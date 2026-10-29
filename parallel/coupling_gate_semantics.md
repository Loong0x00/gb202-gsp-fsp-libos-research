# GB202 reset-coupling PLM gate 与 FSP 分流边界

## 结论先行

这次交叉审计把 `devicePriBase+0x308/+0x30c/+0x310` 的 `bit4` 语义
缩窄到了可以正式命名、但仍需保留寄存器私有命名边界的程度：

1. **FACT（固定 610 GSP）：** 三个 word 的 `bit4` 分别挡在
   `+0x40/+0x44/+0x48.bit0` 写入之前；`bit4=0` 时不执行目标 RMW。
2. **PUBLIC FACT（NVIDIA 610 published PLM layout）：** PLM word 的 `bit4`
   正式字段名是 `WRITE_PROTECTION_LEVEL0`，值 1 正式表示 `ENABLE`。它不是
   MODS 的 network security level 4，也不是“第四级权限”。
3. **V-STATIC（跨固定 GSP 与 MODS RegHal）：** 对这三个 private PMC-relative
   word，最准确的描述是“对应 fuse/boot/base coupling target 的 PRI access-mask /
   PLM word”。MODS 的 `0xfffe` access-metadata rows 恰好给出同三 offset，且
   direct-access helper 把读出的 word 按标准 PLM 位布局解释。
4. **仍不是 PUBLIC FACT：** 公开 610 的 GB202 published headers 没有发布这三只
   coupling 寄存器及其 PLM 的正式宏名。因此不能凭现有材料伪造类似
   `NV_PMC_*RESET_COUPLING*_PRIV_LEVEL_MASK` 的具体符号名。
5. **PUBLIC FACT / V-STATIC：** 固定 GSP 在 gate 关闭或写后 `bit0` 仍为 0 时均
   形成 `0x40`；公开 `nvstatuscodes.h` 将 `0x40` 定义为
   `NV_ERR_INVALID_STATE`。它不是 `NV_ERR_INSUFFICIENT_PERMISSIONS`，而且单看
   返回码无法区分“gate 关闭”和“写入未生效”。gate 失败路径还经过 assert /
   条件 `ebreak`，所以不能把它当成无害的权限探针。
6. **FACT（MODS 570）：** 所谓 FSP fallback 不是在 direct write 已经失败后重试。
   MODS 在写入前计算每个 target 的 `HasRWAccess` 式谓词，然后二选一：权限谓词
   全满足就只走 direct；缺任一所需权限就只走 FSP task 4/subobject 1。direct
   写后验证失败不会再转 FSP，FSP 失败也不会回头 direct。
7. **重要版本边界：** 固定 610 GSP setter 自身没有 FSP fallback；下面的自动
   分流来自另一个静态样本 MODS 570.151。两者对相同 PLM offset/target 的吻合是
   很强的语义交叉证据，但不能把两个程序拼成一个实际调用栈。

## 范围、样本与安全边界

- 固定 GSP inner ELF：`/tmp/gsp_inner_19f040_a.elf`
  - size `82,577,496`
  - SHA-256
    `bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`
  - bounded windows：`0x1084508..0x1084740`、
    `0x109300c..0x1093200`
- MODS executable：`mods_audit/static/extracted_inner/mods`
  - size `392,339,552`
  - SHA-256
    `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`
  - bounded windows：`0x126d4e0..0x126db00`、
    `0x126db90..0x126dca2`、`0x1857b10..0x1857ba6`、
    `0x185e0e0..0x185e55c`、`0x198a7e0..0x198a9f8`
- published source：`/usr/src/nvidia-610.43.03/src`

只读取了本地文件并做有限窗口反汇编、RegHal table 离线解码和公开头文件交叉。
没有运行 MODS，没有打开 `/dev/nvidia*`，没有访问 GPU/MMIO，没有 reset、驱动
操作或固件执行。

本文使用：

- **FACT：** 固定样本的指令/表项直接证明；
- **PUBLIC FACT：** NVIDIA 公开 610 C/header 直接定义；
- **V-STATIC：** 两个固定私有 artifact 与公开 layout 互相闭合，但缺目标寄存器
  的公开符号；
- **INFERENCE / UNKNOWN：** 证据不足以升级为正式名称或运行时事实。

## 1. 固定 GSP 的三个 gate 是同一结构

固定 GSP 的两个 setter window 已闭合为：

| selector | gate word | 检查 | target | 动作 |
|---:|---:|---:|---:|---|
| `4` | `devicePriBase+0x308` | `word & 0x10` | `devicePriBase+0x40` | `OR bit0` |
| `5` | `devicePriBase+0x30c` | `word & 0x10` | `devicePriBase+0x44` | `OR bit0` |
| `8` | `devicePriBase+0x310` | `word & 0x10` | `devicePriBase+0x48` | `OR bit0` |

selector `4/5` 位于 `0x1084508`，selector `8` 位于 `0x109300c`；后者对非 8
输入 tail-call 前者。三个分支均先用同一 device-info tuple
`(type=0x2a, index=3, runlist=-1, internal=0)` 取 entry，从 `entry+0x10` 取得
`devicePriBase`，再通过 `pGpu+0xb98` aperture 读取相对寄存器。

每路顺序均为：

```text
read32(gate)
if ((gate & BIT(4)) == 0): assert/report; intended status = 0x40
read32(target)
write32(target, old | BIT(0))
fixed rdtime delay
read32(target)
status = target.bit0 ? 0 : 0x40
```

因此下列行为是 **FACT**：

- gate 是写前资格检查，不是 coupling 当前状态本身；
- target `bit0` 才是被置位并回读的状态；
- gate 关闭时没有 target store；
- gate 通过仍不保证成功，写后 readback 可产生同一个 `0x40`；
- bounded setter 内没有 FSP sender、第二 backend 或 retry-after-failure。

selector `4/5/8` 与公开 BIF reset type
`BOOT_DEVICE_FUSE/BOOT_DEVICE/BASE` 数值相同；结合 MODS 的 reset 状态机，项目
目前把 `+0x40/+0x44/+0x48` 分别校准为 fuse/boot/base coupling。这里沿用
**V-STATIC**，不把 stripped GSP 的私有 selector 名称冒充公开符号。

## 2. `bit4` 可以正式命名为 L0 write-enable

### 2.1 Blackwell 公开 header 的直接定义

公开 Blackwell GB100 `dev_gsp.h:60-66` 明确定义同一 PLM 位布局：

```text
READ_PROTECTION_LEVEL0       0:0
WRITE_PROTECTION_LEVEL0      4:4
..._LEVEL0_ENABLE            1
..._LEVEL0_DISABLE           0
```

公开 `kernel_gsp_gb100.c:56-59` 同时测试 read L0 和 write L0；紧邻注释
`:78-80` 直接说这是等待 GSP “lower PLM to allow RM reset access”。公开
`timer_gv100.c` 也用 `WRITE_PROTECTION_LEVEL0_ENABLE` 判断 RM 是否能写 PTIMER，
并把失败打印为 “Level 0 PLM is disabled”。

所以对一个符合 NVIDIA 标准 PLM layout 的 word：

```text
bit4 == 1  <=>  WRITE_PROTECTION_LEVEL0_ENABLE
```

是 **PUBLIC FACT**。准确人话是“允许 L0 发起者写”，在公开 RM 的上述用例中 L0
就是 RM 所需访问级别；它不是 MODS 的 `SecurityUnlockLevel=4/5`，也不表示全部
级别 `[7:4]` 都开放。只有 write-protection nibble 为 `0xf` 才能描述为四级都
enabled。

### 2.2 完整 PLM layout 与 MODS helper 恰好吻合

公开 NVIDIA LS10 `dev_falcon_v4.h:27-73` 给出完整扩展 PLM layout：

| bits | 公开字段 |
|---:|---|
| `3:0` | `READ_PROTECTION`（L0..L3） |
| `7:4` | `WRITE_PROTECTION`（L0..L3） |
| `8` | `READ_VIOLATION` |
| `9` | `WRITE_VIOLATION` |
| `10` | `SOURCE_READ_CONTROL` |
| `11` | `SOURCE_WRITE_CONTROL` |
| `31:12` | `SOURCE_ENABLE` vector |

MODS helper `0x198a7e0` 在正常 access-check 路径上对读出的 word 精确计算：

```text
direct_rw_allowed = bit0 & bit4
                  & (!bit10 | bit12)
                  & (!bit11 | bit12)
```

按公开 layout，它等价于：

```text
L0 read enabled
AND L0 write enabled
AND (source-read control lowered OR source-enable[0])
AND (source-write control lowered OR source-enable[0])
```

公开 header 没有在这里给 `SOURCE_ENABLE[0]` 发布具体 requester 名称，因此不能
把 bit12 再武断叫成 CPU、GSP 或某个 engine；“source-enable vector 的最低位”
是当前可正式支持的上限。

另一个必要边界是：固定 GSP setter **只检查 bit4**；上述 bit0/bit10/bit11/
bit12 组合是 MODS 的 full-RW eligibility helper，不能倒灌成 GSP window 中没有
的条件。反过来，GSP 看见 bit4=1 也不等价于 MODS 一定选择 direct backend。

`0x198a7e0` 还存在 policy short-circuit：access metadata lookup 不存在，或
RegHal backend/vtable policy 表示不做当前 privilege check 时，它可直接返回 true，
不进入上面的 PLM 公式。解码 JS 确实暴露 `-reg_priv_check ->
JsRegHal.RegPrivCheckMode`，但本次没有建立目标运行时 mode。对这里三个 descriptor，
GB202 table 的 `0xfffe` metadata 都真实存在；因此普通 checking-enabled 路径会
进入公式。后文所谓“direct-access 谓词”严格指 helper 的最终 bool，而不是保证
每次都等于裸 PLM 的四项逻辑式。即便软件 policy 跳过检查，真实硬件仍可能拒绝
写入；这不是安全的权限绕过手段。

## 3. 为什么能称为“对应 coupling target 的 PLM word”

MODS GB202 RegHal table 对三个 direct-access descriptor 的离线结果为：

```text
ID 0x12d6c000  domain 0x31  normal offset +0x40  access row +0x308
ID 0x12d68000  domain 0x31  normal offset +0x44  access row +0x30c
ID 0x12d64000  domain 0x31  normal offset +0x48  access row +0x310
```

这里 `index0=0xfffe` 的 row 被 `RegHal_AccessOffset` 形状的 lookup 使用，返回的
offset 随后由 `0x198a7e0` 读成上节 PLM word；ordinary row 则给出实际 target
offset。固定 GSP 又独立形成完全相同的三组 gate/target pair：

```text
+0x308 -> +0x40
+0x30c -> +0x44
+0x310 -> +0x48
```

因此“这三只 gate word 是三个 coupling target 的 access-mask/PLM metadata”是
**V-STATIC**，不再只是相邻地址猜测。

但公开 610 的 `published/blackwell/gb202/` 目录没有 `dev_pmc.h`，现有
`dev_boot_zb.h` 也没有发布这些 offset 或字段。故以下层次必须分开：

- `bit4 = WRITE_PROTECTION_LEVEL0_ENABLE`：**PUBLIC FACT（通用 PLM layout）**；
- `+0x308/+0x30c/+0x310` 分别配对 fuse/boot/base target：
  **V-STATIC（固定 artifact）**；
- 三只 private register 的 NVIDIA 正式宏名：**UNKNOWN / unpublished**。

## 4. gate 失败的 `0x40` 到底是什么

公开 `common/sdk/nvidia/inc/nvstatuscodes.h:93`：

```text
NV_ERR_INVALID_STATE = 0x00000040
```

同一文件把权限不足与 PRIV security violation 分别定义为：

```text
NV_ERR_INSUFFICIENT_PERMISSIONS = 0x1b
NV_ERR_PRIV_SEC_VIOLATION       = 0x6b
```

因此固定 GSP 的 `0x40` 应正式解释为 **invalid state**，而不是一个精确的
permission-denied code。更重要的是，三个 setter 都把两种失败压成同值：

1. PLM `WRITE_PROTECTION_LEVEL0` 未 enable；
2. target RMW 已发出，但 delayed readback 的 `bit0` 仍为 0。

caller 若只收到 `0x40`，无法知道是哪一种。selector 不支持则另返 `0x56`
（公开名 `NV_ERR_NOT_SUPPORTED`），device-entry helper 的非零状态则原样传播。

gate=false 分支在设置 `0x40` 之前经过两次 report/assert plumbing，并在某个全局
条件为假时执行 `ebreak`。因此“若 assert 路径继续执行，返回 0x40”是精确说法；
不能保证所有 build/runtime 配置下都只做普通返回。这也是它不适合作为实机
只读探针的直接原因。

## 5. MODS 的 direct/FSP 分流是预选，不是失败重试

MODS `GpuSubdevice+0x3a0 = 0x126d4e0` 先读取当前 fuse/boot/base coupling，
再分别对 `0x12d6c000/0x12d68000/0x12d64000` 调用上面的 access helper。
随后按请求 state 分流：

| state | 逻辑前置条件 | 选择 direct 所需的 access 谓词 | direct 动作 | 谓词不全时 |
|---:|---|---|---|---|
| `5 boot` | 当前 fuse=0 且 base=0 | fuse、boot、base 三项全 true | boot=1, fuse=0, base=0 | FSP state 5 |
| `6 fuse` | 当前 base=0 | fuse、base 两项全 true | fuse=1, base=0；boot 不改 | FSP state 6 |
| `7 base` | 无更高 coupling 前置冲突 | base 为 true | base=1 | FSP state 7 |
| `3 hot` | 当前三项必须全为 0 | 三项全 true | 三项冗余写 0 | 尝试 FSP state 3，但下层拒绝该 option |

这张表解释了为什么 boot direct 要求三只 PLM，而 fuse direct 只要求两只：代码
确实会写/确认对应的完整目标组合，不只是置目标层的一个 bit。

### 5.1 不会触发 FSP 的失败

- boot 请求遇到当前 fuse/base 已 coupled：立即日志并返回 raw MODS code `3`；
- fuse 请求遇到当前 base 已 coupled：立即日志并返回 `3`；
- hot 请求遇到任一 coupling：立即日志并返回 `3`，不会帮调用者清零；
- 不支持的 state：返回 `0x308`；
- direct 分支写后组合验证失败：打印
  `Could not set up reset coupling bits (via MODS) as expected`，返回 `0xb6`；
  **不再转 FSP**。

所以 FSP 不是 logical-conflict、invalid state 或 direct readback failure 的兜底。

### 5.2 真正进入 FSP 的条件与 payload

只有逻辑前置条件已满足、但该 state 所需的 direct-access 谓词至少一个为 false，
才调用 `GpuSubdevice+0x1100 = 0x126db90`。

`+0x1100` 只接受 state `5/6/7`，用 `state-5` 查单字节表：

```text
state 5 boot -> payload byte 1
state 6 fuse -> payload byte 0
state 7 base -> payload byte 2
```

然后同步调用 common sender：

```text
task = 4
subobject = 1
payload = one byte above
```

state 3 或其他 state 不发送 task，打印 unsupported option 并返回 `0x308`。
正常 generic mapper 在三项已经全 0 时会令 hot descriptor 的 `needCoupling=0`，
dispatcher 会跳过 setter；因此“hot -> FSP state3 -> rejected”主要是 setter 被
直接调用时的防御分支，不是 normal hot request 的常规流量。

### 5.3 FSP 自己还有两层门

common sender `0x185e260` 先检查 feature `0xdb`；现有静态交叉把它对齐为
`GPUSUB_SUPPORTS_FSP`。task 4 分支随后用 `0x185e0e0(4)` 检查 QCAP；mapper
`0x1857b10` 将 task 4 映射到 key `0x13`。公开 610
`nvdm_format.h:46` 把 `0x13` 定义为 `NVDM_TYPE_PRC`。

QCAP 不存在或尚未 active 时：

```text
"Reset coupling isn't supported by FSP or is not yet active"
raw MODS return = 0x12d
```

通过后才发送 packet 并进入 transport 的 response-completion/parse；任一 send、
poll、response 或 firmware error 原样阻止后续成功验证。FSP 返回零后，外层仍
重新读取 coupling 组合；若不符合请求状态，返回同一个 `0xb6`，日志来源标成
`FSP`。这里同样没有“FSP 失败后试 direct”的逆向 fallback。

## 6. 两个 artifact 不能被错误拼接

可以安全合并的结论是：

- 两边独立使用相同的三个 access/target offset pair；
- PLM bit4 的标准语义是 L0 write enable；
- MODS 把这些 access words 用于写前 backend 选择；
- fixed GSP setter 把 bit4 用于写前拒绝。

不能合并成事实的是：

- **不能说** fixed GSP 返回 `0x40` 后会自动让 MODS/FSP 接手；没有这种调用链；
- **不能说** bit4=1 就足以让 MODS direct，因为 MODS 还检查 L0 read 与 source
  controls；
- **不能说** bit4=0 就说明 coupling target 不存在；它只说明 L0 direct write
  gate 没开放；
- **不能说** FSP task 4 会“永久降低 PLM”；它是在另一路固件 backend 中请求
  coupling，host 看不到 FSP consumer 的内部寄存器动作与生命周期；
- **不能从静态文件推出** 目标 RTX 5090 当前三只 PLM/coupling 的值。

## 7. 最终证据矩阵

| 问题 | 结论 | 等级 |
|---|---|---|
| gate `bit4` 的标准字段 | `WRITE_PROTECTION_LEVEL0` | **PUBLIC FACT** |
| `bit4=1` 的含义 | L0 write enable；不是 security level 4 | **PUBLIC FACT** |
| 三 gate 是否为 access/PLM words | 与 MODS `0xfffe` access rows、PLM helper 完全吻合 | **V-STATIC** |
| private coupling PLM 正式宏名 | 公开 GB202 headers 未发布 | **UNKNOWN** |
| GSP gate=false 的继续返回值 | `0x40 = NV_ERR_INVALID_STATE` | **FACT / PUBLIC FACT** |
| `0x40` 能否区分 gate 与 readback failure | 不能 | **FACT** |
| gate=false 是否保证无 trap | 否；存在 assert/条件 `ebreak` | **FACT** |
| fixed GSP setter 内是否有 FSP fallback | 没有 | **FACT（bounded window）** |
| MODS 何时选 FSP | 写前所需 direct-access 谓词至少一项 false，且逻辑前置条件已满足 | **FACT** |
| direct 失败后是否再 FSP | 否 | **FACT** |
| FSP 失败后是否再 direct | 否 | **FACT** |
| FSP request | task 4 / subobject 1；boot/fuse/base payload `1/0/2` | **FACT** |
| FSP capability family | task 4 -> QCAP `0x13`; public `0x13=NVDM_TYPE_PRC` | **FACT / PUBLIC FACT** |
| FSP 内部如何改寄存器、何时恢复 | host artifact 不可见 | **UNKNOWN** |

最简洁的人话结论是：这三只 `bit4` 的确是“允许普通 RM/MODS 这一侧做 L0
写入”的 PLM 位，而不是某个神秘的网络等级。它们关闭时，原厂 MODS 会在动手
前选择 FSP；它们开放时，MODS 才直接写。但这是一条预先二选一的路径，不是
“随便写，失败了固件再救场”，固定 GSP setter 本身甚至没有这个救场分支。

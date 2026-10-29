# MODS 570.151 software-shadow：reset / resense 可见生命周期审计

Status: **final, bounded static-only**
Date: 2026-07-21

## 范围与证据口径

本轮只读取本地材料：MODS 570.151 已提取 ELF、已解码 JavaScript、既有有限窗口
报告、当前 610.43.03 OpenRM 源码，以及来源已归档的 610 GSP inner ELF。没有运行
MODS，没有访问 GPU、设备节点、PCI/BAR/MMIO 或网络，也没有执行 reset、驱动/
模块/固件操作。没有做新的 whole-section scan 或 Ghidra 分析；新增检查仅限已知
函数地址的小窗口。

主要 artifact：

- `mods_audit/static/extracted_inner/mods`，SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- `/tmp/gsp_inner_19f040_a.elf`，SHA-256
  `bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`，
  来源见 `parallel/GSP_ARTIFACT_PROVENANCE.md`；
- `/usr/src/nvidia-610.43.03/src`；
- `mods_audit/static/decoded/all/gpuargs.js`。

本文严格分为：

- **FACT**：文件、明确地址的小窗口或当前公开源码直接支持；
- **INFERENCE**：由多项 FACT 支持的设计语义，但硬件/FSP consumer 不可见；
- **UNKNOWN**：当前静态材料不能决定。

## 直接答案

1. **成功 reset 后 shadow 是否“预期”保留并生效？**
   **INFERENCE（强）：是，原厂 host 流程显然预期如此。** 正常成功路径只在
   reset 前尝试置 latch、写 raw shadow 并回读，随后无条件 reset/reinit；reset
   后既不重放 raw plan，也不另写 effective mask。若 shadow 不能跨越或被 reset
   状态机消费，这条成功路径便无法实现其唯一可见目的。但这不是任何一种 reset
   的硬件保证；实际 latch/raw/effective 是否保留或重新形成仍是 **UNKNOWN**。

2. **哪些 reset 会重新采样实体 fuse？**
   在 `hot/fuse/boot/base` 四类中，只有 **fuse reset** 有直接、当前代 host 语义
   与 physical-resense 相连：`GB20xPrepareResense` 先发 latch-clear coded request，
   再名义上请求 state 6；物理 fuseblow 路径也明确把后续阶段称为
   `Fuse Resense`。另一个 native 日志说新烧写值可能要等 `fuse / cold reset`
   才反映。**hot、boot、base 是否也会在硬件内重新采样实体 fuse，当前材料没有
   证明；尤其不能把 `base reset` 自动等同于日志中的 `cold reset`。**

3. **host 是否验证 post-reset effective state？**
   **FACT：已审计的 `SetSwFuses` 成功尾没有显式验证。** 唯一逐 plan 项比较是
   reset 前的 raw-shadow readback。post-program callback 不携带 plan 值；reset
   返回后上层只检查 reset/reinit status、析构临时 plan 并返回。它没有读取
   `0x822900`，没有调用公开 LTS-mask GET，也没有把 post-reset effective mask 与
   请求值比较。公开 610/GSP 有可用于另行观察 effective topology 的 GET 路径，
   但它不是 direct-shadow success 的自动验收步骤。

4. **“MODS success”有多强？**
   很弱。latch-set call 的返回未检查；raw write 的返回寄存器也未消费；若 raw
   readback 得到 `0xbadf510c` privilege sentinel，只记日志、不置 aggregate error，
   仍可能进入 reset/reinit。因此 success 甚至不严格证明每个 pre-reset raw 项都
   完成普通 equality check，更不能证明 post-reset effective adoption。

## FACT

### 1. 三层状态与消费端是不同对象

当前 GB202 RegHal 解码已经把三个 L2 mask 视图分开：

| 层 | 地址 | 当前可见角色 |
|---|---:|---|
| raw OPT / shadow | `0x8234e0 + 4*FBP` | direct-shadow plan 的目标；read ID `0x1087c000`、write ID `0x2087c000` |
| software disable | `0x822080 + 4*FBP` | 普通 floorsweep host apply 的目标；write ID `0x20360000` |
| current/effective disable | `0x822900 + 4*FBP` | GSP/RM 的 current LTS-disable 视图；read ID `0x10d64000` |

software-override latch 是 `0x820040.bit0`；RegHal constant IDs
`0x404f0001/0x404f0000` 分别编码 bit 1/0。其 access metadata 指向独立 PLM
`0x8200f8`，不能把 latch 与 raw L2 的 `0x8200dc` PLM 混为一物。

当前 GSP 的 GB202 FB constructor replay 把：

```text
FB +0x9b0 = 0x0132ae68   coarse LTC/ROP-L2 status getter
FB +0x9c0 = 0x0132ef40   physical LTS enable-mask getter
```

`0x0132ef40` 通过 Fuse aperture 读取内部 offset `0x2900 + 4*FBP`，即
`0x822900 + 4*FBP`，在拓扑位宽内反转 disable bits 后返回 enable mask。另一条
`0x0132ae68` 读取 `0x0d70 + 4*FBP`，即 `0x820d70 + 4*FBP`。所以“reset 后
RM 可以重新枚举”不等于“host 直接把 raw shadow 当 effective”；中间 rollup
发生在硬件/GFW/Fuse aperture 可见状态中。

### 2. 正常 direct-shadow 成功链

当前 MODS 的可见顺序为：

```text
ProgramSwFusePlan 0x1515ea0
  -> request 0x404f0001                    # latch := 1（return 未检查）
  -> for each raw plan node:
       write through handler +0xb8         # write return 未消费
       read  through handler +0xc0
       compare before reset
  -> aggregate status

SetSwFusesCore 0x14620d0
  -> only if aggregate == 0: vtable +0x370
MultiMacro post-program 0x146dd30
  -> each accessor +0x90
GB20x post-program 0x1515770
  -> handler +0x100 -> reset/reinitialize
```

关键数据流事实：

- `0x1515ed8..0x1515eea` 发 latch-set coded request，随后直接进入计划循环；
- raw write/readback 在 `0x1515f50..0x15160a7`，全部发生在 post-program 之前；
- 两条实际 core 成功分支分别在 `0x146223c`、`0x14623f9` 调用 `+0x370`；
- `0x146dd30..0x146dd80` 调 accessor `+0x90` 时只传 accessor 本身，没有传
  `(offset, expected raw/effective)` plan；
- `0x1515770..0x1515786` 只进入 reset callback；它没有 raw/effective 读写；
- reset 返回后，`SetSwFusesCore` 在 `0x1462245..0x146224f` 只测试 status 并
  cleanup；外层 `NewFuse::SetSwFuses` 在 `0x14646f1..0x1464720` 只保存返回码、
  析构临时对象并返回，没有 post-reset getter/compare。

正常 success tail 和 programming-error tail 都没有调用 resense slot `+0x88`，
也没有发 `0x404f0000`。reset/reinit 内部也没有收到 raw plan 作为显式参数。

### 3. 实际 reset 类型由既有 coupling 选择

post-program 不是固定 boot reset。`0xdff7b0` 以 request 2 调 GB202 mapper
`0x126b360`；mapper 读取 boot/fuse/base coupling，并按以下优先级产生 RM state：

```text
base coupling = 1 -> state 7, base
else fuse = 1    -> state 6, fuse
else boot = 1    -> state 5, boot
else             -> state 3, hot
```

request-2 分支 `0x126b430..0x126b4a6` 把 descriptor 的“补设 coupling”byte 固定
为 0。因此正常 direct-shadow 是“沿用既有 coupling 后 reset”，不是先为本次
shadow commit 建立某个特定 reset level。

后续固定 610 GSP 审计还证明，公开
`NV2080_CTRL_CMD_GPU_IS_RESET_COUPLED` 并不是上述三个 mapper 输入的完整
汇总：GB202 物理 getter 直接读取的是 fuse `+0x40` OR boot `+0x44`，没有直接
读取 base `+0x48`。因此即使未来取得一个可靠的 false，也不能在 base 的级联/
镜像关系未闭合时据此选择 hot 分支。固定 GSP 的 selector-8 setter 和 type-8
dispatcher 已排除可见软件镜像，但硬件/reset-sequencer/FSP/GFW 级联仍未知；
证据见 `parallel/reset_getter_guard_provenance.md` 与
`parallel/base_coupling_visibility.md`。

`mods_audit/static/decoded/all/gpuargs.js:755-762` 同时公开了四个独立名字；其中
`HotReset` 的说明明确是 secondary-bus reset。610 公开头
`ctrl0080bif.h:37-76` 也把 SBR、`BOOT_DEVICE_FUSE`、`BOOT_DEVICE`、`BASE`
定义为不同 BIF reset type；当前 GSP 的 `NV0080_CTRL_CMD_BIF_RESET` handler
`0x01066260` 对 type 4/5/8 分别有独立分支（`0x0106653c`、`0x0106656a`、
`0x0106661a`）。这证明 reset taxonomy 确实不同，但公开头没有给出 latch/raw
寄存器的逐 type reset-domain 表。

一次正常 reset/reinit 成功后，`0x127b000` 才检查 recovery-mode property；只有
该 property 为真才发第二次 reset。第二次是 recovery fallback，不是 shadow 的
两阶段提交，也没有 effective compare。

### 4. 四种 reset 的可见边界

下表的“未见”都严格限当前 host/GSP 小窗口；不表示硬件绝无隐式动作。

| RM state | 选择条件 | 正常 `SetSwFuses` 尾的显式 latch/raw 动作 | 实体 fuse resense 证据 | post-reset effective 验收 |
|---|---|---|---|---|
| `3 hot` | 三种 coupling 均为 0 | 不 clear latch；不 replay raw | 未见；JS 只确认其为 SBR | 无 |
| `5 boot` | boot=1 且 fuse/base=0 | 不 clear latch；不 replay raw | 未见；公开接口将 `BOOT_DEVICE` 与 `BOOT_DEVICE_FUSE` 分开 | 无 |
| `6 fuse` | fuse=1 且 base=0 | 正常 writer 仍不 clear latch；不 replay raw | **有名义/设计证据**：resense path 请求 state 6，physical-fusing mode 2 称 `Fuse Resense` | 无 |
| `7 base` | base=1，最高优先级 | 不 clear latch；不 replay raw | 未见；存在独立 `BASE` reset type，但没有等同 cold/resense 的公开说明 | 无 |

因此可证的是 reset 选择与 host 动作，不是各 reset domain 对三只寄存器的硅级
保持规则。

### 5. 显式 resense 与正常 post-program 是两条不同路径

`GB20xPrepareResense` 的 accessor slot 是 `+0x88`，函数窗口
`0x1516e20..0x1516f91`；正常 post-program 是相邻但不同的 `+0x90 = 0x1515770`。
resense 可见顺序为：

```text
request reset coupling state 6 via handler +0xf8
  -> nonzero: log "Can't couple resets for resensing", but continue
request 0x404f0000 via handler +0x78
  -> return immediately overwritten; no readback
if preparation status == 0 and platform is not pre-silicon:
  -> handler +0x100 -> coupling-selected reset/reinit
else if pre-silicon:
  -> log and skip fuse reset
```

这里还有两个必须保留的限制：

- 传给 `+0x100` 的整数 6 会被 thunk `0x151ad50` 丢弃；最终仍由 mapper 观察到的
  coupling 决定。只有当时 base=0、fuse=1 才真的选 state 6；
- coupling request 和 latch-clear request 都不是 fail-closed，因此一次 resense
  API 返回路径本身不能证明 latch 已清或实体 fuse 已重新采用。

物理 FSP fuseblow 协调器 `0x1249960` 的 mode 2 日志为
`Performing a Fuse Resense after Fsp Fuseblow`，并在 `0x1249a70..0x1249a81`
进入 reset callback。另一个只属于 physical-fusing state machine 的日志说明，
若跳过 reset，新 fuse 值可能要等 `fuse / cold reset` 才反映。它直接支持
“fuse/cold reset 是实体 fuse 反映边界”的软件预期；它不证明 boot/hot/base 的
采样规则，也不把 physical fuseblow 的 reset 前提移植给 direct shadow。

### 6. post-reset host 验证缺失

可见 success tail 验证的是：

1. reset 前 ordinary raw readback 是否等于 plan value；
2. aggregate writer status 是否为 0；
3. reset/reinit callback 是否返回 0。

它没有验证：

- latch 在 reset 后是否仍为 1；
- `0x8234e0 + 4*FBP` 在 reset 后的 raw-shadow 值；
- `0x822900 + 4*FBP` 的 current/effective 值；
- GSP `0x820d70 + 4*FBP` status 是否与请求拓扑一致；
- L2 size/count 或 `NV2080_CTRL_FB_FS_INFO_LTS_MASK` 是否符合预期。

公开 610 的 `NV2080_CTRL_CMD_FB_GET_FS_INFO (0x20801346)` 确实支持 query type
`NV2080_CTRL_FB_FS_INFO_LTS_MASK (3)`，返回按 FBP flatten 的 `ltsEnMask`
（`ctrl2080fb.h:2021-2033,2284-2359`；generated dispatch
`g_subdevice_nvoc.c:10201-10213`）。它说明**存在另行观察 active/effective topology
的接口面**，不说明 target 必然支持，也不说明 MODS success tail 调用了它。本轮
没有发出该 control。

610 的 GB202 FSP 源码还明确说 Bootfsm 在 chip reset 后触发 FSP 执行，host
等待 boot-complete scratch（`kern_fsp_gb202.c:50-85`）。这证明 reset/reinit 会
经过真实 firmware boot 边界；它没有公布 fuse-sense consumer，也没有返回
shadow/effective equality 结果。

## INFERENCE

### 1. 正常成功路径的设计意图是保留/消费 shadow，而不是清回实体 fuse

这是强推断，理由是：

- writer 先尝试 latch=1，再写 raw shadow；
- 只有 aggregate success 才进入 reset/reinit；
- reset 后不重放 raw plan，也不直接写 effective；
- 另有专门 resense path 在 reset **之前**显式尝试 latch=0。

因此最自洽的设计是：在合法 reset/coupling 条件下，latch/raw shadow 要么跨 reset
保持，要么被 reset 硬件消费并重新形成 fuse-status/effective 视图。正常
post-program 并不打算撤销 shadow。

这项推断只描述 NVIDIA host 算法的预期，不把一次返回 0 升级成实卡证明。特别是
privilege sentinel 可漏记错误，且 latch call 根本没有 checked acknowledgement。

后续独立 GSP 数据流审计补上了这个负结论的另一半：固定 GSP 中存在 raw A
`0x8234e0+4*FBP` 与 effective B `0x822900+4*FBP` 的独立读取 wrapper。原先
误归为“可形成 B 类地址”的 `0x15d3a98` 已证明是 GH100 Ioctrl/MINION
NVLink EOM sender，GB202 对应槽位为 stub，故不属于 B writer；已审计 bounded
范围内仍没有“A 值流入 B write”的 copy/recompute。故可见时序只能写成
“reset 前 host 写 A -> 不可见 reset/sense/FSP-GFW/hardware 边界 -> init 后
GSP 读 B”。这排除显眼的软件 copier，不证明硬件自动 rollup。完整证据见
`parallel/raw_effective_propagation.md`。

### 2. effective 更像 reset/reinit 后重新形成的派生状态，不是需要原值“保持”的配置

当前可见 host writer 只改 raw shadow；普通 floorsweep 只改 software mask；GSP
随后从 Fuse aperture 读取 current/effective/status。没有发现 host 在重载时把
`0x822900` 回写成固定 SKU 值。因此更合理的生命周期是：

```text
(latch policy, raw OPT/shadow, software-disable, physical fuse/other policy)
                    -> reset 边沿下的未知 rollup/rebuild/replay
                    -> status/effective registers
                    -> RM/GSP topology consumers
```

这里“重新形成/rollup”是推断，因为真正 consumer 位于不可见硬件/FSP/GFW
阶段；不能把该图当作已知逻辑公式或 bit-for-bit 优先级证明。

### 3. fuse reset 与 resense 不能只按名称等同

显式 resense 在 fuse-oriented reset 前先清 latch，说明“让实体 fuse 重新成为
有效来源”至少在 host 设计上依赖 **clear latch + reset** 的组合，而不是看见
state 6 就自动得出 shadow 已消失。

因此，正常 `SetSwFuses` 若因既有 coupling 选到 state 6，但没有 clear latch，
最合理的解释是：硬件可以重新 sense physical fuse，同时仍由 active override
覆盖/合并成 shadow 结果。raw storage 是保持、被复制，还是由另一 always-on
状态重建，当前看不见；只可推断“normal state-6 success 不应自动等同 resense”。

### 4. 权限恢复与 shadow 数据寿命是两件事

FSP/task-2/HULK 可能在 reset 时关闭 `0x8200dc/0x8200f8` 的写权限；即使如此，
已接受的 latch/raw 数据仍可能保持并继续决定 effective。相反，PLM 暂时开放也
不证明 shadow 已被接受。当前没有证据把 permission lifetime 与 latch/raw
lifetime 绑定成同一个状态变量。

## UNKNOWN

1. `0x820040.bit0`、`0x8234e0..0x8234fc`、`0x822900..0x82293c` 分别属于哪些
   hot/boot/fuse/base reset domain；任何一种 reset 是否会隐式 clear、retain、
   reload 或重新计算它们。
2. normal post-program 在实际零售 GB202 上选中的 reset 类型；公开
   `IS_RESET_COUPLED` 已静态证明绑定状态感知 getter，但直接只读 fuse OR boot，
   不读 base；历史结果又未归档，仍不能给出当前三项或最终类型。
3. `base reset` 是否包含 fuse/cold-reset 语义。现有公开枚举把 `BASE`、
   `BOOT_DEVICE_FUSE`、`BOOT_DEVICE` 分列，没有层级/包含关系说明。
4. hot 或 boot reset 是否也会重新采样实体 fuse；名称和“没有显式 clear”都不足
   以证明硅级行为。
5. fuse reset 在 latch 仍为 1 时，raw shadow 是物理保持、sense 后重新覆盖、还是
   由其他状态恢复；只知道 normal path 不主动 clear/replay。
6. resense 中 coupling 和 latch-clear 请求是否真正成功。两者的错误处理不足以
   给出保证；final mapper 也可能选到 hot/boot/base。
7. reset/reinit 内部是否做了某种通用拓扑自洽检查。即使存在，也没有证据表明它
   把 `SetSwFuses` 的期望 plan 与 post-reset `0x822900` 逐项比较。
8. raw shadow 到 `0x820d70` status、`0x822900` effective 以及最终容量/count 的
   精确传播、优先级和失败状态。
9. 一次 `SetSwFuses` 返回 0 后，本卡 latch/raw/effective 的实际值与被启用单元
   健康性；本轮没有任何 live observation。

## 最小可引用结论

> MODS 570.151 的 GB20x direct-shadow 成功路径在 reset 前尝试置
> `0x820040.bit0`、写并回读 raw OPT shadow，随后沿用既有 coupling 选择
> hot/boot/fuse/base reset 并重建 RM 状态；正常尾不清 latch、不重放 raw，也不
> 比较 post-reset `0x822900` effective mask。这个控制流强烈表明 shadow 被预期
> 跨 reset 保留或由 reset 状态机消费后生效，但当前静态材料没有给出四种 reset
> 的寄存器保持表，因而不能把预期写成硬件保证。显式实体-fuse resense 的当前
> host 语义是“尝试 fuse coupling、尝试 clear latch、再条件 reset”；只有 fuse
> （以及另一路径日志中的 cold）reset 有明确 physical-resense 语义，hot/boot/base
> 是否也重采样仍未知。`SetSwFuses` 的 success status 不是 post-reset effective
> state 的验收证明。

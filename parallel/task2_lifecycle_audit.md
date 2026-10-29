# GB202 / MODS 570.151：task 2/subobject 1 生命周期静态审计

Status: **final, static-only；已内联 GSP `f8` 绑定纠错**
Date: 2026-07-21

## 范围、材料与证据口径

本轮只读本地 610.43.03 源码、MODS 570.151 已提取文件、既有静态报告和已提取
GSP 固件。没有访问 GPU、设备节点、BAR/MMIO、PCI config 或 debugfs；没有执行
MODS、诊断程序或固件；没有 reset、驱动/模块操作、提权或任何设备状态变更。

主要材料：

- `mods_audit/static/extracted_inner/mods`：ELF64 x86-64，size
  `392339552`，SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
  `.text` VA `0x4a0940`、file offset `0x0a0940`、size `0x8736b3a`；
- 解码 JS：`mods_audit/static/decoded/all/gpuargs.js`；
- 610.43.03 OpenRM：`/usr/src/nvidia-610.43.03/src/nvidia`；
- 当前 GSP inner ELF 的来源记录：`parallel/GSP_ARTIFACT_PROVENANCE.md`；
- 已有 GSP/FSP/f8 有限窗口审计：`parallel/gsp_f8_hulk_audit.md`；
- 交叉报告：`parallel/tmux_mods_permissions.md`、
  `parallel/mods_final_crosscheck.md`、`parallel/evidence_audit.md`、
  `parallel/gb202_610_arch.md` 和 `L2_REENABLE_STATIC_FINDINGS.md`。

下文只使用三个结论等级：

- **FACT**：当前文件、限定反汇编窗口或明确注明范围的负扫描直接支持；
- **INFERENCE**：事实共同支持，但缺少 GB202 FSP consumer/运行状态等直接证据；
- **UNKNOWN**：当前材料不能回答。

负结果均严格限定在所列 host/GSP 路径或扫描模式，不能改写成“固件或硬件绝不
存在该行为”。

## 结论摘要

| 问题 | 判定 | 等级 |
|---|---|---|
| task 2 的正常 host 顺序 | 可选 PRC map 处理在前；首次 eligible FS 调用中，task `2`/subobject `1` 的发送及响应状态返回在 pending host apply 之前 | **FACT** |
| 是否同步等待 | common sender 先经 transport `+0x38` 发送，再经 `+0x30` 的 response-completion 路径等待/解析；非零状态阻止 host apply | **FACT（host 同步边界）** |
| 成功返回是否证明 PLM 已降低且仍开放 | 只证明 QCAP `0x13` presence gate 已通过且 transport/FSP command status 为零；没有状态快照或授权 token | **FACT（F1/F2）/ UNKNOWN（D）** |
| 正常路径是否有第二次 close/restore | `+0x520` 返回后未见第二条 task-2、逆向参数、undo handle 或显式 d0/dc/f8 restore；`+0x488` 在 `SkipFspFs=0` 时为 no-op | **FACT（可见 host 路径负结果）** |
| FSP 是否可能自动收权 | host/GSP 可见材料不能排除按 ack、首写、计时、阶段、reset 或内部状态机收权 | **UNKNOWN** |
| PRC knob `0x1d` 与 task 2 | `0x1d` 是独立的 task `13`/submessage `2` PRC 写事务，位于 FS/task 2 之前；两者共享 QCAP key `0x13`，但 host 不会把 `0x1d` 自动嵌入 task 2 | **FACT** |
| `0x1d` 是否被 task 2 消费/自清 | 名称和顺序支持 one-shot permission-preparation 解释，但值、必需性、消费点和自清时机不可见 | **INFERENCE / UNKNOWN** |
| task 2 与 `0x8200d0/dc` | Hopper 同槽 precheck 与 `SkipFspFs` 校验均只检查 d0/dc；结合 GB20x send-before-apply，强支持其为 d0/dc floorsweep PLM 准备权限 | **INFERENCE（较强）** |
| task 2 与 `0x8200f8` | task-2 precheck 不检查 f8；当前 host/GSP 未见 task-2 f8 setter；只有旧 GV100 secure-PMU 历史先例 | **UNKNOWN** |

## 1. 正常 GB20x host 生命周期

### 1.1 总顺序

在普通 FSP-enabled、`SkipFspFs=0`、FS 对象尚未 initialized 且所有前置调用成功的
限定路径中，host 可见顺序为：

```text
Gpu::Initialize
  -> prefetch all FSP QCAPS                    0xda3654
  -> optional PRC read map                     0xda39d2
  -> optional PRC write map                    0xda39f8
       -> read current knob
       -> if different: task 13/submessage 2
       -> read back and compare
  -> JS ProcessFloorsweepingArgs               0xda3b80
  -> GB20xFs::Apply wrapper                     0x106fec0
  -> generic FS dispatcher                     0x1095e50
       -> derive doFsp
       -> prerequisite +0x480                  0x10960a8
       -> GB20xFs +0x520                        0x10960cc
            -> task 2/subobject 1 send+wait     0x106c587 -> 0x185e890
       -> only after zero status:
            pending host apply +0x308           0x1096228..0x1096231
            post hook +0x488                    0x1096234..0x1096243
            set initialized                     0x1095fe5..0x1095ff0
  -> optional post-FS reset +0x3c8              0xda3c91..0xda3cc2
  -> FSP fuse-error/status check +0x448(3)      0xda3cce..0xda3ce2
```

**FACT：** `Gpu::Initialize` 只在 PRC read/write map 非空时分别调用 `+0x340`
和 `+0x338`；两者的返回值一旦非零便直接走错误出口。PRC 处理完成后才进入
`ProcessFloorsweepingArgs`。因此“PRC map -> FS/task 2”是成功 host 路径的严格
相对顺序，不表示每次初始化都配置了 `0x1d`。

**FACT：** `0xda3654` 在上述 PRC map 处理之前以参数 `0xff` 调用
`0x185deb0`，即预取全部 QCAPS。后续 PRC write 与 task 2 使用同一缓存，不存在
“写 `0x1d` 后刷新另一份 task-2 capability”这一 host 步骤。

### 1.2 `doFsp` 的来源，不是 response 返回值

通用 dispatcher `0x1095e50` 的直接控制流为：

- **FACT：** `0x1095e7b` 把本地 `doFsp` byte 初始化为 0；
  `0x1095e80` 把另一个输出 byte 初始化为 1。
- **FACT：** 它读取 JS 属性 `SkipFspFs`，再检查 feature ID `0xdb` 和
  `GpuSubdevice+0x438`（`0x1095ec2..0x1095ee4`）。在该分支成立且
  `SkipFspFs==0` 时，`0x109603d` 才把 `doFsp` 置 1。
- **FACT：** `SkipFspFs==1` 时改走 helper `0x1095cb0`。该 helper 用 RegHal
  read/constant IDs 检查 d0 与 dc；只有两者均处于常量 `0xf` 才把 `doFsp`
  保持/置为 0，否则返回 `0x308`。它没有 setter。
- **FACT：** `0x10960bf` 把这个本地 byte 作为 `+0x520` 的第二参数；因此
  `doFsp` 是 host 在调用前计算的控制值，不是 FSP response、JS payload 字段或
  task 2 返回的授权位。
- **FACT：** GB20x `+0x520 = 0x106c4e0` 在 `0x106c4f1` 直接测试该值；
  `doFsp==0` 跳到 `0x106c5c0` 的 no-send 分支，只有 `doFsp==1` 才调用
  common sender。

`gpuargs.js:403` 把 `g_SkipFspFs` 默认定义为 false；
`gpuargs.js:1667` 的说明是跳过向 FSP 发送 FS PRC packet 并完全在 MODS 内执行
FS。该文字与上述控制流一致。

### 1.3 首次无 floorsweep 参数的特殊生命周期

**FACT：** FS 基类构造器 `0x109a470` 在 `0x109a485` 以一个 word store 同时清零
对象 `+0x10/+0x11` 的两个状态 byte。dispatcher 在 `0x1095f00..0x1095f0e`
读取 initialized；若已置位会直接返回，不再发送 task 2。

**FACT（constructor 与既有完整 data-flow 交叉）：** 对首次、无 FS 参数、正常
FSP 路径，pending 为 0 但 initialized 也为 0，所以 dispatcher 仍到达 `+0x520`
并发送 task 2；成功后 pending=0 使
`+0x308` host apply 被跳过，`+0x3d0(true)` 再把 initialized 置位。外层请求汇总
为 0，因而 `0xda3cba` 的 post-FS reset 被跳过。

**FACT：** 后续走同一 generic dispatcher 的重复调用会被 initialized gate 提前
返回；可见 host 流程没有在第二次 generic 调用中自动配对一个 close 消息。

**INFERENCE：** 这构成“首次 task-2 成功返回后，host 不 apply、不 reset，便返回
上层”的静态 host control-flow interval；它不是已证明的 permission window。

**UNKNOWN：** 该 interval 内 d0/dc/f8 的实际值、FSP 是否已经自动收权，以及后续
另一路径是否仍被允许，均不能由 pending/initialized 两个 host byte 推出。

## 2. task 2 的发送与同步响应边界

### 2.1 精确实参与状态传播

GB20x `+0x520` 的关键调用位于 `0x106c570..0x106c5ac`：

- **FACT：** 调用 common sender `0x185e890` 时，参数为 task `2`、subobject
  `1`、payload vector，response-vector 参数 `r8=0`；
- **FACT：** 调用前临时把 FSP host 对象 byte `+0x31` 置 1，成功或失败清理时都
  立即清回 0；该 byte 没有跨调用保存；
- **FACT：** common sender 返回非零时，`+0x520` 原样返回错误；返回零时才把
  caller 的输出 byte 写 0 并返回成功；
- **FACT：** dispatcher 在 `0x10960d2..0x10960d4` 测试该返回值，非零立即退出，
  不可能到达 `0x1096228` 的 pending host apply。

因此这里存在严格的 host happens-before：**task-2 sender 完整返回零，先于任何
pending host apply**。这项事实不依赖 task 2 实际改变了哪只 PLM。

### 2.2 transport 确实进入 response-completion 路径

common sender 的两阶段调用可以由 vtable 直接闭合：

1. **FACT：** `0x185e890` 先调用 `0x185e260`。后者通过 transport vtable
   `+0x38` 发送构造好的 packet（调用点 `0x185e632..0x185e660`），并传播发送
   错误。
2. **FACT：** 发送阶段成功后，`0x185e890` 在 `0x185e8c9..0x185e8ed` 再调用
   同一 transport 的 `+0x30`，把其 EAX 直接作为最终状态返回。
3. **FACT：** `FspEmemTransport` RTTI/vtable 位于 `0x930f1b0..0x930f258`；
   address point `0x930f220` 的 `+0x30 = 0x185c7d0`，该函数使用明文 poll 名
   `FspEmemTransport::PollFspResponseComplete`，而 `+0x38 = 0x185bdd0` 是发送
   路径。
4. **FACT：** `FspMnocTransport` address point `0x930f270` 的
   `+0x30 = 0x185d290`、`+0x38 = 0x185ba90`；`0x185d290` 读取并解析 response，
   其日志路径包括返回码/response 内容。

所以“同步”可以精确表述为：**MODS 当前线程在 `+0x520` 内完成发送，并进入所选
transport 的 response-completion/response-parse 调用；该调用返回状态前，
dispatcher 不会继续 host apply。**

**FACT：** task 2 还有 QCAP 门。`0x185e530..0x185e55c` 调用 capability helper；
缺失时打印 `Floorseeping PRC isn't supported by FSP or is not yet active`，返回
`0x12d`，不进入正常发送。

**FACT：** task-to-QCAP mapper `0x1857b10` 对 task 2 落入 bitmask
`0x4713e` 的 `0x13` 返回分支；task 13 也落入同一分支。公开 610 头文件
`nvdm_format.h:43-50` 定义 `NVDM_TYPE_PRC=0x13`、
`NVDM_TYPE_CAPS_QUERY=0x16`。

**FACT（F1/F2 分层）：** QCAP `0x13` 只是一条 FSP-reported PRC message-family
entry 的 cache-presence test，不是 credential 或 PLM snapshot；presence 通过后，
本次 task 2 仍由独立 command status 给出 host-visible completion/error。两步都
不能证明设备 PLM 已改变。

### 2.3 同步 ack 不等于权限状态证明

**FACT：** GB20x 调用把 response vector 设为 null，host 没有保存 permission
token、cookie、prior PLM value、expiry 或 undo handle。

**FACT：** 公开 610 的 `NVDM_PAYLOAD_COMMAND_RESPONSE` 只有三个 `NvU32`：
`taskId`、`commandNvdmType`、`errorCode`
（`nvdm_payload_cmd_response.h:35-42`）；parser 只映射 error status
（`kern_fsp_gh100.c:455-500`）。

**UNKNOWN：** status 0 返回时，GB202 FSP 是否实际改变 `d0/dc`、写成什么值、
是否仍保持或已按内部规则收回。`f8` 是 latch 的独立 PLM，现有 task-2 旁证没有
覆盖它。同步 host ack 对这两类 device state 都不能作答。

## 3. 是否存在第二次 close/restore

### 3.1 正常 `+0x520` 主线

**FACT（path-scoped negative）：** 从 `0x10960cc` 的 `+0x520` 成功返回到 generic
dispatcher 退出，可见调用只有条件化内部处理、pending `+0x308`、`+0x488`、
状态 bookkeeping；没有第二次 `0x185e890/0x185e980`、没有 task/subobject 常量，
也没有已知 d0/dc/f8 setter。

**FACT：** GB20x `+0x488 = 0x105f060` 在 FSP feature 与 `+0x438` 成立时读取
`SkipFspFs`。普通 `SkipFspFs=0` 在 `0x105f102..0x105f107` 直接回到零返回；
因此它不是正常路径的 close/restore sender。

**FACT：** `FSP object +0x31` 在 `0x106c5ac` 清零只是 host 对象的临时
in-flight 标志。它既未触发第二条 transport call，也未携带 PLM 值，不能称为
permission restore。

**FACT：** `Gpu::Initialize` 的 `+0x3c8` reset 是条件调用，不是每次 task 2 后
无条件执行；首次无参数路径可以跳过。即使 reset 发生，现有 host 代码也没有把
它标成 d0/dc/f8 restore 或验证 reset 后 PLM 值。

**FACT（existing bounded audit）：** 紧随其后的 GB202 `+0x448(3)` 最终实现
`0x1255150` 是 FSP fuse-error/status 检查；已有有限窗口与字符串交叉检查未见
task-2 sender、reset 或已知 PLM setter。它不能充当隐藏 close 的证据。

### 3.2 不能误当作 close 的其他事务

- **FACT：** `GB20xFs+0x40 = 0x106c660` 是另一条完整方法。它会发送相同的
  task `2`/subobject `1`，随后进入 reset 处理；generic dispatcher 的正常
  `+0x520` 主线没有调用该方法。相同 task/subobject 且无 inverse flag，不能把它
  描述为初始 send 的逆向 close。
- **FACT：** `HopperFs` RTTI/vtable 直接把 `0x1071bd0` 绑定在
  `8HopperFs` 类中（RTTI 名在 `0x9263208`，函数指针在 `0x9263280`）。该方法
  也可发送相同 task/subobject 后 reset；这是旧/兄弟类的独立事务，不是 GB20x
  normal `+0x520` 的后继。
- **FACT：** Hopper 同槽 `+0x520 = 0x1094990` 只在 send 前检查 d0/dc，若已为
  `0xf` 则跳过 send；它没有配对的 restore 参数。

### 3.3 host/GSP 之外的边界

**FACT（current visible-material negative）：** 当前 OpenRM、可见 GSP ELF 与
归档报告没有公开 task-2 close/undo schema、host token 或 f8 restore 调用点。
`parallel/gsp_f8_hulk_audit.md` 对当前 GSP 的限定扫描也未找到可见 direct f8
setter/restore。

**FACT：** 公开 GB202 FSP source 写明 FSP 由 chip reset 后的 Bootfsm 启动，host
只等待 boot-complete scratch（`kern_fsp_gb202.c:50-61`）。当前可见 GSP ELF
不是 FSP 指令体，因此本地材料缺少可审计的 task-2 consumer。

**UNKNOWN：** FSP/ROM/硬件是否把权限绑定到 response、首个受保护写、timer、
init phase、session、reset 或其他状态机，并在 host 看不见的位置自动恢复。
“host 没有第二次 close”不能升级成“权限永久保持”。

## 4. PRC knob `0x1d` 与 task 2 的精确关系

### 4.1 `0x1d` 的身份与独立写事务

**FACT（纠正旧记录错配）：** native knob-table 的临时记录大小为 `0x28`：
`std::string name` 位于 `+0x00`，`uint32 id` 位于 `+0x20`。插树循环
`0x1860a75..0x1860aab` 按这个布局复制字段并每次前进 `0x28`。字符串块
`0x9224d30`、`0x9224d40` 与 `0x9224c10` 在 stack record `rsp+0x4b8` 拼成
`PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT`，同一 record 的 ID store 是
`0x1860458 -> [rsp+0x4d8]=0x1d`。`0x18603d4` 写入的 `0x1c` 属于前一条
`rsp+0x490` 的 `PRC_KNOB_ID_RPR_ALLOW_INB`，不能配给下一条名字。完整记录
证据见 `parallel/prc_knob_metadata.md`。

**FACT：** PRC executor `0x185ef60` 对每个请求项：

1. `0x185f336..0x185f37b` 先读 current knob value；
2. 只有 current != requested 才进入 `0x185f1c0`；
3. `0x185f284..0x185f299` 调用 common sender，参数 task `13`、submessage `2`；
4. 非零 sender status 立即返回；
5. `0x185f2a6..0x185f2ee` 再读同一 knob 并比较 requested value；
6. mismatch 在 `0x185f458..0x185f474` 返回 `0x12f`。

因此 `0x1d` 是**单独的 PRC object write/readback transaction**，不是 task 2
payload 中的字段。

### 4.2 共享的是 capability family，不是 task identity

**FACT：** task 13 的 capability check 位于 `0x185e490`，task 2 的 check 位于
`0x185e530`；两者经 `0x1857b10` 都映射到 QCAP key `0x13`。这说明两者共享
FSP PRC message family capability。

**FACT：** 成功写入 `0x1d` 已经要求 QCAP `0x13` 存在；所以在同一份已预取的
cache 中，它不能“创造”原来不存在的 task-2 capability。反过来，若该独立写
事务成功，后续 task 2 不会因缺少另一条 QCAP family 而失败，但仍可能因具体
policy、payload、transport 或 FSP command error 失败。

**FACT（host negative）：** 没有 PRC write map 时，host 不会自动添加 `0x1d`；
task-2 sender 也不读取 knob map、knob ID 或 requested value。故“每次 task 2
之前必定写 0x1d”不是事实。

这个 negative 在可见 JS 前端也可独立复核：`gpuargs.js:251` 把
`g_FspPrcWriteArray` 初始化为空数组，`ArgFspPrcWrite()`
（`16481..16487`）是已解码脚本目录中唯一向其 push 的位置，而
`HandleGpuPreInitArgs()`（`7362..7365`）只在数组非空时调用
`Gpu.SetFspPrcWriteInfo()`。因此普通无参数脚本不会自动生成 `0x1d` 请求；显式
`-fsp_prc_write` 才会走这条 JS 路径。该结论只覆盖现有解码脚本，不排除 FSP
启动默认值、私有脚本或其他 native caller。

对 native executor `0x185ef60` 的 `.text` direct `call rel32` 目标扫描只找到
四处：通用 map `0x123fcd4`、IST=1 `0x1ebc909`、CCD=1
`0x1ef55c3`、CCD=0 `0x1ef6128`；没有硬编码 floorsweeping `0x1d` caller。
JS callback `0x116bd50` 也只见一次 `SetFspPrcWriteInfo` 注册立即数。该结果加强
host negative，但仍不覆盖动态间接 caller、未包含模块或 FSP 初始状态；详见
`parallel/prc_autoinject_audit.md`。

**INFERENCE：** knob 名称 `FLOORSWEEPING_ALLOW_INB_ONE_SHOT`、它在 FS/task 2
之前的可选位置、以及 task 2 的 PRC capability/log context，共同支持：`0x1d`
用于为随后 floorsweep/PRC 动作准备一次性 in-band permission。

**UNKNOWN：** 对 floorsweeping one-shot 而言 requested value 是否必须为 1、
task 2 是否消费它、何时自清、是否可省略、失败/重试语义及 FSP 内部 lifetime。
host 在 FS 后没有显式写 0，但这不能证明一定由 task 2 自清。

## 5. `0x8200d0`、`0x8200dc` 与 `0x8200f8`

### 5.1 d0/dc：强语义旁证，但不是 GB202 consumer 事实

| 对象 | 当前 MODS 静态证据 | 判定 |
|---|---|---|
| `0x8200d0` OPT/FS PLM | Hopper `0x1094a50..0x1094a8e` 用 read ID `0x10e0c000`、constant ID `0x40e0c000` 检查 `0xf`；`SkipFspFs` helper 在 `0x1095d30..0x1095dd0` 做同类检查 | **FACT** |
| `0x8200dc` L2 PLM | Hopper `0x1094a94..0x1094ad2` 用 `0x1059c000/0x4059c000` 检查 `0xf`；`SkipFspFs` helper 在 `0x1095dd0..0x1095e0a` 做同类检查 | **FACT** |
| 二者与 task 2 | Hopper 只有在二者未同时为 `0xf` 时发送相同 task `2`/subobject `1`，已开放则打印 `Skipping FSP FS because PLMs are already lowered!` | **FACT（Hopper sibling）** |
| GB20x task-2 实际 effect | GB20x 省略 precheck，但仍在 host apply 前发送相同 task/subobject | **INFERENCE：旨在为至少 d0/dc 准备权限** |
| GB202 实际值与写入 | 无可见 FSP consumer 或运行读值 | **UNKNOWN** |

**FACT（bounded executable-immediate scan）：** 对 MODS `.text` 的分块立即数扫描
未命中 d0/dc 的 RegHal field-setter IDs `0x20e0c000/0x2059c000`，也未命中
直接 `0x8200d0/0x8200dc` 指令立即数。已知 host 路径只有 read/constant compare，
没有直接 lowering/restore setter。

该负结果支持“host 把动作交给 FSP”的解释，但不能排除动态地址、表驱动、不可见
FSP/ROM 或硬件状态机。

### 5.2 f8：独立缺口

**FACT：** RegHal access metadata 把 latch `0x820040.bit0` 的访问 PLM 指向
`0x8200f8`；它不是 d0/dc 两只 floorsweep PLM 的同义地址。

**FACT：** Hopper task-2 precheck 和 `SkipFspFs` helper 都只检查 d0/dc，不检查
f8。task-2 host payload/call 参数也没有 f8 address、field 或 inverse flag。

**FACT：** current GB20x `IsFusePrivSecurityEnabled` 最终函数 `0x151b000` 只在
`0x151b059..0x151b070` 用 `0x405c4100` compare f8.bit4；它是 query，不是 setter。

**FACT（bounded scan + binding correction）：** MODS `.text` 未命中
`0x205c4000/0x105c4000`；可执行 `0x405c4000` 只在旧 `0x1455240` 的 f8 setter
出现。固定 GSP ELF 确有 `0x0108c4ae` 对 `0x8200f8` 的 read block，且该块只写
`0x820040/0x82013c`、不写 f8；但 OBJBSP constructor 重放证明该 helper 只绑定
TU102/TU116，GB202/index 65 在同一槽绑定无副作用 success stub。因此该 block
既不是 GB202 task-2 consumer，也不是 GB202 `f8` setter/restore 证据。完整绑定
纠错见 `parallel/gsp_f8_consumer_lifecycle.md`。

**FACT：** MODS 的直接 `0x8200f8` x86 命中 `0x6d84ee8` 也是 read bit4；该
NVDEC ucode-encryption/latch helper 随后写 `0x820040` 与 `0x82013c`，并不写
`0x8200f8`。它既不是 task-2 sender，也不是 PLM restore。

### 5.3 旧 GV100 secure-PMU 只能作为历史先例

**FACT（old-class binding）：** RTTI/vtable 给出严格类边界：

- `9GV100Fuse` RTTI 名约在 `0x92ec278`，vtable address point 在
  `0x92ec2b0`；
- secure-PMU transaction `0x1454bd0` 位于该 vtable entry `0x92ec390`；
- query `0x14551e0` 位于 `0x92ec3b0`；
- setter `0x1455240` 位于 `0x92ec488`；
- 紧随其后的 `7NewFuse` RTTI/vtable 从 `0x92ec490` 起，旧 setter 不属于
  `NewFuse` vtable。

**FACT：** `0x1455240` 先用 `0x40e14100`，再用 `0x405c4000`，把旧路径的
f4/f8 write-protection fields 降至 constant `0xf`；失败路径日志为
`Secure PMU could not be loaded!`。`0x1454bd0` 是 secure-PMU transaction，
也见于 GP10x vtable，说明这是旧架构复用机制。

**INFERENCE（historical analogy only）：** 旧 GV100 证明“latch PLM 曾需要安全
微码专门降低”这一设计先例，并提高了 f8 不能被 d0/dc 自动涵盖的可信度。

**UNKNOWN for GB202：** task 2 是否以 FSP 替代旧 secure-PMU 并处理 f8、是否
使用相同数值、lifetime 或 restore 规则。旧 vtable、旧 fusebinary 与旧 caller
不能迁移成 GB202 事实。

## 6. 最终直接回答

1. **FACT：host 调用时序。** 在正常 first eligible GB20x FS 路径中，可选 PRC
   read/write 先发生；`doFsp=1` 时随后发送 task `2`/subobject `1`，完整返回零后
   才可能进入 pending host apply。首次无 FS 参数仍可发送 task 2，但跳过 apply
   与 outer reset，并把 FS 对象标记 initialized。
2. **FACT：F1/F2 与同步等待边界。** task 2 先要求 cached QCAP key `0x13`
   presence，再由 common sender 调 transport send `+0x38` 和
   response-completion/parse `+0x30`；status 逐层传播到 dispatcher，非零不会继续
   host apply。QCAP presence 是 message-family gate，status 是本次请求的
   host-visible completion/error；二者都不是授权 token 或 PLM-state proof。
3. **FACT（host-visible negative）：没有第二次 close/restore。** 正常 `+0x520`
   后未见第二条 task-2、逆向 flag、PLM setter、undo handle 或 response token；
   `+0x488` 在 `SkipFspFs=0` 时 no-op。条件 reset、status check 和独立 `+0x40`
   事务不能重命名为已证明的 restore。
4. **UNKNOWN：device effect 与隐藏生命周期。** FSP/ROM/硬件是否实际改变
   `d0/dc`、维持或收回这些状态以及 reset 后具体值，当前不可见 consumer 不能
   回答；独立 `f8` 是否被 task 2 处理也仍未知。
5. **FACT：`0x1d` 是独立前置事务。** 它通过 task `13`/submessage `2` 做
   read-if-different-write-readback，与 task 2 共享 QCAP `0x13`；host 不会把它
   自动嵌入 task 2，也不会在 FS 后显式写 0。
6. **INFERENCE / UNKNOWN：`0x1d` 语义。** 名称与顺序强支持 floorsweep one-shot
   permission preparation；required value、task-2 消费/self-clear 和 lifetime
   仍未知。
7. **INFERENCE（较强）：d0/dc。** Hopper precheck、`SkipFspFs` 校验和
   send-before-apply 强支持 task 2 旨在为 d0/dc 准备权限；GB202 实际修改仍未
   由 consumer 证明。
8. **UNKNOWN：f8。** task-2 旁证没有覆盖独立 f8；当前只见 query/read，旧 GV100
   setter 只是历史类比。不能把 task-2 成功扩写成 latch/raw writer 已获完整权限。

本报告不提供或暗示任何 live probe、MMIO 写入、MODS 执行或 reset 实验；所有
结论仅限上述静态证据边界。

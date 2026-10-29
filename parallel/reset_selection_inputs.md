# MODS 570.151：NewFuse 成功尾声的 reset 选择输入审计

## 范围与约束

本报告只做静态分析，目标是回答以下窄问题：

1. `NewFuse.SetSwFuses` 成功后究竟怎样选择 hot / boot / fuse / base reset；
2. boot、fuse、base 三个 coupling 输入从哪个对象读取，怎样设置，已知初始化来源是什么；
3. 哪些 CLI/JS 入口会影响它们，是否存在公开且不接触 GPU 的查询方法；
4. 是否漏掉了会改变 `base > fuse > boot > hot` 优先级的条件。

审计对象是：

- `mods_audit/static/extracted_inner/mods`
- SHA-256：`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`
- ELF：64-bit x86-64，stripped
- 解码脚本：`mods_audit/static/decoded/all/gpuargs.js`
- OpenRM 610.43.03 源码：`/usr/src/nvidia-610.43.03/src`

没有运行 MODS，没有打开 `/dev/nvidia*`，没有访问 GPU/MMIO，没有加载/卸载模块，也没有触发 reset。

证据等级沿用 **FACT / INFERENCE / UNKNOWN**：FACT 是本样本中直接闭合的静态事实；INFERENCE 是由多个事实支持但仍缺运行时观测的解释；UNKNOWN 是当前静态样本不能回答的部分。

## 结论先行

- **FACT：** 普通 NewFuse direct-shadow 编程成功后的第一个 reset，选择优先级确实是：

  ```text
  base coupling = 1  -> state 7, base reset
  else fuse = 1     -> state 6, fuse reset
  else boot = 1     -> state 5, boot reset
  else              -> state 3, hot reset
  ```

  状态名由 `RmStateToString` `0x1845f20` 直接确认。

- **FACT：** mapper 在判断优先级前按 boot、fuse、base 的顺序把三项都采样一遍；这是“先全部读取，再按 base/fuse/boot 判断”，不是短路读取。

- **FACT：** direct-shadow 成功尾声给 mapper 的 request 固定为 `2`。request 2 只继承已有 coupling，descriptor 的 `needCoupling` 字节固定为 `0`；所以这条路径不会调用 coupling setter，也不会为了 reset 临时把 boot/fuse/base 中某一位置 1。

- **FACT：** 没有成功但不 reset 的已知 `SetSwFusesCore` 分支。普通编程分支和 alternate 分支成功后都进入相同的 `+0x370` 回调。

- **FACT：** 第一次 reset 成功后，`0x127b000` 还可能因 recovery mode 发起第二次 reset。第二次调用会重新采样三个位，因此理论上第二次的 reset 类型可以与第一次不同。

- **UNKNOWN：** 本机此刻三个位的实际值。静态 RegHal 表只能证明字段和选择逻辑，不能证明当前硬件/固件状态。

## 1. direct-shadow 成功链闭合

**FACT：** 两条成功分支汇合到同一 post-program 回调：

```text
NewFuse::SetSwFusesCore                         0x14620d0
  ordinary dispatcher success                  0x14621f3 -> 0x146223c
  alternate dispatcher success                 0x14623da -> 0x14623f9
  -> object +0x370
  -> MultiMacro                                 0x146dd30
  -> each accessor +0x90                       0x146dd62
  -> GB20x accessor method                      0x1515770
  -> handler +0x100
  -> thunk                                      0x151ad50
  -> GpuSubdevice +0x1b0
  -> Blackwell implementation                  0x127b000
  -> reset/reinit wrapper                       0x0dff7b0
  -> mapper through GpuSubdevice +0x1070        0x126b360
  -> reset dispatcher                           0x0dfe3d0
```

**FACT：** `0x1515770` 看似传入整数 `5`，但 thunk `0x151ad50` 重新取得 `GpuSubdevice` 后跳到只使用该对象的 `+0x1b0` 方法；该整数没有进入最终 mapper。`0x0dff7b0` 随后重新构造 request `2`。因此不能把这里的早期 `5` 解释为固定 boot reset。

**FACT：** Blackwell vtable 基址 `0x92c1550`：

- `+0x1b0`（`0x92c1700`）=`0x127b000`
- `+0x1070`（`0x92c25c0`）=`0x126b360`

## 2. mapper 的完整 request 表与优先级

mapper `0x126b360` 首先通过当前 `GpuSubdevice` 的 RegHal 对象测试：

| 采样顺序 | 输入 | test constant | 结果 |
|---:|---|---|---|
| 1 | boot coupling | `0x42d68001` | 布尔值 |
| 2 | fuse coupling | `0x42d6c001` | 布尔值 |
| 3 | base coupling | `0x42d64001` | 布尔值 |

**FACT：** 三个 test 都发生在 request 分支判断之前。mapper 对外只拿到三个布尔量，没有另行传播“字段读取失败”状态。

request jump table 位于 `0x92c0900`；静态还原如下：

| request | 选择的 state | descriptor `needCoupling` 条件 | 与 direct writer 的关系 |
|---:|---:|---|---|
| 0 | invalid | — | 不使用 |
| 1 | invalid | — | 不使用 |
| 2 | `base ? 7 : fuse ? 6 : boot ? 5 : 3` | 恒为 `0` | **direct writer 固定使用** |
| 3 | 3 | `boot || fuse || base` | generic hot-reset request |
| 4 | 6 | `!(fuse && !base)`；boot 不参与 | 与 request 6 共用 arm；语义名称未确认 |
| 5 | 5 | `!(boot && !fuse && !base)` | generic boot-reset request |
| 6 | 6 | `!(fuse && !base)`；boot 不参与 | generic fuse-reset request |
| 7 | 7 | `!base` | generic base-reset request |

**FACT：** request 2 的精确分支位于 `0x126b430..0x126b4a6`：base 为真先选 7，其次 fuse 选 6，其次 boot 选 5，最后选 3；同时无条件写 `descriptor+8 = 0`。

**FACT：** dispatcher `0x0dfe3d0` 只有在 `descriptor+8 != 0` 时，才在 `0x0dfed6d..0x0dfed86` 调 `GpuSubdevice +0x3a0` 设置 coupling。request 2 的该字节恒为 0，所以 direct-shadow 尾声不会走 setter。

**FACT：** mapper 使用的 bounded RegHal helper `0x1988fc0` 在 unsupported-lookup 分支返回 `0`，mapper 本身没有单独的读错状态。

**INFERENCE：** “全为 false 所以选 hot”只说明 mapper 当次看见的三个布尔量都是 false，单凭这个结果不能证明所有更低层读取机制绝对可靠。已解码的 GB202 表包含这三个 field ID，因此“不支持该 ID”并非当前首选解释；但没有运行时读回，仍不能把 mapper 结果当作本卡实测。

## 3. 三个输入从哪里读

**FACT：** Blackwell `GpuSubdevice` vtable `+0x208` 是 `0x0db40a0`。它：

1. 读取 `GpuSubdevice+0x6c0` 的可选对象指针；
2. 非空则返回该对象；
3. 为空则返回嵌入对象 `GpuSubdevice+0x90`。

mapper 每次都通过这个 getter 取得 RegHal 类对象，再测试三个 field；这不是 mapper 内保存的三个 C++ cached bool。

后续独立生命周期审计已经闭合 `+0x6c0`：基础构造器把它清零；只有
`GET_PARTITIONS` 成功、存在有效 MIG partition 且选择了 SMC/GR engine 后，
writer `0x0dee6c6` 才安装 RTTI 名为 `SmcRegHal` 的对象；重选会替换并析构旧
对象，`GpuSubdevice` 析构时释放现对象。MIG unsupported 或没有有效 partition
的首次初始化路径保持 null。完整证据见 `parallel/reghal_override_lifecycle.md`。

已解码的 RegHal 元数据为：

| coupling | field / test ID | RegHal domain 内 field offset | PLM metadata offset |
|---|---|---:|---:|
| fuse | `0x42d6c000 / 0x42d6c001` | `0x40` | `0x308` |
| boot | `0x42d68000 / 0x42d68001` | `0x44` | `0x30c` |
| base | `0x42d64000 / 0x42d64001` | `0x48` | `0x310` |

**FACT：** 三项属于同一个 RegHal domain word `0x31`。

**重要边界：** 表中的 `0x40/0x44/0x48` 是 RegHal domain 内部字段偏移，`0x308/0x30c/0x310` 是 PLM 元数据偏移；它们不是可直接拿去戳 BAR0 的绝对 MMIO 地址。

`SmcRegHal` 只把 resolved `0x400000..0x5fffff` 且 SMC-enabled 的 GR-local
访问改走带 route 的 `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS`；其余访问回退普通
RegHal。coupling 三项是 PMC-relative `+0x40/+0x44/+0x48`，所以静态证据强
支持普通未分区 GB202 使用内嵌普通 RegHal，即使存在 SMC override 也不会接管
这三项。由于本轮没有执行 MODS 来得到 domain `0x31` 的当次 resolved 数值，
最后一句仍标为**强 INFERENCE**，而不是本卡 runtime FACT。

## 4. setter、权限和已知初始化来源

Blackwell `GpuSubdevice +0x3a0`（vtable `0x92c18f0`）是 `0x126d4e0`。

### setter 行为

| 请求 state | 前置约束 | direct-write 目标 | 成功后验证 |
|---:|---|---|---|
| 3 hot | boot/fuse/base 必须已全为 0 | 不写 coupling | 任何一项已置位就报 `Resets already coupled, can't trigger hot reset` |
| 5 boot | fuse=0 且 base=0 | boot=1、fuse=0、base=0 | boot=1、fuse=0、base=0 |
| 6 fuse | base=0 | fuse=1、base=0 | fuse=1、base=0；boot 不在 acceptance 中 |
| 7 base | 无更高 coupling 前置项 | base=1 | base=1 |

**FACT：** direct-write access descriptors 是：

- boot `0x12d68000`
- fuse `0x12d6c000`
- base `0x12d64000`

PLM direct-write 判定 helper 为 `0x198a7e0`。本样本已还原的允许式是：

```text
bit0 & bit4 & (!bit10 | bit12) & (!bit11 | bit12)
```

**PUBLIC FACT / V-STATIC：** NVIDIA 公开 PLM layout 把 bit4 正式定义为
`WRITE_PROTECTION_LEVEL0_ENABLE`。它表示 L0 写允许，不是 MODS 的 network
`SecurityUnlockLevel=4`。固定 610 GSP 的三个 coupling setter 各自只检查配对
PLM 的 bit4；gate 关闭或写后 target bit0 未置位都形成
`0x40 = NV_ERR_INVALID_STATE`，前者还经过 assert/条件 `ebreak` 路径，不能把它
当作无害权限探针。完整边界见 `parallel/coupling_gate_semantics.md`。

**FACT：** MODS 在任何写入前按上述 helper 的最终 bool 预选 backend：所需
direct-access 谓词不全时，setter 才走
`GpuSubdevice +0x1100 = 0x126db90`，只接受 state 5/6/7，并经 `0x185e890`
发送 FSP task 4 / subobject 1；boot/fuse/base 的单字节 payload 表是
`[1, 0, 2]`。这不是 direct 写失败后的 fallback：direct readback 失败不会再转
FSP，FSP 失败也不会回头 direct。setter 之后读回验证，并区分 MODS 直写与 FSP
路径的日志。固定 GSP setter 自身也没有 FSP sender。

**FACT：** 这组 setter 中没有发现“清空全部 coupling”的 state。hot state 3 只接受它们原本已经全零，并不会替调用者清零。

### 已知会建立 coupling 的路径

- **FACT：generic reset。** request 3/5/6/7 经 mapper 生成目标 state；如果现状不匹配，descriptor `needCoupling` 为 1，dispatcher 先调用 `+0x3a0`，再发 reset。这些不是只设置不 reset 的安全查询入口。
- **FACT：physical FSP fuseblow coordinator。** `GpuSubdevice+0x368 = 0x1249960` 的 mode 0 用 request 5，并在需要时设置 boot coupling；对应日志明确为 `Setting up coupling for boot reset without issuing it!`。mode 1 fuseblow，mode 2 日志为 `Fuse Resense`。这是物理 fuse 流程，不在普通 shadow `SetSwFuses` 成功链中。
- **FACT：resense。** 已知 GB20x resense 路径名义上请求 state 6，再执行其 latch-clear/resense/reset 生命周期；这里的 clear 不是已证明的 coupling-clear。它与 direct-shadow writer 的普通成功尾声不是一条路径。
- **FACT：direct-shadow success。** 固定 request 2，`needCoupling=0`，不建立新 coupling。

**FACT（bounded enumeration）：** 已检查的普通 `Gpu::Initialize` / `SetSwFuses` 直接调用链中，没有发现无条件预置 boot/fuse/base coupling 的初始化步骤。`-fusing_mode` 可以进入独立的 physical-fusing 流程，但普通无参数初始化不等于该流程。

**UNKNOWN：** power-on、GFW/FSP/GSP、制造配置或跨 reset 保留状态能否在 MODS 入口前设置这些位，以及本卡实际启动时做了什么。这需要另一侧 firmware/硬件证据，当前静态 ELF 不能证明。

## 5. CLI / JS 暴露

解码的 `gpuargs.js` 明确提供：

| 行 | 参数 | JS 动作 | 结论 |
|---:|---|---|---|
| 755 | `hot_reset` | `Gpu.Reset=Gpu.HotReset` | 执行 reset，不是 query |
| 760 | `boot_reset` | `Gpu.Reset=Gpu.BootReset` | 执行 reset，必要时建立 coupling |
| 761 | `fuse_reset` | `Gpu.Reset=Gpu.FuseReset` | 执行 reset，必要时建立 coupling |
| 762 | `base_reset` | `Gpu.Reset=Gpu.BaseReset` | 执行 reset，必要时建立 coupling |
| 1668 | `use_boot_reset_for_fs` | 设置 `g_UseBootResetForFs` | 影响 floorsweep 后的独立 reset 策略 |
| 13209-13211 | — | `subdev.UseBootResetForFs = ...` | 不改变 direct writer 固定 request 2 |
| 1811 | `reg_priv_check` | `JsRegHal.RegPrivCheckMode` | 只控制 RegHal privilege-check 模式，与 coupling 选择无关 |

**FACT：** generic `NoReset` 符号/选项存在，但已检查的 `NewFuse.SetSwFuses` 入口只收 fuse pair；其两条成功编程分支都调用 `+0x370`。没有证据表明 `NoReset` 能压掉这条 direct-shadow 成功回调。

**FACT：** 解码 JS 中没有找到命名的 boot/fuse/base coupling getter/setter。generic `JsRegHal.Read32/Test32` 类能力的 native 字符串不能等价为“公开、安全、离线”的 coupling 查询；真使用它仍会进入 live register/backend access。

**FACT：** native 字符串 `ResetCoupling` 出现在 FSP use-case 名单中，并不构成一个 JS 属性或公开查询 API。

## 6. 第一次与 recovery 第二次 reset 的额外条件

`0x127b000` 的控制流是：

```text
call 0x0dff7b0                  # 第一次 reset；request 2
if error: return error
if IsIstMode: return success
if RegHal property 0x42384201 == false: return success
log recovery mode
call 0x0dff7b0                  # 第二次 reset；再次使用 request 2
```

**FACT：** `IsIstMode` 和 property `0x42384201` 只决定是否追加第二次 recovery reset，不参加第一次 reset 的 base/fuse/boot/hot 优先级判断。

**FACT：** 第二次调用重新进入 mapper，并重新采样 boot/fuse/base。若第一次 reset 改变了 coupling 状态，第二次的选择可能改变；不能机械地假设两次类型必然相同。

**FACT：** `SetSwFusesCore` 内一个尚未命名的 property enum `0xbd` 决定 ordinary/alternate plan 分支，但两条成功分支都进入同一 `+0x370`，故它不改变上述 reset priority。

**FACT：** `0x0dff7b0` 还根据平台属性填写 dispatcher flags；这些 flags 会影响 reset 执行细节，但 mapper-selected state 仍来自 request 2 和三个 coupling 布尔量。当前 bounded audit 没有给所有 flag 强行命名。

## 7. 公开 query：能知道“是否 coupled”，不能知道是哪一种

OpenRM 公开头文件：

- `/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080gpu.h:4907`
- `NV2080_CTRL_CMD_GPU_IS_RESET_COUPLED = 0x208081f3`
- 输出结构只有一个 `NvBool isResetCoupled`

生成的 control item：

- `/usr/src/nvidia-610.43.03/src/nvidia/generated/g_subdevice_nvoc.c:13546`
- method `0x208081f3`
- flags `0x48`，即 route-to-physical（`0x40`）加 nonprivileged（`0x08`）
- access right `0`
- param size 为 1-byte bool 结构

**FACT：** 公开 ABI 只返回一个 bool，没有三项分量字段；仅从 ABI 无法重建
`base > fuse > boot > hot` 的选择。

**FACT：** 固定已安装 610.43.03 inner GSP 的 handler `0x142c510` 会调用
`OBJGPU+0x668` 并写出单字节结果；artifact provenance 见
`parallel/GSP_ARTIFACT_PROVENANCE.md`。

**V-STATIC（2026-07-21 补充）：** 两套独立、有界的 OBJGPU 构造重放均证明：
GB202 index 65 / group 2 low 1 把 `0x144d4e8` 写入 `OBJGPU+0x668`，而不是
`0x19508c4` 恒 false 默认桩。旧解释只看到了 group-1 bitmap `0x98000000`，
遗漏了包含 low bit 1 的 group-2 bitmap `0x303f`。进一步的 getter/setter
交叉审计把 guard 校准为 `isVirtual`，并把三个 device-relative 位闭合为
`+0x40=fuse`、`+0x44=boot`、`+0x48=base`；getter 只直接读取前两项并做短路
OR，没有第三次 `+0x48` load。证据链见
`parallel/reset_coupled_binding_replay.md`、`parallel/gsp_objgpu_668_replay.py`
、`parallel/objgpu_668_independent_check.md`、
`parallel/reset_getter_guard_provenance.md` 和
`parallel/reset_getter_internal_fields.md`。

**FACT：** 项目里虽有历史 `reset_coupling_readonly_probe.c`，但没有保存 stdout 和同时段健康证据；本次没有运行。它会打开 `/dev/nvidiactl` 和 `/dev/nvidia0` 并发 ioctl，因此也不满足“完全不接触 live GPU”的条件。

**V-STATIC（公开 610 control 面的定向清单）：** 对公开 ctrl headers 和 generated
Subdevice methods 的 reset/coupling 命名项做定向搜索，只找到这一条 coupling
GET；`NV2080_CTRL_CMD_GPU_GET_RESET_STATUS` 返回的是“设备是否被标记为需要
reset”的 `bResetRequired`，不是 coupling 分量，而 `NV0080_CTRL_CMD_BIF_RESET`
会实际发起 reset。没有找到公开、只读、逐 fuse/boot/base 返回的 control。这个
负结果严格限 610.43.03 已公开控制面，不排除私有 firmware/MODS 接口。

**结论：** 没找到 CPU-only/offline 的当前 coupling 查询。静态 RegHal 元数据能
告诉我们字段、优先级和 setter 逻辑，却不能给出当前值；任何当前值读取最终都
必须接触 RM/GSP/GPU 一侧。GB202 的公开 control 现在已知会到达状态感知 getter，
但固定实现直接返回的是 `fuse || boot`，不直接读取 base；它还会创建/使用 RM
对象并经过 driver/RPC，而不是纯文件解析。项目叙述的历史 0 没有输出留档，也
不是当前值；即便准确，也不能单独排除 base-only 状态。固定 GSP 的 selector 8
只写/读回 base `+0x48`，type-8 reset arm 不追加 selector 4/5，所以可见软件
镜像已排除；硬件/reset-sequencer/FSP/GFW 隐式联动仍未知。

## 8. 最终证据矩阵

| 问题 | 结论 | 等级 |
|---|---|---|
| direct writer 的 reset request | 固定 request 2 | **FACT** |
| reset 优先级 | base 7 > fuse 6 > boot 5 > hot 3 | **FACT** |
| 是否先读完三项 | 是，boot -> fuse -> base，然后判断优先级 | **FACT** |
| direct writer 是否先设置 coupling | 否，request 2 的 `needCoupling=0` | **FACT** |
| 显眼的早期整数 5 是否强制 boot reset | 否，被 thunk 丢弃，后面重新建立 request 2 | **FACT** |
| generic reset 是否可设置 coupling | 是，状态不匹配时经 `+0x3a0` / direct-write 或 FSP | **FACT** |
| coupling PLM gate bit4 | 标准 `WRITE_PROTECTION_LEVEL0_ENABLE`；不是 network level 4 | **PUBLIC FACT / V-STATIC** |
| direct 失败是否再转 FSP | 否；backend 在写前二选一 | **FACT** |
| 是否存在清空全部 coupling 的已知 setter | 此路径中没有；hot 只接受原本全零 | **FACT** |
| direct success 能否不 reset | 已检查两条成功分支都 reset | **FACT** |
| recovery 是否可能第二次 reset | 是；非 IST 且 property `0x42384201` 为真 | **FACT** |
| 第二次是否重采样 | 是，因此 reset type 理论上可变 | **FACT** |
| 本卡当前三个位值 | 静态分析无法得知 | **UNKNOWN** |
| 可选 RegHal override `+0x6c0` 的来源 | MIG/SMC partition 专用 `SmcRegHal`；普通未分区卡保持 null | **FACT / 强 INFERENCE** |
| 公开 query 的固定 GB202 直接输入 | `fuse(+0x40) || boot(+0x44)`；不直接读 base `+0x48` | **V-STATIC** |
| query guard | `isVirtual`；virtual 时立即 false | **V-STATIC** |
| 公开 query 能否重建三项 coupling | 不能；不区分 fuse/boot，也不直接覆盖 base | **FACT / V-STATIC** |
| base 是否由可见 GSP 软件镜像到 fuse/boot | 否；setter 和 reset dispatcher 均无该动作 | **V-STATIC / bounded negative** |
| base 是否存在硬件/firmware 隐式级联 | 未闭合 | **UNKNOWN** |
| GB202 公开 query 是否绑定恒假桩 | 否，index 65 绑定状态感知 `0x144d4e8` | **V-STATIC** |
| 完全离线地查询当前 coupling | 未找到；从系统边界上也缺少当前状态输入 | **UNKNOWN / no known path** |

因此，优先级、GB202 getter 绑定、guard 和两个直接输入已经足够扎实；剩余真正
阻碍“预测本机实际 reset 类型”的，不是 mapper 还有隐藏分支或未知 RegHal
override，而是本机当前三项 coupling 状态、base 是否会经硬件/reset
sequencer/FSP/GFW 隐式级联到 getter 前两位，以及这些状态的 firmware/boot
初始化来源尚未有可信证据。

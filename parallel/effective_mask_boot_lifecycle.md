# GB202 启动后 effective L2 topology 的读取、比较与验收顺序

日期：2026-07-21
状态：final；纯文档/公开源码考古，没有运行固件或访问设备

## 范围与判定口径

本报告只回答正常 reset/reinit 与启动链中的一个窄问题：

> GB202 在启动后是否有公开可见的软件步骤，自动读取 current/effective L2
> topology，并把它与启动前的 raw plan 或某个期望 topology 做一致性比较？

材料只包括：

- 本地 NVIDIA 610.43.03 OpenRM C/H 源码；
- 已归档的小窗口结论
  `parallel/shadow_reset_lifecycle.md`、
  `parallel/raw_effective_propagation.md`、
  `parallel/gb202_getfsinfo_support.md` 和
  `parallel/getfs_client_path.md`；
- 当前项目中的文档，不包括任何 live 读取结果。

本报告没有采用任何新的固件二进制分析结果；范围确定后只做公开源码与既有文档
读取。全程没有运行 GSP/FSP/MODS，没有打开设备节点，没有访问 PCI/BAR/MMIO，
也没有执行 reset、驱动、模块或固件操作。

下文严格区分：

- **FACT**：公开源码或既有归档小窗口直接支持；
- **INFERENCE**：与全部事实相容的最窄解释；
- **UNKNOWN**：公开材料没有给出实现或调用关系。

## 结论先行

1. **FACT：正常启动有多层“活着没有”的检查，但没有公开可见的 L2 adoption
   compare。** FSP boot-complete、FMC/lockdown、RISC-V active、GSP INIT_DONE、
   每个 engine 的 `StateLoad` 返回码都会被检查；这些检查都没有携带 raw L2
   plan、effective mask 或期望 L2 容量。
2. **FACT：启动完成后存在真实的 effective-topology 读取接口。** 已归档的
   GSP 小窗口证明，GB202 的 `GET_FS_INFO/LTS_MASK` 路径最终读取
   `B = 0x822900 + 4*FBP`，返回该 FBP 内 flattened LTS enable mask。
3. **FACT：这个 GET 是查询接口，不是已证明的自动启动验收。** 在公开 610 C/H
   树中，相关命中是 method export、RPC route、结构拷贝和接口声明；没有找到
   normal boot 主动构造 type-3 query 并把结果与某个 expected mask 比较的
   callsite。
4. **FACT：启动完成消息本身无法承担这种比较。** `GSP_INIT_DONE` 的公开 payload
   只有 `bIsD3Hot`；随后取得的 `GspStaticConfigInfo` 也没有 FBP/LTC/LTS mask、
   LTS count 或 L2 cache size 字段。
5. **UNKNOWN：GSP-RM 私有初始化内部是否读取 B 并做内部自洽检查。** 公开 host
   源码看不到 GSP 中物理 FB/Fuse 初始化实现；因此不能证明“启动期间完全不读
   B”。能证明的是：即使内部读过，公开成功合同也没有把请求前的 raw plan 送入
   启动端，再把 post-init B 返回给 host 做逐项 equality check。
6. **因此，`reset/reinit success`、`FSP boot complete`、`GSP FW RM ready` 和
   `gpuStateLoad == NV_OK` 都不是 post-reset effective L2 topology 与期望值一致的
   证明。** 它们证明对应阶段没有报告致命初始化错误。

## 1. 必须先区分四种“验证”

| 检查类别 | 正常启动中是否可见 | 它实际证明什么 |
|---|---|---|
| firmware/processor liveness | 是 | FSP/GSP 到达规定状态，没有报告该阶段错误 |
| engine lifecycle status | 是 | 各 `StateInit/StateLoad` callback 没有返回未容忍错误 |
| effective topology query | 有接口，但未证明自动调用 | 调用时返回 GSP/RM 当前看到的 active/effective topology |
| requested raw plan 与 post-init effective mask 比较 | 未找到 | 当前公开材料没有这样的成功验收合同 |
| 新增/现存 LTS 的物理健康验证 | 没有 | mask/count 本身不证明数据路径或单元健康 |

这里最容易混淆的是前两行和第四行。一次启动能顺利到 `GSP FW RM ready`，只说明
GSP 初始化协议成功；它不自动意味着 L2 topology 与某个外部期望完全相同。

## 2. 公开可见的正常启动顺序

### 2.1 FSP boot-complete：检查的是 FSP 完成标志

**FACT。** GB202 的 Bootfsm 在 chip reset 后触发 FSP。公开
`kfspWaitForSecureBoot_GB202` 轮询
`NV_THERM_I2CS_SCRATCH_FSP_BOOT_COMPLETE` 的 success 值；超时时读取 FSP scratch、
记录 GPU init error，并把设备标记为需要 reset：

- `kern_fsp_gb202.c:58..61`：Bootfsm/FSP boot-complete 语义；
- `kern_fsp_gb202.c:74..108`：轮询、超时诊断与返回 status。

这个 API 没有 raw/effective L2 mask 参数，也不读取 `0x822900`。因此
`FSP boot complete` 是 FSP 启动里程碑，不是 topology readback。

### 2.2 GSP bootstrap：检查协议、FMC 与处理器状态

**FACT。** 正常 boot 的公开顺序为：

```text
FSP target-mask release / 可选 SPDM
  -> 发送早期 init RPC
  -> 等 lockdown release，并检查 FMC error/mailbox
  -> 检查 GSP RISC-V active
  -> 初始化 status queue
  -> 等待 GSP_INIT_DONE
```

对应源码：

- `kernel_gsp_gh100.c:944..964`：正常 boot 发送 init RPC；
- `kernel_gsp_gh100.c:967..1012`：lockdown/FMC/mailbox/RISC-V 检查；
- `kernel_gsp_gh100.c:1014..1029`：status queue 与 `kgspWaitForRmInitDone`。

GB202 的 GSP bootstrap 复用这条 GH100 流程，既有归档见
`parallel/gb202_610_arch.md`。

**FACT。** 公开的早期 init RPC 只有：

```text
NV_RM_RPC_GSP_SET_SYSTEM_INFO
NV_RM_RPC_SET_REGISTRY
```

见 `kernel_gsp.c:4685..4708`。该函数没有 L2 raw plan、expected LTS mask 或
post-reset comparison 参数。

### 2.3 `GSP_INIT_DONE`：只返回状态与 D3Hot 信息

**FACT。** `kgspWaitForRmInitDone`：

1. 等待 `NV_VGPU_MSG_EVENT_GSP_INIT_DONE`；
2. 检查 RPC header 的 `rpc_result`；
3. 设置 `gspRmInitialized = NV_TRUE`；
4. 从 payload 读取 `bIsD3Hot`。

见 `kernel_gsp.c:6260..6312`。

公开 payload 定义为：

```c
typedef struct rpc_init_done_v17_00
{
    NvBool bIsD3Hot;
} rpc_init_done_v17_00;
```

见 `generated/g_rpc-structures.h:1589..1594`。其中没有：

- FBP/LTC/LTS mask；
- raw/effective floorsweep mask；
- LTS count 或 L2 size；
- expected/actual pair；
- topology mismatch status。

因此 host 端对 `INIT_DONE` 返回 0 的解释只能是“GSP-RM 自己报告初始化完成”，
不能扩展成“host 已验收 effective L2 topology”。

### 2.4 `GET_GSP_STATIC_INFO`：仍不返回 L2 topology

**FACT。** GSP 初始化成功后，CPU-RM 会取得 GSP static info，再设置若干 GPU
properties：`kernel_gsp.c:5146..5175`。

但 `GspStaticConfigInfo` 的公开字段是 GID、SKU、FB region、SR-IOV、engine caps、
FB length、产品属性、VBIOS 信息、内部 handle、RTD3 属性等；没有 FBP/LTC/LTS
mask、LTS count 或 L2 cache size：
`inc/kernel/gpu/gsp/gsp_static_config.h:79..167`。

其中的 `bSysL2CacheCoherentMode` 是 system-L2 coherent-mode 属性，不能当成离散
LTS enable mask 或 L2 容量验收结果。

### 2.5 CPU-RM `gpuStateLoad`：检查 callback status，不比较 topology

**FACT。** `gpuStateLoad` 按 engine 顺序调用 `engstateStateLoad`，检查返回值，并
确认 broadcast 状态没有遗留；`NV_ERR_NOT_SUPPORTED` 还会被归一化为 `NV_OK`：
`gpu.c:2770..2831`。

全部 engine load 完成后，它设置 `bStateLoaded = NV_TRUE`，继续做 PMA usage、
polling 与 PCIe P2P 初始化：`gpu.c:2901..2955`。

这是一套 generic engine lifecycle 验收。公开函数体没有构造
`GET_FS_INFO/LTS_MASK`，也没有保存 expected LTS mask 后做 equality compare。
不能因为某个私有 FB engine callback 可能在内部读取 topology，就把 generic
`StateLoad == NV_OK` 重命名为 L2 adoption proof。

## 3. 启动后可以读取 B，但读取与比较是两回事

### 3.1 公开接口的语义

**FACT。** `NV2080_CTRL_CMD_FB_GET_FS_INFO` 的 type 3 为
`NV2080_CTRL_FB_FS_INFO_LTS_MASK`。输入是 `fbpIndex`，输出是该 FBP 内把所有 LTC
的 LTS 位 flatten 后的 `ltsEnMask`：

- `ctrl2080fb.h:2021..2033`：type-3 参数；
- `ctrl2080fb.h:2284..2341`：query enum 与 batch 结构；
- `ctrl2080fb.h:2343..2359`：control 与返回 status。

一个 query 的 `status == NV_OK` 只说明该 query 成功处理。结构中没有 expected
mask 字段，所以该 control 本身也不做“实际值是否等于某次请求值”的判断。

### 3.2 GB202 的实际 endpoint

**FACT（来自既有小窗口归档）。** `parallel/gb202_getfsinfo_support.md` 已闭合：

- physical GSP export 中存在真实 `GET_FS_INFO` handler；
- non-MIG type-3 分支调用 FB vtable `+0x9c0`；
- GB202 index 65 把 `+0x9c0` 绑定到非 stub getter；
- getter 读取 current/effective LTS-disable view
  `B = 0x822900 + 4*FBP`，裁宽并反相成 enable mask。

因此“启动后有办法问 GSP 当前生效 topology”是 FACT。

### 3.3 没有证据表明 normal boot 自动发这个 GET

**FACT（公开树的有限负搜索）。** 对本地 610.43.03 C/H 树检索：

```text
NV2080_CTRL_CMD_FB_GET_FS_INFO
NV2080_CTRL_FB_FS_INFO_LTS_MASK
ltsEnMask
subdeviceCtrlCmdFbGetFsInfo
```

命中的是：

- public control/header 定义；
- generated export/dispatch；
- vGPU/RPC route 与结构拷贝；
- `subdeviceCtrlCmdFbGetFsInfo_IMPL` 声明。

没有命中 normal boot 中主动构造 type-3 query、保存 expected mask、再比较输出的
callsite。`rpc.c` 对 method ID 的 case 只是把一个已经到来的 control 路由到 RPC，
不是启动端自己发起查询。

这项负结果只覆盖公开 C/H 树，不能排除私有 GSP-RM 内部在建 OBJGPU/FB engine 时
直接调用同一底层 getter。

## 4. direct-shadow success tail 同样没有 post-reset compare

**FACT（既有归档）。** `parallel/shadow_reset_lifecycle.md` 已证明：

```text
reset 前：逐项 raw-shadow readback
  -> reset/reinit callback
  -> 只检查 callback status
  -> cleanup / return
```

可见 success tail：

- 不携带 raw plan 进入 reset callback；
- 不在 reset 后重放 raw plan；
- 不读取 current/effective B；
- 不调用公开 LTS-mask GET；
- 不比较 L2 size/count 或 coarse status；
- 不把一次 reset status 0 与 expected topology 绑定。

所以唯一明确的逐项 equality check 发生在 reset **之前**，对象是 raw shadow
readback；它不是 reset 后的 effective adoption check。

`parallel/raw_effective_propagation.md` 进一步确认：当前可读 host/GSP 成功路径中
没有发现 A-derived B writer/copy/recompute，也没有发现 reset 后的 A/B compare。

## 5. 当前能写出的最窄时序

```text
T0  reset 前 raw state 被读取/检查
T1  提交 reset/reinit；callback 不携带 expected topology
T2  chip reset -> Bootfsm/FSP boot-complete
T3  FSP-assisted GSP bootstrap；检查 lockdown/FMC/RISC-V
T4  GSP_INIT_DONE；payload 只有 bIsD3Hot
T5  CPU-RM 取得不含 LTS topology 的 GSP static info，继续 engine lifecycle
T6  若有调用者显式发 GET_FS_INFO(type 3)，GSP 此时读取/返回 B
```

### 可以确定的边界

- **FACT：** T2..T5 的公开 success checks 都不是 topology compare。
- **FACT：** T6 的 endpoint 读取 effective B，而不是 raw A。
- **FACT：** T6 的 query status 不表示结果符合某个先前 plan，只表示 query 被成功
  处理。
- **UNKNOWN：** 私有 GSP 初始化是否在 T3..T5 之间已经读取 B；即使读了，公开
  host 也没有拿到 expected/actual pair。
- **UNKNOWN：** B 在 T2、T3、T4 还是稍后才稳定可读。

## 6. 公开材料看不到的来源与动作

### 6.1 FSP/GFW 内部

公开 OpenRM 给出 FSP mailbox transport、boot wait 与 command-response plumbing，
但没有 GB202 FSP runtime 的 floorsweep consumer，也没有：

- raw A 到 effective B 的计算函数；
- reset 边沿上的 source-select/sense routine；
- L2-specific post-reset validation response；
- 把 expected raw plan 返回给 host 的 schema。

### 6.2 私有 GSP-RM FB/Fuse 初始化实现

公开 host tree 有 control ABI 和 RPC route，但物理 GSP 中 FB/Fuse engine 的完整
初始化源码不在树中。既有小窗口能证明 getter 与 handler，却不能仅凭 getter 存在
还原整个 normal-boot object-aware caller graph。

因此以下两种情况目前都相容：

1. GSP 初始化时读取 B，用它建立内部 topology，但只把“初始化成功/失败”作为总体
   status 返回；
2. 更低层的 FSP/GFW/hardware 已经建立 topology，GSP 初始化只消费其它派生表，
   直到显式 query 才直接读取 B。

### 6.3 hardware reset/sense/rollup

公开寄存器 metadata 能给出地址和字段，不能给出：

- latch/raw/B 各自属于哪些 reset domain；
- hot/boot/fuse/base 各自 retain、clear、sample 或 recompute 什么；
- A 到 B 是 identity、pair expansion、与实体 fuse 合并，还是还叠加 repair/SKU
  policy；
- topology 不自洽时硬件是拒绝启动、回退到较小 mask，还是只记录诊断。

### 6.4 VBIOS、签名固件与 repair provenance

当前公开 host success contract 也没有披露 VBIOS/FSP/repair 状态如何参与最终 B，
更没有给出每个 disabled bit 的来源或健康信息。一个正常返回的 effective mask 只是
当前 active topology，不是 provenance 或物理健康证书。

## 7. FACT / INFERENCE / UNKNOWN 汇总

| 问题 | 判定 | 等级 |
|---|---|---|
| FSP 启动后是否检查 boot-complete？ | 是 | **FACT** |
| GSP 启动后是否检查 lockdown/FMC/RISC-V/INIT_DONE？ | 是 | **FACT** |
| `INIT_DONE` 是否携带 L2 mask/count/size？ | 否，公开 payload 只有 `bIsD3Hot` | **FACT** |
| `GET_GSP_STATIC_INFO` 是否携带离散 LTS topology？ | 否 | **FACT** |
| generic `gpuStateLoad` 是否检查 engine callback status？ | 是 | **FACT** |
| generic `gpuStateLoad` 是否显式比较 raw/effective L2？ | 公开函数体没有 | **FACT** |
| 启动后是否存在读取 effective B 的正式接口？ | 是，`GET_FS_INFO/LTS_MASK` | **FACT** |
| type-3 handler 是否读 GB202 effective B？ | 是，既有小窗口已闭合 | **FACT** |
| normal boot 是否自动调用 type 3？ | 公开 C/H 树未见；私有 GSP 内部未知 | **有限负证据 / UNKNOWN** |
| reset success tail 是否自动比较 post-reset B？ | 否 | **FACT** |
| query success 是否证明 B 等于某个 expected plan？ | 否；query 没有 expected 字段 | **FACT** |
| 私有 GSP 初始化是否有内部 topology sanity check？ | 当前看不到 | **UNKNOWN** |
| FSP/GFW/hardware 是否执行 A→B？ | 当前看不到 | **UNKNOWN** |
| 启动成功是否可能只是接受了一个降级 topology？ | 与现有事实相容，但未证明 | **INFERENCE / UNKNOWN** |

## 最终可引用结论

> GB202 的公开 610 启动链会验证 FSP boot-complete、FMC/lockdown、GSP RISC-V
> active、GSP INIT_DONE 和各 engine `StateLoad` 返回码；这些都是启动/生命周期
> 检查，不是 L2 topology adoption compare。`GSP_INIT_DONE` 只返回
> `bIsD3Hot`，`GspStaticConfigInfo` 也不含 FBP/LTC/LTS mask、LTS count 或 L2
> size。启动完成后，物理 GSP 确有 `GET_FS_INFO/LTS_MASK` 路径可读取 GB202 的
> current/effective `0x822900+4*FBP` view，但公开 C/H 树没有 normal boot 自动发
> 该 query、保存 expected mask 并比较输出的 callsite；direct-shadow success tail
> 同样只做 reset 前 raw readback，reset 后不比较 B。因此当前只能证明“启动成功后
> effective topology 可被另行查询”，不能把任何一个 boot/reset success status
> 当成“post-reset effective L2 已按期望采纳”的验收证明。私有 GSP/FSP/GFW 与
> hardware sense/rollup 内部是否另有自洽检查，仍为 UNKNOWN。

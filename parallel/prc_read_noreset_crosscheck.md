# MODS 570.151 `-fsp_prc_read`：host 显式写入/reset 交叉审计

Status: **final, bounded static-only cross-check**  
Date: 2026-07-21

## 范围与结论口径

本轮只读以下本地材料：

- `mods_audit/static/extracted_inner/mods`
  - ELF64 x86-64；
  - SHA-256
    `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- `mods_audit/static/decoded/all/gpuargs.js`。

只对下列地址窗口做了限界 `objdump`/`readelf`/`rg` 复核：

- PRC read map executor `0x185f500..0x185f59f`；
- PRC read helper `0x185ea20..0x185eb64`；
- common FSP sender 的相关窗口 `0x185e260..0x185e690`、
  `0x185e890..0x185ea20`；
- `Gpu::Initialize` 的相关窗口 `0xda34e0..0xda3e30`、
  `0xda5d80..0xda5ed0`；
- late read fallback `0xd9d760..0xd9e0d0`（正常返回在
  `0xd9db86`，其后为该函数的清理/异常分支）；
- late write fallback 对照窗口 `0xd9c390..0xd9ca70`。

没有执行 MODS，没有访问 GPU、设备节点、BAR/MMIO、PCI config 或 debugfs，
没有 reset、驱动/模块操作或提权；也没有修改主报告。

本文使用：

- **FACT**：上述文件与限定窗口直接支持；
- **INFERENCE**：事实支持但缺少 FSP consumer/实际 vtable 或运行态证据；
- **UNKNOWN**：当前静态材料不能回答。

## 结论摘要

| 问题 | 结论 | 等级 |
|---|---|---|
| `-fsp_prc_read` 是否调用 PRC writer | read executor 只解析 knob ID、发送 read、保存结果；未调用 task `13` writer | **FACT（可见 host 路径）** |
| read map 是否进入 `Gpu::Initialize` 的 post-FS reset 汇总 | `Gpu+0x1e0` read-map guard 没有进入汇总；`Gpu+0x1b0` write-map guard 明确进入 | **FACT** |
| 只有 read map、其他请求标志均为零时，是否由它触发 `+0x3c8` reset | 不会；read call 返回后没有置位 reset-summary local | **FACT（条件化 data-flow）** |
| late read fallback 是否显式 reset | 正常控制流只到 `+0x340` reader；未见 `+0x1b0`/`+0x3c8` reset call | **FACT（限定函数）** |
| late writer 对照 | `+0x338` 成功后立即以 state `3` 调 `+0x1b0` | **FACT** |
| 因此运行 MODS read 是否安全 | 不能推出。read 仍向 FSP 发命令；整个 GPU 初始化还有其他不透明调用、条件 reset 和独立 task-2/FS 生命周期 | **UNKNOWN / 不得据此执行** |

最窄、准确的结论是：**在已见 host 语义控制流中，PRC read map 本身没有调用
PRC 写入器，也没有给 post-FS reset 汇总置位；这绝不等于“没有任何 device-side
写流量”，更绝不等于可以在承担桌面的 5090 上安全运行 MODS。**

## 1. CLI 只构造 read map

解码 JS 的直接事实：

- `g_FspPrcReadArray` 与 `g_FspPrcWriteArray` 分别初始化为空数组；
- `ArgFspPrcRead()` 只把大写后的 knob 名称压入 read array；
- `HandleGpuPreInitArgs()` 只在对应数组非空时分别调用
  `Gpu.SetFspPrcReadInfo()` / `Gpu.SetFspPrcWriteInfo()`。

因此，**FACT（可见 JS 前端）**：单独的 `-fsp_prc_read` 不会由这个参数回调顺带
构造 write map。这个结论不排除整个程序的其他默认初始化动作或未见私有入口。

## 2. `0x185f500`：read executor 只保存回读值

`0x185f500` 遍历传入的 `std::map`：

1. `0x185f56b..0x185f57e` 把 node `+0x20` 的名称交给 `0x1858280`，
   解析为数值 knob ID；
2. `0x185f520..0x185f535` 调 `0x185ea20` 读取该 ID；
3. 成功后打印结果，并在 `0x185f557` 把返回的 32-bit zero-extended value
   存入 map node `+0x40`；
4. 任一步失败即把错误码向上传播，全部成功则返回零。

**FACT：** 此函数没有调用 `0x185ef60` PRC write executor、task-13 sender、GPU
reset vtable slot 或 register writer。它确实写了 host 进程内的 map result，这不
是 GPU 状态写入。

## 3. `0x185ea20`：wire 编码与 response 宽度

### 3.1 请求

`0x185ea20` 将传入 `esi` 的低 16 位拆成两个 byte，按低字节在前构造 2-byte
request vector；高 16 位不会进入该 request。随后在
`0x185ea92..0x185eab7` 调 common sender `0x185e9b0`，参数为：

```text
task/type       = 0x0c  (12)
submessage      = 0x02
request         = 2-byte knob ID
response vector = caller-provided empty vector
```

task-2 路径在同一 sender ABI 上以 `esi=2, edx=1` 表示 task 2/subobject 1；writer
也以 `esi=0x0d, edx=2` 进入同一 ABI。因此把这里记作 **PRC read task 12 /
submessage 2** 是 **FACT（当前 MODS host 编码）**。

### 3.2 返回

发送成功后，`0x185eaf8..0x185eb0f`：

- 要求 response vector 的总长度**严格等于 4 bytes**；
- 只执行 `movzx eax, WORD PTR [rdi]`，即读取前 2 bytes；
- 将这个 16-bit 值 zero-extend 后写进 caller 的 32-bit output；
- 其余 2 response bytes 在该函数里没有被读取；
- response 长度不是 4 时返回 `0x12e`。

所以必须区分两个“宽度”：

- **FACT：协议 response frame 在此处必须是 4 bytes；**
- **FACT：host 暴露/保存的 knob value 是其中前 16 bits。**

`0x185ea82..0x185eac7` 还会暂时把 FSP manager host object 的 byte `+0x68`
清零，并在所有可见返回路径恢复原值。这是 host 对象内存变化。common sender
在 `0x185e632..0x185e65e` 经 transport vtable `+0x38` 发 packet，随后
`0x185e9e8..0x185ea0c` 经 `+0x30` 取 response；因此该路径不是“完全无写流量
的被动内存读取”。

**FACT（可见语义）：** helper 没有 task 13、PRC knob write 或 reset call。

**UNKNOWN：** FSP 在处理 read packet 时是否更新内部计数、会话、权限状态或
其他固件状态；host binary 看不到 consumer，不能用命令名 `Read` 排除这些副
作用。

## 4. early `Gpu::Initialize`：read map 不进入 reset summary

### 4.1 read 与 write 的两个 guard

在 feature `0xdb` 可用的路径中：

```text
0xda39ba  test [Gpu+0x1e0] read-map nonempty
0xda39d2  call GpuSubdevice vtable +0x340 (read)

0xda39e4  test [Gpu+0x1b0] write-map nonempty
0xda39f8  call GpuSubdevice vtable +0x338 (write)
```

两者的非零返回都会直接走 error exit。write 成功后，
`0xda3a06..0xda3a0d` 才把 feature-`0xdb` local `-0x258` 复制到 local
`-0x248`；read 成功后没有对应 store。

### 4.2 reset-summary local `-0x262`

`0xda373d..0xda37ac` 在 PRC calls **之前**构造 post-FS reset summary byte
`[rbp-0x262]`。其可见输入为：

- boolean locals `-0x216/-0x215/-0x214/-0x213`；
- dword locals `-0x1fc/-0x208/-0x204`；
- `r14d` 中的另一个初始化请求 boolean；
- **`[Gpu+0x1b0] != 0`，即 PRC write map；**
- 另组请求 locals `-0x250/-0x261/-0x248`。

精确到 data-flow：只有当前面的 bool/dword 条件都未先置位时，
`0xda3780..0xda3788` 才以 `[Gpu+0x1b0] != 0` 生成 `al`；随后它或已有的
非零请求值最终汇入 `-0x262`。在这个汇总窗口中**没有读取
`[Gpu+0x1e0]` read map**。

之后的 read call `0xda39d2` 也没有写 `-0x262`。因此：

- **FACT：** write map 是 post-FS reset summary 的一个输入；
- **FACT：** read map 不是该 summary 的输入；
- **FACT（条件化）：** 若上述其他请求输入全为零且只有 read map 非空，
  read map 自身不会把 `-0x262` 从零变为非零。

### 4.3 reset gate

`0xda3c91..0xda3cc2` 的逻辑为：

1. `-0x262 == 0`：跳过 `+0x3c8`；
2. `-0x262 != 0`：继续；
3. `-0x248 != 0` 时才检查全局 `SkipPrcReset`；该全局为真则跳过；
4. 否则以 `esi = byte[-0x261]` 调 GPU subdevice vtable `+0x3c8`。

write map 成功后对 `-0x248` 的 store 会影响第 3 步，但“是否需要 reset”的
第一层判断仍是更早生成的 `-0x262`。read map没有置位二者。

**FACT（路径限定）：** read helper 报错时从 `0xda39da` 直接走 error exit，
不会继续到这个 post-FS reset block。

**重要限定：** 同一个 `Gpu::Initialize` 的更早窗口
`0xda351a..0xda353e` 还有一个由其他 locals 控制的 `+0x1b0(state 4)` reset。
因此“read map 不触发 post-FS reset”不能扩张为“整个 MODS 初始化绝无 reset”。

## 5. late fallback：reader 与 writer 的非对称性

### 5.1 caller 顺序

`0xda5e2d..0xda5e69` 明确显示：

1. read map `[Gpu+0x1e0]` 非空时先调用 `0xd9d760`；
2. 成功后再检查 write map `[Gpu+0x1b0]`；
3. write map 非空才调用 `0xd9c390`。

因此 read map 不会因这个 caller 自动转成 write map。

### 5.2 `0xd9d760` reader

late reader 枚举 GPU objects。对每个候选：

- vtable `+0x198` 的 GPU kind 必须等于 `4`；
- feature `0xdb` 必须为真；
- `+0x1d8` 若正是默认 false stub `0xd967c0`，直接进入 read；若不是，
  调该 predicate，返回 false 时进入 read、true 时跳过；
- read 点 `0xd9d9b5..0xd9d9c8` 调 vtable `+0x340`，参数为
  `Gpu+0x1b8` read-map object。

在 `0xd9d760..0xd9db86` 的正常可达控制流中，前面的 `+0x198`、`+0x48`、
`+0x1d8` 是类型/feature/predicate 查询；与 PRC map 执行相关的调用只有
`+0x340`。未见 `+0x338` writer、`+0x1b0` 或 `+0x3c8` reset。错误只被传播，
正常结束返回零。清理/异常分支到约 `0xd9e0c7` 也未出现上述 reset slot。

这是 **FACT（限定 host 函数）**，但非默认的 `+0x1d8` predicate 实现本身是否
有隐藏副作用仍是 **UNKNOWN**；当前 caller 只把它当 boolean gate。

### 5.3 `0xd9c390` writer 对照

writer 的对应路径形成鲜明对照：

```text
0xd9c5f1..0xd9c604  call vtable +0x338 (write map)
0xd9c606..0xd9c619  on success, call vtable +0x1b0 with state 3
```

因此 **FACT：** late writer 有显式 reset，late reader 没有同构 reset tail。

## 6. 为什么不能把结论写成“只读 MODS 安全”

以下边界必须保留：

1. **FACT：read 会发送 FSP packet。** packet 构造、transport send、channel
   状态以及 response completion 不是“CPU 只读一个普通文件”；即使命令的业务
   语义是 read，通信本身也会改变 transport/device communication state。
2. **FACT：整个 GPU 初始化不是 read helper。** `Gpu::Initialize` 还有大量
   virtual/firmware calls、条件 reset、FS/task 生命周期；本报告只证明 read map
   不进入一个具体 reset summary，不证明其他默认或并存路径不会改变设备状态。
3. **INFERENCE（结合已独立完成的 task-2 生命周期审计）：** 初次普通
   FSP-enabled 初始化即使没有 floorsweep 参数也可能发送独立的 task 2；它与
   PRC read 不是同一请求，不能由本报告排除固件/PLM 状态变化。
4. **UNKNOWN：** read task 的 FSP consumer、零售 GB202 策略、超时/error recovery
   和非默认 vtable predicate 的内部副作用。
5. **FACT（环境事实）：** 目标 5090 当前承担桌面。即使狭义 read path 没有显式
   reset，也不能在这种环境中把未签名、未验证的 MODS 当作安全查询工具。

## 最终判定

- **FACT：** `-fsp_prc_read` 的可见 native reader 是 task/type `0x0c`、
  submessage `2`；request knob ID 为 16-bit，小端；raw response 必须为 4 bytes，
  但 host 只使用前 16-bit value。
- **FACT：** early init 的 PRC write map进入 reset summary，PRC read map不进入；
  只有 read map且所有其他请求 flag 为零时，该 map 本身不触发 `+0x3c8`。
- **FACT：** late reader未见显式 reset，late writer成功后明确执行 state-3 reset。
- **INFERENCE：** host 设计意图显然把 read 当作不需要 PRC reset 的查询，把 write
  当作需要 reset/reinit 的动作。
- **UNKNOWN：** FSP 处理 read 时的内部副作用，以及运行完整 MODS 初始化时所有
  其他路径的设备影响。

因此，本报告只能支持：**“host 未见由 PRC read map 直接触发的语义写入或
reset”**。它不能支持：**“运行 `-fsp_prc_read` 无害”**，也不能作为在当前桌面
5090 上执行 MODS 的授权或安全依据。

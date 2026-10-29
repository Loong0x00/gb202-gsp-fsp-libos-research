# MODS `-fsp_prc_read`：host 可见 reset/写入静态审计

日期：2026-07-21  
状态：本地主审完成，独立交叉审计一致

## 范围与安全边界

本轮只读取 MODS 570.151 已提取 ELF、已解码 JS 和既有静态报告。使用的 ELF 为
`mods_audit/static/extracted_inner/mods`，SHA-256
`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`。
只查看下列有限反汇编窗口，没有执行 MODS，没有访问 GPU、设备节点、PCI/BAR/
MMIO 或 debugfs，也没有 reset、驱动、固件、模块或电源操作。

本报告只回答“当前 host 可见路径是否显式请求 reset/PRC write”。它**不回答**
运行 MODS 是否安全：所谓 PRC read 仍会初始化 GPU 并向 FSP 发送内部消息；FSP
consumer、固件副作用和错误恢复不在可见 host ELF 中。

独立限定窗口复核见 `parallel/prc_read_noreset_crosscheck.md`；它分别重做了
request/response 编码、early reset-summary data-flow 和 late reader/writer
对照，得到相同结论。

## 结论摘要

| 问题 | 结论 | 等级 |
|---|---|---|
| JS 是否默认发起 PRC read | 否；read array 默认空，只有显式 `-fsp_prc_read` 才 push | **FACT（可见 JS）** |
| read wire shape | task `12`、submessage/object `2`，request 为 2-byte knob ID，成功 response body 必须恰为 4 bytes，取首个 `u16` 为 knob value | **FACT（host ABI）** |
| read executor 是否发送 PRC write | 未见；它逐项解析名称、调用 read helper、把值存回 map node | **FACT（限定函数）** |
| early read map 是否进入 post-FS reset 汇总 | 不进入；write map和其他 mutation flags会进入，read map本身不会 | **FACT（host control flow）** |
| late fallback reader 是否显式 reset | 未见；它调用 `+0x340` reader，兄弟 writer则在 `+0x338` 后明确调用 `+0x1b0(state=3)` | **FACT（限定 host 路径）** |
| 因而能否在当前桌面安全运行 MODS read | 不能推出；MODS 初始化、首次 task 2、内部 FSP request和不可见固件行为仍存在 | **UNKNOWN / 不执行** |

## 1. JS 入口不是自动注入

`mods_audit/static/decoded/all/gpuargs.js` 中：

- `:252` 把 `g_FspPrcReadArray` 初始化为空数组；
- `:1711` 注册 `-fsp_prc_read`；
- `ArgFspPrcRead()` 在 `:16490..16493` 只把用户给出的 knob 名称 push 进数组；
- `HandleGpuPreInitArgs()` 在 `:7367..7369` 只在数组非空时调用
  `Gpu.SetFspPrcReadInfo()`。

因此普通无该参数的可见 JS 前端不会生成 read map。该结论不覆盖私有脚本、动态
native caller 或 FSP 内部默认动作。

## 2. native reader 的精确协议形状

### 2.1 map executor `0x185f500`

`0x185f500..0x185f59e` 遍历 read map：

1. `0x185f56b..0x185f57e` 调用 `0x1858280`，把 knob 名称解析成数值 ID；
2. `0x185f520..0x185f535` 调用 `0x185ea20` 读取该 ID；
3. `0x185f539..0x185f557` 打印并把结果写入 map node `+0x40`；
4. 任一步出错便返回，遍历完成返回 0。

在这个限定函数中没有 task-13 writer、reset 方法或已知 PLM/MMIO setter。

### 2.2 read helper `0x185ea20`

`0x185ea20..0x185eb63` 的 host ABI 可直接还原：

- `0x185ea3d..0x185ea7d` 把 16-bit knob ID 组为 2-byte request；
- `0x185ea9c..0x185eab7` 以 `rsi=0x0c`、`rdx=2` 调用 common request/response
  helper `0x185e9b0`，即 task `12`、submessage/object `2`；
- `0x185eaf8..0x185eb04` 要求 response body 长度恰为 4 bytes，否则返回
  `0x12e`；
- `0x185eb06..0x185eb0b` 读取 response 首个 `u16` 并写入 caller 的 32-bit
  输出槽。后两个 response bytes在该 helper中不被解释。

task-to-QCAP mapper `0x1857b10` 的 bitmask `0x4713e` 包含 task 12，因此它与
task 2/13 一样映射到 QCAP key `0x13`。这说明 read 仍属于 FSP PRC 消息族；它
不是本地缓存查询。`0x185ea82..0x185eac7` 还会临时改动 MODS 的 host FSP 对象
byte `+0x68`，调用结束后恢复，这不是 GPU reset，但再次说明它是主动协议事务。

公开 GH100 源码里另一个特定 PRC query 的 response body也由 `NvU16 knobValue`
和 `NvU16 misc` 构成，能作为这 4-byte shape 的协议旁证；该公开 caller只绑定
GH100，不能证明任意 GB202 knob 的支持或安全性。

## 3. `Gpu::Initialize`：read map本身不置 reset 汇总

在 `Gpu::Initialize` 的限定窗口中：

- `0xda39ba..0xda39da` 仅在 read map `[Gpu+0x1e0]` 非空时调用
  `GpuSubdevice+0x340`，失败直接走错误出口；成功后未修改本轮 reset/mutation
  汇总 local；
- `0xda39e4..0xda3a0d` 对 write map `[Gpu+0x1b0]` 调用 `+0x338`，成功后明确把
  FSP-path local `[rbp-0x258]` 复制到 reset-request local `[rbp-0x248]`；
- 更早的 `0xda373d..0xda37ac` 构造 aggregate request byte
  `[rbp-0x262]` 时会检查 write map `Gpu+0x1b0`（`0xda3780`），但不检查 read map
  `Gpu+0x1e0`；
- post-FS reset `GpuSubdevice+0x3c8` 位于 `0xda3c91..0xda3cc2`，首先要求该
  aggregate request byte 非零。

所以在“只有 PRC read map、没有其他 FS/PRC-write/fusing/reset 请求”的限定
host 路径上，read map本身不会使 `0xda3cba` 的 post-FS reset可达。若同时存在
其他 mutation 请求，reset仍可由那些请求触发；不能把结论写成“带 read 参数的
整个 MODS 初始化绝不会 reset”。

## 4. late fallback：reader/writer 的不对称是直接证据

`Gpu::Initialize` 尾部 `0xda5e2d..0xda5e69` 先在 read map非空时调用
`0xd9d760`，随后若 write map非空才调用 `0xd9c390`。

reader `0xd9d760` 的目标设备分支在 `0xd9d970..0xd9d9c8`：要求 device type
返回 4、检查 feature `0xdb`，再经 `+0x1d8` HAL predicate/默认路径进入
`GpuSubdevice+0x340`。限定函数的可见核心路径没有 `+0x1b0`、`+0x1a8` 或
`+0x3c8` reset调用。

兄弟 writer `0xd9c390` 在相同 device/feature/HAL 形状下，于
`0xd9c5f1..0xd9c604` 调用 `+0x338`；成功后立刻在
`0xd9c606..0xd9c619` 调用 `+0x1b0(state=3)`。因此“late reader未显式 reset”
不是仅凭函数名猜测，而有同构 writer 的明确反例作校准。

这仍是 host-visible negative。动态 vtable predicate、FSP firmware、driver
初始化或错误恢复的不可见行为，不能由“reader函数里没有reset槽调用”排除。

## 5. 对安全设计的实际含义

当前可以把 `-fsp_prc_read` 归类为：**host 可见控制流中没有专门的写-knob或
显式 reset收尾，但会发送内部 FSP read transaction的路径**。它不是“纯本地、
无副作用的寄存器读取”。

尤其是，运行完整 MODS还会经过 GPU初始化；既有静态证据表明正常、首次、
FSP-enabled且未设置 `SkipFspFs` 的无-floorsweep参数路径仍可能发送 task
2/subobject 1。当前没有公开 GB202 consumer能证明该初始化序列、PRC read或
失败路径对正在承担桌面的卡无副作用。因此本轮结论只帮助以后设计隔离环境中的
验证顺序，**不构成在当前 5090/桌面会话上执行 unsigned MODS的许可**。

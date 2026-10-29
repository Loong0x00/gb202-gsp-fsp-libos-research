# PRC `0x1d` / floorsweep task 2：公开源码有限审计

> 文件名保留了早期误判的 `1c`，正文已按 0x28-byte MODS knob record 纠正：
> floorsweeping one-shot 是 `0x1d`，`0x1c` 是 `RPR_ALLOW_INB`。记录证据见
> `parallel/prc_knob_metadata.md`。

日期：2026-07-21

## 范围、来源与安全边界

本轮只读取：

- 本地 NVIDIA Open GPU Kernel Modules 610.43.03 源码树：
  `/usr/src/nvidia-610.43.03`；
- 项目中已有的纯文本、头文件和脚本，用于判断是否已有公开定义；
- NVIDIA 官方 GitHub 仓库的 tag/HEAD、原始源码文件与 commit 元数据。

没有分析或执行 MODS 二进制，没有读取本机 GPU、设备节点、BAR/MMIO、PCI
config 或 debugfs，没有发送 RM/FSP 请求，也没有 reset、驱动、固件或电源操作。
本报告不修改主报告。

来源完整性：

- 本地 `version.mk:1-2` 与 `README.md:1-4` 均标明 `610.43.03`；
- 2026-07-21 查询 NVIDIA 官方仓库时，`main`/`HEAD` 都是 commit
  `452cec62d827034798072827d3866d1881662b77`，它也是 tag `610.43.03`
  的 peeled commit；
- 本报告用到的三个关键本地文件与该官方 commit 的 raw 文件 SHA-256
  逐字节一致：
  - `kern_gpu_gh100.c`：
    `d8794fb681f00d63bf46f2c1368ebde897e8b0710c586b0b6b3ec4053ee98b16`
  - `g_gpu_nvoc.c`：
    `4b4b35072f93d136c5478e49e48e9bc39163c1e2eb157b4bc65fcf4f975886ae`
  - `nvdm_format.h`：
    `e1744a9f031a6fc2d99d8510e6310c8cfa9b70933629c4703097a8b4f7b835da`

官方固定版本链接：

- [`kern_gpu_gh100.c`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/src/kernel/gpu/arch/hopper/kern_gpu_gh100.c)
- [`g_gpu_nvoc.c`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/generated/g_gpu_nvoc.c)
- [`nvdm_format.h`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/452cec62d827034798072827d3866d1881662b77/src/nvidia/arch/nvalloc/common/inc/nvdm_format.h)

## 结论先行

| 问题 | 公开 610.43.03 的结论 | 证据等级 |
|---|---|---|
| 是否公开定义 `PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT`？ | 没有；精确 token 及其三个稳定子串均为零命中 | **FACT（限定当前 C/H 树的精确负结果）** |
| 是否公开把 PRC knob ID `0x1d` 绑定到 floorsweep？ | 没有；当前公开树没有该 ID/name 绑定 | **FACT（限定当前树）** |
| 是否公开定义 floorsweep `task 2/subobject 1`？ | 没有；精确文本 `task2`、`task 2`、`subobject1`、`subobject 1` 均为零命中 | **FACT（精确 token absence）** |
| `0x1d` 允许值是什么？ | 未公开；只能证明公开 PRC response 的值槽是 `NvU16`，不能证明合法集合 | **UNKNOWN** |
| 值 `1` 是否意味着允许？ | 只对另一个 GH100 PPCIE knob `0x2d` 有公开定义，不能外推到 `0x1d` | **不同 knob 的类比，不是证据** |
| 谁消费 `0x1d`，何时 self-clear？ | 没有公开 consumer、clear、rearm、expiry 或 restore 实现 | **UNKNOWN** |
| task 2 的权限窗口有多长？ | 通用 response 只有 task/type/error，没有 token、lease、deadline 或 undo handle | **UNKNOWN** |
| 是否有公开的只读 PRC 查询协议？ | 有一条 **GH100-only 内部 RM** 查询作为协议先例 | **FACT（仅 GH100 caller）** |
| 是否有 GB202 绑定或公开用户态接口可读任意 knob？ | 没有；GB202 对该 query HAL 走返回 `NV_FALSE` 的默认 stub，SDK ctrl/interface 中也没有任意 PRC read control | **FACT（当前公开 host 树）** |

因此，本轮没有找到能把 `0x1d` 的 required value、task-2 consumer 或
self-clear/lifetime 从 UNKNOWN 升级的公开证据。新增的真正有用信息是：公开源码
确实泄露了一种 PRC read-object wire shape，但只在 GH100 的特定 PPCIE 检查中
使用，不能直接当成 GB202 的受支持只读接口。

## 1. 精确 token 审计

对以下目录的 `*.c/*.h/*.cpp/*.hpp` 做不区分大小写的精确文本检索：

- `/usr/src/nvidia-610.43.03/src/nvidia`
- `/usr/src/nvidia-610.43.03/src/common`
- `/usr/src/nvidia-610.43.03/kernel-open`

结果为：

```text
PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT  0
FLOORSWEEPING_ALLOW_INB                       0
ALLOW_INB_ONE_SHOT                            0
subobject1                                    0
subobject 1                                   0
task2                                         0
task 2                                        0
```

项目自身除 `mods_audit` 外的源文件/头文件/脚本也没有上述 PRC 名称或
`NVDM_TYPE_PRC` 定义。项目的 Markdown 报告里出现该名称，是另一轮闭源样本
静态分析的二手记录；本轮没有重新读取或验证那个二进制来源，因此它不能被写成
“公开 NVIDIA 定义”。

这组零命中只证明**精确 token 没公开**。它不证明 FSP 固件内部没有数值 ID
`0x1d`、task 2 或同义的枚举，因为当前仓库不含可审计的 FSP runtime consumer
源码。

## 2. 公开 PRC 事实

### 2.1 不应把相邻 NVDM 数值当成 knob 证据

`src/nvidia/arch/nvalloc/common/inc/nvdm_format.h:36-58` 公开：

```c
#define NVDM_TYPE_HULK       0x11
#define NVDM_TYPE_PRC        0x13
#define NVDM_TYPE_FSP_RESPONSE 0x15
#define NVDM_TYPE_UEFI_RM    0x1C
```

这里的 `0x1C` 是顶层 **NVDM message type** `UEFI_RM`。项目目标则是 PRC
payload 内部的 knob ID **`0x1d`**；两者不仅命名空间不同，数值也不同。早期
`0x1c` 误判曾造成一个表面的数值碰撞，记录边界纠正后该碰撞已经消失。公开
`NVDM_TYPE_UEFI_RM=0x1C` 与 floorsweep knob 的存在或语义无关。

同一公开树没有给出 `ALLOW_INB` 的展开。NVLink/NVSwitch 源码中大量出现的
“inband”属于另一协议域，不能据此断定该 PRC 缩写究竟表示 in-band、inbound
还是 NVIDIA 内部其他术语。

### 2.2 唯一显式 GPU PRC caller：GH100 PPCIE 查询

`src/nvidia/src/kernel/gpu/arch/hopper/kern_gpu_gh100.c:541-605` 定义一条
PRC read-object 查询：

```c
typedef struct {
    NvU8  prcObjType;
    NvU8  numBytes;
    NvU16 knobId;
} NVDM_PAYLOAD_PRC_OBJECT_READ;

typedef struct {
    NvU8  messageType;
    NvU32 taskId;
    NvU32 commandNvdmType;
    NvU32 errorCode;
    NvU16 knobValue;
    NvU16 misc;
} NVDM_PAYLOAD_PRC_OBJECT_RESPONSE;

#define NVDM_PRC_PPCIE_READ_OBJECT 0x0C
#define NVDM_PRC_PPCIE_NUM_BYTES   0x02
#define NVDM_PRC_PPCIE_KNOB_ID     0x2D
```

`gpuIsProtectedPcieSupportedInFirmware_GH100()` 将上述 read object 作为
`NVDM_TYPE_PRC` 发给 FSP，并读取 `knobValue`。这直接证明：

1. 至少一个公开 PRC read object 的 object type 是 `0x0c`；
2. 它携带 16-bit knob ID；
3. 此 caller 请求 2-byte value，response 中 value 槽为 `NvU16`；
4. 无效 knob ID 可返回错误，caller 接受 `NV_ERR_INVALID_ARGUMENT`；
5. 对 **PPCIE knob `0x2d`**，源码明确规定“存在且 value == 1”才为 ON。

这些事实没有公开 PRC write-object 格式，也没有给出任意 knob 的合法值枚举。
特别是，“公开 response 是 `NvU16`”只证明传输宽度，不证明 `0x1d` 是 Boolean；
“PPCIE 的 1 为 ON”也不能证明 floorsweep one-shot 的 required value 是 1。

### 2.3 公开错误只覆盖 invalid ID

`src/nvidia/inc/kernel/gpu/fsp/kern_fsp_retval.h:24-29` 只公开一个 PRC 专用
错误：

```c
#define FSP_ERR_PRC_ERROR_INVALID_KNOB_ID 0x1E3U
```

`kern_fsp_gh100.c:1583-1608` 把它映射成 `NV_ERR_INVALID_ARGUMENT`。公开树没有
`INVALID_KNOB_VALUE`、范围表或逐 knob policy。这个负结果不能解读成“任何 16-bit
值都合法”；FSP 也可能用未公开错误或通用错误拒绝具体值。

## 3. 为什么 GH100 read-object 不能直接升级为 GB202 接口

### 3.1 caller 的 HAL 绑定明确排除 GB202

`src/nvidia/generated/g_gpu_nvoc.c:2417-2433` 显示
`gpuIsProtectedPcieSupportedInFirmware_GH100` 只绑定 `ChipHal: GH100`；其余芯片
包括 GB202 都走 `g_gpu_nvoc.h:5443-5445` 的默认 `NV_FALSE` stub。

所以公开源码只证明“GH100 内部 RM 有这个特定 query caller”，不证明：

- GB202 FSP 接受相同 read-object schema；
- GB202 的 knob namespace 与 GH100 相同；
- `0x1d` 在 GB202 存在；
- 当前 GB202 驱动实际发送过 PRC read。

### 3.2 GB202 transport 能路由 PRC，不等于存在公开 caller

`g_kern_fsp_nvoc.c:509-520` 把 GB202 的 `kfspNvdmToSeid` 绑定到 GH100
实现。该实现 `kern_fsp_gh100.c:276-301` 只为 InfoROM 指定 SEID 1，HULK 与
default 都返回 SEID 0；因此 `NVDM_TYPE_PRC` 会落到 default SEID 0。

这证明 GB202 所用通用 FSP transport **具备发送 PRC type 的路由形状**，但不
证明目标 firmware 暴露任意 knob，也不构成 caller/consumer 证据。具体的
`kern_fsp_gb202.c` 只有 110 行，负责 secure-boot completion/error handling；
其中没有 `PRC`、`knob`、`task`、`subobject`、`floorsweep` 或 `one-shot` 命中。

整个 610.43.03 源码中 `kfspSendAndReadMessage(...)` 的显式调用只有四类：

- GH100 PPCIE PRC query；
- GSP-FMC/COT boot；
- GB100 clock-boost capability query；
- GB100 clock-boost command。

唯一 PRC caller 正是 GH100-only 那一条。

## 4. task 2/subobject 1 的公开边界

### 4.1 通用 response 有 `taskId`，没有公开 subobject

`src/nvidia/arch/nvalloc/common/inc/fsp/nvdm_payload_cmd_response.h:35-42`
公开的通用 response body 只有：

```c
NvU32 taskId;
NvU32 commandNvdmType;
NvU32 errorCode;
```

`kern_fsp_gh100.c:455-500` 只记录这三个字段并映射 error code。host parser 没有：

- `subobject` 字段；
- permission token/cookie；
- lease、expiry 或 deadline；
- previous value；
- undo/restore handle；
- self-clear/rearm 状态。

因此公开的 `taskId` 字段只证明 FSP response 能报告“由哪个内部 task 处理”，
不能反向证明 task ID 2 的请求 schema、subobject 1、动作或生命周期。

### 4.2 没有公开 consumer/restore

当前 C/H 树对 `task2`、`task 2`、`subobject1`、`subobject 1` 的精确文本均为零
命中；也没有 `0x8200d0`、`0x8200dc`、`0x8200f8` 的公开静态交叉引用。因而
公开源码不能回答：

- task 2 是否消费 `0x1d`；
- task 2 是否降低 d0/dc，更不能证明它同时处理 f8；
- “one shot”在 dequeue、认证、寄存器动作、host apply、reset 或超时中的哪个
  时点被消耗；
- 失败、重试或 reset 后 knob/window 的状态；
- 是否存在 firmware 内部自动 restore。

项目已有的 host 顺序和 Hopper sibling 旁证仍可支持“task 2 旨在为 d0/dc
floorsweep 写准备权限”的强推断，但本轮公开源码没有提供真正 consumer，不能
把该推断提升为 GB202 firmware 事实，更不能把它延伸到独立的 f8。

## 5. 是否存在可用的公开只读查询接口

### 5.1 有协议先例，没有受支持的 GB202 用户接口

GH100 PPCIE caller 证明“read object -> `knobValue` response”在某个产品路径存在。
但是：

- `kfspSendAndReadMessage()` 是内核 RM 内部 helper，不是公开用户态 ABI；
- 对 `src/common/sdk/nvidia/inc/ctrl`、`src/nvidia/interface` 与 RMAPI 公开接口检索，
  没有 arbitrary PRC read、FSP NVDM passthrough 或 knob query control；
- GB202 没有绑定该 PPCIE query HAL；
- 即使 payload 名为 read，它仍会真实发送 FSP 消息；仅凭公开源码不能承诺对
  未公开 knob ID 的请求无副作用或不会触发错误恢复路径。

所以当前没有可推荐的“官方、GB202、任意 knob、只读且已知无副作用”查询入口。
本报告也没有尝试构造或发送任何请求。

### 5.2 公开源码仍能给未来纯静态核对提供什么

若将来出现 NVIDIA 官方的新源码或文档，最有判别力的目标 token/结构是：

1. `PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT` 或与 ID `0x1d` 的显式绑定；
2. PRC write/read object 的共享公共头文件，而不是 GH100 C 文件中的局部 struct；
3. per-knob allowed-value schema；
4. task/subobject dispatcher 及 task 2 consumer；
5. consume/clear/rearm/restore 的状态机；
6. 一个明确绑定 GB202 的只读 HAL 或公开 RM control。

## 6. 最终证据分级

### FACT

1. 610.43.03 当前官方主线公开 `NVDM_TYPE_PRC=0x13`。
2. 精确 floorsweep one-shot 名称、task2/subobject1 token 没有公开。
3. 公开 `0x1C` NVDM 常量属于 UEFI_RM，不是 PRC knob。
4. GH100 有特定 PPCIE PRC read-object caller；read object type `0x0c`、value
   width 2 bytes、knob ID `0x2d`，且该 knob 的 `1` 表示 ON。
5. 该 caller 的 HAL 只绑定 GH100；GB202 走默认 false stub。
6. GB202 通用 FSP transport 对 PRC type 走 SEID 0，但没有公开 PRC caller。
7. 通用 response 有 task/type/error，没有 subobject、lease 或 restore 字段。
8. 公开 SDK/RM control headers 没有任意 PRC read passthrough。

### 仅能类比

1. PPCIE knob `0x2d` 的值 1 语义不能迁移到 floorsweep knob `0x1d`。
2. `NvU16 knobValue` 只给出传输宽度，不给出合法值集合。
3. GH100 read-object 格式不能自动视为 GB202 firmware ABI。
4. project report 中的 one-shot 名称只能提示“可能有一次性授权”，不能确定消费
   点或 self-clear 行为。

### UNKNOWN

1. `0x1d` 在 GB202 的存在性、默认值、required value 与合法值集合；
2. `ALLOW_INB` 的官方展开；
3. task 2/subobject 1 的公开 wire schema 与 FSP consumer；
4. d0/dc/f8 的实际修改；
5. permission lifetime、self-clear、failure/retry/reset 语义；
6. firmware 内部 restore/undo；
7. 任意未公开 PRC read 在 GB202 上是否无副作用。

本轮公开源码审计的实际结论不是“已经知道怎么设置 `0x1d`”，而是把一条容易
误用的旁证降到了正确位置：**公开 GH100 query 证明 PRC 可有 read-object，但没有
公开 GB202 floorsweep knob 的值、consumer 或安全查询接口。**

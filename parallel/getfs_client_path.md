# `GET_FS_INFO/LTS_MASK` 最小用户态 RM client 路径审计

日期：2026-07-21  
状态：静态接口审计完成；未访问 `/dev/nvidia*`，未发出任何 RM control

## 结论先行

可以在 **不运行 MODS、不卡入其初始化链** 的前提下取得一份
`NV2080_CTRL_CMD_FB_GET_FS_INFO / LTS_MASK` effective-topology baseline。
最小可见对象链是：

```text
open /dev/nvidiactl
  -> allocate userspace RM client
  -> allocate NV01_DEVICE_0 for the selected RM device instance
  -> allocate NV20_SUBDEVICE_0
  -> GET_FS_INFO(FBP_MASK)
  -> GET_FS_INFO(LTS_MASK for each enabled FBP)
  -> free client tree and close /dev/nvidiactl
```

不需要 MODS、security level 4/5、HULK、PLM 解锁、寄存器接口、BAR/MMIO，
也不需要打开 `/dev/nvidia0` 或调用 `NV_ESC_REGISTER_FD`。

但“只读”要限定为 **不改 topology、handler 是读取 effective 状态**。建立和
销毁 handle 仍会改变每进程的 RM/GSP 对象账本；该 control 的 export flags 也
没有 `API_LOCK_READONLY` 和 `NO_GPUS_ACCESS`，所以它会走物理 GSP、拿锁并访问
GPU。它不是“完全不触碰设备/不可能唤醒电源状态”的接口。

现有 `gb202_fs_probe.c` 的 control ABI 和 LTS 查询布局可以复用，但它的
`reader_open()` **不应原样复用**：当前代码额外打开 `/dev/nvidia0`，而实际设备
节点的首次 open 可以进入 `nv_start_device()` / `rm_init_adapter()`。为得到边界
更干净的 baseline，应删掉 card fd 和 `NV_ESC_REGISTER_FD`，只保留
`/dev/nvidiactl` 上的 client/device/subdevice 分配与 GET control。

## 审计边界

本轮只读检查：

- 本机 610.43.03 OpenRM 源码与随附 control/class headers；
- 本机已安装 `libnvidia-ml.so.610.43.03`、`libnvidia-cfg.so.610.43.03`、
  `libcuda.so.610.43.03`、`libnvidia-api.so.1` 的动态符号表；
- 项目中的 `gb202_fs_probe.c`；
- 既有静态 GSP handler 审计 `parallel/gb202_getfsinfo_support.md`。

未打开设备节点，未运行/编译/加载探针，未调用 control，未读取 live GPU，未
运行 MODS，未 reset/rebind/unload，也未写寄存器、固件或 VBIOS。

## FACT

### 1. 用户态调用不因写了 `NV01_ROOT` 而得到 root client 权限

`NV_ESC_RM_ALLOC` 的 Unix ioctl 入口把用户态传来的 `NV01_ROOT`、
`NV01_ROOT_CLIENT` 和 `NV01_ROOT_NON_PRIV` 都强制改成
`NV01_ROOT_CLIENT`（`escape.c:452..475`）。安全级别来自 ioctl 当时的
`osIsAdministrator()`，普通用户得到 `RS_PRIV_LEVEL_USER`
（`escape.c:372..381`）。

因此现有探针：

```c
NVOS21_PARAMETERS root = { .hClass = NV01_ROOT };
```

只是请求一个普通 userspace RM client handle；它不是 MODS 的 privileged root，
也不会绕过 control 权限检查。

`NV01_DEVICE_0` 与 `NV20_SUBDEVICE_0` 的 resource entries 都带
`RS_FLAGS_ALLOC_NON_PRIVILEGED`、`RS_FLAGS_ACQUIRE_RO_API_LOCK_ON_ALLOC`，且
required access rights 为 `RS_ACCESS_NONE`
（`resource_list.h:175..183,482..490`）。只要 Unix 设备节点权限允许，建立这两
层对象本身不要求管理员身份。

### 2. 最小 handle 层级确实是 client -> device -> subdevice

`GET_FS_INFO` 是 `NV20_SUBDEVICE_0` 的 exported method；其 control 的
`hObject` 必须是调用 client 所拥有的 subdevice handle。公开 RM helper
`rmapiutilAllocClientAndDeviceHandles()` 也采用相同顺序：client、
`NV01_DEVICE_0`、`NV20_SUBDEVICE_0`
（`src/kernel/rmapi/rmapi_utils.c:42..117`）。

所需 allocation 参数为：

| 对象 | parent | 参数 | 本卡最小值 |
|---|---|---|---|
| userspace client | root object | optional root alloc params | 可沿用零初始化 `NVOS21` |
| `NV01_DEVICE_0` | client | `NV0080_ALLOC_PARAMETERS` | `deviceId=0` 仅在目标确为 RM instance 0 时成立，其余字段 0 |
| `NV20_SUBDEVICE_0` | device | `NV2080_ALLOC_PARAMETERS` | `subDeviceId=0` |

`deviceSetClientShare()` 只记录 share/VA 参数，VAS 直到以后真的请求时才初始化
（`device_share.c:49..82`）；因此全零 device 参数不会为这个查询创建 channel、
显存对象或 VA mapping。

这里仍有两个普通 RM bookkeeping 动作：

- GSP-offload 时 device/subdevice allocation 会分别发
  `NV_RM_RPC_ALLOC_SHARE_DEVICE` 与 `NV_RM_RPC_ALLOC_SUBDEVICE`
  （`device.c:179..190`；`subdevice.c:120..131`）；
- 若系统已启用 GPU accounting，device allocation 会给该进程开始一条 accounting
  记录，free 时停止（`device.c:418..438`）。

它们不是 L2/topology 写入，但说明“建立只读查询 client”并非零 driver-state
变化。

### 3. 只用 `/dev/nvidiactl` 即可；card fd/register 是多余的

所有 `NV_ESC_RM_ALLOC` 与 `NV_ESC_RM_CONTROL` 都要求 ioctl 发在 control
device 上（`escape.c:452..488,788..803`）。对普通 `GET_FS_INFO`，
`RmGetDeviceFd()` 走 default，设置 `bSkipDeviceRef=NV_TRUE`；只有
`ATTACH_GPU` 和特定 `EXPORT_MEM` 需要从参数取得实际 device fd
（`escape.c:75..120,803..833`）。

`NV_ESC_REGISTER_FD` 的方向是“在某个实际设备 fd 上登记一个 control fd”，使
以后从该实际 fd 发出的 ioctl 可以关联 control client
（`escape.c:915..995`）。现有 `gb202_fs_probe.c` 随后的 alloc/control 全部发在
`r->ctl`，没有一个发在 `r->card`，所以这条注册关系没有被查询链消费。

反过来，额外打开实际节点不是完全无意义的动作：`/dev/nvidia0` 的 open 进入
`nv_open_device()`；若 `NV_FLAG_INITIALIZED` 尚未设置，它明确调用
`nv_start_device()`（`kernel-open/nvidia/nv.c:1638..1697`），后者继续进入
`rm_init_adapter()`。而 `/dev/nvidiactl` 的 open 只建立 control-file private
state、增加 control usage count，不调用 `nv_start_device()`
（`nv.c:1879..1886,3113..3138`）。

所以未来的严格最小版本应依赖“桌面 GPU 已经由现有驱动栈初始化”，只打开
`/dev/nvidiactl`。若物理 GPU/GSP 当时不可用，宁可让 device allocation/control
报错，也不通过打开 card fd 主动初始化它。

### 4. control 参数结构与 ABI

610.43.03 header 定义：

- method：`NV2080_CTRL_CMD_FB_GET_FS_INFO = 0x20801346`；
- query type：`NV2080_CTRL_FB_FS_INFO_LTS_MASK = 3`；
- 单个 LTS 参数：`NvU32 fbpIndex` 输入，`NvU32 ltsEnMask` 输出；
- 每个 query：`NvU16 queryType`、2-byte reserved、`NvU32 status`、union；
- outer params：`NvU16 numQueries`、6-byte reserved、120 个 8-byte aligned
  query。

出处为 `ctrl2080fb.h:2021..2033,2284..2359`。生成 dispatch 要求参数大小严格为
`sizeof(NV2080_CTRL_FB_GET_FS_INFO_PARAMS)`，610.43.03 中即 `0xf08`
（`g_subdevice_nvoc.c:10201..10213`）。

现有探针的自定义布局满足这一 ABI：单 query 为 32 bytes，outer 为
`8 + 120 * 32 = 0xf08`。未来版本仍应新增显式断言：

```text
sizeof(FsQuery)  == 0x20
offsetof(FbFsInfo, queries) == 8
sizeof(FbFsInfo) == 0xf08
```

即使只发一个 query，也必须把完整 `0xf08` 作为 `paramsSize`；将短结构大小传给
`NVOS54` 会在 dispatch 尺寸检查处失败。所有 reserved 字节和未用 query 必须
清零。

`NVOS54_PARAMETERS.flags` 应保持 `NVOS54_FLAGS_NONE (0)`。下一节的
`0x10248` 是 driver export metadata，不是用户要复制进 `NVOS54.flags` 的值。

### 5. 权限和 route flags

生成 method entry 为：

```text
method       0x20801346
flags        0x00010248
accessRight  0
paramSize    0x0f08
```

`0x10248` 解码为：

- `0x8` `NON_PRIVILEGED`；
- `0x40` `ROUTE_TO_PHYSICAL`；
- `0x200` `ROUTE_TO_VGPU_HOST`；
- `0x10000` `GSP_PLUGIN_FOR_VGPU_GSP`。

定义见 `control.h:201..205,226..250,282..287`。`accessRight=0`，且没有
`PRIVILEGED`、`INTERNAL` 或额外 access right，所以普通 client 在方法权限层面
可以调用。

两个不可忽略的负事实：

- flags **没有** `API_LOCK_READONLY (0x100)`；“handler 是读路径”不能写成
  “export 被 RM 标成 read-only API-lock control”；
- flags **没有** `NO_GPUS_ACCESS (0x2)`；RM 不承诺 GPU 处于掉电状态时也能完成
  它。

在正常 GSP-offload 情形，`ROUTE_TO_PHYSICAL` 使 CPU-RM 序列化参数并调用
`NV_RM_RPC_CONTROL`，成功后跳过 host-local implementing function
（`resource.c:210..250,253..300`）。因此未来调用会真的到物理 GSP，而不是只读
CPU 内存中的缓存。

### 6. 最小 baseline 可以只用同一个 GET control

不需要现有探针额外调用的 `GET_INFO_V2` 与旧
`GET_LTC_INFO_FOR_FBP`。更小、错误边界更清楚的两步是：

1. 第一次 `GET_FS_INFO` 只放一个 `FBP_MASK (type 1)`，并明确令
   `swizzId=NV2080_CTRL_GPU_PARTITION_ID_INVALID (0xffffffff)`；取得 physical FBP
   enable mask。
2. 清空整个参数块；对第一步 mask 中每个 enabled FBP 放一个
   `LTS_MASK (type 3)`，设置对应 `fbpIndex`，一次 batch 发出。

每次都必须同时检查：

- ioctl syscall 返回值；
- `NVOS54_PARAMETERS.status`；
- 每个有效 query 自己的 `query.status`。

现有探针对第一组 FBP query 打印了 per-query status，但对后面的四项 batch 只看
outer RM status，未逐项检查 `query.status`（`gb202_fs_probe.c:264..302`）。未来
baseline 应给每个 status/output 先放非零 sentinel，再要求 handler 明确改为
`NV_OK`，避免“未处理的零初始化输出”被误认成真 mask。

### 7. 查询路径没有显式 reset，但不是绝对的无扰动承诺

可见 CPU-RM client/device/subdevice constructors 没有调用 reset；device 构造遇到
“GPU 正在 full-chip reset”反而返回 `NV_ERR_GPU_IN_FULLCHIP_RESET`
（`device.c:150..160`）。既有 GSP 小窗口审计还证明 GB202 type-3 handler 调
FB getter，读取 current/effective LTS-disable view 后生成 enable mask；没有写
raw/effective register 或调用 reset（详见
`parallel/gb202_getfsinfo_support.md`）。

这支持如下精确说法：

> 正常成功路径没有请求 reset，也没有 topology 写操作。

它不支持更强的说法“任何环境下调用都绝不可能伴随 reset”。固件内部实现不全
公开，而且若 GPU 本来已故障，独立的 RM recovery 可能与一次查询同时发生。
此外 control 会拿 GPU lock、RPC 到 GSP，并可能让低功耗设备恢复到可访问状态。

## 现有 `gb202_fs_probe.c` 的复用判定

| 部分 | 判定 | 原因/未来动作 |
|---|---|---|
| `NVOS21` / `NVOS54` wrappers | 可复用 | ABI 与当前 OpenRM 一致；继续保持 version-match 和 size asserts |
| root -> device -> subdevice 层级 | 可复用 | 是最小 subdevice-control 对象链 |
| nominal `NV01_ROOT` | 可复用 | userspace 会被内核强制改为 `NV01_ROOT_CLIENT`，不会提权 |
| `FsQuery` / `FbFsInfo` layout | 可复用 | 32-byte query、`0xf08` outer 与 610.43.03 一致；补 outer size/offset assert |
| `/dev/nvidia0` open | 不应复用 | 多余；首次 open 可隐式 `nv_start_device()` / `rm_init_adapter()` |
| `NV_ESC_REGISTER_FD` | 不应复用 | 后续 ioctl 都在 ctl fd；该关联未被 GET_FS_INFO 使用 |
| `GET_INFO_V2` | baseline 非必需 | 可用 type-1 FBP mask 取代其 FBP discovery |
| 旧 `GET_LTC_INFO_FOR_FBP` | baseline 非必需 | LTS effective baseline 直接用 type 3 即可 |
| 同 batch 的 LTC/FBPA/ROP | baseline 非必需 | 减少范围，只发 type 3 |
| per-query error handling | 需要加强 | 每个 query status 和输出 sentinel 都要验证 |
| `deviceId=0` | 条件可用 | 只在已静态确认目标 5090 是 RM device instance 0 时成立 |

### 已安装库入口

对本机四个库的动态导出表做了只读检查：

- `libnvidia-cfg.so.610.43.03` 没有导出通用 `NvRmAlloc` / `NvRmControl`；
- `libnvidia-ml.so.610.43.03` 没有导出 LTS/LTC/floorsweep topology API；
- `libcuda.so.610.43.03` 没有导出通用 RM control wrapper；
- `libnvidia-api.so.1` 只见通用 `nvapi_QueryInterface`，没有一个可据此认定稳定的
  Linux `GET_FS_INFO` wrapper。

所以当前可复核的路径是直接使用随 OpenRM 公布的 ioctl/class/control ABI。
它是 NVIDIA 用户库实际依赖的低层接口，但不是 NVML/CUDA 面向应用开发者承诺
长期稳定的 API；必须用与 loaded kernel RM 对应的 headers/结构版本，不能假设
跨大版本永远保持 `0xf08` 和相同 method semantics。

## INFERENCE

1. 在当前桌面已经稳定使用 RTX 5090、GSP 已运行、无 MIG 的前提下，删除 card
   fd 后的最小 ctl-only 查询应能获得全物理 GPU 的 current/effective LTS enable
   masks，而且不会触发 MODS 初始化或 MODS task-2。
2. 该路径的风险等级显著低于读寄存器 probe：它调用专用的 non-privileged
   topology getter，不接受任意地址，也没有 write opcode。
3. `GET_FS_INFO` 不带 `API_LOCK_READONLY` 更可能是整个 batched multiplexer 的
   locking 分类，而不是 type-3 secretly writes；已审计的 type-3 分支本身仍是读。
4. ctl-only 版本若在未初始化/掉电环境失败，应该把失败视为安全边界，不再自动
   fallback 到 `/dev/nvidia0` open、模块操作或 reset。

## UNKNOWN

1. 当前 live kernel module/GSP 的精确 build 是否与静态审计的 610.43.03 artifact
   字节一致；本轮没有向设备查询。
2. 本机实际 RM device instance 是否始终为 0；单 NVIDIA GPU 情形很可能如此，
   但 hardcode 在多 NVIDIA GPU/热插拔环境不是可靠身份校验。
3. 私有 GSP object-allocation/free implementation 的所有微小副作用；可见 host
   只请求 per-client device/subdevice 对象，没有 reset/topology mutation。
4. runtime power-management 恰好处于低功耗状态时，这个没有
   `NO_GPUS_ACCESS` 的 control 会产生何种 wake/latency 行为。
5. MIG/partition 模式下 type-3 返回全物理还是实例可见 mask 的精确 runtime
   选择；既有 handler 审计显示存在 instance-aware 分支，所以 physical baseline
   应限定在确认无 MIG 的环境。
6. 一次 live 调用的实际 allowlist/return status；本轮按要求未执行。

## 人话版

我们不用 MODS 也能“问官方驱动：你现在认为每个 FBP 里哪些 L2 小块是开的”。
最干净的办法只打开驱动的总控门 `/dev/nvidiactl`，办三个临时证件（client、
device、subdevice），问两次，然后注销证件。

现有小程序问的问题本身没毛病，但它还顺手打开了 `/dev/nvidia0`。这一步对正在
跑桌面的卡通常什么也不会发生，可如果卡原本没初始化，驱动确实可能借此启动
整套 GPU 初始化。因此以后真做 baseline 时应把这一步拿掉。

拿到的结果只是“此刻驱动/GSP 生效的 L2 开关表”，不是熔丝原稿、坏块证明或
解锁能力。它适合做改动前后的只读对照尺，不是解锁工具。

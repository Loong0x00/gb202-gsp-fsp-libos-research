# GALAX Xtreme Tuner Plus 1.1.0.4 静态审计

日期：2026-08-11  
范围：只下载、解包和反汇编；没有启动 Windows 程序，没有调用 NVAPI/RM，没有读取或修改正在使用的显卡。

## 结论

这份影驰程序没有显示出一条仅限 HOF 的秘密 GPU 控制通道。它的 GPU 超频主体是 NVIDIA 私有 NVAPI：

- V/F 编辑器确实调用逐点 `VfPointsGetInfo/GetControl/SetControl`；
- 程序确实调用 `PERF_LIMITS GET/SET`，其中写入路径固定构造 `VOLTAGE` 类型，并打印 `Volt lock call succeeded`；
- 程序能查询时钟域并识别 `GRAPHICS CLOCK`、`MEMORY CLOCK`、`PROCESSOR CLOCK`；
- 但程序中没有当前 610 分支完整 `ClockDomainsGetControl/SetControl` 的接口 ID，也没有 XBAR、SYS、MSVDD、NVVDD 字符串或相应参数流；
- HOF 对话框是界面/链接入口，不是另一个硬件控制后端；
- 附带的 `DeviceDll.dll` 是 HID/SetupAPI 外设控制库，没有 GPU IOCTL/I2C 控制路径。

所以，对当前目标最重要的判断是：**Xtreme Tuner 可以证明 Windows 厂商工具也在使用私有 NVAPI，但它没有提供比我们现有 Linux `libnvidia-api`/RM 路径更完整的 XBAR/SYS 控制实现。** 值得迁移的是已闭合的 V/F 与 PERF_LIMITS ABI，而不是整套影驰程序。

## 样本与散列

官方页面指向的 Google Drive 中取得两个 1.1.0.4 包：

| 文件 | 大小 | SHA-256 |
|---|---:|---|
| `XtremeTuner_en_v1.1.0.4.rar` | 14,0 MB | `579266a09994c4bc97549d9902b39409f7bef753107f7be5fd7378682e65b20a` |
| `XtremeTuner_KFA2_Device_v1.1.0.4.rar` | 118 MB | `e31b7314c0fe651153975c5a9f6fcd952fc8302b52c9de3e7048afe284376c36` |
| `XtremeTuner_en.EXE` | 14,510,708 | `84e067c0691ee9c9df4106bd7930c312fe0078a7b626dec179ee20cb315ffb17` |
| `XtremeTuner_KFA2_Device.EXE` | 131,198,556 | `e4ac41eea75e3979a37c1d1512f9c7e923b5ea1a3c640461411a41e975d23c6a` |
| 解包后的 `Xtreme Tuner.exe` | 14,822,744 | `746917cfe53918613e08665bb4e17d4088962fa6b8379280652fe76b97b3b2a3` |
| 解包后的 `DeviceDll.dll` | — | `f6132e1351143cbc32e47c97ca6147ae20e207cb64554e7b6368ae999b331587` |

安装器是 Wise 格式，已用 WiseUnpacker 静态展开到 `payload_en/` 和 `payload_kfa2/`。主程序是签名的 32-bit PE，编译时间戳为 2025-01-14 12:06:23，PDB 路径为：

```text
F:\SVN_Code\XtremeTuner\XtremeTuner_Blue_Dev_en\Release\Xtreme Tuner.pdb
```

PE 自报 Product/File Version `1.0.7.1`，与发行包名 `1.1.0.4` 不一致；这只说明内部组件版本和发行版本分开维护。

## NVAPI 装载方式

主程序动态装载 `nvapi.dll`，解析：

```text
nvapi_QueryInterface
nvapi_Direct_GetMethod
```

其封装器优先/并行支持 Direct Method，再以 QueryInterface ID 回退。初始化还取得 Direct Method 接口 `0xad298d3f`、`0x33c7358c`，以及回退接口 `0x0150e828`、`0x593e8644`。

这说明下面的接口 ID 不是从错误字符串猜出来的，而是程序实际传给 QueryInterface 的常数。

## V/F 曲线：已证实可达

| 功能 | QueryInterface ID | 包装器 |
|---|---:|---:|
| `ClockClientClkDomainsGetInfo` | `0x64b43a6a` | `0x004045b0` |
| `ClockClientVfPointsGetInfo` | `0x507b4b59` | `0x00404680` |
| `ClockClientVfPointsGetControl` | `0x23f1b133` | `0x00404750` |
| `ClockClientVfPointsSetControl` | `0x0733e009` | `0x00404820` |

调用闭包：

```text
UI/profile handlers
  -> 0x00628d80  DomainsGetInfo + VfPointsGetInfo
  -> 0x006372f0  VfPointsGetControl + VfPointsSetControl
  -> 逐点循环修改频率偏移
```

`0x00638e00` 也读取 V/F control，并从最多 32 个域中保存 graphics/domain 0 与 memory/domain 4 的状态。这与本地 LACT 610 实现的接口 ID 完全一致。

已证实的 RM 映射：

```text
VfPointsGetInfo     -> 0x2080902a
VfPointsGetControl  -> 0x2080902c
VfPointsSetControl  -> 0x2080d02d
```

程序含 `VfPointsGetStatus` 错误字符串，但没有本地 610 对应的 Query ID `0x21537ad4`，因此不能仅凭字符串声称该状态接口可达。

## PERF_LIMITS：已证实可达

程序实际包含并调用：

| 功能 | QueryInterface ID | 包装器 | 高层调用 |
|---|---:|---:|---:|
| PERF_LIMITS GET | `0xe440b867` | `0x00402e20` | `0x00632460` |
| PERF_LIMITS SET | `0x39442cfb` | `0x00402ef0` | `0x00633300` |

`0x00632460` 构造 0x308-byte 参数并读取五种限制：

```text
0 GRAPHICS_MAX
1 GRAPHICS_MIN
2 MEMORY_MAX
3 MEMORY_MIN
6 VOLTAGE
```

`0x00633300` 的写入参数固定为类型 6；参数为零时禁用，非零时使用数值类型 3 和调用者给出的值。成功日志是：

```text
Volt lock call succeeded
```

该函数由至少六个 UI/profile handler 调用，故不是链接器残留。它证明影驰程序能施加电压 perf-limit/lock，也解释了 UI 中“电压锁”类能力；它不等同于修改 MSVDD 硬件电压，也不等同于完整时钟域控制。

当前本机 `libnvidia-api.so.1` 还含另一组旧/新 PERF_LIMITS 接口 ID（如 `0xefcedd1f`、`0x32ca4983`）和 Direct Method/RM 路径。影驰选择的是上表这一对版本。

## 完整时钟域控制：强负证据

本机 610 `libnvidia-api.so.1` 的完整时钟域控制为：

```text
ClockDomainsGetControl Query ID 0xf58938f5 -> RM 0x2080901b
ClockDomainsSetControl Query ID 0xd14b69cf -> RM 0x2080d01c
```

影驰主程序对上述两个 little-endian ID 的命中数均为 0；作为对照，四个 V/F ID 与两个 PERF_LIMITS ID 均各出现 3 次（缓存、Direct Method 辅助和 QueryInterface 路径）。

程序的域名转换函数 `0x00630750` 只识别：

```text
domain 0 = GRAPHICS CLOCK
domain 4 = MEMORY CLOCK
domain 7 = PROCESSOR CLOCK
```

没有 XBAR/SYS/HUB/DISP/PWR 的 UI/字符串/参数映射。因此现有证据不支持“影驰工具藏有 XBAR 曲线编辑器”或“它能借 HOF 型号门槛写任意 ClockDomains control”。

## HOF、I2C 与附带外设组件

- `CCHOFDeviceDlg` 的已追踪方法负责界面初始化、链接和消息分发，没有 GPU 控制调用链。
- 英文主包没有 `.sys` 驱动，也没有单独打包的 `nvapi.dll`；它使用系统 NVIDIA 驱动。
- `DeviceDll.dll` 导入 HID/SetupAPI、`CreateFile`、`WriteFile`，面向 KFA2/GALAX 外设；没有 `DeviceIoControl`、GPU RM control 或可识别 I2C 电压控制路径。
- KFA2 Device 包的大量新增文件是键鼠/灯光等外设资源，不能视为 HOF 显卡硬件后端。
- 包内存在开发期遗留的 `TestServices` 脚本，指向不存在的 `F:\SVN_Code\...\TestService.exe`；它不是本包可用的 GPU 服务。

## 已证实 / 推断 / 未知

### 已证实

- 影驰 UI 实际调用逐点 V/F GET/SET。
- 影驰 UI 实际调用 PERF_LIMITS GET/SET，并能写 voltage-limit 类型。
- 没有当前 610 完整 ClockDomains Get/Set 的 QueryInterface ID。
- 没有发现自带 GPU 内核驱动、HOF I2C 后端或 XBAR/SYS/MSVDD 控制路径。

### 推断

- “电压滑块/锁”主要经 NVIDIA perf-limit/V/F 语义工作，而不是像 Lightning 外置控制器那样直接偏移物理电压。
- HOF 型号差异更可能来自可用范围、VBIOS/RM 暴露能力和板级电源遥测，而不是 Xtreme Tuner 中另一套隐藏总线。

### 未知

- 在 Windows 610 驱动上每个 PERF_LIMITS 结构字段的完整 ABI 与 Linux 610 是否逐字节相同。
- 影驰特定 HOF VBIOS 是否让相同接口接受更宽的值域。
- 运行时型号检查是否会隐藏某些普通 UI 控件；但即使隐藏，当前二进制仍没有完整 ClockDomains SetControl 接口号。

## 下一步

影驰路线已足够闭合。下一步转向两版 MODS 的纯静态差分：

1. MODS 570.151（GB202/RTX 5090 制造包，已完整解出用户态 ELF）；
2. MODS 570.215（4 GB 启动镜像，含 570.215 MODS 与新增 GB202 CVB/IST/repair 资源）。

优先比较 `mods` ELF 中 ClockClient、PERF_LIMITS、XBAR/SYS/MSVDD、PWR、repair/floorsweep 的新增调用闭包；不运行 MODS，不加载 `mods.ko`，不向真实 GPU 发请求。

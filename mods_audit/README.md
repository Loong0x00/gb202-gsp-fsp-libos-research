# RTX 5090 MODS 570.151 审计、thermal 对照与安全结论

日期：2026-07-14  
机器：RTX 5090 / GB202 `0000:01:00.0`，Arch Linux，nvidia-open 610.43.03

## 最终结论

下载到的是面向 PG145 SKU35 / RTX 5090 的 MODS 570.151 制造包，但它**没有达到可判定为无恶意、可在日常宿主 root 直跑的门槛**。

| 命题 | 结论 |
|---|---|
| 下载内容与公开 Yandex 元数据相同 | **VERIFIED** |
| 包内 `mods-kernel-driver` 源码等同 NVIDIA 官方 v4.29 | **VERIFIED** |
| 未发现常见矿工、勒索、隐蔽持久化 IOC | **VERIFIED（限已做扫描）** |
| 闭源 392 MB `mods` ELF 与 72 个不透明 JSE 没有恶意 | **UNKNOWN / 无法证明** |
| 原版 MODS/driver 能满足“只读 therm、绝不写 MMIO” | **否** |
| 已让下载的 MODS 接触真实 GPU | **否** |
| 不依赖 MODS 的 hotspot reader 能稳定工作 | **是；VERIFIED 数值/行为，热点语义 INFERRED** |

因此没有执行“审计无恶意后再跑 MODS”这一分支：前提无法成立。真实 GPU 上只运行了我们已经逐操作审过的 NVIDIA KMD `READ_32` reader。

## 样本

主下载文件：`570.151_GB202_5090.zip`

```text
size    943721235 bytes
MD5     3ae2748b5cea1a73ce1f7f7056477ab1
SHA256  d141f685ea70c9a49095b7369201ab0651222bea3c063acfd6616dfde058ded9
```

关键内层散列：

```text
570.151.tgz  3f579e910b87c69dfa1d955af4150b03c8098c71c1142b24fbba6c85d87fba60
mods         c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
driver.tgz   fa8eeb376ef108c3198ed03feded213f0700b690905958d22ff2ce63fad1853b
```

这不是 ISO。外层是 ZIP，唯一成员是一个 `659-...tbz` 制造包，再内含 `570.151.tgz`。维修站 ISO/TinyLinux 可以提供启动环境，有的旧镜像捆绑 MODS、有的 50 系镜像明确不含 MODS；它们本身不会提供额外的 GB202 thermal 符号，也不改善闭源 payload 的可信度。

## 为什么没有把它判为“安全”

正面证据很强但不充分：archive 没有路径穿越/SUID/capability，驱动源码逐字节等同 NVIDIA v4.29，文件结构和 5090 制造配置也高度像真实 NVIDIA 内部包。

决定性缺口是：

- `mods` 是 stripped、无可验证发布签名的 392 MB ELF；
- thermal/gputest 等 72 个 JSE 接近满熵，无法审阅实际脚本逻辑；
- 用户态可执行 shell、联网，并可经原版驱动访问物理内存、PCI/MMIO、DMA、EEPROM、fuse、reset 等；
- `-no_net` 只表示“不在 NVIDIA 内网”，不是操作系统级断网；
- 一旦原驱动给用户态建立可写 BAR mmap，seccomp/namespace/strace 都无法拦截或观察普通 CPU store。

无 GPU 动态审计还证实，连 `mods -h` 都先探测 `/proc/modules` 和 `/dev/mods`；给假的 `/dev/mods` 时首个 ioctl 是 `MODS_ESC_GET_API_VERSION`，随后安全失败。到这个停止点没有网络或进程执行，但这不覆盖真正初始化路径。

## MODS thermal 调用与独立发现的关系

### 一致的部分

MODS 570.151 的 provider 表精确给出：

```text
thermal device class 1 = GPU
provider 4 = GPU_MAX
provider 5 = GPU_AVG
provider 6 = GPU_OFFSET_MAX
provider 7 = GPU_OFFSET_AVG
provider 8 = DYNAMIC_HOTSPOT
provider 9 = DYNAMIC_HOTSPOT_OFFSET
```

`IntTempMonitor` 经以下 GET 路径读取内部温度：

```text
0x20808536  ThermalDeviceGetInfo
0x2080853a  ThermalChannelGetInfo
0x2080853b  ThermalChannelGetStatus
```

570 的 status entry `+4` 是 signed Q24.8：

```text
temperature_C = int32 / 256.0
```

所以 NVIDIA 内部应对齐的 hotspot 目标名确实是 `GPU_OFFSET_MAX`，这是 **VERIFIED**。

### 仍不能声称完全相同的部分

MODS host ELF 中没有出现 `0x00ad0aa0`、`0x00ad0ae0`、八个 source offset 或 `0x00ad0718`。调用链是 thermal abstraction → private RM/GSP，而不是 host 程序直接硬编码这两个 BAR offset。

独立 reader 已证明：

```text
BAR0+0xad0aa0 == max(0xad0a90, 0xad0a94, 0xad0a98, 0xad0a9c)
BAR0+0xad0ae0 == max(0xad0ad0, 0xad0ad4, 0xad0ad8, 0xad0adc)
candidate      = max(decode(0xad0aa0), decode(0xad0ae0))
```

650/650 个时点均严格成立。它与 `GPU_OFFSET_MAX` 的结构和负载行为高度一致，但缺少 MODS/private provider 6 与 BAR 两值的同帧比较，所以“二者一一相等”仍是 **INFERRED**，没有冒充 VERIFIED。

## 610.43.03 的“删除”已在过滤前验证

通过只观察可信的本机 `/usr/lib/libnvidia-api.so.1` ioctl，保存了 610 的原始 GET 返回；observer 不修改请求或响应。

精确 ABI：

```text
0x20808536 size 0x63d0 = header 0x34 + 255 * 0x64
0x2080853a size 0x3bf8 = header 0x34 + 255 * 0x3c
0x2080853b size 0x37f0 = header 0x28 + 255 * 0x38
0x20808549 size 0x0c1c = header 0x28 + 255 * 0x0c
```

结果：

- `8536` 的 GPU devices 只实例化 provider `0..5`；provider `6 GPU_OFFSET_MAX` 和 `7 GPU_OFFSET_AVG` 都不存在；
- `853a` 的有效 24 个 channel 中没有 class-1 DEVICE hotspot channel；
- `853b` 只有 GPU_AVG/edge `34.55–34.85°C` 与 memory `46°C` 有效；GPU_MAX 和其余 current/debug provider 值都是 `255°C` invalid；
- E255 的高索引也全零，并非 NvAPI 只复制前 96 个而漏掉热点；
- `8549` 的 23 个 thermal-device status payload 全零。

这使“610 private API 里是否还漏藏了 provider 6”成为 **VERIFIED negative**，也解释了 NVML/NvAPI 的现象。

## 安全 reader 与本次复测

构建和运行：

```sh
cd /home/user/rt_5090_project/hotspot_reader
make gb202_hotspot
sudo ./gb202_hotspot
sudo ./gb202_hotspot -c -r -i 200 -n 10
```

reader 固定提交 15 个 `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS` 项；每项都是 `READ_32`、GLOBAL，源码中没有 WRITE opcode/分支，不 mmap BAR、不改 selector、风扇、频率、功耗、固件或绑定。

本次审计后的 10 次空闲复测：

```text
edge                         35 C（10/10）
hotspot candidate            37.688 .. 37.812 C
candidate - edge              2.688 .. 2.812 C
bit30 valid bank words        12/12（每次）
bit30 valid mirrors            2/2（每次）
aggregate - source max error   0.000 C（每次）
aggregate - mirror error       0.000 C（每次）
```

同一 READ32 路径重新读取静态限制字：

```text
BAR0+0x00ad0718 = 0x03480d60
(raw & 0x3fff) / 32 = 107.000 C
```

该地址是 limit，不是 live temperature；不能拿它冒充热点当前值。

已有同日受控 FP32 验证（未改任何散热/功耗设置）：

```text
400 samples @ 100 ms
max board power              475.79 W
max synchronized edge         68 C
max candidate                 81.375 C
max instantaneous delta       20.781 C
aggregate == source max       800/800 bank-samples
cooldown candidate            46.938 C
```

默认散热没有接近 107°C，也没有 Xid/thermal throttle；没有通过关风扇、改功耗或写控制寄存器强行制造阈值事件。

## 只读 MODS 驱动补丁的定位

另有一个可编译的研究 patch：只允许目标 BDF 的 `BAR0+0xad0000` 单个 4 KiB 页以 RO/NX/UC 映射，并默认拒绝写类 ioctl。它在当前 7.1.3 内核上编译成功，但**没有加载**。

它能安全地让 MODS 在第一次需要写/访问页外时失败，但不能证明闭源程序无恶意，也不能把访问限制到同页的确切 15 个 word；原始 MODS 初始化预计还会因拒写而失败。因此实际读温度应继续用精确 offset 的 KMD READ32 reader，而不是为了“试 MODS”加载额外模块。

## 清理与当前系统状态

- 删除了下载留下的重复 `.part`、外层 TBZ 和三份可由主 ZIP 重建的中间解包副本，
  从约 5.3 GiB 清到约 1.8 GiB；保留唯一已散列 ZIP、实际内层 payload、审计报告
  和复现材料。
- 未安装/加载 `mods.ko`，未运行 `install_module.sh`，未写 udev/`/lib/modules`。
- 未卸载、重绑或 reset NVIDIA；当前 `01:00.0` 仍由 `nvidia` 驱动。
- 没有修改 vBIOS/固件、风扇、频率、电压或 power limit。
- 最终检查没有 kernel Xid。

## 报告索引

- `static_audit.md`：archive、ELF/JSE、IOC 与供应链审计；
- `dynamic_audit.md`：无 GPU sandbox 的早期行为与 strace；
- `thermal_re.md`：MODS thermal provider、controls、ABI 和调用链；
- `nvapi_610_raw.md`：610 原始 RM buffers 的独立解码；
- `containment/containment.md`：原版驱动危险面与拒写 patch；
- `../hotspot_reader/RESULT.md`：最终 reader、寄存器、位域及完整验证。

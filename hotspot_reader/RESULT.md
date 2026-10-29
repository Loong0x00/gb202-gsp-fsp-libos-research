# RTX 5090 / GB202 hotspot reader（Arch Linux，610.43.03）

## 结论先行

路线 1 得到了一个稳定、只读、不依赖 MODS、无需修改 KMD 的 GB202
hotspot **候选值**：

```sh
cd /home/user/rt_5090_project/hotspot_reader
make gb202_hotspot
sudo ./gb202_hotspot
```

本机最终版实测输出：

```text
edge=36 C  hotspot_candidate=39.438 C [INFERRED]  delta=3.438 C  aggregate=39.438/39.438 C  selfcheck=0.000/0.000 C
```

操作公式是：

```text
hotspot_candidate_C = max(decode(BAR0 + 0x00ad0aa0),
                          decode(BAR0 + 0x00ad0ae0))
```

证据等级不能省略：

- **VERIFIED（数值关系）**：`0xad0aa0` 在 650/650 个样本中逐 raw word
  等于 `max(0xad0a90, 0xad0a94, 0xad0a98, 0xad0a9c)`；`0xad0ae0`
  同样逐字等于 `max(0xad0ad0, 0xad0ad4, 0xad0ad8, 0xad0adc)`。最大
  来源会在 source 0 和 source 3 间切换，不是某个固定第五传感器碰巧总最热。
- **VERIFIED（行为）**：这些字按下述 Q9.5 公式得到实时温度；随负载从约
  42.6°C 升至 81.375°C，停载后回落；edge 同期最高 68°C。
- **INFERRED（语义）**：两组聚合 MAX 再取较大值就是 GB202 GPU
  junction/hotspot。MODS 570.151 的静态逆向已独立确认 NVIDIA 内部目标名
  `GPU_OFFSET_MAX`（GPU device/provider 6）及其 private RM/GSP 读取路径；但 MODS
  host ELF 没有上述 BAR offset，本机 610 又已删掉 provider 6，无法做同帧对照。
  因此不能把“这两个 BAR aggregate 与该 provider 一一相等”标成 verified。
- **UNKNOWN**：两组 bank 的私有角色、四个 source 的物理位置、辅助字含义、
  `0xad0b50/0xad0b70` 镜像的硬件用途，以及接近 107°C 时与降频比较器的逐周期
  关系。

换句话说：现在已有可连续运行的最佳寄存器 reader；若验收标准要求“已由 NVIDIA
私有符号或 MODS 同帧读数证明就是 hotspot”，公开材料和本机现有接口还不足以把
最后这一层从 **INFERRED** 提升为 **VERIFIED**。

## 寄存器、位域和物理地址

本机 `0000:01:00.0` 的 BAR0 基址是 `0xd8000000`，长度 64 MiB。

| 观测角色 | BAR0 offset | 物理地址 | 证据等级 |
|---|---:|---:|---|
| edge | `0x00ad0400` | `0xd8ad0400` | `raw & 0xff` 与 `nvidia-smi` 对齐，**VERIFIED** |
| bank A sources | `0x00ad0a90..0x00ad0a9c`，步长 4，共 4 路 | `0xd8ad0a90..0xd8ad0a9c` | 实时温度，**VERIFIED** |
| bank A aggregate | `0x00ad0aa0` | `0xd8ad0aa0` | 650/650 等于前四路 MAX，数值关系 **VERIFIED**；私有角色 **INFERRED** |
| bank A auxiliary | `0x00ad0aa4` | `0xd8ad0aa4` | 实时温度，具体含义 **UNKNOWN** |
| bank B sources | `0x00ad0ad0..0x00ad0adc`，步长 4，共 4 路 | `0xd8ad0ad0..0xd8ad0adc` | 实时温度，**VERIFIED** |
| bank B aggregate | `0x00ad0ae0` | `0xd8ad0ae0` | 650/650 等于前四路 MAX，数值关系 **VERIFIED**；私有角色 **INFERRED** |
| bank B auxiliary | `0x00ad0ae4` | `0xd8ad0ae4` | 实时温度，具体含义 **UNKNOWN** |
| aggregate A mirror | `0x00ad0b50` | `0xd8ad0b50` | 250/250 与 `0xad0aa0` 逐字相同；用途 **UNKNOWN** |
| aggregate B mirror | `0x00ad0b70` | `0xd8ad0b70` | 250/250 与 `0xad0ae0` 逐字相同；用途 **UNKNOWN** |
| 107°C limit word | `0x00ad0718` | `0xd8ad0718` | 静态 107°C 阈值，不是 current，**VERIFIED** |

温度字的实测布局为：

```text
bit 30      12 个 bank 字在 650/650 样本中恒为 1；两个 mirror 在 250/250 中恒为 1；字段名 UNKNOWN
bits 16:3   signed 14-bit Q9.5 temperature
bits 2:0    在全部样本中为 0
```

精确解码：

```c
q5 = (raw >> 3) & 0x3fff;
if (q5 & 0x2000)
    q5 -= 0x4000;
celsius = q5 / 32.0;
```

公式有两份独立支撑：本机读数以 1/32°C 步进且与 edge/负载的绝对温标一致；
610.43.03 GSP 中旧架构 current-temperature HAL 也执行完全相同的
`bits 16:3 -> 14-bit sign extend -> /32` 转换。旧地址 `0x20460/0x204a0`
在 GB202 已是 `NV_ERR_NOT_SUPPORTED` stub，不能沿用；本次地址由 Blackwell
PTHERM 窗口的只读差分得到。`0xad0718` 的阈值则是 low-14 Q9.5 表项，不能套用
current 字的 bit 30/右移 3 布局。

公开源码的边界也已核实：

- NVIDIA 610.43.03 的
  `/usr/src/nvidia-610.43.03/src/common/inc/swref/published/blackwell/gb202/dev_therm.h`
  只公开 `NV_THERM_I2CS_SCRATCH = 0xad00bc`，没有 TSENSE/current/MAX 名称。
- 当前 Nouveau 的 GB202 device 没有 `.therm` subdevice；thermal 实现止于旧的
  `gp100.c` 和 `0x20460` 路径。

## reader 用法与只读保证

一次读取：

```sh
sudo ./gb202_hotspot
```

每 500 ms 连续读取，Ctrl-C 结束：

```sh
sudo ./gb202_hotspot -i 500
```

十次 CSV，附带所有原始字：

```sh
sudo ./gb202_hotspot -c -r -i 200 -n 10
```

`-n 10 -i 200` 也等价；参数顺序已实机回归。非 root 时 RM 会拒绝这些寄存器
访问，程序明确报错退出，不会把零值当温度。程序还会 fail closed：必须收到
12/12 个 bank 字和 2/2 个镜像的 bit 30 观测，并要求 aggregate/source 与
aggregate/mirror 两个自检误差都不超过一个 Q9.5 LSB（1/32°C）。

程序没有直接 mmap 已被驱动绑定的 `resource0`，而是使用 open KMD 已公开的
`NV2080_CTRL_CMD_GPU_EXEC_REG_OPS = 0x20800122`。官方头文件明确其 READ32
语义为 `regValueLo = read(bar0 + regOffset)`：

- 15 个 op 全部固定 `NV2080_CTRL_GPU_REG_OP_READ_32 = 0`；
- 全部固定 `NV2080_CTRL_GPU_REG_OP_TYPE_GLOBAL = 0`；
- `WRITE_32 = 1`，源码既没有定义它，也没有写分支；
- 不读写 selector/data `0xad07f0/0xad07f4`；
- 不改风扇、频率、功耗、模块、固件或设备绑定。

本工具按题设单卡固定 `/dev/nvidia0` / RM device 0，只适用于已验证的 GB202
RTX 5090，不应把这些 offset 复制到其他芯片。

完成 MODS 审计后又做了 10 次、200 ms 间隔的空闲复测：edge 10/10 为 35°C，
candidate 为 37.688--37.812°C；12/12 个 bank valid bits、2/2 个 mirror valid
bits 每次都通过，aggregate/source 与 aggregate/mirror 自检误差每次均为
0.000°C。此复测只运行上述 READ32 reader，没有运行 MODS。

## 负载验证

验证负载是有时限和 edge guard 的 FP32 CUDA matrix multiply，没有改变散热或
功耗设置。

| 项目 | 约 14.6 秒预采样 + 10.4 秒负载重叠（负载总长 12 秒；trace 先结束） | 约 6.4 秒预采样 + 25.0 秒负载 + 8.8 秒冷却 |
|---|---:|---:|
| PTHERM samples | 250 × 100 ms | 400 × 100 ms |
| 最大板功耗 | 473.24 W | 475.79 W |
| `nvidia-smi` edge 最大 | 62°C | 65°C |
| 同步 PTHERM edge 最大 | 64°C | 68°C |
| aggregate candidate 最大 | 77.969°C | 81.375°C |
| candidate 最大时 edge / delta | 64 / 13.969°C | 68 / 13.375°C |
| 最大瞬时 candidate-edge | 19.281°C | 20.781°C |
| aggregate==四 source MAX | 500/500 bank-samples | 800/800 bank-samples |
| 最大来源 | source 0 与 source 3 均实际获胜 | source 0 与 source 3 均实际获胜 |
| mirror 自检 | 500/500 bank-samples 逐 raw word相同 | 旧 trace 未采 mirror |
| 停载后 | PTHERM trace 先于负载结束，未覆盖冷却 | candidate 回落至 46.938°C，edge 44°C |

两份 raw trace 合计 650 个时点；所有 12 个 bank 字的 bit 30 均置位，low 3 bits
均为零，aggregate/source 误差均为 0。可复算：

```sh
python validation/audit_trace.py \
  validation/gb202_hwmax_trace_20260714.csv \
  validation/gb202_hotspot_trace_20260714.csv
```

这两份 CSV 是发现阶段由旧版程序写出的，因此文件名和派生列仍含暂定的
`hotspot`/`hwmax` 标签；审计脚本刻意忽略那些派生列，只从每行保存的
`address + raw word` 重新解码上述不变量。最终 reader 的新 CSV 列名是
`hotspot_candidate_c`、`bank*_aggregate_c` 和 `mirror_error_c`。

本机默认散热下没有接近 107°C，也没有 thermal throttle 或 NVIDIA Xid。用户曾见
到的 30--40°C delta 和约 107°C 降频在这两个受控负载中没有复现；本次最大瞬时
delta 是 20.781°C。因此“接近 107°C 时该候选与 MODS/降频点一对一重合”仍为
**UNKNOWN**，没有通过关风扇、写 MMIO 或改功耗设置强行制造。

## 路线 2--4 的结论

### 路线 2：KMD / GSP

**VERIFIED negative for audited paths**：Host KMD 找不到可直接导出为 sysfs 的
junction current 字段。Thermal Execute V2 只提供 sensor 0=edge，1..31 经物理
GSP 仍无效；RUSD 只有 GPU(edge) 与 MEMORY；thermal throttle 共享路径只有 reason
bits。NVD thermal dump、未填充的 `junction_temp` protobuf、PFM TGPU、
TemperatureV 均没有当前 junction 数值。

进一步在 NvAPI 包装器过滤前截获了 R610 的 private-RM GET 原始返回：`0x8536`
的 GPU thermal devices 只含 provider 0..5，明确没有 provider 6
`GPU_OFFSET_MAX`；`0x853b` 仅 edge 与 memory 有效，其余 current/debug provider
均为 255°C invalid。`0x20808549` 的 23 个 device payload 也全零。没有可靠 Host
字段可暴露，所以没有制作或加载猜测性的 KMD patch，也就没有模块恢复步骤。
详见 `kmd_gsp_path_result.md`、`../mods_audit/thermal_re.md` 和
`../mods_audit/nvapi_610_raw.md`。

### 路线 3：NVML / private NvAPI enum

**VERIFIED negative**：`nvmlDeviceGetTemperature` 与
`nvmlDeviceGetTemperatureV` 的 enum 0..255 中只有 0 成功，而且就是 edge；其余
全是 invalid argument。私有 thermal channel 的 `GPU_MAX` 是 255°C invalid
sentinel，`GPU_AVG` 是 edge，另一个动态值明确是 MEMORY；96-slot V3 中所有未
广告位也失败。

### 路线 4：I2C

**VERIFIED inventory / UNKNOWN device identity**：GPU adapters 1..7 只发现若干
未绑定地址；没有 NVIDIA hwmon 或已实例化温度 client。为避免误碰 EEPROM/VRM，
没有对未知设备做寄存器盲读。工作候选来自片上 PTHERM，不依赖 I2C。

## 用户给的四个链接

1. [NVIDIA MODS kernel driver](https://github.com/NVIDIA/mods-kernel-driver)
   最有机制层面的价值：它是让 MODS 用户态访问 PCI/BAR 的通用桥；源码没有
   GB202 thermal offset、位域或算法。
2. [Repair Wiki guide](https://repair.wiki/w/Nvidia_GPU_Memory_Testing_Guide)
   是 MODS/MATS 版本和显存测试使用指南，没有 thermal register 信息。
3. [Levirepair thread](https://www.levirepair.eu/infusions/forum/viewthread.php?thread_id=3&pid=70)
   最有趣的是列出 `nvmt ts` 和 MODS 的 `-bg_dram_temp`，但前者没有解释输出，
   后者明确是 VRAM 温度记录而非 GPU junction。首帖所带 MODS 镜像声明到 RTX
   40；后续虽提供 RTX 50 可启动 OS，却明确不含 MODS、需要另找二进制。它不是
   GB202 hwref，本任务也没有下载或运行这些第三方镜像。
4. [RkBlog overview](https://rkblog.dev/posts/pc-hardware/nvidia-modular-diagnostic-software-mods/)
   有助于理解 MODS/MATS 的 Linux 工作流和日志；示例中的
   `-no_thermal_slowdown` 与本任务护栏相冲突，未使用。页面没有温度寄存器线索。

所以第一个解释了“MODS 为什么能碰 BAR”；四个链接都不能证明 GB202 hotspot
地址。实际定位依赖本机只读 PTHERM 差分、GSP 解码和 650-sample 结构不变量。

## 2026-07 公开维修圈的 RTX 50 MODS 追踪

- **VERIFIED availability**：VLab 主帖后来把工具目录扩展到了 570；Yandex
  [公开目录](https://disk.yandex.ru/d/tAIPw5QLnez-2g)及其
  [公共资源 API](https://cloud-api.yandex.net/v1/disk/public/resources?public_key=https%3A%2F%2Fdisk.yandex.ru%2Fd%2FtAIPw5QLnez-2g&limit=1000)
  当前确实列出 `570.151 GB202 - 5090.zip`（943,721,235 bytes，
  MD5 `3ae2748b5cea1a73ce1f7f7056477ab1`，SHA-256
  `d141f685ea70c9a49095b7369201ab0651222bea3c063acfd6616dfde058ded9`）。
  这是约 900 MiB 的 MODS payload，不是可启动 ISO；本项目随后下载到完全相同的
  文件并完成静态/无 GPU 动态审计。checksum 只能证明拿到同一文件，不能证明
  NVIDIA 签名、来源安全或授权状态。
- **VERIFIED GB202 execution**：GPU Solutions 的
  [RTX 5070/5080/5090 实机视频（7:49）](https://youtu.be/gon1OA74_ZA?t=469)
  同屏显示 `lspci` 的 NVIDIA DID `2b85`、目录 `570.151_5090`，随后执行
  `./mods gputest.js -skip_rm_state_init` 并生成 5090 GDDR7 训练结果。目录清单
  还可见 `thermal.jse` 和 `thermregpu.jse`。这证明它是能在 5090 上初始化的完整
  MODS，不只是 MATS 或启动外壳。配套文章后文有一次写成 `570.215_5090`，但
  文章前面的目录表和视频画面都明确是 `570.151_5090`，应视为笔误。
- **VERIFIED Blackwell thermal command**：VIK-on 的
  [RTX 5070/GB205 实机视频（2:19）](https://youtu.be/SPUoLuR1EHs?t=139)
  显示 MODS 570 运行：

  ```sh
  ./mods gputest.jse -oqa -test 2 -skip_azalia_init \
    -timeout_ms 5000 -bg_int_temp 1000 -loops 50
  ```

  日志持续输出 `GPU_OFFSET_MAX`、`GPU_AVG`、`GPC_OFFSET_MAX`、`GPC_AVG`、
  `MEM_MAX` 等内部温度；视频中的 `GPU_OFFSET_MAX` 约 79.5--79.7 C，而
  `GPU_AVG` 约 65.8 C。老版 MODS 手册也把 `-bg_int_temp` 定义为 internal
  thermal sensor monitor。NVIDIA 官方 R580.167.08
  [release notes](https://docs.nvidia.com/datacenter/tesla/tesla-release-notes-580-167-08/index.html#fixed-issues)
  又明确写出 “new HAL with `GPU_OFFSET_MAX` visible”；VLab 的
  [MODS 日志](https://vlab.su/viewtopic.php?f=48&start=540&t=124090)
  则把 107 C overtemp event 的 sensor 直接标为 `GPU_OFFSET_MAX`。因此
  `GPU_OFFSET_MAX` 是需要对齐的 NVIDIA 私有目标名，**VERIFIED**；它与本项目
  `0xad0aa0/0xad0ae0` 的确切映射仍没有同帧对照，保持 **INFERRED**。
- **UNKNOWN on GB202 hotspot**：公开实机视频验证了 `570.151` 在 RTX 5090 上
  跑显存诊断，也验证了 570 在 RTX 5070 上用 `-bg_int_temp` 读内部最大温度；但
  尚无公开画面把二者合在同一台 5090 上。因此“`570.151` 可直接输出 5090
  `GPU_OFFSET_MAX`”概率很高但仍是 **INFERRED**，不能标 verified。

公开网已经给出专包、哈希和实机画面，没有转向 Tor/onion 的技术必要。更重要的
是 MODS 会初始化 RM、切 P-state、调风扇并可能 reset/shutdown GPU；上面的测试
命令也会制造负载，不能当成严格只读监控工具。本项目已下载并把它作为数据做
静态逆向，也只在无 GPU、无网络、payload 只读的 sandbox 中执行到首个假的
`/dev/mods` ioctl 失败；从未让它接触真实 GPU。最终 reader 仍走只读寄存器路径
且不依赖 MODS。完整结论见 `../mods_audit/README.md`。

## 交付、恢复和清理

- `gb202_hotspot.c` / `gb202_hotspot`：最终只读 reader；
- `validation/audit_trace.py`：从 raw CSV 独立复算不变量；
- `validation_fp32_load.py`：带时限/edge guard 的可选验证负载；
- `validation/gb202_hwmax_trace_20260714.csv`：250-sample raw trace + mirror；
- `validation/gb202_hotspot_trace_20260714.csv`：400-sample raw trace；
- `THERM_REGISTER_AND_NVAPI_EVIDENCE.md`：寄存器和私有 API 详细证据；
- `kmd_gsp_path_result.md`：Host KMD/GSP 排查；
- `nvml_enum_result.md`、`i2c_result.md`：路线 3/4 结果。
- `../mods_audit/README.md`：MODS 下载、恶意面审计、thermal 逆向和 610 raw
  private-RM 对照。

没有修改系统文件、KMD、固件、风扇、功耗限制或设备绑定，因此系统恢复步骤为
“无”。验证负载已退出且 CUDA allocation 已释放。只删除本目录编译产物可运行：

```sh
make clean
```

源码和验证 CSV 不会被删除。

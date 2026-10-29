# ASUS RTX 5090 Astral 与 RTX PRO 6000 Blackwell WS VBIOS 离线兼容性初查

日期：2026-09-04（Asia/Shanghai）

## 安全边界

- 本轮没有停止显示、卸载 NVIDIA 驱动、解绑 PCI 设备、reset GPU 或写 EEPROM。
- 在 `Display Active: Enabled`、NVIDIA 模块保持加载时，通过 PCI sysfs 只读取得了当前 E0 档的基础 Option ROM。
- 没有执行任何刷写命令。`nvflash --save` 只读尝试因当前内核没有 `iomem=relaxed`、严格 `/dev/mem` 拒绝而退出；没有改变显卡状态。
- 完整结构比较使用本卡既有 E1 全 EEPROM 备份。E0/E1 的板卡、Device ID、Chip SKU 相同，但不能假设所有性能/风扇表逐字节相同。
- 本报告不记录或公开本卡 PPID，以及 TPU donor ROM 中的完整序列号。

## 输入

### 当前本机卡

- 产品：ASUS ROG Astral RTX 5090 OC
- PCI：`10de:2b85`, subsystem `1043:89e3`
- 当前 VBIOS：`98.02.2E.40.E0`（AS30）
- 当前只读 sysfs Option ROM：
  - `ASUS_Astral_1043-89E3_live_sysfs_98.02.2E.40.E0.rom`
  - 162,304 bytes
  - SHA-256 `fa91bdc10dd6a2ed3f46c78fa8a96b902ed7256ef74fd08c10a6def616660211`
  - 是完整的主机可见 PCI Option-ROM 链：`0xfa00` legacy image + `0x18000` EFI image；不是完整 SPI/EEPROM 映像
- 既有完整 E1 EEPROM 备份（仅用作结构基线）：
  - `flash_logs/astral-original-20260726_020901.rom`
  - 1,961,984 bytes
  - SHA-256 `01a2e0340725c82988d54300934b993968f977ddea3185e64be161c279a8333b`

### TPU 下载的六份 RTX PRO 6000 WS ROM

六份文件都是：

- `98.02.52.00.02`
- `PG144 SKU 520 VGA BIOS`
- PCI `10de:2bb1`, subsystem `10de:204b`
- firmware Board ID `0x0716`
- Chip SKU `870-0`
- Project `G144-0520-0`
- Build `2025-03-19`，Modification `2025-03-24`
- Chip Family `0x001b`
- Security Version Number `0x0003`

这不是六个不同 VBIOS。逐字节比较显示：

- 六份文件的 `[0, 0x1d10b0)` 完全相同；
- 主 Option-ROM chain `[0x35800, 0x114000)` 的 SHA-256 全部为
  `8b27d74de6bcaf5fe7bde701f5742d43dcb4513167bf2cf8c5419eba34d380bb`；
- 任意一份相对基准仅有 6--13 个不同字节；
- 差异全部位于尾部 `BRD/OBD` records，内容是单卡制造日期、序列号，以及渠道 P/N
  `900-5G144-2200-000` / `900-5G144-2500-000`；
- TPU 标成 NVIDIA 或 PNY 不代表固件主体不同。

因此做离线结构分析任选一份即可；做真实 raw flash 时它们不是“无身份的通用镜像”，因为仍携带 donor BRD/OBD 数据。

## NVFlash 显式兼容性绑定

| 字段 | Astral E1 基线 | PRO 6000 WS 52 |
|---|---:|---:|
| Device ID | `0x2b85` | `0x2bb1` |
| firmware Board ID | `0x06d2` | `0x0716` |
| Chip SKU | `300-0` | `870-0` |
| Project | `G145-0030` | `G144-0520-0` |
| Chip Family | `0x001b` | `0x001b` |
| Security Version Number | `0x0003` | `0x0003` |

PRO 镜像的 component `C003` 显式绑定 Device ID `2bb1`；`C014/C00C/C012` 同时绑定 Board ID `0716` 和 Device ID `2bb1`。标准 NVFlash/update 路径因此存在确定的 Device/Board mismatch。既有实测仅证明 stock 5.877 的 `-6` 能在 Device ID 与 Board ID 相同时覆盖 subsystem mismatch，不能外推到本次跨 Device/Board。

共同的 Chip Family 与 SVN 表明它们属于同一 GB202 安全世代；目标各组件也都标为 `Prod`，没有可见的 SVN 降级。但这不能消除产品/板卡绑定，也不能证明强写后 BootROM/FSP 会接受。

## 比预期更接近的部分

以下比较使用本卡完整 E1 基线与 PRO WS 52；是文件事实，不代表可启动。

### 显存

- `MEMORY TIMINGS` 表结构均为 `v0x20, header 6, record 105, count 12`。
- 两边完整 1,266-byte timing table **逐字节相同**：
  SHA-256 `911cccfe3edde7c00e2344434842b470d48f7ae7233447430350090ff7202a89`。
- `MEM TYPE` 表均为 `v0x10, header 7, record 22, count 16`。
- 本卡实测 `RAM Config = 0`；PRO 的 config 0 也不是 Skip，但该 record 有一个字节与 Astral 不同。
- 16 个 type records 中，config 0、4、7 有差异；其余 13 个相同。PRO 的 config 4 从 Astral 的 Skip 变为有效项。
- timing-mapping 表的主布局相同（v0x11、10 个时钟项、13 个 RAM config），但 PRO 的 per-config xinfo record 从 `0x54` 增至 `0x5c`，每项多 8 bytes；这与其不同显存拓扑相容，但这 8 bytes 的 GB202 私有语义未公开。
- 可见的其它 Memory 表也不是整体替换：`M+0x05` 的 0x6a-byte训练表相同，`M+0x09` 训练 pattern 仅一字节不同，`M+0x0d` 表相同。加密初始化载荷内部仍不可见。

结论：之前“PRO 镜像完全没有 5090 可选显存项、必定在第一步训练失败”的说法过强。它确实保留多个 5090 类配置，config 0 有效，基础 timing 甚至完全相同；但 Astral 当前实际使用的 config 0 record 被修改，扩展 mapping 也不同。公开字段不足以把任一记录正式命名为“16×2 GB”或“32×3 GB clamshell”，故兼容性仍未知。

### 风扇与热控

- 两边 fan table 都是 `v0x10, header 9, record 26, count 4`；仅 24/113 bytes 不同。
- 两边 fan-management table 都是 `v0x20, header 4, record 51, count 11`；89/565 bytes 不同。
- thermal-device table 490 bytes逐字节相同。
- thermal-monitor table 36 bytes逐字节相同。
- PRO GPIO 保留 Astral 也有的 `FAN_TACH`（line 13）与 `FAN_PWM`（line 16）；Astral 另有 `PWM_2`（line 28），PRO 表没有。

按“目标 VBIOS 使用的控制通道必须是原卡硬件的子集”这一经验规则，PRO WS 并未表现为比 Astral 要求更多风扇通道；风扇不是当前最强否决项。不过通道地址、外部控制器与实际四风扇分组仍未动态验证。

### 供电与传感器

两边对应表的版本、header/record/count 均相同，而且差异量很小：

- power-sense：299 bytes 中 5 bytes 不同；
- power-topology：849 bytes 中 18 bytes 不同；
- power-budget：2,096 bytes 中 41 bytes 不同；
- thermal-channel：681 bytes 中 2 bytes 不同。

这说明不是完全无关的板级固件，但少量关键 calibration/mapping 字节仍可能足以造成错误功耗读数或保护行为。

### 显示输出

- Astral DCB：3×DP + 2×HDMI；
- PRO WS DCB：4×DP + stereo/sync 项。

即使GPU初始化成功，也不能预期所有夜神输出正常；测试不能依赖被重映射的接口。

## FSP/安全对象

两边都有同一 GB202 Falcon-v6 格式的加密 `FSP_RUN` envelope，app/target 及 descriptor epoch 相同，但 payload 不同：

- Astral E1：envelope `0x29450` bytes，SHA-256
  `1f01255cf607f32ef1cbffb0d65c9fb5829e55f63af1f0ca9a674f5e9adab19c`；
- PRO WS 52：envelope `0x2a850` bytes，SHA-256
  `2d9d8e5c8988fb148218c277c6fed358386b48f1c4cb38cb90b20b0b31356415`。

PRO WS 的三个外层 P-384 public-point slots 与 NVIDIA FE/Server 样本相同，ASUS Astral 使用另一组三点；但本卡能运行 ASUS 镜像只说明设备接受对应签名链，不能由此证明它也会接受 PRO 的产品身份。

## 当前判断

### 已证实

1. 六个 TPU 文件是同一个 VBIOS build 的六张卡回读，不是六种候选；全文件联合差异集仅13字节，全部属于BRD/OBD个体信息。
2. 标准 NVFlash 面对明确的 Device ID `2b85 -> 2bb1` 与 Board ID `06d2 -> 0716` mismatch；stock路径大概率会在写入前拒绝，但本轮没有在实卡上触发写入流程验证具体报错点。
3. 目标不是完全不同架构：Chip Family/SVN相同，显存基础 timing、热传感器、部分供电和风扇结构高度共用。
4. 风扇通道从静态表看不像首要否决项。
5. 没有执行真实刷写，因此无法证明设备端最终接受或拒绝。

### 修正后的概率判断

静态结果比仅看产品规格更接近，故不能再严谨地称“写入后几乎必定完全不枚举”。真正剩下的两个高风险门是：

1. signed component 的 Device/Board binding 是否会在 update 或下一次 secure boot 被设备端强制；
2. RAM config 0 中不同的一字节、以及 mapping 每项额外 8 bytes，是否会让 16×2 GB 板在早期显存初始化失败或产生错误容量映射。

因此准确表述仍是：**标准路径不可刷；强制写入后的启动结果未知，且当前没有公开成功先例。**

## 下一步（仍只读）

若要继续，最低干扰步骤是下次正常启动临时加入 `iomem=relaxed`，保持驱动和显示加载，先尝试：

1. 当前 E0 档完整 EEPROM `nvflash --save`，连续保存两次并核对大小和SHA-256；
2. 当前卡与 PRO ROM 的 `--version`/只读兼容性输出；
3. 确认双 BIOS 的 E0/E1 对应物理开关档位并保留一档原厂；
4. 确认 iGPU/SSH 与外置 SPI 恢复链。

历史证据只确认“驱动加载 + `iomem=relaxed`”时 `--list` 可用，尚未确认同状态下完整 `--save` 一定成功；若仍拒绝或超时就停止，回退到维护启动且不加载 NVIDIA 模块后保存。`iomem=relaxed` 会降低 `/dev/mem` 防护，只应临时使用。

真实写入属于另一阶段，需要单独明确授权，不能从本轮只读分析自动推进。

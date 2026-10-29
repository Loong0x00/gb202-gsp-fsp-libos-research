# RTX 5090 GB202：MODS 570.215 实机只读时序寄存器验证（2026-09-24）

**后续进展：**八分区+广播 9×6 字实机读回及原值 `rw` 见 `GB202_MODS_NATIVE_COMMAND_FOLLOWUP_20260924.md`；隔离 VM 下原生 `dramclk(18000)` 实测约 **17999 MHz、CL37**，详见 `GB202_MODS_18000MHZ_LIVE_20260924.md`。本篇以下只记第一次 VM 尝试，其当时的宿主状态已非最新。

## 前提与实际执行

用户确认当前桌面/显卡无人使用，并要求在确认 Quill 的 kernel/view 分离后手动 VFIO 直通，只做只读探针。Quill 常驻 `quill-kernel` 和独立 SSH `quill-attach` 全程保持。关闭 GDM 和 GPU 用户态服务；自定义水冷控制服务正常退出时恢复主板 BIOS 智能 PWM 模式 `pwm3_enable=pwm4_enable=5`，**实际冷排 fan3 ~2080–2238 RPM、水泵 fan4 ~3600–3802 RPM**。未强改冷却曲线。

手动卸载 NVIDIA 模块时发现原本未排除的 `hsr-path-probe.service` 每约0.5秒执行 `nvidia-smi`，能再次载入/占用驱动。确认无游戏进程后，在没有 GPU FD 的窗口以 `systemctl freeze` **暂停而非停止**此服务，不触发它退出时的游戏启动器配置恢复；之后 NVIDIA 模块和两个 PCI 功能按引用/持有者检查成功交给 VFIO。`rtx5090-vfio-preflight` 验证 group13 与 root port。没有禁用该服务，也没有修改游戏配置。

只读资源是 Ubuntu 22.04.5、kernel 5.15.0-119、MODS 570.215、诊断模块4.29、一次性 qcow2 客体写层，QEMU 不连网也不共享宿主文件。首轮 QEMU 因 qemu 用户 `RLIMIT_MEMLOCK=8MiB` 的 DMA 映射失败且**没有执行 MODS**；重新以只对 QEMU 进程生效的无限 memlock 启动。MODS 客体未加载 nouveau，显卡被确认为 `10de:2b85`、subsystem `1043:89e3`。

独立的 `gb202_config0_5_readonly.js` 调 `Gpu.Initialize` 返回 `invalid object property`，**不是有效读数**。改用 MODS 自带 `mods.js`；其首次初始化因客体缺失 gldGB202 golden 文件、首次还因 Azalia 条件失败。清洁 VM/FVIO reset 后按本地过去成功的诊断选项运行 `-skip_azalia_init -null_display -no_vga`，增加源代码明确支持的 `-no_gold -no_test` 跳过 golden 和所有测试，GPU 初始化成功。在 **MODS 交互提示符**只执行一次读取命令：

```text
RegRd32(0x9a0290, 6)
```

这不是写入命令；但 MODS 本身的 GPU 初始化仍可配置硬件。期间客体 MODS 显示 GDDR7、Samsung、RAM Config 0、E0 VBIOS `98.02.2E.40.E0`、**DRAM Clock 14001 MHz**、GPU约32°C。没有执行压力测试、时序修改、时钟/电压覆盖或刷机。交互会话受 85s 客体超时约束；试图随后读八分区时它已退出，命令落入 Bash 被拒，**八个分区没有实机读数**。

## 实际广播寄存器读回（真卡，MODS 14001 MHz 时）

| 地址 | 名称 | 32-bit raw |
|---|---|---|
| `0x9a0290` | CONFIG0 | `0x1a6afd4f` |
| `0x9a0294` | CONFIG1 | `0x796805a3` |
| `0x9a0298` | CONFIG2 | `0xcc2a0f00` |
| `0x9a029c` | CONFIG3 | `0x2400004c` |
| `0x9a02a0` | CONFIG4 | `0xf1428032` |
| `0x9a02a4` | CONFIG5 | `0xe8027144` |

这些字节与本卡旧 E1 完整 VBIOS `flash_logs/astral-original-20260726_020901.rom`、`MEMORY TIMINGS` entry14（`0x73681+6+14*105`）前六个字 **逐字相同**。这是 E0 的实机读回与 E1 同档的独立交叉验证，不代表两份固件所有时序表相同。

按 NVIDIA [Memory Tweak Table](https://nvidia.github.io/open-gpu-doc/MemoryTweakTable/MemoryTweakTable.html) 公布的 CONFIG0/1 位域解码，**RC=79、RFC=253、RAS=53、RP=26、CL=35、WL=11、RD_RCD=32、WR_RCD=22**。该字段解释还得到公开 mVolt+ 0.47.2 静态读取/解码实现交叉支持。按旧公开定义继续解 CONFIG2..4 可得到候选 `WR=42、RRD=5、CCDL=4、CCDS=2、W2R_BUS=12、R2W_BUS=12`；GB202 的记录长105字节而旧公开基础记录为76字节，这些**后续字段的 GDDR7 语义尚未独立确认**。尤其不得把旧字段解析出的 `FAW=0` 说成实际 tFAW 为零，也不得把 `REFRESH` 编码直接叫 tREFI。

**频率边界：**MODS 运行时读的是 **14001 MHz** 档（entry14）；恢复宿主 NVIDIA+GDM 后当前频率读回 **17001 MHz**，不能拿这组六字当宿主当时 17001 MHz 的 live timing。此前基于 E1 表推测 17001 档的 `CL=37、RFC=272` 等只是该档固件候选，未在此实验实测。

## 退出、回退及尚未达成的目标

每轮 QEMU 退出后内核日志均记录 GPU+HDA 的 VFIO reset 与 `reset done`。最后一轮退出后检查无 QEMU 和 `/dev/vfio/13` 持有者，手动解除 VFIO，恢复 `nvidia`/`snd_hda_intel`、`nvidia_uvm`、`nvidia_modeset`、`nvidia_drm`。NVIDIA `nvidia-smi` 对 E0 卡和容量读回正常，随后恢复 `waterloop-fan-control`、`nvidia-persistenced`、`lactd`、GDM，并 `systemctl thaw hsr-path-probe.service`。结尾服务均 active，quill-kernel/appserver 与远程 attach 存活，GDM 显示登录界面；原 GNOME 用户窗口不会自动回来。末次冷排约1965RPM、水泵约3089RPM，GPU30°C。没有时序寄存器写、没有 CL+1。

**原生接口与写入安全必须分开：**`mods.js` 明确提供交互式原始 `RegWr32`/`rw`（已初始化后走 `GpuSubdevice.RegWr32`）；旧高层 CONFIG 写槽 `+0x700` 在 GB202 命名 HAL 为 no-op、三个旧 profile setter 返回不支持，并不禁用通用原始写。读寄存器成功**不等于** CONFIG1.CL 可安全热改或可持久锁存，尤其尚未掌握同步 GDDR7 模式寄存器/读延迟/训练的流程；本轮未做寄存器写试错。八个 FBPA 的 CONFIG0..5 均有可寻址的只读地址，八组没取到是本次 MODS 交互 85s 超时造成的操作问题，**不是 MODS 只能读广播或者只能读两字**。

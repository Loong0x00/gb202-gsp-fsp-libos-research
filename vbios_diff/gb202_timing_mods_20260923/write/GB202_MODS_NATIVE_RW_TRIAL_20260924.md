# GB202 / RTX 5090：隔离 VM 内 MODS 原生 CL+1 写入试验（2026-09-24）

用户明确授权在 VFIO 隔离客体中直接试 MODS 自带的原始命令，并强调**无需为继续远程交流而退出 VM/恢复主机显示**。此记录覆盖此前“CL+1 未执行”的报告之后的**新一轮、全新客体**。前一轮独立结果见 `../read/GB202_MODS_NATIVE_COMMAND_FOLLOWUP_20260924.md`。

## 严格限定的条件

- 关 GDM 后仅 Quill GPU 图形前端退出，`quill-kernel`/`quill-appserver` 和 SSH `quill-attach` 存活；`hsr-path-probe.service` 冻结，persistenced/LACT 关闭。两个 PCI 功能在 IOMMU group13 中绑定 `vfio-pci`，VM 无网络、无主机文件共享，使用全新一次性写层/OVMF_VARS。MODS 570.215 内置 `mods.js` 使用 `-skip_azalia_init -null_display -no_vga -no_gold -no_test`，显卡已初始化、识别 GB202 DID `0x2b85`、E0 VBIOS、Samsung GDDR7，MODS 内 DRAM **14001 MHz**。测试无显存压力负载。
- 水冷服务退出到主板 BIOS 自动 PWM `pwm3/4_enable=5`；尝试时冷排约 2115 RPM、水泵约 3658 RPM、CPU约70°C，硬件泵/风扇不依赖宿主 NVIDIA 服务。写前用 MODS 原生命令复核 **FBPA0..7 + 广播，每组 CONFIG0..5 共54个 32-bit 字均一致**：`1a6afd4f 796805a3 cc2a0f00 2400004c f1428032 e8027144`。
- 每次异值写前启动宿主独立的**25s QMP 复位看门狗**；成功完成九组全部复核后解除。若 MODS 无响应、恢复失败或出现数据差异，脚本立即请求 QMP 关闭 VM，外部计时器兜底。两个计时器均已解除，VM 没被关闭。

## 原生命令的实际响应

本地**570.151** 解码 JS 中，`mods.js` 的 `rw(Address,Data)` 调用 `RegWr32(Address,Data)` **再**调用 `RegRd32(Address)`；`intrutil.js` 的 `FillData` 在省略 `NumWrites` 时缺省为 **1**，却不检查每次写入的返回值。这份磁盘明文来自 570.151，不可直接当作 VM 570.215 的源码；**后续在匹配的 570.215 VM 里只读调用 `rw.toString()`、`RegWr32.toString()`、`FillData.toString()` 已验证当前进程的这几段脚本逻辑相同**。仍没有独立定位 570.215 `GpuSubdevice.RegWr32` 原生写调用的错误码/硬件接受条件，不能从包装层 `RC.OK` 证明硬件写成功。详见 `MODS_570215_AUTH_AND_TIMING_ROUTE_20260924.md`。

原值 CONFIG1 = `0x796805a3`，按已核对位域 `CL=35`；仅将最低7位加1，异值 `0x796805a4` (`CL=36`)，其余位保持。分别试了两条地址，**各一次**，读回立即观察并尝试写回原值：

| 尝试地址 | MODS 原生命令（请求写） | 紧随命令的 MODS 回读 | 原值恢复命令回读 |
|---|---|---|---|
| 广播 CONFIG1 `0x9a0294` | `rw(0x9a0294, 0x796805a4)` | `0x796805a3`（未变） | `0x796805a3` |
| 单分区 FBPA0 CONFIG1 `0x900294` | `rw(0x900294, 0x796805a4)` | `0x796805a3`（未变） | `0x796805a3` |

两次尝试后，分别对八分区和广播完整复读 CONFIG0..5，**全部 54 字均等于写前原值**。没有时钟/电压更改、VBIOS 刷写、异值保持或稳定性压力测试。

**能下的结论：**在这块卡的 MODS 14001 MHz 已初始化状态，用 MODS 原生 `rw` 对广播或 FBPA0 的 CONFIG1 请求 `CL+1`，**均没有产生可见的 CONFIG1 位变化**。570.215 当前进程的只读函数内省后来确认了 `rw → RegWr32 → GpuSubdevice.RegWr32` 的 JS 调用链；但**原生写后端的状态/硬件接受点仍未闭合**。不能因此泛化“GB202 物理上绝对无法修改时序”，也不能证明无效发生在 JS、RM 权限、硬件写保护、锁存/更新协议中的哪一层。没有已验证的可用热更新流程，不继续盲试其它时序寄存器。

## 试验结束时的主机状态（暂不恢复显示）

按用户要求 VM 仍在运行，GPU 和音频仍在 VFIO；MODS 命令进程有受限超时，**即使该进程日后退出，VM 仍会存在，但不应在同一客体盲目重复 GPU 初始化**。GDM、`lactd`、`nvidia-persistenced`、`waterloop-fan-control` 仍停止，`hsr-path-probe.service` 仍冻结。最近冷排约2146 RPM、水泵3719 RPM，Quill 常驻服务和 SSH attach 正常。要回到主机桌面，应先经 QMP 正常退出 VM，确认 VFIO GPU/HDA `reset done`，再依次恢复宿主 PCI 驱动、NVIDIA、散热服务、persistenced/LACT/GDM，并最后解冻 HSR 探针；不能一边 VM 持有显卡一边重载宿主驱动。

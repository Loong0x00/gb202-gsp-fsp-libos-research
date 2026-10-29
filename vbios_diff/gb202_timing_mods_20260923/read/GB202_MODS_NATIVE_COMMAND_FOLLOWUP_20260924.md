# MODS 原生命令追查与九组 CONFIG 实机读回（2026-09-24 第二轮）

**本篇只记录第二轮及其当时的恢复状态。**用户随后授权了全新 VFIO 客体中的异值 `CL+1` 原生命令试验；广播及 FBPA0 写请求均未使 CONFIG1 回读发生可见变化。最新 VM 状态见 `../write/GB202_MODS_NATIVE_RW_TRIAL_20260924.md`。

## 澄清

用户说的“写”是 MODS 自带的 UI/命令接口，不限于旧版显存时序 profile setter。此前“无写通道”是把这两层混为一谈。静态解码 `mods_audit/static/decoded/all/mods.js`：`RegRd32`、`RegWr32` 在 `Gpu.IsInitialized` 时分别走 `GpuSubdevice.RegRd32/RegWr32`；同文件还提供交互 `rw(address, data)` 和 NV 脚本的 `dd`/`ed`。**原始写指令确实存在**。GB202 特定 profile HAL setter 不支持，仅表示不能依赖它自动处理热更新、训练和回退，不能否定原始寄存器写。

## 本轮只读：八分区 + 广播 CONFIG0～5

延用人工 GDM/NVIDIA→VFIO 接管流程，先在高频 `nvidia-smi` 采样器两次调用间冻结 `hsr-path-probe.service`；Quill/SSH 保持运行。BIOS 自动 PWM 下持续监测到冷排约 2014–2086 RPM、水泵约 3470–3600 RPM；GPU 客体不连网、只使用一次性 qcow2 层。MODS 570.215 客体运行内置 `mods.js`、跳过 golden/测试、Azalia 和显示初始化。对 `base=0x900290 + i*0x4000 (i=0..7)` 和广播 `base=0x9a0290` 分别使用**原生命令** `RegRd32(base, 6)`。日志逐项复核，所有 9×6=**54** 个 32-bit 原始读数完整，九组一致（FBPA2 因串口半包补读一次，同值）。

| 实机读回 base | 对象 |
|---|---|
| `0x900290`, `0x904290`, `0x908290`, `0x90c290` | FBPA0～3 |
| `0x910290`, `0x914290`, `0x918290`, `0x91c290` | FBPA4～7 |
| `0x9a0290` | broadcast |

每一组的 CONFIG0～5 **依序都是** `1a6afd4f 796805a3 cc2a0f00 2400004c f1428032 e8027144`，与上一轮 MODS **14001 MHz** 广播读数及本卡 E1 VBIOS 同档前六字完全一致。因此 MODS 并无“只能读两字/只能读广播”的限制；但**这只是已验证的 CONFIG0～5**，不等于已发现或解释了 GB202 所有 GDDR7 寄存器、VBIOS 105 字节条目和训练状态。

## 原生命令原值写回与 CL+1 的实际边界

在同一受限 MODS 会话，运行一次 `rw(0x9a0294, 0x796805a3)`，即把 CONFIG1 **原样字**写回，再回读 `009a0294: 796805a3`，未见同步错误且冷却正常。这证实**MODS 原生交互可以调用这条写/读路径**；相同值的回读**无法证明 GB202 硬件真正锁存了新时序**，也不能推出直接修改 CL 安全。

后续打算尝试 `CL=35→36` 的 `0x796805a4` 时，MODS 会话因预设 155s 上限已结束：命令落入客体 Bash，返回语法错误，**绝未由 MODS 执行该异值写入**。检查客体驱动关闭日志无 GPU 错误；在**同一**客体内再次启动 MODS 以做紧邻读/改/回写验证，GPU 初始化停在 `Successfully cleared GPU's interrupt state` 后，没有进入命令界面，门槛检查未发送任何异值写入。造成再次初始化停滞的原因未确定，不能推定原值写回导致，也不能在这种状态下盲试 CL+1。

QMP 退出 VM，内核确认 GPU/HDA 的 VFIO `reset done`。主机恢复 GPU=`nvidia`、音频=`snd_hda_intel`、`nvidia_uvm/modeset/drm`、waterloop、persistenced、LACT、GDM，解冻 HSR 采样器；quill-kernel/appserver 活跃，显卡 E0 VBIOS 和 17001 MHz 主机频率读回正常，温度约 30°C，最后冷排约2083 RPM、水泵3470 RPM。**没有执行 CL+1、没有固件刷写、没有运行显存压力测试。**

后续若确需异值写试验，必须重新建立**全新客体/完成 MODS 初始化**、写前校验实机配置与频率、在同一有时限会话内连续实现写/回读/原值恢复，并由独立的 QMP/VFIO 复位作为失联兜底；不能把一次原值写回当成安全性证明。

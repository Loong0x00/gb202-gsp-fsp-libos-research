# VFIO 低噪声冷却（2026-09-24，当前临时客体）

用户要求冷排风扇约 **800 RPM**、水泵约 **2500 RPM**，原 BIOS PWM 模式 `pwm3_enable=pwm4_enable=5` 当时实测冷排 fan3 ~2050–2119 RPM、水泵 fan4 ~3540–3680 RPM。CPU Tctl ~68–72°C、主板 CPUTIN ~38–39°C；GPU 在 VFIO 客体中，宿主不能实时取得其温度。九个冷排风扇共用主板 `nct6799` pwm3，水泵是 pwm4；主板 fan2 ~1200–1300 RPM 属于另一未确认设备/风道，本次未动。

当前不是修改 BIOS 曲线或常驻 service 文件：在 `/run/rt5090-quiet-vfio.sh`（root、仅本次启动有效）运行 transient `rt5090-quiet-vfio.service`，覆盖 pwm3/4 为 manual1、按 fan3/fan4 **实测 tach** 小步微调。水泵 PWM72 实测约 2500–2528 RPM。冷排降到现有控制器注明的 **PWM30 最低安全档**后，fan3 实测约 880–886 RPM；没有再下调到800，因为多风扇并联仅有一条可读 tach，低于既有 PWM30 下限可能使其它扇叶停转，不能凭 fan3 一条 tach 保证九个风扇都安全运行。不能把“设定 800”误写成“实际 800”。

**守护/回退：**每4秒检测 CPU Tctl、板载 CPUTIN、fan3/fan4 tach、QEMU 存活、经受限本机 SSH 检查客体 MODS 进程是否启动。如果 Tctl>=85°C、CPUTIN>=52°C、fan3<530 RPM、fan4<1900 RPM、客体失联/MODS 开始、传感器失效或控制模式被改变，立刻退出并恢复两个 PWM 通道的主板 BIOS 模式5。服务的 `ExecStopPost` 也调用同一恢复脚本，在异常停止时兜底。由于客体没有可用 GPU 温度读数，**不在此静音档运行显卡负载**；跑 MODS 前会先因进程检测恢复 BIOS 冷却。若临时 service 意外消失，第一时间确认两个 `pwm*_enable=5`。

立即手动恢复（不影响 VM/Quill）：

```sh
sudo systemctl stop rt5090-quiet-vfio.service
cat /sys/class/hwmon/hwmon1/pwm3_enable /sys/class/hwmon/hwmon1/pwm4_enable
```

切勿在本静音服务运行时重新启动 `/usr/local/sbin/waterloop-fan-control`，两个控制器会争夺 PWM。当前该原服务保持 inactive；当从 VFIO 恢复宿主 GPU 时，应先停止本静音服务、确认 BIOS 控制，再按已有 VFIO leave 流程恢复原 GPU/桌面/水冷服务。

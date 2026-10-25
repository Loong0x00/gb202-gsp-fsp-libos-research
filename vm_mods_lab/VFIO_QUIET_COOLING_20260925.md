# VFIO 静音冷却（2026-09-25，宿主-only 窗口）

用户要求：冷排风扇 **800 RPM**、水泵 **2000 RPM**。

## 实测：800 RPM 达不到（这是硬件下限，不是没调）

冷排通道 nct6799 **pwm3 / fan3**（九把 120mm 并联，只有一路可读 tach）本次逐档实测：

| pwm3 | 8 | 10 | 12 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 23 | 25 | 27 | 30 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fan3 RPM | 889 | 888 | 890 | 888 | 888 | 890 | 889 | 887 | 888 | 886 | 888 | 890 | 885 | 886 | 877 |

即：**pwm3 ≤ 30 时转速不再下降，风扇组自己的电子下限约 888 RPM**。800 RPM 只能靠换扇/加限速线/DC 模式（pwm3_mode=0，九扇并联+可能带供电 HUB，风险高、未验证），本次没有动 `pwm3_mode`。

所以本次保持 **pwm3=30**（既有最低安全档，落在那条下限平台上），实测 tach **888–895 RPM**。**不要把"设定 800"写成"实际 800"**：实际是 ~890 RPM。

水泵通道 **pwm4 / fan4**：pwm4=40 → **2030–2039 RPM**，符合"2000"要求（与主控制器的 `PUMP_MIN_PWM=40`、此前记录的 PWM40≈2030 一致）。

## 当前实现

- `/run/rt5090-quiet-vfio.sh`（root 0700，仅本次启动有效）+ transient unit `rt5090-quiet-vfio.service`（`--collect`，`ExecStopPost=/run/rt5090-quiet-vfio.sh --restore`）。
- 取手动控制：`pwm3_enable=pwm4_enable=1`，`pwm3=30`、`pwm4=40`，每 4 秒核对并回写被改动的值。
- 中止即恢复主板 BIOS 自动档（`pwm*_enable=5`）：`Tctl>=85°C`、板载 `CPUTIN>=52°C`、`fan3<530 RPM`、`fan4<1900 RPM`、传感器读数失效、控制模式被外部改动、**qemu 客体启动**（宿主拿不到 GPU 温度，不能在静音档跑显卡负载）。
- 已实测验证中止路径：注入 `pwm3_enable=5` 后 4 秒内 ABORT 并恢复两路为模式 5。

**主控制器 `waterloop-fan-control.service` 已 stop，静音期间必须保持 inactive**（两个控制器会争夺 pwm3/4）。它今天一直把冷排/水泵顶在 180/187（约 2360/4245 RPM），原因是 **RTX 5090 当前没有宿主驱动**（`nvidia-smi` 报 No devices，PCI 01:00.0 无 driver，VFIO lab 的 prepare 报 `uses driver, expected vfio-pci`），控制器判为遥测失效 → failsafe 满速。这与静音档无关，属于 GPU 侧状态。

## 恢复

```sh
sudo systemctl stop rt5090-quiet-vfio.service     # ExecStopPost 会把两路交回 BIOS 模式5
cat /sys/class/hwmon/hwmon1/pwm3_enable /sys/class/hwmon/hwmon1/pwm4_enable   # 期望 5 5
# 只有在宿主 GPU 恢复之后才重新启动常驻控制器：
sudo systemctl start waterloop-fan-control.service
```

若临时 service 意外消失，第一件事是确认两个 `pwm*_enable=5`。

未动：主板 fan2 通道（当前约 580 RPM，另一未确认风道）。

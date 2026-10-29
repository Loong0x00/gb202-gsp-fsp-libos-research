# waterloop gpu-handoff 策略改动（2026-09-26 05:35）

用户要求：**显卡存在但读不到（给了客体 / 无宿主驱动）时，不要顶 failsafe 满速，改为水泵 ~2500、冷排 ~1k**。理由是客体里的高负载基本是短时的，888 以下余量也够。

## 改动（`/usr/local/sbin/waterloop-fan-control`）

1. 新增配置（文件顶部）：
   - `GPU_HANDOFF_RAD_PWM=39` → 实测 **1003 rpm**
   - `GPU_HANDOFF_PUMP_PWM=72` → 实测 **2500–2513 rpm**
2. 新增 PCI 归属判定：`find_gpu_pci()` / `gpu_driver_name()` / `read_gpu_binding()`（`read_inputs()` 每轮调用，只写状态变量 `gpu_host_owned`，策略层不做 IO）。
3. `update_policy()`：在 `apply_conservative_airflow` 之后、hot/failsafe 之前插入 hand-off 地板；failsafe 条件改为"GPU/热点丢失**且**显卡由宿主驱动持有"才算故障。
4. 日志 `safety=hot:%d,fail:%d,handoff:%d`；`started:` 与 `--check` 增加 `gpu_pci=` / `driver=`。

## 行为表

| 状态 | CPU 遥测 | GPU/热点遥测 | 结果 |
|---|---|---|---|
| 正常（宿主 nvidia 驱动持有） | 有 | 有 | 照旧：空闲 30/40（~888/~2030），按 CPU/GPU 曲线爬 |
| **显卡交给客体 / 未绑定 / 不在**（`driver=vfio-pci`/`none`/`absent`） | 有 | 无（设计如此） | **handoff 地板：冷排 ≥39（~1000）、水泵 ≥72（~2500）**；CPU 曲线仍可往上加；Tctl≥95 仍 emergency 230/187 |
| 宿主驱动持有但遥测丢失（驱动卡死/Xid） | 有 | 无 | 严格 failsafe：冷排 180、水泵 187（且只升不降） |
| CPU 遥测丢失（任何状态） | 无 | — | 严格 failsafe：180/187（CPU 单次失败即触发，handoff 不会降级它） |
| 恢复可读 | — | 回到正常 | 地板撤掉，回到空闲 30/40（慢趋势 ~50 s 才降回去，属设计） |

注：判定用 PCI 绑定而非设备是否存在——`nvidia*` = 宿主持有（丢遥测=故障）；`vfio-pci`、无驱动、设备不存在 = handoff 地板。

## 验证

- 测试台 `validate_policy.sh`（source 策略半段，无硬件 IO）：7 项全 PASS
  （宿主持有丢遥测→failsafe；客体态两样本→地板 39/72；handoff+CPU 95℃→230/187；handoff+CPU 86℃→目标 123 > 地板；恢复→30/40；CPU 丢失→failsafe；仅热点丢失+宿主持有→failsafe）
- 旧测试台 `../waterloop-am5-gpu-proxy-20260917-155452/validate_policy.sh` 对 candidate 仍 5 项全 PASS。
- 部署后实测：`driver=nvidia` → 不触发 handoff；无 `写入错误`；空闲/负载路线与旧版一致。
- handoff 分支本身未做"真拔驱动"的端到端验证（原机显示还在用这张卡），只跑策略测试台。要真验证需在下一次 VFIO 窗口看一眼日志里 `handoff:1`。

## 回滚

```sh
sudo cp -a /usr/local/sbin/waterloop-fan-control.bak-20260926-0535-before-gpu-handoff /usr/local/sbin/waterloop-fan-control
sudo systemctl restart waterloop-fan-control.service
```

# SBR 恢复发现 — Power Cycle ≠ SBR (Reset-Domain 分析)

## 事件
2026-09-28 晚,向 PRC 0x25/0x26 写入 0xFFFFFFFF 后 GPU 进入完全死锁:
- GSP 邮箱 = BADF4100
- MNOC = BADF5660
- EMEM = 0x00000000
- SPI 控制器 = BADF1100
- 官方干净驱动(615.71.09)同样卡死
- 完全断电(拔 AC)重启后依旧死锁

## 修复
对 GPU 上游 PCIe 桥执行 Secondary Bus Reset (SBR):

```bash
# GPU = 01:00.0, 上游桥 = 00:01.1 (AMD GPP Bridge)

# 1. 移除设备
echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove
echo 1 > /sys/bus/pci/devices/0000/01:00.1/remove

# 2. SBR (Bridge Control bit 6)
ORIG=$(setpci -s 00:01.1 3E.B)          # 读原值 (0x12)
setpci -s 00:01.1 3E.B=$(printf '%02x' $((0x$ORIG | 0x40)))  # 断言
sleep 2
setpci -s 00:01.1 3E.B=$ORIG             # 释放

# 3. 重新扫描 + 加载驱动
echo 1 > /sys/bus/pci/rescan
modprobe nvidia nvidia_uvm
```

结果: GPU 完全恢复。nvidia-smi 正常、CUDA 正常、GSP 615.71.09 运行、
InfoROM Image Version 干净读出 G005.0000.98.01、PRC/OEM/OBD 对象全部正常。

## 为什么断电没修好但 SBR 修好了

PCIe 有多种 reset 机制,触发不同的 reset domain:

| Reset | 机制 | 效果 |
|-------|------|------|
| 断电重上电 | POR (Power-On Reset) | FSP 从头冷启动 → 读同一状态 → **重新进入坏状态** |
| FLR | Function Level Reset | 只重置 PCIe 功能逻辑,不碰内部电源域 |
| **SBR** | Bridge Control bit 6 → Hot Reset | 设备保持供电,但特定 reset domain 被清除,FSP 看到"SBR"这个 reset reason → **走另一条初始化路径** |

关键: **断电不是"没断干净",而是"断得太正常"。**
每次冷启动 FSP 都按 cold-boot 流程走,重新制造同一个问题。
SBR 从一个不同的入口,把状态机踹回去了。

## NVIDIA 自己的证据

NVIDIA `gpu-admin-tools` 提供了:
- `--recover-broken-gpu` → 对无响应 GPU 执行 SBR
- **`--set-next-sbr-to-fundamental-reset`** → "让下一次 SBR 表现得像 fundamental reset"

第二个选项的存在证明 NVIDIA 明确知道 SBR 和 fundamental reset 语义不同,
并且有一个可设置的标志改变 SBR 的行为深度。

## 对之前"发现"的重新解读

之前的假说: PRC 写入 → 持久化到 InfoROM flash → flash 数据损坏 → 不可逆

修正后的模型:
```
PRC 写入 0xFFFFFFFF → 改变某个运行期硬件状态 / secure region
                    → 冷启动不清除(或冷启动路径重新制造它)
                    → SBR 命中不同 reset domain → 清掉了
                    → flash 数据可能从未被真正破坏
```

证据: SBR 后 InfoROM Image Version 正常读出 → flash 完好。

"FSP InfoROM 持久化" 发现需要降级:
可能不是 flash 写,而是一个冷启动不清、SBR 才清的 volatile/secure 区域。

## 已知类似案例

- Blackwell "unexpected WPR2 already up" → 驱动重载不行 → SBR 恢复
- GitHub: gengchaogit/blackwell-xid-wpr2-gsp-crash-recovery
- 知乎: zhuanlan.zhihu.com/p/2056743676932518898
- NVIDIA 论坛: 多个 Blackwell GSP timeout 案例

## 待验证

1. [ ] 另一个 BIOS 位置是否也正常(切换后检查)
2. [ ] 重新触发死锁状态 → 验证 SBR 可重复修复
3. [ ] 查找 `--set-next-sbr-to-fundamental-reset` 对应的寄存器位
4. [ ] 确认 PRC 对象当前实际值(是否仍包含 0xFFFFFFFF 或已被重置)
5. [ ] PCIe Gen5 x8 是否正常(应为 x16?)

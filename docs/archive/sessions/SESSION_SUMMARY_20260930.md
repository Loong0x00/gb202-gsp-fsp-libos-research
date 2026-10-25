# 2026-09-29/30 战役总结 — 供下次会话恢复用

---

## 当前卡的状态

```
GPU: RTX 5090 (GB202), 双BIOS (XOC=当前, 原版=CC已清)
问题: FSP flash 里有"毒"(记录A+B), 断电后 WPR2 恢复, 驱动起不来
解决: 每次冷启动后跑 MODS CPU-RM 复活流程 (~5分钟)
永久修复: 需要 CH341A 编程器读/写 SPI flash (未购买)
```

## 5 个核心文件 (按重要性)

| 文件 | 内容 |
|------|------|
| `EXPERIMENT_LOG_20260929_30.md` | 完整时间线+发现+资产清单 |
| `GPU_REVIVE_MANUAL.md` | 复活操作手册 (含完整命令) |
| `BIOS_SLOT_CC_LOCK_RECOVERY.md` | WPR2 死锁分析 + CC修复记录 |
| `MNOC_PORT0_PROTOCOL.md` | MNOC 通信协议完整规格 |
| `K31_INJECTION_SETUP.md` | K3-1 注入环境搭建+踩坑 |

## 其他相关文件

| 文件 | 内容 |
|------|------|
| `MODS_SUL5_PATCH_SPEC.md` | SUL=5 双补丁技术规格 |
| `NVFLASH_VM_EXPERIMENTS.md` | nvflash 完整实验记录 |
| `DS_SESSION_K31_RECOVERY_20260929.md` | DS 会话考古 |
| `HANDOFF_K31.md` | 原始交接文档 (部分过时) |

## 快速恢复命令

```bash
# 1. 宿主绑 vfio
sudo /home/user/rt_5090_project/vm_mods_lab/vfio-bind-5090.sh

# 2. 启动 VM
sudo bash /home/user/rt_5090_project/GPU_REVIVE_MANUAL.md 中的QEMU命令

# 3. VM 内修复 (SSH 或串口)
# 见 GPU_REVIVE_MANUAL.md 步骤4

# 4. 验证
nvidia-smi  # 在VM内应显示 RTX 5090
```

## 立即可做的实验

```
1. K3-1 注入触发 (需 610.57 用户态库):
   传 libnvidia-ml.so 等 → nvidia-smi → RPC fn=73 → 溢出

2. 宿主 MODS 中断修复:
   研究 kernel 7.2.6 的 MSI-X API 变化
   或降级到 6.x 内核

3. nvflash 交互命令探测:
   protectinfo / compare 等未测试的命令

4. 0x12 FWUP 深度逆向:
   nvflash 的状态机重构 (42个槽位调用)
```

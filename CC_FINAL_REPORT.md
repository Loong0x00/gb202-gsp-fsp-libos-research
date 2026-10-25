# CC 模式研究 — 最终报告

日期: 2026-09-28 深夜

## 攻击面完整地图

```
第1层 [软件]  驱动 CPU TEE 检查
              ↓ 补丁绕过 ✓
第2层 [软件]  bForceEnableCC 门控
              ↓ 补丁硬编码 ✓
第3层 [协议]  SPDM 握手 (CPU↔GPU 认证)
              ↓ 补丁跳过 ✓
第4层 [固件]  FSP boot 命令 (GSP-FMC 引导)
              ↓ 补丁跳过 ✓
第5层 [固件]  GSP-RM Proxy boot (COT 命令)
              ↓ 补丁跳过 ✓
第6层 [硬件]  FSP CC 模式硬件状态
              ↓ 无法绕过 ✗ ← 最终阻塞点
```

## 第 6 层的具体表现

FSP CC knobs=1 时:
- FSP counter 寄存器 → badf4100(硬件锁定状态)
- GPU probe 静默失败(无详细错误)
- 所有软件层补丁无效
- FSP 在硬件层阻止非 CC 环境的初始化

**结论: FSP 检测到运行环境不符合 CC 要求(无 CPU TEE),
在硬件层面拒绝初始化 GPU。这不是软件检查,是硬件状态机。**

## 已证明的能力

| 项目 | 状态 | 方法 |
|------|------|------|
| FSP PRC knob 读 | ✓ | EMEM 通道, type 0x13/0x0C |
| FSP PRC knob 写 | ✓ | EMEM 通道, type 0x13/0x0D |
| Flash 持久化 | ✓ | 写入后穿越 SBR/断电 |
| CC knob 开启 | ✓ | knob 6/8 = 1, FSP 接受 |
| CC 硬件位变化 | ✓ | 0x590 寄存器 bit 0 变化 |
| 驱动 CC 引擎触发 | ✓ | confComputeConstructEngine 执行 |
| CPU 检查绕过 | ✓ | if(0) 补丁 |
| SPDM 绕过 | ✓ | 直接返回 NV_OK |
| FSP boot 绕过 | ✓ | if(0) + gpuBootGspRmProxy 跳过 |
| GSP CC 模式启动 | ✗ | 硬件层阻塞 |

## 关键发现

1. **CC 模式是硬件架构级隔离** — 不是软件开关
2. **FSP 是信任根** — 它在硬件层验证运行环境
3. **消费级 GPU 有 CC 硅片但被 FSP 拦截** — 缺 CPU TEE 配对
4. **PRC knob 是持久的** — flash 级,断电+SBR 不掉
5. **FSP CC 模式下 EMEM 通道部分可用** — PRC 读写可以,但 boot 命令不行

## 工具产出

- `prc_rw` — PRC knob 读写工具(EMEM 协议)
- `prc_read_emem` — 全 knob 扫描工具
- 补丁版驱动 615.71.09(4 个补丁: CPU check, bForceCC, SPDM, FSP boot)

## SBR 恢复方法(必备知识)

```bash
echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove
ORIG=$(setpci -s 00:01.1 3E.B)
setpci -s 00:01.1 3E.B=$(printf '%02x' $((0x$ORIG | 0x40)))
sleep 2; setpci -s 00:01.1 3E.B=$ORIG; sleep 4
echo 1 > /sys/bus/pci/rescan
modprobe nvidia
```

## 文件索引

- `PRC_KNOB_MAP.md` — 完整 knob 地图
- `PRC_COMPLETE_LOGIC.md` — 协议分析  
- `SBR_RECOVERY_DISCOVERY.md` — SBR 恢复发现
- `CC_ATTEMPT3_RESULT.md` — 尝试 #3 分析
- `FINAL_STATUS_20260928.md` — 当日总状态
- 本文档: `CC_FINAL_REPORT.md`

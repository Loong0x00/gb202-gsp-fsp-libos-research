# COT 注入攻击 — 最终定论

日期: 2026-09-28/29 深夜

## 核心结论

**COT (NVDM type 0x14) 只在 FSP 的 boot-phase dispatcher 中有 handler。
在 runtime dispatcher 中被静默丢弃 — 无响应、无错误、通道不受影响。**

## 实验证据

| FSP 状态 | PRC (0x13) | COT (0x14) | FSP counter |
|----------|-----------|-----------|-------------|
| Runtime (正常) | ✓ 响应 | ✗ 静默丢弃 | 递增 |
| Runtime (boot失败后) | ✓ 响应 | ✗ 静默丢弃 | 递增 |
| SBR 后 (locked) | ✗ 无响应 | ✗ 无响应 | badf4100 |
| 昨天 limbo 状态 | ✓ | ★ 响应! | 递增 |

## FSP 状态机 (已映射)

```
SBR → [boot-phase dispatcher]
        ├── 有 COT handler
        ├── 有 FRTS handler  
        └── 但寄存器 locked (badf4100) — 无法通过 EMEM 发消息!
        
驱动初始化 → [unlock 序列] → [runtime dispatcher]
              ├── 有 PRC handler (knob 读写)
              ├── 有 InfoROM handler
              └── 无 COT handler → 静默丢弃
```

## catch-22

```
要在 boot-phase 发 COT → 需要 SBR
SBR → 寄存器 locked → EMEM 通道死
驱动 unlock → FSP 进入 runtime → COT handler 不存在
```

## 昨天成功的原因 (推测)

昨天的 CC 模式失败序列意外创造了一个"limbo"状态:
- 驱动发送 boot 命令 → FSP 开始 boot 处理
- CC 模式导致 WPR2 已配置 → 驱动 boot 失败
- FSP 停在 boot 处理中途 → boot dispatcher 仍活跃
- 我们的 COT 被 boot dispatcher 处理 → 得到响应

这个状态很难精确重现 — 依赖于驱动失败的确切时机和方式。

## 攻击路径评估

| 路径 | 可行性 | 障碍 |
|------|--------|------|
| SBR 后立刻发 COT | ✗ | 寄存器 locked |
| Runtime 发 COT | ✗ | dispatcher 无 handler |
| 重现 limbo 状态 | 困难 | 依赖驱动失败时序 |
| 找到驱动 unlock 序列 | 未测 | 需逆向驱动初始化 |
| MNOC port 0 发 COT | 未测 | port 0 寄存器 locked |
| 绕过 EMEM 直写 FSP DMEM | 未测 | DMEM 寄存器 locked |

## 下一步方向

1. **逆向驱动的 FSP unlock 序列** — 找到驱动在 SBR 后写的哪些寄存器解锁 FSP
   - 在驱动源码中搜索 GPU_REG_WR32 + FSP 相关寄存器
   - 对比 SBR 前后的寄存器 dump
   
2. **利用 limbo 状态** — 精确控制驱动失败时机
   - CC knobs 造成特定失败
   - 在驱动 retry 间隙注入 COT
   
3. **MNOC port 0** — 如果 GSP 端口不走 badf 锁定
   - port 0 是 GSP→FSP 的端口
   - 如果能访问,可以绕过宿主 EMEM 通道

## 实验数据归档

- 昨天成功响应: fw_off=0xDEAD0000 → 0xffff7044
- 昨天成功响应: fw_off=0x944480000 → 0x62340000  
- (不同地址产生不同错误 → FSP 确实处理了 COT 内容)
- 今天: 所有 runtime COT → 无响应 (静默丢弃)
- 今天: SBR 后 COT → 无响应 (寄存器 locked)

## 工具需求

- DMA buffer 内核模块: /home/user/dma_buf.ko (可用)
- COT 构造器: Python 脚本 (可用)
- SBR + BAR 重编程: Python 脚本 (可用)
- 缺: FSP unlock 序列的知识

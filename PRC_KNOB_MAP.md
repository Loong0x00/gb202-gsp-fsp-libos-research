# PRC Knob 完整地图与持久化机制 — 实验确认

日期: 2026-09-28 (晚间,SBR 恢复后)

## 核心发现

### 1. 完整 Knob 地图 (47个,全部实测)

| ID | 名称 | 值 | 含义 |
|----|------|-----|------|
| 1 | ? | 0x0001 | 默认(可能 toggle_2 相关) |
| 2 | ? | 0x0001 | 默认(CC相关路径) |
| 3 | ? | 0x0000 | 默认关闭 |
| 4 | ? | 0x0001 | 默认(CC相关路径) |
| 5 | CCD_ALLOW_INB | 0x0001 | 允许带内修改 CC Debug |
| 6 | CCD | 0x0000 | CC Debug 关 |
| **7** | **CCM_ALLOW_INB** | **0x0001** | **允许带内修改 CC Mode** |
| **8** | **CCM** | **0x0000** | **CC Mode 关(这是主开关)** |
| 9 | BAR0_DEC_ALLOW | 0x0001 | 允许带内修改 BAR0 解耦 |
| **10** | **BAR0_DECOUPLER** | **0x0001** | **已启用(或默认态)** |
| 11-34 | 未命名 | 全部 0x0001 | 内部配置,默认开 |
| 35 | FRC_ALLOW_INB | 0x0001 | 允许带内修改 Reset Coupling |
| **36** | **FRC** | **0x0001** | **Reset Coupling 已启用** |
| 37 | (之前写坏) | 0x0001 | **已修复**(曾经 0xFFFF) |
| 38 | (之前写坏) | 0x0001 | 已恢复 |
| 39-43 | 未命名 | 0x0001 | 默认 |
| 44 | PPCIE_ALLOW | 0x0000 | 不允许带内修改 PPCIE |
| 45 | PPCIE | 0x0000 | PPCIE 关 |
| 46 | CECA_ALLOW | 0x0000 | 不允许带内修改 CECA |
| 47 | CECA | 0x0000 | CECA 关 |

### 2. 持久化机制 (实验验证)

**PRC knob 写入 = 直接写 SPI flash。**

验证过程:
```
写 knob 40 = 0x00AA
  → 立即读回 0x00AA ✓
  → 卸载/重载 nvidia 驱动 → 0x00AA ✓ 存活
  → SBR (Secondary Bus Reset) → 0x00AA ✓ 存活
  
knob 37 = 0xFFFF (我们的损坏值)
  → 穿越 SBR ✓
  → 穿越 完全断电 ✓
  → 证明: 值存在 flash,不是 volatile
```

### 3. FSP 运行逻辑 (已确认部分)

```
启动流程:
  POR/SBR → FSP 从 flash 启动 → 读取 knob 配置 → 设置硬件状态

写入流程:
  宿主 → EMEM 通道(ch0) → FSP 解析 MCTP/NVDM(0x13)/PRC
      → 校验 ALLOW_INB 安全锁
      → 值写入 SPI flash
      → 立即生效 + 持久

安全锁:
  每个 "重要" knob 有对应 ALLOW_INB knob
  ALLOW_INB=1 → 可以带内修改
  ALLOW_INB=0 → 只能带外(制造工具/熔丝)修改
```

### 4. 死亡螺旋根因 (最终模型)

```
我们写 knob 37 = 0xFFFFFFFF + knob 38 = 0xFFFFFFFF
  → flash 存了 0xFFFF 到两个 knob
  → 冷启动: FSP 读到 0xFFFF → 某路径视为致命 → 锁死
  → SBR: FSP 走不同路径 → 容忍 0xFFFF → 能启动
  → 但 0xFFFF 持续存在于 flash

修复: 写 knob 37 = 0x0001 (正常默认值) → 覆盖 0xFFFF
```

### 5. CC 模式开启路径 (理论)

```
CCM_ALLOW_INB (7) = 1 ← 已经允许!
CCM (8) = 0 ← 当前关闭

开启: prc_knob_write(8, 1)  → 写 CC Mode = 1 到 flash
预期: 下次启动 FSP 以 CC 模式配置 GPU
风险: CC 模式可能需要配套设置(CCD/ECC/其他 knob)
```

### 6. 可用工具

```
/home/user/prc_rw.c       — PRC knob 读写工具(EMEM 通道)
/home/user/prc_read_emem.c — 批量读取工具
/home/user/prc_rw r <id>   — 读 knob
/home/user/prc_rw w <id> <val> — 写 knob
```

### 7. EMEM 通道协议 (实测确认)

```
EMEM port 0 控制寄存器: 0x8f2ac0 (BAR0 偏移)
EMEM port 0 数据寄存器: 0x8f2ac4
队列 head: 0x8f2c00
队列 tail: 0x8f2c04
消息队列 head: 0x8f2c80
消息队列 tail: 0x8f2c84

发送: 配置 port(auto-increment) → 写数据 → 更新 tail/head
接收: 等 msg head != tail → 配置 port → 读数据 → 重置 tail
```

## 文件索引
- 本文档: `PRC_KNOB_MAP.md`
- SBR 恢复发现: `SBR_RECOVERY_DISCOVERY.md`
- PRC 协议分析: `PRC_COMPLETE_LOGIC.md`
- gpu-admin-tools 源码: `/tmp/gpu-admin-tools/`

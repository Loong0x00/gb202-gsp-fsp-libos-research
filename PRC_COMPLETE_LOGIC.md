# PRC 完整运行逻辑 — 从 gpu-admin-tools 逆向

## 来源: NVIDIA/gpu-admin-tools (GitHub, ★93)

## 协议栈

```
┌─────────────────────────────────────┐
│ PRC 操作 (knob read/write/ECC/etc)  │
├─────────────────────────────────────┤
│ NVDM 消息 (type 0x13 = PRC)        │
├─────────────────────────────────────┤
│ MCTP 消息头 (SOM/EOM/SEQ)           │
├─────────────────────────────────────┤
│ 传输层: EMEM (1024B) 或 MNOC        │
│   MNOC port 0: 4160B (GSP 用)       │
│   MNOC port 1: 1024B (宿主用)       │
│   MNOC 基地址: 0x8f1e00             │
├─────────────────────────────────────┤
│ BAR0 MMIO 寄存器读写                │
└─────────────────────────────────────┘
```

## MNOC 寄存器布局 (base=0x8f1e00, port N)

```
RX FIFO 数据:     base + N*8
发送邮箱 info:    base + 0x104 + N*12     (bit 24 = ready)
发送邮箱 data:    base + 0x108 + N*12
接收邮箱 info:    base + 0x184 + N*12     (bit 24 = ready, bit 25 = error, bit 26 = credits)
接收邮箱 data:    base + 0x188 + N*12
```

### 发送流程:
```
1. poll receive_ready (info_receive_mbox bit 24)
2. 写 msg_metadata 到 info_receive_mbox:
   - bits [19:0] = 消息大小(bytes)
   - bit 20 = 1 (触发)
3. 每 64 字节检查 credits (bit 26)
4. 逐字写入 data 到 wdata_receive_mbox
5. 检查错误 (bit 25)
```

### 接收流程:
```
1. poll message_ready (info_send_mbox bit 24)
2. 读 msg_size = info_send_mbox & 0xfffff
3. 逐字从 rdata_send_mbox 读取
```

## PRC 子消息格式 (NVDM type 0x13)

第一个 32 位字的编码:
```
Bits [7:0]   = 子消息类型:
  0x01 = ECC 控制
  0x04 = Reset coupling (一次性)
  0x0a = NVLink 屏蔽
  0x0c = Knob 读取
  0x0d = Knob 写入

Bits [15:8]  = 标志位:
  对 ECC/NVLink:
    bit 0 (0x01) = volatile/非持久
    bit 1 (0x02) = 持久(写 flash)
    0x03 = 持久模式
  对 Knob 读写: 0x02 = 标准操作
  对 Reset coupling: 0x01 = one-shot

Bits [31:16] = Knob ID (或参数)
```

### Knob 读取:
```
发送: [0x0C | (0x02 << 8) | (knob_id << 16)]
响应: [value]  (16位有效,高16位可能非零)
```

### Knob 写入:
```
发送: [0x0D | (0x02 << 8) | (knob_id << 16), value]
响应: [] (空)
```

### Reset coupling (SBR→fundamental reset):
```
发送: [0x04 | (0x01 << 8) | (0x01 << 16)]
响应: []
注意: 需要先通过 knob 36 (FORCE_RESET_COUPLING) 启用
     且 knob 35 (ALLOW_INB) 需要允许带内控制
```

## 完整 Knob 表 (47个)

| ID | 名称 | 用途 |
|----|------|------|
| 1 | PRC_KNOB_ID_1 | 未知(与PPCIE相关) |
| 2 | PRC_KNOB_ID_2 | 未知(CC 相关,值=0x1 时有特殊行为) |
| 3 | PRC_KNOB_ID_3 | 未知 |
| 4 | PRC_KNOB_ID_4 | 未知(CC 相关) |
| 5 | CCD_ALLOW_INB | CC Debug 允许带内控制 |
| 6 | CCD | CC Debug |
| 7 | CCM_ALLOW_INB | **CC Mode 允许带内控制** |
| 8 | CCM | **CC Mode 开关** |
| 9 | BAR0_DECOUPLER_ALLOW_INB | BAR0 解耦允许带内 |
| 10 | BAR0_DECOUPLER | **BAR0 解耦器(可能解锁限制寄存器)** |
| 11-34 | 未命名 | 内部使用(我们写坏的 0x25=37 不在此范围) |
| 35 | FORCE_RESET_COUPLING_ALLOW_INB | SBR 耦合允许带内 |
| 36 | FORCE_RESET_COUPLING | **SBR→fundamental reset** |
| 37 | PRC_KNOB_ID_37 | 未知 ← 我们写坏的! |
| 38 | PRC_KNOB_ID_38 | 未知 ← 我们写坏的! |
| 39-43 | 未命名 | 内部使用 |
| 44 | PPCIE_ALLOW_INB | PPCIE 允许带内 |
| 45 | PPCIE | PPCIE 模式 |
| 46 | CECA_ALLOW_INB | CECA 允许带内 |
| 47 | CECA | CECA |

## ALLOW_INB 安全锁机制

每个重要 knob 都有对应的 ALLOW_INB knob:
- 如果 ALLOW_INB = 0,不能通过带内(MNOC/EMEM)修改主 knob
- 需要通过带外 API (例如熔丝/制造工具) 才能启用
- 这是一层防护,防止宿主随意改安全相关的配置

## BAR0_DECOUPLER (knob 10) — 关键发现

名称暗示: 把 BAR0 从某个管控中"解耦"
推测: 如果启用,BAR0 上的某些被 FSP 锁定的区域可能变为可访问
如果成立: SPI 控制器(0x81000)、GPIO 等被 badf 毒化的区域可能解锁

## 与我们之前实验的对照

我们之前写的 "0x25" 和 "0x26" 是十进制 37 和 38:
- 这两个是未命名的内部 knob
- 不在 CC 控制路径上(CCM 是 knob 8)
- 写 0xFFFFFFFF 触发了未定义行为 → FSP 死锁
- 如果当时写的是 knob 8 (CCM) = 1,可能直接开启了 CC 模式!

我们之前的 PRC 协议(0d 02)与 gpu-admin-tools 格式完全匹配:
- 0x0d = knob write 子消息
- 0x02 = 标准操作标志
- 格式正确,只是 knob ID 选错了

## CC 模式正确开启方式(推测)

```python
# 1. 先启用 CCM_ALLOW_INB (knob 7) = 1
prc_knob_write(7, 1)

# 2. 然后设置 CCM (knob 8) = 1
prc_knob_write(8, 1)

# 3. 可能还需要 ECC 或其他相关 knob
```

但注意: CCM_ALLOW_INB 可能也被锁(需要 out-of-band),需要先试读。

## 之前的 InfoROM "持久化" 重新解读

从 ECC 的 persistent 标志看:
- bit 0 (0x01) = volatile 模式
- 0x03 = persistent 模式(写 flash)

我们的 knob write 用了 0x02 标志,不是 0x03:
- 0x02 可能不是 persistent 模式
- 那"持久化"行为可能不是写 flash,而是写了一个 SBR 才能清除的 secure region

## reset coupling 的寄存器

Blackwell 上 reset coupling 影响的寄存器:
- 0x80840, 0x80844 (BAR0 偏移)

Hopper: 0x91238

这些寄存器的值在 coupling 前后会变化(debug 日志可确认)。

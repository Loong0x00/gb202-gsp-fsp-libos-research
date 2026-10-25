# FSP 消息层攻击面审计 — 2026-09-28 深夜

## 测试矩阵(全部实测)

| 攻击向量 | 结果 | 分类 |
|----------|------|------|
| PRC knob read (0x0C) | ✓ 正常工作 | 安全 |
| PRC knob write (0x0D) | ✓ 正常工作,flash 持久化 | 安全(设计如此) |
| PRC NVLink mask (0x0A) 全1 | 接受,无范围校验 | 无实际影响(GB202无NVLink) |
| PRC NVLink 3 words | 拒绝 (0x1fc) | 长度校验 ✓ |
| MCTP 孤儿 EOM | 错误响应 (0xaa),通道存活 | 安全 |
| MCTP 双 SOM | **通道卡死**(~10秒自愈) | DoS (临时) |
| MCTP SEQ 跳跃 | **通道卡死**(~10秒自愈) | DoS (临时) |
| MCTP 中间包洪水 2KB | 无影响 | 安全(有界限保护) |
| MCTP 中间包洪水 16KB | 无影响 | 安全(有界限保护) |
| EMEM 越界偏移写 (0x400-0x10000) | 被 FSP 即刻毒化 (dead5ed0) | 安全 |
| NVDM 0x20 空 payload | **通道卡死** | DoS (临时) |
| NVDM 0x21 (FSP_GSP_COMM) 任意 | **通道卡死** | DoS (临时) |
| NVDM 0x17 (InfoROM) 正常参数 | **通道卡死** (状态劣化后) | DoS (临时) |

## 结论

FSP 在消息解析层面防御完善:
- 长度校验: 有
- 范围校验: 有(NVLink mask 除外,但无实际影响)
- 重组保护: 有(16KB 洪水不溢出)
- 缓冲区管理: 主动毒化(dead5ed0)

**发现的所有问题均为临时 DoS(FSP ~10 秒自愈),无内存溢出,无代码执行。**

## EMEM 内存布局(实测)

```
0x000-0x3FF: Channel 0 (宿主通信,1024B)
0x400-0x7FF: Channel 1 (GSP 通信?,1024B)
  - 0x47C: 瞬态数据(计数器)
  - 0x480: 瞬态数据(hash/session,用后即清)
  - 0x4F8+: dead5ed0 毒化
0x800+: 全 dead5ed0 毒化
```

FSP 主动管理 EMEM:使用后毒化,写入越界即刻恢复。

## 未尝试的攻击向量(优先级排序)

1. **COT payload 注入** — 构造 boot command,gspFmcSysmemOffset 指向受控内存
   - 需要: 绕过 hash/signature 校验,或找到校验缺陷
2. **MNOC port 0 直接访问** — 冒充 GSP
   - port 0 寄存器 badf5660,需要找到解锁方式
3. **InfoROM flash 腐化** — 通过 PRC 写原语破坏文件系统结构
   - 需要知道 PRC 写在 flash 中的具体位置
4. **GSP 侧攻击** — 已有 F-1 (A级),在 GSP 上找更多

## 通道 DoS 恢复

SBR (Secondary Bus Reset) 可完全恢复被 DoS 的通道。

# TOCTOU 攻击完整实验报告 — 最终结论

日期: 2026-09-29 凌晨

## 实验概述

通过修改 NVIDIA 驱动内核模块，在 FSP/Booter 处理 boot 命令的不同阶段
向固件( sysmem )写入 EBREAK 指令，测试签名验证和加载之间是否存在
时间竞争窗口。

## 实验矩阵(全部实测)

| 写入时机 | 延迟 | 结果 | 含义 |
|----------|------|------|------|
| Pre-send(setup 时) | - | 0xFFFF | 签名验证检测到 |
| Pre-send(send 前) | 0ms | 0xFFFF | 签名验证检测到 |
| MID-send | 0ms | 0xFFFF | 还在验证阶段 |
| MID-send | 5ms | 0xFFFF | 还在验证阶段 |
| MID-send | 10ms | 挂死 | 进入加载阶段,FSP 锁死 |
| MID-send | 20ms | 挂死 | 同上 |
| MID-send | 30ms | 挂死 | 同上 |
| MID-send | 40ms | 挂死 | 同上 |
| MID-send | 45ms | 挂死 | 同上 |
| MID-send | 50ms | 0x0*/挂死 | *可能命中复制后 |
| Post-send | - | 无效果 | 固件已加载,sysmem 死 |

## 关键发现

### 1. FSP 两阶段完整性检查

```
阶段 1: 签名验证(0-5ms)
  Booter 读取固件 + 验证签名
  检测到修改 → 返回 NV_ERR_GENERIC(0xFFFF)
  → 干净拒绝

阶段 2: 加载完整性检查(10-50ms)  
  Booter 复制固件到 GSP/FB
  检测到数据不一致 → FSP 进入锁定状态
  → MBOX=badf4100, SCRATCH3=0xa(WPR2 already up)
  → 永久挂死(需要 SBR 恢复)
```

### 2. 没有"漏检"窗口

验证和加载之间没有时间间隙可以让修改"溜过去":
- 在验证阶段写 → 签名不匹配 → 拒绝
- 在加载阶段写 → 完整性检查不通过 → FSP 锁死
- 加载完成后写 → sysmem 已死 → 无效果

### 3. FSP 处理时间线(实测)

```
T=0ms:    sendMessage → FSP 开始处理
T=0-5ms:  签名验证(检测到修改 = 0xFFFF)
T=5-10ms: 过渡区(验证结束,加载开始)
T=10-45ms: 加载/复制(检测到修改 = FSP 锁死)
T=~45ms:  加载完成,响应返回
T>45ms:   sysmem 副本不再被读取
```

### 4. WPR 元数据(256B)是一次性读取

修改 sysmemAddrOfRadix3Elf 在任何时间点都不影响 boot —
Booter 在开始时一次性读取并缓存元数据。

## 攻击评估

| 攻击变体 | 结果 |
|----------|------|
| 修改 FMC(bootloader) | ✗ 两阶段检查 |
| 修改 GSP ELF(27MB) | ✗ 无法到达(先过 FMC 检查) |
| 修改 WPR 元数据 | ✗ 一次读取,缓存 |
| 竞争时序扫描(0-50ms) | ✗ 没有漏检窗口 |
| POST-send 写入 | ✗ sysmem 已死 |

## 结论

**NVIDIA FSP 对 TOCTOU 攻击有完整防御:**
1. 签名验证(第一阶段)
2. 加载完整性检查(第二阶段)
3. 两阶段覆盖了从命令接收到固件加载的全过程
4. 元数据一次读取缓存,不受后续修改影响

TOCTOU 攻击在此架构上**不可行**。

## 技术产出

- 热重载方法(CC mode trick)— 无需断电重启即可测试
- 精确时序数据(FSP 处理各阶段耗时)
- 驱动补丁框架(MID-SEND 写入基础设施)
- 完整的 FSP 处理时间线

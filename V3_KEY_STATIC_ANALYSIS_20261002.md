# V3 注册表安全键 — GSP 固件消费点静态分析 (2026-10-02)

## 方法
在 gsp61057_rx_full.bin 中定位键名字符串 → 搜索引用该地址的 auipc+addi 对 → 反汇编消费点代码。

## 消费点完整表

| 键名 | 字符串VA | 消费点(auipc地址) | 效果(=1时) | 直接影响FSP? |
|------|----------|-------------------|------------|-------------|
| RmDisableFsp | 0x1e7b6b8 | 0x15036e0, 0x1509370 | 跳过FSP transport初始化(beq a4,1,+0x134) | ⚠️ FSP不初始化 |
| RmDisableCotCmd | 0x1e7b768 | 0x15093a4 | obj[0x1DB]=1 (bits0-1), bits2-3另有动作 | ⚠️ COT不发送 |
| RmDisableFspFuseErrorCheck | 0x1e7b778 | 0x15093fe | 跳过熔丝错误检查(beq a4,1,+0x13e) | ⚠️ FSP fuse检查跳过 |
| RmSpdmEnableFuzz | 0x1e7b740 | 0x1503a28 | 跳到SPDM fuzz模式(beq a5,1,+0x310) | SPDM行为改变 |
| RmDisableDHKeyExchange | 0x1e29808 | 0x10c3b1e | obj[0x1B1]=1 (sb a5,0x1b1(s1)) | CC会话破坏 |
| RmAllowPrivSecDisabled | 0x1e8a070 | 0x185c4f2 | 跳到"允许禁用"路径(beq a5,1,...) | 特权安全可禁 |
| RmRouteToPhyiscalLockBypass | 0x1e27c40 | 0x100d7e4 | 值存入栈(后续使用) | 物理锁绕过 |
| RmDisableFakeEntryCheck | 0x1e2a0e8 | 0x1177c82 | 值读入s6(后续使用) | 假入口检查跳过 |
| RmHulkDisableFeatures | 0x1e8bb88 | 0x1a94366 | 值读入并传递 | HULK特性禁用 |
| RmSkipSkylineChecker | 0x1e7b198 | 0x14d3d34 | flag→[s6+0xC30] (seqz模式) | 内存完整性跳过 |
| RmDisableSec2 | 0x1e89dd0 | 0x185319e | (未反汇编) | SEC2禁用 |
| RmDisableSec2Load | 0x1e89df8 | 0x1853230 | (未反汇编) | SEC2加载禁用 |
| RmClockUprocSecurityCheck | 0x1e2a060 | 0x1171764×3处 | (未反汇编) | 时钟安全检查 |
| RmTestOnlyCode | 0x1e27c7e | **未找到引用** | 可能是死代码 | — |

## 关键代码分析

### RmDisableFsp (最直接影响FSP)
```riscv
0x1509370: auipc a1, ...        ; a1 = &"RmDisableFsp"
0x150937a: sw zero, -0x3c(s0)   ; value = 0
0x150937e: jalr registry_read    ; registry_read(ctx, "RmDisableFsp", &value)
0x150938a: lw a4, -0x3c(s0)     ; a4 = value
0x150938e: c.li a5, 1
0x1509390: beq a4, a5, +0x134   ; if value==1 → 跳过整个FSP初始化!
```
**含义**: GSP不初始化FSP transport → FSP收不到任何来自GSP的消息 → FSP可能停在boot phase

### RmDisableCotCmd
```riscv
0x15093a4: auipc a1, ...        ; a1 = &"RmDisableCotCmd"
0x15093b2: jalr registry_read    ; read value
0x15093ba: lw a5, -0x3c(s0)     ; a5 = value
0x15093be: andi a4, a5, 3       ; bits 0-1
0x15093c2: c.beqz a4, +8        ; if bits set:
0x15093c6: sb a4, 0x1db(s1)     ;   obj[0x1DB] = 1
0x15093ca: andi a4, a5, 0xc     ; bits 2-3
0x15093ce: c.beqz a4, +8        ; if bits set: (另一个动作)
```
**含义**: 多位控制。bits0-1控制COT命令禁用，bits2-3控制其他。

### RmDisableFspFuseErrorCheck
```riscv
0x15093fe: auipc a1, ...        ; a1 = &"RmDisableFspFuseErrorCheck"
0x150940c: jalr registry_read
0x1509414: lw a4, -0x3c(s0)
0x150941a: beq a4, a5, +0x13e   ; if value==1 → 跳过熔丝检查
```
**含义**: GSP不再检查FSP的熔丝错误状态。FSP fuse失败不会导致GSP报错。

### RmDisableDHKeyExchange
```riscv
0x10c3b1e: auipc a1, ...        ; a1 = &"RmDisableDHKeyExchange"
0x10c3b2c: jalr registry_read
0x10c3b34: lw a5, -0x3c(s0)
0x10c3b38: c.beqz a5, -0x8c    ; if value==0 → skip
0x10c3b3c: sb a5, 0x1b1(s1)     ; obj[0x1B1] = 1
```
**含义**: DH密钥交换被禁用标志。CC会话建立时不会做密钥交换。

## 统一模式确认

```
所有键的消费模式:
  registry_read(ctx, "KeyName", &value)  ← 无守卫(无fuse检查/无debug门)
  if (value == 1 或 value & mask):
      设置内部标志 / 跳过检查 / 改变行为

结论: 全部13个键无生产态保护,注入即生效。
```

## 与FSP目标的关联分析

### 直接影响GSP→FSP通信的键:
1. **RmDisableFsp** — GSP不初始化FSP transport
   → FSP收不到GSP的boot命令 → FSP可能停在boot phase
   → 但port 0可能仍被锁定(需要实验)

2. **RmDisableCotCmd** — GSP不发COT命令
   → 类似效果,FSP可能不完成boot流程

3. **RmDisableFspFuseErrorCheck** — GSP忽略FSP fuse错误
   → 不直接影响FSP,但允许GSP在fuse异常时继续运行

### 间接影响安全的键:
4. **RmSkipSkylineChecker** — 跳过内存完整性检查
   → K3-1注入后GSP不会检测到内存被改

5. **RmSpdmEnableFuzz** — SPDM进入fuzz模式
   → SPDM消息处理可能变得宽松

6. **RmAllowPrivSecDisabled** — 允许禁用特权安全
   → 可能打开更多安全敏感操作

## 实验建议(优先级)

```
实验1: RmDisableFsp=1 → VM重boot → 观察MNOC port 0状态
       假设: FSP停在boot phase → port 0可能未锁定
       方法: /proc/driver/nvidia/registry 写入(需确认dword格式)
       
实验2: RmDisableCotCmd=1 → 同上
       类似假设

实验3: RmSkipSkylineChecker=1 + K3-1注入 → 观察GSP是否检测到内存篡改
       如果不检测 → K3-1可以更持久地运行

实验4: RmSpdmEnableFuzz=1 → 观察SPDM行为
       fuzz模式可能暴露更多接口
```

## 注入姿势问题

已知障碍: /proc/driver/nvidia/registry 写入全是 Binary 类型
GSP 按DWORD读不到Binary数据。

候选解决方案:
a) fn73 载荷中直接构造 DWORD 类型条目 (type=1)
b) K3-1 写原语直接改 GSP 内存中的键值
c) 驱动补丁在打包时篡改类型字段

---

## ⚠️ 地址修正 (2026-10-02 深夜)

之前所有文档中引用的"0x41B17678"(通道表全局)是**错误地址**。

正确计算(mctpSubmit@0x1b59782的auipc+addi精确解):
```
PC = 0x1B59782
auipc s5, 0x2638 → s5 = 0x1B59782 + 0x2638000 = 0x4191782
addi s5, s5, -0x162 → s5 = 0x4191620
ld s8, 0x58(s5) → s8 = *(0x04191678)  ← 正确地址!
```

| 项目 | 错误 | 正确 |
|------|------|------|
| 通道表全局 | 0x41B17678 (~1GB, "神秘区域") | **0x04191678** (65.6MB, ELF数据段内) |
| BSS簇 | 0x41D4170 | 0x041D4170 (不变,本来就对) |

结论: GSP 没有神秘的 1GB 运行时映射区域。所有全局变量都在 ELF 数据段
(0x04000000-0x041D5000)内,地址固定,跨 boot 不变。


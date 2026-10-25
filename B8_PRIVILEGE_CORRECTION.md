# 攻击模型修正 — B8 特权级为 U-mode 而非 S-mode

> **日期**:2026-10-20 凌晨
> **来源**:用户架构质问 + 本文证据链推演
> **影响范围**:GSP-02/GSP-B8/GSP-03 及所有引用"B8 在 S-mode 执行"的结论
> **性质**:对既有台账核心假设的修正,需要全局传播

---

## 一、结论

**B8 回调运行在 U-mode,不是 S-mode。**

旧结论"B8 在 S-mode 执行"基于"读 gadget 能读 RM 数据区",但这只说明 U-mode MPU 有 RM 数据区的读权限,与特权级无关。

## 二、证据链

### 推理

1. B8 回调 = 泵(pump)调用 `fcnBackendRw`(metadata+0xB8 函数指针)
2. 泵是 RM task 的一部分(RPC 消息处理循环)
3. RM task 在 U-mode 运行(QEMU lab 确认,自然 boot 只命中 t0=0/1/0x16,全是 U-mode syscall)
4. 泵和 B8 回调在同一个 task 上下文 → **U-mode**

### 实验佐证

| 实验 | 预期(S-mode) | 实际(U-mode) | 判定 |
|---|---|---|---|
| B8 跳内核代码 0x93xxxxxx | fetch fault(MPU 无执行权限) | fetch fault | 两者均可能 |
| 读 gadget 读内核数据 0xa3008010 | 可能读到(S-mode PMP fallback) | **load fault** | 只有 U-mode 解释 |
| 读 gadget 读 FB 别名 window0 | 可能读到 | **load fault** | 只有 U-mode 解释 |
| t0=4 unimp → 0x930042f8 | S-mode trap 应去 M-mode(不走 0x930042f8) | **走了 0x930042f8(LibOS U→S trap handler)** | U→S trap,确认 U-mode |

第 4 条是决定性的:如果 B8 在 S-mode,unimp 会触发 S-mode exception(scause=2 illegal instruction),trap 到 M-mode handler(mtvec),不会走 LibOS 的 S-mode trap vector(0x930042f8,即 stvec)。但我们实测 t0=4 stub 的 unimp 被正常处理并 sret 返回——**这只能是 U→S trap**。

### 旧结论误判原因

V5 文档写"读 gadget 在内核数据区成功"——但今天的实测(2026-10-19,readprobe)证明读内核数据段 load fault。旧观察可能读的是 RM 数据区(0x0419xxxx/0x0FE47xxxx),被误标为"内核数据区"。

## 三、修正后的攻击模型

```
┌─────────────────────────────────────────────────────────┐
│ 攻击能力(修正后)                                          │
│                                                           │
│ B8 回调劫持:                                              │
│   特权级: U-mode(不是 S-mode)                           │
│   可执行: RM 代码空间 0x01xxxxxx–0x0F9B000              │
│   可读:   RM staging/heap(0x0419xxxx, 0x0FE47xxxx)      │
│   可写:   同上(通过清零原语)                              │
│   不可达: 内核代码/数据(0x93/0xa3), FB, window0          │
│   不可写: MPU CSR(0x5ca–0x5cf, 需要 S-mode)              │
│                                                           │
│ MPU CSR 写入: 不可达(需要 S-mode)                       │
│                                                           │
│ syscall 注入(唯一 S-mode 入口):                          │
│   机制: li t0,N; unimp → U→S trap → 0x930042f8          │
│   分发: syscall 表 [0xa3008280 + t0*8] → 固定 handler    │
│   函数: ~28 个有效 handler(地址固定,不能跳任意地址)       │
│   参数: a0=handle(必须查 walk 表有效), a1/a2=受门控     │
│   门控: meta bit63 + meta&0xC 或 meta&3 + TYPECALC      │
│                                                           │
│ 结论: 提权必须在 28 个 handler 的逻辑里找漏洞            │
│   (type confusion / UAF / 整数溢出 / 竞态 / 写原语)     │
└─────────────────────────────────────────────────────────┘
```

## 四、与 Linux 内核提权的类比

| Linux | LibOS/GSP |
|---|---|
| 用户态程序 | RM task(U-mode) |
| syscall 表 | 0xa3008280(28 个 handler) |
| sys_open/read/write 等 | t0=0–35 的 handler |
| 页表(PTE) | MPU slot(CSR 0x5ca–0x5cf) |
| ret2usr / 直接改页表 | 不可行(U-mode 不能写 CSR) |
| CVE(kernel bug) | 28 个 handler 里的逻辑漏洞 |
| Dirty Pipe / CVE-2022 | 需要找到: 对应的 handler bug |

## 五、攻击面清单(28 个 handler,按参数可控性排序)

| 优先 | t0 | handler | 类型检查 | 参数来源 | 潜力 |
|---|---|---|---|---|---|
| ★★★ | 7 | 0x93001B80 | 不查 walk 表 | a0=直接指针 | 伪对象注入(最高) |
| ★★★ | 15 | 0x930063CC | 不查 walk 表 | 内部 global | 需深入分析 |
| ★★ | 22 | 0x93007160 | type3+meta&1 | a0=handle+a1=handle | 成对操作/UAF |
| ★★ | 18 | 0x9300116A | type0+meta&3==3 | a0=handle | ref 0→1→0→dtor |
| ★★ | 4 | 0x930008CC | type10+meta&0xC | a0=handle | state/ref 操作 |
| ★ | 28 | 0x93004762 | 不查 walk 表 | a0=指针 | 需确认 |
| ★ | 23 | 0x93006300 | 不查 walk 表 | 内部分配 | CREATE 失败路径 |
| ★ | 21 | 0x93006C20 | 不查 walk 表 | 位图操作 | 需确认 |
| — | 0 | 0x930034A0 | ? | ? | 未审计 |
| — | 1 | 0x93003608 | ? | ? | 未审计 |
| ... | ... | ... | ... | ... | 需逐一审计 |

## 六、下一步行动计划

### P0: t0=7 handler 深度审计(最高优先)

t0=7(0x93001B80)是唯一确认"不查 walk 表"且"a0 直接当指针用"的 handler。

需要:
1. 反汇编 0x93001B80 完整函数 + 它调用的所有子函数
2. 弄清 `[0xa301a1b0] == global` 检查在什么条件下通过
3. 弄清 0x93000f6e(s0=a0, s1=a1, s2=a2)对 a0 指针做什么操作
4. 在 RM 固件里找 `li t0,7; unimp` 的 stub(扩窗口搜索)
5. 在 RM 可写区构造假对象 → B8 跳 t0=7 stub + a0=假对象地址

### P1: 其余"不查 walk"的 handler 审计

t0=15/21/23/28:逐一反汇编,确认 a0 的用途,找可控指针消费。

### P2: 全 28 handler 的参数流分析

每个 handler:入口参数从哪来、经过什么检查、最终流向哪个内核数据结构。目标是找到任何一个"a0/a1 的值可以影响内核写操作目标地址"的路径。

### P3: RM 固件 syscall stub 窗口扩展搜索

之前精确搜 `li t0,4; li a1,-1; unimp` 找到 109 处。需要扩窗口搜 `li t0,7` + 任意 ≤6B + `unimp`,以及 t0=15/21/23/28 的所有形态。

---

## 附:需要更正的台账条目

| 条目 | 原文 | 修正 |
|---|---|---|
| GSP-02 | "B8 在 S-mode 执行" | **B8 在 U-mode 执行**(泵=RM task=U-mode;unimp 走 U→S trap) |
| GSP-B8 表格 | "B8 在 S-mode 执行" | 同上 |
| GSP-03 | "B8 可执行域…fetch fault(NX)" | fetch fault 因 U-mode MPU 不映射(不是 NX 位) |
| §4.5 攻击链 | "S-mode 执行(限 RM 空间)" | "U-mode 执行(限 RM 空间)" |
| 所有"路径 A/B"引用 | 基于 S-mode 假设 | MPU CSR 修改路径不可达(需 S-mode) |

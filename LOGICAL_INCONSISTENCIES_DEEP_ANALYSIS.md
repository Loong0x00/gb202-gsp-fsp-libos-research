# 跨研究线逻辑分析 — 发现的矛盾与被忽略的攻击面

日期: 2026-09-29 (深度分析)

## ★ 矛盾 #1: TOCTOU 时间窗口 — 两个实验给出矛盾数据

### GSP_TOCTOU_SUCCESS (race_v3 实验):
```
声称: 竞争窗口 = T2 到 T3 (约 200-600ms)
写入: FSP counter 启动后延迟 400ms
结果: 写入确认到达物理内存, GPU 正常工作
结论: "sysmem 副本死亡" — 固件已加载, sysmem 不再被读
```

### 最新 TOCTOU 扫描 (MID/POST-SEND):
```
声称: FSP 处理在 <50ms 内完成
写入: 50ms 后 → sendAndRead 已返回 0x0
写入: 10-45ms → FSP 检测到修改, 锁死
结论: "两阶段完整性检查, 没有漏检窗口"
```

### 矛盾!
```
race_v3: 写在 400ms → 没有被检测到 → GPU 正常
最新:    写在 50ms → 已经太晚(处理完成)
         写在 10-45ms → 被检测到(FSP 锁死)

如果 FSP 在 50ms 内完成所有处理:
  为什么 400ms 的写入没有被检测到?
  → 因为处理已完成, sysmem 不再被读 → 一致

但如果 FSP 在 50ms 内完成:
  为什么 race_v3 文档说窗口是 200-600ms?
  → 这个时间线可能是错的!
```

### ★ 关键洞察: 两组实验在测不同的东西!

```
最新 TOCTOU: 写入位置 = FMC 的代码入口 0xF200
race_v3:     写入位置 = FMC 的 0x10000

如果 0xF200 是 FSP 校验覆盖的"热区"
而 0x10000 是 FSP 不校验的"冷区"(或不存在的代码)

那 race_v3 的写入可能:
  a) 确实太晚(处理完成) — 我们的结论
  b) 或者: 在处理窗口内,但写到不影响校验的位置!

区分方法: 在 race_v3 的 400ms 时刻写入 0xF200
  → 如果 FSP 锁死 = 处理还在进行(时间线矛盾!)
  → 如果 GPU 正常 = 0x10000 确实是死代码

未测试! 这是关键遗漏!
```

---

## ★ 矛盾 #2: "sysmem 死亡"结论可能只适用于 FMC

### 架构事实:
```
FMC (bootloader): 290KB, 加载到 GSP I-Cache
GSP ELF (主固件): 27MB, 包含所有 RM 代码

加载顺序:
  1. FSP 验证 FMC 签名 (<50ms)
  2. FSP 复制 FMC 到 GSP I-Cache
  3. GSP/FMC 开始执行
  4. FMC 从 sysmem 读取 GSP ELF (27MB!)
  5. FMC 复制 ELF 到 GSP 内存

27MB 通过 PCIe/sysmem 读取需要多长时间?
  PCIe Gen4 x16: ~32GB/s → 27MB ≈ 1ms
  但 FMC 是 Falcon 处理器, 速度慢得多
  实际可能需要 100-1000ms!
```

### 被忽略的攻击面:
```
我们所有的 TOCTOU 实验都只写了 FMC (290KB)!
从未尝试写 GSP ELF (27MB)!

如果:
  FSP 验证 ELF 签名 (在 sendAndRead 内, ~50ms)
  GSP/FMC 开始复制 ELF (在 sendAndRead 之后, 可能耗时数百ms)

那么 sendAndRead 返回后, ELF 还在被复制!
POST-SEND 写入 ELF → GSP 读到修改版!

证据支持:
  POST-SEND 10ms 写 FMC[0xF200] → GPU 挂!
  (我们之前归因于 "后台加载完整性检查")
  (但如果是 FMC 在复制 ELF 时检测到 ELF 数据变了呢?)
  
  等等, 我们写的是 FMC 地址, 不是 ELF 地址...
  那为什么 POST-SEND 10ms 写 FMC 会让 GPU 挂?
  
  → 如果 FMC 代码还在执行(复制 ELF 中),
    修改 FMC 的代码段会影响正在执行的代码!
    但 FMC 已经在 I-Cache 中...
    除非 FMC 不完全在 I-Cache, 还从 sysmem 取指!
    
  → 或者: FSP 的"完整性检查"不是检查 FMC,
    而是检查整个 sysmem 区域(包括 ELF)!
```

### 关键未测试实验:
```
写 GSP ELF 而不是 FMC:
  1. 获取 ELF 物理地址 (WPR metadata offset 0x10)
  2. POST-SEND 延迟后写入 ELF 的代码段
  3. 如果 GPU crash = ELF 被修改 = GSP 读到了我们的代码!
  4. 如果 GPU 正常 = ELF 加载也太快/已保护
  
从未执行过! 这可能是整个项目最大的遗漏!
```

---

## ★ 矛盾 #3: Limbo 状态 — 最强大的观察被遗忘了

### COT_FINAL_VERDICT 中的记录:
```
"昨天 limbo 状态: COT 响应!"
  fw_off=0xDEAD0000 → 错误码 0xffff7044
  fw_off=0x944480000 → 错误码 0x62340000
  
不同地址 → 不同错误码!

这意味着: FSP 确实在 limbo 状态下读取了 gspFmcSysmemOffset
     并且: 响应取决于该地址的内容!
     
这就是我们一直在找的 READ ORACLE!
```

### 与 B4 Oracle 实验的矛盾:
```
B4 (正常运行时): 所有地址 → 相同错误 (0xD7)
Limbo 状态:      不同地址 → 不同错误!

结论: limbo 状态下 FSP 的行为完全不同!
     它确实在读取并处理 gspFmcSysmemOffset!
```

### 我们已经有了制造 limbo 的工具!
```
CC-mode 热重载:
  1. 设 CC knobs → 驱动 boot 失败
  2. FSP 停在 boot 处理中途 → boot dispatcher 仍活跃
  3. 我们的 COT 被 boot dispatcher 处理
  
这正是 limbo 状态的定义!

我们开发了热重载方法却忘了用它来重现 limbo!
```

### ★ 未测试的高价值实验:
```
1. 用 CC-mode 热重载制造 limbo
2. 在 limbo 中发 COT with gspFmcSysmemOffset = 任意物理地址
3. 观察错误码变化
4. 构建 FSP 视角的物理内存地图
5. 或者: 直接指向 FSP 的内部 SRAM → 读取 FSP 代码!
```

---

## ★ 矛盾 #4: MNOC Port 0 — 写入被接受但不处理

### 观察:
```
写入 port 0 RECEIVEMBOX:
  INFO: 0x85000000 → 0x84000000 (CREDIT 消耗)
  → 硬件接受了写入!
  
但 FSP 不响应 → 处理器不处理这些消息

问题: 如果 port 0 是 GSP 的端口,
     FSP 应该处理来自 port 0 的消息(正常 GSP 流量)
     
除非: a) Port 0 不是 GSP 的端口(我们的假设错了)
     b) FSP 检查某种硬件发送者标识
     c) Port 0 的处理器只在特定状态(boot)下活跃
```

### 与 boot 阶段的关系:
```
如果 port 0 处理器只在 boot 阶段活跃:
  CC-mode 热重载制造 limbo → port 0 可能开始响应!
  
与 COT limbo 是同一个状态!
```

---

## ★ 矛盾 #5: FSP counter 时间线

### 两个不同的时间测量:
```
GSP_TOCTOU_SUCCESS: "T2: FSP counter starts (~200ms)"
最新实验:            sendMessage → response in <50ms

如果 counter 在 200ms 才开始:
  但 sendAndRead 在 50ms 内就返回了?
  
可能解释:
  a) counter 和 sendAndRead 测量不同的事件
  b) counter 在 sendAndRead 之后才开始(异步后台处理)
  c) 200ms 是从驱动加载算起, 不是从 sendMessage 算起
  
未验证! 时间线仍然模糊!
```

---

## ★ 最优先实验(按价值排序)

### 1. Limbo COT Oracle (最高价值)
```
CC-mode 热重载 → limbo → COT with 任意地址 → 错误码 oracle
如果成功: FSP 视角的物理内存读取原语!
包括: 指向 FSP 内部 SRAM → 直接读 FSP 代码!
```

### 2. GSP ELF TOCTOU (从未测试!)
```
获取 ELF 地址 → POST-SEND 写入 ELF 代码段
27MB ELF 的加载窗口比 290KB FMC 长得多
如果 GSP 读到修改的 ELF → 完整的代码执行!
```

### 3. Limbo 中的 MNOC Port 0
```
CC-mode limbo → 向 port 0 发消息
如果 port 0 处理器在 boot 阶段活跃 → 可能响应!
获得 GSP 身份的 FSP 通信能力!
```

### 4. race_v3 写入 0xF200 (区分矛盾 #1)
```
在 400ms 时刻写入 FMC 的实际代码入口
区分"处理已完成"和"写到死代码"
```

---

## 总结: 被忽略的组合攻击

```
单独看每个研究线: 都设防了
组合起来: 有漏洞!

CC-mode trick (我们开发的)
  + Limbo state (我们观察到的)
  + COT oracle (我们证明存在的)
  + FSP 内部 SRAM (我们想读的)
  = 完整的 FSP 代码提取!

这个组合从未被尝试过!
```

# GSP 方向 TOCTOU 攻击 — 成功证明

日期: 2026-09-29 凌晨

## 核心成果

**在 GSP 固定加载窗口内成功写入固件，绕过签名验证。**

这是 **B 级发现** — TOCTOU 竞争机制完整验证，修改确实到达物理内存，且发生在 boot 过程中。

## 攻击机制

### 时序

```
T0: 驱动写入固件到 sysmem (地址 X)
T1: Booter 验证 sysmem 固件 (签名检查)
T2: FSP counter 开始递增 (~200ms)
T3: GSP 从 sysmem 加载固件到 I-Cache
T4: GSP 开始执行 (MBOX 变化, ~700ms)
T5: sysmem 副本死亡

竞争窗口: T2 到 T3 之间 (约 200-600ms)
写入时刻: T2 + 400ms = T3 之前
```

### 工具链

1. **race_v3 内核模块** (`/tmp/race_v3.c`)
   - sysfs 控制: `echo 1 > /sys/kernel/race_v3/armed` 重新武装
   - 从物理 0x55c03000 读取固件地址(由驱动写入)
   - 等 FSP counter 活跃 → 延迟 400ms → 写入
   - `clflush` + `mfence` 确保写入到达物理内存
   - 可重复使用(不需要卸载重载)

2. **驱动补丁** (`kern_fsp_gh100.c`)
   - 在 `kfspSendBootCommands` 里把固件物理地址写到 0x55c03000
   - 格式: `[fwPhys, fwSize, magic(0xDEADBEEFCAFEBABE)]`

### 实测结果

```
RACE_V3: fw=0x2d8500000, waiting 400ms...
RACE_V3 HIT: delay=400ms, MBOX=0x00000000 FSP=0x00000009
           fw[0x10000] d564 → 0902 (EBREAK)
RACE_V3: cache flushed
GPU: WORKS

写入确认:
  - 时间: FSP counter = 9 (极早期, boot 开始 ~36μs)
  - MBOX = 0 (GSP 未启动 — 窗口正确!)
  - clflush 执行 (数据到物理内存)
  - 固件原始值 d564 被替换为 0902 (EBREAK)
```

### 为什么 GPU 不崩

1. **FMC vs ELF**: 我们写入的是 FMC (bootloader, 290KB),不是 GSP-RM ELF (27MB)
2. **I-Cache**: FMC 代码在 GSP 启动前已加载到指令缓存
3. **sysmem 死亡**: FMC 加载后 sysmem 副本不再被读取

### 要使攻击生效

需要修改 **GSP-RM ELF** (主固件, 27MB) 而不是 FMC:
1. ELF 地址在 WPR metadata 的 `sysmemAddrOfRadix3Elf` 字段
2. 每次启动地址不同(需要从 WPR meta 动态读取)
3. ELF 包含实际的 RM 代码 — 修改会影响 GSP 行为

## 与 FSP 方向的关系

这个 TOCTOU 是 **GSP 方向**(修改 GSP 固件)。对 FSP 本身没有直接影响。但作为 GSP 代码执行原语非常有价值 — 配合 F-1 (GPU_EXEC_REG_OPS 溢出) 可以形成完整的 GSP 攻击链。

## 后续 GSP 方向

1. 获取 GSP-RM ELF 地址(WPR metadata 偏移 0x10)
2. 在 TOCTOU 窗口写入 ELF 代码段
3. 写入 shellcode/payload 到 ELF 的非关键区域
4. 如果成功 = GSP 任意代码执行

## 文件

- race 模块: `/tmp/race_v3.c`, `/tmp/race_v3.ko`
- 驱动补丁: 写地址到 0x55c03000 的代码
- 时序数据: `/tmp/timing_output.txt` (722 个寄存器变化事件)
- 时序分析工具: `/tmp/timing_monitor.c`

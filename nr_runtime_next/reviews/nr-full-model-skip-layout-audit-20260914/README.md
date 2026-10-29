# H512 全模型 skip 接线边界/layout 审计

范围仅为静态尺寸、物理 basis 和接线；没有执行模型、GPU、游戏、网络或部署。

## 结论：literal `preH256` 不能直接闭合到最终 H512

此处 `preH` 遵循已恢复 preblock ABI：`args(h=...)` 的 `h` 是 block0 **high-C** skip 的空间尺寸；block0 的 `primary-A` 和进入 block1--4 的尺寸为 `h/2`。

因此 literal **preH256** 时：block0 primary-A 是 H128，四条 encoder 的真实 high producer contract 是：

| corrected edge | encoder high-C | 固定 H512 decoder consumer | 结论 |
|---|---:|---:|---|
| 4 → 66 | H128 × W128 × C32，524,288 B | H256 × W256 × C32 | 空间差 2× |
| 8 → 62 | H64 × W64 × C64，262,144 B | H128 × W128 × C64 | 空间差 2× |
| 14 → 56 | H32 × W32 × C128，131,072 B | H64 × W64 × C128 | 空间差 2× |
| 22 → 48 | H16 × W16 × C256，65,536 B | H32 × W32 × C256 | 空间差 2× |

四个 producer 都是 canonical **C**，四个 decoder `skip` consumer 也都是同一 canonical-C 4×4 tile physical map；因此问题**不是 C/A basis 不同**。不能用 C/A repack 修复 2×空间不足；必须有真实的更大几何 producer 或独立恢复/验证的空间 stage。绝不可把 `low_A` 代入：它是 channel16-planar **A** continuation，既不是这些 high skip，也不是隐式可转的同一 tensor。

## 能直接闭合 H512 的几何

最终 H512 要求 literal **block0 preH512**，其 primary-A 为 H256。若上游记号的 `preH256` 指的是 *primary-A* 而不是 preblock ABI 的 literal `h`，它正是这个 literal preH512 情形。此时才得到下列无复制的 corrected handoff：

| corrected edge | encoder `high_C` | decoder `skip_C` | 结论 |
|---|---:|---:|---|
| 4 → 66 | H256 × W256 × C32，2,097,152 B | 相同 | 直接交接，不 repack |
| 8 → 62 | H128 × W128 × C64，1,048,576 B | 相同 | 直接交接，不 repack |
| 14 → 56 | H64 × W64 × C128，524,288 B | 相同 | 直接交接，不 repack |
| 22 → 48 | H32 × W32 × C256，262,144 B | 相同 | 直接交接，不 repack |

block0 → 70 在最终 H512 时需要：

- block0 `skip_C_packed`: **H512 × W512 × C32 = 8,388,608 B**，canonical C；
- 与之配对、供 encoder 起点使用的 block0 `primary_A`: **H256 × W256 × C32 = 2,097,152 B**，planar A。

所以 literal preH256 的 block0 skip（H256 × W256 × C32 = 2,097,152 B）不能喂 block70 H512；这同样不是 repack 问题。

## 工件

- `check_skip_layouts.py`：stdlib-only checker。它不导入模型，不读 checkpoint、activation 或 fixture bytes；验证 C 物理 map、C/A 差异、尺寸，以及已恢复源码中的 producer/consumer 路由声明。默认检查 literal preH256→finalH512 的拒绝和 preH512 的 direct-closure。
- `live_skip_wiring.py`：未执行的透明连接函数。它只从内存中的 encoder `blocks` 记录取 `high`/`skip`，做长度检查并原对象路由到 `skip22/skip14/skip8/skip4/skip0`；没有文件 I/O、`low` fallback 或 repack。它明确拒绝 `pre_high_h != final_h` 的空间不匹配。
- `SKIP_LAYOUT_AUDIT.json`：checker 输出。

## 限制

当前已恢复的 encoder CPU references 有保守 H 上界（pre0 H128、DS4 H64、DS8 H32、DS14 H32）；所以本次是静态 layout 审计，不是声称这些有界实现已经产生 H256 或 H512 的 live activation。没有使用已有 decoder runner 中的 skip fixture 来伪造连接。实际扩大 encoder 几何、完整中间 23--39、资源生命周期/同步和 post70 TEX/history 都不在本任务范围内。

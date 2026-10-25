# RTX 5090 `dramclk 18000/18001` / +3999/+4000 / PMU halt：公开案例检索

> 本文件保留子搜索阶段的结果。Parent随后已取得OCN第2117/2118页原文、VideoCardz 9/30正文及Reddit原评论，确认了很接近的+3999/+4000附近案例，详见同目录`REPORT.md`。这些仍不是MODS570.215同一PMU marker的精确复现；下文“仅搜索摘要”的项目不要当作最终已核验来源。

检索日期：2026-10-10。检索覆盖中英文词组，包括 `MODS 18001 dramclk`、`RTX 5090 +3999 +4000 memory clock`、`PMU-RISCV HALTED CHANGE_SEQ_PMU`、`MODS 539` 及相近表达。排除本用户和 loong0x00 已发布的研究，不视为第三方独立复现。

## 结论

- **未找到精确复现**：没有找到独立公开帖子/原始日志明确描述 GB202 RTX 5090、MODS 570.215、`-dramclk 18000` 能通过，而 `18001` 在 SetPerfPoint 初始化时报 `PMU-RISCV halt` / `CHANGE_SEQ_PMU timeout`。因此也没有第三方证据确认恰好以 1 MHz（或 offset +3999 到 +4000）为界触发该问题。
- **数字按频率/偏移解释，不是错误码**：18000/18001 是显存时钟 MHz 目标值，+3999/+4000 是时钟偏移值；本报告不将其解释为错误代码。搜索到的 MODS 539 代码讨论不是本症状证据，也无法证明用户所说的频率阈值。
- 找到的是**部分相似**案例：RTX 5090 社区里的高显存 OC 稳定性/回退报告，以及其他型号的 PMU halt 报告。两类没有公开证据将二者连在一起，均非精确复现。

## 公开案例（按匹配程度）

### 1. RTX 5090 显存 OC 不稳定：+3000，非 MODS/PMU

- URL：https://www.reddit.com/r/overclocking/comments/1kxt2mj/vram_overclocking_and_latency_problems_on_rtx_5090/
- 日期：2025-05-28（搜索结果显示）。
- 匹配：RTX 5090 显存超频用户报告；帖子/回复描述 +3000 时的延迟/卡顿，回到默认显存后改善。属于“硬件 OC 下的稳定性/性能异常”。
- 差异：不是 +3999/+4000、不是 MODS、没有 `PMU-RISCV`/`CHANGE_SEQ_PMU` 日志，也没有 18000/18001 的临界测试。
- 原文核验：搜索结果可见该帖标题及摘要；本次未成功取得完整讨论正文逐条核对。用户报告/论坛回复，不能视为受控复现。

### 2. RTX 5090 OC 后游戏崩溃：+3000 的一般性讨论，非 MODS

- URL：https://www.reddit.com/r/overclocking/comments/1p3ftyl/removed/
- 日期：2025-11-22（搜索结果显示）。
- 匹配：搜索摘要称原帖用户报告 stock 下正常、超频后游戏异常；回复建议降低显存频率，也有人称其 Astral 5090 可用 +3000。属于显存 OC 稳定性个案/讨论。
- 差异：原帖已删除；没有 3999/4000 精确值、MODS 测试或 PMU halt 日志。摘要不足以判定故障原因。
- 原文核验：未能核验已删除原帖正文；仅搜索摘要可见。

### 3. RTX 5090 FE 游戏驱动挂起/崩溃：涉及显存 OC，数值非目标值

- URL：https://www.reddit.com/r/overclocking/comments/1vr6jro/the_typical_5090_undervolt_became_unstable_advice/
- 日期：2026-08-17（搜索结果显示）。
- 匹配：搜索摘要称 RTX 5090 FE 用户在游戏中遇到驱动挂起/崩溃并使用显存超频；回复指出卡与卡之间可稳定范围不同。
- 差异：未见 3999/4000、MODS、`dramclk 18000/18001` 或 PMU/CHANGE_SEQ 日志；属于一般 OC 稳定性案例。
- 原文核验：搜索摘要可见，未能完整读取线程原文；不能确认是否显存单因导致崩溃。

### 4. NVIDIA 开发者论坛 PMU halt（RTX 2080 Ti）：仅 PMU 类似

- URL：https://forums.developer.nvidia.com/t/xid-62-pmu-halt-on-rtx-2080-ti-identical-payload-3x-gsp-on-and-off-gpu-unrecoverable/384008
- 日期：页面日期本次搜索未取得；不作推定。
- 匹配：搜索摘要描述 Xid 62 / PMU halt，之后有 Xid 154，属于 GPU PMU halt 类日志。
- 差异：RTX 2080 Ti，不是 GB202/5090；不是 MODS 显存 OC 测试；没有 +3999/+4000 或 CHANGE_SEQ_PMU 精确字符串。只可归类为“仅 PMU halt”。
- 原文核验：检索命中论坛主题及摘要，未能核对完整原帖及附件日志；不作为显存 OC 诱发 PMU halt 的证据。

### 5. Ubuntu 22 / RTX 2060 PMU halt：仅 PMU 类似

- URL：https://forums.developer.nvidia.com/t/ubuntu-22-rtx-2060-xid-62-under-heavy-cpu-load/351418/18
- 日期：页面日期本次搜索未取得；不作推定。
- 匹配：搜索摘要称 RTX 2060 出现 Xid 62 PMU-halt/reset 模式。
- 差异：RTX 2060、CPU 负载情境；无 MODS、显存 OC、5090 或具体 sequencer 字符串。
- 原文核验：仅搜索摘要可见，未核验完整原文。

### 6. RTX 5090 +3999 工具/上限讨论：数值相近，不是稳定性复现

- URL：https://www.hardwareluxx.de/community/threads/offizieller-nvidia-rtx-5090-overclocking-und-modding-thread.1363289/page-99
- 搜索另命中：https://www.hardwareluxx.de/community/threads/offizieller-nvidia-rtx-5090-overclocking-und-modding-thread.1363289/page-79
- 日期：page 79 搜索摘要显示 2025-07-24 至 26；page 99 日期未确认。
- 匹配：搜索摘要称社区有 MSI Afterburner 的 +3999 RAM 偏移/工具配置讨论，属于“RTX 5090 +3999 数字近似”。
- 差异：没有 18000/18001 的 MODS 设置、通过/失败对照、PMU halt 日志或 +4000 失败报告。不能当作目标问题复现。
- 原文核验：直接检查 page 99/79 的搜索结果时，页面摘要内容与此前命中的 +3999 关键词不完全一致（分页内容可能变动或摘要抓取不准）；未能在原帖中定位/核实包含 +3999 的具体发言。**谨慎起见不把该条作为已核实原始实例**，只记录为待复查的检索线索。

## 查询未命中项

- 精确搜索 `"MODS" "18001" dramclk RTX 5090`、`"dramclk" "18000" MODS`：未发现公开第三方的该频率临界测试或原始 MODS 日志。
- 精确搜索 `"CHANGE_SEQ_PMU"`、`"PMU-RISCV"` 与 RTX 5090/MODS 组合：未找到公开的精确字符串案例。PMU halt 的其他 GPU 论坛帖不能替代该证据。
- 中英文搜索 `MODS 539` 与 RTX 5090/显存：未找到 5090 在 MODS 539 下因 +4000 OC 失败的可靠原帖。搜索结果混杂其他 MODS 版本和代码语境，不能推断为本故障。
- 普通显存超频讨论（例如 +2000/+3000、软件限制或跑分）不等于 MODS 测试通过/失败；PMU halt 单独出现也不等于由显存 OC 引起。

## 方法与限制

结论仅限公开网页搜索可见内容。部分论坛/Reddit 页面动态加载、已删除或搜索摘要不完整；本次未取得可供校验的 MODS 原始日志附件。日期只在搜索结果/页面摘要明确显示时列出，未显示则注明未确认。**目前公开证据没有精确独立复现；这不证明现象不存在。**
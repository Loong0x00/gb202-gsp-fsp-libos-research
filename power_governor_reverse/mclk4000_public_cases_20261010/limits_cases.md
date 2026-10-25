# RTX 50 系列 GDDR7 超频边界：公开案例核验

> 后续补证：Parent已读取OCN第2117/2118页原文与Reddit原评论，找到+3999/+4000附近的真实讨论及驱动崩溃报告，见同目录`REPORT.md`。本文件是子搜索阶段记录，以下未取得原文的项目仍只是线索，“本轮未找到原帖”不代表Parent后续也没找到。

检索日期：2026-10-10（任务指定日期）。范围：只整理公开搜索结果中能定位到的用户帖/issue；没有运行本机或 GPU 工具。最多列 6 个较相关实例。

## 摘要 / 判读

- 搜到用户声称 RTX 5090 可设 **+4000 MHz** 的案例，也搜到论坛讨论 BIOS/软件 slider 能设到 +4000；但本轮未能抓取对应原帖正文，不能据此认定读回实际时钟、负载稳定或对应 36 Gbps。
- 本轮**未找到可核验的用户原帖**直接比较 `+3999/+4000`、`+4000/+4001`、`2250/2251 MHz` 或 `18000/18001 MHz`，也未找到可证实因这些相邻值造成 software reject、setting hang/timeout 或负载不稳的原始记录。不能从“工具 slider 接受 36 Gbps”推导 PMU/MCLK `18001` 可用。
- 有公开帖谈到较高显存超频的游戏崩溃/性能下降，亦有 mVolt 与驱动兼容故障报告；这些属于不同故障类别，不能当作 4000/4001 边界证据。
- 此轮搜索结果给出的 Reddit/HWLuxx 日期不完整或不可见；下列明确注明“日期未能从搜索结果核验”，不猜日期。原文抓取情况也逐项标注。

## 相关实例（按证据贴近程度）

### 1. Reddit：RTX 5090 用户报 +4000 memory
- URL: https://www.reddit.com/r/overclocking/comments/1pp0cou/whats_your_5090_ocuv_results/
- 日期：搜索结果未显示，未能核验。
- 公开结果可见事实：帖子标题为 “What’s YOUR 5090 OC/UV results?”；搜索结果摘要称有用户报告 RTX 5090 Astral LC 显存 **+4000 MHz**，同时报告 core +280。回复中有人质疑该 memory offset 是否准确。未见摘要证明稳定时长、实际时钟/有效带宽或超过 +4000 后的表现。
- 故障分类：**不能分类为稳定通过或失败**；只是设置/结果自述，数值可信度有讨论。
- 原文是否抓取：否；仅有搜索结果摘要，未读取 Reddit 原帖/评论正文。

### 2. Hardwareluxx：5090 OC 线程中的 +4000 设置与实际时钟区别
- URL（页 130）: https://www.hardwareluxx.de/community/threads/offizieller-nvidia-rtx-5090-overclocking-und-modding-thread.1363289/page-130
- 另一个被搜索结果指向的页面（页 20）: https://www.hardwareluxx.de/community/threads/offizieller-nvidia-rtx-5090-overclocking-und-modding-thread.1363289/page-20
- 日期：搜索结果未显示，未能核验。
- 公开结果可见事实：摘要称帖子讨论特定 BIOS 可设置 **+4000 memory offset**，但设置值不保证 GDDR7 实际以相应时钟运行；建议记录实际时钟，并称 BIOS 可能限制实际值。另页摘要提到 Astral 1000W BIOS 的 +4000、特殊 XOC BIOS 的 +5000。后者是特定 BIOS/论坛讨论，不是通用上限或稳定证明。
- 故障分类：**设置/BIOS 可接受与实际应用值可能不一致**；不是明确的 software reject、hang 或负载崩溃案例。
- 原文是否抓取：否；只核验到搜索结果摘要，未抓取论坛正文及上下文。

### 3. Reddit：+3000 讨论，稳定、纠错/性能收益意见不一
- URL: https://www.reddit.com/r/overclocking/comments/1nb906h/why_are_people_ocing_the_5090_with_3000_men_when/
- 日期：搜索结果未显示，未能核验。
- 公开结果可见事实：标题讨论 RTX 5090 `+3000` memory 与错误纠正/性能。搜索摘要呈现用户意见分歧：有人自述 +3000 稳定，也有人质疑稳定性或实际性能；另一相关讨论表示高 offset 下收益可能平台化。它不证明 36 Gbps，也没有相邻边界 A/B 测试。
- 故障分类：**负载稳定性/性能争议**，非设置拒绝或 hang。
- 原文是否抓取：否；搜索结果摘要，不是对原帖评论的直接抓取。

### 4. Reddit：高显存 offset 通过基准但个别游戏崩溃
- URL（搜索结果给出的相关帖子）: https://www.reddit.com/r/overclocking/comments/1k7i6m4/drop_down_your_rtx_5080_overclocks/
- 日期：搜索结果未显示，未能核验。
- 公开结果可见事实：摘要称相关评论提及 5090 在 `+3000` memory 可通过 3DMark，但在特定游戏崩溃。原结果页面标题是 RTX 5080 超频分享，因此这条二手定位需要谨慎；未能确认评论作者/显卡上下文。
- 故障分类：若摘要转述准确，属于**负载不稳（游戏崩溃），基准通过不代表稳定**；不是 driver/software reject。
- 原文是否抓取：否；只见搜索摘要，原帖/评论均未抓取。证据强度低于直接可读原帖。

### 5. Reddit：mVolt 与 NVIDIA 616.56 的 Power Limit 操作崩溃报告（非 MCLK 边界）
- URL: https://www.reddit.com/r/overclocking/comments/1vzw3gb/title_nvidia_61656_causes_mvolt_to_crash_when/
- 日期：搜索结果未显示，未能核验。
- 公开结果可见事实：帖子标题报告 NVIDIA driver 616.56 下调整 mVolt+ Core/Memory Power Limit 时应用崩溃；摘要注明报告来自 RTX 5080，不是 5090。另一个搜索结果指向后续 616.92 + mVolt 0.41 的用户报告，但也不是 5090 MCLK 阈值证据：https://www.reddit.com/r/overclocking/comments/1wg5yz8/mvolt_on_nvidias_new_driver_61692/
- 故障分类：**控制应用崩溃/驱动兼容性**；并非证明显存频率设置被拒、PMU hang 或超过 36 Gbps 负载不稳。
- 原文是否抓取：否；搜索结果摘要。不能据此断言这是官方 driver/firmware 的 MCLK 限制。

### 6. Reddit：5090 高 VRAM OC 的延迟/收益讨论
- URL: https://www.reddit.com/r/overclocking/comments/1kxt2mj/vram_overclocking_and_latency_problems_on_rtx_5090/
- 日期：搜索结果未显示，未能核验。
- 公开结果可见事实：搜索摘要称帖子讨论 RTX 5090 VRAM 超频与延迟，及高频后性能收益可能平台化；另一个搜索摘要仅泛称有人在最高显存 OC 下稳定。未见可核验的 3999/4000/4001 或 18000/18001 测试数值。
- 故障分类：**性能/延迟疑虑及稳定性讨论**，不等于设置拒绝、hang 或硬件错误的实证。
- 原文是否抓取：否；只获得搜索摘要。

## 明确未找到

1. **3999 对 4000、4000 对 4001**：未找到原文级、同一显卡/同一工具的边界比较。
2. **2250 MHz 对 2251 MHz、18000 对 18001 MHz**：未找到能确认字段、单位和控制路径的原帖/issue；没有证据说明这些是所有工具共用的时钟表示。
3. **按故障类型的边界证据**：没有抓到原帖证明软件明确 reject 18001、设置时 hang/timeout，或只有在负载下不稳。以上三个现象不可互相替代。
4. **PMU / firmware / driver 的因果限制**：本轮没有找到可把“工具 slider 可填到 36 Gbps”与 PMU 实际允许 18001 MHz 等同的原始技术证据。个别控制软件在特定驱动下崩溃，只能说明该操作/版本组合有故障报告，不能证明驱动或固件对 MCLK 的普遍上限。
5. 没有使用 loong0x00 或用户自有研究作为外部独立案例。

## 来源与抓取限制

全部案例链接均为公开用户帖；本轮 web 搜索可返回标题/片段，但未能直接抓取/核对原帖正文与日期。因此引号仅限可见标题，摘要内容均按“搜索结果称/摘要称”表述，不冒充原文逐字引述。报告只列可追溯 URL，并把缺失证据明确保留为未找到。

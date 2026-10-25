# 网上类似案例：5090 +3999 / +4000附近

检索/核验日期：2026-10-10。只做公开网页研究，没有运行超频工具、登录新账号、订阅付费内容或访问GPU。

## 结论

**有非常接近的Windows/mVolt案例，明确讨论+3999、+4000、18001MHz与driver crash；不是只有本机MODS出现这一带的问题。** 但仍未找到第三方MODS570.215、18000通过/18001失败，并附同一PMU completion marker25728或CHANGE_SEQ_PMU转储的精确复现。

这些外部案例能支持“5090在这个名义频率/偏移区域有跨工具差异/失效报告”，不能证明相同根因，也不能直接归罪FSP或排除CPU RM/GSP RM。

## A. 最接近：OCN 5090用户俱乐部，2026-09-24

原页：<https://www.overclock.net/threads/official-nvidia-rtx-5090-owners-club.1814246/page-2117>

直接浏览器导航失败，直接HTTP返回202 challenge；随后通过公开Jina Reader成功取得该原页文本，保存`primary/ocn2117_jina.txt`。下面post ID与日期由原页提取文本核对，不采用Google AI概览或SERP摘要。

### A1. 高于+4000，软件应用后驱动崩溃

- 原帖：<https://www.overclock.net/threads/official-nvidia-rtx-5090-owners-club.1814246/page-2117#post-29626867>
- 帖号#42,327；日期2026-09-24。
- 用户`nomadka670670`（姓名由后续回复引用该post确认）。
- 短摘：
  > is there a reason i cant get to run vram over 4000?
  > mvolt apply it. but the driver crash
- 贴近点：5090主题、显存偏移、高频设置应用后driver crash。
- 边界：原文写的是**over4000**，不能改写成“恰好4000已经失败”，没有MODS或PMU dump。

### A2. 回复直接建议+3999

- 原帖：<https://www.overclock.net/threads/official-nvidia-rtx-5090-owners-club.1814246/page-2117#post-29626871>
- 帖号#42,329；日期2026-09-24。
- 引用A1后回复短摘：
  > try +3999
- 后续post29626879有用户再确认“3999”；不是包含配置/日志的完整A/B实验。

### A3. 明确提到18001与部分卡只能3999

- 原帖：<https://www.overclock.net/threads/official-nvidia-rtx-5090-owners-club.1814246/page-2117#post-29626873>
- 帖号#42,330；日期2026-09-24；用户`luciferXdevil`（由后续引用确认）。
- 短摘：
  > Currently Nvidia only allows till +4000 where you can get a max of 18001 MHz but some can only do +3999 MHz.
- 这是目前最接近用户数值的第三方讨论。
- **“Nvidia only allows”是论坛用户的解释，不是NVIDIA官方限制说明，也不是已恢复的固件比较代码。** 该帖未给driver版本、VBIOS、准确目标/实测字段或失败PC。

### A4. 5090 FE能应用3999，但回退/再次控制有状态问题

- 原帖：<https://www.overclock.net/threads/official-nvidia-rtx-5090-owners-club.1814246/page-2118#post-29627065>
- 日期2026-09-24；用户`el_marzocco`由后续引用确认。
- 内容：mVolt+ Extreme让5090FE使用+3999，但尝试撤销会报错。post29627073有另一用户确认，称需重启才能撤销/继续控制，driver crash后工具状态也异常。
- 核验：`primary/ocn2118_jina.txt`；第2119页再次引用原帖，存`ocn2119_jina.txt`。
- 不是3999本身会停机的证明，属于控制状态/回退故障。

### A5. 也有+4000实际运行memtest的反例

- 原帖：<https://www.overclock.net/threads/official-nvidia-rtx-5090-owners-club.1814246/page-2045#post-29614679>
- 2026-08-28，`kryptonfly`（后续引用确认）称测试了+4000 memtest，随后因功耗遥测很高而主动停止。正文读取存`primary/ocn2045_jina.txt`。
- 同用户post29614813说HYDRA的+4000可用但需保持工具运行。
- 不是完整PASS或长期稳定证明，也未独立核验截图实际clock字段；但说明不能把+4000对所有5090的设置路径一概判为失败。

## B. 媒体汇总：5090与5070Ti表现不同

- 原文：<https://videocardz.com/newz/geforce-rtx-5070-ti-gddr7-memory-has-been-overclocked-from-28-to-39-gbps>
- 文章发布时间经网页meta/JSON-LD核验：2026-09-30T07:30:54+00:00。
- 浏览器已读取完整相关正文，不只看标题。
- 专节“RTX 5090 appears to hit a lower limit”转述：5090用户先做到3999，再绕过界面应用4000，但超过4000仍driver reset；与此同时部分5070Ti可以更高，原因未明。
- 这是**二手报道**，不能与它引用的论坛案例当成两份独立复现。它也把“界面能否填4000”与“超过4000重置”分开，不能把两者都说成固件主动拦截。
- 5070Ti示例+5500≈39Gbps、+6000立即driver重启，见下列可读原评论。

## C. Reddit原评论：明确设置/版本差异案例

主帖：<https://www.reddit.com/r/overclocking/comments/1wsnllh/finally_unlocked_gddr7_memory_overclocking_with/>

浏览器成功读取原评论、作者、comment permalink及`time datetime`。主帖本体显示已被Reddit过滤删除，所以不把已删除主帖的全部自述视为本轮已核验；仅使用仍可读的评论。

### C1. +6000立即崩溃，高于5500出现花屏

- <https://www.reddit.com/r/overclocking/comments/1wsnllh/comment/pcncubg/>
- 用户`evilTOend`；时间2026-09-28T20:05:59.033Z；ASUS5070Ti Prime OC。
- 自述+5500有性能收益，更高出现artifacts，+6000立即crash。
- 这是原帖级的“高偏移应用/运行失败”证据，但卡型与阈值不同，无PMU日志。

### C2. 原先5000失败，换驱动后5000可用

- <https://www.reddit.com/r/overclocking/comments/1wsnllh/comment/pcok3ok/>
- 用户`Believesteve`；发表于2026-09-28T23:20:28.239Z，编辑时间2026-10-05T21:04:02.021Z。
- ASUS5070Ti Prime Non-OC；先报告4500可用、5000花屏/崩溃；后编辑称换driver后5000没有问题且性能继续增加。
- **只是用户观察，driver版本未给出、未作受控复现**，但支持不能把一次高频失败全部解释成显存芯片的固定物理极限。

### C3. HYDRA的4000设置可能回落，另工具重设

- <https://www.reddit.com/r/overclocking/comments/1wsnllh/comment/pcnx96u/>
- 用户`rzultamorda420`；时间2026-09-28T21:30:30.742Z。
- 自述设置2250MHz(+4000)后会回落1875；重启HYDRA或用普通mVolt重新设置。
- 此评论未明确卡型；不能归为独立5090精确案例，只说明工具/状态管理也能引入差异。

## D. 已核验的PMU halt类案例，相关性较低

1. 同为GB202的RTX PRO6000：<https://forums.developer.nvidia.com/t/375503>。
   - 用户tejeswar01，2026-07-03发布；正文内日志日期为Mar27。
   - driver595.58.03，LLM负载，Xid62→PMUhalt→Xid154；没有显存OC阈值证据。
   - 原文通过Discourse JSON读取，已保存`primary/nvidia375503_posts.json`。
2. RTX5070 GB205闲置PMUhalt：<https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1307>。
   - 2026-08-19，driver610.57.04；PMUhalt先于GSPwatchdog约5秒。
   - 原文GitHubAPI已读取，存`primary/nvidia1307.json`；不是MODS/显存边界。
3. RTX2080Ti，GSP开关下相同PMUhalt payload：<https://forums.developer.nvidia.com/t/384008>。
   - 2026-09-22原帖；NVIDIA人员9/23回复识别payload并拟复现。
   - 原文JSON已读取；架构不同、非OC临界。不能拿它证明本机FSP/PMU同根因。

这些仅证明“PMUhalt不必由显存误码/测试算法触发”，不是3999/4000问题的额外复现。

## 对当前分析的影响

- 之前不能把36Gbps宣传值当作18001已验证；现在确有论坛用户**明确说18001/+4000有人能用、有人只到3999**，这是一条新线索，仍缺精确实测与日志。
- 不能继续把“18001在所有5090必然不可用”当假设前提；也不能反向推定本机570.215必然应该通过。
- 更合理的是核对具体card/VBIOS、driver/PMU构建、工具如何生成名义target/应用控制，以及设置失败时response/notification现场。
- **没有找到同版MODS与同一断言PC/marker的独立公开复现。** 原帖有相似边界，不等于确定了FSP或CPU RM首因。

## 检索及核验限制

子搜索输出`exact_cases.md`/`limits_cases.md`保留早期只取得摘要的结果，已加后续补证提示；最终以本报告原文核验项目为准。Google AI概览曾把18xxx误写成18Gbps、混淆游戏mod与NVIDIAMODS，均未采信。排除loong0x00/本用户自己的已发布研究，避免循环佐证。

OCN日期按每个post链接，不采用搜索统一显示的Jan7,2025或置顶首帖更新日期。Jina仅作为原页面文本提取途径，广告/affiliate链接不作技术证据。

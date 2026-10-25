# 浏览器核验的公开来源

2026-10-09，只读网页研究。搜索提供方两次报错后使用真实 Chrome 导航/DOM 读取；没有登录新账号、发帖、付费或运行/下载超频工具。VideoCardz 与 Wccftech 的直接 urllib 请求返回 HTTP 403；VideoCardz 已通过浏览器正文核验。以下是摘录/字段笔记，不是完整网页存档。

## HYDRA 原作者：36 Gbps 功能

- 作者公开帖：<https://www.patreon.com/1usmus/posts/hydra-unlocks-166927902>
- 帖名：HYDRA Unlocks RTX 5000: VRAM Overclocking & Power Limit Control。
- 公开正文列出原有 5090 28–34 Gbps、5080 30–36 Gbps；新增初始上限 36 Gbps，声称所有厂商 RTX 5000 兼容、RTX PRO 6000 实验支持。
- 作者原文短摘：
  > Up to 36 Gbps for GDDR7
  > No VBIOS flashing. No security hacking. No magic drivers. Just HYDRA.
- 演示卡是 Asus ROG Astral LC GeForce RTX 5090 OC，公开页面附短视频。作者将其描述为 36 Gbps、2.3 TB/s，并称这是人为设置的初版上限；正文未公开具体寄存器/控制 API/固件改动方法。
- 公告计划先向 Early Access 会员提供。相关帖子卡片显示 HYDRA 2.3B PRO 构建已经发布，但付费下载正文未访问，未获得工具二进制。
- 作者 X 宣布帖也已打开并核验：<https://x.com/1usmus/status/2089406972592349518>。

## 两个二级正文交叉核验

1. <https://videocardz.com/newz/hydra-adds-unlocked-vram-and-power-limit-controls-for-geforce-rtx-50-series>
   - 明确命名 HYDRA 2.3B Pro。
   - 报道普通 5090 等从 34 到 36 Gbps，5080原已可到36；Astral LC演示。
   - 文中作者明确自己未实测，依赖开发者的视频。不能把该文当作独立硬件验证。
2. <https://www.tomshardware.com/pc-components/gpus/famed-overclocker-1usmus-updates-hydra-overclocking-tool-with-up-to-3000-mhz-memory-offset-new-update-gives-vram-and-power-limit-controls-to-rtx-50-series-gpus>
   - 正文报道36 Gbps及同一Astral LC演示。
   - 标题/首段仍写“+3000 MHz”，与5090从28到36 Gbps按常用MCLK口径需+4000不一致。不能用这一标题推导协议字段或偏移基准，应以作者绝对36 Gbps声明及实机target为准。

## Lightning Z 外置晶振：原始 HWBOT 记录

- <https://esports.hwbot.org/benchmarks/3dmark_-_port_royal/submissions/6065913>
- 用户：Cmaker；提交时间2026-08-30；Port Royal得分53558。
- 卡：GeForce RTX 5090，Lightning系列；液氮冷却。
- 提交频率：核心3650 MHz、显存2333 MHz；XBar3436 MHz。
- 用户原文关键短摘：
  > RTX 5090 Lightning Z (28.6363MHz Crystal)
- 同一评论链接视频：<https://youtu.be/xzmFZkklQFQ>。本轮没有观看视频，不把未观看画面作为证据。
- HWBOT页面验证链接指向下面3DMark结果。

## 对应 3DMark 名义读数与校验警告

- <https://www.3dmark.com/pr/4007885>
- 得分53558；名称RTX 5090 LIGHTNING Z；描述106.06%；显卡厂商MSI。
- 显示核心3442 MHz（平均3395）；显存总线2200 MHz（默认1750，平均2200）；驱动32.0.15.9576；平均GPU温度-40°C。
- 重要：页面显示INVALID；警告完整文字为：
  > This result is invalid as some system specifications appear to be modified in a way we cannot verify. This could be the result of physical hardware modifications that bypass built-in driver restrictions or issues with the GPU driver installation.
- 因此这是有成绩输出的硬件改装/极限跑分记录，不是3DMark认可的有效结果，更不是日用稳定性证据。

## 数值交叉检查（分析，不是额外测量）

若按常规27 MHz参考频率算，28.6363/27 = 1.0606037：

- 2200 × 1.0606037 = 2333.328 MHz，与HWBOT填报2333吻合。
- 3442 × 1.0606037 = 3650.598 MHz，与HWBOT填报3650吻合。
- 2200 MHz常用GDDR7工具口径对应35.2 Gbps及MODS MCLK 17600 MHz；缩放后约37.333 Gbps。

106.06%的结果描述、晶振数值、名义2200/3442与填报2333/3650形成很强的一致性。但本轮没有独立示波器/时钟测量，不把换算当作独立实测。

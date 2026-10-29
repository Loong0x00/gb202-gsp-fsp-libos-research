# DLSS 5 NR “变黑/脸黑”来源与可见性核查

日期：2026-09-15。范围：已保存的原始 DLL 同输入结果、本地公开来源归档、普通公开网页/视频。这里的“DLSS 5 NR”与旧的 DLSS Ray Reconstruction (RR) 分开。

## 结论

1. **不是二游独有，也不是统一全图降曝光。** 原始 `nvngx_dlssnr.dll` 的同输入测试在真人脸上也会选择性压低肤色；但二游的大块浅色、平涂/SDF 脸部更容易让局部阴影变化被识别成“黑脸”。
2. “大多数游戏不可见”只说对了一半：**全帧平均值可能几乎不变，但人脸 ROI 可以明显变暗。** HSR 离线同输入例子全帧平均亮度仅 -0.232%，Castorice 脸部 ROI 却为输入的 72.5%，96.8% 的 ROI 像素变暗。
3. 公开视频中的“变黑”来源混在一起：单次 NR 的局部负残差、多层重复放大、Style/Tone/Structure 选择、无人物 mask 的通用注入、HDR/曝光/后处理，以及非配对镜头。不能全部归成同一个 bug。
4. 纯白测试不具有排除力。首帧 final post 在忽略舍入时近似 `clamp01(A + learnedRGB/4)`；当 `A=1` 时正残差被上限裁掉，只能看到负残差。实测纯白 98.27% RGB 分量恰为 1，平均下降仅 8.05e-6。

## 最强的同输入数值证据：原始 DLL，不是公开视频观感

来源：`/home/user/rt_5090_project/dlss5_model_dump/native-rerun-20260831/RESULT.md`、`skin-summary.csv`、`skin-comparison.png`。原始 DLL SHA-256 `e16bcf15...e1fc8e`；公共 CUDA API、reset 首帧、零运动、depth 0.5、无 control mask、intensity/tone/structure=1、skin=-1、style=0。51 个重跑输出与旧输出逐浮点完全一致。

| ROI | 输出/输入平均亮度 | ROI 变暗像素 |
|---|---:|---:|
| WuWa 浅色腿部，384 | 0.731 | 99.4% |
| HSR Castorice 脸，原生 6K 帧 | 0.725 | 96.8% |
| HI3 角色脸，2560 帧 | 0.646 | 98.2% |
| Obama 真人脸，256 | 0.865 | 72.6% |
| Trump 真人脸，256 | 0.868 | 83.5% |
| Xi 真人脸，256 | 0.915 | 77.2% |
| MetaHuman Creator，256 | 1.049 | 23.5% |

所以这是**选择性肤色/局部色调响应**，不是“动漫检测后统一变黑”。同一个 MetaHuman Creator 在 1024 尺寸时亮度比为 0.824，而 256 时为 1.049，说明对象尺度/上下文也会改变方向。

HSR 全帧来源：`dlss5_model_dump/hsr-20260831-default-6k/metrics.csv`。全帧 `0.281519 -> 0.280866`，比值 `0.997680`，28.49% 像素变暗；脸部的强变化被面积巨大的背景均值掩盖。

WuWa 五层同输入 fixture 进一步给出相反的全局/局部组合：`reviews/nr-contrast-shortcut-20260911/REPORT.md`。frame3 B→P5 全图平均亮度 **+63.2%**，但仍有 **23.8%** 像素变暗，`Y<0.01` 比例从约 0.002% 增至 1.52%。因此“整体更亮”和“人物/阴影更黑”可以同时成立。

## 二游/NTE 报告的实际出处

### WuWa

- FanticSama：[YouTube yLfgFIbz-4s](https://www.youtube.com/watch?v=yLfgFIbz-4s)，B站搬运 [BV1G34m6sETX](https://www.bilibili.com/video/BV1G34m6sETX/)。本地完整审计：`reviews/public-nr-demo-comparison/README.md`。约 01:20 的“5”侧脸/颈与环境明显更暗、阴影更重，但左右姿势、朝向和取景不同；只能证明公开视频呈现出 relighting，不能做像素归因。
- [BV1NhtW67EUq](https://www.bilibili.com/video/BV1NhtW67EUq/) 的 UP 玄方研究院后来报告 NR-before-SR，并附“右图开启”的两张图；人物动作不同，参数/曝光不全。来源：`reviews/nr-comments-wuwa/README.md`。
- 本地原始 DLL 的 WuWa 浅色腿部 ROI（上表）是比公开视频更强的选择性变暗证据。

### ZZZ

- [BV1hEbn6QEtc](https://www.bilibili.com/video/BV1hEbn6QEtc/) 的 UP 搜索简介原文是“**纯实机 直播效果 叠三层 脸不黑**”。它证明作者把“脸黑”当成需要声明/避免的现象，但没有给出同帧 raw 对照和完整三层参数，不能升级为普遍 bug。来源：`reviews/nr-comments-zzz/README.md`、`targets.json`。
- [BV1ot4D6gEC2](https://www.bilibili.com/video/BV1ot4D6gEC2/) 的 authored “MATCHED FRAME”植物场景中 ON 侧接触阴影更深；公开视频只有 854×240 转码。评论同时有人认为更立体，也有人认为破坏三渲二风格。
- [BV1sk4y6iEH5](https://www.bilibili.com/video/BV1sk4y6iEH5/) 的观众只说颜色不如 RenoDX HDR，UP 回复“不知道为什么”；这不是严格的“变黑”报告。

### HSR

- 本地最强证据是上述原始 DLL 的同输入 Castorice ROI：亮度比 0.725；同时全帧比值 0.99768，准确展示了“全图看不出、脸部很明显”。
- 公共视频 [YouTube hZDSeyUAGDg](https://www.youtube.com/watch?v=hZDSeyUAGDg)，Gowther1414，2026-09-06，标题 `DLSS 5 in Honkai: Star Rail is CRAZY`，简介称相同动画 side-by-side。保存的 608×1080 短视频可见 OFF/Natural、Default/Cinematic 的角色和地面明暗差异；尤其 Default 与 Cinematic 的明暗差异很大，说明 Style 是强变量。公开视频压缩且画面并非像素注册，不能代替 raw 数值。
- 本轮没有找到标题/正文明确写“HSR 变黑”的独立中文原帖。不能把效果展示或“剔除人脸”教程自动改写成黑脸报告。

### NTE / 异环

- 本地 B站搜索原始状态中有直接标题：[BV1y94D6pEz4](https://www.bilibili.com/video/BV1y94D6pEz4/)，《**异环用上不适配的DLSS5，角色发黑？**》，UP 发呆的阳咩咩，2026-08-30。来源：`reviews/nr-comments-zzz/search/q3.cards.json`。封面已保存为 `images/BV1y94D6pEz4-cover.jpg`。这是最直接的中文“角色发黑”来源，但仍是单视频标题；当前 Bili API 请求被 412/非 JSON 拒绝，没有取得新的正文、评论或同帧原图。
- 另一份 NTE forced-injection 视频来自 [X @iaklsydney](https://x.com/iaklsydney/status/2093087575296643365)，本地归档在 `dlss5_model_dump/reboot-save-20260831/external-wuwa-nte/`；只有 ON 演示，无 OFF 同帧，不能用夜景本身证明变暗。
- NTE 官方 RR 与社区 DLSS 5 注入必须分开。官方 RR 实测讨论多为反射、闪烁、鬼影或场景级 RT 错误；不等于这里的生成式 NR “黑脸”。

## 非二游反例

- 同一原始 DLL 已在 Obama/Trump/Xi 真人脸 ROI 上测出 8.5%–13.5% 平均亮度下降，故“只有二游”已被本地同输入数据直接否定。
- Reddit 帖 [“Why does DLSS 5 add exaggerated makeup and dark circles to characters?”](https://www.reddit.com/r/pcmasterrace/comments/1w19tf4/why_does_dlss_5_adds_exaggerated_make_up_and_dark/) 直接讨论眼周暗影、烟熏妆、面部轮廓加深；评论对这些阴影是否更合理有分歧。
- Digital Foundry 的 [DLSS 5 hands-on](https://www.youtube.com/watch?v=4ZlwTtgbgVA) 涵盖 Resident Evil Requiem、Starfield、Oblivion Remastered、Assassin’s Creed Shadows：有的场景增加 AO/接触阴影，有的反而填平或删除帽檐阴影。最准确的概括是“scene-dependent relighting + tone/material change”，不是单向变暗。
- 本地 Reddit megathread 公开 RSS 归档列出 Control、Wuchang、Death Stranding 2、Cyberpunk 2077、FF7 Rebirth、AC、TLOU2、Starfield、Stalker 2、Forza、KCD2、Silent Hill 2、Elden Ring 等大量非二游注入案例。评论中既有“更真实/更有深度”，也有“破坏光照、局部黑白/反相”。来源：`reviews/public-nr-demo-comparison/sources/reddit_rss.extracted.json`。
- 旧 DLSS Ray Reconstruction 的非二游局部暗部问题也存在（例如 Indiana Jones 水面变暗/暗部白噪点、Cyberpunk 黑色伪影），但 RR 是另一套技术，不能拿来证明当前 NR 模型的统一偏置。

## 为什么二游特别显眼

1. **三渲二脸故意压平明暗。** 大面积均匀肤色、弱鼻影/眼窝影、SDF 阴影是风格的一部分；NR 新增 AO、接触阴影、SSS/色调梯度时，相对变化很大。
2. **同一数值变化在 PBR 场景会被命名为“更真实”。** 写实游戏本来已有肤色起伏、粗糙度和复杂光照；类似残差容易被理解为材质深度，而不是“脸黑”。这不是数值不可见，而是感知标签不同。
3. **对象尺度很关键。** 原始 DLL 的 MetaHuman 与 WuWa 缩放实验表明，输出方向/幅度随脸在网络输入中的像素尺度显著改变。
4. **社区注入缺少开发者 mask。** WuWa/ZZZ/HSR 的演示多为 ReShade/XXMI/RenoDX/通用 post 注入，不是开发者按角色、材质和场景调好的官方集成；往往没有可靠人物 control mask。
5. **多层叠加会累积。** ZZZ“叠三层”、HSR 社区四层、WuWa 多层路线把上一层输出再送进同一模型，局部负残差和风格化会被重复强化。
6. **HDR/曝光可混淆。** 燕云公开配方明确还有曝光补偿 -8、暗角 9、对比度 65 和 FakeHDR；这类视频不能把全部暗化归给 NR。非配对镜头、自动曝光和视频 tone mapping也会造成假差异。

## 与官方设计的关系

NVIDIA 官方 [DLSS 5 3D-Guided Neural Rendering](https://www.nvidia.com/en-us/geforce/news/dlss-5-3d-guided-neural-rendering/) 明确称：

- Tone Intensity 控制低频照明和颜色响应；Tone=0 用于保留 rendered frame 的颜色；
- Structure Intensity 控制 AO、contact shadows、reflections、subsurface scattering 等高频结构；
- 有 semantic automatic mask 与开发者 per-pixel/engine mask；
- 开发者可按室内/室外、玩法/过场选择模型和参数。

这正说明 generic global injection 的结果不能代表经过人物 mask 和逐场景调参的正式游戏集成。

## 最终判断

- **确有模型本体的局部肤色/阴影变暗，不只是录像错觉。** 原始 DLL 同输入数据已经证明。
- **它不是二游专属，也不是全图固定乘一个变暗系数。** 真人脸、不同尺度、不同 Style 都可出现不同方向。
- **二游更容易“被看见/被叫作黑脸”。** 大面积平涂脸、无 mask、多层注入和截图中心构图共同放大了感知。
- 对“大多数游戏不可见”的准确表述应是：**全帧均值和普通跑图中可能不醒目；脸部、浅色皮肤、接触阴影和特定尺度上仍可能很强。在写实游戏中同一变化常被接受为 relighting，而非被报告为黑脸。**

## 访问/误判记录

- 对七个 Bili view API 的新请求均返回不可解析页面（当前反自动化响应）；原始 body/meta 已保留，未做登录、签名或挑战绕过。
- 搜索提供者曾把 `dlss5studio frame-1d485667` 描述为 HSR；直接下载 before/after 后确认画面是 Roblox 风格驾驶游戏，页面自身也未标游戏名，因此已拒绝作为 HSR 证据。文件保存在 `images/hsr-dlss5studio-*` 仅作误判记录。

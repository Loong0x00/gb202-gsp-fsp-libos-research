# 鸣潮教程参数核查（2026-09-11，公共资料 / CPU-only）

## 给主代理的结论

**已找到原教程画面中的精确数值，不必用其他游戏参数代替。** 但这是旧版教程显示的参数，**不是玄方研究院本人逐项公开的 PRE-SR 配置**，也不是对当前 Linux PRE3 管线的兼容认证。当前游戏运行中，本任务没有修改/读取运行配置、调用 GPU、Wine 或游戏，没有下载插件/DLL/网盘文件。

- 玄方本人明确选 **Cinematic**；9 月 2 日明确改为 **Quality（质量）+ NR→SR**。用户 Quality 必须保持，不应倒退照搬简介旧的 Balanced，或原教程旧的 DLAA 要求。
- 原教程 `BV1kU4y6aEcE` **01:20、01:25、01:30** 清楚显示：`NR Preset=Default`, `NR Style=Cinematic`, `NR Intensity=2.00`, `Local Tone Strength=2.00`, `Local Structure Strength=2.00`, `Skin Structure Strength=2.00`, `Scene Paper-white Scale=1.000`, `HDR Transfer Strength=1.00`, `Color Strength=1.00`, `Depth Convention=Use game NGX flag`, `Motion Scale X/Y Multiplier=1.000/1.000`。
- **可以作为有来源的标量候选**：上述四个 `2.00` 和 transfer/color/paper-white 的 `1`。应用前由主代理确认本地字段确为同一语义/范围；不能以“教程验证”冒充“已证实 PRE3 完全等效”。本次没有验证本地 enum 数字映射。
- **不能直接套用的内容**：旧的 `Enable Upscaling` 开关、DLAA、最高 RT、原生 FG、Lossless Scaling、自动 mask/UI 布尔、depth/MV 覆盖、叠层数。保留当前 Quality 与已工作的 physical PRE3；不为追随 Windows 教程改变管线。
- 小马蜂 P1 的前置版本实际显示另一套值：`NR 强度=1.00`, `NR 风格=自然`, `皮肤结构=-0.00`, `局部照明=1.00`, `局部结构=1.00`, `NR 细节混合强度=1.00`, `NR 颜色混合强度=1.00`。不能将这套值伪称玄方 Cinematic 参数，也不能把“自动人脸/皮肤遮罩”当作原插件 `Automatic Mask` 的等价开关。

## 身份、时间与引用链

完整简介见 `DESCRIPTIONS.md`；全文公共评论和楼内回复见 `COMMENTS.md` / `comments.json`。时间统一 UTC+8，身份由视频搜索 SSR 的 mid 与评论 mid/API upper.mid 对照，不凭昵称猜测。

1. **玄方研究院**，mid `3707016587512597`，`BV1NhtW67EUq`：本次只复用既有公共抓取，文件保存在 `anchor/`，不是新抓取的第四个视频。
   - 简介明示“几个模式下Cinematic确实最适合鸣潮”；旧设置“渲染&光追全部最高/超分：平衡/关闭动态模糊/DLSS帧生成X3”。它列出了两张 GPU，第二张负责 Lossless Scaling 固定 120 帧。
   - **作者置顶 rpid `312682909937`，2026-09-02 13:14:50**：链接 `BV1zutj6EEbo`，说将神经渲染移到超分之前；“目前上述配置和设置已经可以在质量模式下开启两倍帧生成叠加2倍Lossless Scaling完美120帧运行（之前需要平衡+3倍帧生成）”。这是 FG/LS 的两次插帧，**不是 NR 两层**。性能、延迟、鬼影改善均是作者自报，不是本次实测。
2. **木每木每酉卒了**，mid `174415188`，原教程 https://www.bilibili.com/video/BV1kU4y6aEcE/ 。发布时间见 `DESCRIPTIONS.md` / `targets.json`。
   - **作者置顶 rpid `312423879505`，2026-08-30 23:47:22**：“现在V4.55版本已经可以支持开启dlss质量档和全量光追了，更追求画面可以开启光追，追求帧数可以关闭…目前还有一些偶尔闪烁的小问题。”
   - 现在的简介也写 V4.55；**视频画面本身仍演示 V3**，不要把更新后的简介版本错误贴到旧截图数值上。
3. **野生的装机宅**，mid `941799`，https://www.bilibili.com/video/BV1zutj6EEbo/ 。这是 PRE-SR 原理/实现教程，主要演示 2077 和另一游戏，**不能作为鸣潮标量的替代来源**。
   - 作者普通主楼（抓取时非置顶）**rpid `313152496545`，2026-09-06 20:38:53**：0.1 跑通 `NR→SR`；0.2/0.3 稳定 HDR 合成但兼容性待测；0.4 可保持游戏 1440p 渲染、NR 降采样再合成到 DLSS SR 增强输出。这些是版本说明，没有 HDR transfer/paperWhite 的标量。
   - **当前作者置顶 rpid `313476260049`，2026-09-10 04:54:20**：0.4.7 支持 NR 前/后置，RR 自动后置 NR，新增色彩保护；明确“一键安装器内置多帧生成和 SR 选项建议先别碰，可能不兼容”。Vulkan bridge 仅称 RTX50 SDR 受控 600 帧验证；**不是 Linux/Wine 鸣潮兼容证明**。
4. **小马蜂Official**，mid `57184`，https://www.bilibili.com/video/BV19ntz6uEXT/ 。简介 P1 链接上面的装机宅教程，P2 列出 Optiscaler v0.7.1 和装机宅 v0.4.6，两个方案不是一个版本。
   - **作者置顶 rpid `313433758961`，2026-09-09 18:45:08**：“Optiscaler v0.7.1…叠层可以全部走nr前置减开销，2层才等于原版1层的开销”。这是 **NR 多 pass**，不同于玄方的 FG×2 + LS×2。此处比例是作者体验性说法，不是跨设备保证。
   - 作者回复 `313461955201`，2026-09-09 23:29:36，称异环自己装不上 Opti、仍用 ReShade，进一步表明不能泛化安装兼容性。

## A. 原教程可逐项核验的参数（旧 V3，鸣潮实画面）

直接证据：`frames/original-at-80s.png`, `frames/original-at-85s.png`, `frames/original-at-90s.png`；局部放大只做普通像素缩放：`frames/original-at-85s-controls-3x.png`。时间由 ffmpeg `-ss 80/85/90` 定点解码，不是猜测。视频来自公开 playurl 返回的 360P 媒体；运输中断，只保存了文件前 8 MiB，但以上时间点可正常解码；**不声称看完 6:03 原片**。

| 字段（原 UI 拼写） | 画面值 | 限定 |
|---|---:|---|
| NR Preset | Default | 枚举名字；不是 NR Style，也不是 SR Quality |
| NR Style | Cinematic | 与玄方本人简介相符；numeric enum 未查 |
| NR Intensity | 2.00 | 明确显示，不是“2层” |
| Local Tone Strength | 2.00 | 同上 |
| Local Structure Strength | 2.00 | 同上 |
| Skin Structure Strength | 2.00 | 同上 |
| Scene Paper-white Scale | 1.000 | **倍率，不是 1 nit，更不是 200/203 nits 的证据** |
| HDR Transfer Strength | 1.00 | 控件标题为 `Control-compatible color transfer`；不证明系统/显示器实际开启 HDR |
| Color Strength | 1.00 | 不能与其他版本的 `NR 颜色混合强度` 自动视为等价 |
| Depth Convention | Use game NGX flag | 不能转换成强制 reversed-Z 或指定 depth buffer ID |
| Motion Scale X Multiplier | 1.000 | 乘数；不说明 motion vector 坐标空间、尺寸或正负约定 |
| Motion Scale Y Multiplier | 1.000 | 同上 |

`Automatic Mask` 与 `NR UI Correction` 可见，但 360P 的小复选框没有足够清晰的状态证据，本报告**不批准据此改布尔值**。`Enable DLSS Neural Rendering` 明确勾选。`Enable Upscaling` 在 01:25 还未勾选、01:30/01:35 已勾选；此为旧插件步骤中的状态变化，不得映射成 PRE3 的 `NR before SR` 开关。

视频约 01:12 字幕要求旧版 `DLAA`；01:35–01:42 一带说明 V3 仍有问题并出现崩溃画面。后来的 V4.55 作者置顶明确支持 Quality，因此 **Quality 优先，禁止照搬 DLAA 或 Balanced**。

## B. 小马蜂 P1 前置版本：独立的对照，不混入 A

直接证据 `frames/related720-at-65s.png`（01:05，720P，18 MiB 合法 HTTP Range 前缀）。UI 文件名 `nr-before-sr.zh-CN.addon64`，描述“切换 SR→输出分辨率 NR 与渲染分辨率 NR→SR”。

- `启用(F6)`、`使用渲染分辨率 NR→SR` 有勾选。
- 显示游戏 DLSS：`1280×720 → 2560×1440`，NR 分辨率 `1280×720`。**这是该视频的配置/演示，不能令用户从 Quality 改为 Performance。**
- HDR 线性合成状态行显示预曝光 `1.000`、曝光缩放 `1.000`、系数 `1.000`。这些是这个插件的状态行，不能据此指定用户 HDR 输出模式。
- `NR 强度=1.00`; `NR 风格=自然`; `自动人脸 / 皮肤遮罩` 勾选。
- `皮肤结构=-0.00`（UI 说明 `-1 = 跟随局部结构`），`局部照明=1.00`, `局部结构=1.00`, `NR 细节混合强度=1.00`, `NR 颜色混合强度=1.00`。
- `深度模式=跟随游戏 DLSS`；`预热帧数=2`；深度倍率/MV 倍率没有给出另一组能迁移的精确值。
- 片后 06:15–06:35 演示人物界面和颜色混合的调节，字幕说可以把某选项调到零并展示游戏原调色；这是功能演示，不应把任意瞬时值当成作者唯一最终配置。相关定点帧保存为 `frames/related-at-375s.png`、`380s`、`390s`、`395s`。

## C. PRE-SR 顺序、P2 叠层与更新边界

`BV1zutj6EEbo` 的公开完整 360P 视频保存为 `video360-BV1zutj6EEbo-p1.body`。其预览图 `contact-BV1zutj6EEbo.jpg` 和 `shots-BV1zutj6EEbo.body` 直接展示：

- 约 00:22–00:37 旧顺序：1080p 渲染 → DLSS 4.5 超分 4K → DLSS5 AI 增强 → 4K 输出。
- 约 00:42 新顺序：1080p 渲染 → DLSS5 AI 增强 → DLSS 4.5 超分 4K → 4K 输出。
- 约 01:02 / 01:07 / 01:12 对比 Performance / Quality / DLAA，说明不是只能 Performance。那些数字是讲解用的例子，并非鸣潮指定输入分辨率。
- 9/10 的 RR 自动后置更新已不同于最初“总是 NR→SR”的概括；不可把后来的 RR 规则硬套到本机正在运行的 PRE3。

小马蜂 P2 媒体返回 403，未绕过；公开预览 sprite 成功。`p2-pvdata.body` 为公开索引，按大端 uint16 解出 `[0,0,5,…,255]`，与 P1 API 索引结构一致，第一零为头/哨兵；其余为逐 cell 的秒数，见 `p2-sprite-index.json`。**这些是预览采样时间，不是逐帧精确字幕起止。**

- P2 cell 34，约 **02:50**：字幕“Apply before SR是让滤镜跑在超分前减开销”。
- cell 40，约 **03:20**：字幕说一层满血跑会降低约 50% 帧数，并非 FG 倍率。
- cell 43，约 **03:35**：字幕说两层降低约 50% 帧数、与未前置时一层开销相同。
- 此类百分比都是作者该机器自报。P2 可见 UI 文字与滑块，但原 sprite 每格只有 480×270，**不足以可靠提取所有 layer-specific strength/preset/mask/HDR 数值**；不能放大猜出 1、2、0.5 再当参数。
- 小马蜂 P2 的 NR 颜色跟随选项说明（cell 20，约 01:40）可读字幕：“NR颜色跟随决定整体色调是否跟随滤镜”。没有可批准的精确枚举/数值，且不是玄方的设置。

## 已知 / 缺失 / 主代理边界

**已证实来源值**：A 表所有枚举名字和标量；玄方 Cinematic + Quality + NR→SR 的选择；B 的另一套前置 UI 值；P2 存在 NR 多层前置。

**仍缺失**：玄方本人 PRE-SR 的逐项强度、preset、mask/UI 布尔、transfer/color/paperWhite 最终值；其 NR 层数；P2 每层的完整值；HDR 显示链路/色域/transfer function/白点 nits；可直接迁移的 depth/MV binding 和坐标约定；本地 PRE3 字段/枚举对照与 Linux FG/RT/LS 支持。

因此严格复现玄方本人时，目前能直接确认的只有 **Cinematic、Quality、前置顺序**；按“他链接的原教程 UI 数值”复现时，可额外提出 **四个 2.00、三项颜色/纸白倍率 1**，但必须明确这来自木每木每酉卒了的旧 V3 画面，不是玄方公开 PRE3 参数。Depth/MV 维持当前已验证路径，不依据视频覆盖；bool 不猜。**不调低用户 Quality。**

## 获取与验证限制

- 只使用无登录公开 HTTP：Chrome131 User-Agent；无私有 cookies、无账户、无签名计算、无挑战绕过。播放 API 自动返回带平台签名的公共 CDN URL，原样使用；没有自行生成签名。
- 常规 view/video HTML 返回 412；停止该通路。archive/desc、search SSR、reply/reply、pagelist、player、playurl、videoshot 可公开读取。
- 四个 player 响应的 subtitle list 均为空：**无公开字幕轨获得**。引用字幕来自视频烧录字幕/预览帧，不是猜测 ASR。
- 3 个视频各抓 hot 页 1、2；页 2 返回零结构，而页 1 公布大量总评论数，**不能声称抓全评论区**。所有抓到的作者根楼均展开楼内分页（36 回复的楼抓 2 页），见 `coverage.json`；“full descriptions”成立，“all public comments”不成立。
- 原教程360P与小马蜂720P仅取得前缀；野生装机宅/小马蜂P1的360P是完整公共媒体。已保留失败 HTTP metadata，部分 `.body` 是错误页而非视频，应依据 status/content-type 区分。
- 解码均 `ffmpeg -hwaccel none -threads 1`，图像仅 Pillow CPU 裁剪/缩放；没有运行下载到的脚本或二进制，没有访问网盘/插件链接，没有运行本地游戏或配置工具。搜索 SSR 仅在 node 限时空 VM 中解码序列化状态表达式。

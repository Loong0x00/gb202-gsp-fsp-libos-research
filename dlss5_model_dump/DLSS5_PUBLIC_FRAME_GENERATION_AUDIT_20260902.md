# 公开 DLSS 5 / DLSSNR 测试中的 Frame Generation 使用情况

审计日期：2026-09-02

目的：回答“目前公开的大量 DLSS 5 测试中，哪些实际开启了 Frame Generation”，并判断是否已有足够证据支持研究 NR→MFG 轻量转接器。

## 1. 分类规则

- **明确开启**：视频章节、设置画面、作者正文或官方测试脚注明确写出 FG/MFG 及倍率。
- **明确关闭**：明确写出 `FG Off`、`no frame gen` 或 `Frame Generation disabled`。
- **未披露**：游戏支持 FG、GPU 支持 FG、FPS 很高或作者讨论过 FG，都不能代替本次测试状态证据。
- **非 DLSS FG**：Smooth Motion、Lossless Scaling 等单独列出，不能混入原生 DLSSG/MFG。

还要区分：

- NR Off + FG On；
- NR On + FG Off；
- NR On + FG On。

只有最后一种能直接观察 NR→FG 时间域兼容性。

---

## 2. 明确开启 NR + NVIDIA DLSS FG/MFG 的公开测试

### 2.1 NVIDIA 官方《NBA 2K27》

来源：<https://www.nvidia.com/en-eu/geforce/news/dlss-5-3d-guided-neural-rendering/>

所有官方性能柱状图同时开启：

```text
DLSS 5 3D-Guided Neural Rendering
+ DLSS Super Resolution
+ 6× Multi Frame Generation
```

关键结果：

- 4K Performance：RTX 5090 370 FPS、RTX 5080 233 FPS；
- 1440p Quality：5090/5080/5070 Ti/5070 为 594/413/353/262 FPS；
- 1080p Quality：5090/5080/5070 Ti/5070/5060 Ti/5060 为 797/602/530/386/325/258 FPS。

这些是 6×生成后的输出 FPS，不是 MFG-off 渲染 FPS。官方没有公开 2×/4×/6×运动画质 A/B。

#### 2.1.1 官方视频与 Gamescom 可操作试玩复核（2026-09-03）

官方视频：<https://www.youtube.com/watch?v=79D8SVjB3HQ>

下载到的最高质量 YouTube 轨为 `3840×2160/30 FPS`、141.733 秒，视频 SHA-256
`1c17397472fd3753bedbe6dc7a7d64e01554428b676a38eb6682a4d95fa368f4`。英文字幕和画面标注只说明
`DLSS 5 ON/OFF`，没有说明这些镜头本身使用 6× MFG；明确的 6×声明属于上述性能图。片中绝大部分是剪辑后的低机位、近景、回放或过场式镜头，没有 HUD、输入画面或连续自由操控证据。30 FPS 发布轨也无法保留 258–594 FPS 输出中的逐个 MFG 中间帧，因此它不能验证 6× MFG 的时间域质量，更不能回答“不可预测玩家输入是否触发失败”。

媒体证据必须进一步区分“有人实际操控”与“看实时演示/官方录像”：

| 来源 | 玩家实际操控 | 当场 FG 倍率 | 时间域观察 |
|---|---|---|---|
| PurePC | 是；原文 `mogłem pograć` | 未披露 | **报告偶发伪影：快速移动球员出现可见 smear/trailing**；原文为 `sporadycznie ... artefakty ... widocznym smużeniem przy szybko poruszających się graczach`。但没有说明出问题的是记者控制的球员还是场上 NPC，也没有独立录像。 |
| PC Gamer | 是；`I played virtual basketball` | 未披露；6×只明确用于性能图 | 作者刻意寻找 fast motion 下的 ghosting、脸部 morph、blur/smear，称在这次受限试玩中 `there was no hint of that here`。 |
| ComputerBase | 短暂试玩 | 未披露 | 称短暂试玩没有图形错误，快速运动也未见问题；未做逐帧或 MFG 隔离。 |
| TechRadar | `brief hands-on` | **2× FG** | 称 RTX 5060 Laptop 很流畅；没有专门检查 ghosting。因此不能用来证明 6×。 |
| Tom's Guide | 是，多套系统 | MFG 开启且 `ramped up`，倍率未披露 | 帧率计数器关闭；称主观流畅、无可察觉延迟，但未报告逐帧伪影检查。 |
| Frandroid | 只明确称看到实时运行，未建立亲自操控 | **6× MFG** | 没有报告 ghosting/smear；不能作为玩家输入测试。 |

PurePC：<https://www.purepc.pl/nvidia-dlss-5-zapowiedz-nba-2k27>

PC Gamer：<https://www.pcgamer.com/hardware/graphics-cards/nvidia-snuck-me-into-a-room-to-show-off-dlss-5-in-person-and-its-somehow-beautiful-ugly-impressive-and-troubling-all-at-the-same-time/>

ComputerBase：<https://www.computerbase.de/artikel/grafikkarten/nvidia-dlss-5-launch.99166/>

TechRadar：<https://www.techradar.com/computing/gpu/i-played-nba-2k27-with-nvidias-dlss-5-at-gamescom-and-i-was-genuinely-impressed-with-it-but-one-thing-still-worries-me>

Tom's Guide：<https://www.tomsguide.com/gaming/pc-gaming/i-tested-the-real-dlss-5-forget-the-leaked-mods-its-not-an-ai-filter-this-is-nvidias-photorealistic-game-changer>

Frandroid：<https://www.frandroid.com/marques/nvidia/3227471_nvidia-ma-definitivement-convaincu-avec-le-dlss-5-sur-nba-2k7-mais-attention-aux-performances>

严格结论：已经有一条**可操作试玩中快速球员 smear** 的一手媒体报告，但尚无同时满足
`玩家自由操控 + 明确 6× + 独立高帧率直录 + 能确认伪影属于受控角色` 的样本。因此它与本机《鸣潮》“NPC稳定、受控角色失败”的现象方向一致，但还不能证明两者是同一时间域契约问题。

### 2.2 MxBenchmarkPC：RTX 5080 严格分段测试

这一组是目前最清楚的社区公开证据。视频说明直接列出每个章节的 `DLSS 5 NR On` 与 `DLSS FG Off/2X/4X`，且抽取的设置画面能看到实际 FG 菜单项。FG-on 章节是连续移动实机画面，不是只有菜单或静态截图。

#### Cyberpunk 2077

视频：<https://www.youtube.com/watch?v=tTowPWp3cQc>

配置：RTX 5080、4K/1440p、DLSS 4.5、RT/PT。

明确 NR+FG 段：

- 4K Performance、RT：FG 2× `5:54`；MFG 4× `6:54`
- 1440p Balanced、RT：FG 2× `9:44`；MFG 4× `10:43`
- 1440p Balanced、PT：FG 2× `12:21`；MFG 4× `13:14`

另有匹配的 NR On + FG Off 章节，可用于性能和画面基线。

#### S.T.A.L.K.E.R. 2

视频：<https://www.youtube.com/watch?v=Yu1w1Wcf1Iw>

配置：RTX 5080、Epic、4K/1440p。

明确 NR+FG 段：

- 4K Performance：FG 2× `6:01`；MFG 4× `7:02`
- 1440p Balanced：FG 2× `11:05`；MFG 4× `12:01`

#### Resident Evil Requiem

视频：<https://www.youtube.com/watch?v=llEmw5yk8z4>

配置：RTX 5080、Path Tracing、4K/1440p。

明确 NR+FG 段：

- 4K Performance：FG 2× `6:50`；MFG 4× `8:16`
- 1440p Balanced：FG 2× `12:28`；MFG 4× `13:50`

#### The Witcher 3

视频：<https://www.youtube.com/watch?v=P86M1uS_i2I>

配置：RTX 5080、RT Ultra+、4K/1440p。

明确 NR+FG 段：

- 4K Performance：FG 2× `7:49`
- 1440p Balanced：FG 2× `12:48`

这个游戏的视频没有 4×章节。

#### Control 对照

视频：<https://www.youtube.com/watch?v=tBNHXfPpWwY>

同一频道的 Control 测试只列 NR Off/On，没有 FG 章节。不能把它算作 FG-on 测试。

### 2.3 GTA V Enhanced：RTX 5090、4×MFG

视频：<https://www.youtube.com/watch?v=Buk1-GKxUoU>

标题和说明均明确写出：

```text
4K, RTX 5090, max settings, ray tracing,
DLSS 5 Neural Rendering + DLSS 4X Multi Frame Generation
```

视频含驾驶和角色移动段。作者也明确指出 NR 会在 MFG 之前把底层帧率大致减半。

### 2.4 S.T.A.L.K.E.R. 2：RTX 4090 社区 On/Off

来源：<https://www.reddit.com/r/nvidia/comments/1w1gcp3/removed/>

作者明确报告：

> With frame gen on ... 100fps with DLSS5 turned on. Without frame gen, that drops to around 60.

这是明确的 NR+FG On/Off 用户报告，但原帖被删除，分辨率、倍率和完整设置缺失，证据强度低于带章节的视频。

### 2.5 Cyberpunk 2077：Ada MFG 解锁社区测试

来源：<https://www.reddit.com/r/nvidia/comments/1w3ycdy/dlss_mfg_working_on_ada/>

明确组合测试包括：

- RTX 4090：4K、PT、DLSS Performance、DLSS 5、4×FG；报告延迟约 70–80 ms，并看到更多 4×伪影；
- RTX 4080：DLSS 5 下更偏好 3×而不是 4×；快速运动时 4×伪影更多；
- 其他用户报告 3×–6×，但设置完整度较低。

这是非官方 Ada MFG 解锁路径，不代表 Blackwell 正式质量；但它明确证明社区已经在观察 NR→MFG 的组合行为。

### 2.6 本机《鸣潮》

录屏：`/home/user/2026-09-02 06-14-04.mp4`

- 6144×3456、60 FPS、28.373 秒；
- Ultra Performance `2046×1151 → 6144×3456`；
- Feature18/DLSSNR + 6×FG；
- 角色奔跑、技能、头发、衣摆、腿和武器边缘出现周期性分裂、拖影和鬼影。

这是本机目前最强的 NR→6×FG 时域证据，因为已同时验证 SR/RR、NR Evaluate 和下游 Streamline DLSSG 顺序。

---

## 3. 使用了生成帧，但不是原生 DLSS FG/MFG

### Helldivers 2：Smooth Motion 2×

来源：<https://www.reddit.com/r/nvidia/comments/1w10znh/testing_helldivers_2_with_dlss_5_on_ada/>

配置：RTX 4070 Ti Super、4K、DLSS Quality、实验性 DLSSNR；30–40 FPS 底层帧率由 NVIDIA Smooth Motion 大致翻倍。

这是 driver-level Smooth Motion，不是 Streamline DLSSG/MFG。可以作为“NR 输出交给普通图像插帧器”的旁证，但不能验证 DLSSG guide contract。

Lossless Scaling 等外部插帧测试也应归入此类。

---

## 4. 明确关闭 Frame Generation 的公开测试

| 游戏/来源 | 明确证据 |
|---|---|
| 《鸣潮》公开 4K DLAA 视频 <https://www.youtube.com/watch?v=NIX4LbAfxPo> | 视频说明：`FG - Off` |
| S.T.A.L.K.E.R. 2 / Game With Dave <https://www.youtube.com/watch?v=vvKeVW_jN4w> | 说明：`RTX 5090 performance with Frame Generation disabled` |
| Cyberpunk 2077 截图 <https://www.reddit.com/r/cyberpunkgame/comments/1w0qqfw/dlss_5_cyberpunk_screenshots/> | 作者：`no frame gen` |
| Like a Dragon: Infinite Wealth <https://www.reddit.com/r/nvidia/comments/1w0snlv/dlss_5_like_a_dragon_infinite_wealth/> | 作者：`+80fps ... no FG` |
| Half Sword <https://www.reddit.com/r/nvidia/comments/1w11gcn/half_sword_with_dlss5_afterbefore/> | 作者：`NO Frame Gen` |
| MxBenchmarkPC / Control <https://www.youtube.com/watch?v=tBNHXfPpWwY> | 所有性能章节只列 NR Off/On，没有 FG-on 段；按章节记录为 FG Off/无 FG 测试 |

Control 5070 Ti 的著名 `71 → 35 FPS` 测试只写了 4K、RT High、DLSS Quality、NR On/Off，没有逐字写 `FG Off`。Control 原始模组也没有 DLSSG 组件，所以它很可能是非 FG 帧率，但严格分类仍记作“未披露/高概率关闭”，不当作明示证据。

---

## 5. 大量未披露状态的测试

### 5.1 Reddit 非官方 DLSS 5 megathread

来源：<https://www.reddit.com/r/nvidia/comments/1w1817k/megathread_unofficial_dlss_5_neural_rendering/>

审计到 29 个游戏/评论测试：

- 明确 FG Off：2
- 明确 FG On：0
- FG 未披露：27

这不表示 27 个都关闭，只表示截图、正文和设置不足以判断。

### 5.2 Testing Games 系列

公开视频覆盖：

- Control
- Cyberpunk 2077
- GTA V Enhanced
- The Witcher 3
- Red Dead Redemption 2
- Horizon Forbidden West
- S.T.A.L.K.E.R. 2

视频说明通常只列 `DLSS Quality` 和 NR On/Off，没有写 FG。抽查 Control 视频可见 124 FPS Off 对 62 FPS On，但 FPS 数值不能替代 FG 设置证据，因此整组列为未披露；Control 高概率未使用 FG。

### 5.3 Kran.GG

<https://kran.gg/Blog/dlss-5-testing>

Starfield、Fallout 4、Rainbow Six Siege 的大量截图和场景测试均未明确披露 FG 状态。文章提到一次 FG/HDR 故障，但不说明具体截图测试是否开启 FG。

### 5.4 Ampere 大规模兼容测试

Tom's Hardware 汇总的 GTA V、Dying Light 2、Hogwarts Legacy、Mortal Shell 2、Ready or Not、NTE、NBA 2K27、Deep Rock Galactic、Cyberpunk 等 Ampere 测试都没有可靠 FG 声明：

<https://www.tomshardware.com/pc-components/gpus/dlss-5-mod-brings-next-gen-tech-to-old-ampere-gpus-but-frame-rates-are-horrible-most-games-tank-to-single-digits-high-end-gpus-can-hit-up-to-40-fps-in-some-cases>

不能从 RTX 30 不支持原生 DLSSG 就自动推断“完全无生成帧”，因为测试者仍可能使用 Smooth Motion、OptiFG、FSR FG 或 Lossless Scaling；来源没写就只能记未知。

### 5.5 Final Fantasy VII Rebirth

<https://www.reddit.com/r/nvidia/comments/1w0lbsv/dlss5_final_fantasy_rebirth_comparisons/>

作者明确说：

> Atm it's only usable if you use multi frame gen

这证明作者认为 MFG 是可用性要求，但没有证明每张对比截图拍摄时 MFG 已开启，也没写倍率，因此归类为“建议/很可能使用，未形成严格测试证据”。

---

## 6. 统计结论

按“独立游戏标题”计，已经找到明确 NR+原生 NVIDIA FG/MFG 的至少 7 款：

1. NBA 2K27（官方 6×）
2. Cyberpunk 2077（2×/3×/4×，多个来源）
3. S.T.A.L.K.E.R. 2（2×/4×及社区 On/Off）
4. Resident Evil Requiem（2×/4×）
5. The Witcher 3（2×）
6. GTA V Enhanced（4×）
7. Wuthering Waves（本机 6×）

MxBenchmarkPC 四个游戏本身就提供至少 16 个明确的 NR On + FG On 分段配置；加上官方 NBA、GTA、社区 S.T.A.L.K.E.R. 2/Cyberpunk 以及本机《鸣潮》，样本已经足够证明 NR→FG 组合不是罕见边缘情况。

但绝大多数 Reddit 截图、新闻引用和兼容性截图没有 FG 状态，不能用于统计鬼影发生率。

---

## 7. 对 adapter 研究的意义

### 可以确认

- 有足够多的 NR+FG 真实运动样本支持进一步研究；
- 公开 MxBenchmarkPC 段包含驾驶、奔跑、武器/角色、雨天人群和植被等不同运动类型；
- 高倍率 4×/6×比 2×更适合作为伪影压力测试；
- 本机《鸣潮》仍是最可控的现场，因为可以访问 NR 前后颜色、MV、Depth 和调用时序。

### 公开视频的限制

- 大多数 YouTube 视频是 60 FPS 编码，无法保留 4×MFG 的全部真实输出 cadence；
- 有损压缩会掩盖/制造细边缘残影；
- 没有原始 SR/NR endpoint、MV、Depth、disocclusion 和每个生成帧；
- 因此适合做定性场景选择，不适合直接训练几十万参数 adapter。

### 建议实施顺序

1. 不先训练模型；先在《鸣潮》实现零参数/少参数 motion gate：

   ```text
   Color_for_FG = SR + alpha(MV, depth edge, history validity) × (NR - SR)
   ```

2. 静态区 `alpha≈1`；高速运动、深度断裂、新显露区域退回 SR。
3. 固定使用 Quality SR，禁止热切 DLAA；先测试 FG 2×，再逐步升到 4×/6×。
4. 保存 NR 前 SR endpoint，否则 NR 当前的 in-place output 无法回退。
5. 记录相同路线的：NR Off+FG、NR On+FG、gate+NR+FG 三组原始捕获。
6. 如果 heuristic gate 明显减少鬼影，再采集输入/标签训练低分辨率约 0.1–0.5M 参数 adapter。

这条路径不要求修改封闭的 DLSSG 内部接口；先通过改变送给 MFG 的真实端点验证“轻量转接层是否有效”。若要输出 DeltaMV/confidence，则后续还需确认 Streamline/DLSSG 是否允许安全地提供修正 guides。

---

## 8. 社区实现是否和本机顺序不同

结论：**主流 RenoDX/OptiScaler 路径与本机逻辑顺序基本相同，不是简单的 FG→NR 晚期滤镜。** 但每个游戏的 FG 是否消费同一 HUDless 资源仍需资源指针追踪，不能仅凭菜单证明。

### 8.1 RenoDX 二进制静态证据

本机保留的 Cyberpunk 社区 addon：

- `benchmark_logs/dlss5_cp2077_rerun_20260829_184518/artifacts/final-installed-files/renodx-dlss5.addon64`
- SHA-256：`87aef9ddd937c7241e6bf8d8efea0045d63559135e254c60dab316db3d3a4aee`

其字符串明确写出：

```text
Insertion: immediately after the game's NGX DLSS output; UI remains downstream.
```

另一本机 addon（SHA-256 `b842c25e...`）同时 hook：

- `NVSDK_NGX_D3D12_EvaluateFeature`
- `slEvaluateFeature`
- `slSetTag` / `slSetTagForFrame`

并记录：

```text
D3D12 NGX hooks installed; inline DLSS contract capture armed
```

这说明它的核心不是 ReShade Present 后处理，而是识别上采样/RR Evaluate，随后立即运行 NR。

### 8.2 OptiScaler-DLSSNR 源码证据

审计源码：<https://github.com/Dagherbou/OptiScaler_DLSSNR/tree/dlss-neural-rendering>

本地审计 commit：`393e0706b950a0ff1498e9dcf66989a80de72f31`

`DlssNrFeature_Dx12.h` 明确写出：

```text
The model runs immediately after the game's upscaler, before the interface is drawn.
Called only for upscaler evaluates -- never for frame generation.
```

菜单说明则写：

```text
Synthesises detail in the upscaler's output, before frame generation sees it.
```

所以其设计顺序也是：

```text
SR/RR → NR → UI/FG
```

### 8.3 社区并没有隐藏的运动 adapter

OptiScaler 当前 resolve 会：

- 保存未改动的上采样输出；
- 给 NR 一个 display-referred proxy；
- 用 RenoDX 的 luminance ratio、OkLab hue 修正与 AP1 clamp 把 NR 结果合成回原图；
- 通过 `TransferStrength`、`ColourStrength` 和 `MaxRatio` 限制修改幅度。

源码中还残留 `gMotion`、`previous edit` 与 temporal accumulation 的描述符/注释，但当前 shader 没有实际读取这些历史；模块 README 明确写：

```text
There is no accumulator; the composition is re-anchored to the model every frame.
```

因此它没有解决“NR 新细节缺少 MFG 运动语义”这一根本问题。本机 codec 同样使用 RenoDX 的 ratio/OkLab 合成，不能把差异简单归因于社区多了一层时域网络。

### 8.4 为什么公开视频看起来更干净

1. **倍率不同**：公开视频主要为 2×/4×；本机压力测试是 6×。
2. **真实端点 cadence 不同**：本机约 `70/6≈11.7 FPS`，每两个真实端点相隔约 85.7 ms。
3. **内部输入不同**：本机 Ultra Performance 为 `2046×1151→6144×3456`，空间倍率约 3×；公开视频 4K Performance 通常约 2×。
4. **内容不同**：本机包含动漫角色启动、头发、衣摆、腿、武器和技能；抽取的公开段多为刚性车辆、慢走、第一人称武器摆动或 2×角色移动。
5. **强度可能不同**：本机现场存在 `Intensity 1.55–2`、`LocalStructure 2`、`SkinStructure 2`、`ColourStrength 1` 的激进控制记录；本机保存的 Cyberpunk 社区包只显式覆盖 `NRColorStrength=0`，其余接近默认 `1/1/1/-1`。公开视频作者没有披露完整 RenoDX slider，不能证明完全相同。
6. **契约模式可能不同**：本机 6×测试附近的 2046×1151 session 日志显示 `ScalingRatio=0.5`、`DLSSNR.Upscaling=true`；社区/OptiScaler 设计文档默认把 NR 当作 full-display post-upscale pass。两者不是严格同一 Feature18 operating point。
7. **视频采样掩盖**：公开源为 4K60 YouTube。4×MFG 在高于 60 Hz 的输出中产生的多数中间帧不会进入录制，压缩和缩放也会掩盖一帧型边缘分裂。

抽取 Cyberpunk、STALKER 2、RE Requiem 与 Witcher 3 的连续 12 个 60 Hz 录制帧，没有看到与本机一样严重的周期性分裂；这只能说明这些慢速片段在 60 Hz 编码中没有明显暴露，不能证明所有生成帧无鬼影。

此外，Cyberpunk Ada MFG 社区报告已经明确称 4×快速运动伪影更多，并偏好 3×；OptiScaler 源码也记录过错误 MV 比例导致沿运动方向 smear，以及“如果细节在运动中 shimmer，应继续检查 history”。所以社区路径不是无伪影。

### 8.5 仍未排除的逐游戏资源差异

Streamline FG 可能消费：

- 被 NR 原位改写的同一上采样/HUDless texture；或
- 游戏另行标记的 HUDless scene resource。

第一种是真正的 `SR→NR→FG`；第二种可能出现“NR 只改真实显示帧、FG 仍从原场景资源生成”的部分串联。公开视频设置和 FPS 无法区分。要确认每个游戏，必须记录 `slSetTag` 的 `HUDLessColor` 资源地址、上采样 Output 地址以及 DLSSG Present 前后的 resource identity。

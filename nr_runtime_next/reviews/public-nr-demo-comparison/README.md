# Public NR demo comparison — evidence, not a reproduction

Checked **2026-09-10 UTC**. Scope: unauthenticated public web downloads and **CPU-only** video-frame inspection. No local game, Wine, GPU, app/account, private-cookie, or network-configuration operations. Images here are extracted from public videos, **not captures of the user's game**. No DLL/add-on was downloaded or executed.

## Bottom line

1. **The main WuWa demo is not a 6K test.** Its visible UI is **2560×1440, DLSS Quality, frame generation 6×, ray tracing Off**. At **00:06** the original creator explicitly says DLAA/RT were avoided because otherwise the video would be choppy. This is a concrete reason its apparent smoothness cannot establish acceptable latency/performance for the user's 6K RR→NR case.
2. Found the **content-matching YouTube comparison and the creator's public X→YouTube link**. A separate tutorial by that creator exposes NR controls: **Natural**, preset **Default**, intensity/tone/structure **1.00**, skin **−1.00**, automatic mask **Off**, HDR transfer **1.00**. These differ from the user's recorded controls. **They are tutorial settings, not proven settings of the earlier comparison.** Numeric style/preset enums and module hashes remain unknown.
3. The large WuWa differences are chiefly **relighting, material/texture appearance and character shading changes**. The split views often differ in camera, pose, zoom, or action timing. They do **not** establish objective detail recovery, mesh improvement, or temporal stability.
4. The ZZZ examples do **not** uniformly demonstrate a dramatic gain. One uploader reports a **20–25% FPS loss**; another reports roughly halved FPS and commenters describe small changes. These are source reports, not measurements of this user's case. The supplied X video is a single-view demonstration, not an identified controlled On/Off comparison.
5. **No evidence justifies promising a fix, identifying a wrong genus, or claiming that stronger settings will solve the user's “little benefit, severe lag.”** The user's exact NR path, guides and HDR behavior cannot yet be matched to the comparison.

## 1. Source identity and access

| Source | Public evidence obtained | Limit / provenance |
|---|---|---|
| [BV1G34m6sETX](https://www.bilibili.com/video/BV1G34m6sETX/) — lalana1712, `[鸣潮] 当切换为 DLSS 5 会有什么变化` | HTML, API metadata, public comments, complete **852×480 / 30 fps** video | Description says authorized sharing, RTX 5070 Ti + 7800X3D + 32 GB, “DLSS 4.5 / DLSS 5 Quaity.” Only low-resolution streams returned anonymously. |
| [YouTube yLfgFIbz-4s](https://www.youtube.com/watch?v=yLfgFIbz-4s) — FanticSama | Complete **1920×1080 / 60 fps**, 233.25 s video | Same hardware/settings introduction and comparison sequence as the main Bilibili upload: matched at 00:06, 00:12, 00:42 and 01:20. YouTube carries FANTICSAMA watermark; Bilibili adds its own branding/subtitles/divider label. Content match, not a Bilibili description explicitly naming the original author. |
| [FanticSama on X](https://x.com/FanticSama/status/2093832272084599250) | Creator's [public profile](https://x.com/FanticSama) contains this status and explicit link to `youtube.com/watch?v=yLfgFIbz-4s` | YouTube descriptions reciprocally link `x.com/FanticSama`. Saved profile HTML is the inspected evidence; no login. |
| [BV1ot4D6gEC2](https://www.bilibili.com/video/BV1ot4D6gEC2/) — 樹导, `绝区零强开 DLSS5神经渲染 对比` | HTML/API/comments, complete **854×240 / 30 fps**, 65.17 s video | Original upload dimension in API: 3840×1080 split screen, not proof of either game's internal guide dimensions. Public stream is very low resolution. |
| [BV1sk4y6iEH5](https://www.bilibili.com/video/BV1sk4y6iEH5/) — 蘿蔔Grape, `【绝区零 \| DLSS 5】40系简单测试` | HTML/API/comments, complete **854×356 / 29.97 fps**, 33.73 s video | NR panel is present but tiny. Enlarging its approximately 120-pixel-wide panel does not recover trustworthy exact values. API description provides additional **textual**, not frame-verified, information. |
| [X wuwaguy/2094376789514780985](https://x.com/wuwaguy/status/2094376789514780985) | Public HTML and its directly linked **1920×1080 / 60 fps**, 211.77 s MP4 | Text says ZZZ is forced to run DLSS5 and not to treat it as official results. No author/source link connecting this clip to either Bilibili ZZZ upload found in the inspected post. It is not presented here as their mirror. |
| [Reddit megathread](https://www.reddit.com/r/nvidia/comments/1w1817k/megathread_unofficial_dlss_5_neural_rendering/) | Public [RSS/Atom feed](https://www.reddit.com/r/nvidia/comments/1w1817k/megathread_unofficial_dlss_5_neural_rendering/.rss) returned **200** and thread/comments | Main HTML and JSON returned **403**; old.reddit HTML also **403**. RSS is a normal unauthenticated public representation, not an account bypass. Feed is a subset, not a claim to have read every comment. |
| Creator-linked follow-up: [BV13ptx6hEGN](https://www.bilibili.com/video/BV13ptx6hEGN/) / [YedVDOKdxJE](https://www.youtube.com/watch?v=YedVDOKdxJE) | Main Bilibili uploader's comment links `https://b23.tv/6nScl5a`, which redirects to BV13ptx6hEGN. Matching titled 293 s YouTube performance follow-up found on FanticSama's channel; opening **00:00–00:40** frames inspected | YouTube transfer ended at **23,068,496 of 183,518,471 bytes**, curl 56 (TLS unexpected EOF). **Partial file; no claim about its remainder.** Its visible settings contradict the Bilibili follow-up's reused “Quality” description: see §3. |
| Same-creator tutorial: [GLuElt0RLtc](https://www.youtube.com/watch?v=GLuElt0RLtc) | Complete **1920×1080 / 60 fps**, 184.85 s video; readable NR UI at **02:40–02:52** | Separate video, later than the comparison. Only inspected as evidence; its installation instructions were not followed. |

### Access failures and mirror search, precisely

- User/task reported the parent's earlier Bilibili API **HTTP 412**. **That failure was not reproduced here**: at 09:12:41 UTC all three ordinary `x/web-interface/view?bvid=...` requests returned HTTP 200 / JSON `code: 0`; public playurl and comment APIs also returned code 0. No cookies, login, signed-WBI workaround, CAPTCHA handling or access-control bypass was used.
- The public playurl response advertised higher quality labels but returned only low-resolution anonymous streams. Only returned stream URLs were downloaded; no fabricated higher-quality URL or quality-unlock workaround.
- Main Bilibili CDN download first ended at **6,291,456 bytes**, curl 18, with 20,107,307 bytes missing. Ordinary HTTP range resume returned **206** and completed the **26,398,763-byte** file. Main YouTube download initially timed out at **58,261,072 bytes**, curl 28; ordinary range resume completed **153,610,928 bytes**. Original failures and resume records remain saved.
- Google searches returned JavaScript redirect shells without usable results. Bing responses contained unrelated results (Naver/Windows help/ticketing); these were **discarded as evidence**, not taken as “no such video.” DuckDuckGo returned no result for `"lalana1712" "DLSS"`.
- Public YouTube search for `Wuthering Waves DLSS 5 5070 Ti` found the performance follow-up. The creator's public channel exposed the comparison and tutorial; the creator's public X profile independently links the comparison. No author-linked YouTube/X mirror of the two ZZZ Bilibili clips was established from their inspected descriptions/comments.

## 2. Main WuWa comparison: actual settings and visual evidence

Timestamps below are elapsed time in **yLfgFIbz-4s**; the matched Bilibili introduction has the same second marks. PNG links are exact-seek CPU extractions, not contact-sheet estimates.

| Time / evidence | Visible information |
|---|---|
| [00:00](frames/youtube_fanticsama_comparison_clip_t000.png) | AMD Ryzen 7 7800X3D, RTX 5070 Ti, 16 GB video memory, 32 GB memory, graphics driver 616.56, DX12. |
| [00:06](frames/youtube_fanticsama_comparison_clip_t006.png) | Graphics Custom, Full Screen, **2560×1440**. Caption: “And this is the settings I used for the video. (Didn't used DLAA/RT or else the video would be choppy)”. |
| [00:12](frames/youtube_fanticsama_comparison_clip_t012.png) | NVIDIA DLSS **On**; Frame Generation **6x**; Super Resolution **Quality**; Sharpening **0**; anisotropic filtering **1x**. |
| [00:13](frames/youtube_fanticsama_comparison_clip_t013.png) | Ray Tracing **Off**. This is not evidence of the exact SR/RR hook or guide-input stage. |
| [00:42](frames/youtube_fanticsama_comparison_clip_t042.png) | NPC face/clothing comparison labelled 4.5 versus 5, but **different zoom/framing**. Cannot call larger visible facial detail an objective improvement. |
| [01:20](frames/youtube_fanticsama_comparison_clip_t080.png) | Same character/location, **different facing/pose**. Right/“5” has stronger face/neck shading, darker scene, more pronounced cloth/material shading; the left retains flatter anime-style facial lighting. A style/lighting change, not proof of corrected face geometry. |
| [02:05](frames/youtube_fanticsama_comparison_clip_t125.png) | Forest/path pair: right has changed foliage/ground shading and surface contrast; bodies/stride and viewpoints are not pixel-registered. Same route rather than same input frame. |
| 03:00–03:50, [sheet](frames/youtube_fanticsama_comparison_clip_04.jpg) | Different combat moments/animations and countdowns. Unsuitable for per-pixel fidelity or temporal-quality metrics. |

**Not visible in the comparison's inspected frames:** NR DLL version/hash, add-on build, numerical preset/style enum, layer count, exact input stage, actual guide/output sizes, SR/RR API sequencing, motion/depth validity, automatic-mask state, UI correction, strength sliders, HDR transfer or paper white. The “4.5” and “5” labels are editorial labels, not runtime telemetry or binary-version proof. The video stream's BT.709 tag is **not** an NR HDR-transfer setting or a measurement of the source display pipeline.

## 3. Important follow-up discrepancy: trust visible UI over copied description

The **Bilibili uploader's own reply** links the performance follow-up. Its description again says “DLSS 4.5 / DLSS 5 Quaity.” But the content-matching YouTube follow-up's accessible opening shows:

- **00:05** subtitle: “This is the settings I used throughout the video. (This time I turned RT on and FG is disable)”.
- **[00:10](frames/youtube_fanticsama_performance_clip_t010.png):** Frame Generation **Close**, Super Resolution **DLAA**, Ray Tracing **High**, Sharpening **0**.
- **[00:15](frames/youtube_fanticsama_performance_clip_t015.png):** instantaneous overlay rows labelled **FPS** read **81 left / 50 right**; the separate **D3D12** row reads **93 / 76**. These counter labels must not be conflated, nor treated as a controlled mean or latency measurement. Framing/stride differ; no numeric performance extrapolation to the user's machine is warranted.

Only the first 40 s of this **partial** download were sampled. Its existence strengthens the original creator's warning about cost, but does not supply the missing NR configuration or a 6K benchmark.

## 4. Same-creator tutorial: readable NR UI, kept separate

Source: **GLuElt0RLtc**, [02:40](frames/youtube_fanticsama_tutorial_clip_t160.png), [02:45](frames/youtube_fanticsama_tutorial_clip_t165.png), [02:48](frames/youtube_fanticsama_tutorial_clip_t168.png), [02:50](frames/youtube_fanticsama_tutorial_clip_t170.png), [02:52](frames/youtube_fanticsama_tutorial_clip_t172.png).

This UI is on the **WuWa title/login screen**, not a matching gameplay scene from the comparison. The main comparison's exact configuration **must not be backfilled from it**.

| Field | Actually visible in tutorial | User's supplied pre-quit case |
|---|---|---|
| Add-on file / displayed version | `renodx-dlss5 (1).addon64`; **0.2026.828.2110** | Not supplied; not locally inspected |
| NR module/hash | Footer includes **DLSSNR v310.8.0**, ACTIVE / NR INJECTED; parts are subtitle-occluded across frames. **No hash shown** | Not supplied |
| Integration description | “Generic experimental DLSS Neural Rendering post-pass for DX12 games using NGX or Streamline DLSS” | **RR→5 independent NR** |
| NR enabled / add-on upscaling WIP | Enabled checked; Enable Upscaling (WIP) unchecked | NR active before quit; other field not supplied |
| NR Preset | **Default** (02:40–02:52); **numeric enum not shown** | **Preset 0** |
| NR Style | **Default at 02:45 → Natural by 02:48–02:52**; **numeric enum not shown** | **Style 1**, user UI label **Cinematic** |
| Intensity / Local Tone / Local Structure | **1.00 / 1.00 / 1.00** | **2 / 2 / 2** |
| Skin Structure Strength | **−1.00**, displayed signed value; sentinel semantics not verified | **2** |
| Automatic Mask / NR UI Correction | **Unchecked / unchecked** | **1 / 0** |
| HDR Transfer Strength / Color Strength | **1.00 / 1.00** | **0.6 / 1** |
| Scene Paper-White Scale | **1.000** — scale, **not a nit value** | **1** |
| Depth Convention | **Use game NGX flag** | Not supplied |
| Motion Scale X / Y | **1.000 / 1.000** | **MV scale 1** |
| Layers / genus / guide validity / exact SR-RR ordering | **Not shown or not established** | Layers/genus not supplied; no new assumption |

The creator changes the style to Natural and the 02:50 subtitle says “I just think that's the best.” That is **the creator's preference**, not an objective optimum. No numeric Natural↔Style1 mapping is justified by menu position or another game. Preset “Default” likewise does not establish equality to this runtime's Preset 0. The visibly lower strengths contradict an unsupported assumption that the impressive demo necessarily used higher strengths than the user's 2s.

## 5. ZZZ: what was actually seen versus claimed

### BV1ot4D6gEC2 — 樹导

- Public description: **ROG XBOX ALLYX + Thunderbolt eGPU RTX 4000 Ada SFF**; “40系强开，帧数基本上要下降20-25%.” This is the uploader's hardware/performance report.
- **[00:15](frames/bili_BV1ot4D6gEC2_clip_t015.png)** is a static planter-detail pair labelled **“DLSS 4 / NR OFF”** left and **“DLSS 5 / NR ON”** right, **“MATCHED FRAME / HOLD 3s”**. Overlay: **FPS 81 vs 59; DELTA −22 FPS (−27.2 percent)**. This single authored overlay is not an independently measured benchmark and is outside the description's approximate 20–25% range.
- The right planter/pavement has darker and differently distributed leaf/contact shading. Large new geometric detail is **not established**. The camera match is close, not proven pixel-identical; the 854×240 transcode limits texture/face judgments. Other paired scenes include storefront/signs and photo results; see [contact sheet](frames/bili_BV1ot4D6gEC2_clip_01.jpg).
- No readable NR-control panel. **No module hash/version, preset, style enum, layers, input-stage/guide validity or HDR controls can be extracted** from the inspected material.

### BV1sk4y6iEH5 — 蘿蔔Grape

- Public description: **i9-13900HX, RTX 4080 Laptop 12 GB, 32 GB DDR5-5600**. Author reports roughly halved FPS, calls the method unofficial/experimental, and warns repeated NR toggling can leak VRAM. **This warning is not a diagnosis of the user's lag.**
- Description names **HoYoShade-V3.0.0-Beta.9, renodx-zzz.addon64, renodx-dlss5.addon64, nvngx_dlssnr.dll** and says the footer should display **DLSSNR v310.8.0: ACTIVE**. That is descriptive guidance, **not proof of the precise loaded DLL or hash** in the clip.
- **[00:02](frames/bili_BV1sk4y6iEH5_clip_t002.png), [00:06](frames/bili_BV1sk4y6iEH5_clip_t006.png), [00:12](frames/bili_BV1sk4y6iEH5_clip_t012.png):** stationary orange wall/bicycle/charging-dock scene with green **DLSS 5 ON** label and visible NR UI. Changes are comparatively subtle at this transcode quality. Do not treat changes between these ON-labelled frames as a verified Off/On pair.
- **[00:28](frames/bili_BV1sk4y6iEH5_clip_t028.png)** shows a street with ON; **[00:32](frames/bili_BV1sk4y6iEH5_clip_t032.png)** shows a different bench scene labelled OFF. These two are **not a same-scene comparison**. No controlled same-scene toggle pair established by the inspected samples.
- Exact small UI fields are **unreadable/unreliable**; see [4× nearest-neighbor panel crop](frames/bili_BV1sk4y6iEH5_UI_t002_4x_nearest.png). No AI enhancement or guessed transcription. In particular, **do not copy the WuWa tutorial's fields into this ZZZ configuration**.
- Public comment: `alwaysyuri` says their own test changed little and colors were less pleasing than earlier RenoDX HDR; uploader replies “隔壁原也是这样，不知道为什么.” Both are **subjective reports**, not integration evidence.

### X — WuWa Timeline / wuwaguy

- Post: “Zenless Zone Zero with DLSS5~ (Demo) … The game is forced to run with DLSS5 here, Please do not refer it to the official results.”
- Sampled 5-second frames span street traversal, interiors and travel menus, **00:00–03:30**; [sheets 1](frames/x_wuwaguy_1080p_clip_01.jpg), [2](frames/x_wuwaguy_1080p_clip_02.jpg), [3](frames/x_wuwaguy_1080p_clip_03.jpg), [4](frames/x_wuwaguy_1080p_clip_04.jpg).
- No NR settings panel, identified Off reference, version/hash or workload telemetry found in those samples. It can illustrate an appearance, **not the size or cause of improvement over baseline**. No claim to have watched every frame or assessed latency/temporal artifacts.

## 6. Reddit: useful caution, not missing configuration

The accessible RSS contains moderator `/u/Nestledrink`'s reminders: **unofficial**, **not final**, results are modders' creations, unknowns should not be filled by speculation, and comparisons should include before/after across varied scenes. These are moderation/source-status statements, not authoritative NR parameter documentation.

A [WuWa comment](https://www.reddit.com/r/nvidia/comments/1w1817k/comment/p6j4j2o/) by `/u/Available-Ad6751` reports R5 5600 + 5060 Ti dropping to around 30 FPS. This is an unverified individual report. Another comment discusses Color Strength/HDR transfer, but is **not tied to the requested WuWa/ZZZ clips**, so its suggestions are not used to reconstruct their settings. No game's genus, layers or preset were borrowed from unrelated game posts. Extracted feed: [reddit_rss.extracted.json](sources/reddit_rss.extracted.json).

## 7. Comparison against the exact supplied active case

User-supplied record, **not re-read from game/config or re-tested**:

```text
Output: 6144×3456 (6K)
Quality guides: 4099×2306
Path: RR → 5 independent NR
Style: 1 (this user's UI: Cinematic)
Preset: 0
AutoMask: 1
UICorrection: 0
Intensity / Tone / Structure / Skin: 2 / 2 / 2 / 2
HDR transfer: 0.6
Color: 1
PaperWhite: 1
MV scale: 1
User experience: no obvious benefit; severe lag; game quit/closed
```

- **Display workload mismatch:** 6K is **21,233,664 pixels**, versus the main demo UI's **3,686,400** at 1440p: **5.76× display pixels**. The user's guide surface is **9,452,294 pixels**; the demo's actual NR guide surface is **unknown**. This is arithmetic, **not a 5.76× NR-time prediction**. It cannot substitute for measured NR dispatch sizes or timings.
- **Performance-presentation mismatch:** main demo uses **6× FG** and avoids RT/DLAA expressly for smoothness. Video frame rate / generated display frames do not establish base rendering FPS, input latency or sustained VRAM behavior. The follow-up deliberately changes to DLAA + RT High + no FG, so it is not the same test either.
- **Control mismatch, but only against the tutorial:** Natural vs user's Cinematic label; 1/1/1/−1 vs 2/2/2/2; mask off vs on; HDR transfer 1 vs 0.6. These are plausible differences to investigate only with future authorization and matched evidence. They **do not prove** why the user's benefit was small or which setting would help.
- **Unknown integration equivalence:** “Generic post-pass” does not tell us whether it matches the user's RR→independent NR, nor prove motion/depth quality, input stage, layers or training genus. Source games must be evaluated separately.
- **Quality criterion mismatch:** altered lighting/material/face appearance may be preferred or disliked. Objective improvement would require comparable framing/inputs, actual detail preservation, face/identity fidelity, temporal stability, UI preservation and performance evidence. The retrieved marketing-like split screens do not establish all of these.

**What would close the gap, without reopening anything now:** a creator-provided timestamped NR status/control view from the actual comparison session, displayed guide/output dimensions and SR/RR input path, exact DLL/add-on version **and hash**, numeric enum mapping for that build, layers and motion/depth diagnostics, HDR mode/transfer/paper-white values, plus matched static and moving On/Off clips and base-FPS/frametime data. Until then, neither “your setup is wrong” nor “copy this preset and it will be better” is supported.

## 8. Artifact and verification notes

- `sources/`: public response bodies, headers, timestamps/statuses, extracted metadata and public video payloads. Video files retain `.body` suffix; their actual containers are MP4. **`youtube_fanticsama_performance_clip.body` is incomplete.** Server-issued public CDN URLs may expire; they are not private/account cookies.
- `frames/`: timestamped contact sheets and exact-seek PNGs. Contact sheets preserve selected **input PTS** before tiling; they do not relabel fps-filter midpoint samples as exact times. Exact PNG filenames `_tNNN` denote requested elapsed seconds; codec timestamp rounding can differ by one source frame.
- `verification/`: ffprobe metadata, actual CPU ffmpeg command records, decoder logs and [summary](verification/decode-summary.json). Full CPU decode with `-xerror` **passed for all six complete videos**. The partial performance file **failed as expected (exit 183)**; it is not silently counted as a complete video. Probe duration alone does **not** prove complete download: that file advertises its full duration in its header. Python AST syntax checks passed for all three scripts, and all report-relative evidence links were checked to exist.
- [bilibili_metadata_extract.json](bilibili_metadata_extract.json): bounded primary metadata/description extracts, including the follow-up's misleading Quality description.
- [SHA256SUMS.txt](SHA256SUMS.txt): exact paths/checksums of research artifacts; these hashes **are not NR module hashes**.
- Scripts: `fetch_public_sources.py`, `inspect_cpu_clips.py`, `verify_artifacts.py`. Network fetching used ordinary public `curl --disable` and `yt-dlp --ignore-config --no-cache-dir --skip-download --dump-single-json`; no cookie options. Decoding used `ffmpeg -hwaccel none -threads 2`, software filters and null-output validation. Audio was not evaluated. No objective image-quality metric was computed on unregistered pairs.

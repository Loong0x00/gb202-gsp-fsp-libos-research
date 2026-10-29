# WuWa public comment audit — primary comment text, not same-source matching

No GPU/Wine/game/config operations. User explicitly removed the Douyin same-source requirement.

## Substantive uploader evidence

Video [BV1NhtW67EUq](https://www.bilibili.com/video/BV1NhtW67EUq/), uploader 玄方研究院, mid3707016587512597. Comment rpid312682909937 has the same member.mid (uploader verified by saved Bili search metadata). Public API:

`https://api.bilibili.com/x/v2/reply?type=1&oid=117184978229885&sort=2&pn=1&ps=20`

Uploader says:

> 目前已有UP主研究出将DLSS5神经渲染环节移至超分辨率之前，这样可在较低分辨率下进行渲染再超分，损失极小的DLSS5效果，但换来了较大的性能提升。传送门：BV1zutj6EEbo
> 目前上述配置和设置已经可以在质量模式下开启两倍帧生成叠加2倍Lossless Scaling完美120帧运行（之前需要平衡+3倍帧生成），延迟和鬼影都得到了极大改善。已经完全达到日常体验的程度。下面是开启DLS5S效果对比（右图为开启）

The video was published 2026-08-31T10:57:34+08:00, while this uploader update is dated 2026-09-02T13:14:50+08:00. **The later PRE/FG settings must not be backfilled as the original video's recording configuration.**

This is **a primary uploader report, not independent performance validation**. Crucial differences versus our ended live trial: author reports **NR before SR**, plus **2x frame generation and2x Lossless Scaling**, whereas our live trial was RR then5 independent NR at6K. '120 frames' cannot be treated as120 native game-rendered frames. '3x' in the parenthetical is explicitly frame generation, NOT3 NR passes. No NR pass count or full parameter set is supplied by this comment. Do not claim that PRE is compatible with our current RR path or silently deploy it.

Thread endpoint (`x/v2/reply/reply`, same type/oid, root312682909937) returned8 replies. Uploader rpid312699466849 recommends2x DLSS frame generation and calls it nearly lossless; this remains opinion, not independent latency/ghosting acceptance. A viewer with a single5090Dv2 asks how to configure the game; the fetched thread supplies no complete answer for that question.

Two uploader-attached4032x2268 PNGs were fetched and decoded, preserved as `author-312682909937-image-{0,1}.png`. Main inspected the fixed downscaled previews. Similar viewpoint, but NPC positions/animation differ. Author identifies the right/second image as enabled. Material contrast/cloth highlights/bamboo shading change; no same-frame fidelity metric or frame-rate proof inferred. No extra filter or diffusion workflow is established by these pictures.

## Other comments, kept separate

- 五言不会唱歌 BV1uGth6CEfh uploader rpid316339626480: '教程已发，看新视频'. Fetched its7-reply thread; no complete NR parameter recipe in the returned text.
- Viewer rpid312703251393 calls the appearance '晶莹剔透'. Useful confirmation that another viewer describes the same kind of appearance, NOT technical proof.
- Viewer rpid316080139664 objects to anime being made photoreal and predicts future game-specific adaptation. This is opinion/speculation, not a verified explanation of the network.
- Man牢布 BV1Xzt46BErZ viewer rpid316016910208 says '这个滤镜感觉副作用了'. That wording is a visual judgment, NOT evidence that an external filter was enabled.

## Coverage limits

Three targeted videos. The public first-page responses returned only3 ordinary top-level comments each plus uploader pins/reply previews, despite larger advertised counts. Pages2–4 returned code0 but empty replies and zero page counters. Do NOT interpret that as no more comments or claim complete coverage. Two targeted uploader threads were additionally fetched. `all-extracted.json` contains41 deduplicated comments/replies with IDs, roles, timestamps, source file, text and attachments. Raw responses and request URLs/statuses are preserved. No private cookies/login, signatures/challenge handling or attempts to unlock the missing pages.

# Main synthesis: public comments, no same-source requirement

2026-09-10. CPU/public research ONLY; game/GPU experiments remain paused and restored.

## Corrections based on new evidence

- Earlier absence of a ZZZ three-layer source is superseded: **稚qr柠, BV1hEbn6QEtc**, public author description says `纯实机  直播效果  叠三层 脸不黑`; tags include 无滤镜. This establishes an author's explicit three-layer claim, not a universal minimum or verified identical per-layer implementation. The associated tutorial/pin was also retrieved; no full three-layer settings recipe obtained.
- Do not dismiss the user's observed translucency/photoreal shift as an ordinary filter, and do not claim videos are diffusion-redrawn. Conversely, do not deny directly evidenced extra processing: **Kodakchrome, BV1SFto62EQ3**, uploader pin313043894673 supplies screenshots showing enabled **ReShade HDR[FakeHDR.fx]** and NR. Main independently viewed both original images. This proves the posted recipe includes FakeHDR, NOT NVIDIA RTX HDR/Freestyle and NOT that all clips use filters or that their entire change comes from FakeHDR.

## Specific recipes / workflow differences

### ZZZ

The newer three-layer author's description is distinct from the earlier 蘿蔔Grape demo in which a viewer said changes were small and the uploader replied `隔壁原也是这样，不知道为什么`. Earlier weak-effect examples must not be used to dismiss the newer three-layer method. No numeric per-layer controls, mode ordering, Genus or signed-binary hashes were obtained for the three-layer clip.

Separate author 乖受鱼, **BV1bobN66EmF**, describes a Magpie fork plus patch and says `解锁所有dlss5的选项从2改为10`. This is a claimed UI/control-range modification, NOT evidence of10NR passes or10x frame generation. Exact fields, selected values and signed-runtime limits unverified. No patch was downloaded or run; 'absolute safety' claim not endorsed.

### YanYun

Kodakchrome's posted NR panel: Preset Default, Style Natural; intensity/local tone/local structure2.00, **skin structure0.60**; automatic mask/UI correction unchecked. Skin0.60 is NOT HDR transfer0.60. Posted FakeHDR: Power0.705, Radius1 0.711, Radius2 0.688. Author's text additionally specifies game-native color/exposure controls (see nr-comments-yanyun/README.md) and clarifies that text is game settings, images are ReShade/NR settings. No NR layer count established from intensity2.00.

Other viewers under **BV199Yp6gEwL** explicitly report two-layer results with images (313386765473 /313530275473); these are their own reports, not the video uploader's recipe. Negative reproduction and performance reports retained: `我这么调了也没有视频的效果`, Natural oversharpening complaint, and a viewer unable to stack because even one pass was too slow. Not controlled reproductions.

### WuWa

**玄方研究院 BV1NhtW67EUq**, full description: RTX5090 for rendering+DLSS and a second5090Dv2 for Lossless Scaling fixed120 display; original video description lists max rendering/RT, SR Balanced, DLSS FG3x. Author calls original setup higher-latency/barely playable and reports large base-FPS loss. These are author reports, not independently measured.

Later uploader comment **312682909937**, Sept2 13:14:50 UTC+8 (video Aug31), reports **NR before SR**, references BV1zutj6EEbo, and Quality + DLSS FG2x + Lossless Scaling2x giving120. Do not backfill this later workflow as the original recording setup. Neither120 is proof of120 native frames; neitherFG3x norFG2x is an NR layer count. Our ended live trial was6K RR→POST5, materially different. Main viewed author's two attached images; animated NPCs differ, so no same-frame metric.

## Conclusions and gaps

Concrete multi-NR, different control-range and different input-stage recipes exist in public sources; there is no verified shared 'three passes with identical parameters plus NVIDIA filters' recipe. No evidence supports a universal three-layer threshold. Unknown shader/control/guide details remain unknown; don't infer signed model architecture or dependencies from appearance/comments. NR itself can change appearance while optional extra color processing also exists.

Sources, exact raw comments, uploader-mid verification, timestamps, partial-coverage and access limits:
- nr-comments-wuwa/README.md, all-extracted.json (41 deduplicated objects)
- nr-comments-zzz/README.md, COMMENTS.md (88 objects, limited target roots)
- nr-comments-yanyun/README.md, evidence.md, descriptions.md (129 objects)

Counts overlap between reviews and MUST NOT be summed as unique users or replications. Many public root pages exposed only3 roots; later pages returned empty shells; no complete-comment-area claim. No login/cookies/bypass, no private-group contact, no GPU or game activity.

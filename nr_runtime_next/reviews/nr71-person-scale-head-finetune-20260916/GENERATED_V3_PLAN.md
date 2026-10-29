# Adapter V3 generated full-body plan — frozen before NR captures

## Motivation

V2 passed isolated-face identities but improved two final full-body faces by only0.0239–0.0297EV. The missing supervision is not merely more icons: a realistic full body has a face only about9–12% of body height, so a 512px canvas cannot provide a same-composition >160px-face teacher. Ideogram4 therefore generated high-resolution source identities; a source-identical head/shoulder crop supplies the close teacher.

## Sources

- Ideogram4 NF4 revision `f664347839e0a87bc495f5c9483cc0014b8e344e`.
-24 frozen train prompts; two objective rejections (`ideo-train-004/005`) for face boxes extending outside the source frame;22 accepted.
- U2Net/rembg soft masks are local-research-only preprocessing; generated RGB/masks remain under Ideogram’s non-commercial terms.
- Six `reserved-final` prompts remain ungenerated until V3 recipe/checkpoint freeze.

## Exact NR capture matrix

For each accepted source, construct source-identical fixed-background cases:

- full body heights:256,320,384,448,480px;
- head/shoulder crop heights:160,224,288,448px;
- the 448px head crop is the safe teacher (expected face height >120px).

All derivatives of one generated source stay in training. Controls remain tone0.25, structure0.75, style0, skin-1, no auto mask, reset first frame.

## Target construction

For cases whose input-derived face height is40–90px, map each face pixel through the known source affine into that identity’s 448px head-teacher learned block70 RGB output. Target is `teacher_learned - original_learned`, multiplied by the transformed face mask. Outside that band target is zero. Background/person/non-face distillation samples remain zero.

## V3 training

Keep V2 architecture and optimization unchanged: zero-initialized `32 -> 32 SiLU -> 3`, AdamW, same learning rate/weight decay/batch/30 epochs, trained from zero. Combine frozen V2 data with generated cases; generated identities are grouped and cannot cross into validation/final.

## Final cohorts frozen now

- untouched Fluent: `fluent-013`, `fluent-018`, `fluent-019`, `fluent-022`;
- six already-frozen Ideogram `reserved-final` prompts, generated only after the V3 checkpoint is frozen.

Gates remain unchanged: every identity worst danger-band improvement >=0.05EV, close change <=0.03EV, outside-person/background RGB MAE <=1/255, all finite. No threshold adjustment or deployment after final scoring.

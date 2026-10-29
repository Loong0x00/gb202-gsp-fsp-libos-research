# Block48 representation repair V6 — draft, not frozen

Status: **design discussion only**. No training, final generation, threshold change, checkpoint promotion, package edit, DLL edit, manager edit, or game deployment is authorized by this document.

## Why block70 stops

V1--V5 established a repeatable Pareto conflict at the output head:

- enough correction amplitude can be produced;
- background preservation can be made very good;
- but an unseen danger-band full-body face or an unseen close face still crosses a preregistered gate.

V5 passed 9/11 identities but failed one danger identity at +0.04609 EV and one close identity at 0.03859 EV. No threshold is relaxed. The remaining problem is conditional representation, not raw RGB leverage.

## Why block48 before block38

Block38 is causally relevant: its train-derived direction moves brightness with the intended sign in 4/4 held-out categories, with median target contrast 0.011041 EV versus 0.000110 EV for the orthogonal control. It is also the 8x12, 1024-channel global bottleneck whose 64-pixel cell size matches the observed 46--76-pixel face-darkening resonance.

It is not the safest correction site:

- 8x12 localization is coarse;
- the existing intervention was spatially broad;
- approximately 0.1 channel-SD produced only about 0.011 EV median movement, so reaching 0.05 EV by simple scaling would require a much larger perturbation;
- global-token edits risk scene-wide semantic and exposure drift.

Block48 is the first checkpoint passing the strict max-checkpoint low-capacity screen. Its 32x36 spatial grid is approximately 16 pixels per visible cell, so a 40--90-pixel face occupies roughly 2.5--5.6 cells. It also already fuses the block38-derived decoder stream with the block22 skip and applies nonlinear FFN plus spatial attention. Therefore V6 starts at block48; block38 remains mechanistic evidence and an optional later context source, not the first correction site.

## Graph-preserving trainable scope

First candidate: a low-rank update to the existing block48 `attention.final_projection` matrix only.

- base tensor: `[256,256]` E4M3 weights;
- trainable form: `delta_W = A @ B`, rank selected from `{1,2,4}` on development/validation only;
- no new runtime tensor, gate, mask, coordinate, identity, scale input, control parameter, DLL call, or side network;
- after training, fold `delta_W` into the original matrix and quantize with the exact SM120 E4M3 RN-satfinite policy;
- all other 648 logical tensors and every graph edge remain frozen.

The projection input already contains local attention context. A low-rank weight update is therefore input-conditional despite adding no architecture. If this scope lacks capacity, it fails; V6 does not silently expand into block38, FFN, QKV, or a new adapter.

## Required pre-training causal pilot

Do not train immediately. First establish that a localized block48 intervention has useful leverage.

1. Passively capture the block48 pre-final-projection tensor and block48 output for existing development identities.
2. Derive a correction direction from training identities only.
3. Apply exact E4M3 perturbations at block48 to input-derived face cells for causal diagnosis only; masks are forbidden at runtime.
4. Run the untouched exact blocks49--70 suffix.
5. Require the declared sign in all development categories, useful danger-band movement, and an orthogonal matched-RMS control at least 10x smaller in median absolute EV.
6. Require untouched block48 suffix closure to reproduce every stored output byte-for-byte.

Failure of this pilot stops V6 before optimization.

## Representation target

If the pilot passes, train the low-rank projection update to make block48 produce the train-derived safe direction only when its own pre-projection features resemble danger-band face cells.

Supervision may use input-derived masks, known source affines, and same-identity scale labels during training. Runtime receives none of them. Target correction is zero for:

- background;
- outside-person pixels;
- person non-face pixels;
- faces below 40 pixels;
- faces above 90 pixels, including all close anchors;
- all explicit neutral controls.

The positive target is restricted to input-derived 40--90-pixel face cells and is based on train-only paired safe/danger evidence. No output-driven sample deletion is allowed.

## Data and identity policy

- Reuse existing accepted Fluent and Ideogram training identities and captures for development.
- All identities previously used in V1--V5 heldout/final scoring become development evidence for V6; none may be called final again.
- All transforms of a source identity remain in one split.
- A new final cohort must be frozen and generated only after the V6 recipe, rank, amplitude policy, exact quantized checkpoint, and scoring code are frozen.
- New final should contain at least 10 accepted identities spanning photoreal, game-like, anime/stylized, full-body pose, isolated face, varied skin/material/background, plus non-person controls.
- Ideogram assets remain local research evidence under their existing gated/non-commercial terms.

## Gates — proposed unchanged core plus stronger scale protection

Core gates remain:

- every final identity worst danger-band improvement `>= 0.05 EV`;
- close mean absolute change `<= 0.03 EV`;
- outside-person RGB MAE `<= 1/255`;
- background-only RGB MAE `<= 1/255`;
- every output finite.

Proposed additional V6 protections, to freeze before optimization:

- face-height `<40 px` mean absolute change `<= 0.03 EV`;
- face-height `>90 px and <160 px` mean absolute change `<= 0.03 EV`;
- no identity may pass only by brightening the entire person/background;
- exact base-weight/no-update execution must reproduce stored outputs byte-for-byte;
- exact quantized candidate, not an unquantized PyTorch surrogate, is the scored model.

## Evidence and promotion boundary

Training may use a differentiable surrogate only as an optimizer. Promotion requires:

1. folded and exact-quantized block48 weight bytes;
2. exact transparent block48 execution;
3. exact transparent blocks49--70 suffix scoring on every case;
4. all frozen final gates passing without post-final tuning;
5. no package, manager, DLL, game profile, or live deployment until that result exists.

V6 is rejected if any required identity fails. Near misses are reported, not rounded or waived.

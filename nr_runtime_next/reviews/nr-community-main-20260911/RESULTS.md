# Main acceptance: community chain differences, with fixed-input limits

Main independently reran197 static/CPU checks and64 artifact hashes for `nr-community-chain-diff-20260911`, then15 codec tests plus29 input pins/27 artifacts for `nr-codec-counterfactual-20260911`.

## Confirmed differences worth isolating

Pinned community implementations differ from frozen owned graphics code in HDR/color-domain selection, exposure/white-point treatment, per-channel versus luminance/peak compression, output ratio floor/guard, filtering order, and per-pass controls. The pinned multipass implementation defaults later LocalTone to0 rather than repeating the first pass's2. Different pinned forks also place NR/SR/RR differently. This does not identify the Douyin author's stack.

## Fixed A/B/raw-NR result

Actual old POST transfer≈.6, color1, white1; no new inference:
- P1 compositor outputs almost identical (RGB MAE≈2e-7), ratio guard never triggers.
- P5 MAE .004119/.005764, guard affects8.93%/11.15% pixels, predominantly reducing excessive brightening. This is NOT universal dark-scene brightening.
- Explicit counterfactual transfer1 increases P5 MAE to .01745/.02522 and protects some darker regions while suppressing over-bright ones. It is not a setting change.
- Encoder differences on this old A are sparse:99.5918% components unchanged, but rare HDR saturated values differ greatly. Changed encodings were NOT paired with old NR outputs to invent a full community result.

Owned CPU compositor first reproduced saved GPU D with MAE8.42e-5/8.86e-5; this validates the approximate mathematical comparator, not exact shader/format parity. The old scene has only6 source pixels below Y=.01 and is not the latest black PRE3 scene or ZZZ video.

These findings narrow causes rather than select a convenient explanation. The output compositor alone does not explain a whole-scene realism gap in this fixture. Next isolate per-pass tone and input/working-resolution contracts with original NR, keeping source and other settings fixed. A CPU/crossbuild-only private pass-profile candidate is being prepared at `nr-pass-profile-lab-prep-20260911`; no game/installation/profile change or GPU acceptance is implied.

Games already use original NR DLLs. CPU model reconstruction and its HFMA/RTZ corrections are a separate validation tool, not the cause of the installed runtime's visual difference.

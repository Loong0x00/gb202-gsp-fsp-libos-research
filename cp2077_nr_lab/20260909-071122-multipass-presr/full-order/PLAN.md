# Frozen implementation plan: actual single-NR order

Status: CPU implementation/handoff candidate. GPU execution is reserved for the
main owner.

## Superseding proof

The earlier cold-plan restrictions are superseded only by the actual gate in
`order-captures/20260909-124056-dual-sr-headless`: two distinct signed Feature-1
instances produced finite, byte-identical 6K RGBA16F output for IDs 257/258.
All critical fixes from that proven router remain: optional Create
`Output.Subrects`, accepted Create mask `0xff/0x1ff`, Evaluate float mask allowing
PreExposure, DWORD handle-ID matching rather than pointer matching, alias-ID
rejection, and the narrowly scoped same-open-native-list exception for original
signed-SR Create followed by Evaluate. That exception never authorizes Feature
18.

## Modules

1. `00-dlss-order-router.addon64`: verified signed-SR clone/pair router plus
   explicit order orchestration.
2. `01-dlss-order-pair-capture.addon64`: verified two-plane 6K recorder, extended
   additively to schema/ABI v2 actual-NR metadata.
3. `02-dlss-order-nr.addon64`: one shared signed-NR Vulkan bootstrap and exactly
   two role contexts/private maps/histories. Its only operational exports are
   private versioned Prepare/Evaluate/Release.

No source or binary outside `full-order/` belongs to this candidate.

## Frame state machine

- Process is inert unless the immutable launch latch is exactly
  `CP2077_ORDER_MODE=single-nr-order`.
- Signed SR_A/SR_B are created through the verified untouched opaque Create map.
- Router snapshots the complete eligible Evaluate contract and one frozen NR
  control block.
- Router calls Prepare(PRE) and Prepare(POST) before any NR evaluation.
- Each Feature-18 Create is build-only. API-18 reset/destroy invalidates an
  unexecuted create. Only an actual exact-list execute callback marks it ready.
- Until both are ready, SR_A and SR_B each run once from original Color; neither
  NR history advances.
- Once both are ready, every successful actual-order frame records:
  1. stage immutable active 4K Color;
  2. PRE codec -> exactly one NR_PRE evaluate -> HDR compose compact 4K;
  3. bind compact result and evaluate signed SR_A once to game output A;
  4. restore original Color/Output/color bases;
  5. bind original Color and owned output B; evaluate signed SR_B once;
  6. restore original bindings;
  7. snapshot actual 6K B, POST codec -> exactly one NR_POST evaluate using the
     same low-resolution guides -> HDR compose to B;
  8. verify counters/restoration and offer both 6K UAVs to capture.
- Failed/skipped role work never resumes. Auxiliary failure closes only the
  comparison; SR_A's original result/best output remains game-facing.
- Matched Present/fence completion gates NR_PRE, NR_POST, and SR_B release from
  the worker.

## Fixed contracts

- Input/output: 4096x2304 -> 6144x3456, signed Feature 1, quality 2,
  RGBA16F, source flags `0x4b`, clean NR flags `0x09`.
- PRE work source: compact 4K. POST work source: actual 6K; low-resolution
  motion/depth guides stay 4K-active. POST's proven create-only compatibility
  advertisement is recorded separately from its actual 6K work surface.
- Controls: Style/Preset/AutoMask 0, Intensity/Tone/Structure 1, Skin -1,
  HDR paper-white/transfer 1 and luminance-only color strength 0.
- Original game Evaluate map mutations are limited to guarded Color, Output,
  and Color subrect base X/Y. NR keys are written only to two private
  core-allocated maps using the distinct verified ABI slots.

## Recorder

- Schema `cp2077-single-nr-order/v2`, final 6K planes only.
- Production windows: 256..355, 576..675, 896..995. Smoke: one start, count 2.
- All successful actual frames between windows still run both SR and both NR
  exactly once; selection affects capture only.
- 300 pairs = 101,921,587,200 bytes; hard bounds 120 GiB, 300 pairs, 96 slots,
  32 GiB readback, 8 GiB host reserve, 360 s.
- Execute callback does not signal. Matching Present signals. Worker requires
  `GetCompletedValue >= fence` before Map/write.

## Acceptance sequence

1. `make clean check all` and verify package/source manifests and exports.
2. Main owner deploys all three exact basenames with signed files hash-guarded.
3. Run headless 6144x3456 RTX 5090 two-frame smoke.
4. Reject on any non-actual mode/count, duplicate/aliased handle/map, bootstrap
   count != 1, create count != 1 per role, role evaluate delta != 1, restoration
   failure, capture drop, nonfinite plane, or stale/missing terminal receipt.
5. Only after smoke acceptance, run the frozen three-window production plan.
6. Analyze same-frame final-output differences without claiming authoritative
   temporal warping (raw MV/depth planes are intentionally absent).

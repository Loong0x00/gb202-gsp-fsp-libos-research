# Cold dual signed-SR calibration gate

This package implements only the first GPU acceptance gate from `PLAN.md`:

- original signed Feature 1 handle **SR_A** writes the game's original output;
- a second, distinct handle **SR_B** is created by calling the captured original
  `NVSDK_NGX_D3D12_CreateFeature` again on the same command list, feature ID, and
  untouched opaque parameter object;
- every accepted game SR frame evaluates A once and then B once from the same
  original Color/jitter/guides; only A receives the game's progress callback;
- the reusable recorder captures two final 6144x3456 RGBA16F planes named
  `branch_a` (**SR original**) and `branch_b` (**SR shadow**).

There is no Feature-18/NR runtime initialization, PRE/POST service, NR lease,
RR/FG route, or claimed NR ordering in this build. Do not use these raw pairs as
NR-before-SR versus SR-before-NR evidence. `PLAN.md` is preserved unchanged.

## Exact add-on filenames

Deploy together, with these exact basenames (the router rejects generic or
renamed providers):

```text
00-dlss-order-router.addon64
01-dlss-order-pair-capture.addon64
```

Use the main owner's backup/restore harness, adapted to these two new owned
filenames. Do not hot-deploy, rename, mix with the old pre/post/multipass add-ons,
or install this package while the game/ReShade process is running.

## Offline-by-default environment

With `CP2077_ORDER_DUAL_SR_CALIBRATION` absent, the router is a direct pass-through
and capture is disabled. A calibration launch requires all of the following:

```bash
env \
  CP2077_ORDER_DUAL_SR_CALIBRATION=1 \
  'CP2077_ORDER_CAPTURE_DIR=Z:\cp2077-order-calibration-NEW-UNIQUE' \
  CP2077_ORDER_CAPTURE_START=256 \
  CP2077_ORDER_CAPTURE_COUNT=2 \
  <the-main-owner-existing-launch-command>
```

Requirements:

- `CP2077_ORDER_DUAL_SR_CALIBRATION` must be exactly `1` and is latched for the
  process lifetime.
- `CP2077_ORDER_CAPTURE_DIR` is mandatory, must be an absolute `Z:\...` path,
  and **must not already exist**. The worker creates it. Old capture roots and
  the deleted old raw payloads are never reused or recreated.
- `CP2077_ORDER_CAPTURE_START` defaults to `256` (zero-based successful dual-SR
  ordinal).
- `CP2077_ORDER_CAPTURE_COUNT` defaults to `2`; allowed range is `1..300`.
  Calibration is intentionally a modest two-frame smoke test—do not run 300
  pairs for this gate.

Before launch, configure the game for signed DLSS Super Resolution Feature 1 at
4096x2304 input to 6144x3456 output, quality `2`, HDR source flags `0x4b`. Disable
ray reconstruction, frame generation, and every NR/pre/post add-on. These values
are read and rejected on mismatch; the router does not synthesize them.

## Output/service filenames

A new root contains:

```text
job.json
capture-status.json
complete.json                 # only after all GPU/IO work drains successfully
failed.json                   # only after pending GPU/IO drains on failure
frames/frame-000000.json
frames/frame-000000-branch_a.bin
frames/frame-000000-branch_b.bin
...
```

Schema is `cp2077-order-pair/v1`, job mode is `dual-sr-calibration`, and metadata
labels are exactly A=`SR original`, B=`SR shadow`. Both raw planes are top-left,
tightly packed little-endian RGBA16F and exactly `169869312` bytes. Each pair is
`339738624` bytes.

The capture path is hard bounded to 120 GiB, 300 pairs, 32 GiB readback memory,
96 slots, an 8 GiB host-available reserve, and 360 seconds. API-18 execute is
used only as exact-list/pre-submit association; it never signals. A later
matching Present signals the queue. Only the worker calls `GetCompletedValue`,
then `Map` and disk I/O. Frame metadata sets
`gpu_fence_completed_before_map=true` only on that proven path.

## Gate acceptance

After `complete.json`, the GPU owner should verify:

1. both Create results are success, original/shadow handles differ, all three
   documented Create snapshot hashes match, and Create execute acknowledgement
   is true;
2. evaluate IDs/ordinals and original/shadow evaluate counters are strictly
   contiguous and exactly once each;
3. dimensions, quality, flags, output identities/formats, reset, jitter/MV
   scales, parameter restoration, and fence proof match the fixed contract;
4. every A/B pair is finite and byte-identical (`cmp`) unless a tolerance is
   explicitly declared before testing. This package declares **bit-exact** as
   the default acceptance criterion.

Any auxiliary fault permanently fails capture while the original game SR result
continues to be returned. The owned shadow handle is used only after exact
Create-list execute acknowledgement and is released only after a matching
original-handle lifecycle release plus a later-Present fence completion, from a
worker outside loader lock. If that proof is unavailable, it is retained until
process teardown rather than released unsafely.

## Build and CPU/static checks

```bash
make clean check all
(cd package/dual-sr-calibration && sha256sum -c SHA256SUMS)
sha256sum -c package/dual-sr-calibration/SOURCE_SHA256SUMS
```

No game or GPU process is started by the build/tests. Packaged artifacts are in
`package/dual-sr-calibration/` with binary and source SHA-256 manifests.

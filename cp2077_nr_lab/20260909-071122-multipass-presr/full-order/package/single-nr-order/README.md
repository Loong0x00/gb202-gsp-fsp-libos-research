# Actual single-NR order comparison

This subtree is the purpose-built successor to the verified dual signed-SR gate.
It reuses that gate's router, handle-ID pairing, parameter guard, submission
tracking, and bounded two-plane recorder, then adds one actual signed Feature-18
NR evaluation to each order branch:

- **A / `branch_a` / NR-before-SR:** immutable current compact 4096x2304 Color
  -> one NR history (`PRE`) -> HDR luminance-gain composition -> signed SR_A ->
  the game's original 6144x3456 output.
- **B / `branch_b` / SR-before-NR:** the same original Color, guides, jitter,
  exposure, reset, and source flags -> signed SR_B -> owned 6144x3456 output ->
  one separate NR history (`POST`) using that actual 6K work source plus the
  same low-resolution guides -> HDR composition back into B.

This is never a multipass-NR build. There are exactly two Feature-18 handles,
one per role, and one EvaluateFeature call per handle on every actual-order
frame. The two contexts have separate private core-allocated parameter maps,
resources, counters, reset state, and temporal history, while one service DLL
loads, patches, and calls `NVSDK_NGX_VULKAN_Init_Ext2` only once.

The implementation reuses the locally proven vkd3d/ReShade Vulkan interop and
HDR codec shims. It does **not** claim that the rest of the signed runtime state
is unmodified.

## Verified prerequisite

The cold gate in
`order-captures/20260909-124056-dual-sr-headless` passed for IDs 257/258:
all four 6144x3456 RGBA16F planes (679,477,248 bytes total) were finite and the
A/B planes were byte-identical. See its `CALIBRATION_VERIFICATION.json` and the
repository `verify_order_calibration.py`. This subtree does not relabel those
calibration planes as order evidence.

## Exact files and private ABI

Deploy these exact basenames together:

```text
00-dlss-order-router.addon64
01-dlss-order-pair-capture.addon64
02-dlss-order-nr.addon64
```

The service exports only:

```text
DLSS5_OrderNrPrepareV1
DLSS5_OrderNrEvaluateV1
DLSS5_OrderNrReleaseV1
```

The router rejects renamed providers, duplicate providers, missing exports,
ABI/version/sizeof mismatches, aliased NR handles, shared parameter maps, or a
runtime bootstrap count other than one. Generic `DLSS5_PreEvaluate*` and
`DLSS5_PostEvaluate` exports are compile-disabled.

## Offline default and exact opt-in

With `CP2077_ORDER_MODE` absent, every module is inert/pass-through and the NR
service rejects calls. No old calibration flag or marker can arm it. An actual
job requires:

```bash
env \
  CP2077_ORDER_MODE=single-nr-order \
  'CP2077_ORDER_CAPTURE_DIR=Z:\cp2077-single-nr-order-NEW-UNIQUE' \
  CP2077_ORDER_CAPTURE_STARTS=256,576,896 \
  CP2077_ORDER_CAPTURE_WINDOW_COUNT=100 \
  <main-owner-launch-command>
```

`CP2077_ORDER_MODE` is process-latched and must equal `single-nr-order` exactly.
The capture root is mandatory, absolute under `Z:\`, must not contain `..`, and
must not already exist.

The production default is three 100-frame source windows: `256..355`,
`576..675`, and `896..995` (300 pairs). A small pre-calibration smoke uses one
two-frame window without changing binaries:

```bash
CP2077_ORDER_CAPTURE_STARTS=256
CP2077_ORDER_CAPTURE_WINDOW_COUNT=2
```

At most three sorted, non-overlapping starts and 300 total pairs are accepted.
The fixed game contract is signed Feature 1, 4096x2304 -> 6144x3456, quality 2,
RGBA16F HDR source flags `0x4b`, RR off, FG off. The private NR maps rebuild
clean flags `HDR|DepthInverted = 0x09`; they never sanitize the game's opaque
parameter object.

Frozen NR/codec controls are Style 0, Preset 0, Intensity/Tone/Structure 1,
Skin -1, AutoMask off, paper-white scale 1, transfer strength 1, and HDR
luminance composition color strength 0. Exactly one immutable control snapshot
is created per game call and copied to both role requests.

## Readiness and failure behavior

Both roles are prepared before either role evaluates. Feature-18 Create records
only build work and returns `CREATE_PENDING`; unlike the proven original signed
SR same-open-list exception, it must receive an actual matching API-18 execute
acknowledgement before Evaluate. While either NR role is pending, both signed SR
instances run once from the unmodified source and neither NR history advances.
Actual order frames begin only when both roles are ready.

The game's Reset remains unchanged for both signed-SR calls and is copied to
both private NR maps; each NR history also resets on its first evaluation. Any
provider, bind, restore, create, evaluate, counter, or capture fault permanently
fails the auxiliary comparison. Histories never resume after one role faults.
The game-facing return remains SR_A's original signed result and the best
available game output remains in the original output resource; stale B is never
presented.

Owned NR_A, NR_B, and SR_B releases happen only from the retirement worker after
a later matching Present signal and fence completion. DllMain performs no NGX,
COM, wait, map, hash, or disk teardown work.

## Capture format and limits

A fresh root contains `job.json`, `capture-status.json`, frame metadata/two raw
planes, and exactly one drained `complete.json` or `failed.json`. Schema is
`cp2077-single-nr-order/v2`, job mode is `single-nr-order`. `branch_a` and
`branch_b` are tightly packed, top-left little-endian RGBA16F, each 169,869,312
bytes. Motion/depth are metadata-only guides; there are no raw MV/depth planes
and no authoritative temporal-warp claim.

The recorder retains the verified no-render-thread-I/O design: execute only
associates the exact list, matching Present signals, and only the worker calls
`GetCompletedValue` before `Map`, hashes/provenance, and disk I/O. Limits remain
300 pairs / 120 GiB capture, 96 readback slots / 32 GiB, 8 GiB host reserve, and
360 seconds. 300 raw pairs total 101,921,587,200 bytes (~94.92 GiB).

Per-frame metadata includes source/scene/evaluate IDs, QPC, reset, jitter,
exposure, guide bases/scales, source/clean flags, immutable controls, SR and NR
handles/private maps, role work and advertised dimensions, create/evaluate
counts, readiness flags, restoration proof, service and signed-runtime
provenance. `job.json` hashes the router, capture, NR service, signed SR, and
actual signed NR module.

## Build and CPU/static checks

These commands do not start a game or submit GPU work:

```bash
make clean check all
(cd package/single-nr-order && sha256sum -c SHA256SUMS)
sha256sum -c package/single-nr-order/SOURCE_SHA256SUMS
```

The package is `package/single-nr-order/`. Tests cover exact one-evaluate role
sequencing, immutable snapshots/restoration and failure paths, role/history/map
separation, shared bootstrap once, build-only create lifecycle/readiness,
metadata mode/counters, and recorder windows/byte budgets.

## Main-owner GPU handoff (not run by this worker)

Only the main owner deploys and launches. Confirm the 6144x3456 RTX 5090 virtual
output, then use the established backup/restore runner under a headless
Gamescope scope equivalent to:

```bash
Gamescope --backend headless -W 6144 -H 3456 -w 6144 -h 3456 -r 60 \
  --prefer-vk-device 10de:2b85 --force-windows-fullscreen -- \
  python <main-owned-runner> ...
```

No extra ReShade effect host is required. Never hot-deploy or mix these files
with old pre/post/multipass add-ons. The main owner must verify a two-frame smoke
before the full three-window run and preserve evidence before deleting raw
analysis payloads.

# Offline final-HDR NR/SR order analysis

This directory is a read-only analyzer for the actual full-order producer:

```text
A / NR-before-SR: compact source -> one NR -> signed SR_A -> 6K output
B / SR-before-NR: compact source -> signed SR_B -> one NR at actual 6K work source
```

Actual-order input must use the native producer schema
`cp2077-single-nr-order/v2` and `job_mode: single-nr-order`, as written by
`full-order/capture/order_pair_capture.cpp`. The analyzer does **not** adapt V1
actual-order aliases or accept old metadata merely because it was renamed. The
old `cp2077-order-pair/v1` shape remains supported only with `--calibration` for
explicit dual-SR, zero-NR, bit-exact calibration evidence.

Each frame has exactly two top-left, tightly packed little-endian RGBA16F
planes:

```text
frames/frame-NNNNNN-branch_a.bin
frames/frame-NNNNNN-branch_b.bin
6144x3456 x 4 x 2 bytes = 169869312 bytes per plane
```

Synthetic fixture output is test evidence only. It is never reported as a game
quality result.

## Native V2 integrity adapter

The validator reads the producer's exact nesting and keys:

- `signed_sr.handle_ids.A/B`, `handles.A/B`, create/evaluate results, and
  create/evaluate/success counters;
- `nr.pre` and `nr.post` model handles, private `parameters` maps,
  prepare/create/evaluate counters, status, result flags, work source, guide
  dimensions, and role-local `reset`;
- NR shared bootstrap count 1, aggregate create count 2, and aggregate evaluate
  count equal to the role sum;
- `lifecycle` signed-SR create acknowledgement/same-list proof, Feature-18 NR
  create acknowledgement, and signed-SR parameter restoration;
- `control_snapshot_id`, `source_scene_id`, exact frozen effective `controls`,
  same-source identities, resource descriptions, output-state round trip, and
  post-Present fence proof;
- job schedule/windows, exact domain/plane contract, signed SR, signed NR and NR
  service hashes/RVAs, plus `capture-status.json` and the terminal receipt.

Signed-SR A/B handle IDs are compared only within their NVSDK handle-ID
namespace. They are not compared numerically with model pointers. The four
signed-SR/NR **model handles** must be independent, and the two private NR
parameter maps must be distinct.

The producer exposes no numerical generation counter. The analyzer therefore
records `generation_counter.available=false`; it does not invent generation 0
or 1. Continuity is instead backed by a derived SHA-256 fingerprint over the
stable four model handles and two private NR maps. Effective control values are
fingerprinted separately. Per-frame snapshot IDs must be unique because the
producer snapshot hash includes the source scene/frame identity; snapshot IDs
are not incorrectly required to stay constant.

NR evaluate counts must agree between PRE/POST and equal both the NR logical
`evaluate_id` and `successful_pair_ordinal + 1`. `source_scene_id` is treated as
the actual game signed-SR frame identity, not renamed to the NR logical ID.
Stable nonnegative source-scene/NR, source-scene/signed-SR, and
prepare/evaluate offsets allow the producer's build-only Feature-18 Create
warmup without pretending that the warmup ran an NR evaluate.

`capture_window_index` maps 0/1/2 to early/middle/late. Capture indexes and
indexes within each window must be consecutive. Positive ordinal gaps are
allowed only at planned window boundaries and remain recorded in the report.

Unsupported V1-generic fields in a V2 frame, missing fields, inconsistent
counts/identities/controls, wrong formats, malformed status/terminal data, and
unreferenced payloads are retained as findings and make the report partial.

## Interpretation limits

- A and B are endpoints, not ground truth. Metrics are difference/similarity
  measurements. High similarity is not improvement; no quality winner is
  selected.
- Full-resolution HDR metrics include RGB MAE/RMSE/max/changed-pixel fraction,
  positive-luminance mean ratio B/A, per-channel values, and separate alpha
  differences. Optional `--quantiles` uses a bounded deterministic histogram.
- Display metrics apply the same fixed mapping to both planes:
  `max(RGB * exposure, 0)`, Reinhard `x/(1+x)`, sRGB OETF, then integer area
  reduction to 1024x576. Display SSIM/PSNR/MAE describe only that analysis map.
- Planes are branch working HDR before the game's final display tone map/HUD;
  they are not screenshots.
- The producer explicitly captures no raw motion/depth planes. Therefore no
  authoritative temporal, motion-warp, disocclusion, or flicker metric is
  computed. LPIPS is also not measured and no weights are downloaded.
- Debug-overlay state is a runner responsibility and is not inferred from raw
  pixels.

## Streaming and bounded resources

Each worker opens payloads read-only and performs one full row-chunk pass for
layout/finite validation, SHA-256, and metrics. It returns metrics/hashes, not
raw images. The process pool is bounded to 1..6 workers and uses bounded
submission on Python 3.14.

Checksums are not a second full read. After metric selection, at most six frames
may be reread solely to produce reduced previews; maximum-difference exemplars
are marked selection-biased. No raw copy is written. Orphan in-root binaries are
streamed and hashed once without metrics. Path-escaping payloads are reported
and not followed.

The output directory must be new and outside `capture/frames`. Capture metadata
and payloads are never modified or deleted. Do not run the analyzer against an
active capture; wait for `complete.json`.

## Commands

Check dependencies without installing anything:

```bash
python3 order-analysis/analyze_order.py --check-dependencies
```

Analyze the planned 300-frame, three-window capture:

```bash
python3 order-analysis/analyze_order.py /path/to/capture-root \
  --output /path/to/new-order-report --workers 6 \
  --expected-frames 300 --expected-per-segment 100
```

Analyze a two-frame native V2 smoke while disabling per-segment count assertions:

```bash
python3 order-analysis/analyze_order.py /path/to/single-nr-order-smoke \
  --output /path/to/new-smoke-report --workers 2 \
  --expected-frames 2 --expected-per-segment 0
```

Validate old dual-SR calibration as strict NR0 bit-exact RGBA only:

```bash
python3 order-analysis/analyze_order.py /path/to/dual-sr-calibration \
  --output /path/to/new-calibration-report --calibration \
  --expected-frames 2 --expected-per-segment 0 --no-previews
```

Small producer-shaped CPU fixtures may explicitly replace dimensions:

```bash
python3 order-analysis/analyze_order.py FIXTURE \
  --output NEW_REPORT --workers 1 \
  --expected-frames 0 --expected-per-segment 0 \
  --allow-nonstandard-dimensions 12x8 --analysis-size 6x4 --no-previews
```

A complete report exits 0; a retained integrity/continuity finding exits 2; a
CLI/runtime failure exits 1.

## Outputs

- `per-frame.csv` — A/B metric rows, IDs, source scene, snapshot, and status.
- `payload-audit.csv` — path, size, SHA-256, finite/channel stats, and findings.
- `frame-audit.csv` — native bindings, derived identity/control fingerprints,
  explicit generation-unavailable state, and metadata findings.
- `payload-hash-manifest.json` / `PAYLOAD_SHA256SUMS` — hashes from the metric
  pass and complete discovered-file coverage.
- `summary-global.json` / `summary-{early,middle,late}.json` — integrity,
  continuity, warmup offsets, and numeric summaries.
- `previews/` / `contact-sheet.jpg` — at most six bounded reduced exemplars.
- `manifest.json` — size and SHA-256 for report artifacts.

## CPU verification

```bash
make -C order-analysis check
```

Fixtures cover valid native V2 data; paired-count, NR-identity, controls, format,
and consecutive-ID failures; short-payload hashing; serial/parallel metric and
hash equivalence; rejection of V1 relabeling; and explicit V1 NR0 calibration.
No test starts a game or GPU workload.

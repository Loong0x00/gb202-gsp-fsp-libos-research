# Paired pre-SR capture analysis

This directory analyzes the frozen `cp2077-presr-paired/v1` payload contract in
`../CAPTURE_SCHEMA.md`. It does not capture frames and does not modify or copy
capture payloads.

## Important interpretation limits

- `original` is a same-source-frame **reference, not ground truth**. All reported
  MAE/RMSE/SSIM/PSNR/LPIPS values describe change or similarity; they are not
  labelled as NR improvement or degradation.
- Full-resolution direct metrics operate on scene-linear HDR RGB. Absolute-error
  quantiles use a documented bounded 4096-bin log histogram. Positive-luminance
  exposure ratios include a mean ratio/EV delta and bounded per-pixel ratio
  quantiles.
- Display-domain images use one fixed analysis mapping for every frame and
  variant: `max(sceneRGB * exposure, 0)`, per-channel Reinhard `x/(1+x)`, then
  the sRGB OETF. The default exposure is 1.0. This mapping is **not Cyberpunk
  2077's final tone mapper**. SSIM and PSNR use the declared common area-reduced
  resolution (1024 pixels wide by default), while HDR MAE/RMSE are direct at
  full source resolution.
- Temporal numbers are warp-instability measurements, not quality scores.
  Motion, lighting, transparency, exposure, animated materials, and bad motion
  vectors can all affect them. Both raw-image warp instability and instability
  of each enhancement residual (`nr1-original`, `nr3-original`, `nr3-nr1`) are
  reported.
- The depth rejection mask is heuristic. Without camera matrices it is not an
  authoritative disocclusion/occlusion mask. It rejects non-finite samples,
  out-of-bounds warps, likely sky, depth edges, and current/warped-depth
  mismatches using thresholds recorded in each report.

## Resource behavior

By default the analyzer reads one source frame at a time. Optional `--workers 6`
uses a bounded, ordered CPU process pool (1–8 workers), with at most the worker
count of queued results. Each child streams full-resolution planes in row chunks;
only reduced images and metric records return to the parent. Temporal comparisons
remain in exact source order in the parent. Parallel mode requires LPIPS off and
Python 3.14 (`Executor.map(buffersize=...)`).

Full-resolution planes are read in bounded row chunks (32 rows by default); SHA-256, byte/layout checks,
finite/range/alpha statistics, direct pair differences, and reduced working
images are produced during that streaming read. Only reduced current and
previous frames are retained for temporal analysis. It never loads all 300
frames into RAM.

Visuals are selected after numeric analysis and re-read for at most 12 source
frames. They are reduced exemplar composites, fixed-scale difference heatmaps,
and one modest JPEG contact sheet. The approximately 95 GiB raw corpus is never
automatically copied.

Missing, short, malformed, hash-mismatched, or non-finite payloads remain in the
audits as invalid/partial. They are not silently dropped. A partial report exits
with status 2.

## Run after Main finishes capture

Do not run analysis concurrently with capture. First check the local environment
without changing it:

```bash
python analysis/analyze_capture.py --check-dependencies
```

Required: NumPy, OpenCV (`cv2`), scikit-image, and Pillow. SciPy is only reported
for environment provenance and is not required. The command never installs or
upgrades packages.

After `complete.json` (or a terminal `failed.json` for an explicitly partial
report) exists:

```bash
python analysis/analyze_capture.py /path/to/capture-root \
  --output /path/to/analysis-report --workers 6
```

Production defaults assert 300 frames, 100 each in `early`, `middle`, and
`late`, exact 4096x2304 top-left layouts, and a terminal marker. `failed.json`,
missing payloads, continuity gaps, or integrity failures still produce CSV/JSON
records but return exit code 2. Development fixtures can disable production
count/dimension assertions with:

```bash
python analysis/analyze_capture.py FIXTURE --output REPORT \
  --expected-frames 0 --expected-per-segment 0 \
  --allow-nonstandard-dimensions --no-visuals
```

Outputs:

- `per-frame.csv`: three same-frame comparison rows (`0vs1`, `0vs3`, `1vs3`)
  per metadata frame, including unavailable/partial rows.
- `per-adjacent-pair.csv`: every neighboring capture-record candidate, including
  explicit exclusion reasons and measured raw/residual warp instability.
- `payload-audit.csv`: bytes, SHA-256, finite/range/alpha checks for every plane.
- `frame-audit.csv`: metadata, NGX flag decoding, and frame status.
- `summary-global.json` and `summary-{early,middle,late}.json`.
- `manifest.json`, up to 12 `exemplars/*.png`, and `contact-sheet.jpg`.

The report output should be outside `frames/`. Existing payloads are opened
read-only.

## Motion and jitter assumptions

The temporal implementation samples the previous frame from the current pixel:

```text
previous_coord = current_coord
               + sign * (current_raw_motion_xy * captured_mv_scale_xy)
               + configured_jitter_delta
```

The displacement is then converted from full-resolution pixels to the common
metric resolution. The default `--mv-sign plus` is the explicit backward
(current-to-previous) convention; `--mv-sign minus` is available for a known
motion test. This direction/sign is an analysis assumption, not inferred from
image agreement.

`MVJittered` is decoded from official NGX bit 2, but that bit alone does not
establish the coordinate/sign convention for adding a jitter delta. No delta is
applied by default. Test known motion with `--jitter-adjust none`,
`previous-minus-current`, and `current-minus-previous`; the selected option and
actual delta are recorded. Do not choose an option merely because it lowers an
error on unknown game content.

See [`NGX_FLAGS.md`](NGX_FLAGS.md) for the header verification. In particular,
`0x4b` does **not** set bit 2 and must not be guessed as `MVJittered`.

## Optional LPIPS

LPIPS is off by default. `--lpips` uses CPU only and reports a number only when:

1. the `lpips` and `torch` packages are already installed,
2. the package's trained Alex linear weights exist locally, and
3. the trained AlexNet backbone is already in the local Torch checkpoint cache.

No weight download and no random/untrained substitute is allowed. Otherwise
`value` remains null, `measured` is false, and a skip reason is written. This
machine currently has the core metric packages but should always be rechecked
before the real run.

## Tests

Seven synthetic tests cover serial/parallel metric and audit equivalence,
exact identity, a known pixel change, fixed HDR mapping,
a shifted frame with scaled backward motion, reset/source-ID-gap exclusion,
`0x4b` bit decoding, and a short payload remaining visible as partial:

```bash
python -m unittest discover -s analysis/tests -v
```

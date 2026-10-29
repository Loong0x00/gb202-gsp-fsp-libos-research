# Agreed paired-capture v1 schema and budget

Explicit user request: a few hundred frames in Cyberpunk benchmark, separated
into beginning/middle/end. Main selects300 source frames:100 per window.
No routine/automatic captures outside an explicitly armed capture test process.

## Domain and stages

Actual source/working resolution4096x2304; final game output6144x3456.
Capture BEFORE original signedSR. Variants represent the same original source
frame after0/1/3 NR passes, with the same persistent per-layer histories from the
three-pass run. They are not independent6K SR outputs, and not counterfactual
full-game histories. Capture actual GPU-composed scene-linear HDR at every
variant, never compare raw neural sRGB-like proxies against linear HDR.

Capture5 planes per source frame:
- `original`: tightly packed little-endianRGBA16F,4channels, current immutable HDR.
- `nr1`: RGBA16F,4channels, one-pass raw result composed using exactly the existing
  GPU HDR codec against immutable original/base. Preserve raw pass1 before A is
  overwritten by pass3; never recompute it with a different/reset history.
- `nr3`: RGBA16F,4channels, actual final composed3-pass HDR supplied to signedSR.
- `motion`: current game guide, expectedRGBA16F4channels (XY used); preserve raw
  values and record actual source format/scale/subrect. Reject unknown formats.
- `depth`: current game guideR32F1channel; typeless DXGI39 must be copied/read as
  the existing32bit depth float bits, not converted toUNORM. Reject unsupported
  partial depth/stencil copies/layouts.

All images have matching active dimensions and D3D top-left orientation.
Expected payload324MiB/source frame;300 frames94.922GiB. Hard total capture
budget120GiB; hard300frames; max360s after first eligible source frame. Up to96 readback slots,
max32GiB host-readback allocations, with dynamic allocation and at least8GiB
available-memory reserve. No render-thread disk/hash/write or GPU fence waiting.
Map ONLY after a fence that actually follows this command-list submission.
Use proven existing raw_capture_d3d12.cpp execution/present tracking principles.
If buffers/IO can't sustain continuity, record drops/gaps/partial completion;
never relabel gapped frames as consecutive. Fail closed for capture only.

## Scheduling

Default windows by successful three-pass source-frame ordinal:
`early`:256..355, `middle`:576..675, `late`:896..995 (zero/one indexing must be
explicit in job metadata). These are source-frame windows spanning the known
benchmark route, not wall-clock screenshots. Preserve warmup/history frames,
and document exact chosen starts. Source calls include startup rendering; after
the run also locate each window against the benchmark summary/frame-time timeline
using timestamps. Do not equate a source-call ordinal to a benchmark frame index.
Main may adjust starts from observed actual benchmark progression; do not silently
start three new histories per segment. NR remains active across the whole run.

## Files

Root contains`job.json`, per-frame files under`frames/`, and atomic
`capture-status.json`. Terminal`complete.json` only after all files are written
and all300 frames succeeded;`failed.json`/status records exact partial counts.

Per frame: `frame-000000.json` and planes named
`frame-000000-original.bin`, `-nr1.bin`, `-nr3.bin`, `-motion.bin`, `-depth.bin`.
Metadata JSON:
```
{
 "schema":"cp2077-presr-paired/v1",
 "capture_index":0,"segment":"early","segment_index":0,
 "source_evaluate_id":123,"service_call":123,"source_frame":100,
 "width":4096,"height":2304,"output_width":6144,"output_height":3456,
 "orientation":"top-left",
 "qpc":0,"qpc_frequency":10000000,"unix_ns":0,
 "reset":false,"pass_reset":[false,false,false],
 "feature_generation":1,"feature_flags":75,"nr_flags":9,
 "jitter_x":0.0,"jitter_y":0.0,"mv_scale_x":4096.0,"mv_scale_y":2304.0,
 "depth_inverted":true,"mv_jittered":false,
 "pre_exposure":1.0,"pre_exposure_available":true,
 "gpu_fence_completed_before_map":true,
 "color_domain":"scene-linear HDR before signedSR; exact GPU composition",
 "planes":{
  "original":{"file":"frame-000000-original.bin","dtype":"<f2","channels":4,"bytes":75497472},
  "nr1":{"file":"frame-000000-nr1.bin","dtype":"<f2","channels":4,"bytes":75497472},
  "nr3":{"file":"frame-000000-nr3.bin","dtype":"<f2","channels":4,"bytes":75497472},
  "motion":{"file":"frame-000000-motion.bin","dtype":"<f2","channels":4,"bytes":75497472},
  "depth":{"file":"frame-000000-depth.bin","dtype":"<f4","channels":1,"bytes":37748736}
 }
}
```
Record actual effective control values (intensity/tone/structure/skin/style,
AutoMask, paper-white/transfer/color strengths) and artifact hashes at job/run
level. Unknown metadata uses null/availability=false, never fabricated defaults
claimed measured. Jitter/MV flag meanings must be verified against NGX headers.
SHA256 may be computed in a post-capture streaming pass rather than delaying
writer throughput. No encoded-PNG refeed. Analysis reads these exact planes.

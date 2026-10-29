# CP2077 PRE-SR3 paired capture

This is a purpose-specific capture build derived from the verified
`../presr-multipass` source. It does not replace that production candidate and
is **off by default**. No marker auto-arms it.

## Build artifacts

```bash
make clean check package
sha256sum -c copies/paired-capture/SHA256SUMS \
  --ignore-missing
```

Deploy the matched pair together (deployment and game control belong to the
main worker):

- `copies/paired-capture/00-dlss-ngx-router.addon64`
- `copies/paired-capture/01-dlss5-presr-service.addon64`
- `copies/paired-capture/SHA256SUMS`
- `copies/paired-capture/SOURCE_SHA256SUMS`

A successful cross-compile/source test does not prove that GPU capture works.
Do a short smoke before the 300-frame run.

## Process environment

Required, set before the cold game process starts:

```text
DLSS5_PRE_PASSES=3
DLSS5_PAIRED_CAPTURE=1
DLSS5_PAIRED_CAPTURE_DIR=Z:\absolute\new-or-empty-capture-root
```

`DLSS5_PAIRED_CAPTURE` must be exactly `1`. The output path must be an absolute
Wine `Z:\` path and the root must contain neither an old `job.json` nor terminal
metadata; an existing `frames` directory must be empty. Any unsafe capture
configuration disables/fails capture only, not PRE-SR NR or the game.

Optional bounded plan overrides:

```text
DLSS5_PAIRED_CAPTURE_STARTS=256,576,896
DLSS5_PAIRED_CAPTURE_COUNT=100
```

`STARTS` accepts one to three strictly increasing, non-overlapping successful
three-pass ordinals. `COUNT` is per listed start and is limited to `1..100`;
the total remains capped at 300. Defaults are three 100-frame windows:
`256..355`, `576..675`, and `896..995`.

Suggested two-fileset smoke (same five-plane schema):

```text
DLSS5_PAIRED_CAPTURE_STARTS=8
DLSS5_PAIRED_CAPTURE_COUNT=2
```

Starting smoke at 8 leaves worker-side path/disk/hash/job initialization time;
the render thread never waits for it. An initialization that is not ready by a
selected ordinal is reported as a dropped/failed capture, not shifted.

The existing router PRE-SR enablement still has to select NR mode for the whole
run. Do not turn NR off between windows: each of the three Feature-18 handles
owns one process-persistent history.

## Indexing and pairing

The source ordinal is explicitly **zero-based** and increments only after all
three Feature-18 evaluations and `EndVkCommandBufferInterop` succeed. Creation,
build-only, fallback, and failed calls consume no ordinal. It is a service
source-call timeline, not the benchmark's frame index. `source_evaluate_id`,
`service_call`, QPC, Unix time, prior captured IDs, and detected ordinal gaps
are recorded so the main worker can align windows to benchmark/frame-time logs.

On selected source frames the GPU:

1. keeps the compact immutable 4096x2304 original;
2. copies raw pass-1 A to a capture-owned GPU texture before pass 3 overwrites A;
3. completes passes 2 and 3 normally;
4. performs the game's unchanged single NR3 HDR composition;
5. after all pass recording, runs the exact same HDR codec/constants once on
   preserved pass 1 into a separate NR1 HDR comparison texture;
6. ends Vulkan interop, then records five D3D12 readback copies while restoring
   every source state.

The diagnostic path never binds Color and never calls Create/Evaluate or resets
a history. These are same-source 4K working-domain planes, not paired 6K signed
SR outputs.

## Output and completion

The root contains `job.json`, atomic `capture-status.json`, and `frames/`.
Each fileset is:

```text
frame-NNNNNN.json
frame-NNNNNN-original.bin
frame-NNNNNN-nr1.bin
frame-NNNNNN-nr3.bin
frame-NNNNNN-motion.bin
frame-NNNNNN-depth.bin
```

All planes are top-left, little-endian, and tightly packed at 4096x2304:
RGBA16F original/NR1/NR3/motion and raw R32 typeless depth bits. A fileset is
324 MiB (339,738,624 bytes). The full 300-frame payload is 101,921,587,200 bytes
(94.922 GiB).

The readback pool grows only as needed, to at most 96 slots and 32 GiB, while
preserving at least 8 GiB reported available physical memory. Capture is capped
at 300 frames, 120 GiB, and 360 seconds after the first eligible source frame.
Disk capacity is checked before `job.json` is committed.

ReShade API 18's execute callback occurs before native submission, so it only
associates the exact native list with its queue. It never signals. A matching
later Present enqueues the fence signal. Only the writer thread checks
`GetCompletedValue`, maps, and directly writes tight planes; there is no
render-thread map, wait, disk write, or hash and no duplicate full-plane CPU
scratch copy.

`complete.json` appears only after every requested fileset is written and no GPU
or I/O item remains. For the default plan it additionally records
`production_300_filesets_complete:true`. A smoke override can complete its
smaller declared plan but records that production flag as false. Slot pressure,
format/layout mismatch, timeout, disk/write failure, or command-list loss is
reported in heartbeat status and `failed.json`; the failure marker includes any
still-pending count and is atomically replaced after a normal drain. Selected
ordinals are never relabeled. Main must wait for `complete.json`; on
`failed.json`, wait for `pending_gpu_or_io:0` in heartbeat/failure metadata when
the device is still healthy before stopping the game. Otherwise process death
can truncate the writer.

`job.json` hashes the loaded service, matched router, and signed
`nvngx_dlssnr.dll` on the worker, and records the actual Create/Evaluate export
RVAs plus upstream commits and plan parameters. Plane SHA256 is intentionally a
post-capture streaming step.

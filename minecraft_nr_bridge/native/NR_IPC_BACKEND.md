# Persistent Wine Feature18 CUDA-IPC backend

`nr_ipc_backend.exe` is a persistent Windows worker for the frozen
`mcnr_protocol.h` version 1 control page. It maps only the 4096-byte CPU control
file; all four image planes remain in CUDA device memory.

## Build

```bash
cd /home/user/rt_5090_project/minecraft_nr_bridge
native/build_backend.sh
```

The build uses MinGW C++20 (`std::atomic_ref`) and statically links the MinGW
C/C++/thread runtimes. Output: `native/nr_ipc_backend.exe`.

## Launch

The Linux producer must first create and initialize the control file and export
four distinct 64-byte CUDA IPC handles in this order: color, depth, motion,
output.

```bash
tools/run_nr_backend.sh /absolute/path/to/control.mmap
# Pre-create the expensive Feature18 model before READY:
tools/run_nr_backend.sh /absolute/path/to/control.mmap --nr
```

The exact direct Wine form used by the launcher is equivalent to:

```bash
WINEPREFIX=/home/user/rt_5090_project/dlss5_model_dump/nativecuda-wineprefix \
WINEDEBUG=-all WINEDLLOVERRIDES='nvcuda=b;winedbg.exe=d' \
/usr/bin/wine \
  'Z:\home\user\rt_5090_project\minecraft_nr_bridge\native\nr_ipc_backend.exe' \
  'Z:\absolute\path\to\control.mmap' \
  'Z:\home\user\rt_5090_project\dlss5_model_dump\nvngx_dlssnr.dll' [--nr]
```

The launcher SHA-256-locks the DLL to
`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`,
uses the already-proven isolated Wine prefix, and defaults to a bounded six-hour
foreground lifetime (`NR_BACKEND_MAX_SECONDS` overrides it). It does not call
`wineserver`, detach, inspect a game, or signal unrelated processes.

## Data and completion contract

- Padded allocations/arrays and the Feature18 evaluation extent are
  `width * height`: color/output RGBA32F, depth R32F, and motion RG32F. The
  producer replicates the color/depth border into padding and crops the top-left
  `active_width * active_height` only after completion; active dimensions must
  not exceed padded dimensions.
- Color is the current frame RGB/255 approximation with alpha; it is not an
  HDR-ready transfer. Depth is the un-inverted GL window value in `[0,1]`.
  Motion is backward current-to-previous in full-resolution top-left pixels;
  therefore Feature18 MV scales are exactly 1.
- `mode=COPY` performs one CUDA device-to-device color-to-output copy and does
  not create Feature18 if it has not yet been needed.
- `mode=NR` copies imported color/depth/motion device allocations to persistent
  CUDA arrays, evaluates one persistent Feature18 handle, synchronizes the CUDA
  context, copies the output array directly to the imported output allocation,
  and synchronizes again.
- Dynamic parameters use the proven keys `DLSSNR.Reset`, `DLSSNR.Intensity`,
  `DLSSNR.LocalToneStrength`, `DLSSNR.LocalStructureStrength`,
  `DLSSNR.SkinStructureStrength`, `DLSSNR.Style`, and
  `DLSSNR.UseAutoMask`. The producer must write every field before its release
  update of `request_seq`; zero is a valid exact value and is not replaced by a
  backend default.
- `completed_seq` is release-published with `result=1` only after all output GPU
  work completes; only then is state returned to `READY`. A failed CUDA/NGX
  call sets `FAILED` with an error and never fabricates completion. Actual
  Feature18 calls increment `evaluations`; COPY does not.
- `gpu_ms` is always `-1`: the known single-stream CUDA event interval is not
  proven to cover all internal Feature18 execution.
- On nonzero `shutdown`, imported pointers are closed only after queued GPU use,
  NGX release/shutdown, and array destruction. `STOPPED` is then published.

## Verification status

The executable builds and its static-runtime dependency check passes. The local
Wine nvcuda bridge exports `cuIpcOpenMemHandle`, `cuIpcOpenMemHandle_v2`, and
`cuIpcCloseMemHandle`, and the backend resolves the unsuffixed ABI and fails
closed if it is absent. A genuine producer-owned IPC smoke test has **not** yet
been run, so this document does not claim Create/Evaluate/output interoperability
evidence. Use a small COPY request first, then one reset NR request; do not begin
a high-resolution stress run until actual output has been checked by the Linux
producer.

## Subsequent main-agent integration verification (2026-09-09)

The worker-only unverified status above is historical. Main subsequently ran
real Java/JNI/GL3.3/CUDA/Wine COPY and Feature18 tests at1080p and6144x3382
(active)/6144x3392(padded), plus a genuine post-publication timeout/late-discard
test. All passed. See ../README.md and benchmark_logs/mc-java-cuda-ipc-6k-final-20260909-0451.
Native defaults are now published explicitly (tone1/structure1/skin-1/style0/AutoMask0),
and COPY preserves the pending NR reset. Application launch uses direct exec
Wine, not the standalone timeout wrapper, to make importer process lifetime
observable by Java. The running game has not yet received0.2.0.

# Wuthering Waves native-RR temporal Feature18 replay

## Persisted source context

The evidence report at
`/home/user/rt_5090_project/benchmark_logs/wuwa-native-replay-r-cinematic-20260903-122359/README.md`
describes a complete 150-frame source capture. Its global frame IDs are
6912..7061 with no gap. Raw frames 9..97 cover the R cinematic; the previously
bad poses map approximately to raw25/raw27, with raw26/raw28 adjacent. The
source native-RR images were visually reviewed and contain no structured
mosaic.

The immutable input directory is
`/home/user/rt_5090_project/capture_archives/wuwa-native-replay-final-20260904-0104/raw-captures/20260903-122359-540-p320`.
Its manifest has 150 frame records and one clean session record: 150/150
complete, no abandoned/write-failed frames. Each frame has a 6144x3456
R11G11B10 native-RR image, 3564x2005 RG16F motion, and 3564x2005 R32F depth.
Resets occur at raw9 and raw68. Clean Feature18 flags are 1. The replay scripts
never write, move, or delete anything in this directory.

The CUDA parameter ABI comes from `ngx_cuda_pe_bare_probe.cpp`: private float
reads use vtable slot 14; CUDA image parameters occupy the ULL slot and contain
a pointer to a `CUtexObject`; the initialized device is `{CUcontext, CUstream}`.
The exact runtime is `nvngx_dlssnr.dll`, SHA-256
`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.
The executable checks that hash before loading the DLL. It then checks the
original bytes `ff 15 8e 45 09 00` at RVA `0x17e94` before applying the verified
Blackwell architecture-query compatibility patch. Any mismatch is fatal.

The post-SR contract in `dlss5_vk_bridge.cpp` creates native Feature18 at high
resolution using a create-only 4096x2304 / scaling-ratio 0.5 / upscaling=true
compatibility rewrite, then restores 3564x2005 / ratio 1 / upscaling=false for
evaluation. Color/output remain 6144x3456. Motion and depth retain the captured
subrect bases. The clean flag word contains HDR bit 0 (and depth inversion only
when requested); this capture therefore uses flag 1 and non-inverted depth.

`codec_encode.comp` clamps negative R11G11B10 source RGB, applies its HDR
shoulder and sRGB encoding with HdrMode=1 and PaperWhiteScale=1, preserves the
implicit alpha of 1, and stores RGBA16F. `native_replay_codec.cu` performs that
operation on the GPU directly into the Feature18 half array. Feature18 receives
RGBA16F color/output, original RG16F motion and original R32F depth.
`codec_decode.comp` is intentionally not run because the requested artifact is
the raw neural RGBA16F output, not the final scene-linear decoded blend.

## Safety and temporal policy

- A smoke process evaluates raw0 with half color/output plus mixed half/float
  guides. The default temporal process starts only after smoke verification.
- The default process creates one handle, evaluates raw0..31 in order, and
  saves only raw24..28. It does not skip raw0..23.
- Raw0 is forcibly reset because a new standalone temporal history has no prior
  state. This differs from the captured `reset=false` and is explicitly written
  to the output JSONL run, frame, and session records.
- Captured resets (raw9 in the default range, and raw68 in longer runs) are
  preserved. Jitter, exposure, subrect bases, and motion-vector scales are
  copied from each manifest frame.
- DLL/hash/manifest/resource/CUDA/NGX/readback errors terminate immediately.
  Partial JSONL is retained and never renamed to a complete manifest.
- No game deployment is touched. No Fast/priority service tier is used.

## Build and run

```bash
./build_native_replay_feature18.sh
./run_native_replay_feature18.sh
```

An optional second run argument selects a new output directory:

```bash
./run_native_replay_feature18.sh /path/to/capture /new/output/directory
```

The run directory contains the full capture checksum log, smoke/default logs,
output JSONL manifests, per-output SHA-256 values, a verification report, a
complete artifact `SHA256SUMS`, and its verification log.

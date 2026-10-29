# DLSS Router frame telemetry

The Wuthering Waves Router writes one complete record for every signed SR/RR
`EvaluateFeature` call to:

`Client/Binaries/Win64/dlss-ngx-frames.jsonl`

Schema: `dlss-ngx-frame/v1`.

Each record contains:

- `utc_unix_ns` and `utc_iso`, sampled next to `qpc_end` with Windows precise
  wall clock (100 ns representation)
- process-global `global_frame_id` (`frame_id_scope=ngx_evaluate`) and the
  role-local sequence
- `qpc_begin`, `qpc_end`, and `qpc_frequency`
- Reset, jitter, MV scale, pre-exposure, exposure scale, source flags, and
  presence bits for optional values
- parameter and D3D12 resource addresses
- physical width, height, format, dimension, and sample count for Color,
  Output, MotionVectors, Depth, and ExposureTexture
- original signed Evaluate result, requested/candidate/effective post mode,
  whether post was called, post result, and Reset/settle/forced-Reset routing

`global_frame_id` counts NGX Evaluate calls, not Present calls. Wuthering Waves
normally has one terminal RR Evaluate per rendered frame, but that scope is kept
explicit so an SR+RR title is not mislabeled.

## OBS correlation

```bash
cd /home/user/rt_5090_project/dlss_ngx_proxy
./tools/correlate_obs_dlss.py \
  '/path/to/recording.mp4' \
  --video-frame 156 \
  --telemetry '/path/to/Client/Binaries/Win64/dlss-ngx-frames.jsonl' \
  --role rr --neighbors 3
```

Or use video-relative seconds:

```bash
./tools/correlate_obs_dlss.py recording.mp4 --time 2.600 \
  --telemetry dlss-ngx-frames.jsonl --role rr
```

MP4 `creation_time` is commonly quantized to one second, so this automatic
mapping has up to about ±0.5 s anchor uncertainty. For exact calibration, give
one known video/DLSS pair:

```bash
./tools/correlate_obs_dlss.py recording.mp4 --time 2.600 \
  --telemetry dlss-ngx-frames.jsonl --role rr \
  --anchor-video-frame 156 --anchor-global-frame 4217
```

The tool also fits the telemetry wall clock to QPC and reports fit residuals.
It does not treat MP4 metadata alone as frame-exact evidence.

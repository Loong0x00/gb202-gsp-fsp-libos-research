# Wuthering Waves: corrupted frame caught in post-NR raw

## Result

The 5-second deferred Flight succeeded and captured the visible defect inside
the owned post-NR output texture.

This is the first same-run, same-pose correlation in which OBS contains the
bad frame and the intermediate post-NR raw contains the same structured block
corruption. The defect therefore exists no later than Feature18 + codec decode;
it is not first introduced by UE's later HDR/post-processing, Present, OBS
sampling, or AV1 encoding.

This capture alone does not yet split Feature18 neural output from the custom
codec decoder, because `post_nr` is after both.

## Integrity

Capture session:

`Client/Binaries/Win64/dlss5-raw-captures/20260903-110139-783-p320`

- requested/recorded/completed: `150/150/150`
- abandoned/write-failed: `0/0`
- 150 post-NR raw files
- output: 6144×3456, DXGI_FORMAT_R11G11B10_FLOAT
- payload: 12,740,198,400 bytes (11.87 GiB)
- all files exist and match manifest sizes
- `SHA256SUMS.capture` contains all 150 raw hashes plus the manifest hash
- no UE4 crash, Xid, OOM, or process kill

OBS source:

`/home/user/2026-09-03 11-01-35.mp4`

- SHA-256: `30fbd4d2ab3233f3a9fa64d7c7df0c20297c36a9a9cc77a8d57d68538d1753c4`
- AV1, 6144×3456, 60 fps, 1479 video frames, 24.661 seconds
- complete ffmpeg decode passes

## Exact bad/clean sequence

OBS recording started at 11:01:36.093 CST. Raw timestamps use the same wall
clock. A stable approximately 47–50 ms raw-to-OBS display offset aligns:

| State | Raw capture | Bridge | Router global | Raw-relative PTS | OBS samples | Feature18 GPU |
|---|---:|---:|---:|---:|---:|---:|
| clean | 103 | 1323 | 3066 | 7.747 s | preceding clean | 18.237344 ms |
| **bad** | **104** | **1324** | **3067** | **7.784 s** | **470–471, 7.833–7.850 s** | **19.206048 ms** |
| clean | 105 | 1325 | 3068 | 7.817 s | 472–473, 7.867–7.883 s | 18.534304 ms |
| **bad** | **106** | **1326** | **3069** | **7.853 s** | **474–476, 7.900–7.933 s** | **20.404128 ms** |
| clean | 107 | 1327 | 3070 | 7.886 s | transition onward | 20.450208 ms |

Both bad raw images contain the same large structured mosaic/block pattern as
OBS. The clean raw frame between them is also clean in OBS. Every Router entry
reports Reset=0, original signed RR success, Feature18 post success, no reset
or settle bypass, and no deferred forced Reset. There is no distinctive timing
failure: clean bridge 1327 is slightly slower than bad bridge 1326.

Artifacts:

- `obs-vs-post-104-107.jpg`: four aligned OBS/raw pairs
- `raw-post-frames-100-112.jpg`: raw sequence around both corruptions
- selected bit-exact raw 104–107 and hashes
- complete capture hash list
- Router and GPU-timing excerpts
- OBS contact sheets and metrics

## Next diagnostic split

Capture the model's R16G16B16A16 neural output immediately before codec decode:

- neural bad -> Feature18 inference/temporal contract
- neural clean but post-NR bad -> codec decode/output stage

The broad UE/Present/OBS branch is now closed.

## Cleanup

After preserving raw frames 104–107, their hashes, the complete manifest/hash
list, OBS video, and full run logs in this report, the 11.87-GiB active session
was removed at the user's request. The earlier accidentally stopped 109-frame
post-only payload was also removed, leaving its manifest and archived OBS
video. The live capture root, telemetry logs, and markers are now empty; the
next run starts from a clean slate.

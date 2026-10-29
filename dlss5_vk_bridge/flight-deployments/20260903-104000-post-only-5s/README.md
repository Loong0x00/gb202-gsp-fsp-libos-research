# Five-second post-NR Flight recorder

Built while the game was running, then atomically deployed after it exited.

Installed SHA-256:

`07c1fce75e185d21f8866af679ac3d961e644df8b9ed68e9170c12eac174a6cf`

- 150 deferred frames, approximately five seconds at 30 fps.
- post-NR only, 6144x3456 R11G11B10.
- Expected readback/disk payload: 12,740,198,400 bytes (11.87 GiB).
- Fits under the unchanged 12-GiB allocation cap because each output footprint
  is exactly 84,934,656 bytes.
- No per-frame Signal, Map, worker write or disk I/O during the target window.
- OBS remains required for final-frame correlation.

Capturing all five resources for five seconds would require roughly 34-43 GB
at the observed 24-30 fps and is intentionally rejected. Post-NR alone is the
minimal decisive first split: a corrupted post texture implicates the owned
Feature18/codec path; a clean post texture with a bad OBS frame moves the fault
downstream.

`restore.sh` restores the previous 32-frame five-surface deferred recorder only
while the game is stopped.

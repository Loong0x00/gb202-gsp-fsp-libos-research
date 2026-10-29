# Wuthering Waves output-copy-only A/B

## Binary

Previous transition-only service:

`5cc15ba7c71a70c3823e3d3d9a8f73489af76dac8fab26c0f0a79a73fa181690`

Current output-copy-only service:

`ed2db2a3ed3e0f83284a904b9965407af39ff5f753760ec5bcb644f781d5425a`

## Controlled change

Both a UAV barrier and a no-copy `UAV -> COPY_SOURCE -> UAV` round-trip failed
to suppress the defect. This build performs one real full-resolution output
copy after Feature18 and codec decode:

1. transition output `UAV -> COPY_SOURCE`
2. `CopyTextureRegion` the 6144×3456 R11G11B10 output into one persistent
   readback-heap sink (expected 84,934,656 bytes)
3. transition output `COPY_SOURCE -> UAV`

The sink is never mapped, written to disk, or waited on by the CPU. It is
reused every frame on the same ordered command queue. Raw capture remains
inactive unless separately armed. This isolates a real GPU read/copy from the
five-surface raw capture and its CPU writer/fence handling.

## Test

1. Launch normally at 6K.
2. Do not press `Super+Alt+C`.
3. Confirm normal performance, then test the two input cases separately.
4. Report whether the structured bad frame remains.

A valid run must log both:

- `post-SR D3D12 full-output copy sink enabled (copy-only A/B; no Map/wait)`
- `post-SR output-copy sink ready size=6144x3456 format=26 bytes=84934656`

If sink creation fails, the service logs that the A/B is invalid but preserves
the original successful Evaluate return. `restore.sh` returns to the prior
transition-only build while the game is stopped.

## Live result

FAIL to suppress the defect. The required build marker and successful sink
allocation are present in `bridge.latest-run.log`, including the exact
84,934,656-byte 6K footprint. The user reports that the bad frame remains and
raw capture was not armed.

The run contains 3,291 Router Evaluate records. After login gating, 1,759
Feature18 posts succeeded and zero failed. The game exited normally, with no
new UE4 crash or Xid. Therefore a real full-output read/copy by itself is
insufficient; the next split must reproduce the five-resource copy set or the
CPU/fence side of raw capture.

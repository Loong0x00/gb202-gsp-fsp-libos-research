# Owned true NR-before-SR benchmark candidate

This branch contains a native-Linux/Proton Cyberpunk 2077 candidate with the
actual ordering:

```text
current low-resolution Color + Depth + MotionVectors
  -> compact origin-zero Color staging
  -> HDR codec encode
  -> one signed Feature 18 (DLSSNR) evaluate at input resolution
  -> luminance-gain HDR composition at input resolution
  -> temporary Color bind
  -> original signed Feature 1 DLSS SR evaluate at requested output resolution
  -> restore the game's original Color parameter
```

It does not patch or replace NVIDIA SR/RR DLLs. The dedicated service does not
export `DLSS5_PostEvaluate`, and the router suppresses the old post callback
whenever pre-SR is requested. Feature 13/the RR role is fail-closed to untouched
signed RR.

See [`docs/PRESR_BENCHMARK.md`](docs/PRESR_BENCHMARK.md) for provenance, build,
diagnostic modes, expected logs, hashes, and benchmark handoff.

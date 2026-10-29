# Native formatted-SUST conversion — Main result

Main reviewed the original/witness instruction encoding and unchanged source-bit dataflow, checked61 worker artifact pins, reran8 CPU tests, then independently approved/built the own host. This uses only the new CUDA13.3 SM120 witness, not the NR model.

Guarded runs:
- `174958-positive`: 61441 RGBA vectors, 245764 scored components.
- `175044-extended`: 632 vectors, 2496 scored components plus32 raw unscored NaNs.

Both: exit0/Guardian0, successful post-launch synchronization and full context cleanup, unchanged input, zero border/tail guard errors. Main-only benchmark.lock, fresh no-games, >=4GiB initial headroom, global31000MiB cap,30s isolated-kernel watchdog; no game/DLL/driver/network changes.

## Measured result

| Domain | Scored | RNE mismatches | RTZ mismatches |
|---|---:|---:|---:|
| Positive [0,1], all half intervals' midpoint/neighbor probes and exact-half controls |245764|69120|0|
| Separate signed/extreme exploratory domain |2496|264|0|

Matched RTZ includes the tested half-subnormal cases, signed zeros, finite-overflow/max-finite cases and infinities. The32 NaN input components remain raw observations, not normalized or scored against invented payload rules. `POSITIVE_ANALYSIS.json` and `EXTENDED_ANALYSIS.json` retain range breakdowns and raw values.

This independently supports **RTZ behavior for these measured formatted SUST.P→RGBA16F inputs on this device/driver**. It is not all possible F32 values, all architectures, arbitrary Vulkan image writes, texture behavior, or a neural-equivalence proof.

Together with the separate original-CUBIN F32/F16 experiments, it separates presentation quantization from the small internal arithmetic discrepancy. That discrepancy requires the original SASS Q/K contraction proof, not a conversion-policy tweak or output offset.

Reproduce analysis only:
```
python3 -B fixture_cpu.py --domain positive --analyze run-20260911-174958-positive/output.rgba16f
python3 -B fixture_cpu.py --domain extended --analyze run-20260911-175044-extended/output.rgba16f
```

Prior worker sources, blocked binary and original kernels remain unchanged. Main's enabled host/approval and every run's raw outputs are separately pinned.

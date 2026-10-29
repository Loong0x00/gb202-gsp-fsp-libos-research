# PTX XBAR stress tester

Build:

```sh
make
```

Run one workload:

```sh
./ptx_xbar_stress --mode l2 --seconds 5 --l2-mib 32 --vram-mib 1024
```

Run with synchronized hardware-clock, voltage-target, NVML, and kernel-event
logging:

```sh
./run-ptx-xbar-case.sh l2 LABEL 5
```

`hardware-clocks.csv` measures the RM API-domain IDs directly: GPC `0x1`,
XBAR `0x2`, SYS `0x4`, and NVD `0x100000`. Earlier versions of this harness
mislabelled domain `0x1` as SYS even though the topology and simultaneous NVML
clock prove it is GPC; new runs use the corrected four-domain schema.

Available isolated modes are `compute`, `l2`, `vram`, `atomic`, and `all`.
`all` runs those four tests sequentially. True mixed modes interleave the
selected operations inside every warp of one kernel, so compute executes while
other resident warps have L2/VRAM transactions or atomics outstanding:

- `mix-cl`: compute + L2
- `mix-la`: L2 + atomics
- `mix-cla`: compute + L2 + atomics
- `mix-lv`: L2 + VRAM
- `mix-clva`: compute + L2 + VRAM + atomics

The tester
returns nonzero for a CUDA failure, a data-integrity mismatch, or incomplete SM
coverage. `run-ptx-xbar-case.sh` additionally fails on kernel alerts or a failed
post-run `nvidia-smi` query.

`--pause-ms N` inserts a host-side pause after each verified kernel round. It
is intended for thermal coexistence tests: a graphics heat source runs during
the pauses, while short full-SM validation pulses repeatedly execute at the
already-elevated die temperature.

`--target-sm N` uses PTX `%smid` filtering. Whole-GPU runs are the validated
path used by `RESULTS_20260816.md`; targeted-SM VRAM coverage is not yet a
replacement for the whole-GPU VRAM test.

The recorded balanced daily-profile candidate (not yet applied or declared
stable) is in `PROFILE_CANDIDATE_20260816.md`.

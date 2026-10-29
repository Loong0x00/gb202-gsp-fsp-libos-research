# IAS/GAS root hierarchy probe

This is a standalone OptiX microbenchmark. Normal timing launches use one
raygen thread; the optional ownership mode uses exactly two active roles in a
bounded grid. It does not modify
`agent_optix/minimal` and it does not change clocks, power limits, driver
settings, persistence mode, ECC, or GPU cache controls.

## Controlled scene families

Every GAS contains the same single triangle at `z=1`; every IAS contains
exactly one identity-transform instance.

| Code | Unique root handles | Child mapping | Intended comparison |
|---|---|---|---|
| `G` | K direct GAS roots | none | direct-GAS baseline |
| `IS` | K independent IAS roots | every IAS -> GAS 0 | vary IAS root, hold child fixed |
| `IU` | K independent IAS roots | IAS i -> GAS i | vary both IAS root and child GAS |

For every family, `unique` traverses the K roots in a deterministic Sattolo
cycle and `same` traverses the identical ring table with every handle replaced
by root 0. That same-handle control retains table traffic and operation count.

`forced_outside_root` sends `-Z` rays away from the complete root bounds.
`guaranteed_hit` sends `+Z` rays through the triangle. The miss and closest-hit
programs return payload 0 and 1; the host rejects any sample whose payload sum
does not match the expected result. A no-trace `ring_control` is also available.

The pipeline combines `OPTIX_TRAVERSABLE_GRAPH_FLAG_ALLOW_SINGLE_GAS` and
`OPTIX_TRAVERSABLE_GRAPH_FLAG_ALLOW_SINGLE_LEVEL_INSTANCING`, because OptiX
declares direct-GAS and `IAS -> GAS` graphs as separate, combinable contracts.
Trace depth is 1 and both pipeline-link and stack traversable depth are 2. The
host also checks that the selected device supports these limits before launch.

## Build only

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j2
```

These commands compile host code and OptiX IR but do not launch a GPU workload.

## Example runs (explicitly launch the GPU workload)

```sh
./build/optix_ias_root_probe \
  --scenario all --handle-set both --mode both \
  --max-k 24 --samples 9 --rounds 64 --warmup 4 \
  --order sattolo --format json --output results/k24.json

./build/optix_ias_root_probe \
  --scenario is --handle-set unique --mode miss \
  --max-k 24 --only-k 17 --samples 1 --rounds 1024 --warmup 64 \
  --format csv --output results/is_k17.csv
```

Hard limits are K <= 64, at most 2,000,000 trace calls in any launch, 64
samples, 4096 rounds, 1024 warmup rounds, a 10 s watchdog, no more than 64 MiB
of explicitly accounted probe VRAM in the normal sweep (256 MiB in explicit L2
mode), and no more than 1% of free VRAM.

Interpret `G -> IS` as the cost of introducing an IAS root with a fixed GAS
child, and `IS -> IU` as the cost of changing the GAS child as well. Output
metadata records all root and child handle mappings. AS output allocation sizes
are reported for reproducibility; they are not asserted to equal cache working
set sizes.

## Host-interlaunch L2 residency mode

L2 mode measures exactly one selected scenario, handle set, trace mode, and K.
Use `--warmup 0`; priming, marking, and eviction pressure are controlled by
the host between separate OptiX launches. `--rounds 1` is the first-cold
configuration. Larger values intentionally amortize the first cold ring over
in-launch reuse.

```sh
# Direct GAS: ordinary pressure baseline.
./build/optix_ias_root_probe \
  --max-k 64 --only-k 64 --samples 9 --rounds 1 --warmup 0 \
  --scenario g --handle-set unique --mode miss \
  --l2-policy normal --l2-window gas --thrash-mib 112

# IAS -> GAS hit: preserve only the IAS output range.
./build/optix_ias_root_probe \
  --max-k 64 --only-k 64 --samples 9 --rounds 1 --warmup 0 \
  --scenario iu --handle-set unique --mode hit \
  --l2-policy cuda-mark --l2-window ias --thrash-mib 112

# Preserve both separately allocated IAS and GAS ranges before the pressure pass.
./build/optix_ias_root_probe \
  --max-k 64 --only-k 64 --samples 9 --rounds 1 --warmup 0 \
  --scenario iu --handle-set unique --mode hit \
  --l2-policy cuda-mark --l2-window both --thrash-mib 112
```

Policies:

| policy | operation before each measured OptiX launch |
|---|---|
| `normal` | ordinary access-policy window, then streaming pressure |
| `persist` | persisting window attached to the OptiX stream; TTU self-read test |
| `cuda-normal-mark` | ordinary CUDA pre-read, then pressure |
| `cuda-mark` | CUDA persisting pre-read, then pressure |
| `cuda-mark-reset` | persisting pre-read, reset L2 preference, then pressure |

`--l2-window gas|ias|both` selects which AS allocation CUDA marks.
`both` is valid only with a `cuda-*-mark` policy because GAS and IAS are
separate allocations and must be marked under two successive policy windows.
`--mark-offset` plus `--mark-bytes` reads the same 16-byte-aligned subrange
from every selected fixed-stride AS record; it is intended for 128-byte line
mapping. A zero `--mark-bytes` reads the complete selected allocation(s).

`clock64()` excludes marker and pressure time. The program does not change
clocks. If cross-process cycle counts matter, lock the GPU externally or use
large effects, repeated processes, and the included normal controls.

## Same-launch SM ownership mode

Ownership mode runs a prime role P and probe role Q in one OptiX launch, records
their actual `%smid`, and classifies results only after execution. It does not
assume that adjacent SMIDs are a TPC. P/Q each have a device-side spin deadline,
and the host watchdog exits without resetting the GPU if scheduling cannot
satisfy the handshake.

```sh
# Fixed same-SM layout observed on this machine.
./build/optix_ias_root_probe \
  --scenario g --handle-set unique --mode miss --max-k 64 \
  --ownership-mode inlaunch --ownership-width 8192 \
  --ownership-prime-index 0 --ownership-probe-index 64 \
  --ownership-trials 64 --output results/ownership_same.csv

# Explicit two-role layout; always trust the SMIDs in the output, not the indices.
./build/optix_ias_root_probe \
  --scenario g --handle-set unique --mode miss --max-k 64 \
  --ownership-mode inlaunch --ownership-width 8192 \
  --ownership-prime-index 0 --ownership-probe-index 128 \
  --ownership-control-order reverse --ownership-trials 64 \
  --output results/ownership_pair_reverse.csv
```

The v9 CSV contains matched controls for trace-prime A versus unrelated C,
ordinary global loads of the located GAS `+0/+0x380` lines, Q-only L1 pressure,
and disjoint P/Q 256 KiB `L1::evict_last` pressure. Except for `probe_only`, Q
performs exactly 16 preparation traces before the timed A probe. `forward` and
`reverse` change execution order while keeping record slots indexed by control
ID. `--ownership-index-gap N` remains a convenience for `Q=P+N`; explicit
`--ownership-probe-index` also permits reverse-direction pairs.

Current v11 additionally accepts `--ownership-scrub-count N` and
`--ownership-controls unique|capacity`. `capacity` runs only the trace-A versus
unrelated-C pair with disjoint P/Q L1 pressure and N unique Q evictors. This is
the low-overhead mode used to locate the paired-SM S=15/16 effective-capacity
boundary; N must be at most `max-k-2`, because the unrelated target is `A-1`.

Adjacent width-1 launches and separate-stream concurrency are retained as
diagnostic modes, but were non-discriminatory/serialized on this system. The
same-launch findings and their limits are documented in
[`../../RT_CACHE_OWNERSHIP_FINDINGS.md`](../../RT_CACHE_OWNERSHIP_FINDINGS.md).

## Opaque AS dumps and OptiX JIT capture

`--dump-gas FILE` and `--dump-ias FILE` copy only AS output allocations
owned by the current process with `cudaMemcpyDeviceToHost`. Output metadata
records the traversable handle minus its allocation base; these dumps are
driver/build-specific observations, not a stable OptiX ABI.

`--optix-cache-dir DIR` enables a dedicated OptiX disk cache and links
capture-only closest-hit variants that force current-hit and from-handle
triangle fetch lowering. They are never referenced by the timing SBT. With no
cache directory, the timing pipeline still contains only its original five
program groups and the OptiX disk cache is disabled.

The cache database can be carved read-only:

```sh
python3 ../../jit_cache/extract_optix_cache.py \
  /path/to/capture/optix7cache.db /path/to/capture/carved
```

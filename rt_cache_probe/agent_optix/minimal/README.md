# Minimal headless OptiX 9.1 path

This prototype uses the official `NVIDIA/optix-dev` v9.1.0 headers and the
`libnvoptix.so.1` supplied by the installed NVIDIA display driver. It has no
windowing, OpenGL, asset, or full OptiX SDK dependency.

It builds one triangle GAS and launches one ray by default. `--mode hit`
targets the triangle center; `--mode miss` points the ray away from the GAS.
Both modes validate the returned payload. Triangle and ray counts are tunable,
but conservative hard caps and a VRAM budget prevent accidental large jobs.

Build:

```sh
cmake -S . -B build -G Ninja -DOPTIX_COMPUTE_ARCH=compute_120
cmake --build build -j 2
```

Minimal smoke checks:

```sh
./build/optix_minimal_probe --triangles 1 --rays 1 --mode hit
./build/optix_minimal_probe --triangles 1 --rays 1 --mode miss
```

A small adjustable-GAS check (still low load):

```sh
./build/optix_minimal_probe --triangles 1024 --rays 1024 --mode hit
```

Independent-GAS cache working-set sweep:

```sh
./build/optix_gas_sweep --max-k 32 --samples 9 --rounds 64 \
  --warmup 4 --mode all --format csv --timeout-ms 2000
./build/optix_gas_sweep --max-k 32 --samples 9 --rounds 64 \
  --warmup 4 --mode all --format json --timeout-ms 2000
```

`optix_gas_sweep` builds 32 physically independent one-triangle GAS outputs and
uses exactly one ray-generation thread. For each working-set size K=1..32 it
warms the K-handle ring and records multiple `clock64()` samples. It exposes:

- `guaranteed_hit`: traversal plus a triangle primitive hit;
- `forced_miss`: traversal in the opposite direction;
- `ring_control`: volatile handle/next loads without `optixTrace`;
- `empty_control`: integer-loop/clock overhead without handle loads or tracing;
- `same-handle`: the same loop shape while every entry names one GAS;
- `prime`: prime A, touch K-1 other GASes, then time only the probe of A;
- `prime-same`: the corresponding repeated-handle control.

Use `--order reverse` or `--order permuted` to change both GAS-handle and
entry-table traversal order while preserving the same K-element working set.
This helps distinguish a real capacity boundary from sequential-address or
prefetch artifacts.

The per-launch `optixTrace` count is hard-limited to 2,000,000 and a host-side
watchdog exits only the probe process if a launch exceeds its timeout. No launch
has more than one active ray-generation thread.

On this driver each one-triangle GAS output allocation is 2,560 bytes. That is
not the measured RT-path record working set. The controlled result on this RTX
5090 is a 16-entry residency threshold: cyclic timing steps at 16 -> 17, and
prime/evict/probe retains A behind 15 other GASes but evicts it behind 16.
One-pass L1TEX counters show four additional 32-byte sectors per traversal after
overflow. This supports a 2 KiB effective L1-backed footprint, but does not by
itself prove that the RT unit contains exactly 2 KiB of physical SRAM. See
[`../../FINDINGS_5090_RT_CACHE.md`](../../FINDINGS_5090_RT_CACHE.md) and
[`../../counter_analysis.md`](../../counter_analysis.md).

Prime/evict/probe reproduction:

```sh
./build/optix_gas_sweep --max-k 24 --samples 21 --rounds 256 \
  --warmup 64 --mode prime --order sattolo --allocation-layout contiguous \
  --launch-layout isolated --format json --output results/prime_unique_k24.json
./build/optix_gas_sweep --max-k 24 --samples 21 --rounds 256 \
  --warmup 64 --mode prime-same --order sattolo --allocation-layout contiguous \
  --launch-layout isolated --format json --output results/prime_same_k24.json
```

Both processes disable the OptiX on-disk compilation cache. They only create a
CUDA primary context, allocate/free process-owned VRAM, build OptiX GASes, and
launch the requested rays. They do not change
clocks, power limits, persistence mode, ECC, firmware, kernel modules, or driver
configuration.

Replacement/victim scan:

```sh
# No refresh, A-prefix refresh, and immediate-warm victim controls.
./build/optix_gas_sweep --max-k 64 --samples 7 --rounds 64 --warmup 2 \
  --mode replace-all --allocation-layout contiguous \
  --replacement-rotation 7 --replacement-refresh-count 1 \
  --output results/replacement_contiguous_rot7.csv

# Refresh A,B1,...,B7 after filling A..B15, then insert X.
./build/optix_gas_sweep --max-k 64 --samples 7 --rounds 64 --warmup 2 \
  --mode replace-refresh --allocation-layout padded \
  --replacement-rotation 31 --replacement-refresh-count 8 \
  --output results/replacement_prefix8.csv
```

Replacement output uses `victim=k-1`. Every round first traces disjoint handles
32..63, fills candidates `A0..A15`, optionally refreshes entries, inserts X,
and times exactly one victim. Prefix refresh happens to match LRU, but arbitrary
orders show the actual serial rule is circular successor: after the last hit to
Ai, insertion evicts `A(i+1 mod16)`, always at +27 cycles.

Arbitrary-order and matched insert/no-insert control:

```sh
./build/optix_gas_sweep --max-k 64 --samples 9 --rounds 48 --warmup 4 \
  --mode replace-refresh-controlled --allocation-layout permuted \
  --replacement-rotation 47 --replacement-refresh-order 1,2 \
  --replacement-scrub-passes 4 --output results/replace_controlled.csv
```

Address-selected eviction-set scan (`k-1` is the evictor count):

```sh
./build/optix_gas_sweep --max-k 64 --samples 5 --rounds 32 --warmup 2 \
  --mode evict-set --allocation-layout padded --eviction-victim 31 \
  --eviction-start 18 --eviction-step 62 --output results/evict_set.csv

# Or supply any explicit 1..16-member subset; 32 disjoint scrub roots are
# selected automatically from the remaining GASes.
./build/optix_gas_sweep --max-k 64 --samples 7 --rounds 64 --warmup 2 \
  --mode evict-set --eviction-victim 0 \
  --eviction-candidates 2,4,6,8,10,12,14,16,18,20,22,24,26,28,30 \
  --output results/evict_set_explicit15.csv
```

The measured 64-GAS pool had no eviction with fewer than 16 candidates across
192 affine scans and 64 single-member reductions. Full controls and
interpretation: [`../../RT_ROOT_REPLACEMENT_FINDINGS.md`](../../RT_ROOT_REPLACEMENT_FINDINGS.md).

Hit/deeper-path 31+1 victim control:

```sh
# k is victim+1. Test inserts A31; the equal-length control re-hits the last
# resident fill instead. Fourway also runs forced-miss probes to subtract root
# path changes. Optional L1 trash amplifies a hit/deeper backing miss.
./build/optix_gas_sweep --max-k 64 --only-k 31 \
  --samples 9 --rounds 16 --warmup 4 --mode hit-replace-fourway \
  --replacement-scrub-passes 4 --hit-replacement-l1-trash \
  --output results/hit_replace_v30.csv

# Change which logical record is the 31st fill.
./build/optix_gas_sweep --max-k 64 --only-k 2 \
  --samples 21 --rounds 64 --warmup 8 --mode hit-replace-controlled \
  --order reverse --replacement-scrub-passes 4 \
  --output results/hit_replace_reverse_last_A1.csv
```

Sequential/reverse/permuted/Sattolo fills move the victim to the respective
last fill `A30/A1/A4/A16`; each is +27 cycles relative to the previous fill.
An optional `--hit-replacement-refresh N` re-hits a stable record after fill;
tested hits did not move the streaming slot. See
[`../../PRIMITIVE_PATH_CACHE_FINDINGS.md`](../../PRIMITIVE_PATH_CACHE_FINDINGS.md).

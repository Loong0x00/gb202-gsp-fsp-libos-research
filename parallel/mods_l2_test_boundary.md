# MODS 570.151 L2 test observability boundary

Status: **final, static-only**
Date: 2026-07-21

## Scope

This note audits only the decoded JavaScript shipped in the already extracted
MODS 570.151 package. MODS was not executed, no GPU/device/MMIO interface was
opened, and no reset or configuration operation was performed.

## Direct result

MODS contains two materially different L2-test families, but neither supplies a
validated per-disabled-bit health test for a retail GB202:

1. The old `CudaL2Mats` JavaScript wrapper really does create one perfmon
   experiment for each `(FBP, slice)` and reports hit/miss counts per logical
   slice. However, its own support callback rejects GA10x-and-newer GPUs which
   have no uGPU. That excludes an ordinary single-die GeForce GB202 through this
   visible wrapper.
2. The newer `NewCudaL2Mats` test is explicitly configured for Blackwell and is
   registered for LinuxRM. It chooses an allocation no larger than the current
   reported L2 capacity and enables `TriadTest`, but its visible setup has no
   `(FBP, slice)` selector, no `IsL2SliceValid` loop, and no per-slice perfmon.
   It is therefore a whole-cache-sized stress/check candidate, not a certificate
   for one newly enabled physical LTS.

This is useful future validation context, not permission to run an untrusted
diagnostic binary on the desktop GPU.

## FACT

### Legacy per-slice wrapper

`mods_audit/static/decoded/all/gpudecls.js:487` registers `CudaL2Noc` test 228
only for client-side RM/Android/DA and describes it as a GA100 L2-NOC test.
`gpudecls.js:5295-5321` configures the older `CudaL2Mats` wrapper and its
support callback. The callback returns false when:

```text
family >= Ampere && UGpuCount == 0
```

The wrapper body at
`mods_audit/static/decoded/all/gputest.js:12820-13021`:

- obtains `FrameBuffer.MaxL2SlicesPerFbp`;
- loops over every slice and FBP;
- skips entries for which `FrameBuffer.IsL2SliceValid(slice, fbp)` is false;
- creates `Perfmon.CreateL2CacheExperiment(fbp, slice, ...)` for each valid
  logical slice;
- runs one shared memory workload, then reads per-experiment hit/miss counters;
- treats zero hit or miss counts as unreliable and fails only on a configured
  miss-rate condition.

For the `CudaL2Noc`/test-228 branch, the same body explicitly sets
`RunExperiments=false` because GA100+ can intermittently fail to latch these
perfmonitors. It then skips the per-slice experiments entirely. Thus the visible
modern-uGPU fallback cannot be repurposed as per-slice counter validation.

### Blackwell-capable whole-cache test

`mods_audit/static/decoded/all/gpudecls.js:451` registers `NewCudaL2Mats`
test 351 for LinuxRM as well as other environments. Its setup at
`gpudecls.js:3515-3548`:

- enables random data;
- enables `TriadTest` by default for `family >= Blackwell`;
- uses 1024 iterations and a nominal 5-second runtime;
- sets `MaxFbMb` to the currently reported `FrameBuffer.L2CacheSize`.

The visible setup contains no physical or logical LTS identifier and does not
call the per-slice perfmon APIs. The allocation-size choice can keep the working
set near the aggregate cache capacity, but it does not prove that every physical
data/tag bank or every newly enabled slice was exercised.

### `FixL2ModeToTest` is not a selector

Both generic memory-test setup paths call `FixL2ModeToTest`. Its complete body at
`mods_audit/static/decoded/all/gpuargs.js:14114-14123` only changes a request for
globally disabled L2 back to globally enabled L2 when the GPU cannot disable L2.
It has no FBP/LTC/LTS argument and cannot isolate one cache slice.

## INFERENCE

- `NewCudaL2Mats` could be one layer of a future aggregate post-change stress
  plan because it is explicitly Blackwell-aware and sizes its allocation from
  the post-init reported cache size.
- Per-slice hit/miss counters, where supported, show that traffic was attributed
  to a logical counter domain. They do not by themselves prove data/tag-array
  integrity, stable mapping to a raw OPT bit, or exclusive routing of accesses.

## UNKNOWN

1. Whether the downloaded MODS build's native `NewCudaMatsTest` implementation
   is safe or trustworthy; this audit does not establish binary provenance.
2. Whether test 351 would be accepted on the exact retail GB202 configuration.
3. Coverage of every data/tag/set/way/bank, ECC path, replacement state, and
   address hash in a newly enabled unit.
4. Stable correspondence among a raw mask bit, a post-reset logical LTS index,
   and any perfmon instance.
5. Whether a faulty unit could corrupt driver/display/GSP traffic before a test
   detects it.

## Minimal conclusion

The package contains a Blackwell-capable aggregate L2-sized memory test, but the
visible genuinely per-slice perfmon wrapper excludes ordinary Ampere-and-newer
non-uGPU devices. MODS therefore does not presently close the missing GB202
per-new-slice health-verification problem.

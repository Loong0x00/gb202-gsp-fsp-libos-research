# Literal `cc_vit_1d_ffn_contract_fp8` CPU/static execution review

## Scope and pinned source

This directory contains an **exact byte copy** of the main review's entry as
`original.ptx`, SHA-256
`241e1ef9d146d34ce54b36abed24bbe41e6a04f2a3c4a9c5af699fa63f2adf96`.
The entry is `cc_vit_1d_ffn_contract_fp8`, has a 72-byte parameter record,
CTA `(32,4,1)`, canonical `N=128`, and grid `(8,1,4)`. Its own declarations
are 16,384 bytes of aligned shared input storage and 16 bytes of shared copy
barriers. This review reads/PTX-parses only local text and runs CPU Python; it
does not execute GPU/PTX, a PE/host program, Wine, or a checkpoint loader.

The live ABI pointer record is source-pinned at offsets `0,8,16,24,32,40` and
geometry at `64,68`; the contract model keeps the p32 counter and p40 temp
separate. The real block32/layer1 slab pin is `[39812674,44009026)`, 4,196,352
bytes, SHA-256 `5c0a940e75c7df37d50098a53796a5014019844d347dabe8c34d73dff4ca6696`:
4,194,304 bytes of projection source plus the 2,048-byte f16 coefficient tail
read at `p24+4194304`. The CPU operator deliberately requires source/weight/
skip/coefficient/output maps rather than claiming an unproved dense checkpoint
or raw-slab swizzle.

## Critical correction: terminal predicate and counter control

The previous `nr-vit-contract-reference-20260912/REPORT.md` is retained
unchanged as historical evidence. Its statement that z0 polls `z-1` is an
erratum. The copied source says, in order:

```ptx
setp.eq.b32 %p69, %r1675, 0;
@%p69 bra $L__BB46_119;
```

`%r1675` is `ctaid.z`. Therefore **z0**, not non-z0, branches directly to
`BB46_119`, whose guarded output-valid path writes the p40 temp b128 stores.
It does not poll `-1` and p40 is not zero-filled.

For **z=1,2,3**, lane 0 reaches `BB46_116`, calculates `z-1`, and repeatedly
uses the relaxed counter load until `counter >= z-1`. Other threads take the
CTA barrier path (`BB46_135`); the waiting lane joins that barrier after the
poll. z1/z2 use the 16 literal `red.global.v4.f16x2.add.noftz` operations.
z3 loads p40, adds its own partial, converts/packs E4M3, and writes p16. Every
path then reaches `BB46_176`'s CTA barrier; only lane 0 executes the release
store of `ctaid.z` to p32 after it.

`test_source_cfg.py` locks this predicate direction, confirms that BB46_119
has 16 direct b128 p40 stores and no relaxed poll, checks the z>0 poll form,
and checks that the end barrier precedes the release store. This is separate
from the NN arithmetic tests so a future map/model change cannot hide a CFG
regression.

## CPU derived execution boundary

`execute_reference.py` is a standalone finite, source-derived NN operator for
one or a bounded set of lanes in one actual 128-feature output group (group 0
via `run_first_output_group`; `run_features` accepts groups 0--7). It returns
and writes reference E4M3 output values, not merely an MMA primitive. It uses:

* all four z K partitions (`z*1024 .. z*1024+1024`) and a real 32-product
  E4M3 dot followed by one binary16 RN-even result per literal K=32 MMA;
* z0's actual learned C: `skip(E4M3) * coefficient(f16 tail)` before its MMA
  chain, rather than an unweighted residual guess;
* source-order z1 then z2 scalar components of
  `red.global.v4.f16x2.add.noftz`; the binary16 helper retains subnormals and
  does not FTZ; and
* z3 p40 load/add/output packing and the caller's independent output map.

The default one lane makes exact-rational CPU execution practical. Passing
`range(128)` executes a full first output group; expanding every output group
or raw byte swizzle is intentionally not claimed by the default test fixture.

There are two deliberately distinct notions of ordering:

1. **Source-control dependency, modeled:** a caller explicitly supplies a
   fresh p32 counter word of `-1`, and the controlled CPU scheduler executes
   z0, z1, z2, z3. The source then observes releases `0,1,2` at the nonzero-z
   relaxed polls. Missing counter state, stale/non-`-1` epoch state, missing
   p40 source stores, and any alternate/native CTA schedule fail closed.
2. **Portable/native happens-before, not proved:** the source's relaxed loads,
   release stores, CTA-local barriers, epoch initialization/lifetime, and
   cross-CTA visibility do not by themselves prove a portable CUDA
   happens-before for p40. This model's sequential control schedule is not a
   claim of native GPU parity or that arbitrary atomic reduction ordering is
   associative.

Thus a controlled fresh counter `-1` is an explicit **caller precondition**,
not an initializer invented by the kernel. In particular, z0's direct store
must produce p40; no fallback fill is permitted.

## Reproduce

```sh
python -B reviews/nr-vit-contract-execution-20260912/test_source_cfg.py
python -B reviews/nr-vit-contract-execution-20260912/test_execute_reference.py
```

The arithmetic test uses real nonzero coefficient/skip/C fixture values,
checks all z K partitions and source/weight/skip/coefficient/output map
coverage, output storage, missing-state rejection, z0-poll rejection, order
rejection, and `.noftz` subnormal retention. It is not a native execution
comparison.

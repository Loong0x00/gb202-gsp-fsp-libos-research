# Literal module-05 1-D FFN contract reference

## Correct target and launch contract

This review is limited to the literal
`reviews/nr-ptx-bundle-20260911/modules/module-05-dll-00dd4bc0.ptx` entry
`cc_vit_1d_ffn_contract_fp8`.  It is **not** a non-1D similarly named entry
and it does not use an 80-byte parameter record.  The entry declares and loads
a 72-byte live record.  Its six pointer loads are exactly:

| offset | actual host role (from the pinned contract forward) | actual 1-D PTX use |
|---:|---|---|
| 0 | `I[1]`, source candidate | async/global input-read family |
| 8 | `I[0]`, skip candidate | z=0 global-read/initial-C family |
| 16 | `O[0]`, output | final E4M3 global-store family |
| 24 | layer state/weights | bulk/matrix reads and `+4194304` tail reads |
| 32 | `O[1]`, counter | release store and relaxed poll address family |
| 40 | `O[class-vector-count+1]` or zero, temp | staging stores, atomics, and z=3 load |
| 64,68 | geometry | `N = p64*p68` |

The roles are verified against this entry's own `ld.param` instructions, not
an older non-1D source.  The pinned host code supplies CTA `(32,4,1)` and grid
`(8*ceil(N/128),1,4)`.  The executable reference deliberately has canonical
`N=128`, hence grid `(8,1,4)`; it does not infer a different image geometry.

The block32/layer1 slab pin is `[39812674,44009026)`, 4,196,352 bytes, SHA-256
`5c0a940e75c7df37d50098a53796a5014019844d347dabe8c34d73dff4ca6696`.
The first 4,194,304 bytes are source-addressed projection storage; the source
also explicitly loads `p24+4194304`, leaving a 2,048-byte tail.  The byte
counts agree with the host ctor's 4096-to-1024 configuration, but this review
does **not** turn the F16/raw container into a guessed dense layout.  In
particular, `LogicalMaps` requires independent source, matrix, skip, tail
coefficient, and p16 output-address mappings from a future byte-layout proof.

## Source-visible computation and cross-CTA state

The entry contains 128 literal `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`
instructions, 16 `red.global.v4.f16x2.add.noftz` instructions, and uses a
16,384-byte shared region with two copy barriers.  `contract_reference.py`
implements a nonmock scalar MMA: exact E4M3 product sum plus C, rounded to
binary16 once per K=32 MMA.  It runs four 1024-K partitions for the expected
4096-to-1024 projection and retains binary16 rounding at every K=32 boundary.
It does not substitute C, a callback, or an identity projection.

The source's terminal paths are important:

* z=0 obtains its C path from `p8`; the code converts skip E4M3, loads and
  multiplies the `p24+4194304` f16-tail values, then uses those registers as
  MMA C.  Thus there is evidence for a **learned skip contribution**, not for
  an unweighted/identity residual.
* z=0 stores its partial to `p40`; z=1 and z=2 execute
  `red.global.v4.f16x2.add.noftz` against `p40`; z=3 loads that p40 family,
  adds its own partial, converts to E4M3, and stores `p16`.
* The counter address is `p32 + 4*(8*tile + group)`.  Every CTA's lane-0
  terminal path does `st.release.gpu.global...s32` with `ctaid.z`.
  The only visible relaxed poll is the z=0 control path, against `ctaid.z-1`
  (therefore `-1` for z=0).

There is no p32 initializer in this kernel and no source instruction that
zeroes p40 before the z=0 store.  More critically, these instructions alone
do not establish a portable inter-CTA happens-before from z0/z1/z2 to the z3
load.  The bounded CPU method therefore requires explicit producer-owned
counter state and permits only the declared external schedule `(0,1,2,3)`.
It raises rather than zero-initializing a missing counter/temp or claiming a
native CTA order.  `red.global` ordering is modeled only in that explicit
schedule; this is not a claim that arbitrary half atomic reduction orders are
associative or equivalent.

## Delivered boundary

`ContractReference.run_point` is a useful NN-level, CPU-only contract for one
canonical `(token, output-feature)` point.  It has independent maps and a
full four-z learned projection/reduction for that point, including the
source-supported learned skip C path.  It is intentionally not advertised as
a full raw-checkpoint standalone forward: the PTX swizzles/async byte mapping
from the 4,196,352-byte slab and producer mapping for p0/p8/p16 have not been
proved.  Supplying those maps and a real producer synchronization boundary is
necessary before expanding it to all `128 x 1024` points.

## Reproduce

```sh
python -B reviews/nr-vit-contract-reference-20260912/collect_evidence.py
python -B reviews/nr-vit-contract-reference-20260912/test_contract_reference.py
```

These commands read pinned local text only and write `EVIDENCE.json` only in
this review.  They do not execute a PE/host, GPU, Wine, or PTX.

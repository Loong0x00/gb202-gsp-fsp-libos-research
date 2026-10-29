# block62 2h-upsample source review — bounded report

## Scope and method

This is a static reading of the authorized packet, chain result, `TWO_H_SOURCE.txt`, and the supplied 4h comparison candidates. It is **not** an execution, a numerical comparison, a native/standalone acceptance result, or a proof that a graph edge is bound to a particular kernel parameter. `PACKET.json` identifies block62 inputs as block61 output0 and block8 output1, but does not give the entry-parameter binding. Consequently the source establishes pointer-relative behavior; it does not by itself establish that `%rd1` is P0 or that `%rd3` is P24.

`CURRENT_CHAIN_RESULT.json` is useful upstream context only: it bounds NN48–61 output matching and reports block61’s CTA/MMA counts, while expressly not constituting full-NR/native/standalone acceptance. Its physical channel16-planar 16×16×128 A-basis finding is therefore not silently promoted to a block62 consumer-layout proof.

## Entry / pointer facts

* The entry has an 88-byte parameter block and 4096-byte dynamic shared declaration (2h source opening). It loads four 64-bit parameter-derived bases at offsets `0`, `8`, `16`, and `24` into `%rd1`, `%rd12`, `%rd13`, and `%rd3`, respectively. `%rd12` is used as the final output base; `%rd13` supplies the packed slab; `%rd1` and `%rd3` feed early global loads.
* CTA coordinate construction uses `ctaid.x/y/z`, lane/thread IDs, multiply-adds, and signed shift/compare/select operations. These are real addressing operations, not a declarative tensor-layout annotation. A physical tensor axis order cannot be recovered merely from the parameter list.
* At the opening projection, `%rd1` is addressed through an index assembled from the coordinate terms and lane subindices, then loaded as packed `b32` FP8 fragments (for example the `%r5894` family). Those values are used directly as the A operand of `mma.sync.aligned.m16n8k32...e4m3.e4m3.f32`; there is no intervening global-to-half conversion or input transpose instruction. Thus the first-projection consumer requires the packed FP8 fragment ordering selected by that address program. This is compatible in kind with an FP8 producer, but it does **not** prove that block61’s reported A-planar output is the exact P0 binding/ordering.
* The other early global input path derives from `%rd3`, loads packed values, converts them from FP8 to half, and participates in a scale/add path. It is the source witness for a second activation-like input, but is not sufficient to name that pointer P24. No source annotation attaches graph port names P0/P24 to parameter offsets.

## Prefix: literal dependency, addressing, and zero behavior

The early projection is a four-step K=32 FP8 MMA sequence. Its loop cursor begins at 0 and executes the 0, 32, 64, and 96 portions (the controlling compare is `< 96` after the first body), so its observed reduction coverage is K=128. Its packed B-side slab addressing is based at parameter+16 with CTA/thread-dependent terms and K-step advances. This is direct evidence for the MMA sequence and its local slab address family, not a complete matrix-shape proof.

The second input path uses coordinates derived with signed/truncation-style shifts and guarded selection. The loaded FP8 values are converted to half and multiplied by values loaded through the same parameter+16 slab base, with the visible scale region `+36992`; the resulting half values are added to the projection-derived half accumulator values before subsequent FP8 saturation/packing and shared-memory movement.

This establishes the following **local data dependence**:

```
%rd1 packed-FP8 projection (four K32 MMAs)
    -> half accumulator
%rd3 packed-FP8 -> half -> slab-derived scale
    -> add to that accumulator
    -> saturated FP8 packing / shared exchange
```

The source then performs coordinate-remapped shared/global movement with per-coordinate predicates. Its `selp`/predicate paths substitute zero fragments for invalid contributions before later MMA/shared stages; later phases likewise predicate stores and use zero-selected registers around out-of-range branches. These are genuine zero paths, rather than evidence that invalid lanes read a semantically valid padded tensor.

A conventional high-level statement such as “projection, nearest repeat, scaled skip add” has **not** been established from this alone. The arithmetic ordering above is local and precedes the later cross-thread/shared coordinate remap; reconstructing whether that remap is a semantic nearest operation before or after the skip at every output location would require a complete lane/CTA reconstruction. The 4h prefix candidate’s `projection -> reshape -> nearest -> scale skip -> add` order is therefore not copied into the 2h result.

## Slab witnesses, synchronization, and reduction structure

The directly established 2h parameter+16 slab witness is `+36992`, used by the early scale-vector address family on the `%rd3` input path. Its address includes coordinate/thread-derived terms. It must not be converted into a contiguous tensor size, axes, or universally applicable stride without enumerating every relevant address expression.

The initial B-side and later stages also have CTA/lane-dependent slab address programs and K-step advances, but this bounded review does not claim their full ranges. The source therefore does not support a complete slab ledger.

The entry contains repeated `bar.sync 0` phase boundaries around shared-memory producer/consumer exchanges. It also contains multiple FP8 `m16n8k32` groups and half-domain arithmetic/reduction tails, including warp shuffle/reduction code. Observed K=32 unit operations are not evidence that every logical reduction is a single K=32 pass: later work has separate phases and tail handling. Predicated selections provide zeros at several boundaries, but the source review does not establish a single global “padding rule.”

## 2h versus supplied 4h material

The strongest direct numeric difference is source-relative: the 2h source has a parameter+16 `+36992` witness, whereas the corresponding 4h source witness recorded during review is `+131328`. They are different address programs, not a license to scale dimensions or offsets.

The supplied 4h candidates describe a 256→128 prefix, canonical 64×128 FFN features, FP8 ranges/weights, a cubic half activation, LUT-dependent normalization/attention behavior, and a two-K32 PV characterization. None is a substitute for a 2h source derivation. For 2h, the source directly supports only:

* an early FP8-to-half projection/scale/add chain followed by FP8 packing and shared remap;
* recurring FP8 MMA, half arithmetic, barriers, predicates/zero substitution, and reduction-tail machinery; and
* the pointer-relative slab anchors above.

It does **not** establish a 2h FFN tensor shape, raw-QKV tensor shape, normalization formula, head/bank mapping, activation formula, exact nearest-repeat geometry, residual semantic identity, or an exact 2h two-phase-tail equivalent. In particular, no 4h FFN/raw/norm/two-phase-tail conclusion has been resized or copied to 2h.

## Conclusions and remaining proof gaps

1. The source proves a direct packed-FP8 first operand path from parameter+0, four K=32 projection steps, a distinct parameter+24 packed input path converted to half, a slab-scaled add, FP8 saturation/packing, predicates that supply zero values, and synchronization/shared exchanges.
2. It does not prove which of those pointer parameters is P0/P24. The requested P0/P24 physical addressing and block61-to-block62 layout compatibility therefore remain **unproven** pending a graph-to-parameter binding or a direct runtime argument record.
3. It does not prove the semantic prefix order beyond the local arithmetic dependency, nor complete slab extents/strides, nor 2h FFN/QKV/norm/tail semantics. These must remain open rather than imported from the 4h candidates.

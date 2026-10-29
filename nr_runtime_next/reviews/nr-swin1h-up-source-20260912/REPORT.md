Concrete fact: the block-66 source declares `.param ...[96]` at UP1_SOURCE.txt:1--2 and emits its final global stores at 13198, 13219, 15012, and 15029.

# Block 66 / 1h upsample — source-only reconstruction

## Identity and constraints
- Entry: `cc_tinlayout_fused_swin_1h_32_1_upsample_fp8` (UP1:1).
- Packet identity: 5,875 instructions, 96-byte parameter span, and the named F16 slab is 11,392 elements / 22,784 bytes (`PACKET.json`).
- This report uses the 1h source as the authority. UP2 and the `*2_NN.py.txt` files are comparator hypotheses only; their 88-byte ABI and 2h schedule were not mechanically halved or adopted.
- No dynamic shared-memory declaration occurs in UP1; no F32 MMA is assumed. The actual tensor opcode is repeatedly `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16` (for example UP1:275--299, 2447--2555, 11453--11561, 13070--13122, 14701--14939). FP8 E4M3 operands accumulate to F16.

## Own ABI: all actually loaded parameter offsets

| offset | load and source lines | source-established role |
|---:|---|---|
| P0 | `ld.param.b64 %rd5` (17), converted to `%rd1` (18) | first input/global feature source; addressed by the prefix loads at 125--127, 173--175, 222--224, 270--272 |
| P8 | `ld.param.b64 %rd6` (14) | output base; final addresses are based on `%rd6` at 13183--13185 and 14995--14999 |
| P16 | `ld.param.b64 %rd7` (13) | own named-slab base; converted again at 788; all recorded slab weights/scales/gammas derive from it |
| P24 | `ld.param.v2.b32 {%r37,%r38}` (15) | primary-source extent/axis pair: signed round-up then half at 31--36, edge predicates at 59--61 and 100--114 |
| P32 | `ld.param.v2.b32 {%r39,%r40}` (16) | CTA tile-origin pair: `%ctaid.{x,y}<<3` is added at 21--24 |
| P40--P72 | no `ld.param` in this entry | unused/reserved by this source; no role is inferred |
| P80 | `ld.param.b64 %rd2` (12) | second input/skip base, used by the FP8 loads at 598--608, 654--664, 707--717, and 760--770 |
| P88 | `ld.param.v2.b32 {%r41,%r42}` (11) | second-input extent/axis override pair: selected against P24 at 561--572 and used to bound P80 loads |

Thus P0/P24 describe the first producer input and P80/P88 the second input. Graph metadata identifies low producer `(65,0)` and high skip `(4,1)` as context only; it is not ABI proof or a live-activation claim. The ABI differs from the comparator's 88-byte record: P80 and P88 are actually read here.

## Slab access trace (relative to P16)

These are the relative offsets actually present in the source address expressions; ranges include the lane-vector coverage visible from the paired 16-byte loads.

| relative bytes | source examples | evidence-based use |
|---:|---|---|
| 0--8191 | 2320--2332; 3460--3473; 4696--4709; 5932--5945; 7168--7181 | FFN expand bank, loaded in source-owned unrolled K/group work |
| 8192--9215 | 71--82, iterated by 57--304 | prefix matrix, two K=32 passes (base advances by 128 bytes at 302) |
| 10256--10383 | 1725--2092 | F16 coefficient/vector loads consumed in the prefix/residual path |
| 10336--10463 | 901--1268 | overlapping F16 coefficient/vector loads consumed in the same path; overlap is source fact, not a deduced serialization layout |
| 10400--13471 | 7412--7459 | FFN grouped-projection bank |
| 13472--17567 | 11383--11450 | raw Q/K/V projection bank |
| 17568--21663 | 13233--13300 | later projection bank used after the attention path |
| 21664--21667 | 8509 | scalar F32-to-F16 scale load |
| 21680--22703 | 12998--13011 and 14815--14828 | final projection bank |
| 22704--22783 | 7917--8507 and subsequent packed-vector use | terminal F16 coefficient/vector area; exact semantic partition remains unresolved |

The only demonstrable large untouched interval is 9216--10255. The 12-byte 21668--21679 hole is also not addressed by the cited scalar/vector expressions. No layout, bijection, name, size, or serialized-F16 interpretation was inferred to fill those gaps.

## Source-owned pipeline

1. **Prefix and upsample selection.** P0 is read under explicit bounds; all other cases retain the zero initialization (`mov.b32 %r5047,0`, etc., UP1:115--127). The initial loop is genuinely two K=32 iterations: initial K selector zero (62), `mma...k32` (275--299), then selector `32` (302) and the backedge (304). Do not replace this with a truncated ceil rule.
   - Spatial halving is signed round-up then arithmetic shift, not bare truncation: UP1:25--36.
   - Candidate coordinates, OOB predicates, and zero/select behavior are explicit at 59--127 and replicated at 129--272. The second input uses nearest-style selections and predicate-gated zero FP8 at 575--787; it must retain the source `selp`, edge tests, and `cvt.rn.satfinite.e4m3x2.f16x2` conversion rather than an assumed sampling rule.

2. **Prefix/residual coefficient path.** The prefix fragments are shuffle-rearranged at 329--560. P80 FP8 is loaded only under the bounds/select logic (598--770), converted at 794--891, multiplied by slab values (1273--1490), and added (1497--1715). This preserves actual FP8-to-F16 conversion and source rounding; no generic nearest or skip formula is substituted.

3. **Own FFN is unrolled ownership, not a borrowed loop.** Source loads and converts 0--8191, repeatedly issues the actual FP8 MMA opcode, applies the cubic activation `min/max/abs/fma/fma/mul` (2559--3023 and repeated blocks), and quantizes with `cvt.rn.satfinite.e4m3x2.f16x2` (23235--2445 etc.). The unrolled progression, its zero accumulators, and every quantization point belong to this source. It is not a mechanically halved 2h ledger.

4. **Raw Q/K/V and two query halves.** The raw projection uses the 13472--17567 bank and MMA groups beginning 11453. The source makes two 32-channel halves visible in distinct register families: Q-side values feed squares beginning 8511/8514 and the Q normalization tree through 9632--9849; K-side values begin 9957/9960 and normalize through 10632--11049. Each tree preserves `mul.f16x2`, staged `add.f16x2`, `shfl.sync.bfly.b32`, `max.f16x2`, and the explicit `rsqrt.approx.ftz.f32` blocks (9202--9377 and 10632--10807). The epsilon is the actual F32 bit literal `948045311` (9063--9067), not a guessed epsilon.

5. **Attention, packed mapping, normalization, and PV.** QK uses the actual K32 MMA opcode (11453--11561); then the source applies constants `1027077105`, `1067877303`, `1065615360`, and `1070129152` (11567--11592), `fma.rn.f16x2`, max/min clamp, `shl.b32 ...,5`, and add `2146992128` (11596--11625 onward). This is the raw/packed score map, not an inferred softmax. Its reduction includes the same epsilon, then `rcp.approx.ftz.f32` at 12323--12332. The two PV K=32 blocks are the two MMA phases at 13070--13122 and 14887--14939, with FP8 re-quantization maintained between phases.

6. **Final projection and stores.** Final source code quantizes via `cvt.rn.satfinite.e4m3x2.f16x2` (14944--14989), predicates both output rows (14991--15029), and stores 128-bit vectors. It retains the original barriers/zeroing/shuffles/early seeds and quantization; no barrier, store, or rounding rewrite is proposed.

## Synchronization
`UPSTREAM_GRID_RESULT.json` records six source boundaries at PCs 1581, 2747, 3700, 4045, 4969, and 5299, all barrier id 0 with epochs 0--5 and 64 threads. That records the actual epoch sequence for the supplied grid result; it is not permission to introduce shared memory or to collapse barriers.

## Remaining unknowns and non-claims
- Source establishes access ranges and instruction/data flow, but does not name every F16 field or prove an external serialized tensor layout. In particular, the semantic split of the overlapping 10256--10463 range and the terminal 22704--22783 coefficients is unresolved.
- The exact high-level tensor mapping of every `shfl`, `prmt`, and `movmatrix` permutation remains a reconstruction task; no bijection is claimed from sizes or names.
- The packet's upstream graph is context only. It does not prove live input identity, host binding order beyond the source ABI, or activation contents.
- No numerical comparison, native launch, full-NR acceptance, GPU run, PE/Wine use, or external validation was performed or claimed.

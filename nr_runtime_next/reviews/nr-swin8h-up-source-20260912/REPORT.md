# SOURCE restoration notes — block48 upsample kernel

## Scope and confidence

This is source-only PTX analysis. Citations are original source line numbers from `upsample-numbered-nonblank.txt` / `standard-numbered-nonblank.txt`. “Fact” means directly present instruction/dataflow; tensor axes, parameter names, launch dimensions, and host DAG below are explicitly **not proved**.

## 1. Parameter object and pointer dataflow (facts)

Both entries declare 88 bytes (upsample 1–3; standard 1–3). The upsample loader is:

| bytes | register | subsequent direct use | source fact |
|---|---|---|---|
| +0 | `rd9 -> rd1` | first prelude global input loads | 12–18, 128–136, 164–173, 201–210, 238–248 |
| +8 | `rd10` | only final global-store base seen | 13, 15420, 15463 |
| +16 | `rd11 -> rd2` | slab/weight global loads, and core start `rd386=rd11` | 16, 875–1267, 33375–33378 |
| +24 | `rd3` | early separately-addressed e4m3 reads | 12, 565–690 (first four shown) |
| +32/+36 | `r39,r40` | bounds/dimension arithmetic | 14, 40–57 |
| +40/+44 | `r41,r42` | CTA origin arithmetic | 15, 20–39 |

Thus the defensible pointer-role labels are: **P0 prelude source base**, **P8 final destination base**, **P16 slab base**, **P24 early auxiliary/skip-candidate base**. Calling P24 “skip” is a strong DAG/layout hypothesis, not a source fact; calling P0 “source” is only a pointer-role shorthand. The architecture packet’s two incoming block edges does not establish which field receives which edge.

The standard loader has the homologous P0/P8/P16 fields (standard 12–17); unlike upsample it does not load P24 in its prologue.

## 2. Concrete upsample-only prefix

The upsample code has a substantial prefix before it writes its packed intermediates to shared and enters the same style of tiled Swin computation.

* CTA origin is `u=r42+8*ctaid.y`, `v=r41+8*ctaid.x`; then `iy=floor(u/4)`, `ix=floor(v/4)` (upsample 20–39). Bounds use rounded/negative-safe shifts, so a lift must reproduce signed shifts, not replace them with naive unsigned division.
* It performs `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16` on P0-fed fragments and P16+360960-fed fragments (251–275). The loop increments its slab address by 8192 and runs for counters 0,32,…,480 (`<480`) (278–283); source fragment reads are individually bounds-predicated and zero-filled (118–136 etc.). This is an actual additional learned tensor-core projection absent from the standard entry’s prologue.
* P24 is read as 16-byte vectors under spatial bounds; the early visible base calculation is `P24 + 4*((row<<10)+(tid.y<<7)+lane-vector-index)` (565–690). Invalid samples are constructed as zero then `cvt.rn.satfinite.e4m3x2.f16x2` (580–593 and analogous blocks). This proves an auxiliary e4m3 field participates in the prefix; it does **not** prove it is an additive residual.
* The prefix applies packed f16 operations, then spatially varying selects/zeroing. Example coordinate construction and OOB select are 1719–1763; all four comparisons are explicit in 1756–1763. At 3225–33335 the selected f16x2 values are rounded/saturated to e4m3x2 and packed.
* Those packed values are stored into the 16-KiB shared allocation, four 4096-byte planes, at a base shifted by `tid.y<<9`; a CTA barrier follows (33339–33374). Immediately after, P16 is reset as the tiled core’s base (33375–33411). This is the clearest source boundary: **extra projection/auxiliary spatial prefix → packed shared intermediate → normal tiled core**.

### Primitive equation (literal MMA candidate)

For each *decoded MMA fragment* (the PTX fragment permutation still must be decoded), the instruction is the orientation fact

`D[m,n] = MMA_f16_row_col(A_e4m3[m,k], B_e4m3[k,n], C_f16[m,n]), k=0..31`

from the exact opcode at upsample 251–275. Candidate logical lifts must retain both orientations:

* H1: `D = A @ B` with P0/intermediate as rows and slab tensor as `[K,N]`.
* H2: serialized slab axes are transposed relative to the host tensor, while preserving the *PTX* row/col operand orientation.

Neither serialized F16 size nor slab adjacency chooses H1/H2. Do not scalarize it as FP32 GEMM: the opcode output/accumulator is `.f16`; the source does not expose scalar dot-product rounding points beyond the MMA instruction contract.

## 3. What remains shared with standard, and the late weight shift

After the prefix, upsample executes the same visible family of shared-memory tile loads, e4m3 MMA, packed-f16 activation, quantization, normalization/reduction, and projection stages as standard. The standard core begins its initial shared write/barrier/MMA sequence at 253–290; the upsample core begins the corresponding P16-reset sequence at 33339–33411.

Direct late correspondence establishes a real slab-address shift, not a guessed tensor shape:

* standard late operand loads use `P16+688704` (standard 11303–11318);
* upsample late operand loads use `P16+820256` (upsample 14369–14388);
* difference: **131552 bytes**.
* standard final output-projection loop is based at `P16 + tid.y*1024 + 623680` (12067–12087);
* upsample corresponding loop is `P16 + tid.y*1024 + 755232` (15137–15157);
* difference again: **131552 bytes**.

This is strong evidence that the upsample slab has an extra 131552-byte region inserted before these late tensors. It does **not** by itself identify that region’s host tensor axes or prove contiguous logical matrices.

The extra final stage is not merely a store: it has a 32-wide e4m3 MMA tile with `m16n8k32.row.col` instruction, using shared packed activations and P16-sourced operand fragments (upsample 15195–15303), looped for counter 0,32,…,224 (`<224`) with shared address `+512` and slab address `+8192` each iteration (15306–15311). The standard analogue is 12125–12241. The final output-stage base is shifted as above.

## 4. Precision/order facts useful to a CPU executor

* MMA operands are e4m3, accumulators/output f16 (e.g. upsample 251–275, 15195–15303). Intermediate f16x2 results are repeatedly rounded with `cvt.rn.satfinite.e4m3x2.f16x2` before being reused (3225–33335; 15313–15406).
* The activation is exact instruction order, lane-wise packed f16: let constants be the **F16 values obtained by RN conversion** of the five shown f32 bit patterns. For input `x`, source order is

  `q=min.f16(max.f16(x, RN16(0xC0800000)), RN16(0x40800000))`

  `t=fma.rn.f16(RN16(0xBD660000), abs.f16(q), RN16(0x3F650000))`

  `h=fma.rn.f16(q, t, RN16(0x3EE50000))`

  `y=mul.f16(x,h)`.

  The instruction sequence is standard 1665–1723 and the upsample homolog begins in its core at 4743–4800. Keep min/max/abs/FMA/multiply in that order and f16x2 lane granularity; do not replace it with a named activation evaluated in FP32.
* Norm/reduction code explicitly uses f16x2 pairwise adds and shuffle permutations (e.g. upsample 12028–12345), applies `max` with a converted f16 epsilon/value, then converts each lane to f32, executes `rcp.approx.ftz.f32`, and converts RN back to f16 (12345–12371). Therefore a numerical-equivalence candidate must model approximate FTZ reciprocal if this path matters; ordinary exact CPU `1/x` is only a hypothesis.

## 5. Shared-memory / synchronization facts

* Static shared allocation is 16384 bytes, aligned 16 (upsample 11; standard 11).
* Four planes at offsets 0, 4096, 8192, 12288 are used repeatedly, with per-lane `laneid<<4` vector positions (upsample 33339–33372; final-stage reads 15160–15192). A CPU instruction lift should model byte-addressed shared storage plus 16-byte vector transactions, not infer a conventional NHWC tensor from those offsets.
* Visible producer/consumer phases use `bar.sync 0`: prefix packing then core (33345–33374), multiple core phase boundaries, and final return barrier (15496). Warp-local rearrangements use `shfl.sync.idx` (e.g. 12252–12342), independent of CTA barriers.
* No `mbarrier` instruction was observed in the inspected source regions; this is not a whole-file absence proof.

## 6. Exact final global output byte mapping (fact)

Let `t=tid.y`, `l=laneid`, `Y=ctaid.y`, `X=ctaid.x`, and use signed arithmetic as emitted:

`u = r42 + 8Y; v = r41 + 8X; iy=floor(u/4); ix=floor(v/4); W4=floor(r40/4); H4=floor(r39/4)`.

For the first output point, final code computes

`word = ((iy*W4 + ix) << 10) + (t << 7)`

and stores 16 bytes at

`P8 + 4*word + 16*l`

when `(u > -4) AND (iy < H4) AND (v > -4) AND (ix < W4)` (15408–15433).

It conditionally stores the next x point at `+4096` when the first-y predicate and second-x predicate hold (15436–15450), then uses `iy+1` / `u>-8` for the second y point (15453–15476), and the diagonal at second-y plus `+4096` (15479–15493). Each stored b128 is four packed e4m3x2 words = 16 e4m3 scalar bytes (15313–15406, 15423–15433).

Facts implied by the address, without choosing tensor axes: each spatial neighbor has a **4096-byte** stride; a warp/lane set writes a 512-byte `t` slice (`32*16`), and `t<<7` is a 512-byte slice increment. A candidate `blockDim=(32,8,1)` fills eight such slices per 4096-byte spatial record, but that is a launch hypothesis, not established by PTX alone.

## 7. Deliberately retained unproved hypotheses / rejected shortcuts

1. **P24=skip residual.** Plausible (auxiliary field feeds the prelude and P0 is separately projected), but unproved. Do not collapse P0/P24 based on model edge order.
2. **Upsample formula.** Plausible candidate: `packed_prefix = Q_e4m3( spatial/OOB-gather(activation(MMA(P0,Wextra)), P24) )`, then ordinary Swin core. The exact gather combination and logical spatial axes remain unresolved; source proves gather/select/packing, not this compact formula.
3. **Weight shapes/orientation.** Row/col MMA orientation is proved, but host serialization order, tensor axes, and a byte bijection are not. Preserve H1/H2 above.
4. **CTA/warp count and output channels.** `laneid` and `tid.y` dependencies are source facts; block dimensions and host geometry are not. The 4096-byte spatial stride cannot alone name a channel dimension.
5. **Native equivalence.** No execution, numerical test, native check, or host launch inspection was performed.

## Main continuation trigger

Main can now implement a literal address-first executor: bind P0/P8/P16/P24 separately; implement the prefix boundary at 33339–33411; preserve e4m3/f16 conversion and the explicit output equations; then enumerate slab regions by their emitted addresses rather than guessed serialized shapes. The unresolved fragment permutation, P24 algebra, and launch geometry require either an MMA-fragment decoder or external host/test evidence.

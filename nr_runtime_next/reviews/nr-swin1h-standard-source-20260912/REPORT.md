# ordinary1h67/68 source-only report

## Scope and ABI

The packet identifies ordinary `cc_tinlayout_fused_swin_1h_32_1_fp8`, 4,902 instructions and a 96-byte parameter object. Its actual parameter loads are exactly:

| byte offset | loaded value | source use |
|---:|---|---|
| 0 | `rd1` | P0 ingress base |
| 8 | `rd4` | output-store base |
| 16 | `rd5` | slab base |
| 24 | `r15,r16` | high H,W extent pair |
| 32 | `r17,r18` | X,Y origin pair |

No `ld.param` reads offsets 40–95. This is an ABI observation, not a claim about live host arguments. Packet graph context only supplies the bounded chain 66→67→68; it supplies no live-origin or host conclusion. Block 69 OUTVIEW is deliberately excluded.

The named packet slabs are both F16, 10,336 elements, 20,672 bytes: slab 67 at data offsets 147271072–147291743 and slab 68 at 147291744–147312415. The source uses the same slab-relative layout for either ordinary invocation.

## P0 ingress and bounds

`ctaid.y*8 + Y` and `ctaid.x*8 + X` form the two ingress coordinates (source 16–21). The signed sign-bit/add/shift sequences at 22–37 implement truncation toward zero for the division: `+3 → 1` and `-3 → -1`; they are not ceiling division. The guarded P0 address is base `rd1` plus a row/column-derived `<<7`, `*4`, and lane `*16` address (63–73; repeated for the four 2×2 positions).

For every failed row/column predicate, the alternate path writes integer zero, converts F16 zero to satfinite E4M3, and replicates that FP8 zero into the affected register quartet (76–89, 128–141, 177–190, 226–239). Thus out-of-bounds P0 contributes FP8 zero before any MMA. This is source-derived ingress behavior only; it does not identify P0’s live producer.

## Slab layout from actual source accesses

Ranges below are source access bounds, not inferred from a vector count or copied from UP data.

| slab byte range | source-derived role |
|---|---|
| 0–8191 | FFN matrix operands: source loads cover the four interleaved hidden-32 work portions and the 32-wide contraction operands. |
| 8192–8207 | 16-byte unaccessed gap between that weight region and the first gamma loads. |
| 8208–8271 | first gamma C=32: 32 F16 scalars = **64 bytes**. There is no fabricated 128-byte overlap. |
| 8272–8287 | 16-byte gap. |
| 8288–11359 | raw-QKV matrix operand bank accessed by the raw projection MMAs. |
| 11360–15455 | QK seed/bias accumulator bank: these values are C operands of the QK score MMAs, not raw-QKV weights. |
| 15456–19551 | later attention matrix/seed operand region accessed by the second unrolled score-side sequence; source establishes access, not a semantic stage name from instruction distance. |
| 19552–19555 | scalar loaded before the normalization/score-side scaling path. |
| 19556–19567 | 12-byte gap. |
| 19568–20591 | final 32×32 FP8 matrix operand region. |
| 20592–20655 | final gamma C=32: 32 F16 scalars = **64 bytes**. |
| 20656–20671 | 16-byte tail gap. |

The first gamma reads are at `rd5+8208` (source 364 onward); the scalar products appear at 734 onward. The final gamma reads are at `rd5+20592` (6442 onward), and feed the later final-MMAs as C accumulators (11594 onward). These are separate scalar-residual forks.

## FFN and residual provenance

The ordinary source shows the same two-layer shape established by the prior-66 Main result: **32→128→32**, not an UP two-head group/mix. In the ordinary code this is unrolled rather than a loop: the four hidden-32 portions are separately materialized/quantized and separately fed through the contraction path; there is no loop back-edge implementing a generic hidden loop. Weight accesses divide the four interleaved hidden-32 portions across the 0–8191 matrix region. The four portions are interleaved in register/MMA scheduling, not a shared grouped-mix buffer.

The first residual fork is traced locally: decoded/bounded P0 values are multiplied by the 8208–8271 gamma bank (`mul.f16x2` beginning source 734) and become carried C operands in the FFN contraction MMAs (for example source 2120 onward). It must **not** be assumed identical to any UP “unquantized P”; ordinary source establishes only this local P0-decode → gamma → carried-accumulator trace.

The final residual fork is also local: the unquantized FFN values in registers `r1502…r1533` are multiplied by the distinct final gamma bank at 20592–20655 (6818 onward). Their products `r2907…r2936` are the C inputs of the final projection MMAs (11594–11646). Therefore the final residual is from unquantized FFN, not from a decoded shared FP8 copy.

No `.shared` declaration, shared load/store, `bar.sync`, or other CTA barrier occurs in the ordinary source. This conclusion is from this source only, not synchronization transplanted from upstream JSON.

## Raw QKV, normalization, score mapping, and PV

All shown MMA instructions are `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`: FP8 E4M3 operands with F16 accumulation/results.

Raw QKV is distinguished from QK bias by operands, not slab position. The raw projection MMAs use the quantized feature-side A fragments (`r1536…r1539`) and slab B fragments loaded from 8288 onward (6106 onward). In contrast, QK score MMAs use quantized Q/K-side fragments (e.g. `r2473…` and `r3556…`) while values loaded from 11360 onward are their C accumulators (9977 onward): that is the QK bias/seed bank. The source therefore does not support calling both banks the same raw-QKV weight bank.

Normalization is a register/warp path: squared F16 pairs, `add.f16x2`, butterfly shuffles, epsilon max, `rsqrt.approx.ftz.f32`, conversion back to F16, and F16 multiply are visible from 7046 through 8385 and again in the later mirrored path. The attention scalar map is likewise explicit: F16 FMA, max/min clamp, then packed-word `shl`/`add` transformation (10089 onward). No source-only claim is made about a measured numerical replacement for approximate reciprocal/rsqrt.

`movmatrix.sync.trans.aligned.m8n8.b16` at 9697–9790 transposes private register tiles. The following PV MMA chain (11408–11516) consumes register-held probability/value fragments; no shared-memory staging or barrier is present. This is private PV/register dataflow, not a synchronization point.

## Output stores

The output base is parameter-8 `rd4`. Stores are guarded by the same signed spatial predicates: the first pair at 11720 and 11737 writes b128 tiles at the computed base and base+512; the second pair at 13530 and 13547 does the analogous next-row pair. Each store is `st.global.L1::no_allocate.b128` after FP8 satfinite conversion. The report does not assert an output tensor’s live host identity.

## Limits

This is source-only structural evidence. It provides no numeric acceptance, no native execution, no full-NR claim, no host/launch claim, and no block-69 OUTVIEW analysis.

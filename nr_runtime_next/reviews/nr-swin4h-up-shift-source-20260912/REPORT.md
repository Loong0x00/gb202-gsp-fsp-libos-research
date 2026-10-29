# SOURCE-ONLY4h shifted-PREFIX boundary report

## Scope and conclusion

Fact retained: actual current PE+factory block-56 origin is **XY=(-4,0)**, not the 8h-up zero origin. This is a static source trace only; it neither accepts that shift nor claims native/live/full-model behavior.

For `H=W=16`, `grid=(3,2)`, the source proves **raw FP8 source-zero** for out-of-range P0 and P24/skip operands. At `cx=0` and `cx=2`, the intended coordinate-zero gather is therefore the source policy for those operands, not caller padding:

| CTA x | high X origin | P0/low X (`ceil(X/2)+j`, `j=0..3`) | P24/skip X (same low coordinates, packed in 2x2 P24 granules) |
|---|---:|---|---|
| `cx=0` | -4 | -2,-1 = raw zero; 0,1 = real source | -2,-1 = raw zero; 0,1 = real source |
| `cx=1` | 4 | 2,3,4,5 = real source | 2,3,4,5 = real source |
| `cx=2` | 12 | 6,7 = real source; 8,9 = raw zero | 6,7 = real source; 8,9 = raw zero |

For both `cy=0,1`, Y starts at 0 or 8: P0 low Y is respectively `0..3` or `4..7`, and P24/skip low Y is in `0..7`; no Y operand gather is invalid here.

**Answer:** coordinate-zero P0/P24 gathering is sufficient for the *operand* boundaries, provided it occurs before the source's FP8 decode/MMA/skip scaling path and retains its reduction/order. It is **not sufficient for the complete prefix result by itself**: the source additionally zeros every out-of-range high-resolution result *after* the f16 late add and *before* FP8 quantization. Those late masks must be retained; they cannot be replaced by, or inferred from, the gather policy.

## Register trace

### Coordinates, signed narrowing, and P0 raw zero

The CTA high origin is `Y0=%r49+8*%ctaid.y` and `X0=%r48+8*%ctaid.x` (`%r1`, `%r2`; lines 20–39). The signed bias-and-shift sequences form `a=ceil(Y0/4)=%r3`, `b=ceil(X0/4)=%r4`, `qy=ceil(Y0/2)=%r5`, and `qx=ceil(X0/2)=%r6` (lines 26–39). They are signed operations, not unsigned coordinate arithmetic.

At 16x16 the extent equations yield `%r7=%r8=8` (lines 40–57). The four MMA operand loads use the same logical P0 coordinates

```
u = qy + i,   v = qx + j,   i,j in {0,1,2,3}
valid_P0 = (0 <= u < %r7) && (0 <= v < %r8).
```

The source computes that predicate at lines 115–124, 152–160, 189–197, and 226–234. Before each guarded global load it writes a literal raw zero word (`%r5819..%r5822=0`, lines 125–136, 161–173, 198–210, 235–248); an invalid predicate branches around the load. Thus invalid operands are source-created E4M3 zero bytes.

The actual P0 address equations also identify this as the guarded source operand, rather than a shape-based axis assumption. For the first fragment:

```
%r100 = %r5809 + %r13
%r101 = %r100 * %r10 + (%r96 << 2)
%r102 = %r101 + %r98
addr  = %rd1 + 4*%r102
```

(lines 130–136), with the analogous source address forms at lines 166–173, 203–210, and 241–248. `%r5809` starts as `%r5`, then increments by `%r12` within the unchanged K loop (lines 75, 278–283). The MMA loop is `K=0..255` in 32-wide steps, with zero f16 carry initialization (`%r5810..%r5817`, lines 58–83) and its original ordered `mma.sync` accumulation (lines 84–283). Keep this loop/order/barrier structure unchanged.

### P24/skip raw zero

For 16x16, `%r18=%r19=4` are the P24 granule extents (`H/4`, `W/4`; lines 532–539). The H/W=4 special cases `%p86/%p89` are false. The four P24 granules are addressed at `(a,b)`, `(a,b+1)`, `(a+1,b)`, `(a+1,b+1)` where `a=%r3`, `b=%r4`.

The exact source admission predicates are:

```
row0 = !(%r1 < -3 || a   >= 4)
row1 = !(%r1 < -7 || a+1 >= 4)
col0 = (%r2 > -4) && (b   < 4)
col1 = (%r2 > -8) && (b+1 < 4)
load(a+i,b+j) = rowi && colj.
```

See lines 547–579, 605–637, 662–692, and 717–748. (The `or`/`and`/branch form is equivalent to these admission conditions only after specializing the inactive H/W=4 cases.) The P24 pointer is constructed from the admitted granule index, e.g. `%r366=%r3*%r19+%r22`, then `(%r366<<9)+(%r9<<7)` and lane offset (lines 565–577); this is source evidence for its packed canonical-C128 traversal.

Each non-admitted P24 granule is explicitly formed from f16 zero, saturated to E4M3 zero, and copied to all fragment registers before later decode: lines 580–593, 638–651, 693–706, and 749–761. It is therefore raw source zero, not an asserted external padding rule.

### Projection, late skip, and required extra masks

The source decodes the admitted/zero P24 fragments to f16x2 at lines 764–861, multiplies them by the loaded scale/gamma values (examples at lines 1272–1490), and adds them to the reordered MMA result (lines 1496–1714). In source-level notation, preserving the K32 accumulation order,

```
L[i,j,n] = ordered_RN16_sum_k( decode_e4m3(P0[qy+i,qx+j,k])
                                * decode_e4m3(W[k,n]) )
N[2i+dy,2j+dx,n] = L[i,j,n]              # source shuffle/reorder
T = RN16(N + RN16(decode_e4m3(P24[...]) * gamma[n]))
```

where an invalid P0/P24 coordinate supplies the literal decoded zero above. This describes the operand boundary only; it does not remove the actual shuffle, instruction order, or rounding.

For every final f16x2 late-add register `%r684..%r715`, the source separately evaluates the high-resolution coordinate against `0 <= Y < %r46` and `0 <= X < %r47`, then applies three `selp` zeros. The first complete equation is:

```
pX = (%r976 < 0) || (%r976 >= %r47)
pYlo = (%r974 < 0);  pYhi = (%r974 >= %r46)
%r977 = pX   ? 0 : %r525
%r978 = pYhi ? 0 : %r977
%r684 = pYlo ? 0 : %r978
```

(lines 1752–1763). The same pattern is repeated for all final registers through lines 3223, then only those selected values are quantized E4M3 at lines 3225–3335 and stored to shared memory before the original barrier (lines 3337–3374).

Consequently the required final equation is:

```
prequant[Y,X,n] = (0 <= Y < 16 && 0 <= X < 16) ? T[Y,X,n] : 0
out = fp8_rn_satfinite(prequant).
```

At `cx=0`, this late mask zeros high X `-4,-3,-2,-1` even where a nearest/skip contribution could otherwise be nonzero; at `cx=2`, it zeros high X `16,17,18,19`. It is active across the complete CTA output register set, so it is an additional required mask, not redundant with the P0/P24 coordinate-zero gathers.

## Limits

No execution, commands, tests, network/search, directory reads, agents, acceptance decision, or padding-template inference was used. The zero-origin NN agreement/equal-byte information was not used as axis or boundary proof.

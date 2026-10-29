# Main bounded QKV address solution and split-block CPU tail

## What changed

The preceding worker report correctly left its symbolic SSA uncomposed. Main now **solves the expressions in the explicit H=W8, XY0, spatialCTA(0,0), four-warp domain**, checks them against original-instruction execution, and compares original MMA operands/output stores to independent expected maps. No live binding, arbitrary geometry or native arithmetic is inferred.

The original static QKV host grid-z4 evidence remains the corrected table atBA298, forward6d260, initializer6e230—not the cross-tableBA260window. The four CPU z slices use this bounded static context, not a captured live submission.

## Solved bulk/shared equations

At this domain, original r2=r3=0,r4=r5=2,r6=warp; r77=0,r76=warp//2,r9=128*(warp%2),r8=256*(warp//2). Broadcast and spatial-OOB paths are not taken. S0/S1 are stage0. In S2/S3, original r2882=64*s for s=0..6 prefetches t=s+1; the original unrolled tail consumes t7. The two original banks alternate without resetting retained bytes.

For input64-channel slice t0..7, tile-row ty0..1 and issuer warp w0..3:

```
source = 8192*(2*ty+w//2) + 1024*t + 512*(w%2)
shared = 4096*(t%2) + 2048*ty + 512*w
bytes  = 512
```

Original static copy PCs180/243 provide S0/S1;418/499 provide S2/S3. Main checks each actual issuer, pointer, size and original-PC occurrence against these formulas:64 transfers and32768 distinct input bytes per CTA. This is not `512*i` guessed from the range.

## Producer C layout -> shared -> first learned MMA A/B/C

Layer1's independently verified packed-C map is the logical reference. Decoding every byte of each solved512-byte chunk gives its producer row,column,channel. Combining that with the forward MMA-A fragment coordinates yields the **nonidentity channel permutation**

```
pi(k) = 16*(k//16) + 2*((k%16)//4) + 8*((k%4)//2) + k%2
producer channel = 64*t + 32*hk + pi(k)
```

All first768 MMAs per warp (seven loop passes plus original tail) receive independently checked A bytes from that map, exact B bytes from

```
98304*t + 12288*CTA.z + 3072*warp + 512*g
          + 49152*hk + 16*lane + 8*n + byte
```

and original C recurrence. The first learned projection really initializes its C to source r1629=zero; this is **not** replacement of the later attention-C backing region. Across four z slices the B checks cover all786432 first-projection bytes, including reused operands, without assigning guessed Q/K/V matrix axes.

Every MMA in each full execution still uses nonmock exact finite FP8 dot+C then RN-half and a separate forward-fragment arithmetic oracle; RCP/RSQRT use explicit reference policies, not identity callbacks.

## Independent final-C -> output and layer3 reader

At the final attention output groups (original PCs2313..2328 and3286..3301), Main forward-places independently computed final MMA-C half elements using source group/row/column assignments, independently quantizes with integer-dyadic RN E4M3, and checks **all8192 written bytes per z**. It does not use VM final output-register values as its expected output.

The resulting QKV packed-C byte equation is checked against layer3's independent `packed_a` reader across all32768 coordinates:

```
layer3_A(y,x,k) == QKV_C(y,x,32*(k//32)+pi(k%32))
```

This explicitly models the channel permutation while preserving raw bytes—no repacking. Main then executes both original layer3 channel CTAs using **src=A, skip=retainedP**, with the existing independent A/B/C/half/quant/store proofs and complete263168-byte real layer3 slab. Missing A or P bytes reject.

## Results and reproducibility

`check_boundaries.py` checks the real prior P on all four z slices and four finite address-tag fixtures on z0. Four4-bit tag digits distinguish every physical input address without FP8 NaNs. All executions reach originalret under real reference arithmetic. Original QKV candidate bytes remain unchanged:

- P: `247fa40fc373b2591a1236dcdeae85a14d228bba0e92a4ee3409bc68ea163a44`.
- A: `6de6b9a0431740353cdc39eec9f36fdcf02328a376ea8f76405ff8fb78193fc9`.
- **Layer3 Y: `a4b5fd7e645791ee59b0e6dc594f07461bd5fbd33b9345c18963b87ef01c4d99`**,32768bytes.

`test_boundaries.py`: four tests pass, including actual rejected mutations for identity-channel substitution, wrong bulk address, and wrong independent output quantization. `compose_layer3.py` records the final tail and preserves old UNVALIDATED-named files; it writes new bounded-reference copies rather than silently relabeling history.

```sh
python3 -B check_boundaries.py
python3 -B test_boundaries.py
python3 -B compose_layer3.py
```

This composes the previously verified layer0 F/layer1 P with newly checked A/layer3 Y: **all four original FP8 layer programs run in this bounded CPU fixture, retaining both residual edges**. It is not the complete NR network, real-game image/history execution, or native bit equality.

## Remaining limits

The first projection's full A/B/C provenance and the final-C output boundary are independently checked. **All internal attention-phase A/B/C semantic/typed mappings, all half arithmetic intermediates, all async schedules and arbitrary spatial/padding domains are not exhaustively certified.** The other131136 slab bytes are retained/read, with earlier source scalar/C witnesses, but this report does not upgrade those witnesses to full internal-role proof. Native precision remains unresolved (including the separate original4h226-byte gap). No GPU/Wine/installed changes occurred here.

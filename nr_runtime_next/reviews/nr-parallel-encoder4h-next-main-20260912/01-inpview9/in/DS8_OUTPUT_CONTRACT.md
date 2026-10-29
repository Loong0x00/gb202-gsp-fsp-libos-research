# Block8 output contract — exact supplied 2H DS source

Status: **static conditional contract, not host-port/allocation acceptance**. All integers below denote the source signed/wrapping operations; simplified envelopes assume nonnegative nonoverflow dimensions and a compatible CTA `(32,2,1)`. `q2/q4` mean truncation toward zero, **not floor for negative operands**. `X0=s32(X+8*ctaid.x)`, `Y0=s32(Y+8*ctaid.y)`.

## ABI (88 bytes)

| Offset | Source interpretation |
|---:|---|
|0|input C64 tiled byte pointer|
|8|full-resolution C64 quantized output (“skip” by function)|
|16|own block8 slab base|
|32,36|signed H,W for ingress/skip; also basis for learned output strides|
|40,44|signed X,Y origins|
|72|learned down-output pointer|
|80,84|signed PH,PW, **padding dimensions, not ingress overrides here**|

Offsets24–31 and48–71 are not loaded by this entry. The pointer+80/84 role is not the inpview5 interpretation. Source does not establish graph port numbers, host rounding or actual allocation. +72 null is checked only **after learned stores**, at13459–13460; it is not an optional-output guard for those stores. +8 likewise has no null store guard.

## 1. Skip at ABI+8: tiled C64 E4M3

Let `H4=q4(H), W4=q4(W), ty=q4(Y0), tx=q4(X0)`.
Four source stores (10390,10407,12717,12734) cover tile positions `(ty+a,tx+b)` for `a,b∈{0,1}`. Exact guards factor as:

```
GY(a) = (Y0 > -4*(a+1)) && (ty+a < H4)
GX(b) = (X0 > -4*(b+1)) && (tx+b < W4)
store iff GY(a) && GX(b)
byte = 1024*((ty+a)*W4+tx+b) + 512*warp + 16*lane
width = 16 bytes per lane
```

Stores are quantized from final half MMA D values; no per-pixel bounds test is inserted. For nonaligned/negative origins, do not replace the exact guards with an imagined pixel guard. Ingress additionally supports dimension-tile singleton broadcasts (`H&-4==4`, independently W) and zero-quantized OOB reads; output is not that ingress policy.

Canonical byte map for integer `0<=y<4*H4`, `0<=x<4*W4`, `0<=c<64`:

```
m = 4*(y%4)+x%4
skip(y,x,c) = 1024*((y//4)*W4+x//4) + 512*(c//32)
            + 64*(m%8) + 16*((c%8)//2) + 4*(m//8)
            + 8*((c%32)//16) + 2*((c%16)//8) + c%2
```

The complete tiled envelope is `1024*H4*W4` bytes, equal to `64*H*W` only for positive dimensions divisible by4. This is a formula, not an allocation. No skip padding clear exists. Finite byte-tag checks establish all4096 neuron bytes for an interior8×8 tile.

## 2. Learned output at ABI+72: eight planes of16 E4M3 bytes

`HD=q2(H), WD=q2(W), oy=q2(Y0), ox=q2(X0)`. The two-trip projection loop uses induction `u=0,64`; each warp computes output channels `32*warp+u .. +31`, not K64 in one operation. For lane `l`, plane `g=2*warp+(u>>4)`, four stores use:

```
(g,   y=oy+l//16,   x=ox+(l//4)%4), packed {rs1,rs2}
(g,   y=oy+l//16+2, x=ox+(l//4)%4), packed {rs3,rs4}
(g+1, y=oy+l//16,   x=ox+(l//4)%4), packed {rs5,rs6}
(g+1, y=oy+l//16+2, x=ox+(l//4)%4), packed {rs7,rs8}
```

Each is independently guarded `0<=y<HD && 0<=x<WD`, and stores **4 raw E4M3 bytes**, despite PTX transport type `.v2.b16`:

`byte=16*((g*HD+y)*WD+x)+4*(l%4)`.

Define `pi16(c)=4*((c%8)//2)+2*((c//8)%2)+c%2`. The canonical C128 layout is:

`down(y,x,c)=16*(((c//16)*HD+y)*WD+x)+pi16(c)`.

Complete learned-data envelope: `128*HD*WD` bytes. Source uses **trunc(H/2),trunc(W/2), not PH/PW and not ceil(H/2)**. Byte-tag checks cover all2048 neuron bytes of the interior4×4×128 output. No down bias, gain or post-projection residual is loaded.

## 3. Padding is a different, incompatible-by-default address contract

Source13451–13970 computes `CH=q2(s32(H+1)), CW=q2(s32(W+1))`. It exits padding if pointer72 is null or **both** `PH<=CH` and `PW<=CW`.

Every padding element writes sixteen literal zero bytes at:

`pad(g,y,x)=16*((g*PH+y)*PW+x)`, **`g=0..15`**.

That is **sixteen planes /256 bytes per pixel**, not the learned output's eight planes /128. The enclosing pad address envelope, when fully relevant, is `256*PH*PW` bytes. `.b32` stores of0 mean raw zero bytes here, not F32 output neurons.

Per-CTA padding executes the ninth barrier13504 iff

`(oy<PH && oy+4>CH) || (ox<PW && ox+4>CW)`.

The predicate is CTA-uniform under uniform ABI/CTA IDs. Following it, linear CTA thread IDs below256 distribute a loop over `i=tidLinear+k*ntidTotal <256` (remainder prelude plus four-way-unrolled body, preserved in CFG). Set `g=i&15`, `y=oy+(i>>6)`, `x=ox+((i>>4)&3)`; write iff within PH/PW and **not** `(y<CH && x<CW)`.

CTA `(0,0,0)` additionally clears uncovered bottom/right strips, with actual grid-dependent boundaries:

```
coverY = q2(s32(Y+8*nctaid.y-8)) + 4
coverX = q2(s32(X+8*nctaid.x-8)) + 4
limitY = min(coverY,PH)
bottomStart = max(limitY,CH)
rightStart = max(min(coverX,PW),CW)
```

Bottom: `bottomStart<=y<PH`, `0<=x<PW`. Right: `0<=y<limitY`, `rightStart<=x<PW`. Both loop over all16 planes, using source remainder/four-way-unrolled clearing loops. Their entry guards and signed/unsigned divisions remain in CFG/source; these rectangle descriptions assume the positive/nonoverflow domain.

**Concrete source-address counterexamples, not proposed live shapes:** H=W8,PH=PW8,grid1×1 learns2048 unique bytes but clears12288 unique bytes through16384, overlapping1536 learned bytes. H=W4,PH=PW4 overlaps384/512 learned bytes. Odd H9/W11 with PH=PW8 also overlaps1216 learned bytes. The padding guard uses ceil-half, leaving odd fringe semantics distinct from trunc-half learned-store guards. No repair, size substitution, silent channel-count halving, allocation claim or host reconciliation is justified by the packet.

## 4. Publication and ownership limits

All source barriers are retained, including consecutive13103/13104 and conditional13504. No inter-kernel or inter-CTA publication proof is supplied. Extents above are source byte envelopes only. Neither pointer separation nor nonaliasing, allocation ownership, launch compatibility, host-selected dimensions or producer-consumer visibility is established.

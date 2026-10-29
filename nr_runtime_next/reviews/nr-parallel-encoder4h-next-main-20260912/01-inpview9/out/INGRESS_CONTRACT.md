# Block9 4H-INPVIEWC128 ingress — source-derived, conditional runtime contract

## ABI and domain

Exact entry `cc_tinlayout_fused_swin_4h_128_4_inpview_fp8`, 88-byte aligned-8 aggregate. Loads (source lines12–17): input pointer+0, output+8, own slab+16, signed H/W+32/+36, signed X/Y+40/+44, signed effective overrides+80/+84. Bytes24–31 and48–79 are unread. In particular +24 is NOT a residual pointer; +72 is NOT a second output here. No auxiliary wait/signal/poll loads occur.

Lines34–37 really implement `EH=(ABI80>0?ABI80:H)`, `EW=(ABI84>0?ABI84:W)`, independently. These are **4H source** fields, not borrowed 2H assumptions. No device ceil-to8 is applied to EH/EW. Assume compatible `(32,4,1)` CTA: `l=laneid in[0,31]`, `w=tid.y in[0,3]`, `Y0=s32(Y+8*ctaid.y)`, `X0=s32(X+8*ctaid.x)`. Simplified formulas below require nonoverflow arithmetic; exact signed/wrapping ops and guards are in SOURCE/OPERAND/CFG maps.

## Sixteen 4-byte reads/thread, eight planes total

For each thread, source lines38–828 enumerate:

```
g in {2*w,2*w+1}; dy in {0,2,4,6}; dx in {0,4}
y=Y0+l//16+dy; x=X0+(l//4)%4+dx
read iff (EH==1 or 0<=y<EH) and (EW==1 or 0<=x<EW)
y'=0 if EH==1 else y; x'=0 if EW==1 else x
byte=16*((g*EH+y')*EW+x') + 4*(l%4); width=4
```

Singleton broadcast is **pixel dimension exactly1**, independently for H/W. It is not ordinary4H's `(H&-4)==4` tile broadcast. Invalid reads leave literal raw32 zero; no load or speculative allocator padding is inferred. Source branch detail, including short-circuit predicates, is retained. Guards refer to effective dimensions, not rounded output dimensions.

Canonical C128 planar16 ingress (logical c convention matching the supplied DS8 contract):

```
pi16(c)=4*((c%8)//2)+2*((c//8)%2)+c%2
input(y,x,c)=16*(((c//16)*EH+y)*EW+x)+pi16(c)
```

There are **eight planes**, each `16*EH*EW` bytes, total source-address envelope `128*EH*EW` bytes for positive dimensions. Not F16 storage; the four transported bytes are raw E4M3. Sixteen per-thread reads must not be confused with sixteen planes. For an interior8x8 tile the 128 threads read8192 distinct bytes.

Raw reads are packed without decode/reencode into four shared stores839/848/857/866:
`shared=512*w+16*l+2048*t`, width16, `t=0..3` in 2x2 spatial4x4 order. Shared extent8192. The checker independently maps all8192 byte tags from planar ingress to this tiled MMA representation; there is no identity-MMA test.

## HH rounding and DS8 compatibility: conditional, not host acceptance

The supplied HOST_REPORT verifies static DS8 ordered O0 -> block9 I0 and current4H I0 aggregate+0. It does **not** supply the complete 4H aggregate H/W/+80/+84 stores. Its zero-override and R8 proofs are specifically the 2H common host path; transplanting them to block9 would be unsupported.

If an external 4H host supplies rounded `HH=R8(h9), WW=R8(w9)`, then zero/nonpositive overrides make effective dimensions HH/WW. Positive overrides preserve their own source strides instead. This is a conditional expression, not a recovered live 4H launch. The device itself computes output `H4=trunc0(H/4), W4=trunc0(W/4)` at7375–7382, not ceil. When H/W are positive multiples8 this represents the rounded HH/WW tile envelope, but it never silently rounds EH/EW.

The supplied DS8 contract states learned primary bytes use `HD=trunc0(H8/2), WD=trunc0(W8/2)` and the same pi16/eight-plane map. Thus direct layout agreement requires **EH=HD and EW=WD**, plus compatible coordinates, initialization and publication. Static handle routing alone is insufficient. Example, not a live shape: a4x4 learned producer plane has stride256 bytes; a hypothetical rounded8x8 consumer plane has stride1024. Matching pointer and channel count cannot reconcile that discrepancy. A real positive4/4 override would select matching source strides, but this packet does not prove such host values.

DS8 padding is a separate source contract using PH/PW and **sixteen planes**, `16*((g*PH+y)*PW+x)`, g0..15. Its conditional overlapping/stride hazards from DS8_OUTPUT_CONTRACT are retained, not repaired into eight planes. Neither `256*PH*PW` padding envelope nor this consumer's `128*EH*EW` envelope is allocation evidence. No producer bytes, live dimensions, allocation extents, ownership, aliasing, initialization or fences were acquired here.

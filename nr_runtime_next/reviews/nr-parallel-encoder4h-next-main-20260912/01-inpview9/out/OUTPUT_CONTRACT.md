# Block9 ordinary tiled C128 output

ABI+8 is the sole output pointer; +80/+84 affect input only. Source does not guard output stores by pointer-null, does not pad/clear output and has no DS-style secondary pointer.

Let `q4=truncation toward zero`, `H4=q4(H), W4=q4(W)`, `ty=q4(Y0), tx=q4(X0)`, compatible CTA `(32,4,1)` and lane/head l,w. For a,b in{0,1}:

```
GY(a) = Y0 > -4*(a+1) && ty+a < H4
GX(b) = X0 > -4*(b+1) && tx+b < W4
store iff GY(a) && GX(b)
byte = 2048*((ty+a)*W4+tx+b) + 512*w + 16*l
width = 16 raw bytes
```

The four actual `st.global.L1::no_allocate.b128` instructions are9917,9938,12431,12448. Their local b128 moves are real counted instructions. Final half2 MMA accumulators convert with `cvt.rn.satfinite.e4m3x2.f16x2`, then pack. No F16 output neurons are implied by half MMA D or b128 transport. Guards are tile guards, not per-pixel clipping; especially do not replace the exact negative-origin inequalities by floor-divided pixel tests.

Canonical map, positive nonoverflow H/W, `0<=y<4*H4`, `0<=x<4*W4`, c0..127:

```
m=4*(y%4)+x%4
out(y,x,c)=2048*((y//4)*W4+x//4)+512*(c//32)
          +64*(m%8)+16*((c%8)//2)+4*(m//8)
          +8*((c%32)//16)+2*((c%16)//8)+c%2
```

Envelope `2048*H4*W4` bytes, equal to128*H*W only when positive H/W are divisible4. An interior8x8 tile has8192 unique stored bytes; the checker verifies its bijection and address guards. This is the ordinary4H tiled representation, **not planar16 output** and not a 2H/64-channel stride scaled by guesswork.

Both residual forks remain in the numerical graph: first, decoded raw ingress times gain98320 seeds dense mix; second, decoded **quantized intermediate** times gain196912 seeds output mix. The latter is split spatially: top residual loads9010/9019 feed first two stores, bottom loads11539/11548 feed last two. It is not a host skip pointer or unquantized intermediate bypass.

Static byte maps do not establish numerical output equality, live buffer extent, valid launches, aliasing/lifetime, or publication. **Existing ordinary4H native/CPU226-of8192 mismatch remains OPEN**, even if all static checks pass. Main owns first exact numeric freeze/campaign.

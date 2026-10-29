# Implemented mathematical boundary — CPU ONLY

## Source mapping

Paths relative to project root; all bytes in `INPUT_PINS.json`, checked before analysis and again afterward.

- O: `reviews/nr-swin-consumer-main-20260911/source/native/shaders/codec_encode.comp:19–43`, `codec_decode.comp:25–100,103–144`; runtime `native/runtime/codec.cpp:34–43`. These link to the completed audit's frozen9e source manifest, including embedded `codec_shaders.inc`.
- C: `reviews/nr-community-chain-diff-20260911/community/OptiScaler/shaders/dlssnr/precompile/dlssnr.hlsl`, fixed wilsjo2 commit **e237f895623742b761f9e5f00067cb3dc62619f4**. SHA256 **c0aebd916f0cff6a04720bf8111d850e5312e0e7a179c5d8961dc7876d563534**. HPE/gamut at 82–153; Oklab/hue 166–222; sRGB 289–302; knee 324–355; encode 728–775; same-raster resolve 816–839,957–1057,1071,1109.
- Guard is **2.0**, parsed from pinned `community/OptiScaler/Config.h:348` (not guessed from a comment). Pinned `shaders/dlssnr/DlssNr_Dx12.cpp:2787` forwards `cfg.DlssNrMaxRatio.value_or_default()` to resolve. This is the source default, NOT evidence of a real community installation's effective setting.

`codec_cpu.py` extracts separate O GLSL column-major and C HLSL row-initialized matrices, converts both to mathematical row matrices and applies `v @ M.T`. Thus C does not borrow the O hue or AP1 clamp. Common Oklab matrices are equal because the sources actually contain the same decimal constants, not because the implementations were conflated. Source fetch SHA256/Git blob records and frozen baseline linkage are verified locally; no network or shader compiler is invoked.

## Input encoder

Let `a=max(A,0)/white`, white=1 in this task. O runtime clamps white to at least 1; C WhitePoint to at least 1e-4 in this fixed/no-exposure branch. HDR is enabled; C passthrough=0 and reversible mode=0. Alpha passes through.

```
K_O(x) = x                                  x <= .75
         .75+.25*(1-exp(-5.770780*(x-.75)))  otherwise (each RGB component)

Y_C(a) = dot(a,(.2126,.7152,.0722))
rolled = .75+.25*(1-exp(-(Y_C(a)-.75)/.25))
a1 = a*rolled/Y_C(a) if Y_C(a)>.75 else a
K_C(a) = a1/max(1,max(a1))
B_O = E_O(K_O(a)); B_C = E_C(K_C(a))
```

E clamps [0,1], then `12.92*x` below .0031308, else `1.055*x^(1/2.4)-.055`. O uses <= at the threshold; C uses HLSL `step` (high branch at equality) and `max(x,1e-8)` in the high power. D clamps [0,1], then `x/12.92` below .04045, else `((x+.055)/1.055)^2.4`; the same O <= / C < distinction is retained. The CPU avoids evaluating the unused negative-side exponential; this is finite mathematical branch equivalence, not speculative execution emulation.

## Hue and gamut — full RGB, not a grey approximation

For both sources, `Lab = M2 * signed_cuberoot(M1*RGB)`, inverse `RGB = M4*(M3*Lab)^3`, with row matrices:

```
M1 = [.4122214708  .5363325363  .0514459929
      .2119034982  .6806995451  .1073969566
      .0883024619  .2817188376  .6299787005]
M2 = [.2104542553   .7936177850  -.0040720468
     1.9779984951 -2.4285922050   .4505937099
      .0259040371   .7827717662  -.8086757660]
M3 = [1  .3963377774   .2158037573
      1 -.1055613458  -.0638541728
      1 -.0894841775 -1.2914855480]
M4 = [ 4.0767416621 -3.3077115913  .2309699292
      -1.2684380046  2.6097574011 -.3413193965
       -.0041960863 -.7034186147 1.7076147010]
```

Given incorrect/target Lab `i,k`, chromas `ci=length(i.ab)`, `ck=length(k.ab)`:

- O sets `i.ab=k.ab*(ck==0 ? 1 : ci/ck)`, inverse Lab, then converts RGB to AP1, clamps AP1 components >=0, converts back. Its row matrices are `[.613097,.339523,.047379; .070194,.916354,.013452; .020616,.109570,.869815]` and `[1.705051,-.621792,-.083259; -.130256,1.140805,-.010548; -.024003,-.128969,1.152972]`. No final RGB clamp in O.
- C sets `direction = k.ab/ck if ck>1e-5 else (0,0)`, `i.ab=direction*ci`; inverse Lab; then **D65 neutral-axis gamut compression**, not O's hard AP1 clamp, despite the HLSL function name `ClampAp1`.

Actual C HPE matrices:

```
BT709ToLMS = [.30569589 .62271286 .04528636
              .15776262 .76968599 .08807030
              .01933082 .11919478 .95053215]
LMSToBT709 = [5.62059812 -4.57145756  .15577924
             -1.15555585 2.25800438 -.15415806
              .03059913 -.19018011 1.06820532]
```

`adaptive=BT709ToLMS*(.18,.18,.18)`; `d65=LMSToBT709*max(adaptive,1e-8)`; for candidate RGB `v`, `y=Y_C(v)`, `neutral=d65*y/max(Y_C(d65),1e-8)`.
If `y<=1e-8`, scale remains 1. Otherwise each channel with `v_j<0 && neutral_j>v_j` proposes `neutral_j/(neutral_j-v_j)` if `abs(denominator)>1e-8`, else 1. `s=saturate(min(1, proposals))`. Return unchanged v when s>=1; else `neutral+(v-neutral)*s`. Final resolve clamps RGB nonnegative. A low/nonpositive-Y invalid-gamut candidate is not silently assigned another neutral; the implementation preserves this source branch.

## Held-fixed compositor

Every pair consumes **exactly the same saved A=S, saved B, saved raw N=P1/P3/P5**. The new encoders' B outputs are never fed here.

O `o=max(A,0)/white`, C `o=A/white` (the C resolve itself does not pre-clamp originalSample); `p=D(B)`, `n=D(N)`. Saved A is nonnegative, so this distinction is inactive in the image study but separately tested. Define `Yo,Yp,Yn` with O weights `(.212639,.715169,.072192)` or C weights `(.2126,.7152,.0722)` respectively.

```
O r = Yo/Yp                       if Yo<Yp
      (Yn+max(0,Yo-Yp))/Yn         otherwise, if Yn>0
      0                           otherwise
O u = (1-t)*o+t*HueO(n*r,n)
O l = o*(Y(u)/Yo) if Yo!=0 else o
O out = white*((1-color)*l+color*u)

C if Yn<=1e-5: u=o
  else:
    r = Yo/max(Yp,1e-6)            if Yo<Yp
        (Yn+max(0,Yo-Yp))/Yn       otherwise
    u = (1-saturate(t))*o+saturate(t)*HueC(n*r,n)
  f=1/512
  q=(Y(u)+f)/(Yo+f)
  amplified=pow(max(q,1e-6),1+max(t-1,0))
  g=max(MaxRatio,1) = 2
  bounded=clamp(amplified,1/g,g)
  u2=u*bounded/max(q,1e-6)
  out=max(white*((1-color)*o*bounded+color*u2),0)
```

Here t is actual metadata **0.6000000238418579** or separately labelled counterfactual **1.0**; color=white=1. API deliberately rejects unsupported t>1/color>1 even though the source supports additional paths. All three rasters are 768x432, same pixel centers, so O's decode-before-bilerp and C's bilerp-before-decode reduce to the same stored texel, without emulating GPU texture coordinate precision. No matched-residual, reversible replacement, SkinProtection, debug/compare view, exposure texture or new inference is present.

The guard bounds **the floored ratio**, not the exact final `Y(out)/Y(o)` at color=1. Test: `o=p=.2,n=.01,t=1` gives O≈.01, C≈.084477 (<.1), not a strict half-brightness floor; reverse dark-to-bright gives >2x original. It is incorrect to turn shader comments into a strict final-Y theorem. With N=0 O gives `(1-t)*o`, C returns o for nonnegative A.

## Floating-point and invalid-input limits

- Primary arrays: exact captured little-endian half samples promoted to float32 by the hash-pinned loader, then to **float64**. Every half value is exactly representable in both. Matrix/power/exp operations are NumPy CPU mathematics, not SPIR-V/DXIL/native instruction replay.
- Float32 runs are sensitivity checks only: CPU evaluation order, BLAS, FMA contraction, pow/exp approximation, denormal handling, shader compiler transformations and GPU textures are not certified.
- NPZ results retain unquantized float64 RGB plus original alpha separately. They are **not new RGBA16F GPU surfaces**. RNE-half diagnostics use NumPy conversion only. Observed saved-surface differences do not establish RTZ, all-channel rounding policy, or hardware parity. No borrowed HFMA/RZ model reference participates.
- Strict entry/intermediate finite checks precede clamps; missing/wrong-size inputs and nonfinite RGB or alpha fail. No `nan_to_num`, `nanmean` or silent NaN fallback. This intentionally differs from C's SanitizeFinite recovery on invalid data: the reference domain is finite, well-defined math, not an assertion of invalid-input shader equivalence. Active arithmetic divide/overflow/invalid raises; harmless underflow may become zero. Arbitrary finite values whose math overflows or hits a singularity are not claimed supported.
- Only helper functions `load` and `preview` are AST-extracted from the fully SHA-pinned old analyzer (`b7d1cce53e3f09c6aef8c4f0ba20c4c432d0c67c34a89ca26bea7a0342527d2b`). No module top-level code or old compose/main is imported or executed.

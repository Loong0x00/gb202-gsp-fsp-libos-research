# Padded public-worker static prototype

This package retains the planning/contract prototype and adds pure CPU stages
for the now-passing padded encoder and split boundaries. They never start
CUDA/Wine, open the public DLL, or execute PTX, a VM, or a CUBIN; no validated
source-family file is modified.

`PaddedPublicEncoderStage` accepts pre0 `primary_bytes` and `skip_bytes`, then
returns `block22_low`, `block22_high`, `skip4`, `skip8`, and `skip14`.
`PaddedPublicSplitStage` accepts `block22_low`, then returns
`block30_layer3`, `head_8x12`, and `n96_repack`. Constructors resolve local
review dependencies (and encoder weights); forwards perform no file, network,
process, capture, or native-artifact I/O. Both accept a configurable
`reviews_root`, which defaults to the current reviews directory.

## Captured facts used

`public_dll_capture/captured-public-pre0-args.bin` is a 264-byte aggregate:

- source extent at `+208`: `(512, 512)`;
- padded internal extent at `+240`: `(512, 576)`;
- half extent at `+256`: `(256, 288)`.

The two captured ViT repacks both contain `<QQii>` factors `(8, 12)`, hence
`N=96`. The captured decoder-input upsample ends in `(8, 12, 16, 20)`. The
captured post aggregate records internal `(512, 576)` and visible `(512, 512)`.

`prototype.py` records the requested complete topology, including the
non-halving padded transitions `32x36 -> 16x20` and `16x20 -> 8x12`. It also
records paths to the existing transparent exact families and SM120 pure-array
patches, but does **not** import them. The separate encoder/split stage
classes load the accepted padded local families during construction only.

## Finite/fail-closed policy

Boundary bindings require exact byte lengths. FP8 ports reject either E4M3 NaN
encoding (`code & 0x7f == 0x7f`). Unknown port names, malformed captured
records, and all source/patch drift fail rather than selecting a fallback.

## N96 attention status

**Not generalized.** The existing N64 tensor attention implementation explicitly
requires a 64-key denominator and contains only the `start=0` pass. A `64+32`
denominator partition is recorded only as a proposed work split; it has no
source-derived reduction order, accumulation/rounding proof, reciprocal-domain
proof, or N96 output comparison. `execution_blocker()` preserves that refusal.

Run static checks only (they do not construct or execute the full model):

```sh
python3 padded_public_worker/static_validate.py
python3 padded_public_worker/test_stage_api.py
```

The new stages preserve the accepted HFMA2 normalization patch, block22
logical-width 18 / zero-cleared 16x20 allocation, block23 partial final
window, and logical 8x10 pool zero-padded to 8x12. These checks do not claim
runtime equality.

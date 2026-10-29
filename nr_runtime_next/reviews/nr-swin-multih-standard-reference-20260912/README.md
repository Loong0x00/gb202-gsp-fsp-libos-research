# Plain standard 2h / 4h / 8h Swin CPU reference

## Result

`reference.py` executes the literal original plain entries below as bounded CPU warp coroutines, through every original CTA barrier and `ret`, using the exact historical byte slabs. This is an executable operational neural-network model (FP8 ingress, learned attention/MLP instructions, FP8 packed output), not a guessed dense/checkpoint-axis reconstruction.

| family | literal entry | graph block / slab | static instructions | warps | dynamic FP8 MMAs | barriers | output bytes |
|---|---|---|---:|---:|---:|---:|---:|
| 2h | `cc_tinlayout_fused_swin_2h_64_2_fp8` | 6 / `block6.layer0.layer` | 4845 | 2 | 832 | 6 | 4096 |
| 4h | `cc_tinlayout_fused_swin_4h_128_4_fp8` | 10 / `block10.layer0.layer` | 4804 | 4 | 2816 | 10 | 8192 |
| 8h | `cc_tinlayout_fused_swin_8h_256_8_fp8` | 16 / `block16.layer0.layer` | 5300 | 8 | 10240 | 8 | 16384 |

The artifact is CPU/static only: no GPU, Wine, host executable, installation write, PTX assembly, PTX downgrade, or source rewrite occurred. `MODULE_HEADERS.txt` records the literal source module `PTX 9.4`, `sm_120`, and 64-bit-address headers; `plain-*.ptx` are exact entry byte slices.

## Own ABI, geometry, barriers, and weights

Each source declaration independently proves an 88-byte aggregate. The reference accepts only this explicit own ABI acknowledgement:

```
plain-{2h|4h|8h}-input0-output8-slab16-hwxy32
```

* `+0` input, `+8` output, and `+16` slab are distinct, non-null, non-overlapping byte spans.
* `+32,+36,+40,+44` are signed `H,W,X,Y`. There is **no inpview override**, DS, wait/protocol, chained publication, readiness assumption, or borrowed query scalar in this reference.
* All other aggregate bytes remain poisoned (`0xA5`), not assigned semantics. The bounded supported geometry is H/W and X/Y divisible by four, H/W 8..64, and effective XY in -64..64.
* Shared capacity is source-checked as 4096/8192/16384 bytes. The scheduler requires respectively 2/4/8 complete 32-lane warps at the same original `bar.sync 0`; uninitialized shared reads and RAW/WAR/WAW races fail.
* The only accepted learned bytes are `block-2h.bin`, `block-4h.bin`, and `block-8h.bin`. Unknown/unread bytes stay in the slab; they are never zero-filled or NaN-repaired.

`SOURCE_MANIFEST.json` records hashes and exact source ranges. `selftest.py` independently reads the literal `WEIGHTS_HT.bin` raw ranges and the safetensors payload ranges, verifies byte equality and hashes, and joins them to `architecture.json` blocks 6/10/16. The architecture types at those indices spell `*_shifted_*`; that historical graph spelling does **not** establish native launch selection or justify a shifted-name axis inference. The selected PTX entries are exactly the plain names in the table.

## Numerical and packed-tensor contract

Callers must explicitly supply all three policies; `reference.policies()` supplies the checked CPU reference choices:

* MMA: finite E4M3 dot plus FP16 C with RN-even FP16 after **each original k32 MMA**;
* RCP and RSQRT: explicit RN FP32 substitutes on their accepted finite domains.

These are not a claim of native tensor-core accumulation, `approx.ftz`, contraction, or bit parity. Unsupported nonfinite arithmetic rejects rather than being repaired.

Ingress is physical E4M3 `[channels/16,H,W,16]`:

```
input_offset(H,W,row,col,c) = 16 * (((c//16)*H + row)*W + col) + c%16
```

Output is an independently enumerated packed 4x4 microtile layout (with explicit family channel count `C`):

```
m = 4*(row%4) + col%4
lane = 4*(m%8) + (c%8)//2
j = 4*((c%32)//16) + 2*(m//8) + (c%16)//8
offset = C*16*((row//4)*(W//4)+col//4) + 512*(c//32) + 16*lane + 2*j + c%2
```

The confined tests prove both maps are bijections for each 8x8 fixture, ledger every actual input/slab load against tagged bytes, and ensure original stores cover exactly the independent packed output map.

## Run and verify

```sh
PYTHONDONTWRITEBYTECODE=1 python3 reviews/nr-swin-multih-standard-reference-20260912/selftest.py --record
```

The four confined tests run full forwards (8h first), parse all source instructions, count every dynamic MMA and barrier, verify source/raw/checkpoint provenance, test independent layouts/tags/operands, reverse warp scheduling, and negative ABI/slab/policy/size/CTA/order/missing-byte failures. The synthetic fixture output hashes are recorded in `VERIFICATION.json`; they are reproducibility values, not native goldens.

## Remaining boundary

This completes only the bounded CPU/static plain-entry forward for the supplied 8x8 synthetic physical FP8 inputs. It does **not** claim native PTX-versus-cubin/variant selection, launch dimensions, stream/inter-CTA ordering, activation capture, predecessor/consumer binding, DS bridge, wait/chained behavior, dark-scene diagnosis, or native numerical parity. In particular, the known native 4h **226/8192 gap remains unresolved**; the successful 4h CPU forward is not evidence of native parity across that boundary.

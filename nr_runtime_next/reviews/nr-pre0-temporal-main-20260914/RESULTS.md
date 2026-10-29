# PREBLOCK0 temporal recovery — CPU-only

## Result

Recovered the nonzero-counter temporal ingress into a **transparent, pure-array CPU model**:

- `T0`: selected Color/Backbuffer → normalized source RGB features 4–6.
- `T1`: `dlssnr_prev_output` → five-tap cross-cubic reconstructed guide RGB 7–9.
- `T2`: `DLSSNR.MVec` → one motion sample/reprojection per pixel.
- `T4`: `DLSSNR.ControlMask` → mask Y/Z tone/structure features 11/12, independent of counter.
- `T3`: PTX selector-X math is implemented and full-output checked only behind an explicit non-frontend `selector_x_only` proof. The recovered frontend route passes `R9D=0`; **Depth is not substituted into T3**.

The accepted host family is nonzero **full-u64** counter, successful T1/T2 pair, `Reset==0`, recovered block0 route, T3 null, and optional/non-null T4. `ActualFrontendState` validates the existing 264-byte ABI exactly; it does not patch a partial pair, erase an unknown T3, or invent an image. Reset suppresses the pair but does not claim a counter reset or history clear.

`pure_array_model.py` returns readonly NumPy `skip_C_packed` (+216) and `primary_A_planar` (+248) arrays plus transparent 16-half feature tiles. It has no `Replay`, `Thread`, parser, ctypes/native invocation, or VM dependency. Every texture read uses `SamplerPolicy.sample(handle, raw_x_f32, raw_y_f32)`; all approximate operations use an explicit nonnative callback.

## Extracted branch contract

See `BRANCH_AND_ABI_EXTRACTION.json`, `INTERFACE_AND_STATE_CONTRACT.json`, and `SOURCE_MANIFEST.json`.

PTX source `../nr-pre1h0-main-20260912/original.ptx`, SHA-256
`7ef1fb2650817e1b45b44104e06fac39d9d26c3a2afcd042f915681167a2bba8`:

- Lines 322–328: either-null T1/T2 copies source guide and skips temporal reads.
- Lines 329–390: optional T3 centre/TL/TR/BL/BR strict selector; +168 zero=min, nonzero=max; ties/unordered retain prior selection.
- Lines 392–516: T2.X/Y reprojection and T1 LM/MT/MM/MB/RM source-ordered cubic reconstruction.
- Lines 518–550: separately rounded F16 guide normalization.
- Lines 553–585: T4 mask/control branch.

All 16 features are documented in the extraction JSON. The model preserves FTZ/FMA/F16 rounding boundaries with integer/Fraction raw-bit primitives. It does not emulate native approximate-error bits or hardware sampler semantics.

## Frozen prediction then original-VM comparison

Before formal VM comparison, `freeze_predictions.py` wrote immutable current and heldout array predictions (`FROZEN_ARRAY_PREDICTIONS.json`, receipt SHA `94273c26…acc3091c`). `verify_against_original_vm.py` first rechecked code/data/frozen output hashes, then imported the **test-only** original CPU VM and supplied the same callback object.

`CURRENT_HELDOUT_VM_COMPARISON.json` passes bitwise for all 4 CTAs in each synthetic 16×16 normal-output case:

| Case | Counter | T3 | Per CTA callback samples | Result |
|---|---:|---|---:|---|
| current | 1 | null | 512 | shared +216 +248 exact |
| heldout | 2^32+3 | null | 512 | shared +216 +248 exact |

Each CTA has 16 F16 and 256 FP8 original VM MMAs; +216 has 2048 and +248 has 512 checked bytes per CTA. The heldout counter demonstrates full64 temporal gating while its low32 is only the noise seed.

A separately frozen explicit all-nonnull T1/T2/T3/T4 **nonfrontend** selector test also passes all 4 CTAs (`NONFRONTEND_T3_VM_COMPARISON.json`, 832 same-callback samples/CTA). This is coverage for the PTX T3 math, not a claim that the current frontend binds Depth there.

## Verification

```sh
cd reviews/nr-pre0-temporal-main-20260914
PYTHONDONTWRITEBYTECODE=1 python -B test_temporal_recovery.py
# Frozen receipts already exist and are intentionally not rewritten:
PYTHONDONTWRITEBYTECODE=1 python -B verify_against_original_vm.py   # refuses overwrite
PYTHONDONTWRITEBYTECODE=1 python -B verify_selector_t3_vm.py        # refuses overwrite
```

The 9 unit tests pass (`UNIT_TEST.log`). Formal VM receipts are retained rather than rerun/overwritten.

## Explicit non-claims / fail-closed boundary

No game, GPU, network, deployment, PE loading, dynamic native execution, sampler filtering, real texture capture, history copy, history allocation, synchronization, or resource state mutation occurred. Resource format/swizzle/filter/content and the producer/copy path for `dlssnr_prev_output` remain caller-owned opaque callback state. Unknown T3 semantics, single-member history pairs, malformed callbacks, nonfinite consumed values, unsupported mirrors/padding, and unsupported denominators reject rather than become zeros.

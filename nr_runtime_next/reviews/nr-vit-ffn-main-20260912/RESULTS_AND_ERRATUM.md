# Main FFN post-MMA tail — source constants corrected

## Original worker tail is NOT accepted as source-equivalent

Main read original module05 lines181695..181760 rather than trusting the activation name or tests. Worker used(-0.05625,+0.3,+0.9), but the actual source f32 constants and their destination chains are:

| source | f32 bits | exact value | converted half |
|---|---|---:|---|
| r563 -> r568 | bd650000 | -0.055908203125 | ab28 |
| r562 -> r570 | 3ee50000 | 0.447265625 | 3728 |
| r561 -> r572 | 3f650000 | 0.89453125 | 3b28 |

Clamp limits remain−4/+4. The actual instruction order is min,max,abs,FMA,FMA,multiply,FP8 conversion. The worker's substring tests did not validate these constant definitions, and its successful standalone FP8 quantizer comparison did not verify the complete activation.

Examples: source+1 -> half3d25 -> FP8 3a, while old tail returned39; source−4 -> negativezero/FP8 80, while old tail returnedc2. The wrong-tail artifact and its tests remain preserved as historical evidence; no game/model deployment used it.

## Independently checked Main implementation

`source_tail.py` extracts exact decimal-immediate bits from the literal original expand entry, verifies all five constants and the actual destination/use sequence, then implements exact-rational half rounding and E4M3 packing. It does not substitute an activation based on its class name.

`test_tail.py`: four tests pass, including **all63488 finite FP16 inputs** against separately implemented integer-dyadic half arithmetic and quantization. Low/high packed lanes, signedzero, positive overflow/∞ saturation, source constant register roles and wrong-old-tail regressions are checked. This is an independent CPU arithmetic comparison, not a GPU proof.

Positive∞ remains∞ then packs to7e. **Negative∞ clamps to−4; the polynomial is exactly+0, so the final original−∞*0 is NaN**. That case and NaN payloads explicitly reject; the old unconditional infinity-sign preservation was not valid for the actual coefficients. Finite large negative inputs yield negativezero, not an invented negative saturation result.

## Scope and next step

This accepts **only the post-MMA activation/packing tail**. It is NOT a full expand/contract, a slab permutation, host72-byte pointer-role proof, repack_input implementation, or wholemodel result. Four block31/32 slab range records remain useful provenance; named architecture/serializedF16 types do not supply missing dense axes.

New CPU workers separately recover actual FFN host contracts/repack/reduction paths and full nonmock expand arithmetic. OriginalPTX9.4 and all historical inputs remain unchanged. No GPU/Wine/host execution or installed/network changes were performed here.

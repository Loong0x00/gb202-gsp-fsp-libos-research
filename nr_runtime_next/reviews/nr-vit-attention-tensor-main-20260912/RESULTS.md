# Main attention neural-tensor lift

`nn_reference.py` consumes logical Q/K/V axes through their separately proved physical maps, performs half QK dot32, the exact affine/clamp and half-bit exponent, original half denominator tree, FP8 probability conversion, per-K32 RN-half PV and measured-half-input reciprocal followed by half multiply. This is NOT standard softmax.

Full output131072 bytes matches original-instruction CPU grid:
`7f93c03037ec60bfa9093cf9bdf38686754a868a275d953ea1fedb2f8349ab98`.

Constants F32 bits1035427960,1071303771,1069039616,1073553408 convert to half2dbb,3ed6,3dc2,3fe9. Scalar exponent `((bits<<4)+0x4000)&65535` was checked across the complete admitted clamp domain against the original packed-word shift/add0x3ffc4000; it is not an assumed ordinary exp approximation. Denominator sums the pre-FP8 half probabilities; PV uses their quantized FP8 values.

Heads0/31 intermediate checks run all512 original MMA instructions per head, including literal padding warps. For valid query warps0/1 per head:128 score and128 PV operand-origin/C checks,256 D-half checks,16384 probability halves,256 denominator partial and128 final halves,4096 output halves/store placements. These are original arithmetic observers, not tag arithmetic. Other heads' full outputs are matched; all-head per-intermediate observation is not claimed.

Seven tests PASS: current full output/maps, packed exponent domain, independent scalar half denominator tree, hook immutability, wrong K ingress packing rejected, wrong denominator shortcut rejected, first/last receipts. No blanket acceptance of NaN/overflow or out-of-domain reciprocal.

N128 bounded CPU reference only. Local source/evidence imports remain dependencies; not whole-model/native/temporal equivalence. NoGPU/PE/Wine/installed/network changes.

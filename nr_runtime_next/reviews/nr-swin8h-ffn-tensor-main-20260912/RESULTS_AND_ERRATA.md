# Main Swin8h core FFN tensor recovery

## Scope

Original block48 upsample entry/slab and the independently restored prefix are reused read-only. `ffn.forward(features,slab,hooks=...)` is a NumPy NN-facing operator with explicit learned matrices, named logical intermediates and detached immutable hooks. It does not execute a VM/DLL in forward, but still imports local arithmetic/layout helpers; NOT a standalone package/full layer/native/whole-model delivery.

Input/output are64x256 canonical-C packed FP8,16384bytes. M is local4x4-tile-major position. The original full10752-MMA entry is still executed by the separate oracle/checkers; no original instruction/loop/barrier/weight is altered.

## Restored NN structure and source bases

Let `pi(k)=16*(k//16)+2*((k%16)//4)+8*((k%4)//2)+k%2`, from actual C→A producer/consumer byte/element lineage, not identity-by-shape.

- Decode input into original MMA A basis (`A=C∘pi`) and retain canonical-C X for residual.
- Full256→1024 expansion. Original matrix encoding `32768*(h//128)+B(k,h%128,128)`, slab[0,262144), with zero C and eight ordered K32 RN-half steps.
- Original clamp(min+4 then max−4),abs,FMA,FMA,multiply activation, then FP8 RN/satfinite. Coefficients RN-half ab28/3728/3b28; no named activation replacement.
- Eight independent grouped128→32 projections: source hidden basis128*g+pi(k), weight encoding `262144+4096*g+B(k,n,32)`,32768bytes. Four K32 RN-half steps, zero initial C. This is a learned grouped linear stage, NOT an inferred multiplicative gate. FP8 quantize grouped result.
- Full256→256 mixing: group output in A basis, matrix[294912,360448). **Initial C is half(X*gamma)**,256 half coefficients at491520. Eight ordered K32 RN-half steps, then FP8 output. Residual is NOT a late add.

## First predictions, full original-grid proof

First `ffn.py` SHA194b0200ce6fa2641905bd9d3756d6d1a7a72cd84c25df4b8da37d11a1913ec7 unchanged. Before oracle comparison, both first16384B predictions frozen:
- grouped shared SHAcd7598e72fd9956ffa7d1e04b29825c15dd2580e6bc57cb187d141b9c1e98af8;
- FFN shared SHA2c565d325be600cf5328625220d7d1ae960c5d216ca64d2b2374f42ca13b9c5f.
Both match full original shared boundaries at epochs3 and5; original final output remains3da96cddc0606a05fdc173bc333d6adeda7f928f66094aa75cb82418ed18d753.

All original5632FFN MMAs independently verified:
-4096expansion: actual shared epoch1 A addresses, actual slab B byte origins,rawA/B,C/D;
-512grouped: actual activation/quantization/pack element origins including nonidentity pi,actual B origins,rawA/B,C/D;
-1024mix: actual shared epoch3 A addresses and grouped-source labels,actual B origins,rawA/B,C/D, and initial residual source labels.
Also65536neurons' min/max/abs,131072FMA results,65536activation multiplies and65536activation prequant halves;16384residual seed source/gamma bytes and multiply results;16384group/16384mix prequant halves;32768actual shared-store provenance bytes. Total409600scalar-result halves checked, not an output-only comparison.

New heldout low/skip fixture: first prefix/group/FFN predictions frozen before running the full original10752MMA/8ret-warps oracle; all three boundaries matched. Heldout FFN SHAac139265743e76ba25faddada19c0687f235565e6e037002088d150ba9fae9d9, final original output SHAe21aec2c4592ca7ac849cd7a484e322b77c444b9e268604b090d196d75c02e53. This is a boundary heldout, not new all-MMA observer coverage.

## Domain and negatives

- Exhaustive63488finite half activation inputs compared to independent fixed-point integer min/max/abs/FMA/multiply implementation:62585exact matches,903overflow inputs explicitly refused. Native equivalence not asserted.
- Identity hidden-channel basis is rejected at the actual grouped MMA A provenance.
- Wrong late residual is rejected at actual mixing C. On fixed fixture it changes9694/16384prequant halves and97FP8bytes; output-only checks conceal most intermediate differences.
-6testsPASS: full operands,unchangedfirstprediction,identitybasisnegative,late-residualnegative,exhaustiveactivation,hooks/domain/NaN.

## Preserved errors

Worker source report unchanged. Main review in `../nr-swin8h-core-source-20260912/MAIN_REVIEW.md` corrects first-bank offset set, group loop placement/range (no overlap with mixing), mixing warp stride1024 vs4096, attention seed stride8192 vs2048 and early residual placement. Source-only envelope guesses were not adopted as tensor proof.

The first operand checker incorrectly indexed byte-addressed C labels by half index0/1 instead of byte0/2. It failed early residual source identity (odd channels duplicated preceding even labels). `FIRST_OPERAND_CHECK.log` and `CHECKER_BEFORE_C_LABEL_BYTE_WIDTH_FIX.py.txt` preserved. Only observer label indexing corrected; tensor code, original VM arithmetic and weights unchanged. Full entry re-executed and every check passed.

## Remaining

After prefix512 and FFN5632, the remaining4608MMAs cover QKV/attention/value/final projection. They still execute literally; this result does NOT restore their NN semantics or complete the Swin layer. Upstream inputs here are explicit fixtures, not recovered live encoder/decoder states. Original4h226/8192 native mismatch, cross-frame/sync/geometry and standalone model gaps remain. No GPU, PE/Wine execution, game/deployment/network changes.

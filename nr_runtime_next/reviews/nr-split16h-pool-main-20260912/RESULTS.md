# Main original CPU pool -> head -> N64 repack

Exact pool80ABI, CTA32×4, shared8192+16 (TWO async banks), grid4×2 at caller H=W16. This differs from ordinary split projection's eight warps/shared12288+24. An initial unexecuted VM declaration-copy assumption is preserved as `VM_INITIAL_DECLARATION_ASSUMPTION_UNEXECUTED.py.txt`; actual source/host inspection corrected it BEFORE pool execution. No kernel or shared allocation was enlarged.

Full8 pool CTAs each return all4 warps,2048 real MMA independently checked against the second arithmetic implementation. All263168 bytes of real block30 layer3 slab are read. Both outputs are uniquely produced without holes: full131072B SHA c1315f7b4bd215af8c60df6f498f230484b423196cecdf27443809ff4576cc0d; pooled32768B SHA80caf86e9ac3eea859f4705e2716ef532f8e41cbac3a08367ef49abf7290c57e.

Pool source tail gathers prequantization half results with shuffles, three half adds (two pairs then pair totals), then half multiply by source F32 bits1048576000 (0.25 converted to half), before its FP8 stores. Do not replace this with pooling already-quantized full output. A complete independent NN-coordinate pool lift is not claimed yet.

That exact pooled output1 feeds the original final-head40ABI, CTA32×8/grid4×1 at kernel Hp=Wp8, matching the recovered host transformation from block16×16. All4 head CTAs return eight warps and2048 independently checked MMA each. Head65536B SHA9b0df1cff2aa18e5392394ff9f54b0a11aea9f26fa7be3902663d1ca25fafddb. The exact source b32-copy repack then yields N64/65536B SHA20823a4af8a95a5e66f76af48b05ff597b3ed37bc801e2f2d0818f10eeec03ee.

Total24576 original real MMA. Five tests PASS: current host/primary edge witnesses and shape distinction, full receipts/hashes, actual wrong async transaction count refused, exact shared bounds, missing source/skip/pool tail refused.

Inputs to pool are explicitly frozen, nontrivial deterministic physical FP8 fixtures, NOT recovered upstream block30 activations. We used real block30 weights but have not executed or proved the entire encoder producing those inputs. This is a conditional original-CPU composition, not whole-model/native equivalence, nor a pool/head NN tensor lift. No opaque ranges were filled or relabeled as observed live tensors. Old head fixture and result remain untouched.

Subsequent actual N64 ViT admission is in `../nr-vit-n64-main-20260912/`; it does not append64 unknown input tokens. NoGPU/PE/Wine/installed/game/network changes.

# Main accepted bounded projection tensor reference

Full N128 1024→1024 projection, real block32 layer4 slab, explicit four256-K partitions, RN-half per K32, learned skip seeded in z0, original ordered half reductions. All131072 FP8 output bytes match the sealed original-instruction CPU grid (07b7b4ca…). No original buffer or coefficient was changed.

`check_operands.py` executes full four-z groups0/7 with original arithmetic plus shadow byte origins published at actual async completion. Per group:4096 MMA A/B-origin+C/D-half checks,16384 learned skip/coefficient-half-origin checks,16384 prequantization-half and output-byte placement checks. It does not replace arithmetic with tags. Other groups' final output is compared, not every intermediate separately observed.

Five tests PASS: complete maps/nonidentity input basis; full output; missing/NaN/overflow refusal and immutable hooks; wrong producer-C-as-consumer-A hypothesis rejected at original ingress; first/last proof receipts. Logical weights, input, seed, all z partials and output are available to callers.

This remains a finite-domain CPU source-policy component, not native GPU/whole-model equivalence. Local source/evidence imports remain dependencies. NoGPU/PE/Wine/installed/network changes.

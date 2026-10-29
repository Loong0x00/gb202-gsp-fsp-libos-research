Instruction fact: each QK MMA takes its A operand from FP8-packed normalized registers and its B operand from a distinct FP8-packed normalized register set; its C seed is loaded from `rd11 + 8192*tid.y + 689152 + 512*j + 16*laneid`, not from a 2048-byte-stride envelope (source 10537–10682).

Bounded source-only pass complete. REPORT.md records register-level Q/K/V identification, the exact half reduction and RSQRT/scale order, FP8 packs/transposes, and seeded-QK entry. No layout axis, softmax, or named-normalization inference was made.

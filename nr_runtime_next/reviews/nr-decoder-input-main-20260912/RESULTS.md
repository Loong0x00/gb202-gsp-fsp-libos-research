# Main original decoder-input CPU execution

Exact module06 `cc_dec_input_upsample_1024_512_fp8`, own80ABI, ctor0x180073bf0/vtable0x1800bc2a8/+8forward0x1800744b0/+38init0x1800749f0. Full split-unwind forward and init windows are retained.19 current host instruction witnesses verify the distinctly small CTA32×2, shared2048+16, and four-z grid—not inherited four/eight-warps from a nearby projection.

Host fields: p0I[0] input, p8I[1] retained full skip, p16O[0] output, p24O[3] (not read by this plain entry), p32O[1] split counter, p40 optionalO[2] chained flag (plain0), p48 optionalO[4] temp, p56slab, p64..76 rounded input/output H/W. Host requires at least4 outputs; this reference explicitly supplies the optional fifth non-alias temp. It does not prove the null-temp/alias route. No positive output-size override is needed for the8×8→16×16 case; general override handling is source-reviewed but not numerically validated.

Inputs are fully defined: predicted block38 2D ViT output65536B SHA9e98785b… and retained original-CPU block30 full skip131072B SHAc1315f7b…. Their producer connection is established by the outer graph audit. The first is a source-policy NN prediction, NOT a fresh original/native entire ViT-stack capture; upstream pool inputs remain a declared fixture.

All32 CTAs of grid4×2×4 return both warps, each128+128 independently checked real MMA, total8192. Original z0 initializes all65536 temp bytes; z1/z2 use original half RED; z3 merges, upsamples and adds learned full skip, then writes all131072 output bytes. Every input/skip byte and all525312 slab bytes were actually read. Counter=-1 is still an explicit fresh caller condition; no missing temp/output byte is synthesized.

Final output SHA `400f1915123127068305daf6d82cba968cd949b4d267fb7334e53259a3882002`.

Five tests PASS: own host/geometry, full grids/hashes, stale-ready missing temp, actual missing-last-skip byte, and2048-byte/64-thread barrier bounds. Normal CPU ret is not native equivalence. Optional live flag selection, temp alias route, real allocator/epochs and all-size geometry remain open. NoGPU/PE/Wine/installed/game/network changes.

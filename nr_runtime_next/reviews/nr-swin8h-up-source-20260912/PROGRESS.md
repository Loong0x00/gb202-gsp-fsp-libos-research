Source fact: both entries declare one 88-byte parameter object; upsample loads 64-bit fields at +0/+8/+16/+24 and two u32 pairs at +32/+40 (upsample numbered lines 12–17).

Status: source-only comparative analysis complete. REPORT.md records the upsample-only P0/P24 prefix, P16 slab shift (+131552 in late tensors), f16/e4m3 order, shared/barrier protocol, and exact final P8 store equation. No execution performed.

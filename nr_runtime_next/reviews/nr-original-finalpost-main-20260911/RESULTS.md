# Original finalpost CUBIN — first bounded native execution

## Main accepted phases

1. **164130 load-only:** original ELF loaded via CUDA Driver, exact function resolved, attributes queried; no buffer/array allocations or kernel launch compiled into that phase. All CUDA calls/cleanup and Guardian exit0. Binary version120, registers168, static shared0, max threads384. Source/binary/approval preserved in `backups/load-only/`.
2. **164343 one CTA:** the same untouched original ELF, exact `cc_tinlayout_fused_post_block_swin_1h_32_fp8`, grid1×1×1/block32×1×1. All CUDA calls, post-launch synchronization, readbacks and normal context cleanup returned0; Guardian0. Original ELF unchanged.

ELF SHA256 `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`, original API0x86/Mercury1.1 preserved. No PTX/header recompilation, architecture patch, DLL/frontend loading or NVX hook was used. This is not the old CUDA architecture probe.

## Deliberate no-texture boundary

A=B=C=0. Exact original PTX plus all3336 byte-checked SASS instructions support exclusion of all14 TEX sites on both output paths. Raw TEX's high-word ABI remains unresolved for nonzero CUDA texture objects; no masking or invented handle was used. The surface convention has separate compiler-backed witnesses. Full opaque Driver-created surface value is passed unchanged.

Own allocations only: main1472 bytes, skip3072, real slab21808, real blend2; one16×16 RGBA16F surface. The blend allocation is retained because its load precedes the skipped history branch. Input bytes, slab and blend are unchanged after execution. Exactly64 output pixels were finite with alpha1;192 outside pixels retained qNaN poison unchanged.

These are synthetic internal features, **not captured NR activations or image inputs**. Optional absent-A arithmetic is mathematically neutral-source(.5) under the selected decoder, but this does not test native texturing, history, the game's image path or the complete model.

## Operational gates / limitations

Main reviewed the exact no-TEX proof, surface/compiler convention, owned parameter/memory plan and188 CPU packing mutants; reran17 worker CPU tests/checksums. Approval is for a bounded experiment, not prior numerical/runtime equivalence. `run.py` pins inputs/binary, takes benchmark.lock, checks no games and >=4GiB starting headroom, arms Guardian, enforces global31000MiB and a30s isolated-kernel watchdog. It never changes driver/power/network/game settings.

`HOST_DIFF.patch` records Main changes: explicit phased approval, function attributes, checked flush/close/status handling. All earlier worker blocked hosts/gates remain unchanged. No in-flight resources are individually freed on failed drain. Successful cleanup here does **not** fix/validate the unrelated Wine NR teardown issue.

## Numerical result

Initial comparison against diagnostic RNE-half CPU output found80/256 differing half components, each -1ULP. **Do not call that an80-component internal neural error.** The later F32-surface experiment separates arithmetic from surface quantization; see `../nr-original-finalpost-comparison-20260911/COMPARISON.json` and README.

Complete native arithmetic/model equivalence remains false. API0x86 loading, this no-TEX resource binding and this complete bounded kernel execution now have real evidence; broader version/shape/texture compatibility does not follow.

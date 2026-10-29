Concrete fact: block 66 is `cc_tinlayout_fused_swin_1h_32_1_upsample_fp8`, has a 96-byte parameter record, 5,875 instructions, and a 22,784-byte F16 named slab (11,392 elements).

## Scope completed
- Read only the nine supplied artifacts; no executable, native, numerical, network, or filesystem-discovery action was used.
- Traced the 1h source PTX through its final stores and separated its own evidence from the 2h NN comparator.
- Wrote the source-only reconstruction notes to `REPORT.md`.

## Key source facts
- The 96-byte ABI actually loads P0, P8, P16, P24, P32, P80, and P88; P40..P72 are not loaded in this source. P80/P88 are the second input pointer/extent pair, not evidence for a prior 88-byte ABI.
- The actual compute opcode is `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`, with FP8 operands and F16 accumulation. The source does not support an F32-MMA substitution.
- The upsample prefix performs two K=32 passes (source lines 57--304); spatial coordinates use the explicit signed round-up-before-`shr.s32 ...,1` sequence at lines 25--36, and its nearest/edge selection is explicit at lines 59--127 and 129--272.
- The source contains raw Q/K/V projection, separate Q and K square/reduce/`rsqrt.approx.ftz.f32` trees, two query halves, packed score mapping, pre-PV reciprocal normalization, two K=32 PV passes, and final stores (line 14942 onward).

## Limits
This is source reconstruction only. No numerical, native, full-NR, or acceptance claim has been made.

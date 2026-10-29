# Layer-2 FP8 QKV/attention — resumed static boundary

## Result

This resumes **only** this directory and leaves the pre-resume
`attention_reference.py`, `warp_machine.py`, and `PINS.json` untouched. They
are not an accepted attention replay. The actual layer-2 slab remains the
pinned **917,568-byte** `block23-layer2.bin`; it is not joined with layers 1
or 3 and is not interpreted as serialized dense F16.

A fresh, confined static audit now pins the original
`cc_split_swin_16h_qkv_512_fp8` source and parses all **3,360** instructions.
It proves the real 56-byte parameter aggregate, physical source roles, FP8
MMA/approximate-operation inventory, original async/mbarrier/polling
instructions, and the exact first current-VM boundary. This is deliberately a
boundary report, **not** a fake whole-block or softmax implementation.

No GPU, Wine, DLL/PE execution, host execution, installed-file mutation,
sibling CLI, or sibling write was used.

## Pinned source and route

`RESTORED_PINS.json` pins:

* FP8 QKV source `original.ptx`:
  `fb1585fc32da5d6b48fc82015f52fa50392d1bd4c682d65dfd1ff7c3eebb18f7`.
* exact layer-2 slab `block23-layer2.bin` (917,568 bytes):
  `4418029920032fe9b68e7757bd7fc83f87c1fa56ee714db5a015f7cfef12e3a7`.
* separately retained PTX module header (PTX 9.4 / sm_120 / address_size 64).
* the read-only source DLL fingerprint used for the host-byte anchors:
  `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.

The host anchors at `0x18006e2d5..0x18006e309` select the historical QKV
name versus `cc_split_swin_16h_qkv_512_fp8` based on the `_fp8` condition and
create the latter with CTA `(32,4,1)`. Thus it is four warps, not an assumed
16-warp fused block. The historical spelling is not silently treated as the
FP8 route: any future replay must require an explicit conditional-FP8 route
acknowledgement until the route rewrite proof is complete.

The source genuinely reads `%ctaid.z` and `%tid.y`; grid.z therefore cannot
be erased or inferred from a 16-warp model. A nearby common-forward anchor
passes z=2, but its QKV-vtable association is not established in this
confined audit. It is recorded as an anchor only, **not** promoted to a QKV
grid-z contract. The pre-resume `<4` z check is consequently not accepted as
host proof.

## Actual ABI and storage evidence

The only declared aggregate is 56 bytes:

| offset | original load/register | role |
|---:|---|---|
| 0 | `%rd5` | packed physical input base |
| 8 | `%rd6` | packed physical output base |
| 16 | `%rd7` | layer-2 slab base |
| 24, 28 | `%r28,%r29` | signed H, W |
| 32, 36 | `%r30,%r31` | signed X, Y origin |

The entry forms `CTA.y*8 + Y` and `CTA.x*8 + X` before its address/OOB
logic. XY is therefore part of this ABI, unlike the older layer-0 input-view
entry. Output uses original `st.global.L1::no_allocate.b128`; input is staged
through the original bulk copies from `%rd5`; no dense-F16 input or output
map has been invented.

The two source-defined shared allocations are 8192 bytes at alignment 512
and 16 bytes at alignment 8. Four
`cp.async.bulk.shared::cta.global.mbarrier::complete_tx::bytes` operations
transfer 512 bytes each; each has its original `expect_tx`. There are two
mbarrier initializations, two arrival operations, and two polling waits. The
source retains both polling backedges (`$L__BB23_21` and `$L__BB23_36`) and
the learned-loop backedge from `$L__BB23_36` to `$L__BB23_23`. None has been
rewritten into a serialized copy or a barrier-free loop.

## Learned regions and numerics actually observed

These are direct address/dataflow anchors, not a checkpoint-axis reshape:

* At source lines 3789–3796, `4*CTA.z + tid.y` selects a 32-bit item at
  `slab + 917504`; the same scalar path occurs again at lines 6243–6249.
  Each is subsequently converted by original `cvt.rn.f16.f32` (lines 4347
  and 6803). This is a scalar region, not an FP32 substitute for all weights.
* At source lines 4518–4529, `slab + 786432` is the base of a
  `ld.weak.global.ca.v4.u32` sequence feeding the later attention MMA C
  fragments. It is not a default-zero C matrix.
* The source contains 256
  `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`, 32
  `rsqrt.approx.ftz.f32`, and 4 `rcp.approx.ftz.f32` instructions.

A valid executable replay must receive separate explicit policies for that
MMA form, RCP approximation, and RSQRT approximation, with independent
operand/layout and numerical checks. This audit supplies none and calls no
library softmax. It performs no NaN repair, zero-fill, or output synthesis.

## Precise remaining boundary

The retained generic VM rejects the original source before async execution:

```text
static instruction #153 (one based after declarations/labels), source line 221
cvt.s64.s32 %rd48, %r83;
```

The confined parser verifies this position while parsing the complete source.
Adding only signed 32-to-64 conversion would still be insufficient: the next
required semantics include bulk mbarrier-completing async copies,
`mbarrier.expect_tx.relaxed`, elected issuer ownership, phase/token polling,
and the FP8 MMA/RCP/RSQRT policy-oracle checks. No launch/replay API is
published because accepting packed buffers, a CTA/grid.z, or policies before
those semantics are implemented would falsely claim an original `ret`.

Consequently, no full learned-attention output, native equivalence, complete
packed layout, exact QKV grid.z, or projection 1/3 result is claimed here.

## Verification

```sh
PYTHONDONTWRITEBYTECODE=1 python -B \
  reviews/nr-split16h-attention-reference-20260911/test_restored_attention_static.py
```

The test is local to this directory. It hash-checks the source/slab/header,
requires the 917,568-byte slab, parses all 3,360 PTX instructions, checks
critical ABI/XY/packed-I/O/region anchors and original operation counts, and
checks the host CTA/conditional-route byte anchors. It does not invoke legacy
write-proof CLIs or run a GPU/native host.

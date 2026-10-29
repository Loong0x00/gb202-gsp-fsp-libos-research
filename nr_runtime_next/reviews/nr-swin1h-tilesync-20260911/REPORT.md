# Swin1H selected tilesync variant: exact CPU/static comparison

## Verdict

**Arithmetic and ordinary data-store trace equivalence is proven conditionally at PTX level; whole-kernel memory-effect/native synchronization equivalence is false.** The selected kernel is `cc_tinlayout_fused_swin_1h_32_1_inpview_tilesync_fp8`, not the plain `..._inpview_fp8` entry.

The plain entry has **5,505 instructions**. Tilesync has **5,531**: all **5,504 non-return plain instructions** match under a typed, bijective register/label mapping and checked dataflow/control-flow; **26 extra instructions** implement parameter loading, index arithmetic and a publication epilogue. Both retain their final `ret`. This is not a name-based match, numerical sample/checksum comparison, or execution of the plain body masquerading as native tilesync.

No Wine, GPU, installed DLL changes, header changes, activation reads, allocation/lifetime operations, or imports/execution/edits of the separate plain worker were performed. The full common arithmetic body is not reimplemented here.

## Source and actual launch

Unmodified PTX module: `reviews/nr-ptx-bundle-20260911/modules/module-00-dll-000df0e0.ptx`, SHA256 `9fa036fc715cb56c9138a1f931db1314fdd444ed30d1c31f66307a6babc7176a`; original `.version 9.4`, `.target sm_120`, 64-bit addresses. The bundle identifies fatbin SHA256 `c11e2eb6f6eeabadffe340dba74ec8c3f474f4ac4a8ed601d59e04d1d49bda3d`, also present in the actual trace.

Exact entry byte ranges, half-open:

- Plain: `[5724445,5940870)`, 216,425 bytes. Exact equality checked against the other worker's `swin1h-original.ptx`, read-only.
- Tilesync: `[7637809,7855133)`, 217,324 bytes.

`verification.json` records entry/module hashes, instruction mappings, read/definition roles, extra operations, capture hashes, and exact trace lines. `original.diff` is the unnormalized source diff; its size reflects extensive register renaming. No instructions were edited to manufacture the match.

Actual `20260911-145411-observer_on` submissions 2 and 5:

- Selected tilesync entry, module SHA above, grid `(48,28,1)`, block `(32,1,1)`, shared bytes 0, 96-byte argument buffer.
- Both `nr-kernel-args-{02,05}.bin` are identical, SHA256 `3aa1a822d08fc3854b85a163c92867615cb6581835fa55e2e0e005e76dcb1862`.
- Input `0x2507dc00` equals preblock submissions 1/4 aggregate `+248` down-output pointer; independently checked against those 264-byte captures.
- Output `0x2531dc00`; slab `0x12c05600 = 0x12c00000 + 22016`.
- These establish **metadata binding before original submission**, not completed GPU execution or captured activation contents.

## Every used aggregate field

Offsets are decimal bytes in the single 96-byte aggregate.

| Offset / size | PTX meaning from use | Captured value | Plain | Tilesync |
|---|---|---|---|---|
| 0 / 8 | input pointer | `0x2507dc00` | read | read |
| 8 / 8 | data-output pointer | `0x2531dc00` | read | read |
| 16 / 8 | encoded slab pointer | `0x12c05600` | read | read |
| 24 / 4 | H | 224 | read | read |
| 28 / 4 | W | 384 | read | read |
| 32 / 4 | X input-view origin | 0 | read | read |
| 36 / 4 | Y input-view origin | 0 | read | read |
| 56 / 8 | sync-word array base | `0x245e0000` | **not read** | **read** |
| 72 / 4 | positive H override, else H | 0 | read | read |
| 76 / 4 | positive W override, else W | 0 | read | read |

Tilesync never reads bytes `[40,56)`, `[64,72)`, `[80,96)`; their meaning is not inferred. Plain additionally does not read `[56,64)`. There is no sync-flag read, acquire operation, incoming wait-pointer use, or atomic RMW in this entry. The new index uses raw **W and X**, not effective overridden W, H or Y.

## Complete extra program and formula

`extra-instructions.txt` lists **all 26** extras with original PTX line and PC:

1. One new `ld.param.b64` at `+56`; the existing immutable `+72` parameter load is reordered.
2. Eleven integer/predicate/branch operations after the CTA-coordinate reads, before the common body. They compute a row contribution from `W - min(X,0)`.
3. Fourteen epilogue operations after all four guarded ordinary data-store sites: `bar.sync 0`; read `%tid.{x,y,z}`, OR and compare them; branch nonzero thread IDs to `ret`; calculate sync address; store zero with GPU release ordering.

For ordinary non-overflow positive dimensions:

```text
n = W - min(X, 0)
row = 0                         if n == 0
      cta.y * ceil(n / 8)        if n > 0
index = row + cta.x
all CTA threads: bar.sync 0
if tid.x == tid.y == tid.z == 0:
    st.release.gpu.global.L1::no_allocate.s32 [sync_base + 4*index], 0
```

The source supports signed arithmetic/overflow cases not described by unbounded `ceil`. `sync_effects.py` implements the exact signed-32 wrap, arithmetic/logical shifts, signed-wide multiplication and 64-bit address wrap. It independently interprets the original extra-program prefix/epilogue and compares that to a separate closed formula. Neither path runs or approximates a native barrier. Returned events explicitly have `native_completed: false`; no memory is changed.

For the captured launch, `index = 48*cta.y + cta.x`. One intended four-byte zero publication per CTA covers **1,344 distinct words**, addresses **`0x245e0000` through `0x245e14fc`**, byte span **`[0x245e0000,0x245e1500)`**, 5,376 bytes. Both captures produce the same intended address set. This is an address calculation, **not proof those words were actually written or initially nonzero**.

No data-output guard suppresses the epilogue. Even a tile with no ordinary data stores still reaches the barrier and thread-zero publication. `cta.z` is unused in the index; uniqueness for arbitrary 3D grids is not claimed.

## Why the arithmetic/data-store proof is stronger than names

`verify_variants.py` parses all non-declaration entry text, including inline scopes and multi-line packed MMA operands; unknown text fails closed. It checks:

- Every opcode/modifier, immediate, predicate, address expression, vector ordering, destination and source operand of every shared instruction.
- A **bijective typed** register/label map, with special registers fixed (e.g. `%ctaid.x` cannot become `%ctaid.y`). Definitions and reads are explicitly compared, including predicate inputs and MMA read-modify-write accumulator roles.
- Every shared forward branch target and fallthrough order. Plain exit edges now target the barrier; no common-body branch can bypass it.
- Parameter loads are immutable, independent and confined to the initial load group. Only their order changes.
- Every extra definition is disjoint from all shared symbols. The new prefix's zero assignment dominates its skip/join, and neither extra branch changes common-body paths.
- An exact opcode/operand/control/memory whitelist for all extras, including the release scope/value/address and thread-zero guard.

Thus induction over the common forward CFG preserves common register values and ordinary memory-event address/value/guard sequences for the same immutable arguments and same observed input/slab bytes, with the same PTX arithmetic semantics. This covers **256 MMA sites, 32 rsqrt and 4 reciprocal approximation sites**, all FP8 conversions, existing warp collectives, loads, and **all four `st.global.L1::no_allocate.b128` data-store sites**. Approximate instructions being identical does not assert that a CPU policy equals native hardware arithmetic.

The shared global memory operations are unchanged: `ld.global.b32`, `ld.weak.global.ca.v4.u32`, and the four ordinary b128 stores. Existing `mma.sync`, `shfl.sync` and `movmatrix.sync` also match; they are not new tilesync functionality.

The proof does **not** equate all registers (extra registers have real new meanings), all memory effects, timing, races, visibility, completion or final pixels. With arbitrary aliasing/concurrent writers, merely having equal arithmetic PTX is insufficient for equal native observations. The extra release can also fault or modify a location the plain entry never accesses.

## Remaining native barrier/publication contract

The online NVIDIA PTX ISA was consulted; relevant text and fetched-HTML hash are saved in `ptx-memory-order-excerpts.txt` (URL in that file). The static source and ISA support the following limited conclusions:

- `bar.sync 0` is a **CTA** barrier, not an all-CTA/grid barrier. It orders participating threads' preceding memory accesses before their post-barrier accesses. This gathers ordinary output stores before thread-zero publication via the barrier's cross-thread synchronization relation.
- `st.release.gpu.global.L1::no_allocate.s32` is a four-byte **GPU-scope release write of zero**. It is not `atom.*`, `red.*`, an atomic decrement, a compare/exchange, a polling loop, an acquire, or a host completion notification. No atomic RMW instructions occur anywhere in this selected entry; that does not deny the scalar write's PTX atomicity/strong-operation properties.
- `.L1::no_allocate` is a cache policy, **not a substitute for acquire/release synchronization**. Ordinary output stores alone do not replace this publication edge.
- For cross-CTA concurrent consumers, the matching acquire/observation relation must cover the same flag location and sufficient scope (or separately proven API synchronization must order consumption). Barrier-to-release causality can then publish preceding participating-thread data stores. **No such actual consumer protocol or scheduling was proven here.**
- Flag initialization, meaning of zero, initial/stale-zero avoidance, reset/epoch/reuse between submissions 2 and 5, allocation size/alignment, nonaliasing, ownership and lifetime remain external obligations. Numeric pointer relationships are not lifetime authorization.
- Upstream readiness and absence of racing updates to the raw input/slab remain obligations too: this variant contains **no incoming wait**.
- A replacement may reuse the proved common CPU data computation for a bounded reference, but must carry the explicit unresolved publication contract. Dropping the epilogue and calling the result native-identical is invalid. Unsupported atomics/consumer concurrency remain a hard boundary, not a no-op implementation.

The main run's reported observer-off/on pixel identity is not a plain-versus-tilesync ablation, contains no captured GPU activation bytes, and cannot close any of these gaps.

## Verification / reproduction

From project root:

```sh
PYTHONDONTWRITEBYTECODE=1 python reviews/nr-swin1h-tilesync-20260911/verify_variants.py
PYTHONDONTWRITEBYTECODE=1 python reviews/nr-swin1h-tilesync-20260911/test_tilesync.py
```

**19 tests passed.** Tests include exact extraction, exhaustive shared-PC/def-use coverage, both captures across all 1,344 CTAs, thread-zero filtering, 2,000 deterministic random integer cases, signed/overflow/address-wrap boundaries, unused-field independence, and fail-closed mutation tests for arithmetic, predicates/CFG, data-store addresses/values/cache policy, special registers, extra register clobbers, barrier ID, publication value/scope, and atomics. `tests.txt` and `verification-summary.txt` record results. No full-body numeric replay or GPU comparison was performed.

All worker-created files are under this review directory. This checkout is not a Git worktree, so verification relies on exact source hashes/excerpt equality and scoped writes rather than a Git diff of the project.

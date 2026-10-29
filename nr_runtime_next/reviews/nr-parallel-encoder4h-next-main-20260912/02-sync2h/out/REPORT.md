# Independent actual 2H wait/chained static review

## Result and scope

**Confirmed from these three PTX sources: base 4,845 → wait 4,921 (+76) → chained 4,947 (+26) executable instructions.** All common instructions, operands, scoped registers, shared operations, barriers and CFG frontiers match under checked bijections, with the narrowly justified exceptions below. This proves **conditional address/state and common-computation compatibility**, not native visibility, progress, numerical correctness or an observed launch.

Only PACKET.json and its five text inputs were read. The DLL was never opened, scanned, loaded, hashed or statted. Its supplied inode/copy/read-only properties and PTX-to-DLL/source-module provenance were not independently verified. All five text hashes and byte lengths match the packet. Model requested by packet/task: `openai-codex/gpt-6-astra`, xhigh; runtime model identity is not programmatically attested by these tools.

PCs below are **zero-based executable instruction indices**, not source lines. Inline-scope instructions count individually; declarations, labels and braces do not. FULL_OP_MAPPING.json records all 14,713 operations, exact source lines, raw operands, normalized typed scoped symbols, full pairwise maps, label maps and every addition. CFG_MAPPING.json retains the complete, uncontracted CFGs, basic blocks, dominators and natural loops, as well as the comparison projection.

## Complete common core, shared storage and CFG

|Check|base → wait|wait → chained|
|---|---:|---:|
|Common operations covered|4,845/4,845|4,921/4,921|
|Typed register/scoped-symbol bijection size|5,381|5,440|
|Branch-label bijection size|21|29|
|Compared finite-path frontier edges|4,857|4,941|
|Unmatched common operands / CFG comparisons|0 / 0|0 / 0|
|Extra writes to common mapped registers|0|0|

Common storage is one **4,096-byte, align-16 CTA shared allocation** per source. Only its variant-specific symbol name is renamed. Every common memory address, predicate, vector lane, immediate, cache/order qualifier, rounding/saturation modifier, tensor instruction and scoped temporary is checked—not merely opcode histograms. The 88 scoped local registers include repeated `low`, `hl/hu/fl/fu` and `v` declarations with their actual types and lexical scopes.

The only operand commutations are nonsaturating modular `add.s32` at base PCs **9, 11, 3768** → wait **11, 13, 3844**. Integer addition modulo 2^32 is commutative; no floating-point reassociation is used. Base PC28 `mov.u32 ..., %tid.y` moves to wait PC65. Its immutable special-register source, unique destination definition, and domination of every use are checked in both CFGs. Wait→chained needs neither commutation nor motion.

Common static inventories include 304 `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`, 192 `fma.rn.f16x2`, 8 `st.shared::cta.v4.u32`, 20 `ld.shared::cta.v4.u32`, 32 butterfly and 72 indexed shuffles, and four final global b128 stores. These counts supplement, not replace, full operand/CFG checks. No neural or original numeric execution was performed.

### All six common barriers, plus both additional barriers

All are exactly `bar.sync 0`; none was removed, merged or replaced by CPU ordering.

|Common barrier|base PC|wait PC|chained PC|
|---:|---:|---:|---:|
|1|1579|1655|1667|
|2|2745|2821|2833|
|3|3691|3767|3779|
|4|3811|3887|3899|
|5|4735|4811|4823|
|6|4843|4919|4937|

Incoming adds wait **PC74 / source line89**, mapped to chained **PC86 / line102**, before common data reads. Outgoing adds chained **PC4938 / line12842**, immediately after common final barrier4937 / line12841. Leader detection4931–4936 precedes these two exit barriers; nonleader branching4939 follows **both**. Source barrier totals are **6 / 7 / 8**. Actual CTA convergence/launch shape remains a condition.

### Fresh 2H math loop: do not import 1H's zero-loop result

Base has **one real natural loop**, backedge **1507→613**; wait maps it to **1583→689**, chained to **1595→701**. It is not merely a lexical backward jump. Base609 initializes `%r4268=0`; base612 initializes `%p138=true`; header613 copies `%p138` to `%p3`. Tail1505 writes `%r4268=1`, 1506 writes `%p138=false`, and 1507 branches on the saved `%p3`. All definitions are checked. Thus the common body executes with scalar index **0 then 1**, then exits. Header614 shifts the index by11 and615 widens/multiplies by4; that address contribution is 0 then8,192 bytes. No body arithmetic was executed on CPU.

Wait additionally has natural backedges **118→120 (rows), 127→129 (columns), 137→132 (poll)**; chained maps these to **130→132, 139→141, 149→144**. Row/column backedges can be textually forward because of block layout. Natural-loop counts are **1 / 4 / 4**; lexical backward-edge counts are **1 / 6 / 6**. Full CFGs preserve them all.

The common-frontier comparison follows finite paths across added operations and separately handles the pure `%tid.y` motion. It does **not** claim that an inserted poll terminates, erase it operationally, or equate its memory semantics with the base.

## Fresh ABI and exhaustive additions

All three entries independently declare `.param .align 8 .b8 ...[88]` and `.maxnreg 168`. Source loads establish:

|Bytes|PTX role|
|---|---|
|0 / 8 / 16|common input / regular output / parameter-weight pointers|
|32 / 36|current H / W|
|40 / 44|current X / Y origins|
|48|64-bit incoming counter pointer: wait PC0, chained PC1|
|56 / 60|previous X / Y: wait PC4, chained PC5, `ld.param.v2.b32`|
|64|64-bit outgoing counter pointer: chained PC0|

Bytes24,72,80,84 are not loaded by these ordinary sources. These offsets are not borrowed from 1H. The host's 88-byte aggregate is contextual corroboration only.

**Every +76 incoming operation** is identified in FULL_OP_MAPPING.json. Inclusive wait-PC partition:
- **0,4:** incoming pointer and previous XY loads (2).
- **22–43:** previous-grid width/height counts, including zero cases (22).
- **44–63:** predecessor overlap bounds (20).
- **64,66–74:** x/z leader inputs, OR with moved common tid.y at65, row-empty/leader branch, added entry barrier (10).
- **116–137:** complete row, column, signed address, poll, ready, sleep and loop branches (22).

Common base61 is correctly mapped to wait115 (`bra.uni` to the common join), **not** to the visually similar poll backedge137. This ambiguity was caught and repaired using CFG targets; skeleton-only matching is not accepted evidence.

**Every +26 outgoing operation**, inclusive chained PCs:
- **0:** signal pointer load (1).
- **45–55:** own-width count and outgoing row-base computation, with zero branch (11).
- **4931–4936:** independent exact leader detection (6).
- **4938–4945:** extra barrier, nonleader exit branch, ctaid.x, slot add, signed wide byte offset, pointer add, zero literal and GPU-release store (8).

Wait's entire 76-operation incoming addition maps into chained unchanged under alpha/CFG mapping. Chained's common final barrier4937 remains separate from added4938.

## Actual poll, leader, state and memory scope

Wait132 / line159 and chained144 / line172 are exactly:
`ld.relaxed.gpu.global.L1::no_allocate.s32`.
Next instruction is `setp.gt.s32 value,-1`; the taken branch advances to the next slot. Therefore **ready = signed value ≥ 0**, including **0,1,INT_MAX**. **Pending must be signed negative**, e.g. `0x80000000` or `0xffffffff`, not just nonzero.

A pending read executes literal64 → `nanosleep.u32` at wait136 / line165 (chained148 / line178), then unconditionally returns to the poll. This is a requested source operand, not a measured duration, deadline, timeout or progress bound. Only CTA thread **(tid.x,tid.y,tid.z)=(0,0,0)** polls. Nonleaders go to the incoming CTA barrier; leader rows with no overlapping columns also avoid polling.

After both exit barriers, only the same exact leader performs chained **PC4945 / line12850**:
`st.release.gpu.global.L1::no_allocate.s32`, storing literal **zero**.

There is no acquired-value load, acquire fence, membar, atomic RMW, or system-scope publication operation in these sources. Ordinary data loads include weak/cached global loads. The GPU-relaxed reader, release-zero writer and subsequent CTA barrier are **not an explicit GPU release/acquire visibility proof**, and certainly not CPU/system ordering. Neither a native bug nor native correctness is inferred.

No incoming instruction initializes counter memory. Correct negative pending initialization before consumers, publication of initialization, absence of late reset, allocation lifetime, disjoint/intentional aliases, valid addressing, and matching invocation/epoch are external conditions. The single 32-bit slot carries no epoch tag or generation comparison: stale nonnegative state can pass immediately; stale negative state can remain pending. There is no increment/decrement protocol implied by the word “counter.”

## Exact predecessor/address arithmetic, including wrap

Let `u32` retain low32 bits, `s32` interpret them signed, `u64` retain low64 bits, and `td8` truncate signed division by8 toward zero. Every indicated 32-bit add/subtract/multiply wraps. Define:

```
N(D,P): n = s32(D - min(s32(P),0))
        return 0 if n==0 else u32(td8(s32(n-1)) + 1)
Tx = s32((u32(ctaid.x)<<3) + X)
Ty = s32((u32(ctaid.y)<<3) + Y)
NX = N(W,previousX); NY = N(H,previousY)
B(d,N): d = s32(d)
        lo = u32(max(d,0)) >> 3
        e = u32((u32(d+7)>>3)+1) if s32(d+8)>0 else 0
        hi = min(s32(e),s32(N))
(lx,hx) = B(Tx-previousX,NX)
(ly,hy) = B(Ty-previousY,NY)
```

Rows iterate from ly to hy-exclusive, and columns from lx to hx-exclusive, using the actual signed entry comparisons, modular increments and equality latches. For nonoverflowing ordinary dimensions/origins, this is the intersection of the current **8×8** rectangle with the predecessor's **8×8** tile grid, clipped to predecessor tile counts. There are at most two rows × two columns. Do not replace the wrapped signed formula by unconditional mathematical ceil/floor at extreme inputs.

For selected predecessor `(ix,iy)`:
`incoming = u64(wait_pointer + 4*s32(u32(iy*NX + ix)))`.
Chained outgoing:
`outgoing = u64(signal_pointer + 4*s32(u32(ctaid.y*N(W,X) + ctaid.x)))`.

Crucially, low32 slot wrap is followed by **signed** `mul.wide.s32`, not `4*u32(slot)` zero-extension. Outgoing width uses **current X**, incoming width uses **previous X**. Incoming bounds use the consumer's current H/W; no previous dimensions are passed separately.

Example H=W=16, CTA(1,1): current(-4,-4), previous(0,0) reads predecessor slots0,1,2,3 with stride2, while its own outgoing stride is3 and slot4. Current(-4,0), previous(-4,-4) reads slots4,7 with stride3; own stride is3. These are conditional block6/7-style geometry examples, not observed allocations or launches.

Address equality holds when consumer wait handle equals producer signal handle, previous XY describes that producer, the producer slot coordinates correspond, and the producer's outgoing stride matches the consumer's incoming NX (matching W suffices). The same low32 arithmetic and signed widening then produce identical addresses. Producer H/grid coverage must also cover the selected rows, and allocated aligned slots must be valid. Release-zero is compatible with the freshly derived ready predicate. Wrong width/stride, stale state, wrong handle or mismatched epochs defeats this conditional reasoning.

## Host configuration boundary and unverified claims

HOST_REPORT.md reports registrations and dispatch conditions permitting **5 tilesync → 6/7 chained → 8 DS-wait** if G, variant handles and appended auxiliary handles are present. Registration operands (32,2,1) are not an observed launch. Supplied ordinary entries are `_fp8`; actual name/handle mutation and selection remain open.

**Neither block5 inpview-tilesync nor block8 DS-wait PTX is supplied here. Neither is alpha-closed by this review.** A generic third origin transition in the scripted geometry cases does not validate DS8's source. No downstream4H/decoder, learned slab, graph execution, allocator or initialization closure is added. The 1H report was context only; every 2H opcode, offset and loop conclusion above was freshly checked.

Explicitly unverified: real launch/convergence; FP8 selection; actual H/W/origin provenance; pointer, extent, alignment, alias and layout compatibility; producer coverage/padding; allocation/initialization/reset and epoch protocol; submission/scheduling, residency, fairness and eventual counter visibility; GPU release/relaxed data visibility; CPU/system visibility; original neural values or whole-network numerical/native acceptance. No GPU, Wine, network, game, deployment, gates, nested agents or outside discovery was used.

## Verification and stopping budget

`python -B out/static_checker.py` last run: **61/61 aggregate checks passed**, including full alpha/CFG/typed-scope checks and negative alpha controls. The bounded scalar interpreter checked **555 normal geometry cases + 2,048 signed/wrap cases**, both wait and chained prefixes and chained signal epilogues; normal cases also compare exhaustive geometric tile overlap and matching producer addresses. **26 scripted traces** cover negative→zero, zero/positive ready, permanently negative bounded-cap, stale-ready/late-reset, all three nonleader axes, and empty overlap with a null unused handle. `bar.sync` is only logged as an event, never modeled as CPU ordering. The common numerical core is skipped, not executed.

Parser/alignment development failures are retained in FAILURES.json; no failed intermediate map is the final evidence. READ_LEDGER.json records all reads and projections. Exactly **36 input-file opens across bounded read batches** have been used (each allowed text/manifest read six times); further input reads stop here. Machine maps/traces are compact JSON to keep text-line output bounded. See PROGRESS.md for final artifact-only checks and primary-unit accounting.

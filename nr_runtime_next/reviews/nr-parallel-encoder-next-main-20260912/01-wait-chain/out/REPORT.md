# Ordinary1H base → wait → chained: independent source recovery

## Result

**Conditional common-source closure PASS; complete synchronization deltas recovered. Native synchronization/visibility acceptance remains OPEN.** Actual executable counts are **4902 → 4979 → 5005**, i.e. **+77**, then **+26**.

**Critical correction:** the consumer does **not** perform an acquire load. It polls with `ld.relaxed.gpu.global.L1::no_allocate.s32` and accepts **every signed nonnegative value**, not only zero. Consequently a pending value must be **signed negative**; merely “nonzero” is insufficient. The producer's supplied release-zero claim is state/address-compatible under the conditions below, but these sources do **not** establish a matched GPU-scope release/acquire publication proof.

The user's accepted base1 bounded-CPU status and base2/3 all153-first-grid/core-proof status are retained as **supplied context**, not recomputed or upgraded. No full NN/original numerical execution occurred. No DLL bytes were opened, loaded, executed, hashed, or PE-scanned.

Requested model: `openai-codex/gpt-6-astra/xhigh`, also recorded by PACKET. This worker has no independent runtime-model attestation or model-switch tool; none was attempted.

## 1. Identity and counting

| Property | base | wait | chained |
|---|---:|---:|---:|
| Bytes | 199021 | 201475 | 202331 |
| Source lines | 13552 | 13641 | 13671 |
| Executable PTX statements | **4902** | **4979** | **5005** |
| Basic blocks | 33 | 48 | 52 |
| Conditional branches | 12 | 19 | 21 |
| Natural loop backedges | 0 | 3 | 3 |
| CTA `bar.sync 0` sites | 0 | 1 | 2 |
| GPU acquire / standalone fence / membar / atom / red sites | 0 | 0 | 0 |
| `.pred` register bound | 137 | 148 | 150 |
| `.b16` register bound | 470 | 470 | 470 |
| `.b32` register bound | 4318 | 4364 | 4380 |
| `.b64` register bound | 288 | 291 | 294 |

Entries are respectively `cc_tinlayout_fused_swin_1h_32_1_fp8`, `cc_tinlayout_fused_swin_1h_32_1_wait_fp8`, and `cc_tinlayout_fused_swin_1h_32_1_chained_fp8`. All declare one aligned-8 **96-byte aggregate**, `.maxnreg 168`, and 56 register declarations, including 52 local declarations.

All five non-DLL inputs' byte lengths and SHA256 match PACKET. PTX hashes:

- base: `15ddfc388ff77a4a1ce1bd4bbad79d44df220dda70f731a379eefa1694e0a8cd`
- wait: `40b0839f601a289fd0f21f05779c287e9b866a2c8a2903cb95c14da5a5a5725c`
- chained: `097fa1ebad1f7ef529d1ab13671b26d0c3333680ea33cc29eeef2f9da9fb7d78`

**PC convention throughout:** zero-based executable PTX statement ordinal, **not native byte PC**. Ranges are half-open. The parser handles multiple statements per line, multiline instructions, register declarations, labels, vector braces and lexical scopes. In particular, each local `mov.b128 ...; st.global...;` contributes **two** instructions; declarations contribute none. `PARSED.json` retains every literal instruction, operand, predicate, source-line interval, scope, label and CFG edge.

## 2. Full common arithmetic/ingress/output proof, with exact exceptions

This is **not merely an opcode histogram or a name-based comparison**. `BASE_WAIT_ALPHA.json` checks every token of **all 4902 base instructions** using a bijection over **5230 symbols**. `WAIT_CHAINED_ALPHA.json` checks all **4979 wait instructions** using **5298 symbols**. Every predicate, immediate, operand position, precision/approximation/cache modifier, vector order and label is retained. Builtins and local unnumbered registers remain literally equal. All 52 local declarations and **2996** local scope-open/close events match.

### Base → wait PC map

| Base PC | Wait PC |
|---|---|
| `[0,4)` | `p+1` |
| `[4,11)` | `p+2` |
| `[11,15)` — signed Y/4 | `p+59` |
| `[15,19)` — signed X/4 | `p+51` |
| `[19,59)` | `p+55` |
| `[59,4902)` | `p+77` |

**Three, not zero, literal operand-order changes** require an explicitly checked integer identity, not pure alpha renaming:

- base8 → wait10: `add.s32 %r1, %r21, %r18` → `add.s32 %r1, %r23, %r28` (mapped sources exchanged);
- base10 → wait12: `add.s32 %r2, %r22, %r17` → `add.s32 %r2, %r22, %r29` (mapped sources exchanged);
- base4112 → wait4189: recomputed output Y `add.s32` likewise exchanges its two sources.

Each is a nonpredicated, nonsaturating integer `add.s32`: addition modulo 2^32 is commutative. There is no floating-point reassociation. Base's independent four-instruction signed Y/4 and X/4 groups are scheduled in opposite order in wait. The checker proves their read/write sets disjoint and their instructions pure integer operations. Wait's inserted work cannot clobber any common destination register.

### Wait → chained PC map

| Wait PC | Chained PC |
|---|---|
| `[0,5)` | `p+2` |
| 5, ABI48/52 parameter load | **1**, hoisted |
| `[6,9)` | `p+1` |
| `[9,4978)` | `p+12` |
| 4978 `ret` | **5004 `ret`**, textual correspondence only |

This second comparison needs **no operand permutations**. The hoisted ABI48/52 load crosses only independent immutable parameter loads; dependency sets are checked. Added destinations again lie outside the common map image. Signal bookkeeping introduces no common-register clobber.

### Conditional CFG correspondence, without deleting synchronization

- Base common region **[19,4901)** maps to wait's corresponding instructions, ending at explicit frontier **4978**: **4894 predicate-labelled CFG edges** match exactly. The source-layout wait loop at114..135 is *not* part of this image: the common first successful ingress branch at113 jumps past it to144.
- Wait region **[9,4978)**, **including the actual polling loops and entry barrier**, maps to chained **[21,4990)**: **4988 edges** match exactly. The boundary is chained4990, **not its return5004**.
- Base final label `$L__BB15_28` → wait `$L__BB20_40` → chained `$L__BB21_42` at4990. Thus the old return frontier now enters real outgoing work. Chained's `$L__BB21_44` at5004 is a distinct later return.
- Both full actual CFGs, including all branches/backedges, remain in `PARSED.json` and `EXACT_PC_CFG.md`. No polling edge is collapsed into “ready”; no fence/barrier is replaced by CPU sequential ordering.

All **256** `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`, **104** `shfl.sync` (32 bfly, 72 idx), **32** `movmatrix.sync.trans.aligned.m8n8.b16`, arithmetic, conversions, constants, residual value paths, and all slab loads match. The remaining common global-load census is 65 `ld.global.b32` plus 42 `ld.weak.global.ca.v4.u32`, as well as the four ingress vector loads below. Slab `cvta.to.global.u64` base178 → wait255 → chained267 is preserved. No slab numerical values or live binding were supplied or executed.

**Precisely conditional claim:** at corresponding common points, equal common parameter/register inputs and equal *observed* input/slab load values, with valid PTX warp semantics and allocation/nonaliasing conditions, give equal common expressions, predicates, output addresses and bytes. This is not whole-program termination, memory-trace, inter-CTA visibility, or numeric-model acceptance. The wait can change when/what memory is observed or never finish; chained adds publication work.

## 3. Common ingress and output, not inferred from family names

### Exact memory PCs

| Operation | base | wait | chained |
|---|---:|---:|---:|
| top-left ingress v4.u32 | 57 | 112 | 124 |
| top-right ingress v4.u32 | 96 | 173 | 185 |
| bottom-left ingress v4.u32 | 132 | 209 | 221 |
| bottom-right ingress v4.u32 | 168 | 245 | 257 |
| top-left output b128 | 4131 | 4208 | 4220 |
| top-right output b128 | 4144 | 4221 | 4233 |
| bottom-left output b128 | 4887 | 4964 | 4976 |
| bottom-right output b128 | 4900 | 4977 | 4989 |

Ingress is **`ld.weak.global.cg.v4.u32`**, four vectors = sixteen raw 32-bit words per thread if all four paths load. Output is **`st.global.L1::no_allocate.b128`**, not a release store. Raw ingress, zero-FP8 construction, all FP8 conversions, output packing and guards match exactly. `MEMORY_WARP_PREDICATE_MAP.json` gives all three literal operand records for every mapped memory/warp/predicated witness.

For readability let `s32` wrap and interpret signed32, `tdiv4` truncate toward zero, `x=s32(8*ctaid.x+X)`, `y=s32(8*ctaid.y+Y)`, `qx=tdiv4(x)`, `qy=tdiv4(y)`, `W4=tdiv4(W)`, `H4=tdiv4(H)`. These are *not* floor divisions for negative coordinates.

- Horizontal guards: `GX0=(x>-4 && qx<W4)`; `GX1=(x>-8 && s32(qx+1)<W4)`.
- Row validity for ingress: if `(H & -4)==4`, both rows broadcast row0 and are valid. Otherwise row0 rejects `y<-3 || qy>=H4`; row1 rejects `y<-7 || s32(qy+1)>=H4`.
- For a valid ingress row, `(W & -4)==4` broadcasts column0; otherwise column `s32(qx+dx)` requires `GXdx`. These singleton tests are the actual bitwise expressions, not simply `H==4`/`W==4`.
- On the valid path, row offset is0 for the singleton case, otherwise the source's wrapping `W4*(qy+dy)`. Add the selected column, `shl.b32` by7, then **signed** `mul.wide.s32` by4 and add ABI0 plus `16*laneid` in64 bits. The intermediate32-bit shift is retained; blindly rewriting this as unbounded `512*index` is wrong on overflow.
- On an invalid path the source constructs zero through `cvt.rn.f16.f32`, `cvt.rn.satfinite.e4m3x2.f16x2`, and word duplication. These instructions were not replaced by a guessed byte representation.

Output does **not** use the singleton ingress relaxation. `GY0=(y>-4 && qy<H4)` and `GY1=(y>-8 && s32(qy+1)<H4)`. Each output quadrant requires `GYdy && GXdx`. Base branch PCs4122/4134/4878/4890 skip their stores when negated predicates are true; their mapped guards and reconvergence labels are exact. Top/bottom row addresses use ABI8, the source's wrapping row/column index and shift/mul sequence, plus `16*laneid`; right-hand stores add512 in64-bit arithmetic to that row's left address. No ABI64 secondary output exists here.

## 4. ABI and incoming dependency geometry

All offsets below are **decimal bytes**. Exact load PC table:

| ABI field | Meaning in these sources | base | wait | chained |
|---|---|---:|---:|---:|
| 0 | input | 2 | 3 | 5 |
| 8 | ordinary packed output | 1 | 2 | 4 |
| 16 | slab | 0 | 1 | 3 |
| 24/28 | logical H/W | 3 | 4 | 6 |
| 32/36 | current X/Y origins | 4 | 6 | 7 |
| 40 | predecessor signal base `I` | — | 0 | 2 |
| 48/52 | previous X/Y origins `XP,YP` | — | 5 | 1 |
| 56 | outgoing signal base `S` | — | — | 0 |

ABI64..95 are unused in all three. There are **no separately loaded previous H/W dimensions**. Incoming stride and height bound use **current ABI28/24 with previous ABI48/52 origins**. Therefore correct predecessor shape equality is an external compatibility condition, not proved by the argument names. There is no signal-pointer `cvta`, null check, alignment/range check or epoch field.

### Exact incoming formulas

Use `u32` for a 32-bit bit pattern, `u64` for wrapped address arithmetic, and `tdiv8` for signed truncation toward zero:

```
Nw = s32(W - min(s32(XP), 0))
Nh = s32(H - min(s32(YP), 0))
T(n) = 0, if n == 0
       s32(tdiv8(s32(n-1)) + 1), otherwise
TX = T(Nw); TY = T(Nh)
x = s32(8*ctaid.x + X); y = s32(8*ctaid.y + Y)
dx = s32(x-XP); dy = s32(y-YP)
L(d) = u32(max(s32(d),0)) >> 3
U(d,T) = min(s32((u32(s32(d+7)) >> 3)+1), T), if s32(d+8)>0
         min(0,T), otherwise
XL=L(dx); XU=U(dx,TX); YL=L(dy); YU=U(dy,TY)
row = YL .. YU-1, column = XL .. XU-1       // only if each interval nonempty
slot = s32(s32(row*TX) + column)
load_address = u64(I + 4*signextend32(slot))
```

Wait13..23 computes TX,24..34 TY,35..44 Y bounds,45..54 X bounds; chained counterparts are +12. Row register wait `%r4342`, limits `%r49`; column starts `%r5`, exclusive end `%r6`, loop register `%r4343`; stride `%r4340`; row product `%r7`. Address wait127..129 is `%r62=column+rowProduct`, `%rd7=4*signextend32(%r62)`, `%rd8=ABI40+%rd7`. Chained139..141 uses `%r69`, `%rd8`, `%rd9`.

In the ordinary positive/nonoverflow domain, TX/TY simplify to ceil-div8 of predecessor-origin-adjusted logical dimensions. The selected slots are exactly those predecessor **8×8 tile cells** whose half-open rectangles overlap the current tile rectangle, clipped to `[0,TX)×[0,TY)`. This is a tile-cell intersection claim, not a proof that live tensors or every arbitrary launch satisfy it.

Boundary behavior is explicit: `d=-8` has no overlap; `d=-7..-1` can select index0; `d=0` selects index0 only; `d=4` can select0 and1; upper equality is excluded. Empty rows bypass both loops. Empty columns still traverse the selected rows, but read no signal slots. Normal8×8 overlaps require at most four slots; arbitrary signed/overflow ABI values are governed by the exact formulas, not that simplification. `n-1` wraps before division; e.g. `n=INT_MIN` produces T=268435456, not a positive-domain extrapolation.

### Supplied host-origin consequences, conditional on actual handles/shapes

HOST_REPORT supplies block1 `(0,0)`, block2 `(-4,-4)`, block3 `(-4,0)`. It also describes auxiliary tables, but does **not** resolve live signal bindings. If those adjacent ordinary producer/consumer relationships and equal H/W hold:

- block2 waiting on block1 selects columns `{cx-1,cx}`, rows `{cy-1,cy}`, each clipped to the predecessor grid. Its incoming stride is `ceil(W/8)`; its **outgoing** stride is `ceil((W+4)/8)`.
- block3 waiting on block2 selects column `{cx}`, rows `{cy,cy+1}`, clipped. Its incoming stride is `ceil((W+4)/8)`, matching block2's outgoing stride—not the unshifted stride.
- Example H=W=16, block2 CTA(1,1) reads block1 slots0,1,2,3, but publishes its own slot4 (stride3). Block3 CTA(cx,0) reads block2 slots `cx` and `cx+3`, if in bounds.

These are derived source-geometry examples, not confirmed launches. Block4 is DS; its wait source is **not** among permitted inputs, so no DS-loop equivalence is asserted.

## 5. Actual polling, predicates, backedges, CTA/warp control

All77 wait additions and all26 chained additions are printed **without elision** in `EXACT_PC_CFG.md` and `DELTA.json`. Added wait PCs are exactly **{0,5} ∪ [13,66) ∪ [114,136)**.

Wait's core polling instructions, unchanged in chained at +12:

```ptx
130: ld.relaxed.gpu.global.L1::no_allocate.s32 %r63, [%rd8];
131: setp.gt.s32 %p13, %r63, -1;
132: @%p13 bra $L__BB20_10;       // target123: advance column
133: mov.b32 %r4339, 64;
134: nanosleep.u32 %r4339;
135: bra.uni $L__BB20_8;         // target130: read SAME slot again
```

- `s32(value)>-1` means **ready iff sign bit is clear**. `0`, `1`, and `INT_MAX` all pass. `-1`, other negative values, and bit pattern0xffffffff all remain pending. There is no equality-zero test, decrement, old-value RMW, atomic acquire, arrival count or timeout.
- The source requests nanosleep with operand64; no actual sleep duration or scheduling fairness is inferred. A finite number of negative observations does not prove eventual completion.
- Wait55..60 OR the **full `%tid.x/y/z`** and set `%p9=(tid!=(0,0,0))`. Wait61 tests `YL>=YU`;62 ORs the predicates. At63, `%p11` true branches to **65 `bar.sync 0`**. Only the CTA's thread(0,0,0), with a nonempty row range, enters64→118. This is **not lane0 in every warp**; tid.x32 does not poll.
- At118, `%p12=(XL>=XU)`;119 true→114 advances the row without loads. Otherwise120 forms row*TX,121 resets the column,122→127 computes its address. No extra signal slots are consulted.
- A ready observation takes132→123;123 increments column;124 sets `%p14=(column!=XU)`;125 true→127, false126→114. At114 row increments;115 sets `%p15=(row!=YU)`;116 true→118, false117→65.
- **Natural loop backedges** are wait116→118 (row),125→127 (column),135→130 (poll); chained128→130,137→139,147→142. Row/column backedges happen to point *forward in source layout*. The five lexical backward edges are separately retained; lexical order is not a substitute for loop analysis.
- The entry barrier is wait65/chained77, **ID0 without an explicit participant count**. Static reachability proves that no common ingress/slab load, MMA or output store is reachable from entry while avoiding it. A leader stuck polling can leave nonleaders waiting there indefinitely. There is no early return bypass.

All arithmetic after this barrier retains its warp-synchronous contracts: e.g. idx shuffle base3688 carries literal control31 and membermask-1, and all register-fed bfly masks and their defining instructions are mapped. `mma.sync.aligned`/`movmatrix.sync` and `.bra.uni` annotations are preserved verbatim. Valid CTA participation, warp convergence/active lanes, block shape, and scheduling remain external; this source does **not** establish one warp per CTA. No grid-wide barrier exists. Neither incoming indexing nor outgoing indexing uses ctaid.z, so z-slice uniqueness is not established.

**Memory-order limit:** the poll is `.relaxed.gpu`, followed by a CTA barrier, then ordinary/weak input loads. There is no explicit GPU-scope acquire load or acquire fence anywhere in these entries. A local CTA barrier cannot simply be relabelled as a matching inter-CTA GPU acquire from the producer. `L1::no_allocate`, `.cg`, and a successful zero observation are not substitutes for that missing proof. These sources alone do not close cross-CTA data publication or actual cache visibility.

## 6. Chained outgoing signal, all additional behavior

Exactly26 instructions are added relative to wait: chained **0**, **[10,21)** and **[4990,5004)**. The prefix loads ABI56 and computes `%r4355`, the outgoing row offset, using **current W/current X**, not previous X or input signal stride:

```
Nc = s32(W - min(s32(X),0))
TC = T(Nc)
rowOut = s32(ctaid.y * TC)       // explicitly0 when Nc==0
indexOut = s32(rowOut + ctaid.x)
addressOut = u64(ABI56 + 4*signextend32(indexOut))
```

`TC=ceil((W-min(X,0))/8)` only in the positive/nonoverflow domain. Signal indexing uses logical width, not `%nctaid.x`, override fields or output pixel byte stride. A conventional unique dense signal grid requires grid.z=1, grid.x=TC, signed32-safe indices and enough aligned allocation. A too-wide grid aliases rows; Nc=0 collapses row offsets; grid.z>1 repeats slots. No such launch/allocation check exists here.

The old return frontier enters:

```ptx
4990: mov.u32 %r4346, %tid.x;
4991: mov.u32 %r4347, %tid.y;
4992: or.b32 %r4348, %r4346, %r4347;
4993: mov.u32 %r4349, %tid.z;
4994: or.b32 %r4350, %r4348, %r4349;
4995: setp.ne.b32 %p141, %r4350, 0;
4996: bar.sync 0;
4997: @%p141 bra $L__BB21_44;    // target5004 ret
4998: mov.u32 %r4352, %ctaid.x;
4999: add.s32 %r4353, %r4355, %r4352;
5000: mul.wide.s32 %rd293, %r4353, 4;
5001: add.s64 %rd292, %rd7, %rd293;
5002: mov.b32 %r4351, 0;
5003: st.release.gpu.global.L1::no_allocate.s32 [%rd292], %r4351;
5004: ret;
```

Here the leader predicate is computed **before** the barrier, but the divergent branch and signal store are **after** it. Every returning path passes4996; all output guards converge into4990, including the no-output case. Nonleaders return at5004 without waiting for the leader's later signal store. The leader alone performs a4-byte **GPU-scope release overwrite of zero**; no count is read or decremented. All preexisting ordinary output stores remain unchanged. Wait alone has **no outgoing signal** and does not load ABI56.

## 7. Compatibility with the supplied INPVIEW producer claim—separate from visibility

INPVIEW_SIGNAL_REPORT is a hash-verified **supplied report**, not a newly read producer PTX or inspected DLL. It claims a CTA barrier followed by a thread(0,0,0)-only `st.release.gpu.global.L1::no_allocate.s32` zero through ABI56, with no inputwait; its signal slot is `producer.cy*T(producer.W-min(producer.X,0))+producer.cx`. The source report's zero-width/wrapping cases are also consistent with the formula used above.

Conditional compatibility follows:

1. Set consumer ABI40 to the same allocation/address basis as producer ABI56; ensure actual matching aligned4-byte slots, unique writer ownership and valid extents.
2. Consumer XP/YP must equal that producer's current X/Y. Consumer H/W must equal the producer's **logical signal dimensions**, because consumer has no separate previous-H/W ABI.
3. Then a selected predecessor `(column,row)` reads exactly the producer's slot for that tile. Its release-zero payload satisfies the consumer's nonnegative-ready predicate. Source override dimensions in the producer are not signal-grid dimensions.
4. This establishes **slot/payload compatibility only**. It supplies neither an explicit consumer GPU acquire nor evidence of live GPU visibility, scheduler progress, actual dispatch or cache behavior. Producer publication is an outgoing claim; it does not retroactively establish readiness of that producer's own input/slab (the supplied producer has no inputwait).

The host report's alternate handle/gate/auxiliary descriptions are consistent with ABI40 and56 use, but registration is not actual dispatch. Its noted inpview tail mismatch—source override72/76 versus non-DS host positive overrides88/92—remains open. Ordinary here reads neither pair. No host/DLL claim was independently revalidated against PE bytes under this task's restrictions.

### Initialization, epochs and lifetime remain explicitly missing

- Neither wait/chained nor the supplied producer claim establishes global pending initialization. Local register zeroes are only index setup or the outgoing ready value.
- For this **actual** consumer predicate, pending must be a **negative signed32** value, established before any consumer can accept and before producer completion. An arbitrary positive nonzero initializer is already ready. No exact negative initial value is prescribed by source.
- Initial or stale zero can admit a consumer before current data is produced; late negative initialization can overwrite completion and leave a consumer polling. Reset ordering is not supplied.
- No epoch/generation tag, ABA prevention, reader acknowledgement, consumer retirement or data-buffer lifetime retention exists. Reusing signal/data memory after a read but before all consumers finish can invalidate later input loads. A later chained release is not itself a proof that every consumer of a predecessor has retired.
- Multiple writers sharing a slot can let the first completion publish zero prematurely. Signal buffers aliasing input/slab/output can break the conditional common-value proof.
- Live allocation,4-byte alignment, bounds, shapes/origins, input/slab readiness, backend handle selection, stream/submission ordering, inter-device/system visibility, barriers' participation and GPU fairness remain unverified. Native lowering/ISA version acceptance is also unverified.

## 8. Verification, failures, read budget and artifacts

Final command:

```
PYTHONDONTWRITEBYTECODE=1 python /home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-encoder-next-main-20260912/01-wait-chain/out/static_checker.py
```

PASS: exact counts; all common token maps with only the three disclosed integer commutations; local declarations/scopes; register bounds; both conditional CFG maps; independent scheduling changes; complete frozen delta sequences; barrier-frontier reachability; **7608** scalar prefix checks; **3600** independent tile-rectangle intersections; **3804** outgoing-address checks; **60** leader-predicate checks; **9** finite synthetic traces; **12** rejected negative mutations.

The scalar checker runs **only allowed integer prefix/wait fragments**, using explicit finite observation tapes (including repeated negatives, zero and positive values). It stops at the CTA barrier and never executes it. Outgoing-address arithmetic is a separate fragment ending **before** the release store. It never enters common NN arithmetic, treats synchronization as CPU ordering, defaults a missing read to ready, or models GPU progress. An all-negative trace ends at a bounded cutoff, not an invented completion.

Three checker-development failures are preserved in `CHECKER_FAILURES.log`: a7-token instruction was initially asserted to have8 tokens; the third legitimate commuted add atbase4112 was initially omitted; vector parameter destinations initially hit a scalar-only destination assertion. Each was corrected explicitly and rerun from derived caches, without extra primary reads. The first parser already counted4902/4979/5005 correctly. No failed check is represented as passing.

**27/36 primary read units**, each ≤2000 lines; no tool-truncated primary projection. PACKET was read first. Three PTX files were each ingested in seven bounded chunks; the initial packet/two report reads and explicitly charged identity rereads account for the remainder. `INPUT_READS.json` records exact absolute paths, source-line and byte intervals, per-chunk hashes and total identities. Nine units remain unused; **STOP within budget**.

Key files, all under this worker's `out/`:

- `REPORT.md`, `PROGRESS.md`: result, limitations, chronology/read accounting.
- `EXACT_PC_CFG.md`, `DELTA.json`: **every** added instruction and every actual branch/label target.
- `PARSED.json`: all literal PCs/operands/scopes/full CFGs and dominators.
- `BASE_WAIT_ALPHA.json`, `WAIT_CHAINED_ALPHA.json`: complete token/PC/symbol maps and common-frontier edge checks.
- `MEMORY_WARP_PREDICATE_MAP.json`, `SUMMARY.json`: mapped ingress/slab/output/warp/predicate witnesses and counts.
- `static_checker.py`, `protocol_checks.py`, `ingest.py`: reproducible bounded source/static checks and ingestion.
- `PROTOCOL_CHECKS.json`, `NEGATIVE_MUTATIONS.json`: finite observation traces, address tests, preserved lifecycle hazards and mutation results.
- `INPUT_READS.json`, `DERIVED_READS.json`, `DERIVED_READS.jsonl`, `CHECKER_RUN.log`, `CHECKER_FAILURES.log`, and six named `cache_*` files: evidence and read/failure accounting.

No external discovery/recursive scan, network/native/GPU/Wine execution, DLL inspection, additional agent, deployment, gate action, or input modification occurred. **Unverified items above are not cleared by source equality or the bounded synthetic traces.**

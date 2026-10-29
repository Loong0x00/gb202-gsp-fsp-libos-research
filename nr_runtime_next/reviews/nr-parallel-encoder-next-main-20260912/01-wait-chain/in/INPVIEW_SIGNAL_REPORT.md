# INPVIEW_TILESYNC — independent source-gap closure

## Result and scope

**PASS: the previously UNVERIFIED tilesync source delta is recovered and checked. NOT full base-kernel equivalence, numerical acceptance, or native visibility acceptance.**

The entire base instruction stream has an exact bijective symbol correspondence inside tilesync. Tilesync adds **26 instructions**: a signal-pointer load, signal-index setup, and a **CTA barrier followed by a thread-(0,0,0)-only GPU-scope release store of zero**. There is **no producer wait, polling loop, counter read, atomic RMW, acquire load, or early return** in this tilesync source. Its former base-return frontier now enters synchronization-visible work; it cannot be replaced by `ret` or CPU ordering.

Requested model is `openai-codex/gpt-6-astra/xhigh`, also stated by PACKET. This interface does not independently attest the active runtime model; no model-switch operation was available or attempted.

## 1. Independently measured identity

| Property | base | tilesync |
|---|---|---|
| Entry | `cc_tinlayout_fused_swin_1h_32_1_inpview_fp8` | `cc_tinlayout_fused_swin_1h_32_1_inpview_tilesync_fp8` |
| Bytes | 216425 | 217324 |
| Source lines | 14159 | 14189 |
| Actual executable PTX instructions | **5505** | **5531** |
| ABI | one aligned-8, 96-byte aggregate | same |
| `.maxnreg` | 168 | 168 |
| `.pred` declaration | `%p<364>` | `%p<366>` |
| `.b16` declaration | `%rs<462>` | same |
| `.b32` declaration | `%r<4654>` | `%r<4670>` |
| `.b64` declaration | `%rd<305>` | `%rd<308>` |

SHA256, computed from the complete source bytes and matching PACKET:

- base: `e36a534b79b5361f853f1e8baf4cd63f80d85bd73259e46de36a31321568ce13`
- tilesync: `0d852d65e676316dfa9c26264820b691299d59d7cc9daf9d8b88870f23e1491c`

The supplied reports and prior alpha JSON also match their packet byte sizes and hashes; exact measurements are in `INPUT_READS.json` and `DELTA.json`.

**PC convention:** zero-based executable PTX statement ordinal, ranges half-open; not native byte PCs. The parser splits multiline instructions and multiple instructions on one line, excludes all 56 register declarations, and retains original source lines and lexical scopes. In particular, each inline `mov.b128 ...; st.global...;` is **two** instructions. The provisional line parser's incorrect 5531/5557 counts are preserved, rejected, and not used as evidence.

## 2. Exact common instructions, arithmetic, ingress, output, and CFG

`ALPHA_PROOF.json` checks **every token of all 5505 base instructions**, including every operand position, predicate, immediate, precision/cache modifier, branch label, and return. Its map is bijective over **5810 symbols**. Local register names that are not generated `%...` symbols remain literally equal; all **52 local declarations**, lexical braces, and instruction scope depths are also checked.

Exact base→tilesync PC correspondence:

| Base | Tilesync |
|---|---|
| 0,1,2 | 2,3,4 |
| 3 | 0: ABI+72/+76 load hoisted |
| 4..8 | `p+1` |
| `[9,5504)` | `p+12`, i.e. `[21,5516)` |
| 5504 `ret` | 5530 `ret` — textual correspondence only, **not equivalent incoming CFG** |

There are **no deleted instructions or changed mapped opcodes/operands after alpha renaming**. The only common scheduling change is moving the independent, immutable parameter load from base PC3 to tilesync PC0. No prior global-memory operation is crossed. All added destination registers are outside the common alpha-map image; the added work does not clobber the common register state.

For the contiguous **5495-instruction common region**, the checker proves equality of **5523 predicate-labelled CFG edges**, mapping its terminal boundary to an explicit `COMMON_CORE_FRONTIER`. That boundary is **base PC5504 versus tilesync PC5516**, not tilesync's later return. The full actual CFGs remain separately retained:

- base: 57 blocks, 28 conditional branches, 0 backedges;
- tilesync: 61 blocks, 30 conditional branches, 0 backedges.

All existing ingress/source-zero predicates, singleton broadcasts, effective-source-dimension fallbacks, address expressions, and sixteen raw 32-bit ingress loads are identical under the map. No new input wait or raw FP8 reencoding is inserted. All arithmetic instructions, constants, F16/F32 precision/approximation qualifiers, residual forks, **256 MMA**, **104 shfl.sync**, and **32 movmatrix.sync** instructions are identical. The exact source/ISA semantics remain the assumption; no MMA or numerical kernel is executed here.

All output geometry, guards, address arithmetic, FP8 packing, and stores are preserved. Output-store pairs are:

```
base 4730 -> tilesync 4742
base 4747 -> tilesync 4759
base 5490 -> tilesync 5502
base 5503 -> tilesync 5515
```

These are ordinary `st.global.L1::no_allocate.b128` output stores; **they were not changed to release stores**. `DELTA.json` lists all ingress load pairs and raw ingress register mappings. Their shared PC offset also covers the supplied base report's arithmetic/output witnesses.

The supplied `BASE_CORE_ALPHA.json` is independently hash-checked and its **4721 records / 5087-symbol map** are checked against the actual base operand sequence and explicit PC ranges, then composed to tilesync, including all 256 MMA records. `PRIOR_ALPHA_COMPOSITION.json` preserves this result. **Ordinary PTX was not an allowed input and was not read:** this verifies the supplied proof's base-side/internal consistency and composition, not a fresh proof of its ordinary-source antecedent. Its mapped return likewise does not erase tilesync's epilogue.

**Precise equivalence scope:** at corresponding common-core points, equal observed input/slab loads and compatible PTX warp semantics yield the same common register expressions, output addresses, predicates, and values. This is not a whole-program memory-trace or termination equivalence. In particular, the signal buffer must not race with or alias concurrently observed input/slab/output memory; live launch shape, memory contents, allocations, and ordering remain external conditions. Even matching final output bytes would not remove the signal/barrier behavior.

## 3. Every added instruction and its ordering

The following are the **complete 26 additions**, with tilesync PCs. `P` below denotes the exact tilesync entry's `_param_0`; `DELTA.json` retains literal text and source lines for every instruction.

### Prefix: source line12 and lines21..31 (12 additions)

```ptx
   1: ld.param.b64 %rd7, [P+56];
  10: min.s32 %r45, %r41, 0;
  11: sub.s32 %r3, %r40, %r45;
  12: setp.eq.b32 %p20, %r3, 0;
  13: mov.b32 %r4645, 0;
  14: @%p20 bra $L__BB31_2;
  15: add.s32 %r46, %r3, -1;
  16: shr.s32 %r47, %r46, 31;
  17: shr.u32 %r48, %r47, 29;
  18: add.s32 %r49, %r46, %r48;
  19: shr.s32 %r50, %r49, 3;
  20: mad.lo.s32 %r4645, %r2, %r50, %r2;
```

Here `%r40=W`, `%r41=X`, `%r2=ctaid.y`. Label `$L__BB31_2` is PC21, where the unchanged common ingress begins. The new predicate tests the adjusted **logical width**, not a signal/counter. It is CTA-uniform for fixed arguments; the branch only skips the division/index calculation. PC13 initializes a **local row-index accumulator**, not global counter memory. Neither branch path returns or skips arithmetic.

### Epilogue: source lines14170..14184 (14 additions)

```ptx
5516: bar.sync 0;
5517: mov.u32 %r4637, %tid.x;
5518: mov.u32 %r4638, %tid.y;
5519: or.b32 %r4639, %r4637, %r4638;
5520: mov.u32 %r4640, %tid.z;
5521: or.b32 %r4641, %r4639, %r4640;
5522: setp.ne.b32 %p349, %r4641, 0;
5523: @%p349 bra $L__BB31_60;
5524: mov.u32 %r4643, %ctaid.x;
5525: add.s32 %r4644, %r4645, %r4643;
5526: mul.wide.s32 %rd307, %r4644, 4;
5527: add.s64 %rd306, %rd7, %rd307;
5528: mov.b32 %r4642, 0;
5529: st.release.gpu.global.L1::no_allocate.s32 [%rd306], %r4642;
```

- `$L__BB31_58` now names PC5516, the barrier. The last output guard, PC5505 `@%p348 bra $L__BB31_58`, and the final output-store fallthrough both reach it. No source path bypasses it to return.
- `bar.sync 0` is CTA barrier **ID0, no explicit participant count**. Correct PTX participation/launch assumptions are still required. All syntactic paths reach it before the new thread-ID divergence; there is no early exit before it.
- PC5523 sends **all threads except `(tid.x,tid.y,tid.z)=(0,0,0)`** to `$L__BB31_60` at PC5530 `ret`. This selects one thread per CTA, not one per warp. The leader alone executes the address calculation and release store, then reaches the same return.
- The scalar signal store writes **zero, 4 bytes, global state space, `.release.gpu`, `L1::no_allocate` hint**. There is no old-value read, increment, decrement, exchange, reduction, CAS, or atom/red instruction. A release store must not be described as an atomic arrival-counter decrement. The cache hint is not a substitute for memory ordering.
- There is **no standalone `fence`/`membar`**, no shared-memory operation, no acquire/polling load, and no backedge. That does **not** mean synchronization-free: the CTA barrier and release ordering are explicitly present, besides the common warp-synchronous operations.
- The intended source ordering is common output stores → CTA barrier → leader's GPU-scope release store → leader return. It is not a grid-wide barrier; other CTAs may still be working. Nonleaders need not wait for the leader's later signal store before their own returns. The source expresses a publication protocol; consumer-side matching ordering and actual device visibility are **not verified** here. `.gpu` is not a CPU/system-scope visibility proof.

Actual CFG DAG path bounds are checked, without executing synchronization: base/tilesync each have 256 MMA on every path and 0..4 output stores; tilesync has exactly one CTA barrier on every path and 0..1 signal stores per thread path.

## 4. Exact ABI fields and signal address

ABI offsets here are **decimal bytes**.

| Field | Base load PC | Tilesync load PC | Actual use |
|---|---:|---:|---|
| 0 | 5 | 6 | input pointer, followed by common `cvta.to.global` |
| 8 | 1 | 3 | packed output pointer |
| 16 | 0 | 2 | own slab pointer |
| 24,28 | 2 | 4 | logical H,W; **W additionally sets signal row stride** |
| 32,36 | 4 | 5 | X,Y origins; **X additionally sets signal row stride** |
| 40 | not loaded | not loaded | no auxiliary-input/wait handle used |
| 48,52 | not loaded | not loaded | no previous X/Y used |
| 56 | not loaded | **1** | signal base pointer, directly added in 64-bit address arithmetic |
| 64 | not loaded | not loaded | no secondary output |
| 72,76 | 3 | **0** | positive source H/W overrides, otherwise logical dimensions |
| 80..95, including88/92 | not loaded | not loaded | no tail overrides consumed |

Base ignores `[40,72)` and `[80,96)`. Tilesync ignores `[40,56)`, `[64,72)`, and `[80,96)`. The signal pointer has **no `cvta`, null check, range check, or counter load**; it must already supply a usable global address basis. All threads load ABI56, but only the leader dereferences the computed signal address.

Let `s32` wrap modulo2^32 and interpret signed; `tdiv8` truncate signed division toward zero; `S` be ABI56. Exact expressions are:

```
n      = s32(W - min(s32(X), 0))
stride = 0 if n == 0 else tdiv8(s32(n - 1)) + 1
row    = s32(ctaid.y * stride)
index  = s32(row + ctaid.x)
address = u64(S + 4 * signextend32(index))
```

The sign-bias shifts implement truncation toward zero, not Python floor division. The subtraction `n-1` wraps **before** division. For example, `n=INT_MIN` wraps to `INT_MAX` and gives stride268435456; extrapolating a positive-domain ceil formula there is incorrect.

In the **positive, nonoverflow domain** this simplifies to `stride=ceil((W-min(X,0))/8)`. It is based on logical ABI28 and origin ABI32, **not** source override ABI76 or `%nctaid.x`. Signal indexing uses neither H/Y nor `ctaid.z`, lane ID, or thread-block dimensions.

For a conventional dense grid, `grid.z=1`, `grid.x=stride`, nonnegative nonoverflow indices, and adequate allocation give one 4-byte slot per `(ctaid.x,ctaid.y)`. More generally, `0<grid.x<=stride` permits holes but distinct row slots; the highest used index is `(grid.y-1)*stride+grid.x-1`, which must stay within signed32 and the allocation. None of these live conditions is checked by the PTX. Too-wide grids overlap rows; `grid.z>1` repeats slots. With `n=0`, row is always zero, so different y CTAs reuse x slots. Even a CTA whose four output guards all reject still reaches the barrier and its leader signals.

## 5. Counter initialization/lifetime and remaining acceptance boundary

This is a **completion-side overwrite-to-zero** source, not a complete counter lifecycle implementation.

1. It never initializes pending counter memory, inspects prior state, resets for a future generation, or decrements an arrival count. `%r4645=0` is only address setup.
2. The consumer protocol is not supplied. **If zero means ready**, each used slot needs an externally established nonzero pending state before consumers can accept that generation. Initial zero or stale previous-generation zero can look ready too early; a late pending initialization can overwrite completion. No particular nonzero initial value is derived from this source.
3. Allocation, 4-byte alignment, valid address extents, ownership, nonaliasing/race freedom, producer/consumer ordering, and completion-generation retirement before reuse must be established externally. The source has no epoch tagging, ABA protection, pointer guard, or multiple-producer aggregation.
4. The consumer needs compatible acquire/ordering and scope for the intended publication. No consumer PTX, native visibility test, host polling protocol, or inter-device/CPU publication is established. CTA barrier participation and warp contracts are source preconditions, not launch evidence. The source does not prove one warp per CTA; common code uses lane ID, whereas the added signal uses full thread ID.
5. Input/slab readiness is independent: this entry does **not** wait through ABI40/48 or acquire a predecessor signal. Main's accepted pre0 boundary and newly checked own-slab hash are not re-run and do not close this protocol.

`HOST_REPORT.md` reports an inpview alternate handle gated by extra signal output, consistent with source use of ABI56 and nonuse of40/48. It also reports non-DS host source dimensions at72/76 being zero and positive overrides stored at88/92, while these PTX entries read72/76 and ignore88/92. **That mismatch remains explicit.** The report is a supplied static claim, not freshly inspected DLL bytes, live dispatch, or ABI argument validation here.

## 6. Verification, failures, and exact reads

Successful final command:

```
PYTHONDONTWRITEBYTECODE=1 python /home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/static_checker.py
```

PASS: independently parsed 5505/5531 instructions; exact5505-instruction alpha; 5810-symbol bijection; 5523 common-boundary CFG edges; all26 additions; scoped declarations; ABI fields; prior-proof base-side/composition checks; **12645 integer signal-address cases**, **1032 positive-grid bijections**, **129 leader-predicate cases**, and seven negative mutation checks. These are CPU static/address tests, **not numerical NN or synchronization execution**. The checker never interprets or replaces a barrier, wait, signal store, or return as CPU ordering.

Failures are retained in `parsed.json` (INVALID exploratory parse), `CHECKER_FAILURES.log`, `CHECKER_RUN.log`, `EXPLORATORY_FAILURE.md`, and `PROGRESS.md`: provisional line parsing counted declarations and bundled inline ops incorrectly; the first strict parser rejected local `.reg.b16`; a later scope-gap assertion incorrectly mapped the pre-barrier closing scope to the later return. Both strict-checker failures are fixed with explicit syntax/boundary handling. All retries used generated caches, with **no additional primary source reads**.

**22 of24 bounded primary-input read units**, every unit ≤2000 lines, no truncated input read. Exact offsets, byte intervals, chunk hashes, and file identities are retained in `INPUT_READS.json`. The one-line alpha JSON is614339 bytes, ingested by one bounded CPU read without dumping it to the tool output. Initial packet/report reads cost3; full PTX ingestions cost8+8; report identity checks cost1+1; alpha cost1. No input was mutated.

### All primary task-input paths actually read (absolute; no others)

1. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/PACKET.json` — mandatory first read, limit2000.
2. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/base.ptx` — lines1..14159 in8 chunks.
3. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/tilesync.ptx` — lines1..14189 in8 chunks.
4. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/BASE_REPORT.md` — initial limit2000 and one complete156-line identity ingestion.
5. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/HOST_REPORT.md` — initial limit2000 and one complete146-line identity ingestion.
6. `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/BASE_CORE_ALPHA.json` — one complete1-line ingestion.

### Generated task-artifact paths actually read

These are self-generated cache/checker/log dependencies, not additional external inputs. Checker reads are appended to `DERIVED_READS.jsonl`; exploratory and shell-log reads are recorded in `PROGRESS.md`.

- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_base.ptx`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_tilesync.ptx`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_BASE_CORE_ALPHA.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_BASE_REPORT.md`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/cache_HOST_REPORT.md`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/INPUT_READS.json`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/CHECKER_RUN.log`
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/ingest.py` — local script executed by CPU Python.
- `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-inpview1-tilesync-source-20260912/out/static_checker.py` — local script executed by CPU Python.

No outside discovery/recursive scan, DLL/PE/Wine/GPU/CUDA/network execution, ordinary PTX/slab discovery, model prediction, original numerical run, nested agent, deployment, or gate change occurred. All task-controlled writes are under the authorized `out/` directory.

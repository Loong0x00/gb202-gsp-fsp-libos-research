# Original standard FP8 Swin variants — conditional equivalence certificate

## Result

**Proved, conditionally:** every common arithmetic instruction, load, predicate,
warp collective and data store in plain
`cc_tinlayout_fused_swin_1h_32_1_fp8` has an equivalent counterpart in ORIGINAL
`wait_fp8` and `chained_fp8`. This is a complete common-computation certificate,
not a sampled opcode/checksum comparison. **Whole-kernel equivalence is false.**
The incoming polling CFG and chained outgoing publication remain separate,
mandatory effects; neither is stripped from the source or silently implemented
by calling the plain computation.

| Original entry | Total instructions | Common prefix | Common body | Protocol extras | ret |
|---|---:|---:|---:|---:|---:|
| plain standard | 4902 | 27 | 4874 | 0 | 1 |
| wait_fp8 | 4979 | 27 | 4874 | 77 | 1 |
| chained_fp8 | 5005 | 27 | 4874 | 103 | 1 |

All **4901 non-ret plain instructions** are covered exactly once. Common memory
operations include 5 parameter loads, 4 input `ld.weak.global.cg.v4.u32`,
65 `ld.global.b32`, 42 `ld.weak.global.ca.v4.u32`, and all **4 b128 data stores**.
All **256 FP8 MMA instructions**, including their accumulator operands, match.
Opcode qualifiers, immediates, operand order, packed vectors, predicates, local
register types/scopes, and read-modify-write sources are checked.

`certificate.json` contains both complete PC pairings, a 5238-symbol typed
register/label map per variant, entry-livein expressions, extra definitions,
full protocol instruction/edge lists, and 12 conditional-branch reconvergence
joins per common body. PCs are zero-based parsed instruction indices.

## Why the inpview/tilesync verifier cannot be reused unchanged

1. These are standard entries with **4902**, not inpview's instruction count.
   They load common parameter offsets 0, 8, 16, 24, 32, not the inpview override
   geometry at +72.
2. Polling blocks occur **out of line inside the textual body span**:
   wait PCs 114–135 and chained PCs 126–147. The incoming barriers occur earlier
   at PCs 65 and 77. A slice ending at the first barrier misses real loop code;
   a slice beginning after it incorrectly includes that code as computation.
3. The variants calculate x/4 before y/4; plain does y/4 before x/4.
   Two coordinate additions swap their integer operands in the prefix, and
   plain body PC **4112** also swaps its `add.s32` source operands.
   Strict ordered alpha-equivalence therefore fails. The new checker permits
   only proven modular-integer addition commutation, never FP reassociation.
4. Chained's thread-zero predicate setup is **before** its outgoing barrier.
   Its epilogue begins at PC 4990, not at barrier PC 4996. The publication-index
   value computed before waiting must survive the entire common computation.

The new parser preserves lexical register scopes and declared types, accepts
backward CFG edges, and fails on unsupported/unparsed syntax. It does not import
or execute another worker's verifier or CPU arithmetic reference.

## Proof obligations discharged

### Entry values and instruction reordering

Common-prefix parameter loads are paired by immutable ABI byte offset. CTA
reads and the coordinate DAG are paired explicitly, as are the reordered
four-instruction quotient groups. Symbolic expressions are evaluated in each
original program's prefix order. Every paired prefix destination has the same
expression under the typed bijection, with only `add.s32` operand commutation.
This is bit-width-preserving equality, not an unbounded-positive-geometry
approximation to signed division.

The common data-body cuts are plain PC 27, wait PC 82 and chained PC 94.
Backward CFG liveness finds the same 14 live-ins:

```
%ctaid.y %laneid
%r1 %r2 %r3 %r4 %r5 %r6 %r15 %r16 %r18
%rd1 %rd4 %rd5
```

All ordinary live-ins are established by equal prefix expressions; special
register identities are fixed, not freely renamed. Removing any common
pre-barrier defining instruction makes the incoming barrier unreachable from
entry: these definitions dominate it even with the original loops retained.
Protocol definitions are disjoint from **all** common mapped registers, not
merely the live-in subset. A must-defined fixed point on the full incoming CFG
also checks protocol reads through its cycles and conditional joins.

### Common CFG and reconvergence

Reachability from each data-body cut stops at the plain exit, wait ret, or
chained epilogue. The common-body instruction sets have the same size and are
paired in layout order. **Every taken branch and fallthrough edge** must map
exactly, including branches that skip over the out-of-line poll blocks.
The common graph is acyclic; this property is not assumed for the full kernel.
All 12 conditional branches have corresponding computed immediate
postdominator joins. Thus the control/predicate structure and reconvergence
structure match, conditional on the same incoming lane masks and legal
collective participation.

Inductively, equal live-ins plus identical typed operation/operand semantics
produce equal common register values. Matched predicates select corresponding
edges and active lanes. Equal data-memory read observations produce identical
common memory event addresses, widths and store values. Packed FP8 conversions,
MMA accumulators and output-address calculations are all inside this induction.
This does not require choosing a host FP rounding implementation.

### Full incoming graph, not loop stripping

The original variant CFG is partitioned into:

* entry/poll region, including every out-of-line iterator and sleep block;
* incoming `bar.sync 0`;
* 16 quotient instructions and common body;
* terminal return or chained publication epilogue.

These cover every original instruction. The incoming graph cannot enter the
common region without the barrier. The common region cannot jump into polling;
the epilogue cannot reenter the prefix or body. Five backward-layout edges per
variant are recorded (some are exits/iterator edges, not five independent spin
loops). Every extra opcode, operand and successor is compared against the
frozen, hash-pinned `protocol_expected.json`; changes fail closed.

Only thread `(0,0,0)` polls overlapping upstream tile words. Empty overlaps and
other threads go to the incoming CTA barrier. Each load remains exactly

```
ld.relaxed.gpu.global.L1::no_allocate.s32
```

The ready test is **signed value > -1**, not just equality to zero. Negative
values execute `nanosleep.u32 64` and the original retry edge. Iterator loops
then advance through the other overlapping words. +40 is the incoming flag
base; +48/+52 are upstream origins. No polling observation is fabricated.

**Arrival is not barrier completion; a nonnegative relaxed flag is not an
acquire of producer data.** The CTA barrier synchronizes its own participants,
not an absent inter-CTA acquire on the polled location. This distinction agrees
with the locally available NVIDIA ISA ordering excerpts in
`reviews/nr-swin-sync-protocol-20260911/isa-ordering.txt`: an acquire pattern
requires an acquire operation or an appropriate subsequent acquire fence.
No such operation is inserted here. No online or device execution was needed.

### Outgoing publication and noninterference

Wait has no extra output write. Chained initializes persistent `%r4355` (row
index, with its zero arm) and `%rd7` (+56 publication base) in the incoming
region. Both are definitely initialized at the barrier and cannot be clobbered
by the common computation. Its epilogue has six thread-zero predicate setup
instructions, **then `bar.sync 0`**, then the thread-zero branch and

```
st.release.gpu.global.L1::no_allocate.s32 [address], 0
```

The publication address is exactly the original b32/b64 integer calculation:
`N = s32(W - min(current_X,0))`; row is zero if N is zero, otherwise
`row = s32(cta_y * (trunc_s32(s32(N-1)/8) + 1))`; then
`address = u64(base56 + 4*s32(row + cta_x))`.
The implementation retains the actual shift/bias sequence, including wraps.
It uses **current** X at +32, not upstream X at +48.

The release publication is separately conditioned on common data stores and
all participating threads completing the outgoing barrier. The CPU helper
returns an intent; it does not issue a write, complete a barrier, or claim
producer visibility to a later relaxed consumer.

## Conditional CPU reuse contract

`cpu_intents.py` is a planning helper, **not native consumer selection**. Its
`conditional_reuse(...)` checks source/weight pins and the structural proof,
then interprets each of the 32 symbolic threads' original incoming CFG with
bounded, explicitly supplied polling observations. Its fixed supported block is
`(32,1,1)`. Missing observations and budget exhaustion never mean ready.

Permission additionally requires an explicit caller readiness attestation:

* a nonempty `snapshot_id`;
* `input_and_weights_visible=True`;
* `cta_barrier_completed=True`;
* `protocol_buffers_disjoint=True`;
* `valid_collective_participation=True`.

This permits **conditional common-computation reuse on supplied CPU bytes**.
The caller must use the same ABI/data-memory observations and preserve the
separate incoming and outgoing intents. The attestation is a caller assertion,
not independently verified native readiness or a hash binding to snapshot bytes.
No arithmetic consumer is called or selected by this helper; native selection
remains pending and is outside this task. The helper re-reads immutable local
sources; concurrent modifications during a call are outside its contract.

## Exact provenance and remaining limits

`SOURCE_PINS.json` pins all three original excerpts, their exact containing
module (`9fa036fc…`), the frozen extra graph, the full 147695410-byte
`WEIGHTS_HT.bin` (`836f445d…`), and both 20672-byte block1/block2 slabs at raw
offsets 21834 and 4508173. Each excerpt must equal extraction from that module.
Its original header remains **PTX 9.4 / sm_120 / address_size 64**. No PTX header
was changed, copied into a downgraded executable, assembled, or launched.
The upload offsets in the pin manifest are provenance metadata, not a new
runtime allocation/layout proof.

Whole-kernel equivalence has a direct counterexample: with a permanently
negative polled word, the variant can keep sleeping/polling while plain has no
such wait. Chained also has an additional globally visible release store when
it completes. The proof does **not** establish native progress, concurrency,
producer-to-consumer visibility, actual barrier completion, final-image parity,
or an independent GPU FP8/MMA numerical implementation. Weight hashes establish
exact bytes, not tensor-layout correctness. Any preexisting CPU common-body
reference's numerical/layout limitations remain unchanged.

The checker is a finite, source-specific Python structural certificate, not a
proof-assistant-verified general PTX semantics implementation. Its trusted
boundary includes parsing/operand-role handling, PTX instruction semantics,
original source/manifest authenticity, and explicit memory/participation
preconditions. Unsupported variants fail closed.

## Verification

From project root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 reviews/nr-swin-standard-variants-20260911/test_standard.py
PYTHONDONTWRITEBYTECODE=1 python3 reviews/nr-swin-standard-variants-20260911/verify_standard.py
(cd reviews/nr-swin-standard-variants-20260911 && sha256sum -c SHA256SUMS)
```

Eight test methods pass, including **31 variant mutants plus one plain mutant**
rejected by the structural checker **without relying on source hash mismatch**.
Mutations cover arithmetic/rounding, accumulator operands, load/store qualifiers,
store addresses/widths, local types, predicates, live-in geometry, body reentry,
poll-loop removal, sleep/barrier changes, private-register clobber, upgrading
relaxed polling to acquire, and weakening outgoing release. Separate tests
reject entry/module/raw-weight/slab pin changes and fixture byte corruption.
Protocol tests cover retries, all four overlap addresses, signed readiness,
empty overlaps, non-polling lanes, missing observations, budgets, readiness-gate
denial, and conditional publication.

Only this review directory was written. No GPU, Wine, package installation,
installed application changes, or another worker's file edits were performed.

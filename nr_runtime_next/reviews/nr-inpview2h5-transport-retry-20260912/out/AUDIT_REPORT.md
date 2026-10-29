# Block5 transport-retry audit

## Disposition

**PASS_STATIC_ONLY — persisted evidence independently rechecked. The original session remains `failed(stop): WebSocket error`.** Artifact survival and a successful static recheck do not turn that session into a successful completion, nor grant native/numerical acceptance.

All **55** packet-listed seeded artifacts initially matched their packet byte lengths and SHA256 hashes. Both PTX sources and the slab were acquired anew from the permitted Main-seeded copies; they were not treated as this worker's previously harvested data. The final confined command `cd out/recheck && python -B verify.py` exited **0**, passing **134 aggregate checks**, **557,056 field-operand checks**, and **538,197 layout/guard/bit/transport checks**. This extends the historical 59-check verifier; it does not falsify its history.

Current read accounting is **32/48 units**, with 16 unused and every text unit at most 2,000 lines. `NEW_READ_LEDGER.json` records the 55 Main-seeded acquisitions, 14 bounded PTX chunks, the binary slab acquisition, document/script inspections, and bounded derived-artifact catalog/summary reads. Large generated JSON and binary field tables were machine-processed without raw dumps. Reanalysis of already acquired own-output copies is separately recorded. The unchanged historical `recheck/READ_LEDGER.json` remains **18/32**, not this audit's usage.

## Independently checked facts

| Property | inpview | ordinary |
|---|---:|---:|
| Source bytes | 220,426 | 202,549 |
| Source lines | 13,351 | 12,737 |
| Executable instructions | **5,459** | **4,845** |
| Static MMA sites | **304** | **304** |
| ABI bytes | **88** | **88** |
| Shared bytes / static CTA barriers | **4,096 / 6** | **4,096 / 6** |
| Math-loop visits / MMA sites in loop | **2 / 112** | **2 / 112** |
| Dynamic collective MMAs per warp / compatible two-warp CTA | **416 / 832** | **416 / 832** |

An independent semicolon/scope parser, not the seed parser's multiline-MMA special case, reproduced every normalized executable statement. Every indexed instruction was checked against its exact source-line range. Source line counts, byte lengths and hashes were recomputed rather than accepted from cached index metadata.

SHA256:

- inpview: `f5979cb2032432e185a0d7fbcc9b24592902a72fd83920c5e110d7742b772c31`
- ordinary: `056455261062601c5c690fe16089c37def7ad3da9e1b4a35cdbc0afcd4e49170`
- 61,760-byte slab: `1b905577285978107b21b5730aac2b0105d45f757b5e78334291d9b4ab5646bb`

These certify the supplied snapshots against this packet, not their extraction from a DLL reopened by this worker. The supplied DLL was deliberately **unopened and unhashed**.

### ABI and ingress/output basis

Actual parameter declarations and loads establish 88 bytes. Inpview uses pointer offsets 0/8/16, H/W at 32/36, X/Y at 40/44, and independent signed-positive effective ingress overrides **80/84**, not 72/76. Ordinary never loads 80/84. Source lines 34–37 select `EH = ABI80>0 ? ABI80 : H`, independently for EW; output geometry remains H/W.

The four-plane physical ingress basis is

`pi(c)=16*(c//16)+4*((c%8)//2)+2*((c//8)%2)+c%2`

`byte(y,x,c)=16*((c//16*EH+y)*EW+x)+pi(c)%16`.

Reexecuted byte-tag proofs check two first-projection K32 contributions covering K64, 131,072 ordinary/inpview first-MMA A basis bytes, Q/K shuffles, V transpose, PV token permutation, and all 4,096 interior output neuron bytes. Output is ordinary tiled C64, not planar16. Eleven ingress-address cases and four output-guard cases retain singleton broadcasts, positive overrides, negative origins and skipped/fringe output distinctions. This is finite source/address verification, **not a universal signed-overflow, exceptional-codec, or live-allocation guarantee**. Ingress CFGs are intentionally not equated.

### Nine typed fields and all access ranges

| Slab byte range, end exclusive | Payload | Canonical field |
|---|---|---|
| 0–16384 | E4M3 | FF expansion [256,64] |
| 16384–24576 | E4M3 | FF contraction [2,32,128] |
| 24576–28672 | E4M3 | FF mixing [64,64] |
| 28688–28816 | F16 | input residual gain [64] |
| 28832–41120 | E4M3 | QKV [2,3,32,64] |
| 41120–57504 | F16 | score bias [2,64,64] |
| 57504–57512 | **F32** | Q scale [2] |
| 57520–61616 | E4M3 | attention output [64,64] |
| 61616–61744 | F16 | attention residual gain [64] |

Both source traces have **129 distinct slab load sites**, referencing **61,704 bytes**. Exactly **56 bytes** remain unread: `[28672,28688)`, `[28816,28832)`, `[57512,57520)`, `[61744,61760)`. No dtype or learned field was invented for these gaps. F16[30880] container metadata does not make the actual payload uniformly F16. Own F32 scale bytes decode to 2.3823421001434326 and 9.916067123413086; this is parameter decoding, not a neural run.

The original trace classifies weight loads by their starting address and uses a broad symbolic input region. The added independent checks therefore validate **whole accesses**, not merely starts: all slab accesses stay within 61,760 bytes, every shared access within 4,096, and synthetic 16×16 input/output accesses within their explicit C64 envelopes, for both source variants. Every canonical table offset is scalar-aligned and fully slab-bounded; scalar counts, bijective/disjoint field coverage and raw-byte reconstruction are checked. All 18 regenerated field/table binaries are byte-identical to their seed versions.

`fields_proof.main()` regenerated all absolute field paths under this worker's `out/recheck/fields` **before any field-map dereference**. The verifier additionally checks each path against its exact expected own-output filename. Comparison with the permitted old snapshot proves `FIELD_MAP.json` changed only those 18 paths; all semantic data are identical. Old paths were compared as strings, never followed.

### Alpha proof, exceptions and control flow

Independent substitution checked one globally injective register/label/shared-symbol map over **4,615 complete instructions**. Instruction pairing is one-to-one and ordered. The entire ordinary core is covered by those pairs plus one add; the entire inpview core additionally has exactly 18 explicitly identified recomputations.

- Ordinary 10365 / inpview 10969 require **commuting the sources of `add.s32`**, exact modulo 2^32, not literal alpha equivalence. Both strict token conflicts remain recorded at that instruction.
- Inpview 8643–8650 recompute H/W divisions; 10973–10978 and 11001–11004 recompute column guards. All four pure definition DAGs were inspected and their serialized expressions compared structurally, rather than trusting PASS flags.
- All five paired core branches preserve labels and fallthroughs. Exactly one taken target has the proven four-instruction guard prelude; its actual indexed target interval was independently checked.
- Each source has one lexical backward edge consistent with its CFG. The copied loop predicate is initialized true, captured at the header, then set false at the tail; the induction definitions are exactly 0 then 1, with no internal escape branch. Per-lane/site traces independently show two visits for the first 112 MMA sites and one for the other 192: `112*2+192=416` per warp. All 64 lanes supply 26,624 trace records, representing **832 collective operations**, not 26,624 independent MMAs.

The whole suffix is **not** pure alpha-identical. No universal ingress-value or native memory-semantics equivalence follows.

### Shared epochs and symbolic limits

All six actual barrier cohorts contain both 32-lane warps at the same source barrier and phase. Source-compatible shape **(32,2,1)** remains a conditional shape, not an observed launch; neither entry declares `.reqntid`.

Shared epoch read/write ranges are respectively:

1. none / `[0,4096)`;
2. `[0,4096)` / none;
3. `[0,2048)` / `[0,2048)`;
4. `[0,2048)` / none;
5. **`[2048,4096)` / `[0,2048)`**;
6. `[0,2048)` / none.

Finite checks retain unique writers and no same-epoch other-thread read/write conflicts. Bottom PV scratch reuses the first half; it does not overwrite the second half as a guessed two-buffer scheme. CTA barriers do not prove inter-kernel publication or live completion/visibility.

MMA D values are **fresh opaque labels**, never identity MMAs or numerical products. Elementwise labels preserve basis without computing floating values and can omit denominator dependencies. The 304,704-pair exponent carry lemma covers only its finite clamped halfword domain. None of this fabricates an activation, original numerical run, or full-NN prediction.

## Preserved failures and transport classification

- **F1:** the historical diagnostic emitted **2,041 lines**, breached the 2,000-line/output bound and was truncated. The spill was not read by this worker; this violation is not excused by either read ledger.
- **F2:** the historical preliminary parsers omitted brace-wrapped operations or counted declarations / failed multiline MMA recognition (5485/4871, zero MMA). Their failure history remains; the independent parser now agrees with corrected source counts.
- **F3:** the naive PV grouping failed **16,384** checks. The full rejected evidence remains byte-identical; corrected interleaved C-chain grouping is explicitly retained.
- **F4:** strict whole-core alpha failure and both explicit exception classes remain, including the rejected initial candidate.
- **Transport:** the packet reports `failed(stop): WebSocket error`. Classify this as the reported session/transport termination, separately from successful persisted static audits and separately from F1–F4. No original transport transcript/root-cause evidence was supplied here; exact timing/cause is unverified. Do not relabel that session success.

Historical `REPORT.md`, `PROGRESS.md`, `READ_LEDGER.json`, `FAILURES.json`, and both rejected-candidate JSON files remain byte-identical in the clone. Original input snapshots were never modified.

## Scoped changes and reproducibility

Before executing any supplied main, all seven participating modules were read and reviewed for imports and writes, syntax-checked, and confirmed to use their clone-local `OUT`. Exact seeded paths and field parents were non-symlink paths. No import or execution of `harvest.py` occurred; its source was inspected and its bytes hashed only. `-B` disabled bytecode writes. No old original-path main was run.

Exactly **five** of the 55 seed artifacts changed:

- `out/recheck/verify.py`: current-ledger/path guards and 65 additional independent static checks; original historical check explicitly labeled historical.
- `out/recheck/finalize_artifacts.py`: no longer rewrites the historical read ledger; all proof/failure payloads preserved.
- `out/recheck/FIELD_MAP.json`: 18 regenerated own-output paths only.
- `out/recheck/STATIC_TEST_RESULTS.json`: 134 checks, current 32/48 accounting, explicit original transport-failure status, updated script hashes.
- `out/recheck/VERIFY_LOG.txt`: regenerated proof log and historical-ledger-preservation message.

The other **50** seed files retain their original SHA256 hashes. `SEED_VERSION_HASHES.json` preserves all original hashes; `RECHECK_RESULT.json` contains exact old/new hashes and a complete changed/created-path inventory. `recheck/INDEPENDENT_STATIC_AUDIT.json` contains the new source/count/range/control evidence. The historical `FILES_CHANGED.json` lists 61 files: the same 55 supplied artifacts plus six non-supplied generated bytecode files. Those six paths were neither searched nor opened; source proofs were rerun with bytecode writing disabled.

## Still open — Main owns these

Actual block3→4 source/activations and the first numerical freeze; actual DS4 and wait-variant verification; live EH/EW versus DS4 HD/WD and H/W; producer padding/odd-size safety; exact host operand/FP8 dispatch/launch and slab binding; live allocation extent, alias/lifetime, completion and visibility; native FP8 codecs/MMA/normalization/reciprocal precision and exceptional values; original neural execution and full-NN numerical acceptance.

Original reports' DS4/host handoff descriptions remain **conditional historical evidence**, not independently reacquired host/producer proof in this permitted input set. No DLL/PE scan, GPU/native/Wine/network, discovery/recursive scan, deployment/gate action, nested agent, NN execution, or activation fabrication was performed. Main's parallel work was untouched.

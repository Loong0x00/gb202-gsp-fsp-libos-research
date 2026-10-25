# MCLK command-0 completion path follow-up (static)

Date/scope: 2026-10-09. Static-only review of matching `gb202_r570215_runtime_pmu.elf` (RV64) plus existing runtime mailbox/transition decompilation. No MODS execution, GPU access, firmware changes, or edits to prior artifacts. This report supersedes only interpretations explicitly corrected below; it does not establish a firmware fix.

## Executive summary

The command-0 primitive writes a tagged request through the PMU register accessor to physical-looking addresses `0xc09a4514` then `0xc09a4504`; it marks the in-flight sequence with `20016af8`. In the normal (non-direct) path it blocks on wait object `20016b00`, then validates a response read from `01402808` and copies the response's second word from `01402828` to the caller. A distinct direct/poll branch polls `01403ae0` through helper `205d1c44`.

This closes the *consumer contract as observed by the PMU caller* (request writes, completion wait, response validation) and reveals an event wakeup path: init creates `20016b00`, and interrupt/status dispatch type 2 signals it through `205dd420` → `205cf644`. However, no positive evidence shows an IRQ handler copying response words into scratch; the waiter reads response words directly from `01402808/01402828`. The device-side request consumer and endpoint identity remain unresolved. No endpoint attribution to FBPA/PBFB/PMU-mailbox/FSP can be defended from local public register databases searched. Do not identify these blocks by numerical resemblance alone.

The corrected fault interpretation remains: marker `0x25728` is from the failed wait at `205d1acc`, not proof of entry busy. The busy marker is different (`0x256c8`).

## Request construction and writes

In `205d19ce` (shared primitive; wrapper caller `206358ca` for MCLK):

- `a0` is command id; `a1` points at a 16-bit payload; `a2` points at a 32-bit caller/result word. Command 0 is the MCLK path.
- `20016af8` is tested and set before the command can proceed; only command IDs `<5` pass the non-busy gate. On the normal completion path it is cleared before returning. This is a primitive-local transaction guard, not evidence of a preceding stuck transaction in the reviewed crash.
- `20016af9` is incremented as an 8-bit sequence; the request word is formed as `(command << 8) | sequence | (payload << 16)`. If that equals the input/result word, bit `0x8000` is ORed in to avoid equality.
- Accessor `205d496a` maps its low 32-bit register offset to `0xc0000000 + offset` (and serializes writes when required). The primitive invokes it first for offset `0x9a4514` with the 32-bit input word loaded through caller `a2` (MCLK request payload), then for offset `0x9a4504` with the constructed tagged command word. It does not write a literal zero as the first payload. Thus static effective addresses are `0xc09a4514` and `0xc09a4504`.
- In the non-direct path it computes wait budget from the wrapper-provided timeout and calls `205cf612(20016b00, budget)`. The MCLK wrapper supplies timeout 95000 and direct=0 (existing review). After wait success it reads `01402808`; low byte must equal sequence, bits 8..14 must equal command. It reads `01402828` and stores that value through the caller's result pointer; the high half of `01402808` is copied through the payload pointer.

These are source-level observations of PMU access semantics. They do not by themselves prove what physical block implements these addresses or what the request means to that block.

## Completion / response branches

Normal non-direct branch:

1. Wait on opaque object `20016b00` via `205cf612`.
2. On wait failure it immediately takes the assertion route (`205d1acc` loads marker `0x25728`, then jumps to shared `ebreak`). There is no normal retry in the original instructions. Ghidra's apparent loops are artifacts of treating the shared `ebreak` as returning.
3. On success, validate response sequence and command in `01402808`; copy response value at `01402828` and returned payload field at response bits 16+; clear `20016af8`.

Direct branch (primitive's `param_5 != 0`): it calls `205d1d14` to clear `01403ae0`, writes the same request pair, and invokes `205d1c44` to poll. `205d1c44` polls `01403ae0`, matches command/sequence and response type (`bits 16..19 == 2`), copies response payload, and returns. This branch does not establish the behavior of the MCLK call because MCLK's wrapper uses direct=0.

The response fields are therefore *consumed directly from `01402808/01402828` by the waiting transaction*. In the inspected command-0 function there is no intervening memcpy from an IRQ-owned scratch buffer. That is not proof that no IRQ path stages or mirrors them elsewhere: the producer and any ISR/callback path that updates the event object were not closed in this pass.

## Wait object, guard and signal producer

- `20016af8`: high-confidence primitive-local busy/in-flight byte based on exact read/set/clear xrefs in `205d19ce`. The crash marker correction is decisive: this crash failed later in the wait path; it does not prove this guard was already set at entry.
- `20016b00`: passed to generic wait `205cf612`; the full ELF xrefs show creation via `205cf59e(&DAT_ram_20016b00,0)` in init routine `205d9688` (after setup calls). The apparent retry loop in the decompilation is not a normal instruction-level retry; the original code asserts if the created object pointer is null.
- Signal side: `205dd420(2)` calls `205cf644(20016b00)`, i.e. the generic signal/post operation. It is selected by `205dd1f8` for notification type 2. The caller `205dd196` reads pending status via `205d07e2` from PMU-local address `014024c0`, masks it with `5`, then traverses individual set bits. Bit index 2 (mask `4`) selects type 2; it writes `1 << bit_index` via `205d07f6` to acknowledge the status before dispatch. `205d080a` updates `014024c4` and includes `fence io,io`. This closes a status-dispatch path, but not its actual ISR registration or hardware producer. Thus the ELF supports an event signal via dispatch type 2, although exact silicon interrupt source ownership is not identified here.
- No response-to-scratch copy was found in the command-0 caller: response values are read directly from `01402808/01402828` after wake. This does not exclude an external producer updating the registers before raising the notification.
- `01403ae0` has direct-path ready/status use in the primitive's polling helper, but that alone does not name its register block.

## Endpoint attribution check

Searched local `tools/envytools/rnndb` and available public headers for exact `0x01402808`, `0x01402828`, and the `0x9a4504/0x9a4514` offsets. No exact symbol/field match surfaced in the searched material. The local rnndb does contain a `gf100_pbfb.xml`, but no evidence links these command addresses to that block. Nor does the address alone prove FBPA, PBFB, PMU mailbox, or FSP ownership. The earlier review's caution about public FSP scratch addresses (`0x008f03xx`) remains a non-attribution, not proof that private/indirect FSP participation is impossible.

Conclusion: retain neutral labels “PMU-accessed request register pair” (`c09a4514`, `c09a4504`) and “response/status words” (`01402808`, `01402828`) until a documented register map, firmware consumer, or cross-layer call path binds them.

## 18 GHz boundary / derived constants

The retained 18000-success / 18001-failure observation is confounded: from the same 14001 MHz base it is also +3999 / +4000 MHz. The current static evidence does not distinguish an absolute target limit from an offset limit.

The older scan states that the runtime PMU ELF contains no literal 32-bit `4000000`, `18000000`, or `18001000` constant. This follow-up did not find a new direct comparison or a consumer-side boundary constant. Request construction is payload-driven; command-0 primitive itself does not compare the target to 18 GHz. A threshold might be derived from runtime tables, firmware data or the external consumer/change sequence, but that remains a hypothesis, not a finding. No 18 GHz limiting constant is closed by this report.

## Open items (not closed)

1. Identify the device-side consumer of writes to `c09a4514/c09a4504` with positive source/register-map evidence.
2. Locate who writes/updates `01402808/01402828`, and whether writes precede an event signal.
3. Construction and signal/posting of wait object `20016b00` are now located; establish the actual ISR registration and hardware source that sets pending bit 2.
4. Bind the status dispatcher to its invocation context and any producer of the response registers; the located type-2 path posts the event without copying response words.
5. Find the origin of the 18 GHz boundary / any derived target constant, and separate absolute-target from relation-offset behavior.

## Evidence anchors

- ELF: `../../gb202_r570215_runtime_pmu.elf`; existing function exports/decompilation: `../../gb202_r570215_runtime_trace_decompile.log` and `../../gb202_r570215_runtime_mailbox_helpers.c`.
- Shared primitive: `205d19ce`; register accessor: `205d496a`; direct poll helper: `205d1c44`; reset helper: `205d1d14`; MCLK wrapper: `206358ca`; generic wait: `205cf612`.
- Full-ELF reference/decompile passes: wait object xrefs (including create and signal paths) and dispatch targets were inspected with Ghidra `DumpTargetReferences.java` / `DecompileAddresses.java`; transient outputs `/tmp/mclk_refs.out`, `/tmp/mclk_sync_refs.out`, `/tmp/mclk_upstream_refs.out`.
- Prior corrected fault evidence: `../../mclk4000_readonly_review_20261009/REVIEW.md`, including `205d1acc` / marker `0x25728` versus entry-busy marker `0x256c8`.
- Address search: local `tools/envytools/rnndb` and public headers available in project; absence of a name match is not proof of hardware ownership.

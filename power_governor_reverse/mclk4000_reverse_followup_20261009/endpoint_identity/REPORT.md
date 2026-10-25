# taskC / MCLK notification endpoint identity — static follow-up

Scope: read-only review of the matching R570.215 GB202 runtime PMU ELF, existing local source/header trees and envytools rnndb. No GPU/MODS execution; no old Ghidra database opened or modified. Any instruction claims below are from `llvm-objdump` on `../../gb202_r570215_runtime_pmu.elf` (SHA-256 recorded in sibling `send_path/REPORT.md`).

## Findings in brief

- `0x01400000` is **not justified as a BAR0 offset**. The firmware directly executes RISC-V loads/stores at `0x014024c0`, `0x014024c4`, `0x01402808`, and `0x01402828`; the command path separately uses accessor `205d496a`, which constructs `0xc0000000 + register_offset` for its `0x9a45xx` writes. Those are distinct address-formation paths. In the absence of an authoritative GB202 PMU/PPWR address-map definition, the strongest safe description is “PMU-visible local address/aperture at 0x014xxxxx”; its hardware bus target and BAR relationship are **unknown**.
- `0x014024c0` is a pending-status word. `205dd196` loads it, masks with `5`, shifts through the set bits and dispatches each set bit index. This is per-bit dispatch, not a `status == 5` equality test. For bit index 2, it calls `205dd420(2)`, which obtains the saved event object and calls generic signal/post `205cf644`. `205d07f6` writes the acknowledged status back to `0x014024c0`.
- `0x014024c4` is read/OR/mask/update state in `205d080a`; its write helper is followed by `fence io,io` in the disassembly. The exact register name, bitfield meaning, and whether it is an enable, mask, or another control word are not supplied by an authoritative map; label it conservatively as a notification control/ack-state word.
- MCLK wrapper `206358ca` waits on generic object `20016b00`; status dispatch index 2 signals that object. That establishes the PMU-side receive/wakeup protocol, **not the silicon source/IRQ line** that causes status bit 2 to be set. No positive evidence found for the producer or its interrupt registration.
- Worker `2063597a` is a persistent task-style queue consumer: it takes a lock, waits indefinitely on queue/event ID `0xf`, dequeues/parses an 0x800-byte message, dispatches message types (notably 0x10/0x11), and loops. It is not shown to be the ISR for bit 2. Parent instruction review found `205d970e–205d9726` passing function pointer `2063597a` as `a2` to setup helper `205dbdba` (with `a3=0x12`); this is a positive setup/callback anchor, not an ISR-vector binding. Do not conflate this queue worker with the status-dispatch/wait-object signal route.
- `0xc09a4514` then `0xc09a4504` are PMU-accessor writes (data then command/trigger by caller behavior); they have no proven positive name or recipient. Neither public headers nor local envytools rnndb identify them as PPWR/PMU/FALCON/PEREGRINE/PBFB registers. Their broadcast semantics and intended receiving endpoint remain **unknown**.

## Address identity / mapping boundary

The four `0x0140xxxx` references are literal CPU load/store addresses in PMU code (e.g. `lui a5,0x1402; lw ...,0x4c0(a5)`). They are neither formed by the `205d496a` helper nor demonstrated to be offsets relative to BAR0. The ELF's Ghidra naming `DAT_ram_014...` is not an authoritative register-block name and is not used here as evidence of RAM or BAR placement. The `0xc09a45xx` command path uses a different accessor-derived address (`0xc0000000 + 0x9a45xx`). Without an address translation table, a matching GB202 register header, or an implementation-side consumer, numerical normalization between these regions would be speculation.

| Firmware address | Observed operation / role | Positive public name? |
|---|---|---|
| `0x014024c0` | status load; `status & 5`; per-bit dispatch; ack write | Unknown register name; status/pending role from use |
| `0x014024c4` | RMW/update; write; `fence io,io` | Unknown register name; control/mask-like role only |
| `0x01402808` | response sequence/command validation, response upper field | Unknown register name; response metadata/status by use |
| `0x01402828` | response word copied to caller | Unknown register name; response data by use |
| `0xc09a4514` | helper write before trigger | No positive block/name; request data by caller role |
| `0xc09a4504` | helper write after data | No positive block/name; request/command by caller role |

`0x01402808/0x01402828` are read by the waiting command primitive after wake; the reviewed caller does not copy them from an ISR-owned software buffer. This does not identify who updates the words or establish that the notification source writes them.

## Worker and notification route

`2063597a` begins with common runtime check `205d3206`, repeatedly verifies lock/object `202af000`, waits on `205cf474(0xf, ..., 0x20, -1)`, extracts a message from task queue `DAT_ram_20017510`, and loops after dispatch/completion. Message 0x10 has an explicit wait/signal interaction on object `DAT_ram_200154f0`; 0x11 dispatches to `2063880a`. These facts support “worker/queue consumer,” not “interrupt service routine.” Parent review of init `205d9688` confirms function pointer `2063597a` is passed to setup call `205dbdba` at `205d9726`. The helper's exact ABI/name and any interrupt-vector registration connecting this worker to `205dd196` remain unresolved.

On the status route, `205dd196` invokes status reader `205d07e2`; on a set bit it writes the one-bit acknowledgement via `205d07f6`, then dispatches that bit index. Dispatch index 2 branches to `205dd420`, which signals the event object loaded from a global slot and jumps to `205cf644`. The MCLK completion path uses the same generic event object `20016b00` (created at init by `205cf59e`, per sibling completion report). This is positive PMU-side linkage of bit 2 to the waiter. It does not identify the external interrupt source, hardware vector, or the component that sets/clears pending bit 2.

## Public-name / history search

Searched the local public Open GPU Kernel Modules source/header trees, published GB202/GB100 headers, and `tools/envytools/rnndb` for the exact `0x014024c0`, `0x014024c4`, `0x01402808`, `0x01402828`, and `0x9a4504/0x9a4514` values and relevant PPWR/PMU/FALCON/PEREGRINE names. No exact map/name or consumer binding surfaced. Public FALCON headers describe other blocks and do not provide the missing `0x014xxxxx` mapping. Local rnndb has generic PBFB data but no evidence binding this address range or command pair to PBFB. No project Git history is available at the working-directory root (`git` reports this is not a repository), so no historical name can be established from there.

Thus no positive basis exists to relabel these as PPWR/PMU/FALCON/PEREGRINE/PBFB endpoints. “PMU notification status/control words,” “PMU-visible response words,” and “PMU-accessed request pair” are usage labels only; exact protocol and block identity remain **unknown**.

## Evidence / verification

- Sibling `completion_path/REPORT.md`: request/response caller contract, generic event creation, notification dispatch type 2 and event signal.
- `llvm-objdump` direct snippets saved alongside this report: helper/status-dispatch instruction windows and selected worker window; instruction control flow is preferred over a Ghidra atomic pseudoloop (the shared `ebreak` label can mislead decompilation).
- Search commands covered exact address strings and PPWR/PMU/FALCON/PEREGRINE in local source/header/rnndb trees. No authoritative exact match found; absence is not proof that a private/unpublished definition does not exist.

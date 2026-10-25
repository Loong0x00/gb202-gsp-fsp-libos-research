# GSP Pstate descriptor selector and range producers (static-only)

## Result

Corrects the interpretation in `../pstate_writers/REPORT.md`: factory `0x01670ea0` takes descriptor in **a1**, and loads its selector from `*(u8 *)(a1+0)` (raw factory load is `0x01670ec8`; existing evidence excerpt is `../pstate_writers/new_original_instruction_windows.asm`). The value is not read from the first argument. The three references in the large constructor/initializer at `0x011982xx` have this lineage:

| Factory call | descriptor (`a1`) | selector write in same function | factory path |
|---|---|---|---|
| `0x01198f0a` | `s8` | `sb 1,0(s8)` at `0x01198b7e` | 1 / Perf-derived getter `0x0167be2c` |
| `0x01198fb8` | `s6` | `sb 9,0(s6)` at `0x0119881a` (conditional on `s5 != 0 && *(u8 *)(s5+0x7c4) != 0`; otherwise this object is not the selector-9 descriptor) | 9 / getter `0x01692ea8` |
| `0x01199018` | `s9` | `sb 3,0(s9)` at `0x01198390` | 3 / cache getter `0x0168ac3c` |

Thus the descriptor choice is explicitly constructed in one GSP main function, not looked up as an opaque per-GPU selector. It is not a global GB202 selector: selector 9 is conditional. The kind-1 and kind-3 descriptor selectors are immediate constants in this code path.

## Descriptor bytes and range inputs

**Selector 3 / descriptor `s9`:** initialized by zeroing its object (`0x119832e/0x119833e`), then written as selector 3 (`0x1198390`). The domain loop `0x1198492..0x1198556` constructs the `+0x5e0` record from domain-data words fetched into stack scratch at `-0x114(s0)` / `-0x110(s0)`. At `0x11984c2..0x11984d4`, it extracts low bits and bits `[?]` (right shift 14 followed by mask) and stores into record offsets `+0x5e0` and `+0x5f4`; the type-dependent path `0x11984dc..0x11984fc` may rewrite those values. `0x1198528..0x119854e` fans these values out to paired fields (`+0x5e8/+0x5ec`, `+0x5f0`, `+0x5f4`, `+0x5fc/+0x600/+0x604`, and `+0x610/+0x614/+0x618`). This is a VBIOS/Perf-domain-derived cache construction, not evidence that the values are an OC control-offset SET.

The relevant upstream call is `0x11983d0 -> 0xae518c`; the later domain reads use object/vtable `+0x148/+0x38` at `0x119855e..0x1198566`. The exact producer of the stack words `-0x114/-0x110` is therefore function `0xae518c` (or its callee-population chain) and remains the next function to recover for table/version semantics.

**Selector 9 / descriptor `s6`:** the guarded branch calls `0xae4fac` at `0x1198832`, then loops through entries at `0x11988fc..0x11989a4`. It derives each descriptor's per-domain `+0x5ec` record at `0x1198912..0x119893c` from stack inputs `-0x11c(s0)` / `-0x118(s0)`: masks low bits and right-shift-14 bits are stored at record `+0` and `+0x14`, with an adjacent field at `+0x28`; the non-special type path (`0x1198942..0x1198964`) conditionally changes them. The loop then duplicates them into the record's `+8/+c`, `+0x1c/+0x20`, and `+0x30/+0x34` fields (`0x119898e..0x11989a4`). The function `0xae4fac` and its input preparation must be followed to name the actual table and version branch; no assumption that these are absolute frequencies is justified from the writes alone.

**Selector 1 / descriptor `s8`:** descriptor byte is set at `0x1198b7e`; its initial local table/config is built from the parser return at `0x1198ba8 -> 0xae535c`. Control metadata at `0x1198c8a..0x1198cc0` is decoded from stack/config words, including stores at `s8+0x5e0..0x5e4`. Its later domain records are built by `0x1198d80..0x1198e58`, using parsed entry data and a call chain through `0xaee3e8` / `0xb58474`; values are stored into a separate entry array (`s8 + index*0xc`) rather than shown here to be the same as a 5e0/5ec absolute-frequency pair. The selector-1 slot-548 getter reads related Perf state and a table/runtime record, and may call converter `0x01bcebe4` (prior report); the table producer and converter mapping remain unresolved.

### Perf+0x2e3..0x2ea capability relation

No precise mapping from Perf `+0x2e3..+0x2ea` cap bits to selectors 1/3/9 is proven by these instructions. The only directly evidenced gate choosing selector 9 is `s5+0x7c4` (`0x1198810..0x119881a`). For selectors 1 and 3 the byte stores are constants. The prior `max_capability/REPORT.md` explicitly leaves MCLK_MAX_CAPABILITY's producer/value semantics unresolved, so this task does **not** assign its descriptor values or a bit mapping to those `+2e3..+2ea` fields. Next exact step if pursuing that proposed relation: recover the data-producing call(s) feeding the `s5` object at `+0x7c4` and identify the `s5` object's type/constructor; separately trace the Perf byte/bit reads in the factory/getter before proposing a map.

## Can local data bind this to the GB202 runtime selector?

No static binding was available. The project contains saved VBIOS ROMs (including `xoc_dirty_eeprom_20260930.rom`, plus candidate/unverified ROM images under `vbios_diff/`) and prior VBIOS clock-table parser notes, but none is a captured GSP descriptor or an identified record instance tied to this `0x11982xx` code path. The checked-in `pstate_writers` and `gsp_mclk4000_review_20261010/parent_capability` artifacts are static disassembly/recovery, not runtime pstate-info. Benchmark telemetry and Perf-limit captures do not preserve the selector byte or these descriptor buffers. Therefore ROM table version/layout and actual running selector cannot be bound from the saved evidence without a non-GPU runtime descriptor/pstate-info capture or full producer recovery plus a verified ROM/table-version match.

Do not interpret the MCLK GSP relation-key absolute-frequency checker as the source/consumer of a control offset SET; this report establishes only descriptor construction and range/cache payloads.

## Evidence / verification

- `instruction_evidence.asm`: raw LLVM RISC-V instruction windows from `gsp61057_full_main_view.elf` for selector stores, producer loops, and the three calls; inner ELF VAs preserved.
- Source view: `../../gsp_mclk4000_review_20261010/parent_capability/gsp61057_full_main_view.elf`; task's preceding evidence: `../pstate_writers/REPORT.md` and `../pstate_writers/new_original_instruction_windows.asm`.
- Commands: `llvm-objdump -d --start-address=... --stop-address=... <full_main_view.elf>` for the listed windows. Static only: no GPU access or firmware execution; no Ghidra DB opened or changed.
- Remaining uncertainty is upstream source semantics: next exact functions are `0xae518c` (selector-3 record words), `0xae4fac` (selector-9 range inputs), and `0xae535c` plus `0xaee3e8/0xb58474` (selector-1 table/config path); and the origin/type of `s5+0x7c4` for its selector-9 gate.

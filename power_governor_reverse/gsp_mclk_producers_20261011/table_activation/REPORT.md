# GSP capability-table activation: object/flag producer trace (static-only)

## Parent follow-up: object identity and Perf gate now closed

The original worker findings below are retained as historical evidence. Their **unresolved object identity** has since been superseded: `classid_to_child @ 0x0141f1c0` maps ID `0xf3d722` to `pGpu+0x2050`, and the same-version generated `g_eng_desc_nvoc.h` defines that ID as **Pmu**. Raw instructions `0x0141f2d8..0x0141f2e0` and `0x0141fa8e..0x0141fa94` verify the mapping. The allocation call `0x014200d4 -> 0x01419ab4` supplies the Pmu class ID and the output slot `pGpu+0x2050`; this helper creates the object and stores the cast Pmu view into the slot.

Also, in the relevant branch of `perf_init_locked_impl @ 0x0164bb38`, the exact Pmu pointer is held in `s11`; `0x0164bece` reads its `+0x78c` and `0x0164bed6` sets Perf `+0x2ea=1` when nonzero. Thus the actual Perf-side store is connected to a Pmu field, although it is not itself a write to Pmu `+0x78d/+0x78e`.

These facts do **not** close initialization/values of the three Pmu bytes or actual GB202/GB203 selection. There is also no established need for a separate GB203 GSP image: the generic main includes multiple HAL/model paths; the decisive missing data are the selected registry/HAL and these field producers/values, not merely a second file name. See the consolidated `../REPORT.md`, sections 2–3, and raw evidence in `../control_dispatch/`.

## Original worker result

Scope is the R610.57.04 GSP main view in the existing GB202 Ghidra project. No GPU access, firmware execution, MODS, or original project/DB edits. I copied `control_dispatch/work_db` to `table_activation/sandbox/work_db` before opening it. This closes several instruction-level details about candidate producers but **does not prove the runtime identity/value of the `pGpu+0x2050` object or which table a specific GB202/GB203 runtime selected**.

The already-established consumer remains: `FUN_ram_01bacb98` loads the pointer at `pGpu+0x2050`, checks its bytes `+0x78d/+0x78e`, and calls `FUN_ram_01b9e158` with table `0x01e21b98,count=0xfd` if `+78d==0 && +78e!=0`; if `+78d!=0`, it passes `0x01e23b38,count=0xf5`. `+78d==0 && +78e==0` errors. This confirms the branch logic, not the conditions that populate its state.

### What the candidate writes actually show

The proposed addresses `0x012b6fe2` and `0x012cab4a` are valid instructions in parallel small helpers. Both operate on `a0` as a destination object and copy/derive byte fields from `a1`:

```asm
# helper containing 0x012b6fe2
012b6fc8: sb a5,0x789(a0)      # a5 = (lw 0x2c(a1) & 7)
012b6fd2: sb a5,0x788(a0)      # a5 = (lbu 0x28(a1) & 1)
012b6fe2: sb a5,0x78e(a0)      # a5 = (lw 0x40(a1) & 0x3f)
012b6fee: sb a5,0x78f(a0)      # a5 = (lw 0x40(a1) >> 6) & 7
012b7040: sh a5,0x78e(a0)      # alternate branch stores 0x328 (16-bit)
```

```asm
# corresponding helper containing 0x012cab4a
012cab30: sb a5,0x789(a0)      # (lw 0x2c(a1) & 7)
012cab3a: sb a5,0x788(a0)      # (lbu 0x28(a1) & 1)
012cab4a: sb a5,0x78e(a0)      # (lw 0x40(a1) & 0x3f)
012cab56: sb a5,0x78f(a0)      # (lw 0x40(a1) >> 6) & 7
012caba8: sh a5,0x78e(a0)      # alternate branch stores 0x328 (16-bit)
```

In each function, the `0x328` fallback is reached when the 32-bit value at `a1+4` is below `0x1a`; otherwise the low six bits from `a1+0x40` are used. This is a **real multi-byte `sh` write** to the same byte pair beginning at `+0x78e`, not a one-byte-only producer. The functions also materialize `+788/+789` and `+78f`. The decoded blocks shown do not establish a write to `+78d`; they therefore cannot by themselves explain the full table selector predicate.

`0x01d6b250` did not resolve as an instruction/reference target in this GB202 view with the supplied query; it is not evidence for an initializer. Treat this candidate as unconfirmed.

The Perf-side candidates are likewise not all equivalent. At `0x0164bed6`, the instruction really is `sb a5,0x2ea(s1)`, but that is a write to the distinct Perf/control record addressed by `s1`, not to the pointer object at `pGpu+0x2050` (unless an additional object/layout equivalence is independently shown; none was found). The parser-side `0x01ad1a88` and `0x01ad3388` both store literal `0xff` to `0x2ea(a0)` and then materialize adjacent words/bytes from parsed packed values; these are raw-initialization/parser paths, not evidence those values are the runtime `pGpu+0x2050` fields. In particular, the two blocks are substantially parallel parser/format paths, not proof of two GPU-model table choices.

### Object identity and initialization status

The consumer's load is exactly `ld ...,0x2050(pGpu)` followed by byte reads at pointer `+0x78d/+0x78e`; this proves only a pointer slot plus offsets. The nearby capability helper code uses the same `+0x2050` pointer with other offsets (`+0x786/+0x783`) as shown in `capability_source_object.c`, but neither the saved static output nor recovered generated source assigns that pointed-to allocation a trustworthy class/type name or proves that the helper above is its constructor. Similar field offsets and data shape are insufficient to identify object identity.

The two verified `+78e` helper writes show candidate initialization/copy semantics from a descriptor-like input record at `a1+0x40`, including a low-six-bit value and an alternate default of `0x328`. They do **not** establish who calls either helper for the table-consumer's object, the origin/format/version of `a1`, or a producer for `+78d`. The unrelated parsed Perf `+2ea` stores do not bridge that gap. Thus the required initialization chain is not closed and I do not claim a static derivation of the actual flags.

### GB202 versus GB203 table selection

Only the existing GB202/R610 main view/project was available in the specified control-dispatch evidence. Its generic GSP consumer includes both table alternatives and no branch on a decoded GB202/GB203 chip/model value is visible in the recovered consumer. No corresponding GB203 R610 GSP main view or matching generated firmware source was found locally to compare code/data tables. Consequently, **whether GB202 and GB203 actually select different tables is undetermined**. Do not infer it from different table lengths or from the duplicated parser blocks above. GB202 uses one branch or the other only when runtime object fields satisfy the recorded predicate; no runtime instance was captured.

### Next smallest evidence needed

The next decisive field is the **allocation/call-site provenance of the exact pointer loaded from `pGpu+0x2050`**: identify its constructor/factory and show which setter writes `+0x78d` and `+0x78e` into that same allocated object. Then trace the input descriptor's source (and model discriminator if any). Separately, a GB203 R610 GSP view is required for a static code/table comparison. Without those, actual runtime selection remains unconfirmed.

## Verification/provenance

- Read `control_dispatch/capability_table_user.c`, `capability_source_object.c`, and the existing descriptor/table artifacts.
- Copied `control_dispatch/work_db` into this directory's `sandbox/work_db`; ran Ghidra headless queries against a working copy, never the original. Re-copied the source DB afterward so the retained sandbox is a pristine byte-for-byte copy of the original and marked it non-writable.
- Queried candidate instruction windows with Ghidra `BoundedDisassembly.java`; exact inner ELF VAs and decoded instructions are quoted above. Queried `XrefsTo.java` for candidate addresses; no xrefs at the candidate instruction locations (expected for instruction addresses), and `0x01d6b250` did not validate as a producer.
- Local static search found no GB203 counterpart/main-view matching this GB202 Ghidra project. No hardware/runtime validation was performed.

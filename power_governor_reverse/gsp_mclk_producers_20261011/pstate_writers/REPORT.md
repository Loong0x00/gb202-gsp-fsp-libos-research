# R610.57.04 GSP Pstate slot-548 producer trace (static-only)

## Result

Bounded follow-up to `../gsp_mclk4000_review_20261010/REPORT.md`. I read the local complete-main static view and related recovered slot-548 code/instructions; no GPU, MODS, firmware execution, register access, or ELF modification. This closes the factory's **dispatch mechanism** and identifies which constructor families install the known getters, but does **not** close the GB202-specific factory discriminator or the upstream provenance of the min/max payload. Those remain explicit one-hop gaps, not guesses.

### Factory and selection logic

The Pstate factory is `0x01670ea0`. Its first argument includes a descriptor whose byte `[0]` is loaded at `0x01670ec8`; the factory is a switch on that byte (not a hard-coded R570 `0x3c` index):

| byte `[0]` | factory branch | slot-548 implementation installed | Cache treatment visible in factory |
|---:|---|---|---|
| 1 | `0x01671192` | `0x0167be2c` (the `AUIPC` at `0x01671202`; its result is written at `0x0167122a`) | Copies descriptor fields including `+0x5ec`; getter later constructs range values from Perf/runtime table and optional converter |
| 3 | `0x01670ef0` | `0x0168ac3c` (`0x01670fa8`) | Copies per-domain `0x3c` bytes from input `+0x5e0` to object `+0x5e0` |
| 4 | `0x01671270` | `0x0168b2a8` (`0x01671368`) | Copies per-domain `0x40` bytes from input `+0x5ec` to object `+0x5ec` |
| 9 | `0x01670fca` | `0x01692ea8` (installed by the associated derived constructor path; the constructor at `0x01671558` in the supplied mapping) | separate derived implementation; input mapping requires its constructor body for complete field lineage |

Other selector values go to the factory's error path. Branch-1's AUIPC source PC matters: `0x01671202` + `0x000b0000` - `0x3d6` resolves to `0x0167be2c`, **not** `0x0167be50`.

This is enough to name factory classes by their encoded selector and to reject transplanting R570's `0x3c` index. It is **not enough to assert which selector GB202 actually chooses**: the three factory callers located at `0x01198f0a`, `0x01198fb8`, `0x01199018` pass different object records through an indirect follow-up constructor/method. I did not establish the GB202 model's selector byte as it enters those callers, or a GB202-specific registry row resolving it. Therefore no claim that GB202 uses selector 1/3/4/9 is made. The next exact step is to recover the GB202-specific descriptor/registry record feeding `0x01670ea0` and read its byte `[0]` (also establish whether model-index input is the R610 domain mapping rather than an R570 layout).

### What writes the bytes consumed as range data

The known non-Perf getter implementations are **read/copy accessors**, not writers:

- `0x01668f40`: returns 0x3c bytes from `object + domain*0x54 + 0x61c` (selector-16 mapping can remap the domain). Its slot setter is in constructor `0x0166df26`; that constructor is outside the four factory cases listed above and I did not establish which GB202 route instantiates it.
- `0x0168ac3c`: returns from `object + domain*0x3c + 0x5e0`.
- `0x0168b2a8`: returns from `object + domain*0x40 + 0x5ec`.
- `0x01692ea8`: maps a domain and returns a range-cache record (the complete caller/field interpretation is not advanced here).
- `0x0167be2c`: does not copy a static per-domain cache. It obtains a domain/perf object through vtable `+0x38`, its related object through `+0x558`, reads baseline min/max at related-object `+8/+0xc`, and for one type reads three values from a table row addressed from Pstate/perf state. For relation type 3 it calls `0x01bcebe4` on those values before writing triplicate min/max pairs into the caller's 0x3c-byte output buffer.

The factory itself supplies concrete cache **initialization/copy writers** for two branches: selector 3's loop copies input `+0x5e0` records to the new object's `+0x5e0`; selector 4's loop copies 0x40-byte input records beginning `+0x5ec` to object `+0x5ec`. The selector-1 path copies scalar fields from the input descriptor, installs `0x0167be2c`, and that getter synthesizes output from Perf/runtime values as above. Constructor `0x0166df26` installs the `0x01668f40` getter but its corresponding originating factory branch/writer was not identified. This closes the immediate object-field writer path only for the explicitly traced constructors, not the origin of descriptor/table values.

Consequently the evidence supports these limited origins:

1. **Selector 3 / 4 cache bytes:** copied from the factory's input descriptor, then served by a getter. No instruction in the recovered factory labels those source bytes as VBIOS, RPC, OC offset, or a specific capability-limit record.
2. **Selector 1 dynamic values:** read from related Perf/domain objects and one runtime table; conversion may be applied through `0x01bcebe4`. The runtime table's producer and converter semantics are not recovered here.
3. `MCLK_MAX_CAPABILITY` is only a name/descriptor from the preceding review; no producer edge from that capability to these cache fields has been established. Do **not** attribute the resulting min/max to VBIOS, RPC, OC offset, or capability limit yet.

### Compact pseudocode (structural, names are descriptive)

```c
pstate_factory(desc):
    switch (desc->kind) {            // byte at +0
    case 1:
        obj = make_kind1(desc);
        copy_scalar_fields(desc, obj);
        obj->slot548 = range_from_perf_table;  // 0x0167be2c
        return obj;
    case 3:
        obj = make_kind3(desc);
        for (d = 0; d < perf_domain_count; ++d)
            memcpy(obj + 0x5e0 + d*0x3c, desc + 0x5e0 + d*0x3c, 0x3c);
        obj->slot548 = copy_3c_cache;           // 0x0168ac3c
        return obj;
    case 4:
        obj = make_kind4(desc);
        for (d = 0; d < perf_domain_count; ++d)
            memcpy(obj + 0x5ec + d*0x40, desc + 0x5ec + d*0x40, 0x40);
        obj->slot548 = copy_40_cache;           // 0x0168b2a8
        return obj;
    case 9: return make_kind9_with_mapped_cache(desc); // 0x01692ea8, constructor path 0x01671558
    default: error;
    }
}

range_from_perf_table(domain):
    related = perf_domain(domain)->related(+0x558);
    base = related->minmax(+8,+0xc);
    row = perf_table_row(domain);
    if (relation_type == 3) convert_each(row[0..2], 0x01bcebe4);
    emit three {min,max} pairs to output;
```

### Original-instruction evidence and provenance

`new_original_instruction_windows.asm` contains the newly relevant raw LLVM decode windows for the factory switch/constructors, the slot-548 checker, and getter bodies. It is an excerpt of `parent_capability/gsp61057_full.asm`, which was produced from the supplied full-main view; instruction addresses are inner ELF VAs. The underlying original `windows_driver_compare/610.88/inner/linux-610.57.04-gsp-main.elf` SHA-256 is `ee1475a798c6a8cb8ecac7d58e18e2bbbbfa51569186ce958feaebe976af773a`; the existing provenance record says the view maps RX to VA `0x01000000`, includes the complete RX/RW, and prior project-byte checks compare representative functions to the original. View SHA-256: `8b66217940da2cc4de6869ce613a599ceda6734adf6305c83b6b77e041d8b781`.

Interpretive references: prior getter recovery in `../gsp_mclk4000_review_20261010/parent_capability/pstate_range_slot548_recovered.c`; raw slot-548 instructions in `../gsp_mclk4000_review_20261010/parent_capability/pstate_range_original_instructions.asm`; provenance in `../gsp_mclk4000_review_20261010/parent_capability/full_main_provenance.json`. No Ghidra was opened in this task, so no project/index change.

## Closed facts / remaining one-hop questions

- **Closed:** factory address and byte selector; selector 1/3/4 branch-to-getter mapping; selector 9's recovered constructor/getter association; immediate cache copy writer for selector 3/4; selector-1 Perf-table/runtime synthesis; proper AUIPC PC. Getter `0x01668f40` is bound to constructor `0x0166df26`, but not to a factory selector.
- **Not closed:** which selector the GB202 descriptor feeds at R610 factory entry; identity/source of the factory descriptor; actual producer feeding selector-3/4 descriptor cache; producer of the selector-1 Perf runtime table; whether/how `MCLK_MAX_CAPABILITY`, VBIOS range, RPC, or OC offsets contribute to those values. No runtime values are inferred.

## Verification

- Read the specified prior report, validator review, recovered getter C, and original range ASM.
- Confirmed hashes for the original complete-main ELF and supplied full-main view with `sha256sum`.
- Generated the new instruction excerpt from the existing complete-main disassembly; no firmware execution or Ghidra analysis performed.

# MCLK_MAX_CAPABILITY producer hunt (bounded pass)

## Scope and result

Target: `MCLK_MAX_CAPABILITY` name at RX VA `0x1e8e860`, descriptor words at `0x1e23b18..0x1e23b30`; comparison neighbor `MCLK_LIMIT` at `0x1e22e78/0x1e22e88`. Inputs were GSP 610.57 RX VA `0x1000000` and RW VA `0x4000000`; the prior complete-main view was used only as the provided static reference. No GPU, MODS, or firmware execution was performed.

This pass **did not close** either numeric value's semantic identity, a runtime activation/producer, or the source class (chip/VBIOS/OC/capability). In particular, it does not support calling `0x122` “ID 290” or attributing the table to a runtime producer. Nor is there new evidence here that this descriptor causes an ~18 GHz absolute-MCLK threshold. Those remain open questions, not negative findings.

## Evidence from this pass

- Read the existing `parent_capability/NOTES.md` first. Its descriptor bytes are `1e23b18=[u32 0xff,u32 0x122]`, `1e23b20=0x11e`, name pointer `1e23b28 -> 1e8e860`, and trailing `0xff02` at `1e23b30`; neighbor MCLK_LIMIT is as stated there.
- Copied the existing Ghidra project into `sandbox/` before using it. The only Ghidra invocations used `-readOnly -noanalysis`; no old project/database was opened for modification or refreshed.
- Ghidra `XrefsTo` found no ordinary code references to the descriptor addresses or either name address. Given this appears to be a static metadata table, the absence of modeled xrefs is inconclusive; it does not establish that the names/table are display-only.
- Ran an exact-instruction-operand scan for `0x122` and `0x11e`, saved as `scalar_hits.log`. The results are broad and mostly unrelated RV64 operands. The known false-positive `0x122` at `0x013002d4` is present, confirming why a scalar hit alone is not evidence. No hit was promoted to a producer. The scan only catches exact scalar operands and cannot exclude const-building sequences.
- The supplied prior notes explicitly exclude known false positives: `0x01183ddc`'s `0xfb` is a bindata/group entry; `0x013583d0`'s `0x122` is part of a LUI/register-address construction; `0x013002c4/0304`'s `0x122` is an index offset. None is treated as the target producer here.

## Current conclusion / stopping point

At this bounded stopping point the distinction requested between a display-name table and the actual producer is **unresolved**. The immediate useful next step is to identify the table's loader by following the descriptor's containing array/group reference or a consumer of its entry layout, then correlate the decoded numeric fields through that consumer's enum/name lookup. After that, follow the specific MCLK_MAX_CAPABILITY dispatch into its update function and inspect the value source and any absolute-MCLK comparison. Do not infer semantics from numeric coincidence.

No finding in this pass changes the prior finding that there is no established `~18000` comparison in the examined MCLK path; the current search was not sufficient to prove absence.

## Reproducibility and artifacts

- `sandbox/gb202_gsp61057.gpr` and `sandbox/gb202_gsp61057.rep`: local copy of the Ghidra project used read-only.
- `scalar_hits.log`: Ghidra exact-operand scan output for `0x122` and `0x11e`.
- `new_raw_instructions.txt`: 345 exact operand-hit instruction lines extracted from that scan, with function addresses where Ghidra supplied them. These are raw candidate instructions, not confirmed consumers.
- Commands were `analyzeHeadless ... -readOnly -noanalysis -process gsp_inner_61057.elf ... XrefsTo.java ...` and `FindExactScalar.java 0x122/0x11e` against the sandbox project. First attempted Ghidra path was invalid; actual executable was `/opt/ghidra/support/analyzeHeadless`.

No original firmware, source project, or Ghidra database outside this new directory was changed.

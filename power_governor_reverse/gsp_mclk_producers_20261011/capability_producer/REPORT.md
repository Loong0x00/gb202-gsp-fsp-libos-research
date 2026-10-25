# Capability producer follow-up — bounded static result

## Result

This pass did **not** close the updater for the special capability source with `source+0x58 == 0xff` and `source+0x5c == 0x122`. I did not identify a function that matches those fields and writes a resulting MCLK maximum, nor prove that this row is active on the target. The metadata/factory chain alone remains insufficient for that conclusion.

One concrete frequency-input path was recovered nearby and is useful as a boundary:

- `FUN_0168e04c` consumes per-domain records (`param_3`, domain stride `0x24`) with frequency-like endpoints at record `+0x54/+0x58` and a second optional interval at `+0x5c/+0x60`; it calls `FUN_0168ddf8` to resolve these into output ranges and accumulates extrema into domain records at `param_3 + domain*0x30 + 0x304..0x31c`.
- `FUN_0168ddf8` passes its first pair of u32 endpoints to `FUN_01aed400`, which returns two u32 outputs. It then walks the Perf/Pstate-like object at `param_2+0x1af0`; eligible entries (checks include state byte `+0x19c`, class/value `+0x1a4 == 4`, domain byte `+0x1a8`, flags at `+0x60`) can tighten the outputs from per-domain values at `state + 0x10 + (domain+0x68)*8`. This is evidence that this range consumer combines a base interval with dynamic Perf/Pstate inputs; it is **not** proof these are the `MCLK_MAX_CAPABILITY` row's inputs.
- The entries in `0168e04c` are not shown to be the factory source object. Record offsets differ from the descriptor-loader's `source+0x58/+0x5c`, so conflating them would be unsafe. No MCLK-domain selector or row-`0xff` match was established here.

## Evidence / reproduction

- `frequency_range_consumer.asm`: original RV64 instruction windows from the supplied complete-main ELF view, generated with `llvm-objdump -d --mattr=+m` for `0x0168ddf8..0x0168e3b8` and `0x0168e04c..0x0168e6a0`.
- Read-only Ghidra decompilation was performed against the existing `control_dispatch/work_db` with `-readOnly -noanalysis`; no database save or GPU/MODS/firmware execution.
- Supporting transient decompilation outputs: `/tmp/ddf.log` and `/tmp/cands.log` (not project evidence artifacts).

## Next step

To answer the requested producer question, follow concrete stores/loads for the object instance populated by the type-6 factory and recover the call path that uses its `+0x58/+0x5c` fields. In particular, distinguish the metadata descriptor from the later runtime range record. Until that link is proven, activation and the MCLK-capability value source remain unresolved.

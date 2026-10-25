# R610.57.04 GB202 GSP-RM VF-relation SET / MCLK offset validator

Date: 2026-10-10. Static-only review of the locally installed 610.57.04 GSP bundle and its extracted RX bytes. No GPU/MODS execution, RM setter, MMIO, or firmware edit was performed. No Ghidra program database save was requested; the read-only project open refreshed small repository index metadata, disclosed under Verification below.

## Result

**No hard-coded `+4000 MHz` (`4,000,000 kHz`), `18,000/18,001 MHz`, or `17,000 MHz` / `34 Gbps` comparison was found in the decoded `0x2080d073` dispatch, the type-7/type-9 VF-relation SET importers, or the related GSP relation-frequency range-check routine listed below.** This is scoped to those recovered functions; it is not a negative claim about the opaque nested payload, PMU firmware, or every clock-control path.

The R610 GSP SET path imports a 32-bit relation-control word at record `+0x08` directly into object state. Its type-specific importer has no frequency-limit comparison. Separately, the R610 GSP VF-relation processing path contains an **unsigned, runtime-data-driven range check** for an absolute relation frequency: a 16-bit MHz value at object `+0x62` is multiplied by 1000 and compared to min/max values filled by an indirect runtime callback. The code does **not** compare that absolute frequency against a fixed 17,000/18,000/18,001 MHz constant.

The important distinction is that the direct call edge from this `0x2080d073` SET import to the `0x01670320` absolute-frequency checker is not established here. Thus the evidence proves a dynamic range check exists in related GSP VF-relation processing, but does not prove that this checker validates the imported `+0x08` offset synchronously during SET. The importer itself does not clamp or reject that offset by a visible numeric limit.

## Firmware provenance and address basis

See [`firmware_provenance.json`](firmware_provenance.json). The wrapper is `/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin`, SHA-256 `c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999`; inner ELF SHA-256 `88cb25e9940d9b242a8dc518291d028519b1f7b734954c6d358112b4af0a690e`. The reviewed RX extract hashes to `50614073f1ca73d4a10e66bdba15e557763b402c75b203a8950161c0afe59085`, maps inner offset 0 to VA `0x01000000`, and matches the recorded extraction verification.

The file called `gsp61057_rx_full.bin` omits the last `0x4000` bytes of the RX PT_LOAD; all function ranges in this report are below that tail. Addresses below are inner-ELF virtual addresses, **not** wrapper file offsets.

The raw instruction listing is [`gsp_validator_disassembly.asm`](gsp_validator_disassembly.asm), generated from the hash-checked original RX bytes with LLVM 23.1.1 and `--triple=riscv64-unknown-elf --mattr=+m,+a,+c,+f,+d`. The script [`decode_gsp_validator_ranges.sh`](decode_gsp_validator_ranges.sh) reproduces it. It emits compressed instructions and `M/A/F/D`-capable decoding; no Capstone-only/default-extension omission is relied on. The address-to-function extents were read from the existing Ghidra project with `-readOnly -noanalysis`; no program analysis changes or project save were requested. Ghidra did refresh repository index metadata on open; see Verification.

## R610 GSP-RM SET path and fields

The method table record at RX VA `0x01c20b60` is preserved in [`api_2080d073_descriptor.hex`](api_2080d073_descriptor.hex): method `0x2080d073`, parameter size `0x37ec`, descriptor pointer `0x01c23870`, handler `0x01105f5c`, flags `0x44`.

Existing R610 ABI recovery gives the control-array base `+0x24`, stride `0x38` (56 bytes), maximum 255 records. The handler at `0x01105f5c` is a generic dispatcher: after a pointer chain it loads the selected group from a computed parent object's `+0x170`, calls the group accessor at `+0x20`, then tail-dispatches through group `+0x28`. It has no inline frequency comparison. The exact runtime `+0x28` function pointer for this particular group instance was not independently resolved to a fixed address, so I do not silently equate it with the apply method installed on a different group.

The type-specific slots are independently recovered from the constructors:

- Type 7 constructor `0x011240f0` installs object-state `+0x30 = 0x0111c14c` (`clk_vf_rel_type7_method30`).
- Type 9 constructor `0x01124484` installs object-state `+0x30 = 0x0111f594` (`clk_vf_rel_type9_method30`).
- `0x0111c14c` calls `type7_control_import` at `0x0111c008`; on success it loads a **u16** from input record `+0x2c` and stores it to object `+0xbe`. This is a separate selector-like/sentinel field (current R610 CONTROL readback uses `0xffff` for type 7); it is not the 32-bit offset word.
- `0x0111f594` delegates to type-7 method 30 and imports the type-9 extension through `0x0111f360`.
- `0x0111c008` first calls the common BoardObj-control type check at `0x01ae404c`, then copies fields: a u32 from record `+0x04` to object `+0x68`, a 32-bit word from `+0x08` to object `+0x6c`, and a count-indexed u32 from `+0x0c + 4*i` to object `+0x64`; the index/count byte is read from object `+0x60`. The raw sequence is `lw`/`sw`, not a frequency compare or unit conversion.

| GSP location / field | Width and operation | Unit / interpretation | Evidence and limit source |
|---|---|---|---|
| API `0x2080d073`, record `+0x08` | 32-bit word copied by `lw`/`sw` | GSP importer itself treats it as opaque; the same MODS 570.215 method treats the corresponding word as signed `freqOffset_kHz` | No numeric comparison in `0x0111c008` / `0x0111c14c`; unit attribution is cross-build ABI evidence, not a conversion in this GSP code |
| API record `+0x04` | 32-bit word copied | Flag/control word; exact GSP meaning not renamed here | Common object-type validation plus direct copy |
| API record `+0x0c + 4*i` | 32-bit words, index from object `+0x60` | Opaque indexed control values; unit not recovered | Direct indexed load/store; no frequency conversion |
| API record `+0x2c` | u16 copied to object `+0xbe` | Selector-like field; no frequency unit | `0x0111c14c`; prior CONTROL/status model identifies `0xffff` sentinel, exact internal name remains inferred |
| VF relation object `+0x62` in `0x0111cc80` | u16 load, multiply by 1000 into 32-bit value | MHz to kHz conversion | Raw instructions at `0x0111ccec..0x0111ccf8` (type-7 path); it is not the imported offset field at record `+0x08` |

The absence of a bound compare in the type-7 importer is direct: after the common type check, it copies the words and returns the helper status. The type-7 method-30 wrapper only calls that importer and stores the u16 field. Bounds on values elsewhere in those functions concern type IDs, entry/counts, and error handling—not `+4000` or an MCLK ceiling.

## Related GSP runtime capability-range check

`vf_rel_method_b0` at `0x0111cc80` handles the type-7/type-11 switch cases (`*record` values 7/11 enter cases 1/5). It loads the internal u16 at `+0x62`, executes `li 1000; mulw`, and calls `0x01670320` with mode 0. This is an absolute frequency path, distinct from the signed kHz offset copied from SET record `+0x08`.

At `0x01670320`, a returned object’s virtual slot `+0x548` is called with an output pointer to stack locals. Those locals are then loaded as 32-bit min/max values. In the mode-0 branch:

```text
0x01670436  lw    max, -0x9c(s0)
0x0167043a  lw    min, -0xb0(s0)
0x016703ce  bltu  max, request, ...
0x016703d2  bltu  request, min, ...
```

`bltu` confirms unsigned 32-bit comparisons. The bound values come from the runtime indirect callback at object `+0x548`; the exact leaf source/value was not recovered here, so they are described as runtime-supplied capability/range data, not asserted to be VBIOS fields. A special object-type branch selects another pair of callback-filled values. This is the observed dynamic limit source; the operands are not literals 4,000,000 / 17,000,000 / 18,000,000 / 18,001,000.

The checker iterates available objects/domains and has sentinel/error returns; it is not a simple `if (offset >= 4000000)` validator. No run-time range values were read or executed in this review.

## MODS CPU-RM `0x06e204c0` comparison — different build

The existing static analysis `mods570215_rm_vfrel_validate.c` is from **MODS 570.215 x86-64 CPU RM**, not the 610.57.04 GSP-RM binary. At `vfrel_control_set_validate` `0x06e204c0`, the CPU RM rejects a nonzero byte flag at `param3+4`; reads an `int`/s32 at `param3+8`; and requires `offset <= max && min <= offset`. It obtains max via `get_max_oc_offset` `0x06e20340` and min via `get_min_oc_offset` `0x06e201c0`. Both helpers follow runtime virtual methods (clock-domain slot `+0x38`, then relation-object method `+0x18` for max / `+0x20` for min). The compared limits are callback-derived; no literal `+4000` appears in that validator.

This is evidence about that MODS CPU-RM build only. It does **not** prove the GSP importer uses the same leaf range data or that a MODS/PMU failure stack applies to R610.57.04. In particular, the prior 570.215 `+3999/+4000` runtime findings are not imported as an R610 GSP limit or fault-stack attribution.

## Public `kernel_gsp.c` host-KMD boundary

The locally available open NVIDIA kernel-module source is commit `d7b969d1210f6c655c16b7837ef1f559ee6e72d4`, whose `version.mk` says **610.43.03**, not 610.57.04. In `src/nvidia/src/kernel/gpu/gsp/kernel_gsp.c:205-209`, `_kgspGetActiveRpcDebugData` reads the CPU-to-GSP `GSP_RM_CONTROL` RPC `cmd` and `paramsSize` for debug history. This is host KMD transport/diagnostic code; it does not implement the target GPU-side GSP-RM `0x2080d073` validator. It is not used as a substitute for the R610.57.04 RX instructions above.

## Bottom line / uncertainty

- **Hard `+4000`, `18,000/18,001 MHz`, `17,000 MHz`, or `34 Gbps` compare in reviewed GSP SET/import path:** not found.
- **R610 GSP literal offset ceiling:** not found in the importer; `+0x08` is copied as a 32-bit word.
- **Runtime constraint elsewhere in GSP VF relation processing:** yes—absolute u16-MHz relation frequency is converted to kHz and compared to callback-filled 32-bit bounds. Its values and exact leaf source are runtime-derived and unknown here.
- **Does this range checker directly validate `0x2080d073` record `+0x08` during SET?** not established; keep the two fields/paths distinct.
- **Could the downstream PMU/embedded consumer or omitted/opaque firmware reject a resulting target?** remains open. No claim about actual runtime behavior or fault stack follows from this static review.

## Reproduction / checks

```sh
sha256sum power_governor_reverse/gsp61057_rx_full.bin \
          power_governor_reverse/gsp61057_rw_full.bin \
          /usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin
python3 vbios_diff/gb202_boot_upstream_20260911/gsp_upstream/verify_extracts.py
power_governor_reverse/gsp_mclk4000_review_20261010/validators/decode_gsp_validator_ranges.sh
```

The extract verification matched the recorded wrapper/inner/RX/RW hashes and mapping. The custom decoder completed successfully with `+M,+A,+C,+F,+D` enabled. No hardware-facing command was run. The read-only Ghidra headless opens refreshed only `ghidra_static/gb202_gsp61057.rep/idata/~index.{bak,dat}` and `ghidra_static/gb202_gsp61057.rep/versioned/~index.{bak,dat}`; each `.bak` is byte-identical to its `.dat` (SHA-256 `5236b548...` for `idata`, `0a503499...` for `versioned`). The main program store `idata/00/~00000000.db/db.559.gbf` and project `.gpr` timestamps remained unchanged. This index-metadata side effect is disclosed rather than claiming that every byte of the old project directory was untouched.

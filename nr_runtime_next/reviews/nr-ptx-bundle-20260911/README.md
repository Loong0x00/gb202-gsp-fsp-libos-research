# Exact e16 DLL embedded PTX bundle — CPU/static only

## Result and limits

- **15/15 `.data` fatbinaries**, each containing one zstd PTX record followed by one native ELF record; bijective match to all **15 ELFs** in `../nr-static-layout-20260911/source-manifest.json`.
- **231 entries**, **37,129,930 exact decompressed PTX bytes**, **913,415 static PTX instructions**. PTX plus verbatim cuobjdump text totals **74,263,909 bytes**, below 100 MB. No non-entry `.func` declarations were found. All PTX is `.version 9.4`, `.target sm_120`, `.address_size 64`.
- All new files are under this directory. DLL and prior review artifacts were opened read-only; eight consumed original files were SHA-256 checked before and after, unchanged (`input-integrity.json`). No GPU, Wine, CUDA driver API, DLL/kernel execution, patching, recompilation, or SASS dump was used. `cuobjdump` and libzstd run on the CPU.
- **Container capture does not establish whether native ELF or PTX was selected. Selection remains unknown. PTX names and instructions do not establish PyTorch or other high-level source provenance.** This is exact embedded intermediate code, not recovered original high-level source and not a validated reconstruction.
- Coverage is the bounded PE `.data` section and its existing ELF inventory, not an assertion about unrelated resources or other DLLs. All fatbinary magic occurrences in that section were parsed; none were silently skipped.

## Provenance and first actual capture

DLL: `/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll`

- Size: **165,840,496 bytes**.
- SHA-256: `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.
- `.data` raw extent: **[911872, 18092544)** (half-open DLL file offsets).
- Module 00: DLL offset **913632**, **3944768 bytes**, SHA-256 `c11e2eb6f6eeabadffe340dba74ec8c3f474f4ac4a8ed601d59e04d1d49bda3d`.
- Compared **all bytes**, not only hashes, with `../nr-static-followup-main-20260911/runs/20260911-122501-observer_on/observed-finalpost-module.cubin`. Despite that file's extension, these captured bytes are the whole fatbinary.
- Inner ELF: relative offset **1155392**, DLL offset **2069024**, **2789376 bytes**, SHA-256 `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`; all bytes match `../nr-static-layout-20260911/finalpost-sm120.cubin`.
- Newly generated module-00 cuobjdump stdout is byte-identical to `../nr-static-followup-main-20260911/observed-module-ptx.txt` (**9309080 bytes**).
- Prior `finalpost-original.ptx` is an exact substring of module-00 raw PTX at byte offset **1283746**; no whitespace or other transformations were used for this check.

## Files and byte preservation

- `manifest.json`: exact input hashes, PE bounds, record offsets/sizes/raw headers, compressed-frame hashes, ELF inventory mappings, output hashes, tool version/command, entry names, and capture comparisons.
- `modules/<id>.fatbin`: exact, bounded DLL slice. ELF remains inside it; no duplicate CUBIN or all-SASS output.
- `modules/<id>.ptx`: **exact libzstd decompression, including the single terminal NUL**. Normalization is **none**: no trimming, newline conversion, substitutions, guessed transforms, demangling, or formatting.
- `modules/<id>.cuobjdump-ptx.txt`: verbatim `cuobjdump -ptx` stdout, including NVIDIA's PTX/ELF metadata wrappers. `*.cuobjdump-stderr.txt` preserves stderr (all empty).
- Every raw PTX, except its one terminal NUL which cuobjdump does not print, is a unique byte-identical substring of its cuobjdump stdout; exact comparison offsets are in the manifest. The NUL is retained in the `.ptx` artifact. Some text tools therefore classify `.ptx` files as binary; use `grep -a` or the cuobjdump text for browsing.
- `modules/<id>.analysis.json`: every entry's exact name, declaration text, parameter storage byte counts/alignment, byte/line ranges, slice SHA-256, full-opcode and base-opcode histograms. Entry ranges start at `.entry` (not its `.visible` qualifier) and end after its matching closing brace.
- `entries.tsv`: compact all-entry index, parameter bytes/spans, instruction counts, and raw PTX byte ranges.
- `opcode-histogram.json`: aggregate full-opcode counts across all entries.
- `extract_bundle.py`, `test_bundle.py`: reproducible bounded extractor and CPU-only tests.
- `extraction.log`, `tests.log`, `cuobjdump-version.txt`, `input-integrity.json`: evidence. `SHA256SUMS` covers bundle files except itself and `checksum-verification.log` (the check's output).

Parameter byte totals are sums of PTX declaration storage. The separately reported span includes inter-parameter alignment but **does not invent final ABI padding, host structs, pointer pointees, or captured parameter values**. Opcode counts are lexical static instruction counts, not runtime frequency, SASS counts, or proof of an algorithm. Full modifiers are preserved; base histograms group at the first period. Analysis masks comments/strings only in memory, balances entry bodies, handles predicates/labels/vector operands, and fails on unsupported declarations or unparsed statement starts. No artifact text is rewritten for analysis.

## Module/reconstruction index

Labels below summarize observed entry names, not verified model topology. DLL offsets and sizes are decimal. See `entries.tsv` for all 231 names and exact parameter byte counts.

| Module | Fatbin DLL offset | Fatbin bytes | ELF DLL offset | PTX bytes | Entries | Static instructions | Name-based focus |
|---|---:|---:|---:|---:|---:|---:|---|
| [00](modules/module-00-dll-000df0e0.analysis.json) | 913632 | 3944768 | 2069024 | 9308801 | 38 | 225659 | pre/post `swin_1h_32`, FP8, blend/control-mask variants |
| [01](modules/module-01-dll-004a2220.analysis.json) | 4858400 | 2473688 | 5690584 | 5738680 | 24 | 138371 | fused `swin_2h_64` variants |
| [02](modules/module-02-dll-006fe100.analysis.json) | 7332096 | 2419288 | 8161200 | 5588093 | 24 | 137036 | fused `swin_4h_128` variants |
| [03](modules/module-03-dll-0094cb60.analysis.json) | 9751392 | 2637352 | 10691568 | 6275440 | 24 | 152773 | fused `swin_8h_256` variants |
| [04](modules/module-04-dll-00bd0990.analysis.json) | 12388752 | 2114088 | 12965712 | 3954406 | 46 | 98199 | split `swin_16h` / FFWD variants |
| [05](modules/module-05-dll-00dd4bc0.analysis.json) | 14502848 | 3202680 | 15214296 | 5555470 | 62 | 141094 | `cc_vit_*` FFN/QKV/attention/projection/repack names |
| [06](modules/module-06-dll-010e2a40.analysis.json) | 17705536 | 255312 | 17789712 | 613658 | 5 | 17580 | `cc_dec_input_upsample_*`, `cc_cb_clear` |
| [07](modules/module-07-dll-01121b90.analysis.json) | 17963920 | 8016 | 17965056 | 2612 | 1 | 75 | `cuda_font_kernel` |
| [08](modules/module-08-dll-01123af0.analysis.json) | 17971952 | 10904 | 17973096 | 3944 | 1 | 133 | `cuda_capture_kernel` |
| [09](modules/module-09-dll-01126590.analysis.json) | 17982864 | 11792 | 17984160 | 4720 | 1 | 151 | `cuda_capture_output_exposure_scale_kernel` |
| [10](modules/module-10-dll-011293b0.analysis.json) | 17994672 | 10560 | 17996256 | 5138 | 1 | 144 | `cuda_capture_mv_dilate_kernel` |
| [11](modules/module-11-dll-0112bd00.analysis.json) | 18005248 | 9960 | 18006488 | 4097 | 1 | 131 | `cuda_capture_buffer_as_texture` |
| [12](modules/module-12-dll-0112e3f0.analysis.json) | 18015216 | 6552 | 18015880 | 1007 | 1 | 23 | `cuda_clear_view_kernel` |
| [13](modules/module-13-dll-0112fd90.analysis.json) | 18021776 | 54824 | 18036728 | 72298 | 1 | 2007 | `cg2r_post_process_kernel` |
| [14](modules/module-14-dll-0113d3c0.analysis.json) | 18076608 | 6936 | 18077432 | 1566 | 1 | 39 | `cg2r_copy_kernel` |

### First captured module: finalpost FP8 focus

These five exact entry names also appear in the prior selected ELF inventory. Their declarations are explicit byte arrays, so no hidden struct layout is inferred here. Module 00 also contains non-FP8 finalpost and pre/post-related variants; do not assume a particular variant was launched merely because it is present.

| Entry | Declared parameter bytes | Static instructions | Raw PTX lines (inclusive) |
|---|---:|---:|---|
| `cc_tinlayout_fused_post_block_swin_1h_32_fp8` | 184 | 6805 | 78255–94520 |
| `cc_tinlayout_fused_post_block_swin_1h_32_fp8_simple_blend` | 312 | 6890 | 111772–128126 |
| `cc_tinlayout_fused_post_block_swin_1h_32_fp8_simple_blend_full_rect` | 312 | 6876 | 145364–161704 |
| `cc_tinlayout_fused_post_block_swin_1h_32_fp8_control_mask` | 312 | 6911 | 178976–195351 |
| `cc_tinlayout_fused_post_block_swin_1h_32_fp8_control_mask_full_rect` | 312 | 6883 | 212595–228942 |

For reconstruction triage, compare same-family entries and modifiers before inferring equivalence. The aggregate contains 35,072 `mma.sync.aligned.m16n8k16.row.col.f16.f16.f16.f16`, 19,728 `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16`, and 24,736 `cvt.rn.satfinite.e4m3x2.f16x2` instructions. These are literal PTX opcodes/counts, not claims about high-level framework or runtime usage. Per-entry full-modifier histograms are the more useful comparison unit.

## Parsing and verification

1. Verify exact DLL hash/size. Bounds-check DOS/PE32+ headers, section table and every stored section; reject section overlaps. Search **only `.data` raw bytes** for `50 ed 55 ba`.
2. Require outer `<IHHQ>` magic `0xba55ed50`, version 1, 16-byte header, bounded u64 data length. Parse contiguous records using the observed `<HHIQ>` kind/version/header-size/padded-payload-size layout; require record version `0x0101`. Reject malformed, nested, overlapping, truncated, oversized, or unsupported candidates rather than silently skipping them. This deliberately supports the observed exact-DLL layout, not every possible CUDA fatbinary format.
3. For PTX, validate zstd magic and obtain exact compressed-frame/content sizes independently from libzstd. Require these to agree with observed raw header fields at +16 (u32 compressed length) and +56 (u64 expanded length); permit only 0–7 zero padding bytes. Raw headers are recorded, avoiding speculative interpretation of unknown fields.
4. Bounds-check every ELF64 program/section table and stored segment/section (excluding fileless `SHT_NOBITS`). Require computed file extent, inventory size/RVA/flags/SM, and record extent to agree. Require a one-to-one mapping of all 15 inventory ELFs and nonoverlapping outer containers.
5. Enforce container/decompression/text caps, CPU timeouts and a cuobjdump output-file size limit; redirect tool temporary paths inside this directory. Decompress exact PTX bytes, run `/opt/cuda/bin/cuobjdump -ptx` on each bounded local container, compare bytes, and write indexes/histograms. NVIDIA cuobjdump is **13.3.73**; libzstd version is recorded in the manifest.
6. Re-hash consumed original inputs; independently test emitted hashes, exact capture/stdout identity, all-entry spans/counts, and instruction/declaration semicolon conservation.

Run from this directory (these commands only create/overwrite files here):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 extract_bundle.py > extraction.log 2>&1
PYTHONDONTWRITEBYTECODE=1 python3 test_bundle.py > tests.log 2>&1
sha256sum -c SHA256SUMS
```

**37 tests passed**, covering every byte truncation of synthetic PE/fatbin/ELF/zstd fixtures; hostile u32/u64 bounds, zero/negative/oversized sizes, record truncation, nonzero padding, malformed/nested magic, section clipping/overlap, invalid ELF extents/tables, 300 deterministic randomized hostile length mutations, zstd length/cap/trailing-frame checks, PTX parameters/predicates/inline scopes/vectors/comments, and read-only real-bundle checks. Tests do not execute artifact code or invoke a GPU. Rerunning extraction/tests changes log timing; regenerate checksums if intentionally rebuilding the bundle.

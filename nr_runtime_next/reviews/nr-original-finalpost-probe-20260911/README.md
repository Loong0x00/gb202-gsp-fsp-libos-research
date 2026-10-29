# Original finalpost isolated oracle — CPU-only blocked proposal

**Status: BLOCKED_SURFACE_OBJECT_ABI_NOT_ESTABLISHED.** This is not a completed
GPU oracle. Eight CPU tests pass and the standalone Linux CUDA Driver host
compiles with warnings-as-errors. **No host executable, CUDA API, runtime
initialization, or GPU work was executed.** See [SURFACE_ABI.md](SURFACE_ABI.md)
for the exact remaining launch-safety boundary.

## Scope

New standalone host for the **original unmodified SM120 ELF**, not a DLL,
frontend/architecture code-patch probe or recompiled kernel:

* Original file: `../nr-static-layout-20260911/finalpost-sm120.cubin`
* Bytes: **2,789,376**; SHA-256:
  `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`
* Exact entry: `cc_tinlayout_fused_post_block_swin_1h_32_fp8`
* One CTA: grid `(1,1,1)`, block `(32,1,1)`, dynamic shared memory 0.
* Direct `cuModuleLoadData` on hash-checked original ELF bytes, never PTX/fatbin
  selection, header downgrade, architecture editing, NVX hooks or NR loading.
* Explicit **synthetic internal main/enc0-skip activations**, with real encoded
  block70 weights. This is NOT an image-to-model inference or whole-model parity.

Only this review directory was used for new project artifacts. Archived
references/captured scalar arguments and original weights were read on CPU;
`verify_live_contract.verify()` was NOT invoked (it has unrelated side effects).
No original NR GPU pool was accessed. The ELF remains at its original path;
no modified copy was created.

## Exact 184-byte parameter plan

The fixture template contains **zero in every address/handle slot**. The host
replaces them only with its own Driver-returned values. CPU tests use separate
symbolic Memory keys, not GPU addresses, and never dereference such keys.

| Offset | Field / proposed value |
|---:|---|
| 0 | own `cuMemAlloc` main pointer |
| 8 | own `cuMemAlloc` enc0-skip pointer |
| 16 | own `cuSurfObjectCreate` result **(ABI unproved; launch blocked)** |
| 24 | own `cuMemAlloc` 21,808-byte real encoded block70 slab pointer |
| 32,36 | padded H,W = 16,16 |
| 40,44 | signed origin X,Y = 0,0 |
| 48,52 | FP32 multiplier 1/32, decode flag 1 |
| 56 | own source-A `cuTexObjectCreate` result |
| 64,68 | captured A offsets 0,0 |
| 72,76 | captured A extents rescaled from 768,432 to 16,16 |
| 80,84 | captured A reciprocals rescaled to 1/16,1/16 |
| 88,96 | texture B,C = null (no history) |
| 104 | own 2-byte allocation with **real blend coefficient**, FP16 0.73974609375 |
| 112 | captured displacement flag 1 (history branch inactive) |
| 116..160 | preserve captured zero scalar bytes; no fabricated history transforms |
| 164,168 | captured reciprocals rescaled to 1/16,1/16 |
| 172,176 | source W,H = 16,16 |
| 180..183 | captured zero trailing bytes, not reinterpreted |

The original first store reads the blend coefficient **before** deciding that
B/C are null; omitting its allocation would be incorrect. Slab and blend use
independent owned allocations. The original pool's -512 relationship is not
required by an instruction and is not simulated with unknown padding.

Captured source-A sampling is `(offset + extent*((pixel+.5)/source_size)) *
reciprocal`. Rescaling both extent and reciprocal yields exactly
`((x+.5)/16,(y+.5)/16)` here. Source A is a 16x16, four-channel HALF CUDA array,
every channel exactly 0.5 (`0x3800`), with normalized coordinates, POINT/nearest
filtering, CLAMP on all axes, no integer-read or sRGB flags. B/C stay null.

Output is a separate 16x16 RGBA16F CUDA array with
`CUDA_ARRAY3D_SURFACE_LDST`, accessed through a surface object, not an ordinary
GPU pointer or raw CUarray cast. `SUST.P` uses **pixel X**, not byte X, and
formatted FP32-to-HALF conversion. The proposed host passes the complete opaque
64-bit handle, without truncation/descriptor manipulation. That does not by
itself establish its compatibility with the original uniform operand.

## Fixtures and bounds

Read sets come from `nr-ptx-prefix-20260911/layout_reference.py`, independently
checked against original-PTX prefix execution. For lane l, site s:

* Main: dy=s%2, plane=s//2, row=l//16+2dy, col=(l//4)%4.
  Byte offset = `16*((row+8*plane)*8+col)+4*(l%4)`, length 4.
  Maximum end **1472**; **512** distinct bytes loaded.
* Skip: (dy,dx)=divmod(s,2), byte offset =
  `512*(4*dy+dx)+16*l`, length 16.
  Maximum end **3072**; **2048** distinct bytes loaded.
* Main/skip allocations are these minimal extents, with every byte initialized,
  including holes. Deterministic pattern uses only finite E4M3 values
  0 and ±1/32, ±1/16, ±1/8, ±1/4. These are not captured activations.
* Slab: original raw weight-file offset **147406312**, length **21808**,
  SHA-256 `197024afb1f78602dc08cfd5ae87c413385237c5f537dd5dcfeae742be85eca8`.
  Original encoded bytes are copied exactly, not unpacked/repacked as dense FP16.
* Blend: raw weight-file offset **147406234**, length 2. Both spans verified
  against the pinned whole-file upload contract.
* Source/output each occupy 2048 host fixture bytes. Output starts entirely
  at FP16 qNaN poison `0x7e55`. Two store maps cover 64 unique pixels in the 8x8
  tile; all **192 pixels outside it must remain byte-exact poison**. Every tile
  component must be finite, alpha exactly 1. Untouched tile poison is failure.

The CPU interpreter verifies complete prefix/prehead loads fit these extents.
It is not a full SASS address emulator. Original SASS has scalar 32-bit main
loads and 128-bit skip loads; all 3,336 disassembled instruction encodings were
matched to ELF bytes. Any remaining original descriptor/handle-binding evidence
must be reviewed before activation, not inferred from CPU arithmetic tests.

## Proposed lifecycle (compiled, not exercised)

CLI syntax is strict: `--execute --device N --run NAME`. Missing/malformed gate
returns 64. **Even valid syntax returns 78 before libcuda is opened**, because
the source-level ABI gate is false. There is no runtime override.

If independently unblocked by a later review, the host would:

1. Verify all file hashes and original ELF; create a new non-overwriting
   `run-NAME` directory here; resolve CUDA Driver symbols without a CUDA link.
2. Require exact device SM120, create its own context via current installed
   `cuCtxCreate_v4`, and load only the original ELF. Missing API, unsupported
   ELF or object behavior fails: no fallback/patch/PTX compilation.
3. Create/upload own main, skip, slab, blend, source/output arrays and objects.
4. Pack one 184-byte launch buffer using `CU_LAUNCH_PARAM_BUFFER_POINTER/SIZE`,
   launch the exact symbol once, then **`cuCtxSynchronize`**.
5. Only after successful sync, read own output and all own inputs. Save raw
   output/argument bytes, check input immutability and poison/coverage.
6. Drain again before cleanup. Destroy surface/texture views before arrays,
   unload module, destroy arrays, free allocations in reverse order, destroy
   context. On failed drain, do not read back or individually free possibly
   in-flight resources; attempt terminal owned-context destruction and fail.
   Failed view destruction retains its array until context teardown. All API
   CUresults and the first CUDA error remain in `cuda-status.tsv`; cleanup
   errors cannot be overwritten by an earlier success. Host failure is 70
   (full CUDA numeric statuses stay in file), output-write failure 74.

Module-loading, launching, readback and cleanup behavior have **not** been
runtime-tested. Guardian, benchmark lock, no-games check, device selection,
run authorization and run review remain the main agent's responsibilities.
They are not supplied or bypassed by this worker.

## Reproduce CPU-only verification

From project root:

```sh
bash reviews/nr-original-finalpost-probe-20260911/verify_cpu.sh
```

Uses only cuobjdump/readelf CPU inspection, Python CPU fixtures/tests and a
host-only g++ compile (`-std=c++20 -Wall -Wextra -Wpedantic -Werror`, installed
CUDA 13.3 headers). No nvcc/device compilation, no executable invocation,
no libcuda/libcudart link, and no Windows/DLL architecture harness. Evidence
records eight passing tests and a successful native Linux host build.

`compare_cpu.py` is an optional **later CPU-only** reader for an actual owned
successful run. Run `RN_f32_reference` and `measured_SM120_half_input` separately;
the existing latter reference hash-checks recorded RCP/RSQRT LUTs and rejects
inputs outside their measured domain. It preserves learned half values,
pre-surface FP32 and a separately labelled diagnostic RN-half conversion.
It reports errors, not a numeric-parity pass. Native MMA accumulation, PTX/SASS
contraction and surface rounding differences are not suppressed. The comparator
was syntax-checked only; there is no GPU result to compare in this deliverable.

## Main files

* `host.cpp`, `fixture_pins.hpp`, `build/original-finalpost-host`: blocked proposal.
* `prepare.py`, `test_cpu.py`, `verify_cpu.sh`: reproducible CPU verification.
* `fixtures/*`, `MANIFEST.json`: exact fixture bytes, read sets and provenance.
* `compare_cpu.py`: separate optional CPU-reference comparison.
* `SURFACE_ABI.md`, `evidence/*`: boundary, local/official source and build checks.
* `FILES_CHANGED.txt`, `SHA256SUMS`: exact new-file inventory and hashes.

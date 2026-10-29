# Static-first reconstruction, continuation: native confirmation and original PTX

2026-09-11. **Substantial continuation, not a complete model forward.** No game was launched or deployed. Static research stayed in isolated reviews; Main alone ran seven bounded, serial, private-prefix GPU fixtures using the already validated native Vulkan NR route through owned D3D12/vkd3d interop. No game settings, installed DLLs, signed on-disk files or old reconstruction sources were changed.

## 1. More of the real dataflow is now known

### Input routing

`../nr-static-routing-20260911/REPORT.md` proves descriptor copies and the actual network→block→layer gather. The first finalpost inputs are `[output69[0], output0[1], external[0], N+298, N+2a0]`.

- A: view of selected `DLSSNR.Color`/`DLSSNR.Backbuffer`, not automatically a pristine original snapshot.
- B: named resource `dlssnr_prev_output`.
- C: named input `DLSSNR.MVec`.
- Descriptor +98 is an **external-input selector**, not a block-output edge. Layer +a8 performs the ordered gather.
- History validity, reset and a global gate control whether B/C are supplied. Their resource contents/update recurrence are not thereby recovered.

### Byte-copy upload and placement

`../nr-static-upload-20260911/REPORT.md` proves raw CPU payload copy, lexical string-map order, per-payload `align_up(size,512)`, and pointer-preserving map binding on the inspected CUDA path. All 153 archived HtoD request destinations/lengths corroborate it; that old trace later faults, so request logging is not successful-transfer evidence.

Pool size 147,719,680 bytes; actual payload 147,683,778; padding 35,902 bytes **unknown, not zero-filled by the reference**. Block70 scalar offset 147429376, slab offset 147429888, slab length21808. No repack/conversion occurs on that traced upload path; kernels consume already-packed data. Current device payload contents were not read.

`ALIGNMENT_HYPOTHESIS.json` deliberately preserves Main's initial size-only hypothesis. It has since gained the stronger instruction/copy-sequence support above; it was not silently rewritten as an earlier proof.

### Tile and operand maps

`../nr-static-tile-20260911/REPORT.md` recovers four enc0-skip load addresses, boundary/broadcast behavior, exact 2048 skip-byte/main-byte pairings (4:1, **not an invertible tensor reshape**), and both stores' 8×8 coordinate maps. Upstream producer layout and full tensor semantics remain separate.

## 2. Minimal actual-native check — observer does not change pixels in this fixture

The approved runtime's real NR backend resolves `NVSDK_NGX_VULKAN_*`; D3D12 supplies resources/interop. It is **not an NVAPI_D3D12 inference path**. This justified wrapping only the GIPA/GDPA pointers handed to signed NR Init in an owned runtime clone. Existing filename-identity IAT compatibility remains exactly as in the approved runtime; no new signed-module code patch was added.

Worker observer review: `../nr-finalpost-observer-20260911/REVIEW.md`. Main selectively integrated it into the **normal-reserve fixed PRE3 source**, not the worker's older zero-reserve base. The experiment itself is POST1 at768×432, two frames, fixed prior WuWa still, zero MV/constant depth. It is neither current-game PRE3 nor a full guide/history replay.

Main added:
- exact module-byte hash + exact kernel-name/ABI allowlists before parameter reads;
- a single bounded CPU copy of one already observed exact module container;
- static-proved Vulkan extras parsing, no guessed pointer chasing;
- hash-pinned isolated harness and `run_probe.py`, benchmark lock, no-games checks, Guardian/global31000MiB protection and normal reserve;
- six CPU proxy scenarios plus ASan/UBSan, including wrong-module no-read and extras tag/size rejection.

### Runs and preserved intermediate failures

All seven GPU runs exit0, Guardian0, signed staged files unchanged, owned submissions fenced. They intentionally use the prior **fast exit only after fences/files complete**; normal DLL teardown is still NOT validated.

| Run | Purpose/result |
|---|---|
| `121525-frozen` | Exact normal-reserve runtime9e0154 baseline |
| `121626-observer_off` | v1 observer disabled; all5 pixel files byte-identical to frozen |
| `121737-observer_on` | v1 observed actual module/launch; correctly refused unknown outer hash and extras ABI; no aggregate read |
| `122411-observer_off` | v2 disabled |
| `122501-observer_on` | v2 captures exact module CPU bytes; parameters still deliberately refused; all5 pixel files match frozen/off |
| `123233-observer_off` | final v3 disabled |
| `123323-observer_on` | final v3 captures two complete184-byte aggregates, no skips/drops; all5 pixel files match frozen/off |

Each directory is under `runs/20260911-...`. The five equal files comprise two input readbacks, two changed NR output readbacks, and the final output file. Both NR outputs differ from their original inputs; this was not an identity-only test. `verify_live_contract.py` rechecks hashes, recorded fences, trace completeness and exact metadata without invoking GPU APIs.

Final observer runtime SHA256: **bf97610fb7bbc12a6b7046668260c27bf2886205bae911c6686ee33faa5aad72**. `LAB_APPROVAL.json` pins94 files. Earlier observer/source/harness approvals are preserved under `backups/observer-v1` and `observer-v2`; each run also retains its own staged binaries. Frozen baseline remains `9e0154fac9d821f9d51a18e7fe163114e12b9f0924e93e7bb724aeb3bf80caaa`.

Private run parents are0700. Wine mapped the owner DACL to0660 files despite host umask; Main verified no execute bits and normalized only new trace/module artifacts to0600. No claim is made that Wine enforced a native0600 mapping on creation.

### Real Vulkan arguments

`../nr-vulkan-launch-abi-20260911/REPORT.md` proves host routine `0x18004f2f0` constructs:

```
paramCount=0; pParams=NULL; extraCount=1;
pExtras -> [1, aggregate_pointer, 2, pointer_to_size_t_bytes, 0]
```

**pExtras[0] is tag1, not a readable pointer.** The observer reads the proven five-word structure, validates all tags and declared184/312 size, then copies only that bounded CPU argument buffer. Embedded GPU addresses are never dereferenced.

Final captured base-FP8 calls have grid97×57, block32, 184 bytes. Both show multiplier1/32 and decode flag1. Internal extents are448×768 with origin(-4,-4); source extents are768×432. We do not conflate padded/internal height448 with output height432.

The slab/scalar pointers differ by512 and independently imply the same pool base using the recovered static offsets. First call's B/C handles are null, second call's B/C are nonnull; A stays the same. This corroborates pointer placement and the static history-pair gates, **not GPU scalar contents, history pixel values, recurrence or full intermediate activations**.

## 3. The apparent module mismatch revealed original PTX

Initial actual module: **c11e2eb6f6eeabadffe340dba74ec8c3f474f4ac4a8ed601d59e04d1d49bda3d**, 3,944,768 bytes. `readelf` correctly rejected it as non-ELF. It is a CUDA **fatbinary**, containing compressed PTX plus CUBIN, not an unexplained alternative model:

- Entire actual uploaded container equals the exact DLL slice at file offset913632.
- Embedded ELF begins at container offset1155392.
- That inner ELF is **byte-identical** to prior static carve `feb368ff5279a7408b1e55554db6e468d7f114a24b18b2af8d7e6989a410c612`.
- `cuobjdump -ptx` recovered the original PTX9.4 / sm120 intermediate program. The selected finalpost entry is16,266 lines,265,352 bytes, one184-byte parameter.

`FATBIN_PROVENANCE.json`, `MODULE_CAPTURE_RESULT.json`, `LIVE_CONTRACT_VERIFICATION.json` retain this chain. Driver-internal selection between ELF and PTX remains unknown; uploading a container does not attest individual machine instructions.

Follow-on **CPU-only** extraction in `../nr-ptx-bundle-20260911/` recovers all15 original fatbinaries and231 PTX entries, 37.13MB exact PTX. These are compiled variants/entries, **not231 neural layers**. Exact containers and decompressed text, including terminal NULs, are preserved with no normalization; metadata maps them to the original ELF inventory. This is GPU intermediate code, not original PyTorch/training source.

## 4. A real learned computation is reconstructed, not only routing scaffolds

`../nr-ptx-finalpost-20260911/REPORT.md` recovers the actual final **32-feature → 4-component** learned head:

- 128 live learned FP16 coefficients, exact byte offsets from block70 tail `[20784,21808)`; not the old guessed leading3×16 matrix.
- Two K16 stages with visible half-accumulator boundaries, zero initial accumulator, no separate bias in this head.
- Exact packed feature/weight fragment maps and output selectors for both stores.
- First three outputs feed RGB decode; fourth is a learned sigmoid logit for the temporal blend, not surface alpha.
- `head_reference.py` computes an exact unrounded integer dot and an explicitly chosen staged RN-half reference. Native Tensor Core accumulation order/subnormal/rounding parity is still unproved and must not be assumed from mathematical dot-product equality.

Main's **`connected_output_reference.py`** now connects that real learned head to the previously recovered color decode for an interior tile on the observed first-launch/no-history-pair branch. It starts from packed pre-head registers and supplied texture samples, **not an input image**. It requires an explicit reference-rounding policy, rejects the observed second-launch temporal path rather than silently omitting it, and does not dereference GPU pointers. Six tests include actual-weight basis projection through RGB decode and both output-store coordinate maps. This is a usable small reconstructed segment, **not the full finalpost kernel or neural model**.

## 5. Verification and next boundary

Main independently reran the new static suites: routing15, upload12, tile13, Vulkan ABI5, learned head13, PTX bundle37, connected segment6 (**101 CPU/static tests**, separate from the six proxy scenarios and sanitizer runs). Worker extraction/head hashes were independently checked. GPU evidence is restricted to the seven fixtures and their recorded fences/pixels, not inferred from these tests.

A CPU-only attempt to reassemble the original finalpost PTX is retained in `ptxas-reassembly.log`: installed CUDA13.3 ptxas supports PTX9.3 and rejects original **9.4**. No header downgrade or patched replacement was attempted. This blocks a same-version local reassembly check, not static analysis or the existing original-DLL oracle.

Next work is the **upstream FP8 feature/MMA/normalization pipeline feeding this head**, using original PTX and the recovered packed maps. Full numerical parity also needs actual corresponding intermediate values and explicit native rounding checks. A compatible isolated PTX9.4 toolchain would enable safer kernel instrumentation experiments; it must not silently replace global drivers/tools or modify installed signed files.

**Still false:** complete logically/numerically equivalent model; raw GPU middle-activation capture; proof that the model learned '3D=black'; gameplay visual/performance acceptance. No parameter tuning was performed in this continuation.

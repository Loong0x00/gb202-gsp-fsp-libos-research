# Runtime packed-weight upload/map provenance — CPU/static only

## Result

**Recovered a byte-copy upload path, 512-byte per-payload pool placement, and pointer-preserving full-name → block → layer map routing.** On the inspected CUDA backend, no F16→FP8 conversion or in-place weight permutation occurs between the deserialized CPU payload and the `cuMemcpyHtoDAsync` request. The already-packed bytes are copied, not reconstructed as dense tensors.

The formerly unexplained **147,719,680-byte allocation is exactly the pool size calculated by native instructions**, not just a proposed alignment coincidence:

```
for key in lexicographic_string_map_order:
    offset[key] = total
    total += (payload_size[key] + 511) & ~511
```

All **153 archived HtoD call destinations and lengths** in `nvcuda-eval.trace` independently match this calculation, including the scalar and block70 slab. This is stronger than matching a lone allocation size. It remains archived API-request evidence, not a successful upload/launch capture or attestation of that trace's module bytes.

Physical DLL opened read-only:
`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll`

SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`, 165,840,496 bytes. Read prerequisite binding/layout/main reports and the small existing `ghidra-weight-bind.log`. No Ghidra project opened, GPU API invoked, Wine/PE/game execution, patch, model evaluation, or original artifact modification. No input resource/tile-layout research duplicated.

## Address convention

All native code addresses here are preferred-image **VAs**; image base `0x180000000`. `.text` file offset = VA − image base − `0xc00`. `UPLOAD_PROOF.json` records exact bytes and file offsets for 41 selected instruction sites. Bounded `host-*.txt` dumps retain the surrounding control flow. `.pdata` sometimes splits a function: explicit joined ranges were used where needed.

## 1. Embedded serialized bytes → owning CPU payload map

- `0x1800239a0` looks up the named embedded-weight descriptor. Descriptor table starts at `0x1800b0d80`, stride `0x288`; its first entry `+0x10` contains pointer `0x1800b1068`, the literal **WEIGHTS_HT**.
- `0x180023ac0` obtains its own module and uses real PE IAT imports: `GetModuleHandleExA` at IAT `0x1800ac118`, `FindResourceA` at `...ac168` with type **10/RCDATA**, `LoadResource` at `...ac150`, `LockResource` at `...ac158`, `SizeofResource` at `...ac160`. Resource pointer/size are returned at `0x180023b4c/3b57`.
- `LoadWeights`, `0x180022a80`, obtains those bytes at `0x180022afa`, allocates a CPU vector, and calls byte-copy **`0x18007e550`** at `0x180022b98` with `(destination, resource_pointer, resource_size)`. It passes that vector to map parser **`0x180044ee0`** at `0x180022bae`.
- The parser walks the existing serialized format: outer total, name length/name, inner record length/record. Each record is copied to a temporary CPU byte vector (`0x180044ff5`), then parsed by **`0x180044cf0`**.
- `0x180044d4c..d50` reads record `+8` as payload byte length and saves it to tensor-value **`+8`**. Record `+0x10` is the storage/location discriminator; value 2 is rejected by this CPU deserializer (`0x180044d6e..d71`). For the pinned kind-1 records, `0x180044d90` allocates that exact payload length, `0x180044d9c` stores the resulting CPU pointer at value **`+0`**, and `0x180044da0..da7` copies **record+0x14, length bytes** into it.
- The two trailing 32-bit fields and shape vector are parsed only **after** the raw payload copy. They do not drive a payload conversion. `0x18004505f/5067` stores CPU pointer/length into map node **`+0x40/+0x48`**; the string key is at node **`+0x20`**.

Thus there are ordinary owning CPU copies, not a view directly into the locked resource. The prior byte-provenance report already proves WEIGHTS_HT/manifest/safetensors equality; this pass does not reinterpret their F16-designated raw storage.

### Byte-copy implementation check

`0x18007e550..7ebc4` is a memmove-style byte-copy implementation with small-size jump tables, forward/backward SSE/AVX moves, and a CPU-feature-selected `REP MOVSB` path at `0x18007e530..53f`. There is no floating-point arithmetic/conversion in these copy branches. For **size 2**, jump-table entry at VA `0x181164008` selects `0x18007e5b8`: `MOVZX ECX,word [RDX]; MOV word [RAX],CX; RET` (bytes `0fb70a668908c3`). The 21,808-byte case uses the bulk byte-move paths; it does not convert each 16-bit slot to a floating-point value.

## 2. CPU map → pool allocation → CUDA HtoD request

Manager **`0x18001f570..20627`** loads the CPU map at `0x18001f795`. It traverses the map in string-key order, not numerical block order (`block10` precedes `block2`).

### Exact allocator arithmetic

For each node with nonzero pointer and byte count:

- `0x18001f8b7`: save current running offset in the parallel offsets vector.
- **`0x18001f8ec`**: load byte count `[node+0x48]`.
- **`0x18001f8f0`**: add `0x1ff`.
- **`0x18001f8f6`**: AND with `0xfffffffffffffe00`.
- **`0x18001f8fc`**: add aligned length to running total.
- Invalid/empty entries take a distinct zero-offset/no-increment branch. The pinned 153 entries are all nonempty; the CPU helper deliberately supports only that proven domain.

The manager checks `1 <= total <= 0xffffffff` at `0x18001fa0c..18`. It puts total into the first dword of a buffer descriptor (`0x18001fa1e`). Backend **vtable+0x70** creates the target at manager `+0x58` (`0x18001faa8`) and an upload resource at manager `+0x60` (`0x18001fbf5`, name **CG2RWeightUpload**). Target descriptor kind at `+0x18` is 1; upload descriptor kind is 2.

CUDA backend vtable **`0x1800bc9e8`**, installed by constructor `0x1800766ad`, resolves:

| Slot | Target | Role in this chain |
|---|---|---|
| `+70` | `0x180046860` | Common create-buffer wrapper |
| `+88` | `0x180046730` | Common CopyHostToDeviceBuffer wrapper |
| `+b8` | `0x180078830` | Extract target device pointer |
| `+250` | `0x1800773d0` | CUDA allocate buffer on cache miss |
| `+268` | `0x180076f70` | CUDA HtoD implementation |
| `+278` | `0x1800482f0` | Common cached-resource lookup before allocation |

`0x180046860` first tries cached reuse (`0x1800468f7`); only a `-7` miss calls `+250` at `0x180046a3c`. Descriptor construction `0x180045b80` copies its first 0x24 bytes unchanged. In CUDA `0x1800773d0`, kind-1 target allocation reads descriptor dword0 as the size (`0x180077498`) and calls object **`+0x478`** (`0x1800774e3..4f2`). Kind-2 upload allocation instead requests **1 byte** (`0x180077428..436`): CUDA does not need a full host-visible upload staging pool here. This explains the archived adjacent allocation requests **147719680, 1** without inventing a second large staging allocation.

Dynamic CUDA table setup is concretely tied to imports by name: `0x180078ede..ee5` loads table at backend **+0x408**; loader `0x1800793d0` resolves **cuMemAlloc** to table **+0x70** (`0x1800797ca..de`) and **cuMemcpyHtoDAsync** to table **+0x98** (`0x1800798e5..fc`), requesting API version `0x2f30` (12080). Therefore backend `+0x478 = +0x408+0x70`, and `+0x4a0 = +0x408+0x98`.

CUDA allocation saves the returned device pointer in resource descriptor **+8** (`0x180077531..539`), and `0x180078fd0` copies that descriptor into the resource object. `GetBufferDevicePointer` (`0x180078830`) resolves a mapped resource if needed, then returns resource **+8** (`0x18007889d..8a1`). The manager saves this base in local `[rsp+0xa0]` through the `+b8` call at `0x18001fd22`.

### Exact HtoD arguments, no repack step

At `0x18001fe60..fec9`, for each CPU entry:

```
R9 = node+0x40 first qword = CPU payload pointer
R8 = node+0x48            = unaligned payload byte count
arg5 = upload resource
arg6 = target resource
arg7 = offset[i]
arg8 = offset[i]
```

The common wrapper `0x180046730` validates resources and dispatches backend `+268`. CUDA implementation `0x180076f70` resolves **arg6** to its resource object, then:

```
0x180076fc2: RCX = resource.device_pointer (+8)
0x180076fc6: RDX = original R9 = CPU payload pointer
0x180076fc9: RCX += arg8 = offset[i]
R8 remains the exact payload byte count
0x180076fd1: R9 = backend.stream (+0x3f8)
0x180076fd8..df: call backend+0x4a0 = cuMemcpyHtoDAsync
```

CUDA ignores the upload-resource storage and arg7 for the actual byte transfer. **Alignment affects destination placement only; the copy length is NOT rounded up.** Padding bytes therefore have no proven values. A cache hit can change allocation origin/lifetime, not this copy's destination-offset/length arithmetic.

## 3. Uploaded map → block/layer local keys → selected binder

After each successful copy request:

- `0x18001fee3` copies tensor metadata to a temporary value.
- **`0x18001fee9..fefc`** replaces its first qword with **device_base + offset[i]**.
- **`0x1800200ba`** writes that pointer to the GPU-map node **+0x40**, under the unchanged full key. `0x18002013f` sets its value kind at node+0x70 to 2. Sizes/shape metadata are copied, not payloads.
- **`0x180020351..35a`** passes this GPU map to network virtual **+0x30**. This precedes CPU payload release at `0x180020377..37b`; hence subsequent binders retain GPU pointers, not those freed CPU allocations.
- Network constructed at `0x18003f8d2` installs vtable `0x1800b1960` (`0x180031c47..4e`). Its `+30` is **`0x18003d7a0`**. That method retains a metadata map at network `+0x260`, then tail-calls **`0x180028eb0`**.
- `0x180028eb0` constructs **`block` + decimal block index + `.`** (literal `block` at `0x1800b1748`; period store `0x1800290b8`). It accepts prefix matches at offset zero, strips only that prefix, and copies first-qword values unchanged to the block-local map (`0x180029399..39d`). It passes this to **`0x18002b8c0`** at `0x1800294cc`.
- `0x18002b8c0` analogously constructs **`layer` + decimal layer index + `.`** (literal at `0x1800b1950`), strips the prefix, copies first-qword values unchanged (`0x18002bda9..dad`), and calls the layer's virtual **+0x30** (`0x18002bed3..bee3`).

Consequently `block70.layer0.blend_scale` becomes local **blend_scale**, and `block70.layer0.layer` becomes local **layer**. No string-level lookup substitutes the serialized scalar for the host RGB multiplier.

For the selected finalpost layer instance, the prior independently verified vtable maps `+30` to **`0x180075ce0`**:

```
GPU map local key layer       → node+40 → state+0 → aggregate+18
GPU map local key blend_scale → node+40 → state+8 → aggregate+68
```

Binder stores `0x180075f8b/76040`; aggregate stores `0x180075a15/75aa0`. This pass proves the map routing algorithm; it does not add a runtime block70-instance/selected-kernel capture beyond the prior architecture/family correspondence. The 1/32 host literal at aggregate+30 remains separate.

## 4. Concrete byte ranges and archived cross-check

Computed from all 153 pinned payloads in lexicographic map order:

| Key | WEIGHTS_HT payload range (decimal) | Pool offset | Copied bytes | Reserved / trailing unknown padding |
|---|---|---|---|---|
| `block70.layer0.blend_scale` | `[147406234,147406236)` | **147429376 = 0x8c99800** | **2**, `eb39` | 512 / 510 |
| `block70.layer0.layer` | `[147406312,147428120)` | **147429888 = 0x8c99a00** | **21808 = 0x5530** | 22016 = 0x5600 / 208 |

Total payload = **147683778**; total reserved = **147719680 = 0x8ce0600**; padding = **35902**. The slab's proven end is `base + 0x8c9ef30`; its reserved next boundary is `base + 0x8c9f000`.

Archived `nvcuda-eval.trace`, opened read-only:

- line78: allocation request 147719680; line79: request 1.
- lines80–232: **153 HtoD API calls**, each destination and exact byte count matching the native pool calculation.
- inferred base from first copy = **1099683594240 = 0x1000a400000**.
- line229 scalar destination **1099831023616**, source `0x7f80bf6ff480`, length2.
- line230 slab destination **1099831024128**, source `0x7f80bf6e1110`, length21808.
- line233 records a context-synchronize call; the trace later faults. Neither call logging nor synchronization entry proves success/contents/launch.

`UPLOAD_PROOF.json` retains every correlated call, line number, source/destination, offset/length, and the historical trace hash. **The pool interpretation now has native-instruction and complete archived copy-sequence support; actual bytes in historical device memory remain uncaptured.**

## Strict CPU helper / verification

`upload_contract.py` models only those uploaded spans; it never executes DLL code, allocates GPU memory, or imports torch. It exposes precise source bytes by pool-relative offset and a block/layer pointer map for a caller-supplied base. Reads into padding/cross-span/invalid bounds fail; padding is not silently zero-filled. Raw NaN-like half bit patterns are preserved. This is **not** a dense-weight unpacker, lane/channel layout model, or whole-network forward.

```
cd /home/user/rt_5090_project/nr_runtime_next/reviews/nr-static-upload-20260911
python -B collect_evidence.py
python -B test_upload.py
```

**12 tests pass**: 41 native instruction anchors/source hash, vtables, exact allocation total, all archived copy offsets/lengths, scalar/slab equality, all payload spans, unknown-padding rejection, lexical rather than numeric ordering, strict bounds/overflow/malformed records, and scalar-size copy jump table. GNU objdump independently checked the CUDA copy argument slice (`objdump-copy-check.txt`). Initial collector caught two instruction-byte transcription typos; corrected against the existing disassembly before final passing tests.

## Limits / stopping point

- Proven absence of payload repack/conversion is scoped to this **resource-deserialize → manager → CUDA HtoD → GPU-map/binder path**, not every function in the DLL, later device writes, or current-game D3D12 behavior.
- Kernel can interpret the unchanged slab as mixed packed FP8/FP16 data; its complete weight permutation is still unresolved. F16 container designation is not dense matrix semantics.
- No actual device contents, successful transfers, aggregate values, current backend selection, or model/kernel runtime hash attestation were captured. Cached-resource lifetime and driver asynchronous staging behavior are not emulated by the helper.
- All output is confined to this review directory. Existing source/game/serialized artifacts and prior reports remain unchanged.

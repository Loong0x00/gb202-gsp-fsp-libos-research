# Swin block1 → block2 arithmetic chain (CPU/static, SYNTHETIC)

## Result

**Executable composition achieved:** four complete original block1 plain `inpview_fp8` tiles, using the real block1 payload, produce checked output patches; one complete original **plain standard `cc_tinlayout_fused_swin_1h_32_1_fp8`** tile consumes those patches with the **real block2 payload**. No surrogate attention, borrowed query scale, missing activation placeholder, or output-zero backing is used.

The consumer executes the original module00 **4,902-instruction entry**, through final `ret`, including all **256 FP8 K32 MMAs**, both score normalizers, actual FFN residuals, learned projections and four b128 store sites. The producer executes its original 5,505-instruction entry four times. This is **plain-standard arithmetic only**, not attestation of native consumer selection, native wait/chained arithmetic, scheduling, visibility, or numerical parity.

**9 new tests and 14 read-only rerun producer tests pass.** The clearly synthetic H=W=16 fixture produces 8,192 block1 bytes and one complete 2,048-byte block2 8×8 tile. Block2 tile-order SHA256:

`b8f5488f5784b14adc1004cd4a74214a39750dbb2ef15f25b94cabd2488ddb97`

All writes are confined to this directory. No GPU, Wine, native PE execution, installed-file modification, PTX header downgrade, or sibling-worker edits.

## Reproduce

From the project directory:

```sh
python -B reviews/nr-swin1h-chain-reference-20260911/collect_evidence.py
python -B reviews/nr-swin1h-chain-reference-20260911/chain_reference.py --synthetic --reference-policies
python -B reviews/nr-swin1h-chain-reference-20260911/typed_evidence.py
python -B reviews/nr-swin1h-chain-reference-20260911/test_chain.py
```

Python API in `chain_reference.py`:

```python
result, tile_order_bytes, regs, memory = fixture(
    mma=prefix.mma_exact_rn,
    rsqrt=prefix.rsqrt_rn_policy,
    reciprocal=prehead.reciprocal_policy)

# Or caller-supplied sparse packed activations and an explicit slab:
regs, memory = run_standard(args96, patches, slab, input_size, output_size,
    cta=(1, 1), mma=mma_policy, rsqrt=rsqrt_policy, reciprocal=rcp_policy)
# patches: {byte_offset: byte_value}; absent bytes are NOT zero.
```

All three numerical policies are mandatory. CLI requires both explicit synthetic/reference-policy flags. `block2-tile-order.bin` concatenates the four actually stored 512-byte microtiles in source tile order; it is **not** an 8,192-byte backing buffer or a claimed NCHW tensor. `demo-output.json` preserves every actual sparse producer and consumer store/address, plus per-producer read ownership.

## Original source and real block2 bytes

`collect_evidence.py` freshly checks the exact signed DLL resource against the serialized container and all checkpoint payloads, then freshly decompresses module00 from its original DLL zstd frame and compares the full module. It uses read-only pinned sibling parsers, not their writing CLIs.

- DLL SHA256: `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`.
- Module00 SHA256: `9fa036fc715cb56c9138a1f931db1314fdd444ed30d1c31f66307a6babc7176a`.
- Exact entry byte interval **[4004627,4203648)**, **199,021 bytes**, SHA256 `15ddfc388ff77a4a1ce1bd4bbad79d44df220dda70f731a379eefa1694e0a8cd`.
- Original directives **`.version 9.4`, `.target sm_120`, `.address_size 64`** retained separately in `original-module-header.txt`. `standard-original.ptx` is an unchanged entry slice, not a downgraded or assembled module.

| Payload | Serialized byte offset | Bytes | Recomputed sorted/512-aligned upload offset | SHA256 |
|---|---:|---:|---:|---|
| block1.layer0.layer | 21834 | 20672 | 22016 | `0270fb8f406d3d0a916953ddaf6ec5d29328fe95b9d6cb408ca0c25c91108e3a` |
| block2.layer0.layer | 4508173 | 20672 | 4512256 | `379da9fb2027273f2dffa52a970a3950e97ca2d720fdf089fe4a1af409bf81c8` |

Offsets are recovered by parsing serialized named records; upload offsets are recomputed from the sorted records. They are not inferred from block order and do not attest a captured block2 binding. F16 container metadata is not interpreted as a dense weight matrix.

### Standard-entry load and scalar proof

`TYPED_LOAD_PROOF.json` records every original standard slab-load site's PC, registers and 32-lane offsets, and **all 256 actual MMA D/A/B/C tuples**. Direct slab B/C operands are checked against raw slab words at their actual traced addresses before each MMA; computed operands are explicitly distinguished. Covered slab ranges are:

`[0,8192), [8208,8272), [8288,19556), [19568,20656)`.

Unread/untyped ranges are exactly:

`[8192,8208), [8272,8288), [19556,19568), [20656,20672)`.

These sets come from the standard entry's real loads, not assumed padding or copied postblock constants. Learned B uses original E4M3 MMA typing; additive C uses original FP16 MMA typing. The byte layout happens to agree with block1's slab schema, but the **payload and scalar do not**.

Actual block2 scalar provenance:

- Original standard line **7041**, PC **2418**: `ld.global.b32 %r1973, [%rd54+19552]`.
- Line **8156**, PC **2788**: `cvt.rn.f16.f32 low, %r1973`; then replicate into `%r1976` and multiply original query halfwords.
- Actual block2 f32 bits **`0x4062fb35`**, value **3.5465824604034424**, RN-half **`0x4318`**.
- This is neither block1's 0.408796… scalar nor any finalpost scalar. No offset/queryscale substitution occurs in the interpreter.

## Independent packed layout and byte coverage

### Producer raw inpview input

Reuses the pinned producer's independently tested layout equations, then checks every load address **and loaded raw register bits** again on all four producer CTAs. For site `s=0..15`, `tile,local=divmod(s,4)`, `dy,dx=divmod(tile,2)`, lane `l`, effective tile origin `(X,Y)`:

```text
row = Y + 4*dy + 2*(local%2) + l//16
col = X + 4*dx + (l//4)%4
byte_offset = 4 * (4*((row + (local//2)*H)*W + col) + l%4)
```

Each load is a u32. This fixture has no invalid/singleton/override input coordinates. The general producer reference handles those separately; no conventional HWC/NCHW reshape is assumed here.

### Producer output → standard input → standard output

Independent standard layout domain: H,W in [8,4096], divisible by4; effective origins divisible by4 and bounded to [-4096,4096]. Singleton **4-pixel-tile broadcast** and signed-overflow geometries are deliberately outside the independent checker, not generalized from the producer's pixel-singleton rules.

Let effective `X=args.X+8*CTA.x`, `Y=args.Y+8*CTA.y`. For source tile order `(dy,dx)=(0,0),(0,1),(1,0),(1,1)`:

```text
row = Y/4 + dy; col = X/4 + dx
valid = 0 <= row < H/4 and 0 <= col < W/4
byte_offset(lane) = 512*(row*(W/4)+col) + 16*lane
```

- Producer output: one 16-byte store per lane, little-endian concatenation of eight b16 E4M3x2 registers. Original producer lists start **rs338, rs346, rs440, rs448**.
- Standard input: one `ld.weak.global.cg.v4.u32` per lane at **exactly that packed address**, into four low-first u32 slots. Standard register lists start **r4299, r4304, r4309, r4314**.
- Standard output: same packed address equation; original eight-b16 output lists start **rs346, rs354, rs448, rs456**.

`check_standard` independently checks every input address/loaded bit and every output byte/store address, rather than comparing only a hash. No input transpose, inferred logical channel index, or copy-to-inpview shortcut is introduced. This establishes **raw packed byte compatibility for this standard consumer**, not permission to feed standard output into arbitrary variants.

The explicit synthetic geometry is producer origin(0,0), CTAs `(0,0),(1,0),(0,1),(1,1)`; consumer origin(-4,-4), CTA(1,1), hence effective origin(4,4):

| Consumer microtile | Packed byte span | Producing block1 CTA |
|---|---|---|
| (0,0) | [2560,3072) | (0,0) |
| (0,1) | [3072,3584) | (1,0) |
| (1,0) | [4608,5120) | (0,1) |
| (1,1) | [5120,5632) | (1,1) |

Four producer outputs are disjoint and cover exactly [0,8192). Consumer reads exactly **512 produced bytes from each producer**, and stores exactly those four packed microtile spans in its separate output address space. All byte coverage is explicit. A second run with **only the 2,048 required bytes** supplied produces identical output; removing any contributing patch, or even byte2567 alone, raises `unproduced input byte`. Unwritten output extraction and overlapping stores also reject.

Original invalid-input branches explicitly generate padding-zero registers; these are tested separately and are **not** a missing-memory fallback. The principal chain fixture takes no padding branch.

## Interpreter reuse and numerical policies

No interpreter operation was invented or relaxed. `chain_reference.py` reuses the hash-pinned strict `nr-ptx-swin1h-20260911/static_replay.py` unchanged. Relative to the inpview source, the only additional opcode forms are **`bra.uni`** and **`ld.weak.global.cg.v4.u32`**, both already explicitly implemented there. New tests independently verify the skipped forward branch and exact 4×u32/little-endian load unpacking, then test all original standard raw-load sites over 48 geometries. Unsupported operations, missing registers, loops, partial-warp collectives and unproven approximation policies remain fail-closed.

Both complete standard score normalizers are separately proved bijectively register-renaming equivalent to the pinned independent prehead normalizers, including opcodes, immediates and register reuse: **598 and 584 instructions** (`NORMALIZER_PROOF.json`). Their outputs are independently cross-checked on the actual composed block2 scores. No prehead weight, projection, offset, or query scale is reused.

Policies remain conditional CPU mathematics:

1. **MMA:** explicit exact integer dot plus typed C, RN-even-half result at each original K32 MMA. All 256 block2 MMA calls are checked against the independent forward fragment-map oracle; 128 have nonzero C. The oracle deliberately shares the RN-half rounder, so this is operand/map validation, not independent native accumulation validation.
2. **RSQRT/RCP:** caller callbacks required for original `.approx.ftz.f32` operations. CLI uses RN-f32 reciprocal-square-root/reciprocal references, **not native approximate bits**. Unsupported zero, FTZ/nonfinite domains reject.
3. Literal PTX half arithmetic follows source-order rounding; native contraction/SASS internal precision remains unproved. All 384 executed half→FP8 conversions on the interior consumer fixture are checked against an independent nearest-finite/RN-even quantizer. NaNs/unsupported overflow reject; no sanitization.
4. One complete 32-lane tile at a time, pure CPU order. No native concurrency, stream dependency, in-place alias, launch capture, or full-network reconstruction is implied.

## Historical graph and unresolved synchronization

The read-only `nr-swin-sync-protocol-20260911` evidence supplies a real **conditional historical data edge**: with empty block+38 and block index>0, network forward uses N+110[index-1]; first implicit layer input takes V[0]. The separately recovered completion edge is block2+68=[1], layer2+138=[0], same `B+F[1][0][0]` producer outgoing/consumer incoming slot. The graph log names block1 inpview and block2 shifted standard families. These support the historical composition interpretation, **not a captured block2 dispatch**.

Native launcher shift provenance is available only as a formula:

- aggregate +32/+36 = `-4*max(layer-object+7c/+78,0)`;
- equivalently descriptor +74/+70 because the descriptor is copied to object+8;
- predecessor-origin pointer is the real block1 descriptor edge.

The historical dumper writes block headers, but **does not serialize layer descriptors or print those scalar shift fields**. No layer binary was found in the inspected dump. Consequently the actual block2 numeric shift cannot be recovered from these artifacts. Origin(-4,-4), H=W=16, arguments and CTAs remain **explicit synthetic assumptions**, not facts derived merely from the word "shifted".

**Wait/chained versus plain full common-body equality was not verified here.** Therefore this deliverable is labeled **plain-standard only**; it makes no selected-consumer arithmetic-equivalence claim. The native variant and actual consumer selection remain unattested. The stricter parser rejects the real wait/chained backedges; no loop is treated as a no-op and no barrier is silently stripped.

Carry the sync worker's unresolved side effects unchanged: conditional `cc_cb_clear` writes -1; producer publishes release-zero; actual consumer polls relaxed signed >=0 with sleep retries then a CTA barrier; chained may publish its own release. This CPU arithmetic chain neither executes those effects nor resolves reset execution, stale-zero exclusion, native scheduling/API ordering, or producer-data visibility. A relaxed read plus CTA barrier is not asserted to be a GPU acquire. Sequential CPU patch composition is not native publication evidence.

## Artifacts and verification

- `chain_reference.py`: executable sparse-memory chain, standard layout checker, mandatory policy API/CLI.
- `standard-original.ptx`, `original-module-header.txt`: original unmodified source/directives.
- `collect_evidence.py`, `SOURCE_PINS.json`, `PROVENANCE.json`, `collection.txt`: fresh exact source/resource/checkpoint/slab audit and historical pins.
- `NORMALIZER_PROOF.json`: complete standard/prehead bijective register maps.
- `typed_evidence.py`, `TYPED_LOAD_PROOF.json`, `typed-run.txt`: standard load/operand/scalar provenance and complete read coverage.
- `test_chain.py`, `tests.txt`: 9 passing CPU tests, covering chain ownership/missing bytes, independent load/store layout, boundaries, all MMAs/conversions/normalizers, typed slab coverage, strict failures and newly encountered opcode forms.
- `producer-tests.txt`: 14 passing tests rerun from the pinned sibling without editing it.
- `demo-output.json`, `demo-run.txt`, `block2-tile-order.bin`: reproducible synthetic numeric fixture and exact sparse stores.
- `BOUNDARIES.json`: machine-readable completed scope and external gaps.
- `SHA256SUMS`, `verification.txt`: artifact hashes and final unchanged-source/checksum checks.

Remaining gaps are **external/native**, not a missing arithmetic or byte-layout stage in the declared synthetic chain: actual shift scalar descriptor bytes, actual block2 args/slab/variant selection, wait/chained common-body equality, native approximation/accumulation/contraction parity, synchronization/reset/visibility, and other geometries/graphs/full-model execution.

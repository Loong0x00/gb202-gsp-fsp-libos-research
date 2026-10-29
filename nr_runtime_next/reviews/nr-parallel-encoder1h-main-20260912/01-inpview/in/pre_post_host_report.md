# Task C — current-byte host port proof

## Result

**Conditional static port closure is established. The downsample branch reverses the tempting store-order interpretation.**

| Pre output-vector index | Pre aggregate pointer | Its dimension fields (H,W) | Graph port | Consumer under the supplied historical factory0 topology |
|---:|---:|---|---:|---|
| `O[0]` | **+248** | **+256,+260** | **0 / primary** | **block1 first primary input → Swin launcher ABI+0** |
| `O[1]` | **+216** | **+240,+244** | **1 / secondary** | **block70 second primary input → post launcher ABI+8 (skip)** |

Post70 **input0 → ABI0 is its main input from block69**, not block0 primary. This is not a claim about any currently running graph or live handle.

If the independent source proof establishes **+216 = high C32** and **+248 = low planar A**, this host proof attaches those layouts to **port1/post70 skip** and **port0/block1 inpview**, respectively. It does not independently establish their neuron-byte maps, numerical compatibility, or allocation extents. A 32-channel count and output metadata integers are not layout evidence.

## 1. Independent DLL and exact output stores

Read only this worker's copy:
`/home/user/rt_5090_project/nr_runtime_next/reviews/nr-parallel-pre0-main-20260912/03-host-ports/in/nvngx_dlssnr.dll`

SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`, 165,840,496 bytes. Addresses are preferred-image VAs, base `0x180000000`.

At launcher **0x180060cf0**, entry RSP=Q. Five pushes and `sub rsp,0x1a0` give RSP=Q−0x1c8; `lea rbp,[r11−0xc8]` gives RBP=Q−0xc8. Thus **A=RSP+0x70=RBP−0x90**. It is not the post launcher's RBP−0x80 base.

The third argument/output-vector object is retained in R15 (`60d1c`). `_ds` substring lookup at `60d52..60d61` controls the branch; when present, output count must be at least two (`60d67..60d72`).

| VA | Original bytes | Instruction | Consequence |
|---|---|---|---|
| `180060f4e` | `498b0f` | `mov rcx,[r15]` | RCX=O.begin |
| `180060f5b` | `488b4108` | `mov rax,[rcx+8]` | O[1] |
| `180060f5f` | `48894548` | `mov [rbp+0x48],rax` | **A+216=O[1]** |
| `180060f74` | `488b01` | `mov rax,[rcx]` | O[0] |
| `180060f77` | `48894568` | `mov [rbp+0x68],rax` | **A+248=O[0]** |

Absent `_ds`, the separate branch writes O[0] to +216 and zeroes +248/+256..263. It cannot be substituted for this ds kernel.

Constructor `5fbf0` installs vtable **0x1800b7d38**, independently read **+8=60cf0, +0x38=61510**. Initializer separately searches `_ds` and `_fp8`; both present select literal **`cc_tinlayout_fused_pre_block_swin_1h_32_1_ds_fp8`** at `0x1800b7e40`. Registration stores its return into state+8. Dispatch sends **264 bytes**, through a pointer-to-A slot, at `60fd1..61026`. Supplied PTX has this exact entry and one aligned-8 264-byte parameter. These identity checks are static; a live registered handle is not observed.

## 2. Dimensions — source overrides are not output dimensions

Let **h,w** be incoming launcher arguments 5,6: entry Q+0x28/Q+0x30, subsequently RBP+0xf0/+0xf8. Restrict the simplified formulas to nonnegative sizes without signed-addition overflow:

- **A+208/+212:** positive state+0x18/+0x1c overrides, otherwise h,w (`60db4..60dd9`, `60f4b/60f51`).
- **A+240/+244:** `ceil8(h), ceil8(w)` (`60ddc..60e0e`, `60f6e/60f71`). These use incoming h,w, **not** the positive overrides.
- **A+256/+260:** `ceil4(ceil(h/2)), ceil4(ceil(w/2))` (`60f7b..60fac`), only on ds.

Thus high dimensions equal twice low dimensions in this admitted domain. With caller **448×768** and source overrides **432×768**, the three pairs are **432×768**, **448×768**, **224×384**. This explains the old report's numbers without claiming a fresh argument capture. Calling with h=432 would not itself round to448 here.

The block caller loads per-layer dimensions from block+0x128 at `2b37a..2b390`. Their complete shape-inference provenance, and equality with post70's incoming dimensions, remain outside this bounded proof. **Do not divide high pixel H/W again by tile counts.**

## 3. Output table → ports → actual layer arguments

### No output-port permutation in this single-layer path

Network forward **3cc80** indexes block descriptor `D=*(N+0x78)+k*0xe0`. For non-final blocks, `3ce5d..3cead` copies the ordered inner vector **T[k] at `*(N+0x1f0)+24*k`** into the block output-vector argument. `3d30f..3d31b` passes that vector as R8.

Block forward **2ac60** copies the supplied output vector for its **last layer** at `2ad36..2ad77`; additional outputs can append, not precede this prefix. It passes this vector as layer R8 at `2b398`. Constructor **3fbf0** checks the single-layer descriptor has exactly one layer. Therefore block0 O[0:2] and graph T[0][0:2] have the same order.

Export-pair helper **3dfd0** interprets D+b0/D+c8 as ordered `(layer,output)` selections. When D+b0 is empty, it emits the last layer's outputs in increasing index; count is `(L.e0−L.d8)/12`, default1 only if that record vector is empty (`3e144..3e1c2`). The pre ds builder creates exactly **24 bytes = two 12-byte records** at `6034d..6036b`. No output-type enum interpretation or destructor inference is used.

### Exact descriptor gather

At **2afd4..2b046**, `L=*(block+0x28)+layer_index*0x170`; L+a8 is an **ordered gather of block-input qwords**. Each index is bounds-checked and the **selected handle**, not its index, is appended. Later input groups append. The launch call loads layer vtable+8 with **RDX=&I, R8=&O**, at **2b366..2b3a6**.

- Current pre builder **603b0**, `6056d..605c4`, explicitly sets **L+a8=[0,1,2,3]**.
- Current post builder **74d90**, `74f7e..74fc4`, sets **L+a8=[0,1]**. This proves its required main/skip prefix, not the full five-entry historical descriptor.
- Supplied old routing report separately records historical block70 **L+a8=[0,1,2,3,4]**. Runtime augmentation making that full historical gather is **not reconstructed** here.
- With both L+90 and L+a8 empty, **first layer I[0]=V[0]**, by `2af33..2af67`. This is block1's constructed default, not a fabricated `[0]` array inferred from an omitted dump field.

Actual descriptor-copy callers retain +a8 (`1eb1c..1eb2a`), block fields38/50/98/b0/c8 (`1e9b7..1ea2b`), and network's e0-stride block vector (`1ef0a..1eff7`). Block constructor passes copied layer descriptors to dispatcher `3fdc0`; type matches select pre `5fbf0`, Swin1H `61ee0`, and post `74b70`. Generic string/vector-copy/memmove callees are not exhaustively decoded; their call-site operands and sizes are retained.

### Network edge mechanics and historical composition

For explicit D+38 edges, `3d100..3d1a8` appends **T[block][selector]**, using D+50[j], default0 only when its vector is shorter. D+98 then selects **external input indices**, not block outputs. The post-specific branch appends N+298 then N+2a0; runtime extras follow.

Applying the **historical**, not fresh, block70 values:

```
D+38=[69,0], D+50=[0,1], D+98=[0]
V70 prefix = [T[69][0], T[0][1], external[0], N.298, N.2a0]
```

Post launcher **758a0**, bytes at **759fc/759ff** and **75a03/75a07**, independently proves **I[0]→ABI0; I[1]→ABI8**. Therefore historical graph0 **secondary→post70 skip** is separate from, and composes with, current-byte **O[1]→pre+216**.

For **block1**, D+38 empty and k>0 chooses **`(*(N+0x110))[k−1]`**, at `3d0c4..3d0da`. Critically, **3e798..3e7c4** fills N+110[k] from **T[k][0]**, or zero if empty. This closes the implicit edge **T[0][0]→V1[0]→I1[0]**, rather than merely repeating the historical “primary” label.

## 4. Block1 really is inpview — conditional exact kernel selection

Current factory code **39780** initializes its block vector empty, appends pre, then at **39d9b** calls Swin builder **629d0** with:

- EDX=32;
- R8B=0 (unshifted);
- caller stack+28=1, +30=0;
- R9D and stack+20 both −1.

Builder prologue establishes RBP=entryRSP−0x3b8; caller slots+28/+30 become RBP+3e8/+3f0. **62b30..62b72** therefore selects the **inpview unshifted prefix**, not standard, shifted, or outview. It initializes L+90/L+a8 empty. This corroborates the supplied historical name `cc_tinlayout_fused_swin_1h_inpview_32` with actual flags and branches.

Swin vtable **0x1800b8108** has **+8=637b0**, **+38=641c0**. Initializer invokes selector **623f0**; precedence is **upsample → _ds → _inpview → _outview → standard**, with `_fp8` handled separately. For inpview it returns:

- **`cc_tinlayout_fused_swin_1h_32_1_inpview`**, or
- **`cc_tinlayout_fused_swin_1h_32_1_inpview_fp8`**, only if the actual name contains `_fp8`.

Registration stores the handle at S+8. The classifier **62210** rejects inpview from the plain-family path (S+30=0). Init also registers **inpview_tilesync[_fp8]** at S+38. Forward **637b0** puts I[0] at ABI+0 (aggregate RSP+70, byte count96), normally uses S+8, but can use S+38 if the gated supplementary output handle and alternate handle are nonzero. Other initialized state/extra inputs could affect alternatives. **A present historical name or initializer lookup is not proof of the currently dispatched handle.** This review proves the inpview family and exact conditional candidates; it does not guess a live base/tilesync/FP8 selection.

## 5. Allocation, lifetime and alias boundary

There is a concrete pool chain, not merely anonymous pointers: setup **3e4e0** receives a base and available size, stores N+250/+258, forms pool base **incoming_base+N+208**, resolves an allocation-slot index through **N+1a8[block][layer][output]**, reads its offset at **N+178+16*slot**, and appends **pool_base+offset** to T[k] (`3e6e0..3e766`).

However, actual slot values, per-slot byte extents, overlap, ownership, reuse schedule and GPU publication/fences are not observed. Separate ports **do not imply separate allocations or non-aliasing**; tests deliberately admit aliased handles. CPU vector storage/copies are not device allocation extents. Host submission ordering is not completion or producer-consumer visibility. Historical sparse-store byte bounds are not native allocation ownership evidence.

## Verification and artifacts

`HOST_PORT_PROOF.json` includes exact original instruction bytes, decoded structured operands, VAs/file offsets, selected witnesses, all bounded raw windows, `.rdata`/`.pdata` slices, identity hashes, historical/current separation, scripts and exact input paths read.

**PASS:** 10 allowed-input identities; every retained binary slice rechecked against the independent DLL; 176 overlapping old post witnesses freshly byte-matched; symbolic routing/permutation/default-selector/alias/dimension tests; vtable and CFG-cell checks. CFG cell `0x1800ac428` targets `0x1800a7c30`, bytes **ff e0 / JMP RAX**.

Budget: **1×699,904-byte .text scan; 32 individually bounded windows, 23,145 bytes total, each ≤4,096 bytes**. Bounded clipped instruction tails are retained and explicitly excluded from witnesses; `.pdata` fragments are not treated as whole functions. All human-facing text projections were bounded below2,000 lines. No recursive discovery or other project input access.

No DLL/native/PE/Wine/GPU/CUDA/network execution, DLL loading, native/PTX compilation, patching or NN prediction occurred. Only local CPU hashing, decoding and symbolic checks. No old sibling main was run. All writes are under this task's `out/`.

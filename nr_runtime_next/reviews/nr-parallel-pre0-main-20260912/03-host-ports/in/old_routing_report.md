# Finalpost upstream routing — static proof, 2026-09-11

## Result

**Recovered two actual upstream routing stages, plus named resource-field provenance.** This is no longer a match between two five-element counts.

For the historical factory(0) block70 descriptor, the **first five** finalpost launcher inputs are:

```
I[0] = network_output_table[69][0]       # main
I[1] = network_output_table[0][1]        # enc0 skip
I[2] = external_inputs[0]               # texture A
I[3] = *(CCNetwork + 0x298)             # texture B
I[4] = *(CCNetwork + 0x2a0)             # texture C
```

The native block descriptor **+0x98 indexes the network's external-input vector**, not a block-output table or just an execution dependency. Thus the dumper label `completion_input_blocks=[0]` supplies A from **external input 0**. It does **not** mean block0 output0.

On the recovered successful frontend path:

- **B** is the view of feature-state **+0x60**, allocated with literal resource name **`dlssnr_prev_output`**.
- **C** is the view of request **+0x18**, populated from the literal parameter key **`DLSSNR.MVec`**. Its identity does not come from observing two-component sampling.
- **A** is the view of the frontend's selected color resource. The evaluated request's first resource descriptor is selected from **`DLSSNR.Color` or `DLSSNR.Backbuffer`**; it is **not proven to be pristine original RGB**. The separately named `dlssnr_original_color` snapshot is a different feature-state member, **+0x50**, and must not be equated with A.

These are **static construction/provenance results**, conditional on this graph and path. No current-game launch arguments, backend selection, resource contents, previous-frame recurrence, sampler enum meanings, or full numerical parity were captured.

## Source and scope

Physical DLL, read only:
`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/nvngx_dlssnr.dll`

SHA256 **`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`**, 165,840,496 bytes. All addresses below are preferred-image **VAs**, base `0x180000000`.

Read the binding/layout/output/main reports. Historical factory log/dumper and small existing Ghidra text were read only; no Ghidra project was opened or analyzed. Used Capstone to scan only the 699,904-byte PE `.text` for selected xrefs, then decode **25,184 selected host-code bytes**. Small named `.rdata`, RTTI, table and global-data reads supply anchors; whole-file reading is for hashing/mapping, not whole-DLL analysis. No GPU, Wine, native PE loading/execution, emulation, DLL patch, model execution, or historical-file modification.

## 1. Descriptor → block object → layer object

The offsets below have native copy/consumer evidence, rather than only dumper labels.

1. Network constructor **`0x180031c10`** calls base initializer `0x180027930`. At **`0x18002794f..7956`**, destination is **network+8**, and `0x18001eea0` copies the supplied network descriptor there. Its **`0x18001ef0a..eff7`** loop copies the descriptor's **+0x70 block vector**, stride **0xe0**, by calling `0x18001e8a0`. Therefore the runtime object's same vector starts at **network+0x78**.
2. **`0x180031db3..1dc4`** passes network+8 as descriptor to `0x18003c580`; **`0x18003c5ec`** calls build-blocks **`0x180036300`** with it. The selected build slice retains its descriptor argument, indexes its +0x70 vector (`0x1800365ce..6607`), and passes a block descriptor to single-layer-block constructor **`0x18003fbf0`** at **`0x180036989..698f`**. The result is inserted into network's runtime block-pointer vector **+0xf8** (`0x1800369a9..69c0`, with growth alternative following). This report does not attest which dimensions/variant a live instance selected.
3. Single-layer-block constructor calls `0x180029b50`; **`0x180029b6f..9b76`** copies its block descriptor to **block-object+8**. Copy helper **`0x18001e8a0`** copies each layer with stride **0x170** at **`0x18001e990..e9b3`**; block descriptor +0x20 thus becomes **block-object+0x28**. Its vector copies at **`0x18001e9b7..ea03`** preserve +0x38, +0x50, +0x98. Helper `0x18001e7f0..e88b` allocates and copies `(end-start)/8` qwords, not reinterpreted labels.
4. **`0x18003fcb0..fcb8`** passes these copied layer descriptors to dispatcher **`0x18003fdc0`**. Type comparison against literal `CCTinlayoutFusedPostBlockSwin1H` at **`0x18003ff99..ffbe`** selects constructor **`0x180074b70`** (`0x18003ffda`). Layer pointers are saved to block-object **+0xe8** (`0x18003fcbe..fceb`). Layer constructor also copies its descriptor to layer-object+8 through `0x18001ea60`; **`0x18001eb1c..eb2a`** explicitly copies descriptor **+0xa8** unchanged.
5. Single-layer-block vtable installed at **`0x18003fc2c..fc33`** is **`0x1800b23a8`**. Its first qword is **`0x18002ac60`**, the actual block-forward routine below. Finalpost vtable is **`0x1800bc530`**, whose +8 is launcher **`0x1800758a0`**, as independently proved in the binding review.

This connects the captured descriptor layout to actual constructors and consumers. It does not turn the historical factory capture into a current runtime capture.

## 2. Network forward constructs the block-input vector

Actual routine **`0x18003cc80`**, independently anchored by the `CCNetwork::forward_range` error strings and network vtable **`0x1800b1960+0x10`**.

At entry:

- R15 = network object **N** (`0x18003ccbb`).
- R13 = first block index; third argument is exclusive end index.
- The **fourth argument R9** is external-input vector **E**, saved at **RBP-0x71** (`0x18003ccad`). It is **not** the launcher's own second argument.
- Each block descriptor **D = *(N+0x78) + block_index*0xe0** (`0x18003cd90..cd97`).
- Local block-input vector **V = RSP+0x50**, initially empty (`0x18003ceb0..cec2`).

The table's **output role** is also consumed natively: for a non-final block, **`0x18003ce5d..cead`** copies its N+0x1f0 inner vector into the local output vector at RBP-0x69; `0x18003d30f` passes that vector as block-forward R8. The block's last layer copies those supplied outputs at **`0x18002ad36..ad77`**, then passes them as layer-launch R8 at `0x18002b398`. Blocks 0 and 69 are non-final in the captured 71-block graph. Thus “output table” is not a label inferred from counts; allocation/content generation still remains outside this proof.

### Ordered append proof

| Stage | Concrete native dataflow | VA evidence |
|---|---|---|
| Block-output edges | Iterate qwords of **D+38**. For edge j, select block k. Select output q from **D+50[j]**, or **0 if that selector vector is shorter**. Index 24-byte inner vector at **`*(N+1f0) + k*24`** and append its qth qword. Both block and output indices are bounds-checked. | **`0x18003d100..d1a8`**, especially `d133`, `d139`, `d140..d160`, `d16b..d17a` |
| External inputs | Iterate **D+98**. For each qword e, load the saved fourth argument E, bounds-check e against `(E.end-E.begin)/8`, append **E[e]**. | **`0x18003d015..d071`**, loop tail `d1b3..d1cc` |
| Post-specific pair | Inspect first layer's **type string +20**; exact 31-byte match to `CCTinlayoutFusedPostBlockSwin1H`. Append **`*(N+298)`**, then **`*(N+2a0)`**. | **`0x18003d1d2..d282`**; loads `d20f`, `d24a` |
| Additional runtime inputs | Append entries from per-block vector in **N+1d8**, if present. This happens **after** the preceding items. | **`0x18003d282..d301`** |
| Dispatch | Receiver **`(*(N+f8))[block_index]`**, RDX=&V, R8=&local output vector, virtual **slot 0**. | **`0x18003d301..d31b`** |

Growth-path helpers `0x180027370` and `0x18001e110` dereference the supplied R8 qword and insert it at the supplied end position; their loads/stores at `0x1800273ff..7403` and `0x18001e19f..e1a3` agree with the inline append paths. They do not append descriptor indices as handles.

Applying the **actual values** in `graph-factory.log` block70:

```
D+38 = [69,0]; D+50 = [0,1]; D+98 = [0]
V starts [ output[69][0], output[0][1], E[0], N.298, N.2a0 ]
```

The branch for a block with no D+38 edges is different and is not silently substituted here. In particular, no conclusions about every old JSON `input_layers` record are needed for this proof.

## 3. Block forward constructs the launcher's actual vector

Routine **`0x18002ac60`** receives the preceding V in RDX, saves it in **R12** and at RBP-0x78 (`0x18002ac91..ac94`). For each layer:

- **L = *(block+0x28) + layer_index*0x170**, at **`0x18002ad05..ad0c`**.
- Actual layer input vector **I = RSP+0x40**, zero-initialized at **`0x18002af21..af2a`**.
- **`0x18002afd4..b046`** walks **L+0xa8** in qwords. Each value is loaded into RSI (`aff0`), checked against V's qword count (`aff3..b006`), then used as a **subscript into V** (`b00c`). **The selected handle value** is appended (`b017..b026`), with the same growth helper alternative (`b035`).
- Other descriptor fields can append later; their existence does not alter this prefix. Thus this report proves the requested first five bindings without inventing zeroes for omitted historical vectors or claiming total arity from a count.
- **`0x18002b366..b3a6`** loads the layer pointer from block+0xe8; **RDX=&I** at `b39d`, R8=&outputs at `b398`; loads **vtable+8** at `b3a2` and calls at `b3a6`.

The historical layer **+0xa8 = [0,1,2,3,4]** is therefore an **ordered gather from the block-input vector**, not a list of operator indices and not an independently inferred set of texture labels. Composing this gather with section 2 gives the five bindings in the Result. Altering the indices with the same count changes routing, as covered by CPU tests.

All these virtual calls use the indirect-call cell **`0x1800ac428`**. Its on-disk pointer is **`0x1800a7c30`**, whose two instruction bytes `ff e0` are **JMP RAX**. Thus the preceding vtable-loaded RAX is the call target; the apparent absence of direct calls to `0x1800758a0` is not a dead-end xref result.

## 4. Frontend → network state / named resources

Recovered caller **`0x180021bb0`** is directly called at **`0x180019811`** in the selected feature-evaluation routine **`0x180018620`**.

Define:
- **P** = wrapper third argument (R8, retained as R14).
- **H** = wrapper fourth argument (R9, retained as R12), the feature-state record passed in RDI at `0x1800197fd`.
- Wrapper's network pointer is at its receiver+0x48. The cast at **`0x180021cb0..1cd0`** supplies type descriptors `.?AVNetwork@HNetCpp@@` / **`.?AVCCNetwork@HNetCpp@@`** (`0x1811412b0`, `0x1811412d8`); successful result is saved at RSP+0xe0 and later used for setter RCX. This is an independent RTTI anchor, not a guessed receiver based on offsets alone.

### A: external vector construction

**`0x180021dae..1dcc`** requests backend virtual **+0xa8** with:
`RDX=*(P+0)`, `R8=&[RSP+0xd0]`, `R9D=2`.
On success, that output qword is placed in a **one-element vector** at RSP+0xf0 (`0x180022739..2776`). This exact vector is passed to either:

- network vtable+8 at **`0x1800227b2..27c8`**; wrapper `0x180028830` forwards it as **R9** to network vtable+0x10, or
- network vtable+0x10 directly, as **R9**, at **`0x1800227e0..2800`**.

This proves **E[0] → A**, not merely an argument-count correspondence.

Parameter reader **`0x180019f30`** sends key **`DLSSNR.Color`** (`0x1800aebe8`) with destination Praw+0 at **`0x180019f68`, `0x18001a07f..a08a`**; it sends **`DLSSNR.Backbuffer`** to Praw+0xa8 at **`0x18001a6bd..a6d2`**. In evaluation, Praw is copied to RBP+0x20. Its Backbuffer resource descriptor is copied to local RBP-0x50 at **`0x18001907b..908e`** (subrect fields can be adjusted afterward). At **`0x180019390..93af`**, a byte predicate at RBP-0x80 selects local Backbuffer versus Praw Color and copies the selected **24-byte resource descriptor** into the final P at RBP+0x1c0, passed to the wrapper at **`0x180019800`**. The selector is computed at `0x180019016..9033` from the request's UICorrection/non-null-Backbuffer/UI-related fields; this is not a claim about actual UI settings.

The separately named **`dlssnr_original_color`** allocation supplies **H+0x50**, explicitly by R8=&H.50 and R9=name at **`0x180019672..9688`**. Other branches use that snapshot later. **No direct H+50 → E[0] connection is established or assumed.** Pixel contents/in-place earlier modifications are not part of this resource-identity proof.

### B/C: named view requests, gates, stores

1. **`0x180021d3a..1da2`** permits motion-resource pointer P+0x18 only if **H byte+0x68 is nonzero, P dword+0x100 is zero, and *(P+0x18) is nonzero**. P+0x100 is populated from key `DLSSNR.Reset` in the parameter reader.
2. At **`0x180022067..207f`**, require **H+0x60 nonzero** and the preceding motion predicate. Otherwise both view-output locals remain zero, as initialized at **`0x180021ffc..2200c`**.
3. **`0x180022085..209d`** requests backend virtual+0xa8 with resource **H+0x60**, output **RSP+0xc8**, literal mode **0**.
4. **`0x1800220f0..210e`** requests the same backend slot with resource **P+0x18**, output **RSP+0xc0**, literal mode **2**.
5. **`0x180022626..2636`** passes these locals in **RDX and R8 respectively** to **`0x18003f490`** (RDX=previous-output view, R8=motion view; R9 is zero). Setter stores **RDX→N+0x298** at **`0x18003f4cc`**, **R8→N+0x2a0** at **`0x18003f4d3`**.
6. Setter first tests **global byte `0x1800e06d0`** (`0x18003f49d`). If zero, **both RDX and R8 are zeroed** (`0x18003f4b1..4b3`) before the stores. Initial on-disk value is 1, **not evidence of its value in a live launch**.

**Names are tied to destinations, not sampled channel counts:**

- **Previous-output resource:** allocator **`0x180017840`** retains second argument H in RBX. **`0x1800178f3`** loads literal `dlssnr_prev_output` (`0x1800aea68`), **`0x1800178fe`** sets R8=&H.60; backend allocation at **`0x18001794f`** fills that field. Evaluation calls this allocator with the same feature record at **`0x180018d46..8d4c`** (also `0x180018e09`). Existing diagnostic string describes RGBA16F; numerical format conversion and current contents were not reconstructed.
- **Motion resource:** **`0x18001a150`** sets destination **Praw+0x18**, **`0x18001a154`** loads literal **`DLSSNR.MVec`** (`0x1800aec78`), parameter-get call at **`0x18001a162`**. The request copying in evaluation preserves this resource field; the final source-resource override at `0x1800193a3..93af` covers only offsets 0..0x17, not +0x18. This is the named motion-input field, not an inference from the kernel's sampling operations.

Modes **0 and 2** above are exact integer API arguments; no filter/address/normalization enum meaning is assigned. Error paths may retry/log view retrieval; the stated bindings describe the successful-view path. This review does not claim every backend's success/failure behavior or that a null texture is numerically equivalent to a specific temporal reset.

**Important distinction:** N+0x2a8 is a separate field. The finalpost-specific append code reads **N+0x298 and N+0x2a0**, not N+0x2a0 and N+0x2a8. The previously anonymous C is now linked to MVec, not to the third field merely because three texture handles were expected.

## Verification and boundary

**15 CPU/static tests pass.** They check exact physical DLL hash, 13 frozen byte-slice hashes plus instruction transcription, all selected decode boundaries, copy/index/dispatch operands, real vtable targets and JMP-RAX thunk, literal parameter/resource destinations, and captured descriptor consistency. Opaque-handle CPU tests cover changed permutations with unchanged counts, duplicate indices, external-index versus block-output distinction, missing output-selector default0, trailing extras, type/pair gates and rejected negative/out-of-bounds indices.

`routing_reference.py` implements **only proved opaque-handle routing**, not native execution, image arithmetic, handle creation, or a full graph interpreter. Unsupported implicit-block routing fails closed. Tests validate static transcription and its symbolic consequences; they are not native runtime parity tests. GNU objdump independently confirms the network edge/append and layer gather/dispatch slices in `objdump-check.txt`.

Remaining boundaries:

- **Resolved:** descriptor-to-runtime block input; layer +a8 gather into the launcher's second argument; frontend view-output-to-E/state chains; named `dlssnr_prev_output` and `DLSSNR.MVec` field provenance.
- **Not resolved:** actual frame's selected graph/backend/variant/handles; history resource contents and exact update/reset recurrence; original/color/backbuffer pixel equivalence; API sampler enums and resource formats beyond literal diagnostics; packed slabs/weights; full network forward or current D3D12 equivalence.
- The captured factory(0) graph remains historical evidence. We do not assert all variants preserve those indices or that graph block70 was dynamically observed invoking this launcher today.

Reproduce, from this directory:

```sh
python -B collect_evidence.py
python -B test_routing.py
```

`evidence.json` records exact VAs, file offsets, bytes, tables and the bounded descriptor observation; `source-manifest.json` pins physical and historical inputs. `verification.txt` records collection, tests and independent-check commands. All writes are confined to **`reviews/nr-static-routing-20260911/`**.

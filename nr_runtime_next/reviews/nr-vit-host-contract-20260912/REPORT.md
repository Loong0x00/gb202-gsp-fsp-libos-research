# Block 31/32 ViT FFN host contract — static original-DLL review

## Result

This closes the previous *host-contract* boundary, not the numerical FFN:
original `nvngx_dlssnr.dll` bytes give concrete construction, virtual-forward,
72-byte launch-record, pointer-container, and grid evidence for the two actual
classes.  All VAs below are preferred-image VAs (`0x180000000` base).  The
DLL, PTX, prior slab manifest, and prior static name-rewrite record are pinned
in `SOURCE_PINS.json`; retained original code ranges and decoded text are in
this directory.  No PE was loaded or executed.

### Constructor → true vtable → forward lineage

| architecture class | factory match/call | constructor evidence | constructor-installed vtable | forward slot | init slot |
|---|---|---|---|---|---|
| `CCVit1DFfnExpand` | factory compares literal `0x1800b2818` then calls `0x180071120` (`host-factory-ffn-types.txt:...3388..3393`) | allocates 0x48 state at `layer+0x178`; requires `layer+50=0x400`, `+54=0x1000` | **`0x1800bb998`**, stored at `0x180071149` | `+08 = 0x180072840` | `+38 = 0x180073710` |
| `CCVit1DFfnContract` | literal `0x1800b2830`, call `0x180071060` (`...343b..3446`) | 0x48 state at `layer+0x178`; requires `+50=0x1000`, `+54=0x400` | **`0x1800bb9f0`**, stored at `0x180071089` | `+08 = 0x180072620` | `+38 = 0x180073610` |

These are the ctor stores, not a nearby rdata-looking window.  The complete
10-qword tables are in `EVIDENCE.json`; their common `+30` binder is
`0x180073340`.  The expand init at `0x180073710` selects the expand,
publish/chained, and (only when its local predicate is true) repack kernel
handles.  The contract init at `0x180073610` selects contract and chained
handles.  Both use `0x180073b50`'s local `_fp8` name predicate.  This is a
static name condition, **not** a claim about a global live mode.

The already-proven catalog record supplies only the static post-rewrite names:

```
block31 expand:   cc_vit_1d_ffn_expand_repack_input_fp8
block31 contract: cc_vit_1d_ffn_contract_fp8
block32 expand:   cc_vit_1d_ffn_expand_fp8
block32 contract: cc_vit_1d_ffn_contract_fp8
```

It is retained as an input pin, rather than re-derived or promoted to a live
object observation.  The four existing exact checkpoint slabs remain
respectively `4194320, 4196352, 4194320, 4196352` bytes (full records and
hashes in `EVIDENCE.json`); no slab was copied or interpreted as a tensor.

## Actual forwards and launch records

`0x180072840` is the expand virtual forward.  It calls
`0x1800731e0`, which scans the layer name for the literal `_repack_input`.
When true it requires exactly two output-vector entries and performs a real
preceding backend dispatch at `0x1800729b9`; that dispatch receives an
**18-byte** record: `{ input[0], output[1], arg5, arg6 }`.  The init code only
creates the `state+30` repack handle under that same name predicate.  Thus
block31's spelling has an actual host sublaunch lineage; block32's spelling
does not satisfy this predicate.  This is not an invented graph edge.

Both main forwards pass exactly `0x48` bytes at their backend call sites.  The
PTX declaration reserves an 80-byte parameter symbol, but the host passes the
72-byte live prefix; no bytes `+72..+79` are supplied by these forwards.
`arg5` and `arg6` are copied to record offsets `+64` and `+68`; they give
`N = arg5 * arg6`.  The following is an address/value-role diagram, where
`I[k]`/`O[k]` mean entries of the forward's runtime input/output pointer
vectors—not inferred model tensors.

```
Expand ABI, record base P (72 bytes), forward 0x180072840
 P+00 = I[0] normally; O[1] after the `_repack_input` sublaunch
                                  PTX expand dereferences it
 P+08 = 0                     host explicitly clears it
 P+16 = O[0]                  PTX expand dereferences it
 P+24 = *(state+00)           weight/state pointer; PTX expand dereferences it
 P+32,+40 = 0                 host explicitly clears this 16-byte region
 P+48 = I[1] or 0             optional-handle selector dependent
 P+56 = O[output-vector-count] or 0; retained as the exact host expression
 P+64 = arg5, P+68 = arg6     geometry

Contract ABI, record base P (72 bytes), forward 0x180072620
 P+00 = I[1]                  PTX pointer
 P+08 = I[0]                  PTX pointer
 P+16 = O[0]                  PTX pointer / final-store family
 P+24 = *(state+00)           PTX weight-read family
 P+32 = O[1]                  PTX counter address family
 P+40 = O[class-vector-count+1], or 0  PTX reduction/temp address family
 P+48,+56 = conditional host vector entries (pinned PTX entry does not load them)
 P+64 = arg5, P+68 = arg6     geometry
```

The `O[...]` expressions are deliberately positional: host bytes prove them;
they do not prove that `I[0]` or `I[1]` is a retained model residual.  The
contract error literal says its interface needs `skip, src` plus destination
and reduction control buffers, but this forward does not label the two vector
positions.  No residual edge is therefore asserted.

### Exact host grid tuples

At each backend-vtable `+0x28` call, the Windows-ABI fields after the
backend receiver are `RDX=kernel`, `R8D=grid.x`, `R9D=grid.y`, stack
`+0x20=grid.z`, stack `+0x28=&local_qword_holding_P`, stack `+0x30=record
size`, and stack `+0x38=flag`.  Thus the bytes give real grid components; this
result does **not** rely on absence of PTX `.reqntid`.

| dispatch | static condition | grid `(x,y,z)` |
|---|---|---|
| expand repack sublaunch | `_repack_input`; `_fp8` false | `(2*ceil(N/16), 1, 1)` |
| expand repack sublaunch | `_repack_input`; `_fp8` true | `(ceil(N/32), 1, 1)` |
| expand main | either name branch | `(32*ceil(N/128), 1, 1)` |
| contract main | either name branch | `(8*ceil(N/128), 1, 4)` |

The original instruction sequences are retained in `host-expand-forward.txt`
and `host-contract-forward.txt`.  The final CTA thread shape is still not
passed in these host calls; PTX obtains it from `%ntid.x * %ntid.y` for its
copy-barrier participant count.  This review therefore identifies exact host
grid, but does not fabricate a block shape.

## Contract reduction/counter, and why it is not a residual proof

In the pinned `cc_vit_ffn_contract_fp8` entry (PTX starts at source line
96241), parameter `+32` loads into `%rd12`; the conditional completion path
forms `%rd426` from it, performs
`st.release.gpu.global...s32 [%rd426], %r1507`, then polls that same address
with `ld.relaxed.gpu.global...` until its value reaches the computed bound
(entry-relative lines 4532 and 4540--4548).  Host `P+32 = O[1]` is therefore
the counter-buffer *role*.

Parameter `+40` loads into `%rd13`.  For `ctaid.z < 3`, the PTX executes the
visible `red.global.v4.f16x2.add.noftz` sequence against addresses based on
`%rd13`; other paths use ordinary global stores/loads from the same address
family.  Host `P+40` is consequently the reduction/temp-buffer role.  These
are actual cross-CTA reduction/completion dependencies.  They do **not** show
that either `I` vector entry is added back as a model residual, nor map either
runtime pointer to an upstream block output.

The main-source tail correction is retained only as a regression guard:
`bd650000`, `3ee50000`, `3f650000` are exactly `-0.055908203125`,
`0.447265625`, `0.89453125`; no older `-.05625/.3/.9` values are used here.
This review makes no activation or F16-conversion claim.

## Conditions and remaining unclosed branches

**Static facts:** ctor/type/vtable/slot lineage above; local `_repack_input`
and `_fp8` predicates; all ABI field stores; the sublaunch; grids; PTX
reduction/counter code; static catalog spelling; and slab byte pins.

**Live conditions not established:** actual layer-object names after creation,
state-handle success, pointer-vector contents, `arg5/arg6`, which optional
handle-selection branch fires, counter-buffer initial values/lifetime, and
whether any particular forward was submitted.  Therefore the remaining
unclosed branches are the runtime values of these predicates and buffers, the
producer/consumer identities of `I[]/O[]`, full CTA block dimensions, weight
layout/upload mapping, and any model-level residual/DAG edge.  None can be
closed by this CPU/static evidence alone.

## Reproduce

```sh
python -B reviews/nr-vit-host-contract-20260912/collect_host_contract.py
python -B reviews/nr-vit-host-contract-20260912/test_host_contract.py
```

The collector reads only literal pinned paths and writes only this review
directory.  It does not use GPU, Wine, native/PE execution, PE autoanalysis,
network, installed-path scans, or sibling-review writes.

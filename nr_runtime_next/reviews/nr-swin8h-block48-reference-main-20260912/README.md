# Block48Reference — complete bounded Swin8h-upsample NN component

```python
from block import Block48Reference
model = Block48Reference.from_checkpoint(checkpoint_path)
result = model.forward(low_fp8_codes, skip_fp8_codes,
    hooks={'attention.probability_half': inspect_tensor})
out = result['output']
weights = model.weights()
```

Canonical arrays are uint8 E4M3 codes: low[4,4,512], skip[8,8,256], output[8,8,256]. `forward_packed` separately accepts the proved channel16-planar low bytes and canonical-C tile-packed skip bytes. Neither API accepts RGB images or silently inserts unknown activations. `weights()` exposes11 detached immutable named tensor views; hooks expose named logical stages, not interpreter/DLL handles. Forward runs only tensor math.

## Evidence

Complete original block48 learned slab, named checkpoint range and whole checkpoint SHA verified during construction; pinned measured half-input RSQRT/RCP LUTs loaded then. The FIRST forward after construction passed an audit guard rejecting file/process/dlopen/socket I/O. No user hooks were installed for that I/O check. Runtime still depends on local Python arithmetic/layout helpers: this is not a self-contained distribution.

All original10752MMA operations are covered by the separately accepted source-operand checks on the connected fixture:
-512 upsample prefix;
-5632 FFN;
-3072 raw projection;
-256 seeded QK,256 PV,1024 final projection.

Original source intermediates, half arithmetic order, source versions/byte origins, normalization/packing/transpose, final stores and all original loops/barriers were checked by those oracles. Whole NN output16384B SHA3da96cddc0606a05fdc173bc333d6adeda7f928f66094aa75cb82418ed18d753 matches the full original CPU entry. Heldout new low/skip fixture also matches full original output SHAe21aec2c4592ca7ac849cd7a484e322b77c444b9e268604b090d196d75c02e53. New heldout is whole-output/boundary evidence, not another all-MMA intermediate observer run.

`COMPOSITION.json`,4passing component tests, and preceding `nr-swin8h-{up-main,ffn-tensor-main,qkv-tensor-main,qkv-normalized-main,attention-tensor-main}-20260912/` provide detailed evidence. The observed first-forward CPU time is for this tiny fixed component only, not game/native/4K performance.

## Not promoted

This is a complete **bounded neural-network component**, not the complete NR model or native-equivalence proof. Input features are explicit non-live fixtures; block47 producer-layout compatibility/live geometry, whole graph, pre/post/history, cross-frame visibility and existing4h226/8192native mismatch remain separate. No GPU/PE/Wine execution or game/deployment changes. Finite/overflow/LUT-domain refusal is intentional; arbitrary activations outside those domains are unsupported.

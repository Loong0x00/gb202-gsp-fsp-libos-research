# Main raw Swin8h projection NN lift (normalization NOT yet accepted)

`qkv.forward_raw(features,slab,hooks=...)` restores the64x256→64x768 FP8-input/F16-output projection after the proved FFN. Matrix is source-backed B(k,n,768) at492544,196608bytes. Canonical-C feature input is consumed in actual A basis; zero C, eight ordered K32 RN-half steps. The64x8x3x32 view denotes actual per-warp bank groups; Q/K/V consumer identities and normalized output semantics are a separate next step.

First implementation SHA9a956cead804631aac28ed1a7a666fd9583780cdec1969f3923db6b200705f92 unchanged. First raw98304B half prediction SHAb12a44eecc24f0080bd9743e2312dd55abc89e53000cf9dd32f097015adf35cc.

All3072 original projection MMAs checked: actual shared epoch5 A addresses and FP8 bytes, actual slab B byte origins and FP8 bytes, C before and independently computed D after every K32. All49152 final register halves compared at the actual loop exit. The entire original10752-MMA entry still ran to8warp returns; original final16384B output SHA3da96cddc0606a05fdc173bc333d6adeda7f928f66094aa75cb82418ed18d753 unchanged. No shortcut past normalization/attention in the oracle.

4testsPASS: all operands/register boundary, unchanged first code/prediction, wrong-weight-base provenance negative, immutable named hook/domain and loop-exit source witnesses.

## Preserved observer failure

Initial checker selected PC4235 as an alleged post-loop boundary. It is actually the loop counter move; the backedge is PC4236, and genuine exit is PC4237. At first iteration it compared partial K32 values to final K256 values. `FIRST_RAW_CHECK.log` and `CHECKER_BEFORE_LOOP_EXIT_FIX.py.txt` preserved. Only observer boundary moved to the source-proven exit, with counter==256 assertion. Original PTX, VM, tensor candidate and weights unchanged; entire entry re-executed, all3072MMA checks and49152halves passed.

## Limits / next

`normalized_QKV_proved=False`. This is the RAW learned projection only, not normalized Q/K/V or full attention. Source-only normalization report has now arrived in `../nr-swin8h-qkv-norm-source-20260912/REPORT.md`; it still requires Main numeric/lineage validation. The source report is not an oracle. No new native/GPU/whole-model/synchronization/standalone-package claim. Only original block48 slab and explicit non-live local fixture admitted for the executed comparison; raw forward exposes finite tensor computation without a VM but retains local helper imports.

# Main review: ordinary Swin8h source handoff

Report retained unchanged. Confirmed directly in the exact original standard entry: FFN gamma loads begin360464 (not360448/360480); raw QKV starts360992; Q scale623136; final matrix623168; final gamma688704. Two16-byte gaps bracket the FFN gamma. No scalar operation is inferred from those unused gaps. Standard vs up offsets are field-specific, not a whole-slab translation.

Corrections:
- Bias/seed warp byte stride is8192, NOT2048. Original7467–7469 performs `r3264=r19<<11; rd189=4*r3264`, with r19=tid.y. Full seed range557600..623136 is consistent with8192*8. The worker's2048 expression and its stated range were inconsistent.
- Sign-bias + arithmetic shifts implement truncating signed division by4, NOT floor for arbitrary negative coordinates. On the admitted multiples-of4 origins the results coincide, but they must not be generalized.
- Group projection loads also include1024*q for q0..3; rd306 remains the loop-carried slab base and advances after the loads. The table's first-trip addresses omit q; do not interpret them as all iterations.

The chosen real block49 (and block16) descriptors are named shifted. The primary graph edge48→49 is source-backed, but actual host shift values must still be resolved. Testing zero or -4 caller origins is an explicit conditional CPU experiment, not proof that either is the live instance configuration. Main will preserve original padding/zero paths and recover them from ingress instructions before connecting shifted grids.

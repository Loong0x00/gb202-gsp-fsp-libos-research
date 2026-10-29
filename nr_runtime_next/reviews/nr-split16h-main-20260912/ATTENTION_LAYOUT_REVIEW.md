# Main review: do not upgrade tautological byte maps into logical-layout proof

The worker's five static tests pass, but Main inspection found an important limitation in `layout_audit.py`: both transport maps are constructed as `(offset,offset)` over32768 bytes; ingress chunks are simply `512*i` over64 entries. Their tests prove identity/bijection of these constructed tables, **not an independently derived mapping of original producer/consumer register, channel and spatial addresses**. The slab partition exhausts the interval, but interval coverage and a few source anchors are not all-site typed-operand provenance.

Therefore Main does **not** accept this delivery as closing the requested logical P->QKV->layer3 proof. The actual-reference-policy QKV result remains explicitly UNVALIDATED-layout and is not fed to layer3. Conditional source-program execution, structural async tests, mathematical policy correctness and logical-layout verification stay separate.

## Host window/vtable correction

The copied window beginning0x1800ba260 is not the beginning of the QKV vtable. Treating its+0x40 as the QKV virtual method slot is misleading: that offset crosses into the next table. Main independently decoded the pinned DLL and found the actual QKV method table at **0x1800ba298**:

- table+0x08 = forward **0x18006d260**;
- table+0x38 = initializer **0x18006e230** (the separately identified QKV-name/CTA initializer).
- LEAs installing/referring to that exact table occur at0x18006aa7e and0x18006ad0a; the other constructor snippets at6a7e0/6a8b0 must not be paired by guessed class order.

Main also disassembled the full copied forward:0x18006d423 loads target `[r10+0x28]`;0x18006d427 writes literal4 to `[rsp+0x20]`;0x18006d42f dispatches through the guard thunk. The preceding code sets grid x/y arguments and packed-argument pointer. This supports the **static QKV forward grid-z4** lineage when coupled to the true table/initializer, not live runtime selection/submission.

See `QKV_FORWARD_DISASSEMBLY.txt` and `QKV_HOST_TABLE.json`. Original worker artifacts and their historical claims are retained, not silently rewritten. No GPU, DLL execution or installation change was used for this audit.

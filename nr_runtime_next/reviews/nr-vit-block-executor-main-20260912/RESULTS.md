# Main: actual ViT block primary dataflow recovered

Current signed DLL is read statically only. `PRIMARY_GRAPH_PROOF.json` pins its hash and50 instruction witnesses; complete bounded constructor, builder and generic dispatcher disassemblies remain here. Five tests PASS. This is source-backed review plus an abstract primary-pointer binding check, not execution of the PE or a formal proof of its entire allocator/CFG.

## Block vs layer vtables

`cc_vit_1d_block` constructor0x180043260 installs vtable0x1800b27a0. It has TWO slots here: +0=0x18002ac60 (generic block execution), +8=0x1800446d0 (shape propagation leaf through0x180044702). Following0x1800b27b0 is error-string data, not extra methods. The block dispatcher itself calls each layer's vtable+8 at0x18002b3a2. Do not conflate the block and layer slot layouts.

## Independently identified primary graph

Current builder0x1800439d0 constructs five0x170-byte descriptors in order Expand,Contract,QKV,Attention,Projection. The non-input-repack branch at0x180043ca5→0x180043ecb explicitly sets:

| layer | +a8 block inputs | +90 prior layers | +c0 output selectors | dispatcher primary I |
|---|---|---|---|---|
|0 Expand|empty|empty|empty|X (first-layer default)|
|1 Contract|[0]|[0]|[0]|X,F|
|2 QKV|empty|[1]|[0]|P|
|3 Attention|empty|[2,2,2]|[0,1,2]|Q,K,V|
|4 Projection|empty|[3,1]|[0,0]|A,P|

Here F=expanded hidden, P=contracted FFN output, A=attention output. The dispatcher appends block-input sources before prior-layer sources. Thus the contract host's I[0]=skip X/I[1]=expanded F and projection host's I[0]=attention A/I[1]=skip P are both satisfied. Projection's residual is the FFN output, not initial X or expanded F.

Builder stack proof: RBP=RSP+0x100; contract descriptor baseRBP−0xb0 means its+a8/+90/+c0 atRBP−8/−0x20/+0x10, written zero at0x43f9f/0x44080/0x44109. QKV descriptor baseRBP+0x3a0 writes[1]/[0] at+0x430/+0x460 (0x441f9/0x4423d). Attention base+0x230 copies[2,2,2]/[0,1,2] at+0x2c0/+0x2f0. Projection base+0xc0 copies[3,1]/[0,0] at+0x150/+0x180. r13=0,rsi=1,r14=2 and the stack-source arrays are explicitly pinned, not guessed from output matching.

The preserved factory(0) log independently gives those same fields for block32. Its INDEX_VECTOR records omitted offsets: `parse_historical_edges.py` pairs offset-ordered VECTOR records with INDEX records only when record and count sequences agree, retaining overlapping scanner false positives as untyped. Only fields whose roles are checked in current source get labels. The old log itself is not misrepresented as a fresh current-DLL run. Current builder agreement on the same values supplies independent current-source evidence. Blocks32–37 have the same primary routing; this does not prove every block's numeric outputs.

## Auxiliary vectors are not primary residuals

+108/+120 refer to prior completion outputs; +138 to block completion inputs. Prior completion index is offset by that producer's primary-output count. The tensor specification stride at+d8 is12 bytes (magic high-multiply2aaaaaaaaaaaaaab then SAR1), not24. A24-byte stride applies elsewhere to vectors of vector objects. The tests explicitly distinguish this; no live counter initialization or native acquire semantics is inferred.

Block31 input-repack branch uses two layer0 primary outputs: contract sources layer0 output1 (repacked skip), then output0 (expanded). It must not silently enter the ordinary one-output model. Block38 output-repack also remains a separate boundary. Neither is solved by padding unknown tokens.

## Claim upgrade and remaining limits

The prior five-op CPU byte composition now has source-backed non-repack primary topology; it is not merely an invented runnable order. Fresh counters−1, temporary allocation ownership, route/live geometry, epoch/visibility and outer-model temporal edges are still separate unproved conditions. This does not retroactively turn old COMPOSITION.json's historical classification into a false report; that artifact is left unchanged.

NoGPU/PE/Wine/installed/network changes. Follow-up NN interface is `../nr-vit-block32-reference-main-20260912/`.

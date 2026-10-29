# Main outer primary graph, exports and auxiliary binding roles

Current signed DLL static witnesses43 and4 tests PASS. Complete candidate/selected bounded disassemblies are retained. No PE execution or fresh live-memory capture. `RETYPED_FACTORY_GRAPH.json` is a NEW interpretation of the preserved factory(0) trace; original architecture.json, dump log and collector source remain unchanged.

## Correct BlockDesc field meanings

The historical collector assigned names mechanically, without proving consumer roles:

| offset | recovered role | old collector label |
|---|---|---|
|+38|primary input block indices|input_blocks|
|+50|primary exported-output selectors (default0)|input_block_outputs|
|+68|auxiliary input producer blocks|input_layers|
|+80|producer LAST-layer auxiliary buffer selectors (default0)|input_layer_outputs|
|+98|extra external input-vector indices|completion_input_blocks|
|+b0|exported layer indices|completion_input_block_outputs|
|+c8|exported layer-output selectors (default0)|completion_input_layers|

Thus block32's old input_layers=[31],input_layer_outputs=[1] is NOT feature input from block31's primary output1. That primary export does not even exist. Treating it as such fails the independent export bounds test. The primary feature path uses the default previous block output0; auxiliary1 is appended from a separate buffer table.

## Current consumer evidence

-0x18003cc80 executes a block range. Primary explicit gathers read+38/+50 and global primary pointer vectors at this+1f0. An empty+38 uses previous block's default pointer this+110; the binder0x18003e4e0 sets that default to the first primary exported pointer. +98 appends selected external input-vector elements. First/pre/post-specific history input augmentation remains a separate branch.
-0x18003dfd0 builds export pairs from+b0/+c8. If absent, it exports all primary outputs of the LAST layer, using that layer's12-byte tensor-spec entries or default1. Binder0x18003e4e0 resolves those pairs through layer/output slot indices and workspace offsets, building this+1f0. This establishes pointer selection semantics, not complete allocation/lifetime safety.
-Aux binding at0x18003f010 reads+68/+80, selects the producer's LAST layer in this+210, obtains its selected internal-buffer offset, and builds this+1d8. Range execution appends this separate vector to the primary inputs before calling block vtable+0. It does not index the primary export table for these fields.

## Bottleneck and decoder connection

Block30 explicitly exports[(layer4,output0),(layer3,output0)]: head output and full-resolution pool/projection output, not pooled output1. Block31 takes block30 primary export0, then blocks32–38 each take the previous ViT block's primary export0. Block39 explicitly receives[(block38,export0),(block30,export1)] = final ViT/repacked head feature plus retained full block30.layer3.output0. This is source-backed routing, not assumed sequential adjacency.

The new parser checks all71 preserved blocks/152 layers, acyclic primary inputs, and every selected primary export against the declared primary counts. It does not assign tensor coordinates from those counts. Geometry, manager mutations, active live variants, workspace capacities/aliases, initial counter contents/epochs and native visibility are not promoted by this graph proof. Existing independent numeric limitations remain.

All work CPU/static in reviews only; noGPU/PE/Wine/game/install/network changes.

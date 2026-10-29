# Block55 OUTVIEW: complete bounded NN and original-store proof

Exact5759-op88ABI FP8 OUTVIEW entry, sourceSHA5f2d0b18269a375b703b72e2fb997f2fe2091f6ed3b166365f121ef41199d723. Original block55 named slab689232 SHA c4e79845c2c12855841a8d2b1c5b59426f7ac638c473f788fb04004c90148377; whole checkpoint verified. Private VM only enables the already-implemented exact `st.global.v2.b16` form. Original PTX/loops/arithmetic/weights unchanged.

## Tensor semantics

Same source-proved ordinary8h core, with4983 exact common-core instructions matched under register/symbol/branch-target renaming, not merely opcode counts. All10240MMA/scalar/source-provenance checks were also run on the original OUTVIEW entry.

Output80/84 select positive effectiveH/W, otherwise input32/36H/W. Final16guarded4-byte stores use per-coordinate bounds. Physical channel16-planar layout is:
`offset=16*((k//16*OH+y)*OW+x)+k%16`, where stored value is canonical-C output at channel**pi(k)**. All original final-neuron tags and emitted addresses prove this nonidentity basis. It is NOT a plain reshape of canonical-C output. The NN computes each full window before masking/scattering; no original padding arithmetic is omitted.

## First predictions and original grids

First `nn.py` and all predictions unchanged. Input is a declared fixed block49 output fixture, not yet a restored block54 activation in this directory.

| case | effective extent | originalCTAs / MMA | output SHA |
|---|---|---|---|
|origin(0,-4),80/84=0|8x8|2 /20480|4fc59237b82f109451399933c9c455805c47f92d5110407931843f4f6aeb8e03|
|origin0|8x8|1 /10240|2444adb77645cf5abe6e387f6752908b2895f14aad730f42858a4a132111830f|
|positivecrop|5x7|2 /20480|c8c648158a2d69ed9c6b88f832791e9c09a4ee6a602a112b10c9e1f9d2ec9ee6|
|positiveexpanded|12x8|2 /20480|5fc4d3beccb7126acf4ba4454688e43c8ce18277ecdaed15925ed47ef9d366f0|

All7originalCTAs/56warpsret,71680MMA, all shared ingress/group/FFN/PV boundaries and every final byte matched. Larger requested13x8 outside emitted coordinates is refused as missing output. Negative output extents fall back by signed source predicate. Expanded original ghost rows8..11 include6708nonzero-magnitude FP8bytes out of8192; not fabricated zeros.

Default firstCTA received complete FFN/raw/norm/attention/final original operand and intermediate checks: all10240MMA plus scalar/byte/epoch provenance. Its8192copied+8192originalzero shared ingress bytes are tracked. Crop5x7 andexpanded12x8 lastCTA tail checks independently verify all1536tailMMA and original per-coordinate stores, including1792crop bytes and16384expanded bytes. First store checker passed; identity-channel alternative is rejected by neuron provenance.

5testsPASS.21current-byte host/name witnesses recorded. Source worker's third-vs-seventh argument error corrected separately; seventh selects outview, third selects shifted/constant_pad_nd. Conditional selector strings do not establish a live instance or native synchronization route.

This directory is a complete bounded OUTVIEW NN component with local helper dependencies, not a full NR/native/standalone delivery. The later decoder-stack directory separately uses actual connected block54 output and verifies complete original49..55 grids.

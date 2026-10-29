# Main pool/head host and primary-edge recovery

Only bounded static reads of current signed DLL; hash e16bcf15… unchanged. `HOST_GEOMETRY_PROOF.json` verifies36 current x86 instruction witnesses, with full bounded source windows retained. Unwind .pdata omits the small shape leaves, so they were read at exact vtable targets rather than treated as nonexistent. Initial wider vtable windows are preserved separately: +0x50 is following metadata/string, not another method.

| component | ctor | vtable | +8 forward | +38 init | parameter bytes | CTA |
|---|---|---|---|---|---|---|
|pool|0x18006a980|0x1800ba348|0x18006cfd0|0x18006e0b0|80|32×4×1|
|head|0x18006a7e0|0x1800ba3a0|0x18006cbe0|0x18006dc60|40|32×8×1|

For positive caller block geometry H,W, set Hp=round_up4(ceil(H/2)),Wp=round_up4(ceil(W/2)) (=4ceil(H/8),4ceil(W/8)). Pool grid=(2ceil(W/8),ceil(H/8),1); parameter+64..76=(H,W,Hp,Wp). Head grid=(4ceil(Wp/8),ceil(Hp/8),1); parameter+32/+36=(Hp,Wp), NOT original caller H,W. Head kernel8×8 is therefore admitted by caller block16×16; caller8×8 would produce kernel4×4 instead. The old explicit8×8 head calculation was a callee condition, not proof that host inputs were8×8.

Pool+0/+8=I[0]/I[1] projection source and retained skip; +16/+24=O[0]/O[1] full and pooled feature outputs; +32=slab. Plain route leaves +40..63 unused0. Head+0=I[0],+8=O[0],+16=slab,+24 optional readiness (plain0). Variant selection and optional flags remain conditional, not observed live.

Current block builder0x180040e20 uses pool constructor branch and gives head descriptor baseRBP+0x3c0. Its prior-layer vector at+0x90 (RBP+0x450) is[3], selector vector+0xc0 (RBP+0x480) is[1]. Generic block dispatcher previously reviewed therefore gives head **pool output1**, not full output0. Preserved historical block30 layer records independently agree; pool itself consumes layer2 output0 and retained layer1 output0.

The historical root-field names in graph-factory.log/architecture.json are collector labels, not sufficient evidence for every outer-graph/extra-output role. Builder fields+b0/+c8 and outer allocation/export selection still need an independent consumer audit before declaring the complete block30→decoder/global DAG. We do not infer outer exports merely from[4,3]/[0,0] values or label names.

Accepted bounded CPU execution uses these exact H=W16 pool and Hp=Wp8 head contracts in `../nr-split16h-pool-main-20260912/`. Host source admission is not proof of live geometry, ownership, epoch, native ordering or numerical equivalence. NoGPU/PE/Wine/installed/game/network modifications.

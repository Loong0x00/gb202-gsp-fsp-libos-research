# Main review: expected static block49 origin, with worker axis correction

Worker REPORT.md retained. The first(1,1) pair→expected block49→(-4,-4) conclusion survives. However its X/Y labels were reversed for asymmetric pairs.

The ordinary aggregate starts at `[rsp+0x70] = [rbp-0x90]` (forward prologue and69e5b/69fe3). Stores69e92/69e95 put ECX at`[rbp-0x68]`=parameter+40 (X) and R12D at`[rbp-0x64]`=+44 (Y). ECX came from runtime+7c;R12D from+78. The PTX prologue explicitly uses+40 for ctaid.x and+44 for ctaid.y. Therefore:

- originX=-4*max(runtime+7c,0)=-4*max(desc+74,0)=-4*max(table.first,0);
- originY=-4*max(runtime+78,0)=-4*max(desc+70,0)=-4*max(table.second,0).

Expected decoder table origins for historical blocks49..55 are consequently
(-4,-4),(-4,0),(0,-4),(0,0),(-4,-4),(-4,0),(0,-4).
The worker had the two asymmetric entries swapped.

Typographic corrections: builder is068ea0, saveR9D is068ecb (not0688ea0/0688ecb); ctor retains this inR14 at068658, while06865b is the stack copy. Seven pushes plus LEA establish builder RBP=entryRSP-3d8, soRBP+400=entryRSP+28, Win64fifthargument. Firsttableword is passed at callerRSP+20;second inR9D.

The optional pointer at runtime+158 writes a DIFFERENT pair of aggregate parameters+56/+60, not mainX/Y+40/+44 and not the grid-origin locals. It does not undermine this primary-origin dataflow on the shown path. Its consumers/readiness and specialized entry routing remain separate, not proved by plain numerical execution.

Main accepts CURRENT-STATIC expectedfactoryroute usingcurrent instruction/data witnesses plushistoricalsource-retyped ordering; no fresh DLL factory/live fieldcapture. For H=W=8, block49expected(-4,-4) gives2x2CTAgrid. All four originalCTAs and NN output have already matched under those explicit arguments; first/lastCTAall-MMA/scalar/provenance checks include12288 original internal zero bytes, not extra caller padding. Native visibility/mutableinstance guarantees remain unpromoted.

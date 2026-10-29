# SOURCE-ONLY 4h two-phase tail finding

## Disposition
**Confirmed:** the original has two distinct 32-query attention/PV/final passes, and its shared-memory reuse explains the reported epochs without relying on byte equality.  This is source evidence only; it does **not** establish native execution, all-domain behavior, or all-intermediate equivalence/acceptance.

## Operand and query-half ownership
* Phase 0 QK is PC 5065–5080 (`SOURCE.txt` original lines 09941–10049).  Its two m16 A operand banks are `r3686..r3689` and `r3720..r3723`; its K B operand sequence is `r3682/3, r3690/1, …, r3714/5`.  Thus the two m16 tiles are query rows 0–15 and 16–31 (phase-0 rows 0–31).
* Phase 1 QK is PC 6186–6201 (12495–12603): A banks `r4773..r4776` and `r4793..r4796`, i.e. rows 32–47 and 48–63; it reuses that exact K B sequence (`r3682..r3715`).  The deferred Q codes are explicitly retained as 16-bit `rs505..rs520` (08401–08446), then packed into those A registers only after phase 0 (12413–12420).
* V is the E4M3 B bank `r4083..r4112`: phase-0 PV PC 5679–5694 uses it (11372–11480), and phase-1 PV PC 6786–6801 uses the same bank (13893–14001).  K and V are consequently source-proven live across phase 0; they are not reconstructed from a shared snapshot.
* The normalized-probability E4M3 A packs for PV are `r4085..r4124` in phase 0 (11260–11370, consumed at PC 5679–5694) and `r5151..r5176` in phase 1 (13781–13891, consumed at PC 6786–6801).  QK MMA opcode operands are E4M3 and C/output fragments are F16; the score affine/clamp/packing is source-visible at 10084–10623 and 12610–13149.

## Scratch overwrite and residual lifetime
* Phase-0 residual is read **before** its PV result is stored: shared `[r39]` and `[r39+2048]` load at 11492/11501, are decoded and gamma-multiplied into the actual initial-final C bank `r4248/49, r4252/53, r4256/57, r4260/61, r4266/67, r4268/69, r4270/71, r4272/73` (11768–11873).  Those are C operands of first final K32 group PC 5992–5999 (11989–12041).
* Only afterwards does phase-0 PV write `r4226..r4235` to `[r39]` and `[r39+2048]` (11938/11947); `r39 = shared_base + tid.y*512` (11486–11499).  This is the source proof of the first-4096 PV overwrite observed at epochs 7/8.
* At phase 1, residual instead reads `[r39+4096]` and `[r39+6144]` (14010–14020), then gamma-multiplies to the second final seed bank beginning `r5299/r5300` (14282–14388).  Its PV writes again target only `[r39]` and `[r39+2048]` (14452/14461), not the +4096/+6144 locations.  Therefore epochs 9/10 having first 4096 = second PV while last 4096 remains FFN is **confirmed from instructions**.

## Final K32 carry order (must remain explicit)
* Phase 0 barrier PC 5969 is source line 11949.  Final groups are PC 5992–5999, 6020–6027, 6048–6055, 6076–6083 (11989–12317): C carries are seed `r4248...` -> `r4286...` -> `r4324...` -> `r4362...`.  Weight-load group bases progress `+213520/+214032`, `+217616/+218128`, `+221712/+222224`, `+225808/+226320` (11958–12262): original K=0–31, 32–63, 64–95, 96–127 order.
* Phase 1 barrier PC 7069 is line 14463.  Its final groups PC 7090–7097, 7118–7125, 7146–7153, 7174–7181 (14501–14829) carry `r5299...` -> `r5337...` -> `r5375...` -> `r5413...` in the same four K32 groups.  Final barrier PC 7233 is line 14923.

Main should observe both query halves and every original K32 accumulator transition; no full-token elision or arithmetic substitution is source-justified.

# Progress — completed bounded Task A

## Delivered

- `FIELD_MAP.json`: nine exact typed slab fields, four untyped gaps, full logical weight-byte maps, embedding source A/B/C/D maps, all272 MMA register lists/logical D maps/C definitions, FFN and attention/final equations, ABI consumption and explicit assumptions.
- `REPORT.md`: detailed findings, exact authorized input paths actually read, failure preservation, verification and limits.
- Own static scripts and provenance artifacts; no external review imports, learned numerical inference, or original execution.

## Independent findings

- ONE-K16 half embedding16→32 at8208;64 computational rows map to source8×8 pixels through an explicit permutation.
- Unquantized E*g_ffn residual at9232 versus F8(E) EXP fork.
- Interleaved EXP/CON32→128→32 at0..8192, with four ordered K32 C carries and recovered clipped cubic activation.
- QKV at9312 (32→96); QK half C seed12384 (64×64); own F32 Q gain20576; final FP8 matrix20592 (32→32); final half residual gain21616.
-109 slab load sites cover21636 typed bytes;60 bytes unread and untyped.
- Source packed-word attention map retained, not replaced by ordinary exponential/softmax. Exact pre-PV half-add normalization tree and row redistribution proved symbolically for4096 scalar uses.

## Verification

`extract_static.py`: hashes and6459 indexed instruction matches PASS after correcting index-only `ret __terminal__` annotation. Initial failure remains in `extract_static.log`.

`build_field_map.py`: address bijections, all weight operands, embedding shared operands, QK seed map, FFN/final/PV carries,128 activation patterns and QK/PV symbolic operand identities PASS. Final enriched run in `build_field_map_enriched.log`.

`verify_reduction.py`: both32-query halves' exact denominator trees and routing PASS. Final run in `verify_reduction_enriched.log`.

## Bounds / caveats

33 conservative original-input read units: seven bounded tool reads (manifest included), plus26 extraction chunks including the failed pass. All source text chunks≤2000 lines; binary slab reads bounded to21696B. No further original input reads after the comparative post attention read. Exact paths are listed in REPORT.md.

No DLL/PE bytes read or executed, network, GPU/CUDA/Wine, chmod, input mutation, or nested agents. Only writes under this out directory. Native arithmetic equality, host launch/ABI binding, texture ingress values and selected-half output routing remain unproven. Main retains first NN prediction, freeze and acceptance.

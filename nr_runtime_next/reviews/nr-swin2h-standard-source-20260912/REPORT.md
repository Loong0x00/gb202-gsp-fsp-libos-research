# Bounded source review — own ordinary 2H blocks 63/64

## Scope/result

This is a source-only review of the ordinary 4,845-op entry, contrasted structurally (not ledger-copied) with the 7,064-op UP entry. It does **not** establish ordinary acceptance, a numerical result, native execution, or full-model behavior. Graph context binds 63<-62 and 64<-63; block 65 is the separate 5,301-op OUTVIEW and is not covered.

The supplied chain result remains relevant only as prior provenance: block 62 was source-proven as 16 CTA / 13,824 MMA at C64 32x32. It does not prove an ordinary 63/64 live ingress or output merely from labels.

## Ordinary ingress, bounds, ABI, and storage facts

* The ordinary prologue loads P8 to `%rd8` (line 12), P0 to `%rd1` (13), and P16 to `%rd9` (16); P16 is converted to `%rd2` (17). Thus P0 is the source feature-address operand in the initial loads, P8 the store-address operand, and P16 the slab-address operand in this entry. P24 is not loaded by this ordinary prologue.
* P0/P24 describe ABI parameter offsets/aliases, not graph tensor identity. Graph I0/I1 binding is a separate fact; no live-origin conclusion follows from the names or offsets.
* The ingress OOB path is explicit: predicates select the non-load path at lines 80–93, form f32 zero, round it to f16, convert/saturate it to e4m3x2, and replicate it into the loaded vector registers. This is source zero-fill, not an unproven host-side pad. Stores are separately predicate-gated (e.g. 10376–10407 and 12702–12731); the source does not write an OOB zero there.
* Coordinate division is signed truncation logic, not floor/ceil: the sign correction followed by `shr.s32` appears at lines 24–39 (and repeats). Keep that exact behavior and the original predicates/zero masks.
* The declaration is static `.shared ... shared_storage[4096]` (line 11), not `extern`/dynamic shared memory. The source has material `bar.sync 0` phase boundaries (for example 4324, 8045, 10416, 12458, 12734); they must not be elided.

## Ordinary slab map actually addressed

The following is an address map relative to ordinary P16, derived from the concrete base displacements and adjacent access constructions. It is an accessed-map statement, not a claim about allocation length or value contents.

| byte range | source role evidenced by dataflow |
|---|---|
| 0..16383 | first FP8 weight slab (the two-pass initial/expand region) |
| 16384..24575 | grouped-projection FP8 region |
| 24576..28671 | FP8 mix/projection region |
| 28672..28687 | gap before first gamma |
| 28688..28815 | first 64-half gamma vector |
| 28816..28831 | gap before raw QKV weights |
| 28832..41119 | raw-QKV FP8 weight region |
| 41120..57503 | two-head QK seed/bias region |
| 57504..57511 | two f32 Q-scale words |
| 57512..57519 | gap before final projection |
| 57520..61615 | final FP8 projection region |
| 61616..61743 | final 64-half gamma vector |

In particular, the ordinary gamma loads are at +28688 (e.g. lines 367–735) and +61616 (e.g. 9752 onward), not the UP gamma locations. The raw-QKV slab starts at +28832 in ordinary (4368 onward); the QK seed region begins at +41120 (8054 onward). These ordinary facts supersede the incompatible candidate offsets when describing this entry.

## Arithmetic/order facts retained

* The actual ordinary MMA opcode is exactly `mma.sync.aligned.m16n8k32.row.col.f16.e4m3.e4m3.f16` (e.g. 1048–1051, throughout). Its accumulator type is f16; this report does not substitute an f32 MMA claim.
* Each exposed matrix phase retains K32 accumulation and FP8 conversion boundaries. The source contains the f16x2 cubic activation sequence `min`, `max`, `abs`, two `fma.rn`, then `mul` (1234 onward); it must remain in this order.
* The raw-QKV material is produced before the separate half-domain normalization trees: ordinary makes the raw banks through the shared exchange and MMA block around 4324–5176, then squares/reduces, epsilon-clamps, `rsqrt.approx.ftz.f32`, rounds to f16, and applies factors (5184 onward and the second repeated half). Therefore no normalization may be moved after QK/PV.
* QK applies the f16 affine/clamp and packed bit mapping (8234 onward); probability normalization precedes the two K32 PV passes. The packed map, exact half reductions, and `prmt`/shuffle lane order are source-observable and are not replaceable with a generic softmax.
* The final residual paths are early seeded by their gamma before the following K32 accumulations; preserve the existing conversion points, barriers, packed mapping, and masks.

## Ordinary versus UP: limited structural differences

* Ordinary has a two-pass loop headed at `L__BB1_21`: `%r4268` begins at 0, is set to 1 at 4170, and branches once more through the saved predicate (4171–4173). UP's corresponding early loop uses `%r5893 = 0,32,64,96`, advances by 32, and branches while `%r5893 < 96` (UP 84–283): four K32 iterations. This is a source-structure difference, not permission to transplant the UP operation ledger.
* UP's raw-QKV weight accesses begin at +37120 (UP 6338–6393), whereas ordinary's begin at +28832. UP also uses its own later ranges, including Q scale +65792, final weights +65808, and gamma +69904; none are ordinary slab bases.
* Both entries visibly use the same literal MMA type above; the UP source is not evidence for a different f32 accumulator type. Its different width/phase layout and additional parameter use make it non-substitutable.
* The ordinary later tail has separate predicate-controlled half-stores at a base and base+1024 (10377–10407, then analogous final pair 12702–12731). UP has its own distinct p4/p2 two-half tail (14659–14701). These are physical tail structures; neither proves a semantic output binding or authorizes copying UP tail handling.

## Boundaries

No source read establishes runtime dimensions, host shifts, actual input bytes, numerical equality, or live graph origin. No assertion here covers block 65 or turns candidate Python equations into ordinary acceptance.

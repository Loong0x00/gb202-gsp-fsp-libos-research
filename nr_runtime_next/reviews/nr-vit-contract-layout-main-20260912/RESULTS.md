# Main full contract tensor lift: layout blocker resolved

## Result

The first Main source-equation prediction in `tensor_reference.py` yields the exact sealed full original-instruction CPU output: **131072/131072 FP8 bytes match**, SHA
`a9493e2a256c8dd3f465d43edf99fc18c470111115fa3d5a84f2a07e6c6b70e6`.

Inputs, weights, output oracle and original kernels were not changed. This is a full **bounded N128,4096→1024 CPU tensor operator** with real block32 weights, learned residual coefficients, explicit K32 RN-half boundaries, four1024-K partitions and ordered half reductions. It consumes the complete expand output already sealed by Main. Its logical arrays and immutable observation hooks can be inspected without DLL execution.

It is not all-shape/all-number support, an entire ViT block, a live DAG claim, native inter-CTA visibility proof, or whole-model equivalence. Finite E4M3 operands and finite half carry/reduction are the admitted domain. The stateful original-instruction reference retains counter/poll/barrier behavior; this tensor operator represents its admitted fresh-counter, ordered CPU numerical semantics, not arbitrary live scheduling.

## The actual missing relation

For a width-W tensor, let A be the consumer's packed MMA-A address map, C the producer's packed MMA-C output map. They are distinct. The source equations give, for every token m and channel k in the bounded domain:

`A(m,k,W) = C(m,pi(k),W)`

`pi(k) = 16*(k//16) + 2*((k%16)//4) + 8*((k%4)//2) + k%2`.

For example A(0,2)=byte2, while C(0,2)=byte16; byte2 in C means channel8. This permutation stays within each K32 group but is not identity. The tensor interface deliberately exposes `input_mma_axes` and `weight_mma_axes`; it does not silently relabel the input as unchanged producer axes.

**No extra repack kernel or byte shuffle was inserted into the original chain.** The same physical p0 buffer is interpreted through the consumer's own map. p8 skip uses its own C-coordinate map; coefficient n is the actual half at slab+4194304+2*n. Those were checked against actual source origins, not inferred from the term residual or a byte-range bijection.

## Independent literal checks beyond final-output matching

`check_operands.py` executes the actual original CPU stream for full four-z output groups0 and7. All arithmetic stays real and independently checked. The observer adds only shadow byte origins:

* Original bulk-copy issue addresses are queued; source origins are published **when the actual shared-memory model publishes those copies**, not prematurely at issue time.
* Raw load/move/FP8-to-half origin tracking identifies actual MMA A/B byte sources and z0 learned-skip/coefficient sources.
* Every MMA's incoming C and outgoing D is compared at raw-half precision with the independently lifted per-K32 tensor states.
* Final prequantization half values and each source store's physical byte position are checked against logical output coordinates.

Per checked group:16384 MMA A/B-origin+C checks,16384 MMA D checks,16384 learned-seed half-origin checks,16384 prequantization halves and16384 output-byte placement checks. Across both groups:32768 real MMA calls. This is stronger than final quantized-output equality, but does **not** claim that all other groups' intermediates or native GPU intermediates were separately observed. The full tensor's final output is compared across all eight groups.

The source's channel-group shift is affine in the bounded grid: r1=cx, token remainder r2=0, r5=128*cx+64*(warp%2). Input-copy coordinates are independent of cx; B group offsets, skip/output offsets, coefficients and counter cells follow their respective source strides. The first/last groups test the range endpoints; full-grid map tests establish logical and physical coverage.

## Verification and retained failure

`test_tensor_reference.py`: five tests PASS: complete maps/nonidentity edge, full131072-byte comparison, missing spans/NaNs/overflow refusal and immutable hooks, actual wrong-layout-hypothesis rejection against original byte origins, and first/last proof receipts. The intentionally wrong hypothesis uses producer C directly as consumer A; it fails at the original MMA ingress, rather than being allowed to continue or judged by a loose output tolerance.

The failed worker deleted its prototype and supplied no exact failure digest. Main records that evidence-retention shortfall in `WORKER_FAILURE.md`; no missing historical source/result was fabricated. This Main implementation and its first prediction remain separately preserved.

CPU-only, original PTX9.4 unchanged, no GPU/PE/Wine/installed/network changes. The original4h226/8192 numerical gap and remaining network stages still require work.

## Reproduce

Use `OPENBLAS_NUM_THREADS=1` and `python3 -B`:

* `tensor_reference.py` — saves the source-equation prediction.
* `check_operands.py 0` / `check_operands.py 7` — fresh original-instruction operand/origin checks.
* `test_tensor_reference.py` — model/edge/negative tests.

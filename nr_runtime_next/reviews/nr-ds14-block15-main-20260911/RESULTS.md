# Main: DS14 -> full block15 CPU composition

Main independently reran the delivered 16 DS tests and 14 8h tests, plus both frozen artifact checksum inventories. Both passed. Later write-scope audit found that the legacy test CLIs rewrite byte-identical `COVERAGE.json` files; content pins remain unchanged, but these invocations were not write-free. See `../nr-reference-test-write-audit-main-20260911/ERRATUM.md` and its confined test wrapper. Worker reports were not regenerated.

`python3 -B bridge.py` now connects these modules in isolated Python child processes (avoiding collisions between their identically named helper modules):

1. Four full original plain-DS14 CTAs operate on the same explicitly synthetic 16x16x128 input and real 229936-byte block14 slab. Each retains all four warps, 2944 MMAs and twelve 128-thread barriers. Independent pooling/projection/layout checks run on every CTA.
2. Their downstream writes are disjoint and exactly cover all 16384 bytes. No holes, implicit initialization, reshape or repack. The newly produced bytes equal the worker's frozen DS fixture, SHA256 `c04f7fe13777e13f44a32d78bcf057139eebd08b7cbf4c286451603045e181dc`.
3. Those very bytes are passed directly to the **complete original block15 inpview**, not only its first-barrier ingress. All eight warps reach ret; all eight 256-thread barriers remain. All 10240 MMAs are independently checked under the declared reference arithmetic policies. Shared producer/epoch and typed-load proofs, and independent input/output layouts, pass on this DS-produced input.
4. Complete 16384-byte block15 output SHA256: `e6bf99ed75186684288c9a969ee48b125736c941b990c07d12ec97944e9ac2c5`.
5. Deleting the last required input byte is rejected as `unproduced input`; no numerical fallback or zero fill. All pinned deliverables/helpers remain unchanged.

## Scope

This adds a **conditional CPU byte-layout and full-arithmetic composition** to the worker's first-barrier-only boundary. It does not retroactively change either worker's original synthetic-fixture claim.

The actual graph records do not supply a block15 input edge. This CPU compatibility test therefore does **not** prove a native block14->15 dependency, variant selection, shift/origin, queue readiness, or runtime argument binding. It also does not connect blocks9 through14 or blocks15 through22: intervening standard blocks are not skipped and called equivalent. No complete encoder/image/history model claim.

RN-half per k32 MMA and reference RN-FP32 RCP/RSQRT remain explicit substitutes; passing their independent CPU oracle is not native Tensor Core or approximate-instruction equality. No GPU/Wine/installed file changes.

Reports: `DS14_TESTS.log`, `BLOCK15_TESTS.log`, `PRODUCER.json`, `CONSUMER.json`, `VERIFICATION.json`. Main CPU continuation tasks now separately address block22 8hDS and block23 split16h entry; their boundaries must be independently established.

# Main literal ViT expand execution — claimed overruns disproved

## Actual bounded execution

Main executes the **unchanged original `cc_vit_1d_ffn_expand_fp8` instruction stream**, real block32/layer0 slab4194320bytes,72ABI, N0=128/N1=1, grid(32,1,1), block(32,4,1). First and last channel CTAs0/31 each reach originalret in all four warps, with **4096 nonmock FP8 MMAs independently checked against the forward-fragment oracle**. Corrected source activation constants are unchanged.

The private CPU memory model supplies input131072bytes and an output address span524288bytes; it records only actual writes, never zero-fills unknown output. It preserves all original loops, elections, copies, expectations, arrivals, polling and barriers. Only the generic parser declaration whitelist was extended from12288 to24576 shared bytes, and its already implemented mov.b16 handler was admitted. The own shared/bulk model accepts the source's512/1024 transfer forms rather than inheriting a512-only projection restriction.

Observed first-CTA results:

| region | actual bytes/support |
|---|---|
| input |128 original1024-byte transfers; all131072 bytes read |
| slab |16384 lane loads;131072 distinct bytes; maximum end4067328, within4194320 |
| shared |all24576 declared bytes, no overrun or missing producer |
| output |16384 sparse bytes, maximum end460800, no padding of holes |

Last CTA31's slab maximum is4194304. Source-derived enumeration across all32 channel CTAs covers the first4194304 matrix bytes and all524288 output bytes exactly, with no output overlap/holes. **Only CTAs0/31 were numerically executed here; full-grid numeric execution is not implied by the coverage enumeration.** The remaining16 slab bytes are retained and unread in this path.

The actual source produces16 mbarrier completions plus its initialbar.sync: bank0 six phases, bank1/2 five each, each completion8192 transaction bytes. This is a bounded CPU schedule/model, not native GPU visibility or arbitrary async-order proof.

## Why the worker preflight was wrong

The previous `nr-vit-expand-execution-20260912` remains preserved. Its purported incompatible preconditions came from its formulas, not original execution:

1. It replaced the source's masked warp offsets with raw `warp*2048`, and even used the bank remainder as an unaligned byte offset in the first shared load. Actual `r35=(warp<<11)&0x1ff000` and `r465=4*((warp<<9)&0x7fc00)` are **0,0,4096,4096**. Shared accesses remain within24576.
2. It omitted the initialB-base multiplication by4 and generated prefetch stages128..1024. Original prefetch runs only when oldk<=959; with step64 it runs at0..896 and supplies **nextK64..960**. NoK1024 load is executed.
3. It omitted the output warp mask: `r33=(warp<<1)&0x7fc` is **0,0,4,4**, not0,2,4,6. All four output row groups remain valid at N128; the claimed full-grid output holes were artificial.
4. It treated initial copies as the full input schedule and selected512-byte alternatives. Original canonical execution issues1024-byte transfers and includes later prefetches; total input support is131072, not24576.
5. Nominal serialized F16 is not a prepared-weight type proof. All actual first4MiB matrix bytes are finite E4M3 encodings in this slab; the retained16-byte tail is zero. No larger prepared allocation, record concatenation or F16 conversion was needed.

Thus the claims of requiring4329472/4456448-byte weights and26624-byte shared memory are **rejected**, not worked around with larger buffers. No original data or kernel was changed to pass.

## Tests and retained limits

`execute_reference.py` reproduces firstCTA and stores its sparse spans. `test_bounds.py`: five tests pass, including actual first/last CTA execution, exact per-warp/lane weight reads, source masks/guard checks, full-grid address coverage, and genuine rejected mutations: allowing the forbidden final prefetch causes an actual out-of-bounds read; inconsistent transaction expectation causes barrier-model rejection.

This is a real bounded expand-entry reference milestone, **not complete FFN, complete standalone model, nativeMMA/activation bit parity or real-game equivalence**. CPU policies remain explicit. Learned matrix/tensor lifting and1-D contract/repack/whole-network joins proceed separately. NoGPU, Wine, DLL/host execution, installed/config/network or sibling writes.

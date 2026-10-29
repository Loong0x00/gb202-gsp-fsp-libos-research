# Source-comparison and observer corrections

## What the ordinary loop really partitions

The source worker correctly reported ordinary slab offsets, exact F16 MMA type and fixed shared storage. Its comparison between ordinary `r4268=0,1` and the UP prefix's `0,32,64,96` loop is not a comparison of corresponding neural stages. The former streams TWO128-hidden-channel groups through the ordinary FFN; the latter is an unrelated learned upsample projection's K loop.

Main proves ordinary FFN warp ownership is32rows/warp, not the UP FFN's hidden-column ownership. Each pass interleaves four32-hidden expansion/activation chunks with the four K32 grouped-contraction steps, quantizes that group's32outputs, then immediately applies its K32 contribution to the64-output mix. The mix carries its early seed/result across the two passes. No shared ingress/group tensor exists here: the first shared barrier/checkpoint is AFTER complete FFN output. The source report is retained unchanged and not used to invent UP-like epochs.

## First FFN observer failure: missing input roundtrip metadata

FIRST_FFN_OBSERVER.py.txt and FIRST_FFN_OBSERVER.log preserve the first checker/assertion. Actual ordinary input is decoded FP8→half for retained feature/residual values, then reencoded half→FP8 for expansion operands. The first observer's generic zero-conversion branch discarded valid source-neuron labels for zero input cells, so the first expansion reported -1 labels despite correct byte/zero origins.

Only the observer was corrected: it now explicitly checks input half values, the actual FP8 conversion result, and preserves original byte/sourcezero plus neuron labels across that roundtrip. FFN_OBSERVER_RETRY.log passes. FINITE_FP8_HALF_ROUNDTRIP.json checks all254 finite E4M3 codes, including both zeros, as a bitwise roundtrip on the admitted domain; NaN codes remain refused. The original instructions are retained in the oracle. No NN arithmetic or first prediction was changed. Scalar-half and input-code result counters are recorded separately.

## Raw-observer import failure

A mechanical import replacement produced `import fixture,first`. FIRST_RAW_OBSERVER.py.txt and FIRST_RAW_NORM_TAIL_OBSERVERS.log preserve that ModuleNotFoundError, before any numerical checker ran. It was corrected to `from fixture import run,lit,first`; RAW_NORM_TAIL_RETRY.log passes. No model/VM/PTX changes.

All45CTA batches then passed, using separate block-qualified outputs in independent CPU processes. Existing complete raw/norm/tail proofs were reused only under pinned source/observer hashes; no sibling main/runner was called. First NN code/predictions and exact original4845-op PTX remain unchanged.

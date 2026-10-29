# Main source-only wait/chained recheck: pending sign and ordering correction

Current module00 slices were independently parsed and compared with worker caches: base4902/wait4979/chained5005. Every common operand maps under the checked bijections; three nonsaturating integer-add operand swaps are explicitly justified, not floating reassociation. Common-frontier CFG edges4894/4988 match; all actual wait/chained loops remain present. Main also independently derived natural backedges (0/3/3), distinct from lexical backward-edge counts, and checked2307 incoming-prefix/address cases (259 normal-grid cases plus2048 signed/wrap cases).

**Critical confirmed instructions:** waitPC130 `ld.relaxed.gpu.global.L1::no_allocate.s32`, PC131 `setp.gt.s32 value,-1`; PC134 `nanosleep.u32` with requested operand64 and backedgePC135→130. Only CTA thread(0,0,0) polls selected predecessor slots; entry barrier0 isPC65, chainedPC77. Chained outgoing barrierPC4996 precedes leader release-zero at5003 throughABI56. No acquired-value load, GPU acquire fence, membar or atomic RMW is present.

- Ready = **signed value>=0**, including0,1,INT_MAX.
- Pending for this predicate must be **signed negative**, not merely nonzero. `0x80000000` and`0xffffffff` remain pending.
- Incoming slots use currentH/W and previousX/Y at48/52; outgoing stride uses currentW/currentX. Block2(-4,-4)→previous1(0,0) and block3(-4,0)→previous2(-4,-4) have different incoming/outgoing strides. Matching predecessor dimensions/handles/slots remain external conditions.
- Producer release-zero is compatible with the consumer's state predicate and correctly matched slot addresses. This is **not an explicit matched GPU release/acquire proof**. The relaxed poll, subsequent CTA-local barrier and weak/cached data loads cannot simply be relabeled GPU acquire or CPU/system visibility. No native bug or successful visibility claim is inferred either.
- Initialization of negative pending values before consumers, reuse/ABA/epochs, late resets, aliases, consumer lifetime, convergence/launch shape, fairness and progress remain OPEN. A source nanosleep operand is not a measured timeout/duration.

This supersedes any shorthand “nonzero pending” or assumed “acquire wait” in earlier planning. The sealed block1 outgoing-only source report was conditional about zero-ready consumers; it was not a proof of this actual reader predicate. Sealed numerical/reference files were not edited.

`MAIN_REVIEW.json` / `MAIN_REVIEW_01.log` are Main's evidence; original worker reports/maps/failures remain at nr-parallel-encoder-next-main-20260912/01-wait-chain/out. No NN/original neural/kernel/GPU/DLL/Wine/network/deployment action occurred in this review.

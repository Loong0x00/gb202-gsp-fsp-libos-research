# Main OUTVIEW review and host-argument erratum

Worker retry completed14bounded reads; original report retained. Main's exact original execution and neuron/address observer now validate the output equations, selected extents and common arithmetic. Results in ../nr-swin8h-outview-main-20260912/.

Important additions/corrections:

- Common core is stronger than an opcode-form resemblance:4983 consecutive instructions (ordinary211..5193 vsoutview212..5194) match exact operands/predicates/branch targets under one unambiguous register/symbol renaming. The extra parameter load and final conversion/store path are separate; no executed PTX is rewritten.
- OUTVIEW physical plane channelk corresponds to canonical-C neuron's channelpi(k), not identical channelk. Main proves this from original final-MMA neuron tags through FP8 conversion and actual4-byte stores. Address coverage/bijection alone was not used as layout evidence.
- Worker incorrectly attributes seventh-argument outview selection to r15b and the rbx==12 operator branch. r15b is the THIRD argument r8b (068ed0), the shifted flag; that branch inserts `constant_pad_nd` (current string0x1800b8890). The SEVENTH argument is entryRSP+38=RBP+410, tested at069000. It chooses outview name prefixes0x1800ba048/ba078. At069897..0698a5 it also writes desc+84=3+2*arg7. These are distinct flags.
- Selector searches `_fp8` and `_outview`; current-byte/name witnesses confirm conditional target0x1800b9ba0 vsnonFP8b9bd0. This does not claim every live instance carries the_fp8 suffix or chooses the plain rather than wait/sync entry.
- Current-static block55 origin(0,-4) remains correct under previously proved factory/historical ordering. Main uses explicit80/84 parameters and checks positive values vsfallback, not assumed equality with input H/W.

Expanded output extents can expose computed ghost-region outputs. For inputH8 and emitted grid reachingY11, outputH12 produces8192 extra bytes in rows8..11;6708 have nonzero finite FP8 magnitude in the tested original run. One cannot merely crop/repack an ordinary already-masked global output or zero-fill expansion.

No native/live/full-model claim; all original loops/barriers/zero paths preserved. No source/weights/arithmetic altered to obtain matching predictions.

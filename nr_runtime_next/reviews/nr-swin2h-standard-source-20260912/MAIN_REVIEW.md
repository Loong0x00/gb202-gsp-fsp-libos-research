# Main ordinary2h review

Original REPORT.md retained. Its ordinary offsets/gaps, F16 MMA type and fixed shared declaration are accepted after direct original-operand verification. However, the ordinary `r4268=0,1` loop is not a corresponding version of the UP prefix K=0/32/64/96 loop: it streams two128-hidden/32-group-output channel groups through FFN, with warp ownership of32query rows. Expansion/activation/group K32 chunks and carried mix are interleaved; first shared checkpoint is AFTER FFN.

Main additionally restored actual input FP8→half→FP8 roundtrips and their source-neuron identity, including sourcezero cells. All254 finite codes, both signed zeros, and every actual runtime conversion were checked. This is not an invented shared-ingress/group path. Actual register-private loop/predicates and six original barriers remain.

`../nr-swin2h-standard-main-20260912/RESULTS.md` supplies complete45CTA/37440MMA/all270sharedboundaries and ALL45CTA original source/MMA/scalar/norm/two-phase/store proofs. Main's first roundtrip-label omission and raw-import failure are archived with observer-only corrections, no NN/prediction changes. Current-byte host proof establishes static expected63(-4,-4),64(-4,0);65OUTVIEW excluded. Eight tests, heldout25CTA and NN48–64 composition pass within non-live bounded upperinputs. No native/fullNR/standalone/live claim.

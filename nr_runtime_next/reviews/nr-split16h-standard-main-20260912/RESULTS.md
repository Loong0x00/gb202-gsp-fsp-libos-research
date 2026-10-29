# Main recovery of completed-on-disk standard Split16H delivery

The agent reported a WebSocket failure, not successful completion. Main therefore did not accept the notification as a result. Inspection found a complete local report/source/test inventory; it was archived as `DELIVERY_BEFORE_MAIN_CHECK.tar.gz` before independent review.

Main reran all published hashes and four CPU tests: pass,34.6s. This supports the delivered **bounded block24 first-two-layer raw CPU forward**, not a complete/equivalent neural model:

- Original standard FP8 FFWD layer0, own56ABI,8warps, real524288-byte block24slab.
- Original standard FP8 FFWD projection layer1, own72ABI,4warps, real263168-byte slab, separate original-input residual.
- 8x8 witness:12288 dynamic reference-policy MMAs,819200 checked half scalar operations, full recorded slab/output support and reverse-warp equality. F/P hashes retained in worker report.

Layers2/3 and actual native shift/variant/binding/readiness remain unexecuted/unproved for block24 here. Existing block23 references are not substituted with incorrect weights or assumed shifts. No full standalone-model or native-numeric equality claim; no GPU/Wine/installed changes. Worker files preserved; no restart was needed just to recover the already saved output.

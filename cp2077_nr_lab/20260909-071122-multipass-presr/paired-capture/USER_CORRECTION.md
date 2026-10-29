# User correction: compare order, not pass count

The user explicitly clarified after RESULTS.md: compare **one NR before SR** against **one NR after SR**, not one versus three NR iterations. Previous multipass image metrics do not answer that question and must not be used to rank processing order.

Requested branches at current settings:
- same 4096×2304 source → NR exactly once → signed SR → 6144×3456 final working output;
- same 4096×2304 source → signed SR → NR exactly once → 6144×3456 final working output.

A strict same-input temporal experiment needs independent SR and NR histories for the branches (or a validated identical-input sequence replay). Evaluating one shared SR history twice, comparing pre-SR 4K to post-SR 6K, or pixelwise scoring unmatched benchmark runs is not a valid substitute.

## Completed cleanup

On explicit user request, removed only this mistaken capture task's raw planes:
- captures/20260909-102619-paired-smoke-2: 0 planes;
- captures/20260909-103827-paired-smoke-2-fixed: 10 planes;
- captures/20260909-104246-paired-300: 1500 planes.

Total: 1510 files, 102,601,064,448 logical bytes (95.5546875 GiB), with zero targeted .bin files remaining. Reports, JSON metadata, CSV metrics, previews, old checksums, and source/build artifacts remain. Historical statements that raw data was retained describe the earlier completion state and are superseded by this notice. Original payload hash manifests are historical evidence, not proof that deleted files remain available. No unrelated raw archives, other games, snapshots, or user files were removed.

Receipt: RAW_CLEANUP_20260909.json.

## Evidence still usable

Existing same-settings single-pass timing runs measured NR inference at about 7.58785ms before SR versus 17.05588ms after SR. Those are separately measured GPU timings, not image quality evidence, not necessarily all-pipeline overhead, and not new tests in response to this correction.

As of this correction, no new order-comparison image capture or similarity result has been completed. An isolated architecture review is in progress under ../order-comparison/.

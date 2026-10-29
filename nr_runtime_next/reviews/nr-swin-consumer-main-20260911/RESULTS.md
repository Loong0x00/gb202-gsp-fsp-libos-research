# Main native metadata: clear + actual chained consumers

Reviewed worker's four-file delta, original ELF/PTX ABI/name↔module coupling and all 125 package pins. Main reran 17 sanitizer mock modes. Candidate DLL is **0efd06383925b2e41a9c84d38746317de89ef8907ebb93c03be6858ee58c2690**, not the ancestor DLL left in worker source/native/build. Fresh harness/source pins are in LAB_APPROVAL.json.

OFF `155436` and ON `155526` both completed with exit0/Guardian0, unchanged signed NVIDIA disk files. All five RGBA16F files match frozen 121525 byte-for-byte (`verify.py`, `VERIFICATION.json`). Scope remains private POST1 768×432, two frames, synthetic guides; fast exit after fenced output readback. No normal-teardown/game/SR/Present or visual acceptance claim. Normal reserve, public ABI and prior identity IAT path remain unchanged.

## Newly recorded—not inferred from creation

Sixteen selected-family argument records, no drop/skip/coverage gap, below the 32-attempt cap. Each frame's filtered sequence is:

1. `cc_cb_clear`, module06 hash6619…, 16-byte aggregate, grid119×1, block256.
2. preblock264.
3. block1 inpview_tilesync96.
4. block2 chained96.
5. block3 chained96.
6. block67 chained96.
7. block68 chained96.
8. finalpost184.

Other kernel families remain filtered out; adjacency in this list is not an all-kernel DAG. Weight keys above are identified from exact observed slab offsets in the proven upload table, not names alone.

Both clear records contain base `0x245e0000`, count **30464 words**, corresponding to **121856 bytes**. `base+121856` equals preblock's first ordinary output pointer. Original clear PTX/SASS specify -1; **no flag bytes were read**, so this is not a direct observation of their stored values or reset visibility.

Actual block1→block2→block3 metadata:

| Block | Origin | Incoming predecessor origin | Grid | Outgoing flag offset from workspace |
|---|---|---|---|---:|
| 1 | (0,0) | no incoming flags | 48×28 | 0 |
| 2 | (-4,-4) | (0,0) | 49×29 | 5632 |
| 3 | (-4,0) | (-4,-4) | 49×28 | 11776 |

All use H224/W384. Each data output equals the next input; each outgoing flag pointer equals the next incoming pointer. Block2 slab is pool+4512256. The two frames' filtered consumer metadata are identical. Later block67/68 reuse ordinary workspace addresses with different weight slabs: pointer equality alone does not identify a neural block or capture epoch.

The block2 shift is now captured rather than hypothetical; “shifted” still does not imply both axes -4, as block3 demonstrates. No standard wait_fp8 launch appeared within this filter; this is **not** evidence that ds/outview or other wait families did not execute.

## Proof boundary

Logs are before-original callback observations. Separately, the enclosing private submissions yielded fenced output readbacks. We have not observed per-kernel flag/data effects, actual API barrier calls, native cache visibility or stale-zero exclusion. Static release/relaxed-polling/barrier-bypass findings retain those limits. No GPU-copy command, buffer-usage change, flag inspection or activation readback was added.

The selected chained common computation is now independently certified against plain-standard arithmetic (`nr-swin-standard-variants-20260911`, eight Main-rerun tests); its polling/publication effects are not erased. Native numerical equivalence and the full image-to-image model remain incomplete.

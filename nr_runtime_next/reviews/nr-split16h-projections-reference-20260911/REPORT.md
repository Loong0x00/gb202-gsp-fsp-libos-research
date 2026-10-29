# Split16H projections — conditional CPU/static reference

## Certified scope

This review completes the two separate original FP8 projection entries with their own 72-byte ABI and CTA scheduler:

| layer | original FP8 entry | declared source roles | CTA warps | exact slab |
|---|---|---|---:|---:|
| 1 | `cc_split_swin_16h_ffwd_proj_inpview_512_fp8` | `src=layer0 F`, `skip=original V0`, `out=layer1 P` | 4 | 263,168 B, SHA256 `61bd7b37c8458f4baf1e401def0135d1887f416c8c8300cf02faa0225ebb9bbd` |
| 3 | `cc_split_swin_16h_proj_512_fp8` | `src=layer2 A`, `skip=layer1 P`, `out=layer3 Y` | 8 | 263,168 B, SHA256 `ad2ddbc077729a776267698f4cccbf23c87bc09d825902475777e2cbd3fd1b06` |

The ABI is exactly `src@0`, `skip@8`, `out@16`, `weights@24`, signed `H@32`, signed `W@36`, with bytes `40..71` poisoned/unread.  No 56/88-byte sibling ABI is accepted.  The source-derived grid is `(2*ceil(W/8), ceil(H/8), 1)`; the two x CTAs own separate 256-channel slices, rather than a single 512-channel CTA.

Each original PTX body is parsed and executed unchanged through `ret`; original branches/loops, its initial CTA barrier, mbarrier init/arrive/polling, async bulk transfers, and all nine observed synchronization epochs remain in the reference.  The local scheduler only releases a full CTA at its original `bar.sync` and rejects incomplete async state or early retirement.

The slab roles are `[0,262144)` E4M3 MMA-B bytes and `[262144,263168)` residual FP16 coefficients. The independent proof checks A and B FP8 fragments, C residual seeds/recurrences, each half multiply and FP8 quantization, packed source/output layouts, exact global slab reads, shared producer ownership, and final output bytes.  It does not use VM-computed addresses or final registers as expected output.

For the finite, isolated 8x8 synthetic witness, both x slices together per layer establish:

* 4,096 original FP8 MMAs (2,048 per CTA);
* 32,768 independently checked scalar half operations and 32,768 independently checked quantizations;
* all 32,768 output bytes, with no overlap between channel CTAs;
* all 263,168 bytes of that layer's real serialized slab, including the final coefficient bytes.

Input and residual buffers are separate finite synthetic E4M3 spans in this certified scope.  Null/overlapping pointer spans, missing bytes, wrong slab identity/size, geometry outside the bounded grid, partial warp sets, unknown route, and NaN E4M3 source bytes fail closed.

## Conditional route boundary

This is **not** a claim that the historical default host path executes these FP8 entries.  `ROUTE` requires the explicit value `conditional-fp8-nontilesync-selection-and-readiness-unproved`.  It records that host selection/readiness for the FP8 non-tilesync route remains unproved.  The reference neither treats a named operation as matmul-add nor interprets the serialized F16 container label as a dense F16 matrix.

The layer role labels follow the already documented DAG (`V0 → F → P → A → Y`), but no validated DS22/Main bridge byte capture binds `V0`, `F`, `P`, or `A` to a live allocation in this review.  The reported `1382b2fb…` 32,768-byte bridge candidate therefore remains unavailable to this API; synthetic source/skip witnesses are intentional and are not a deployment claim.

## Reproducibility and pins

Run only the confined wrapper:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B reviews/nr-split16h-projections-reference-20260911/verify.py
```

It runs four own CPU/static tests and permits writes only to this review's `TEST_RESULT.json`; it does not invoke legacy sibling test CLIs or write their `COVERAGE`/`EDGE_PROOF` artifacts. `PINS.json` hashes both source/slab artifacts and every generic helper reused for bounded VM/arithmetic semantics.  No GPU, Wine, host execution, deployment, or sibling writes are part of this result.

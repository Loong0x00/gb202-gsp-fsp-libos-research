# Original Swin2H inpview probe preparation — BLOCKED / CPU-only

**Approval remains false. Host was compiled, never invoked. No GPU/Driver API,
Wine, game/NR pool, PTX recompilation/patch, header downgrade, installed or sibling
edits.** All deliverables are inside this review.

Prepared exact original module01 SM120 ELF + exact
`cc_tinlayout_fused_swin_2h_64_2_inpview_fp8`, one CTA32×2×1,
H=W=8,origin0,overrides0. **88-byte ABI: INPUT0, OUTPUT8, SLAB16**;
H/W32/36, X/Y40/44, overrides80/84. The earlier reversed labels are rejected.

## Key findings

* Full2600-instruction SASS byte check, all97 global loads,4 global stores,
  28 shared accesses,6 barriers and7 branches inventoried.
* **Original ELF shared5120**, not PTX user4096: user shared is physically
  `[1024,5120)`. Launch dynamic shared must be **zero**.
* No textures/surfaces/atomics/flag waits/local memory. Retained two-pass learned
  loop; unreachable post-EXIT self-branch is explicitly accounted for.
* Real61760-byte block5 slab; clearly **synthetic DS-produced4096-byte input**
  from completed2h reference, not captured game activations.
* Frozen4096-byte prediction SHA256:
  `3ec96811ccf3e8feb034b6cdab773efcb3294185e1384da28de151f21563d0f6`.
  CPU rerun matched fully;832 MMAs/CTA, both warps and all six64-thread barriers.
* SASS has32 additional HFMA2 versus explicit PTX fma sites and32 fewer mul/add
  sites. **General native precision unknown**; contraction/approximation/MMA
  audit may be needed after measuring. Prediction is not retrofitted.

## Reviewable contents

| Path | Purpose |
|---|---|
| `STATIC_REVIEW.md`, `STATIC_REVIEW.json` | Complete scoped memory/control/resource review, code bounds, all sites and explicit proof limits |
| `MANIFEST.json` | Original DLL/fatbin/ELF/PTX/slab/fixture/tool/helper pins and section metadata |
| `original-module01-sm120.cubin` | Unmodified1641504-byte inner ELF carved from original DLL and matched original fatbin |
| `host.cpp`, `contract.hpp`, `fixture_pins.hpp` | Disabled Driver-only host, exact ABI and owned buffer/guard contract |
| `fixtures/` | Synthetic input, real slab, frozen prediction, zero-pointer88-byte template, guarded/poisoned4608-byte output allocation image |
| `FROZEN_REFERENCE.json`, `evidence/reference-*` | Recomputed CPU prediction, full lane-level global accesses, shared proof and12-test log |
| `prepare.py`, `static_review.py`, `freeze_reference.py` | CPU-only provenance/census/reference reproduction |
| `packing_cpu.cpp`, `test_preparation.py`, `compare_cpu.py` | Negative packing/coverage/provenance checks and future CPU-only full-output diagnostics |
| `verify_cpu.sh`, `build/` | CPU verification, current CUDA13.3-header host compilation, no host execution |
| `APPROVAL.json` | Exact Main approval/runtime/numerical blocks; cannot enable host |

## Host proposal, not an approved run

Gate is a non-CLI/non-environment constant in `contract.hpp`, checked twice before
driver loading. No execution wrapper is supplied. After **separate explicit Main
approval**, Main must record any gate change/rebuild and chosen device/run budget.
Runtime first checks SM120, loads **only the original ELF**, looks up the exact
symbol, records/validates attributes, then allocates its own input4096,
output4608, slab61760 bytes. No array/texture/surface or NR allocation exists.

The packed argument buffer passes output allocation+256; one Driver launch uses
zero dynamic shared. Readback only follows successful launch and synchronization.
Both output guards and every input/slab byte are checked, and **all4096 output
bytes** are compared to the frozen prediction. Numerical mismatch is diagnostic
exit2, API/guard/resource failure exit70. Failed drain skips individual frees and
attempts owned-context teardown; failures remain reported. No retry or fallback.
This follows Main original-finalpost's load/launch/sync/status/drained-cleanup
pattern, without its array/surface machinery.

Runtime code-path selection (ELF contains untouched Mercury sections), attribute
compatibility, launch safety, real memory behavior and numerical result remain
unmeasured. Static addresses are a complete site/family review plus enumeration,
**not an executable numerical/per-lane ingress SASS emulator**. Review this
limitation in `STATIC_REVIEW.md` before authorization.

## CPU reproduction

From project root:

```sh
bash reviews/nr-original-swin2h-probe-prep-20260911/verify_cpu.sh
```

This executes **only** the CUDA-free packing-test binary, Python CPU references,
static binary tools and host compiler. It never invokes `build/host`, even with
blocked/negative GPU CLI syntax. Tests:12 existing reference tests,7 preparation
tests,43 C++ CPU checks. Build uses `/opt/cuda/include` with
`CUDA_VERSION==13030`, no linked CUDA runtime/driver dependency.

The exact remaining approval/runtime blocks are in `APPROVAL.json`. This would
measure **plain original-kernel arithmetic only**, not native game selection,
current block5 binding/publication, concurrency, downstream consumer, or full model.

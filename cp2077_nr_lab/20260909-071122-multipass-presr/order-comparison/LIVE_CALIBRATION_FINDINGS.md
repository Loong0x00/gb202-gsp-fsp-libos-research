# Dual-SR calibration: live 6K headless gate PASSED

This is **NR-disabled calibration**, not the requested NR ordering quality result.

Verified capture: `../order-captures/20260909-124056-dual-sr-headless`.
Run/restore evidence: `../runs/20260909-124057-dual-sr-headless`.

- Gamescope headless Xwayland: current **6144×3456**, actual NVIDIA RTX5090 direct rendering and Vulkan compositor. Physical monitor is not needed. No desktop display/power settings were changed; AC auto-suspend was already `nothing`.
- Captured source IDs257/258, independent signed Feature1 IDs **1 and 2**. Both complete 6144×3456 RGBA16F planes in each pair have identical SHA256—not merely high similarity. RGB MAE/max error0, changed RGB and alpha components0, no nonfinite values. Nonconstant scene, RGB maxima100.375 and128.5.
- 2 pairs/4 planes/679,477,248 bytes. Fence-before-Map, counts, source parameter restoration, Create snapshot equality and independent resources checked. Game benchmark completed, no Xid, owned files/controls/settings/markers restored and signed DLLs unchanged.
- Complete verifier output is `CALIBRATION_VERIFICATION.json` in the capture root. It records a predeclared bit-exact RGB threshold and separately checks alpha (alpha was also exactly equal here).

## Necessary corrections discovered by actual ABI/runtime testing

1. **The Create map's Output.Subrects field is unavailable to the typed getter.** Eight required fields were observed with mask0xff, nodes1/1, input4096×2304/output6144×3456/quality2/flags75. The old policy incorrectly required0x1ff. Now allow0xff or0x1ff but compare the exact availability masks and values before/after both Creates. The original opaque map is reused unchanged; the unavailable optional field is not inserted or manufactured as a measured zero.
2. **Handle identity is not pointer identity.** NGX core copies the public handle payload: Create and Evaluate receive different addresses. Local signed SR `ad3e9c07ee864e9702032459a59c6825166766c2cb75bd0318d5626595693bdb` at Evaluate RVA0x34dd4 loads the DWORD at the handle pointer and hashes that ID to locate the feature. Store/read the actual DWORD IDs with checked ReadProcessMemory; match live pairs by ID, reject ambiguous/alias IDs. The observed IDs were1/2. Pointer tokens remain useful provenance but not instance identity.
3. **Optional PreExposure adds bit4 to the metadata float-availability mask.** The actual mask is0x1f. Requiring equality with0x0f incorrectly rejected valid source metadata. Require the four mandatory bits, and validate optional exposure when present.
4. **Native signed SR records Create and its first Evaluate on the same still-open command list.** The first invocation showed equal Create/Evaluate native list addresses, no reset/invalidation, and no prior execute acknowledgement; frame2 onward was acknowledged. The corrected rule accepts either an acknowledged Create or an explicitly tracked pending Create earlier on the exact same unreset native list. It does not assert that command recording is GPU execution. The full-list later Present fence still must finish before Map. This exception is specific to observed native SR recording; do not apply it blindly to Feature18 NR creation.
5. Early failure diagnostics must survive an incomplete Create gate. Abort-only provenance now retains actual snapshots without authorizing any frame. Normal successful frame validation remains strict.

All prior diagnostic failures produced0 raw pairs and restored production. Do not call those failed initialization/ABI probes successful image comparisons.

## Virtual display probing caveat

The first3-second empty Gamescope probe exited139 with a CPU `gamescope-shdr`/NVIDIA shader-compiler teardown fault, no GPU Xid. A20-second held probe exited0, and the subsequent real90-second headless game/restore run exited normally. Do not describe the first probe as clean or conflate a compositor teardown fault with NR inference. Logs remain under `../display-probes/`.

## Next experiment

The verified source/binaries were frozen at `../order-calibration-verified-20260909-124056` before NR integration. Actual one-pass NR-before-SR versus one-pass NR-after-SR work is isolated under `../full-order/`; that work is not yet a completed quality measurement.

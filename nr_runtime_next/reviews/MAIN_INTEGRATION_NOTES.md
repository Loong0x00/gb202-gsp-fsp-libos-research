# Main integration notes (pending candidates)

- Main `native/` is currently pc3b, not the original pc3 review tree: verified_effective_passes in common/control.h + telemetry publication + tests/build ID prevent pending requests from inventing active layer counts.
- WuWa first candidate is NOT merged; followup worker fixes probe budget guarding, per-frame allocation double charge and actual-game PID selection. Rebase against pc3b, preserve those publication changes.
- Loader-hardening first patch is NOT merged. CP main factory import is proven; WuWa EXE has no D3D12CreateDevice import. Followup adds queue observation through owned DXGI factory CreateSwapChain methods, avoiding unsupported/protected main-module lookup assumptions.
- HSR candidate is NOT deployed/linked into main. Followup fixes the bidirectional-fence/global-shared-texture race and CPU waits, plus external post commit/view attestation. See HSR_TRANSPORT_MAIN_REVIEW.md.
- FormatBridge library HAS changed after initial candidates: MV shader now explicitly f16tof32(f32tof16); seven actual GPU data cases pass; Vulkan core/sync clean with WSI disabled for the offscreen harness only. Relink all consumers. D3D12 debug layer remains unavailable and strict harness exit1 is retained, not a full debug-layer pass.

## Packaging after linking external adapters

Current native/tools/source_manifest.py hashes native/ + frozen protocol only.
Once WuWa/FormatBridge source is linked, extend it to the actual transitive owned
adapter/format source inputs (including generated DXBC), not build directories.
Do not publish a source manifest that omits linked external code.

The parent native Makefile must force the FormatBridge submake/dependency check
before compiling/linking the host, even when libnr_format_bridge.a already
exists. A file-exists-only rule can link stale shader/library bytes while
recording newer source hashes. Verify clean/incremental behavior and freeze
source/artifact manifests before cold tests.

Only an exact-DLL-matching completed GPU run may supply installation capabilities.
Do not copy an old active status. CP original 6K DLAA still trips the conservative
budget guard; no silent game-quality change or permanent migration has occurred.

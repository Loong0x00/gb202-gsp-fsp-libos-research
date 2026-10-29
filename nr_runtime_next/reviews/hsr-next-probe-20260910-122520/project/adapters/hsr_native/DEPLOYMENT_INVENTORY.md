# Read-only candidate/deployment inventory

No file listed below was installed, renamed, removed, or restored by this worker.
Main owns cold deployment, process watching, deployment backup creation, and
rollback. This source candidate remains blocked on the current host's missing
external-POST commit export, Guardian publisher, observed HSR view contract, and
GPU acceptance; these hashes are not deployment authorization.

## Candidate-owned filenames

Build outputs (never copy while StarRail is running):

```text
adapters/hsr_native/build/NVUnityPlugin.hsr-native-candidate.dll
adapters/hsr_native/build/dlss5-hsr-format-bridge.dll
```

Clean cross-compile hashes for this scoped handoff:

| candidate | SHA-256 |
|---|---|
| `NVUnityPlugin.hsr-native-candidate.dll` | `5e5c245e1162e7eb0a776982f593c34fcde846db0a5d3c685d822c8482db3121` |
| `dlss5-hsr-format-bridge.dll` | `04aac6e84149860ec619deeae814839a960fa1f4e4a34b1e342fb3e91f65f10f` |

A reviewed cold layout would use:

```text
HSR/StarRail_Data/Plugins/x86_64/NVUnityPlugin.dll       # candidate target
HSR/StarRail_Data/Plugins/x86_64/NVUnityPlugin.real.dll  # retained package original
HSR/dlss5-hsr-format-bridge.dll                          # late owned converter
HSR/dlss5-native-host.dll                                # late owned host
HSR/dlss5-native-runtime.dll                             # host-owned runtime
```

Do **not** install native `dxgi.dll` for HSR. The old
`HSR/01-dlss5-post-service.dll` must be backed up and removed in the same cold
transaction; the new route has no service discovery, ReShade file, add-on, or
separate order/layer manager. This document is not authorization to perform that
transaction.

## Retained real and observed installed hashes

Read-only snapshot of the currently installed HSR files used by the prior
evidence inventory:

| path | SHA-256 |
|---|---|
| `HSR/StarRail.exe` | `829581f61694a2c2fa64ff6c1292ac18b876a1359241e1a5d1530c7768bd0258` |
| `HSR/StarRail_Data/Plugins/x86_64/NVUnityPlugin.dll` (current slot-8 router) | `ff680caea4c5bca23833b569e27f27cec77b1e2630dff675b3d109725cebf425` |
| `.../NVUnityPlugin.real.dll` (package original retained by candidate) | `a1db4a529bbc06fa3e0aefb61f95e97851b401633e5cf55a8f0f92640324f98a` |
| `.../nvngx_dlss.dll` | `ba685453f689201997db726fb0d904e969bdd148ea9a58a56ba5c1ead86eeaf9` |
| `HSR/nvngx_dlssnr.dll` | `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` |
| `HSR/01-dlss5-post-service.dll` (legacy removal target) | `c26c45e8a223109807beb3b23225969b7ef07be03eea58161a509997d140d965` |

A PE security directory was previously observed for the retained signed files;
that is not itself signature validation. The external lease must not set
`signed_game_path=intact` or `native_build_attested=1` until main has performed
its real signature/hash/layout checks.

The old live router log did not capture an NGX application ID. This source does
not hardcode one: it captures the real numeric argument after original core Init
success. A Project-ID-only path remains closed unless native ABI ownership is
reviewed; launcher/Steam IDs are not substitutes.

## Source provenance copied into this directory

The forwarding inventory is a byte-for-byte copy from the proven lab proxy:

| source | SHA-256 |
|---|---|
| `/home/user/rt_5090_project/hsr_dlss5_lab/hsr_nvunity_iat_router.cpp` (design basis, not copied verbatim) | `caf770013323f54f64b0f485cfd26b14022f07d6328900a24f4fd152d4130385` |
| `hsr_dlss5_lab/nvunity_proxy/generated/export_list.inc` | `1a091601ad1d23cc218ceb83dced302372bde22f82e57b5e5b318c95929910e9` |
| `hsr_dlss5_lab/nvunity_proxy/generated/exports.S` | `54c0fef44992b7139e2a7b635386f29faef3db2958deaabf65fea69f5f76f52e` |
| `hsr_dlss5_lab/nvunity_proxy/generated/proxy.def` | `75e0bc40bbfe215346aaf0b22700c48698da2ebbc3b60aebd3b6674429480fca` |
| `hsr_dlss5_lab/nvunity_proxy/nvunity_proxy.cpp` (forwarding design reference) | `b37802cc51863fd808f6ecd3ff9c8e38c89bdc7220dd62c9ad96150e6bb7998a` |

`SOURCE_SHA256SUMS` freezes the new scoped source files after this implementation.
Candidate binary hashes are recorded in `CANDIDATE_SHA256SUMS` after a clean
cross-compile. `FORMAT_INPUT_SHA256SUMS` records the exact separately owned
`adapters/format_bridge` sources consumed by this helper build; main must still
reconcile them with that worker's accepted manifest.

## Existing exact rollback references

Current router -> prior slot-8 backup:

```text
/home/user/.local/share/honkers-railway-launcher/HSR/.dlss5-hsr/backups/20260902-002200-nvunity-slot8-v2/restore.sh
SHA-256 a1179c236870fda2ab7aa910032942b27c0bb9034253b76cda9361e203973785
```

Pure packaged NVUnity restore:

```text
/home/user/.local/share/honkers-railway-launcher/HSR/.dlss5-hsr/backups/20260902-001000-nvunity-iat-router/restore.sh
SHA-256 1d7807056a071ad2c12270a8c0aed8688e17d87159da363fc4dfd3660bfd7bf2
expected restored NVUnity SHA-256 a1db4a529bbc06fa3e0aefb61f95e97851b401633e5cf55a8f0f92640324f98a
```

Those scripts predate the new host/format files. Main must make a fresh backup
covering every target above and the complete old service/ReShade layout before
any cold change; do not extend an old restore script in place.

# Read-only installed-state and rollback inventory

Observed 2026-09-10T05:10:35+08:00. Commands were read-only (`find`, `stat`,
`file`, `sha256sum`, `md5sum`, `objdump`, `strings`, `grep`). No launcher,
desktop, systemd, anti-cheat, game config, or live DLL was modified.

## Profile resolution

`/home/user/.config/dlss5-linux/profiles.json` contains exactly the relevant
existing profiles:

- lines 5-40: **赛博朋克 2077**, executable
  `.../Cyberpunk 2077/bin/x64/Cyberpunk2077.exe`;
- lines 42-77: **wuwa**, executable
  `.../Wuthering Waves/Client/Binaries/Win64/Client-Win64-Shipping.exe`, Steam
  app 3513350;
- lines 79-114: **崩坏：星穹铁道**, executable
  `/home/user/.local/share/honkers-railway-launcher/HSR/StarRail.exe`, Wine
  prefix `/home/user/.local/share/honkers-railway-launcher/prefix`.

Only wuwa and HSR adapters are present here. CP2077 and all other games are
unchanged.

Read-only input source hashes used for this port:

| source | SHA-256 |
|---|---|
| `dlss_ngx_proxy/src/router_addon.cpp` | `5a513853f47852423387cc21d8f35e7509bd111b059f6a5a61b5cce8a8c94456` |
| `dlss5_vk_bridge/wuwa_phase_gate.py` | `72107467d683a285c41b773bce5df00052e9930e0545cf020eb5ba75079e0033` |
| `hsr_dlss5_lab/hsr_nvunity_iat_router.cpp` | `caf770013323f54f64b0f485cfd26b14022f07d6328900a24f4fd152d4130385` |
| `hsr_dlss5_lab/Makefile.nvunity-iat` | `d6cfde74f7b7fa3bf4ec6d53b7e067946ef01f84e5fc3c276b40fe8885e53eb1` |
| `hsr_dlss5_lab/nvunity_proxy/nvunity_proxy.cpp` | `b37802cc51863fd808f6ecd3ff9c8e38c89bdc7220dd62c9ad96150e6bb7998a` |
| `hsr_dlss5_lab/nvunity_proxy/Makefile` | `01c5ece1cd5a715bc5e6836ca1cddf9c151d9687eeb2657b5004ae57937a967f` |
| `astral_pin_monitor/astral_hsr_guard.py` | `8947300c02c179db59343038086be52175b59847b2b7f9eddd971af3118fc413` |

## Wuthering Waves

Steam manifest `/home/user/.local/share/Steam/steamapps/appmanifest_3513350.acf`
identifies `Wuthering Waves`, build ID `24626793`. Current installed hashes:

| file | SHA-256 |
|---|---|
| `Client/Binaries/Win64/Client-Win64-Shipping.exe` | `a6cdb83f6f2909b5a13ca19b1d5ff4f0455f743e8fabf40bb07546500968cdfa` |
| `Engine/Plugins/Runtime/Nvidia/DLSS/Binaries/ThirdParty/Win64/nvngx_dlss.dll` | `22c4660249da5b352cde0ce4d95178c3761223dd6ac096d0b88e5c03d7a5cdd1` |
| same directory, `nvngx_dlssd.dll` | `50eb21e654a1fd12403e000f5ac9c2488bf9149930c028e73196f3f1d47d10a9` |
| `Client/Binaries/Win64/00-dlss-ngx-router.addon64` | `65be255fc529f18c7751666360f4748a743198f21fa7d17f3a757a295ec043ad` |
| `Client/Binaries/Win64/01-dlss5-post-service.addon64` | `6e1621581aa2a1a81b422a5870c07ed326a32299d4c1b2a098a1c8af42d29210` |
| `Client/Binaries/Win64/dxgi.dll` | `b85441eb50ee35b36e593990f53c5f286c867eec5b1a95401ef4329866221238` |
| `Client/Binaries/Win64/nvngx_dlssnr.dll` | `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` |

The active DLSS and DLSSD hashes match their retained `dlss-proxy-real/sr` and
`dlss-proxy-real/rr` copies. `objdump -x` reports nonempty PE Security Directory
entries for both (`0x343b400/0x2870` and `0x1b41a00/0x2870`). This records
embedded-signature presence, not cryptographic trust validation.

Current `dlss-ngx-router.jsonl:8-14` shows D3D12 DLSSD Feature 13 create/evaluate
success and coherent RR Color/Output/MV/depth pointers. Archived ordinary-SR
evidence at
`benchmark_logs/wuwa-startup-phase-gate-20260903-044944/dlss-ngx-router.before.jsonl:8-15`
shows successful D3D12 DLSS Feature 1 Create/Evaluate. Archived frame evidence
at
`/home/user/rt_5090_project/benchmark_logs/wuwa-native-replay-75-pre-event-20260903-121233/dlss-ngx-frames.jsonl:1`
records render `4099x2306`, padded Color `4100x2308`, output `6144x3456`, and
exact-render MV/depth. Formats are Color/Output/MV/depth `10/26/34/41`. That is
why the adapter does not assume Color extent is identical to the render subrect
or advertise the current native format path as ready.

**Existing owned load/gate point:** the old router is a ReShade add-on in the EXE
directory and is enabled only by
`Client/Binaries/Win64/.dlss-ngx-router/enable-dlss5`; the phase watcher removes
that marker at startup and creates it after login settle. The new adapter has no
ReShade dependency. Native deployment must snapshot/remove the entire old
ReShade host only after its own safe NGX/queue path is validated; this audit did
not touch it.

**Known stable state/rollback evidence:**
`/home/user/rt_5090_project/dlss5_vk_bridge/nr-restore-deployments/20260904-010212-restore-stable-nr/README.md:1-9`
and `SHA256SUMS:1-17`. The currently installed router/service hashes equal the
stable hashes on README lines 3-4. `restore-native-replay.sh` is a rollback to the
pre-cleanup capture components, not a clean-native deployment recipe. A future
native deployment must create its own exact pre-deployment rollback and refuse
while `Client-Win64-Shipping.exe` runs.

## Honkai: Star Rail

Installed game identity:

- `HSR/.version:1` = `4.5.0`;
- `HSR/StarRail_Data/app.info:1-2` = `Cognosphere` / `Star Rail`;
- `HSR/pkg_version:58-59` names `nvngx_dlss.dll` and `NVUnityPlugin.dll` with
  packaged MD5 values;
- the configured executable is `HSR/StarRail.exe` (PE32+ x86-64); active graphics
  evidence is D3D11, not an assumed D3D12 seam.

Current installed hashes:

| file | SHA-256 | package/observed MD5 where relevant |
|---|---|---|
| `HSR/StarRail.exe` | `829581f61694a2c2fa64ff6c1292ac18b876a1359241e1a5d1530c7768bd0258` | package `3112c65df9cf6ff3e11c8df022320189` |
| `HSR/StarRail_Data/Plugins/x86_64/NVUnityPlugin.dll` (owned IAT router) | `ff680caea4c5bca23833b569e27f27cec77b1e2630dff675b3d109725cebf425` | `43488fd53b774a0a164db3ae94a6f674` |
| `.../NVUnityPlugin.real.dll` (retained packaged original) | `a1db4a529bbc06fa3e0aefb61f95e97851b401633e5cf55a8f0f92640324f98a` | package match `b492cfbcc1d4dd4f7f92197b9d4f9d33` |
| `.../nvngx_dlss.dll` | `ba685453f689201997db726fb0d904e969bdd148ea9a58a56ba5c1ead86eeaf9` | package match `12627ab9ee39858b6a28039a32d1b7c2` |
| `HSR/nvngx_dlssnr.dll` | `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e` | — |
| `HSR/HoYoKProtect.sys` | `3f2803ff2dd12d134fd3b4e37708c510a1fac4b0503b091b73b80ddf7e857732` | package match `cb4a0060c4656a0f849913a43ce8cf36` |
| `HSR/mhypbase.dll` | `f8ad6b077ff4368cdb4f34114453c7b3da92537ee27a0240a56111dab0016dde` | package match `a1fcf04a8e59a672c5e4127bd9f006fa` |

`objdump -x` reports nonempty PE Security Directories in the retained original
NVUnity, NVIDIA DLSS/NR, HoYoKProtect, and mhypbase files. Again, that is
signature-presence evidence only. No signed file or protection component was
changed.

**Actual feature/API evidence:**
`HSR/StarRail_Data/Plugins/x86_64/hsr-dlss5-router.jsonl:1-17` records 68/68 real
NVUnity exports resolved, D3D11 NGX Create/Evaluate/Release resolution, successful
Feature 1 Create (`4096x2304 -> 6144x3456`), parameter slot 8, output format 26 at
output extent, MV format 33 and depth format 19 at render extent, followed by
successful post execution. Its Output/MV/depth formats are `26/33/19`. It does
not evidence RR or a live D3D12 render seam, and that old router did not acquire
the pre-SR Color contract. HSR `pre_sr`
therefore remains backend-unready/unadvertised until native extracts and validates
that real resource seam.

**Safe owned load/gate point:** retain the NVUnity IAT forwarding path and its
packaged `NVUnityPlugin.real.dll`; do not move the renderer host to process
startup. The established route discovers/loads the renderer only inside a
successful signed DLSS Evaluate (`hsr_nvunity_iat_router.cpp:163-203`). Guardian
must be armed before launch and keeps independent kill-on-trip/I2C-loss behavior.
Its phase lease opens only after `_OnLoadingFinish` plus settle and closes on
loading/restart/log/parser failures. Nothing in this adapter hides a proxy or
weakens Jadeite/HoYoProtect.

**Rollback targets:**

- Current slot-8 router back to prior router:
  `HSR/.dlss5-hsr/backups/20260902-002200-nvunity-slot8-v2/restore.sh` (refuses
  while StarRail runs).
- Pure packaged NVUnity restore:
  `HSR/.dlss5-hsr/backups/20260902-001000-nvunity-iat-router/restore.sh:1-17`;
  expected restored SHA-256 is
  `a1db4a529bbc06fa3e0aefb61f95e97851b401633e5cf55a8f0f92640324f98a`.

These are read-only inventory references. Deployment/rollback remains with the
native owner after policy, code-signing, Guardian, and game validation.

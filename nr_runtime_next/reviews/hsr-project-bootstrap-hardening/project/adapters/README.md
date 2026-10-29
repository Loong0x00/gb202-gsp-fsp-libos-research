# Native NR game adapters

This subtree contains CPU-only evidence normalization, phase state machines, and
eligibility policy for **Wuthering Waves** and **Honkai: Star Rail**. It contains
no renderer, DLL loader, injection path, NGX Create/Evaluate stub, deployment
script, game-setting writer, or ReShade dependency. The frozen request/status
wire contract remains [`../protocol/PIPELINE_V1.md`](../protocol/PIPELINE_V1.md).

## What is implemented

- `common/frame_contract.h`: adapter-owned ABI v1 normalized frame/safety/backend
  evidence (240/56/64 bytes). Opaque resource IDs are never dereferenced here.
- `common/policy.*`: fail-closed ordering, resource-generation/extent checks,
  independent-layer and ping-pong capacity, mandatory budget preflight, reset and
  resolution history, and distinct `unsupported`, `budget_exceeded`,
  `gate_closed`, `disabled`, and `error` outcomes.
- `common/native_contract_bridge.*`: compiled, field-by-field conversion to the
  native owner's current Attach/Gate/RawFrame ABI; it builds values but never
  loads a module or calls native exports.
- `wuthering_waves/`: D3D12 Feature 1/13 topology and the login-time phase gate.
- `honkai_star_rail/`: observed D3D11 Feature 1 topology and the new-data-only
  Player.log phase event state machine. HSR additionally requires a live
  Guardian lease and attested late load path.
- `tests/test_policy.cpp`: fake NGX feature/resource events plus phase, loading,
  reset, resolution-change, multi-layer, budget, Guardian, and backend fixtures.

`DecisionStatus::dispatch` means only “eligible to attempt.” It is **not** the
frozen runtime `active` state. Only the native worker may publish `active`, and
only after all requested independent NR evaluations actually succeed.

## Evidence-based game topology

| game | observed live reconstruction seam | adapter behavior |
|---|---|---|
| Wuthering Waves | D3D12 `nvngx_dlssd.dll`, Feature 13 (RR) in the current mode | `post` may follow a successful signed RR evaluate. `pre_sr` is rejected and NR is bypassed; noisy RR Color is never used as NR input. |
| Wuthering Waves ordinary-SR mode | D3D12 `nvngx_dlss.dll`, Feature 1 role is separately routed | Feature 1 is the only Wuthering Waves topology eligible for `pre_sr`. The adapter never changes RR, ray-tracing, or game mode settings. |
| Honkai: Star Rail 4.5.0 | Unity/NVUnity resolves D3D11 NGX; live Create is Feature 1 and `4096x2304 -> 6144x3456` Output/MV/depth were read at parameter slot 8 | Ordinary SR only. No RR or D3D12 active-game path is claimed. `post` is eligible after successful signed Evaluate. The old evidence did not capture pre-Color; `pre_sr` stays unadvertised unless native later extracts it and attests a real pre-Evaluate D3D11 binding. |

Primary evidence locations and exact source lines:

- Wuthering Waves role classification and real D3D12 exports:
  `/home/user/rt_5090_project/dlss_ngx_proxy/src/router_addon.cpp:721-750`.
- Wuthering Waves post placement and reset/settle behavior:
  `router_addon.cpp:528-619`; current RR Feature 13 live evidence is
  `.../Wuthering Waves/Client/Binaries/Win64/dlss-ngx-router.jsonl:8-14`.
  A successful ordinary-SR Feature 1 Create/Evaluate is recorded at
  `/home/user/rt_5090_project/benchmark_logs/wuwa-startup-phase-gate-20260903-044944/dlss-ngx-router.before.jsonl:8-15`.
- Wuthering Waves fail-closed login transition state machine:
  `/home/user/rt_5090_project/dlss5_vk_bridge/wuwa_phase_gate.py:102-157`.
- HSR D3D11 ABI declarations and parameter getter slot 8 evidence:
  `/home/user/rt_5090_project/hsr_dlss5_lab/hsr_nvunity_iat_router.cpp:38-47,124-149`.
- HSR real D3D11 resolution interception:
  `hsr_nvunity_iat_router.cpp:668-692`; late service rule:
  `hsr_nvunity_iat_router.cpp:163-203`; NVUnity IAT forwarding/bootstrap:
  `hsr_nvunity_iat_router.cpp:753-798`.
- Installed HSR live log:
  `/home/user/.local/share/honkers-railway-launcher/HSR/StarRail_Data/Plugins/x86_64/hsr-dlss5-router.jsonl:1-17`
  (68 NVUnity exports, D3D11 Create/Evaluate/Release, Feature 1, slot 8,
  coherent output/MV/depth, and successful original/post results).
- HSR Guardian arm-before-launch and fail-closed monitor:
  `/home/user/rt_5090_project/astral_pin_monitor/astral_hsr_guard.py:420-456,474-484,521-586`;
  phase parser: `astral_hsr_guard.py:298-401`.

The source/log facts establish call topology, not native-host compatibility or
multi-NR GPU correctness. See [`evidence/INVENTORY.md`](evidence/INVENTORY.md).

## Deliberately blocked / not claimed

- No live DLL, launcher, desktop, systemd, game setting, Guardian, or anti-cheat
  configuration was changed; removal/deployment of the old host remains native
  owner work after validation and rollback capture.
- Neither adapter can advertise against the current runtime until the evidenced
  format mismatch is resolved and `format_conversion_ready` is attested.
- HSR additionally lacks a validated native D3D11-to-D3D12 binding, captured
  pre-SR Color contract, and evidenced NGX application ID. Its NVUnity late path
  and Guardian lease remain mandatory.
- CPU tests do not establish GPU, game, Wine, anti-cheat, performance, or
  multi-pass compatibility.

## Build and CPU tests

```bash
make -C adapters
make -C adapters test
```

The build emits `adapters/build/libnr_game_adapters.a` and the CPU-only test
binary. No GPU, game, Wine, network, or deployment operation is performed.

## Capability and pass-count rules

`capabilities_for()` returns unavailable until the native runtime build and
adapter binding are attested. The advertised UI maximum is:

```
min(10, independent_history_capacity, ping_pong_layer_capacity)
```

An order is exposed only when its real native dispatch is ready. Both game
contracts also require an attested format-conversion path: observed Wuthering
Waves and HSR guides/output do not match the current native validator's accepted
formats (details in `NATIVE_BOUNDARY.md`). Per-frame VRAM preflight is additional:
an unknown estimate or a request above the guarded
frame budget yields `budget_exceeded`, never an OOM capability probe. Every pass
must have its own handle/history; repeated use of one temporal handle is outside
this contract.

Native integration requirements are in
[`NATIVE_BOUNDARY.md`](NATIVE_BOUNDARY.md). The native common header appeared and
its size assertions were corrected while this work was in progress, so the
adapter library now compiles directly against it. No capabilities JSON is
shipped from this adapter-only contribution, because a real backend has not been
integrated or GPU-validated here.

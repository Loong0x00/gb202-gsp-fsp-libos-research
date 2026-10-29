# Native host boundary (adapter ABI v1)

`common/frame_contract.h` was created as the temporary normalized seam before
`native/include/native_adapter.h` appeared. During coordination the native owner
corrected its C++ size assertions to the declared 200-byte `D5nRawFrameV1` and
216-byte `D5nRawFrameResultV1`. `common/native_contract_bridge.*` now includes
that header directly, repeats those assertions deliberately, and performs an
explicit field-by-field build of native Attach/Gate/RawFrame values. It never
calls the exports.

There is no reinterpret-cast between contracts. The adapter game enum values
differ from native values (WuWa/HSR are 1/2 here and 2/3 in native), so the bridge
maps them explicitly. Resource pointers are supplied separately with matching
opaque evidence IDs; this permits an owned HSR interop conversion without
pretending a D3D11 pointer is D3D12.

## Bootstrap requirements

The native host must satisfy all of these before setting the corresponding
attestations:

1. Preserve NVIDIA/game signed files and verify the expected owned deployment
   layout. A PE security directory or filename alone is not signature proof.
2. Preserve the game's original Create/Evaluate/Release results and call the
   original game path exactly once. Adapter bypass or NR failure must leave the
   game image and result unchanged.
3. Do not load early, conceal a proxy, disable ACE/HoYoProtect/Jadeite, or alter
   anti-cheat configuration. `PolicyPermission::permitted` is an external policy
   decision, not something this adapter can infer or grant.
4. Wuthering Waves must unconditionally close/remove any prior enable lease
   before watching, then consume the established phase state. Missing DB
   evidence/watcher heartbeat is closed. A same-process login update closes the
   gate and starts a fresh settle. Forward the state machine's nonzero,
   monotonically increasing generation; never reuse an old open lease.
5. HSR must retain the existing NVUnity IAT late route: Guardian is armed before
   launch; only new `Player.log` bytes are watched; loading/error/log replacement
   or parser failure closes the phase gate; the renderer path is not made
   available until NGX is loaded and a signed Feature 1 Evaluate has succeeded.
   Missing/stale Guardian lease or combined gate generation closes NR. Guardian
   trip/monitor failure retains its independent kill behavior; the adapter is
   not a replacement for it.
6. Maintain one combined, nonzero `gate_generation` per adapter and increment it
   before every externally visible open/close transition, including Guardian,
   integrity, anti-cheat-policy, and late-path changes—not only phase-parser
   changes. Native rejection of a stale/non-increasing generation stays closed.
7. `runtime_build_attested`, `adapter_binding_ready`, format conversion, and
   order readiness mean a real native runtime/queue binding exists. A symbol,
   configuration file, or CPU test is insufficient.

The adapter never self-loads and has no ReShade registration/discovery code.
Removal and deployment of the old live host are owned by the native worker and
must remain rollback-safe.

## NGX evidence normalization

The host retains library role and feature ID on each successfully created NGX
handle and supplies them on Evaluate:

- Wuthering Waves: D3D12 `dlss + Feature 1 -> ordinary_sr`;
  `dlssd + Feature 13 -> ray_reconstruction`. Other combinations normalize to
  unknown. Current game evidence is Feature 13 RR.
- HSR: only observed D3D11 `dlss + Feature 1 -> ordinary_sr`. D3D12, DLSSD, and
  other IDs normalize to unknown even though the NVUnity binary contains code
  strings for more than one graphics API.

The audited HSR router/logs do not record the NGX application ID. Capture the
actual nonzero value from the game's real NGX initialization path before Attach;
do not substitute the blank launcher profile/Steam ID or guess a value.
`build_native_attach()` rejects zero for this reason.

For `post`, call policy after the original Evaluate succeeds and map signed
`Output` to `reconstructed_color`. For `pre_sr`, call policy before original
ordinary-SR Evaluate and map game `Color` to `source_color`; HSR also requires a
successful signed Evaluate from an earlier late-safe frame. Never invoke
`pre_sr` around Feature 13 RR.

Every resource carries a nonzero opaque native ID, frame resource-generation,
extent, format, and sample count. Base coordinates plus the active render extent
must fit inside Color/MV/depth; HSR requires origin-zero exact guides, while WuWa
may explicitly provide padded guides. Post color is origin-zero at output
extent. Pre Color may be padded but must cover the render subrect (observed
Wuthering Waves Color can be `4100x2308` for a `4099x2306` render subrect). A
generation mismatch is stale evidence and bypasses with `error`.

The current native raw ingress contains D3D12 pointers only. HSR's observed seam
is D3D11, so the native owner must provide and validate its D3D11-to-D3D12
ownership, fence, state, and same-frame identity conversion before either order
is marked ready. The old experimental transport and a CPU policy decision are
not such an attestation.

WuWa also cannot pass the observed resources straight through to the current
runtime validator. Evidence records Output/MV/depth DXGI format numbers
`26/34/41` (R11G11B10_FLOAT, R16G16_FLOAT, R32_FLOAT), while HSR records
`26/33/19`. `native/runtime/pipeline.cpp:118-123` currently requires
source/MV/depth `10/10/39` (R16G16B16A16_FLOAT twice and R32_TYPELESS) before it
copies subrects. Pre-SR WuWa Color itself is format 10, but its guides still do
not match. The bridge therefore supports separately owned converted bindings,
and both game contracts require `format_conversion_ready`. Keep it false—and
capabilities unavailable—until native conversion/acceptance is implemented and
validated for all three resources. A matching opaque evidence ID ties each
converted binding to the source frame; it is not format proof by itself. For
post, a converted working/output surface also requires one final, synchronized
format-aware copy/composition back to the original game Output before an
`output_committed` acknowledgement. The bridge does not perform or claim that
copy.

## Dispatch requirements

A `dispatch_pre_sr` plan requires scratch output. Never overwrite game Color in
place before NR succeeds. If any NR layer fails, submit the original SR Evaluate
with the original Color/parameters. On success, feed the final scratch color to
ordinary SR without changing the selected game reconstruction mode.

A `dispatch_post` plan starts only after successful game SR/RR. Failure preserves
that signed output for presentation.

For N passes:

- own N independent NR feature handles and N temporal histories;
- ping-pong through bounded scratch surfaces; do not evaluate one handle N times;
- use the one coherent frame's color/MV/depth metadata for all layers;
- propagate reset to every layer; and
- compose to the game/presentation target only after the final successful layer.

`HistoryState` is transactional. Commit a bypass decision's `next_history`
immediately. Commit a dispatch decision's state only after all N layers succeed;
on partial failure retain the previous state, invalidate/repair partial native
history as needed, and preserve the game image. Resolution changes and explicit
Reset close the affected frame. Wuthering Waves also closes one settle frame,
then requests reset on all independent NR histories.

Queue/list ownership, barriers, fences, descriptor lifetime, and deferred release
are native responsibilities. ReShade event numbers and private unwrapping UUIDs
are not valid execution acknowledgement.

## Frozen protocol/status mapping

Read and validate D5RP with the frozen `protocol/pipeline_v1.h`; order and pass
count are process-latched as documented. Adapter decisions map as follows:

| adapter status | worker status before execution |
|---|---|
| `disabled` | `disabled` |
| `unsupported` | `unsupported` |
| `gate_closed` | `gate_closed` |
| `budget_exceeded` | `budget_exceeded` |
| `error` | `error` |
| `dispatch` | not yet `active`; publish `active` only after successful real execution |

The worker must atomically write a fresh status heartbeat with exact sequence,
requested/effective order and pass count, reconstruction (`sr`/`rr`), reason, and
actual NR call/layer diagnostics. RR + `pre_sr` stays `unsupported` with zero NR
calls; it is never silently moved to post. A pending cold request stays
`pending_restart` and must not be relabeled.

Install `pipeline-capabilities.json` only when `capabilities_for().installable`
is true for the same attested build. Expose only returned orders and
`max_nr_passes`; phase/budget do not fabricate static capability, and adapter
source alone advertises nothing.

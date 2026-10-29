# Native adapter ABI v1

Adapters include `native/include/native_adapter.h` and locate exports on the already loaded exact module `dlss5-native-host.dll`. No add-on discovery, INI file, event framework, private unwrap IID, or NVIDIA filename replacement is part of the ABI.

## Attach

Call `DLSS5_NativeAdapterAttachV1` once outside `DllMain`. Supply a stable non-null identity, a verified NGX application ID, and only capabilities the adapter actually extracts:

- `D5N_ADAPTER_SUPPORTS_POST_V1` is mandatory;
- `D5N_ADAPTER_SUPPORTS_PRE_FEATURE1_V1` means the adapter has an ordinary signed Feature 1 pre boundary;
- `D5N_ADAPTER_SUPPORTS_RR_FEATURE13_V1` means Feature 13 RR is identified;
- `D5N_ADAPTER_PROVIDES_PADDED_GUIDES_V1` is informational; the runtime still copies active guide subrects to owned origin-zero resources.
- `D5N_ADAPTER_EXTERNAL_POST_COMMIT_V1` says POST copyback is performed by an external adapter and must be acknowledged through the separately probed external-POST export. HSR requires this bit and an identity different from the host. Built-in WuWa intentionally keeps host identity and does not set it.

The API does not assert that HSR has Feature 1. HSR omits PRE unless its own game-specific evidence proves that boundary.

## Gate

Call `DLSS5_NativeAdapterSetGateV1` with a nonzero, strictly increasing generation whenever phase eligibility or reconstruction changes. Frames must repeat that exact generation and set `D5N_FRAME_GATE_OPEN_V1`. An SR/RR change without a new gate closes NR; the host never silently switches order or game reconstruction.

## Submit raw frame

`DLSS5_NativeAdapterSubmitRawFrameV1` accepts native D3D12 pointers and an explicit resource-state/subrect contract. The adapter retains ownership. Inputs must remain alive through native command-list execution under normal D3D12 rules.

- PRE call phase before signed ordinary SR. On `D5N_FRAME_EVALUATED_V1`, bind `replacement_color` at Color origin `(0,0)` only for that same signed SR call. Restore and reread the original bindings afterward.
- POST call only after the original signed SR/RR Evaluate returned success. `source == output`; final HDR composition is recorded in place once.
- Pending/disabled/unsupported/gate/budget/error results require normal game pass-through and must not present an old replacement.

Every layer ID/create/evaluate counter and budget diagnostic is returned. The host validates that actual calls equal the cold-latched pass count before active status is possible.

## PRE commit

After a successful PRE replacement is consumed by the original signed Feature 1 call, call `DLSS5_NativeAdapterCommitFrameV1` with the exact frame/owner/game identity, original signed result, parameter-restoration proof, and output-commit proof. Without this acknowledgement status remains `gate_closed`; an evaluated NR buffer alone is not presentation proof.

Built-in WuWa uses this regular commit for both PRE and deferred POST format conversion, including RR POST. An external HSR POST instead calls `DLSS5_NativeAdapterCommitExternalPostV1` only after the original signed SR succeeded and a nonblocking poll observed completion of the D3D11 retirement point ordered after Wait+copyback. Merely queuing that Signal is not delivery proof. The host matches the pending channel, phase, frame, owner, game, reconstruction, gate generation, and reset generation; the frozen 72-byte commit does not grow.

Native queue execution and completion are separate requirements. Even after either adapter commit, status remains non-active until the hooked real `ExecuteCommandLists` forwards, the same queue accepts a fence signal, and the background runtime worker observes a current-epoch successful-frame sample complete. Commit-result publication and the pending blocker are one status-lock transaction, so telemetry cannot observe the first external frame unblocked. External `CREATE_PENDING` atomically clears an older delivery floor. After one delivered external frame is proven, that current-epoch floor may sustain active while the adapter's single bounded next copyback is pending; built-in WuWa pending commits continue to block. Create acknowledgement is never counted as Evaluate completion.

`DLSS5_NativeAdapterRetireV1(owner)` is accepted only while an external-POST adapter is attached. It revokes status proof before forwarding retirement of that owner's private runtime map. Built-in CP/WuWa release behavior is unchanged.

## Threading/lifetime

Frame calls are serialized by the production runtime. Attach/gate/status polling may occur on other threads. Do not call adapter APIs under loader lock. Do not release or reset a recorded command list to hide a rejected frame: native hooks explicitly invalidate such work and fault the associated chain.

All ABI structures use fixed-width fields and 8-byte packing; C++ static assertions freeze current sizes. Reserved fields must be zero in future adapter implementations even though v1 currently ignores them. The internal host/runtime `D5rQueryV1` remains 80 bytes; its first four formerly reserved words now carry an optional owner selector and lower-bound submission/completion sample outputs. Adapter-facing `D5nRawFrameV1` (200 bytes), `D5nFrameCommitV1` (72 bytes), and `D5nRawFrameResultV1` (216 bytes) are unchanged.

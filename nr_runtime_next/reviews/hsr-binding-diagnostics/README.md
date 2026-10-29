# HSR CPU-only binding diagnostics review

Source was copied from
`reviews/hsr-live-diagnostics-20260910-112307/project` without its prior build
directories. Nothing in this review tree is deployed or merged. The task's
supplied run113832 finding (`capture_armed=1`, install installed/already-installed,
3322 creation calls, zero scoped motion/depth matches, and a 53k normal-SR
sequence) is treated as motivation, not re-run or independently claimed here.

## Change

The creation-only `ID3D11Device::CreateShaderResourceView` diagnostic was
replaced by a pass-through observer of the real supplied
`ID3D11DeviceContext::CSSetShaderResources` context. Slot 67 is proven by a
compile-only `offsetof(ID3D11DeviceContextVtbl, CSSetShaderResources)` assertion
against the MinGW Windows SDK. No PS/VS/GS/HS/DS stage hook was added: the
reported normal-SR sequence justifies testing CS first, while no evidence yet
justifies widening interception.

The observer:

- keeps at most 8 shared context-vtable records and scans at most the SDK's 128
  CS SRV slots per call;
- reads a read-only vtable slot without RMW, publishes predecessor plus its
  module lease before permission-guarded CAS, restores protection, and retains
  a real context COM lifetime for every exposed shared-vtable wrapper;
- forwards the predecessor exactly once with the original context, start slot,
  count, and view array unchanged;
- arms immediately before the signed Feature-1 D3D11 Evaluate and finishes
  immediately after it, and accepts calls only from that exact context identity;
- calls `GetDesc` and `GetResource` on views actually passed to CS binding, then
  compares exact returned-resource `IUnknown` identity to the current Frame
  motion/depth identities;
- records bounded raw samples as `m|d@slot=format:accepted`, including unexpected
  formats, while strict attestation still requires exact 33/37 motion and 19/21
  depth resource/view contracts;
- reports separate total/scoped calls, examined/truncated views, role identity
  matches, accepted role views, and accepted complete contracts.

A format-33 resource is never inferred to have view format 37. A typed view that
was merely created/cached, or belongs to another resource/context identity, is
not accepted as SR binding evidence. Existing transport, directional fences,
copyback retirement/acknowledgement, host/native/protocol ABI files, and export
inventory are byte-identical to the source tree.

## Status

Cross-compilation, SDK layout assertions, PE/source checks, existing CPU logic,
vtable permission/CAS tests, and 302 hermetic fake-COM binding checks pass. No
GPU, Wine, game, deployment, or production-main action was performed.

This remains diagnostically **unproven** until a later authorized physical HSR
run observes relevant CS binding calls and exact Frame identity matches. Zero
binding calls, zero scoped calls, or zero identity matches must remain a failed
proof and cannot enable NR.

See `logs/clean-check.log`, `logs/scope-verification.log`, the source under
`project/`, and `patches/hsr-cs-binding-observer.patch`.

# Main review of in-progress HSR transport (not yet deployed)

Observed 2026-09-10 ~07:16 in adapters/hsr_native/d3d11_transport.cpp. Worker may still change this source; re-check final delivery before patching.

## Blocking lifetime/order issue to resolve before GPU execution

The current transport shares ONE fence (`fence12_` opened as `fence11_`) and uses `next_fence_++` for BOTH D3D11 input-ready Signal and D3D12 output-ready Signal. D3D11 waits for output-ready only when `copy_back` is true.

For CREATE_PENDING / budget / bypass / failed-NR frames, `complete(..., false)` submits D3D12 work and records an output fence, but does not insert the D3D11 GPU wait. A later D3D11 input Signal can therefore satisfy an earlier D3D12 output value before that D3D12 work completes. That is not valid lifetime proof. The input shared textures are also global rather than per-slot, so next-frame copies can overwrite them before prior D3D12 consumption.

Preferred correction: use TWO directional shared fences, each with one signalling queue and its own monotonically increasing counter, plus always insert the D3D11 GPU output-completion wait for every successfully submitted bridge frame when shared textures are reused—even when no copyback occurs. Only CopyResource-to-game is conditional. Alternatively use correctly fenced per-frame shared texture sets; do not just separate fences and leave global textures racy.

The current wait_for_slot()/flush paths also contain render-thread WaitForSingleObject. Do not describe this candidate as nonblocking. Prefer nonblocking fence polling/bypass on slot pressure; resolution-change retirement must not release in-flight shared textures. UINT64_MAX must not count as completion. Destructor/process-exit safety is distinct from per-frame behavior.

Good detail: ensure_submission_queue() is delayed until after NativeSubmitRawFrame has had a chance to hook the owned device via track_command_list; this avoids missing the queue when D3D12CreateDevice was dynamically resolved before host observation. Preserve or explicitly replace this dependency.

No HSR GPU run, native deployment, Guardian mutation, or anti-cheat modification was performed during this review.

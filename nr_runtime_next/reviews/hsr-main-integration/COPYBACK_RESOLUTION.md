# Resolution of `MAIN_COPYBACK_REVIEW.md`

The initial draft acknowledged external POST after enqueueing the D3D11
retirement Signal. That was insufficient: the host Runtime completion sample is
for the D3D12 list and can precede the game-output D3D11 copy.

The final proposal does **not** use Signal enqueue as completion:

- `HsrTransportCompletion` returns the exact private D3D11-produced retirement
  value associated with its command slot.
- Router stores one `PendingExternalPost` containing frame commit, host gate
  generation, slot and retirement value.
- Before any next host Submit, it calls `GetCompletedValue` through
  `poll_retirement`; busy bypasses the current native attempt, and
  `UINT64_MAX`/invalid fails closed. There is no CPU wait.
- It calls `CommitExternalPost` with `output_committed=1` only after the poll is
  ready. Gate/owner/reset changes clear or reject the pending epoch.
- First external pending blocks active. After one delivered frame establishes
  the current-epoch floor, status retains that delivered frame's diagnostics
  while the one bounded next external copyback is pending. Regular WuWa
  PRE/POST pending commits still block exactly as before.
- A failed copyback chain sends the matching failed commit, which clears prior
  proof/status before the adapter closes its route.

This is CPU-reviewed behavior only. It still requires an actual D3D11/D3D12 GPU
run to validate queue and driver behavior.

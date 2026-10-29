# Main additional acceptance question (2026-09-10)

Please review before live acceptance: external POST must not call D3D11
`Signal(retired)` GPU completion. Current HSR adapter acknowledges copyback
immediately after queuing D3D11 Wait/Copy/retirement Signal. Native host completion
samples cover the D3D12 list, which can finish before the dependent D3D11 copy.
That proves NR inference completion but not D3D11 game-output delivery completion.

If claiming full delivered-frame active, keep a bounded external pending commit
sample (do not overwrite it with each moving frame), retain its per-slot commit
metadata/epoch, and acknowledge after nonblocking retired-fence GetCompletedValue
confirms it (never UINT64_MAX). Poll/reap before the next submit; no render-thread
CPU wait, no fence Signal-as-completion. Gate/control/reset/owner changes invalidate
old pending metadata. Otherwise explicitly separate NR-complete from external
copyback-complete state and don't label the latter proven.

This is a Main review requirement, not an already observed HSR game failure.
Main baseline currently uses the untouched old deployment, not this candidate.

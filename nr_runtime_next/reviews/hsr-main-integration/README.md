# HSR main integration review tree (CPU-only, not deployed)

This is an isolated base/proposed review tree. Nothing here authorizes or
performs game, GPU, Wine, launcher, Guardian, production-native, signed-file, or
anti-cheat changes.

## Deliverables and apply order

1. `patches/MAIN_HSR_EXTERNAL_POST_RETIRE.patch` — rebased on current
   pc4+WuWa main. Apply/review this first.
2. `patches/HSR_ADAPTER_OFFICIAL_ABI_AND_VIEW_CAS.patch` — switches the HSR
   adapter to the reviewed native names/flag and hardens the D3D11 SRV observer.
3. `patches/HSR_INTEGRATION_COMBINED.patch` — exact concatenation of 1 and 2.
4. `patches/GUARDIAN_PUBLISHER_OPTIONAL.patch` — separate, opt-in patch for the
   actual Guardian source layout; do not apply without approved receipts and a
   cold owner review.

Patch hashes are in `PATCH_SHA256SUMS`. `base/` is the read-only input snapshot,
`proposed/` is the build-tested result, and `verify-apply/` is a disposable
patch-application check. Input hashes are in `INPUT_SHA256SUMS`; isolated output
hashes are in `BUILD_SHA256SUMS`.

Do **not** apply `inputs/OPTIONAL_NATIVE_EXTERNAL_POST.patch` or the original
adapter copy unchanged. Its global external capability/self-identity rule would
reject built-in WuWa Attach, and its regular-commit phase rule would reject
built-in WuWa RR POST.

## Main rebase decisions

- Adds official external-POST commit and owner-retire export names/function
  types plus capability bit; Raw=200, Result=216 and Commit=72 are unchanged.
- HSR alone must attach with the external-POST bit and identity different from
  host. Existing CP/WuWa Attach behavior does not gain that requirement.
- CP built-in POST still records its success floor directly.
- WuWa PRE and WuWa POST (ordinary SR **and RR**) still use the regular deferred
  commit channel.
- HSR POST uses a distinct external channel. Pending state records phase,
  gate generation and reset generation. A commit must match frame, owner, game,
  reconstruction, channel and the still-open current epoch.
- First-frame evaluated diagnostics and the pending blocker are installed under
  one status lock. The HSR adapter keeps one pending sample, polls its private
  D3D11 retirement value without waiting, and only then calls Commit. Commit
  only removes the first blocker and sets a delivered-frame floor; it cannot by
  itself publish active. Existing telemetry still requires current-gate
  evidence, exact layer count, submission acknowledgement and sampled runtime
  fence completion at/after the floor. Later bounded external pending work may
  retain that delivered-frame status; external `CREATE_PENDING` atomically
  clears the old floor, and built-in WuWa pending work still blocks.
- External Retire is available only for an attached external-POST adapter and
  invalidates publication proof before forwarding Runtime retirement.

## HSR view-observer audit/fix

The input observer changed a read-only shared COM vtable slot with a plain store,
did not compare against the observed predecessor, and did not retain the
predecessor module/device lifetime. The proposal now:

- reads the slot without an RMW;
- retains the predecessor module and publishes predecessor+lifetime before CAS;
- makes only the exact pointer writable, uses
  `InterlockedCompareExchangePointer`, restores the exact old protection, and
  preserves a competing hook on mismatch;
- holds one D3D11 device reference for the observed shared vtable;
- keeps pass-through forwarding/lifetimes if protection restoration fails, but
  disables view attestation/capture;
- has a host CPU collision/permission/lifetime test.

The latest adapter's already-fixed two-direction fence/nonblocking transport is
preserved. The only transport addition returns the exact D3D11 retirement value
and exposes nonblocking polling for the bounded external commit; no fence
producer/order, shared-resource reuse rule, CPU wait, or copyback path changed.

## Guardian

See `GUARDIAN_PUBLISHER_DESIGN.md`. No approved build-integrity or LOCAL route
policy receipt is supplied. The examples under `receipt-templates/` are
intentionally denied/unreviewed and cannot arm. The publisher must never be
represented as vendor anti-cheat authorization or protection bypass.

## Remaining acceptance blocks

CPU compilation is not HSR acceptance. Actual numeric AppID capture, actual
same-resource 37/21 SRV observation, D3D11/D3D12 state/synchronization, exact
cold-build hash/layout, current Authenticode verification, approved LOCAL route
policy, Guardian hardware operation, and real GPU/game behavior remain
unverified. Keep the lease unattested and do not deploy until those independent
owner checks pass.

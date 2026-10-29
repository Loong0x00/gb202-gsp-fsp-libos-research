# WuWa UE4 crash on first 6K raw-capture trigger

Time: 2026-09-03 08:29 local.

## Evidence

- Capture active marker and empty session directory were created at 08:29:29.307.
- The last complete Router frame was global ID 3694 at 08:29:29.316; it was a
  successful 6144x3456 signed RR + Feature18 frame. Its CPU recording time rose
  to 13.106 ms while first readback resources/copies were recorded.
- No raw surface completed and `manifest.jsonl` remained zero bytes.
- UE4 recorded an execute access violation at unmapped address
  `0x00006fffb4810000` on thread 1384. It was not an OOM/assert/stall.
- No matching kernel Xid/NVRM event occurred.
- The minidump stack places the caller in
  `01-dlss5-post-service.addon64+0x2fe35`, exactly after the invalid direct call
  emitted for `on_command_list_reset_or_destroy`.

## Root cause

The capture add-on used a locally declared pure-virtual `get_native()` method to
call ReShade API objects. MinGW `-O2` devirtualized that external-object call to
an invalid pure-virtual placeholder. The first armed frame enabled command-list
events, and the reset callback executed that bad target.

This is a capture implementation defect, not the original 6K red-frame bug,
not Feature18 inference failure, and not GPU/driver failure.

## Containment and fix

1. Removed trigger/stop/active markers.
2. Rolled back immediately to stable post service SHA-256
   `6e1621581aa2a1a81b422a5870c07ed326a32299d4c1b2a098a1c8af42d29210`.
3. Replaced the pure virtual call with explicit vtable slot-0 dispatch through
   an opaque type.
4. Verified fixed assembly uses `call *%rax` from the external vtable and no
   callback cold pure-virtual thunk remains.
5. Added persistent `dlss5-raw-capture.log` diagnostics.
6. Reduced initial validation to 4 frames.
7. Deployed fixed capture+timing build SHA-256
   `6e01cfef594cf877dede77ec49e3fbe49c66e9bf99691728ecf60645f303fc7d`.

Fixed-build rollback:

`/home/user/rt_5090_project/dlss5_vk_bridge/raw-capture-deployments/20260903-083619-timing/restore.sh`

The fixed callback still requires a live four-frame validation before increasing
the capture window.

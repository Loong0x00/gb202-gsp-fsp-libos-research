# Wuthering Waves output transition-only A/B

Deployed only after the lingering closed-game process exited.

## Binary

Previous UAV-only service:

`b341eae7f00d1e74cc3453d1b78b936e67367e6947575fb9485a6ddccfbef090`

Current transition-only service:

`5cc15ba7c71a70c3823e3d3d9a8f73489af76dac8fab26c0f0a79a73fa181690`

## Controlled change

The prior single UAV barrier did not suppress the defect. This build removes
that A/B and, immediately after Vulkan interop, records only this output state
round-trip:

`UNORDERED_ACCESS -> COPY_SOURCE -> UNORDERED_ACCESS`

There is deliberately no copy, readback allocation, Map or CPU/GPU wait. Raw
capture remains compiled but inactive unless separately armed. This tests the
stronger transition/cache-flush component of the successful raw-capture path
without its 6.35 GiB payload or timing disturbance.

## Test

1. Launch normally at 6K.
2. Do not press `Super+Alt+C`.
3. Test the two cases separately again; recording is optional for this binary
   result, though useful if the defect remains.
4. Report whether the structured frame appears in either case.

Successful load marker in `dlss5-vk-bridge.log`:

`post-SR D3D12 output UAV-COPY_SOURCE-UAV transition enabled (transition-only A/B)`

Rollback to the UAV-only build is available through `restore.sh` while the
game is stopped. The earlier deployment directory retains the stable
capture+timing build for a full rollback chain.

## Live result

FAIL to suppress the defect. The user reports that the structured frame is
still present; raw capture was not armed. The transition build is confirmed by
the load marker in `bridge.latest-run.log`.

The run contains 2,868 Router Evaluate records. After login gating, 1,324
Feature18 posts succeeded and zero failed. The game exited normally, with no
new UE4 crash or Xid. Therefore an output state round-trip without a real copy
is also insufficient.

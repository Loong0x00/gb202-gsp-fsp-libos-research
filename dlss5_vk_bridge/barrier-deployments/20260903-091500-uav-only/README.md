# Wuthering Waves barrier-only A/B deployment

Deployed after `Client-Win64-Shipping.exe` exited.

## Binary

Previous capture+timing service:

`6e01cfef594cf877dede77ec49e3fbe49c66e9bf99691728ecf60645f303fc7d`

Barrier-only A/B service:

`b341eae7f00d1e74cc3453d1b78b936e67367e6947575fb9485a6ddccfbef090`

Installed at:

`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/01-dlss5-post-service.addon64`

## Controlled change

After `EndVkCommandBufferInterop` and after the existing GPU-timing endpoint,
the service records exactly one legacy D3D12 UAV barrier targeting the game
output resource:

- type: `D3D12_RESOURCE_BARRIER_TYPE_UAV`
- resource: signed-RR/Feature18 game output
- no state transition
- no texture copy
- no Map
- no fence wait
- no raw capture unless its separate marker is armed

This isolates D3D12-side output visibility from the heavier raw-capture path,
which used `UAV -> COPY_SOURCE -> UAV` transitions and five readbacks.

## Test

1. Start normally through the 6K launcher/Steam route.
2. Do **not** press `Super+Alt+C`; raw readback must remain inactive.
3. Record the same R animation, preferably one ER-together attempt and one
   R-only attempt.
4. Report whether either structured red/block frame appears.

A successful load must include this in `dlss5-vk-bridge.log`:

`post-SR D3D12 output UAV visibility barrier enabled (barrier-only A/B)`

Rollback, only while the game is stopped:

`./restore.sh`

## Live result

FAIL to suppress the defect. The user tested the two input cases separately,
without arming raw capture and without recording video; the structured bad
frame remained in both.

ReShade confirms the service was loaded, and the required barrier-build string
appears in `bridge.latest-run.log`. The latest Router run contains 4,896 signed RR
Evaluate records; 2,765 called Feature18 after the login gate, with zero post
failures. Therefore a plain D3D12 UAV barrier is insufficient.

The game window did not terminate its background process after more than 30
seconds. After confirming the exact game PID and the user's stated intent that
the game was closed, it was terminated with SIGTERM before the next binary was
deployed.

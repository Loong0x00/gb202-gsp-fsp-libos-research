# Native runtime acceptance — work in progress (2026-09-10)

Latest stage: pc4 includes WuWa ingress and exact-target/factory queue observation.
Main corrected a read-only-vtable CAS-as-read bug caught by the real Wine
factory harness, then passed that harness and a fresh CP post1 cold regression.
WuWa RR/post1 reached 1,781 actual Evaluates / 890 completed GPU samples at
1080p; see `WUWA_LIVE_FINDINGS.md`. A later ten-layer request crashed in the
game's libcrypto before NR was enabled, so WuWa ten-layer execution is **not**
validated. HSR remains source/CPU/Wine-fake-harness work, not a live game result.

Not a release/three-game compatibility declaration. Every completed cold test
restored its owned files/settings and checked signed NVIDIA hashes. Production
CP/WuWa/HSR deployments have **not** been permanently migrated. Current profiles
in `~/.config/dlss5-linux/profiles.json` were not rewritten.

## Observed CP2077 execution

All cases use the owned DXGI forwarder + native host/runtime, headless Gamescope,
PT on, FG and dynamic resolution off. Process maps and copied proxy hashes
identify the owned loader; no ReShade/addon modules appear in captured maps.
The signed NVIDIA files remain unchanged on disk; Wine/Vulkan compatibility
shims still exist and this is not a claim of an unmodified in-memory runtime.

|Case|Observed maximum successful Evaluate counts per layer|Result|
|---|---:|---|
|6K SR Quality, post 1, first candidate|7|Failed: persistent game Output binding was unsuitable|
|6K SR Quality, post 1, owned HDR target fix|1320|Continuous execution|
|6K SR Quality, pre 1|1607|Continuous execution|
|6K SR Quality, post 2|1185 each|Two distinct handles, Create count one each|
|6K SR Quality, pre 3, retry|1194 each|Three distinct handles; also tested live off/on|
|1080p SR Quality, post 10|2198 each|Ten distinct handles, Create count one each|
|1080p SR Quality, pre 10|2610 each|Ten distinct handles, Create count one each|
|1080p RR, requested pre 1|0|Unsupported, RR remains enabled; no hidden post fallback|
|6K SR Quality, requested post 10, corrected receipt|0|Persistent budget_exceeded; zero layer Creates|
|6K DLAA, requested post 1|0|Budget_exceeded; original game path retained|

Counts are **lower bounds from asynchronous samples**, and successful NGX
recording counters alone are not GPU fence-completion proof. Runtime queue
forwarding/fences, continuous actual GPU workload, scene progression and
compositor images provide additional evidence; the exact `active` publication
boundary is still under review (below). No per-NR GPU timing was measured here.

## Fixes and tested control behavior

- POST now composes once into a chain-owned RGBA16F texture, then records a copy
  to the **current frame's** game Output only after all layers/composition and
  EndInterop succeed. No game Output pointer or descriptor is cached forever.
  PRE retains its owned replacement Color and original parameter restoration.
- Temporal reset includes discontinuous frame IDs, in addition to original
  reset/generation/first-evaluation conditions.
- Admission charges five work surfaces, guides, a conservative per-layer
  workspace/history allowance, and reserve **before** private chain allocation.
  Rejected chains retain budget_exceeded on subsequent frames rather than
  becoming an unhelpful generic error. First rejection run exposed that receipt
  bug; the later `064115` run verifies the correction.
- Real manager API exchange during post2: active post2 -> request pre3 ->
  pending_restart with effective post2. Requesting original post2 again returned
  to active on subsequent real frames (the first response can still be pending).
- Real D5LC manager off/on during pre3: acknowledged disabled then active pre3;
  no profile-store changes. That run's FPS is not an uninterrupted performance
  sample.

## Visual evidence and limitations

Early X11 root screenshots were black because they did not capture Gamescope's
Vulkan-presented plane. They are retained as **invalid visual evidence**, not
black game frames. `tools/run_cp_case.py` now uses the isolated compositor's
`gamescopectl screenshot <owned path>`; native-resolution PNG and JPEG previews
are retained from the successful pre3 retry and later cases.

The ten-layer 1080p images show strong structured texture/edge artifacts in some
regions. No same-source NR-off reference was captured in these runs, so this is
not a quantified quality attribution or a claim of improvement. Manager wording
recommends starting at one layer and warns that more layers can reinforce
artifacts. These snapshots do not measure temporal stability or flicker.

## Why default 6K DLAA is not force-enabled

Observed **global** NVML peak memory (MiB), not per-layer allocation measurements:

- 6K SR Quality NR bypass/budget rejection: 22,769 (corrected receipt run).
- 6K SR Quality post1: 25,680; post2: 27,918.
- 6K DLAA bypass/budget rejection: 28,398.

The 6K DLAA admission snapshot was current usage 23,955,111,936 bytes against
budget 28,249,686,016, with estimate 4,090,494,976 and reserve 2,824,968,601.
It fails the guard. Do not weaken the guard or silently switch DLAA/RR/settings
to make the request appear active. These peaks are across separate runs and
include other GPU clients/readback effects, not exact matched per-layer deltas.
On pc2 status, `current_usage_bytes` is the **admission snapshot**, not continuously
refreshed memory telemetry.

## Remaining acceptance blockers

1. The pc3 patch now gates `active` on bounded nonblocking GPU-completed samples
   for the selected enable/gate/owner epoch, separate from the moving retirement
   fence. Main integrated the reviewed patch with backup and full build/Wine
   harness verification. Cold post1/pre1 now report real completed sample counts.
   pc3b also prevents an unexecuted/budget-rejected chain from claiming nonzero
   effective layers merely because a new request is pending. Further regression
   and negative-case acceptance remain; no permanent migration yet.
2. First pre3 launch `062708` stalled before any NR frame/benchmark directory,
   with idle GPU and sampled Wine Windows threads in `wait_suspend`. Stacks and
   maps are retained. Only owned test processes were terminated; rollback
   succeeded. Identical retry `063042` worked. A matching REDEngine minidump now
   proves this followed the game's crash-report/suspension path, not an NR GPU
   hang. It has no ExceptionStream, so the initiating fault remains unknown.
   `reviews/startup-stall/` retains the dump and source audit of real loader/IAT
   race surfaces (not yet proven causal). No protective software was bypassed.
3. WuWa RR/post1 and the format shaders now have real GPU evidence; other WuWa
   combinations remain unvalidated. HSR's two-directional-fence/view-observer
   source passes 57 CPU checks and a real Wine fake-NVUnity forwarding test, but
   actual Guardian lease, AppID/view capture, interop and game commit acceptance
   remain required. HSR PRE is only a proposal, not implemented game support.
   Both games' original deployments remain restored, not permanently migrated.
4. RR/pre cold test deliberately had no cached capabilities; the backend emitted
   fresh unsupported status, but did not produce capability JSON without an NR
   compatibility probe. Do not manufacture capability evidence to enable UI.

## Evidence

`LIVE_RUNS.json` is generated by `tools/summarize_native_runs.py` from completed
run directories. Each run contains request, status samples, deployment hashes,
process maps, benchmark/telemetry, rollback and retained evidence hashes.
`manager-live-exchange.json` and `manager-live-enable-exchange.json` record actual
manager/core interactions, not synthetic fixtures. No large raw-plane capture
was introduced in these tests; prior order-comparison raw cleanup remains intact.

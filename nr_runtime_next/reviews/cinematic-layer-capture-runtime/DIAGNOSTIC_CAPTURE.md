# Isolated DIAGNOSTIC per-layer staging (CPU/crossbuild only)

Source clone: `../quality-post5-cinematic-20260910-173726/source`, excluding all `build`/`package` directories. Only this new clone was modified. No signed DLL changes, deployment, Main/game edits, Wine or GPU runs. The sibling `cinematic-image-chain-probe` was not edited.

## Caller contract / opt-in

Set **`D5R_DIAGNOSTIC_LAYER_CAPTURE=OWNED_STATIC_OFFSCREEN`** before the first enabled chain allocation. This exact value explicitly attests that the caller is the authorized owned, static, offscreen lab harness. There is no ABI field that can independently prove image ownership/static content; do not enable in a game. Start with the lab output directory as the Windows current working directory (no other output path option). Its absolute path is frozen at cold preparation. A long/unavailable cwd is rejected. Environment is sampled once; unset/any other value preserves the normal recording path.

Admission selects the first eligible POST5 owner with work extent **1..1536 by 1..864**. All other owners are ignored for the lifetime of the process. One READBACK allocation, one capture bundle in flight, **two attempts maximum** (stricter than two successful frames), no forced reset/history/control/pass-count changes. First eligible Evaluate is captured; a later normal Evaluate is captured only after exact GPU retirement and worker disk copy-out. The harness must keep running/polling long enough for the worker (~100 ms cadence), then submit a later ordinary-history Evaluate. It must execute each native recording once, on the same queue used for Create, and report existing D5R Submitted/Reset callbacks truthfully. Replaying an already reported recording is not supported by the inherited submission tracker.

Allocation happens in cold chain resource preparation, before Create recording, not in hot Evaluate. Exact padded footprints plus existing estimated chain/reserve budget must fit. At maximum extent the allocation is **84,934,656 bytes (81 MiB)**; hard admission limit is **256 MiB**. No live-resource eviction/quality reduction. Allocation is deliberately held to process exit, even after two captures; only proven-retired, CPU-drained slices may be reused for attempt two.

## Capture and interop changes

* S: native copy of the owned snapshot immediately after `copy_active`.
* B: encoded base after encode.
* P1..P5: each successful signed Evaluate output **inside the loop before parity reuse**, distinct immutable staging offsets for all five stages.
* D: decoded composition immediately after compose, before native output commit.

B/P1..P5/D add seven interop breaks per captured frame. Each break adds conservative ALL_COMMANDS/MEMORY_WRITE ordering, normalizes every temporary ping read layout back to the D3D12 UA contract, calls existing global_post/EndInterop, transitions the selected D3D12 resource to COPY_SOURCE, copies to READBACK, restores the exact D3D12 state, then BeginInterop/global_pre and restores temporary ping read layouts. Existing original per-layer/codec barriers remain. A failed capture boundary stops the partial frame and quarantines resources. No D3D12 copies while interop is active. No Vulkan image copy or assumption of Vulkan TRANSFER_SRC usage.

This **changes command-buffer boundaries and may affect NR internals**. Captured images are diagnostic evidence, not production-quality acceptance; compare separately with the unmodified DLL baseline. Configure, NR controls/maps/handles/history policy, codec, host, signed modules, and public headers/exports are unchanged. The frozen query ABI flags are not a declaration that this instrumented build is production.

## Retirement and output

The bundle binds the exact Evaluate Pending cookie/list. Only accepted same-queue post-forward Submitted callbacks bind its own AddRef'd fence/value; it never uses the runtime's older completion sample. The existing retirement worker alone polls this fence, rejecting `UINT64_MAX` and requiring a nonzero value and completed >= value. Map/raw/metadata writes happen only after that proof, outside the render/submit mutex. Staging remains pinned during output.

Failed Signal/submission, wrong list/queue, Reset/Release before submission, interop boundary failure, device loss, or a 30-second unproven-retirement deadline quarantines the bundle without recycling/freeing it. Failed Evaluate, binding validation, or retiring/failed owner invalidates the sample; with exact retirement proof it may produce **metadata only**, no valid raw claim. A disk/map failure ends capture (possibly leaving partial files marked `raw_complete=0` when metadata could be written). There are no GPU waits, extra queue executions/signals, or hot-frame disk operations. DLL/process shutdown does not drain pending captures; leave the lab alive to finish. Counters/terminal phase prevent retries beyond two attempts.

Directories, created with no overwrite, beneath the saved lab cwd:

```
d5r-layer-capture-<WindowsPID>-<sessionTick>-o<owner>-f<frame>-a<1|2>/
  S.rgba16f.raw
  B.rgba16f.raw
  P1.rgba16f.raw ... P5.rgba16f.raw
  D.rgba16f.raw
  metadata.txt
```

Each complete raw file is exactly `width*height*8` bytes, top-to-bottom rows, little-endian RGBA16F interleaved; footprint padding is stripped. S/D are HDR domain; B/P1..P5 proxy domain. Metadata is written last, contains validity, stage mask, dimensions/offsets/pitches, owner/frame/gate/reset, exact control bits with field order, Evaluate results, per-layer handles/maps/CBs, expected generation routing, wrappers/images/views/formats/ranges/ReadWrite, resource key getter results and pointers, and exact list/queue/fence/value/completed evidence. Existing `runtime_log` reports bounded arm/refusal/quarantine/dump events.

## Binding evidence and limitations

Capture-only pointer getter uses **core vtable slot 8 (+0x40)**, not host feature-map slots. Local verification: `../cinematic-five-layer-dataflow-audit/signed-reader.txt`, reader RVA `0x1a086` (Color), `0x1a15e` (MVec), `0x1a23e` (Depth), corresponding Output reader; cached signed artifact SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`. This cached artifact was not revalidated against a GPU-loaded DLL here. Getters are observational only. Unknown pointers are never dereferenced. A namespaced resource getter failure/mismatch invalidates the capture rather than guessing a binding or copying an unknown image. Bare aliases Color/Output/MotionVectors/Depth are reported but never changed. This tier does **not** capture a differing actual-selected input or prove signed descriptor consumption/hidden writes; those require separate follow-up, not interpreting invalid dumps as expected routing.

No G/Present/screenshot or WuWa post-format-bridge capture: D is the owned decoded image, not proof of later output conversion/commit. Original host pointers beyond those passed in D5R are unavailable and explicitly labeled; metadata identifies D5R normalized source/output. Static scene/ownership is caller-attested, not inferred from pointer identity. No GPU validation was performed; D3D12/Vulkan driver ordering and actual pixel results still require the parent's authorized lab run and separate uninstrumented baseline comparison.

## Verification / artifact

```
make -C native capture-cpu-check
make -C native cpu-check          # CPU checks + crossbuild, NOT `check` (which runs Wine)
g++ -std=c++20 -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
  native/tests/capture_policy_test.cpp -o native/build/capture_policy_test_san
ASAN_OPTIONS=detect_leaks=1 native/build/capture_policy_test_san
```

Tests cover bounds/budget overflow, exact numeric retirement, device loss, one-bundle/two-attempt lifecycle, no reuse during CPU copy-out, quarantine, command-time copies for 1..10 layers and delayed parity-copy mutation detection, padded-row stripping, source boundary/copy placement, unchanged Configure/codec/host/public ABI and six PE exports. These are CPU models/source checks, not mocked execution of the full Windows GPU implementation or a signed NR test. Logs: `capture-tests.log`, `cpu-check.log`, `crossbuild.log`, `sanitizers.log`. See `ARTIFACT_SHA256SUMS` and `CHANGED_SOURCE_SHA256SUMS`.

Build: `native/build/dlss5-native-runtime.dll` (MinGW x86-64 PE DLL). No deployment/package action is performed. Only use this DLL in the isolated owned harness; unchanged host/boot crossbuilds generated by cpu-check are not deployment instructions.

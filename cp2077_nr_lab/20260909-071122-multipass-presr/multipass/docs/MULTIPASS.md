# Cyberpunk 2077 post-SR/RR Feature 18 multipass

## Scope and attribution

This branch changes only the owned native-Linux/Proton Vulkan Feature 18 post-service. The router export ABI is unchanged. It does not implement pre-SR processing and does not modify or deploy any game, prefix, installed configuration, `dlss5_vk_bridge`, or `dlss_ngx_proxy` checkout.

The lifetime and data-flow design is directly adapted from
[wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass](https://github.com/wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass), verified commit
`ec96f42f8d32a4fc82f7c4558c0ed12a9f90d853`, especially
`OptiScaler/shaders/dlssnr/DlssNr_Dx12.cpp` and
`OptiScaler/dlssnr/design/pre-sr-multipass.md`. This local adaptation uses the existing vkd3d-proton D3D12/Vulkan interop and signed Vulkan NGX runtime rather than OptiScaler's D3D12 forwarder.

## Control

The default is one pass. Select 1, 2, or 3 for the process lifetime with either:

```text
DLSS5_POST_PASSES=3
```

or a `dlss5-post-service.ini` beside the service DLL/add-on:

```ini
[DLSS5]
PostPasses=3
```

The environment variable takes precedence. Numeric values are clamped to `1..3`; malformed values are ignored. Configuration is intentionally latched on first use, so restart the process after changing it. `service/dlss5-post-service.ini.example` is a template only and is not deployed by the build.

## Processing and lifetime

For an N-pass frame:

1. GPU-copy the completed signed DLSS SR/RR output to an owned source snapshot. The game output remains untouched.
2. Encode that snapshot once to the immutable R16G16B16A16 proxy.
3. Evaluate independent persistent Feature 18 histories using raw neural ping-pong:
   - pass 1: `base -> A`
   - pass 2: `A -> B`
   - pass 3: `B -> A`
4. Decode/compose the final raw answer against the immutable base/source exactly once, and only if every requested evaluation succeeded.

There is no CPU image transfer. Inter-pass barriers transition only the previous raw answer to shader-read and return it to the UAV/GENERAL rest layout. A failed create/evaluate or a build-only warm-up frame does not run the decoder, so the signed game output remains in place.

Each layer has its own `NVSDK_NGX_Handle`, reset flag, create count, evaluate count, and successful-evaluate count. A camera/game/controller reset reaches every active layer. Changes to feature-affecting live controls or the guide contract wait for prior GPU work, release all layer histories, and rebuild/reset them. Output size/format changes similarly invalidate handles, cached image views/descriptors, and all owned post resources after GPU idle before allocating a complete replacement set.

To retain as much of the community creation safety rule as the unchanged service ABI permits, pass counts 2/3 create at most one missing feature on each build-only service invocation. No multipass handle is evaluated on the invocation that creates it. Thus two passes require two initial pass-through invocations, and three passes require three, before the first complete multipass frame. The one-pass path intentionally retains production behavior (create and evaluate on its first invocation).

The router ABI does not expose a proven queue-submission epoch. An invocation boundary is therefore weaker than OptiScaler's submitted-epoch check if an engine records multiple upscaler evaluations before submitting the command list. Cyberpunk runtime logs must confirm expected one-create warm-up progression; compilation cannot prove this synchronization assumption.

## Dimensions and memory

Do not conflate these dimensions:

- **game output**: the signed SR/RR output and final composition target;
- **work raster**: the owned encoded proxy and A/B raw model surfaces; currently the same dimensions as game output;
- **evaluation guides**: motion/depth dimensions supplied to Feature 18, normally render size;
- **create compatibility input**: for a native output above 4096x2304, the existing compatibility path advertises 4096x2304 and scale 0.5 only while creating each feature, then restores the real evaluation contract.

The signed runtime's private internal network dimensions are not observable. Therefore the 4096x2304 create compatibility value must not be reported as measured neural execution size. Logs and timing CSV report render, work, guide, and game-output dimensions separately.

At 6144x3456, each R16G16B16A16 work surface is about 162 MiB. Multipass adds the B surface and two additional persistent Feature 18 histories. Runtime-owned history memory is unknown; three passes can materially increase VRAM use or fail allocation.

## GPU timing and exact counts

The branch artifact is built with `DLSS5_GPU_TIMING=1`. `dlss5-gpu-timing.csv` uses Vulkan timestamp queries for:

- encode;
- Feature setup/create GPU interval (kept separate from inference);
- Feature 18 pass 1, pass 2, and pass 3 intervals;
- aggregate Feature 18 interval;
- decode and tail.

Per-pass intervals include the required inter-pass Vulkan image-layout synchronization. They are GPU timestamps, not CPU command-recording/QPC durations. The CSV also records configured/attempted/successful passes and cumulative per-layer Create/Evaluate call counts. The existing D3D12 total timestamp remains separate; if unavailable, `total_ms` and `copy_interop_ms` are `-1`.

## Build and checks

```bash
make -C service multipass
python3 tests/test_multipass_static.py
mkdir -p build/tests
g++ -std=c++20 -Wall -Wextra -Wpedantic -Werror \
  tests/multipass_policy_test.cpp -o build/tests/multipass_policy_test
build/tests/multipass_policy_test
```

Deliverable:

```text
service/build/multipass/01-dlss5-post-service.addon64
```

The build only compiles local source. It performs no deployment and launches no game. Compilation and static tests are not evidence of functional Cyberpunk 2077 execution; deployment, GPU benchmark, image inspection, and timing validation remain required.

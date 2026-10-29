# Native Linux GL/CUDA IPC producer

`gl_cuda_ipc.cpp` implements the native side of
`dev.local.nrbridge.NativeIpc`. It is a Linux producer: a private CUDA context
on the device matched by `cuGLGetDevices` registers four Java-owned OpenGL 2D
textures and exports four genuine CUDA IPC allocations. The mmap file is CPU
control data only; image pixels never pass through it.

## Exact JNI API

```java
static native long open(String controlPath,
                        int colorTex, int depthTex, int motionTex, int outputTex,
                        int width, int height,
                        int activeWidth, int activeHeight);
static native int evaluate(long handle, long frameId, int mode, boolean reset,
                           float intensity, int timeoutMs);
static native String status(long handle);
static native void requestStop(long handle);
static native void close(long handle, boolean peerExited);
```

The exported symbols are
`Java_dev_local_nrbridge_NativeIpc_{open,evaluate,status,requestStop,close}`.
`open` throws `IllegalStateException` and cleans its private partial state if
creation fails. Invalid handles and an unsafe `close` also throw. A fatal bridge
error is reported by `evaluate == -1`; waiting, skipped, timed-out, and late
frames return `0`; only a result completed in the same `evaluate` call and
copied to the output texture returns `1`.

The texture requirements are exact:

| Plane | GL level-0 internal format | CUDA registration |
|---|---|---|
| color | `GL_RGBA32F` | read-only |
| depth | `GL_R32F` | read-only |
| motion | `GL_RG32F` | read-only |
| output | `GL_RGBA32F` | write-discard |

All four must be distinct `GL_TEXTURE_2D` objects with level-0 dimensions
exactly `width * height`. Padded and active dimensions must be positive and at
most 8192 on each axis, padded pixels must not exceed `MAX_PIXELS`, and the
active top-left crop must fit exactly inside the padded image. `open` must run
with the owning GL context current. It creates `controlPath` exclusively with
mode 0600, maps exactly 4096 bytes, and does not use SCM_RIGHTS.

The producer creates a private CUDA context and pops it after every operation,
restoring any CUDA context that was current on the calling thread. It never
resets a CUDA device or a primary/global CUDA context.

## Frame and lifetime rules

`evaluate` clamps `timeoutMs` to 1..250 ms (the intended main-loop value is 100
ms). It accepts mode 1 (`COPY`) or 2 (`NR`). It only submits while the backend
is `READY` and no old sequence is outstanding. The three input GL arrays are
mapped and copied directly to exported linear device allocations with
`cuMemcpy2DAsync`; an event must report completion before `request_seq` is
release-published.

After publication, those allocations are not touched again until that exact
sequence is acknowledged. If the bounded same-call wait expires, later output
for that sequence is discarded and is never mapped into the GL output. A
skipped, timed-out, failed, or late frame causes the next submitted request to
carry reset. A same-call successful result is copied directly from the output
IPC allocation to the mapped output GL array. CUDA unmap transfers ownership
and establishes ordering for later GL use; there is no texture upload or
readback on the CPU frame path.

CUDA's GL map/unmap entry points can themselves block in the NVIDIA driver on
prior GL/CUDA ownership even though event and backend polling have a bounded CPU
wait. No unbounded GL semaphore wait is used.

`requestStop` release-stores the shared `shutdown` word. `close(handle, false)`
refuses to free unless the peer published `STOPPED`; `close(handle, true)` is an
explicit caller assertion that the peer process has exited. Both paths also
refuse while the producer CUDA stream still has work. This prevents implicit
freeing while Wine still imports or operates on an allocation. Call methods
serially with respect to `close`.

`status` is JSON and includes `submitted`, `completed`, `timeouts`,
`late_discarded`, backend Feature18 `evaluations`, `gpu_ms`, `state`, and
`error`, plus producer `evaluate_calls`, sequence, shutdown, reset, and
local-work diagnostics.

## Build

```bash
cd /home/user/rt_5090_project/minecraft_nr_bridge
native/build_native.sh
```

Defaults are `/opt/cuda/include`, `/usr/lib/libcuda.so`, and
`/usr/lib/jvm/java-25-openjdk/include`. Override `CUDA_HOME`, `JAVA_HOME`, or
`CXX` if needed. Outputs stay in the project and are not installed into the
game:

- `build/native/libmcnr_gl_cuda_ipc.so`
- `build/native/native_ipc_smoke`

## Isolated smoke harness

Do **not** run these high-resolution checks while Minecraft or another heavy GPU
workload is open. The harness creates an invisible GL 4.5 window, initializes
all input textures on the GPU, and reads only a 12-byte reduction result back to
the CPU. It writes no raw image files and performs one requested evaluation.
The producer creates the control file first, so start the harness in terminal A
and the backend in terminal B after the harness prints `control file created`.
Set the logged-in display environment if the shell does not already have it.

1920x1080 COPY identity:

```bash
# terminal A
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.CURRENT \
  build/native/native_ipc_smoke \
  --control /tmp/mcnr-smoke-1080.control --mode copy \
  --width 1920 --height 1080 --active-width 1920 --active-height 1080

# terminal B, after the file-created line
 tools/run_nr_backend.sh /tmp/mcnr-smoke-1080.control
```

6144x3382 active image in a 6144x3392 padded allocation:

```bash
# terminal A
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.CURRENT \
  build/native/native_ipc_smoke \
  --control /tmp/mcnr-smoke-6k.control --mode copy \
  --width 6144 --height 3392 --active-width 6144 --active-height 3382

# terminal B
 tools/run_nr_backend.sh /tmp/mcnr-smoke-6k.control
```

Real NR finite/nonidentity (pre-create Feature18 before `READY`):

```bash
# terminal A
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.CURRENT \
  build/native/native_ipc_smoke \
  --control /tmp/mcnr-smoke-nr.control --mode nr \
  --width 1920 --height 1080 --evaluate-timeout-ms 250

# terminal B
 tools/run_nr_backend.sh /tmp/mcnr-smoke-nr.control --nr
```

Timeout/late-result immutability uses a 1 ms NR request and requires that input
preparation finishes soon enough for the request to be published. It fails
rather than claiming coverage if the timeout occurred before publication:

```bash
# terminal A
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.CURRENT \
  build/native/native_ipc_smoke \
  --control /tmp/mcnr-smoke-timeout.control --mode timeout \
  --width 1920 --height 1080

# terminal B
 tools/run_nr_backend.sh /tmp/mcnr-smoke-timeout.control --nr
```

On a pass the harness stores shutdown, waits for `STOPPED`, then closes the
producer and deletes its GL objects. It deliberately waits instead of freeing
IPC allocations while the backend may still import them. Replace `CURRENT`
with the current Xwayland authority filename; do not copy a stale example
literally.

## Subsequent main-agent integration verification (2026-09-09)

The worker-only unverified status above is historical. Main subsequently ran
real Java/JNI/GL3.3/CUDA/Wine COPY and Feature18 tests at1080p and6144x3382
(active)/6144x3392(padded), plus a genuine post-publication timeout/late-discard
test. All passed. See ../README.md and benchmark_logs/mc-java-cuda-ipc-6k-final-20260909-0451.
Native defaults are now published explicitly (tone1/structure1/skin-1/style0/AutoMask0),
and COPY preserves the pending NR reset. Application launch uses direct exec
Wine, not the standalone timeout wrapper, to make importer process lifetime
observable by Java. The running game has not yet received0.2.0.

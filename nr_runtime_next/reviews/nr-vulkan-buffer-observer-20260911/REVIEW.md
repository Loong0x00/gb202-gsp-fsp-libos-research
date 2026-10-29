# Vulkan activation-buffer observer — CPU/crossbuild preparation only

## Result / provenance

Prepared an isolated extension of **Main NORMALRESERVE observer v3**, cloned from `../nr-static-followup-main-20260911/source`.

- Original runtime: `bf97610fb7bbc12a6b7046668260c27bf2886205bae911c6686ee33faa5aad72`.
- Candidate: `source/native/buffer-build/dlss5-native-runtime.dll`.
- Candidate SHA256: **`0fef444c8461b2cf6faeabfd429ff8020064394bd7186cb0710cafbb8f54d24b`**.
- **41 CPU test modes pass; the same 41 pass ASan + UBSan with leak detection.** Runtime-only MinGW crossbuild passes. Six runtime exports and PE imports match the original; PE timestamp is zero.
- Complete 92-file original-source manifest verified unchanged. Only two existing clone files differ: observer core and a test's explicit `return 0`. New files are listed below.
- No Wine, Windows/native runtime, GPU workload, CUDA patch, deployment, package change, host/boot rebuild, or readback was performed. The worker0 architecture/CUDA patch was never used. The original pixel acceptance is inherited provenance, **not pixel verification of this candidate**.

`BASE_SOURCE_HASHES.json`, `SOURCE.diff`, `PINS.json`, `SOURCE_CHECKS.log`, `BUILD_CPU.log`, `SANITIZERS.log`, and `DLL_PE.txt` contain the evidence. `SOURCE_CHECKS_INITIAL.log` preserves a checker-only failed assertion that assumed UTC in objdump's local-time rendering; verification now reads the actual PE timestamp field, which is zero.

## Observer behavior

Existing exact `D5R_FINALPOST_TRACE=OWNED_STATIC_OFFSCREEN` opt-in and Windows IO remain unchanged. Opt-out still **literally returns the original GIPA/GDPA pair**, without setup or extra reads. Prebootstrap identity IAT, NR initialization/parameters, reserve policy, module capture/hash implementation, and finalpost parameter ABI/extra-buffer gates are unchanged.

New intercepted names, in addition to the existing NVX three:

| API | Observation |
|---|---|
| `vkCreateBuffer` | Host size/usage before call; only `VK_SUCCESS` binds the returned nonnull handle. Failed calls do not read the output or retire an existing generation. |
| `vkDestroyBuffer` | Retire the owned-device handle **before** forwarding; null destroy is a no-op. |
| `vkGetBufferDeviceAddress` | Exact core typed slot, unchanged info pointer and returned base. |
| `vkGetBufferDeviceAddressKHR` | Separate exact KHR typed slot/wrapper. |
| `vkGetBufferDeviceAddressEXT` | Separate exact EXT typed slot/wrapper (`VkBufferDeviceAddressInfoEXT` is the header alias). |

All five have **independent instance-query and device-query original slots and wrappers**. Vulkan PFN compile-time assertions pass in CPU and x64 crossbuilds. Every resolver and Vulkan callback is forwarded exactly once, with original handles, pointers, allocator, structure bytes, and result. Original calls execute outside the observer mutex. Fake originals re-enter setup under a timeout to test that property. Observer exceptions are contained; they never synthesize a Vulkan result. Exception containment applies to the observer, not C++ exceptions illicitly thrown by an external Vulkan implementation.

The table has **4,096 live slots**, no heap-backed metadata container and no eviction of live entries. Generations distinguish reused handles; every observed successful reuse clears its previous address. Destroy/query races cannot attach a returned address to a later generation. Attribution is suppressed while any tracked buffer call is in flight. The unsigned generation counter fails closed at exhaustion. Creation/address/destruction metadata logging is capped at 256 events, reserving room in the unchanged 4,096-line trace for finalpost reports. Table tracking continues after this metadata-log cap.

Create metadata supports a bounded eight-node **CPU-only** pNext walk for external-memory buffer info, buffer opaque capture address, EXT device-address create info, NV dedicated allocation info, and KHR usage-flags2. Usage-flags2 overrides legacy usage, with all 64 bits retained. Unknown/unreadable/cyclic/oversized chains, duplicate usage2, zero size and sparse buffers are not guessed. Extension values, queue-family arrays, and allocator payloads are never modified or followed into GPU memory.

### Fail-closed rules

Unknown successful-create handle/metadata, missing observed create/destroy resolver coverage at creation, unknown address/destroy handles, device mismatch on an issued wrapper, table/generation exhaustion, changed dispatch pointer, unreadable resolver name, observer read exception, address-generation race, changed nonzero base, and overflowing `[base,base+size)` each disable attribution for the rest of this observer instance. Existing issued wrappers still forward their original targets; a changed resolver target is returned untouched. Failed creates alone do not invalidate an otherwise known live record.

A zero returned base has no interval. A later first nonzero base can become known. The endpoint calculation rejects overflow; `base+size == UINT64_MAX` is representable, with UINT64_MAX itself excluded by the half-open interval. Multiple matching observed intervals are ambiguous and do not produce an association. Buffers can be separately attributed only where exactly one observed interval contains the pointer.

## Finalpost report contract

After the **unchanged exact module hash, exact kernel name, and 184-byte CPU aggregate gates**, the observer copies four 64-bit integers from its already-captured local snapshot:

| Label | Hex byte offset |
|---|---:|
| `main` | `0x00` |
| `enc0skip` | `0x08` |
| `weights` | `0x18` |
| `blend` | `0x68` |

These integers are compared against table intervals; **they are never cast to readable GPU pointers or passed to the host reader**. The original aggregate and parameter/extra arrays are unchanged. 312-byte variants still follow the original capture behavior, without these 184-byte field interpretations.

Each field logs either:

- `attribution=one_observed_live_buffer`, with owned device, handle, generation, base, size, buffer-relative offset, `available_bytes = size - offset`, and effective usage; or
- `attribution=none`, with unknown-coverage/inflight, no-live-interval, or ambiguous-overlap reason.

An additional `activation_all_four_same_observed_live_buffer=yes|no_or_unknown` distinguishes four pointers sharing one buffer from pointers individually mapped to separate buffers. The four individual records remain authoritative. Log phase is **before original submission, not GPU completion**; if later snapshot saving fails, the normal artifact failure is retained and the run does not become accepted evidence.

## Scope and Main-only next gate

**There is no actual activation-buffer identity or GPU byte result yet.** This is preparation for Main's later owned readback review, not authorization to copy anything.

Coverage is explicitly limited to the one owned device's supplied Init GIPA/GDPA stream. The observed NVX function supplies the owned-device scope; Vulkan command buffers have no device argument. **Command-buffer ownership and use of the supplied resolver stream remain the existing Main harness preconditions**, not facts inferred from opaque handles. Other resolver routes (including original GDPA obtained indirectly through GIPA), pre-observer allocations, unobserved direct calls, memory binding/freeing, and command-buffer ownership are not globally instrumented. Foreign resolver queries return their original results without recording foreign buffers. A matching integer is not an association to a foreign device. Main must not interpret this as a complete Vulkan layer or as evidence if those preconditions are unknown.

The report proves at most a unique **fully observed buffer lifecycle/address interval within that stream**. It does not prove tensor extent/layout, current memory contents, completion, visibility, memory binding validity at a later instant, absence of unobserved aliases, transfer-source legality, or physical allocation ownership. `available_bytes` is only the bytes remaining in the recorded logical buffer. Sticky drops, unknown/ambiguous fields, missing files, or resolver bypass are **no attribution**, not negative model evidence.

Only Main may later separately approve/run an offscreen candidate comparison and require complete traces, unchanged pixel/output acceptance and exact original module/184-byte contract. Any later readback must independently establish ownership/lifetime, required existing usage bits, valid byte ranges and synchronization. **This patch adds no usage flags, copies no GPU memory, inserts no barriers, maps no native buffers, allocates no GPU resources and changes no NR parameters.** A complementary disassembly audit of signed NR's allocation flags was not undertaken; actual observed usage is the primary planned evidence.

## Files changed in the isolated clone

Paths relative to this review directory (the old source remains untouched):

- `source/native/runtime/finalpost_observer.cpp`: buffer route/state integration, exception fail-closed flag, dispatch substitutions and post-snapshot attribution hook.
- `source/native/runtime/finalpost_buffers.h`: private fixed-capacity metadata and exact typed dispatch slots.
- `source/native/runtime/finalpost_buffers.inc`: read-only buffer metadata/lifetime/address wrappers and four-field interval reporting.
- `source/native/tests/finalpost_buffers_test.cpp`: production-core fake Vulkan tests, reusing the original NVX harness.
- `source/native/tests/finalpost_observer_test.cpp`: explicit `return 0` so the unchanged test harness can also be included with its main function renamed.
- `source/native/Makefile.buffer-review`: restricted CPU tests/runtime-DLL-only crossbuild targets; original Makefile unchanged.
- `verify_source.py`: manifest, exact ABI logic, forbidden-operation and PE checks.
- Review documents/manifests/logs/diff and generated `source/native/buffer-build/` and `source/native/buffer-build-sanitized/` artifacts.

The inherited `source/native/build/` binaries are unchanged provenance and **are not the candidate**. Candidate DLL is only at the `buffer-build` path above.

## Reproduce (CPU/crossbuild only)

From this review directory, use a temporary directory here:

```sh
mkdir -p tmp
export TMPDIR="$PWD/tmp"
make -C source/native -f Makefile.buffer-review cpu-test runtime-only
ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 \
make -C source/native -f Makefile.buffer-review BUILD=buffer-build-sanitized \
  CPU_FLAGS='-std=c++20 -O1 -g -Wall -Wextra -Wpedantic -Werror -Wno-missing-field-initializers -pthread -fsanitize=address,undefined -fno-omit-frame-pointer' cpu-test
python3 verify_source.py
```

The 35 new buffer modes cover core/KHR/EXT on both resolver routes, exact forwarding, failed creates, null/foreign/changed resolvers, zero/overflow/end boundaries, unknown metadata/handles, device mismatch for each API family, successful reuse/retirement, same/different/overlapping buffers, sticky unknowns, sparse rejection, usage2/external-memory metadata, pNext cycles, table saturation/reclamation, exceptions/output-read failure, in-flight suppression and generation changes during a real callback. Six unchanged NVX modes cover baseline, normal flow, limits, failures, exact fatbin-extra ABI and wrong hashes. New tests also verify unknown NVX functions and wrong hashes never trigger buffer attribution.

# MODS 570.151 test 351 `NewCudaL2Mats` native/JS cross-check

Status: **final, static-only**  
Date: 2026-07-21

## Scope and result

This is an independent cross-check of test 351 in the already extracted MODS
570.151 package. It used only decoded JavaScript, ELF metadata, bounded native
string windows, RTTI strings, and a streaming string check of the ELF fatbin
section. MODS was not executed; no GPU, CUDA device, driver node, PCI/BAR/MMIO,
reset, or firmware interface was accessed. No full disassembly or Ghidra
analysis was performed.

The direct result is:

1. Test 351 is **not a distinct native L2-test class**. It is the ordinary
   native `NewCudaMatsTest` with a JavaScript run-name alias and L2-sized
   defaults.
2. Its visible registration and setup are Blackwell-capable: LinuxRM is an
   allowed environment, Blackwell enables `TriadTest`, and the native Triad
   validator's visible architecture floor is SM 8.9. This is strong static
   evidence that the path was intended to include Blackwell, but it is not a
   live acceptance result for this retail GB202.
3. The visible test-351 path sizes one allocation from the **aggregate reported
   `L2CacheSize`**. It has no FBP/LTC/LTS selector and no loop that directs
   traffic to one cache slice.
4. The native class can detect read-data miscompares and failures/corruption in
   its own error-reporting machinery. It can optionally classify bit/burst
   errors and the SM/TPC that encountered a miscompare, but none of those is a
   proved identity for the failing physical LTS.

The inspected ELF is
`mods_audit/static/extracted_inner/mods`, 392,339,552 bytes, SHA-256
`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`.

## FACT

### 1. Test 351 is a configured generic `NewCudaMatsTest`

`mods_audit/static/decoded/all/gpudecls.js:451` registers:

```text
NewCudaL2Mats, 351, NewCudaMatsTest, NewCudaL2Mats,
SetupNewCudaL2Mats, ... OS_LINUXRM ..., DT_GPUS, TT_PIPELINEABLE
```

The `CUDA_CHANGE_RUN_NAME` mechanism at `gpudecls.js:36-67` creates a prototype
method which only changes the logged run name and calls `this.Run()`. Line 3548
uses it as:

```text
CUDA_CHANGE_RUN_NAME("NewCudaMatsTest", "NewCudaL2Mats")
```

An exact ELF string check found zero occurrences of `NewCudaL2Mats` but eleven
occurrences of `NewCudaMatsTest`. The native RTTI window at ELF file offsets
approximately `151383668..151384549` contains `15NewCudaMatsTest`,
`NewCudaMatsTest::NewCudaReportedError`, and six lambda type names belonging to
`NewCudaMatsTest::SetupMemError`. Therefore the visible native implementation is
the generic memory-test class; the L2 specialization is the JavaScript setup,
not a separate native class.

### 2. Visible Blackwell/GB202 support gates

- `gpudecls.js:451` allows client-side RM, Android, DA, and LinuxRM, and targets
  GPU devices.
- `SetupNewCudaL2Mats` at `gpudecls.js:3515-3548` does **not** add an
  `IS_SUPPORTED` callback. This differs from legacy `CudaL2Mats`, whose explicit
  callback at lines 5305-5323 rejects GA10x-and-newer devices without a uGPU.
- The test-351 setup enables `TriadTest` when
  `BoundGpuDevice.Family >= Gpu.Blackwell` (`gpudecls.js:3522-3526`).
- The native `NewCudaMatsTest` string group contains
  `TriadTest is only supported on SM 8.9+.` at ELF file offset `143635248`.
  Thus the visible Triad-specific check is a lower bound, not a Blackwell
  rejection.
- The ELF `.nv_fatbin` section contains many `-arch sm_120` and `-arch sm_120a`
  records. This proves the package as a whole carries Blackwell-generation CUDA
  code objects; strings alone do not bind any particular one of them to
  `NewCudaMatsTest`.

No bounded native string in the `NewCudaMatsTest` group stated a GB202/SM120
rejection. That negative string result is not proof that the stripped C++ class
has no other generic CUDA/device support check.

### 3. What the L2 mode actually configures

`SetupNewCudaL2Mats` sets (`gpudecls.js:3515-3544`):

- `UseRandomData = true`;
- `TriadTest = true` on Blackwell and newer;
- `Iterations = 1024` and `MaxInnerIterations = 1024`;
- `RuntimeMs = 5000`;
- `MaxFbMb = FrameBuffer.L2CacheSize / (1024 * 1024)`.

The minimum-time override reduces this to one outer/inner iteration and disables
the fixed runtime; it does not alter cache routing.

The native property help describes Triad as:

```text
RRW memory test (perform 2 reads for every write, good for testing L2)
```

This string is at ELF file offset `143638232`. The same native group emits
`Requested MaxFbMb <= L2 size. Test will auto-optimize for L2.` at offset
`143635752`. Together with the JS assignment, this proves that the normal
test-351 specialization is selected by aggregate allocation size plus an RRW
access mode, not by a topology identifier.

### 4. No exposed per-FBP/LTC/LTS direction in test 351

The native `NewCudaMatsTest Js Properties` string block at ELF offsets roughly
`143630256..143640128` lists iteration, allocation/range, block/thread,
pattern/random/bus/Triad/read/write, pulse/power, and error-reporting controls.
It contains no FBP, LTC, LTS, slice, or raw-fuse-bit selector.

There are three nearby features that must not be mistaken for such a selector:

1. **`StartPhys` / `EndPhys`:** the native validator says
   `Cannot specify StartPhys or EndPhys if not testing client-mapped memory!`
   (ELF offset `143635520`). Even where a physical interval is accepted, the
   interface names an address interval, not an FBP/LTC/LTS, and this package
   exposes no address-to-one-LTS routing guarantee for test 351.
2. **`RunExperiments`:** the native class has a Boolean described only as
   `Runs perfmon experiments along with the test.` Test 351's setup does not set
   it, and its visible JS setup creates no experiment. By contrast, the
   separate legacy `CudaL2Mats` wrapper explicitly calls
   `CreateL2CacheExperiment(fbp, slice, ...)` in
   `gputest.js:12892-12925`. That explicit per-slice loop is absent from test
   351.
3. **`FbDecode` in error handling:** RTTI proves that
   `NewCudaMatsTest::SetupMemError` receives `MemError::ErrorRecord` and
   `FbDecode` objects. This is an error-decoding/reporting path; it is not an
   exposed pre-run cache-routing selector.

There is also a distinct post-Hopper, two-uGPU CTC/HBI wrapper at
`gpudecls.js:14786-14870`. It launches one `NewCudaL2Mats` per uGPU and can set
`ComputeUgpu` / `MemoryUgpu`. Its own support callback requires
`UGpuCount == 2`, and its localization is at uGPU/die memory granularity—not
FBP/LTS granularity. It does not establish a slice selector for a normal
single-die GB202 test-351 run.

### 5. Errors the native class visibly handles

The bounded native string group proves handling for:

- a data-test failure after some iteration
  (`NewCudaMats: Failure detected after ...`, offset `143633880`);
- expected allocation versus actual allocation mismatch;
- unsupported or untestable physical ranges;
- invalid combinations such as Triad without random data, Triad with random
  access, and Triad below SM 8.9;
- a corrupt or inconsistent error-results buffer, including reported/consumed
  count mismatch and an "actual" value equal to the expected value;
- more detected errors than the reporting limit.

The native property/help block also exposes optional:

- `ReportBitErrors` and `ReportBurstErrors`;
- an overflow error buffer and selectable flush depth;
- `ReportFailingSmids`, documented as reporting the SMID and hardware TPC that
  **encountered a miscompare**;
- `SkipErrorReporting`.

Some of these are conditional. The same validator says bit-error reporting
arguments require client-mapped memory, burst reporting requires the relevant
32-byte read ISA support, and bit-error reporting is currently dGPU-only.
Test 351's JS setup does not explicitly enable these optional reporters.

No native property or diagnostic in the bounded `NewCudaMatsTest` group names
an L2 ECC-counter check, L2 tag-array test, per-LTS pass/fail result, or a
raw-fuse-bit identity.

## INFERENCE

1. The Blackwell branch plus the native SM-8.9 lower bound makes test 351 a
   plausible **aggregate post-change stress test** on GB202, subject to the
   remaining runtime/provenance constraints.
2. If RM reports a larger `L2CacheSize` after a configuration change, the JS
   default should scale the requested working set to that new aggregate size.
   If the reported property remains unchanged, this setup has no independent
   knowledge of extra physical cache.
3. Two reads per write and a working set no larger than reported L2 should
   create substantial L2 traffic and can expose data-consistency faults that
   manifest under the selected addresses and patterns. Equal allocation and
   cache capacity do not ensure every set, way, bank, tag path, or replacement
   state was reached.
4. A reported failing SMID/TPC identifies the execution unit that observed bad
   data. It does not by itself identify the cache slice that produced the data.
5. `FbDecode` may enrich a failing-address report with framebuffer topology,
   but the inspected strings do not prove an LTS field, stable raw-bit mapping,
   or a facility to route the next access exclusively through that decoded
   unit.

## UNKNOWN

1. Whether the stripped native class has an additional non-string support gate
   that rejects the exact retail GB202/RTX 5090 configuration.
2. Whether the particular SM120 code object used by `NewCudaMatsTest` is native
   SM120 code or another compatible/fallback image; the package-wide fatbin
   strings do not establish that binding.
3. The exact address hash/interleave used by GB202 and whether any accepted
   physical interval could be constructed to isolate one FBP/LTC/LTS.
4. Coverage of all data arrays, tags, sets, ways, banks, ECC paths, replacement
   state, and coherence paths in an enabled unit.
5. Whether correctable/uncorrectable L2 ECC events or asynchronous Xids are
   converted into the test's own return code when no CUDA data miscompare is
   observed.
6. Stable correspondence among a raw floorsweep bit, post-reset logical LTS,
   `FbDecode` output, and a physical cache macro.
7. Whether a faulty newly enabled unit could corrupt display/driver/GSP traffic
   before this aggregate test reports a failure.
8. Runtime safety and provenance of the downloaded MODS binary. Nothing in this
   static test-capability review changes the existing decision not to run it on
   the desktop GPU.

## Cross-check against `mods_l2_test_boundary.md`

The earlier report's principal result is confirmed: test 351 is
Blackwell-aware and aggregate-L2-sized, while the visible genuinely per-slice
perfmon wrapper is the older path that rejects ordinary GA10x-and-newer
non-uGPU devices.

This review adds four narrower facts:

- `NewCudaL2Mats` is only a JS run-name alias over native
  `NewCudaMatsTest.Run()`;
- native Triad's visible architecture gate is SM 8.9+;
- native `StartPhys`/`EndPhys`, error decode, and SMID reporting do not amount to
  an LTS targeting interface;
- the only visible localization reuse of test 351 is two-uGPU/die-level CTC/HBI
  setup, not FBP/LTS selection.

## Minimal conclusion

MODS 570.151 contains a generic CUDA memory comparator configured by test 351
to keep a random RRW working set at or below the currently reported aggregate
L2 capacity. Its visible Blackwell gates are compatible with GB202, and it can
detect data miscompares under the traffic it generates. It still provides no
proved way to direct the test to one newly enabled FBP/LTC/LTS, no exhaustive
L2-array/ECC certificate, and no stable mapping from a failure back to one raw
floorsweep bit.

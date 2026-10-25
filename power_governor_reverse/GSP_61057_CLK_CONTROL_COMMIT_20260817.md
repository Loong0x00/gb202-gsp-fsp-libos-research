# GB202 clock-domain CONTROL commit path

This note separates three things that were previously easy to conflate:

1. writing a public CLK_DOMAIN control record;
2. applying the BoardObj control group in GSP-RM;
3. loading the resulting PS3.0 Perf/Volt/Clock state toward PMU execution.

No GPU or MODS code was executed to obtain this result.  The evidence is static
R610.57.04 GSP-RM code plus a GB202 R570.151 MODS cross-build control.

## Current R610.57.04 path

`subdeviceCtrlCmdClkDomainsSetControl` at `0x010f46d8` resolves the clock-program
group at `manager+0x1150`, obtains state 1, and calls its `+0x28` method.  The
constructor at `0x01102b5c` assigns that method to `0x010fae18`.

Raw RISC-V decoding of `0x010fae18` establishes this sequence:

```text
pPerf = *(pGpu + 0x1f98)
status = BoardObjGrp CONTROL apply(...)
if status == 0:
    target = *(pPerf + 0x560)
    status = target(pGpu, pPerf)
```

The decisive instructions are `ld a5,0x560(s4); jalr a5`. Thus `+0x560` is a
direct per-object callback slot, not a second-level C++ vtable offset. The
exact exported bytes are preserved in
`gsp61057_perf_post_clock_apply_exact.bin`; the continuity-checked Capstone
decode is `gsp61057_perf_post_clock_apply_exact.capstone.asm`. The older
`gsp61057_clk_program_apply_range2.asm` starts at `0x010faf04` and is not raw
evidence for this function.

The object identity is current-build evidence. Exact class-ID dispatch at
`0x0141f1c0`, plus the matching generated R610 headers, gives:

```text
pGpu + 0x1f88 -> ClockManager, class 0x00bcadd3
pGpu + 0x1f90 -> Fan,          class 0x00add018
pGpu + 0x1f98 -> Perf,         class 0x00ed0b65
pGpu + 0x1fa0 -> KernelPerf,   class 0x00c53a57
```

ClockManager descriptor `0x01c49aa8` has size `0x1bb0` and constructor
`0x018dc860`. Perf descriptor `0x01c77fa0` has size `0x8f1e0` and constructor
`0x019df2a0`. Therefore this path applies a ClockManager-owned BoardObj group,
then invokes a callback owned by the separate Perf object.

The Perf constructor initializes its direct method area only through byte
`+0x2a8`; `+0x560` is still zero after construction. Its adjacent `+0x568`
field is initialized by `0x019df0a0` to point at a separately allocated
0x68-byte object and does not back-fill `+0x560`.

The later installation is now closed. `Perf::initLocked` at `0x0164bb38`
calls `0x016a9f40(pGpu,pPerf)`. Raw CFG from that entry proves `s2=a1`, then
`0x016ab146` writes target `0x016abaf4` to `pPerf+0x560` and sets
`pPerf+0x2ed=1`. Target `0x016abaf4` is a seven-instruction return-zero stub.
Thus the SET_CONTROL path still calls the slot for ABI compatibility, but the
slot itself performs no re-evaluation or load on this build.

Two exact false positives are now excluded. At `0x01933e5a`, the apparent
`sd ...,0x560(a2)` is preceded by `c.lui a2,0x1; c.add a2,s1`, so its effective
destination is `s1+0x1560`, not `s1+0x560`. Separately, constructor
`0x0198785c` allocates a nested 0x11b8-byte object and writes that object's
index `0xac` (`+0x560`); it is not the 0x8f1e0-byte Perf object. The raw
pre-bias sequence and nested allocation are regression-checked so neither can
silently become the claimed Perf installer.

There is now a stronger same-generation semantic anchor for that open slot.
In GB202-capable R570.151 MODS, both the ordinary caller at `0x06ee8a00` and
the deferred-load caller at `0x0724fb21` pass `(pGpu, pPerf)` to
`0x071cd890`. The first caller reports any nonzero result with the literal
`NVRM: Perf load failed (0x%08x)`; the second is bracketed by the literals
`Initiating deferred Perf load` and `Deferred Perf load complete/failed`.
Inside `0x071cd890`, enabled state at `pPerf+0x366` causes a request to PMU
unit `0x1c`. Thus `perfLoad(pGpu, pPerf)` is an evidence-backed semantic name
for that particular R570 MODS function. It is not a safe name for the current
R610 slot.

The intervening R570.144 GSP image closes the layout correspondence and shows
a real version transition. Function `0x010e3d58` repeats the
post-clock chain using `gpu+0x1c20 -> ClockManager`, `gpu+0x1c30 -> Perf`, and
`Perf+0x4d8`; relative to R610, the Perf callback moves by exactly `+0x88` to
`+0x560`. Other R570.144 callers invoke the same `+0x4d8` slot as either
`callback(pGpu,pPerf)` or `callback(pGpu,pPerf,out_u32,0,mode)`. R570
`Perf::initLocked` calls `0x01637864`, which conditionally installs no-op
`0x01625810` or active `0x01639f44`; the latter sends PMU
`0x1300/type-0x0c`. The runtime capability bit selecting those branches is
still unknown, but both concrete implementations are now recovered.

R610 moves the active work to callbacks `0x016aedcc` and `0x016bcc80`,
registered with contexts `pPerf+0x338/+0x340`. They exchange exact
`0x214`-byte PERF/type-0x0c and `0x54`-byte PERF/type-0x0d packets. Selected
returned domain words are cached at `pPerf+0x368+0x20*i` before ClockManager
post-apply processing. See `GSP_61057_PERF_EVENT_PROTOCOL_20260817.md`.

That apparent final ClockManager post-apply edge is now closed as a no-op, not
as a hardware programmer. The finalizer loads ClockManager from
`pGpu+0x1f88`, selects the object at `ClockManager+0x1168`, and calls its direct
slot `+0x8ee8`. A raw affine-address scan of the R610 image found one direct
constructor assignment to that slot: `0x01ac2cea` stores target `0x010f1de4`,
whose complete body is `return 0`. The adjacent Pstate finalizer variants at
`0x01690978` and `0x0167ca18` both converge on `0x01ae21d0`; its concrete
`+0x1498` targets are a status predicate or another return-zero stub. Neither
edge performs MMIO clock programming.

## GB202 R570.151 MODS cross-build control

The host-side function at `0x06dd88b0` has a similar two-stage structure, but
its second-stage owner is ClockManager rather than the current R610 Perf
object:

```text
pClk = *(pGpu + 0x1fa8)
status = 0x072f2940(...)                 // CLK_DOMAINS BoardObj SET_CONTROL
if status == 0:
    status = 0x069acd00(pGpu, pClk)
```

`0x069acd00` is a dispatch thunk to the direct `pClk+0x5d8` function slot.  The
caller reports its failure with the literal string `Error loading the PS30
features`.

An earlier draft over-connected that slot to the adjacent function at
`0x069acd10`.  Static evidence proves that `0x069acd10` schedules worker
`0x069ad6e0` once and guards it with the `pClk+0x3c2` in-flight flag.  It also
proves direct wrappers at `0x069661d0` and `0x069661e0` reach this function.
It does **not** yet prove that the GB202-selected value of `pClk+0x5d8` is
`0x069acd10`: no assignment/reference from the slot initializer to that target
has been found, and the multi-architecture ClockManager initializer has both
no-op and non-trivial `+0x5d8` variants.  Therefore the SET_CONTROL-to-worker
edge remains open.

If invoked, worker core `0x069ad0b0` performs the following ordered commit:

```text
Perf-object load
  -> Voltage-object refresh / VFE voltage PERF_LIMITS SET_CONTROL
  -> Clock-program group load
```

The final clock step is `0x06979b30(..., pClk, 1)`, which dispatches the active
clock-program object `+0x1a8` loader.  A conditional path first sends a
unit-`0x0e`, 0x54-byte RPC and copies per-domain returned values into the clock
object before executing the three ordered stages.

## Consequence for the virtual solver

A user frequency offset is not an immediately realized frequency. Current
R610 proves ClockManager BoardObj apply followed by a no-op compatibility
hook; the actual GSP transition is event-driven and exchanges masked
per-domain state with the PMU before ClockManager post-apply processing.
The available R570 artifact separately proves that one PS3.0 worker performs
a joint Perf/Voltage/Clock reload, but it is not byte-identical to R610.
Independent recovered relation, rail and grid
stages already explain why two XBAR offsets can end at the same XBAR clock
while hidden voltage or SYS/NVD state differs, and why the final GPC clock can
differ from the initially selected power-policy candidate.

The simulator exposes this as `stages.control_commit_pipeline`, and
`gpu_inverse/perf_change_protocol.py` executes the exact R610 packet/import
boundary. The clear R570 PMU artifact now supplies both the recovered
multi-domain response solver and the downstream physical clock programmer:
policy types 3/5 reach `0x202ba402 -> 0x202baa54`, per-clock descriptors are
built by `0x202ba85c`, and `0x202bbf3a` saturates and packs the two divider
lanes into MMIO words. `gpu_inverse/pmu_clock_programmer.py` implements that
integer normalization, divider projection, inverse readback, and bit-exact
packing. `gpu_inverse/digital_twin.py` executes this as the final physical
projection. Current R610 `0x0112d0ac` now supplies the exact row-to-PMU wire
map for the divider fields, and the live main-domain lists fix their effective
ratio at 15/2, so the checked-in model executes the divider/readback projection
for GPC/XBAR/SYS/NVD. It still labels the downstream implementation as R570
cross-build and does not invent the unreduced factorization or MMIO lane map.

## Remaining boundary

Confirmed on current R610: the handler, ClockManager BoardObj apply,
`gpu+0x1f98 -> Perf`, direct `Perf+0x560` call, the later slot installation,
its no-op target, both event callbacks, and type-0x0c/type-0x0d wire/import
layouts. Confirmed in R570.144 GSP: the exact `Perf+0x4d8` predecessor,
its `+0x88` slot shift, two observed call ABIs, and conditional no-op/active
targets. Confirmed in the
GB202-capable R570 MODS artifact: the similar `pClk+0x5d8` dispatch and the
separate PS3.0 worker's Perf/Volt/Clock order. Still unknown: the R570 runtime
capability branch, the R570 `pClk+0x5d8`-to-worker edge, the virtual targets
inside parts of the R610 object walk, the current R610 unreduced divider
factorization/object-local source-grid/MMIO lane fields, and the byte-identical
encrypted-R610 equivalents of the clear R570 PMU routines. The PMU
response-producing algorithm and physical packing are
therefore no longer wholly unknown: their exact R570 implementation is
executable, while current-build parameter activation remains an explicit
boundary. No R570 constant is claimed as a measured R610 value.

## Preserved evidence

- `gsp61057_clk_program_apply.c`
- `gsp61057_perf_post_clock_apply_exact.bin`
- `gsp61057_perf_post_clock_apply_exact.capstone.asm`
- `gsp61057_clk_program_constructors.c`
- `gsp61057_classid_dispatch_0141f1c0.c`
- `gsp61057_clockmanager_descriptor_functions.c`
- `gsp61057_clockmanager_classid_hits.txt`
- `gsp61057_perf_descriptor_candidates_words.txt`
- `gsp61057_perf_constructor.c`
- `gsp61057_perf_embedded_568_init.c`
- `gsp61057_01933e52_exact.asm`
- `gsp61057_ctor_0198785c.c`
- `gsp570144_post_clock_slot4d8_20260817.c`
- `gsp570144_slot4d8_call_contexts_20260817.c`
- `gsp570144_perf_constructor.c`
- `gsp61057_slot560_owner_path_20260817.txt`
- `gsp61057_slot560_owner_target_20260817.c`
- `gsp61057_perf_callback_followups_20260817.c`
- `gsp61057_clock_post_finalize_target_010f1de4_20260817.c`
- `gsp61057_raw_affine_8ee8_stores_20260817.asm`
- `gsp61057_final_clock_commit_candidate_01ae21d0_20260817.c`
- `gsp570144_slot4d8_owner_full_20260817.c`
- `GSP_61057_PERF_EVENT_PROTOCOL_20260817.md`
- `mods570_perf_load_impl.c`
- `mods570_perf_load_string_raw_refs.c`
- `mods_clk_domains_apply_ps30.c`
- `mods_clk_ps30_impl.c`
- `mods570_clockmanager_constructor_helpers.c`
- `mods570_ps30_impl_raw_refs.asm`
- `mods_clk_ps30_worker.c`
- `mods_clk_ps30_worker_core.c`
- `mods_clk_ps30_load_subsystems.c`
- `r570_pmu_per_clock_programmer_20260817.c`
- `r570_pmu_clock_program_selection_20260817.c`
- `r570_pmu_program_tuple_and_inverse_20260817.c`
- `gsp61057_clock_table_pmu_transfer_0112d0ac_20260817.c`

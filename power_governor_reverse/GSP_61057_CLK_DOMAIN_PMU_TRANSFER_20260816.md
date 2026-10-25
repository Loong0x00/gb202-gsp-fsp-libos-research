# R610.57 clock-domain GSP/PMU transfer boundary

Date: 2026-08-16  
Safety boundary: offline GSP and same-generation PMU/MODS analysis only; no GPU
query, setter, workload, or MODS execution in this continuation.

## Static R610 transfer ABI

The current R610.57 GSP clock-domain base constructor is `0x010f07dc`; its
derived constructor is `0x010f0f10`. The source-to-transfer serializer
`0x010ee204` copies these GSP object fields:

```text
transfer +0x1c <- object +0x148  u8
transfer +0x1d <- object +0x149  u8
transfer +0x1e <- object +0x14a  u8
transfer +0x20 <- object +0x14c  u32
transfer +0x24 <- object +0x150  u32
transfer +0x28 <- object +0x154  u16
transfer +0x2a <- object +0x156  u16
transfer +0x2c..+0x53 <- object +0x158..+0x17f  (0x28 bytes)
```

The derived serializer `0x010ee478` adds:

```text
transfer +0x54 <- object +0x1a0  u8
transfer +0x55 <- object +0x1a1  u8
```

A second/status-shaped path `0x010ef390 -> 0x010ef544` exports a shorter
projection of the same object fields. These functions serialize state; they do
not contain the PMU frequency evaluator.

## Factory offset crosses the PMU boundary

The public domain INFO exporter `0x010f7840` copies:

```text
public record +0x30 <- GSP domain object +0x160
```

The already recovered public record identifies `+0x30` as
`factory_offset_khz`. Independently, `0x010ee204`'s 0x28-byte block maps:

```text
PMU transfer +0x34 <- the same GSP domain object +0x160
```

This proves the factory offset is transferred toward the PMU object surface; it
is not merely presentation metadata. It does **not** yet prove which current
encrypted-PMU evaluator field consumes transfer `+0x34`, nor that it is one of
the R570 runtime object's `+0x3c/+0x44/+0x80` slots.

## Runtime user offset uses a separate control route

Current R610 user controls are exposed in the 0x83c-byte ClockDomains CONTROL
block:

```text
record = 0x3c + domain_index * 0x40
record +0x08 = frequency-offset mode
record +0x0c = signed frequency offset in kHz
record +0x10 + rail*4 = signed per-domain rail offset in uV
```

The GET handler `0x010ddcf0` enters `manager+0x1148`. The SET handler
`0x010f46d8` instead enters the clock-program/control group at
`manager+0x1150`; its state-1 `+0x28` target is `0x010fae18`. That function
first performs generic BoardObj group apply, then calls the direct function
slot at byte `+0x560` of the object loaded from `gpu+0x1f98`.

Current-build class-ID dispatch proves that object is `Perf` (class
`0x00ed0b65`, size `0x8f1e0`, constructor `0x019df2a0`), not ClockManager.
ClockManager is instead at `gpu+0x1f88` (class `0x00bcadd3`). The exact current
activation boundary is therefore:

```text
ClockManager clock-program BoardObj apply
  -> Perf+0x560 callback(pGpu, pPerf)
```

The Perf constructor leaves `+0x560` zero. The later edge is now closed:
`Perf::initLocked` `0x0164bb38` calls `0x016a9f40(pGpu,pPerf)`, whose raw CFG
writes `0x016abaf4` to `pPerf+0x560` at `0x016ab146` and sets
`pPerf+0x2ed=1`. Target `0x016abaf4` is an exact return-zero stub. Exact
decoding excludes an apparent `0x01933e5a` setter:
its base was pre-biased by `0x1000`, making the effective slot `+0x1560`.
Constructor `0x0198785c` is also excluded because its `+0x560` belongs to a
separately allocated 0x11b8-byte nested object.

A separate R570.151 MODS semantic anchor identifies `0x071cd890(pGpu,pPerf)`
as `Perf load` from exact failure/deferred-load strings. It checks
`pPerf+0x366` and, when enabled, requests PMU unit `0x1c`. The ABI matches the
current R610 callback, but the recovered R610 target proves that ABI shape
alone was insufficient: the current slot is a no-op and does not perform the
MODS operation.

A GB202 R570.151 MODS cross-build closes the role, though not the current
implementation address. Its matching function `0x06dd88b0` loads `pClk` from
`gpu+0x1fa8`, performs CLK_DOMAINS BoardObj SET_CONTROL, then invokes thunk
`0x069acd00`, which dispatches `pClk+0x5d8`. Failure is named `Error loading the
PS30 features`. The same binary contains a PS3.0 worker that commits Perf,
Voltage/VFE-PERF_LIMITS, then Clock-program state in that order, but the
GB202-selected `pClk+0x5d8` value has not yet been proven to select that worker.
See `GSP_61057_CLK_CONTROL_COMMIT_20260817.md`.

Consequently, a user offset cannot be identified with the static factory field
or any single clear-R570 PMU adjustment slot merely because all are expressed
in kHz. After BoardObj apply, the direct R610 hook is inert. Active transition
work instead runs through registered callbacks `0x016aedcc/0x016bcc80`, exact
PMU PERF/type-0x0c and type-0x0d transfers, masked per-domain result import,
and ClockManager post-apply processing. R570.144 independently proves the
`+0x88` slot shift and conditionally selects either a no-op or active
type-0x0c target. The remaining bridge is the PMU algorithm that produces the
returned words, not the R610 slot address. See
`GSP_61057_PERF_EVENT_PROTOCOL_20260817.md`.

## Preserved evidence

- `gsp61057_clk_domain_constructors.c`
- `gsp61057_clk_domain_transfer_methods.c`
- `gsp61057_clk_domain_control_handlers.c`
- `gsp61057_clk_program_apply.c`
- `gsp61057_perf_post_clock_apply_exact.capstone.asm`
- `gsp61057_classid_dispatch_0141f1c0.c`
- `gsp61057_perf_constructor.c`
- `gsp61057_slot560_owner_target_20260817.c`
- `gsp61057_perf_callback_followups_20260817.c`
- `GSP_61057_PERF_EVENT_PROTOCOL_20260817.md`
- `r570_pmu_ordered_adjustment_pipeline.c`

# GB202 R570 PMU PERF task and periodic solver walk

Date: 2026-08-17  
Scope: offline static analysis of the clear GB202 R570 PMU image and the
R570.144/R610.57 GSP images. No live GPU, fan, setter, workload, or MODS
operation was used.

## 1. Correct PMU task routing

The first candidate at `0x202d4518` was a false positive. Its registration
contains `0x13`, but that field is an RTOS task ID. At runtime it accepts only
message unit `local_67 == 0x1b`; its tiny type-`0x0d` handler therefore cannot
be the consumer of GSP's 0x214-byte PERF packet.

The actual incoming unit byte is `local_67`. Multi-unit task `0x202c7b84`
dispatches `local_67 == 0x13` to `0x202c784a`. That handler switches on wire
byte `+0x02`, exactly matching the GSP PERF header `0x1300`:

| Wire type | R570 PMU target | Exact role |
|---:|---:|---|
| `0x00` | `0x202c7814` | BoardObjGroup dispatch; validates group `0x19..0x21` and operation byte |
| `0x0c` | `0x202c7b16` | starts/enables the periodic controller |
| `0x0d` | `0x202b7062` | imports the 0x214-byte per-domain state and computes active entries |
| `0x0e` | `0x202b6f7a` | exports selected cached u32 results into the 0x54-byte mask response |

This closes the GSP-to-PMU identity for the R570 C/group/D/E sequence. The
R610 GSP migration retains the group exchange and renumbers the old large D
and finalize E messages to C and D.

## 2. Large per-domain packet

The R570 type-D handler imports the leading domain mask, copies each active
0x20-byte record, then calls `0x202b71f8` with:

```text
record +0x00  u16 object id
record +0x02  u8  selector/type
record +0x03  u8  validation field
record +0x04  0x18-byte input state
record +0x1c  u32 computed result
```

`0x202b71f8` opens a device-evaluation session, recursively evaluates the
referenced object graph to a float, applies selector-specific transforms, and
writes the converted u32 result. The selector cases are exact; semantic units
for every selector remain unassigned. This is a per-domain input/equation
evaluation stage, not by itself the final clock choice.

## 3. Periodic control sequence

Type C reaches `0x202c88e0`, which enables a timer and registers callback
`0x202c867a`. Its active iteration is:

```text
detect input-object changes
-> refresh/evaluate policy inputs
-> recompute every active 0x20-byte domain record
-> recompute the secondary cached domain group
-> run global domain/policy stages
-> run the multi-voltage stage
-> optionally emit PERF/type-0x02 0x54-byte asynchronous results
```

The top-level calls and current clear-image behavior are:

- `0x202c7dd6`: input refresh, limit stage, and per-domain stage;
- `0x202c7e16`: limit commit, policy arbitration, domain commit, then two
  cross-task notifications;
- `0x202cbb00`: voltage preparation and voltage application;
- `0x202cca6a`: return-zero in this image; it is not evidence that all clock
  programming is absent, because domain commit and the notified tasks remain.

## 4. Multi-voltage update structure

`0x202bd63a` applies a 32-entry request matrix. Each active entry has a
three-bit rail mask and three signed u32 values. All values land in the same
internal matrix at:

```text
state + 0x5f4 + domain_index*0x10 + rail_index*4
```

Mode byte zero adds the signed values; nonzero mode replaces them. Only rail
indexes 0..2 are accepted. A separate commit byte determines whether the
updated matrix is merely cached or starts the asynchronous voltage transition.

Before commit, `0x202cb3d0` evaluates up to five referenced equation objects,
adds per-object signed offsets with negative-to-zero clamping, finalizes each
candidate, and stores three ordered candidates plus their minimum. The exact
object-field layout and min operation are recovered, but mapping those object
indexes to the current R610 physical NVVDD/MSVDD rails is not yet proven.

## 5. Late directional clock clamp

The recovered clock-domain path also has a now-executable late clamp at
`0x202c9a06`. After ordered adjustment objects, a domain frequency below its
base is raised to at least `base + object[0x36]`; one above its base is lowered
to at most `base + object[0x38]`. Any change is immediately reprojected through
the active V/F relations. This is an exact additional reason why an initially
selected GPC value need not be the final value, and why a coupled XBAR/SYS
value can converge after apparently distinct offsets. The arithmetic is in
`domain_adjustment.clamp_frequency_to_base_window()`; current R610 object
values are still needed before enabling it by default.

Immediately upstream, `0x202c9662` applies a per-destination unsigned-byte
percentage as exact integer arithmetic:

```text
projected_mhz = floor(source_mhz * percentage / 100)
```

An enabled flag then reprojects that value through the destination domain's
active V/F relations. The floor makes this stage intrinsically many-to-one
(for example, 3000 and 3001 MHz both become 2700 MHz at 90%), before any later
clock grid. `clock_propagation.project_domain_percent()` reproduces it. The
current R610 destination IDs and percentage bytes remain unread private state,
so this mechanism is confirmed but its use for a particular live XBAR/SYS
sample is still conditional.

## 6. Final PMU solver output

`0x202c7fd8` maintains three per-client clock constraint endpoints with the
invariant `lower <= middle <= upper`. If an input violates that order it lowers
`lower` to the minimum of all three and lowers `middle` to `min(middle, upper)`;
it does not raise `upper`. A relation-derived terminal bound independently caps
all three, preserving both raw and bounded forms.

`0x202c840e` serializes those six u32 values, in
`raw-lower/bounded-lower/raw-upper/bounded-upper/raw-middle/bounded-middle`
order, for up to ten clients in each of seven clock domains. It appends up to
four rail results per domain and emits a fixed 0x780-byte `0x1300/type-0x05`
packet. `perf_type5_output.py` reproduces the ordering repair, bound clamp, and
wire layout exactly.

## 7. Exact R570.144 GSP consumer and post-import rewrite

The R570.144 GSP PERF dispatcher receives the same unit/type pair as logical
message 0x1305. At 0x017b5216 it passes message+4 to the capability-selected
handler, and the enabled target at 0x017b5448 -> 0x016254ec is an exact
consumer of the PMU layout:

```text
PMU domain stride       0x110
PMU client stride       0x18
PMU client words        +0x10/+0x14/+0x18/+0x1c/+0x20/+0x24
GSP client stride       0x40
GSP cache destinations  +0x5e4/+0x5e8/+0x5f8/+0x5fc/+0x60c/+0x610
```

It accepts domain indexes 0..6 and client indexes 0..9. One clock-client type
predicate skips objects of type 0x10 with a non-0xff field at +0x146. For
voltage it skips object type 5, otherwise copies the domain's rail result to
the domain cache at +0xde4+4*rail_index.

There is a noteworthy asymmetric bound: PMU 0x202c840e produces only rail
indexes 0..3, but GSP 0x016254ec accepts indexes 0..7. For indexes 4..7 its
literal source formula reads the following domain's 16-byte preamble (the final
packet tail for domain 6). The normal BoardObj population may keep those
indexes inactive, but the code-level mismatch is real and the executable model
preserves it.

The import is not the final clock decision. After fixing Ghidra's missing
noreturn annotation for the stack-guard failure routine, 0x016115f0 decompiles
cleanly as a GSP-side cache recompute. It:

1. selects one of three local low/high/middle triplets based on ClockManager
   flags and client type;
2. in one branch converts kHz to integer MHz, invokes the clock-client +0x1b8
   projection callback in middle/low/high order, then converts back;
3. obtains another client-specific limit through the +0x88 callback;
4. writes each bounded endpoint as min(selected_endpoint, callback_limit).

This is a confirmed mechanism for an initially selected GPC/XBAR/SYS value to
change after the PMU solver. perf_type5_output.py now replays both the exact
GSP import and this local selection/projection/cap core.

## 8. Physical clock programmer and post notifications

The physical writer is not a late GSP cache callback. Before the type-5 status
serialization, policy objects of type 3/5 reach `0x202ba402 -> 0x202baa54`.
For each active physical clock object:

1. `0x202ba5f6` selects an object-local or global affine source grid and floors
   valid values to the global step;
2. `0x202ba85c` resolves the domain's V/F program and builds two eight-byte
   hardware descriptors;
3. `0x202c2d2a` maps frequency to a u16 divider with asymmetric integer
   rounding, while `0x202c2e00` is the inverse representable-frequency map;
4. `0x202bbf3a` saturates two dividers to 9 bits, saturates the associated
   4/3-bit control fields, and writes the packed words to per-clock MMIO
   addresses obtained from `DAT_ram_2007c800`.

This final conversion is itself many-to-one. With a reduced 15/2 clock ratio,
requests 98, 99 and 100 all produce divider 13 and inverse frequency 97. The
exact source-grid, divider and MMIO packing layers are executable in
`pmu_clock_programmer.py`.

The main-domain divider fields are now bridged across the version boundary at
the transfer ABI. Current R610 GSP `0x0112d0ac` serializes row
`+0x21/+0x22/+0x24/+0x3e` into the 0x40-byte PMU transfer
`+0x05/+0x0a/+0x0c/+0x25`. Clear R570 PMU importer `0x202f74d2` installs those
same four transfer fields at grid object `+0x05/+0x0a/+0x0c/+0x30`, exactly
where `0x202c2d2a/0x202c2e00` consume them. The current live frequency lists
fix the main-domain effective ratio at 15/2. Although its unreduced raw
factorization remains unknown, direct and doubled-input encodings were
exhaustively compared for every integer request 0..3999 MHz and yielded the
same divider/readback pair. The default twin can therefore execute this stage
for GPC/XBAR/SYS/NVD while labeling the algorithm body as R570 cross-build.

The unit-9/type-0x11 and unit-6/type-0x13 messages sent afterward do not contain
the final divider. Both converge on `0x202a5826`, which reprojects three
threshold samples through clock domains 1/0xd and updates a piecewise limiter.
They are post-policy limiter refreshes, not the per-clock MMIO writer.

The current R610 finalizer also does not supply a missing writer:
`ClockManager+0x1168` slot `+0x8ee8` is constructed as return-zero
`0x010f1de4`. Pstate group `+0x1b8` variants converge at `0x01ae21d0`, whose
`+0x1498` targets are a predicate or a return-zero stub.

Separately, current R610 constructor implementation `0x01ba5814` contains a
signed-offset rewrite: under its type/flag/program gates it adds domain
`s32 +0x150` to cache words 4/9 and the selected program frequency, then calls
`0x01ae0808` to reproject both onto the legal domain grid and mirrors the
program result to word 14. `apply_gsp_signed_clock_offset()` replays this core.
Its GB202 HAL selection remains conditional.

## 9. Evidence boundary

Confirmed:

- real PMU PERF unit routing and the false-positive task exclusion;
- exact R570 C/group/D/E handlers and GSP packet-size correspondence;
- timer activation and periodic solver call order;
- per-domain 0x20-byte record import/recompute/export path;
- three-rail, 32-entry additive/replacement voltage matrix behavior;
- candidate offset, nonnegative clamp, and minimum reduction in the voltage
  preparation object;
- exact voltage-equation step quantization, including corrected negative
  remainder, optional upward rounding, zero-step behavior, and min/max clamp;
- exact three-endpoint repair/bound rule and fixed PERF type-5 output layout;
- exact R570.144 logical type-0x1305 dispatch edge, GSP client/voltage import
  offsets, and post-import local candidate/projection/cap behavior;
- exact R570 PMU source-grid normalization, asymmetric divider conversion,
  inverse representable-frequency map, descriptor packing and per-clock MMIO
  writes;
- exact current R610 clock-table-row to PMU-transfer field map and the live
  effective 15/2 main-domain divider grid;
- unit-9/unit-6 post-notification handlers and their common threshold/limiter
  update role;
- current R610 finalizer `+0x8ee8` return-zero target and the non-programming
  `0x01ae21d0` convergence.

Still unresolved:

- current encrypted R610 PMU handler bodies and whether every R570 field is
  layout-compatible after the C/D renumbering;
- semantic units/names for every type-D selector and returned word;
- runtime-populated status behavior of BoardObjGroup `0x1b` in the R570 table;
- exact physical rail and GPC/XBAR/SYS/NVD object-index mapping;
- the exact R570 virtual-slot registration/caller of 0x016115f0;
- current R610 unreduced divider factorization, object-local source-grid
  values, MMIO lane map and encrypted-PMU implementation identity;
- GB202 HAL selection of generic R610 `0x01ba5814` signed-offset logic.

Primary artifacts:

- `r570_pmu_perf_unit13_entry_20260817.c`
- `r570_pmu_perf_group_cde_handlers_20260817.c`
- `r570_pmu_perf_solver_core_20260817.c`
- `r570_pmu_perf_trigger_solver_20260817.c`
- `r570_pmu_perf_periodic_callback_20260817.c`
- `r570_pmu_perf_periodic_stages_20260817.c`
- `r570_pmu_perf_solver_inner_20260817.c`
- `r570_pmu_voltage_rail_resolution_20260817.c`
- `r570_pmu_voltage_request_and_commit_20260817.c`
- `r570_pmu_domain_commit_deep_20260817.c`
- `gsp570144_stride110_candidate_20260817.c`
- `gsp570144_type5_dispatch_pred_20260817.txt`
- `gsp570144_clock_cache_recompute_clean_20260817.c`
- `r570_pmu_per_clock_programmer_20260817.c`
- `r570_pmu_clock_program_selection_20260817.c`
- `r570_pmu_program_tuple_and_inverse_20260817.c`
- `gsp61057_clock_post_finalize_target_010f1de4_20260817.c`
- `gsp61057_projector_01ae0808_20260817.c`
- `gsp61057_clock_table_pmu_transfer_0112d0ac_20260817.c`

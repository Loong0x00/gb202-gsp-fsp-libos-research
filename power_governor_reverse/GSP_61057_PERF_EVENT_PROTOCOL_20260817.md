# R610.57 Perf event protocol and the no-op `Perf+0x560` slot

Date: 2026-08-17  
Scope: offline static R610.57.04/R570.144 GSP-RM analysis only. No GPU query,
setter, workload, fan command, or MODS execution was used.

## 1. The R610 slot installation is closed

The current-build Perf lifecycle table selects `0x0164bb38` as
`Perf::initLocked(pGpu,pPerf)`. That function directly calls
`0x016a9f40(pGpu,pPerf)`. A raw, function-boundary-independent CFG proves:

```text
0x016a9fa6  s2 = a1                         # s2 is pPerf
...
0x016ab13e  auipc a5,1
0x016ab142  addi  a5,a5,-0x64a             # a5 = 0x016abaf4
0x016ab146  sd    a5,0x560(s2)             # pPerf+0x560
0x016ab14c  sb    1,0x2ed(s2)
```

Target `0x016abaf4` is exactly seven instructions and returns zero:

```text
prologue -> a0 = 0 -> epilogue -> return
```

Therefore the post-CLK_DOMAINS call through `Perf+0x560` remains an ABI hook
but performs no calculation or PMU submission in this R610 build. It must not
be named `perfLoad`, `solve`, or `apply`.

## 2. The active work moved to two registered callbacks

The same `0x016a9f40` initialization path registers:

```text
callback 0x016aedcc, context pPerf+0x338
callback 0x016bcc80, context pPerf+0x340
```

`0x016aedcc` resolves `pPerf = *(pGpu+0x1f98)`, opens the objects at
`pPerf+0x318/+0x320`, and dispatches their enable/disable methods. The second
callback `0x016bcc80` owns the transfer/apply state machine. Its GSP-visible
state is:

```text
pPerf+0x349  active
pPerf+0x34a  deferred/retrigger state (functional name inferred)
pPerf+0x34b  successful type-0x0c response present
pPerf+0x34c  32-bit domain mask; current layout has storage for 16 domains
pPerf+0x368+0x20*i  cached 32-bit returned word for domain i
```

The exact bit meanings of returned words are not yet named, so the executable
model keeps them as unsigned 32-bit values.

## 3. PERF/type-0x0c transfer

`0x016bcae0` is the type-0x0c worker. When `pPerf+0x349` is active it builds:

```text
wire size       0x214 bytes
wire +0x00      u16 0x1300       # little-endian PERF unit word
wire +0x02      u8  0x0c
wire +0x10      0x204-byte snapshot copied from pPerf+0x34c
```

After a successful synchronous PMU call, it walks the domain mask. For every
set bit `i` it performs:

```text
pPerf+0x368+0x20*i <- u32 response[0x2c+0x20*i]
```

The wire offset is not guessed: `0x2c = 0x10 + (0x368 - 0x34c)`. The final
valid byte for `i=15` is inside the 0x214-byte packet; higher mask bits have no
backing entry in this layout. Success then sets `pPerf+0x34b = 1`.

## 4. PERF/type-0x0d transfer

`0x016adb28` is the follow-up/finalization path. Under its active/mask gate it
builds:

```text
wire size       0x54 bytes
wire +0x00      u16 0x1300
wire +0x02      u8  0x0d
wire +0x10+4*i  returned u32 word for domain i
wire +0x50      u32 domain mask
```

Only words selected by the local domain mask are imported, again into
`pPerf+0x368+0x20*i`. It then enters a ClockManager-owned post-change method
and the previously recovered clock post-apply helpers. Thus this path is the
GSP-side event-finalization boundary; it is not by itself the physical clock
writer, and `Perf+0x560` is not.

The higher-level callback flow is:

```text
event enable
  -> clear 0x30 + 255*0x60 BoardObjGroup status buffer
  -> build group header and one-byte child type IDs
  -> PMU unit 0x13 / group 0x1b / method 0x60 group exchange
  -> enumerate Perf child objects and import post-exchange status via child+0x4a0
  -> if domain mask != 0: PERF/type 0x0c snapshot exchange
  -> PERF/type 0x0d selected-word exchange
  -> ClockManager/post-apply processing
  -> acknowledge event

event disable
  -> unregister event id 0x10
  -> clear pPerf+0x34b and pPerf+0x349
```

## 5. R570 comparison

R570.144 `Perf::initLocked` calls `0x01637864(pGpu,pPerf)`. Its reachable
store at `0x01638c4a` assigns `Perf+0x4d8`, but the target is capability
selected:

```text
capability clear -> no-op 0x01625810
capability set   -> 0x01639f44
```

`0x01639f44` sends a 0x10-byte `0x1300/type-0x0c` trigger and continues into
`0x0163995c`. The old follow-up then performs the same group-transfer/object-
import shape and sends a 0x214-byte type-`0x0d` packet; its finalizer sends a
0x54-byte type-`0x0e` packet. R610 removes the initial trigger from the no-op
slot path and shifts the two retained inline messages down by one ID:

```text
R570: trigger C -> group transfer -> large D -> finalize E
R610:             group transfer -> large C -> finalize D
```

This proves a real protocol migration. The R570 runtime capability bit was not
read from a live boot, so its selected branch remains unknown.

## 6. Executable boundary

`bug_inverse/algorithm/gpu_inverse/perf_change_protocol.py` implements:

- the exact post-group-transfer child-workspace imports for classes 0x07,
  0x0d and 0x0f;
- the inherited no-op behavior for all other child classes;
- exact packet sizes, headers, snapshot, mask and result offsets;
- the 16-domain storage invariant;
- masked imports that preserve unselected cached words;
- active and response-valid GSP state transitions.

It deliberately does not fabricate the PMU response-producing algorithm.
For R570, that algorithm has since been recovered from the clear PMU:
type C enables periodic callback 0x202c867a, type D imports/recomputes the
per-domain equations, type E finalizes selected words, and 0x202c840e emits
the fixed 0x780-byte type-5 solver result. The executable implementation is
split across perf_change_protocol.py, pmu_voltage_matrix.py,
domain_adjustment.py, clock_propagation.py, and perf_type5_output.py.

The matching R570.144 GSP type-5 consumer is 0x016254ec. The dispatcher passes
message+4 at 0x017b5216/0x017b5448, and the consumer copies the PMU's 0x110
domain / 0x18 client layout into 0x40-byte GSP client records. A separate
GSP cache recompute at 0x016115f0 can then reselect a local candidate triplet,
run the client's MHz-grid projection callback, and cap all three endpoints
again. Current R610 PMU bodies remain encrypted, so cross-version field
identity is still not asserted.

The two apparent R610 post-apply candidates have now been falsified as physical
writers. The exact finalizer instructions load `ClockManager=gpu+0x1f88`, then
`ClockManager+0x1168`, and call its `+0x8ee8` slot. The only direct constructor
assignment installs `0x010f1de4`, an exact return-zero function. Pstate-group
`+0x1b8` implementations `0x01690978/0x0167ca18` both reach `0x01ae21d0`, but
its `+0x1498` targets resolve to a status predicate or return-zero stub.

The same-generation clear-PMU physical path is instead
`0x202ba402 -> 0x202baa54 -> 0x202ba85c -> 0x202bbf3a`.
It selects a clock-program row, converts frequency into a saturated divider
descriptor, and writes packed words to per-clock MMIO. This layer is replayed
by `pmu_clock_programmer.py`. Current R610 serializer `0x0112d0ac` now proves
the 0x40-byte transfer mapping from row `+0x21/+0x22/+0x24/+0x3e` to PMU wire
`+0x05/+0x0a/+0x0c/+0x25`; R570 importer `0x202f74d2` consumes those exact
positions as the physical grid parameters. The current live 15/2 effective
ratio is therefore used for main-domain divider/readback projection without
claiming an unreduced raw factorization or a byte-identical R610 PMU body.

Current R610 `0x01ba5814` also contains a distinct pre/finalization cache
rewrite: gated signed offset `+0x150` is added to words 4/9 and the selected
program frequency, then `0x01ae0808` reprojects them and word 14 is updated.
The implementation is executable, but its GB202 HAL selection remains to be
proven.

## 7. Evidence boundary

Confirmed:

- R610 Perf lifecycle caller, `pPerf` register provenance, slot store, flag,
  and return-zero target;
- both callback registrations and GSP-side state-machine fields;
- callback group/accessor/iterator targets, exact group transfer identity,
  0x60 workspace stride, and child `+0x4a0` state copies;
- exact type-0x0c/type-0x0d packet and masked-import layouts;
- R570 conditional no-op/active target and exact C/group/D/E sequence;
- R570 clear-PMU periodic solver, type-5 output, exact GSP consumer, and
  post-import GSP constraint rewrite;
- the R570 physical per-clock divider/MMIO writer and the fact that both R610
  finalizer candidates above are non-programming stubs/predicates.
- the current R610 clock-table row to PMU transfer-field bridge and live
  effective 15/2 main-domain divider grid.

Still unknown:

- semantic names and units of each returned 32-bit domain word;
- the current encrypted-R610 implementation and exact cross-version field
  compatibility;
- the PMU handler that produces R610 group-returned workspace fields;
- R570 live capability-bit selection;
- current R610 unreduced divider factorization, object-local source grid/MMIO
  lane map, and activation of generic `0x01ba5814` signed-offset logic.

Preserved artifacts:

- `gsp61057_raw_slot560_stores_20260817.txt`
- `gsp61057_slot560_owner_path_20260817.txt`
- `gsp61057_slot560_owner_target_20260817.c`
- `gsp61057_perf_replacement_callbacks_20260817.c`
- `gsp61057_perf_callback_followups_20260817.c`
- `gsp570144_slot4d8_owner_full_20260817.c`
- `r570_pmu_domain_commit_deep_20260817.c`
- `gsp570144_stride110_candidate_20260817.c`
- `gsp570144_clock_cache_recompute_clean_20260817.c`
- `gsp61057_clock_post_finalize_target_010f1de4_20260817.c`
- `r570_pmu_per_clock_programmer_20260817.c`
- `gsp61057_clock_table_pmu_transfer_0112d0ac_20260817.c`
- `tools/riscv_direct_store_scan.py`

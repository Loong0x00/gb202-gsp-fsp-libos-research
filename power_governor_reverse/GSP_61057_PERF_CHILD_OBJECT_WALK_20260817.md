# R610.57 Perf BoardObjGroup transfer and child-object status import

Date: 2026-08-17  
Scope: offline static analysis of the R610.57.04 GSP-RM image. No live GPU,
fan, setter, workload, or MODS operation was used.

## 1. Exact callback walk

Callback `0x016bcc80` gets the group at `pPerf+0x318`. Its accessor
`0x016abb78(group,index)` returns `group+0x880` for indexes 0 and 1. The
embedded group's default constructor is `0x01ac2860`; the Perf-derived owner
replaces embedded slot `+0x120` with `0x016ac830`.

The resulting path is:

```text
0x016bcc80 callback
  -> group+0x20 accessor 0x016abb78
  -> embedded+0x108 method 0x01741630
     -> clear the shared 0x5fd0-byte status buffer
     -> wrapper 0x016b92f4
     -> generic builder 0x01737830
     -> PERF BoardObjGroup PMU transfer
  -> enumerate child objects with group+0x40 iterator 0x01743ea8
  -> embedded+0x120 method 0x016ac830
     -> workspace = base + domain_index*0x60 + 0x30
  -> child+0x4a0(workspace)
  -> if domain mask is nonzero, PERF/type-0x0c exchange
```

`0x01737830` calls each child's auxiliary-object slot `+0x18`. The concrete
default target is `0x017375b0`: it recovers the parent child object and copies
only its one-byte class/type ID to the destination slot. It does **not**
produce the returned status fields.

The buffer is then transferred through `0x01740d74`. The Perf-derived embedded
group was initialized with PMU unit `0x13`, group/message byte `0x1b`, method
record `0x0060`, and buffer size `0x5fd0`:

```text
0x5fd0 = 0x30-byte group header + 255 * 0x60-byte object slots
```

The PMU exchange returns before the callback invokes child `+0x4a0`. Therefore
that virtual call is a post-group-transfer status import, although it remains
before the later inline PERF/type-`0x0c` request. GSP alone proves the ordering,
not which bytes the PMU mutates in place.

## 2. Child class dispatch

The hidden child factory starts at raw entry `0x01b79324`; Ghidra's enclosing
function boundary was too broad. Base constructor `0x01bbd3d8` installs a
return-zero method `0x016abbcc` at child slot `+0x4a0`. Only three classes
override it:

| Class | Allocated size | `+0x4a0` target | Effect |
|---|---:|---:|---|
| `0x07` | `0x5c0` | `0x016acd80` | scalar status import |
| `0x0d` | `0x540` | `0x016acea0` | scalar status import |
| `0x0f` | `0x570` | `0x016ad0f8` | four-lane status import |
| all others | class-specific | `0x016abbcc` | no-op, return zero |

The exact state-changing operations, excluding diagnostic logging, are:

```text
class 0x07 / 0x0d:
  child[0x50c:0x51c] <- workspace[0x0c:0x1c]
  child[0x524]       <- workspace[0x1c]
  child[0x525]       <- 1

class 0x0f:
  child[0x510:0x550] <- workspace[0x0c:0x4c]
  child[0x550:0x554] <- workspace[0x4c:0x50]
  child[0x554:0x558] <- {1,1,1,1}
```

The apparent loop in class `0x0f` interleaves the first and second halves,
but its aggregate result is exactly the contiguous 64-byte copy shown above.

## 3. Consequence for the control model

These methods do not calculate a frequency, voltage, constraint minimum, or
winner. They import the post-exchange per-object workspace into object status
fields before the inline type-`0x0c` PMU request. Therefore:

- child `+0x4a0` is classified as a post-group-transfer/pre-inline-type-C
  status-import stage;
- it cannot explain XBAR offsets converging to the same result by itself;
- auxiliary child slot `+0x18` supplies only the class/type ID;
- the PMU handler behind unit `0x13`, group `0x1b`, method `0x60` is the
  remaining boundary for determining whether/how the workspace fields change.

`bug_inverse/algorithm/gpu_inverse/perf_change_protocol.py` implements the
three exact byte-copy cases as `import_child_workspace()`. Unit tests verify
the changed ranges, untouched ranges, valid flags, no-op classes and size
guards.

## 4. Evidence boundary

Confirmed:

- group/accessor/iterator and embedded virtual target addresses;
- `0x30 + 255*0x60 = 0x5fd0` shared buffer layout and object-index address
  calculation;
- PMU unit `0x13`, group/message `0x1b`, method `0x60`, and the fact that the
  transfer occurs before child status import;
- auxiliary slot `+0x18` target `0x017375b0` copies only the child type byte;
- the exact three overriding classes, targets, object sizes and byte writes;
- all other classes inherit the no-op `+0x4a0` method.

Still unknown:

- semantic names and units of the post-exchange workspace words;
- the PMU-side handler that computes the unit-`0x13`/group-`0x1b`/method-`0x60`
  object results;
- which returned fields become inputs to the later inline PERF arbitration;
- the PMU-side producer of type-`0x0c` and type-`0x0d` response words.

Primary artifacts:

- `gsp61057_perf_child_factory_exact_20260817.c`
- `gsp61057_perf_child_domain_processors_20260817.c`
- `gsp61057_embedded_group_buffer_build_20260817.c`
- `gsp61057_embedded_group_transfer_20260817.c`
- `gsp61057_perf_child_interface_accessors_20260817.c`
- `gsp61057_perf_child_workspace_producer_20260817.c`
- `gsp61057_perf_group_buffer_helpers_20260817.asm`
- `gsp61057_prop_group_virtual_targets_20260817.c`
- `gsp61057_factory_mid_entry_cfg_20260817.txt`

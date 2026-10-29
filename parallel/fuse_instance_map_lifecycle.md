# GB202 fuse accessor: DeviceInfo2 instance-map source and lifecycle

## Result

The alternate branch in MODS function `0x1252200` is not evidence that an
external plan, JSON option, simulator, or partition setting overwrites the
ordinary GB202 fuse accessor's instance number.  The accessor still supplies
literal `instance = 0`.

What can change is the **source of the register base address**:

```text
GB202 logical fuse-domain request
    type/class = 0x10, instance = 0, fixed selector = 0x10ef4000
                         |
                         v
          lazily parse PTOP DEVICE_INFO2 hardware table
                         |
           +-------------+-------------+
           |                           |
   no entries for class 0x10    one or more entries
           |                           |
           v                           v
 RegHal selector 0x10ef4000      find instance 0 record
 index 0 -> 0x00820000           return record.devicePriBase
```

Therefore the answer to the narrow question is:

- **No:** this mechanism does not change the constructor's fixed selector
  instance from 0 to 1 and does not select the embedded `0x00bf0000` row by
  changing that integer.
- **Yes, conditionally:** on an ordinary hardware object, a populated PTOP
  DeviceInfo2 vector for mapped class `0x10` makes `0x1252200` discard the
  fixed selector ID and obtain the base for `(class 0x10, instance 0)` from
  hardware topology instead. A later complete translation audit proves that
  GB202 PTOP raw type `0x22` maps to this internal class; published
  `NV_FUSE0_PRI_BASE=0x820000` independently supports its fuse-PRI-aperture
  semantics. See `parallel/deviceinfo_class10_identity.md`.
- **Not established for this RTX 5090:** no live table was read, so static
  analysis cannot say whether its runtime class-`0x10` vector is populated or
  what its instance-0 `devicePriBase` contains.

The earlier description of this as a special "prebuilt instance map" should
be replaced with **an object-owned, lazily built cache of the hardware PTOP
DeviceInfo2 table**.

## Safety and scope

This audit was entirely offline and read-only:

- no MODS execution;
- no GPU device opening, BAR mapping, MMIO, ioctl, reset, or write;
- no GSP/FSP interaction;
- no broad Ghidra import or unbounded full-binary disassembly;
- only bounded `objdump` windows, small pointer/direct-call scans, the existing
  offline RegHal decoder, strings, and locally installed NVIDIA 610 source.

Target:

```text
mods_audit/static/extracted_inner/mods
SHA-256 c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
```

Addresses below are virtual addresses in that ELF.

## FACT: the GB202 request still carries instance 0

The preceding constructor/factory audit proved that the normal GB20x
SetSwFuses accessor is constructed with a literal zero instance.  The domain-5
case in the GB202 resolver forwards that integer without transformation:

```text
0x125c1f6  mov %esi,%ecx          # caller's instance -> resolver instance
0x125c1f8  mov $0x10ef4000,%edx   # fixed RegHal base selector
0x125c1fd  mov $0x10,%esi         # mapped device class/type requested
             -> 0x1252200
```

Thus `0x1252200` receives:

```text
type/class = 0x10
instance   = 0
selector   = 0x10ef4000
```

The existing offline RegHal decode of selector `0x10ef4000` found:

```text
idx=(0,0,0,0) -> 0x00820000
idx=(1,0,0,0) -> 0x00bf0000
```

Nothing in the alternate path increments, remaps, or replaces the instance
integer.  It remains zero in `R12D` until it is passed to `0xdd2230`.

## FACT: `0x1252200` chooses between two address sources

At function entry, `0x1252200` saves all three inputs and calls `0xdeda50`:

```text
0x1252202  mov %edx,%r13d         # save selector ID
0x1252207  mov %ecx,%r12d         # save instance
0x125220b  mov %esi,%ebp          # save class/type
0x1252215  call 0xdeda50
0x125221a  test %eax,%eax
0x125221c  jne 0x1252298
```

When `0xdeda50` returns zero, the function builds a one-element index vector
from the saved instance and calls the RegHal selector:

```text
0x1252248  mov %r12d,(%rax)       # vector[0] = instance
0x1252261  mov %r13d,%edx         # selector 0x10ef4000
0x1252268  call 0x1988910
```

When it returns nonzero, the selector saved in `R13D` is never used again:

```text
0x125229c  mov %r12d,%edx         # instance remains 0
0x125229f  mov %ebp,%esi          # class/type remains 0x10
0x12522aa  jmp 0xdd2230
```

The nonzero branch therefore replaces the **base-resolution mechanism**, not
the instance.

## FACT: `0xdeda50` reports unique instance IDs in a class vector

`0xdeda50(this, type)` first performs lazy cache construction:

```text
0xdeda5b  compare byte [this+0x698] with 0
0xdeda64  call virtual [vtable+0x1080] when it is zero
0xdeda6d  set byte [this+0x698] = 1
```

It then selects a vector using:

```text
this + 0x158 + 24 * type
```

Each vector element is `0x3c` bytes.  For every element, the function passes
the dword at element offset `+0x4` to `0xbc1120`.  The latter is an
`std::set<uint32_t>`-style red-black-tree insert: it compares the dword as the
key, stores it in a newly allocated node at node offset `+0x20`, and updates
the tree size at tree offset `+0x28`.  `0xdeda50` returns that size.

Consequently its return value is the number of **unique instance IDs** present
in the requested class vector.  `0x1252200` uses only the distinction between
zero and nonzero.

This also explains why duplicated records would not affect branch selection:
the result is a unique-ID count, not the raw vector length.

## FACT: `0xdd2230` returns the matching record's `devicePriBase`

`0xdd2230(this, type, instance)` uses the same lazy flag and the same vector
formula.  It scans `0x3c`-byte records, compares the requested instance to the
dword at record offset `+0x4`, and returns the dword at record offset `+0x18`
from the matching record.

The optimized loop compares up to four consecutive records at a time, but its
logical operation is simply:

```text
for record in vectors[type]:
    if record.instanceId == instance:
        return record.devicePriBase
```

The field meanings are established independently by the builder and by the
published NVIDIA structure described below.

## FACT: the cache is built from PTOP DeviceInfo2 hardware rows

### GB202 dispatch

A raw vtable-pointer scan places resolver `0x125b720` in the
`GB202GpuSubdevice` vtable.  Its vtable slot `+0x1080` points to builder
`0xdec350`.  The same builder is present in the examined Blackwell/GB10x/GB20x
GpuSubdevice vtables, so this is not a fuse-only callback.

Builder `0xdec350` chooses a RegHal object from `GpuSubdevice+0x6c0` when that
override is non-null, otherwise from the embedded object at
`GpuSubdevice+0x90`.  It then reads two RegHal-described hardware regions:

```text
RegHal ID 0x12ae8000 -> relative register 0x4fc
RegHal ID 0x12adc000 -> relative row array 0x800 + 4*i
```

The existing GB202 offline decoder also gives these field descriptions:

```text
0x22ae8100 -> cfg bits [31:20]       (number of rows)
0x22ae8000 -> cfg bits [19:16]
0x22adcb00 -> row bits [30:24]       (device type enum)
0x22adc600 -> row bits [23:16]       (instance ID)
0x22adc400 -> row bits [10:0]        (fault ID)
0x22adc800 -> row bits [39:32]       (reset ID)
0x22adc300 -> row bits [57:40]       (device PRI base)
0x22adc900 -> row bits [65:64]       (runlist-engine ID)
0x22adca00 -> row bits [89:74]       (runlist PRI base)
```

The binary's own diagnostics name the same table:

```text
Unable to get hardware device info!
Mismatch between MODS manual in PTOP_DEVICE_INFO2__SIZE1: <%d, and HW register
PTOP_DEVICE_INFO_CFG_NUM_ROWS: %d. Skipping PTOP_DEVICE_INFO(%d) and after.
```

### Cross-check against NVIDIA 610 published headers

Local NVIDIA 610 source makes the register identity mechanical:

- `.../published/blackwell/gb100/dev_top.h:27` defines
  `NV_PTOP_DEVICE_INFO_CFG` as `0x224fc`.
- The same file at line 30 defines `NV_PTOP_DEVICE_INFO2(i)` as
  `0x22800 + 4*i`.
- Lines 37, 40-41, 44, 46, 50-51 define the same chained-row bit fields for
  fault ID, instance ID, type enum, reset ID, device PRI base, runlist-engine
  ID, and runlist PRI base.
- Lines 102-107 define the configuration fields, including
  `NUM_ROWS` at bits `[31:20]`.
- `.../published/ampere/ga100/dev_top_addendum.h:27-30` publishes the
  zero-based relative aliases at exactly `0x4fc` and `0x800 + 4*i`.

NVIDIA's generated `g_gpu_nvoc.h:775-792` explicitly says
`DEVICE_INFO_ENTRY` holds data obtained by parsing the DeviceInfo2 table at
initialization.  Its fields include `instanceId`, `typeEnum`, and
`devicePriBase` in the order seen here.  `ctrl2080internal.h:745-773` likewise
describes parsing the DeviceInfo2 table on the physical side and exposes the
same record fields.

### Record construction

The builder constructs a `0x3c`-byte temporary record.  The relevant stores
are:

```text
raw PTOP type enum [30:24] -> helper 0xdd2550 -> record +0x00
PTOP instance ID   [23:16]                    -> record +0x04
PTOP device PRI base [57:40], address-scaled  -> record +0x18
```

It appends the completed record to:

```text
this + 0x158 + 24 * mapped_type
```

Thus the lookup result at record `+0x18` is a hardware-table-derived
`devicePriBase`.  The exact raw-enum-to-internal-class mapping performed by
`0xdd2550` is not needed to establish the source or lifecycle, and its complete
mapping was not expanded in this bounded audit.

## FACT: object ownership, lazy construction, and invalidation

### Construction

The base `GpuSubdevice` constructor at `0xdf2af0` initializes 56 consecutive
24-byte vector objects from object offset `+0x158` through the byte before
`+0x698`.  It then clears the lazy-built flag at `+0x698`.

The storage is therefore initially empty and belongs to each GpuSubdevice
object; it is not a process-global table injected before object creation.

### First use

Both the count helper `0xdeda50` and lookup helper `0xdd2230` call the virtual
builder once when the flag is clear, then set the flag.  Of note, the callers
set `+0x698 = 1` after the virtual builder returns even if the builder logged an
error and returned early.  A failed first parse therefore does not
automatically retry on every subsequent query.

### Explicit invalidation

`0xdd2520` walks all 56 vectors, sets each vector's end pointer back to its
begin pointer while retaining allocated capacity, then clears `+0x698`:

```text
for each vector at this+0x158 ... this+0x680:
    vector.end = vector.begin
this[0x698] = 0
```

The next count or lookup rebuilds from hardware.

A later sequencing audit narrows this further: the successful FS path calls
the invalidator only after task-2 completion plus host apply/post-hook work and
before a possible post-FS reset.  Within one serial `ProgramSwFusePlan`, the
latch RMW may trigger the first build, after which latch/raw write/readback
reuse the same cache; that function contains no invalidator or reset.  The
ordinary post-program reset has not been proved to invalidate the cache or
reconstruct `GpuSubdevice`.  See `parallel/deviceinfo_cache_writer_timing.md`.

A bounded scan found one direct call at `0x1095ffa`.  The containing routine is
installed in shared Ampere/AD10x/GA10x-style `Fs` vtables and sits in a flow
whose nearby diagnostics include:

```text
Cannot use -skip_fsp_fs as the PLMs are raised
-skip_fsp_plm_check and -skip_fsp_fs can't be used together
```

The conservative interpretation is that a shared FS programming or
reinitialization path invalidates cached topology before later use.  This
evidence does not by itself prove the exact reset level of that enclosing
operation.

### Destruction

The base destructor walks the same 56 vectors from high to low offsets and
frees their buffers.  This closes the ownership/lifetime chain:

```text
GpuSubdevice construction -> empty vectors, flag clear
first query               -> parse PTOP DeviceInfo2, flag set
FS reinitialization path  -> empty vectors, flag clear
next query                -> reparse hardware
destruction               -> free vector buffers
```

## FACT: other callers confirm a general topology facility

A bounded direct-call scan found `0xdeda50` used with several other class/type
values, including `0x13`, `1`, `4`, and `3`.  Nearby output strings identify
ordinary engine instances:

```text
LCE%d=0x%08x
NVDEC%d=0x%08x
NVENC%d=0x%08x
OFA%d=0x%08x
NVJPG%d=0x%08x
```

This is consistent with a general PTOP device-instance inventory.  It is
inconsistent with interpreting the cache as a special fuse-unlock map or a
one-off external override.

## INFERENCE

- If GB202's runtime DeviceInfo2 table has a mapped class-`0x10`, instance-0
  record, its `devicePriBase` is very strongly expected to be `0x00820000`,
  agreeing with the embedded RegHal fallback. In addition to that structural
  argument, NVIDIA 610 binds GB202's primary-FUSE getter to a stateless function
  returning the same `NV_FUSE0_PRI_BASE` constant. This expectation is not
  promoted to a live-row FACT without a table capture; see
  `parallel/deviceinfo_reset_stability.md`.
- The alternate branch may be the normal hardware branch on devices whose
  DeviceInfo2 table includes this class, rather than a simulation-only or
  partition-only exception.
- Because the value comes from hardware topology and no vector writer other
  than the DeviceInfo2 builder was found, this path does not look like a
  user-selectable hook for redirecting instance 0 to `0x00bf0000` or an
  arbitrary aperture.
- Explicit invalidation after FS-related activity suggests MODS expects the
  table to reflect hardware state that can require rediscovery. The invalidator
  clears all 56 class vectors, so it is best explained as generic topology
  coherence; it does not show that FUSE base changes or that software can freely
  manufacture new devices or bases.

## UNKNOWN

- Whether this specific RTX 5090 currently exposes any mapped class-`0x10`
  DeviceInfo2 record.
- If it does, the actual runtime `instanceId` set and `devicePriBase` values.
- The complete numeric mapping implemented by `0xdd2550` is now recovered in
  `parallel/deviceinfo_class10_identity.md`: GB202 raw type `0x22` maps to
  internal class `0x10`. The exact proprietary C++ enumerator token and exact
  public PTOP macro spelling remain unpublished/UNKNOWN; the semantic FUSE
  identity is strongly cross-checked by the caller and `NV_FUSE0_PRI_BASE`.
- The follow-up in `parallel/deviceinfo_instance_nomatch.md` closed the machine-
  code behavior for a malformed/non-dense vector: a nonempty class with no
  requested instance does not report an error or use the fixed fallback;
  `0xdd2230` reads `vector.end()+0x18`, and the raw wrapper treats that dword as
  a base. `parallel/deviceinfo_instance_invariant.md` further proves that the
  published 610 client builders neither synthesize nor require instance 0 and
  that the public exact-tuple lookup reports absence; the hidden physical-side
  producer remains the only place that could still guarantee the invariant.
  Whether normal GB202 hardware does so remains UNKNOWN.
- Why the embedded selector also contains `idx=1 -> 0x00bf0000`, and whether
  any real GB202 configuration constructs an accessor with instance 1.
- Whether indirect callers beyond those identified participate in cache
  invalidation.  The direct-call scan is evidence, not a proof that no virtual
  or computed call exists.

## Reproduction notes

The principal offline checks were bounded variants of:

```text
objdump -d --start-address=0x12521f0 --stop-address=0x12522c0 mods
objdump -d --start-address=0xdeda50  --stop-address=0xdedb40  mods
objdump -d --start-address=0xdd2230  --stop-address=0xdd2370  mods
objdump -d --start-address=0xdd2520  --stop-address=0xdd2550  mods

python3 gb202_reghal_offline.py --id 0x10ef4000 --include-metadata
python3 gb202_reghal_offline.py --id 0x12ae8000 --include-metadata
python3 gb202_reghal_offline.py --id 0x12adc000 --include-metadata
```

Here `mods` abbreviates the target path stated above.  The published-header
cross-checks came only from `/usr/src/nvidia-610.43.03`; they did not load or
query the installed driver.

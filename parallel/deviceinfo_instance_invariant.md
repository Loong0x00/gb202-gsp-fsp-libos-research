# NVIDIA 610 DeviceInfo2 instance-0 invariant audit

Date: 2026-07-21
Scope: published NVIDIA 610.43.03 source only, plus existing project reports for
the already recovered MODS raw-type/class correspondence

## Result

The published 610 source does **not** establish the general invariant:

> If a DeviceInfo2 type/class has at least one entry, global instance 0 must
> exist.

In particular, it does not establish that invariant for the MODS internal
class `0x10` used by the GB202 fuse-domain resolver.

What the source actually establishes is narrower:

- `instanceId` is an explicit field carried by every DeviceInfo2 record.
- The two published client-side builders preserve the upstream entry order and
  copy `instanceId` and `typeEnum` verbatim.  They enforce only a total-entry
  upper bound; they do not sort, renumber, fill gaps, require zero, or reject
  duplicates.
- The published lookup API scans records and explicitly returns
  `NV_ERR_OBJECT_NOT_FOUND` for no match and `NV_ERR_MORE_DATA_AVAILABLE` for a
  non-unique match.  It does not index a dense per-type array by instance ID.
- Several Blackwell callers request global instance 0 for particular expected
  devices such as TMR, PBUS, HUBMMU, and LCE, but each checks the returned
  status.  This is evidence of an architecture/product expectation for those
  call sites, not a published all-types density guarantee.
- The physical-side implementation that parses PTOP DeviceInfo2 and services
  `NV2080_CTRL_CMD_INTERNAL_GET_DEVICE_INFO_TABLE` is not present in the
  published source tree.  The tree contains its control definition,
  declaration, export wrapper, and client call, but not the implementation
  body where a hardware-origin invariant could have been enforced.
- Published GB202 type headers do not name raw type `0x22`; they publish only
  selected type constants.  Existing offline work proved that MODS maps raw
  GB202 type `0x22` to its private internal class `0x10`, but the public API
  operates on the raw `typeEnum`, not the private MODS class number.

Therefore the earlier malformed-table case remains **unclosed by public
source**.  This audit does not show that a normal GB202 can actually expose a
nonempty fuse-type set lacking instance 0.  It shows only that no published
610 API/builder/type definition rules that shape out or repairs it.

For an offline safety checker, the conservative rule remains appropriate:
reject a nonempty requested type/class whose requested instance is absent.
Do not infer instance 0 from occupancy alone and do not silently substitute a
fixed selector.

## Safety and provenance

This was a read-only source audit.  Files came from:

```text
/usr/src/nvidia-610.43.03
```

The locally checked development mirror identifies the source generation as
`610.43.03`; no network fetch was needed.  No MODS or firmware binary was run,
and no GPU node, BAR/MMIO, ioctl, debugfs, reset, rebind, or write was used.
This report deliberately does not repeat the already completed machine-code
analysis of the MODS no-match helper.

## FACT: the public record carries explicit independent IDs

`src/nvidia/generated/g_gpu_nvoc.h:775-806` describes `DEVICE_INFO_ENTRY` as
holding information parsed from DeviceInfo2 during initialization.  The record
contains separate fields for:

```c
NvU32 instanceId;
NvU32 typeEnum;
NvU32 groupId;
NvU32 groupLocalInstanceId;
```

The header defines `-1` wildcard values for global and die-local instance
queries.  It does not define a per-type count, a dense-index flag, an
instance-zero requirement, or a singleton annotation.

The published PTOP row definition in
`published/blackwell/gb100/dev_top.h:27-51` likewise gives the hardware record
an explicit 8-bit `DEV_INSTANCE_ID` field at bits `[23:16]` and a distinct
7-bit `DEV_TYPE_ENUM` field at `[30:24]`.  The same header defines invalid
values for the complete row, fault ID, and reset ID, but publishes no
`DEV_INSTANCE_ID_INVALID`, density rule, or ordering rule.

These absences are not proof that hardware permits holes.  They do show that
the published record format itself does not encode the desired invariant.

## FACT: published builders do not create or validate density

### FWCLIENT / ordinary GB202 client path

Generated HAL selection in `g_gpu_nvoc.c:853-864` includes GB202 and binds a
non-VF object to `gpuConstructDeviceInfoTable_FWCLIENT`.

That builder, in `gpu_gspclient.c:225-284`, performs this sequence:

1. request `NV2080_CTRL_CMD_INTERNAL_GET_DEVICE_INFO_TABLE` from physical RM;
2. accept an empty response;
3. assert only that `numEntries <= 512`;
4. allocate exactly `numEntries` records;
5. for `i = 0..numEntries-1`, copy every field from source entry `i` to
   destination entry `i`.

In particular:

```c
.instanceId = pSrc->instanceId,
.typeEnum   = pSrc->typeEnum,
```

There is no:

- sort by `(typeEnum, instanceId)`;
- per-type grouping or count validation;
- `instanceId = loop_index` rewrite;
- check that the minimum instance is zero;
- check that instances are consecutive;
- check that an exact `(type, instance)` tuple is unique.

Consequently any such guarantee on the ordinary path would have to come from
the physical-side producer, not this published builder.

### VF path

`gpu_vgpu.c:230-284` behaves the same way for the static VF-supplied table.  It
checks the total count, allocates the flat table, and copies `instanceId`,
`typeEnum`, and all peer fields in source order.  Its diagnostic prints the
supplied global and local IDs, but it performs no density or instance-zero
validation.

This independent path reinforces that `DEVICE_INFO_ENTRY` is treated as a
collection of explicit tuples rather than a builder-normalized dense array.

## FACT: the public query API fails closed on absent or ambiguous tuples

The iterator in `gpu.c:7768-7808` linearly walks the flat table in stored
order.  It filters only by exact `typeEnum` and a dielet mask; it does not use
the instance ID as an array index and does not stop merely because a class is
nonempty.

`gpuGetOneDeviceEntry_IMPL` in `gpu.c:7812-7855` then applies the requested
global and die-local IDs:

```text
zero matching tuples       -> NV_ERR_OBJECT_NOT_FOUND
exactly one matching tuple -> NV_OK and that entry
second matching tuple      -> NV_ERR_MORE_DATA_AVAILABLE
```

It initializes the output pointer to null before searching.  Thus the public
API has explicit behavior for a requested instance being absent; it neither
falls back to the first record of that type nor assumes that record 0 exists.

This is the strongest public-source evidence against treating density as an
API guarantee.  It does not contradict a possible hardware-generation
invariant: defensive/error-returning APIs can still sit above well-formed
hardware.  It simply means that invariant is not promised or enforced here.

## FACT / INFERENCE: exact instance-0 callers show convention, not theorem

Published Blackwell code repeatedly asks for global instance 0:

- `timer_gb100.c:49-60`: TMR, then `NV_ASSERT_OR_RETURN(status == NV_OK, 0)`;
- `kern_fsp_gb100.c:427-436`: PBUS, then status-checked early return;
- `kern_bus_gb100.c:242-249`: HUBMMU, then status-checked early return;
- `kernel_ce_gb202.c:309-316`: LCE, returned status propagated by
  `NV_ASSERT_OK_OR_RETURN`;
- `kernel_sec2_gb20b.c:837-845`: PBUS, then status-checked early return.

From those call sites it is reasonable to infer that NVIDIA expects instance 0
to exist for these required devices on the architectures where the routines
are selected.  However:

1. the callers name particular raw public types, not every populated type;
2. they do not first test “type nonempty”; they request the exact tuple;
3. every caller has a failure path;
4. none states or checks that the remaining IDs are consecutive.

They therefore support a **per-device convention/requirement**, not the
general implication “nonempty type => instance 0 exists.”

## FACT: the physical parser contract is only partly published

`ctrl2080internal.h:745-773` documents the internal control as:

> Parse the DEVICE_INFO2_TABLE on the physical side and return it to kernel.

Its public payload is only:

```text
numEntries
deviceInfoTable[512]
```

with explicit record fields.  There are no documented ordering, uniqueness,
singleton, density, or instance-zero preconditions/postconditions.

The published tree contains:

- the declaration of `subdeviceCtrlCmdInternalGetDeviceInfoTable_IMPL` in
  `g_subdevice_nvoc.h:4659`;
- an NVOC export wrapper calling it in `g_subdevice_nvoc.c:3034-3037`;
- the FWCLIENT control invocation described above.

A source-tree-wide exact-symbol search finds no `.c` implementation body.
Accordingly this audit cannot inspect whether the physical producer validates
or synthesizes instance numbering.  Any claim that it guarantees instance 0
would require an additional primary artifact, such as the actual published
implementation or an authoritative hardware/API specification; neither is in
the 610 source set examined here.

## FACT: public raw type and MODS private class are different namespaces

The public `DEVICE_INFO_ENTRY.typeEnum` is the PTOP raw type value.  Existing
offline report `parallel/deviceinfo_class10_identity.md` mechanically proved
the GB202 MODS conversion:

```text
PTOP raw DEV_TYPE_ENUM 0x22 -> MODS internal class 0x10
```

The public 610 headers do not expose a symbolic raw-type macro for `0x22`:

- `published/blackwell/gb202/dev_top_zb.h:27` publishes only GB202 `LCE =
  0x13`;
- `published/blackwell/gb100/dev_top.h:41-43` publishes the type field and only
  selected values (`LCE = 0x13`, `HSHUB = 0x18`);
- a scoped search for a `DEV_TYPE_ENUM` definition with value `0x22` or a
  `...FUSE` type macro finds no match in the 610 published tree.

Therefore no public class-`0x10` singleton/density declaration exists to
apply.  Calling MODS class `0x10` “fuse” remains a strong semantic inference
from its consumer and base selector, but the private class number itself is
not an OpenRM API token.

## Answer to the project question

Evidence levels are:

| Question | Result |
|---|---|
| Does the 610 client builder ensure every populated type has instance 0? | **No** |
| Does it sort or renumber instances densely? | **No** |
| Does the public lookup assume density? | **No; it searches exact tuples and reports not-found/non-unique** |
| Do some architecture callers expect a specific instance 0? | **Yes, for named devices, with checked failure paths** |
| Does the published physical parser prove the invariant? | **UNKNOWN; implementation body is absent** |
| Does public source prove it for MODS class `0x10` / raw GB202 type `0x22`? | **No** |
| Does this prove real GB202 hardware can omit instance 0 while retaining another instance? | **No; runtime/hardware producer remains UNKNOWN** |

The most precise wording for the main investigation is therefore:

> MODS appears to rely on a valid-topology invariant when its class vector is
> nonempty, but NVIDIA 610's published DeviceInfo2 record API and client
> builders do not state or enforce “nonempty implies instance 0.”  The public
> lookup API instead handles an exact instance being absent.  Whether the
> hidden physical parser or GB202 hardware guarantees the fuse tuple remains
> unknown.

## Reproduction commands

Only bounded source searches/views were used, principally:

```text
rg -n "gpuConstructDeviceInfoTable|gpuGetOneDeviceEntry|DEVICE_INFO_ENTRY" \
  /usr/src/nvidia-610.43.03

rg -n "subdeviceCtrlCmdInternalGetDeviceInfoTable_IMPL" \
  /usr/src/nvidia-610.43.03

rg -n "DEV_TYPE_ENUM.*0x22|TYPE_ENUM_FUSE|DEV_TYPE.*FUSE" \
  /usr/src/nvidia-610.43.03/src/common/inc/swref/published \
  /usr/src/nvidia-610.43.03/src/nvidia
```

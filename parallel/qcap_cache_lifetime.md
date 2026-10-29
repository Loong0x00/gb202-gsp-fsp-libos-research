# MODS FSP QCAP cache owner and reset lifetime

Date: 2026-07-21
Status: final; static-only

## Result

The QCAP `{NvdmType, Version}` RB tree belongs to a `0xa8`-byte host FSP
wrapper stored at `GpuSubdevice + 0x1ad8`.  It is not firmware memory and is
not reconstructed by the normal `SetSwFuses` post-program reset.

The visible lifetime is:

```text
GpuSubdevice construction
  -> +0x1ad8 = null

FSP-wrapper ensure path
  -> if +0x1ad8 is non-null: return without reconstruction
  -> otherwise allocate 0xa8 bytes
  -> construct wrapper at 0x185f690
  -> store pointer at GpuSubdevice+0x1ad8

GpuSubdevice destruction
  -> load +0x1ad8
  -> 0x18576f0 destroys wrapper-owned trees
  -> free the 0xa8-byte wrapper
```

Within that wrapper, the QCAP tree uses header/root/count fields at
`+0x38/+0x48/+0x60`.  Destructor `0x18576f0` walks the root at `+0x48` and
frees its `0x28`-byte nodes.

The already audited normal reset chain preserves the same `GpuSubdevice*` and
does not touch `+0x1ad8`, call the wrapper constructor/destructor, or clear the
tree.  Consequently, on the visible MODS 570.151 path, a QCAP `0x13` presence
result survives hot/boot/fuse/base post-program reset as a host cache entry.
That persistence does **not** prove that FSP still advertises the capability or
would accept a new task after firmware/reset state changes.

There is a second cache-coherency boundary.  A later all-query may add new
NVDM types, but the tree's unique insert does not overwrite an existing key's
Version and does not delete keys absent from the new response.  Therefore an
all-query is not a full snapshot replacement.  No timestamp, firmware epoch,
expiry, or active-state revalidation field is visible.

In plain language: QCAP answers are sticky host-side capability records, not a
live permission lease.  Presence can become stale across a device/firmware
transition, and actual task status remains the only per-command visible
decision.

## Scope and safety

This audit used only bounded disassembly of the fixed local MODS 570.151 ELF
and existing static reports.  MODS was not executed; no GPU node, MMIO/BAR,
PCI configuration, firmware interface, reset, module, or network operation was
used.

Artifact:

```text
mods_audit/static/extracted_inner/mods
sha256 c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
```

## FACT: owner construction and storage

Base construction at `0x12500a0` initializes the host pointer:

```text
0x1250193  mov qword ptr [GpuSubdevice+0x1ad8], 0
```

The ensure path at `0x1250365..0x125041b` first tests that field.  A non-null
pointer returns immediately.  A null field takes this branch:

```text
0x12503c8  operator new(0xa8)
0x12503e5  call 0x185f690
0x12503f1  store new pointer at GpuSubdevice+0x1ad8
```

The replacement cleanup in the same helper calls `0x18576f0` and frees
`0xa8` bytes if an older pointer existed.  The ordinary GB202 vtable method
`+0x370 = 0x1247260` simply returns `[GpuSubdevice+0x1ad8]`; this is the object
passed to QCAP fetch/lookup and task senders.

## FACT: the QCAP tree is wrapper-owned

`0x185deb0` and `0x185e0e0` use:

```text
wrapper +0x38  RB-tree header
wrapper +0x48  root
wrapper +0x60  entry count
```

QCAP response records become `0x28`-byte nodes whose payload is:

```text
node +0x20  NvdmType
node +0x24  Version
```

Wrapper destructor `0x18576f0` loads `[wrapper+0x48]`, recursively destroys
the nodes, and frees each with size `0x28`.  This directly ties QCAP lifetime
to the host wrapper rather than to a transient response vector.

The GB202 `GpuSubdevice` non-deleting destructor at `0x127c620` later loads
`[GpuSubdevice+0x1ad8]`, calls `0x18576f0`, frees the wrapper with size `0xa8`,
and continues into the base destructor.  Thus full object destruction does
clear QCAP state.

## FACT: normal post-program reset does not clear the owner or tree

`parallel/postreset_deviceinfo_cache_lifetime.md` proves that
`0x127b000 -> 0xdff7b0 -> 0xdfe3d0` preserves and reuses the same
`GpuSubdevice*` across the normal coupling-selected reset.

A bounded review of the complete `0xdfe3d0..0xdff776` dispatcher found no:

- access to displacement `+0x1ad8`;
- call to wrapper constructor `0x185f690` or destructor `0x18576f0`;
- call to QCAP fetch `0x185deb0` or lookup `0x185e0e0`;
- call to the `GpuSubdevice` constructor/destructor.

The full-text direct-call inventory also places the ordinary wrapper
construction at the explicit ensure helpers, not in this reset dispatcher.
Accordingly, cache retention is a visible-host-path FACT.  Firmware-internal
state retention is a separate UNKNOWN.

## FACT: refresh is additive, not replacement

`parallel/qcap13_semantics.md` proves the current cache policy:

- initialization may issue an all-query (`0xff`);
- lookup retries all-query only when the whole tree is empty;
- a nonempty tree missing `0x13` does not targeted-refresh;
- duplicate `NvdmType` insertion does not overwrite the existing Version;
- keys absent from a later response are not removed.

Therefore even a later all-query is not a transactional replacement of the
old capability snapshot.  It cannot by itself prove that an old `0x13` entry
is still active after FSP restart/reset.

## Evidence classification

### FACT

- QCAP tree owner is the host wrapper at `GpuSubdevice+0x1ad8`.
- The wrapper is allocated once by the ordinary ensure path and has size
  `0xa8`.
- Full `GpuSubdevice` destruction destroys the wrapper and QCAP nodes.
- Normal `SetSwFuses` post-program reset preserves the owner and does not clear
  or refetch QCAP.
- Later all-query insertion does not update duplicate Versions or remove
  absent keys.

### INFERENCE

- MODS treats QCAP primarily as a relatively stable protocol-capability cache,
  not as a short-lived authorization lease.
- If FSP capability publication changes across a reset/restart while the host
  wrapper survives, the host map can be stale until full wrapper destruction;
  even another all-query may not remove a stale key.

### UNKNOWN

- Whether each hot/boot/fuse/base reset actually restarts FSP or changes its
  advertised capability set.
- Whether the private transport has an unobserved firmware-epoch check outside
  this tree.
- Whether another dynamically computed or external-module path clears the map.
- The actual QCAP state of this RTX 5090; no live query was performed.

## Reproduction windows

```text
0x12500a0..0x1250438  GpuSubdevice field initialization / wrapper ensure
0x1247260..0x1247268  GB202 wrapper getter
0x18576f0..0x1857772  wrapper destructor / QCAP-node cleanup
0x185deb0..0x185e260  QCAP fetch, insert, and lookup
0x127c620..0x127c7e0  GB202 GpuSubdevice destructor
0xdfe3d0..0xdff776    normal state reset dispatcher
```

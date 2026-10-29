# DeviceInfo2 class nonempty / requested instance missing: exact resolver behavior

## Result

The malformed-table corner case is **not fail-closed** in the examined MODS
binary.

For `0x1252200(this, class, instance, selector)` the three relevant cases are:

| class vector state | result |
|---|---|
| no records / no unique instance IDs | use the fixed RegHal `selector` |
| at least one record and `instance` is present | return that record's `devicePriBase` |
| at least one record but `instance` is absent | read and return the dword at `vector.end() + 0x18` |

The third row is an out-of-range record-field read, not an error result and not
a fallback.  At the C++ level it is undefined behavior; at the level of this
specific machine code, the attempted return value is exactly the 32-bit load
from `end + 0x18`.  Depending on heap layout, this can be stale/uninitialized
data, zero by accident, or a host-process fault.  There is no diagnostic or
status channel in this lookup path.

Both raw wrappers then treat whatever dword was returned as an ordinary base
address.  They add it to the remapped relative register offset with a 32-bit
`add`, and forward the sum to the ordinary register read/write backend.  A
zero-looking or error-code-looking value is not distinguished from a valid
base.

This closes the earlier UNKNOWN in
`parallel/fuse_instance_map_lifecycle.md`: a class-`0x10` vector containing,
for example, only instance 1 would neither fall back to selector
`0x10ef4000` nor safely report that instance 0 is absent.

It does **not** establish that a normal GB202 DeviceInfo2 table can have this
shape.  The code clearly relies on an invariant that every requested instance
exists whenever the corresponding class vector is nonempty.  No live table
was read in this audit.

## Safety and scope

This was a purely offline, bounded static audit of:

```text
mods_audit/static/extracted_inner/mods
SHA-256 c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
```

Only small `objdump` windows around the already identified functions and
existing project notes were used.  The binary was not executed.  No GPU node,
BAR, MMIO, ioctl, debugfs, RM private interface, reset, or write was accessed.

## FACT: branch selection checks class occupancy, not membership

As established in `parallel/fuse_instance_map_lifecycle.md`, `0xdeda50`
returns the number of unique instance IDs in the selected class vector.
`0x1252200` tests only whether that number is zero:

```text
0x1252215  call 0xdeda50
0x125221a  test eax,eax
0x125221c  jne  0x1252298
```

The zero branch constructs a one-element RegHal index vector and calls the
saved selector at `0x1252268`.  The nonzero branch discards that possibility:

```text
0x125229c  edx = saved requested instance
0x125229f  esi = saved class
0x12522aa  jmp 0xdd2230
```

There is no comparison such as `requested_instance < count`, no membership
query against the temporary set, and no second selector call after
`0xdd2230`.  Consequently one record for any instance is enough to suppress
the fixed selector fallback.

For the ordinary GB202 domain-5 path the saved inputs remain:

```text
class    = 0x10
instance = 0
selector = 0x10ef4000
```

## FACT: `0xdd2230` retains `vector.end()` as its no-match candidate

The selected vector has the normal three-pointer layout.  At entry to the
search:

```text
0xdd226e  rcx = vector.end()
0xdd2272  rax = vector.begin()
```

Records are `0x3c` bytes.  The optimized loop checks four records per group
at instance-field offsets `+0x04`, `+0x40`, `+0x7c`, and `+0xb8`, then handles
zero to three remainder records.  Every match path changes the selected
pointer to the matching record and returns its field at `+0x18`.

The critical detail is that `RCX` remains `vector.end()` until a match occurs:

```text
# a main-loop match
0xdd22d6  rcx = rax
0xdd22d9  eax = dword [rcx + 0x18]

# final one-record check
0xdd2312  cmp requested, dword [rax + 0x04]
0xdd2316  cmove rcx,rax
0xdd231d  eax = dword [rcx + 0x18]
```

For a zero-record remainder, `0xdd2310` jumps directly to the same return
load.  For two or three remainder records, failed comparisons advance `RAX`
and eventually reach the `cmove`; if the last comparison also fails, the move
is not taken and `RCX` is still `end`.

Thus all no-match shapes converge on:

```text
eax = *(uint32_t *)(vector.end() + 0x18)
```

There is no call, branch to a logger, sentinel constant, exception throw, or
fallback selector on the no-match path.  If capacity equals size, this is
beyond the vector allocation.  If spare capacity happens to cover the
address, it is still outside the constructed record range and can contain
arbitrary old bytes.

## FACT: the domain resolver propagates the dword unchanged

GB202 domain 5 enters the common helper with:

```text
0x125c1f6  ecx = incoming instance
0x125c1f8  edx = 0x10ef4000
0x125c1fd  esi = 0x10
             -> 0x1252200
```

The common epilogue at `0x125b989` tail-jumps to `0x1252200`; the latter
tail-jumps to `0xdd2230` on its nonempty-class branch.  Therefore no caller
between the DeviceInfo2 lookup and the raw wrapper converts the returned
dword into a status or checks it.

## FACT: write and read wrappers interpret it as a base

The write wrapper `0xdb5540` first computes the optionally remapped relative
offset in `R12D`.  It calls the GB202 domain resolver at `0xdb567b`, then does:

```text
0xdb5682  add r12d,eax
```

It subsequently tail-calls vtable slot `+0x230` with `ESI = R12D` as the
resolved register address and the requested value in `EDX`.

The read wrapper `0xdb68a0` is symmetric:

```text
0xdb69db  call domain resolver
0xdb69e2  add r12d,eax
             -> vtable slot +0x220
```

Both additions are 32-bit and therefore wrap modulo `2^32`.  Neither wrapper
has an error branch after the resolver call.  In particular:

- a coincidental return of `0` means “base zero,” not “lookup failed”;
- a coincidental return resembling an `NV_ERR_*` value is still an address
  contribution;
- the fixed `0x10ef4000` selector cannot be retried because that decision was
  already discarded by `0x1252200`.

The ordinary write backend has its separate configurable exclusion/write-mask
table, but that is not a DeviceInfo2 membership check.  Existing lifecycle
work shows that table is empty by default, so it is not a general fail-closed
guard for this hypothetical malformed topology.  The direct mapped-aperture
branch ultimately forms `mappedBase + uint32_t(resolvedAddress)`; it does not
repair the resolver result.

## Interpretation

The narrow conclusion is stronger than “unknown error handling” but should
not be generalized into a claim about the real card:

- **FACT:** this binary assumes nonempty class implies the caller's requested
  instance can be found; violating that assumption produces an out-of-range
  host-memory read.
- **FACT:** downstream raw read/write code has no status-aware recovery and no
  selector fallback.
- **INFERENCE:** NVIDIA expects the PTOP parser/hardware table plus its callers
  to maintain a dense/valid instance invariant, rather than making this helper
  robust against malformed class vectors.
- **UNKNOWN:** whether hardware, FSP/GSP policy, or the builder guarantees that
  class `0x10` always includes instance 0 when any class-`0x10` row exists.
- **UNKNOWN:** the actual class-`0x10` rows on this RTX 5090, because reading
  the live table was explicitly out of scope.

For any offline safety model, the conservative behavior should be stricter
than MODS here: if a class vector is nonempty but the requested instance is
absent, reject the topology as inconsistent instead of guessing zero or using
the selector fallback.

## Reproduction notes

The bounded static windows were:

```text
objdump -d -M intel --start-address=0xdd2230  --stop-address=0xdd2367 mods
objdump -d -M intel --start-address=0x1252200 --stop-address=0x12522af mods
objdump -d -M intel --start-address=0x125c1e5 --stop-address=0x125c207 mods
objdump -d -M intel --start-address=0xdb5670  --stop-address=0xdb568a mods
objdump -d -M intel --start-address=0xdb69d0  --stop-address=0xdb69ea mods
objdump -d -M intel --start-address=0xdc74f0  --stop-address=0xdc7644 mods
```

Here `mods` abbreviates the target path and hash stated above.

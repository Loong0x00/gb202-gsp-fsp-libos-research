# GB202 domain-5 instance / base-selector offline audit

Scope: MODS 570.151 ELF
`mods_audit/static/extracted_inner/mods` (SHA-256
`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`).
This is a bounded, offline serialization/address-resolution audit.  The ELF was
not executed and no device interface was opened.

## Result

For the ordinary GB20x accessor constructed by the local factory, the integer
passed as the raw-register `instance` is **0**.  It is not inferred from the
plan offset: the factory passes literal zero to the accessor constructor, the
constructor stores it at `GB20xFuseAccessor+0x8`, and
`ProgramSwFusePlan` later reloads that same field.

For logical domain 5, the GB202 resolver receives that same integer plus mapped
class `0x10` and fixed RegHal selector ID `0x10ef4000`.  The embedded fallback
table has:

```text
index 0 -> 0x00820000
index 1 -> 0x00bf0000
```

Therefore the **fixed-table fallback** for the ordinary instance-0 accessor is
`0x00820000`, not `0x00bf0000`.  A later lifecycle audit closed the alternate
branch: if the lazily parsed PTOP DeviceInfo2 cache contains mapped class
`0x10`, `0x1252200` discards the fixed selector and returns that hardware
record's instance-0 `devicePriBase` instead.  It does not change instance 0 to
instance 1.  The current RTX 5090 table was not read, so its runtime source
choice and numeric `devicePriBase` remain unknown.  See
`parallel/fuse_instance_map_lifecycle.md`. A subsequent complete type-map audit
proves that GB202 PTOP raw type `0x22` maps to this internal class and that the
published fallback name is `NV_FUSE0_PRI_BASE`; see
`parallel/deviceinfo_class10_identity.md`.

## FACT

### 1. The GB20x factory supplies literal instance 0

The factory window allocates the GB20x accessor and calls its constructor at
`0x1431fe3`.  Immediately before the call:

```text
0x1431fd1  lea  -0x80(%rbp), %rcx
0x1431fd5  xor  %edx, %edx
0x1431fd7  lea  0x10(%r12), %rdi
0x1431fdc  mov  -0x150(%rbp), %rsi
0x1431fe3  call 0x1517df0
```

Thus constructor argument 3 (`EDX`) is exactly zero.  This call is tied to the
GB20x class rather than identified only by proximity:

- constructor `0x1517df0` installs vtable address point `0x092f1480` at
  `0x1517e82`;
- the associated RTTI name at `0x092f1440` is
  `17GB20xFuseAccessor`;
- vtable address point `0x092f1480` plus slot `0x40` contains
  `0x1515ea0`, the audited `ProgramSwFusePlan` implementation.

The constructor preserves `EDX` in `R13D` at entry and stores it without
transformation:

```text
0x1517df2  mov %edx, %r13d
...
0x1517edb  mov %r13d, 0x8(%rbx)
```

### 2. The plan dispatcher does not synthesize a different instance

The MultiMacro dispatcher `0x1471530` iterates its slot counter in `R15D`,
selects the accessor pointer for that slot, and calls accessor vtable slot
`+0x40` at `0x1471608`.  The slot counter itself is not passed as an extra
integer argument to `ProgramSwFusePlan`.

At `0x1515ea0`, the writer saves its accessor object in `RBP` and reloads the
instance from the stored member:

```text
0x1515eac  mov %rdi, %rbp
...
0x151605b  mov 0x8(%rbp), %esi
0x1516066  mov $5, %edx
0x151606b  call *writer_slot
```

The same member is also used for the latch request and raw readback at
`0x1515edf` and `0x1515fa5`.  Consequently the integer entering the device
wrapper is the constructor's stored zero, not the plan-node key and not the
MultiMacro loop counter.

### 3. Context is forwarded, but it does not select the domain-5 base

`0xe10d10` constructs the small context object used by the writer by storing
the constant pointer `0x186e9400`.  `ProgramSwFusePlan` loads that value into
`RCX` at `0x1516053`; thunk `0x151ad00` only replaces `RDI` with its contained
GpuSubdevice and tail-calls slot `+0x238`, preserving the remaining arguments.

The generic raw wrapper `0x0db5540` likewise saves `RCX` in `R15` and calls
GpuSubdevice slot `+0x218` with:

```text
ESI = accessor instance
EDX = logical domain
RCX = forwarded context
```

However, the GB202 domain-5 case does not use that context to choose the
resolver input.  `0x125b720` saves the incoming context in `R9`, but domain
5 selects the first jump-table entry (`0x092b3d38 -> 0x125c1f6`), whose code is:

```text
0x125c1f6  mov %esi, %ecx          # instance becomes selector index
0x125c1f8  mov $0x10ef4000, %edx   # base-selector RegHal ID
0x125c1fd  mov $0x10, %esi
             -> 0x1252200
```

The original context saved in `R9` is not forwarded to `0x1252200` on this
case.  The request is keyed by class `0x10` and integer instance 0; inside
`0x1252200`, the available DeviceInfo2 class vector decides whether the base
comes from hardware topology or the fixed selector fallback.

### 4. The fixed-table branch turns instance into RegHal index 0

At entry, `0x1252200` saves `ECX` in `R12D` and the selector ID in `R13D`.
On its embedded-table branch it allocates a one-dword index vector and writes
the saved instance into its first element:

```text
0x1252202  mov %edx, %r13d
0x1252207  mov %ecx, %r12d
...
0x1252248  mov %r12d, (%rax)
...
0x1252261  mov %r13d, %edx
0x1252268  call 0x1988910
```

`0x1988910` passes the selector ID and that vector to `0x1983580`.
The bounded helper `0x19834c0` reads each 32-bit vector element, checks that it
fits in 16 bits, copies it into the table-search key, and calls the table
lookup.  Therefore accessor instance 0 selects table tuple
`idx=(0,0,0,0)`; it cannot select the `idx=(1,0,0,0)` row unless the instance
integer is 1.

### 5. The embedded GB202 table fixes the two values

The existing offline decoder was run only against the ELF's compressed RegHal
table:

```text
python3 gb202_reghal_offline.py --id 0x10ef4000 --include-metadata
```

It identified chip table `0xff2` at file offset `0x8fd61aa` and decoded:

```text
row 7027  id=0x10ef4000  idx=(0,0,0,0)
          words=(0,0,0,0x00820000)
row 7028  id=0x10ef4000  idx=(1,0,0,0)
          words=(0,0,0,0x00bf0000)
```

Combining the proved constructor value with the proved selector-index flow
gives `instance 0 -> 0x00820000` **when the fixed-table branch is selected**.

## INFERENCE

- The factory's explicit zero, its insertion of that accessor into the normal
  accessor container, and the single-die GB202 use case make this the ordinary
  primary-die path.  The key conclusion does not require interpreting `0` as a
  marketing die number; it follows from the table index mechanically.
- The separately audited alternate route is an object-owned, lazily populated
  cache of PTOP DeviceInfo2 hardware rows, not an externally supplied prebuilt
  map.  If class `0x10` is populated, it still looks up instance 0 but obtains
  `devicePriBase` from the matching hardware record.  That value is very
  strongly expected to be `0x00820000` on an ordinary device because both the
  fallback and NVIDIA 610's stateless GB202 primary-FUSE getter return that
  value. This expectation is not promoted to a live-row FACT without a saved
  table capture; see `parallel/deviceinfo_reset_stability.md`.

## UNKNOWN

- This audit plus `parallel/fuse_instance_map_lifecycle.md` proves the two
  address sources but not which one this RTX 5090 currently selects, nor the
  runtime class-`0x10` instance-0 `devicePriBase` if the vector is populated.
- A follow-up also proved that a nonempty class missing requested instance 0
  does not fail closed: the optimized lookup returns a dword read past
  `vector.end()` and the raw wrapper consumes it as a base. What remains
  unknown is whether a valid GB202 DeviceInfo2 table can violate the instance-0
  invariant. Published 610 builders do not enforce it and the public lookup
  explicitly supports an absent tuple; only the unpublished physical producer
  could still guarantee it. See `parallel/deviceinfo_instance_nomatch.md` and
  `parallel/deviceinfo_instance_invariant.md`.
- It does not assign a hardware meaning to the secondary `0x00bf0000` aperture
  beyond the embedded selector's index-1 value.
- It does not prove anything about register accessibility or device behavior;
  only the offline integer provenance and address-selection interface were
  examined.

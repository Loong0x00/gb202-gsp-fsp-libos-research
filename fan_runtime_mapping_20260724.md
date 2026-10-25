# ASUS RTX 5090 Astral runtime fan mapping (2026-07-24)

## Confirmed physical grouping

Tested through NVIDIA's normal fan-control attributes at 30% versus 100%:

- logical `Fan 0` / controller 0 drives physical fans **1 and 3**: the fan near
  the case rear panel and the fan near the case front panel;
- logical `Fan 1` / controller 1 drives physical fans **2 and 4**: the middle
  fan and the rear-side/backplate fan.

The grouping is therefore interleaved, not two adjacent pairs.  This is a
direct physical observation by the card owner.  Driver telemetry independently
showed each logical channel reaching about 3,270 RPM at a 100% target while the
other remained near 600 RPM at a 30% target.

## Static VBIOS GPIO mapping already established

- controller 0: PWM GPIO line 16 (`0xD650` pad/mux candidate), tach line 13
  (`0xD644`);
- controller 1: PWM GPIO line 3 (`0xD61C`), tach line 7 (`0xD62C`).

The precise PTHERM PWM-generator slot behind each GPIO line is still not
runtime-confirmed.

## Public PCB evidence and the third channel

Hardwareluxx forum post #3715 (2026-01-29, updated 2026-02-03) independently
matches the runtime observation above:

- Astral Black connects all four fans through two GPU channels.  Its rear-side
  fourth fan shares a channel with the middle front fan.
- Astral White uses three GPU channels.  Its rear-side fan has a dedicated PWM
  and tach signal.
- Matrix VBIOS on an otherwise unmodified Astral Black exposes three software
  controls, but only the first two work; the third control is inert.
- Making the third control physical requires a separate, multi-jumper fan
  modification using 0-ohm 0402 links.  This is distinct from the single
  100-kohm EEPROM-SI strap change used to make Matrix VBIOS acceptable.

Source: <https://www.hardwareluxx.de/community/threads/offizieller-nvidia-rtx-5090-overclocking-und-modding-thread.1363289/page-124#post-31082403>

Full-resolution copies of the four annotated PCB photographs are retained in
`sources/hardwareluxx_post_3715/` with their original attachment names.

## Matrix-VBIOS early-start gate

Contemporary user reports distinguish this from a mere `nvflash` device-ID
check.  Astral Black users could write the Matrix image, but the next boot
commonly produced no display or a Windows Code 43; several independent users
reported the incompatibility.  After the 100-kohm EEPROM-SI resistor was moved
from the pull-down position to the pull-up position, unchanged signed Matrix
VBIOS images initialized and ran normally on modified Black cards.

This strongly indicates an early hardware-state/board-configuration gate.  The
SI net is sampled before or during very early VBIOS initialization, so the
Matrix image sees a compatible state only with the pull-up.  Public evidence
does not yet identify whether the consumer is the GPU boot ROM itself or an
early signed VBIOS/FSP/GSP component, so that exact attribution remains open.
It is not a failure of the Matrix image's cryptographic signature, since the
same signed bytes work after only the resistor position changes.

Supporting reports:

- <https://www.hardwareluxx.de/community/threads/asus-rog-matrix-platinum-geforce-rtx-5090-sondermodell-ab-ende-november-verf%C3%BCgbar.1373366/page-7>
- <https://www.hardwareluxx.de/community/threads/asus-rog-matrix-platinum-geforce-rtx-5090-sondermodell-ab-ende-november-verf%C3%BCgbar.1373366/page-8>

The two full-resolution EEPROM-SI comparison photographs are retained beside
the fan-routing photographs in `sources/hardwareluxx_post_3715/`.

Offline comparison of all three local Matrix ROMs against the local Astral
Black/LC ROMs identifies the dormant third channel exactly:

| channel | PWM GPIO tag / line / pad register | tach GPIO tag / line / pad register |
|---|---|---|
| 0 | `0x09` / 16 / `0xD650` | `0x3D` / 13 / `0xD644` |
| 1 | `0xD1` / 3 / `0xD61C` | `0xD2` / 7 / `0xD62C` |
| 2 (Matrix/White-style) | `0xFA` / 1 / `0xD614` | `0xFB` / 2 / `0xD618` |

At GPIO-table offset `legacy+0x4835`, Astral Black/LC marks lines 1 and 2 as
unused (`0xFF`).  Every local Matrix ROM changes those same records to tags
`0xFA` and `0xFB`.  Its `FAN_COOLERS` header likewise changes the slot list
from `00 01 ff ff` to `00 01 02 ff`.  This is strong evidence that the PCB
modification routes the rear fan onto GPU GPIO lines 1/2; the exact downstream
PTHERM PWM-generator slot still needs a runtime read to confirm.

## MSI Lightning cross-flash fan failure

Both local Lightning images, 800 W (`281640`) and 1000 W (`281649`), have the
same one-channel topology:

- `FAN_COOLERS` active slots: `00 ff ff ff`;
- GPIO line 16 / tag `0x09` PWM and line 13 / tag `0x3D` tach remain active;
- GPIO lines 3/7, used by Astral Black channel 1 (`0xD1`/`0xD2`), are marked
  `UNUSED`.

Therefore an Astral Black running either Lightning VBIOS drives only its
physical fans 1 and 3 through logical channel 0.  Physical fans 2 and 4—the
middle/front and rear-side pair observed on logical channel 1—receive no normal
VBIOS fan-channel initialization.  This exactly predicts the reported
two-spinning/two-stopped behavior.

## Failed sysfs BAR0 snapshot method

With the NVIDIA driver bound, this kernel rejects direct userspace access to
`/sys/bus/pci/devices/0000:01:00.0/resource0`:

- read-only `mmap`: `EINVAL`;
- four-byte read/pread: `EIO`.

Consequently the `fan_probe_20260724_022642` snapshot files are empty and do
not contain register evidence.  This is an access-path limitation, not a
negative result for any PWM candidate.

The next read-only route is a fixed-address kernel probe like the existing
`bar0_read_probe`, rebuilt for the running kernel and limited to the already
identified GPIO/PTHERM candidates.

## Runtime software-workaround boundary (2026-07-25)

The second Astral channel was isolated again with LACT paused and NVIDIA's
normal control path.  At a 100%/30% split, the selected logical channel reached
about 2,440--2,500 RPM while the other stayed around 580--610 RPM.  LACT was
then restored and is active.  Raw samples are under
`fan_probe_20260725_231421_rm_lact_paused/` and
`fan_probe_20260725_231808_kernel_mmio/`.

A fixed-address, read-only kernel BAR0 probe did not reveal a usable GB202 PWM
duty register.  GPIO pad candidates `0xD61C`, `0xD62C`, `0xD644` and `0xD650`
all returned the protected sentinel `0xbadf1100`; old-generation PTHERM duty
candidates remained static while either fan channel changed speed.  Thus the
old PTHERM register guesses cannot be used as a GB202 fan-control workaround.

Driver 610.43.03 publishes four nominal internal GPIO controls in
`ctrl2080gpio.h` (`0x20802300..0x20802303`), including physical-pin direction,
output, input and hardware-function mux operations.  An ordinary external
client receives RM status `0x56` (`NV_ERR_NOT_SUPPORTED`) because these are
`0xc0` internal controls.  That result described the host access gate, not the
GB202 implementation: after a root-only local driver hook marked only these
commands internal, the requests reached GSP and returned success.

The earlier static claim of a one-entry descriptor shift was wrong.  The table
walker had associated each handler with the preceding descriptor.  A no-reload
runtime discriminator on 2026-07-26 settled the mapping directly:

| command | verified destination |
|---|---|
| `0x20802300` | GPIO `ProgramDirection` |
| `0x20802301` | GPIO `ProgramOutput` |
| `0x20802302` | GPIO `ReadInput` |
| `0x20802303` | GPIO `ActivateHwFunction` |

Using the alleged shifted read command (`0x20802301`) to sample GPIO13 250
times returned constant zero.  After changing only the command/profile to the
published `ReadInput` ID (`0x20802302`), 1000 GPIO13 samples returned 502 zero,
498 one, and 92 transitions while the known fan group was spinning.  This is
an objective live discriminator; the public header and generated RM table are
correct, and the prior shifted-table interpretation must not be reused.

The ordinary cooler API is VBIOS-object based rather than physical-pin based.
Its public structures carry cooler IDs returned by GetInfo; they do not provide
an arbitrary GPIO field.  This makes it unsuitable for creating Astral channel
1 after Lightning VBIOS omitted that cooler and marked GPIO lines 3/7 unused.

Consequences for a Lightning cross-flash:

- a brief boot/idle enumeration test can be bounded and rolled back while only
  physical fans 1 and 3 run;
- a high-power benchmark is not acceptable with physical fans 2 and 4 stopped,
  because the stopped pair includes the middle/front and rear-side fans and can
  leave memory/VRM cooling uneven;
- the currently demonstrated workaround is external fan wiring: power/control
  the missing group from a motherboard/controller adapter, or share only a
  known-good PWM control signal while retaining appropriately rated power and
  avoiding tied tach outputs.  Exact connector pinout must be checked before
  fabricating such an adapter;
- a pure software workaround would require new GB202-specific low-level fan
  control, not a LACT/NvAPI setting or a root permission bypass.  It is not yet
  demonstrated.

## Direct physical BAR0 write result (2026-07-26)

A one-shot kernel probe bypassed the NVIDIA cooler object/API and mapped the
GPU's actual PCI BAR0 resource directly.  On this boot BAR0 was physically
mapped at `0x00000000d8000000`, making the targets:

- GPIO3 pad/control: CPU physical address `0x00000000d800d61c`
  (`BAR0+0x0000d61c`);
- PMGR GPIO shadow trigger: CPU physical address `0x00000000d800d604`
  (`BAR0+0x0000d604`).

With the NVIDIA driver still bound and the GPU nearly idle, the probe issued:

1. `readl(BAR0+0xd61c)`;
2. `writel(0x00042000, BAR0+0xd61c)` to select normal open-drain output and
   hold GPIO3 low (the full-duty request for an active-low four-wire fan PWM);
3. `writel(1, BAR0+0xd604)` to request the GPIO shadow update;
4. a posted-write flush and another `readl(BAR0+0xd61c)`.

The exact kernel result was:

```text
GPIO3 0xbadf1100 -> wrote 0x00042000 -> read 0xbadf1100
```

No NVIDIA Xid appeared and the GPU remained responsive.  The module was then
unloaded without resetting the display GPU.  This proves that the test reached
the real host PCI MMIO aperture, but the host-visible BAR0 path returned the
protected `0xbadf1100` sentinel both before and after the store.  It therefore
does not demonstrate that the internal GPIO register accepted the value; an
internal privileged/GSP-side path remains distinct from this CPU BAR0 path.

## No-desktop-reload path and selector correction (2026-07-26)

All work in this section was static or read-only.  No module described below
was loaded, no display service was restarted, and no GPU/VBIOS write was made.

Root `EXEC_REG_OPS` confirms that the GSP path can read the two GB202 PWM
sources while the protected GPIO pad/mux registers remain inaccessible:

```text
PWM10 0x118ab0 = 0x010003e8   PWM10 0x118ab4 = 0x00000150
PWM11 0x118ab8 = 0x1a0000d8   PWM11 0x118abc = 0x00000000
GPIO pad/mux reads = 0xbadf1100
```

The original Astral ROM maps physical fan group 2/4 to GPIO3 function `0xd1`
and PWM selector `0x5c` (PWM11), with GPIO7 function `0xd2` as tach.  The
Lightning ROM instead creates GPIO3's runtime record as function `0xff` with
selector `0`.  Disassembly of GSP `ActivateHwFunction` at `0x017f699c` shows
that selector zero is not a generic-GPIO mode: after matching the requested
function it enters the assertion/error path instead of calling the hardware
selector method.  Therefore `Activate(0xff, GPIO3)` is not a valid or safe mux
operation and must not be used.

The actual GB202 raw selector method is `OBJGPIO +0x250`, implemented at GSP VA
`0x01802f74`.  It preserves the rest of the per-pin word and replaces its low
selector byte.  The required operation for the Astral second fan group is thus
conceptually `selector(GPIO3) = 0x5c`; direction/output calls alone cannot
create that route.

A no-driver-reload host bridge was built under `gpio_internal_bridge/` for
offline review only.  It uses a one-shot, same-thread, two-second kprobe arm at
`serverControl_ValidateCookie` and changes only the per-call `bInternal` byte.
The byte offset is `0x68`, confirmed both by `pahole` and the currently installed
610.43.03 `nvidia.ko` instruction `cmpb $0,0x68(%rbx)`.  The module is not
loaded.  This bridge can cross the host-side internal-control gate but cannot
by itself supply the missing GSP runtime selector record, so it is not yet a
fan 2/4 solution.

The GSP also has an `OBJGPIO +0x298` helper at `0x01805b30`.  For a pin whose
two saved selector bytes are both zero, its enable path programs fixed selector
`3` before applying software direction/output state.  This is evidence for a
possible full-speed/static-level fallback, not PWM11 control: no external RM
control that reaches this helper with an arbitrary pin has yet been identified,
and selector `3` is not selector `0x5c`.

The two initially suspicious undocumented display controls are negative:

- `0x730127`, 32-byte params, handler `0x0121c014`, returns display-system
  state and does not carry an arbitrary GPIO pin/selector;
- `0x730138`, 12-byte params, handler `0x011ece34`, walks display objects and
  reports a mask; it likewise exposes no arbitrary GPIO selector.

The official ASUS GPU Tweak III package was also inspected without running it.
Its exported NVIDIA direct-register fan slots in `Exeio.dll` are stubs returning
failure, while `Vender.dll` references an absent `nvgpio.dll`.  Consequently the
package does not contain a reusable NVIDIA GPIO3/PWM11 implementation.

### ASUS I2C / ITE8915 closure (2026-07-26)

The ASUS utility's `IC_IT8915` implementation was statically inspected as a
possible out-of-band fan path.  It sends ordinary I2C requests with an 8-bit
device identifier `0x52` (Linux 7-bit candidate `0x29`) and reads/writes its
own telemetry/control registers.  This is not evidence that it controls the
missing GPU PWM group.

The decisive local discriminator already exists: on this Astral PCB, the
actual onboard IT8915FN-56 is reachable on NVIDIA I2C port 1 at address
`0x2b`.  During a 30% -> 100% -> 30% test of the still-working fan group 1/3,
its `0xa2:0xa3` field changed from `03 a0` to `04 58` and back, while physical
fans 2/4 remained stopped.  It is the independently used 12V-2x6 input-power
detector, not a controller for 2/4.  No arbitrary I2C probing or writes are
justified by the GPU Tweak strings.

Thus the hardware evidence remains consistent with the Astral DCB mapping:
physical group 2/4 is driven directly by GPU GPIO3 -> PWM11, and restoring it
requires the missing GSP GPIO/FanCooler runtime object rather than an external
I2C fan-controller command.

### Public GSP test-control closure (2026-07-26)

The public 610.43.03 headers expose controls named `GPU_RPC_GSP_TEST`,
`GSP_CORE_TEST`, and `GSP_GDMA_FUZZ_TEST`.  They are not a generic RPC escape
hatch.  The host implementation of `GPU_RPC_GSP_TEST` accepts only four
enumerated tests (integrity, unserialized IP-version request, NOP, timeout) and
for the serialized cases forwards the *same test control* to the GSP.  It has
no field for an arbitrary RM control ID, GSP function pointer, GPIO pin, or
selector.  The other two controls are fixed memory/DMA test workloads.

They therefore cannot reach the raw GPIO selector method or instantiate a
FanCooler object, and are not candidates for a live fan recovery experiment.

The subsequent caller enumeration is recorded below.  It found no existing
control that accepts a caller-supplied pin/selector.  The remaining
software-only hypotheses therefore require either a GSP-owned runtime-record
update mechanism or a newly discovered, narrowly scoped GSP debug operation;
host BAR0 and ordinary root RegOps are already excluded by direct readback.

## No-reload normal-GPIO live discriminator (2026-07-26)

The one-shot bridge was dynamically loaded without replacing or reloading any
NVIDIA module.  Active VBIOS and driver were verified as `98.02.2E.C0.0F` and
`610.43.03`.  The Lightning and original-Astral GPIO3 DCB records are:

```text
Lightning  GPIO3: 03 ff 00 00 ef 10
Astral     GPIO3: 03 d1 00 80 ef 10
```

Both records specify initial state zero and input direction; Astral additionally
assigns function `d1` and the PWM attribute.  The live test therefore staged
the output latch before selecting output direction, tested both constant
levels, then restored input direction followed by latch zero.

The published command mapping was first validated using GPIO13:

```text
samples=1000 value0=502 value1=498 transitions=92
```

The bounded GPIO3/GPIO7 result was:

```text
gpio13-known-baseline: 1140 samples, 80 transitions
gpio7-baseline:         1140 samples, 0 transitions, all high
GPIO3 output value 1:   GPIO3 input 0; GPIO7 2280 samples, 0 transitions
GPIO3 output value 0:   GPIO3 input 0; GPIO7 2280 samples, 0 transitions
restore direction=input: SUCCESS
restore output-latch=0: SUCCESS
```

GPU temperature remained 40 C, the driver reported no new Xid/NVRM error, and
the bridge module was unloaded afterward.  This directly disproves the static
high/low fallback on the current board: crossing the internal-control gate and
programming normal GPIO direction/output are not sufficient to start fan group
2/4.  The remaining runtime path must restore GPIO3's Astral PWM hardware
function, ultimately selector `0x5c` (PWM11), rather than treating GPIO3 as a
constant-level output.

Reproducible artifacts after this run:

```text
bridge_gpio3_static_probe  7fd457097070b3f4db0b6db5836ed62c8cce9857206eb773dd7e311776d1070e
bridge_read_probe          1cd2c2b78608d45121c58fac669f5d13d50a6e36f65a6cd0e996e0c782f67ed2
nv_gpio_internal_bridge.ko 5bdabb88ef265cf21f0af82d976b638a9059d35c4c924cbf87f252f1ef39b209
```

## Selector-setter closure and D1 activation discriminator (2026-07-26)

All eight direct calls to the GSP runtime-record selector setter
`0x017fe5b4` were classified:

- `0x01181530` builds a record from the VBIOS/DCB GPIO entry and copies its
  selector fields;
- `0x011f11f2` and `0x011f12e8` are the display SLI-link GPIO temporary
  disable/restore sequence;
- `0x0121cb96` inserts another firmware-table-sourced record and copies the
  two selector bytes from that table entry;
- `0x0122a6a2` and `0x0122a6fe` belong to `OBJSOR` (class ID `0x5ccbfa`) and
  temporarily replace/clear a selector before restoring display state;
- `0x01294852` and `0x0129487c` are cleanup paths that write selector zero.

The apparently promising `OBJSOR` helper at `0x0122a5a0` does not accept an
arbitrary selector.  Its callers first locate the GPIO record for the SOR's
pre-initialized function, read the record selector with `0x017fe68c`, and save
that byte at object offset `+0xc38`.  The helper can only apply that saved byte
or zero.  It therefore cannot turn Lightning's GPIO3 `ff/0` record into
Astral's `d1/5c` record.  The raw GB202 selector method `0x01802f74` appears
only as three vtable-address initializations, not as an exported direct call.

A bounded live discriminator then issued the published internal
`ActivateHwFunction` control with exactly `function=0xd1, pin=3`.  Static
analysis establishes that the handler checks the existing record's function
before invoking the hardware selector, so a mismatch has no selector-write
path.  Runtime result:

```text
active VBIOS before: 98.02.2E.C0.0F
GPU temperature before: 40 C
activate discriminator: function=0xd1 pin=3 rm_status=0x0000ffff
GPU temperature after: 40 C
bridge module after: unloaded
new Xid/NVRM errors: none
```

This confirms experimentally that `ActivateHwFunction` will not create or
upgrade the missing runtime record.  The next required primitive is a GSP-owned
runtime-record update that installs GPIO3 function `0xd1` and selector `0x5c`,
or an existing narrowly scoped operation that reaches the raw selector method.

New artifact:

```text
bridge_activate_d1_probe b1c6bd67c907e6bd930d60eeef08ec995216096743fe6a1e3c18c53b2cc16975
```

## Runtime-object and raw-selector closure (2026-07-26)

The relevant GSP GPIO primitive at `0x01802f74` was decompiled directly.  Its
second argument is bounded by the GPIO-record count at `object + 0x25a4`; it
then preserves the upper bits of the selected hardware word and replaces its
low byte with the caller-supplied third argument.  Thus the desired physical
operation is unambiguous: an existing caller of that primitive could select
Astral GPIO3's PWM11 route by supplying `pin=3, selector=0x5c`.

That primitive is not directly exposed as an RM control.  A dedicated static
scan of short RISC-V `ld fn,0x250(object); indirect-call fn` sequences found
the GPIO-owned path at `0x01805b70`, inside the already-audited helper rooted
at `0x01805b30`.  That helper only consumes the selector stored in the
existing runtime GPIO record.  With Lightning's GPIO3 record (`function=ff,
selector=00`), it cannot synthesize the missing `d1/5c` pair.

The FanCooler allocator at `0x01b835ec` has four direct GSP call sites in the
610.43.03 image:

```text
0x011cdcfc, 0x011ce434, 0x012f296a, 0x012f2af6
```

The latter two are in the same firmware-table/board-object initialization
flow: they obtain a table entry through its callback, allocate the object, and
insert it into a board-object group.  They are not RM command handlers.  The
standard `0x2080c535` and `0x2080c541` handlers also only locate an already
existing child object and dispatch to it; they return the normal missing-object
error instead of constructing one.

Finally, the public 610.43.03 `ctrl2080bios.h` BIOS control family contains
only GET operations (info, NBSI, SKU, post time, UEFI support).  It exposes no
reload/reparse operation capable of applying the original Astral fan table at
runtime.  This closes the normal public-RM route: restoring fans 2/4 requires
either a GSP-owned update of the runtime GPIO/FanCooler records, a GSP debug
entry point, or starting the GPU with a ROM that advertises both controllers.

## Object-creation and debug-knob follow-up (2026-07-26)

Two narrow follow-ups remove the remaining plausible normal-RM shortcuts.

1. **Retargeting an otherwise valid fan command does not create channel 1.**
   A local test intercepted only the already-valid physical FanCooler control
   `0x2080c531`, moved its one 56-byte record from index 0 to index 1, and
   changed both masks from `0x1` to `0x2`.  GSP accepted the transport ioctl
   but returned RM status `0x1f`; Fan0 remained at 30% and about 800 RPM.
   The identical command without the index change succeeds.  This is a direct
   runtime proof that the failure is a missing child object, rather than a
   hidden range limit or a user-mode choice of fan index.

2. **The only allocator callers are firmware-table importers.**  A fresh,
   offline decompile of the two analyzable direct callers at `0x011cdcfc` and
   `0x011ce434` shows both reading a table entry through `0x011751ac`, building
   a local cooler descriptor, calling the allocator `0x01b835ec`, then
   inserting the result through a board-object-group callback.  The records
   are built only while enumerating VBIOS table entries; neither routine is an
   RM request handler.  The two remaining direct references remain in the same
   static initialization family.  No existing dynamic create/reparse path was
   found.

`RMEnableNonSiliconGpio` was also checked because its string occurs near GSP
GPIO code.  Its enclosing routine is an assertion/error-report path for a
non-silicon configuration: it reports an error and executes `ebreak` when the
flag is absent.  It is not a callable fan/GPIO control and gives no path to
create the Lightning-omitted GPIO3 record.

An attempted **read-only** sysfs BAR0 read of the Blackwell WPR2-boundary page
was rejected by this running kernel at `mmap` with `EINVAL`, before any GPU
register access.  It therefore supplied no WPR values and does not alter the
existing conclusion that the host BAR0 access path is unavailable while the
NVIDIA driver owns the device.

## GSP-resident FanCooler copy: object path and access boundary (2026-07-26)

The exact *object path* for the copy is now established from the 610.43.03
GSP-RM image.  This is distinct from merely knowing that a general GSP heap
exists:

```text
VBIOS FAN_COOLERS / fan-management entry
  -> temporary GSP cooler descriptor on the importer stack
  -> FanCooler child object, allocated by 0x01b835ec
  -> persistent GSP BoardObjGrp passed as argument a3
```

The main importer begins at `0x011cd878`.  Its caller at `0x012f2772` passes
the persistent group in `a3` (`a3 = s6` immediately before the call).  The
importer constructs one local descriptor for each VBIOS table entry, invokes
the allocator at `0x01b835ec`, then calls the group vmethod at `+0x30` to add
the returned child.  The allocator's first implemented variant requests
`0xf0` bytes, copies the descriptor fields starting at child offset `+0x80`,
and installs the FanCooler vmethods.  Thus the current Lightning boot has one
such child at group index 0; it does not have a dormant index-1 child whose
speed could simply be set.

The group pointer is a GSP heap pointer, not an EEPROM offset or normal host
VRAM pointer.  The parent board-initialisation flow allocates and zeroes the
group before calling the importer (the live pointer is held in `s6`; the
allocation size in this branch is `0x2b0`).  Its numeric virtual address is
chosen anew by the GSP heap allocator each boot.  That is the runtime copy to
target if a supported GSP-side update primitive is found.

The public host driver has a superficially relevant method,
`0x20800afa` (`INTERNAL_MEMMGR_MEMORY_TRANSFER_WITH_GSP`), whose ABI describes
physical-address memcpy/memset performed by GSP.  It is *not* an available
reader for this object on the installed kernel: the generated 610.43.03
Subdevice implementation compiled for this configuration returns
`NV_ERR_NOT_SUPPORTED` unconditionally.  Separately, it operates on physical
transfer surfaces, while the FanCooler group above is addressed through the
GSP's private virtual heap.  Therefore there is currently no host-visible,
read-only route from the discovered object path to its live address.

This narrows the remaining work to either:

1. identify a GSP-owned debug/introspection RPC that enumerates a BoardObjGrp;
2. identify a GSP-side code path that can invoke the existing importer or add
   a child after boot; or
3. recover the GSP virtual-to-physical mapping and a permitted read primitive.

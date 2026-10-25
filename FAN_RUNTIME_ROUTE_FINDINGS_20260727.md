# GB202 fan runtime route findings — 2026-07-27

Scope: ASUS Astral Black RTX 5090 running MSI Lightning 800 W VBIOS.  This
file records only new route findings; it does not restate the already-known
"Lightning initializes only one cooler" premise.

## Confirmed static facts

The public/generated 610.43.03 RM GPIO control ABI exposes only four internal
GPIO methods:

- `0x20802300` program direction: inputs `gpioPin`, `bInput`
- `0x20802301` program output: inputs `gpioPin`, `value`
- `0x20802302` read input: input `gpioPin`, output `value`
- `0x20802303` activate hardware function: inputs `function`, `pin`

No public/generated GPIO control takes the required runtime pair
`function=0xd1`, `selector=0x5c`, or a raw selector byte.

The GSP side contains a generic raw-selector wrapper at `0x01bca3f8`.
It:

1. receives `a0=GPIO object`, `a1=pin/function-index`, `a2=selector`;
2. validates that the selected runtime record exists;
3. jumps through `object + 0x250`.

For the GB202 GPIO class, `object + 0x250` is the raw selector method
`0x01802f74`.  Therefore `0x01bca3f8` is a usable internal wrapper only if an
existing caller can supply `a1=3` and `a2=0x5c`, or if another path can write
the GPIO3 runtime record first.

Known direct callers of `0x01bca3f8`:

```text
0x011f11fc
0x011f12f4
0x0122a6ae
0x0122a708
0x0129485c
0x01294886
0x017ffa54
0x017ffa64
0x017ffa8a
0x0180003c
0x0180004c
0x01800072
0x01800630
0x01800640
0x01800666
0x01808250
0x01808272
```

The first six are previously classified restore/cleanup/SOR paths.  The
`0x017ffa..`, `0x018000..`, and `0x018006..` families do compute selector-like
values and call the wrapper, but the values are derived from existing
board/display configuration fields, not from a host control payload.  They are
not arbitrary selector setters.

## New registry-key route findings

The GSP image contains these relevant registry strings:

```text
RmFan2XOverride
RMEnableNonSiliconGpio
RMDisableThermOnlyGpio
RMForceEnableBrightnessOverPwmPin
RMSCIVidPWM
RMGpioPmuMutexTimeoutus
RmPmgrOverride
RmPmgrPmuOverride
```

Linux accepts unknown RM registry keys through `NVreg_RegistryDwords` /
`NVreg_RegistryDwordsPerDevice`; the open driver parses unknown `key=value`
pairs and passes them to RM rather than rejecting them as invalid static
module parameters.

Current live module state only shows:

```text
RegistryDwords: "RMUseSwI2c=0x01"
RegistryDwordsPerDevice: ""
```

So none of the candidate keys is active in the current boot.

### 2026-07-27 follow-up: extra PMGR/PWM registry keys

Static string VAs in `/tmp/gsp_inner_19f040_a.elf`:

```text
RMForceEnableBrightnessOverPwmPin  0x01e2ff88  xref 0x011e0ac8
RMSCIVidPWM                        0x01e84c50  xrefs 0x017d9520, 0x017d953c
RMGpioPmuMutexTimeoutus            0x01e8a6d8  xref 0x01be3784
RmPmgrOverride                     0x01e83c38  xref 0x017507d8
RmPmgrPmuOverride                  0x01e83c70  xref 0x01758c8e
```

Current classification:

- `RMForceEnableBrightnessOverPwmPin` is in a display brightness-over-PWM
  initialization sequence.  It reads registry dwords and stores boolean bytes
  around object offsets `+0x701`, `+0x703`, `+0x704`, etc.  The consumer name
  and surrounding strings (`...BrightnessOverAux`, `ipNvsrInit`) point to LCD /
  display brightness, not board fan PWM.
- `RMSCIVidPWM` is in a large SCI VID PWM construction path.  The same key is
  read twice: absent or nonzero continues the VID-PWM object construction; a
  present zero value skips that branch.  The constructed object uses parsed
  voltage/VID-style fields and is not a fan-cooler/GPIO3 selector creator.
- `RMGpioPmuMutexTimeoutus` writes a timeout value into a GPIO/PMU mutex state
  (`+0x7c4`) and sets enable bytes around `+0x7b8/+0x7b9`.  This can affect a
  wait/timeout policy, not synthesize a missing GPIO3/PWM11 runtime record.
- `RmPmgrPmuOverride` controls whether PMGR uses a PMU-backed path.  The code
  initializes `+0x5a0 = 1`, then if the registry value exists and bit 0 is set,
  clears `+0x5a0`.  This is a PMGR backend policy bit, not fan topology.
- `RmPmgrOverride` is a PMGR initialization override.  It is adjacent to
  `RmNvswitchGpioDetect`, writes the registry value to a PMGR object word near
  `+0x4ebc`, then invokes a PMGR vmethod.  It may be a boot-time experiment
  candidate if a driver/GSP reload is acceptable, but static evidence does not
  show any direct route from this key to the required
  `GPIO3 function=0xd1 selector=0x5c`.

Open-source host-side 610.43.03 files contain no direct occurrences of these
five strings, so there is no public source comment or ABI definition to lean on.
They should not be treated as confirmed fan-enabling knobs.

### MODS script surface check

The local decoded MODS JavaScript surface does contain fan controls, but the
relevant paths are table-level controls over existing RM fan objects:

```text
subdev.Thermal.GetFanObject(fanObj)
subdev.Thermal.GetFanCoolerTable(fanObj.coolerMask, ...)
fanCoolerTable[fanIdx].bPwmSimActive = 1
fanCoolerTable[fanIdx].pwmSim = ...
subdev.Thermal.SetFanCoolerTable(fanObj.coolerMask, fanCoolerTable)
```

This is useful for normal MODS fan tests, but it is not evidence of a hidden
script-level primitive that creates a missing second cooler.  On the Lightning
BIOS, where RM/GSP exposes only one cooler in the mask/table, this surface
would still be bounded by the already-constructed cooler set.

### Host ROM / initialization override sweep

Several broad override strings were checked as a possible way to feed a
modified GPIO/FAN table at driver/GSP startup without flashing SPI ROM:

```text
romOverride                    0x01e23198  no direct AUIPC/ADDI xref found
OverrideGpuInit                0x01e87af0  xref 0x01aabada
OverridePanelStrapAndIndex     0x01e26b38  xref 0x01177db8
OverrideSBIOSDevs              0x01e30a60  xref 0x0126c6ea
RmInternalDTDOverride          0x01e72cb8  xref 0x01459aba
RmADSOverrides                 0x01e87d70  xref 0x01aac346
```

The referenced windows are display/board-init override consumers.  They set
small scalar fields such as panel straps, SBIOS device flags, DTD/ADS/display
configuration, or global GPU-init behavior.  No checked window exposes a host
path that supplies a replacement VBIOS image, a replacement DCB GPIO table, or
the required FAN_COOLERS descriptor.  Treat this as a negative for the
"non-flashed ROM-table override" route until a more specific VBIOS/GPIO-table
override string or control path is found.

### `RMEnableNonSiliconGpio`

Static xref: string at GSP VA `0x01e84ff8`; referenced around
`0x017fc47a`.

The consumer is in GPIO object initialization.  It zeroes/initializes GPIO
runtime arrays, then reads `RMEnableNonSiliconGpio` and stores a boolean-like
flag at `GPIO object + 0x2e0`.

The polarity is not what the name suggests:

- if the key is absent, the default path stores `1` at `GPIO object + 0x2e0`;
- if the key is present and set to `0`, it also stores `1`;
- if the key is present and nonzero, it stores `0`.

The adjacent string read in the same constructor window is
`EPC_HWSLOW_FC7E081B`, not `RMDisableThermOnlyGpio`; the earlier note that
`RMDisableThermOnlyGpio` was read nearby was wrong.

This is a boot/init-time knob.  No live control path was found that rereads it
after initialization.

### `RMDisableThermOnlyGpio`

Static xrefs: string at GSP VA `0x01e8a2b8`; referenced around
`0x01bb225a` and `0x01bb2a20`.

Both consumers read the registry dword and branch only when the value is
exactly `1`.  The taken path looks up GPIO function `0x12`, obtains the
corresponding runtime record, sets `record + 0x724 = 0xff`, and clears the
matching bit in a GPIO-object mask at `object + 0x6c8`.

So this knob appears to remove/disable a therm-only GPIO record.  It is not a
candidate for creating the missing GPIO3/PWM11 fan route, and it should not be
combined with `RmFan2XOverride` in a first-pass experiment.

### `0x018080e8` GPIO vmethod

This function is installed into the GPIO class vtable at slot `+0x248`.
It is not a host RM control.

Important behavior:

- looks up GPIO runtime records by function;
- writes `record + 0x72b = 3` for two records selected by board/config fields;
- if enabled, calls `0x01bca3f8(..., a2=3)` for those records.

This proves that GSP can mutate runtime GPIO records after the initial DCB
import, but this specific path only writes fixed function/selector value `3`.
It does not synthesize the Astral requirement `function=0xd1`, `selector=0x5c`.

### `RmFan2XOverride`

Static xref: string at GSP VA `0x01e30ce0`; referenced around
`0x012f12b4`.

The consumer is in the same fan-management/board-object initialization family
as the FanCooler importer.  It reads the registry dword, masks the low two
bits, and chooses among override/fallback branches.  The code allocates a
`0x2b0` group-sized object and swaps several fan policy callbacks.

This is a startup fan policy/import selector, not a direct GPIO3/PWM11 selector
route.  It might alter whether the FanCooler importer/object path is used, but
there is still no evidence that it can synthesize the missing Astral physical
route `GPIO3 = d1/5c` when the Lightning ROM advertises only one active cooler.

Follow-up decode:

- `0x012f12b4` loads the `RmFan2XOverride` string.
- `0x012f12ca -> 0x0103c0cc` reads the registry dword into the stack slot.
- `0x012f12dc` masks the value with `& 3`.
- `(value & 3) == 1` branches directly to `0x012f150e`.
- `(value & 3) == 2` branches directly to `0x012f12f6`.
- unset/other first calls the default board/fan-policy predicate at
  `*(s1 + 0x120)`; predicate return `0` selects the `0x012f150e` branch,
  nonzero selects the `0x012f12f6` branch.

So this key is not boolean.  Values `1` and `2` are useful precisely because
they force opposite sides of the normal board-policy decision.

The `0x012f150e` side patches multiple fan-policy callbacks/fields, then checks
or mutates already-existing GPIO-function records.  The concrete GPIO helper
calls observed on this side are:

- `0x017fec9c(GPIO, 0x47)`;
- `0x017fec9c(GPIO, 0x0a)` and `0x017ff72c(GPIO, 0x0a)`;
- a possible `0x017feb84(GPIO, 0x0a)` followed by a vmethod update of the
  returned runtime record;
- `0x017fec9c(GPIO, 0x92)` followed by `0x01804318(GPIO, 0x92, 0)`.

Current helper classification:

- `0x017feb84(GPIO, func)` maps a GPIO function to an existing runtime-record
  index, or returns `0xff`;
- `0x017fec9c(GPIO, func)` checks that a GPIO function has a valid runtime
  record and that the corresponding pin is initialized/active;
- `0x017ff72c(GPIO, func)` returns a field from the existing runtime record
  when the same validity checks pass.

So the `value=1` / `0x012f150e` branch is now classified as an existing-GPIO
policy/fallback path.  It does not look like a missing FanCooler creator.

The `value=2` / `0x012f12f6` branch is stronger.  It enters the larger
group/object allocation path, allocates a `0x2b0` group-sized object, reaches
the known FanCooler importer call at `0x012f2776 -> 0x011cd878`, and contains
FanCooler allocator calls to `0x01b835ec` around `0x012f296e` and `0x012f2afa`.
This still does not prove that a second physical cooler will be created, because
the Lightning ROM table advertises only slot 0 active.  But if one runtime
reload experiment is performed first, `RmFan2XOverride=2` is now the more
defensible first value.

Importer follow-up:

- The `0x011cd878` importer stores the caller-provided group pointer, then uses
  the common VBIOS/table parser `0x011751ac`.
- The parser calls use compact format descriptors such as `2b`, `4b`, and
  `3b1w12d1b`.  The importer reads table metadata into stack fields, including
  fields used as entry count, entry size, and entry offset.
- The main loop increments an 8-bit index, computes
  `entry_base + index * entry_size`, parses the entry into a temporary stack
  descriptor, and only then calls the group vmethod / FanCooler allocator path.
- Therefore the registry override is not carrying a host-supplied second fan
  descriptor.  It only changes which startup branch reaches the table-driven
  importer.

This narrows the expected behavior of `RmFan2XOverride=2`: it can help only if
the alternate branch changes which VBIOS fan table/subtable is imported or how
the existing active-slot policy is interpreted.  It cannot by itself be the
missing arbitrary GPIO3 selector setter.

## Negative route status

No host-accessible control path has been found that can pass an arbitrary
selector to `0x01bca3f8` or directly call `0x01802f74`.

The closest internal primitive is now known:

## 2026-07-27 late update: raw selector register geometry

The GB202 raw selector method at GSP code VA `0x01802f74` has now been decoded
far enough to identify its register addressing formula.

Behavior summary:

1. validate that the requested GPIO line index is within the runtime GPIO line
   count;
2. obtain a GSP-internal register object pointer;
3. read a 32-bit word through that object's read vmethod;
4. clear the low selector byte with `value & ~0xff`;
5. OR in the requested selector byte;
6. write the word back through that object's write vmethod.

The computed register-object relative offset is:

```text
relative_offset = (gpio_index + 0x880) * 4
```

For the missing Astral fan route:

```text
gpio_index = 3
relative_offset = (3 + 0x880) * 4 = 0x220c
desired low byte = 0x5c
```

This strongly matches the public PMGR GPIO output-control geometry:

```text
NV_GPIO_OUTPUT_CNTL(i) = 0x00021200 + i * 4
NV_GPIO_OUTPUT_CNTL(3) = 0x0002120c
```

The likely relationship is:

```text
GSP internal PMGR register-object base 0x1f000
  + relative_offset 0x220c
  = BAR0-style offset 0x2120c
```

This explains why earlier direct tests against old GPIO pad offsets such as
`0x0000d61c` were not discriminating: the selector path is not that pad
register.

Runtime negative check:

```text
sudo -n /home/user/rt_5090_project/hotspot_reader/rm_mmio_probe \
  0x00021200 0x0002120c 0x0002121c 0x00021240 0x00021244
```

All tested `0x212xx` candidate offsets returned the protected-looking value
`0xbadf1100` through normal external `GPU_EXEC_REG_OPS`.

Interpretation:

- this does not disprove the GSP-internal method, because `0x01802f74` reaches
  the register through a GSP-owned register object and vmethods;
- it does show that ordinary host/root RM regops do not expose the true
  register value for these GPIO output-control offsets on this build;
- therefore do not repeat ordinary BAR0/regops read/write attempts at
  `0x2120c` unless a different access path is first identified.

Current reduced target:

Find a host-reachable path that either:

1. invokes the same GSP-internal raw selector method with
   `gpio_index=3, selector=0x5c`; or
2. writes the GPIO runtime record so a normal GSP path later invokes that
   method on GPIO3.

## Host-entry follow-up: direct selector callers are not host-payload driven

`0x01802f74` address references:

```text
0x01941ca6 address -> 0x01802f74
0x0194247a address -> 0x01802f74
0x01942b2e address -> 0x01802f74
```

These are vtable/address-installation sites, not ordinary call sites.

The wrapper `0x01bca3f8` has 13 direct call sites in the current exact GSP
image:

```text
0x011f11fc
0x011f12f4
0x0122a6ae
0x0122a708
0x0129485c
0x01294886
0x017ffa54
0x017ffa64
0x0180003c
0x0180004c
0x01800630
0x01800640
0x01808250
```

The GPIO-near families around `0x017ffa..`, `0x018000..`, `0x018006..`, and
`0x01808250` derive their selector argument from existing parsed
configuration/runtime-record state or use a fixed selector value (`3`).  They
do not expose a host-supplied selector byte.

The earlier static “one entry shifted” command-ID suspicion was also
superseded by runtime bridge evidence in
`/home/user/rt_5090_project/gpio_internal_bridge/README.md`: the currently
working GPIO commands are the published `0x20802300..0x20802303`
direction/output/read/activate IDs.  `ActivateHwFunction(function=0xd1,
pin=3)` returned `0x0000ffff`, so simply crossing the internal-permission gate
is insufficient.

## VBIOS-buffer side path status

The open driver does extract a VBIOS image into a CPU-side
`KernelGspVbiosImg->pImage` buffer:

```text
kernel_gsp.c: kgspExtractVbiosFromRom_HAL(...)
kernel_gsp_vbios_tu102.c: pVbiosImg->pImage = copied PROM image
```

However the observed use in the open 610.43.03 source is the GSP/FWSEC/FRTS
boot path:

```text
kgspExtractVbiosFromRom
  -> kgspParseFwsecUcodeFromVbiosImg
  -> kgspFreeVbiosImg
```

No open-source caller was found that sends this CPU-side VBIOS image to the
normal GSP FAN/GPIO/DCB importer.  Therefore patching this extracted
`pVbiosImg` buffer is not currently a proven way to change the runtime fan
topology.  It may affect FWSEC/FRTS parsing, which is the wrong layer for the
missing Astral fan route.

## RM object allocation / thermal public API status

The ordinary RM allocation route does not currently look useful for this
problem:

- `RMCFG_MODULE_GPIO` is disabled in the open 610.43.03 build, while
  `RMCFG_MODULE_KERNEL_GPIO` is enabled.
- `OBJGPIO` exists as a kernel/engine class (`classId(OBJGPIO)`), but no user
  resource-list entry was found that would let a client allocate or construct a
  GPIO object.
- Therefore `GSP_RM_ALLOC` is not presently a candidate for creating the
  missing GPIO3/FanCooler child.

The public thermal execute API is also not a construction path:

- `NV2080_CTRL_CMD_THERMAL_SYSTEM_EXECUTE_V2` /
  `NV2080_CTRL_CMD_THERMAL_SYSTEM_EXECUTE_V2_PHYSICAL` expose target, provider,
  sensor count, sensor target/provider, reading range, and current reading
  instructions.
- The open header and CPU-side implementation do not expose cooler creation,
  GPIO selector mutation, or fan topology override operands.

This leaves the realistic software routes as:

1. find another internal GSP/RM control whose existing ABI reaches the GPIO
   runtime-record setter or raw selector method;
2. patch driver/GSP initialization so the existing VBIOS/table importer sees a
   second valid cooler route before fan objects are built;
3. locate a narrow live GSP object pointer and mutate only the known GPIO3
   runtime-record fields without broad memory scanning.

```text
0x01bca3f8(GPIO object, pin/index, selector)
  -> object + 0x250
  -> 0x01802f74 raw selector method
```

The missing piece remains reachability, not the hardware selector semantics.

## Runtime direct PWM11 tests after ASUS-stock differential

After comparing the ASUS stock BIOS good state with the MSI Lightning 800 W bad
state, the obvious low-cost test was to program the known PWM11 registers
directly:

- ASUS-style test:
  - `PWM11_CFG=0x1a000438`
  - `PWM11_DUTY=0x00000292`
- Lightning-PWM10-style test:
  - `PWM11_CFG=0x000003e8`
  - `PWM11_DUTY=0x00000292`

Both writes succeeded through root `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS`, both
values stuck after readback, and neither made physical fans 2/4 spin.  Fans 1/3
continued to spin.  This rules out the simple PWM-duty/config-latch workaround.

Updated interpretation:

- PWM11 config/duty registers are host-writable.
- GSP does not immediately overwrite those PWM11 values.
- The missing layer is before the PWM duty latch: GPIO3/PWM11 mux/selector or
  GSP runtime record selection.
- `nvidia-settings -q fans` still reports one fan target after the write, so
  this also does not synthesize the RM/NV-CONTROL fan1 object.

Static confirmation of the raw selector path:

The GB202 raw selector method at `0x01802f74` is not a direct BAR0 constant
write.  Its core behavior is:

```text
old = vtable_read(pin_slot)
new = (old & ~0xff) | selector
vtable_write(pin_slot, new)
```

where `pin_slot` is derived from the supplied runtime pin/index and the
underlying object is obtained from GSP object state.  `0x01802f74` is installed
as a GPIO class vtable method at slot `+0x250`; direct address references were
found at `0x01941ca6`, `0x0194247a`, and `0x01942b2e`, consistent with vtable
initialization.  Therefore a host `REG_OPS` write to PWM11 does not exercise
this selector path.

Static confirmation of the runtime-record setter:

The helper at `0x017fe5b4` writes two bytes in the GSP GPIO runtime-record
table, around the `record + 1835/1836` fields selected by the current pin/index
mapping.  The known eight direct callers remain:

```text
0x0118152c
0x011f11ee
0x011f12e4
0x0121cb92
0x0122a69e
0x0122a6fa
0x0129484e
0x01294878
```

No new host-accessible command path was established from the PWM11 experiment.
The next useful work is still to trace those callers upward toward an RM
control/RPC dispatch, or to find a safe supported way to mutate the GSP runtime
record before invoking `ActivateHwFunction`.

## Minimal future experiments

These require a driver/GSP initialization cycle; they are not live-safe while
the desktop is running on the card.

1. Boot or reload with only:
   `NVreg_RegistryDwords="RmFan2XOverride=2"`
   and check fan cooler count / physical fans 2+4.
2. Repeat with `RmFan2XOverride=1` only if value 2 does not help.  Current
   static evidence says value 1 mostly selects an existing-GPIO policy path.
3. Only after those two tests, consider `RMEnableNonSiliconGpio=1` as a
   separate one-key reload experiment.  Its polarity is inverted enough that a
   positive result would need fresh attribution.
4. Treat `RMDisableThermOnlyGpio=1` as low priority; current static evidence
   says it disables function `0x12`, not that it creates a fan route.
5. Avoid combining all keys on the first pass, otherwise a behavior change
   cannot be attributed.

Expected result if the key helps:

- `nvidia-settings`/NV-CONTROL shows a second logical fan/cooler, or
- the existing fan policy starts driving physical fans 2 and 4, or
- GSP log / RM status changes around GPIO/FAN import.

Expected result if it does not help:

- still only one cooler;
- GPIO3 runtime remains unavailable;
- fans 2/4 remain idle under Lightning BIOS.

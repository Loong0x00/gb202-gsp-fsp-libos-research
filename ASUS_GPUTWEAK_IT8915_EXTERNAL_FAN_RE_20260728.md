# ASUS GPU Tweak III / MSI Afterburner fan-control static audit

Date: 2026-07-28

Scope: offline/static analysis only. No live I2C, MMIO, RM, GSP, fan, or GPU
state was changed.

## Inputs

- ASUS GPU Tweak III 2.1.6.0 extracted under
  `/home/user/.cache/rt5090-static/asus_gputweak_2160/`.
- `VGA_Extra.dll` SHA-256:
  `ed96b5424e828f27ad0b9425bd2a74799bbcb29de0cb797ac9ef0de4f7f5d100`.
- `ASUSGPUFanServiceEx.exe` SHA-256:
  `74b58275f984078d1bba0780eeca082868a6f01f58fdab285b3b8ccd8b925283`.
- MSI Afterburner 4.6.7 Beta 2 extracted under
  `/home/user/research/msi_afterburner_re/v467b2/`.
- `RTHAL.dll` SHA-256:
  `9251cdbc614f7dc42b9052b706bab96d0d2a083b98dba32f88965fb6b69f9cbe`.

## Confirmed: ASUS detects the local IT8915 at 8-bit address 0x56

`VGA_Extra.dll` function `0x10003330` probes I2C addresses and stores the
recognized controller address in a per-card device table.

The `0x56` branch is at `0x100035ec..0x10003647`:

- read register `0x20` from 8-bit address `0x56` and require `0x15`;
- read register `0x21` and require `0x89`;
- on success, store controller address `0x56` and mark the device usable.

Linux represents this 8-bit NVIDIA/NVAPI address as 7-bit address `0x2b`.
This matches the device already observed on GPU I2C bus 1 under both the ASUS
and Lightning VBIOS.

## Confirmed: ExternalFan command and telemetry registers

`ASUSGPUFanServiceEx.exe` dynamically loads `VGA_Extra.dll` and calls
`Set_LED_ExternalFan_Info`. Its live service path copies a 128-byte command
structure and sets the block at structure offset `0x50`:

- `+0x50 = 1`: external-fan block is present;
- `+0x54 = 1`: duty-control operation;
- `+0x58 = requested duty percent`.

`VGA_Extra.dll` routes this block through function `0x10005240` and its generic
I2C writer `0x10005c50`. The latter is the dynamically resolved `WriteI2C`
export from `Vender.dll`.

For the recognized `0x56` controller, operation 1 performs:

1. read register `0x40`;
2. if it is not `2`, write `0x40 = 2` and wait 500 ms;
3. write register `0x41 = ceil(percent * 2.55)`.

The inverse getter is function `0x10004b70`:

- `0x41`: duty byte, converted back by division by 2.55;
- `0x44`: external fan tachometer 1, converted as raw times 30 RPM;
- `0x48`: external fan tachometer 2, converted as raw times 30 RPM;
- operation 2 reads `0x40` as the control mode.

The special address `0x52` uses registers `0x10..0x13`; all other recognized
controllers, including `0x54` and `0x56`, use the `0x40/0x41/0x44/0x48`
family. Address `0x54` has extra zero-duty transition handling, while `0x56`
uses the ordinary path above.

## Interpretation boundary

This is the ASUS **ExternalFan/FanConnect** path for the two external 4-pin
headers. It proves a direct software-to-I2C control route for those headers.
It does not prove that the IT8915 generates the missing onboard PWM11 signal,
nor does it replace the missing Lightning-VBIOS GPIO3 -> PWM11 GSP topology.

The prior local A-B-A experiment at IT8915 registers `0xa2:0xa3` only tracked
a consequence of onboard fan 1/3 activity and did not establish an onboard fan
control register. That result is compatible with the IT8915 monitoring board
power/current while separately controlling its external headers.

## MSI Afterburner findings

MSI Afterburner contains a general NVIDIA I2C transport layer in `RTHAL.dll`,
including `I2CRead`, `I2CWrite`, `I2CReadEx`, `I2CWriteEx`, bus enumeration,
device caching, and NVAPI wrappers.

The local `MSIAfterburner.oem2` contains a current entry:

`[VEN_10DE&DEV_2B85&SUBSYS_53031462&REV_??]`

described as `MSI RTX5090 Gaming Trio I2C mod`. It only configures MP29816A
and MP2988 voltage/temperature-controller detection. It contains no fan or
IT8915 mapping.

The bundled `SDK/Doc/Hardware database format reference.pdf` documents a
generic command-line I2C console that does not require a built-in controller
class:

- `/ri<bus>,<7-bit-device>,<register>` reads one byte;
- `/wi<bus>,<7-bit-device>,<register>,<data>` writes one byte;
- `/ai`, `/oi`, and `/xi` perform read/modify/write AND, OR, and XOR;
- `/sg<gpu_index>` selects the target GPU;
- `/fm1` and `/fm2` select one- or two-byte register addressing;
- `/i2cd` is a 256-register dump/scanner.

Consequently, on Windows Afterburner can be used as a generic transport to
issue a targeted read or write to IT8915 address `0x2b`, even though it does
not understand IT8915 fan semantics. The Afterburner I2C-bus index must be
identified independently; it must not be assumed to equal Linux adapter 1.
The broad `/i2cd` scanner is unnecessary for this target and should not be
used as a substitute for targeted accesses.

No `IT8915`, `IT89xx`, `ExternalFan`, or `FanConnect` controller class or
protocol was found in `RTHAL.dll`, `RTCore.dll`, the main executable, or the
three bundled OEM databases. The exposed fan paths are standard NVAPI client
fan coolers/firmware curves plus older explicitly implemented I2C sensor/fan
controller classes.

The bundled Afterburner readme also states that only NVIDIA reference-design
asynchronous fan control is supported and third-party proprietary asynchronous
fan solutions are not supported. Therefore Afterburner supplies a reusable
I2C transport primitive, but no ready-made ASUS Astral onboard-fan or IT8915
external-fan backend.

## Practical consequence

There are now two distinct routes and they must not be conflated:

1. **ASUS external 4-pin headers:** direct IT8915 I2C route at bus-1 address
   `0x2b`, registers `0x40/0x41/0x44/0x48`; fully statically closed.
2. **Onboard physical fans 2/4 under Lightning VBIOS:** still require the
   missing GPIO3/PWM11 physical route or a hardware reroute; neither GPU Tweak
   III nor MSI Afterburner provides a second normal software backend for it.

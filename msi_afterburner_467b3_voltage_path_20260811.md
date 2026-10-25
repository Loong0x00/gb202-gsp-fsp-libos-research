# MSI Afterburner 4.6.7 Beta 3 build 17352 voltage-path audit

Date: 2026-08-11

## Artifact

- Authorized Guru3D mirror archive: `[Guru3D]-MSIAfterburnerSetup467Beta3Build17352.rar`
- Archive SHA-256: `0ed9efdebff78314d3362b8b68b8011e4a500098762baf277a95e4e99332693f`
- Installer SHA-256: `3c954664ae5c45937a4e0059c4edce3fc3dd535df28f28defd0caaaf9b9e4cd0`
- `MSIAfterburner.exe` and the installer contain Authenticode certificates for `MICRO-STAR INTERNATIONAL CO., LTD.`
- The package was extracted statically and no Windows executable or driver was run.

## Conclusion

The RTX 5090 Lightning voltage implementation is hybrid, but it is not merely a wrapper around an NVIDIA "set Lightning voltage" API.

1. MSI Afterburner owns the board-specific voltage-controller logic. `RTHAL.dll` implements dedicated `CHALVRMImplementationMP29816A` and `CHALVRMImplementationMP2988` classes, including VID conversion, voltage readback, default capture/restore, and actual register programming.
2. On an NVIDIA GPU, the normal transport for those I2C transactions is NVIDIA's private NVAPI I2C interface. Afterburner constructs the MP29816A/MP2988 register transactions itself, then passes them through `NvAPI_GPU_I2CWriteEx`/`ReadEx`-style calls.
3. `RTCore64.sys` is also bundled and Afterburner uses its own low-level infrastructure for privileged PCI/MMIO/MSR and optional low-level paths, but the observed normal NVIDIA VRM-I2C call chain terminates in NVAPI, not in an RTCore64 IOCTL.
4. Generic NVIDIA core-voltage/VF control remains a separate driver-level NVAPI path. Lightning's direct PWM core voltage, memory voltage, and AUX/MSVDD controls are board-specific external-controller paths layered above the NVAPI I2C transport.

In short: **Afterburner supplies the controller knowledge and writes; NVAPI supplies the bus conduit.**

## Direct binary evidence

All addresses below are RVAs in `RTHAL.dll` (image base `0x10000000`).

### MP29816A

- `CHALVRMImplementationMP29816A::SetVoltage`: RVA `0x702d0`
- Reads controller register `0x3a` and writes registers `0x24` and `0x21` through the HAL I2C vtable.
- Supports rail selection, matching a multi-output controller used for separate NVVDD and memory rails.

### MP2988

- `CHALVRMImplementationMP2988::SetVoltage`: RVA `0x70a70`
- Programs controller registers `0x5c`, `0x43`, and `0x41` through the HAL I2C vtable.
- The package exposes this controller as an MSVDD/AUX-capable implementation.

### NVIDIA transport

- `CHALImplementationNVAPI::I2CWrite`: RVA `0x633e0`
- Calls `CNVAPIWrapper::I2CWrite`: RVA `0x84670`
- Builds an `NV_I2C_INFO_V3` request and calls `CNVAPIInterface::I2CWriteEx`: RVA `0x80780`
- The dynamic `nvapi_QueryInterface` lookup uses interface ID `0x283ac65a` for the extended write entry.
- `RTHAL.dll` dynamically loads `nvapi.dll`.

This proves the voltage-controller register sequence is implemented in Afterburner's HAL while the ordinary NVIDIA I2C transaction is carried by NVAPI.

## Package documentation evidence

The bundled `Doc/ReadMe.pdf` states:

- version 4.6.7 adds RTX 5090 Lightning support;
- MP2988 and MP29816A support is intended for extreme-overclocking boards with triple/quad-channel voltage control;
- the three relevant controls are core, memory, and auxiliary/MSVDD voltage;
- reference RTX 5080/5090 controller address ranges are blacklisted by the NVIDIA display driver, preventing the same extended voltage control there;
- AUX/AUX2 sliders are mapped to named physical rails such as MSVDD.

The bundled hardware-database reference explicitly distinguishes:

- `Generic`: NVIDIA display-driver VID control;
- named external controllers: direct I2C controller access;
- named external-controller detection has priority, with Generic retained as fallback.

## Unencrypted RTX 5090 example

The included `MSIAfterburner.oem2` contains a 5090 Gaming Trio I2C-mod entry:

```ini
VDDC_Generic_Detection          = 1
VDDC_MP29816A_Detection         = 26h
VDDC_MP29816A_Type              = 1
VDDC_MP29816A_Rail              = 0
MSVDD_MP2988_Detection          = 22h
MVDDC_MP29816A_Detection        = 26h
MVDDC_MP29816A_Type             = 1
MVDDC_MP29816A_Rail             = 1
```

That is a concrete example of the hybrid design: driver-level Generic VDDC exists as fallback, while direct MP29816A/MP2988 controller objects provide the extended rails. The exact Lightning board entry resides in the encrypted internal OEM database, so the precise Lightning bus/device mapping was not recovered from plaintext in this pass.

## Practical implication for XBAR

The Lightning AUX slider changes the physical MSVDD regulator target through an MP2988 transaction. It does not edit the hidden GSP XBAR V/F curve or inform GSP that the rail's physical voltage has been offset. Therefore a hardware/AUX MSVDD increase can leave the firmware's clock request nearly unchanged and produce only one or two XBAR bins. The software clock-domain control discovered on Linux is a different lever and explains why it can produce much larger XBAR changes without a physical voltage mod.

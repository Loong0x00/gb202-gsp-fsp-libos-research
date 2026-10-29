# ASUS stock BIOS final fan snapshot — 2026-07-27 06:08

Purpose:

- Final known-good ASUS Astral BIOS state before switching back to MSI Lightning BIOS.
- Fans were intentionally spinning under LACT static control so PWM values were meaningful.

Live state:

```text
Driver:        NVIDIA 610.43.03
VBIOS:         98.02.2E.40.E0
GPU ID:        10DE:2B85-1043:89E3-0000:01:00.0
Registry:      RMUseSwI2c=0x01
Fan targets:   2 Fans on wayland-0
Fan control:   GPUFanControlState=1
Fan0:          current 45%, target 45%
Fan1:          current 45%, target 45%
LACT mode:     Static
```

Final fixed BAR0 fan/PWM values from the last read-only probe in `fan_mmio_read_probe.dmesg.txt`:

```text
0x00118ab0 GB202_PWM10_PERIOD_OR_CONFIG   = 0x01000438
0x00118ab4 GB202_PWM10_DUTY               = 0x000001a1
0x00118ab8 GB202_PWM11_PERIOD_OR_CONFIG   = 0x1a000438
0x00118abc GB202_PWM11_DUTY               = 0x000001a8
0x00ad0a1c GPIO3_CAP_WORD0                = 0x40000000
0x00ad0a5c GPIO3_CAP_WORD1                = 0x0672000d
0x00ad0a2c GPIO7_CAP_WORD0                = 0x00000000
0x00ad0a6c GPIO7_CAP_WORD1                = 0x06720000
```

Important prior asymmetric mapping in `/home/user/rt_5090_project/asstral_stock_baseline_20260727_055919/fan_mmio_read_probe_asym_35_70.dmesg.txt`:

```text
fan0=35%, fan1=70%
PWM10_DUTY = 0x00000155
PWM11_DUTY = 0x00000292
```

Conclusion:

- `fan0 -> PWM10`
- `fan1 -> PWM11`
- The Lightning BIOS missing fan group 2/4 is the `fan1/PWM11` path.

Files:

- `status.txt`: driver, VBIOS, LACT, NV-CONTROL, fan target state.
- `i2c_bus*.txt`: read-mode I2C scans.
- `fan_component6.pb` and `.wire.txt`: NVD FAN dump; still only 120 bytes.
- `fan_mmio_read_probe.dmesg.txt`: fixed BAR0 fan/PWM/GPIO read-only snapshot.
- `lact_config.yaml`: LACT config used for static fan control.
- `SHA256SUMS.txt`: hashes for captured files.

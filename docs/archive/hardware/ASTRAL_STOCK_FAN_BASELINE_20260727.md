# ASUS Astral stock BIOS fan baseline — 2026-07-27

Environment:

- Card: ASUS RTX 5090 Astral OC, device ID `10DE:2B85-1043:89E3-0000:01:00.0`
- Driver: NVIDIA `610.43.03`
- VBIOS observed by driver: `98.02.2E.40.E0`
- Driver registry dwords: `RMUseSwI2c=0x01`
- Baseline directory: `/home/user/rt_5090_project/asstral_stock_baseline_20260727_055919`

Confirmed good-state facts:

- NV-CONTROL exposes two fan targets:
  - `[fan:0] FAN-0`
  - `[fan:1] FAN-1`
- This directly contrasts with MSI Lightning 800 W BIOS on the same card, where NV-CONTROL exposed only one fan target.
- `NV2080_CTRL_CMD_NVD_GET_DUMP`, component 6, still returned only 120 bytes.
  It remains a tiny generic/wrapped FAN dump and did not become a useful FanCooler object dump under the good BIOS.

LACT static fan setup:

- Added a temporary `/etc/lact/config.yaml` entry for the ASUS GPU ID with:
  - `fan_control_enabled: true`
  - `mode: static`
  - `static_speed: 0.45`
- Config backup before this change:
  `/etc/lact/config.yaml.bak.before_asus_static_fan_20260727_060319`
- `lact cli stats` then reported:
  - `Fan Speed: 45%`
  - `Fan Control Mode: Static`

Good-state PWM/GPIO readback with both fans near 45%:

```text
0x00118ab0 GB202_PWM10_PERIOD_OR_CONFIG   = 0x01000438
0x00118ab4 GB202_PWM10_DUTY               = 0x000001a1
0x00118ab8 GB202_PWM11_PERIOD_OR_CONFIG   = 0x1a000438
0x00118abc GB202_PWM11_DUTY               = 0x000001aa
0x00ad0a1c GPIO3_CAP_WORD0                = 0x40000000
0x00ad0a5c GPIO3_CAP_WORD1                = 0x0672000d
0x00ad0a2c GPIO7_CAP_WORD0                = 0x00000000
0x00ad0a6c GPIO7_CAP_WORD1                = 0x06720000
```

Asymmetric fan test:

- Command target:
  - fan0 target = 35%
  - fan1 target = 70%
- NV-CONTROL readback:
  - fan0 current = 34%, target = 35%
  - fan1 current = 70%, target = 70%
- BAR0/PWM readback during that state:

```text
0x00118ab0 GB202_PWM10_PERIOD_OR_CONFIG   = 0x01000438
0x00118ab4 GB202_PWM10_DUTY               = 0x00000155
0x00118ab8 GB202_PWM11_PERIOD_OR_CONFIG   = 0x1a000438
0x00118abc GB202_PWM11_DUTY               = 0x00000292
```

Conclusion:

- `fan0` maps to `PWM10`.
- `fan1` maps to `PWM11`.
- The missing physical fan group 2/4 under the Lightning BIOS is the `fan1` / `PWM11` path.
- Under the good ASUS BIOS, PWM11 is not dormant: it has a valid period/config word and live nonzero duty.
- The next useful differential is to compare the good-state PWM11/GPIO3 runtime initialization against Lightning's bad-state records:
  - good ASUS: `PWM11_CONFIG=0x1a000438`, `PWM11_DUTY` tracks fan1 target.
  - recorded Lightning bad state: `PWM11_CONFIG=0x1a0000d8`, `PWM11_DUTY=0x00000000`.

Operational note:

- Fans were restored to 45% target after the asymmetric test.
- LACT currently holds static fan mode at about 45% unless the config is restored or changed.

# Lightning VBIOS on ASUS Astral: power telemetry mismatch

Date: 2026-07-26

## Configuration

- GPU PCB: ASUS RTX 5090 Astral Black, one 12V-2x6 input.
- Active VBIOS: MSI Lightning 800 W, intended for a dual-16-pin board.
- Independent connector measurement: ASUS onboard IT8915FN-56 at I2C bus 1,
  address `0x2b`, read by `tools/astral_power_detector.py`.
- Firmware measurement: NVML / `nvidia-smi` and the PMGR A613
  `INPUT_TOTAL_BOARD` channel.

## Direct observations

Idle, with the 6K GNOME desktop active:

- 12V-2x6 detector: about 47.5--47.7 W.
- `nvidia-smi`: about 121--123 W.
- Difference: about 74 W.

Six-second Vulkan FurMark run at 1280x720:

- Independent connector samples at or above 330 W:
  14 samples, 349.16 W mean, 338.01 W minimum, 357.10 W maximum.
- NVML samples at GPU utilization at or above 90%:
  117 samples, 470.26 W mean, 456.89 W minimum, 480.07 W maximum.
- Direct thermal guard: GPU edge 57 C maximum, hotspot 68.1 C maximum,
  connector pin current 5.34 A maximum, connector voltage 12.040 V minimum.
- No NVIDIA Xid or PCIe/AER error was logged.

Raw data:

`benchmark_logs/furmark_vk_direct_1280x720_20260726_032841/`

## What this proves

The independent detector covers the 12V-2x6 input but not PCIe-slot input.
Even granting the PCIe slot its full 75 W specification limit, the observed
connector maximum permits at most about 432 W total board input, below the
480.07 W NVML peak. At the steady connector mean, the corresponding upper
bound is about 424 W, below the 470.26 W NVML mean.

Therefore NVML board power is not an accurate physical input-power reading in
this cross-flashed configuration. The error is not merely a fixed 75 W offset:
the NVML-minus-connector difference grows from about 74 W at idle to about
121 W under this load. A load-dependent scale or a wrong dual-input sensor
topology is also involved.

## NCT6799 limitation

The motherboard NCT6799 driver exposes 18 single-ended voltage channels plus
temperatures and fan tachometers/PWM. Prior local reverse engineering maps
`in0` to VDDCR_CPU and `in5` to VDDCR_SOC. It exposes no current or power ADC,
so it cannot directly close the PCIe-slot wattage term. Read-only SMBus scans
also did not reveal an obvious motherboard INA/PMBus current monitor; the
devices on DesignWare I2C bus 0 identified by ACPI are USB-C/PD devices.

## Remaining uncertainty

Exact total board input still requires either a slot-riser current meter or a
verified onboard measurement of the slot 12 V and 3.3 V rails. The rigorous
current result is an upper bound, not a claim that slot power is exactly 75 W.

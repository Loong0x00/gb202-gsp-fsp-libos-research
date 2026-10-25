# RTX 5090 Lightning VBIOS: LACT high-frequency-tail A/B

Date: 2026-08-03

## Fixed conditions

- RTX 5090 on MSI Lightning VBIOS `98.02.2E.C0.0F`
- NVIDIA driver/GSP stack `610.43.03`
- LACT power ceiling: 800 W
- VRAM offset: +2000 MHz; observed MCLK 15001 MHz
- No GPU or VRAM min/max clock constraints
- Cyberpunk 2077 2.31, 6144x3456, path tracing, fixed benchmark scene
- Each Cyberpunk run rendered 973 frames

The custom curves retained the VBIOS base curve below 1.0 V, progressively
raised the 1.0--1.05 V tail, and flattened all points to the right of 1.05 V.

## Cyberpunk 2077 results

| Requested 1.05 V tail | FPS avg | FPS min | FPS max | Actual GPC avg | Actual GPC max | Avg voltage | Reported avg power | XBAR avg | SYS avg | Six-pin peak | Max single pin |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| VBIOS base | 12.4593 | 10.7867 | 14.5097 | 2992.5 MHz | 3007 MHz | 1036.5 mV | 690.8 W | 2540.5 MHz | 2376.6 MHz | 631.72 W | 9.46 A |
| 3150 MHz | 12.5724 | 10.8759 | 14.7087 | 3019.3 MHz | 3037 MHz | 1035.6 mV | 695.4 W | 2540.6 MHz | 2374.5 MHz | 637.08 W | 9.58 A |
| 3200 MHz | 12.5197 | 10.8149 | 14.5952 | 3048.0 MHz | 3075 MHz | 1035.8 mV | 696.2 W | 2545.1 MHz | 2376.1 MHz | 640.12 W | 9.64 A |
| 3250 MHz | 12.5882 | 10.8880 | 14.5392 | 3071.4 MHz | 3097 MHz | 1036.9 mV | 700.1 W | 2543.6 MHz | 2372.1 MHz | 641.10 W | 9.68 A |
| 3300 MHz | 12.6797 | 10.9166 | 14.7334 | 3096.0 MHz | 3127 MHz | 1036.3 mV | 703.8 W | 2541.4 MHz | 2375.0 MHz | 644.38 W | 9.68 A |

Relative to the VBIOS-base run, the 3300-MHz tail improved average FPS by
1.77% and average reported GPC frequency by 3.46%. XBAR and SYS stayed stable,
so this series did not reproduce the MCLK-constraint/XBAR regression.

The requested tail frequency was not the realized frequency. Even the 3300-MHz
tail produced only 3096 MHz average and 3127 MHz maximum in this PT workload.
The PMU reported DG0 averaging about 3252 MHz, while the realized GPC remained
about 156 MHz lower.

The 3200 result being slightly lower than the 3150 result is small single-run
variance, not evidence that 3200 is intrinsically slower. The monotonic GPC and
power progression confirms that the curve edits were active.

## True-800-W FurMark check

The 3300-MHz flattened curve was also tested for 30 seconds with Vulkan FurMark
at 7680x4320.

- NVML instantaneous power: 800.2 W average / 823.4 W maximum
- NVML one-second average power: 789.3 W average
- Six-pin connector peak: 709.2 W
- Maximum single-pin current: 10.64 A
- GPU temperature: 54.6 C average / 55 C maximum
- Hotspot: 64.7 C average / 67.2 C maximum
- Actual GPC: 2677.1 MHz average / 2992 MHz maximum

Therefore an actual 800-W board load does not imply 3200--3300 MHz. Frequency
depends strongly on workload switching activity. A Port Royal or game workload
can run much higher frequency at similar power, while FurMark spends the same
power at much lower frequency.

FurMark exited with status 139 after its 30-second maximum time. The thermal and
connector guard did not trigger, and the kernel logged no Xid, GPU-lost, or
reset-required event.

## Candidate configs

- `lact-config-lightning-3150mhz-1050mv.yaml`
- `lact-config-lightning-3200mhz-1050mv.yaml`
- `lact-config-lightning-3250mhz-1050mv.yaml`
- `lact-config-lightning-3300mhz-1050mv.yaml`

These are experimental profiles, not yet long-duration stability-certified.
The 3300 profile may reach a much higher realized clock in light workloads than
it did in 6K PT, so it should not be treated as a daily profile based on this
single PT pass.

## Restoration

After the experiment, `/etc/lact/config.yaml` was restored byte-for-byte from
`/etc/lact/config.yaml.bak-before-3150-3200-ab-20260803_151507`, `lactd` was
restarted, clock constraints were reset, the power ceiling was returned to
800 W, and runtime MCLK returned to 14001 MHz. No Xid was observed during the
test window.

# NVML thermal enumeration, RTX 5090 / driver 610.43.03

Read-only reproduction:

```sh
cd /home/user/rt_5090_project/hotspot_reader
./nvml_enum_probe.py
```

Observed on 2026-07-14:

```text
legacy temperature successes: [(0, 58)]
legacy return-code histogram: {0: 1, 2: 255}
TemperatureV successes: [(0, 58)]
TemperatureV return-code histogram: {0: 1, 2: 255}
threshold successes: [(0, 96), (1, 93), (3, 90)]
threshold return-code histogram: {0: 3, 2: 248, 3: 5}
margin: rc=0 value=33 C
thermal settings index=0:  rc=0 count=1 current=58 target=GPU controller=GPU_INTERNAL
thermal settings index=1:  rc=0 count=1 current=0  target=NONE controller=NONE
thermal settings index=2:  rc=0 count=1 current=0  target=NONE controller=NONE
thermal settings index=15: rc=0 count=1 current=58 target=GPU controller=GPU_INTERNAL
```

`NVML_SUCCESS=0`, `NVML_ERROR_INVALID_ARGUMENT=2`, and
`NVML_ERROR_NOT_SUPPORTED=3`.  The scan covered numeric enums 0 through 255
for both `nvmlDeviceGetTemperature` and the new
`nvmlDeviceGetTemperatureV`; only enum 0 succeeded and it matched edge.

Threshold enum 0 is shutdown (96 C), 1 is slowdown (93 C), and 3 is the
public GPU maximum (90 C).  It is a limit, not a live sensor.  Repeated paired
samples observed approximately `edge + margin = 89..91 C`; therefore the
margin is distance to the public GPU slowdown/max policy, not
`107 C - hotspot`.

Status: **VERIFIED negative** -- this driver exposes no hidden live hotspot
through the complete one-byte NVML temperature-enum space, the versioned API,
or the three-slot thermal-settings structure.


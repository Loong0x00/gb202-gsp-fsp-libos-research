# GB202 voltage request, arbitration, and regulator path (2026-07-29)

## Result

The board regulator is not the component that chooses a performance voltage.
The firmware first derives one or more voltage requests from the active V/F and
VFE state, arbitrates the requests, and only then asks the voltage device to
quantize and program the resulting rail target.

The currently installed 610.43.03 user library exposes two physical voltage
rails and four PWM voltage-device descriptors.  All four descriptors report:

- supported voltage range: 445000 through 1280000 uV;
- voltage step: 5000 uV;
- PWM voltage base: 400000 uV;
- PWM voltage scale: 900000 uV;
- raw period: 180.

The descriptor spacing closes exactly:

```text
900000 uV / 180 = 5000 uV per raw PWM code
minimum code = (445000 - 400000) / 5000 = 9
maximum code = (1280000 - 400000) / 5000 = 176
affine index voltage_uV = 400000 + index * 5000
```

This proves the 5 mV grid and its valid affine index range.  It does **not** by
itself prove that the raw hardware duty field equals that affine index.  The
physical PWM polarity is deliberately not inferred from the descriptor alone.

At two observed idle target pairs:

```text
NVVDD target 815000/820000 uV -> affine index 83/84
shared/memory target 875000/880000 uV -> affine index 95/96
```

Every voltage-device descriptor has `i2cDevIdx = 0xff`.  The normal setpoint
path represented by this table is therefore GPU PWM, not a per-transition I2C
write to the board VRM controller.

## Firmware selection path

The R570 GB202 PMU power evaluator and same-generation RM/MODS implementation
show two distinct uses of voltage which must not be conflated.

### Candidate voltage used by the power model

`WORKLOAD_COMBINED_2X` does a discrete candidate-frequency search.  For each
candidate it obtains a frequency/voltage tuple from the V/F point objects for
each physical branch, then uses those voltages in the NVVDD/MSVDD power model.
The relevant R570 PMU functions are:

```text
0x202c3450  query candidate rail state
0x202c52d2  evaluate a clock-domain equation
0x202c5b28  V/F point wrapper
0x202c5c76  V/F point implementation
0x202c5bd8  select V/F point table
0x202c5c0e  select base/entry data
0x202c5d4c  optional V/F adjustment
```

This candidate voltage is an input to predicted power.  It is not proof that
the physical rail was programmed to that voltage.

### Voltage actually requested for a rail

The same-generation RM voltage-request implementation contains ten client
slots per rail.  Its layout and operations are visible in these functions:

```text
0x6a6e040  evaluate one voltage request
0x6a6e260  arbitrate active voltage requests
0x6a6ef90  re-arbitrate and apply the winning target
0x6a6f320  update/deactivate one request slot
0x6a69a80  evaluate the chained V/F/VFE voltage expression
0x6a68920  sequence and program a core-voltage change
0x72f4f90  select a rail's default voltage device and invoke its quantizer
```

The request structure is 16 bytes:

```text
+0x00  client ID, 0..9
+0x04  signed request-local offset
+0x08  request type
+0x09  selector/domain for an F/V-derived request
+0x0c  literal voltage for a literal request
```

Two request types are implemented:

1. a literal voltage request;
2. an F/V-derived request.

For an F/V-derived request, the implementation evaluates a linked chain of VFE
nodes.  Each node produces a signed contribution, each contribution is clamped
to that node's own minimum and maximum, and the contributions are summed.  The
rail-global offset, request-local offset, and per-client offset are then added.
The result is finally quantized by the rail's default voltage device.

### Exact quantization and PWM handoff

The same-generation PWM-device quantizer at `0x6a797a0` closes the rounding
rule.  For the positive 5000 uV step used by these descriptors it computes:

```text
rounded = base + ceil((requested - base) / step) * step
rounded = clamp(rounded, device_min, device_max)
```

It therefore rounds **up**, not to nearest.  For example, a 923000 uV request
becomes 925000 uV; an already aligned 925000 uV request remains unchanged.

The PWM-specific programmer at `0x6a7b610` then searches the device's supported
voltage table for the first entry whose voltage is not below the rounded target.
Each table entry contains at least the supported voltage at `+0x00` and its PWM
duty value at `+0x04`.  The function reads the current PWM period/duty through
`0x6a11fa0`; if either differs, it submits the selected table duty through
`0x6a120c0` and waits the configured settling time.

Thus the closed board-programming path is:

```text
requested uV
  -> ceil to the next 5 mV supported point
  -> clamp to 445..1280 mV
  -> look up that voltage's PWM duty in the device table
  -> program PWM period/duty
  -> wait for voltage settling
```

The remaining unmapped detail is only the electrical polarity of that duty
value at the external regulator input.  It does not affect the voltage-selection
or 5 mV rounding result.

The active-request mask is at rail object offset `+0xab8`; request records begin
at `+0xaf0` with stride `0x10`.  `0x6a6e260` evaluates every active slot selected
by the input mask and takes the unsigned maximum.  Therefore a user-visible V/F
point is only one input: any other active client or offset can raise the final
rail target.

The effective flow is:

```text
active clock/performance state
  -> base V/F result
  -> bounded VFE contributions
  -> global + local + per-client voltage offsets
  -> per-client voltage request
  -> maximum across active clients
  -> default voltage-device quantization
  -> voltage-change ordering / clock coordination
  -> PWM voltage device
  -> board regulator
```

## Exact 610.43.03 read-only observations

The local library was pinned by SHA-256:

```text
14a4861b513d9575a679bc470209e532bfceba688631c6be6eda40ff559b7817
```

Read-only RM control `0x2080b202` reports the current rail targets.  Separate
idle samples during this audit observed the following adjacent 5 mV states:

```text
rail 0 / NVVDD:              815000 or 820000 uV
rail 1 / shared-memory rail: 875000 or 880000 uV
```

Read-only RM control `0x2080b205` reports four active voltage devices:

| Device | Voltage domain | I2C device | Operation type | PWM source |
|---:|---:|---:|---:|---:|
| 0 | 1 | 0xff | 1 | 4 |
| 1 | 1 | 0xff | 4 | 18 |
| 2 | 3 | 0xff | 1 | 5 |
| 3 | 3 | 0xff | 4 | 19 |

The exact semantic names of operation types 1 and 4 have not yet been closed.
They should not be relabeled from guesswork.  The PWM device type and numeric
range/step/base/scale/source/period fields are directly decoded by the audited
610.43.03 wrapper.

## Connection to the Cyberpunk result

The existing path-tracing experiment showed that the same approximately
2897 MHz reported graphics-clock region can be reached in two materially
different voltage states:

```text
baseline:     2897.57 MHz, 973.07 mV, 555.28 W
low-voltage:  2897.13 MHz, 920.65 mV, 514.73 W
```

The low-voltage state was obtained by changing the V/F plateau and the maximum
graphics-clock request.  This proves that the workload does not intrinsically
require 973 mV merely to deliver that throughput.  A plausible interpretation,
consistent with the static path but not yet directly observed at the ten
request slots, is that changing the clock range changed the winning discrete
V/F-derived request while later power arbitration reduced the realized clock.

This does not yet prove which voltage-request client was the winning client in
each benchmark.  The ordinary 610.43.03 status interface exports the final rail
target but not the ten individual request slots.

### XBAR is not the source of the high visible NVVDD target

The earlier synchronized PT captures settle this tempting alternative.  XBAR
does use the second/shared rail and its voltage is indeed in the remembered
970 mV region, but arbitration is per rail; the higher second-rail request does
not become the rail-0/NVVDD target.

Using the exact scene windows:

| State | Visible GPU voltage | Observed rail 0 | Observed rail 1 | XBAR |
|---|---:|---:|---:|---:|
| Baseline PT | 977.44 mV | 976.50 mV | 967.25 mV | 2356.01 MHz |
| Low-NVVDD PT | 914.61 mV | 915.67 mV | 988.77 mV | 2399.14 MHz |

The second row is the decisive counterexample: XBAR/rail 1 required nearly
989 mV while visible GPU voltage and rail 0 remained near 915 mV.  Therefore
the approximately 973--978 mV baseline GPU voltage cannot be explained as
"XBAR asked for 970 mV and the firmware took that maximum across both rails."

XBAR/rail 1 still matters strongly to the two-branch power estimator and can
indirectly change the selected GPC frequency budget.  It is simply not the
direct source of the rail-0 voltage target.  The unidentified winner discussed
below is specifically the winning request inside rail 0's own client set.

### The normal GPC V/F requester is voltage client 1

The remaining normal request path can now be identified more narrowly in the
fixed MODS/R570 image.

The frequency-to-voltage lookup helper at `0x069865b0` copies a 16-byte voltage
request selected from the clock-domain V/F data and then calls `0x06a6ee90`.
That latter helper rewrites the request's first byte, the voltage-client ID,
according to the clock domain:

```text
clock domain 0x0d -> voltage client 1
clock domain 0x07 -> voltage client 3
other domains     -> unsupported in this helper
```

The normal GPC performance-point path at `0x06970adb` calls the lookup helper
with clock domain `0x0d`, then immediately evaluates the returned voltage
request through `0x06a6e040`.  Thus the ordinary GPC V/F-derived request is
statically identified as **voltage client 1**.  The zero client byte seen in a
new P-state object's constructor is only its initial/default placeholder; the
frequency-derived request is retagged to client 1 before evaluation.

Together with the synchronized runtime counterexample above, the best current
answer for the approximately 970--978 mV rail-0 target is therefore the GPC
V/F requester, client 1, not XBAR.  The likely sequence is:

```text
higher requested/allowed GPC performance point
  -> domain 0x0d V/F lookup
  -> client-1 rail-0 voltage request around 970 mV
  -> later power arbitration lowers realized GPCCLK to about 2.9 GHz
```

This explains why the observed voltage can remain higher than the voltage one
would infer from only the final measured clock: voltage selection and the
later power-limited clock decision are distinct stages.  What remains
unobserved on the retail build is the live ten-slot rail-0 dump, so the claim
that client 1 was the literal maximum slot in a particular sample remains a
very strong static-plus-runtime inference rather than a direct slot readout.

## Runtime introspection attempts

Two normal read-only diagnostics were tested once on the running 610.43.03
driver after the static ABI check.

### PMGR module-info control

The installed `libnvidia-api.so.1` contains a wrapper at image offset
`0x90350`.  Its read branch submits command `0x20802620` with exactly 0x38
bytes.  The same command in the R570/MODS table is adjacent to the voltage
request-arbiter controls and its implementation copies out the rail-global
offset, ten per-client offsets, and the special client-9 request state.

A root direct-RM call on the current retail driver returned:

```text
PMGR_GET_MODULE_INFO rm_status=0x00000056 (NV_ERR_NOT_SUPPORTED)
```

No SET branch was called.  This is a useful negative result: the user library
retains the wrapper, but the current retail GSP does not service this read
control on this GPU.

### NVD voltage component

`NVDUMP_COMPONENT_ENG_VOLT` is component 18.  A single root capture succeeded,
but returned only the 120-byte generic GPU/NVD envelope.  It contained no VOLT
payload and no request-client state.  Its SHA-256 is:

```text
d3cb19c03042cea932ae7352ebaf413ed50fd4445cd29d855454072c0a2e967d
```

Therefore neither of the normal read-only diagnostic paths currently exposes
the winning voltage request.  This does not weaken the static arbitration
result; it only closes the observability boundary of the retail build.

## Remaining discriminating question

The next useful target is not the board VRM algorithm; its setpoint conversion
is already closed to 5 mV granularity.  The remaining question is:

```text
During a PT sample, which active rail-0 voltage-request client wins the max
arbitration, and what are its base V/F value and three additive offsets?
```

A useful implementation must expose those ten request slots or instrument the
three known request-update call families.  Merely collecting another single
`GPU Voltage` value cannot distinguish the winner.

## Reproduction tools and evidence

- `tools/nv_voltage_rails_610.py`: version-pinned, read-only rail target query.
- `tools/nv_voltage_devices_610.py`: version-pinned, read-only voltage-device
  descriptor query.
- `tools/nv_pmgr_module_info_probe.c`: direct read-only reproduction of the
  unsupported PMGR module-info control.
- `power_governor_reverse/volt_devices_info_610_20260729.bin`: raw 0x0f48-byte
  device-info response.
- `power_governor_reverse/volt_rails_info_610_20260729.bin`: raw 0x184c-byte
  rail-info response.
- `power_governor_reverse/nvd_volt_20260729/`: component-18 capture, run log,
  and schema-free protobuf decode.
- `power_governor_reverse/voltage_path_layer5_20260729.c` and
  `voltage_path_layer6_20260729.c`: V/F point implementation excerpts.
- `power_governor_reverse/volt_pwm_quantizer_6a797a0_20260729.asm`: exact
  upward-rounding and clamp implementation.
- `power_governor_reverse/volt_pwm_raw_program_20260729.asm`: supported-voltage
  table lookup and PWM period/duty handoff.
- `LOW_VOLTAGE_PT_RESULT_20260729.md`: runtime counterexample separating
  reported graphics clock from the voltage-request state.

No voltage SET control, MMIO write, sysfs write, benchmark, or persistent GPU
configuration change was performed for this note.

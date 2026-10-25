# GB202 rail-by-clock-domain adoption matrix

Date: 2026-08-16  
GPU: NVIDIA GeForce RTX 5090  
Driver: 610.57.04  
VBIOS: 98.02.2E.80.50

## Interface under test

The R610.57.04 `CLK_DOMAINS` control object uses:

```text
GET_CONTROL  0x2080901b, size 0x83c
SET_CONTROL  0x2080d01c, size 0x83c
domain base  0x3c + domain_index * 0x40
rail offset  domain base + 0x10 + rail_index * 4, signed uV
```

Rail 0 is NVVDD and rail 1 is the shared-memory/MSVDD rail on the tested
topology. The experiment wrote only one rail-by-domain slot at a time.

## Method

For each of GPC, XBAR, SYS, and NVD and each of rail 0 and rail 1:

1. capture the complete `0x83c` control preimage;
2. write `+1000 uV` to one slot only;
3. require exact GET_CONTROL readback;
4. while the request is active, capture all four 127-point STATUS banks;
5. restore the complete preimage;
6. recapture all four banks and compare them byte for byte with baseline.

The request was held for two seconds. No concurrent GPU workload was
intentionally launched.

## STATUS adoption matrix

Each cell is the `total_volt_offset_uv` observed across all 127 points of the
named bank:

| requested slot | GPC bank | XBAR bank | SYS bank | NVD bank |
|---|---:|---:|---:|---:|
| GPC × rail 0 (NVVDD) | +1000, 127/127 | 0, 127/127 | 0, 127/127 | 0, 127/127 |
| GPC × rail 1 (MSVDD) | 0, 127/127 | 0, 127/127 | 0, 127/127 | 0, 127/127 |
| XBAR × rail 0 (NVVDD) | 0, 127/127 | 0, 127/127 | 0, 127/127 | 0, 127/127 |
| XBAR × rail 1 (MSVDD) | 0, 127/127 | +1000, 127/127 | 0, 127/127 | 0, 127/127 |
| SYS × rail 0 (NVVDD) | 0, 127/127 | 0, 127/127 | 0, 127/127 | 0, 127/127 |
| SYS × rail 1 (MSVDD) | 0, 127/127 | 0, 127/127 | +1000, 127/127 | 0, 127/127 |
| NVD × rail 0 (NVVDD) | 0, 127/127 | 0, 127/127 | 0, 127/127 | 0, 127/127 |
| NVD × rail 1 (MSVDD) | 0, 127/127 | 0, 127/127 | 0, 127/127 | +1000, 127/127 |

For every adopted pairing, `effective_voltage_uv - source_voltage_uv` was
exactly `+1000 uV` at all 127 points. All eight requests returned success and
exact control readback, including the four pairings that STATUS ignored.

This separates storage acceptance from logical adoption. On this build the
four active logical pairings are:

```text
GPC  -> rail 0 / NVVDD
XBAR -> rail 1 / MSVDD
SYS  -> rail 1 / MSVDD
NVD  -> rail 1 / MSVDD
```

## Restoration and evidence boundary

Post-test GPC, XBAR, SYS, and NVD CSVs were byte-identical to the baselines.
The final control dump contained no nonzero frequency or rail offset fields,
and the kernel journal contained no new Xid, AER, GSP, or PCIe errors.

Confirmed:

- the eight tested slots accept and retain a `+1000 uV` request;
- only the four pairings above are adopted into the corresponding V/F STATUS
  banks;
- adoption is domain-local in this no-load STATUS experiment;
- all state was restored.

Not confirmed by this experiment:

- that every adopted logical offset wins final rail arbitration;
- that physical VRM VOUT changes by exactly 1 mV;
- load stability, performance, or safe voltage ranges.

The XBAR×MSVDD path has separate runtime evidence that larger requests can
alter the winning MSVDD target. That result still describes a logical request
and arbiter output, not an external physical VOUT measurement.

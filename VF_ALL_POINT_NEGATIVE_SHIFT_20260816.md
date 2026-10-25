# GB202 four-bank all-point negative-shift experiment

Date: 2026-08-16  
GPU: NVIDIA GeForce RTX 5090  
Driver: 610.57.04  
VBIOS: 98.02.2E.80.50

## Question

Can every type-`0x11` V/F point in the GPC, XBAR, SYS, and NVD banks be
lowered by 1 MHz or 2 MHz, and does the requested delta appear literally in
the effective STATUS frequency?

## Method

`xbar_vf_point_demo --bank-shift BANK DELTA_KHZ` performed, for each 127-point
bank and each delta (`-1000`, `-2000` kHz):

1. GET_CONTROL preimage capture;
2. byte-identical no-op SET and readback;
3. the same negative offset applied to all 127 type-`0x11` records;
4. exact GET_CONTROL readback check for every point;
5. STATUS comparison for every point;
6. restoration of the complete preimage;
7. a fresh 127-point CSV capture and byte comparison with the baseline.

No concurrent GPU workload was intentionally launched. This experiment tests
control acceptance and curve materialization, not load stability.

## Result

Every one of the 508 tested type-`0x11` control records accepted and exactly
returned both requested values. Effective STATUS frequencies were quantized to
the hardware clock grid rather than moving by exactly 1 MHz or 2 MHz.

| bank | request | exact CONTROL readback | effective-frequency delta distribution | total-offset delta distribution |
|---|---:|---:|---|---|
| GPC | -1 MHz | 127/127 | -15: 21, -8: 83, -7: 21, 0: 2 | -8: 96, -7: 16, 0: 15 |
| GPC | -2 MHz | 127/127 | -15: 21, -8: 83, -7: 21, 0: 2 | -8: 96, -7: 31 |
| XBAR | -1 MHz | 127/127 | -15: 61, -8: 66 | -8: 127 |
| XBAR | -2 MHz | 127/127 | -15: 61, -8: 66 | -8: 127 |
| SYS | -1 MHz | 127/127 | -8: 59, -7: 68 | -7: 127 |
| SYS | -2 MHz | 127/127 | -8: 59, -7: 68 | -7: 127 |
| NVD | -1 MHz | 127/127 | -8: 56, -7: 71 | -7: 127 |
| NVD | -2 MHz | 127/127 | -8: 56, -7: 71 | -7: 127 |

All deltas in the final two columns are MHz. There were no points that moved
opposite to the requested direction. XBAR, SYS, and NVD moved at all 127
points. GPC moved at 125/127 effective-frequency points; two points remained
in the same effective bin.

The identical effective-frequency distributions for -1 MHz and -2 MHz show
that both requests generally collapse onto the same representable clock step.
The different GPC total-offset distributions also show that STATUS contains
more than one quantized/materialized view; `total_freq_offset_khz` and
`effective_freq_mhz` must not be treated as interchangeable raw fields.

## Restoration and health check

The post-restore CSV for every bank was byte-identical to its pre-test baseline:

| bank | baseline SHA-256 | restored comparison |
|---|---|---|
| GPC | `f6f9e682cbec05d18fbcc204a3142aff325b605a6ec1aa4da61b84c9630aec49` | identical |
| XBAR | `0677494467b6541c8a895e233aa159408ff66883a27c3f38f4cf061378e64193` | identical |
| SYS | `f07cd8fee40e76c54212092e770fc47f543822ef8009115baa74f63c5a7bc0e7` | identical |
| NVD | `b50c636020b171633fa668e97c2e6cb7be5864cc9af6cb0feef7d3536b23de8b` | identical |

The kernel journal contained no new Xid, AER, GSP, or PCIe errors after the
matrix. This is a recovery/health observation, not a proof of long-term safety.

## Evidence boundary

Confirmed:

- all 508 type-`0x11` records accept -1 MHz and -2 MHz requests;
- all 508 exactly retain those requests in GET_CONTROL;
- STATUS moves downward at 506/508 effective-frequency points and never moves
  in the opposite direction;
- the control preimage was fully restored.

Not confirmed:

- an arbitrary 1 kHz/MHz change can be physically represented;
- a point that changes in idle STATUS is stable under load;
- the quantization table is identical on another driver, VBIOS, or GB202 board.

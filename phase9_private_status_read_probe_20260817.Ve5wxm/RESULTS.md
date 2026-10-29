# Phase-9 synchronized private-status read probe

Date: 2026-08-17  
Contract: RTX 5090 / R610.57.04 / VBIOS 98.02.2E.80.50  
Safety boundary: read-only RM/NvAPI telemetry plus the previously validated L2 correctness workload. No clock, voltage, propagation, power or fan setter was called.

## Result

The enhanced LACT Phase-9 sampler returned four complete 38-column rows at elapsed 0/115/234/355 ms while the L2 workload was settled. Every row synchronizes:

- GPC/XBAR/SYS/NVD physical clocks and aggregate MSVDD target;
- type-9 VF relations 13..17: relation-stage MHz, inferred current tuple index and inferred one-based output ordinal;
- valid/frequency pairs for known PERF limit IDs `0x41/42/43/46/48/4d/e9/ea`.

The loaded means were:

```text
GPC physical       3192.617 MHz
XBAR physical      2417.612 MHz
SYS physical       2401.817 MHz
NVD physical       2263.524 MHz
PERF limit 0x43    3195.000 MHz
XBAR thermal 0xe9 3135.000 MHz
XBAR power   0xea 2722.000 MHz
```

For GPC, the observed physical mean was within 2.383 MHz of the known `0x43` candidate. For XBAR, the known power candidate was the lower of `0xe9/0xea`, but it still exceeded physical XBAR by 304.388 MHz. Therefore `0xea=2722 MHz` is a real upstream candidate observation, not the binding final constraint or physical grant in this workload. Later V/F, propagation/shared-rail or other unobserved constraints remain decisive.

The five relation records and all eight known PERF limits stayed fixed across the 355 ms bracket. Aggregate MSVDD target nevertheless changed from 1000 mV in the first three rows to 995 mV in the fourth. This is direct evidence that the rail target/winner has independent hidden state not exposed by these clock candidates.

Relation state during the bracket:

```text
rel13 GPC  3195 MHz tuple 23 output 23
rel14 NVD  2655 MHz tuple 52 output 11
rel15 SYS  2775 MHz tuple 73 output 11
rel16 PWR  2302 MHz tuple 94 output 11
rel17 XBAR 2752 MHz tuple 115 output 11
```

Workload correctness:

```text
RESULT pass=1 rounds=622 errors=0 sm_covered=170/170
elapsed_s=4.006060 gib_s=412.422
```

The post-run GPU was healthy at P0. `kernel-alerts.txt` is empty: no NVRM Xid, GSP, AER, fallen-off-bus or reset-required event matched the test window.

## Evidence boundary

- Confirmed: the eight raw IDs are synchronized candidate observations with preserved validity bits.
- Confirmed: known XBAR candidate minimum is not the final physical grant in this workload.
- Unknown: complete candidate set, binding selector, SYS/NVD candidates and aggregate MSVDD request client/winner.
- The relation tuple/output names remain supported inferences, not published private-ABI field names.


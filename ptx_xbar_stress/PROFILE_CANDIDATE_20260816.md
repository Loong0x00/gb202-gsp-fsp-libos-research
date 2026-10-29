# RTX 5090 balanced GPC/XBAR profile candidate — 2026-08-16

Status: recorded candidate only; not applied and not yet daily-stability
validated.

## Candidate controls

- GPC ceiling: 3300 MHz
- Propagation ratio: 1:0.95
- XBAR: independent hard ceiling/curve plateau at approximately 2950 MHz
- NVVDD: dynamic maximum 1.050 V initially; independent hard safety clamp no
  higher than 1.080 V
- MSVDD: dynamic maximum approximately 1.065 V
- Do not lock minimum clocks or minimum rail voltage
- Board power limit remains a separate control; a clock ceiling is not a
  request to sustain that clock under every workload

The 0.95 propagation ratio is not itself an XBAR hard cap and must not be
treated as the direct equation `XBAR = GPC * 0.95`. The XBAR ceiling/curve must
be programmed independently and verified by direct hardware-clock telemetry.

## Evidence supporting the candidate

- A prior ratio-0.95 run observed about 3142 MHz GPC and 2915 MHz XBAR,
  demonstrating useful domain separation.
- The +440 thermal validation completed L2 and mixed full-SM checks at roughly
  2958 MHz average XBAR, 75--78 C hotspot, and zero errors/Xid in both completed
  30-second runs.
- The first warning near the 3 GHz boundary was one silent L2 mismatch; it did
  not reproduce in later trillions of checked loads, but it remains a recorded
  boundary observation.
- Larger offsets (+450 to +500 in the tested combinations) repeatedly produced
  Xid 109 context-switch timeouts. Raising NVVDD did not cure those failures,
  so avoiding the XBAR/MSVDD margin boundary is preferable to forcing 3 GHz.
- A 3300 MHz GPC-tail candidate previously realized about 3096 MHz in the
  fixed Cyberpunk 2077 test. Therefore 3300 is only a ceiling, not a validated
  sustained actual clock.

## Validation still required

Before calling this a daily profile, record direct GPC/XBAR/SYS clocks and rail
targets in an RT-heavy game, confirm that XBAR never exceeds its intended
ceiling, run a short bounded L2/mixed integrity check, and require zero data
errors, Xid, GSP-health, AER, and PCIe events. Avoid another long 750--800 W
soak solely to accumulate duration; loaded connector-current distribution was
not captured in the prior thermal run.

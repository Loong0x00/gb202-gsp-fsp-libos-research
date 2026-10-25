# RTX 5090 MODS 570.215 diagnostic summary

Date: 2026-08-25  
GPU: ASUS RTX 5090, GB202 A1, Samsung 32736 MB GDDR7  
VBIOS: `98.02.2E.40.E0`  
Configured TGP limit: `600 W`

## Confirmed

- Factory GLStress passed. A standalone full-memory MATS attempt ran for 30 minutes without a reported miscompare, but was interrupted and is not a PASS.
- Memory-only suites passed at 16001, 16501, 17001, 17501, 17751, 17876, 17938, and 18000 MHz requests.
- At 18000 MHz, the measured memory clock was about 17982 MHz.
- 18000 MHz NewCudaMatsRandom, 64 iterations: 34.008 TB, 1326.7389 GB/s, PASS, all EDC/read/write/replay counters zero.
- 18000 MHz NewCudaMatsStress plus HMMA, 128 iterations: 67.231 TB, 1094.2416 GB/s, PASS, all EDC/read/write/replay counters zero.
- 18000 MHz plus 60-second GLStress: 53.295 TB, 888.2430 GB/s, PASS, all EDC/read/write/replay counters zero. Maximum board-input telemetry was 501.174 W.
- Factory-clock GLCombustPulse/ClockPulseTest for 120 seconds passed. Board-input telemetry was 577.312-600.487 W.
- The 18000 MHz GLCombustPulse/ClockPulseTest completed before the interrupt arrived and reported PASS with all EDC/replay counters zero. Board-input telemetry ranged from 221.408 W to 657.305 W despite the displayed 600 W TGP limit.
- Both automatic-voltage and manually requested 1050 mV attempts at 18001 MHz failed before the memory test started. The failure occurs after `Offsetting clock vf relationship entry 12 by 4000000kHz`, with PMU-RISCV halt, change-sequencer timeout, and MODS error 539. This is not a memory miscompare.
- A 3000 MHz GPC request was not adopted: SetPState remained at 2955 MHz, while the 60-second GLStress physical GPC clock was about 2765-2814 MHz. That run passed but is not evidence of 3000 MHz stability.
- The guest kernel reported no NVRM/Xid/AER/PCIe/OOM errors. The host reported only expected VFIO resets, with no AER/Xid/OOM evidence.

## Interpretation

- MODS did not enforce the consumer-driver rule that non-RTX-5080 Blackwell cards stop at 17000 MHz. This RTX 5090 ran tests above 17000 MHz and accepted exactly 18000 MHz.
- The 18001 MHz failure is consistent with an internal MODS/RM `+4000 MHz` offset boundary: 18001 - 14001 = 4000 MHz. Exactly 18000 MHz, a +3999 MHz request, was accepted and tested.
- No EDR/replay activity was observed at any explicitly counted high-memory-clock point. Single-run bandwidth fluctuations at 17751-17938 MHz were not repeatable; 18000 MHz returned to 1326.7389 GB/s with zero replay counters.
- These tests found no evidence of a gross GDDR7 link/cell defect or a default-curve GPC computation defect under the covered workloads. They do not prove the hardware is universally stable or reproduce the original game hang.
- Because MODS uses a different control stack and GSP-RM was disabled, clean MODS results leave host-driver/GSP/power-state-transition behavior as a live hypothesis for the game freezes.

## Safety and unknowns

- Do not request 18001 MHz again with this MODS/VBIOS combination; it reproducibly halts PMU-RISCV before the workload.
- Do not repeat the known 1050 mV / 3100 MHz GPC point without a new safety design; it previously hard-failed.
- Do not repeat `18000 + GLCombustPulse` under the assumption that the configured 600 W TGP is a physical instantaneous ceiling. MODS telemetry reported a 657.305 W peak. An external power meter was not used, so the exact physical input remains unverified.
- The 30-minute full MATS attempt was incomplete and cannot be recorded as PASS.

## Recovery state

- VM shut down normally and VFIO reset completed.
- GPU rebound to the host NVIDIA driver; audio rebound to `snd_hda_intel`.
- GDM, LACT, and nvidia-persistenced were active after recovery.
- Final host readback: VBIOS `98.02.2E.40.E0`, 600 W power limit, 14001 MHz memory clock.

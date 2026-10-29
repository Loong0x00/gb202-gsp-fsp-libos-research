# LACT Phase 5 H-04 composite MSVDD receipt

Date: 2026-08-17

Contract: NVIDIA R610.57.04 / VBIOS 98.02.2E.80.50 with the complete library, GSP, ROM and propagation-topology fingerprints pinned by the branch.

## Result

- The composite transaction wrote the rail-1 domain offsets for XBAR, SYS and NVD atomically in one complete `0x83c` clock-domain control block.
- Both experimental-envelope endpoints, `-1000 uV` and `+1000 uV`, passed SET, complete control-block readback, semantic STATUS checks and restoration.
- For each endpoint, all 127 XBAR, 127 SYS and 127 NVD STATUS points moved their effective voltage and total voltage offset by exactly the requested delta. Frequency fields and point controls were unchanged. The GPC/NVVDD curve was unchanged.
- The only bytes differing from the original control block were the three signed 32-bit fields at offsets `0x90`, `0x110` and `0x150`.
- Idle aggregate MSVDD target remained `880000 uV` for baseline and applied snapshots at both endpoints. This does not contradict per-domain adoption: the 1 mV request did not cross the current shared-rail winner or 5 mV target quantization boundary.
- Independent clock counters were recorded but are not treated as an adoption criterion for a voltage-curve shift at idle.
- No Xid, GSP, AER, PCIe bus error or reset-required event appeared in the test window.

## Control-block hashes

```text
original/restored/final:
2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b

-1000 uV applied:
3bdd222559ca0cc244423ee01520695a630b0c9e2727c224844ed578a3d6603b

+1000 uV applied:
14969ca6aba6fe3bef844581a4b281a9d145038fe31415ac4f1dc9f15552f663
```

The first ordinary-user attempt stopped before SET because `/sys/bus/pci/devices/0000:01:00.0/rom` is root-only and the live ROM fingerprint could not be verified. The two successful endpoint tests ran the already-built test binary as root; the contract gate was not bypassed.

## Boundary

This proves adoption and exact restoration of the two tested values on this exact contract. It is not a vendor-advertised safe range and does not authorize extrapolation beyond `-1..+1 mV`. Loaded shared-rail winner reconstruction and combined point/domain controls remain separate tests.

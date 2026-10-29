# LACT Phase 6 propagation-ratio receipt

Date: 2026-08-17

Baseline GPC-to-XBAR ratio: `0x0000e660 = 0.899902344`.

## Control result

- The production transaction changed only the active GPC-to-XBAR ratio record in `CLK_TOP_PROP_RELS CONTROL`.
- Tested raw values `0xe620`, `0xe560`, `0xe760`, and `0xf333` all returned exact SET/readback and restored the complete relation-control preimage.
- Original/restored SHA-256 for every run: `5c94badfbd2cde7b5300a4c6d2d170fdd97fdf50c0caee30470e002a71d00470`.
- Domain and XBAR/SYS V/F preimages remained unchanged.
- All four 8-second L2 runs completed with 170/170 SM coverage, zero data errors, and zero Xid/GSP/AER/PCIe/reset-required alerts.

## Physical result

- `0xe560`: 25-sample XBAR average `2412.125 -> 2410.338 MHz` (about `-1.787 MHz`).
- `0xe760`: 25-sample XBAR average `2412.151 -> 2410.562 MHz` (about `-1.589 MHz`, wrong direction for a simple ratio-only response).
- `0xf333 ≈ 0.95`: 25-sample XBAR average `2411.272 -> 2412.129 MHz` (about `+0.857 MHz`).

These deltas are not discriminating relative to workload/measurement variation. The current L2 case is plausibly limited by the local XBAR V/F candidate or another constraint rather than propagation, but that is an inference, not a proven winner classification.

## Release decision

The private control implementation and restoration are retained, but normal apply is blocked with `physical_adoption_validated=false`. The GUI remains read-only and changed hand-written ratio configurations are rejected. Only the explicit live-test environment gate can bypass that adoption gate for further experiments.

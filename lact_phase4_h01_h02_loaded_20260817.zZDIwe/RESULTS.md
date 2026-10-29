# LACT Phase 4 H-01/H-02 loaded receipt

- Date: 2026-08-17
- Branch: `blackwell-multidomain-vf`
- GPU: `GPU-43fc92f5-ea03-4a4f-ef51-3e346d97c8dc`
- Workload: `ptx_xbar_stress --mode l2 --seconds 6 --l2-mib 32 --vram-mib 1024`
- Transaction: one domain at a time, `0 -> +15000 kHz`, fresh readback, complete preimage restore

## Confirmed

- XBAR CONTROL and all 127/127 effective/total STATUS frequencies moved by exactly `+15000 kHz`.
- XBAR independent physical sample moved from `2416998` to `2430608 kHz` (`+13610 kHz`).
- SYS CONTROL and all 127/127 effective/total STATUS frequencies moved by exactly `+15000 kHz`.
- SYS independent physical sample moved from `2401356` to `2415076 kHz` (`+13720 kHz`).
- Non-target domains and point banks were unchanged during each transaction.
- The L2 workload passed 935 rounds with 0 errors, digest `7becbcafb348d2fd`, and covered 170/170 SMs.
- Original, per-domain restored, and final `0x83c` control blocks are byte-identical. Their SHA-256 is `2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b`.
- A fresh post-test GET reported GPC/XBAR/SYS/NVD domain offsets of `0 kHz`.
- No Xid, GSP reset/failure, AER, PCIe error, or reset-required record appeared in the test window.
- A later rail-observed rerun reported aggregate MSVDD target `995000 uV` at baseline, applied, and restored for both XBAR and SYS. The corresponding files preserve all NVVDD/MSVDD status fields.

## Boundary

- The physical deltas are close to, but not exactly, the requested `15 MHz`; physical clocks remain quantized and workload-governed.
- The earlier idle-only run produced a falling XBAR sample despite exact CONTROL/STATUS adoption. It is retained in the sibling receipt directory as evidence that a single idle sample is not an adoption test.
- The first rail-observed rerun found another false test assumption: complete control restore succeeded, but dynamic V/F STATUS changed under continuing load and failed a whole-struct equality check. The test now compares the complete `0x83c` preimage plus persistent domain/point controls, while treating measured/effective STATUS as dynamic. The corrected identical-load rerun passed.
- This receipt verifies the XBAR/SYS frequency-only path and observes aggregate MSVDD; it does not authorize a voltage setter. Fresh target limits (`VMIN/reliability/maximum`) are not a per-domain offset range.

## Files

- `domain-control-original.bin`: complete preimage.
- `xbar-applied-control.bin`, `sys-applied-control.bin`: SET readbacks.
- `xbar-restored-control.bin`, `sys-restored-control.bin`: per-domain restore readbacks.
- `domain-control-final.bin`: final readback after both transactions.
- `xbar-voltage-rails.txt`, `sys-voltage-rails.txt`: fresh baseline/applied/restored aggregate rail STATUS.

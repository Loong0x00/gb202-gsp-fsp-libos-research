# Verification

PASS: `python out/static_tests.py` (two successful runs, second expands actual high-writer and boundary-barrier coverage). CPU integer/symbolic only, no floating NN, MMA numeric, original prediction or native execution.

PASS: `python out/generate_contracts.py` asserts9 fields/all111 load sites, own slab SHA, exact9 input paths and31 input chunks/windows, then emits all requested contracts/reports.

PASS: final output-only JSON/contract consistency checks:64x32 FP8 learned field; high ABI8/port1 and low ABI64/port0;264MMA;2048 high and1024 low tagged bytes;6464-byte preserved padding/data address overlap. REPORT/PROGRESS/FAILURES are each under2000 lines.

The original source/slab SHA identities and corrected5982/4902 executable-op counts are asserted. PE was only raw-read and disassembled:0 scans,1x4096B .text window,4096B header,2x32B rdata strings. `ACTUAL_PATHS_READ.json` lists original inputs, generated-artifact reloads and executed own static scripts separately.31 is the authorized-input window/chunk count, not a claim about every internal output-artifact file open.

Remaining uncertainty is explicit in both contracts and REPORT: native numeric precision/approximation, actual block4 activations, active handle/warp geometry, alias/allocation/lifetime/publication, general padding safety and odd-size coverage. No completion/freeze claim for these boundaries.

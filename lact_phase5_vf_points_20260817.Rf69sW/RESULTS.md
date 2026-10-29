# LACT Phase 5 XBAR/SYS point-control receipt

Date: 2026-08-17

## Confirmed

- XBAR point 0 accepted and read back `-15000 kHz` and `+15000 kHz`; effective frequency moved `225 -> 210/240 MHz` and the total-frequency-offset field moved by the exact same delta.
- SYS point 0 accepted and read back `-15000 kHz` and `+15000 kHz`; effective frequency moved `180 -> 165/195 MHz` and the total-frequency-offset field moved by the exact same delta.
- For every transaction, the other 126 points in the target bank, the other V/F banks, all voltage fields, and the complete domain control block were unchanged.
- Each transaction restored the complete selected XBAR/SYS V/F preimage before returning. Final V/F and domain preimages were byte-identical to their originals.
- No Xid, GSP failure, AER, PCIe bus error or reset-required event appeared in the test window.

## Hashes

```text
V/F original/restored/final:
f78ccf3c19d1876b18cb0c723f4d5eeb77f53f6ff920a0154b77d9382acc25d5

domain original/final:
2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b

XBAR applied -15/+15 MHz:
f432bf838269003ac6458d8ba5b861c1d646549caf0186e8f6da66a6f24fb45d
42a28992bb8642d24030a3a37a5c4d35734681e2a00c224ed3c19bccc8265803

SYS applied -15/+15 MHz:
be08ecd690119863c6cf14dd16b5b77253e5c702521c925e2e43dac250e00191
859929411ed6defc91af0579f94ea1780cb5be00b47d5ad8c25835ef44f92448
```

## Boundary

This validates the LACT XBAR/SYS sparse point setter and the exact-contract `-15..+15 MHz` experimental envelope. Point 0 is not the active high-voltage point under ordinary P0 load, so idle physical clock samples are not used as point-adoption evidence. NVD point writes remain disabled.

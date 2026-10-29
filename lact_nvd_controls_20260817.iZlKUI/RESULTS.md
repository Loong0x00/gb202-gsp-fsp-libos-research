# NVD domain-frequency adoption and point-control counterexample

Date: 2026-08-17

## Domain-wide frequency control

The formal transaction path requested `NVD 0 -> +15000 kHz`. All 127 NVD
STATUS points shifted by the requested delta, the control block read back, and
the full preimage restored. Idle direct NVD measurement moved
`2134841 -> 2121748 kHz`; that direction is not an adoption discriminator due
to gating/workload drift, so the UI exposes only a clearly experimental
absolute `-15..+15 MHz` envelope and does not claim a known consumer.

The same run rechecked XBAR and SYS `+15 MHz`. Original/final domain CONTROL
SHA-256 are identical:

```text
2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b
```

## NVD point 96 negative result

Separate `-15000` and `+15000 kHz` point requests both passed the immediate
SET/full-CONTROL transaction check, but the next fresh CONTROL/STATUS read
returned point control `0`, effective frequency `2430000 kHz`, and total
offset `0` in both directions. Therefore NVD point SET is not adopted and is
disabled in the production compiler and GUI.

Both failed-adoption probes still ran the restore path. Each restored V/F
CONTROL SHA-256 equals the original:

```text
f78ccf3c19d1876b18cb0c723f4d5eeb77f53f6ff920a0154b77d9382acc25d5
```

No Xid, GSP, AER or PCIe error was logged in the test window.

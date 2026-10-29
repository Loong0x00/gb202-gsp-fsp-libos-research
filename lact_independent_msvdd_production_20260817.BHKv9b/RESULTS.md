# Production compiler: independent MSVDD mapping adoption

Date: 2026-08-17

The formal LACT transaction compiler applied one `+5000 uV` rail-1 mapping
offset at a time to XBAR, SYS and NVD. Each transaction:

- changed only the selected domain's four-byte rail-1 offset field;
- returned the requested per-domain CONTROL and 127-point STATUS voltage shift;
- left the two non-target MSVDD domains and GPC control state unchanged;
- restored from the full domain CONTROL preimage.

The idle aggregate MSVDD target stayed at `880000 uV`; this is control/STATUS
adoption evidence, not proof that the shared physical rail winner changed.

Original and final `0x83c` CONTROL SHA-256 are identical:

```text
2caf4cd0ab7bcf18400926dbf37d787f3a0d3cda95db32c7865eeb05a7ea9b0b
```

No Xid, GSP, AER or PCIe error was logged in the test window.

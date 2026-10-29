# Route 2: natural FSP client mapping — 2026-10-28

> Erratum: the first version closed this route too strongly. `0x41d4140` is a pointer slot, not `A0`; a later read showed that the slot is NULL. Therefore it is not a valid natural client object and cannot be used to judge the route. The raw-MMIO positive-control fault only proves failure in the injected task. The correct status is "no natural client object/mapping evidence currently available", not a proof that every possible natural context fails.

## Findings

- Static call-chain analysis separates the dynamic client instance (`param_2`) from the outer context (`A0`). The MMIO base is `B=*(uint64_t *)(A0+0xb98)`, and EMEMC is accessed as `B+0x8f2ac0`.
- The client instance is allocated dynamically; there is no proven fixed global address for `A0`.
- The previously inspected candidate field `0x41d4140+0xb98` is zero. If that value were used as `B`, the only resulting address is raw `0x8f2ac0`.
- A direct read of raw `0x8f2ac0` already produced a load page fault in the injected task. Thus there is no valid positive-control mapping to test.
- The formal GSP-PRI route independently returns poisoned values for sensitive FSP registers and must not be repeated.

## Conclusion

Route 2 has no valid positive-control experiment. Do not continue guessing dynamic object addresses or raw MMIO aliases. A new runtime artifact showing a natural `A0` and a nonzero, task-accessible `B` would be required to reopen it.

Together with route 1 (`FSP_MESSAGE_SERVICE_AUDIT_20261028.md`), this closes the currently evidenced software paths to `FSP_RUN` plaintext. Further progress requires a new artifact, a protocol/schema discovery, or a different debug access condition.

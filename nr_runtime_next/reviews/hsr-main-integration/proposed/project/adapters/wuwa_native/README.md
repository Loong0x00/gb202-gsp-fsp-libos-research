# WuWa native D3D12 ingress candidate (CPU/cross-compile only)

Deliverables in this isolated scope:

- `native/`: current pc3b verified-effective native source copy with actual WuWa
  ingress, allocation-aware live VRAM admission, format normalization, private
  queue/list format-tail observers, and no runtime ABI/CP runtime edits;
- `protocol/`: unchanged frozen D5RP v1 copy;
- `integration.patch`: main-tree patch based on the exact hashes in
  `SOURCE_PRECONDITIONS.md`;
- `wuwa_lease_publisher.py`: non-deployed heartbeat prototype importing the
  existing read-only LoginTime `PhaseGateState`;
- `tests/`: CPU lease/PID selector, production budget-policy, and source-order
  checks.

Build and CPU-only verification:

```bash
make -C adapters/wuwa_native all
make -C adapters/wuwa_native cpu-test
```

`all` cross-compiles the same three owned Windows DLLs and links the existing
format static library. `cpu-test` does not invoke Wine or launch a GPU/game. See
`INTEGRATION.md` for ordering/lifetime details and exact unresolved live-game
checks.

This candidate does not deploy, rename, or remove installed files. The eventual
clean-native deployment must remove the old ReShade host/add-ons rather than
rename them, while preserving a rollback snapshot; that remains Main-owned.

# Frozen test result

Build ID `d5native-pc1-20260910` was checked on the local x86-64 Linux host with MinGW-w64 GCC 16.2.0 and Wine 11.17.

Passed command:

```text
make -C native check
```

Passed checks:

- native policy test: exact D5RP32 / unchanged D5LC72, cold latch, 1..10 independent layer identities and counters, one PRE/POST chain and final compose, parameter restoration, post-forward submission ordering, reset rejection, RR/PRE and phase guards, VRAM estimate;
- PE source/export check: six audited Wine DXGI exports, host/runtime ABI exports, no ReShade/RenoDX integration symbols, no packaged NVIDIA DLL;
- Wine fake-runtime harness: proxy forwarded `CreateDXGIFactory1` to actual system32 Wine DXGI, loaded both exact owned basenames outside `DllMain`, exposed adapter ABI, and did not emit production capabilities for the fake backend.

The Wine factory check emitted local Mesa EGL device-discovery warnings but created no D3D12 device, command list, Feature 18 handle, or GPU submission. No game test was run. Real CP2077/RTX 5090 acceptance remains the main owner's cold test described in `../docs/HANDOFF.md`.

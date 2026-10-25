Mechanism correction and follow-up: the rail min/max policy window in my earlier comment is **not** the same path as MSI Afterburner's `L` shortcut.

I statically traced Afterburner 4.6.7 Beta 3: `L` reaches private PERF_LIMIT GET/SET QueryInterface IDs and submits one frequency or voltage limit record. It neither expands the frequency request into a min/max pair nor touches the NVVDD/MSVDD rail-control block described above.

I opened a separate issue for the actual NVIDIA/MODS hard P-state mechanism: https://github.com/ilya-zlobintsev/LACT/issues/1177

That issue traces MODS `-pstate_hard` to the distinct `0x2080a071` control, includes both a real MODS run and a production Linux driver/GSP physical validation, and keeps the Windows findings explicitly static/inferred. In other words:

```text
#1045 rail window != Afterburner L != NVML locked clocks != strict PERF_LIMIT clients != A071 HardLock
```

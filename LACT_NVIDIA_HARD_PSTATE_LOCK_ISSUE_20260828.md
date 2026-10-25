## Summary

Could LACT investigate an explicitly experimental NVIDIA **hard P-state lock** mode, separate from both:

1. LACT's existing NVML `nvmlDeviceSetGpuLockedClocks` min/max range; and
2. the voltage-rail policy window described in #1045?

I originally conflated a pair of private PERF_LIMIT clients with MODS `-pstate_hard`. An exact trace showed that this was wrong: the true MODS HardLock branch uses `NV2080_CTRL_CMD_PERF_SET_FORCE_PSTATE_EX` (`0x2080a071`, 12-byte parameters). The build-private PERF_LIMIT client IDs must not be implemented under the name "HardLock".

## Verified MODS path

Static tracing of MODS 570.215 on GB202 gives this chain:

```text
-pstate_hard
  -> g_ForcedPStateLockType = PerfConst.HardLock
  -> GpuSubdev.Perf.ForcedPStateLockType
  -> SetPerfPoint(...)
  -> HardLock branch: 0x2080a071, 12-byte parameters
```

MODS treats this as materially different from its soft/strict PERF_LIMIT paths. It also warns that a hard lock prevents RM from reducing clocks for voltage, temperature, or power protection, and requires `-pwr_cap 0`. This is therefore not a safe synonym for normal locked clocks.

I also ran the real diagnostic path on an RTX 5090 / GB202:

```text
MODS 570.215
GSP-RM: Disabled
gputest.js -test 2 -pstate 0.max -pstate_hard -pwr_cap 0 \
  -gpcclk 3100 -nvvdd_mv 1050 ...

reported GPC: 3105 MHz
reported NVVDD/MSVDD: 1050/1050 mV
GLStress test 2: PASS, 4.960 s
Error Code: 0
```

The `GSP-RM: Disabled` line is important: this first run proves the MODS diagnostic behavior, not availability through the normal production GSP stack.

## Verified production-driver reachability

The same `0x2080a071` control is accepted by the unmodified Linux 610.57.04 production driver and normal production GSP on the same GB202 card.

The tested composition was:

```text
1. Save the complete control preimages.
2. Set the NVVDD policy window and wait for physical target adoption.
3. Set the GPC V/F-domain point through 0x2080d01c.
4. Enable 0x2080a071 with words [1, 0, 2].
5. Restore D01C byte-for-byte, clear A071 with [0, 0, 2], then restore voltage.
```

At a nominal 3100 MHz / 1050 mV request, physical telemetry stayed on the GB202 clock grid at 3090/3097 MHz under a checked mixed compute + L2 + VRAM + atomics workload. The workload covered all 170 SMs, completed 115 rounds with zero data/compute/atomic errors, and peaked at about 267 W. The A071 set and clear calls both returned status 0, and the D01C and voltage preimages were restored.

This demonstrates production-stack reachability and a physical outcome for the composition. It does **not** prove that A071 alone selects a frequency, nor that hardware clock stretching, PLL failure, or emergency hardware protection can be disabled.

For clarity, a separate 2800 MHz multi-engine test used private strict min/max PERF_LIMIT clients. It is useful physical evidence for that different path, but it is **not** evidence for MODS `-pstate_hard` and should not be cited as such.

## Windows evidence: static inference only

I also traced MSI Afterburner 4.6.7 Beta 3 and the retail Windows 610.74 `nvapi64_impl.dll`. No live Windows setter was called.

- Afterburner's `L` handler reaches RTHAL and the private NvAPI PERF_LIMIT GET/SET QueryInterface IDs `0xe440b867` / `0x39442cfb`.
- Its horizontal frequency lock submits one `GRAPHICS_MAX` record (selector 0, type 2, MHz x 1000). Its vertical voltage lock submits selector 6/type 3.
- The Windows 610.74 SET implementation serializes one internal PERF_LIMIT record per input item through the legacy inner command `0x2080e078`. It does not silently expand the Afterburner request into a min/max pair and does not touch the rail-control block from #1045.
- That serializer's build-private mapping table also contains `0x7f -> 0x83` and `0x82 -> 0x86` entries. This suggests that additional strict/MODS-rule limit clients are recognized by the retail Windows userspace bridge.

The last point is only a static inference. It does **not** show that Afterburner `L` uses those clients, that Windows exposes A071, or that a physical hard lock was achieved on Windows. The numeric client identities are driver-build-specific.

Binary fingerprints used for the Windows static trace:

```text
MSIAfterburner.exe  SHA256 6089a3ff1c3372436089f15c1f17ed0a8071edb2b880afe2510e7ee2ef50f98a
RTHAL.dll           SHA256 9a29fbd90a6b92f6a8357a860e2a4778bc1e3e3c3a86adebdd6fcc3a8ac07f85
nvapi64_impl.dll    SHA256 124e10d58ab5720da4d2b865aaabeb568379b21224c5765ebaadaad49214ac8e
```

## Suggested LACT scope

Would you accept a compatibility-gated research implementation of the Linux A071 path? I suggest that it should initially have all of these restrictions:

- clearly separate naming/UI from ordinary "GPU Locked Clocks" and voltage lock;
- exact driver/library/layout fingerprinting and parameter-size validation;
- disabled by default and never applied at boot or stored in automatic profiles;
- a short mandatory timeout, signal-safe clear, and verified restoration preimages;
- physical GPC and rail telemetry after control acceptance, rather than treating setter success as proof;
- no automatic disabling of power/thermal protection;
- an explicit warning that preventing software derating can turn a recoverable throttle into computation errors, a GSP hang, or a GPU reset.

This is related to #1045 only because the controls can be composed. The #1045 rail window, Afterburner `L`, ordinary NVML locked clocks, private strict PERF_LIMIT clients, and A071 HardLock are five distinct mechanisms.

Disclosure: the reverse-engineering workflow and issue drafting were assisted by OpenAI Codex. The hardware runs and measurements were performed on my system.

## Summary

On RTX 50-series (Blackwell / GB202), NVML — and therefore `nvidia-smi`, LACT, and every NVML-based tool — reports only the **edge** GPU temperature. The **hotspot / junction** temperature is not available through NVML on this generation.

While investigating this, I found two things that may be useful for LACT:

1. On driver **610.43.03**, the private thermal graph returned by the driver enumerates GPU thermal providers **0–5 only**; the provider that MODS names **`GPU_OFFSET_MAX`** (the hotspot, provider index 6 in older MODS builds) is **absent** from the graph. In other words, on this driver the value is missing at the thermal-graph level, not merely filtered at the NVML surface.
2. The underlying sensor is still live and the aggregate appears to be **readable via a direct, read-only register access** that does not use MODS and does not modify anything.

I'm filing this as a **finding / feature request for discussion**, with explicit evidence grades. The register/decode is inferred and GB202-specific; please treat it as experimental. A standalone read-only probe is available for anyone who wants to reproduce it.

## Environment (only configuration tested)

- GPU: **NVIDIA GeForce RTX 5090 (GB202, Blackwell, `sm_120`)**, PCI `0000:01:00.0`
- Driver: **610.43.03** (nvidia-open KMD), CUDA 13.3
- OS: Arch Linux

## How it is read (read-only; no MODS; no kernel changes)

Direct `mmap` of `resource0` / `/dev/mem` fails under strict-devmem while the device is bound, so the probe uses the nvidia-open KMD's published control **`NV2080_CTRL_CMD_GPU_EXEC_REG_OPS` (0x20800122)** with a fixed `READ_32` / `GLOBAL` reg-op. The source issues no `WRITE` opcode and has no write branch. Semantics: `read(BAR0 + offset)`. PTHERM base is BAR0 offset `0x00ad0000`.

| BAR0 offset | Meaning | Decode |
|---|---|---|
| `0x00ad0400` | **edge** (equals `nvidia-smi` GPU temp; used to anchor the map) | `raw & 0xff` |
| `0x00ad0aa0` | bank-A MAX of sources `0x00ad0a90/a94/a98/a9c` | Q9.5 (below) |
| `0x00ad0ae0` | bank-B MAX of sources `0x00ad0ad0/ad4/ad8/adc` | Q9.5 (below) |
| `0x00ad0718` | static **107 °C throttle limit** — a threshold, **not** a live temperature | `(raw & 0x3fff)/32` |

```c
static double decode_q95(uint32_t raw) {      /* 14-bit signed, 1/32 C */
    int q = (raw >> 3) & 0x3fff;              /* bits [16:3]           */
    if (q & 0x2000) q -= 0x4000;              /* sign-extend           */
    return q / 32.0;
}
double edge    = read32(0x00ad0400) & 0xff;
double hotspot = fmax(decode_q95(read32(0x00ad0aa0)),
                      decode_q95(read32(0x00ad0ae0)));   /* candidate */
```

## How it was verified

- **Edge cross-check:** `0x00ad0400 & 0xff` tracks `nvidia-smi`'s GPU temp within ±1 °C across samples, confirming the map is anchored correctly. **[verified]**
- **MAX-aggregate invariant:** `0x00ad0aa0 == max(its four sources)` held **800/800** bank-samples under load (and every idle sample); bank B is a byte-exact mirror of bank A. The active max source alternates between source 0 and source 3, consistent with a real "hottest of N sensors" aggregate. **[verified]**
- **Load response:** under a compute load the candidate rises above edge and falls on cooldown. At ~475.8 W board power: candidate **81.4 °C** vs synchronous edge **68 °C** (Δ ≈ **20.8 °C**); idle Δ ≈ 3 °C; no Xid, no throttle. The delta grows with power, as expected for a die junction sensor. **[verified]**
- **MODS naming (static only):** static reverse-engineering of a MODS 570.151 build (never executed; see below) shows GPU thermal provider 6 is named **`GPU_OFFSET_MAX`**, read via private RM controls (`ThermalChannelGetStatus 0x2080853b`, etc.) and returned as signed **Q24.8** (int32 / 256 °C). MODS reads it through private RM → GSP; its host ELF contains no `0xad0aa0/0xad0ae0` constants, i.e. MODS uses a different path to the same class of value. **[verified: the name and MODS path]**

## Inference and open questions

- The BAR aggregate at `0x00ad0aa0/0x00ad0ae0` (max of the two) is very likely the same physical value as MODS's `GPU_OFFSET_MAX` — matching structure (a max over distinct on-die sources), magnitude (~20 °C over edge under load), and behavior. Exact one-to-one equivalence is **[inferred]**, not proven, because MODS was not executed.
- The hotspot's role in the 107 °C throttle is independently documented: an RTX 5070 Ti with poor thermal-interface-material application was reported hitting NVIDIA's 107 °C hotspot throttle limit (read via MODS) while conventional tools showed ~68 °C ([Tom's Hardware](https://www.tomshardware.com/pc-components/gpus/hotspot-temperature-sensor-on-nvidias-blackwell-gaming-gpus-is-still-accessible-if-you-have-access-to-nvidias-internal-mods-tool-nvidia-rtx-5070-ti-caught-throttling-at-107-c-over-poor-tim-application)). I could not reproduce that on this card — its cooling keeps the hotspot far below 107 °C and I did not force it via unsafe fan/power manipulation — so whether **this specific register** is the exact cycle-for-cycle comparator input remains **[inferred]**, though the hotspot-to-107 °C-throttle behavior itself is established.
- Of the four source slots per bank, only **three are independent**: bank B mirrors bank A, and source 3 is consistently `source 2 + exactly 3.0 °C` — plausibly a guardband/margin copy and a redundant read path for a safety sensor, rather than four independent sensors. **[verified relationship; purpose inferred]**
- Offsets and decode are **GB202-specific and undocumented**; they may differ on other Blackwell SKUs and may change across driver revisions.

## Suggestion

Given the caveats, this would fit as an **experimental / opt-in** hotspot readout for GB202, clearly labeled as inferred, rather than a default trusted value. It is worth surfacing because hotspot is exactly the temperature that matters for fan control and is otherwise invisible on RTX 50 under Linux. I'm happy to share the standalone read-only probe and raw sample logs.

## Optional MODS cross-check — NOT performed here; untrusted; use at your own risk

The only remaining way to confirm a frame-for-frame match with NVIDIA's own value would be to run MODS and compare. I deliberately did **not** do this. The only MODS package I could locate for this GPU is a stripped, unsigned, closed-source binary with raw hardware write capability (PCI/MMIO/DMA/EEPROM/fuse/reset via its kernel module); I was not willing to run it against a real GPU, and this method does **not** require it.

For anyone who wants to attempt the cross-check independently and accepts the risk, the package I static-audited was:

- `570.151_GB202_5090.zip`, size `943721235`, SHA256 `d141f685ea70c9a49095b7369201ab0651222bea3c063acfd6616dfde058ded9`
- source (third-party, **unverified**): https://disk.yandex.ru/d/tAIPw5QLnez-2g

Static-audit notes: its bundled kernel-driver source matched NVIDIA's official `mods-kernel-driver` v4.29 byte-for-byte and no obvious IOCs (path traversal, SUID, miners, ransomware, persistence) were found — **but** the ~392 MB core `mods` ELF could not be audited (stripped, high-entropy embedded scripts, no valid release signature). Treat it as untrusted. No safety guarantee.

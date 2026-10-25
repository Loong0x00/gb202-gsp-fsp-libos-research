# 36 — GSP device model (in development)

> **Status: in development (2026-10-03, S1 work package).** This page
> documents the `sim/devices/` device model, the versioned
> `sim/profiles/` documents and the real-firmware boot-ladder results. It is
> the companion to `35-GREENEYE-SIMULATOR-DESIGN.md` §3 (Phase S) and
> `06-ACCURACY.md`. Development-only: nothing here authorises GPU hardware,
> kernel modules, mdev, guest access or reboots.
>
> **See also:** `37-SIM-QEMU-LINE.md` (the B0–B3 device model on the frozen
> simulator-vs-QEMU checks) and `40-NEW-VERSION-TRIAGE.md` (one-command triage
> of a new image through this ladder).

## 1. What this is

The device model gives the native RV64 core (`sim/machine.py`) real MMIO
semantics for the windows the real GSP firmware touches while booting, so a
bounded run advances **past the QEMU first fault** with evidence instead of
lenient zero-reads. Modeled devices take precedence over the lenient
device-map/unknown fallback; an access inside a modeled window that the
device does not implement is still reported as unknown (never silently
zeroed). Every modeled register carries an **evidence kind**:

* **header** — a hardware register/field map (offset, width, access type,
  field positions, reset/alignment);
* **firmware use** — the disassembled firmware code that reads/writes it;
* **observed access** — the address/width/direction/PC/value sequence seen in
  a real run;
* **shim** — reset-time state the real SEC2 booter/host would provide; always
  an explicit, session-recorded assumption, never a device claim.

If a window cannot be proven, none of it is modeled and it is listed as an
unknown (§6).

## 2. Architecture

```
sim/profiles/<name>.json     versioned profile: windows, chip id, load layout,
        │                    DMA aperture windows, boot-shim values
        ▼
sim/devices/__init__.py      registry_from_profile(profile, machine)
        │
        ├─ base.py           DeviceRegistry: range+size decode, access log,
        │                    JSON state/snapshot, peek() debugger surface
        ├─ pmc.py            PMC/master block (NV_PMC_BOOT_42 chip ID)
        ├─ falcon.py         falcon block: IRQ, MAILBOX0/1, DEBUGINFO, DMA,
        │                    FBIF control/transcfg
        ├─ priscv.py         RISC-V-local block: IRQ mask, trace, error regs
        ├─ timer.py          PTIMER (modeled virtual time; opt-in)
        ├─ csb.py            CSB/TRANSCOM message window seam (B4 landing)
        ├─ fwsec.py          WPR2 address pair (FWSEC state unmodeled)
        ├─ pmu.py            PMU stub: observes, never fakes
        ├─ dma.py            aperture → RAM translation seam (FBGPA/SYSGPA)
        └─ irq.py            falcon + RISC-V-local IRQ aggregation
        ▼
sim/machine.py               Machine(devices=..., translator=..., reset_regs=...)
        │                    + sim/mpu.py: XMPU entry model (fetch/load/store)
        │                    + sim/libos.py: libos syscall service model
        ▼
sim/gsp_boot.py              bounded real-firmware run + session + rung
```

`Machine` consults devices after RAM/UART and before the device map/lenient
fallback; the aperture translator (`dma.py`) is consulted first so
FBGPA/SYSGPA memory accesses resolve to RAM. Overlapping device windows
resolve last-registered-first, and a window that does not model an access
defers to the next matching window (safe fallback), so a narrow overlay can
serve some offsets without hiding the wider device. `Machine.device_state()`
and the `greeneye-sim-devices/1` snapshot expose all device state as
serialisable data (snapshot/restore support is additive and not yet wired to
moments).

## 3. Modeled inventory

Offsets are relative to each block base. `RW` semantics are storage unless
noted; every unlisted offset is unhandled and logged.

| Block | Window(s) (PRIV unless noted) | Modeled registers | Evidence |
|---|---|---|---|
| PMC | `+0x0` (size 0x1000) | `BOOT_42` @0xA00: ARCHITECTURE 28:24, IMPLEMENTATION 23:20, MAJOR 19:16, MINOR 15:12, MINOR_EXT 11:8, CHIP_ID 28:20 (TU104 = 0x164), read-only | header + firmware use + observed (first MMIO) |
| Falcon | `+0x110000`, alias `0x300000000` | `IRQSSET` 0x000 (`irq_status \|=`), `IRQSCLR` 0x004 (`&= ~`), `IRQSTAT` 0x008 (read), `MAILBOX0/1` 0x040/0x044, `OS` 0x080, `DEBUGINFO` 0x094, `CPUCTL` 0x100, `BOOTVEC` 0x104, `DMACTL` 0x10c, `DMATRFBASE` 0x110, `DMATRFMOFFS` 0x114, `DMATRFCMD` 0x118 (transfer on write), `DMATRFFBOFFS` 0x11c, `DMATRFBASE1` 0x128, `FBIF_TRANSCFG(0..7)` 0x600, `FBIF_CTL` 0x624 | header + firmware use + observed |
| RISC-V local | `+0x111000`, alias `0x300001000` | `IRQMSET` 0x2ac, `IRQMCLR` 0x2b0, `IRQMASK` 0x2b4 (read), `IRQDEST` 0x2b8, `IRQTYPE` 0x2bc, `TRACECTL` 0x344, `TRACE_RDIDX` 0x348, `TRACE_WTIDX` 0x34c, `PRIV_ERR_STAT` 0x360, `PRIV_ERR_INFO` 0x364 (read), `PRIV_ERR_ADDR` 0x368 (read), `HUB_ERR_STAT` 0x36c | header + observed |
| PTIMER | `+0x9000` | `TIME_0` aperture 0x9400 / block `+0x400` (NSEC 31:5), `TIME_1` aperture 0x9410 / block `+0x410` (NSEC 28:0); value = instruction count × `ns_per_insn` (**modeled**, not calibrated) | header + **modeled** time |
| WPR2 | `+0x1FA000` | `WPR2_ADDR_LO` 0x1FA824, `WPR2_ADDR_HI` 0x1FA828 (4 KiB alignment; HI points at the last 128 KiB block) | header + firmware use |
| CSB/TRANSCOM | profile-declared | none by default; a profile may declare individual registers with width/value and `rw`/`ro`/`wo`/`w1c`/`set`/`clear` semantics | none yet (B4 landing point) |
| PMU | profile-declared | none; the stub records accesses and returns unhandled | none yet |
| DMA seam | FBGPA/SYSGPA (profile) | GPU-physical → RAM windows for falcon DMA and aperture loads/stores; unmapped transfers are refused and recorded | address-map header + firmware use |

Falcon DMA follows the header field semantics: `size = 1 << (SIZE+2)`,
`IMEM`/`DMEM` aperture select, `WRITE` direction, address
`((BASE1<<32 | BASE) << 8) + FBOFFS`, `IDLE` set on success and `ERROR` on a
refused transfer. Which FB/SYS aperture a DMA address targets (the
`FBIF_TRANSCFG.TARGET` decode) is **not proven yet** and is listed in §6.

### 3.1 Boot shim (declared assumptions)

The firmware's `_start` consumes boot arguments the real SEC2 booter/host
writes; the simulator reconstructs them from the documented structure layout
and records each as an assumption in `session.json.boot_shim.assumptions`:

* `NV_RISCV_BOOT_PARAMS` at a RAM address (bootType `NVRM`, size 120,
  version 1, core-dump buffer, one `WPRM` libos init arg);
* a `GspFwWprMeta` (magic/revision/verified and a self-consistent FB layout);
* a `libos_bootstrap_args_t` — six `u64` fields (IMEM and DMEM
  `base`/`size`/`bs`) the real bootloader builds from its TCM configuration
  and passes in `a0`; the M-mode TCM configuration is declared in the
  profile (offsets 0, 64 KiB windows).  This replaces the earlier
  raw-image mirror at the DMEM aperture: with the XMPU model (§3.2) the
  resident-section copy reads its real backing and no image mirror is needed;
* `a0`–`a5` register arguments (a0 = bootstrap-args pointer; the rest are
  declared assumptions the boot path only uses where its own computation is
  not self-sufficient).

The DEBUGINFO **host-consume** behaviour is also a shim: the firmware writes a
boot-stage marker and polls bits 22:20 until they clear, and no self-clearing
path exists in the firmware, so the host side is modelled as consuming the
stage marker on read. The device never changes a read value except for this
documented shim, and the shim is profile-enabled and session-recorded.

### 3.2 CPU protection unit (XMPU) — core model, `sim/mpu.py`

The GSP core boots in bare mode and then enables a small protection unit
through M-mode CSRs; the firmware programs entries for its code/data ranges
and, during init, for a scratch window it copies resident sections through.
Evidence kind: **hardware CSR/field header + firmware use + observed access
sequence** (the 570.144 bootstrap writes are visible in any run's device/CSR
trace). Modelled CSRs:

| CSR | value | semantics |
|---|---|---|
| `MMPUIDX` (0x7C8) | entry index | INDEX field 5:0 (64 entries) |
| `MMPUVA` (0x7C9) | virtual base | BASE 63:12, `VLD` bit 0 |
| `MMPUPA` (0x7CA) | physical base | BASE 63:12 |
| `MMPURNG` (0x7CB) | range (a size) | RANGE 63:12 |
| `MMPUATTR` (0x7CC) | attributes | recorded, not enforced |

Translation is active only when `mstatus.VM == NVMPU` (`0x1E`; field bits
28:24); lookup is lowest-index-first (the firmware's own bootstrap comment
documents the precedence). An entry maps `addr` to `pa + (addr - va_base)`
when `va_base <= addr < va_base + range`. The model applies to instruction
fetch, loads, stores and atomics; permissions/cache attributes are recorded
but not enforced, and **no match is treated as identity** (more lenient than
silicon) because the simulator keeps local memory flat and the boot path's
mappings are self-consistent. `read_mem`/`write_mem` (debugger surface)
remain raw and untranslated.

Evidence in the session: `session.json.mpu` carries the enabled flag, entry
table and `mstatus`. The model removes the B2 ceiling: with the correct
bootstrap args and the scratch mapping, the resident-section copy reads the
in-place image and the run continues (no DMEM image mirror, no faked copy).

### 3.3 libos syscall surface — service model, `sim/libos.py`

The application is a libos task that requests kernel services with `ecall`
(the syscall number in `t0`). The native machine stops on `ecall` unless a
handler is installed, so the boot runner attaches a deterministic service
model that:

* records every request (number, name, arguments, pc, instruction count) in
  `session.json.libos`;
* acknowledges only no-ops and modelled services — task yield, cache
  invalidation, external-interrupt arming, profiler enable/query, the
  modeled timer read, DMA bounce-buffer registration (`TCM` region),
  inverted-pagetable registration, and DMA copy/flush (an in-RAM copy in the
  flat model: the real kernel drives the falcon DMA through TCM, the copy
  effect is identical and is not faked — both sides must resolve or the run
  stops);
* **never fakes waits**: `processor_suspend`, `task_port_send_recv_wait`,
  `task_panic` and every unimplemented syscall stop the run with `R_ECALL`
  and are reported in `session.json.libos.stopped`.

Task switching, interrupt delivery, pagination, partition switch and memory
queries are not modelled (force-stopped, not invented). The B3 result is
exactly this stop: the message-loop task blocks in `task_port_send_recv_wait`
with `armed_mask=0xFF`.

## 4. Boot ladder results (observed, 2026-10-03)

| Rung | Claim | Evidence |
|---|---|---|
| **B0** | flat image loads; first MMIO is the unmodelled PMC `BOOT_42` read at `0x2000_0000_0000_0A00` | `tests/test_sim_devices.py` (B0 classification) |
| **B1** | device model serves the whole boot path: **0 unknown MMIO, 0 unhandled in windows**, deterministic 2M-instruction run stopping at the boot-halt/report loop (`0x4010928`) | `run_boot(use_shim=False)`; sessions `dumps/gsp-boot-b1-run1`, `dumps/gsp-boot-b1-run2`; test `test_no_shim_b1_device_model_serves_boot` |
| **B2** | with the shim, the firmware passes the chip gate, XMPU setup, the bootstrap-args consumer and its **relocation copy** (`0x4007B7C`); the XMPU model resolves the copy's real backing and the run continues into libos init | sessions `dumps/gsp-boot-b2-run1`, `dumps/gsp-boot-b2-run2`; test `test_shim_reaches_relocation_plus_mmu` |
| **B3** | libos init completes (TCM registration `0x5B22000`/`0x1000`, pagetable registration, DMA flush, external-interrupt arming `0xFF`) and the message-loop task blocks in the port wait | sessions `dumps/gsp-boot-b3-run1`, `dumps/gsp-boot-b3-run2`; test `test_shim_reaches_message_loop_b3` |

Reproduction (read-only; no hardware):

```bash
cd open-iov/debug/risc-v-gsp-rm-vm
python3 -m sim.gsp_boot --instructions 2000000 --record dumps/gsp-boot-b3-run1
python3 -m unittest tests.test_sim_devices tests.test_mpu -v
```

Two-run determinism is asserted by `test_two_runs_identical` and was checked
at the recorded B3 sessions: identical instruction count (474 043), stop
reason/PC (`ecall @ 0x4018038`, syscall
`task_port_send_recv_wait`), device-state SHA-256 (`5b3cc7e4…`) and register
file. The B1 no-shim run is likewise identical across runs (2 000 000
instructions, budget stop at `0x4010928`, device-state SHA-256 `88eb07b7…`).

## 5. Session evidence

Each `run_boot` invocation writes a `greeneye-session/1` directory with:

* `session.json` — firmware SHA-256, profile name, load layout, rung,
  milestones, stop reason/PC, unknown-MMIO counts, device-state SHA-256,
  device-access counts, the full boot-shim assumption list, the XMPU state
  (`mpu`: enabled, entries, mstatus) and the libos service log (`libos`:
  calls, counts, TCM/pagetable registrations, the stopping request);
* `blobs/device-state.json` — the `greeneye-sim-devices/1` snapshot of every
  device (registers, IRQ state, DMA windows/counters, shim flags);
* `events.jsonl` — the normal session event stream (`gsp_boot` note).

## 6. Unknowns (explicitly not modeled / not verified)

1. **CSB/TRANSCOM register semantics.** No message-window poll has been
   observed yet, so no register is modeled. The 570.144 firmware blocks in
   the message-loop port wait before any CSB access; B4 waits for the first
   host-traffic-triggered poll; the `csb.py` seam and profile register
   declarations are in place.
2. **Libos services.** Task switching, interrupt delivery, pagination,
   partition switch and memory queries are not modelled: the service model
   records and force-stops on them (never invents progress). DMA copies are
   modelled as in-RAM copies in the flat memory model.
3. **PMU.** No PMU register access observed; stub only.
4. **FWSEC state machine.** Only the WPR2 address pair is modeled; FWSEC
   execution is not.
5. **DMA aperture selection.** `FBIF_TRANSCFG.TARGET`/`MEM_TYPE` decode is
   not proven; only the profile's DMA windows decide what an address means.
6. **Interrupt delivery.** Falcon/RISC-V IRQ state is aggregated and
   serialisable, but mstatus/mie/mip/mtvec trap entry and interrupt injection
   are not modelled (the firmware arms external interrupts with mask `0xFF`
   and then waits forever in the flat model).
7. **PTIMER calibration.** Values are modeled from the instruction count with
   a placeholder `ns_per_insn`; no firmware PTIMER read has been observed and
   no timing claim is made.
8. **XMPU enforcement.** Translation, VLD gating, mstatus enable and
   lowest-index precedence are modelled; permissions, cache/coherence
   attributes and WPR IDs are recorded but not enforced, and an unmatched
   access passes through as identity (lenient by design, listed here).

Nothing in this page is a silicon-accuracy claim; `06-ACCURACY.md` fidelity
levels apply (L0/L1 modelled, L2 modelled-not-calibrated, L3 partial and
listed above).

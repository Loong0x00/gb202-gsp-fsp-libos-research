# B8 shared-window recovery and remaining copy-service boundary — 2026-10-28

> Later update: `B8_STATUS_BREAKTHROUGH_20261028.md` supersedes the remaining-copy-service interpretation. A strict ret0-controlled experiment later proved that the real B8 backend can return zero and reach the success-only second callback. No general B8 data read/write primitive is claimed.

## Verified

- Actual shared VA comes from the runtime initialization structure at `0x041d00f8`: `0x0febe00000`. The historical `0x20800000` is not valid in the current enlarged-queue configuration.
- The shared page table at that VA contains the expected current QPA0 value, proving the mapping exists and is readable.
- ARG at metadata+0x800 is writable/readable, and `ARG+0x78` returns `0x0febe00000` when the full map is present.
- B8 at `0x100cf9c` does execute and reaches the page-array lookup at `0x100d00a`. Invalid page-table pointers deliberately fault there, so callback absence is not an explanation.
- Direct store to the QOUT window faults with a store page fault; it is not an ordinary writable buffer.

## Not established

- No cookie was copied into scratch and no output cookie appeared in QRESULT. The physical copy service, not the page-table lookup, is the remaining failure point.
- No official `DMEM_READ` API exists. The official `DMEM_LOG commandCode=0x06` probe returned no response on 610.57 or 615.
- Initial interpretation of the pure-QEMU stop at `0x9300395e` as a backend error was incorrect. Correct program-header-based disassembly shows that this is the normal LibOS trap entry (`csrw 0x5c0,tp`). After emulating that custom CSR and the matching read in GDB, execution proceeded into the copy service and an SBI memory-grant request. The lab then rejected that unmodeled grant. QEMU therefore proves entry into the physical-copy service, not copy success or failure.
- `gsp_log_ga10x.bin` is not shipped in this driver package, so the backend's detailed firmware log is unavailable.

## Consequence

Do not keep changing VA, page-table pointers, AES parameters, or token candidates. The shared-window description is already verified. The remaining question is whether the real physical-copy helper returns zero; the previous QEMU stop is not evidence of a real hardware copy failure. A paired hardware status experiment must use the same map and an objective success-only second callback, with a `ret0` positive control.

## Corrected kernel extraction note

`kernel_gb20x_REAL.elf` has a LOAD segment at virtual `0xffffffff92fff000`, file offset zero. Consequently `0x93000000` corresponds to file offset `0x1000`, not zero. Earlier raw `dd` disassembly that omitted this page was mislabeled. Corrected files are `libos_error_9300395e.correct.objdump.txt` and `libos_t020_handler_93002852.correct.objdump.txt`.

## Environment

- Host NVIDIA/GDM restored.
- No research VM is active.
- No `FSP_RUN` input was used.

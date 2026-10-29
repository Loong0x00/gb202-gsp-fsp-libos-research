# B8 callback status breakthrough and evidence corrections — 2026-10-28

## Verified result: objective B8 success status

A paired single-message experiment used the same minimal stream layout, QOUT/ARG objects, heap self-links, and a success-only second callback:

- Positive control: `B8=0x0100dcba` (`ret0`) produced `sepc=stval=0xdeadbeee`, `scause=0xc`.
- Real backend: `B8=0x0100cf9c` produced the identical firmware exception.

At `0x1004d32`, the caller branches away unless B8 returns zero; the second callback at `0x1004d50` is reached only on the zero path. This is objective firmware-side evidence that the real B8 backend returned zero. It is stronger than host LARGE submission, a staged value, or an RPC timeout.

Evidence:

- `b8-status-ret0-minimal-dmesg.log`
- `b8-status-copy-minimal-dmesg.log`
- `b8-status-canary-qpte-dmesg.log`

## Direction and data-canary correction

The copy helper ABI is consistent with `(src,dst,len)`:

- `flags=1` at `0x1004d30` calls helper(PA, metadata+0x9c, 4), i.e. PA-to-local read. Its zero return and second callback do not imply a write to the host.
- `flags=0` at `0x1004c9c` calls helper(metadata+0x8c, PA, 4), i.e. local-to-PA write.

Therefore the earlier interpretation of the successful `flags=1` callback as a host-write canary was wrong. A QRESULT sentinel remained unchanged in that direction, as expected for a read. The reverse `flags=0` write attempt timed out and did not change the sentinel, so **no B8 host-write primitive is validated**.

## Firmware-side structure verification

The read gadget at `0x1020a30` jumps through `*(a1+0x168)`; target addresses must be biased by `-0x168`, and 64-bit alignment is required.

Verified with that ABI:

- `metadata+0x40 = 0x0febe3c100` (QOUT).
- `metadata+0x98` qword `0x0000003f00000000`, proving the staged source word when measured in isolation.
- `ARG+0x80 = 0x0fe4791910` (dedicated synthetic table).
- table entry 60 = a real QSTATE physical page (example run: `0x11a23d000`).
- The natural pages0 pointer read by the older qinfo experiment is `0x0fe4600098`. The later `0x80000000` value came from accidentally reading unrelated `0x04191808` and is not natural pages0.

A dedicated QPTE sentinel also works: `ret0` preserves host QRESULT `0xdeadbeef`; this validates the host readback control itself.

## What remains unproven

- No general B8 data read/write primitive is established.
- A two-message chain intended to read PA into metadata and then read it back with a second injected message did not produce firmware evidence. It ended with a later RPC timeout; two host LARGE submissions are not proof of two consumed messages.
- No AES known-answer operation, decryption oracle, `FSP_RUN` plaintext, or resource unlock is implied by the B8 status result.

## QEMU correction

`0x9300395e` is the normal LibOS trap entry, not a backend error log. The raw kernel ELF LOAD base is `0xffffffff92fff000`, so `0x93000000` is file offset `0x1000`. After emulating the custom CSR accesses, the lab reached an SBI memory-grant request that the model rejects. QEMU does not determine real B8 copy success or failure.

## Consequence for AES work

Use the second callback as an objective callback-return-status mechanism where applicable. Keep AES output on dedicated QPTE/QRESULT buffers; do not make a B8 host-write primitive a prerequisite for the AES KAT. The remaining AES blocker is still the SE0 backend mapping/access fault, not B8 callback transport.

/* SPDX-License-Identifier: GPL-2.0-or-later
 * The experimental feature must not change ordinary rv64 CPU semantics.
 */
.option norvc
.section .text
.global _start
_start:
    la t0, trap
    csrw mtvec, t0
    li t0, 0xf000000000000000
    csrw satp, t0
    csrr t1, satp
.ifdef NV_ENABLED
    bne t0, t1, fail
    csrr t0, 0x5ca
    bnez t0, fail
    j pass
.else
    bnez t1, fail
    csrr t0, 0x5ca
    j fail
.endif
trap:
.ifdef NV_ENABLED
    j fail
.else
    csrr t0, mcause
    li t1, 2
    bne t0, t1, fail
    j pass
.endif
pass:
    li t0, 0x100000
    li t1, 0x5555
    sw t1, 0(t0)
    j pass
fail:
    li t0, 0x100000
    li t1, 0x13333
    sw t1, 0(t0)
    j fail

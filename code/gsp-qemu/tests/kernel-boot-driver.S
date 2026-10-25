/* SPDX-License-Identifier: GPL-2.0-or-later
 * Subsystem fixture: enter the unchanged LibOS BOOT entry at its physical
 * load address. This is not FMC/BootROM authentication or a success shim.
 * Every unimplemented M-mode trap stops; no ecall is answered here.
 */
.option norvc
.section .text
.global _start
.global m_trap
_start:
    la t0, m_trap
    csrw mtvec, t0
    li t0, -1
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0
    li t0, 7
    csrw mcounteren, t0
    li a0, 0x30
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 3
    li a6, 0
    li a7, 0xa3000000
    li t0, 0x93000000
    csrw mepc, t0
    li t0, 0x800
    csrs mstatus, t0
    mret
m_trap:
    wfi
    j m_trap

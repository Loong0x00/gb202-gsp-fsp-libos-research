/* SPDX-License-Identifier: GPL-2.0-or-later
 * Standard RV64 execution oracle. This is NOT a replacement NVIDIA ROM.
 * Run only on QEMU virt's test-finisher platform, never as GSP firmware.
 */
.option rvc
.section .text
.global _start
_start:
    li s1, 1
    lui t0, 0x93000
    li t1, 0xffffffff93000000
    bne t0, t1, fail

    li s1, 2
    li t1, 0xffffffff00000000
    sext.w t0, t1
    bnez t0, fail

    li s1, 3
    li t1, 0x7fffffff
    li t2, 1
    addw t0, t1, t2
    li t3, 0xffffffff80000000
    bne t0, t3, fail

    li s1, 4
    csrr s2, sstatus
    li t0, 0x22
    csrc sstatus, t0
    li t0, 0x20
    csrs sstatus, t0
    li t0, 2
    csrs sstatus, t0
    csrr t0, sstatus
    andi t0, t0, 0x22
    li t1, 0x22
    bne t0, t1, fail
    csrw sstatus, s2

    li s1, 5
    li t1, -7
    li t2, 3
    div t0, t1, t2
    li t3, -2
    bne t0, t3, fail
    rem t0, t1, t2
    li t3, -1
    bne t0, t3, fail

    li s1, 6
    li t1, 0x8000000000000000
    li t2, -1
    div t0, t1, t2
    bne t0, t1, fail
    rem t0, t1, t2
    bnez t0, fail
    div t0, t1, zero
    li t3, -1
    bne t0, t3, fail

    li s1, 7
    la s0, signed_word
    c.lw a0, 0(s0)
    li t0, 0xffffffff80000000
    bne a0, t0, fail

    /* The platform test device exits QEMU with status 0. */
    li t0, 0x100000
    li t1, 0x5555
    sw t1, 0(t0)
1:  wfi
    j 1b
fail:
    li t0, 0x100000
    slli s1, s1, 16
    li t1, 0x3333
    or t1, t1, s1
    sw t1, 0(t0)
2:  wfi
    j 2b
.section .rodata
.balign 4
signed_word:
    .word 0x80000000

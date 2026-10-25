/* SPDX-License-Identifier: GPL-2.0-or-later
 * QEMU CPU/MPU subsystem regression. NOT BootROM/FMC or a LibOS shim.
 */
.option norvc
.equ SCODE, 0xffffffff90000000
.equ SDATA, 0xffffffffa0000000
.equ REMAP, 0xffffffffa1000000
.equ SUBPAGE, 0xffffffffa3000000
.equ UCODE, 0x10000000
.equ UDATA, 0x40000000

.macro WINDOW index, va, pa, length, attr
    li t0, \index
    csrw 0x5ca, t0
    li t0, \pa
    csrw 0x5cc, t0
    li t0, \length
    csrw 0x5ce, t0
    li t0, \attr
    csrw 0x5cf, t0
    li t0, (\va)|1
    csrw 0x5cb, t0
.endm
.macro EXPECT cause, address
    li s10, \cause
    li s11, \address
    li s9, 0
.endm
.macro CHECK
    beqz s9, s_fail
    li s10, 0
.endm

.section .text.boot,"ax"
.global _start
_start:
    la t0, m_trap
    csrw mtvec, t0
    li t0, -1
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0
    li t0, 7
    csrw mcounteren, t0
    WINDOW 0, SCODE, 0x80001000, 0x1000, 0x28
    WINDOW 1, SDATA, 0x80200000, 0x1000, 0x18
    WINDOW 2, UDATA, 0x80202000, 0x1000, 3
    WINDOW 3, UCODE, 0x80003000, 0x1000, 5
    WINDOW 4, REMAP, 0x80203000, 0x1000, 0x18
    WINDOW 127, SUBPAGE, 0x80205000, 0x400, 0x18
    li t0, 0xf000000000000000
    csrw satp, t0
    csrr t1, satp
    bne t0, t1, m_fail
    li t0, SCODE
    csrw mepc, t0
    li t0, 0x800
    csrs mstatus, t0
    li s10, 0
    mret
m_trap:
    beqz s10, m_fail
    csrr t3, mcause
    bne t3, s10, m_fail
    li t4, -1
    beq s11, t4, 1f
    csrr t3, mtval
    bne t3, s11, m_fail
1:  li t3, 8
    beq s10, t3, m_pass
    li s9, 1
    csrr t3, mepc
    li t4, 12
    beq s10, t4, 2f
    addi t3, t3, 4
    j 3f
2:  mv t3, ra
3:  csrw mepc, t3
    mret
m_pass:
    li t0, 0x100000
    li t1, 0x5555
    sw t1, 0(t0)
    j m_pass
m_fail:
    li t0, 0x100000
    slli t1, s1, 16
    li t2, 0x3333
    or t1, t1, t2
    sw t1, 0(t0)
    j m_fail

.section .text.s,"ax"
s_start:
    li s1, 1
    li t0, 127
    csrw 0x5ca, t0
    csrr t0, 0x5cb
    li t1, SUBPAGE|1
    bne t0, t1, s_fail
    csrr t0, 0x5cc
    li t1, 0x80205000
    bne t0, t1, s_fail
    csrr t0, 0x5ce
    li t1, 0x400
    bne t0, t1, s_fail

    li s1, 2
    li a0, SDATA
    li t0, 0x12345678
    sd t0, 0(a0)
    ld t1, 0(a0)
    bne t0, t1, s_fail

    li s1, 3
    EXPECT 15, SCODE
    li a0, SCODE
    sd zero, 0(a0)
    CHECK

    li s1, 4
    EXPECT 12, SDATA
    li a0, SDATA
    jalr ra, 0(a0)
    CHECK

    li s1, 5
    EXPECT 13, UDATA
    li a0, UDATA
    ld t0, 0(a0)
    CHECK

    li s1, 6
    li t0, 4
    csrw 0x5ca, t0
    li a0, REMAP
    ld t0, 0(a0)
    li t1, 0x1111
    bne t0, t1, s_fail
    li t0, 0x80204000
    csrw 0x5cc, t0
    ld t0, 0(a0)
    li t1, 0x2222
    bne t0, t1, s_fail

    li s1, 7
    li t0, 8
    csrw 0x5cf, t0
    EXPECT 15, REMAP
    sd zero, 0(a0)
    CHECK

    li s1, 8
    csrw 0x5cb, zero
    EXPECT 13, REMAP
    ld t0, 0(a0)
    CHECK

    li s1, 9
    li a0, SUBPAGE
    ld t0, 0(a0)
    li t1, 0x3333
    bne t0, t1, s_fail
    EXPECT 13, SUBPAGE+0x400
    li a0, SUBPAGE+0x400
    ld t0, 0(a0)
    CHECK

    li s1, 10
    EXPECT 2, -1
    li t0, 128
    csrw 0x5ca, t0
    CHECK

    li s1, 11
    EXPECT 2, -1
    csrr t0, 0x5cd
    CHECK

    li s1, 12
    WINDOW 20, REMAP, 0x80203000, 0x1000, 0x18
    li a0, REMAP
    ld t0, 0(a0) /* warm the dynamic translation */
    csrw 0x5d0, zero
    csrr t0, 0x5d1
    li t1, 0x100000
    and t0, t0, t1
    beqz t0, s_fail
    li t0, 0x1ff /* retain static slots while executing S-mode */
    csrw 0x5d1, t0
    li t0, 20
    csrw 0x5ca, t0
    csrr t0, 0x5cb
    andi t0, t0, 1
    bnez t0, s_fail
    EXPECT 13, REMAP
    ld t0, 0(a0)
    CHECK
    li t0, 1
    csrw 0x5d0, t0
    csrr t1, 0x5d0
    bne t0, t1, s_fail
    csrw 0x5d1, zero
    csrr t0, 0x5d1
    bnez t0, s_fail
    EXPECT 13, SUBPAGE
    li a0, SUBPAGE
    ld t0, 0(a0)
    CHECK

.ifdef OVERLAP_TEST
    /* A broad window and a narrower conflicting window share a target page.
     * Warm the outer portion first: this must not cache over the inner policy.
     */
    li s1, 18
    WINDOW 5, REMAP, 0x80204000, 0x1000, 0x18
    WINDOW 6, REMAP+0x400, 0x80204400, 0x400, 8
    li a0, REMAP
    ld t0, 0(a0)
.if OVERLAP_TEST == 1
    li a0, REMAP+0x400
    sd zero, 0(a0)
.else
    li a0, REMAP+0x3fc
    ld t0, 0(a0)
.endif
    j s_fail
.endif

    /* U-mode has its own permission bits, not S-mode's access rights. */
    csrw sstatus, zero
    li t0, UCODE
    csrw sepc, t0
    sret
s_fail:
    li s10, -1
    ecall
    j s_fail

.section .text.u,"ax"
u_start:
    li s1, 13
    li a0, UDATA
    li t0, 0x9876
    sd t0, 0(a0)
    ld t1, 0(a0)
    bne t0, t1, u_fail

    li s1, 14
    EXPECT 13, SDATA
    li a0, SDATA
    ld t0, 0(a0)
    beqz s9, u_fail
    li s10, 0

    li s1, 15
    EXPECT 15, SDATA
    sd zero, 0(a0)
    beqz s9, u_fail
    li s10, 0

    li s1, 16
    EXPECT 12, SCODE
    li a0, SCODE
    jalr ra, 0(a0)
    beqz s9, u_fail
    li s10, 0

    li s1, 17
    EXPECT 2, -1
    csrr t0, 0x5ca
    beqz s9, u_fail

    li s1, 0
    EXPECT 8, -1
    ecall
u_fail:
    li s10, -1
    ecall
    j u_fail

.section .data,"aw"
    .quad 0
    .org 0x2000
    .quad 0
    .org 0x3000
    .quad 0x1111
    .org 0x4000
    .quad 0x2222
    .org 0x5000
    .quad 0x3333

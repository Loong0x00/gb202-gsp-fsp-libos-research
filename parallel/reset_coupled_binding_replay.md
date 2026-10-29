# GB202 reset-coupled getter 绑定重放

日期：2026-07-21

## 结论先行

对固定 inner GSP ELF 的两次独立、有界离线重放得到同一结果：

```text
GB202 HalVarIdx 65 = group 2 / low 1
OBJGPU+0x668      = 0x0144d4e8
store             = 0x01b9d7ca
```

`0x0144d4e8` 是会读取对象状态、调用下层查询并检查两个 bit 的非平凡实现；
`0x019508c4` 才是直接返回 `NV_FALSE` 的默认短桩。此前“覆盖只包括 group 1 的
59/60/63，GB202 保留默认短桩”的解释是错误的：它只识别了 group-1 bitmap
`0x98000000`，漏掉了 group-2 bitmap **`0x303f`**。后者包含 low bit 1，正好覆盖
GB202/index 65。

这把“GB202 的 `+0x668` 具体绑定”从 `REPORT-ONLY` 升级为固定 artifact 上的
**V-STATIC**，但不把任何历史输出升级成当前运行状态。

## 样本与安全边界

```text
file   /tmp/gsp_inner_19f040_a.elf
size   82577496
sha256 bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47
```

本轮只读取本地 ELF，没有打开 `/dev/nvidia*`，没有运行 MODS/固件，没有访问
BAR/MMIO/PCI config/debugfs，也没有 reset、驱动、模块或显示操作。

持久化材料：

- `parallel/gsp_objgpu_668_replay.py`：带固定 size/hash 检查的有界重放器；
- `parallel/gsp_objgpu_668_replay.results.txt`：GB202 与正、负控制 index 的输出；
- `parallel/objgpu_668_independent_check.md`：第二套独立重放、原始字节和地址复算。

## 1. 漏掉的 group-2 选择

初始化器 `0x01b9c210` 从 `s11+0x48` 读取 chip index。index 65 第一次 dispatch
进入 group-2 block `0x01b9d076`。共同代码随后再次读取 index，并明确进入第二个
group-2 block：

```text
0x01b9c782: lhu   a2,0x48(s11)   # 65
0x01b9c788: srli  a0,a2,5        # group = 2
0x01b9c792: bne   a0,2,+8        # not taken
0x01b9c796: j     0x01b9d7e8
0x01b9d7e8: andi  a3,a2,0x1f     # low = 1
```

最终选择先按 `a0` 区分 group：

```text
group 1: 0x01b9d970..0x01b9d978 -> bitmap 0x98000000
group 2: 0x01b9d9a6..0x01b9d9b0 -> bitmap 0x0000303f
```

对 GB202：

```text
(0x303f >> 1) & 1 = 1
```

于是公共收束点不跳向默认 store，而是形成并写入 override：

```text
0x01b9d7be: beqz  a4,0x01b9c89c  # not taken
0x01b9d7c2: auipc a4,0xff8b0
0x01b9d7c6: addi  a4,a4,-0x2da   # 0x0144d4e8
0x01b9d7ca: sd    a4,0x668(s11)
0x01b9d7ce: j     0x01b9c8a8
```

最后一跳落在默认 store 的下一条指令，明确绕过：

```text
0x01b9c89c..0x01b9c8a4 -> s11+0x668 = 0x019508c4
0x01b9c8a8              -> common continuation
```

因此不是“先写 override、稍后又被 default 覆盖”。

## 2. 重放完整性边界

主重放器从已经选定的 group-2 入口开始，使用 index 65、group 2 和符号对象地址；
它只解释该路径出现的整数运算、分支、直接跳转、对象 index 读取和 store。目标前
唯一外部 call `0x01b9c77e -> 0x0196495c` 被当作 opaque returning call；随后：

1. 构造器重新从 `s11+0x48` 读取 index；
2. 重新计算 group 和 low index；
3. 重放器清除全部 caller-saved 寄存器，任何未重新定义的使用都会立即报错；
4. 本次没有 unknown-dependent branch。

因此 opaque call 的寄存器副作用不会被暗中假定为零。即使该 helper 曾更早写过
同一 slot，后面的 `0x01b9d7ca` 也会覆盖它。

正、负控制结果与 bitmap 精确一致：

| index / low | `0x303f` bit | 最终 `+0x668` |
|---|---:|---:|
| 64 / 0 | 1 | `0x0144d4e8` |
| **65 / 1 (GB202)** | **1** | **`0x0144d4e8`** |
| 70 / 6 | 0 | `0x019508c4` |
| 76 / 12 | 1 | `0x0144d4e8` |
| 78 / 14 | 0 | `0x019508c4` |

独立重放从更早的 `0x01b9c330` 开始，共执行 698 条本地指令，也得到同一 store，
并用原始字节独立复算 `auipc+addi` 地址。

## 3. 两个候选函数不是同一种行为

默认 `0x019508c4` 的有效行为是：

```text
a0 = 0
return
```

GB202 实际绑定的 `0x0144d4e8` 则会：

1. 检查对象 `+0xb68` 的 `isVirtual` guard；非零时返回 false；
2. guard 为零时调用 unique-device-entry helper，请求 type `0x2a`；
3. 从 entry `+0x10` 取得 `devicePriBase`，以对象 `+0xb98` 的 PRI aperture
   pointer 读取 `devicePriBase+0x40.bit0` 与 `+0x44.bit0`；
4. 对两位做短路 OR；错误路径另有日志/false 处理。

相邻固定 GSP setter 和公开 reset-type 枚举已经把三项校准为：

```text
+0x40 = fuse coupling
+0x44 = boot coupling
+0x48 = base coupling
```

因此它是**有条件的、状态感知 getter**，而不是恒假桩；更精确的直接语义是
`fuse || boot`，函数没有读取 base 的 `+0x48`。guard、device-info 结构和三元组
证据见 `parallel/reset_getter_guard_provenance.md`；逐指令地址公式见
`parallel/reset_getter_internal_fields.md`。

## 4. 对历史 control 和 reset 时序的影响

GSP handler `0x0142c510` 确实从 `OBJGPU+0x668` 取方法并把返回字节写入公开
`NV2080_CTRL_CMD_GPU_IS_RESET_COUPLED` 输出。修正绑定后：

- 不能再说该 control 在 GB202 上“必然恒返 0、完全没有状态判别力”；
- 项目叙述的历史 `is_reset_coupled=0` 若真实，可能描述了那个时刻的 fuse/boot
  aggregate 结果，但 stdout、同时间健康快照与 lookup 状态均未留档，所以仍
  只能是 `REPORT-ONLY`；
- 它不是当前值，不能区分 fuse/boot，也没有直接读取 base；因此单靠一个 0 既
  不能排除 base-only，也不能证明将来一定选择 hot reset；
- direct-shadow 成功尾声仍固定使用 request 2，并继承当时的三项 coupling 输入。

后续审计已排除可见 GSP 软件镜像：selector 8 只写/读回 `+0x48`，type-8 reset
arm 也不追加 selector 4/5；完整证据见 `parallel/base_coupling_visibility.md`。
寄存器硬件副作用、reset sequencer 或 FSP/GFW 的隐式级联仍为 `UNKNOWN`。故这项
修正提高了未来只读 query 的解释价值，却没有消除 reset 类型、许可、latch/raw
生命周期或物理 L2 健康方面的未知项，也不构成执行解锁的许可。

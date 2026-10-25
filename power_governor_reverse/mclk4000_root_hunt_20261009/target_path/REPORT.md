# GB202 R570.215 MCLK target → object+0x68 → command-0 DATA / metadata

范围：只读静态检查匹配 runtime PMU ELF。未运行 GPU、MODS 或固件；未打开/保存/改写旧 Ghidra project/database。本次新产物仅在此 `target_path/` 目录。指令证据见同目录 `instructions.asm`。

ELF：`power_governor_reverse/gb202_r570215_runtime_pmu.elf`  
SHA-256：`2eef42f0b434990d2c9669124199a912e8e16d8480d1c9a74d46d75e1575b93b`

## 结论

- 这条 MCLK vtable 路径把传入的 32-bit 请求原样写入 object `+0x68`（仅在更新判定通过时），worker `0x2063469e` 再把该字段原样拷到 command-0 输入 DATA。此链路中没有对该 DATA 做 MHz 换算、除法、rounding、档位取整或 16-bit 截断。
- 正常 worker 路径的 command-0 metadata 输入来自清零后的临时缓冲第二个 dword；因此本路径的高 16-bit metadata 恒为 `0`，不随 `18,000,000 → 18,001,000` 改变。wrapper 通用接口会把第二 dword 截成低 16 位，但这里该 dword 已被 `memset` 成零。
- 两个示例值的 DATA 若确实进入发送分支，分别是 `0x0112A880` 和 `0x0112AC68`。它们只使 DATA 相差 `0x3E8` (1000)；command-0、metadata、sequence 构造及 DATA/CMD 相等时的 bit-15 防碰撞逻辑相同。sequence 是运行期递增字节，静态文件不能给出其实值。
- **是否进入发送分支不是单看这 1000 的差值。** `0x20633630` 先按全局停用门、override bit 和两个容差窗口决定 object `+0x30` 与 `+0x68`。object `+0x30 == 1` 时 worker 跳过 command；通常写成 2 才继续。没有运行态的 selected reference、previous target、两个 gate 值，不能声称这两种输入实际发送或不会发送。
- 没有从固件静态数据推导出本次运行时的真实 DATA、真实 sequence/CMD 字或端点接收结果；下列 payload 只是在给定输入条件下的指令级演算，不是运行记录。

## 指令级链路

地址均为该 ELF 内地址；详细原始指令在 `instructions.asm`。

### 1. 请求 → object+0x68，以及 object+0x30 判定

`0x20633630`：

- `0x20633658: lw a4,0(a1)` 取 32-bit 请求。
- 若全局 byte `0x20013ed8+0x42` 非零，`0x20633646–0x20633648` 直接写 `sb 1,0x30(a0)` 并返回，不更新 `+0x68`。
- 否则读全局 word `0x200142b0`；若 bit `0x10` 置位，分支直接到 `0x20633690`，跳过两项容差比较。
- 正常比较所用 reference 是 object 内 `((*(u8*)0x202a2860 + 1) * 16)` 偏移处的 dword；旧 target 是 object `+0x68`。比较指令为 `addiw +0x7d0` / `addiw -0x7d0`（±2000）以及 `addiw +0x1f4` / `addiw -0x1f4`（±500），配合 unsigned `bgeu`。
- 只有请求同时落在 reference ±2000 窗外、且落在旧 target ±500 窗外，或 bit `0x10` 强制绕过时，才在 `0x20633690–0x20633696` 写 `state=2` 和 `object+0x68=request`。其他情况写 `state=1`，旧 `+0x68` 保留。
- 初始化函数 `0x20632620` 将现有 `+0x68` 复制到一条 range/reference 记录；若为 0，则以全局 `0x200142c8` 初始化 `+0x68` 和该记录。因此比较基准是运行态对象/全局内容，不能从 ELF 单独代入为 14,001,000 或 18,000,000。

等价伪代码（正频率范围内；保留指令中的边界方向）：

```c
if (global_disable_byte) {
    obj[0x30] = 1;
    return;
}
uint32_t req = *(uint32_t *)request;
uint32_t ref = *(uint32_t *)(obj + 16 * (domain_index + 1));
uint32_t old = *(uint32_t *)(obj + 0x68);
bool outside_ref = req >= ref + 2000 || req < ref - 2000;
bool outside_old = req >= old + 500  || req < old - 500;
if ((global_flags & 0x10) || (outside_ref && outside_old)) {
    obj[0x30] = 2;
    *(uint32_t *)(obj + 0x68) = req;
} else {
    obj[0x30] = 1;
}
```

这些不等式来自 `addiw` 后 unsigned branch；对本例约 18M 的值没有有符号边界/整数回绕歧义。上界包含、下界不包含：例如 reference `R` 时，`req == R+2000` 会通过上侧，`req == R-2000` 不会通过下侧。

### 2. object+0x30 决定 worker 是否发 command

`0x2063469e` 开始 `lbu` object `+0x30`：0 或大于 3 走断言；值为 1 则从 `0x206346e4` 跳到函数收尾，不调用 wrapper；值 2（此 setter 的正常更新值）进入发送段。值 3 也会通过 worker 状态门，但本 setter 未产生该值。

发送段先 `memset(local_60,0,12)`，再执行 `lw 0x68(s1)` / `sw ..., -0x60(s0)`：即 `local_60[0] = object[0x68]`。随后调用 `0x206358ca(local_60, &local_3c, auStack_40)`。所以 DATA 来自保存后的最终 object target；这里没有将 target 加回 relation/base 或缩放。

### 3. wrapper 与 primitive 中 DATA、metadata 的确切形成

`0x206358ca` 将输入结构地址保存在 `s2`，先调用 `0x2063c3e8`；该 helper 指令没有读取/改写原 `s2` 指向的数据。随后：

- `0x206358f8: lw a4,0(s2)` 取 DATA；`sw a4,-0x4c(s0)` 暂存。
- `0x206358fc: lw a5,4(s2)` 取第二 dword；`sh a5,-0x4e(s0)` 截成 16-bit halfword。
- `0x2063590e–0x2063591c` 调 `0x205d19ce`：`a0=0` (command 0)，`a1=&halfword`，`a2=&DATA`，`a3=0x17318` (95,000)，`a4=0`。

在当前 MCLK worker，`local_60` 的前 12 byte 刚被清零，只有 dword 0 随后写成 object `+0x68`；故 wrapper 的输入 `lw 4(s2)` 为 0。另一个已清零的 `local_50` 是 wrapper 的输出 metadata 缓冲，不是这个输入 halfword。

primitive `0x205d19ce` 的相关指令：

- `0x205d1a06: lhu 0(s4)` 读取 metadata halfword；`0x205d1a50: slliw ...,0x10` 将其放到 CMD 高 16 位。
- `0x205d1a0a: lw 0(s3)` 读取 32-bit DATA。
- `0x205d1a3a–0x205d1a58` 形成 `CMD = (uint32_t)H<<16 | (cmd<<8) | seq8`；command 为 0，`seq8=(counter+1)&0xff`。
- `0x205d1a5a` 比较 DATA 与 CMD；只有全 32-bit 相等才在 `0x205d1a5e–0x205d1a62` 对 CMD OR `0x8000`。本 MCLK 路径 H=0，CMD 仅含 8-bit sequence；两个示例 DATA 均大于 `0xffff`，故不会触发该相等/bit-15 分支。
- `0x205d1a64–0x205d1a76` 先将 DATA、再将 CMD 交给 32-bit store helper `0x205d496a`。该 helper 的 store 是 `sw`；未对 DATA 取低 16 位。

通用 wrapper 若由别处调用且第二 dword 不为零，则 metadata 为 `(uint16_t)input_dword1`，CMD 高 16 位精确保留该 halfword；本 MCLK worker 已将其清零，故不会随 target 数值变化。

## 两个目标值的可复核对照

按输入为 raw `uint32_t` target（其外部单位/标注采用 kHz 的解释来自既有接口链路；这里不做额外单位换算）：

| 假设请求 | hex / DATA word | 与 18,000,000 的差 | 本 MCLK 路径 H | CMD 高 16 位 |
|---:|---:|---:|---:|---:|
| 18,000,000 | `0x0112A880` | — | `0x0000` | `0x0000` |
| 18,001,000 | `0x0112AC68` | `+1000` (`0x3E8`) | `0x0000` | `0x0000` |

两者均无 target 量化/rounding；条件满足时分别从 `object+0x68` 原样写成 DATA。命令低 8-bit sequence 取决于运行时计数器，故不能给出“实际完整 CMD”。也不能把表格当作实际运行 payload。

**比较边界代入示例**（仅说明门控，不是声称运行态值）：若 reference=old=14,001,000，则两目标都分别超过 reference 上界阈值 2,000 和 old 上界阈值 500，且 disable 门关闭、无其他条件阻断时，两者都令 state=2，走同一 worker/wrapper/command-0 路径，DATA 只差 1000。若 reference=old=18,000,000，则两者都未超 reference ±2,000；第二个虽超过 old+500，AND 条件仍不成立，两者都置 state=1，worker 不发送。若 override bit `0x10` 置位，则只要 disable 门关闭，两者都会 state=2。

精确窗外条件可直接用于任意运行态值：

| req | reference 外窗 | old target 外窗 |
|---:|---|---|
| 18,000,000 | `ref <= 17,998,000` 或 `ref >= 18,002,001` | `old <= 17,999,500` 或 `old >= 18,000,501` |
| 18,001,000 | `ref <= 17,999,000` 或 `ref >= 18,003,001` | `old <= 18,000,500` 或 `old >= 18,001,501` |

因此，1000 的增量可能在 reference/old 恰处于这些边缘带时改变 state，但不存在固定的 “18,000,000 被接受、18,001,000 被量化/截断或在 command-0 中走另一条频率分支” 结论。只有在状态判定使两者均进入 worker 时，才可说发送路径相同。

## 证据、限制和未知

- 本轮读取了任务点名的 `gb202_r570215_runtime_mclk_solver.c`、`..._vtable.c`、`..._lock_wrappers.c`、`..._clock_range_selected.c` 及最新 follow-up `REPORT.md`；既有 MCLK vtable 导出将 setter/worker 对应到 slot `+0x08=0x20633630`、`+0x10=0x2063469e`。随后针对目标 ELF 直接用 `llvm-objdump` 重查，并将输出留在 `instructions.asm`。文件名为 `.c` 的旧证据实际上包含既有 Ghidra 导出/日志；没有再次运行 Ghidra，也没有打开其旧 DB。
- 没有观察某次调用时的 `request`、domain index、reference、旧 `+0x68`、global disable/override 值或 sequence；因此无法判定 18,000,000 / 18,001,000 的特定实例到底 state=1 还是 state=2，也不能报告实际写出的 payload/CMD。
- 下游消费者、DATA 的设备端语义、ACK/执行成功均不由此发送端静态代码确定。此任务只闭合软件侧的目标复制和 command 字段构造；不重述或推断旧故障原因。

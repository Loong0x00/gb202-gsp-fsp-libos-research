# MODS 570.151 `UseRmRegOps` / RM-ready 生命周期（有界静态审计）

## 范围与结论

本审计只读固定样本 `mods_audit/static/extracted_inner/mods` 与解码后的
`mods_audit/static/decoded/gpuargs.js`。没有执行 MODS，没有访问 GPU、MMIO、
`debugfs` 或任何设备节点，也没有启动 Ghidra。二进制检查限于已知函数窗口及
连续的 `GpuSubdevice` 实现窗口 `0x0dc0000..0x0e10000`；特殊地址表只从已知的
GB202 RegHal 压缩块文件偏移 `0x8fd61aa` 定点读取 16-byte header 和 29,724-byte
压缩 payload，没有扫描整个 ELF。

结论是：

1. **FACT：** `GpuSubdevice+0x19c2` 构造默认值为 0；构造尾只会把一个 JS
   boolean 配置一次性复制进该 byte。解码 JS 把对应用户开关暴露为
   `-use_rm_reg_ops` / `Gpu.UseRmRegOps`。
2. **FACT：** `GpuSubdevice+0x19c0` 构造为 0；正常 phase-0 初始化成功走到
   `0xe000a8` 后变为 1；正常 teardown 走到 `0xdd624a` 后恢复为 0。
3. **INFERENCE（正常产品流程）：** `ProgramSwFusePlan` 发生时对象已经完成
   phase-0 初始化，所以 `+0x19c0` 应为 1。该函数自身没有检查这一生命周期
   前提，因此对刻意的 pre-init/失败恢复调用仍是 **UNKNOWN**。
4. **INFERENCE（普通、未显式给 `-use_rm_reg_ops`、无地址 remap）：**
   `0x8234e0..0x8234fc` raw OPT、`0x820040` latch、`0x8200dc` / `0x8200f8`
   PLM 访问更可能走 mapped register aperture，而不是 `EXEC_REG_OPS`。
   显式启用该参数且 `+0x19c0==1` 时则确定走 `EXEC_REG_OPS`。
5. **高置信 default / UNKNOWN 边界：** 后续完整 setter-source 审计证明 remap
   tree 初始化为空，唯一 direct setter caller 是显式 `-reg_remap` 的 JS
   callback，随包参数没有该选项；因此 stock/default 流可按 identity 处理。
   任意一次未观察的真实命令行/动态注入仍无运行态证据，所以不能把“mapped”
   升级成所有调用环境下的无条件事实。

下文的 **FACT** 只表示固定指令、vtable、解码 JS 或定点解出的 GB202 表项直接
证明；**INFERENCE** 是正常生命周期的组合判断；**UNKNOWN** 是静态样本不能
决定的运行状态。

## 1. `+0x19c2`：构造默认值与配置 setter

### 1.1 构造默认值

基础 `GpuSubdevice` 构造函数从 `0xdf2af0` 开始。在相关尾部：

```text
0xdf3551  mov word ptr [rbx+0x19c0], 0  # 同时清 +0x19c0/+0x19c1
0xdf355a  mov byte ptr [rbx+0x19c2], 0
```

因此 `+0x19c2` 的对象级默认值是 0，`+0x19c0` 的初值也为 0。这是
**FACT**，不依赖 JS 或运行平台。

### 1.2 构造尾的一次性 boolean 复制

同一个构造函数尾部先在 `0xdf5788` 调通用 JS-property resolver
`0xbe40c0`；resolver 成功时分支到：

```text
0xdf59b5  mov rsi, [rbp-0x80]          # resolved JS value
0xdf59b9  lea rdx, [rbx+0x19c2]        # destination byte
0xdf59c3  call 0xbe3c00                # generic bool conversion/store
```

`0xbe3c00` 的最终 store 为：

```text
0xbe3c68  cmp dword ptr [rsp+4], 1
0xbe3c6d  sete byte ptr [r12]
```

所以该 setter 只有在转换后的 JS 整数恰为 1 时写 1；false/0 写 0。它是
**构造期配置复制**，不是 RM init 自动把 `+0x19c2` 打开的 setter。

解码 JS 的唯一同名参数定义为：

```js
// gpuargs.js:1704
AddArg("use_rm_reg_ops", FLAGT, "Gpu.UseRmRegOps", null, null,
       "Use RM regops control call for register access once RM is initialized");
```

- 参数名、属性名和 help 文本是 **FACT**；
- `+0x19c2` 的 backend 行为与该 help 完全一致，结合构造期 JS boolean 复制，将
  它识别为对象内 `UseRmRegOps` byte 是 **INFERENCE（高置信）**。固定 ELF 中
  resolver 使用的是运行期初始化的 JS atom，当前有界窗口没有静态明文 atom
  可以把属性字符串和该地址再做一次独立等号证明。

在 `0x0dc0000..0x0e10000` 的 exact-displacement 清单中，`+0x19c2` 只有：

- backend read/write gate：`0xdc6f7e`、`0xdc7546`；
- 一个 policy getter：`0xdd5290`；
- 构造清零与构造期 destination address：`0xdf355a`、`0xdf59b9`；
- 初始化尾的只读检查：`0xe01e6a`。

没有发现 post-construction 的直接 byte writer。这个负结果只覆盖上述 5 MiB
类实现窗口；是否存在窗口外通过别名指针写该 byte，严格说仍是 **UNKNOWN**。

## 2. `+0x19c0`：RM-ready phase 生命周期

### 2.1 置 1 的 phase-0 初始化

GB202 vtable `0x92c8500` 的 `+0x10` 固定为 `0xe009e0`，该 wrapper 清零
`esi` 后 tail-call `0xdffa80`。`0xe01df0` 在安装 RM device/subdevice 指针
`+0xf58/+0xf60` 后正是调用这个 `+0x10` slot。

`0xdffa80(..., phase=0)` 的关键状态机是：

```text
0xdffaa6  cmp byte ptr [rbp+0x19c0], 0
           jne -> log + return 2
0xdffab3..0xdffb71  per-subdevice preparation; error returns before transition
0xe000a8  mov byte ptr [rbp+0x19c0], 1
0xe000af  jmp 0xdffbc5             # continue RM setup
```

因此 **FACT** 是：phase 0 要求旧状态为 0，并在前置循环成功后将其置 1。
同一 helper 的 phase 1 分支在 `0xdffbb8` 要求该 byte 已为 1；否则
`0xe00080..0xe000a4` 记录错误并返回 2。`0xe009f0` 在 `0xe00a64` 调用的就是
phase 1。

注意置 1 位于整个大初始化 helper 的中部；其后仍有可能失败的 control 调用。
高层失败清理是否对每个异常出口都立即调用 teardown，本轮有界窗口没有证明，
所以“任意失败出口后一定立刻回到 0”是 **UNKNOWN**。

### 2.2 teardown 清零

GB202 vtable `+0x3f0` 固定为 `0xdd6350`：

```text
0xdd6350  xor esi, esi
0xdd6352  jmp 0xdd5d10
```

`0xdd5d10` 释放/撤销 RM 侧对象并在统一正常尾部执行：

```text
0xdd624a  mov byte ptr [rbx+0x19c0], 0
0xdd6251  mov byte ptr [rbx+0x0f54], 0
```

另一个 rebind/reinit 路径 `0xdd6360` 在 `0xdd64aa` 以参数 1 调同一 cleanup
helper，也汇合到上述清零尾部。因此正常生命周期为：

```text
constructor       phase-0 init                         teardown/rebind
+0x19c0 = 0  ->   +0x19c0 = 1  ---------------------> +0x19c0 = 0
```

对象最终 destructor 后该 byte 所在存储本身消亡；析构函数不需要再把它写 0。

### 2.3 `ProgramSwFusePlan` 发生时是哪一 phase

`SetSwFusesCore` 在 `0x14621f3` 先调用 programming dispatcher；成功之后才在
`0x146223c` 调 post-program callback，而 reset/reinitialize 链位于这个 callback
之后。`ProgramSwFusePlan` 的 bounded body 本身没有 `+0x19c0` writer。

由此可以严格分层：

- **FACT：** 若调用前已完成 `GpuSubdevice +0x10` phase-0 init，计划写入期间
  `+0x19c0` 保持 1；post-program reset 不会抢在 raw write/read 前清零它。
- **INFERENCE：** 普通 MODS 在已初始化 GB202 上从 `NewFuse.SetSwFuses` 进入时，
  正处于这个 `+0x19c0==1` phase。
- **UNKNOWN：** `ProgramSwFusePlan` 没有自带 lifecycle guard；刻意从 pre-init、
  partial-init 或异常恢复上下文调用时，固定函数不能保证该 byte 为 1。

## 3. ordinary register backend 的两个显式 transport

raw plan thunks 为：

```text
0x151ad00 -> GpuSubdevice vtable +0x238 (write)
0x151ad10 -> GpuSubdevice vtable +0x228 (read)
```

GB202 vtable 的相关固定项是：

```text
+0x220 = 0xdc6f70   low-level read
+0x228 = 0xdb68a0   domain/instance read wrapper
+0x230 = 0xdc74f0   low-level write
+0x238 = 0xdb5540   domain/instance write wrapper
```

### 3.1 `UseRmRegOps && RM-ready`

read 和 write 分别执行完全相同的首选 gate：

```text
0xdc6f7e / 0xdc7546  if (+0x19c2 == 0) fallback
0xdc6f89 / 0xdc754f  if (+0x19c0 == 0) fallback
```

两者均为 1 时，read 进入 `0xdc68d0`，write 进入 `0xdc73b0`；两个 helper
都构造 control ID `0x20800122` (`NV2080_CTRL_CMD_GPU_EXEC_REG_OPS`) 的单项
请求。read 返回 response `regValueLo` (`0xdc696b`)，write opcode byte 在
`0xdc740b` 置 1。这是 **FACT**。

### 3.2 mapped aperture

不走 RM helper 时，普通 direct 分支为：

```text
read  0xdc7022..0xdc702e:
    base = *(GpuSubdevice+0x128)->mappedBase
    value = *(uint32_t *)(base + translatedOffset)

write 0xdc7621..0xdc7642:
    base = *(GpuSubdevice+0x128)->mappedBase
    *(uint32_t *)(base + translatedOffset) = value
```

因此在显式 `UseRmRegOps` gate 未满足且没有命中特殊地址 policy 时，transport
就是 mapped aperture。这也是 **FACT**。

## 4. `+0x13d8/+0x13d9/+0xf54/+0xff0/+0xff8` 特殊地址 predicate

`UseRmRegOps` 不是唯一能够进入 RM helper 的条件。read fallback 还可在以下
条件下汇合到 `0xdc6f92`：

```text
GpuSubdevice+0x13d8 != 0
&& GB202 vtable +0xff0 (translatedOffset) != 0
&& GpuSubdevice+0x0f54 != 0
```

write fallback 在 `0xdc7590..0xdc7703` 有两条独立的特殊 policy 路径；任一路
命中后都还要求 `+0xf54 != 0`，才汇合到 `0xdc7558`：

```text
(GpuSubdevice+0x13d8 != 0
 && GB202 vtable +0xff0 (translatedOffset) != 0)
OR
(GpuSubdevice+0x13d9 != 0
 && GB202 vtable +0xff8 is not the constant-false stub
 && GB202 vtable +0xff8 (translatedOffset) != 0)
```

另外还有 vtable `+0x1000` policy 路径；它同样只有在 predicate true 且
`+0xf54 != 0` 时才进入 RM helper。

构造器 `0xdf31fb..0xdf322d` 从 rodata `0x923c848` 取得 `0x0101`，所以
`+0x13d8/+0x13d9` 的构造默认值均为 1。成功 RM setup 在 `0xdffc88` 把
`+0xf54` 置 1，teardown 在 `0xdd6251` 清零。GB202 `+0xff0` 固定为
`0x12516e0`；`+0xff8` 和 `+0x1000` 都固定绑定恒 false 的 `0xdb3f50`。
因此在 GB202 上，`+0x13d9/+0xff8` 第二路和 `+0x1000` 第三路对所有目标地址
都不可能命中；只需继续解析 `+0x13d8/+0xff0` 第一路的地址集合。

### 4.1 GB202 `+0xff0` 的静态区间

`0x12516e0` 先查 RegHal ID `0x12a90000`，取得 index 0 和最后一个 index，
把它们作为 inclusive lower/upper bound；若输入不在其中，再检查硬编码区间
`0x00400000..0x005fffff`（另受 chip predicate 控制）。

对已知 GB202 压缩表做定点解码得到：

```text
ID 0x12a90000:
  metadata extent = 12
  domain = 0x29
  offsets = 0x00, 0x04, ... 0x2c

ID 0x12e0c000 (domain 0x29 base selector):
  index 0 -> 0x0000cc00
  index 1 -> 0x0000ce00
```

GB202 vtable `+0x398 = 0xd70290` 恒返回 1，所以 `0x12516e0` 的 loop 只使用
instance/index 0。`0x1988910` 是 descriptor address resolver：它把 domain base
和 descriptor offset 相加后返回地址，不读取这些地址的寄存器内容。因此本卡
该 table-derived inclusive interval 是静态的：

```text
[0x0000cc00, 0x0000cc2c]
```

它不是“从 0xcc00/0xcc2c 运行时读取两个边界值”。这一区分是 **FACT**。

### 4.2 逐个核对 requested addresses

backend 在进入 predicate 前先经 `0xd99930` 做可选 exact-address remap。若采用
普通 identity translation，则：

| 输入 | `[0xcc00,0xcc2c]` | `[0x400000,0x5fffff]` | 特殊 predicate |
|---|---:|---:|---:|
| `0x820040` latch | 否 | 否 | false |
| `0x8200dc` OPT access PLM | 否 | 否 | false |
| `0x8200f8` latch PLM | 否 | 否 | false |
| `0x8234e0..0x8234fc` raw OPT array | 否 | 否 | false |

所以“动态表内容未知”不是剩余缺口：GB202 表本身已静态解出，identity 输入时
这些地址确定不命中。

剩余边界是 `0xd99930` 的进程全局 exact-address remap tree。其 root 为空时原样
返回输入；命中显式 key 时会用 node value 替换 offset。后续
`parallel/reg_remap_lifecycle.md` 已证明其静态初始化 root/size 均为 0，固定
executable 中 map setter 只有 `Gpu.RemapRegister` callback 一个 direct caller，
全部解码 JS 又只从显式 `-reg_remap` 参数调用它，随包参数没有该选项：

- **FACT：** identity / 无相应 remap 时，上述五类地址不命中特殊 predicate；
- **高置信 INFERENCE：** stock/default GB202 流没有把这些 raw/PLM 地址 remap 到
  `0xcc00..0xcc2c` 或 `0x400000..0x5fffff`；
- **UNKNOWN：** 任意自定义运行是否曾安装这样的 exact remap。没有运行态观测，
  也不能形式化排除外部动态模块或运行时算出的间接 caller。

## 5. 最终判定矩阵

| 条件/问题 | 判定 | 等级 |
|---|---|---|
| `+0x19c2` 构造默认值 | 0 | **FACT** |
| `+0x19c2` 自动随 RM init 置 1 | 不会；RM init 只读它 | **FACT（有界类窗口）** |
| `+0x19c2` 可由什么改变 | 构造期 JS boolean copy；解码用户开关为 `-use_rm_reg_ops` | **FACT + 高置信 INFERENCE（属性绑定）** |
| `+0x19c0` 构造默认值 | 0 | **FACT** |
| 正常 phase-0 init 后 | 1 | **FACT** |
| phase-1 前置条件 | 必须已经为 1 | **FACT** |
| 正常 teardown 后 | 0 | **FACT** |
| 正常 `ProgramSwFusePlan` 时 `+0x19c0` | 更可能为 1；post-program reset 在写入后 | **INFERENCE，顺序为 FACT** |
| `+0x19c2==1 && +0x19c0==1` | global `EXEC_REG_OPS` | **FACT** |
| 两者 gate 未满足、特殊 predicate false | mapped aperture load/store | **FACT** |
| requested raw/latch/PLM 地址命中特殊 predicate（identity） | 均不命中 | **FACT** |
| 普通无参数、无 remap 的 GB202 raw writer | mapped aperture 更可能 | **INFERENCE** |
| 显式 `-use_rm_reg_ops` 且正常已初始化 | `EXEC_REG_OPS` | **FACT（给定条件）** |
| 任意实际运行究竟选哪一支 | 取决于命令行/JS 与 remap state | **UNKNOWN** |

最简洁的回答是：**正常 phase 下 `+0x19c0` 多半已经是 1，但这不会自动启用
RM regops；决定默认类别的是构造默认 0 的 `+0x19c2`。在未显式给
`-use_rm_reg_ops` 且没有非常规 exact-address remap 的普通 GB202 上，raw
floorsweep writer 更可能走 mapped aperture。**

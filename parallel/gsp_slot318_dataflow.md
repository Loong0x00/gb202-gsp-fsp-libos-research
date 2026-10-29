# GSP `base+0x318` 间接调用候选与 primary-fuse-base getter 的有限行为对齐

日期：2026-07-21

## 范围与安全边界

本轮只读取已提取的
`/tmp/gsp_inner_19f040_a.elf` first executable PT_LOAD
（VA `0x01000000..0x01e97000`，大小 `0xe97000`），没有访问 GPU、设备节点、
BAR/MMIO、PCI config 或 debugfs，没有执行 MODS/固件，也没有 reset、驱动或模块
操作。

为避免全量反汇编和高内存占用，扫描器先在 2-byte 边界上匹配 RV64
`ld reg, 0x318(base)` 的确切 32-bit 编码，再只保留 12 条指令内通过该
`reg` 做 `jalr/c.jalr` 的候选。随后只在每个候选附近做小窗口、有限状态的
符号追踪：

- 初始把返回寄存器 `a0` 标成“未知 base + 0”；
- 跟踪 move、`lui/addi/addiw/add/addw` 等形成的 base-relative offset；
- 条件分支两侧均入队；
- 单路径最多 180 条指令，地址窗口限定为 load 前 `0x200` 到后 `0x800`；
- 每个候选最多 2500 个抽象状态；
- 只报告相对 offset 的形成、以其为 memory base 的访问，或作为下一次调用参数。

这不是 whole-program proof；表驱动地址、未建模运算、跨 helper 的动态语义和
FSP 内部行为均不在证明范围。

## 1. 候选规模

精确 raw scan 得到：

```text
ld +0x318 encoding candidates: 271
nearby indirect-call sequences: 84
```

`+0x318` 是常见对象偏移，所以 84 条不能全部当作 `OBJGPU`，也不能先把裸
offset 全局命名为某个方法。必须用各 call-site 的 receiver 和调用后返回值用途
做正校准。

## 2. 正校准：四条调用行为与公开 610 方法语义逐项对齐

公开 610.43.03 host RM 源码直接证明：

- GB202 的 `gpuGetPrimaryFuseBaseAddr` 绑定
  `gpuGetPrimaryFuseBaseAddr_GH100`；
- getter 返回 `NV_FUSE0_PRI_BASE = 0x820000`；
- 本次在 GSP 候选中匹配到的公开 caller offset pattern 为 `+0x074c`、
  `+0x0c04`、`+0x3814`，以及 GH100-only sibling 的
  `+0x4e04/+0x4e08/+0x4e0c`；7 个公开 direct caller 的完整 offset 集还包括
  SEC2/GSP ucode-version 使用的 `0x4140/0x41c0 + 4*index`。

同一版本的公开 **host** `OBJGPU` 布局同时给出一个重要限制：按官方
Makefile 头文件配置编译 `offsetof`，`__gpuGetPrimaryFuseBaseAddr__` 位于
`+0x460`，而公开 `+0x318` 是 `__gpuGetSriovCaps__`。所以公开源码能校准
getter 的语义和已知 caller pattern，不能为 stripped GSP 的 `+0x318` 提供
ABI/字段名证明；私有 GSP 可能采用裁剪或重排的 generated layout。

详见 `parallel/public_fusebase_callers.md`。有限数据流扫描在 GSP 中精确恢复出：

```text
load 0x01357b0e -> call 0x01357b1c -> formed +0x3814 at 0x01357b24
load 0x014157a6 -> call 0x014157b4 -> formed +0x0c04 at 0x014157bc
load 0x018ae67a -> call 0x018ae688 -> formed +0x074c at 0x018ae68a
load 0x018af0c4 -> call 0x018af0ce -> formed +0x4e04/+0x4e08/+0x4e0c
```

前三组分别与 GB202-selected 的 ECC readout、display fuse，以及两个公开
debug-mode reader 共享的 `+0x074c` pattern 相符；第四组与公开 GH100-only
spare-bit sibling 相符，不能外推为 GB202 实际 runtime path。

**FACT：** 上述 offset 和调用后运算是当前 GSP 指令直接给出的。

**FACT（公开 host RM）：** GB202 的 C 层 getter 绑定 GH100 实现，后者返回
`0x820000`；公开 host `OBJGPU` 中该方法位于 `+0x460`，不是 `+0x318`。

**FACT（限本扫描的已访问路径）：** 扫描记录上述四个 `base+0x318` 间接
调用点的返回值随后形成公开 offset pattern；另行记录的构造追踪称一个候选
构造器把返回 `0x820000` 的函数写入相关 receiver 的 `+0x318`。

**INFERENCE（强）：** 若该构造器归属、receiver 传递和扫描结果均成立，这四个
调用点的相关字段很可能是私有 GSP 布局中的 primary-fuse-base getter。这里是
构造器/行为/源码语义对齐，不是公开 ABI 或 ELF symbol 对齐。

**UNKNOWN：** stripped GSP 的正式 receiver 类型、字段名和 symbol，以及其余
80 个 `+0x318` 间接调用候选分别属于哪些对象/方法。

## 3. 对权限／latch offset 的结果

下列 offset-to-semantic 标签来自另行归档的 RegHal/静态分析，不由本节公开
getter caller 源码建立；本扫描只把它们当作待匹配的数值 offset：

```text
+0x040  latch
+0x0d0  OPT/FS PLM
+0x0dc  L2 PLM
+0x0e0  security PLM sibling
+0x0f4  security PLM sibling
+0x0f8  latch access PLM
+0x13c  latch/encryption sibling register
```

结果：

```text
public calibration sequences matched: 4
permission-interest matches:          0
```

也就是说，在由近邻规则筛出的 84 个 `base+0x318` 间接调用候选中，扫描器已
访问的模型状态没有报告“候选调用返回值形成
`+0x40/d0/dc/e0/f4/f8/13c`”，也没有把这些相对地址作为下一 helper 的参数。

这是比单纯搜索 `0x008200f8` literal 多覆盖一层的**有限负证据**：它覆盖
“先经本次捕获的 `base+0x318` 间接调用取得 base，再在模型窗口内用简单运算
形成 `+0xf8`”这一具体编译形态；不能先假定 84 个候选全是 getter。

## 4. 不能越过的负证据边界

- 84 条候选中有 12 条在分支工作队列达到每候选 2500-state 上限；其已访问状态
  没有目标命中，但不能声称所有更深路径都被穷尽。
- `+0x318` 也是其他类可能使用的普通对象偏移；公开 host ABI 的 getter 甚至在
  `+0x460`。没有正校准行为的候选不能仅凭 slot 数字归类成 OBJGPU/getter。
- 符号执行只覆盖常见 move/加法形式；复杂位运算、表驱动 RegHal、通用 PRI
  helper 或跨调用的私有协议可能避开该模型。
- 当前可见 GSP 不是 FSP 指令体；HULK certificate payload 也能让目标地址只存在
  于签名数据/FSP policy 中。
- 因此 `permission-interest matches = 0` 的准确含义是：
  **当前 GSP first PT_LOAD 中，84 个近邻候选的已访问、已建模状态没有命中**，
  不是“任意 getter caller、setter、GB202/FSP/硬件绝不存在这些访问”。

## 结论

1. 公开 host 源码的 GB202 getter 绑定和返回值是 **FACT**；其公开对象字段位于
   `+0x460`，所以不能用公开 ABI 给 GSP `+0x318` 命名。
2. 四个经正校准的 GSP `base+0x318` 调用点与 getter 的关系是
   **INFERENCE（强）**，不是字段名或 ELF symbol FACT。
3. 在 84 个近邻候选的已访问、已建模状态中未发现 `f8/d0/dc` 等目标，是
   **FACT（限扫描域）**。
4. 该 0-match 只削弱“经本次捕获的候选调用取 base，再以简单运算形成
   `+0xf8`”这一具体实现假设；近邻筛选外、12 个截断候选、复杂位运算、
   表驱动 RegHal、跨 helper/跨段、直接 literal、FSP/HULK/动态 payload 仍为
   **UNKNOWN**。

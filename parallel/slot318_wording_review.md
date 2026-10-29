# `+0x318` 命名与 0-match 负证据措辞审计

日期：2026-07-21

## 范围

本次只阅读并交叉核对：

- `parallel/gsp_slot318_dataflow.md`；
- `parallel/public_fusebase_callers.md`；
- `L2_REENABLE_STATIC_FINDINGS.md:875-886`；
- `/usr/src/nvidia-610.43.03` 中的公开 generated HAL、C 源码和公开头文件。

没有读取或分析 GSP/MODS/固件二进制，没有访问 GPU、设备节点、BAR/MMIO、
PCI config 或 debugfs，也没有执行 reset、rebind、驱动或模块操作。本审计不重跑
`gsp_slot318_dataflow.md` 所述二进制扫描；涉及该扫描的数字只核对其文档内部的
证据等级和适用域。

## 总体判定

`public_fusebase_callers.md` 的核心公开源码事实经复核成立：GB202 的公开 host RM
getter 绑定、`0x820000` 返回值、21 个文本命中／8 个文件、7 个源码级直接 caller，
以及这些直接 caller 对 `+0x40/+0xd0/+0xdc/+0xf8` 的 0-match 都没有发现事实错误。

需要修订的是两类外推：

1. **`OBJGPU +0x318`／“ABI 对齐”写得过强。** 当前公开 610 host RM 布局中，
   `OBJGPU::__gpuGetPrimaryFuseBaseAddr__` 实际位于 `+0x460`，而 `+0x318` 是
   `OBJGPU::__gpuGetSriovCaps__`。因此公开源码能提供方法语义的正校准，不能提供
   stripped GSP `+0x318` 的 ABI/字段名证明。私有 GSP 可以采用裁剪或重排后的另一
   套 generated layout，所以这个差异也不能反向证明 GSP `+0x318` 一定不是 getter；
   准确等级是**强行为推断**，不是 FACT。
2. **`permission-interest matches = 0` 的局部边界写得基本正确，但结论句仍略宽。**
   0 只覆盖由“12 条指令内 `ld +0x318` 到间接调用”规则选出的 84 个候选、扫描器
   实际访问到的抽象状态和已建模的简单数据流；其中 12 个候选还达到状态上限。
   它削弱的是这一种具体实现形态，不是任意 getter caller 或任意无凭据 setter。

## 1. 公开 610 源码复核

### 1.1 可保留为 FACT 的内容

- `/usr/src/nvidia-610.43.03/version.mk` 给出的版本为 `610.43.03`。
- `generated/g_gpu_nvoc.c:2723-2733` 的 chip 分支明确包含 GB202，并执行：

  ```c
  pThis->__gpuGetPrimaryFuseBaseAddr__ = &gpuGetPrimaryFuseBaseAddr_GH100;
  ```

- `generated/g_gpu_nvoc.h:4319-4320` 的公开 dispatch 经 per-object 函数指针调用。
- `kern_gpu_gh100.c:647-653` 返回 `NV_FUSE0_PRI_BASE`；其实际包含的
  `published/hopper/gh100/hwproject.h:31` 把该常量定义为十进制 `8519680`，即
  `0x820000`。`published/blackwell/gb100/hwproject.h:31` 的同名常量也是
  `0x820000`。
- 对整个 `/usr/src/nvidia-610.43.03` 做精确字符串搜索，结果仍是 21 行、8 个文件。
  剔除声明、宏、dispatch、函数指针赋值及 getter 定义后，确有 7 个源码级直接
  调用函数。
- 7 个直接 caller 的显式 getter-base 硬件访问均为 `GPU_REG_RD32`。其偏移全集为
  `0x074c`、`0x4e04/0x4e08/0x4e0c`、`0x0c04`、
  `0x4140+4*index`、`0x41c0+4*index` 和 `0x3814`；没有
  `+0x40/+0xd0/+0xdc/+0xf8` 表达式。
- generated HAL 对 GB202 的 caller 选择与 `public_fusebase_callers.md` 表格一致，
  包括三个 GSP/SEC2 方法的非 VF 限定，以及
  `confComputeIsGpuCcCapable_GH100` 只属于 GH100、GB202 选择 GB100 实现的限定。

上述 public-caller 0-match 的准确 FACT 只能写成：

> 在 610.43.03 这一公开源码快照中，本次按 getter 名称/字段枚举出的 7 个源码级
> 直接 caller，没有把 getter 返回值与 `0x40/0xd0/0xdc/0xf8` 相加。

它不是“整个公开驱动没有这些地址”，更不是“固件/FSP/硬件没有这些访问”。

### 1.2 公共 host `OBJGPU` 布局反查：getter 是 `+0x460`，不是 `+0x318`

项目已有只读布局探针 `nv_offsets_static.c`，其中直接打印：

```c
offsetof(struct OBJGPU, __gpuGetPrimaryFuseBaseAddr__)
```

使用 `src/nvidia/Makefile` 中与头文件布局有关的 x86-64 host RM include 路径和
preprocessor 定义，针对同一公开树编译。以下是本次使用的可复现命令；省略的仅是
不影响 C 结构布局的 kernel-object code-generation/warning flags：

```bash
N=/usr/src/nvidia-610.43.03
S="$N/src/nvidia"
C="$N/src/common"

gcc -std=gnu11 \
  -include "$C/sdk/nvidia/inc/cpuopsys.h" \
  -D_LANGUAGE_C -D__NO_CTYPE -DNVRM \
  -DLOCK_VAL_ENABLED=0 -DPORT_ATOMIC_64_BIT_SUPPORTED=1 \
  -DPORT_IS_KERNEL_BUILD=1 -DPORT_IS_CHECKED_BUILD=0 \
  -DPORT_MODULE_atomic=1 -DPORT_MODULE_core=1 -DPORT_MODULE_cpu=1 \
  -DPORT_MODULE_crypto=1 -DPORT_MODULE_debug=1 -DPORT_MODULE_memory=1 \
  -DPORT_MODULE_safe=1 -DPORT_MODULE_string=1 -DPORT_MODULE_sync=1 \
  -DPORT_MODULE_thread=1 -DPORT_MODULE_time=1 -DPORT_MODULE_util=1 \
  -DPORT_MODULE_example=0 -DPORT_MODULE_mmio=0 \
  -DRS_STANDALONE=0 -DRS_STANDALONE_TEST=0 \
  -DRS_COMPATABILITY_MODE=1 -DRS_PROVIDES_API_STATE=0 \
  -DNV_CONTAINERS_NO_TEMPLATES -DINCLUDE_NVLINK_LIB -DINCLUDE_NVSWITCH_LIB \
  -DNV_PRINTF_STRINGS_ALLOWED=1 -DNV_ASSERT_FAILED_USES_STRINGS=1 \
  -DPORT_ASSERT_FAILED_USES_STRINGS=1 \
  -I"$S/kernel/inc" -I"$S/interface" \
  -I"$C/sdk/nvidia/inc" -I"$C/sdk/nvidia/inc/hw" \
  -I"$S/arch/nvalloc/common/inc" -I"$S/arch/nvalloc/common/inc/gsp" \
  -I"$S/arch/nvalloc/common/inc/deprecated" \
  -I"$S/arch/nvalloc/unix/include" -I"$S/inc" -I"$S/inc/os" \
  -I"$C/shared/inc" -I"$C/inc" \
  -I"$C/uproc/os/libos-v2.0.0/include" -I"$C/uproc/os/common/include" \
  -I"$C/inc/swref" -I"$C/inc/swref/published" -I"$S/generated" \
  -I"$C/nvswitch/kernel/inc" -I"$C/nvswitch/interface" \
  -I"$C/nvswitch/common/inc" -I"$C/inc/displayport" \
  -I"$C/nvlink/interface" -I"$C/nvlink/inband/interface" \
  -I"$S/src/mm/uvm/interface" -I"$S/inc/libraries" \
  -I"$S/src/libraries" -I"$S/inc/kernel" \
  /home/user/rt_5090_project/nv_offsets_static.c \
  -o /tmp/nv_offsets_static_exact

/tmp/nv_offsets_static_exact
```

输出为：

```text
OBJGPU.size=19320
OBJGPU.vtable_first=160
OBJGPU.vtable_last=1120
Subdevice.pbase_gpures=344
GpuResource.pGpu=224
```

这里 `vtable_first = 160 = 0xa0`，`vtable_last = 1120 = 0x460`；探针源码中的
`vtable_last` 就是 `__gpuGetPrimaryFuseBaseAddr__`。公开
`g_gpu_nvoc.h:989-1110` 又明确给出 121 个连续 per-object 函数指针；按该公开布局
枚举，index 79 的 `+0x318` 是 `g_gpu_nvoc.h:1069` 的
`__gpuGetSriovCaps__`，index 120 的 `+0x460` 才是
`g_gpu_nvoc.h:1110` 的 `__gpuGetPrimaryFuseBaseAddr__`。

准确解释是：

- **FACT：** 当前公开 610.43.03 host RM 的 `OBJGPU` ABI 不把 primary-fuse-base
  getter 放在 `+0x318`；所以“公共 ABI 与 GSP `+0x318` 对齐”不成立。
- **INFERENCE：** stripped GSP 可能使用另一套裁剪/重排的 generated object
  layout；若原报告的构造器写槽和返回值追踪成立，相关 `+0x318` 调用与 getter
  语义高度相容。
- **UNKNOWN：** 仅靠公开 host 源码，不能确定 stripped GSP 中相关 receiver 的
  类型、`+0x318` 字段名或 ELF symbol，也不能把所有 `+0x318` 候选归到同一类。

这不是对原 GSP 行为推断的反证；它是对“ABI”一词和 FACT 等级的明确限制。

## 2. `gsp_slot318_dataflow.md` 建议修订

### 2.1 标题和全局槽位命名

当前标题 `GSP OBJGPU +0x318 / primary-fuse-base` 容易把 receiver 类型、字段偏移和
方法名一起读成已证事实；但该文档自己在 `:37-38,102-103` 承认 `+0x318` 是常见
对象偏移，84 个候选不能全部当作 OBJGPU。

建议标题改为：

> # GSP `base+0x318` 间接调用候选与 primary-fuse-base getter 的有限行为对齐

全文也应避免不带 receiver/call-site 限定的“固件 `+0x318` 槽”。对象字段的身份
至少是 `(receiver 类型, offset)`，不能由裸 offset 全局命名。统一改称“四个经正
校准的 `base+0x318` 间接调用点”或“相关 receiver 的候选 `+0x318` 字段”。

### 2.2 `:42-68` 的公开事实、扫描观察和身份推断应拆层

`:42` 的“generated HAL 直接证明”应拆成两种来源：generated
`g_gpu_nvoc.c` 证明绑定，手写 `kern_gpu_gh100.c` 加实际 include 的
`hwproject.h` 证明返回常量。它们都属于公开 **host RM** 源码，不证明 GSP 布局。

`:47-48` 列出的并非 7 个公开 direct caller 的完整偏移集，只是本次四个 GSP
匹配所对应的偏移。完整集合还包括 `0x4140+4*index` 与
`0x41c0+4*index`。建议改成：

> 本次在 GSP 候选中匹配到的公开 caller offset pattern 为 `+0x3814`、
> `+0x0c04`、`+0x074c`，以及 GH100-only 的
> `+0x4e04/+0x4e08/+0x4e0c`；公开 7 个 direct caller 的完整偏移集还包括
> SEC2/GSP ucode-version 的 `0x4140/0x41c0 + 4*index`。

`:59-61` 把 `+0x074c` 唯一命名为 “GSP debug-fuse caller” 也过窄。公开源码中
`confComputeIsDebugModeEnabled_GH100` 和 `kgspIsDebugModeEnabled_GB100` 都直接
形成 `+0x074c`；只展示 “call 后形成该 offset” 不能在二者之间唯一判别。建议改成：

> 前三组 offset pattern 分别与 GB202-selected 的 ECC readout、display fuse，
> 以及两个公开 debug-mode reader 共享的 `+0x074c` 模式相符；第四组与
> GH100-only spare-bit caller 相符，不能当作 GB202 runtime-path 证据。

`:65-68` 建议用以下四档句子替换，尤其删除“ABI 对齐”：

> **FACT（公开 host RM）：** GB202 的 C 层 getter 绑定 GH100 实现，后者返回
> `0x820000`；公开 host `OBJGPU` 中该方法位于 `+0x460`，不是 `+0x318`。
>
> **FACT（限原扫描报告的已访问路径；本次未重跑）：** 报告记录四个
> `base+0x318` 间接调用点的返回值随后形成上述公开 offset pattern，并另记录一个
> 候选构造器把返回 `0x820000` 的函数写入 `+0x318`。
>
> **INFERENCE（强）：** 若构造器归属、receiver 传递和扫描结果均成立，这四个
> 调用点的相关字段很可能是私有 GSP 布局中的 primary-fuse-base getter。这里是
> 构造器/行为/源码语义对齐，不是公开 ABI 或 ELF symbol 对齐。
>
> **UNKNOWN：** stripped GSP 的正式类型名、字段名和 symbol，以及其余 80 个
> `+0x318` 间接调用候选分别属于哪些对象/方法。

结论 `:114-116` 相应建议改为：

> 公开 host 源码的 GB202 getter 绑定和返回值是 FACT；四个经正校准的 GSP
> `base+0x318` 调用点与该 getter 的关系是强 INFERENCE，不能把裸 `+0x318`
> 全局命名为 OBJGPU getter，也不能称为公开 ABI 事实。

### 2.3 `permission-interest matches = 0` 的准确等级

`:91-96` 目前把 84 个一般对象候选的返回值统称为 “getter 返回值”。建议改为：

> 在由近邻规则筛出的 84 个 `base+0x318` 间接调用候选中，扫描器已访问的模型
> 状态没有出现“候选调用返回值形成
> `+0x40/d0/dc/e0/f4/f8/13c`”或把这些相对地址作为下一 helper 参数的报告项。
> 这只是在已选择候选、已访问状态和已建模 move/加法形式内，对“调用返回 base
> 后简单加目标 offset”形态的有限负证据。

`:98-110` 的边界大体正确，应保留；建议把 `:108-109` 的
“这组 getter-call”改为“这组 `+0x318` 间接调用候选”，避免先假设待证明的身份。

结论 `:117-120` 中“进一步削弱当前 GSP 内藏普通、无凭据 `f8` setter”仍略宽。
建议改为：

> **INFERENCE：** 该 0-match 削弱的是“setter 先经本次捕获的 `base+0x318`
> 间接调用取得 base，再在模型窗口内用简单运算形成 `+0xf8`”这一具体实现假设。
> 它不能单独削弱所有无凭据 setter 形态。
>
> **UNKNOWN：** 超出 12 指令近邻筛选的 caller、12 个达到 2500-state 上限的更深
> 路径、复杂位运算、表驱动 RegHal、跨 helper/跨段路径、直接 literal，以及
> FSP/HULK/动态 payload。

换言之，“0-match”是扫描器域内的 **FACT**；“因此某种简单实现较不可能”是
**INFERENCE**；“全程序/全固件不存在访问或 setter”仍是 **UNKNOWN**。

### 2.4 数字 offset 的语义标签需注明来源

`:74-81` 把 `0x40/d0/dc/e0/f4/f8/13c` 命名为 latch/PLM/sibling register。
这些名称不是从本次公开 getter caller 搜索得到的。若保留，应在表前补一句：

> 下列 offset-to-semantic 标签来自另行归档的 RegHal/静态分析，不由 610 公开
> getter caller 源码建立；本节的数据流扫描只把它们当作待匹配的数值 offset。

## 3. `public_fusebase_callers.md` 建议修订

该文档已经在 `:58-60,111,115-120` 正确限制公开源码的证明域，没有把
`+0x318` 宣称为公开源码事实；核心结论无需降级。

建议做两处小修：

1. 把 `:62` 的标题“全部 7 个公开直接调用函数”改成“本次精确符号搜索枚举出的
   7 个公开源码直接调用函数”，避免把 exact-name enumeration 写成对所有可能
   wrapper、别名或间接调用形式的全程序证明。
2. 在 `:58-60` 后加入公共布局反查：

   > **FACT（公开 host 布局）：** 按同版本 `src/nvidia/Makefile` 的 host RM
   > 头文件配置，`offsetof(OBJGPU, __gpuGetPrimaryFuseBaseAddr__)=0x460`；公开
   > `OBJGPU+0x318` 对应 `__gpuGetSriovCaps__`。因此公开源码不仅没有证明 GSP
   > `+0x318` 的 getter 身份，也不能为它提供 ABI 对齐。私有 GSP 可能使用不同
   > generated layout，所以该事实不反证另文的行为推断。

`d0/dc/f8/latch` 表中四个“FACT：否”可以保留，因为列标题和 `:111` 已把“否”
严格限定为上述 7 个直接 caller；不得在别处省略这个限定。

## 4. 主报告 `L2_REENABLE_STATIC_FINDINGS.md:875-886` 建议整段替换

现段落已经保留 12 个截断候选和未建模路径，负证据边界总体正确；主要问题是
“GSP 对象槽”“ABI 对齐”和四个模式的运行时含义。建议替换为：

> 同时对 GSP 中 `base+0x318` 的间接调用候选做了低内存、有限控制流的数据流
> 校准。公开 610 host RM 的 generated HAL 明确把 GB202 的
> `gpuGetPrimaryFuseBaseAddr` 绑定到返回 `0x820000` 的 GH100 实现，这是公开
> 源码 FACT；但同一公开 host 布局把该字段放在 `OBJGPU+0x460`，不是
> `+0x318`，所以公开源码只提供方法语义校准，不提供 GSP ABI/字段名证明。
> 原扫描报告记录四个 `base+0x318` 调用点随后形成 `+0x3814`、`+0xc04`、
> `+0x74c` 和 `+0x4e04/+0x4e08/+0x4e0c`；前三组与 GB202-selected 公开
> caller 的 offset pattern 相容（其中 `+0x74c` 由两个 debug-mode reader
> 共享），第四组只与 GH100-only sibling 相容，不能当作 GB202 runtime-path
> 证据。结合另行记录的构造器写槽/返回值追踪，可把相关 receiver 的
> `+0x318` 字段识别为 primary-fuse-base getter 的**强行为推断**，但不能把裸
> `+0x318` 全局命名为 OBJGPU getter，也不能称为公开 ABI 或 ELF symbol 事实。
> 同一模型在已访问状态中没有形成 `+0x40/d0/dc/e0/f4/f8/13c`，因此对
> “候选调用返回 base 后以已建模简单运算形成 `+0xf8`”这一具体形态构成有限
> 负证据。不过 84 个候选中有 12 个达到每候选 2500-state 上限，且近邻筛选外、
> 复杂表驱动、跨 helper/跨段、直接 literal、FSP/HULK 和动态 payload 均未被
> 覆盖；这不是 getter caller、setter 或全程序访问不存在的证明。

## 5. 统一 FACT / INFERENCE / UNKNOWN 口径

| 命题 | 准确等级 | 准确范围 |
|---|---|---|
| 公开 610 GB202 getter 绑定 GH100 实现 | **FACT** | 公开 host RM generated table |
| GH100 实现返回 `0x820000` | **FACT** | 公开 C 实现及其实际 include 头文件 |
| 21 hits／8 files／7 direct caller | **FACT** | 610.43.03 快照中的精确 token/field 搜索 |
| 7 个 direct caller 不用 `40/d0/dc/f8` | **FACT** | 仅这 7 个源码级直接 caller |
| 公开 host `OBJGPU` getter offset 为 `0x460` | **FACT** | 本次 x86-64 host RM 头文件配置 |
| GSP 相关 `+0x318` 调用是 getter | **INFERENCE（强）** | 依赖另文构造器、receiver 和行为追踪均正确 |
| `+0x318` 与公开 `OBJGPU` ABI 对齐 | **不成立** | 公开 host offset 实为 `+0x460` |
| 所有 GSP `+0x318` 候选都是 OBJGPU/getter | **UNKNOWN；原报告也明确禁止这样归类** | offset 可被不同对象类复用 |
| 扫描器已访问状态的 target match 为 0 | **FACT（限原扫描报告）** | 84 个近邻候选、已建模状态；本次未重跑 |
| 简单的 getter-return-plus-`f8` 形态较不受支持 | **INFERENCE** | 仅扫描器捕获和建模的形态 |
| GSP/FSP/硬件不存在 `f8/d0/dc` 访问或 setter | **UNKNOWN；不能由 0-match 推出** | 未建模、截断、间接和不可见路径仍开放 |

## 结论

公开 610 源码部分总体可靠，且其负搜索已经有合格的 caller 范围限定。真正需要
修正的是将“公开方法语义相同”升级成“GSP `OBJGPU+0x318` ABI/字段身份相同”。
公共 host 布局的 `+0x460` 结果明确排除了这种 ABI 表述，但不排除私有 GSP 使用
另一套布局；因此最佳口径是“相关 call-site 的强行为推断，正式类型/字段名未知”。

同理，0-match 应始终写成“84 个近邻候选的已访问、已建模状态未命中”。它只对
一种具体而常见的实现形态提供范围明确的负证据，不能升级为 getter caller、
无凭据 setter、FSP/HULK 路径或全程序访问不存在。

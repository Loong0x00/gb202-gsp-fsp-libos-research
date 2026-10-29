# 610.43.03 公开源码中的 `gpuGetPrimaryFuseBaseAddr` 与 GB202 调用者核对

日期：2026-07-21  
范围：纯公开源码、离线、只读。未分析任何固件或 MODS 二进制，未访问 GPU、MMIO、debugfs，也未执行 reset/rebind/固件代码。

## 结论

- **FACT：** 610.43.03 的 generated HAL 明确把 GB202 的 `gpuGetPrimaryFuseBaseAddr` 绑定到 `gpuGetPrimaryFuseBaseAddr_GH100`。
- **FACT：** 该实现返回 `NV_FUSE0_PRI_BASE`；它所在的 GH100 编译单元所包含的公开头文件把该常量定义为十进制 `8519680`，即 `0x820000`。GB100 的公开 `hwproject.h` 也把同名常量定义为 `0x820000`。
- **FACT：** 对 `/usr/src/nvidia-610.43.03/src/nvidia` 全树精确搜索得到 21 个 `gpuGetPrimaryFuseBaseAddr` 文本命中、分布在 8 个文件。剔除 generated 声明、宏、dispatch、函数指针赋值和 getter 自身定义后，剩下 7 个直接调用函数。
- **FACT：** 这 7 个直接调用函数里的所有硬件访问都是 `GPU_REG_RD32`；没有一个直接调用表达式使用相对 fuse base 的 `+0x40`、`+0xd0`、`+0xdc` 或 `+0xf8`。
- **FACT：** 其中一个直接调用函数 `confComputeIsGpuCcCapable_GH100` 并不是 GB202 所选择的 HAL 体；GB202 对该上层方法选择 `confComputeIsGpuCcCapable_GB100`。因此它的 `+0x4e04/+0x4e08/+0x4e0c` 三次直接读取不能当成 GB202 路径证据。
- **UNKNOWN：** 公开主机源码不能证明某一公开 HAL 在一张具体 RTX 5090 上是否实际被调用，也不能排除未公开源码或固件内部还有其他 fuse-base 调用者。

## 1. GB202 的 getter 绑定与返回值

### FACT：generated HAL 绑定

`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_gpu_nvoc.c:2723-2733` 的 `gpuGetPrimaryFuseBaseAddr` 初始化分支明确列出：

```text
ChipHal: GH100 | GB100 | GB102 | GB10B | GB110 | GB112 |
         GB202 | GB203 | GB205 | GB206 | GB207 | GB20B |
         GB20C | GR100 | GR102
```

该分支执行：

```c
pThis->__gpuGetPrimaryFuseBaseAddr__ = &gpuGetPrimaryFuseBaseAddr_GH100;
```

`g_gpu_nvoc.h:4319-4320` 的 dispatch 则直接调用这个 per-object 函数指针。

### FACT：返回常量

`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/arch/hopper/kern_gpu_gh100.c:647-653`：

```c
NvU32 gpuGetPrimaryFuseBaseAddr_GH100(OBJGPU *pGpu)
{
    return NV_FUSE0_PRI_BASE;
}
```

同一编译单元包含 `published/hopper/gh100/hwproject.h`；该头文件第 31 行定义：

```c
#define NV_FUSE0_PRI_BASE 8519680
```

`8519680 == 0x820000`。作为交叉核对，`published/blackwell/gb100/hwproject.h:31` 也定义：

```c
#define NV_FUSE0_PRI_BASE 0x820000
```

### UNKNOWN：与固件对象偏移的关系

这里只能给出公开 C/H 层面的 getter 身份、HAL 绑定和返回值。此次范围没有分析 GSP ELF，因此不能仅凭这些公开源码把固件对象中的某个字节偏移（例如 `+0x318`）宣称为已经二进制级验证的 `gpuGetPrimaryFuseBaseAddr` 槽位。

**FACT（公开 host 布局）：** 按同版本 `src/nvidia/Makefile` 的 host RM
头文件配置编译布局探针，
`offsetof(OBJGPU, __gpuGetPrimaryFuseBaseAddr__)=0x460`；公开
`OBJGPU+0x318` 对应 `__gpuGetSriovCaps__`。因此公开源码不仅没有证明 GSP
`+0x318` 的 getter 身份，也不能为它提供 ABI 对齐。私有 stripped GSP 可能
采用裁剪/重排后的另一套 generated layout，所以这个事实也不反证另文基于
构造器和返回值用途提出的行为推断。可复现编译命令与字段枚举见
`parallel/slot318_wording_review.md:74-155`。

## 2. 本次精确符号搜索枚举出的 7 个公开源码直接调用函数

下表的“相对偏移”均是源码实际加到 getter 返回值上的量；“绝对地址”按已证实的 base `0x820000` 做直接算术展开。

| 直接调用函数 | 源码位置 | 相对偏移 | 展开的绝对地址 | 访问 | GB202 HAL 选择 |
|---|---|---:|---:|---|---|
| `confComputeIsDebugModeEnabled_GH100` | `conf_compute_gh100.c:48-55` | `0x074c` (`NV_FUSE_ZB_OPT_SECURE_GSP_DEBUG_DIS`) | `0x82074c` | `GPU_REG_RD32` | **是**；generated 表明确将 GB202 绑定到此体 |
| `confComputeIsGpuCcCapable_GH100` | `conf_compute_gh100.c:66-92` | `0x4e04`, `0x4e08`, `0x4e0c` (`SPARE_BIT_0/1/2`) | `0x824e04`, `0x824e08`, `0x824e0c` | 三次 `GPU_REG_RD32` | **否**；GB202 选择 `confComputeIsGpuCcCapable_GB100` |
| `gpuFuseSupportsDisplay_GB100` | `kern_gpu_gb100.c:1699-1705` | `0x0c04` (`NV_FUSE_ZB_STATUS_OPT_DISPLAY`) | `0x820c04` | `GPU_REG_RD32` | **是**；generated 表明确列出 GB202 |
| `ksec2ReadUcodeFuseVersion_GB100` | `kernel_sec2_gb100.c:39-59` | `0x4140 + 4*index` | `0x824140` 到 `0x82417c` | `GPU_REG_RD32` | **是（非 VF 分支）**；GB202 不匹配前置 TU/GA 分支，落到 GB100 体 |
| `kgspIsDebugModeEnabled_GB100` | `kernel_gsp_gb100.c:290-298` | `0x074c` | `0x82074c` | `GPU_REG_RD32` | **是（非 VF 分支）**；GB202 落到 GB100 体 |
| `kgspReadUcodeFuseVersion_GB100` | `kernel_gsp_gb100.c:308-328` | `0x41c0 + 4*index` | `0x8241c0` 到 `0x8241fc` | `GPU_REG_RD32` | **是（非 VF 分支）**；GB202 落到 GB100 体 |
| `kmemsysCheckReadoutEccEnablement_GB100` | `kern_mem_sys_gb100.c:216-223` | `0x3814` (`NV_FUSE_ZB_FEATURE_READOUT`) | `0x823814` | `GPU_REG_RD32` | **是**；generated 表明确列出 GB202 |

两个 ucode-version 宏的字段都定义为 `15:0`。源码用 `index < DRF_SIZE(..._DATA)` 限界；公开 `nvmisc.h` 将 `DRF_SIZE` 定义为高位减低位再加一，因此共有 16 个 32-bit 项，表中的末地址分别是起点加 `4 * 15`。

## 3. GB202 实际 HAL 路径的细化

### FACT：直接选择

- `g_conf_compute_nvoc.c:681-690`：GB202 的 `confComputeIsDebugModeEnabled` -> `confComputeIsDebugModeEnabled_GH100`。
- `g_gpu_nvoc.c:1994-2021`：GB202 的 `gpuFuseSupportsDisplay` -> `gpuFuseSupportsDisplay_GB100`。
- `g_kern_mem_sys_nvoc.c:880-900`：GB202 的 `kmemsysCheckReadoutEccEnablement` -> `kmemsysCheckReadoutEccEnablement_GB100`。

### FACT：非 VF 分支中的默认 GB100 选择

- `g_kernel_gsp_nvoc.c:609-632`：物理/非 VF 路径中，GB202 不匹配 Turing 或 GA/Ada/Hopper 分支，因而 `kgspIsDebugModeEnabled` 选择 GB100 体。
- `g_kernel_gsp_nvoc.c:1081-1105`：相同结构使 `kgspReadUcodeFuseVersion` 选择 GB100 体。
- `g_kernel_sec2_nvoc.c:627-653`：相同结构使 `ksec2ReadUcodeFuseVersion` 选择 GB100 体。

VF 分支会先选 stub，所以上述三项不能无条件描述成所有 RM variant 都执行 GB100 体。

### FACT：GH100 spare-bit caller 不属于 GB202 选择

`g_conf_compute_nvoc.c:693-706` 只给 GH100 选择 `confComputeIsGpuCcCapable_GH100`；GB202 明确选择 `confComputeIsGpuCcCapable_GB100`。后者位于 `conf_compute_gb100.c:194-207`，只调用 `confComputeIsDebugModeEnabled_HAL` 并根据结果返回，不直接获取 fuse base，也不读取 `SPARE_BIT_0/1/2`。

因此，对 GB202 而言，上层 `confComputeIsGpuCcCapable` 最多通过其 debug-mode HAL 间接触发已列出的 `0x82074c` 读取；不能把 GH100 的三个 spare-bit 地址算入 GB202 直接 caller 集合。

## 4. 与 `d0/dc/f8/latch` 的逐项核对

以 getter 返回的 `0x820000` 为 base，目标相对偏移对应：

| 目标 | 相对 fuse-base 偏移 | 绝对地址 | 7 个公开直接 caller 是否使用 |
|---|---:|---:|---|
| latch | `0x40` | `0x820040` | **FACT：否** |
| d0 | `0xd0` | `0x8200d0` | **FACT：否** |
| dc | `0xdc` | `0x8200dc` | **FACT：否** |
| f8 | `0xf8` | `0x8200f8` | **FACT：否** |

这里的“否”严格限定为：上述 7 个公开 C 直接调用函数中，没有任何 getter 返回值加这些偏移的表达式。它不等价于“整个驱动、闭源组件或固件绝不存在这些地址的访问”。

## 5. 证据边界

- **FACT：** 本次精确字符串搜索覆盖 `/usr/src/nvidia-610.43.03/src/nvidia` 全树；宏数值另外从这些 C 文件实际包含的同版本公开 `src/common/inc/swref/published/...` 头文件解析。
- **FACT：** 公开直接 caller 只展示读取，没有展示 fuse-base 写入、权限降低、latch 操作或 L2 floorsweep 改动。
- **UNKNOWN：** 某一条 HAL 在零售 GB202 上的实际运行频次与时序。
- **UNKNOWN：** 未公开 RM、FSP/GSP 固件内部调用者及其偏移。
- **UNKNOWN：** 固件二进制对象布局中的 `+0x318` 是否对应此 getter；本报告有意不做二进制推断。
- **UNKNOWN：** 上述只读状态寄存器与 L2 解锁之间存在任何直接机制关系；公开 caller 本身没有提供这种关系。

# `0xbadf510c` privilege sentinel 的静态来源边界

日期：2026-07-21
状态：final；严格静态、只读、有限窗口

## 范围与材料

本文回答一个很窄的问题：MODS 570.151 的 raw floorsweep writer 回读到
`0xbadf510c` 时，这个值究竟是 host 程序自己造出来的，还是从寄存器访问
backend 返回的。

固定材料：

- `mods_audit/static/extracted_inner/mods`，SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- 本地 NVIDIA open-gpu-kernel-modules 源码 commit
  `c331140f40b033b0ad2d428b03a408c9913e4ac9`（工作树当时有其他 dirty
  状态；本文只读下列已存在源文件）；
- `parallel/reghal_writer_transport.md` 已闭合的 raw read/write 调用链。

未执行 MODS，未访问 GPU、BAR、MMIO、debugfs 或 RM control。

## 结论

1. **FACT：固定 MODS host ELF 不生成 `0xbadf510c`。** 默认 mapped-aperture
   分支直接返回 32-bit load；可选 RM-regops 分支直接返回 response
   `regValueLo`。`ProgramSwFusePlan` 只是之后比较这个常量。
2. **FACT：RM-regops helper 看到了 control status 和 per-op `regStatus`，但
   并不把它们变成 caller 可依赖的失败返回。** 有错误时它至多走诊断日志；
   正常返回值仍取 response `regValueLo`。
3. **FACT：NVIDIA 公开驱动把 `0xBADxxxxx` 明确定义为硬件 PRI-read error
   family。** 普通寄存器读取检测该前缀、调用错误处理器，但不重写原读值。
   NVIDIA 自己还在少数地方使用 unchecked/raw read，专门为了保留
   `0xBADF41YY` 一类硬件错误值。
4. **INFERENCE：** 因而 `0xbadf510c` 是寄存器 fabric / 更下层访问 backend
   返回的 PRI-error 编码，而不是 MODS host 的软件哨兵。默认 direct 分支时，
   下一层就是 mapped aperture；RM-regops 分支时，公开材料只能把来源收窄到
   RM/GSP/硬件链，不能再唯一指定是哪一层首先形成该值。
5. **UNKNOWN：** 公开 Blackwell 头文件没有给出精确 `0xBADF51xx` 子类型与
   低字节 `0x0c` 的字段定义。MODS 的日志把这个固定值称为
   `Priv-level violation`，但不能据此把 `0x51` 或 `0x0c` 自行解码成某个
   source/target ID。

## 1. MODS 的两条返回路径

已闭合调用图见 `parallel/reghal_writer_transport.md`：

```text
raw read
  -> GpuSubdevice +0x228
  -> ordinary backend
       default: mapped aperture 32-bit load
       optional: NV2080_CTRL_CMD_GPU_EXEC_REG_OPS READ_32/GLOBAL
  -> ProgramSwFusePlan compares returned dword with 0xbadf510c
```

direct 分支 `0x0dc702b..0x0dc702e` 是普通 32-bit load 后直接返回，没有
常量替换逻辑。

RM-regops helper `0x0dc68d0..0x0dc69bd` 的关键窗口为：

```text
0x0dc690a  edx = 0x20800122              # EXEC_REG_OPS
0x0dc6949  call control transport
0x0dc694e  save control status
0x0dc6952  test control status
0x0dc6956  cmp byte [rsp+0x12], 0         # operation.regStatus
...
0x0dc696b  eax = [rsp+0x24]               # operation.regValueLo
...
0x0dc69b9  eax = [rsp+0x24]               # diagnostics tail also returns it
```

所以此 helper 不是“收到 NOACCESS 就给上层一个可靠错误码”的接口；它把
status 用于诊断分支，而把读取到的 dword 当作函数返回值。`0xbadf510c`
若从 RM control 回来，会原样穿过这里。

## 2. NVIDIA 公开源码对 `0xBADxxxxx` 的定义

`src/nvidia/generated/g_gpu_nvoc.h` 定义：

```c
#define GPU_READ_PRI_ERROR_MASK  0xFFF00000
#define GPU_READ_PRI_ERROR_CODE  0xBAD00000
```

`src/nvidia/src/kernel/gpu/gpu_access.c` 的
`gpuSanityCheckRegRead_IMPL()` 对 32-bit read 做：

```text
if ((value & 0xfff00000) == 0xbad00000)
    gpuHandleSanityCheckRegReadError(..., value)
return NV_OK
```

调用者 `_regRead()` 在 sanity check 后仍返回原 `returnValue`。也就是说，
公开 RM 会识别并记录这种读错误，但这段通用代码没有把它替换成另一值。

`src/nvidia/arch/nvalloc/common/inc/flcnretval.h` 还公开定义了：

```c
#define FLCN_CSB_PRIV_PRI_ERROR_MASK  0xFFFF0000U
#define FLCN_CSB_PRIV_PRI_ERROR_CODE  0xBADF0000U
```

这证明 `BADF` 是 NVIDIA 硬件/固件寄存器访问错误约定的一部分，不是这个
MODS writer 私有创造的 magic。

## 3. `0xBADF41YY` 的官方旁证及其边界

公开驱动的
`src/nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c` 明说：

- CPU 没有其他硬件机制判断 GSP target mask 是否开放；
- 读取受阻时会看到 `0xBADF41YY`；
- 因普通寄存器工具会做 `0xbadf` sanity checking，该点必须用
  `GPU_REG_RD32_UNCHECKED`；
- 比较 `0xBADF4100/0xFFFFFF00`，低 8 位包含额外错误信息。

Blackwell GB10B SEC2 路径
`src/nvidia/src/kernel/gpu/sec2/arch/blackwell/kernel_sec2_gb10b.c`
也使用相同 `0xBADF4100` mask 和 raw OS read。

这是很强的**格式与来源类别**旁证：`BADFxxYY` 能由硬件 target/PRI
访问控制直接作为读值返回，低字节可附带额外信息。但它并未定义
`BADF51YY`，所以不能把 `0xBADF4100` 的语义直接移植到
`0xbadf510c`。

## 4. 这对 floorsweep writer 的实际含义

`ProgramSwFusePlan` 把 `0xbadf510c` 单独分支为 privilege violation，随后
只记日志并继续；普通不等值才设置 aggregate error `0x79`。结合本报告：

- 该特殊值不是“host 主动把一次拒绝包装成成功”；
- 更准确地说，是下层已经返回了一个可识别的 PRI 拒绝编码，而 host
  验证器选择不把它计入 aggregate failure；
- 即使 RM-regops 的 `regStatus` 同时表示错误，MODS read helper 也没有把
  它提升为 caller 的可靠失败状态；
- 因而 MODS 顶层 success 仍不能证明 raw OPT/shadow write 被硬件接受。

## 证据矩阵

| 问题 | 结论 | 等级 |
|---|---|---|
| MODS host 是否构造 `0xbadf510c` | 否；两条 backend 都原样上传 read value | **FACT（闭合 host 链）** |
| RM helper 是否读取 per-op status | 是 | **FACT** |
| RM helper 是否把 status 可靠传播给 writer | 否；函数返回仍为 `regValueLo` | **FACT** |
| `0xBADxxxxx` 是否 NVIDIA PRI-read error family | 是 | **FACT（公开源码）** |
| `0xBADFxxxx` 是否存在硬件/固件寄存器访问约定 | 是 | **FACT（公开源码）** |
| `0xbadf510c` 精确字段解码 | 未公开证明 | **UNKNOWN** |
| direct backend 时最初来源 | mapped register aperture 的 read response | **FACT（到 aperture 边界）** |
| RM-regops backend 时最初来源 | RM/GSP/硬件链中的某层；当前不能唯一定位 | **UNKNOWN（已收窄）** |

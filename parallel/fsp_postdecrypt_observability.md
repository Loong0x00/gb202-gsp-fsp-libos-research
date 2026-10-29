# GB202 FSP 解密后 runtime 的 host 侧可观测性审计

日期：2026-07-22（Asia/Singapore）

## 0. 范围、安全边界与结论

本轮只做了本地静态读取：

- `/usr/src/nvidia-610.43.03` 中公开的 FSP、Falcon、CrashCat、CPER 与生成 HAL；
- 项目中已经保存的 VBIOS/FSP 报告；
- 已提取 MODS ELF 的流式字符串和几个已知小窗口。

没有访问 GPU、`/dev/nvidia*`、PCI/BAR/MMIO、debugfs；没有运行 MODS、发送 FSP
命令、reset/rebind/unload、加载固件或修改 VBIOS。本文讨论的 live 路径也都**没有执行**。

### 一句话结论

> **在当前公开 610 host 代码和已提取 MODS 字面证据中，没有找到一个受支持的、
> 只读的 GB202 FSP runtime plaintext 回读接口。** 公开可见面只到 boot/scratch
> 状态、版本、GSP mailbox、192-byte CMS2 日志、MCTP/NVDM 通信响应和 CPER/Xid。
> 通用 Falcon 确实有 DMEM/CrashCat/ICD 设施，但公开 `KernelFsp` 没有接入
> `KernelFalcon`，CrashCat 不含 IMEM/code packet，ICD memory read 需要写调试命令，
> destructive core dump 还会 halt core。因此这些不能闭合成“把 FSP_RUN 解密后的
> 指令体读回来”的安全路径。

严格分级：

- **FACT：** 没有找到公开、已接线的 FSP IMEM/DMEM/code-dump API。
- **INFERENCE（强）：** production GB202 的 FSP plaintext 预期位于 device-side
  受保护执行域，host 被有意限制为状态/协议可观测，而不是代码可观测。
- **UNKNOWN：** plaintext 的精确落点（内部 ROM/SRAM、映射的执行存储或多级组合），
  以及 NVIDIA 实验室凭据/engineering silicon 是否存在额外私有读口。当前材料不能
  证明“物理上绝不可能读”，只能证明“当前找不到合法的零风险 host 回读链”。

## 1. 解密后 plaintext 是否经过 host 内存

### FACT

1. GB202 公开流程是 BootFSM 在 chip reset 后触发 FSP；host 只轮询
   `NV_THERM_I2CS_SCRATCH.FSP_BOOT_COMPLETE`：
   `/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb202.c:50-85`。
2. `KernelFsp` 只继承 `OBJENGSTATE`，没有继承 `KernelFalcon` 或
   `KernelCrashCatEngine`：
   `/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kern_fsp_nvoc.h:81-100`。
3. 它的 host 数据成员是 FRTS、GSP-FMC、GSP boot args、COT payload、RPC 状态和
   mailbox aperture；没有 FSP runtime image/plaintext memdesc：
   `g_kern_fsp_nvoc.h:141-157`。
4. 既有启动链审计也已闭合：GB202 公开 RM 不提取/上传 `FSP_RUN`；host 后续交给
   FSP 的大映像是 GSP-FMC/GSP-RM boot material，而不是 FSP 自身 runtime：
   `parallel/fsp_boot_chain_trace.md:31-45,142-197,199-292`。

### INFERENCE

正常启动时，VBIOS v6 对象若确实承载 FSP 主体，其认证/解密和落地发生在设备内部
早期安全链中，而不是先得到一个可由 Linux RM 映射的 plaintext host buffer。

### UNKNOWN

公开代码没有给出 v6 loader、plaintext destination、运行时虚拟地址表或生命周期；
不能仅凭“BootFSM 启动”断言代码一定在传统 Falcon IMEM，也不能排除 ROM first
stage 与受保护 bulk runtime 的组合。

## 2. FSP 专用的公开可观测路径

| 路径 | FACT：公开 610 实际得到什么 | 能否得到代码本体 | 是否是纯被动 read |
|---|---|---|---|
| Boot-complete scratch | 一个 `0xff` 完成状态 | **否** | host 侧轮询读 |
| FSP scratch/version | scratch group 2 的 4 个 dword；ucode major/minor 来自 scratch group 3 | **否** | 这些字段本身是读 |
| `kfspDumpDebugState_GB100`（GB202 复用） | FSP 版本/scratch、GSP mailbox、GSP FMC error、PGSP mailbox、CMS2 log | **否**；函数没有 IMEM/DMEM loop | 混合；CMS2 需要先写索引寄存器 |
| CMS2 log | 索引 `0x50..0x7f`，共 48 dword = 192 bytes，被代码明确称为 `CMS2 Log` | **没有代码语义证据** | 不是纯 read；每个 dword 先写 `*_RD_ADDR` 再读 `*_RD_DATA` |
| FSP EMEM transport | 固定 1 KiB RM channel 上的 MCTP/NVDM command/response packet | **否**；它是通信队列，不是 runtime aperture | 不是；配置 EMEMC，读后还更新 MSGQ head/tail |
| MNOC transport | mailbox packet send/receive | **否** | 协议交互，不是 passive dump |
| FSP CPER | `GPU-KFSP` 事件 + legacy Xid 文本，内容来自 host 已读的 status/scratch | **否** | 事件生成/记录路径 |

### 2.1 GB202 的 FSP debug HAL 到底会读什么

### FACT

生成 HAL 把 GB202 映射到 `kfspDumpDebugState_GB100`：
`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kern_fsp_nvoc.c:569-578`。

该实现只做以下动作：

- 读 FSP ucode version、FSP scratch group 2；
- 读 GSP mailbox、GSP FMC error 和 `NV_PGSP_MAILBOX(i)`；
- 收集并打印 CMS2 log。

对应代码：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb100.c:204-250`。

CMS2 收集范围和实际访问：

- `CMS2_LOG_START=0x50`、`END=0x7f`、192 bytes：同文件 `:67-70`；
- 循环先写 `NV_POOBHUB_RCV_INDIRECT_CMS2_MEM_RD_ADDR`，再读 DATA：`:294-307`；
- 公开寄存器头只把这两个口定义成 indirect address/data：
  `/usr/src/nvidia-610.43.03/src/common/inc/swref/published/blackwell/gb100/dev_oob_pri.h:27-28`。

### INFERENCE

CMS2 是最接近“解密后设备内部内容”的正式诊断窗口，但当前代码把它限定为固定
192-byte **log**，不是可选地址/长度的 FSP executable-memory reader。即使日志偶尔
含 PC、错误码或少量诊断字节，也不等于可连续恢复 runtime。

### UNKNOWN

CMS2 每个字段的私有格式没有发布。不能排除某个固件版本在异常日志中偶然泄露少量
内存，但没有证据支持把它当作代码 dump 通道，也没有运行验证。

### 2.2 EMEM 不是“FSP 的全部内存”

### FACT

公开定义明确说 EMEM channel 0 是 CPU-RM/其他 uproc 与 FSP management partition
之间承载 NVDM-over-MCTP 的通信机制，大小固定 1024 bytes：
`/usr/src/nvidia-610.43.03/src/nvidia/arch/nvalloc/common/inc/fsp/fsp_emem_channels.h:27-37`。

host read 路径：

1. 从 MSGQ head/tail 计算 packet size；
2. 把 EMEMC 配置到 RM channel offset 0；
3. 从 EMEMD 读 response packet；
4. 把 MSGQ tail/head 更新为已消费。

见
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c:656-724`。

公开 NVDM type 表包含 reset、HULK、firmware update、PRC、COT、caps、InfoROM、
`ROMREAD` 等类型，但没有公开命名的 FSP memory/code dump 类型：
`/usr/src/nvidia-610.43.03/src/nvidia/arch/nvalloc/common/inc/nvdm_format.h:37-61`。

### UNKNOWN

`NVDM_TYPE_ROMREAD=0x1a` 在当前公开树中只有常量、没有 payload 格式或调用者。
不能把它解释成 FSP runtime memory read，更不能推断它返回解密 plaintext。

### 2.3 CPER/Coredump 名字容易造成的误会

### FACT

FSP boot failure 的 CPER builder 只创建 `GPU-KFSP` NVIDIA event section，再加入
legacy Xid context；没有附加 FSP memory、CMS2 blob、IMEM 或 DMEM：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/kern_fsp.c:1001-1077`。

GB202 boot-time Xid 文本只包含 poll status、boot-complete scratch 和四个 FSP
scratch dword：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb202.c:87-105`。

所以这里的 “dump/CPER” 是状态与错误记录，不是 firmware image coredump。

## 3. 通用 Falcon/CrashCat/ICD 为什么不能直接套到 FSP

### 3.1 对象接线边界

### FACT

`KernelFalcon` 才继承 `KernelCrashCatEngine`，并提供 RISC-V ICD、PC/trace、DMEM 等
接口：
`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kernel_falcon_nvoc.h:96-175`。

公开 `KernelFsp` 则只是 `OBJENGSTATE`，没有这些 vtable 和 register/riscv base；见
第 1 节引用。公开的 `kflcnGetKernelFalconForEngine()` 特殊接线只列 SEC2 与 GSP，
没有 FSP：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/falcon/kernel_falcon.c:62-81`。

因此，**通用 Falcon HAL 在 GB202 这一芯片代际存在**不等于**公开 RM 已构造一个可
对 FSP 使用的 KernelFalcon 对象**。

### UNKNOWN

已提取 MODS 内有字面串 `Falcon object constuct failed for FSP.`，说明它携带的私有
RM/MODS build 可能在某条路径尝试构造 FSP Falcon facade；但字符串本身没有给出
成功路径、register base、权限或 memory-dump API，不能推翻上述公开对象边界。

### 3.2 非破坏 core dump 只有状态、PC 与 trace

### FACT

通用 `CoreDumpRegs` 包含 PC、CPU/IRQ/priv-error、mailbox/FBIF 和最多 64 个 trace
PC，没有代码或任意 memory buffer：
`/usr/src/nvidia-610.43.03/src/nvidia/inc/kernel/gpu/falcon/kernel_falcon_core_dump.h:28-55`。

`kflcnCoreDumpNondestructive()` 只填这些字段并打印：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/falcon/kernel_falcon.c:446-492`。

Blackwell 的 `kflcnDumpCoreRegs_GB202()` 同样只读一组 RISC-V 状态寄存器：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/falcon/arch/blackwell/kernel_falcon_gb202.c:35-50`。

即使未来能对 FSP 接线，它最多帮助定位 PC/错误状态，不能直接恢复指令体。

### 3.3 ICD 的 `RDM` 能读虚拟地址，但不是安全的 passive readback

### FACT

通用 Falcon ICD 的 `kflcnRiscvIcdReadMem_TU102()` 确实支持 1/2/4/8-byte 对齐的
RISC-V virtual-address read；但实现会：

- 写 ICD address registers；
- 写 ICD command register，发 `RDM` command；
- 再读返回值。

见
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/falcon/arch/turing/kernel_falcon_tu102.c:560-619`；
GB202 的通用 KernelFalcon HAL 会选择这组 ICD method：
`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kernel_falcon_nvoc.c:719-800`。

destructive coredump 先发送 ICD `STOP`/halt，再读寄存器和栈；它不是只读操作：
`kernel_falcon_tu102.c:795-835`、
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/falcon/kernel_falcon.c:495-661`。

公开 GSP caller 还明确说明 production board 上 ICD dump 不能安全做，因为 halt 是
final；只有 fatal timeout + 特定 stall-detection 配置才调用 destructive dump：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/kernel_gsp.c:2570-2584`。

### INFERENCE

FSP 是更早的安全 root/manager，把这套 generic ICD method 的存在解释成“零售 FSP
也允许 host RDM”与安全模型不相容。最可能还有 engine-specific debug fuse、secure
mode 或 PLM gating。

### UNKNOWN

公开 GB202 FSP header 没发布 ICD/IMEM/DMEM/PLM 字段，也没有 FSP KernelFalcon
接线，所以无法从源码决定 raw access 会返回 privilege error、零、总线错误还是被
完全隐藏。由于 ICD command/halt 本身会改变设备状态，不能用 live probing 填这个
空白，尤其当前桌面仍在该 GPU 上。

### 3.4 CrashCat 是诊断报告，不是 code dumper

### FACT

CrashCat 的协议描述是：Peregrine 崩溃后由 firmware 写 wayfinder 和 tagged crash
report queue，host consumer 再读报告：
`/usr/src/nvidia-610.43.03/src/common/uproc/os/common/include/nv-crashcat.h:31-47`。

它公开的 memory aperture 只有 SYSGPA、FBGPA、DMEM、EMEM，**没有 IMEM**：
同文件 `:173-185`。packet 类型只有 report、RISC-V CSR/GPR、PC trace 和 I/O state，
**没有 raw code packet**：`:200-214`。

host DMEM/EMEM 支持用于同步 firmware 指定的 crash-report buffer：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/falcon/kernel_crashcat_engine.c:310-342`。
CrashCat 默认不启用，必须由具体 KernelFalcon 配置；公开 GSP 明确启用它：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/arch/turing/kernel_gsp_tu102.c:60-85`，
而公开 FSP 没有对应配置/继承。

因此 CrashCat 可能提供崩溃 PC、寄存器和 stack trace；它既不是 FSP 的已接线路径，
格式上也不是连续代码回读。

## 4. MODS 静态字面证据

对固定 ELF
`/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods` 做了流式 `strings`
筛选，没有执行该 ELF。

### FACT

找到的 FSP 可观测相关字符串主要是：

- file `0x888ec18`：`FSP EMEM TRANSPORT QUEUE Empty Poll`；
- file `0x888ed30`：`PollFspInitialized::I2CS_SCRATCH is priv protected! Need HULK license!!`；
- file `0x8baf668`：`Falcon object constuct failed for FSP.`；
- file `0x8baf968`：`About to read data from FSP, ememcOff=0, size=...`；
- file `0x8ccef9d`：`FSP Debug Regs:`。

`FSP Debug Regs:` 所在的本地 `0x8cce000..0x8cd1000` 小窗口紧邻的标签是
`BOOTFSM`、`FUSE_POD`、`FUSE_SCPM`、`FSP_SCPM`、`FSP_DCLS`、`GSP_DCLS` 等，输出
格式是 `reg:0x%x value:0x%x`。这是状态寄存器清单的字面形态，不是 memory image
writer/readback 形态。

全 ELF 字符串的定向组合搜索没有找到一个把 `FSP` 与 `IMEM`、`DMEM`、`ICD`、
`CrashCat` 或 code/core dump 明确连在一起的接口名/诊断文本。相反，generic/GSP
路径有明确字符串：

- file `0x8b165b8`：HS Falcon 下不能经 priv 更新 TRACEPC index；
- file `0x8b77158`：`Unable to obtain core dump from GSP-RISCV.`；
- file `0x8b78020`：`GSP-CrashCat Report`；
- file `0x8ba0e80`：`Allowing non-secure falcon memory accesses`。

### INFERENCE

MODS 的 private build 知道更多 FSP 状态寄存器并有 FSP Falcon 构造概念，但它对
production/HS 路径仍区分“non-secure memory access”和受 priv/HULK 保护的状态。
当前字符串更支持“实验室/非安全配置可能有额外调试能力”，不支持“零售 GB202
存在无凭据的 FSP plaintext dump”。

### UNKNOWN

字符串负结果不能排除数字表驱动、无日志的 private method，或只在另一份 NVIDIA
实验室组件中的接口；也不能仅凭 `HULK license` 文本推导许可证能开放哪些 FSP
memory region。没有做全文件反汇编或 live 验证。

## 5. 最终判定：能否把解密后的 runtime 读回来

### FACT

在已审计材料范围内，答案是 **不能用现成合法 host 路径闭合**：

```text
VBIOS encrypted FSP_RUN
  -> device-internal authenticate/decrypt/load       [private]
  -> FSP executes
  -> host-visible scratch/log/RPC/CPER               [public]
  -X-> no public FSP IMEM/DMEM/plaintext image dump
```

可获得的是“它启动了没有、版本/错误是什么、通信返回什么、PC/日志是否有线索”这一
类观测，不是 FSP 代码字节。

### INFERENCE（强）

这不像公开源码“漏写了一个 helper”，而像明确的安全边界：密文可以由 host 保存，
plaintext 只在受保护执行侧使用，host 只拿最小诊断面。generic ICD/DMEM 代码属于
跨 Falcon 的基础设施，并不能自动越过 FSP 的对象、secure-mode 与 PLM 边界。

### UNKNOWN

以下仍未被证明：

1. engineering/unfused GPU、NVIDIA HULK/内部授权或物理 debug/JTAG 是否能读完整
   FSP address space；
2. FSP crash firmware 是否有未公开、签名授权的更完整 dump；
3. 某个异常是否会把 plaintext 片段泄漏进 CMS2/CrashCat；
4. `FSP_RUN` 主体和 task-2 consumer 是否恰好在同一个 post-decrypt image。

这些 unknown 都不能作为当前零售卡的安全实验方案。

## 6. 对项目下一步的含义

1. **不要把 FSP EMEM response queue 当成 runtime EMEM/DMEM。** 它只有固定 1 KiB
   RM 通信 channel，并且 read 操作会改队列状态。
2. **不要把 generic Falcon ICD 当成只读方案。** 它要写 debug command，destructive
   路径会 halt；公开 FSP 也没有接线。
3. **CMS2/scratch 适合将来在停机测试环境中做官方诊断对照，不适合代码恢复。**
   本轮没有读它们。
4. 当前最安全、信息增益最高的方向仍是纯静态：继续比较三个 v6 envelope、寻找公开
   v6/FSP symbol/spec，或寻找同一 FSP build 的合法 debug/symbol artifact。除非出现
   一个明确签名、FSP 专用、只返回 code bytes 且不写/halt/reset 的官方接口，否则
   “post-decrypt live dump”应维持 **不可用** 判定。

## 7. 结论措辞（可直接并入主报告）

> 公开 610 对 GB202 FSP 的 host 可观测面止于 boot-complete、scratch/version、
> GSP mailbox、固定 192-byte CMS2 log、MCTP/NVDM response 和 CPER/Xid；这些路径
> 均没有 FSP IMEM/DMEM/code-image 输出。通用 KernelFalcon 虽提供 CrashCat、PC
> trace 和 ICD virtual-memory read，但公开 KernelFsp 不继承/配置该对象；CrashCat
> 无 IMEM/code packet，ICD 还需写 command，destructive dump 会 halt。故当前没有
> 合法安全的方式把 VBIOS FSP_RUN 认证解密后的 runtime 从零售 GB202 回读。最可能
> 是 plaintext 被留在 device-side secure domain；其精确存储位置及 NVIDIA lab/debug
> 授权下的额外能力仍属 UNKNOWN。

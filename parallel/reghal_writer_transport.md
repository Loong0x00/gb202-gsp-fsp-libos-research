# MODS 570.151 raw writer / ordinary RegHal transport 调用图

## 范围

本文只记录固定样本
`mods_audit/static/extracted_inner/mods`（SHA-256
`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`）
中的有界静态调用图。不执行样本，不观察任何运行时设备状态。

下文的 **FACT** 表示指令窗口或固定 vtable 直接证明；
**INFERENCE** 表示是由这些固定关系归纳出的语义。

## 结论先行

1. **FACT：raw 计划项不经 RegHal 对象。**
   `0x151ad00/0x151ad10` 直接跳到 `GB202GpuSubdevice`
   `+0x238/+0x228`。它们与普通 RegHal 最终使用同一组
   `GpuSubdevice` read/write slots，但 raw 路径本身不查 RegHal
   descriptor、`accessOffset` 或 PLM metadata。
2. **FACT：未分区 GB202 使用普通 RegHal，但“未分区”本身不唯一
   决定底层 transport。** 普通 backend 的默认分支是对已映射寄存器
   aperture 做 32-bit load/store；只有 `Gpu.UseRmRegOps` 为真且对象已
   进入 RM-initialized 状态时，这一普通 backend 才改发全局
   `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS (0x20800122)`。因而默认类别是
   direct mapped aperture；可选类别是 RM reg-ops control。
3. **FACT：raw write 之前没有显式 RegHal access/PLM predicate。**
   下层有一个通用 register-exclusion/write-mask table lookup，但它不是
   RegHal `accessOffset` metadata。
4. **FACT：在已闭合的 host 调用链里，没有函数生成
   `0xbadf510c`。** direct 分支把 aperture load 原样返回；RM
   reg-ops 分支把 response 中的 `regValueLo` 原样返回。
   `0x1515fb6` 只是第一个相关 caller 比较点，不是 generator。
5. **FACT：调用者不保存 raw-write status。** `0x151606b` 调用后，
   `0x151606e` 立即用另一个对象 vptr 覆盖 `RAX`。底层 direct
   store 本来也是 void-style；可选 RM-control 分支在底层记录
   control/reg-op status，却不把它传回这个 caller。
6. **FACT：`0x404f0001` 的上层不同，最终 read/write 函数族相同。**
   它先走 RegHal constant-descriptor 解码和 read-modify-write，然后仍然调
   `GpuSubdevice +0x228/+0x238`。它不是 raw 计划项的同一个入口，
   却会汇合到同一个底层 transport family。

## 1. raw write/read 精确调用链

`ProgramSwFusePlan` 中每个计划项的 write 链是：

```text
0x151606b  DeviceFuseAccessHandler vtable +0xb8
  -> 0x151ad00
  -> GB202GpuSubdevice vtable +0x238 = 0x0db5540
  -> domain / instance offset translation
  -> GB202GpuSubdevice vtable +0x230 = 0x0dc74f0
  -> ordinary register-write backend
```

紧接着的 readback 链是：

```text
0x1515fb3  DeviceFuseAccessHandler vtable +0xc0
  -> 0x151ad10
  -> GB202GpuSubdevice vtable +0x228 = 0x0db68a0
  -> domain / instance offset translation
  -> GB202GpuSubdevice vtable +0x220 = 0x0dc6f70
  -> ordinary register-read backend
```

GB202 vtable `0x92c8500` 在 `+0x220/+0x228/+0x230/+0x238` 的固定项依次是
`0x0dc6f70/0x0db68a0/0x0dc74f0/0x0db5540`。这证明上述绑定不是从
其他 GPU 世代类比出来的。

`0x0db5540/0x0db68a0` 处理 logical domain 和 instance 偏移。本路径的
domain 参数是 `5`；处理完后分别 tail-call `+0x230/+0x220`。
这两个 wrapper 没有取 `GpuSubdevice+0x6c0` RegHal override，也没有
RegHal descriptor lookup。准确的关系是：**raw 路径与普通 RegHal 共用
GpuSubdevice 底层 slots，而不是 raw 路径先进入 RegHal。**

## 2. ordinary backend 的两个 transport 分支

### 2.1 默认：mapped register aperture

read `0x0dc6f70` 的直接分支在 `0x0dc701b..0x0dc702e`：

```text
base = *(GpuSubdevice+0x128)->mappedBase
value = *(uint32_t *)(base + translatedOffset)
```

write `0x0dc74f0` 的对应分支在 `0x0dc7621..0x0dc7643`：

```text
base = *(GpuSubdevice+0x128)->mappedBase
*(uint32_t *)(base + translatedOffset) = value
```

constructor `0x0df34d0..0x0df3561` 将 `GpuSubdevice+0x19c0..+0x19c2`
初始化为零。解码的 `gpuargs.js:1704` 将 `+0x19c2` 对应的用户
选项命名为 `Gpu.UseRmRegOps`，说明是“在 RM 初始化后用 RM regops
control call 做 register access”。因此默认零值分支是 mapped-aperture
load/store，不是 `EXEC_REG_OPS`。

### 2.2 可选：RM `EXEC_REG_OPS`

`0x0dc6f7e..0x0dc6f99` 和 `0x0dc7546..0x0dc7562` 都要求
`GpuSubdevice+0x19c2 != 0` 且 `+0x19c0 != 0`。满足时：

- read 进入 `0x0dc68d0`，构造单项 READ_32/GLOBAL
  `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS`，然后返回 response 中的
  `regValueLo` (`[rsp+0x24]`)；
- write 进入 `0x0dc73b0`，构造单项 WRITE_32/GLOBAL 的同一
  control ID。

这个选择与 SMC/MIG `SmcRegHal` 是两层不同机制。未分区使
`GpuSubdevice+0x6c0` 保持空、因而取内嵌 ordinary RegHal；但是否
使用普通 backend 自身的 `UseRmRegOps` 可选分支，仍是独立条件。
所以仅凭“未分区”不能把所有配置都等同成 direct MMIO；默认配置
才是 direct mapped aperture。

后续生命周期审计进一步证明：`UseRmRegOps` 对象 byte 构造默认值为 0，RM
phase-ready byte 由正常 init 置 1 并在 teardown 清零；init 本身不会自动打开
`UseRmRegOps`。GB202 的特殊地址 predicate 在 identity translation 下也不匹配
本项目的 latch、PLM 与 raw OPT 地址。因而“普通无显式 flag 时更可能 mapped”
的判断现有了地址级交叉验证；任意实际命令行/remap state 仍未运行观察。详见
`parallel/rmregops_lifecycle.md`。

## 3. metadata predicate 边界

### 3.1 raw 计划项

`0x151ad00 -> 0x0db5540 -> 0x0dc74f0` 没有调用 RegHal
`accessOffset` lookup，也没有调用已知 PLM 公式 helper `0x198a7e0`。
因此对“raw write 前是否有显式 RegHal access/PLM predicate”的回答是
**没有**。

`0x0dc74f0` 会调用 `0x0d9aac0` 查一张通用 register-exclusion /
write-mask range table：返回零时记录 `RegWr32(... ) excluded`，非 `-1`
时先与旧值合并 mask。它是另一层 host register filter，不是
RegHal table 中与目标寄存器配对的 access/PLM metadata，两者不应
混同。

### 3.2 RegHal constant 路径

`0x404f0001` 走的 `0x151b6c0` 确实先用 `0x1986e30` 检查
constant descriptor 是否存在；失败分支只记录 unknown descriptor，不做
寄存器访问。这是 **descriptor-existence predicate**。

ordinary RegHal setter `+0x38 = 0x198b410` 还会读全局
`JsRegHal.RegPrivCheckMode`。非零时它调用 `0x198af70`，后者可通过
`0x198a7e0` 读 access metadata 并计算 PLM predicate。但这个 helper
是 diagnostic/audit 形状：`0x198af70` 不返回一个被 `0x198b410`
消费的 fail-closed status，caller 在它返回后无条件继续到
`0x198b446` 的 read-modify-write 主体。而 raw 计划项连这个可选
RegHal audit 也不经过。

## 4. `0xbadf510c` 的来源

在本调用链中，它只是 caller 识别的一个 32-bit 读值：

- mapped-aperture 分支的值来自 `0x0dc702b..0x0dc702e` 的直接
  32-bit load；
- RM reg-ops 分支的值来自 `0x0dc696b` 读出的 response
  `regValueLo`；
- 两个分支都不比较、替换或构造 `0xbadf510c`；
- `ProgramSwFusePlan` 在 `0x1515fb6` 收到 readback 后才与该常量
  比较。

因此不存在一个可归档为“MODS host-side sentinel generator”的函数地址。
更严格的结论是：**它由所选 backend 以 register value 形式传入 host；
直接分支的下一层是 mapped aperture，control 分支的下一层是
RM response。固定 host ELF 不能再分辨 control 分支中是 RM、GSP 还是
更下层填入了该值。**

后续对 RM helper 与 NVIDIA 公开驱动的交叉核对又证明：helper 会检查
control status 和 response `regStatus`，但其正常/诊断返回尾仍取
`regValueLo`；公开驱动则把 `0xBADxxxxx` 定义为 PRI-read error family，
并存在为保留 `0xBADF41YY` 硬件错误值而特意使用 unchecked/raw read 的
官方路径。因此该值不是 host 私造；精确 `0xBADF51xx` 子类型仍未由公开
Blackwell 头文件解码。详见 `parallel/badf510c_provenance.md`。

## 5. write 返回值如何丢失

raw write call 是：

```text
0x151606b  call *handler+0xb8
0x151606e  mov  [r13], rax       # 立即覆盖 call 后的 RAX
```

没有 `test eax,eax`、没有 store status，也没有把它合并进
`[rsp+0xc]` aggregate status。而且 `0x0dc74f0` 的 direct 分支是
void-style store；RM-control write helper `0x0dc73b0` 虽会在内部检查并记录
control status 和 per-op status，但其函数尾也没有向上层建立稳定的
status return。

所以 `ProgramSwFusePlan` 对 write 结果的 host-visible 判断来自后续
readback，不是 write call 自身的传播状态。

## 6. `0x404f0001` 与 raw 项的共用层

`ProgramSwFusePlan` 在 `0x1515ed8..0x1515eea` 把 `0x404f0001`
交给 handler `+0x78 = 0x151b6c0`。后者的主要步骤是：

```text
GpuSubdevice +0x208                         # 取当前 RegHal
  -> 0x1986e30                             # constant descriptor lookup
  -> 0x1987000 / 0x1983230                 # 解码 field/value
  -> RegHal vtable +0x38
```

内嵌 ordinary RegHal vtable `0x93fadf0` 的 `+0x38` 是 `0x198b410`。
它根据 descriptor 做 read-modify-write：

```text
0x198b4c1  取 GpuSubdevice +0x228
0x198b4fe  read old value
0x198b518  合成 field new value
0x198b525  取 GpuSubdevice +0x238
0x198b565  write new value
```

因此分层结论是：

- raw 计划项：从 handler 直接进 `GpuSubdevice +0x238/+0x228`；
- `0x404f0001`：先经 RegHal constant/field RMW，再进同一组
  `GpuSubdevice +0x228/+0x238`；
- 两者的顶层入口不同，底层 transport family 相同。

`0x1515eea` 的 latch-set call 返回后，`0x1515eed` 直接开始取下一个
对象，同样没有消费 `EAX/RAX`。

## 证据矩阵

| 问题 | 结论 | 等级 |
|---|---|---|
| raw thunk 是否先进 RegHal | 否，直接进 `GpuSubdevice +0x238/+0x228` | **FACT** |
| 普通 RegHal 默认 backend | mapped register aperture load/store | **FACT** |
| 普通 RegHal 可选 backend | `UseRmRegOps && initialized` 时的 global `EXEC_REG_OPS` | **FACT** |
| 未分区是否唯一决定 transport | 否；它决定 ordinary/SmcRegHal，`UseRmRegOps` 是独立层 | **FACT / INFERENCE** |
| raw write 前是否有 RegHal access/PLM predicate | 没有 | **FACT** |
| raw write 是否有其他 host filter | 有通用 exclusion/write-mask table，非 RegHal PLM metadata | **FACT** |
| `0xbadf510c` host generator | 没有；作为 backend read value 进入，caller 只比较 | **FACT（调用链范围）** |
| raw-write status 是否传到 aggregate status | 否，call 后 `RAX` 立即被覆盖 | **FACT** |
| `0x404f0001` 是否同一顶层入口 | 否，它先走 RegHal constant RMW | **FACT** |
| `0x404f0001` 是否汇合到同一底层 read/write family | 是，最终用 `GpuSubdevice +0x228/+0x238` | **FACT** |

# PRC knob `0x1d` 值域与生命周期：最后一轮静态复核

日期：2026-07-21
状态：**final，strict static-only**

## 结论先行

这一轮把 **host 能接受/编码的数值包络**闭合得更精确了，但仍然没有得到
**FSP 对 `0x1d` 的合法值集合**：

| 问题 | 最窄结论 | 等级 |
|---|---|---|
| 目标 ID | `PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT = 0x1d` | **FACT** |
| host 输入类型 | JS `parseInt()` 后进入 ECMAScript `ToUint32` 风格转换 | **FACT** |
| host 可成功回读比较的包络 | 转换后的 `uint32` 必须落在 `0..65535`；这只是 host/wire 必要条件 | **FACT** |
| FSP 合法值 | 未知；不能把上述包络当成 allowed-values | **UNKNOWN** |
| 是否 Boolean / `1=arm` | 很像，但没有 target-specific schema、caller 或 consumer 证明 | **INFERENCE / UNKNOWN** |
| 默认值 | table、JS 和 writer 都没有静态 default；日志中的 `default` 是写前动态读值 | **UNKNOWN** |
| one-shot 如何实现 | wire 没有额外 one-shot/persistence 字段；若实现，只能由 ID/schema/设备侧状态决定 | **FACT（wire）/ INFERENCE（实现位置）** |
| 何时消费/自清 | immediate readback 之前不太可能简单清掉同一可见状态；task 2 之后没有 host read/clear | **INFERENCE / UNKNOWN** |

因此，本轮仍不能认证“写 `1` 会打开一次窗口”，也没有得到可构造的 rearm、
consume 或 self-clear 流程。新增的硬结论主要有两项：native 输入确实执行
`ToUint32` 式归一化；MODS 的错误名 switch 可以把 PRC/floorsweep 相关错误词汇
精确映射到数值 error code，但这些错误码仍没有绑定 `0x1d` 的具体合法值。

## 范围与安全边界

只读取了以下本地固定材料：

- MODS 570.151 ELF：`mods_audit/static/extracted_inner/mods`，392,339,552 bytes，
  SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- 75 个 `mods_audit/static/decoded/**/*.js`；
- NVIDIA Open GPU Kernel Modules 610.43.03：`/usr/src/nvidia-610.43.03`；
- 固定 GSP inner ELF：`/tmp/gsp_inner_19f040_a.elf`，82,577,496 bytes，
  SHA-256
  `bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`；
- 本机已安装但版本不同的 GB202 GSP FMC/bootloader 570.144，以及项目内四个
  canonical GB202 ROM/NVFW 保存样本。

只用了精确文本检索、ELF header、固定 VA 小窗口 `objdump`、4.8 KiB jump-table
读取和有界 direct-call/pointer 扫描。没有运行 MODS，没有访问 GPU、设备节点、
BAR/MMIO、PCI config、debugfs，没有发送 RM/GSP/FSP 消息，没有 reset、rebind、
模块、VBIOS/固件或电源操作，也没有全文件反汇编/Ghidra 导入。

证据等级：

- **FACT**：当前固定 artifact 或指定小窗口直接支持；
- **INFERENCE**：由事实约束出的合理解释，但没有 device-side consumer；
- **UNKNOWN**：当前静态材料不能决定。

## 1. 名称、ID 与 metadata shape

### 1.1 目标记录仍严格绑定到 `0x1d`

MODS constructor 在 `0x18603df..0x186044a` 用 rodata
`0x9224d30`、`0x9224d40`、`0x9224c10` 拼出 44-byte 名称：

```text
PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT
```

`0x1860458` 把 `0x1d` 写入同一条 `rsp+0x4b8` record 的 `+0x20`，即
`[rsp+0x4d8]`。前一条 `RPR_ALLOW_INB` 才是 `0x1c`。

插树循环证明 record 大小为 `0x28`：

```text
+0x00  std::string name  (0x20 bytes)
+0x20  uint32 id
+0x24  padding
```

**FACT：** host table 没有 type、default、allowed-values、range、Boolean、
writable、one-shot 或 persistence flag。

### 1.2 name parser 只做大写和精确 lookup

`gpuargs.js:16481..16487` 的 `ArgFspPrcWrite()`：

```js
obj.knobId = knobId.toUpperCase();
obj.knobValue = parseInt(knobValue);
g_FspPrcWriteArray.push(obj);
return RC.OK;
```

它没有 `isNaN`、range、enum 或 target-specific 检查。native callback
`0x116bd50..0x116c0b6` 取 `knobId` 和 `knobValue`，把转换后的 dword 存到 map
node `+0x40`。writer 再通过 `0x1858280` 做精确 name -> ID lookup；没有 numeric
ID bypass、别名或按 `0x1d` 分支。

## 2. 新增闭合：host 数值归一化与成功包络

### 2.1 native 不是“保留任意 JS Number”，而是转为 `uint32`

callback 在 `0x116bf28..0x116bf46` 调 `0xbe3a90`，随后把输出 dword保存到
map node。`0xbe3a90` 经 thunk `0x24e7df0` 到
`0x252dee0..0x252df11`，先把 JS value 转为 double，再调用
`0x252cce0..0x252ce2b`。

后一小窗口直接显示：

- NaN/Infinity 或零路径把输出置零（`0x252cced..0x252cda4`）；
- 大数用常量 `2^32` 做 `fmod`（`0x252cd3a..0x252cd5c`）；
- 负数路径按模 `2^32` 归一化（`0x252cd70..0x252ce27`）；
- 最终只存低 32 bits（`0x252cd5d..0x252cd64`）。

**FACT：** 这是 ECMAScript `ToUint32` 形状，而不是 `0..65535` range validator。
特别地，JS callback 没检查 `parseInt()` 的 NaN，native conversion 会把非有限结果
归一为零。这个事实只描述 parser，不认证任何输入是安全或受支持的。

### 2.2 wire 截成 `u16`，readback 再与完整 `u32` 比较

generic writer `0x185ef60` 的每个工作项保存：

```text
node+0x10  resolved knob ID (uint32)
node+0x14  requested value after native uint32 conversion
```

当 current != requested 时，`0x185f1c0..0x185f1ff` 只编码四个字节：

```text
[ id low, id high, value low, value high ]
```

随后 `0x185f284..0x185f299` 发送 task `13` / submessage `2`。写后
`0x185f2a6..0x185f2ee` 用 task-12 reader 取得 `u16`，零扩展为 dword，再与
**完整 requested dword** 比较；不等在 `0x185f458..0x185f474` 返回 `0x12f`。

令 native 转换后的值为 `D`：

```text
wire value = D & 0xffff
readback   = zero_extend_u16(...)
success comparison requires readback == D
```

所以：

- **FACT（host 必要条件）：** 通过 generic readback equality 的 `D` 必须属于
  `0..65535`；
- **FACT：** 这不是 FSP allowed-values。FSP 仍可把其中绝大多数值按 knob ID、
  SKU、阶段、policy 或当前状态拒绝；
- **FACT：** 原始命令行文本也不是该包络，先经过 `parseInt` 和模 `2^32`
  归一化。不能把“输入看起来大于 16 位”简单等同于传给 FSP 的数值。

### 2.3 wire tail 固定为零，没有用户控制的 one-shot/persistence mode

task-13 request 的当前可见 body 是 6-byte
`id16 + value16 + zero16`。writer 也只按名称是否含 `ALLOW_INB` 排序；它不检查
`ONE_SHOT`。末尾两字节由 host 固定为零，当前代码没有给它们命名；
`PRC_TASK_PRC_OBJ_WR_INVALID_OPTIONS` 使 options/reserved 解释有可能，但没有
公开 bit 定义。可以确定的是，用户不能通过这条路径附加 clear-on-use、
persistence、lease、generation 或 rearm flag。

**FACT（host ABI）：** one-shot 不是一枚独立 host request bit。

**INFERENCE：** 如果 `0x1d` 确实按 one-shot 工作，FSP/硬件只能从 knob ID 的
私有 schema、当前 lifecycle、固定 tail 的私有含义或另一份内部状态知道该语义；
host 没有发送用户选择的 one-shot mode。

## 3. 默认值仍然没有闭合

### 3.1 空数组只代表 host 不主动写

`gpuargs.js:251` 把 `g_FspPrcWriteArray` 初始化为空；
`HandleGpuPreInitArgs()` 仅在数组非空时调用 `SetFspPrcWriteInfo()`。75 个 decoded
JS 中，完整目标名、`FLOORSWEEPING_ALLOW_INB_ONE_SHOT`、
`ALLOW_INB_ONE_SHOT` 和 `ONE_SHOT` 都没有 target-related caller 命中。

**FACT：** stock decoded JS 不自动注入目标项。
**UNKNOWN：** 这不说明 FSP 的 reset/power-on/current value 是 0、1 或其他值。

### 3.2 日志中的 `default` 是动态 current

format `0x8c92bd8`：

```text
Before Write PRC, default PrcKnob Value= 0x%x for knob %s (knobId %u)
```

但代码在 `0x185f336..0x185f356` 先实际 task-12 read，再把读值传给该日志
（`0x185f35b..0x185f373`）。没有 table/default constant 参与。

**FACT：** 这里的 `default` 只是“写前 current”的日志措辞。

## 4. 新增闭合：PRC 错误字符串的数值映射

### 4.1 这是 error-code switch，而非散落的无主字符串

函数 `0x1858480..0x185a7b4` 直接比较 `edx <= 0x257`，随后按
`[0x930de00 + edx*8]` 跳转。wrapper `0x185a7c0` 调它并用格式
`"0x%x:%s\n"` 输出 numeric code 和字符串。

读取这张仅 `0x258 * 8 = 0x12c0` bytes 的固定 jump table，可得到：

| error code | MODS 名称 |
|---:|---|
| `0x0af` | `PRC_TASK_FLOORSWEEPING_INVALID_OPTIONS` |
| `0x1e0` | `PRC_TASK_PRC_OBJ_WR_INVALID_OPTIONS` |
| `0x1e3` | `PRC_ERROR_INVALID_KNOB_ID` |
| `0x1e4` | `PRC_ERROR_PERSISTENCE_NOT_SUPPORTED` |
| `0x1e5` | `PRC_ERROR_PERSISTENCE_NOT_ALLOWED` |
| `0x1e6` | `PRC_ERROR_PERM_KNOB_ID_INVALID` |
| `0x1e8` | `PRC_ERROR_FEATURE_NOT_ALLOWED` |
| `0x1ea` | `PRC_ERROR_PERMISSION_KNOB_ID_INVALID` |
| `0x223` | `INVALID_PRC_KNOB_VALUE` |
| `0x23a` | `PRC_ERROR_INVALID_KNOB_VAL` |

公开 610 的 `kern_fsp_retval.h:29` 同样定义
`FSP_ERR_PRC_ERROR_INVALID_KNOB_ID = 0x1e3`，与 switch 精确相符。这加强了“表
index 是 firmware error code”的识别。

### 4.2 这些错误名能证明什么、不能证明什么

**FACT：** 当前 firmware family 的 host error vocabulary 容纳：invalid knob ID、
invalid knob value、permission-knob ID、feature policy 和 persistence policy。
这直接否定“wire 是 16 bit，所以所有值都合法”的外推。

**FACT：** `0x0af` 是 floorsweep **task options** 错误，`0x1e0` 是 PRC object
write **options** 错误；它们不是名为 `0x1d_INVALID_VALUE` 的 per-knob schema。
当前 6-byte writer payload 的末尾 `zero16` 可能是 options/reserved，但值固定为
零且字段名未知；它不是可由用户选择的独立 mode。

**UNKNOWN：** `0x223` 与 `0x23a` 属于哪个 generation/dispatcher、GB202 是否会对
`0x1d` 返回其中之一、什么具体值触发，以及 target 的 allowed-values。错误名表
是诊断词汇，不是校验表。

## 5. callers 与自动注入边界

对 `.text` 中 `call rel32 -> 0x185ef60` 的有界精确扫描只有四个 caller：

| call site | 可见用途 |
|---:|---|
| `0x123fcd4` | 通用用户/脚本 name -> value map |
| `0x1ebc909` | `PRC_KNOB_ID_IST = 1` |
| `0x1ef55c3` | `PRC_KNOB_ID_CCD = 1` |
| `0x1ef6128` | `PRC_KNOB_ID_CCD = 0` |

read executor `0x185f500` 的 direct caller 只有 `0x1ef5d97`；name resolver
`0x1858280` 只由 write/read executor调用。

**FACT（direct-call 边界）：** 没有专用 caller 构造 floorsweeping one-shot
名称，也没有 caller 以目标 ID 选择 Boolean 0/1。

**UNKNOWN：** 动态间接 caller、未包含模块、私有脚本或 FSP boot initialization；
不能把 direct-call negative 扩成全系统不存在目标状态。

IST/CCD 的 1/0 只属于普通 action knob；公开 GH100 PPCIE 路径也只对另一个
knob `0x2d` 明确规定 value `1` 为 ON。它们使 `1=arm` 成为自然类比，但都不是
`0x1d` 的 validator。

## 6. public 610 与固定 GSP/FSP artifact 的最后边界

### 6.1 Open GPU Kernel Modules 610.43.03

对当前 C/H 树的精确检索仍为：

```text
PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT  0 files
FLOORSWEEPING_ALLOW_INB                       0 files
ALLOW_INB_ONE_SHOT                            0 files
PRC_TASK_FLOORSWEEPING_INVALID_OPTIONS        0 files
INVALID_PRC_KNOB_VALUE                        0 files
PRC_ERROR_INVALID_KNOB_VAL                    0 files
```

公开树只提供：

- `NVDM_TYPE_PRC = 0x13`；
- `FSP_ERR_PRC_ERROR_INVALID_KNOB_ID = 0x1e3`；
- GH100-only PPCIE knob `0x2d` read-object 先例，其 caller把 `value == 1` 当 ON。

**FACT（当前公开树）：** 没有 `0x1d` schema、默认值、write validator、task-2
consumer 或 self-clear/rearm 状态机。

### 6.2 固定 610 GSP inner ELF

对整个固定 GSP ELF 精确检索以下完整 token，全部零命中：目标全名、
`FLOORSWEEPING_ALLOW_INB`、`ALLOW_INB_ONE_SHOT`、`ONE_SHOT`、上述两种
invalid-value 名、floorsweep invalid-options 名以及两种 persistence error 名。

`strings` 中少量混合大小写 `Prc`/`KNOb` 碎片没有稳定单词边界，属于高熵/随机
字节命中，不能作为 PRC consumer。

**FACT（literal/xref 边界）：** GSP 没有目标 literal，因此不存在可从目标
字符串出发的有界 PC-relative xref anchor。
**UNKNOWN：** stripped GSP 可完全按 numeric task/ID 处理；字符串零命中不证明
不存在相关 host transport，更不证明 FSP 内部语义。

### 6.3 GB202 FMC/bootloader 与 VBIOS FSP 保存样本

对解压后的 GB202 570.144 FMC（199,820 bytes；SHA-256
`cb59a35c1d4bd1274d7267fd10243c29f843ff41c851b9cbd59f5af2ddd7fece`）和
bootloader（200,812 bytes；SHA-256
`d40b48e431d1707dc77af3605db358ed7a32ebfc2830eb74de2eddb4d3025071`）做同组
exact-token 检索，均为零。这两项本来就是启动组件，且版本与 MODS/GSP 不同，
不能当作 private FSP runtime consumer 的完整代码。

项目内四个 canonical GB202 ROM/NVFW 整文件也没有这些 exact token。已有 Falcon
v6 inventory 把 `app=0x24/target=0x0f` 条目标为 `encrypted` flag，并观察到目标
region 为高熵字节；GeForce 两样本共享一组 region，两个 Pro revision各自不同。

**FACT（可见字节）：** 当前保存的目标 FSP region 没有可用 plaintext 名称/xref。
**UNKNOWN：** 加密/高熵 payload 解开后的 consumer、校验表、默认值和 lifecycle。

所以“继续扫字符串”这条路线已经到边界：真正缺失的是可审计的 FSP plaintext 或
官方 schema，而不是另一个 host-side名称命中。

## 7. one-shot lifecycle：新增约束，但仍未闭合

### 7.1 已闭合的 host 时序

在普通成功路径、且显式提供 write map 时：

```text
task 12: read current 0x1d
if current != requested:
    task 13/submessage 2: write id16+value16+zero16
    task 12: immediate readback and compare
ProcessFloorsweepingArgs
conditional task 2/subobject 1
only after zero status: pending host floorsweep apply
optional post-FS reset
```

没有 write map 时，正常首次初始化仍可能发送 task 2；反过来，PRC write 成功也
不保证 task 2 一定被后续门控允许。task 2 payload不携带 `0x1d` 或 requested
value。

**FACT：** host 只闭合了“可选 write/readback 在条件 task 2 之前”，没有闭合
`task13 -> task2` 的必然 consumer dataflow。

### 7.2 immediate readback 的约束

如果 task-12 readback 直接反映同一个 permission state，那么成功 write 不会在
紧接着的 readback **之前**简单自清，否则 generic writer 会报 mismatch。

但 readback 可能只是配置/影子值，内部 armed/consumed state 也可能另存。因此：

- **INFERENCE（有前提）：** 简单“写完立即把同一可见位清零”不符合 host成功流；
- **UNKNOWN：** permission 是否已经在内部 latch、readback 后何时 consume。

### 7.3 read-if-equal skip 对重复 rearm 的额外约束

writer 在 current == requested 时完全跳过 task 13。由此可得一个新的设计一致性
约束：

- 如果目标要靠同一 generic path、用同一 requested value反复 rearm，且 consume
  后 readable value仍保持原值，那么下一次 host 会把它误判为“已经设置”而不发
  write；
- 因而在这种特定设计假设下，readable current 需要能区分 consumed/unarmed 与
  armed，或者 rearm 根本不靠重复同值 write。

这是 **INFERENCE**，不是“已证明 task 2 后读回 0”。也可能存在影子值、内部
generation、session-only semantics、一次初始化只使用一次，或完全不同的 FSP
状态机。

### 7.4 task 2 后没有观察点

可见 host 在 task 2 后：

- 不读 `0x1d`；
- 不写 `0x1d=0`；
- 不接收 permission token、remaining-use count、lease、expiry 或 undo handle；
- post-FS reset 的存在也没有公开说明它是 consume、restore 还是只为其他
  floorsweep/PRC 状态生效。

**UNKNOWN：** 消费单位是 task dequeue、ack、首个受保护写、host apply、整个 init
phase、timer、reset 还是别的事件；失败/重试是否保留额度；何时 self-clear/rearm。

## 8. 最终 FACT / INFERENCE / UNKNOWN

### FACT

1. 目标 host ID 是 `0x1d`；metadata 只有 name+ID。
2. JS 只 `toUpperCase()+parseInt()`，没有 target-specific/NaN/range validator。
3. native 将 JS Number 按 `ToUint32` 形状归一化；NaN/Infinity -> 0，其他数按
   模 `2^32` 落到 dword。
4. wire value 是低 16 bits；readback 是零扩展 `u16`，再与完整 dword比较。
   因此 `D <= 0xffff` 是 host成功的必要条件，但不是 FSP合法域。
5. task-13 payload 是 `id16+value16+zero16`；tail 固定为零且字段名未知，没有
   用户控制的 one-shot/persistence flag。
6. writer 先读、不同才写、立即读回；同值时跳过 write。
7. stock JS 默认不注入 `0x1d`，direct caller 扫描也没有专用 target caller。
8. error-name switch 精确给出 PRC invalid-value、permission 与 persistence 错误码；
   它是错误词汇，不是 target schema。
9. 公开 610、固定 GSP literal、FMC/bootloader 和保存的高熵 FSP region都没有
   target schema/consumer plaintext。
10. task 2 可无 host `0x1d` write，write 也不保证 task 2；task 2 后 host 不读/清
    目标项。

### INFERENCE

1. `ALLOW_INB_ONE_SHOT` 很像 Boolean permission，`1=arm` 是自然候选，但未认证。
2. one-shot 若真实存在，其语义由 FSP per-ID schema/内部状态决定，而非额外 wire
   flag。
3. 若 readback 是实际 permission state，简单 self-clear 不会早于 immediate
   readback。
4. 若同一路径需要重复同值 rearm，consume 后 readable state应改变；否则
   read-if-equal 会抑制下一次 write。这只是设计约束，不是已观察自清。

### UNKNOWN

1. `0x1d` 的 FSP合法值、是否只有 0/1、`1` 是否 grant；
2. power-on/reset/current/post-consume default；
3. GB202 production FSP 是否支持、允许写或要求这个 knob；
4. task 2 是否查询/消费它以及消费事件；
5. visible readback 与内部 permission latch 是否同一状态；
6. self-clear、rearm、failure/retry、session、timer 和 reset lifetime；
7. private encrypted FSP consumer与逐 knob validator。

## 9. 可供主报告采用的最窄措辞

> MODS 570.151 把 `0x1d` 当作 generic `uint16` PRC value传输，但 JS/native
> 前端并没有 target-specific schema：输入先归一为 `uint32`，wire value 只发送低
> 16 bits，另带固定 `zero16` tail；随后用 `u16` readback 与完整 dword比较。因此
> `0..65535` 只是 host
> 成功包络，不是 FSP allowed-values。名称与时序支持 Boolean one-shot permission
> 的解释，但 required value、default、task-2 consume 和 self-clear仍因 private
> FSP consumer不可见而 UNKNOWN。

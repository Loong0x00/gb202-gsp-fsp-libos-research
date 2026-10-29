# MODS 570.151 PRC knob `0x1d` 值与 one-shot 消费语义审计

日期：2026-07-21
状态：**final，strict static-only**

## 结论先行

目标项的 host-table 身份已经确定：

```text
0x1c  PRC_KNOB_ID_RPR_ALLOW_INB
0x1d  PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT
0x1e  PRC_KNOB_ID_HBM_FREQ_CHANGE_ALLOW_INB
```

但“名字里有 `ALLOW`/`ONE_SHOT`”不能补出设备侧 schema。当前最严格的直接回答是：

| 问题 | 结论 | 等级 |
|---|---|---|
| `0x1d` 的 FSP 合法值集合 | **未知**；host wire value 是 16 bit，但这不是 allowed-values | **UNKNOWN** |
| 默认值 | **未知**；JS write array 默认空只表示“不发 host 写请求” | **UNKNOWN** |
| 是否 Boolean、`1` 是否 grant | **未证明**；`1` 是合理候选，但只能来自名称和别的 knob 类比 | **INFERENCE / UNKNOWN** |
| 是否按 one-shot 实现 | 名称明确含 `ONE_SHOT`；host 没有 one-shot flag/validator/clear | **FACT（名称）/ UNKNOWN（实现）** |
| 是否 consume-once | host 看不见消费动作，也不在 task 2 后读取 `0x1d` | **UNKNOWN** |
| task 13 write 后 task 2 如何消费 | **没有可见 host dataflow，也没有 GB202 FSP consumer**；若有消费，只能是 FSP/硬件读取此前状态的内部副作用 | **INFERENCE / UNKNOWN** |
| `task13 write => task2 consume` 是否必然 | **否，不能这样写**；task 2 可在没有 host PRC write map 时发送，两步也各有独立门控 | **FACT（host 控制流）** |

因此本报告没有认证 value `1` 为合法或安全值，也没有得到可构造的
consume/rearm 流程。

## 范围与安全边界

只读取以下本地材料：

- MODS ELF：`mods_audit/static/extracted_inner/mods`，大小 `392339552`，SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- 75 个 `mods_audit/static/decoded/**/*.js`；
- NVIDIA Open GPU Kernel Modules 610.43.03：`/usr/src/nvidia-610.43.03`；
- `mods_audit/nvapi_610_raw.md` 和现有项目报告。

二进制取证只用了字符串、原始小窗口和指定 VA 的小窗口 `objdump`；每次二进制
反汇编均加 `ulimit -v 262144` 与短 timeout。没有运行 MODS，没有访问 GPU、设备
节点、BAR/MMIO、PCI config、debugfs 或网络；没有发送 FSP/RM 请求，没有 reset、
驱动/模块或固件操作；没有做全文件反汇编、Ghidra 导入或大内存扫描。

证据标签：

- **FACT**：当前文件、指定地址窗口或明确限定的负检索直接支持；
- **INFERENCE**：事实支持这种解释，但没有 device-side consumer；
- **UNKNOWN**：当前静态材料不能决定。

## 1. 身份与 host-table shape

### 1.1 `0x1d` 绑定是 FACT

MODS table constructor 的目标 record 基址是 `rsp+0x4b8`：

- `0x18603df..0x186044a` 用 rodata 块 `0x9224d30`、`0x9224d40`、
  `0x9224c10` 拼出 44-byte
  `PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT`；
- `0x1860458` 把 `0x1d` 写到同一 record 的 `+0x20`，即 `[rsp+0x4d8]`；
- `0x18603d4` 的 `0x1c` 写在前一条 record `rsp+0x490` 的 `+0x20`，属于
  `PRC_KNOB_ID_RPR_ALLOW_INB`。

插树循环 `0x1860a60..0x1860aab` 独立确认 layout：它从 record `+0x00/+0x08`
复制 string，在 `0x1860a8a` 只读 `dword [record+0x20]`，把它存入 node
`+0x40`，然后 `record += 0x28`。所以每条可见 metadata 只有：

```text
+0x00  std::string name  (0x20 bytes)
+0x20  uint32 id
+0x24  padding
```

**FACT：** 这个表没有 type、default、allowed-values、min/max、writable、
Boolean、one-shot 或 persistence flag。完整相邻记录重建也见
`parallel/prc_knob_metadata.md:22-65`。

### 1.2 host 表存在不等于 GB202 FSP schema 已公开

这张表证明 MODS 570.151 能把名称解析成 wire ID `0x001d`；它不证明 production
GB202 FSP 一定支持该对象、允许修改它或采用与 MODS 相同的 per-knob policy。
设备侧存在性、校验和消费仍要由 FSP response/consumer 决定。

## 2. 合法值：只能确定 host 编码包络，不能确定 FSP allowed-values

### 2.1 decoded JS 没有值域或 Boolean 校验

两个 `gpuargs.js` 副本 SHA-256 均为
`14b37e0792addab7c5eb770509bfd85bd59553de2e076a2a8637a0d812397c16`。
75 个 decoded JS 中以下 token 均为零命中：完整目标名、
`FLOORSWEEPING_ALLOW_INB_ONE_SHOT`、`ALLOW_INB_ONE_SHOT`、`ONE_SHOT`。

可见 JS 只做：

- `gpuargs.js:251-252`：write/read arrays 初始化为空；
- `gpuargs.js:1710-1711`：注册泛型 knob-name/value 与 knob-name 参数；
- `gpuargs.js:7362-7369`：数组非空才交给 native；
- `gpuargs.js:16481-16487`：`knobId.toUpperCase()`、`parseInt(knobValue)`、push，
  随后无条件 `RC.OK`。

**FACT：** JS 没有为 `0x1d` 执行 Boolean、enum、range、非负或 `isNaN` 校验。
这只说明前端宽松，不表示 FSP 接受任意值。

### 2.2 native executor 的 wire width 与成功条件

native callback `0x116bd50..0x116c0b6` 把 `knobValue` 保存为 map node
`+0x40` 的 32-bit dword。通用 executor `0x185ef60`：

1. `0x185f074..0x185f088` 只做 name -> ID；
2. `0x185f090..0x185f0b4` 唯一的名称分类是查找 9-byte `ALLOW_INB`，用于排序；
   没有查找 `ONE_SHOT`；
3. `0x185f336..0x185f37b` 先从 FSP 读取当前值；
4. current != requested 时，`0x185f1c0..0x185f27f` 编码
   `[id_lo,id_hi,value_lo,value_hi,0,0]`；末尾 `zero16` 由 host 固定，字段名未知；
5. `0x185f284..0x185f299` 发送 task `13` / submessage `2`；
6. `0x185f2a6..0x185f2ee` 再读同一 ID，把返回 `u16` 零扩展后与完整 requested
   dword 比较；不等时 `0x185f458..0x185f474` 返回 `0x12f`。

由此可精确区分：

- **FACT（ABI）：** ID 和 value 在线上各为 16 bit，read 值也是 `u16`；
- **FACT（host 成功的必要条件）：** 若 native map 中 requested dword 的高 16 位
  非零，发送时会截断，而 readback 只会零扩展 `u16`，generic executor 不可能
  通过完整 dword 相等校验；
- **UNKNOWN（合法域）：** `0..65535` 只是 host 可编码/可能通过 readback 的包络，
  不是 `0x1d` 的合法值集合。FSP 可按 ID、SKU、lifecycle、policy 或当前状态拒绝。

### 2.3 MODS 自带错误词汇反而要求保留 FSP validator 边界

同一 MODS artifact 含以下明文错误名：

| file offset | 字符串 |
|---:|---|
| `0x0888f908` | `PRC_TASK_FLOORSWEEPING_INVALID_OPTIONS` |
| `0x08891670` | `PRC_TASK_PRC_OBJ_WR_INVALID_OPTIONS` |
| `0x088916e8` | `PRC_ERROR_PERSISTENCE_NOT_SUPPORTED` |
| `0x08891710` | `PRC_ERROR_PERSISTENCE_NOT_ALLOWED` |
| `0x08cfbdcc` | `INVALID_PRC_KNOB_VALUE` |
| `0x08cfbef2` | `PRC_ERROR_INVALID_KNOB_VAL` |

**FACT：** artifact 的通用/multi-generation 错误词汇明确容纳 invalid value、
invalid options 与 persistence policy。

**UNKNOWN：** 当前没有把这些字符串中的某个错误号绑定到 GB202 的 knob `0x1d`
或某个具体输入值；它们不能反推出 allowed-values。其正确用途只是阻止“16-bit
所以所有值合法”这种外推。

## 3. 默认值：两种容易混淆的“default”都不是 knob default

### 3.1 空 JS array 不是默认值

`g_FspPrcWriteArray = new Array` 只证明无显式参数时 host 不构造 write map。
现有 decoded JS 也没有第二个 push 或目标名称，故普通可见前端不会自动注入
`0x1d`。这不说明 FSP 中该 knob 是 0、1、未实现、持久保存或按 SKU 初始化。

### 3.2 writer 日志中的 `default` 实为动态 current read

format string VA `0x8c92bd8` 是：

```text
Before Write PRC, default PrcKnob Value= 0x%x for knob %s (knobId %u)
```

但 `0x185f336..0x185f356` 先主动读 FSP，随后才在
`0x185f35b..0x185f373` 用该 format 打印读回值。代码没有从表或常量取得 factory、
reset 或 schema default。

**FACT：** 这里的 `default` 只是日志对“写前 current value”的称呼。

**UNKNOWN：** `0x1d` 的 power-on、post-reset、post-consume、persistent 或当前卡
实际值全部未知。

## 4. Boolean 与 `1`：合理候选，不是已证合法值

### FACT

- 目标名称含 `ALLOW_INB_ONE_SHOT`，但 table/executor 没有 Boolean type；
- `WriteIstPrcKnob()` 在 `0x1ebc7f0..0x1ebca2a` 对另一个普通 knob
  `PRC_KNOB_ID_IST` 使用 1/0；decoded JS
  `mathslink_args.js:190` 也把这一路描述为 enable/disable；
- CCD 专用 callers 在 `0x1ef559d`、`0x1ef6100` 对另一个普通 knob
  `PRC_KNOB_ID_CCD` 使用 1/0；
- 这些专用 callers 都不写对应 `*_ALLOW_INB`，也不写 floorsweeping `0x1d`；
- 公开 610 的 GH100 PPCIE caller 只对另一个 knob `0x2d` 明确规定
  `knobValue == 1` 为 ON
  (`kern_gpu_gh100.c:542-565,575-603`)；generated HAL 只把该实现绑定 GH100
  (`g_gpu_nvoc.c:2417-2432`)，其余走返回 `NV_FALSE` 的 stub
  (`g_gpu_nvoc.h:5443-5445`)。

### INFERENCE

`ALLOW` 加 `ONE_SHOT` 很像一枚 Boolean permission，值 `1` 很像 arm/grant。
IST、CCD 和 PPCIE 的 0/1 用法让这个候选更自然。

### UNKNOWN

没有任何 target-specific caller、schema、validator 或 FSP consumer把
`0x1d: 0/1` 定义为 false/true；也不能排除 enum、bitfield、generation counter、
permission class 或保留值。故不得把“很像 Boolean”写成“合法值是 0/1”或
“正确写值是 1”。

## 5. `ONE_SHOT` 与 consume-once：名称事实不等于状态机事实

### 5.1 host 如何对待 `ONE_SHOT`

**FACT：** `ONE_SHOT` 只存在于构造出来的名称字节中。resolver 返回 ID；writer
只按 `ALLOW_INB` 分组，随后走与 IST/CCD 等相同的 generic
read-if-different/write/readback 流程。没有 host one-shot flag、decrement、clear、
rearm、expiry 或 consume counter。

**INFERENCE：** 名称及同一 artifact 中的 persistence 错误词汇支持“设计上有
one-shot 与 persistent policy 区分”。它们仍不能说明 one-shot 是“一次 task”、
“一次 protected write”、“一个 init phase”还是“一次 reset session”。

### 5.2 immediate readback 给出的唯一时序约束

task 13 返回后，host 在进入 floorsweep/task 2 前立即用 task 12 读回，并要求值
等于 requested。因而：

- **INFERENCE（有前提）：** 如果 task-12 readback 直接反映同一个实际状态位，
  一个成功的 generic write 不应在这次 readback 前简单自清；
- **UNKNOWN：** readback 也可能返回配置/影子值，而真正的 permission latch、
  consumed bit 或 generation state 是另一份 FSP 内部状态。故上述约束不能证明
  task 2 前仍 armed，更不能证明 task 2 后自清。

### 5.3 host 看不到消费结果

正常 FS 路径在 task 2 后没有显式写 `0x1d=0`，也没有再次读取 `0x1d`。task-2
调用的 response-vector 参数为 null；host 只得到 status，没有保存 permission
token、cookie、remaining-use count、expiry 或 undo handle。

**FACT（host negative）：** consume/clear/rearm 不在当前可见 host 代码中。

**UNKNOWN：** FSP/ROM/硬件是否按 dequeue、command ack、首个受保护寄存器写、
host floorsweep apply 完成、timer、init phase、reset 或其他状态机消费/恢复。

## 6. task 13 write 与 task 2：闭合的是先后顺序，不是 consumer dataflow

### 6.1 条件化 host 时间线

普通 FSP-enabled、`SkipFspFs=0`、FS 尚未 initialized、相关调用均成功时，可见
顺序是：

```text
Gpu::Initialize
  optional PRC write map                        0xda39e4..0xda3a06
    task 12: read current                       0x185f336..0x185f37b
    if different:
      task 13 / submessage 2: write             0x185f1c0..0x185f299
      task 12: immediate readback               0x185f2a6..0x185f2ee
  ProcessFloorsweepingArgs                      0xda3b80
  generic FS dispatcher                         0x1095e50
    conditional GB20xFs +0x520                 0x10960cc
      task 2 / subobject 1                     0x106c570..0x106c58c
    only after zero status: pending host apply  0x1096228..0x1096231
```

`0x106c587` 调 common sender 时，显式实参是 task `2`、subobject `1`、独立
floorsweep payload vector、null response vector。它不从 task-13 request 复制
`0x001d` 或 requested value。

### 6.2 两步共享 QCAP family，不代表 task 2 消费 `0x1d`

task 13 的 capability check 在 `0x185e490`，task 2 的 check 在 `0x185e530`；
mapper `0x1857b10..0x1857b46` 对 task 2 与 task 13 都返回 QCAP key `0x13`。
公开 610 的 `nvdm_format.h:43-50` 把 `0x13` 定义为 `NVDM_TYPE_PRC`。

**FACT：** 两步共享的是 PRC message-family capability。它不提供 per-knob
dependency edge，不表示 task identity 相同，也不表示成功写 `0x1d` 创造了新的
task-2 capability；QCAP 在 `0xda3654` 已预取。

### 6.3 两个反例排除“必然 consume 链”

1. **task 2 无 task 13：** `g_FspPrcWriteArray` 默认空。首次、无 floorsweep
   参数、正常 FSP 路径仍可到达 task 2；pending 为 0 时只跳过后续 host apply。
   因此每次 task 2 前都由 host 写 `0x1d` 是 false。
2. **task 13 无 task 2：** PRC map 处理和 FS sender 有独立条件。task 13 只在
   current != requested 时发生；后续 task 2 又受 `doFsp`、feature、
   `SkipFspFs`、initialized 和错误状态门控。成功 PRC write 本身不保证随后一定
   发送 task 2。

所以“task 13 write 后 task 2 如何消费”的精确答案是：

- **FACT：** host 先完成独立 write/readback transaction，再可能发送独立 task 2；
- **FACT（bounded negative）：** task-2 sender 不读取 host knob map、ID 或 value；
- **INFERENCE：** 若 `0x1d` 的名称确实描述 task-2 gate semantics，唯一合理的连接是
  FSP 在处理 task 2 时内部查询/消费此前 armed 的 PRC 状态；
- **UNKNOWN：** 当前没有 GB202 FSP 指令体/dispatcher 来证明该查询存在，也不知
  消费点、是否 required、失败是否保留额度、重试是否重用、何时 rearm/self-clear。

## 7. 公开 610.43.03 的严格边界

对以下 610 C/H 树共 3660 个文件做限定 token 检索：

- `/usr/src/nvidia-610.43.03/src/nvidia`
- `/usr/src/nvidia-610.43.03/src/common`
- `/usr/src/nvidia-610.43.03/kernel-open`

完整目标名、`FLOORSWEEPING_ALLOW_INB`、`ALLOW_INB_ONE_SHOT`、
`task[ _-]?2`、`subobject[ _-]?1` 均为零文件命中。

公开树能证明的只有协议边界：

- `nvdm_format.h:43-50`：`NVDM_TYPE_PRC=0x13`；
- `kern_gpu_gh100.c:542-603`：GH100-only PPCIE read-object 先例使用
  `NvU16 knobId`/`NvU16 knobValue`；它不能给 `0x1d` 定义值；
- `kern_fsp_retval.h:24-29` 与 `kern_fsp_gh100.c:1583-1608`：公开 host 只把
  PRC invalid-knob-ID `0x1e3` 特判为 `NV_ERR_INVALID_ARGUMENT`，其他未知 FSP
  error 落 generic；这不表示没有 private invalid-value policy；
- `nvdm_payload_cmd_response.h:35-42`：通用 response 只有 taskId/type/error，
  没有 subobject、lease、consume count 或 restore handle；
- `kern_fsp_gb202.c:50-61`：GB202 的 FSP 由 chip reset 后 Bootfsm 启动，公开 host
  只等待 boot complete。当前 OpenRM/GSP host 材料不是 FSP runtime consumer。

`mods_audit/nvapi_610_raw.md` 对 `PRC/FSP/knob/floorsweep/one-shot/task2` 零命中；
该文件没有补充值或消费语义。

**FACT（公开材料负结果）：** 610 host source 没有目标 schema、task-2 consumer
或 consume/clear/rearm 实现。

**UNKNOWN：** private GB202 FSP firmware 的真实实现。

## 8. 最终 FACT / INFERENCE / UNKNOWN

### FACT

1. MODS 570.151 的目标 host ID 是 `0x1d`，不是 `0x1c`。
2. host table 只有 name+ID；JS/native 都没有 target-specific value validator。
3. task-13 vector 为 `id16+value16+zero16`，其中 tail 固定为零；value/readback
   为 `u16`，generic executor 发送 task 13 后立即 task-12 readback，并比较完整
   requested dword。
4. JS 默认 write array 为空；空数组不等于 knob default。
5. writer 日志所谓 `default` 是动态 pre-write current read，不是静态 default。
6. `ONE_SHOT` 只在名称中；host 不执行 clear/consume/rearm。
7. 可选 PRC transaction 在条件 task 2 之前；task 2 payload 没有显式携带
   `0x1d`/requested value。
8. task 2 与 task 13 共享 QCAP `0x13`，仅证明共享 PRC capability family。
9. task 2 可在没有 host `0x1d` write 的首次正常初始化发送；两步不是必然配对。
10. host 在 task 2 后不读/清 `0x1d`，response 也没有授权/消费 token。

### INFERENCE

1. 名称、前置位置、PRC capability context 和 floorsweep 错误词汇共同支持：
   `0x1d` 意在准备某种一次性 floorsweep in-band permission。
2. `ALLOW` 使 Boolean/`1=arm` 成为自然候选，但类比不足以认证它。
3. 若 task 2 真消费该 permission，连接一定在不可见 FSP/硬件内部，而非 host
   将 task-13 payload 转交 task 2。
4. 若 task-12 readback 等于实际 permission 状态，简单 self-clear 不会早于
   task 13 后的即时 readback。

### UNKNOWN

1. `0x1d` 的合法值集合、默认值、当前值、是否 Boolean、`1` 是否 grant；
2. GB202 FSP 是否允许写、是否要求该 knob、task 2 是否实际检查/消费它；
3. one-shot 的单位与消费点：command、ack、首写、host apply、phase、timer、reset；
4. self-clear/rearm、失败/重试、persistence、session 和 reset lifetime；
5. FSP-side consumer、device-side readback 是否代表 permission latch 本身。

## 9. 措辞约束

后续文档可以写：

> MODS host 顺序闭合为“可选 `0x1d` task-13 write/readback，随后条件 task 2”；
> 名称支持 one-shot permission 的用途推断，但值、Boolean 类型、task-2 consume
> 和 self-clear 均未由 GB202 FSP consumer 证明。

不应写：

- “`0x1d` 的合法值是 0/1”；
- “写 1 就打开一次窗口”；
- “task 2 必然消费并自清”；
- “每次 task 2 前都会写 `0x1d`”；
- “task 2 返回成功证明 grant 尚未被消费”。

主报告现已把相关标题和结论修正为：只有 **host-visible placement/order**
闭合；合法值、Boolean 类型、必需性以及 FSP consume/self-clear 均未闭合。

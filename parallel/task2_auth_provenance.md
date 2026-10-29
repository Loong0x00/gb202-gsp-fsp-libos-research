# GB202 `SetSwFuses` / FSP task 2：授权来源、生命周期与校验时序静态审计

日期：2026-07-21
状态：**final，strict static-only**

## 结论先行

这次审计最重要的结果，是把 H/F1/F2/D 四种容易混在一起的 gate/result/state
彻底分开：

| 层次 | 可见权威来源 | 检查点 | 当前结论 |
|---|---|---|---|
| H：MODS process-local 写入门 | 进程全局 `SecurityUnlockLevel` | `ProgramSwFusePlan 0x1515ea0` 入口要求 `>3` | **FACT：** host 启动时由本地 bypass-record 分类与 NVIDIA-network TLS Boolean 组合；不是 GPU/FSP 回包或设备授权 |
| F1：FSP task-family capability | FSP QCAP cache 中是否存在 key `0x13` | task-2 packet 构造/发送前 | **FACT：** 来源是 FSP capability query；只测 presence，不是 credential、grant 或 PLM snapshot |
| F2：具体 task-2 completion | FSP command response/status | packet 已发送后、host apply 前 | **FACT：** host 只得到同步 completion/error status；不是 device permission-state proof |
| D：`d0/dc/f8` device PLM state | 不可见 GB202 consumer / 未读取 current words | FSP/硬件内部 | **INFERENCE：** task 2 旨在准备 `d0/dc`；**UNKNOWN：** actual effect/lifetime，且独立 `f8` 无同等级旁证 |

由此可直接回答：

1. **`SetSwFuses` 的 process-local `SecurityUnlockLevel > 3` 与 task 2 是两道
   正交门。** task 2 不接收、不传输、也不生成 `SecurityUnlockLevel`；task-2
   status zero 也不会提升该 host value，更不证明 device PLM 已开放。
2. **普通 `SetSwFuses` 并不调用 task 2。** task 2 属于较早的 GB20x GPU
   initialization/floorsweep 生命周期；direct-shadow writer 后来只读取已存在的
   process-local value，并尝试 latch/raw access。把二者画成“SetSwFuses 发 task 2 获得
   token，再写 L2”是不符合当前控制流的。
3. **没有可见的签名会话凭据被带进任一路径。** NVIDIA-network 探测确实验证
   TLS server certificate，但最后只留下 host Boolean/level；TLS socket、证书或
   session token 不进入 GPU/FSP packet。task 2 caller 也把 response-vector 设为
   null，FSP 返回后没有 host 保存的 permission token、cookie、lease 或 undo
   handle。
4. **task 2 的 host-visible admission/completion 是两步：** 先检查
   FSP-reported PRC-family QCAP key `0x13` presence，再发送 task 2/subobject 1
   并等待 command status。第一步不是 grant，第二步也不是 PLM snapshot；两者都
   不证明 `d0/dc/f8` 的最终值。
5. **可选 PRC knob `0x1d` 不是已证 credential。** 普通参数可以请求独立的
   task-13 write/readback，但默认不会自动注入；值域、`1=grant`、task-2 是否
   consume 和 self-clear 全部仍是 UNKNOWN。

## 1. 范围、artifact 与安全边界

固定 MODS artifact：

```text
mods_audit/static/extracted_inner/mods
size   392,339,552 bytes
sha256 c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
```

公开交叉材料：

```text
/usr/src/nvidia-610.43.03
```

本轮只做：

- 指定 VA 的小窗口 `objdump`；
- `.text` 中 `E8 rel32` 的低内存 direct-call 扫描及精确 pointer literal 扫描；
- 已解码 bundled JavaScript 的定向文本检索；
- NVIDIA 610.43.03 公开 FSP/NVDM header 与 parser 的只读比对；
- 对现有静态报告逐项交叉验证。

没有运行 MODS、未知程序或 firmware；没有访问 GPU、`/dev/nvidia*`、BAR/MMIO、
PCI config、debugfs、网络或实时驱动状态；没有 reset、模块/驱动操作、提权、固件
写入、全文件反汇编或 Ghidra 数据库。

证据标签：

- **FACT**：当前 artifact 指令、字段或公开源码直接支持；
- **INFERENCE**：多条事实支持，但缺少 device-side consumer；
- **UNKNOWN**：当前静态材料不能决定。

## 2. `SecurityUnlockLevel > 3` 的来源与生命周期

### 2.1 它是 host process 状态，不是设备凭据

**FACT：** native backing dword 为零填充 `.bss` 中的 `0x186d6f74`。getter body
`0xd5d660` 只是读取该 dword；public getter trampoline 为 `0xd53530`。setter body
为 `0xd5d5d0`，public trampoline 为 `0xd53520`。

对完整 `.text` 的 direct `call rel32` 目标扫描再次确认：

```text
CALL source=0xbb5f3b target=0xd53520
```

这是 setter trampoline 的唯一 established direct caller。该 caller 位于启动参数/
bypass-record parser。没有发现 GPU、GSP、FSP 或 VBIOS reply 写入这个 dword。

**FACT：** `SecurityUnlockLevel` 的 JavaScript property 只有 getter；注册时 setter
callback 为 null。bundled JavaScript 只读取/比较它，没有赋值路径。因而它不是
`NewFuse.SetSwFuses` 的普通 numeric argument。

### 2.2 level 4/5 的 stock 计算输入

setter 的可见状态机为：

1. 先把 level 写成 1；
2. 接收启动 parser 对本地 `-b` record 的分类结果；
3. 若没有 `-no_net`，执行一次带缓存的 NVIDIA-network detector；
4. 把本地 record 分类与 network Boolean 合成最终 1..5。

其中：

- **FACT：** `-b` parser 读取固定长度的本地 record，做可逆字段变换、常量比较和
  realtime expiry 比较；检查窗口内没有 signature、MAC、hash 或 certificate
  verification。这里不复述构造常量，也不提供生成方法。
- **FACT：** `-no_net` 只能跳过 network detection 并保留 parser 已得到的 level；
  它不会凭空生成 level 4。
- **FACT：** network detector 并行尝试固定 NVIDIA auth hosts，最多等待约 10 秒，
  用 bundled NVIDIA CA 验证 TLS peer chain，并检查 issuer text。成功结果只是
  Boolean。
- **FACT：** auth worker 不接收账号 entitlement、HTTP token 或 server-returned
  numeric level。server 不发“4/5”；MODS 在本地把 Boolean 与 parser input 合成。

因此分类为：

| 候选来源 | 判定 |
|---|---|
| 普通 `SetSwFuses` 参数 | **否** |
| 可写 JavaScript property | **否** |
| GPU/VBIOS/GSP/FSP report | **否** |
| build-time constant | **否**；`.bss` 零起点、runtime setter |
| NVIDIA TLS server certificate/reachability | **是，作为一个 Boolean 输入** |
| server 返回的签名 session/grant/token | **没有** |
| 本地 vendor-controlled bypass record | **是，作为另一个 parser 输入；合法签发来源 UNKNOWN** |

### 2.3 生命周期

**FACT：** stock direct setter 在 startup parser 中调用一次；setter 入口重置 level，
network detector 自己缓存 completed/result。完整 `.text` store audit 没有找到之后的
周期 revalidation、clear 或 downgrade store。

**INFERENCE：** 在 established stock path 中，最终 level 持续到 MODS process
退出；新进程重新解析并探测。它不是与 GPU reset、FSP session 或某一次 task 2
绑定的短期 credential。

**UNKNOWN：** 未装入当前 ELF 的动态模块、runtime-created function pointer 或
self-modifying path 不能由纯静态 direct-xref 绝对排除；当前 artifact 没有这类正证据。

## 3. `SetSwFuses` 在哪里校验，以及它没有做什么

`GB20x::ProgramSwFusePlan 0x1515ea0` 的入口指令顺序是：

```text
0x1515eb4  call 0xd53530       # get SecurityUnlockLevel
0x1515eb9  cmp eax, 3
0x1515ebc  jg  0x1515ed8
0x1515ebe  ... return 3
0x1515ed8  first GPU-facing latch operation begins
```

所以：

- **FACT：** level `<=3` 时，当前 writer 在接触 latch 或任何 raw plan item 前返回
  error 3；level 4/5 才继续。
- **FACT：** 这只是一处 entry-time host check。每项 raw write/readback 不再重新
  读取 level，也没有把数字 4/5 写进设备 PLM。
- **FACT：** 该函数没有调用 task-2 sender `0x185e890`、QCAP helper
  `0x185e0e0` 或 FSP capability prefetch `0x185deb0`。
- **FACT：** level 通过后，writer 尝试 latch 和 raw access；实际寄存器是否接受
  仍由 hardware PLM、`disable_sw_override`、firmware/hardware state 等独立条件
  决定。

因此 level 4/5 的准确语义是“允许 MODS host 进入这条编程算法”，不是“FSP 已
授予 L2 写权限”。

## 4. task 2 的 host 输入：没有 `SecurityUnlockLevel` 或 session token

GB20x sender `0x106c4e0` 在 `doFsp!=0` 时构造 payload，然后：

```text
0x106c574  xor r8d,r8d          # response vector = null
0x106c577  rcx = payload vector
0x106c57a  edx = 1              # subobject 1
0x106c57f  esi = 2              # task 2
0x106c587  call 0x185e890       # common send + wait
```

**FACT：** task-2 caller 的显式输入只有 FSP host object、task `2`、subobject `1`、
floorsweep payload vector 和 null response vector。它没有：

- `SecurityUnlockLevel`；
- NVIDIA-network Boolean；
- bypass record 或其分类；
- TLS certificate/session state；
- account/token/signature；
- prior PLM value或 permission cookie。

**FACT：** payload builder 生成固定 6-byte GB20x floorsweep payload，当前已解码
字段来自复用的 NVLINK/NVLC_LINK topology slots；其中没有 L2 mask、PLM value、
PRC knob `0x1d` 或 authorization blob。

**FACT：** caller 在 send 前把 FSP host object `+0x31` 置 1，所有 success/error
cleanup 都立即清回 0。该 byte 不跨调用保存，不被作为 response payload 返回，
也不携带权限值；它只能称为可见的 call/in-flight state，不能叫 credential。

**UNKNOWN：** 底层 chip-internal transport、requester/source identity、secure-boot
state 或 FSP firmware 可以在 host 看不见的位置形成隐式信任边界。当前结论只说
host caller 没有显式提供签名/令牌，不能升级为“设备端完全不认证来源”。

## 5. QCAP `0x13`：真正来自 FSP 的 capability 门

### 5.1 来源与 cache shape

**FACT：** `Gpu::Initialize` 在 feature ID `0xdb`（FSP support）成立并取得 FSP
host object 后，于 `0xda3654` 调：

```text
0x185deb0(fspObject, 0xff)
```

即预取全部 QCAPS。该调用的返回值在此 call site 没有被测试；它是 best-effort
prefetch，不是 task 2 最终授权状态本身。

`0x185deb0` 的可见行为：

- object-local RB tree header 在 `+0x38`，entry count 在 `+0x60`；
- key 已存在时跳过重复 query；
- 缺失时通过 task `0x7f` 的 capability-query transaction 请求指定 key或 `0xff`；
- 成功 response 按 4-byte records 解析为 `low16 NvdmType / high16 Version`，存入
  host tree。

后续独立审计在同一 parser 的本地 map-dump 字符串中恢复了标题
`NvdmType  :  Version`，所以 high16 的字段名已闭合为 16-bit `Version`；只有其
内部编码/协商规则仍未公开。见 `parallel/qcap13_semantics.md`。公开 610 的
`FSP_CAPS_QUERY_RPC_PAYLOAD_PARAMS` 独立确认 generic caps-query request 只有一个
`NvU8 subMessageId`，但 MODS 的 all-query/list encoding 属于 private artifact，
不能把两者未经证明地写成逐字节同一 schema。

### 5.2 task 2 如何消费 cache

task-to-QCAP mapper `0x1857b10` 对 task 2 返回 key `0x13`。公开 NVIDIA 610
`nvdm_format.h` 定义：

```text
NVDM_TYPE_PRC        = 0x13
NVDM_TYPE_CAPS_QUERY = 0x16
```

task-2 common sender 在 `0x185e530..0x185e55c`：

1. 以 task `2` 调 `0x185e0e0`；
2. cache 为空时，helper 会 lazy 调 `0x185deb0(0xff)` 再查；
3. exact key `0x13` 存在时返回 true；缺失时打印
   `Floorseeping PRC isn't supported by FSP or is not yet active`，返回 `0x12d`，
   packet 不进入正常发送；
4. helper 会把 entry 的 high16 Version 复制到 caller stack，但 task-2 sender 只测试
   Boolean return；进入 packet path 前没有使用该 copied value，随后同一 stack
   slot被复用。

所以最精确的描述是：

- **FACT：** task 2 的 host-side QCAP gate 是 **FSP-reported PRC family entry 的
  presence test**；
- **FACT：** 不是 host numeric security level，也不是来自普通 CLI 的 Boolean；
- **FACT：** 不是一枚会随 task 2 packet 发回 FSP 的 credential；
- **UNKNOWN：** FSP 为何发布/撤销该 capability、Version 的内部编码/协商规则、
  reset/firmware phase 后 cache 何时失效。

### 5.3 生命周期边界

**FACT：** 当前初始化主线先 prefetch QCAPS，随后可选 PRC read/write 与 task 2
共用同一个 object-local tree。task 2 自身不刷新 cache；若 tree 为空，helper
只会按上述规则 lazy query。

**FACT：** 完整 `.text` direct-call 扫描只找到一个显式 `0x185deb0` prefetch
call site `0xda3659`，以及 helper 内部的 lazy call `0x185e21a`。当前审计路径没有
task-2 前由普通参数直接向 tree 插入 key `0x13` 的 setter。

后续 `parallel/qcap_cache_lifetime.md` 已闭合普通 host 生命周期：完整
`GpuSubdevice` 析构会销毁 FSP wrapper/tree，但正常 post-program reset 保留同一
wrapper 且不 clear/refetch；later all-query 也不覆盖重复 Version 或删除缺失 key。
firmware-side capability 是否在 reset/restart 后变化仍 UNKNOWN。因此 QCAP entry
只能称为可能陈旧的 host capability snapshot，不能称为 process-lifetime 授权。

## 6. task 2 的最终裁决与 response

common sender 的可见时序是：

1. feature/QCAP 检查并构造 packet；
2. transport vtable `+0x38` 发送；
3. 发送成功后，wrapper `0x185e890` 调 transport `+0x30` 进入 response-completion/
   response-parse；
4. 最终 `NV_STATUS` 返回 GB20x caller；非零立刻阻止 pending host apply；零才继续。

**FACT：** GB20x caller 的 response-vector 参数为 null。它没有接收或保存：

- grant token/cookie；
- PLM snapshot/prior value；
- lease/expiry/remaining-use count；
- subobject-specific response object；
- undo/restore handle。

公开 610 `NVDM_PAYLOAD_COMMAND_RESPONSE` 只有：

```c
NvU32 taskId;
NvU32 commandNvdmType;
NvU32 errorCode;
```

公开 parser 只做长度检查、日志和 `errorCode -> NV_STATUS` 映射。这个公开 schema
不能证明 private MODS wire format每字节完全相同，但与 null response-vector 一起
支持相同的 host-visible negative：**没有权限对象返回给 caller。**

因此：

- **FACT：** status zero 是“FSP command 完成且没有返回可见错误”的同步裁决；
- **UNKNOWN：** status zero 时 d0/dc/f8 是否被改变、是否仍保持、是否已 one-shot
  consume 或自动恢复；
- **UNKNOWN：** FSP 是否根据 requester source、secure boot phase、SKU、fuse、
  hidden policy或其他内部状态拒绝 task 2。这些都可能体现在 generic error status，
  但 consumer 不可见。

## 7. 可选 PRC knob `0x1d`：host request，不是已证凭据

目标名称/ID 已静态闭合为：

```text
0x1d  PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT
```

**FACT：** 可见 JavaScript 的 `g_FspPrcWriteArray` 默认为空；只有显式
`-fsp_prc_write <name> <value>` 才向它 push。无参数 task 2 仍可在首次正常
初始化中发送，所以 host 自动写 `0x1d` 不是 task 2 的必需前置事实。

**FACT：** 若显式提供，该项走独立流程：

```text
task 12 read current
if different:
  task 13/submessage 2 write
  task 12 immediate readback and compare
later, under independent gates:
  task 2/subobject 1
```

**FACT：** task 13 与 task 2 都映射到 QCAP key `0x13`，说明共享 PRC message
family。成功写 knob 不会“创造”原本缺失的 QCAP；写事务本身已经要求同一 entry。

**FACT：** task-2 payload 不复制 knob ID/value；host 只闭合了相对顺序，没有
consumer dataflow。

**INFERENCE：** 名称 `ALLOW_INB_ONE_SHOT` 与 placement 支持“某种 floorsweep
一次性 permission preparation”的用途解释。

**UNKNOWN：** 合法值、默认值、是否 Boolean、`1` 是否 grant、task 2 是否检查/
consume、自清单位、失败/重试和 reset/session lifetime。故它不能被列为已知可用
credential 或解锁步骤。

## 8. 完整校验时序

在普通 FSP-enabled、`SkipFspFs=0`、前置调用成功的限定 stock 流程中，可见顺序为：

```text
MODS process startup
  parse local -b records
  optional NVIDIA-network TLS certificate/reachability check
  compute and cache SecurityUnlockLevel in host .bss

Gpu::Initialize
  feature 0xdb / FSP object checks
  prefetch FSP QCAP list (0xff; call-site status not consumed)
  optional PRC map
    task 12 read
    optional task 13 write + task 12 readback
  floorsweep dispatcher derives doFsp
  task 2 preparation
    exact QCAP key 0x13 presence check
    if missing: host returns 0x12d, no normal send
    if present: send task 2/subobject 1 + 6-byte payload
    wait for FSP completion/status
  only after zero status: optional pending host floorsweep apply

Later script call to NewFuse.SetSwFuses
  ProgramSwFusePlan entry reads cached host SecurityUnlockLevel
  if <=3: return before latch/raw access
  if >3: attempt latch/raw plan
  no task 2/QCAP transaction in this writer
```

首次没有 floorsweep 参数的 GB20x 路径仍可发送 task 2，然后因 pending=0 跳过
host apply，并因 mutation aggregate=0 跳过外层 reset。它构成一个静态候选阶段，
但**不证明** QCAP、task status 或某个 `ONE_SHOT` state 在返回脚本层时仍代表可用
PLM permission。

## 9. 普通 MODS 参数能控制什么，不能控制什么

| 参数/状态 | 可见作用 | 是否产生已证授权 |
|---|---|---|
| `-b <file>` | 给 startup parser 提供本地 record 分类输入 | 可影响 process-local `SecurityUnlockLevel`；合法签发来源 UNKNOWN，不是 task2/FSP token |
| `-no_net` | 禁止 network probe，保留已有 parser input | **不能提升** |
| `-fsp_prc_write` | 请求独立 PRC write/readback | 由 FSP 最终裁决；`0x1d` grant 语义未证 |
| `-skip_fsp_fs` | 仅在 host precheck 观察到 d0/dc write nibble 均为 `0xf` 时允许跳过 task 2，否则失败 | 不创建或证明 device state |
| `-skip_fs_plm_check` | Hopper 上跳过 precheck 并更直接发 task 2；GB20x sender 不消费 | 不抑制 task 2，也不证明 GB202 device effect |
| `-skip_prc_reset` | 改变 host reset 尾声 | 不改 process-local `SecurityUnlockLevel`、QCAP 或 FSP policy |
| `doFsp` | dispatcher 由 feature/config 临时计算的 stack Boolean | 只是“是否发送”，不是 response/grant |
| FSP object `+0x31` | 调用期间置 1、cleanup 清 0 | in-flight state，不是 credential |

## 10. 签名、会话和不可由宿主直接控制的边界

### FACT

1. NVIDIA-network path 有真实 TLS certificate-chain validation；其输出只是一枚
   host Boolean，最终汇入 `.bss` level。
2. 没有 TLS session/token/certificate data流入 `ProgramSwFusePlan` 或 task 2
   packet。
3. 本地 bypass-record parser 的检查窗口没有密码学签名/MAC/hash verifier。
4. QCAP `0x13` 来自 FSP query response；普通 CLI 不能直接往 task-2 checker 的
   cache tree注入该 key。
5. task 2 的最终 success/error 来自 FSP response completion；caller只消费 status。

### INFERENCE

1. NVIDIA-network机制是 PKI-backed network-location/reachability attestation，
   不是 per-user entitlement service。
2. task 2 的实际 security policy 很可能位于 FSP/硬件 trust boundary，而不是
   MODS process-local `SecurityUnlockLevel`；当前可见 FACT 只到 FSP-reported
   QCAP `0x13` presence 与 command status，后者也不是 device permission-state
   proof。
3. FSP可能依靠 chip-internal requester/source identity与 secure-boot firmware
   provenance，而非 host携带 token；当前只有机制合理性，没有 consumer事实。

### UNKNOWN

1. 合法 bypass record 的签发、运输、绑定身份与撤销机制；
2. FSP QCAP `0x13` 的发布/撤销 policy及 high16 Version 的内部编码/协商语义；
3. task 2 consumer 的 per-SKU/fuse/source/session checks；
4. production GB202 task 2 是否实际改变 d0/dc、写成什么值、one-shot consume、
   自动 restore 和 reset lifetime；
5. 独立 f8 是否被 task 2/HULK/其他固件路径处理及其 lifetime；
6. hidden transport metadata是否还携带 host不可见的 authenticated source context。

## 11. 最终可引用表述

> GB202 direct-shadow `ProgramSwFusePlan` 与 FSP floorsweep task 2 使用互不传递的
> host/protocol checks。前者在第一次 GPU-facing 操作前读取 MODS process-global
> `SecurityUnlockLevel` 并要求 `>3`；该 value 在 startup 由本地 bypass-record
> 分类与 NVIDIA-network TLS Boolean 合成，不是 GPU/FSP reply 或签名 session
> token。task 2 则在 GPU initialization 中先要求 FSP-reported QCAP key `0x13`
> presence，再发送 task 2/subobject 1 并同步等待 command status；packet 不携带
> `SecurityUnlockLevel`、bypass/TLS state 或 permission token，caller 也没有
> response vector。QCAP presence 与 status zero 都不是 PLM-state proof。现有证据
> 只强推断 task 2 旨在准备 `d0/dc`；production GB202 actual effect/lifetime 和
> 独立 `f8` 均为 UNKNOWN。可选 `0x1d` one-shot knob 是另一条默认不注入的
> task-13 request，其值与消费语义同样未知。

## 12. 复核命令（全部离线只读）

```sh
readelf -SW mods_audit/static/extracted_inner/mods

objdump -d -Mintel \
  --start-address=0x1515e90 --stop-address=0x1516090 \
  mods_audit/static/extracted_inner/mods

objdump -d -Mintel \
  --start-address=0xd5d5c0 --stop-address=0xd5d6a0 \
  mods_audit/static/extracted_inner/mods

objdump -d -Mintel \
  --start-address=0x106c4d0 --stop-address=0x106c5e0 \
  mods_audit/static/extracted_inner/mods

objdump -d -Mintel \
  --start-address=0x185deae --stop-address=0x185e0e0 \
  mods_audit/static/extracted_inner/mods

objdump -d -Mintel \
  --start-address=0x185e0e0 --stop-address=0x185e930 \
  mods_audit/static/extracted_inner/mods

python3 parallel/mods_x86_direct_xrefs.py \
  0xd53520 0xd53530 0xd5d5d0 0xd5d660 0xd5d680

python3 parallel/mods_x86_direct_xrefs.py \
  0x185deb0 0x185e0e0 0x185e890 0x185f5a0

rg -n 'g_SkipFspFs|skip_fsp_fs|fsp_prc_write|skip_prc_reset' \
  mods_audit/static/decoded/all/gpuargs.js
```

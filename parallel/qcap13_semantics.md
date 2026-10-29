# FSP QCAP `0x13`：字段语义、task-2 消费与失败行为静态审计

日期：2026-07-21
状态：**final，strict static-only**

## 0. 结论先行

| 问题 | 结论 | 证据等级 |
|---|---|---|
| QCAP key `0x13` 是什么？ | 16-bit **NVDM message type**；公开 610 名称为 `NVDM_TYPE_PRC` | **FACT** |
| entry 的另 16 bit 是什么？ | MODS 自己打印为 **Version**；不是长度、security level 或 token | **FACT** |
| task 2 如何使用它？ | 只检查 key `0x13` 是否存在；虽然 helper 复制 Version，caller 不比较、不编码进 packet，随后覆盖该栈槽 | **FACT** |
| QCAP presence 代表什么？ | host 将其当成 FSP 报告的 PRC 命令族 capability/active gate | **FACT（host 行为）** |
| 是否等于 task-2 授权？ | 否。presence 通过后仍要真正发送 task 2 并等待独立 FSP status | **FACT** |
| 是否是 credential？ | 不是可见 credential：没有 nonce、签名、cookie、lease、expiry，也不回送该 Version | **FACT（可见协议边界）** |
| Version 的更细格式是什么？ | 只知道 16-bit `Version`；major/minor 编码、协商规则、FSP 内部用途未公开 | **UNKNOWN** |

最准确的一句话是：

> QCAP `0x13` 是一条 `{NvdmType=PRC, Version=v}` 的 capability 记录。MODS 的
> task-2 路径只把“PRC 记录是否存在”当作发送前兼容性/可用性门，不校验 `v`；
> 它不是 MODS network level、不是 FSP 授权级别，也不是随请求携带的凭据。

这修正了既有报告中“high16 只能称 auxiliary value、语义 UNKNOWN”的保守表述：
**本 artifact 的本地格式字符串已直接给出 `Version` 名称。** 但 `Version` 的内部
编码仍然未知。

## 1. 范围、artifact 与安全边界

固定 MODS artifact：

```text
mods_audit/static/extracted_inner/mods
size   392,339,552 bytes
sha256 c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
```

公开交叉材料：

```text
/usr/src/nvidia-610.43.03/
```

本轮只执行指定 VA 小窗口 `objdump`、只读字符串/源码检索，以及 256 MiB 上限内的
`.text` direct-`call rel32` / exact-pointer 扫描。没有运行 MODS，没有打开 GPU
设备节点，没有读取或写入 MMIO/BAR/PCI config，没有 reset、rebind、模块操作、
固件/VBIOS 操作或网络访问，也没有进行全文件反汇编或 Ghidra 分析。

下文标签：

- **FACT**：当前 MODS 指令/字符串或 NVIDIA 公开 610 源码直接支持；
- **INFERENCE**：事实组合支持，但没有 FSP consumer 实现；
- **UNKNOWN**：当前材料不能决定。

## 2. 32-bit QCAP record 的字段已经命名

### 2.1 response parser 的机械拆分

QCAP fetch/cache 函数 `0x185deb0` 在 transport 成功后遍历返回 vector，每次读取
一个 32-bit little-endian word：

```text
0x185df58  mov eax, dword ptr [rbx]
0x185df62  movzx edx, ax
0x185df65  shr eax, 16
0x185df68  store low16  -> temporary key
0x185df6c  store high16 -> temporary value
0x185df70  insert {key,value} into object-local RB tree
0x185df75  add rbx, 4
```

tree node 的 payload 为：

```text
+0x20  NvU32 key     (实际来自 record low16)
+0x24  NvU32 value   (实际来自 record high16)
```

因此 record 的位布局是直接事实：

```text
bits 15:0   key
bits 31:16  value
```

### 2.2 MODS 自己把两列打印为 `NvdmType : Version`

插入完全部 response records 后，`0x185df7e..0x185e024` 遍历同一棵 tree。
其只读字符串为：

```text
VA 0x90fc132  "NvdmType  :  Version \n"
VA 0x90fc149  "0x%-7x : 0x%x\n"
```

每行调用在进入 formatter 前恰好加载：

```text
edx = [node+0x20]   # first printed integer
ecx = [node+0x24]   # second printed integer
```

故当前 MODS artifact 对字段的原生名称已经闭合：

```text
record.low16  = NvdmType
record.high16 = Version
```

这是 **FACT**，不再只是根据 record shape 猜测。与此同时，字符串没有说明
`Version` 是单一递增 revision、major/minor packed value、minimum/maximum version
还是其它编码；这些更细语义仍为 **UNKNOWN**。

### 2.3 它不是长度、授权级别或 credential

**FACT：** parser 没有把 high16 用作 vector 长度、record count、copy size 或
allocation size；迭代步长固定为 4 bytes。

**FACT：** tree key 是 low16；presence lookup 返回 high16 给可选 output pointer，
但不会据此改变 MODS `SecurityUnlockLevel`，也没有把它存入 auth/session 对象。

**FACT：** QCAP map dump 明确称它 `Version`，不是 `permission`、`level`、
`credential`、`token` 或 `flags`。

## 3. 公开 610 对 NVDM/QCAP 身份的独立交叉验证

公开文件
`src/nvidia/arch/nvalloc/common/inc/nvdm_format.h:39-51` 说明 NVDM types 来自跨
FSP/SEC2/GSP 子系统的共享 message-type namespace，并定义：

```c
#define NVDM_TYPE_PRC        0x13
#define NVDM_TYPE_CAPS_QUERY 0x16
```

所以 low16 key `0x13` 的公开语义是 **PRC message family**，不是 task number 13、
network security level 或 PLM 数值。

公开
`src/nvidia/arch/nvalloc/common/inc/fsp/fsp_caps_query_rpc.h:33-47` 定义的 query
request 只有：

```c
NvU8 subMessageId;
```

而 response 在 generic command response 后保留 4-byte `rspPayload`。公开 header
没有给这 4 bytes 的子字段命名，因此不能只靠公开源码推出 MODS 的 all-query list
ABI；但“一次 targeted query 指定一个 NVDM type、response 有一个 4-byte opaque
payload”与 MODS 的 4-byte `{type,version}` record **结构相容**。

公开
`kern_fsp_gb100.c:171-194` 还给出一个清晰用例：host 以
`subMessageId=NVDM_TYPE_CLOCK_BOOST` 发送 `NVDM_TYPE_CAPS_QUERY`，只根据返回
`NV_STATUS` 设置 `bClockBoostSupported`。这独立支持“CAPS_QUERY 是命令族 capability
probe”，不支持“它返回授权 token”的解释。

边界：公开 610 没有 PRC QCAP Version 的符号名、version 常量或解码 macro；
`Version` 名称来自当前 MODS 的本地打印字符串，更细格式仍不可见。

## 4. task 2 到 QCAP `0x13` 的精确映射

mapper `0x1857b10` 接收 MODS internal task byte。对 task `1,2,3,4,5,8,12,13,14,18`
（bitmask `0x4713e`）都返回 `0x13`；因此 task 2 确定属于 PRC NVDM family：

```text
input task = 2
1 << task intersects 0x4713e
return 0x13
```

common sender 的 task jump table `0x930f0c0` 对 index 2 指向 `0x185e530`。该分支：

```text
0x185e530  out = &stack[0x80]
0x185e538  task = 2
0x185e540  call QcapLookup(0x185e0e0)
0x185e545  test bool result
0x185e547  true  -> normal packet-build/send path
0x185e54d  false -> log PRC unsupported/not active
0x185e55c  false -> return raw 0x12d path
```

对应日志字符串是：

```text
"Floorseeping PRC isn't supported by FSP or is not yet active\n"
```

（原字符串就是 `Floorseeping` 拼写。）

所以 task 2 的 QCAP gate 是：

```text
map contains NvdmType 0x13 ? pass : fail
```

没有：

- `Version >= minimum` 比较；
- Version equality/range/bit test；
- Version 到 packet payload 的 copy；
- Version 到 host security level 的转换。

lookup helper 在命中时确实把 `[node+0x24]` 的 Version 写到 `stack+0x80`，但
task-2 branch 只测试 Boolean return；成功后跳回 packet builder。在第一次 packet
发送成功后的 `0x185e5d0`，同一 `stack+0x80` 又被当成临时 string 对象重新构造，
此前 Version 没有被读取。故“task 2 只看 presence、忽略 Version”是 **FACT**。

完整 `.text` direct-call 扫描找到 `QcapLookup(0x185e0e0)` 的 7 个直接 call site：

```text
0x122f4cf  0x124945f
0x185e4a0  0x185e4e0  0x185e510  0x185e540  0x185e578
```

其中 task-2 site 就是 `0x185e540`。两个外部 site 查询另一 NVDM family 后也没有
读取 Version output；common sender 的五个 site 都只测试 presence。查询后的 map
dump 会显示 Version，但在 established task-2 控制流中它不是 gating input。

## 5. query、cache 与刷新行为

### 5.1 初始化 prefetch

`Gpu::Initialize` 在 feature `0xdb`（FSP support）成立且取得 FSP object 后，于
`0xda3654..0xda3659` 调：

```text
QcapFetchAndCache(fspObject, 0xff)
```

即 all-query prefetch。call site 紧接着进入 object cleanup，未测试返回 `eax`；
因此 prefetch 是 **best effort**，不是 task 2 的最终授权结果。

### 5.2 lazy retry 只发生在整棵 tree 为空时

`QcapLookup(0x185e0e0)` 先检查 tree entry count `object+0x60`：

- count 为 0：调用 `QcapFetchAndCache(object,0xff)`，**忽略其 status**，然后再查；
- count 非 0：直接查 key，不刷新缺失项；
- exact key 命中：返回 true，可选复制 Version；
- key 缺失：返回 false。

因此：

1. prefetch 完全失败且 map 仍空时，首次 task lookup 会再尝试一次 all-query；
2. response 成功但为空时，map 仍空，后续 lookup 仍可重复 all-query；
3. map 已含其它 capability、唯独缺 `0x13` 时，task 2 **不会 targeted re-query**，
   会直接当作 PRC unavailable；
4. lookup 没有 cache timestamp、firmware epoch 或 per-entry active expiry 检查。

### 5.3 插入与重复项

response parser 每 4 bytes 调一次 `0x185de10`，其行为是 RB-tree unique insert。
重复 `NvdmType` 不覆盖旧 node 的 Version；tree count 只在新 key 插入时增加。

`QcapFetchAndCache` 自身若发现请求的具体 subMessageId 已在 map，会记录
`caps already present in the capability map` 并直接返回成功，不向 FSP 重问。
现有两个 established direct fetch caller都请求 `0xff`（初始化 prefetch与空-map
lazy fetch），没有普通 task-2 path 的 targeted `0x13` refresh。

后续 `parallel/qcap_cache_lifetime.md` 已把 host owner/lifetime 闭合得更窄：

- **FACT：** tree 属于 `GpuSubdevice+0x1ad8` 指向的 FSP wrapper；完整
  `GpuSubdevice` 析构会销毁 wrapper/tree；
- **FACT：** 正常 post-program reset 保留同一 wrapper，不 clear/refetch；后续
  all-query 又只做 unique-add，不覆盖旧 Version，也不删除 response 中消失的 key；
- **UNKNOWN：** firmware-side capability 是否在 reset/restart 后改变，以及隐藏的
  非正常 teardown/reconstruction 路径。

因此该记录可能跨正常 reset 变陈旧；它是 host capability snapshot，不是实时
permission lease，更不能仅凭 presence 宣称当前 firmware session 仍授权。

## 6. 失败语义：presence failure 与 command failure 是两层

### 6.1 QCAP fetch 自身

`QcapFetchAndCache(0x185deb0)` 的可见结果：

| 情况 | 行为 |
|---|---|
| requested key 已缓存 | 不发送，log 后返回 0 |
| FSP/query transport 返回非零 | 不解析，原样返回该非零 status |
| transport status 为 0、response vector 为空 | log `QCAPS ... failed; ... assumed ... disabled`，但函数返回 0，map 不增加 |
| response 非空 | 每 4 bytes 插入 `{NvdmType,Version}`，打印 map，返回 0 |

parser 没有可见的 `response_size % 4 == 0` 检查；它以 `+4` 迭代直到 end。正常
firmware response 显然被假定满足 4-byte record invariant。异常/恶意 response 的
行为不是本项目的运行目标，也没有测试。

### 6.2 task-2 gate 会把多种 query 问题折叠为 `0x12d`

lookup 的 lazy fetch 不检查 fetch status。因此在 map 最终没有 `0x13` 时，task-2
common sender只能观察到 Boolean false，并统一：

```text
log "... PRC isn't supported by FSP or is not yet active"
return raw MODS status 0x12d
do not enter normal task-2 packet send path
```

所以 raw `0x12d` 在这里不能区分：

- FSP 真正不支持 PRC；
- PRC 尚未 active；
- all-query transport/parse 失败且 cache 为空；
- cache 是非空但不完整/陈旧，缺少 `0x13`；
- capability query 发生在 FSP boot 尚未 started 的时刻。

不要把这个 raw MODS `0x12d` 误命名为公开 RM 的
`NV_ERR_NOT_SUPPORTED=0x56`；当前只能保留 raw value 与本地日志语义。

### 6.3 presence 通过后仍有独立的 FSP 裁决

若 `0x13` 存在，common sender才构建/发送正常 task-2 packet。同步 wrapper
`0x185e890` 先接收 send status；send 成功后再调用 transport response-completion/
parse，并把最终非零/零 status 返回 GB20x caller。

因此：

- **FACT：** QCAP presence 不是 task-2 success；
- **FACT：** 任意 16-bit Version（包括 0）在当前 host gate 都能通过，因为没有
  version predicate；
- **FACT：** 实际 task 2 仍可被 FSP command response拒绝；
- **UNKNOWN：** FSP consumer 是否基于 secure boot phase、SKU/fuse、requester
  identity、内部 version、one-shot state或其它 policy 作最终裁决。

## 7. “能力、版本、授权、凭据”最终分类

### FACT

1. low16 是 `NvdmType`；`0x13` 的公开名称是 `NVDM_TYPE_PRC`。
2. high16 是 MODS 原生输出明确命名的 `Version`。
3. task 2 只要求 PRC key presence，不使用 Version。
4. QCAP query/cache 与 MODS host `SecurityUnlockLevel` 没有数据流。
5. QCAP Version 不进入 task-2 packet，也不作为 response token保存。
6. capability presence 后仍有一次独立、同步的 FSP command status。

### INFERENCE

1. QCAP entry 是 FSP 对某个 NVDM message-family及其协议 revision 的支持声明；
   Version 很可能用于跨 host/firmware兼容描述。由于当前 task-2 caller忽略它，不能
   声称这里完成了实际 version negotiation。
2. 日志中的 `or is not yet active` 表明 capability 发布可能受 firmware phase影响；
   但 cache没有 freshness检查，host看到的是上次 query snapshot。

### UNKNOWN

1. 16-bit Version 的编码、取值范围、major/minor 结构和 FSP内部校验规则；
2. FSP 发布/撤销 PRC `0x13` 的条件；
3. firmware restart/reset 后 device-side capability 是否变化，以及任何未见的
   非正常 wrapper reconstruction；正常 post-program reset 的 host tree 保留已知；
4. task-2 consumer 的真实授权规则，以及成功后是否/如何改变 d0/dc/f8；
5. private MODS all-query wire ABI 与公开 610 targeted-query struct 是否逐字节相同。

## 8. 对主研究的直接含义

QCAP `0x13` 不能填补“如何取得写权限”的缺口。它只能提前告诉 MODS：FSP声称
PRC 命令族存在/active到足以尝试。即使它存在：

- 不代表 MODS network level 已满足；
- 不代表 task 2 会被接受；
- 不代表任何 PLM 已经 lowered；
- 不代表 permission仍有效；
- 不提供可以复用、伪造或回放的 credential。

反过来，缺失 `0x13` 也不等价于物理硬件永久不支持：在当前 host实现中，它还
可能表示 query timing/cache/transport问题。只有可读 FSP consumer或受控环境中的
合法协议观测才能再区分这些情形；本轮没有进行任何 live probe。

## 9. 可复核的离线只读命令

```sh
objdump -d -Mintel \
  --start-address=0x1857b10 --stop-address=0x1857bb0 \
  mods_audit/static/extracted_inner/mods

objdump -d -Mintel \
  --start-address=0x185deb0 --stop-address=0x185e260 \
  mods_audit/static/extracted_inner/mods

objdump -d -Mintel \
  --start-address=0x185e260 --stop-address=0x185e890 \
  mods_audit/static/extracted_inner/mods

objdump -s \
  --start-address=0x8c927e0 --stop-address=0x8c92b40 \
  mods_audit/static/extracted_inner/mods

objdump -s \
  --start-address=0x90fc120 --stop-address=0x90fc1b0 \
  mods_audit/static/extracted_inner/mods

ulimit -v 262144
python3 parallel/mods_x86_direct_xrefs.py \
  0x1857b10 0x185deb0 0x185e0e0 0x185f5a0 0x185de10
```

本轮 direct-xref pass 完成于约 4.7 秒；没有运行目标 binary或访问硬件。

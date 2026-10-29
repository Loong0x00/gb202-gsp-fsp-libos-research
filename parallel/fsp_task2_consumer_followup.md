# GB202 FSP task 2/subobject 1 consumer：静态跟进审计

Status: **final, static-only, negative result with bounded coverage**
Date: 2026-07-21

## 0. 直接结论

| 问题 | 本轮结论 | 等级 |
|---|---|---|
| 是否找到 GB202 FSP task `2` / subobject `1` consumer？ | **没有。** VBIOS 中唯一可疑的 `app=0x24/target=0x0f` 三组字节对象均由 v6 descriptor 标为 encrypted，切片接近满熵；610 bindata 中新复核的小对象是 **GSP-FMC boot image**，不是 FSP runtime | **FACT（材料分类与限定负结果） / UNKNOWN（不可见 consumer）** |
| task 2 向 host 返回什么？ | MODS 该调用不提供 response vector，只消费同步调用的零/非零状态。公开 610 的通用 FSP response body 是 `taskId`、`commandNvdmType`、`errorCode` 三个 `NvU32`；没有公开 task-2 专用扩展 | **FACT（各自 host/schema 边界）** |
| response 是否返回 subobject、PLM 值或权限凭据？ | 公开通用 response 没有 `subobject`、d0/dc/f8 值、prior value、token、lease、expiry、undo/restore handle；MODS task-2 caller 也没有接收额外 vector | **FACT（可见 host/schema negative）** |
| task 2 是否改变 `0x8200d0/0x8200dc`？ | Hopper sibling 的同 task/subobject precheck 和 GB20x 的 send-before-apply 仍强支持此目的；但没有 GB202 consumer 指令或返回状态快照，不能升级为实际写入事实 | **INFERENCE（较强） / UNKNOWN（实际 effect）** |
| task 2 是否改变 `0x8200f8`？ | 没有新增证据。precheck 不含 f8，host payload/response 也无 f8 字段；opaque firmware 不能审计 | **UNKNOWN** |
| task 2 是否恢复上述 PLM？ | 可见 host 路径仍没有配对 close/undo sender 或 restore 字段；FSP 内部是否按 ack、首写、阶段、timer、reset 等自动收权不可见 | **FACT（host negative） / UNKNOWN（firmware/hardware）** |

因此，本轮最重要的新增结果不是找到 consumer，而是排除了一个容易误判的本地
候选：`/tmp/fmc_gb202_prod.bin` 可逐字节闭合到 610 的
`g_gsp_gb20x_dyn_spdm_concatenated_fmc_prod_image.bin`，它属于 GSP-FMC/GSP boot
链，不是随 chip reset 启动的 FSP 指令体。

## 1. 范围、复用材料与安全边界

本轮复用而不重复展开以下既有结论：

- `parallel/task2_lifecycle_audit.md`：MODS task-2 send/wait、null response-vector、
  send-before-host-apply、正常 host 路径无第二次 close/restore；
- `parallel/vbios_fsp_inventory.md` 与 `parallel/fsp_v6_payload_compare.md`：四个 raw
  image 去重为三个 `app=0x24/target=0x0f` 字节对象，v6 descriptor、encrypted bit、
  切片范围与 hash；
- `parallel/gb202_610_arch.md`、`parallel/prc_1c_public_audit.md`（文件名保留早期
  `0x1c` 误判，正文已纠正目标为 `0x1d`）与
  `parallel/gsp_f8_hulk_audit.md`：GB202 的可工作 host endpoint 是 FSP，公开树没有
  task-2 consumer，当前 GSP ELF 不是 FSP 指令体，公开 response 三字段；
- `parallel/GSP_ARTIFACT_PROVENANCE.md`：当前可读 inner GSP ELF 的来源边界。

本轮没有重做 GSP host transport/caller 扫描，没有运行 MODS、updater、固件或未知
二进制，没有访问 GPU、设备节点、PCI/BAR/MMIO、debugfs 或实时驱动状态，没有
reset、模块操作、提权或网络访问。没有尝试密钥恢复、认证绕过、解密或解压未知
firmware payload；也没有使用 Capstone、Ghidra 或全段反汇编。

下文使用：

- **FACT**：当前文件、公开字段或明确限定的字节扫描直接支持；
- **INFERENCE**：多项事实支持，但缺少目标 consumer；
- **UNKNOWN**：当前材料不能回答。

## 2. 先判定哪些对象可读

### 2.1 VBIOS `app=0x24/target=0x0f`：候选最相关，但不可作 plaintext 审计

既有 inventory 已证明四个 canonical raw image 只产生三个唯一 target 对象。
本轮只对三个既定的 word1-sized immediate region 做定点复核，没有扩大为全 ROM
反汇编或未知格式恢复：

| 唯一对象 | region bytes | Shannon entropy | ASCII printable run >= 16 bytes |
|---|---:|---:|---:|
| GeForce common | `0x29400` = 168,960 | `7.999017` bit/B | 0 |
| Dell Pro 8D | `0x36c00` = 224,256 | `7.999129` bit/B | 0 |
| HPE Pro 9E | `0x37000` = 225,280 | `7.999179` bit/B | 0 |

三个 descriptor 的 raw word0 都是 `0x0050060d`：version 6、descriptor size
`0x50`、flags `0x0d`，其中 `flags.bit2=1`，即 descriptor 明确报告
`encrypted=true`。这个 flag 本身不独立证明 immediate region 就是 ciphertext，
但三个 region 均覆盖全部 256 个 byte 值，且其起始 bytes 没有 ELF、PE 或其它可
直接识别的文件头，也没有长度至少 16 的稳定 ASCII run。

对三个切片（合计 `0x97000` = 618,496 bytes）的下列精确模式均为 0 命中：

- `0x8200d0`、`0x8200dc`、`0x8200f8` 的 little-endian 与 big-endian 4-byte
  表示；
- ASCII `task 2`、`task2`、`subobject`、`restore`、`undo`。

这是严格的**encrypted-flag/high-entropy region 字节负结果**，语义权重很低：
它不能排除认证后展开或解码后的 consumer、动态地址、表驱动寄存器 ID 或内部
restore 状态机，也不能仅凭 entropy 在加密、压缩和其它高熵编码之间作选择。

### 2.2 `/tmp/fmc_gb202_prod.bin`：可闭合来源，但属于 GSP-FMC

这个临时小对象大小为 `503808` (`0x7b000`) bytes，SHA-256 为：

`7db6adc7015aba4938d87c60f403d433b31546e4b56a546465e6be5154a11e6a`

逐行、低内存提取 610 generated C array，并只做公开 bindata 的 raw-deflate 解包，
得到：

- compressed bytes：478,456；
- decompressed bytes：503,808；
- decompressed SHA-256：与上值相同；
- 与 `/tmp/fmc_gb202_prod.bin` **逐字节相等**。

来源文件
`generated/g_bindata_kgspGetBinArchiveConcatenatedFMC_GB202.c:31-38`
把它明确命名为
`kernel/inc/gspcc/bin/g_gsp_gb20x_dyn_spdm_concatenated_fmc_prod_image.bin`，storage
在 `:29954-29960` 记录相同的 compressed/uncompressed size。对应的 28-byte
compressed descriptor 在
`generated/g_bindata_kgspGetBinArchiveConcatenatedFMCDesc_GB202.c:31-58`，解包为
92-byte `RM_RISCV_UCODE_DESC`：

```text
version               6
manifestOffset        0x00000
manifestSize          0x00a00
monitorDataOffset     0x00a00
monitorDataSize       0x0a900
monitorCodeOffset     0x0b300
monitorCodeSize       0x33900
bIsMonitorEnabled     1
```

字段布局来自公开
`arch/nvalloc/common/inc/rmRiscvUcode.h:36-93`。descriptor 所界定的
monitor data `[0xa00,0xb300)` 熵为 `7.995739` bit/B，monitor code
`[0xb300,0x3ec00)` 熵为 `7.999114` bit/B；后部另一个高熵主体
`[0x45000,0x7b000)` 为 `7.999148` bit/B。整个对象没有长度至少 16 的 ASCII
字符串；对前述 d0/dc/f8 双端字节模式及 `task 2/task2/subobject/PRC/FSP` 的精确
扫描也均为 0。

这些统计只说明 production object 对普通静态指令审计是 opaque；没有尝试解释或
绕过其安全封装。更关键的是，它的**职责可由公开 host 源码直接分类**：

- generated 文件名、archive 和入口全部以 `kgsp` / `GSP` / `FMC` 命名；
- `generated/g_kernel_gsp_nvoc.c:773-799` 使 GB202 落到
  `kgspGetGspRmBootUcodeStorage_GB100`；该方法在 confidential-compute 分支选择
  `ConcatenatedFMC` image/descriptor（`kernel_gsp_gb100.c:124-152`）；
- sibling 实现的公开接口名就是 `kgspGetGspRmBootUcodeStorage`，并在
  `kernel_gsp_gh100.c:1051-1081` 把该 archive 赋给 GSP-RM boot ucode storage；
- FSP 侧 `kern_fsp_gh100.c:784-821` 的函数叫 `kfspGetGspUcodeArchive`，日志明确为
  `Loading GSP-RM image using FSP`，说明 FSP 是验证/启动方，payload 是 GSP image。

所以无论 opaque bytes 内部是什么 GSP-FMC monitor 功能，都不能把它重命名为
FSP runtime，更不能据此认定存在 task-2 dispatcher。对全部 generated bindata
`// FILE NAME:` 行做不区分大小写的 `fsp` 精确过滤为 0；GB202 的 firmware-like
条目均是 `g_gsp_*_gfw_*`、GSP-FMC、GSP-RM boot 等 host-supplied GSP 材料。

### 2.3 可读 GSP ELF：可分析，但属于错误的执行域

`/tmp/gsp_inner_19f040_a.elf` 是可读的 RISC-V ELF；既有 provenance 和 bounded
audit 已闭合其来源及若干 GSP 函数。它是 GSP-RM，不是由 Bootfsm 在 chip reset
后启动的 FSP runtime。本轮没有重扫其 text、caller 或 transport；把 GSP sender
或 GSP `0x8200f8` read 再命名为 FSP consumer 会混淆两个执行域。

## 3. consumer 搜索的最终边界

公开 GB202 FSP HAL
`src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb202.c:50-61` 只说明：Bootfsm 在
chip reset 后触发 FSP，host 等待 FSP 写 boot-complete scratch。它没有加载一份
host-visible FSP image，也没有暴露 task dispatcher。

结合既有全文精确检索与本轮 bindata/object 分类，目前可读材料中仍只有：

1. MODS 的 task-2 **producer/sender**；
2. OpenRM/GSP 的 FSP transport、通用 parser 与 GSP boot payload；
3. encrypted v6 `app=0x24/target=0x0f` 候选字节对象；
4. 没有可读的 GB202 FSP task table、task-2 handler、subobject-1 switch 或
   d0/dc/f8 setter/restore body。

在公开 FSP include/source 与 generated bindata metadata 的限定范围内，精确检索
`task2`、`task 2`、`subobject1`、`subobject 1`、`0x8200d0`、`0x8200dc`、
`0x8200f8` 没有产生 consumer 命中；唯一 PRC-specific public error token仍是
`FSP_ERR_PRC_ERROR_INVALID_KNOB_ID`。这不能证明 FSP 内部没有 consumer，只证明
当前可读 host tree 没有其实现。

**最终 consumer 判定：UNKNOWN。** 当前材料边界停在 encrypted/opaque FSP
候选与 chip-internal/ROM boot 边界；在不解密、不绕过认证且不运行 firmware 的
约束下，没有合法的下一层静态指令体可审计。

## 4. 返回字段：能说到哪一层

### 4.1 MODS task-2 caller 实际消费的是状态

`parallel/task2_lifecycle_audit.md` 已闭合：GB20x `+0x520` 调 common sender 时参数
为 task `2`、subobject `1`，response-vector 参数 `r8=0`。common sender 完成
transport send 与 response-completion/parse 后，把最终非零/零状态返回；caller
只用该状态决定是否继续 host apply。没有 response object、permission token、
prior PLM value 或 undo handle 被保存。

因此，对这个具体 MODS caller，最严格的“返回字段”答案是：**host 可见结果只有
同步调用 status；没有 caller-owned task-2 response vector。**

### 4.2 公开 610 通用 response 只有三个字段

公开
`arch/nvalloc/common/inc/fsp/nvdm_payload_cmd_response.h:35-42` 定义：

```c
NvU32 taskId;
NvU32 commandNvdmType;
NvU32 errorCode;
```

`kern_fsp_gh100.c:465-500` 只检查长度、记录这三个字段，并把 `errorCode` 映射为
`NV_STATUS`。`kern_fsp_gh100.c:1583-1608` 的公开 mapper 只认识 success、少量
IFS/IFR generic error 和 PRC invalid-knob-ID；没有 floorsweep/task-2-specific
状态，也没有“PLM lowered”“permission still open”“restored”之类返回码。

整个公开 `arch/nvalloc/common/inc/fsp/` 目录只有五个 header。capability query 与
TNVL 的专用 response 会在通用 command response 后追加各自 payload；目录中没有
floorsweep/task-2 response struct。特别是通用三字段中**没有 subobject**。

边界必须分开：公开三字段 schema 是 610 FSP 通用 parser 的 FACT；当前没有可读
task-2 consumer/schema 来证明闭源 MODS 的每个 wire byte 必然完全等同于这个公开
结构。两条独立事实能共同支持的最强结论只是：MODS task-2 caller 不接收额外
vector，而公开 command response 也不提供任何权限状态证明。

## 5. 对 d0/dc/f8 修改与恢复的最终判定

### `0x8200d0` / `0x8200dc`

- **FACT（sibling/host）**：Hopper 同 task/subobject 在发送前检查 d0/dc 是否已为
  `0xf`；GB20x task 2 在 host floorsweep apply 之前同步完成。
- **INFERENCE（较强）**：task 2 旨在为至少 d0/dc 的 floorsweep 写准备权限。
- **UNKNOWN（GB202 effect）**：没有可读 consumer、response snapshot 或运行值，
  所以不能证明它具体写入什么值、何时写、是否在 ack 前已经恢复。

### `0x8200f8`

- **FACT（visible negative）**：Hopper precheck 与 `SkipFspFs` 校验只覆盖 d0/dc；
  task-2 host 参数和公开 response 都没有 f8 字段。
- **UNKNOWN**：encrypted/opaque consumer 可能用动态地址或内部表访问 f8；当前也
  可能完全不处理 f8。两者均无法由 plaintext zero-hit 区分。

### restore / close

- **FACT（host path）**：正常 `+0x520` 返回后没有第二条 task-2、inverse flag、
  undo handle、PLM setter 或固定 reset；FSP object `+0x31` 清零只是 in-flight flag。
- **FACT（response/schema）**：没有 prior value、restore result、lease/expiry 或
  close token 可供 host 驱动恢复。
- **UNKNOWN（FSP/hardware）**：自动收权可能绑定 response、首个受保护写、timer、
  init phase、session、reset 或其他内部状态机。host 没有显式 restore 不等于
  firmware 不会 restore；同样也不证明权限会持续。

## 6. 负结果覆盖范围与资源记录

### 覆盖到的范围

- 三个唯一 v6 target immediate region，共 618,496 bytes：熵、ASCII run 和列明的
  双端 register/text exact patterns；
- `/tmp/fmc_gb202_prod.bin` 全部 503,808 bytes：来源逐字节闭合、公开 descriptor
  字段、分区熵、ASCII 与列明 exact patterns；
- 610.43.03 的 FSP public headers/source、GB202 FSP HAL、GSP-FMC selection 和
  generated bindata filename/metadata；
- 既有 task-2 lifecycle、VBIOS inventory、GSP provenance 与 bounded GSP audit。

### 没有覆盖、不能由负结果排除的范围

- encrypted-flag v6 target 认证后展开或解码后的 plaintext；
- chip ROM、Bootfsm 私有 image、设备内认证后展开代码或未保存的 firmware；
- 动态/表驱动/编码后的寄存器地址与 task ID；
- FSP 内部 permission lifetime、one-shot 消费点、失败/重试/reset 状态机；
- 任何 live GPU 状态或本卡实际 PLM 值。

### 资源

- 核心可复现 pass 按行读取 2,993,858-byte（约 2.86 MiB）generated C，只保留
  478,456-byte compressed array 与 503,808-byte output；三个 VBIOS region 使用
  seek 后逐个读取，不在内存中保留任何完整 raw image；
- 该合并 pass 在 `/proc/self/status` 记录 `VmHWM: 19864 kB`、
  `VmRSS: 18832 kB`、`VmPeak: 34900 kB`，低于 256 MiB 目标；
- 没有创建固件副本、反汇编数据库或大中间文件；唯一项目写入是本报告。

## 7. 最终可引用表述

> 当前本地材料仍未提供可读的 GB202 FSP task 2/subobject 1 consumer。VBIOS 中
> `app=0x24/target=0x0f` 的三个唯一 v6 payload 均被 descriptor 标为 encrypted
> 且接近满熵；新复核的 503,808-byte 小对象则逐字节属于 610 的 GSP-FMC/GSP
> boot bindata，不是 FSP runtime。MODS task-2 caller 只消费同步 status，公开 610
> 通用 response 只有 `taskId/commandNvdmType/errorCode`，没有 subobject、PLM
> 快照、权限 token 或 restore handle。因此 d0/dc lowering 仍是 sibling 与时序
> 支持的强推断，f8 effect 以及 d0/dc/f8 的自动恢复均保持 UNKNOWN；可见 host
> 路径无显式第二次 close/restore，只是限定 host-side negative。

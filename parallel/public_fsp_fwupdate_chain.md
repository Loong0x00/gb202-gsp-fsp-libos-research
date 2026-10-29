# Public FSP firmware-update chain（纯静态、有界）

日期：2026-07-22（Asia/Singapore）

## 0. 范围与结论先行

本报告只读检查：

- `/usr/src/nvidia-610.43.03` 的公开 NVIDIA RM 源码；
- 已保存的 `nvflash` 5.877.0（SHA-256
  `d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780`）；
- 项目中已保存的 HPE/Dell `.fwpkg`、`.nvfw` 及既有静态报告。

没有执行 `nvflash`、updater、MODS 或任何固件；没有访问 GPU、驱动设备节点、
PCI/BAR/MMIO、debugfs、reset 或网络。

核心结论：

1. **FACT：**公开 610 RM 只公开了 `NVDM_TYPE_FIRMWARE_UPDATE = 0x12` 这个
   消息类型常量；整棵公开源码中没有 type `0x12` 的 payload 定义、发送者、处理器
   或子命令枚举。公开部分只能看到通用 MCTP/NVDM 分片运输和三字段响应。
2. **FACT：**保存的 `nvflash` 不是把 `.fwpkg` 当成完全 opaque 文件：host 会解析
   DSP0267 package header、设备/组件记录，检查 UUID、header size 和 CRC32，再按
   component offset/size 取出数据；它也识别外层 `NVFW`。
3. **FACT：**已识别的 `nvflash` Falcon descriptor classifier 对 Blackwell
   `0d 06 50 00` 没有 v6 case，会错误落到旧 GFW-v1 catch-all。没有证据表明 host
   理解、解密或验证 nested `FSP_RUN` v6 body。
4. **FACT：**`nvflash` 确实实现 NVIDIA vendor `0x10de`、NVDM type `0x12` 的私有
   firmware-update client，至少有编号 1–7 的命令，并能接收 raw status；但命令
   名称和 payload schema 没有公开。
5. **FACT：**DSP0267 的职责边界是 Update Agent 解析 package/header/component 并
   推进更新，Firmware Device 在 `VERIFY` state 按实现选择的方法验证组件。
   **INFERENCE：**`nvflash` 的 PLDM 状态机和 NVDM `0x12` client 很可能构成
   host-to-device bridge；本次没有闭合“每个 PLDM command 对应哪个 NVDM 子命令”。
6. **FACT：**公开 response 最多直接给 host `taskId`、原命令的 NVDM type 和
   `errorCode`。它能说明请求是否成功、粗略失败类别；它不暴露 key、fuse、SKU
   rule、policy table 或怎样绕过授权。

因此当前能够重建的是“host 包解析 -> 私有更新运输 -> device verify/status”的职责
分层，而不是 `FSP_RUN` v6 格式或可用的解锁写法。

## 1. 分层链路

```text
.fwpkg on disk
    |
    | host / Update Agent：解析 DSP0267 header、匹配记录、CRC32、component ranges
    v
component byte buffer（例如外层 NVFW）
    |
    | nvflash 内有 PLDM update state machine
    |              |
    |              +-- exact PLDM <-> NVDM subcommand mapping：UNKNOWN
    v
NVIDIA vendor MCTP/NVDM type 0x12，private subcommands 1..7
    |
    | generic packet fragmentation / receive status
    v
GPU Firmware Device / FSP-side private handler
    |
    | DSP0267 VERIFY：实现相关的组件验证方法
    v
verify/apply result -> host 显示 stage/result/status
```

这条链必须与另一个公开链分开：

```text
already-running FSP <- NVDM type 0x14 COT
                      (GSP-FMC sysmem address + hash + signature + public key)
```

type `0x14` 是 host 让已经启动的 FSP 验证/启动 **GSP-FMC/GSP-RM** 的公开例子；
它不是 type `0x12` firmware update，也不是 host 上传 `FSP_RUN` runtime。

## 2. 公开 RM：type `0x12` 的边界在哪里

### 2.1 只有类型号，没有公开 payload/handler

`nvdm_format.h:43-59` 在共享 namespace 中定义：

```text
0x11 HULK
0x12 FIRMWARE_UPDATE
0x13 PRC
0x14 COT
0x15 FSP_RESPONSE
...
```

对 `/usr/src/nvidia-610.43.03` 做完整文本搜索，
`NVDM_TYPE_FIRMWARE_UPDATE` 只有
`src/nvidia/arch/nvalloc/common/inc/nvdm_format.h:45` 这一处命中。

**FACT：**公开树没有以下任一项：

- firmware-update payload struct；
- command/subcommand enum；
- type `0x12` caller/sender；
- FSP-side handler；
- package/signature policy implementation。

**UNKNOWN：**这些定义在私有 RM、`nvflash` 自身、FSP runtime，还是几者共同持有。
公开源码不能把 1–7 号命令命名。

### 2.2 公开 transport 不看 payload body

`src/kernel/gpu/fsp/kern_fsp.c:473-576` 的 `kfspSendMessage()` 只做：

- 用调用者给出的 `nvdmType` 创建 NVDM header；
- 按最大 packet size 分片；
- 复制 payload bytes；
- 经 FSP queue 发送。

`kern_fsp.c:599-683` 只重组接收分片，再把完整 message 交给 NVDM dispatcher；
`kern_fsp.c:707-747` 只是 send -> poll -> read 的同步 wrapper。

**FACT：**这层是 generic byte transport，不解析 PLDM package、NVFW 或 Falcon-v6
body，也不做 package/signature 验证。

### 2.3 公开 response 能看到什么

`arch/nvalloc/common/inc/fsp/nvdm_payload_cmd_response.h:35-42` 定义 packed response：

```c
NvU32 taskId;
NvU32 commandNvdmType;
NvU32 errorCode;
```

`kern_fsp_gh100.c:426-501` 接受 response type `0x15`，打印上述三个字段，再映射
错误。`kern_fsp_gh100.c:1583-1609` 的公开映射只有：

| FSP raw code | host mapping |
|---:|---|
| `0` | success |
| `0x9f` | object not found |
| `0x9e`, `0xa1` | invalid data |
| `0x1e3` | invalid argument |
| 其他 | generic error |

`kern_fsp_retval.h:25-29` 还定义 `0xa0 = NOT_SUPPORTED`，但该 mapping 没有专门
保留它，会落入 generic error。

**FACT：**raw log 若能保留，可指出 task/type/error；上层 `NV_STATUS` 会丢失大部分
细节。成功的准确含义只是“FSP 报告该 command processed successfully”，不能自动
推出某个隐藏 mask、fuse shadow 或 cache slice 已按期望生效。

**UNKNOWN：**type `0x12` 是否另有比三字段 generic response 更丰富的私有 reply。

## 3. 已保存 `nvflash`：host 解析到哪一层

### 3.1 `.fwpkg` / DSP0267 是 host-side parser

有界反汇编已定位：

- `.fwpkg` extension dispatch：`0x445e2a..0x445e43` 和
  `0x44b6ce..0x44b6e7`，进入 parser `0x4708e4`；
- PLDM package parser：`0x4735c0`；
- UUID 检查：`0x473606..0x473630`；
- declared header length 检查：`0x473c9c..0x473d25`；
- polynomial `0xedb88320` 的 CRC32 复算：`0x473cde..0x473d60`；
- 按 component size 分配/复制 byte ranges：`0x473d62..0x473f20`；
- 外层 `NVFW` magic 的识别路径：`0x45d317`，另一路在
  `0x451ed8/0x451eeb`。

本地包也提供机械交叉验证：

- Dell/HPE 的开头都是 DSP0267 v1 UUID
  `f0 18 87 8c cb 7d 49 43 98 00 a0 2f 05 9a ca 02`；
- Dell header CRC32 `0x5d4e81de`、HPE `0xdbdb9d70` 均复算一致；
- Dell 是一份 component，HPE 是两份 component。

**FACT：**Update Agent 至少理解 package metadata、匹配记录、component 边界和
外层 NVFW；“host 完全不看包，整文件盲传”不成立。

**FACT：**header CRC32 只检测 PLDM header 损坏，不是发布者身份认证。

### 3.2 包外层签名与 inner firmware 验证不能混称

HPE 两个登记组件结束于 `0x219ecd`，之后有真正的 `0x400` footer。其内容包括
随包携带的 P-384 SPKI 公钥和 DER ECDSA signature；对精确范围
`package[0:0x219fb5)` 做 ECDSA P-384/SHA-384 verification 成功。Dell package 在
唯一 NVFW component 末端直接 EOF，没有同型 footer。

**FACT：**HPE 文件的外层 byte sequence 在密码学上自洽；修改 signed range 会让
原签名失效。

**UNKNOWN：**`nvflash`/FSP 是否强制验证这个 HPE-specific footer、是否 pin 该公钥
或公钥 hash。footer 只有随包裸 SPKI，没有本地闭合的 HPE/NVIDIA X.509 trust
chain；“签名数学有效”不等于“发布者身份已由可信根证明”。

**FACT：**Dell 没有同型 footer，因此该 footer 不是所有 GB202 NVFW 被设备接受的
通用必要格式。inner NVFW/Falcon authentication 是另一层。

完整分解和签名复算见 `parallel/fwpkg_container_auth.md`。

### 3.3 host 没有被证明理解 `FSP_RUN` Falcon-v6 body

已识别的 Falcon classifier 在 `0x7dde66`。输入 Blackwell descriptor 首字节
`0d 06 50 00` 时，它不检查 version 6 或 size `0x50`，而在 `0x7ddead` 落到 enum
3、按旧 `GFW_STYLE_V1` 解读，甚至会把 `FSP_RUN` ASCII 的一部分误报成巨大的
legacy DMEM size。

**FACT（有界 negative）：**没有找到显式检查 version 6 + size `0x50` 的第二个
Falcon body parser；详见 `parallel/nvflash_v6_parser_reverse.md`。

**FACT：**字符串 `fsprt` 在该 ELF 中只是 component/region ID `1` 的显示标签
（xref 附近 `0x52c395`）；它证明工具知道一个名为 FSP runtime 的 region 类别，
不证明工具理解、解密或验签 v6 body。

**UNKNOWN：**host 可能定位并 opaque-copy nested object；opaque carrying 不等于
schema parsing 或 cryptographic verification。

## 4. `nvflash` 的私有 NVDM `0x12` client

有界反汇编在 VA `0xd360c8` 找到一张相关 vtable：

| vtable slot | method | 静态可证动作 |
|---:|---:|---|
| `+0x00` | `0x797110` | 校验收到的 MCTP vendor frame/header |
| `+0x20` | `0x793c3c` | 构造 NVDM `0x12`，command `1` |
| `+0x28` | `0x793f52` | command `2` |
| `+0x30` | `0x794258` | command `3` |
| `+0x38` | `0x7963f8` | command `4` |
| `+0x40` | `0x79779a` | command `5`，读取 reply status/data |
| `+0x48` | `0x79455e` | command `6` |
| `+0x50` | `0x79487a` | command `7` |

各 method 的共同 header 字段是 MCTP vendor-defined message `0x7e`、NVIDIA vendor
ID `0x10de`、NVDM type `0x12`，随后是 command dword 和各自数据。ELF 还包含
`NVDM firmware update receive failed with error code 0x`；`0x797a3a..0x797a78`
在 receive virtual call 返回后读取 response object `+0x0c` status 并显示 raw code。

**FACT：**这是 type `0x12` 真正存在、且至少有七个私有操作的静态证据；公开 RM
缺少的是 schema/命名/handler，不是“这个协议根本不存在”。

**FACT：**`0x797110` 检查 message type、vendor/header 和长度，是 frame validation，
不是 firmware signature verification。

**UNKNOWN：**command 1–7 的准确名字、字段、调用顺序、哪些是 data transfer、哪些
是 status/commit/abort，以及哪一条触发 device-side VERIFY。不能仅凭编号给它们
强行套上 PLDM command 名称。

## 5. 谁负责 package/signature verification

[DMTF DSP0267 1.0.1](https://www.dmtf.org/sites/default/files/standards/documents/DSP0267_1.0.1.pdf)
给出的标准角色边界是：Update Agent 解析 package header/components 并驱动更新；
Firmware Device 进入 `VERIFY` state 后验证传入组件，验证方法由实现决定。

结合本地证据，最窄且可靠的职责表如下：

| 层 | 已证责任 | 未证部分 |
|---|---|---|
| host `nvflash` / UA | 解析 DSP0267 metadata；UUID/size/CRC32；选择、切分 component；识别外层 NVFW | 是否/如何强制 HPE footer trust；v6 inner schema/crypto |
| generic public RM transport | 分片并搬运任意 NVDM payload；重组 response | type `0x12` schema、policy、handler |
| Firmware Device / private FSP path | 按 DSP0267 state machine 返回 transfer/verify/apply status | inner v6 的精确 verifier、key root、SKU/fuse policy |
| GB202 boot chain | BootFSM 在 reset 后启动 FSP；public host 等待 FSP ready | VBIOS `FSP_RUN` v6 object 的具体 ROM/FSP loader 实现 |

**INFERENCE（强）：**nested `FSP_RUN` 的最终真实性/解密检查在 GPU 内部 secure-boot
chain，而不是当前已识别的 host descriptor parser。依据是：host parser 不支持 v6，
GB202 public RM 不提取/上传该对象，且 BootFSM 在 RM 接管前已触发 FSP。

**UNKNOWN：**具体 verifier 位于 BootROM、BootFSM microcode、早期 FSP partition，
还是这些阶段的组合；公开材料尚不能命名。

## 6. type `0x14` COT 是有用旁证，但不是答案替身

公开 COT struct 在 `kern_fsp_cot_payload.h:37-55`，包含
`gspFmcSysmemOffset`、`hash384[12]`、`publicKey[96]`、`signature[96]` 和 boot args。
`kern_fsp_gh100.c:951-1047` 从 bindata 取出 image/hash/signature/public key，把 image
放到 sysmem，再把认证材料复制进 COT；`1258-1475` 首先等待 FSP secure boot，
`1499-1528` 才以 NVDM type `0x14` 发送。

**FACT：**host 把 signed GSP material 交给已经运行的 FSP；这里没有 host crypto
verify call，也没有 `FSP_RUN` body。

**INFERENCE（强）：**这个公开设计说明 NVIDIA 的典型职责是 host 提供 blob 和认证
材料，FSP/device secure stage 执行接受/拒绝。但不能据此推出 type `0x12` 每个私有
component 都使用完全相同的 COT 格式或 key policy。

## 7. status 能否透露“授权策略”

保存的 `nvflash` 含有独立的 transfer、verify、apply、get-status 流程和错误文本，
包括 verify result/timeout、signature verification failure、returned PLDM/NVDM code。
因此：

- **FACT：**status 可以定位失败阶段，例如 package 本地解析、transport、device
  verify 或 apply；某些错误还可区分 invalid data/not supported/signature failure。
- **FACT：**公开 generic response 保留 command type 和 raw `errorCode`，但公开映射
  会把多数未知值压成 generic error。
- **INFERENCE：**若未来在完全隔离、可恢复的测试平台只做合法原包 dry-run/查询，
  raw log 可能帮助判断门槛发生在哪一层。
- **UNKNOWN：**某个 code 背后究竟是 key hash、board ID、SKU、rollback counter、
  fuse state、PLM 还是别的 policy。status 没有返回规则表或 verifier 内部状态。

最重要的语义限制是：protocol success 只证明命令在该层被接受/处理，不能单独证明
物理 cache slice 已启用；反之 generic failure 也不能自动定位到某一种 fuse/policy。

## 8. 对当前 L2 解锁研究的直接含义

- **FACT：**这条研究没有得到可以安全调用的 type `0x12` payload，也没有得到
  Falcon-v6 字段定义、签名私钥、trust-root bypass 或 L2 mask command。
- **FACT：**“改 `.fwpkg`/NVFW 然后重签外层”不是闭合方案：HPE footer trust 尚未
  闭合，inner secure-boot/SKU policy 更没有闭合；Dell 又证明 HPE footer 不是普适
  接受条件。
- **INFERENCE：**type `0x12` 最有价值的是作为将来理解 device update/verify 边界的
  观测点，而不是当前可以直接拿来改 L2 的入口。
- **UNKNOWN：**L2 disable/effective-mask 是否存在于任何可更新 component，或者在
  boot-time fuse/shadow/policy 已经决定。这里没有新证据把它放进 firmware-update
  payload。

## 9. 一句话答案

host 会读 `.fwpkg` 和外层 NVFW、做格式/CRC/组件切分，但没有被证明能读懂
`FSP_RUN` v6 body；公开 RM 只留下 `NVDM 0x12` 类型号和通用运输/响应，真正的更新
schema、验签实现与授权策略在私有 device/FSP 链中。返回码能告诉我们“哪一阶段、
哪一类失败”，不能告诉我们“怎样绕过或改哪一个策略”。

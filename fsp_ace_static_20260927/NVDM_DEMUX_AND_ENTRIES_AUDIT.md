# GSP 610.57 NVDM 解复用与宿主入口静态审计

日期：2026-09-27。范围：本地只读、静态反汇编及开源源码交叉参照；未碰 GPU/驱动/VM、未执行固件、未联网。目标镜像 `power_governor_reverse/gsp61057_rx_full.bin`，RV64GC，基址 `0x1000000`，故 VA = 文件偏移 + `0x1000000`。证据等级：A=610.57 指令直接证实；B=结构/跨源码参照；U=未闭合。**不将 610.43.03 host 驱动源码当作 610.57 GSP/FSP 固件证据。**

## 0. 结论摘要

1. **命令队列接收路径 `0x1016104` 没有校验 NVDM type。**它校验 MCTP version=1、NVDM vendor ID=`0x10de`、checksum 和 seqNum；`nvdmHeader` 的高字节（NVDM type，offset `+7`）被截掉而未比较。故本路径无论 type 是否 `0x25`，都会继续按 RM_RPC staging 格式处理。此结论仅限该队列路径，不等同于“整个 GSP 无其他 type demux”。（A）
2. `0x1016104` 的两个直接调用点是 `0x1a8b3d4`（caller 函数 `0x1a8b374`）和 `0x1a92356`（caller `0x1a91e90`）。这是宿主共享 command queue 的收包路径。复制循环受 `rxAvail` 限制，并从已拷贝数据 `staging+0x10` 取首个 RPC payload dword 推导所需元素数；真正 RPC `length` 的读取点是 `staging+0x18`，在复制后检查。其容量缺失即已知 **K3-1**，本报告不重复报为新发现。（指令级 A；字段语义交叉参照 B）
3. **未在已审阅的 610.57 GSP 指令中定位到处理 `NVDM_TYPE_FSP_RESPONSE(0x15)`、`SMBPBI(0x18)` 或 `FSP_GSP_COMM(0x21)` 的独立 NVDM type 分派器。**610.57 GSP 内可见的 `0x1b594d0` 确实有类型分派，但它分派的是内部 MCTP 应用 opcode（`msg[0]` 为 `0x0f..0x14`），不是 NVDM header 的 byte 7；每种拷贝长度为立即数。不能据此替代 FSP runtime 的 NVDM handler 分析。（A/U）
4. 610.43.03 开源 host driver 参照中，FSP/SEC2 收包的 NVDM type `0x15/0x18` 都路由到同一 command-response handler；该 handler 在结构体读取前检查 `size >= 1 + sizeof(NVDM_PAYLOAD_COMMAND_RESPONSE)`。这只证明对应版本的**host 接收端**实现，不能证明 610.57 GSP/FSP firmware 的处理方式。`0x21` 仅找到类型定义/alias，未找到该源码树中的 handler 使用。（B）
5. **未确认 K3-1 之外的新 610.57 宿主可达长度/计数漏洞。**E3 的完整 RPC function 映射、E7 的运行时类/方法表以及 startup 参数解析尚未闭合；因此不是对这些下游 handler 的“全量安全证明”。

## 1. 线格式和具体比较点

开源参照定义（`driver_gpio_internal_610.43.03/src/nvidia/arch/nvalloc/common/inc/mctp_format.h:39-58`、`nvdm_format.h:48-61`）：

| 偏移 | 字段 | 610.57 command queue 解析情况 |
|---|---|---|
| `+0..3` | MCTP transport header；version 在 bits 3:0 | 检查低 nibble 等于 1；其他 transport bits 未在此函数作为 NVDM type 检查 |
| `+4..7` | MCTP message/NVDM header；message type bits 6:0、IC bit 7、vendor bits 23:8、NVDM type bits 31:24 | 只比较 vendor=`0x10de`；消息 type、IC、NVDM type 未见比较 |
| `+8...` | payload；RM_RPC type 常量为 `0x25` | 作为 RPC queue element/RPC header 处理 |

610.57 关键指令（`ev_recv_mainline_0x1016232.asm`，同镜像 VA）：

```asm
0x1016264  lw       a1, 0(s5)             ; MCTP transport dword
0x1016268  lw       a5, 4(s5)             ; MCTP/NVDM message-header dword
0x101626c  andi     a1, 0xf
0x101626e  bne      a1, s9, ...           ; s9=1：检查 MCTP version
0x1016272  srliw    a5, a5, 8
0x1016276  slli     a1, a5, 0x30
0x101627c  srli     a1, 0x30              ; 仅保留移位后的低 16 位=原 header bits 23:8
0x101627e  addi     a2, a2, 0xde          ; a2=0x10de
0x1016282  bne      a1, a2, ...           ; 仅比较 vendor ID
0x1016286  lw       a2, 0xc(s5)
0x101628a  bne      a2, s10, ...           ; seqNum 检查
```

由 `mctp_format.h` 字段定义可直接推出：`srliw 8` 后再取低 16 位会保留 vendor bits、丢弃原 bits 31:24（NVDM type）。这不是对 NVDM type 的比较。也没有在上述序列中比较 message type `0x7e`。该证据支持“队列只校验 vendor（另有 version/seq/checksum）”，但不支持“GSP 所有接收路径均没有 type 检查”。

### 1.1 长度/计数信任与次序（K3-1，已知项）

`0x1016104` 直接装载 MQI/staging 指针：`0x101612a ld s8,0x1a8(s11)`（queue handle）、`0x101612e ld s5,0x198(s11)`（RX staging）。逐元素拷贝循环先读取 `rxLinked`/`rxAvail`（`0x101614c-0x1016156`），按元素尺寸 `0x84(handle)` 与 queue source `+0x28(handle)` 计算源地址（`0x101615a-0x101617a`），调用 backend copy helper（`0x101618c-0x1016192`），并推进 staging 指针（`0x101619e-0x10161a2`）。循环随后从已拷入 staging 的首个 payload dword 取值（`0x10161b6 lw s2,0x10(s5)`），加 queue header size 与 element size−1，再除以 element size 得出目标元素数（`0x10161ba-0x10161c6`），并继续拷贝至该数或 `rxAvail` 上限（`0x10161ce`）。**固件指令只证明这里使用 staging+0x10 的原始 dword；它没有在该处读取 staging+0x18 的 RPC length。** 610.43.03 公开 `rpc_message_header_v03_00` 将 payload 首 dword 标为 `header_version`，RPC `length` 位于 header 偏移 `+8`（`generated/g_rpc-message-header.h:41-50`）；这只是跨版本字段语义参照，不能代替 610.57 ABI 的固件证据。后续 `0x10162a2 addi s3,s5,0x10; 0x10162a6 lw a1,8(s3)` 才读取 staging+0x18，并在 `0x10162b0-0x10162b8` 检查 length+header size 的回绕及最大值；该检查在复制之后。此处没有先将累计拷贝量与 RX staging 容量比较。

拷贝完成后才走验证：checksum 分支在 `0x1016232-0x1016262` 或 plaintext 分支 `0x1016314-0x101633a`；随后是 version/vendor（上表）、seqNum（`0x1016286-0x101628a`），再验证真正 RPC length（按 610.43 ABI 参照为 header+8）及 queue 最大长度（`0x10162a2-0x10162b8`），之后才进入 consume/分发（`0x10162bc-0x10162c4`）。因此宿主可控头字段驱动的拷贝先于校验，是已知 K3-1，不另列新发现；将 `staging+0x10` 直接称为 RPC `length` 不受 610.57 指令支持。

该 staging 区与邻接对象的分配布局已由初始化指令核过：`0x1a99022` 分配 `0x200e8`；`0x1a9904e/0x1a99052` 将块首部登记为 RX staging；`0x1a99056` 登记 TX staging=`P+0x10000`；`0x1a9905a` 登记 metadata=`P+0x20000`。详见既有 `parallel/K3_STAGING_ADJACENCY_20260926.md`。这只用于说明 K3-1 的缓冲区边界，不构成新的漏洞报告。

## 2. 独立 type handler / 同名但不同层的 dispatcher

### 2.1 610.57 GSP 的 `0x1b594d0`：不是 NVDM type

已审阅函数 `0x1b594d0` 的 `msg[0]` 分派（细节见既有 `parallel/DS_GSP_MNOC_SERVER_20260926.md` §2.2）：先将 opcode 限制在 `0x0f..0x14`（`0x1b594ee`、`0x1b594fc`、`0x1b59520-0x1b59536`），之后跳转表按类型对固定长度 payload 执行复制：

| `msg[0]` | 固定拷贝长度 | 说明 |
|---:|---:|---|
| `0x0f` | `0x40` | `msg+4` 到固定全局缓冲 |
| `0x10` | `0xa0` | 同上 |
| `0x11` | `0x20` | 同上 |
| `0x12` | `0x44` | 同上 |
| `0x13` | 不拷贝 | unsupported/status 路径 |
| `0x14` | 不拷贝 | 状态路径 |

例如 `0x18bbd60` 将固定 `0xa4` 字节请求与 `0x78` 字节响应交给该 API，并检查返回首字节是否 `0x14`；这些长度是编译期常量，没发现由宿主声明长度驱动的 copy。此 `msg[0]` 是该 MCTP 服务协议的应用 opcode，不是 MCTP/NVDM header 的 NVDM type byte。该服务是 GSP↔FSP/MNOC 调用链，不能据此认定为宿主直达的独立 NVDM handler。

### 2.2 开源 host driver 参照：FSP/SEC2 响应类型

610.43.03 参照代码：

- `src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c:425-453`：`kfspProcessNvdmMessage_GH100` 读 `pBuffer[0]`，`0x15 FSP_RESPONSE` 和 `0x18 SMBPBI` 都转 `kfspProcessCommandResponse_HAL`，其他类型返回 `NV_ERR_NOT_SUPPORTED`。
- 同文件 `:465-500`：command-response handler 先检查 `size < sizeof(NvU8) + sizeof(NVDM_PAYLOAD_COMMAND_RESPONSE)` 并返回，再将 `pBuffer+1` 转为结构体并读 taskId/command type/errorCode；没有按 payload 内长度作动态复制。
- `src/kernel/gpu/sec2/arch/blackwell/kernel_sec2_gb20b.c:322-370` 有同形的 SEC2 type switch（`0x15/0x18`）和共用 response 结构长度检查。
- `kern_fsp.c:605-685` 的 `kfspReadMessage` 在重组拷贝前以 `payloadBufferSize < totalPayloadSize + curPayloadSize` 拒绝超容量；`kfspValidateMctpPayloadHeader` 要求最少含 NVDM type byte。该路径方向是 FSP→host receiver，且属于 610.43.03 host 源码。

`NVDM_TYPE_FSP_GSP_COMM=0x21` / `NVDM_TYPE_SEC2_GSP_COMM` alias 见 `nvdm_format.h:58-59`，但全树检索未找到 610.43.03 中对应 handler 的实际使用；不能据此断言 610.57 GSP 或加密 FSP runtime 中不存在该 handler。FSP runtime 本身是加密镜像，行为未知。**没有把 host-side handler 长度检查外推成 610.57 固件的安全结论。**

## 3. E1–E7 宿主→GSP 入口表（区分真正 ingress 与下游/反向接口）

| ID | 610.57 VA/路径与宿主可控字段 | 解析者、长度信任/检查 | 宿主可达性与本轮状态 |
|---|---|---|---|
| **E1 命令队列 RX** | `0x1016104`；共享队列元素、queue 可用计数、RPC header 各字段/参数数据；NVDM type byte 在 queue element `+7` | 首个 payload dword（`staging+0x10`）驱动复制所需元素数，另由 `rxAvail` 限制；真正 RPC length 在 `staging+0x18` 后置检查。checksum/version/vendor/seq/max length 均在拷贝后；NVDM type 未比较。 | 宿主通过 command queue 提交可达；两个直接调用点 `0x1a8b3d4`、`0x1a92356`。K3-1 已知，不重复作为新发现。（指令 A；字段名交叉参照 B） |
| **E2 GSP→host status/response queue** | 发送函数 `0x1016790`，不是 host→GSP 请求入口；host 主要消费响应/推进队列 | TX 路径在写头/拷贝前校验 `length + hdrSize` 回绕与 `sizeMax`：`0x10167d6-0x10167ec`；随后构造 `0x2510de7e`（RM_RPC NVDM header，`0x1016816-0x101681e`）。 | 方向为 device→host，列作对照，不计入 ingress。静态所见 fail-closed；不把它当作 E1 的防护。（A） |
| **E3 RM_RPC body/function dispatch** | E1 staging 后续 RPC header 的 function、sequence、length、payload 均宿主可控；固件用 `staging+0x10` 首 dword推导 RX 拷贝元素数，后在 `staging+0x18` 读取 length（610.43 header 结构仅作字段名参照）。 | E1 的先拷后验/容量问题见 K3-1。RPC function→具体 handler 的 610.57 全表、各 handler 的二级长度检查本轮未闭合；不能据此给所有 RPC 参数判安全。 | 是 E1 后的下游解析层，不是第二条独立物理入口。保留为未闭合攻击面。（U） |
| **E4 其他 NVDM types（0x15/0x18/0x21 等）** | 对同一 GSP command queue，当前证明为 NVDM type 不参与 E1 分派；GSP 内 `0x1b594d0` 是不同的内部 opcode 分派。host-facing FSP EMEM/MNOC 可由宿主送往 FSP，但不是直接 GSP RX。 | GSP 610.57 独立 NVDM handler 尚未定位；0x15/0x18 的共同 response handler 及 size guard 仅见于 610.43 host 参照。0x21 的 GSP/FSP handler/长度未知。 | 当前不确认额外 GSP ingress。FSP runtime 加密，不能从 GSP 客户端/host driver 推断其 handler。（U） |
| **E5 msgq / RX metadata backend** | 不是另一 wire entry；是 E1 消费宿主共享 queue 的设备侧 msgq 层。宿主控制队列数据/实际投递元素。 | `0x1016104` 对 `rxAvail`/RPC length 的使用见 §1.1；初始化的 `msgqMetadata` 及 backend copy 回调在 staging 邻接文档中有逐字段证据。此层不能“替代”E1 中缺失的 staging 容量校验。 | 通过 E1 可达，独立于 E1 的新宿主入口未证实。（A/B） |
| **E6 log/event/status 队列** | 现有清单中的 GSP log/event/status 方向是 GSP→host；host 消费事件记录。 | 不是本次 host payload 的通用 ingress；host 对队列索引的控制与日志读取协议未做完整反向解析。 | 从 host→GSP 漏洞入口统计中排除；不代表所有事件控制寄存器均被审计。（U/范围限定） |
| **E7 RM class/method dispatch** | 经 E3 RPC 到 RM 后的运行时类方法/引擎 method；方法 ID、对象标识、参数块会由宿主侧 RPC 决定。 | 方法表由运行时构建；本轮未钉 610.57 分发表 VA/表布局，也未按 handler 审计所有 count/length 字段。 | 逻辑上经 E1 可达，但不是独立硬件入口；明确标为未完成，不能给负面安全结论。（U） |

### 3.1 入口范围限制

上述 E1–E7 是既有 `RM_HOST_IFACE_BUGHUNT_K3_20260925.md` taxonomy 的逐项更新，不是“所有可能的 host→GSP 字节来源已穷尽”的证明。启动期 firmware/init arguments、共享内存映射元数据及 BAR/MMIO 控制字段需要作为独立 bootstrap 面继续跟踪到 610.57 消费指令；本轮没有将 host-side `kernel_gsp.c` 初始化结构当成 GSP parser 证据。FSP 的 host-facing EMEM/MNOC 入口属于 FSP，而 FSP runtime 加密，不能算作已证明的 GSP ingress。

## 4. 新长度/计数问题判断

**新发现：无（本轮静态证据范围内）。**

- 唯一明确的“宿主计数/length 驱动接收拷贝，边界验证后置”是 `0x1016104`，其元素循环、RX staging 与校验顺序已属于已知 K3-1；按要求不重复登记。
- `0x1016790` 的 GSP→host TX length 有回绕和最大长度检查在构造/拷贝之前。
- `0x1b594d0` per-opcode copy 长度为固定立即数，且不是 NVDM type dispatcher；没有发现 host 声明 length 驱动的拷贝。
- E3/E7 handler 清单不完整，故不能把“未找到新问题”解释为这些二级 RPC/method parser 已全部安全。

## 5. 后续需闭合项

1. 在 610.57 plaintext 中继续定位 host RPC function 分发表及 E7 class/method runtime table，逐 handler 追 length/count→copy 与宿主可达路径。
2. 用 GSP 固件指令确认是否存在 command queue 之外的 host→GSP bootstrap/共享描述符 parser；当前 E1–E7 表对这些路径保留范围限制。
3. 如要审计 `0x15/0x18/0x21` 在 FSP runtime 中的独立 handler，必须取得可分析 plaintext；610.43 host driver 参照不能代替。

## 复核资料

- `parallel/k3_device_work/ev_recv_0x1016104.asm`
- `parallel/k3_device_work/ev_recv_mainline_0x1016232.asm`
- `parallel/K3_STAGING_ADJACENCY_20260926.md`
- `parallel/DS_GSP_MNOC_SERVER_20260926.md`
- `parallel/RM_HOST_IFACE_BUGHUNT_K3_20260925.md`
- 610.43.03 host 源码：`src/nvidia/src/kernel/gpu/{fsp/kern_fsp.c,fsp/arch/hopper/kern_fsp_gh100.c,sec2/arch/blackwell/kernel_sec2_gb20b.c}`；仅为版本化交叉参照。

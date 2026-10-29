# 615.78.08 RPC 拷贝与旧 K3 等价实现审计

日期：2026-10-27。范围：用户自有 GB202 的离线静态研究；未触发 GPU、RPC、复位或驱动操作，未修改现有实验驱动。

## 结论

**旧版 K3 的“声明 33 个元素 → GSP 先拷贝溢出至 `msgqMetadata` → 经 `rxrefresh` 回调指定地址”不能直接移植到 615.78.08。**

原因不是单个字段或偏移变化，而是两项前提同时消失：

1. 615 GSP 接收函数在首元素拷贝后立即检查 `mctpPayloadSize`，通过 `<= queueElementSizeMax` 后才计算后续元素数；因此最多继续接收 16 个 4 KiB 元素，不能到达 element 32 的 metadata。
2. 615 `msgqMetadata` 和 MSGQ v2 接收路径已重构。正常 RX 读/消费路径直接操作 head/tail 寄存器，不再存在旧版 `rxrefresh → fcnBackendRw` 的稳态回调。旧 `+0xb8` 地址和触发方式均不适用。

这只否定旧 K3 的移植，**不证明 615 没有其它独立漏洞**。下一步应审计新的 GMCAPI/NVKV 和 MSGQ v2 输入路径，而不是继续尝试旧 K=33。

## 样本与提取

Stock outer firmware：

- 路径：`/usr/lib/firmware/nvidia/615.78.08/gsp_ga10x.bin`
- SHA-256：`a20100cafd5a85e22b3e13188339730c6ced94bd5f654984dd2ed274ed58d584`
- outer `.fwimage`：文件偏移 `0x40`，大小 `0x19be000`

`.fwimage` 中有 12 个对齐的 inner ELF。主 GSP-RM 为其中最大的 RV64 镜像：

- `.fwimage` 内偏移 `0x1dd000`
- 大小 `0x1081098`
- RX `PT_LOAD`：文件 `[0, 0xed2000)`，VA `0x1000000`
- RW `PT_LOAD`：文件 `[0xed2000, 0x1081000)`，VA `0x4000000`
- inner SHA-256：`3b2af3707c17309fb9975d58b141e304224febf049c56b44a70778755b8ebcca`

复现：`python3 extract_gsp615.py`。输出在 `out/`。

## 1. Host 侧 RPC 构造已经改变

615.78.08 的 `GspMsgQueueSendCommand` 位于：

`/usr/src/nvidia-615.78.08/src/nvidia/src/kernel/gpu/gsp/message_queue_cpu.c:483`

与旧版的关键差异：

- API 变为 `GspMsgQueueSendCommand(pMQI, pGpu, nvdmType, size)`。
- 元素数由 `pCQE->mctpPayloadSize` 计算，不再由旧 `rpc->length` 计算。
- 非加密消息的实际 RPC payload 从偏移 24 开始，旧版为 16。
- 旧 `checkSum` / `seqNum` 被移除；新增 `mctpMagic`、`mctpPayloadSize`、`nvdmPayloadSize` 和 `MCTP_MAGIC_SEEN`。

因此旧补丁直接修改 `pRpcX->length`，既不再控制发送元素数，也不再控制 GSP 接收元素数。

`/home/user/gpu_src_615` 中已有一次 615.71 实验，只在 `nvdmType == 0x25` 时强制 host 的局部变量 `nElements = 33`，但保留原 `mctpPayloadSize`。这不等价于旧 K3：

| 输入状态 | 615 GSP 的预期行为 |
|---|---|
| host 只强制局部 `nElements=33`，头部保留真实小长度 | GSP 自己从头部重新计算，仍只接收真实数量；没有旧 staging 溢出 |
| 同时将 `mctpPayloadSize` 伪造成大于 `0x10000` | GSP 在首 4 KiB 元素后拒绝，不计算或拷贝第 33 个元素；仍不到 metadata |
| 伪造合法但不超过 `0x10000` 的长度 | 元素数最多为 16，仍不到 element 32 |

## 2. 615 GSP 接收函数：长度检查在后续拷贝之前

主 GSP-RM 中 `GspMsgQueueReceiveStatus` 的函数起点为 **`0x1013b10`**。函数在 `0x1013d0e` 构造并比较 `MCTP_MAGIC (0x4d435450)`，可据此确认其身份。

关键顺序（完整指令见 `out/gsp_receive_1013b10.asm`）：

```text
0x1013b54  开始接收循环
0x1013b88  若首个元素不存在则退出
0x1013b80  拷贝当前 4 KiB 元素到 staging（首元素尚在容量内）
0x1013bae  lwu a1, 4(s4)           ; pCQE->mctpPayloadSize
0x1013bb2  ld  a4, 0x20(s11)       ; queueElementHdrSize
0x1013bb6  长度小于 header 则失败
0x1013bba  ld  a4, 0x30(s11)       ; queueElementSizeMax = 0x10000
0x1013bbe  长度大于 max 则失败
0x1013bc2  此后才计算 nElements = ceil(mctpPayloadSize / 0x1000)
```

与旧版不同，`Incorrect message length` 不再位于全部元素拷贝之后。首元素拷贝本身只有 4 KiB，不构成旧式越界。

发送函数 `GspMsgQueueSendCommand` 位于 **`0x1013ed8`**，也使用新的 MCTP 字段，进一步确认 host 与固件协议一致。

## 3. 旧指定地址调用链不再存在

615 的 `msgqMetadata` 仍位于两个 64 KiB staging 之后，但大小由旧 `0xe8` 变为 **`0xa8`**。GSP 初始化代码 `0x101374a` 也使用该尺寸。

相关 RV64 布局：

| 字段 | 新偏移 | 旧利用中的意义变化 |
|---|---:|---|
| `rxAvail` | `0x90` | 正常 RX 在 `0x1013b5e` 等处读取 |
| `rxLinked` | `0x94` | 正常 RX 在 `0x1013b58` 等处读取 |
| `fcnBackendRw` | `0x98` | 只在 create/link 路径使用 |
| `fcnBackendRwArg` | `0xa0` | 同上 |

615 源码中 `fcnBackendRw` 只有两类调用：

- `msgqTxCreate`；
- `msgqRxLink`。

固件中的对应间接调用点为 **`0x1013846`** 和 **`0x10138cc`**。它们属于初始化/链接，不是旧 K3 的接收重试泵。

正常 `msgqRxGetReadBuffer` / `msgqRxMarkConsumed` 则直接：

- 从 `regRxHead` 读取生产位置；
- 用 `pTheirEntries + slot * msgSize` 取得元素；
- 更新 `rxReadPtr`；
- 通过 `osGpuWriteReg032(..., regRxTail, ...)` 写回消费位置。

因此，即使未来另有独立方式破坏 metadata，也不能直接套用旧 `meta+0xb8` 的地址调用模型；需要先找到新的可达间接控制点。

## 4. 后续研究入口

旧 K3 停止后，较合理的新静态目标是：

1. **GMCAPI_HEADER.size / max_response_size**：615 新增的 40 字节 GMCAPI 头与 NVKV 编解码路径；
2. **MSGQ v2 create/link 输入一致性**：版本、`msgSize`、`msgCount`、`entryOff` 与 backing-store 实际容量之间的关系；
3. **CC 分支**：`mctpPayloadSize` 与 `GSP_MSG_QUEUE_ELEMENT_ENCRYPTION_OFFSET` 的减法及加解密尺寸一致性；
4. 任何新发现的“攻击者控制长度在容量校验之前影响拷贝”路径，应单独建立证据，不能借用旧 K3 的结论。

## 证据文件

- `extract_gsp615.py`：stock outer/inner 哈希校验、主 GSP 提取、接收函数反汇编。
- `out/gsp_rm_615_78_08.elf`：主 GSP-RM 镜像。
- `out/gsp_receive_1013b10.asm`：接收路径完整关键反汇编。
- `/usr/src/nvidia-615.78.08/src/nvidia/src/kernel/gpu/gsp/message_queue_cpu.c`
- `/usr/src/nvidia-615.78.08/src/nvidia/src/libraries/msgq/msgq.c`
- `/usr/src/nvidia-615.78.08/src/nvidia/inc/libraries/msgq/msgq_priv.h`

## 5. 不需 K3 的现有接口（后续补充）

615.78.08 保留了 `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS (0x20800122)`。用户态 ABI 与旧 `rm_reg_probe` 相同；`gpuValidateRegOffset_IMPL` 检查 BAR0 范围，并在管理员路径下跳过用户寄存器 allowlist。因此可先用正式 RPC 让 GSP-RM 代读 FSP 地址，不必先移植溢出。

已新增 `rm_fsp_read_probe.c`，仅包含 READ_32 操作：PMC/EMEM/QUEUE 作正控制，再读 HWCFG1/HWCFG2/IMEMC/DMEMC。源码已通过 `gcc -O2 -Wall -Wextra -Werror` 编译检查，**未执行**。

另有 615 新增的 `_kfspGatherDmemLog_GB100()`：通过 MCTP VDM IANA `commandCode=0x06` 和 sessionId 分页下载 FSP DMEM 日志，每包最多 52 字节，host 缓冲上限 4096 字节。它是现成日志接口，不是任意地址/全代码读取；旧 610 源码中未见该实现。

## 6. 真机只读验证结果（2026-10-27）

用户授权后，以一次一个 RPC、每次读毕等待 100 ms 的方式执行了 `rm_fsp_read_probe`。结果：

| 地址 | 读值 | 解释 |
|---|---|---|
| `0x00000000` | `0x1b2000a1` | 设备/RPC 正控制有效 |
| `0x008f2ac0` EMEMC | `0x02000014` | GSP 自身 FSP 客户端正控制为真实值 |
| `0x008f2c00` QUEUE_HEAD0 | `0x00000000` | 消息面正控制有效 |
| `0x008f212c` HWCFG1 | `0xbadf5040` | GSP 视图同样过滤 |
| `0x008f20f4` HWCFG2 | `0xbadf5040` | GSP 视图同样过滤 |
| `0x008f2180` IMEMC0 | `0xbadf5040` | GSP 视图同样过滤 |
| `0x008f21c0` DMEMC0 | `0xbadf5040` | GSP 视图同样过滤 |

这使用正式的 GSP-RM `EXEC_REG_OPS`，不需要 K3，且有独立正控制，因此旧“GSP 侧 PRI 可能放行 IMEM/DMEM”的 R1 路线可关闭。

DMEM 日志则使用最终核对后的官方请求布局：`mctpHeader=0xc1000000`、`VENDOR_IANA=0x7f`、`IANA_NV=0x1647`、`RQ=1`、commandCode `0x06`、messageVersion `1`、sessionId `0xff`，14 字节请求按 16 字节对齐、TAIL=12。100 ms 后单次接收为 **none**。随后 CAPS 正控制正常返回 `{PRC 0x13,v1}`，证明 EMEM 通道仍活着。故只能判定“当前卡/当前 FSP 状态下该日志请求未获响应”，不能推广为所有 FSP 版本均不支持。

临时 `fsp-read-probe` 任务已从 `gpu-allowlist/tasks.json` 删除并恢复原配置。最终 nvidia-smi 正常、无新增 Xid。原始输出见 `out/fsp_read_probe_allowlisted_run.log`、`out/fsp_dmem_log_official_layout_first_packet.log` 和 `out/fsp_dmem_log_transcript.txt`。

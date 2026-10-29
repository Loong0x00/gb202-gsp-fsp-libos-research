# K3：FSP 固件提取与 MNOC/NVDM 消息接收路径静态分析

日期：2026-09-26。范围：只读本地文件（`vbios_diff/`、`driver_gpio_internal_610.43.03/`、
`vm_mods_lab/`、已提取 GSP RV64 ELF）。未碰 GPU/驱动/VM/MMIO，未执行固件，未联网。

证据等级：**FACT**（字节/代码可直接复核）/ **INFERENCE** / **UNKNOWN**。

---

## Q1. FSP 镜像提取 —— 已完成导出，但 payload 加密，无法静态反汇编

### 导出物（`parallel/k3_device_work/fsp/`，hash 与 `vbios_fsp_inventory.md` §4 的 hash-confirmed 值逐项一致）

| 文件 | 来源 raw image | 文件偏移 `[start,end)` | 大小 | SHA-256 |
|---|---|---|---:|---|
| `fsp_image.bin` | FE `98.02.2E.00.03.rom` | `[0x11b354,0x144754)` | 0x29400 | `1a546c20…4597214` |
| `fsp_image_dell8d.bin` | Dell `…8D.00.01.nvfw` | `[0x128154,0x15ed54)` | 0x36c00 | `3ba67345…e590c09` |
| `fsp_image_hpe9e.bin` | HPE `…9E.00.01.nvfw` | `[0x12cd54,0x163d54)` | 0x37000 | `12532859…999e9d9` |
| `*_descriptor.bin` | 同上各 desc 起点 −0x50 | 0x50 字节 | 0x50 | 见脚本输出 |

复核步骤：`python3 extract_fsp_v6.py <raw_image> <desc_abs> <前缀>`，切片规则
`region = [desc+0x50, desc+0x50+le32(desc+4))`，断言 `word0==0x0050060d`。

### 关键判定

- **加密（FACT 级）**：三份 region Shannon entropy = 7.999017/7.999129/7.999179 bit/B，
  头 16 字节无任何已知 magic；descriptor `flags=0x0d` bit2=ENCRYPTED
  （位定义：`kernel_gsp_fwsec.c:129-146`）。`fsp_image.bin` 是**密文信封**，
  不是可反汇编 plaintext。导出价值在于固定边界/hash 供后续 live 或差分使用。
- **ISA（INFERENCE，强）**：执行核是 PFSP Falcon——`kern_fsp_gb100.c:84` 直接用
  `NV_PFSP_MNOC_RX_FIFO_DATA(0)`；VBIOS 条目是 Falcon **v6** descriptor
  （`app=0x24/target=0x0f`）。指令集应为 Falcon 系，但 168–225 KB 体积远超典型
  Falcon IMEM，plaintext 落点更可能是受保护 EMEM/SRAM（与
  `fsp_postdecrypt_observability.md` 的 host 不可观测结论一致）。**UNKNOWN**：
  精确 ISA 版本与落点，未解密前不能定。
- **基址/入口（UNKNOWN）**：v6 schema 未公开，无可证入口字段。descriptor
  private words 的跨样本不变量（观察，非语义断言）：
  `word1 = word3 + word5`（FE `0x29400=0x25400+0x4000`；Dell `0x36c00=0x30c00+0x6000`；
  HPE `0x37000=0x31000+0x6000`）；`word10=0x01012801` 三样本恒定；
  `word6/7` 随 build 变化（`0x301/0x01030000` vs HPE `0x401/0x01040000`，像版本号）；
  `word2/4` 像分段尺寸。`+0x2d` 起 `FSP_RUN`，`+0x34..+0x50` 28 字节高熵尾
  （hash/IV 候选，未证）。**没有任何一个 word 可作为入口地址候选被证实。**

## Q2. MNOC 信箱接收路径 —— 协议面全部闭合；FSP 侧"先拷后验"与否静态不可判

### 协议面（FACT，全部有本地代码/工具复核）

- 长度字段位置：**MNOC INFO 寄存器 bits 19:0**（`MNOC_MESSAGE_SIZE_MASK=0x000fffff`，
  `gb202_fsp_prc_sweep.c:48`；官方名 `NV_MNOC_ZB_PRI_MESSAGE_INFO_0_*_MESSAGE_SIZE`，
  `kern_gpu_gb100.c:1281-1286`）。发送方（host 或 GSP）**自声明**长度，上限
  `mask+1 = 0x100000`（1 MiB，`gpuMnocMboxMaxMessageSize_GB100`，
  `kern_gpu_gb100.c:1524-1532`）。触发位 bit20，ERR bit25，CREDIT bit26，
  每写 64 B 需 CREDIT 握手（`gb202_fsp_prc_sweep.c:334-353`）。
- 报文布局（wire format）：dword0=MCTP 传输头（SOM bit31/EOM bit30/SEQ 29:28/
  SEID 23:16，`mctp_format.h:39-54`）；dword1=NVDM 头（type 在 byte7，
  `mctpCreateNvdmHeader`）；payload 自 byte 8。PRC 请求 `+8=cmd,+9=nbytes,+10=knob`；
  通用响应 `+8=taskId,+12=commandNvdmType,+16=errorCode`
  （`fsp/nvdm_payload_cmd_response.h:36-41`）。多包重组由 SOM/EOM/SEQ 驱动，
  首包扣 8 字节双头、续包扣 4 字节（`kfspReadMessage`，`kern_fsp.c:605-688`）。
- 任务级 payload 都很小（PRC ≤ 12 B、COT 为 `NVDM_PAYLOAD_COT`），而信箱声明长度
  可到 1 MiB —— **声明长度与真实协议需求之间有 5 个数量级的攻击面**。

### FSP 侧是否存在"先按长度拷、后校验"—— **UNKNOWN（静态不可判）**

FSP 指令体加密（Q1），本地无任何 plaintext（`fsp_postdecrypt_observability.md`
已闭合：host 无回读口）。能给出的只有参照实现与风险建模：

1. **参照实现是先验后拷的**：同一份公开 MCTP 栈的 host 接收端 `kfspReadMessage`
   在每次 `portMemCopy` 前检查 `payloadBufferSize < total+cur → INSUFFICIENT_RESOURCES`
   （`kern_fsp.c:666-678`）；MNOC 收端 `gpuMnocMboxRecv_GB100` 先断言
   `recvMsgSize ≤ max` 且 `*pMsgSize ≥ recvMsgSize` 再进拷贝循环
   （`kern_gpu_gb100.c:1361-1369`）。**但这两段都是"FSP→接收方"方向，FSP 是发送端**；
   它们不能证明 FSP 自己作为接收端时同型安全。NVIDIA 的 FSP uproc 代码不公开，
   与 host RM 是否共享此 MCTP 源文件：UNKNOWN。
2. **与 GSP bug 同型的假设（INFERENCE）**：MNOC 是 FIFO 信箱，硬件按声明长度交付；
   溢出只能发生在 FSP 软件"按声明长度把 FIFO 内容弹进固定重组/task 缓冲"那一步。
   若该步缺容量校验，则与 0x1016104 完全同型，且长度上限 1 MiB 远大于任何
   合法 task 缓冲。
3. **可观测预测（未执行，仅供 live 轮次）**：经 MNOC 向 FSP 发声明 size 远超
   task 结构的多包消息（SOM=1,EOM=0，SEQ 递增，中途 EOM=1），分别扫
   size ∈ {0x40, 0x400(EMEM RM 通道 1K 参照,`fsp_emem_channels.h:37`), 0x100000}：
   安全实现 ⇒ `MNOC_SEND_ERR`(bit25) 或 FSP 响应 `errorCode≠0`；
   有 bug ⇒ FSP WDT/异常（host 可见 `SEC_FAULT _FSP_WDT/_FSP_UNCORRECTABLE_ERROR`
   Xid 字符串已在 GSP-RM 中确认存在）或信箱挂死（READY 不再置位）。
   **触发字段规格**：长度=`RECV_INFO` bits19:0；SOM/EOM/SEQ=dword0 bits31/30/29:28；
   NVDM type=dword1 byte7；payload 自 byte8，溢出内容从第一个 payload dword 起连续。

### 立即可做的同型审计（不依赖解密）

GSP-RM 自己也跑 MNOC/MCTP 服务端：GSP ELF 中有 `_tdispmgrServiceMnocMctpAsyncMsg_GB100`
与 `RmFspUseMnoc` 字符串（`gsp_inner_19f040_a.elf`，FACT）。GSP 是 RV64 plaintext，
其收包/重组路径可**立即**反汇编审计"先拷后验"——既是 FSP 路径的最佳同型参照
（同一套 NVDM/MCTP 代码风格），又因为我们已控制 GSP 执行，可双向构造畸形报文。

## Q3a. `FSP_GSP_COMM (0x21)`：来源区分机制存在，权限差异不可见

- **FACT**：0x21 同时 alias `SEC2_GSP_COMM`（`nvdm_format.h:58-59`）——它是
  uproc↔uproc 通道类型，与 host 用 type（PRC/COT/CAPS_QUERY）命名空间分开。
- **FACT**：来源区分至少在两层机制上存在：① MNOC 有 4 个端口，CPU-RM 固定用
  **port 2**（`KERNEL_FSP_MBOX_PORT 2`，`kern_fsp_gb100.c:56`），GSP 侧通道由独立
  regkey 位配置（`RmFspUseMnoc` bit0=CPU/bit1=GSP，`nvrm_registry.h:2062-2065`），
  端口层天然可分源；② MCTP SEID 用于把包路由到 FSP 内不同 task
  （`kfspNvdmToSeid_GH100` 注释，`kern_fsp_gh100.c:269-279`）。
- **FACT**：GSP-RM 内嵌完整 kfsp 客户端（GSP ELF 中 `GPU-KFSP`、`RmFspUseMnoc`
  字符串），即 GSP→FSP 的协议栈与 host 同源。
- **UNKNOWN**：FSP 侧是否对"来自 GSP 端口的报文"与"来自 host 端口的报文"施加
  不同权限/校验——FSP 代码不可见，公开树无 FSP 端 dispatch 表。
- **结论**：机制上"拿到 GSP 控制权 ⇒ 可经 0x21 通道以 GSP 身份向 FSP 发任意
  NVDM 报文"是**通的**（客户端代码就在我们已控制的 GSP-RM 里，且 GSP 的 MNOC
  服务端可反汇编后复用其发送序列）；能否因此获得比 host 更高的 FSP 侧权限，
  静态不可证。

## Q3b. `ROMREAD (0x1A)` / `INFOROM (0x17)` 读服务

- **FACT**：两类型常量在册；GH100 时代 INFOROM 被路由到独立 SEID=1（多包，
  `kern_fsp_gh100.c:287-297`），说明 FSP 有专门 task 处理 INFOROM。
- **FACT（negative）**：公开 610 Blackwell 树中 ROMREAD **全树仅常量定义**，
  无 payload、无 sender、无 handler；INFOROM 在 Blackwell 无公开 sender。
- **评估**：INFOROM 数据（EEPROM 对象）含板级/序列号等受保护信息，若 FSP 侧
  task 仍在且对 0x21/host 端口开放，则是**纯读情报通道**；可达性与 payload
  schema 均 **UNKNOWN**。优先级低于 Q2 的长度校验问题。

## Q4. 镜像抽不出 plaintext 的替代路径（按性价比排序）

1. **GSP-RM 内 MNOC/MCTP 服务端反汇编**（`_tdispmgrServiceMnocMctpAsyncMsg_GB100`，
   本地 RV64 ELF + 已有 Ghidra 工程）——同协议族、plaintext、今天就能做，
   直接回答"先拷后验"在同代码风格下是否成立，并给出 GSP→FSP 的发送原语。
2. **VBIOS 内其他明文 Falcon 对象**（同一 NVFW 的其余 descriptor 条目）——
   解密/加载 `FSP_RUN` 的 BootROM 级 loader 逻辑若在其中，可反推 v6 格式与入口。
3. **SEC2 不共用 FSP 代码**：`sec2/` 目录有自己的 `sec2_nvdm_format.h` 与
   COT sender（`kernel_sec2_gb20b.c:1075`），类型 alias 仅共享编号，不能当 FSP 源码替代。
4. Live 轮次（本轮不做）：按 Q2 §3 的可观测预测做尺寸扫描，黑盒判定 FSP 接收侧校验。

---

## 总结

1. FSP 镜像已按 hash-confirmed 边界导出三份（`fsp_image*.bin`），导出脚本可一键复核；
   但 descriptor encrypted bit + 7.999 bit/B 熵确认是**密文**，ISA/基址/入口均不可证，
   只能确认执行核是 PFSP Falcon、descriptor 为 v6 格式。
2. MNOC/NVDM 协议面已完全闭合：长度字段=INFO 寄存器 bits19:0（发送方自声明，
   上限 1 MiB），MCTP/NVDM 双头各 1 dword，payload 自 byte8，SOM/EOM/SEQ 重组语义明确。
3. FSP 接收侧"先按声明长度拷、后校验"是否成立**静态不可判**——唯一证据源（FSP
   plaintext）加密；两个可见参照实现（host 收端）都是先验后拷，但方向相反、不证明 FSP。
4. 攻击面定量：合法 task payload ≤数十字节 vs 可声明 1 MiB，若 FSP 重组缓冲固定且
   缺容量校验，则与 GSP 0x1016104 同型；已给出 size 扫描的可观测预测（ERR 位 / WDT Xid /
   信箱挂死三种结局）。
5. GSP↔FSP 通道（0x21）机制上可用：端口/SEID 分源机制存在，GSP-RM 内嵌同源 kfsp
   客户端，我们已控 GSP ⇒ 可以 GSP 身份向 FSP 发任意报文；FSP 侧权限差异不可见。
6. 下一步最高性价比：反汇编 GSP ELF 的 `_tdispmgrServiceMnocMctpAsyncMsg_GB100`
   审计同型 bug 并提取 GSP→FSP 发送原语；ROMREAD/INFOROM 读通道优先级靠后。

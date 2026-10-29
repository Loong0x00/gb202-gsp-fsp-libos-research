# SEC2（FWSEC 安全引擎）接口可复现访问方案 —— 纯静态分析

- 日期：2026-09-26
- 机器：RTX 5090（`0x2b85`，die = GB202），BDF `0000:01:00.0`（与既有 FSP 工具一致）
- 方法：**只读源码**。本轮没有碰设备、没有跑任何 GPU 实验、没有改任何既有文件；本文件是本轮唯一新增文件。
- 源码版本：`/usr/src/nvidia-610.57.04/`；下文所有 `文件:行号` 均相对 `/usr/src/nvidia-610.57.04/src/`。
- 证据等级约定：
  - ✅**[源]** = 源码/寄存器头文件里的直接证据（可引用行号）
  - ⚠️**[同族]** = 来自同 IP 的兄弟代（ga100/ga102/gh100/gb10b/gb20b）已发布寄存器表，跨到 GB202 只是"同 IP 假设"
  - ❓**[推测]** = 明确标注的推测，不要当结论

---

## 0. 结论摘要（先看这里）

| # | 问题 | 结论 | 等级 |
|---|---|---|---|
| 1 | PSEC EMEM 是不是与 PFSP 同型？ | 是。`EMEMD=EMEMC+4`、`QUEUE→MSGQ` 相差 `0x80`、`AINCW=bit24/AINCR=bit25`、`OFFS 7:2/BLK 15:8`、块=64 dword，全部一致 | ✅[源] |
| 2 | 我们（GB202）这一代用哪份 SEC2 代码？ | **`gb20b` 不是我们的 HAL。** `chipHal` 里 GB202=65、GB20B=70、GB20C=71；ksec2 的 EMEM 收发 HAL 只对 `GB10B\|GB20B\|GB20C` 挂真实实现，**GB202 落到 default 桩**（`NV_ERR_NOT_SUPPORTED`/`NV_FALSE`/`0`） | ✅[源] |
| 3 | 这对我们意味着什么？ | 在这台机器上 **Kernel RM 从不经 EMEM 跟 SEC2 说话**（GB202 还有 FSP，`gpuBootGspRmProxy` 优先走 FSP）。所以 0x840xxx 的 EMEM 行为**没有源码背书**，只能"同 IP 假设 + 只读实测" | ✅[源] + ❓[推测] |
| 4 | 主机→SEC2 有哪些消息？ | 开源 RM 里只有 1 条：**COT（0x14，860 B 载荷）**；另外有 INFOROM→SEID=1、HULK→SEID=0 的**路由表**痕迹（无调用点）；CLOCK_BOOST/CAPS_QUERY/PRC 在源码里都是 **FSP 侧**的 | ✅[源] |
| 5 | 有没有"良性"消息可以先发？ | **没有。** SEC2 侧唯一有发送路径的 NVDM 类型就是启动安全链的 COT。第一步只能"只读" | ✅[源] |
| 6 | 最安全的只读指纹 | ① `PMC 0x5E0 == 0xFF`（FWSEC 启动完成）② `PSEC 0x840320..0x84032C`（FWSEC 错误码，0=无错）③ `MSGQ 0x840C80/84`（head≠tail ⇒ SEC2 活着且给主机发过消息）④ `MAILBOX0 0x840040 != 0xC001CAFE` ⑤ `FUSE 0x824140+4i`（SEC2 ucode 版本，0=该 slot 空） | ✅/⚠️ 混合 |
| 7 | 一个必须先解决的坑 | `QUEUE_TAIL` 在驱动里是**字节**偏移（`paddedSize-4`），既有 FSP 工具写的是 **`len/4-1`（dword）**；两者冲突，必须先定论（§1.7） | ✅[源] |

---

## 1. SEC2 的 EMEM 完整配方

### 1.1 寄存器绝对地址表（BAR0 偏移，通道 0）

"基址"含义：`NV_PSEC` 块基址 = `0x00840000`（⚠️[同族] `common/inc/swref/published/ampere/ga100/dev_sec_pri.h:27`：`#define NV_PSEC 0x843fff:0x840000`；gb20b 自己没发布 `NV_PSEC`，但下面所有偏移都在 0x84xxxx 内，反推一致）。
PSEC 块内偏移全部取自 **gb20b 的寄存器头**：`common/inc/swref/published/blackwell/gb20b/dev_sec_pri.h`（✅[源]）。

| 寄存器 | 通道 0 偏移 | i 的 stride | 位域 | 出处 |
|---|---|---|---|---|
| `NV_PSEC_EMEMC(i)` | `0x00840AC0` | `+8i`（i=0..7） | `OFFS 7:2`（**dword** 偏移）、`BLK 15:8`（块号，1 块=64 dword）、`AINCW 24`、`AINCR 25` | `dev_sec_pri.h:26,28,30,32,36`（gb20b） |
| `NV_PSEC_EMEMD(i)` | `0x00840AC4` | `+8i` | `DATA 31:0` | `dev_sec_pri.h:40,42`（gb20b） |
| `NV_PSEC_QUEUE_HEAD(i)`（主机→SEC2） | `0x00840C00` | `+8i` | `ADDRESS 31:0` | `dev_sec_pri.h:44,46`（gb20b） |
| `NV_PSEC_QUEUE_TAIL(i)`（主机→SEC2） | `0x00840C04` | `+8i` | `ADDRESS 31:0` | `dev_sec_pri.h:48,50`（gb20b） |
| `NV_PSEC_MSGQ_HEAD(i)`（SEC2→主机） | `0x00840C80` | `+8i` | `VAL 31:0` | `dev_sec_pri.h:53,55`（gb20b） |
| `NV_PSEC_MSGQ_TAIL(i)`（SEC2→主机） | `0x00840C84` | `+8i` | `VAL 31:0` | `dev_sec_pri.h:57,59`（gb20b） |
| `NV_PSEC_FALCON_COMMON_SCRATCH_GROUP_2(0..3)` | `0x00840320` | `+4i` | `VAL 31:0` | `dev_sec_pri.h:62,66`（gb20b） |
| `NV_PSEC_FALCON_MAILBOX0 / 1` | `0x00840040 / 0x00840044` | — | `DATA 31:0` | ⚠️[同族] `dev_sec_pri.h:27,30`（**只发布了 gb10b**，gb20b 头里没有）；与 falcon_v4 标准布局一致：`ampere/ga100/dev_falcon_v4.h:44` MAILBOX0 = falconbase+0x40 |
| `NV_PFALCON_FALCON_HWCFG2`（SEC2 falcon 内） | `0x008400F4` | — | 只发布地址 | `blackwell/gb20b/dev_falcon_v4.h:27`（= falcon 基址 + 0xf4） |
| `NV_PSEC_FALCON_ENGINE` | `0x008403C0` | — | 只发布地址 | ⚠️[同族] `ampere/ga100/dev_sec_pri.h:28`（gb20b/gb10b 未发布） |
| `NV_PFALCON_FALCON_CPUCTL`（SEC2 falcon 内） | `0x00840100` | — | `STARTCPU 1`、`HALTED 4` | ⚠️[同族] `ampere/ga100/dev_falcon_v4.h:49-54` |
| `NV_FALCON2_SEC_BASE`（SEC2 的 RISC-V/falcon2 页） | `0x00841000` | — | BROM/PKA 相关 | ⚠️[同族] `ampere/ga102/dev_falcon_second_pri.h:28`；`NV_PFALCON2_FALCON_BROM_CURR_UCODE_ID`=+0x198（同文件:35） |
| `NV_FUSE_ZB_OPT_FPF_SEC2_UCODE1_VERSION`（**fuse 域，不是 PSEC 块**） | `BAR0 + 0x820000 + 0x4140 + 4i` = `0x824140+4i` | — | `DATA 15:0`（值=最高位+1 ⇒ 版本号） | ⚠️[同族] 基址 `blackwell/gb100/hwproject.h:31`（`NV_FUSE0_PRI_BASE 0x820000`）+ 偏移 `blackwell/gb100/dev_fuse_zb.h:37-40`；消费点 `kernel/gpu/sec2/arch/blackwell/kernel_sec2_gb100.c:38-59`（读在 `:51`，版本换算 `:52-56`；该 HAL 对 GB202 是挂上的，见 §1.8） |
| `NV_THERM_I2CS_SCRATCH`（FSP 启动完成，**对照用**） | `0x00AD00BC`，值 `0xFF`=成功 | — | — | `blackwell/gb202/dev_therm.h:27` + `dev_therm_addendum.h:27-30`，消费点 `kernel/gpu/fsp/arch/blackwell/kern_fsp_gb202.c:60-61` ✅[源]（**这条是 GB202 自己发布过的**） |
| `NV_PMC_ZB_SCRATCH_RESET_PLUS_2`（FWSEC 启动完成） | `BAR0 + 0x5E0`（`NV_PMC0_PRI_BASE=0`） | — | 值 `0xFF`=完成 | `blackwell/gb20b/dev_boot_zb.h:26`、`hwproject.h:27`、消费点 `kernel_sec2_gb20b.c:525-527` ✅[源] |

通道容量与通道号（✅[源]）：RM 固定用通道 0，容量 **1024 字节**：
`nvidia/arch/nvalloc/common/inc/sec2/sec2_emem_channels.h:33-37`（`SEC2_EMEM_CHANNEL_RM=0x0`、`SEC2_EMEM_CHANNEL_RM_SIZE=1024`），并被 `kernel_sec2_gb20b.c:126-138`、`kernel_sec2_gb10b.c:321-333` 直接返回。

### 1.2 发送配方（主机 → SEC2）——驱动**实际执行顺序**

⚠️ 关键：**GB20B 的发送函数是 GB10B 的实现体**——`g_kernel_sec2_nvoc.c:806` 把 `ksec2SendPacket` 绑到 `ksec2SendPacket_GB10B`（`GB10B|GB20B|GB20C`），`GetMaxSendPacketSize` 同理（`:794`）。所以"GB20B 的发送顺序"= `kernel_sec2_gb10b.c:677-711`。

| # | 动作 | 写/读 | 具体值 | 出处 |
|---|---|---|---|---|
| 0 | 等 SEC2 收走上一条（超时 `GPU_TIMEOUT_DEFAULT`） | 读 | 轮询直到 `QUEUE_HEAD(0) == QUEUE_TAIL(0)` | `kernel_sec2_gb10b.c:343-357`（注释："SEC2 will set QUEUE_HEAD = TAIL after each packet is received"）、`kernel_sec2.c:613-648`（`ksec2PollForCanSend`） |
| 1 | 配置 EMEMC：offset 0 + 写自增 | 写 | `EMEMC(0) = 0x01000000`（`OFFS=0,BLK=0,AINCW=1,AINCR=0`） | `kernel_sec2_gb10b.c:118-154`（`:151` 是那句 `GPU_REG_WR32(NV_PSEC_EMEMC(0), reg32)`），调用点 `:701` |
| 2 | 连续写数据 dword | 写 | 每个 dword 写 `EMEMD(0)`；余数字节补 0 再写一个 dword | `kernel_sec2_gb10b.c:189-202` |
| 3 | 回读 EMEMC 自检 | 读 | 断言 `EMEMC.OFFS + BLK*64` 恰好推进 `wordsWritten` | `kernel_sec2_gb10b.c:205-210` |
| 4 | 写 TAIL，**再**写 HEAD（敲门铃） | 写 | `QUEUE_TAIL(0) = paddedSize - 4`；`QUEUE_HEAD(0) = 0`。注释："The write to HEAD needs to happen after TAIL because it will interrupt SEC2" | `kernel_sec2_gb10b.c:704-708` + `:72-84` |

即 mmap 伪代码（可直接照抄，**但先读 §1.7/§3，本轮不要执行**）：
```c
/* 基址：EMEMC=0x840ac0 EMEMD=0x840ac4 QHEAD=0x840c00 QTAIL=0x840c04 */
while (rd(QHEAD) != rd(QTAIL)) ;                     /* 0. 可发 */
wr(EMEMC, 0x01000000);                               /* 1. offset0 + AINCW */
for (i = 0; i < ndwords; i++) wr(EMEMD, dw[i]);      /* 2. 数据（不足 4B 补 0） */
wr(QTAIL, bytes_padded - 4);                         /* 3. TAIL=最后一个 dword 的字节偏移 */
wr(QHEAD, 0);                                        /* 4. 敲门铃 */
```

### 1.3 接收配方（SEC2 → 主机，GB20B 专有路径）

到 GB20B 才有 MSGQ（`dev_sec_pri.h:53-60`），GB10B 的 `dev_sec_pri.h` 里**没有 MSGQ**，其 `ksec2IsResponseAvailable` 是返回 `NV_FALSE` 的桩（`g_kernel_sec2_nvoc.c:845` → `g_kernel_sec2_nvoc.h:880-882`）；GB10B 收包靠轮询 `MAILBOX0`（`kernel_sec2_gb10b.c:285-311`、`:617-628`）。

| # | 动作 | 写/读 | 具体值 | 出处 |
|---|---|---|---|---|
| 0 | 是否有回包 | 读 | `MSGQ_HEAD(0) != MSGQ_TAIL(0)`（"SEC2 updates the head after writing data into the channel"） | `kernel_sec2_gb20b.c:148-161`、`:105-116` |
| 1 | 算长度 | 读 | `packetSize = (MSGQ_TAIL - MSGQ_HEAD) + 4`（注释："Tail points to last DWORD in packet"） | `kernel_sec2_gb20b.c:476-482` |
| 2 | 配置 EMEMC：offset 0 + 读自增 | 写 | `EMEMC(0) = 0x02000000`（`AINCR=1`） | `kernel_sec2_gb20b.c:490` + `:410-445` |
| 3 | 连续读数据 dword | 读 | 读 `packetSize/4` 次 `EMEMD(0)` | `kernel_sec2_gb20b.c:499-503` |
| 4 | 回读 EMEMC 自检 | 读 | 断言 `OFFS + BLK*64 == packetSize/4` | `kernel_sec2_gb20b.c:506-514` |
| 5 | 应答（ACK） | 写 | `MSGQ_TAIL(0) = head; MSGQ_HEAD(0) = head`（= 推进到 head，清空） | `kernel_sec2_gb20b.c:511-512` + `:84-95` |

### 1.4 报文封装（MCTP over NVDM）

两个头 dword 的索引定义 ✅[源]：`kernel_sec2.c:44-54`（`HEADER_DWORD_MCTP=0`、`HEADER_DWORD_NVDM=1`、`HEADER_DWORD_MAX=2`）。

- `dword0 = mctpCreateTransportHeader(SOM, EOM, SEID, DEID=0, SEQ=0)`：`kernel_sec2.c:322-327`；构造体 `mctp_format.h:78-94`（`VERSION` 硬编码 0x1；TAG/TO=0）。**单包 ⇒ `0xC0000001`**（SOM=1,EOM=1,SEID=0,SEQ=0,VERSION=1）。
- `dword1 = mctpCreateNvdmHeader(nvdmType)`：`kernel_sec2.c:328`；构造体 `mctp_format.h:108-118`（`TYPE=0x7e, IC=0, VENDOR=0x10de`）⇒ **`0xTT10DE7E`**（TT=NVDM 类型；COT ⇒ `0x1410DE7E`）。
- 校验（收方向）：类型必须 `0x7e`、vendor 必须 `0x10de`：`kernel_sec2_gb20b.c:271-309`。
- 载荷起点：**发** = 偏移 8（`kernel_sec2.c:311-331`）；**收** = 偏移 7（`sizeof(MCTP_HEADER)==7`，即 dword1 的最高字节 = NVDM 类型字节，故收侧"载荷"第 0 字节就是 NVDM 类型）：`kernel_sec2.c:445-455`、`:479-481` + `nvidia/inc/kernel/gpu/fsp/kern_fsp_cot_payload.h:27-33`（`MCTP_HEADER{ NvU32 constBlob; NvU8 msgType; NvU16 vendorId; }`，本轮用 gcc 复核 `sizeof==7`）。
- 多包：首包带 NVDM 头，后续包只带 MCTP 头（`kernel_sec2.c:338-368`，后续包 `headerSize=4`、`SEQ=(++seq)%4`）；SEID 决定路由到 SEC2 侧哪个任务：`ksec2NvdmToSeid_GB20B`（`kernel_sec2_gb20b.c:176-198`：`INFOROM→1`，其它含 `HULK→0`）。
- 单包容量：`1024 - 8 = 1016 B` 载荷（`kernel_sec2.c:311-314`）。COT 载荷 860 B ⇒ **单包**。

### 1.5 完整报文样例（COT，仅用于说明格式，**不要发**）

```
offset 0x00  dword0 = 0xC0000001           (MCTP: ver1 SEID0 DEID0 SEQ0 EOM1 SOM1)
offset 0x04  dword1 = 0x1410DE7E           (NVDM: type 0x7e, vendor 0x10de, NVDM_TYPE_COT=0x14)
offset 0x08  NVDM_PAYLOAD_COT (860 B, little-endian, #pragma pack(1))
```
`NVDM_PAYLOAD_COT`（860 B，本轮 gcc 复核 =860）：`version:u16`(=2，`g_kernel_sec2_nvoc.c:497-504` GB20B 分支；GB202 走 default = 0，`:506-510`)、`size:u16`(=860)、`gspFmcSysmemOffset:u64`、`frtsSysmemOffset:u64`、`frtsSysmemSize:u32`、`frtsVidmemOffset:u64`（"offset from the end of FB"）、`frtsVidmemSize:u32`、`hash384[12]:u32`(48 B = SHA-384)、`publicKey[96]:u32`(384 B)、`signature[96]:u32`(384 B)、`gspBootArgsSysmemOffset:u64` —— 定义在 `nvidia/inc/kernel/gpu/fsp/kern_fsp_cot_payload.h:36-55`；打包点 `kernel_sec2_gb20b.c:1018-1019, 782-799`；签名/公钥大小断言 =384：`kernel_sec2_gb20b.c:787-795` + `g_kernel_sec2_nvoc.c:491-495`。整包 = 8 + 860 = **868 B**。

### 1.6 发/收方向的"谁更新谁"

| 寄存器对 | 方向 | 谁写 | 驱动怎么用 | 出处 |
|---|---|---|---|---|
| `QUEUE_HEAD/TAIL(0)` | 主机→SEC2 | 主机写 TAIL 再写 HEAD（HEAD=敲门铃）；**SEC2 收到后把 HEAD 设成 TAIL** | 可发判定 `HEAD==TAIL` | `kernel_sec2_gb10b.c:81-83, 355-356` |
| `MSGQ_HEAD/TAIL(0)` | SEC2→主机 | **SEC2 写数据后更新 HEAD**；主机读完把 TAIL 与 HEAD 拉平 | 有包判定 `HEAD!=TAIL` | `kernel_sec2_gb20b.c:159-160, 512` |
| `EMEMC/EMEMD` | 数据窗口 | 主机写 EMEMC 选偏移+自增方向，然后连续访问 EMEMD | 自检偏移推进量 | 见 §1.2/§1.3 |

### 1.7 ⚠️ 必须先把"单位"钉死：`QUEUE_TAIL` 是字节还是 dword？

- 驱动（三条独立代码路径）都写成**字节偏移**（`paddedSize - sizeof(NvU32)`）：
  - `kernel_sec2_gb10b.c:704-708`
  - `kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c:648-651`
  - `common/nvswitch/kernel/fsprpc_nvswitch.c:326-343`（注释："Pad to align size to 4-bytes boundary since EMEMC increments by DWORDS"）
  且**收方向**同样按字节解释（`(TAIL-HEAD)+4`，并断言 `${EMEMC.OFFS} == packetSize/4`）：`kernel_sec2_gb20b.c:479, 514`、`kern_fsp_gh100.c` 同构。若 TAIL 真是 dword 计数，L10 交换机的 FSP RPC 与 GB10B/GB20B 的 COT 回读都会立刻算错 → 强证据支持**字节**。
- 而我们**既有的、自称跑通的** FSP 工具写的是 dword：`/home/user/fsp_probe/fsp_emem_mod.c:76`（`iowrite32((len + 3u)/4u - 1u, bar + QTAIL)`）、`/home/user/fsp_probe/emem_cli.c:46`（`wr(B_QTAIL+8*ch,(uint32_t)(nd-1))`），且读侧用 `dw = (tail-head)+1`（`fsp_emem_mod.c:34-36`）——**与 §1.7 第一条的字节语义差 4 倍**。
- 只读定论办法（不用发任何东西）：复核既有 FSP 实验里打印过的 `MSGQ_HEAD/MSGQ_TAIL` 原始值（`fsp_emem_mod.c:88-100` 有打印），把 `TAIL-HEAD+4` 与"实际回包字节数"对比：若相等 ⇒ 字节；若等于 `4*(TAIL-HEAD+1)` ⇒ dword。**在做任何 SEC2 写入之前请先给出这个结论**，否则第一次发送就可能把长度报错 4 倍（对 COT 这种 860 B 的消息，报错 4 倍会直接越过 1024 B 通道容量）。

### 1.8 与 FSP 的差异对照（可直接照抄/必须改的地方）

| 项 | PFSP（既已验证） | PSEC（本方案） |
|---|---|---|
| 块窗口基址 | `0x008F0000`（PFSP 所属 ZB 设备窗口；由 `MNOC RX FIFO`=0x8f1e00、`SCRATCH_GROUP_2`=0x8f0320 反推，✅`blackwell/gb202/dev_fsp_pri.h:27`、`gb100/dev_fsp_pri.h:37`；**但 EMEM 在该窗口内偏移 +0x2AC0**） | `0x00840000` ⚠️[同族]（EMEM 在窗口内偏移 **+0x0AC0** —— 两者差 0x2000，这是 GB202 上最需要实测确认的一点） |
| EMEMC/EMEMD | `0x8F2AC0 / 0x8F2AC4`（`hopper/gh100/dev_fsp_pri.h:26,40`，与你实测一致） | `0x840AC0 / 0x840AC4`（`gb20b/dev_sec_pri.h:26,40`） |
| QUEUE | `0x8F2C00/04`（`:53,57`） | `0x840C00/04` |
| MSGQ | `0x8F2C80/84`（`:44,48`） | `0x840C80/84` |
| EMEMC 位域 | 与 PSEC **完全相同**（gh100 头 `:28-39` vs gb20b 头 `:28-39`） | 同 |
| 寄存器对间距 | `EMEMC→QUEUE = 0x140`、`QUEUE→MSGQ = 0x80`、`EMEMD = EMEMC+4` | **完全一致**（`EMEMC→QUEUE = 0x140`、`QUEUE→MSGQ = 0x80`） |
| 各代 HAL | GB202 用 `kfspSendPacket_GB100`→转 GH100 的 EMEM 实现（`g_kern_fsp_nvoc.c:353-355`、`kern_fsp_gb100.c:311-330`） ⇒ **FSP 的 EMEM 在 GB202 上是被驱动启用的** | GB202 走 default 桩（`g_kernel_sec2_nvoc.c:806,811,829,834,840,845,794,799,782,787`） ⇒ **SEC2 的 EMEM 在 GB202 上未被驱动使用** |

**⇒ 结论（重要）**：FSP 那套配方"能在本机跑通"，是因为 FSP HAL 真的挂在 GB202 上；而 SEC2 EMEM 的**所有**发送/读回/ACK 代码在 GB202 上都是死代码。所以本报告给出的 PSEC 配方是"同 IP 推断 + 寄存器表"，**不是**"本机已在跑的路径"。这也解释了为什么 0x8F2xxx 有实测数据而 0x840xxx 目前没有。

---

## 2. 主机 ↔ SEC2 的消息清单

### 2.1 NVDM 类型总表（`nvdm_format.h:43-61` ✅[源]）

| 类型 | 值 | 开源 RM 里的方向 | 有无回包 | 出处 |
|---|---|---|---|---|
| `NVDM_TYPE_COT` | `0x14` | **主机→SEC2（唯一有调用点的 SEC2 消息）** | **有**（回 `0x15`，读回链路 `ksec2SendAndReadMessage`） | `kernel_sec2_gb20b.c:1074-1075`、`kernel_sec2_gb10b.c:600-601`；回读 `kernel_sec2.c:504-531`→`:396-486` |
| `NVDM_TYPE_SEC2_RESPONSE`（=`NVDM_TYPE_FSP_RESPONSE`） | `0x15` | **SEC2→主机**（收） | — | `kernel_sec2_gb20b.c:337-339`、`nvdm_format.h:48-49` |
| `NVDM_TYPE_SMBPBI` | `0x18` | **SEC2→主机**（收；与 `0x15` 同一解析器） | — | `kernel_sec2_gb20b.c:338-339`；⚠️[推测] 语义是"带外 BMC/SMBus 请求的转发/回执"，本树无发送点 |
| `NVDM_TYPE_INFOROM` | `0x17` | 主机→SEC2（**只有 SEID 路由痕迹，无调用点**） | ❓[推测] 有（INFOROM 有独立任务 ⇒ SEID=1） | `kernel_sec2_gb20b.c:186-190` |
| `NVDM_TYPE_HULK` | `0x11` | 主机→SEC2（同上，SEID=0） | ❓[推测] | `kernel_sec2_gb20b.c:191-194` |
| `NVDM_TYPE_CLOCK_BOOST` | `0x20` | **FSP**（不是 SEC2）：`kern_fsp_gb100.c:253-266` | 有 | 同左 |
| `NVDM_TYPE_CAPS_QUERY` | `0x16` | **FSP**：`kern_fsp_gb100.c:171-194`（查 CLOCK_BOOST 能力） | 有 | 同左 |
| `NVDM_TYPE_PRC` | `0x13` | **FSP**（`kern_gpu_gh100.c:586-594` 读 knobs）、**nvswitch FSP** | 有 | 同左 |
| `NVDM_TYPE_COT` 的 FSP 版 | `0x14` | FSP 也有自己的 COT：`kern_fsp_gh100.c` | 有 | — |
| `NVDM_TYPE_RESET` / `FIRMWARE_UPDATE` / `ROMREAD` / `UEFI_RM` / `UEFI_XTL_DEBUG_INTR` / `TNVL` / `FSP_GSP_COMM`(=`SEC2_GSP_COMM`) / `RM_RPC` | `0x4/0x12/0x1A/0x1C/0x1D/0x1F/0x21/0x25` | 本树内**没有** SEC2 发送点（`0x1F` 只在 nvswitch FSP RPC；`0x25` 是 GSP-RM RPC） | 未知 | `nvdm_format.h:43-61`、`gsp/message_queue_cpu.c` |

### 2.2 回包结构与错误码

- 收包解析（`0x15`/`0x18` 共用）：`NVDM_PAYLOAD_COMMAND_RESPONSE { u32 taskId; u32 commandNvdmType; u32 errorCode; }`（12 B，`#pragma pack(1)`）：`nvidia/arch/nvalloc/common/inc/sec2/nvdm_payload_cmd_response.h:35-42`；解析点 `kernel_sec2_gb20b.c:362-397`（载荷第 1 字节起是 NVDM 类型之后的体）。
- 错误码 → NV_STATUS：`ksec2ErrorCode2NvStatusMap_GB20B`（`kernel_sec2_gb20b.c:1143-1166`），用的是 **FSP 错误码命名空间**：`FSP_OK=0x00`、`FSP_ERR_IFS_ERR_INVALID_STATE=0x9E`、`FSP_ERR_IFR_FILE_NOT_FOUND=0x9F`、`FSP_ERR_IFS_ERR_NOT_SUPPORTED=0xA0`、`FSP_ERR_IFS_ERR_INVALID_DATA=0xA1`、`FSP_ERR_PRC_ERROR_INVALID_KNOB_ID=0x1E3`（`nvidia/inc/kernel/gpu/fsp/kern_fsp_retval.h:24-29`）。
- PRC 请求/响应体（FSP 侧，SEC2 若实现同一 task 可复用；**不要在不确认的情况下发**）：
  - 请求 `NVDM_PAYLOAD_PRC_OBJECT_READ { u8 prcObjType; u8 numBytes; u16 knobId; }`（4 B）：`kernel/gpu/arch/hopper/kern_gpu_gh100.c:542-549`；示例 knob：`READ_OBJECT=0x0C`、`NUM_BYTES=0x02`、`KNOB_ID=0x2D`（`:563-565`），调用 `:586-594` 传 `nvdmType = NVDM_TYPE_PRC`。
  - 响应 `NVDM_PAYLOAD_PRC_OBJECT_RESPONSE { u8 messageType; u32 taskId; u32 commandNvdmType; u32 errorCode; u16 knobValue; u16 misc; }`（17 B，gcc 复核）：`:551-561`。

### 2.3 判定"谁回包"的依据

- 会回包：任何走 `ksec2SendAndReadMessage`（`kernel_sec2.c:504-531`）的消息 ⇒ 发送后 `ksec2PollForResponse` + `_ksec2ReadMessage`，**期待** `0x15`/`0x18`。SEC2 侧当前唯一已知会回的就是 COT。
- 不回包（单向）：若只用 `ksec2SendMessage`（`kernel_sec2.c:284-375`），就是"发了不等回"。GB10B 的 COT 是这种（`kernel_sec2_gb10b.c:600-601` 只 Send），GB20B 的 COT 是"发+读"（`kernel_sec2_gb20b.c:1074-1075`）⇒ **同一类型在不同代上回包行为不同**。
- SEC2 固件侧到底认识哪些类型：源码不可见（固件闭源）。INFOROM/HULK 的存在只能从 SEID 路由表推断 ❓[推测]。

---

## 3. ★ 最安全的第一步：只读指纹（零写入、零风险）

### 3.1 只读清单（全部是 `ioread`/`mmap` 读，不写任何寄存器）

| 偏移 | 名称 | 读什么 | 解释规则 | 出处 |
|---|---|---|---|---|
| `0x000005E0` | `NV_PMC_ZB_SCRATCH_RESET_PLUS_2` | FWSEC boot 完成 | `0xFF` ⇒ **FWSEC/SEC2 启动已完成**；`0` ⇒ 未完成/未运行 | `kernel_sec2_gb20b.c:525-527`（注释同句）、`dev_boot_zb.h:26` |
| `0x00840040 / 0x00840044` | `NV_PSEC_FALCON_MAILBOX0/1` ⚠️[同族偏移] | SEC2 命令处理状态 | `MAILBOX0 == 0xC001CAFE` ⇒ **SEC2 正在处理一条命令**；否则空闲 | `kernel_sec2_gb10b.c:292-297`；超时打印点 `:617-628` |
| `0x00840320..0x0084032C` | `NV_PSEC_FALCON_COMMON_SCRATCH_GROUP_2(0..3)` | FWSEC 错误现场 | 驱动把它们打印成 `FWSEC Error Code / Offending PC / Offending Address / Additional info` ⇒ 全 0 = 无错；非 0 = 报过错（保留现场） | `kernel_sec2_gb20b.c:862-872`、`dev_sec_pri.h:62-67` |
| `0x008400F4` | `NV_PFALCON_FALCON_HWCFG2` | SEC2 falcon 块是否真实存在 | 驱动对 GSP falcon 的活体判据：`HWCFG2 != 0` 且 `(HWCFG2 & 0xFFFFFF00) != 0xBADF4100`（后者是 priv-err 毒值）⇒ 可作 PSEC 的同型判据 | `kernel_sec2_gb10b.c:264-283`（对 GSP）；地址 `gb20b/dev_falcon_v4.h:27` |
| `0x008400C0` | ❓[推测] `NV_PSEC_FALCON_ENGINE`（若与 ampere 同址） | 只是备选，不建议作为主判据 | ⚠️ 地址来自 `ampere/ga100/dev_sec_pri.h:28` | — |
| `0x00840100` | `NV_PFALCON_FALCON_CPUCTL` ⚠️[同族] | SEC2 核是否在跑 | `HALTED(bit4)==0` ⇒ 运行中；`==1` ⇒ 已停 | `ampere/ga100/dev_falcon_v4.h:49-54` |
| `0x00840C80 / 0x00840C84` | `NV_PSEC_MSGQ_HEAD/TAIL(0)` | SEC2→主机队列 | `HEAD != TAIL` ⇒ **SEC2 活着、且曾主动给主机发过消息**（本机驱动不会去 ACK，因为 GB202 是死代码 ⇒ 这会是"SEC2 活着"的最强动态证据）；`HEAD == TAIL` ⇒ 空/静默 | `kernel_sec2_gb20b.c:148-161` |
| `0x00840C00 / 0x00840C04` | `NV_PSEC_QUEUE_HEAD/TAIL(0)` | 主机→SEC2 队列 | 两者相等（通常都是 0）⇒ 无未收命令；**不等** ⇒ 有人（不是本机驱动）往里投过命令或投了一半 | `kernel_sec2_gb10b.c:343-357` |
| `0x00840AC0..+8i` | `NV_PSEC_EMEMC(0..7)` | 主机侧 EMEM 游标 | 全 0 ⇒ 无待完成传输（`AINCW/AINCR` 都关）；bit24/25 非 0 ⇒ 上一次传输被中断 | `gb20b/dev_sec_pri.h:26-39` |
| `0x824140 + 4i`（i=0..15） | `NV_FUSE_ZB_OPT_FPF_SEC2_UCODE1_VERSION` | **SEC2 ucode 是否存在及其版本** | 0 ⇒ 该 slot 无镜像；非 0 ⇒ 版本号（值=最高位+1，`kernel_sec2_gb100.c:52-56`） | 基址 `gb100/hwproject.h:31`、偏移 `gb100/dev_fuse_zb.h:37-40`、读法 `kernel_sec2_gb100.c:38-59` |
| `0xAD00BC` | `NV_THERM_I2CS_SCRATCH`（FSP，**对照**） | FSP 启动完成 | `0xFF` ⇒ FSP boot 完成（本机应该已是这条路，可用来"校准"读取方法学） | `gb202/dev_therm.h:27`、`gb202/dev_therm_addendum.h:27-30`、`kern_fsp_gb202.c:60-61` |

> 注：**不要为"探活"去读 `0x00840AC4`（EMEMD）**：EMEMD 是数据窗口，若 `EMEMC` 的 AINC 位仍被上一次传输置着，读它会**推进游标**（`kernel_sec2_gb10b.c:189-202` 的写侧同理）。先读 `EMEMC`，确认 bit24/25 都是 0 再考虑读 EMEMD。

### 3.2 判定流程（建议照这个顺序做，全部只读）

```
Step 0 存在性：读 0x8400F4(HWCFG2) / 0x840320..2C / 0x840AC0 / 0x840C00,04 / 0x840C80,84
        - 若全 0xFFFFFFFF 或出现 0xBADFxxxx 毒值 ⇒ 该偏移在本机 PSEC 上不存在/不可访问 ⇒ 停。
          （候选窗口应同时试 0x840AC0 与 0x842AC0 两个版本：位表里 PSEC 的 EMEM 在 +0xAC0，
           而 PFSP 的 EMEM 在 +0x2AC0，两者相对基址差 0x2000；GB202 未发布 PSEC 位表 ⇒ 必须实测）
        - HWCFG2 != 0 且非毒值 ⇒ falcon 子块存在
Step 1 SEC2/FWSEC 是否跑起来：
        0x5E0 == 0xFF ?  ⇒ FWSEC boot 完成（驱动自己的等待条件）
        0x840100 bit4 == 0 ? ⇒ SEC2 核在跑 [同族偏移]
        0x840320[0] == 0 ? ⇒ FWSEC 未记录错误
Step 2 SEC2 是否"在通信"：
        0x840C80 != 0x840C84 ⇒ 主机侧消息队列非空（= SEC2 主动发过东西；本机驱动不会清）
        0x840040 == 0xC001CAFE ⇒ 正在处理命令中
        0x840C00 == 0x840C04 ⇒ 主机命令队列空（正常）
Step 3 底线证据：0x824140+4i 非 0 ⇒ 本机 fuse 里确实有 SEC2 ucode（零风险、可长期追踪）
```

最省事的现成工具（只读模式）：`/home/user/fsp_probe/emem_cli.c` 已经把基址做成环境变量，**`status` 模式只读**，可直接指向 PSEC：
```bash
sudo env BDF=0000:01:00.0 \
    EMEMC=0x840ac0 EMEMD=0x840ac4 QHEAD=0x840c00 QTAIL=0x840c04 MHEAD=0x840c80 MTAIL=0x840c84 \
    /home/user/fsp_probe/emem_cli status 0
```
（`emem_cli.c:34-37` 只做 `ioread`；⚠️ 注意它的 `send`/`recv` 模式**会写** EMEMC/QTAIL/QHEAD，本轮不要用。）

### 3.3 如果"必须发一条消息才算接触"，哪一条最良性？

**诚实回答：开源 RM 里不存在"良性"的 SEC2 消息。** 主机→SEC2 在源码里有实际发送路径的类型只有 COT（`kernel_sec2_gb20b.c:1074`、`kernel_sec2_gb10b.c:600`），而 COT 就是**把 GSP-FMC 镜像交给 FWSEC 验签并启动**的那条链（见 §4.1），发错等于拿启动链去赌。

按"风险从低到高"排序的建议（后两条都是 ❓[推测]，且**不建议**在本机做）：

1. **只读接触（推荐）**：§3.1/§3.2 全部动作，零写入。
2. **只写数据不敲门铃（不推荐）**：写 `EMEMC=0x01000000` + 写 `EMEMD`，但**不**写 `QUEUE_TAIL/QUEUE_HEAD` ⇒ 按驱动模型 SEC2 不会被中断、不会看到这条消息，通道内容会被下一次传输覆盖（推断依据：SEC2 靠 `QUEUE_HEAD` 写入被中断，`kernel_sec2_gb10b.c:81-83`）。风险点在于"非预期的 EMEMC 自增状态"和"通道残留"是否会被固件误读 —— ❓[推测]，且这是**在写别人的共享 SRAM**，不算零风险。
3. **发一个未知/未实现的 NVDM 类型**（例如 `NVDM_TYPE_PRC 0x13`）：理由是"SEC2 若不认识就会忽略/报错"。但 `0x13` 在 FSP 侧是**真实读写 knob** 的通道（`kern_gpu_gh100.c:586-594`），SEC2 侧是否有同 task 未知 ⇒ 可能读到/写到真实 knob。❓[推测]，不建议。

---

## 4. 风险清单与恢复手段

### 4.1 必须回避的消息（按"链上/持久"排序）

| NVDM 类型 | 值 | 为什么危险 | 证据 |
|---|---|---|---|
| `NVDM_TYPE_COT` | `0x14` | 这是**启动安全链**本身：载荷里给出 GSP-FMC 镜像的 sysmem 地址 + SHA-384 + 签名 + 公钥 + bootArgs 地址，由 FWSEC 验签后启动 GSP。伪造/错填 ⇒ 验签失败（RM 起不来、设备被 `gpuMarkDeviceForReset`），或最坏情况下把控制权交给非预期镜像。**这是唯一一条我们有发送代码的消息，也是唯一不能随便发的消息** | 打包 `kernel_sec2_gb20b.c:707-808, 982-1049`、发送 `:1063-1114`；失败路径 `:1107-1113`（`ksec2DumpDebugState` + "RM cannot boot"）；GB10B 侧还追加等 `MAILBOX0` 的 CMD 处理完成 `:617-628` |
| `NVDM_TYPE_FIRMWARE_UPDATE` | `0x12` | 名字即固件更新（**持久化**写 flash 类操作） | `nvdm_format.h:45`（本树无 SEC2 发送点） |
| `NVDM_TYPE_RESET` | `0x4` | 复位管理分区（可能让 GPU 进入非预期状态） | `nvdm_format.h:43` |
| `NVDM_TYPE_INFOROM` | `0x17` | InfoROM 读写（**持久化**设备数据；SEID=1 表示 SEC2 侧有专门任务） | 路由 `kernel_sec2_gb20b.c:186-190` |
| `NVDM_TYPE_HULK` | `0x11` | HULK = 固件/特性授权（license）通道；本仓库既有报告显示它牵涉 `USER_FW_MOD`/licreq/InfoROM license 流程 ⇒ 可能写授权状态 | 路由 `kernel_sec2_gb20b.c:191-194`；背景见 `enthusiast_hulk_license_route_20260723.md` |
| `NVDM_TYPE_SMBPBI` | `0x18` | 带外（BMC/SMBus）管理通道；可能与 PMBus/功率上限设置相关 | `kernel_sec2_gb20b.c:338-339` ❓[推测] |
| `NVDM_TYPE_SEC2_GSP_COMM` | `0x21` | GSP↔SEC2 专用通道（本树无发送点）⇒ 别插队 | `nvdm_format.h:58-59` |
| `0x1A / 0x1C / 0x1D / 0x1F / 0x25` | ROMREAD / UEFI_RM / UEFI_XTL_DEBUG_INTR / TNVL / RM_RPC | 与本任务无关的通道，误用可能扰乱 GSP/UEFI 侧状态 | `nvdm_format.h:53-61` |

补充（"看起来无害但要小心"）：`NV_PSEC_QUEUE_HEAD` 的写入会被 SEC2 当成**中断/敲门铃**（`kernel_sec2_gb10b.c:81-83`），所以"随便写个 head 看看"= 发一条长度由 TAIL 决定的半成品消息。

### 4.2 出问题后的恢复手段（按从小到大）

| 手段 | 依据 | 备注 |
|---|---|---|
| 重新加载/复位 RM（`rmmod nvidia`/模块重载、`nvidia-smi --gpu-reset`、PCIe FLR、系统重启） | 驱动的 devinit 失败路径会 `gpuMarkDeviceForReset`（例：`kern_fsp_gb100.c:123`、`kern_fsp_gb202.c:97`）；SEC2 侧失败只是把错误返回给 `gpuBootGspRmProxy`（`kernel_sec2_gb20b.c:1107-1113` → `gpu.c:7884`） | ✅[源] 前半个（devinit 失败会 mark reset）；❓[推测] SEC2 失败是否走到那条 mark 由调用者决定，源码未在 sec2 侧显式写 |
| **完全断电**（关 PSU 开关/拔 AC，等数秒） | 推理：FWSEC/SEC2 的固件是每次 chip reset 由 BootFSM 重新装载的（`kern_fsp_gb202.c:56-58`："In GB202, Bootfsm triggers FSP execution out of chip reset"；`kernel_sec2_gb20b.c:540-553` 同理等 boot 完成）⇒ COT 类"一次性引导参数"不落盘，冷启动即回到干净状态 | ❓[推测]（驱动代码没有明写"断电即恢复"） |
| 让 RM 自己启动 GSP（绕过 FWSEC 的 COT） | registry `RMDevinitBySecureBoot=0`（`nvrm_registry.h:3178-3180`）⇒ `PDB_PROP_KSEC2_RM_BOOT_GSP=NV_TRUE`（`kernel_sec2.c:102-107`）⇒ `gpuBootGspRmProxy` 走别的路（`gpu.c:7874-7888`）。另：`RmDisableCotCmd`（`nvrm_registry.h:2053-2060`，bit `GSPFMC 5:4`）在**硅片/真机**上会被拒绝："Chain-of-trust (GSP-FMC) cannot be disabled on silicon"（`kernel_sec2_gb20b.c:951-957`） | ✅[源]；但注意 `RMDevinitBySecureBoot` 只在 __构造期__ 读且与 `IS_EMULATION/IS_FMODEL/IS_RTLSIM` 判定耦合（`kernel_sec2.c:102-107`） |
| 真刷坏了（极端情形）⇒ nvflash 重刷 VBIOS/InfoROM | 本仓库既有工作流（`enthusiast_hulk_license_route_20260723.md`、`vbios_fsp_inventory.md`） | 需要可用镜像与（对某些操作）授权 |

**风险分级的一句话**：**只读**（§3.1）不会有任何残留状态；**发 COT** 的危险是"本次 devinit 崩",冷启动可回到干净状态；真正"持久化"的危险是 `FIRMWARE_UPDATE/INFOROM/HULK` 这三类（它们会碰 flash/授权状态），而这三类在本树里**没有 SEC2 调用点**——也就是说，如果真的要用 EMEM 探索，必须先把"绝不发 0x12/0x17/0x11"当铁律。

### 4.3 ❓[推测] 需要注意但源码给不出答案的
- GB202 上 SEC2 是否**存在并响应** 0x840xxx 的 EMEM：驱动不这么用（§0 #3），GSP-RM 固件（570.144）里也没有 EMEM 客户端证据——既有报告 `DS_FWSEC_CALLSITE_20260926.md` §3 定位的是 host 侧 **FWSECLIC/UDE 客户端**（347 条错误码），说明真机路径很可能是 **UDE/其它寄存器组**，而不是 Kernel RM 的 EMEM。**这是本轮最需要实测确认的假设。**
- `NV_PBUS_ZB_SW_SCRATCH(i)`（= `PBUS devicePriBase + 0x400 + 4i`，`gb20b/dev_bus_zb.h:27`）里驱动会读 `FWSEC version(0)/Devinit version(2)/Devinit Boot Status(12)/FRTS Completion(52)/COT Polling Status(54)/Failing Register Addr(15)/Devinit PC(16)/PRI error code(28)`（`kernel_sec2_gb20b.c:850-887`）。**但 `devicePriBase` 是运行时从 device-info 表拿的**（`gpuGetOneDeviceEntry`，表来源在 GSP-RM/vGPU 路径：`gpu_gspclient.c:235-270`、`gpu_vgpu.c:239-270`）⇒ 静态无法定绝对地址。若"0x8F0000 同时是 PBUS/PTOP 的 pri 窗口"这一推测成立，则 `FWSEC version` 就在 `0x8F0400`，值得**只读**试一次。

---

## 5. 复现命令与"不要做"清单

只读（本轮推荐的全部动作）：
```bash
# (1) PSEC 侧只读状态（只读模式，工具已支持基址覆盖）
sudo env BDF=0000:01:00.0 EMEMC=0x840ac0 EMEMD=0x840ac4 \
     QHEAD=0x840c00 QTAIL=0x840c04 MHEAD=0x840c80 MTAIL=0x840c84 \
     /home/user/fsp_probe/emem_cli status 0
# (2) 其它只读偏移（沿用既有 bar0 读工具即可，例如 /home/user/fsp_probe/bar0_read_mod.c / fscan_mod.c 的风格）
#     0x000005E0 (PMC FWSEC 完成)  0x00840040/44 (MAILBOX)  0x008400F4 (HWCFG2)
#     0x00840100 (CPUCTL)          0x00840320..2C (FWSEC 错误码) 0x00840AC0+8i (EMEMC 0..7)
#     0x00840C00/04, 0x00840C80/84 0x824140+4i (i=0..15)  0x00AD00BC (FSP 对照)
```
**不要做**（本轮明确列为禁区）：对 SEC2 写 `QUEUE_HEAD/QUEUE_TAIL/EMEMC/EMEMD`；发 COT；发 `0x12/0x17/0x11/0x4/0x18`；不要用 `emem_cli send|recv`；不要在未定论 §1.7 单位之前做任何发送。

---

## 6. 最后 10 行总结（给人看）

1. **SEC2 的 EMEM 位表我们已经拿到手**：通道 0 的 `EMEMC=0x840AC0`(+8i)、`EMEMD=0x840AC4`、`QUEUE_HEAD/TAIL=0x840C00/04`、`MSGQ_HEAD/TAIL=0x840C80/84`、FWSEC 错误 scratch `0x840320+4i`；位域与 PFSP **逐位相同**，通道容量 1024 B，RM 用通道 0。
2. **发送顺序（驱动实写）**：等 `QUEUE_HEAD==QUEUE_TAIL` → `EMEMC=0x01000000`(offset0+AINCW) → 连写 `EMEMD` → `QUEUE_TAIL=paddedBytes-4` → `QUEUE_HEAD=0`(敲门铃)；**接收**：`MSGQ_HEAD!=MSGQ_TAIL` → 长 `(tail-head)+4` → `EMEMC=0x02000000`(AINCR) → 连读 `EMEMD` → ACK 把 `MSGQ_TAIL=MSGQ_HEAD`。
3. **最大的意外**：`gb20b` 不是我们的 HAL。GB202（chipHal 65）的 ksec2 收发/读回 HAL 全是 default 桩，真机 RM **从不**经 EMEM 跟 SEC2 通信（GB202 有 FSP，boot 走 FSP）。因此 0x840xxx 的行为**没有源码背书**，只是"同 IP 假设"。
4. **主机→SEC2 在源码里只有一条消息：COT(0x14)**，860 B 载荷（version=2 + 三个内存偏移 + hash384/publicKey/signature 各 48/384/384 B + bootArgs 偏移），整包 868 B 单包发出并期待 `0x15` 回包；另有 INFOROM→SEID1、HULK→SEID0 的路由痕迹（无调用点）。CLOCK_BOOST/CAPS_QUERY/PRC 都是 FSP 侧的。
5. **第一步就该只读**：`PMC 0x5E0==0xFF`（FWSEC 启动完成，驱动自己的判据）、`0x840320` 全 0（无 FWSEC 错误）、`MSGQ head!=tail`（SEC2 主动发过消息 = 活着）、`MAILBOX0 != 0xC001CAFE`（不在处理命令）、`0x840100 bit4==0`（核在跑）、`0x824140+4i` 非 0（fuse 里有 SEC2 ucode）；顺手读 `0xAD00BC`（GB202 自己发布过的 FSP 启动完成 = 校准读取方法学）。
6. **单位必须先钉死**：驱动三条独立路径都表明 `QUEUE_*_TAIL` 是**字节**偏移（`paddedSize-4`），而既有 FSP 工具写的是 `len/4-1`（dword）；先用既有 FSP 实验日志里的 `MSGQ_HEAD/TAIL` 数值定论，再考虑任何 SEC2 写入（否则 860 B 的消息会按 4 倍长度报错，直接越过 1024 B 通道）。
7. **没有"良性消息"可用**：唯一有发送代码的类型就是启动安全链的 COT，所以"必须发点什么"这个前提在源码层面不成立；退而求其次的"只写数据不敲门铃"也只是把风险从"启动链"降到"共享 SRAM 残留"，不算零风险。
8. **禁区**（会碰持久状态/启动链）：`COT 0x14`、`FIRMWARE_UPDATE 0x12`、`INFOROM 0x17`、`HULK 0x11`、`RESET 0x4`、`SMBPBI 0x18`、`SEC2_GSP_COMM 0x21`；`0x1A/0x1C/0x1D/0x1F/0x25` 与本任务无关，也别碰。
9. **恢复手段**（有据的）：RM 失败会自己 `markDeviceForReset` → 复位/重载/重启即可重跑 devinit；`RMDevinitBySecureBoot=0` 可让 RM 绕过 FWSEC 的 COT 自己启动 GSP（但 `RmDisableCotCmd` 在真机上被明确拒绝）；"COT 不落盘 ⇒ 冷断电回到干净态"是推测但合理（BootFSM 每次 reset 重跑 FSP/SEC2 引导）。
10. **下一步建议顺序**：先跑 §5 的只读清单并记录（含 `0x840AC0` 与 `0x842AC0` 两个候选窗口的对比）→ 用既有 FSP 日志钉死 §1.7 的单位 → 只有当 ①`0x5E0==0xFF` ②`0x840320` 全 0 ③`HWCFG2` 非毒值 都成立、且明确接受"最坏情况 = 本次 devinit 失败、需要冷启动"时，才考虑在**通道 0** 上做第一次 SEC2 写入（且第一发绝不发 COT）。

---

### 附：已知空白（源码里查不到，明确不编造）

| 空白 | 现状 |
|---|---|
| GB202 的 PSEC 寄存器位表 | swref 里**没有** `blackwell/gb202/dev_sec_pri.h`（只有 gb10b/gb20b），本报告用 gb20b 表 + 同 IP 假设 |
| GB202 上 SEC2 是否响应 EMEM | 驱动不使用（§1.8）⇒ 未知；GSP-RM 侧证据指向 UDE/FWSECLIC（既有报告 §3） |
| `NV_PSEC_FALCON_MAILBOX0/1` 在 GB20B/GB202 上是否同址 | gb20b 头未发布；gb10b 头发布为 0x840040/44，且与 falcon_v4 标准（base+0x40）一致 ⇒ ⚠️[同族] |
| `EMEM` 区域在 PSEC 内的相对深度（+0xAC0 vs PFSP 的 +0x2AC0） | 两个头文件各自发布；跨到 GB202 无法判定 ⇒ 建议同时只读探测 `0x840AC0` 与 `0x842AC0` |
| SEC2 固件认识的 NVDM 类型全集/载荷格式 | 固件闭源，只能看到 host 侧路由表（INFOROM/HULK）与收包解析器（0x15/0x18） |
| `PBUS devicePriBase`（决定 `SW_SCRATCH` 绝对地址） | 运行期来自 device-info 表（`gpu_gspclient.c:235-270`）⇒ 静态不可定 |
| `QUEUE_TAIL` 单位 | 驱动=字节（3 条路径），既有 FSP 工具=dword ⇒ 需用既有实测数据定论（§1.7） |

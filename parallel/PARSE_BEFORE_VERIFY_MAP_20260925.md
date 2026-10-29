# GB202 parse-before-verify 地图（静态、只读）

日期：2026-09-25（Asia/Singapore）
范围：**纯本地只读静态审计**。没有 GPU 写入 / 刷写 / reset / rebind / insmod，
没有打开 `/dev/nvidia*`、PCI/BAR、MMIO 寄存器窗口、debugfs，没有联网，
没有执行 `nvflash` / updater / MODS。
本文件不含、也不提供任何出口管制相关（算力/授权/熔丝绕过）内容，不含任何刷写、
重签、回滚或移植固件的步骤。所有"候选缺陷"都是**防御性解析/信任边界观察**，
用于说明验签实现自身的鲁棒性与信任落点。

目标：把 GB202 上"host 递交的字节里，**哪些字段在验签之前就被消费**（分配/
拷贝/索引/取地址/选槽）"逐字段画出来。这正是 170HX 类漏洞的形状
（host 控长度 + 受信域无界拷贝），只是 GB202 上要分三条通道分别定位。

材料边界说明（重要）：GB202 真正的 **设备侧 verifier**（FSP runtime、BootROM/ACR
Booter、FMC monitor）**不在本机任何文件里**（见 §6 负结果 N7/N8）。因此本文把每条
通道拆成三段：
`host 可见消费方（有代码，可判定）` → `交接面（有结构体/寄存器，可判定）` →
`设备侧消费者（无代码，只能给"结构性推断 + 错误码存在性"）`。

---

## 1. 结论摘要

**核心判定：三条通道的"验签前消费"性质完全不同，只有一条拿到硬证据。**

| 通道 | "验签前消费"是否成立 | 最硬的一条证据 | 置信度 |
|---|---|---|---|
| (1) FMC 容器 72-B 头 / 0xA00 manifest | **结构性成立，但本地无消费者代码** | host **完全不解析** 72-B 头（全树 0 消费点）；设备侧 FSP/SEC2/FWSEC 是唯一消费者，代码不在本地 | 结构性 STRONG / 具体缺陷 UNKNOWN |
| (1b) 92-B `RM_RISCV_UCODE_DESC`（v6） | **成立，且有本地代码 + 无边界检查** | `kernel_gsp_gh100.c:744/751/758` 把 `monitorCodeOffset/monitorDataOffset/manifestOffset` 直接算成 `FMC 物理地址 + offset` 写进 `NV_PRISCV_RISCV_BCR_DMAADDR_*`（BootROM DMA 源地址）；**三个 offset 与 image size 之间没有任何检查**，且该 92-B desc **没有任何签名/hash 伴随字段** | **STRONG**（host 代码）+ 设备侧后果 UNKNOWN |
| (1c) WPR2 meta（`GspFwWprMeta`） | **成立，且是 GB202 默认（FSP/SEC2）路径** | `_kgspBootGspRm()` 在 bootstrap **之前** 调 `kgspPopulateWprMeta_HAL`（`kernel_gsp.c:4814`），把上面三个未校验 offset 写进 FB 的 WPR2 meta（`kernel_gsp_gh100.c:340-342`）；meta 还带 `verified` 字段（由 Booter 填 `0xa0a0…`）+ 一个**与 signature 复用的 union**（别名候选） | **STRONG**（host 侧顺序） |
| (2) `.fwsignature_<family>` 4 KiB 帧 | **确定性成立（帧内字段无人校验），但两端都没有解析器** | host 只做"抽 section + 拷贝到 256-B 对齐 sysmem"（`_kgspCreateSignatureMemdesc`），**一个字段都不解析**；设备侧解析器不在本地（acr booter_load/unload 里 0 命中帧头常量） | host 侧 STRONG（负结果）/ 设备侧 UNKNOWN |
| (3) 控制面 NVDM/MCTP/PRC/`NV2080_CTRL_*` | **host→device 方向基本 fail-closed；device→host 方向抓到一条真候选** | **`GspMsgQueueReceiveStatus()` 用设备给的 `rpc_message_header_v.length` 算 `nElements` 并开始拷贝，长度合法性检查在循环之后**（`message_queue_cpu.c:698 vs 823-834`），目标缓冲区只有 `queueElementSizeMax`=64 KB，而可读元素上限≈63×4 KB | **HIGH（代码级确定）**，威胁模型需注意方向 |

一句话版本：
**GB202 的"host 控长度 + 受信域拷贝"在 host 侧有两处真东西——(a) 92-B desc 的三个
offset 未校验就被写进 DMA 地址寄存器/WPR2 meta（但 desc 不是 host 递交的字节，而是
随驱动编译/可被 MODS 覆盖）；(b) GSP-RM 消息队列设备→host 接收方向把"长度"用在
"长度检查"之前。真正符合 170HX 字面形状（host 递交的 FMC 容器字节 → 受信域用其中的
长度做拷贝）的那条链，其决定性代码在 FSP/FWSEC 内部，本地不可见。**

---

## 2. 方法与复算基线（全部只读）

| 类别 | 路径 | 关键事实 |
|---|---|---|
| host 源码（本机工作树） | `/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src` | 本文全部行号引用出自此处；与 610.57.04 在引用的 11 个文件上**逐字节相同**（§9.1） |
| host 源码（第二份，交叉核对） | `/usr/src/nvidia-610.57.04/src` | 与上者在本文引用的所有点上一致（§9.1 已验证差异摘要） |
| 设备侧 RV64 GSP-RM（610.57.04） | `power_governor_reverse/gsp61057_rx_full.bin`（15,298,560 B，`50614073f1ca73d4…`） | PH0 code 0xe9b000 + PH1 data 0x1d5000 |
| 设备侧 RV64 GSP-RM（570.144） | `ghidra_static/gsp_inner_570144_main.elf`（15,085,568 B，`6c36425881780a14…`） | PH0 0xd73000 + PH1 0xf0000 |
| 设备侧 RV64 GSP-RM（debug/大） | `ghidra_static/gsp_inner_19f040_a.elf`（82,577,496 B，`bda917c955476443…`） | **内含 3 个拼接 RV64 ELF**：@0x0（0xe97000+0x1d5000）、@0x106d000（0xa2000+0xf000）、@0x111f000（0x5000+0x9000）；`NV_FWSECLIC_*` 名池 @0xe2bdf2..（本次新定位） |
| FMC 容器（ELF32 形式，570.144） | `/usr/lib/firmware/nvidia/gb202/gsp/fmc-570.144.bin.zst` → 199,820 B ELF32 | section：`hash` 0x30 / `signature` 0x60 / `publickey` 0x61 / `image` 0x30a48 |
| FMC bootloader（570.144） | `/usr/lib/firmware/nvidia/gb202/gsp/bootloader-570.144.bin.zst` → 200,812 B | Falcon `0x10de` 头 + **92-B desc @0x18**（本次亲手解出） |
| 610 bindata | `nvidia/generated/g_bindata_*` | GB202 的 IMAGE/DESC/HASH/SIG/PKEY 四件套 |
| 经典 wrapper | `/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin`（84,310,168 B） | 19 个 section，12 个 `.fwsignature_*` 各 0x1000 |

关键 host 侧的"检查语义"基线（决定后面所有置信度判读）：

* `NV_ASSERT(expr)` = `NV_ASSERT_OR_ELSE_STR(expr, #expr, COVERITY_ASSERT_FAIL())`
  （`nvidia/inc/libraries/utils/nvassert.h:329`）→ **不是**安全边界，release 下只记录。
* `NV_ASSERT_OR_RETURN/_OR_GOTO/_OR_ELSE` 才是真门（`nvassert.h:387` 等）。
* `NV_ASSERT_CHECKED` 在非 checked build 下**恒为空**（`nvassert.h:341-347`）。
  ⇒ 下文凡"只有 `NV_ASSERT`"的地方都按"无检查"计。

---

## 3. 通道 (1)：FMC 容器

### 3.1 72-B 容器头（第一手复算，四份 GB 系样本逐字段一致）

复算命令见 §9.2。字段与实测值：

| 偏移 | 类型 | 含义（本文命名） | GB202 610 prod | GB202 610 CC | GB100 610 | GB202 570.144 |
|---|---|---|---|---|---|---|
| `+0x00` | u16 | `ver` | 0x0403 | 0x0403 | 0x0403 | 0x0403 |
| `+0x02` | u16 | `hdrSize` | 0x48 | 0x48 | 0x48 | 0x48 |
| `+0x04` | u32 | `payloadSize` | 287,232 | … | 197,888 | 199,168 |
| `+0x08` | u32 | (未命名，全 0) | 0 | 0 | 0 | 0 |
| `+0x0c` | u32 | `codeSize` | 225,280 | 211,200 | 152,576 | 153,600 |
| `+0x10` | u32 | (未命名，全 0) | 0 | 0 | 0 | 0 |
| `+0x14` | u32 | `dataSize` | 59,392 | 43,264 | 42,752 | 43,008 |
| `+0x18` | u32 | (常量) | 0x104 | 0x104 | 0x104 | 0x104 |
| `+0x1c` | u32 | (全 0) | 0 | 0 | 0 | 0 |
| `+0x20` | u32 | (常量) | 0x2801 | 0x2801 | 0x2801 | 0x2801 |
| `+0x24..0x47` | — | 全 0（24 B） | | | | |

恒等式（四份样本全部精确成立，`hdrSize + 0xA00 + dataSize + codeSize == 文件长度`）：

```
GB202 prod : 72 + 2560 + 59392 + 225280 = 287304 = len(image)
GB202 CC   : 72 + 2560 + 43264 + 211200 = 257096 = len(image)
GB100 prod : 72 + 2560 + 42752 + 152576 = 197960 = len(image)
570.144    : 72 + 2560 + 43008 + 153600 = 199240 = len(image)
payloadSize == dataSize + codeSize + 0xA00     （四份全部成立）
```

### 3.2 逐字段"谁消费 / 什么顺序"表

判定口径：`消费`=读该字段用于分配、拷贝、索引、取地址或选槽；`验签前`=在该字节串
被任何本地可见密码学检查之前。

| 字段 | 消费方（host 可判定） | 消费方（设备侧） | 顺序证据 | 候选缺陷形状 | 置信度 |
|---|---|---|---|---|---|
| `+0x00 ver` | **无**。host 全树没有任何代码读 FMC 容器头的 `0x0403` | FSP/SEC2/FWSEC（不可见）| host 侧只把整块 blob 交给设备；`_kgspFwContainerGetSection()` 只解析 **外层 ELF64 wrapper**，从不进入 image 内部（`kernel_gsp.c:6098-6196`）| 版本选择语义（debug/prod/CC/inst-in-sys）在设备侧；若设备按 host 传入的 ver 选键，则 ver 是"验签前被消费的选择器" —— **UNKNOWN** | host 侧 **STRONG（负）** |
| `+0x02 hdrSize` | **无** | 设备侧用它定位 manifest 起点（`0xA00` 在样本里等于文件中 manifest 长度，但字段本身未被任何本地代码使用）| 同上 | 若设备用 `hdrSize` 而非常量定位 manifest/api-version，则 `hdrSize` 是 offset（**offset 派生**）；越界与否不可见 | **UNKNOWN** |
| `+0x04 payloadSize` | **无** | 设备侧可能用它界定 signed range / DMA 长度 | 同上；本地唯一"用长度"的地方是 host 自己算 section，不涉及该字段 | **未检长度**候选：若设备按 `payloadSize` 拷贝而目标固定，则形状与 170HX 相同。**本地无法证实/证伪** | **UNKNOWN（最高价值）** |
| `+0x0c codeSize` | **无** | 设备侧：code DMA/解压长度 | 同上 | 同上（无界长度）；注意 host 侧自己的"code 尺寸"来源是 **92-B desc**，不是这个字段 —— 两条来源**互不校验**（见 §3.3 ②） | **UNKNOWN** |
| `+0x14 dataSize` | **无** | 设备侧：data DMA/解压长度 | 同上 | 同上 | **UNKNOWN** |
| `+0x18` / `+0x20` 常量 | **无** | 未知（可能是 format/api version）| 四份样本恒定 ⇒ 大概率是"格式版本"而非策略开关 | 低 | **LOW** |
| 整个 72-B 头 | — | — | **签名覆盖整块 image（含头）**：`SHA-384(image)==UCODE_HASH` 且 ECDSA P-384 用 image/pkey/sig 全部验签成功（本地 9/9 样本，见 `SIGNATURE_VERIFIER_HUNT_FSP_20260925.md` §3.4） | **负结果**：篡改头必然破坏签名。因此"头被消费在前"本身**不构成**可利用面，除非设备先按头做一次拷贝/分配再验签 | **STRONG** |

### 3.3 92-B `RM_RISCV_UCODE_DESC` 逐字段表（本通道真正的硬证据）

结构定义：`nvidia/arch/nvalloc/common/inc/rmRiscvUcode.h`（23×u32 = 92 B）。
实测（第一手，§9.2）：GB202 610 `..._prd_desc.bin` / `..._dbg_desc.bin` **逐字节相同**
（sha256 `6f4ecedadb0a7da0…`），GB202 CC 的 `..._spdm_prd_desc.bin`（sha256 `bbdabd5a7c833652…`）
与 570.144 `bootloader-570.144.bin@0x18`（v5）关系见下。

| 字段 | 值（GB202 prod / GB202 CC / GB10B / GB20B） | host 消费方 | 顺序证据 | 候选缺陷 | 置信度 |
|---|---|---|---|---|---|
| `version` | 6 / 6 / 6 / 6（570.144 bootloader 里是 **5**） | **无**（全树无 `desc->version` 消费点） | — | 读 v6 字段时不检查 version ⇒ v5 描述符的尾巴字段（`bIsSmp/bIsPlicEnabled`）实测读到**垃圾值**（570.144 样本：`0x5a85f079`/`0x519e1f43`）。**字段越界/版本错配候选** | **HIGH（字段级事实）**；影响 LOW（这两个字段在 host 侧无消费者） |
| `manifestOffset` | 0 / 0 / 0 / 0 | `kgspPopulateWprMeta_GH100`（→ WPR2 meta）；`_kgspBootstrapGspFmc_GH100`（→ BCR 寄存器）| `kernel_gsp_gh100.c:342`、`:758` | **无校验**：用前不检查相对 image 的界（见下"三个 offset"） | **STRONG** |
| `monitorCodeOffset` | 0xF200 / 0xB300 / 0xB200 / 0xF000 | 同上 | `kernel_gsp_gh100.c:340`、`:744` | 同上 | **STRONG** |
| `monitorDataOffset` | 0xA00 / 0xA00 / 0xA00 / 0xA00 | 同上 | `kernel_gsp_gh100.c:341`、`:751` | 同上 | **STRONG** |
| `monitorCodeSize` | 0x37000 / 0x33900 / 0x23600 / 0x24D00 | **无消费者**（host 不读） | grep 全树 0 命中 | — | **STRONG（负）** |
| `monitorDataSize` | 0xE800 / 0xA900 / 0xA800 / 0xE600 | **无消费者** | 同上 | — | **STRONG（负）** |
| `manifestSize` | 0xA00 | **无消费者** | 同上 | — | **STRONG（负）** |
| `bIsMonitorEnabled` | 1 | **无消费者** | 同上 | — | **STRONG（负）** |
| `bootloaderOffset/Size`、`bootloaderParamOffset/Size`、`riscvElfOffset/Size`、`appVersion`、`swbrom*`(4)、`fbReservedSize`、`bSignedAsCode`、`bIsSmp`、`bIsPlicEnabled` | 0（部分见上） | **无消费者** | grep 全树 0 命中（`rmlsfm.h:374-376` 的三行 offset 名**是注释**，不是有效字段） | — | **STRONG（负）** |

**三个 offset 的"无检查"证据链（本通道核心）：**

```
① 准备阶段（host，验签前）
   kernel_gsp.c:5594  memdescCreate(&pGspRmBootUcodeMemdesc, pGpu, bufSizeAligned=ALIGN_UP(bindataSize,0x1000) …)
   kernel_gsp.c:5625  bindataStorageAcquireData(UCODE_DESC)

② 顺序（host，全部在 bootstrap 之前）
   kernel_gsp.c:5003  kgspPrepareBootBinaryImage()        // 拷 FMC/BL image + 拿 desc 指针
   kernel_gsp.c:5011  _kgspPrepareGspRmBinaryImage()      // 解析 wrapper ELF（.fwversion/.fwimage/.fwsignature_*/.note.gnu.build-id）
   kernel_gsp.c:4814  kgspPopulateWprMeta_HAL()           // ← 在这里把 3 个 offset 写进 WPR2 meta
   kernel_gsp_gh100.c:795 kgspPrepareForBootstrap_GH100() // FMC args + COT payload（hash/sig/pkey）
   kernel_gsp.c:4840  kgspBootstrap_HAL()                 // 才把设备叫起来（内部按 FSP/SEC2/直接三选一）

③ 取地址（host，无校验）
   kernel_gsp_gh100.c:744  physAddr = (fmcPhysAddr + pRiscvDesc->monitorCodeOffset) >> 8   → BCR_DMAADDR_FMCCODE_LO/HI
   kernel_gsp_gh100.c:751  physAddr = (fmcPhysAddr + pRiscvDesc->monitorDataOffset) >> 8   → BCR_DMAADDR_FMCDATA_LO/HI
   kernel_gsp_gh100.c:758  physAddr = (fmcPhysAddr + pRiscvDesc->manifestOffset)   >> 8   → BCR_DMAADDR_PKCPARAM_LO/HI
   全树没有任何 `monitorCodeOffset < gspRmBootUcodeSize` 之类的检查（grep 0 命中）。
   desc 的 `monitorCodeSize/monitorDataSize/manifestSize` 本身**也没被 host 使用**，
   因此"offset+size ≤ image 大小"的不变量在 host 侧既没有代码也没有设备侧输入。
```

硬件侧约束（`common/inc/swref/published/hopper/gh100/dev_riscv_pri.h:39-56`）：
`DMAADDR_*_LO` 是 32-bit，`DMAADDR_*_HI` 只有 **12 bit** → 有效地址上限 44 bit；
`DMACFG.TARGET` 被 host 设成 `COHERENT_SYSMEM`（`kernel_gsp_gh100.c:764-771`）。
即：**BootROM 的 FMC code/data/PKCPARAM 三个 DMA 源地址完全由 host 计算**，
且 `manifestOffset` 决定 BootROM 从哪读 PKC 参数（验证材料本身）。

**候选缺陷（本通道最硬）：**

| ID | 形状 | 描述 | 需要的能力 | 置信度 |
|---|---|---|---|---|
| **C1-1** | 未检 offset / 取地址 | 3 个 offset 未与 image 大小校验 → BootROM 从 host 指定物理地址取 FMC code/data/**验证参数**。offset 是 u32，`fmcPhysAddr + offset` 可指向 sysmem 任意 44-bit 地址 | 能替换/覆盖 bindata（MODS file-override 或改模块数据） | **STRONG（代码）**；可利用性 UNKNOWN（BootROM 的 manifest 签名/PKC 检查仍须通过） |
| **C1-2** | 未认证输入 | **92-B desc 没有任何 hash/sig 伴随 label**：`kgspGetBinArchiveGspRmBoot_GB202` 只有 `IMAGE_{DBG,PROD}` + `DESC_{DBG,PROD}`。GFW 签名只覆盖 `..._gfw_image.bin`（287,304 B），**不覆盖** `..._desc.bin`（92 B） | 同上 | **STRONG** |
| **C1-3** | 版本错配 / 字段越界 | host 读 desc 时不看 `version`；v5 desc 的尾部字段实测为垃圾；v6/v5 的字段语义只在**用到的 3 个**上经验一致 | 同上 | **MEDIUM** |
| **C1-4** | 别名（union） | WPR2 meta 里 `sysmemAddrOfSignature/sizeOfSignature` 与 `gspFwHeapFreeListWprOffset/unused0/unused1` 共用同一 16 B（`gsp_fw_wpr_meta.h:86-118`；`sysmemAddrOfSignature` 在 `:90`、`gspFwHeapFreeListWprOffset` 在 `:100`、`verified` 在 `:207`）；由 **boot mode** 决定解释方式，`revision` 只保证"接口不向下兼容" | 无（设计） | **MEDIUM**（需要设备侧消费者代码才能定级） |
| **C1-5** | 长度不匹配（host 内，低危） | `bindataWriteToBuffer(UCODE_HASH, pCotPayload->hash384, 48)` **没有** `==` 长度等式检查（同函数里 sig/pubkey 都有：`kern_fsp_gh100.c:1035/1040`；SEC2 同：`kernel_sec2_gb20b.c:788/793`）。该 label 是 `COMPRESSION: NO` ⇒ 走 `portMemCopy(dst,48,src,48)`，源数组若短于 48 B 就 OOB 读模块数据 | 同上 | **LOW**（后果只是设备侧 hash 比对失败，fail-closed） |

### 3.4 0xA00 manifest

| 项 | 结论 |
|---|---|
| 位置 | 恒在 `image[hdrSize : hdrSize+0xA00]`（=绝对 0x48..0xA48）；desc 的 `manifestOffset`=0、`manifestSize`=0xA00 与之一致，但二者**语义不同**：desc 描述的是 **GspRmBoot blob**（无 72-B 头，见 §3.5），头字段描述的是 **signed gfw 容器** |
| 内容形状 | 高熵（2546/2560 非零）；前 16 个 u32 无单调结构 ⇒ **不是** 简单的 (offset,size) 二元表；与 610 的 VBIOS manifest（`bcrt_manifest_coverage.md`/`FWSEC_OPT_TABLE_GB202_20260925.md` §6 里可解出的 hash-record 表）**形状不同** |
| host 消费方 | **无**（host 从不进入 image 内部） |
| 验签关系 | **整块被覆盖**（签名 = 整个 image 字节串）⇒ manifest 是被认证数据的一部分 |
| 候选缺陷 | **无本地证据**。真正的问题是设备侧"先按 manifest 里的记录做 DMA/解压，再验签"还是反之 —— 不可见 |
| 置信度 | 覆盖范围 **STRONG**；设备侧顺序 **UNKNOWN** |

### 3.5 一个容易搞错的地方：两种 framing 同时存在

第一手复算（§9.2）显示 GB202 610 同一个 build 里有**两套几何相同的 framing**：

| 对象 | 大小 | 头 | 被签名? |
|---|---|---|---|
| `BINDATA_LABEL_UCODE_IMAGE` of `GspRmFmcGfwProdSigned_GB202`（= `g_gsp_gb20x_dyn_prd_gfw_image.bin`） | 287,304 | **有 72-B 头**（ver 0x0403） | **有**（HASH+SIG+PKEY 三个 label） |
| `BINDATA_LABEL_UCODE_IMAGE_PROD` of `GspRmBoot_GB202`（= `g_gsp_gb20x_dyn_prd_image.bin`） | 290,816 | **无**（@0 是 manifest 字节） | **无**（该 archive 只有 IMAGE+DESC） |
| GB202 CC：`ConcatenatedFMC_GB202` | 503,808 | **无** | **无**（archive 只有 `UCODE_IMAGE_PROD`）|

两套几何一致（data 0xE800 + code 0x37000）但**字节不同**（不是同一份复制）。
因此设备侧到底"用哪套 framing + 谁验签"取决于是 FSP/SEC2 COT 路径还是
`_kgspBootstrapGspFmc_GH100` 直接路径；**同一份 desc 同时被用于两条路径的地址计算**。
→ 这是 §3.3 C1-1/C1-2 的现实触发面：只要走直接路径，desc 就是地址来源且无签名。

---

## 4. 通道 (2)：`.fwsignature_<family>` 4 KiB 帧

### 4.1 帧结构（第一手复算，本次给出精确 offset 图）

`.fwsignature_gb20x` @ `0x505f06e`（`gsp_ga10x.bin`, 610.57.04）：

| 偏移 | 值/内容 | 备注 |
|---|---|---|
| `+0x000` | u32 0x00020001 | 帧头 word0 |
| `+0x004` | u32 0x000008C8 (2248) | 含义未由公开材料定义 |
| `+0x008` | u32 0x0000000C (12) | |
| `+0x00c` | u32 0x00010100 | |
| `+0x010` | u32 0x00000200 (512) | **= 槽大小**（自描述） |
| `+0x014` | 槽0：0x14..0x194 **连续非零 384 B**，其余 128 B 为 0 | 384 B = RSA-3072 尺寸签名 |
| `+0x214` | 槽1：非零 384 B（跨 0x214..0x394，内部有 20 B 零洞） | 同上 |
| `+0x414` | 槽2：连续非零 384 B | 同上 |
| `+0x614` | 槽3：连续非零 384 B | 同上 |
| `+0x814` | 尾部小结构：`0x00010001, 0x00020001, 0x00000001, 0` | 两个家族文件在此**逐字节相同** |
| `+0x87c` | 尾部小结构：`0x00000001, 0x00000402, 0x00000001, 0` | 同上 |
| `+0x890..0xFFF` | 全 0 | 帧远未用满 4 KiB |

机械复算（本次运行 `cot_pin_work/fwsignature_frame_probe.py`）：

```
.fwimage size=84258816 sha384=c81df5bb2f7ef0693ae89ecc217fd122095fcc2afb9b883995dc85f29b197becbc42aa0f384c245eb83f0b557c5c69ce
.fwsignature_gb20x      : diff_vs_gb20x=0     p384_points=0  sha384(fwimage)_present=False
.fwsignature_cc_gb20x   : diff_vs_gb20x=1529  p384_points=0  sha384(fwimage)_present=False
（其余 7 个家族：diff 1524..1533，p384_points 全 0，hash 全 False）
9 个家族 section 的帧头 5 个 u32 完全相同
```

### 4.2 逐字段"谁解析 / 何时解析 / 有无边界校验"

| 层级 | 对帧内字段做了什么 | 代码/证据 | 边界校验 |
|---|---|---|---|
| host 内核（经典/单体路径） | 只用 **section 名** 与 **section offset/size**；`_kgspFwContainerGetSection()` 要求 `shstrndx<=shnum`、`shoff+64*shnum-1<=size`、section 数据区间 `offset+size-1<=size`；**同名 section 取"最后一个"**（表尾向前遍历） | `kernel_gsp.c:6098-6196`；570.144 实际 section 表见 `SIGNATURE_VERIFIER_HUNT_FSP_20260925.md` §3.3 | 文件名/section 级 **有**；帧内字段级 **无** |
| host 内核（拷贝） | `_kgspCreateSignatureMemdesc()`：`NV_ALIGN_UP(signatureSize,256)` 分配、`portMemCopy(dst, memdescSize, src, signatureSize)` | `kernel_gsp.c:5666-5718` | 目标 ≥ 源 **有**（alloc 用同一 size），**无**长度上限校验（上限≈文件大小） |
| host 交接 | 把 `sysmemAddrOfSignature/sizeOfSignature` 写进 WPR2 meta（初 boot 那个 union 分支） | `kernel_gsp_gh100.c:344-348` | **无** |
| host | **对帧内 `0x00020001/0x8C8/0x0C/0x00010100/0x200` 与 4 个槽一个字都不解析**（全树 0 消费点） | grep 全树：除 `_kgspPrepareGspRmBinaryImage`/`_kgspCreateSignatureMemdesc` 外无 `pSignatureData` 消费者 | — |
| 设备侧 | 由 **Booter** 消费（WPR2 meta 的注释即契约：`gsp_fw_wpr_meta.h:33` "Verified, and locked in WPR2 by Booter"） | — | **UNKNOWN** |
| 设备侧解析器是否在本地 | **不在**。实测：`ad102/ga102` 的 `booter_load/booter_unload/scrubber-570.144.bin` 里 `0x00020001` 与 `0x8C8` 命中数 = **0**；GB202 连 `booter_load-*.bin` 都没有本地副本 | §9.3 | — |

**候选缺陷（通道 2）：**

| ID | 形状 | 描述 | 置信度 |
|---|---|---|---|
| C2-1 | 选择语义分歧（selector mismatch） | host 对**同名 section 取最后一个**（`for (idx = shnum-1; idx >= 0; idx--)` 命中即返回）。若设备侧有独立解析器并按"第一个"取，或按"section 序号"取，则 host/device 对"哪 384 B 是生效签名"可以不一致 —— 这是**版本选择型**（而非内存破坏型）候选 | host 语义 **STRONG**；device 语义 **UNKNOWN** |
| C2-2 | 槽数/槽长为**自描述且未校验** | 帧内 `0x200` 自称槽长、4 个槽无计数/无类型标签；host 不做任何一致性检查（`0x8C8` 与 4×0x200+0x14 不等，说明还有未命名子结构） | **STRONG（host 无校验）** |
| C2-3 | 帧内无 hash、无公钥 | 与 `E8` 一致：帧里既无 97-B P-384 点、也无 `SHA-384(.fwimage)` ⇒ 签名对象/公钥只能来自别处（熔丝/其它 section/设备 ROM）。对"验签前"的意义：设备必须先信一个外部根才能用这 4 个槽 | **STRONG（负结果，实测）** |
| C2-4 | 长度上限缺失 | `signatureSize` 只受"section 必须在文件内"约束，可让 host 分配/搬运 ≈文件大小 | **MEDIUM**（DoS 面，需要能替换 blob） |

---

## 5. 通道 (3)：控制面（NVDM / task-subobject / PRC / `NV2080_CTRL_*`）

### 5.1 公开树里"到底有哪些 NVDM 结构"（完整清单，避免把不存在的头字段当事实）

| 结构 | 定义 | 字段 | host 消费点 |
|---|---|---|---|
| MCTP 头 | `mctp_format.h:43-55` | w0：`VERSION[3:0] RSVD[7:4] DEID[15:8] SEID[23:16] TAG[26:24] TO SEQ[29:28] EOM[30] SOM[31]`；w1：`TYPE[6:0] IC[7] VENDOR_ID[23:8] NVDM_TYPE[31:24]`（`TYPE` 必须 0x7e、`VENDOR_ID` 必须 0x10de） | `kfspGetPacketInfo_GH100:317`、`ksec2GetPacketInfo_GB20B:200` |
| NVDM 类型 | `nvdm_format.h:41-58` | `0x04 RESET, 0x11 HULK, 0x12 FIRMWARE_UPDATE, 0x13 PRC, 0x14 COT, 0x15/0x18 RESPONSE/SMBPBI, 0x16 CAPS_QUERY, 0x17 INFOROM, 0x1A ROMREAD, 0x1C UEFI_RM, 0x1D UEFI_XTL_DEBUG_INTR, 0x1F TNVL, 0x20 CLOCK_BOOST, 0x21 FSP_GSP_COMM, 0x25 RM_RPC` | 见 §5.2 表 |
| PRC 读请求 | `kern_gpu_gh100.c:542-548`（`NVDM_PAYLOAD_PRC_OBJECT_READ`）| `prcObjType u8; numBytes u8; knobId u16`（packed，4 B）| `gpuIsProtectedPcieSupportedInFirmware_GH100():576-606`（**唯一**的 host PRC 发送方）|
| PRC 响应 | `kern_gpu_gh100.c:551-560`（`NVDM_PAYLOAD_PRC_OBJECT_RESPONSE`）| `messageType u8; taskId u32; commandNvdmType u32; errorCode u32; knobValue u16; misc u16`（packed，17 B）| 同上，`responseBufferSize = 17` |
| SEC2/FSP 通用响应 | `fsp/nvdm_payload_cmd_response.h:35-42`（SEC2 同名副本）| `taskId u32; commandNvdmType u32; errorCode u32`（packed，12 B）| `kfspProcessCommandResponse_GH100`（`kern_fsp_gh100.c:466`；size 检查 `:478`）、`ksec2ProcessCommandResponse_GB20B`（size 检查 `kernel_sec2_gb20b.c:375`）|
| COT payload | `kern_fsp_cot_payload.h:36-55` | `version u16; size u16; gspFmcSysmemOffset u64; frtsSysmemOffset u64; frtsSysmemSize u32; frtsVidmemOffset u64; frtsVidmemSize u32; hash384[12]; publicKey[96]; signature[96]; gspBootArgsSysmemOffset u64` | 见 §5.3 |
| CAPS / CLOCK_BOOST / TNVL | `fsp_caps_query_rpc.h`、`fsp_clock_boost_rpc.h`、`fsp_tnvl_rpc.h` | CAPS/CLOCK_BOOST：`subMessageId u8`（+rspPayload）；TNVL：`subMessageId u8; rsvd u8; minorVersion u8; majorVersion u8`（+`nonce`/`certChainLength u16`/`measurementSize u32`…） | `kfspCheckForClockBoostCapability_GB100()`、`kern_fsp_gb100.c:179/262` |

**明确负结果（重要）**：公开树里**没有**任务描述里那种
`PRC 包头 { sub_message_id, flags, object_id, reserved }` 结构。
grep 全树 `sub_message_id` / `subMessageId` 只有 TNVL/CAPS/CLOCK_BOOST 的
**1 字节** `subMessageId`（且它们不是"包头"，就是载荷首字节）。
`flags`/`reserved`/`object_id` 作为**包头字段**只出现在 **nvswitch ls10** 的
`fsprpc_nvswitch.h`（`NVSWITCH` 路径），**不在 GB202 的 GPU 路径**上。
GB202 上离它最近的真实结构是 4-B 的 `{prcObjType, numBytes, knobId}`：
`prcObjType`≈object_id，`numBytes`≈长度/计数，`knobId`≈**16-bit 索引**。

### 5.2 host→device 发送面（谁在验签前决定长度/索引）

| 发送方 | nvdmType | 载荷字段 | "验签前消费"判定 |
|---|---|---|---|
| `gpuIsProtectedPcieSupportedInFirmware_GH100` | PRC 0x13 | `prcObjType=0x0C`、`numBytes=0x02`、`knobId=0x2D`（**全是 host 硬编码**，非用户可控） | 这是**索引/长度**进入设备 selector 的最纯粹样例：`knobId` 是 16-bit **索引**、`numBytes` 是 **返回长度**。设备侧若按 `knobId` 查表而不检查范围 ⇒ 未检索引；若按 `numBytes` 组装回复 ⇒ 未检长度。**设备侧代码不在本地 ⇒ UNKNOWN**，但"host 提供索引+长度且协议无 TLV 长度字段"是 **STRONG** |
| `kfspCheckForClockBoostCapability_GB100` | CAPS 0x16 | `subMessageId` 1 B | 低 |
| `kfspSendClockBoostRpc_GB100` | CLOCK 0x20 | `subMessageId` 1 B | 低 |
| FSP COT | COT 0x14 | 见 §5.3 | **中**（见下） |
| SEC2 COT | COT 0x14 | 同上 | 中 |
| FSP/SEC2/GSP-RM 帧传输 | 任意 | 分片：首片 7 B MCTP 头 + 1 B NVDM type（被折叠进 w1），后续片 4 B | 见下方"发送侧的长度处理" |

**发送侧的"长度"处理（全部 fail-closed，负结果）：**
`kfspSendMessage`（`kern_fsp.c:480-576`）与 `ksec2SendMessage`（`kernel_sec2.c:250-345`）
都用 `maxPacketSize = ksec2/kfspGetMaxSendPacketSize_HAL()` 先算容量，
`curPayloadSize = NV_MIN(size, packetPayloadCapacity)`，每片都用 `portMemCopy(dst, packetPayloadCapacity, src, curPayloadSize)`
⇒ **目标容量是常量、源长度被 MIN 夹住**，无越界。**STRONG（负）**。

### 5.3 COT payload：host 递交、设备第一件事就用

| 字段 | host 值/来源 | 设备侧"验签前"用法（结构性） | 候选缺陷 | 置信度 |
|---|---|---|---|---|
| `version u16` | FSP HAL：GB202/GB100/GB10B/GB20B/GB20C = **2**，其余 = 1（`g_kern_fsp_nvoc.c:262-299`，`cotPayloadVersion` 赋值在 `:290`）；SEC2 HAL：GB10B=1、GB20B/C=2、**其余=0**（`g_kernel_sec2_nvoc.c:491-509`，sig/pubkey 恒 **384**） | 设备**必须**先读 `version` 才能知道后面 `publicKey`/`signature` 各是 96/97（P-384）还是 384/384（RSA-3072）⇒ **version 是"验签前被消费的选择器"**，这是本通道最干净的一条 | 若设备用 `version` 选**键槽/熔丝来源**（debug vs prod、revoked slot），则 version 是 host 可控的 downgrade 选择器 | **STRONG（结构性）**；后果 UNKNOWN |
| `size u16` | host 恒填 `sizeof(NVDM_PAYLOAD_COT)` | 设备若用 `size` 界定解析范围，则它是长度字段 | **未检长度候选**：本地只能证明 host 填的是常量 | **MEDIUM** |
| `hash384[12]` (48 B) | bindata `UCODE_HASH`，`bindataWriteToBuffer(..., 48)` **无等式检查**（C1-5） | 设备用它比对 `SHA-384(image)` | C1-5 | **LOW** |
| `publicKey[96]`(384 B 缓冲) | bindata `UCODE_PKEY`，97 B（P-384 未压缩点）；FSP 路径断言 `==97`；**SEC2 路径断言 `==384`** | 设备用 host 递交的公钥（或只用来做比对） | **跨 HAL 长度语义不一致**：GB202 prod 实际键 97 B，SEC2 HAL 却要求 384 B —— 本地样本（570/610）全部是 96/97 ⇒ 若 GB202 真走 SEC2 COT，`NV_ASSERT_OR_GOTO(... ==384)` 会**直接 failed**（fail-closed）。这解释了为什么必须走 FSP：与 `evidence_audit.md` 的"GB202 NVDM 端点是 FSP"一致 | **STRONG（代码级不一致）** |
| `signature[96]`(384 B 缓冲) | 同上 96 B | 设备验签 | — | — |
| `gspFmcSysmemOffset u64` | host 分配并清零的 sysmem 物理地址 | 设备从该地址 DMA 整个 FMC blob | **受信域按 host 给的地址取"待验证字节"**（这一步按定义在验签之前） | **STRONG（结构性/必然）** |
| `frtsSysmemOffset/Size`、`frtsVidmemOffset/Size` | host 分配，`frtsSize` 来自常量 `NV_PGC6_AON_FRTS_INPUT_WPR_SIZE…<<12`（`kern_fsp_gh100.c:1338`，回填 `:1381`） | 设备写入 FRTS 区 | 目标 buffer 由 host 分配、长度由 host 填 —— 若设备按 `frtsSysmemSize` 写而实际大小不符 ⇒ 未检长度。**host 侧两侧一致（同一个 `frtsSize` 变量）⇒ 仅"设备是否复核"不可见** | **MEDIUM** |
| `gspBootArgsSysmemOffset u64` | host 的 `pGspFmcArgumentsDescriptor` | FMC 从这里读 boot args | **boot args 结构是 host 完全可控的地址+尺寸表**（见 §5.4） | **STRONG（结构性）** |

### 5.4 FMC boot args / WPR2 meta：host 递交的"地址+尺寸表"

`GSP_FMC_BOOT_PARAMS`（`gsp/gspifpub.h:47-119`，packed 结构）由
`kgspSetupGspFmcArgs_GH100()`（`kernel_gsp_gh100.c:419-497`）填充，物理地址经
`MAILBOX0/1` 交给 FMC（`kernel_gsp_gh100.c:733-735`）。**FMC 读它是在任何验签之前**。

| 字段 | host 值 | 设备侧用途 | 候选缺陷 |
|---|---|---|---|
| `bootGspRmParams.gspRmDescOffset` | `pWprMetaDescriptor` 物理地址 | FMC/ACR 从这读 WPR2 meta | 地址由 host 给（必然） |
| `bootGspRmParams.gspRmDescSize` | `sizeof(GspFwWprMeta)` = **256**（`ct_assert`） | 解析 meta 的长度 | **未检长度候选**：host 填常量，但字段本身无认证；`ct_assert` 只保证 host 自己的结构是 256 B |
| `bootGspRmParams.target` | `GSP_DMA_TARGET_COHERENT_SYSTEM`/`LOCAL_FB` | 决定 DMA aperture | 选择器（host 控制） |
| `gspRmParams.bootArgsOffset` | `pLibosInitArgumentsDescriptor` 物理地址 | GSP-RM init args | 地址 |
| `gspSpdmParams.payloadBufferOffset/payloadBufferSize` | `pSpdm->pPayloadBufferMemDesc` + `payloadBufferSize` | SPDM 通道 | 长度字段 |
| `initParams.regkeys u32` | `pCC->gspProxyRegkeys` \| nvlink regkeys | FMC 侧"registry" | 策略位（不是长度） |
| `gspRmMemParams.flushSysmemAddrValLo/Hi` | 可选 flush buffer 物理地址 | CC WAR | 地址 |
| WPR2 meta 的 `sizeOfBootloader / sysmemAddrOfBootloader / sysmemAddrOfRadix3Elf / sizeOfRadix3Elf` | host 计算（image 大小来自 bindata） | Booter DMA | **长度来自 host**；`verified` 字段由 Booter 回填 0xa0a0…（=验签结果落点） |

### 5.5 GSP-RM 消息队列（NVDM 0x25 RM_RPC）—— 本通道唯一代码级候选缺陷

路径：`NV2080_CTRL_*` 在 GSP-client 模式下经 `rpc.c` 打包 → `GspMsgQueueSendCommand`
→ 共享队列 → GSP-RM（设备）；反向 `GspMsgQueueReceiveStatus`。

**TX 方向（host→device）——fail-closed（负结果）：**

```
message_queue_cpu.c:487  msgLen = queueElementHdrSize + gspMsgQueueGetRpcMessageLength(pMQI, pCQE)
message_queue_cpu.c:491  if ((msgLen < queueElementHdrSize) || (msgLen > queueElementSizeMax)) → NV_ERR_INVALID_PARAM_STRUCT
message_queue_cpu.c:503  nElements = gspMsgQueueBytesToElements(msgLen, queueElementSizeMin)   // 检查之后才用
message_queue_cpu.c:545  checkSum = _checkSum32(pSrc, msgLen)   // CC 开时用 541（整元素）
```
长度在**使用之前**检查（并且 `msgLen < hdrSize` 专门抓 u32 wrap）。**STRONG（负）**。

**RX 方向（device→host）——候选缺陷 C3-1（长度检查在拷贝之后）：**

```
message_queue_cpu.c:643  pTgt = (NvU8 *)pMQI->pCmdQueueElement;      // staging 区
message_queue_cpu.c:660  for (i = 0; i < nElements; i++)              // nElements 初值 1
message_queue_cpu.c:680      portMemCopy(pTgt, queueElementSizeMin, pNextElement, queueElementSizeMin);
message_queue_cpu.c:682      pTgt += queueElementSizeMin;
message_queue_cpu.c:698      nElements = gspMsgQueueBytesToElements(   // ← 用设备给的 length 改循环上界
                                 queueElementHdrSize + gspMsgQueueGetRpcMessageLength(pMQI, pMQI->pCmdQueueElement), …)
message_queue_cpu.c:823  // Sanity check for the given RPC length      // ← 检查在这里，循环已经结束
message_queue_cpu.c:827      (msgLen > pMQI->queueElementSizeMax) → NV_ERR_INVALID_PARAM_STRUCT
```

量化（全部为本地常量，可复算）：

| 量 | 值 | 出处 |
|---|---|---|
| `queueElementSizeMin` | `RM_PAGE_SIZE` = 4096 | `message_queue_cpu.c:88` |
| `queueElementSizeMax` | `RM_PAGE_SIZE*16` = **65536** | `:89` |
| staging 可用空间 | 就是 `queueElementSizeMax`；`pMetaData = pCmdQueueElement + queueElementSizeMax`（**紧邻**） | `:151-164` |
| status 队列默认 | 0x40000 = 262144 B ⇒ `msgCount` = **64** 元素 | `:71-72,117` |
| 可"可用"的元素上界 | `rxAvail = writePtr + msgCount - readPtr`（≥msgCount 就减 msgCount）⇒ 最大 **63** | `msgq.c:640-677`（计算在 `:660`） |
| 元素布局 | `GSP_MSG_QUEUE_ELEMENT = {mctpHeader, nvdmHeader, checkSum, seqNum, payload[]}`（16 B 头）⇒ `queueElementHdrSize = 16`；payload 首字节就是 RPC 头，而 `rpc_message_header_v.length` 在 RPC 头 **+0x08**（`g_rpc-message-header.h:41-52`：`header_version, signature, length, function, …`）| `message_queue_priv.h:52-67` |
| 63 元素拷贝量 | 63×4096 = **258,048 B** 打进 65,536 B ⇒ 溢出 ≈ **192 KB**；第 17 个元素起就砸到 `pMetaData`（消息队列自己的 `msgqMetadata`），随后越出 `portMemAllocNonPaged(workAreaSize)` 分配。**诚实的限制**：溢出会同步破环 `msgqMetadata`（`rxReadPtr`/`rxAvail`），循环后半段的可用性判断也就不可靠 ⇒ 利用不是直白的（需要构造能跑完的记录数/队列状态），但**写入先于检查**这一事实本身不受影响 | 复算 |
| `msgqRxGetReadBuffer` 的界 | 只按"队列可用元素数"判（`if ((n >= pQueue->rxAvail) && (n >= msgqRxGetReadAvailable(handle))) return NULL;`），**不按 staging 区大小判** | `msgq.c:672-700` |
| registry 放大 | `NV_REG_STR_RM_GSP_STATUS_QUEUE_SIZE`（KB）可把 status 队列加大 ⇒ 可可用元素更多 ⇒ 溢出更大 | `:107-113` |

⇒ **候选缺陷 C3-1**：设备可发布首元素 `rpc_message_header_v.length` = 任意大值并使
N 个元素 available，host 在"长度合法性检查"之前就拷 N×4 KB 到 64 KB staging 区，
内容完全由设备控制。**形状与 170HX 同（长度在检查之前被消费），方向相反
（device→host）**。置信度：**HIGH（代码级确定）**；影响面取决于威胁模型
（需要 GSP-RM 侧可控/被攻陷，或任何能把越界记录投进 RM status 队列的路径）。
另外注意：`source 侧`的同类循环在**设备侧**（`message_queue_gsp.c`）**不在公开树**，
同一份逻辑很可能是共享代码 ⇒ 该方向对"host 控长度 → 设备 OOB"的镜像结论
**无法本地判定**（UNKNOWN）。

其它已在本文档核过的点：

| 位置 | 形状 | 结论 |
|---|---|---|
| `_ksec2ReadMessage` / `kfspReadMessage`：`curPayloadSize = packetSize - curHeaderSize`（`kernel_sec2.c:455`、`kern_fsp.c:657`）| u32 下溢候选 | **负结果**：`packetSize` 先被 `ksec2ReadPacket_GB20B` 夹在 `[4, maxPacketSize]`；START/SINGLE 分支必经 `ksec2ValidateMctpPayloadHeader_GB20B`，其中 `size < sizeof(MCTP_HEADER)+1 = 8` 直接返回错 ⇒ `packetSize ≥ 8` ⇒ `curPayloadSize ≥ 1`，**不可能下溢** |
| 同上，`portMemCopy(pPayloadBuffer + totalPayloadSize, payloadBufferSize - totalPayloadSize, …)` | 未检计数 | **负结果**：前一行 `payloadBufferSize < (totalPayloadSize + curPayloadSize)` → 报错。（只在 `curPayloadSize` 可下溢时才有 wrap 风险，而上一条排除了） |
| `ksec2ValidateMctpPayloadHeader_GB20B` | 读 `((NvU32*)pBuffer)[1]` **早于** `size>=8` 检查 | **低危**：读到的是 1024-B 收包缓冲内的 4..7 字节（未初始化/陈旧），仅影响接受/拒绝判定，不回传内容 |
| `kfspReadPacket_GH100` / `ksec2ReadPacket_GB20B` | `packetSize = (msgqTail-msgqHead)+4`（设备写 head/tail 寄存器） | **负结果**：`NV_ASSERT_OR_RETURN((packetSize >= 4) && (packetSize <= maxPacketSize))`，会 wrap 但被上下界抓住（`kern_fsp_gh100.c:666-694`、`kernel_sec2_gb20b.c:459-500`）|
| FSP/SEC2 通用响应解析 | `size < headerSize + sizeof(NVDM_PAYLOAD_COMMAND_RESPONSE)` 先查 | **负结果**（`kernel_sec2_gb20b.c:375`、`kern_fsp_gh100.c:478`）|

### 5.6 `NV2080_CTRL_*` 的长度/计数处理

| 检查 | 位置 | 判定 |
|---|---|---|
| `paramsSize` 必须**精确等于**生成表里的 `ctrlParamsSize` | `rmapi/control.c:445-458`（`rmapiutilGetControlInfo` + `paramsSize != ctrlParamsSize`）| **STRONG（负）**：`NV2080_CTRL_*` 走的正是这张表 ⇒ 长度由 RM 自己钉死，客户端改 `NVOS54_PARAMETERS.paramsSize` 会被拒 |
| **例外**：`getCtrlInfoStatus != NV_OK`（命令不在表里）时该等式**被短路**，`paramsSize` 不再与任何期望值比对 | `control.c:450` | **候选**：未知/非表内命令的 `paramsSize`（ioctl 侧 = 客户端可控，`osapi.c` 等）会原样进入 handler。**MEDIUM**（需逐个 handler 审计那些"用 paramsSize 做拷贝"的地方） |
| 内部/内核客户端绕过 | `control.c:424-445`（privLevel 判定在 `:438`，在 size 检查**之前**）| 顺序：先是 client 有效性 + IRQL/priv 检查，再 size 检查，再 `rmCtrlParams.pParams = pUserParams` 赋值。**priv 检查在 size 检查之前 ⇒ 顺序正确**（STRONG） |
| `ctrlParamListSize` 类"计数"字段 | **公开树 0 命中**（`grep ctrlParamListSize` 无结果）| 这些 handler 在闭源 RM 核心；**UNKNOWN**，只能靠 §8 的下一步去定位 |
| 计数器风格 | 已有 `pDumpParams->size <= NV0000_CTRL_NVD_MAX_DUMP_SIZE`、`pParams->size <= NV0000_CTRL_NVLOG_MAX_BLOCK_SIZE` 之类的**显式上限**（`client_resource.c:3607/3841`）| 正面样例：说明 RM 里有"先夹长度再用"的既有模式，可作为对照基线 |

---

## 6. 明确负结果清单（同样重要）

| ID | 负结果 | 证据 |
|---|---|---|
| N1 | 本机可见的全部 open 源码里，**没有任何 host 侧密码学验证**用在 FMC/COT/`.fwsignature_*`/desc 上（只有 `SHA`/`ECDSA` 字面在库里，GSP/FSP/SEC2 目录 0 命中） | grep `nvidia/src/kernel/gpu/{gsp,fsp,sec2}/` 对 `sha384|sha256|rsa_|ecdsa|verifySignature` = 0 |
| N2 | 72-B 容器头的 10 个字段在 host 侧**消费点 = 0** | 全树 grep；唯一"进入 image 内部"的解析器不存在 |
| N3 | 92-B desc 的 **20/23 个字段消费者 = 0**（只有 3 个 offset 被用） | 全树 grep，逐字段列于 §3.3 |
| N4 | `.fwsignature_*` 4 KiB 帧：**host 不解析任何字段**；帧内**无公钥、无 `SHA-384(.fwimage)`** | §4.1/§4.2 + `fwsignature_frame_probe.py` 运行结果（9 个家族 p384_points=0、hash False） |
| N5 | 公开树里**没有** `{sub_message_id, flags, object_id, reserved}` 这种 PRC 包头（只有 4-B `{prcObjType,numBytes,knobId}` 与 17-B 响应；`subMessageId` 是 TNVL/CAPS/CLOCK 的 1 字节载荷首字节） | §5.1 全清单 + grep |
| N6 | 公开树里**没有** HULK(0x11)/FIRMWARE_UPDATE(0x12)/ROMREAD(0x1A)/UEFI(0x1C/0x1D)/FSP_GSP_COMM(0x21) 的**发送方或载荷定义** | grep：这些常量只出现在 `nvdm_format.h`（+ INFOROM/HULK 仅做 SEID 映射 `kern_fsp_gh100.c:292-296`、`kernel_sec2_gb20b.c:186-192`） |
| N7 | 设备侧 3 份 GSP-RM 二进制里 **0 命中**：`WPR2 meta magic 0xdc3aae21371a60b3`、`GSP_FW_WPR_META_VERIFIED 0xa0a0…`（除 1 处巧合）、`GSP_FW_HEAP_FREE_LIST_MAGIC`、`NVUCODES`、`.fwsignature_`（570/610 RX 两份 0；82MB 那份的 12 命中在**外层 .shstrtab 字符串区** @0x4ec02a4，不是解析器） | §9.4 逐文件字节搜索 |
| N8 | **没有 GB202 的 FMC/Booter 解析器可读**：GB202 无本地 `booter_load/booter_unload`；`ad102/ga102` 的 booter 里 0x00020001/0x8C8 **0 命中**；`fmc-*.bin` 是 ELF32 容器（host 侧无消费者：open 驱动按 `nv-firmware.h` 只取 `gsp_ga10x/gsp_log_ga10x/ucodes_ga10x`） | §9.3 + `nv-firmware.h:96-115` |
| N9 | GB202 的 FMC 公钥/签名/hash 在**全部本地设备侧制品**里 0 命中（沿用 `COT_PUBKEY_PINNING_20260925.md` E1/E2，本次未推翻） | 引用 |
| N10 | 发送方向（host→device）的长度处理 fail-closed：FSP/SEC2 分片 `NV_MIN` + 常量容量；GSP-RM 队列 TX 先检 `msgLen` 再算 `nElements` | §5.2/§5.5 |
| N11 | `ksec2/kfspReadMessage` 的 u32 下溢路径**被上游 size 检查排除**（不是缺陷） | §5.5 |
| N12 | CC/inst-in-sys 路径（`ConcatenatedFMC`）**没有任何 hash/sig/pkey label**（archive 只有 IMAGE），与既有 §5.4 一致 | `g_bindata_kgspGetBinArchiveConcatenatedFMC_GB202.c` label 清单 |
| N13 | 公开树**没有** 570.144 的 `fmc-*.bin`（ELF32）消费者 | `nv-firmware.h` 只声明 `gsp_*/gsp_log_*/ucodes_*` 三种类型 + 4 个基名 |

---

## 7. 置信度与威胁模型说明（避免误读）

1. **"host 递交"的口径**：本文严格区分
   (a) **运行期 host 递交的字节**（NVDM COT payload、WPR2 meta、FMC args、消息队列记录）；
   (b) **随驱动/固件包一起递交的字节**（bindata、`/lib/firmware` 文件、92-B desc）。
   C1-1/C1-2/C3-1 的可达性依赖 (b) 能被替换（MODS file-override / 改模块数据 /
   换 `/lib/firmware`），这一点本身需要额外的本地权限，本文不提供任何操作路径。
2. **"验签前"的判定**：只有两处能给出**代码级**顺序（C1-1 的 host 侧顺序、
   C3-1 的检查/使用顺序）。FMC 容器头与 manifest 的"验签前消费"是**结构性必然**
   （受信域必须先知道在哪、多长，才可能去验），但**无法证明它用没用那些长度做拷贝**。
3. **170HX 同类形状在本文档里的落点**：
   最接近字面形状的是 **§3.1 的 `payloadSize/codeSize/dataSize` 三字段**（host 递交
   的容器字节 + 受信域内的长度），但**消费者不在本地** ⇒ 只能列为最高价值 UNKNOWN；
   实际拿到代码证据的是 **§3.3 的三个 offset（host 计算 → 受信域 DMA）** 与
   **§5.5 的 message-queue RX（长度在检查前消费）**，两者与 170HX 同类但方向/层级不同。

---

## 8. 5 个纯静态下一步（不需要设备）

1. **给三处 index/offset 做"合成输入 → 判定顺序"的可回归复现（用户态，不加载模块）**
   目标：把 (i) `control.c:445-458` 的 `paramsSize==ctrlParamsSize` 短路条件
   （`getCtrlInfoStatus != NV_OK`）、(ii) `message_queue_cpu.c:660-700` 的
   `nElements` 计算链、(iii) `_kgspFwContainerGetSection` 的 `shstrndx<=shnum`
   与 `strtab size` 边界，写成纯 Python 判定树 + 测试向量（含 `shstrndx==shnum`、
   strtab `size=0`、`name` 极大、同名 section 两份）。
   判据：能否用**不越界**的输入得到"通过全部检查"（复现既有 §5.1 的结论），
   以及 `nElements` 在多少元素/多大 `statusQueueSize` 下越过 64 KB。

2. **定位设备侧 `message_queue_gsp.c` 等价物：在 GSP-RM 二进制里找 msgq 元数据布局的常量族**
   目标：用本机 `libraries/msgq` 里可编译出的常量（`msgqMetadata` 字段偏移、
   `FCN_FLAG_BACKEND_QUEUE_RX`、`rxAvail` 计算）在 3 份 RV64 ELF 里做**结构-常量匹配**
   （不是 u32 盲扫：用 `lui+addi` 成对 + 结构偏移组合）。
   判据：能否在设备侧定位到"读 `pWriteIncoming` → 算 `available` → 定元素数"的循环，
   从而判定 host 递交的长尾记录能否驱动设备侧 staging 拷贝。

3. **把 `.fwsignature_*` 4 KiB 帧的 12 个家族做成 schema 矩阵 + 槽位归属验证**
   目标：本次已拿到精确布局（头 5×u32 + 4×0x200 槽 + 尾部 0x814/0x87c 小结构）。
   下一步把 570.144（7 份）与 610.57.04（12 份）全部对齐，判定：
   (a) 尾部两处小结构是否是"记录数/类型/大小"（`0x00000402` 像 type、`1` 像 count）；
   (b) 4 个槽是否与 `NV_FUSE_ZB_OPT_FPF_SEC2/GSP_UCODE1_VERSION` 的槽序对应
   （用 `s_patchBooterUcodeSignature` 的 `sigIndex = numSigs-1-fuseVer` 语义反推）；
   (c) 槽内 384 B 是否与 `BINDATA_LABEL_UCODE_SIG_PATCH_*`/`NUM_SIGS` 家族同源。
   判据：能否把 12 份归约成"同构 4 槽 + 家族参数 + 固定尾部"。

4. **跨 framing 一致性审计（容器头 vs desc 的交集）**
   目标：把 GB202/GB100/GR100/GH100/GB10B/GB20B 的 **signed gfw 容器头**、
   **无头 GspRmBoot blob**、**92-B desc** 三者做几何矩阵（本次只做了 GB202/GB100，
   已发现 570.144 的 desc 是 **version=5** 且尾部字段为垃圾）。
   判据：是否存在"某些 chip 走 signed 容器、某些走无头 blob"的绑定表；以及
   `_kgspBootstrapGspFmc_GH100` 的 BCR 寄存器路径在哪些 chip 上是**可达**的
   （按 `pKernelFsp/pKernelSec2` 的构造条件逐 chip 判定 ⇒ 决定 C1-1 的真实可达性）。

5. **PRC/knob 面的设备侧存在性审计（字符串 + 名字池 + 交叉引用）**
   目标：本机已确认 PRC 发送方只有一条（PPCIE knob read：`prcObjType=0x0C,numBytes=0x02,knobId=0x2D`）。
   下一步：在 82MB debug ELF 的 `NV_FWSECLIC_ERR_CODE_*` 名池附近（@0xe2bdf2..）
   以及 MODS 570.215 名字池里，查找 "knob"/"PRC"/"numBytes" 家族的**错误名/日志格式串**，
   并用**名字池 → 交叉引用**的方式判定设备侧是否存在"按 host 给的 `knobId`/`numBytes`
   查表/组装"的路径（有则 C3-2 从 UNKNOWN 升级）。
   判据：是否能找到一个"索引越界/长度超限"类的错误名且被 PRC 处理函数引用。

---

## 9. 复现命令（全部只读；无设备访问）

### 9.1 host 源码第二份交叉核对（本次已实跑，11/11 逐字节相同）

```bash
A=/usr/src/nvidia-610.57.04/src
B=/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src
for f in nvidia/src/kernel/gpu/gsp/kernel_gsp.c \
         nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c \
         nvidia/src/kernel/gpu/gsp/message_queue_cpu.c \
         nvidia/src/kernel/gpu/fsp/kern_fsp.c \
         nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c \
         nvidia/src/kernel/gpu/sec2/kernel_sec2.c \
         nvidia/src/kernel/gpu/sec2/arch/blackwell/kernel_sec2_gb20b.c \
         nvidia/src/kernel/gpu/arch/hopper/kern_gpu_gh100.c \
         nvidia/src/kernel/rmapi/control.c \
         nvidia/src/libraries/msgq/msgq.c \
         nvidia/arch/nvalloc/common/inc/flcnretval.h ; do
  echo "$(diff -u "$A/$f" "$B/$f" | wc -l)  $(sha256sum "$B/$f" | cut -c1-12)  $f"
done
```

结果：**全部 `0 lines-diff`**（含 `kernel_gsp.c` `a0cc13bac921`、`message_queue_cpu.c` `bf4e4f6513b4`、
`msgq.c` `6285dca23061`、`kern_fsp_gh100.c` `63f4acb79c32`、`kernel_sec2_gb20b.c` `4906b5f957c8`、
`control.c` `0c686e045845`）⇒ 本文所有 file:line 引用在两个分支上**行号与内容一致**，
不存在“引用自旧分支”的风险。

### 9.2 FMC 容器头 + 92-B desc 复算（本次第一手）

```bash
mkdir -p /tmp/fmcchk && cd /tmp/fmcchk
zstd -d -q -f /usr/lib/firmware/nvidia/gb202/gsp/fmc-570.144.bin.zst -o fmc.bin
zstd -d -q -f /usr/lib/firmware/nvidia/gb202/gsp/bootloader-570.144.bin.zst -o bl.bin
cd /home/user/rt_5090_project/parallel
python3 fmc_signature_probe_20260925.py fmc-elf /tmp/fmcchk/fmc.bin
python3 - <<'PY'
import re,zlib,struct
G='/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src/nvidia/generated/'
def parse(p):
    t=open(p,errors='replace').read()
    F=re.compile(r'//\s*FUNCTION:\s*(\w+)\("([^"]+)"\)\s*\n(.*?)static BINDATA_CONST',re.S)
    A=re.compile(r'static BINDATA_CONST[^=]*=\s*\{(.*?)\};',re.S)
    B=re.compile(r'0x([0-9a-fA-F]{2})')
    metas=[(m.group(2),bool(re.search(r'// COMPRESSION: Y',m.group(3)))) for m in F.finditer(t)]
    arrs=[bytes(int(x,16) for x in B.findall(m.group(1))) for m in A.finditer(t)]
    return [(l,zlib.decompress(r,-15) if c else r) for (l,c),r in zip(metas,arrs)]
for f in ['g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c',
          'g_bindata_kgspGetBinArchiveGspRmBoot_GB202.c']:
    for l,d in parse(G+f):
        print(f,l,len(d))
        if len(d)==92:
            n="version bootloaderOffset bootloaderSize bootloaderParamOffset bootloaderParamSize riscvElfOffset riscvElfSize appVersion manifestOffset manifestSize monitorDataOffset monitorDataSize monitorCodeOffset monitorCodeSize bIsMonitorEnabled swbromCodeOffset swbromCodeSize swbromDataOffset swbromDataSize fbReservedSize bSignedAsCode bIsSmp bIsPlicEnabled".split()
            for k,v in zip(n,struct.unpack_from('<23I',d,0)): print('   ',k,v,hex(v))
        elif len(d)>1000 and d[:2]==b'\x03\x04':
            ver,hdr=struct.unpack_from('<HH',d,0)
            print('   container: ver=0x%04x hdr=%d'%(ver,hdr),
                  [hex(x) for x in struct.unpack_from('<7I',d,4)])   # => '0x46200 0x0 0x37000 0x0 0xe800 0x104 0x0'
PY
```

### 9.3 `.fwsignature_*` 帧 + 设备侧 booter 复算

```bash
cd /home/user/rt_5090_project/parallel
python3 cot_pin_work/fwsignature_frame_probe.py
mkdir -p /tmp/booter && cd /tmp/booter
for f in /usr/lib/firmware/nvidia/{ad102,ga102}/gsp/{booter_load,booter_unload,bootloader,scrubber}-570.144.bin.zst; do
  zstd -d -q -f "$f" -o "$(basename $f .zst)" 2>/dev/null; done
# 帧头常量搜索必须用字节精确匹配（bash 命令行不能携带 NUL，`grep $'\x01\x00…'` 会退化成单字节匹配）
python3 - <<'PY'
import glob,struct
for f in sorted(glob.glob('/tmp/booter/*')):
    d=open(f,'rb').read()
    print(f.split('/')[-1], len(d), 'hdr0x00020001=',d.count(struct.pack('<I',0x20001)),
          'u32_0x8C8=',d.count(struct.pack('<I',0x8c8)),
          'u32_0x200=',d.count(struct.pack('<I',0x200)))
PY
# => 四个 ACR/booter 镜像均为 hdr=0、0x8C8=0
```

### 9.4 设备侧二进制逐字节搜索（本文用的模式集）

```bash
cd /home/user/rt_5090_project
python3 - <<'PY'
import struct
F={'610rx':'power_governor_reverse/gsp61057_rx_full.bin',
   '570main':'ghidra_static/gsp_inner_570144_main.elf',
   '19f040a':'ghidra_static/gsp_inner_19f040_a.elf'}
P={'WPR_META_MAGIC':bytes.fromhex('b3601a3721ae3adc'),
   'HEAP_FREE_LIST':b'HEAPFREE','NVUCODES':b'NVUCODES',
   'fwsignature_':b'.fwsignature_','fwimage':b'.fwimage','fwversion':b'.fwversion'}
for n,p in F.items():
    d=open(p,'rb').read(); print(n,len(d))
    for k,v in P.items(): print('  ',k,d.count(v))
PY
```

---

## 10. 未闭合（UNKNOWN）清单

| # | 未闭合项 | 需要什么才能闭合 |
|---|---|---|
| U1 | 设备侧到底用 `payloadSize/codeSize/dataSize` 做了什么（分配？DMA？解压目标？）以及是否**先拷贝后验签** | FSP runtime 或 FMC monitor 的可读镜像（本地无） |
| U2 | 92-B desc 的三个 offset 在设备侧是否被二次校验（Booter/ACR 侧） | `booter_load-*.bin` 的 GB202 版本或 ACR 源码 |
| U3 | WPR2 meta 的 `verified` 判定包含哪些字段（只 magic/revision，还是也 check 三个 offset？） | 同上 |
| U4 | `.fwsignature_*` 帧的权威解析器与"槽 ↔ 熔丝版本"映射；host"取最后一个同名 section"语义是否与设备一致 | 同上 + 更多家族样本 |
| U5 | 设备侧 `message_queue_gsp.c` 是否与 `_cpu.c` 共享"检查在拷后"的顺序（决定 C3-1 的镜像方向是否成立） | 设备侧 RM 源码或对 GSP-RM 的定位（§8.2） |
| U6 | 未知/表外 ctrl 命令的 `paramsSize` 在哪些 handler 里被用于拷贝 | 闭源 RM 核心 handler 集合 |
| U7 | CC/inst-in-sys（`ConcatenatedFMC`）路径的认证材料来源 | 沿用既有 UNKNOWN（`SIGNATURE_VERIFIER_HUNT_FSP_20260925.md` §5.4） |

---

## 附录 A：本次新增/刷新的机械事实（便于被独立复核）

1. `gsp_inner_19f040_a.elf` 不是单个 ELF：内含 **3 个 RV64 ELF**（@0x0 / @0x106d000 / @0x111f000），
   且 `NV_FWSECLIC_*` 名池集中在 **@0xe2bdf2..@0xe2de13**（同段还有
   `NV_UDE_ERR_*`、`NV_UCODE_ERR_GFWIMAGEPARSER_*`、`NV_UCODE_ERR_GFWIMAGE_READ_*`、
   `NV_UCODE_ERR_GP_BUFFER_*`、`NV_COMPACTION_ERR_*`、`NV_PREOS_ERR_*`）。
   值得注意的存在性证据（说明设备侧**确实有**这些检查）：
   `FALCON_LOADER_BUFFER_READ_UNDERFLOW`、`FALCON_LOADER_INVALID_UCODE_DESCRIPTOR_INFO`、
   `BOOTLOADER_UCODE_HASH_MISMATCH`、`BOOTLOADER_INTERFACE_HASH_MISMATCH`、
   `MMU_WPR_UNALIGNED`、`CERT_HULK_DATA_BUFFER_TOO_SMALL`、
   `CERT21_FMT_FORMATTER_DATA_BLOCK_OVER_SIZE`、`BCRT2X_VDPA_INTBLK_BUFFER_SIZE_OVERFLOW`、
   `SECUREBOOT_INVALID_INCMD_STRUCT`、`GFWIMAGEPARSER_*`（8 项）。
2. `/usr/lib/firmware/nvidia/610.57.04/ucodes_ga10x.bin`（31,744 B）只有 19 个非零字节：
   `NVUCODES` magic（@0）+ `version=1`（@8）+ `numEntries=0x523`（@0xc）+ `fingerprint=0xa3251724509f926f`（@0x10），
   **其余全 0**（`ucodes_tu10x.bin` 同形，12,032 B，`numEntries=0x1f0`、`fingerprint=0x2bae986bab90198d`）。
   逐字段对应 `BINDATA_UCODES_BIN_HEADER`（`bin_data_pvt.h:85-117`）—— 这就是“外部 bindata 索引头”。
   另：同一 magic **与同一 fingerprint** 也出现在 `gsp_ga10x.bin` 的 **0x1039370**（落在 `.fwimage` 区间
   `[0x40,0x505b040)` **内部**），但那里的布局是 `magic || fingerprint(@+8) || 若干 8-B 记录`，
   与 `ucodes_*.bin` 的 header 布局**不同**（后者 magic→version→numEntries→fingerprint）；
   跟随的记录里出现 `0xdeaf0002/0xdeaf0005` 之类的 `0xdeaf` 前缀值（疑似 sentinel / external 条目索引，
   本次**未闭合**）⇒ 与 `bin_data_pvt.h` 注释“fingerprint 也嵌在对应 gsp.bin 里”相容。
   安全含义：外部 bindata 的“索引”是独立 host 文件，数据在 gsp 容器内；两者都落在
   `.fwimage` 覆盖范围内（非 host 运行期递交，而是随固件包递交）。
3. `GspRmBoot_GB202` 的 UCODE_IMAGE_PROD（290,816 B）与 signed gfw 容器（287,304 B）
   **几何相同、字节不同**；前者无 72-B 头、无 hash/sig/pkey（见 §3.5）。
4. 570.144 的 `bootloader-570.144.bin` 里 92-B desc 的 `version=5`，其后两字段
   （`bIsSmp`/`bIsPlicEnabled`）实测为**非 0 垃圾**（`0x5a85f079`/`0x519e1f43`）。

---

## 追加约束(用户口径,2026-09-25)

### 发现 2(消息队列 staging 越界)当前状态:**未复现候选,不上报、不宣称**

- 现状:仅为**静态代码阅读**得出的顺序问题(`message_queue_cpu.c:698` 取值 vs `:823-834` 检查),
  报告里那条"~192 KB 越界"量级**是推导,不是观测**;报告自身也列了自干扰等 caveat。
- 用户要求:**先能稳定复现再谈上报**;在此之前不得写成"漏洞"或对外宣称。
- 要成为可上报结论,最低需要:一个**由设备侧写入**的受控异常长度 + 观测到越界写入(或宿主内核报错),
  复现路径可在既有 harness 上做(`nvidia-live-recovery-lab` 下的 fake-engine / engine-recorder 系列,
  `vfio_production_lab/smoke-nogpu*`),而不是靠读代码推断。
- 在此之前,本文件的定位是"字段地图 + 待验证清单",不是漏洞报告。

### 实验纪律修正(针对 COT 那组)

1. **同一次运行内必须回读**:
   - `/proc/driver/nvidia/params` 的 `RegistryDwords:` 行(= 模块参数是否进去);
   - **RM 是否采纳**:同串带上 `RmDisableFspFuseErrorCheck=1`,看是否出现
     `FSP's fuse error detection status check during boot is disabled using the regkey.`
     —— 出现才证明 RM 解析了这条 dwords 串,同串里的 `RmDisableCotCmd=48` 才有资格被讨论。
2. 在此之前,任何"旋钮无效/有效"的结论都只能标注为**未验证**。

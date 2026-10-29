# 92-B `RM_RISCV_UCODE_DESC` 的偏移可滥用性 + FMC 公钥/哈希锚点定位（静态、只读）

日期：2026-09-25（Asia/Singapore）
范围：**纯本地只读静态审计**。本次没有访问 GPU / `/dev/nvidia*` / PCI/BAR/MMIO / debugfs，
没有 nvflash / updater / MODS / insmod / 刷写 / 重签 / 熔丝写入，没有联网。
所有结论只来自本机普通文件、本地源码文本与离线脚本复算。
本文件不含、也不提供任何出口管制相关内容（算力/授权/熔丝绕过/固件移植），不含任何设备侧操作步骤。

上游起点（本次只做增量，不重复推导）：
`parallel/PARSE_BEFORE_VERIFY_MAP_20260925.md`（§3.3/**C1-1/C1-2/C1-3**/§3.5/N3/N12）、
`parallel/COT_PUBKEY_PINNING_20260925.md`（E1/E3/E8/E13a/E13b/E14，工作目录 `parallel/cot_pin_work/`）。

**证据等级约定（本文严格遵守）**

| 标记 | 含义 |
|---|---|
| **B（字节级/代码级）** | 本机文件里的字节、源码行号、离线复算结果；可被独立复现 |
| **N（名称级）** | 只拿到"名字/字符串"，证明某个检查**存在于某处**，但**不能**证明其代码、算法与落点 |
| **S（结构性）** | 由接口/结构体/协议必然性推出的结论，无需代码 |
| **I（推断）** | 依赖命名或间接线索的猜测 —— **本文任何"可滥用"结论都不允许只靠 I 级** |

---

## 0. 结论（TL;DR）

### 0.1 三个问题的直接回答

**Q1（3 个偏移 + 相尺寸如何被 BootROM/FSP/SEC2 使用？有无校验？）**

* **host 侧：3 个偏移被当作无边界偏移消费，尺寸字段零消费 —— B 级确认（本次逐行复核）。**
  `kernel_gsp_gh100.c:744/751/758` 计算 `(fmcPhysAddr + offset) >> 8` 后写进
  `NV_PRISCV_RISCV_BCR_DMAADDR_{FMCCODE,FMCDATA,PKCPARAM}_LO/HI`；
  同样 3 个值在 `:340-342` 写进 WPR2 meta（`gsp_fw_wpr_meta.h:81-83`，注释明确写 **"Consumed by Booter for DMA"**）。
  `monitorCodeSize/monitorDataSize/manifestSize` 全树 **0 消费点**（B）。
* **更正起点文档一处**：有消费者的字段是 **4 个**，不是 3 个 —— `appVersion` 在
  `kernel_gsp_gh100.c:1000`（turing 同型 `kernel_gsp_tu102.c:588`）被写进
  `NV_PFALCON_FALCON_OS`。本机全部 desc 样本的 `appVersion` 都是 0。
* **host 侧没有任何边界/一致性校验（B）**：既没有 `offset < gspRmBootUcodeSize` 之类的比较，
  也没有 `version` 检查（v4 描述符的 3 个 offset 恒为 0 也会被照写），
  更没有 `offset_i == Σsize_j` 这个"生产者确实遵守"的不变量检查（见 §1.3）。
* **设备侧：本机无代码（B/负结果）**，但**有具名检查存在性证据（N）**：
  `UCODE_UNRECOGNIZED_DESCRIPTOR_P1/P2/P3`、`UCODE_DESCRIPTOR_V5_SANITY_FAILURE`、
  `FALCON_LOADER_INVALID_UCODE_DESCRIPTOR_INFO`、`BOOTLOADER_UCODE_HASH_MISMATCH`
  等错误名存在于 MODS 570.215 与三份设备侧 GSP-RM 的 FWSECLIC 名池里。
  ⇒ "设备侧是否复核这 3 个偏移"仍是 **UNKNOWN**（不能从名字升级为事实）。

**Q2（能否构造"BootROM 从宿主可控内存取固件/PKC 参数"？）**

* **"地址由 host 决定"这一步是结构性必然 + B 级证据，不需要推断**：
  BootROM 的 FMC code/data/PKCPARAM 三个 DMA 源地址 100% 由 host 计算（§1.1/§1.4），
  `DMAADDR_*_HI` 只有 12 bit ⇒ 有效地址空间 44 bit、且 `DMACFG.TARGET` 被 host 固定成
  `COHERENT_SYSMEM`（`dev_riscv_pri.h`，B 级）。
* **但"让 BootROM 用宿主可控的*未认证*字节启动"在本地方案内不能成立为事实**：
  拦截它的受信根**不在 host 代码里**（下面 Q3 的 N 级证据显示它是设备侧 FMC/GFW 自己的检查）。
  而且有**结构性反证**：host 有权完全不发 COT（`RmDisableCotCmd` 的 `GSPFMC` 位，
  `kern_fsp.c:148-150`/`kernel_sec2.c` 同型，沿用 E14），此时 host **没有递交任何公钥**，
  设备却仍必须启动 ⇒ **设备侧必然存在自己的锚点**（S）。
* 因此本节的产出是**分层结论**：可达的"地址选择"是事实（B/S）；
  "能不能靠它换掉被信任的固件/PKC 参数"= **UNKNOWN**，且所有本地反证都指向"会被设备侧拒绝"。

**Q3（公钥/哈希钉扎的设备侧证据）**

* **本次新增（N 级，MODS 570.215 字符串表）**：出现了**键清单（key manifest）+ prod/dev 键槽 +
  RSA 模数**这一族命名：
  `RSA_MODULUS_KEY_MANIFEST_MISMATCH_PROD` / `..._DEV`（0x88f6130 / 0x88f6158）、
  `INVALID_GSP_FMC_MODULUS`、`INVALID_GSP_FMC_KEY_PROD`、`INVALID_GSP_FMC_KEY_DEV`、
  `FMC_SIGNATURE_MISMATCH`、`NON_FMC_UCODE_NOT_ALLOWED`、`INVALID_GSP_FMC_VERSION`；
  以及 `ACR_ERROR_GFW_CHAIN_OF_TRUST_BROKEN`、`ACR_ERROR_INVALID_UCODE_FUSE`、
  `ACR_ERROR_GSP_FMC_AND_GSP_RM_MISMATCH`、`ACR_ERROR_GSP_RM_SR_WPR_META_VERIF_FAIL`、
  `GFW_FUSE_CHECK_FAILURE`，和一组 **GFW 信任等级**寄存器字段名
  `NV_PGC6_AON_SECURE_SCRATCH_GROUP_05_0_GFW_BOOT_VALIDATION_STATUS_{PASS_TRUSTED,
  PASS_UNTRUSTED,PASS_NO_TRUST,FAIL,IN_PROGRESS,NOT_STARTED}`。
* **形态判定**：把 E8（经典路径 host 不给键）+ E13b（`fuserework_debug_gfw_pub_key/hash/sig.bin`）
  + 本次新增的 `..._KEY_MANIFEST_..._{PROD,DEV}` 合起来读，
  最受支持的读法是：**设备侧锚点是"一份允许键（模数）的清单"，且区分 prod / dev 两个槽**。
  "整键 vs 仅 key-hash"与"熔丝 vs ROM"**仍未闭合**（本地无字节可以定这两问）。
* **明确负结果（B）**：`gb202/gb100/gh100-fmc-570.144.bin`、`gb202/gb100/ad102/ga102-bootloader-570.144.bin`、
  `ad102/ga102-{booter_load,booter_unload,scrubber}-570.144.bin`
  的解密后镜像体熵 **7.90–7.99**，`FUSE/PKC/ECDSA/RSA/SHA/MODULUS/MANIFEST/DMAADDR/PKCPARAM/DESCRIPTOR`
  等 30 个模式**全 0 命中** ⇒ 这些镜像里**没有可静态阅读的熔丝读点、hash/key 比对循环或 PKC 入口**（§3.2）；
  三份设备侧 GSP-RM 二进制里 `FMC_`/`GSP_FMC`/`booter`/`RSA_MODULUS` 亦 **0 命中**（§4）。

### 0.2 字段级置信度总表

| # | 判定 | 等级 | 最硬的一条证据 |
|---|---|---|---|
| D1 | 3 个 offset 被当无边界偏移用于 3 个 BCR DMA 源地址 | **B** | `kernel_gsp_gh100.c:744/751/758` + `dev_riscv_pri.h`（LO 31:0 / HI 11:0） |
| D2 | 同 3 个值进入 WPR2 meta，供 Booter DMA | **B** | `:340-342`；`gsp_fw_wpr_meta.h:81-83` 注释 "Consumed by Booter for DMA" |
| D3 | 3 个 size 字段 host 零消费 | **B（负）** | 全树 `grep` 只有结构体定义命中 |
| D4 | 4 个字段有消费者（含 `appVersion`→`FALCON_OS`） | **B** | `:1000`；`kernel_gsp_tu102.c:588` |
| D5 | desc 与 blob 存在生产者侧几何不变量，且 24 个本地样本 0 违例 | **B** | §1.3 矩阵 |
| D6 | host 侧无任何 offset/size 边界校验、无 version 检查 | **B（负）** | §1.1 grep + 逐行阅读 |
| D6b | desc 真实长度 = `hdr[0x10]-0x18`（v4=76 B / v5=84 B），消费者固定读 92 B | **B** | §1.3；被误读字节 = payload 前 8/16 B（24 样本） |
| D7 | 设备侧存在"描述符 sanity / hash / 键 / 熔丝"类检查 | **N** | FWSECLIC 名池 + MODS 状态名表 |
| D8 | 设备侧钉扎形态 = 键（模数）清单 + prod/dev 槽 | **N**（偏正） | §3.1 |
| D9 | 锚点物理落点（熔丝 / ROM / ucode 常量） | **UNKNOWN** | 本地无边字节可判（§3.3） |
| D10 | FMC/booter 镜像内可见熔丝读点/PKC 入口 | **B（负）** | 密文，30 模式 0 命中 |
| D11 | "自签 FMC 可被接受" | **不可证，且有反证（N）** | §2.4 |

---

## 1. Q1：3 个偏移 + 相尺寸的消费图（host 有代码，设备侧无代码）

### 1.1 host 侧消费点（B 级，逐行 + grep）

工作树：`/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src`
（与 `/usr/src/nvidia-610.57.04/src` 在相关文件上逐字节相同，沿用起点文档 §9.1 的复核）。

```
nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c:740   RM_RISCV_UCODE_DESC *pRiscvDesc = pKernelGsp->pGspRmBootUcodeDesc;
nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c:741   RmPhysAddr fmcPhysAddr = memdescGetPhysAddr(pKernelGsp->pGspRmBootUcodeMemdesc, AT_GPU, 0);
:744  physAddr = (fmcPhysAddr + pRiscvDesc->monitorCodeOffset) >> RISCV_BR_ADDR_ALIGNMENT;   → BCR_DMAADDR_FMCCODE_LO/HI
:751  physAddr = (fmcPhysAddr + pRiscvDesc->monitorDataOffset) >> RISCV_BR_ADDR_ALIGNMENT;   → BCR_DMAADDR_FMCDATA_LO/HI
:758  physAddr = (fmcPhysAddr + pRiscvDesc->manifestOffset)   >> RISCV_BR_ADDR_ALIGNMENT;   → BCR_DMAADDR_PKCPARAM_LO/HI
:764  target = NV_PRISCV_RISCV_BCR_DMACFG_TARGET_COHERENT_SYSMEM;   // 固定成 coherent sysmem
:768  kflcnRiscvRegWrite_HAL(... NV_PRISCV_RISCV_BCR_DMACFG, ... LOCK=LOCKED ...);
:770  kflcnRiscvProgramBcr_HAL(pGpu, pKernelFalcon, NV_TRUE);
:773  kflcnRiscvRegWrite_HAL(... NV_PRISCV_RISCV_CPUCTL, ... STARTCPU=TRUE ...);
```

`RISCV_BR_ADDR_ALIGNMENT = 8`（`kernel_gsp_gh100.c:51`，`kernel_gsp_ga102.c:40`）⇒ 地址按 256 B 对齐。

调用点（"何时发生"）：`kgspBootstrap_GH100()`（`:852-899`）在
`pKernelFsp != NULL` 时走 FSP COT 路径（`:889`），
`pKernelSec2 != NULL && KSEC2_BOOT_GSPFMC` 时走 SEC2（`:894`），
**两者都不满足才落到 `_kgspBootstrapGspFmc_GH100`（`:898`）** —— 即 3 个 BCR 寄存器路径是
**fallback**；GB202 默认走 FSP（与 `PARSE_BEFORE_VERIFY_MAP` §5.3 的"GB202 NVDM 端点是 FSP"一致）。
无论走哪条，"3 个 offset 进 WPR2 meta"都在更早的 `kgspPopulateWprMeta_HAL`（`kernel_gsp.c:4814`）发生（B）。

**"无检查"的机械证据（B，可复算）**

```bash
# 只有 14 处命中：3 处 WPR2 meta + 3 处 BCR + turing 同型 6 处 + 结构与 ls10.h 副本
grep -rn "monitorCodeOffset\|monitorDataOffset\|manifestOffset\|monitorCodeSize\|monitorDataSize\|manifestSize\|bootloaderCodeOffset\|bootloaderDataOffset\|bootloaderManifestOffset" $SRC
# 所有 pRiscvDesc-> 用法（全部消费者）
grep -rn "pRiscvDesc->" $SRC --include=*.c      # → gh100:340/341/342/744/751/758/1000, tu102:588/872/873/874, tu102(falcon):484
```

* `kernel_gsp_gh100.c:320` 只查 `pRiscvDesc != NULL`；
  其后的 3 个赋值**没有任何** `offset < size` / `offset + size <= imageSize` 比较。
* 3 个 **size 字段**在 host 侧连读都没读过（D3）。
* 因此 "offset+size 落在 image 之内" 这条不变量在 host 侧**既没有代码、也没有设备侧输入**（只有 struct 里存在）。
* `version` 也没被读 ⇒ **v4 描述符（3 个 offset 恒 0）与 v6 不会被区分**（D6，见 §1.3 矩阵里 tu102/ga100 全 0）。

### 1.2 desc 从哪来（B 级：BINDATA archive/label 归属）

```
kgspPrepareBootBinaryImage_IMPL        kernel_gsp.c:5562-5634
  :5582  kgspGetGspRmBootUcodeStorage_HAL(...)      // 选 archive
  :5585  bufSize = bindataGetBufferSize(pBinStorageImage);
  :5586  bufSizeAligned = NV_ALIGN_UP(bufSize, 0x1000);
  :5613  pKernelGsp->gspRmBootUcodeSize = bufSize;   // ← 唯一的 size 来源，但只进 WPR2 meta
  :5625  bindataStorageAcquireData(pBinStorageDesc, &pDesc);  // ← 92 B desc，直接指针，无长度校验
kgspGetGspRmBootUcodeStorage_GH100     kernel_gsp_gh100.c:1052-1082
  CC 开 → ConcatenatedFMCDesc + ConcatenatedFMC 两个 archive（:1064-1075）；否则 → _GA102（:1081）
kgspGetGspRmBootUcodeStorage_GA102      kernel_gsp_ga102.c:80-100   // label: UCODE_IMAGE_{PROD,DBG} / UCODE_DESC_{PROD,DBG}
```

* `GspRmBoot_GB202` archive 只有 `IMAGE`+`DESC` 两个 label（起点文档 §9.2/N12，本次复核一致）⇒
  **92 B desc 没有 hash/sig 伴生 label**，`bindataStorageAcquireData` 也不校验长度（B）。
* `UCODE_DESC_DBG` 在 `ConcatenatedFMCDesc_*` 里**不存在**（该 archive 只有 `UCODE_DESC_PROD`，
  `g_bindata_kgspGetBinArchiveConcatenatedFMCDesc_GB202.c:31-35`）⇒ CC+debug 组合下 `Desc` storage
  取不到 DBG 变量（**本次未追这条的返回值语义**，列为 UNKNOWN，见 §6-U3）。

### 1.3 92-B desc：3 个样本的 annotate hexdump + 24 样本几何矩阵（B 级）

**样本 A：GB202 610 prod，非 CC 路径**（`g_gsp_gb20x_dyn_prd_desc.bin`，sha256 `6f4ecedadb0a7da0…`）

```
+0x00  06 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00   version=6, 其余全 0
+0x10  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
+0x20  00 00 00 00 00 0a 00 00 00 0a 00 00 00 e8 00 00   manifestOffset=0 manifestSize=0xA00 dataOffset=0xA00 dataSize=0xE800
+0x30  00 f2 00 00 00 70 03 00 01 00 00 00 00 00 00 00   codeOffset=0xF200 codeSize=0x37000 bIsMonitorEnabled=1
+0x40  00 …(全 0，含 fbReservedSize/bSignedAsCode/bIsSmp/bIsPlicEnabled=0)
```

**样本 B：GB202 610 CC（`g_gsp_gb20x_dyn_spdm_prd_desc.bin`，sha256 `bbdabd5a7c833652…`）**

```
+0x20  … manifestSize=0xA00  dataOffset=0xA00 dataSize=0xA900
+0x30  codeOffset=0xB300     codeSize=0x33900   bIsMonitorEnabled=1
```

**样本 C：`/lib/firmware/nvidia/gb202/gsp/bootloader-570.144.bin` 的 inline desc @0x18（v5）**

```
file: de10 0000 0100 0000 0011 0300 1800 0000 6c00 0000 0010 0300 0500 0000
      magic=0x10de  ver=1  fwSize=0x31100  hdrSize=0x18  payloadStart=0x6C  ?0x31000  descVer=5
desc@0x18: version=5, manifestOffset=0/manifestSize=0xA00,
      dataOffset=0xA00/dataSize=0xA800, codeOffset=0xB200/codeSize=0x25800,
      bIsMonitorEnabled=1, 之后：bIsSmp=0x5a85f079, bIsPlicEnabled=0x519e1f43  ← 见下方 8-B 越读
xxd @0x60: 00…00  79 f0 85 5a  43 1f 9e 51  2b 9c 0a bd  5e 2b d1 24 …
                    └── 0x6C 起就是密文 payload（两块 "垃圾" 值就是 payload 的前 8 B）
payload = [0x6C, 0x6C+0x30A00)，最后一个非零字节 0x30A6B == 0x6B + 0x30A00
其后全 0 至文件尾 0x3106C（文件余量 0x3106C-0x30A6C = 1528 B）
```

**8 字节越读的字节级解释（B，本次新得）**：头字段 `hdr[0x10] = 0x6C` 就是 **payload 起始**，
而下发把 desc 当成 **92 B** 读（到 0x74）⇒ **最后 8 B（`bIsSmp`/`bIsPlicEnabled`）读到的是 payload 密文**。
GB202 的 v5 样本实测正是这样（`0x5a85f079`/`0x519e1f43` = payload 前 8 B；逐家族值见下表）。
⇒ 起点文档的 **C1-3（"v5 尾部字段是垃圾"）由此从"现象"升级为"机制"**：
**v5 desc 实际是 84 B（21 字段）**，v6 结构多出的 8 B 落在 payload 里。
范围限定：这 8 B 只被读、且这两个字段在 host 侧**没有任何消费者**（D3），
本机**也没有任何代码消费该文件**（F8）⇒ 这是**结构性观察**，不是已触发的缺陷。

**偏移基准的字节级验证（B，本次新得）**：desc 的偏移基准是 **payload 起点**。用 ad102/ga102 做判定：

```
ad102-bootloader:  desc.bootloaderOffset=0x8000 → 0x6C+0x8000 = 0x806C
                  实测尾部唯一结构化 blob 起点 = 0x806C  ← 逐字节吻合
                  desc.bootloaderParamOffset=0x8880 → 0x88EC，paramSize=0x10
                  实测最后一个非零字节 = 0x88F9 ∈ [0x88EC,0x88FC)  ← 吻合
ga102-bootloader:  desc.bootloaderOffset=0x5000 → 0x6C+0x5000 = 0x506C = 实测 blob 起点
```

（AD102/GA102 的两段尾部 blob 的 256-B 熵剖面在 30 个块上**逐块一致**：`0.25, 5.77, 6.10, 5.72, 5.82, 4.64,
0.71, 0.69, 1.27, 1.88` ⇒ 同一份小 blob 的两个副本，B。）
GB202/GB100/GH100 的 `bootloaderOffset=0`（无内层 bootloader，§1.3 矩阵，B）。

**生产者侧几何不变量（本机 24 个 `bootloader-570.144.bin` 全样本实测，0 违例）**

```
inv1: monitorDataOffset == manifestSize
inv2: monitorCodeOffset == manifestSize + monitorDataSize
inv3: monitorCodeOffset + monitorCodeSize == 描述的程序长度（且 ≤ 文件内 payload 长度）
```

| chip(s) | 文件长 | desc ver | manifest | data | code | code_end | inv1/2/3 | desc sha256(12) |
|---|---|---|---|---|---|---|---|---|
| gb202/gb203/gb205/gb206/gb207 | 200,812 | 5 | 0xA00 | 0xA800 | 0x25800 | 0x30A00 | OK | `609e3f357637` |
| gb100/gb102 | 200,812 | 5 | 0xA00 | 0xA700 | 0x25200 | 0x30300 | OK | `a2011f81e892` |
| gh100 | 168,044 | 5 | 0xA00 | 0xA700 | 0x1D500 | 0x28600 | OK | `d1949df2fbe9` |
| ad102…ad107 | 36,972 | 5 | 0x800 | 0x4000 | 0x2900 | 0x7100 | OK | `04c8ce7771ad` |
| ga102…ga107 | 24,684 | 5 | 0x800 | 0x1000 | 0x2900 | 0x4100 | OK | `3f83850ae6ed` |
| ga100/tu102/tu104/tu106/tu116/tu117 | 4,196 | **4** | 0 | 0 | 0 | 0 | OK(退化) | `67dbcc8d6be1` |

**desc 实际长度 ≠ 被读取长度（B，24 样本实测）**：头字段 `hdr[0x10]` = payload 起点，
且 `desc 真实长度 = hdr[0x10] - 0x18`：

| 家族 | `hdr[0x10]` | 推出的 desc 长度 | 字段数 | v6 读法多读的字节 | 那些字节是什么 |
|---|---|---|---|---|---|
| ga100/tu102…tu117（descVer=**4**） | 0x64 | **76 B** | 19 | **16** | payload 前 16 B |
| ad102…gb207/gh100（descVer=**5**） | 0x6C | **84 B** | 21 | **8** | payload 前 8 B |

被误读成 `bIsSmp/bIsPlicEnabled` 的 8 B 实测（每家族一致、四族不同）：
`gb202=79f0855a431f9e51`、`gb100=fb16d784c643816c`、`gh100=af46450250df6aa8`、`ad102=f5f33a338e7d1aab`、`ga102=8aaaf9341ad74bba`。
⇒ 起点文档 C1-3 的"v5 尾部是垃圾"**得到机制解释**；同时得到一条**契约缺口**：
92-B 结构自身不声明长度，而消费者固定按 92 B 读。
**范围限定**：本机没有任何代码消费这些文件（F8），所以这是**结构性缺陷（字段级）**而非已触发行为；
且在 host 里这两个字段**无消费者**（D3），后果仅为"读出与 payload 重叠的 8/16 B"。

**与 blob 的边界实测（B）**

* `GspRmBoot_GB202` 驱动 blob 290,816 B（`0x47000`）：**最后一个非零字节在 0x461FF**，
  `code_end = 0x46200` 之后 **0 个非零字节** ⇒ 描述范围恰好等于"有意义内容"长度。
* `ConcatenatedFMC_GB202` blob 503,808 B（`0x7B000`）里的逐字节事实（本次实扫）：
  `ConcatFMC[0xB300 : 0xB300+0x33900]` 与 `fmc_cc_prod_gb202` 容器 payload（= `image` section 去 72-B 头）
  的 **前 0x33900 字节逐字节相同**（0 差异；0x33900 = 211,200 = desc 的 `monitorCodeSize`
  = 容器 header 的 `codeSize`）；而 CC payload 的尾部 `[0x33900, 0x3EC00)` 在同一位置
  **有 45,633 B 不同**（同几何、不同字节）。
  同时：desc 的三段几何（`0/0xA00/0xB300`，尺寸 `0xA00/0xA900/0x33900`）与
  `fmc_cc_prod_gb202` 容器 header 的几何（`0x48` 之后的 manifest/data/code）**完全同构**
  （差别仅在 desc 从 payload 起算、容器从文件起算 +0x48）。
  ⇒ **B 级可写的话**：desc 的 `monitorCodeOffset` 确实指到了一份**真实存在、
  与已签名容器内容字节相同（至少 0x33900 B）**的内嵌程序；
  **不能**写成"内嵌了整份未签名的第二个固件"（尾部不一致，原因未知，列 UNKNOWN）。
* `/lib/firmware` 的 `gb202-bootloader-570.144.bin` 的 inline desc 与同版本 `gb202-fmc-570.144.bin`
  （ELF32 容器）**几何完全一致**：desc 的 `dataSize/codeSize` == 容器的 `dataSize/codeSize`，
  `code_end` == 容器 `payloadSize=0x30A00`；而 desc 的 `dataOffset=0xA00` 相对容器 header 内的
  `dataStart=0x48+0xA00` **差 0x48** ⇒ **desc 的偏移是"payload 相对"**：
  在 signed 容器里 = 去掉 72 B header 之后；在 falcon framing 里 = 从 `hdr[0x10]=0x6C` 起（上一小节逐字节验证）。
  但两份密文**不是同一份字节**（GB202：容器 payload 与 bootloader payload 198,396/199,168 字节不同，
  sha256 `5372b86e…` vs `73ef5e58…`）⇒ 同几何、不同密文/不同交付实例（B）。

### 1.4 硬件侧地址空间（B）

`common/inc/swref/published/hopper/gh100/dev_riscv_pri.h`（本次直读）：

```
NV_PRISCV_RISCV_BCR_DMAADDR_PKCPARAM_LO  0x670  VAL 31:0
NV_PRISCV_RISCV_BCR_DMAADDR_PKCPARAM_HI  0x674  VAL 11:0      ← 12 bit
NV_PRISCV_RISCV_BCR_DMAADDR_FMCCODE_LO   0x678  ... HI        0x67c
NV_PRISCV_RISCV_BCR_DMAADDR_FMCDATA_LO   0x680  ... HI        0x684
NV_PRISCV_RISCV_BCR_DMACFG               0x66c  TARGET 1:0 = {LOCAL_FB=0, COHERENT_SYSMEM=1, NONCOHERENT_SYSMEM=2, IO=3}; LOCK 31:31
```

⇒ 写入的是 **44 bit 物理地址**（host 侧还右移 8），target 由 host 固定为 coherent sysmem。
`monitorCodeOffset/monitorDataOffset/manifestOffset` 是 **u32**，`fmcPhysAddr + offset` 在 u64 域相加，
**高位进位会落进 HI 的 12 bit**（host 不做任何检查，B）。

### 1.5 设备侧消费者：只有具名证据（N），没有代码（B 负）

* 三份设备侧 RV64 二进制里**没有任何 FMC/booter 字样**（`FMC_`/`GSP_FMC`/`booter` 全 0 命中，§4）。
* 但 FWSECLIC 名池（90 项，起始 `gsp61057_rx_full.bin@0xe300f8`，见
  `parallel/cot_pin_work/FWSECLIC_ERR_CODE_names_61057.txt`）里与"描述符/哈希/引导器"直接相关的是：

```
e31318 NV_FWSECLIC_ERR_CODE_BOOTLOADER_UCODE_HASH_MISMATCH
e31350 NV_FWSECLIC_ERR_CODE_BOOTLOADER_INTERFACE_HASH_MISMATCH
e31388 NV_FWSECLIC_ERR_CODE_BOOTLOADER_INTERFACE_NOT_FOUND
e312e8 NV_FWSECLIC_ERR_CODE_BOOTLOADER_FALCON_INVALID
e313e8 NV_FWSECLIC_ERR_CODE_FALCON_LOADER_BUFFER_READ_UNDERFLOW
e31458 NV_FWSECLIC_ERR_CODE_FALCON_LOADER_INVALID_UCODE_DESCRIPTOR_INFO
e314a0 NV_FWSECLIC_ERR_CODE_FALCON_LOADER_INVALID_INTERFACE_DESCRIPTOR_INFO
e313c0 NV_FWSECLIC_ERR_CODE_MMU_WPR_UNALIGNED
e31130 NV_FWSECLIC_ERR_CODE_SECUREBOOT_INVALID_INCMD_STRUCT
NV_UCODE_ERR_CODE_GFWIMAGEPARSER_{INVALID_FW_IMAGE, INVALID_ROM_SIGN, INVALID_DATA_STRUCT_SIGN,
      CERT_BLOCK_NOT_PRESENT, INVALID_EXTIMG_DATA, IFR_INVALID_SIZE, INVALID_IFR_IMAGE, INFOROM_BLOCK_NOT_PRESENT}
NV_UCODE_ERR_GFWIMAGE_READ_{DMA_DMEM_OFFSET_NOT_ALIGNED, INVALID_EEPROM_BASE_OFFSET, INVALID_MEDIA_TYPE, ...}
NV_UCODE_ERR_GP_BUFFER_ALLOCATION_{INVALID_SIZE, TOTAL_SIZE_MISMATCH}
```

**读法（明确等级）**：这些名字证明**设备侧确实存在**"对某个 ucode 描述符做 sanity"
（`FALCON_LOADER_INVALID_UCODE_DESCRIPTOR_INFO`）与"bootloader 对 ucode 做 hash 比对"
（`BOOTLOADER_UCODE_HASH_MISMATCH`）的**具名检查**（N）。
但**不能**据此说"它检查了这 3 个 offset"：没有代码、没有数字码、没有交叉引用（D7，UNKNOWN）。

---

## 2. Q2：能否构造"BootROM 从宿主可控内存取固件/PKC 参数"

### 2.1 需要的能力（威胁模型，S）

| 能力 | 是否本地可得 | 说明 |
|---|---|---|
| 让 `fmcPhysAddr` 指向宿主缓冲 | 设计如此 | `memdescGetPhysAddr(pGspRmBootUcodeMemdesc)`，合法 |
| 改 3 个 offset 的值 | 需替换**驱动模块 bindata**（或 MODS file-override） | desc 是编译进模块的数据；不是运行期用户输入（起点文档 §7 口径 (b)） |
| 让 FMC code/data/PKCPARAM 落在别处 | 同上（offset 是唯一来源） | 无边界检查（D1/D6） |
| 递交自己的 (image,hash,sig,pkey) 四元组 | 运行期可以（COT payload） | 但设备侧要过键检查（§3） |

### 2.2 分层结论

**(a) 事实（B/S）**：BootROM 用的 3 个源地址完全由 host 计算、
目标空间是 44-bit coherent sysmem、**没有任何一处 host 侧校验**；
`manifestOffset` 决定"PKC 参数从哪里读"。
若偏移被改成落在这块 sysmem 之外，host 不会报错，DMA 会照发。

**(b) 事实（B）**：**desc 本身没有被认证**——
`GspRmBoot_GB202` archive 只有 `IMAGE`+`DESC`；没有 desc 的 hash/sig 伴生 label；
`bindataStorageAcquireData` 只返回指针。同一 desc 还被用于两条路径的地址计算（§1.2）。

**(c) 事实（B，本报告新做）**：在 **有 72-B 头的 signed 容器 framing** 下，
`manifest + data + code` **整段在签名覆盖范围内**：
本机复算 GB202 prod `sha384(image)==UCODE_HASH`（48 B，逐字节相等），
并用 97-B P-384 点 + 96-B (r‖s) **离线验证 ECDSA P-384/SHA-384 通过（VALID）**。
⇒ 在**容器 framing**里，PKC 参数区不是"未认证字节"。

**(d) 推断/未知（I/UNKNOWN）**：在 **GspRmBoot 无头 framing**（驱动 bindata，`IMAGE` 无 hash label）里，
这条"hash 覆盖 manifest"的关系**不能由本地文件证明**——它的认证材料要么来自设备侧自身，
要么来自 FSP/SEC2 的 COT 三元组。⇒ "把 PKCPARAM 指到宿主内存能否生效" 取决于这条，
**本地不可判**。

### 2.3 受信根在哪里拦（证据 / 反证）

| 拦截点 | 证据 | 等级 |
|---|---|---|
| FMC 自身的签名/哈希/键检查 | `FMC_SIGNATURE_MISMATCH`、`INVALID_GSP_FMC_MODULUS`、`INVALID_GSP_FMC_KEY_{PROD,DEV}`、`NON_FMC_UCODE_NOT_ALLOWED`（MODS 状态名表） | N |
| 键（模数）与"清单"比对，且分 prod/dev 槽 | `RSA_MODULUS_KEY_MANIFEST_MISMATCH_{PROD,DEV}` | N |
| 熔丝参与的键/版本策略 | `ACR_ERROR_INVALID_UCODE_FUSE`；起点文档 E4：`NV_FUSE_ZB_OPT_SECURE_GSP_DEBUG_DIS(0x74C)` 选 prod/debug 材料、`OPT_FPF_GSP_UCODE1_VERSION(0x41C0)` 选签名槽 | N+B（熔丝字段本身是已发布 swref，B） |
| GFW 级链式信任 + 熔丝检查 + 信任等级寄存器 | `ACR_ERROR_GFW_CHAIN_OF_TRUST_BROKEN`（带 `NVRM: ACR FAILED: Error:` 前缀）、`GFW_FUSE_CHECK_FAILURE`、`NV_PGC6_AON_SECURE_SCRATCH_GROUP_05_0_GFW_BOOT_VALIDATION_STATUS_{PASS_TRUSTED,PASS_UNTRUSTED,PASS_NO_TRUST,FAIL}` | N |
| FMC 与 GSP-RM 配对校验 | `ACR_ERROR_GSP_FMC_AND_GSP_RM_MISMATCH`、`ACR_ERROR_GSP_RM_SR_WPR_META_VERIF_FAIL` | N |
| **host 可以完全不发 COT（反证：锚点必须在设备侧）** | `RmDisableCotCmd` 的 `GSPFMC` 位（`kern_fsp.c:148-150` → `PDB_PROP_KFSP_DISABLE_GSPFMC`；`kernel_sec2.c` 同型，沿用 E14） | **B** |

**因此（重要，避免误读）**：
`_kgspBootstrapGspFmc_GH100` 这条路（3 个 BCR 寄存器）**是 fallback**，
而 FSP 默认路径把同样 3 个未校验偏移塞进 WPR2 meta——**两条路的偏移来源同一个未认证的 92 B 结构**。
所谓"受信根"**不在 host 侧任何代码里**；本地能证的只是"设备侧必然有锚点"（§2.3 最后一行 + E8），
而**锚点的读取者与形态在本地不可读**（§3.2 的密文负结果）。

### 2.4 明确禁止的写法（本次拒绝下的结论）

* ❌ "可以自签 FMC 让设备接受" —— 无字节级证据，且有 `..._KEY_MANIFEST_...`/`INVALID_GSP_FMC_KEY_*` 族反证（N）。
* ❌ "偏移越界会导致 BootROM 执行任意宿主内存" —— host 侧无校验是事实（B），
  但**没有**任何本地证据说明越界后设备侧不会做 sanity/键校验；
  把它写成"可执行任意代码"属于把 I 级推断当事实（§1.5 明确为 UNKNOWN）。
* ❌ "钉扎在熔丝 / 在 ROM" —— 两问本地都不可判（§3.3）。

---

## 3. Q3：公钥钉扎的设备侧证据（新增 + 复核）

### 3.1 本次新增（N 级，MODS 570.215 字符串表，带文件偏移）

来源：`parallel/cot_pin_work/off_strings_mods570215.txt`（MODS 570.215，基址 0x400000）。

```
# (A) GSP-FMC 签名/键/模数/版本 —— 同一张状态名表内（0x8d65b0d..0x8d66f20）
8d65b0d  FMC_INFO_ERROR
8d6645d  FMC_SIGNATURE_MISMATCH
8d6663c  INVALID_GSP_FMC_VERSION
8d667bb  NON_FMC_UCODE_NOT_ALLOWED
8d668c3  INVALID_GSP_FMC_MODULUS          ← 对"模数"的显式校验
8d66e9e  INVALID_GSP_FMC_KEY_PROD         ← prod 键槽
8d66eb7  INVALID_GSP_FMC_KEY_DEV          ← dev 键槽
8d66e6b  DEV_KEY_ALREADY_ALLOWED / 8d66e83 DEV_KEY_ALREADY_DISALLOWED
（同表邻域还有 INVALID_DEVINIT_FMC_*、INVALID_HULK_FMC_*、INVALID_MINION_FMC_*、INVALID_FBFALCON_FMC_VERSION）

# (B) "键清单"—— 与 ucode 描述符 sanity 相邻（0x88f6018..0x88f6158）
88f6018  UCODE_UNRECOGNIZED_DESCRIPTOR_P1 / P2 / P3
88f6090  UCODE_DESCRIPTOR_V5_SANITY_FAILURE
88f6108  FUSING_PAYLOAD_INVALID_ENUM_INDEX
88f6130  RSA_MODULUS_KEY_MANIFEST_MISMATCH_PROD   ← "RSA 模数 键-清单 不匹配（prod）"
88f6158  RSA_MODULUS_KEY_MANIFEST_MISMATCH_DEV    ← （dev）
88f5e10… SWITCH_RTOS/BOOTEXIT/FUSEBLOW/…_CODE_REGION_UNALIGNED（同表的"区域未对齐"族）

# (C) ACR（设备侧引导 ucode）报错名 —— host 打印前缀证明这是 ACR 报上来的
8c096c8  NVRM: ACR FAILED: Error: ACR_ERROR_GFW_CHAIN_OF_TRUST_BROKEN
8c08da8  NVRM: ACR FAILED: Error: ACR_ERROR_INVALID_UCODE_FUSE
8c09cf8  NVRM: ACR FAILED: Error: ACR_ERROR_GSP_FMC_AND_GSP_RM_MISMATCH
8c0a2b0  NVRM: ACR FAILED: Error: ACR_ERROR_GSP_RM_SR_WPR_META_VERIF_FAIL
（ACR_ERROR_* 全表另有 ACR_ERROR_MEMCMP_FAILED / ACR_ERROR_CMC_SR_SIGVERIF_FAIL /
  ACR_ERROR_LS_UCODE_IS_NOT_ENCRYPTED / ACR_ERROR_GLOBAL_MEM_LOCK_FUSE_FOUND_UNSET 等 60+ 项）

# (D) GFW 级：熔丝检查 + 信任等级
8d245e0  GFW_BOOT_FAILURE
8d245f1  GFW_FUSE_CHECK_FAILURE
NV_PGC6_AON_SECURE_SCRATCH_GROUP_05_0_GFW_BOOT_VALIDATION_STATUS_{NOT_STARTED,IN_PROGRESS,
        PASS_NO_TRUST,PASS_TRUSTED,PASS_UNTRUSTED,FAIL}
NV_PGC6_AON_SECURE_SCRATCH_GROUP_05_0_GFW_BOOT_VALIDATION_DETAILS{,_INIT}
NV_PGC6_AON_SECURE_SCRATCH_GROUP_05_0_GFW_BOOT_PROGRESS_{STARTED,COMPLETED,
        BOOT_VALIDATION_COMPLETED,FB_SCRUB_STARTED,FBFALCON_BOOT_TRAINING_COMPLETED,…}
CHAIN_OF_TRUST_BOOT_NOT_COMPLETE / CHAIN_OF_TRUST_INVALID_PAYLOAD / CHAIN_OF_TRUST_FW_SIZE_TOO_LARGE
```

**与已发布 swref 的对应（B）**：
`common/inc/swref/published/ampere/ga102/dev_gc6_island_addendum.h:30-32` 给出
`NV_PGC6_AON_SECURE_SCRATCH_GROUP_05_0_GFW_BOOT = NV_PGC6_AON_SECURE_SCRATCH_GROUP_05(0)`
与 `..._GFW_BOOT_PROGRESS`（`7:0`，`COMPLETED=0x000000FF`），
寄存器地址由 `dev_gc6_island.h:33` 定为 `0x00118234 + i*4`（**B**）。
MODS 里的 `..._GFW_BOOT_VALIDATION_STATUS_*` 字段名**不在**开源 published swref 里（**N**）。

**读法（严格分级）**：
`GFW_BOOT_VALIDATION_STATUS` 存在 `PASS_TRUSTED / PASS_UNTRUSTED / PASS_NO_TRUST / FAIL` 四态 ⇒
设备（PMC/AON 域）确实在 GFW 引导时**给出一个"信任等级"，且允许"验证通过但不可信"这一态**（N/S）。
这**不能**推出"验证可被绕过"：`PASS_NO_TRUST/PASS_UNTRUSTED` 更可能对应 debug/技能 SKU；
但它说明**信任判定是设备侧状态机的结果**，而不是 host 递交的布尔值（S）。

### 3.2 字节级复核：FMC/booter 镜像里**什么都读不到**（B，明确负结果）

`/tmp/descabuse/fw/`（本次工作的解压副本，路径与哈希见表）：

| 文件 | 长度 | 16-K 块熵（前 12 块） | 30 个模式命中 |
|---|---:|---|---|
| `gb202-bootloader-570.144.bin` | 200,812 | 7.973…7.990（尾部零填充） | 仅 2-B 巧合 `0x074c`×1（噪声） |
| `gb100-bootloader-570.144.bin` | 200,812 | 同上 | 同上 |
| `gb202-fmc-570.144.bin` | 199,820 | 7.963…7.990 | 0（除 ELF section 名 `.shstrtab/signature/publickey`） |
| `gb100-fmc-570.144.bin` | 198,028 | 7.960…7.989 | 0 |
| `gh100-fmc-570.144.bin` | 166,600 | 7.963…7.990 | 0 |
| `ad102-bootloader-570.144.bin` | 36,972 | 7.985 / 6.916 / 2.823 | 0 |
| `ad102-booter_load-570.144.bin` | 57,720 | — | 0（`RSA` 1 次为随机噪声） |
| `ga102-booter_load-570.144.bin` | 61,304 | — | 0 |
| `ad102/ga102-booter_unload`、`ga102-bootloader`、`ad102-scrubber` | 41,592 / 41,080 / 24,684 / 8,312 | — | 0 |

模式集（大小写变体）：`FUSE/Fuse/fuse/ZB_/OTP/SECDED/PKC/ECDSA/RSA/SHA/secp384/PUBKEY/PUBLICKEY/MODULUS/
MANIFEST/manifest/DMAADDR/PKCPARAM/FMCCODE/FMCDATA/DESCRIPTOR/CHAIN/VERIFY/SIGNATURE/CERT/ROM/BOOT`
+ 熔丝地址常量 `0x41C0/0x4140/0x3814/0x820000` + P-384/P-256 曲线常数 + `0x10de`。

**结论（B）**：这些镜像体是**密文**（与起点文档 E9 一致，本次把范围扩到 gb202/gb100/ad102/ga102 的
bootloader/booter 与 gh100/gb100/gb202 的 fmc）⇒
"熔丝读点（ZB/RB 熔丝地址）、hash/key 比对循环、PKC 入口" **在本地静态不可得**，
这是**负结果而非"不存在"**。唯一可读的结构是：`bootloader-570.144.bin` 的
**明文头 + 92-B desc@0x18**（§1.3 样本 C），以及 fmc ELF32 的 **section 表**
（`hash`/`signature`/`publickey`/`image`，与 E8/E13a 一致）。

`ad102/ga102-bootloader` 尾部另有一段结构：从 payload 内偏移 `0x8000`（ad102）/`0x5000`（ga102）
开始、共 1220 个非零字节的**低熵小 blob**（256-B 块熵 `0.25…6.10`），
与 desc 的 `bootloaderOffset=0x8000/0x5000`、`bootloaderSize=0x880`、`bootloaderParamOffset=0x8880/0x5880`、`paramSize=0x10`
**逐字节对上**（验证见 §1.3）。GB202/GB100/GH100 的 `bootloaderOffset=0`（B，矩阵 §1.3）——
即"内层 bootloader 描述"只在 ad102/ga102 存在。
注意：**这是 FMC/booter 家族里唯一可静态阅读的（低熵）块**，本次已在其中做
`bootloader/FUSE/PKC/MODULUS/DESCRIPTOR` 全模式扫描：**0 命中**（B）。

### 3.3 与 E1/E8/E13b 合并后的读法

| 命题 | 既有 | 本次 | 判定 |
|---|---|---|---|
| 可见材料里存在 FMC 键/hash 常量 | E1/E2 = NONE | 复核 NONE（新增 8 个镜像 0 命中） | **B（负，范围限定）** |
| host 在经典路径不递键 ⇒ 设备必有键/anchor | E8 | 复核（`publickey`/`signature` 槽内 0 个 on-curve P-384 点，沿用） | **B/S** |
| 存在"把 GFW 键材料装进熔丝"的工艺 | E13b（`fuserework_debug_gfw_pub_key/hash/sig.bin`） | — | **N（机制级）** |
| 键检查的**形态**：清单 + prod/dev 槽 + 模数 | — | `RSA_MODULUS_KEY_MANIFEST_MISMATCH_{PROD,DEV}`、`INVALID_GSP_FMC_KEY_{PROD,DEV}`、`INVALID_GSP_FMC_MODULUS` | **N（偏正，新）** |
| 熔丝参与键/版本策略 | E4 | `ACR_ERROR_INVALID_UCODE_FUSE`；`GFW_FUSE_CHECK_FAILURE`；GFW 信任等级寄存器 | **N + 熔丝字段本身 B** |
| 整键 vs 仅 key-hash | E13b 两文件并列 | `..._MODULUS_...` 指向"模数"级别 | **UNKNOWN（略偏模数/hash 而非整键）** |
| 熔丝 vs ROM | UNKNOWN | 仍 UNKNOWN | **UNKNOWN** |

**一句话**：本次把 Q3 从"有机制线索、缺闭环"推进到
**"有形态线索（key manifest + prod/dev 键槽 + 模数校验 + GFW 信任等级），但落点仍不可判"**。
按最保守读法仍应按"锚点存在且设备侧执行"处理。

---

## 4. Q4：明确负结果清单（搜过什么、命中 0）

| # | 负结果 | 目标/模式 | 命中 |
|---|---|---|---|
| F1 | host 侧 3 个 size 字段零消费 | 全树 `grep monitorCodeSize\|monitorDataSize\|manifestSize` | 只有 `rmRiscvUcode.h:57/62/67`、`ls10.h:764/769/774`、`gsp_fw_wpr_meta.h:81-83` 定义（**0 消费**） |
| F2 | host 侧 offset 边界检查 | `grep -c` 针对 offset 与 image size 的比较；逐行读 `:730-777`、`:303-350` | 0 |
| F3 | host 侧 desc `version` 检查 | 全树 `version` 与 desc 的组合读点 | 0（v4 全 0 desc 与 v6 不被区分） |
| F4 | FMC/booter 镜像里的熔丝/PKC/键字样 | 8 个镜像 × 30 模式（§3.2） | **0**（镜像为密文，B） |
| F5 | 三份设备侧 GSP-RM 二进制里的 FMC 域字样 | `FMC_` / `GSP_FMC` / `booter` / `BOOTER` / `RSA_MODULUS` / `INVALID_GSP_FMC` / `FMC_SIGNATURE_MISMATCH` | **0 / 0 / 0**（`BOOTLOADER_UCODE_HASH_MISMATCH` 各 1 次除外） |
| F6 | `ucode_manifest*` 是否= 键清单 | 570.144 ELF 里 3 处，邻域是 `RmSec2*` regkey 与 `ucode_data_prod/dbg` | **不是**：那是 SEC2 ucode 的 **external bindata 名**，与 RSA 键清单无关（避免误读） |
| F7 | WPR2 meta magic 的设备侧消费者 | `0xdc3aae21371a60b3`（LE/BE）在 3 份设备二进制 | RX/570.144 = 0；82 MB debug ELF 里 `0xa0a0…` 命中 1（巧合，未定位） |
| F8 | `/lib/firmware/.../{bootloader,fmc}-570.144.bin` 的开源消费者 | 开源树 `grep -rn "bootloader\"\|/gsp/bootloader\|fmc-570"` | 0；`nv-firmware.h` 只声明 `gsp_ga10x/gsp_log_ga10x/ucodes_ga10x`（B） |
| F9 | MODS 里的 FMC/booter 固件路径 | `nvidia/<chip>/gsp/...` 形式 | 0（MODS 不含该路径族） |
| F10 | 92-B desc 的 hash/sig 伴生 label | `GspRmBoot_GB202` archive label 清单 | 只有 `UCODE_IMAGE_*`+`UCODE_DESC_*`（B） |
| F11 | 24 个本地 desc 样本的几何违例 | inv1/inv2/inv3（§1.3） | **0 违例**（这是"生产者一致"，**不是**"消费者校验"） |
| F12 | desc 长度与 `hdr[0x10]` 不符的样本 | 24 样本 `hdr[0x10]-0x18` vs {76,84} | **0 不符**（v4 全 76/19 字段，v5 全 84/21 字段） |

---

## 5. 置信度与威胁模型（避免误读的三条）

1. **"host 递交"必须分层**：(a) 运行期递交（COT payload / WPR2 meta / FMC args）；
   (b) 随驱动/固件包递交（bindata、`/lib/firmware` 文件、92-B desc）。
   D1/D2/D6 属 (b)：**改 desc 需要模块数据/MODS override 级能力**，不是普通用户输入。
2. **N 级证据只能证"检查存在"**：`RSA_MODULUS_KEY_MANIFEST_MISMATCH_*` 等是**名字**；
   本次没有定位到代码、数字码或数据结构。任何"因此可以/不可以……"的结论都必须标注为待闭合。
3. **密文负结果的双向性**：F4/F5 的 0 命中**既不能证"有"也不能证"无"**；
   它只说明"本地静态看不到"。因此 Q3 的最终判定保持 UNKNOWN，而不是"没有钉扎"。
4. **本次新增一个 UNKNOWN（不要外推）**：`ConcatFMC[0xB300+0x33900 .. ]` 与已签名 CC 容器 payload
   的同位置有 45,633 B 不同（同几何、不同字节）。本地**没有**任何证据说明那些字节是什么
   （另一变体的密文？二次封装？）⇒ 不得用它推出"同一固件存在两套可互换字节"之类结论。

---

## 6. 5 个纯静态下一步（不需要设备）

**S1（最高价值）：把 MODS 状态名表变成"数字码 ↔ 名字"，从而定位 FMC 键检查的产出点。**
`FMC_SIGNATURE_MISMATCH / INVALID_GSP_FMC_MODULUS / INVALID_GSP_FMC_KEY_{PROD,DEV} /
RSA_MODULUS_KEY_MANIFEST_MISMATCH_{PROD,DEV}` 都只是名字。
做法：在 MODS 里找 `NVRM: ACR FAILED: Error: %s` / `%s` 格式化点及其字符串指针表
（0x8c096c8 区域是 ACR 专属表），再看是否有一张并行的 `u32 code[]` 数组；
拿到数值后在 MODS/GSP-RM 里搜**比较立即数**。
判据：能否把 `INVALID_GSP_FMC_MODULUS` 对应到一个被 `cmp`/表查引用的数值 ⇒
若命中，则"模数校验"从 N 升到 B（并且能定位它检查的是 *提交键* 还是 *设备内建键*）。

**S2：在本地全部二进制里枚举"on-curve P-384 点 / RSA 模数"，找除已知 FMC 键之外的锚点候选。**
做法：对 MODS 570.151/570.215、nvflash、NGC/ROM/NVFW、`gsp_*` 容器做
`(y² ≡ x³ - 3x + b mod p)` 全偏移扫描（97-B 与 96-B 两种编码），
剔除已知的 prod/debug FMC 键（`af870e5d…`/`9cdd06eb…`）与曲线常数。
判据：出现**第三类**密钥点 ⇒ 该点就是"钉扎锚点"的强候选，可直接与 `.fwsignature_*` 帧
/ `fuserework_debug_gfw_pub_key.bin` 命名对齐；若只有已知两类 ⇒
把"host 侧制品里没有额外锚点"写成明确负结果。

**S3：判定 `UCODE_DESCRIPTOR_V5_SANITY_FAILURE` / `UCODE_UNRECOGNIZED_DESCRIPTOR_P1..P3`
到底是"Falcon ucode desc（FALCON_UCODE_DESC_V4/V6_PAYLOAD_ENTRY 同表）"还是"92-B RISC-V desc"。**
做法：这两族名字在 MODS 0x88f6018..0x88f6158 相邻，且 92-B 结构的版本号语义里 **v5 = "signing entire
RISC-V image as code"**（`rmRiscvUcode.h:42` 注释，B）。
用同表邻域的 `FALCON_UCODE_DESC_V6_PAYLOAD_ENTRY`（0x8a80468 有 NVRM 打印）反推该表的归属。
判据：若该表属于 host 的 falcon-ucode loader，则"RISC-V desc 无人 sanity"这一结论强化（
即 §1.5 的 UNKNOWN 更偏"设备侧也不查"，但仍是 UNKNOWN）；
若属于设备引导侧，则给出"设备侧 sanity 检查存在"的更强证据。

**S4：把 desc 几何矩阵扩到"与 blob 的交叉一致性"，做违例搜索。**
本次已做 24 个 `bootloader-570.144.bin` 的 desc-vs-自身 payload；下一步把
bindata 侧全部 desc（GB100/GB202/GR100/GH100/GB10B/GB20B 的 `*_desc.bin`，
含 `ConcatenatedFMCDesc`）与对应 `*_image.bin` 做同一张表，
并额外验证"desc 范围是否覆盖容器 header 之后的内容"（本次发现 desc 语义是 post-0x48）。
判据：任何一份 desc 的范围**越出**其 blob ⇒ 直接构成"生产者/消费者不一致"的字节级证据
（本次 24/24 全一致，属负结果）。

**S5：确定 WPR2 meta 的两个"设备侧语义"问题（U3 + 反查）。**
(a) `verified=0xa0a0…` 是否被 host 侧任何代码**读**（决定"设备回填值是否被 host 采信"）；
(b) `bootloaderCodeOffset/DataOffset/ManifestOffset` 是否在 GSP-RM/FSP 侧有 **relocate/加基址**
（即它们相对 `sysmemAddrOfBootloader` 还是相对 WPR2）；(c) CC+debug 时
`ConcatenatedFMCDesc` 没有 DBG label 的返回值语义。
做法：(a) 在 MODS/nvflash 里做 `0xa0a0a0a0a0a0a0a0` 与 magic 的**立即数/比较**搜索（本次只做了原始字节计数）；
(b) 在 GSP-RM 三份 ELF 里用结构偏移（0x28/0x30/0x38 三个 u64 字段）做"三连偏移"结构-常量匹配。
判据：能否在设备侧找到"读 meta 的 3 个偏移并与 `sizeOfBootloader` 比较"的代码骨架。

---

## 7. 复现命令（全部只读；无设备访问；无联网）

```bash
# ---- (1) host 侧：消费点与"无校验" ----
S=/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src
grep -rn "monitorCodeOffset\|monitorDataOffset\|manifestOffset\|monitorCodeSize\|monitorDataSize\|manifestSize\|bootloaderCodeOffset\|bootloaderDataOffset\|bootloaderManifestOffset" $S
grep -rn "pRiscvDesc->" $S --include=*.c
sed -n '740,775p' $S/nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c
sed -n '303,350p' $S/nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c    # WPR2 meta
sed -n '995,1002p' $S/nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c   # appVersion → FALCON_OS
sed -n '25,60p'   $S/common/inc/swref/published/hopper/gh100/dev_riscv_pri.h     # DMAADDR LO/HI 宽度
sed -n '79,120p'  $S/nvidia/arch/nvalloc/common/inc/gsp/gsp_fw_wpr_meta.h        # "Consumed by Booter for DMA"
sed -n '80,101p'  $S/nvidia/src/kernel/gpu/gsp/arch/ampere/kernel_gsp_ga102.c    # 用哪个 archive/label
sed -n '1052,1082p' $S/nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c  # CC 走 ConcatFMC*
sed -n '875,900p' $S/nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c    # BCR 路径是 fallback

# ---- (2) 92-B desc：24 样本矩阵 + 几何不变量（本次脚本）----
mkdir -p /tmp/descabuse/all && cd /tmp/descabuse/all
for s in /usr/lib/firmware/nvidia/*/gsp/bootloader-570.144.bin.zst; do \
  c=$(echo $s|cut -d/ -f6); zstd -d -q -f "$s" -o bl-$c.bin; done
python3 - <<'PY'
import struct,glob,hashlib
N="version bootloaderOffset bootloaderSize bootloaderParamOffset bootloaderParamSize riscvElfOffset riscvElfSize appVersion manifestOffset manifestSize monitorDataOffset monitorDataSize monitorCodeOffset monitorCodeSize bIsMonitorEnabled swbromCodeOffset swbromCodeSize swbromDataOffset swbromDataSize fbReservedSize bSignedAsCode bIsSmp bIsPlicEnabled".split()
for f in sorted(glob.glob('bl-*.bin')):
    d=open(f,'rb').read(); v=dict(zip(N,struct.unpack_from('<23I',d,0x18)))
    inv=(v['monitorDataOffset']==v['manifestSize'],
         v['monitorCodeOffset']==v['manifestSize']+v['monitorDataSize'],
         v['monitorCodeOffset']+v['monitorCodeSize']<=len(d)-0x74)
    print(f,len(d),v['version'],hex(v['manifestSize']),hex(v['monitorDataSize']),hex(v['monitorCodeSize']),inv,hashlib.sha256(d[0x18:0x74]).hexdigest()[:12])
PY

# ---- (3) 与 blob 的边界 / 拼接容器语义 ----
python3 - <<'PY'
d=open('/tmp/fmcaudit/g_bindata_kgspGetBinArchiveGspRmBoot_GB202.c.290816.raw.bin','rb').read()
print('last nonzero',hex(max(i for i,b in enumerate(d) if b)),'desc region end 0x46200')
c=open('/tmp/fmcaudit/g_bindata_kgspGetBinArchiveConcatenatedFMC_GB202.c.503808.bin','rb').read()
cc=open('/tmp/fmcaudit/out/fmc_cc_prod_gb202.BINDATA_LABEL_UCODE_IMAGE.bin','rb').read()[0x48:]   # container payload
run=0
while run<len(cc) and c[0xB300+run]==cc[run]: run+=1
print('ConcatFMC[0xB300..] 与 CC payload 逐字节相同的连续长度 = 0x%x (=desc.monitorCodeSize 0x33900 ?)'%run)
PY

# ---- (4) 签名覆盖范围（hash + ECDSA P-384 离线验证）----
cd /tmp/fmcaudit/out && python3 -c "
import hashlib;img=open('fmc_prod_gb202.BINDATA_LABEL_UCODE_IMAGE.bin','rb').read()
h=open('fmc_prod_gb202.BINDATA_LABEL_UCODE_HASH.bin','rb').read()
print('sha384(image)==UCODE_HASH:',hashlib.sha384(img).digest()==h)"
# （ECDSA 验证：纯 Python、无外部依赖、离线；输出 VALID）
cd /tmp/fmcaudit/out && python3 - <<'PY'
import hashlib
p=2**384-2**128-2**96+2**32-1; a=-3
b=int('b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef',16)
n=int('ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973',16)
Gx=int('aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7',16)
Gy=int('3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f',16)
def add(P,Q):
    if P is None: return Q
    if Q is None: return P
    x1,y1=P; x2,y2=Q
    if x1==x2 and (y1+y2)%p==0: return None
    l=((3*x1*x1+a)*pow(2*y1,-1,p) if P==Q else (y2-y1)*pow((x2-x1)%p,-1,p))%p
    x3=(l*l-x1-x2)%p; return (x3,(l*(x1-x3)-y1)%p)
def mul(k,P):
    R=None
    while k:
        if k&1: R=add(R,P)
        P=add(P,P); k>>=1
    return R
img=open('fmc_prod_gb202.BINDATA_LABEL_UCODE_IMAGE.bin','rb').read()
h=open('fmc_prod_gb202.BINDATA_LABEL_UCODE_HASH.bin','rb').read()
sig=open('fmc_prod_gb202.BINDATA_LABEL_UCODE_SIG.bin','rb').read()
pk=open('fmc_prod_gb202.BINDATA_LABEL_UCODE_PKEY.bin','rb').read()
e=int.from_bytes(h,'big'); Qx=int.from_bytes(pk[1:49],'big'); Qy=int.from_bytes(pk[49:],'big')
print('on-curve',(Qy*Qy-(Qx**3+a*Qx+b))%p==0,' sha384==hash',hashlib.sha384(img).digest()==h)
r=int.from_bytes(sig[:48],'big'); s=int.from_bytes(sig[48:],'big')
w=pow(s,-1,n); Pt=add(mul(e*w%n,(Gx,Gy)),mul(r*w%n,(Qx,Qy)))
print('ECDSA P-384/SHA-384(image):','VALID' if Pt and Pt[0]%n==r else 'INVALID')
PY

# ---- (5) 密钥/熔丝/描述符模式的 0 命中复算 ----
cd /tmp/descabuse/fw && python3 - <<'PY'
import glob
pats=[b'FUSE',b'Fuse',b'ZB_',b'PKC',b'ECDSA',b'RSA',b'SHA',b'secp384',b'MODULUS',b'MANIFEST',b'modulus',
      b'DMAADDR',b'PKCPARAM',b'FMCCODE',b'FMCDATA',b'DESCRIPTOR',b'CHAIN_OF_TRUST',b'PUBKEY',b'SIGNATURE']
for f in sorted(glob.glob('*.bin')):
    d=open(f,'rb').read(); h={p.decode():d.count(p) for p in pats if d.count(p)}
    print('%-42s %8d %s'%(f,len(d),h if h else 'ALL-ZERO'))
PY

# ---- (6) MODS 侧新增名称证据（偏移可复核）----
cd /home/user/rt_5090_project/parallel/cot_pin_work
grep -nE "FMC_SIGNATURE_MISMATCH|INVALID_GSP_FMC_(MODULUS|KEY_PROD|KEY_DEV|VERSION)|RSA_MODULUS_KEY_MANIFEST|UCODE_DESCRIPTOR_V5_SANITY|UCODE_UNRECOGNIZED_DESCRIPTOR" off_strings_mods570215.txt
grep -nE "ACR_ERROR_(GFW_CHAIN_OF_TRUST_BROKEN|INVALID_UCODE_FUSE|GSP_FMC_AND_GSP_RM_MISMATCH)" off_strings_mods570215.txt
grep -nE "GFW_FUSE_CHECK_FAILURE|GFW_BOOT_VALIDATION_STATUS" off_strings_mods570215.txt | head
grep -oE "NV_PGC6_AON_SECURE_SCRATCH_GROUP_05_0_GFW_BOOT[A-Z_]*" strings_mods570215.txt | sort -u

# ---- (7) 设备侧二进制里 FMC 域 0 命中 ----
for f in strings_gsp61057_rx_full.bin.txt strings_gsp_inner_570144_main.elf.txt strings_gsp_inner_19f040_a.elf.txt; do
  for p in "FMC_" "GSP_FMC" "booter" "RSA_MODULUS" "INVALID_GSP_FMC"; do
    printf '%s %s %s\n' "$f" "$p" "$(grep -c -- "$p" $f)"; done; done
```

---

## 附录 A：本次产生的工件（可独立复核）

| 工件 | 说明 |
|---|---|
| `/tmp/descabuse/all/bl-*.bin` | 24 个 chip 的 `bootloader-570.144.bin` 解压副本（仅本地 /tmp，只读来源 `/usr/lib/firmware/nvidia/*/gsp/*.zst`） |
| `/tmp/descabuse/fw/` | gb202/gb100/gh100 的 fmc+bootloader、ad102/ga102 的 bootloader/booter_load/booter_unload/scrubber 解压副本 |
| `cot_pin_work/off_strings_mods570215.txt` | MODS 570.215 带偏移字符串（本文 §3.1 全部偏移引用出处） |
| `cot_pin_work/FWSECLIC_ERR_CODE_names_61057.txt` | 90 项设备侧 FWSECLIC 错误名（§1.5） |

| 输入 | sha256（前 16） | 关键事实 |
|---|---|---|
| `g_gsp_gb20x_dyn_prd_desc.bin`（GspRmBoot desc, v6） | `6f4ecedadb0a7da0` | man 0/0xA00, data 0xA00/0xE800, code 0xF200/0x37000 |
| `g_gsp_gb20x_dyn_spdm_prd_desc.bin`（ConcatFMCDesc, v6） | `bbdabd5a7c833652` | code 0xB300/0x33900（指向内嵌 CC payload） |
| `GspRmBoot_GB202` image | — | 290,816 B；最后非零字节 `0x461FF` == desc 范围末端 |
| `ConcatenatedFMC_GB202` image | — | 503,808 B；CC payload（`fmc_cc_prod_gb202` payload）逐字节 @`0xB300` |
| `gb202-bootloader-570.144.bin` inline desc@0x18 | `609e3f35763707d5` | v5；几何与 `gb202-fmc-570.144.bin` 容器一致（偏移 post-0x48 语义） |
| `gb202-fmc-570.144.bin` | `cb59a35c1d4bd127` | ELF32：`hash`(48)/`signature`(96)/`publickey`(97)/`image`(199,240) |
| `fmc_prod_gb202` 四件套 | — | `sha384(image)==UCODE_HASH` **True**；ECDSA P-384/SHA-384 **VALID**；pkey 97 B 首字节 0x04、on-curve **True** |
| MODS 570.215 `/mods` | `6645d5de5e0ce3c9`（沿用） | §3.1 名称证据来源 |

---

## 附录 B：本文对起点文档的两处更正 / 补充

1. **`appVersion` 有消费者**（起点文档 §3.3 把它列为"无消费者"）：
   `kernel_gsp_gh100.c:1000`、`kernel_gsp_tu102.c:588`、`kernel_gsp_falcon_tu102.c:484`
   把 `pRiscvDesc->appVersion` 写进 `NV_PFALCON_FALCON_OS`（B）。
   ⇒ 表述应为"**23 字段中 4 个有消费者（3 个 offset + appVersion）**"。
2. **3 个 offset 的基准是"payload 起点"**（本次逐字节验证，B）：
   在 signed 容器里 = 去掉 72 B header 之后（desc `dataOffset=0xA00` vs 容器 `dataStart=0x48+0xA00`）；
   在 falcon framing 里 = 从 `hdr[0x10]=0x6C` 起（ad102 `bootloaderOffset=0x8000` 逐字节落在文件 `0x806C`；
   ga102 `0x5000`→`0x506C`；`paramOffset+paramSize` 覆盖最后一个非零字节 `0x88F9`）。
   这解开了两个现象：(a) 无头 `GspRmBoot` blob 的 desc 从 0 计数、有头容器要减 0x48；
   (b) **v5 desc 实际只有 84 B**，按 92-B 读会多读 8 B 进 payload（= 起点文档 C1-3 的"垃圾尾部"成因）。

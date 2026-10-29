# FSP / FMC 容器签名与解析链静态审计（P-384/ECDSA 主线）

日期：2026-09-25（Asia/Singapore）
探针脚本：`parallel/fmc_signature_probe_20260925.py`
（SHA-256 `bf268203b9a75132700d55a2c9c9c1cc76c9ca49ca5cac910b25d4f2d32cc71b`）

## 0. 范围、安全边界与方法

**只做静态、只读。** 本报告全部结论来自本地普通文件的字节、本地公开 RM 源码文本
与离线密码学复算。本次没有：

- 访问 GPU、`/dev/nvidia*`、PCI/BAR/MMIO、debugfs、sysfs 寄存器窗口；
- 执行 `nvflash`、`.scexe`、`.run` updater、MODS、insmod/rmmod、reset/rebind；
- 写入或修改任何固件、`.fwpkg`、`.nvfw`、bindata 或 `/lib/firmware`；
- 联网下载（新增哈希全部来自本机已有文件）。

**出口管制/授权禁止项：**本报告不涉及、也不提供任何针对 5090D（或其他 SKU）
算力限制、L2/授权策略、熔丝写入的绕过路径；不提供刷写、回滚、重签或移植固件
的操作步骤。第 5 节的"候选弱点"全部是**防御性解析/信任边界观察**，用于说明
验签实现自身的鲁棒性与信任落点，不构成对设备的可利用改造方案。

方法：先用离线脚本解出所有内嵌容器（`zlib raw-inflate` 解 bindata，
`zstd -d` 解 `/lib/firmware` 归档），再对每个容器做结构枚举 + SHA-384 复算 +
ECDSA P-384/SHA-384 离线验签；对源码只做逐行阅读与行号引用，不编译、不加载。

## 1. 证据清单（本地、只读）

| 类别 | 路径 | SHA-256（前 16） |
|---|---|---|
| 驱动源码（上游 610.43.03 + 本地 p0 提交，工作树干净） | `…/greenfield/open-gpu-kernel-modules/`（HEAD `d7b969d1`） | — |
| FMC 容器（编译进驱动） | `src/nvidia/generated/g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c` | `bdca34c507d1b6a8` |
| FMC 容器（CC/SPDM prod） | `…GspRmCcFmcGfwProdSigned_GB202.c` | `29134b11b4306fc4` |
| FMC 容器（debug） | `…GspRmFmcGfwDebugSigned_GB202.c` | `4b615950e0a9fda4` |
| GSP 启动镜像（FMC bootloader） | `…GspRmBoot_GB202.c` | `ba14ae304f4eaf71` |
| Concatenated FMC（CC） | `…ConcatenatedFMC_GB202.c` | `0a308947ee91192d` |
| Concatenated FMC 描述符 | `…ConcatenatedFMCDesc_GB202.c` | `64019041c2d2c2c1` |
| 参考：GH100 FMC | `…GspRmFmcGfwProdSigned_GH100.c` | `cf75c1a63a694ef5` |
| 570.144 FMC 容器 | `/lib/firmware/nvidia/gb202/gsp/fmc-570.144.bin.zst` | `7cc18911246663e8` |
| 570.144 FMC bootloader | `/lib/firmware/nvidia/gb202/gsp/bootloader-570.144.bin.zst` | `a4f1c63e7710e893` |
| 570.144 经典 GSP 容器 | `/lib/firmware/nvidia/ga102/gsp/gsp-570.144.bin.zst` | `1aa965fb408b9c4c` |
| 610.57.04 经典 GSP 容器 | `/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin` | 见 §3.4 |
| 设备侧 GSP-RM（RV64） | `rt_5090_project/ghidra_static/gsp_inner_570144_main.elf` | `6c36425881780a14` |
| 设备侧 GSP-RM（debug/大） | `…/ghidra_static/gsp_inner_19f040_a.elf` | `bda917c955476443` |
| 设备侧 GSP RX 切片 | `rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin` | `50614073f1ca73d4` |
| HGX B300 GPU FW 包 | `…/dell_hgx_blackwell/extracted_…662GC…/payload/nvfw_HGX-B300x8_0006_260317.1.2_custom_prod-signed.fwpkg` | `612224d43e8b8c7c` |

既有本地报告（本次只引用、不重复其结论）：
`parallel/fwpkg_container_auth.md`、`parallel/public_fsp_fwupdate_chain.md`、
`parallel/vbios_fsp_inventory.md`、`parallel/falcon_manifest_table.md`、
`parallel/bcrt_manifest_coverage.md`、`parallel/gsp_f8_hulk_audit.md`。

## 2. 结论摘要

1. **FACT（新）** GB202/GB100 的 FMC 镜像在 570.144 与 610.43.03 两个分支里使用
   **同一个 P-384 公钥**（`SHA-256(pubkey)=af870e5dde972840588bfb94a87f94b19ad6
   659dae6e1343dd0d22f16074ba39`），prod 与 CC/SPDM 变体共用这把键；debug 镜像用
   另一把键（`9cdd06eb…`），GR100 又是一把（`34a0836e…`）。
2. **FACT（新）** FMC 镜像的签名**覆盖整个镜像字节**（`ECDSA P-384/SHA-384`，
   `signature = 96B r||s`、`hash = SHA-384`、`pubkey = 97B 未压缩点`）。已对
   570.144 的 `gb202-fmc`、`gb100-fmc` 与 610.43.03 的 `*_gfw_image`（prod/dbg/CC）
   共 **9** 个 P-384 样本离线验签成功，无任何"未覆盖区"；第 10 个样本（GH100，
   384-B 尺寸）的摘要关系成立但签名算法未闭合（§4.3）。
3. **FACT（新）** FMC 容器是**固定 72-byte 头 + manifest(0xA00) + data + code**：
   `+0x00 u16 ver=0x0403`、`+0x02 u16 hdrSize=0x48`、`+0x04 u32 payload`、
   `+0x0c u32 codeSize`、`+0x14 u32 dataSize`；五份 570/610 样本都精确满足
   `0x48 + 0xA00 + dataSize + codeSize == 文件长度`。
4. **FACT（新）** FMC 的认证材料以两种等价封装出现：
   (a) bindata 四元组 `UCODE_IMAGE/UCODE_HASH/UCODE_SIG/UCODE_PKEY`；
   (b) ELF32 容器的 `image/hash/signature/publickey` 四个 section。
   两者字段一一对应，section 名即 bindata 标签的语义名。
5. **FACT（新）** 经典单体路径 `gsp-*.bin`（ELF64 wrapper）里，签名是
   **按芯片家族成套的 4 KiB section**：`.fwsignature_<family>` 与
   `.fwsignature_cc_<family>`。570.144 有 7 个、610.57.04 有 12 个；驱动侧
   `_kgspGetSectionNameForPrefix()` 用 `".fwsignature_" + chipFamily` 现算名字。
6. **FACT** 算法处于迁移中间态：`GH100/GB10B/GB20B` 的 FMC 仍是 **384-byte**
   签名/公钥（RSA-3072 尺寸），`GB100/GB202/GR100` 已切到 **P-384 (96/97)**；
   FSP HAL 与 SEC2 HAL 在源码里用同一组 `cotPayload*Size` 描述这个差异。
7. **FACT（负结果，重要）** GB202 FMC 的 prod 公钥（以及对应 hash、签名）
   **不在任何本地设备侧制品中**：HGX B300 GPU FW 包（111 MB）、Dell/HPE GB202
   NVFW、RTX 5090 ROM、两份 GSP-RM ELF、R570 RX 切片里都搜不到。可见范围内该
   公钥**只由主机驱动提供**（COT payload）；其"钉扎"（若有）只能在设备内部
   （fuse/BootROM/HS-KEK），本地无法验证。
8. **FACT** 固件版本在途中有熔丝与版本驱动的选择：`kgspIsDebugModeEnabled_GB100`
   读 `NV_FUSE_ZB_OPT_SECURE_GSP_DEBUG_DIS`（`0x74C`，`DATA 0 = debug 开`）决定
   用 prod 还是 debug 键；`s_patchBooterUcodeSignature()` 用
   `NV_FUSE_ZB_OPT_FPF_SEC2/GSP_UCODE1_VERSION`（`0x4140/0x41C0`）算
   `sigIndex = numSigs - 1 - fuseVer` 来挑第几份签名。
9. **FACT（新）** 主机内核侧**不做任何签名验证**：它只做 ELF 容器解析
   （`.fwversion`/`.fwimage`/`.fwsignature_*`/`.note.gnu.build-id`），把签名当成
   不透明字节交给设备（WPR2 meta 或 NVDM type `0x14` COT）。因此"验证器"在设备
   侧，公开源码只能给出它的**接口契约与长度约定**。
10. **INFERENCE（强）** 570.144 的 `gsp-ga10x` 容器缺 `.fwsignature_cc_gb20x`
    （610.57.04 才有），与 CC/GB20x 在 610 才成熟、且 open 驱动 CC 路径改用
    "ConcatenatedFMC（无独立 hash/sig/pkey）"一致；该路径的认证材料来源在公开
    源码中**没有闭合**（见 §5.4）。

## 3. FMC / FSP 容器结构与签名 section 的覆盖范围

### 3.1 部署矩阵：谁把哪份镜像送到设备

驱动侧选择逻辑（行号来自 `src/nvidia/src/kernel/gpu/` 下的 610.43.03 源码）：

| 路径 | 选择函数 | GB202（prod, 非 CC） | GB202（CC/SPDM） | 独立签名？ |
|---|---|---|---|---|
| GSP-client 启动镜像（WPR2 bootloader） | `kgspGetGspRmBootUcodeStorage_GB100` (`gsp/arch/blackwell/kernel_gsp_gb100.c:119-153`) | `GspRmBoot_GB202`：`UCODE_IMAGE_{DBG,PROD}` + `UCODE_DESC_{DBG,PROD}`（各 290,816 B + 92 B） | `ConcatenatedFMC_GB202`：`UCODE_IMAGE_PROD` 503,808 B + `UCODE_DESC_PROD` 92 B | **无**（见 §5.4） |
| FSP 启动 GSP-RM | `kfspGetGspUcodeArchive` (`gsp/arch/hopper/kern_fsp_gh100.c:785-857`，发送侧 `kfspSetupGspImages` 同文件 `953-1049`) | `GspRmFmcGfwProdSigned_GB202`：IMAGE 287,304 + HASH 48 + SIG 96 + PKEY 97 | `GspRmCcFmcGfwProdSigned_GB202`：IMAGE 257,096 + 48 + 96 + 97 | **有**（P-384） |
| SEC2 启动 GSP-FMC/RM（GB10B/GB20B） | `_ksec2GetGspUcodeArchive` (`sec2/arch/blackwell/kernel_sec2_gb20b.c:556-620`) | 同 `GspRmFmc*Signed_*` 家族 | 同上 | **有**（GB20B 为 384 B） |
| 经典单体 GSP 路径（monolithic RM client） | `kgspInitRm`→`RmFetchGspRmImages`(`arch/nvalloc/unix/src/osinit.c:1883-1948`) | 从 `/lib/firmware` 取 `gsp_*.bin` ELF64 wrapper，取 `.fwimage` + `.fwsignature_gb20x` | 同文件 `.fwsignature_cc_gb20x` | **有**（按 family 的 4 KiB section） |

`nv_firmware_for_chip_family()` 对 `GR10X/GB10X/GB10Y/GB20Y/GB20X/GH100/AD10X/GA10X`
全部返回同一个基名 `"gsp_ga10x"`（`arch/nvalloc/common/inc/nv-firmware.h:96-115`，
`kernel-open/common/inc/nv-firmware.h:104-117`）——这解释了为什么单个 60–84 MB
ELF64 容器里要同时携带 7（570.144）/12（610.57.04）份 per-family 签名。

### 3.2 FMC 镜像（72-byte header）的真实布局

对 570.144 与 610.43.03 五份样本做字段复算（脚本 `fmc-elf` 模式）：

| 样本 | 文件大小 | ver | hdr | payload | codeSize | dataSize | `0x48+0xA00+data+code` |
|---|---:|---:|---:|---:|---:|---:|---:|
| `gb202-fmc-570.144` image | 199,240 | 0x0403 | 0x48 | 199,168 | 153,600 | 43,008 | 199,240 ✅ |
| `gb100-fmc-570.144` image | 197,448 | 0x0403 | 0x48 | 197,376 | 152,064 | 42,752 | 197,448 ✅ |
| `gh100-fmc-570.144` image | 165,448 | 0x0403 | 0x48 | 165,376 | 120,064 | 42,752 | 165,448 ✅ |
| 610 `g_gsp_gb20x_dyn_prd_gfw_image` | 287,304 | 0x0403 | 0x48 | 287,232 | 225,280 | 59,392 | 287,304 ✅ |
| 610 `g_gsp_gb20x_dyn_spdm_prd_gfw_image` | 257,096 | 0x0403 | 0x48 | 257,024 | 211,200 | 43,264 | 257,096 ✅ |

`+0x18=0x104`、`+0x20=0x2801` 在全部 5 份样本里为常量（含义未由公开材料定义，
不命名）。570.144 的 `bootloader-570.144.bin`（Falcon `0x10de` ucode 头 + 92-byte
描述符）在同一位置给出 `{manifestSize=0xA00, monitorDataOffset=0xA00,
monitorDataSize=0xA800, monitorCodeOffset=0xB200, monitorCodeSize=0x25800,
bIsMonitorEnabled=1}`，与同版本 FMC 容器的 `dataSize=0xA800 / codeSize=0x25800`
**精确一致**——这是"72-byte header = 描述符字段的容器内副本"的机械交叉证据。

610.43.03 的两份独立 92-byte 描述符也互相印证：`GspRmBoot_GB202` 的 DESC_DBG 与
DESC_PROD **逐字节相同**（`sha256 6f4ecedadb0a7da0`），给出
`monitorDataSize=0xE800 / monitorCodeSize=0x37000`，与同版本 `gfw` 容器头的
`dataSize=0xE800 / codeSize=0x37000` **完全一致**（但两者的 manifest/data/code
区域字节并不相同，说明这是同一次 build 的几何参数，不是同一份字节的复制）。
CC 描述符（`…_spdm_prd_desc.bin`）解码为
`version=6, manifestOffset=0, manifestSize=0xA00, monitorDataOffset=0xA00,
monitorDataSize=0xA900, monitorCodeOffset=0xB300, monitorCodeSize=0x33900,
bIsMonitorEnabled=1`，其余字段全 0；字段名取自
`arch/nvalloc/common/inc/rmRiscvUcode.h`（23×u32 = 92 B），并已用上表的
code/data 尺寸互校。驱动对这份描述符**不做任何校验**，只读三个字段：
`kgspPopulateWprMeta_GH100()`（`gsp/arch/hopper/kernel_gsp_gh100.c:304-393`）把
`monitorCodeOffset/monitorDataOffset/manifestOffset` 原样写进 WPR2 meta 的
`bootloaderCodeOffset/bootloaderDataOffset/bootloaderManifestOffset`。

### 3.3 经典 ELF 路径：`.fwsignature_*` section 的形状

`gsp-570.144.bin`（63,571,696 B，ELF64 RISC-V，`.fwversion="570.144\0"`，
`.note.gnu.build-id = 1e5654b51660fd9c462133e46381af2183dd4371`）：

| section | offset | size |
|---|---:|---:|
| `.fwimage` | 0x40 | 0x3C99000 (63,541,248) |
| `.fwsignature_gb20x` | 0x3C9906C | 0x1000 |
| `.fwsignature_cc_gb10x` | 0x3C9A06C | 0x1000 |
| `.fwsignature_gb10x` | 0x3C9B06C | 0x1000 |
| `.fwsignature_cc_gh100` | 0x3C9C06C | 0x1000 |
| `.fwsignature_gh100` | 0x3C9D06C | 0x1000 |
| `.fwsignature_ad10x` | 0x3C9E06C | 0x1000 |
| `.fwsignature_ga10x` | 0x3C9F06C | 0x1000 |

`gsp_ga10x.bin`（610.57.04，84,310,168 B，`.fwversion="610.57.04\0"`）有 12 个同类
section，新增/补齐了 `cc_gr10x, gr10x, gb20y, cc_gb20x, gb10y` 等。

所有 4 KiB section 共享同一帧头：`u32 {0x00020001, 0x8C8, 0x0C, 0x00010100,
0x00000200}`，随后是**四个 0x200-byte 槽位**（`+0x14 / +0x214 / +0x414 / +0x614`），
槽内是变长高熵材料（多数槽的前 384 或 96 字节连续非零）。这与"同一镜像按熔丝
版本/引擎挑选第 N 份签名"的机制相容（§4.4），但 4 KiB 帧的完整 schema
**未由公开材料定义**，本报告只报告机械边界。

### 3.4 签名覆盖范围的实证（离线验签）

脚本对每个"image + hash + signature + publickey"四元组做两件事：
`SHA-384(image) == hash`，以及用 `image/pkey/sig` 做 ECDSA P-384/SHA-384 验签。

| 样本 | image | SHA-384(image)==hash | ECDSA P-384 over 整个 image | pubkey SHA-256（前 16） |
|---|---:|---|---|---|
| 570.144 `gb202-fmc` | 199,240 | ✅ | ✅ | `af870e5dde972840` |
| 570.144 `gb100-fmc` | 197,448 | ✅ | ✅ | `af870e5dde972840`（同一把） |
| 610 `GspRmFmcGfwProdSigned_GB202` | 287,304 | ✅ | ✅ | `af870e5dde972840` |
| 610 `GspRmCcFmcGfwProdSigned_GB202` | 257,096 | ✅ | ✅ | `af870e5dde972840` |
| 610 `GspRmFmcGfwDebugSigned_GB202` | 287,304 | ✅ | ✅ | `9cdd06eb4b7c6d7a`（debug 键） |
| 610 `GspRmFmcGfwProdSigned_GB100` | 197,960 | ✅ | ✅ | `af870e5dde972840` |
| 610 `GspRmCcFmcGfwProdSigned_GB100` | 195,656 | ✅ | ✅ | `af870e5dde972840` |
| 610 `GspRmFmcGfwDebugSigned_GB100` | 197,960 | ✅ | ✅ | `9cdd06eb4b7c6d7a` |
| 610 `GspRmFmcGfwProdSigned_GR100` | 198,472 | ✅ | ✅ | `34a0836e165e8a87`（另一把） |
| 610 `GspRmFmcGfwProdSigned_GH100` | 165,448 | ✅ | ✗（见 §4.3） | `b6590fa3546ab7f7`（384 B） |

**覆盖结论（FACT）**：P-384 家族样本的签名范围 = 镜像的**全部字节**（含 72-byte
头、manifest、code、data），不存在被排除的头部/trailer；`SHA-384` 与
`ECDSA(r,s)` 都是裸值，无 DER/X.509 包装。**被签对象不是"固件版本"或"hash 的
hash"，而是这一个 byte string 本身**——因此任何字节修改（包括 72-byte 头里的
codeSize/dataSize）都会破坏签名。

### 3.5 驱动侧解析规则（host 分支，逐条列点）

`_kgspFwContainerGetSection()`（`gsp/kernel_gsp.c:6098-6194`）：

- 只接受 ELFCLASS64 + 小端（`ident[4]==2 && ident[5]==1`），
  `shentsize == 64`；
- 校验节头表：`shoff + 64*shnum - 1 <= elfDataSize`；
- 取 `shstrndx` 指向的节头作为 strtab，校验
  `offset + size - 1 <= elfDataSize`；
- **从表尾向前**遍历节头（`for (idx = shnum-1; idx >= 0; idx--, hdr--)`），
  命中即返回 → 同名 section **取最后一个**；
- 名字匹配要求：`strtabSize-1 >= name`、前缀比较相等、且 sectionName 以 `\0` 结尾
  （`currentSectionName[sectionNameLength]=='\0'`）→ 因此
  `.fwsignature_gb20x_ext` 这类长名不会被误配，但**重复同名 section 由"最后一个"决定**；
- section 数据范围校验：`offset + size - 1 <= elfDataSize`。

`_kgspGetSectionNameForPrefix()`（`kernel_gsp.c:5781-5826`）+ `nv-firmware.h`
给出名字：`.fwsignature_` / `.fwsignature_cc_` + `{gb20x,gb10x,gh100,ad10x,ga10x,
gr10x,gb10y,gb20y,tu10x,tu11x,ga100}`；CC 前缀切换在
`kgspGetSignatureSectionNamePrefix_GB100`（`gsp/arch/blackwell/kernel_gsp_gb100.c:98-112`），
由 `PDB_PROP_CONFCOMPUTE_CC_FEATURE_ENABLED` 决定。

`_kgspPrepareGspRmBinaryImage()`（`kernel_gsp.c:5828-5928`）依次取
`.fwversion`（`_kgspFwContainerVerifyVersion`，`kernel_gsp.c:5720-5779`，要求**逐字节等于
`NV_VERSION_STRING`**）→ `gspRmFwVersionStr` → `.fwimage` → 按前缀拼出的
签名字段 → `_kgspCreateSignatureMemdesc()`（`kernel_gsp.c:5666-5718`，
`NV_ALIGN_UP(signatureSize, 256)`，注释明确 "alignment needed for Booter DMA"）
→ `.note.gnu.build-id`。**整条路径没有任何密码学调用**：签名只是被复制到
sysmem/FB 侧，交设备验证。

## 4. P-384/ECDSA 校验实现的静态特征

### 4.1 算法与编码（由离线复算确定，FACT）

| 属性 | 值 | 证据 |
|---|---|---|
| 曲线 | `secp384r1`（P-384） | 97-byte 未压缩点 `04||X||Y` 可被 `SECP384R1` 解析；曲线常数见 §4.6 |
| 摘要 | SHA-384 | `stored hash == SHA-384(image)`，10/10 样本 |
| 签名编码 | 裸 `r||s`，各 48 B，共 **96 B** | 96-byte section/绑定数组；`r,s ∈ [1,n)` |
| 覆盖范围 | 整个 image blob | 全部样本验签成功，无排除区 |
| 公钥编码 | 未压缩点，**97 B**（`0x04`+X+Y），无 X.509 壳 | 5 份 prod 样本首字节 `0x04` |
| 私钥/发布者身份 | **UNKNOWN** | 无证书链、无官方 fingerprint 可比对 |

驱动侧的长度契约（这些数字就是设备侧 verifier 的接口契约）：

- `NVDM_PAYLOAD_COT`（`inc/kernel/gpu/fsp/kern_fsp_cot_payload.h:37-55`）：
  `hash384[12]`（48 B）、`publicKey[96]`（384 B 缓冲区）、`signature[96]`（384 B
  缓冲区）、`version/size` 与两个 sysmem offset、FRTS 参数、bootArgs offset；
- FSP HAL（`generated/g_kern_fsp_nvoc.c:262-296`）：
  `cotPayloadSignatureSize = 96 / cotPayloadPublicKeySize = 97 / cotPayloadVersion = 2`
  当 chip ∈ `{GB100,GB102,GB10B,GB110,GB112,GB202,GB203,GB205,GB206,GB207,GR100,GR102}`，
  **否则 384/384/1**；
- SEC2 HAL（`generated/g_kernel_sec2_nvoc.c:491-509`）：`384/384`，`cotPayloadVersion`
  按 GB10B(1)/GB20B,GB20C(2)/其它(0) 分档；
- 发送侧 `kfspSetupGspImages()`（`gsp/arch/hopper/kern_fsp_gh100.c:953-1049`）：
  `NV_ASSERT_OR_GOTO(bindataGetBufferSize(sig) == cotPayloadSignatureSize)`、
  `<= sizeof(pCotPayload->signature)`，公钥同理 —— 这是"长度选择错误 ⇒ 明确失败"
  的保护（`NV_ASSERT_OR_GOTO` 的 `goto` 分支**不受 DEBUG/ASSERT_BUILD 影响**，
  见 `inc/libraries/utils/nvassert.h:360-378`）。

### 4.2 版本/算法迁移（RSA-3072 → P-384）

同一容器格式下，签名 section 的大小直接暴露算法：

| 家族 | `signature` 大小 | `publickey` 大小 | 解释 |
|---|---:|---:|---|
| GB100 / GB202 / GR100（FMC） | 96 | 97 | ECDSA P-384（已验签） |
| GH100 / GB10B / GB20B（FMC） | 384 | 384 | RSA-3072 尺寸（未闭合，§4.3） |
| 经典 `.fwsignature_*`（570.144/610.57.04） | 4 KiB/家族 | （未见独立键 section） | 帧内含 384-B 与 96-B 级槽位 |

`arch/nvalloc/common/inc/flcnretval.h` 里同时存在
`BCRT30_RSA3K_SIG_SIZE 384`（`gsp/kernel_gsp_fwsec.c:187`）与 P-384 尺寸的
COT 契约，属于同一迁移期的双形态残留。

### 4.3 未闭合边界：384-byte 路径不是"简单 RSA-on-image"（负结果）

对 `570.144 gh100-fmc` 的 384-B `publickey`/`signature` 做穷举尝试：

- `SHA-384(image) == hash` ✅（48-B 摘要关系成立）；
- 以 `n = publickey`、`e ∈ {3, 17, 65537}` 做 RSA PKCS#1 v1.5（SHA-384/SHA-256）
  对 image 或 stored hash 验签：**全部失败**；
- 各 e 下 `sig^e mod n` 的恢复块既非 PKCS#1 v1.5 结构，末尾也不等于 stored hash。

因此 GH100/GB10B/GB20B 的 384-B 分支**不是**"RSA PKCS#1 v1.5 over 同一 image"，
其被签对象/序列化仍是 UNKNOWN（可能覆盖别的 envelope、或签名槽本身还有包装）。
本报告不把它称为"RSA 已验证"，只报告尺寸与摘要关系。

### 4.4 熔丝与版本驱动的签名/镜像选择

- **debug/prod 开关**：`kgspIsDebugModeEnabled_GB100`（`kernel_gsp_gb100.c:290-298`）
  `= FLD_TEST_DRF(_FUSE_ZB,_OPT_SECURE_GSP_DEBUG_DIS,_DATA,_NO)`
  → 熔丝地址 `0x74C`（`src/common/inc/swref/published/blackwell/gb100/dev_fuse_zb.h:41-45`，
  `DATA:0`，`DATA_INIT=1`）。debug 判定会同时改变：镜像标签（`*_DBG` vs `*_PROD`）、
  签名绑定（`BINDATA_LABEL_SIG_DBG/PROD`）与公钥（debug 键）。
- **ucode 版本熔丝**：`kgspReadUcodeFuseVersion_GB100`（`kernel_gsp_gb100.c:301-323`）
  读 `NV_FUSE_ZB_OPT_FPF_GSP_UCODE1_VERSION`（`0x41C0`，`+4*index`，取
  `HIGHESTBITIDX_32+1`）；SEC2 版读 `NV_FUSE_ZB_OPT_FPF_SEC2_UCODE1_VERSION`
  （`0x4140`，`sec2/arch/blackwell/kernel_sec2_gb100.c:39-55`）。
- **签名挑选**：`s_patchBooterUcodeSignature()`（`gsp/kernel_gsp_booter.c:132-170`）
  `sigSize = signaturesTotalSize / numSigs`；
  `if (numSigs > 1) { if (fuseVer > numSigs-1) → NV_ERR_OUT_OF_RANGE;
  sigIndex = numSigs - 1 - fuseVer; }`，然后把第 `sigIndex` 份签名 patch 进
  `pImage + sigDestOffset`。元数据来自 bindata 标签
  `PATCH_LOC / PATCH_SIG / PATCH_META / NUM_SIGS / SIG_{DBG,PROD}`，并要求
  `patchSig == 0`（`kernel_gsp_booter.c:260-300`）。索引方向是"**新版本号 →
  更靠前的槽**"，与 §3.3 的 4 槽帧结构相容。
- **失败分类（设备侧错误码）**：`FLCN_ERR_HS_CHK_GFW_CHAIN_OF_TRUST_BROKEN=0xC8`、
  `FLCN_ERR_HS_CHK_UCODE_REVOKED=0xA2`、`FLCN_ERR_LS_CHK_UCODE_REVOKED=0x45`、
  `FLCN_ERR_HS_INVALID_KEY=0xD1`、`FLCN_ERR_HS_SWKG_INVALID_SIGNATURE=0xD2`、
  `FLCN_ERR_HS_SCP_LIB_DMHASH_FAILED=0xD3`、`FLCN_ERR_HS_CHK_ENGID_MISMATCH=0xB7`、
  `FLCN_ERR_HS_CHK_BOARD_MISMATCH=0xB9`（`flcnretval.h:116,193-256`）。
  这说明设备侧校验至少覆盖：链式信任、ucode 吊销、engine-id、board 匹配、
  以及一个"工作密钥组（SWKG）签名"层。

### 4.5 主机侧的另一条 P-384 链（必须与 FMC 链区分）

驱动自带 `libspdm 3.5.0`（`src/libraries/libspdm/…`，`RMCFG_MODULE_LIBSPDM=1`），
其中 `SPDM_ALGORITHMS_BASE_ASYM_ALGO_TPM_ALG_ECDSA_ECC_NIST_P384` 分支与
`libspdm_x509_verify_cert_chain()`（`kernel/gpu/spdm/spdm.c:1038`）是**SPDM 证明
/证书链**用途，与 FMC/GFW 镜像验签不是同一条链（后者主机侧无任何实现）。
在 GSP-RM 侧同样能看到 P-384 痕迹（§4.6），但其归属尚未定位，不可直接
等同于 FMC 验证器。

### 4.6 设备侧 P-384 实现的静态痕迹（新增定位）

在三份设备侧二进制里都找到**成组的 P-384/P-256 曲线常数表**（48-byte 大端字段
依次为 `p, p-3(A), b, Gx, Gy, n`，记录内含 64-bit 指针/addend 表，形如
mbedTLS/PSA 的 EC group 描述）：

| 文件 | P-384 `p` 命中偏移（全部命中） |
|---|---|
| `gsp_inner_570144_main.elf` | `0xd68360, 0xd68820, 0xd68d08, 0xd69228` |
| `gsp_inner_19f040_a.elf` | `0xe8aa40, 0xe8af00, 0xe8b3e8, 0xe8b8d0, 0xe8bdb8` |
| `gsp61057_rx_full.bin` | `0xe8ecb8, 0xe8f178, 0xe8f660, 0xe8fb48, 0xe90030` |

每处命中 +0x120 起就是同构的 **P-256** 记录；三个文件里**没有** P-521 /
secp256k1 / brainpool 常数。SHA-384 IV（`6a09e667f3bcc908…`）**没有**匹配到
（说明该实现可能只保留曲线参数，摘要实现另有常量形式）。

同时确认一个**关键负结果**：GB202 FMC prod 公钥的 X/Y 96 字节、96-B 签名、
48-B 摘要，都不出现在
`nvfw_HGX-B300x8_…fwpkg`（111 MB）、Dell/HPE GB202 NVFW、RTX 5090 ROM、
两份 GSP-RM ELF、R570 RX 切片中（逐字节搜索）。即在本地可见的**全部设备侧
制品**里，看不到这把键；它只存在于主机驱动的 bindata 中。

## 5. 候选弱点与解析边界

按"是否能闭合"分三档。所有条目都不构成绕过 5090D/授权策略或刷写路径。

### 5.1 主机先解析、后验证（parse-before-verify）——结构性问题

`.fwsignature_*` / 描述符 / `.fwimage` 的解析发生在**设备验签之前**，且解析器
处理的正是"尚未被认证的字节"。三个具体边界（均给出可机械复算的算式）：

1. **strtab size=0 下的无符号下溢**（`kernel_gsp.c:6150-6153,6165-6166`）：
   `elfSectionNamesTableSize = 0` 时
   `portSafeAddU64(offset, 0-1)` 回绕（`offset-1`）、`0-1 >= name` 恒真
   （`0xFFFFFFFFFFFFFFFF >= name`）、`currentSectionNameMaxLength = 0-name-1`
   也几乎恒真；随后指针 `&pGspBuf[offset + name]` 中 `name` 是 32-bit、完全
   不受 strtab 边界约束 → 描述符可把节名比较指针推到**缓冲区之后最多 ~4 GB**，
   比较会读最多 `strlen(pSectionName)`（如 `.fwsignature_gb20x` 17 字节）。
   实测算式：`offset=0x400000, size=0, name=0x10000000` ⇒ 通过全部检查，
   比较地址=`0x10400000`（越界 256 MB）。
2. **`shstrndx <= shnum` 的 off-by-one**（`kernel_gsp.c:6147`）：ELF 规范允许的
   合法上限是 `shstrndx < shnum`；`== shnum` 时读到的节头起点恰好在已校验区间
   之外 1 byte，越界窗口最大 63 B（`sizeof(LibosElf64SectionHeader)`）。
3. **`NvS16 idx`**（`kernel_gsp.c:6122,6159`）：`shnum-1` 存进 16-bit 有符号
   变量；`shnum > 32768` 时循环体一次都不执行（fail-closed，但意味着
   `shnum>=0x8000` 的合法 ELF 无法取到 section，属健壮性问题而非越权）。
4. **签名长度无上限**（`_kgspCreateSignatureMemdesc`, `kernel_gsp.c:5666-5718`）：
   `NV_ALIGN_UP(pGspFw->signatureSize, 256)` 直接用于分配，`signatureSize` 来自
   节头（受"节数据必须落在文件内"约束，所以上界≈文件大小）；即便不可越界，
   一个 4 KiB 级 section 也能让驱动分配/搬运 4 KiB（这本就是设计），而对
   **重复同名 section** 只取"最后一个"（见 3.5），设备侧若取第一个就形成
   host/device 选择语义差异（无法在本地验证，列为 UNKNOWN）。
5. **`.fwversion` 逐字节等于模块版本字符串**（`kernel_gsp.c:5720-5779`）：这是
   很强的 build 绑定（`NV_VERSION_STRING`），副作用是"官方向后兼容的固件包"
   无法跨小版本复用。另需注意：`.fwversion` 与 `.fwimage`、`.fwsignature_*` 是
   三个**互不重叠**的 section，本报告只能证明 FMC/GFW 容器的签名覆盖自己那个
   image blob；该 ELF 路径上设备到底把哪些 section 纳入验签范围，本地未闭合。

这些点的现实影响是**本地内核态越界读/崩溃（DoS 面）**，需要能替换固件 blob
的权限（root 或固件搜索路径可控方）。它们**不能**用来绕过设备侧验签：设备在
拿到镜像后会独立复核镜像+签名+公钥的对应关系。

### 5.2 host 侧零验证 + 公钥由 host 提供（信任落点必须在设备）

`kfspSetupGspImages()` 只是把 `hash384/publicKey/signature` 拷进 COT payload
（NVDM type `0x14`，见 `parallel/public_fsp_fwupdate_chain.md`），驱动侧没有任何
密码学检查。结合 §4.6 的负结果（设备侧制品里看不到这把键），可推得：

- **要么**设备内部用 fuse/HS-KEK/ROM 里的**键哈希或根**对传入公钥做背书
  （标准做法；`FLCN_ERR_HS_INVALID_KEY=0xD1`、`HS_SWKG_INVALID_SIGNATURE=0xD2`、
  `HS_CHK_BOARD_MISMATCH=0xB9` 与 `NV_FUSE_ZB_OPT_FPF_GSP_UCODE1_VERSION` 支持
  这种设计），**要么**传入的公钥被直接信任（那将是重大设计缺陷）。
- 本地证据**不能**在这两者之间裁决：这是本次审计最大的 UNKNOWN，也是后续
  纯静态实验的首选目标（§6.5）。

### 5.3 debug/prod 是熔丝判定，且两套键并存

`NV_FUSE_ZB_OPT_SECURE_GSP_DEBUG_DIS`（`0x74C`，1 bit，`DATA_INIT=1`）在运行时
决定"用 debug 镜像 + debug 键"还是"prod 镜像 + prod 键"。工程含义：

- 任何能让该熔丝读到 0 的状态，都会把信任面切到 **debug 键**（`9cdd06eb…`）
  与 `*_DBG` 镜像（后者在同一份 bindata 里就可获得，见 §3.1）；
- 该熔丝是 `RWIVF`，语义与流水线/熔丝编程策略强相关；**本报告不提供、也不
  建议任何熔丝读写**，只把"策略开关是运行时熔丝读"这一事实登记为审计边界。

### 5.4 CC 路径的认证材料来源未闭合

- 610 的 CC 分支走 `ConcatenatedFMC_GB202`（503,808 B）+ 92-B 描述符，**没有**
  `UCODE_HASH/UCODE_SIG/UCODE_PKEY` 标签（`g_bindata_kgspGetBinArchiveConcatenatedFMC_GB202.c`
  只有 `BINDATA_LABEL_UCODE_IMAGE_PROD`）。
- 该 blob 的结构：`[0,0x3EC00)` 为 FMC 主体（=manifest 0xA00 + data 0xA900 +
  code 0x33900，与 CC `gfw` 容器 header 的 code/data 尺寸**相同**，但字节不同），
  `[0x3EC00,0x44001)` 为 ~21.5 KB 零填充，之后是另一段高熵材料（含 0x44000 处
  的尺寸/偏移表），总长 503,808。
- 与 CC `gfw` 容器（257,096，可验签 ✅）**不共享字节**，也不共享 hash/签名。
  因此"ConcatenatedFMC 如何被认证"在公开源码 + 本地制品中**无解**（可能由
  FSP/CC 会话在设备内部完成，或由 SPDM 通道另行提供认证材料）。

### 5.5 解析链中"看起来像弱点"但应保持沉默的部分

- `_kgspFwContainerGetSection` 只做前缀匹配要求的 `'\0'` 结尾判断，
  因此 `.fwsignature_gb20x` 与 `.fwsignature_cc_gb20x` 不会互相误配（已核对
  570.144 实际 section 表：两者并存且互不相同）。
- bindata 解压（`utilGzGetData` raw inflate）在长度不符时直接
  `NV_ERR_INFLATE_COMPRESSED_DATA_FAILED`（`kernel/core/bin_data.c:101-116`），
  未见可控堆写。
- 本报告**不**把"签名覆盖整镜像"解读为"镜像内容可以任改"：签名覆盖的是
  *官方镜像*；没有私钥就无法生成新的合法 `(image, hash, sig)` 三元组。

## 6. 3–5 个纯静态下一步实验

1. **`.fwsignature_*` 4 KiB 帧的 schema 矩阵（最高价值）**
   取 570.144（7 份）与 610.57.04（12 份）的 section，做跨家族/跨版本 diff 与
   槽位对齐；用 §4.4 的 `NUM_SIGS / PATCH_SIG / PATCH_META` 语义去验证"每
   0x200 槽 = 一个熔丝版本的签名"假设，并检查槽内是否出现 97-B 点 /
   384-B 模数形态。判定标准：能否把 12 份 section 归约成"同构 4 槽 + 家族参数"。
2. **384-byte 分支闭合（GH100/GB10B/GB20B）**
   对 `gh100-fmc-570.144` 与 610 的 `*_gh100_*`、`*_gb20b_*` 样本穷举更多
   假设：RSA-PSS、raw-digest、对 stored hash 再哈希、对
   `header+manifest` 子区间签名、大/小端模数、指数为 2^16+1 以外的常见值、
   或"签名其实是 ECDSA P-521/Ed25519 尺寸巧合"。若全部失败，就在报告里把它
   固化为"非 PKCS#1v1.5-over-image"的负结论并停止猜测。
3. **主机解析器的合成 ELF 差分/健壮性实验（用户态复现，不加载模块）**
   用脚本复刻 `_kgspFwContainerGetSection` 的判定顺序，构造：
   (a) `shstrndx == shnum`；(b) strtab `size=0` 且 `name=大值`；
   (c) 两个同名 `.fwsignature_gb20x`（一个在表头、一个在表尾）；
   (d) `signatureSize` 极大 / 与实际镜像尺寸不符。
   目标：把 §5.1 的越界窗口、§3.5 的"取最后一个"语义写成可回归的测试向量，并
   量化 `NV_ERR_*` 失败路径覆盖面（纯静态，不接触设备）。
4. **设备侧 P-384/P-256 曲线表的归属定位（GSP-RM 内）**
   在 `gsp_inner_19f040_a.elf`（未 strip、82 MB）里用符号表 + 立即数引用定位
   §4.6 的曲线表 xref，判断它是 (a) libspdm/SPDM 证明、(b) FMC/GFW 镜像验证、
   还是 (c) 别的安全服务；判定依据：调用点附近的字符串
   (`spdm`/`attestation`/`certificate` vs `image`/`manifest`/`hash384`) 与
   结构体字段（`mbedtls_ecp_group` vs 自定义 container 描述）。
5. **HGX baseboard MCU 侧的 SPDM/更新验证链梳理（新发现的方向）**
   `nvfw_HGX-B300x8_…fwpkg` 内存在 MCXN236（Cortex-M33）MCU 固件：字符串
   `mbedtls_ctr_drbg_random failed`、`r signature is zero`、`s signature is zero`、
   `sign verify fail -%x`、`root hash fail %d`、
   `ImageKeyRovocationOptIndex read fail`、`Invalid sec_version %d`、
   `Invalid key_revoke %d`、`MCHP - Replace this region with MCHP Signature -
   Signature algorithm ECDSA-SHA384 Curve P-384`。
   下一步：把该 MCU 镜像的曲线表/验证函数定位出来，和 `PLDM/NVDM 0x12` 更新
   路径（见 `parallel/public_fsp_fwupdate_chain.md`）对齐，回答"baseboard 是否/
   如何为 GPU FW 组件做指纹与吊销判定"，以及 CFPA（`sec_version/key_revoke`）
   与 GPU 侧熔丝是否是同一策略面。

## 7. 未闭合项（UNKNOWN）清单

1. 设备侧 verifier 的**根**：传入公钥是否被 fuse/ROM 键哈希背书，还是被直接
   信任（§5.2）。这决定"host 提供公钥"是设计还是缺陷。
2. 384-byte 分支（GH100/GB10B/GB20B）的被签对象与签名算法（§4.3）。
3. `.fwsignature_*` 4 KiB 帧的正式字段名与"槽 ↔ 熔丝版本"映射（§3.3/§6.1）。
4. `ConcatenatedFMC`（CC 路径）的认证材料来源（§5.4）。
5. GSP-RM 内 P-256/P-384 曲线表的消费者归属（§4.6）。
6. 设备侧对主机提供公钥/签名的**拒收条件**（SKU/board/engine/rollback 计数）
   的精确判据；只知错误码分类（§4.4）。
7. 主机解析器与设备侧解析器对**重复同名 section** 的选择语义是否一致（§5.1-4）。

## 8. 复现命令（只读）

```bash
# 0) 需要先解开的压缩归档（只解到临时目录，不动机器上的 /lib/firmware）
mkdir -p /tmp/fmcaudit && cd /tmp/fmcaudit
zstd -d -q /lib/firmware/nvidia/gb202/gsp/fmc-570.144.bin.zst      -o gb202-fmc.bin
zstd -d -q /lib/firmware/nvidia/gb100/gsp/fmc-570.144.bin.zst      -o gb100-fmc.bin
zstd -d -q /lib/firmware/nvidia/gh100/gsp/fmc-570.144.bin.zst      -o gh100-fmc.bin
zstd -d -q /lib/firmware/nvidia/ga102/gsp/gsp-570.144.bin.zst      -o gsp-570.144.bin

cd /home/user/rt_5090_project/parallel
G=/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src/nvidia/generated

# 1) bindata 四元组 + 离线验签（prod / CC / debug / GH100）
python3 fmc_signature_probe_20260925.py bindata \
  $G/g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c \
  $G/g_bindata_kgspGetBinArchiveGspRmCcFmcGfwProdSigned_GB202.c \
  $G/g_bindata_kgspGetBinArchiveGspRmFmcGfwDebugSigned_GB202.c \
  $G/g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GH100.c

# 2) FMC 容器的 section 表 + 容器头 + 验签
python3 fmc_signature_probe_20260925.py fmc-elf /tmp/fmcaudit/gb202-fmc.bin /tmp/fmcaudit/gh100-fmc.bin

# 3) 经典 ELF64 wrapper 的 .fwimage/.fwsignature_* 结构
python3 fmc_signature_probe_20260925.py gsp-elf /tmp/fmcaudit/gsp-570.144.bin
python3 fmc_signature_probe_20260925.py gsp-elf /usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin

# 4) 92-byte 描述符字段解码
#    需先自行从对应 g_bindata_*.c 的数组里解压出 raw blob（`zlib.decompress(bytes, -15)`，
#    与脚本 `parse_bindata()` 同一路径），再交给 parse-desc
python3 fmc_signature_probe_20260925.py parse-desc <92-byte-desc.bin>
```

脚本仅用 `argv` 指定的普通文件，无 glob、无目录遍历、无网络、无设备访问。

## 9. 一句话结论

GB202/GB100（以及 GR100）的 FMC/FSP 镜像走的是**"整镜像 ECDSA P-384/SHA-384"**
链：签名覆盖容器全部字节，主机只解析、不验证，公钥由主机传入而设备的钉扎与
拒收策略在 fuse/ROM/HS 层；公开材料能给出接口契约（96/97/48 字节）、熔丝选择
逻辑、错误码分类与经典容器的 per-family 4 KiB 签名 section，但**不能**给出设备
侧根的背书方式、384-byte 分支的被签对象、以及 CC 路径的认证来源——这三项是
后续纯静态工作唯一能继续推进的方向。

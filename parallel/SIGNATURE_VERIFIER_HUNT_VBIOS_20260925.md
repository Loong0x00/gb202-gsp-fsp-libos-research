# NVIDIA vBIOS/固件签名校验器：实现定位、覆盖范围与候选弱点（纯静态）

日期：2026-09-25（Asia/Singapore）
状态：**static-only / read-only**，本文只整理本地文件与离线脚本的结论。

## 0. 范围、边界与证据约定

### 0.1 安全边界
- 只读取本机已有文件；**没有联网下载**，没有运行 updater/nvflash/MODS/driver，
  没有访问 GPU、`/dev/nvidia*`、PCI/BAR/MMIO/debugfs，没有 reset、刷写或修改任何
  ROM/NVFW/firmware。
- 本文不包含、也不分析"5090D 算力限制绕过"或任何出口管制规避内容；不包含任何
  刷写步骤。所有结论仅用于防御性静态审计。
- 对 392 MB 的 stripped `mods` ELF 只做了**有界 VA 窗口**的 `objdump`（约
  0x6e93e00–0x6e95600），没有全程序反编译。

### 0.2 证据标签

- **FACT**：本地字节、本地源码行或本地可复算脚本直接支持。
- **INFERENCE**：由多个 FACT 推出，但缺少决定性一步。
- **UNKNOWN**：本地材料不足或依赖不在本地的 GPU 内部代码/密钥。

### 0.3 输入工件与哈希（本地复核）

| 工件 | 路径 | SHA-256 |
|---|---|---|
| RTX 5090 FE ROM（TPU，provenance 未验证） | `vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom` | `a966aca23518708e44c961af865cccfdfabebc9d0cd06a8e29577a0bd82dc5eb` |
| ASUS RTX 5090 ROM（TPU，未验证） | `vbios_diff/unverified_TPU_280522_ASUS_Astral_1043-89E3_98.02.2E.40.85.rom` | `eeb68ef4ce8b70d2f72aa1738b04e89d912c3af977722959e7ca60c1195f1111` |
| Dell RTX PRO 6000 NVFW `98.02.8D.00.01` | `vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw` | `8658724061087279f59ca3a0d8ce443cb4ca52db2543c64723a3cea632a29b59` |
| HPE RTX PRO 6000 NVFW `98.02.9E.00.01` | `vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw` | `98c52f80e937907c4203280824bbef6bb17439c900edc74532072780611c0fe5` |
| Tesla V100 archive ROM | `hulk_public_research_20260811/vbios_history/NVIDIA.TeslaV100.16384.170728_1.archive.rom` | `c45cf4cca3531de82b7b1a587b81f9f31d58e5589fafad0bb431bb95d89d61d8` |
| MODS 570.215 内嵌 RM ELF | `rt_5090_project/mods_audit/static/extracted_inner/mods` | `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf` |
| nvflash 5.877.0 | `vbios_diff/hpe_static_tools/nvflash` | `d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780` |
| GSP 容器 610.57.04 | `/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin` | `c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999` |

开源模块源码版本：`nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules`
`version.mk = 610.43.03`。

---

## 结论摘要

1. **FACT：开源内核模块里不存在 vBIOS 密码学校验器。**
   `kernel-open/nvidia/internal_crypt_lib.h` 及其 `lkca_*` 实现只被
   `kernel-open/nvidia/libspdm_*` 使用（SPDM 设备证明），没有被任何
   vBIOS/GSP/FMC 校验路径引用。开源驱动对 vBIOS 只做**结构解析、搬运和
   版本选择**。
2. **FACT：vBIOS→FWSEC 的搬运路径只存在于 TU102..AD107。**
   `kgspExtractVbiosFromRom_HAL` 对 GB100/GB20x/GH100/GR100 等一律落到
   `kgspExtractVbiosFromRom_395e98`，直接 `return NV_ERR_NOT_SUPPORTED`
   （`g_kernel_gsp_nvoc.h:1997`，dispatch `g_kernel_gsp_nvoc.c:1402`）。
   `kgspInitRm` 把 `NV_ERR_NOT_SUPPORTED` 当成功继续（`kernel_gsp.c:4947-4951`）。
   因此 Blackwell 上开源驱动**从不读 vBIOS 的 FWSEC 对象**。
3. **FACT：GB202 vBIOS 里仍有 Falcon 表，但没有 FWSEC app。**
   四个 canonical GB202 镜像的 BIT 表（FE/ASUS@`0x38df0`，Dell/HPE@`0x3bdf0`）
   指向的 Falcon v1 表含 35 个 entry；与安全相关的是 `app=0x24/target=0x0f`
   的 `FSP_RUN` v6 加密对象（`flags=0x0d`，descriptor `+0x50`，`word1` 长度）。
   没有任何 `0x05/0x45/0x85` FWSEC/FWSECLIC entry。vBIOS 校验在 Blackwell 上
   发生在 FSP/Booter/FWSECLIC 内部，不由主机驱动执行。
4. **FACT（本次离线复算）：Blackwell GSP-FMC 的 COT 校验是 ECDSA P-384/SHA-384。**
   从 `g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_*.c` 解出并复算：
   - GB202 prod：image 287304 B，`SHA-384(image) == UCODE_HASH`（48 B）；
     `UCODE_SIG` 96 B（raw r||s）、`UCODE_PKEY` 97 B（未压缩 P-384 point）三者
     构成完整可验证的 ECDSA P-384 签名；
   - GB202 **debug**、GB100 prod、GR100 prod 同样验证通过；
   - GB100 prod 与 GB202 prod **公钥逐字节相同**
     （`sha256=af870e5dde972840588bfb94a87f94b19ad6659dae6e1343dd0d22f16074ba39`），
     GB202 debug 与 GR100 各自不同；
   - GH100 `UCODE_SIG/PKEY` 为 384/384 B（RSA-3072 形状），`SHA-384(image) ==
     UCODE_HASH` 成立，但用 big/little-endian modulus、e∈{3,17,65537} 的
     textbook RSA 都不能解出 PKCS#1 v1.5 块 → **GH100 密钥编码/签名序列化
     UNKNOWN**。
5. **FACT：GSP-RM 镜像（`gsp_ga10x.bin`）由主机按 ELF section 名取出
   `.fwimage` + `.fwsignature_<family>` 交给 GPU；主机侧不做密码学校验。**
   610.57.04 容器有 12 个 `.fwsignature_*` section，每个 4096 B；每个 section
   只有 4 个 384 B 槽（`0x14/0x214/0x414/0x614`）与 1 个 per-family 字节
   （`0x81a`）在不同 family 间不同，其余字节完全相同。
6. **FACT：专有 RM（MODS 内嵌）里存在一个主机侧 vBIOS 签名校验器**，其错误
   信息形成了一个可枚举的检查清单：hash header 版本/flags、hash entry 类型与
   边界、"VBIOS image hash 起始点"、"preservation table hash"、signature
   header/format/digest algo、signature size vs hash size、X509 证书链/OEM
   名称/有效期、`VBIOS Signature verification failed`。
7. **FACT：历史 GPU 侧校验器（V100 FIRMWARE_SEC_LIC）使用 RSA-1024 +
   DMOVERAES128（AES-128 Davies–Meyer）**，签名的期望块是精确的
   `00 01 || FF×109 || 00 || digest[16]`；其"被签名 ROM 段"由 ucode 内部
   parser 选择，主机模型只覆盖逻辑 ROM 的 57.1%，且 digest 复现失败（见 §1.7）。
8. **候选弱点集中在：BIT/desc 等"定位元数据"不在签名字节内、版本/回滚选择
   的两套相反约定、单签名归档跳过 fuse 版本检查、签名长度由归档自描述、
   GSP-RM 容器 section 选择（重名取最高 index、`shstrndx <= shnum` off-by-one）、
   以及历史 RSA-1024/AES-128 摘要。** 详见 §3。

---

## 1. 校验调用路径与所校验的字节范围

### 1.0 总览

| # | 路径 | 执行者 | 主机是否做密码学校验 | 校验对象/字节范围 |
|---|---|---|---|---|
| A | vBIOS → BIT → Falcon 表 → FWSEC V2/V3 → FRTS/SB | 主机解析 + Falcon BROM/FWSEC | 否 | V3：`[desc+44, desc+descSize)` 的 384 B 签名 + ucode image；V2：无显式签名字节交给主机 |
| B | Booter Load/Unload/Scrubber bindata patch | 主机 patch + SEC2/NVDEC0 Booter | 否 | `patchLoc` 处 384 B(RSA-3K) 或 16 B(TU/AES) |
| C | GSP-FMC COT payload | FSP/SEC2 Booter | 否 | `hash384 = SHA-384(UCODE_IMAGE)`；sig/key 由主机提供 |
| D | GSP-RM `.fwimage` + `.fwsignature_<family>` | GPU Booter/FMC | 否（仅 `.fwversion` 字符串比较） | 4×384 B 槽位；精确消息/算法 UNKNOWN |
| E | 主机/更新工具与专有 RM vBIOS verifier | x86 RM / nvflash / updater / ERoT | 是（专有代码） | hash-entry 描述的范围 + preservation table + X509 |
| F | GPU 内 FWSECLIC `CMD_VBIOS_VERIFY_*`（历史 V100 可直接分析） | FWSECLIC ucode | —（在 GPU 上） | V100：RSA-1024 公钥运算 + DMOVERAES128(parser-selected segments) |

### 1.1 Path A：vBIOS→FWSEC→FRTS/SB（TU102..AD107）

**触发**：`kgspInitRm_IMPL`（`kernel_gsp.c:4914-4965`）。

1. `kgspExtractVbiosFromRom_HAL`（Turing/Ampere/Ada → `kgspExtractVbiosFromRom_TU102`）
   - `s_getBaseBiosMaxSize_TU102` = **1 MiB**（`kernel_gsp_vbios_tu102.c:423-429`）。
   - `s_romImgReadGeneric`（同文件 108-170）对 `baseOffset+offset+sizeBytes` 与
     `maxOffset` 做 `portSafeAddU32` 溢出/越界检查。
   - `s_locateExpansionRoms`（274-400）走 PCI ROM/PCIR/PCI Data Extension 链，
     取 `biosSize`、`expansionRomOffset`；ROM image 整体复制进
     `pVbiosImg->pImage`（约 440-569）。
   - 若 `biosSizeFromRom > 1 MiB` → 报错退出（不是截断）。
2. `kgspParseFwsecUcodeFromVbiosImg`（`kernel_gsp_fwsec.c:1110-1158`）
   - `s_vbiosFindBitHeader`（404-461）：**线性扫描整幅 image**，匹配
     `u16 Id==0xB8FF` + `u32 "BIT\0"`，然后校验
     `sum(header[0..HeaderSize]) & 0xFF == 0`。**只有 8-bit 和校验。**
   - `s_vbiosParseFwsecUcodeDescFromBit`（467-698）：
     - BIT header 12 B：`Id,Signature,BCD_Version,HeaderSize,TokenSize,TokenEntries,HeaderChksum`；
     - token 大小 6/8 B（`2b2w`/`2b1w1d`）；
     - 找 `TokenId=0x70 (FALCON_DATA) version=2`，读 `DataPtr` 处 u32
       `FalconUcodeTablePtr`；
     - 在 `expansionRomOffset + FalconUcodeTablePtr` 读 Falcon v1 表：
       6 B header + `EntryCount × EntrySize(6 B)` 的 `(ApplicationID,TargetID,DescPtr u32)`；
     - app ID：`0x05 FIRMWARE_SEC_LIC`、`0x45 FWSEC_DBG`、`0x85 FWSEC_PROD`
       （宏定义 129-132）；debug/prod 由
       `kgspIsDebugModeEnabled_HAL` 选择，TU102 实现读
       `NV_FUSE_OPT_SECURE_GSP_DEBUG_DIS`（`kernel_gsp_tu102.c:93-104`）；
     - 读 desc 首 u32 `vDesc`（flags[7:0]/version[15:8]/size[31:16]），
       只接受 V2(size≥60) 或 V3(size≥44)。
3. **V2 desc（60 B）路径** `s_vbiosFillFlcnUcodeFromDescV2`（706-872）：
   - `codeOffset = descOffset+descSize`，`imemSize=IMEMLoadSize`，
     `dataOffset=DMEMOffset`，`dmemSize=DMEMLoadSize`，读取 image 字节；
   - boot type = `KGSP_FLCN_UCODE_BOOT_WITH_LOADER`，**没有 `pSignatures`**。
   本目录可观察到的 V100/Turing/A100 FWSEC 样本都是 V2（`vdesc=0x3C0001`），
   即主机不搬运任何独立签名字节；该路径的认证责任落在 loader/BROM 与 ucode
   自身引用上。
4. **V3 desc（44 B header + 尾随签名）路径** `s_vbiosFillFlcnUcodeFromDescV3`
   （878-1010）：
   - `pUcode->size = RM_ALIGN_UP(pDescV3->StoredSize, 256)`（912）；
   - `pUcode->hsSigDmemAddr = pDescV3->PKCDataOffset`（924）；
   - `sigSize = BCRT30_RSA3K_SIG_SIZE = 384`（189/930）；
   - `sigCount = SignatureCount`，`vbiosSigVersions = SignatureVersions`（931/933）；
   - **签名材料** = `pImage[descOffset+44 .. descOffset+descSize)`
     （`signaturesTotalSize = descSize - 44`，985-994）；
   - **ucode image** = `pImage[descOffset+descSize .. +size)`（938-946、1000-1006）；
   - 越界检查只保证 `imageOffset+size ≤ biosSize`、
     `dataOffset+hsSigDmemAddr+384 ≤ size`（938-978）。
5. **FRTS/SB 执行** `s_prepareForFwsec_TU102`
   （`kernel_gsp_frts_tu102.c:274-450`）：
   - `ucodeVersionVal = 1 << kgspReadUcodeFuseVersion_HAL(pGpu,pKernelGsp,ucodeId)`（357-359）；
     GA100/GB100 的 fuse 读法都是 `HIGHESTBITIDX_32(fuseVal)+1`
     （`kernel_gsp_ga100.c:59-79`、`kernel_gsp_gb100.c:308-330`），即版本号；
   - `hsSigVersions = pUcode->vbiosSigVersions`（u16 位图）；
   - 若 `(ucodeVersionVal & hsSigVersions)==0` → `NV_ERR_NOT_SUPPORTED`（fail-closed）；
   - 循环把两个值右移直到对齐，按"低于目标版本且存在"的位数累加
     `sigOffset += (hsSigVersions&1)*384`（367-378）；
   - 检查 `sigOffset+384 ≤ signaturesTotalSize` 后，把对应 384 B 复制到
     `pMappedData + hsSigDmemAddr`（`pMappedData = image + dataOffset`，396-397）；
   - 之后 `kgspExecuteFwsec_TU102` 触发 Falcon 执行；**真正的 RSA-3K 校验在
     BROM/FWSEC（不在开源源码内）**。
   - `s_vbiosPatchInterfaceData` 会在认证前把 FRTS/SB 命令结构写进 DMEM
     interface 区（280-450），说明 DMEM 的 interface 字节是被主机修改后
     才交给执行环境的。

### 1.2 Path B：Booter Load/Unload/Scrubber 的 bindata 签名 patch

**代码**：`kernel_gsp_booter.c`
- `s_patchBooterUcodeSignature`（132-171）；
- `s_allocateUcodeFromBinArchive`（174-430），入口
  `kgspAllocateBooterLoadUcodeImage/Unload/Scrubber`（432-490）。

**流程（FACT）**
1. 从 bindata archive 取 `HEADER_DBG/PROD`、`IMAGE_DBG/PROD`、`SIG_DBG/PROD`、
   `PATCH_LOC`、`PATCH_SIG`、`PATCH_META`、`NUM_SIGS`。
2. `header` 9×u32：`osCodeOffset,osCodeSize,osDataOffset,osDataSize,numApps,
   appCodeOffset,appCodeSize,appDataOffset,appDataSize`；要求 `numApps==1`。
3. `patchSig` 必须为 0（272-277），`numSigs>0`，`signaturesTotalSize % numSigs == 0`（298-302）。
4. `sigSize = signaturesTotalSize/numSigs`；`fuseVer =
   ksec2ReadUcodeFuseVersion_HAL(...)`（同为 `HIGHESTBITIDX_32+1`）：
   - `if (numSigs > 1) { if (fuseVer > numSigs-1) → NV_ERR_OUT_OF_RANGE;
     sigIndex = numSigs-1-fuseVer; }`（158-166）；
   - **`numSigs == 1` 时完全不检查 `fuseVer`**，`sigIndex` 保持初值 0。
5. Boot-from-HS 路径：`pUcode->hsSigDmemAddr = patchLoc - pUcode->dataOffset`
   （329，纯 u32 减法，无 `patchLoc>=dataOffset` 检查），把选中的 `sigSize`
   字节复制到 `pMappedUcodeMem + patchLoc`（355-370 / 405-415）。
6. 之后由 SEC2/NVDEC0 上的 Booter 用 PKC/fuse 校验。

**本地 bindata 实际值（本次解压 raw-deflate 后 FACTS）**

| archive | patch_loc | meta (fuseVer,engineId,ucodeId) | numSigs | 单签名大小 | header `osDataOff/osDataSize` |
|---|---:|---|---:|---:|---:|
| BooterLoad AD102 | `0x7e10` | (1,1,3) | 2 | 384 | `0x7e00/0x6000` → `hsSigDmemAddr=0x10` |
| BooterLoad GA102 | `0x8a10` | (1,1,3) | 2 | 384 | `0x8a00/0x6200` → `0x10` |
| BooterLoad GA100 | `0x8900` | (0,1,3) | 1 | 384 | `0x8700/0x6400` → `0x200` |
| BooterLoad TU102 | `0x8700` | (0,1,13) | 1 | **16**（`..._tu102_aes_sig.h`） | `0x8500/0x6200` → `0x200` |
| BooterUnload AD102 | `0x5010` | (1,1,3) | 2 | 384 | — |
| Scrubber AD10X | `0x1a00` | (1,1,13) | 2 | 384 | — |

`SIG_PROD`/`SIG_DBG` 在 GA102 文件中被 raw-deflate 压成 420/418 B；解压后是
768 B。**若不按 `BINDATA_FLAG_COMPRESSED` 解压会把 420 B 误当成签名长度**。

### 1.3 Path C：GSP-FMC COT（Blackwell/Hopper 的固件签名路径）

**结构**（`src/nvidia/inc/kernel/gpu/fsp/kern_fsp_cot_payload.h:47-55`）：

```c
typedef struct { ... NvU32 hash384[12]; NvU32 publicKey[96]; NvU32 signature[96]; } NVDM_PAYLOAD_COT;
```

**主机行为**
- `ksec2SetupGspImages_GB20B`（`kernel_sec2_gb20b.c:710-800`）/`_GB10B`（400-510）/
  `kfspSetupGspImages`（`kern_fsp_gh100.c:955-1050`）：
  `UCODE_IMAGE` → sysmem；`UCODE_HASH` → `hash384[12]`（48 B）；
  `UCODE_SIG`/`UCODE_PKEY` → `signature/publicKey`；
  `NV_ASSERT_OR_GOTO(bindataGetBufferSize(...) == cotPayload*Size)` 是真运行时
  检查（`NV_ASSERT_OR_GOTO` 在 release 也执行 `goto`，见
  `src/nvidia/inc/libraries/utils/nvassert.h:378/413-423`）。
- 算法/长度由 HAL 字段决定（`g_kern_fsp_nvoc.c:262-289`）：
  GB100/GB102/GB10B/GB110/GB112/**GB202**/GB203/GB205/GB206/GB207/GR100/GR102
  → sig 96、pubkey 97（ECDSA P-384）；默认（含 GH100 等）→ 384/384（RSA-3072）。

**本次离线复算（FACT）**

| archive | image size | SHA-384(image)==stored hash | sig / key | 验证结果 |
|---|---:|---|---|---|
| GB202 prod | 287304 | ✅ | 96 / 97 | ECDSA P-384 verify OK |
| GB202 debug | 287304 | ✅ | 96 / 97 | ECDSA P-384 verify OK |
| GB100 prod | 197960 | ✅ | 96 / 97 | ECDSA P-384 verify OK |
| GR100 prod | 198472 | ✅ | 96 / 97 | ECDSA P-384 verify OK |
| GH100 prod | 165448 | ✅ | 384 / 384 | textbook RSA(e∈{3,17,65537}, 两种端序) 未解出 PKCS#1 v1.5 → UNKNOWN |

GB100 prod 与 GB202 prod 的 97 B 公钥相同；因此 GB100/GB202 共用同一把生产
P-384 密钥。GR100 使用另一把；debug 另一把。

### 1.4 Path D：GSP-RM 容器的 `.fwsignature_<family>`（主机只搬运）

- `_kgspPrepareGspRmBinaryImage`（`kernel_gsp.c:5828-5900`）：
  `_kgspFwContainerVerifyVersion`（5720-5768）只把 `.fwversion` 字符串与驱动
  `NV_VERSION_STRING` 比较；取 `.fwimage`（`GSP_IMAGE_SECTION_NAME`）和
  `.fwsignature_`+family（`GSP_SIGNATURE_SECTION_NAME_PREFIX`）或
  `.fwsignature_cc_`+family（CC）写入 `pSignatureMemdesc`。
- family 名：`nv_firmware_chip_family_to_string`（`nv-firmware.h:56-66`）；
  GB2XX 在 `gpuImpl >= GPU_IMPLEMENTATION_GB20B` 时是 `gb20y`，否则 `gb20x`
  （`nv-firmware-chip-family-select.h:58-69`）。GB202 属 `gb20x`。
- section 选择：`_kgspFwContainerGetSection`（`kernel_gsp.c:6098-6210`）
  **从 `shnum-1` 递减遍历**，返回**索引最高的重名 section**；边界检查里
  `shstrndx <= shnum` 是 off-by-one（`shstrndx == shnum` 时会读到 section
  header 表之外的一个 64 B header）。
- 610.57.04 `gsp_ga10x.bin`（本地，FACT）：ELF 有 `.fwimage`（`0x505b000` B）
  和 12 个 `.fwsignature_*`，每个 `0x1000` B。每个 section：
  `0x14/0x214/0x414/0x614` 是 4 个 384 B 高熵槽位，段间是 128 B 零区；
  `0x81a` 处 1 B 在 family 间不同（ga10x/ad10x/gb10y = `0x01`，其余 `0x02`）；
  其余全部字节在 12 个 family 间**完全相同**。
- 逐版本比较（本地 4 份副本，其 `.fwversion` 分别为 `610.53`、`610.57.01`、
  `610.57.04`、`610.57.01`；包含 Windows 包 610.74/610.88）显示 `.fwimage`
  与 4 个槽位字节都随版本变化；**没有观察到跨版本签名复用**。
- 该 4 槽位与 Path B 的 “numSigs/fuse 版本选择” 形状一致，但签名算法、消息
  序列化、公钥/根来源都不在本地开源材料里 → UNKNOWN。
- 并行姊妹报告 `parallel/SIGNATURE_VERIFIER_HUNT_FSP_20260925.md`（FSP/FMC
  主线，独立探针）对同一批 FMC 样本给出相同的 P-384 公钥哈希与
  `SHA-384(image)==hash`/ECDSA 验证结果，并对 FMC 镜像的 72 B header、
  `GspRmBoot` 描述符、经典 ELF section 选取与 host 零验证路径给出了更细的
  机器证明；两份报告在 FMC 部分互为独立复现，在 vBIOS 部分本文为主。

### 1.5 Path E：主机/更新工具与专有 RM 的 vBIOS verifier

**专有 RM（MODS 570.215 内嵌 x86-64 ELF）**：本次定位到一个有界 vBIOS 校验
函数区域 `VA 0x6e94400–0x6e95500`（文件 offset = VA − `0x400000`），字符串池
`VA 0x8ee1b00–0x8ee2210`。检查清单（消息按 VA 排序，FACT）：

```text
8ee1de8 NVRM: Unhandled Hash Header version: %x
8ee1e18 NVRM: Hash Header flag set to %u. Expecting 0.
8ee1e48 NVRM: No Expansion ROM found.
8ee1e68 NVRM: Hash entry goes past the PCI block size.
8ee1e98 NVRM: Unknown Hash entry type: %x
8ee1ec0 NVRM: We should have started the VBIOS image hash at this point.
8ee1f08 NVRM: We should have started the preservation table hash at this point.
8ee1f58 NVRM: Invalid signature header version.
8ee1f88 NVRM: Signature Verification - Unknown digest algo: %u
8ee1fc0 NVRM: Unknown signature format: %u
8ee1fe8 NVRM: Invalid signature size. Signature Size: %u VBIOS Hash Size: %u
8ee2030 NVRM: VBIOS Signature verification failed.
8ee2060 NVRM: Preservation table signature verification failed. If this is a bringup board you can ignore this message. ...
8ee2108 NVRM: Unable to find validity period in the X509 certificate.
8ee21d0 NVRM: X509 Certificate chain of trust verification failure.
8ee2210 NVRM: Vbios hash size is inconsistent with the buffer.
8ee1c..  X509/PEM/certificate/vendor/OEM 名称相关消息
```

有界反汇编显示（FACT）：
- hash table entry 步长 **12 B**，entry 首 dword 的高字节是主类型
  （`0x70`、`0xE0` 被识别，其它 → `Unknown Hash entry type`）；`0x70` 类还有
  以 dword 第 2 字节为索引的 **17 项跳转表**（VA `0x108b7168`）。
- 校验器显式跟踪 “VBIOS image hash 起点” 和 “preservation table hash 起点”
  是否出现过（对应 `0x6e9494a`/`0x6e95196` 两个失败点）。
- 签名记录检查：`cmpl $0x1,(%r14)`（header version==1）、
  `test $0x10003,0x8(%r14)`（digest algo ∈ bit0/bit1/bit16，否则报
  "Unknown digest algo"）、`test $0x3,0xc(%r14)`（signature format ∈ 1/2）、
  以及 `movabs $0x1000000080; cmp %rax,0x10(%r14)` 的 64-bit 精确匹配
  （失败时报 "Invalid signature size. Signature Size: %u VBIOS Hash Size: %u"）。
- 之后调用 `0x6e93fd0` 做实际验签（内部实现未展开）；
  X509 证书链/有效期/OEM 名称是独立的一层。

**nvflash 5.877.0 / Dell PRO6000 updater**（本地 strings，FACT）：

```text
Falcon secure load failed, invalid AES signature.
Falcon secure load failed, invalid RSA3K signature.
BCRT_ERROR_CODE_CERT20_BIT_TABLE_NOT_FOUND / CERT20_BIT_2_VDPA_* / CERT30_...
BCRT: Start Certificate 2.0 verification
Certification chain validation failed, invalid cert found.
VBIOS verification failed, NV_STATUS_ERR_CODE_EROT_VERIFY_FW_FAILED.
Verify data by checking the vbios image and data security.
```

Dell `RTXPRO6000_98.02.8D.00.01_FW_upgrade.bin`（100 MB x86-64 ELF updater）的
字符串与 nvflash 基本同源（偏移略有不同），说明主机/更新侧的 BCRT
cert20/cert30、VDPA/HAT、ERoT 校验是共享代码路径。BCRT/VDPA/HAT 的精确
覆盖范围与 trust root 闭合问题，沿用先前静态报告
`parallel/bcrt_manifest_coverage.md`、`parallel/nvfw_auth_layout.md` 的
结论（两层 SHA-384 关系已精确闭合到 v6 envelope 与其 hash table，但未闭合到
设备 pin 的 root）。

### 1.6 Path F：GPU 内 FWSECLIC 的 `CMD_VBIOS_VERIFY_*`（现代部分 + 历史 V100）

**现代 enums（FACT，来自 GSP-RM inner ELF strings）**
`gsp_inner_570144_main.elf` / `gsp_inner_19f040_a.elf` 含：

```text
NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_BIOS_SIG_FAIL
NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_CERT_NOT_FOUND / CERT_PARSE_FAIL / CERT_VERIFY_FAIL
NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_DEVID_FAIL / HAT_FAIL
NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HULK_INIT_FAIL / KA_NOT_FOUND / SIG_INVALID / TYPE_INVALID
NV_FWSECLIC_ERR_CODE_BCRT2X_VDPA_INTBLK_* / CERT20_* / CERT21_* / BOOTLOADER_UCODE_HASH_MISMATCH
NV_FWSECLIC_ERR_CODE_BOOTLOADER_INTERFACE_HASH_MISMATCH /	FALCON_INVALID / INTERFACE_NOT_FOUND
```

这证明 FWSECLIC 同时负责 vBIOS 签名/证书/DEVID/HAT、BCRT2X/VDPA 和 bootloader
hash。现代具体实现位于 FSP/FWSECLIC 保护代码内，本地不可反汇编。

**历史 V100 FIRMWARE_SEC_LIC（可直接分析，FACT）**
- 样本：`vbios_history/v100_fwseclib/`（extraction manifest SHA-256 齐全）。
- 终端门 `0x5540`：
  - 从 `D[0x404c]+0x2c` 取 128 B（modulus）、`+0xac` 取 4 B（exponent=65537）；
  - 从 `D[0x4474]` 取 128 B（signature）；
  - 构造期望块：`00 01 || FF×0x6d(109) || 00 || DMOVERAES128_digest[16]`；
  - 经引擎 RSA 公钥运算后做 **128 B 全量字节比较**（`lcall 0x2083`）。
- `tools/verify_v100_isbn_rsa.py` 本地复算：`rsa_encoding_valid=True`，
  signed digest = `614400cd647cbe5d6c30581f9644ec29`。
- 被签名的 ROM 段由 ucode 内 parser（`0x4d93`/`0x5473`/`0x52bb`）按
  `0x3e002` 的 18 条 descriptor 选择；本地 host 模型得到 13 段、
  184635 B（逻辑 ROM 0x4f000 = 323584 B 的 **57.1%**），最后覆盖到
  `0x3d72b`，尾部 `0x118d5` 不在模型覆盖内；**digest 复现不匹配**
  （host 模型 `43b69409…` vs 签名内 `614400cd…`）→ 精确 signed range 仍是
  UNKNOWN。
- V2 descriptor 的 FWSECLIC image 本身（logical `0x32840`，43172 B）落在上述覆盖段内；
  RSA key object（raw `0x3dc70` = logical `0x3d270`）落在 class-0x10 record 段
  `[0x3d254,0x3d72b)` 内；而 RSA signature（raw `0x3e12b` = logical `0x3d72b`）
  恰好从覆盖段末端的下一个字节开始，**不在这个 host 模型覆盖集合内**（这符合
  "签名本身不被签名覆盖"的结构，但精确 parser 集合仍需 §4.1 验证）。

---

## 2. 明确不在（主机可见）签名字节覆盖内的字段/结构

> 说明：本节区分"主机交给 GPU 的签名字节范围"与"GPU 内部实际哈希覆盖范围"。
> 后者大多不可见；凡不可见者标 UNKNOWN。**不要把前者当成完整信任范围。**

### 2.1 BIT / ROM 定位层（Path A）

- **FACT**：BIT header 12 B（`Id`、`"BIT\0"`、`BCD_Version`、`HeaderSize`、
  `TokenSize`、`TokenEntries`、`HeaderChksum`）只有 8-bit 加和校验，
  不参与任何密码学校验；`s_vbiosFindBitHeader` 对整幅 image 暴力扫描。
- **FACT**：BIT tokens（`TokenId/DataVersion/DataSize/DataPtr`）、Falcon 表
  header（6 B）、Falcon entry（`ApplicationID/TargetID/DescPtr`）都是
  "定位元数据"，决定主机选择哪一个签名对象；它们本身不在
  `pSignatures` 字节内。
- **FACT**：ucode image 的读取与签名材料读取都依赖这些 offset；驱动只做
  算术溢出与 image 边界检查。

### 2.2 FWSEC desc 层（Path A / V3）

- **FACT**：主机复制给 GPU 的签名材料恰好是
  `[descOffset+44, descOffset+descSize)`。以下 44 B desc header **不在**该
  字节区间内：
  `StoredSize, PKCDataOffset, InterfaceOffset, IMEMPhysBase, IMEMLoadSize,
  IMEMVirtBase, DMEMPhysBase, DMEMLoadSize, EngineIdMask, UcodeId,
  SignatureCount, SignatureVersions, Reserved`。
- **FACT**：主机用 `PKCDataOffset` 决定签名写入 DMEM 的地址、用
  `StoredSize` 决定 image 长度、用 `IMEM/DMEM*` 决定加载布局。
- **UNKNOWN**：BROM/FWSEC 的哈希/签名是否覆盖这 44 B（或其中一部分）。
  若只覆盖 IMEM/DMEM 代码，则这些字段在旧架构上是可伪造的"加载元数据"。
- **FACT**：V2 desc（60 B）没有独立签名尾；主机不搬运 `pSignatures`，其
  认证必须来自 loader/BROM/ucode 自身引用（V100 的 key/sig 对象在 image
  之外的 ROM 段）。
- **FACT**：`s_vbiosPatchInterfaceData` 在认证前修改 DMEM 的 interface/命令
  缓冲；若 BROM 哈希包含被修改的 DMEM 字节，签名会失败；因此 BROM 的哈希
  范围要么排除这些地址，要么 ucode 的签名字节/接口布局另有约定。**具体范围
  UNKNOWN**。

### 2.3 COT payload 层（Path C）

- **FACT**：`hash384` 精确等于 `SHA-384(UCODE_IMAGE)`（本次实算）。
- **FACT**：`version/size/gspFmcSysmemOffset/frts*`、`gspBootArgsSysmemOffset`
  等结构字段不在 `hash384` 覆盖内；`publicKey/signature` 本身当然也不是被哈希
  对象。
- **UNKNOWN**：`publicKey` 是否必须匹配 fuse/OTP 中的 key 摘要；驱动的
  `cotPayloadVersion=1/2` 与 `PDB_PROP_KFSP_FSP_FUSE_ERROR_CHECK_ENABLED`
  只说明存在 fuse 相关检查，不证明覆盖面。
- **UNKNOWN**：签名消息是否只是 48 B digest，还是包含其它 COT 字段的
  serialization（GH100 的 RSA 复算失败提示后者可能成立）。

### 2.4 GSP-RM 容器层（Path D）

- **FACT**：`.fwversion` 只与驱动版本字符串做相等比较（功能性检查，非安全
  校验）。
- **FACT**：`.fwimage` 与 `.fwsignature_<family>` 的配对由主机按名字完成，
  主机不验证二者关系。
- **FACT**：4 个 384 B 槽位之后的 `0x794..0x81b` 元数据区（含 family 间唯一
  不同的 1 B @`0x81a`）不在签名槽位内；其语义未定义。
- **UNKNOWN**：签名算法（RSA-3K? 其它?）、精确 signed range、是否覆盖
  `.fwversion`/section headers、以及公钥/根来源。

### 2.5 BCRT/VDPA/HAT（Path E / F）

- **FACT（本仓库先前精确复算）**：GB202 的 Falcon v6 envelope 由
  `raw0=0x22, length=0x50+word1, SHA-384(envelope)` 的 entry 覆盖；该
  两-entry hash table 又被 nested image `+0x209` 的 SHA-384 覆盖。
- **FACT**：v6 descriptor 末尾仍有 28 B opaque；NVFW 外层 `0xa00` opaque 区
  在 FE/ASUS 间逐字节相同，不可能是覆盖主体每个 byte 的 content-specific
  digest。
- **UNKNOWN**：该 digest 的正式签名 serialization、X509/BCRT cert30 与
  device-pinned root 的闭合、以及哪些 ROM 区域不在任何 HAT/VDPA entry 内。
  见 `parallel/bcrt_manifest_coverage.md` §6。

### 2.6 V100 ISBN 层（Path F）

- **FACT**：host 模型只覆盖逻辑 ROM 的 57.1%（13 段），且 digest 不匹配。
- **UNKNOWN**：真正的 parser-selected segment 集合、段顺序、hash 余数/长度
  块与 SCP/AES byte lane 语义；因此"未覆盖字段清单"无法对该样本闭合。

---

## 3. 候选弱点清单（每条附证据与不确定度）

> 严重度按"若 GPU 内部实现如最坏假设"评估；多数条目最终安全性依赖不可见的
> BROM/FSP/FWSECLIC 行为，故列表用于指导后续静态/离线验证，不代表已可利用。

### W1. BIT 表/offset 不受签名保护，8-bit 校验和 + 全图暴力扫描

- **证据（FACT）**：`kernel_gsp_fwsec.c:404-461`（扫描 + `checksum&0xFF==0`）、
  `462-700`（token/表/desc 指针全部来自未签名字节）。
- **影响（INFERENCE）**：攻击者若能让驱动读到被改写的 ROM（如
  `romOverride`/`-gpubios` 类主机路径、或本地 SPI 镜像），可以改变驱动
  "选中哪一个已签名对象、以及把它按什么布局装载"。
- **不确定度（UNKNOWN）**：BROM/FWSEC 是否对 desc/接口做二次哈希。若覆盖充分，
  此弱点只造成 DoS/选择偏差；若只覆盖 IMEM/DMEM 代码，则升级为可伪造加载
  布局（见 W2）。

### W2. V3 44 B desc 不在主机搬运的签名字节内

- **证据（FACT）**：`kernel_gsp_fwsec.c:980-994`（签名范围 = desc 尾）、
  `878-1010`（用 desc 字段决定 image/sig/DMEM 布局）。
- **影响（INFERENCE）**：`PKCDataOffset` 可指向 ucode image 内任意位置，
  `StoredSize`/`IMEM*`/`DMEM*` 可改变实际执行布局；签名仍然只针对
  NVIDIA 签过的 image 字节。
- **不确定度（UNKNOWN）**：BROM 是否把这些字段纳入哈希。

### W3. 版本/回滚选择存在两套相反约定，且单签名归档跳过 fuse 检查

- **证据（FACT）**
  - FRTS 路径：`ucodeVersionVal = 1 << fuseVer`，与
    `SignatureVersions` 位图对齐后按 rank 选签名
    （`kernel_gsp_frts_tu102.c:357-378`）；
  - Booter patch：`sigIndex = numSigs - 1 - fuseVer`（降序）
    （`kernel_gsp_booter.c:158-166`）；
  - **`numSigs == 1` 时 `fuseVer` 完全不检查**（`144-166`）；本地
    TU102/GA100 BooterLoad 正是 `numSigs=1`；
  - `HIGHESTBITIDX_32+1` 在 `fuseVal=0x80000000` 时返回 32，
    `1 << 32` 是 C 未定义行为（`kernel_gsp_ga100.c:59-79`）。
- **影响（INFERENCE）**：若 fuse 版本用于吊销旧固件，单签名归档仍会把同一
  旧签名 patch 进去；两套约定也使跨路径的"版本 N"语义不可直接互换。
- **不确定度（UNKNOWN）**：BROM 可能用 fuse 独立强制吊销；`fuseVal=0x80000000`
  是否可达。

### W4. 签名长度/数量完全由归档自身描述

- **证据（FACT）**：`sigSize = signaturesTotalSize / numSigs`
  （`kernel_gsp_booter.c:145`）没有检查 `sigSize` 等于算法预期
  （TU102 实际是 16 B AES tag；GA/AD 是 384 B RSA3K）；
  `PATCH_SIG` 必须为 0 只防一类错位；`patchLoc - dataOffset` 无下溢检查
  （`kernel_gsp_booter.c:329`）。
- **影响（INFERENCE）**：bindata 与驱动同处一个未自校验的 `.ko`；本地 root
  改 `.ko` 后可让驱动把错误长度/位置写入 ucode image。硬件 PKC 校验应能
  拒绝大多数情况，但会先经过驱动内存写入路径。
- **不确定度（UNKNOWN）**：是否存在绕过硬件校验的 debug/无 fuse SKU。

### W5. GSP-RM 容器解析：off-by-one 与重名 section 选择

- **证据（FACT）**：`_kgspFwContainerGetSection`
  （`kernel_gsp.c:6147`）`shstrndx <= shnum`；`6165-6195` 从高 index 反向
  查找，返回**最后一个**重名 section；`shoff+shentsize*shnum` 之后没有对
  `shstrndx` header 读取范围单独校验（最多 64 B OOB read）。
- **影响（INFERENCE）**：畸形/重复 section 的 container 可让驱动与 GPU
  各自选中不同的 section；OOB read 为只读、读入值随后要过边界检查，
  影响以 DoS/解析混淆为主。
- **不确定度**：实际 buffer 分配粒度是否让 64 B 越界可触发 fault。

### W6. COT 公钥由主机提供，fuse 绑定不可见

- **证据（FACT）**：`kern_fsp_cot_payload.h:47-55`；`kern_fsp_gh100.c:1024-1050`；
  `kernel_sec2_gb20b.c:780-800`（主机写入 image/hash/sig/key 四个字段）。
- **影响（UNKNOWN，潜在最高）**：若 Booter 只信主机给的 `publicKey` 而不与
  fuse/OTP 比对，本地即可构造 image+hash+key+sig 的"自签名 FMC"。但
  `cotPayloadVersion`、`PDB_PROP_KFSP_FSP_FUSE_ERROR_CHECK_ENABLED` 与
  `ksec2ReadUcodeFuseVersion` 的存在提示 fuse 参与。
- **下一步**：见 §4.4。

### W7. 跨产品线公钥复用

- **证据（FACT）**：GB100 prod 与 GB202 prod 的 P-384 公钥逐字节相同
  （`sha256=af870e…`）；GR100 与 debug 各自不同。
- **影响（INFERENCE）**：一把生产私钥泄露/滥用会同时影响 GB100/GB202
  FMC 信任链。
- **不确定度**：是否存在按 fuse 分区/轮换的额外 key 选择（本地只见一个）。

### W8. "bringup 可忽略 preservation table 校验失败"

- **证据（FACT，字符串）**：`8ee2060 NVRM: Preservation table signature
  verification failed. If this is a bringup board you can ignore this message.`
  位于同一 verifier 的失败分支（`0x6e950fb`）附近。
- **影响（INFERENCE）**：存在一个被显式容忍的签名失败类别；如果条件只是
  板级/registry 判定而非 fuse，会形成 downgrade 面。
- **不确定度（UNKNOWN）**：触发条件（fuse、board type、registry、
  bringup flag）未从该窗口确定。

### W9. RM verifier 的 digest/format 枚举面

- **证据（FACT）**：`test $0x10003`（algo ∈ bit0/bit1/bit16）、
  `test $0x3`（format ∈ 1/2）、`(size,hashsize)==0x00000001_00000080` 的
  精确 qword 比较（§1.5）。nvflash 链接的 OpenSSL 代码里带
  MD5/SHA-1/SHA-256 的 RSA 字符串（通用 crypto 库字符串，不证明被运用）。
- **影响（UNKNOWN）**：若旧 algo（如 SHA-1/MD5）仍被接受，旧 ROM 的伪造门槛
  降低；若只接受 SHA-384/ECDSA，则无影响。
- **下一步**：见 §4.2。

### W10. 历史校验器的密码学强度（RSA-1024 + AES-128 DM hash）

- **证据（FACT）**：V100 FWSECLIC 的全 128 B PKCS#1 期望块比较与
  DMOVERAES128（AES-128 Davies–Meyer，128-bit digest，birthday ≈ 2^64）；
  样本中 not-before/not-after 字段存在但 FWSECLIC 内无时间比较；
  device/ECID 绑定依赖可选 extension（V100 样本只有 device-ID allow-list，
  没有 extension 6/ECID）。
- **影响（INFERENCE）**：若同一血缘的代码仍被现代 vBIOS 校验复用，则强度
  低于现代标准；HULK 路径的 3AES + hidden secret 也不可离线复现
  （`HULK_LICREQ_STATIC_FINDINGS_20260811.md`）。
- **不确定度**：现代 GB202 的 vBIOS 校验在 FSP 内，本地不可见。

### W11. hash-entry 覆盖模型可能出现"未声明区间"

- **证据（FACT）**：RM verifier 的 12 B entry 循环含 17 项 subtype 跳转表
  （`0x108b7168`），并有"应已开始 hash"的顺序检查；VDPA 错误名包含
  `ENTRY_NOT_FOUND`、`HASH_MISMATCH`、`FLASH_SIZE_LARGER_THAN_EXPECTED`。
- **影响（INFERENCE）**：若 subtype 允许 "跳过/重置起点" 且不与前一段连续，
  则存在未哈希区间；顺序检查只保证"起点出现过"，未证明覆盖连续。
- **不确定度（UNKNOWN）**：需要把跳转表 17 个目标逐个反汇编才能确认。

---

## 4. 纯静态的下一步实验（3–5 个）

以下均不需要 GPU、不需要网络、不需要运行任何更新器。

### 4.1 闭合 V100 "signed segment" 精确集合

- 输入：`fwseclib_imem.fuc6-crypt.asm`（455 KB）、`verify_v100_isbn_rsa.py`、
  V100 ROM。
- 做法：把 `0x4d93/0x5473/0x52bb` 的 parser 逐指令落成状态机（descriptor
  `0x3e002` 18 项、record base `0x3d254`、special bases `0x1f200/0x2fe00`、
  class 7/8/0x10），穷举 segment 顺序/包含关系/是否包含 0xa00 前缀，用
  `DMOVERAES128` oracle（已验证的 AES 运算与长度块）匹配
  `614400cd…`。
- 目标：给出"V100 vBIOS 签名实际覆盖的字节集合 + 明确未覆盖集合"，
  把 §2.6 的 UNKNOWN 变成闭合结论。

### 4.2 反汇编 RM verifier 的 17 项 subtype 跳转表与 digest 分支

- 输入：`mods`（c30461e2…）。
- 做法：`objdump -d --start-address=0x6e93e00 --stop-address=0x6e95600`；
  再逐个 dump `0x108b7168+8*i` 的 17 个目标；同时 dump `0x6e93fd0`
  （验签 helper）和 digest 枚举分支。
- 目标：列出 hash-entry 类型语义（哪些是 "add range"、是否允许空洞）、
  digest algo 枚举值（1/2/0x10000 对应的 SHA/MD5）、signature format 1/2
  的算法，以及 preservation-table "bringup 容忍" 的判定来源。

### 4.3 解出 `.fwsignature_*` 的 4×384 B 槽位格式

- 输入：本地四份 `gsp_ga10x.bin`（610.53/610.57.01/610.57.04/610.88），
  以及 Bindata 的 GB202/GB100/GR100 FMC key。
- 做法：比较 610.53 与 610.57.04 的槽位与 `.fwimage`；尝试把槽位解释为
  RSA-3072 签名（在 FMC/FSP image 或 fuse 摘要中找 384 B modulus）、
  ECDSA P-384（96 B + padding）、或 (48 B hash + 336 B) 容器；用
  已恢复的 GB202 P-384 key 与任何候选 modulus 做 verify 扫描。
- 目标：确定 GSP-RM 镜像是否与 FMC 共用密钥、4 槽是否对应 fuse 版本，
  以及 signed range 是否覆盖 section headers。

### 4.4 在 GB202 FMC/FSP bindata 中找 COT root 绑定证据

- 输入：`g_bindata_kgspGetBinArchiveGspRmFmcGfw*Signed_GB202.c`、
  `g_bindata_kgspGetBinArchiveGspRmBoot_GB202.c`、GSP inner ELF strings。
- 做法：解压 FMC（287304 B）并找 97 B P-384 公钥的 SHA-384/SHA-256 是否出现
  在 FMC 自身、`cotPayloadVersion`/`publicKey` 相关字符串附近或
  `NV_PBUS_ZB_SW_SCRATCH(54)` COT 轮询相关代码路径；用 Ghidra 工程
  `gb202_gsp61057.rep`/`gb202_gsp570144.rep` 查 RISC-V 侧对 COT 的解包与
   fuse 比对函数。
- 目标：判定 W6（主机提供公钥是否被 fuse pin）。

### 4.5 用一份真正携带 V3 FWSEC desc 的 Ampere/Ada ROM 观察签名槽

- 输入：需要本地已有、非 GB202 的 Ampere/Ada ROM（当前 `vbios_diff`/
  `vbios_history` 没有）。可先扫描现有环境（`find /home/user -name '*.rom'`）
  找 GA10x/AD10x 镜像。
- 做法：复用 `tools/scan_falcon_ucode_tables.py` + 新写只读 parser 解出
  `vDesc` version==3 的 FWSEC entry，dump `descSize`、`SignatureCount`、
  `SignatureVersions` 与 `descSize-44` 的尾随字节数，验证
  `SignatureVersions` 位图与 `numSigs` 的关系。
- 目标：把 §1.1-4/§2.2 的 V3 行为从源码推断升级为样本实证。

---

## 5. 复现命令（只读）

```sh
# 0) 源码侧定位
grep -n "PATCH_SIG\|PATCH_META\|NUM_SIGS" \
  src/nvidia/src/kernel/gpu/gsp/kernel_gsp_booter.c
sed -n '349,400p' src/nvidia/src/kernel/gpu/gsp/arch/turing/kernel_gsp_frts_tu102.c
sed -n '912,1006p' src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c

# 1) GB202 ROM：BIT/Falcon 表与 FSP_RUN
cd /home/user/rt_5090_project
python3 gb202_vbios_diff.py vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom

# 2) GB202 FMC COT：hash 与 ECDSA P-384 验证
python3 - <<'PY'
import re,zlib,hashlib
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ec,utils
from cryptography.hazmat.primitives import hashes
f=('/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/'
   'src/nvidia/generated/g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c')
t=Path(f).read_text()
def arr(suf):
    for m in re.finditer(r'static BINDATA_CONST NV_DECLARE_ALIGNED\(NvU8, 8\) (\w+)_data\[\]\s*=\s*\{(.*?)\};',t,re.S):
        if m.group(1).endswith(suf):
            return bytes(int(x,16) for x in re.findall(r'0x([0-9a-fA-F]{2})',m.group(2)))
img=arr('UCODE_IMAGE'); h=arr('UCODE_HASH'); sig=arr('UCODE_SIG'); p=arr('UCODE_PKEY')
print('SHA384(image)==hash:', hashlib.sha384(img).digest()==h)
pk=ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP384R1(),p)
der=utils.encode_dss_signature(int.from_bytes(sig[:48],'big'),int.from_bytes(sig[48:],'big'))
pk.verify(der,img,ec.ECDSA(hashes.SHA384())); print('ECDSA P-384 verify OK')
PY

# 3) GSP-RM 容器 section 结构（610.57.04）
#    解析 /lib/firmware/nvidia/610.57.04/gsp_ga10x.bin 的 ELF section 表

# 4) V100 FWSECLIC 验证门
cd /home/user/hulk_public_research_20260811
python3 tools/verify_v100_isbn_rsa.py \
  vbios_history/NVIDIA.TeslaV100.16384.170728_1.archive.rom
grep -n "lcall 0x3be3\|lcall 0x5540\|lcall 0x2083" \
  vbios_history/v100_fwseclib/fwseclib_imem.fuc6-crypt.asm

# 5) MODS RM vBIOS verifier 有界窗口
objdump -d --start-address=0x6e93e00 --stop-address=0x6e95600 \
  /home/user/rt_5090_project/mods_audit/static/extracted_inner/mods
strings -a -t x /home/user/rt_5090_project/mods_audit/static/extracted_inner/mods \
  | grep -E "NVRM: (Invalid signature|VBIOS Signature|Unknown digest|Hash entry)"
```

---

## 6. 负结果、限制与不确定性

**负结果（有价值）**

- 开源内核模块中**没有** vBIOS/FMC/BCRT 密码学校验代码；
  `internal_crypt_lib.h`/`lkca_*` 只服务 SPDM（`libspdm_*`）。
- GB202 vBIOS 没有 FWSEC app（0x05/0x45/0x85）；`FSP_RUN` (0x24) 是 v6 加密
  对象，主机驱动也不解析。
- GSP-RM inner ELF 中**没有**主机 RM 的 vBIOS 签名/X509 校验字符串；该
  verifier 在专有 x86 RM 中。
- 本地四个 GB202 样本只提供 3 个独立 target 字节对象；GeForce FE/ASUS 共享
  同一 FSP_RUN target。
- 610.53→610.88 的 GSP-RM `.fwimage` 与 4 个 384 B 槽位都变化，未观察到跨版本
  签名重用。

**限制**

- 真正执行 vBIOS/FMC/FSP 校验的 BROM/FSP/FWSECLIC 代码不在本地可读范围；
  W1/W2/W3/W6 的最终影响高度依赖这些不可见实现。
- 本地没有携带 V3 FWSEC desc 的 Ampere/Ada ROM，V3 签名槽没有样本实证。
- GH100 FMC 的 RSA 密钥编码/签名序列化未复现；`.fwsignature_*` 的算法/根
  未知；COT 的 signed serialization 未知。
- BCRT/VDPA/HAT 的 root 闭合沿用先前报告的 UNKNOWN，本篇没有新增该链条的
  密钥级证据。
- V100 parser 的精确 signed segment 集合未闭合（host 模型 57.1% + digest
  不匹配）。

**未做且不建议在无授权环境下做的事**：刷写、运行 updater/nvflash、向 GPU
写入、任何 export-control 规避。

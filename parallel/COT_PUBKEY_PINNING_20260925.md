# FMC/COT 公钥钉扎（key pinning）静态审计：设备到底有没有把公钥钉死在熔丝/ROM，或只钉一个 key-hash？

日期：2026-09-25（Asia/Singapore）
范围：**纯本地只读静态**。本次没有访问 GPU/`/dev/nvidia*`/PCI/BAR/MMIO/debugfs、
没有执行 nvflash/updater/MODS/insmod、没有刷写或写入任何固件、没有联网。
所有结论只来自本机普通文件、本地源码文本与离线脚本复算。
不含、也不提供任何出口管制相关（算力/授权绕过）内容与刷写步骤。

上游背景（本次只引用、不重复）：
`parallel/SIGNATURE_VERIFIER_HUNT_FSP_20260925.md`、
`parallel/SIGNATURE_VERIFIER_HUNT_VBIOS_20260925.md`、
`parallel/GB202_WRITE_LADDER_PLAN_20260925.md`（§"最重要的 UNKNOWN"）。
本次工作目录（脚本 + 原始输出）：`parallel/cot_pin_work/`。

---

## 0. 结论（TL;DR）

**判定：钉扎机制存在（STRONG）；但"钉整把公钥 / 只钉 key-hash / 钉在熔丝 / 钉在 ROM"四选一在本地方案内不可判（UNKNOWN）。**
"设备完全没钉、纯信任 host 递来的公钥"这一读法被本次证据**显著削弱**（有结构性反证，见 E8/E13），
但不能被完全排除（见 §3 的四格矩阵）。

三句话版本：

1. **可见范围内不存在任何与 FMC/COT 公钥绑定的常量或字段**：FMC prod/debug/CC 公钥本身、
   其 `x||y`、单坐标、`SHA-256`/`SHA-384`（整键与 `x||y`）、镜像 hash、96-B 签名——
   在三份设备侧 GSP-RM 二进制里 **0 命中**；在 GB202 ROM/NVFW/fwpkg、HGX Blackwell FW 包、
   `gsp_ga10x/gsp_tu10x/ucodes_*`、nvflash、`bootloader-570.144` 里同样 **0 命中**
   （阳性对照：同一组模式在 host 侧 MODS（RM 570.151/570.215）各命中 7 次、在
   `fmc-570.144` 容器内命中 8 次）→ **E1/E2 = STRONG-NEGATIVE（可见范围）**。
2. **可见的熔丝面全是"策略/模式"，没有"密钥/哈希"字段**：已发布 swref 里 GB100/GB202/GH100
   只有 5 个 ZB 熔丝 + 4 个 SPARE_BIT，名字/字段中 **KEY/HASH/PK/SIG/ROOT 全部 0 命中**；
   代码里真正被读的只有 `OPT_SECURE_GSP_DEBUG_DIS(0x74C)`（prod/debug 键选择）、
   `OPT_FPF_GSP_UCODE1_VERSION(0x41C0)`/`OPT_FPF_SEC2_UCODE1_VERSION(0x4140)`（防回滚签名槽选择）、
   `SPARE_BIT_0/1/2`（CC 能力）、`FEATURE_READOUT(0x3814)`（→ E4，STRONG）。
3. **反向证据（本次新发现，权重最高）**：经典路径 `.fwsignature_*` 4 KiB 帧**只有签名字节、
   没有公钥、没有镜像 hash**（E8）；host 的驱动 bindata 四件套被明确命名为
   `g_gsp_<chip>_dyn_{prd,dbg,spdm_prd}_gfw_{image,hash,pub_key,sig}.bin`（E13a），
   而 **MODS 的熔丝返修（fuse rework）流程里存在 `fuserework_debug_gfw_pub_key.bin` /
   `fuserework_debug_gfw_hash.bin` / `fuserework_debug_gfw_sig.bin`**（E13b）——
   同一套"GFW 键/hash/签名"命名出现在"把 key 装进熔丝"的流程里。
   ⇒ **"把 GFW（=GSP/FMC 固件）键材料钉进熔丝"这条机制在本地是可证的（至少 debug 变体）；
   prod 变体的锚点落在熔丝还是 ROM，本地不可判。**

⇒ 对原问题的直接回答：
**"设备有没有钉？"→ 有（机制与 debug 路径可证）。"钉的是整把键还是只钉 key-hash？"→ 未定。
"钉在熔丝还是 ROM？"→ 未定，但 debug 路径指向熔丝、prod 路径无本地证据。**

---

## 1. 证据清单

强度定义：**STRONG** = 本地字节/源码/离线复算直接支持，且结论范围被明确限定；
**WEAK** = 只能支持一种更窄的推测或依赖命名/字符串推断；**NONE** = 明确的有界负结果。

| ID | 证据 | 来源（本地路径） | 强度 |
|---|---|---|---|
| E1 | 设备侧 3 份二进制中 **无 FMC 公钥/公钥 hash/镜像 hash/签名** 的任何形态 | `ghidra_static/gsp_inner_19f040_a.elf`、`gsp_inner_570144_main.elf`、`power_governor_reverse/gsp61057_rx_full.bin` | STRONG (neg) |
| E2 | 更广的本地固件/工具集合同样 0 命中；同模式在 host RM 与 FMC 容器命中（阳性对照） | GB202 ROM/NVFW/fwpkg、HGX B300/B100-B200 fwpkg、`gsp_ga10x/tu10x`、`ucodes_*`、nvflash、MODS ×2、`fmc-570.144` | STRONG (neg) |
| E3 | 已发布熔丝头文件里 **无 KEY/HASH/PK/SIG/ROOT 字段** | `src/common/inc/swref/published/**/dev_fuse*.h` | STRONG（范围=已发布子集） |
| E4 | 代码里实际读的熔丝全是"模式/版本/能力" | `kernel_gsp_gb100.c:290-330`、`kernel_sec2_gb100.c:49-51`、`kernel_gsp_booter.c:132-170`、`conf_compute_gh100.c:47-90` | STRONG |
| E5 | COT 结构体**没有 key-hash/key-id 字段**，host 侧零密码学 | `inc/kernel/gpu/fsp/kern_fsp_cot_payload.h:34-56`、`fsp/arch/hopper/kern_fsp_gh100.c:953-1049` | STRONG |
| E6 | 设备侧存在 **FWSECLIC 错误名池**（90 项），含 `BOOTLOADER_UCODE_HASH_MISMATCH`、`VERIFY_ENG_HULK_3AES_SIG_MISMATCH_WITH_GPU_FUSE`、`CMD_VBIOS_VERIFY_HULK_KA_NOT_FOUND`、`GFWIMAGEPARSER_*CERT_BLOCK*` | 三份设备侧二进制 strings（如 `e31318` in RX） | STRONG（作为"存在哪些检查"）；WEAK（作为 pinning） |
| E7 | `FLCN_ERR_HS_{CHK_GFW_CHAIN_OF_TRUST_BROKEN,INVALID_KEY,SWKG_INVALID_SIGNATURE,CHK_UCODE_REVOKED}`（0xC8/0xD1/0xD2/0xA2）**只存在于 host 头文件**，设备侧二进制 0 命中；FMC 错误码经 `NV_PBUS_SW_SCRATCH_GSP_FMC_ERROR` 回传，格式不透明 | `flcnretval.h:116/195/233/242/243`、`gsp_fmc_error_code_formatting.h`、`gpu_gsp_fmc_error_reporting_gh100.c:56-106`、`kernel_gsp_gh100.c:909-1010` | STRONG（边界证据） |
| E8 | 经典 `.fwsignature_*` 4 KiB 帧**无 P-384 点、无 SHA-384(.fwimage)**；用已知 FMC prod/debug 键 1160 次尝试全部不验签 | `gsp_ga10x.bin`（610.57.04）+ `fwsignature_frame_probe.py` | STRONG |
| E9 | FMC/ConcatenatedFMC/`GspRmBoot` 镜像体高熵、无可读串、无已知压缩容器 ⇒ 非明文代码 | bindata + 熵/字符串/魔数复算 | STRONG（"非明文"）；INFERENCE（"加密"） |
| E10 | 3 份镜像里存在 P-384 与 P-256 曲线常数（各 4-5 处）⇒ 设备侧确有 ECDSA 实现 | 常数搜索 | STRONG（但与 FMC 键无直接关联） |
| E11 | FSP fuse 检查存在但**只对 GB100/GB102/GB110/GB112 生效**；GB202 的 `kfspWaitForSecureBoot_GB202` 不读该状态 | `g_kern_fsp_nvoc.c:244-258`、`kern_fsp_gb100.c:134-165`、`kern_fsp_gb202.c:63-88`、`dev_fsp_addendum.h:32-34`（仅 gb100） | STRONG |
| E12 | SPDM 的 `verify_public_key_hash` 只存在于随包 libspdm，开源树内无 caller；MODS 侧 peer key 是"provision"而非硬编码 | `libraries/libspdm/3.5.0/...`、MODS strings `peer_public_key_provision_size` | WEAK |
| E13a | host 驱动 bindata 的 FMC 四件套命名 = `..._gfw_{image,hash,pub_key,sig}.bin`（`gfw_pub_key.bin` 就是 `UCODE_PKEY`，97-B P-384 点） | `generated/g_bindata_kgspGetBinArchiveGspRm{Fmc,CcFmc}Fmc*_*.c` 的 `// FILE NAME` | STRONG |
| E13b | **MODS 熔丝返修流程**引用 `fuserework_debug_gfw_pub_key.bin` / `_gfw_hash.bin` / `_gfw_sig.bin`，并有 `SetRework{Binary,SHAHash,PublicKey,RSASignature}Filename`、`EncryptFuseFile(...,isFuseKey)`、`GetFuseKeyToInstall`、`SetInstalledFuseKey`→`Fuse.L2FuseKey`、`installKey_`/`Installing key %s`/`fuseKey_`/`Setting L2Key to %s` | MODS 570.215 strings `0x88dd650` 等；见 §1.7 | **WEAK→STRONG**（"存在把 GFW 键材料装进熔丝的流程"） |
| E14 | `RmDisableCotCmd`（bits: FRTS_SYSMEM/FRTS_VIDMEM/**GSPFMC**）允许 host **完全不发** FMC COT；`RmDisableFspFuseErrorCheck` 允许关掉 FSP fuse 检查的致命化 | `nvrm_registry.h:2053-2058`、`kern_fsp.c:135-160`、`kernel_sec2.c:121-126` | STRONG（说明 host 侧可旁路） |

---

### 1.1 E1：设备侧二进制里没有任何 FMC 键/hash 形态（明确 NONE）

搜索模式（30 个，脚本 `cot_pin_work/cot_pin_scan.py` + `fmc_key_local_scan.py`）：

* GB202 prod / debug / CC-prod：`UCODE_PKEY` 原样 97 B、`x||y` 96 B、`x` 48 B、`y` 48 B；
* `SHA-256(pkey)`、`SHA-256(pkey)[0:16]`、`SHA-256(pkey_xy)`、`SHA-256(pkey_xy)[0:16/20]`、
  `SHA-384(pkey)`、`SHA-384(pkey_xy)`；
* `SHA-384(image)`（=`UCODE_HASH`）、`SHA-256(image)`、96-B `UCODE_SIG`、image 头 64 B；
* `SHA-384(image)[0:16/24]`、pkey 头/尾 32 B。

目标与结果：

| 目标 | SHA-256 | 命中 |
|---|---|---|
| `gsp_inner_19f040_a.elf`（82,577,496 B, 设备侧 GSP-RM debug/大, RV64, 8 个节头全 unnamed） | `bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47` | **NONE** |
| `gsp_inner_570144_main.elf`（15,085,568 B, RV64, stripped） | `6c36425881780a14e0c3f03622784367a11892d64ee131ef2f2ce3029d7a4ff3` | **NONE** |
| `power_governor_reverse/gsp61057_rx_full.bin`（15,298,560 B, RV64 RX 切片） | `50614073f1ca73d4a10e66bdba15e557763b402c75b203a8950161c0afe59085` | **NONE** |
| **合计命中** | | **0** |

复算基线（host 侧，来自 bindata，用于确认模式本身有效）：

```
GB202_fmc_prod  IMAGE 287304  HASH 48  SIG 96  PKEY 97
   PKEY[0]=0x04  sha256(pubkey)=af870e5dde972840588bfb94a87f94b19ad6659dae6e1343dd0d22f16074ba39
   SHA-384(image)=6028614ae0e3740510e811705ef18c68…  stored hash match: True  ECDSA P-384: True
GB202_fmc_debug sha256(pubkey)=9cdd06eb4b7c6d7ae1b75daa142c4695ff613d7791e642658a674d1147bf371e
GB202_fmc_cc    sha256(pubkey)=af870e5d…（同一把 prod 键）
GB100 / GR100 prod 键：af870e5d… / 34a0836e…
```
（`/usr/src/nvidia-610.57.04` 与 greenfield 610.43.03 的这两份 bindata 逐字节一致，
键与 hash 相同：见 §1.8。）

### 1.2 E2：更广的本地扫描（明确 NONE）与阳性对照

命令：`python3 cot_pin_work/fmc_key_local_scan.py`（同一 30 模式集，另加 18 个变体做二次扫描）

| 对象 | 大小 | 结果 |
|---|---:|---|
| RTX5090 FE ROM `98.02.2E.00.03`(TPU) | 1,961,983 | NONE |
| ASUS Astral ROM `98.02.2E.40.85`(TPU) | 1,961,983 | NONE |
| ASUS 官方 `98.02.2E.40.AS02` | 1,912,272 | NONE |
| ASUS live sysfs ROM `…40.E0` | 162,304 | NONE |
| Dell RTX PRO 6000 NVFW `98.02.8D` | 1,908,176 | NONE |
| Dell GB202 `.fwpkg` | 1,908,383 | NONE |
| HPE RTX PRO 6000 NVFW `98.02.9E` / fwpkg | 1,908,176 / 2,204,365 | NONE |
| `RTX5090_FE_optionrom_chain.bin` / `RTXPRO6000_Server_optionrom_chain.bin` | 1,732,607 / 1,666,512 | NONE |
| HGX-B300x8 `0006_260317.1.2` fwpkg | 111,093,378 | NONE |
| HGX-B100-B200x8 `0009_260317.1.0` fwpkg | 113,021,545 | NONE |
| `gsp_ga10x.bin`(610.57.04) | 84,310,168 | NONE |
| `gsp_tu10x.bin` / `ucodes_ga10x.bin` / `ucodes_tu10x.bin` | 29,381,504 / 31,744 / 12,032 | NONE |
| `bootloader-570.144.bin.zst`（解压后） | 200,812 | NONE |
| `gsp-570.144.bin.zst`（解压后） | 63,571,696 | NONE |
| nvflash（HPE 5.877.0） | 16,309,920 | NONE |
| **MODS 570.215**（host RM/工厂工具，阳性对照） | 392,897,664 | **7 模式命中**（pkey 97B / x\|\|y / SHA-256 等） |
| **MODS 570.151**（阳性对照） | 392,339,552 | **7 模式命中** |
| **`fmc-570.144.bin.zst`**（解压后，payload 本体） | 199,820 | **8 模式命中**（image/hash/sig/pkey 四 section） |

`fmc-570.144` 的复算（`fmc_signature_probe_20260925.py fmc-elf`）：
`sections {.shstrtab, hash(0x30), signature(0x60), publickey(0x61), image(0x30a48)}`，
`stored hash match: True`，`ECDSA P-384/SHA-384 over whole image: True`，
`pubkey sha256=af870e5d…` —— 即**本机的 FMC 公钥副本只出现在"随 host payload 分发"的两处**
（FMC 容器本体 `fmc-570.144`，以及 host RM 二进制 MODS 里嵌入的同一份 bindata）；
没有任何设备侧副本。

### 1.3 E3/E4：熔丝面（STRONG，范围限定）

已发布 swref 中所有 `NV_FUSE_*` 名字（全 arch 合计 165 个）里，匹配
`KEY|HASH|_PK|SIG|ROOT|HS_|COT` 的**只有** 10 个，且全部是
`NV_FUSE_ZB_OPT_SECURE_GSP_DEBUG_DIS*`（"SECURE"误配）。Blackwell 相关全部字段：

```
gb100/dev_fuse_zb.h : _FEATURE_READOUT(0x3814, bit16 ECC_DRAM)
                      _OPT_FPF_GSP_UCODE1_VERSION(0x41C0, DATA 15:0)
                      _STATUS_OPT_DISPLAY(0xC04)
                      _OPT_FPF_SEC2_UCODE1_VERSION(0x4140, DATA 15:0)
                      _OPT_SECURE_GSP_DEBUG_DIS(0x74C, DATA 0:0)
gh100/dev_fuse_zb.h : _SPARE_BIT_0/1/2 + 上述 DEBUG_DIS
```

使用点（全部为模式/版本/能力，无一处与公钥或 key-hash 比较）：

| 站点 | 熔丝 | 语义 | 行号 |
|---|---|---|---|
| `kgspIsDebugModeEnabled_GB100` | `0x74C` | `DATA==NO` ⇒ debug 模式（决定取 prod 还是 debug FMC 镜像/**键**） | `gsp/arch/blackwell/kernel_gsp_gb100.c:290-299` |
| `kgspReadUcodeFuseVersion_GB100` | `0x41C0 + 4*index` | 16×16-bit；`version = HIGHESTBITIDX+1` | 同文件 `:310-330` |
| `ksec2ReadUcodeFuseVersion_GB100` | `0x4140 + 4*index` | SEC2 同型 | `sec2/arch/blackwell/kernel_sec2_gb100.c:45-55` |
| `s_patchBooterUcodeSignature` | 经上两者 | `sigSize = total/numSigs`；`numSigs>1` 时 `sigIndex = numSigs-1-fuseVer`；`fuseVer>numSigs-1 ⇒ NV_ERR_OUT_OF_RANGE` | `gsp/kernel_gsp_booter.c:132-170` |
| `confComputeIsDebugModeEnabled_GH100` | `0x74C` | debug 板 ⇒ CC 直接拒绝 | `conf_compute/arch/hopper/conf_compute_gh100.c:47-58` |
| `confComputeIsGpuCcCapable_GH100` | `SPARE_BIT_0/1/2` | CC 能力位（0=Enable,1=Enable,2=Disable） | 同文件 `:60-90` |

**注意（重要的负结果）**：这些熔丝读点里，`0x41C0/0x4140` 是**选择"第几份签名"**（防回滚），
`0x74C` 是**选择 prod/debug 那一套材料**。它们都**不携带、也不验证**密钥或密钥哈希。
本地**没有任何** `fuseGetState`/fuseID 枚举（`FUSE_ID_*`、`ctrl2080fuse.finn` 只剩空壳）
能证明存在 key-hash 熔丝字段。

### 1.4 E5：COT 结构体与 host 侧零密码学（STRONG）

```c
// inc/kernel/gpu/fsp/kern_fsp_cot_payload.h:34-56   (NVDM_PAYLOAD_COT)
version, size, gspFmcSysmemOffset, frtsSysmemOffset/Size,
frtsVidmemOffset/Size, hash384[12], publicKey[96], signature[96], gspBootArgsSysmemOffset
```
* 结构体**没有** `keyId`/`pubKeyHash`/`keySlot` 类字段；host 只做 memcpy
  （`kfspSetupGspImages()`，`kern_fsp_gh100.c:1006-1049`，无任何 `SHA*`/`ECDSA`/`memcmp`）。
* 长度契约：`cotPayloadSignatureSize/PublicKeySize = 96/97`（GB100/102/10B/110/112/202/203/205/206/207/GR100/102），否则 384/384
  （`generated/g_kern_fsp_nvoc.c:262-296`）。
* 发送：`kfspSendBootCommands_GH100()` 先 `gpuResetGspFmcErrorCode_HAL()`，再
  `kfspSendAndReadMessage(..., sizeof(NVDM_PAYLOAD_COT), NVDM_TYPE_COT=0x14, ...)`
  （`kern_fsp_gh100.c:1490-1520`）。
* **`RmDisableCotCmd` 的 `GSPFMC` 位可以让 host 完全不发这条 COT**（`kern_fsp.c:135-150`；
  SEC2 路径同 `kernel_sec2.c:121-126`）——即 host 有权旁路，因此"host 发什么"本身不是信任边界。

### 1.5 E6：设备侧可见的"检查清单"（FWSECLIC 错误名池，90 项）

三份设备侧二进制**都**含 FWSECLIC 错误名池（RX 切片起始 `0xe2f620` → VA `0x1E2F620`，
570.144 在 `0xcfa3d8`），完整表见 `cot_pin_work/FWSECLIC_ERR_CODE_names_61057.txt`。
与"钉扎"最相关的条目：

```
BOOTLOADER_UCODE_HASH_MISMATCH                      ← bootloader 对 ucode 做 hash 比对
BOOTLOADER_INTERFACE_HASH_MISMATCH                  ← 接口(rate/PMU)hash 比对
VERIFY_ENG_HULK_3AES_SIG_MISMATCH_WITH_GPU_FUSE     ← 签名与 GPU 熔丝比对（唯一显式"fuse"项）
VERIFY_ENG_HULK_NO_3AES_SIG
CMD_VBIOS_VERIFY_HULK_KA_NOT_FOUND                  ← KA(Key Authority?) 缺失
CMD_VBIOS_VERIFY_{CERT_NOT_FOUND,CERT_PARSE_FAIL,CERT_VERIFY_FAIL,HAT_FAIL,BIOS_SIG_FAIL,...}
CERT_HULK_{ECID,DEVID}_MISMATCH / _STRICT_ID_* / _INFOROM_HLK_OBJ_NOT_VALID
CERT20_VDPA_{SIG_INVALID,ENTRY_NOT_FOUND,CERT_INTBLK_MISMATCH,DATA_INVALID}
CERT21_FMT_* / CERT21_CERT_VERSION_UNEXPECTED / CERT21_FRTS_*
GFWIMAGE_*（在 NV_UCODE_ERR 命名空间）：
   INVALID_DATA_STRUCT_SIGN / INVALID_ROM_SIGN / CERT_BLOCK_NOT_PRESENT / INFOROM_BLOCK_NOT_PRESENT
NV_PREOS_ERR_UCODE_VALIDATION_{REVLOCK_ID_MISMATCH,CHIP_ID_INVALID}
```

**但**：

* 池中**没有** `FLCN_ERR_HS_*`（0xA2/0xC8/0xD1/0xD2）这些名字；对三份设备侧二进制
  分别执行 `grep -cE "INVALID_KEY|CHAIN_OF_TRUST|SWKG"` → **0/0/0**；更宽的
  `_KEY` 模式只命中一条无关的 `KEY_IS_INVALID_ZERO`（三份都有）。
  这些 HS 码只在 host 头 `arch/nvalloc/common/inc/flcnretval.h:116/195/233/242/243` 里定义，
  **产出者（BootROM/HS ucode）不在本地**。
* 名池在 RX 切片里是**纯 NUL 分隔字符串池**（16-B 对齐），
  没有任何指向它的 8/4-byte 指针表（搜索 75 个疑似 u32 全部落在随机代码里，无表结构）
  ⇒ **数字码 ↔ 名称的映射本地未闭合**（见 §4 步骤 3）。
* 相关字符串面：`RMExecuteFwsecOnSec2`、`RmDisableFwseclic`、`RMHulkCert`/`RMHulkCertSize`、
  `RmHulkDisableFeatures`、`RmIgnoreHulkErrors`、`RMSec2UseDebugFuseOnlyBinary`、
  `RmDisableFspFuseErrorCheck`+`FSP fuse error check has failed. Status = 0x%x.`
  ⇒ GSP-RM **调度/观测** FWSEC-on-SEC2 与 HULK，但不含 FWSECLIC 的代码（无 ucode 镜像/ bindata 名）。

### 1.6 E7：FMC 错误码回传面（host 只看到不透明码）

* 寄存器：`NV_PBUS_SW_SCRATCH(0x37)` = `NV_PBUS_SW_SCRATCH_GSP_FMC_ERROR`
  （`blackwell/gb100/dev_bus_addendum.h:30-31`；gh100 同址）。
* 格式（`arch/nvalloc/common/inc/gsp/gsp_fmc_error_code_formatting.h`）：
  `VARIANT[31:28] | PARTITION[27:24] | PAYLOAD[23:0]`；
  VARIANT 0 = `SK`：`SK_ERROR[15:8] + SK_PHASE[7:0]`；
  VARIANT 1 = `Generic`：`ADDITIONAL_INFO[23:16] + ERROR_CODE[15:0]`。
* 消费（host）：`gpu_gsp_fmc_error_reporting_gh100.c:56-106`（只打印，不解码语义）；
  `kernel_gsp_gh100.c:909-1010`：`_kgspLockdownReleasedOrFmcError` 失败或
  `gpuCheckGspFmcErrorCode_HAL()` 非 0 ⇒ `NV_ERR_NOT_READY`，并明确写道
  **"Bootrom may have failed, GSP init code may have failed or ACR failed to release target mask.
  RM does not have access to information on which of those conditions happened."**
  ⇒ 即使验签失败，host 侧也拿不到"哪一项检查失败"。
* FMC 错误码的 16-bit `GENERIC_ERROR_CODE` 空间与 FWSECLIC 错误 enum **很可能同域**
  （INFERENCE：两者都在"设备 ucode 错误码"空间，且 FWSECLIC 池包含 `BOOTLOADER_*`/`SECUREBOOT_*`），
  但本地无法把 0xC8/0xD1/0xD2 映射进去。

### 1.7 E13：本次最强的正向线索——`gfw_pub_key/hash/sig` 与熔丝返修流程同名

**(a) 驱动 bindata 的命名（FACT）**：`generated/g_bindata_kgspGetBinArchive…` 里的注释

```
FILE NAME: kernel/inc/gspcc/bin/g_gsp_gb20x_dyn_prd_gfw_image.bin     → BINDATA_LABEL_UCODE_IMAGE
FILE NAME: kernel/inc/gspcc/bin/g_gsp_gb20x_dyn_prd_gfw_hash.bin      → …_UCODE_HASH (SHA-384(image))
FILE NAME: kernel/inc/gspcc/bin/g_gsp_gb20x_dyn_prd_gfw_sig.bin       → …_UCODE_SIG  (96 B r||s)
FILE NAME: kernel/inc/gspcc/bin/g_gsp_gb20x_dyn_prd_gfw_pub_key.bin   → …_UCODE_PKEY (97 B P-384 点)
                                                                        （另有 dyn_dbg_*、dyn_spdm_prd_* ← CC 变体）
```
即 **"GFW"(= GSP/GPU 固件) 的四件套就是 FMC 的认证材料**，且 `gfw_pub_key` 与 `gfw_hash`
是**两个不同**的具名对象。

**(b) MODS（host RM/工厂工具）的熔丝返修流程（FACT，字符串）**：

```
file off   VA(base 0x400000)  字符串
0x88dd650  0x8cdd650  fuserework_debug_gfw_pub_key.bin
0x8d4c334  0x914c334  fuserework.bin
0x8d5d45f  0x915d45f  fuserework_debug_gfw_hash.bin
0x8d5d47d  0x915d47d  fuserework_debug_gfw_sig.bin
（另有 FuseRework / 16FuseReworkHelper / SetInstalledFuseKey / Fuse.L2FuseKey 等）
Usage: JsFuse.SetReworkBinaryFilename(filename)
Usage: JsFuse.SetReworkSHAHashFilename(filename)
Usage: JsFuse.SetReworkPublicKeyFilename(filename)
Usage: JsFuse.SetReworkRSASignatureFilename(filename)
Sets the fuse rework {binary,SHA Hash,Public Key,RSA Signature} filename
Usage: device.Fuse.EncryptFuseFile(fileToEncryt, KeyToEncrypt, isFuseKey)
Usage: device.Fuse.GetFuseKeyToInstall(fuseKey)
SetInstalledFuseKey is deprecated, please use Fuse.L2FuseKey
Usage: device.Fuse.L2FuseKey = fuseKey
Error: Fusekeys of not right size.
installKey_ / Installing key %s / fuseKey_ / Decrypting with key %s. / Setting L2Key to %s
EnableSecureFuseblow / PMU ucode failed to lower privilege level / Secure PMU could not be loaded!
```

**读法与强度**：

* 命名与 (a) 逐字同构（`*_gfw_{pub_key,hash,sig}.bin`）⇒ **`fuserework_debug_gfw_*` 极可能
  就是"debug GFW（FMC）键材料"**，而它出现在**把 key 烧进熔丝的流程**里
  （`GetFuseKeyToInstall`/`SetInstalledFuseKey`/`L2FuseKey`/`Installing key`）。
* 因此"设备侧存在**熔丝承载的 GFW 键/键哈希**"这一命题，在 **debug 路径**上获得了
  本地可证的机制支持（**STRONG as mechanism**）；但**prod 变体没有对应的
  `fuserework_prod_gfw_*` 字符串**（只有 debug + `spdm_prd` 命名出现在驱动 bindata 里），
  所以"prod 键/hash 是熔丝还是 ROM"仍然**未定**。
* 保留意见：MODS 是 host 侧工具，字符串只能证"存在这条工艺与命名"，不能证
  "GB202 的 FMC COT 公钥一定与熔丝值比对"（反例路径：COT 里的 `publicKey` 也可能被
  FSP 完全忽略、只用自身 ROM/ucode 内建键）。

### 1.8 E8/E9/E10：三条补充复算

**(E8) 经典 `.fwsignature_*` 帧**（610.57.04 `gsp_ga10x.bin`，脚本 `fwsignature_frame_probe.py`）：

* 帧长 0x1000；头部 `01 00 02 00 c8 08 00 00 0c 00 00 00 01 01 00 00 00 02 00 00`（0x14 B），
  随后 **4 个 384-B 槽**（`0x14/0x214/0x414/0x614`），其余 **2545–2554 B 为 0**；
  跨家族差异字节数 1528–1535（≈ 4×384）⇒ **只有这 4 个槽是 per-family 的**。
* **全部 12 个家族 section**（含 cc_gb20x/gb20y/cc_gb10x/gb10y/cc_gh100 等）中
  **on-curve 的 97-B P-384 点 = 0 个**，**含 `SHA-384(.fwimage)` 的帧 = 0 个**。
* 用已知 FMC prod/debug 键 × 4 槽 × 全偏移（1160 次）验证 `SHA-384(.fwimage)`：**全部不通过**。
  ⇒ 该路径的验签键**不在 host 容器里**（键必然在设备侧或其它的不可见材料里）。
  （⇒ 这是"设备侧确有键/anchor"的最强结构性反证；至于它是 ROM 常量、熔丝键还是熔丝 hash，不可判。）

**(E9) 镜像体不是明文**：GB202 prod/debug FMC image（287,304 B）、CC image（257,096 B）、
`ConcatenatedFMC`（503,808 B）、`GspRmBoot`（290,816 B）的熵均 ≈ 7.98–8.00，
可读 ASCII（≥8）命中数 47–107（= 纯随机期望值），
无 zlib/gzip/zstd/xz/lz4 魔数、zstd 解码失败、无可辨认的 RISC-V/Falcon 代码特征
⇒ **FMC/GFW 镜像体是密文（非明文代码、非标准压缩）**。
⇒ 即使设备把 key-hash **钉在 FMC 镜像内部**，本地静态也**不可能**看到（这一点必须明写）。

**(E10) 设备侧确有 ECDSA**：`secp384r1` b 系数常数在三份二进制各命中 4–5 次
（`gsp_inner_19f040_a.elf`/`gsp_inner_570144_main.elf`/`gsp61057_rx_full.bin` = 5/4/5），
P-256 b 命中数完全相同（5/4/5）⇒ GSP-RM 内含 P-384/P-256 实现；但它与 FMC 公钥无关
（FMC 键 0 命中）。

---

## 2. 明确写出"没找到"的范围（NONE / 搜过的范围）

| 问题 | 结果 | 搜过的范围 |
|---|---|---|
| 设备侧材料里有没有 FMC 公钥（任何编码）？ | **NONE** | 3 份 GSP-RM/RX 二进制全字节；30+18 个模式变体 |
| 有没有公钥的 SHA-256/384（整键 或 x\|\|y，含 16/20-B 截断）？ | **NONE** | 同上 + §1.2 全部 ROM/NVFW/fwpkg/GSP 容器/nvflash |
| 有没有把两者绑定的"key-hash 比对"常量/表？ | **NONE** | 上述二进制 + 所有已发布 `dev_fuse*.h` + 开源树 `grep -riE "key.?hash|pubkey.?hash|fingerprint|trust.?anchor"`（命中全部属于 hashmap/SPDM 库） |
| 有没有 key/hash 熔丝字段名？ | **NONE** | 165 个 `NV_FUSE_*` 名 + `dev_fuse*.h` 全文 + `ctrl2080fuse.h`（空壳） |
| `FLCN_ERR_HS_*`（0xC8/0xD1/0xD2/0xA2）的产出点？ | **NONE（设备侧）** | 3 份设备二进制 grep；只在 host `flcnretval.h` 定义 |
| COT/SPDM 消费代码里有没有 pin？ | **NONE（可见范围）** | `fsp/`、`sec2/`、`spdm/`、`spdm_proxy/`、`conf_compute/`、`libspdm`（`verify_public_key_hash` 无外部 caller）；设备侧二进制只含 `RmDisableCotCmd`/`RmSpdmEnableFuzz`/`RmConfComputeSpdmPolicy` 三个 regkey 名 |
| FMC 验签器本体（代码）在不在本地？ | **NONE** | FMC image = 密文；FSP_RUN = vBIOS 内 v6 加密对象；BootROM 不在本地 |

**边界说明（必须与结论一起读）**：本次能证伪的只是"**可见材料**里存在绑定常量/字段"。
FMC 验签发生在 **FSP（vBIOS `FSP_RUN` app 0x24/target 0x0f 的 v6 加密对象）
/BootROM/FWSECLIC ucode** 内部；这三者本地都没有明文，因此
**"设备钉了但看不见"与"设备没钉"在本地静态上是不可区分的**——这正是判定为 UNKNOWN 的原因。

---

## 3. 判定：钉了 / 没钉 / 未定 —— 四格矩阵

| 形态 | 本地支持证据 | 本地反证 | 判定 |
|---|---|---|---|
| **整把公钥钉在熔丝** | E13b（`fuserework_debug_gfw_pub_key.bin` + `GetFuseKeyToInstall`/`SetInstalledFuseKey`） | 无 prod 变体字符串；无 key 宽熔丝字段（E3） | **UNKNOWN（偏"存在"）** |
| **只钉 key-hash（熔丝或 ROM）** | E13b（`..._gfw_hash.bin` 与 `..._gfw_pub_key.bin` 并列命名）；E6（`BOOTLOADER_UCODE_HASH_MISMATCH`、`…_SIG_MISMATCH_WITH_GPU_FUSE` 证明设备确实做 hash/fuse 比对） | 本地无任何 hash 常量（E1/E2） | **UNKNOWN（机制存在，落点不可判）** |
| **公钥/hash 钉在 ROM（BootROM/FSP ucode）** | E8（经典路径不给键 ⇒ 键必在设备侧）；E9（FMC 密文 ⇒ 逻辑只可能在不可见处） | 不可读 ⇒ 无法直接证实 | **UNKNOWN（最保守读法）** |
| **完全没钉（纯信任 host）** | E5/E14（host 能发、也能不发；结构体无 pin 字段） | **E8 结构性反证**（经典路径 host 不给键却仍需验签）+ E6/E13b | **基本被排除（不可信）** |

**一句话结论**：
> 设备**有**钉扎（至少 debug GFW 键材料可经熔丝返修装入；prod 路径也必然存在某种锚点，
> 否则经典 `.fwsignature_*` 路径无法解释），但**"整键 vs 仅 key-hash""熔丝 vs ROM"
> 在本地方案内不可判**；可见材料里既没有任何 pin 常量，也没有任何 key/hash 熔丝字段。
> 因此本项目对这条路径的可行性判断**不能升级为"可自签"**——按最保守读法应按"钉扎存在"处理。

对 `GB202_WRITE_LADDER_PLAN_20260925.md` §"最重要的 UNKNOWN" 的更新：
该节把判定线索列为 `0xC8/0xD1/0xD2` 的产出点 + COT 消费代码 + key-hash 熔丝字段。
本次结论：**前两者在本地不可得**（0xC8/0xD1/0xD2 名称不在设备侧二进制；FMC 错误码被压成
不透明 16-bit；COT 消费在 FSP 内部），**第三者出现了间接正证**（`gfw_hash` 与熔丝返修流程同名），
但未闭合到 GB202 prod。⇒ 该 UNKNOWN 的状态从"无线索"变为"有机制线索、缺闭环"。

---

## 4. 决定性的纯静态后续步骤（按投入产出排序）

> 全部为离线只读分析；不涉及设备访问、不写熔丝、不刷写、不联网。

**S1（最高价值）：把 GB202 的"可熔丝字段全集"枚举出来，直接判定是否存在 key/hash 宽度的字段。**
用已有 `/home/user/rt_5090_project/gb202_reghal_offline.py` 解码 MODS 570.215 的 RegHal 表（file `0x9043c8f`，chip=0xff2，
domain 5 = fuse/PRI，base `0x820000`），枚举**全部** fuse-domain 行（含 width/index 语义），
而不是只看已发布 swref 的 5 个名字；重点找 (a) 与 `0x41C0/0x4140/0x74C` 相邻的行，
(b) 行宽为 48/96/384 bit 或多行拼接的字段。
若存在这样的字段 ⇒ **"熔丝承载键/键哈希"从字符串级证据升级为表级证据**；
若不存在 ⇒ 可把"整键熔丝"和"hash 熔丝"两条同时降级，结论明确偏向 ROM。

**S2：闭合 MODS `FuseRework` 的执行语义（x86-64 反汇编，离线）。**
对 `fuserework_debug_gfw_pub_key.bin`(VA `0x8CDD650`)、`..._hash.bin`、`..._sig.bin`、
`fuserework.bin`、`installKey_`、`fuseKey_`、`Installing key %s`、`Setting L2Key to %s`
做 `.text` 内引用搜索（RIP-relative/立即数；MODS 基址 0x400000，`.text` @ `0x4a0ac0`）。
要回答：这四个文件里**哪一个是被写入熔丝的载荷**、`gfw_hash` 是"镜像 hash"还是"键 hash"、
RSA 验签用的是**内嵌**公钥还是**文件提供**的公钥。
判据：若验签公钥内嵌 ⇒ 工具链本身有 pin（且可提取其公钥/指纹）；若 hash 进入 fuse 写入路径 ⇒
"只钉 hash"形态获得实证。

**S3：恢复 ucode 错误码的数值域（本地即可做）。**
以 `cot_pin_work/FWSECLIC_ERR_CODE_names_61057.txt`（90 项，含地址）为索引，在
MODS 570.215 的**同名错误名池**里寻找 `{code, name}` 成对表或平行数值数组
（MODS 是 ELF64 且有 491 KB `.dynstr`，容易定位）；若拿到数值 ⇒
把 `0xC8/0xD1/0xD2/0xA2` 与 `BOOTLOADER_UCODE_HASH_MISMATCH` 等对齐，
再在 host RM/GSP-RM 里搜这些**数值常量**作为比较立即数 ⇒
直接找到"hash/fuse 比对"的产出点（这正是本任务要找的 key-hash 比对类常量）。

**S4：判定 vBIOS 内 FSP/FWSECLIC 对象是否为"可读兄弟样本"。**
对 4 份 canonical GB202 ROM 的 Falcon 表（app `0x24`/target `0x0f`，`FSP_RUN` v6，flags `0x0d`）
做容器/加密态刻画（长度、`+0x50` 描述符、熵、是否携带 cert block）；
同时把 GB100/GB20B/GH100 的本地 ROM/NVFW/fwpkg（HGX B300/B100-B200 包）里同族表项一起列出，
找是否存在**明文**的 FSP/FWSEC/FWSECLIC 表项（app `0x05/0x45/0x85` 或 flags 非加密）。
只要在任一同族样本上找到明文 FSP/FWSECLIC ⇒ 该 ucode 的验证逻辑（含是否有 key-hash 常量）
即可静态读出，并可按家族外推 GB202。

**S5：定位设备侧 FMC 错误码的"消费点"，把可见错误面与检查项对齐。**
在 RX 切片/GSP-RM 中搜索 `NV_PBUS_SW_SCRATCH_GSP_FMC_ERROR` 的读点
（FMC error 的 scratch 索引 0x37 → `NV_PBUS_SW_SCRATCH` 基址可由 `dev_bus_addendum.h` 给出的
域基址 + index 推得），以及 GSP-RM 是否真的消费 FWSECLIC 名称池
（若存在 90 项的数值表 ⇒ 见 S3；若不存在 ⇒ 名池只是宿主 RM 的构建产物，
设备侧错误面更小）。结合 `gsp61057_rx_full.bin` 的 RV64 反汇编（capstone/cs_riscv 已可用）
判定 `VARIANT=SK`（SK_ERROR/SK_PHASE）命名域。

---

## 5. 附录：本次产生的可复算工件

| 文件（`rt_5090_project/parallel/cot_pin_work/`） | SHA-256 | 说明 |
|---|---|---|
| `cot_pin_scan.py` | `e127677367698d2c69741b64cea7627c3b52981dee73ea8c8b7c1dcc2ad0e41a` | 30 模式 × 3 设备二进制扫描（E1） |
| `fmc_key_local_scan.py` | `8de0a1b04434dc86aee5e29beb7cbdce01ab728cff111c94d9b93675fc6e255c` | 本地固件/工具集合扫描 + 阳性对照（E2） |
| `fwsignature_frame_probe.py` | `a566192de24ccd469225bf0aff39269c528e4bb408c765463e00049d2766231b` | `.fwsignature_*` 帧结构/曲线点/验签尝试（E8） |
| `FWSECLIC_ERR_CODE_names_61057.txt` | `55ebf4743eaf168201cda96e515ce2f75e58cec6a098c14a41978e62184af252` | 90 项 FWSECLIC 错误名 + 文件偏移（E6） |
| `off_gsp61057_rx_full.bin.txt` / `off_gsp_inner_570144_main.elf.txt` | — | 带偏移 strings（用于定位/反汇编） |
| `strings_mods570215.txt` / `off_strings_mods570215.txt` | — | MODS 570.215 全字符串（830,677 行） |
| `mods570215_syms.txt` | — | MODS `.dynsym` 全量（4,190 条，绝大多数为 cutlass/boost）——**其中没有 `FuseReworkHelper`/`SetRework*` 符号**，故 S2 必须靠字符串引用 + 原始反汇编定位 |

引用的本机输入（复核用）：

| 输入 | SHA-256（前 16） |
|---|---|
| greenfield open-gpu `HEAD=d7b969d1`（610.43.03） | — |
| `/usr/src/nvidia-610.57.04/src`（与 greenfield 相关路径逐文件 diff：仅 1 个 trace 文件 + 1 个无关寄存器头不同） | — |
| `gsp_inner_19f040_a.elf` | `bda917c955476443` |
| `gsp_inner_570144_main.elf` | `6c36425881780a14` |
| `gsp61057_rx_full.bin` | `50614073f1ca73d4` |
| MODS 570.215 `mods` | `6645d5de5e0ce3c9`（既有报告） |
| `fmc-570.144.bin.zst` → image 199,240 | pubkey `af870e5d…` |

**免责/边界复述**：本文不涉及 5090D/任何 SKU 的算力或授权策略，不给出刷写、重签、
熔丝写入、固件移植的步骤；E13/S1/S2 中对熔丝返修流程的分析**仅用于解释信任锚点的位置**，
不构成任何可执行的改写方案。

# 明文 GSP-RM 里的 FWSEC 调用路径：纯静态定位（RTX 5090 / GB202，gsp-570.144.bin）

日期：2026-09-26
范围：**只读**。全部结论来自磁盘字节 + 本地反汇编。没有打开 `/dev/nvidia*`、没有 MMIO/BAR、
没有 flash/reset/rebind、没有跑任何 GPU 实验、没有修改任何既有文件。
新增文件只有本报告与一份数据附件
`DS_FWSEC_ERRCODE_TABLE_20260926.txt`（347 条 FWSECLIC 错误码→名字）。

主目标：`/tmp/fwscan/gsp-570.144.bin`（63,571,696 B，ELF64 REL "UCB RISC-V"，`BuildID=1e5654b5…`）。
`.fwimage` = file `0x40..0x40+0x3c99000`，把它当成一个扁平 blob；`VA = 0x01000000 + (file_off - 0x40)`
等价于 `blob_off = VA - 0x01000000`。**这个映射在本轮被独立重新验证过**（见 §1）。

---

## 0. 结论摘要

| 问题 | 结论 | 证据强度 |
|---|---|---|
| 明文 RM 里能不能看到"把镜像交给 fwsec/SEC2"的那次调用？ | **看不到。** 明文 RM 里只有 **选项开关**（registry/registry-like 名字）和 **FWSECLIC 客户端的错误码**；没有提交镜像的那段代码 | 负结果，多路独立搜索 |
| 加密模式（CTR/GCM/CBC）能从调用方看出来吗？ | **不能。** 名字空间里没有 mode/IV/key-id/nonce/SEID 字段；只有 `..._ERR_IV_CTR_OVERFLOW`、`AES-GCM AAD START` 等**状态/跟踪名** | 见 §5 |
| AES 引擎寄存器编程（kslot / AES START） | 找到**跟踪串所在的整段 crypto 引擎代码**（VA 0x01c38000–0x01c46000），但**没有**拿到寄存器偏移：GSP-RM 的 MMIO 全走运行期 aperture 指针（`pGpu+0xB98`），静态常量基址扫描 0 命中 | 部分完成 |
| 镜像/表解析器（`0x0050060d` 家族、`FSP_RUN`、bit2=ENCRYPTED、28 字节字段） | **明文 RM 里不存在。** 上述魔数/标签在 63.5 MB 里 0 命中，也没有任何 `lui+addi` 构造出 `0x005 0xxx` | 强负结果 |
| 有没有别的收获 | **有**：定位了 host 侧 **FWSECLIC/UDE 客户端模块**（VA 0x012d2000–0x012d7fff），解出 **347 条 FWSECLIC 错误码→名字**（附件），并定位了 **ACR/SEC2 选项消费点**、**SEC2 ucode 装载选项点** | 强 |

---

## 1. 地址映射的重新验证（并且修正 brief 里的一处误判）

brief 说"文件偏移 0x388d69 处有 `lui ... 0x1e09`"。本轮核实：

* 我把整个 63.5 MB 里所有 `lui` 解码一遍，`imm20 ∈ {0x1e08,0x1e09,0x1e0a,0x1e0b}` 的
  **只有 1 处**，就是 file off `0x388d69`（`bytes=37 84 e0 01` → `lui x8,0x1e08`）。
* 但 `0x388d69` 是**奇数**，RISC-V 指令至少 2 字节对齐 ⇒ 这个位置不可能是指令起点。
  也就是说：**brief 里的那条"lui 页引用"是未对齐数据里的巧合字节**，不是真引用。

真正的引用方式我重新做了全量解码：**全部是 `auipc` 相对寻址**（本镜像里没有 PIC relocation，
代码对数据的引用一律是 `auipc rd,HI20` + `addi rd,rd,LO12`）。方法：

```bash
# /tmp/fwsec/pairs2.py —— 全文件枚举 auipc/lui + (addi|c.addi)，解出 32-bit 目标并落盘
cd /tmp/fwsec && python3 pairs2.py      # -> addr_pairs.tsv  (166,204 条)
```

抽样交叉验证（都能对上已知字符串，误差 0，与 brief 给出的锚点一致）：

| 引用点 VA（=pc 的 auipc） | 解出 | 字符串 |
|---|---|---|
| `0x012d24b4` | `0x01e0cc40` | `NV_UDE_ERR_SEMUTEX_ACQUIRE_VPR_SCRATCH_MUTEXPLM_WRITE_TIMEOUT_WRITE_COMPLETE` |
| `0x01c3a752` | `0x01e08a90` | `AES START` |
| `0x01c3a7dc` | `0x01e08aa0` | `before kslot clear` |
| `0x011af03e` | `0x01e0a458` | `ucode_desc` |
| `0x01295a30` | `0x01e0b6c8` | `RmDisableFwseclic` |

另外两个旁证：

* 代码里 `auipc a5,0x301e / ld a5,…` 解出的 **RW 全局区落在 VA 0x0400_0000–0x041D_5000**，
  与既有工程 `parallel/ds_work/ds_global_usage.py` 里用的 RW 范围 `0x4000000–0x41D5000` 一致。
* 起始代码 `VA 0x01000000` 反汇编为合法函数序（`auipc t0,0x64; addi; lb; beqz; j`），
  说明 `0x01000000` 是代码段起点（= `.fwimage[0]`）。

**修正后的映射（本轮所有结论都用它）**：`blob_off = VA - 0x01000000`，`file_off = VA - 0x01000000 + 0x40`。
自检：`VA 0x01e0b708`（brief 给的锚点）→ file `0xe0b748` → 字符串 `RMExecuteFwsecOnSec2`。✔

---

## 2. FWSEC 调用链：明文 RM 里到底有什么

### 2.1 先说负结果（很重要）

对这 63.5 MB 做精确字节搜索：

| 搜索串 | 命中 |
|---|---:|
| `FalconUcodeFWSecLic` / `FwSecProd` / `FwSecDbg` / `FwSecLic` | 0 |
| `fwsec`（小写）/ `FwSec` | 0（只有 `RmDisableFwseclic`、`RMExecuteFwsecOnSec2` 里的 `Fwsec`） |
| `NV_FWSECLIC_*` | 128 |
| `SEC2MUTEX`（含 `NV_UDE_ERR_SEC2MUTEX_*`） | 40 |
| `GFWIMAGEPARSER` | 8 |
| `VBIOS_VERIF` | 11 |
| 4 字节魔数 `0x0050060d / 0x0050061d / 0x0050061f / 0x00500605` | 0 |
| 8 字节标签 `FSP_RUN`(`0x4e55525f50534600`)、`OOBHUB`(`0x48424f4f`) | 0 |

而且：全文件**没有**任何 4 字节或 8 字节字面量等于
`0x01e0b6c8`(`RmDisableFwseclic`) / `0x01e0b6f8`(`RMExecuteFwsecOnSec2`) / `0x01e0b698`(`RMExecuteDevinitOnPmu`)。
⇒ **brief 里"字符串是表、被间接索引"的猜测不成立**：这批名字全部是**内联的 `auipc+addi` 字面量**，
每个名字只有 1 个（或少数几个）引用点。这解释了"直接找谁引用了某个字符串命中很少"。

**结论：明文 GSP-RM 里没有"提交镜像给 fwsec/SEC2"的那段代码。** RM 侧只做三件事：
(a) 读选项；(b) 把选项存进对象；(c) 解码/上报从安全侧回来的状态码。

### 2.2 RM 侧读 FWSEC 选项的地方（registry 初始化函数，VA 0x01295xxx）

代码特征串（可复现的固定模式）：

```
addi a2, s0, -0x1b4        ; 出参
auipc a1, <名字>           ; 选项名
jalr  ra, ...              ; -> VA 0x011565f4  (RM 的 registry 读帮助函数, blob off 0x1565b4)
sext.w a5, a0
beqz  a5, <skip>
lw    a4, -0x1b4(s0)
sw    a4, OFF(a5)          ; 写进 RM 全局 registry 对象
```

解出的引用点（`addr_pairs.tsv` 过滤）：

| 引用点 VA | file off | 选项名 | 字符串 VA |
|---|---|---|---|
| `0x012959f4` | `0x295a34` | `RMExecuteDevinitOnPmu` | `0x01e0b698` |
| `0x01295a12` | `0x295a52` | `RmDevinitDmaUseSPA` | `0x01e0b6b0` |
| `0x01295a30` | `0x295a70` | **`RmDisableFwseclic`** | `0x01e0b6c8` |
| `0x01295a58` | `0x295a98` | `RMSbProgressProfiling` | `0x01e0b6e0` |
| `0x01295a76` | `0x295ab6` | **`RMExecuteFwsecOnSec2`** | `0x01e0b6f8` |
| `0x01295a9c` | `0x295adc` | `RMDevinitBySecureBoot` | `0x01e0b710` |
| `0x01295e14` | `0x295e54` | `RMDevinitBySecureBoot`（第 2 次读） | `0x01e0b710` |
| `0x01295fa2` / `0x01296396` | — | `RMDevinitBySecureBoot`（共 4 个引用点） | `0x01e0b710` |
| `0x01296158` | — | `RMHulkCertSize` | `0x01e0b728` |
| `0x012961d0` | — | `RmHulkDisableFeatures` | `0x01e0b748` |
| `0x01296212` | — | `RmIgnoreHulkErrors` | `0x01e0b760` |
| `0x0129611c` | — | `RmDisablePreosapps` | `0x01e0b778` |

反汇编片段（`addi a5,zero,CODE` 那种错误块之外，这里是选项读取；file off 0x295a70 起）：

```
0x01295a2c  1306c4e4  addi a2, s0, -0x1b4
0x01295a30  9765b700  auipc a1, 0xb76            ; pc+0xb76000 = 0x01e0ba30
0x01295a34  938585c9  addi a1, a1, -0x368       ; -> 0x01e0b6c8  "RmDisableFwseclic"
0x01295a3a  9710ecff  auipc ra, 0xffec1
0x01295a3e  e780a0bb  jalr ra, ra, -0x446       ; -> 0x011565f4
0x01295a42  9b070500  sext.w a5, a0
0x01295a48  0327c4e4  lw a4, -0x1b4(s0)
0x01295a50  23a8e75c  sw a4, 0x5d0(a5)          ; 公共写回尾
```

**注意**：`RmDisableFwseclic` / `RMExecuteFwsecOnSec2` 在全镜像里各只有 **1** 个引用点，
而且都在这段"一次性把 registry 全读进对象"的初始化代码里 ⇒ 消费者只可能通过
**对象字段**（上面 `0x5d0/?` 之类的偏移）去读，不通过名字。这是"从选项到行为"的断点。

### 2.3 ACR / SEC2 选项消费点（真正跟 SEC2 打交道的模块）

`RMAcrExecuteOnSec2`、`RmSec2*`、`RmDisableSec2*`、`ucode_data/manifest` 这批名字集中在
两段代码：

**(a) ACR/SEC2 选项函数，VA 0x018e0e00–0x018e10xx**

| 引用点 VA | 选项名 | 字符串 VA |
|---|---|---|
| `0x018e0e82` | `RmAcrSigningAlgo` | `0x01e79260` |
| `0x018e0ece` | `RMDisableAcr` | `0x01e79288` |
| `0x018e0ef2` | `RMEnableAcr` | `0x01e79298` |
| `0x018e0f16` | `RmSec2EnableApm` | `0x01e792a8` |
| `0x018e0f3a` | **`RMAcrExecuteOnSec2`** | `0x01e792b8` |
| `0x018e0f62` | `RmEnableRiscvLs` | `0x01e792d0` |
| `0x018e107c` | `RMAcrUseCeForShadowCopy` | `0x01e79320` |

**(b) SEC2 ucode / ACR 装载初始化，VA 0x018f5600–0x018f5c80**

| 引用点 VA | 选项名 | 字符串 VA |
|---|---|---|
| `0x018f566e` | `RmDisableSec2` | `0x01e79b40` |
| `0x018f569a` | `RmSec2EnableGfnPlatform` | `0x01e79b50` |
| `0x018f5700` | `RmDisableSec2Load` | `0x01e79b68` |
| `0x018f5728` | `RmSec2EnableApm` | `0x01e792a8` |
| `0x018f5778` | `RmSec2UcodeProfile` | `0x01e79b98` |
| `0x018f57a0` | `RmEnableRiscvLs` | `0x01e792d0` |
| `0x018f57d4` | `RmSec2FalcTrace` | `0x01e79bd0` |
| `0x018f57fc` | `RmSec2RtosOverrides` | `0x01e79be0` |
| `0x018f5818` | `RmSec2Bug2540582War` | `0x01e79bf8` |
| `0x018f5878` | `RmSec2PrEnabled` | `0x01e79c10` |
| `0x018f5c10` | `RMSec2UseDebugFuseOnlyBinary` | `0x01e79bb0` |
| `0x018fa314` | `ucode_data` | `0x01e79cb0` |
| `0x018fa32a` | `ucode_manifest` | `0x01e79cc0` |
| `0x018f253a` | `ucode_lsf_desc_dbg` | `0x01e79958` |
| `0x018f2524` / `0x018f2840` | `ucode_desc_dbg` / `ucode_desc_prod` | `0x01e6d308` / `0x01e6d318` |

`ucode_*` 名字的完整族群（同族一起排布的字符串，说明属于同一子系统）：

```
ucode_image / ucode_image_dbg / ucode_image_prod / ucode_image_desc
ucode_desc  / ucode_desc_dbg  / ucode_desc_prod
ucode_lsf_desc / ucode_lsf_desc_dbg / ucode_lsf_desc_prod
ucode_lsf_lsb_header / ucode_header / ucode_header_dbg / ucode_header_prod
ucode_data / ucode_data_dbg / ucode_data_prod / ucode_manifest / ucode_manifest_dbg/prod
ucode_sig_dbg/prod / num_sigs_per_ucode_dbg/prod / ucode_hs_ovl_sig_* / sig_prod / sig_dbg
lc128_prod / lc128_dbg / lc128_pa / ucode_sig_patch_loc / ucode_sig_patch_sig
```

⇒ 这就是"要往某个安全引擎（SEC2）装载并验签 ucode 镜像"的那套名字。
但**这里只出现"读选项/取名字"，看不到把镜像地址、长度、IV、key-id 交给谁**。

### 2.4 "传给 fwsec/SEC2 的字段" —— 明确回答

**在明文 GSP-RM 里拿不到。** 我能给出的最接近的直接证据是 §3 的错误码枚举，
它揭示的是**命令结果面**（要验什么），不是**输入参数面**（镜像/IV/mode）。详见 §5。

---

## 3. 本轮最大的实质突破：host 侧 FWSECLIC/UDE 客户端模块

### 3.1 位置

代码 VA **0x012d2000 – 0x012d7fff**（file off `0x2d2040–0x2d8040`）：该区间内
**440 个 `jalr` 全部打到同一个 logger `VA 0x01afcea4`**，其中我用模式匹配解析出 **347 个
完整的"错误上报块"**（全部是 `NV_*_ERR*` 名字；另 93 个是同一 logger 的其它调用形状）。

块的固定形状（编译器把错误路径内联展开）：

```
addi a5, zero, CODE            ; <-- 错误码常量
sd   a5, -0x40(s0)             ; 记录[0] = code
auipc a5, K1 / addi a5,a5,D1   ; -> const char*（错误名，落在 0x1e0bf00–0x1e11600）
sd   a5, -0x38(s0)             ; 记录[1] = name
auipc a5, 0x1f0xx / addi ...   ; -> 指向 VA 0x2034xxxx 的一张表（**不在本镜像**，见 §7）
sd   a5, -0x30(s0)             ; 记录[2] = 那个指针
addi a1, s0, -0x40
auipc ra, 0x829 / jalr ra, ra, X   ; -> 0x01afcea4
j    <公共尾部>
```

真实反汇编（file off `0x2d24ec`，code=`0x432`）：

```
0x012d24ac  93072043  addi a5, zero, 0x432
0x012d24b0  2330f4fc  sd   a5, -0x40(s0)
0x012d24b4  97a7b300  auipc a5, 0xb3a
0x012d24b8  9387c778  addi a5, a5, 0x78c        ; -> 0x01e0cc40
0x012d24bc  2334f4fc  sd   a5, -0x38(s0)         ; "NV_UDE_ERR_SEMUTEX_ACQUIRE_VPR_SCRATCH_MUTEXPLM_WRITE_TIMEOUT_WRITE_COMPLETE"
0x012d24c0  9727071f  auipc a5, 0x1f072
0x012d24c4  93878718  addi a5, a5, 0x188        ; -> 0x20344648  (**出界**)
0x012d24c8  930504fc  addi a1, s0, -0x40
0x012d24ce  2338f4fc  sd   a5, -0x30(s0)
0x012d24d2  97b08200  auipc ra, 0x82b
0x012d24d6  e780209d  jalr ra, ra, -0x62e      ; -> 0x01afcea4
```

### 3.2 解出来的 ID→名字表

```bash
cd /tmp/fwsec && python3 errblocks2.py 0x12d2000 0x12d8000
# 347 个不同错误码；完整表已落盘：
#   /home/user/rt_5090_project/parallel/DS_FWSEC_ERRCODE_TABLE_20260926.txt
```

枚举从 `0x20` 起，是**连续的**（0x20,0x21,…,0x14x）。关键区段（原文照抄）：

```
0x0020 NV_FWSECLIC_ERR_SEMUTEX_RELEASE_BSI_WRITE_MUTEXMUTEX_WRITE_TIMEOUT_WRITE_COMPLETE
0x0025 NV_FWSECLIC_ERR_CODE_CMD_UNSUPPORTED_GPU
0x0026 NV_FWSECLIC_ERR_CODE_CMD_UNSUPPORTED_COMMAND
0x0027 NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_DEVID_FAIL
0x0028 NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_CERT_NOT_FOUND
0x0029 NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_CERT_PARSE_FAIL
0x002a NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_CERT_VERIFY_FAIL
0x002b NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HAT_FAIL
0x002c NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_BIOS_SIG_FAIL
0x002d NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HULK_INIT_FAIL
0x002e NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HULK_KA_NOT_FOUND
0x002f NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HULK_TYPE_INVALID
0x0030 NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HULK_SIG_INVALID
0x0031 NV_FWSECLIC_ERR_CODE_CERT_UNKNOWN_ERROR
…
0x0034 NV_FWSECLIC_ERR_CODE_CERT_UNSUPPORTED_VERSION
0x003a NV_FWSECLIC_ERR_CODE_CERT_UGPU_PERSONALITY_MIS_MATCH
0x003b NV_FWSECLIC_ERR_CODE_CERT_HULK_ECID_MISMATCH
0x003d NV_FWSECLIC_ERR_CODE_ECID_ENCODING_ALGO_UNKNOWN
0x003f NV_FWSECLIC_ERR_CODE_DERIVED_KEY_TYPE_INVALID
0x0040 NV_FWSECLIC_ERR_CODE_UCODE_NOT_IN_HS_MODE
0x0049 NV_FWSECLIC_ERR_CODE_FWSECLIC_PCI_EXP_ROM_NOT_FOUND
0x004a NV_FWSECLIC_ERR_CODE_VERIFY_ENG_HULK_3AES_SIG_MISMATCH_WITH_GPU_FUSE
0x004b NV_FWSECLIC_ERR_CODE_VERIFY_ENG_HULK_NO_3AES_SIG
0x004c NV_FWSECLIC_ERR_CODE_DEVID_MATCH_LIST_DEVID_MATCH_FAILED
0x004d NV_FWSECLIC_ERR_CODE_VERIFY_LICENSE_UGPU_SIG_INVALID
0x004f NV_FWSECLIC_ERR_CODE_CERT_HULK_REG_READ_BACK_VERIFY_MISMATCH
0x0051 NV_FWSECLIC_ERR_CODE_HULK_INST_IN_SYS_VERIFICATION_FAILED
0x0054 NV_FWSECLIC_ERR_CODE_PRI_TRANSACTION_ERROR
0x0056 NV_FWSECLIC_ERR_CODE_CERT20_INTBLK_VDPA_HEADER_INVALID
…
```

另有两个同族表（同一个模块，也在 0x12d2xxx 里）：

* `NV_UDE_ERR_*`（`0x1e0bec8–0x1e0c7f0`）：其中含
  `NV_UDE_ERR_VBIOS_VERIF_COMPLETED_AND_FAILED`、`NV_UDE_ERR_FWSECLIC_DID_NOT_EXECUTE`、
  `NV_UDE_ERR_UCODE_DMEM_VERIFICATION_FAILED`、`NV_UDE_ERR_SEC2MUTEX_ACQUIRE_*`、
  `NV_UDE_ERR_DEVINIT_{TABLE,SCRIPT,RESIGN_DATA_PATCHER,AUTHENTICATE_DATA_PATCHER}_*`
  （大量 `..._DOAESECB_NOT_IN_HSMODE`）。
  引用点：`0x012d46fa`(FWSECLIC_DID_NOT_EXECUTE)、`0x012d472c`(VBIOS_VERIF_COMPLETED_AND_FAILED)…
* `NV_UCODE_ERR_*` / `NV_UCODE_ERR_CODE_GFWIMAGEPARSER_*`（`0x1e10010–0x1e11600`）：
  `GFWIMAGEPARSER_INVALID_FW_IMAGE / INVALID_ROM_SIGN / CERT_BLOCK_NOT_PRESENT /
  INFORM_BLOCK_NOT_PRESENT / INVALID_EXTIMG_DATA / IFR_INVALID_SIZE / INVALID_IFR_IMAGE`，
  以及一大堆 `NV_FWSECLIC_ERR_SEMUTEX_*`（PLM / BSI / VPR-SCRATCH 两个方向的 mailbox 超时）。
  引用点：`0x012d4bdc`(INFOROM_BLOCK_NOT_PRESENT)、`0x012d2838`(INVALID_FW_IMAGE)、
  `0x012d2806`(INVALID_IFR_IMAGE) 等（GFWIMAGEPARSER 一簇，`0x012d2806–0x012d2a6c`）…
  另有 `NV_COMPACTION_ERR_*`（`0x1e125xx`）、`NV_DEVINIT_ERR_*`（`0x12d355c` 起）、
  `NV24/UCODE_ERR_*`。

**这批错误名的语义值得单独指出**（这是 brief 没料到的）：

* `SEMUTEX / BSI_WRITE_MUTEX / PLM` + `MUTEX_READ_SENDREQUEST / GETDATA / WRITE_TIMEOUT_CHANNEL_EMPTY`
  ⇒ 存在一个**基于 mailbox 的"安全互斥量"协议**（BSI = 某块 boot-secure 接口寄存器组，
  PLM = 该接口上的命令通道），主机侧是 `SENDREQUEST → GETDATA → WRITE_COMPLETE` 的同步序列。
* `SEC2MUTEX_ACQUIRE_{BSI_WRITE,VPR_SCRATCH}_MUTEX` ⇒ 互斥量有两类：
  **BSI-WRITE** 与 **VPR-SCRATCH**（VPR = Video Protected Region）。
* `CERT_HULK_*` / `HULK_*` ⇒ HULK = 许可/授权对象（license blob），带 ECID/DEVID、寄存器覆写指令。
* `CMD_VBIOS_VERIFY_*` ⇒ 有一个 **"命令"概念**：安全侧执行 `VBIOS_VERIFY` 这类命令并回状态。
* `3AES_SIG_MISMATCH_WITH_GPU_FUSE` ⇒ 有"三把 AES 签名 vs GPU fuse"的比对（不是 3DES，是 3 路 AES）。
* `CERT20_VDPA_*` ⇒ 有 vDPA/证书 2.0 的中间块格式。

---

## 4. AES 引擎的寄存器编程代码：找到了模块，没拿到寄存器偏移

### 4.1 定位

用 `addr_pairs.tsv` 反查 trace 串，得到整个"crypto 引擎库"的代码范围
**VA 0x01c38000–0x01c46000**（file off `0xc38040–0xc46040`）。该范围内被引用的 trace 串：

| 引用点 VA | trace 串 |
|---|---|
| `0x01c3a7dc` | `before kslot clear` |
| `0x01c3eefc` | `after kslot clear` |
| `0x01c3ee08` | `AES START` |
| `0x01c3efb0` | `AES DONE` |
| `0x01c3acb8` | `AES-GCM AAD START` |
| `0x01c3afbe` | `AES GCM FINAL START` |
| `0x01c3b00a` | `after AES GCM FINAL` |
| `0x01c3e350` | `Keyop done` |
| `0x01c3d0cc` | `post op` |
| `0x01c384cc` | `unknown mod op` |
| `0x01c385c0` | `addition` |
| `0x01c386a0` | `inversion` |
| `0x01c38700` | `reduction` |
| `0x01c38710` | `square` |
| `0x01c40ba4` | `multiplication` |
| `0x01c40c84` | `subtraction` |
| `0x01c40cc8` | `mod exp` |
| `0x01c40ce8` | `dp reduction` |
| `0x01c3ad14` | `CCC arithmetic error\n` |

用法一律是"跟踪打印"：`auipc a1,<串>; jalr ra,…`（每个站点是一个很小的函数，打印后调下层）。
`AES0 engine [AES/RNG]` / `AES1 engine` / `NVRNG engine` / `NVPKA engine [RSA mode]` 这 4 个
**"引擎名"**落在同一个字符串池 `0x1e08948–0x1e089c8`，是**模块自报名**，不是寄存器名。

反汇编样例（file off `0xc3eef0` 附近，AES 操作尾段）：

```
0x01c3ee08  97a51c00  auipc a1, 0x1ca
0x01c3ee0c  938585c8  addi  a1, a1, -0x378      ; -> 0x01e08a90 "AES START"
0x01c3ee12  97300000  auipc ra, 3
0x01c3ee16  e780e0c8  jalr  ra, ra, -0x372      ; trace(AES START)
0x01c3ee1a  1b040500  sext.w s0, a0
0x01c3ee20  e31054f1  bne   s0, s5, -0x100      ; 失败 -> 错误路径
0x01c3ee2a  97300000  auipc ra, 3
0x01c3ee2e  e78020bd  jalr  ra, ra, -0x42e      ; 下一步
...
0x01c3ee3c  238af402  sb    a5, 0x34(s1)        ; 写状态字节
0x01c3ee5c  a389e402  sb    a4, 0x33(s1)
0x01c3ee92  97a51c00  auipc a1, 0x1ca
0x01c3ee96  9385e5c0  addi  a1, a1, -0x3f2      ; -> 0x01e08ab8 "after kslot clear"
0x01c3eefc  97a51c00  auipc a1, 0x1ca
0x01c3ef00  9385c5bb  addi  a1, a1, -0x444      ; -> 0x01e08ad0 "AES DONE"
0x01c3ef06  17330000  auipc t1, 3
0x01c3ef0a  6700a3b9  jalr  zero, t1, -0x466    ; 尾调用
```

`AES START / before kslot clear / after kslot clear / AES DONE / AES-GCM AAD START /
AES GCM FINAL START / after AES GCM FINAL` 这一串**状态机顺序**说明：
该库在一次 AES 操作里会 **先清 key-slot（两次 trace 夹住）→ 发 START → 等 DONE**，
并且**同时支持 GCM（AAD + FINAL）与（见 §5）CTR**。

### 4.2 为什么没拿到寄存器偏移（诚实的负结果）

GSP-RM 访问 MMIO 的方式是**运行期 aperture 指针**（既有报告
`DS_GSP_MMIO_WINDOW_20260926.md` 已确证：`*(u64*)(pGpu+0xB98)` = `devMap[0].gpuNvAddr`，
寄存器地址 = `aperture + 0x820000 + K`）。

我在整个 crypto 区域跑了"常量基址"追踪（`/tmp/fwsec/constmem.py`，把 `lui/addi/mv/add`
的常量传播后报告 `*(base+k)`）：

```bash
cd /tmp/fwsec && python3 constmem.py 0x1c38000 0x1c46000   # -> 0 条
cd /tmp/fwsec && python3 constmem.py 0x12c0000 0x12d8000   # -> 0 条
```

⇒ 该区域**没有**任何"常量基址 + 常量偏移"的访存，寄存器基址全部来自入参对象/全局指针，
**静态拿不到 kslot/模式寄存器的偏移与写入值**。要拿到必须做对象图追踪（`pGpu` 是堆对象，
运行期才存在），这超出纯静态范围。

**所以：`before/after kslot clear` 附近我没有寄存器偏移、没有写入值。** 只有 trace 的顺序信息。

---

## 5. 加密模式能不能从调用方看出来？——不能（给证据）

对全镜像做名字空间搜索（大小写不敏感 / 词边界）：

| 模式：`seid` / `key_slot` / `keyslot` / `keyid` / `nonce` / `aes_ctr` / `aes_cbc` / `derivehwkey` / `bsi` / `vpr` / `ecid` / `gcm` / `cbc` / `ctr` | 命中 |
|---|---|
| `SEID` / `key-id` / `keyslot` / `nonce` / `IV`（作为参数名） | **0** |
| `AES-GCM AAD START` / `AES GCM FINAL START` / `after AES GCM FINAL` | 3（trace 名，§4.1） |
| `NV95A1_OS_ERROR_AES_CTR_FAILURE` | 1（**这是 CE/CBA 引擎的**错误码，不是 fwsec） |
| `NV_FWSECLIC_ERR_CODE_UCODE_NOT_IN_HS_MODE` / `DERIVED_KEY_TYPE_INVALID` / `3AES_SIG_*` | 见附件 |
| `NV_UDE_ERR_*_DOAESECB_NOT_IN_HSMODE` | 8（"AES-ECB" 只出现在 **Ucode DevInit 脚本鉴权**里） |
| `ECID` | 4（只在 `NV_FWSECLIC_ERR_CODE_CERT_HULK_ECID_*` / `..._ECID_ENCODING_ALGO_UNKNOWN`、`..._STRICT_ID_ECID_MISMATCH` 里） |

而 `ENCRYPT_IV_CTR_OVERFLOW` / `DECRYPT_IV_CTR_OVERFLOW` / `ENCRYPT_FAULT` / `DECRYPT_FAULT` /
`SECURE_COPY_DISABLED` / `KEY_IS_INVALID_ZERO` / `AUTH_TAG_COMPARE_FAIL` / `SRAM_SLOT_*`
**和 `RmDisableBsp` / `RmDisableBspLoad` / `ucode_desc` / `ucode_image` / `RMForceNvdecUcodeEncryption`
排在同一个字符串池里**（`0x1e0a340–0x1e0ac80`），也就是说：

* 这些 `ENCRYPT_/DECRYPT_*`、`AUTH_TAG_COMPARE_FAIL`、`SRAM_SLOT_*` 名是 **BSP/ucode 加解密子系统的状态码**；
* 同池里同时存在 **CTR**（`IV_CTR_OVERFLOW`）与 **GCM**（`AUTH_TAG_COMPARE_FAIL`、`AES-GCM AAD START`）
  ⇒ 该加密引擎库**至少支持 CTR 与 GCM 两种**；
* `KEY_IS_INVALID_ZERO` + `SRAM_SLOT_INVALID/SLOT_PREEMPTED` ⇒ 有"SRAM key-slot"抽象；
* `LAUNCHERR_REPORT_*` 一大族（`2D_LAYER_EXCEEDS_DEPTH`、`MEM2MEM_RECT_OUT_OF_BOUNDS`…）⇒
  这台引擎还带一个 2D 拷贝/搬运前端。

**但它给不出"这一次用的是 CTR 还是 GCM、IV/nonce 是什么、key-id 是多少"**：
这些名字全是**状态/错误/trace**，没有一个是参数选择器。**调用方（明文 RM）里没有模式字段。**
所以 brief 问的"CTR? GCM? CBC?"——从调用方**看不出来**；只能从"同一库同时有 CTR 与 GCM 的错误/跟踪名"
推出"两种都可能"，不能推出 VBIOS 容器实际用的是哪一种。

**唯一和 ECB 有关的间接线索**：`NV_UDE_ERR_*_DOAESECB_NOT_IN_HSMODE` 出现了 8 次
（`DEVINIT_TABLE / DEVINIT_SCRIPT / RESIGN_DATA_PATCHER / AUTHENTICATE_DATA_PATCHER` ×
`DERIVEHWKEY`/`COMPUTEAESSIGNATURE`），说明 **Ucode DevInit（UDE）脚本的鉴权链内部用 AES-ECB**，
而且是"必须先进入 HS mode 才能做"的硬件路径。这是 UDE/DevInit 的，不是 VBIOS 容器加密的。

---

## 6. 镜像/表解析器（`0x0050060d` 家族、`FSP_RUN`、bit2、28 字节）——明文 RM 里没有

| 搜索方式 | 结果 |
|---|---|
| 4 字节魔数 `0x0050060d/0x0050061d/0x0050061f/0x00500605` | 0 |
| 8 字节 `FSP_RUN`(`0x4e55525f50534600`)、`OOBHUB` | 0 |
| 4 字节 `"FSP\0"`(LE) | 0（两个 `FSP` 命中是 IR 字符串，见下） |
| 遍历全文件所有 `lui`(89 万个)，找 `imm ∈ {0x4f..,0x500,0x505,0x506,0x507}` 且随后 `addi` 拼出 `0x005 0xxx` / `0x0065 35xx` | 0（`lui 0x500` 有 55 处、`lui 0x506` 有 46 处，但**没有一处**的 addi 落在 v6 的低 12 位值上） |
| 对 `0x1e0b6c8/0x1e0b6f8/0x1e0b698/0x1e0b710`(选项名) 的 4B/8B 字面指针 | 0（再次印证"无指针表"） |

**极性与 bit2=ENCRYPTED 的判断**：明文 RM 里**没有**这种判断。RM 侧唯一相关的
"encrypted"字样是 `RMForceNvdecUcodeEncryption`（一个 registry 选项，意思是"强制加密 NVDEC ucode"）
和 `NV95A1_OS_ERROR_AES_CTR_FAILURE`（CE 引擎错误码）。

**FSP 字样**：全镜像只有两处 `FSP`：
* `FSP fuse error check has failed. Status = 0x%x.` @ VA `0x01e6d2d8`（引用点 VA `0x015e60f4`）——
  这是 GSP-RM 里**唯一的 FSP 语义字符串**，内容是"FSP fuse 检查失败"，说明 RM 会**检查 FSP 的 fuse 状态**，
  但看不到容器解析；
* 另一处是别的区域的巧合字节。

**结论**：`0x0050060d` 家族 v6 描述符、`FSP_RUN` 标签、28 字节高熵字段的解析，
**不在明文 GSP-RM 里**。结合既有报告
`FWSEC_OPT_TABLE_GB202_20260925.md`（GB202 VBIOS 用 descriptor v6，公开 RM 只认 v2/v3，且
GB202 VBIOS 里**没有** FWSEC 0x05/0x45/0x85 条目），最可能的载体是：
**FMC/bootloader（`/tmp/fwscan/fmc-570.144.bin`、`bootloader-570.144.bin`）或 SEC2 上的
FWSEC ucode 本体**（后者自身就是加密的，因此"解密器本体看不到"这一点与 brief 的前提一致）。

---

## 7. 不能确定的部分（严格区分"有反汇编证据"与"推测"）

### 7.1 有证据但没闭环

1. **`VA 0x2034xxxx` 那张表**（每个错误块的第 3 个字段）。
   * 事实：以 FWSECLIC 区间的 347 个块统计（扩到 `0x12c0000–0x12d9000` 共 443 个块，结论相同），
     第 3 字段全部落在 `0x20344180–0x20346b40`，约 11 KB，**常量步长 16 字节**，
     随代码地址增大而**单调递减**（典型"每错误码一条记录"表）。
   * 事实：按本镜像已验证的扁平映射，`0x20344648` 对应 blob off `0x10344648`，
     **远超 `.fwimage` 的 `0x3c99000`**。
   * 结论：**这张表不在我们手里这份明文镜像里**。它是 {行号, 文件名?} 之类的调试定位记录的概率很高，
     但**我没有证据**，因此不命名、不引用。
2. **`sw a4, 0x5d0(a5)` 的公共尾**：选项读完后写回哪个对象的哪个字段——我确认了代码形状，
   但因为多个选项共用同一段尾部代码，**我没有逐键解出各自的字段偏移**（需要数据流追踪）。
3. **AES/AES0/AES1 寄存器偏移与写入值**：没有拿到（§4.2）。MMIO 走运行期 aperture。
4. **`0x12d2000–0x12d7fff` 里那些错误块所在的函数边界**：我没有做完整的函数切分，
   只保证了每个块自身的指令流正确（resync 线性扫描 + 人工核对 3 处）。
5. **`RmDisableFwseclic` / `RMExecuteFwsecOnSec2` 的行为消费者**：只有"读进对象"的 1 个引用点，
   消费者通过对象字段访问，**没有定位到**。

### 7.2 纯推测（不要当结论用）

* "`ENCRYPT_IV_CTR_OVERFLOW` 说明 BSP/ucode 引擎用 CTR，`AES-GCM AAD START` 说明也用 GCM" ——
  这是从**名字共存**推出的，**没有**找到选择字段。
* "`SEC2MUTEX_ACQUIRE_BSI_WRITE_MUTEX` 说明 SEC2 通过 BSI 寄存器组做 mailbox 同步" ——
  名字支持这个读法，**没有**找到寄存器写。
* "GB202 的容器解密在 FMC 或 SEC2 FWSEC ucode 里" —— 这是**排除法**结论（明文 RM 里 0 命中），
  不是直接证据；我**没有**在 `fmc-570.144.bin` 里做本次范围的验证。

---

## 8. 可复现命令

全部脚本在 `/tmp/fwsec/`（只读脚本，不改任何既有文件）：

```bash
# 基础库（VA<->file offset，VA = 0x01000000 + (off-0x40)）
cat /tmp/fwsec/rv.py

# (1) 全文件解析 auipc/lui + addi 的地址对 -> addr_pairs.tsv (166,204 条, 约 3-5 min)
cd /tmp/fwsec && python3 pairs2.py

# (2) 反汇编（带 2 字节 resync；用法: sweep.py <va> <back> <fwd>）
cd /tmp/fwsec && python3 sweep.py 0x01295a30 0x100 0x140      # Fwsec 选项读取
cd /tmp/fwsec && python3 sweep.py 0x01c3ee08 0x80  0x180      # AES START/DONE
cd /tmp/fwsec && python3 sweep.py 0x012d24ac 0x40  0x100      # FWSECLIC 错误块

# (3) 错误码块 -> ID/名字 表（347 条）
cd /tmp/fwsec && python3 errblocks2.py 0x12d2000 0x12d8000

# (4) 常量基址访存扫描（本任务负结果：0 条）
cd /tmp/fwsec && python3 constmem.py 0x1c38000 0x1c46000
cd /tmp/fwsec && python3 constmem.py 0x12c0000 0x12d8000

# (5) 全文件 lui 立即数统计
cd /tmp/fwsec && python3 luiall.py          # 89 万条 lui/auipc；用于证明 v6 魔数不存在

# (6) 某个字符串的所有引用点
python3 - <<'EOF'
from rv import *
for l in open("/tmp/fwsec/addr_pairs.tsv"):
    o,p,v,k=l.split()
    if int(v,16)==0x1e0b6c8: print("RmDisableFwseclic <- pc 0x%s"%p)
EOF
```

---

## 9. 最后 10 行中文总结（给人看）

1. 我先把 brief 里那条"`lui 0x1e09` 页引用 + 文件偏移 0x388d69"证伪了：那是奇数偏移，不可能是指令；本镜像里**所有**数据引用都是 `auipc+addi`，我全量解出 16.6 万个地址对当索引。
2. 明文 GSP-RM 里的 FWSEC 字符串只有两类：**RM 的 registry 选项名**（`RmDisableFwseclic`、`RMExecuteFwsecOnSec2`、`RMExecuteDevinitOnPmu`、`RMDevinitBySecureBoot` 等）和**安全子系统的错误码名**。
3. 选项名是在一个"把 registry 全读进对象"的初始化函数里读的（VA 0x01295a30 / 0x01295a76，各只 1 个引用点），读进对象后消费者不再用名字 ⇒ 到这里链条断掉。
4. **真正有价值的收获**：定位了 host 侧 **FWSECLIC/UDE 客户端模块**（VA 0x012d2000–0x012d7fff），它由 347 个内联错误块组成（该区间共 440 个到同一 logger 的调用），我解出 **347 条 `NV_FWSECLIC_ERR_CODE_*` → 名字**（附件），其中 `CMD_VBIOS_VERIFY_*`、`CERT_HULK_*`、`ECID/DEVID`、`3AES_SIG vs GPU_FUSE`、`BSI/PLM/VPR-SCRATCH` mailbox 互斥量超时，把安全侧的命令面勾出来了。
5. **加密模式仍然看不到**：全镜像 0 处 `SEID/keyslot/nonce/IV` 参数名；`ENCRYPT_IV_CTR_OVERFLOW` 与 `AES-GCM AAD START` 只是**状态/跟踪名**，同池还有 `KEY_IS_INVALID_ZERO`、`AUTH_TAG_COMPARE_FAIL`、`SRAM_SLOT_*`，只能推出"该引擎支持 CTR 与 GCM 两种"，推不出 VBIOS 容器用的是哪种。
6. AES 引擎寄存器编程：定位到 crypto 库整段代码（VA 0x01c38000–0x01c46000），`AES START → before/after kslot clear → AES DONE` 的 trace 顺序清晰，但**寄存器偏移与写入值是负结果**——GSP-RM 的 MMIO 全走运行期 aperture（`pGpu+0xB98`），静态常量基址扫描 0 命中。
7. 镜像/表解析器：`0x0050060d` 家族、`FSP_RUN`、`OOBHUB` 在 63.5 MB 里 **0 命中**，也不存在构造这些常量的 `lui+addi` ⇒ **解析器不在明文 GSP-RM**，应在 FMC/bootloader 或（自身加密的）SEC2 FWSEC ucode 里。
8. 一个未闭环的硬骨头：每个错误块的第 3 个字段指向 VA `0x2034xxxx` 的一张 16 字节步长、约 670 条的记录表，但按已验证映射它落在 `.fwimage` 之外（→ blob off 0x10344648），我**不猜**它是什么。
9. 下一步（若要继续）：优先在 `fmc-570.144.bin` / `bootloader-570.144.bin` 里搜 `0x0050060d`/`FSP_RUN`；其次对 §2.3 的 ACR/SEC2 初始化函数（VA 0x018f5600–0x018f5c80）做完整函数切分 + 数据流，因为它同时握有 `ucode_data`、`ucode_manifest`、`RmDisableSec2Load` ——那是"把镜像交给 SEC2"最可能的出口。**但这需要对象图追踪，纯静态可能到不了。**
10. 全程只读：没有打开任何设备节点、没有 MMIO、没有改动既有文件；新增产出只有本报告与 `DS_FWSEC_ERRCODE_TABLE_20260926.txt`。

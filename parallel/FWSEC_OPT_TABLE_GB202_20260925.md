# FWSEC 镜像与 CTRL_OPT/floorsweep 选项表：RTX 5090 / GB202 VBIOS 静态审计

日期：2026-09-25（Asia/Singapore）
范围：只读本地文件。没有 GPU 写入、刷写、reset/rebind、MMIO/BAR、驱动的网络下载或任何
出口管制绕过；没有打开 `/dev/nvidia*`、`/dev/mem`、PCI resource、debugfs，也没有执行
任何固件/updater。全部结论来自磁盘字节 + 本地公开源码。

本文件回答四个问题：

1. 从 RTX 5090 / GB202 VBIOS 里抽出 FWSEC 镜像（app 0x05 `FIRMWARE_SEC_LIC`、
   0x45 `FWSEC_DBG`、0x85 `FWSEC_PROD`）→ **抽不到，因为 GB202 VBIOS 里没有 FWSEC 条目**；
2. 列出每个镜像的 section / 表结构 → 见 §4（含 6 个**实际存在**的 v6 镜像）；
3. 是否存在 CTRL_OPT / `OPT_*` floorsweep 选项表 → **不存在**（多重字符串与结构扫描全 0 命中）；
4. 该（假想的）表是否落在签名/哈希覆盖范围内 → **Falcon ucode 表本身在 SHA-384 manifest
   覆盖范围内**，6 个镜像的 descriptor + immediate region 也全部被覆盖；证据见 §6。

---

## 0. 结论摘要

| 问题 | 结论 | 关键证据 |
|---|---|---|
| GB202 VBIOS 有 FWSEC（0x05/0x45/0x85）吗 | **没有** | `extract_falcon_ucode.py` 三个 app id 均 `found 0`；独立结构扫描全文件只有 1 张 35-entry Falcon 表、6 个 active entry（0x07/0x18/0x19/0x15/0x23/0x24）；6 份 GB202 样本（4×5090 + 2×PRO 6000）一致 |
| 有 CTRL_OPT / `OPT_L2SLICE_FBPn_DISABLE` / `OPT_TPC_GPCn_DIS` / `OPT_FBP_L` / `ignore_for_floor` 表吗 | **没有（负结果）** | 6 个镜像的整文件与 envelope 内、以及 Ada（4090）真 FWSEC 镜像内，上述字符串命中数全部为 0 |
| Falcon ucode 表在哈希/签名覆盖内吗 | **在** | 文件 `0x61472` 的 SHA-384 manifest entry（`u32_0=0x2b`, len `0xd8`）精确覆盖 `[0x9ce9d,0x9cf75)`，摘要复算逐字节一致（§6.3） |
| 6 个镜像的 descriptor + 数据区在覆盖内吗 | **全部在** | 4 个由 manifest A entry 覆盖（`u32_0=0x36/0x87/0x88/0x9e`），2 个由 nested image 的两-entry hash table + 一级 hash record 覆盖（§6.4） |
| 170HX/GA100 的 “FwSec 尾部 CTRL_OPT 表” 能在本地验证吗 | **不能** | 本地无 GA100 VBIOS/相关材料；该断言只能作为外部声明引用，不作为本文事实 |

**重要限定**：本文只能证明“GB202 VBIOS 内不存在 FWSEC 镜像与 OPT 表”，不能证明
“GB202 平台上不存在 CTRL_OPT 机制”。Blackwell 的 FWSEC/安全处理器固件来源与
floorsweep 选项表的真实载体在本轮证据之外（§7 UNKNOWN）。

---

## 1. 输入样本

全部为本地已保存文件的只读字节。SHA-256 由脚本现算。

| key | 内容 | 文件 | 大小 | SHA-256 |
|---|---|---|---:|---|
| `gb202_5090_fe_tpu` | RTX 5090 FE `98.02.2E.00.03`（TPU） | `vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom` | `0x1defff` | `a966aca23518708e44c961af865cccfdfabebc9d0cd06a8e29577a0bd82dc5eb` |
| `gb202_5090_asus_tpu` | ASUS RTX 5090 Astral `98.02.2E.40.85`（TPU） | `vbios_diff/unverified_TPU_280522_ASUS_Astral_1043-89E3_98.02.2E.40.85.rom` | `0x1defff` | `eeb68ef4ce8b70d2f72aa1738b04e89d912c3af977722959e7ca60c1195f1111` |
| `gb202_5090_asus_official_new` | ASUS 官方 `98.02.2E.40.AS02` payload | `vbios_diff/asus_official_astral_v2_20260904/new_payload/98.02.2E.40.AS02.rom` | `0x1d2dd0` | `bb659273d533ddc973199dd4dab04ac60402fe8629f4c9e21a122601fb4653c9` |
| `gb202_5090_asus_official_old` | ASUS 官方 `98.02.2E.00.AS05` payload | `vbios_diff/asus_official_astral_v2_20260904/default_payload/98.02.2E.00.AS05.rom` | `0x1d2dd0` | `413d7c4a42193ba3ddada2c3cf4e86229dafad1c6de75cfe6abda346db67640e` |
| `gb202_pro6000_dell_nvfw` | Dell RTX PRO 6000 GB202 `98.02.8D.00.01` NVFW | `vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw` | `0x1d1dd0` | `8658724061087279f59ca3a0d8ce443cb4ca52db2543c64723a3cea632a29b59` |
| `gb202_pro6000_hpe_nvfw` | HPE RTX PRO 6000 GB202 `98.02.9E.00.01` NVFW | `vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw` | `0x1d1dd0` | `98c52f80e937907c4203280824bbef6bb17439c900edc74532072780611c0fe5` |
| `gb202_pro6000_dell_fwpkg` | Dell GB202 `98.02.8D` fwpkg 容器 | `vbios_diff/dell_8d_payload/g153_0210_895__98028D0001.fwpkg` | `0x1d1e9f` | 容器，非 BIT/PCI-chain 镜像（见 §3.4） |
| `gb202_pro6000_hpe_fwpkg` | HPE GB202 `251124` prod-signed fwpkg 容器 | `vbios_diff/hpe_scexe_payload/nvfw_RTXPRO6000BWSE_0003_251124.1.0_prod-signed.fwpkg` | `0x21a2cd` | `620b673fcbee27d90693610477344332e5f3d47ba538903f9ebcd09db52abe27`（容器，见 §3.4） |
| `ada_4090_asus_control` | RTX 4090 ASUS STRIX `95.02.3C.40.FB`（AD102 正对照） | `vbios_diff/rtx4090_multisample_20260911/collector/roms/github_asus_strix_3c.rom` | `0x1f4000` | `b330ca3ec967fbd9170ec0be72fca3dc56c0c379bf4a080bb9951696782dd072` |
| `ada_4090_msi_control` | RTX 4090 MSI Gaming Trio（AD102 正对照） | 同上目录 `github_msi_gaming_trio_95.02.18.00.52.rom` | `0x1f4000` | `3ae7bf0b9f4f4a4827bfde8a1a692592334d2d7856308344126613dd6074684b` |

RTX PRO 6000 Blackwell 使用 GB202 die，因此把两份 `98.02.8D`/`98.02.9E` NVFW 一起纳入
GB202 样本（共 **6 份 GB202 镜像**：4×RTX 5090 + 2×RTX PRO 6000）。

---

## 2. 工具、参数与容器几何

### 2.1 指定工具与其正确参数

工具：`/home/user/hulk_public_research_20260811/tools/extract_falcon_ucode.py`
（解析 BIT token `'p'`/v2 → Falcon ucode table → 表项 → v2 descriptor → IMEM/DMEM）。

对 RTX 5090 FE 的正确容器参数不是 0，必须先解出 image base 与 expansion ROM 偏移：

```text
BIT 表头               0x38df0   （header=12, token=6, 20 tokens, 校验和 = 0）
image base (skip)      0x38000   （此样本中 BIT 位于 image+0xdf0，不是其它代的 image+0x1b0）
expansionRomOffset     0x18000
Falcon 表（image 内）  0x64e9d   （= 0x9ce9d - 0x38000）
descriptor bias        0x50000   （= image base + expansionRomOffset = 0x38000 + 0x18000）
```

推导链（三条独立关系一致）：

1. `55 aa` 传统 ROM 头正好在 `0x38000`；`derived/RTX5090_FE_optionrom_chain.bin` 的大小
   `0x1a6fff` 正好等于 `0x1defff - 0x38000`，即既有工作已用过同一个 image base。
2. BIT token `'u'`/`'k'`/`'i'` 等 token 载荷（相对偏移 ≤ 0x10dc）落在 `image+0xe74..` 之后，
   与 6-byte token（`DataPtr` 为 16-bit，相对 image 起点）一致；`BIT` 表头本身也要求
   `image+0xdf0` 落在文件内。
3. token `'p'` v2 的 DataPtr = `0x10c1`，`image+0x10c1 = 0x390c1` 处的 u32 = `0x4ce9d`；
   而 `0x4ce9d + 0x50000 = 0x9ce9d` 正是独立结构扫描找到的 Falcon 表位置。

对应调用：

```bash
python3 .../extract_falcon_ucode.py \
  vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom \
  --skip 0x38000 --table-offset 0x64e9d --pointer-bias 0x18000 --app-id 0x85
```

### 2.2 另外使用的本地解析器

* `gb202_vbios_diff.py`（项目 GB202 parser：BIT、PCI chain、`expansion_offset`、Falcon 表、
  v6 descriptor header；sha256 `90cefd37e109684119e98c5ab64ef382048710dcdc344e1cd4bb5d70abb517eb`）
* `rtx4090_24g_48g_compare_20260911/compare_roms.py`（Ada parser，用于 AD102 正对照）
* 本任务脚本 `parallel/gb202_fwsec_opt_static.py`（sha256
  `d3d83a7152919f63a7fa03afe9786e5d0bdc4c7d981e89e76954fe018aaf3398`）：
  自写 SHA-384 hash-record / manifest 覆盖枚举，不依赖私有字段名。
* 独立 Falcon 表探测器（`/tmp/detect_falcon.py`，双格式 descriptor 校验，见 §3.2）。

---

## 3. FWSEC 抽取：负结果（含工具原文报错）

### 3.1 指定工具：三个 app id 全部 `found 0`

```text
$ python3 extract_falcon_ucode.py <FE rom> --skip 0x38000 --table-offset 0x64e9d \
      --pointer-bias 0x18000 --app-id 0x05 --output-dir /tmp/fwsec_5090_test
ValueError: expected exactly one app 0x05 entry, found 0

$ ... --app-id 0x45 ...
ValueError: expected exactly one app 0x45 entry, found 0

$ ... --app-id 0x85 ...
ValueError: expected exactly one app 0x85 entry, found 0
```

同一参数、同一张表、换成存在条目的 app id（证明参数与表定位正确，失败原因不是偏移错误）：

```text
$ ... --app-id 0x07 ...
ValueError: extractor supports V2 descriptors only; got version=6, size=80
```

即：表与 entry 都被工具正确找到，但 GB202 用的是 **descriptor v6**（`vDesc=0x0050061d`，
version `6`，size `0x50`），超出该工具（以及当前公开 RM）支持的 v2 范围。

### 3.2 独立结构扫描：全文件只有一张 Falcon 表

不做 BIT 索引、直接在全文件逐偏移枚举候选表头（`version==1`、`6<=headerSize<=0x40`、
`6<=entrySize<=0x40`、`1<=entryCount<=64`），要求**所有** active entry 在同一 bias 下都能
解出合法的 v1/v2/v6 descriptor（`desc+size+stored` 不越界）：

| 样本 | 命中的表 | bias | active entries |
|---|---|---:|---|
| 5090 FE | `0x9ce9d` | `0x50000` | 6 |
| 5090 ASUS（TPU） | `0x9ce9d` | `0x50000` | 6 |
| 5090 ASUS 官方 payload ×2 | `0x9ce9d` | `0x50000` | 6 |
| PRO 6000 Dell NVFW | `0xa0783` | `0x53000`（bias 由 parser 解出；该文件未进入本扫描器的 bias 列表） | 6 |
| PRO 6000 HPE NVFW | `0xa0c3e` | `0x53000`（同上） | 6 |

对四份 RTX 5090 样本，本扫描器不依赖 BIT 索引就只找到这一张表；两份 PRO 6000 NVFW 的表
位置由 BIT token `'p'` 给出（`image_base=0x3b000`、`expansion=0x18000`、bias `0x53000`），
本扫描器的 bias 列表未覆盖该值，故其表格一行只是记录目标，不作为独立发现。
没有任一张表包含 `0x05/0x45/0x85`。

### 3.3 GB202 的 6 个 active entry（全部样本一致）

| idx | app | target | descriptor | v | size | flags | enc bit2 | tag(+0x2c..0x38) | immediate region |
|---:|---|---|---:|---:|---:|---:|---|---|---:|
| 5 | `0x07` | `0x06` | `0xa7da0` | 6 | `0x50` | `0x1d` | 1 | `00 00 00 05 00 00 00 11` | `0x20200` |
| 22 | `0x18` | `0x01` | `0x10e104` | 6 | `0x50` | `0x1f` | 1 | `00 00 00 04 00 00 00 02` | `0xcc00` |
| 23 | `0x19` | `0x01` | `0xc7ff0` | 6 | `0x50` | `0x05` | 1 | `00 00 00 04 00 00 00 12` | `0x21b00` |
| 24 | `0x15` | `0x01` | `0xe9c30` | 6 | `0x50` | `0x05` | 1 | `00 00 00 04 00 00 00 11` | `0x5b00` |
| 32 | `0x23` | `0x0e` | `0xef7bc` | 6 | `0x50` | `0x1f` | 1 | `00 00 4f 4f 42 48 55 42` = `"OOBHUB"` | `0x1e200` |
| 34 | `0x24` | `0x0f` | `0x11b304` | 6 | `0x50` | `0x0d` | 1 | `00 46 53 50 5f 52 55 4e` = `"FSP_RUN"` | `0x29400` |

（6 个 entry 的 encrypted 位全部为 1，见 §4.1。）

### 3.4 其它 GB202 材料

* `hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw`（`0x1d1dd0`）：与 Dell NVFW 同构，
  Falcon 表在 `0xa0c3e`（header 同为 `[1,6,6,35,1,48]`），active entry 同样是那 6 个，
  **FWSEC 0 个**；字符串扫描全 0（见 `results.json`）。
* `g153_0210_895__98028D0001.fwpkg`、`nvfw_RTXPRO6000BWSE_0003_251124.1.0_prod-signed.fwpkg`：
  `load_image()` 分别报 `bad PCI ROM signature 0xffff at 0x3b000`（容器，非 BIT/PCI-chain 镜像）。
  两份 fwpkg 的整文件字符串扫描（`OPT_`/`CTRL_OPT`/`FWSEC`/`ignore_for_floor`）命中 0。
* `dell_8d_payload/RTXPRO6000_98.02.8D.00.01_FW_upgrade.bin`：`file` 判为 x86-64 ELF
  （fwupd/updater 可执行文件，100 MB），其中的固件实体就是上面的 `.nvfw`；grep
  `OPT_|CTRL_OPT|FWSEC|ignore_for_floor` 只有 2 处文本命中（在 updater 程序字符串区，
  非 VBIOS 结构），未当作固件表。

### 3.5 AD102（RTX 4090）正对照：同一工具链在 Ada 上确实能得到 FWSEC

用 `compare_roms.py` 的 Ada parser（base `0x9400`，`expansion=0x14e00`）解析
`github_asus_strix_3c.rom`：

```text
falcon table @0xa20d8  v1 h=6 r=6 n=16 default_v=1 default_size=48
  idx 0  app=0x01 tgt=0x01 v1   stored=0x0000a12c
  idx 5  app=0x07 tgt=0x06 v1   stored=0x0000fd6c
  idx 6  app=0x08 tgt=0x01 v1   stored=0x00017f60
  idx 8  app=0x45 tgt=0x07 v3   size=0x32c stored=0x00010280  <- FWSEC_DBG
  idx 9  app=0x85 tgt=0x07 v3   size=0x32c stored=0x00010280  <- FWSEC_PROD
  idx10  app=0x49 tgt=0x05 v3   size=0x32c stored=0x00006428
  idx11  app=0x89 tgt=0x05 v3   size=0x32c stored=0x00006428
```

* Ada 的 FWSEC（0x45/0x85）用 **v3 descriptor**（`0x32c` = 44-byte 头 + 签名区，
  与 RM 的 `BCRT30_RSA3K_SIG_SIZE = 384` 一致）。
* 本地已抽出的 Ada FWSEC 镜像（`rtx4090_multisample_20260911/derived/asus24_app85_target07_{imem,dmem}.bin`
  等）内可见明文模块名 `NVRNG engine` / `NVPKA engine [RSA mode]` / `NIST_P-256` /
  `NIST_P-384`，说明它们是真实的安全固件；而 GB202 VBIOS 里**没有**对应的这种镜像
  （整文件搜 `NVRNG`/`NVPKA`/`NIST_P`/`FWSEC` 全部 0 命中）。
* 结论：GB202 消费者 VBIOS 的 falcon 表把 FWSEC 这条路完全去掉了，只剩 6 个 v6 对象。

### 3.6 公开源码侧的一致性

`/usr/src/nvidia-610.57.04/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c`
（= OpenRM 610.57.04，与本地驱动同版本）：

| 行 | 内容 |
|---:|---|
| 90 | `#define BIT_TOKEN_FALCON_DATA 0x70` |
| 122–127 | `FALCON_UCODE_TABLE_ENTRY_V1_SIZE_6 = 6`；`FALCON_UCODE_ENTRY_APPID_FIRMWARE_SEC_LIC 0x05` / `_FWSEC_DBG 0x45` / `_FWSEC_PROD 0x85` |
| 133–171 | `vDesc` 位域：bit0 = `VERSION_AVAILABLE`、bit2 = `ENCRYPTED`、bits15:8 = descriptor version、bits31:16 = size；只定义 V1..V4 常量 |
| 173–190 | v2（60 B）、v3（44 B，含 `PKCDataOffset`/`SignatureCount`）与 `BCRT30_RSA3K_SIG_SIZE 384` |
| 555、619–622、666 | 只接受 BIT token `'p'` v2；`// skip entries that are not FWSEC`（仅 0x05/0x45/0x85）；非 v2/v3 的 descriptor 直接 `unexpected ucode desc version 0x%x ... skipping` |

即：610.57.04 的 RM 在 VBIOS 里只会找 0x05/0x45/0x85 且只认 v2/v3，而 GB202 VBIOS 给的是
v6 → 按公开语义，**GB202 VBIOS 不承担 FWSEC 载荷**。这与 §3.1–3.3 的字节证据互为印证。

---

## 4. 实际存在的 6 个镜像：section / 表结构

### 4.0 Falcon ucode 表原始字节（FE 样本，`0x9ce9d..0x9cf75`，`0xd8` 字节）

表头 = `01 06 06 23 01 30`（version 1、header 6、entry 6、count 35、descVersion 1、descSize 48）。
35 个 entry 中只有 index 5 / 22 / 23 / 24 / 32 / 34 非空（其余 29 项全 0）。

```text
0009ce9d  01 06 06 23 01 30 00 00 00 00 00 00 00 00 00 00  |...#.0..........|
0009cead  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  |................|
0009cebd  00 00 00 00 07 06 a0 7d 05 00 00 00 00 00 00 00  |.......}........|
0009cecd  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  |................|
0009cedd  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  |................|
0009ceed  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  |................|
0009cefd  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  |................|
0009cf0d  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  |................|
0009cf1d  00 00 00 00 00 00 00 00 00 00 18 01 04 e1 0b 00  |................|
0009cf2d  19 01 f0 7f 07 00 15 01 30 9c 09 00 00 00 00 00  |........0.......|
0009cf3d  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  |................|
0009cf4d  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  |................|
0009cf5d  00 00 00 00 00 00 23 0e bc f7 09 00 00 00 00 00  |......#.........|
0009cf6d  00 00 24 0f 04 b3 0c 00 10 08 89 00 3c a5 00 00  |..$.........<...|
```

6 个非空 entry 的 raw 字节（entry 起点 / `app | target | u32 DescPtr`）：

```text
idx 5  0x9cec1  07 06 a0 7d 05 00   app=0x07 tgt=0x06 DescPtr=0x00057da0
idx22  0x9cf27  18 01 04 e1 0b 00   app=0x18 tgt=0x01 DescPtr=0x000be104
idx23  0x9cf2d  19 01 f0 7f 07 00   app=0x19 tgt=0x01 DescPtr=0x00077ff0
idx24  0x9cf33  15 01 30 9c 09 00   app=0x15 tgt=0x01 DescPtr=0x00099c30
idx32  0x9cf63  23 0e bc f7 09 00   app=0x23 tgt=0x0e DescPtr=0x0009f7bc
idx34  0x9cf6f  24 0f 04 b3 0c 00   app=0x24 tgt=0x0f DescPtr=0x000cb304
```

（`desc = bias 0x50000 + DescPtr`，例如 `0x50000+0xbe104 = 0x10e104`。）
`0x9cf75` 之后紧接的是 manifest A entry（`kind=0x89`）的覆盖区，即表尾没有任何空余包裹。

### 4.1 v6 descriptor 原始字段表（不引入私有字段名）

`desc` 起点 20 个 u32（FE 样本，file 绝对偏移）：

| 字段 | `app07/06` | `app18/01` | `app19/01` | `app15/01` | `app23/0e` | `app24/0f` |
|---|---:|---:|---:|---:|---:|---:|
| `+0x00` vDesc | `0x0050061d` | `0x0050061f` | `0x00500605` | `0x00500605` | `0x0050061f` | `0x0050060d` |
| `+0x04` word1 | `0x00020200` | `0x0000cc00` | `0x00021b00` | `0x00005b00` | `0x0001e200` | `0x00029400` |
| `+0x08` | 0 | 0 | `0x00009200` | `0x00009200` | 0 | `0x00018800` |
| `+0x0c` | `0x0001d600` | `0x00009200` | `0x0001c800` | `0x00005200` | `0x00014c00` | `0x00025400` |
| `+0x10` | 0 | 0 | `0x00003700` | `0x00003700` | 0 | `0x00001400` |
| `+0x14` | `0x00001100` | `0x00001100` | `0x00005300` | `0x00000900` | `0x00007c00` | `0x00004000` |
| `+0x18` | `0x00000200` | `0x00040101` | `0x000c0001` | `0x00030001` | `0x00030000` | `0x00000301` |
| `+0x1c` | 0 | `0x01010014` | `0x00000014` | `0x00000014` | `0x00000014` | `0x01030000` |
| `+0x20` | `0x00001100` | `0x00001f00` | 0 | 0 | `0x00001000` | 0 |
| `+0x24` | 0 | 0 | 0 | 0 | 0 | 0 |
| `+0x28` | `0x01012801` | `0x01012801` | `0x01012801` | `0x01012801` | `0x01012801` | `0x01012801` |
| `+0x2c` tag/字段 | `00 00 00 05` | `00 00 00 04` | `00 00 00 04` | `00 00 00 04` | `00 00 4f 4f`(`"OO"`) | `00 46 53 50`(`"FSP"`) |
| `+0x30` tag/字段 | `00 00 00 11` | `00 00 00 02` | `00 00 00 12` | `00 00 00 11` | `42 48 55 42`(`"BHUB"`) | `5f 52 55 4e`(`"_RUN"`) |
| `+0x34..+0x4f` | 28 B 高熵 | ← | ← | ← | ← | ← |

机械可核对的量（不命名语义）：`word1` 等于紧接着 descriptor 的高熵区字节数（6/6 成立）；
`vDesc` 低字节 flags 的 bit0=1（available）、bit2=1（ENCRYPTED，公开 RM 的唯一命名）。

`app07` descriptor 十六进制（`0xa7da0`，`0x50` B）：

```text
000a7da0  1d 06 50 00 00 02 02 00 00 00 00 00 00 d6 01 00  |..P.............|
000a7db0  00 00 00 00 00 11 00 00 00 02 00 00 00 00 00 00  |................|
000a7dc0  00 11 00 00 00 00 00 00 01 28 01 01 00 00 00 05  |.........(......|
000a7dd0  00 00 00 11 e0 d3 48 04 a5 80 f3 19 0e c7 80 02  |......H.........|
000a7de0  50 65 44 2b 97 e9 5c 9e 5e bc 5d cc 8e 9e 2e f2  |PeD+..\.^.].....|
```

`app24` descriptor 十六进制（`0x11b304`，可见 `"FSP_RUN"`）：

```text
0011b304  0d 06 50 00 00 94 02 00 00 88 01 00 00 54 02 00  |..P..........T..|
0011b314  00 14 00 00 00 40 00 00 01 03 00 00 00 00 03 01  |.....@..........|
0011b324  00 00 00 00 00 00 00 00 01 28 01 01 00 46 53 50  |.........(...FSP|
0011b334  5f 52 55 4e c9 67 dd ff c2 1a c0 cd fd 91 6a f9  |_RUN.g........j.|
0011b344  8a 8c 49 d2 98 16 db 2f 8f a3 bf 77 27 fb 98 9b  |..I..../...w'...|
```

### 4.2 每个镜像的 immediate region（word1 区）

| app/target | region 范围 | 大小 | 首 0x10 字节 | 熵 | 首部结构 |
|---|---|---:|---|---:|---|
| `0x07/0x06` | `[0xa7df0,0xc7ff0)` | `0x20200` | `db0df72f1ac91d5b…` | 7.999 | 无（密文） |
| `0x18/0x01` | `[0x10e154,0x11ad54)` | `0xcc00` | `0100440000000000…` | 7.996 | 4× 20-byte 记录表 |
| `0x19/0x01` | `[0xc8040,0xe9b40)` | `0x21b00` | `01003500a7470000…` | 7.999 | 6× 20-byte 记录表 |
| `0x15/0x01` | `[0xe9c80,0xef780)` | `0x5b00` | `01003500a7470000…` | 7.992 | 3× 20-byte 记录表 |
| `0x23/0x0e` | `[0xef80c,0x10da0c)` | `0x1e200` | `01001d00f4090400…` | 7.999 | 3× 20-byte 记录表 |
| `0x24/0x0f` | `[0x11b354,0x144754)` | `0x29400` | `f39770f87fcc32ae…` | 7.999 | 无（密文） |

**容器/表结构（20-byte 记录）**：4 个 region 以固定 0x14 步长的记录表开头，记录形状为
`u16 t | u16 id | u32 A | u32 B | u32 C | u32 D`。原始字节（FE）：

```text
app18: +0x00 0100440000000000f01d0000000000004c020000
       +0x14 02000100001b0000c00100000000000000000000
       +0x28 01008500000000000021000000000000e0000000
       +0x3c 0100e30000000000002200000000000020000000
app19: +0x00 01003500a7470000b07e0100bd04000000110000
       +0x14 0100890075cf0400008a000044a5000044a50000
       +0x28 0100120068e80300b08f0100280500002c050000
       +0x3c 0100140077630200e0940100f11c0000f51c0000
       +0x50 02000200405a0100702400000000000000000000
       +0x64 02000300d0590100700000000000000000000000
app15: +0x00 01003500a7470000c0570000bd04000000110000
       +0x14 01008a00b9740500004000009007000090070000
       +0x28 0100d2006d930100c06800000f0c0000130c0000
app23: +0x00 01001d00f4090400409c00007100000075000000
       +0x14 01001e00650a0400b89c00003502000039020000
       +0x28 01008000b20c0400009c0000380000003c000000
```

只声明**逐条精确成立**的关系（脚本判定，仅统计连续结构化记录）：

* `app19`、`app15`、`app23`：`D = C + 4` 对全部结构化记录成立；
* `app23`：另外 `A(next) = A(curr) + C(curr)`（前 3 条连续成立）；
* `app18`：`A(next) = A(curr) + C(curr)` 成立（前 4 条），`D = C + 4` 不成立；
* `app07`、`app24`：记录表不成立（第 0 字节即高熵），结构化记录数 0。

其余对 `t/id/A/B/C/D` 的解释（类型、目标地址空间、压缩/加密长度等）**没有**公开定义，
本文不命名。region 体积远小于 word1 之外的信息（例如 `0x1e200` 内包含约 `0x1e250`
字节的 manifest 覆盖区间），且整段近满熵，与 “encrypted bit = 1” 一致。

### 4.3 两个 nested image（Falcon 表 idx22 / idx34 指向的对象）

`app18/01` 与 `app24/0f` 的 descriptor 位于一个 512-byte 对齐的 nested PCI image 内，
每个 image 带一张 **两-entry SHA-384 hash table**（形状 `u32 3 | u32 0x10 | u32 2 | u32 0x2b80`
+ `2 × 0x3c` entry），header 之后的第一个 entry 覆盖 `ff ff + 0x20-byte PCIR`，第二个 entry
覆盖 descriptor + entire immediate region：

```text
app24 表 @0x11b25a..0x11b2e2:
0011b25a  03 00 00 00 10 00 00 00 02 00 00 00 80 2b 00 00
0011b26a  c0 00 00 00 00 00 00 00 22 00 00 00 <48B SHA-384(0x11b2e2..0x11b304)>
0011b2aa  9f 00 00 00 22 00 00 00 50 94 02 00 <48B SHA-384(0x11b304..0x144754)>

app18 表 @0x10e05a..0x10e0e2:
0010e05a  03 00 00 00 10 00 00 00 02 00 00 00 80 2b 00 00
0010e06a  d7 00 00 00 00 00 00 00 22 00 00 00 <48B SHA-384(0x10e0e2..0x10e104)>
0010e0aa  86 00 00 00 22 00 00 00 a0 cc 00 00 <48B SHA-384(0x10e104..0x11ada4)>
```

`0x2b80` 是 device word（`0x2b85`=5090 的同族），`u32 3/0x10/2` 为表版本/头长/entry 数。
这正是既有文档 `parallel/bcrt_manifest_coverage.md` 描述的第二级结构，本文独立复算一致。

---

## 5. CTRL_OPT / `OPT_*` floorsweep 选项表：负结果

### 5.1 搜索词与结果（RTX 5090 FE，其它 GB202 样本相同）

| 搜索串 | 全文件命中 | 6 个 envelope region 内命中 |
|---|---:|---:|
| `CTRL_OPT` | 0 | 0 |
| `OPT_L2SLICE` | 0 | 0 |
| `OPT_TPC` | 0 | 0 |
| `OPT_FBP` | 0 | 0 |
| `OPT_GPC` | 0 | 0 |
| `ignore_for_floor` | 0 | 0 |
| `floorsweep` / `FLOORSWEEP` / `floor_sweep` | 0 | 0 |
| `OPT_`（任意前缀匹配） | 0 | 0 |
| `FWSEC` / `fwsec` | 0 | 0 |

`marker_hits_whole_file_counts` 在全部 6 个 GB202 可解析样本中都是全 0（`{}`），
详见 `parallel/gb202_fwsec_opt_static.results.txt`。

### 5.2 与 170HX/GA100 社区断言的关系

* 参照对象是 “GA100 的 `CTRL_OPT` 表位于 FwSec 尾部、名字形如
  `OPT_L2SLICE_FBPn_DISABLE` / `OPT_TPC_GPCn_DIS` / `OPT_FBP_L` / `ignore_for_floor`，
  且可能未被签名”。
* 本文的 GB202 证据是：**没有 FwSec 镜像可供承载该表**（§3），并且在所有可见字节里
  这些字符串命中 0（§5.1）。
* 本地没有 GA100/CMP 170HX 的 VBIOS 或相关材料（全盘 `*fwsec*` 只命中驱动源码
  `kernel_gsp_fwsec.c`；`170HX`/`CMP 170` 检索为空），因此该社区断言在本轮**未能独立验证**，
  只能作为外部声明引用 —— 不能宣称它错，也不能把它当作 GB202 的已知事实。
* 现有项目内的同名材料属于**寄存器/标签名**，不是 VBIOS 内的表：
  * `gb202_vbios_diff.py` 顶部 `KNOWN_REGISTERS` 含 `OPT_L2_FBP0_DISABLE = 0x008234E0`
    等地址；
  * `L2_REENABLE_STATIC_FINDINGS.md` / `gb202_fuse_descriptor_inventory.md` 记录的
    `OPT_L2SLICE_FBPn_DISABLE` 出现在 **MODS ELF** 里（GSP 侧二进制），不是 VBIOS。

### 5.3 Ada FWSEC 内也没有 OPT 表

对本地已抽出的真正 FWSEC 镜像做同样扫描：

| 文件（4090 / AD102） | 大小 | `OPT_|CTRL_OPT|ignore_for_floor|floorsweep` 命中 |
|---|---:|---:|
| `asus24_app85_target07_imem.bin` | 61952 | 0 |
| `asus24_app85_target07_dmem.bin` | 3456 | 0 |
| `asus24_app45_target07_imem.bin` | 61952 | 0 |
| `asus24_app45_target07_dmem.bin` | 3456 | 0 |

即：即使拿“真实 FWSEC 镜像”做对照，也没有出现 170HX 描述的 OPT 字符串表；
`OPT_*` floorsweep 名字在本地证据里只与 MODS/寄存器空间相关。

---

## 6. 签名 / 哈希覆盖判定

### 6.1 两级 SHA-384 机制的机械定义

本文只使用两种可复算关系（全部在大文件偏移上）：

* **一级 hash record**：`covered_start = record + 0x38 + u32(raw0)`；
  `u32(record+8..+0x38) == SHA-384(file[covered_start : covered_start+u32(len)])`。
  FE 文件共 7 条（与既有 `parallel/falcon_manifest_table.md`、`parallel/bcrt_manifest_coverage.md`
  的记录一致，本文独立复算）。
* **覆盖清单（manifest）entry**：0x3c 字节 `u32 kind | u32 offset | u32 length | 48B SHA-384`，
  entry 之间 `offset` 连续（`offset(next) = offset(curr) + length(curr)`），
  `file_offset = offset + delta`（delta 由“该 entry 的摘要 = 该区间 SHA-384”自动解出，
  不靠猜）。FE 有两条 manifest。

### 6.2 FE 的 7 条一级 hash record

| record | raw0 | length | covered range | 覆盖对象 |
|---:|---:|---:|---|---|
| `0x372aa` | `0x22` | `0x344` | `[0x37304,0x37648)` | nested PCI image 片段 |
| `0x37d22` | `0xd6` | `0x38` | `[0x37e30,0x37e68)` | 片段 |
| `0x38c66` | `0xe206` | `0xaac` | `[0x46ea4,0x47950)` | 片段 |
| `0x47ee6` | `0x32` | `0x17982` | `[0x47f50,0x5f8d2)` | 片段 |
| `0x61746` | `0xac2ca` | `1` | `[0x10da48,0x10da49)` | 单字节 `ff` |
| `0x10e0aa` | `0x22` | `0xcca0` | `[0x10e104,0x11ada4)` | **app 0x18 envelope** |
| `0x11b2aa` | `0x22` | `0x29450` | `[0x11b304,0x144754)` | **app 0x24 envelope** |

### 6.3 Falcon ucode 表本身受 manifest A 覆盖（关键证据）

manifest A：anchor entry `0x61472`，delta `0x6177e`，**95 条 entry 全部摘要复算一致**，
覆盖区间连续 `[0x6f400, 0x10da49)`（即 EFI 段 0x100 前缀起，到 nested image 之前的整个
固件区）。其中：

```text
00061472  2b 00 00 00 1f b7 03 00 d8 00 00 00 71 f5 0b 4e  |+...........q..N|
00061482  1b 29 3c 7e 1c 44 3f 12 96 0c 6d d9 0c 30 99 fc  |.)<~.D?...m..0..|
00061492  44 2c 69 39 3f 13 8b 05 99 a9 93 a0 e0 be e5 05  |D,i9?...........|
000614a2  18 cf d3 cf 30 b2 14 97 b7 2a bf 09 89 00 00 00  |....0....*......|
```

* entry 字段：`kind=0x2b`、`offset=0x3b71f`、`length=0xd8`；
* 映射：`file = 0x3b71f + 0x6177e = 0x9ce9d`；`0x9ce9d + 0xd8 = 0x9cf75`；
* `0xd8 = 6 + 6*35` 正好等于 Falcon ucode 表的完整长度；
* 摘要 `71f50b4e1b293c7e1c443f12960c6dd90c3099fc442c69393f138b0599a993a0e0bee50518cfd3cf30b21497b72abf09`
  与 `SHA-384(file[0x9ce9d:0x9cf75])` 逐字节相等（脚本复算，`digest_matches=True`）。

**结论（FACT）**：GB202 的 Falcon ucode 表（含 35 个 entry、6 个 descriptor 指针）
落在 SHA-384 覆盖范围内；而且紧邻它的两侧也在链内 —— 前一条 entry（`kind=0xe3`）覆盖
`[0x9ce7f,0x9ce9d)`，后一条 entry（`kind=0x89`, len `0xa544`）覆盖 `[0x9cf75,0xa74b9)`。
因此“在表尾追加/修改 OPT 表字节”不可能落在 manifest A 链的缝隙里：该链在
`[0x6f400,0x10da49)` 上按 `offset(next)=offset(prev)+len(prev)` 无缝连续（95 条全部摘要复算
一致）。本文不对 `[0x6f400,0x10da49)` 之外的区域作未被覆盖的推断。

BIT 表同理：manifest B anchor entry `0x3851e`（`kind=0x2d`、`offset=0x152`、`length=0x84`，
delta `0x38c9e`）覆盖 `[0x38df0,0x38e74)`，摘要一致；B 清单连续走 10 条、
覆盖 `[0x38c9e,0x3cc34)`，全部复算一致。

两份 RTX PRO 6000 GB202 NVFW 同样的机制（anchor 由脚本自动解出，非硬编码）：

| 样本 | manifest A anchor / delta | 连续 verified entries | 覆盖跨度 | Falcon 表覆盖者 |
|---|---|---:|---|---|
| Dell `98.02.8D` | `0x643fa` / `0x64706` | 94 | `[0x72400,0x11ab9d)` | entry `0x643fa` (`kind=0x2b`) |
| HPE `98.02.9E` | `0x643fa` / `0x64706` | 34 | `[0x963d1,0x11f7ed)` | entry `0x643fa` (`kind=0x2b`) |

两份 NVFW 的 manifest B 与其 BIT 表 anchor 均为 `0x3b51e` / delta `0x3bc9e`（10 条、
`[0x3bc9e,0x3fc30)`）。注意：这里的“连续 verified entries 数”是**保守下界** —— 步进在
第一次“摘要不复算或不连续”时停止，NVFW 布局中途可能有重叠 entry（同一 `offset` 出现两次）。
无论取哪一份，Falcon ucode 表与 6 个 descriptor+region 均落在已复算的覆盖区间内。

### 6.4 6 个镜像的 descriptor + 数据区覆盖表（FE 样本）

| app/target | descriptor | 覆盖者（区间 / 长度） | region | 覆盖者 |
|---|---|---|---|---|
| `0x07/0x06` | `[0xa7da0,0xa7df0)` | manifest A entry `0x61652`（`kind=0x36`，`[0xa7da0,0xc7ff0)`，len `0x20250` = `0x50+0x20200`） | `[0xa7df0,0xc7ff0)` | 同上 |
| `0x18/0x01` | `[0x10e104,0x10e154)` | hash record `0x10e0aa`（`[0x10e104,0x11ada4)`，len `0xcca0`） | `[0x10e154,0x11ad54)` | 同上 |
| `0x19/0x01` | `[0xc7ff0,0xc8040)` | manifest A entry `0x6168e`（`kind=0x87`，`[0xc7ff0,0xe9c30)`，len `0x21c40` = `0x50+0x21b00+0xf0`） | `[0xc8040,0xe9b40)` | 同上 |
| `0x15/0x01` | `[0xe9c30,0xe9c80)` | manifest A entry `0x616ca`（`kind=0x88`，`[0xe9c30,0xef7bc)`，len `0x5b8c` = `0x50+0x5b00+0x3c`） | `[0xe9c80,0xef780)` | 同上 |
| `0x23/0x0e` | `[0xef7bc,0xef80c)` | manifest A entry `0x61706`（`kind=0x9e`，`[0xef7bc,0x10da48)`，len `0x1e28c` = `0x50+0x1e200+0x3c`） | `[0xef80c,0x10da0c)` | 同上 |
| `0x24/0x0f` | `[0x11b304,0x11b354)` | hash record `0x11b2aa`（`[0x11b304,0x144754)`，len `0x29450`） | `[0x11b354,0x144754)` | 同上 |

**0 个镜像处于无覆盖状态。** manifest A 的 4 条相关 entry 都以对应 descriptor 为覆盖起点、
都以 `0x50 (descriptor) + word1 (immediate region)` 为主干；其中 `app 0x07` 的长度正好等于
主干（`0x20250`），另三者在主干之外还包含 `0x3c`/`0xf0` 字节余量，使覆盖终点正好落在
**下一个 descriptor 起点**（`0xc7ff0` / `0xe9c30` / `0xef7bc` / `0x10da48`）——即 manifest 是一条
无缝的连续覆盖链，descriptor 与密文区被当作一个整体做 SHA-384，中间的 `ff ff + PCIR`
前缀与前一条余量也都在链内。两个 nested image 则由其内部两-entry hash table + 一级
hash record 覆盖（`ff ff + 0x20-byte PCIR` 前缀单独一条覆盖）。

### 6.5 覆盖链的上一层与未闭合处

* 两个 nested image 的 hash table 自身又被 48-byte digest 覆盖：
  `file[0x11b009..0x11b039)` = `SHA-384(file[0x11b25a..0x11b2e2))`（app 0x24），
  `file[0x10de09..0x10de39)` = `SHA-384(file[0x10e05a..0x10e0e2))`（app 0x18），均已复算；
* **manifest 表自身没有在本文件内找到上一层摘要**：把 manifest A `[0x6013a,0x6177e)`、
  manifest B `[0x3846a,0x386c2)` 等候选区间的 SHA-256/SHA-384 在文件内检索，均无存储副本；
* 文件开头 `[0,0x38000)` 是一段近满熵的前置容器区（既有的 `NVGI` 魔数不在此样本中），
  其中未找到任何一级 record 或 6 个镜像/表的摘要；该区的语义与是否携带
  RSA/EC 签名 → **UNKNOWN**（本文范围外，且不做任何解密尝试）；
* 因此能给出的最严格链条是：
  `descriptor + 密文区 ← manifest / hash-record（FACT）→ manifest 与前置容器区 ← UNKNOWN`。
  本文**不**声称 “OPT 表未被签名” 或 “可安全修改”，只给出可复算的覆盖区间。

---

## 7. FACT / INFERENCE / UNKNOWN

### FACT

1. RTX 5090（4 份样本）与 RTX PRO 6000 GB202（Dell `98.02.8D` + HPE `98.02.9E` NVFW，共 6 份
   GB202 镜像）中，Falcon ucode 表的 active entry 恒为 `0x07/0x06, 0x18/0x01, 0x19/0x01,
   0x15/0x01, 0x23/0x0e, 0x24/0x0f`，**不含** `0x05/0x45/0x85`；表头均为 `[1,6,6,35,1,48]`。
2. 指定工具 `extract_falcon_ucode.py` 在上述样本上对 0x05/0x45/0x85 全部报
   `expected exactly one app 0x.. entry, found 0`；对存在条目 0x07 报
   `extractor supports V2 descriptors only; got version=6, size=80`，证明定位正确。
3. 所有 6 个 entry 使用 v6 descriptor（size `0x50`、`ENCRYPTED` 位置 1）。
4. 全文件（含 6 个 envelope）中 `CTRL_OPT`、`OPT_*`、`ignore_for_floor`、`floorsweep`、
   `FWSEC` 等字符串命中数均为 0；Ada 真 FWSEC 镜像内同样为 0。
5. Falcon ucode 表由 manifest A entry（`kind=0x2b`, len `0xd8`）的 SHA-384 精确覆盖
   （5090 样本 entry `0x61472` 覆盖 `[0x9ce9d,0x9cf75)`；NVFW 样本 entry `0x643fa`）；
   BIT 表由 manifest B entry（`kind=0x2d`, len `0x84`）精确覆盖（entry `0x3851e` / `0x3b51e`）；
   6 个 descriptor+region 全部被 manifest 或 hash record 覆盖（6 份样本均如此）。
6. 两个 nested image 各自的 2-entry SHA-384 hash table 被更高一层 48-byte digest 覆盖。
7. OpenRM 610.57.04 的 `kernel_gsp_fwsec.c` 只认 0x05/0x45/0x85 与 v2/v3。
8. AD102（RTX 4090）VBIOS 里确实存在 0x45/0x85（v3, size `0x32c`）。

### INFERENCE

1. GB202 消费者 VBIOS 的 Falcon 表已经不再承载 FWSEC；这 6 个 v6 对象是 Blackwell
   新的固件封装（含可打印标签 `OOBHUB`、`FSP_RUN`），其 consumer 与语义由私有格式决定。
2. 若 GA100 的 `CTRL_OPT` 表真的位于 FwSec 尾部，那么在 GB202 上它不会出现在 VBIOS
   的这张表/这 6 个对象里 —— 该载体必然是其它固件（GSP/MODS/SEC2 或驱动侧固件文件）。
3. manifest（0x3c entry + 连续 offset）与 nvflash/BCRT 里既有的 “hash/VDPA/security-zone”
   词汇相容，但本文没有把某个 nvflash virtual method 绑定到这两个 manifest。

### UNKNOWN

1. v6 descriptor 除 `vDesc` 外所有字段的正式语义（含 `+0x2c` 处 tag 的含义）。
2. 6 个 immediate region 的解密/解压算法、密钥、长度关系（region 全部近满熵）。
3. manifest A/B 自身的上一层认证（是否被前置容器的 RSA/EC 签名覆盖）—— 本文件内不存在
   可复算的上一层摘要。
4. 文件开头 `[0,0x38000)` 区的格式与用途。
5. Blackwell 上 FWSEC/安全固件的真实来源（`/lib/firmware/nvidia/gb202/gsp/{bootloader,fmc}-570.144.bin.zst`
   存在，但本轮未解析；本文不主张其内容）。
6. GA100/170HX `CTRL_OPT` 社区断言在本地无法验证。

---

## 8. 复现

```bash
cd /home/user/rt_5090_project

# (a) 指定工具的三个 FWSEC app id（全部为负）
for app in 0x05 0x45 0x85; do
  python3 /home/user/hulk_public_research_20260811/tools/extract_falcon_ucode.py \
    vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom \
    --skip 0x38000 --table-offset 0x64e9d --pointer-bias 0x18000 \
    --app-id $app --output-dir /tmp/fwsec_5090_test
done

# (b) 全样本结构 / 字符串 / 覆盖枚举（含 descriptor、region、manifest）
python3 parallel/gb202_fwsec_opt_static.py \
  --extract-dir vbios_diff/gb202_fwsec_opt_20260925 \
  --json       vbios_diff/gb202_fwsec_opt_20260925/results.json

# (c) 原始摘要清单（本章表格的机器可读版本）
cat parallel/gb202_fwsec_opt_static.results.txt
```

产物：

| 路径 | 内容 |
|---|---|
| `parallel/FWSEC_OPT_TABLE_GB202_20260925.md` | 本报告 |
| `parallel/gb202_fwsec_opt_static.py` | 审计脚本（sha256 `d3d83a71…aaf3398`） |
| `parallel/gb202_fwsec_opt_static.results.txt` | 逐样本原始结果（含 manifest 全条 entry） |
| `vbios_diff/gb202_fwsec_opt_20260925/results.json` | 机器可读全量 JSON |
| `vbios_diff/gb202_fwsec_opt_20260925/*_descriptor.bin` | 6 个 v6 descriptor 原始字节 |
| `vbios_diff/gb202_fwsec_opt_20260925/*_region.bin` | 6 个 immediate region 原始字节 |

## 9. 本轮没有做的事

没有写卡/刷写/擦除任何 VBIOS 或 flash，没有执行 nvflash/updater/MODS/固件，没有访问
GPU 设备节点、PCI BAR/MMIO、sysfs resource、debugfs、`/dev/mem`，没有 reset/rebind，
没有联网，也没有尝试解密或绕过任何签名/认证；对密钥、出口管制与安全令牌类内容不做任何
推导或利用。所有输出均为本地文件字节的只读陈述。

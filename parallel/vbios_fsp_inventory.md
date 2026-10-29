# `vbios_diff/` GB202 样本与 Falcon v6 `app=0x24/target=0x0f` 清点

## 1. 范围与安全边界

本次只读取 `/home/user/rt_5090_project/vbios_diff/` 下的本地文件，并复用项目根
目录的离线解析器 `gb202_vbios_diff.py`。没有递归扫描项目外目录，没有下载，
没有执行 updater、固件或 MODS，没有访问 GPU、设备节点、PCI/BAR/MMIO、
debugfs，也没有 reset、rebind 或提权。主报告未修改。

解析器当前 SHA-256 为
`90cefd37e109684119e98c5ab64ef382048710dcdc344e1cd4bb5d70abb517eb`。
本次既运行了其普通只读 CLI，也从同一模块复用了 `load_image()`、
`parse_pci_chain()`、`parse_falcon_table()` 和
`parse_falcon_descriptor_header()` 来计算目标 descriptor 与切片 hash。

证据命名保持保守：

- Falcon v6 descriptor 的 raw `word0` 可按现有 vDesc 首字布局拆成 flags、version
  和 descriptor size；其余 private words 没有公开字段定义。
- 下文的 `word1` 只是 descriptor `+0x04` 处 raw little-endian `u32`。
- `[descriptor+0x50, descriptor+0x50+word1)` 仅称为
  **word1-sized immediate region**。把 `word1` 解释为该区域长度有一致性旁证，
  但仍是推断，不是公开 v6 字段语义。
- `flags.bit2=1` 可报告 descriptor 的 `encrypted` flag；它不单独证明上述 region
  就是 ciphertext。高 entropy 也不能区分加密、压缩或其他高熵编码。

## 2. 目录完整清单

`rg --files vbios_diff` 共得到 14 个文件。所有 14 个 standalone 路径的整文件
SHA-256 都不同；“重复”来自 archive member、嵌套 raw image 或派生 option-ROM
chain，而不是两个独立路径恰好拥有同一个整文件 hash。

| 本地路径 | bytes | 整文件 SHA-256 | 分类与候选判定 |
|---|---:|---|---|
| `vbios_diff/Dell_RTXPRO6000_98.02.8D.00.01_FW_upgrade.tar.gz` | 17,712,126 | `023ef3028e6360946794d7a48e85233021c708a38cc228a7a0e39ab876bb9445` | Dell updater archive；不是 raw image |
| `vbios_diff/NVIDIA_RTX_PRO_6000_Blackwell_96GB_PCIe_GPU_VBIOS-98.02.9E.00.01-1-0.x86_64.rpm` | 8,471,656 | `183c76f5ea0d5e72796fe1cf2f1ce5d8c31796e3f6d7876c19121a4e41784fe8` | HPE/NVIDIA RPM wrapper；不是 raw image |
| `vbios_diff/dell_8d_payload/RTXPRO6000_98.02.8D.00.01_FW_upgrade.bin` | 100,223,360 | `6e1ccf97addee26c3c836cc4c87b4fdd0151cf78edb4df921b35338479e6ab61` | x86-64 ELF updater，虽扩展名为 `.bin`，但不是 ROM/NVFW |
| `vbios_diff/dell_8d_payload/RTXPRO6000_98.02.8D.00.01_FW_upgrade.exe` | 108,022,272 | `0714175cbdda0a308d4a8944de128e0288760956434da6a9b24b65523f33299e` | PE32+ updater；不是 raw image |
| `vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw` | 1,908,176 | `8658724061087279f59ca3a0d8ce443cb4ca52db2543c64723a3cea632a29b59` | **可直接解析的 GB202 NVFW；独立 raw 变体** |
| `vbios_diff/dell_8d_payload/g153_0210_895__98028D0001.fwpkg` | 1,908,383 | `27a99791cb2da93aa75fbe815493d2cc7a0c7c884d4181c66a3588351f403f91` | firmware-package wrapper；内含上一行完整 NVFW，不是新 raw 变体 |
| `vbios_diff/derived/RTX5090_FE_optionrom_chain.bin` | 1,732,607 | `3b4ffb74d0f311c93d07747155d043a391c45888d636e387a747fbe56cc881b7` | **可解析 derived chain**；是 FE ROM 的精确后缀，不是新变体 |
| `vbios_diff/derived/RTXPRO6000_Server_optionrom_chain.bin` | 1,666,512 | `34de3d29d95c91d04c738e0d418bf2a960e7a1ecdc0a48dcfc7b37d1476f12d3` | **可解析 derived chain**；是 HPE 9E NVFW 的精确后缀，不是新变体 |
| `vbios_diff/hpe_rpm_extracted/usr/local/bin/NVIDIA_RTX_PRO_6000_Blackwell_96GB_PCIe_GPU_VBIOS-98.02.9E.00.01/NVIDIA_RTX_PRO_6000_Blackwell_96GB_PCIe_GPU_VBIOS-98.02.9E.00.01.scexe` | 8,481,142 | `4c1e99989a81099e6b352c54b39bd313d88ee1fcc7207524d61f250869b3ab94` | shell/self-extract wrapper；不是 raw image |
| `vbios_diff/hpe_scexe_payload/NVIDIA_Firmware_License.txt` | 14,701 | `ec9a824ba0fdcd982a025bb3458c5fe106ac13952b182640256ca1de9395acef` | license 文本；非候选 |
| `vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw` | 1,908,176 | `98c52f80e937907c4203280824bbef6bb17439c900edc74532072780611c0fe5` | **可直接解析的 GB202 NVFW；独立 raw 变体** |
| `vbios_diff/hpe_scexe_payload/nvfw_RTXPRO6000BWSE_0003_251124.1.0_prod-signed.fwpkg` | 2,204,365 | `620b673fcbee27d90693610477344332e5f3d47ba538903f9ebcd09db52abe27` | firmware-package wrapper；内含上一行完整 NVFW，不是新 raw 变体 |
| `vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom` | 1,961,983 | `a966aca23518708e44c961af865cccfdfabebc9d0cd06a8e29577a0bd82dc5eb` | **可直接解析的 RTX 5090 FE ROM；独立 raw 变体，provenance 未验证** |
| `vbios_diff/unverified_TPU_280522_ASUS_Astral_1043-89E3_98.02.2E.40.85.rom` | 1,961,983 | `eeb68ef4ce8b70d2f72aa1738b04e89d912c3af977722959e7ca60c1195f1111` | **可直接解析的 ASUS RTX 5090 ROM；独立 raw 变体，provenance 未验证** |

前两份 GeForce 文件名明确带 `unverified_TPU`，不能当作本机实卡 dump。Dell/HPE
文件来自本地升级包的保存/提取物，也不是设备回读。

## 3. 容器、raw image 与 derived chain 去重

### 3.1 Dell 8D 链

- 顶层 tar 只含保存的 ELF `.bin` 与 PE `.exe`；逐 member 流式 hash 分别与目录中
  两个 updater 完全相同。
- ELF updater 在 file offset `0x00f8d794` 包含完整 Dell `.fwpkg`，其内部
  file offset `0x00f8d863` 开始又包含完整 `.nvfw`。
- PE updater对应 offsets 为 `.fwpkg` `0x0164f634`、`.nvfw` `0x0164f703`。
- Dell `.fwpkg` 本身是 `0xcf` bytes 前缀加完整 1,908,176-byte Dell NVFW；
  NVFW 从 package offset `0xcf` 开始直到 EOF。

因此 tar、两个 updater 与 `.fwpkg` 都没有增加新的 Falcon payload 版本；Dell
8D 的 canonical raw image 只有 `RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw`。

### 3.2 HPE 9E 链

- RPM 中唯一文件 payload 是保存的 `.scexe`；流式 member hash 与目录内 `.scexe`
  完全相同。
- 只读检查 `.scexe` 头部可见 `_SKIP=414`；从第 414 行开始的 gzip/tar 成员包括
  `hpsetup_generic`、`nvflash`、HPE `.fwpkg` 和 license。流式 member hash 证明
  保存的 `.fwpkg` 与 license 均与这些成员完全相同；没有运行 `.scexe`。
- HPE `.fwpkg` 在 offset `0x14d` 包含完整 1,908,176-byte HPE NVFW；NVFW 后的
  `0x483b0` bytes 现已进一步拆成 PLDM component 1 `[0x1d1f1d,0x219ecd)`
  （`0x47fb0` bytes）与 extra footer `[0x219ecd,0x21a2cd)`（`0x400` bytes）。
  后者含可离线验证的 P-384/SHA-384 外层签名，边界与信任限制见
  `parallel/fwpkg_container_auth.md`。

因此 RPM、`.scexe` 与 `.fwpkg` 也没有增加新的 raw image 版本；HPE 9E 的
canonical raw image 只有 `RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw`。

### 3.3 derived chain

- `RTX5090_FE_optionrom_chain.bin` 逐字节等于 FE ROM 的
  `[0x38000, EOF)`，即其合法 BIT image base 被移到文件 offset 0。FE ROM
  该后缀的 SHA-256 正是 derived 文件 hash
  `3b4ffb74d0f311c93d07747155d043a391c45888d636e387a747fbe56cc881b7`。
- `RTXPRO6000_Server_optionrom_chain.bin` 逐字节等于 HPE 9E NVFW 的
  `[0x3b000, EOF)`；对应后缀 SHA-256 为
  `34de3d29d95c91d04c738e0d418bf2a960e7a1ecdc0a48dcfc7b37d1476f12d3`。
- ASUS ROM 的 `[0x38000, EOF)` hash 为
  `568566041dc2633c53318ac1b095846b5d10a3d9892d80474d8cdd21724de3a8`，
  与 FE derived chain 不同；Dell NVFW 的 `[0x3b000, EOF)` hash 为
  `ef62dafeb37e48b0ed93cb86ecdae8df1f5b9e6e2021c5d0d4e1d576f98bc9bb`，
  与 HPE derived chain 不同。

去重结果是：目录中有 6 个可由解析器直接读取的 ROM/NVFW/derived 文件，但派生
关系消除两份 chain 后，只有 **4 个独立完整 raw image 变体**：FE 2E.00.03、
ASUS 2E.40.85、Dell Pro 8D.00.01 和 HPE Pro 9E.00.01。

## 4. Falcon v6 `app=0x24/target=0x0f` 复核

四个 canonical raw image 都有且仅有一个目标条目，Falcon table index 都为 34。
raw `word0` 都是 `0x0050060d`，即 flags `0x0d`、version 6、descriptor size
`0x50`；`flags.bit2` 为 1。打印字节观察的稳定核心为 `FSP_RUN`，但这不是已定义
字段名，也不证明 task、入口或执行语义。

| canonical sample | image base | desc rel / abs | raw `word1` | 0x50-byte descriptor SHA-256 | hash-confirmed region `[start,end)` | region SHA-256 |
|---|---:|---:|---:|---|---|---|
| RTX 5090 FE 98.02.2E.00.03 | `0x38000` | `0xcb304` / `0x11b304` | `0x29400` | `ccc6647fda7d26f4de03f65d46cc683b52c5cb0dac1d3ed75b2e1a08885870fc` | `[0x11b354,0x144754)` | `1a546c20674f1ccb50c5451f305ed3e2e64a2396ae8bf8418ac61ce944597214` |
| ASUS RTX 5090 98.02.2E.40.85 | `0x38000` | `0xcb304` / `0x11b304` | `0x29400` | `ccc6647fda7d26f4de03f65d46cc683b52c5cb0dac1d3ed75b2e1a08885870fc` | `[0x11b354,0x144754)` | `1a546c20674f1ccb50c5451f305ed3e2e64a2396ae8bf8418ac61ce944597214` |
| Dell RTX PRO 6000 98.02.8D.00.01 | `0x3b000` | `0xd5104` / `0x128104` | `0x36c00` | `cd2e6b2d6be17311be889c5e5c8b4b379166c9e1c4f8d58c894f70aa48b2219e` | `[0x128154,0x15ed54)` | `3ba673453b10609d54887abba30fff8f0571435dbd73bed68bac99808e590c09` |
| HPE RTX PRO 6000 98.02.9E.00.01 | `0x3b000` | `0xd9d04` / `0x12cd04` | `0x37000` | `817c1fbe53c379d6369cefc41dca181b759df607d3a44015f9d666563fd77aee` | `[0x12cd54,0x163d54)` | `125328597c20b8c09ae40489ddab56c2b05d203501d865f2c6f154bfd999e9d9` |

derived 文件没有引入新 hash：

| derived alias | descriptor abs | region | descriptor / region 归组 |
|---|---:|---|---|
| FE option-ROM chain | `0xe3304` | `[0xe3354,0x10c754)` | 与 FE 和 ASUS 两项 hash 完全相同 |
| Pro Server option-ROM chain | `0xf1d04` | `[0xf1d54,0x128d54)` | 与 HPE 9E 两项 hash 完全相同 |

`.fwpkg` 的直接 parser rejection 也不表示内部没有 image：两份 wrapper 都确切
嵌入了上述 canonical NVFW，只因 package 前缀改变 4 KiB-relative image base，
把 package 自身当 raw ROM 解析会在 `0x3b000` 看到 `0xffff` 而拒绝。对嵌入 NVFW
去重后，它们分别继承 Dell/HPE 的 descriptor 与 region hash。

### 三个目标对象字节组

1. **GeForce common group**：FE、ASUS 与 FE derived chain；descriptor 和 region
   都逐字节相同。
2. **Dell Pro 8D group**：Dell NVFW，以及 Dell `.fwpkg`/两个 updater 中嵌入的
   同一 raw image。
3. **HPE Pro 9E group**：HPE NVFW、Pro derived chain，以及 HPE `.fwpkg` 中嵌入
   的同一 raw image。

所以 4 个独立完整 raw image 最终只提供 **3 个独立 target descriptor/region
字节对象**。

## 5. SKU 与 firmware revision 能否区分

### 直接可证的字节事实

- 两份完整 GeForce ROM 的整文件 hash 不同，文件名版本也不同
  (`98.02.2E.00.03` 与 `98.02.2E.40.85`)，但目标 descriptor、raw `word1`、
  region 长度和 region bytes 全部相同。由此可知：至少这两个保存样本之间的
  整体 VBIOS/板级差异没有改变目标嵌入字节对象。
- Dell 与 HPE 两份 RTX PRO 6000 NVFW 的文件大小相同，但目标 descriptor、
  raw `word1` (`0x36c00` 对 `0x37000`) 和 region bytes 都不同；region 长度差
  `0x400` bytes。这证明“RTX PRO 6000 family”在现有两个 package 版本中并不
  对应唯一、固定的目标字节对象。
- GeForce common、Dell Pro 8D、HPE Pro 9E 三组互不相同；这只能证明保存的
  嵌入表示不同，不能直接证明解密/解压后的程序或策略不同。

### 不能闭合的因果归因

当前目录**没有更多独立 GeForce 或 Pro 版本**：其余文件都是上述四个 raw image
的容器或精确派生切片。因此样本不是能区分因果的配对设计：

- 没有同一 firmware build 同时跨 GeForce/Pro 的配对；
- 没有已验证为同一具体 board/SKU、只改变 firmware revision 的 Pro 配对；
- Dell/HPE 两项同时改变 package/vendor context、文件名 revision，具体 board
  subvariant 也未由当前离线文件独立闭合；
- GeForce FE/ASUS 的 provenance 未验证，且它们同样不是“只改变一个变量”的
  实验对。

所以目前可以排除的是“看到 GeForce/Pro region 不同就足以证明 SKU 决策位于该
region”这种强结论；不能排除 revision、build、packing、signature、nonce/IV、
重新加密或真正 plaintext 差异等解释。Pro 两项彼此不同尤其说明，单纯用
GeForce-vs-Pro 标签不能解释所有观察到的 target 差异。

## 6. `word1` 与高 entropy 的最终边界

**2026-07-22 后续校正：**四份目标 descriptor 所属 hash table 均有
`raw0=0x22 | length=0x50+word1 | SHA-384(envelope)` entry，摘要全部精确复算
一致；`raw0=0x22` 是 covered-start 相对偏移，不是 Falcon index 34。详见
`parallel/falcon_manifest_table.md` 与 `parallel/bcrt_manifest_coverage.md`。因此
下文切片的 exact envelope boundary 已被 hash entry 确认，只有 `word1` 的正式
字段名/完整 v6 schema 仍未公开。

既有四样本复核中，这些 hash-confirmed region 的 Shannon entropy 都约为 7.999 bit/byte，
并覆盖全部 256 个 byte 值。它们与高质量压缩、加密或其他高熵编码相容，但不
区分这些来源，也不验证算法、key、nonce、签名或可执行语义。

`word1` 长度模型有一致的局部支持：四个目标切片的 confirmed end 都落到高熵材料转为
`0xff` padding 的位置，另一个 descriptor 邻接对也符合
`descriptor + 0x50 + word1 == next descriptor`。但目标 `app=0x24/target=0x0f`
本身都是物理上最后一个登记 descriptor，confirmed end 既没有 next descriptor，
也不是 physical EOF；hash entry 已独立证明 on-disk envelope 边界。仍需保守的
只是 private field 语义：公开 v6 schema 不足以把 `word1` 正式命名为
`StoredSize`、ciphertext size 或 executable size。

## 7. 结论

本地 `vbios_diff/` 没有隐藏出更多独立 GB202 Falcon `app=0x24/target=0x0f`
版本。14 个文件经 archive/member、嵌套 raw 与 derived-chain 去重后是 4 个完整
raw image、3 个 target 字节对象。GeForce 两个版本共享同一 target；Pro 两个
版本各不相同。这个不平衡结果足以证明“target 字节差异不能唯一归因于 SKU”，
但不足以在 SKU、firmware revision、board/vendor build 与高熵打包差异之间作
因果区分。

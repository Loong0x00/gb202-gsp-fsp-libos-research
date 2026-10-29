# Falcon v6 `app=0x24 / target=0x0f` 离线字节比较

## 1. 范围与命名纪律

本次只读取四个已经保存在本地的 VBIOS/NVFW 文件。没有打开任何设备节点、
PCI/sysfs resource、`/dev/mem` 或 MODS，也没有加载、解密或执行固件。

现有公开资料只覆盖旧版 Falcon descriptor；GB202 这里是 v6。因此下文只把
Falcon 表里的 `app_id`、`target_id`、descriptor 指针，以及沿用的 `vDesc`
首字布局作为可直接解析的结构。其余 v6 word 均没有采用私有语义名：

- `word1` 只表示 descriptor 起点 `+0x04` 的原始 little-endian `u32`；
- “`word1` 是紧随 descriptor 的区域字节数”是**推断**，不是公开字段名；

**2026-07-22 后续校正：**`parallel/falcon_manifest_table.md` 与
`parallel/bcrt_manifest_coverage.md` 在四份 target descriptor 所属 hash table
中都确认 `raw0=0x22 | length=0x50+word1 | SHA-384(envelope)`；摘要全部精确
复算一致。`raw0=0x22` 是相对 table end 的 covered-start offset，不是 Falcon
index 34。因此本文切片的 **envelope 边界现已由 hash entry 直接确认**；
`word1` 的正式 v6 字段名仍未公开，不能仅据此命名为 `StoredSize`。
- “word1-sized immediate region”是中性切片名。即使 `encrypted` bit 为 1，
  也不把该切片直接命名为已验证的 ciphertext、code、data 或 signature；
- `FSP_RUN` 只是一段可打印字节，不证明 task、subobject 或入口点语义。

该推断并非只靠字节边界：NVIDIA 610.43.03 公开
`kernel_gsp_fwsec.c:148-185` 中，Falcon descriptor v2 与 v3 在 header 后的
第一个 `u32`（同一 `+0x04`）都明确命名为 `StoredSize`。但同文件只定义到
version 常量 v4，解析器实际只接受 v2/v3；NVIDIA 当前公开 main（610.43.02）
也仍是相同范围，没有 v6 struct。因此“字段位置跨版本延续”给 v6 `word1`
长度解释提供了额外**模式证据**，仍不能把旧版字段名直接升级成 v6 FACT。

## 2. 精确输入

| 样本 | 本地文件 | 文件大小 | 文件 SHA-256 |
|---|---|---:|---|
| RTX 5090 FE | `vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom` | `0x1defff` | `a966aca23518708e44c961af865cccfdfabebc9d0cd06a8e29577a0bd82dc5eb` |
| ASUS RTX 5090 | `vbios_diff/unverified_TPU_280522_ASUS_Astral_1043-89E3_98.02.2E.40.85.rom` | `0x1defff` | `eeb68ef4ce8b70d2f72aa1738b04e89d912c3af977722959e7ca60c1195f1111` |
| Dell RTX PRO 6000 8D | `vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw` | `0x1d1dd0` | `8658724061087279f59ca3a0d8ce443cb4ca52db2543c64723a3cea632a29b59` |
| HPE RTX PRO 6000 9E | `vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw` | `0x1d1dd0` | `98c52f80e937907c4203280824bbef6bb17439c900edc74532072780611c0fe5` |

前两份文件名本身带有 `unverified_TPU`，不能当作实卡 dump provenance。
Dell/HPE 行比较的是从本地升级包保存下来的 `.nvfw`，不是设备回读。

## 3. Descriptor 定位与首字

四份 Falcon 表都只有一个 `app=0x24 / target=0x0f` 条目，表内 index 均为
34。磁盘上的首四字节均为 `0d 06 50 00`，即 raw little-endian word0
`0x0050060d`。按现有 `vDesc` 首字解析为 `flags=0x0d`、`version=6`、
`descriptor_size=0x50`；`flags.bit2=1`，所以报告为 `encrypted=true`。

| 样本 | descriptor relative | descriptor absolute | raw word0 / 解码 | raw `word1`（**长度语义为推断**） | 0x50-byte descriptor SHA-256 | 可打印字节观察 |
|---|---:|---:|---|---:|---|---|
| RTX 5090 FE | `0xcb304` | `0x11b304` | `0x0050060d`: flags `0x0d`, v6, size `0x50` | `0x29400` | `ccc6647fda7d26f4de03f65d46cc683b52c5cb0dac1d3ed75b2e1a08885870fc` | `FSP_RUN` |
| ASUS RTX 5090 | `0xcb304` | `0x11b304` | 同上 | `0x29400` | `ccc6647fda7d26f4de03f65d46cc683b52c5cb0dac1d3ed75b2e1a08885870fc` | `FSP_RUN` |
| Dell RTX PRO 6000 8D | `0xd5104` | `0x128104` | 同上 | `0x36c00` | `cd2e6b2d6be17311be889c5e5c8b4b379166c9e1c4f8d58c894f70aa48b2219e` | `FSP_RUN` |
| HPE RTX PRO 6000 9E | `0xd9d04` | `0x12cd04` | 同上 | `0x37000` | `817c1fbe53c379d6369cefc41dca181b759df607d3a44015f9d666563fd77aee` | 稳定核心为 `FSP_RUN`；启发式 printable run 会继续吸收后面的 `/8` |

HPE 的 `/8` 来自 `FSP_RUN` 后两个恰好可打印的 private bytes；它正好说明
不能把最长 printable run 当作一个已定义字符串字段。

## 4. `word1`-sized immediate region

采用下列**推断切片**：

```text
start = descriptor_absolute + descriptor_size
end   = start + le32(descriptor_absolute + 4)   # end exclusive
region = file[start:end]
```

Shannon entropy 按 256 个 byte 值的经验频率计算：
`H = -sum(p[i] * log2(p[i]))`，单位为 bit/byte；没有做解密、解压或去头。

| 样本 | region `[start,end)` | size | SHA-256 | Shannon entropy |
|---|---|---:|---|---:|
| RTX 5090 FE | `[0x11b354,0x144754)` | `0x29400` = 168,960 B | `1a546c20674f1ccb50c5451f305ed3e2e64a2396ae8bf8418ac61ce944597214` | `7.999017` bit/B |
| ASUS RTX 5090 | `[0x11b354,0x144754)` | `0x29400` = 168,960 B | `1a546c20674f1ccb50c5451f305ed3e2e64a2396ae8bf8418ac61ce944597214` | `7.999017` bit/B |
| Dell RTX PRO 6000 8D | `[0x128154,0x15ed54)` | `0x36c00` = 224,256 B | `3ba673453b10609d54887abba30fff8f0571435dbd73bed68bac99808e590c09` | `7.999129` bit/B |
| HPE RTX PRO 6000 9E | `[0x12cd54,0x163d54)` | `0x37000` = 225,280 B | `125328597c20b8c09ae40489ddab56c2b05d203501d865f2c6f154bfd999e9d9` | `7.999179` bit/B |

所有四个 region 都出现全部 256 个 byte 值。接近 8 bit/B 与加密或高质量压缩
材料相容，但 entropy 本身不能区分加密、压缩或其它高熵编码，也不能验证算法、
key、nonce、签名或可执行语义。

## 5. `word1` 长度是否有边界支持

### 5.1 目标 descriptor 的严格检查

`app=0x24 / target=0x0f` 在四份文件里都是物理地址最高的已登记 Falcon
descriptor，因此没有“下一个已登记 descriptor”可用于验证终点；其推断终点也
都不是物理 EOF：

| 样本 | 推断 end | 下一个已登记 descriptor | physical EOF | EOF 前剩余字节 | 严格的 adjacent-descriptor / EOF 支持 |
|---|---:|---|---:|---:|---|
| RTX 5090 FE | `0x144754` | 无 | `0x1defff` | `0x9a8ab` | **无** |
| ASUS RTX 5090 | `0x144754` | 无 | `0x1defff` | `0x9a8ab` | **无** |
| Dell RTX PRO 6000 8D | `0x15ed54` | 无 | `0x1d1dd0` | `0x7307c` | **无** |
| HPE RTX PRO 6000 9E | `0x163d54` | 无 | `0x1d1dd0` | `0x6e07c` | **无** |

因此，不能写成“word1 的私有字段语义已由相邻 descriptor 或文件末尾证明”。

### 5.2 有限但一致的局部支持

虽然严格检查为“无”，四份样本都在推断 end 处出现同一种清楚的局部转折：

- `[end,end+0xab)` 恰好是连续 171 byte 的 `0xff`；
- `end+0xab`（下一 `0x100` 边界的前一字节）才再次出现非 `0xff`；该字节分别
  为 FE `0x90`、ASUS `0xc6`、Dell `0x83`、HPE `0x11`，其语义未知；
- 若误把 `word1` 当作包含 0x50-byte descriptor 的总长，终点会提前 0x50，
  后面仍有 0x50 byte 高熵数据，不会落在上述 padding 转折处。

另有一个只用于检查模型的邻接对照：每份文件中物理第一个非空 descriptor
`app=0x07 / target=0x06` 都满足
`descriptor + 0x50 + word1 ==` 下一个已登记的
`app=0x19 / target=0x01` descriptor（FE/ASUS 为 `0xc7ff0`，Dell 为
`0xcc780`，HPE 为 `0xce494`）。这给“word1 是紧随区域大小”的**推断**提供了
跨样本结构一致性，但仍不是 v6 私有字段的公开定义，也不能替代目标条目的严格
next-descriptor/EOF 证明。

## 6. 跨样本完全相同/不同能说明什么

### 能说明

- FE 与 ASUS 的完整 0x50-byte descriptor 和推断 region 均逐字节完全相同；
  相同 SHA-256 这里不是孤立碰撞假设，而是直接 byte comparison 的摘要记录。
  这证明这两个保存文件在该切片中复用了同一个嵌入字节对象，尽管两份完整 VBIOS
  的 SHA-256 不同。
- Dell、HPE 以及 FE/ASUS 组之间的 region 长度和 SHA-256 均不同，证明保存的
  嵌入表示不是同一串字节。Dell 与 HPE 的长度还相差 `0x400` = 1,024 byte。
- 四份相同的 raw word0 只证明它们共享同一 envelope 首字取值：v6、0x50-byte
  descriptor、flags `0x0d`；它不证明后续私有 descriptor words 或 region 相同。

### 不能说明

- 完全相同的高熵 region 不能证明两张卡运行时行为相同。相同代码/数据仍可读取
  板级配置、OTP/fuse、InfoROM 或其它外部输入后走不同分支。
- 完全不同的 region 不能直接证明解密后程序、L2 策略或功能不同。差异可能来自
  build、打包、padding、签名、nonce/IV、重新加密或真正的 plaintext 差异；当前
  离线字节证据不能区分这些来源。
- 长度不同提高了“嵌入表示/打包版本不同”的可信度，但仍不能把多出的字节命名为
  新代码、L2 表、license feature 或 server-only policy。
- 这些比较不能恢复 plaintext，不能确认认证链或密钥，也不能证明 descriptor
  会在任一具体设备上被选择、接受或执行。
- 特别是，FE/ASUS 相同与 Dell/HPE 不同都不能单独证明 96 MiB/128 MiB L2 的
  SKU 决策位于或不位于该 region。密文字节 diff 没有可验证的字段到 L2 语义映射。

## 7. 结论

四个目标条目共享 raw header `0x0050060d`，但只有 FE 与 ASUS 的完整 descriptor
及推断 immediate region 完全相同；Dell 8D 和 HPE 9E 各自有不同长度和不同字节。
把 private `word1` 当作 descriptor 后区域的长度，能在四份样本上精确落到高熵
数据到 `0xff` padding 的转折，并得到一个其它 descriptor 的跨样本邻接对照；
公开 v2/v3 的同位置 `StoredSize` 又给出跨版本模式支持。更直接的是，四份 target
hash entry 的 `length` 都精确等于 `0x50 + word1`，且 SHA-384 全部匹配，所以
**本文所用 envelope 的字节边界已是 FACT**。仍未公开的是 v6 中 `word1` 的正式
字段名和完整语义；不能仅因边界已确认，就把它未经格式定义地命名为
`StoredSize`、加密长度或可执行代码长度。

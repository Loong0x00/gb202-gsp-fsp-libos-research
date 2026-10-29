# GB202 Falcon-v6 `FSP_RUN` 三个唯一对象的离线差分

## 1. 范围、安全边界与结论先行

本轮只读取 `/home/user/rt_5090_project/vbios_diff/` 中已经保存的 ROM/NVFW，复用
`gb202_vbios_diff.py` 解析 BIT、PCI expansion-ROM chain 与 Falcon 表。没有访问
GPU、`/dev/nvidia*`、PCI BAR/MMIO、sysfs resource、debugfs 或 MODS；没有运行任何
固件/updater，没有 reset/rebind，也没有写 VBIOS 或设备状态。最大被比较区域仅
225,280 bytes；没有全盘或高内存扫描。

结论：**三个对象的差异最像“不同的 FSP 对象 build/封装版本，再经过加密/认证
封装”，而不是单纯的 VBIOS 外层元数据变化。** 现有字节不能证明解密后的程序
一定不同，也不能排除 nonce/IV、签名、padding 或压缩造成一部分乃至大部分差异。

- **FACT:** FE 与 ASUS 的完整 VBIOS hash 不同，但目标 descriptor 和后随 region
  逐字节相同。这是“只改外层/板级 VBIOS、内嵌 FSP 对象保持不变”的实际对照。
- **FACT:** FE-common、Dell 8D、HPE 9E 三个唯一对象的 descriptor 私有尺寸字段、
  region 长度和 region bytes 均不全相同；Dell 到 HPE 还出现一个只在该
  `FSP_RUN` 条目中观察到的 `3 -> 4` 成对变化。因此三个唯一对象之间不是只改了
  外层指针或表位置。
- **FACT:** 三个 region 均近满熵、不可被 zlib 缩小；任意两组的同位置 byte
  相等率约为随机期望的 `1/256`，bit 差异率约 50%，没有共同的 region-start
  对齐 16-byte block。结合 descriptor 的 encrypted bit，这与密文相容。
- **INFERENCE:** “对象 build/封装版本变化 + 加密造成字节去相关”比“相同对象只
  因外层 VBIOS 元数据变化”更符合全部证据。它也比“完全相同 plaintext 每次仅
  随机重加密”更强，因为明文 descriptor 自己的长度关系和成对字段也发生了结构化
  变化；但当前不能量化 plaintext 变化占多少。
- **UNKNOWN:** v6 私有字段、cipher、key、nonce/IV、签名布局、压缩顺序、plaintext
  长度和执行语义仍未知；没有任何差分可映射到 task 2、PLM 或 L2 策略。

**2026-07-22 后续校正：**`parallel/falcon_manifest_table.md` 与
`parallel/bcrt_manifest_coverage.md` 已在三组 target hash table 中机械确认
`raw0=0x22 | length=0x50+word1 | SHA-384(envelope)`，并对四份样本全部复算
匹配。`raw0=0x22` 是 covered-start 相对偏移，不是 Falcon index 34。因此下文
region/envelope 的**字节边界不再只是强推断**；`word1` 的正式字段名、加密/
认证算法、以及 parent digest 的最终签名/root 仍未知。

## 2. 输入与三组去重结果

解析器 SHA-256：
`90cefd37e109684119e98c5ab64ef382048710dcdc344e1cd4bb5d70abb517eb`。

| 组 | canonical 文件 | bytes | 整文件 SHA-256 |
|---|---|---:|---|
| FE-common | `vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom` | 1,961,983 | `a966aca23518708e44c961af865cccfdfabebc9d0cd06a8e29577a0bd82dc5eb` |
| Dell Pro 8D | `vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw` | 1,908,176 | `8658724061087279f59ca3a0d8ce443cb4ca52db2543c64723a3cea632a29b59` |
| HPE Pro 9E | `vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw` | 1,908,176 | `98c52f80e937907c4203280824bbef6bb17439c900edc74532072780611c0fe5` |

**FACT:** ASUS
`vbios_diff/unverified_TPU_280522_ASUS_Astral_1043-89E3_98.02.2E.40.85.rom`
整文件 SHA-256 为
`eeb68ef4ce8b70d2f72aa1738b04e89d912c3af977722959e7ca60c1195f1111`，
不同于 FE；但其目标 0x50-byte descriptor 与 hash-confirmed region 都和 FE 逐字节相同，
所以不是第四个目标对象。两份 GeForce 文件名都带 `unverified_TPU`，不能当作
本机实卡 dump；Dell/HPE 是升级包中的 NVFW，也不是设备回读。

## 3. 从 Falcon 表到 descriptor 的准确路径

### 3.1 Falcon 表头与最后一个 entry

三个表的 6-byte raw header 都是：

```text
01 06 06 23 01 30
```

按公开 `FALCON_UCODE_TABLE_HDR_V1` 字段名，它是
`Version=1, HeaderSize=6, EntrySize=6, EntryCount=35,
DescVersion=1, DescSize=0x30`。目标 entry 均为 index 34，即最后一个 entry，
其位置固定为 `table + 6 + 34*6 = table + 0xd2`。

| 组 | image base | expansion offset | Falcon table abs | target entry abs | raw 6 bytes | descriptor rel / abs |
|---|---:|---:|---:|---:|---|---:|
| FE-common | `0x38000` | `0x18000` | `0x9ce9d` | `0x9cf6f` | `24 0f 04 b3 0c 00` | `0xcb304` / `0x11b304` |
| Dell Pro 8D | `0x3b000` | `0x18000` | `0xa0783` | `0xa0855` | `24 0f 04 51 0d 00` | `0xd5104` / `0x128104` |
| HPE Pro 9E | `0x3b000` | `0x18000` | `0xa0c3e` | `0xa0d10` | `24 0f 04 9d 0d 00` | `0xd9d04` / `0x12cd04` |

- **FACT:** entry 的 `24 0f` 是 `ApplicationID=0x24, TargetID=0x0f`；后四字节
  是 little-endian descriptor pointer。公开 610 的 entry struct 支持该布局。
- **FACT:** 本地解析器按
  `descriptor_abs = image_base + expansion_offset + descriptor_rel` 计算；上表三组
  都严格满足该关系。
- **FACT:** 三组表头与 app/target/index 完全相同；变化的是表的物理位置和
  descriptor pointer。这部分属于外层定位元数据。
- **FACT:** 表头最后两个 legacy/default 字段为 `1/0x30`，但 pointed descriptor
  自己的 `vDesc` 为 v6/0x50；公开读取代码同样以 pointed `vDesc` 自描述版本与
  大小为准。当前不把两者的关系外推到 v6 私有语义。

### 3.2 0x50-byte descriptor 的完整 raw words

三组 descriptor 首字都是 little-endian `0x0050060d`：

- **FACT:** flags `0x0d`，其中 bit 0 表示 version available，bit 2 是公开定义的
  `ENCRYPTED`；bit 3 在公开旧格式中列为 reserved，不能对 v6 擅自命名。
- **FACT:** descriptor version `6`，descriptor size `0x50`。
- **FACT:** 字节 `[+0x2d,+0x34)` 精确为 ASCII `FSP_RUN`。这是明文字节观察，
  不是已定义字段名、入口点或 task handler 证明。
- **FACT:** 公开 610 只给 v2/v3 body struct；因此 `+0x04..+0x4f` 的 v6 字段名
  均不能从公开格式确认。下表保留为 raw word。

| offset | FE-common | Dell Pro 8D | HPE Pro 9E |
|---:|---:|---:|---:|
| `+0x00` | `0x0050060d` | `0x0050060d` | `0x0050060d` |
| `+0x04` | `0x00029400` | `0x00036c00` | `0x00037000` |
| `+0x08` | `0x00018800` | `0x00016800` | `0x00016800` |
| `+0x0c` | `0x00025400` | `0x00030c00` | `0x00031000` |
| `+0x10` | `0x00001400` | `0x00004000` | `0x00004000` |
| `+0x14` | `0x00004000` | `0x00006000` | `0x00006000` |
| `+0x18` | `0x00000301` | `0x00000301` | `0x00000401` |
| `+0x1c` | `0x01030000` | `0x01030000` | `0x01040000` |
| `+0x20` | `0x00000000` | `0x00000000` | `0x00000000` |
| `+0x24` | `0x00000000` | `0x00000000` | `0x00000000` |
| `+0x28` | `0x01012801` | `0x01012801` | `0x01012801` |
| `+0x2c` | `0x50534600` | `0x50534600` | `0x50534600` |
| `+0x30` | `0x4e55525f` | `0x4e55525f` | `0x4e55525f` |
| `+0x34` | `0xffdd67c9` | `0xaeed1aab` | `0xfef8382f` |
| `+0x38` | `0xcdc01ac2` | `0xbf82d6c5` | `0x7b968e7e` |
| `+0x3c` | `0xf96a91fd` | `0x474fa2ca` | `0xbea08a62` |
| `+0x40` | `0xd2498c8a` | `0xe51b50bf` | `0xd6f3b56d` |
| `+0x44` | `0x2fdb1698` | `0x83b73561` | `0xbc291ba1` |
| `+0x48` | `0x77bfa38f` | `0x548d1b4b` | `0x46875ee4` |
| `+0x4c` | `0x9b98fb27` | `0x70a9b41f` | `0xf697c5c2` |

Descriptor SHA-256 分别是：

| 组 | 0x50-byte descriptor SHA-256 | opaque tail `[+0x34,+0x50)` SHA-256 |
|---|---|---|
| FE-common | `ccc6647fda7d26f4de03f65d46cc683b52c5cb0dac1d3ed75b2e1a08885870fc` | `523588f0b253fbc73ca23858281863430ec5fa59b8d784b11d7026eef5e242bb` |
| Dell Pro 8D | `cd2e6b2d6be17311be889c5e5c8b4b379166c9e1c4f8d58c894f70aa48b2219e` | `1482beb731bbfe70ce92b1e24ae290e876fcfabffcff5eb00bf36e74862c7d48` |
| HPE Pro 9E | `817c1fbe53c379d6369cefc41dca181b759df607d3a44015f9d666563fd77aee` | `8c3e29db4731e51c9f67ff7a27adc33b6c9d1cb4db907d44a93ac4c2e05c2299` |

**FACT:** Dell 与 HPE 都是 Pro-family 样本；两者只有 11/20 个 raw dword 不同。
除 7 个完全不透明的尾部 dword 外，结构化差异恰好位于 `+0x04`、`+0x0c`、
`+0x18`、`+0x1c`。尤其 `+0x18/+0x1c` 同步从 `03` 形态变为 `04` 形态。
对各镜像全部 6 个非空 Falcon v6 descriptor 的有限复核显示，这个 `3 -> 4`
变化只发生在目标 `FSP_RUN` 条目，不是 HPE 镜像所有 descriptor 的全局改写。

**INFERENCE:** 该成对变化很像 FSP 对象自身的版本/格式 epoch，而不是随机密文
偶然改变；但公开 v6 struct 缺失，所以不能把它正式命名为 code version、signature
version 或 key version。

## 4. Hash-confirmed 对象边界与内部长度关系

公开 v2/v3 descriptor 在同一 `+0x04` 位置把字段命名为 `StoredSize`；v6 没有
公开 body 定义。四份 target hash entry 现已直接确认下列 on-disk covered range；
公式中的 `word1` 仍只是私有 raw 字段，不把它正式命名为 `StoredSize`：

```text
descriptor = [desc_abs, desc_abs + 0x50)
region_start = desc_abs + 0x50
region_end   = region_start + le32(desc_abs + 0x04)   # end exclusive
hash-confirmed object envelope = [desc_abs, region_end)
```

| 组 | descriptor | hash-confirmed region `[start,end)` | region bytes | 全 envelope bytes | 全 envelope SHA-256 |
|---|---|---|---:|---:|---|
| FE-common | `[0x11b304,0x11b354)` | `[0x11b354,0x144754)` | `0x29400` = 168,960 | `0x29450` = 169,040 | `1f01255cf607f32ef1cbffb0d65c9fb5829e55f63af1f0ca9a674f5e9adab19c` |
| Dell Pro 8D | `[0x128104,0x128154)` | `[0x128154,0x15ed54)` | `0x36c00` = 224,256 | `0x36c50` = 224,336 | `c1c88db07805cb294e00a38829f47a14de07bf306c5b16047e6dfaf9df97f8dc` |
| HPE Pro 9E | `[0x12cd04,0x12cd54)` | `[0x12cd54,0x163d54)` | `0x37000` = 225,280 | `0x37050` = 225,360 | `8966b4a6ed94c35441609270125da4326a89ef94f7d05e00ef04ecb4558c8a18` |

- **FACT:** 每组都精确满足 raw relation
  `word(+0x04) = word(+0x0c) + word(+0x14)`：FE 是
  `0x29400 = 0x25400 + 0x4000`；Dell 是
  `0x36c00 = 0x30c00 + 0x6000`；HPE 是
  `0x37000 = 0x31000 + 0x6000`。
- **FACT:** 按这两个私有 size-like word 分割 region 后，两段均为高熵且三组 hash
  各异。第一段大小/哈希分别为 FE `0x25400`/
  `d341695ab97bd23de00fc26b4ff036ef4ac10b1e768f4bc7c762ecc4281fc2da`，
  Dell `0x30c00`/
  `47ca7694144daf87ef26387bd99bd6954175bf39101f516d0edc319bee0ff0a2`，
  HPE `0x31000`/
  `4895ec1688e9519e9189f290efd432349566a3f77690af50872796ef21f90eb8`；
  第二段为 FE `0x4000`/
  `13c3822f5d0ec9b90e587ef324facbd98ea8223f3cbd48cd7b2ec9e380a563b8`，
  Dell `0x6000`/
  `7df87c552931bda518b3d62d15a092e7fbee3d9922454a1565bb16697fb701b3`，
  HPE `0x6000`/
  `6b480e56de61d2bac6fdc8036336f9a1f7eb46db1472cdbd4d5624275cec3f5c`。
- **FACT:** 三个 confirmed `region_end` 后的 `[end,end+0xab)` 都恰好为 171 bytes
  `0xff`；`end+0xab` 才出现第一个非-`0xff` byte（FE `0x90`、Dell `0x83`、
  HPE `0x11`）。这与已有另一个 descriptor 的 adjacent-boundary 对照共同支持
  `+0x04` 是后随 region 长度。
- **FACT:** stored/recomputed SHA-384 entry 把上述实际 on-disk envelope 边界
  提升为直接字节事实；边界不再依赖 next descriptor 或 physical EOF。
- **INFERENCE/UNKNOWN:** region 内两个 raw size-like word 提示至少有两个
  size-accounted 子区；由于它们属于 v6 私有 body，本报告不把两段命名为 code、
  data、signature 或 certificate，也不把 `word1` 的正式字段语义写成已公开。

## 5. Region 字节差分

### 5.1 单对象统计

| 组 | region SHA-256 | Shannon entropy | zlib-9 bytes / 原长 | 完整 4 KiB block entropy（mean/min/max） |
|---|---|---:|---:|---|
| FE-common | `1a546c20674f1ccb50c5451f305ed3e2e64a2396ae8bf8418ac61ce944597214` | `7.999017065` | `169021 / 168960 = 1.000361` | `7.955493 / 7.947303 / 7.963242` |
| Dell Pro 8D | `3ba673453b10609d54887abba30fff8f0571435dbd73bed68bac99808e590c09` | `7.999129060` | `224332 / 224256 = 1.000339` | `7.954737 / 7.948020 / 7.963180` |
| HPE Pro 9E | `125328597c20b8c09ae40489ddab56c2b05d203501d865f2c6f154bfd999e9d9` | `7.999179029` | `225356 / 225280 = 1.000337` | `7.954557 / 7.945381 / 7.961436` |

**FACT:** 三组都出现全部 256 个 byte 值，zlib 不仅没有缩小，反而增加 61--76
bytes。这里只把 zlib 当作低成本可压缩性探针；它不识别原始压缩算法。

### 5.2 两两相似度

比较以较短 region 的长度为 overlap。`expected equal` 是独立均匀 byte 的
`N/256`；bit difference 是逐 byte XOR 后的 popcount。

| pair | overlap | 同位置相等 bytes | 期望 `N/256` | 同位置相等率 | bit 差异率 | 最长同位置相等 run |
|---|---:|---:|---:|---:|---:|---:|
| FE / Dell | 168,960 | 674 | 660 | `0.398911%` | `50.038619%` | 2 bytes |
| FE / HPE | 168,960 | 658 | 660 | `0.389441%` | `49.993933%` | 2 bytes |
| Dell / HPE | 224,256 | 874 | 876 | `0.389733%` | `50.012263%` | 2 bytes |

- **FACT:** 对 region-start 对齐的非重叠 block，在每一 pair 中，16、32、64、256
  与 4096-byte 粒度的“同位置相同 block”均为 0；把这些 block 当集合比较，
  “任意 block index 的相同 block”也均为 0。16-byte block 数分别是 10,560、
  10,560 和 14,016。
- **FACT:** 额外只测试了有限、结构上合理的 shift
  `-0x1000,-0x400,-0x100,0,+0x100,+0x400,+0x1000`；所有 pair 的 byte equality
  仍在 `0.361955%..0.410871%`，没有显示简单插入/删除后重新对齐的大片复用。
- **INFERENCE:** 这些数值与彼此去相关的高熵材料非常吻合。结合明确的 encrypted
  bit，“保存 region 主要是密文/认证封装”是最自然的解释之一；但同样统计也可由
  不同的高质量压缩流或“压缩后再加密”产生，不能识别 cipher 或证明 plaintext
  不同。

## 6. 三种解释的证据权重

### A. 只改外层 VBIOS 元数据

- **FACT（支持对照）:** FE 与 ASUS 的整文件不同、VBIOS filename revision 和
  board context 不同，但完整 target descriptor/region 相同；外层变化确实可以
  不触碰 FSP object。
- **FACT（反对作为三个唯一对象的解释）:** Dell/HPE 与 FE 不仅是 table/pointer
  位置不同，descriptor 的 size-like words、opaque tail、region 长度与 region
  bytes 都变了；Dell/HPE 之间也一样。
- **VERDICT:** 能解释同一 FE-common 对象出现在不同 VBIOS，不能解释三个唯一
  对象为何不同。

### B. 完全相同 plaintext，只随机化加密

- **FACT（相容）:** pairwise byte/bit 相似度完全呈随机去相关形态；opaque
  descriptor tail 也各异。
- **FACT（削弱“纯随机化就是全部解释”）:** FE/ASUS 的对象逐字节相同，说明目标
  对象不是每次外层 ROM/板卡 packaging 都重新随机加密。Dell/HPE 的 region 又
  相差 `0x400`，并伴随 `+0x0c` 同步增长 `0x400`、FSP-only `3 -> 4` 成对字段
  变化；这不是只看密文随机噪声得到的差别。
- **UNKNOWN:** 相同 plaintext 经过不同 padding、signature/certificate、压缩参数
  和 nonce 后仍可能产生不同长度及完全不同密文，所以不能彻底排除。
- **VERDICT:** 加密/认证封装很可能负责“为何一个 byte block 都对不上”，但“完全
  相同 plaintext 仅重新随机加密”不是现有结构证据最支持的唯一解释。

### C. FSP 对象 build/封装版本变化

- **FACT:** 三组的 clear descriptor 结构值不同；Dell/HPE 两份同属 Pro family，
  仍有 `0x400` size 增长与目标条目独有的 `3 -> 4` 成对变化。FE/ASUS 则证明
  object 可以跨外层 VBIOS 原样复用。
- **INFERENCE:** 最节省假设的模型是：FE-common、Dell 8D、HPE 9E 携带三个
  不同的预构建 FSP object/envelope revision；每个对象内部又经过加密/认证，因而
  build 间看不到普通代码差分的局部相似性。
- **UNKNOWN:** “对象版本不同”不等同于“task-2 handler 或 L2 policy 不同”。变化
  可能只在链接布局、padding、压缩、证书/签名或密钥 epoch；也可能包含真正程序
  变化。当前密文字节不能二分。
- **VERDICT:** 这是三种解释中最符合全部现有证据的一种，但准确名称应是
  **object/envelope build revision**，不能升级成已证明的 plaintext code revision。

## 7. 对解锁研究的直接含义

- **FACT:** 没有发现明文的 `96 MiB/128 MiB`、L2 mask、task-2 dispatch 或 PLM
  策略字段。
- **INFERENCE:** 继续对三份密文做普通 disassembly/diff 不会恢复 handler 逻辑；
  有意义的静态下一步只能是找到 v6 descriptor 的公开/泄露格式定义、认证展开器、
  或相同 plaintext 的已知配对，从 envelope 元数据建立字段语义。
- **UNKNOWN:** receiver 仍可能位于该 `FSP_RUN` 对象、芯片 ROM，或另一认证后才
  出现的内部 stage。该差分没有把三者之一提升为 FACT。
- **SAFETY:** 这些对象的加密/签名与格式未知，不能据此拼接 Pro blob、修改长度、
  刷写或在桌面所用 5090 上做 live load。全部结果只是离线边界与归因证据。

## 8. 复现命令与计算定义

本轮使用的直接只读命令：

```bash
cd /home/user/rt_5090_project

sha256sum gb202_vbios_diff.py \
  vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom \
  vbios_diff/unverified_TPU_280522_ASUS_Astral_1043-89E3_98.02.2E.40.85.rom \
  vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw \
  vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw

python3 gb202_vbios_diff.py \
  vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom \
  vbios_diff/unverified_TPU_280522_ASUS_Astral_1043-89E3_98.02.2E.40.85.rom \
  vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw \
  vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw

xxd -g1 -l 16 -s 0x9ce9d vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom
xxd -g1 -l 6  -s 0x9cf6f vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom
xxd -g4 -l 80 -s 0x11b304 vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom

xxd -g1 -l 16 -s 0xa0783 vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw
xxd -g1 -l 6  -s 0xa0855 vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw
xxd -g4 -l 80 -s 0x128104 vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw

xxd -g1 -l 16 -s 0xa0c3e vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw
xxd -g1 -l 6  -s 0xa0d10 vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw
xxd -g4 -l 80 -s 0x12cd04 vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw
```

深度统计复用了 `load_image()`、`parse_pci_chain()`、`parse_falcon_table()` 与
`parse_falcon_descriptor_header()`，只在上述三个 `word1`-sized region 上计算：

```text
entropy = -sum(count[b]/N * log2(count[b]/N))
same-position bytes = sum(a[i] == b[i]) over min(len(a),len(b))
bit difference = sum(popcount(a[i] XOR b[i]))
block overlap = exact byte equality of non-overlapping blocks aligned to region start
tested block sizes = 16, 32, 64, 256, 4096 bytes
tested shifts = -0x1000, -0x400, -0x100, 0, +0x100, +0x400, +0x1000
compressibility probe = len(zlib.compress(region, 9)) / len(region)
```

公开格式交叉检查位置：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c:100-188,600-669`。
这里定义 Falcon table header/entry、`vDesc` flags/version/size 和 v2/v3 body；没有
v6 body struct。

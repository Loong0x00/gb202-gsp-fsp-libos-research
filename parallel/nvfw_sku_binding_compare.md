# GB202 ROM/NVFW 的 board/SKU binding 对照（纯离线）

日期：2026-07-22（Asia/Singapore）

## 1. 范围与安全边界

本次只读比较项目中已经保存的四份 canonical raw image，以及 Dell/HPE 已保存
`.fwpkg` 的明文 PLDM metadata：

- RTX 5090 FE `98.02.2E.00.03`；
- ASUS RTX 5090 `98.02.2E.40.85`；
- Dell RTX PRO 6000 `98.02.8D.00.01`；
- HPE RTX PRO 6000 `98.02.9E.00.01`。

没有执行 updater、`nvflash`、MODS、ROM 或 firmware，没有访问 GPU、设备节点、
PCI/BAR/MMIO、debugfs、网络或 reset。所有结论都来自普通文件的结构读取、hash、
公开 PCI/PLDM 字段解码，以及对明文 EC point 的离线曲线合法性检查。

两份 GeForce 文件名带 `unverified_TPU`，所以其字节关系可以复算，但来源身份不能
升级为已验证的本机/厂商 dump。

## 2. 结论先行

1. **可证的 outer binding 确实存在。** 顶层 legacy PCIR/NPDE 明确区分 GeForce
   `10de:2b85` 与 Pro `10de:2bb5`，并携带 subsystem tuple：FE
   `10de:2057`、ASUS `1043:89e3`、Dell/HPE Pro `10de:204e`。明文板卡字符串也分别
   是 `PG144 SKU 30`、ASUS/Astral 和 `PG153 SKU 210`。
2. **Dell/HPE 的 GPU package applicability 完全指向同一个设备身份集合。** 两份
   PLDM GPU records 都列出 PCI `10de:2bb5`、subsystem `10de:204e`、同一 UUID 和
   同一 vendor-defined `APSKU=0x00000652`。HPE 的第二条 record/第二 component 是
   另一套 SMA 身份，不应和 GPU record 混在一起。
3. **`FSP_RUN` 自己所在的后段 PCIR envelope 没有重复零售 SKU ID。** 四份样本在
   目标 descriptor 前的 PCIR 都是 `10de:2b80`；产品 `2b85/2bb5` 和 subsystem
   tuple 位于更外层的 image/package metadata。这个事实证明“对象旁边没有直接写
   2b85/2bb5”，但不能证明 device secure loader 不从外层或硬件身份取值。
4. **外层 signer/key lineage 与 `FSP_RUN` 不是一一映射。** 三个明文 key slots
   均可严格解成 P-384 uncompressed SEC1 public point。FE、Dell、HPE 三个 key
   fingerprints 全部相同，ASUS 三个全部不同；然而 FE/ASUS 的 `FSP_RUN` 完全相同，
   Dell/HPE 的则不同。
5. 因而当前样本能排除“某一个明文 board/SKU 字段或某一套 outer public keys
   唯一决定 `FSP_RUN` bytes”的强说法；**不能**排除 BootROM/FSP 根据 device ID、
   subsystem、fuse、rollback/build、签名链或其他隐藏状态执行接受策略。

## 3. 顶层 PCI/板卡身份

四份主 legacy image 的 PCIR 紧跟 NPDE v1.1；NPDE `+0x10/+0x12` 的两个 `u16`
给出 subsystem vendor/device。对应字节和明文板卡字符串如下：

| 样本 | main image / PCIR | PCI vendor:device | NPDE subsystem | 明文 board/product | BIT `B` version / OEM byte |
|---|---:|---|---|---|---|
| FE | `0x38000` / `0x38ca0` | `10de:2b85` | `10de:2057` | `PG144 SKU 30 VGA BIOS` | `0x98022e00` / `0x03` |
| ASUS | `0x38000` / `0x38ca0` | `10de:2b85` | `1043:89e3` | `RTX5090 ... AS03MR`、`ASTRAL-RTX5090` | `0x98022e40` / `0x85` |
| Dell Pro | `0x3b000` / `0x3bca0` | `10de:2bb5` | `10de:204e` | `PG153 SKU 210 VGA BIOS` | `0x98028d00` / `0x01` |
| HPE Pro | `0x3b000` / `0x3bca0` | `10de:2bb5` | `10de:204e` | `PG153 SKU 210 VGA BIOS` | `0x98029e00` / `0x01` |

例如四个 NPDE identity words 的绝对位置为：

```text
FE    0x38cd0: de 10 57 20
ASUS  0x38cd0: 43 10 e3 89
Dell  0x3bcd0: de 10 4e 20
HPE   0x3bcd0: de 10 4e 20
```

主 image 之前还有两个 code-type `0xe0` PCIR records。GeForce 位于
`0x36e00/0x37800`，都写 `10de:2b85`；Pro 位于 `0x39e00/0x3a800`，都写
`10de:2bb5`。所以 product device ID 不只是 sign-on string，而是在外层 image
records 中被重复编码。

## 4. `FSP_RUN` envelope 的 identity 边界

目标 descriptor 位于另一个 PCI image 内，且紧接在 28-byte PCIR 与 4-byte
padding 后。四份对应 PCIR 都是 vendor `0x10de`、device `0x2b80`：

| 样本 | enclosing image start | PCIR | descriptor | PCIR device | target region group |
|---|---:|---:|---:|---|---|
| FE | `0x11ae00` | `0x11b2e4` | `0x11b304` | `10de:2b80` | GeForce common |
| ASUS | `0x11ae00` | `0x11b2e4` | `0x11b304` | `10de:2b80` | GeForce common |
| Dell Pro | `0x127c00` | `0x1280e4` | `0x128104` | `10de:2b80` | Dell 8D |
| HPE Pro | `0x12c800` | `0x12cce4` | `0x12cd04` | `10de:2b80` | HPE 9E |

因此可以严格分开两层：

```text
outer image/package identity:
  2b85 or 2bb5 + subsystem + board/SKU metadata

nested target envelope identity visible beside FSP_RUN:
  common 10de:2b80 PCIR + app=24/target=0f + Falcon-v6 descriptor
```

这不是“target 对所有卡通用”的证明。secure consumer 仍可以同时读取外层 PCIR、
PLDM matching record、GPU hardware identity 或 fuse。当前静态证据只证明，目标
descriptor 邻接的 PCIR 本身没有直接重复 `2b85/2bb5` 或 subsystem tuple。

## 5. Dell/HPE PLDM applicability records

### 5.1 GPU record：匹配集合相同

Dell `.fwpkg` 有一条 device-ID record；HPE 有两条，其中 record 0 是 GPU。两份
GPU record 的 descriptor 值相同，只有记录内排列和 version string 长度不同：

| PLDM descriptor | Dell GPU | HPE GPU |
|---|---|---|
| IANA enterprise ID | `0x00001647` | `0x00001647` |
| UUID raw bytes | `7865bed953204b6ab94d8fa70b6283d6` | 相同 |
| PCI vendor (`0x0000`) | `0x10de` | `0x10de` |
| PCI device (`0x0100`) | `0x2bb5` | `0x2bb5` |
| subsystem vendor (`0x0101`) | `0x10de` | `0x10de` |
| subsystem ID (`0x0102`) | `0x204e` | `0x204e` |
| vendor-defined title/data | `APSKU` / `52 06 00 00` | 相同 |
| applicable-component bitmap | `0x01` | `0x01` |
| image-set version string | `98.02.8D.00.01` | `GPU:PG153-SKU210:` |

因此 package 层存在可机械证明的 device/subsystem/APSKU applicability binding；
它不是只靠 updater 文件名猜的。`APSKU` 的 raw little-endian value 是
`0x00000652`，本报告不猜它与字符串 `SKU210` 的换算规则。

两份 component 0 的分类/标识也一致（classification `0x000a`、identifier
`0xc000`），image bytes 都是完整 NVFW。comparison stamp、activation flags、
version 和 payload 自身不同，这些是 build/update 差异，不能反向改写为不同的
device applicability。

### 5.2 HPE 的第二 record 是另一设备/component

HPE record 1 的 bitmap 是 `0x02`，version string 为 `SMA:PG153:`，其 identity
为 PCI `10de:2fad`、subsystem `10de:20f1`、不同 UUID，以及
`APSKU=0x00000004`；它对应 component 1（identifier `0xff02`），不是 GPU NVFW。

这也说明 PLDM wrapper 能在同一板级 package 内对两个 firmware devices 做独立
applicability selection，而不是把整包盲目套给 GPU。

## 6. outer P-384 key fingerprints

### 6.1 可证内容与命名限制

在 main image 前的三个固定 slots，均存在 `0x04 || X[48] || Y[48]` 的 97-byte
uncompressed SEC1 point；每个都能由标准 P-384 parser 成功导入。下表使用其规范
SubjectPublicKeyInfo DER 的 SHA-256 fingerprint：

| slot | FE | ASUS | Dell Pro | HPE Pro |
|---|---|---|---|---|
| prelude `-0x590` | `f05850b61be1e674dfaac419d93e5a6a2e2dc913496a1e4cab12b8a78304b916` | `54a8ffd66109b7a4132c7ee1a3d637f04e99bc6549ccb76a563403da5082444c` | 与 FE 相同 | 与 FE 相同 |
| first `e0` image `+0x70` | `0993d3a1999172ab8993e9e889b0a63cd8ead0b8db23f3ee36629007a92b06d0` | `c5533ad26a0bc73ffadfc061aa2d0b82da90ed6038d5a815d1d2e88cc3db082d` | 与 FE 相同 | 与 FE 相同 |
| second `e0` image `+0x70` | `23b1ded8d007b7ab394d51df29afbb2843028603651a300e60ed9b1545969ced` | `d7dab730ff5de183ccccecff621a1f5a50a2ae454a2afe764e6aa5c4cda56a30` | 与 FE 相同 | 与 FE 相同 |

绝对 key offsets 是 GeForce 的 `0x36870/0x36e70/0x37870`，以及 Pro 的
`0x39870/0x39e70/0x3a870`。

每个 public point 后紧跟 96 bytes，尺寸与 raw P-384 `(r,s)` 相容；这些 96-byte
值在各 build 中都不同。但本次没有闭合精确 signed range/verification，所以只称
为 **signature-shaped adjacent field**，不把它升级为已验证 signature 或 X.509
certificate。四份 raw image 中也没有 PEM/X.509 明文证书。

HPE `.fwpkg` 的 `0x400` footer 是另一层：其自带 SPKI fingerprint 为
`525f6d09a398b8b1f8890ca100e3a849337f0bb28d5c5ff5c9bc72d7331e4c34`，与上表六个
fingerprints 都不同；Dell package 又没有同型 footer。故 outer package key、
raw-NVFW prelude key 和 nested Falcon object 不能混称为一套证书层。

### 6.2 key 与 `FSP_RUN` 的交叉约束

- FE、Dell、HPE 的三把 outer keys 完全相同，但三者提供 GeForce common、Dell
  8D、HPE 9E 三个不同 target byte objects。
- ASUS 使用完全不同的三把 outer keys，却与 FE 共享逐字节相同的
  descriptor 和 immediate region。

所以这些 keys 很适合识别 outer signer/发行 lineage，却不能从当前四样本被解释为
“GeForce key”或“Pro key”，也不能用某个 key fingerprint 唯一预测 nested
`FSP_RUN` bytes。

## 7. 末端 ROM/IMG/BRD metadata 的独立交叉检查

四份文件末端都有明文 `ROM/IMG/BRD/OBD/OEM/BBO/CGPP/PTD` directory。按各自
directory base 对齐取 `0x1dd0` bytes：

- Dell 与 HPE 的该区域 **逐字节完全相同**，SHA-256
  `b72dcd3b47a51a5a8a4f2c04167c9916f4dfa46b52ba5db13c8bc73ffc9ac2c9`；
- 其 `IMG` record 明写 `G153.0210.00.02`，以及连续 identity words
  `2bb5,10de,204e,10de`；
- FE 的 `BRD` record 含 `690-1G144-0030-000` 等 PG144 部件号；ASUS 对应 BRD
  字段主要清零，因此 FE/ASUS 该 directory 不同。

这给出另一个很有用的反例：Dell/HPE 的明文 board/product directory 完全相同，
其 `FSP_RUN` 仍不同；FE/ASUS 的 board directory 与 outer keys 都不同，
`FSP_RUN` 却完全相同。

## 8. 关系矩阵与最终边界

| 配对 | 明文 board/applicability | outer key trio | `FSP_RUN` bytes |
|---|---|---|---|
| FE vs ASUS | 不同（subsystem、board directory） | 不同 | **相同** |
| Dell vs HPE | **相同**（PCI/subsystem/APSKU/UUID、PG153 SKU210、末端 directory） | **相同** | 不同 |
| FE vs Dell/HPE | 不同（2b85 vs 2bb5、PG144 vs PG153） | **相同** | 不同 |

可证结论是：

1. board/SKU binding 真实存在于 outer PCIR/NPDE、ROM directory 和 PLDM
   applicability records；不能说 VBIOS 完全没有零售/板卡身份。
2. 当前 `FSP_RUN` carrier bytes 与这些明文字段、outer key set 都不是简单的一一
   函数。相同 object 可以出现在不同 board/signer metadata 下，相同
   board/applicability 也可以随 firmware revision 携带不同 object。
3. 这只回答**文件相关性**。它没有证明跨板接受、拒绝或可移植性，也没有定位
   BootROM/FSP verifier 的输入集合。若 consumer 同时校验硬件 device/subsystem、
   fuse、rollback/build 或 inner authentication，这些矩阵并不与之矛盾。

对当前研究最稳妥的说法是：**载体外层有明确 SKU/board matching；nested
`FSP_RUN` envelope 本身只显出通用 `2b80` PCIR，但最终是否接受仍可能由更外层和
硬件身份共同决定。**

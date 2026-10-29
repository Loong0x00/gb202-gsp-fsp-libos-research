# GB202 raw NVFW prelude P-384 coverage audit（纯离线、有界）

日期：2026-07-22（Asia/Singapore）

## 范围与安全边界

本支线只读检查项目中已经保存的 FE、ASUS、Dell、HPE 四份 raw ROM/NVFW，
以及已经保存的 `nvflash` 5.877.0 的少数静态 parser 窗口。没有执行任何二进制，
没有访问 GPU、驱动设备节点、PCI/BAR/MMIO、debugfs 或网络，也没有修改固件。

目标被严格限制为主 option-ROM chain 前的三个重复槽：97-byte
`04 || X[48] || Y[48]` 与其后相邻 96 bytes。本文只报告成功验证或有界负结果；
不会把“形状相容”升级为已经证明的字段名。

## 结论先行

1. **FACT：**12 个 97-byte 值（4 样本 × 3 槽）全部能被标准 P-384 parser
   作为合法 uncompressed SEC1 public point 导入。相邻 96 bytes 若按标准
   big-endian `r[48] || s[48]` 解释，则 24 个 scalar 全部落在
   `1..n-1`，所以它们与 raw P-384 signature 的尺寸和值域都相容。
2. **BOUNDED NEGATIVE：**在有结构依据的 image ranges、四种常见 hash、六种
   常见 raw-signature byte ordering 下，12 组均没有 ECDSA verification success。
   因而当前不能把相邻 96 bytes 命名为“对本小镜像某一标准范围的
   ECDSA/SHA-384 签名”。
3. **BOUNDED NEGATIVE：**后两小镜像附近可见多个 48-byte hash-shaped 字段；
   对最直接的 offsets 和目标 hash-table 邻接候选做 P-384/SHA-384 prehashed
   verification，也全部失败。常见 image-range 的 SHA-384 也没有以 raw、整段
   反序或逐 32-bit word 反序形式出现在本小镜像中。当前未建立“这 96 bytes
   直接签某个邻近 48-byte digest”的关系。
4. **FACT：**第二、第三小镜像的 PCIR `codeType=0xe0`。公开 RM 把 `0xe0`
   明确命名为 `NV_BCRT_HASH_INFO_BASE_CODE_TYPE_VBIOS_EXT`；保存的 `nvflash`
   也有独立的 BCRT/VDPA/HAT security-zone hash/signature parser。这个上下文支持
   “它们属于 VBIOS/BCRT authentication metadata carrier”这一层级判断，
   **但已定位窗口没有给 `+0x70/+0xd1` 两字段命名，也没有闭合 P-384 coverage**。

## 1. 三个槽的精确边界

GeForce 两份文件的 NVFW 前另有 `0x1000` bytes，以下均使用 raw-file absolute
offset。Dell/HPE 的 NVFW base 为文件 `0`。

| group | small image range | SEC1 point | adjacent 96B | PCIR evidence |
|---|---|---|---|---|
| FE / ASUS slot 0 | `[0x36800,0x36e00)` (`0x600`) | `[0x36870,0x368d1)` | `[0x368d1,0x36931)` | header `+0x18=0`，无有效 PCIR locator |
| FE / ASUS slot 1 | `[0x36e00,0x37800)` (`0xa00`) | `[0x36e70,0x36ed1)` | `[0x36ed1,0x36f31)` | PCIR `+0x4e4`，length `5*0x200`，code `0xe0` |
| FE / ASUS slot 2 | `[0x37800,0x38000)` (`0x800`) | `[0x37870,0x378d1)` | `[0x378d1,0x37931)` | PCIR `+0x55c`，length `4*0x200`，code `0xe0` |
| Dell / HPE slot 0 | `[0x39800,0x39e00)` (`0x600`) | `[0x39870,0x398d1)` | `[0x398d1,0x39931)` | header `+0x18=0`，无有效 PCIR locator |
| Dell / HPE slot 1 | `[0x39e00,0x3a800)` (`0xa00`) | `[0x39e70,0x39ed1)` | `[0x39ed1,0x39f31)` | PCIR `+0x4e4`，length `5*0x200`，code `0xe0` |
| Dell / HPE slot 2 | `[0x3a800,0x3b000)` (`0x800`) | `[0x3a870,0x3a8d1)` | `[0x3a8d1,0x3a931)` | PCIR `+0x55c`，length `4*0x200`，code `0xe0` |

对应 SEC1/SPKI fingerprints 已在
`parallel/nvfw_sku_binding_compare.md` 复算：FE、Dell、HPE 的同号槽共享同一
public point，ASUS 的三个 point 全部不同。反之，三个同号槽的 adjacent 96B
在 FE、ASUS、Dell、HPE 之间全部不同。这证明它们是 build-sensitive material，
但不能单靠相关性断定签名消息。

## 2. 标准 ECDSA range models：全部未命中

对每个 small image 设 base=`B`、PCIR 声明/相邻边界给出的 size=`S`。将相邻
96 bytes 转成 DER ECDSA signature 后，验证了下列有界 message models：

```text
[B, B+S)                         whole small image
[B+0x1a, B+S)
[B+0x20, B+S)
[B+0x131, B+S)
[B+0x132, B+S)
[B+0x200, B+S)                  conventional 512-byte header exclusion
[B,B+0xd1) || [B+0x131,B+S)    exclude adjacent 96B only
same, but zero-fill 96B
[B,B+0x70) || [B+0x131,B+S)    exclude SEC1 point + adjacent 96B
same, but zero-fill both fields
```

每个 range 均测试 SHA-1、SHA-256、SHA-384、SHA-512。raw 96-byte value 测试：

- standard big-endian `r || s`；
- 每个 48-byte scalar 整段反序；
- 每个 scalar 内逐 32-bit word byte-swap；
- 以上三种再交换 `r/s`。

结果为 **4 样本 × 3 槽全部零成功**。这只是对列出的标准模型的有界排除；它不
排除 signed message 是外部 manifest、离散 ranges、规范化/重排后的结构、由
security-zone table 生成的 transcript，或相邻 96 bytes 根本不是 ECDSA signature。

## 3. 邻近 48-byte fields：没有闭合直接关系

三个小镜像在 `+0x1f2` 后都有结构化 metadata；后两个 `0xe0` images 在
`+0x476`、`+0x4b2` 等位置出现 48-byte high-entropy/hash-shaped values，且
附近可见 raw `u32 0x22`。后续完整 table 映射已证明，target entry 中这个值是
covered-start 相对偏移，不是 Falcon index。为避免把形状误认成语义，本次只做
两个有界检查：

1. 把 small image 内 `+0x209/+0x476/+0x47a/+0x4ae/+0x4b2/+0x4ee`
   的 48-byte windows 依次作为 SHA-384 prehash，使用同槽 point 和相邻 96B
   验证；同时测试 digest raw、整段反序、逐 32-bit word byte-swap，以及上节
   六种 signature ordering。12 槽全部零成功。
2. 对上节十种 message range 重算 SHA-384，并在各自 small image 内搜索 digest
   的 raw、整段反序和逐 32-bit word byte-swap 形式。12 槽全部零命中。

所以当前能说的是：附近确有 48-byte hash-shaped records，BCRT/VDPA parser
也确实处理 hash/security-zone 数据；**不能说 adjacent 96B 已被证明直接签了
其中任何一个，也不能给这些 48B 分配精确 raw-file coverage**。

## 4. 与 `nvflash` / public RM 的职责边界

公开 610 RM 的 `kernel_gsp_vbios_tu102.c` 在遍历 PCI option ROM 时使用：

```c
#define NV_BCRT_HASH_INFO_BASE_CODE_TYPE_VBIOS_BASE 0x00
#define NV_BCRT_HASH_INFO_BASE_CODE_TYPE_VBIOS_EXT  0xE0
```

并以首个 `0xe0` image 计算 expansion-ROM offset。这个正式名字足以说明 slot 1/2
所在 images 是 VBIOS extension/BCRT hash-info carrier，而不是 `FSP_RUN`
descriptor 或 HPE PLDM footer。

保存的 `nvflash` 5.877.0 中，已定位的 cert30 parser
`0x4f64e0..0x4f765e`、HAT-like traverser `0x4bf10c..0x4bf1c9` 和相关
security-zone/VDPA error paths，证明 host 工具存在 BCRT hash/signature verifier。
但这些有界窗口没有把 raw image `+0x70` 映射为 P-384 key、把 `+0xd1`
映射为 signature，也没有给出其 coverage builder。另一路 NVFW locator 只识别/
复制 container (`0x451ed8/0x451eeb`, `0x46620a..0x46623d`)，同样不能提供
字段语义。

因此最稳妥的职责图是：

```text
raw prelude / code-type 0xe0 BCRT hash-info carriers
    ├─ legal P-384 SEC1-shaped points at +0x70       FACT
    ├─ 96-byte raw-signature-shaped values at +0xd1 FACT (shape only)
    └─ nearby 48-byte hash-shaped records            FACT (shape only)
             |
             | exact schema / transcript / coverage UNKNOWN
             v
nvflash BCRT/VDPA/HAT security-zone verifier family  FACT (separate parser path)
```

## 最终有界结论

- 没有获得任何 P-384 verification success，也没有获得相邻 48-byte field 对某一
  标准 small-image range 的 SHA-384 exact match。
- 这批 bytes 的结构位置和 `0xe0` 正式 code-type 将其约束在 outer VBIOS/BCRT
  authentication metadata 层；它们不是 per-`FSP_RUN` relative-offset/SHA-384 entry，
  也不是 HPE package footer。
- 在缺少 exact coverage builder/schema 前，应继续称其为 **legal P-384 public
  point-shaped slots + adjacent raw-signature-shaped data**。任何“已验证签名”、
  “覆盖 whole VBIOS”或“直接保护 `FSP_RUN`”的说法都超出当前证据。

# GB202 target nested image `+0x000..+0x504` 字段图（纯离线、有界）

日期：2026-07-22（Asia/Singapore）

## 范围与安全边界

本支线只读四份已保存镜像中各一个 target nested image 的
`[B,B+0x504)`：

| 样本 | 文件内 `B` |
|---|---:|
| RTX 5090 FE `98.02.2E.00.03` | `0x11ae00` |
| ASUS RTX 5090 `98.02.2E.40.85` | `0x11ae00` |
| Dell RTX PRO 6000 `98.02.8D.00.01` | `0x127c00` |
| HPE RTX PRO 6000 `98.02.9E.00.01` | `0x12c800` |

为验证少量签名候选，只额外枚举同一份已保存文件中以 `55 aa` 开头且其
`+0x70` 能作为 P-384 point 导入的 8 个 key-shaped 槽。没有运行任何 firmware、
`nvflash`、updater 或 MODS；没有访问 GPU、驱动设备节点、PCI/BAR/MMIO、
debugfs 或网络，也没有修改镜像。复核脚本为
`parallel/nested_cert_fieldmap.py`。

## 结论先行

1. **FACT：**`[B,B+0x504)` 不是一团不透明数据，而是具有稳定边界的
   `P-384 point | 96B opaque | metadata | parent SHA-384 | 两张 32-entry 表 |
   两-entry SHA-384 table | PCIR` 结构。
2. **FACT：**认证 hash 链可精确闭合为：

   ```text
   FSP_RUN envelope
       <- SHA-384 in entry 1 (first dword 0x9f)
   ff ff + 0x20-byte PCIR
       <- SHA-384 in entry 0 (first dword 0xc0)
   complete 0x88-byte two-entry table
       <- SHA-384 at B+0x209
   ```

3. **纠错 FACT：**第二条完整 entry 起于 `B+0x4a6`，其首 dword 是
   `0x0000009f`；`B+0x4aa` 才是 `raw0=0x22`。现有笔记中把首 dword 写成
   `0` 是转录错误。`raw0`、length、digest 与精确 coverage 均不受影响。
4. **FACT：**`B+0x201` 的 little-endian `u32` 精确等于
   `0x504 + entry1.length`，即 FSP_RUN envelope 结束相对偏移；PCIR 声明的
   image size 又恒等于该值加 `0xac`。
5. **INFERENCE（强，但尚非验签事实）：**`B+0xd1` 的 96 bytes 在形状和上下文
   上更像 raw P-384 ECDSA signature（`r[48] || s[48]`）而不是两个普通 digest
   或另一个 P-384 point；但本次以及已有有界候选均没有产生一次 ECDSA verify
   success，所以仍应称作 **signature-shaped field**。
6. **BOUNDED NEGATIVE：**`B+0x209` parent digest 没有以“直接 prehash”或下述
   常见 raw-contiguous transcript 被该 96B 和同镜像内任一候选 point 验证。
   最合证据的下一层模型是私有 manifest/security-zone canonicalization，或
   “相邻 point 是 subject key、96B 由未定位 parent key 签”的证书式模型；两者
   都还只是可能性。

## 1. 跨样本字段/边界图

“分组”表示整段逐字节相等，而不是只比较 hash 前缀。

| 相对范围 | 长度 | 机械可确认的内容 | 四样本分组 |
|---|---:|---|---|
| `000..070` | `0x70` | `55 aa` ROM header + padding | 全同 |
| `070..0d1` | `0x61` | 合法 SEC1 uncompressed P-384 point | FE=Dell=HPE；ASUS 独立 |
| `0d1..131` | `0x60` | 96-byte high-entropy/signature-shaped field | 四者全不同 |
| `131..1f2` | `0xc1` | 全 `ff` padding | 全同 |
| `1f2..209` | `0x17` | pre-parent metadata；含 `+0x201 u32 object_end` | 四者全不同 |
| `209..239` | `0x30` | `SHA-384(B+45a..B+4e2)` | FE=ASUS；Dell、HPE 各自不同 |
| `239..270` | `0x37` | identity/build-shaped metadata | 四者全不同 |
| `270..276` | `0x06` | header；末两 bytes 为 `0x0a,0x20` | FE=Dell=HPE；ASUS 独立 |
| `276..3b6` | `0x140` | 恰好 `32 * 0x0a` bytes | 全同 |
| `3b6..3ba` | `0x04` | header；末两 bytes 为 `0x05,0x20` | 全同 |
| `3ba..45a` | `0xa0` | 恰好 `32 * 5` bytes | FE=ASUS=Dell；HPE 仅 `+0x3c0` 不同 |
| `45a..46a` | `0x10` | hash table header | 全同 |
| `46a..476` | `0x0c` | entry 0 header | 全同 |
| `476..4a6` | `0x30` | entry 0 SHA-384 | FE=ASUS；Dell、HPE 各自不同 |
| `4a6..4b2` | `0x0c` | entry 1 header | FE=ASUS；Dell、HPE 各自不同（length） |
| `4b2..4e2` | `0x30` | entry 1 SHA-384 | FE=ASUS；Dell、HPE 各自不同 |
| `4e2..504` | `0x22` | `ff ff || 0x20-byte PCIR` | FE=ASUS；Dell、HPE 各自不同（image length） |

两个重复表的边界不是凭视觉猜的：

```text
B+0x270: 6-byte header ending 0x0a,0x20
         followed by exactly 32 * 0x0a bytes -> B+0x3b6

B+0x3b6: 4-byte header ending 0x05,0x20
         followed by exactly 32 * 5 bytes -> B+0x45a
```

这些字节关系是 FACT；在没有私有格式定义前，本文不把两张表命名为某个正式
BCRT/VDPA/HAT struct。

### 1.1 可见的 identity/build 差异

`B+0x239..+0x270` 可进一步机械分为：

```text
+0x239..+0x242  06 + 8 zero bytes                         四份固定
+0x242..+0x252  16-byte maker-shaped field                nvidia / asus
+0x252..+0x269  23-byte board/identity-shaped field        ASUS 独立
+0x269..+0x270  7 ASCII bytes                              四份唯一
```

最后 7 bytes 分别为 `036971B`、`656581B`、`573991B`、`895202B`。这只能证明
它们是 build-sensitive ASCII metadata；没有格式定义时不进一步命名。

## 2. 三层 exact SHA-384 coverage

设 table end `T=B+0x4e2`，descriptor `D=B+0x504=T+0x22`。四份样本都满足：

```text
entry 0 @ B+0x46a:
    first_u32=0xc0, raw0=0, length=0x22
    digest @ B+0x476 = SHA-384(file[T:T+0x22])

entry 1 @ B+0x4a6:
    first_u32=0x9f, raw0=0x22, length=L
    digest @ B+0x4b2 = SHA-384(file[D:D+L])

parent @ B+0x209:
    SHA-384(file[B+0x45a:B+0x4e2])
```

table header 为：

```text
u32 3 | u32 0x10 | u32 2 | u32 0x2b80
```

因此 parent digest 覆盖 header 和两条完整 `0x3c`-byte entries，包括两条 entry
的首字段、offset、length 和 digest，而不是只覆盖两个 digest。

| 样本 | entry 1 `L` | `u32 @ +0x201` | PCIR image size | 固定余量 |
|---|---:|---:|---:|---:|
| FE | `0x29450` | `0x29954` | `0x29a00` | `0xac` |
| ASUS | `0x29450` | `0x29954` | `0x29a00` | `0xac` |
| Dell | `0x36c50` | `0x37154` | `0x37200` | `0xac` |
| HPE | `0x37050` | `0x37554` | `0x37600` | `0xac` |

每行均满足：

```text
u32(B+0x201) = 0x504 + L
PCIR_image_size = u32(B+0x201) + 0xac
```

这把 pre-parent metadata、FSP_RUN envelope length 和 PCIR image boundary 连接成
了一个新的 exact relation；`+0x201` 的正式字段名仍未知。

## 3. 96 bytes 更像什么

### FACT

- 四个 `B+0x70..+0xd1` 都能被标准 P-384 parser 作为 SEC1 uncompressed point
  导入。该事实的随机巧合概率可忽略。
- 若把相邻 96B 拆成 standard big-endian `r[48] || s[48]`，四份的 8 个 scalar
  全部位于 P-384 order 的 `1..n-1`。
- 若在其前补 `04`、把整段 96B 当作 `X[48] || Y[48]`，四份都不是合法 P-384
  point；所以它不像第二把省略前缀的 raw public key。
- 以本字段图的 18 个边界形成所有 contiguous `[start,end)` 组合，对其计算
  SHA-384；96B 的前、后 48-byte half 在四份样本中均为零命中。因此没有证据
  把它解释成“两条对相邻结构字段的普通 SHA-384 digest”。
- 四份 96B 全部不同；其中两个 `s` 高于 `n/2`、两个低于 `n/2`，没有统一
  low-S canonicalization。ECDSA 并不普遍要求 low-S，所以这不排除签名。

### INFERENCE

`合法 P-384 point` 后紧邻 `2 * 48 bytes`，再结合 nvflash 中已经独立确认存在的
BCRT/security-zone signature verifier vocabulary，令“raw P-384 ECDSA
signature-shaped field”成为明显强于“两个普通 digest”或“第二把 point”的解释。
但形状不是验签；在 exact signed serialization/key ownership 未闭合前，仍不能把
它直接标成“已验证的 ECDSA signature”。

## 4. Parent digest 如何进入 transcript：有界验证与剩余模型

对每份 target 的 96B，本次只测试 SHA-384 驱动、且由上述字段边界直接导出的
候选：

- `parent` 既作为 raw message，也作为 prehashed SHA-384；
- `pre-parent metadata || parent`；
- `parent || identity`、`pre-parent metadata || parent || identity`；
- 从 `+0x1f2` 或 `+0x209` 连续到 `+0x45a/+0x4e2/+0x504`；
- `parent || whole hash table` 及 `prefix || parent || whole hash table`；
- PCIR 声明的完整 nested image；将 96B 或 point+96B zero/remove 的四个变体。

每个候选使用同一保存文件内 8 个 `55 aa`-relative、可合法导入的 P-384 points，
并测试 raw signature 的 6 种常见 `r/s`、整段反序和逐 32-bit word byte-swap
组合。每样本共 `864` 次 verify，四份总计 `3456` 次，**零成功**。

这是严格限定候选集的 bounded negative，不是“签名不存在”的证明。它具体排除
的是“96B 在这些常见 raw transcript/ordering 下，由镜像中这些显式 point 之一
直接验证”的简单模型。

跨样本关系还提供两个约束：

- FE 与 ASUS 的 FSP envelope、两-entry table 和 `+0x209` parent digest 完全相同，
  但 point、96B、identity metadata 不同；所以 96B 不是 parent digest bytes 的
  简单复制或普通确定性 digest。不同 signing key 或随机 ECDSA nonce 仍可产生
  不同签名，因此不能只凭这一点排除“签 parent”。
- FE、Dell、HPE 的 adjacent point 相同，但 parent digest 和 96B 都不同；这与
  “同一 key 对不同 build transcript 签名”相容，却仍不是验证证明。

在当前证据下，parent digest 进入下一层最合理但未证明的两类方式是：

1. **canonical manifest/security-zone transcript：**parser 按私有 schema 从多个
   非连续 range/表项抽取字段，或在签名前做归一化；`+0x270` 与 `+0x3b6` 的两张
   32-entry 表可能参与 range/policy 描述，但尚未建立 parser binding。
2. **certificate-style chaining：**`+0x70` 是 subject public key，紧邻 96B 是由
   未定位 parent/root key 产生的 certificate signature；此时用 adjacent key
   自验本来就会失败。当前没有找到 exact parent-key/transcript，故只是模型。

不能在两者之间做事实性选择。更不能从这些 bytes 推导出修改后会被 secure loader
接受。

## 5. 最终 FACT / 有界负结论

### FACT

- `+0x70` 是合法 P-384 SEC1 point；`+0xd1` 是 96-byte signature-shaped data。
- `+0x201` 精确编码 FSP envelope end，PCIR image end 再加固定 `0xac`。
- `+0x209` 精确 hash 完整两-entry table；两条 entry 又分别精确 hash PCIR 前缀
  和完整 FSP_RUN envelope。
- entry 1 首 dword 是 `0x9f`，不是 `0`；`raw0=0x22` 位于其后。
- 两张 32-entry 定长表的边界和跨样本差异可逐字节复算。

### BOUNDED NEGATIVE

- 96B 不是合法 raw P-384 point，也不是本字段图任一 boundary-aligned contiguous
  range 的两条直接 SHA-384 digest。
- 对明确列出的 3456 次 P-384/SHA-384 transcript/key/ordering 组合，零验签成功。
- 因而尚未闭合 `+0x209 parent digest -> signature -> device-pinned root`；目前只
  闭合到 parent digest 本身。

最终答案：**96B 很像签名，但还没有被证明“是谁用哪把 key 对哪段 transcript
签的”。Parent digest 很可能进入私有 canonical manifest 或证书链，而不是简单对
一段连续 raw bytes 直接签名。**

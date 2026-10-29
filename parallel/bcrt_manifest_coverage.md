# GB202 `FSP_RUN` hash-table / BCRT trust coverage（纯静态、有界）

日期：2026-07-22（Asia/Singapore）

## 范围与安全边界

本支线只读取以下四份已经保存在本地的 raw ROM/NVFW，以及保存的
`nvflash` 5.877.0 的少量已定位 parser 窗口：

- RTX 5090 FE `98.02.2E.00.03`；
- ASUS RTX 5090 `98.02.2E.40.85`；
- Dell RTX PRO 6000 `98.02.8D.00.01`；
- HPE RTX PRO 6000 `98.02.9E.00.01`。

没有运行 `nvflash`、updater、MODS 或任何 firmware；没有访问 GPU、驱动设备
节点、PCI/BAR/MMIO、debugfs 或网络；没有修改任何镜像。对 `nvflash` 只查看了
已有的 BCRT cert20/cert30、VDPA/HAT 有界窗口，没有做全程序反编译。

## 结论先行

1. **FACT：`FSP_RUN` envelope 的 SHA-384 record 本身又被一层 SHA-384 覆盖。**
   每个 target nested PCI image 中有一个 `0x88`-byte、两 entry 的 hash table；
   第二条 entry hash 完整 v6 envelope，位于 image `+0x209` 的 48-byte digest
   又精确等于 `SHA-384(整个 0x88-byte table)`。
2. **FACT：此前把 record 首字段 `0x22` 直接称为 “index 34” 是错误命名。**
   机械关系表明它是相对 table end 的 covered-start offset：`0x22` 正好跳过
   `ff ff + 0x20-byte PCIR`。Falcon table 的 entry index 34 是另一张表中把
   descriptor 指向同一地址的独立事实，数值恰好同为十进制 34。
3. **UNKNOWN：链仍没有闭合到一个受设备固定信任的 root。** 邻近存在合法
   P-384 point 和 96-byte signature-shaped 字段，`nvflash` 也确有 BCRT/
   security-zone signature verifier；但当前有界窗口没有证明该 signature 的
   精确 signed serialization，也没有证明哪把 key 被 GPU BootROM/FSP pin 为 root。

因此当前最严格的 trust chain 是：

```text
FSP_RUN descriptor + immediate bytes
        <- exact SHA-384 entry                         FACT
two-entry hash table（也含 PCIR 的独立 SHA-384 entry）
        <- exact SHA-384 at nested-image +0x209       FACT
adjacent certificate/signature-shaped material
        <- exact signed range / algorithm mapping     UNKNOWN
device-pinned NVIDIA root / BootROM acceptance
        <- root identity and binding                   UNKNOWN
```

## 1. Target nested image 的共同布局

四个样本的 target descriptor 都位于一个结构同形的 nested PCI image 的
`base+0x504`；目标 hash entry 所在的两-entry table 位于
`[base+0x45a, base+0x4e2)`：

| 样本 | nested base | table | target entry（完整） | descriptor `D` |
|---|---:|---|---:|---:|
| FE | `0x11ae00` | `[0x11b25a,0x11b2e2)` | `0x11b2a6` | `0x11b304` |
| ASUS | `0x11ae00` | `[0x11b25a,0x11b2e2)` | `0x11b2a6` | `0x11b304` |
| Dell | `0x127c00` | `[0x12805a,0x1280e2)` | `0x1280a6` | `0x128104` |
| HPE | `0x12c800` | `[0x12cc5a,0x12cce2)` | `0x12cca6` | `0x12cd04` |

table 的 raw header 是：

```text
u32 3 | u32 0x10 | u32 2 | u32 0x2b80
```

总长满足 `0x10 + 2 * 0x3c = 0x88`。每条 `0x3c`-byte entry 可以机械拆为：

```text
u32 raw_first | u32 raw0 | u32 length | 48-byte SHA-384
```

本文不把 `raw_first` 升级成未由格式定义证明的私有枚举名；`raw0` 的 covered-start
语义则由两条 entry 的 hash 关系共同约束。

## 2. `raw0=0x22` 不是 Falcon index

令 table end 为 `T = base+0x4e2`。四个样本都同时满足：

```text
entry 0: raw_first=0xc0, raw0=0,    length=0x22
         digest = SHA-384(file[T : T+0x22])

entry 1: raw_first=0x9f, raw0=0x22, length=L
         digest = SHA-384(file[T+0x22 : T+0x22+L])
```

`file[T:T+0x22]` 逐字节是：

```text
ff ff || 0x20-byte PCIR
```

而 `T+0x22` 精确等于 descriptor `D`。因此第二条 entry 的 `raw0=0x22`
最强、无需私有字段名的解释是“相对 table end 的 covered-start offset”。此前报告
把第二条 entry 从 `raw0` 字段开始截成 56 bytes，恰好得到
`raw0 | length | digest`；这个切片关系是对的，但把 `raw0` 称为 index 是错的。

Falcon table 的确另有 **entry index 34** 指向 `D`。正确关联应写成：

```text
Falcon table entry 34 -> descriptor D
hash-table entry raw0=0x22 -> covered_start D
```

两者通过同一个地址 `D` 关联，不能因为 `0x22 == 34` 就把两个字段合并成同一枚举。

## 3. Envelope coverage：四样本精确复算

第二条 entry 的 `L` 和 digest 结果为：

| 样本 | `raw0` | `L` | covered range | stored/recomputed SHA-384 |
|---|---:|---:|---|---|
| FE | `0x22` | `0x29450` | `[0x11b304,0x144754)` | `a45fe2108eb71551a4c5d11f7b12309f4e2de123a6aa28e6c56f1897993f8b51af4d954b31a05752d0c461386421eef1` |
| ASUS | `0x22` | `0x29450` | `[0x11b304,0x144754)` | 同 FE |
| Dell | `0x22` | `0x36c50` | `[0x128104,0x15ed54)` | `537a5bb53bdbb2b891f73e629284716b82d217cb2377ac2f00e1e8b704a52fcae8dd11f22649fc582aa2c1e4f71ac12f` |
| HPE | `0x22` | `0x37050` | `[0x12cd04,0x163d54)` | `719e77ec59e03b2d794a33a7ab6dc4a440e48d42b8f44fd6708d5fc3cbccf4a726d465de44d9288a07c950c10f36c03d` |

这些 `L` 又分别等于 `0x50-byte v6 descriptor + descriptor.word1`。因此
“完整 on-disk v6 envelope 受该 entry 的 SHA-384 覆盖”是 FACT；这仍不等于
“该 digest 已经由设备信任的 root 签名”。

## 4. Digest record 本身的上一层 coverage

最关键的新闭合是：四份样本均满足

```text
file[base+0x209 : base+0x239]
    == SHA-384(file[base+0x45a : base+0x4e2])
```

后一个范围正是完整 table header 加两条完整 `0x3c`-byte entries；因此它包含
target entry 的 `raw_first/raw0/length/digest` 全部 60 bytes，而不是只覆盖 digest。

| 样本 | parent digest slot | SHA-384(two-entry table) |
|---|---:|---|
| FE | `0x11b009` | `e7f88ce9df6fd1ada960d85da9c1bc59e22e5a469258708e2b1d365a1c14dc7bb9515cac5b1591f690d6bf261ec02298` |
| ASUS | `0x11b009` | 同 FE |
| Dell | `0x127e09` | `b824f0aa24bff9d94849b937750e878b394a59d9255c98ace324f89bf75a0390480132a73740d701a09288433417f881` |
| HPE | `0x12ca09` | `503284859b86f08a38e98897b7a07349df6ea03a97469b016080fa38b78bc0cab828f708c587277635376c083a821855` |

这排除了“修改 target digest/length 后只需让 payload hash 自洽、而没有上一层
完整性关系”的简单模型：磁盘格式中至少还要满足这个 parent SHA-384。

## 5. 与 BCRT / VDPA / HAT parser 能闭合到哪里

保存的 `nvflash` 5.877.0 中，有界静态窗口能证明：

- `0x4bf10c..0x4bf1c9` 存在 HAT-like record traverser；
- cert20/cert30 builder 经 image virtual methods 取 BIT/VDPA 信息，并处理多种
  location type；
- binary 明确包含 `BCRT2X_SECURITYZONE_SIGNATURE_INVALID`、
  `BCRT2X_SECURITYZONE_SIG_NOT_FOUND`、
  `BCRT2X_VDPA_ENTRY_VERIFY_HASH_MISMATCH` 等 verifier 错误路径。

上述 vocabulary 与这里观察到的“header + 多 entry + hash + 上层 digest”结构相容，
但当前有界窗口**没有**把一个具体 virtual-method return value 机械落到 GB202
target image 的 `base+0x45a`。所以本文把它称为“两-entry hash table”；
“它就是 cert30 的某个正式 VDPA/security-zone struct”仍是 INFERENCE，而不是 FACT。

## 6. 为什么还不能说 trust root 已闭合

每个 target nested image 还具有：

- `base+0x70` 的 97-byte material，可作为合法 P-384 uncompressed point 导入；
- 紧随其后的 `base+0xd1..base+0x131` 96-byte signature-shaped material。

FE、Dell、HPE 的 target-image raw point SHA-256 相同，为
`706056cf3f3887028f08fc1aed15e6e4a28cf54ecfb83cb7be12d8ccd4a630e7`；
ASUS 为
`383fea5fe830e3f801cc6e734506116e4c54f60efc43bd56d9a0ca83c57e08b6`。
四份 96-byte adjacent fields 均不同。

但这些事实仍没有给出：

1. 96 bytes 的正式算法/端序/encoding；
2. 精确 signed message 是否包含 `base+0x209` digest、以何种 serialization 包含；
3. adjacent point 是 signer、subject、intermediate，还是仅供另一方向验证；
4. BootROM/FSP pin 的 root key fingerprint 和 rollback/lifecycle policy。

对 adjacent/同镜像链中的 P-384 points、常见连续边界、SHA-384 与 prehashed
SHA-384 组合做了有界验证，没有得到可复现的 ECDSA match。这只能作为
“当前候选 signed-range 未闭合”的 negative；不能据此声称签名无效，私有结构可能
有未解析的 canonicalization、额外字段或不同 verifier ownership。

同样，机械扫描出的同型 `raw0|length|SHA-384` exact relationships 中，没有另一条
covered range 包含 target image 的 `base+0x209` digest slot。因而同一种简单
hash-record 关系只闭合到 `+0x209`，再往上必须依赖尚未映射的 certificate/
signature policy。

## 7. FACT / INFERENCE / UNKNOWN

### FACT

- target table 的精确边界是 `base+0x45a..base+0x4e2`，其形状为
  `0x10 + 2*0x3c`。
- entry 0 精确 hash `ff ff + PCIR`；entry 1 精确 hash v6 envelope。
- entry 1 的 `raw0=0x22` 是 covered-start relative offset；不是 Falcon index。
- Falcon table entry index 34 独立地指向同一 descriptor 地址。
- `base+0x209` 的 SHA-384 精确覆盖整个两-entry table，因而覆盖 target digest
  record 本身。
- `nvflash` 中存在 BCRT/VDPA/HAT/security-zone hash/signature verifier；target
  nested image 中存在合法 P-384 point 与 signature-shaped adjacent bytes。

### INFERENCE

- 这个两-entry table 很可能属于 BCRT/VDPA/security-zone 认证内部块；它的布局、
  device word `0x2b80`、上层 digest 和 `nvflash` vocabulary 都支持这一模型。
- `base+0x209` digest 很可能再进入 certificate signature 检查，但当前尚无精确
  signed-range/parser binding，不能升级为 FACT。

### UNKNOWN

- `base+0x209` digest 到 96-byte adjacent field 的正式签名 schema 与消息范围；
- adjacent P-384 point 在链中的 signer/subject/root 角色；
- device-pinned root identity，以及 BootROM/FSP 的最终 key、rollback、SKU/fuse、
  lifecycle acceptance policy；
- `raw_first=0xc0/0x9f` 的正式私有语义；
- 保存的 host `nvflash` verifier 与 device secure-loader verifier 是否使用完全相同
  的 GB202 schema/policy。

最终答案是：**目标 SHA-384 record 确实又被一层 SHA-384 覆盖，coverage map 已从
`FSP_RUN` bytes 闭合到 nested image 的 `+0x209` digest；但尚未闭合到可验证的
certificate signature，更没有闭合到设备固定信任根。**

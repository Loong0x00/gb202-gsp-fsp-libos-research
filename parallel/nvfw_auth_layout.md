# GB202 NVFW / BCRT / Falcon-v6 认证布局（纯静态、有界）

日期：2026-07-22（Asia/Singapore）

## 范围与安全边界

本支线只读检查项目中已经保存的 FE、ASUS、Dell、HPE 四份 raw ROM/NVFW，
以及保存的 `nvflash` 5.877.0 中少数已定位的 parser 窗口。没有执行
`nvflash`、updater 或 MODS；没有访问 GPU、驱动设备节点、PCI/BAR/MMIO、
debugfs、网络，也没有对固件做任何修改。

本文把四层严格分开：

1. 可选的 PLDM/HPE 外层包认证；
2. NVFW 外层容器及 VBIOS 的 BCRT/VDPA/HAT 认证结构；
3. 单个 Falcon-v6 `FSP_RUN` 对象附近的 hash 记录；
4. secure loader 是否接受并运行 Falcon-v6 对象的内部认证策略。

## 结论先行

- **FACT：**四份样本都具有稳定的 NVFW 外层形状：`NVFW`/空白前缀、
  `0xa00` bytes 高熵 opaque 区、`0x200` bytes `ff` padding，然后才是主体。
  保存的 `nvflash` 能定位/复制这个容器，但当前有界代码窗口没有给
  `0xa00` 区命名或证明其覆盖范围。
- **FACT：**目标 nested image 中存在一个两-entry hash table；第二条为
  `raw_first=0x9f | raw0=0x22 | exact envelope length | SHA-384(envelope)`。四份
  样本的 stored digest 均与重算结果逐字节一致。`raw0=0x22` 是相对 table end
  的 covered-start offset，不是 Falcon index 34；此前命名已撤回。
- **FACT：**nested image `+0x209` 的另一条 SHA-384 又精确覆盖整个两-entry
  table，因此 target 的 type/offset/length/digest 全部还有上一层完整性关系。
- **FACT：**该 SHA-384 只证明一个 digest 关系；尚未证明谁签名/信任这个 digest，
  也没有证明它本身就是最终 secure-loader acceptance 条件。
- **FACT：**`nvflash` 中另有 BCRT cert20/cert30、VDPA、HAT、security-zone
  signature/hash verifier。它与 Falcon descriptor classifier 是不同代码路径；
  不能把 BCRT、v6 descriptor 尾部和 HPE package footer 混称为同一个签名。
- **UNKNOWN：**`+0x209` parent digest 怎样进入邻近 96-byte signature-shaped
  字段、由哪个 pinned root 验证，以及 FSP/SEC2/BootFSM 最终在哪一阶段执行
  v6 object acceptance，本次证据尚未闭合。

## 1. 样本身份

| 样本 | 文件大小 | SHA-256 | NVFW base |
|---|---:|---|---:|
| RTX 5090 FE | 1,961,983 | `a966aca23518708e44c961af865cccfdfabebc9d0cd06a8e29577a0bd82dc5eb` | `0x1000` |
| ASUS RTX 5090 | 1,961,983 | `eeb68ef4ce8b70d2f72aa1738b04e89d912c3af977722959e7ca60c1195f1111` | `0x1000` |
| Dell RTX PRO 6000 NVFW | 1,908,176 | `8658724061087279f59ca3a0d8ce443cb4ca52db2543c64723a3cea632a29b59` | `0` |
| HPE RTX PRO 6000 NVFW | 1,908,176 | `98c52f80e937907c4203280824bbef6bb17439c900edc74532072780611c0fe5` | `0` |

FE/ASUS 文件在 NVFW 前多一个 `0x1000`-byte option-ROM image；以下 NVFW
外层 offset 均相对 `NVFW base` 表示。

## 2. NVFW 外层：可复现的事实与边界

四份文件的固定形状为：

```text
NVFW +0x0000 .. +0x03ff   "NVFW" 后为 ff；四份完全相同
     +0x0400 .. +0x0dff   0xa00-byte opaque/high-entropy material
     +0x0e00 .. +0x0fff   0x200 bytes ff
     +0x1000 ..            VBIOS/NVFW body
```

| range | FE | ASUS | Dell | HPE |
|---|---|---|---|---|
| `+0x000..+0x400` SHA-256 | `80a31f…e945` | 同 FE | 同 FE | 同 FE |
| `+0x400..+0xe00` SHA-256 | `0513948fd15a5c2f926daef541dd8f4bfd75eb681c67532425a11e34c4623835` | 同 FE | `e97dc48127862dfbcc9f418dd4a0267a62f54c8cf3ae05d30596d94ef61ae2d4` | `be1bcf4c49d8a223c1001c1f29b62e158ced550bab69f4129424e2a4652a1a36` |
| `+0xe00..+0x1000` SHA-256 | `9f56cd…3a5d` | 同 FE | 同 FE | 同 FE |

opaque 区 Shannon entropy 为约 `7.82–7.84 bits/byte`。FE 与 ASUS 的主体
存在差异，但二者 `0xa00` 区逐字节相同。因此，除非假设密码学碰撞或另有间接
索引，这个区域**不可能单独是覆盖 post-`+0x1000` 主体每一个 byte 的
content-specific digest/signature**。

对 whole file、`body[+0x1000:EOF]`、option-ROM chain、目标 FSP descriptor、
目标 FSP immediate region 和完整 FSP envelope 的 SHA-256/SHA-384 做 raw-byte
搜索，均没有在该 `0xa00` 区找到直接 digest 值。这只是有界 negative；该区仍
可能包含证书、公钥、加密/签名对象或间接 metadata，但当前不能可靠命名。

保存的 `nvflash` 中：

- `0x46620a..0x46623d` 以 4 KiB 步长搜索 `NVFW`，命中后保存 offset；
- `0x45d317` 在 PLDM component 起点识别 `NVFW`；
- `0x451ed8/0x451eeb` 在另一路检查 component-relative `+0x400/+0x1000`。

这些是**定位/识别/复制**证据，不是 `0xa00` 内容的字段定义或验签证据。

## 3. `FSP_RUN` v6 的两-entry SHA-384 table

设 target nested PCI image 起点为 `B`、hash table end 为 `T=B+0x4e2`、v6
descriptor 起点为 `D=B+0x504=T+0x22`。四份样本都满足下列精确布局：

```text
B+0x45a  table header: u32 3 | u32 0x10 | u32 2 | u32 0x2b80
B+0x46a  entry 0: raw_first=0xc0 | raw0=0 | length=0x22 |
           SHA-384(file[T:T+0x22])
B+0x4a6  entry 1: raw_first=0x9f | raw0=0x22 | length=0x50+word1 |
           SHA-384(file[D:D+0x50+word1])
T=B+0x4e2  ff ff || 0x20-byte PCIR
D=B+0x504  Falcon-v6 descriptor: 0d 06 50 00 ...
```

table 总长为 `0x10 + 2*0x3c = 0x88`；每条 entry 是
`u32 raw_first | u32 raw0 | u32 length | 48-byte digest`。`raw_first` 的私有
语义未公开；旧分析从 entry 1 的
`raw0` 开始截取了 56 bytes，byte relation 没错，但把 `0x22` 称为 index 是错的。

逐样本复算结果：

| 样本 | `D` | `word1` | covered envelope | `raw0` field start | stored/recomputed SHA-384 |
|---|---:|---:|---:|---:|---|
| FE | `0x11b304` | `0x29400` | `0x29450` | `0x11b2aa` | `a45fe2108eb71551a4c5d11f7b12309f4e2de123a6aa28e6c56f1897993f8b51af4d954b31a05752d0c461386421eef1` |
| ASUS | `0x11b304` | `0x29400` | `0x29450` | `0x11b2aa` | 同 FE |
| Dell | `0x128104` | `0x36c00` | `0x36c50` | `0x1280aa` | `537a5bb53bdbb2b891f73e629284716b82d217cb2377ac2f00e1e8b704a52fcae8dd11f22649fc582aa2c1e4f71ac12f` |
| HPE | `0x12cd04` | `0x37000` | `0x37050` | `0x12ccaa` | `719e77ec59e03b2d794a33a7ab6dc4a440e48d42b8f44fd6708d5fc3cbccf4a726d465de44d9288a07c950c10f36c03d` |

四次均为 exact match；entry 的 length 也四次精确等于 descriptor `0x50`
加 `word1`。Falcon object inventory 中 entry index 34 另行指向同一 `D`；
`raw0=0x22` 与十进制 34 相同仅为数值巧合。完整 35-entry 交叉扫描还证明，Falcon
index 22 的 descriptor-start entry 同样使用 `raw0=0x22`，直接排除了 index 解释。

这里可以安全地说：**磁盘上的完整 v6 envelope（descriptor + immediate bytes）
受一条 SHA-384 hash-table entry 覆盖。**不能仅凭这一步说它已经由 NVIDIA root
签名；digest 没有密钥，只有当更上层认证结构保护这条 table 时才形成完整信任链。

这一步现在又闭合了一层。四份样本均严格满足：

```text
file[B+0x209:B+0x239] == SHA-384(file[B+0x45a:B+0x4e2])
```

右侧范围正是完整 `0x88`-byte table，包含 header、两条 entry，以及 target 的
`raw_first/raw0/length/digest`。所以修改 envelope 后即使重算 target digest，仍会
破坏 `B+0x209` 的 parent digest。尚未证明的是该 parent digest 的正式签名
serialization、邻近 P-384/96-byte material 的角色和设备 pinned root。

另一个重要区分：descriptor 本身最后 28 bytes 仍是 opaque；上述 digest 位于
descriptor 之前，不应把二者误当成同一字段，也不能未经格式定义把 descriptor
尾部命名为 IV/tag/signature。

## 4. BCRT / VDPA / HAT 是独立的 VBIOS 认证路径

保存的 `nvflash` 5.877.0 含有明确的错误和 verifier 路径：

```text
BCRT cert20 / cert30 BIT or VDPA errors
BCRT2X_SECURITYZONE_SIGNATURE_INVALID
BCRT2X_VDPA_ENTRY_VERIFY_HASH_MISMATCH
certificate algorithm unsupported
security zone signature not found
```

`0x4f64e0..0x4f765e` 的 cert30 有界 parser：

- 经对象 virtual method `+0x4f0` 取得 BIT table；
- 处理内部 `0x30`/`0x50`-byte records；
- 接受至少 `1/2/3` 三种 VDPA location type；
- 把多组 offset/size 交给 hash/signature helper。

另一个 HAT-like traverser（`0x4bf10c..0x4bf1c9`）从 virtual method `+0x6c0`
取得 base，以 record `+0x0c` dword 前进，用 `+0x18` bit 1 判断终止，并把记录数
限制为 `0x32`。这些代码足以证明 BCRT/HAT/VDPA security-zone verifier 存在，
但本次窗口没有把具体 parser virtual-method return value 机械落到上述 nested-image
table；表内与 parent digest 的 byte coverage 已独立闭合，正式 BCRT struct 名仍未知。

四份 raw ROM/NVFW 中搜索常见 DER X.509 OID（RSA、SHA256-with-RSA、EC public
key、CN/C）均为零命中。因而没有证据表明这些文件内嵌了常规 DER X.509 chain；
`nvflash` 的 X.509/BCRT 功能可能服务其他格式/路径。`BIOS Certificate Check
Failed!!!` 字符串本身也不是证书 locator。

## 5. Falcon-v6 object authentication 仍是另一道边界

目标 descriptor 的 `word0 = 0x0050060d`，即 flags `0x0d`、version `6`、header
size `0x50`。保存的 `nvflash` classifier `0x7dde66` 没有 v6 case；这组 bytes
落入旧 GFW-v1 catch-all，按旧字段解释会产生明显不合理结果。未找到显式
`version 6 + size 0x50` body parser。

因此当前静态证据支持以下职责分离：

```text
P-384 point + adjacent 96-byte signature-shaped material
        | exact signed transcript / pinned root: UNKNOWN
        v
parent SHA-384 at nested image +0x209
        | exact hash of complete 0x88-byte table: FACT
        v
raw0/length/SHA-384(v6 envelope) table entry
        | exact byte-integrity relation: FACT
        v
Falcon-v6 descriptor + immediate object
        | decrypt/auth/load policy: UNKNOWN
        v
FSP/secure-loader execution
```

host 能搬运 opaque v6 object，不等于 host 理解、解密或最终授权它。

## 6. PLDM/HPE footer 不能与 inner NVFW 混称

Dell `.fwpkg` 是 `0xcf`-byte PLDM header 加完整 Dell NVFW，组件末端即 EOF，
没有 HPE 型 footer。HPE `.fwpkg` 则是 `0x14d`-byte header、完整 NVFW、第二
firmware component，再加 `0x400` footer。

HPE footer 中的 P-384 SPKI 与 DER ECDSA signature 对 package
`[0:0x219fb5)` 做 ECDSA P-384/SHA-384 verification 成功；精确 signed-data
SHA-384 为：

```text
976ec211f17def7725a81053b9e7f031ec0f3d9ab0448ddc78600d94dc5816ccad3356f063d4bb76506efc1a18672b6c
```

这证明 HPE 外包 byte sequence 自洽，但 key 随包携带、没有本地 pinned root/X.509
chain，所以 publisher identity 未闭合。Dell 没有同型 footer，也证明该 footer
不是所有 GB202 inner NVFW/FSP object 被设备接受的普适必要条件。

## 7. FACT / INFERENCE / UNKNOWN

### FACT

- NVFW 外层固定 prefix/opaque/padding 边界和上述 hashes 可逐字节复算。
- 四份目标 v6 envelope 都由两-entry table 中的 relative-offset/length/SHA-384
  entry 精确覆盖；整个 table 又由 nested image `+0x209` SHA-384 精确覆盖。
- `nvflash` 存在 BCRT cert20/cert30、VDPA、HAT、security-zone hash/signature
  验证器，但已识别 Falcon classifier 不理解 v6 body。
- HPE PLDM footer 签名有效；Dell 没有同型 footer。

### INFERENCE

- 两-entry table 很可能属于 BCRT/VDPA/security-zone 内部块；`+0x209` parent
  digest 很可能再进入相邻 certificate/signature 检查。正式 parser binding 和
  signed transcript 仍只是结构推断，不是闭合证明。
- 最终 v6 接受大概率发生在 device secure-loader/FSP-side policy，而非当前找到的
  host classifier；但具体执行者和时序尚未由这些静态 bytes 唯一确定。

### UNKNOWN

- `NVFW +0x400..+0xe00` 五个 `0x200` 高熵块的字段名称和 trust-root 身份；
- `+0x209` parent digest 到 96-byte adjacent field 的正式签名 schema/range；
- parent digest 是否、以及由哪一把设备 pinned key 间接签名；
- descriptor 尾部 28 bytes 的 v6 私有 schema；
- secure loader 对 board/SKU/fuse/policy 的最终 acceptance 判据。

这些未知量意味着目前已经知道“目标对象的 bytes 怎样被 hash”，但还不能据此
构造可接受的修改，更不能声称已经找到认证绕过或安全运行时解锁方法。

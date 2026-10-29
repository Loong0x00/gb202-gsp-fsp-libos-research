# Dell/HPE `.fwpkg` 容器与认证材料审计（纯离线）

日期：2026-07-22（Asia/Singapore）

## 1. 范围与安全边界

本次只读取项目中已经保存的两份包及其已提取 `.nvfw`：

- Dell `g153_0210_895__98028D0001.fwpkg`
- HPE `nvfw_RTXPRO6000BWSE_0003_251124.1.0_prod-signed.fwpkg`

没有执行 updater、`nvflash`、`.scexe` 或 MODS；没有访问 GPU、设备节点、
PCI/BAR/MMIO、debugfs 或网络。所有验证均为普通文件上的离线结构、CRC、hash
和公钥签名运算。

格式字段用 DMTF
[DSP0267 1.0.1](https://www.dmtf.org/sites/default/files/standards/documents/DSP0267_1.0.1.pdf)
的 PLDM Firmware Update Package 定义交叉校准。未知的厂商尾部字段只报告 raw
offset/数值，不赋予未经证明的名称。

## 2. 两份文件的外层都是 PLDM firmware package

两份文件开头相同的 16 bytes 为：

```text
f0 18 87 8c cb 7d 49 43 98 00 a0 2f 05 9a ca 02
```

这是 DSP0267 v1.0.x 定义的 `PackageHeaderIdentifier`。两者
`PackageHeaderFormatRevision` 都为 `1`；`+0x11` 的 little-endian `u16`
是标准 `PackageHeaderSize`。

| 文件 | bytes / SHA-256 | PLDM header | header CRC32 | 组件数 |
|---|---|---:|---|---:|
| Dell | `1,908,383` / `27a99791cb2da93aa75fbe815493d2cc7a0c7c884d4181c66a3588351f403f91` | `[0,0xcf)` | stored `0x5d4e81de` = recomputed | 1 |
| HPE | `2,204,365` / `620b673fcbee27d90693610477344332e5f3d47ba538903f9ebcd09db52abe27` | `[0,0x14d)` | stored `0xdbdb9d70` = recomputed | 2 |

CRC 的复算范围均为 `header[0:PackageHeaderSize-4]`，最后 4 bytes 是 stored
checksum。这里的 CRC32 只证明 PLDM header 没有意外损坏；它不是带密钥的
hash，也不是 NVIDIA/HPE 发布者签名。DSP0267 把设备在 `VERIFY` 状态如何验证
code image 留给具体实现，因此 PLDM header CRC 也不能替代 payload 自身的安全
校验。

## 3. Dell：标准头后只有一份 NVFW，无外层尾部

Dell component record 可机械解出：

```text
component 0 location = 0x000000cf
component 0 size     = 0x001d1dd0 (1,908,176)
component 0 version  = 98.02.8D.00.01
```

精确关系为：

```text
file size = 0xcf + 0x1d1dd0 = 0x1d1e9f
package[0xcf:EOF] == RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw
embedded NVFW SHA-256 =
8658724061087279f59ca3a0d8ce443cb4ca52db2543c64723a3cea632a29b59
```

因此 Dell `.fwpkg` 的外层确实接近“PLDM metadata carrier”：header 负责设备/
组件匹配、位置、长度和版本，随后就是完整 NVFW。文件在该组件末端精确结束；
外层没有 HPE 那种额外 ECDSA footer。此结论不等于 Dell NVFW 内部没有它自己的
签名/加密材料；那是另一层，本报告没有把 NVFW 内部安全对象混称为 PLDM 外层
签名。

## 4. HPE：两份组件，不是“NVFW + 约 288 KiB 签名”

HPE component table 明确登记两个组件：

| index | location | size | version | 离线内容判定 |
|---:|---:|---:|---|---|
| 0 | `0x14d` | `0x1d1dd0` (1,908,176) | `98.02.9E.00.01` | 完整 GB202 NVFW |
| 1 | `0x1d1f1d` | `0x47fb0` (294,832) | `0008.00.0272.0000` | 以 ARM vector/code 和固件字符串为主的独立第二组件；具体芯片用途未由本次证据命名 |

第一组件逐字节等于保存的
`RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw`：

```text
component 0 SHA-256 =
98c52f80e937907c4203280824bbef6bb17439c900edc74532072780611c0fe5

component 1 SHA-256 =
ad14aa1e6caa2ce307d2a06bf67cd26425c9f1a3bccd8aef0023aaf2a8fb8545
```

两个登记组件在 `0x219ecd` 结束，文件总长为 `0x21a2cd`，所以真正未被 PLDM
component records 覆盖的额外区域只有：

```text
[0x219ecd,0x21a2cd) = 0x400 bytes
SHA-256 = f6a557cb0b39c7b14532a754a660c383334dfc760e5d4f79e9c270ace413c359
```

此前把整个 `0x483b0` bytes 都称为 private trailer 会把第二固件组件误算进去；
严格的容器分解应是 `0x47fb0`-byte component 1 加 `0x400`-byte extra footer。

## 5. HPE `0x400` footer：存在可验证的 P-384/SHA-384 签名

footer 开头 18 bytes 为：

```text
5f 32 cb 08 03 00 00 00 e8 00 21 9e cd 00 00 10 00 d6
```

这些字段没有在本次允许的证据中获得厂商定义，故不命名。只报告两个可机械
验证的边界关系：

- footer `+0x12..+0xe8` 是恰好 `0xd6`（214）bytes 的 PEM
  `-----BEGIN PUBLIC KEY----- ... -----END PUBLIC KEY-----`；
- `+0xe8` 是 NUL，`+0xe9` 为 `0x68`，随后恰好是 `0x68`（104）bytes 的合法
  DER ECDSA signature，余下 bytes 全为 0。

PEM 解码结果是裸 `SubjectPublicKeyInfo`，算法为 EC、曲线为 `secp384r1`
（P-384）；它不是 X.509 certificate，没有 subject、issuer、有效期或证书链。

```text
PEM range              [0x219edf,0x219fb5)
PEM SHA-256            5ff89e31e05ff4180cedef133e670a50196055fe10d523c335bf2acc1ee1c8f0
SPKI DER SHA-256       525f6d09a398b8b1f8890ca100e3a849337f0bb28d5c5ff5c9bc72d7331e4c34
signature length byte  0x219fb6 = 0x68
DER signature range    [0x219fb7,0x21a01f)
signature SHA-256      ac66e11b948aab997a1f1b102852417a497de8beca256c4fff475b373aefc2d7
```

用上述 SPKI 对下列**精确消息范围**执行 ECDSA/SHA-384 verification 成功：

```text
signed bytes           package[0:0x219fb5)
signed length          2,203,573 bytes
signed-data SHA-384    976ec211f17def7725a81053b9e7f031ec0f3d9ab0448ddc78600d94dc5816ccad3356f063d4bb76506efc1a18672b6c
verification           VALID (ECDSA P-384 with SHA-384)
```

该 signed range 覆盖：PLDM header、两份完整 component、footer 的 18-byte raw
header，以及完整 PEM 公钥；它在 PEM 后、NUL/长度 byte/DER signature 之前结束。
所以 HPE 包确实含有一份可复算成功的密码学签名，不应只称为“看起来像签名”。

但这仍须区分两个不同命题：

1. **包内自洽性：已验证。** 当前 payload、footer metadata、公钥和签名相互匹配；
   修改 signed range 中任意内容都会使这份签名失效。
2. **发布者身份：未由本地材料闭合。** 验证用公钥本身随包携带，footer 没有
   X.509 certificate/chain；本地也没有 HPE/NVIDIA 官方公布的该 key fingerprint
   或另一个可信根对它背书。保存的 `nvflash` 中四把 PEM 公钥的 SPKI fingerprint
   也都不等于这把 footer key。因而仅凭这个文件，可以证明“由对应私钥签过”，
   不能证明该私钥一定属于 HPE 或 NVIDIA。设备/工具是否另有 pinned key/hash
   属于本报告尚未闭合的 verifier policy。

## 6. 它能否证明 Pro blob 不能直接移植？

**不能。** 外层证据只能支持以下较窄结论：

- 在 HPE 原 `.fwpkg` 中直接改 PLDM header、NVFW 或第二组件，会破坏已验证的
  footer signature；若原更新路径强制检查它，修改后的整包会被拒绝。
- Dell 没有同型 footer，却同样携带完整 Pro NVFW，证明这个 `0x400` footer
  不是“GB202 Pro NVFW 能否执行”的普适格式条件。
- HPE component 0 可以逐字节从外层容器中分离；PLDM/ECDSA wrapper 没有改变
  该 NVFW 的内部 bytes。因此“抽出 Pro NVFW/object 放到另一载体”是否能启动，
  取决于 NVFW 内部签名/加密对象、board/SKU 匹配、BootFSM/FSP/GSP/hardware
  policy，而不是由 PLDM wrapper 本身回答。

反过来也一样：HPE 外层签名有效，并不授予该 NVFW 跨 SKU 使用权限。它证明的
是这一个 HPE package byte sequence 的完整性关系，而不是 GeForce 对 Pro object
的接受条件。

## 7. 最终结论

- 两份 `.fwpkg` 都不是完全 opaque：外层是可严格解析、可校验 header CRC 的
  DMTF PLDM firmware package；NVFW 的 offset/size/version 都由组件表明确给出。
- Dell 是 `0xcf`-byte PLDM header + 一份完整 NVFW，到组件末端即 EOF。
- HPE 是 `0x14d`-byte PLDM header + 完整 NVFW + 第二份 294,832-byte 固件组件
  + `0x400`-byte extra footer。
- HPE footer 中存在实际有效的 ECDSA P-384/SHA-384 signature；但只有裸随包公钥，
  没有本地可信证书链/官方 key pin，因此密码学完整性已闭合、发布者身份未闭合。
- 这份外层认证会阻止“原包内随手改字节后仍保持原签名有效”，但不能单独证明
  Pro NVFW/FSP blob 不可移植，也不能证明其可移植；决定性约束仍在 inner
  firmware 和 device policy 层。

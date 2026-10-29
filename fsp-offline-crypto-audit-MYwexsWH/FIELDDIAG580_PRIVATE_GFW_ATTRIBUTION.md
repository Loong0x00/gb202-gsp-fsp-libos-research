# FieldDiag 580: 16 个未匹配 type-4 GFW 的静态归属审计

## 结论摘要

对 `v2.0.4/dgx/tests/mods.580/fieldiag` 中 16 个未与公开固件逐字节匹配的唯一 type-4 对象，静态证据支持以下结论：

1. **高置信度：它们是结构完整、SHA-384 自洽的 type-4/GFW-v4 镜像对象，并被纳入程序内的 NVIDIA 风格 `BINDATA_ARCHIVE` getter/存储布局。** 每个对象都对应一个 AArch64 小型 getter；getter 返回唯一 archive 根地址；根记录有 4 个条目，标签集合为 IMAGE、HASH、PKEY、SIG。所有对象的 `SHA-384(image) == stored_hash`。这不是对 RSA/ECC 签名或信任链的独立验证。
2. **中高置信度：它们是 GSP-RM/FMC GFW 类 bindata 成员，而不是可直接命名的散落载荷。** 同一 ELF 中另外 13 个同形对象与 NVIDIA 580.119.02 公开生成源码逐字节匹配，并被命名为 GSP-RM FMC GFW（含 Debug、Prod、CC Prod）。
3. **目前不能把这 16 个对象逐个映射到 GPU 架构、具体组件、Debug/Prod 或 CC 变体。** 本地 615 bindata 与公开 580.119.02 源码也没有给出这些对象的逐字节映射。对象大小、相邻顺序、签名算法或公钥类别均不足以作此命名。
4. **未找到任何一个对象与 `fuserework.bin` 或 FuseRework debug GFW 的正向关联。** 证据更符合普通嵌入式 GSP-RM GFW。严格地说，不能仅凭 type-4 格式或认证尺寸排除某个 RSA 对象也被用作 FuseRework 输入：FuseRework 的 mode-2 parser 接受 type-4，且 9 个 RSA-3072 对象具有 384-byte 公钥和签名。但未找到它们与外部 `fuserework.bin` 加载路径、FuseRework getter 调用点或特定 sidecar 的连接。因此**不应将任一对象标注为 FuseRework 固件**。

置信度说明：表中 ELF 偏移、完整对象 SHA-256、getter VA 和 archive VA 是直接可复核的观测；归属结论按“观察到的结构”与“推测的产品名”分开。

## 范围与方法

- 目标：`external_dgx_spark_fielddiag/v2.0.4/dgx/tests/mods.580/fieldiag`
- ELF SHA-256：`383147f07018911fe55537dd7a35eced01ac9c4b65873dc55dd634fe35483b48`
- 只读检查；没有执行 FieldDiag、发送 FSP 请求或操作 GPU/硬件。
- 16 行表格中的 offset 是该 ELF 内 type-4 对象起点。对象完整 SHA-256 可用于从样本独立复核。
- `.text` AArch64 VA 到文件偏移的换算为 `file_off = VA - 0x210000`；相关只读 LOAD 区域中的数据 VA 到文件偏移为 `file_off = VA - 0x200000`。这些换算用于把 getter 指令与 archive 根记录互相验证。

分析以 `carved_mode2/inventory.json`、`carved_type4_auth/inventory.json` 和 `gfw_getter_map.json` 为基准，并对目标 ELF 的 getter 指令和 archive 根记录重新交叉检查。既有 `gfw_getter_map.json` 中未确认/为空的 getter 字段不作为排除依据；本报告给出重新解码到的 VA。

## AArch64 getter 与 archive 结构

对 29 个 type-4 唯一对象，均可从对象映像指针回溯到 ELF 内存储记录、四项 archive 根和 AArch64 getter。16 个未知对象的 getter 为 `ADRP` 加地址调整再 `RET` 的短 wrapper；其有效返回地址分别是下表 archive VA。对这些 getter 的全 `.text` 直接 `BL` 扫描没有发现调用者；现有映射也没有静态函数指针引用。因此，getter 证明了静态注册/可取得的 bindata 对象，**不单独证明运行时选择路径**。

16 个根记录都满足 `entryNum=4`，标签值序列为 `[0x23, 0x17, 0x38, 0x33]`。本地 NVIDIA `bin_data.h` 的枚举对应为：`0x23=UCODE_IMAGE`、`0x17=UCODE_HASH`、`0x38=UCODE_PKEY`、`0x33=UCODE_SIG`。表项的存储指针回指同一 type-4 对象的相应 image/auth 部分。标签顺序在 ELF 中按数值记录；此处只用标签集合识别组件，不用顺序猜测产品名。

此形态与 NVIDIA 生成源码中的 GFW archive 一致。例如 580.119.02 `g_bindata_kgspGetBinArchiveGspRmFmcGfwDebugSigned_GB202.c` 和 `...GspRmCcFmcGfwProdSigned_GB202.c` 均声明 4-entry archive 并提供返回 archive 地址的 getter；可分别参照本地公开源码对应文件的 archive/getter 段（例如 debug 文件行 13654–13674）。这与 ELF 中已逐字节匹配的 13 个公开对象共同支持“GSP-RM/FMC GFW bindata 类”归属，而不是直接证明未知项的具体命名。

## 16 个未匹配对象清单

`code/data` 是 type-4 header 中 section size 字段（十六进制）。`PKEY SHA-256` 前缀用于关联下方完整 key hash 表；认证算法与对象哈希来自 `carved_type4_auth/inventory.json`。所有 offset、VA 和完整对象 SHA-256 均针对 v2.0.4 ELF。

| ELF offset | 完整对象 SHA-256 | 大小 | getter VA | archive VA | code/data | 认证 / PKEY SHA-256 前缀 |
|---:|---|---:|---:|---:|---|---|
| `0x0768c410` | `98b71a514684a0e5697bab5e81e5a6c064dffdf8a9aa1eb4ae10310fcc08f1fd` | 152,392 | `0x17b32010` | `0x043cda08` | `0x1bf00/0x8a00` | RSA-3072 / `54076b108ad3da65…` |
| `0x076b1860` | `bc018d59aa201eedd4368efc4c251047e365b86eca2063484763aba29237ba3a` | 145,736 | `0x17b32000` | `0x043cd9c0` | `0x1a500/0x8a00` | ECC / `0f28639cc039cbad…` |
| `0x076d52b0` | `c70c92b29934c8018048796ae4bd3812b51863418693ea3199c15cd248010ee0` | 145,480 | `0x17b31ff0` | `0x043cd978` | `0x1a300/0x8b00` | ECC / `0f28639cc039cbad…` |
| `0x076f8e30` | `72a4822ca8b90a3a535efd3407aa1a9327e674f75d5d11ba99284ca50b3d3b6a` | 132,680 | `0x17b31fe0` | `0x043cd930` | `0x17900/0x8300` | RSA-3072 / `b6590fa3546ab7f7…` |
| `0x078ae4a0` | `183e6dc1ee52cc1d45c7649f798ea0b19b3c7f8c0f3c407f18595caf5150d9ee` | 143,432 | `0x17b31f30` | `0x043cd7a8` | `0x18300/0xa300` | RSA-3072 / `7b3d6981aad093ee…` |
| `0x07b37080` | `ce62855bdc565a5b3287303f41e828106440d5765cb8d8f581921d121a8eab5a` | 152,392 | `0x17b31dd0` | `0x043cd498` | `0x1bf00/0x8a00` | RSA-3072 / `7b3d6981aad093ee…` |
| `0x07b5c4d0` | `4ed9953f95baf381d7fe74d519c7566aabe10e1516a62aef6da7a73d346a6351` | 145,736 | `0x17b31dc0` | `0x043cd450` | `0x1a500/0x8a00` | ECC / `d9429022b26cd429…` |
| `0x07b7ff20` | `4b44fb5d0c26451996925b85c1eebb1b2dc1d3e90c791282c7fd519acd8bcc8d` | 145,480 | `0x17b31db0` | `0x043cd408` | `0x1a300/0x8b00` | ECC / `d9429022b26cd429…` |
| `0x07bc4ac0` | `13daa4f8ed663b696f0a5bd7335fc3d1ae8276081ca0e6c19b297878bafbb5db` | 161,608 | `0x17b31d90` | `0x043cd398` | `0x1c900/0xa400` | RSA-3072 / `b6590fa3546ab7f7…` |
| `0x07bec540` | `b9410e7e6af6e0d93a019cf9d428274723dfbd7191f095d1cd90eaef7e5c52a1` | 161,608 | `0x17b31d80` | `0x043cd350` | `0x1c900/0xa400` | RSA-3072 / `7b3d6981aad093ee…` |
| `0x07c13fc0` | `77f8b726146f86047807e4528d677588325bf766bcc27b1461bb4575cf042c6d` | 132,680 | `0x17b31d70` | `0x043cd308` | `0x17900/0x8300` | RSA-3072 / `7b3d6981aad093ee…` |
| `0x07ceb7b0` | `3237db69e92083a40d1a91b92db77aa2403680e8f176557b3e7db49cce79feda` | 121,672 | `0x17b31d10` | `0x043cd1f8` | `0x1ac00/0x2500` | ECC / `d9429022b26cd429…` |
| `0x07d09400` | `acaf89120d77038476a3e0a6b3dcabb53938bb2fc53c40823e054a136eeb6540` | 114,760 | `0x17b31d00` | `0x043cd1b0` | `0x19100/0x2500` | ECC / `0f28639cc039cbad…` |
| `0x07d25550` | `7df564b8803061b94cbbcdd24eb53ee7823c809bcacebba9120ff274c266dfb1` | 117,832 | `0x17b31cf0` | `0x043cd168` | `0x19d00/0x2500` | ECC / `d9429022b26cd429…` |
| `0x07d424d0` | `0811681b44483255f9e481f79913f29a8c5f1166a42b854fa17d010939f145c9` | 108,360 | `0x17b31ce0` | `0x043cd120` | `0x17800/0x2500` | RSA-3072 / `b6590fa3546ab7f7…` |
| `0x07d5cf50` | `4681ebf1a4d3ae02a995b0db4d3a2d4d0e808d98fb5c635cac4bf14a28505415` | 108,360 | `0x17b31cd0` | `0x043cd0d8` | `0x17800/0x2500` | RSA-3072 / `7b3d6981aad093ee…` |

### PKEY SHA-256 完整值

| 前缀 | 完整 PKEY SHA-256 |
|---|---|
| `0f28639cc039cbad…` | `0f28639cc039cbad15cf01e1e63c2c44ea3aa9ce8ed2f447eb7fa66dd65d63f1` |
| `b6590fa3546ab7f7…` | `b6590fa3546ab7f77966dc56f4b12ff7d662c8181b95dcc52dba4bfb64c588fb` |
| `54076b108ad3da65…` | `54076b108ad3da65e09f675d88efd553340a0c0653cf13372f4e30dd6ab17e7c` |
| `7b3d6981aad093ee…` | `7b3d6981aad093ee023a8ceb67b686dbb7c1c72acd97db3107aff59edd2c814c` |
| `d9429022b26cd429…` | `d9429022b26cd429565ba30f2b06678dbd531f207d442fafa25e0668e0b0282d` |

16 项中 7 项为 ECC、9 项为 RSA-3072；这 16 项实际使用 5 个不同 PKEY SHA-256，且这 5 类都出现在公开精确匹配样本中。全体 29 项共有第 6 个 key 类 `e9bbc…`，但它不在这 16 项中。公开样本显示同一 key 类可跨多个公开命名的芯片/变体使用（例如 `0f286…` 对应 GB100/GB202 的多个公开 GFW，`7b3d…` 对应多种公开 Debug GFW）。所以 PKEY 只能验证认证材料类别，不能单独确定未知项的架构或 Debug/Prod/CC 身份。

相同 `code/data` 尺寸的对象成对出现：`0x17800/0x2500`、`0x17900/0x8300`、`0x1bf00/0x8a00`、`0x1a500/0x8a00`、`0x1a300/0x8b00`、`0x1c900/0xa400`。这种重复尺寸可能表示同一尺寸模板下的不同变体；没有命名表、分支选择证据或源码哈希映射，不能据此将任一对称作 production/debug 或某个 GPU 型号。其余四项为不同尺寸。header word `h[6]` 在 11 项中为 `0x104`、5 项中为 `0x103`；本审计没有可靠源码字段定义可将这些值解释成架构或产品模式。

## FuseRework 判断

FieldDiag 580 的已恢复流程（`external_dgx_spark_fielddiag/fieldiag580_fuserework_flow.asm`，以及 `aarch64_fuserework_string_refs.txt`）显示 FuseRework 使用显式外部文件路径：主输入字符串 `fuserework.bin` 在 VA `0x10a051f0` 一带 materialize；认证 sidecar 分别为：

- `fuserework_debug_gfw_hash.bin`：48 bytes；
- `fuserework_debug_gfw_pub_key.bin`：384 bytes；
- `fuserework_debug_gfw_sig.bin`：384 bytes。

执行路径在 `0x10ce9c90` 附近构造 `0x0f` 请求，响应只接受 4-byte `0x0000000f` ACK（参见 `FIELDDIAG580_AARCH64_FSP_SENDER_AUDIT.md` 的 callsite 与响应检查）。没有发现该外部文件加载路径引用 16 个 archive getter/root 之一，也没有在本轮静态 xref 扫描中建立 FuseRework 处理函数到这些 getter 的调用关系。

尺寸比较只能提供有限证据：未知 ECC 对象的 PKEY/SIG 分别为 104/96 bytes，不符合 FuseRework sidecar 明确要求的 384/384 bytes；未知 RSA-3072 对象为 384/384 bytes，尺寸与之相容，但这也是普通 RSA-3072 GFW archive 的正常组成部分。所有 16 项都以 archive 中的 IMAGE/HASH/PKEY/SIG 成员存在；其 archive 形态和与 13 个公开 GSP-RM/FMC GFW 的结构一致性，比“恰好能组成 FuseRework sidecar”更有解释力。由于 main-input parser 本身接受 type-4，且没有取得 `fuserework.bin` 的实际输入文件用于逐字节比对，**不能形式化排除某一 RSA 对象被外部流程复用；但当前没有可支持这种归属的正向证据**。

## 证据边界与置信度

| 命题 | 置信度 | 依据 / 限制 |
|---|---|---|
| 16 项均为结构完整的 type-4/GFW-v4 镜像对象 | 高 | header/section 几何一致；全部 `sections_exact`；认证 inventory 的 SHA-384(image)==stored_hash 检查通过。未在此处独立验证 RSA/ECC 签名。 |
| 16 项均在四成员 GFW bindata archive 中注册 | 高 | 每项有唯一 AArch64 getter 和 archive root；根记录均为四项 IMAGE/HASH/PKEY/SIG；对象指针/数据结构可互相回溯。 |
| 广义 GSP-RM/FMC GFW bindata 成员 | 中高 | 同 ELF 的 13 项逐字节匹配 NVIDIA 580.119.02 生成的 GSP-RM/FMC GFW；16 项使用同类 getter/archive 结构。未知项没有公开生成源码名字。 |
| 精确 GPU 架构、board、Debug/Prod/CC 或 GFW 名称 | 低 / 未确定 | 580 公开源码和本地 615 镜像未命中；getter 没有确认到直接调用者；key、尺寸、顺序均非唯一标识。 |
| 任一项是 `fuserework.bin` 或 FuseRework debug GFW | 未证实；不应标注 | 外部文件/sidecar xref 未连接到 getter；RSA 尺寸只是兼容条件。type-4 与 RSA-3072 本身不足以证明 FuseRework。 |

## 可复核文件与检查

- 目标 ELF 与哈希：`external_dgx_spark_fielddiag/v2.0.4/dgx/tests/mods.580/fieldiag`。
- 对象偏移、完整对象 SHA-256、section/auth 字段：`external_dgx_spark_fielddiag/carved_mode2/inventory.json`、`carved_type4_auth/inventory.json`、`extract_type4_auth.log`；对照过本地 `bindata_615_all_gfw/` 镜像，无逐字节命中。
- 已知公开匹配的 13 项：`external_dgx_spark_fielddiag/public_gfw_exact_map.json`。
- AArch64 getter/root 交叉索引：`external_dgx_spark_fielddiag/gfw_getter_map.json`；本报告对 getter 指令和 16 个有效返回 VA 重新解码。
- NVIDIA 公开 tag：[`open-gpu-kernel-modules` 580.119.02 `src/nvidia/generated/g_bindata.c`](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.119.02/src/nvidia/generated/g_bindata.c) 及本地 `external_dgx_spark_fielddiag/public_580.119.02/` 的具体生成源文件。
- 本地标签定义：`gspkm/src/nvidia/inc/kernel/core/bin_data.h:66–100`；本地 checkout 为 `610.57.04`，用来核对标签名称，不将 615/610 名称冒充为 580 私有项的精确来源。
- FuseRework 路径与 sidecar：`external_dgx_spark_fielddiag/aarch64_fuserework_string_refs.txt`、`external_dgx_spark_fielddiag/fieldiag580_fuserework_flow.asm`、`FIELDDIAG580_AARCH64_FSP_SENDER_AUDIT.md`、`FUSEREWORK_ABI.md`。
- 重现核心检查：`sha256sum <fieldiag>`；`llvm-objdump -d --start-address=0x17b31cd0 --stop-address=0x17b32020 <fieldiag>`；对 `carved_type4_auth/inventory.json` 验证所有 v2 type-4 记录 `sha384_ok=true`；用 ELF 只读扫描从 image 指针回溯 archive root，再解码 getter 的 `ADRP` 与地址调整指令。

本次只新增本报告；未修改 ELF、既有报告或其他取证产物。

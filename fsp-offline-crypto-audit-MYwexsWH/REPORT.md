# GB202 `FSP_RUN` 离线密码审计（第一轮）

日期：2026-10-26

## 范围

仅用 CPU 读取本地 ROM/NVFW/驱动 bindata/MODS ELF。未访问 GPU、BAR、设备节点，未运行或修改固件，未刷写。原始输入未修改；所有新脚本和结果均在本目录。

## 已闭合的事实

### 1. 当前共有 6 个唯一 `FSP_RUN` payload

除既有 FE/ASUS、Dell 8D、HPE 9E 外，发现：

- RTX PRO 6000 WS `98.02.52.00.02`：`0x2a800` 字节，SHA-256 `3dd252cbae27a4836e8d1b52014edeae6a33e4bab0cd5b10ba74b258a49d6b34`
- RTX PRO 4500 `98.03.7B.00.01`：`0x2a800` 字节，SHA-256 `f81b474599568894939c219c14668037ffb658e8436fc47ac8cef6ab6478dc52`
- GALAX RTX 5090D `98.02.31.40.9A`：`0x29400` 字节，SHA-256 `81911b8f10e75b5d743ba860f4c4f66a6db97e248e835c30ae6dfe6919abfc81`

Dell 8D 的 payload/descriptor 又出现在本地 RTX PRO 5000 `98.02.92.00.01` ROM 中，说明对象可跨 SKU 复用。本地既有 `vbios_bulk_5090_20260723` 语料含 24 份 ROM：23 份普通 RTX 5090（包括 ASUS XOC `98.02.2E.80.50`）逐字节复用 FE/ASUS 的同一 `FSP_RUN`，仅 5090D 提供第 6 个对象。进一步对本地树中 71 个含 `FSP_RUN` 的固件文件重扫，得到 58 条有效记录，仍只有这 6 个 payload/6 个 descriptor。该 bulk 语料此前未被首轮显式路径清单纳入，是本轮本地复核纠正。

### 2. v6 descriptor 内嵌一个自描述的 40-byte crypto 子结构

对 18 个唯一的 v6 对象复核：

- 外层 descriptor 总长 `0x50`；
- `+0x28` 到结尾恰为 `0x28` 字节；
- 所有对象 `desc[+0x28:+0x2c] == 01 28 01 01`；
- 其中第二字节 `0x28` 与剩余子结构长度精确相等；
- 后接 8-byte 对象标识（例如 `00 FSP_RUN`、`00 00 OOBHUB`）；
- 再后接 28-byte 高熵字段。

因此 `0x01012801` 不应再解释为“key ID 0x28”。更强的结构解释是：crypto descriptor v1、size `0x28`，再带两个 1-byte 类型/算法字段。正式私有字段名仍未知。

### 3. 本地私有错误表指向 AES-256-GCM，而非 AES-128

从 MODS 570.215 的 0x258-entry error jump table机械恢复：

- `0x16b CRYPTO_AES_GCM_BLOCK_FAILURE`
- `0x16c AES_256_GCM_AUTHENTICATION_ERROR`
- `0x16d AES_256_GCM_DECRYPTION_ERROR`
- `0x17b UCODE_V5_STATE_SANITY_FAILURE`
- `0x1a0 KDF_CONFIG_ERROR`
- `0x1a1 KDF_EXECUTION_ERROR`
- `0x1a2 KDF_SHA_TIMEOUT_EXPIRED`
- `0x213/0x214` crypto descriptor v4 version/sanity
- `0x215/0x216` crypto descriptor v5 version/sanity
- `0x217` unsupported crypto descriptor v1
- `0x218 UNEXPECTED_CRYPTO_MSG_TYPE`
- `0x222 NON_FSP_DECRYPTION_DEV_NOT_ALLOWED`

公开 NVIDIA header 同时定义 AES-256-GCM 的 IV 为 12 bytes、tag 为 16 bytes。因此 `FSP_RUN` crypto 子结构末尾 28 bytes 作为 `IV12 || tag16` 是目前最强的格式模型，但还没有正式字段定义或正确密钥完成认证。

### 4. 28-byte 尾不是常见裸摘要

对全部 18 个对象复算 SHA-224、SHA-256/SHA-384/SHA-512 截断及若干 descriptor/payload 覆盖，零匹配。它不是简单的 `SHA-224(payload)` 或常见摘要截断。

### 5. Blackwell 同代 debug/prod 工件关系

- GB202 `GspRmFmcGfwDebugSigned` 与 `...ProdSigned` 的 **image 逐字节完全相同**；差别在签名/公钥，不提供 debug 加密明文副本。
- `GspRmBoot` debug/prod image 不同，但 descriptor 完全相同。
- dynamic image 的 `0x000..0x2ff` 呈 384-byte 签名槽形态，`0x300` 为 debug/prod 明文标志（`0xaa/0x55`），`0x320` 为 16-byte LC128/MAC 候选，`0x380` 后为连续高熵主体。
- 610 与 615 的同类 descriptor 逐字节相同，密文主体整体变化；不支持固定 ECB 或固定 nonce/key stream 复用。

## 实际测试结果

所有测试都有已知 GA102 debug booter 正例：key 37 的 AES-128-ECB 解密与保存明文逐字节一致，熵 `7.994871 -> 6.933457`。

### AES-128 公共 debug key

- 256 个公开编号 debug keys；
- 当时已知的 5 个唯一 `FSP_RUN`；
- 四种 28-byte IV/tag 拆分；
- ECB/CBC/CTR/GCM stream 多种解释；
- GCM AAD：empty、outer prefix、name、tag-zero descriptor。

结果：认证命中 0；所有结构评分仍处于随机数据区间。

对 18 个 v6 对象执行 92,160 次完整 GCM tag 检验：0 命中。

### AES-256 公共/组合候选

777 个候选，包括：

- `NvTestKey` 32-byte 多种字节序；
- Thor T234/T264 YAML key、dummy key、zero key；
- 编号 debug key 的 self/adjacent/reverse 32-byte 组合。

对 18 个对象执行 279,720 次认证检验：0 命中；`FSP_RUN` stream 解密无结构候选。

### 有依据的 KDF 候选

12 个公开 root × 14 labels × 8 descriptor contexts × 7 KDF constructions：

- SP800-108 HMAC-SHA256 两种消息布局；
- HMAC label/context；
- SHA-256 concat；
- 两块 CMAC 扩展。

每个 target 去重后合计 47,040 derived keys，940,800 次完整 GCM tag 检验：0 命中；188,160 个 stream 评分无结构候选。

### MODS 工厂工具邻近材料

围绕 fuse-rework、AES-256-GCM、KDF、non-FSP-decryption 字符串的有界 ±16 KiB 区域，提取 24,898 个唯一 32-byte raw/SHA256 候选：

- 298,776 次 FE `FSP_RUN` GCM tag 检验：0 命中；
- 99,592 个 stream 评分无结构候选。

### dynamic debug image 两级包钥假说

把 `GspRmBoot` debug image `+0x320` 的 16 bytes 作为 wrapped key/seed，测试 AES encrypt/decrypt、xor、SHA/HMAC 派生，再试 ECB/CBC/CTR：133,120 trials，未出现结构化明文。

## 当前结论

1. 尚未获得 FSP 明文。
2. “AES-128、还差 72 bit”不是当前最符合证据的模型；更可能是 AES-256-GCM data key，经 FSP 内部 KDF/硬件根派生。
3. 170HX 的可迁移教训仍成立：现实突破口应是同明文 debug 工件、工厂 fuse-rework 物料、解析/实现缺陷，而不是攻击 AES 本身。
4. 公开编号 debug key 在 Blackwell `FSP_RUN` 和已测同代 v6 工件中没有直接复用；过去“公开 512 把都已排除”的措辞不准确，公开的是一组 256 把 debug family，production 120-bit prefix 并未公开。

## 下一优先级

1. 搜寻 `FSP_RUN` debug/engineering VBIOS，或 `fuserework.bin` 与 `fuserework_debug_gfw_{pub_key,hash,sig}.bin`。
2. 继续恢复 crypto descriptor v1 的两个 type/algorithm byte、AAD 精确范围和 KDF config。
3. 只有获得新的格式/key/material 证据后再扩大候选搜索。
4. 任何真机 FSP crypto-message / firmware-update oracle 探测需要单独风险授权；本轮未执行。

## 第二轮更新

### MODS 软件 GCM 路径已恢复

从 MODS 570.215 的 `SwDecrypt` 及内置 GCM 实现反汇编/反编译确认：

- key 固定复制 32 bytes；
- IV 固定复制 12 bytes；
- tag 长度固定 16 bytes；
- GCM 调用的 AAD pointer 与 AAD length 均为 0；
- decrypt mode 参数为 0，encrypt mode 参数为 1；
- 该实现是标准 CTR + GHASH 形态。

因此，对同一 MODS 工具链的默认软件 decrypt 路径，主假设应收敛为：
`AES-256-GCM(key, IV12, ciphertext, AAD="", tag16)`。这不能证明 FSP ROM 内部必定调用同一软件函数，但显著提高了 `crypto_desc[12:24]=IV`、`[24:40]=tag`、empty AAD 的可信度。既有测试已覆盖这一精确组合。

### 全本地 firmware corpus 的 crypto header 差分

扫描 350 个本地 firmware-like 文件，命中 203 个 v6/0x50 crypto descriptor 记录、36 个唯一 descriptor。所有记录的内嵌 crypto header 均为 `01 28 01 01`；没有找到可通过字段差分给最后两个 `01` 命名的第二种取值。外层 flags 分布为 `05/0d/1d/1f`，内层 crypto header 不变。

### 保存的 fuse dump 按 AES-256 重新审计

输入：`parallel/fsp_attack_20261026/fuse_region_20261026.bin`，SHA-256 `281e43f15a1ed5906e6cfd19029da6028b4a52a80632cf0204bd4fcb92460d42`。

过去只用 16-byte AES-128 oracle；本轮重新测试：

- 所有 32-byte 滑窗及 raw/reverse/bswap32/reverse-word 变体：25,280 unique keys，50,560 GCM trials，0 命中；
- SHA-256/SHA-512 派生的 16/24/32-byte windows：37,144 keys，74,288 trials，0 命中；
- 每个唯一 16-byte 窗口作为 HMAC-SHA256 KDF root：404,730 derived keys，809,460 trials，0 命中；
- 每个唯一 24-byte root：569,700 keys，1,139,400 trials，0 命中；
- 每个唯一 32-byte root：697,050 keys，1,394,100 trials，0 命中。

KDF 测试包含 SP800-108 标准布局、Thor 本地工具观察到的布局、直接 label/context HMAC，标签包含 `FSP_RUN/FSP/FSPK/RUN_/NVFW/UCODE`，context 包含 crypto prefix、对象 ID、版本字段及 descriptor prefix。

结论边界：已保存的可读 fuse 区没有以这些直接/常见派生形式给出 FSP data key；这不代表 BADF 后不可读的真实 fuse bank 不含 root key。

### 工件路线的新具体目标

公开检索定位到 Blackwell PCIe Field Diagnostics 包：`629-INT27-DIAG-008`，NVOnline ID `1124962`。该包是访问控制物料，比继续扩大随机字典更可能包含 `fuserework` 配套工件，但是否实际包含仍未知。

### GB202 570.151 制造包隐藏返修引用审计

对本地 `570.151_GB202_5090.zip` 的 ZIP/内层 tar 成员、`recipe_eng.xml`、`*_nochk.spc`、`gldGB202.bin` 和 MODS 字符串做只读关联检查：

- MODS ELF 含 `fuserework.bin`、三个 debug GFW sidecar 文件名和 `FRB Riscv Start`，但包成员清单中没有这些文件本体；
- 唯一独立 `frb` 文件仍为旧 `frb_ga100.bin`；
- ENG recipe/spec 没有显式调用 FuseRework；
- `gldGB202.bin` 是高熵数据区加测试索引/名称表，未检出 FSP/FuseRework/GFW 标识；
- FXSJ 分支存在 SMBv1 日志共享挂载，但没有发现返修二进制网络路径；
- manifest/Nautilus 配置含不透明加密数据，当前不能仅凭可打印字符串排除授权字段，但也没有正向物料证据。

详见 `GB202_MFG_HIDDEN_REWORK_AUDIT.md`。

## 第三轮更新：FuseRework 协议与 MODS 镜像取证

### 前置纠错与边界

- 已复核 `FSP_RUN` 样本边界及外层 SHA-384；现有 `fsp_code/` 是 GSP-RM 侧交互/加载代码，不是 FSP 本体明文。
- 旧 CUDA 搜索器存在首块结构过滤漏真密钥的问题，且只覆盖 AES-128、空 AAD 和单一布局；因此旧“未命中”不能外推到当前 AES-256-GCM 模型。GA102 key 37 正例已用于校验修正后的测试链。
- Dell 样本中先前标为“FSP CMAC 校验器”的 `0xad4933` 实际落在 OpenSSL `bsaes_xts_decrypt`，不再作为 FSP 密码证据。
- 本轮仍未访问 GPU、BAR 或设备节点，未发送 FSP 命令，未复位、写入、刷写或熔断。

### FuseRework 文件、认证与发送链

对 MODS 570.215 的 FuseRework 文件加载、编排、payload 构造、FSP sender 与响应解析进行 Ghidra 反编译，确认：

- 主输入文件被加载到 helper `+0x98`，大小必须 `< 0x200000`；后续调用链差分已闭合构造器默认路径，默认主文件就是 `fuserework.bin`，但 JS setter 在所有运行条件下的覆盖时序尚未穷尽；
- `fuserework_debug_gfw_hash.bin` 固定 48 bytes（SHA-384 长度）；
- `fuserework_debug_gfw_pub_key.bin` 固定 384 bytes；
- `fuserework_debug_gfw_sig.bin` 固定 384 bytes；
- 认证形状为 RSA-3072，而不是 GB202 FMC 常见的 P-384 签名形状；
- 编排器把 selector 设为 `1`；可见 payload 精确为 `u16 selector || u16 0x0348 || u64 qword0 || hash48 || pubkey384 || sig384 || u64 qword1 || u16 transfer_len`，总长 `0x346`；常量 `0x348` 的长度口径仍未知；
- 最终调用 FSP sender，use-case/command 为 `0x0f`；
- 成功响应必须恰为 4 bytes，值为 `0x0000000f`；长度不为 4 返回错误，值不匹配返回 `0x21f`。

关键证据文件：

- `ghidra_fuserework_flow.c`
- `ghidra_fuserework_orchestrator.c`
- `ghidra_fsp_sender_18a0d40.c`
- `ghidra_fsp_sender_helpers.c`
- `FUSEREWORK_ABI.md`

### mode-2 helper 定向 carving

按 MODS mode-2 解析器恢复的 `flags/type/header_size` 与分段长度关系扫描 4 GiB 镜像：

- 找到 5 个唯一 type-2 helper 容器，包括已知 `fub_ga100.bin`；
- 4 个额外容器也嵌在 MODS ELF 中；
- 唯一明显低熵容器 `e466ed...` 可完整按 Falcon fuc5 反汇编，DMEM 日期为 `May 4 2017`；
- 其余 type-2 容器为 Falcon fuc5 / encrypted FUB 形态；
- 未发现 Blackwell RISC-V FuseRework 明文 helper。

### MODS FSP sender 全调用点审计

枚举 MODS ELF 中所有 7 个直接 `call 0x18a0d40`：

- 命令仅见 `0x0c`、`0x0e`、`0x0f` 和低字节 `0x82`；
- 响应长度只见 4、12、24 bytes；
- `0x0f` 为 FuseRework；`0x0e` 调用点为遥测/时钟类固定小响应；
- 没有发现携带 v6 crypto descriptor 并把 `0x29400–0x37000` 级明文返回 host vector 的直接 decrypt wrapper。

这不证明 FSP 内部没有解密服务，但该 MODS build 不提供明显的 bulk plaintext 回读调用。详见 `FSP_SENDER_CALLSITE_AUDIT.md`。

### MODS FAT32 删除项与未分配空间

对原始 `MOD570_215.img` 做 FAT32 取证：

- 4 个 `FUSERE~*.BIN` 删除项恢复后均为 1,608-byte 旧 `fuseread_*` 对象，且簇内容已被覆盖，不是目标四件套；
- 删除目录项中没有可恢复的 48-byte / 384-byte 独立认证文件；
- 恢复了删除的 `mods.toc`，但未从中得到目标四件套正文；
- 从镜像 carve 出 84 条结构成立的 GFW v4 记录、45 个唯一容器；
- GFW image 前 `0x340` 的布局闭合为 `384B pkey || 384B sig || 48B SHA-384 || 16B padding || image`；
- 84 条记录中 78 条的保存 SHA-384 与 image 精确匹配，共 25 个唯一公钥；
- 这些对象均可归入常规嵌入固件/镜像残留，没有识别出独立的 `fuserework` 四件套。

GH100、GB10B、GB20B 的公开 debug GFW 使用同一 RSA-3072 公钥，该公钥也出现在 MODS 镜像的常规 GFW 认证域中；但缺失独立的 `fuserework_debug_gfw_pub_key.bin`，因此不能据此证明返修信任域必然复用该钥。

### 认证材料作为错误 AES/KDF 输入的排查

对 78 套 SHA-384 闭合的 GFW 认证材料做额外“坏实现”检查：

- 公钥、签名、hash 的首/末 32 bytes、SHA 派生和折叠异或：587 个唯一 AES-256 候选，1,174 次 GCM 认证，0 命中；
- 认证材料生成 387 个 root，再做 SP800-108/Thor/直接 HMAC-SHA256 派生：34,830 个唯一 key、69,660 次 GCM 认证，0 命中。

这排除了把公开 RSA 认证材料直接或经这些常见 HMAC 方式误用为 `FSP_RUN` data key 的实现缺陷。

### `frb_ga100.bin` 与公开 FieldDiag 包装器

- `frb_ga100.bin` 可用 Falcon fuc5 反汇编，属于旧代 GA100 返修/熔丝 helper；它不是 Blackwell FSP 明文，也不能替代 RISC-V `fuserework.bin`。
- 公开 `DGXDiagOS` 仓库只有旧 DGX FieldDiag 菜单/日志包装脚本，不携带 FieldDiag 二进制。
- 名为 `nvidia_mfg_bridge` 的公开仓库实际是 DLSS/帧生成 Mod，与 NVIDIA 制造/返修工具无关。

## 第四轮更新：合法 FieldDiag 获取路径

### 官方访问条件

Supermicro FAQ 44778 明确给出：

- NVOnline ID：`1124962`
- 版本：`629-INT27-DIAG-008`
- 发布日期：2026-02-23
- 描述：NVIDIA Blackwell GPU Field Diagnostics (x86)

公开页面不提供文件名、大小或校验值，只要求到 NVOnline 获取。NVIDIA AppHub 官方 FAQ 说明：

- 付费产品用户需 Entitlement Certificate，并使用公司邮箱注册；
- trial/evaluation 需从对应产品页申请并经批准；
- NFR 需组织已加入 NPN；
- OEM 需已加入 Direct OEM Portal；
- 普通 NVIDIA 账号本身不会产生这些 entitlement；
- NVOnline 直接文档入口为 `https://partners.nvidia.com/DocumentDetails?DocID=1124962`；实际下载 URL 还需要授权会话的 `SiteID`；
- NVOnline 条款将访问限定给与 NVIDIA 有 NDA/书面合作关系并获具体文档授权的合作伙伴，不能把普通 AppHub/Support 账号等同于下载权限。

### 实际账户与申请结果

使用真实 Chrome 的现有登录态完成 NVIDIA 邮件安全验证后：

- 标准 NVIDIA 账号可正常验证；
- AppHub 仍返回 `We were unable to verify your account`，确认缺少企业 entitlement，而非密码/2FA 问题；
- Gmail 中未找到历史 `Entitlement Certificate`；
- 未购买产品、未接受 NDA、未冒充 OEM/NPN/企业客户；
- 已通过官方无登录 Enterprise Support 表单，以 `Independent Researcher` 如实提交免费咨询；
- 产品分类：`Support Portals` → `NVIDIA Enterprise Support Portal`；严重程度 S4；
- 案例编号：`01303006`；确认邮件已收到；
- Enterprise Support 回复其范围仅覆盖 DGX 与已授权的 Tesla M 及以上产品，并转介 Consumer Support；
- Consumer Support 的 ticket 与 live-chat 端点反复返回 Oracle `Technical Difficulties`；
- 在同一 case 中追问负责 NVOnline / Field Diagnostics 的正确团队并请求内部转派；Enterprise Support 仍只要求联系 Consumer Support，没有转派或提供负责人；
- case 随后被自动关闭，关闭邮件中的“超过 30 天”与当天提交时间矛盾，应为错误模板；没有提供下载、entitlement 或独立研究者访问路径。

提交内容、回复与确认记录保存在 `NVIDIA_ENTERPRISE_CASE_01303006.md`。

## 第五轮更新：公开 DGX Spark FieldDiag 580 包

用户提供了 `/home/user/nvidia-fieldiag/`，其中有四个公开 ARM64 `dgx-spark-fieldiag` 包。只读递归审计得到：

- 1.0.7/1.0.8/1.0.9 内嵌同一个 AArch64 `fieldiag` ELF，SHA-256 `09babac01221b2a440903149c7a88b38dec2a97a18e1dff7b55b1e69ba609c16`，内部版本 `580.120 / 629.580.36`；
- 2.0.4 的 ELF SHA-256 为 `383147f07018911fe55537dd7a35eced01ac9c4b65873dc55dd634fe35483b48`，内部版本 `580.116 / 629.580.34`；
- 两个 ELF 都只有错误/名称表中的 `FSP_RUN` 字符串，严格 v6 envelope 扫描为 0；
- 归档成员中不存在 `fuserework.bin` 或三个 `fuserework_debug_gfw_*` sidecar；
- AArch64 反汇编确认 580 仍固定读取 `48B hash + 384B pubkey + 384B signature`，发送 outer command `0x0f`，响应仍为 4-byte `0x0f`；
- 枚举 AArch64 sender 的全部 7 个直接 `BL` caller，命令/响应仍只有 `0x82` 小状态、`0x0c` 4-byte、FuseRework 4-byte ACK 和 `0x0e` 的 12/24-byte telemetry；没有新增 bulk decrypt-to-host；
- mode-2 carving 得到 34 个唯一对象：5 个 type-2/type-3 helper 与 570.215 逐字节相同，未新增 Blackwell FuseRework helper；另有 29 个新版 type-4 GFW；
- 其中 13 个 GFW 与 NVIDIA 公共 `open-gpu-kernel-modules` tag `580.119.02` 的 GSP-RM GFW 逐字节对应，包括 GB202 prod/debug/CC prod，证明它们不是隐藏改名的 `fuserework.bin`；
- 剩余 16 个私有 type-4 对象也全部位于标准四成员 `IMAGE/HASH/PKEY/SIG` bindata archive/getter 结构中；没有任何 getter 或 archive 与外部 `fuserework.bin` 加载链建立 xref，因此不应标为 FuseRework；
- GB202 debug GFW 使用 97-byte ECC 公钥和 96-byte 签名，与 FuseRework 固定要求的 RSA-3072 `384/384` sidecar 不兼容；
- 对新恢复的 64 个唯一认证材料生成 851 个直接候选并做有界 KDF：共 212,466 次 GCM tag 检验，0 命中。

完整证据见 `DGX_SPARK_FIELDDIAG_AUDIT.md`、`FIELDDIAG580_AARCH64_FSP_SENDER_AUDIT.md`、`FIELDDIAG580_PRIVATE_GFW_ATTRIBUTION.md` 与 `external_dgx_spark_fielddiag/`。这些公开包提供了更晚的实现和固件对照，但不是 NVOnline 的 Blackwell PCIe FieldDiag `629-INT27-DIAG-008`。

## 第六轮更新：论坛与公开网盘搜索

分别覆盖英语、中文、俄语/东欧维修社区，以及 GitHub/GitLab/Gitee/Hugging Face/Internet Archive/Zenodo/NVIDIA 公共目录和常见网盘。结果：

- 精确文件名 `fuserework.bin` 和三个 `fuserework_debug_gfw_*` sidecar 在公开代码/归档索引中仍为 0 个可验证文件命中；
- `629-INT27-DIAG-008` 的唯一高可信公开证据仍是 Supermicro FAQ → NVOnline DocID `1124962`，下载本体受组织 entitlement 控制；
- VLab 的公开 MEGA 目录可见 570.133/570.151/570.215/570.278 与 MODS 520 包，未含 MODS 580 或 FuseRework 文件；
- 找到公开 Google Drive `Mats Mods by Meister V6_Final.7z`（22,378,300,632 bytes）。没有下载完整 22 GB archive；通过 HTTP Range 读取并校验 7z header，流式解压前 64 MiB packed 数据，再解析 GPT/Btrfs 元数据，重建出 12,268 条当前文件路径；
- 该 62 GB 镜像的 `/home/RTX5XXX` 仅含 `540.263_5060`、`570.133_5080`、`570.151_5090`、`570.215_5070`、`570.215_5080`、`570.278_5050`，没有四件套、目标 FieldDiag 或 standalone MODS 580；其 570.151 文件尺寸与本地既有包一致，因此避免了重复下载；
- 另一公共 Drive 的 `3.rar` 经 RAR5 QuickOpen 远程 range 检查，仅含一个 2021 年的加密 `3.pmf`；`OVERKILL2.vhdx` 当前被 Drive quota 阻断，且没有目标文件正向证据，未尝试复制/绕过；
- 维修论坛和商业 USB 仅宣称支持 RTX 5090，公开可见内容仍是常规 MODS/MATS 集合；没有 `fuserework`/FieldDiag 工件证据，也未购买、加群或私聊。

证据见 `WEB_HUNT_ENGLISH.md`、`WEB_HUNT_CHINESE.md`、`WEB_HUNT_RU_REPAIR.md`、`WEB_HUNT_INDEX_ARCHIVES.md`、`WEB_HUNT_MEISTER_V6.md` 与 `web_hunt_meister_v6/`。

## 当前物料墙与后续

目前仍缺：

- `fuserework.bin`
- `fuserework_debug_gfw_hash.bin`
- `fuserework_debug_gfw_pub_key.bin`
- `fuserework_debug_gfw_sig.bin`
- 正确的 AES-256-GCM data key 或可验证的 KDF/hardware-root 路径

后续优先级：

1. 继续恢复 crypto descriptor v1 私有字段与片内 KDF/hardware-root 消费路径；现有 host 侧只能看到 raw-key AES-256-GCM helper，不能看到 FSP root/key producer。
2. 继续搜寻 debug/engineering FSP 或合法 OEM/NVOnline Blackwell PCIe FieldDiag 镜像，重点文件名仍为 `fuserework.bin`。
3. 只有获得 580 私有 bindata 的符号/构建清单时再继续精确命名那 16 个对象；现有结构证据已足以排除“明显隐藏的外部 FuseRework 文件”。
4. 真机 oracle、FSP 命令、复位、写入、刷写或熔断仍未授权执行。

## 本轮收束

按用户决定，本轮研究停止在“未获得明文”的状态。继续重复现有离线分析和公开搜索的预期收益过低；后续仅在出现新工件或用户新增真机实验授权时恢复。

最终状态、阻塞点、禁止重复事项和恢复步骤见：

`FINAL_STATUS_AND_RESUME_GUIDE_20261027.md`

# GB202 FSP 明文研究：最终状态与恢复指南

日期：2026-10-27

## 结论

本轮工作未获得可直接交给 Ghidra/反汇编器的 GB202 `FSP_RUN` 明文。

继续对现有本地材料做同类静态扫描、普通零售 VBIOS 收集、公开密钥组合或常见 KDF 字典扩展，预期收益已经很低。当前工作在此收束，保留全部证据和可复现脚本；只有出现新的关键工件或另行授权真机实验时才值得恢复。

## 已建立的主要事实

### 1. 目标固件与样本范围

- 本地全量扫描得到 58 条有效 `FSP_RUN` 记录。
- GB202 当前只有 6 个唯一 payload/descriptor 对象。
- 23 份普通 RTX 5090 VBIOS（包括 ASUS XOC）复用同一个 `FSP_RUN`，继续批量收集普通零售 BIOS 基本没有信息增益。
- RTX 5090D、RTX PRO 和服务器 Blackwell 样本提供了少量不同对象，但没有公开明文对照。

### 2. 密码模型

MODS 570 和 FieldDiag/MODS 580 的软件路径均支持以下模型：

```text
AES-256-GCM
key: 32 bytes
IV: 12 bytes
AAD: empty
TAG: 16 bytes
```

所有成功判断都以 GCM tag 验证为准，不以熵、猜测头部或“像代码”为证明。

v6 外层 descriptor 长度为 `0x50`；`+0x28` 存在 40-byte 子结构：

```text
01 28 01 01 || 8-byte object ID || 28 opaque bytes
```

`0x28` 与子结构长度一致；第一个 `01` 很可能是版本。最后两个 `01`、精确字段名和片内 KDF 配置仍未知。

### 3. 已排除的 key/KDF 路线

已经测试：

- 公开 debug-key family；
- AES-128 旧假设及修正后的 AES-256-GCM 模型；
- MODS 邻近数据和动态 key/wrapped-key 猜测；
- 保存的 128 KiB fuse dump 的窗口、变换、hash 和 HMAC/KDF；
- GFW 公钥、签名、SHA-384 认证材料；
- SP800-108、Thor 风格和直接 HMAC-SHA256 派生；
- FieldDiag 580 新恢复的认证材料。

全部 GCM tag 检验均为 0 命中。已保存的可读 fuse 区没有以这些直接或常见派生方式暴露 data key；不能据此排除芯片内部不可读 root secret。

### 4. FuseRework 路线

主文件名已经闭合为：

```text
fuserework.bin
```

还需要：

```text
fuserework_debug_gfw_hash.bin      48 bytes
fuserework_debug_gfw_pub_key.bin   384 bytes
fuserework_debug_gfw_sig.bin       384 bytes
```

恢复的请求布局：

```text
u16 selector
u16 0x0348
u64 qword0
48-byte hash
384-byte RSA public key
384-byte RSA signature
u64 qword1
u16 transfer_len
```

可见请求 vector 实际长度为 `0x346`；`0x348` 字段的长度口径仍未闭合。

外层 FSP command 为 `0x0f`；成功响应仅为 4-byte `0x0000000f` ACK。该接口不是 host plaintext 回读接口。

### 5. MODS 570/580 sender 审计

- MODS 570.215 的通用 FSP sender 有 7 个直接调用点。
- AArch64 FieldDiag/MODS 580 的 sender 同样只有 7 个直接调用点。
- 已见命令为小型状态请求、`0x0c`、FuseRework `0x0f` 和 telemetry `0x0e`。
- 响应只消费或严格要求 4、12、24 bytes。
- 没有发现把约 `0x29400–0x37000` 级 FSP 明文返回主机的 bulk wrapper。
- sender 内的间接调用是下层 transport vtable 分派，不是已证明的另一个上层 decrypt API。

### 6. MODS/FieldDiag 工件取证

#### MODS 570

- 570.151、570.215、570.278 的相关 FuseRework helper 集合一致。
- 独立 `frb_ga100.bin`/`fub_ga100.bin` 属于旧 GA100/Falcon 路线，不是 Blackwell RISC-V FuseRework。
- FAT32 删除项、未分配空间和 GFW carving 未恢复目标四件套。
- GB202 570.151 制造包的 ENG/NOCHK recipes、`gldGB202.bin` 和脚本没有目标文件正文或明确外部返修路径。

#### MODS/FieldDiag 580

用户提供的公开 DGX Spark FieldDiag 包内含 AArch64 `mods.580/fieldiag`：

- 580.120 / 629.580.36；
- 580.116 / 629.580.34。

严格 mode-2 carving 得到：

- 5 个旧 type-2/type-3 helper，与 570.215 逐字节一致；
- 29 个 type-4 GFW；
- 其中 13 个逐字节匹配 NVIDIA 公开 `open-gpu-kernel-modules` 580.119.02 GSP-RM GFW，包括 GB202 prod/debug/CC prod；
- 剩余 16 个也属于标准 `IMAGE/HASH/PKEY/SIG` bindata archive/getter 结构，未与外部 FuseRework 文件加载链建立关联。

公共 GB202 debug GFW 使用 ECC 97-byte public key / 96-byte signature；FuseRework 明确要求 RSA-3072 384/384 sidecars，因此两者不能直接互换。

FieldDiag 580 中没有有效 `FSP_RUN` envelope，也没有目标四件套。

### 7. NVIDIA 与公开网络路径

- 目标官方条目：`629-INT27-DIAG-008`。
- NVOnline DocID：`1124962`。
- 描述：NVIDIA Blackwell GPU Field Diagnostics (x86)。
- 普通 NVIDIA 账户没有组织 entitlement；Enterprise Support case 被转回 Consumer Support 后关闭，没有提供下载路径。案例编号与账户材料未纳入公开副本。

公开网络搜索覆盖英语、中文、俄语/东欧社区、GitHub/GitLab/Gitee、Hugging Face、Internet Archive、Zenodo、NVIDIA 公共目录和常见网盘。

精确四文件名和目标 FieldDiag archive 均没有可验证的公开文件命中。

对公开 `Mats Mods by Meister V6_Final.7z` 进行了无需完整下载的远程取证：

- 7z 大小 22,378,300,632 bytes；
- 内部为约 62 GB Btrfs 镜像；
- 通过 HTTP Range、LZMA2 前缀解压和 Btrfs metadata 重建出 12,268 条当前路径；
- RTX5XXX 目录只包含常规 540/570 MODS 包；
- 没有四件套、目标 FieldDiag 或 standalone MODS 580。

VLab MEGA 目录也仅含已知 520/570 包。没有必要重复下载这些大型镜像。

## 当前真正的阻塞点

至少需要下列任一新证据：

1. `fuserework.bin` 与对应 RSA-3072 sidecars；
2. 合法取得的 x86 Blackwell FieldDiag `629-INT27-DIAG-008`；
3. GB202 debug/engineering/pre-production `FSP_RUN`，最好有同明文 prod/debug 对照；
4. FSP crypto descriptor/KDF 消费者的明文代码或符号；
5. 能证明 data key 来源的硬件 root/KDF 配置；
6. 明确授权的真卡 oracle 实验。

## 不建议重复的工作

除非出现新证据，不再建议：

- 批量下载普通 RTX 5090 零售 BIOS；
- 扩大无结构 AES key 字典；
- 继续尝试 AES-128；
- 将 GFW public key/signature/hash 当作直接 AES key；
- 重复扫描 MODS 570.151/570.215/570.278 或 FieldDiag 580 中相同 helper；
- 下载已通过远程文件树确认只含现有包的 20+ GB 社区镜像；
- 把错误名 `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED` 当成 host decrypt API；
- 把 GSP-RM 侧代码误认为 FSP 本体明文。

## 如果以后恢复工作

按优先级：

1. 对新获得的 archive 先保存原件、记录来源、计算 SHA-256，并只读列出成员；搜索四个完整文件名。
2. 对新 debug/engineering VBIOS 运行现有 inventory，并以 GCM tag 验证任何候选解密。
3. 若取得 `fuserework.bin`，先做格式/签名/目标架构离线分析，不直接发给 GPU。
4. 若只有真机路线，先写风险设计，限定只读缓冲、命令、超时和恢复步骤；发送命令、复位、写入、刷写或熔丝前再次取得用户明确授权。

## 安全边界

2026-10-27 后续决定：用户明确不继续真机 FSP/GSP 操作。本地历史故障与风险复核见：

[`../HARDWARE_DO_NOT_TOUCH_RISK_SUMMARY_20261027.md`](../HARDWARE_DO_NOT_TOUCH_RISK_SUMMARY_20261027.md)

本轮没有：

- 向 GPU/FSP 发送命令；
- 映射或写入真实 GPU BAR；
- 复位设备；
- 刷写 VBIOS/EEPROM；
- 修改或烧写熔丝；
- 运行来源不明的 MODS/FieldDiag；
- 购买、付费、接受 NDA、冒充 OEM/NPN/企业客户；
- 绕过登录、提取码、下载额度或组织 entitlement。

## 关键文件索引

主报告与总结：

- `REPORT.md`
- `FUSEREWORK_ABI.md`
- `FSP_SENDER_CALLSITE_AUDIT.md`
- `FUSEREWORK_CALLCHAIN_DIFF.md`
- `V6_CRYPTO_KDF_CONSUMER_AUDIT.md`
- `DGX_SPARK_FIELDDIAG_AUDIT.md`
- `FIELDDIAG580_AARCH64_FSP_SENDER_AUDIT.md`
- `FIELDDIAG580_PRIVATE_GFW_ATTRIBUTION.md`
- `GB202_MFG_HIDDEN_REWORK_AUDIT.md`
- NVIDIA support case record（私有，不公开）

公网搜索：

- `WEB_HUNT_ENGLISH.md`
- `WEB_HUNT_CHINESE.md`
- `WEB_HUNT_RU_REPAIR.md`
- `WEB_HUNT_INDEX_ARCHIVES.md`
- `WEB_HUNT_MEISTER_V6.md`

主要实验目录：

公开副本：`fsp_plaintext_audit_20261027/`

## 最终状态

**Stopped without plaintext.**

原因不是 AES 被破解失败，而是现有材料没有暴露正确 data key、片内 KDF/root 或合法 plaintext-export 路径。恢复工作的条件应是“出现新工件或新增硬件实验授权”，而不是继续重复相同搜索空间。

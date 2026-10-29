# NVIDIA R580.126.09 FSP / RESET PLM 公开范围审计

日期：2026-07-21
范围：仅 NVIDIA 官方公开文档与官方 `NVIDIA/open-gpu-kernel-modules` 两个发布快照；全程离线/网页只读，没有接触设备、驱动节点、BAR/MMIO、PCI config，也没有提出或执行 reset/固件操作。

## 结论先行

1. **PUBLIC FACT：** NVIDIA 的 R580.126.09 Data Center Linux release note 明确说，FSP 会依 PLM 条件决定是否 reset；该次修复把某个 **RESET PLM** 做 source isolation，使 FSP 无法访问它。官方原文中可安全保留的两个短语是 “conditionally reset depending on the PLM” 和 “the source isolates the RESET PLM so FSP cannot access it”。
2. **产品边界：UNKNOWN。** 该 bullet 没有产品、board、PCI ID、架构或 chip codename。它出现于 Data Center Driver 文档，只能证明这是 R580.126.09 发布内容；不能证明所有受支持 Data Center 产品都曾受影响，更不能从该 bullet 单独外推到 GeForce RTX 5090 / GB202。
3. **对象边界：UNKNOWN。** 可确定的 actor/requester 是 **FSP**，可确定的受保护对象类别是一个 **RESET privilege-level mask**；但 release note 没说它属于 GSP、FSP、某个 Falcon、PMC/reset controller、NVSwitch/SOE，还是其他 engine，也没有地址或字段值。
4. **GB202 上存在一个很接近但仍不能等同的公开候选：** 官方 OpenRM 明文代码让 GB202 使用 `kgspResetHw_GB100()`；该函数轮询 `NV_PGSP_FALCON_RESET_PRIV_LEVEL_MASK` 的 PL0 read/write enable，再 reset GSP。这个对象是 **GSP Falcon RESET PLM**。它证明“GB202 的公开 reset 路径确实有 RESET PLM gating”，但相关文件在两个 tag 间完全未变，release note 也没有把 fixed issue 指向它。因此只能列为 **candidate / generic corroboration**，不能定案为 bullet 所指对象。
5. **不能关联到项目中的 GB202 fuse/boot/base reset coupling。** R580 公开控制头只发布 reset type `4/5/8 = BOOT_DEVICE_FUSE/BOOT_DEVICE/BASE`；没有发布项目中三个 coupling target、相邻 PLM、FSP fallback 或 coupling 生命周期。release note 也没有 `coupling`、type 4/5/8 或 PMC 字样。故本条最多支持“FSP reset 决策可能受 PLM 可见性影响”这一通用命题，不能支持“它修了 GB202 coupling”“它解释 base/fuse/boot 级联”或“它改变了 coupling latch/raw 值”。
6. **580.119.02 → 580.126.09 没有对应的明文 source-isolation 实现。** 相关明文 FSP/GSP/PLM 文件要么 byte-identical，要么只有空行删除。能看到的是 GB100 与 GB202 两套 GSP-RM/FMC/GFW 自动生成 binary arrays 同时整体更新。它们是可能的交付载体之一，但公开 diff 不能把其中任何 byte delta 归因到这个 fixed issue；也不能排除实际改动位于未发布的 GFW/FMC source、VBIOS/FSP firmware 或 NVIDIA 共享内部树的其他组件。

因此本项目中的推荐定位是：

> **NVIDIA 官方通用旁证，不是 GB202 reset-coupling 的对象归属、因果或修复证据。**

## 证据等级

- **PUBLIC FACT**：NVIDIA 官方文档或公开源码直接陈述/定义。
- **OFFICIAL-STATIC**：官方发布 tag 的源码、生成表或 tag-to-tag diff 可直接复核。
- **INFERENCE**：多个官方事实相容，但官方没有完成对象/产品归属。
- **UNKNOWN**：公开材料不能决定；不得升级措辞。

## 1. 官方发布对象与可复核 revision

官方来源：

- [R580.126.09 Data Center Linux release note](https://docs.nvidia.com/datacenter/tesla/tesla-release-notes-580-126-09/index.html)
- [对应 NVIDIA PDF（RN-08625-580 v5.1）](https://docs.nvidia.com/datacenter/tesla/pdf/NVIDIA_Data_Center_GPU_Driver_Release_Notes_580_v5.1.pdf)
- [`open-gpu-kernel-modules` 580.126.09 release](https://github.com/NVIDIA/open-gpu-kernel-modules/releases/tag/580.126.09)
- [官方 tag comparison：580.119.02...580.126.09](https://github.com/NVIDIA/open-gpu-kernel-modules/compare/580.119.02...580.126.09)

本地 official-origin clone (`origin=https://github.com/NVIDIA/open-gpu-kernel-modules.git`) 验证结果：

| tag | annotated-tag object | peeled commit | commit date | 官方链接 |
|---|---|---|---|---|
| `580.119.02` | `e5bc65acc55a86ec74ba86724b0ce6aedd6bad27` | `de3d54abf3dacfb9293d96ed1aa31b449e0d6518` | 2025-12-11 | [commit](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/de3d54abf3dacfb9293d96ed1aa31b449e0d6518) |
| `580.126.09` | `f394189a8606429ca06267f54e818fd207c38ff1` | `455d4b8b75f56d7483489c255705d064fdedf3c6` | 2026-01-13 | [commit](https://github.com/NVIDIA/open-gpu-kernel-modules/commit/455d4b8b75f56d7483489c255705d064fdedf3c6) |

两个 peeled commit 是直接 parent/child，区间只有一个 commit；GitHub compare 也报告 `1 commit / 67 files changed`。但这**不等于一个 internal CL**。NVIDIA 自己在 [README lines 89-101](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/README.md#L89-L101) 说明该仓库主要是每个 driver release 的 snapshot，通常每个 release 只有一个 commit，且不提供共享内部树中每项变更的独立 revision history。因此 release note 所说的 “fix CL” 不能从公开 commit 中单独恢复或建立一对一文件归属。

## 2. Release note 本身能确定和不能确定什么

### 2.1 能确定

R580.126.09 页面自称是 **Release 580 family of NVIDIA Data Center GPU Drivers for Linux**，发布日期为 2026-01-13；Fixed Issues 中存在上述 FSP/PLM bullet。这支持以下最窄陈述：

```text
FSP has a reset decision path dependent on a PLM.
NVIDIA fixed one issue by source-isolating an unspecified RESET PLM from FSP.
```

这里把 “source” 解释为访问发起源/source isolation，而不是“公开 source code”，属于有公开字段结构支持的 **INFERENCE**。这一解释与 NVIDIA 已发布 PLM 字段中存在 `SOURCE_READ_CONTROL`、`SOURCE_WRITE_CONTROL`、`SOURCE_ENABLE` 相容；见 [LS10 Falcon v4 RESET PLM layout](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/common/inc/swref/published/nvswitch/ls10/dev_falcon_v4.h#L74-L121)。但该 header 属于 **NVSwitch LS10**，只能证明 NVIDIA PLM 具有 source-specific access-control 这一公开结构，不能把其中任何 source bit 映射为 GB202 FSP。

### 2.2 不能确定

该 bullet 没有给出：

- 原始故障现象、触发条件、Xid/status 或 reset 类型；
- 受影响产品/架构/stepping；
- RESET PLM 的 owner、engine、地址、reset target 或 source ID；
- 被移除的是 read、write 还是两者访问；
- “条件 reset” 的 true/false 分支行为；
- 与 fuse/boot/base coupling、SBR、FLR、hot reset 或 full-chip reset 的关系；
- internal CL 编号或公开 source commit。

特别要注意，同一个官方树内 `RESET_PRIV_LEVEL_MASK` 并不唯一：至少公开了 GSP Falcon、NVSwitch LR10 SOE Falcon、NVSwitch LS10 generic Falcon 等对象。因此不能把不带 owner 的 “RESET PLM” 自动解析成项目正在研究的 PMC-relative coupling PLM。

## 3. 产品范围：Data Center 文档、驱动兼容与 fixed-issue 适用性必须分开

### 3.1 文档范围

[该 release note 的 supported-products section](https://docs.nvidia.com/datacenter/tesla/tesla-release-notes-580-126-09/index.html#supported-nvidia-data-center-gpus) 列出 HGX/GB200/B200/Hopper 以及多种 RTX PRO Blackwell 产品。Fixed Issues 列表是 release-level 汇总；单个 bullet 没有产品标签。故：

- “该修复随 Data Center Driver 580.126.09 发布”是 **PUBLIC FACT**；
- “所有列出的 Data Center GPU 都受影响”是 **UNKNOWN / 不支持**；
- “该 bullet 特指某一 RTX PRO 6000 Blackwell SKU”也是 **UNKNOWN**。

### 3.2 RTX 5090 只达到版本兼容，不达到问题归属

独立的 NVIDIA Linux x86_64 580.126.09 README 确实列出 [GeForce RTX 5090, PCI ID 2B85](https://download.nvidia.com/XFree86/Linux-x86_64/580.126.09/README/supportedchips.html)，官方 open-module [README compatible-GPU table](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/README.md#L950-L958) 也包含该产品。官方生成 name table 同样有 [2B85 → NVIDIA GeForce RTX 5090](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/nvidia/generated/g_nv_name_released.h#L5418)。

这些事实只证明 **580.126.09/open modules 支持这张卡**。Data Center fixed-issue bullet 没列 GeForce 产品，驱动支持列表也不携带 per-fix applicability。因此推理链：

```text
580.126.09 supports RTX 5090
AND 580.126.09 contains an FSP/RESET-PLM fix
THEREFORE the fix applies to RTX 5090
```

是无效的合取后归属，不能采用。

## 4. 公开源码里最接近的对象：GSP Falcon RESET PLM

### 4.1 明文代码

[`kernel_gsp_gb100.c` lines 36-85](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/nvidia/src/kernel/gpu/gsp/arch/blackwell/kernel_gsp_gb100.c#L36-L85) 提供了明确行为：

- `_kgspWaitForResetAccess()` 同时测试
  `NV_PGSP_FALCON_RESET_PRIV_LEVEL_MASK.READ_PROTECTION_LEVEL0` 与
  `.WRITE_PROTECTION_LEVEL0`；
- `kgspResetHw_GB100()` 在 suspend/shutdown reset path 等待 GSP lower PLM，允许 RM 获得 reset access；
- timeout 文本明确称它为 “GSP reset PLM”。

[`gb100/dev_gsp.h` lines 60-66](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/common/inc/swref/published/blackwell/gb100/dev_gsp.h#L60-L66) 给出的公开符号和地址是：

```text
NV_PGSP_FALCON_RESET_PRIV_LEVEL_MASK = 0x1103c4
READ_PROTECTION_LEVEL0               = bit 0
WRITE_PROTECTION_LEVEL0              = bit 4
```

### 4.2 GB202 确实使用这个 reset HAL

官方生成 dispatch [`g_kernel_gsp_nvoc.c` lines 1070-1092](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/nvidia/generated/g_kernel_gsp_nvoc.c#L1070-L1092) 把 GH100、T234/T264、TU/GA/AD 分支列出后，其余支持的 Blackwell chip 落到 `kgspResetHw_GB100`。同一生成文件以专属 `group 2 / bit 0x20` 明确识别 [GB202](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/nvidia/generated/g_kernel_gsp_nvoc.c#L1757-L1770)，并在 firmware archive dispatch 中把 [GB202/203/205/206/207 映射到 GB202 images](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/nvidia/generated/g_kernel_gsp_nvoc.c#L796-L815)。因此“公开 R580 OpenRM 的 GB202 GSP reset path 使用上述 GSP RESET PLM 检查”是 **OFFICIAL-STATIC**。

### 4.3 为什么仍不能把它认定为 release-note 对象

五个关键文件的 tag blob 审计如下：

| file | 580.119.02 blob | 580.126.09 blob | 结果 |
|---|---|---|---|
| `fsp/arch/blackwell/kern_fsp_gb202.c` | `15d2fb1c...` | `15d2fb1c...` | byte-identical |
| `gsp/arch/blackwell/kernel_gsp_gb100.c` | `27a87a87...` | `27a87a87...` | byte-identical |
| `generated/g_kernel_gsp_nvoc.c` | `c1b0dbea...` | `c1b0dbea...` | byte-identical |
| `published/blackwell/gb100/dev_gsp.h` | `b6665061...` | `b6665061...` | byte-identical |
| `fsp/arch/hopper/kern_fsp_gh100.c` | `6cc75cb3...` | `88fe0f6b...` | 只删除 2 个空行；忽略空白后无 diff |

也就是说，这个漂亮的 GSP RESET PLM 候选**不是 580.126.09 新增或修改的明文逻辑**。Release note 所指对象可能与它相容，但没有公开 delta 或官方文字完成归属。不能把“树中唯一容易看到的 GPU RESET PLM”误当成“fixed issue 必然指它”。

## 5. 580.119.02 → 580.126.09 diff：明文逻辑与 bindata

### 5.1 明文负结果

官方 compare 共 67 files。排除 `g_bindata_*` 后，对所有新增/删除的实际行搜索 `PLM|PRIV_LEVEL_MASK|FSP|RESET`，只有：

- 新增一个 PFB `LOCAL_MEMORY_RANGE__PRIV_LEVEL_MASK` 定义；
- NVLink fabric-health 的 `RESET_REQUIRED` 枚举/判断变化；
- LOCAL_MEMORY_RANGE reset/FSP boot 的说明；
- 上述 Hopper FSP 文件的空行删除。

没有任何 changed line 包含 `PLM`，也没有 RESET PLM source-control/source-enable 写法。定向检查 `src/nvidia/src/kernel/gpu/fsp` 与 `.../gsp` 后，唯一有语义的 GSP 明文修改是 Turing bootstrap 增加“processor 已 suspended”判断，与 PLM/source isolation 无关。

所以准确结论不是“整个 diff 只有 bindata”，而是：

> **diff 另有许多不相关的明文 driver 修复；但找不到与该 FSP/RESET-PLM bullet 对应的明文实现。相关实现若随此 repo 交付，只能藏在更新后的 binary payload 中，或根本不在此 repo。**

### 5.2 同时变化的 10 个 firmware bindata C 文件

五类 archive 各有 GB100 与 GB202 一份，合计十个：

| archive family | GB100 | GB202/GB20x | 生成文件自述 |
|---|---:|---:|---|
| `ConcatenatedFMC` | changed | changed | binary prod image |
| `GspRmBoot` | changed | changed | debug/prod image + desc |
| `GspRmCcFmcGfwProdSigned` | changed | changed | image + hash + sig + key |
| `GspRmFmcGfwDebugSigned` | changed | changed | image + hash + sig + key |
| `GspRmFmcGfwProdSigned` | changed | changed | image + hash + sig + key |

例如官方 [GB202 ConcatenatedFMC bindata](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/nvidia/generated/g_bindata_kgspGetBinArchiveConcatenatedFMC_GB202.c#L25-L40) 明确标记 `AUTOMATICALLY GENERATED`、`FILE TYPE: BINARY`，随后只是 `NvU8[]`；[GB202 GspRmBoot bindata](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/nvidia/generated/g_bindata_kgspGetBinArchiveGspRmBoot_GB202.c#L25-L40) 结构相同。所有这些 payload 的声明 size 在两 tag 间保持不变，byte content 有更新；带签名的 archive 文件还包含 hash/signature arrays。

该事实只支持：

- 580.126.09 携带了新的 GB100 与 GB202 GSP-RM/FMC/GFW payload；
- 这些 payload 处在公开 FSP/GSP boot flow 所选择的 firmware-archive 体系中；例如 [GB202 FSP HAL](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb202.c#L43-L97) 说明 chip reset 后 BootFSM 触发 FSP，RM 等待 FSP boot complete，而 [Hopper+ FSP setup](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c#L975-L1050) 明确准备 GSP-FMC/image boot args 给 FSP command。

它**不支持**：

- fixed issue 一定存在于 GB202 payload；
- GB100 与 GB202 都包含同一 fix；
- changed bindata 是 FSP 自身 firmware（公开名字是 GSP-RM/FMC/GFW，不是一个可直接识别的 FSP ucode image）；
- 任何特定 binary offset/函数/寄存器对应 source isolation。

尤其因为 GB100 与 GB202 两套 payload 同时变化，且 NVIDIA 的公开 commit 聚合整个 release，不能用“GB202 blob changed”作为 product attribution。

此外，`GB100`/`GB202` 在这些函数名中是 archive HAL 分组标签，不是 affected-product 标签。生成 dispatch 会让多个 chip 共用相应 archive；例如 `GspRmBoot_GB202` 至少覆盖 GB202/203/205/206/207，其他 FMC archive 的复用集合还可包含 GB20B/GB20C。故连“changed file 名称”也不能缩成单一 GB202 产品结论。

## 6. 与 GB202 fuse/boot/base reset coupling 的严格边界

官方 R580 控制头 [`ctrl0080bif.h` lines 36-76](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/580.126.09/src/common/sdk/nvidia/inc/ctrl/ctrl0080/ctrl0080bif.h#L36-L76) 只证明：

```text
type 4 = BOOT_DEVICE_FUSE
type 5 = BOOT_DEVICE
type 8 = BASE
```

该文件在两个 tag 间 byte-identical；公开 R580 source 中也没有把这些 type 连到三个 coupling bit/PLM 的明文 caller。由此形成以下结论矩阵：

### 6.1 两类 PLM 必须明确分开

| 项目 | 官方公开的 GSP RESET PLM | 项目 private artifact 中的 coupling gates |
|---|---|---|
| owner / object | `PGSP` / GSP Falcon reset control | PMC/reset-controller-like device entry 下的 fuse/boot/base coupling targets |
| 地址形式 | **绝对公开 PRI 地址 `0x1103c4`** | device-PRI-base relative target `+0x40/+0x44/+0x48`；相邻 access/PLM words `+0x308/+0x30c/+0x310` |
| 公开正式符号 | `NV_PGSP_FALCON_RESET_PRIV_LEVEL_MASK` | R580 published headers **没有**对应 coupling/PLM 正式符号 |
| 明文行为 | `kgspResetHw_GB100()` 等待 PL0 read+write access 后 reset GSP | 固定 private GSP/MODS artifact 中用于 coupling setter/direct-vs-FSP eligibility；不在本次官方 diff 中 |
| 两者等同证据 | 无 | 无 |

因此 `0x1103c4` 是 **GSP Falcon 自身 reset register 的 PLM**，不是 coupling target `+0x40/+0x44/+0x48`，也不是它们的 PLM `+0x308/+0x30c/+0x310`。绝对地址与 device-relative offset、owner 和用途均不同；现有官方资料没有 alias、forwarding 或 shared-state 关系把两类寄存器连在一起。

### 6.2 结论矩阵

| 命题 | 官方公开材料结论 |
|---|---|
| FSP 的 reset 决策可依某个 PLM | **PUBLIC FACT** |
| source isolation 可以禁止指定 requester 访问 RESET PLM | **PUBLIC FACT（该 bullet）** |
| GB202 公开 GSP reset path 检查 GSP RESET PLM | **OFFICIAL-STATIC** |
| bullet 所指 RESET PLM 就是 GSP `0x1103c4` | **UNKNOWN** |
| bullet 适用于 RTX 5090 / GB202 | **UNKNOWN** |
| bullet 所指 RESET PLM 是项目的 `+0x308/+0x30c/+0x310` coupling gate | **不支持 / UNKNOWN** |
| bullet 证明 FSP 依据 fuse/boot/base coupling PLM 选 backend | **不支持** |
| bullet 证明 type 8/base 会级联或镜像 type 4/5 | **不支持** |
| 580.126.09 明文修改 coupling PLM | **否** |
| changed GB202 bindata 可能承载相关未发布逻辑 | **可能，但不可归因** |

与项目既有静态发现最稳妥的接法仅是：

> 项目 private artifact 显示 reset-coupling access predicate / FSP path；NVIDIA R580.126.09 release note 独立表明 FSP reset behavior 确实可能受 PLM visibility 影响。两者在**机制类别**上相容，但没有公开对象 ID、寄存器地址、reset type 或 product tag 将它们闭合为同一机制。

## 7. 可直接用于主报告的措辞

推荐：

> NVIDIA 的官方 R580.126.09 release note 记录过一项 FSP/PLM reset 修复：FSP 会依 PLM 条件决定 reset，修复通过 source isolation 禁止 FSP 访问一个未指明 owner 的 RESET PLM。官方 580.119.02→580.126.09 OpenRM diff 没有对应的明文 PLM 实现，只更新了包括 GB100 与 GB202 在内的聚合 GSP-RM/FMC/GFW bindata。该材料支持“PLM 可见性会影响 FSP reset 决策”的通用机制，但不能把 fixed issue 归属到 RTX 5090/GB202，也不能把 RESET PLM 等同于本项目的 fuse/boot/base coupling PLM。

不得写成：

- “NVIDIA 580.126.09 修复了 RTX 5090 reset coupling”；
- “RESET PLM 已确认是 GB202 PMC coupling PLM”；
- “FSP 一定读取 base/fuse/boot coupling 来决定 reset”；
- “GB202 bindata diff 证明了该 fix 的实现”；
- “source isolation 改写/清除了 coupling bit”；
- “该 fix 证明 base reset 与 fuse/boot 存在硬件级联”。

## 8. 复核命令（全部只读）

```sh
git rev-parse 580.119.02 580.119.02^{} 580.126.09 580.126.09^{}
git rev-list --count 580.119.02..580.126.09
git diff --stat 580.119.02 580.126.09
git diff --name-status 580.119.02 580.126.09
git diff --unified=0 580.119.02 580.126.09 -- ':!src/nvidia/generated/g_bindata_*'
git diff 580.119.02 580.126.09 -- src/nvidia/src/kernel/gpu/fsp src/nvidia/src/kernel/gpu/gsp
git grep -n -i -E 'RESET.{0,40}PLM|PLM.{0,40}RESET|\\bPLM\\b' 580.126.09 -- ':!src/nvidia/generated/g_bindata_*'
git diff --name-only 580.119.02 580.126.09 -- 'src/nvidia/generated/g_bindata_*'
```

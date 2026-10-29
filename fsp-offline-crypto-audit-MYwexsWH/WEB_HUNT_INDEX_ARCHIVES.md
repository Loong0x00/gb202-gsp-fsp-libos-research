# 公开文件索引与代码/归档专项搜索

检查日期：2026-10-27。仅使用无需登录的公开页面/API、公开目录索引和 raw URL；没有尝试绕过访问控制、猜 NVOnline 下载 URL/token、复用登录态或获取私有文件。

## 结论摘要

- **本轮没有找到四个 `fuserework*` 文件的独立公开文件对象，也没有找到 `629-INT27-DIAG-008` 对应包的公开下载 URL/归档。** 这是对已检查索引和路径的结论，不代表文件不存在于授权 NVOnline/OEM 分发渠道。
- 唯一有内容的近似公开命中是 GitHub 仓库 `JetBrains-Hardware/spark-setup` 中的 **DGX Spark FieldDiag 运行日志/文件散列清单**：日志提到 `onediagfield.r9.257.3`，清单提到 `tests/mods.580/...`、`driver.tgz`。仓库收录的是文本日志，不是 `.deb`、`.tgz`、ELF 或四个 FuseRework 文件；记录的产品是 `NVIDIA_DGX_Spark`，不能当成 NVOnline 的 Blackwell PCIe x86 Field Diagnostics 包。
- `1124962`、`mods.580` 等短/含标点关键词在平台搜索中有明显数字分词、标点分词噪声。下文将它们标为误命中，不把标题相似或搜索摘要当作文件证据。
- NVIDIA NVOnline 的公开文档入口会跳转到登录页；Supermicro FAQ 直连在本环境返回 403。因此，目标版本的文档信息只作为文档引用线索，不宣称已下载或复核目标包。

## 精确搜索词

四个目标文件名（依据本地先前 MODS/FieldDiag 字符串审计列出）：

1. `fuserework.bin`
2. `fuserework_debug_gfw_hash.bin`
3. `fuserework_debug_gfw_pub_key.bin`
4. `fuserework_debug_gfw_sig.bin`

其他精确词及归档变体：`629-INT27-DIAG-008`、`1124962`、`629-24975-0000-FLD`、`nvidia-629-INT27`、`onediagfield`、`onediagfield.r9.257.3.tgz`、`onediagfield.r9.257.8.tgz`、`mods.580`、`SECUREBOOT_FAILURE_ABANDON_FUSEREWORK`、`dgx-spark-fieldiag`、`driver.tgz`。

## 已直接抓取的原始 URL 证据

这些是源站 raw 文件/目录，不是搜索摘要。哈希用于固定本次抓到的内容。

| 原始 URL | HTTP / 内容 | SHA-256 | 能证明什么 / 不能证明什么 |
|---|---|---|---|
| [GitHub raw: `run.log`](https://raw.githubusercontent.com/JetBrains-Hardware/spark-setup/main/docs/spark-05-pcie-defect-bundle/fieldiag/run.log) | 200；2,722 bytes | `59b4c74c796849c4c7d5c1d90c15c51d13e007079056443f461a36bac3ce7614` | 第 1 行写有 `onediagfield.r9.257.3`；日志标示 Build Date `Fri, 19 Dec 2025`、Product `NVIDIA_DGX_Spark`。这是**文本命中**，不是可下载 archive 或目标 PCIe 包。 |
| [GitHub raw: `filehash.log`](https://raw.githubusercontent.com/JetBrains-Hardware/spark-setup/main/docs/spark-05-pcie-defect-bundle/fieldiag/filehash.log) | 200；12,640 bytes | `427eb105a7d240c5b08bd6249f945815cf97aabebff114081aaa17b06e4a1bab` | 第 235 行有 `tests/mods.580/fieldiag: OK`；第 237 行有 `tests/mods.580/driver.tgz: OK`；第 260 行有 `tests/mods.580/nvlinktopofiles.onediag.bin: OK`。这些是已安装包文件的散列清单行，不是对应二进制/归档本身。 |
| [NVIDIA raw: GB202 debug GFW generated source, tag `580.119.02`](https://raw.githubusercontent.com/NVIDIA/open-gpu-kernel-modules/580.119.02/src/nvidia/generated/g_bindata_kgspGetBinArchiveGspRmFmcGfwDebugSigned_GB202.c) | 200；1,357,692 bytes | `96788b169f126e3c04ed42824060bff4a9ccb5a44250be079c9d504e9ba550ee` | NVIDIA 公开仓库中的普通 GB202 GFW bindata 源码样本；文件内容不含四个目标文件名、目标版本串、NVOnline ID 或 `SECUREBOOT_FAILURE_ABANDON_FUSEREWORK`。不是 FuseRework 文件。 |
| [NVIDIA CUDA 公共目录索引](https://developer.download.nvidia.com/compute/cuda/repos/) | 200；6,843 bytes | `ee7196661cf66323d36c0dd526da7bf7f60b89ea98dd5b97450eb9d2004f3ed3` | 返回 `Index of /compute/cuda/repos`。在 Ubuntu 22.04/24.04 x86_64、arm64 `Packages.gz` 中查找 `fieldiag`、`fuserework`、`onediagfield`、`diag-008`，均无匹配 package stanza。这只覆盖该公开 CUDA APT 树。 |
| [Supermicro FAQ 44778 直连](https://www.supermicro.com/en/support/faqs/faq.php?faq=44778) | 403 `Access Denied` | 响应页 SHA-256 `c146a26584b46fa7358c0ae361d1f22a15f1f49420cf5e15346bb3cc19260a4f` | 本次无法读取正文；不使用代理绕过。项目已有本地记录引用该 FAQ 将 NVOnline ID `1124962` 对应到 `629-INT27-DIAG-008`，但本轮未能从该源站独立复核。 |
| [NVIDIA NVOnline 文档入口 `DocID=1124962`](https://partners.nvidia.com/DocumentDetails?DocID=1124962) | 200 后跳转 `/Login?...DocID=1124962` | 最终登录页 SHA-256 `7d01801d1c59bf8befd2c673457c42b00ec91105461af1949d8935d6298f9afe` | 证明该 URL 是访问控制入口；没有取得文档附件、下载 URL 或 token，也没有继续探测。 |

另对 GitHub API 直接读取上述 Spark 仓库的递归 tree：当前 `main` 共 65 个条目；`fieldiag/` 子树全部是日志/JSON/CSV，没有 `.deb`、`.tgz`、`.bin`、`.elf` 或 FuseRework 四件套。`run.log` 的路径历史有 1 个提交（2026-05-14，`414a1dbd...`），属于日志纳入版本史，不是包版本史。

## 命中分类

### A. 真文件 / 可访问归档

- **四个 FuseRework 文件：0 个真文件命中。** GitHub 公开代码索引、HF、IA、Zenodo、Gitee 项目索引、NVIDIA 公共仓库树中没有找到对应的可下载文件对象或公开文件路径。
- **目标 Field Diagnostics 包：0 个公开归档命中。** 未找到可公开取回的 `629-INT27-DIAG-008`、`nvidia-629-INT27*` 或与 `629-24975-0000-FLD` 绑定的 archive。
- 本地先前审计 `DGX_SPARK_FIELDDIAG_AUDIT.md` 记录过另一条产品线的本地归档名：`dgx-spark-fieldiag_{1.0.7,1.0.8,1.0.9,2.0.4}-1_arm64.deb`，其嵌套文件名为 `onediagfield.r9.257.3.tgz`（1.0.7–1.0.9）和 `onediagfield.r9.257.8.tgz`（2.0.4）。这是**本地审计已有样本/文件名**，本轮没有找到其公开 CDN 下载链接；不能把它们改称目标 NVOnline x86 包。
- GitHub 日志另提到包内路径 `tests/mods.580/driver.tgz`。它是 `filehash.log` 中的成员路径引用，不是仓库内 `.tgz` 文件。

### B. 源码/字符串命中（不是目标文件本体）

- `onediagfield`：上述 GitHub raw `run.log` 仅以命令行程序名形式出现，具体是 `onediagfield.r9.257.3`。
- `mods.580`：上述 `filehash.log` 列出该目录中的文件名，包括 `fieldiag`、`driver.tgz`、若干 `.bin`/`.spe`。公开仓库提交的是散列文本，不含这些包成员。
- 四个 `fuserework*` 文件名：公共 grep.app 精确代码搜索均为 0；没有找到公共代码托管中的精确字符串命中。它们在项目已有的 MODS/FieldDiag 本地静态审计中作为 ELF 字符串/外部输入文件名出现，但这是**本地样本字符串证据**，不是本轮公开索引发现，更不是文件本体。
- `SECUREBOOT_FAILURE_ABANDON_FUSEREWORK`：grep.app、IA、Zenodo、HF、Gitee 精确查询没有公开命中；本地既有审计将它记录为 MODS 570.278 的字符串。未找到可公开引用的原始源码行或新下载样本，故不提升为公开源代码事实。
- NVIDIA 官方公开 `open-gpu-kernel-modules` 中的 GFW bindata 是相关背景源码，但与外部 FuseRework 输入文件并非同一物件；直接抓取的 GB202 debug GFW raw 源文件也没有目标词串。

### C. 文档引用 / 受限入口

- 项目已有记录把 Supermicro FAQ 44778、NVOnline ID `1124962`、版本 `629-INT27-DIAG-008` 联系起来；本轮 Supermicro URL 被 403，故正文仅作为**已有文档引用**注明，不能视作本轮独立取得的包清单证据。
- NVIDIA `DocumentDetails?DocID=1124962` 当前公开请求只到登录页。没有授权时不能读取附件；没有尝试生成 `SiteID`、猜测 CDN 参数或 token。
- `629-24975-0000-FLD` 与上述 ID/版本之间，本轮没有找到可靠公开文档或源码映射。

### D. 搜索噪声 / SEO-like 假命中

- GitHub 对裸数字 `1124962` 的 repository 搜索出现用户名 `porus1124962`；commit 搜索也出现哈希/代码中偶合该数字的无关提交。不是 NVOnline 文档。
- Gitee 的公开 Indexea widget 是“开源项目搜索”，不是代码文件搜索。`1124962` 返回 `joker510/hospital`；`mods.580` 返回 14 个普通项目元数据结果，均无 NVIDIA FieldDiag 关系。不能把项目名/数字分词命中当作文件命中。
- Internet Archive 对 `1124962` 有 Archive-It 作业编号等无关结果；对 `mods.580` 的未加严格限定查询返回的文档也不相关。是数字/标点分词，不是归档本体。
- Bing 对精确词的结果多为无关通用页面（例如 `onediagfield` 查询回出气球图片站、`629-24975-0000-FLD` 查询回出餐馆页面）；Google/ DuckDuckGo 则返回自动化挑战/空壳页面。这些不作为支持证据。这里的“SEO-like”指无关搜索结果噪声，不断言这些页面有恶意操纵。

## 各公开平台/API 结果

| 平台 | 本次做法 | 结果与限制 |
|---|---|---|
| GitHub | REST repository/commit/issue 搜索；HTML code search；代码索引 grep.app；NVIDIA 与命中仓库的公开递归 tree/raw/历史。 | 精确文件名及目标版本在 repo/commit/issue 搜索无命中；GitHub Code Search 显示登录提示，REST `/search/code` 返回 401 `Requires authentication`，不尝试绕过。grep.app 四个精确文件名、目标版本/料号、secureboot 字符串均 0；`onediagfield` 与 `mods.580` 各有一个日志文本命中，指向 `JetBrains-Hardware/spark-setup`。NVIDIA `open-gpu-kernel-modules` 的 `580.119.02`（4,393 tree entries）及 `610.57.04` release commit（4,490 entries）中，没有 `fuserework`、`fielddiag`、`onediagfield`、`mods.580` 或 `629-int27` 路径。 |
| GitLab | `/api/v4/projects?search=...`；`/api/v4/search?scope=blobs&search=...`；UI 搜索页。 | 项目搜索对目标词返回空列表；blob 搜索返回 401，UI 被反自动化页挡住。未尝试登录或绕过权限。 |
| Gitee | 读取公开前端公开配置，调用 `https://so.gitee.com/v1/search/widget/wong1slagnlmzwvsu5ya`，query 1048。 | 此 widget 明确为“开源项目搜索”，不索引文件内容。四个文件名、目标版本、料号、archive 名、secureboot 字符串均 0 个项目结果；`1124962` 是无关医院项目，`mods.580` 是分词噪声。 |
| Hugging Face | Hub 公共 models/datasets/spaces 搜索 API，逐个查文件名、版本、料号、archive 名和字符串。 | 全部 0 个匹配模型、数据集或 Space。 |
| Internet Archive | `advancedsearch.php` 查四个文件名、版本、料号、archive 名和字符串；Wayback CDX 查 `*fuserework*`、Supermicro FAQ URL。 | 精确文件/目标包查询 0 记录；Wayback `*fuserework*` 返回空数组，FAQ URL 的 CDX 查询也为空。裸数字 `1124962` 有不相关 Archive-It 等结果。IA 本身不保证收录未公开或未爬取的附件。 |
| Zenodo | 公共 Records API 查四个文件名及任务标识词（版本、ID、料号、`nvidia-629-INT27`、`onediagfield`、`mods.580`、secureboot 字符串）。 | 首轮 API 返回 0 records；随后服务对当前出口返回 403 unusual-traffic 页面。没有把被限流当作额外负结果；`onediagfield*.tgz` 未在限流后重复请求。 |
| Software Heritage | 公共 origin API `/api/1/origin/search/...`。 | 返回反机器人挑战 HTML，不是 API JSON；因此状态为**未能检索**，不能据此声称无记录。SWH origin 搜索本身也不是任意文件内容搜索。 |
| NVIDIA 公共 repo/CDN | NVIDIA `open-gpu-kernel-modules` 两个历史版本树、GB202 debug GFW raw 源码；公开 CUDA APT 目录和 Ubuntu 22.04/24.04 x86_64/arm64 package 索引。 | 目标 repo 路径和 APT package stanza 均未出现。`developer.download.nvidia.com/` 与 `download.nvidia.com/` 根目录不是可列出的匿名通用下载目录（分别 404）；CUDA APT 树可公开列目录，但与 NVOnline Field Diagnostics 无关。 |
| Common Crawl / 搜索引擎缓存 | Common Crawl `CC-MAIN-2026-43` URL index；Google、Bing、DuckDuckGo、Brave、Mojeek、Startpage。 | Common Crawl 对 FAQ URL 返回 0 页；通配 `fuserework` 与宽泛 NVIDIA 目录查询遇到 502/504。搜索引擎端有挑战、403/429 或明显无关结果；没有可用的可信缓存快照。 |

## 边界与下一步

- “公开索引无命中”不能证明授权包不存在，也不能推断包内一定含/不含四个文件；目标 NVOnline 文档受登录/授权控制，本次没有权限读取。
- 若之后通过合法授权取得 `629-INT27-DIAG-008` 或合法 OEM 镜像，优先比对**归档成员清单**和四个完整文件名，并保存来源 URL、版本、大小、散列；不要用日志里的成员路径或 MODS 字符串冒充真实文件。
- 若要验证 `629-24975-0000-FLD` 是否为该文档的 part number/别名，需要可公开复核的原厂文档或有授权的包清单；本轮不猜其语义。

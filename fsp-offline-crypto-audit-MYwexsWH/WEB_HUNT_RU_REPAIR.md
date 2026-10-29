# 公网检索：MODS/MATS 580、Blackwell/RTX 5090、FieldDiag 与 FuseRework

**检索日期：2026-10-26**  
**范围：** 俄语/东欧及国际 GPU 维修社区、公开搜索索引、Telegram 公开页面、Yandex Disk/MEGA/OneDrive/Pixeldrain 页面，以及 NVIDIA 官方公开文档。仅打开公开网页/文件清单；未下载诊断二进制或镜像，未加入私群、联系卖家、付款、登录会员区或绕过拦截。

## 结论

- **未找到可核验的免费公开 `NVIDIA MODS/MATS 580` 包，也未找到明确面向 `GB202 / RTX 5090` 的公开 MODS/MATS 二进制或 `fuserework.bin`。** 这是公开索引范围内的“未找到”，不是证明其不存在。
- 找到 VLab 维修论坛上的 **MATS 570.215** 社区测试记录：有人称它可识别笔记本 RTX 5060（GB206），但同帖报告 MODS 报 assertion failure；未见 5090/GB202 成功记录。该信息不能外推到 GB202。
- 有一项 NVIDIA 官方 **DGX Spark Field Diagnostics** 文档化包名 `dgx-spark-fieldiag_<version>-1_arm64.deb`，但这是 DGX Spark 系统诊断，不是 RTX 5090 板卡维修包；公开文档没有给出当前 `.deb` 的具体版本、大小或直链。
- 有商业页面声称其 v2.1 UEFI/Legacy VRAM 测试包支持 RTX 5090；但页面明示出售的是打包/脚本/文档便利，**不是 NVIDIA 专有工具本身**。未付款、未下载，无法核验其中是否含可用的 5090 MODS/MATS 或其版本。

## 已打开并核实的候选

| 候选 / 原页面 | 页面原文证据 | 文件名、版本、大小、状态 | 评估与风险 |
|---|---|---|---|
| **VLab：MATS/MODS 400/455/520/570**<br>[主题页](https://vlab.su/viewtopic.php?t=124090)；[后续讨论页](https://vlab.su/viewtopic.php?t=124090&start=780) | 首帖写“Последние и доступные версии”（最新且可用的版本），列表中 `AD102 RTX 4090 … 520`、`GH100 H100 … 520`，未列 GB202/RTX 5090。后续贴中一位用户称 `mats 570.215` 能识别 GB206 笔记本 RTX 5060，但 MODS 报 `gpu.shutdown … assertion failure`；另一用户称 570.215 构建似乎面向 5070，并报告 MATS 写错误。帖内另有“Какая версия MATS подойдёт под Gigabyte RTX5070?”及“why dont have NVMT FOR 5090 ANYMORE?”，均是提问而非 5090 包发布。 | **570.215** 是可见的较新社区版本证据；没有 580 包名/大小，也没有 GB202 支持证明。错误日志和单用户报告未经独立复测；不应将 GB206 结果当作 5090 兼容性。 |
| **VLab 公开云盘链接**<br>[MEGA 文件夹](https://mega.nz/folder/qSBkHabQ#Tr01gbXF9K9uP66FhQzKVg)；[Yandex 400](https://disk.yandex.ru/d/R9lW1UfUvfBBrA)；[Yandex 455](https://disk.yandex.ru/d/pTW7PqlPOCHDIA) | 主题首帖直接链接 MEGA，并称 Yandex 暂不可用；页面标题为 `MATS/MODS 400/455/520/570`。 | MEGA 页面初始显示 **18.32 GB folder**，但本次未能得到子文件名/版本清单，故内容未验证。两个 Yandex 页面打开后均显示“Ничего не найдено”（未找到）。没有下载任何包。 | 18.32 GB 只是云盘页面显示的文件夹大小，不代表内容是某一版本或可信。文件清单/哈希缺失，不能把它标记为 580 或 5090 包；不应为取得内容绕过登录/分享状态。 |
| **Levirepair：MATS/MODS USB stick**<br>[公开论坛主题](https://levirepair.eu/infusions/forum/viewthread.php?thread_id=3)；[OneDrive 文件夹](https://1drv.ms/f/s!AiSvffRQEcWrrQXe2-_9YOCieQLW)；[Pixeldrain 镜像页](https://pixeldrain.com/u/ksBpKU3b) | 原帖说旧镜像适用于 **GT 1xx 至 RTX 40xx**，包含更新到 455/520 的 MODS 与 NVMT。另一个“RTX series memory testing OS (mods not included)”帖子明确写 RTX 50 需要 UEFI，并提示 MODS 文件需“somewhere else”另行放入；该 OS 包本身不含 MODS。 | OneDrive 清单显示 `455.219.7z` **234 MB**（2025-02-05）及 `MODS from 60GB Image - NVMT - Rufus - including newer mods1-13-2023.7z` **2.32 GB**（2023-02-04）。Pixeldrain 页面同名归档显示压缩 **2.49 GB**、解压 **7.95 GB**、上传 2024-05-31；清单为 `MODS From 60GB 1-11-2023 with NVMT.img`（7.95 GB）、`Patch notes.txt`（1.86 kB）、`rufus-3.21.exe`（1.40 MB）。原帖附件还列 `rtx.zip`（53.52 MB），但其描述是“不含 MODS”的启动环境。 | 与 580/5090 不匹配。OneDrive 与 Pixeldrain 对类似归档显示 **2.32/2.49 GB** 的大小差异，未核实为同一字节内容；未见哈希/签名。第三方启动镜像和诊断二进制有来源、版本混配及恶意篡改风险。 |
| **GPU Solutions 商业包**<br>[产品页](https://gpusolutions.net/product/nvidia-vram-test-usb-bundle-uefi-legacy-digital-download/)；[视频说明页](https://www.youtube.com/watch?v=gon1OA74_ZA) | 产品页声称支持“GTX 6XX up to RTX 5090”，标题为 `NVIDIA VRAM Test v2.1 USB – Bundle (UEFI + Legacy)`；页面明示：“You’re purchasing packaging, workflow scripts, and documentation convenience — not the proprietary tools themselves.” 视频说明链接到该产品，描述使用自制 UEFI USB + MODS 测试 RTX 5070/5080/5090。 | 产品页列出 `VRAM_TEST_V21_UEFI_Digital.zip` 与 `VRAM_Test_V21_Legacy_Digital.zip`，SKU `MATSMODS-BUNDLE-110`；观测时标价 **AED 175**（原价 AED 200）。未列 ZIP 大小、哈希或其中 MODS/MATS 的精确版本。产品页曾可读（HTTP 200），后续刷新遇 HTTP 406；视频页面公开描述标注 2025-11-01。 | 这是**付费商业包装**，兼容性仅为卖家声明；页面称不含专有工具本身。未联系卖家、未加购物车、未付款或下载，包内容及 5090 能力未验证。不能据此认定存在公开的 MODS 580。 |
| **NVIDIA DGX Spark Field Diagnostics**<br>[官方支持指南](https://docs.nvidia.com/dgx/dgx-spark/support.html)；[Field Diagnostics PDF](https://docs.nvidia.com/pdf/userguide-dgx-spark-fieldiag.pdf) | 官方文档称 Field Diagnostic 面向 **NVIDIA DGX Spark**；支持页给出的包名模式为 `dgx-spark-fieldiag_<version>-1_arm64.deb`，并提供通过系统 APT 安装的说明。 | 具体版本、`.deb` 大小、校验值及独立直链均未在这些公开页面给出；本次未尝试安装或获取包体。 | 官方、但目标是 DGX Spark 系统，不是 RTX 5090 的 GeForce 维修诊断。文档描述需要高权限并要求运行前调整 Secure Boot；属于目标平台专用系统诊断，不应在无授权/非目标设备上运行。 |
| **NVIDIA Field Diagnostic 旧帖**<br>[NVIDIA Developer Forum 主题](https://forums.developer.nvidia.com/t/where-can-i-download-the-nvidia-field-diagnostic-software/76685) | 2021 年一位论坛参与者写：“field diag does exist but is not generally available”，并称可能需联系 NVIDIA support/sales；其获得的文件名是 `nvidia-629-INT14-UNIV-ALL.tgz`。 | 文件名中有 `629`，但帖子没有大小、下载链接、校验值或可验证的具体发布版本；未联系任何支持人员。 | 这是论坛参与者的旧报告，不等于目前面向 Blackwell/RTX 5090 的包。和上面的 DGX Spark 包应视为不同来源/产品，不要混为同一个 FieldDiag 发行物。 |
| **Telegram 公开索引 / 旧教程**<br>[Geekland 公开频道快照](https://t.me/s/geek_land?q=%23mods_mats&before=26002)；[其链接的 Forat 教程](https://foratdot.info/como-testear-las-vram-de-nvidia-y-amd/)；[教程 Yandex 链接](https://disk.yandex.ru/d/_lYEyiqxuogDmg?w=1) | Telegram 公开帖是“Como testear las VRAM de Nvidia y AMD”教程/视频标签，没有 MODS 包附件。Forat 原文称该旧组合不支持 RTX 3080 以上（后续兼容表写到 RTX 3090，页面自身表述不完全一致）。 | 教程列出若干旧 MATS 版本（如 455.127）及 Yandex 文件链接；该 Yandex 页面现显示“Ничего не найдено”。没有文件大小或 5090/Blackwell 版本。 | 只属于旧教程/旧镜像，不是目标包；兼容范围自相矛盾且分享已失效。 |

## 社区搜索与误命中

- **Badcaps**：打开过 [MODS & MATS for 4080 (520.132)](https://www.badcaps.net/forum/troubleshooting-hardware-devices-and-electronics-theory/troubleshooting-desktop-motherboards-graphics-cards-and-pc-peripherals/3836755-mods-mats-for-4080-520-132)；标题明确是 4080/520.132，不是 5090/580。另一个旧 VRAM 讨论页 [Software to analyze Video RAM faults on graphics cards?](https://www.badcaps.net/forum/troubleshooting-hardware-devices-and-electronics-theory/troubleshooting-desktop-motherboards-graphics-cards-and-pc-peripherals/75981-software-to-analyze-video-ram-faults-on-graphics-cards/page3) 中出现目录写法 `/mods/580` 和 `/mods/rx570`，是路径/型号上下文，不足以证明存在“MODS 580”版本；该页提示附件完整下载需 Premium supporter。本次未尝试取得附件或付费。后续抓取遇到站点 202/WAF 响应，未绕过。
- **TechPowerUp**：[3060 测试结果讨论](https://www.techpowerup.com/forums/threads/nvidia-mods-mats-3060-12gb-test-result-confusion.329131/) 的原页显示 JavaScript 自动化检查，未开放正文；标题也不是 5090 包。未绕过检查。
- **4PDA**：搜索产生的候选 [topic=1127509](https://4pda.to/forum/index.php?showtopic=1127509) 原页标题为 `Grand Theft Auto IV[Release]`，与 GPU 诊断无关。
- **Overclockers.ru**：[RTX 5090 笔记本 shuntmod/超频文章](https://overclockers.ru/blog/molexandr/show/233698/Shuntmod-i-razgon-GeForce-RTX-5090-dlya-noutbukov-povysil-proizvoditel-nost-do-41-2) 已打开；主题是笔记本超频，不是诊断包。**Overclockers.ua** 的 [Mats+Mods 主题](https://forum.overclockers.ua/viewtopic.php?t=270254) 请求返回 HTTP 403，未继续访问或尝试规避。
- **GitHub 假同名**：[`bluenetic/fielddiag`](https://github.com/bluenetic/fielddiag) 是仅含网页资源（`index.html`、`script.js`、`styles.css`）的公开仓库，未发现 NVIDIA FieldDiag 二进制或 NVIDIA 关联说明；不作为候选包。

## 搜索词与边界

执行了用户给出的词及变体：`NVIDIA MODS 580 скачать`、`MODS MATS RTX 5090`、`GB202 ремонт видеокарт`、`fielddiag Blackwell скачать`、`fuserework.bin`、`MATS 570.215`、`MODS 580.82.07`、`nvidia-629-INT14-UNIV-ALL.tgz`；并用站点限定搜索了 TechPowerUp、Badcaps、4PDA、VLab、Overclockers、`t.me/s`、Yandex Disk、MEGA 和 GitHub。`fuserework.bin` 的精确字符串及 `fuserework` 变体，在公开索引及 `disk.yandex.ru`、`mega.nz`、`t.me/s`、GitHub 限定搜索中均未得到相关结果。`580.82.07` 搜索主要命中 NVIDIA 数据中心**驱动**，不能当成 MODS 版本证据。

搜索索引不完整；“无结果”只表示本次索引/公开页面没有可核验命中。搜索过程中打开了候选原页面，公开文件页面只查看列表和元数据；没有下载诊断程序/镜像、尝试登录、进入私群、联系卖家或付款。除官方说明文档外，没有执行任何软件或操作 GPU。

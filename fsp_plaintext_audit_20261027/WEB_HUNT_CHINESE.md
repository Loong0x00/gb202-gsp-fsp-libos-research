# 中文公网检索：NVIDIA MODS/MATS、Blackwell FieldDiag 与 FuseRework

**检索日期：2026-10-27**
**范围：** 中文关键词、公论坛/网盘页面、B 站简介；只核实公开页面和分享页元数据。未登录、未付费、未加群/私聊、未提交任何提取码、未下载或解压文件。

## 结论摘要

1. **找到了 NVIDIA Blackwell FieldDiag 的官方版本记录，但没有公开下载包。** Supermicro FAQ 公开写明 NVOnline 文档号 `1124962`、版本 `629-INT27-DIAG-008`、发布日期 2026-02-23、x86，并称该版本增加 Blackwell PCIe GPU 支持。FAQ 指向 NVOnline；用公开文档号打开 NVIDIA 页面会跳转到登录页。未登录，文件名、大小、校验和均不可见。
2. **没有找到可验证的 NVIDIA 官方 MODS/MATS 580 包，也没有找到公开可验证的 `fuserework.bin`。** 公开社区材料中可核实到的版本包括 455/520/570，以及一个社区称支持 4000/5000 系列的 “MEINSTER V6”；它们不能等同于 NVIDIA 正式发布的 MODS 580，也没有证据证明 V6 对 GB202/RTX 5090 的实际兼容性。
3. **找到 B 站简介公开放出的两条旧百度网盘分享链接**，简介公开展示提取码 `6666`。百度分享页只显示“请输入提取码”；未输入该码，因此文件名、大小及包内版本不可见。
4. **找到公开论坛分享的社区镜像。** VLab 主题中的 MEGA 文件夹公开显示总计 `18.32 GB / 13 files`；另一个 Google Drive 文件夹公开显示 `Mats Mods by Meister V6_Final.7z`、`20.84 GB`。页面元数据可见，但未下载。VLab 后续帖有用户报告 V6 镜像损坏；没有哈希/签名，可信度低。
5. 对 `fuserework.bin`、熔丝返修等精确词及 Baidu/Quark/Aliyun/Xunlei 站内检索，在可访问的索引中未发现可验证的公开包。由于百度、搜狗、360、Google 等搜索入口出现验证/反自动化页面，这不是“全网不存在”的证明。

## 公开页面与分享页

### A. Blackwell FieldDiag：官方版本信息，包本身受登录限制

- **官方/合作伙伴 FAQ：** [Supermicro FAQ 44778](https://www.supermicro.com/en/support/faqs/faq.php?faq=44778)
  - 页面原文要点：`latest Fielddiag Utility adds more support for Blackwell PCIe GPUs`；NVOnline ID `1124962`；Version `629-INT27-DIAG-008`；Release Date `2/23/2026`；Description `NVIDIA Blackwell GPU Field Diagnostics (x86)`。页面日期为 `02/27/26`。
  - **可访问性：** 浏览器打开时可读到 FAQ 全文；本次直接 HTTP 抓取另遇到 Supermicro CDN 403，故存在访问方式差异。FAQ 可读不代表文件可下载。
  - **下载/文件信息：** FAQ 没有公开文件名、大小或校验和；指示到 NVOnline 查看详情。
  - **NVOnline 文档页：** [DocumentDetails?DocID=1124962](https://partners.nvidia.com/DocumentDetails?DocID=1124962) 直接跳转至 NVIDIA Login。未登录；未尝试恢复或绕过访问。
  - **可信度：高（仅限版本号、发布日期和产品描述）**；不能据此证明已获得包或其内容。

### B. 社区 MATS/MODS 镜像：公开元数据，不是 NVIDIA 官方发布

- **VLab 主题：** [MATS/MODS 400/455/520/570，测试显存用启动盘](https://vlab.su/viewtopic.php?f=48&t=124090)
  - 主题正文列有版本系列 `400/455/520/570`，首帖称为用户自制启动盘合集，并列出适配型号/版本。没有列出 `580`。
  - **MEGA 文件夹：** [qSBkHabQ](https://mega.nz/folder/qSBkHabQ#Tr01gbXF9K9uP66FhQzKVg)
    - MEGA 原始分享页可打开，公开元数据为 **18.32 GB、13 个文件**；未获取/下载文件，页面摘要未给出逐项文件清单。
    - 提取码：分享页未显示。
    - **可信度：低至中（仅证明分享页存在及元数据）**。这是论坛用户合集；没有 NVIDIA 官方来源、哈希或签名。
  - **同主题 Google Drive 文件夹：** [NVIDIA MATS folder](https://drive.google.com/drive/folders/1dSKmQ-2Nw_im-QbXZin7TBbdFJR8AN1X)
    - 未登录可读取列表：`PDF manual mats.pdf` — 1 MB；`Mats 2.0 Flash Drive By Meister Ver 4.4.rar` — 8.69 GB；`Mats 2.0 Flash Drive By Meister Ver 4.5_v2_teste.img` — 28.65 GB；`Mats 2.0 Flash Drive By Meister Ver 4.6.zip` — 18.39 GB；另有 `UEFITool_v0.28.0.zip` — 7 MB。
    - 页面没有文件哈希；这里只查看公开目录，不曾点击下载。
    - **可信度：低至中**；文件名/大小是云盘公开目录元数据，不是对包内容或授权的验证。

- **VLab 同主题末页（2026-09 至 2026-10 帖）：** [第 30 页](https://vlab.su/viewtopic.php?f=48&t=124090&start=870)
  - 公开帖子称 **“MATS MODS by MEINSTER V6”** 主要针对 4000/5000 系列，并称支持 Legacy 与 UEFI；这只是发帖者声明，未验证 RTX 5090/GB202 实测结果。
  - **Google Drive 文件夹：** [BY MEINSTER](https://drive.google.com/drive/folders/1ICDJ7BKhdtmGNfjdIPAd1RwKgJZmexxu?usp=sharing)
    - 未登录可读取目录：`Mats Mods by Meister V6_Final.7z` — **20.84 GB**（页面显示共享时间 9 月 4 日）。未下载。
    - 末页有用户称多次下载后镜像损坏；发帖者称它是约 20 GB 的 7z 压缩包、解压后约 60 GB 镜像。以上均为论坛用户陈述，不是本次验证。
    - **提取码：** 页面未显示。
    - **可信度：低**。社区包、无哈希/签名，且存在损坏报告；“支持 5000 系列”不等于已证实支持 GB202。
  - 末页还提到 SwissTransfer 链接可能因 30 天/250 次限制失效；页面中 URL 被省略显示，且帖子称链接过期。本次未尝试恢复或访问它。
  - 末页讨论的 `455.195` 一次性链接通过论坛私信发送，**不属于公开资源，本次未查找或请求**。

- **VLab 2021 主题：** [DMGG - Mods/Mats - Tserver](https://vlab.su/viewtopic.php?t=118802)
  - 主题称版本最高到 `455.127`；帖子文字公开包含一个 MEGA 文件链接及 Google Drive 链接，并公开显示压缩包密码 `123`。该密码仅按帖子公开文本记录，本次未用于解压。
  - MEGA 页 [File on MEGA](https://mega.nz/file/xx8EwJTT#9LSY3oFNL28ooHpNGNvlw6-yvNyMFF7EuVJFUaZGqSk) 返回通用标题 `File on MEGA`，没有可读文件名/大小；未下载。帖子中的 [Google Drive 文件](https://drive.google.com/file/d/118-CCPZx7PsTiVR7Paj7hhEsXYm9ImPY) 返回 404。
  - 论坛页说明其附件需要登录、达到 15 帖或购买权限；没有登录、发帖或购买。讨论中另有用户质疑该工具包涉及版权/未经授权分发。
  - **可信度：很低**；老版本、来源/授权不明，且有版权争议及失效链接。

### C. B 站简介里的百度网盘链接

> B 站原视频 URL 返回 HTTP 200，但本次无登录静态抓取未得到可读页面主体；以下简介字段来自 B 站公开搜索元数据。对应百度分享页已直接打开核实为提取码提示页。没有提交提取码。

- [显卡测试程序 Mats 制作及使用教程，垃圾佬必备](https://www.bilibili.com/video/BV1XF411L7i7)（2022-05-16）
  - 简介公开链接：[百度网盘分享](https://pan.baidu.com/s/1XqhERKMcUcIk99LjvAylBg)，公开提取码 `6666`。
  - 分享页可打开，但要求输入提取码；未输入。**文件名/大小/内部版本：不可见；可访问性：受提取码保护；可信度：低，旧教程/用户分享。**
- [显卡测试程序 Mods 进阶教程，干货拉满](https://www.bilibili.com/video/BV1h5411R7b9)（2022-05-19）
  - 简介公开链接：[百度网盘分享](https://pan.baidu.com/s/1q-ke24qxi5fdPLDgnmjpAQ)，公开提取码 `6666`。
  - 分享页可打开，但要求输入提取码；未输入。**文件名/大小/版本：不可见；可访问性：受提取码保护；可信度：低，旧用户分享。**
- [2026 年新版显卡内存检测软件 V1.0](https://www.bilibili.com/video/BV1pX6UBkEtf)（公开简介元数据日期 2026-01-10）
  - 简介声称包含 `mods/mats/nvmt`，支持 RTX 5090 与 AMD 9070 XT；没有公开可核实的文件名、大小、哈希或直接下载链接。
  - **可信度：低**，是宣传性用户内容，支持声明未经独立验证。
- [2026 最新版显卡显存检测软件 V1.3](https://www.bilibili.com/video/BV17zFxzQEBe)（公开简介元数据日期 2026-02-07）
  - 简介同样声称支持 5090/9070 XT，并出现闲鱼商品链接；按要求未打开商品页、未询价或购买。无可核实公开文件名/大小。
  - **可信度：低；商业销售线索，不是公开免费包。**

### D. 维修论坛/技术报道（非包下载）

- [Badcaps：Nvidia MATS help please - 33 errors on two cards?](https://www.badcaps.net/forum/troubleshooting-hardware-devices-and-electronics-theory/troubleshooting-desktop-motherboards-graphics-cards-and-pc-peripherals/107039-nvidia-mats-help-please-33-errors-on-two-cards)（2023）页面公开可读，用户提到从视频链接获取 `400.184`。本页没有包链接或文件元数据；回复内容是用户经验，可信度低。
- [VLab：MATS/MODS 测试结果讨论](https://vlab.su/viewtopic.php?f=48&t=100601)（2020）公开页只讨论 `367.38.1`/GTX 1080 等旧版本，附件要求登录、15 帖或购买。本次不访问附件。
- [Bodnara：RTX 50 系列热点传感器与 MODS](https://www.bodnara.co.kr/bbs/article.html?num=213537) 页面公开可读；文章称 MODS 是 NVIDIA 内部诊断工具、通常不向普通用户发布，并称检查 GPU/显存/板卡功能。属于二手报道，不是官方授权或下载来源；可信度中（仅作背景）。
- 搜索摘要还指向 Coolenjoy、Quasarzone、Linus Tech Tips 等旧讨论；本次原页分别遇到超时或 403，未把摘要当作已核实内容，也未尝试绕过验证。

## 按指定关键词的检索结论

| 关键词 | 结果 |
|---|---|
| `英伟达 MODS 580 下载`、`NVIDIA MODS 580` | 未找到可核实的 MODS 580 下载页。搜索结果有 GTX 580 显卡驱动/580.xx 驱动噪声，避免与诊断工具版本混淆。 |
| `5090 MODS`、`GB202 MODS`、`显卡维修 5090 MODS MATS` | 找到 B 站用户对“支持 5090”的宣传，以及 VLab 社区 V6（声称面向 4000/5000 系列）；无官方包，也无可验证 GB202 测试证据。 |
| `Blackwell 场诊断`、`629-INT27-DIAG-008`、`1124962` | 找到 Supermicro FAQ 对应的官方版本记录；NVIDIA 下载文档需要 NVOnline 登录。 |
| `fuserework.bin`、`返修 熔丝 NVIDIA` | 可访问索引中没有找到可打开验证的公开包/网盘条目。不能据此断言私有或未索引内容不存在。 |
| `site:pan.baidu.com`、`site:pan.quark.cn`、`site:aliyundrive.com`、`site:pan.xunlei.com` | 站内限定检索未找到可验证的 MODS 580/FieldDiag/FuseRework 包。B 站简介中另发现两条旧 Baidu 分享，见上表；夸克、阿里云盘、迅雷云盘未找到确认条目。 |
| 博客附件（CSDN、Cnblogs 及精确 FieldDiag/FuseRework 词） | 可访问索引中未发现与目标工具对应且能打开验证的博客附件；CSDN 等结果未提供相关附件线索。 |

## 搜索与访问限制

- 使用了 Bing、Naver，以及对 Baidu、Sogou、360、Google、Brave 的公开搜索尝试；Baidu 显示安全验证、Sogou/360 显示验证码/反自动化页、Google 显示异常流量页、Brave 返回 429。未解验证码、未换身份、未用代理绕过。
- 对发现的论坛、厂商 FAQ、网盘分享页及 B 站视频 URL 做了原页 HTTP/浏览器打开核实；网盘只读公开目录/分享提示页，未下载文件。
- 未进行付费、注册/登录、加群、私聊、私信索取链接、输入提取码、下载、解压、运行或硬件测试。所有社区包均无本次计算的 SHA-256、数字签名/发布者授权验证；不要把可见分享页等同于可信或合法发行。

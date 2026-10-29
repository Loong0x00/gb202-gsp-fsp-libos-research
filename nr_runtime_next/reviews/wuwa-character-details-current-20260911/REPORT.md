# 鸣潮 C 角色详情页：3.6 新线索的限定核查

## 结论

这两个仓库**没有在本次限定检查范围内提供当前角色详情页的 ScenePath、相机参数、灯光/后处理配置或角色查看调用链**。这是有版本固定点和路径范围的负面索引结果，不是“游戏没有这些配置”的断言。

- `TomyJan/WutheringWaves-UIResources` 的 `3.6` 分支确实对应仓库作者标注的 3.6 UI 资源提交；已完整索引的角色相关子树只有 PNG，不是 TypeScript 源码或场景配置。停止此分支，不下载图片、不根据图标猜算法。
- `TheLovinator1/wutheringwaves` 是游戏官网新闻/RSS 抓取仓库，不是游戏实现仓库；根目录和 README 前缀没有指向角色查看源码/配置。停止此分支，不抓文章全集或新闻图片。
- 此结果不能把先前 v2.3 SDK 中的 `UiScene` 字段提升为 3.6 实现证据；也没有新增任何可以归因给 NR 的渲染证据。主任务已独立确认的本地 C 绑定不在此重复研究。现有静态截图足够作为视觉参考，本次无需视频或新链接。

## 1. UIResources：固定提交及角色资源索引

仓库：<https://github.com/TomyJan/WutheringWaves-UIResources>

固定提交：[`5b3d1d128ed3938cbb8e5260ba07b075b321a7c6`](https://github.com/TomyJan/WutheringWaves-UIResources/commit/5b3d1d128ed3938cbb8e5260ba07b075b321a7c6)

- 查询分支：`3.6`。
- 提交时间：`2026-08-19T08:19:55Z`。
- 提交说明：`CN_Windows_Product_3.6.0_8368735_3.6.4_8464571`。这是资源仓库的版本声明，不等于独立验证安装客户端的构建号，也不保证涵盖之后所有 3.6 热更新。
- 固定版 [`README.md`](https://github.com/TomyJan/WutheringWaves-UIResources/blob/5b3d1d128ed3938cbb8e5260ba07b075b321a7c6/README.md)，858 字节，全文读取：自述“鸣潮游戏解包UI资源 | Unpacked UI resources of Wuthering Waves.”，其余为版本历史、通知和归档链接，未声称提供 TS 实现。

先读取根目录和 `UIResources` 单层树，再限定读取角色子树索引；未获取任何资源 blob：

| 提交内路径 | 检查深度 | 结果 |
|---|---|---|
| `/` | 单层完整 | `.gitattributes`、`README.md`、`UIResources/` |
| `UIResources/` | 单层完整 | UI 分类目录；不将目录名称解释成调用关系 |
| `UIResources/UiRole/` | 递归完整，API `truncated=false` | 532 个条目：28 个目录、504 个 blob；全部 blob 后缀为 `.png` |
| `UIResources/UiNewRole/` | 递归完整，API `truncated=false` | 4 个条目：2 个目录、2 个 `.png` blob |
| `UIResources/Common/` | 仅单层，API `truncated=false` | `Atlas/`、`Image/`、`Spine/`；没有继续读取其内容 |

可复查的角色页相关**图片路径**（只查索引，没有下载或分析图片）：

- [`UIResources/UiRole/Image/RoleDetailInfo/T_DetailInfoBgDeco.png`](https://github.com/TomyJan/WutheringWaves-UIResources/blob/5b3d1d128ed3938cbb8e5260ba07b075b321a7c6/UIResources/UiRole/Image/RoleDetailInfo/T_DetailInfoBgDeco.png)
- [`UIResources/UiRole/Image/RoleRoot/T_HintRainbowRing.png`](https://github.com/TomyJan/WutheringWaves-UIResources/blob/5b3d1d128ed3938cbb8e5260ba07b075b321a7c6/UIResources/UiRole/Image/RoleRoot/T_HintRainbowRing.png)
- [`UIResources/UiRole/Atlas/T_TPI_UiRole1_UIAtlas.png`](https://github.com/TomyJan/WutheringWaves-UIResources/blob/5b3d1d128ed3938cbb8e5260ba07b075b321a7c6/UIResources/UiRole/Atlas/T_TPI_UiRole1_UIAtlas.png)

**可支持的判断：**这两棵完整角色相关子树没有 `.ts`/`.js`、配置文本、`.umap`/`.uasset` 等非 PNG 文件。图片名称不是场景加载、相机设置、曝光、色调映射、灯光参数或算法证据。

**范围限制：**未递归索引仓库其余 UI 分类，也未读取 `Common/Spine`；不声称整个仓库每一个文件都只有 PNG。README 的资源定位与完整角色子树已足以终止该线索，避免扩大为全资源下载。

## 2. TheLovinator1：新闻站镜像，不是客户端代码

仓库：<https://github.com/TheLovinator1/wutheringwaves>

固定提交：[`0eb610f8cb2f67164fb8f0abb3f6483c2db8b45a`](https://github.com/TheLovinator1/wutheringwaves/commit/0eb610f8cb2f67164fb8f0abb3f6483c2db8b45a)

- 查询默认分支：`master`。
- 提交时间：`2026-09-09T18:11:06Z`。
- 仓库说明：`Automated scraper for Wuthering Waves game news and announcements with RSS feed generation`。
- 固定版 [`README.md`](https://github.com/TheLovinator1/wutheringwaves/blob/0eb610f8cb2f67164fb8f0abb3f6483c2db8b45a/README.md)：索引大小 107,059 字节，仅用 HTTP Range 读取前 16,384 字节（响应 206），开头为 RSS feeds 和游戏官网新闻文章列表。列表含 3.6 新闻，但“当前版本新闻”不是“当前版本游戏实现”。
- 根树完整、`truncated=false`：`.gitattributes`、`.github/`、`.gitignore`、`.vscode/`、`README.md`、`articles/`、`articles_all.xml`、`articles_latest.xml`、`html/`、`logo.png`、`pyproject.toml`、`scrape.py`。
- [`scrape.py`](https://github.com/TheLovinator1/wutheringwaves/blob/0eb610f8cb2f67164fb8f0abb3f6483c2db8b45a/scrape.py) 只作为根索引中的路径记录，未读取或运行；`articles/` 和 `html/` 未递归遍历，未下载文章 JSON、RSS 或图片。

**可支持的判断：**仓库自述、README 前缀和根组织一致显示这是新闻抓取项目，没有值得继续抓取的客户端 ScenePath/角色查看配置线索。不是对所有嵌套新闻正文的全文检索结论。

## 3. 本地证据与验证

同目录保存两仓库 `*-repo.json`、`*-pin.json`、`*-root-tree.json`，以及固定版 README（新闻仓库仅前缀）、四份 UI 子树索引。`verification.json` 记录索引计数、扩展名及检查结果；`SHA256SUMS` 记录本次交付文件摘要。

复查 API 模式：

```text
GET https://api.github.com/repos/{owner}/{repo}
GET https://api.github.com/repos/{owner}/{repo}/commits/{ref}
GET https://api.github.com/repos/{owner}/{repo}/git/trees/{pinned_commit}
GET https://api.github.com/repos/{owner}/{repo}/git/trees/{commit.tree.sha}
GET https://api.github.com/repos/{owner}/{repo}/git/trees/{subtree_sha}
GET https://api.github.com/repos/{owner}/{repo}/git/trees/{role_subtree_sha}?recursive=1
GET https://raw.githubusercontent.com/{owner}/{repo}/{pinned_commit}/README.md
```

验证时发现：用提交 SHA 查询树的响应顶层 `sha` 为提交 SHA，而非提交元数据的根树 SHA；初次一致性断言因此失败。随后改用 `commit.tree.sha` 重新查询两仓库根树，确认条目完全相同，保存规范根树响应后重新检查通过。网络只用于元数据、树索引、README；角色递归树请求设 2 MB 读取上限。未 clone，未下载图片/游戏资产，未运行 SDK、游戏、Wine 或 GPU，未改安装目录、NR 代码、原始 PNG 或此前报告文件 `reviews/wuwa-character-details-rendering-20260911`。所有写入限定在本目录。

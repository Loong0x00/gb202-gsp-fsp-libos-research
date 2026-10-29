# RTX 4090 24GB 多样本收集结果

所有写入仅限本 collector/；未访问硬件、未运行 NVFlash、未运行下载的可执行文件、未登录账户、未求解/绕过网站挑战。下载时间：2026-09-11。

## 已获取：4 份完整 NVGI ROM

完整路径前缀：`/home/user/rt_5090_project/vbios_diff/rtx4090_multisample_20260911/collector/`

| 文件（roms/ 下） | 版本 | MD5 | 验证等级 |
|---|---|---|---|
| github_msi_gaming_x_trio.rom | 95.02.18.80.70 | 684144c47827830af13356063f801008 | **独立 TPU 251470 MD5、SHA1 均匹配**；Git blob SHA1 也匹配仓库树 |
| github_msi_suprim_liquid_x.rom | 95.02.18.80.74 | 03f52c8734b020bc97b81bcbc75a6953 | **独立 TPU 251095 MD5、SHA1 均匹配**；Git blob SHA1 也匹配仓库树 |
| github_msi_gaming_trio_95.02.18.00.52.rom | 95.02.18.00.52 | d8c8c75e823601ff564c46045202c815 | 发布者 README 的 SHA1 匹配；从公开 7z 仅解出 ROM/文本；TPU 251582 页面被挑战阻挡，**无独立预期 MD5** |
| github_asus_strix_3c.rom | **95.02.3C.40.FB** | 5b12774d8a5ef34fd756d211b8087f0c | 固定 GitHub 提交的 raw 文件与同提交 tar.gz 内文件完全一致；提交注明来自 TPU 261777；TPU 页面被挑战阻挡，**无独立预期 TPU MD5/SHA1** |

前三份来源：公开仓库 `cyclone-github/nvidia_vbios`，固定提交 `977fa23d877cd6658d602a6b1ae964763c66b8fc`。
第四份来源：公开仓库 `gabrielmaialva33/NVDAAL-Driver`，固定提交 `f88b3eca7c29d42c7d4b4bd0c09bde2a1e8daa7a`，`Firmware/vbios_asus_rog_strix_4090.rom`。
每份精确下载 URL、来源证据、MD5/SHA1/SHA256 与身份字符串均在 `manifest.json`，HTTP 下载记录在对应 `sources/*.metadata.json`。

4 份都是 2,048,000 字节，开头 NVGI，PCI ROM 的 55AA 在 0x9400，PCIR 检出 NVIDIA 10DE:2684，内嵌版本符合表格。三个 MSI 内嵌 `PG139 SKU 330`，**不是目标 SKU332**。ASUS 内嵌 `ROG-STRIX-RTX4090` / `95.02.3C.40.AS19`。
24GB 分类依据 TPU 标准列表 `sources/tpu_model.txt`；未独立解码容量 strap，因此这里不是物理显存容量或固件签名有效性的鉴定。ASUS .3C 样本优先用于跨 .18/.3C 差分，但信任等级低于两份独立 TPU 哈希匹配样本。

## 首选同版本 SKU332：未能取得

- TPU 274124：预期 MD5 `e9311c9717627e0ef8a80bc6c19f0dd4`，SHA1 `91b5dab7d46b4c2884e0a933229f0b8de5146281`。
- TPU 276524：预期 MD5 `28b5a29fd37b8a8b792a89a1812c2c5d`，SHA1 `23395926b4a1f9d2cc2d608abeebe439e893bf44`。
- 两者均为目录声明 95.02.3C.00.02、PG139 SKU332、24576 MB；原来源快照复制到 `sources/expected_tpu274124.*`、`sources/expected_tpu276524.*`。
- 常规 TPU 直链均 HTTP 200 但 **113,213 字节 text/html 自动机器人挑战**；没有保存为 ROM，没有哈希匹配。详情页后续也出现挑战。
- 普通公开域尝试：裸域相同挑战；`tpucdn.com/vgabios/...` 403；`us1-dl.techpowerup.com/vgabios/...` 404；`www.techpowerup.de` 无 DNS。没有发现可验证的公开 GitHub 镜像。**不把其他 SKU/版本冒充这两个样本。**
- ASUS TPU 263008 (.3C.40.FB EVA-02) 和 260875 (.3C.C0.5A Matrix) 元数据可获取，但 ROM 直链也返回挑战。263008 的预期 MD5 `71c28f1df141e6a81194ddc6bf2c18c4` 不同于已取得的普通 STRIX 261777；不能混同。
- GitHub API 后期触及匿名限流后，改用正常公开仓库提交页面、raw 与 codeload；未尝试账户登录或绕过限流。

## 补充文件（不纳入完整对照集）

`sources/github_gtxferrari4090.header_stripped.rom`：公开 `GTXFerrari/dotfiles` 提交 `35aa80c58ba3ab2946fbc9b314e29bc8762738e4` 的 `VM/4090.rom`。2,010,112 字节、起始 55AA，内嵌 `PG136 SKU 332` 和 `95.02.47.00.01`；比完整 ROM 恰好少 0x9400 字节，符合为 VFIO 剥除 NVGI 前缀的文件形态。没有独立完整文件哈希，**不补造头部，不将其视为完整标准 ROM**。MD5 `790339071070632d6975086a71c810a1`；更多来源/哈希见同名 metadata JSON。

## 用户文章

已读取并保存 `https://duanyll.com/2026/7/13/4090-48G-P2P/` 到 `sources/duanyll.html`、`sources/duanyll.txt`。文章说明泄露 48GB VBIOS 和 32GB BAR1、驱动动态映射实现；**未发现 ROM 下载链接或配套标准 24GB ROM**。相关 GitHub 链接是 open-gpu-kernel-modules 驱动仓库，不是固件下载。

## 验证

在本目录执行：

```sh
python tools/verify_collection.py
sha256sum -c SHA256SUMS
md5sum -c MD5SUMS
```

均通过。`MD5SUMS` 自检仅说明本地文件完整；独立外部 MD5 校验仅适用于表中前两份，不应把自生成清单误作来源认证。`file` 识别 NVGI 为 data 是正常现象，身份由上述头部/PCIR/内嵌字符串交叉核查。

原始 `/home/user/Downloads/278392.rom`、`Asus.RTX4090.24576.221013_2.rom` 未改动；父目录及其他工作者文件未改动。

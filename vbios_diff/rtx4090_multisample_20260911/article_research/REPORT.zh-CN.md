# duanyll 4090 48G P2P：固件机制与多样本差分线索核查

## 结论先行

1. **此链接是“已扩容卡的 P2P 驱动补丁”，不是 24→48GB 的 VBIOS 制作教程。** 作者宣称 AD102 + 泄露 VBIOS + 复用 3090 Ti PCB、双面 24 颗显存；公开材料未给该批卡的厂商/PCB 照片、颗粒料号、VBIOS 版本或 ROM SHA256。不能把它直接认定为现有 `278392.rom / 95.02.3C.00.02 / PG139 SKU332`。
2. **仓库有比博客更新、显著更具体的容量验证和限制说明。** 38 GiB resident tensor 与正确的 `P2P/CUMEM` all-reduce 同时存在（峰值 39.4 GiB）；但 legacy `cudaDeviceEnablePeerAccess` 仍约 31.75 GiB 封顶。博客“保住全部48G”不是所有 CUDA API 的无条件承诺。
3. **发现一个新的、带硬件报告绑定的 48GB 固件版本目标：RTX 4090 D `95.02.74.00.0C`，PCI `10de:2685`，Subsystem `10de:1697`。** 来自 tinygrad issue #36 的原始 bug-report 附件；四张卡均显示 49140 MiB FB / 32768 MiB BAR1。它不是 duanyll 已确认使用的版本，也不是已取得 ROM 的样本。
4. 公开补丁修改 RM/UVM/PCIe 地址映射，不修改显存容量初始化、VBIOS 字节或板上 memory strap。**没有找到与本批 48GB 卡绑定的 ROM、固件补丁、容量 offset、颗粒/通道 strap 配置或签名绕过材料。** 唯一明确的单字节 offset 是另一篇 5090 GDR 的 `libcuda.so` 补丁，不能用于 ROM 差分。

## 固定来源与本地镜像

- [博客](https://duanyll.com/2026/7/13/4090-48G-P2P/)：`article.html`、`article.txt`、`article_links.tsv`；源码 Markdown `sources/article.md`。
- [duanyll fork](https://github.com/duanyll/open-gpu-kernel-modules)，595 分支固定在 **`025090f64d7f79b3b6de118c3e9c50bc32988235`**（末次提交为补充 8 卡验证日志）。完整源码镜像：
  `sources/open-gpu-kernel-modules-025090f64d7f79b3b6de118c3e9c50bc32988235/`，下文简称 **R/**。
- 590 分支固定在 `f6eb773b17d4c976ab1a4a91c2ed8ee1e2d8cd79`，保存递归树 `sources/tree590.json`，未再下载完整的重复源码。
- `sources/duanyll-full595.diff`：原版 `51edebee7991` 到该 595 快照的完整 diff。`sources/duanyll-method3.patch`：Method3 初始提交；初稿不含后续修复，分析以快照为准。
- NVIDIA 原版同版本 `kern_bus_tu102.c` / `kern_bus_gh100.c` 已单独保存，供核对被修改前的真实门禁。
- [tinygrad issue #36](https://github.com/tinygrad/open-gpu-kernel-modules/issues/36)：正文、全部此次返回评论、原始 [bug-report 附件](https://github.com/user-attachments/files/19624113/nvidia-bug-report.log.gz) 均已保存；精简带原始行号摘录 `issue36_firmware_evidence.txt`。
- [aikitoria issue #20](https://github.com/aikitoria/open-gpu-kernel-modules/issues/20)：保存 JSON/文本；其最新评论已补充 libcuda GDR 结论，不能继续沿用早期设计文档“未解答”的描述。
- [NCCL 官方环境变量](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html) 保存 HTML/文本，核实 cuMem 版本条件。
- 全文件校验与精确新增路径见 `SHA256SUMS` / `FILES.txt`；外部 URL 补充清单见 `sources/extra_urls.json`、`sources/followup_urls.json`。

## 1. 具体硬件、固件：证据分级

### A. duanyll 的 48G 非 D 卡

**作者陈述**：复用 RTX 3090 Ti PCB，正反面共24颗，泄露 NVIDIA VBIOS，原版驱动能够识别全部48G。没有提供泄露事件来源、实际板照、焊接配置或二进制文件。因此“泄露固件如何启用48G”仍是未披露机制，不是源码已证实的结论。

**仓库原始输出可核对**（R/docs/48g-4090-p2p/hw-logs-2026-07/）：

| 节点 | GPU / 驱动 | 容量、BAR 与用途 |
|---|---|---|
| node6-modded48g | 4×RTX4090 / 修改595.71.05 | 每卡49140 MiB；GPU0 PCI BAR1为32GiB；P2P、38GiB占用验证 |
| node32-modded48g-8x | 8×RTX4090 / 修改595.71.05 | 同样49140 MiB / GPU0 BAR1 32GiB；大占用测试日志实际world=2，不是8 rank同时占用38GiB |
| node14-stock48g | 4×RTX4090 / stock580.95.05 | 已显示49140 MiB；P2P=CNS；当前BAR1仅256MiB，但PCI ReBAR支持列表到32GiB |
| node13-modded24g | 4×RTX4090 / 修改590.48.01 | 24G对照卡；PCI BAR1为32GiB，static路径 |

后两行尤其重要：**容量识别不依赖 Method3；当前 BAR1 大小又取决于平台/启用状态，不是显存容量字段。** 同时，stock580与modified595属于跨版本对照，不能视作严格同版本单变量实验。

博客“普通4090是24G显存/24G BAR1”不宜照抄为PCI资源尺寸：仓库24G对照机的 `04-lspci-bar.log` 显示 **32G BAR1**。PCI ReBAR按2的幂选尺寸，需区分PCI aperture、驱动统计/可映射区域及实际FB容量。

### B. 新固件版本线索：4090 D 48G，95.02.74.00.0C

issue #36 最初报告者 ac101m 于2025年4月发布的附件中，以下信息绑定在同一GPU输出里：

- 原始行42–45：四张 RTX4090 D / 49140 MiB / VBIOS `95.02.74.00.0C`。
- 行6594–6604：AD102 `[10de:2685]`，Subsystem `[10de:1697]`，BAR1 `[size=32G]`，Expansion ROM 资源窗口512K（**这不是已导出ROM文件大小**）。
- 行44002、44006：VBIOS同版本；GPU Part Number `2685-250-A1`。
- 行44036：GSP Firmware `570.124.04`，与驱动同版本；不要把此GSP版本误作VBIOS版本。
- 行44080–44088：FB Total49140 MiB / Reserved621 MiB / BAR1 Total32768 MiB。
- 行37903–37914：`/proc/driver/nvidia/gpus/.../information` 独立重复同一VBIOS字符串。

这比仅依据 ROM 上传描述把固件标为“48G”更强，但仍只有识别与P2P失败报告，**不是全48G地址读写正确性测试**。报告中的 `Board ID 0x100/0x8100/...` 随总线位置变化，不能替代 PG139 SKU 身份。

**对多样本最有价值的跟进**：向该版本实际持有者/公开存档追索原始ROM及24GB 4090D同版本对照，先分开4090与4090D家族，再做跨家族容量相关区域交集。此次未找到该版本的ROM文件；Google精确版本搜索返回跳转壳页，不构成“公网不存在”的证明。

## 2. 代码确实改变了什么

[固定快照源码](https://github.com/duanyll/open-gpu-kernel-modules/tree/025090f64d7f79b3b6de118c3e9c50bc32988235)

- 原版 `src/nvidia/src/kernel/gpu/bus/arch/turing/kern_bus_tu102.c:367+`，`kbusIsStaticBar1Supported_TU102`：FORCE_ENABLE比较 `bar1VASizeAligned` 和 client-visible FB；AUTO还需userD、doorbell、console、mailbox、padding等空间。对48G FB /32G BAR1不能整块static-map。
- 原版 `.../hopper/kern_bus_gh100.c:1447+`，`kbusIsPcieBar1P2PMappingSupported_GH100`：明确要求两端static BAR1已启用。
- 新版 `src/nvidia/src/kernel/rmapi/nv_gpu_ops.c:3688+` 的 `_nvGpuOpsDynBar1Create`：
  - 按分配大小、64MiB保留空间检查BAR1字节预算；
  - `kbusMapFbAperture_HAL` 把远端分配映入一段连续BAR1 VA；
  - `windowPhys = gpumgrGetGpuPhysFbAddr(remote) + memArea.pRanges[0].start`；
  - window memdesc owner是远端GPU，`memdescMapIommu` 映给source GPU；
  - `nv_gpu_ops.c:4603/4961` 的PTE物理地址为 `dynBar1DmaBase + offset + i*mappingPageSize`。
- 新版 `kern_bus_gh100.c:1473+` 放开static要求，但1495+拒绝混合static/dynamic卡对；1779+/1845+仅在static两端保留原per-pair映射。
- `gpu/bus/p2p_api.c` 加入static检查，避免legacy初始化路径无条件索取不存在的static DMA memdesc。
- 动态映射跟随duped memory handle清理；预算用尽明确拒绝。此机制是**预先按分配pin/map**，不是远端PCIe缺页后自动换页。

因此两个容量必须分开：FB物理容量48GiB；同时开放给peer的BAR1映射总量受32GiB限制。驱动补丁改变后者的地址翻译，不增加前者。

`changed_upstream_paths.txt` 已列全部diff路径。没有 VBIOS ROM、容量初始化固件补丁或memory-strap字节修改。仓库中部分 `.bin` 是NVIDIA SPDM证书材料，不是48G ROM。

## 3. 容量实测到底证明到哪一步

### 已有实测材料

- `method3-usable-vram-cumem-vs-legacy.md`：作者报告无P2P可分配46.75 GiB（256MiB块）；legacy peer-access只31.75 GiB。
- node6与node32的 `21-maxp2p-legacy-32GB-cap.log`：legacy实测上限31.75 GiB、最高分配块写入校验PASS。
- 两机的 `20-bigmem-p2p-cumem.log`：world=2、每rank GPU total47.4 GiB；38GiB resident、free8.9GiB；`NCCL_CUMEM_ENABLE=1`、`via P2P/CUMEM`；all-reduce `correct=True`、峰值39.4GiB。
- `dist_p2p_bigmem.py` 源码实际先分配38GiB FP16张量并 `fill_`、同步，再做默认256MiB通信张量all-reduce并逐元素比较结果。这不是只打印 `nvidia-smi` 容量。
- 小buffer `p2pcheck.cu` 为256MiB peer copy + 校验；作者给出Xeon22.7GB/s、EPYC26.3GB/s。原始collective日志也提供wrong=0。

### 不应升级成的结论

- 38GiB resident test **没有逐元素回读核验38GiB resident本体**，也没有全48GiB随机/地址相关pattern、跨轮回校验和alias测试。它证明大于32GiB占用能与正确P2P通信共存，不等于完整容量验真。
- 测试没有实际FB物理页位置追踪；“先分配38G后分配通信buffer”不自动证明通信buffer落在物理32G以上。
- `p2pbig.cu` 的注释声称大buffer尾部是物理高地址，但它使用legacy peer-access且失败后将请求逐GiB缩小。源码会提示退到≤32GiB；未见对应>32GiB成功原始日志。不能将该源码标题当作“高物理地址peer写已证明”。
- `maxp2p.cu` 以累计分配字节推算“physical floor”；这只是测试假定，不是读取页表取得物理地址，PASS也只校验最后一个块。
- issue #36 的ChihayaK先报告P2P/NCCL小buffer成功，随后明确补充>32GB写失败；2026-08-05又提及其方案部分场景silent corruption。未给出在duanyll固定快照上的复现，不能据此认定duanyll补丁已被证伪，但很适合跟进具体失败API与模式。

## 4. 驱动/用户态要求（区分容量识别、P2P、GDR）

1. **容量识别**：仓库stock580.95.05日志已识别48G非D卡；issue#36的570.124.04识别48G D卡。没有证据表明必须595才识别48GB，亦没有在这些材料中确认最老可用驱动版本。
2. **本方案P2P**：595.71.05-p2p-48g和590.48.01-p2p-48g分支确实存在；48G原始成功日志为595.71.05。内核模块与对应用户态/GSP须匹配。DKMS针对Debian/NVIDIA CUDA apt命名体系；博客要求对应版本GSP，但实际 `packaging/dkms/control.in` 写的是 `firmware-nvidia-gsp (>= @VER@)`，不是严格等号锁定，不能靠包依赖自动保证完全匹配。此GSP依赖不是修改版显卡VBIOS。发布资产只有两版DKMS `.deb`，不是ROM。
3. **保留>32G占用同时P2P**：应按实际NCCL `P2P/CUMEM`路径判断，不只看`canAccessPeer`或`P2P/direct`。官方文档确认 `NCCL_CUMEM_ENABLE` 自2.18引入、2.19起**在系统支持时**自动启用；不能只由“PyTorch≥2.8”推出必然启用。测试实际NCCL2.27.3+cuda12.9。
4. 节点同构、一进程一GPU；v1不支持混合48G dynamic与普通static卡对、managed跨卡迁移及虚拟peer-copy模式；关闭大buffer注册（`NCCL_LOCAL_REGISTER=0`、`NCCL_GRAPH_REGISTER=0`）。NCCL多host-bridge拓扑需 `NCCL_P2P_LEVEL=SYS` 才选择P2P。
5. ACS/IOMMU影响性能。新文档写“ACS off + iommu=pt”，但同一仓库原始node6/node32命令行**没有iommu=pt**，日志README解释在默认IOMMU下运行时关闭ACS后得到满速。故不能把iommu=pt写成已被所有平台实验证明的硬要求；应保留批次差异。
6. **GDR不是本P2P方案的必要步骤**。aikitoria #20 的 [Harry-Chen评论](https://github.com/aikitoria/open-gpu-kernel-modules/issues/20#issuecomment-4489627490) 确实报告 `libcuda.so.590.48.01` 文件offset `0x42d69b`，`0x40→0x60`，用于5090 DMA-BUF GPUDirect RDMA。这是用户态ELF版本专属字节，**不是VBIOS offset、不是48GB开关、也不能应用到278392.rom**。GDR博客网页403、尝试公开源码路径404；该字节信息由作者本人issue评论交叉核实。

## 5. 对现有多ROM差分的意义与下一步目标

现有候选仅读取hash/strings，未修改：

- `/home/user/Downloads/278392.rom`
- SHA256 `6a92225642b3dd7d83a86774ab34c913a825a58b3e0f277d43ef3d5e9e1d1037`
- 可见两份 `PG139 SKU 332 VGA BIOS / Version 95.02.3C.00.02` 字符串。

用户已给定对Asus24GB `95.02.18.80.87` 比较：MEM TYPE359 bytes、partition16、training113、timing-mapping8340 bytes相同、微码不同；此次没有重复进行该差分。

**事实与推测边界**：

- 本文和驱动代码没有把48G功能定位到微码。版本跨度本来就会带来微码变化，不能把“微码不同”提升为“容量开关就在微码”。
- 表内容相同不代表实际选中entry、硬件strap、boot-time配置或板级颗粒拓扑相同；这些是候选解释，而不是本文给出的答案。
- BAR1最大32GiB是另一个属性。已见标准24G与改48G都可最大32GiB，所以它不是48G样本分类的充分特征。

### 优先级明确的跟进

**P0：取得已知实机ROM身份桥梁。** duanyll/node6/node32任何一张实机对应的现成ROM、SHA256、VBIOS版本、PCI/SVID/SSID、PCB/颗粒照片；先确认是否就是95.02.3C.00.02，再决定如何给278392标注。作者仓库/issue36评论是直接联系人线索；此次未向任何人发送信息。

**P0：新48G D固件 `95.02.74.00.0C`。** issue36报告者ac101m及该类卡供应商/公开固件库是最具体目标。应寻找同版24G D对照，不把2685 D与2684普通4090的一切差异都算成容量差异。

**P1：源码中的验证程序和原始日志可用于今后标注样本等级。** 区分“系统识别48G”“成功分配/填充>32G”“全容量address-dependent pattern验证”“高物理页P2P验证”；目前只有前两项加小buffer正确通信的材料，未完成后两项。

**P2：NvStrapsReBar只保留为跨代结构研究线索。** issue36曾建议 [bfa61f54提交](https://github.com/terminatorul/NvStrapsReBar/commit/bfa61f54f8e5a9d93363c33068a7d4c46eb319f6)。已抓源码patch与README，该提交实为新增Turing PCI ID分组；README定位GTX16/RTX20的UEFI BAR straps，不是AD102显存颗粒/容量strap，也无4090 64GiB BAR成功案例。原报告者强行将驱动BAR候选尺寸提高一档失败，不能当成可用64GiB方案。

**暂不投入：dockettidal0b 550.90.07 fork。** issue36评论给出具体反证：调用不存在的`rm_get_gpu_fb_size`/`rm_get_gpu_bar1_size`，无法编译；没有可靠成功日志或ROM材料。此次只保留评论证据，未将其当作可信固件补丁下载。

## 核查范围

全程仅HTTP获取与本地文本/源码/现有ROM只读检查；没有调用GPU程序、NVFlash、驱动编译/安装、寄存器访问。所有主动创建文件均在本article_research目录。源码和日志是作者公开材料的静态核查，不是本地独立硬件复现。博客、库内新文档、旧issue需按时间和API语义分别解释，不能以其中最乐观的措辞代替实际测试覆盖范围。

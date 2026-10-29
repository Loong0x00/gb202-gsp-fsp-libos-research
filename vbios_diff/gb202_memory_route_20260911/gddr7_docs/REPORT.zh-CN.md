# GDDR7 density / x16（2-channel、clamshell）初始化来源核查

核查日期：2026-09-11。仅查网页、公开文档和源码；未访问 GPU、MMIO、PCI 配置或运行刷写程序。本文不判断具体 5090 ROM 的二进制内容。

## 结论先行

**不能凭“GDDR7 有信息读取寄存器、支持 clamshell”断言原版 RTX 5090 VBIOS 换颗粒/改外部电阻就能扩容；也不能凭这些公开资料断言必须改 BIOS。具体原 ROM 是否已有可达的大容量初始化路径，仍未知。**

本轮新增的关键主源线索，比泛泛的 clamshell 介绍更具体：

1. **公开的 JEDEC JESD239.01 预览目录明确列有表 150：`CA State at Initialization for 4-Channel Mode vs. 2-Channel Mode`（正文 p.298），以及 §11.5 `2-Channel Mode Enable`（p.297）。** 因而可以确认 GDDR7 标准将 2-channel 使能与初始化时 CA 状态联系起来；不应未经核查说成“像某代 GDDR6 那样拉某个 DQ 引脚”，或武断说成“只写某个 MR”。但预览不含 p.297–298 正文，**具体 CA 位、极性、采样时刻、是否还需 MR 配合，均未取得**。
2. **同一 JEDEC 预览直接确认 Info Read 和 Vendor ID 信息寄存器，而不仅是 Cadence 的功能介绍：** §6.6 p.128；表 75 Info Read Data p.129；表 77–80 是 Info Register Address 0/1/2/3 — Vendor ID1/2/3/4，p.132–134。**目录未列这些字段的位编码，尚不能证明其中哪一位能读 density，甚至不能只凭 Vendor ID 表名认定必含 density。**
3. **实际 Nouveau GB202 路径并非旧版 RAMCFG 软件初始化代码的简单延续。** v6.18 中 GB202 FB 使用 `r535_fb_new`；总大小来自预先存在的 GPU vidmem-size 寄存器，区域信息经 GSP RPC 返回。不能把“驱动最后读到了容量”当成“驱动执行了 GDDR7 density 自动探测”。

## 1. 证据分层

| 问题 | 本轮可确认 | 尚不能确认 |
|---|---|---|
| 16Gb / 24Gb GDDR7 | Micron 官方目录有 MT68A512M32DF（16Gb、x32）和 MT68A768M32DF（24Gb、x32）；SK hynix 厂商 PDF 列 16–24Gb | 某张 5090 原 ROM 是否支持所换厂商/修订/速率 |
| clamshell / 2-channel | Micron 产品简报 `Clam shell: Yes`；JEDEC 发布稿明确 `2-Channel mode to double system capacity`；SK hynix PDF 列 `4ch, 2ch mode` | 具体 5090 PCB 是否布线/供电支持，原 ROM 是否选择并训练该拓扑 |
| GDDR7 x16 使能来源 | JESD239.01 §11.5、图155–156、表150明确指向 **初始化 CA 状态与 4ch/2ch 模式** | 精确绑定位/电平、CA 是板级固定连接还是由主控驱动的实施方案、是否伴随 MR、能否仅改电阻 |
| GDDR7 信息读取 | JEDEC Info Read、IR0–IR3 Vendor ID 表确实存在；Cadence 产品页明确支持 Info Read command / Information Read Registers | density 的 IR 地址、bit range、16Gb/24Gb 编码，以及 GB202 是否读并采纳 |
| NVIDIA 配置来源 | NVIDIA BIT M v2 定义内存 strap translation、memory information、partition information、memory script list 指针；Nouveau 实际有 strap→表项/group 的实现 | 现代 GB202 memory information 表所有字段；表项数、相似字节不等于大容量已支持 |
| 5090 Laptop 对照 | NVIDIA 官网明确标准配置为 **24 GB GDDR7** | 本轮未取得可验证原厂 Laptop ROM、颗粒照片/料号与 ROM 的绑定证据；24GB 本身不能独立证明 8×3GB 的物理布局 |

注意三个“strap”不是同一概念：**GPU 板级配置 strap**选择固件配置；**DRAM 初始化时 CA 状态**选择器件通道模式；**MR/IR**是协议内寄存器/信息接口。不能用其中一种的证据替代另一种。

## 2. JEDEC：可公开预览的新证据及其边界

### [J1] JESD239.01（April 2024）公开预览

- 发布者：JEDEC；承载：Accuris 标准商店公开 preview。
- 原链接：https://store.accuristech.com/products/preview/2901627
- 本地：`sources/jedec_preview_via_jina.txt`。
- 获取方式：原站直接 requests 返回 403；通过 Jina Reader 得到该公开 **19 页预览**的转录，不是完整标准。标题、版本、目录及正文第1页已保留；没有声称拿到第132或298页正文。

精确定位（页码是标准印刷正文页码，不是本地文件行号）：

| 章节/表 | 正文页 | 可见目录标题 |
|---|---:|---|
| §3.1 | 31 | Power-Up Initialization |
| §3.2 | 35 | Initialization With Stable Power |
| §6.6 | 128 | Info Read |
| 表75 | 129 | Info Read Data |
| 表77 | 132 | Info Register Address 0 – Vendor ID1 |
| 表78–79 | 133 | Info Register Address 1 – Vendor ID2；Address 2 – Vendor ID3 |
| 表80 | 134 | Info Register Address 3 – Vendor ID4 |
| §6.7.1 | 137 | Additional Requirements Concerning a Non-Existing Row Address Range |
| §11.5、图155 | 297 | 2-Channel Mode Enable；Enabling 2-Channel Mode |
| 图156、表150 | 298 | Example System View for 4-Channel Mode vs. 2-Channel Mode；CA State at Initialization for 4-Channel Mode vs. 2-Channel Mode |

本地关键行：112–120、234–250、360、696–698、858–878、1022–1034。

正文第1页明文规定对象为 **16Gb through 64Gb x8 quad channel GDDR7**，且说明部分特性可选、AC timings 等须咨询厂商 datasheet。与发布稿的“16–32Gb”或厂商现售“16–24Gb”不应混为同一范围：它们分别是标准范围、发布时介绍与实际产品目录。早期版本还带有将来更新可能要求 host design changes 的提示，故原卡/目标颗粒的适用修订要对齐。

**下一步最有价值的资料索取不是 LPDDR MR8，而是 J1 的 p.129–134、p.297–298，以及目标 GDDR7 厂商相应章节。** 其中 Vendor ID 表是否包含 density，必须看到字段本体再定论。

### [J2] JEDEC 官方发布稿

https://www.jedec.org/news/pressreleases/jedec-publishes-gddr7-graphics-memory-standard

本地 `sources/jedec_press_via_jina.txt`（原站有 Cloudflare，正文经 Reader 获取）。2024-03-05 明确说明四个独立通道、16–32Gbit 密度、2-channel 模式可让系统容量翻倍。这直接证实标准层的容量拓扑能力，**不证明一个既有主控固件实施该能力**。

当前标准着陆页：https://www.jedec.org/standards-documents/docs/jesd239 ，本次显示 **JESD239F，Aug 2026，免费下载但须注册/登录**，记录在 `sources/jedec_jesd239_via_jina.txt`。本轮未注册账号或取登录后文档。公开镜像检索只见封面/摘要，没有作为字段编码证据。

## 3. 厂商与 IP 主源

### [M1] Micron 产品目录和简报

- https://www.micron.com/products/memory/graphics-memory/gddr7/part-catalog
- 本地 `sources/micron_catalog_via_jina.txt`：真实表格行给出 `MT68A768M32DF-28:A | 24Gb | ... | x32 | 266-ball | ... | 768Mb x32`，以及16Gb的512M32系列。直接 HTML 是动态框架，Reader 版本含表格。
- 简报原始 URL 可由 `sources/micron_gddr7.html` 的 `Read product brief` 链接核验：
  https://assets.micron.com/adobe/assets/urn:aaid:aem:087330f6-6d71-4575-b622-cb10f20cdaf0/renditions/original/as/gddr7-product-brief.pdf
- 正文转录 `sources/micron_brief_via_jina.txt`，3页，Rev. A 06/2024，p.2：`Device width 32 bits`、`#Channels/package 4`、`Clam shell Yes`、266 balls。**这是 product brief，不是完整 datasheet。** 原 PDF 直取返回200的拒绝 HTML，已改名为 `.pdf.response.html`，没有冒充 PDF。
- Micron 16Gb 详细产品页通过 Reader 只展示 REACH、RoHS 等公开下载，没有找到完整 GDDR7 datasheet。经销商搜索命中“datasheet”标题不等于已经取得数据手册。

16Gb=2GB，24Gb=3GB 是常用显存容量命名换算。本报告不把目录里的 x32 误认为“不支持2-channel”，也不把它当作使能2-channel的步骤说明。

### [H1] SK hynix 原站可直接下载 PDF

https://product.skhynix.com/download.do?attNo=423&attTypeCd=SKT02

- `sources/skhynix_gddr7_saleskit.pdf`（**真实 PDF，2页，2,833,586 bytes**）。
- SHA256：`1e780104538686235a39dd761202c6aa8cae48752b64503961d6d44882625d2f`。
- `pdftotext -layout` 转录：`sources/skhynix_gddr7_saleskit.txt`。
- p.1 specifications：Density 16–24Gb；Channel 4ch, 2ch mode；p.2：32 Byte Access per channel / Four Independent / 2 channel mode support。

这是厂家 sales kit，也未给 CA 绑定位、IR 密度字段或 MR 编码。

### [C1] Cadence GDDR7 VIP 页面

https://www.cadence.com/en_US/home/tools/system-design-and-verification/verification-ip/simulation-vip/memory-models/dram/gddr7.html

本地 `sources/cadence_dram_vip_via_jina.txt`，重点行759–786：

- `Supported Commands` 包括 `Mode Register Set`、`Info Read command`。
- `Mode Registers`：页面声称支持 MR0 to MR64。
- `Information Read Registers`：页面声称支持 IR0 to IR128，默认值和可配置字段、相关时序检查。

**这些数字按产品网页原样记录，不视为已独立核实的 JEDEC 寄存器边界，也不推导 density 字段。** J1 更早版目录只列 MR0–MR31，版本或页面表述差异尚未澄清。

## 4. NVIDIA 文档和实际 Linux/Nouveau 代码

### [N1] 官方 BIT / MemoryClockTable 文档

- https://download.nvidia.com/open-gpu-doc/BIOS-Information-Table/1/BIOS-Information-Table.html
- `sources/nvidia_bit.html.txt` 行548–573：BIT_MEMORY_PTRS v2 按顺序有 count(8bit)、strap translation pointer(16bit)、memory information pointer(16bit)、reserved(64bit)、partition pointer(32bit)、memory script list pointer(32bit)。由宽度累加，memory information pointer 在 M 数据块 **+3**；这是指针，不是 density 数值。
- https://nvidia.github.io/open-gpu-doc/MemoryClockTable/MemoryClockTable.html
- `sources/nvidia_memory_clock.html.txt` 行19–31：每个频率区间的 base entry 后有多条 strap entry。

**本轮未找到官方独立 Memory Information Table 完整字段规范。** 公开 open-gpu-doc 目录/递归树已查；只有 BIT 对它的指针说明不能当作表体文档。Memory Clock / Tweak 表不是同一个表，也没给本任务需要的 GDDR7 density/2ch 完整定义。

### [L1] Linux v6.18：历史的 strap→表项确有实码

固定版本源 URL 前缀：
`https://raw.githubusercontent.com/torvalds/linux/v6.18/drivers/gpu/drm/nouveau/nvkm/subdev/`

- `bios/ramcfg.c` 行30–33：`(rd32(0x101000) & 0x3c) >> 2` 取得 strap。
- 同文件行51–77：M v2 的 `nvbios_M0203Em` 匹配后返回 group，否则使用 translation table。
- `bios/M0203.c` 行30–44：从 BIT M+3 取表指针，只接受 table version 0x10。
- 同文件 `nvbios_M0203Ep`：条目 byte0 的低4位→type、高4位→strap；byte1低4位→group。`Em` 按 RAMCFG strap 匹配。
- `fb/ramgf100.c` 行147–170：频率先选 rammap，再根据 strap/group 选配置与 timing。

**限制：这是实际的历史路径/解析器；不是“GB202 正在按这4bit初始化GDDR7”的证明。M0203解析器也没有给出 GDDR7 density/x16 字段。** 不能从 group 数量或 bit_M.length 直接算出支持几GB。

### [L2] Linux v6.18：GB202 实际 FB/GSP 路径

所有下述文件位于 `sources/linux_v6.18/`，可用同一原始 URL 前缀逐一核验：

1. `fb/gb202.c` 行21–30：`.vidmem.size = ga102_fb_vidmem_size`，创建时走 `r535_fb_new`。
2. `fb/ga102.c` 行28–32：`ga102_fb_vidmem_size` = `rd32(0x1183a4) << 20`。是读取 GPU 寄存器，不是向DRAM发Info Read。
3. `gsp/gb202.c`：`oneinit = gh100_gsp_oneinit`；固件接口为 r570 / 570.144。
4. `gsp/gh100.c` 行131–140：初始化 GSP WPR meta 时，`gsp->fb.size = nvkm_fb_vidmem_size(...)`。
5. `fb/r535.c` 行32–51：`ram->size = gsp->fb.size`；RAM type 此处仍 `UNKNOWN /*TODO: pull this from GSP.*/`；可用分区来自 `gsp->fb.region[]`。
6. `gsp/rm/r570/gsp.c` 行77–105：经 `GET_GSP_STATIC_INFO` RPC 收取 `fbRegionInfoParams`，转给 `r535_gsp_get_static_info_fb`；后者在 `gsp/rm/r535/gsp.c` 行178–200整理可用区域。

所以准确说法是：**大小寄存器读回 + GSP区域信息消费**。不是“所有容量来自GSP自动识别”，更不是开源代码证实5090原ROM会读取24Gb density。是谁、在哪个开机阶段、以什么颗粒/strap信息编程该大小寄存器及地址映射，需要继续查启动固件/ROM/主控实现；这些函数没有回答。

## 5. 对“原BIOS只改外部硬件”的直接意义

必须把两个增容轴分开（按512bit总数据接口和完整颗粒容量作算术，不是改装可行性承诺）：

- **32→48GB**：16×2GB 换为16×3GB；重点是24Gb的地址几何、时序、厂商训练等支持，**不必然涉及2-channel/clamshell拓扑**。
- **32→64GB**：32×2GB，利用2-channel/clamshell在不加总位宽的情况下增加颗粒数；需要器件侧模式与GPU侧映射/训练同时匹配。
- **32→96GB**：32×3GB；两种变化都涉及。

原ROM已有某个未启用配置，外部GPU strap选到该配置，是“无需改ROM”的一种可能机制；DRAM信息读取动态决定几何，是另一种可能机制。**公开资料没有证实任一机制在目标5090原ROM中完整存在且可达。** DRAM有信息寄存器，不意味着固件会读、能解码24Gb、会据此重设映射；初始化CA状态涉及硬件，也不意味着增加电阻就能覆盖主控驱动或替主控训练。

应对离线ROM分析提出的验收问题：

1. 是否存在与目标颗粒厂商/修订/密度相符的可达配置，而不仅是“同一版本也用于专业卡”？
2. 24Gb相关地址映射、上限/空洞处理和时序/训练是否具备？J1 §6.7.1仅提供相关章节线索，不能代替实码。
3. 若走clamshell：GPU侧初始化CA状态、通道/颗粒组织和对应训练脚本是否实际改变；板侧物理连接是否允许该状态？
4. 若声称自动检测：能否定位Info Read发起、IR字段解码、以及将其用于映射/时序的调用链？“容量最终读回64/96GB”只是结果，不能反推出该链。

## 6. 可选 Laptop 对照

https://www.nvidia.com/en-us/geforce/laptops/50-series/ → `sources/nvidia_laptop_50.html.txt` 行980–1010，官方明确5090 Laptop标准配置24GB GDDR7。本轮有限检索 MSI/Lenovo 官方更新来源，**未取得具备机型、GPU芯片、颗粒料号、版本、哈希闭环的原厂Laptop ROM**。未下载/运行更新工具。即使未来取得GB203 Laptop ROM，只能作24Gb支持路径的对照，不能直接证明GB202 GeForce原ROM沿用该路径。

## 7. 复核与文件说明

- 网络通过 requests 获取；遇到公开网页防机器人响应时另用 Jina Reader，正文来源仍以上列主源为准，报告中已区分直接文件与第三方转录。
- `manifest.jsonl` 保留抓取历史（同名重试的旧响应哈希属于旧响应）；`manifest_latest.json` 是当前文件最新URL/状态/长度/SHA256清单。**HTTP200可能是拦截页，须看正文。** 不成功响应及搜索页均不是机制证据。
- 两个未得到真实PDF的直取响应已命名为 `.pdf.response.html`；目前真实厂商PDF只有SK hynix sales kit。
- `FILES_CHANGED.txt` 列本任务目录内所有文件的绝对路径；`SHA256SUMS` 用于复核全部证据文件。
- 通用搜索曾返回错误自动摘要，把“并行row/column commands”说成“clamshell mode register”；未采用。没有将 LPDDR MR8 或 GDDR6 引脚/MR编码冒充 GDDR7。

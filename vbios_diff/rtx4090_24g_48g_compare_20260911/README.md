# RTX 4090：ASUS 24GB 与 TPU 标注 48GB ROM 的离线对比

日期：2026-09-11。仅读取文件；未调用 NVFlash、显卡管理工具，未访问显卡设备节点、MMIO 或 GPU sysfs，未修改源 ROM。

## 结论

**两份固件的可见显存配置比文件整体差异显示的更接近：MEM TYPE 全表、显存分区表、训练选择表完全相同；timing-mapping 按记录对齐后，全部 8340 字节的记录区完全相同。没有定位出可确认为“24GB→48GB”的容量开关或容量检查补丁。**

这不是同版本、同板卡的受控比较：ASUS STRIX 95.02.18.80.87 对 NVIDIA PG139 SKU 332 95.02.3C.00.02。版本、厂商/板级配置与容量标签的变化混在一起，不能将任何差异直接归因于扩容。

278392 的“48GB”已确认是 TPU 页面标签，且其页面哈希匹配本地文件；未通过 ROM-only 解码或实卡读写证明容量。该页面明确标为 unverified upload。不能把这等同于证明其造假或不支持48GB。

## 输入与身份

| 项目 | ASUS 24GB | TPU 标注48GB候选 |
|---|---|---|
| 原路径 | `/home/user/Downloads/Asus.RTX4090.24576.221013_2.rom` | `/home/user/Downloads/278392.rom` |
| 字节数 | 2,048,000 | 2,048,000 |
| BIOS字符串 | RTX4090 VB Ver 95.02.18.80.AS03 / ROG-STRIX-RTX4090 | PG139 SKU 332 VGA BIOS |
| 版本 | 95.02.18.80.87 | 95.02.3C.00.02 |
| legacy PCIR Device | 10DE:2684 | 10DE:2684 |
| NVGI头中的Subsystem | 1043:889D | 10DE:16F3 |
| TPU页面标注编译日期（未独立解码） | 2022-10-13 | 2024-10-23 |
| SHA256 | `3ca93a93cad87f0f60898f4c7ec69ef2192bd12da1469cb24a7402b4283d90ed` | `6a92225642b3dd7d83a86774ab34c913a825a58b3e0f277d43ef3d5e9e1d1037` |
| MD5（匹配TPU页面） | `8759feeaef5719c0c002d829c29bfb83` | `6d3777f24c166f3cb1d7b5867227d3d9` |
| SHA1（匹配TPU页面） | `ca6d365f043820add49d9ee055ec189fe4376f27` | `8009f58dfb2ea33f484221dc5c542611cbfe2547` |

身份来源：
- https://www.techpowerup.com/vgabios/268983/asus-rtx4090-24576-221013-2
- https://www.techpowerup.com/vgabios/278392/278392

278392 页面 BIOS Internals / Memory Support 仅写 GDDR6X、Micron；49152MB 位于 Graphics Card Info。无法由页面确认容量元数据是手填还是工具采集，更不是独立实测。

另有同版本 `95.02.3C.00.02`、同 `PG139 SKU 332` 但标注24GB的条目：
- https://www.techpowerup.com/vgabios/274124/274124
- https://www.techpowerup.com/vgabios/276524/276524

它们页面编译日期为2023-05-17、Subsystem 10DE:510A，也属于未验证上传。仅核对了页面，没有下载这两份参考ROM；页面哈希与278392不同，不能声称其固件内容相同。但版本号/SKU不是48GB专属标志。

## 解析方法和重要限制

两份文件均为 NVGI 容器，首个 legacy ROM 位于绝对 `0x9400`，BIT 位于 `0x95b0`。按 PCIR/NPDE 遍历的链包含 legacy、EFI 和两个扩展镜像；EFI gap 为 `0x14e00`。BIT短指针按legacy基址处理；扩展32位指针按对应扩展地址空间解析。

两份文件都在偏移 `0xe0000` 后还有对应副本；各自完整Option-ROM链与其副本相同。48候选的两个0xe0000-byte槽整体相同，ASUS两个槽外围有1670个不同字节，但链自身相同。

原始全文件同偏移比较共有1,119,503个不同字节（54.6632%）。这包含复制槽、签名/元数据、代码版本变化和表重定位，不能据此推导“扩容改了54%的BIOS”。

旧版 envytools nvbios 对这些提取链报告扩展表OOB/未知版本，ASUS解析还退出135。`*_envy.txt` 仅保留为失败诊断，**不得作为有效完整解析结果**。正式结果使用本目录Python只读、边界检查解析器和独立固定偏移断言。未修改旧版工具或既有项目脚本。

## 显存表：直接字节证据

以下都是原始源ROM的绝对偏移；表名部分采用 envytools 历史命名，不意味着所有私有字段均已知。

| 表 | ASUS偏移 / 大小 | 候选偏移 / 大小 | 结果 |
|---|---|---|---|
| M+1 strap translation（按M[0]的14项） | 0xd50e / 14 | 0xd50e / 14 | 相同 |
| M+3 MEM TYPE | 0xd5fc / 359 | 0xd5fc / 359 | **全表相同：7-byte头，16×22-byte记录** |
| M+0xd memory partition | 0xe5ee / 16 | 0xe60e / 16 | **相同** |
| M+5 training selection | 0x9cdf6 / 113 | 0x9fedc / 113 | **相同**；不等于证明全部训练算法/数据相同 |
| P+8 timing | 0x92e14 / 966 | 0x95d3b / 1014 | 记录80→84bytes，见下 |
| P+4 timing-mapping | 0x90d66 / 8366 | 0x93c8b / 8368 | 头26→28bytes；**全部8340-byte记录区相同** |

MEM TYPE全表SHA256：`91e3ba96eb0a6fe9c4cdc79f4db945fd2d0b6ecb47b8930db5175b36aa19a30a`。

### timing真正的差异

两边都是v0x20、6-byte头、12条记录。ASUS每条0x50 bytes，候选每条0x54 bytes。

- 候选12条记录末尾各多4个零字节。
- 对齐后，config无关的timing记录0～7，每条仅 `+0x2a: 0x18 → 0x24`。
- 记录8～11的原80字节全部相同。

**0x18和0x24是十六进制字节值，不能望文生义解释为24GB/48GB；0x24的十进制是36。**未验证该字节在AD102上的字段语义。可能涉及时序/版本变动，但本次无法因果归因。

### timing-mapping真正的差异

两边都是v0x11、10条主记录、每条主记录106bytes、每条含14个52-byte扩展配置。对齐各自头长度后：

- 10条主记录全部相同；
- 10×14=140条扩展配置全部相同；
- 头部既有指针0x827d→0x829d、0x8289→0x82a9（目标表重定位）；
- 头末多2个零字节。

没有出现“48GB版新增某条RAM配置”这一现象。相同表可能被不同硬件strap或不同微码以不同方式使用，不能由表相同证明运行容量相同。

## 其它差异

- fan表：58bytes中14bytes不同；fan-management表：412bytes中67bytes不同。
- power-sense可见表911bytes相同；power-budget表结构和内容不同（1544→1710bytes）。仅比较表布局，未独立解码功率限值。
- 7个非空Falcon微码条目的存储载荷均不同，不是单纯改容量标签的两份近乎相同镜像。
- app/target `01/01`（envytools命名PRE_OS）的stored payload：`0x910c→0xa12c`；`08/01`：`0x166dc→0x17f60`；`45/07`和`85/07`：`0xff80→0x10280`。
- 这些是载荷字节事实，不是反汇编结论；未识别“解除显存容量校验”的代码路径，也未验证签名或固件能否在具体板卡运行。
- Ada v1 descriptor第一个DWORD是StoredSize，不是Blackwell vDesc flags；本次没有错误地把它当成加密标志。

## Memory Size Report不是显存开关

NVIDIA官方 BIT_BIOSDATA v2 的 Memory Size Report 位于B+0x11。两文件绝对0x965b处都为00。官方明确说明它只决定控制面板显示容量的计算方案，**不影响功能**。不能通过修改该字段扩容。

公开BIT_MEMORY_PTRS v2主要给出指针与strap数量，没有完整定义本代MEM TYPE中的容量/拓扑字段；样本M token长度41bytes，公开字段表只覆盖前21bytes。

文档缓存：`nvidia_BIT_spec.html` / `.txt`。
来源：https://nvidia.github.io/open-gpu-doc/BIOS-Information-Table/BIOS-Information-Table.html

## 对扩容假设的意义

事实与“固件可能已有通用配置、容量由硬件拓扑/strap等决定，不必专门改一个容量值”的假设相容，但没有证明该机制，也没有排除微码或其它层的限制。

要定位48GB专属差异，下一步应找同板型、同build的已验证24/48GB样本，最好附完整硬件strap/颗粒拓扑和超过24GB的设备显存读写测试。本次结果不能直接外推5090的GDDR7 96GB可行性。

## 重现和产物

```sh
python compare_roms.py > comparison.json
python verify_results.py
```

- `compare_roms.py`：不触碰设备的结构解析和对比脚本；只读两个固定源ROM，JSON输出到stdout。
- `comparison.json`：详细偏移、SHA256、记录差异和微码清单。
- `verify_results.py`：独立固定偏移核对、全部timing记录与mapping记录断言，并确认源ROM SHA256未变。
- `*_optionrom_chain.bin`：衍生提取链，不是可刷写推荐文件。
- `*_envy.txt`：失败工具诊断，不作为证据结论来源。
- `sources/`：TPU页面及文本缓存，保留48GB标签/来源证据。

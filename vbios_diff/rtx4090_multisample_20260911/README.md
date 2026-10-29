# RTX4090 24GB / 48GB：七对照差分与显存配置数据流

日期：2026-09-11。全部为离线读取、下载和静态分析；没有NVFlash、显卡设备节点/MMIO/GPU sysfs访问，没有驱动变更或刷写。浏览器下载尝试使用独立临时profile且禁用GPU；失败HTML从未当作ROM。

## 结论：这次定位到了具体显存初始化参数

**48GB样本并非在同代标准24GB代码上增加新的微码指令；它修改了微码内部DMEM里的显存配置数组。**

- 加入7份标准24GB对照后，3份`.3C`对照的全部7个非空Falcon IMEM代码/存储区，均与48GB样本逐字节相同。
- 最接近的`276524.rom`与`274124.rom`主Option-ROM链相同；与48GB样本在主链`[0x9400,0xa2200)`内只差**116字节**，而不是跨`.18/.3C`比较时的百余万字节。
- 其中**6字节位于两组14项显存配置数组**，仅改变索引0、1。已经从数组读取追踪到`D32[0x149a0200] / D32[0x149a0204]`的写入。
- 根据envytools对Pascal以后PBFB广播区的定义，这两个地址强对应FBPA/PBFB广播`CFG0/CFG1`。CFG1的两组行地址字段均由6变7，符合**行地址位数增加1、对应geometry容量翻倍**。
- 这不是只改控制面板容量显示，也不是公开MEM TYPE表里的开关。前一轮只比公开表，确实没有覆盖到微码内部这层数据。

**证据分级：** 原始字节、代码区完全相同、数组到写入指令的数据流为直接静态证据；CFG寄存器名称/ROWBITS解释依赖继承的公开rnndb，缺少AD102专属完整手册；未实机验证这些值是否被选用和最终全48GB正确读写。尚不能称为已验证的刷写配方或证明“只改这6字节足够”。

## 1. 样本与来源

| 编号 | 文件/来源 | 版本 | 备注 |
|---|---|---|---|
| C0 | 用户 `Downloads/Asus.RTX4090.24576.221013_2.rom` | 95.02.18.80.87 | ASUS STRIX，TPU268983页面哈希匹配 |
| C1 | 用户 `Downloads/274124.rom` | 95.02.3C.00.02 | PG139 SKU332、10DE:510A，TPU页面哈希匹配 |
| C2 | 用户 `Downloads/276524.rom` | 95.02.3C.00.02 | 同上；主ROM链与C1相同，单卡/外围数据不同 |
| C3 | `collector/roms/github_asus_strix_3c.rom` | 95.02.3C.40.FB | 固定GitHub提交下载，ASUS STRIX O24G身份；尚无独立TPU哈希 |
| C4 | `collector/roms/github_msi_gaming_trio_95.02.18.00.52.rom` | 95.02.18.00.52 | 发布者SHA1匹配 |
| C5 | `collector/roms/github_msi_gaming_x_trio.rom` | 95.02.18.80.70 | TPU251470 MD5/SHA1匹配 |
| C6 | `collector/roms/github_msi_suprim_liquid_x.rom` | 95.02.18.80.74 | TPU251095 MD5/SHA1匹配 |
| T | 用户 `Downloads/278392.rom` | 95.02.3C.00.02 | PG139 SKU332、10DE:16F3，TPU标注48GB，页面哈希匹配 |

7个不同文件并不等于7个完全独立固件build，特别是C1/C2同主链；已在匹配关系中保留，不人为夸大独立性。对照容量来自公开产品/条目身份，不是本机实测。

用户新补充两份的独立验证：
- 274124：MD5 `e9311c9717627e0ef8a80bc6c19f0dd4`；SHA256 `b8c2a7d943330ac30102ca4c9543f2b958db367d26eeff4226ae3aa41237fb71`。
- 276524：MD5 `28b5a29fd37b8a8b792a89a1812c2c5d`；SHA256 `c845dac798b6c332d6ea619d3786a8c1ff2a7ec626144b7639c445f6bbffab3d`。
- 278392：SHA256 `6a92225642b3dd7d83a86774ab34c913a825a58b3e0f277d43ef3d5e9e1d1037`。

所有输入路径、SHA256、布局见`reports/seven_controls/multisample.json`。额外下载的精确URL、固定提交及校验强度见`collector/manifest.json`。

## 2. 多样本真正排掉了什么

### 不是新增48GB代码

C1/C2/C3的app/target `01/01, 07/06, 08/01, 45/07, 85/07, 49/05, 89/05`全部IMEM均与T完全相同，descriptor也相同。

- app01（PRE_OS）DMEM与C3完全相同；C1/C2与T仅14字节板级数据不同。
- app07、45、85、49、89的DMEM也与同代对照相同。
- 主要未匹配的微码数据是**app08/target01 DMEM**：T相对C1/C2只差10字节。
- signed v3条目按descriptor的存储区做二进制比对；不声称全部存储区已解密或解码。

### 前一轮的timing差异属于版本变化

`.18`的timing记录80bytes→`.3C`的84bytes，记录内`+0x2a:18→24`（hex）同样存在于标准24GB `.3C`样本中，不是48GB专属。

MEM TYPE、partition、training-selection、timing-mapping等公开表高度共用的结论仍成立，但不能据此遗漏微码DMEM中的另一套寄存器初始化数组。

### 初筛“3字节”不是全部差异

`aligned_control_invariant_target_outliers.csv`仅对已解析且记录对齐的表做字节不变量筛查；得到的3字节全部在fan/fan-management中，不能当作扩容开关。脚本有意不把未做对象对齐的整块DMEM/IMEM当作已对齐记录。随后对同代相同代码、相同DMEM布局单独分析，才定位到真正有意义的6字节。

## 3. 核心：内嵌CFG0 / CFG1数组

app08 target01，`.3C`样本：
- descriptor绝对`0x7b74c`，v1，48字节；
- IMEM绝对`0x7b77c`，大小`0xf310`；
- **DMEM绝对`0x8aa8c`**，大小`0x8c50`，物理装载基址为0；
- 两组数组分别在DMEM `+0x29f8`和`+0x2a30`，每组14×4bytes。

| 项目 | 7份24GB的对应值 | 48GB值 | T原ROM绝对位置 |
|---|---|---|---|
| CFG0 array[0] | `0x061f8003` | `0x06dfd003` | `0x8d484`（4-byte word） |
| CFG0 array[1] | `0x061f8003` | `0x06dfd003` | `0x8d488` |
| CFG1 array[0] | `0x4266b000` | `0x4277b000` | `0x8d4bc` |
| CFG1 array[1] | `0x4266b000` | `0x4277b000` | `0x8d4c0` |

具体6个不同字节：`0x8d485, 0x8d486, 0x8d489, 0x8d48a, 0x8d4be, 0x8d4c2`。第二固件槽另有偏移`+0xe0000`的对应变化。

两组数组的元素2～13分别保持`0x061e8003`和`0x4266a000`，没有修改。`.18`样本中对应数组是DMEM `+0x29f4/+0x2a2c`，比`.3C`早4字节，读取基表也从`0x12c4`移到`0x12c8`；不能直接按整块DMEM固定偏移筛选。

### 从数据到寄存器的链条

T的app08 IMEM相对PC：

```text
0x4157: r15 = 0x70c2
0x415b: r14 = D8[r15]
0x415d: r8 = 0x12c8
0x4161: r14 = sign_extend8(r14)
...
0x425a: r11 = 0x149a0200
0x4281: r12 = r14 + 0x5cc
0x42d5: r10 = r14 + 0x5da
...
0x4365: r9 = D32[r8 + 4*r12]
0x4372: D32[r11] = r9
0x4374: r15 = D32[r8 + 4*r10]
0x4377: r9 = 0x149a0204
0x4381: D32[r9] = r15
```

因此令`i=sign_extend8(DMEM[0x70c2])`：

```text
D32[0x149a0200] = D32[0x29f8 + 4*i]
D32[0x149a0204] = D32[0x2a30 + 4*i]
```

地址公式：`0x12c8 + 4*0x5cc = 0x29f8`；`0x12c8 + 4*0x5da = 0x2a30`。随后`0x4399..0x43a7`对CFG0的AND/OR使用四份3C样本共同的`ffffffff/0`，该步不撤销刚写入的变化。

这些指令机器码已直接与ROM提取IMEM核对；独立复核还检查了20652行候选反汇编指令编码，零不匹配。语义跟踪不是通过搜一个孤立24/48常数得出的。

### 字段解释的确定程度

本地`tools/envytools/rnndb/memory/gf100_pbfb.xml`：
- `GP100-`的PBFB_BROADCAST基址`0x9a0000`；
- CFG0偏移`0x200`，CFG1偏移`0x204`；
- CFG1 bits16:19 = ROWBITSA，bits20:23 = ROWBITSB，编码为实际行地址位数减8。

结合代码反复使用的`0x14000000`寄存器窗口前缀，上面的两个写入强对应`0x009a0200/204`。

按继承字段解释：
- 两个ROWBITS：6→7，即14→15行地址位；
- COLBITS=11、BANKBITS=2均不变；
- **单独增加1个行地址位与寻址空间翻倍相符**。

CFG0的严格位差是XOR `0x00c05000`，bit12、14、22、23由0变1。本地资料没有可靠的AD102字段名；不得把它们直接命名为clamshell开关。已知RANKS bit2没有变化，故也不能说“开启第二rank”。

实际板卡是否选择索引0/1、最终读写正确性、CFG0各位的准确AD102含义仍需后续证据。这里给出的是强定位候选，不是未经实验就宣称6字节足以稳定扩容。

## 4. app08 DMEM另4字节的排除/分类

相对C1/C2，整块app08 DMEM总共只差10字节，而非6字节：

| DMEM offset | 原ROM offset | 24→48 | 判断 |
|---|---|---|---|
| 上述两个数组 | 上述6处 | 6字节 | 强显存geometry候选 |
| `+0x6258/+0x625a` | `0x90ce4/0x90ce6` | `1c→1f`各一处 | ASUS标准24GB `.3C.40.FB`也为1f，非48独有 |
| `+0x6370/+0x6372` | `0x90dfc/0x90dfe` | `00→01`各一处 | 两条外部I²C初始化路径使能，器件及扩容因果未定 |

门控证据：
- IMEM `0xa242/0xa244`读取`DMEM[6370]`，零则跳过至`a447`；
- `0x9dd4/0x9dd7`读取`DMEM[6372]`，零则跳过至`9fda`；
- 第三条同类路径由`6371`控制，保持0。

底层访问`0x1400d000 + port*0x20`附近I²C寄存器；路径读取外部器件寄存器后比较，再执行寄存器/值对写入。因此可称为外部器件初始化门控，尚不知道具体VRM/控制器型号，不宣称与容量无关或必需。

## 5. 最近匹配的主ROM全部116字节分类

`reports/near_pair_primary_116_bytes.csv`逐字节记录地址、原值、新值和分类，无未归类位置（分类不等于所有字段语义已解码）。

| 分类 | 不同字节数 |
|---|---:|
| 日期字符串 | 5 |
| 删除NV4090.011字符串 | 10 |
| Subsystem ID | 2 |
| GPIO表HPD0项 | 3 |
| DCB显示输出记录 | 8 |
| 外部器件表 | 2 |
| Connector表 | 2 |
| 镜像校验字节 | 2 |
| PRE_OS DMEM数据（与ASUS3C标准版相同） | 14 |
| **内嵌CFG0/CFG1数组** | **6** |
| app08 DMEM 6258/625a（与ASUS3C标准版相同） | 2 |
| app08外部I²C初始化门控 | 2 |
| performance表字段（`0x938f2:0c→08`，具体语义未解码） | 1 |
| fan表 | 12 |
| fan-management表 | 45 |
| **合计** | **116** |

这些变化在第二槽`+0xe0000`重复；C1/C2/T各自两条主ROM链相同。

整文件对C2差5759字节、对C1差5764字节。其余涉及NVGI头、证书/哈希样式块、制造商信息和末尾单卡数据等。**全部原始变化已无损列出，但没有把所有容器字节都宣称为已解码的签名字段，也没有验证签名接受性。**

## 6. 用户文章带来的证据更新

https://duanyll.com/2026/7/13/4090-48G-P2P/

这不是扩容教程，而是对已能使用48GB显存的卡修复P2P。其仓库具有38GiB驻留tensor加正确P2P/CUMEM通信的测试日志，比仅看TPU容量标签强得多；没有直接绑定当前ROM SHA256，也未对全48GiB作穷尽地址测试。

- 48GB FB与32GB BAR1是两个不同资源，驱动补丁修改动态映射，不增加显存。
- 普通24GB卡PCI BAR1也可能是32GiB，不能将32GiB BAR1本身当作48GB独有标志。
- 后续仓库明确legacy peer-access仍有约31.75GiB限制，cuMem/P2P路径不能与所有API混称。
- 另一个公开gist记录`95.02.3C.00.02`、Subsystem `16F3`、49140MiB，与本候选身份相符，但没有ROM哈希，故不是逐字节同一性证明。
- 另发现4090D 48GB `95.02.74.00.0C`线索，可作为未来跨家族验证，不混入当前AD102 2684标准组。

完整审阅：`article_research/REPORT.zh-CN.md`；固定仓库提交/硬件日志、公开issue均在该目录。仅作为研究证据，没有安装其驱动。

## 7. 对之前问题的修正

“公开显存表相同，因此可能物理改对就行”不够完整。这组样本显示：

> **同一套微码代码 + 不同的内嵌显存geometry参数 + 匹配的实际硬件拓扑。**

没有证据表明必须新增一段“解除24GB限制”的程序；但也不能说所有标准24GB固件原样都可以。此次找到的变化正处在固件配置显存控制器的路径中，证据明显强于只比较MEM TYPE表。

还不能将这些AD102/GDDR6X偏移外推为GB202/GDDR7的96GB补丁。修改ROM也涉及完整性/签名及板级适配，未产生任何可刷写修改文件。

## 8. 重现与验证

工具均只读原ROM：
- `tools/analyze_samples.py`：结构分层、全部字节差异、记录级不变量；输入显式`--control`，不靠文件名自动断言容量。
- `tools/trace_memory_config.py`：7对照的两组数组、三对照七IMEM一致性、关键18处指令编码、CFG0后续无效掩码断言。
- `tools/classify_near_pair.py`：116字节完整分类，并将每份对照的完整差异日志回放到内存中，确认重建的字节流与目标ROM完全相同。
- `code_research/`：初步函数级归一化差分、旧版与同代标准固件的反证。

核心结果：
- `reports/seven_controls/multisample.json`：284个命名单位（有重叠，不是284个独立组件）、全输入哈希和匹配矩阵。
- `reports/seven_controls/*all_byte_differences.csv.gz`：7份对照各自对目标的无损全文件差异，不漏掉未知区。
- `reports/memory_config_trace.json`：显存数组和机器码锚点。
- `reports/near_pair_primary_116_bytes.csv` / `near_pair_classification.json`。
- `reports/seven_control_replay_verification.json`：七次无损重建验证。
- `reports/verification_summary.txt`：最终核查输出与原始文件哈希。

“全字节差异已枚举并验证”已经完成；“所有私有字段和启动行为已完整逆向”没有完成，两者不混淆。

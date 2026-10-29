# GB202 原版 VBIOS＋外部硬件扩容：配置选择链调查

日期：2026-09-11。

## 本轮答案

**已经还原了可见 Memory Information 表的关键字段及一条真实 RM 选择链，但尚未还原加密启动固件如何建立最终 GDDR7 地址几何。**

可以明确限定的是：

> 在本地26份5090/5090D固件中，改变 `_STRAP_MEMSEL` 只会在6条非Skip记录之间选择；这些记录全部是 density code=6、Memory Organization=3。它不能经这条选择链选出PRO固件才有的6/2或7/2组合，也不能使Skip的config4突然有效。

**这不等于证明“原版固件＋硬件扩容绝无可能”。** 存在一个本地直接反例：4090 24GB与48GB的MEM TYPE有效记录整条相同，容量相关差异却位于微码内嵌CFG0/CFG1数组。可见表不是完整容量配置；因此不能把“表里没有PRO组合”扩大为“所有冷启动路径都锁死32GB”。

本轮没有找到原版5090可复现的48/64/96GB选择方案，也没有建立“GDDR7 IR自动识别→密度/组织覆盖→正确地址映射”的代码闭环。准确结论仍是：**仅改strap选PRO对应条目这条简单路线不成立于所查表；其它原BIOS动态路径仍待证。**

## 安全与范围

- 只读原ROM、MODS ELF、公开源码/文档；没有运行MODS、NVFlash或其它GPU工具，没有访问GPU设备/MMIO/PCI资源，没有驱动变更和刷写。
- 新文件全部位于本目录；没有修改原ROM和既有项目脚本。
- MODS的离线AES容器解码仅用于本地`.jse`文本研究，未执行解码后的脚本。
- 私有枚举未解码处保持数字编码，不把6/7直接写成16/24Gb，不把org2/3直接写成x16/x32或单双面。

## 1. 样本规模与同一性

共29份：
- 24份既有bulk目录镜像，加本卡完整Astral E1回读和FE参考，共26份GeForce类样本；其中25份5090 `10de:2b85`、1份5090D `10de:2b87`。包含普通、OC、XOC镜像，不等同于26种独立启动代码。
- PRO6000 WS `98.02.52.00.02` / `10de:2bb1`。
- PRO6000 Server `98.02.8D.00.01`、`98.02.9E.00.01` / `10de:2bb5`。

完整路径、SHA256、实际PCIR基址、BIT地址和表原文：`reports/memory_corpus.json`。

解析时从实际legacy PCIR找基址，不再把PRO的0x35800误向下取整成0x36000。29份均解析成功。

### 稳定性结果

- 26份GeForce MEM TYPE全表字节相同。
- 3份PRO的MEM TYPE **record区相同**；WS/Server的头内指针有所重定位，不把这个区别误当字段变化。
- 25份非D5090的FSP_RUN声明payload逐字节相同，包括本地不同品牌及XOC镜像；5090D、PRO各build另成组。
- 每份Falcon表均有6个非空v6描述符、均置encrypted flag。本轮没有获得这些启动载荷的明文。
- memory partition和training-selection表在29份里相同；不等于全部训练算法相同。

这意味着继续换一个现有品牌32GB BIOS，在本样本集里并不会找到不同的MEM TYPE选项；至少当前26份没有“某厂原版单独开放config4”的例外。

## 2. 关键字段已从真实解析代码恢复

输入MODS ELF：`/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods`，392,339,552 bytes，SHA256：
`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`。

它为stripped ELF。下列地址是按行为识别的函数/指令，不是假冒恢复出的原始函数名。

主要解析器VA `0x672c9e0`。22-byte记录格式为`1d1b1w5b1w2d`，真实解包器将每个字段扩展到32位槽；先确认原ROM偏移与中间结构偏移的对应，再追日志参数和消费者。

| 原ROM字段 | 恢复含义 |
|---|---|
| `+0[3:0]` | RAM type；0xd转内部GDDR7，0xf直接Skip |
| `+0[7:4]`（另有扩展位） | strap匹配值 |
| `+1[3:0]`（另有扩展位） | timing index |
| `+1[7:4]` | vendor ID |
| `+2[3:0]` | vendor revision |
| **`+2[7:4]`** | **density code** |
| **`+3[2:0]`** | **Memory Organization code** |
| `+4[3:0]` | group / logical-part目标 |
| `LE16(+5)&0x1fff` | frequency code |

闭环证据包括：
- density和vendor字段进入真实日志`Strap Idx Type Vendor/Rev Density Grp Freq`的对应参数。
- organization字段进入`Mixed mode partition has unsupported Mem Org %d`分支，并控制后续timing位域选择。
- NVIDIA公开`ctrl2080fb.h`补证vendor1=Samsung、6=Hynix、15=Micron。

完整反汇编、偏移和验证：`mods_schema/REPORT.md`、`mods_schema/verification.json`。因此这次不是按0x60/0x70看起来像容量而猜。

## 3. 实际ROM解码后的完整选择集合

### GeForce：26份一致

| 原始record | vendor | density code | org code | strap/timing index |
|---:|---|---:|---:|---:|
| 0 | Samsung | 6 | 3 | 0 |
| 1 | Hynix | 6 | 3 | 1 |
| 2 | Micron | 6 | 3 | 2 |
| 3 | Samsung | 6 | 3 | 3 |
| 7 | Samsung | 6 | 3 | 7 |
| 8 | Hynix | 6 | 3 | 8 |

4/5/6/9～15均Skip。**这些行density/org相同，不代表已经证明每行都是32GB；总容量还可能由其它固件数据/几何决定。** 但它们没有一条直接切换到PRO的另一组density/org编码。

### PRO：3份record集合一致

- record0、7：density6 / org2。
- record4：density7 / org2，Samsung、rev0、timing index4。
- record1、2、3、8：仍保留density6 / org3。

必须区分“ROM包含某项”和“实际96GB卡选中某项”；本轮没有运行PRO卡读取实际strap，不能直接宣称config4就是这三张卡的当前活动项。

完整CSV：`reports/decoded_ram_configs.csv`。

## 4. 外部strap究竟可以改变什么

### 表自身的选择模式已核对

29份实际ROM表头都是 `header[4]&7 == 0`，即所恢复RM解析器的method0。

- method0：调用selector5，日志命名为`_STRAP_MEMSEL`，在**非Skip有效记录**中匹配strap字段。
- method4：另一种实现按`_MEMINFO_INDEX`匹配原始record序号，但**这些样本的表头并未选择method4**。
- MEMSEL、原始record序号、过滤后的内部记录序号、timing index是不同层，不得随意互换。

对每份实际ROM模拟MEMSEL全部0～31输入：
- GeForce可达density/org组合只有`(6,3)`。
- PRO可达组合为`(6,3)、(6,2)、(7,2)`。
- GeForce MEMSEL4没有匹配项；PRO匹配record4。

这只是该选择函数的穷举，不是模拟完整GPU冷启动。结果见`reports/selection_matrix.json`。

### 新增：BIT V虚拟strap表为空

NVIDIA官方BIT_VIRTUAL_PTRS文档定义两个表指针及translation指针。MODS的`BIT_TOKEN_VIRTUAL_PTRS`初始化和getter `0x67070a0`把它们交给selector函数`0x6711f00`。

实际29份ROM中：
- Virtual Strap Field表头均为`10 03 00`；
- Virtual Strap Register表头均为`10 0d 00`；
- 真实3-byte头解析的entry count均为0。

selector代码`0x6712046..0x671205e`检测到零项后回退HAL，不会从空表提供另一条私有MEMSEL重映射。实际原ROM指针和头字节保存在`selection_matrix.json`。

HAL候选读取`0x10ebb0`或`0x118fb0`低5位，但尚未完成具体HAL分支与GB202 SKU的绑定；**不能据此给板上电阻位置、直接把这些寄存器称为外部引脚，或认定它们没有被更早固件重写**。

## 5. 又找到的两个稳定明文差异

由BIT M+0x1d / M+0x21指向的表，已按头和下一表边界完整比较：

| 表 | 26份GeForce | 3份PRO | 差异位置 |
|---|---|---|---|
| M+0x1d，header4、6×64-byte | 03 | 04 | record1 +0x00 |
| M+0x21，header4、6×96-byte | ff | 01 | record1 +0x20 |

除这一个字节外，各自全表相同。两表的尺寸恰好接到下一M指针，边界已独立校验。**目前未恢复表名/字段用途，不把03→04解释为RAM config3→4，也不把ff→01叫作扩容使能。**

PRO timing-mapping扩展项92bytes，GeForce84bytes。PRO新增8bytes在所查WS各clock/config中均见`00 10 00 00 00 10 00 00`；它不是通过补零就能完全对齐的纯格式变化。共用84bytes内还存在多个配置差异，不能把“每项多8bytes”直接当容量字段。

## 6. GDDR7：已取得的主源证据

完整报告及可复核下载：`gddr7_docs/REPORT.zh-CN.md`。

- JEDEC官方说明2-channel mode用于系统容量翻倍；Micron和SK hynix确认GDDR7支持4ch/2ch或clamshell。
- JESD239.01公开预览目录明确指向p.297–298的`2-Channel Mode Enable`及`CA State at Initialization for 4-Channel Mode vs. 2-Channel Mode`。
- 这说明器件通道模式与初始化CA状态有关，但没有拿到具体位、电平、采样时刻等正文；不能直接给出“拉哪根电阻”的结论。
- Info Read以及IR0～IR3 Vendor ID表真实存在；没有取得可认证的density位图，也未证明GB202原版启动固件会据此重建几何。
- Nouveau v6.18的GB202路径读取既有容量寄存器`0x1183a4`并消费GSP返回的区域信息；不是开源驱动自己发现3GB颗粒的证据。

三类东西必须分开：GPU配置strap、DRAM初始化CA状态、MR/IR协议接口。

## 7. 为什么仍不能宣布“必须改BIOS”

1. 恢复的是MODS/RM的MEMINFO表解释/后续选择链，不是全部加密冷启动逻辑。
2. 4090两份24/48样本的MEM TYPE有效记录完全相同，均density6/org2；已知扩容相关变化在微码DMEM其它位置。由此可见这些字段不是整卡容量的充分描述。
3. org2/3仅证明影响timing子字段及某条件路径内部模式bit22，没有获得可靠的x16/x32具名枚举。
4. density6/7与16/24Gb器件的对应目前只是硬件一致性推断。不能借用其它DRAM-info结构的density枚举：在同一ELF的三套独立信息解码中，code6可返回32、8、12，且按Gb/channel显示；并不是同一字段空间。
5. 没有证明运行时是否存在识别实际颗粒、改写selector或忽略/覆盖表参数的路径。

因此，本轮成果是**约束并还原了一条具体路线**，而非证明所有可能路线不存在。若原版5090确能硬件扩容，下一步必须找到可执行的动态探测/其它几何配置机制，不能只引用“有六个非Skip项”。

后续最有价值的目标：
- FSP/相关初始化载荷中Info Read→密度/通道组织→地址映射的路径，或与之对应的明文参数输入；
- 已验证大显存5090的ROM主体哈希，用来判别原版固件是否确实未改；
- M+0x1d/M+0x21两表的真实消费者；
- 完整JEDEC/颗粒datasheet对应章节，用于识别2-channel初始化所需外部信号，而非跨代套用GDDR6做法。

## 8. 产物与重现

```sh
python tools/memory_corpus.py > reports/memory_corpus.log
python tools/selection_matrix.py
python tools/verify_corpus.py
```

- `tools/memory_corpus.py`：29份GB202边界检查解析、表/加密载荷哈希分组。
- `tools/selection_matrix.py`：把恢复的解码应用到原ROM；输出32种MEMSEL选择结果和BIT V头。
- `tools/verify_corpus.py`：独立原始字节核对、源文件SHA256、174个加密v6描述符、58个空虚拟strap表、两个私有表边界和稳定差异。
- `mods_schema/`：核心静态解析证据。
- `enum_followup/`：枚举单位补查、原始4090反例和指令锚点。
- `gddr7_docs/`：主源标准/厂商/开源代码证据。
- `reports/`：实际样本矩阵、CSV、日志和验证输出。

最终验证：29份源文件SHA256未变，全部脚本断言通过。没有生产可刷写的修改ROM。

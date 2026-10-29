# GB202 v6前缀：确认外置表装载记录与真正stored-body边界

## 结论

**有实质进展：20字节前缀不是随机明文，也不是目前有证据支持的“压缩块目录”。它把设备端载荷与ROM中的Devinit/BIT数据表连起来，最符合“外部表复制/分配/重定位元数据”。**

1. 四份ROM/nvfw共24个描述符，`u16(descriptor+0x1a)`严格等于前缀记录数，`u16(+0x1c)`为20或零。**word1长度不包含这些记录**：对四份样本的app19/app15，`descriptor+0x50+N*20+word1`恰好等于下一个descriptor，8/8成立。之前`descriptor+0x50`直接取word1会把记录当body头，并截掉body尾。
2. 58条非零源指针记录，**58/58精确匹配另一条独立BIT指针**；源数据是结构化表，不是需要解压才能看见的字节。id35同时与公开规格里的`BIT.I+0x14` Devinit Tables Pointer及`+0x16` Size完全相等，8/8成立。已经按这些边界提取。
3. 记录不是统一low16=1；app19和app18有**type=2**。把type2也强行当`source_offset,compressed_size`会错误切片。
4. 校正后的body、候选code/data切分、源表边界共604项有界raw-deflate/LZ4/zstd测试，严格有效命中零。**并未发现设备端CPU执行入口/ISA/可执行明文。** 现在障碍可具体定位为body本身及其装载/认证语义，而不是“整个region都是encrypted”。

只读源文件、静态格式解析；没有运行ROM/MODS/updater代码，没有硬件访问。所有写入仅本目录。

## 1. 可复现的前缀与body切分

以下是实测布局，不冒充公开v6结构定义：

```text
D = Falcon表指向的descriptor文件偏移
assert u8(D+1)==6 && u16(D+2)==0x50
S = u32(D+0x04)
N = u16(D+0x1a)
R = u16(D+0x1c)
assert (N==0 && R==0) || (N>0 && R==20)
records = ROM[D+0x50 : D+0x50+N*R]
body_start = D+0x50+N*R
body_end   = body_start+S
```

四样本记录数：app07=0；app18=4；app19=12；app15=3；app24/FSP_RUN=0。app23/OOBHUB在5090/HPE为3，在PRO/Dell为0，与有没有结构化前缀完全一致。

### 校正的body区间（左闭右开，原文件绝对偏移）

| 样本 | app19 | app15 |
|---|---|---|
| 5090 | `[0xc8130,0xe9c30)` | `[0xe9cbc,0xef7bc)` |
| PRO | `[0xc67c8,0xe79c8)` | `[0xe7a54,0xecf54)` |
| HPE | `[0xce5d4,0xf12d4)` | `[0xf1360,0xf6960)` |
| Dell | `[0xcc8c0,0xee9c0)` | `[0xeea4c,0xf404c)` |

这8个body结束均**精确落在独立Falcon表指向的下一descriptor**。不是以随机低熵终点猜长度。app07的零记录边界也在四份样本精确相接。

5090其他校正区间：
- app18：`[0x10e1a4,0x11ada4)`，后到下一descriptor有0x560字节，未命名这些间隙。
- app23：`[0xef848,0x10da48)`，后到下一descriptor有0x6bc字节，未命名。
- FSP_RUN：`[0x11b354,0x144754)`；N=0，所以此前入口候选偏移没有变化，也没有新magic。

这些body已提取为`slices/5090_app{07,18,19,15,23,24}_stored_body_candidate.bin`。它们是格式切片，**不是成功解出的代码**。对app18/app23等不能用上述间隙猜测签名、压缩尾或完整外层认证对象。

## 2. 20字节record有可独立交叉验证的字段

小端布局：

```text
+0x00 u16 type       // 实际有1与2
+0x02 u16 id         // tag高16位；稳定的表/对象标识候选
+0x04 u32 A
+0x08 u32 B
+0x0c u32 C
+0x10 u32 E
```

### type=1且A非零

证据最强的解释：
- A：**ROM逻辑地址形式的源表指针**。
- C：**源表字节数**，多个标准表头、公开BIT长度字段精确确认。
- B：设备端装载目的位置候选，不是body文件内偏移。
- E：目的分配/保留长度候选，所有记录`C<=E`。例如C为0x3c、E为0x40，不应机械命名为“压缩前后长度”。

该四样本中源地址转换：

```text
source_file_offset = legacy_base + A + (expansion_offset if A>0xffff else 0)
```

基址由既有`memory_corpus.load`重新解析PCI链：5090=0x38000；PRO=0x35800；HPE/Dell=0x3b000；expansion_offset全部0x18000。阈值及映射是这些样本的既有BIT逻辑地址约定，不声称适用于任意新ROM布局。

**独立指针交叉表（四样本均成立；OOBHUB仅5090/HPE含记录）**：

| id | A匹配的BIT字段 | C的额外边界证据 |
|---|---|---|
| 35 | `I+0x14/u16` | `I+0x16/u16`公开Devinit Tables Size，完全相等 |
| 89 | `i+0x6e/u32` | 源头`10 08 89 00 <u32 length>`，8+length=C |
| 8a | `i+0x72/u32` | 源头`10 08 8a 00 <u32 length>`，8+length=C |
| 12 | `P+0x28/u32` | 本任务不强命名复杂表头 |
| 14 | `P+0x20/u32` | 同上 |
| 81 | `P+0xb0/u32` | header_length+record_length*count=C |
| 82 | `P+0xb4/u32` | 同上 |
| 70 | `M+0x1d/u32` | 同上；原memory_corpus的M1d表 |
| 71 | `M+0x21/u32` | 同上；原memory_corpus的M21表 |
| 72 | `M+0x25/u32` | 源指针匹配；未证明完整复杂表长公式 |
| d2 | `i+0x94/u32` | 源指针匹配；简单嵌套表长度猜测失败，保留unknown |
| 1d | `P+0x58/u32` | header_length+record_length*count=C |
| 1e | `P+0x5c/u32` | 同上 |
| 80 | `P+0xdc/u32` | 同上 |

注意大写`I`与小写`i`是不同BIT token。`analysis.json`保留实际字节、全部匹配、SHA256与候选目的区间。

### 用户给的5090 app15实例，现在可以有根据切源片段

| id | A | 真正源文件区间 | B（候选目的） | C / E |
|---|---|---|---|---|
| 35 | 0x47a7 | `[0x3c7a7,0x3cc64)` | 0x57c0 | 0x4bd / 0x1100 |
| 8a | 0x574b9 | `[0xa74b9,0xa7c49)` | 0x4000 | 0x790 / 0x790 |
| d2 | 0x1936d | `[0x6936d,0x69f7c)` | 0x68c0 | 0xc0f / 0xc13 |

id35是公开规格所称“contiguous segment containing tables required by Devinit opcodes”，不是一个已确定入口的Devinit程序；不要把此数据块直接当Falcon/x86代码。

源切片分别为：
- `slices/5090_app15_record00_id35_source.bin`
- `slices/5090_app15_record01_id8a_source.bin`
- `slices/5090_app15_record02_idd2_source.bin`

跨固件例：id35源指针PRO仍0x47a7但C降到0x3fc，HPE/Dell指针变0x47a3、C=0x4bd；独立BIT.I的pointer/size同步改变。因此不是恰好落到一块看起来结构化的数据。id89/8a自带匹配的id和长度，再提供第二类独立约束。

### type=1且A=0、type=2不能照搬源切片规则

app18有id44/id85/ide3三条type1，A=C=0而B/E非零；本任务**不把ROM基址当源地址，也不伪造零填充**。可能是运行时提供的对象，待consumer确认。

app19的type2/id2、id3：C=E=0，但A/B非零。若将其解释为`[目的起点A, 长度B]`，与相邻type1目的区间严密相接。例如5090：

```text
type2/id3 [0x159d0,0x15a40)
type2/id2 [0x15a40,0x17eb0)
type1/id35 [0x17eb0,0x18fb0)
type1/id12 [0x18fb0,0x194dc)
```

所有有记录的描述符按此模型目的区间无重叠；四样本app19/app15最小目的地址均等于`u32(D+0x10)+u32(D+0x14)`，支持“既有数据段之后追加外部表”模型。app19其他相邻间隙多为对齐或固定保留空间，但有0x3e4、0xe30等大间隙，不把它描述为完全连续紧密打包。

这足以否定“B是相对stored-body偏移”的直觉：app15目的0x68c0大于stored_size=0x5b00，而源却能由独立BIT指针与长度精确确认。**不能据此确认type2具体执行memset、malloc还是另一种重定位；也没有证明B属于DMEM物理地址而非虚拟/复合地址空间。**

## 3. 分块/压缩探索与未解决入口

`decompression.json`记录604次测试，零有效流：
- 校正后的整个body，与此前误含前缀的old_immediate作为对照。
- 仅在`u32(D+0x0c)+u32(D+0x14)<=S`时测试这两个尺寸的候选子块；这只是有头字段的假设，不冒充已经恢复IMEM/DMEM布局。
- 上述58条源表的精确C字节，解压目标长度E。
- raw deflate要求EOF、全输入消费、无剩余、最大4MiB；已知目标长度时还要完全一致。
- LZ4 block使用外给输出长度，要求完全相等；body还单独标注1/2/4倍猜测比例，未将其当作格式事实。
- zstd严格无尾随数据；不是只搜magic。

源数据不解压即有有效表头/长度/独立指针，多个E-C=4或1，以及id35固定保留0x1100而源C随ROM变化，更支持复制/分配，而非压缩规则。测试失败不证明不存在私有压缩、分段认证/加密或未识别封装；本次不再无目标地对随机字节逐偏移穷举。

**没有设备端执行入口。** FSP_RUN仍是descriptor内标识，N=0且body无可验证容器入口；app15/app19现在能提供正确body起点和外置数据来源，但入口PC、ISA、映射、认证/解码consumer仍缺。没有做随机反汇编，也没把能反汇编等同成功。

有价值的下一步是找**读取descriptor+0x1a/+0x1c、以20步进、按u16 type=1/2分支、消费BIT逻辑源地址**的设备端/更新器consumer。这比找`FSP_RUN`字符串或盲扫压缩头明确得多。先不要把B当文件偏移拼“可执行镜像”。

## 4. 资料核查与限制

- 官方BIT文档已联网保存：`BIT-spec.html`，来源 https://raw.githubusercontent.com/NVIDIA/open-gpu-doc/master/BIOS-Information-Table/BIOS-Information-Table.html 。`_bit_nvinit_ptrs`明确Devinit Tables Pointer/Size，支持id35的独立语义；**它没有提供本次v6 prefix的正式定义**。
- 本地开源驱动：`/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c`，145–188行为v2/v3结构，653–661仅选v2/v3；不能拿它们的body字段偏移套v6。
- 已读既有静态报告`/home/user/rt_5090_project/parallel/nvflash_v6_parser_reverse.md`：nvflash5.877把v6落到旧GFW-v1默认分支，不能用其打印字段“证明”v6。此次只对nvflash做strings静态检索，未重新恢复或执行该parser。
- 先读指定`firmware_probe/REPORT.zh-CN.md`与完整`probe.json`；本报告修正其immediate-region定义，不改原结果文件。

## 5. 产物与复现

```sh
/home/user/rt_5090_project/vbios_diff/gb202_boot_upstream_20260911/.venv/bin/python -B \
 /home/user/rt_5090_project/vbios_diff/gb202_boot_upstream_20260911/payload_research/analyze.py
```

脚本只读取四份源ROM/nvfw与既有本地解析模块，禁写pycache，输出固定在自身目录。

- `analysis.json`：四样本SHA、24描述符、全部records、源指针与BIT匹配、边界/目的区间验证。
- `decompression.json`：604个精确记录的有界测试及零命中。
- `summary.txt`：校正body区间摘要。
- `slices/`：58份源片段（包含不同app引用同一表的重复副本），以及5090六份body候选。
- `slices_manifest.json`：上述64个切片的精确路径、长度和SHA256。

实际完成两次脚本运行；公开BIT的id35 pointer/size、简单表头长度和所有边界assert通过。另对58/58非零源记录都有独立BIT指针匹配作了断言检查。没有修改源ROM或其他工作目录。

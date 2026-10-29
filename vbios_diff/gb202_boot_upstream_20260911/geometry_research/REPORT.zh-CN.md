# GB202 明文几何候选数组：离线独立核查

## 结论（证据等级分开）

1. **所有者已闭环，不只是值匹配：29/29 的数组均在 BIT 小写 `i` 的 `+0x6e/u32` 指向的 typed blob `0x89` 内。** 其头为 `10 08 89 00 <u32 payload_length>`，总长为 `8+payload_length`。29/29 同时有 Falcon application **0x19** 的 v6 descriptor 后置20字节 source record，id=0x89，source 精确等于上述 BIT 指针，size/alloc 精确等于 blob 总长。数组不在任何六个 encrypted-flag stored-body 区间内。
2. **尚未闭环 blob 内字段 → 0x9a0200/0x9a0204/其它寄存器写入。** CFG0/CFG1 是候选名；不能把 id89直接正式命名为“显存devinit几何结构”，也不能将外置表被app19引用等同于已证明其寄存器写入语义。可信边界停在“被app19 source record引用的明文typed数据区”。
3. **26个标准5090/5090D四组候选数组完全一致**：CFG1候选13项全 `1e66b000`；两个后续13项块全0。
4. **三个PRO的原始前13配置一致**：CFG1候选0/7=`1e77b000`，4=`1e88b000`，其余=`1e66b000`；两个后续块都是仅config4=`0000c000`。
5. **重要布局例外：HPE 98.02.9E是16项，而非13项块！** 前13项之后CFG0另有3个`06920000`，CFG1另有3个`0144b000`；两个后续块也各16项。若强套13项，会把c000错分到config7/10。这不是strap_count变化：三PRO的BIT M strap_count仍13，MEM TYPE record_count仍16。块长目前由重复结构、边界及共同前导8字节定位，未得到正式schema；不能将strap_count直接作为id89数组长度。

## 独立所有权与引用链

逻辑指针换算遵循本corpus已验证PCI-chain规则：`absolute = legacy_base + expansion_offset + logical_ptr`（这些指针均>0xffff）。每个样本重新调用 `memory_corpus.load`，且ROM SHA256与corpus记录相等。

| 样本 | id89绝对范围（末端不含） | CFG0候选 | CFG1候选 | 后块A | 后块B | 项数 |
|---|---|---|---|---|---|---|
| Astral E1 | 9cf75..a74b9 | a31d5 | a320d | a3241 | a3275 | 13 |
| PRO WS | 9a9dc..a5750 | a1054 | a108c | a10c0 | a10f4 | 13 |
| HPE 9E | a0d16..ad45a | a8176 | a81ba | a81fa | a823a | 16 |
| Dell 8D | a085b..ab747 | a7043 | a707b | a70af | a70e3 | 13 |

Astral：BIT.i+6e值`0004cf75`，blob总长`a544`。app19 source record绝对`c8054`：

```
00890001 0004cf75 00008a00 0000a544 0000a544
```

PRO WS对应record绝对`c66ec`：

```
00890001 0004d1dc 00008d00 0000ad74 0000ad74
```

格式：`tag/id+type, ROM logical source, candidate destination, copy size, allocation size`。destination语义沿用既有元数据分析，仍标为候选而不是实际加载后的地址证明。Astral四块相对blob偏移`6260,6298,62cc,6300`，若destination解释成立，其对应候选目的地址`ec60,ec98,eccc,ed00`。PRO WS相对偏移`6678,66b0,66e4,6718`，对应候选目的`f378,f3b0,f3e4,f418`。

v6 descriptor固定头长80，record count在`+0x1a/u16`、stride在`+0x1c/u16`，记录区在固定头**之后**，不能只扫描80字节头。stored body候选起点还须加`count*stride`。复现脚本明确使用这一边界。

这与公开BIT.I+14 Devinit Tables段不同：**小写i、id89是本次owner；大写I、id35不是。** 官方BIT文本对大写I的描述不能自动套给私有i+6e。

## 数组原值与实时读值边界

26标准样本CFG0候选13项：

```
1e878083 1e078083 1e078083 04168003 04168003 04168003 04168003
1e078083 1e078083 04168003 04168003 04168003 04168003
```

三PRO前13项CFG0候选：

```
1e478083 1e078083 1e078083 04168003 1ec78083 04168003 04168003
1e478083 1e078083 04168003 04168003 04168003 04168003
```

全部块前共用8字节`ff ff ff f0 00 00 00 01`；CFG0候选与CFG1候选之间u32=`ffff8000`。它的mask含义未被consumer代码证明。

用户授权的既有读值仅作外部线索，本worker未访问硬件：`9a0200=3e8f0883`不等于ROM config0 `1e878083`，异或`20088800`。因此“查到相似数组”甚至不证明CFG0未经修改直接写入。`9a0204=1e66b000`与所有13个标准候选项相同，也**不能反向确定选中哪个配置**。

## c000、24Gb与非2次幂：能说与不能说

- 三PRO在正确块长下，两个后块config4同时出现c000；其前13项其它索引为0，所有26标准样本为0。MEM TYPE非Skip及原始记录也逐样本保存在JSON；这是多样本相关性，不能单靠相关性证明寄存器、单位或用途。
- 数学上`0xc000=49152=3/4*65536`，确实**兼容**“24Gb器件在更大2次幂地址包络中使用3/4范围”的假说；但也可能是编码位域、计数、分段上限等。没有字段名、单位、consumer的移位/比较/写地址证据，不应写成已证“24Gb地址上限”，更不能因为两份值就推断rank/通道数。
- 未从这次ROM/ELF工作证明MemoryInfo density7=24Gb。既有MODS parser证明density code位置，不证明单位枚举。也未证明CFG1 nibble8是特定行数、bank/rank组合；即便某几何域扩大，范围限制仍可独立限制可用地址。因此**row8→128GB、density7→24Gb、c000→固定容量**均不能作为本任务结论。
- 公开驱动确有独立的最终范围消费路径：`src/common/inc/swref/published/blackwell/gb100/dev_fb.h:27..32`定义`1fa3e0`、MAG[27:4]、SCALE[3:0]；`src/nvidia/src/kernel/gpu/mem_sys/arch/pascal/kern_mem_sys_gp102.c:44..55`注释Devinit计算range，并使用`MAG << (SCALE+20)`，该GP102分支另有ECC 15/16调整。该证据表明容量不必由row指数单独决定，**不把GP102的所有ECC字段套用GB202**。
- 给定实测`1fa3e0=0007f5f0`，MAG=`7f5f`、SCALE=0，按此已有GB202消费路径一致的公式为32607MiB、约31.8428GiB，且`1183a4=7f5f`。这是最终usable range线索，不是c000字段来源证据。

## MODS静态探索：未假冒闭环

只对ELF `/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods` 做字符串搜索、反汇编和候选引用扫描，没有执行它。

- 日志字符串`NVRM: could not unpack meminit table data` VA=8e105a0，指令引用67168aa；附近67070e0/6e808c0链保存在`meminit_parser.asm`。**未证明该旧解析路径读取id89**，不能因字符串叫meminit就认领本次数组。
- `cfg0_writer_candidate.asm`中完整函数700f500..700f620确有基于对象字段修改CFG0并日志输出的路径：700f567设置r8d=200、调用HAL+738解析地址，再700f581调用6abc210。该函数还改若干位，说明存在运行时合成路径。但**未证实其HAL属于GB202，也没连接其输入到id89**。
- `candidate_offset_refs.txt`为MODS中候选blob偏移/目的地址的原始字节匹配，含假阳性，不能当调用图或解引用证明。没有恢复GB202对应的encrypted app19写寄存器代码。

## Verification

运行：`python -B geometry_research/analyze.py`，29样本全部通过：输入SHA256、PCI/BIT重新解析、typed blob头与边界、唯一CFG1候选、共同前导边界、app19 source/size/alloc匹配、六个stored-body不重叠、26+3分组断言。

结果：标准四数组hash组=1；PRO完整数组hash组=2（WS/Dell 13项与HPE16项的布局差异）；三PRO前13项一致且两个后块仅索引4=c000。`verification.txt`是最终通过运行日志。首轮13项假定被HPE数据否定后已修正，JSON使用修正后的16项布局。

安全范围：全部新写入仅在本geometry_research目录；没有执行MODS、ROM、GPU命令或读取设备节点。未开展网络搜索；已优先核查本地公开driver与既存公开BIT文本。仍需app19解密/公开schema/对应consumer才能完成精确写入链及c000用途证明。

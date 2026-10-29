# GB202 Memory Information / MEM TYPE：MODS 静态字段与选择链

## 核心结论

**已从真实解析指令和日志参数的数据流确认，不是按字符串猜字段：**

- record `+1` **低四位是内存 timing/strap index，高四位是 vendor**，不是整个字节的 density/rank。
- record `+2` **低四位是 vendor revision，高四位是 density code**。
- record `+3` **低三位是 Memory Organization code（Mem Org）**，不是 density 或 manufacturer；`03→02` 是 organization 改变。尚未从此二进制证明这两个枚举准确对应 x32/x16，更不能直接叫“rank 1/2”。
- `+0[3:0]=0xd` 被翻译为 RM RAM type `0x15`，其实际字符串映射 `_GDDR7`；`0xf` 直接 Skip，不进入有效记录列表。
- PRO config4 的差异是 **strap match 4 / timing index 4 / vendor 1 / rev 0 / density code 7 / organization 2**；5090 config0 是 **0 / 0 / 1 / 0 / 6 / 3**。PRO config0 仍然 density code 6，只有 organization 为 2。
- 可选记录由表头 selection method 控制：method 0 按 `_STRAP_MEMSEL` 匹配，method 4 按 `_MEMINFO_INDEX` 匹配原始记录序号。**外部 strap 不会使 Skip 记录变成有效大容量记录，也不能创造表中不存在的配置。**
- 本次只证实 MODS/RM 的表解释和选择机制，**没有证明 5090 存在可由外部电阻 strap 激活的大容量有效配置，也没有证明 GDDR7 information 自动改写此表的 density/organization/selection**。

## 证据定位与可信边界

输入 ELF：`/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods`。
ELF 是 stripped；动态符号 4182 行，没有所需 BIOS 函数命名。日志 source 名也被替换为 `0x0002a2` 等。因此下列函数按**地址和行为命名**，不是冒充恢复出的 C++ 符号。

本报告所有代码/只读字符串 VA 落在首个 PT_LOAD：**file offset = VA - 0x400000**。例如解析器 VA `0x672c9e0` → file `0x632c9e0`。

关键文件：`meminfo_parser.asm`、`format_unpack.asm`、`strap_to_timing_index.asm`、`strap_accessor.asm`。反汇编由 Capstone 从只读 mmap 数据产生，没有执行 ELF。`static_refs.py refs/calls` 是候选字节扫描，可能有假阳性；正文引用的目标已用完整指令/基本块校验，不能把候选列表本身当调用图。

## 1. 表格式与解包

解析/选择函数 VA **0x672c9e0**：

- `0x672cc15` 取 VBIOS 对象 `+0x43c` 的 Memory Info Table 指针。
- `0x672cc24→0x67056a0` 读版本；`0x672cc35` 要求 `0x10`。
- `0x672cc3f` 用格式串 VA `0x9183fa4` = `5b` 读取五个表头字段；header size 要求 >4。header7 可以接受，但本解析器没有解读 header+5/+6。
- `0x672cc75` record size switch；record22 走 `0x672d1ab`，选择格式 **`1d1b1w5b1w2d`**（VA `0x9184b7f`），长度恰为22。
- `0x672cd78..0x672cd9a`：`entry_offset = table_pointer + header_size + raw_record_number * record_size`。
- 解包调用链 **0x6705600 → 0x6e80d10 → 0x6e80b30**。后者 `0x6e80ba1` dword、`0x6e80be4` word、`0x6e80c00` byte，均写一个32位输出槽（`0x6e80ba8..bb3`）。这验证了栈上 dword 与原始 ROM offset 的对应，而非误把展开后的偏移当 ROM 偏移。

22字节记录→临时栈（解析循环入口 rsp）：

| ROM | 临时槽 | 大小 |
|---|---|---|
| +0..3 | +0x40 | dword |
| +4 | +0x44 | byte 扩展到 dword |
| +5..6 | +0x48 | word 扩展 |
| +7,+8,+9,+10,+11 | +0x4c,+0x50,+0x54,+0x58,+0x5c | 五个 byte 各扩展 |
| +12..13 | +0x60 | word 扩展 |
| +14..17,+18..21 | +0x64,+0x68 | 两个 dword |

## 2. 原始字段位图

设 `D=LE32(record+0)`、`F=record[4]`、`W=LE16(record+5)`。有效记录的内部结构长 **0x24**。

| ROM 字段 | 内部 offset | 实际运算 / 已证含义 | 指令 VA |
|---|---:|---|---|
| +0[3:0] | +4 (u32) | type；0xd→0x15 GDDR7；0xf→Skip | 0x672cda7、0x9cedb60 jump table、0x672cdb5 |
| +0[7:4]、+4[4] | +8 | `(D>>4)&15 \| F&0x10`，strap match | 0x672cdd7..cdfa |
| +1[3:0]、+4[6] | +9 | `(D>>8)&15 \| (F>>2)&0x10`，timing index | 0x672cdfe..ce17 |
| +1[7:4] | +0xa | vendor | 0x672ce1b..ce26 |
| +2[3:0] | +0xb | vendor revision | 0x672ce2a..ce35 |
| +2[7:4] | +0xc | density code | 0x672ce39..ce44 |
| +3[2:0] | +0xd | Memory Organization | 0x672ce48..ce53 |
| +3[3],[4],[5],[6],[7] | +0xe,+0x12,+0xf,+0x10,+0x11 | 五个独立布尔字段，名称未确认 | 0x672ce57..ce9b |
| +4[3:0] | +0x13 | group / logical-part destination | 0x672cea0..cea8 |
| +5..6[12:0] | +0x14 u16 | frequency code | 0x672cead..cec9 |
| +5..6[13] | +0x16 | 未命名 | 0x672ceb7..ced5 |
| +4[5] | +0x17 | 未命名 | 0x672cec3..cedc |
| +11 | +0x18 | 未命名 | 0x672cee3..cee7 |
| +12,+13 | +0x19,+0x1a | 未命名 | 0x672ceee..cefd |
| +14..17,+18..21 | +0x1c,+0x20 | 未命名 dwords | 0x672cf04..cf13 |

本解析函数未消费 +7..10，不能解释为整个 VBIOS 都不使用；PRO config4 的 `+9=01` 差异因此仍需其它解析器/firmware 补证。表头扩展和尾部字段不能靠这段代码擅自命名。

### vendor/revision/density 的闭环证据

字符串 VA `0x8e14700`：`Strap Idx Type Vendor/Rev Density Grp Freq`。
格式 VA `0x8e147c8`：`[%1d] %02x %02x %6s (%2x->%2x) %4x/%2x %1x %1x %d`。
`0x672cf1c..cf35` 明确从内部 `+0x14,+0x13,+0xc,+0xb,+0xa,+4` 取值；`0x672cf6a..cfa3` 按 SysV varargs 顺序送入格式化器。这把上表字段名与实际掩码解包相连。

内存类型字符串表 VA **0x9cedc40**，每项16字节；值21→字符串 VA `0x9184c89` `_GDDR7`。ROM nibble13 的 jump table 项进入 `0x672cdb5`，写内部 type=21。

公开驱动补证：`src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080fb.h:231..245,439..448` 明确 MEMORYINFO_VENDOR_ID 来自 VBIOS Memory Information Table，1=Samsung，6=Hynix，15=Micron。样本 vendor=1；**+2=0x60 不是 Hynix ID 6**，6在 density 高半字节中。

### organization 的闭环证据

解析结果内部 `+0xd` 被选择后驻留 framebuffer 对象 `+0x898d + group*0x24`。
函数 VA **0x6e5b390** 在 `0x6e5b449` 读取这个字段，存临时 `rsp+0xa7`；`0x6e5b547..b557` 检验 organization 是否为2或3，不合格跳 `0x6e5db50`。
那里把该数值作为 `%d` 参数，输出实际字符串 VA **0x8eda320**：

`NVRM: Mixed mode partition has unsupported Mem Org %d`

因此“Mem Org”有数据流证据。`0x6e5cecf` 还以 code==2 控制内部模式字 bit22；`0x672b57a` 和 `0x672bbd2` 附近按 code==2 选择另一组 timing 位域。**没有拿到 x16/x32 的具名枚举定义，不能把合理推测当已证事实。**

## 3. strap / index 选择链

### A. 有效记录构建（0x672cd78..0x672cfe0）

原始序号 r14d 每条递增；有效记录计数 ebp 只在非Skip时递增。
内部 `+0` 保存的是 **原始记录序号**（`0x672cdd3`），不是过滤后的紧凑序号。
`type nibble=15` 的 jump table 项直接进入 `0x672cfac`，跳过所有填充和有效计数步骤。
表头第5个字节 `header[4]&7` → selection method（`0x672cfd9..cfe0`）。

### B. method 0：按 `_STRAP_MEMSEL`

- `0x672ca10..ca18` 调 **0x6711f00(gpu,5,0,0)**，日志 VA `0x9184b8c` 标明 `_STRAP_MEMSEL`。
- `0x672ca70..ca76` 对有效记录的内部 `+8` 与返回值比较。
- 匹配后 `0x672ca78..ca9b` 按内部 `+0x13` 的 group 复制 0x24 字节至各 logical-part 槽。
- 匹配数与 logical partition 数比较，失败可能返回 0x4a，也有 ignore 标志路径（`0x672caa7..cae5`、`0x672ccd0`）。不是无条件任取第一条。

**0x6711f00** 优先使用两张 VBIOS 表，由 **0x67070a0** 返回地址，解析条目并匹配 selector ID=5。`0x67120ed` 取描述符索引，`0x6712136..2158` 取 lsb/msb，**0x6712187→0x6711480** 按描述符读数据；`0x67121b3..21bd` 移位、掩码并拼接结果。若这些表缺失/不适用，`0x6711f90` 回退 **VBIOS HAL callback +0x1d0**。因此不能假定 MEMSEL 总是一个固定外部脚位值。

HAL 构造函数 **0x6b64650** 的 +0x1d0 候选包括：

- **0x6e99c90**：selector4/5 读取寄存器地址常量 `0x10ebb0`，取[4:0]。
- **0x6ea0e20**：selector4/5 读取常量 `0x118fb0`，取[4:0]。

两者均调用 **0x687b960** 通用32位寄存器读取路径，而不是 `gb202_reghal_offline.py` 的压缩RegHal ID解析器。**不要把这些地址常量再当 RegHal ID 解码。** 本次未完成 chip selector→GB202 的绑定证明；不可据此给出板级电阻位置或宣称 5090 必然使用哪一个寄存器。

### C. method 4：按 `_MEMINFO_INDEX`

- `0x672cb05..cb0b` 调 VBIOS HAL **+0x1e0**。
- `0x672cb3f` 与有效记录内部 `+0`（原始 record number）相等匹配。
- `0x672cb54..cb74` 同样按 group 复制选中记录。
- 找不到返回 0x5b，并输出 `_MEMINFO_INDEX %x not found in MemoryInfoTable!`（VA `0x8e14860`）。

HAL +0x1e0 静态候选包括 **0x6ea0d90**：`read32(0x205e4)>>2 &31`；**0x6ea36b0**：`read32(0xad05e4)>>2 &31`；老分支 **0x6e99d10**：`read32(0x10e5c0)&31`。后者和前者属于不同 HAL 分支，不能混作同一 GB202 实测链。**这类 INDEX 可以是已初始化的状态；尚不能认定它直接来自外部 strap，或由 GDDR7 自动识别写入。**

方法1..3明确打印 `Selection methods not yet implemented`；>4分支直接结束，不能将其推导为自动探测。

### D. 选中记录→后续 timing index

函数 **0x6712970** 在 `0x67129a2` 调上述解析/选择函数；成功后 `0x67129b2` 取 `FB+0x8989+group*0x24`，即记录内部 `+9`，作为后续 memory strap/timing index；与 VBIOS `+0x42c` count 检查。

失败回退 `0x67129ec→0x6711f00(gpu,5,0,0)`，再按可选映射表 VBIOS `+0x430` 查一个字节（`0x67129f1..2a06`）。这说明 **MEMSEL、MemoryInfo 原始记录序号、timing index 是不同层，不能都叫 config index 然后直接互换**。

## 4. GDDR7 information 自动识别：找到什么/没找到什么

找到独立的 MODS DRAM information 获取路径：

- **0xd9b050** 检查对象/世代码，code11走 **0x114e0c0**（preOS PBI），其它 >10 走 **0xded740**（NVDM）；成功设 `out+8=1`。
- 失败真实分支分别在 **0xd9b0d9 / 0xd9b0b8** 输出“Failed to get DRAM information from VBIOS preOS PBI/NVDM. Will attempt to read from the DRAM.”。
- 直接调用点 **0xda4e21** 在 MODS 的初始化遍历中；这段证明读取/缓存 DRAM 信息的能力，**不证明它是 VBIOS 上电 devinit 的 density/organization 决策算法**，也没证明 code11 就是GB202。
- 显示侧 **0x1959e80→0x1959c20** 有 `Density/chan : %u Gb`（VA `0x9103a41`），并存在不同信息格式的 density 枚举解码函数 `0x19594a0/0x19595a0/0x1959740`。这组枚举属于另一信息结构，**不能直接套在 MEM TYPE density code 上**。

已分析的 MEM TYPE parser 本身只按 ROM 解包并按 selector选表；没有沿读取GDDR7 information→覆盖density/organization→重选strap的已证路径。但有未解析的 HAL/firmware 边界，**不能反向宣称所有VBIOS/GSP/boot固件都绝无自动density/clamshell机制**。

## 5. 样本与可操作性边界

`decoded_samples.json` 为纯数据脚本转录结果。输入来自任务文字，没有读取实际 ROM 文件；PRO config0 由所述 +3 差异构造。header+4 原始值未给出，故不能在 method0 与 method4 之间替实际固件下结论。

| 样本 | type | match strap | timing idx | vendor/rev | density code | Mem Org |
|---|---|---:|---:|---|---:|---:|
| 5090 config0 | GDDR7 | 0 | 0 | 1/0 | 6 | 3 |
| PRO6000 config0 | GDDR7 | 0 | 0 | 1/0 | 6 | 2 |
| PRO6000 config4 | GDDR7 | 4 | 4 | 1/0 | 7 | 2 |

- density 6→7 是已证编码变化；6=16Gb、7=24Gb 如需定量结论必须结合正式表规范，**本次未从MODS代码建立这组单位换算**。
- 5090 config4 Skip（用户给定）若为 nibble0xf：method0没有相应有效项；method4不会找到原始序号4。其它项是否可用须检查整张5090表，不能仅由这三条片段判断。
- 这些结果不构成刷写/修改电阻方案；没有运行MODS、NVFlash、设备命令或硬件访问。

## Verification

- `file`、`readelf -l`、`nm -D -C` 检查 ELF 格式/地址转换/符号边界。
- `strings -a -t x` 定位候选；只读 mmap + Capstone 沿真实指令核对解析及选择链；一次 `objdump -d` 复核指令边界（其“最近动态符号+大offset”标签不被当成真实函数名）。
- `python .../mods_schema/decode_meminfo22.py`：3个给定样本字段断言及22字节格式对应，见 `decoded_samples.json`。
- `verification.json` 包括输入SHA256及关键解析指令/日志字符串锚点断言。
- 所有新文件仅在本 `mods_schema/` 目录。探索性 `*.asm` 可能带首尾邻接函数片段；正文引用的块才是已确认范围。

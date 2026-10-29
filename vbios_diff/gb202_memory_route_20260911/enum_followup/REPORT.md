# MEM TYPE density / organization：限时离线补查

## Result

**两个精确枚举仍未达到可证明的定量结论。** 本次没有把独立 DRAM-info 枚举偷换成 MEM TYPE，也没有把 PRO 板型当作 org=2 的 x16 定义。

1. **MEM TYPE density 6→16 Gb、7→24 Gb（每颗、分别约 2 GiB / 3 GiB）只能保留为硬件配置一致性推断，不能写成已恢复的枚举或换算单位。** 未找到从 `FB+0x898c` 到容量数字/单位的代码闭环；不能确定它规范上以 die、package、channel 还是其它逻辑单元为参照。尤其不能将 6/7 当作总显存大小，也不能由 6→7 推导“翻倍”。
2. **org=2 / org=3 已证会选择不同 timing 子字段，以及在 mixed-partition 路径设置/清除内部模式 bit22；尚不能证明具体 x16 / x32，更不能证明 rank1 / rank2 或单面 / 双面。** 4090 24GB/48GB 两份 ROM 的有效 MEM TYPE 记录不仅 org 相同，density 也相同，原始22字节整条相同。
3. 新增防误用证据：**同一 ELF 的独立 DRAM-info 三套 density 解码中，code6 分别返回 32、8、12；第三套 code7 返回16，根本不是 MEM TYPE 拟议的 6→16、7→24。** 这些返回值由显示路径按 `Density/chan : %u Gb` 使用；不能跨结构借用。
4. 全部29份 GB202 输入已经重新只读核对真实文件 SHA256 和 MEM TYPE 每条原始字节。注意：PRO 的0/7为6/2、4为7/2是正确的，**但若“有效项”定义为 parser 的 non-Skip，三份 PRO 还保留1/2/3/8为6/3**；不能把“存在有效项”写成“该成品实际选中此项”。

## 1. density：直接消费者与证明边界

ELF `/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods`。本报告代码和表均在首个 LOAD 内，`file_offset = VA - 0x400000`；SHA256 见 `verification.json`。

`parser_fields.asm` 再次从目标字节反汇编：

```text
0x672ce3e c1e914       shr ecx,20
0x672ce41 83e10f       and ecx,15
0x672ce44 884c170c     mov [rdi+rdx+0xc],cl  # density
0x672ce4d c1e918       shr ecx,24
0x672ce50 83e107       and ecx,7
0x672ce53 884c170d     mov [rdi+rdx+0xd],cl  # org
```

复核 `../mods_schema/decoded_field_refs.txt` 的直接 density displacement 命中：

- `0x67e2b6d` 比较2；`0x67e2c56` 比较3；`0x67e2cf7`、`0x67e2dd8` 比较4。均是 vendor/type/附加字段限定下的内部标志分支，不是容量换算。
- 补查 `0x6fd1110..1190`：`type==8 && vendor==0xf && density==5` 时设置 `FB+0x8c48=1`。原始指令 `0x6fd1151: 80b88c89000005`。继续追 `0x680bf22` 的标志消费者仍只是其它模式位操作，未出现 Gb/MB 数值闭环。
- 原 refs 中其它 `0x898c` 字节命中包含 call 相对位移和无关 immediate，并非全部字段访问。

这只是**已核查直接引用范围**；结构复制、改基址、指针别名、间接 HAL 或 firmware 路径可能不带该绝对 displacement，因此不是“整个 MODS 没有任何换算”的证明。

若事先独立确认5090的32GiB由16颗组成、PRO的96GiB由32颗组成，而且确认使用了相应条目，则分别可算得16Gb/颗、24Gb/颗。这支持候选解释，但 **ROM 内包含一个条目 ≠ 该卡实际选择了它**；产品资料所写16–24Gb并不定义 NVIDIA MEM TYPE nibble。公开头文件及本地 envytools 搜索见 `public_search.txt`，未找到所需具名枚举。

### 独立 DRAM-info 不能借用：可复现 jump-table 证据

三套函数都读另一对象的 `+0x29`，不是 `FB+0x898c`。函数选择见既有 `dram_density_decode.asm`；单位显示见既有 `dram_density_display.asm`。

| jump table VA | code | 表内LE64目标 | 真实返回证据 |
|---|---:|---:|---|
| 0x9342160 | 6 | 0x19594c8 | 0x19594da `b820000000`，eax=32 |
| 0x9342198 | 6 | 0x1959688 | 0x195969a 跳0x195965a，那里 `b808000000`，eax=8 |
| 0x9342198 | 7 | 0x1959718 | unknown分支，0x195972a `xor eax,eax` |
| 0x9342200 | 6 | 0x1959858 | 0x195986a `b80c000000`，eax=12 |
| 0x9342200 | 7 | 0x1959878 | 0x195988a `b810000000`，eax=16 |

`verification.json` 保存了表指针原始8字节和目标指令。未将这些数字用作 MEM TYPE density 值。

## 2. organization：能证明的仅限行为，不能命名具体总线宽度

`org_timing.asm`：

```text
0x672b577 and edx,3            # 缺省选择输入[1:0]
0x672b57a 80bc8f8d89000002     cmp byte [rdi+rcx*4+0x898d],2
0x672b582 jne 0x672b58c
0x672b584 shr eax,2
0x672b589 and edx,3            # org2改选输入[3:2]
0x672b58c mov [r13+0x1d],dl
```

另一路 `0x672bbd1` 依org2从输入[7:6]取值，否则取[5:4]，见既有 `meminfo_accessors.asm` 的 `0x672bdd0..bdd5`。这是表内备选 timing 位域的选择，不是“向宽度变量写16/32”。

`org_mode.asm` / 既有 `memorg_consumer_full.asm`：

- `0x6e5b449` 从另一个 group 的 `FB+0x898d+group*0x24` 读取org，存 `rsp+0xa7`。
- mixed-partition 路径中 `0x6e5b550: lea eax,[r9-2]`、`cmp eax,1`、`ja` 要求org为2或3；不合格日志明确 `unsupported Mem Org %d`。
- `0x6e5ceae` 先检查 `rsp+0x28>1`，此时才执行下面逻辑：
  - 读 `[r12+0x120]`；构造 `old|0x400000` 和 `old&~0x400000`；
  - `0x6e5cecf: 80bc24a700000002` 比较org2；`0x6e5ced7: cmove r14d,edx`；
  - 写 `[r12+0x2d8]`，变化时再经 HAL callback `FB+0x738` 和调用 `0x6808910` 进入后续路径。

所以可精确写作：**在该路径，org2使内部模式bit22=1，org3使其=0。** 没有从这里证明该模式字对应的具体寄存器/具名位，不能擅自叫 `X16`、`CLAMSHELL`，也未证明这段 HAL 在GB202的实际选用情况。即便日后能命名为某一代 x16，也仍需区分 package总DQ宽度、内部channel宽度和rank/板面数量。

### 4090 反例已直接核对，而非仅引用任务描述

输入与原研究归类：

- 24GB：`/home/user/Downloads/Asus.RTX4090.24576.221013_2.rom`
- 48GB：`/home/user/Downloads/278392.rom`

两文件绝对 `0xd603` 的record0都是：

```text
0a f0 60 02 00 00 c0 00 ff ff ff 00 ff ff 00 10 00 00 00 00 00 00
```

绝对 `0xd619` 的record1都是同一串，仅起始两字节为 `1a f1`。两份有效项全是density6/org2。型号/容量归类沿用既有4090研究，**没有运行固件验证48GB可用性**。该证据排除“这个字段的2/3变化是这两份4090容量差异的必要开关”；不能单凭它排除任何代际相关的 bus-organization 定义。

## Verification / 复现

```bash
cd /home/user/rt_5090_project/vbios_diff/gb202_memory_route_20260911/enum_followup
python verify_offline.py
# PASS: ELF instruction anchors, 29 ROM hashes/all MEM TYPE bytes, 2 Ada tables; no target execution
python ../mods_schema/static_refs.py dis 0x6e5ceae 0x6e5cf11
python ../mods_schema/static_refs.py refs 0x898c 0x898d
```

`verify_offline.py` 只读 ELF / ROM，以 Capstone 反汇编，导入既有纯数据 `compare_roms.Rom` 读取Ada表；不执行 MODS、驱动、固件，不打开设备，不联网。它验证输入 hashes、GB202 全部表记录字节及关键指令边界/锚点，并输出真实ROM绝对偏移。

新增文件全部在 `enum_followup/`；既有研究没有改写。`nearby_field_refs.txt`、`other_field_refs.txt` 是探索性字节扫描候选，不能当确定引用。

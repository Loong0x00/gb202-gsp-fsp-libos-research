# GB202 每-FBP L2 floorsweep mask 粒度交叉审计

审计日期：2026-07-21

## 结论

本轮能静态确认的最窄结论是：**GB202 的 raw OPT L2 floorsweep 控制在每个
FBP 上是一个 `[7:0]` 字段；离线编码器可以表达只改变某个 FBP 的其中一个
bit。** 这证明的是控制坐标和编码粒度，不是被该 bit 控制的物理容量、健康状态
或独立启用能力。

对后续选择性测试，判定应写成：

- **FACT-STATIC：** 最小可表达的 raw 目标是一个 `(FBP, raw_bit)`；实际写入描述
  是该 FBP 的整个 `[7:0]` raw 值，而不是硬件原子 bit-write。
- **CONDITIONAL：** 若未留档的 `8 x 0x12` 报告准确，且规则等容量模型成立，
  一个 raw bit 的容量记账是 **2 MiB**。所以 2 MiB 是最小的数字化**候选标签**。
- **FACT-STATIC LIMIT：** 当前允许材料没有 raw bit 以下的 selector。只有在
  “一个 bit 对应两个 NCU `l2s`、合计 2 MiB”的条件模型成立时，才能进一步说
  模型中的单个 1-MiB `l2s` 不能由这条路径单独选择。
- **FACT-STATIC LIMIT：** 当前材料也没有证明一个 raw bit 会被硬件独立接受，
  或不会受 L2/PAC、路由、LTC 对称性、拓扑校验及 reset/re-enumeration 约束。
  因而可保证的物理/可工作最小单位仍未确定，**可能大于 2 MiB**。
- **FACT-STATIC LIMIT：** 静态可稳定命名的是寄存器坐标
  `FBPn.raw_bitb`。当前材料不能把它稳定映射到一个绝对
  `LTC/local-LTS`、两个绝对 NCU `l2s`，或一个绝对 PerfWorks LTS rollup ID。

换言之，若必须在“1 MiB、2 MiB、larger”中作计划选择：**控制面选择一个 raw
bit；用“理论 +2 MiB”作条件性记账；不要把它称为已证明的 2-MiB 物理单元。
即使接受该模型，硬件实际最小可工作粒度也只能写成 `2 MiB or larger`；不接受
该模型时，现有静态证据根本不能给它赋一个 MiB 数值。**

## 证据等级与边界

本文只使用以下三类标签：

- **FACT-STATIC**：由当前 OpenRM、当前 GSP、本地 MODS 570.151 或已解码 MODS
  文本直接、有限范围复核；
- **FACT-ARCHIVE**：由项目中保存的 NCU/PerfWorks 原始输出直接复核，只代表
  2026-07-13 的归档运行；
- **REPORT-ONLY / CONDITIONAL**：前者是项目曾报告但未保留 stdout/raw dump 的
  本卡读数；后者显式依赖这些报告或额外的等容量/排列假设。

本轮没有访问 GPU、BAR0/MMIO、PCI config 或设备节点；没有执行 MODS、GPU
workload、内部 RM control、reset 或网络请求；没有修改任何硬件或软件状态。
MODS 仅从 `0x8fd61aa` 直接 seek/read 一个 16-byte 表头和 `0x741c` bytes 压缩流，
解压为 `0x88b64` bytes；GSP 只做已有构造重放与 `0x132ef40..0x132f010`
的小窗口反汇编，没有 whole-segment scan。

## 1. 每 FBP 8-bit 是静态事实

### 1.1 MODS RegHal 的独立、低资源解码

**FACT-STATIC（仅限本地 MODS 570.151 样本）：**

- `mods_audit/static/extracted_inner/mods` 为 392,339,552 bytes，SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- GB202 `chip_id=0xff2` 的表头位于 file offset `0x8fd61aa`；表头给出
  `compressed=0x741c`、`uncompressed=0x88b64`、`rows=19999`；
- `gb202_reghal_offline.py:204-245` 所述九平面累积差分解码后，raw read ID
  `0x1087c000` 的普通 lookup rows 为：

```text
row 4251 index 0 -> BAR0 0x8234e0
row 4253 index 1 -> BAR0 0x8234e4
...
row 4265 index 7 -> BAR0 0x8234fc
```

- raw field-setter ID `0x2087c000` 的 row 4282 为 `words[3]=0x00070000`；按
  `gb202_reghal_offline.py:90-95` 的格式直接解码为字段 **`[7:0]`**。

因此静态事实是八个 FBP 实例、每实例一个 8-bit raw OPT 字段：

```text
raw(FBP n) = BAR0 0x8234e0 + 4*n,  n = 0..7
```

表项只证明地址、实例数和字段宽度，不证明寄存器当前值或写入会被接受。
`parallel/evidence_audit.md:65-83` 给出了同一表的 provenance 与证据边界；
`gb202_reghal_offline.py:303-330` 也把八地址数组和 `[7:0]` setter 作为离线断言。

**FACT-STATIC（避免误读）：** effective read ID `0x10d64000` 在 RegHal 表中有
16 个潜在 FBP address index（`0x822900..0x82293c`），其 setter 是 `[31:0]`。
这里的“16”是潜在 **FBP address slots**，不是“每 FBP 16 个 LTS”，也不能覆盖
raw setter 已直接证明的 `[7:0]` 宽度。

### 1.2 当前 GSP 只证明 effective mask 的动态裁宽，不证明位身份

**FACT-STATIC（当前 610.43.03 GSP）：** 已归档构造重放把 GB202 chip index 65
的 FB vtable `+0x9c0` 绑定到 `0x0132ef40`
（`parallel/gsp_fb_vtable_replay.results.txt:29-34,48-56`）。该 getter 的小窗口
控制流为：

```text
W = call(FB slot +0x758) * call(FB slot +0x730)
require W <= 31
disable = FuseRead32(4 * (0xa40 + fbp))   # internal 0x2900 + 4*fbp
return (~disable) & ((1U << W) - 1)
```

对应指令是 `0x132ef98..0x132efb8` 的两次 getter/multiply/width check、
`0x132efbe..0x132efdc` 的 effective register read，以及
`0x132efe2..0x132efec` 的裁宽反掩码。RegHal domain-5 基址使内部
`0x2900 + 4*FBP` 对应 `BAR0 0x822900 + 4*FBP`。

这证明 GSP 把两个 getter 返回值的乘积当作 flattened enable mask 的有效位宽，
这条函数本身不使用固定的 96-MiB SKU 常量。当前保留材料没有把
`+0x730/+0x758` 的 GB202 返回值和方法名独立绑定，也没有给出 raw
`0x8234e0` 如何展开/传播到 effective `0x822900` 的逐 bit 公式。因此不能从
这段代码单独推出 `bit -> LTC -> local slice` 排列。

## 2. “2 LTC / 16 LTS”必须拆成三个命名层

裸写“每 FBP 2 LTC / 16 LTS”会混合不同计数域。严格拆分如下：

| 层 | 本轮可保留的说法 | 等级 |
|---|---|---|
| raw OPT 控制 | 每 FBP 8 个 bit-position | **FACT-STATIC** |
| MODS 人类可读拓扑标签 | 既有 bounded static 分析在 `OPT_L2SLICE_FBP0_DISABLE` 项下枚举 8 个 `f0fbpltc{0,1}slice{0..3}` 标签，即 2 个 LTC 名 × 每 LTC 4 个 RM/MODS slice 名 | **FACT-STATIC**，但标签项本身没有显式 numeric bit coordinate |
| 本卡 active LTC 总数 | 16 total；若八 FBP 均匀则 2/FBP | **REPORT-ONLY + CONDITIONAL**；`gb202_fs_probe` stdout 未保存，16 个 DRAM rollup 不能替代 16 LTC |
| NCU `l2s` | 归档当前为 96 total、12/FBP | **FACT-ARCHIVE** |
| “full 16 NCU `l2s`/FBP” | 8 raw positions × 2 NCU `l2s`/position | **CONDITIONAL**，不是归档当前值 |
| PerfWorks LTS rollup | 归档当前为 48 个匿名 rollup | **FACT-ARCHIVE**；没有每实例 index 或与上述层的 identity edge |

MODS 标签集合的静态出处是 `L2_REENABLE_STATIC_FINDINGS.md:2143-2149`。它支持的
最大拓扑形状是：

```text
per FBP: 2 LTC labels * 4 RM/MODS slice labels = 8 labels
```

它**不是** 16 个 RM mask-LTS。只有再采用“每个 8-way mask position 数值上对应
两个 NCU `l2s`”这个条件模型，才得到：

```text
per FBP: 8 RM mask positions * 2 NCU l2s/position = 16 NCU l2s (full model)
```

所以后文如需写“16 LTS”，必须明确它是 **16 个满配模型中的 NCU `l2s`**；
OpenRM flattened `ltsEnMask`、MODS tag-map 的 8 个 slice 标签和 NCU 的 16 个
满配 `l2s` 不能用同一个裸词 `LTS` 代替。

OpenRM 头文件与这个区分一致但不补齐数值：

- `ctrl2080fb.h:1240-1269` 定义每 physical FBP 的 active
  `ltcMask/ltcCount/ltsMask/ltsCount`；接口存在不等于本卡返回值已留档；
- `ctrl2080fb.h:2021-2033` 只说 `ltsEnMask` 是 physical/local，且把一个 FBP
  内所有 LTC 的 LTS bits flatten；没有规定 flatten 顺序；
- `ctrl0080gr.h:139-151` 分别定义 `NUM_LTC_PER_FBP` 和
  `NUM_SLICES_PER_LTC` 查询 index，但公开头文件没有 GB202 的返回常量。

## 3. 归档当前状态与 `0x12` 的条件记账

### 3.1 不依赖 `0x12` 的保存事实

**FACT-ARCHIVE：**

- `l2_slice_re/raw/20260713T092611+0800.LGScei/lts_rollup.raw.csv` 的数据行给出
  `device__attribute_fbp_count=8`、`device__attribute_l2_cache_size=100663296`、
  `device__attribute_l2s_count=96`、`device__attribute_num_l2s_per_fbp=12`；
- 同目录 `topology.summary.tsv:2-4` 的三次同-launch 采样均为 8 FBPA、16 DRAM、
  48 LTS rollup instances；
- 64 个归档 `.ncu-rep` 的一致性及 48-rollup 边界见
  `L2_SLICE_MAP_FINDINGS.md:37-85`。

直接可算的只是以下数值比率：

```text
96 MiB / 8 FBP       = 12 MiB per reported FBP count
96 MiB / 96 NCU l2s = 1 MiB per reported NCU-l2s count
96 MiB / 48 rollups  = 2 MiB per observed rollup count
```

这些商不能自动解释成每实例物理容量。尤其最后一行不证明一个 rollup、一个
raw bit 和两个 NCU `l2s` 是同一个已索引物理对象；公共 rollup 输出对隐藏
instance label 的排列不敏感
（`L2_SLICE_MAP_FINDINGS.md:47-61,63-85`）。

### 3.2 仍然只是报告的数值

以下三项保持 **REPORT-ONLY**：

- 本卡 active LTC total 为 16；
- 八个 FBP 的 raw/effective low-8 disable 均为 `0x12`；
- 八个 software disable 均为 0。

项目没有保留 topology probe 或寄存器读取 stdout/raw dump；证据降级依据见
`parallel/evidence_audit.md:155-176`。本文不把后续算术反向当成这些读数的独立
验证。

### 3.3 接受报告后的精确算术

**CONDITIONAL（假设每 FBP disable=`0x12`）：**

```text
disable = 0x12 = bit 1 | bit 4
enable  = (~0x12) & 0xff = 0xed
popcount(disable) = 2
popcount(enable)  = 6
```

因此八个 FBP 上共有 48 个 enabled raw position 和 16 个 disabled raw
position。再加入规则、等容量的 2-MiB/position 模型：

| 范围 | enabled | disabled | capacity accounting |
|---|---:|---:|---:|
| 每 FBP | 6 raw positions / 12 NCU `l2s` | 2 raw positions / 4 NCU `l2s` | 12 MiB current + 4 MiB disabled |
| 8 FBP 总计 | 48 raw positions / 96 NCU `l2s` | 16 raw positions / 32 NCU `l2s` | 96 MiB current + 32 MiB disabled |
| 满配模型 | 64 raw positions / 128 NCU `l2s` | 0 | 128 MiB |

这个模型同时满足归档的 12 active NCU `l2s`/FBP 和 96 MiB，但它证明的只是
**平均/规则记账**：

```text
12 active NCU l2s / 6 enabled raw positions = 2 NCU l2s/position
12 MiB / 6 enabled raw positions             = 2 MiB/position
```

当前证据没有逐 bit 容量读数来排除不等分解释，也没有证明两个 NCU `l2s` 是由
该 bit 原子、共同控制的已定位物理 pair。

对未来计划可使用的条件记账是：

- 清一个特定 `(FBP, bit)`：理论 `+2 MiB`，例如总量 `96 -> 98 MiB`；
- 清同一 bit column 的全部 8 FBP：理论 `+16 MiB`；
- 清 bit 1 和 bit 4 的全部 16 个报告位置：理论 `+32 MiB`，即
  `96 -> 128 MiB`。

这些不是写入接受、拓扑传播或 disabled-unit health 证明。

## 4. bit 1 / bit 4 不能静态升级为绝对 LTS 身份

**FACT-STATIC：** raw 字段可把目标稳定写成 `(FBP n, bit 1)` 或
`(FBP n, bit 4)`；OpenRM 只承诺一个 FBP 内的 LTS bits 被 flatten。当前头文件
没有 flatten 公式，保留的 MODS tag-map 结论也明确说 tag record 没有
chain/offset/bit 数值坐标。

因此下面两种仅作示例的具体映射都只能是 **CONDITIONAL**：

```text
若 b = 4*local_ltc + local_slice（LTC-major）:
    bit 1 -> local LTC 0, slice 1
    bit 4 -> local LTC 1, slice 0

若 b = 2*local_slice + local_ltc（slice-major）:
    bit 1 -> local LTC 1, slice 0
    bit 4 -> local LTC 0, slice 2
```

两种排列（以及其他置换）都与“2 LTC × 4 RM slice = 8 flattened positions”
相容；当前允许材料没有裁决哪一个是 GB202 raw/effective 的实际顺序。因此本文不采用
`bit1=LTC0.slice1` 或 `bit4=LTC1.slice0` 作为事实。

即使将来拿到 flatten 公式，还缺两条身份边：

1. 一个 RM/MODS mask position 到两个 NCU `l2s` 的绝对编号；
2. 该 position 到某个 PerfWorks LTS rollup hidden instance 的绝对编号。

MODS 已解码脚本确实按 `(fbp, slice)` 调用
`CreateL2CacheExperiment`，并用 `IsL2SliceValid(slice, fbp)` 过滤
（`mods_audit/static/decoded/all/gputest.js:12860-12907`）；这证明 MODS 内部存在
per-FBP slice index，不给出该 index 与 raw bit、NCU `l2s` 或 PerfWorks hidden
label 的等式。通用 repair 参数另用
`<PhysicalGlobalLtcIdx>:<PhysicalLocalL2SliceIdx>`
（`mods_audit/static/decoded/all/repair_guts.js:57-58`），同样不能证明 GB202 repair
坐标就是 floorsweep bit 或 rollup identity。

**FACT-ARCHIVE：** 当前 placement 工具只能在同一 live allocation 内构造 48 个
相对 rollup class；class ID 绑定 allocation base，不是 portable physical ID
（`L2_SLICE_MAP_FINDINGS.md:414-431`）。所以未来即使观察到 class 数或容量变化，
也不能把新增/变化 class 静态归因给目标 raw bit。

## 5. 对未来选择性测试的最终粒度合同

1. **FACT-STATIC：** 唯一可精确选择的目标名是一个 raw register coordinate：
   `BAR0 0x8234e0 + 4*FBP` 的一个 bit；离线 sparse encoder 可只改变一个 FBP
   的一个 bit（`L2_REENABLE_STATIC_FINDINGS.md:1904-1924`）。
2. **FACT-STATIC：** raw setter 的字段是 `[7:0]`；没有同一路径的半-bit/
   NCU-`l2s` selector。
3. **CONDITIONAL：** 给一个 bit 加“理论 +2 MiB”标签；该值来自报告与规则
   accounting model，而不是物理 identity 证明。在这个模型内，单个 1-MiB
   NCU `l2s` 不是可单独表达的 raw floorsweep 选择单位。
4. **FACT-STATIC LIMIT：** 不宣称一个 bit 是独立启用/独立测试单位；可能必须
   同时改变多个 bit、LTC/PAC 或 FBP，或硬件可能完全拒绝 disabled unit。
5. **FACT-STATIC LIMIT：** 不宣称可把 workload pin 到该 bit。现有 48-class
   placement 只能做 allocation-scoped 相对观测，不能形成逐物理 LTS 健康证书。

所以静态审计给出的最小未来实验计划单位是：

```text
one (FBP, raw_bit) delta
capacity label: conditional +2 MiB
physical identity: unresolved
hardware-accepted/testable minimum: unresolved, possibly larger
```

这份粒度结论不改变主项目的安全门：在权限、raw→effective 传播、reset/recovery、
PAC/route coupling 和 disabled-unit health 被独立证明之前，不能把该候选转换成实卡
操作。

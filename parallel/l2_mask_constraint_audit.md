# GB202 L2 floorsweep mask host-side 形状约束审计

日期：2026-07-22
状态：完成；strict static-only

## 结论

最窄结论是：**MODS 570.151 的 direct-shadow `NewFuse.SetSwFuses` 编码链可以
表达只改变一个 FBP 的一个 raw bit，也可以表达奇数个、非对称分布的 raw-bit
delta；在这条已见 host 链中，没有发现 LTC 配对、L2/PAC 同步、跨 FBP 对称、
偶数 popcount 或特定 bit-pattern 的拒绝/补齐逻辑。**

这里的“单 bit”是新旧两个 8-bit FBP raw 值之间只差一位。实际 plan node 仍写
该 FBP 的完整 `[7:0]` 值，不是寄存器级原子 bit clear。编码器会按 descriptor
宽度裁掉高位，并在 `type="dis"` 时执行 logical-to-raw 取反；这是 per-field
归一化，不是拓扑配对规则。

因此，若同时接受尚未归档的 `8 x 0x12` 报告与规则的 2-MiB/raw-position
accounting model，则 host 数据结构至少能表示：

| 条件容量 | raw-bit delta 数 | host 表达 |
|---:|---:|---|
| `96 -> 98 MiB` | 1 | 一个 FBP 的完整 byte 值只清一个报告 bit |
| `96 -> 100 MiB` | 2 | 同一 FBP 清两个 bit，或两个 FBP 各清一个 bit |
| `96 -> 110 MiB` | 7 | 将七个 bit delta 稀疏分布到所需 FBP byte 节点；无已见偶数/对称补齐 |

这只是**计划表示能力**。本地 stock 名称入口仍缺 authentic `gb202_f.json`；writer
另有 `SecurityUnlockLevel > 3`、设备 PLM、latch、readback、reset/reinitialize 等
独立门。更重要的是，FSP/GFW、硬件 sense/rollup、L2/PAC route 与被屏蔽单元健康
是否接受这些形状仍是 **UNKNOWN**。本报告不能把“可编码”升级为“会生效、可启动
或可稳定工作”。

## 范围与方法

本轮优先复核：

- 已有 bounded-static 报告中的 `SetSwFuses` wrapper、SplitMacro encoder、plan
  writer 与 raw write-filter 数据流；
- `mods_audit/static/decoded/gpuargs.js`、`decoded/all/gputest.js`、
  `decoded/all/prntutil.js` 的相关小范围文本；
- NVIDIA 610.43.03 公开 FB control、RPC serializer 和现有只读 topology
  getter 结论。

现有材料已经足以回答 host 表达问题，故没有新增反汇编或扩大扫描。没有运行
MODS 或项目硬件程序，没有访问 GPU、设备节点、BAR/MMIO、PCI config、firmware，
也没有 reset、rebind、模块或网络操作。

证据标签：

- **FACT**：当前固定 artifact、已解码 JS 或 NVIDIA 610 公开源码直接支持；
- **INFERENCE**：由多条 FACT 得到的最窄解释；
- **UNKNOWN**：私有实现、firmware 或硬件才能决定。

## 1. Direct-shadow 输入是稀疏的，不会自动补齐八个 FBP

### 1.1 FACT：JS wrapper 只转交调用者给出的 pair

既有 bounded audit 已闭合 `NewFuse.SetSwFuses` wrapper `0x1446860`：

- 只接受一个 `fuseNameValPairs` array；
- 每项必须是 `[name, 32-bit integer]`；
- 只遍历实际提供的元素，规范化名称后插入输入树；
- 重复名称报错；
- 不枚举未提供的 L2 名称，不读取目标容量，也不补齐
  `OPT_L2SLICE_FBP0_DISABLE ... FBP7`。

证据汇总见 `L2_REENABLE_STATIC_FINDINGS.md:2373-2378`。这些是输入结构检查，
不是 LTC/PAC、popcount 或跨 FBP 形状检查。

### 1.2 FACT：SplitMacro 每个名称只生成其自己的 raw node

`SplitMacro_EncodeSetSw 0x148b4c0` 只遍历调用者输入树。对每个名称，它：

1. 查找一个 descriptor；
2. 读取该 descriptor 的 `bits/type` 与唯一 domain-relative offset `+0x8c`；
3. 计算一个 raw value；
4. 以该 offset 插入或更新一个 plan node。

函数不遍历全部 descriptor，也不按八个 FBP 复制。外层 `0x147b4b0` 的循环是
macro accessor/die 循环；单 die GB202 不会因此扩展成八个 FBP。已有例证是只给
FBP0 的 logical `0xef` 时，只生成 raw `0x10`、key `0x34e0` 的一个 node，不会
暗中生成 FBP1..7。见 `L2_REENABLE_STATIC_FINDINGS.md:2362-2371`。

这直接排除了 direct-shadow host encoder 中的 mandatory cross-FBP symmetry
或“同一 bit column 必须八卡位齐写”规则。

## 2. 已见的 per-field 约束，不是 topology-shape 约束

### 2.1 FACT：宽度/type 归一化

对 `type == "dis"`，encoder 使用：

```text
raw = ~logical & ((1 << width) - 1)
```

若 authentic L2 descriptor 为已恢复的 `width=8, type="dis"`，结果只保留低
8 bit。由此 raw `0x12 -> 0x10/0x02/0x00` 都能被表示；超出字段宽度的 logical
高位会被裁掉。见 `L2_REENABLE_STATIC_FINDINGS.md:765-774`。

这是唯一已见、与 mask 位形直接相关的普通归一化。它不检查 enabled/disabled
popcount，不要求 LTC 内成对，也不比较其他 FBP。

### 2.2 FACT：direct SetSw 路径不调用实体熔丝 transition validator

`ValidateFuseTransition 0x148e890` 会约束另外两条 fuseless/physical-fuse 编码
路径，但 direct shadow 使用的 `0x148b4c0` 不调用它。故 disable bit 从 1 降为 0
不会仅因 transition direction 被 host encoder 拒绝。见
`L2_REENABLE_STATIC_FINDINGS.md:840-854`。

### 2.3 FACT：plan writer 按 node 独立迭代

`ProgramSwFusePlan 0x1515ea0` 在 host security gate 通过后，逐 node 传递：

```text
(domain=5, relative offset, full raw value)
```

每项独立 write、立即 readback、比较后前进。已见控制流没有先收集 L2 nodes 做
全局 popcount、FBP column equality、LTC/PAC join 或 allowed-pattern lookup。
普通 readback mismatch 是写后错误，不是写前 shape validator；权限哨兵
`0xbadf510c` 甚至只记日志。见 `L2_REENABLE_STATIC_FINDINGS.md:642-651` 与
`parallel/deviceinfo_cache_writer_timing.md:174-195`。

普通 register write-filter `0xd9aac0` 也只是按最终地址查可配置的
`(range,writableBitMask)` 表；固定函数没有 L2 地址特判，stock/default JS 表为空。
它可能由外部 `-reg_write_mask` 限制任意位，但不是 L2 topology shape policy。
见 `parallel/raw_filter_targets.md:18-44,88-158`。

## 3. 其他 floorsweep/repair 路径确有约束，但不能套到 direct shadow

### 3.1 普通 software-floorsweep 路径会保护 current hard-disabled bits

`fbp_l2slice_enable/disable` 操作的是 software-disable 数组
`0x822080 + 4*FBP`，不是 raw OPT shadow。GB20x 的已见参数调整实现会读取
current/effective mask；若请求试图清除当前 disabled bit，就把该 bit OR 回请求
software mask。因而这条路径会归一化请求并阻止用 software mask 越过 hard mask。
见 `L2_REENABLE_STATIC_FINDINGS.md:372-399`。

这是另一条写入层，不能反推 direct `SetSwFuses` encoder 会把 raw `0x10`
恢复成 `0x12`。

### 3.2 解码 JS 暴露可选 dependent-FS 调整与不透明 FsLib gate

`mods_audit/static/decoded/gpuargs.js:1239-1243` 暴露：

- `adjust_fs_args`：自动补 dependent floorsweeping arguments；
- `adjust_fs_l2_noc`：按 command-line FS args 自动 disable paired L2-NOC FBPs；
- `fix_fs_init_masks`：ATE floorsweeping 后使 masks consistent。

这些状态在 `gpuargs.js:196-207` 默认为未提供，`13298-13350` 只在设置时转交
Subdev 属性。`ArgFloorsweepArgs` 本身在 `2660-2687` 只以 `:` 拼接文本，不解析
mask 或检查 popcount/配对/对称性。因此 JS 层没有证明 mandatory normalization；
但这些旋钮明确说明普通 floorsweep 框架存在 dependent/pair consistency 概念。

`gpuargs.js:13352-13368` 还表明：若 `g_IncludeFslib` 为真，真实硬件默认选择
`FsLib.MODE_FUNC_VALID`。解码 JS 不含 FsLib 实现，也未闭合该组件在目标调用中的
包含状态。因此 private FsLib 是否对 GB202 请求施加额外 valid-shape 规则属于
**UNKNOWN**。当前 direct-shadow 调用链没有已见 FsLib 调用，不能仅凭普通
`-floorsweep` 参数框架把这个未知门移植到 `SetSwFuses`。

### 3.3 LTS repair 的 L2/PAC 配对规则属于容量中性的 swap planner

通用 MODS repair planner 明确：software-disabled L2 spare 数必须与 PAC spare 数
相等；目标 L2/PAC 若已在 hard mask 中会被拒绝；规划器同时生成 L2/PAC 映射，
且同一 LTC 一次最多替换一个 slice。见
`L2_REENABLE_STATIC_FINDINGS.md:487-506`。

该规则服务 InfoROM-managed spare swap，不服务 direct raw OPT plan：它使用不同
mask family/metadata，目标是容量不变的 repair；GB202 index 65 的 repair/marking/
commit 槽又绑定 no-op stubs。它证明软件体系中确有 PAC pairing 概念，却不是
“任意 raw L2 bit 在 SetSwFuses 编码时必须带 PAC node”的证据。

## 4. OpenRM 610 公开面没有 input mask 可做 shape validation

### 4.1 FACT：公开 LTS/PAC controls 是彼此独立的 GET query

`ctrl2080fb.h:2021-2033` 的 LTS query 以 `fbpIndex` 为输入，返回 flattened
`ltsEnMask`；`:2238-2249` 的 PAC query 同样以 `fbpIndex` 为输入、返回
`pacEnMask`。`:2284-2359` 将它们列为独立的 GET-FS-INFO query type，没有 client
输入的 LTS/PAC mask，也没有 set/write contract。

公开 host RPC serializer
`src/nvidia/inc/kernel/vgpu/rm_plugin_shared_code.h:5618-5800` 只检查 query count、
复制各 query 的 `fbpIndex`/返回 mask，并拒绝未知 query type；LTS 与 PAC 分开
处理，没有 pairing、symmetry、popcount 或 input valid-mask normalization。
`src/nvidia/src/kernel/vgpu/rpc.c:4949-4979` 只是 serialize、RPC、deserialize。

因此这些公开接口既没有 host-side write shape gate，也不能证明硬件会接受某种
raw shape。

### 4.2 FACT：可见 valid-width/popcount 用于输出/观察

当前 GB202 GSP 的 non-MIG LTS getter按一个动态宽度 `W` 对 effective disable
word 取反并裁宽：

```text
enable = (~disable) & ((1U << W) - 1)
```

它还要求 `W <= 31`，但没有跨 FBP 比较。见
`parallel/l2_mask_granularity.md:87-110`。这是对返回的 effective mask 去除无效
高位，不是对 raw plan 的 admission check。

解码 `prntutil.js:3178-3196` 对 L2 slice mask 的 `CountBits` 只用于打印总数；
`gputest.js:12892-12939` 的 `IsL2SliceValid(slice,fbp)` 只过滤当前 topology 上的
perf experiment。二者都没有把用户 raw mask 拒绝或归一化。

## 5. 约束矩阵

| 候选约束 | direct-shadow host 链 | 其他可见路径 | 最终判定 |
|---|---|---|---|
| 单 FBP 单 raw-bit delta | sparse pair -> one FBP byte node | 普通 software FS 可能保护 current mask | **可表达；硬件接受 UNKNOWN** |
| LTC 内配对 | 未见检查 | repair planner 有 swap/pair 规则 | **不构成 direct encoder gate** |
| PAC/route 同步 | plan 无 PAC node 或 join | repair 需 PAC spare；普通 FS 有可选 L2-NOC paired-FBP adjust | **direct 路径未见；下层 UNKNOWN** |
| 跨 FBP 对称 | encoder不枚举/复制其他 FBP | 可选 dependent-FS adjust 存在 | **direct 路径未见 mandatory symmetry** |
| popcount/偶数性 | 未见全局 count/reject | repair 统计 spare；打印代码 CountBits | **direct 路径未见 gate** |
| valid-bit mask | descriptor width 只保留低 8 bit | effective getter按 `W` 裁输出 | **per-field/output 裁宽，不是 acceptance proof** |
| hard-mask/current-mask 合并 | direct raw plan 未见预 OR | software FS adjust 会 OR current mask | **只约束 software FS 路径** |
| functional-valid policy | 已见 direct chain 无 FsLib | 条件 FsLib mode 存在、实现不透明 | **private/lower-layer UNKNOWN** |

## 6. 最终回答与边界

### FACT

1. `SetSwFuses` 的 JS/encoder/plan 数据结构可以稀疏表示一个 FBP byte；该 byte
   相对可信旧值可以只差一个 raw bit。
2. direct encoder 不自动补齐八个 FBP，不要求偶数 delta，也不调用 physical-fuse
   transition validator。
3. 已见 direct writer逐 node 执行，没有 L2/PAC join、跨 FBP equality 或全局
   popcount check。
4. OpenRM 610 的公开 LTS/PAC 面是只读 query，不是 raw mask setter。

### INFERENCE

在 authentic descriptor 可用、输入基线准确并仅讨论 host plan representation
时，理论 `98/100/110 MiB` 对应的 1/2/7 个 raw-position delta 都能被 stock
`SetSwFuses` encoder/plan 形状表达。110 MiB 所需的奇数 delta 不会被已见 host
代码自动补成对称/偶数集合。

### UNKNOWN

- authentic `gb202_f.json` 是否还有当前未观察的产品数据约束；本地包没有该文件；
- private FsLib、未公开 MODS C++ caller 或外部 policy 是否在别的入口施加 shape
  validation；
- FSP/GFW、hardware sense/rollup、L2-NOC/PAC routing、memory interleave 或 SKU
  policy 是否拒绝、扩大、缩小或重新归一化该 delta；
- raw shadow 能否传播到 effective mask，以及 98/100/110 MiB 是否能被实际枚举；
- disabled 单元的物理健康和可稳定工作的最小组合。

因此最终结论只能写成：**96 -> 98/100/110 MiB 的候选 raw masks 至少具有 stock
host plan-level representability；没有证据证明零售 GB202 会接受其中任何一个。**

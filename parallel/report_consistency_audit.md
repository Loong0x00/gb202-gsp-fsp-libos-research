# GB202 Markdown 报告一致性审校（纯文本、只读源报告）

日期：2026-07-22（Asia/Singapore）

## 范围与方法

本次只读取 `/home/user/rt_5090_project` 下的 Markdown 文本；没有读取或分析任何
ROM/NVFW/updater/MODS 二进制，没有访问 GPU、设备节点、PCI/BAR/MMIO、debugfs
或网络，也没有修改既有报告。唯一写入是本审校清单。

检查范围与规则：

- 枚举项目内 165 份 Markdown（其中 `parallel/` 下 106 份）；
- 搜索 `index 34`、`raw0=0x22`、`u32 index`、`index|length|SHA-384` 等旧命名；
- 对所有同时提到 `raw0=0x22` 的 9 份报告逐项检查上下文，区分真正的 Falcon
  table entry 34 与 hash-table entry 的 `raw0`；
- 交叉核对主报告、工作索引、`nvfw_auth_layout.md`、
  `bcrt_manifest_coverage.md` 和 `falcon_manifest_table.md` 的地址基准、长度、
  coverage 方向以及 FACT/INFERENCE/UNKNOWN 边界；
- 从全部 Markdown 提取 99 个唯一 `parallel/*.md` 引用并检查目标文件存在性。

## 总结

- **没有发现**仍把 target hash-table entry 的 `raw0=0x22` 正向解释成 Falcon
  index 34 的残留。现有命中要么是在明确撤回旧命名，要么是在说另一张 Falcon
  object table 中真实存在的 entry index 34。
- 主报告 `L2_REENABLE_STATIC_FINDINGS.md` 与索引 `GB202_PARALLEL_WORK.md` 对新链条
  的表述一致：

  ```text
  FSP_RUN descriptor + immediate region
      -> target entry SHA-384
  complete 0x88-byte two-entry table
      -> nested-image base+0x209 parent SHA-384
  signature serialization / device-pinned root
      -> UNKNOWN
  ```

- 99 个唯一 `parallel/*.md` 引用全部存在，缺失数为 0。
- 发现 4 项措辞/术语问题；它们不推翻已闭合的 SHA-384 字节关系，但可能让读者
  误以为 envelope 边界仍只是 padding 推断，或把 entry 起点错开 4 bytes。

## 问题清单

### 1. `fsp_run_object_diff.md` 同时把 envelope 边界写成 FACT 和 UNKNOWN

严重度：**中**。

- `parallel/fsp_run_object_diff.md:31-36` 的后续校正已经正确写明：hash entry
  精确覆盖 `0x50+word1`，所以 region/envelope 的**字节边界不再只是强推断**。
- 但同文 `:144-159` 仍以“推断对象边界”“推断 region”描述相同范围，
  `:181-186` 又将“边界是强结构推断”列为 UNKNOWN。

这与新证据的严格区分不一致。现在应当是：

- covered range / envelope end：**FACT**（由 stored/recomputed SHA-384 entry
  和 exact length 直接确认）；
- `word1` 的正式私有字段名是否为 `StoredSize`、以及内部两段语义：
  **INFERENCE/UNKNOWN**。

建议把章节标题和表头改为“hash-confirmed object/envelope boundary”，并把 UNKNOWN
限定到 v6 private schema/field semantics，而不是边界本身。

### 2. `fsp_v6_payload_compare.md` 的最终结论仍停留在旧证据等级

严重度：**中**。

- `parallel/fsp_v6_payload_compare.md:14-20` 已正确加入后续校正，明确
  “envelope 边界现已由 hash entry 直接确认”。
- 但 `:63` 仍称“推断切片”，`:124`、`:150` 继续使用“推断 region”，最终
  `:155-156` 又总结为“该切片规则得到强的一致性支持”。

最后一句虽然紧接着强调“v6 private 字段语义没有公开证明”，技术上可以作窄义
解释，但读者很容易把“字段语义未知”误读成“covered byte range 仍未确认”。建议
明确拆成两句：**range/length relation 已由 hash table 证明；`word1` 正式名称和
完整 v6 语义仍未知。**

### 3. `vbios_fsp_inventory.md` 的“推断 region/end”标签已过时且容易歧义

严重度：**低**。

- `parallel/vbios_fsp_inventory.md:175-180` 已正确说 exact envelope boundary
  被 hash entry 确认。
- 同文 `:110-116`、`:182-190` 仍使用“推断 region”“推断 end”和“该规则是强支持
  的切片推断”。后一句实际想保留的是 `word1` 的 private-field 语义边界，但没有
  明确限定主语。

建议把范围标签统一成“hash-confirmed region/end”，并只把“`word1` 正式命名为
`StoredSize`/其完整 schema 语义”标为推断。这样会与主报告 `:331-354` 的表述完全
一致。

### 4. `nvfw_auth_layout.md` 的 `record start` 列比完整 entry 起点晚 4 bytes

严重度：**低，但属于精确地址术语问题**。

- 同文 `parallel/nvfw_auth_layout.md:94-103` 把完整 entry 定义为
  `u32 raw_type | u32 raw0 | u32 length | 48-byte digest`；target entry 起点是
  `B+0x4a6`，例如 FE 为 `0x11b2a6`。
- `:108-113` 的表头写 `record start`，但值是 FE `0x11b2aa`、Dell
  `0x1280aa`、HPE `0x12ccaa`，即 `raw0` 字段/56-byte 后缀切片起点，而不是完整
  60-byte entry 起点。
- `parallel/bcrt_manifest_coverage.md:49-58` 则把完整 target entry 起点正确列为
  `...2a6`。两份报告的 bytes 没冲突，冲突只在“record”一词指代不同。

建议二选一：把列名改成 `raw0/56-byte slice start`；或者若想表达完整 entry，
则把四个地址各减 `0x4`。不要继续让 `record start` 同时指 56-byte slice 和
60-byte entry。

## 已确认无问题的关键边界

- Falcon object table 的 **entry index 34** 独立指向 `FSP_RUN` descriptor；这是
  合法、应保留的 index 34 用法。
- target hash-table entry 的 **`raw0=0x22`** 是 covered-start 相对偏移；
  `0x22 == 34` 只是数值巧合，不是 object index。
- target nested image 的 table 为
  `[base+0x45a, base+0x4e2)`，长度 `0x88 = 0x10 + 2*0x3c`。
- target entry 覆盖 `[D, D+0x50+word1)`；四样本 stored/recomputed SHA-384
  一致。
- `file[base+0x209:base+0x239]` 精确等于
  `SHA-384(file[base+0x45a:base+0x4e2])`。
- “parent digest 如何进入邻近 96-byte signature-shaped material”及设备 pinned
  root 仍为 UNKNOWN；主报告和三份新认证报告都没有越界声称签名链已闭合。

## 链接检查结果

检查方式是从项目所有 Markdown 中提取每个
`parallel/[A-Za-z0-9_.-]+.md` 形式的引用，再相对项目根目录检查 regular file。
共 99 个唯一引用，全部存在；未发现 dangling `parallel/*.md` 引用。

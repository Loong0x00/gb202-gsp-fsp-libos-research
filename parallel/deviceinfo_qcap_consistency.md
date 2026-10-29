# DeviceInfo2 / QCAP 报告一致性审阅

日期：2026-07-21
范围：`L2_REENABLE_STATIC_FINDINGS.md`、`GB202_PARALLEL_WORK.md`、
`parallel/deviceinfo_*.md`、`parallel/qcap13_semantics.md`、
`parallel/task2_auth_provenance.md`；QCAP cache 生命周期的后续闭合材料为
`parallel/qcap_cache_lifetime.md`
性质：仅做 Markdown 表述交叉审阅；未运行 MODS、项目程序、测试或硬件操作

## 结论

发现并闭合两组需要修订的表述：

1. `parallel/deviceinfo_cache_writer_timing.md` 对 normal `SetSwFuses`
   post-program reset 后 DeviceInfo2 cache 生命周期仍标为 `UNKNOWN`，已被后续
   `parallel/deviceinfo_reset_stability.md`、主报告和工作契约中的同对象/无
   invalidator 证据取代。这是明确的**过时结论**，现已在该时序报告中修正为
   visible host path FACT。
2. `parallel/deviceinfo_class10_identity.md` 的结论摘要以及
   `L2_REENABLE_STATIC_FINDINGS.md` 的可行性表使用了“record 不存在/缺记录就走
   fixed fallback”式简写。该简写没有容纳后来闭合的第三种情况：class vector
   非空但 requested instance 缺失时，MODS 不 fallback，而是读取
   `vector.end()+0x18`。这是容易造成错误实现的**条件缺失/局部矛盾**；
   `parallel/deviceinfo_class10_identity.md` 现已改成三分支。主报告可行性表因不在
   本轮编辑范围内，仍保留为待同步项。

其余三项主结论当前一致：plan/descriptor 使用 domain-relative offset；本卡 live
class-`0x10`/instance-0 row 尚未捕获；QCAP high16 已命名为 `Version`，但 task 2
只测试 key presence。后续 `parallel/qcap_cache_lifetime.md` 还证明 normal
`SetSwFuses` post-program reset 保留同一个 FSP wrapper/QCAP tree；host entry 因而
跨该 reset 保留并可能陈旧，而 firmware 是否仍发布/接受该 capability 是另一项
UNKNOWN。

## 1. Relative offset：当前一致，无需纠错

各报告现已一致地区分三层数值：

| 层次 | 正确值/规则 | 说明 |
|---|---|---|
| descriptor / plan key | `0x34e0 + 4*FBP` | fuse domain 内的相对 offset |
| runtime address | `resolvedDomain5Base + relativeOffset` | wrapper 在每次访问时相加 |
| fixed-selector 展开结果 | `0x820000 + 0x34e0 + 4*FBP`，即 `0x8234e0 + 4*FBP` | 只代表 fixed-selector instance-0 分支 |

一致证据包括：

- `GB202_PARALLEL_WORK.md:22-27` 同时列出 physical/fixed-selector family 与
  descriptor/plan offset，并说明 domain-5 wrapper 另加动态解析的 base；
- `L2_REENABLE_STATIC_FINDINGS.md:653-659` 明确警告把 `0x8234e0...` 填入
  plan/JSON 会被 wrapper 再加一次 base；
- `parallel/deviceinfo_instance_nomatch.md:143-166` 对 read/write wrapper 的描述
  同样是先保留/remap relative offset，再加 resolver 返回的 base；
- `parallel/deviceinfo_reset_stability.md:386-389` 使用
  “domain-relative key `0x34e0 + 4*FBP`”的相同术语。

建议保持一句统一警示：**`0x8234e0 + 4*FBP` 不是 descriptor/plan offset，也不
是未读取 live row 时可无条件宣称的 runtime 地址。**

## 2. Fixed fallback：两处摘要需收紧条件

### 2.1 当前已闭合的三分支语义

`parallel/deviceinfo_instance_nomatch.md:5-18` 与 `:57-73` 给出的精确语义是：

| class `0x10` vector 状态 | resolver 行为 |
|---|---|
| 空 / unique-instance count 为 0 | 使用 RegHal selector；普通 accessor 的 instance 0 得到 `0x820000` |
| 非空，且 exact requested instance 存在 | 返回该 record 的 `devicePriBase` |
| 非空，但 exact requested instance 缺失 | **不 fallback、不报错**；读取 `vector.end()+0x18` 的越界 dword |

因此 “fallback” 的触发条件必须写成 **class vector 为空**，不能写成泛化的
“requested record 缺失”。

### 2.2 修订状态

1. `parallel/deviceinfo_class10_identity.md` 的修订前摘要曾写成：

   > `PTOP class-0x10 record.devicePriBase when present -> otherwise selector fallback`

   在后续 no-match 审计之前，这种二分摘要尚可理解；它会把“class 非空但
   instance N 缺失”误归入 fallback。该文件现已把摘要和 resolver 正文都改成
   empty-vector fallback、exact-instance match、nonempty no-match 三分支。

   已采用的替代表述为：

   > If the class vector is empty, use the fixed selector for the same instance.
   > If it is nonempty, MODS attempts an exact-instance record lookup; a match
   > returns `devicePriBase`, while a missing instance reaches the unsafe
   > `vector.end()+0x18` no-match path and does not fall back.

2. `L2_REENABLE_STATIC_FINDINGS.md:2669` 仍写成“缺记录用 `0x820000`
   fallback”。同一主报告在 `:656-674` 已给出正确的空 class / exact match /
   no-match 三分支，因此可行性表这一短句与正文不严密一致。

   后续同步时应把“缺记录”改成：

   > class vector 为空时用 instance-0 fixed fallback `0x820000`；class 非空时
   > 必须存在 exact instance 0，否则 MODS 进入越界 no-match 路径，离线安全模型
   > 应拒绝。

`GB202_PARALLEL_WORK.md:24-27` 的 “used when populated, otherwise fallback”
也宜统一写成 “when the class vector is empty”，不过该文件在 `:262-269` 已经使用
了准确的 “an empty class falls back” 并补充 malformed 分支，故这里只是前部
摘要的可读性修订，不是新的事实冲突。

## 3. Live row：结论一致，不能被固定 getter 替代

以下报告均明确说本卡的 class-`0x10` / raw-type-`0x22` instance-0 row 及其
`devicePriBase` 没有 live capture：

- `parallel/deviceinfo_class10_identity.md:242-246`；
- `parallel/deviceinfo_instance_nomatch.md:34-37`、`:193-199`；
- `parallel/deviceinfo_reset_stability.md:36-40`、`:417`、`:431`；
- `L2_REENABLE_STATIC_FINDINGS.md:33-42`、`:671-675`；
- `GB202_PARALLEL_WORK.md:273-280`。

这与 NVIDIA 610 的 GB202 primary-FUSE getter 固定返回 `0x820000` 并不矛盾：

- 固定 getter 和 MODS selector row 证明/支持的是架构常量与 fallback；
- “正常 live row 若存在也应为 `0x820000`”在
  `parallel/deviceinfo_reset_stability.md` 中被正确标为强 inference；
- 它们不能升级为“本卡已捕获 row”或“已实测 row value”。

建议继续统一使用：**live row 未读；正常 row 强预期为 `0x820000`；任何未来
离线输入仍须验证 class 形状、instance 0 存在性和 base 一致性。**

## 4. DeviceInfo2 cache / reset：旧 `UNKNOWN` 已修正

### 4.1 冲突位置

`parallel/deviceinfo_cache_writer_timing.md` 修订前的以下结论停留在较早证据阶段：

- 结论段把 normal writer reset 是否保留或重建 cache 二者都留为 `UNKNOWN`；
- T9/T10 把 post-program reset 的 cache effect/runtime state 标为 `UNKNOWN`；
- 刷新来源段只说 normal reset 自动 invalidation/object rebuild “尚未证明”；
- 最小可引用结论仍说是否重建 `GpuSubdevice` 未证明。

后续 `parallel/deviceinfo_reset_stability.md:24-27`、`:280-300` 已把同一
570.151 可见 host 路径闭合为 FACT：reset 前后保留同一个 `GpuSubdevice*`，不调
constructor/destructor，不调 `0xdd2520`，也不写 cache vectors/flag。相同更新已
进入：

- `L2_REENABLE_STATIC_FINDINGS.md:685-698`；
- `GB202_PARALLEL_WORK.md:282-289`。

所以在**当前已见 normal `SetSwFuses` post-program reset host 路径**上，正确结论
不再是“两者未知”，而是：built DeviceInfo2 snapshot 跨该 reset 保留；下一次
resolver 不会仅因 reset 自动重读 PTOP。

仍然未知、不能随之抹掉的边界是：

- 硬件 DeviceInfo2 寄存器在 reset 边沿内部如何 retain/reload；
- 隐藏/未见间接路径的绝对不存在；
- 本卡 live row 的内容；
- raw L2 shadow 是否被采纳到 effective topology。

### 4.2 FS invalidation 与 reset 必须分开写

成功 floorsweep Apply 主线显式调用 `0xdd2520`，其顺序是 task 2/host apply 后、
可选 post-FS reset 前；它清 vectors/flag，但不立即 rebuild。因而 post-FS reset
之后的下一次 query 会重建，原因是**reset 前已经执行 invalidator**，不是 reset
本身具有通用 cache-reset 语义。

`parallel/deviceinfo_cache_writer_timing.md` 现已把结论、三分支 resolver 描述、
T5/T9/T10 时间线、刷新来源和最小可引用结论统一到上述证据边界。

## 5. QCAP Version 与 QCAP cache：当前一致

本次范围内的报告对 32-bit QCAP record 的表述一致：

```text
low16  = NvdmType
high16 = Version
```

证据与消费语义在以下位置一致：

- `parallel/qcap13_semantics.md:77-114` 用 MODS 自己的
  `NvdmType : Version` 标题闭合字段名；
- `parallel/qcap13_semantics.md:170-218` 证明 task 2 只测试 key `0x13` presence，
  不比较 Version，也不把 Version 编入 packet；
- `parallel/task2_auth_provenance.md:214-224`、`:239-257` 使用同一字段名和消费
  结论；
- `L2_REENABLE_STATIC_FINDINGS.md:2110-2117` 与
  `GB202_PARALLEL_WORK.md:228-231` 已同步更新。

因此旧的 “high16 只是 auxiliary value、字段语义 UNKNOWN” 已不应继续引用；在
本次指定文件中只看到 `parallel/qcap13_semantics.md:30-32` 把它作为已被纠正的
历史说法，没有发现仍把 high16 当作未命名字段的现行结论。

仍为 UNKNOWN 的是 `Version` 的内部编码、major/minor 结构、协商规则和 FSP 内部
用途；“字段名已知”与“编码未知”不矛盾。任意 16-bit Version（包括 0）都能通过
当前 host-side task-2 gate，因为 caller 只消费 lookup Boolean。

QCAP cache 也应与 DeviceInfo2 cache 分开。较早报告把 reset/FSP restart 后何时
清 tree 整体留为 UNKNOWN；后续 `parallel/qcap_cache_lifetime.md` 已闭合 normal
`SetSwFuses` post-program reset 的 visible host path：

- QCAP 是 `GpuSubdevice+0x1ad8` 所指 host FSP wrapper 内的 RB tree；normal
  post-program reset 保留同一 `GpuSubdevice*` 与 wrapper，不调用 wrapper
  constructor/destructor，不清 tree，也不 refetch；
- 因此已有 `0x13`/Version entry 会跨 hot/boot/fuse/base post-program reset 作为
  host cache entry 保留；这是一项 FACT，不再是该限定路径上的 UNKNOWN；
- full `GpuSubdevice` destruction 会销毁 wrapper/tree；普通 reset 不会；
- 仅空 tree 会触发 lazy all-query，非空但缺 `0x13` 不 targeted refresh；later
  all-query 只做 unique insert，不覆盖已有 key 的 Version，也不删除新 response
  中缺失的旧 key；
- tree 没有 timestamp、firmware epoch、expiry 或 active-state revalidation，故
  firmware/reset transition 后 retained entry **可能陈旧**，presence 仍不能替代
  每次 command 的 FSP status；
- 仍为 UNKNOWN 的是 reset 是否实际改变 FSP 发布集、private transport 是否另有
  epoch check、未见动态/外部路径是否 clear，以及本卡 live QCAP state；
- DeviceInfo2 的 `0xdd2520` 结论不能迁移成 QCAP cache reset 结论。

## 建议的统一最小表述

> L2 direct-shadow descriptor/plan key 是 fuse-domain-relative
> `0x34e0 + 4*FBP`；wrapper 再加 domain-5 base。只有 class `0x10` vector 为空时
> 才走 instance-0 fixed selector `0x820000`，得到
> `0x8234e0 + 4*FBP`；class 非空时要求 exact instance 0，缺失会进入 MODS 的
> 越界 no-match 路径而不是 fallback。本卡 live row 未捕获；公开固定 getter只让
> 正常 row 等于 `0x820000` 成为很强 inference。成功 FS Apply 会在其 reset 前
> 显式 invalidate DeviceInfo2 cache，而 normal `SetSwFuses` post-program reset
> 在已见 570.151 host 路径上保留同一对象与 built snapshot。QCAP `0x13` record
> 的 high16 字段名是 `Version`，但 task 2 只检查 PRC key presence；Version 编码
> 仍未知。normal post-program reset 同样保留 `GpuSubdevice+0x1ad8` 的同一 FSP
> wrapper/QCAP tree，不 clear 或 refetch；旧 entry 因而会保留且可能相对变化后的
> firmware capability 状态变陈旧，实际 task status 仍是每次命令的可见裁决。

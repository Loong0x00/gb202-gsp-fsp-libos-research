# `L2_REENABLE_STATIC_FINDINGS.md` 合并后一致性审计

日期：2026-07-21  
状态：final，纯文档只读审计；未修改主报告

## 审计基线与范围

本次逐段对照以下八份新报告：

- `parallel/shadow_reset_lifecycle.md`
- `parallel/gb202_fuse_descriptor_inventory.md`
- `parallel/l2_mask_granularity.md`
- `parallel/gb202_getfsinfo_support.md`
- `parallel/mods_l2_test_boundary.md`
- `parallel/newcudal2mats_native.md`
- `parallel/local_recovery_script_scope.md`
- `parallel/sbr_shadow_scope.md`

审计期间主报告又被另一条并行工作流合并；最终增量复核基线是 2,432 行，
SHA-256 为
`8461b9a0e4c15a9083253f45ef756353d1788bf57d35d26920d03a60a375b90f`，mtime
为 `2026-07-21 07:45:30 +0800`。下列行号针对这个精确版本；同时给出原文锚点，
以便主报告继续变化后仍可定位。

本轮只读 Markdown 文档，没有访问 GPU、设备节点、PCI/BAR/MMIO、MODS 或任何
二进制，也没有执行 reset、脚本或硬件测试。

## 总结

主报告已经正确吸收了绝大多数新结论，尤其是：

- `SetSwFuses` success tail 只有 reset 前 raw readback，没有 post-reset effective
  验收；
- reset 类型继承既有 coupling，shadow 保留/消费只是强设计推断；
- `GET_LTC_INFO_FOR_FBP` 的 host-local stub 不等于 GSP-offload endpoint 也是 stub；
- 2 MiB 只是条件性 accounting 标签，bit 的物理身份仍未知；
- test 351 是 aggregate `NewCudaMatsTest` 配置，不是逐 LTS 证书；
- 本地 SBR 脚本不是 shadow rollback，而且桌面在 5090 上时不能运行；
- authentic `gb202_f.json` 在已识别包链中缺失，synthetic JSON 不能替代它。

仍有 **5 处优先修正**和 **6 处建议收紧**。其中 tag-map 的 numeric-bit 身份、
per-FBP GET 返回范围和 post-reset “机制已知道”是实质性矛盾/过强结论，不只是
文风问题。

## 优先修正

### 1. tag-map 不能把 `0x12` 翻译成具体 slice

主报告 `2207..2213`，锚点为 `GB20X fuse tag maps`：

> 单项结构为 32-byte 字符串加 24-byte 字符串 vector，没有任何 chain、offset、
> bit 坐标或数值 tag。因此它能把 `0x12` 翻译成“哪个 slice 被关”……

前半句与后半句直接冲突，也与主报告自身 `2002..2006` 及
`parallel/l2_mask_granularity.md:232..258` 冲突。当前只能证明一个 FBP 名下有
8 个可读标签；记录中没有 numeric bit coordinate，因而不能判定 bit 1、bit 4
分别对应哪一个 `LTCx.slicey`。

建议替换为：

> 该表只能把一个 FBP 的 L2 floorsweep 名称关联到八个候选人类可读标签；由于
> 记录中没有 numeric bit coordinate 或 flatten 顺序，当前不能用 `0x12` 判定
> 具体哪两个标签被关闭，也不能生成 fuseless/IFF 行。

这是本次最明确的陈旧句。

### 2. 外部 JSON 字段与 parser 派生字段被混在一起

主报告 `571..581`，锚点为 `高层名称编码仍需要外部 JSON`，把名称、类型、
`FPF 标志 (+0x80)`、位宽和 offset 都列成“每个名称描述器至少提供”的项目，
却漏列 parser 必需的 `customer_visible`。同一主报告 `2136..2141` 已正确说明：

- `+0x80` 的 FPF 标志由加载来源派生，主 `_f.json` 传 0、`_fpf.json` 传 1；
- `customer_visible` 是 JSON 中必填的元数据；
- `_POR.json`、`_fpf.json` 是可选 companion，不是 direct-shadow 名称入口所需的
  主数据库。

建议把 `571..581` 改成两层表述：

> stock 名称入口必须先成功加载主 `gb202_f.json`；派生的 `_POR.json` 和
> `_fpf.json` 是可选 companion。主文件中每个目标 `Chip_options` record 至少要
> 有对象 key/name、`bits`、`type`、`offset` 和 `customer_visible`。内部
> descriptor 的 `+0x80` FPF 标志由 parser 根据主文件/FPF companion 来源填入，
> 不是主 JSON record 自己提供的必填字段。

这样可与 `parallel/gb202_fuse_descriptor_inventory.md:215..262` 及主报告后文完全
一致。

### 3. “机制已知道”超过了 reset 生命周期证据

主报告 `1899..1915`，锚点为 `这使关键链条已经闭合到原厂 host 控制流层面`，
先正确保留“哪种 reset 能让 OPT shadow roll up 仍未知”，随后又总结：

> 因此可以说**机制已知道**，不能说**本卡已验证解锁**。

这会把尚不可见的核心 consumer 误写成已知。新报告只闭合了 host scaffold：尝试
置 latch、写/回读 raw、依 coupling reset/reinit，以及 GSP 中分别存在 status/
effective getter。下列内容仍是 UNKNOWN：

- latch/raw 在每类 reset domain 中的保持、清除或消费规则；
- raw `0x8234e0` 到 status `0x820d70`、effective `0x822900` 的逐 bit rollup；
- reset/reinit 是否实际采纳本次 plan；
- success tail 是否在 reset 后观察到与 plan 相符的 topology（已证明它不比较）。

建议替换结尾为：

> 因此可以说 host 的“写 shadow → reset/reinit → GSP 重新枚举”框架已经知道；
> 真正决定 shadow 是否被保留、消费并传播到 effective topology 的 reset-domain/
> firmware/hardware 机制仍未知，本卡当然也未验证解锁。

`1902` 的“重建后的 GSP 再从 `0x820d70` 枚举”也宜标为设计链/强推断，而不是把
它写成 success-tail 已做的 post-reset 验收；独立 `+0x9b0/+0x9c0` getter 的存在
不等于该调用自动比较了请求值。

### 4. `GET_FS_INFO/LTS_MASK` 返回的是单个查询 FBP 的 flattened mask，不是“整卡 mask”

主报告 `132..147`，锚点为 `普通 GSP LTS 枚举没有发现 5090 专用容量常量`：

> 未启用 MIG 时，直接调用 FB 对象槽 `+0x9c0` 返回整卡 physical LTS enable
> mask……

`NV2080_CTRL_FB_FS_INFO_LTS_MASK_PARAMS` 带 `fbpIndex`，GB202 non-MIG handler
也把该 index 传给 `FB +0x9c0`。返回值是**所查询 physical FBP 内**所有 LTC/LTS
position flatten 后的 `ltsEnMask`；只有对多个 FBP 发 query/批处理并汇总，才构成
整卡视图。这里的 `physical/local` 还是坐标语义，不是 raw physical fuse 来源。

建议替换为：

> 未启用 MIG 时，type-3 query 把调用者给出的 physical `fbpIndex` 传给 FB
> `+0x9c0`，返回该 FBP 内 flattened current/effective LTS enable mask；批量覆盖
> 各 FBP 后才可组成整卡 effective-topology baseline。

同时建议把结论区 `43` 的“非 MIG 容量槽 `+0x9c0`”改成“非 MIG LTS-mask getter
槽”，避免把 topology getter 误叫容量槽。

### 5. 归档事实段混入了条件性的 48 raw positions / 2 MiB 模型

主报告 `70..92` 先列可直接复核的归档计数，随后在 `80..81` 写：

> 不能把 96 个 NCU `l2s`、48 个匿名 rollup 和 48 个 mask-bit 单元……

但“48 个 enabled raw positions”需要先采用未归档的 `8 x 0x12` 报告；它不是
前面归档数据直接给出的第三套计数。`91..92` 又称“结合静态的 2 MiB/bit
accounting model”，而新粒度报告明确把它列为 **CONDITIONAL**：还依赖规则、
等容量假设。

建议改为：

> 归档的 96 个 NCU `l2s` 与 48 个匿名 rollup 之间没有已证明的绝对身份映射；
> 即使进一步采用未归档的 `8 x 0x12` 报告，条件推得的 48 个 enabled raw
> positions 也不能与前两者直接写成一一/二一物理映射。

以及：

> 若 `8 x 0x12` 报告准确，并额外采用规则等容量的 2-MiB/raw-position
> accounting model……

“16 个 mask 单元”也宜写成“16 个 disabled raw positions”，避免把条件数字升级
成已识别物理单元。

## 建议收紧

### 6. 明说“单 bit delta”仍是整段 `[7:0]` raw 值写入

主报告 `1972..1992` 已正确证明 sparse plan 只生成一个 FBP 的一个 raw node，
并称其可表达“单个 raw mask bit 的修改”。但
`parallel/l2_mask_granularity.md:12..23,274..296` 进一步限定：控制目标可描述为
`(FBP, raw_bit)`，实际 plan/write 携带的是该 FBP 的完整 `[7:0]` 值，不是硬件
atomic bit-write。

建议在 `1978..1979` 后补一句：

> 这里的“单 bit”只描述新旧 8-bit 值的 delta；实际计划项仍写该 FBP 的完整
> `[7:0]` raw 值，因此其余七位必须来自可信基线，不能理解成寄存器级原子 bit
> clear。

### 7. JSON 缺失的文件系统范围应避免写成“全本机”

主报告 `2087..2097` 的“完整 archive 清单和本机文件搜索都没有找到副本”比
`parallel/gb202_fuse_descriptor_inventory.md` 的实际负搜索边界更强。该报告证明
的是项目目录、已提取 payload 和所有**可识别**嵌套 archive 中没有可寻址 schema；
`FindPkgFile` 的精确目录优先级、私有 Nautilus/runspace staging、加密/custom blob
仍未知。

建议把“本机文件搜索”改成“项目目录及已识别包链的 filename/member 搜索”，并
保留后文已有的 private staging / opaque blob caveat。结论区的“本地完整可识别
归档链”措辞已经合适，无需放大。

### 8. summary/下一步中的 GET 结论应继承 runtime allowlist 限定

主报告 `50..58` 和 `2407..2415` 使用“能/已静态证明能另行读回 effective
拓扑”。正文 `2284..2323` 已更精确：610.43.03/610.74 的 physical GSP export、
handler、GB202 getter 以及 ctl-only 最小 client chain 静态存在，但当前 live RM
object、control allowlist、句柄、加载中固件版本和返回码均未验证；
`GET_FS_INFO` export flags 也不含 `API_LOCK_READONLY`。这是 summary 的措辞收紧，
不是说新加入的 client-path 正文有硬错误。

建议 summary 改成：

> 已静态证明 GSP-offload physical/non-MIG 路由上存在读取 current/effective
> mask 的 handler/getter，可作为未来 baseline 候选；本卡 live 调用是否被允许及
> 返回状态仍未知。

这不会否定其 read-handler 语义，只避免把“静态 endpoint 存在”写成“本卡已经能
调用”。

### 9. 恢复脚本是“原用途/候选”，不是已验证适合该用途

主报告 `2388..2398` 的关键安全结论正确：脚本执行 SBR/hot-class 整卡恢复流程，
没有 shadow rollback，也不能在桌面仍由 5090 承担时运行。仅“它适合其原本的
dirty GSP/RM 恢复用途”略强于两份脚本报告；静态源码只能证明该目的和流程，
不能保证每种 dirty state 都能恢复。

建议改成“它原本用于、且可合理期待用于 dirty GSP/RM 恢复”，并补两个实际边界：

- BDF 固定为 GPU `0000:01:00.0`、上游桥 `00:01.1`，使用前必须重新确认；
- SBR 作用于桥下游，必须先确认没有其他 function/device 会被连带 reset。

还可注明它最后只用 `lspci` 和 `nvidia-smi` 验证设备/RM 回来，不验证 L2 topology。

### 10. `0x1087c000` / `0x10880000` 的双 ID 与“硬熔丝”术语需要显式解释

主报告 `184..190` 和新粒度报告直接证明 raw OPT/shadow 的 read/write ID 是
`0x1087c000/0x2087c000`。但主报告 `600..602`、`2201..2204` 又把同一地址族写成
`0x10880000`，`801..810` 同时列出两者。两者可能是不同 metadata/read alias，
但当前文本没有解释角色差异，读者会把它看成 ID 写错。

建议二选一：

- 若已有独立证据证明两个 ID 都映射该地址族，明确写成 alias，并分别说明哪个是
  direct-shadow raw getter、哪个是 hard-mask/floorsweep metadata getter；
- 若没有这项归档证据，把 direct-shadow 段统一回直接复核的 `0x1087c000`。

同理，`184` 的“硬熔丝/OPT”、`2202` 的“普通硬熔丝”、`2217` 的“运行时硬熔丝
读出视图”和表格中的 `hard mask` 容易让人误解为永久 OTP。对可被
`SetSwFuses` shadow writer 覆盖的这组坐标，建议统一称 `raw OPT/shadow view`；
把“实体 fuse”只留给 physical fuse/resense 语义。

### 11. aggregate test 的正信号应写成“reported”，并补异步错误边界

主报告 `2342..2362` 对 test 351 的整体判断正确。`2360` 的“容量/rollup 数增加”
建议改成“RM/PerfWorks **reported** 容量/rollup 数增加”，因为测试按当前报告的
`L2CacheSize` 配置 working set，并没有独立测量物理容量。

可在 `2355..2358` 后补一句：当前材料也不知道仅出现 L2 ECC/Xid、但没有 CUDA
data miscompare 时，test 351 是否会把异步事件纳入自身返回码。这样可避免把
“能捕捉所生成流量下的数据错误”读成“能捕捉所有新单元故障”。

## 已确认无需改动的关键段落

以下部分与八份新报告一致，建议保留当前证据等级：

1. `47..60` 及 `1383..1410`：success tail 没有 post-reset raw/effective/L2-size
   compare，success 不等于 adoption。
2. `1211..1410`：hot/boot/fuse/base 由已有 coupling 选择；显式 resense 尝试
   state-6 coupling + clear latch，但两项都不是 fail-closed 保证；base 不等于
   cold。
3. `2284..2296`：host-local old-control stub 与 physical GSP route 正确区分，
   `GET_FS_INFO` flag 不含 `API_LOCK_READONLY` 的 caveat 也已保留。
4. `1949..2009`（除上文 whole-byte 补充）：2 MiB 只作条件 accounting，不能把
   bit 1/4 固定映射到 LTC/slice、NCU `l2s` 或 PerfWorks rollup。
5. `2342..2358`：legacy per-slice wrapper 的支持门与 test 351 aggregate-only、
   generic-native 边界均正确。
6. `2364..2398`：核显/隔离构想不能真正 pin 桌面到物理 LTS；SBR 脚本不是
   rollback，桌面在 5090 上时绝不执行。
7. `2085..2165`（除上文范围/早期字段列表）：主 `_f.json` 缺失、companion
   optional、authentic descriptor 仍必要、自造 JSON 不提供安全性，这些结论一致。

## 最小合并建议

若只做一次小型修订，优先处理以下五项即可消除会改变读者理解的矛盾：

1. 删除 tag-map “能把 `0x12` 翻译成哪个 slice”的句子；
2. 修正 JSON 必填字段与 FPF 来源；
3. 把“机制已知道”限定为 host scaffold 已知；
4. 把 GET 返回范围从“整卡”改为“指定 FBP”；
5. 把 48 raw positions / 2 MiB 明确放回 `REPORT-ONLY + CONDITIONAL` 层。

其余六项属于证据口径和安全边界收紧，不改变当前总判断：目前仍不能安全写出或
运行 GB202 L2 解锁器。

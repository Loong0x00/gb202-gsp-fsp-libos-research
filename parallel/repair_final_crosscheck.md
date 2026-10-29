# GB202 current-GSP L2 repair final cross-check

日期：2026-07-21。对象是 610.43.03 的静态 GSP inner ELF、当前开源
RM，以及 `parallel/tmux_gsp_l2_repair.md` 和它的三支分析脚本。本复核没有
访问 GPU、设备节点、PCI/MMIO/BAR/debugfs，没有执行 MODS，没有 reset、
rebind、模块操作或固件操作，也没有做整镜像反汇编。

## 结论先行

1. **[已证实] GB202 没有绑定真正执行 LTS repair/marking 的两个方法。**
   当前开源 RM 将 GB202 映射为 `ChipHal` index 65，即 group 2 / low 1
   (`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_chips2halspec_nvoc.c:129-132`)。
   GSP 构造器的 `+0x188` 选择掩码是 `0x3001`；low 1 因而安装
   `0x01975824`，不是实现 `0x0156df8c`。同一构造器给 GB202 的
   `+0x1b0` 安装 `0x01975874`，而包含 `Marking LTS` 文案的实现是
   `0x0156e394` 和 `0x01581374`。
2. **[已证实] GB202 的两个短桩是“成功 no-op”，不是显式 unsupported。**
   `0x01975824..0x01975830` 和 `0x01975874..0x01975880` 都只建立/撤销
   16-byte 栈帧、把 `a0` 置 0 后返回；不写参数，也没有 repair 副作用。
   当前状态码定义明确 `0 == NV_OK`、`0x56 == NV_ERR_NOT_SUPPORTED`
   (`/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/nvstatuscodes.h:27,115`)；
   同一短桩簇的 `0x01975804`、`0x01975814` 确实返回 `0x56`，所以不能把
   GB202 选中的返回 0 短桩描述成 `NV_ERR_NOT_SUPPORTED`。
3. **[已证实但需限定] GB202 还会安装一个公共的 `+0x5e8 =
   0x0157b570` 条件处理器。** 该函数在 `0x0157b662..0x0157b672`
   以 selector 3 间接调用同对象的 `+0x188`。因此在 GB202 上，该调用仍落到
   `0x01975824` 成功短桩，而不是 `0x0156df8c` repair body。公共处理器的
   存在不能推翻前两项结论；现有扫描也没有完成 object-aware caller 证明，
   所以“构造时安装”不能自动升级成“GB202 runtime 必然调用”。
4. **[已证实] `Marking LTS` 和 no-spare 文案不是整个固件中的孤立死数据；
   [结论] 这些引用不构成 GB202 repair 实现存在的证据。** 前两条 marking 文案有
   真正的 PC-relative code xref，但其 enclosing 方法不绑定 GB202。no-spare
   文案在公共处理器内有 code xref，但分支有条件，且处理器内的 repair 调用在
   GB202 上仍是 no-op。
5. **[未知] `pending LTS swap` 是否有 live consumer。** 它只有一个位于
   `0x01dcd7d0..0x01dcd810` 的原因字符串指针表条目；限定 xref 扫描没有找到
   直接代码地址构造。该表是字符串表，**不是 repair/spare map**。间接索引、
   GP-relative 或其它未覆盖访问仍可能存在，所以也不能把它证明成死数据。
6. **[结论] 当前证据能区分“通用结构化 repair record/请求”与“公开的 flattened
   floorsweep LTS enable mask”这两种软件表示，但不能证明零售 GB202 有一张
   非空、与 SKU mask 分开持久化的 repair map。** 更不能从文案或通用构建开关
   推出本卡 disabled LTS 可被 repair 路径重新启用。

## 1. 静态对象和映射复核

- `/tmp/gsp_inner_19f040_a.elf` 本次复算为 82,577,496 bytes，SHA-256
  `bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`；
  既有来源记录把它闭合到 610.43.03 outer firmware 的 `0x19f040` 后缀
  (`parallel/GSP_ARTIFACT_PROVENANCE.md:16-25,34-42`)。
- ELF 是 stripped ELF64 little-endian RISC-V/RVC。第一个 executable
  `PT_LOAD` 为 file offset 0 -> VA `0x01000000`，file/memory size
  `0x00e97000`。三支脚本使用的 VA/file-offset 换算与这个具体 artifact 一致。
- 当前开源 `ChipHal` 表给 GB202 index 65；这是 group 2、low 1
  (`g_chips2halspec_nvoc.c:129-132`)。

### 基础构造器

- `0x0198d010` 先做 `a3 = a2 & 0x1f`，与 group-2 low index 一致。
- `0x0198da5a..0x0198da70` 计算 `(0x3001 >> a3) & 1`。
  set 分支在 `0x0198da74..0x0198da7c` 构造并写入
  `+0x188 = 0x0156df8c`；clear 分支在 `0x0198de56..0x0198de5e`
  构造 `0x01975824` 后回到同一 store。故 group-2 真实现集合严格为
  low `{0,12,13}`，不含 low 1/GB202。
- 对 GB202 的同一路径，`0x0198db9c..0x0198dba0` 保留
  `t5 = 0x01975874`，并在 `0x0198dbdc` 写入 `+0x1b0`。
- 独立重跑 `gsp_inforom_vtable_replay.py` 得到：

  | index | 芯片 low | `+0x188` | `+0x1b0` |
  |---:|---:|---:|---:|
  | 64 | 0 | `0x0156df8c` | `0x0156e394` |
  | 65 / GB202 | 1 | `0x01975824` | `0x01975874` |
  | 76 | 12 | `0x0156df8c` | `0x01581374` |
  | 77 | 13 | `0x0156df8c` | `0x01581374` |

  我还把 replay 的“缺失寄存器默认为 0”临时替换成 read-before-write 即报错的
  strict getter，以上 base/extension 四个索引全部通过；这排除了这些路径依赖
  未初始化寄存器而偶然选中分支的风险。

### extension 构造器和公共处理器

- extension 原函数在 `0x01b29a54` 从对象读取 chip index，
  `0x01b29a5a` 计算 group，group 2 在 `0x01b29a64` 跳到
  replay entry `0x01b29f4c`。因此脚本预置的 `a4=2, a5=index` 与前驱一致。
- `0x01b2a1b8..0x01b2a1e4` 对 low index 测试 `0x30ff`。该集合是
  low `{0..7,12,13}`，不是全部 group-2 index；GB202 low 1 在集合中。
- 该分支在 `0x01b2a22a..0x01b2a22e` 构造 `0x0157b570`，于
  `0x01b2a26e` 写入 `+0x5e8`。全 32 个 group-2 low index 的限定 strict
  replay 也给出：low `{0..7,12,13}` 为 `0x0157b570`，其它 low 为
  `0x01975f40`。
- `0x0157b570` 内的关键路径为：`0x0157b662` load `+0x188`，
  `0x0157b66c` 设置 selector 3，`0x0157b672` 间接调用；返回 0 后的另一条件
  分支才在 `0x0157b67c` 构造 no-spare 字符串并于 `0x0157b68a` 调日志函数。
  因而对 GB202 能静态证明的是“公共 handler 内调用成功短桩”，不是“执行 repair”。

## 2. 实现、no-op 和 unsupported 的边界

- `0x0156df8c` 不是短桩：它保存多个寄存器、按 selector 分支，并间接调用同对象
  的多个方法槽；函数体延伸到约 `0x0156e25a`。这足以把它与 16-byte stub
  区分。
- `0x0156e394..0x0156ecbe` 和 `0x01581374..0x01581e0e` 也都是大型实现；
  前者在 `0x0156e842`、`0x0156eb64` 构造 marking 文案，后者在
  `0x01581dd4` 构造 marking 文案。它们随后把字符串作为日志参数传递，不是把
  ASCII 偶然解码成指令。
- `0x01975824`、`0x01975874` 则没有调用、store 或参数写回，只有 `a0=0`
  后 return。对 `+0x188` 的调用点又以 `bnez a0` 处理错误，所以这是可观察的
  success/no-op 行为。可以说功能在 GB202 上“不受支持/未实现”，但不能把返回码
  写成 `NV_ERR_NOT_SUPPORTED`。
- `RMCFG_FEATURE_LTS_REPAIR=1` 的当前注释是 “Support for LTS swapping
  in-field” (`/usr/src/nvidia-610.43.03/src/nvidia/generated/rmconfig.h:340`)。
  它只说明通用功能族被编入；构造器的 per-chip 选择优先，不能覆盖 GB202 stub。

## 3. 字符串存活性复核

| 字符串 | 静态事实 | 对 GB202 可推出什么 |
|---|---|---|
| `Marking LTS ... FBP` (`0x01e7ed10`) | code xrefs `0x0156e842`, `0x01581dd4` | 在非 GB202 实现中为 live log；GB202 `+0x1b0` 不指向这些函数 |
| `Marking LTS ... FPB` typo (`0x01e7ec50`) | code xref `0x0156eb64` | 同上 |
| `Repairing LTS failed ... no more spare` (`0x01e818a0`) | 公共 handler code xref `0x0157b67c`，日志 call `0x0157b68a` | handler 被安装，但路径有条件；repair dispatch 仍落 GB202 no-op |
| `pending LTS swap` (`0x01e81a70`) | 仅见 `0x01dcd7e8` 的 64-bit pointer-table entry | live/dead 未决；不能当作 map，也不能证明 GB202 pending 状态 |
| `bus reset` / `os reboot` / `unknown` | marking 实现内有直接选择 xref | 支持通用实现“下次 reset 激活”的语义，不证明 GB202 实现 |

`0x01dcd7d0..0x01dcd810` 是九个相邻字符串指针，依次覆盖 internal error、
pending row/bank/LTS、no spare、HW limit、full InfoROM object、SBE row remap、
disabled retirement。这里存的是显示原因，不是 FBP/LTC/LTS bit map。限定 AUIPC
扫描只在 `0x0158021c` 命中表后方的 `0x01dcd818`；该函数随后从
`0x01dcd838` 起读取另一组 0x20-byte 结构，不能据此宣称消费了
`0x01dcd7d0` 字符串表。补充对第二个约 1.9-MiB RW `PT_LOAD` 的同一组
32/64-bit direct-value 搜索也没有表基址/邻近地址命中；这加强了“未见直接引用”，
但仍不排除计算地址或间接索引。

因此原报告“pending 字符串没有直接 code construction”的窄说法成立；把这个
阴性结果扩展为“必为死数据”或“必为 InfoROM live status”都超过证据。

## 4. repair record 与 SKU floorsweep mask

### 能证明的区分

- 当前公开 FS 查询把 LTS topology 表示为每个 physical/local FBP 的 flattened
  `NvU32 ltsEnMask` (`/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080fb.h:2021-2033`)。
- 非 GB202 的 marking 实现把第三参数保存在 `s5` (`0x0156e3b8`)，随后把它当
  结构化 record 使用：读取 `+0/+4/+8/+0xc` dword，例如
  `0x0156e85a`、`0x0156ea58..0x0156ea72`、
  `0x0156ebf6..0x0156ec06`；它还遍历内部集合并调用多个对象方法。
  这不是把一个 flattened `ltsEnMask` 直接当作 repair map。
- marking 文案本身说与 pair 一起标记并要求 bus reset 或 OS reboot；结合
  `rmconfig.h:340` 的 “swapping in-field”，它支持“通用现场 swap 请求、下次
  reset 激活”，而不是“只有一次的制造阶段修复”。它也不同于 row-remap：二者
  只是在退休原因字符串表中并列。

### 不能证明的区分

- 上述“软件表示不同”不等于“本卡物理存储一定分离”。本次静态证据没有找到
  GB202 非空 repair/spare record、持久化对象位置、条目内容或它与 SKU/OTP/
  effective floorsweep mask 的合并顺序。
- `pending LTS swap` 的字符串表不是持久化 map 证据；`InfoROM` 相关邻近文案也
  不能替代对象写入/读取链证明。
- 公开的 LTS enable-mask 查询没有 provenance 字段，无法说明一个 clear/set bit
  来自 SKU、缺陷、repair 还是合并结果。公开 repair-status control 也只返回
  TPC/channel pending，没有 LTS 字段
  (`/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080ecc.h:203-220`)。
- 最关键的是 GB202 的 record-processing/marking 槽位均为 no-op stub。因此即使
  通用框架存在，也不能据此声称 GB202 当前 firmware 会消费或生成 LTS repair map。

最终判定应写成：**通用 RM/GSP 有独立于 flattened topology mask 的 repair-record
概念；GB202 是否存在独立、非空且持久化的 defect/repair map，仍是 UNKNOWN。**

## 5. 三支脚本的可信范围

### `gsp_l2_xrefs.py`

- 优点：只扫描第一 executable `PT_LOAD`，AUIPC 候选要求 Capstone 解码和后续
  operand 配对；每次只解 24 bytes。对本次已核 hash 的 artifact，字符串
  PC-relative xref 和构造器常量 xref 可复现。
- 限制：ELF mapping、size 和所有目标地址均硬编码
  (`parallel/gsp_l2_xrefs.py:18-47`)；脚本不校验 hash/program header。
- `DIRECT32` 命中 64-bit pointer 的低四字节时会与 `DIRECT64` 重复，不能算两条
  独立引用。
- AUIPC 扫描只覆盖随后 24 bytes 内的简单 ADDI/memory/jalr 配对
  (`gsp_l2_xrefs.py:62-106`)；GP-relative、先存后取、跨更长 basic block 和
  二级表索引会漏报。故“没命中”不能证明 dead。
- `CALLSLOT` 只按数值 offset `+0x188/+0x1b0/+0x5e8/+0x6a0` 搜索
  (`gsp_l2_xrefs.py:108-147`)；这些 offset 在大型固件的其它对象中大量重用。
  它不是 type/object-aware xref，输出的数百个候选不能作为 repair-object caller
  清单。已知 `0x0157b570` 内部的 `+0x188` 调用之所以可信，是先由构造器和函数
  局部控制流固定了对象关系，而不是只凭 offset 扫描。

### `gsp_rv_window.py`

- 它只读取请求窗口，强制第一 `PT_LOAD` 范围并限制为 128 KiB
  (`parallel/gsp_rv_window.py:15-22`)；本次使用窗口均远小于上限，资源行为合格。
- 它同样硬编码 VA mapping，且 Capstone 遇到不可解码字节会停止而不额外报警；
  所以函数边界仍需由邻接入口/控制流人工复核。这里的两个 stub 和三个大型函数
  边界均已用相邻入口重新核过。

### `gsp_inforom_vtable_replay.py`

- 它是有限 RV64/RVC 解释器，只在两个 constructor window 内运行，遇到未支持
  指令或逃逸会报错，最多 10,000 steps；不会调用任何固件 method
  (`parallel/gsp_inforom_vtable_replay.py:34-155`)。
- 本次在 384 MiB ceiling 下重跑完成；四个报告索引以及全 32 个 group-2 low
  index 的关键槽结果与手工小窗口一致。前驱窗口也验证了 base/extension 的
  seeded register state。
- 限制：它以 `Path.read_bytes()` 读完整 82.6-MiB ELF，仍低于本任务 ceiling，
  但并非最小读取；也没有 size/hash/program-header guard
  (`gsp_inforom_vtable_replay.py:158-168`)。
- `get()` 默认把未知寄存器当 0，正式脚本本身不会报告 undefined read；本复核的
  strict-getter 重跑降低了这次四条路径的风险，但这个限制对以后新增索引/stop
  point 仍存在。
- extension 默认在写 `+0x5f0` 后停止，却还打印 `+0x6a0/+0x760/+0x778`；这些
  `value=0, store=0` 表示“未重放到/未记录”，不是构造器实际写了 0
  (`gsp_inforom_vtable_replay.py:43,171-176`)。

## 6. 对 `tmux_gsp_l2_repair.md` 的审计结论

### 可保留

- 第 16-24 行的 string VA、marking/no-spare code xref 和 pending 字符串表布局
  均可复现；但 pending 的结论必须保持为“未见直接 xref”。
- 第 28-37 行的 GB202 index 65、`0x3001` 选择、`+0x188/+0x1b0` 绑定和两个
  zero-return stub 是核心正确结论。
- 第 38-39 行谨慎写成 “every tested group-2 index” 是正确的；若改成“全部
  group-2”，则会错，因为 extension handler 的实际集合是 `0x30ff`。

### 必须保留的限定/缺口

- stripped ELF 没有给出符号名；“repair HAL slot”“InfoROM constructor”是由函数
  行为、文案和互调关系作出的语义归类，地址绑定是事实，类/方法正式名称应标成
  inference。
- 构造器安装方法不等于已证明 runtime caller/reachability。现有 `CALLSLOT`
  扫描不能完成 object-aware caller 追踪。
- 原报告没有回答原任务中的持久化/row-remap/制造修复区分、repair map 与 SKU
  mask 分离、公开可观测性，也没有最终 plain-language summary；不能把 39 行报告
  当作这些问题已闭合。

## 最终一句话

**610.43.03 inner GSP 确实包含非短桩的通用 LTS in-field swap 实现体和代码日志引用，
但 GB202 index 65 的两个关键方法都被构造成返回 `NV_OK` 的无副作用短桩；公共
no-spare handler 的存在不改变这一点。当前静态材料也没有证明本卡有一张独立、
非空的 LTS repair map，更没有证明它能与最终 SKU floorsweep mask 安全分离或用于
扩容。**

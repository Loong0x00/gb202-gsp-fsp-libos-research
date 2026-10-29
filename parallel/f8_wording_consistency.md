# `0x8200f8` 事实／推断／未知措辞一致性核对

> **后续事实更新：** 固定 610.43.03 GSP 的 direct `f8` block 已闭合为
> TU102/TU116 OBJBSP/NVDEC helper；GB202/index 65 的同槽绑定 success stub。
> 因此凡将该 block 写作“GB202 runtime reader”的措辞均应撤回；其静态读写方向
> 仍可作为旧芯片实现事实。见 `parallel/gsp_f8_consumer_lifecycle.md`。

## 范围

收到任务改为纯文档核对后，本阶段只核对
`L2_REENABLE_STATIC_FINDINGS.md:792-972` 与 `parallel/` 下现有 Markdown 的
措辞和相互引用；本文结论没有采用新的二进制分析，没有访问 GPU、MMIO、
debugfs 或设备节点，也没有修改主报告。

本文采用三档口径：

- **事实**：被所引文档作为直接静态关系陈述；
- **推断**：由若干静态关系支持，但并非 GB202 FSP/硬件内部动作的直接证据；
- **未知**：现有文档没有闭合，负搜索也不能升级为“不存在”。

## 总体判定

各文档的最终安全结论没有实质冲突：`0x8200f8` 是与 `0x8200d0/0x8200dc`
分离的 latch access-PLM 关系；现有材料不知道本卡当前 `0x8200f8` 值，也没有
直接证明 GB202 task 2 会修改它、权限能维持多久或如何恢复。旧 GV100 secure-PMU
路径只是历史先例，GB20x `UseTestValues` 也不是替代降权入口。

需要修正的是证据等级和协议边界的表达。当前最明显的问题是：主报告一处把
`d0/dc` 的强推断写成了语法前提；若干段又把 HULK `NVDM_TYPE=0x11` 与 MODS
floorsweep `task=2/subobject=1` 并排压缩成“HULK task 2”，容易造成两者已被证明
相同或存在映射的错觉。现有文档并未证明这种等价或内部映射。

## 建议修正的具体段落

### 1. 主报告 `L2_REENABLE_STATIC_FINDINGS.md:794-799`

当前 `“latch 的写权限由 0x8200f8 裁决”` 容易被读成 `0x8200f8` 是全部写权限
的唯一判据；`“即使 task 2 已经把 0x8200d0/0x8200dc 降到可写”` 又把其他
文档明确标为 **强推断** 的 `d0/dc` lowering 写成了既成事实。它与
`parallel/evidence_audit.md:193-201`、`parallel/tmux_mods_permissions.md:51-53`
及 `:96-97` 的分级不一致。

建议改成：

> RegHal access metadata 把 latch ID 的设备侧 access PLM 指向
> `0x8200f8`。这证明一项独立的静态 PLM 关系，不证明该 PLM 的当前值、latch
> 的总体可写性或写请求会被接受。即便暂时接受“task 2 旨在降低
> `0x8200d0/0x8200dc`”这一强推断，也不能外推 task 2 同时处理 `0x8200f8`。

这样仍可保留“`f8` 是 latch 的独立设备侧门”的结论，同时避免把 host gate、
其他硬件条件和实际寄存器状态吞并进一个绝对的“由它裁决”。

### 2. 主报告 `L2_REENABLE_STATIC_FINDINGS.md:825-829` 后应补明当前状态未知

该段已经正确说明 `IsFusePrivSecurityEnabled` 是只读 OR 查询，不能把查询结果
等价成 latch 可写性；但没有在同段明确说“静态映射和查询逻辑都不能给出本卡
当前 `0x8200f8` 值”。`parallel/evidence_audit.md:20-22,176,201`、
`parallel/tmux_mods_permissions.md:52-54,114-115` 均把这项列为未知。

建议补一句：

> 现有归档没有本卡 `0x8200f8` 的读取结果；其当前值及一次 latch-set 请求是否
> 会被接受仍为未知。

这不是新结论，而是把 parallel 文档已经统一采用的证据边界带回主段落。

### 3. 主报告标题 `L2_REENABLE_STATIC_FINDINGS.md:871`

`“HULK 是现代签名降权通道”` 把“存在签名授权/受控寄存器动作机制”直接命名成
当前 GB202 已证实的 PLM lowering。正文 `:966-968` 和 parallel 文档实际上只说：
若存在绑定本卡且授权 `0x8200f8` 的证书，理论上可能建立权限窗口；目前没有这种
证书，也不知道 HULK 对任何具体 PLM 的效果。

建议标题改为：

> HULK 是现代签名授权／受控寄存器动作通道；是否降低 GB202 `0x8200f8` 未知

或至少把“降权”标为可能用途，而不是当前 GB202 的事实。对应边界见
`parallel/evidence_audit.md:211-217`、`parallel/gb202_610_arch.md:116-123` 和
`:265-277`。

### 4. 主报告 `L2_REENABLE_STATIC_FINDINGS.md:864-899` 应显式拆开 HULK 与 task 2

`:864-869` 讨论可见 GSP 的 HULK 证书通道，`:894-899` 紧接着写
`HULK payload/caller、task/subobject dispatcher` 和
`“task 2/f8/恢复语义”`。虽然逐句可以解释为列举两个独立缺口，但当前排列容易
暗示 HULK `0x11` 已知会落到 floorsweep `task 2/subobject 1`。

建议明确写成两个互不替代的未知项：

> 可见 GSP-RM 中存在 HULK `NVDM_TYPE=0x11` sender，但没有证据把该 HULK
> 请求映射为 MODS floorsweep 的 `task=2/subobject=1`。另一方面，公开源码也
> 没有披露独立 floorsweep task-2 consumer。HULK 对 `f8` 的证书动作、task 2
> 是否处理 `f8`，以及两条路径各自的 restore/lifetime 均未闭合。

这也能解释看似相反的两句并不矛盾：主报告从可见 GSP-RM 静态材料中找到了
HULK sender，而 `parallel/gb202_610_arch.md:110-123` 只说公开 610 C/H host
源码没有公开 HULK caller/payload。

### 5. `parallel/evidence_audit.md:151`

`“公开源码仍无法证明 HULK task 2/subobject 1 或 PLM restore”` 把两条尚未证明
等价的协议压成了一个名词组。建议改为：

> 公开源码仍无法证明 HULK 的 payload/PLM 效果，也无法证明独立 floorsweep
> task 2/subobject 1 的 firmware consumer 或任何 PLM restore；现有材料没有
> 建立 HULK 与 task 2 的映射。

`parallel/evidence_audit.md:184-201` 对 floorsweep task 2 的独立分级本身正确，
无需改变。

### 6. `parallel/gb202_610_arch.md:16,265,273-277`

`:16` 和表格 `:265` 使用 `“HULK task 2 / subobject 1”`，同样容易把未知映射
写成已存在的协议对象。`:273-277` 应保留为“待回答的问题”，但要明确这是询问
是否存在内部映射，而不是已知 HULK payload 格式。

建议把表格问题改为：

> 当前树能否证明 HULK `0x11` 在 FSP 内部映射到 floorsweep
> `task 2/subobject 1`？——不能；两者等价性未知。

并另列：

> 当前树能否证明 MODS 所见 floorsweep task-2 consumer、`f8` 动作和
> restore？——不能。

该报告 `:116-123` 已经正确说“不能证明 HULK 落到哪个 task”；只需让摘要和表格
沿用同一限定。

### 7. `parallel/tmux_mods_permissions.md:51,114,123` 与 completion 摘要 `parallel/inbox/tmux_mods_permissions.done.md:10`

`tmux_mods_permissions.md:51` 正确把“task 2 旨在为 `d0/dc` 准备权限”列为
**强推断**；但 `:114,123` 及 completion 摘要把实际 `d0/dc/f8` lowering 一并
压成“未知/未证明”，没有说明三者的支持强度不同。这不是逻辑上的硬矛盾——
“意图的强推断”与“实际 firmware 动作未证明”可以同时成立——但目前措辞很容易
被读成前后降级互相否定。

建议统一成：

> 对 `d0/dc`，task 2 的用途有强静态推断，但实际 GB202 firmware 修改仍未直接
> 证明；对独立 `f8`，现有 task-2 类比连用途都没有覆盖，是否修改完全未知。
> 三者的实际 lifetime/restore 均未知。

### 8. `parallel/tmux_mods_permissions.md:104` 的历史引用应更新

该段对 GV100 `f4/f8` 的“历史事实、GB202 未知”分级正确，但引用
`L2_REENABLE_STATIC_FINDINGS.md:786-790` 已失配；当前对应段落是
`L2_REENABLE_STATIC_FINDINGS.md:831-835`。这是引用定位错误，不改变结论等级，
但应修正以免读者落到无关的 resense 段落。

## 不构成矛盾、应保留的边界

- 主报告 `:831-835` 的 GV100 secure-PMU `f4/f8` setter 是历史静态事实；
  `parallel/evidence_audit.md:225-235` 和 `parallel/tmux_mods_permissions.md:102-110`
  只禁止把它外推到 GB202，二者不矛盾。
- 主报告 `:837-853` 把当前 GB20x `UseTestValues` 限定为软件布尔动作；这与
  `f8` lowering 未知并不冲突。它只排除了一个候选入口，没有证明所有私有固件
  路径不存在。
- 主报告 `:855-869` 的直接常量扫描属于有范围的负证据。最终收窄为
  “没有找到无凭据的 GB20x `f8` setter”，并未证明 HULK/FSP/间接描述符不存在；
  这个限定应保留。
- 主报告 `:966-968` 使用“若存在”“理论上可能”“当前不能证明”，已经是正确的
  假设性推断，不应升级成可用入口或当前权限事实。
- `parallel/mods_final_crosscheck.md:79-87,104` 对 `d0/dc` 强推断、`f8` 未知的
  分级与上述标准一致，无需修正。

## 建议采用的统一最小表述

> 静态 RegHal metadata 将 software-override latch 的设备侧 access PLM 指向
> `0x8200f8`；这不提供本卡当前值，也不证明 latch 请求会被接受。GB202
> floorsweep task 2 为 `0x8200d0/0x8200dc` 准备写权限属于强推断，其实际
> firmware 动作仍未直接可见；没有相应证据把该推断扩展到独立的 `0x8200f8`。
> HULK `NVDM_TYPE=0x11` 是另一条签名授权通道，现有材料没有证明它等同或映射到
> floorsweep task 2，也没有可用于本卡并授权 `0x8200f8` 的证书。`f8` 当前值、
> task-2/HULK 对它的实际动作、权限 lifetime、消费与 restore 均为未知。

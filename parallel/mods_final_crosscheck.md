# `tmux_mods_permissions.md` 终稿交叉审计

审计对象：`parallel/tmux_mods_permissions.md`（2026-07-21 03:53:01 +0800 版本，37,897 bytes）。该文件在本审计进行期间从 03:47 版本更新；以下结论已按 03:53 版本重新核对。

## 范围与总评

本次只读取现有报告、脚本以及 MODS 570.151 ELF 的少量地址窗口；没有运行 MODS，没有访问 GPU、`/dev/nvidia*`、PCI/BAR/MMIO、驱动 control、debugfs 或任何 reset/rebind 接口，也没有做全文件反汇编。没有修改被审计主报告。

03:53 版本已经补入两个重要事实：raw handler `+0xb8` 的返回寄存器不被 caller 消费，以及 resense coupling/clear 请求不是 fail-closed。主体证据等级现在基本稳健；仍有三项终稿修正：一个确定的字符串事实错误、一个 resense reset 分支遗漏，以及一个无参数 task-2 路径限定。完成这三项纯文本修正后，本次有限范围审计可接受其余重点结论。

## 仍需修正

### 1. `0xbadf510c` 分支的日志字符串写错

当前第 28 行引用的 VA/file offset 正确，但字符串内容错误：

- `0x1516090` 装入 `esi=0x8c526e0`。
- VA `0x8c526e0` / file offset `0x88526e0` 实际为 `Priv-level violation while verifying offset [0x%08x] on D%u\n`。
- `Unexpected true read mismatch : 0x%x, 0x%x` 位于另一位置（file offset `0x8852ac0`），不是此分支使用的字符串。

控制流等级仍可保持 **PROVED**：readback 为 `0xbadf510c` 时只记录 privilege-level violation，`0x15160a7` 随后前进到下一节点，不修改 `[rsp+0xc]` aggregate status。需要修的是日志内容和语义，不是该分支的继续行为。

### 2. resense caller 可能在 pre-silicon 分支跳过 reset

03:53 版本已经正确降级为“发出 `0x404f0000` clear-coded operation”，并正确记录 coupling failure 只日志后继续、clear call 返回被覆盖。但第 70、72、91、123 行仍把 caller 概括成随后“reaches/invokes reset”，漏掉一个直接可见分支：

- `0x1516f30` 调用 preparation helper；非零返回会直接退出。
- helper 返回零后，caller 在 `0x1516f49..0x1516f58` 再调用平台 predicate `+0x1c0`。
- predicate 为 false 时才在 `0x1516f5a..0x1516f6f` 调用 handler `+0x100`。
- predicate 为 true 时，`0x1516f80` 记录 `Skipping fuse reset on Pre Silicon Platforms!`，然后以当前零状态返回；该分支明确不请求 reset。

因此建议精确表述为：

- **PROVED：** 当前 GB20x host 路径尝试 state-6 coupling，随后发出 `0x404f0000`；在 preparation 成功且非 pre-silicon 分支，caller 才进入 coupling-selected reset callback。
- **INFERENCE (strong)：** RegHal 配对和函数角色支持把 `0x404f0000` 解释为“尝试清 software-override latch，以便从 physical fuse resense”。
- **UNKNOWN：** coupling 是否建立、latch 是否真正清零、reset 是否实际执行并完成，以及 FSP/hardware 最终效果。

另有一个 reset-type 措辞需要收紧。第 73/92 行把 type 6 与“本次 coupling attempt 实际生效”绑定得过紧。mapper 静态证明的条件只是：它在 reset 时观察到 base=false、fuse=true；该 fuse coupling 可能是本次请求建立，也可能是先前已存在。精确结论应是：最终 type 6 仅在 mapper 观察到 fuse coupling 且没有更高优先级 base coupling 时选择，不能仅凭 host caller 把该 bit 的来源归因于本次 attempt。

这些修正不改变核心路径分离：该 helper 不在已检查的 `SetSwFuses` 正常成功尾或 error cleanup 尾中，没有恢复旧 raw 值，因而不是 direct writer rollback。

### 3. “无参数首轮仍发送 task 2”需要正常 FSP 路径限定

当前第 63、117 行的窗口假设有静态依据，但“still sends task 2”不应无条件书写：

- `0x10960cc` 确实在 host apply `0x109622b` 之前调用 vtable `+0x520`。
- GB20x implementation `0x106c4e0` 在 `0x106c4f1` 先测试传入的 `doFsp` 布尔；为 false 时直接走 no-send 分支，不进入 `0x106c570..0x106c58c` 的 task-2 sender。
- `0x109a485` 把新对象的 pending/initialized 清零，直接证明首次调用不会因 initialized 状态提前返回；它本身不证明所有配置分支都令 `doFsp=1`。

建议改为：在正常 GB202 FSP-enabled、`SkipFspFs` 未启用且前置检查成功的首次无-floorsweep-参数路径，host 仍发送 task 2，但因 pending=false 跳过 host apply，外层请求汇总为零时也跳过 post-FS reset。`SkipFspFs` 或前置失败路径不属于这个命题。

后续权限是否维持到脚本层 `SetSwFuses` 仍为 **UNKNOWN**；主报告对权限 lifetime、`f8` 和 restore 的 UNKNOWN 等级正确。

## 错误继续与 reset 行为复核

| 事件 | 直接可见的 host 行为 | 证据结论 |
|---|---|---|
| `0x404f0001` latch-set request 返回 | 未测试，继续进入计划 | **PROVED**；实际 latch set **UNKNOWN** |
| raw handler `+0xb8` write 返回寄存器 | `0x151606e` 立即覆盖 `rax`，随后依赖 readback | **PROVED**；03:53 版本已补入 |
| readback 为普通不等值 | aggregate 尚为零时置 `0x79`，继续其余节点 | **PROVED** |
| readback 为 `0xbadf510c` | 记录 privilege violation，不设 aggregate error，继续 | **PROVED**；可最终进入 success/reset 尾 |
| pre-program preparation 非零 | 在进入 writer 前 cleanup | **PROVED**；不存在 partial writer 状态 |
| programming aggregate 非零 | core cleanup，跳过 `+0x370` | **PROVED**；无 host rollback/latch clear/reset |
| programming aggregate 为零 | 两个已检查 core 分支都进入 `+0x370` | **PROVED**；不等于所有底层动作均被确认 |
| resense coupling request 非零 | 只日志，仍发 `0x404f0000` | **PROVED**；不是 fail-closed |
| `0x404f0000` 返回 | 未测试、未保存、无立即 readback | **PROVED request**；实际 clear **UNKNOWN** |
| resense pre-silicon predicate 为 true | 明确记录日志并跳过 reset | **PROVED**；主报告当前遗漏 |

仅凭 raw-write caller 不能确定 `+0xb8` 的源码声明是 `void` 还是带返回值；严格证明的是 caller 不消费返回寄存器，也没有独立 write-acknowledgement 检查。03:53 版本第 27 行的实质结论成立。

## 重点标签的接受结果

### Reset priority

证据充分，可保持 **PROVED**。`0x126b360` request-2 分支的选择优先级为 base `7`，其次 fuse `6`、boot `5`，最后 hot `3`；request-2 jump-table entry 落到 `0x126b430`。这只证明 mapper priority，不证明本卡当前 coupling 值、某次实际 reset 类型或 coupling bit 的来源。

`0x127b000` 先执行一次正常 reset/reinit；仅在第一次成功后且 recovery property 为 true 时才第二次调用 `0xdff7b0`。所以“第二次 reset 是 recovery handling，不是 two-phase commit”可保持 **PROVED**。

### PRC 与 FSP task 2

除上述默认路径限定外，分级正确：

- **PROVED（成功 host 路径的相对顺序）：** 可选 PRC read/write 先于 floorsweep 参数处理；真正发送 task 2 时，该操作成功后才可能执行 pending host apply。错误会终止后续步骤。
- **PROVED（ID 后续纠正）：** PRC executor 先读目标 knob，仅在值不同时发送 task `0x0d`/submessage `2`，随后读回比较；完整 0x28-byte record 重建证明 `PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT` 是 knob `0x1d`，而 `0x1c` 是前一项 `RPR_ALLOW_INB`。这证明 host 协议，不证明 FSP 内部消费/self-clear 语义；纠正依据见 `parallel/prc_knob_metadata.md`。
- **PROVED：** GB20x sender 的实际消息为 task `2`/subobject `1`；capability 缺失时走 `0x12d`，不发送正常请求。
- **STRONG INFERENCE：** Hopper sibling 的 `0x8200d0/0x8200dc` PLM precheck、相同 task/subobject，以及 GB202 send-before-apply，共同支持“GB202 task 2 至少旨在为 d0/dc host floorsweep 写准备权限”。没有 GB202 FSP consumer，不能升级成 PROVED。
- **UNKNOWN：** 是否也降低独立 `0x8200f8`、权限能否保持到后续 `SetSwFuses`、是否跨 reset、何时 restore/self-clear，以及 production 610 是否接受 MODS 570 假定的全部状态。

### Direct writer 与 rollback

区分成立。direct writer 尝试 latch=1，逐节点写 raw 并 readback；其 programming-error tail 只做 host plan cleanup，没有保存旧 raw 值、没有调用 resense、没有 `0x404f0000`、没有成功尾 reset。resense 则尝试 latch=0 并在特定分支请求 coupling-selected reset，但没有旧 raw 值恢复动作。两者既不是同一调用尾，也不是 commit/rollback 对。

“已检查 host failure path 没有 rollback”可保持 **PROVED（path-scoped）**；“FSP/hardware 不可能有隐藏恢复”必须保持 **UNKNOWN**。主报告在这个外推边界上正确。

## 终稿接受条件

不需要任何新增 live 操作；只需：

1. 把第 28 行日志改成 privilege-level violation 的实际字符串。
2. 给 resense reset 加上 preparation 成功且非 pre-silicon 的条件，并把 type-6 条件写成 mapper 观察值，不归因于本次 attempt。
3. 给首次无参数 task-2 send 加上正常 FSP/`SkipFspFs=0` 路径限定。
4. 上述修正合入后再把头部 `Status: in progress` 改为终稿状态。

除此之外，本次有限范围复核没有发现 host gate、ordinary mismatch continuation、preparation/programming error-tail 区分、reset priority、recovery second-reset、PRC executor 顺序、task2-before-apply，或 `d0/dc` strong inference / `f8` UNKNOWN 的反证。

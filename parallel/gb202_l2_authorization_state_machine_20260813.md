# GB202 L2 授权/提交状态机：当前已证边界（2026-08-13）

## 结论

当前失败发生在 **reset/采样之前**：FSP task 2 成功把
`0x8200d0/0x8200dc` 从 `...b8f` 改成 `...bff`，但独立的 latch PLM
`0x8200f8` 仍是 `...b8f`；普通 host 写 `0x820040.bit0=1` 不落位，随后 raw A
`0x8234e0=0x10` 也立即读回原值 `0x12`。因此尚未到 post-program reset，更没有
到 effective B (`0x822900+4*FBP`) adoption。

这组事实不能推出“缺 HULK”。HULK 是可能的安全固件路径，但当前没有证据证明
它对 GB202 L2 是必要条件或充分条件。

## 候选状态机

| 阶段 | 已见 actor / gate | 当前判定 |
|---|---|---|
| 0 | 可选 PRC object `0x1d = FLOORSWEEPING_ALLOW_INB_ONE_SHOT`：read，必要时 active write，再 immediate readback | host 顺序 **PROVED**；值域、消费、自清 **UNKNOWN** |
| 1 | QCAP `0x13` presence；发送 FSP task 2/subobject 1；同步等待 command status | **PROVED**；不是 credential 或 PLM snapshot |
| 2 | task2 status 0 后 `d0/dc: ...b8f -> ...bff`，`f8` 不变 | retail GB202 runtime **PROVED** |
| 3 | `ProgramSwFusePlan` 要求 process-local `SecurityUnlockLevel > 3` | **PROVED host gate**；不是硬件授权 |
| 4 | 先通过 RegHal constant `0x404f0001` 尝试设置 `0x820040.bit0`；返回值被忽略 | **PROVED** |
| 5 | 逐个写 raw A，立即读回比较；普通 equality 是唯一 host-visible acceptance gate | **PROVED** |
| 6 | mismatch 记录错误；失败尾声没有 reset、rollback 或 latch clear；全成功才进 reset/reinit | **PROVED** |
| 7 | reset 后 A 如何成为 effective B | actor、采样边和最终 compare 均 **UNKNOWN** |

## 为什么 `f8` 是当前最强可见阻断点

公开/静态闭合的普通 L0/source0 RMW 条件为：

```text
bit0 & bit4 & (!bit10 | bit12) & (!bit11 | bit12)
```

`0xfffffb8f` 的 `bit4=0`，所以普通 L0 latch write 不满足许可；task2 后
`0x8200f8` 仍为该值。相比之下 `0x8200dc=0xfffffbff` 已打开全部低四级 write
bits，但 raw 写仍不落位。最小解释是：raw shadow 除自身 `dc` 访问 PLM 外，还受
未能置位的 software-override latch 或等价的 firmware-mediated commit gate 约束。
这是强推断；缺少硅/FSP consumer，不能把 latch 称为所有路径的绝对必要条件。

## `0x1d` / `0x1e4` 纠正

NVIDIA 2026 Nova PRC 公开格式把 payload 头定义为
`subcmd, flags, object_id, reserved`，其中 flags bit0 是 Persistent、bit1 是
Active。因此观测请求：

```text
0d 02 1d 00  01 00 00 00
```

是对 object `0x1d` 的 **active-only** equal-current write，不是 persistent
write。FSP 返回名为 `PRC_ERROR_PERSISTENCE_NOT_SUPPORTED` 的 `0x1e4` 只能说明
该请求在当时被拒绝；不能证明缺 HULK、请求了 persistence，或全部 PRC 写都不可用。

直接源码：

- <https://patchew.org/linux/20260604114339.1565660-1-zhiw%40nvidia.com/20260604114339.1565660-5-zhiw%40nvidia.com/>
- <https://patchew.org/linux/20260604114339.1565660-1-zhiw%40nvidia.com/20260604114339.1565660-6-zhiw%40nvidia.com/>

## HULK 边界

- 本次 task2 run 没有发送或激活 HULK，仍完成 `d0/dc` 权限变化；但不能排除卡上
  预先存在的 fuse/InfoROM/lifecycle/boot policy。
- MODS 的 `%s register is PRIV protected. Please acquire HULK license.` helper
  只在已闭合的 HBM IEEE1500/repair caller 中检查 `0xbadf` 并打印诊断；它不检查
  `0x8200f8`、PRC `0x1d` 或 L2 plan。
- 历史 HULK 证明签名对象可以携带寄存器 RMW，但六个公开样本既不允许
  device `0x2b85`，也不含 `0x8200f8/0x820040/0x8234e0`。
- NVIDIA 当前公开的 NSMD 还证明存在一条**不同的**相邻授权路径：GPU
  `HardwareUnlock` Debug Token 的 `PrcKnobEn` subtype bit 是 `0x00001000`；同表
  另列 `NvlinkGlobalHulk` 和 `PxucGlobalHulk`。与此同时，NSM reconfiguration
  permission index `16` 叫 `HULKLicenseUpdate`，只描述是否允许 in-band 更新
  HULK license。前者说明“PRC knob 权限可能来自非 HULK token”是具体候选，不再
  只是抽象可能性；后者是更新许可 gate，不是 HULK 内容，也不能推出 L2 权限。
  两套 ABI 都未把 `PrcKnobEn` 或 `HULKLicenseUpdate` 映射到 `f8`/latch/raw A。

## 下一项真正有判别力的证据

取得以下任一项才可继续提升结论：

1. GB202 FSP 对 `0x1d/task2/f8` 的明文 consumer/schema；
2. 明确覆盖 `0x8200f8/0x820040/0x8234e0` 且绑定 `0x2b85` 的签名授权对象；
3. 原厂完整日志展示 `f8 open -> latch sticks -> raw A readback -> reset edge -> B adoption`。

在此之前，不能把 HULK、PRC `0x1d`、`disable_sw_override` 或某一种 reset 单独宣布
为充分条件。

## 固定证据

| 文件 | SHA-256 |
|---|---|
| `vm_mods_lab/fsp_task2_zero_result_20260722.md` | `990eddbffd1d931596c3eb85fffac468bd04e7e9014ac4695be3631c0c2761b3` |
| `parallel/l2_plm_static_permissions.md` | `159590f9c163c88d15805ccd81c1e04a90c9af2180468be975ef0760427c7b8d` |
| `parallel/task2_lifecycle_audit.md` | `45dff857f5d24b23df132316dd2555149fc21fc3508d5d9bc189af9c6b06d65a` |
| `parallel/raw_effective_propagation.md` | `60bf2a6798db1b3f7ffddcc79f55c147cb753c415eef7fc5a9b412898be7f0f4` |
| `parallel/l2_mask_constraint_audit.md` | `2c4489c6c950fe231294a15516a9e3d6d8314836589acef18d7fd803bc9c6502` |
| `parallel/disable_sw_override_lifecycle.md` | `3058ad6f45d975fcb0cc1d7510ea36b9b0be20acdfbaebaaa87a7234004801cc` |
| `parallel/tmux_mods_permissions.md` | `0cc71bc8ea02075627ca2cb60a92fa5c2b4ed6379493dbaff167f4ce336d20f7` |
| `parallel/reghal_writer_transport.md` | `aa825c6e99d4a9f39177c18fdf804c4d27672064c433f21bc256471f70560530` |
| `parallel/mods_hulk_priv_message_xref_20260813.md` | `f5f59b03db55f14627f828abe210bb253cffbbb305e924ee92ad0cc5d0adb902` |
| `parallel/debugtoken_prc_candidate_20260813.md` | `52a41ee32eedfa854ac1a23c1f996bbfda9588750fdf1e82e4c6f8cdf5ea9b69` |
| `parallel/prc_knob_en_mask_generation_20260813.md` | `48a9d114fe20ea783c6feb0cffb6f1ab507c1bea3102b1a631a0962a007bf2c1` |

本报告只整合已归档静态证据和既有隔离 VM 运行记录；本轮没有执行 GPU、MMIO、
FSP、MODS、固件、reset 或 flash 操作。

# RTX 5090D SM issue-throttle 静态逆向结论 — 2026-09-23

## 结论先行

本轮出现了比 `OverrideIssueRate()` 更贴合实测现象的新证据：NVIDIA R580 以后公开 RM 头文件明确暴露了一套独立的 **SM issue throttle** 熔丝查询接口；到云端实测所用的 R595.71.05，接口恰好有两项：

```c
NV2080_CTRL_GR_SM_ISSUE_THROTTLE_CTRL_MASK   = 0
NV2080_CTRL_GR_SM_ISSUE_THROTTLE_CTRL_CREDIT = 1
```

文档明确把返回内容称为 **fuse values**，并说明它是“various instruction types”的 throttle control。CPU-RM 在初始化每个 GR engine 时，通过内部 control 从 GSP/RM 侧取得这些值、缓存在 `KGRAPHICS_STATIC_INFO`，再由只读公共 control 返回。

因此目前最强机制候选应从泛化的“issue-rate/speed-select”进一步收窄为：

```text
SKU / fuse identity
  -> per-GR SM issue-throttle MASK + CREDIT
  -> GSP 提供静态配置，CPU-RM 缓存
  -> GR/SM 硬件按被 mask 选中的指令类别执行 credit 限流
```

这与实测的两个关键特征高度吻合：

1. **选择性**：同一进程、同一功耗条件下，部分 QMMA/累加模式受限，另一些接近完整 5090；`MASK` 很自然地承担“哪些 issue 类别受限”。
2. **并发边界**：1–170 CTA 基本满速，超过约一 CTA/SM 后第二批并发容量被截断；`CREDIT` 比单纯每条指令固定除速更贴合这种“第一批容量保留、额外并发额度受限”的形状。

这仍不是最终证明：尚未取得 2B87 与 2B85 的 `MASK/CREDIT` 实值对照，也未解出 mask 位到 Blackwell `QMMA.16832.F16.E4M3.E4M3` 的映射和 credit 单位。但在现有证据中，它已比普通 VBIOS 功耗表、应用名检测或单纯 scalar issue-rate divisor 更接近观测。

本轮保持静态分析：没有运行 MODS，没有提交 SET control，没有读写 MMIO，没有刷固件，也没有运行本报告涉及的 RM control。

## 1. 公开 ABI 的版本演化

保存的源码快照位于：

```text
power_governor_reverse/sm_issue_throttle_sources/
```

逐版本差分给出清楚的演化：

| 驱动公开标签 | `GET_SM_ISSUE_THROTTLE_CTRL` | index 0 `MASK` | index 1 `CREDIT` |
|---|---:|---:|---:|
| 575.64.05 | 无 | 无 | 无 |
| 580.65.06 | 有 | 有 | 无 |
| 590.48.01 | 有 | 有 | 无 |
| **595.71.05** | **有** | **有** | **有** |
| 610.57.04 | 有 | 有 | 有 |

关键差分：

- `ctrl2080gr-575.64.05_to_580.65.06.diff`：首次加入 `MASK` 和 control `0x2080123d`；
- `ctrl2080gr-590.48.01_to_595.71.05.diff`：加入 `CREDIT`。

R580 初始定义原文包括：

```c
#define NV2080_CTRL_GR_SM_ISSUE_THROTTLE_CTRL_MAX_LIST_SIZE (0xFFU)
#define NV2080_CTRL_GR_SM_ISSUE_THROTTLE_CTRL_MASK          (0x0U)

/*
 * This command provides an interface to retrieve the throttle control values of
 * various instruction types for a GR engine.
 * ...
 * When caller passes smIssueThrottleCtrlListSize = 0, all fuse
 * values are returned.
 */
#define NV2080_CTRL_CMD_GR_GET_SM_ISSUE_THROTTLE_CTRL 0x2080123dU
```

R595 在同一列表加入：

```c
#define NV2080_CTRL_GR_SM_ISSUE_THROTTLE_CTRL_CREDIT (0x1U)
```

这很重要，因为云端 5090D 的驱动/GSP 正是 `595.71.05`：不是拿 R610 的新符号倒推一个旧驱动不存在的功能；R595.71.05 自身公开头文件已经同时定义 `MASK` 和 `CREDIT`。

## 2. 与普通 issue-rate modifier 是两套独立控制面

同一头文件把两套接口并列定义：

```text
0x2080123c  GET_SM_ISSUE_RATE_MODIFIER_V2
0x2080123d  GET_SM_ISSUE_THROTTLE_CTRL
```

前者的公开 index 是：

```text
FMLA16, DP, FMLA32, FFMA, IMLA0..4, FP16, FP32, DFMA, DMLA
```

后者的 index 则只有：

```text
MASK, CREDIT
```

所以不能再把两者合并成一个模糊的“issue-rate 开关”：

- **issue-rate modifier / speed select**：按执行单元或指令族给固定速率除数；本地 MODS 的 `OverrideIssueRate()` 与它对应。
- **issue-throttle control**：由 mask 选择受控 issue 类别，再用 credit 控制节流资源；它在命名和数据形状上更像并发/仲裁额度。

本地 MODS 570.215 的现有逆向仍然有价值，但其年代早于该公共 ABI 的 R580/R595 暴露：

- MODS 明确存在 `OverrideIssueRate()` 与 `-override_issue_rate`；
- 可见单元名主要是 FMLA/FFMA/IMLA；
- 未找到 `MASK/CREDIT` 的明文名字；
- 这不否定硬件已有 throttle 控制，只说明 R570 MODS 符号面不足以独立命名这条后来公开的接口。

因此此前将 `OverrideIssueRate` 视为最强候选需要降一级：它可能是相邻或兼容的 speed-select 路径，但**不能自然解释一 CTA/SM 后才出现的大幅差异**；`MASK+CREDIT` 更符合该形状。

## 3. CPU-RM / GSP 数据流

R610.57.04 开源 RM（与 R595 相同 ABI）给出了完整只读数据流。

### 3.1 初始化时从 GSP 获取

`kernel_graphics.c::kgraphicsLoadStaticInfo_KERNEL()` 依次请求：

```text
SM Issue Rate Modifier
SM Issue Rate Modifier V2
SM Issue Throttle Control
```

第三项使用内部 control：

```c
NV2080_CTRL_CMD_INTERNAL_STATIC_KGR_GET_SM_ISSUE_THROTTLE_CTRL
    = 0x20800b05
```

成功后将当前 `grIdx` 的返回结构复制到：

```c
pPrivate->staticInfo.pSmIssueThrottleCtrl
```

这说明该值不是应用启动时临时由 CUDA 用户态策略生成，而是 GR static-info 初始化的一部分。

### 3.2 对外只读查询

公共 control：

```c
NV2080_CTRL_CMD_GR_GET_SM_ISSUE_THROTTLE_CTRL = 0x2080123d
```

其 handler：

1. 选定目标 GR engine；
2. 要求 `pStaticInfo->pSmIssueThrottleCtrl != NULL`；
3. 调用者传 size=0 时返回全部有效 index；
4. 从缓存列表返回每个 index 的 data。

生成的 NVOC method table 给该公共方法 `accessRight=0`，公开头文件只有 GET，没有对应 SET。这并不证明硬件值永不可改；它只证明正常 RM ABI 把这里暴露为熔丝/静态信息查询，而不是普通用户可写参数。

### 3.3 GSP 610.57.04 二进制交叉检查

固定对象：

```text
wrapper SHA-256: c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999
inner ELF SHA-256: 88cb25e9940d9b242a8dc518291d028519b1f7b734954c6d358112b4af0a690e
Ghidra project: /home/user/rt_5090_project/ghidra_static/gb202_gsp61057.gpr
```

主 ELF 中只有一个公共命令常量和一个内部命令常量命中：

```text
VA 0x01c1bea0: cmd 0x2080123d, params 0x07fc, handler 0x0145ab68
VA 0x01c1b580: cmd 0x20800b05, params 0x3fe0, handler 0x018b9a38
```

尺寸也与头文件精确一致：

```text
公共：4 + 255 * 8 = 0x07fc
内部：8 个 GR engine * 0x07fc = 0x3fe0
```

`0x0145ab68` 的精确指令清单显示它取得当前 KernelGraphics 对象，然后以列表 size 和首个请求 index 尾调用对象内的 HAL 槽 `+0x10d8`。这把 `0x2080123d` 从“仅有头文件声明”推进到了实际签名 GSP 主 ELF 中的命令描述符和 dispatcher。

但不应继续过度命名下游：当前 stripped GSP 的大型 HAL 初始化器边界不可靠，`0x018b9a38` 的初步反编译与公开结构语义不够一致，尚不能把某个物理寄存器地址或函数名定案。已保存原始清单、反编译和 SHA-256 manifest，避免把暂定 Ghidra 名称冒充 NVIDIA 符号。

## 4. 与 5090D 实测的对应关系

实测不是“每个 SM 的 QMMA 永久按固定比例减速”：

```text
170 CTA: 5090D 555 T, 5090 571 T
340 CTA: 5090D 563 T, 5090 1028 T
```

同一 `QMMA.16832.F16.E4M3.E4M3`、同一二进制、非零 FP8 操作数下也复现。最小解释需要同时具备：

- 指令/模式选择；
- 跨 SM 或跨并发 wave 的额度/仲裁限制；
- 第一批约一 CTA/SM 基本不受损。

`MASK + CREDIT` 恰好提供了这种最小控制形状。它比以下解释更吻合：

| 候选 | 与现有证据的匹配度 | 原因 |
|---|---|---|
| SM issue-throttle fuse `MASK+CREDIT`，GSP/RM 配置，硬件执行 | **最高** | 名字、熔丝属性、模式选择和并发额度同时匹配 |
| 普通 issue-rate/speed-select divisor | 中 | 能解释指令选择，但固定除速较难解释 1 CTA/SM 前后断点 |
| SKU fuse 直接硬连线到调度器 | 中高 | 仍可能是最终物理来源，但公开数据流显示 GSP/RM明确搬运 throttle fuse 值 |
| VBIOS 普通功率/频率表 | 低 | 低功耗、正常时钟、模式选择和 CTA 边界均不吻合 |
| CUDA 应用名/进程名检测 | 很低 | 同一进程、同一 CUBIN 内出现模式和 grid 选择性 |

更精确的表述是：**“软配置，硬执行”现在有了一个具名候选控制面**。SKU/fuse 提供 `MASK/CREDIT`，GSP 在 GR 初始化时传递/配置，实际发放或拒绝 Tensor issue credit 的动作发生在 GR/SM 硬件中。

## 5. HULK / Debug Token 的边界

`nvflash` 中的 HardwareUnlock 特征 `sm_speed_select_throttle` 仍与该领域相关，但目前不能推导出：

```text
有该 feature token => 可以清除 issue-throttle MASK/CREDIT
```

原因：

- 名称直接对应 speed-select throttle，可能只授权 MODS 的 issue-rate override；
- 新发现的 `MASK/CREDIT` 是另一套 control ID；
- 本地材料没有将该 HULK feature bit 连到 `0x2080123d/0x20800b05`；
- MODS 只能加载已有签名 token，不能生成或签发 token。

因此不能宣称 Debug Token 足以解锁 5090D，也不应尝试盲写寄存器、跨刷 VBIOS或伪造授权对象。

## 6. 尚未证明的项目

当前仍未知：

1. 2B87 和 2B85 实际返回的 `MASK` 与 `CREDIT` 数值；
2. `MASK` 中哪一位对应 FP8→FP16 QMMA、FP16→FP16、INT8 或 block-scaled 路径；
3. `CREDIT` 的单位是每 SM、每 GPC、每 TPC、每分区还是芯片级 token；
4. 熔丝值是否直接驱动寄存器，还是由 GSP 转换为另一个 privileged scheduler 参数；
5. 物理 fuse field / RegHal ID / BAR0 地址；
6. `sm_speed_select_throttle` token 是否覆盖这套独立的 MASK/CREDIT 控制；
7. 该机制是否正是为出口合规设计。接口和测量可以证明技术相关性，不能单独证明法律分类或设计动机。

## 7. 最小后续验证

在不写硬件的前提下，最有信息量的下一步不是继续猜 VBIOS 表，而是对两 SKU 执行同一只读 GET：

```text
NV2080_CTRL_CMD_GR_GET_SM_ISSUE_THROTTLE_CTRL (0x2080123d)
```

分别记录：

```text
list size
index 0 / MASK data
index 1 / CREDIT data
RM status
GPU PCI ID、VBIOS、driver/GSP 版本
```

理想设计是 2B85/2B87 在同一 R595 或 R610 驱动上比较。若 2B87 的 mask/credit 与 2B85 不同，并与 native-QMMA sweep 同机对应，这将是当前最短的因果闭环。该 GET 是只读公开 control，但本轮为遵守静态审计范围，**没有运行它**。

## 8. 证据文件

源码快照与差分：

```text
power_governor_reverse/sm_issue_throttle_sources/
```

GSP 静态产物：

```text
power_governor_reverse/gsp61057_sm_issue_throttle_handlers_20260923.c
power_governor_reverse/gsp61057_public_throttle_listing_20260923.txt
power_governor_reverse/gsp61057_slot10d8_targets_20260923.c
power_governor_reverse/gsp61057_split10d8_functions_20260923.c
power_governor_reverse/gsp61057_sm_issue_artifacts_20260923.sha256
```

本地 MODS issue-rate 逆向：

```text
power_governor_reverse/mods570215_issue_rate_blackwell_20260923.c
power_governor_reverse/mods570215_issue_rate_blackwell_rebuilt_20260923.c
```

实测报告：

```text
nr_runtime_next/reviews/rtx5090d-live-20260923/REPORT.md
```

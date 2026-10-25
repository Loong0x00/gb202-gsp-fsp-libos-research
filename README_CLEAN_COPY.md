# GSP / FSP / LibOS 研究资料库（clean copy）

> 本目录是 `/home/user/rt_5090_project` 的**只读资料副本**，用于文档分类、去重与结论规范。
> 原始项目未被修改。本目录内的原始文档也**未被修改、移动或删除**；所有整理产物都是新增文件。
> 生成日期：2026-10-18。

## 1. 这是什么

一套围绕 NVIDIA RTX 5090（GB202）的三条研究线：

1. **QEMU 模拟器支线**：用主线 QEMU 执行生产 FMC/LibOS，恢复 GSP 启动链；
2. **真机 GSP 支线**：GSP-RM 消息队列溢出、回调劫持、对象生命周期与提权链；
3. **FSP / 时钟 / 电压支线**：FSP 信任链与通道、PRC/MNOC、MCLK/XBAR 运行时控制。

库内共 **230 份原始 `.md`**（另有固件、反汇编、Ghidra 工程、厂商源码树，未计入）。全部登记在 `docs/INDEX.md`。

## 2. 先读什么

| 你的目的 | 阅读顺序 |
|---|---|
| 5 分钟了解现状 | `AUTHORITATIVE_STATUS.md` → `STATUS.md` → `FINDINGS.md` §A/§B |
| 接手继续做 | `STATUS.md` → `OPEN_QUESTIONS.md` §5 → `NEXT_STEPS.md` |
| 查某个结论是否可信 | `FINDINGS.md`（看 E 级别）→ `CORRECTIONS.md`（是否被更正）→ 原始 `file:line` |
| 写对外材料 | `STATUS.md` §5/§8 → `FINDINGS.md` §J（引用限定）→ `CORRECTIONS.md` |
| 了解文档为什么这样整理 | `docs/INDEX.md` → `docs/DEDUP_PLAN.md` → `docs/EVIDENCE.md` |
| 找旧文档 | `docs/ARCHIVE_INDEX.md`（原件仍在原路径，`docs/archive/` 只是副本） |

## 3. 目录结构

```text
gsp_libos_clean/
├── README.md               ← 本文件：入口、结构、规则
├── AUTHORITATIVE_STATUS.md ← **唯一权威总览**（GSP/LibOS + 模拟器 + 工具/脚本 + 坑）
├── STATUS.md               ← 一页现状（短版）
├── FINDINGS.md             ← 结论库（77 条，每条带 E0–E6 / file:line / 日期 / 置信度）
├── OPEN_QUESTIONS.md       ← 未决问题 + 最小复现实验（18 条，2 条已静态关闭）
├── NEXT_STEPS.md           ← 真机 / QEMU / 静态 三线优先级
├── CORRECTIONS.md          ← 旧文档:行 → 更正后表述 → 依据（18 条）
├── AGENTS.md               ← 项目约定（原件，未改）
├── COPY_MANIFEST.md        ← 拷贝范围说明（原件）
├── docs/
│   ├── INDEX.md            ← 230 份原始 .md 的逐条登记
│   ├── DEDUP_PLAN.md       ← 重复组、冲突点、混写审查、归档建议
│   ├── EVIDENCE.md         ← E0–E6 定义与引用格式（唯一权威）
│   ├── ARCHIVE_INDEX.md    ← 被取代文档：原路径 / 副本路径 / 取代者 / 哈希
│   └── archive/            ← 54 份旧文档的**副本**（原件仍在原位）
├── gsp_qemu/               ← QEMU 主线（活文档 + 源码 + 固件 + 脚本）
├── gspkm/                  ← NVIDIA open kernel modules 610.57.04（vendor）
├── driver_gpio_internal_610.43.03/  ← 610.43.03 + GPIO patch（vendor）
├── fsp_ace_static_20260927/← FSP 静态战役报告
├── fsp_code/               ← FSP 相关明文代码摘录
├── power_governor_reverse/ ← GSP 时钟/功耗逆向（静态为主）
├── vm_mods_lab/            ← 隔离 VM / VFIO 实验记录
├── vfio_production_lab/    ← 生产 VFIO lab 说明
├── ghidra_static/          ← Ghidra 工程（.rep，勿当文本扫描）
└── （根目录其余）           ← 230 份原始研究文档（按时间/主题命名）
```

## 4. 证据分级（摘要）

完整定义见 `docs/EVIDENCE.md`。

| 级别 | 含义 | 能支撑 | 不能支撑 |
|---|---|---|---|
| E0 | 真机裸机 | 硬件/固件行为、时序、恢复 | 芯片内部结构、跨版本 |
| E1 | 真机直通 VM | 同上，需注明 VM | 宿主特有路径 |
| E2 | 静态（固件/源码/VBIOS） | 代码路径、字段、常量 | 运行时取值、是否执行 |
| E3 | QEMU lab | 本 profile 的执行流 | 真机地址/可达性/认证链 |
| E4 | 旧 Python 模拟器（`rv64_emu.py`） | 指令语义 | 真机可达性（已降级为历史） |
| E5 | 二手综合 | 索引、时间线、待办 | 一手事实 |
| E6 | 公开/第三方 | 公开基线、外部案例 | 本项目硬件行为 |

**引用格式**：`path:line` 或 `path:start-end`，相对本目录；归档副本不作为引用源。

## 5. 三条硬规则

1. **模拟器结论不得写成真机结论。** QEMU/`rv64_emu` 的结果必须标 E3/E4 并注明“受控实验/本 profile”。
2. **真机与模拟器冲突时拆成两条 claim，不合并。** 典型：t0=4 fast path 的 lab 语义（E3）与真机 U-mode 可达性（未证）。
3. **后续文档只是“声称”而没有证据时，标 unresolved。** 只有“后续 + 证据”才能进 `CORRECTIONS.md` 的“已裁决”。

## 6. 维护规则

- **不改原件。** 发现旧文档错误 → 追加到 `CORRECTIONS.md`（旧文档:行 → 更正 → 依据），而不是编辑原文。
- **新结论 → `FINDINGS.md`**，分配新 ID（区段前缀 + 序号），必须带 E 级别、`file:line`、日期、置信度。
- **未决 → `OPEN_QUESTIONS.md`**，附最小复现实验（命令 + 预期输出 + 判据）。
- **归档 = 复制。** 只把副本放入 `docs/archive/<topic>/<原相对路径>`，原件保持原位；在 `docs/ARCHIVE_INDEX.md` 登记哈希与取代者。
- **地址必须带版本**：凡出现 `0x9300xxxx`/`0x1a8xxxx` 这类 VA，必须写清固件版本（610.57.04 / 615.71.09 / MODS 570.215）。
- **不新增“A 级/实锤/已证明”这类自评词**，只写证据级别与置信度。

## 7. QEMU 使用提示

```sh
cd gsp_qemu
make build          # 独立构建，不覆盖系统 QEMU
make test           # 包验证 / ISA / MPU / 原始内核 / lab 回归
make test-lab       # 签名 FMC + 原始 LibOS → walk 表检查点
make probe-kernel   # 原始 boot 自然进入 init，记录下一处缺项
```

注意：`gsp_qemu/README.md` 与 `docs/LAB_BOOT.md` 中的 `cd /home/user/rt_5090_project/...` 是拷贝前的旧路径，在本副本中应改为 `/home/user/gsp_libos_clean/...`（见 `CORRECTIONS.md` C-13）。

## 8. 已知的文档陷阱

| 陷阱 | 说明 | 处理 |
|---|---|---|
| “真机/硅晶验证” | 多数其实是直通 VM（E1），少数是宿主直跑（E0） | 引用时标 E0/E1 |
| “真内核” | 指真机固件里的 `kernel_gb20x.elf`，仍由模拟器执行 | 标 E4 |
| “A 级/实锤” | 作者自评 | 忽略，改看 E 级别 |
| 同名不同物 | `C2_ENTRY_AUDIT_20260926.md` 是 10-11 的残片 | 见 `CORRECTIONS.md` / `docs/INDEX.md` |
| 版本串味 | 615.71 的 VA 被当作 610.57 使用 | 地址必须带版本（OQ-16） |
| 旧路径 | 49 份文档引用 `rt_5090_project` | 只修命令类，历史路径保留 |

## 9. 边界与安全

- 本库只做**防御性研究**记录；`AGENTS.md` 的约定仍然有效：不伪造启动成功、不改原厂固件、不把子系统进展冒充完整启动成功。
- 真机实验前先确认卡状态与恢复路径（WPR2 死锁需 SBR/断电，见 `FINDINGS.md` REC-02/REC-03）。
- 破坏性实验（ELF 注入、FSP 写、flash 操作）必须先有 arm/disarm 与回滚方案，见 `NEXT_STEPS.md` §5。

## 10. 来源

- 数据来源：`/home/user/rt_5090_project`（未修改），拷贝范围见 `COPY_MANIFEST.md`。
- 厂商源码：`gspkm/`、`driver_gpio_internal_610.43.03/`，版权与许可见各自 `COPYING`/`README.md`。
- Ghidra 工程：`ghidra_static/*.rep`，仅作为二进制分析产物，不应按文本扫描。

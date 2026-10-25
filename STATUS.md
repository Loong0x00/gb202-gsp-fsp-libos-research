# STATUS — 当前真实状态（一页）

> **总览/唯一权威**：`AUTHORITATIVE_STATUS.md`。本页是短版；细节以其为准。

> 更新：2026-10-19（QEMU 支线：init 参数 blob 契约已实测——`0x93005550` 语义、blob 入口全零、生产布局 a1/a3/a7；fixture 实现被 QEMU 11.1.2 iotlb dispatch 异常阻塞）。本页只写**有证据支撑的现状**；每条可追到 `FINDINGS.md` 的 ID。
> 未证明的假设、未裁决的冲突进 `OPEN_QUESTIONS.md`；旧文档的更正见 `CORRECTIONS.md`。

## 1. 一句话

**QEMU 模拟器支线：生产 LibOS 已能自然 boot 到 init、穿过 384B 启动区域表并发布 walk 表（E3），完整 FSP/FMC/LibOS/GSP-RM 链未完成。真机支线：溢出 + 回调劫持 + 读写原语已成立（E1），但“U-mode 可达的提权链”仍未闭合。FSP 线：信任链与通道行为有大量 E0 结论，但永久 DoS 的因果未最小化。**

## 2. 三条线

| 线 | 当前到哪 | 证据 | 关键缺口 |
|---|---|---|---|
| **QEMU / 启动链** | 生产 FMC 包签名验证（宿主侧）；原始 LibOS boot→init `pc=0xffffffff93001ec6`；384B 区域表生产者实测 + 审计分支 `handoff=fixture` 通过该检查点（`0x93002052`）；**init 参数 blob 契约实测**：`0x93005550` 语义破解、blob 入口**全零**、a7=内核数据段 backing（生产布局 `FB+0x8001000` 起 data+blob 连续）；lab profile 执行到 `0xffffffff93007324` 并发布 walk 表 `0x800000000803a000` | E3（Q-01…Q-04、Q-10…Q-18） | **QEMU 11.1.2 iotlb dispatch 阻塞（Q-18，P0）**：fixture 无法按生产布局把 data/blob 放 FB；内核日志窗口；RM 任务启动；完整认证链 |
| **真机 GSP** | RPC 队列溢出、B8 回调劫持（S-mode）、读原语、清零原语、三明治 walk(2) 触发；K3-1 泄漏读可用 | E1（GSP-01…GSP-13） | t0=4 真机可达性；非零写；t0=2 表位置；K3-1 精确利用 |
| **FSP** | COT 95% 字段被忽略、WPR 签名真实、COT runtime 静默丢弃、47 个 PRC knob、MNOC p0 协议闭合；畸形序列后 runtime 服务持续不可用 | E0（FSP-01…FSP-13） | 最小触发；设备侧首因；FSP 代码加密不可静态读 |
| **时钟/电压** | 显存锁频 −16.43% FPS；有限 MCLK 上限静默约束 XBAR/SYS（最高 ~32%）；XBAR 独立时钟域；生产驱动可同锁 GPC/NVVDD | E0+E2（CLK-01…CLK-12） | MCLK +4000 的 completion 首因；MCLK_MAX 角色 |
| **恢复/取证** | 卡已复活（WPR2 bypass）；Power cycle ≠ SBR；双槽失败 ≠ 双 flash 损坏；原版槽最后健康点 2026-09-28T12:32Z | E0/E5（REC-01…REC-05） | 槽位归属；FSP runtime 恢复 |

## 3. 卡与环境

- 目标卡：ASUS RTX 5090 Astral（GB202，`10de:2b85 / 1043:89e3`），双 BIOS（XOC / 原版）。
- 最近记录的可工作状态：`REVIVAL_FINAL.md:3-8`（宿主直跑，`nvidia-smi`/CUDA 正常，WPR2-bypass 一行补丁）。
- 驱动/固件版本必须逐条标注：**610.57.04**（GSP/QEMU 主线）、**615.71.09**（K3-1/原版槽观察）、**MODS 570.215**（MCLK 故障）。三者地址不可互套（`CORRECTIONS.md` C-12 类问题）。
- 实验环境：GSP 主线多为**直通 VM（E1）**；FSP/时钟多为宿主直跑（E0）；QEMU 为纯 TCG（E3）。逐条环境仍待补（OQ-17）。

## 4. 对外投稿

- 两封 PSIRT 邮件已于 2026-10-13 发出（`SUBMISSION_RECORD_20261013.md:3-12`，E5）。
- 稿 1 的措辞是“畸形序列后 runtime 服务持续不可用”，**不是**“单条 ROMREAD 即永久 DoS”（`PSIRT_DRAFT_1:5`）。
- 稿 2 明确不主张双 flash 同时损坏（`PSIRT_DRAFT_2:211`）。

## 5. 最关键的“未证明”（写材料时必须带）

1. **t0=4 fast path 不是 U-mode 路径**：lab 受控入口，U-mode 可达性未证明（`CORRECTIONS.md` C-01；`FINDINGS.md` Q-05/Q-06）。
2. **C1/C2 仅在旧 Python 模拟器 + 真实内核镜像上闭合**（E4），真机未验证（`CORRECTIONS.md` C-10）。
3. **lab 与 handoff profile 的地址不是真机地址**：`0x800000000803a000`、`0x8000000000800000` 只属 QEMU profile（`FINDINGS.md` Q-04、Q-11、Q-13）。
4. **FSP 永久 DoS 的触发未最小化**（`FINDINGS.md` FSP-08）。
5. **GSP TOCTOU 只证明“写入到达内存”，未证明“执行”**（`FINDINGS.md` TOC-03/TOC-04）。

## 6. 可复现命令（当前基线）

```sh
# QEMU 支线（E3）
cd gsp_qemu
make test-lab            # 签名 FMC + 原始 LibOS → walk 表检查点
make test-lab-fastpath   # 受控 t0=4：state 0→1、ref 不变（不是 U-mode trap）
make test-lab-statecond  # slow handler 的 state/ref 条件
make test-lab-destroy    # 直接调 0x93005b26 → dtor（不是 U-mode 可达路径）
make probe-kernel        # 原始 boot → init → 区域表接受，记录下一处缺项
make probe-lab-table     # 原始 SBI server 生成的 384B 区域表 + init 解析记录

# 静态复核（E2，2026-10-18 已执行）
riscv64-linux-gnu-objdump -D -b binary -m riscv:rv64 \
  --adjust-vma=0xffffffff92fff000 firmware/kernel-610.57.04/code.bin \
  | awk '/^ffffffff93005b4[c-f]:|^ffffffff93005b5[0-9a-f]:/'
```

## 7. 文档状态

- 原始文档 **230 份 `.md` 全部保留在原路径**，未修改、未移动、未删除。
- 新增：`README.md`、`STATUS.md`（本页）、`FINDINGS.md`（77 条）、`OPEN_QUESTIONS.md`（18 条，其中 2 条已静态关闭）、`NEXT_STEPS.md`、`CORRECTIONS.md`（18 条）、`docs/EVIDENCE.md`、`docs/ARCHIVE_INDEX.md`，以及 `docs/archive/` 下的**副本**（54 份）。
- 旧文档的更正只写在 `CORRECTIONS.md`，不在原文上打补丁；归档只复制，不替代引用源。
- 第一步产物：`docs/INDEX.md`（230 份登记）、`docs/DEDUP_PLAN.md`（重复/冲突分析）。

## 8. 不要写进对外材料的说法

- “GSP 提权已完成 / 已获得 S-mode 代码执行”（真机链未闭合）。
- “t0=4 是真机 U-mode 路径”（模拟器受控入口）。
- “QEMU 已启动 GSP-RM”（只到 LibOS init + walk 表检查点）。
- “单条 ROMREAD 永久禁用 FSP”（因果未最小化）。
- “GSP TOCTOU 绕过签名验证”（只证明写入到达内存）。
- “C1/C2 已在真机证明”（E4）。

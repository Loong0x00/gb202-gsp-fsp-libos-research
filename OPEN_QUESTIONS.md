# OPEN_QUESTIONS — 未决问题与待重跑实验

> 更新：2026-10-18。共 **18** 条编号（OQ-01…OQ-18）：**16 条未决 + 2 条已静态关闭**（OQ-02、OQ-03，记录在 §3 以便复核）；另有子项 **OQ-02R**（P3）。
> 规则：**能静态裁决的先静态**；必须动态的给出 lab 命令与预期输出；不猜。
> 每条 = 问题 / 已知 / 缺口 / 最小实验 / 判据 / 优先级（P0 阻断当前主线，P3 仅文档）。

命令默认工作目录：`/home/user/gsp_libos_clean`。QEMU 相关命令需先 `cd gsp_qemu`；真机实验一律先确认卡状态（`nvidia-smi`）并遵守 `AGENTS.md` 的“不伪造启动成功、不改原厂固件”。

---

## 0. 冲突裁决索引（来自 `docs/DEDUP_PLAN.md` §3）

| 冲突 | 当前状态 | 去向 |
|---|---|---|
| C1 t0=4 是否 U-mode 路径 | 已裁决：不是（E3 受控入口）；**真机可达性仍未知** | `CORRECTIONS.md` C-01；OQ-01 |
| C2 lab 结论与真机并列 | 已裁决：按 E0–E6 拆条 | `CORRECTIONS.md` C-02 |
| C3 dtor `+0x28` vs `+8` | 已裁决：GB20X `+8`，GB10Y `+0x28`；旧模拟器“成功”未解释 | `CORRECTIONS.md` C-03；OQ-02R |
| C4 RELEASE `0x930060f2` vs `0x93005b26` | 已裁决：GB20X `0x93005b26` | `CORRECTIONS.md` C-04 |
| C5 TOCTOU 有没有窗口 | 部分裁决：对象不同；时间线矛盾未决 | `CORRECTIONS.md` C-08；OQ-11 |
| C6 “GSP TOCTOU 成功/绕过签名” | 已裁决：只证明写入到达内存 | `CORRECTIONS.md` C-07；OQ-10 |
| C7 COT 是否按内容响应 | 已裁决：runtime 静默丢弃 | `CORRECTIONS.md` C-18 |
| C8 FSP 永久 DoS 因果 | 已裁决（措辞）；最小触发未决 | `CORRECTIONS.md` C-09；OQ-06 |
| C9 WPR2 槽位归属 | 未裁决 | OQ-12 |
| C10 MCLK 首因 / marker | 已裁决（marker `0x25728`）；设备侧首因未决 | `CORRECTIONS.md` C-06；OQ-08 |
| C11 `MCLK_MAX_CAPABILITY` | 未裁决 | OQ-13 |
| C12 版本串味（610.57/615.71/570.215） | 部分裁决（规则确立）；重定位未决 | OQ-16 |
| C13 C1/C2 “PROOF” | 已裁决：E4，仅模拟器 | `CORRECTIONS.md` C-10；OQ-09 |
| C14 CC 恢复方案 | 已裁决：v2 为准 | `CORRECTIONS.md` C-12 |
| C15 风扇环境前提 | 已裁决：按 VBIOS 分环境 | `FINDINGS.md` HW-01/HW-02 |
| C16 L2/SM 解锁可做性 | 已裁决：停止旧线 | `FINDINGS.md` HW-03 |
| C17 旧路径 | 已裁决（记录）；是否落地未决 | `CORRECTIONS.md` C-13；OQ-15 |

---

## 1. 真机主线

### OQ-01【P0】t0=4 fast path 在真机 U-mode 是否可达

- **已知**：受控 lab 实验中 `t0=4,stval=0` 进入 `0x930042f8` 只做 state 0→1、ref 不变、不调 handler（`gsp_qemu/docs/LAB_BOOT.md:606-631`）；自然 boot 未命中 t0=4（`gsp_qemu/PROGRESS.md:109`）。
- **缺口**：从未在**真机 U-mode** 下用合法 syscall 指令（`li t0,4; unimp`）对 state=0 的真实对象触发并观测 `sepc`。现有结论均为 lab 注入或静态。
- **最小实验**：
  1. lab 回归（先确认基线）：`cd gsp_qemu && make test-lab-fastpath`，预期 `LAB_FASTPATH_STATE pc=0x93004382 a0=0x17 ref=0x1 state=0x1`。
  2. 真机（E1）：用 B8 读原语读出目标对象 state/ref，确认 `state=0`；从 RM 用户态执行 `li t0,4; unimp`（或现有 syscall stub），在宿主 dmesg 记录 `sepc`/`stval`/`Xid`。
- **判据**：`sepc` 落在 `0x930042f8..0x930043a0` → 走 fast path（不触 dtor）；落在 `0x930008cc` → 进入 slow handler（推翻“仅 fast path”）；无异常且 state 变 1 → 与 lab 一致。
- **风险**：低。

### OQ-04【P0】t0=2 的 walk 查找表在真机/内核堆的哪里

- **已知**：`t0=2` walk 机制静态清楚；三明治 gadget 能触发 walk(2)（`★V5_STATUS:28,66`）；扫 60+ 地址未见负数 meta（`:14,93`）。
- **缺口**：表的运行时基址与索引规则未知；lab 地址 `0x800000000803a000` 只属 lab profile（`gsp_qemu/README.md:69`）。
- **最小实验**：真机用读原语按 `[global+0x450]` 读候选指针，再按 `entry=tbl+16*(idx+1)` 扫描；或在 lab 中 hook walk(2) 的消费者，观察它实际使用的基址。
- **判据**：找到一张 16B 步长、`meta` bit63=1 的表，且 `walk(2)` 命中同一表项。
- **风险**：中（读地址需限制在已确认可读集合内）。

### OQ-05【P0】是否存在非零写入原语

- **已知**：`B8=0x01B52246` 只能写 0（a4 恒 0）；a4/a0/a5/s4 均不可控（`★V5_STATUS:767-775`）。
- **缺口**：未穷尽 RM 空间的所有 store gadget；未尝试通过 syscall 间接触发写入。
- **最小实验（静态优先）**：对 RM 代码段扫描“同基址 load + store”序列：
  ```sh
  # RM 反汇编已存在（F1 报告使用的 rm disasm）；对新版本可先反汇编
  grep -nE "\b(sw|sd)\b" rm_disasm.txt | grep -B1 "a1" | head -50
  ```
  预期：找到/找不到 `ld X,off(a1); sw X,0(a1)` 型 gadget；记录扫描指令数与 VA。
- **判据**：存在一个 B8 可直接跳转、第二操作数来自可读内存的 store gadget。
- **风险**：静态无风险；动态验证先用 `a4=0x41` 探针。

### OQ-07【P1】K3-1 能否绕过相邻堆结构的破坏

- **已知**：K=33 写入 4096B 破坏相邻堆对象，crash 固定 `0x1b8ffbc`（`K31_FINAL_REPORT.md:5-9`）；K=32 无回调（`C2_ENTRY_AUDIT_20260926.md` 残片）。
- **缺口**：相邻堆内容未知；未尝试“写回合理 chunk header”。
- **最小实验**：E1 环境按 `C2_ENTRY_AUDIT_20260926.md` 的路径 C：先用读原语泄漏 `[0x100e8..0x10fff]` 原值，再在溢出时写回；观察是否仍 crash。
- **判据**：连续 3 次不 crash 且泵存活 → 路径 C 成立；否则记录 crash 点变化。
- **风险**：高（可能再次 WPR2 死锁，需 SBR/断电）。

### OQ-06【P1】FSP runtime 服务不可用的最小充分触发

- **已知**：一段畸形序列后 PRC/FWUP/caps/InfoROM 持续不可用（`PSIRT_DRAFT_1:34-45`）；最小触发未知（`:5`）；COT version fuzz 单独触发过 PRC handler 死亡（`WPR2_INCIDENT.md:6-7`）。
- **缺口**：从未在“干净断电 → 单步操作 → 每步复验健康”的条件下重放。
- **最小实验**：每次完整断电后只做一步（如单条截断 `0x1A` 到 MNOC p1），随后 `prc_rw r 0x13` + `nvidia-smi` + dmesg 复验；逐步累加。
- **判据**：找到“某一步之后 runtime 服务不再恢复”的最小前缀；若单步即可复现，PSIRT 稿需升级。
- **风险**：高（可能使 FSP 再次不可用，需断电/编程器）。

### OQ-08【P1】MCLK +4000 失败的设备侧首因

- **已知**：marker `0x25728` = completion wait 超时（`power_governor_reverse/mclk4000_root_hunt_20261009/notification_failure/REPORT.md:17`）；发送段无主动拒绝（`power_governor_reverse/mclk4000_root_hunt_20261009/REPORT.md:7`）；`0x256c8` 才对应 busy。
- **缺口**：为何没有正常 completion 未定位；早期“mailbox busy”说法未撤回干净。
- **最小实验（静态）**：
  ```sh
  riscv64-linux-gnu-objdump -D <gb202_r570215_runtime_pmu.elf> \
    | grep -n -B4 -A4 "205d1a2c\|25728\|256c8"
  ```
  预期：`0x205d1a2c` 位于 wait 失败分支，`0x256c8` 在另一条 busy 分支。
- **判据**：确认两条 marker 调用点不同；再决定是否需要动态复现（记录 IRQSTAT/`0x014024c4`）。
- **风险**：静态无风险。

### OQ-09【P1】C1/C2 在真机是否可触发

- **已知**：C1 双释放、C2 页头投毒→S-mode jalr 仅在 `rv64_emu.py` + GB20X 内核镜像上闭合（`KERNEL_PRIVESC_C1_C2_PROOF:21-27`）。
- **缺口**：真机从未观测到 C1 竞争窗口或 C2 的 `jalr` 落点。
- **最小实验**：E1 环境用 RPC 风暴制造 C1 窗口，B8 读原语监控 refcount；C2 用受控页头 + `t0=2` 触发，观察 `sepc` 是否等于攻击者写入值。
- **判据**：出现目标 `sepc`/`stval`；否则记录“未触发”，保留 E4 结论。
- **风险**：高。

### OQ-10【P1】GSP ELF TOCTOU 能否从“被读取”走到“被执行”

- **已知**：写 ELF 头导致 GSP 挂死，证明 100ms 时仍被读（`ELF_TOCTOU_BREAKTHROUGH.md:5-12`）；FMC 写入未证明执行（`GSP_TOCTOU_SUCCESS.md:47-55`）。
- **缺口**：未在 ELF **代码段**写入可执行 payload 并观察行为变化；无 arm/disarm 对照。
- **最小实验**：E1 环境，arm 后延迟 100ms 写 ELF 代码段一条 `ebreak`（不破坏 magic/容器头），观察 GSP 是否在对应 PC 触发异常；disarm 组应正常启动。
- **判据**：arm 组出现与该 VA 对应的 GSP 异常、disarm 组无 → 执行确认。
- **风险**：高（可能变砖，需 WPR2 bypass/编程器）。

---

## 2. QEMU 支线

### OQ-18【P0-QEMU】init 消费的 384B 启动区域表与 RM 任务启动

- **状态（2026-10-18 更新）**：**表已建模，PC 已越过**。生产者侧由原始 SBI server 实测（4 个非空项 + 9 条解析记录）；消费者契约（`(a5<<58)+a6+0x200`、16×24B、8 aperture 校验）已恢复。
- **已知**：
  - `make probe-lab-table` → `gsp_qemu/logs/lab-boot-region-table.bin`、`logs/lab-region-records.bin`（FINDINGS Q-11/Q-12）。
  - `make probe-kernel`（`handoff=fixture`）→ `BOOT_REGION_TABLE_ACCEPTED pc=0xffffffff93002052`（FINDINGS Q-13）。
  - 新 `NEXT_UNMODELED_INPUT`：handoff init 参数 blob（`line 220`），随后 panic 路径缺 `0xffffffff60000000` 日志窗口（`mcause=5/mtval=0xffffffff60050800`）。
  - trap 入口所需的 `CSR 0x5c0`（trap scratch）与 `time (0xc01)` 已建成硬件输入（FINDINGS Q-14）。
- **缺口**：init 参数 blob（`a1/a2`）与日志窗口属于 boot handoff / M-mode 服务输出，未建模；RM 任务未启动。
- **状态（2026-10-19 增补）**：init 参数 blob 的消费者契约与生产布局已实测
  （`0x93005550` 语义、blob 入口全零、a7=数据段 backing；FINDINGS Q-15/Q-16/Q-17，
  复现 `make probe-lab-init-args`）。fixture 侧实现被 QEMU 11.1.2 iotlb dispatch
  异常阻塞（Q-18）：FB/SYS 在 CPU dispatch 中解析为 unassigned。NS-Q2 剩余项见
  `NEXT_STEPS.md`。
- **最小实验**：
  ```sh
  cd gsp_qemu && make probe-kernel
  cd gsp_qemu && make probe-lab-table
  ```
- **判据**：区域表检查点已达成；下一步要看 `0x93005550` 的 init 参数解析能否在**不伪造 SBI 返回值**的前提下由真实生产者字节喂通。
- **风险**：无（纯模拟）。

### OQ-11【P2】TOCTOU 时间线矛盾（200–600ms vs <50ms）

- **已知**：`GSP_TOCTOU_SUCCESS.md:23` 声称窗口 200–600ms；`TOCTOU_FINAL_REPORT.md:32-44` 显示 FSP 处理在 50ms 内完成；`LOGICAL_INCONSISTENCIES_DEEP_ANALYSIS.md` 矛盾 #1 已指出。
- **缺口**：两组实验写入位置不同（FMC `0x10000` vs `0xF200`），从未交叉复现。
- **最小实验**：race_v3 中分别于 50/100/200/400ms 写 FMC `0xF200` 与 `0x10000`，记录 FSP counter、MBOX、GPU 状态（4×2 矩阵）。
- **判据**：`0xF200` 在 400ms 仍锁死 → 时间线矛盾成立；若均正常 → `0x10000` 是死代码。
- **风险**：中（可能 FSP 锁死）。

---

## 3. 已于 2026-10-18 静态关闭（保留命令以便复核）

### OQ-02（已关闭）dtor 偏移 `+0x28` vs `entry+8`

**结论：GB20X 为 `entry+8`；`0x28` 是 stride，不是偏移。** 反汇编证据：

```sh
cd gsp_qemu
riscv64-linux-gnu-objdump -D -b binary -m riscv:rv64 \
  --adjust-vma=0xffffffff92fff000 firmware/kernel-610.57.04/code.bin \
  | awk '/^ffffffff93005b4[c-f]:|^ffffffff93005b5[0-9a-f]:/'
```

实测输出（节选）：

```text
ffffffff93005b46:  li   a5,40                 # stride = 0x28
ffffffff93005b4c:  mul  a0,a0,a5
ffffffff93005b54:  addi a5,a5,1200            # -> 0xffffffffa300a000
ffffffff93005b5a:  ld   a5,8(a5)              # dtor at entry+8  ← 决定证据
ffffffff93005b60:  jalr a5
```

同时确认 `0x930060f2` **不是** RELEASE（该处是 `sd a0,0/8/16(a0)` 的链表初始化），RELEASE 入口是 `0x93005b26`（`beqz a0` → `ld a5,-8(a0)` → `sd a5,-8(a0)` 的 refcount 递减）。

### OQ-02R【P3】旧模拟器运行为何用 `+0x28` 也“成功”

`KERNEL_PRIVESC_C1_C2_PROOF` 的模拟器运行为何用 `+0x28` 也能得到 `jalr 0xcafec0de`，仍未解释（可能是另一镜像或“写哪读哪”巧合）。

- **最小实验**：用同一 `rv64_emu.py` 重跑 Phase B，打印 RELEASE 时的 `slot` 与 `[slot]`（分别用 `+8`/`+0x28` 计算）。
- **判据**：若 `+0x28` 处恰为攻击者写入值 → 巧合；否则说明镜像不同。

### OQ-03（已关闭）TYPECALC 基线 `0xa300a020` vs `0xa300a000`

**结论：基线为 `0xffffffffa300a000`。** 反汇编：

```sh
riscv64-linux-gnu-objdump -D -b binary -m riscv:rv64 \
  --adjust-vma=0xffffffff92fff000 firmware/kernel-610.57.04/code.bin \
  | awk '/^ffffffff9300456[0-9a-f]:|^ffffffff9300457[0-9a-f]:/'
```

```text
ffffffff93004568:  lui   a5,0xfffff
ffffffff9300456a:  and   a0,a0,a5          # 页对齐
ffffffff9300456c:  ld    a5,32(a0)         # desc = [page+0x20]
ffffffff93004572:  addi  a4,a4,-1390       # -> 0xffffffffa300a000  ← 基线
ffffffff9300457e:  sub   a5,a5,a4
ffffffff93004580:  srai  a5,a5,0x3
ffffffff93004582:  mulw  a0,a5,a0          # × [0x9300cb20]=0xCCCCCCCD
```

`KERNEL_PRIVESC_C1_C2_PROOF:18-20` 的 `a300a020` 应视为旧值/笔误（见 `CORRECTIONS.md` C-05）。

---

## 4. 文档与证据链

### OQ-12【P2】WPR2 事故的槽位归属

- **已知**：双槽同时失败不等于双 flash 损坏（`DUAL_BIOS_CROSS_SLOT_FORENSICS_20261012.md:8,102`）；原版槽最后健康点 2026-09-28T12:32Z（`ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md:10`）；PSIRT 稿 2 自注不主张双 flash 损坏（`:211`）。
- **缺口**：具体哪一槽先进入不可逆状态，历史日志无法唯一确定。
- **最小实验（只读）**：按 JSONL 时间线复核每次槽位切换前后的 `nvidia-smi`/dmesg；不做新硬件操作。
- **判据**：仍无法唯一归属 → 保持“未知”，不写进对外稿。

### OQ-13【P2】`MCLK_MAX_CAPABILITY` 是否参与限幅

- **已知**：它只是可加载的源描述（`power_governor_reverse/gsp_mclk_producers_20261011/REPORT.md:5-7`）；消费者未闭合。
- **最小实验（静态）**：从 descriptor 表基 `0x01e21b98` + 行 `0xff` 出发，追 `+0x58/+0x5c/+0x68` 字段的读者。
- **判据**：找到读取该源对象的限幅比较指令 → 参与；找不到 → 不参与（记录 xref 覆盖范围）。

### OQ-14【P2】FSP runtime 能否恢复

- **已知**：boot dispatcher 仍工作、runtime 死（`HANDOFF_20261006.md`）；思路是 T76 读 flash → 清死亡标志 → 复活 runtime。
- **缺口**：死亡标志位置/语义未确认；T76 读路径未在干净卡上验证。
- **最小实验**：先只读 T76 读取 flash 状态区，与健康卡对比；再决定是否写。
- **判据**：找到“健康/死亡”状态位差异；写入前需单独评审。
- **风险**：高。

### OQ-15【P3】是否修原文的失效路径

- **已知**：`gsp_qemu/README.md:93,115`、`gsp_qemu/docs/LAB_BOOT.md:86` 仍指向 `/home/user/rt_5090_project/...`。
- **缺口**：本阶段硬约束是“不改原文件”，因此只记录在 `CORRECTIONS.md` C-13。
- **最小实验**：无（文档决策）。若批准，只改这三处命令，并在 `CORRECTIONS.md` 标记“已落地”。

### OQ-16【P2】615.71.09 的地址能否套到 610.57.04

- **已知**：两版本文档出现同形态 VA；`gsp_mclk_producers` 明确“不能直接套用到 R570.215”（`:5`）。
- **缺口**：没有 615.71 → 610.57 的重定位表。
- **最小实验（静态）**：对 `tdispmgr` 等 3 个函数做字节指纹（前 32B + 调用图），在 610.57 镜像中搜索。
- **判据**：得到稳定偏移，或确认函数不存在。

### OQ-17【P2】关键实验的环境出处（裸机 vs 直通 VM）

- **已知**：V5 §7.1 写“VM实验室”，正文多用“真机/硅晶验证”；`GSP_FSP_IFACE:91` 明写 VM；`REVIVAL_FINAL` 明写宿主直跑。
- **缺口**：没有逐实验的环境清单。
- **最小实验（只读）**：按 `FINDINGS.md` 的 GSP/CLK/FSP 条目逐条回查原文的“VM/裸机”措辞，产出映射表。
- **判据**：每条 E0/E1 都有明确环境；无法确认的降级为“环境未记录”。

---

## 5. 优先级汇总

| 优先级 | 条目 |
|---|---|
| P0 / P0-QEMU | OQ-01、OQ-04、OQ-05、OQ-18 |
| P1 | OQ-06、OQ-07、OQ-08、OQ-09、OQ-10 |
| P2 | OQ-11、OQ-12、OQ-13、OQ-14、OQ-16、OQ-17 |
| P3 | OQ-02R、OQ-15 |
| 已关闭 | OQ-02（dtor +8）、OQ-03（TYPECALC 基线 a300a000） |

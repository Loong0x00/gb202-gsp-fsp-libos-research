# NEXT_STEPS — 下一步（真机 / QEMU / 静态 三线）

> 初版：2026-10-18。**2026-10-27 状态覆盖：下文所有现有 RTX 5090 真机步骤均取消/不再授权，只保留为历史计划，不得照做。**
> 原因见 `HARDWARE_DO_NOT_TOUCH_RISK_SUMMARY_20261027.md`：FSP/GSP 消息、宽范围 MMIO 读取和恢复动作均曾引发 WPR2、PCIe 或内核级故障，且现有卡的经济损失不可接受。
> 当前有效后续仅限：离线静态分析、QEMU 模拟、公开新工件监测，或未来独立可牺牲样品上的重新授权实验。

**环境前提**

- 真机实验：**停止。** 不发送消息、不做 BAR/MMIO 扫描、不 reset、不运行 MODS 极限测试、不触碰 FuseRework/flash/fuse。
- QEMU 实验：`cd gsp_qemu`；不改系统 QEMU；纯 TCG、无网络/磁盘。
- 静态实验：只读；不改原始样本和 `ghidra_static/*.rep`。

当前可恢复条件：出现 `fuserework.bin` 四件套、合法 x86 Blackwell FieldDiag、debug/engineering `FSP_RUN`、新的符号/明文，或独立可牺牲样品并重新取得明确授权。

---

## 1. 真机主线（历史计划，全部取消）

### NS-R1【P0】t0=4 在真机 U-mode 的 A/B（对应 OQ-01）

- **目标**：判定真机 U-mode 的正常 syscall 是否可能进入 `0x930042f8` fast path，以及是否会触及 slow handler `0x930008cc`。
- **依据**：lab 只证明受控入口（`FINDINGS.md` Q-05/Q-06）；V5:784 的“真正的 U-mode 路径”已更正（`CORRECTIONS.md` C-01）。
- **步骤**：
  1. 基线回归：`cd gsp_qemu && make test-lab-fastpath`。
  2. 真机：用 B8 读原语确认目标对象 `state=0/ref=1`；从 RM 用户态执行 `li t0,4; unimp`；记录 dmesg 的 `sepc/stval/Xid`。
  3. 对照：对 `state=1` 的同一对象重复。
- **预期**：`state=0` 时 `sepc∈0x930042f8..0x930043a0`，state 变 1，无 dtor；`state=1` 时可能进入 `0x930008cc`。
- **判据**：若 `state=0` 直接进入 handler 并出现 `jalr` 到 dtor → 推翻“fast path 不可达 dtor”；否则确认 lab 结论在真机成立。
- **风险**：低。**这是最应该先重跑的一条。**

### NS-R2【P0】定位 t0=2 walk 表（对应 OQ-04）

- **目标**：找到真机/内核堆中 `t0=2` 使用的 16B 步长查找表。
- **依据**：三明治 gadget 已能触发 walk(2)（`★V5_STATUS:28,66`）；表位置未知（`:14,93`）。
- **步骤**：用读原语读 `[global+0x450]` 及其邻近指针；按 `entry=tbl+16*(idx+1)` 扫描；对每个候选读 `meta=[entry+16]` 的 bit63。
- **预期**：出现一处 bit63=1 且 `obj=[entry+8]` 合理的表。
- **判据**：walk(2) 的 sepc 与候选表项能对应上。
- **风险**：中（限制在已确认可读集合）。

### NS-R3【P0】非零写入原语的动态验证（对应 OQ-05）

- **目标**：确认/否定“只能写 0”。
- **依据**：V5:767-775 的负结果；静态扫描尚未穷尽。
- **步骤**：先做 NS-S2 静态扫描；若有候选，用 `B8=候选`、`a1=已知可写地址`、`a4=0x41414141` 触发，再用读原语回读。
- **预期**：读到 `0x41414141` → 存在非零写；读到 0 → 候选不成立。
- **判据**：一次成功即可改写攻击链；失败则记录 gadget VA 与寄存器现场。
- **风险**：中（写错地址可能打死 GSP）。

### NS-R4【P1】K3-1 路径 C：泄漏并写回相邻堆（对应 OQ-07）

- **目标**：让溢出后泵存活。
- **依据**：`K31_FINAL_REPORT.md:5-9`；`C2_ENTRY_AUDIT_20260926.md` 路径 C。
- **步骤**：读 `[0x100e8..0x10fff]` 原值 → 溢出时写回合理 chunk header → 观察 crash 点是否变化。
- **预期**：不再固定 crash 在 `0x1b8ffbc`。
- **判据**：连续 3 次不 crash 且泵存活。
- **风险**：高（WPR2 死锁/需 SBR 或断电）。

### NS-R5【P1】FSP runtime 不可用的最小触发（对应 OQ-06）

- **目标**：把“畸形序列”缩减到最小前缀。
- **依据**：`PSIRT_DRAFT_1:5`（最小触发未知）。
- **步骤**：每次完整断电后只做一步，随后 `prc_rw r 0x13` + `nvidia-smi` + dmesg 复验；逐步累加。
- **预期**：找到第一个不可恢复的步骤。
- **判据**：单步可复现 → PSIRT 升级；需多步 → 在稿中写清序列。
- **风险**：高（FSP 再次不可用）。

### NS-R6【P1】GSP ELF TOCTOU 的“执行”验证（对应 OQ-10）

- **目标**：从“被读取”推进到“被执行”。
- **依据**：`ELF_TOCTOU_BREAKTHROUGH.md:5-12`。
- **步骤**：arm/disarm 两组；在 ELF 代码段写一条 `ebreak`（不破坏 magic）；延迟 100ms；观察 GSP 异常 PC。
- **预期**：arm 组在写入 VA 处异常；disarm 组正常。
- **判据**：异常 PC 与写入 VA 对应。
- **风险**：高（可能变砖）。

### NS-R7【P1】C1/C2 的真机触发（对应 OQ-09）

- **目标**：把 E4 结论提升到 E1。
- **依据**：`KERNEL_PRIVESC_C1_C2_PROOF:21-27`（仅模拟器）。
- **步骤**：RPC 风暴制造 C1 窗口 + B8 读原语监控 refcount；C2 用受控页头 + `t0=2`。
- **预期**：出现目标 `sepc`/`stval`。
- **判据**：一次命中即可；未命中则记录“真机未触发”，不得写成已证明。
- **风险**：高。

### NS-R8【P2】TOCTOU 时间线 4×2 矩阵（对应 OQ-11）

- **目标**：解决 200–600ms 与 <50ms 的矛盾。
- **步骤**：50/100/200/400ms × 写 `0xF200`/`0x10000`，记录 FSP counter、MBOX、GPU 状态。
- **预期**：得到窗口边界。
- **判据**：能解释两组旧数据或推翻其一。
- **风险**：中（可能锁死 FSP）。

### NS-R9【P2】WPR2 槽位归属只读复核（对应 OQ-12）

- **目标**：确认事故槽位；若不能，保持“未知”。
- **步骤**：按 JSONL 时间线复核槽位切换前后的 dmesg/nvidia-smi。
- **判据**：唯一归属或明确“不可归属”。
- **风险**：无（只读）。

### NS-R10【P2】FSP runtime 恢复路径（对应 OQ-14）

- **目标**：确认 T76 读 flash → 清死亡标志的可行性。
- **步骤**：先只读 T76 读状态区，与健康卡对比；写入前单独评审。
- **判据**：找到状态位差异。
- **风险**：高（写入阶段）。

---

## 2. QEMU 模拟器支线

### NS-Q1【P0】补 384B 启动区域表模型（对应 OQ-18）— **已达成，2026-10-18**

- **结果**：
  - 生产者实测：`make probe-lab-table` 抓取原始 SBI server 生成的 4 项表 + init 解析的 9 条记录（`FINDINGS.md` Q-11/Q-12）。
  - 审计分支模型：`nvidia-gsp,handoff=fixture` 只声明被真实 RAM 支撑的区间，驱动用生产回绕编码。
  - 新检查点：`BOOT_REGION_TABLE_ACCEPTED pc=0xffffffff93002052`；`mtval` 不再是 `0x0c00000000000200`（Q-13）。
- **新下一处缺项**：handoff init 参数 blob（`line 220`）+ 内核日志窗口 `0xffffffff60000000`（属 NS-Q2）。
- **复现**：`cd gsp_qemu && make probe-kernel && make probe-lab-table`
- **仍不成立**：不是 BootROM/熔丝认证，也不是 RM 任务启动；lab 地址不可当真机地址。

### NS-Q2【P0→P1】init 参数 blob、日志窗口与 RM 任务启动

- **状态（2026-10-19 更新）**：**第一步（lab 测量）已达成**：
  - `0x93005550(base, size, kind=12, out)` 语义破解（FINDINGS Q-15）；blob **入口全零**（Q-16）；
    生产布局 a1/a3/a7 实测（Q-17）；`make probe-lab-init-args`（新脚本）可复现。
  - 决策已定：**声明式建模**（blob 全零 + 真实 RAM 支撑即可，无需合成描述符）。
- **阻塞（新，P0）**：QEMU 11.1.2 fixture 机器的 CPU iotlb dispatch 把 FB/SYS 解析成
  `io_mem_unassigned`（FINDINGS Q-18），内核 MPU slot PA 指向 FB 的数据访问全部
  transaction failed。修好前无法按生产布局把 data/blob 放 FB（fixture 暂维持 staging 布局）。
- **下一步**：
  1. 修 dispatch（`phys_page_find`/P_L2 顶层槽位 off-by-one 假设）或对照上游 master；
  2. 修好后：driver 传生产 a1/a3/a7 + data.bin 装载 FB+0x8001000，预期越过
     `reason=init_args` 停点；
  3. 内核日志窗口 `0xffffffff60000000`（M-mode 服务/MPU 窗口）建模；
  4. a3 区 frame 目录内容解析（`logs/lab-init-a3-region.bin`）。
- **判据**：新增阶段有断言与哈希，不以“跑过”代替。
- **风险**：dispatch 修复涉及 QEMU 核心改动，需保持 `make test` 全绿。

### NS-Q3【P1】walk 表的 handle→索引规则

- **目标**：解释真机 handle `0x0303000000307c70` 如何映射到表项。
- **依据**：`LAB_BOOT:722-726`。
- **步骤**：在 lab 中改变 handle 高位/低位，观察 lookup 命中；与真机 handle 结构对照。
- **判据**：给出可验证的索引公式。
- **风险**：无。

### NS-Q4【P1】回归基线固化

- **目标**：把已有关键结论变成可重复回归，防止文档漂移。
- **步骤**：把 `make test-lab-fastpath`、`test-lab-statecond`、`test-lab-release`、`test-lab-destroy` 的输出纳入 `STATUS.md` 的“可复现命令”表。
- **判据**：任何人按命令能得到相同关键行。
- **风险**：无。

### NS-Q5【P2】profile 地址清单

- **目标**：避免把 lab 地址当真机地址（`0x800000000803a000` 事故）。
- **步骤**：在 `LAB_BOOT` 增加“本 profile 地址 vs 真机地址”对照表，并由回归断言。
- **判据**：文档中所有 lab 地址都有 profile 标注。
- **风险**：无。

---

## 3. 静态分析

### NS-S1【P0】跨版本核对 RELEASE/TYPECALC（610.57.04 vs 615.71.09）

- **目标**：确认 `0x93005b26`/`+8`/`a300a000` 是否在 615.71 同样成立。
- **依据**：`GSP_61571_FINAL_ADDR_MAP.md` 与 610.57 地址同形态；`FINDINGS.md` OBJ-01/02 已由 610.57 反汇编确认。
- **步骤**：
  ```sh
  # 610.57（已做，可复现）
  riscv64-linux-gnu-objdump -D -b binary -m riscv:rv64 \
    --adjust-vma=0xffffffff92fff000 gsp_qemu/firmware/kernel-610.57.04/code.bin \
    | awk '/^ffffffff93005b4[c-f]:|^ffffffff93005b5[0-9a-f]:/'
  # 615.71：对对应镜像重复，比较 li/mul/ld 的立即数
  ```
- **预期**：stride 40、base `a300a000`、`ld +8` 一致；若不同，记录差异。
- **判据**：两版本逐指令一致或给出差异表。
- **风险**：无。

### NS-S2【P0】RM 空间 store gadget 穷尽扫描（对应 OQ-05）

- **目标**：确认是否存在“可控非零写”。
- **步骤**：用 `power_governor_reverse/tools/riscv_range_disasm.py` 扫描 RM 全段，找同基址 load/store 对：
  ```sh
  python3 power_governor_reverse/tools/riscv_range_disasm.py \
    gsp_qemu/firmware/gsp-fwimage-610.57.04.bin 0x01000000 0x01e9b000 \
    --load-address 0x01000000 > /tmp/rm.dis
  # 再筛 sw/sd 与其前驱 ld
  ```
- **预期**：0 个或给出候选 VA。
- **判据**：候选进入 NS-R3 动态验证；0 个则把负结果写回 `FINDINGS.md` GSP-06。
- **风险**：无。

### NS-S3【P1】MCLK 两条 marker 的调用点（对应 OQ-08）

- **目标**：确认 `0x25728`（wait）与 `0x256c8`（busy）属于不同分支。
- **步骤**：按 `notification_failure/REPORT.md` 的范围反汇编 PMU ELF，检查 `0x205d1a2c` 附近与 `0x256c8` 的调用者。
- **预期**：两条断言路径分离。
- **判据**：给出两条路径的指令级差异。
- **风险**：无。

### NS-S4【P1】`MCLK_MAX_CAPABILITY` 消费者（对应 OQ-13）

- **目标**：判定它是否参与限幅。
- **步骤**：从 `0x01e21b98` 表 + 行 `0xff` 追 `+0x58/+0x5c/+0x68` 的读者。
- **判据**：找到限幅比较或确认无读者。
- **风险**：无。

### NS-S5【P2】615.71 → 610.57 重定位表（对应 OQ-16）

- **目标**：让两版本文档的地址可互译。
- **步骤**：对 `tdispmgr` 等 3 个函数做字节指纹，在两版镜像中搜索。
- **判据**：稳定偏移差或“不存在”。
- **风险**：无。

### NS-S6【P2】更正落地与链接检查

- **目标**：让 `CORRECTIONS.md` 的条目可追踪。
- **步骤**：为每条更正加“原文锚点 + FINDINGS ID”；跑一次全库链接/路径检查（含 C-13 的旧路径）。
- **判据**：`CORRECTIONS.md` 每行都能在 `FINDINGS.md` 找到对应 ID；旧路径清单完整。
- **风险**：无。

---

## 4. 重跑清单（按“必须重跑”排序）

| 顺序 | 实验 | 原因 | 关联 |
|---:|---|---|---|
| 1 | t0=4 真机 U-mode A/B | 当前最重要的未证明假设 | NS-R1 / OQ-01 |
| 2 | 静态 RELEASE/TYPECALC 复核 | 已做 610.57，需覆盖 615.71 | NS-S1 |
| 3 | RM store gadget 扫描 | 决定攻击链是否有非零写 | NS-S2 / OQ-05 |
| 4 | t0=2 表定位 | 攻击链关键缺口 | NS-R2 / OQ-04 |
| 5 | K3-1 路径 C | 决定 K3-1 是否可利用 | NS-R4 / OQ-07 |
| 6 | FSP DoS 最小触发 | 对外稿件因果 | NS-R5 / OQ-06 |
| 7 | ELF TOCTOU 执行 | 决定 TOCTOU 是否成立 | NS-R6 / OQ-10 |
| 8 | C1/C2 真机 | 把 E4 抬到 E1 | NS-R7 / OQ-09 |
| 9 | MCLK marker 分支 | 修正“mailbox busy” | NS-S3 / OQ-08 |
| 10 | QEMU 384B 表 | **已达成 2026-10-18**；下一步 init 参数 blob | NS-Q1 / OQ-18 |

## 5. 暂不做（除非明确授权）

- 任何会写 VBIOS / InfoROM / OTP / 熔丝的步骤。
- 任何未经 arm/disarm 的 ELF 注入（`NS-R6` 需先做 disarm 对照）。
- 任何在“未确认卡已恢复”的状态下重跑 WPR2 相关实验。
- 把 `t0=4`、C1/C2、lab 地址直接写进对外材料。

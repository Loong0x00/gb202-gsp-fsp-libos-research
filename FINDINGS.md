# FINDINGS — 结论库（按证据级别分区）

> 更新：2026-10-20（GSP-17/18:B8 特权级修正为 U-mode + 攻击面收敛到 28 handler 审计;详见 B8_PRIVILEGE_CORRECTION.md）。上一轮：2026-10-19。每条 = ID / claim / evidence class / source / date / confidence。
> 证据级别定义见 `docs/EVIDENCE.md`；旧文档被更正的映射见 `CORRECTIONS.md`；未决项见 `OPEN_QUESTIONS.md`。
> **规则**：E3/E4（模拟器）条目不得被引用为真机结论；真机与模拟器冲突拆成两条，不合并。

## 0. 统计

| 区 | 条目数 |
|---|---:|
| A. QEMU 模拟器（E3） | 14 |
| B. 真机 GSP 溢出与执行域（E0/E1） | 13 |
| C. 对象生命周期 / syscall / walk | 9 |
| D. FSP | 13 |
| E. TOCTOU | 5 |
| F. 时钟 / 电压 / 功耗 | 12 |
| G. 风扇 / L2 / ISA | 4 |
| H. 恢复 / 事故 / 取证 | 5 |
| I. 对外投稿 | 2 |
| **合计** | **77** |

---

## A. QEMU 模拟器（E3）

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| Q-01 | 生产 FMC 包在宿主侧通过 SHA384 + ECDSA-P384 验证；错误信任锚在 CPU 启动前被拒绝。这是**宿主侧实现**的验证，不等于芯片熔断/BOOTROM 认证。 | E3 | `gsp_qemu/README.md:28-33,81` | 2026-10-18 | 高（在实现范围内） |
| Q-02 | 未修改的 610.57.04 生产 LibOS 在 QEMU 中从 boot 执行到 init：`pc=0xffffffff93001ec6`，下一处未建模输入为 `mcause=0xd/mtval=0x0c00000000000200`（384B 启动区域表）。 | E3 | `gsp_qemu/docs/MPU_MODEL.md:13-25` | 2026-10-18 | 高 |
| Q-03 | `nvidia-gsp-lab` profile 执行到 `0xffffffff93007324`（`sd s7,0x450(s0)`）并发布 walk 表；`[global+0x450]=s7` 断言通过。 | E3 | `gsp_qemu/README.md:58-69,81`；`gsp_qemu/docs/LAB_BOOT.md:10` | 2026-10-18 | 高 |
| Q-04 | walk 表地址 `0x800000000803a000` **只属本 profile**；真机探针必须使用真机布局的地址，不能照搬。 | E3 | `gsp_qemu/README.md:69`；`gsp_qemu/docs/LAB_BOOT.md:192` | 2026-10-18 | 高 |
| Q-05 | 受控 `t0=4, stval=0` 注入进入 `0x930042f8`：只做 state 0→1、refcount 保持 1、不调 `0x93005b26`、不调 handler `0x930008cc`。 | E3 | `gsp_qemu/docs/LAB_BOOT.md:606-631` | 2026-10-18 | 高 |
| Q-06 | 自然 boot 中 `0x930042f8` 的命中为 `t0=0/1/0x16`；**未观察到 t0=4 或 t0=23**。 | E3 | `gsp_qemu/PROGRESS.md:109` | 2026-10-18 | 高 |
| Q-07 | 第二次发布后 walk 表被填充有效项：`meta=[entry+16]` 的 bit63=1，回读 4096 字节、116 项、SHA256 稳定。 | E3 | `gsp_qemu/README.md:60-66,81`；`gsp_qemu/docs/LAB_BOOT.md:183` | 2026-10-18 | 高 |
| Q-08 | `t0=17` 释放的是新分配对象 s1，不是用户传入的 a0/s2；它是 create/register，不是 destroy。 | E3 | `gsp_qemu/README.md:87`；`gsp_qemu/PROGRESS.md:113` | 2026-10-18 | 高 |
| Q-09 | QEMU 侧回归覆盖：42 项 C 正/负检查、5000 个有界畸形输入、17 项 S/U MPU、2 项页内冲突/跨界拒绝。 | E3 | `gsp_qemu/README.md:73-79` | 2026-10-18 | 高（覆盖声明） |
| Q-10 | 完整 FSP/FMC/LibOS/GSP-RM 启动链**尚未完成**；当前只到 LibOS init + walk 表检查点。 | E3 | `gsp_qemu/README.md:3` | 2026-10-18 | 高（负结论） |
| Q-11 | 384B 启动区域表的**生产者**已实测（原始 SBI server）：契约 `source=(a5<<58)+a6+0x200`（64 位回绕）、16×24B `{selector, pad, base, size}`、`size==0` 跳过；本 profile 生成 4 个非空项（FB WPR heap `FB+0x800000/0xF800000`、WPR meta `FB/0x800000`、整段 FB aperture `FB+0xFFFFFFF/0x3FFFFFF0000001`、SYS `0x9400…/0x1000000`）。`a5=3` 是把 FB 物理地址折回 `0x8000…` VA 窗口的回绕常量，不是 aperture 选择器。 | E3 | `gsp_qemu/logs/lab-boot-table.gdb.log`；`gsp_qemu/logs/lab-boot-region-table.bin`；`gsp_qemu/docs/LAB_BOOT.md` §“384B 启动区域表” | 2026-10-18 | 高（直接实测） |
| Q-12 | init 对区域表的消费者契约：校验 `[base,base+size)` 落在 `0x9300c918` 的 8 个 aperture 内，然后写 9×24B 记录到 `0xffffffffa3008e28`。两条写路径：`selector==2 且 aperture 0` 固定写 record[0]（`+8=(3<<58)+base`），其余项从第一个空槽（本 profile 为 record[3]）追加（`+0` aperture 索引、`+1` selector、`+8` 滚动累加值、`+16` size；物理 base 另存 `+216+i*8`）。record[1]/[2] 是更早初始化写好的 VA 区域（heap `0xffffffffb3000000`、log `0xffffffff60000000`）。 | E3 | `gsp_qemu/docs/LAB_BOOT.md`；`gsp_qemu/logs/lab-region-records.bin` | 2026-10-18 | 高 |
| Q-13 | 审计分支 `handoff=fixture` 已穿过区域表检查点（`0x93002052`，rec0 `va=0x8000000000800000 size=0xF800000 pa=0x7400000000800000`）。下一处未建模输入是 handoff init 参数 blob（`line 220`，`0x9300395e` 的 `a0=11/a1=0xdc`），随后 panic 路径因缺少 `0xffffffff60000000` 日志窗口触发 `mcause=5/mtval=0xffffffff60050800`。该 profile 只声明被真实 RAM 支撑的区间，不伪造 SBI 返回值。 | E3 | `gsp_qemu/scripts/test-kernel-boot.sh`；`gsp_qemu/logs/kernel-boot.gdb.log` | 2026-10-18 | 高（本 profile） |
| Q-14 | 内核 trap 入口使用 `CSR 0x5c0` 保存/恢复 `tp`（静态仅 `0x9300395e` 写、`0x930039e2` 读两处），并读 `CSR 0xc01`（time）。两者都是硬件输入：`0x5c0` 建成 per-CPU scratch、time 用虚拟时钟；未建模时 trap 入口直接 illegal。 | E2/E3 | `/tmp` 反汇编复核 + `gsp_qemu/qemu/target/riscv/tcg/nv_gsp.c`；`gsp_qemu/qemu/target/riscv/cpu.c` | 2026-10-18 | 高（适用范围：本内核） |
| Q-15 | init（0x93001ec6）在区域表之后调用 `0x93005550(base=a1, size=a2, kind=12, out=&obj)` 解析 handoff init-argument 区域；返回非零 → panic line 220（`0x9300216e`），这正是 fixture 停点 `reason=init_args line=0xdc` 的出处。该函数把 `[base, base+align4k(pages*24))` 当 24B/页描述符数组、尾部作 buddy 堆并**自己切分回填描述符**，分配 type-12 对象（与 t0=23 CREATE 同一分配器），注册 `0xa300a7f0`，`[0xa301a130]=size`。 | E3 | `gsp_qemu/scripts/probe-lab-init-args.sh`；`gsp_qemu/logs/lab-init-args.gdb.log`；code.bin 反汇编（基址 0x92fff000） | 2026-10-19 | 高 |
| Q-16 | 生产 boot 环境交给 init 的 a1 blob（`FB+0x801c000, 0x7e4000`）在**入口时刻全零**（8.2MB dump 无一非零字节）。描述符数组与 buddy 结构全部由消费者构建；声明式 fixture 只需提供清零 RAM，无需合成内容。 | E3 | `gsp_qemu/logs/lab-init-blob-pre.bin`；`docs/LAB_BOOT.md` §init-args | 2026-10-19 | 高 |
| Q-17 | handoff `a7 = FB+0x8001000` 是**内核数据段的物理 backing**：内核 boot 早期把 MPU slot 7 建成 `VA 0xffffffffa3000000 / PA=a7 / size=0x1b000`（=data.bin 大小）。生产布局中 data 段 `[FB+0x8001000, FB+0x801c000)` 与 blob `[FB+0x801c000, FB+0x87fffff)` 连续无缝。a3 区（`FB+0x1068000, 0x4000`）入口含 265/2048 非零 qword（frame 目录：`FB+0x7003000` 等物理指针）；a3/a7 的消费者是 `0x93006d68(obj, kind, base, size, attr=12)`。 | E3 | `gsp_qemu/logs/lab-init-a7-region.bin`、`lab-init-a3-region.bin`；lab slot7 trace；`scripts/test-kernel-boot.sh` | 2026-10-19 | 高 |
| Q-18 | 工具限制：`nvidia-gsp,handoff=fixture`（staging@0x80000000 + FB@0x7400… + SYS@0x9400…）中，内核 MPU slot PA 指向 FB 的数据访问**间歇性** transaction failed（mcause=7）：MPU/PMP 翻译成功、`tlb_set_page_full` 被调用，但 section 解析为 `io_mem_unassigned`；同二进制同参数曾一次成功到达 `0x93002052`、其余多次失败 → **竞态**。flatview/monitor/rom 路径一直正常（data.bin 实际加载成功，syscall 表内容可从 FB 读回）。已排除：MTTCG、region 注册顺序、强制 commit、@0 dummy、staging 大小、machine init 末尾 `drain_call_rcu()`。`info mtree -f -d` 的 dispatch 树本身正确（root 槽 58/74 为**十进制**=0x74/0x94>>57）。`nvidia-gsp-lab`（32M@0）不受影响。待查：FB 页 fill 时 `address_space_translate_for_iotlb` 内的打印从未触发，说明 unassigned section 来自不经此函数的路径，根因未定。修好前 fixture 不能按生产布局把 data/blob 放 FB。 | E3（环境注记，非内核结论） | `gsp_qemu/PROGRESS.md` 2026-10-19 节；`docs/LAB_BOOT.md` §fixture 侧阻塞 | 2026-10-19 | 高（现象与竞态确凿；根因待定） |


### A2. trap/syscall 分发与 U-mode destroy 门控（2026-10-19 静态战役，全部 E2）

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| OBJ-10 | `0x930042f8` 是 trap 统一入口的 fast 分支：要求 **stval==0**（trap 指令为 c.unimp/0x0000）、**t0∈{4,5}**；对象表 = `[[sscratch]+1104]`（即 `[global+0x450]`）+ `a0*16+24`，门控 = meta bit63 置位、**meta&0xC==0xC**、obj 非空、desc 基线差 == **400**（=type10×0x28，即 type10 检查）。t0=4=try-lock（state 0→1、owner=sscratch）、t0=5=unlock（验 owner、state→0）；state 不满足时转 `0x930043e6` 走 syscall 表。返回时 **sepc+=2**、sret。 | E2 | code.bin 反汇编（基址 0x92fff000）`0x930042f8..0x930043e2` | 2026-10-19 | 高 |
| OBJ-11 | syscall 表分发器精确链：`0x930043ea`（t0<36 否则 `0x930019b6`）→ `0x930043f6`（t0*8）→ `0x93004400`（lw `[0xa3008280+t0*8]`）→ `0x9300440a`（jalr）。表内容（data.bin 静态）：t0=16/29 空；**t0=17 有 handler（0x93001ae0）**——"t0=17 不可达"仅因 RM 无 stub（OBJ-08 原表述修正）；t0=4→0x930008CC、t0=5→0x930009C2、t0=18→0x9300116A、t0=22→0x93007160。 | E2 | data.bin 0x8280 区 + 反汇编 | 2026-10-19 | 高 |
| OBJ-12 | RM 固件的 syscall stub 形态实测：`li t0,N` + ≤2 条短指令 + `c.unimp`。t0=4 核心序列 `li t0,4; li a1,-1; unimp` 共 **109 处**（即旧记录"124 处"的实际形态；a1=-1 为固定参数）；t0=28 形态 36 处、t0=9 4 处、t0=31 3 处。trap 指令是 c.unimp（2 字节、stval=0x0000），RM 运行时自然执行这些 stub → t0=4 在真机 U-mode **自然可达**（静态确证）。 | E2 | rm_fw_plaintext.bin 字节级模式扫描（c.li t0,4=0x4291） | 2026-10-19 | 高 |
| OBJ-13 | 各慢 handler 的 meta/type 双门控：t0=4（0x930008CC）：type==10 且 **meta&0xC==0xC**；t0=18（0x9300116A）：type==0 且 **meta&3==3**，且 ref+1→操作→05B26（无 fast 拦截，若入口 ref 已为 0 则 0→1→0→dtor）；t0=22（0x93007160）：type==3 且 meta&1；t0=19：type==3 且 meta&3==3。**净 -1 destroy 都在特殊 meta 状态的对象上**——普通对象（meta 低 2 位 0/1/2）不满足任何 destroy 门控。 | E2 | 反汇编各 handler 入口 + 05B26 调用点普查（98 处） | 2026-10-19 | 高 |
| OBJ-14 | lab walk 表对象地图（boot 期，17 项）：type∈{1,3,5,8,0xe}、**meta&3∈{0,1,2}（无 3）**、ref/state/kind 已 dump。**t0=4/t0=18/t0=19 的 destroy 门控对象（meta&3==3 或 meta&0xC==0xC、type 0/10）在 lab boot 期不存在** → "清零 refcount + 自然 t0=4/18 → dtor"路径被 meta/type 门控封死（与 statecond 测试注释一致：fast 拦 state=0）。待查：meta 低 4 位由谁在何种生命周期置 3/0xC。 | E3 | `gsp_qemu/scripts/test-lab-t18-refzero.sh` 输出（logs/lab-t18.gdb.log） | 2026-10-19 | 高（对 boot 期；运行期未证） |

> 注：Q-05 与 Q-06 是两条独立 claim。前者说明“该分支做什么”，后者说明“自然路径不走到它”。**不能**由 Q-05 推出 U-mode 可达。

---

## B. 真机 GSP 溢出与执行域（E0/E1）

> 本节实验来自 v25.x 驱动补丁 + 610.57.04；环境为带物理卡直通的实验 VM（E1）。凡标 E0 的条目在原文中写明宿主直跑。

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| GSP-01 | RPC 消息队列可溢出：声明 33 元素 → 泵全读 → metadata 溢出；`B8=0xDEADBEEF` 时 `sepc=0xdeadbeee`，为溢出确认铁证。 | E1 | `★V5_STATUS_20261016.md:27` | 2026-10-16 | 高 |
| GSP-02 | `B8`（metadata+0xB8）回调函数指针可劫持，在 S-mode 执行；`a1` 完全可控（MAP 0x10038→[s1+0xA0]）；`a0` 恒 0；支持 46 连发与 MAP 轮换。 | E1 | `★V5_STATUS_20261016.md:745-756` | 2026-10-16 | 高 |
| GSP-03 | B8 可执行域只有 RM 代码空间 `0x01xxxxxx–0x0F9B000`；内核 `0x9300xxxx`、staging/队列/对象目录均 fetch fault（NX）。 | E1 | `★V5_STATUS_20261016.md:757-761` | 2026-10-16 | 高 |
| GSP-04 | 读原语：`B8=0x01020A30`（`ld a5,0x168(a1); jalr a5`），数十次验证。 | E1 | `★V5_STATUS_20261016.md:762` | 2026-10-16 | 高 |
| GSP-05 | 写原语：`B8=0x01B52246`（`c.sw a4,0(a1)`），但回调路径上 `a4` 恒 0，等价于“清零原语”。 | E1 | `★V5_STATUS_20261016.md:763-764` | 2026-10-16 | 高 |
| GSP-06 | 非零写入原语经穷尽排除未找到：a4/a0/a5/s4 均 0；358 个 `sw a0` gadget 无一有相邻 `ld`。 | E1 | `★V5_STATUS_20261016.md:769-775` | 2026-10-16 | 中（负结果，范围有限） |
| GSP-07 | 三明治 gadget `0x1E1E62E` 可触发 walk(2)：`sepc=0x1e1e648`。 | E1 | `★V5_STATUS_20261016.md:28,66` | 2026-10-16 | 中（单次记录） |
| GSP-08 | `B8=ret0` 时零崩：`Xid120=0`，泵仍存活。 | E1 | `★V5_STATUS_20261016.md:29` | 2026-10-16 | 中 |
| GSP-09 | 关键指针跨 boot 稳定：`s1=0x0FE4790E10`、`sp=0x0FEB80FCD0`、`global handle=0x0303000000307c70`。 | E1 | `★V5_STATUS_20261016.md:745-756,292` | 2026-10-16 | 中 |
| GSP-10 | K3-1 staging 溢出**存在但无法精确利用**：溢出区含关键堆结构，任何写入都在回调前崩；crash 固定 `pc=0x1b8ffbc`、`stval=0x4fe6`。 | E1 | `K31_FINAL_REPORT.md:5-9,15-16` | 2026-09-29 | 高 |
| GSP-11 | K3-1 泄漏读成功：崩溃 PC 等于读出值，`*(0x04191678)=0x0FE4790E10`，与 metadata 指针精确匹配。 | E1 | `GSP_FSP_IFACE_20261006.md:105-112` | 2026-10-06 | 高 |
| GSP-12 | v25.3 两步法（先 33 个 → 等 50ms → 再发续传凭证）确认溢出并保持泵存活；v25.2 一次性发 65 个**无溢出**（泵改变路径）。 | E1 | `★V5_STATUS_20261016.md:19-30,244-245` | 2026-10-16 | 中 |
| GSP-13 | t0=2 的 walk 查找表位置**未知**，可能不在已扫描的堆区（扫 60+ 地址未见负数 meta）。 | E1 | `★V5_STATUS_20261016.md:14,79,108` | 2026-10-16 | 中（负结果） |

| GSP-14 | 真机 t0=4 syscall 分发存活确证：B8→RM 固件天然 t0=4 stub（0x100fd7a `li t0,4; li a1,-1; unimp`）后，unimp trap 被内核正常 dispatch 并 sret 返回（sepc=0x101002c，落在 unimp 之后 0x2b2 处，死于脏寄存器的 load 对齐错误 stval=0xd9），泵随 Xid120 退役。即 c.unimp→0x930042f8 fast/表分发的整条链在真机 U-mode/S-mode 边界上工作。 | E1 | `rt_5090_project/k61_t4probe.sh` + `t4probe_113640.log`（dmesg Xid120 sepc=0x101002c） | 2026-10-19 | 高 |
| GSP-15 | B8 回调上下文的 MPU 边界实测：读 gadget `ld a5,0x168(a1)` 以 a1+0x168=0xffffffffa3008010（内核数据段）为目标时 **load page fault（cause 0xd，sepc=gadget 自身）**——与内核代码 0x9300xxxx fetch fault 同因：回调跑在 RM/泵上下文 MPU 下，**内核数据段与内核代码段均不可直接读写**。GSP-READ 的"任意已映射地址"应修正为"回调上下文 MPU 可见区域"（RM 空间/FB/staging/设备空间）。内核侧信息需经 syscall（内核上下文执行）或 window0 别名（待测）获取。 | E1 | `k61_readprobe.sh` + `readprobe_*.log`（Xid120 cause:0xd stval=0xffffffffa3008010） | 2026-10-19 | 高 |
| GSP-16 | B8 注入的 a0 可控性：旧 loadgadget 实验的 MAP `0x10030:0x00000002` 使回调后 sepc=0x2，证明 **a0 由 metadata+0x30 槽提供、全可控**（GSP-02/OBJ 侧"B8 时 a0 恒 0"的表述仅适用于未覆盖 0x10030 的场景）。配合 a1（0x10038）= 两个参数完全可控 → `li t0,N; ...; unimp` 型 stub 可带任意 handle/参数注入。 | E1 | `k3_loadgadget.sh`（MAP 0x10030、判读 sepc=0x2）；`k3_fn76_tx.sh` MAP 例 | 2026-10-19 | 高 |

| GSP-17 | **B8 回调特权级为 U-mode 而非 S-mode**(对 GSP-02/GSP-B8 的修正):泵(pump)是 RM task 的一部分(RM task = U-mode),B8 回调 = 泵调 fcnBackendRw = 在泵上下文执行 → U-mode。决定性证据:t0=4 stub 的 unimp 走了 LibOS 的 0x930042f8(U→S trap handler)而非 M-mode handler,只有 U-mode 的 unimp 才会触发 U→S trap。旧结论"S-mode"基于"读 gadget 能读 RM 数据区",但 U-mode MPU 同样有 RM 数据区读权限,是误判。**影响:不能直接写 MPU CSR(需 S-mode);MPU 修改提权路径不可达。详见 B8_PRIVILEGE_CORRECTION.md。** | E1/E2 | t0=4 sepc=0x101002c(U→S trap 处理后返回);readprobe 内核段 load fault;win0probe window0 load fault | 2026-10-19 | 高(修正核心假设) |
| GSP-18 | 攻击面收敛:B8 = U-mode 任意 RM 空间代码执行;唯一 S-mode 入口 = syscall 表(~28 个固定地址 handler,参数受 walk 表/meta 门控)。提权必须在 28 个 handler 的逻辑里找漏洞(type confusion / UAF / 整数溢出),与 Linux 内核提权同思路。优先审计:① t0=7(不查 walk,a0 直接指针,伪对象注入);② t0=15/21/23/28(不查 walk);③ t0=22/18(查 walk 但参数双 handle)。 | E2 | B8_PRIVILEGE_CORRECTION.md;OBJ-07/08(syscall 表);OBJ-13/14(meta 门控) | 2026-10-19 | 高 |

> 环境说明：V5 §7.1 写的是“VM实验室”。凡引用本节结论到裸机场景，需重新确认时序与地址稳定性。

---

## C. 对象生命周期 / syscall / walk

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| OBJ-01 | TYPECALC(`0x93004568`)：`desc=[(obj&~0xFFF)+0x20]`；`type=低32位((diff>>3)×0xCCCCCCCD)`，diff 以 `0xffffffffa300a000` 为基线。 | E2/E4 | `C2_ENTRY_AUDIT_20261010.md:12-15`；反汇编复核见 `OPEN_QUESTIONS.md` §3（`code.bin @0x93004568`） | 2026-10-10（复核 2026-10-18） | 高 |
| OBJ-02 | RELEASE(`0x93005b26`)：`slot=(0xffffffffa300a000 + type_u32×40 + 8) mod 2^64`；`dtor=[slot]`，非零则 `c.jalr dtor`（`@0x93005b60`，a0=obj，S-mode）。 | E2/E4 | `C2_ENTRY_AUDIT_20261010.md:16-19`；反汇编复核见 `OPEN_QUESTIONS.md` §3（`ld a5,8(a5)` @0x93005b5a） | 2026-10-10（复核 2026-10-18） | 高 |
| OBJ-03 | GB10Y 旧内核使用 `RELEASE=0x930060f2` 且 dtor 在 `+0x28`；**不可用于 GB20X**。 | E4 | `KERNEL_PRIVESC_C1_C2_PROOF_20261008.md:21-27`；`GSP_PRIVESC_FINAL_PLAN_20261008.md:2481-2484` | 2026-10-08 | 中（历史版本；OQ-02 已静态裁决） |
| OBJ-04 | dtor 表静态为 BSS 0；运行时 type10 dtor 为 `0x93008130`，dtor 表基 `0xA300A000`、stride `0x28`、函数指针在 `entry+8`。 | E3 | `gsp_qemu/PROGRESS.md:109`；`★V5_STATUS_20261016.md:787` | 2026-10-16 | 中 |
| OBJ-05 | 慢 handler 条件：`state=1/ref=0` → ref 0→1、不 dtor；`state=0/ref=0` → ref 0→1 后调 `0x93005b26` → ref 0 → dtor（priv=1，S-mode）。 | E3 | `gsp_qemu/docs/LAB_BOOT.md:700-720` | 2026-10-18 | 高 |
| OBJ-06 | `t0=23`（CREATE）创建 type12 对象，`ref=1`、`state=0`；create 返回 a0=0，slot 在栈上不返回。 | E3 | `gsp_qemu/docs/LAB_BOOT.md:612-617`；`★V5_STATUS_20261016.md:780,840` | 2026-10-18 | 高 |
| OBJ-07 | syscall handler 表 `0xA3008280`，每项 8B、32 位 handler 指针；分发 `t0×8+表基 → lw → jalr`，不走 walk 表。共 34 个 handler（16、29 为空）。 | E2 | `★V5_STATUS_20261016.md:793-797` | 2026-10-16 | 高 |
| OBJ-08 | RM 实际使用带 stub 的 syscall：0,1,2,3,4(124 处),5,6,8,9,11,12,15,18,21,22,23,27,29,31；`t0=17` 无 stub → U-mode 不可达。 | E2 | `★V5_STATUS_20261016.md:798-800` | 2026-10-16 | 高 |
| OBJ-09 | 普通 U-mode `t0=4` fast path 在 state=0 时只置 state=1，不进入 slow handler，因此 `li t0,4; unimp` **不能**到达 dtor。 | E3 | `gsp_qemu/docs/LAB_BOOT.md:711-718` | 2026-10-18 | 高 |

> C 区的关键区分：OBJ-01/02/07/08 是静态（E2，部分经 E4 复核）；OBJ-04/05/06/09 是 QEMU lab（E3）。**没有一条是 E0**。

---

## D. FSP

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| FSP-01 | COT（860B）中 816B（95%）验证字段被忽略：hash384 全 0xFF、publicKey 任意值，只要固件未改仍能启动。 | E0 | `FSP_ULTIMATE_FINDINGS.md:7-13`；`COT_SIGNATURE_FINDINGS.md:5-12` | 2026-09-29 | 高 |
| FSP-02 | 但“hash 全 0xFF + 改固件 1 字节”会被 FSP 拒绝（`✗ FSP 拒绝`），说明固件本体仍被校验。 | E0 | `FSP_TRUST_CHAIN_MODEL.md:10-11` | 2026-09-29 | 高 |
| FSP-03 | WPR 元数据层的签名验证是真实的；COT 层不是。两层必须分开表述。 | E0 | `FSP_ULTIMATE_FINDINGS.md:16` | 2026-09-29 | 高 |
| FSP-04 | COT（NVDM type 0x14）只在 FSP boot-phase dispatcher 有 handler；runtime dispatcher 静默丢弃，无响应、无错误、通道不受影响。 | E0 | `COT_FINAL_VERDICT.md:8,14-15` | 2026-09-29 | 高 |
| FSP-05 | 47 个 PRC knob 完整地图；PRC 写入可 flash 持久化（设计如此）。 | E0 | `PRC_KNOB_MAP.md:7,32` | 2026-09-28 | 高 |
| FSP-06 | MNOC port 0 协议完整闭合，并在“脏卡”上验证通过；旧 B7b 的“硬件级来源验证”结论错误。 | E0 | `MNOC_PORT0_PROTOCOL.md:4,10-15` | 2026-09-30 | 中 |
| FSP-07 | 一段畸形 NVDM/传输序列后，FSP runtime 服务（PRC、FWUP、caps、InfoROM、clock boost）持续不可用，且跨完整断电；GSP 启动与计算仍正常。 | E0 | `PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md:34-45` | 2026-10-13 | 高（现象） |
| FSP-08 | 该不可用状态的**最小充分触发未知**：序列含多次操作，期间未恢复并复验 FSP 健康。 | E5 | `PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md:5` | 2026-10-13 | 高（作为“未知”） |
| FSP-09 | FSP_RUN v6 为 AES-GCM 加密（熵 7.999/字节，密钥芯片内锚定），本地与公开世界均无明文；公开研究为空白。 | E2/E6 | `fsp_ace_static_20260927/SUMMARY.md:13,20,74` | 2026-09-27 | 高 |
| FSP-10 | EMEM 命令队列寄存器协议：`QUEUE_HEAD` 是 FSP 读区间起点且宿主可写，`QUEUE_TAIL` 为 dword 单位，单包驻留；PSEC 块 `0x840000-0x843fff` 同型。 | E2 | `fsp_ace_static_20260927/notes/FSP_SURFACE_REVISIONS.md:7-24` | 2026-09-27 | 高 |
| FSP-11 | GSP 侧 FSP 传输栈：EMEM 后端 `0x15015c8/0x14fb74c`、MNOC aperture `0x150a3b0`（base `0x8f1e00`、span `0x200`）、方法槽 `+0x158/+0x1c8/+0x1d0`。 | E2 | `fsp_ace_static_20260927/SUMMARY.md:30` | 2026-09-27 | 高 |
| FSP-12 | FSP 黑盒异常清单共 32 项：永久损伤 7、系统级死锁 4、临时 DoS 6、信息泄露 3、设计缺陷 3、行为异常 9。 | E0 | `FSP_BUG_INVENTORY.md:4` | 2026-10-02 | 中（因果表述须按 C-09 降级） |
| FSP-13 | 消息层：PRC read/write 正常；NVLink mask 全 1 被接受且无范围校验（GB202 无 NVLink，无实际影响）。 | E0 | `FSP_MSG_LAYER_AUDIT.md:7-8` | 2026-09-28 | 高 |

> FSP-07 与 FSP-08 必须成对引用：前者是现象（E0），后者否认了“单条请求即永久 DoS”的因果（E5 记录）。

---

## E. TOCTOU

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| TOC-01 | FMC 方向：验证期写入 → `0xFFFF` 干净拒绝；加载期（10–45ms）写入 → FSP 锁死（`MBOX=badf4100`）；加载完成后写入 → 无效。**没有可用于 FMC 的漏检窗口。** | E0 | `TOCTOU_FINAL_REPORT.md:32-44` | 2026-09-29 | 高 |
| TOC-02 | GSP ELF（27MB）在 `sendAndRead` 返回后 100ms 仍被 FMC 读取：写 ELF 起始 4 字节即致 GSP 挂死。**读到 ≠ 执行。** | E0 | `ELF_TOCTOU_BREAKTHROUGH.md:5-12` | 2026-09-29 | 高 |
| TOC-03 | GSP 方向 FMC `fw[0x10000]` 写入到达物理内存（`d564→0902`，clflush+mfence 后），且 GPU 仍工作。 | E0 | `GSP_TOCTOU_SUCCESS.md:9,33-40,47` | 2026-09-29 | 高 |
| TOC-04 | 上述写入**未证明被执行**：FMC 在 GSP 启动前已进 I-Cache，`0x10000` 可能是死代码；作者自评 B 级。 | E0（负结果） | `GSP_TOCTOU_SUCCESS.md:47-55` | 2026-09-29 | 中 |
| TOC-05 | FSP 对 sysmem 数据做“全阶段”校验：`sendAndRead` 返回 0x0 只代表验证通过，后台加载仍在继续。 | E0 | `SESSION_20260929_TOCTOU.md:3-5,70` | 2026-09-29 | 中（与 TOC-01 同源） |

> TOC-01（FMC）、TOC-02（ELF）、TOC-03/04（GSP FMC 写入）是三个不同对象，禁止互相套用结论。

---

## F. 时钟 / 电压 / 功耗

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| CLK-01 | MCLK 18000MHz（relation offset `3999000 kHz`，即 +3999）通过；硬件实测约 17982MHz（≈请求×1000/1001）。 | E0 | `power_governor_reverse/MODS570215_MCLK_3999_4000_STATIC_FINDINGS_20260903.md:29,33` | 2026-09-03 | 中（单一平台） |
| CLK-02 | MCLK 18001MHz（offset `4000000 kHz`，即 +4000）在显存测试开始前失败；PMU 在 `SEPC=0x205d1a2c` 断言停机，host 等 `CHANGE_SEQ_PMU` 后返回 `NV_ERR_TIMEOUT(0x65)`。 | E0 | 同上 `:11,30`；`power_governor_reverse/mclk4000_root_hunt_20261009/REPORT.md:32` | 2026-10-10 | 高 |
| CLK-03 | 本案失败 marker 是 **`0x25728` = completion wait 超时**；`0x256c8` 才对应 busy 失败。两者不可混称。 | E2 | `power_governor_reverse/mclk4000_root_hunt_20261009/notification_failure/REPORT.md:17` | 2026-10-10 | 高 |
| CLK-04 | 已恢复的发送段未发现对 +4000/18001 的主动频率拒绝：频率按 32 位原样发送，metadata 恒 0；失败发生在等待 completion 预算耗尽后。 | E2 | `power_governor_reverse/mclk4000_root_hunt_20261009/REPORT.md:7` | 2026-10-10 | 高 |
| CLK-05 | “为何没有正常 completion”的设备侧首因未定位；不能定性为 FSP 拦截、36Gbps 硬限制或显存训练失败。 | E2（负结果） | 同上 `:7` | 2026-10-10 | 高（作为未知） |
| CLK-06 | `MCLK_MAX_CAPABILITY` 不能当作已找到的 18000MHz 硬上限；它只是可加载的源描述，是否参与限幅未闭合。 | E2 | `power_governor_reverse/gsp_mclk_producers_20261011/REPORT.md:5-7` | 2026-10-11 | 高 |
| CLK-07 | 显存锁频（`min=max=15000`）在不变 V/F 曲线与 +2000 offset 下，使 CP2077 PT 平均 FPS 下降 16.43%、GPU 时钟降 118.1MHz。 | E0 | `RT_MEMORY_LOCK_AB_TEST_20260728.md:7-8,36` | 2026-07-28 | 高 |
| CLK-08 | 有限的显存时钟上限会静默约束 XBAR/SYS：路径追踪下板功耗降约 146W 而性能降约 15.5%；FurMark 下报告核心频率上升但渲染吞吐降约 32%。 | E0 | `NVIDIA_ISSUE_BLACKWELL_MEMORY_LOCK_PERF.md:1,42` | 2026-07-28 | 高 |
| CLK-09 | 800W 板功耗上限下，RT 负载实际只获得约 500W 有效预算，控制器允许约 2955MHz。 | E0 | `RT_POWER_BUDGET_CURRENT_FOCUS_20260727.md:7-8,21` | 2026-07-27 | 中 |
| CLK-10 | XBAR 是独立物理时钟域：有独立 PMU 对象、时钟源、V/F 点、硬件测频与运行时控制；改变它改变实测时钟与渲染吞吐。 | E0+E2 | `XBAR_PHYSICAL_HARDWARE_DRAFT_ZH.md:5,32` | 2026-08-13 | 高 |
| CLK-11 | 生产 610.57.04 驱动 + 原厂 GSP（不用 MODS）可同时保持 GPC 频率与 NVVDD。 | E0 | `PRODUCTION_GPC_VF_LOCK_20260824.md:5-6` | 2026-08-24 | 中 |
| CLK-12 | `CLK_VF_POINTS`：INFO `0x20809021`/`0x8208`B；STATUS `0x20809022`/`0x98208`B。 | E0 | `VF_POINT_BANK_INVENTORY_20260816.md:5-10` | 2026-08-16 | 高 |

> CLK-01 与 CLK-02 是**两个 case**：+3999 通过、+4000 失败。不得写成“+3999/+4000 边界”一条。

---

## G. 风扇 / L2 / ISA

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| HW-01 | 逻辑 Fan0/controller0 驱动物理风扇 1 与 3；Fan1/controller1 驱动 2 与 4（30% vs 100% 实测）。 | E0 | `fan_runtime_mapping_20260724.md:3-9` | 2026-07-24 | 高 |
| HW-02 | Lightning 800W VBIOS 只声明一个 `FAN_COOLERS` 活动槽（`00 ff ff ff`），导致 fan1/PWM11/GPIO3 运行时对象缺失。 | E0 | `FAN_CONTROL_DO_NOT_REPEAT_20260727.md:9` | 2026-07-27 | 高 |
| HW-03 | 目前**不能**安全写出把 L2 96→128MiB 的工具；已排除 `fbp_l2slice_enable` 等两条直接路径。 | E2 | `L2_REENABLE_STATIC_FINDINGS.md:5-12` | 2026-07-22 | 高（负结论） |
| HW-04 | sm_120 SASS 的缓存控制与特殊寄存器访问已单独整理（不含普通算术 ISA）。 | E2 | `SM120_CACHE_AND_REGISTER_ISA.md:1` | 2026-07-13 | 中 |

---

## H. 恢复 / 事故 / 取证

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| REC-01 | 卡已完全可用（宿主直跑）：`nvidia-smi` 正常、CUDA 可用、32GB 显存；恢复机制是 WPR2-bypass 补丁模块（一行改动）。 | E0 | `REVIVAL_FINAL.md:3,6,8` | 2026-09-30 | 高（当时状态） |
| REC-02 | WPR2 事故触发序列：卸载驱动 → COT 基线 → size fuzz（全部静默消费）→ version fuzz（PRC handler 死亡、MT=0 不响应）。 | E0 | `WPR2_INCIDENT.md:3-7` | 2026-09-28 | 中 |
| REC-03 | Power Cycle ≠ SBR：SBR 清除特定 reset domain 并让 FSP 走另一条初始化路径；断电不一定达到同样效果。 | E0 | `SBR_RECOVERY_DISCOVERY.md:1,44` | 2026-09-28 | 中 |
| REC-04 | “一次操作后两个 BIOS 槽都无法启动”**不是**两颗 SPI flash 同时永久损坏：共享 GPU/FSP 状态可让两槽同时表现失败。 | E5 | `DUAL_BIOS_CROSS_SLOT_FORENSICS_20261012.md:8,102` | 2026-10-12 | 中 |
| REC-05 | 原版槽最后一个无争议健康点是 2026-09-28T12:32Z；后续失败不能唯一归因于单槽或单次 COT 请求。 | E5 | `ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md:10,322` | 2026-10-13 | 中 |

---

## I. 对外投稿

| ID | Claim | E | Source | Date | Conf |
|---|---|---|---|---|---|
| SUB-01 | 两封 NVIDIA PSIRT 邮件已于 2026-10-13 通过已登录 Gmail 发出（显示 `Message sent`），附源文件与 SHA-256。 | E5 | `SUBMISSION_RECORD_20261013.md:3-12` | 2026-10-13 | 高 |
| SUB-02 | 投稿稿 1 明确**不**主张“单条合法 ROMREAD 即永久禁用 FSP”，只报告“畸形序列后 runtime 服务持续不可用”。 | E5 | `PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md:5` | 2026-10-13 | 高 |

---

## J. 引用本文档时的强制限定

1. `Q-*`、`OBJ-04/05/06/09`、`OBJ-03`（E4）永远不能出现在“真机已验证”清单里。
2. `GSP-*` 是 E1（直通 VM），引用到裸机需重测时序与地址稳定性。
3. `FSP-*`、`CLK-*`、`TOC-*` 的 E0 条目只对其固件/驱动版本成立（610.57.04 / 615.71.09 / MODS 570.215 各不相同）。
4. 所有地址类 claim 的完整表述必须带版本，例如 `0x93005b26（610.57.04 GB20X）`。

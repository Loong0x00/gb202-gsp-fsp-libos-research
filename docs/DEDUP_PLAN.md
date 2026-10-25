# 去重与合并方案（DEDUP_PLAN）

> 生成日期：2026-10-18（第一步产物）
> 状态：**仅分析，未移动、未删除、未覆盖任何原文件。**
> 配套文件：`docs/INDEX.md`（230 份 `.md` 的逐条登记）。
> 第二步（待确认后执行）：生成 `STATUS.md` / `FINDINGS.md` / `OPEN_QUESTIONS.md` / `NEXT_STEPS.md`，并把本文件 §6 列出的文件移入 `docs/archive/`。

---

## 0. 判定原则

1. **证据类别不因文档语气而升级。** 只有实际执行过的对象才算证据：物理卡 = 真机；反汇编/源码 = 静态；QEMU/`rv64_emu.py` = 模拟器。文档自述“已验证/实锤/A 级”不改变类别。
2. **同一主题按“最后一份带新证据的文档”定权威**，而不是按“最后修改时间”或“标题带★”。
3. **只有在原位置会继续误导时才算“需要归档”**；报告目录内部的局部副本、厂商源码树内的模板文件，移动它们会破坏可读性/完整性，一律原地保留（见 §6.2）。
4. **合并 ≠ 删除结论。** 被归档文档中的独有事实先抽取到 `FINDINGS.md` 对应条目，再移动文件。

建议在第二步统一使用的证据分级（供 STATUS/FINDINGS 引用）：

| 级别 | 含义 | 典型来源 |
|---|---|---|
| E0 | 真机裸机实测 | 宿主直接跑 nvidia 610.x + 物理 5090 |
| E1 | 真机直通 VM 实测 | `vm_mods_lab`、K3-1 注入、`GSP_FSP_IFACE` 泄漏读 |
| E2 | 静态：原始固件/官方源码/头文件/VBIOS | `power_governor_reverse/*`、`fsp_ace_static/*` |
| E3 | 模拟器：QEMU lab | `gsp_qemu/*` |
| E4 | 旧 Python 模拟器 | `rv64_emu.py`（按 AGENTS.md 仅作历史参考） |
| E5 | 二手综合（基于既有文档的复盘/清单） | `VULN_INVENTORY`、`LOGICAL_*`、`RESUME_BRIEF` |
| E6 | 公开网页/第三方资料 | `mclk4000_public_cases`、`open-iov-device-model.md` |

---

## 1. 方法与去重口径

- 全文清点 230 份 `.md`（排除 `ghidra_static/*.rep`、`gsp_qemu/qemu`、`gsp_qemu/build`、`.pytest_cache`、`__pycache__`）。
- **字节级重复**：`md5sum` 全量比对（结果见 D1/D2）。
- **近重复**：按行集合 Jaccard 比对（阈值 ≥0.5 判近重复；仅 D2 命中）。
- **同系列/同主题**：按文件名日期、自述“覆盖/作废”、结论对象与取证对象人工归组。
- **不是重复的情况**：同一实验的“数据”和“结论”、同一事件的“过程”和“取证”，均保留。

---

## 2. 重复组

### D1 字节级重复（厂商模板 / 报告内副本）

| 成员 | 关系 | 建议保留 | 建议处理 |
|---|---|---|---|
| `gspkm/CODE_OF_CONDUCT.md`、`gspkm/CONTRIBUTING.md`、`gspkm/SECURITY.md` | 与 `driver_gpio_internal_610.43.03/` 同名文件字节相同 | `gspkm/`（610.57.04，较新） | **原地保留，不归档**：属于厂商源码树，移动会破坏 vendor tree 完整性 |
| `power_governor_reverse/gsp_mclk4000_review_20261010/parent_capability/NOTES.md`、`power_governor_reverse/gsp_mclk_producers_20261011/max_capability/NOTES.md` | 字节相同（5333B） | 后者（2026-10-11，较新） | **原地保留**；在两份文件头部各加一行“同内容副本位于 …”，避免重复维护 |
| `power_governor_reverse/**/.pytest_cache/README.md`（3 份） | 工具生成 | — | 不属于文档，已在索引中排除；第二步可随意删除（非文档） |

### D2 近重复（正文包含关系）

| 成员 | 关系 | 建议保留 | 建议处理 |
|---|---|---|---|
| `GITHUB_NEW_ISSUE_WPR2_RECOVERY_PREVIEW.md` ⊃ `GITHUB_NEW_ISSUE_WPR2_RECOVERY_BODY.md` | 行集合 Jaccard 0.97；PREVIEW = `# Title` + Body | **PREVIEW**（完整可粘贴） | BODY 归档；`GITHUB_ISSUE_1080_COMMENT_PREVIEW.md` 是另一个 issue 的评论，虽同源但不重复，保留 |

### D3 版本链：谁取代谁

| 文档 | 自述 | 结论 | 建议 |
|---|---|---|---|
| `★AUTHORITATIVE_PROGRESS_20261011.md` | 第一版“唯一权威” | 被 v2 覆盖 | 归档 |
| `★AUTHORITATIVE_PROGRESS_v2_20261013.md` | “覆盖所有旧文档” | 被 v3/V4 覆盖；细节最全（99 个二级标题） | 归档（先抽取独有细节，见 C2/C4） |
| `★AUTHORITATIVE_PROGRESS_v3_20261015.md` | “覆盖所有旧文档” | 被 V4 覆盖 | 归档 |
| `★V4_PROGRESS_20261016.md` | “覆盖所有旧文档(v2/v3/v3.x 全部作废)” | 被 V5 覆盖；独有 §3.4 msgq 协议 / §3.5 backend `0x0100CF9C` 解码 | 先抽取 §3.4/§3.5 到 FINDINGS，再归档 |
| `★V5_STATUS_20261016.md` | “状态快照”，写到 2026-10-18 | **当前最新** | **保留为唯一权威档**（但必须加证据列，见 §4） |

> 注意：文件名同为 `20261016`，V5 的实际内容延续到 10-18（含“最终归档”一节），因此 V5 > V4，不能按文件名并列。

### D4 同主题多版结论（保留一份 + 归档其余）

| 主题 | 成员（按时间） | 保留 | 归档 | 理由 |
|---|---|---|---|---|
| FSP 信任链 | `FSP_LINE_COMPLETE_20260926` → `FSP_COMPLETE_TRUST_CHAIN` → `FSP_TRUST_CHAIN_MODEL` → `FSP_ULTIMATE_FINDINGS` | `FSP_ULTIMATE_FINDINGS`（最终结论）+ 把 `FSP_TRUST_CHAIN_MODEL` 的唯一完整实验矩阵并入 FINDINGS 附录 | 前两份 +（矩阵并入后）MODEL | ULTIMATE 只给结论，矩阵在 MODEL 里；两者互补，其余被覆盖 |
| FSP TOCTOU | `TOCTOU_FINAL_REPORT`、`SESSION_20260929_TOCTOU` | `SESSION_20260929_TOCTOU`（矩阵更全 + 热重载方法） | `TOCTOU_FINAL_REPORT` | 后者“没有漏检窗口”的表述只对 FMC 成立（见 C5），需先改标题范围再归档 |
| GSP TOCTOU | `GSP_TOCTOU_SUCCESS`、`ELF_TOCTOU_BREAKTHROUGH` | `ELF_TOCTOU_BREAKTHROUGH` | `GSP_TOCTOU_SUCCESS` | 后者结论强于证据（见 C6） |
| COT 注入 | `COT_INJECTION_FINDINGS` → `COT_SIGNATURE_FINDINGS` → `COT_FINAL_VERDICT` | `COT_FINAL_VERDICT` + `COT_SIGNATURE_FINDINGS`（A 级证据） | `COT_INJECTION_FINDINGS` | 初版“按内容响应”已被最终判定否定（见 C7） |
| CC 模式 | `CC_ATTEMPT3_RESULT` → `CC_FINAL_REPORT` → `BIOS_SLOT_CC_LOCK_RECOVERY`（v2） | `BIOS_SLOT_CC_LOCK_RECOVERY`（含“v1 方案已实测失败”的更正） | 前两份 | v2 明确声明 v1 过时（见 C14） |
| 615.71 地址 | `GSP_61571_ADDR_MAP` → `GSP_61571_FINAL_ADDR_MAP` | FINAL | 初版 | 直接覆盖关系 |
| K3-1 | `HANDOFF_K31`、`DS_SESSION_K31_RECOVERY`、`HOT_SWAP_GSP_ANALYSIS`、`K31_INJECTION_SETUP`、`K31_FINAL_REPORT` | `K31_FINAL_REPORT`（结论）+ `K31_INJECTION_SETUP`（环境可复现） | 前三个 | HANDOFF 页首自注“已过时两处”；DS/HOT_SWAP 是过程与构想 |
| BIOS 取证 | `DUAL_BIOS_CROSS_SLOT_FORENSICS`、`ORIGINAL_BIOS_SLOT_FORENSICS` | 两份合并为一份 `FINDINGS` 条目 + `docs/FINDINGS.md` §恢复 | 合并后归档两份 | 两份回答不同问题（跨槽 vs 单槽），但共享时间线，重复叙述多 |
| 会话总结 | `FINAL_STATUS_20260928`、`SESSION_SUMMARY_20260930`、`SESSION_SUMMARY_20261002`、`FINAL_SESSION_20261002`、`WRAPUP_20260926` | `EXPERIMENT_LOG_20260929_30`（最完整的战役时间线）+ `FINDINGS.md` | 其余 | 同日两份 10-02 总结内容互补但都不完整，事实应并入 FINDINGS |
| 交接 | `HANDOFF_20261001`、`HANDOFF_20261006`、`HANDOFF_CURRENT` | `HANDOFF_CURRENT`（最短、最新） | 前两份 | 第二步由 `STATUS.md`/`NEXT_STEPS.md` 接管后，HANDOFF_CURRENT 也可归档 |
| FSP 缺陷清单 | `FSP_BUG_INVENTORY`（32 项） vs `VULN_INVENTORY`（全领域） | 两份都保留 | — | 范围不同；但 FSP_BUG_INVENTORY 必须加因果注释（C8） |
| 早期控制逻辑 | `BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725`、`BLACKWELL_VF_RUNTIME_GOVERNANCE_FINDINGS_20260724` | `power_governor_reverse/` 系列 | 两份 | 7 月版被 8-9 月的静态系列细化 |

### D5 同名不同物（不是版本）

| 文档 | 问题 | 建议 |
|---|---|---|
| `C2_ENTRY_AUDIT_20260926.md` | 文件名是 9-26，内容是 2026-10-11 的“二十四、根因发现”残片，无 H1，首行是 `---` | 内容并入 `C2_ENTRY_AUDIT_20261010.md` 或 FINDINGS 后归档；不要当成 9-26 的审计 |
| `GSP_PRIVESC_FINAL_PLAN_202601008.md` | 文件名日期 `202601008` 为笔误，实为 10-08 同日更早的短稿 | 并入 `GSP_PRIVESC_FINAL_PLAN_20261008.md` 后归档 |

### D6 报告目录内部的“总结 + 子报告”

`power_governor_reverse/gsp_mclk*_{review,producers,root_hunt,followup,public_cases}_*` 下均为 `REPORT.md`（阶段总结）+ 子目录 `REPORT.md`（单项证据）。**这不是重复**：阶段报告给结论，子报告给证据。全部保留，索引中已标注“权威/静态”。

---

## 3. 冲突点（必须先在 FINDINGS 里裁决，再写 STATUS）

> 格式：**冲突 → 证据 → 裁决**。裁决建议写入 `FINDINGS.md` 的“已裁决”区，未裁决的进 `OPEN_QUESTIONS.md`。

### C1【高】t0=4 fast path 是不是“真正的 U-mode 路径”

- A：`★V5_STATUS_20261016.md:784` — “t0=4 fast path(0x930042F8): 真正的U-mode路径”。
- B：`gsp_qemu/docs/LAB_BOOT.md:606-631` — 受控注入 `t0=4, stval=0` 才进入 `0x930042f8..0x930043a0`；自然 boot 只命中 `t0=0/1/0x16`；结论原文是“**因此这是受控 fast-path 入口，不是 U-mode trap**”。`gsp_qemu/README.md:86` 同样写“明确不是真实 U-mode trap”。
- 裁决：**B 正确**。A 把 lab 的受控入口写成真机 U-mode 可达路径，且与它自己引用的 lab 报告直接矛盾。正确表述：“受控实验确认 `0x930042f8` 分支对 state=0 只做 state 0→1、ref 不变、不调 handler/0x93005B26；自然 boot 未观察到 t0=4；**U-mode 可达性未证明**”。

### C2【高】lab 结论被列进“真机验证”小节

- `★V5_STATUS_20261016.md:743` 标题为“20.1 已证明的核心事实(全部有实验证据)”，其下 `:778` 子标题写“对象生命周期机制(与DeepSeek lab联合验证)”，紧接着 `:781-789` 列出：t0=23 CREATE、t0=4 LOOKUP+DEREF、`0x93005B26` 真 RELEASE、dtor 表 `0xA300A000+type*0x28+8`、gadget `0x930035D2` lab 验证成功。
- 同一节上方 `:745`（溢出平台）、`:757`（B8 可执行域）才是真机验证；`:793` 明确标了“静态提取确认”。
- 裁决：**按条目拆分证据级别**。t0=23/t0=4/0x93005B26/dtor/gadget = E3（QEMU lab）；只有“溢出、B8 劫持、B8 可执行域、a0/a1 可控” = E0/E1。父标题“全部有实验证据”应改为“全部有实验证据，级别见条目”。

### C3【高】类型表：dtor 偏移是 `+0x28` 还是 `+8`

- A：`KERNEL_PRIVESC_C1_C2_PROOF_20261008.md:14` “entry=40B, dtor在+0x28”、`:25` “slot = base + type×40 + 0x28”、`:122` “+0x28 dtor”。
- B：`GSP_PRIVESC_FINAL_PLAN_20261008.md:346` “40B/项，★dtor在entry+8 — GB10Y是+0x28”、`:2484` “dtor在entry+8 (GB20X与GB10Y不同!)”；`★V5_STATUS:327` “0xA300A000 + type*0x28，函数在entry+8”。
- 裁决：**B 正确，A 把 stride 当成了偏移**。GB20X：entry stride = `0x28`(40B)，dtor 在 `entry+8`；GB10Y 旧内核才是 `+0x28`。所有引用 A 的文档（含 `:25` 的公式）必须改。

### C4【高】RELEASE 地址 `0x930060F2` 还是 `0x93005B26`

- A：`GSP_PRIVESC_FINAL_PLAN_20261008.md:2441` 记录“老文档 0x930060F2(dtor@+0x28,实证) vs 近期读的 0x93005B24”；`:2481` 自我更正“❌ RELEASE=0x930060F2/dtor+0x28 为准 — 那是 GB10Y 旧内核!”。
- B：`★V5_STATUS:781-787`、`KERNEL_PRIVESC_C1_C2_PROOF:21-27` 使用 `0x93005B26`。
- 裁决：**GB20X = `0x93005B26`**；`0x930060F2`（及 `0x93005B24` 变体）属旧内核/不同变体，不得混用。凡出现 `0x930060F2` 的段落需标“GB10Y，勿用”。

### C5【中】TOCTOU 到底有没有窗口

- A：`TOCTOU_FINAL_REPORT.md` — “没有‘漏检’窗口”（验证期写→0xFFFF；加载期写→FSP 锁死；加载后写→无效）。
- B：`ELF_TOCTOU_BREAKTHROUGH.md` — GSP ELF（27MB）在 `sendAndRead` 返回后 100ms 内仍被读取，写 ELF 头即挂死。
- C：`GSP_TOCTOU_SUCCESS.md` — 声称窗口 200-600ms（FMC），写 400ms 命中。
- 裁决：**三者对象不同，不构成同一结论**。A 只对 FMC（290KB，已在 I-Cache）成立；B 证明 ELF 有读取窗口（读到 ≠ 执行）；C 的时间线无独立复现，且与 A 的 <50ms 处理时间冲突（`LOGICAL_INCONSISTENCIES_DEEP_ANALYSIS.md` 矛盾 #1 已指出）。STATUS 中只允许写：“FMC 无可用窗口（E0）；ELF 有读取窗口（E0，100ms 量级）；写入→执行未证明”。

### C6【中】“GSP TOCTOU 成功/绕过签名验证”是否成立

- `GSP_TOCTOU_SUCCESS.md` 标题与首段：“成功写入固件，绕过签名验证”。
- 同文正文自述 GPU 不崩的理由：FMC 代码在 GSP 启动前已加载到指令缓存、sysmem 副本死亡；并且只验证了 `fw[0x10000]` 从 `d564` 变 `0902`。
- 裁决：只成立“**写入到达物理内存且发生在 boot 期间**”；FMC 已被缓存 + 写入点在 `0x10000`（可能是死代码）说明“执行了修改后的代码”未被证明。标题应降级；作为“原语”引用时必须带此限定。

### C7【中】COT 注入：FSP 会不会按内容响应

- A：`COT_INJECTION_FINDINGS.md` — 不同 `gspFmcSysmemOffset` 得到不同响应，推断 FSP 处理内容。
- B：`COT_FINAL_VERDICT.md` — COT 只在 boot-phase dispatcher 有 handler；runtime dispatcher **静默丢弃**，无响应、无错误。
- 裁决：**B**。A 的“不同响应”很可能来自 boot 阶段或测量方法差异，作为历史记录保留。

### C8【高】FSP 永久 DoS 的因果

- A：`FSP_BUG_INVENTORY.md:4` — “永久损伤 7”；`FINAL_SESSION_20261002.md` — “单条 ROMREAD → FSP runtime dispatcher 永久死亡”。
- B：`PSIRT_DRAFT_1_GB202_FSP_RUNTIME_DOS.md:5`（内部注记）— **明确不主张**单条合法 ROMREAD 即可永久禁用 FSP；实际是“畸形 64B EMEM `0x1A` → 一次无效的错寄存器 MNOC 尝试 → 截断 `0x1A` 打 MNOC p1/p0 → 又一次 EMEM → 其他诊断”，期间未恢复并复验 FSP 健康，**最小充分触发未知**。
- 裁决：**B**。`FSP_BUG_INVENTORY` 的“永久损伤 7”必须改成“观察到的持久不可用状态（触发序列未最小化）”；对外只能引用 PSIRT 稿措辞。

### C9【中】WPR2 事故发生在哪个 BIOS 槽

- `PSIRT_DRAFT_2_GB202_WPR2_PERSISTENT_STATE.md:211`（内部注记）：槽位切换不能给出干净对照，另一槽已有 COT/WPR2 损伤，**不主张一次畸形请求改坏两颗 flash**。
- `ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md`：把旧文档混在一起的事件拆开，指出最后无争议健康点是 2026-09-28T12:32Z。
- 裁决：保留“槽位归属未证”的限定；以 ORIGINAL_BIOS_SLOT_FORENSICS 的时间线为准。

### C10【中】MCLK +3999/+4000 的首因

- A：`power_governor_reverse/MODS570215_MCLK_3999_4000_STATIC_FINDINGS_20260903.md:15` — “后续 MCLK command-0 请求发现 mailbox busy → PMU ebreak”。
- B：`mclk4000_root_hunt_20261009/notification_failure/REPORT.md:17` — 本案日志 marker 是 `0x25728` = **completion wait**；`0x256c8` 才对应 busy 失败；且“当前能证明的是 completion wait 超时，不是 endpoint 未处理/IRQ 丢失”。
- 裁决：**B**。A 的 “mailbox busy” 是把两个 marker 混称，应降级为“未决假说”。`mclk4000_root_hunt_20261009/REPORT.md` 的“不是已证明的主动拦截”为当前结论。

### C11【中】`MCLK_MAX_CAPABILITY` 是不是 18000MHz 硬上限

- `gsp_mclk_producers_20261011/REPORT.md` 开篇：“本轮**不把** `MCLK_MAX_CAPABILITY` 当成已找到的 18000 MHz 硬上限”。
- 早期笔记（`gsp_mclk4000_review_20261010/parent_capability/NOTES.md` 等）把它当作候选限幅源。
- 裁决：按新报告——只是“可加载的源描述”，是否参与限幅未闭合。

### C12【高】版本串味：610.57.04 / 615.71.09 / MODS 570.215 的地址混用

- `GSP_61571_*`（615.71.09）、`GSP_FSP_IFACE`/`power_governor_reverse`（610.57.04）、`MODS570215_*`（570.215）在文档里出现**相同形态的 VA**（如 `0x1a8a938`、`0x205d1a2c`）。
- `gsp_mclk_producers_20261011/REPORT.md` 自己写明：“分析对象是本地 R610.57.04 GSP main，所有地址均为其内部 VA；**不能直接套用到 MODS R570.215**”。
- 裁决：FINDINGS 中所有地址必须带“固件版本 + 证据级别”三元组；跨版本推论一律标“需重定位”。

### C13【中】C1/C2 是“PROOF”还是“模拟器实证”

- `KERNEL_PRIVESC_C1_C2_PROOF_20261008.md` 标题含 `PROOF`，正文首行写“模拟器实证”；`GSP_PRIVESC_FINAL_PLAN_20261008.md:327` 写“在 GB20X REAL **真内核**上重证完成”，其中“真内核”指 `/tmp/kernel_gb20x_REAL.elf`（仍由 `rv64_emu.py` 执行）。
- 裁决：C1/C2 全部为 **E4（旧 Python 模拟器）**。禁止在 STATUS 中写成“已证明的内核提权”；正确写法：“在模拟器中于真实 GB20X 内核镜像上闭合，真机未验证”。

### C14【中】CC 锁死后的恢复方案

- `CC_FINAL_REPORT.md`（9-28）给出“切槽 + `prc_rw w 8 0`”方案。
- `BIOS_SLOT_CC_LOCK_RECOVERY.md` 开头即写：v1 方案“**已于 9月29 05:17 被 glm 会话实测失败**”，本文按完整记录重写。
- 裁决：**BIOS_SLOT_CC_LOCK_RECOVERY v2**；CC_FINAL_REPORT 仅作攻击面地图参考。

### C15【低】风扇文档的环境前提不一致

- `fan_runtime_mapping_20260724.md` / `ASTRAL_STOCK_FAN_BASELINE_20260727.md`：Astral 原厂 BIOS。
- `FAN_CONTROL_DO_NOT_REPEAT_20260727.md` / `FAN_ROUTE1_STAGE_20260727.md`：“Lightning 800W VBIOS 只启用一路 cooler，fan1 缺失”。
- 裁决：物理映射（Fan0→1/3、Fan1→2/4）两份一致；但“fan1 缺失”只对 Lightning BIOS 成立。FINDINGS 必须写清 VBIOS。

### C16【低】L2/SM 解锁是否“可做”

- `L2_REENABLE_STATIC_FINDINGS.md`：目前不能安全写出 96→128MiB 工具，已排除两条直接路径。
- `WRAPUP_20260926.md`：目标未达成（32MiB L2 + 22 SM 没拿回来）。
- 与 `GB202_PARALLEL_WORK.md` 的“并行工作契约”语气相比更保守。
- 裁决：以 WRAPUP + L2 静态结论为准，标为“已停止的旧线”，不作为当前 NEXT_STEPS。

### C17【低】文档内路径已失效（拷贝导致）

- `gsp_qemu/README.md:93` “`cd /home/user/rt_5090_project/gsp_qemu`”、`:115` 输入默认 `/home/user/rt_5090_project/gspkm`、`gsp_qemu/docs/LAB_BOOT.md:86` 同样引用旧路径；全库 49 份 `.md` 含 `rt_5090_project`。
- 裁决：**第二步只改 gsp_qemu 的“使用”命令**（改成 `cd /home/user/gsp_libos_clean/gsp_qemu`），历史文档里的路径保留（它们是证据的一部分），在 FINDINGS 的“环境”条目里说明。

---

## 4. 真机 / 静态 / 模拟器混写专项审查

> 这一节针对“模拟器结论被写成真机结论”。判定标准：该结论的执行载体是什么，而不是文档用什么形容词。

### 4.1 已确认的混写（需要在第二步修正）

| # | 位置 | 原文/写法 | 实际证据 | 应改成 |
|---|---|---|---|---|
| M1 | `★V5_STATUS_20261016.md:784` | “t0=4 fast path: 真正的U-mode路径” | E3：lab 受控注入；LAB_BOOT 明确“不是 U-mode trap” | “受控 lab 入口；U-mode 可达性未证明” |
| M2 | `★V5_STATUS_20261016.md:743` + `:778` | 父标题“已证明的核心事实(全部有实验证据)”下混入 lab 条目 | 混合 E0/E1 与 E3 | 每条加证据级别列 |
| M3 | `★AUTHORITATIVE_PROGRESS_v2_20261013.md:87` | 标题“四、内存布局 (从模拟器PMP窗口+实测)” | 模拟器布局与真机实测混在同一张图 | 拆成“模拟器布局”与“真机可写区（已验）”两张表 |
| M4 | `GSP_PRIVESC_FINAL_PLAN_20261008.md:327` | “在 GB20X REAL 真内核上重证完成” | E4：`emu_test_c2_gb20x.py` + `rv64_emu.py` | “在模拟器加载的真实 GB20X 内核镜像上” |
| M5 | `C2_ENTRY_AUDIT_20261010.md:3,5` | “A=真内核指令级/模拟器互证” | “真内核”= 真机 ELF，非真机硬件 | 改“真实内核镜像（静态+模拟器）” |
| M6 | `KERNEL_PRIVESC_C1_C2_PROOF_20261008.md` 标题 | `PROOF`（未带模拟器） | E4 | 标题加“（模拟器）”或在 FINDINGS 强制限定 |
| M7 | `GSP_TOCTOU_SUCCESS.md` 标题/首段 | “成功证明 / 绕过签名验证” | E0 但只证明“写入到达物理内存” | 见 C6 |
| M8 | `TOCTOU_FINAL_REPORT.md` 标题 | “TOCTOU 最终结论”（未限定 FMC） | E0 但仅 FMC | 标题加“（FMC 方向）” |
| M9 | `FSP_BUG_INVENTORY.md:4` / `FINAL_SESSION_20261002.md` | “永久损伤 7”“单条 ROMREAD 即永久 DoS” | E0 观察 + 未最小化序列 | 见 C8 |
| M10 | `GSP_FSP_IFACE_20261006.md:91` | “K3-1 泄漏读验证 (VM 内实弹)” — 本身标注正确 | E1（直通 VM），不是裸机 | 保留，但 STATUS 引用时写 E1 |

### 4.2 标注正确、可作为范式引用的文档

- `gsp_qemu/README.md:83-88`：每个 lab 测试都显式写“明确不是用户 syscall / 不是 U-mode 可达性证明 / 不是真实 U-mode trap”。**建议把这种句式定为第二步的证据标注模板。**
- `gsp_qemu/docs/LAB_BOOT.md` §“与真机布局的差异”“尚未完成”：明确 lab 地址 `0x800000000803a000` 只属本 profile，真机探针须用真机布局。
- `F1_FINAL_VERDICT.md`：静态预言与真机 dmesg 崩溃 PC 逐点对齐，属于**静态+真机互证**的正确写法（不是“模拟器互证”）。
- `mclk4000_root_hunt_20261009/notification_failure/REPORT.md`：把“指令直接支持的发现”与“未决/假说”分节，可作为静态报告的写法模板。
- 同类子报告（`completion_path/`、`endpoint_identity/`）：统一写“能证明的是 X，不是 Y”，并单列未决项。

### 4.3 术语陷阱（第二步统一）

| 词 | 在本库中的实际含义 | 风险 |
|---|---|---|
| “真机” | 物理卡，**多数时候是直通 VM**（V5 环境写的是“VM实验室”） | 被读成裸机 |
| “真内核” | 真机固件里的 `kernel_gb20x.elf`，但由模拟器执行 | 被读成真机执行 |
| “硅晶验证” | 物理卡上的注入实验（多为直通 VM） | 被读成芯片级探针 |
| “实证/实锤/A 级” | 作者自评，不等于证据级别 | 自评通胀 |
| “已验证” | 常指“在某个 profile/版本下跑通” | 跨版本套用 |

**建议**：第二步所有结论统一写成 `结论（E级别，固件/驱动版本，载体）`，例如“t0=4 分支只做 state 0→1（E3，610.57.04，QEMU lab）”。

---

## 5. 合并后的目标结构（第二步产物）

| 目标文件 | 内容 | 主要素材 |
|---|---|---|
| `STATUS.md` | 一页现状：模拟器链到哪、真机链到哪、卡/环境状态、对外投稿状态 | `gsp_qemu/README.md`+`PROGRESS.md`、`★V5_STATUS`（去混写）、`REVIVAL_FINAL`、`SUBMISSION_RECORD` |
| `FINDINGS.md` | 按证据级别分区的结论库（含“已裁决冲突”区） | `★V5`、`K31_FINAL_REPORT`、`FSP_ULTIMATE_FINDINGS`、`PRC_KNOB_MAP`、`MNOC_PORT0_PROTOCOL`、`power_governor_reverse/*/REPORT.md`、`fsp_ace_static/SUMMARY`、`F1_FINAL_VERDICT` |
| `OPEN_QUESTIONS.md` | 未闭合问题（含 C10/C11 等未裁决项、lab 未建模项） | `gsp_qemu/docs/LAB_BOOT.md` §尚未完成、`mclk4000_*` §未决、`FULL_REREAD_FINDINGS`、`LOGICAL_GAPS_AUDIT` |
| `NEXT_STEPS.md` | 按“能验证/能证伪”排序的下一步 | `gsp_qemu/PROGRESS.md`、`HANDOFF_CURRENT`、`★V5` §下一步、`power_governor_reverse` 未闭合项 |
| `docs/archive/` | 历史文档（见 §6） | — |

---

## 6. 建议归档清单（第二步执行；当前未动）

### 6.1 建议移动（先抽取独有事实）

| # | 原路径 | 目标 | 理由 | 替代 |
|---|---|---|---|---|
| 1 | `★AUTHORITATIVE_PROGRESS_20261011.md` | `docs/archive/status/` | 被 v2/v3/V4/V5 覆盖 | `★V5_STATUS` |
| 2 | `★AUTHORITATIVE_PROGRESS_v2_20261013.md` | `docs/archive/status/` | 被覆盖；先抽 C2/内存布局细节 | `★V5_STATUS` |
| 3 | `★AUTHORITATIVE_PROGRESS_v3_20261015.md` | `docs/archive/status/` | 被覆盖 | `★V5_STATUS` |
| 4 | `★V4_PROGRESS_20261016.md` | `docs/archive/status/` | 先抽 §3.4 msgq / §3.5 backend 解码 | `★V5_STATUS` |
| 5 | `C2_ENTRY_AUDIT_20260926.md` | `docs/archive/exploit/` | 残片、错名 | `C2_ENTRY_AUDIT_20261010` |
| 6 | `GSP_PRIVESC_FINAL_PLAN_202601008.md` | 同上 | 同日短稿、文件名笔误 | `GSP_PRIVESC_FINAL_PLAN_20261008` |
| 7 | `GSP_TOCTOU_SUCCESS.md` | 同上 | 结论强于证据（C6） | `ELF_TOCTOU_BREAKTHROUGH` + FINDINGS 更正 |
| 8 | `HANDOFF_K31.md` | `docs/archive/exploit/` | 页首自注过时 | `K31_FINAL_REPORT` |
| 9 | `DS_SESSION_K31_RECOVERY_20260929.md` | 同上 | 会话过程 | `K31_FINAL_REPORT` |
| 10 | `HOT_SWAP_GSP_ANALYSIS.md` | 同上 | 未验证构想 | FINDINGS “构想”区 |
| 11 | `GSP_61571_ADDR_MAP.md` | 同上 | 被 FINAL 覆盖 | `GSP_61571_FINAL_ADDR_MAP` |
| 12 | `COT_INJECTION_FINDINGS.md` | `docs/archive/fsp/` | 被最终判定否定（C7） | `COT_FINAL_VERDICT` |
| 13 | `FSP_COMPLETE_TRUST_CHAIN.md` | 同上 | 被 ULTIMATE 覆盖 | `FSP_ULTIMATE_FINDINGS` |
| 14 | `FSP_TRUST_CHAIN_MODEL.md` | 同上 | 合并进 FINDINGS 后归档 | FINDINGS（矩阵） |
| 15 | `FSP_LINE_COMPLETE_20260926.md` | 同上 | 早期总览 | FINDINGS |
| 16 | `CC_ATTEMPT3_RESULT.md` | 同上 | 一次性实验 | `BIOS_SLOT_CC_LOCK_RECOVERY` |
| 17 | `CC_FINAL_REPORT.md` | 同上 | 方案已被实测推翻（C14） | `BIOS_SLOT_CC_LOCK_RECOVERY` |
| 18 | `B4_B5_B7_RESULTS.md` | 同上 | 一次性负结果 | FINDINGS “已排除” |
| 19 | `FSP_INFOROM_PERSISTENCE_20260928.md` | 同上 | 单日记录 | FINDINGS |
| 20 | `INFOROM_QUERY_STATUS_20260928.md` | 同上 | 中间状态 | FINDINGS |
| 21 | `TOCTOU_FINAL_REPORT.md` | 同上 | 先改标题范围再归档（C5） | `SESSION_20260929_TOCTOU` |
| 22 | `HANDOFF_20261001.md` | `docs/archive/sessions/` | 旧交接 | `HANDOFF_CURRENT` / `STATUS.md` |
| 23 | `HANDOFF_20261006.md` | 同上 | 旧交接 | 同上 |
| 24 | `RESUME_BRIEF.md` | 同上 | 97KB 旧总集 | `★V5_STATUS` + FINDINGS |
| 25 | `WRAPUP_20260926.md` | 同上 | 旧阶段收尾 | FINDINGS |
| 26 | `FINAL_STATUS_20260928.md` | 同上 | 单日状态 | `EXPERIMENT_LOG` + FINDINGS |
| 27 | `SESSION_SUMMARY_20260930.md` | 同上 | 单日总结 | 同上 |
| 28 | `SESSION_SUMMARY_20261002.md` | 同上 | 单日总结 | 同上 |
| 29 | `FINAL_SESSION_20261002.md` | 同上 | 单日总结（去重后） | 同上 |
| 30 | `POST_REBOOT_QUEUE_20260926.md` | 同上 | 过期清单 | FINDINGS §恢复 |
| 31 | `POST_RESET_TODO_20260926.md` | 同上 | 过期清单 | 同上 |
| 32 | `DUAL_BIOS_CROSS_SLOT_FORENSICS_20261012.md` | `docs/archive/forensics/` | 合并取证后 | FINDINGS §BIOS |
| 33 | `ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md` | 同上 | 同上 | FINDINGS §BIOS |
| 34 | `GITHUB_NEW_ISSUE_WPR2_RECOVERY_BODY.md` | `docs/archive/submissions/` | D2 近重复 | PREVIEW |
| 35 | `BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md` | `docs/archive/power/` | 7 月版被细化 | `power_governor_reverse/*` |
| 36 | `BLACKWELL_VF_RUNTIME_GOVERNANCE_FINDINGS_20260724.md` | 同上 | 同上 | 同上 |
| 37 | `ASTRAL_STOCK_FAN_BASELINE_20260727.md` | `docs/archive/hardware/` | 单次基线 | `fan_runtime_mapping` + FINDINGS |
| 38 | `FAN_NOPTRS_REGOPS_ROUTE_20260728.md` | 同上 | 单次路线测试 | `FAN_CONTROL_DO_NOT_REPEAT` |
| 39 | `FAN_STATIC_AUDIT_FOLLOWUP_20260728.md` | 同上 | 一次性跟进 | `FAN_CONTROL_DO_NOT_REPEAT` |
| 40 | `gptpro_fan_route_followup_static_closure_20260727.md` | 同上 | 一次性收口 | 同上 |
| 41 | `handoff_fan0_runtime_address_prompt_20260726.md` | 同上 | 任务书 | 同上 |
| 42 | `L2_SLICE_RE_BRIEF.md` | 同上 | 任务书 | `L2_REENABLE_STATIC_FINDINGS` |
| 43 | `GB202_PARALLEL_WORK.md` | 同上 | 并行契约（旧线） | `L2_REENABLE_STATIC_FINDINGS` |
| 44 | `COMPILER_RE_BRIEF.md` | 同上 | 任务书 | `SM120_CACHE_AND_REGISTER_ISA` |
| 45 | `WATERLOOP_AM5_FAN_AUDIT_20260917.md` | `docs/archive/hardware/` | CPU 侧一次性审计 | — |
| 46 | `fsp_ace_static_20260927/CONTINUATION.md` | `docs/archive/fsp-static/` | 会话状态 | `SUMMARY.md` |
| 47 | `fsp_ace_static_20260927/GSP_EXEC_RUNBOOK.md` | 同上 | 施工单（未执行完） | `SUMMARY.md` |
| 48 | `fsp_ace_static_20260927/notes/CONTEXT_BRIEF.md` | 同上 | 战役上下文 | `SUMMARY.md` |
| 49 | `fsp_ace_static_20260927/artifacts/LIVE_SESSION_LOG_20260927.md` | 同上 | 原始会话日志 | `F1_FINAL_VERDICT` |
| 50 | `fsp_ace_static_20260927/artifacts/GADGET_INVENTORY.md` | 同上 | 工具性清单 | FINDINGS 附录 |
| 51 | `power_governor_reverse/bug_inverse/EXECUTION_BOARD_20260814.md` | `docs/archive/power/` | 任务板（已停） | `BUG_AWARE_INVERSE_GOVERNOR_TASK_BOARD` |
| 52 | `power_governor_reverse/bug_inverse/data_pipeline/TASKS.md` | 同上 | 任务板 | `data_pipeline/README.md` |
| 53 | `power_governor_reverse/bug_inverse/algorithm/SMOKE_REPORT_20260814.md` | 同上 | 冒烟记录 | `algorithm/README.md` |
| 54 | `power_governor_reverse/M40_HISTORICAL_CONTROL_LINEAGE_20260729.md` | 同上 | 历史背景 | — |

### 6.2 明确**不**移动

| 路径 | 原因 |
|---|---|
| `gspkm/**`、`driver_gpio_internal_610.43.03/**` | 厂商源码树；模板文件重复（D1）是上游事实，移动会破坏树完整性 |
| `gsp_qemu/**`（README/PROGRESS/docs） | 当前执行主线的活文档 |
| `power_governor_reverse/**/REPORT.md`（含子目录） | 阶段报告 + 证据，成对保留才有可审计性 |
| `power_governor_reverse/**/parent_capability/NOTES.md` 等报告内副本 | 见 D1：原地保留 + 交叉引用 |
| `fsp_ace_static_20260927/{SUMMARY,F1_FINAL_VERDICT,FSP_TRANSPORT_AUDIT,NVDM_DEMUX_AND_ENTRIES_AUDIT,RPC_LAYER_AUDIT,notes/FSP_SURFACE_REVISIONS,notes/PUBLIC_BASELINE_CHECK}` | 静态战果主体 |
| `VULN_INVENTORY`、`FSP_BUG_INVENTORY`（加注后）、`PRIMITIVE_CROSS_ANALYSIS` | 唯一的总目录/清单，改注不归档 |
| `AGENTS.md`、`COPY_MANIFEST.md` | 项目约定与拷贝溯源 |
| `docs/INDEX.md`、`docs/DEDUP_PLAN.md` | 本阶段产物 |

### 6.3 归档目录结构建议

```
docs/archive/
├── status/           # ★AUTHORITATIVE v1/v2/v3、V4 等旧权威档
├── exploit/          # C2 残片、K3-1 过程、615.71 初版、GSP TOCTOU
├── fsp/              # 信任链旧版、COT 初版、CC、TOCTOU（FMC）
├── fsp-static/       # fsp_ace_static 的过程性文档
├── sessions/         # HANDOFF/RESUME/SESSION_SUMMARY/POST_*
├── forensics/        # 双 BIOS/原版槽取证（合并后）
├── power/            # 7 月控制逻辑、任务板、历史脉络
├── hardware/         # 风扇/L2/ISA 的任务书与一次性实验
└── submissions/      # 重复的 issue 正文
```

每个归档文件顶部加一行元数据（第二步执行时写入）：

```
<!-- ARCHIVED 2026-10-18 | superseded-by: docs/FINDINGS.md#<anchor> | evidence: E3 | do-not-cite -->
```

---

## 7. 需要你确认的问题（影响第二步）

1. **权威档取舍**：`★V5_STATUS_20261016.md` 作为唯一权威档（V4 及更早归档），是否同意？V4 的 msgq/backend 细节会先抽取到 FINDINGS。
2. **冲突裁决**：C1（t0=4）、C3（dtor +8）、C4（RELEASE `0x93005B26`）、C10（completion wait ≠ mailbox busy）、C8（DoS 因果）按上文裁决写入 FINDINGS，是否有异议？
3. **归档范围**：§6.1 的 54 项是否全部移动？其中 37-45 属“风扇/L2/ISA 旧线”，如仍计划继续该线，可暂缓。
4. **是否允许改原文件**：C1/C3/C4/C8 的更正目前只写在本文档。第二步是**改原文件加注**（顶部加“⚠ 结论已更正，见 FINDINGS §x”），还是**只归档不改**？建议只加注、不改正文。
5. **厂商源码树**：`gspkm` 与 `driver_gpio_internal_610.43.03` 是否保留双份（当前建议保留，仅索引标注重复）？
6. **`gsp_qemu/docs/sources/open-iov-device-model.md`**：第三方文档副本是否移出 `gsp_qemu/docs/sources/`（避免被误当本项目设计），改放 `docs/archive/reference/`？
7. **旧路径**：是否只修 `gsp_qemu/README.md` 与 `gsp_qemu/docs/LAB_BOOT.md` 的 `cd`/输入路径（C17），其余历史文档保留原样？

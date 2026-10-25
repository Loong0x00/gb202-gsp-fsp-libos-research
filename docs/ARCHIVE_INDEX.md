# ARCHIVE_INDEX — 归档副本索引

> 更新：2026-10-18。共 **54** 份。
> **归档 = 复制，不是移动。** 原件全部保留在原路径，并继续作为引用源（`FINDINGS.md` 只引用原路径）。
> 副本与原件**字节相同**（下表 MD5 为全文件哈希，副本已逐一校验相等）。
> 取代者/原因写在本表，不写进副本，避免副本与原件产生差异。

## 目录结构

```text
docs/archive/<topic>/<原相对路径>
```

例：`docs/archive/power/power_governor_reverse/bug_inverse/EXECUTION_BOARD_20260814.md` 对应原件 `power_governor_reverse/bug_inverse/EXECUTION_BOARD_20260814.md`。

## status/ — 旧权威档（4）

| # | 原路径（原件仍在） | 归档副本 | 取代者 / 去向 | 原因 | 大小 | MD5 |
|---|---|---|---|---|---:|---|
| 1 | `★AUTHORITATIVE_PROGRESS_20261011.md` | `docs/archive/status/★AUTHORITATIVE_PROGRESS_20261011.md` | ★V5_STATUS_20261016.md + FINDINGS.md | 被 v2/v3/V4/V5 依次覆盖；自述“唯一权威”已失效 | 55572 | `21e445fef0e4deee3d11e56ef6771309` |
| 2 | `★AUTHORITATIVE_PROGRESS_v2_20261013.md` | `docs/archive/status/★AUTHORITATIVE_PROGRESS_v2_20261013.md` | ★V5_STATUS_20261016.md + FINDINGS.md | 被 v3/V4/V5 覆盖；独有 C2/内存布局细节已抽取 | 62338 | `ebc1448d666c7f11ff071a48a56e7a0f` |
| 3 | `★AUTHORITATIVE_PROGRESS_v3_20261015.md` | `docs/archive/status/★AUTHORITATIVE_PROGRESS_v3_20261015.md` | ★V5_STATUS_20261016.md + FINDINGS.md | 被 V4/V5 覆盖 | 28388 | `2de2daf57ff31a0f778b7467f11d4573` |
| 4 | `★V4_PROGRESS_20261016.md` | `docs/archive/status/★V4_PROGRESS_20261016.md` | ★V5_STATUS_20261016.md + FINDINGS.md | 被 V5 覆盖；§3.4 msgq / §3.5 backend 细节已抽取到 FINDINGS | 7904 | `c2c188a48351bc12dcae2320ce4af8f8` |

## exploit/ — 提权/C2/K3-1/TOCTOU 过程（7）

| # | 原路径（原件仍在） | 归档副本 | 取代者 / 去向 | 原因 | 大小 | MD5 |
|---|---|---|---|---|---:|---|
| 1 | `C2_ENTRY_AUDIT_20260926.md` | `docs/archive/exploit/C2_ENTRY_AUDIT_20260926.md` | C2_ENTRY_AUDIT_20261010.md | 文件名为 9-26，实为 10-11 的残片，无 H1；内容属 C2 主线 | 1479 | `8374d1343f1e4406a0cd52512395aae8` |
| 2 | `DS_SESSION_K31_RECOVERY_20260929.md` | `docs/archive/exploit/DS_SESSION_K31_RECOVERY_20260929.md` | K31_FINAL_REPORT.md | 会话过程记录，结论已入 FINAL_REPORT | 12347 | `76402cb20444e9422f2ac3ca4ebd0741` |
| 3 | `GSP_61571_ADDR_MAP.md` | `docs/archive/exploit/GSP_61571_ADDR_MAP.md` | GSP_61571_FINAL_ADDR_MAP.md | 地址初版，被 FINAL 覆盖 | 2534 | `5af98721f242b0ef20a47e2e19660a65` |
| 4 | `GSP_PRIVESC_FINAL_PLAN_202601008.md` | `docs/archive/exploit/GSP_PRIVESC_FINAL_PLAN_202601008.md` | GSP_PRIVESC_FINAL_PLAN_20261008.md | 文件名日期笔误（202601008），同日更早短稿 | 1233 | `8a03120fb18c01efa32b2b3214c429e7` |
| 5 | `GSP_TOCTOU_SUCCESS.md` | `docs/archive/exploit/GSP_TOCTOU_SUCCESS.md` | ELF_TOCTOU_BREAKTHROUGH.md + CORRECTIONS.md C-07 | 标题“成功/绕过签名”强于证据；只证明写入到达物理内存 | 2816 | `a3b29e11f88e8febed1b9433b56e3990` |
| 6 | `HANDOFF_K31.md` | `docs/archive/exploit/HANDOFF_K31.md` | K31_FINAL_REPORT.md | 页首自注两处已过时 | 8387 | `a3fc38b5b3891971c0ae555db8641c19` |
| 7 | `HOT_SWAP_GSP_ANALYSIS.md` | `docs/archive/exploit/HOT_SWAP_GSP_ANALYSIS.md` | （无直接替代；构想保留于 FINDINGS 叙述） | 未验证的热切换构想 | 4563 | `f557e1a68c145b25366ed3aed1aa7880` |

## fsp/ — FSP 信任链/通道/CC/TOCTOU（10）

| # | 原路径（原件仍在） | 归档副本 | 取代者 / 去向 | 原因 | 大小 | MD5 |
|---|---|---|---|---|---:|---|
| 1 | `B4_B5_B7_RESULTS.md` | `docs/archive/fsp/B4_B5_B7_RESULTS.md` | FINDINGS.md（已排除项） | 一次性负结果 | 3647 | `2478153b824ab503f63ec2389fe87de0` |
| 2 | `CC_ATTEMPT3_RESULT.md` | `docs/archive/fsp/CC_ATTEMPT3_RESULT.md` | BIOS_SLOT_CC_LOCK_RECOVERY.md | 单次 CC 实验记录，恢复方案以 v2 为准 | 2381 | `ce7fe8b4a9a7e08a31ec887ed528e4ae` |
| 3 | `CC_FINAL_REPORT.md` | `docs/archive/fsp/CC_FINAL_REPORT.md` | BIOS_SLOT_CC_LOCK_RECOVERY.md | 其“切槽+prc_rw”方案已于 9-29 实测失败（C-12） | 2734 | `152fdc36e58cc8f7de2b9fe44003a7f0` |
| 4 | `COT_INJECTION_FINDINGS.md` | `docs/archive/fsp/COT_INJECTION_FINDINGS.md` | COT_FINAL_VERDICT.md | 初版“按内容响应”已被最终判定否定（C-09 同类） | 2374 | `93d304891b5204e4cc8b9a714c56f54b` |
| 5 | `FSP_COMPLETE_TRUST_CHAIN.md` | `docs/archive/fsp/FSP_COMPLETE_TRUST_CHAIN.md` | FSP_ULTIMATE_FINDINGS.md | 信任链模型第一版，被最终研究覆盖 | 6445 | `8b26c66e4838416e53ceba01a6aac06a` |
| 6 | `FSP_INFOROM_PERSISTENCE_20260928.md` | `docs/archive/fsp/FSP_INFOROM_PERSISTENCE_20260928.md` | FINDINGS.md | 单日研究记录，事实已抽取 | 5097 | `353d07b7ef3df3c91e397a58d693b7d7` |
| 7 | `FSP_LINE_COMPLETE_20260926.md` | `docs/archive/fsp/FSP_LINE_COMPLETE_20260926.md` | FINDINGS.md + FSP_ULTIMATE_FINDINGS.md | 早期 FSP 线总览，结论已被细化/更正 | 21170 | `f1d1c9fcdac7ccf886f68c68fc3c74d6` |
| 8 | `FSP_TRUST_CHAIN_MODEL.md` | `docs/archive/fsp/FSP_TRUST_CHAIN_MODEL.md` | FINDINGS.md FSP-01/FSP-02 | 唯一完整实验矩阵已抽取为 FINDINGS 条目 | 3960 | `188c5c92de8610939f5f40c9e9fc8644` |
| 9 | `INFOROM_QUERY_STATUS_20260928.md` | `docs/archive/fsp/INFOROM_QUERY_STATUS_20260928.md` | FINDINGS.md | 中间状态记录 | 3229 | `dc04c41d41354f3698f544d8363c4943` |
| 10 | `TOCTOU_FINAL_REPORT.md` | `docs/archive/fsp/TOCTOU_FINAL_REPORT.md` | SESSION_20260929_TOCTOU.md + CORRECTIONS.md C-08 | “无漏检窗口”只对 FMC 成立，标题未限定 | 2966 | `ec74f6429dc709368bfde9bac7c3c770` |

## fsp-static/ — FSP 静态战役过程文档（5）

| # | 原路径（原件仍在） | 归档副本 | 取代者 / 去向 | 原因 | 大小 | MD5 |
|---|---|---|---|---|---:|---|
| 1 | `fsp_ace_static_20260927/CONTINUATION.md` | `docs/archive/fsp-static/fsp_ace_static_20260927/CONTINUATION.md` | fsp_ace_static_20260927/SUMMARY.md | 会话状态，结论已入 SUMMARY | 6866 | `5b729b5fe1d405c02fe616e70647508b` |
| 2 | `fsp_ace_static_20260927/GSP_EXEC_RUNBOOK.md` | `docs/archive/fsp-static/fsp_ace_static_20260927/GSP_EXEC_RUNBOOK.md` | fsp_ace_static_20260927/SUMMARY.md | 施工单，未执行完 | 3632 | `4e9d05a6ffe25e2420626d32a6635452` |
| 3 | `fsp_ace_static_20260927/artifacts/GADGET_INVENTORY.md` | `docs/archive/fsp-static/fsp_ace_static_20260927/artifacts/GADGET_INVENTORY.md` | FINDINGS.md（附录） | 工具性清单 | 421 | `a53f64fb8fa623ab01eb93fd535ae143` |
| 4 | `fsp_ace_static_20260927/artifacts/LIVE_SESSION_LOG_20260927.md` | `docs/archive/fsp-static/fsp_ace_static_20260927/artifacts/LIVE_SESSION_LOG_20260927.md` | fsp_ace_static_20260927/F1_FINAL_VERDICT.md | 原始会话日志，定级已入 F1 | 5467 | `e3ffecc374da9db2f3a323774dd98be5` |
| 5 | `fsp_ace_static_20260927/notes/CONTEXT_BRIEF.md` | `docs/archive/fsp-static/fsp_ace_static_20260927/notes/CONTEXT_BRIEF.md` | fsp_ace_static_20260927/SUMMARY.md | 战役上下文 | 4104 | `ebe9d68df0868677c88fb3a27d0e9c14` |

## sessions/ — 交接/会话总结/待办（10）

| # | 原路径（原件仍在） | 归档副本 | 取代者 / 去向 | 原因 | 大小 | MD5 |
|---|---|---|---|---|---:|---|
| 1 | `FINAL_SESSION_20261002.md` | `docs/archive/sessions/FINAL_SESSION_20261002.md` | FINDINGS.md | 单日总结，事实已抽取 | 7216 | `336f7dfec198d49a02c8bd5f34de6756` |
| 2 | `FINAL_STATUS_20260928.md` | `docs/archive/sessions/FINAL_STATUS_20260928.md` | EXPERIMENT_LOG_20260929_30.md + FINDINGS.md | 单日状态记录 | 6424 | `68e7f16edd7b26b0ff21c2508feb3adc` |
| 3 | `HANDOFF_20261001.md` | `docs/archive/sessions/HANDOFF_20261001.md` | HANDOFF_CURRENT.md + STATUS.md | 旧交接 | 6369 | `f8e2384d8dc8c570d2b0af459706f915` |
| 4 | `HANDOFF_20261006.md` | `docs/archive/sessions/HANDOFF_20261006.md` | STATUS.md | 旧交接；FSP boot 窗口结论已入 FINDINGS | 5437 | `1a066b2aaee5a321aa9edaf009f9631a` |
| 5 | `POST_REBOOT_QUEUE_20260926.md` | `docs/archive/sessions/POST_REBOOT_QUEUE_20260926.md` | FINDINGS.md（REC） | 过期待办 | 5377 | `991a54ca6142859892e9fa7367ef1606` |
| 6 | `POST_RESET_TODO_20260926.md` | `docs/archive/sessions/POST_RESET_TODO_20260926.md` | FINDINGS.md（REC） | 过期待办 | 3728 | `acb0cfbe958fc80462c5846cf81e691b` |
| 7 | `RESUME_BRIEF.md` | `docs/archive/sessions/RESUME_BRIEF.md` | STATUS.md + FINDINGS.md | 97KB 旧总集（9-26 前），已被现行文档取代 | 97569 | `8acb59a400448f08b4caddb991a15eb0` |
| 8 | `SESSION_SUMMARY_20260930.md` | `docs/archive/sessions/SESSION_SUMMARY_20260930.md` | EXPERIMENT_LOG_20260929_30.md | 单日总结，时间线已并入实验记录 | 1819 | `793b058eeddb1ae77d517af14cec995d` |
| 9 | `SESSION_SUMMARY_20261002.md` | `docs/archive/sessions/SESSION_SUMMARY_20261002.md` | FINDINGS.md | 单日总结，事实已抽取 | 5051 | `03283d46e838d52f8aa297d45d38585b` |
| 10 | `WRAPUP_20260926.md` | `docs/archive/sessions/WRAPUP_20260926.md` | FINDINGS.md（HW/REC） | 旧阶段收尾；目标未达成的结论已保留 | 13961 | `bbf1b7cd806d2ff76e97cafc5c4d9b59` |

## forensics/ — BIOS 取证（2）

| # | 原路径（原件仍在） | 归档副本 | 取代者 / 去向 | 原因 | 大小 | MD5 |
|---|---|---|---|---|---:|---|
| 1 | `DUAL_BIOS_CROSS_SLOT_FORENSICS_20261012.md` | `docs/archive/forensics/DUAL_BIOS_CROSS_SLOT_FORENSICS_20261012.md` | FINDINGS.md REC-04 | 跨槽取证结论已抽取 | 9392 | `b6f6a60cad9e8eba8f95193b523f3ec3` |
| 2 | `ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md` | `docs/archive/forensics/ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md` | FINDINGS.md REC-05 | 单槽取证结论已抽取 | 12853 | `d30ee94a422ff5113647924dbc914abd` |

## submissions/ — 投稿重复稿（1）

| # | 原路径（原件仍在） | 归档副本 | 取代者 / 去向 | 原因 | 大小 | MD5 |
|---|---|---|---|---|---:|---|
| 1 | `GITHUB_NEW_ISSUE_WPR2_RECOVERY_BODY.md` | `docs/archive/submissions/GITHUB_NEW_ISSUE_WPR2_RECOVERY_BODY.md` | GITHUB_NEW_ISSUE_WPR2_RECOVERY_PREVIEW.md | 与 PREVIEW 近重复（Jaccard 0.97） | 3053 | `99c26c06af11bd18b39fbabe2e747a05` |

## power/ — 旧控制逻辑/任务板/历史（6）

| # | 原路径（原件仍在） | 归档副本 | 取代者 / 去向 | 原因 | 大小 | MD5 |
|---|---|---|---|---|---:|---|
| 1 | `BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md` | `docs/archive/power/BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md` | power_governor_reverse/ 系列 | 7 月底稿，已被 8-9 月静态系列细化 | 85511 | `54db11d403db294b227282595cdf5f43` |
| 2 | `BLACKWELL_VF_RUNTIME_GOVERNANCE_FINDINGS_20260724.md` | `docs/archive/power/BLACKWELL_VF_RUNTIME_GOVERNANCE_FINDINGS_20260724.md` | power_governor_reverse/ 系列 | 同上 | 68059 | `fe2015ae8032b662afabab35ba6f867e` |
| 3 | `power_governor_reverse/M40_HISTORICAL_CONTROL_LINEAGE_20260729.md` | `docs/archive/power/power_governor_reverse/M40_HISTORICAL_CONTROL_LINEAGE_20260729.md` | （无；历史背景） | Fermi→Blackwell 背景材料 | 12478 | `2b16575784853492aec1a0609b03f413` |
| 4 | `power_governor_reverse/bug_inverse/EXECUTION_BOARD_20260814.md` | `docs/archive/power/power_governor_reverse/bug_inverse/EXECUTION_BOARD_20260814.md` | BUG_AWARE_INVERSE_GOVERNOR_TASK_BOARD_20260814.md | 已停止的任务板 | 8961 | `adcdc13d3df08ae3bc3936dd18d31cad` |
| 5 | `power_governor_reverse/bug_inverse/algorithm/SMOKE_REPORT_20260814.md` | `docs/archive/power/power_governor_reverse/bug_inverse/algorithm/SMOKE_REPORT_20260814.md` | power_governor_reverse/bug_inverse/algorithm/README.md | 冒烟记录，算法说明仍有效 | 5761 | `9a8a20243fd975924acff03bdfb0c46f` |
| 6 | `power_governor_reverse/bug_inverse/data_pipeline/TASKS.md` | `docs/archive/power/power_governor_reverse/bug_inverse/data_pipeline/TASKS.md` | power_governor_reverse/bug_inverse/data_pipeline/README.md | 任务板，管线说明仍有效 | 2535 | `b792fddbf153fa64e2cdf2400c5172f0` |

## hardware/ — 风扇/L2/ISA 任务书与一次性实验（9）

| # | 原路径（原件仍在） | 归档副本 | 取代者 / 去向 | 原因 | 大小 | MD5 |
|---|---|---|---|---|---:|---|
| 1 | `ASTRAL_STOCK_FAN_BASELINE_20260727.md` | `docs/archive/hardware/ASTRAL_STOCK_FAN_BASELINE_20260727.md` | fan_runtime_mapping_20260724.md + FINDINGS.md HW-01 | 单次基线，映射结论已抽取 | 2842 | `0e227e3d7b21669a4bc6b18c4368370c` |
| 2 | `COMPILER_RE_BRIEF.md` | `docs/archive/hardware/COMPILER_RE_BRIEF.md` | SM120_CACHE_AND_REGISTER_ISA.md | 任务书 | 3036 | `32c6ced7d4e39dcdde62f3fba8bec85c` |
| 3 | `FAN_NOPTRS_REGOPS_ROUTE_20260728.md` | `docs/archive/hardware/FAN_NOPTRS_REGOPS_ROUTE_20260728.md` | FAN_CONTROL_DO_NOT_REPEAT_20260727.md | 单次路线测试 | 2321 | `d9f98bab6416a38736add1562f86ee46` |
| 4 | `FAN_STATIC_AUDIT_FOLLOWUP_20260728.md` | `docs/archive/hardware/FAN_STATIC_AUDIT_FOLLOWUP_20260728.md` | FAN_CONTROL_DO_NOT_REPEAT_20260727.md | 一次性静态跟进 | 8723 | `c7a8a9344ccc3d0e2dd49cd5cd1a5e9a` |
| 5 | `GB202_PARALLEL_WORK.md` | `docs/archive/hardware/GB202_PARALLEL_WORK.md` | L2_REENABLE_STATIC_FINDINGS.md | 并行契约（旧线） | 29408 | `c824f76312d0467e142d4c8bffc424eb` |
| 6 | `L2_SLICE_RE_BRIEF.md` | `docs/archive/hardware/L2_SLICE_RE_BRIEF.md` | L2_REENABLE_STATIC_FINDINGS.md | 任务书，结论文档仍有效 | 7528 | `38f23954d4927f444dc816defe554461` |
| 7 | `WATERLOOP_AM5_FAN_AUDIT_20260917.md` | `docs/archive/hardware/WATERLOOP_AM5_FAN_AUDIT_20260917.md` | （无；CPU 侧一次性审计） | 与 GPU 主线无关 | 3623 | `b562d452622373a889b1dfd0af9a645b` |
| 8 | `gptpro_fan_route_followup_static_closure_20260727.md` | `docs/archive/hardware/gptpro_fan_route_followup_static_closure_20260727.md` | FAN_CONTROL_DO_NOT_REPEAT_20260727.md | 一次性静态收口 | 5920 | `fa0f8862979e2bc688d09190bf6fa904` |
| 9 | `handoff_fan0_runtime_address_prompt_20260726.md` | `docs/archive/hardware/handoff_fan0_runtime_address_prompt_20260726.md` | FAN_CONTROL_DO_NOT_REPEAT_20260727.md | 任务书 | 12128 | `4b32d2773c691043b7ad58bd145c7734` |

## 校验方式

```sh
cd /home/user/gsp_libos_clean
while IFS='|' read -r src dst; do
  cmp -s "$src" "$dst" || echo "DIFF: $src"
done <<'EOF'
★AUTHORITATIVE_PROGRESS_20261011.md|docs/archive/status/★AUTHORITATIVE_PROGRESS_20261011.md
★AUTHORITATIVE_PROGRESS_v2_20261013.md|docs/archive/status/★AUTHORITATIVE_PROGRESS_v2_20261013.md
★AUTHORITATIVE_PROGRESS_v3_20261015.md|docs/archive/status/★AUTHORITATIVE_PROGRESS_v3_20261015.md
★V4_PROGRESS_20261016.md|docs/archive/status/★V4_PROGRESS_20261016.md
C2_ENTRY_AUDIT_20260926.md|docs/archive/exploit/C2_ENTRY_AUDIT_20260926.md
DS_SESSION_K31_RECOVERY_20260929.md|docs/archive/exploit/DS_SESSION_K31_RECOVERY_20260929.md
GSP_61571_ADDR_MAP.md|docs/archive/exploit/GSP_61571_ADDR_MAP.md
GSP_PRIVESC_FINAL_PLAN_202601008.md|docs/archive/exploit/GSP_PRIVESC_FINAL_PLAN_202601008.md
GSP_TOCTOU_SUCCESS.md|docs/archive/exploit/GSP_TOCTOU_SUCCESS.md
HANDOFF_K31.md|docs/archive/exploit/HANDOFF_K31.md
HOT_SWAP_GSP_ANALYSIS.md|docs/archive/exploit/HOT_SWAP_GSP_ANALYSIS.md
B4_B5_B7_RESULTS.md|docs/archive/fsp/B4_B5_B7_RESULTS.md
CC_ATTEMPT3_RESULT.md|docs/archive/fsp/CC_ATTEMPT3_RESULT.md
CC_FINAL_REPORT.md|docs/archive/fsp/CC_FINAL_REPORT.md
COT_INJECTION_FINDINGS.md|docs/archive/fsp/COT_INJECTION_FINDINGS.md
FSP_COMPLETE_TRUST_CHAIN.md|docs/archive/fsp/FSP_COMPLETE_TRUST_CHAIN.md
FSP_INFOROM_PERSISTENCE_20260928.md|docs/archive/fsp/FSP_INFOROM_PERSISTENCE_20260928.md
FSP_LINE_COMPLETE_20260926.md|docs/archive/fsp/FSP_LINE_COMPLETE_20260926.md
FSP_TRUST_CHAIN_MODEL.md|docs/archive/fsp/FSP_TRUST_CHAIN_MODEL.md
INFOROM_QUERY_STATUS_20260928.md|docs/archive/fsp/INFOROM_QUERY_STATUS_20260928.md
TOCTOU_FINAL_REPORT.md|docs/archive/fsp/TOCTOU_FINAL_REPORT.md
fsp_ace_static_20260927/CONTINUATION.md|docs/archive/fsp-static/fsp_ace_static_20260927/CONTINUATION.md
fsp_ace_static_20260927/GSP_EXEC_RUNBOOK.md|docs/archive/fsp-static/fsp_ace_static_20260927/GSP_EXEC_RUNBOOK.md
fsp_ace_static_20260927/artifacts/GADGET_INVENTORY.md|docs/archive/fsp-static/fsp_ace_static_20260927/artifacts/GADGET_INVENTORY.md
fsp_ace_static_20260927/artifacts/LIVE_SESSION_LOG_20260927.md|docs/archive/fsp-static/fsp_ace_static_20260927/artifacts/LIVE_SESSION_LOG_20260927.md
fsp_ace_static_20260927/notes/CONTEXT_BRIEF.md|docs/archive/fsp-static/fsp_ace_static_20260927/notes/CONTEXT_BRIEF.md
FINAL_SESSION_20261002.md|docs/archive/sessions/FINAL_SESSION_20261002.md
FINAL_STATUS_20260928.md|docs/archive/sessions/FINAL_STATUS_20260928.md
HANDOFF_20261001.md|docs/archive/sessions/HANDOFF_20261001.md
HANDOFF_20261006.md|docs/archive/sessions/HANDOFF_20261006.md
POST_REBOOT_QUEUE_20260926.md|docs/archive/sessions/POST_REBOOT_QUEUE_20260926.md
POST_RESET_TODO_20260926.md|docs/archive/sessions/POST_RESET_TODO_20260926.md
RESUME_BRIEF.md|docs/archive/sessions/RESUME_BRIEF.md
SESSION_SUMMARY_20260930.md|docs/archive/sessions/SESSION_SUMMARY_20260930.md
SESSION_SUMMARY_20261002.md|docs/archive/sessions/SESSION_SUMMARY_20261002.md
WRAPUP_20260926.md|docs/archive/sessions/WRAPUP_20260926.md
DUAL_BIOS_CROSS_SLOT_FORENSICS_20261012.md|docs/archive/forensics/DUAL_BIOS_CROSS_SLOT_FORENSICS_20261012.md
ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md|docs/archive/forensics/ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md
GITHUB_NEW_ISSUE_WPR2_RECOVERY_BODY.md|docs/archive/submissions/GITHUB_NEW_ISSUE_WPR2_RECOVERY_BODY.md
BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md|docs/archive/power/BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md
BLACKWELL_VF_RUNTIME_GOVERNANCE_FINDINGS_20260724.md|docs/archive/power/BLACKWELL_VF_RUNTIME_GOVERNANCE_FINDINGS_20260724.md
power_governor_reverse/M40_HISTORICAL_CONTROL_LINEAGE_20260729.md|docs/archive/power/power_governor_reverse/M40_HISTORICAL_CONTROL_LINEAGE_20260729.md
power_governor_reverse/bug_inverse/EXECUTION_BOARD_20260814.md|docs/archive/power/power_governor_reverse/bug_inverse/EXECUTION_BOARD_20260814.md
power_governor_reverse/bug_inverse/algorithm/SMOKE_REPORT_20260814.md|docs/archive/power/power_governor_reverse/bug_inverse/algorithm/SMOKE_REPORT_20260814.md
power_governor_reverse/bug_inverse/data_pipeline/TASKS.md|docs/archive/power/power_governor_reverse/bug_inverse/data_pipeline/TASKS.md
ASTRAL_STOCK_FAN_BASELINE_20260727.md|docs/archive/hardware/ASTRAL_STOCK_FAN_BASELINE_20260727.md
COMPILER_RE_BRIEF.md|docs/archive/hardware/COMPILER_RE_BRIEF.md
FAN_NOPTRS_REGOPS_ROUTE_20260728.md|docs/archive/hardware/FAN_NOPTRS_REGOPS_ROUTE_20260728.md
FAN_STATIC_AUDIT_FOLLOWUP_20260728.md|docs/archive/hardware/FAN_STATIC_AUDIT_FOLLOWUP_20260728.md
GB202_PARALLEL_WORK.md|docs/archive/hardware/GB202_PARALLEL_WORK.md
L2_SLICE_RE_BRIEF.md|docs/archive/hardware/L2_SLICE_RE_BRIEF.md
WATERLOOP_AM5_FAN_AUDIT_20260917.md|docs/archive/hardware/WATERLOOP_AM5_FAN_AUDIT_20260917.md
gptpro_fan_route_followup_static_closure_20260727.md|docs/archive/hardware/gptpro_fan_route_followup_static_closure_20260727.md
handoff_fan0_runtime_address_prompt_20260726.md|docs/archive/hardware/handoff_fan0_runtime_address_prompt_20260726.md
EOF
```

## 未归档但可能被误认为“重复”的项

- `gspkm/**` 与 `driver_gpio_internal_610.43.03/**` 的 `CODE_OF_CONDUCT/CONTRIBUTING/SECURITY`：字节相同，但属厂商源码树，移动会破坏 vendor tree；原地保留。
- `power_governor_reverse/gsp_mclk*_review_*/parent_capability/NOTES.md` 与 `.../max_capability/NOTES.md`：字节相同；属报告内部副本，原地保留并在索引中标“重复”。
- `.pytest_cache/README.md`（3 份）：工具生成，不属文档，未归档。

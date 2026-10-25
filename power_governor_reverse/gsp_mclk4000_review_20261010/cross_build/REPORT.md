# GSP 570.144 / R610.57 与 MODS 570.215 的 MCLK +3999/+4000 静态交叉复核

日期：2026-10-11。范围：只读检查本地 GSP/PMU ELF、已保存的 MODS 日志、ROM 及既有静态逆向材料；不访问 GPU、不运行 MODS/固件、不修改旧 Ghidra DB。本文把“VBIOS OC offset 上限”“运行时支持频率”和“PMU transaction 成功”视为不同边界，不把公开 `kernel_gsp.c` 当作 GPU-RM 完整源码。

## 结论摘要

1. `+3999/+4000 MHz` 的可复核算式是 **VBIOS MCLK relation 12 基准 14,001 MHz + MODS signed offset**：分别生成绝对目标 18,000,000 / 18,001,000 kHz。既有记录中 18,000 MHz 路径完成（实测约 17,982 MHz），18,001 MHz 在显存测试前失败。ROM 的 MCLK offset range 是 `-1000..+5000 MHz`；host RM 验证器 `0x6e204c0` 使用含端点比较，接受 `+4000 MHz`。这只是可表达/可接受的 OC offset，不等于物理时钟能力。
2. 与故障场景相配的 R570.215 runtime PMU ELF 中，MCLK setter `0x20633630` 在状态门通过时把绝对 target 保存到对象 `+0x68`；worker `0x2063469e` 将其原样放进 command-0 DATA，再由 `0x206358ca -> 0x205d19ce` 发出。已恢复的这一段没有 `4000000` / `18000000` / `18001000` 比较，没有 18 GHz hardcap、频率 round/clamp 或 16-bit target 截断。
3. `+4000` 的现场不是“收到 PMU 非零拒绝 response”：R570.215 PMU 在等待 completion 失败后于 `0x205d1acc` 带 marker `0x25728` 断言；response 检查只在 wait 成功后执行。host 随后等 CHANGE_SEQ_PMU 超时并报 `0x65`。设备端为什么没有 completion 仍未知。
4. R610.57.04 的 Clock Programming 解析证据没有 parser-level MCLK off-by-one：Clocks 表将 MCLK 映到 relation/program IDs **8..12（含端点）**，恰为五行；Clock Programming 表有 25 行，0..17 active、18..24 disabled。ROM relation 12 的键为 14,001 MHz。R610 当前公开 MCLK 支持列表最大值却是 15,001 MHz；它是另一 build/运行态能力，不能反推 R570.215 的故障阈值。
5. 在当前证据中**没有发现** Clock Programming/timing 键选择处的 off-by-one 或 `+4000`/18,000 MHz 固件 hardcap，因而没有可报告的“错误比较原始地址”。缺少 R570.144 OC/VBIOS parser 及 timing-selector 的闭合反编译；“未发现”不等于全路径已证明不存在。

## Build 与证据身份

| 对象 | 身份与 SHA-256 | 可用于何种结论 |
|---|---|---|
| R570.144 GSP 主 ELF | `ghidra_static/gsp_inner_570144_main.elf`，RISC-V；SHA-256 `6c36425881780a14e0c3f03622784367a11892d64ee131ef2f2ce3029d7a4ff3`；ELF 字符串含 `570.144` | 只代表这个 570.144 GSP image；不是 MODS 570.215 运行镜像身份的替代品 |
| R610 GSP | 既有文档标定 driver/GSP 为 R610.57.04；inner ELF SHA-256 `88cb25e9940d9b242a8dc518291d028519b1f7b734954c6d358112b4af0a690e`。R610 RX parser evidence segment `gsp61057_rx_full.bin` SHA-256 `50614073f1ca73d4a10e66bdba15e557763b402c75b203a8950161c0afe59085` | BIT C、Clocks/Clock Programming parser 和 runtime INFO 静态证据 |
| R570.215 runtime PMU | `power_governor_reverse/gb202_r570215_runtime_pmu.elf`，SHA-256 `2eef42f0b434990d2c9669124199a912e8e16d8480d1c9a74d46d75e1575b93b` | target → command-0 DATA / timeout-response 路径 |
| MODS 570.215 现场 | 既有 `edc18001-auto` / `edc18001-msvdd1050` 日志和 MODS 570.215 静态导出 | 日志显示 `GSP-RM Disabled`；故障现场不能说成经过 R570.144 GSP handler。当前报告没有独立复核 host MODS 原始 ELF 的 SHA-256，host 地址只按已有 570.215 静态证据引用 |

## 频率边界：offset、ROM key 与 runtime maximum 不是同一概念

### MODS 570.215 / 对应 ROM 场景

既有 ROM 核对对象为完整 Astral/XOC ROM `281814.rom`（SHA-256 `0a1a511e72d707f513aab02a1d1ccfa8a78347d56915b0c922398724193ec97d`），与本机 sysfs VBIOS 的非零内容一致。Clocks v0x50 中 MCLK 关系范围为 `8..12`；packed signed range 为 `-1000..+5000 MHz`。ROM 最后 MCLK key/relation 12 为 `14,001,000 kHz`。

| MODS 请求 | relation-12 base | signed offset | 绝对 target |
|---:|---:|---:|---:|
| 18,000 MHz | 14,001 MHz | +3,999 MHz = 3,999,000 kHz | 18,000,000 kHz |
| 18,001 MHz | 14,001 MHz | +4,000 MHz = 4,000,000 kHz | 18,001,000 kHz |

MODS 日志直接记录 `Offsetting clock vf relationship entry 12 by 4000000kHz`。host RM `0x6e204c0` 比较控制 offset 与取得的 max/min range，成功条件为 `offset <= max && min <= offset`；因此 +4,000,000 在该 VBIOS 范围内，正常 host validator 不应以越界拒绝。`0x6e20340` / `0x6e201c0` 是取得 max/min 的相关 helper。其语义是 OC 输入范围校验，不是绝对 MCLK 上限。

### R610.57.04 交叉对照

R610 RISC-V GSP 的 parser 坐标：Clocks v0x50 `0x0117e9c4`；Clock Programming v0x50 `0x0118d228`。BIT C 的 Clocks pointer 在 `C+0x08`，Clock Programming pointer 在 `C+0x0c`。解析所得 Clocks MCLK 映射为 8..12；25 个 Clock Programming row 的 0..17 active，18..24 为 disabled/sentinel。MCLK rows 8..12 含首尾共 5 行，relation 12 的 ROM key 为 14,001 MHz。

R610 live `CLK_DOMAIN_GET_INFO` 的 MCLK 列表为 `405, 810, 7001, 13801, 15001 MHz`，最大值 15,001 MHz（既有 read-only RPC 证据）。ROM 14,001 到 runtime 15,001 的 +1,000 MHz 差异说明 ROM key 不是最终 runtime capability。R610 当前 offset range 同样读为 `-1000..+5000 MHz`，但这只是 R610 构建/运行态；不能拿它当 R570.215 的 firmware cap。反过来，R570.215 接受 +4,000 MHz offset 也不意味着它支持 18,001 MHz 绝对 target。

## +3999/+4000 target 数据流与 PMU failure 分支

### 从 VBIOS relation 到 PMU target

```text
Clocks v0x50 MCLK relation 12 (ROM key 14,001,000 kHz)
  + MODS relation offset (3,999,000 / 4,000,000 kHz)
  = absolute request (18,000,000 / 18,001,000 kHz)
  -> R570.215 PMU MCLK setter 0x20633630
       state gate: global disable / override bit / reference ±2000 / old target ±500
       update object+0x68 with request only on state=2
  -> worker 0x2063469e copies object+0x68 to command-0 input DATA
  -> wrapper 0x206358ca -> primitive 0x205d19ce
       DATA store first, then tagged command store; command=0
       wait for completion (wrapper timeout argument 95,000; converted budget 1,900 ticks)
```

只有 MCLK setter 的状态门通过，request 才会更新 `+0x68` 并送入 worker；runtime reference、old target 与 gate 值没有保存，所以不能声称此次 18,000/18,001 的 DATA 实值来自故障转储。指令级条件演算表明，若已发送，其 DATA 是原始绝对 kHz 值：`18,000,000 = 0x0112a880`，`18,001,000 = 0x0112ac68`；DATA 相差 1,000，metadata 为零。该路径不加回 VBIOS base、不做单位换算或频率表量化。

### 失败不是负 response

PMU primitive 在 wait 失败处 `0x205d1acc–0x205d1ad4` 设 marker `0x25728` 并进入共享 `ebreak`。wait 成功后才检查 `0x01402808` 的 sequence/command，并读取 `0x01402828` 的 response word。故障现场没有经过这条正常 response 校验；它是 completion timeout，不是被证实的 non-zero response rejection。PMU 停止后 host 的 CHANGE_SEQ_PMU 等待超时，错误状态 `0x65` (`NV_ERR_TIMEOUT`)。R570.215 ELF 的 command-0 发送段没有发现 4,000,000、18,000,000 或 18,001,000 常量/阈值，也没有主动返回 hardcap error。

另有不同的 **GSP PERF synchronous PMU-RPC** 失败处理，不能与上述 command-0 timeout 混为一谈：

- R570.144 GSP `0x016395a8`（既有导出名 `perf_masked_worker`）调用 PMU helper `0x017ba344`，构造 0x214-byte、unit `0x1300`、type `0x0d` 消息。仅当返回状态为 0 时才按 mask 导入结果并设置 valid byte；非零时记录错误、设置 fault 状态后 `ebreak`，不是向 host 返回一条正常的拒绝结果。
- R610.57.04 GSP `0x016bcae0` 使用 PMU helper `0x0182b0a8` 进行 0x214-byte、unit `0x1300`、type `0x0c` RPC。成功才导入 masked domain words；失败路径同样记错误/置 fault 并 `ebreak`。这是 R610 与 R570 的 protocol migration（R570 的 C/D/E 对应 R610 的 inline C/D 路径变化），不是 command-0 completion 的 response handler。

因此，不能用 GSP RPC 的 `status!=0 -> ebreak` 解释本次 `0x25728`：日志明确落在 R570.215 runtime PMU 等待完成失败分支，且 MODS 日志显示 GSP-RM disabled。

## Off-by-one / hardcap 检查结果

- **ROM/解析边界没有证据支持 row 12 被漏掉**：MCLK `8..12` 是 5 个 inclusive IDs；R610 Clocks / Clock Programming parser 的 row count/stride 与该范围一致。该结果只排除了已恢复 parser 的区间端点错误，不证明所有下游 selector 都没有错误。
- **host offset compare 不存在 +4000 exclusive 上界**：range 是 +5000，且 validator 两端均包含；它不会在 4,000,000 kHz 把输入拒绝。
- **未找到 18,000/18,001 MHz selector 或 timing hardcap 地址**：R570.215 command-0 sender 是 raw target pass-through；R610 当前 runtime max 15,001 MHz 是不同 build、不同 endpoint 的 capability 证据，不是 R570.215 故障首因。
- **+3999 成功 / +4000 失败不能单独区分 absolute cap 与 offset cap**，但在已有静态 sender 中没有相应主动比较；现有证据指向 wait/completion 未完成，真正未完成的设备端 consumer/notification 首因仍待定。

没有发现可负责任地标记为“off-by-one bug”的 GSP/PMU 原始地址；没有把任何未经定位的 +4000 条件伪称成 firmware hardcap。R610 Clock Programming row 8..12 的 parser 地址如上；故障 PMU wait 与 response 分支原始地址为 `0x205d1acc` 及 `0x205d1ad6` 之后。

## 570.144 parser 缺口与结论边界

本轮的 570.144 registry-string xref 查询（`gsp570144_registry_xrefs.txt` 与新增 `gsp570144_mclk_registry_xrefs.txt`）未给 `MCLK_LIMIT`、`RMEnableClk`、`RMProgrammableClkMask`、`RMClkVfOverride` 等目标返回代码引用。此负结果不证明 registry 项无效或实现不存在；目标可能是注册字符串/间接配置记录。现有 570.144 GSP 可证的是 `Perf+0x4d8` post-clock ABI 和 PMU PERF event/response 消费轮廓（见下列材料），**尚不能据此声称已恢复其 VBIOS Clocks/Clock Programming OC parser、MCLK absolute-capability 对象或 timing key selection**。

相应地，14,001 MHz 与 +3999/+4000 的直接证据来自 MODS 570.215 / 对应 ROM / 匹配的 R570.215 runtime PMU，不是从 570.144 GSP parser 推导出来的。R610 的完整 parser 仅作同类对象的跨版本对照，不能替代缺失的 R570.144 function evidence。R610 当前 RISC-V body 的相关信息详见 `VBIOS_CLOCK_TABLE_GRAPH_20260817.md`、`GSP_61057_CLK_DOMAIN_READBACK_20260816.md` 与 `GSP_61057_PERF_EVENT_PROTOCOL_20260817.md`。

## 主要本地证据

- `MODS570215_MCLK_3999_4000_STATIC_FINDINGS_20260903.md`：ROM offset range、`0x6e204c0` host validation、relation-12 base、18000/18001 日志结果。
- `mclk4000_root_hunt_20261009/target_path/REPORT.md`：R570.215 PMU `0x20633630 -> +0x68 -> 0x2063469e -> 0x206358ca` raw DATA route。
- `mclk4000_root_hunt_20261009/REPORT.md` 与 `mclk4000_reverse_followup_20261009/completion_path/REPORT.md`：timeout marker、response check 顺序、completion wait/signaling 未闭合项。
- `gsp570144_perf_protocol_workers_20260817.c`、`gsp570144_post_clock_slot4d8_20260817.c`：R570.144 GSP event/RPC failure behavior 与 slot predecessor。
- `GSP_61057_PERF_EVENT_PROTOCOL_20260817.md`、`gsp61057_perf_callback_followups_20260817.c`：R610 RPC packet/import/failure path 和与 R570 的 protocol 对照。
- `VBIOS_CLOCK_TABLE_GRAPH_20260817.md`：R610 parser addresses、BIT C pointers、25-row parse ABI、active row ranges、MCLK relation/program IDs。
- `GSP_61057_CLK_DOMAIN_READBACK_20260816.md`：R610 当前 MCLK supported list/readback。

## 安全与验证

- 新增的 MCLK registry xref：以 Ghidra `-readOnly -noanalysis` 打开既有 `gb202_gsp570144` 项目，执行只读 `DumpTargetReferences.java`；无 GPU、MODS 或固件执行。
- 核对 R570.144 ELF 身份：`sha256sum ghidra_static/gsp_inner_570144_main.elf`；`file` 确认为 RISC-V ELF；`strings` 确认版本字符串 `570.144`。
- PMU/ROM 地址结论取自上述已保存静态报告与哈希固定的本地输入；没有编辑 ELF、固件或既有 DB。
- 本报告保留一个重要不确定性：R570.144 MCLK OC/VBIOS parser 与最终 timing-key selector 未恢复；并无设备端实测来判定超时首因。

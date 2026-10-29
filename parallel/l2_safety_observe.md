# GB202 L2 拓扑、缺陷证据与安全可观测性

研究日期：2026-07-21；目标栈：RTX 5090 / GB202，NVIDIA 610.43.03。

> **协调者勘误（2026-07-21）：** 本报告把工作契约中的 `16 LTC`、
> `0xed/0x12` 和“48 active RM mask 单元”称为保存事实，但它们实际引用的是
> 先前主报告，项目没有保留对应 topology-probe/register stdout。按随后完成的
> `parallel/evidence_audit.md`，这些值必须降为 `REPORT-ONLY`；本报告没有对它们
> 做独立运行复核。原始归档可直接证明的是 96 MiB、8 FBP、96 个 NCU `l2s`
> 属性和 48 个匿名 LTS rollup 基数。下文凡依赖 `0xed/0x12` 或 16 LTC 的推断
> 都应按这一证据等级阅读；关于公开 610 接口能力的源码结论不受此勘误影响。

## 结论先行

1. **[事实] 当前能确认的是“驱动当前采用的有效拓扑”，不是被屏蔽单元的物理健康。** 保存的项目证据给出 8 FBP、16 LTC、48 个 active RM LTS mask 单元、96 MiB；每个 FBP 的 enable/disable mask 分别为 `0xed`/`0x12`。这是既有结果，本任务没有重新读取硬件（`GB202_PARALLEL_WORK.md:10-13`）。
2. **[事实] 不能把所有“slice”计数混成同一种物理单元。** Nsight 属性命名空间报告 96 `l2s`（12/FBP），性能计数器证明的是 48 个 LTS rollup domain；二者最简单的数值解释是每个 rollup 对应两个 `l2s`，但身份映射没有被公开接口证明（`L2_SLICE_MAP_FINDINGS.md:41-85`）。同理，“48 LTS rollup”不能单独表述成“48 个已定位的物理 slice”。
3. **[事实] 610 源码有只读的有效拓扑查询面，但没有返回 mask 来源或健康状态的字段。** 它能给出总 L2 容量、active FBP/LTC/LTS 数量和每 FBP 的 LTC/LTS enable mask；不能区分 SKU floor-sweep、物理缺陷、维修记录或这些来源的合并结果。
4. **[结论] 当前 610 没有发现适用于零售 GB202、受支持且安全的“逐 L2 slice 隔离 / 修复 / 完整性自检”接口。** MIG 在本卡为 N/A；CUDA persisting/access-policy 是性能提示而非物理隔离；通用 `LTS_REPAIR` 构建开关不等于 GB202 能用；故障注入也不是自检，并且不属于本任务允许的只读操作。
5. **[推断，中等强度] 八个 FBP 完全相同的 `0x12` 更符合规则化 SKU floor-sweep，而不像 16 个独立随机缺陷。** 但没有群体样本、来源标签或工厂缺陷记录，因此不能排除“SKU mask 与独立 defect/repair map 合并”或工厂按坏块分档后形成相同最终 mask。
6. **[未知] 16 个当前 disabled mask 单元是否健康、是否存在单独的物理缺陷表、表中是否有记录，以及未来启用后能否稳定工作，均不能由现有安全接口确认。** “没有错误记录”也不是健康证明。

## 本任务的安全边界与方法

- 已完整阅读并遵守 `GB202_PARALLEL_WORK.md:41-64`。本任务没有执行任何 GPU 工作负载、`nvidia-smi`/NVML 查询、内部 RM 请求、MODS、MMIO/BAR0/PCI/debugfs 访问、reset、模块装卸、提权或配置修改；也没有运行 `permission_state_readonly_probe`。
- 只读取 610.43.03 开源驱动、项目源码、保存输出、已解码的静态脚本文本和既有研究报告。
- 唯一执行的分析程序是本地离线 `gb202_vbios_diff.py`；其源码明确只读取命令行给出的文件且不打开设备节点或 PCI/MMIO（`gb202_vbios_diff.py:2-11`）。比较对象是项目中已保存的 FE 与 RTX PRO 6000 Server option-ROM chain 文件，没有访问显卡。
- 下文提到的当前卡 mask/容量是**既有保存事实**，不是本任务重新探测所得。下文提到的未来 workload/profiler 仅是能力边界分析，不是本次执行建议，更不是对受保护配置的操作步骤。

## 1. 必须分开的三套拓扑术语

| 观察层 | 已保存的结果 | 可以证明 | 不能证明 |
|---|---:|---|---|
| RM effective topology | 8 FBP、16 LTC、48 active LTS mask 单元、96 MiB；每 FBP `0xed` | 610 当前枚举并向软件暴露的有效容量和 enable mask | mask 的来源；disabled 单元健康；每 bit 与 Nsight 名称的绝对映射 |
| Nsight device attributes | 8 FBP、12 `l2s`/FBP、96 `l2s`、96 MiB | Nsight 属性命名空间中的设备属性 | 96 个可独立寻址、可隔离的物理 slice |
| PerfWorks/Nsight rollup | 8 FBPA、16 DRAM、48 LTS rollup instances | 汇总计数的实例基数 | 隐藏实例编号、跨单元家族身份、物理地址到 LTS 的路由 |

证据：64 个归档报告一致给出 `l2s_count=96`、`num_l2s_per_fbp=12`、`fbp_count=8`（`L2_SLICE_MAP_FINDINGS.md:41-46`）；保存的三轮 topology summary 均为 8/16/48（`l2_slice_re/raw/20260713T092611+0800.LGScei/topology.summary.tsv:1-4`）。项目已明确将原先“48 physical L2 slices”的说法收窄为“48 LTS rollup instances”（`L2_SLICE_MAP_FINDINGS.md:74-85`）。

**[推断]** 48 个 RM active mask bit 与 48 个 LTS rollup 的基数相同，因而二者很可能紧密对应；但普通 `.ncu-rep`/CUPTI 只给 rollup，隐藏实例标签在任意排列下结果不变（`L2_SLICE_MAP_FINDINGS.md:47-61`），所以不能从相同基数推出绝对身份映射。

## 2. 不访问原始寄存器时，610 能观察什么

### 2.1 源码可见的只读 RM 拓扑查询

610 头文件定义了以下 GET 控制：

- `NV2080_CTRL_CMD_FB_GET_INFO_V2` 可请求 FBP count/mask、L2 bytes、active LTC count 和 active LTS count；字段语义见 `/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080fb.h:216-270,347-357,489-496`。
- `NV2080_CTRL_CMD_FB_GET_LTC_INFO_FOR_FBP` 返回指定 physical FBP 的 active `ltcMask/ltcCount/ltsMask/ltsCount`（同文件 `:1240-1269`）。
- `NV2080_CTRL_CMD_FB_GET_FS_INFO` 的 `LTS_MASK` 查询返回按 FBP flatten 的 physical/local LTS enable mask（同文件 `:2021-2033,2284-2359`）。
- 当前生成的方法表确实含 `0x20801303`、`0x20801328`、`0x20801346`，且表项 `accessRight=0`（`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_subdevice_nvoc.c:9871-9883,9991-10003,10201-10213`）。实现从 virtual static info 返回 popcount、`ltsCount` 与 `sizeL2Cache`（`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/mem_sys/kern_mem_sys_ctrl.c:86-114`）。

项目中的 `gb202_fs_probe.c` 仅封装上述三个 GET 控制，源码声明无 MMIO/变更控制（`gb202_fs_probe.c:3-10,32-47,218-235,264-303`）。**本任务没有运行它。** 而且它属于内部 RM control 使用方式，不应把“源码存在、语义只读”误写成 NVIDIA 面向终端用户承诺的稳定公开 API；当前合同也禁止新增 live internal-RM 请求（`GB202_PARALLEL_WORK.md:50-53`）。

这些接口可确认：

- 软件当前看到的总容量与 active topology；
- 每 FBP 当前生效的 LTC/LTS enable mask；
- 若未来在另一项、明确授权的工作中拓扑发生变化，驱动是否重新枚举了变化。

这些接口不能确认：

- enable/disable bit 来自 SKU、OTP/fuse defect、软件 repair 还是固件合并；
- disabled 单元是否通过生产测试；
- enabled 单元每个 set/way/bank 的完整性；
- GPU virtual/physical address 到一个绝对 FBP/LTC/LTS mask bit 的映射。

### 2.2 CUDA/Nsight 的高层可见信息

保存的探针元数据报告 `l2_bytes=100663296`，即 96 MiB（`l2_slice_re/raw/20260713T092611+0800.LGScei/probe.stdout.txt:7`）。CUDA 的标准设备属性也只暴露总 `l2CacheSize` 和 persisting-L2 能力，不提供 physical slice ID（`/opt/cuda/include/driver_types.h:2642-2651`）。

Nsight/PerfWorks 能证明 rollup 基数和总/平均流量，可用作“新枚举拓扑是否有活动”的统计证据；普通报告不提供可依赖的逐物理实例索引（`L2_SLICE_MAP_FINDINGS.md:47-61`）。因此它不能把一次数据错误定位到某个绝对 `FBP/LTC/LTS`，也不能保证工作负载只经过一个目标 slice。

## 3. 是否存在独立于统一 SKU mask 的 defect/repair 状态

### 已确认事实

- 当前保存结果中，所有 FBP 都是相同的 final/effective disable pattern `0x12`，软件 mask 为零；项目将其解释为硬件/工厂 mask 的当前有效结果，但也明确指出这不证明被屏蔽单元健康（`L2_REENABLE_STATIC_FINDINGS.md:42-52,95-99`）。
- 610 通用构建包含 `RMCFG_FEATURE_LTS_REPAIR=1`，注释为 “LTS swapping in-field”（`/usr/src/nvidia-610.43.03/src/nvidia/generated/rmconfig.h:340`）。私有 MODS 静态脚本也能表示独立的 InfoROM LTS repair records（`mods_audit/static/decoded/all/repair_guts.js:57-60,419-449`）。这只能证明通用软件体系**有单独维修记录这一概念**，不能证明本卡有记录或这些记录参与了当前 `0x12`。
- 保存的 `nvidia-smi` 显示 InfoROM ECC object、ECC mode、所有 SRAM/DRAM ECC 数及 L2 SRAM bucket 都为 N/A（`l2_slice_re/raw/20260713T092611+0800.LGScei/nvidia-smi.before.txt:46-50,147-169`）。N/A 表示不可获得/不支持，不能解释成零错误，也不能据此证明某个 InfoROM repair object 不存在。
- 离线 VBIOS 比较没有找到明文的八连 `0x12`、八个 little-endian `u32 0x12` 或 raw/effective L2 mask register reference；FE 与 PRO 的 BIT `i` 表仅多出一个已识别为非 L2 的 `SYS_PIPE_DISABLE` 项。两边 Falcon descriptor 都是 encrypted v6，能看到 `OOBHUB`/`FSP_RUN` 标签但 payload 不透明（`L2_REENABLE_STATIC_FINDINGS.md:152-181`；解析器的寄存器/pattern 定义见 `gb202_vbios_diff.py:23-33,314-360,364-390,466-472`）。

### 结论与边界

- **[事实]** 没有在 VBIOS 明文中找到一张独立的 GB202 L2 defect/repair map。
- **[事实]** 高层有效拓扑 GET 控制没有 provenance 字段；它只返回最终 active mask/count。
- **[推断]** 完全规则化的 `0x12` 更支持 SKU floor-sweep 是主要来源。
- **[未知]** 不能排除 defect bits 在 OTP/fuse、加密/签名 FSP payload、GFW 初始化或私有 InfoROM repair object 中与 SKU mask 合并。对明文扫描的阴性结果不是“不存在”的证明。

因此，对问题“物理缺陷图是否与统一 SKU mask 分开存储”，目前最精确的答案是：**通用软件有独立 repair-record 机制，但本卡是否有单独 defect/repair 数据、位于何处、是否非空，均未被安全高层接口确认。**

## 4. 当前 610 的逐 slice 隔离、修复与测试能力

| 能力 | 610 中看到的机制 | GB202 / 本卡判定 |
|---|---|---|
| 物理 L2 slice 隔离 | MIG/SMC、CUDA access-policy/persisting 提示、RM profiler-monitor mask 查询 | **无可用逐 slice 隔离。** 本卡 MIG N/A；提示不改变 shared-L2 ownership；monitor mask 是可见性查询，不是分配控制。 |
| LTS repair | 通用 `RMCFG_FEATURE_LTS_REPAIR=1`；私有 InfoROM repair 语义 | **无受支持的零售 GB202 repair 入口。** 当前公开 ECC repair-status 只含 TPC/channel；项目既有 GSP 静态分析还显示 GB202 repair hook 为成功 no-op。 |
| L2 slice 自检/BIST | 私有 MODS 文本有 MBIST/IOBIST；诊断头有故障注入声明 | **没有发现当前公开逐 LTS 完整性自检。** 私有诊断不可执行；fault injection 不是健康测试。 |
| 逐 LTC/slice ECC 注入 | 共享头文件声明 `NV208F_CTRL_CMD_FB_INJECT_LTC_ECC_ERROR` | **本构建没有对应诊断方法派发项。** 即使别的产品存在，也属于写入式故障注入，不在安全范围。 |
| 聚合 ECC 注入/计数 | 通用 subdevice ECC controls | 方法存在不等于本卡 runtime 支持；当前 GeForce 遥测为 N/A，且注入会主动制造故障。 |

### 4.1 隔离

保存状态显示 MIG Current/Pending 均为 N/A（`nvidia-smi.before.txt:20-22`）。项目既有分析指出 green context/TPC mask 不能隔离共享 L2，另一进程的 L2 traffic 仍会进入同一计数域（`L2_SLICE_RE_BRIEF.md:42-55`）。

CUDA `cudaLimitMaxL2FetchGranularity` 明确只是 hint；access-policy window 只有 normal/streaming/persisting 属性，driver 可对范围对齐或限制，没有 slice selector（`/opt/cuda/include/driver_types.h:1410-1433,1934-1935`；`/opt/cuda/include/cuda_runtime_api.h:423-429`）。RM 的 `PROFILER_MON_LTS_MASK` 是以 partition/swizz 可见性为语义的查询类型（`ctrl2080fb.h:2291-2294`），不是将物理 LTS 独占给某个进程的控制。

**结论：** 当前没有地址到绝对 LTS 的公开 hash/map，也没有 ownership/pinning API；因而不能构造“只让目标 slice 接收流量、其余 slice 不接收”的受支持实验。

### 4.2 修复

`NV2080_CTRL_CMD_ECC_GET_REPAIR_STATUS` 只返回 `bTpcRepairPending` 和 `bChannelRepairPending`，没有 LTS 字段（`/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080ecc.h:203-220`）。在 `/usr/src/nvidia-610.43.03/src` 对 LTS repair 控制进行有界检索，只找到通用构建特性，没有找到当前公开 `NV2080` LTS-repair control。

项目此前对当前 GSP 的离线分析进一步表明：通用 LTS repair 是用预留的软件-disabled L2/PAC spare 做**容量不变的 in-field swap**，不是重新启用硬件-disabled 单元；本卡保存的 L2 software masks 为零；GB202 chip index 65 的 runtime repair hook 被安装成恒成功 no-op（`L2_REENABLE_STATIC_FINDINGS.md:276-316`）。这组结果比单独的 `RMCFG_FEATURE_LTS_REPAIR=1` 更具体。

**结论：** 不能把编译期开关解释为 RTX 5090 可用维修能力，也不能把 private repair records 当作扩容或安全试错接口。

### 4.3 自检与故障注入

共享诊断头声明 `NV208F_CTRL_CMD_FB_INJECT_LTC_ECC_ERROR (0x208f050f)`，参数含 physical LTC 与 slice（`/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl208f/ctrl208ffb.h:372-398`）。但当前生成的 `DiagApi` 方法表从 `0x208f050e` 直接跳到 `0x208f0510`，没有 `0x208f050f`（`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_subdevice_diag_nvoc.c:289-378`）；对当前生成/实现目录的精确符号检索也没有找到 handler。故“头文件有声明”不是本构建导出能力的证据。

通用 subdevice 类确实导出 aggregate ECC counters、unique SRAM uncorrectable entries、generic injection、repair status 与 injection-supported 查询（`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_subdevice_nvoc.c:12931-13033`；结构定义见 `ctrl2080ecc.h:37-220`）。但是：

- runtime 对具体 unit 的支持仍需设备实现；当前保存遥测为 N/A；
- generic injection 主动制造 SBE/DBE，属于 mutation/fault injection；
- 注入成功只能验证错误路径，不是全面检查 cache data/tag/ECC、所有 set/way/bank 的 BIST；
- 它不能提供进程级物理 slice 隔离。

另一个全局 cache-control 命令能 reset/改变 cache state，但文档明确是 verification-only，且不是 per-slice；当前构建 `RMCFG_FEATURE_VERIF_ONLY_CONTROLS=0`（`ctrl208ffb.h:93-143`；`rmconfig.h:306`）。MODS 静态脚本中的 MBIST/IOBIST 与 LTS repair 命令（`repair_guts.js:47-60,195-215`）只证明私有诊断工具有这些概念，不构成当前零售驱动支持的安全接口。本任务未执行也不建议执行这些路径。

## 5. 未来若有另行授权的 enable，哪些高层信号能检测问题

以下是观测能力矩阵，不是本任务执行步骤；任何实际 enable/reset/配置改变均超出本报告范围。

| 高层信号 | 能确认的内容 | 关键盲点 | 本卡当前状态 |
|---|---|---|---|
| CUDA 总 L2 bytes / RM effective counts+masks | 驱动是否采用了新的有效容量/拓扑 | 不证明新增单元健康；不说明来源 | 保存值 96 MiB / 48 active RM LTS |
| Nsight LTS rollup 基数与流量 | 是否出现额外可计数 rollup、整体 L2 是否有活动 | 无稳定绝对实例标签；不能强制只走一个 slice | 保存值 48 rollup |
| 端到端数据校验 workload | 某些实际路由到的访问是否返回错误数据/触发崩溃 | 无 address→LTS 映射，不能证明目标 slice 被覆盖，更不能覆盖所有 set/way/bank | 本任务未运行 |
| ECC client-exposed counters | 若产品支持，可检测聚合 SRAM corrected/uncorrected 与 L2 bucket | 聚合而非 per-slice；当前 N/A；无变化不等于健康 | N/A |
| unique SRAM uncorrectable entries | 若 InfoROM ECC 支持，可给 unit/location/address/count | 公开结构未定义到 physical FBP/LTC/LTS 的映射；依赖 InfoROM | InfoROM ECC N/A |
| passive Xid | 可发现部分 LTC/ECC/memory-subsystem 严重错误 | 非全覆盖、通常非逐 slice、没有 Xid 不能形成健康证书 | 可作为未来被动告警面 |
| retired pages / remapped rows | DRAM page/row 可靠性 | 这是 DRAM 机制，不是 L2 SRAM slice 健康 | N/A |

ECC client counters只给 aggregate SRAM/DRAM 与 `sramBucketL2`（`ctrl2080ecc.h:37-82`）；unique uncorrectable 结构含 generic `unit/location/address/count`，但头文件没有记录其到 physical LTS 的映射，且查询依赖 ECC InfoROM（同文件 `:112-163`）。因此即使未来某个平台能读这些字段，也不能自动获得“LTS 17 健康/故障”的证书。

610 的 Xid 枚举包含 GPU ECC DBE 48、LTC error 90、excessive SBE 92、unrecoverable ECC escape 140、uncorrectable SRAM 172 和 memory subsystem error 175（`/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/nverror.h:63,96-98,135,166-172`）。这些是可能的被动故障信号，不保证每种 L2 数据错误都触发，也没有承诺携带绝对 slice 身份。驱动内部确有按 FBPA/subpartition 计算 L2 ECC DED register 地址的实现（`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/mem_sys/arch/blackwell/kern_mem_sys_gb100.c:226-236`），但这是 raw internal register path，不是 client 可安全使用的 per-LTS telemetry，本任务没有访问。

保存的 `nvidia-smi` 中 ECC mode/counters、L2 SRAM bucket、unrepairable-memory、retired pages 和 remapped rows 均为 N/A；只有 channel/TPC repair pending 显示 No（`nvidia-smi.before.txt:147-177`）。后两个 No 不涉及 LTS，所有 N/A 也都不能当成“零错误”。

## 6. 事实、推断与未知项清单

### 已确认事实

- 当前保存有效拓扑为 8 FBP / 16 LTC / 48 active RM LTS mask 单元 / 96 MiB，每 FBP `0xed`，且模式完全规则（`GB202_PARALLEL_WORK.md:10-13`）。
- Nsight 的 96 `l2s` 与 48 LTS rollup 是不同观察命名/粒度；普通报告没有绝对 per-instance identity（`L2_SLICE_MAP_FINDINGS.md:41-85`）。
- 610 具有有效拓扑 GET controls，但返回的是 final active mask/count，不含缺陷来源或健康字段（`ctrl2080fb.h:216-270,1240-1269,2021-2033,2332-2359`）。
- 本卡 MIG 与 ECC/row-remap telemetry 为 N/A（保存 `nvidia-smi.before.txt:20-22,46-50,147-177`）。
- 当前源码没有发现受支持的 per-LTS isolation/self-test/repair control；逐 LTC/slice injection 只有共享头声明，没有当前 `DiagApi` dispatch；generic repair 编译特性不能证明 GB202 支持。

### 推断

- **中等强度：** 统一 `0x12` 主要是 SKU floor-sweep 的可能性较高。
- **中等强度：** 48 active RM mask bits 与 48 LTS rollup domains 很可能对应同一有效粒度的不同观察面，但缺少绝对身份映射。
- **有限：** 若未来高层容量、RM effective mask 和 rollup 基数一致增加，并且广泛数据校验及被动错误信号均正常，只能说明“新增资源被枚举且被部分实际流量使用”；仍不能证明每个新增物理单元全覆盖健康。

### 仍然未知

- 16 个 disabled mask 单元各自的物理健康与生产测试结果。
- 是否存在与 SKU mask 分开的 non-empty defect/repair map；若存在，其存储位置、合并优先级和本卡条目。
- 96 Nsight `l2s`、48 rollup domains、48 active RM mask bits 之间的绝对 identity mapping。
- 地址/partition/SM 到 physical FBP/LTC/LTS 的 hash 与可控性。
- 是否有 NVIDIA 内部、设备授权且不公开的 GB202 per-LTS BIST；当前零售 610 对客户端没有发现这种接口。
- 未来任何被授权 enable 后的稳定性、ECC 行为与 reset 后持久性。

## 最终判定

在不触碰 MMIO、reset、模块、MODS 或受保护配置的前提下，可以高置信确认**当前有效拓扑和总容量**，并界定现有高层 telemetry 的粒度；不能确认 disabled 单元的物理健康，也不能证明统一 mask 是否已混入独立 defect map。当前 610 对 RTX 5090 没有可用的逐 L2 slice 隔离、repair 或完整性 self-test 接口。未来即便由另一项工作合法地改变拓扑，现有安全信号最多形成“重新枚举 + 有流量 + 未观察到粗粒度错误”的证据链，不能形成逐 slice 的硬件健康认证。

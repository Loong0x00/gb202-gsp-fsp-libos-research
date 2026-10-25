# PMU command-0 请求：设备消费者 / 寄存器身份追踪

## 结论

**身份仍未闭合。** 新增材料没有把 `0xc09a4514` / `0xc09a4504` 正面绑定到任何已命名的 GB202 设备块或设备侧消费者，也没有给出 PMU-visible `0x0140xxxx` 状态/响应字的正式寄存器名。可以确认的上限是：R570.215 runtime PMU 的 MCLK 调用者把 command 0 交给通用 PMU 事务原语；该原语先写 request data (`+0x14`)，再写 tagged command (`+0x04`)，随后等待并读取 response。**调用者是 MCLK 路径，不等于接收端或 opcode 0 的硬件语义已被识别。**

`PBFB`、FSP、GFW/FBFalcon、FBPA 等归属都没有达到正面证据门槛。尤其不能因数值 `0x9a45xx` 接近公开 `PBFB_BROADCAST` 基址而认定是 PBFB。硬件总线目标、端点寄存器正式名称、命令的设备侧消费函数，以及 response/status 字背后的硬件源仍未知。

## 新增正面证据

### 1. 旧 PMU firmware：请求形态是通用事务原语，而非已识别的 MCLK 专用端点

对本地两个 stripped RISC-V clear-PMU ELF 的静态反汇编复核：

| 工件 | SHA-256 | 相关发送原语 |
|---|---|---|
| `power_governor_reverse/gb202_r570_clear_pmu_333d8c4e.elf` | `333d8c4ea22659f65c898579d70806640b7e26357eb6305bd900a807627d2db0` | `0x202d0050`，数据/命令写入位于 `0x202d00cc–0x202d00e8` |
| `power_governor_reverse/gb202_r570215_clear_pmu.elf` | `c822f7e07b4a00e8e7add07dd470e67221006aa7ca17bd3c59aefbe8ee6ea17a` | `0x202e3104`，数据/命令写入位于 `0x202e3180–0x202e319c` |

两版都从参数取得 command、16-bit 字段与 32-bit 输入值，递增 8-bit sequence，组装带序号的请求字；随后通过同一结构的寄存器写 helper 先写偏移 `0x9a4514`，再写 `0x9a4504`。旧版 helper `0x20292566`、R570.215 helper `0x202a555c` 都将偏移变为 `0xc0000000 + offset`，因此分别落到 `0xc09a4514` 与 `0xc09a4504`。这证明该请求对/事务框架至少跨这两个本地 firmware 构建沿用；不证明哪个设备接收，也不证明 opcode 0 的设备侧意思。`clear_pmu` 工件的用途和请求消费者不可由文件名或发送形态反推。

另一个边界证据：两份 clear-PMU ELF 在完成等待后直接读取 `0x01400808/0x01400828` 校验/取回 response；目标 runtime MCLK path 则使用 `0x01402808/0x01402828`（`endpoint_identity/REPORT.md`）。即请求写对沿用并不代表不同 firmware image 的 response-local 地址相同；不能从 clear image 将局部响应字的地址映射移植给 runtime，更不能据此给任一地址命名。

目标 R570.215 runtime ELF 的 SHA-256 为 `2eef42f0b434990d2c9669124199a912e8e16d8480d1c9a74d46d75e1575b93b`（见既有 `send_path/REPORT.md`）。该 runtime 的 MCLK wrapper 将 command 0 交给同类事务原语；故“PMU 发起 MCLK 相关调用”有证据，“command-0 设备端实现是某个内存控制器/时钟控制器”则没有。

### 2. 可公开核对的 memory-clock 协议术语，与目标请求没有连接

- 本地 Nouveau 的旧世代 RAM reclocking 实现明确以 `RAM reclocking` 命名：`/home/user/amd_mcr_research/linux-apcb-runtime/drivers/gpu/drm/nouveau/nvkm/subdev/fb/ramgt215.c:343-345`。`gt215_ram_calc` 在 `:492-557` 查 RAM 配置/时序并计算 MCLK PLL；`gt215_ram_lock_pll` 在 `:455-463` 写入并等待 PLL。`/home/user/amd_mcr_research/linux-apcb-runtime/drivers/gpu/drm/nouveau/nvkm/subdev/fb/ramgf100.c:184-194,229-244` 明确区分 current/target mclk configuration 并计算/编程 mempll。
- 这些是内存时钟确实存在的公开 reclocking 路径证据，但属于不同世代的直接 RAM/PLL 编程代码；其中没有 `0x9a4504/0x9a4514`、GB202 PMU command-0 或连接到该请求的消费者。因此不能拿术语或功能相似性替代 endpoint 证据。
- NVIDIA 已发布 `/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080clk.h:48-52,69-87` 提供 `NV2080_CTRL_CMD_CLK_PMUMON_CLK_DOMAINS_GET_SAMPLES`，sample 字段包含 `dramClkFreqKHz`。这是 PMUMON 的 DRAMCLK **监测/读样本**接口，不是目标私有请求的寄存器映射或设备侧写入协议。

### 3. PBFB 名称/地址库：存在近邻广播基址，但没有目标寄存器定义

本地 `tools/envytools/rnndb/memory/gf100_pbfb.xml`：

- `:1-145` 定义 `gf100_pbfb` 组，列出的寄存器最高到 group offset `0x8e0`；
- `:161-168` 定义 GP100+ `PBFB_BROADCAST` 基址 `0x9a0000`、stride `0x4000`，以及独立 `PBFB` 数组；
- 目标 offsets `0x9a4504/0x9a4514` 分别是该 broadcast 基址 `+0x4504/+0x4514`，XML 中没有这些寄存器或对应字段。它们也在声明的 `0x4000` stride 以外。

所以公开 rnndb 可证明的是“有名为 PBFB_BROADCAST 的公开块/基址”，不能证明目标请求落在该块。没有任何表项、字段或调用链将请求对指向 PBFB；仅地址相近不足以归责。

### 4. MODS RegHal、已发布头文件及局部地址映射边界

- 已有 GB202 RegHal 离线解码报告 `parallel/GB202_REGHAL_FULLMAP_20260925.md` 记录 MODS 570.215（SHA-256 `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856`）中的 GB202 `0xff2` 表共 20,083 行。既有精确查询 `0x9a4504/0x9a4514`、`0x014024c0/0x014024c4`、`0x01402808/0x01402828` 均没有可用表项/正式名称。该 RegHal 是特定编码的地址字典，不是所有私有或未发布端点的穷尽硬件 register map；负结果不能证明端点不存在。
- 目标 runtime PMU 对 `0x014024c0/0x014024c4` 的用法分别呈 pending-status/ack 与 control/ack-state 更新；对 `0x01402808/0x01402828` 的用法是 response 校验/取值。它们是**按使用方式命名**的 PMU-visible local addresses。没有找到权威 GB202 地址转换表，不能把这些地址称为 BAR0 offsets，也不能将其与 `0xc09a45xx` 偏移数值归一化为同一硬件块。
- 公开 GB202 FSP 头 `/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src/common/inc/swref/published/blackwell/gb202/dev_fsp_pri.h:27-35` 命名的是 FSP scratch groups `0x008f0320` 与 `0x008f0330`；没有目标 `0x9a45xx` 或 `0x0140xxxx` 的定义。这只能说明已发布头文件中的该 FSP scratch 接口与目标请求尚无连接，不排除未公开/间接路径。

### 5. FSP / GFW / FBFalcon 本地 inventory

- 已发布 open-gpu-kernel-modules 的 Blackwell FSP host code 中，`/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb100.c:253-265` 经 `kfspSendAndReadMessage(..., NVDM_TYPE_CLOCK_BOOST, ...)` 发送明确命名的 clock-boost RPC；`/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src/nvidia/src/kernel/gpu/fsp/kern_fsp.c:271-279` 在 cleanup 路径禁用该 feature。可证 FSP 有独立的 clock-boost RPC；没有证据把它连到 PMU command 0、该请求寄存器对或 DRAM MCLK reclocking。
- GB202 generated bindata inventory（`/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src/nvidia/generated/`）中有 GSP boot、concatenated FMC 与 `GspRmFmcGfw*Signed` 包（例如 `g_bindata_kgspGetBinArchiveConcatenatedFMC_GB202.c`、`g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c`）。它们是归档/签名固件数据，不是已公开的 target consumer 源码。`windows_driver_compare/610.88/REPORT.md:55-85` 还显示两份候选 GB202 PMU image slot 均为约 2 MB opaque payload；跨 Windows/Linux 包一致并未解开其消费者。
- 本地 `parallel/vbios_fsp_inventory.md` 清点的 VBIOS/NVFW 样本含 Falcon v6 `app=0x24/target=0x0f` FSP_RUN descriptor；报告只将其后续区域保守称为带 encrypted flag 的 word1-sized region，未把它当作可读 FSP 程序或证明任何 command 消费者。
- 在本轮检查的 GB202 published-header 与 generated firmware 名称范围内，没有找到 standalone FBFalcon consumer image/source，也没有找到能将目标偏移映射到 FBFalcon 的正面材料。此为有界本地 inventory 的结果，不是对所有未公开或未归档 firmware 的不存在性证明。

## 身份闭合矩阵

| 问题 | 当前可证结论 | 状态 |
|---|---|---|
| 哪个 PMU caller 发起 command 0？ | R570.215 runtime 的 MCLK wrapper；PMU 通用原语写 data 后写 command 并等待 | caller 侧已闭合 |
| 请求寄存器名字/所属 block？ | `+0x14` data 与 `+0x04` command/trigger 是依写入顺序和角色命名；没有正式字段名或 block map | **未知** |
| opcode 0 的设备侧含义/消费者？ | 本地旧版 PMU 证明通用原语重用，不含对应外部接收者 | **未知** |
| `0x0140xxxx` 的正式寄存器块/总线映射？ | 仅从 runtime PMU 使用方式推断 status/control/response 角色 | **未知** |
| PBFB/FSP/GFW/FBFalcon/FBPA 归属？ | 没有目标寄存器定义或连接消费者的正面证据 | **未建立** |
| PMU bit-2 通知链是否指明设备消费者？ | 只闭合 PMU 内 notification dispatch 到等待对象的关联；未识别设置该位的源/接收端 | **否** |

要闭合至少还需要以下一类正面证据：GB202 权威 register/PRI address map 定义精确目标地址；读取/处理该请求对的设备侧 firmware 函数并跟 command-0 调用相连；或有明确跨层文档/实现把该 PMU 请求路由到命名 consumer。地址相似、同属 memory-clock 主题、或者 PMU 侧等待通知均不足以替代。

## 覆盖范围、限制与安全

本轮为本地静态只读：覆盖 MODS 570.215 RegHal、已发布 GB202/FSP 头文件、两份旧版 clear-PMU ELF 与目标 runtime PMU 的既有反汇编、本地 Nouveau 公开 RAM reclocking 代码、envytools PBFB rnndb，以及已列明的 GSP/FMC/GFW/FSP/PMU inventory。没有运行 GPU/MODS，没有访问设备或 MMIO，没有联网，也没有打开/修改旧 Ghidra DB。受限于私有/签名 firmware 不透明、公开 register map 不完整和本地 inventory 有界，负结果只表示上述证据范围没有身份绑定。

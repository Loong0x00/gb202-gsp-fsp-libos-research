# GB202 L2 重新启用：本地研究资料证据审计

审计日期：2026-07-21

> **协调者后续更新（2026-07-21）：** 审计完成后已新增
> `parallel/GSP_ARTIFACT_PROVENANCE.md`、`parallel/gsp_fb_vtable_replay.py`
> 和 `parallel/gsp_fb_vtable_replay.results.txt`。它们闭合了当前 outer/inner
> GSP provenance，并可复现证明当前 610 中 GB202 index 65 的 FB vtable
> `+0x9b0=0x132ae68`、`+0x9c0=0x132ef40`。因此本报告中“GB202 effective
> getter 具体绑定仍为 REPORT-ONLY”这一项现可升级为 `V-STATIC`。该更新不
> 改变 `8 x 0x12`、SW=0、PLM、coupling 及 disabled-unit health 缺少原始
> 运行证据的结论。

> **协调者第二次更新（2026-07-21）：** 新增的
> `parallel/gsp_objgpu_668_replay.py`、结果留档与独立重放证明：GB202 index 65
> 的 `OBJGPU+0x668` 实际绑定状态感知 `0x144d4e8`，不是恒假
> `0x19508c4`。旧分析漏掉 group-2 bitmap `0x303f`。因此本文下方所有“GB202
> reset-coupled getter 恒假/完全无判别力”的旧判断均由
> `parallel/reset_coupled_binding_replay.md` 取代。历史 control 输出仍未留档、
> 仍不是当前值，公开 ABI 也仍不能区分 boot/fuse/base。

> **协调者第三次更新（2026-07-21）：** 后续的 getter、相邻 setter 与虚拟化
> guard 交叉审计进一步证明：`0x144d4e8` 的 `+0xb68` guard 是 `isVirtual`；
> 物理路径直接读取 `fuse(+0x40) || boot(+0x44)`，而 base 位为 `+0x48` 且没有
> 被该 getter 直接读取。对应报告为
> `parallel/reset_getter_guard_provenance.md`、
> `parallel/reset_getter_internal_fields.md` 和
> `parallel/coupling_setter_crosscheck.md`。因此下方把 guard/两个 bit 仍列为
> 未闭合的旧段落也由这次更新取代；base 是否级联/镜像仍为 `UNKNOWN`。

> **协调者第四次更新（2026-07-21）：**
> `parallel/base_coupling_visibility.md` 又排除了可见 GSP 软件镜像：selector 8
> 只置位/读回 base `+0x48`，type-8 reset arm 不串行调用 selector 4/5。当前
> 未知项已缩到寄存器硬件副作用、reset sequencer 或 FSP/GFW 隐式级联。

## 结论摘要

现有本地材料足以证明“这张卡在归档运行中呈现 96 MiB L2、8 个 FBP，并存在一套可被 MODS 570.151 描述的 Blackwell raw/SW/effective floorsweep 寄存器链”。现有材料也足以静态证明：MODS 570.151 的 direct-shadow 写入器有 host security-level 门、设备侧受保护写入、逐项回读以及成功后的重型 reset/reinit；失败路径不是事务性的。

现有材料**不足以**证明以下关键命题：

- 当前卡的 8 个 raw/effective 寄存器仍都为 `0x12`、8 个 SW 寄存器仍都为 0；
- `0x8200dc`、`0x8200f8`、`0x8212ac.bit0`、override latch 和 reset-coupling 的当前值；
- GB202 FSP 的 task 2/subobject 1 确实、完整且持续地开放 direct-shadow 写入所需权限，尤其是 latch 所需的 `0x8200f8`；
- raw shadow 的降低会在零售 GB202 上传播到 effective 拓扑，并在任一种 reset 后稳定生效；
- 16 个被屏蔽的低级单元均物理健康，或能够逐个安全启用；
- 48 个 PerfWorks LTS rollup、48 个当前活动 mask-bit 单元和 96 个 NCU `l2s` 属性之间存在已索引、已验证的一一/二一物理映射。

因此，`L2_REENABLE_STATIC_FINDINGS.md` 的最终安全结论——目前不能安全、合法地交付主系统可运行的解锁器——得到支持。需要修正的是若干“已验证本卡状态”的证据等级，以及旧映射材料对“48 个物理 slice / 16 个 MC”的过度命名。

## 范围、方法与等级

本审计完整阅读了：

- `GB202_PARALLEL_WORK.md`；
- `L2_REENABLE_STATIC_FINDINGS.md`；
- `L2_SLICE_MAP_FINDINGS.md`、`L2_SLICE_RE_BRIEF.md`、`l2_slice_re/README.md` 及其相关归档数据；
- `EXPERIMENT_PLAN.md`；
- `mods_audit/README.md`、`mods_audit/static_audit.md`、`mods_audit/dynamic_audit.md`、`mods_audit/containment/containment.md` 中与本任务有关的范围和证据；
- `gb202_reghal_offline.py`、`gb202_fjson_offline.py`、`gb202_iff_offline.py`、`gb202_vbios_diff.py`；
- `gb202_fs_probe.c`、`permission_state_readonly_probe.c`、`reset_coupling_readonly_probe.c` 和 `bar0_read_probe/` 的源码/构建产物；
- 当前 `/usr/src/nvidia-610.43.03` 中与 FSP、NVDM、MNOC、fuse control 和 GB202 HAL 有关的公开源码。

等级定义：

- **V-RUNTIME**：项目内有原始运行输出，可直接复核；只代表归档时的卡和软件状态。
- **V-STATIC**：可从指定版本的源码、固件或二进制静态复核；不自动外推到实时硬件行为。
- **REPORT-ONLY**：报告叙述了运行或静态结果，但项目内没有对应原始输出、提取映射或重放脚本供独立复核。
- **INFERRED**：由多个事实推导出的最合理解释，但仍有其他兼容解释。
- **UNKNOWN**：材料不能裁决。

本审计没有执行 MODS，没有访问 GPU、BAR0/MMIO、PCI config 或设备节点，没有加载模块，没有复位、解绑、重绑或请求 root。对 MODS 只做了少量地址范围的 bounded disassembly；没有整文件反汇编。

## 一、可直接确认的本卡/归档运行事实

| 命题 | 等级 | 本地证据 | 严格边界 |
|---|---|---|---|
| 归档运行报告的是 NVIDIA GeForce RTX 5090，L2 为 `100663296` bytes（96 MiB） | **V-RUNTIME** | `l2_slice_re/raw/**/{lts_rollup,api_validation}.raw.csv` | 是 2026-07-13 归档状态，不是 2026-07-21 的实时重读 |
| `device__attribute_fbp_count=8` | **V-RUNTIME** | 43 个 raw CSV、33,276 个带属性的数据行一致 | 这是 NCU 设备属性；未给出物理 FBP 身份映射 |
| `device__attribute_l2s_count=96`、`num_l2s_per_fbp=12` | **V-RUNTIME** | 同上，33,276 行全部为 `(96,12,8,100663296)` | NVIDIA/NCU 的 `l2s` 命名层；不能直接改称 48 个物理 slice |
| 同一拓扑采样中有 8 FBPA、16 DRAM、48 LTS rollup instance | **V-RUNTIME** | `l2_slice_re/raw/20260713T092611+0800.LGScei/topology.summary.tsv` 三次均为 8/16/48 | 只证明 rollup 基数，不证明跨单元族的身份边，也不证明 16 个物理 MC |
| 可在同一 CUDA allocation 内稳定构造 48 个相对 LTS rollup class | **V-RUNTIME** | `L2_SLICE_MAP_FINDINGS.md` 指向的 case/raw/summary 归档 | 只支持 allocation-scoped 相对类；没有绝对物理编号 |
| 公共 rollup 输出对隐藏 instance 标签的置换不敏感 | **V-STATIC + V-RUNTIME** | 当前映射报告、归档 `sum/avg/min/max` 形式 | 因此不能从现有输出恢复绝对 slice/MC/FBP 身份 |

项目当前共有 107 个 `.ncu-rep`：`rt_cache_probe/` 下 64 个，`l2_slice_re/` 下 43 个。`L2_SLICE_MAP_FINDINGS.md` 的“all 64 archived”是某个子集/写作时点的计数，不应再表述为当前项目总数；这不是拓扑数值矛盾，但属于清单口径漂移。

## 二、可静态确认的寄存器与 MODS 570.151 行为

### 2.1 RegHal 表

`mods_audit/static/extracted_inner/mods` 为 392,339,552-byte ELF，SHA-256：

`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`

本审计以低内存方式复核 `gb202_reghal_offline.py` 的表定位和内置断言，得到 `header=0x8fd61aa`、19,999 行、解压大小 559,972 bytes，self-test 通过。以下是 **V-STATIC（仅限该 MODS 样本）**：

- raw OPT/shadow 数组映射为 `0x8234e0 + 4*FBP`，8 个实例；
- SW L2 配置数组映射为 `0x822080 + 4*FBP`；
- effective L2 disable 数组映射为 `0x822900 + 4*FBP`；
- `0x820040.bit0` 有独立 access metadata，指向 `0xf8`；
- raw/SW L2 目标的 access metadata 指向 `0xdc`；
- `0x8200dc.[7:4]` 被表述为写保护字段，表中存在值 `0xf` 的枚举；
- `0x8212ac.bit0` 的字段/常量条目确实存在。

这些表项证明的是 ID、地址、字段和 access-offset 元数据。它们**不单独证明**：寄存器的人类语义、当前值、某项写入会被硬件接受，或 PLM 在当前卡上处于哪个等级。名称和行为仍依赖代码交叉引用。

### 2.2 direct-shadow writer

本审计仅对 MODS 中以下局部范围做了 bounded disassembly：writer `0x1515ea0`、上层 core `0x14620d0`、post-program/reinit `0x127b000`、reset-coupling 选择器 `0x126b360` 及少量直接被调 helper。以下是 **V-STATIC（MODS 570.151）**：

- writer 在 host security level 不高于 3 时拒绝继续；这是 MODS host gate，不等于设备 PLM；
- writer 先尝试设置 override latch，再按计划逐项对 raw offset/value 执行写入和立即回读比较；
- 多项计划不是事务：单项不匹配会记录错误，但控制流仍可继续处理其余项；
- 上层在 writer 报错时进入清理，跳过成功后的 post-program 路径；没有看到自动回滚已改变 raw 项或确认/清除 latch 的事务；
- 成功路径进入 RM 状态卸载、reset/reinit；reset 类型由已有 coupling 状态选择，静态优先级与主报告的 base、fuse、boot、hot 顺序一致；
- 失败路径不会获得成功路径的 reset/reinit，因此“部分写入 + 无成功 reset”的状态风险真实存在。

这组事实只刻画 NVIDIA MODS 570.151 样本中的 host 算法。它不证明：

- MODS 可以或应该在当前 610.43.03 日常系统运行；
- 当前零售卡 PLM 会接受写入；
- raw shadow 会传播到 effective view；
- 被屏蔽单元健康；
- reset/reinit 后一定可恢复显示和桌面。

### 2.3 普通 `fbp_l2slice_enable` 与 direct-shadow 不能混用

主报告对普通 floorsweep 参数路径的结论在静态逻辑上自洽：普通 `fbp_l2slice_enable` 走 SW 配置，并把当前已屏蔽位重新并入，不能用来清除硬/生效屏蔽。direct-shadow `SetSwFuses` 是另一条 raw writer 路径。

本审计将前者记为 **REPORT-ONLY（详细的 MODS 570.151 静态论证，但本审计未独立重放该函数）**，而不是本卡运行事实。项目没有保存一次无副作用调用的 trace；也没有必要通过运行 MODS 补证。

## 三、当前 610.43.03 能证明与不能证明的内容

### 3.1 公开源码可直接证明

以下为 **V-STATIC（610.43.03 源码）**：

- `/usr/src/nvidia-610.43.03/src/nvidia/arch/nvalloc/common/inc/nvdm_format.h` 定义 `NVDM_TYPE_HULK=0x11`、`NVDM_TYPE_PRC=0x13`、通用 response `0x15`；
- GB202 的 `KernelFsp` 存在并使用有效的 FSP/MCTP/NVDM HAL；`kern_fsp_gb202.c` 明确说明 chip reset 后由 Bootfsm 触发 FSP，并等待 secure-boot complete；
- GB202 的 `KernelSec2` 对 packet/NVDM send/read/process 落到 not-supported/空 stub，因此不能仅因对象存在就把它当作 GB202 的 HULK/PRC 端点；
- 通用 FSP transport 可封装 HULK/PRC，但开源树没有 GB202 HULK payload、caller、task/subobject 路由或 restore/undo schema；
- `ctrl2080fuse.h` 是 34 行空壳，`generated/rmconfig.h` 中 `RMCFG_MODULE_FUSE=0`，公开 RM 没有可用于读取这些 fuse/PLM 状态的 fuse control；
- `RMCFG_FEATURE_LTS_REPAIR=1` 只证明通用 repair 功能被编进构建；它不证明 GB202 的 chip HAL 实际挂接非空 repair 实现；
- MNOC mailbox 的实际 HAL mask 只覆盖 GB100/GB102/GB110/GB112/GR100/GR102。GB202 落到 send/recv `NV_ERR_NOT_SUPPORTED`、availability false、message size 0 的 stub；所以公开 610 host-RM 不能把 IANA debug-token query 当作 GB202 的可用状态探针；
- `NV2080_CTRL_CMD_GPU_IS_RESET_COUPLED=0x208081f3` 的公开定义和 route-to-physical control 项存在，但公开源码本身不披露 GB202 的真实 coupling 位。

### 3.2 当前 GSP 固件的静态边界

当前固件 `/usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin` 为 84,277,400 bytes，SHA-256：

`572373620a37418f24dc16b5031c39338778c3257e48e8408de9a57291b24f3a`

对字符串的本地复核可确认固件包含 HULK 相关名和 LTS repair 文案，包括标记 LTS/pair 和“no spare”错误。等级为 **V-STATIC（字符串存在）**。字符串不能证明 GB202 可达性、HAL 安装或任务效果。

本地另有未纳入项目版本管理的临时提取物 `/tmp/gsp_inner_19f040_a.elf`，大小 82,577,496 bytes、SHA-256 `bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`。逐字节比较确认它等于上述 outer firmware 从 file offset `0x19f040` 开始的同长度区间，因此其来源可以静态闭合到当前固件。对该 inner ELF 的小窗口 Capstone 反汇编可直接确认：

- `0x1975824` 是返回 0 的短桩；
- `0x19508c4` 是返回 false/0 的短桩；
- `0x144d4e8` 是检查对象 guard、调用下层查询并读取两个 bit 的非平凡 getter；
- `0x156df8c` 是非平凡的 repair 实现；
- `0x132ef40` 是非平凡 getter，其局部控制流构造 `0x2900 + 4*index` 一类内部 offset、经对象方法读取 word 后形成反掩码结果。

这些**函数体本身**为 **V-STATIC（当前 inner GSP）**。临时 ELF 不应被当作长期归档；本审计没有把它复制进项目。

主报告此前进一步声称：

- GB202 chip index 65 的 LTS repair hook 是恒成功 no-op；
- non-MIG physical LTS getter 消费 `0x822900`；
- reset-coupled getter 在 GB202 index 65 上是恒假 HAL（现已证伪）；
- coarse status getter 消费 `0x820d70`。

审计完成后的多个持久化 constructor replay 已分别闭合 repair、FB topology 和
reset-coupled 槽。前两项与 coarse/effective getter 的具体绑定现有各自脚本和
输出；第三项则得到与旧报告相反的结果：GB202 把 `0x144d4e8` 安装到
`OBJGPU+0x668`。因此这些**固定 artifact 上的具体绑定**现可列为 `V-STATIC`，
但它们仍不等于本卡当前寄存器值或运行状态。

`parallel/gb202_610_arch.md` 对当前公开源码的独立审计进一步支持：GB202 可工作的 NVDM engine 是 FSP，SEC2 不是；但公开源码仍无法证明 HULK 的 payload/PLM 效果，也无法证明独立 floorsweep task 2/subobject 1 的 firmware consumer 或任何 PLM restore。现有材料没有建立 HULK 与 task 2 的映射。

## 四、“已验证本卡状态”中应降级的项目

`L2_REENABLE_STATIC_FINDINGS.md:42-52` 把若干项目统列在“已验证的本卡状态”下。按当前项目留档情况，应拆分如下：

| 原命题 | 审计等级 | 原因 |
|---|---|---|
| 当前/归档 L2 为 96 MiB | **V-RUNTIME** | raw NCU CSV 可复核 |
| 8 个 FBP | **V-RUNTIME** | raw NCU CSV 可复核 |
| 8 个 raw 低字节均为 `0x12` | **REPORT-ONLY** | 没有保存对应寄存器读取 stdout/raw dump；脚本常量不是独立证据 |
| 8 个 effective 值均为 `0x12` | **REPORT-ONLY** | 同上 |
| 8 个 SW 值均为 0 | **REPORT-ONLY** | 同上 |
| bit 1、bit 4 共 16 个被屏蔽低级单元 | **INFERRED from REPORT-ONLY** | 依赖 `8 x 0x12` 观测 |
| 每 mask bit 代表 2 MiB | **INFERRED / static accounting** | 与 96 MiB、8 FBP、12 active `l2s`/FBP、8-bit mask 模型一致；不是独立物理健康证明 |
| GB202 满配 128 MiB | **INFERRED / architecture model** | 可由 8 FBP × 8 mask-bit × 2 MiB 算术得到；没有本项目中实际 128 MiB GB202 的运行输出 |
| 共有 48 个活动 LTS slice / 16 个 LTC | **命名需拆分** | 48 rollup 为 V-RUNTIME；48 mask-bit 活动单元依赖 `0x12`；16 LTC 的 probe stdout 未留档；不能把三者合并为一个物理事实 |

项目中没有找到 `gb202_fs_probe`、`permission_state_readonly_probe`、`reset_coupling_readonly_probe` 或 BAR0 probe 的运行输出。全项目（排除主报告/源码/硬编码脚本）也没有命中 `raw/effective=0x12` 或 `is_reset_coupled=0` 的原始记录。

同轮生成的 `parallel/l2_safety_observe.md` 把 16 LTC、`0xed/0x12` 和 48 active RM mask 单元称为“保存事实”，但其引用回到 `GB202_PARALLEL_WORK.md`/主报告，而不是一个寄存器或 topology-probe stdout。它是结论转述，不是独立原始证据，不能提升上述等级。

三个源码的证据能力也不同：

- `gb202_fs_probe.c` 是 GET-only RM topology probe；其源码可证明查询格式，但没有 stdout，不能证明本卡返回了 16 LTC 或任何具体 mask；
- `permission_state_readonly_probe.c` 固定为 `READ_32`，但只列 FBP0 的 raw/effective/SW，并读取 `0x8200dc`、disable override 和 latch；它**没有读取 `0x8200f8` latch PLM**。没有编译产物或 stdout；
- `reset_coupling_readonly_probe.c` 的源码可证明只读 control 格式，不能替代结果留档；
- `bar0_read_probe/` 有 `.ko/.o` 构建产物，但没有加载/运行日志。构建成功不证明它曾被加载，也不证明任何寄存器值。

主报告叙述了 `is_reset_coupled=0` 的一次历史 control 返回，但没有对应输出文件。
新的绑定重放证明 GB202 使用状态感知 getter，所以不能再用“恒假”否定该值的
fuse/boot 判别意义；然而 stdout 和同时段健康快照均未留档，而且固定 getter
没有直接读取 base。因此它仍不能用作**当前**三项 coupling 或最终 reset 类型证据。

## 五、推断、类比和仍未闭合的权限链

### 5.1 task 2/subobject 1

可以确认的材料是：

- MODS host 控制流在 floorsweep 流程中发送 FSP task 2/subobject 1，并在其后进入 host apply；
- Hopper 的相关实现会检查 `0x8200d0` 和 `0x8200dc` 是否已处于开放等级；
- MODS RegHal 表把 L2 raw/SW 区域的 access metadata 指向 `0x8200dc`；
- 当前公开 610 源码证明 GB202 的 NVDM 端点是 FSP，但没有公开 task 2 的 firmware consumer。

由此得到“GB202 task 2/subobject 1 旨在降低至少 d0/dc PLM”的结论，等级应为 **INFERRED（较强）**，而不是直接的 GB202 FSP 内部事实。尤其不能再外推：

- task 2 会开放 `0x8200f8`；
- 权限持续到 direct-shadow writer；
- 权限跨 reset 保留；
- task response 成功等于 latch/raw 写入被授权；
- 存在自动 restore。

`0x8200f8` 是 direct-shadow 能否设置 latch 的独立关键缺口。当前项目既无本卡值，也无 GB202 FSP 降低它的直接证据。

### 5.2 `disable_sw_override`

主报告已在后文作出重要修正：`IsSwFusingAllowed` 的确检查 `0x8212ac.bit0`，但 direct-shadow `SetSwFuses -> Core -> ProgramSwFusePlan` 链没有调用该 helper。因此：

- “该 bit 是 soft-burn 路径的真实 gate”为 **V-STATIC（MODS 570.151）**；
- “该 bit 会阻断 direct-shadow writer”为 **UNKNOWN**，只能由硬件/更低层行为决定；
- 主报告开头把它与 direct-shadow 权限并列时，应避免读成已闭合的直接调用门。

### 5.3 HULK 与 host security level

MODS 的 network security level 4/5 是 host 软件 gate；HULK 是签名/设备相关材料经 NVDM/FSP 处理的设备授权机制；GSP/FSP/SEC2 的认证又有各自边界。三者不能互相替代。

MODS 样本中的 HULK 接口名和 sender 相关字符串为 **V-STATIC（MODS 570.151）**；主报告对签名大小、设备相关检查和发送控制流的进一步结论为 **REPORT-ONLY（详细静态论证，本审计未独立重放该段）**。当前 610 固件字符串和公开 NVDM 常量证明协议名/类型存在，但公开 610 host 源码没有 GB202 HULK caller/payload。项目也没有可用于本卡的授权材料。故“当前 production 610 可由某个公开入口激活 HULK 并开放 L2 writer”仍为 **UNKNOWN**。

旧 Figueroa/2015 证书、旧 PMU binary 或其他卡的证书不能当作 GB202 授权证据；设备绑定信息反而是反对这种外推的证据。

### 5.4 repair

通用 GSP repair 文案和 `RMCFG_FEATURE_LTS_REPAIR=1` 证明“共享实现/功能族存在”。“repair 是用 spare 做等量 swap，而非扩容”得到文案与构建注释支持。主报告的 GB202 index-65 no-op 结论若成立，则 GB202 路径甚至不会执行通用 swap。

这两句并不矛盾：前者描述共享实现，后者描述芯片 HAL。审计建议把 GB202 no-op 标为 **REPORT-ONLY（待归档重放链）**；无论取哪一层，repair 都没有成为增容证据。

## 六、旧材料与当前 GB202/610 的适用性

| 材料 | 可保留的意义 | 不得外推的内容 |
|---|---|---|
| 390.67 旧 PMU/HULK、Type-7 RMW | 历史上存在安全微码介导的 fuse/PLM 模式 | GB202 的寄存器、消息格式、权限或可达入口 |
| GV100 secure PMU 降低 `f4/f8` | “latch PLM 可能需专门安全固件”这一历史先例 | GB202 可以复用旧 binary、旧 caller 或相同 PLM restore 语义 |
| Maxwell/Volta 等旧 `dev_fuse.h`/floorsweep 字符串 | `NV_FUSE_OPT_*` 地址族和 disable 语义的旁证 | Blackwell 当前 mask 宽度、repair、FSP 路由或单元健康 |
| Hopper task-2 PLM precheck | task 2 与 PLM lowering 的强语义类比 | GB202 FSP 内部一定降低 d0/dc/f8、持续多久或如何恢复 |
| 2015/Figueroa HULK 资料/证书 | HULK 是受签名约束的安全机制 | 证书可在 GB202/本卡重放或可生成替代品 |
| MODS 570.151 GB202 包 | GB202-aware 私有 host 逻辑、RegHal 表、writer/reset 算法 | 当前 610 production RM/GSP/FSP 会接受同一请求；也不能证明包安全可运行 |
| 610.43.03 OpenRM + 当前 GSP 固件 | 当前对象/HAL/NVDM transport、公开 control 和固件字符串 | 私有 MODS network gate、FSP firmware 内部 task 语义或 live PLM 值 |
| FE/RTX Pro GB202 VBIOS 样本 | 当前代样本之间的静态表差异 | 本机卡的运行时 floorsweep 状态或 encrypted Falcon 内部策略 |

当前项目应把“current”限定为两种不同含义：

1. **当前被研究的 MODS 样本**是 570.151；
2. **当前 production driver/GSP**是 610.43.03。

不能把“MODS 里有 GB202 分支”写成“610 production stack 已验证支持该私有写入流程”。

## 七、材料间的矛盾、修正和术语冲突

### 7.1 旧 brief 的 48 physical slice / 16 MC 结论已被新报告收窄

`L2_SLICE_RE_BRIEF.md:17-18` 把 `sum/avg=48` 称为“48 个 LTS(L2 slice)，板上钉钉”，并把 16 个 DRAM rollup 直接命名为 16 个内存控制器，进一步推出每控制器 3 slice。

`L2_SLICE_MAP_FINDINGS.md:3-7, 37-85` 已明确纠正：

- 48 只证明 LTS rollup instance 基数；
- 16 只证明 DRAM rollup instance 基数；
- 公共输出没有 indexed identity；
- “16 MC”和“3 slice/MC”未知。

审计判定：旧 brief 这一部分是**已被后续材料取代的过度推断**，不得继续作为事实引用。

### 7.2 96 `l2s`、48 rollup、48 active mask-bit unit 不是同一个名词

应固定区分三层：

1. **96 个 NCU `device__attribute_l2s_count`**：V-RUNTIME，官方属性命名；
2. **48 个 PerfWorks LTS rollup instance/class**：V-RUNTIME，匿名汇总域；
3. **48 个活动 2-MiB mask-bit 单元**：依赖 `8 x 0x12` 和 2-MiB accounting，因此是 REPORT-ONLY + INFERRED。

“一个 rollup 对应两个 `l2s`，也对应一个 mask bit”是最简、数值一致的模型，但现有数据没有绝对索引来证明该对应。主合同中的“48 个活动 LTS slice / 16 LTC”应附这一术语限定。

### 7.3 repair build flag 与 GB202 no-op

全局 build flag 为 1 与某芯片 hook 为 no-op 不矛盾。把 build flag 当作 GB202 runtime reachability 是错误推断。

### 7.4 reset-coupled 返回 0 与实际 coupling 未知

历史 RM control 返回 0（报告叙述）与当前 coupling 未知不矛盾。GB202 已静态
证明绑定状态感知 getter，且 getter 的物理直接输入是 fuse OR boot；但未留档的
旧 0 不是当前值，也没有直接覆盖 base，所以仍不能证明 hot reset 会被选中。

### 7.5 “task 2 降权”与 `f8` 未证实

“task 2 很可能处理 d0/dc”与“direct-shadow latch 仍可能因 f8 受阻”同时成立。把前者写成“writer 已具备设备侧权限”会造成实质矛盾。

### 7.6 主报告中已经撤回的中间判断

后续章节已纠正或收窄以下早期判断，引用时必须采用最终版本：

- post-program reset 不是固定 boot reset，而由 coupling 决定；
- 未留档的 reset-coupled control 旧值不是当前三项 coupling 的权威证据；
- `disable_sw_override` helper 不在 direct-shadow 调用链；
- generic repair 文案存在不等于 GB202 hook 可用；
- old PMU/HULK 不是当前 GB202 入口。

## 八、离线工具与输出的证据质量

### 8.1 self-test 结果

本审计复核结果：

- `gb202_reghal_offline.py`：self-test PASS；
- `gb202_fjson_offline.py`：`self-test: ok`；
- `gb202_iff_offline.py`：`self-test: ok`；
- `gb202_vbios_diff.py`：对本地 FE/Pro/Dell/HPE 样本的只读解析可重现主报告所述 BIT `i` 表基数差异、Pro-only `0x00822170` 和 v6 encrypted Falcon descriptor。

但 self-test 的证明范围不同：

- RegHal test 实际约束了解压表中的具体地址/字段，因此能支持静态映射；
- fjson test 使用 synthetic dummy，证明 parser/schema 逻辑，不证明拿到了 authentic `gb202_f.json`；
- IFF test 内置 `128 MiB`、`2 MiB/bit` 和 `8 x 0x12` 常量，因而对这些 GB202 板卡事实是**一致性测试，不是独立验证**；
- VBIOS exact-literal absence scan 只能证明明文字节模式未出现，不能排除编码、压缩或 encrypted firmware 内的策略。

脚本 SHA-256：

| 文件 | SHA-256 |
|---|---|
| `gb202_reghal_offline.py` | `e9cc196414125c3b420340b29988a783b72fea1f93a0f1bff2fcacce2a0eb5c2` |
| `gb202_fjson_offline.py` | `79f430fa585b8e46e5bb9349d2acfdf439027a009a628b741daee6710a0a8bab` |
| `gb202_iff_offline.py` | `e06cd7204cca10cdc325e6a3491065f4b686aa8218d5a24d5c9367c26ebaed2f` |
| `gb202_vbios_diff.py` | `90cefd37e109684119e98c5ab64ef382048710dcdc344e1cd4bb5d70abb517eb` |

**后续资源修正：** `gb202_reghal_offline.py` 已不再使用 `Path.read_bytes()`；
当前入口以 4 MiB chunk 扫描并增量 hash，只用 `pread` 读取候选压缩 stream。它在
`ulimit -v 131072`（128 MiB virtual-memory hard limit）下完成固定 MODS 的
`--self-test` 并 exit 0，仍得到相同 input hash、`header=0x8fd61aa`、19,999 行和
559,972-byte 解压表。修改与回归记录见
`parallel/gb202_reghal_streaming_regression.md`。因此原先的默认入口资源缺陷已经
修复；128 MiB guard 通过不是精确 RSS 测量，但足以排除整份 374 MiB heap copy。
后续 DeviceInfo2 审计还要求把工具的 absolute 输出限定成 fixed-selector
instance0 fallback；当前字段已改名为 `fixed_selector_bar0`，并明确不声称读取了
本卡 runtime class-`0x10` `devicePriBase`。fjson validator 同样只把该 fallback
作为辅助字段，真正校验目标仍是 domain-relative descriptor offset。

### 8.2 VBIOS 结论的边界

本地只读 diff 可重现：

- FE derived chain 的 BIT `i` 地址表为 72 项；Pro 样本为 73 项；相对 FE 的唯一新增项是 `0x00822170`；
- 主报告把 `0x822170` 静态定名为 `SYS_PIPE_DISABLE`，所以 Pro-only 项不是 L2 开关；
- 四个样本均有 6 个非空 Falcon descriptor，version 6、size `0x50`、encrypted；
- 没有发现 `8 x u8 0x12`、`8 x u32le 0x12`、raw/effective 地址明文字节；SW 地址可出现。

等级为 **V-STATIC（这些样本）**。样本之一文件名本身标记 `unverified_TPU`，derived chain 也不是 live-card dump；因此不能把差异当作本卡工厂 floorsweep 记录。HPE tag parser 输出中的 `FSP_RUN/8` 一类 printable tag 是启发式 cleartext 提取，不证明 task/subobject 语义。

### 8.3 MODS 审计输出的边界

`mods_audit/static/decoded/gpuargs.js` 可直接确认若干 fusing/reset/HULK 参数名存在；这只证明接口面，不证明安全、权限或本卡运行效果。

`mods_audit/dynamic_audit.md` 记录了历史上在无 GPU、无真实设备节点的 sandbox 中执行过 MODS 的帮助/早期失败路径。它证明的只是早期文件/ioctl 探测行为，不能证明 GPU 初始化或 L2 writer。当前合同禁止再执行 MODS；本审计没有重复该操作。

`EXPERIMENT_PLAN.md` 是计划文档，不是结果证据。任何其中可能涉及 live probe、MMIO、模块或 reset 的阶段，均已被 `GB202_PARALLEL_WORK.md` 的当前绝对禁令覆盖。

## 九、仍缺的证据（按阻塞程度排序）

以下只列证据缺口，不构成执行建议；在当前合同下不得通过新的 GPU/MMIO/MODS 操作补采。

1. **本卡寄存器状态原始留档**：8 个 raw、SW、effective 值及采集时间、driver/firmware hash、命令输出。当前只有主报告叙述。
2. **关键权限状态**：`0x8200dc`、`0x8200f8`、`0x8212ac.bit0`、override latch。现有 permission probe 源码没有 f8，且无任何 stdout。
3. **当前 reset-coupling 状态**：公开 control 在 GB202 上直接判别 fuse OR boot，
   但旧结果未留档、不代表当前值，并且 getter 不直接读取 base；没有当前、留档
   的三项权威来源。
4. **GB202 FSP task-2 consumer**：task/subobject dispatch、d0/dc/f8 的实际修改、授权持续时间、错误语义和 restore/undo。
5. **base 对公开 getter 的硬件/firmware 间接可见性**：guard 已校准为
   `isVirtual`，两个直接输入已校准为 fuse/boot，第三项 base 为 `+0x48` 且没有
   直接 load；可见 GSP 软件镜像已排除，但寄存器硬件副作用、reset sequencer
   或 FSP/GFW 是否隐式级联到前两位仍未闭合。
6. **raw -> effective -> topology 的接受/传播证据**：特别是不同 reset 类型下的 latch、shadow 和 effective 保留/清除规则。
7. **失败回滚证据**：writer 本身未见事务回滚；没有证明的安全恢复原语，也没有证明 latch/部分 raw 项在失败后必然清除。
8. **被屏蔽单元的物理健康与成因**：统一 `0x12`（即使接受该观测）与 SKU floorplan 相容，但不能排除 repair/PAC/ECC/时序缺陷或组合限制。
9. **L2/PAC 配对及可隔离故障身份**：现有 48 相对 rollup class 没有绝对物理索引，无法把未来错误归因到某个“新启用”的确定单元。
10. **authentic GB202 fuse JSON / IFF 当前行状态**：parser 和 CRC 已恢复，但目标 chain 坐标、原始行、空行和合法写入状态未取得。
11. **16 LTC 的原始 runtime 输出**：`gb202_fs_probe.c` 可表达该 query，但没有 stdout；16 DRAM rollup 不能替代 16 LTC。
12. **当前 production 610 与 MODS 570 私有流程的兼容性**：没有证据证明 610 GSP/FSP 会接受 MODS 570 所假定的所有状态和时序。

## 十、建议在主结论中采用的最小准确表述

在不修改主文档的前提下，本审计建议后续引用采用如下口径：

> 归档 NCU 数据直接证明该 RTX 5090 在采样时为 96 MiB L2、8 FBP、96 个 NCU `l2s` 属性，并暴露 48 个匿名 LTS rollup 域。MODS 570.151 的静态代码证明存在 GB202 raw/SW/effective 寄存器描述和一条受多重权限、非事务、reset-coupled 的 direct-shadow 写入流程。项目报告称本卡 raw/effective 为 `8 x 0x12`、SW 为 0，但对应原始读取没有留档；2 MiB/bit、128 MiB 满配和 48 个活动 mask-bit 单元是与该观测及拓扑相容的 accounting model，不是被屏蔽单元可用性的证明。当前仍缺 latch PLM、task-2 权限/恢复、reset coupling、raw-to-effective 传播和物理健康证据，因此不能安全或合法地交付解锁器。

这是现有本地证据能够支持的最强结论；再强的表述会把静态能力、历史类比或未留档观测误写成当前 GB202/610 的硬件事实。

# RTX 5090 / GB202 L2 重新启用：静态逆向结论

更新日期：2026-07-22

## 结论

当前还不能安全地写出“把 96 MiB 变成 100/110/128 MiB”的工具。

已经排除两条看起来最直接的路径：

- MODS 的 `fbp_l2slice_enable` 不会清除芯片当前的硬 L2 屏蔽位；
- GSP/InfoROM 的通用 LTS repair 语义是“退役一个活动单元，再换上预留备用
  单元”，不是增加总容量；MODS 的通用规划器只把 software CTRL 中预留的
  L2/PAC 配对算作备用。更直接的是，当前 610 inner GSP 的有界构造重放已证明
  GB202 index 65 把 repair、marking 和 apparent commit 槽 `+0x188/+0x1b0/+0x6a0`
  都绑定到返回 `NV_OK` 的无副作用短桩，而非真正实现；公共 `+0x5e8` handler
  的内层 repair 调用仍落到该短桩。此前实卡 L2 CTRL=0 只属未归档
  `REPORT-ONLY`，但即使不依赖该报告，当前 GB202 也没有接上这条 repair 路线。

现在确认有两条不同的软件熔丝路径，不能再把它们混为一谈：

- SW IFF 路径把逻辑熔丝变成 11-bit chain 记录；其格式、Blackwell 尾部和
  CRC 已恢复，但仍缺 `gb202_f.json` 中的 `fuselessFuse` 坐标和本卡原始行状态；
- Blackwell `NewFuse.SetSwFuses` 还有一条**不经过 IFF** 的直接 OPT shadow
  路径。它先发出 `0x820040.bit0=1` 请求，再按计划中的原始 offset/value 调用
  OPT shadow writer，并逐项回读。host 不检查 latch 请求或 raw-write 调用的返回
  值；普通回读不等会记错，但权限哨兵 `0xbadf510c` 只记日志而不让 aggregate
  失败。按已恢复的 ordinary writer ABI，要命中 L2 raw 目标所需的
  plan/descriptor offset 已能精确落到 `0x34e0 + 4*FBP`。固定 selector 的
  instance0 fallback base 是 `0x820000`，展开后为物理 raw family
  `0x8234e0 + 4*FBP`；该物理地址另有 GSP/RegHal 交叉证据。MODS 的 runtime
  resolver 若发现 PTOP DeviceInfo2 class `0x10`，则改取硬件 record 的
  instance0 `devicePriBase`。本卡该 record 未读取，所以任何未来离线计划仍要做
  runtime base 一致性检查；不过公开 610 对 GB202 的 primary FUSE getter 已证明
  无状态地固定返回 `0x820000`，正常 record 若存在也强预期与该架构常量一致。

DeviceInfo2 的设备类型翻译也已完成独立闭合：GB202 PTOP raw type `0x22`
机械映射为 MODS internal class `0x10`，而本地 NVIDIA 公开源码又把普通 fallback
`0x820000` 明确命名为 `NV_FUSE0_PRI_BASE`。因此把该 class 解释成 fuse PRI
aperture 现有强交叉证据，不再只是数值碰撞；精确的私有 C++ enum token 和公开
PTOP 宏名仍未发布。本卡是否真的枚举 raw-type-`0x22`/instance0 record、以及该
record 的实际 base 仍未读取。完整 51 项 GB202 翻译表见
`parallel/deviceinfo_class10_identity.md`；公开 getter 与 reset 稳定性见
`parallel/deviceinfo_reset_stability.md`。

第二条路线把问题从“地址未知”推进到了三个互不替代的门：普通按名称入口仍需
外部 JSON 描述器；`ProgramSwFusePlan` 先要求 MODS 进程内
`SecurityUnlockLevel > 3`；较早的 FSP task-2 路径另有 QCAP `0x13` presence
检查和独立 command status，但二者都不证明设备权限已经改变；设备侧 raw L2 与
latch 又分别面对 `domainBase+0xdc` 和独立 `domainBase+0xf8` PLM。现已把
`disable_sw_override` 定位到 `0x8212ac.bit0`，其独立读 PLM 定位到
`0x8200fc`，但本卡这些 PLM word 均未读取，也没有证明 production GB202 task 2
的实际 lowering effect 或 lifetime。新确认的正常写入尾声会自动进入
一次 RM 状态卸载/重载；具体是 `hot/boot/fuse/base` 中哪种 reset，由 GB202
当时的 reset-coupling 位选择，并不是 host 无条件写死为 `boot`。因而确实
存在让 GSP/RM 重新枚举拓扑的重型状态转换机制；尚未确认的是零售卡
权限、本卡当时会选中的 reset 类型、override 在转换中的保留情况、raw OPT shadow 到
`0x822900` effective 视图在重枚举中的传播，以及被解屏蔽单元的物理健康。
当前 GSP 中 `0x132ef40` 的函数体已确认直接消费 `0x822900` effective 视图；
新的有界 FB 构造重放也已归档，直接证明 GB202 index 65 的非 MIG LTS-mask getter 槽
`+0x9c0` 安装该函数。因此这条绑定现为 `V-STATIC`，不再只是旧报告值。
目前没有发现 GSP 另有一张 5090 固定 96 MiB 常量表。

进一步的 raw→effective 数据流审计把这个缺口夹出了上下界。固定 GSP 中确有
`0x8234e0+4*FBP` raw A 的读取 wrapper，也有 `0x822900+4*FBP` effective B 的
读取 wrapper。此前被归为“能形成 B 类地址的通用 setter”的 `0x15d3a98` 已被
对象 class ID、GB202/GH100 HAL 绑定、NVLink control method ID 和公开 MINION
寄存器名共同反证：它实际是 **GH100-only Ioctrl/MINION NVLink EOM DLCMD
sender**，其中 `0x0a40` 是 `0x2900/4` 的命令数组下标碰撞，不是 effective-B
offset；GB202 对应槽位又分别绑定 no-op/`NV_ERR_NOT_SUPPORTED` stub。它应从
B-writer 候选集合彻底删除。当前可读 GSP、OpenRM 和 MODS normal success path
中没有发现“A 的返回值 -> 变换 -> 写 B”的软件数据流，FModel
property 又只在仿真条件下做 coarse mask intersection。这排除了 host/GSP 中一个
显眼的固定 `0x12` copier，却**没有证明硬件会自动传播**。真正采纳点仍可能是
reset 边沿下的 hardware sense/rollup、FSP/GFW 或隐藏状态 replay；逐 bit 公式和
各 reset type 的采样时刻仍未知。见 `parallel/raw_effective_propagation.md`。
假 setter 的完整 Ioctrl/HAL/method-ID 归因见
`parallel/effective_setter_provenance.md`。

`0x8200f8` 的可见 GSP 线也有一项重要纠错。`0x0108c494` 虽然确实读取
`f8.bit4` 并在旧芯片上为 NVDEC ucode encryption 设置 `+0x40/+0x13c`，但
OBJBSP constructor 重放证明它只绑定 TU102/TU116；GB202/index 65 的同一方法
槽安装无副作用 success stub。因此它不是 5090 的 latch 权限入口，也不能支持
“GB202 GSP state-load 会顺便准备 L2 latch”的假说。剩余 f8 权限缺口进一步
集中到不可见 FSP/ROM/签名 payload 或硬件策略，而不是这条明文 GSP helper。

另一个新的 OBJGPU 构造重放修正了此前 reset-coupled 分析中的实质性错误：旧分析
只看到 group-1 bitmap `0x98000000`，漏掉了 group-2 bitmap `0x303f`。GB202
index 65 / low 1 实际把非平凡、状态感知的 `0x144d4e8` 安装到 `+0x668`，不是
恒假默认桩 `0x19508c4`。该绑定现为 `V-STATIC`。进一步的 getter/setter 交叉
审计又确认：其 `+0xb68` guard 是 `isVirtual`，物理路径实际返回
`fuse_coupling || boot_coupling`；对应 device-relative 位为 `+0x40.bit0` 与
`+0x44.bit0`。第三个 `base_coupling` 位在 `+0x48.bit0`，该 getter **没有直接
读取它**。因此公开 control 虽仍只返回一个 bool，却不能笼统解释成三项全 OR；
历史返回又没有 stdout 留档，所以本卡当前三项状态和最终 reset 类型仍未知。

NVIDIA R580.126.09 release note 还提供了一条必须严格限域的官方旁证：FSP
确实存在“依 PLM 条件决定是否 reset”的逻辑，某项修复通过 source isolation
禁止 FSP 访问一个未指明 owner 的 RESET PLM。但公开 GB202 reset 源码中能
明确定位的 `0x1103c4` 是 **GSP Falcon 自身 reset-control PLM**；它不是上述
device-relative coupling targets `+0x40/+0x44/+0x48`，也不是相邻
`+0x308/+0x30c/+0x310` PLM words。相关明文文件在 580.119.02 到
580.126.09 间没有语义变化，更新的 GB100/GB202 firmware bindata 又无法按
单项修复归因。因此这条官方资料只证明机制类别相容，不能证明 RTX 5090 的
coupling 归属、base/fuse/boot 级联或该修复适用于 GB202。详见
`parallel/official_fsp_plm_scope.md`。

进一步的 success-tail 审计也确认：MODS 只在 reset 前读回 raw plan，reset 后
不会自动比较 latch、raw、effective mask 或最终 L2 容量。因此“原厂流程预期
shadow 经 reset 被采用”是强设计推断，不是硬件保持保证，MODS 返回成功也不是
扩容验收。另有 GSP-offload physical/non-MIG 路由上的
`GET_FS_INFO/LTS_MASK` handler/getter 已静态确认读取 effective 拓扑，可作为
未来独立前后对照候选；本卡 live allowlist/返回状态仍未验证，而且它不返回
raw/repair provenance 或健康。
对公开 610 正常启动链的补充审计也排除了一个容易高估的“隐式验收”：host 会
检查 FSP/GSP 是否启动、RISC-V 是否存活以及各 engine `StateLoad` 是否成功，
但这些是启动存活性检查。`GSP_INIT_DONE` 的相关 payload 只携带 `bIsD3Hot`，
`GspStaticConfigInfo` 也不含 LTS mask/count 或 L2 size；公开 normal boot 没有
自动调用 `GET_FS_INFO/LTS_MASK` 后比较 expected/actual。私有 GSP/FSP/GFW 或
硬件内部是否另有自洽检查仍为 UNKNOWN。完整证据见
`parallel/effective_mask_boot_lifecycle.md`。
该 baseline 现在也已收敛出不依赖 MODS 的最小用户态对象链：只打开
`/dev/nvidiactl`，分配普通 RM client/device/subdevice，再查询 FBP mask 和逐
FBP LTS mask。旧探针额外打开 `/dev/nvidia0` 并注册 fd 是多余的，且实际设备
节点首次 open 在未初始化情形可进入 `nv_start_device()/rm_init_adapter()`，未来
版本不应保留。这个 control 的数据语义是只读 effective topology，但建销对象、
GSP RPC、拿锁和可能唤醒设备仍会产生有限 driver state，不能叫“零扰动”。本轮
没有编译或运行该客户端，也没有访问 live GPU。

新的 reset-domain 矩阵还把“跨 reset 生效”的未知拆成三种同样相容的底层实现：
latch/raw 物理保持、reset 边沿先采样后原寄存器可清，或 FSP/GFW 从不可见状态
重建 downstream rollup；现有 host 控制流无法区分。公开 GB202 SBR HAL 最终只
切上游桥 Bridge Control `0x40` 并等待配置空间恢复，四组 L2 状态均无显式动作。
另有公开源码证明 GB202 chip-reset boot model 会启动 FSP，但没有逐 reset type
的完整连接，更没有 FSP 如何处理这些状态的证据。因此 hot/SBR、boot、fuse、
base 和 resense 目前都不是已验证 rollback。

高层名称入口所需的 `gb202_f.json` 已在本地完整可识别归档链中确认
缺失；可编译信息只够重建语法与 raw 地址，不能替代 authentic descriptor。

因此当前状态是：**离线可以准确列出单个 raw-shadow mask-bit 的候选目标；只有
在未归档的 `8 x 0x12` 报告与 2 MiB/bit accounting model 都成立时，才能把它
条件性标成“理论 +2 MiB”。host plan 也能稀疏表达理论 `98/100/110 MiB` 所需的
1/2/7 个 bit delta，但下层接受仍完全未知。目前仍不能安全、合法地写出主系统
可运行的解锁器。**
当前不尝试绕过 NVIDIA
认证门，不写 MMIO，也不把“能表示一个值”误当作“硬件会接受且能稳定启动”。

## 本卡状态：原始归档与报告值分层

项目现有原始运行归档可直接复核以下内容（`V-RUNTIME`，只代表归档采样
时点；证据位于 `l2_slice_re/raw/**/{lts_rollup,api_validation}.raw.csv` 和
`l2_slice_re/raw/20260713T092611+0800.LGScei/topology.summary.tsv`）：

- 设备为 RTX 5090，L2 容量 `100663296` byte，即 96 MiB；
- `device__attribute_fbp_count=8`；
- NCU 属性层为 96 个 `l2s`、每 FBP 12 个；
- PerfWorks rollup 层为 48 个匿名 LTS instance、16 个 DRAM instance、
  8 个 FBPA instance。

归档的 96 个 NCU `l2s` 与 48 个匿名 rollup 之间没有已证明的绝对身份映射。
即使进一步采用下述未归档的 `8 x 0x12` 报告，条件推得的 48 个 enabled raw
positions 也不能与前两者直接写成一一/二一物理映射。

此前研究报告还记录了以下一次只读结果，但项目中没有保存对应 stdout/raw dump，
所以目前只能列为 `REPORT-ONLY`，不能称为当前值或独立复核事实：

- 16 个 LTC；
- 8 个 FBP 的 raw/effective 低 8-bit disable 值均为 `0x12`；
- 8 个 software disable 值均为 0；
- `is_reset_coupled=0` 以及相关 PLM/latch 读取结果。

若 `8 x 0x12` 报告准确，并额外采用规则等容量的
2-MiB/raw-position accounting model，则每 FBP 的 bit 1、bit 4 被屏蔽，可条件
推得 16 个 disabled raw positions、总差额 32 MiB，
并得到 128 MiB 的完整配置模型。这个算术与 RTX PRO 6000 Blackwell 的公开
容量相容，但既不是被屏蔽单元健康证明，也不是本项目中一张 128 MiB GB202
实卡的运行归档。

寄存器**地址映射**已由 MODS 570.151 RegHal 表静态复核（`V-STATIC`），但
下列括号内的实卡值仍属于上述 `REPORT-ONLY`：

- raw OPT/shadow：`BAR0 + 0x8234e0 + 4*FBP`（报告值 `0x12`）；
- software disable：`BAR0 + 0x822080 + 4*FBP`（报告值 0）；
- effective disable：`BAR0 + 0x822900 + 4*FBP`（报告值 `0x12`）。

GSP 的 GR 拓扑枚举并不直接读取上述 raw OPT 槽；它经 Fuse 对象读取另一组
`BAR0 + 0x820d70 + 4*FBP` 状态/读出寄存器，再取反得到 ROP/L2 disable mask。
该组地址的当前实卡原始值尚未读取，不能把它和 `0x8234e0` 当成同一寄存器。

这条 `0x820d70` 路径是报告所述对象槽 `+0x9b0` 的 LTC/ROP-L2 状态掩码，
不是控制接口查询的 LTS 掩码。后者在普通非 MIG 模式走对象槽 `+0x9c0`；
`0x132ef40` 的函数体会通过 Fuse 读接口读取内部 offset
`0x2900 + 4*FBP`。RegHal 的 domain-5 映射把该 offset 精确还原为
`BAR0 + 0x822900 + 4*FBP`，即上面的 current/effective L2 disable 数组。
它在由两个拓扑 getter 算出的有效位宽内对 disable 值取反，得到该 FBP 的 enable
mask。函数体、地址映射以及 GB202 的 `+0x9c0` 绑定现均为 `V-STATIC`；重放
脚本和原始输出分别保存在 `parallel/gsp_fb_vtable_replay.py` 与
`parallel/gsp_fb_vtable_replay.results.txt`。

两组状态寄存器的粒度也已用命令行参数修正器独立区分：

- `fbp_ltc_enable/disable` 走对象 `+0x1c0`，读 `0x10d6c000 -> 0x820d70`，
  日志是 `FBP L2 current Mask`；
- `fbp_l2slice_enable/disable` 走对象 `+0x310`，读
  `0x10d64000 -> 0x822900`，日志明确多了 `L2 Slice`。

所以 `0x820d70` 是粗粒度 FBP LTC/ROP-L2 状态，而 `0x822900` 是按 FBP
展平的 RM LTS effective-disable mask 数组；这里的一个 mask bit 尚不能与
NCU `l2s` 或 PerfWorks rollup 的绝对物理身份等同，也不能把两组寄存器当成
同一个 mask 的别名。

这些地址只说明运行时屏蔽状态，不能直接换算为 IFF 记录。

### 普通 GSP LTS 枚举没有发现 5090 专用容量常量

官方 `NV2080_CTRL_FB_FS_INFO_LTS_MASK` 对应的 GSP 控制分支已经离线对齐：

- 未启用 MIG 时，type-3 query 把调用者给出的 physical `fbpIndex` 传给 FB
  对象槽 `+0x9c0`，返回该 FBP 内 flatten 的 current/effective LTS enable mask；
  只有查询并汇总各 FBP 才组成整卡 effective-topology 视图；
- 启用 MIG 时，才读取 `MIG_GPU_INSTANCE` 的 active-LTC 位图和每 LTC 的 LTS
  分配字节，拼出该实例可见的 mask。

因此此前追到的 MIG 每-LTC byte 表只是分区分配元数据，不能拿来增加裸卡总容量。
真正的非 MIG 物理函数由 FB 构造扩展 `0x1b036cc` 安装。当前 610 generated
chip 表将 GB202 映射为 index 65；有界离线构造重放得到：

```text
FB +0x9b0 = 0x132ae68   LTC/ROP-L2 status mask
FB +0x9c0 = 0x132ef40   per-FBP physical-coordinate LTS enable mask
```

当前 610 generated 表把 GB203/GB205 映射为 index 66/67；相同重放确认它们
也在这两个槽选择 `0x132ae68/0x132ef40`，而相邻控制 index 64 选择不同函数。
脚本、输入固件 provenance、hash 和完整输出均已归档。该函数不查 PCI device ID、板卡
SKU 或 96 MiB 常量，而是读取每 FBP 的 effective disable word，再在拓扑宽度内
取反。这是一个积极结果：GSP 在这一层没有额外把 GB202 零售卡硬裁成固定容量。
但它仍不证明 `0x8234e0` raw shadow 的修改会被硬件接受并传播到 `0x822900`，
更不证明被工厂屏蔽的 L2/PAC 单元物理健康。

对 effective 数组的“写 ID”做完整交叉引用后，还排除了一个隐藏 host 回写器。
RegHal 确实定义了 `0x20d64000`，字段宽度 `[31:0]`，并与
`0x10d64000 -> 0x822900+4*FBP` 配对；但这个 field-setter ID 在可执行代码里
唯一对齐的使用点是 `0x106efe8`。它属于 `0x106ee40` 的 floorsweep-unit
switch L2 case，调用 `0x198a3f0`。后者的控制流是“由 field ID 找到父 read、
读取寄存器、抽取字段、写入调用者输出指针”，没有待写的新值参数。全 ELF 的
另一个同字节序列跨越一条指令的 displacement/immediate 边界，并不是该常量。

因此 `0x20d64000` 在这里是供通用 RegHal API 描述/读取字段的 setter 句柄，
不是 host 对 `0x822900` 的写操作。普通 floorsweep 真正写掩码的路径仍明确使用
`0x20360000 -> 0x822080`。目前没有发现 RM/MODS 在重载时把 effective L2 数组
硬编码回 `0x12`。后续对固定 GSP 的 A/B wrapper 只确认了独立 reader；原先的
caller-driven “B 类 setter”候选已证明属于 GH100 Ioctrl/MINION NVLink EOM
命令路径，而非 Fuse/FB 写入器。因此仍没有找到 A-derived B
writer/copy/recompute。
因此更新若存在，只能继续在 hardware sense/rollup、FSP/GFW 或隐藏状态 replay
中寻找；三者目前没有优先级证据。这个结果排除了一个可见 host/GSP 固定值
障碍，但传播是否被零售硬件/固件接受仍只能留作未知，不能由“没找到软件
copier”反证。

### GB202 RegHal 地址表已经离线恢复

MODS 内部确实带有压缩的普通寄存器地址表，但它不是缺失的 IFF/JTAG 坐标表。
此前容易把相邻的 GB203 表误认成 GB202；按文件名构造器重新核对后，GB202
对应芯片 ID `0xff2`，表头位于 MODS 文件偏移 `0x8fd61aa`。该表使用 zlib
压缩，解压后是 19,999 行、每行 28 byte 的累积差分 SOA 数据。

正确解码出的 L2 三组映射为：

- 软件 L2 屏蔽数组：read ID `0x10360000`，write ID `0x20360000`，
  `0x822080..0x8220bc`（16 个潜在 FBP 槽位，GB202 实用前 8 个）；
- 硬熔丝/OPT L2 屏蔽数组：read ID `0x1087c000`，write ID
  `0x2087c000`，`0x8234e0..0x8234fc`（8 个 FBP）；
- 当前生效 L2 屏蔽数组：read ID `0x10d64000`，
  `0x822900..0x82293c`。

代码交叉引用也确认 `0x1087c000` 的打印名是
`OPT_L2SLICE_FBP%u_DIS`，而 `0x20360000` 是 `L2SLICE_DISABLE` 的软件
setter。因此上述映射不是仅凭地址形状推断。

另一个容易误判的 OR 链已经排除。`0x107ea30` 确实查找了软件数组
`0x10360000`，但这次查找只为取得字段是否存在和宽度；最后
`0x107eca9` 真正 OR 在一起的两个值是：

- 粗粒度 raw `0x10894000 -> 0x823090`（ROP/L2 整体停用）；
- 每 FBP raw slice `0x1087c000 -> 0x8234e0 + 4*FBP`。

这段代码是把粗粒度控制器屏蔽与细粒度 slice 硬屏蔽展开到命令
mask，不是 `effective = raw | software` 的实现证据。`0x823090`、
`0x8234e0` 与软件数组都共用 `0x8200dc` PLM，但共用权限掩码
不代表它们的位语义相同。

新增的 `gb202_reghal_offline.py` 只读 MODS 文件并解压/查询这张表，不加载
MODS、不打开设备。内置测试会固定检查上述地址，MODS 样本 SHA-256 为
`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`。其读取器
现以 4 MiB chunk 扫描，不再把 392 MiB ELF 整份复制进 Python heap；在
128 MiB virtual-memory hard limit 下 self-test 通过，回归记录见
`parallel/gb202_reghal_streaming_regression.md`。

### 专业卡 VBIOS 多出的表项不是 L2

5090 VBIOS 的小写 BIT token `i` v2 在数据偏移 `+0x60` 指向一张 72 项的
地址表；两份来自 Dell/HPE 的 RTX PRO 6000 Server VBIOS 都是 73 项，且只
多出 `0x822170`。MODS 把小写 `i` 明确命名为 `BIT_TOKEN_INTERNAL_USE`；
主机侧解析器会解析这两个指针字段，但其通用 VBIOS 消费者跳过这两个字段，
所以公开 BIT 文档不足以证明该表的具体固件用途。

现在已通过 GB20x floorsweep 注册代码给两个可疑地址定名：

- `0x822170` / RegHal `0x10490000`：`SYS_PIPE_DISABLE`，其硬 OPT 视图为
  `0x8230c8` / `0x10b84000`；
- `0x822168` / RegHal `0x10390000`：`OFA_DISABLE`，其硬 OPT 视图为
  `0x8230bc` / `0x108fc000`。

所以专业卡多出的 `0x822170` 是系统管线屏蔽类别，不是额外 L2 开关，也不能
用来把 5090 的 96 MiB L2 改成更大容量。

对两份镜像内的 Falcon 表继续解析也没有出现可改的明文 L2 配置。FE 与 PRO
各有 6 个非空 Falcon 条目；所有 descriptor 都是 Blackwell v6、固定大小
`0x50`，且 raw bit 2 全部为 1；公开旧共用 `vDesc` header 把该 bit 命名为
`ENCRYPTED`，但 v6 同时置了旧定义称为 reserved 的 bit 3，故这里只保留中等
兼容性解释。两边相同位置都能从 descriptor 明文识别出 `OOBHUB` 和 `FSP_RUN`
标签，但后随私有区域近满熵且没有公开 v6 body，不能直接按明文代码/数据解释。
镜像全局扫描
同时没有发现 `0x12` 八连值、八个 little-endian
`u32 0x12`、raw OPT 地址 `0x8234e0` 或 effective 地址 `0x822900`；共同出现的
只是上述内部地址表中的软件 CTRL 起点 `0x822080`。

把样本扩大到两份 GeForce（FE、ASUS）和两份 RTX PRO 6000（Dell、HPE）后，
`app=0x24 / target=0x0f` 的 Falcon table index 34 条目都具有相同 raw word0
`0x0050060d`（v6、descriptor `0x50`、raw bit 2 set）。早期先从 padding/邻接
关系推断私有 `word1` 是紧随区域大小；后来在每个 descriptor 所属 nested image
的两-entry hash table 中确认 `raw0=0x22 | length=0x50+word1 |
SHA-384(envelope)`，四份 stored digest 均与重算逐字节一致。这里 `raw0=0x22`
是相对 table end 的 covered-start offset，正好跨过 `ffff + 0x20-byte PCIR`；
它不是 Falcon index，二者都等于十进制 34 只是巧合。因此 region **边界现已由
相邻 hash table entry 确认**，但 `word1` 的正式 v6 字段名仍未公开。切片结果为：

| 样本 | region bytes | region SHA-256 | 熵 |
|---|---:|---|---:|
| RTX 5090 FE | `0x29400` | `1a546c20674f...0597214` | `7.999017` bit/B |
| ASUS RTX 5090 | `0x29400` | 与 FE 逐字节相同 | `7.999017` bit/B |
| Dell RTX PRO 6000 8D | `0x36c00` | `3ba673453b10...590c09` | `7.999129` bit/B |
| HPE RTX PRO 6000 9E | `0x37000` | `125328597c20...99e9d9` | `7.999179` bit/B |

FE/ASUS 的完整 0x50-byte descriptor 与该 region 均逐字节相同；两个 Pro
样本各自具有不同长度和字节内容。四个终点都精确落在高熵数据转为
`0xab` 字节 `0xff` padding 的边界，另一个 descriptor 的跨样本邻接也支持该
切片规则。官方 610 的 Falcon v2/v3 struct 还把相同 `+0x04` 字段明确命名为
`StoredSize`，提供了跨版本模式支持；但公开解析器只接受 v2/v3，没有 v6 struct，
而目标条目本身又都是最后一个已登记 descriptor，终点既非下一个条目也非物理
EOF。相邻 SHA-384 record 现在把 envelope 长度和内容覆盖提升为直接字节事实；
但把 `word1` 正式命名为 `StoredSize` 仍是跨版本推断，不是公开 v6 schema。
高熵也只能与加密/压缩相容，不能自行证明算法或明文语义。

这项差分证明两个已保存的 GeForce VBIOS 复用了相同嵌入字节对象，而 Pro
样本的嵌入表示不同；它不能把差异归因于 96/128 MiB L2，也不能区分真正代码
变化与 build、打包、nonce/IV、签名或重新加密。相同 payload 仍可读取
fuse/OTP/InfoROM 后按设备分支，故它既没有找到一个可修改的 L2 字段，也不支持
把 Pro blob 移植到 5090。完整边界与哈希见
`parallel/fsp_v6_payload_compare.md`。

对 `vbios_diff/` 的完整清点还排除了“目录里其实藏着更多独立版本”的可能：14
个路径包含 updater、tar/RPM/scexe/fwpkg 容器和两个 exact-tail derived chain；
去重后只有 4 个独立完整 raw image，并只形成 3 组目标 descriptor/region 字节
对象（FE/ASUS 共用一组，Dell Pro 与 HPE Pro 各一组）。两份 GeForce 文件名还
明确带 `unverified_TPU`，两份 Pro 是升级包保存物而非设备回读；样本中没有“同
一 firmware build 跨 SKU”或“同一 board 只换 revision”的配对。因此 Pro 内部
差异反而证明不能把目标 region 的变化唯一归因于 GeForce/Pro SKU。完整容器/
派生关系见 `parallel/vbios_fsp_inventory.md`。

另一个本地小对象 `/tmp/fmc_gb202_prod.bin` 也已从候选列表中排除。它的
503,808 bytes 与 610 generated bindata
`g_gsp_gb20x_dyn_spdm_concatenated_fmc_prod_image.bin` 解包结果逐字节相同；
公开 `kgspGetGspRmBootUcodeStorage` 调用链把它明确归入 GSP-FMC/GSP-RM boot
image，由 FSP 验证/启动，而不是 FSP 自己的 runtime 指令体。当前最接近 FSP
consumer 的仍是上述三个 `app=0x24/target=0x0f` v6 对象，但 descriptor 均标记
encrypted 且切片近满熵，无法在不越过安全封装的前提下作 plaintext 指令审计。
所以本地仍没有可读的 GB202 task-2/subobject-1 consumer；完整对象分类见
`parallel/fsp_task2_consumer_followup.md`。

2026-07-22 的完整 artifact 复核又把“不可读”定位到了精确封装边界，而不是笼统
归因于压缩包。ZIP/TBZ/TGZ、RPM/scexe/fwpkg、raw-DEFLATE bindata 与 GSP ELF
嵌套都能静态走通；HPE 包在 GPU NVFW 后登记了第二个 `0x47fb0`-byte firmware
component，其内容与 MCXN236 MCU/PLDM firmware 相容，随后另有 `0x400`-byte
认证 footer；没有证据把二者认作 GPU FSP receiver。安装的两个 `ucodes_*.bin`
则只有 24-byte
`NVUCODES` header，余下 body 全零；可见 GSP/FMC 对象又是已运行 FSP 后续验证/
启动的 GSP boot material，不是 FSP runtime。当前驱动/包中没有 standalone FSP
image。最接近 device consumer 的仍是三个唯一 VBIOS Falcon-v6
`app=0x24,target=0x0f` 对象：每个 descriptor 都置 raw bit 2，旧共用 header
将其命名为 `ENCRYPTED`；公开 610 只定义 v6 的 4-byte descriptor header，
没有 body layout。因此 consumer 可能在
该加密对象、芯片 ROM 或另一未保存的认证展开阶段；当前材料不能三选一。完整
清单、offset 与 hash 见 `parallel/tmux_task2_artifact_inventory.md`。

2026-07-22 的三份唯一 `FSP_RUN` 对象差分进一步把“不同”与“能解释”分开了。
FE/ASUS 对象逐字节相同；FE、Dell Pro、HPE Pro 的后随 region 分别为
`0x29400`、`0x36c00`、`0x37000` bytes。Dell 到 HPE 除长度增加 `0x400` 外，
descriptor 内还有只出现在目标条目上的成对 `3 -> 4` 形态变化。三组 region
两两同位置 byte 相等率约为随机期望 `1/256`，bit 差异率约 50%，没有共同的
起始对齐 16-byte block。最符合全部证据的描述是“三个不同的 object/envelope
build revision，再经过加密/认证封装”，而不是只改 VBIOS 外层指针；但密文
不能证明 plaintext code、task-2 handler 或 L2 policy 一定不同。详见
`parallel/fsp_run_object_diff.md`。

公开格式边界也已收紧：`0x0050060d` 只能可靠拆成 raw flags `0x0d`、version
`6`、descriptor size `0x50`；公开共用 header 把 bit 2 命名为 `ENCRYPTED`，
但同一个 raw byte 还置了旧定义称为 reserved 的 bit 3，说明旧公开 header 并非
完整 v6 flags 规范。`+0x04..+0x4f` 均没有公开 v6 body 定义。28-byte opaque
tail 虽可在数学上拆成常见的 `12+16`，却没有证据把它定义成 IV/tag，且 descriptor
基址本身并非 16-byte 对齐；不能据此猜 cipher 或构造解密器。公开历史与边界见
`parallel/falcon_v6_public_research.md`。

启动链现在能闭合到更靠近私有边界的位置。公开 610 的 GB202
`kgspExtractVbiosFromRom` HAL 返回 `NV_ERR_NOT_SUPPORTED`，host 不提取或上传
`FSP_RUN`；chip reset 后由 BootFSM 触发 FSP，host 只等待 boot-complete `0xff`。
FSP 已运行后，host 才把公开命名的 `g_gsp_gb20x_*` GSP-FMC/GSP-RM 材料通过
COT 交给它认证和启动。因此最初 root-of-trust/loader 必须位于 device-internal
早期启动链；体积较大的 runtime 很可能来自 VBIOS 中的加密 `FSP_RUN`，但真正
v6 parser、task-2 handler 位于芯片 ROM、该对象还是另一认证阶段仍是 UNKNOWN。
详见 `parallel/fsp_boot_chain_trace.md`。

VBIOS 自带的 legacy x86 与 UEFI GOP 也已作为另一种 host-side consumer 被有界
排除。四份保存镜像各自的 `0xfa00`-byte legacy image 和 EFI compression type 1
GOP 都已离线解开为 checksum 正确的 x86-64 PE，但没有执行。legacy/GOP 中均无
完整 `0x0050060d`、`FSP_RUN` 或 `0x0f24` immediate；所有 raw `24 0f` 都能归为
`and al,0xf`、LEA displacement 或跨指令字节。唯一真正的 `cmp al,0x24` 与
`0x18/0x1e/0x30` 并列，是 24/30/36/48 显示格式/位深分支。GOP 有通用 PCIR
解析，但目标 Falcon entry/descriptor 全在这些 host code image 之外的数据区。
因此“GOP 明确解析 v6/FSP_RUN”没有证据；无专用 literal 的间接通用接口仍属
UNKNOWN。详见 `parallel/vbios_uefi_v6_consumer.md`。

HPE 升级包中保存的 `nvflash` 5.877.0 也没有补上这个格式缺口。对其 ELF 仅做
有界静态反汇编后，已定位 classifier `0x7dde66`：输入 `0d 06 50 00` 会依次
错过它显式支持的 v2/v3/v4 和 `NVFW` 分支，落入 catch-all enum 3，并被打印为
`FALCON_UCODE_DESCRIPTOR_GFW_STYLE_V1`。该路径完全不检查 `0x50`，还会把 v6
raw `+0x2c = 0x50534600`（可见 `FSP_RUN` 前缀）误投影成旧布局的 DMEM size；
所以这是 legacy 误分类，不是 v6 body 支持。有限常数/xref/指令形状检查也没有
发现第二套显式识别 version 6 + size `0x50` 的 parser。更新器仍可能把已签名对象
作为 opaque blob 搬运，但“能够刷整包”不等于“知道 v6 字段、能解密或能改写”。
全程没有执行该 binary；详见 `parallel/nvflash_v6_parser_reverse.md`。

同一 `nvflash` 的更新兼容路径说明“不是 blind copy”与“不理解 v6”可以同时成立。
它会按扩展名在 host 侧解析 DMTF PLDM `.fwpkg`，检查 UUID、声明 header size 和
CRC32，按 component table 切出定长 byte buffer；随后还会识别外层 `NVFW` magic
并复制/重排其中的 image range。PLDM/NVDM 更新错误则是在 virtual transport/
protocol 调用返回 response/status 后显示，包括设备/接口 verification outcome。
但外层结构识别没有补出 Falcon-v6 body parser；精确 verifier 仍不能从这些
有限窗口归到 host 或 device 的某一个具体组件。详见
`parallel/nvflash_update_compat_boundary.md`。

两份保存 `.fwpkg` 的外层也已按 DMTF DSP0267 1.0.1 完整拆分。Dell 是
`0xcf`-byte PLDM header 加一份完整 NVFW，到组件末端即 EOF；HPE 是
`0x14d`-byte header、完整 HPE NVFW、一个 `0x47fb0`-byte 第二 firmware component，
再加 `0x400`-byte footer。两者 header CRC32 都复算匹配，但 CRC 只保护 PLDM
metadata。HPE footer 还包含 P-384 public key 与 DER ECDSA signature；独立
OpenSSL 复核已确认该签名以 SHA-384 有效覆盖 `package[0:0x219fb5)`，即 header、
两组件、footer header 和随包 PEM key。它会阻止在原 HPE package 内改任意 covered
byte 后仍保留原签名，但 key 本身随包携带且没有 X.509 chain/可信 pin，所以只能
证明 package 内部密码学自洽，不能单凭本地字节认证 HPE/NVIDIA publisher；Dell
又没有同型 footer。外层结果既不证明 Pro NVFW 可跨 SKU，也不证明不可跨 SKU，
决定性条件仍在 inner NVFW/FSP/device policy。详见
`parallel/fwpkg_container_auth.md`。

公开 RM 与私有 updater 的协议边界也已闭合到消息类型级。公开 610 全树只出现
一次 `NVDM_TYPE_FIRMWARE_UPDATE = 0x12` 常量，没有其 payload、subcommand、
caller 或 FSP handler；公开 transport 只分片/重组 bytes，通用 response 也只有
`taskId/commandNvdmType/errorCode`。相对地，保存的 `nvflash` 中可以静态确认
NVIDIA vendor `0x10de`、NVDM type `0x12` 的七个私有 command（1..7）以及 raw
status receive，但命令名称、字段和与 PLDM state 的逐项对应仍未知。DMTF 标准
明确由 Update Agent 解析 package/component，而 Firmware Device 在 VERIFY state
用实现自选方法验证 code image；这与“device side 有最终验证职责”相容，但不能
单靠标准把 v6 verifier 命名为某个 FSP partition。公开 type `0x14` COT 则是已运行
FSP 验证/启动 GSP-FMC 的另一条链，不是 type `0x12`，也不是 `FSP_RUN` loader。
详见 `parallel/public_fsp_fwupdate_chain.md`。

HPE footer 的实际 consumer 另行审计后，不能再把这份数学有效签名当作已证明的
更新门。完整 `hpsetup_generic` 只把同一 `.fwpkg` 文件名交给 `nvflash`；后者已
定位的 PLDM parser 在读完两个登记 component 后直接返回，不要求 EOF，也不消费
尾随 `0x400`。footer magic、完整 SPKI/EC point 及常见 key hash 均未在 `nvflash`
或 component 1 中找到；`nvflash` 自带的四把 P-384 key 又属于 MCU/CEC
challenge-attestation 路径，fingerprint 全不相同。因此普通保存的
`hpsetup_generic -> nvflash` 路径强烈表现为忽略 footer，且没有找到 publisher
key pin。不同 HPE catalog/deployment 工具或未检查的间接路径是否验证它仍是
UNKNOWN；详见 `parallel/hpe_footer_consumer.md`。

明文 board/SKU binding 则确实存在，但位置在更外层。顶层 PCIR/NPDE 区分
GeForce `10de:2b85` 与 Pro `10de:2bb5` 及各 subsystem；Dell/HPE 的 PLDM GPU
applicability record 又完全同为 `10de:2bb5`、subsystem `10de:204e`、同一 UUID、
`APSKU=0x652` 和 PG153-SKU210。相反，`FSP_RUN` 邻接 PCIR 在四份样本中都只是
通用 `10de:2b80`。交叉矩阵还给出两个反例：FE/ASUS 的 subsystem、board directory
和三把明文 P-384 key 全不同，`FSP_RUN` 却逐字节相同；Dell/HPE 的 applicability、
board directory 和 key trio 相同，`FSP_RUN` 却不同。因此 outer metadata/key
lineage 与目标 object 不是简单一一映射；但 secure consumer 仍可同时读取外层
身份、硬件 ID、fuse 或 rollback state，文件相关性不能证明跨 SKU 接受或拒绝。
详见 `parallel/nvfw_sku_binding_compare.md`。

对象自身的完整性层又有一项比外层相关性更直接的证据。四份 target nested image
均有一个 `0x10 + 2*0x3c = 0x88`-byte hash table。第二条 entry 是
`raw_first=0x9f | raw0=0x22 | length=0x50+word1 | SHA-384(file[D:D+length])`；
table end 加 `raw0` 精确等于 descriptor `D`。第一条 entry 则独立 hash
`ffff + 0x20-byte PCIR`。FE/ASUS、Dell、HPE 的 stored SHA-384 都分别与完整
v6 envelope 重算结果逐字节相等。因此 descriptor 加后随 region 的每个 byte
都被 per-object digest 覆盖是 FACT，且 envelope 边界不再只靠 padding 推断。

更关键的是，nested image `base+0x209` 的另一条 48-byte digest 又精确等于
`SHA-384(file[base+0x45a:base+0x4e2])`，即覆盖整个 table header 和两条完整
entry，也覆盖 target 的 `raw_first/raw0/length/digest`。所以简单地改 payload、
再重算对象 digest 仍会破坏父摘要。当前 coverage 已闭合为“FSP_RUN envelope →
两-entry table → parent SHA-384”；尚未闭合的是 parent digest 邻近 96-byte
signature-shaped 字段的正式算法/序列化和设备 pinned root。`nvflash` 中存在
BCRT cert20/cert30、VDPA、HAT 与 security-zone verifier，但在签名范围和 root
尚未机械对齐前，不能把它们与 v6 descriptor 尾部或 HPE footer 混称为同一认证层。
详见 `parallel/bcrt_manifest_coverage.md`、`parallel/falcon_manifest_table.md` 与
`parallel/nvfw_auth_layout.md`。

该 binary 的本地来源链也已逐层核验：保存的 RPM 中唯一 `.scexe` member 与提取
文件逐字节相同；`.scexe` 从 file offset `0x2765` 开始的 gzip 解出四个 tar
member，其中原始 `nvflash` 数据区 `[0x5600,0xf934a0)` 与当前静态样本逐字节
相同，SHA-256 均为
`d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780`。
RPM 中可用的 SHA-1/SHA-256/MD5、payload/member digest、XZ check 和 gzip CRC
全部能复算通过，故“当前文件是精确提取物”是 FACT。但 RPM signature header
没有标准 DSA/RSA/PGP/GPG 公钥签名 tag，`.scexe`/tar 也没有 detached signature；
因此本地字节不能单独证明 HPE publisher authenticity，`prod-signed` 只属于相邻
firmware package 的文件名。这个结论继续支持“不执行该工具”的安全边界，详见
`parallel/hpe_nvflash_provenance.md`。

HPE 官方目录提供了有限的外部身份交叉证据：官方
[Linux VBIOS Flash Utility 页面](https://support.hpe.com/connect/s/softwaredetails?collectionId=MTX-932a73f6d33b4c5c&language=en_US)
确实列出 RTX PRO 6000、版本 `98.02.9E.00.01`、发布日期 2026-04-24，类型为
Firmware - Video BIOS、级别 Recommended、安装后需重启。这能确认对应产品/版本
发布记录存在，但公开页面没有给出本地 RPM 的精确 filename、大小、官方 SHA-256、
签名或 `downloads.hpe.com` 直链；因此仍不能把本地
`183c76f5...41784fe8` 当成 HPE 公布的 checksum。查询边界见
`parallel/hpe_official_catalog.md`。

正常启动后也没有发现安全的 plaintext 回读旁路。公开 GB202 `KernelFsp` 不继承
`KernelFalcon`，host 可见面止于 boot/scratch/version、GSP mailbox、固定
192-byte CMS2 log、MCTP/NVDM response 与 CPER/Xid；这些接口没有 FSP
IMEM/DMEM/code-image 输出。通用 Falcon ICD 的 memory read 需要写 debug command，
destructive dump 还会 halt core，CrashCat 又没有 IMEM/code packet，均不能当作
当前桌面卡上的只读回读。故现阶段既不能从 host buffer 取得解密对象，也不能借
“只读 GPU”安全恢复 plaintext；完整审计见
`parallel/fsp_postdecrypt_observability.md`。

这不能证明 FSP 内部绝不根据板卡或芯片状态处理 L2，只说明 FE/PRO 差别不是
一个暴露在 VBIOS 明文表里的 `96 MiB/128 MiB` 开关。若策略在 `FSP_RUN` 内，
静态 VBIOS diff 面对的是密文和签名，既不能可靠定位语义，也不能安全修改。
`gb202_vbios_diff.py` 已增加只读 v6 header/encrypted/tag 报告以复现该结论。

## 普通 `fbp_l2slice_enable` 为什么无效

MODS 570.151 中：

- `fbp_l2slice_enable` 和 `fbp_l2slice_disable` 都接收 `(FBP, mask)`；
- enable 分支先对用户掩码取反，然后与 disable 分支汇合；
- Blackwell 的实际 Apply 实现 `0x1066040` 会进入公共软件掩码写入器
  `0x107d450`；L2 分支使用 RegHal setter `0x20360000`，即只写
  `0x822080 + 4*FBP` 这一层软件 disable mask；
- GB20x 虚表 `+0x3a8` 的覆盖实现 `0x107f010` 会读取当前生效掩码
  `0x10d64000`。如果请求试图清除任何当前已屏蔽 bit，它会把当前掩码重新
  OR 回请求值；对应日志为：
  `Adding the FBP L2 Slice current Mask, adjusting ... disable mask ...`。

虚表同一槽位在 Blackwell 基类中的日志是
`-adjust_fs_l2_noc is deprecated ... integrated into -adjust_fs_args`，因此
`0x107f010` 的准确语义是 `AdjustL2NocFloorsweepingArguments` 一类的参数
自动修正；目前不能声称它是每一次 Apply 的必经调用。但这不影响静态机制结论：
即使关闭自动修正，官方 floorsweep 写入器也只控制额外的 software-disable 层，
最终 effective mask 仍会合入 raw/hardware mask。此前未归档报告称本卡 software
mask 为 0；若该报告准确，再写 0 也没有增容收益，但不能把这个 0 称为当前实卡
已复核值。

### `FsReset` 会把 raw 掩码复制到软件层，但它不是自动 reset 尾声

GB20x 的 `ResetFloorsweepingSettings` 继承链已追到 AD10x 基实现
`0x107f460`。它遍历 FBP，用读槽取
`0x1087c000 -> 0x8234e0 + 4*FBP`，再用写槽把同一值写到
`0x10360000 -> 0x822080 + 4*FBP`；粗粒度 hard mask 也有同类复制。
对 GB202 的完整虚表链为：

```text
GB20xFs/BlackwellFs +0x3b8  0x10661e0
  -> HopperFs reset          0x1071f00
  -> AD10x base reset        0x107f460
  -> raw 0x1087c000 read / software 0x10360000 write
```

但通用 FS apply `0x1095e50` 只在虚表 `+0x350`返回真时调用
`+0x3b8`。GB20x 的 `+0x350 = 0x1099a30` 查询的 JS 属性就是
`FsReset`。解码后的 `gpuargs.js` 也给出了完整门控：

```text
AddArg("fs_reset", ..., "g_FsReset", ...)
if (typeof(g_FsReset[DevInst]) !== "undefined")
    Subdev.FsReset = g_FsReset[DevInst]
```

`g_FsReset` 默认是空数组，所以没有明确 `-fs_reset` 时不会进入这条
raw-to-software 复制。全 ELF 中通用 FS 主函数 `0x1095e50` 也只有
`0x106fed3` 这一个直接调用者；RM state dispatcher 没有直接回到它。
因此不能把这次复制当成 `SetSwFuses` 后每次 reset 都会自动执行的
隐含操作。

此前只读报告称本卡 software L2 mask 已是 0，因此按该报告没有一份旧
`0x12` 需要清掉；原始输出未归档，不能把这个 0 当作当前实卡事实。若在
raw shadow 修改之前误用 `FsReset`，它会把当时的 raw 值复制到软件层并继续
屏蔽相同 bit。即使 software 当前确为 0，在 raw 修改后再执行复制也只会增加
写入和时序风险，不是已证明的必要步骤。

### GB20x 确实登记了 L2 的 SW/raw 双通道

进一步拆解 floorsweep 单元描述表后，排除了“raw L2 setter 只是 Blackwell
基类中的未使用模板”这一可能。Blackwell 基类虚表 `+0x5d8 = 0x1069750` 会
登记各单元；GB20x 虽在同一槽覆盖为 `0x1058530`，但覆盖实现通过常量表重新
建立了同样的正式描述对象。L2 条目位于 `0x105938c..0x1059596`：

- 内部单元类型为 `0x17`；
- 名称为 `L2SLICE_DISABLE` / `fbp_l2slice`；
- `0x1059428` 从 `0x920d2d0` 读取一对 RegHal setter：
  `0x20360000`（SW）和 `0x2087c000`（raw OPT）；
- 实例数来自 FBP 数量查询，描述对象的两个控制字节 `+0xac/+0xad` 均为 1。

公共构造器 `0x1064800` 证明最后三个参数依次为实例数及两个布尔属性；它并不
执行寄存器写入。初始化器 `0x1067c00` 会把 `Fs+0x468` 架构注册表中的完整
描述对象复制到 `Fs+0x4a0` 运行时哈希表，因此 raw 字段并不是在初始化时被
裁掉。

继续闭合两个容器的全部本地消费者后，结论比“相邻代码没有读取”更强：

- 运行时哈希表的查找器 `0x1063880` 的全部可执行调用点都位于
  `0x10663b5..0x106ccb9`；只有 `0x1066740/0x106675c` 从返回对象读取
  `+0x48`（SW setter），没有任何调用点读取 `+0x4c`；
- 有序注册表查找器 `0x1058300` 的全部调用点也已枚举。除架构登记/复制外，
  真实消费者只读取 mask 数组 `+0x78`；
- 整个 FS 代码簇中唯一的 `+0x4c` 读取位于复制赋值器 `0x105fd4c`，它只是把
  raw setter 从源描述对象复制到目标描述对象；运行时增量复制入口只处理
  类型 `0x0b/0x0d/0x0e`，不处理 L2 的类型 `0x17`。

所以 **GB202 软件栈知道 raw L2 通道且保留其元数据，但这版 MODS 没有把该
字段接入 host floorsweep 执行器**。普通 `fbp_l2slice_enable` 只有 SW 通道；
`0x2087c000` 不能通过给现有参数路径换一个开关而被调用。真正的 raw 写入器
仍是后面的 `NewFuse::ProgramSwFusePlan` direct-shadow 路径。

## GSP/InfoROM 的 LTS repair 为什么也不能扩容

610.43.03 inner GSP 中确有通用 LTS-repair 实现、reset-choice/no-spare 文案及
真实代码引用；这证明共享实现不是纯死字符串，**不证明 GB202 dispatch 可达**：

- `Marking LTS %d in FBP %d along with its pair for repair`；
- 提示执行 `bus reset` 或 `os reboot` 才激活维修；
- 没有备用单元时打印
  `Repairing LTS failed as there are no more spare L2 slices.`。

公开驱动构建配置也启用了 `RMCFG_FEATURE_LTS_REPAIR`，注释是
`Support for LTS swapping in-field`。这只表示通用功能族被编入；这里的关键词
**swapping** 表示现场替换而非扩容，per-chip constructor 仍可把实际方法换成
短桩。

MODS 中相应的通用维修规划器给出了更具体的规则：

1. 遍历 L2 软件 CTRL 掩码 `0x10364000`，以其中置 1 的 bit 数作为备用 LTS 数；
2. 遍历 PAC 软件 CTRL 掩码 `0x10e38000`，统计备用连接/路由单元；
3. 两个备用数必须相等，否则以拓扑异常退出；
4. 目标若出现在 L2 硬掩码 `0x10880000` 中，会被明确拒绝；连接的 PAC 若在
   硬掩码 `0x10e98000` 中，也会被拒绝；
5. 规划器同时生成 L2 和 PAC 的退役/替换映射，并要求同一 LTC 一次至多替换
   一个 slice。

因此，“备用”专指生产时预留、通过 **软件 CTRL** 停用且具备配套 PAC 路径的
单元。它不包括 raw/hardware mask 已屏蔽的单元。此前报告称本卡八个 L2 CTRL
掩码均为 0，但原始读取没有归档；在该报告成立的条件下，如果 PAC CTRL 也为
0，则备用数就是 0；如果 PAC CTRL 非 0，则两边数量不等，同样不能形成可用
备用。无论哪种情况，这条维修路径都不能把 96 MiB 变成
100/110/128 MiB。

GSP 文案明确有 paired-repair 语义，这与当前 accounting model 的数值相容；
但现有公开/归档数据没有证明 repair pair、RM mask bit、48 个匿名 rollup 与
96 个 NCU `l2s` 之间的身份映射。能保留的结论是：通用 repair 属于容量中性的
spare swap，而不是把硬屏蔽单元直接加入总容量。

当前对 GSP 芯片 HAL 构造表的有界离线重放已经把 GB202 适用性闭合到
`V-STATIC`：610 generated 表将 GB202 映射为 chip index 65（group 2 / low 1）。
基础构造器的 group-2 mask `0x3001` 不含 bit 1，分别把 `+0x188/+0x1b0`
选为两个短桩；独立的 extension 构造器重放使用
`--extension --stop-slot 0x6a0`，在 store `0x1b2b494` 把 `+0x6a0` 选为第三个
短桩。因此：

```text
OBJINFOROM +0x188 = 0x1975824   16-byte, return 0 / NV_OK
OBJINFOROM +0x1b0 = 0x1975874   16-byte, return 0 / NV_OK
OBJINFOROM +0x6a0 = 0x197605c   16-byte, return 0 / NV_OK
```

真正的 repair body `0x156df8c`、含 `Marking LTS` 的实现
`0x156e394/0x1581374` 以及 apparent InfoROM commit 方法 `0x157a72c` 都没有
绑定 GB202。这里的 0 是 success no-op，不是 `NV_ERR_NOT_SUPPORTED=0x56`；
同簇另有明确返回 `0x56` 的短桩，可排除混淆。GB202 仍安装公共
`+0x5e8=0x157b570` handler，但其 selector-3 调用会再次落到 `+0x188` 的 no-op。
构造重放脚本、固定 hash/输出和详细地址证据保存在
`parallel/gsp_inforom_vtable_replay.py`、
`parallel/gsp_inforom_vtable_replay.results.txt`、
`parallel/tmux_gsp_l2_repair.md` 与 `parallel/repair_final_crosscheck.md`。

对真正支持这些槽位的其他芯片，静态直接证据是“修改 `OBJINFOROM` 内部状态、
发起 4-byte backing-store request，并提示在 bus reset 或 OS reboot 后激活”；
把它概括为运行时提出、InfoROM 管理的 LTS-pair swap 是强推断，而不是 DRAM
row-remap 或仅制造阶段流程。请求是否形成特定 on-media record、非易失写入是否
最终成功，仍不能只靠静态文件证明。对 GB202 不应移植这条生命周期。
`pending LTS swap` 目前只在原因字符串指针表中出现，该表
不是 repair map；当前证据最多证明通用 repair record 与公开 flattened
floorsweep mask 是两种软件表示，不能证明零售 GB202 有一张独立、非空、持久化
且与 SKU mask 分开的 defect/repair map。

## GB202 的 SW IFF 路径

静态分析确认 GB20x 有真正的 IFF 软件写入器：

- 最多处理 128 行；
- 有行号、CRC、解析、执行和回读校验；
- 会检查 PRI 写权限；
- 权限失败日志包括 `No write permissions to set up soft burn` 和
  `Could not enable FMMC MIRROR ENABLE, no write access`；
- 写后不一致和非法 1→0 编码转换会失败。

GB202 的 `IsSwFusingAllowed` 不是编译期恒假。真实判断为：成功读取
`disable_sw_override`，且该熔丝值为 0，才返回允许。这里必须按路径分层：

1. 对 `IsSwFusingAllowed`/soft-burn 查询路径，`disable_sw_override` 必须读为 0；
   本卡当前值为 `UNKNOWN`；
2. GSP/PRI/firewall 仍须允许相关软件写入。该 helper 不在已审计的
   direct-shadow writer 主机调用链中，因此该 bit 对 direct-shadow 的更低层
   作用也仍为 `UNKNOWN`。

该门的精确位置现已由第二条独立控制流闭合：当 `Fuse.UseSoftBurn` 为真时，
`GB20xFuseAccessor::IsSwFusingAllowed` 不再按名称查询，而是用 RegHal constant
setter `0x407c4001` 直接比较寄存器。离线 RegHal 表将其展开为
`BAR0 0x8212ac.bit0 == 1`；比较成立时只在 `Fuse.UseFakeFuses` 也为真时放行，
否则拒绝真实 SW fusing。比较函数逐位提取字段再做相等判断，并非权限检查或
常量占位。因此：

- `0x8212ac.bit0 = 1`：`disable_sw_override` 生效，真实 soft-burn 被禁；
- `0x8212ac.bit0 = 0`：通过这道门，但仍不代表后续 PRI/GSP 写入一定获准。

该读地址还有自己的 access metadata：`0x107c4000/0x107c8000` 都把
`0xfffe` access offset 指向 `0x8200fc`。所以 `disable_sw_override` 的读取受
第三只独立 PLM 保护；它不是 raw L2 的 `0x8200dc`，也不是 override latch 的
`0x8200f8`。

当前无法通过 610 的公开 RM GET 接口读取本卡该位：公开 `ctrl2080fuse.h` 是
空壳，OpenRM 配置中的 `RMCFG_MODULE_FUSE` 为 0。虽然地址现已知道，裸 BAR
读取仍会涉及设备绑定、运行状态和权限边界，所以本阶段没有增加实机 MMIO
探针。

静态调用链现已继续追到底层：`GB20xFuseAccessor` 的成员并不是直接指向
Device handler，而是由 `NewFuse` 控制器构造时统一注入。权限检查实际走：

```text
GB20xFuseAccessor::IsSwFusingAllowed
  -> NewFuse::GetFuseValueByName
  -> 每个 die 的 SplitMacroEncoder::GetFuseValueByName
  -> 普通熔丝描述器/硬件宏缓存
```

`DISABLE_SW_OVERRIDE` 也确实列在 GB20x SKU handler 的支持名称表中，不是
遗留字符串。`SplitMacroEncoder` 会把传入名称标准化、在普通熔丝描述器树中
查找并返回对应 die 的值；其延迟初始化再经 `BlackwellFuseHelper` 和通用
FuseConfig 装入普通 macro 布局。这证明权限位有真实的普通熔丝读取路径，
但该路径没有提供 IFF 的 `chainId/offset`，也没有变成公开 RM 的安全读取接口。
上面的 soft-burn 快路径则给出了同一语义的直接寄存器位置。

继续枚举调用点后，需要再区分“可查询的允许条件”和“写入器实际强制的前置
条件”。公开 `IsSwFusingAllowed` callback 确实走：

```text
NewFuse vtable +0xc0 (0x1456860)
  -> MultiMacro 聚合器 0x146dcb0
  -> GB20xFuseAccessor vtable +0x80 (0x1516c50)
```

`0x1516c50` 在 `UseSoftBurn=true` 时用 `0x407c4001` 比较
`0x8212ac.bit0`，为 1 时仅在 `UseFakeFuses=true` 时返回允许；在
`UseSoftBurn=false` 时则按名称读取 `DISABLE_SW_OVERRIDE` 并要求值为 0。
但是对 `NewFuse.SetSwFuses -> SetSwFusesCore -> ProgramSwFusePlan` 的全部
调用点检查没有发现它调用这条 `IsSwFusingAllowed` 链。直接 OPT shadow
写入器在软件层实际强制的是后面的进程内 `SecurityUnlockLevel > 3`；
`disable_sw_override` 若仍阻断 direct-shadow，阻断点应是硬件是否接受
`0x820040.bit0`/raw shadow，而不是这个公开查询函数主动返回错误。零售 GB202
上该硬件耦合仍未验证，所以不能据此把 `disable_sw_override` 从风险列表移除。

目前还确认了第二个真实读取者：物理 fuse-binary 编程前的 FMMC mirror
precheck 会用 `0x407c4000` 比较该位是否为 0。MODS `.text` 中两个相关 constant
的直接立即数用途都进入 compare slot `+0x98`；没有找到直接立即数形式的 field
write 或原始地址写入者。这个负结果不排除表驱动/FSP/硬件 setter。host 可见的
direct-shadow success/failure、resense 也都不保存或恢复该位；它在
hot/boot/fuse/base 中的保持/重采样规则及本卡当前值仍为 UNKNOWN。两版 GSP 的
一个动态地址假候选也经 GB202 constructor 绑定排除为 `NV_ERR_NOT_SUPPORTED`
stub，不能冒充该位的当前 consumer。完整证据见
`parallel/disable_sw_override_lifecycle.md`。

## 更直接的 Blackwell `SetSwFuses` shadow 路径

继续追踪 `NewFuse.SetSwFuses` 后，确认 GB20x 的常用写入分支不是前述 IFF
记录执行器。完整静态调用链为：

```text
JS NewFuse.SetSwFuses              0x1446860
  -> NewFuse::SetSwFuses           0x14643f0
  -> NewFuse::SetSwFusesCore       0x14620d0
  -> SplitMacro 输入准备/编码       0x147b4b0 / 0x148b4c0
  -> MultiMacro 分发                0x1471530
  -> GB20x::ProgramSwFusePlan       0x1515ea0
```

`GB20x::ProgramSwFusePlan` 的行为很明确：

1. 进程内 `SecurityUnlockLevel < 4` 时立刻返回错误 3；
2. 通过 RegHal constant setter `0x404f0001` 尝试把 `0x820040.bit0` 置 1，
   但不检查这次调用的返回值；
3. 对计划里的每个 `(domain-relative raw offset, raw value)` 调用设备 handler
   的原始写接口，
   caller 同样不消费 raw-write 返回寄存器；
4. 用同一 offset 立即回读。普通不等值会累计错误 `0x79`，但特殊返回
   `0xbadf510c` 只记录 privilege-level violation 并继续，不设置 aggregate error。

它没有调用 `GB20x` 的 IFF writer `0x1515820`，也不需要把普通 BAR0 offset
换成 chain/bit 坐标。真实设备 handler 的 raw write/read 又分别直接委托给
GB202 `GpuSubdevice` vtable 的 `+0x238/+0x228`，最终进入普通 `RegWr32/RegRd32`
路径。这里后来闭合了一处重要的表示法区别：L2 计划项携带的是 fuse domain
内的相对 offset `0x34e0..0x34fc`；GB202 wrapper 将单独解析的 domain base
再加上去。PTOP DeviceInfo2 class `0x10` 非空时，该 base 取硬件 instance0
record 的 `devicePriBase`；class 为空时才用 fixed-selector fallback
`0x820000`，此时最终访问为 `0x8234e0..0x8234fc`。plan/JSON 中若误填后一个
绝对地址，wrapper 会再次加 base。逐跳证据见
`parallel/raw_filter_targets.md` 的 offset erratum。
parser/descriptor/plan 的独立复核见
`parallel/descriptor_offset_semantics.md`。
普通 GB20x factory 还被逐跳证明以 literal `instance=0` 构造 accessor；这在
两条 base-source 分支中都不变。此前所谓“运行时预建 instance-map”现已正向
识别为 GpuSubdevice 延迟解析 PTOP DeviceInfo2 后持有的 56-class 拓扑缓存，
不是特殊配置或任意 redirect hook。class `0x10` 有记录时，`0x1252200` 丢弃
固定 selector，按同一个 instance0 返回 record 的 `devicePriBase`；class 为空
才用 selector `0x10ef4000` 的 row0=`0x820000`，row1=`0xbf0000` 不会被 instance0
暗中选中。GB202 的 raw DeviceInfo2 type `0x22` 会机械翻译成该 internal class，
且公开 `NV_FUSE0_PRI_BASE` 命名闭合了它在此路径中的 fuse-aperture 语义；精确
私有 enum token 仍 UNKNOWN。成功 FS 主线会使缓存失效，下一次查询才重建。
本卡 class `0x10` 是否存在及
其 numeric base 仍 UNKNOWN。异常表的失败语义也已闭合：class 非空却缺
requested instance0 时，`0xdd2230` 不报错也不 fallback，而会读取
`vector.end()+0x18` 的越界 dword，raw wrapper 再把它当 base。当前没有证据证明
正常 GB202 表会违反“class 非空即含 instance0”的构建不变量，但安全模型不能
依赖未验证的越界行为。公开 610 client builder 只原样复制显式 `instanceId`，
既不排序、补零也不检查连续性；公开 lookup 反而明确返回 not-found/duplicate
错误。真正可能保证 instance0 的 physical-side parser 未公开，所以这条不变量
不能从开源侧补证。完整边界见 `parallel/fuse_domain_instance.md`、
`parallel/fuse_instance_map_lifecycle.md` 与
`parallel/deviceinfo_instance_nomatch.md`、`parallel/deviceinfo_instance_invariant.md`；class/type 身份见
`parallel/deviceinfo_class10_identity.md`。

该 cache 的 writer 时序也已闭合到可用精度。latch constant setter 是 RMW；若
cache 尚未建立，本次 plan 最早会在读取 latch 旧 word 时解析整张 DeviceInfo2，
随后 latch write 和每项 raw write/readback 都复用 `+0x698=1` 的同一 snapshot。
串行 `ProgramSwFusePlan` 内没有 task2、invalidator 或 reset，所以同一 plan 的
base 来源稳定。成功 floorsweep 主线则是 task2/host apply 完成后才调用
`0xdd2520` 清 vectors/flag，再可能做 post-FS reset；invalidator 本身不重建。
普通 `SetSwFuses` 的 post-program reset 则已闭合为相反结果：
`0x127b000 -> 0xdff7b0 -> 0xdfe3d0` 在 reset 返回后继续解引用同一个
`GpuSubdevice*`，可选 recovery reset 也复用它；可见 dispatcher 既不调用
`0xdd2520`，也不走 constructor/destructor 或触碰 `+0x158..+0x698`。因此在当前
570.151 的已见 host 路径上，writer 建立的 pre-reset DeviceInfo2 snapshot 会跨
post-program reset 保留，下一次 resolver 不会仅因这次 reset 自动重读 PTOP 表。
这不证明硬件表本身不变，更不证明 raw mask 已被采纳。见
`parallel/deviceinfo_cache_writer_timing.md` 与
`parallel/postreset_deviceinfo_cache_lifetime.md`。

这里的全表 invalidation 也不应被误读成 FUSE base 会漂移。`0xdd2520` 无 class
参数，会清空全部 56 个 device/engine vectors，最合理的用途是 floorsweep 后做
通用 topology cache coherence。更关键的是，NVIDIA 610 generated HAL 明确把
GB202 `gpuGetPrimaryFuseBaseAddr_HAL` 绑定到一个只返回
`NV_FUSE0_PRI_BASE=0x820000` 的无状态实现，与 MODS instance0 fallback 完全
一致。因此对正常 GB202，class-`0x10` row 若存在，其 `devicePriBase` 也有很强的
产品不变量理由应为 `0x820000`；仍未公开的是 DeviceInfo2 位在各 reset 边沿怎样
reload，以及本卡 live row，而不是已经发现了合法的 FUSE relocation。见
`parallel/deviceinfo_reset_stability.md`。

`0x820040.bit0` 还有跨架构语义旁证：MODS/GSP 中同构的 NVDEC ucode-encryption
强制例程会在配对 PLM 已允许时读取该地址、OR bit 0 并写回。不过新的 OBJBSP
构造重放证明该实现只绑定 TU102/TU116；GB202 index 65 在相同 `+0x338` 槽绑定
的是无副作用 success stub。因此这只能加强“共享 software-fuse override latch”
的历史/跨代解释，**不是** 5090 上一条可执行的权限准备路径。对 GB202 的主要
证据仍是 direct-shadow set、resense clear 及 RegHal 配对。完整绑定见
`parallel/gsp_f8_consumer_lifecycle.md`。

### 高层名称编码仍需要外部 JSON

普通按名称的 `SetSwFuses` 并没有完全摆脱外部描述文件。编码器延迟初始化
会进入 `FuseJsonParser2`；stock 名称入口必须先成功加载主 `gb202_f.json`，
派生的 `_POR.json` 和 `_fpf.json` 是可选 companion。主文件中每个目标
`Chip_options` record 至少需要对象 key/name、`bits`、`type`、`offset` 和
`customer_visible`。内部 descriptor 的 `+0x80` FPF 标志由 parser 根据主文件
或 FPF companion 的来源填入，不是主 JSON record 自己提供的必填字段；其余
已恢复布局为类型字符串 `+0x60`、位宽 `+0x88`、domain-relative raw OPT
offset `+0x8c`。

对 `FuseJsonParser2` 的字段解析继续反汇编后，`offset` 的语法也已确定：

```text
<十进制寄存器地址>
<十进制寄存器地址>|<MSB>:<LSB>
NA
```

没有 `|MSB:LSB` 时默认整段 `[31:0]`。解析器把地址、LSB、MSB 分别存入
描述对象，后续编码器原样取这个 32-bit 数值生成 raw write plan；这里的
`offset` 是 logical fuse domain 内的寄存器 offset，不是完整 BAR0 地址，也不是
IFF chain/row 坐标。

编码器对 `offset == NA` 的原始报错是
`%s has no OPT fuse register. Bypassing`，计划打印格式也是
`<name> @ <offset> to <value>`。所以 JSON 的 `offset` 语义已经能明确叫作
**OPT fuse register**，不是普通 floorsweep 软件掩码。再结合：

- 同名 `OPT_L2SLICE_FBP%u_DIS` 的 direct-shadow raw getter 对应 read ID
  `0x1087c000`；
- GB202 RegHal 将该 ID 的 8 个实例展开为 domain-relative
  `0x34e0..0x34fc`；配套 field-setter 是 `0x2087c000.[7:0]`。fixed-selector
  fallback base `0x820000` 将其展开为 `0x8234e0..0x8234fc`；runtime
  DeviceInfo2 分支则使用 class `0x10` instance0 的硬件 `devicePriBase`；
- NVIDIA 已公开的其他芯片 `dev_fuse.h` 也把 `NV_FUSE_OPT_*` 直接定义为
  `0x82xxxx` OPT 地址；

因此，要让 ordinary writer 命中 L2 raw shadow，其 descriptor/plan offset
必须为 `0x34e0 + 4*FBP`。固定 fallback 展开为 `0x8234e0 + 4*FBP`，并与独立
物理地址证据一致。本卡 runtime DeviceInfo2 row 尚未观察，但公开 GB202 primary
FUSE getter 固定返回 `0x820000`，所以正常 row 强预期与 fallback 一致；工具仍不
把这项架构不变量冒充 live capture。这仍不是对缺失
原厂 `gb202_f.json` 内容的直接观察。`0x822080`
是另一套 floorsweep software-disable 接口，不是这里缺失 JSON 中的 OPT
offset。

类型恰为 `dis` 时，编码器执行：

```text
raw = ~logical & ((1 << width) - 1)
```

所以在“宽度 8、类型确为 `dis`，且此前 `raw=0x12` 报告准确”这些条件下，
`raw 0x12` 对应 logical `0xed`；候选 raw `0x10`、`0x02`、`0x00` 分别对应
`0xef`、`0xfd`、`0xff`。
L2 名称中的 `_disable` 与该类型一致，但在缺失 JSON 原件时仍把这些 logical
值标为条件结论。更低层的 raw plan 可绕过名称/JSON，却不能绕过下面的权限、
认证和初始化问题。

JS 包装器的输入语法也已经从参数检查中精确恢复：`SetSwFuses` 只接受一个
array 参数，其中每项必须是长度为 2 的 `[name, integer]`。它不是此前文档中
写成的 JavaScript object。GB20x 名称表构造器逐个 FBP 生成的外部名称是
`OPT_L2SLICE_FBP0_DISABLE` 到 `OPT_L2SLICE_FBP7_DISABLE`；内部 floorsweep
描述器使用的小写 `opt_l2slice_fbpN_disable` 只是另一层元数据名称，不能混用。
这里记录调用语法是为了校正文档，当前没有生成或运行实卡脚本。

另外几个看似可能绕过 JSON/权限的入口也已经排除：

- `SetSharedSwFuses` 和 `ParseAndSetSwFuseInputs` 只是把不同输入格式展开，随后
  仍进入同一个 `SetSwFusesCore`、准备器和 GB20x 写入器；
- `SetSimulatedFuses` 的通用 JS 包装器会先调用 vtable `+0x108` 取得模拟熔丝
  提供器，再立即读取 `[provider+8]`。实际 `NewFuse` 的该槽是
  `0x14563f0`，只返回空指针；包装器没有空值检查。因此这不是 GB202 上的
  模拟写入口，调用还可能直接异常。虽然同一 vtable 的 `+0x360` 是空 setter，
  但在这条 `NewFuse` 路径上到不了它，不能把该 API 当作无害 no-op；
- `SetFsFuseList` 只把名称转交给各子对象，不携带要写入的值。

所以没有找到“换一个公开 JS 函数就能避开进程内
`SecurityUnlockLevel > 3` 门槛”的捷径。

另一个看似相关的 `SkipSwFuseCheck` 也不是写入权限旁路。它是 `GpuGcx`
对象的 GC6 测试属性：属性 setter 只改 `GpuGcx+0xafe`，初始化测试时再复制到
运行结构 `+0x61ba`。GC6 测试入口先通过 `GpuSubdevice` 的 Fuse 对象查询当前
是否处于 SW-fused 状态；若为真且该选项为假，就打印
`GC6 Test is not compatible with SW fusing.` 并返回错误。把选项设为真只会跳过
这项 GC6 测试兼容性检查；它不进入 `SetSwFusesCore` 或
`ProgramSwFusePlan`，也不改变 security unlock level、
`disable_sw_override`、PLM 或 raw write 行为。

#### `SetOverrides` 只改名称映射，不是 raw writer

`SetOverrides` 也已从 JS 参数层追到 Blackwell 的实际 handler：

```text
JS SetOverrides                       0x1445530
  -> NewFuse vtable +0x50             0x1456630
  -> [NewFuse+0x18] vtable +0x20      0x14ae130
```

最后一个槽不是从旧架构类推出来的：`BlackwellSkuHandler` 的 vtable address
point 为 `0x92f07d0`，`GB20xSkuHandler` 为 `0x92f1a10`，两者的 `+0x20`
都明确指向同一个 `0x14ae130`。

JS 输入仍是按名称组织的数组项，携带名称、整数值和一个可选标志；没有 raw
BAR0 地址、OPT offset、width、type 或 reset policy。`0x1456630` 只遍历输入
map 并逐项委派；`0x14ae130` 只在 `SkuHandler` 的红黑树中插入
`name -> override` 记录，重复名称时报 `Duplicate override for %s!`。整段没有
寄存器访问、shadow plan、network 权限检查、PLM、GSP/FSP 或 reset 调用。

后续通用解析辅助函数 `0x14a7060` 的顺序也表明 override 是附着数据：它先用
已经解析出的 fuse component 名称查询编码/访问适配器并取得当前数据，之后才
在 handler 的 override 树中查同名记录。也就是说，override 能改变一个已知
descriptor 的逻辑值，却不能凭一个任意字符串造出 raw 寄存器描述。由于
`SetOverrides` 本身不含 offset/width/type，它也不能替代缺失的
`gb202_f.json`，更不能绕过最终 `SetSwFusesCore` 的进程内
`SecurityUnlockLevel > 3`、PLM 和 reset
时序。

### SetSwFuses 编码器没有禁止降低 raw disable 位

MODS 里确实有一个 `ValidateFuseTransition`（`0x148e890`），会拒绝某些
fuseless/实体熔丝计划中的非法 `1 -> 0` 转换。但交叉引用表明它由
`0x148ed60` 和 `0x148f3c0` 两条其他编码路径调用；`SetSwFuses` 使用的是
`SplitMacro_EncodeSetSw`（`0x148b4c0`）。后者对 `type == "dis"` 直接执行
上述按位取反，再把 `(domain-relative raw OPT offset, raw value)` 插入 shadow
plan，没有调用
该 transition validator。

因此从 MODS 前端算法看，候选 raw `0x12 -> 0x10`、`0x12 -> 0x02`，乃至
`0x12 -> 0x00` 都不会仅因“disable 位从 1 变 0”而被编码器拒绝。这是比旧版
“软件熔丝只能继续关闭”猜测更积极的结果，但只说明计划能够生成；它不证明
零售 GB202 会接受写入，也不消除进程内 `SecurityUnlockLevel > 3`、PLM、
`disable_sw_override`、初始化时序和坏单元风险。

### host、FSP admission/completion 与设备 PLM 已经分层

MODS 自己的 security unlock level 枚举已经静态对齐：

| 数值 | 名称 |
|---:|---|
| 1 | `SUL_NONE` |
| 2 | `SUL_BYPASS_EXPIRED` |
| 3 | `SUL_BYPASS_UNEXPIRED` |
| 4 | `SUL_NVIDIA_NETWORK` |
| 5 | `SUL_NVIDIA_NETWORK_BYPASS` |

`ProgramSwFusePlan` 的精确 host predicate 是进程内
`SecurityUnlockLevel > 3`。4/5 是该 enum 的两个可通过值；它们在启动期由
bypass-record 分类和可选 NVIDIA-network Boolean 合成。这只放行 host
algorithm，不是 FSP credential，也不证明任何 PLM 已开放；本研究不尝试补丁掉
或伪造这道门。

#### security unlock level 的正常来源已经还原

`ProgramSwFusePlan` 在 `0x1515ea0` 调用的 getter 是 `0xd5d660`；它只返回
进程全局值 `0x186d6f74`。对应 setter 为 `0xd5d5d0`，公开跳板为
`0xd53520`。对整个 `.text` 的直接调用扫描只找到命令行解析器
`0xbb594c` 在 `0xbb5f3b` 调用该跳板：等级不是 `SetSwFuses` 脚本参数，也
没有在此路径上发现可写的普通 JS 属性。完整绑定复核进一步确认：
`SecurityUnlockLevel` 的 JS 属性只有 getter、setter callback 为 null；底层
dword 位于零填充 `.bss`，启动 setter 先把它写成 1，之后没有找到第二个直接
setter caller、周期性刷新或清除路径。故在已见 stock 流程中它是一次启动时
建立、持续到进程退出的 host 状态，不是 GPU/GSP/FSP 回包。

解析器读取重复的命令行参数 `-b <file>`；内置帮助对 `-b` 的原文是
`bypass file name`。每个候选文件必须恰好为 16 字节，随后按
`uint32 + uint32 + uint64` 读入并逐字段按位取反。静态分支为：

- 首字段必须等于魔数 `0x21ec8fb9`，否则该文件不给解锁等级；
- 第二字段等于特殊类型 `0x2faa67c2` 时给等级 4；
- 否则第三字段按毫秒时间戳处理：当前时间早于它时给等级 3，已经到期时给
  等级 2；
- 没有有效 bypass 文件时为等级 1；多个文件按解析器的组合规则汇总。

setter 随后才处理 NVIDIA 内网状态：`-no_net` 的作用只是跳过内网探测，
不会凭空生成等级 4。未指定 `-no_net` 且 TLS/证书探测确认位于 NVIDIA
内网时，普通等级会升级为 4，未过期 bypass 等级会组合成 5。程序内横幅也
分别写有 `Authenticated on NVIDIA network`、`Authenticated with bypass
file` 和二者组合的状态。网络端只产生证书验证成功/失败这一布尔结果；等级
4/5 是 MODS 在本地把该布尔值与 `-b` 分类结果组合出来的，不是服务器返回的
数字、账号 entitlement，也不是固件授权结果。

这道门在真实写入器中的位置也已逐指令固定。`ProgramSwFusePlan`
`0x1515ea0` 在 `0x1515eb4` 先取全局 level，并在 `0x1515eb9` 要求
`level > 3`；失败分支于 `0x1515ebe..0x1515ed1` 直接返回错误 3。设置
`0x820040.bit0` 的第一次 GPU 操作直到 `0x1515ed8` 才开始。因此在没有合法
通过值 4/5 时，这个具体 writer 会在碰 override latch 和任何 raw 计划项之前
退出。该顺序只约束 `ProgramSwFusePlan` 本身，不能把运行未知 MODS 的整个
初始化过程归类为无副作用；但它排除了“认证失败仍会先写半个 L2 计划”这一种
局部风险。

进一步的授权数据流复核证明，这个 host level 与 FSP floorsweep task 2 是两道
正交的门。`ProgramSwFusePlan` 自身不调用 task-2 sender/QCAP helper，也不把
level、bypass record、TLS certificate 或 session 状态放进任何 FSP packet；
task 2 位于更早的 GPU initialization/floorsweep 阶段，返回值也不会回写或提升
`SecurityUnlockLevel`。因此进程内 level 4/5 只允许 MODS 进入 writer，不能证明 FSP
或硬件 PLM 已放行。完整来源/时序见 `parallel/task2_auth_provenance.md`。

内网探测本身也已经从静态代码还原，不是主机名、DNS 后缀或可执行文件名称
判断。`0x8ba8960` 对下面八个固定端点并行启动线程，最多等待约 10 秒；任意
一个线程成功即可把缓存结果置为 true：

```text
hqnvmodsauth01.nvidia.com ... hqnvmodsauth04.nvidia.com
rnnvmodsauth01.nvidia.com ... rnnvmodsauth04.nvidia.com
```

每个线程最终进入 `0x8bc1b70`，以 TLS client 建立到 443 端口的连接，并且：

- 从包内同目录加载 `HQNVCA121-CA.crt`；该文件是自签名 CA，SHA-256 指纹为
  `F1:57:17:70:EB:DA:BE:7C:42:AE:CC:C4:D4:A9:65:1C:4A:1A:81:93:3A:02:46:D2:67:97:35:05:71:75:48:72`；
- 设置 peer verify 和 SNI，取得服务器证书后要求 OpenSSL
  `SSL_get_verify_result` 返回成功；
- 另外把 issuer 展成文本，要求同时包含 `DC=nvidia` 与
  `CN=HQNVCA122-CA`；
- 成功后立即把该端点视为 NVIDIA network，没有再发送账号、口令或 HTTP
  认证正文。

二进制没有导入或动态解析 `SSL_set1_host`、
`X509_VERIFY_PARAM_set1_host`，所以没有看到独立的证书主机名匹配；同时它把
cipher list 设成 `DEFAULT:@SECLEVEL=0`，显然兼顾旧内部 PKI。但证书链验证、
指定 issuer 检查和内网端点可达性都真实存在，所以仅伪造 DNS/机器名并不能
得到 level 4。本研究不连接这些内部端点，也不尝试伪造其证书或绕过认证。

这里还有一个容易混淆的同名机制：`-access_token`、
`-acquire_access_token`、`-release_access_token` 只对应开源 MODS 内核模块
的多客户端占用锁；驱动源码明确说明 token 是随机生成的会话互斥值，它与
security unlock level 无关。

已对当前下载包的展开目录、`Downloads` 和本地研究目录做只读扫描：没有找到
符合该 16 字节格式的 bypass 文件，也没有找到上述魔数的文件内容。公开精确
字符串检索同样未找到 NVIDIA 发布的格式或获取渠道。解析路径表面上没有调用
签名验证，但这不构成自行制造授权文件的许可；本研究只记录机制并寻找已有的
合法凭据，不生成或伪造 bypass 文件。启动来源、唯一 setter、TLS worker 与
生命周期的完整静态审计见 `parallel/mods_auth_level_origin.md`；合法签发和
获取渠道仍为 UNKNOWN。

设备 handler 还存在另一项真正的 `Check read write access`（vtable `+0xb0`）。
它不是静态白名单：先通过 `GpuSubdevice::RegRd32` 读取目标 PRI level mask，
再按以下条件返回：

```text
bit0 && bit4 && (!bit10 || bit12) && (!bit11 || bit12)
```

该布局与 NVIDIA 公开头文件中的通用 PLM 定义一致：bits 3:0/7:4 是读/写保护
等级，bits 10/11 是 source read/write control，bits 31:12 是 source enable。
GB20x 的硬熔丝准备代码会对 RegHal read ID `0x105bc000` 使用这项检查；该 ID
精确映射到 `0x820000`。所以这里确实存在实时硬件 PRI 权限门，而非 MODS 内部
一个可随意改的布尔值。

进一步还原 `RegHal_AccessOffset` 后，L2 目标自己的权限寄存器也能精确定位。
该函数用特殊索引 `0xfffe` 查询每个 read ID 的 access-offset 元数据；
direct-shadow raw getter `0x1087c000` 以及另一条 repair/tag-metadata 路径使用的
`0x10880000`，其 8 个 FBP 实例都返回 relative access offset `0xdc`；固定
selector fallback 下对应 BAR0 `0x8200dc`，runtime DeviceInfo2 分支则是
`devicePriBase+0xdc`。同一 RegHal 表又把该 PLM 的 `[7:4]` 定义为
write-protection field，setter/value IDs 为 `0x2059c000/0x4059c000`。其中
constant `0xf` 只表示四个 write-level bits 全开，并非整个 PLM word
`0x0000000f`，也不自动满足 read/source 条件。

对普通 SW L2 mask 的 read ID `0x10360000` 做同样的 metadata 查询，16 个
实例也全部返回 access-offset `0xdc`；其实际地址是 `0x822080...0x8220bc`。
raw OPT L2 mask 的 `0x1087c000` 则对应 `0x8234e0...0x8234fc`，但同样全部
指向 relative `domainBase+0xdc`；fixed fallback 即 `0x8200dc`。两套 field setter 分别是 `0x20360000.[31:0]` 和
`0x2087c000.[7:0]`。因此普通 floorsweep mask 与 raw shadow 在硬件权限层
共享**同一只 L2 PLM**；不存在尚待寻找的 raw-L2 专用 PLM。这个结论只闭合
权限归属：普通 host floorsweep 执行器仍只选择 SW setter，不会因此自动改写
raw OPT。

这里必须区分“字段定义”和“当前硬件值”：表中 `0xf` 只证明 MODS 知道怎样
表示全级别可写，不证明零售 5090 启动后 `0x8200dc.[7:4]` 实际仍为 `0xf`。
当前只确定了应该观察哪一个 PLM，仍没有对实卡做 MMIO 读取。latch 的 access
metadata 又独立落在 relative `+0xf8`，field/value IDs 为
`0x205c4000.[7:4]` / `0x405c4000=0xf`，fixed fallback 即 `0x8200f8`。
`dc/f8` 两只 PLM 自己都没有 `0xfffe` self-access metadata；host audit 因缺
metadata 会 pass，但这不证明硬件允许写 PLM 自身。当前 GB202 host 中也没有
找到已绑定的 direct lowering caller。完整权限矩阵见
`parallel/l2_plm_static_permissions.md`。

同时纠正一个早先命名误差：device handler vtable `+0x90` 读取寄存器并测试
字段是否等于 setter 的目标值；它用于判断 `0x820040.bit0` 是否已经为 1，
不是 read/write access 检查。真正的 access 检查是 `+0xb0`。

`ProgramSwFusePlan` 本身没有显式调用 `+0xb0`，但原始写仍走真实
`GpuSubdevice::RegWr32`，硬件/GSP 对 PRI 写的最终裁决仍然存在。能绕过前端
level 检查不等于寄存器会接受写入。

security level 检查的层次也已从每项写入链闭合。`ProgramSwFusePlan`
在函数入口只调用一次 unlock-level getter；通过后，每个计划项依次走：

```text
DeviceFuseAccessHandler +0xb8/+0xc0
  -> DeviceFuseAccessHandler 0x151ad00/0x151ad10
  -> GB202GpuSubdevice +0x238/+0x228
  -> 0xdb5540 / 0xdb68a0
  -> GB202GpuSubdevice +0x230/+0x220
  -> 0xdc74f0 / 0xdc6f70
```

新的 transport 审计还确认：这条 raw 路径根本不先进入 RegHal descriptor，因而
没有调用 `accessOffset`/PLM predicate；它只与普通 RegHal 在最后的
`GpuSubdevice +0x228/+0x238` 底层槽汇合。默认 ordinary backend 是 mapped
register aperture 的 32-bit load/store；只有 `Gpu.UseRmRegOps` 已启用且对象已
进入 RM-initialized 状态时，才改走 global `EXEC_REG_OPS`。MIG/SMC override 与
这个 transport 选择又是两层不同机制。

这两个 backend gate 的生命周期和特殊地址例外也已闭合。`GpuSubdevice+0x19c2`
构造默认清零，构造尾只会按显式 JS boolean `-use_rm_reg_ops` 一次性设置；RM
phase-0 成功只把独立的 ready byte `+0x19c0` 置 1，teardown 再清零，并不会
自动打开 `+0x19c2`。read/write fallback 虽还有特殊地址 policy，但 GB202
`+0xff0` 只匹配静态区间 `0xcc00..0xcc2c` 和条件化的
`0x400000..0x5fffff`；`+0xff8/+0x1000` 均绑定恒假 stub。在普通 identity
translation 下，`0x820040`、`0x8200dc/f8`、`0x8234e0..fc` 全不命中。exact
remap 的 default 来源也已闭合：全局 tree 的静态初始化 root/size 为 0，map
setter 的完整 direct-call scan 只命中显式 `-reg_remap` 的 JS callback，随包
参数没有该选项。因此无显式 flag 的 stock/default GB202 流程可高置信判为
identity 并更可能直接访问 mapped aperture；显式 `-use_rm_reg_ops` 且 RM-ready
时才确定走 `EXEC_REG_OPS`。任意未观察的外部 argv/dynamic state 仍不能写成
无条件事实。详见 `parallel/rmregops_lifecycle.md` 与
`parallel/reg_remap_lifecycle.md`。

因此每项 raw write/read 分发没有再次读取 MODS 的全局 security unlock level，
也没有 host-side fail-closed PLM precheck。进程内 `SecurityUnlockLevel > 3`
是在入口只检查一次的软件门，`0x8200dc` 等 PLM 的真实拒绝发生在更低层；二者
彼此独立。RegHal 的
`RegPrivCheckMode` 只影响某些 constant setter 的可选诊断 audit，audit 返回后
RMW 仍无条件继续，raw path 更是完全绕过它，所以它既不是安全授权，也不是
可靠的拒绝预测器。完整调用图见 `parallel/reghal_writer_transport.md`。

同一审计还证明 `0xbadf510c` 在已闭合 host 链内没有 generator：mapped-aperture
分支原样返回 32-bit load，RM-regops 分支原样返回 response `regValueLo`；
`ProgramSwFusePlan` 只是比较该值。raw-write call 后的 `RAX` 又立即被下一次
vptr load 覆盖，底层 control status 不进入 aggregate。故该 sentinel 至多说明
所选 backend/更低层以寄存器值形式报告异常，host 无法靠它区分具体拒绝层；而
现有 caller 还错误地只记录日志并继续。这个结论不意味着绕过前端门就能写成功，
也不改变本研究不补丁认证、不伪造凭据的边界。

公开 NVIDIA 驱动又把这个来源边界向下收紧了一层。其通用寄存器代码将
`(value & 0xfff00000) == 0xbad00000` 定义为 PRI-read error family，识别并
记录后仍保留原读值；Falcon 公共头还定义了 `0xBADF0000/0xFFFF0000` 的
CSB-PRI error family。官方 FSP/SEC2 代码甚至必须使用 unchecked/raw read
来观察硬件返回的 `0xBADF41YY` target-mask 错误。因此 `0xbadf510c` 不是
MODS host 私造的哨兵，而是寄存器 fabric/更低层 backend 返回的同类 PRI
错误编码；但公开 Blackwell 头没有定义精确 `0xBADF51xx` 与低字节 `0x0c`，
所以其具体 source/target 字段仍为 `UNKNOWN`。RM helper 同时检查 control
status 与 per-op `regStatus`，诊断尾却依旧返回 `regValueLo`，进一步证明
上层不能把这条路径当作可靠的失败传播。详见
`parallel/badf510c_provenance.md`。

`0x820040.bit0` 的设置本身不是 fail-closed 的确认点：
`ProgramSwFusePlan` 调用 `DeviceFuseAccessHandler +0x78`（实际
`0x151b6c0`）执行 RegHal constant setter `0x404f0001`，但忽略返回值，也没有
紧接着调用已有的 constant-compare 槽回读 latch。每个 raw OPT 计划项随后会
调用 writer 并立即回读，但 writer 返回值在 `0x151606e` 被覆盖。普通不等值会
累计错误 `0x79`；若 readback 返回 `0xbadf510c`，实际日志是
`Priv-level violation while verifying offset ...`，host 却只记日志、前进到下一
节点而不设置 aggregate error。所以上层既可能因普通 mismatch 跳过 post-program
reset，也可能在权限哨兵未被当成错误时仍误入 success/reset 尾。该路径不是
fail-closed 的验证器，更不足以把实卡试写归类为安全。

进一步沿错误分支核对后，可以把 host 侧结论说得更强：这条 direct-shadow
写入对 MODS host 而言**不是事务**，失败路径没有保存/恢复旧值的 host rollback。
FSP/GFW/硬件内部是否另有原子拒绝或以后恢复仍为 `UNKNOWN`。`ProgramSwFusePlan`
在遍历开始前尝试把
`0x820040.bit0` 置 1；某一 raw 项出现普通回读不符时，它只把首个错误记为
`0x79`，仍继续遍历并尝试其余计划项；权限哨兵分支甚至不设置该错误。函数内
没有保存旧 raw 值，也没有在返回前写
`0x404f0000` 清 latch。`SetSwFusesCore` 收到错误后，从 `0x14621fa` 直接跳到
`0x146219d`，跳过 post-program `+0x370` 及其自动 reset/reload，只调用两次
`0x1457470`；该函数完整行为是递归析构计划树并释放堆内存，没有 GPU/device
对象输入。最外层 `NewFuse::SetSwFuses` 在 `0x14646f1` 调用 core 后也只析构
两个本地容器并原样返回错误码。

所以调用后存在多种静态上都不能排除的中间状态：latch 写被拒且 raw 全未变；
latch 已生效但 raw 全被拒；前若干 raw 项改变而后续项失败；以及 readback 因
权限哨兵未被计错、上层仍进入 success/reset。没有一条 host 路径保存并恢复旧
raw 值。重启/显式 resense 或许最终能恢复
实体熔丝拓扑，但这不是失败路径自身保证的，而且类型 6 resense 本身也是重型
设备状态转换。故“写一个值、立即读回，不对就退出”不能定义成无害探测；在
桌面正由该卡驱动的主系统上尤其不能试。

### override latch 另受 `0x8200f8` 保护，`UseTestValues` 不是降权入口

继续展开 RegHal 的 access-offset 元数据后，`0x820040.bit0` 与 L2 raw OPT
并不受同一只 PLM 保护。latch 的 read ID `0x104f0000` 有两行：普通实例映射到
`BAR0 0x820040`，特殊索引 `0xfffe` 的 access offset 则是 `0xf8`。因此
RegHal access metadata 把 latch ID 的设备侧 access PLM 指向 `0x8200f8`；
这是独立的静态 PLM 关系，不证明该 PLM 的当前值、latch 的总体可写性或写请求
会被接受。即便暂时接受“task 2 旨在降低 `0x8200d0/0x8200dc`”这一强推断，
也不能外推 task 2 同时处理 `0x8200f8`。

Blackwell 还保留了一个公开查询 `IsFusePrivSecurityEnabled`。GB20x 的完整
分发链为：

```text
JS callback                         0x1439fb0
  -> NewFuse vtable +0xc8           0x1456620
  -> MultiMacro                     0x146fa80
  -> GB20xFuseAccessor +0x70        0x1515690
  -> DeviceFuseAccessHandler +0xa8  0x151b000
```

最后一个函数只做 RegHal constant compare，不写硬件。按实际短路控制流，它
返回真的条件是：

```text
0x820434.bit0 == 1
AND
(
    0x8200f4.bit4 == 0
 OR 0x8200f8.bit4 == 0
 OR 0x8200e0.bit4 == 0
)
```

四个 compare ID 分别是 `0x409ac000`、`0x40e14200`、`0x405c4100`、
`0x404c8100`。这里必须按 OR 理解：第二个比较若成立就直接返回真，只有失败
才继续检查 `f8`，再失败才检查 `e0`。所以 `0x8200f8` 是 latch 的直接访问
PLM，也是 fuse-priv-security 查询考虑的三只安全 PLM 之一，但不是该查询中的
唯一总开关；更不能把“查询返回真/假”直接等价成 latch 当前可写/不可写。
现有归档没有本卡 `0x8200f8` 的读取结果；其当前值及一次 latch-set 请求是否
会被接受仍为未知。

旧 GV100 路径提供了严格限定的历史先例：`0x1454bd0` 会启动 secure PMU
事务，成功后由 `0x1455240` 用 RegHal setter `0x40e14100/0x405c4000` 把
`0x8200f4.[7:4]` 与 `0x8200f8.[7:4]` 写成 `0xf`；失败日志包括
`PMU ucode failed to lower privilege level` 和 `Secure PMU could not be loaded!`。
但该实现依赖只覆盖旧芯片的 `fusebinary_<chip>.bin`，不能移植性地套到 GB202。

尤其是，GB20x 的同名 `UseTestValues` 已经排除为这条旧 secure-PMU 通道的
替身。GB20x factory 在 `0x14315ed` 分配 `GB20xSkuHandler`，在
`0x14316b4` 安装 vtable address point `0x92f1a10`，并在
`0x1431ebd -> NewFuse::NewFuse` 时把同一对象转移到 `NewFuse+0x18`。
于是：

```text
NewFuse::UseTestValues  0x14564a0
  -> [NewFuse+0x18] vtable +0x50
  -> GB20xSkuHandler     0x14a1e80
```

`0x14a1e80` 只有一条有效动作：把 `SkuHandler+0xe8` 的软件布尔值设为 1；
相邻 `+0x58 = 0x14a1e90` 只是读回该布尔值。这里没有 RegHal、PRI、FSP/PMU、
`SecurityUnlockLevel` getter/setter 或 reset 调用。作为交叉检查，stub factory 对应的
`StubSkuHandler+0x50 = 0x1421010` 甚至直接返回。故 `UseTestValues` 只选择
测试值数据源，不会降低 `0x8200f8` 或授予 raw writer 权限。

对 MODS 可执行 `.text` 的常量/指令边界扫描也只在旧 GV100 setter 中找到
可执行的 `0x405c4000`，未找到 GB20x 的 `0x205c4000/0x105c4000` setter
调用。对 GB202 GSP RV64 text 的直接 `0x820...` 基址使用逐条展开后，ELF 中
唯一的 `0x8200f8` direct block 确实属于 NVDEC encryption/latch 例程，没有
第二个**硬编码** setter；但对象绑定审计又证明 GB202 不安装这段实现，而安装
空成功 stub。随驱动发布的 GB202 FMC/GFW bindata 可确认有生产签名、hash、
public-key 等认证材料；其中部分 blob 呈高熵，但高熵本身不能证明加密。可读的
GSP-RM ELF 也说明“现代固件全部加密”不成立。准确结论只是：当前取得的
驱动 FMC/GFW bindata 没有提供可直接审计的 task-2 consumer，其具体加密状态
不能只靠熵断言。另行解析的 VBIOS Falcon v6 `FSP_RUN` 条目则确有 raw bit 2
置位，旧共用 header 把它命名为 encrypted；这是不同封装对象的 header 观察，
不能反推所有固件载荷，也不能自行定义 v6 的加密范围或算法。

把该负搜索再细化一层后，可以精确区分 ELF 中 `f8` block 的读写方向与实际
GB202 绑定。first executable PT_LOAD 中唯一由 `LUI 0x820` 直接形成的
`base+0x8200f8` 访问位于 `0x0108c4ae`，指令是
`lw a2, 0xf8(a5)`；同一基本块的 store 只写 `+0x40` 与 `+0x13c`，不写
`+0xf8`。其余 7 个直接 `LUI 0x820` 小窗口没有第二个 `f8` 命中。OBJBSP
constructor 的确定重放进一步证明：TU102/TU116 才把该函数装到 `+0x338`；
GB202/index 65 装入 `0x019b4ea0` 的 `return 0` stub，且固定构造路径没有后续
覆盖。所以这段代码对绑定它的旧芯片只**读取/消费**既有 f8 权限，不能 lowering
或 restore；对当前固定 610 GSP 的 GB202，它根本不执行。表驱动 PRI、动态
payload 和 FSP 内部仍不在这项 literal/constructor 证明范围。

同时对 GSP 中 `base+0x318` 的间接调用候选做了低内存、有限控制流的数据流
校准。公开 610 host RM 的 generated HAL 明确把 GB202 的
`gpuGetPrimaryFuseBaseAddr` 绑定到返回 `0x820000` 的 GH100 实现，这是公开
源码 FACT；但同一公开 host 布局把该字段放在 `OBJGPU+0x460`，不是
`+0x318`，所以公开源码只提供方法语义校准，不提供 GSP ABI/字段名证明。

现在已有独立于 host ABI 的 private-GSP constructor 证据。固定 GSP ELF 的
GB202/index-65 构造路径在 `0x1b9e5da` 把 constant-return function
`0x1444500` 写入同一对象 `s11+0x318`，而该函数只返回 `0x820000`；同一路径还
把 `0x141579c` 写入 `s11+0x1a0`。后者正是形成 fuse-base `+0xc04` 的正校准
函数。四个正校准函数调用 `+0x318` 时都传递未改写的原始 `a0`，并都再次访问
各自的 `a0+0xb98` companion field；前三个入口连这段 16-byte 指令序列都逐
字节相同。于是相关 private layout 的 `+0x318` 是 primary-fuse-base getter
已经是有 constructor、receiver 与返回值用途共同支持的**强行为推断**，不再
依赖“公开 host 偏移也许一样”这一错误前提。

原扫描记录的四组返回值用途仍是 `+0x3814`、`+0xc04`、`+0x74c` 和
`+0x4e04/+0x4e08/+0x4e0c`；第四组只与 GH100-only sibling 相容，不能当作
GB202 runtime-path 证据。stripped GSP 没有给出 private type/field 正式名称，
所以仍不能把裸 `+0x318` 全局命名为 `OBJGPU` getter，也不能称为公开 ABI 或
ELF symbol 事实。
同一模型在已访问状态中没有形成 `+0x40/d0/dc/e0/f4/f8/13c`，因此对
“候选调用返回 base 后以已建模简单运算形成 `+0xf8`”这一具体形态构成有限
负证据。不过 84 个候选中有 12 个达到每候选 2500-state 上限，且近邻筛选外、
复杂表驱动、跨 helper/跨段、直接 literal、FSP/HULK 和动态 payload 均未被
覆盖；这不是 getter caller、setter 或全程序访问不存在的证明。新的 constructor
闭合也没有扩大该 `f8` 负搜索范围，更没有证明存在 setter。完整方法、正校准和
边界见 `parallel/gsp318_private_provenance.md`、
`parallel/gsp_slot318_dataflow.md`、`parallel/public_fusebase_callers.md` 与
`parallel/slot318_wording_review.md`。

针对此前未覆盖的数据段/table-flow 又做了一次限定复核。固定 GSP ELF 的两个
PT_LOAD 中没有完整 `0x8200f8` literal、已知 MODS 风格 f8 RegHal setter ID、
普通 `AUIPC + signed-lo12` 形成点或相邻 `{0x820,0xf8}` descriptor。唯一值得
追的两份 77 项 `u32` 表虽然包含裸 `0xf8`，但其内容是
`0x0..0x15c` 的 PCIe-style DWORD offsets；两条 consumer 都把每项加到三只
动态 base，loop 内没有 `0x820000` 数据依赖。即使不采用 PCIe 语义标签，
binary-only 也足以排除“这两张表直接描述 fuse-base+f8”。因此已覆盖的直接
地址、literal、普通 PC-relative、已知 RegHal ID、邻接 descriptor 和 aligned
`u32` table 形式只剩那条后来证明未绑定 GB202 的旧 NVDEC read block，没有
setter/lowering/restore。packed 表、
通用动态 PRI helper、FSP/ROM 与 HULK payload 仍不在这个负证明内；详见
`parallel/gsp_f8_tableflow.md`。

本地更新的 610.74 Windows 驱动包又提供了一份独立跨版本交叉检查。其内层
GSP-RM ELF 比 610.43.03 的 RX/RW PT_LOAD 各增长 `0x2000`，不能沿用旧绝对
地址；重新枚举后仍恰有 8 个直接 `LUI 0x820` 锚点。已知 f8 block 平移到
`0x0108c586`，核心指令仍是 `lw a2,0xf8(a5)`，store 仍只落在 `+0x40/+0x13c`；
两个 77 项 offset table 也逐项保留，且仍无完整 `0x8200f8` literal 或旧式 f8
RegHal setter ID。这不是动态/FSP 全局负证明，但说明更新版本没有在最直接的
GSP 形式中新增 f8 writer。该跨版本检查没有重放 610.74 的 OBJBSP chip binding，
所以不能把“函数仍存在”写成“GB202 会调用”；610.43.03 的固定构造重放已经对
本项目当前样本给出 GB202=stub。artifact hash、来源边界和复核窗口见
`parallel/gsp_61074_crosscheck.md`。

这里需要保留一个后续发现带来的修正：可见 GSP 确实有 HULK 证书传输通道，
它把具体寄存器动作交给签名证书和 FSP/FWSECLIC 验证，因而本来就不需要在
GSP text 中出现 `0x8200f8` 常量。另一方面，MODS floorsweep 另有
`task=2/subobject=1` 路径；现有材料没有证明 HULK `NVDM_TYPE=0x11` 与该
task-2 请求等同或在 FSP 内部相互映射。HULK 是否处理 `f8` 取决于实际证书授权
范围，task 2 是否处理 `f8` 也独立未知；当前既没有可用于本卡并授权 `f8` 的
证书，也没有直接可见的 task-2 consumer。准确结论是“没有找到无凭据的 GB20x
`f8` setter”，而不是“现代固件完全没有受控授权机制”。

### HULK 是现代签名授权／受控寄存器动作通道；是否降低 GB202 `0x8200f8` 未知

#### 当前 610 的 GB202 host transport 是 FSP，不是 SEC2

`610.43.03` 开源 RM 的 generated HAL 已把这件事分清。GB202 同时创建
`KernelFsp` 和 `KernelSec2` 对象，但“对象存在”不等于都能收 NVDM：

- GB202 的 `KernelFsp` 绑定了可工作的 packet send/read、MCTP/NVDM 解析、
  response 和 SEID 映射实现；
- GB202 的 `KernelSec2` 对 send/read、response-ready、NVDM-to-SEID、packet
  parsing/processing 等方法全部落到 not-supported/空 stub；
- `NVDM_TYPE_HULK=0x11` 在 GB202 使用的 FSP 映射中显式走 SEID 0；
  `NVDM_TYPE_PRC=0x13` 没有专用 case，落到 default SEID 0；
- 正常 GB202 GSP-RM bootstrap 选择 FSP COT 路径；SEC2 的 GSP-FMC fallback
  property 在 GB202 为 false。

直接源码证据集中在：

- `/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kern_fsp_nvoc.c`；
- `/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kernel_sec2_nvoc.c`；
- `/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c`；
- `/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c`。

完整逐行核验见 `parallel/gb202_610_arch.md`。该报告同时给出重要的负证据：
公开 GPU 源码没有 GB202 HULK payload/caller，也没有独立 floorsweep task-2
consumer 或专用 restore；唯一显式 PRC caller 是只绑定 GH100 的 protected-PCIe
查询。通用 `0x15` response 只有 task/type/error 状态，不能证明权限自动恢复。
因此当前能说的是“若私有 GB202 caller 发送 HULK/PRC，它的 host transport 是
FSP”，不能说“公开 610 已提供可调用入口”。同样不能把 HULK `0x11` 当成
task 2 的别名，或声称两条路径对 `f8` 的动作、lifetime/restore 已由源码闭合。

MODS 自带 JS 参数和主程序字符串把现代机制说得很直白：

```text
-hulk_cert <file>       Handle HULK license
-activate_hulk          Activate HULK license with token flashed to EEPROM
-hulk_disable_features  HULK contains suicide bits to disable VPR/WPR/HDCP
-ignore_hulk_errors
```

`Gpu.SetHulkCertificate(binary, length)` 的 native callback 位于
`0x1169c..0x1169d`。它只把 JS 数组逐字节复制到进程内 vector，再交给
`0xd9ad30` 保存；该 callback 本身没有 GPU、FSP、寄存器或 reset 动作。真正
处理发生在随后 GPU init 内的 HULK loader：x86 MODS 实现从 `0x7338100`
开始，GB202 GSP 对应实现从 `0x150ee04` 开始。MODS 还提供
`StopInitAfterHulk`（说明为 `Stop GPU init after processing HULK.`），进一步
把 HULK 定位成初始化序列中的明确边界，而不是普通测试中随时写一个寄存器。

对 GSP RV64 text 做流式 `AUIPC+ADDI` 交叉引用扫描后，三个 registry 字符串的
真实代码引用已经闭合：

```text
0x150f2ea -> RmActivateHulk  (VA 0x1e77698)
0x150f310 -> RMHulkCertSize  (VA 0x1e776a8)
0x150f606 -> RMHulkCert      (VA 0x1e776b8)
```

若 registry 提供证书，loader 分配 `size+4` 字节，在首 dword 写入证书长度，
再由 `0x150ef64` 通过统一 sender `0x150e918` 发送
`NVDM_TYPE_HULK = 0x11`。若 `RmActivateHulk=1` 且没有外部证书，则调用
vtable `+0x1b0`；GB202 实现 `0x1510108` 发送同一 NVDM type、总长度 4、
payload dword 为 0，请 FSP 激活 EEPROM/InfoROM 中已刷好的 token。x86 MODS
实现 `0x7339e90` 的成功日志正是
`FSP activated HULK using flashed License`，失败日志则是
`Failed to activate HULK using flashed token`。

两个 HULK sender helper 都是同步“发消息、检查返回、返回状态”，函数体内没有
reset/rebind/reload。这说明**授权消息本身并非天然要求主机重启或 GPU reset**。
但对 `0x150e918` 的全部 18 个直接调用点逐一还原参数后，只有
`0x150ef64` 和 `0x1510136` 把 NVDM type 设为 `0x11`；两者都只从上述 init
loader 可达。目前没有找到公开 RM control、普通驱动 API 或第二个直接 runtime
sender。因此不能把“消息本身无 reset”外推为“零售驱动已经有可安全调用的
运行时 HULK 接口”。

另一组 GSP 引用位于全局 registry 摄取流程 `0x1a91c1a..0x1a91cfa`：它读取
`RMHulkCertSize/RMHulkCert`，并把 `RmHulkDisableFeatures` 的 bit 0/1/2 分别
保存成三个软件布尔量，把 `RmIgnoreHulkErrors=1` 保存成第四个布尔量。这些只
配置后续 init 行为，不会当场发 HULK 消息。反向搜索也没有发现 HULK deactivate、
close 或 restore sender；可见 host 侧只有“载入证书”与“激活 flashed token”
两种进入动作。授权效果何时由 FSP 收回仍未知，不能仅凭 host 无 close 推断它
必然保持到 reset。

HULK 也不是一个可自行构造的布尔开关。GSP/MODS 的 FWSECLIC 错误表明确包含
签名无效、ECID/DEVID/strict-ID 不匹配、证书撤销、opcode 未定义，以及
register override/RMW read-back verify mismatch。随 MODS 附带的六个独立旧
Figueroa 证书大小为 304--664 字节；内容含可识别的寄存器地址/mask/data 项和
尾部签名。离线扫描确认它们均不含 `0x8200f8`、`0x8200dc`、`0x820040`、
`0x8234e0` 或其他本研究 GB202 目标地址；包内也没有 `.hulk` 文件或 GB202/5090
命名证书。这些 2015 年、板卡绑定的凭据不能在 GB202 上试用，更不能改后重签。

PRC 名称表中的相邻项也与此一致：`0x21 = HULK_ALLOW_INB`、
`0x22 = HULK`。实际 HULK loader 在发送证书前没有先由 host 写这两只 knob，
说明 allow-inband 更像制造/安全策略预授予或由 FSP 内部裁决的条件，而不是同一
次请求可先打开的自授权位。最终能否接受证书仍由 FSP/FWSECLIC、设备身份和
撤销状态决定。

对 L2 路线的含义是：若存在 NVIDIA 签发、绑定本卡且明确允许改
`0x8200f8` 的 HULK，理论上它可能建立所缺的 latch 权限窗口；当前证据不能证明
有这种证书。即使有，`NewFuse.SetSwFuses` 的 host 入口仍会先要求进程内
`SecurityUnlockLevel > 3`，HULK 不会自动绕过这个软件前置检查。绕开该
入口另写 direct-shadow writer 又会重新暴露非事务、部分写入、reset/coupling
和坏 slice 风险。因此当前不加载旧证书、不请求 flashed token、不向活跃 5090
发送 HULK/PRC 消息，也不实现凭据绕过。

#### DebugTokenQuery 能观察 HULK 状态和寿命策略，但 GB202 没有受支持的在线入口

MODS 还导出了只读语义的 `GpuSubdevice.QueryDebugToken(pTokenStatus)`，JS 说明为
`Get HULK Debug Token status`。native callback `0x11845e0` 最终调用
`0x185af40`；后者以 command `0x0f`、空请求 payload 进入通用 sender
`0x185aa90`，再由 transport vtable `+0x28` 取回响应。命令名称映射器
`0x1857f90` 把 `0x0f` 明确命名为 `DebugTokenQuery`。

这不是前述 `NVDM_TYPE_HULK=0x11`。首包构造器 `0x1857880` 在 wire buffer 前
加入 `0x7f`、32-bit enterprise number `0x00001647`、命令和版本字段；`0x7f`
是 MCTP IANA vendor-defined message type，`0x1647` 是 NVIDIA 的 IANA enterprise
number。发送器对 EMEM transport 直接报
`IANA messages are not support with EMEM transport. Use -mnoc_fsp.`，所以该查询
依赖 MNOC/MCTP 邮箱，不会走普通 HULK 证书使用的 NVDM/EMEM 通道。

对 callback 的字段访问和随包 JS 打印逻辑交叉还原后，返回对象如下。这里的偏移
是 MODS 接收缓冲区偏移，不擅自宣称为去掉所有 transport header 后的 FSP C
结构偏移：

```text
+0x0d  u8   nvCompletionCode
+0x0e  u8   tokenStatus       (JS: 1 = Installed，其余 = Not installed)
+0x0f  u64  pdi               (格式化为 0x%016llx)
+0x17  u8   fuseStatus
+0x18  u32  tokenType
+0x1c  u16  usageCounter
+0x1e  u16  config            (较新/较长响应才导出)
+0x20  u16  processStatus     (较新/较长响应才导出)
```

这也修正了早先把 `+0x0f` 误认成 `fuseStatus` 的临时笔记：该 qword 的 JS 属性名
实际是复用字符串 `pdi`，真正的 `fuseStatus` 是后面的 byte。`config` 六个已知
位由 `static/decoded/all/prntutil.js` 直接解释为：

```text
bit 0  Token Lifespan : 1 temporal（脚本拼成 temperal），0 persistent
bit 1  Token Activate : 1 manual，0 auto
bit 2  Token Revoke   : 1 auto，0 manual
bit 3  Token Devid    : 1 enabled，0 disabled
bit 4  Token Replay   : 1 enabled，0 disabled
bit 5  Token Reset    : 1 mandated，0 not mandated
```

`processStatus` 则依次映射为 `not processed`、`processed`、
`verification failure`、`runtime error`，更大值显示为 `unknown`。因此 HULK/debug
token 的寿命、激活、撤销和 reset 要求由签名 token 自身策略决定；不能再假设
所有授权都“固定保持到 reset”，也不能反向假设调用返回后固件必然立刻收权。

协议名称表还包含 command `0x0c = DebugTokenErase`，但它目前不是一个可调用的
恢复路径。对整个 MODS `.text` 流式扫描所有 x86 `call rel32` 后，通用 IANA
sender `0x185aa90` 只有两处真实调用：`0x185af6a` 是上述 `0x0f` 查询，
`0x185afe3` 是携带单字节 payload 的另一个 `0x09` 命令。没有 `0x0c` 调用者、
没有 JS `EraseDebugToken` 方法，也没有 HULK deactivate/close sender。换言之，
固件协议可能定义“erase”，但本包没有提供受支持的 host 撤销按钮；自行拼包既是
状态修改，又可能触发 token 的防重放、计数或 reset 策略，本研究不实现、更不发
送它。

生产驱动进一步封死了把只读 query 当作当前 5090 安全探针的想法。本机
`610.43.03` 开源 RM 的 generated HAL 只给
`GB100/GB102/GB110/GB112/GR100/GR102` 绑定
`kbifCacheMnocSupport_GB100` 和 `gpuMnocMbox* _GB100`；`GB202` 落到空的
`kbifCacheMnocSupport_d44104`，其 send/recv/sync-recv stub 明确返回
`NV_ERR_NOT_SUPPORTED`，availability 返回 false，最大消息尺寸返回 0。虽然
registry 存在 `RmFspUseMnoc`，强制它也不会凭空给 GB202 增加这些 HAL。MODS 的
私有 bare-metal `-mnoc_fsp` 能否在某种实验室板卡配置上绕到硬件，不能由零售
驱动推出；在当前活动桌面 5090 上运行未知 MODS 去验证它不属于“只读无风险”。

这一限制只针对 IANA debug-token query，不否定已经确认的 HULK init sender：
HULK 证书/flash-token 仍使用独立的 `NVDM_TYPE_HULK=0x11`，可经普通 FSP
NVDM/EMEM transport 到达。两者共享的是 FSP 对授权状态的最终裁决，不是同一个
host API。

### “SW fusing 只能关闭”字符串不属于 Blackwell 写入器

主程序确有 `SW Fusing cannot be enabled it can only be disabled` 和
`SW fusing can only be disabled.` 两条字符串。反查后，前者属于旧 GM/GV
`Fuse.EnableSwFusing` 的拒绝 callback，后者是旧基类的默认虚函数；包含这些
地址的 vtable 是 GM10x/GM20x/GP10x/GV100 类。Blackwell 使用的 `NewFuse`
vtable 没有指向该拒绝桩，其 `SetSwFuses` 入口是独立实现。因此这两句不能用来
证明 GB202 raw shadow 值只能从 0 变 1。真正限制仍是认证、PLM、
`disable_sw_override`、写入时机和物理单元健康。

### 写入后会自动进入 RM 状态重载，但 reset 类型由 coupling 状态选择

此前“`SetSwFuses` 写完只刷新缓存、不会自动重载拓扑”的判断不正确。实际
`NewFuse` vtable 表明，`ProgramSwFusePlan` 成功后会沿下面的完整链路进入一次
设备级 RM unload/reload：

```text
NewFuse::SetSwFusesCore             0x14620d0
  -> NewFuse vtable +0x370          0x1456870
  -> MultiMacro post-program        0x146dd30
  -> GB20xFuseAccessor +0x90        0x1515770
  -> DeviceFuseAccessHandler +0x100 0x151ad50
  -> GB202GpuSubdevice +0x1b0       0x127b000
  -> GpuSubdeviceResetOrReinit      0xdff7b0
  -> RmStateCallbackDispatcher      0xdfe3d0
```

`0x127b000` 中的第一次 reset 才是普通成功路径。只有第一次 reset 已成功且
recovery-mode 属性 `0x42384201` 为真时，它才会再发起第二次 reset；对应日志为
`GPU is in Recovery Mode! Issuing another reset to recover from it.`。所以这里的
第二次 reset 是恢复模式兜底，并不是正常 shadow 提交所必需的“两阶段提交”。
第二次调用会重新进入同一个 mapper，再按 boot、fuse、base 顺序采样三个位；
如果第一次 reset 改变了 coupling，第二次理论上可能选择不同类型。
`IsIstMode` 和 recovery property 只决定是否追加这次调用，不参与第一次的
base/fuse/boot/hot 优先级。

但“这条路径固定执行类型 5 / boot reset”是进一步反汇编后需要撤回的结论。
`0x1515770` 的确先把 `esi=5`，然而 `0x151ad50 -> 0x127b000 -> 0xdff7b0`
这几层没有使用这个传入值；`0xdff7b0` 自己创建内部请求值 2，再调用 GB202
vtable `+0x1070` 的映射器 `0x126b360`。映射器读取三个 domain `0x31` 的
reset-coupling 布尔域，并按以下优先级选择真正的 RM state：

```text
base coupling  (RegHal 0x42d64001) = 1 -> state 7, base reset
否则 fuse coupling (RegHal 0x42d6c001) = 1 -> state 6, fuse reset
否则 boot coupling (RegHal 0x42d68001) = 1 -> state 5, boot reset
否则                                      -> state 3, hot reset
```

状态名称由 `RmStateToString` `0x1845f20` 直接确认：3、5、6、7 分别是
`hot`、`boot`、`fuse`、`base`。因此正常 post-program 一定会进入重型 RM
状态转换，但究竟是哪一种 reset，取决于调用当时已经生效的 coupling 位；在
没有安全本卡读数之前不能写死为 boot。

mapper 并不是按优先级短路读取：它会先把 boot、fuse、base 三项全部采样，再
执行 base > fuse > boot > hot 判断。采样使用的 RegHal helper 在 unsupported
lookup 分支只返回 0，mapper 没有独立的“读取失败”状态；不过当前 GB202 表确实
包含这三个 field ID，所以 unsupported 不是首选解释。对象 getter 还允许从
`GpuSubdevice+0x6c0` 取得一个可选 RegHal backend override，空时才用嵌入对象
`+0x90`。该 override 的生命周期现已闭合：构造时为 null，只有成功枚举并选择
MIG/SMC partition 与 GR engine 后才安装 RTTI 名为 `SmcRegHal` 的对象，重选时
替换并析构旧对象，`GpuSubdevice` 析构时再释放。`SmcRegHal` 也不是通用固件
backend；它只把 resolved `0x400000..0x5fffff` 的 SMC-local GR 访问改走带
GR route 的 `EXEC_REG_OPS`，其余回退普通 RegHal。coupling 三项是 PMC-relative
`+0x40/+0x44/+0x48`，静态证据强支持它们在普通未分区 GB202 上使用嵌入的普通
RegHal，即使存在 SMC override 也仍回退普通路径；只有 domain `0x31` 的当次
runtime translation 数值未执行验证。因此 backend 身份已不再是主要未知，
剩下的是本卡当前三个位、固件/上电来源和更低层寄存器语义。完整证据见
`parallel/reghal_override_lifecycle.md`。

另需排除一个看似相近、实际 owner 不同的官方对象。R580.126.09 release note
确实记录 FSP 会依据某个 PLM 条件 reset，并通过 source isolation 禁止 FSP
访问一个未指明的 RESET PLM；但公开 GB202 路径中的
`NV_PGSP_FALCON_RESET_PRIV_LEVEL_MASK = 0x1103c4` 管的是 GSP Falcon
reset-control。它是绝对 PRI 地址，和本项目的 device-relative coupling targets
`+0x40/+0x44/+0x48`、对应 PLM words `+0x308/+0x30c/+0x310` 在 owner、地址
形式与用途上均不同。两个 580 tag 的相关明文文件 byte-identical；firmware
bindata 虽更新，却无法归因到该单项修复。所以它只能证明“FSP reset 逻辑可能受
PLM 可见性影响”这一通用机制，不能填补 coupling 的具体权限或级联缺口。详见
`parallel/official_fsp_plm_scope.md`。

这里还必须区分“设置 coupling”和“真正 reset”。相关虚函数为：

```text
DeviceFuseAccess +0xf8  0x151ad40 -> GpuSubdevice +0x3a0
DeviceFuseAccess +0x100 0x151ad50 -> GpuSubdevice +0x1b0
GpuSubdevice +0x3a0      0x126d4e0 -> 设置/校验 reset coupling（host/FSP 双路径）
GpuSubdevice +0x1b0      0x127b000 -> 选择状态并执行 reset/reinitialize
```

配套的 GpuSubdevice `+0x368 = 0x1249960` 模式 0 原始日志明确写着
`Setting up coupling for boot reset without issuing it!`，而其实际调用目标正是
`+0x3a0`；所以 `+0x3a0` 本身并不发起 reset，只设置并回读校验 coupling。
PLM 允许时它直接通过 RegHal 写，PLM 不允许时才回退到 FSP task 4。随后
dispatcher 才输出
`Performing a %s reset on %s`，保存配置、卸载设备状态、等待 GFW boot、恢复
配置并重建 RM 状态。这不是运行时热加一片 L2 的轻量接口。

显式 `GB20xPrepareResense` 走 accessor `+0x88`（`0x1516f30`）：先尝试通过
`+0xf8` 请求 state-6/fuse-reset coupling；失败只记日志，仍继续发出
`0x404f0000` clear-coded 请求，而这次 clear 调用的返回也被忽略。仅在 preparation
返回零且平台 predicate 判定为非 pre-silicon 时，caller 才进入 `+0x100`
reset/reinitialize；pre-silicon 分支明确记录 `Skipping fuse reset ...` 并跳过
reset。RegHal 配对与函数角色强烈支持把这解释为“尝试停止 software override
并从实体熔丝 resense”，但 coupling 是否建立、latch 是否真清零、reset 是否
执行完成均为 `UNKNOWN`，也不能把最终可能选到的 type 6 归因于本次 coupling
请求。普通 `SetSwFuses` post-program 则只走 `+0x100`，没有在这条局部链路里
先设置 coupling，也没有清 latch；所以它最终选择哪种 reset，成为新的关键时序
前提。映射器的 request 2 跳表项已经逐指令核对：无论最后选出
base/fuse/boot/hot 哪一种，写入 descriptor byte 8 的“需要补设 coupling”标志
都固定为 0。因此后面的 dispatcher 也不会偷偷替普通 post-program 补一个 boot
coupling。

对 dispatcher 的直接调用点再做穷举，整个 `.text` 只有 `0xdff7a1`、
`0xdff82c`、`0xdff903` 三处；第三处只是 `+0x1a8` 默认虚函数的内联包装，仍把
descriptor byte 8 初始化为 0，并没有第四种隐藏构造器。`0xdff7b0` 随后让
`+0x1070` 映射器处理 request 2；跳表项会读取现有三个 coupling 位，选择当前
实际的 state，并明确写回 byte 8 = 0。这进一步确认 direct-shadow 的含义是
“沿用已有 coupling 后 reset”，不是“为这次 shadow 提交建立一个 coupling”。

对“设置 coupling”本身继续展开后，协议也已闭合。GB202 的
`GpuSubdevice+0x1100 = 0x126db90` 只接受 state 5/6/7，并调用
`0x185e890(task=4, subobject=1)`；payload 是一个字节，boot/fuse/base 分别为
`1/0/2`。不过 `+0x3a0 = 0x126d4e0` 并非无条件发 task 4。它先读取当前
fuse/boot/base coupling，再用 `0x198a7e0` 检查三个字段各自的直接写权限。
该 helper 不是简单的“RegHal 条目存在”测试，而是读取 PLM word 后精确计算：

```text
direct_write_allowed = bit0 & bit4
                     & (!bit10 | bit12)
                     & (!bit11 | bit12)
```

这里的 bit4 已能按 NVIDIA 公开 PLM layout 正式命名为
`WRITE_PROTECTION_LEVEL0_ENABLE`：它表示 L0 requester 可写，**不是** MODS
host 的 network `SecurityUnlockLevel=4`。bit0 是 L0 read enable，bits 10/11
是 source read/write control，bit12 是 source-enable vector 的最低位；公开头
没有发布该最低位对应的具体 requester 名。固定 610 GSP 的三个私有 setter
各自只检查配对 PLM 的 bit4；gate 关闭或 target 写后 bit0 仍未置位都会形成
`0x40 = NV_ERR_INVALID_STATE`，且 gate 失败路径带 assert/条件 `ebreak`，不能
当作无害的权限探针。完整证据见 `parallel/coupling_gate_semantics.md`。

GB202 RegHal 表把三组字段放在同一个 domain word `0x31` 中，并给出如下成对
记录；这里保留 RegHal 内的字段/PLM offset，不把它们擅自推成 BAR0 绝对地址：

```text
target  value IDs                 field offset  PLM metadata offset
fuse    0x42d6c000 / 0x42d6c001      0x40             0x308
boot    0x42d68000 / 0x42d68001      0x44             0x30c
base    0x42d64000 / 0x42d64001      0x48             0x310
```

具体分支也能逐条确定：请求 boot 时，现有 fuse/base 必须都为 0；三组 PLM
都允许才由 host 直接写成 boot=1、fuse=0、base=0，否则在**写入前**选择 FSP
task 4。请求 fuse 时，现有 base 必须为 0；fuse 与 base 两组 PLM 都允许便
direct 写 fuse=1、base=0，否则预选 FSP。请求 base 时只需 base PLM 可写便
direct 置 1，否则预选 FSP。这个分流不是失败重试：direct 写后验证失败不会再
转 FSP，FSP 失败也不会回头 direct；固定 GSP setter 自身则根本没有 FSP sender。
每条成功路径最后都回读验证，并在失败日志中明确区分修改来源 `MODS` 或
`FSP`。hot 则更严格：已有任一 coupling 时直接拒绝并报告
`Resets already coupled, can't trigger hot reset`；它不是可用的“清空 coupling”
快捷方式。普通 post-program 的 request 2 本来就不会触发这些转换分支。

本组 setter 没有已知的“全部清零”state：boot/fuse/base 只建立并验证对应组合，
hot 则要求三者原本就全为 0，不会代替调用者清除已有 coupling。

task 4 也不是另一套独立 capability：sender 的 `0x185e500` 分支先用输入 4
调用同一个 `0x185e0e0`，而 `0x1857b10` 的 `0x4713e` 位图包含 bit 4，故仍映射
到 QCAP `0x13`；失败文案是
`Reset coupling isn't supported by FSP or is not yet active`。也就是说
floorsweep task 2、reset-coupling use case 4、PRC read/write 共享“FSP 支持 PRC”
这一能力门，但固件仍可对具体 subobject/knob 分别裁决。

全程序对 `GpuSubdevice+0x1100` 和 coupling RegHal 常量的 host 调用点枚举也没有
找到 `Gpu::Initialize` 中的无条件预设：可确认的 GB202 task-4 调用都收敛在
`+0x3a0` 的显式设置/校验器；direct-shadow dispatcher 的 descriptor byte 8
又固定为 0，不会补调它。因此 host 控制流没有“SetSwFuses 前必定设置 boot
coupling”的保证。FSP/GFW 在最初上电或别的固件状态机中是否自行留下某个
coupling 仍是独立未知，不能由 host xref 反向排除。

物理 FSP fuseblow 流程确实有独立的 coupling 准备器，但 direct shadow 不走它。
GB202 GpuSubdevice 的相邻槽为：

```text
+0x360 0x1248970  查询 fuse-reset 是否已经设置
+0x368 0x1249960  FSP fuseblow 三模式协调器
+0x370 0x1247260  返回 FSP 对象
```

`+0x368` 模式 0 先按 state 5 准备 boot coupling 而不 reset；模式 1 日志为
`Triggering Fsp Fuseblow`；模式 2 日志为
`Performing a Fuse Resense after Fsp Fuseblow`。`0xda1960` 的物理熔丝状态机调用
了这些模式。完整 `NewFuse::SetSwFuses -> ProgramSwFusePlan -> post-program`
链中则没有 `+0x368` 调用，不能把物理 fuseblow 已经准备好的 boot coupling
前提移植到 direct-shadow 路径。

继续回查 `Gpu::Initialize` 后还找到了对 `0xda1960` 的两处直接调用（事件/模式
0 和 4），但它们并不是普通启动的无条件准备步骤。前一处先检查 Gpu 对象
`+0x210` 的 fusing-mode 用例树；树为空便直接跳过协调器。JS 端只有显式
`-fusing_mode` 才填充 `g_FusingModeUseCases` 并调用
`Gpu.SetFusingModeUseCases`，对应 native callback `0x116b670` 最终通过
`0xd9aee0` 拷入的正是对象 `+0x1f0..+0x210` 这棵树。普通未指定
`-fusing_mode` 的启动保持 `+0x210 == 0`，因而不会借物理 fuseblow 状态机预设
boot coupling。`-fusing_mode` 属于实体熔丝操作的用例选择，不是 direct-shadow
的安全初始化开关，不能为此拿来实机尝试。

当前 MODS x86-64 ELF 的 direct-literal constant scan 共找到 11 个
`0x404f0000` 使用点，已见位置不包括正常 `GB20xPostSwProgram90` 或已审计的
direct-shadow success/failure tail。GB20x accessor vtable 也把 resense
`0x1516f30` 放在 `+0x88`，把正常 post-program `0x1515770` 放在相邻但不同的
`+0x90`。因此只能说这些 host 路径不主动发出已知 clear constant；该负结果不
排除间接/动态 RegHal 构造、其他版本或模块、GSP/FSP/GFW，或者 reset 硬件状态机
改变 latch。

此前关于 EarlyInitCallback 递归的判断也需要撤回。`GpuSubdeviceEarlyInitPhase`
是 GpuSubdevice vtable `+0x3b8` 的 `0xe03f20`；完整 dispatcher `0xdfe3d0`
没有调用这个槽位。全 ELF 中已确认的完整初始化调用在初次 subdevice 创建路径
`0xdb0cc8`，而不是上述 post-program dispatcher。映射器生成的 descriptor
byte 8 表示“是否需要设置 coupling”，不是“是否再次运行 EarlyInitCallback”。
因此目前没有 host 静态证据证明 post-program 会自动递归该 callback。

这不等于可以把 `SetSwFuses` 放进 EarlyInitCallback：它仍会在初始化中途发起
一次设备级 unload/reset/reload，属于高风险重入状态转换。当前只把自动 RM
重载视为“原厂流程可能采用新 shadow 拓扑”的积极证据；reset coupling 的既有
状态、GSP 对 shadow 的接受、物理切片健康和失败恢复仍未闭合，因而不生成、更不
运行写入脚本。

### shadow 跨 reset 生效是强设计推断，不是已证明的保持规则

对 success tail 再做一次生命周期审计后，可以把“重载”与“验收”明确分开。
`ProgramSwFusePlan` 只在 reset **之前**尝试置 latch、逐项写 raw shadow 并立即
回读；post-program callback 不再携带 plan 的 offset/value。reset/reinit 返回后，
`SetSwFusesCore` 只检查 callback status、释放临时 plan 并返回。已检查链路没有：

- 重放 `0x8234e0 + 4*FBP` raw plan；
- 读取或比较 `0x822900 + 4*FBP` current/effective mask；
- 比较 `0x820d70 + 4*FBP` status；
- 调用 LTS-mask GET 或核对最终 L2 容量/count。

所以原厂控制流**强烈预期** latch/raw shadow 能跨所选 reset 保留，或被 reset
状态机消费后重新形成 effective 拓扑；否则正常 success path 没有可见机制让计划
生效。但这只能证明软件设计意图，不能证明 hot/boot/fuse/base 四类 reset 对
`0x820040`、raw shadow 和 effective 寄存器的硅级保持域。

四类 reset 里，当前只有 fuse reset 与 physical-resense 有直接语义联系：显式
resense 会先尝试 state-6 coupling 和 latch clear，物理 fuseblow 协调器也把相应
阶段称为 `Fuse Resense`；另一路径日志称新烧写值可能需要 `fuse / cold reset`
才反映。hot、boot、base 是否也重采实体 fuse仍为未知，尤其不能把独立枚举的
`base reset` 直接等同于 `cold reset`。正常 writer 即便因既有 coupling 选到
state 6，也没有先 clear latch，不能把它等同于显式 resense。

公开 610 的 BIF reset control 进一步证明这些名称是分开的：其 wire enum 明列
`SBR=2`、`BOOT_DEVICE_FUSE=4`、`BOOT_DEVICE=5`、`BASE=8`，并明确说
Blackwell 起不支持 `FUNDAMENTAL=3`，应改用 boot-device-fuse 或 boot-device。
这里的 BIF wire number 与 MODS 的 RM state 3/5/6/7 不是同一套数字，不能按数值
互换；但独立 taxonomy 足以反证“base 就是 fundamental/cold”的简化解释。

OpenRM 的 GB202 secondary-bus-reset HAL 也已静态闭合为
GB202 -> GH100 -> GM107 body。最终函数只打开上游桥、置/清 Bridge Control
`0x40`、等待并轮询 GPU config access；没有 BAR0/fuse-aperture 访问、latch clear、
raw save/replay、fuse resense 或 L2 topology compare。GB202 的另一组公开源码
说明 chip reset 会触发 FSP 执行并等待 secure boot，但当前没有证明每次
hot/SBR/boot/fuse/base 都走完全相同阶段，也没有证明 FSP 会 retain、clear、
sample 或重建上述四组值。完整证据矩阵见 `parallel/shadow_reset_domains.md`。

版本边界也已用 NVIDIA 官方 upstream 交叉检查：截至 2026-07-21，官方
`open-gpu-kernel-modules` 仓库公开的最新 610 Linux 源码快照仍是 610.43.02；
其 BIF reset taxonomy 与本地 610.43.03 一致，没有新增四组 L2 状态的
reset-domain 合同。本地 610.74 Windows/GSP artifact 仍只属于另一种二进制
交叉样本，不能替代缺失的公开 FSP/hardware consumer。见
`parallel/upstream_610_reset_crosscheck.md`。

这也进一步降低了 `SetSwFuses` 返回成功的证明力：latch-set 返回未检查、raw
write 返回未消费，`0xbadf510c` privilege sentinel 只记日志；最终 status 既不是
每个 raw 项的严格 pre-reset 验收，更不是 post-reset effective adoption 证明。
完整分层证据见 `parallel/shadow_reset_lifecycle.md` 与
`parallel/effective_mask_boot_lifecycle.md`。

### 标准 direct-shadow 路径没有公开的 no-reset 变体

`SetSwFusesCore` 的两条实际编程分支分别在 `0x146223c` 和 `0x14623f9` 调用
vtable `+0x370`；两处都只在编程错误时跳过，成功时没有读取命令行、JS 属性或
reset-policy 参数。`0x1456870 -> 0x146dd30` 随后逐个 macro 无条件调用
accessor `+0x90`，GB20x 的该槽就是上面的 `0x1515770`。所以从公开
`SetSwFuses` 入口不能自然得到“只提交、不 reset”。

写入成功与 `+0x370` 之间另有 `NewFuse+0xd0 = 0x14567b0`，但它也不是隐藏的
coupling 准备器：其两个目标 `0x146db30`、`0x1473b70` 只复位/释放解析计划的
红黑树、vector 和记录容器，没有 `GpuSubdevice`、RegHal 或 FSP 调用。故这一步
不能补上普通 direct-shadow 路径缺失的 task 4。

JS 全局确实注册了 `NoReset` 常量，但它与 `ResetDevice/HotReset/BootReset/...`
并列，属于通用设备 reset 枚举；`SetSwFuses` 的包装器只接受唯一一个
`fuseNameValPairs` 数组，没有第二个 reset mode 参数。二进制中的
`-skip_reset_post_fusing` 及日志
`Skipping the reset after fusing. New fuse values may not be reflected until a fuse / cold reset`
也只被物理 FSP fuseblow 状态机 `0xda1960` 引用，不进入 software-shadow
`SetSwFuses` 链。它们都不能抑制这里的 post-program reset/reinit。

### 公开 reset-coupled control 实际只直接汇总 fuse/boot；GB202 槽绑定现为 V-STATIC

610.43.03 公开头文件定义了只读控制
`NV2080_CTRL_CMD_GPU_IS_RESET_COUPLED = 0x208081f3`，输出只有一个
`NvBool isResetCoupled`。此前把本机 CPU-RM 模块 NVOC 导出表中的空 `pFunc`
误判成“实现被编译禁用”；完整检查公开控制分发代码后，这一判断已经修正。

该条目的 `flags=0x48` 实际是：

```text
0x40 RMCTRL_FLAGS_ROUTE_TO_PHYSICAL
0x08 RMCTRL_FLAGS_NON_PRIVILEGED
```

`NVOC_EXPORTED_METHOD_DISABLED_BY_FLAG` 正是让这种 route-to-physical 控制在
CPU-RM 一侧不链接本地函数。`rmresControl_Prologue_IMPL` 会经
`NV_RM_RPC_CONTROL` 把命令和参数发给 GSP/physical RM；RPC 成功时返回内部
`NV_WARN_NOTHING_TO_DO`，Resserv 因而跳过空 `pFunc`，再由 serialization
epilogue 把 GSP 回包复制回调用者。因此空函数指针是转发设计，不是成功的空操作。

此前未归档的只读探针报告称：在显示仍由 RTX 5090 驱动时，用普通
RM client/device/subdevice handle 发出一次该控制，并把输出预填为非布尔哨兵
`0xa5`；报告结果为：

```text
ioctl_rc=0  rm_status=NV_OK  is_reset_coupled=0
```

同一报告称哨兵被覆盖，且查询后显示、温度和功耗正常；但项目没有保存 stdout
或健康快照，所以这些运行观察均为 `REPORT-ONLY`，不能称为当前值或独立复核
事实。可独立复核的静态结论是：该 control 为 route-to-physical GET，以及下述
固定 inner GSP 中 GB202 的具体 getter 绑定；这不会把未留档的历史输出变成当前值。

GSP 中该 control 的实现位于 `0x142c510`。它经
`Subdevice+0x158 -> GpuResource+0xe0` 精确取得 `OBJGPU *`，调用
`OBJGPU+0x668` 的 HAL 槽，将返回字节写入输出并返回 `NV_OK`。两个对象偏移与
610.43.03 公开结构的 `offsetof` 完全吻合。

以 GSP 中唯一的 `OBJGPU` class ID `0x7ef3cb` 为锚点，可定位其 class def、
`0x5650` 字节对象大小、object-create wrapper `0x195a688`，继而落到真正的
OBJGPU 初始化器 `0x1b9c210`。该初始化器对 `+0x668` 只有两种赋值：

```text
默认：0x19508c4  -> 直接 return NV_FALSE
覆盖：0x144d4e8  -> 查询 device-info 项并读取两个状态 bit
```

GSP 自身的 ChipHal 映射器 `0x1ae6538` 把
`arch=0x1b, impl=2`（GB202）映成 HalVarIdx `65`。新的有界构造重放揭示最终
选择有两张 bitmap，而不是只有旧分析识别出的第一张：

```text
group 1: 0x98000000  -> low bits 27, 28, 31
group 2: 0x0000303f  -> low bits 0..5, 12, 13
```

GB202 位于 group 2 / low 1，所以 `(0x303f >> 1) & 1 = 1`，路径在
`0x1b9d7ca` 写入 `s11+0x668 = 0x144d4e8`，随后直接跳到默认 store
`0x1b9c8a4` 的下一条指令，明确不会被 `0x19508c4` 覆盖。正、负控制 index 的
重放结果也与这张 bitmap 一致。脚本、输出和第二套独立原始字节复核分别保存于
`parallel/gsp_objgpu_668_replay.py`、
`parallel/gsp_objgpu_668_replay.results.txt` 和
`parallel/objgpu_668_independent_check.md`；完整影响分析见
`parallel/reset_coupled_binding_replay.md`。该**具体绑定**现为 `V-STATIC`。

`0x144d4e8` 不是恒假桩。它的正常物理路径精确为：用
`gpuGetOneDeviceEntry`-like helper 查询 type `0x2a` 的唯一 device-info entry，
从 entry `+0x10` 取 `devicePriBase`，再经对象 `+0xb98` 的 PRI aperture pointer
读取 `devicePriBase+0x40.bit0` 与 `+0x44.bit0`，做短路 OR。另一条固定 GSP
路径用同一个对象 byte 在 VGPU static-info cache 与物理 control 之间分支，并与
公开 `kbusSendBusInfo_IMPL` 及 command `0x20801823` 逐项吻合，故 getter 入口的
`+0xb68` guard 可校准为 `isVirtual`；它不是 PLM、network security level 或
fuse lock。

相邻 GSP setter 又用完全相同的 device-info tuple 和 aperture，按 reset selector
形成以下三元组：

```text
type 4: PLM +0x308 -> set +0x40.bit0
type 5: PLM +0x30c -> set +0x44.bit0
type 8: PLM +0x310 -> set +0x48.bit0
```

公开 610 BIF 名称把 type 4/5/8 分别定义为 `BOOT_DEVICE_FUSE`、
`BOOT_DEVICE`、`BASE`；该数值关系又与 MODS RegHal 的 fuse/boot/base 三元组
完全相同。因此 `+0x40/+0x44/+0x48` 的名称现为 `V-STATIC`，而固定 getter 的
直接返回语义是 **fuse OR boot**，没有第三次 `+0x48` load。完整证据见
`parallel/reset_getter_guard_provenance.md` 与
`parallel/reset_getter_internal_fields.md`。

这意味着该 control 并非 mapper 三个输入的完整快照。项目叙述的历史 0 若准确，
也至多说明当时 getter 没有返回 fuse/boot；它不能直接排除 base-only 状态，且
stdout、同时间健康快照与 lookup 结果均未留档，所以仍只是 `REPORT-ONLY`，不是
当前值。进一步的 bounded xref/dispatcher 审计已经排除可见 GSP 软件镜像：
selector 8 只置位并读回 base `+0x48`，type-8 reset arm 也不会再串行调用
selector 4/5。剩下的 `UNKNOWN` 已缩到寄存器硬件副作用、reset sequencer 或
FSP/GFW 是否隐式级联；在闭合该关系前，一个 false 仍不能证明三项都为零。

公开 host 侧可见用途也与“不能当三位快照”相容：
`_gpuRefreshRecoveryActionInLock` 仅在 self-hosted GPU 已需要 bus reset 时发这个
control；返回 true 就把 recovery action 从 bus reset 升为 system reboot。
这能证明接口服务于恢复策略，却没有公开解释为何 fixed getter 忽略 base，故
设计理由仍保留为 `UNKNOWN`。对公开 610 control headers/generated methods 的
定向清单也没有找到逐 fuse/boot/base 的只读 GET；`GPU_GET_RESET_STATUS` 只返回
设备是否被标记为需要 reset，不能补上 base 位。

因此普通 `SetSwFuses` 尾声究竟选择 state 3 `hot reset`，还是因某个既有/先行
设置的 coupling 选择 boot/fuse/base，现阶段仍是**未知**。未留档的历史 0 不能
排除当前 coupling，也不能据此设计 reset 时序。此外该公开 ABI 只有一个
`isResetCoupled`；当前固定实现只直接覆盖 fuse/boot，既不能区分这两者，也不
直接覆盖 base，因而更无法据此重建 mapper 的三个优先级输入。完整选择输入、
setter 和 query 边界见
`parallel/reset_selection_inputs.md`。

### FSP floorsweep one-shot 的 host 可见时序已闭合，值与消费语义未闭合

MODS 的通用 PRC 命令行参数为：

```text
-fsp_prc_write <knobName> <knobValue>
-fsp_prc_read  <knobName>
```

原生 PRC 名称表中 `PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT`
的精确 ID 是 **`0x1d`**。此前把它写成 `0x1c`，原因是把前一条 0x28-byte
记录末尾的 ID store 错配给了下一条刚开始构造的名字。现在按完整记录重建：
每项是 `{std::string name[0x20]; uint32 id @ +0x20; pad}`，插树循环
`0x1860a75..0x1860aab` 每次前进 `0x28`，从 record `+0x20` 复制 ID。对应边界
为 `0x1b=RRL_ALLOW_INB`、`0x1c=RPR_ALLOW_INB`、
`0x1d=FLOORSWEEPING_ALLOW_INB_ONE_SHOT`、`0x1e=HBM_FREQ_CHANGE_ALLOW_INB`；
floorsweeping 名称位于 stack record `rsp+0x4b8`，其 ID store 是
`0x1860458 -> [rsp+0x4d8]=0x1d`。JS 只负责把名称/整数值复制进 `Gpu` 管理器；
真正执行器 `0x185ef60` 先读当前值，只在不同时发送 FSP
task 13/submessage 2，然后读回校验，不匹配返回 `0x12f`。这条 host
路径没有 `ProgramSwFusePlan` 的进程内 `SecurityUnlockLevel > 3` 前置检查；是否允许修改由 FSP
响应和固件策略最终裁决。完整表项只有 name+ID，没有 type、default、range、
writable 或 one-shot flag；writer 也只按名称是否含 `ALLOW_INB` 分组，不按 ID
做值域校验。因此值 `1` 仍不能从 host table 推出。进一步的值语义审计还排除了
两个容易混淆的“默认值”来源：JS write array 默认为空只表示 host 不发写请求；
writer 日志里的 `default PrcKnob Value` 实际是 task-12 刚读回的 current value，
不是 schema 或 power-on default。artifact 自身还有
`INVALID_PRC_KNOB_VALUE`、`PRC_ERROR_INVALID_KNOB_VAL` 与 floorsweep invalid
options 等错误词汇，说明 FSP 侧可能存在 host 看不见的 per-knob validator。
所以当前只能证明 wire value 为 `u16`；合法值、默认值、Boolean 类型以及
`1=grant` 全部仍是 UNKNOWN。完整证据见 `parallel/prc_knob_metadata.md` 与
`parallel/prc_1d_value_semantics.md`。

同一构造器继续向后还恢复出一组与上述新时序直接相关的 PRC ID：

```text
0x1f PRC_KNOB_ID_ROW_REMAP_ALLOW_INB
0x20 PRC_KNOB_ID_ROW_REMAP
0x21 PRC_KNOB_ID_HULK_ALLOW_INB
0x22 PRC_KNOB_ID_HULK
0x23 PRC_KNOB_ID_FORCE_RESET_COUPLING_ALLOW_INB
0x24 PRC_KNOB_ID_FORCE_RESET_COUPLING
```

这说明 FSP 明确把“允许带内强制 reset coupling”和“实际 coupling 请求”分成
两个 knob。通用 `-fsp_prc_write` host 执行器对 `0x23/0x24` 没有单独的 MODS
security-level 检查或值域验证，仍是把 16-bit 值交给 FSP、读回并比较；是否
接受、是否一次性以及允许哪些值完全由 FSP 裁决。

这里还有一个重要的执行顺序限制。`Gpu.SetFspPrcWriteInfo` 的 native callback
`0x116bd50` 从 JS 数组逐项读取字符串属性 `knobId` 和整数属性 `knobValue`，
再以**完整 knob 名称**为键装入 `std::map`；所以数组/命令行原始顺序会丢失，
重复名称则由后值覆盖。执行器 `0x185ef60` 按名称字典序遍历该 map，但在构造
最终链表时把不含 `ALLOW_INB` 的普通项插到表头，把含 `ALLOW_INB` 的项插到
表尾，随后从表头逐项执行“读旧值 -> 必要时写 -> 读回”。因此同时提交
`PRC_KNOB_ID_FORCE_RESET_COUPLING` 和
`PRC_KNOB_ID_FORCE_RESET_COUPLING_ALLOW_INB` 时，确定的 host 顺序是先处理
实际 coupling knob，后处理 allow knob，而不是“先授权、再动作”。这可能是在
已有许可下先动作、最后收口的设计，也可能说明两个 knob 并非简单的即时前置
依赖；仅凭名字无法区分。在找到 FSP 消费语义前，不能把 `0x23=1`、随后
`0x24=?` 当作可用时序，更不能因为命令行书写顺序正确就认为它会被保留。

同一 MODS 内部的 IST 流程进一步收窄了语义。`WriteIstPrcKnob()`
`0x1ebc7f0` 在进入 IST 前构造的 map 只有
`PRC_KNOB_ID_IST=1`，结束后只有 `PRC_KNOB_ID_IST=0`，然后同样调用
`0x185ef60`；它从不在运行时配套写 `PRC_KNOB_ID_IST_ALLOW_INB`。JS 参数说明也
明确称这是“进入 IST 前 enable，结束后 disable”。这强烈支持
`*_ALLOW_INB` 是由制造/安全策略预先授予的带内修改许可，而相邻的普通 knob 才
是获准后可反复切换的动作值；执行器把 allow 项排到动作之后，也会阻止同一批
请求简单实现“先开许可、立即动作”。套到 reset coupling 上，真正需要先确认的
是零售 GB202 上 `0x23` 的**既有只读值**以及 FSP 是否允许读，而不是假定可以先
写 `0x23=1`。静态文件不能给出每张卡的当前 PRC 状态。

另一路非 PRC 的 FSP reset-coupling sender 已经给出确定编码。GB202
`GpuSubdevice +0x1100 = 0x126db90` 只接受 RM state 5/6/7，并分别发送单字节
`1/0/2`，即 boot/fuse/base；消息走 FSP use-case 4。它证明 FSP 有“只配置
coupling、稍后再 reset”的协议，但不能仅凭相邻命名断言 PRC knob `0x24` 也使用
完全相同的 1/0/2 值。FSP consumer 不在 host/VBIOS 明文中，所以当前不构造、更
不发送该 PRC 请求。

PRC 请求和回读值均为 16 bit。公开的 NVIDIA GH100 内核源确实给出一条
`NvU16 knobId` / `NvU16 knobValue` 的 PRC read-object 先例，但它只查询
protected-PCIe knob `0x2d`，也只有**那个不同 knob**明确把值 1 解释为 ON；其
HAL caller 只绑定 GH100，GB202 走默认 false stub。因此它只能校准传输宽度，
不能把 floorsweeping `0x1d` 的 required value 推成 1。`0x1d` 的合法值集合仍是
`UNKNOWN`。host 路径在 FS 后没有显式写 0；因此名称中的 `ONE_SHOT` 若名副
其实，可能由 FSP 自清/消费或由会话生命周期失效，但两者目前不能仅凭 host
反汇编区分。公开源码边界与固定版本 hash 见
`parallel/prc_1c_public_audit.md`；该文件名保留早期误判的 `0x1c` 以维持既有
引用，正文与当前结论均已纠正为 `0x1d`。

最后一轮 native/wire 复核又闭合了“host 能编码什么”，但没有闭合“FSP 允许
什么”。JS `parseInt()` 的结果进入 ECMAScript `ToUint32` 形状的转换；task-13
vector 是 `id16+value16+zero16`，末尾两字节由 host 固定为零、没有用户控制的
one-shot/persistence 位；该 tail 的私有字段名仍未知。task-12 readback 把 u16
零扩展后与完整 requested u32 比较。因此 `0..65535` 只是 generic writer 可能
通过回读比较的必要包络，绝不
是 `0x1d` 的 allowed-values。MODS 的 firmware error switch 确实恢复出两类
invalid-knob-value，以及 permission/persistence 相关错误，证明设备侧另有逐项
校验；但没有任何 error/caller/schema 把 `0x1d` 的合法值绑定为 0/1。wire 也没有
独立 one-shot/persistence flag，若语义存在，只能来自私有 per-ID schema/内部
状态。故 `1=arm`、默认值、task-2 consume、自清与 rearm 时机继续为 UNKNOWN。
private response parser 会在日志中保留详细 firmware code/name，但 QCAP 缺失、
错误 response type 与已解析的非零 application error 最终都可折叠成 raw host
status `0x12d`；`0x12e` 专指 PRC read response-length mismatch，`0x12f` 专指
post-write readback mismatch。公开 R580/R610 又只新增 invalid-knob-ID `0x1e3`
映射，没有公开 `0x1d` value schema。因此未来若只保存一个 `0x12d` 数字，仍
无法区分 capability 缺失与具体固件拒绝，必须同时保留详细日志。见
`parallel/prc_1d_domain_followup.md` 与
`parallel/tmux_prc1d_consumer_refresh.md`。

公开驱动同时解释了为什么安装目录中没有 standalone FSP image。官方
`kern_fsp_gb202.c` 明确写着：`In GB202, Bootfsm triggers FSP execution out of
chip reset`；host 只轮询 `NV_THERM_I2CS_SCRATCH_FSP_BOOT_COMPLETE`，等待 FSP
写入 `0xff`。公开源码中的 archive/load 路径针对的是随后由 FSP 验证/启动的
GSP 镜像，而不是 FSP 本体。结合完整 VBIOS inventory，最接近 FSP 本体的本地
候选是 raw bit 2 置位、并被旧共用 header 命名为 encrypted 的 Falcon-v6
`FSP_RUN` 对象；公开代码又不定义其 v6 body。故现在只能说 receiver 位于芯片
复位认证链的不可读一侧，不能
裁决主要代码来自该 VBIOS 对象、芯片 ROM 还是另一内部展开阶段，也无法直接证明
`0x1d` 的自清实现。

一个先前的函数边界判断已经纠正。`Gpu.SetFspPrcWriteInfo()` 不在
`DoInitialModeset()` 尾部，而在 `HandleGpuPreInitArgs()` 中；后者由
`Gpu::Initialize` (`0xda25f0..0xda6066`) 开始阶段内部调用。因此 PRC map
在同一次 GPU 初始化中就已可用，不需要等初次 floorsweep 结束。

解码 JS 还把“是否自动注入 `0x1d`”限定得更清楚。`gpuargs.js:251` 将
`g_FspPrcWriteArray` 初始化为空数组；注册项 `-fsp_prc_write` 的唯一回调
`ArgFspPrcWrite()`（`16481..16487`）只是把用户给出的名称和值压入该数组；
`HandleGpuPreInitArgs()`（`7362..7365`）也只在数组非空时调用
`Gpu.SetFspPrcWriteInfo()`。对整个已解码脚本目录的文本检索没有第二个 push、
没有 floorsweeping one-shot 名称，也没有脚本自动构造 `0x1d` 的路径。因此在
**这份可见 JS 前端**里，无参数启动不会预先写 `0x1d`；只有显式
`-fsp_prc_write`（或另一个未见/私有调用者直接调用 native 接口）才会提供 PRC
write map。这个 bounded negative 不排除 FSP 内已有的持久/启动默认值，也不
证明 native 或其他未解码组件绝无第二入口。

对 native PRC executor `0x185ef60` 的所有 x86 `call rel32` 再做精确目标扫描，
当前 ELF 只有四个直接 caller：通用保存-map 路径 `0x123fcd4`、硬编码
`PRC_KNOB_ID_IST=1` 的 `0x1ebc909`，以及硬编码
`PRC_KNOB_ID_CCD=1/0` 的 `0x1ef55c3/0x1ef6128`。四处都没有自动构造
floorsweeping `0x1d`；JS callback `0x116bd50` 也只在
`0x7d1d65` 以 `SetFspPrcWriteInfo` 方法登记一次。这个 direct-call/immediate
枚举进一步支持“无参数 task 2 不伴随 host 自动写 `0x1d`”，但仍不能排除动态
间接 caller、未包含模块或 FSP 内部初始状态。方法与边界见
`parallel/prc_autoinject_audit.md`。

`0xb9e020` 也已经解码：它只检查环境变量 `SRIOV_GFID` 是否非空。
未设置该变量的普通零售 Linux 路径会绕过一小段 SR-IOV 专用初始化，
随后在 `0xda2e97` 重新汇入相同主线；它并不跳过下面的 PRC/FS 顺序。

GB202 的实际顺序现在可以精确到调用点：

```text
HandleGpuPreInitArgs
  -> SetFspPrcWriteInfo / SetFspPrcReadInfo
Gpu::Initialize
  -> GB202GpuSubdevice +0x340             PRC read   @ 0xda39d2
  -> GB202GpuSubdevice +0x338             PRC write  @ 0xda39f8
  -> JS ProcessFloorsweepingArgs                     @ 0xda3b80
  -> d9ed10
  -> GB202GpuSubdevice +0x9b8
  -> dee1a0
  -> [GpuSubdevice+0x1810] Fs +0x18(true)
  -> GB20xFs::Apply wrapper               0x106fec0
  -> generic FS dispatcher               0x1095e50
  -> GB20xFs +0x520                       conditional FSP operation
       (doFsp=true 时才实际发送 task 2)
  -> if pending-FS: GB20xFs +0x308        host FS apply
  -> return to Gpu::Initialize
  -> if any FS/PRC/fusing request:
       GB202GpuSubdevice +0x3c8            post-FS reset @ 0xda3cba
```

最后一项由“本次确有 FS/PRC/fusing 请求”的汇总标志触发，不是空操作启动的
无条件 reset；`+0x308` 也只在 FS 对象的 pending 标志为真时执行。GB202 的
`GpuSubdevice+0x3c8 = 0x126ddf0` 默认走 `+0x1a8` 的 FLR；只有 JS 属性
`UseBootResetForFs` 为真时才改走 `+0x1b0`，再由 coupling 映射器决定实际
boot/fuse/base/hot 状态。该属性只改变 reset 类型，不能取消 reset。

正常 GB202 FSP-enabled、`SkipFspFs=0` 且前置检查成功时，初次**无
floorsweep 参数**的路径是这里的重要例外。Fs 基类构造器
`0x109a470` 用 `mov word [obj+0x10], 0` 明确把 pending 与 initialized 两个
状态字节同时清零；通用 dispatcher 随后不会从 `+0x320` 的“已经处理过”分支
提前返回。在这条限定路径中，它把 `doFsp=1` 传给 `+0x520` 并同步发送 task 2；
`0x106c4e0` 自身在 `doFsp=false` 时会直接走 no-send 分支，因此不能把 send
写成所有配置下的无条件事实。正常路径的 pending 为 0
会跳过 `+0x308`，而 `Gpu::Initialize` 的请求汇总值为 0 又会跳过
`0xda3cba` 的 post-FS reset。dispatcher 最后才通过 `+0x3d0` 把 initialized
置 1，后续重复调用才会提前返回。

`+0x520` 的实参中没有 pending-FS 标志，只有 `doFsp` 和一个返回布尔指针。
其 6-byte payload 的两个 floorsweep 类型现已从
`FsUtil::FsData::FloorsweepTypeToString()::names` 静态表精确还原：`0x1f` 是
`NVLINK`，`0x20` 是 `NVLC_LINK`（相邻 `0x21=DISPLAY`、
`0x22=HALF_FBPA`）。`0x106bfd0` 把 `NVLINK` mask 和两个 GB20x flag 填入
首字节，再把 `NVLC_LINK` 的 per-link masks 打包进余下字节；
`0x1067ac0..0x1067b43` 对类型 `0x20` 的操作还由日志
`FsLib Adjusting NVLC[%d] Perlink Disable Mask to 0x%x` 独立对齐。

所以 payload **没有** L2 类型 `0x17` 或任何 L2 mask。这反而收紧了协议解释：
若 task 2 会为后续 host L2 写入协调 PLM，那是 task/subobject 操作本身的效果，
不是由 payload 中某个 L2 请求位触发。无参数首轮发送的仍是与有参数路径相同的
task 2 消息；差别发生在 FSP 返回后的 host apply 与外层 reset 分支。

`GB20xFs+0x40 = 0x106c660` 是另一条完整的 FSP/restore/reset 事务：它发送相同
task 2/subobject 1 后也立即调用 `GpuSubdevice+0x3c8(true)`，失败日志是
`Reset after Fs FAILED! GPU may need to be reset!`。GB202 初始主线使用的是上面的
`+0x520 -> +0x308 -> Gpu::Initialize +0x3c8`，因此不能把 `+0x40` 硬插进初始
调用图。它只能说明该备用/显式事务本身总以 reset 收尾，不能否定上面的初次
无参数主线窗口。

task 2 构造路径还带有精确日志 `Skipping FSP PRC during FS`，所以已证事实是：
它属于 floorsweep 生命周期中的 FSP PRC transaction，而不是因附近 NVLink
payload 而误认的链路专用消息。该日志本身不能证明 permission effect。普通 L2
mask 不被打包进该 FSP payload；host 随后仍单独应用软件 floorsweep 表。这里的
`NVLINK/NVLC_LINK` 只是固定通用协议槽位；字段存在不表示零售 GB202 产品具有
NVLink，未实现的拓扑可自然编码为全零。
产品规格也与这项解释一致：GeForce RTX 3090/3090 Ti（Ampere）官方仍列出
NVLink，RTX 4090（Ada）与 RTX 5090（Blackwell）则明确为无 NVLink；专业卡中
RTX A6000（Ampere）有 NVLink，而 RTX 6000 Ada 的官方接口规格也不再列出它。
因此这里看到的是跨产品复用的 MODS/FSP 数据结构，不能据此推断 GB202 上存在
可启用的 PHY、封装引脚或板级连接器。

**FACT：** Hopper 同槽实现在发送相同 task 2/subobject 1 前，读取 OPT/FS PLM
`0x8200d0` 与 L2 PLM `0x8200dc` 的 write-protection 字段；只有两者都等于
`0xf` 时才打印 `Skipping FSP FS because PLMs are already lowered!` 并跳过消息。
GB20x 则省略这次 host 预检查，并在 `doFsp=true` 时先要求 QCAP `0x13` presence、
再发送并等待 command status。**INFERENCE：** Hopper sibling precheck 与 GB20x
send-before-apply 顺序强烈支持 task 2 旨在准备 `d0/dc`。**UNKNOWN：**
production GB202 是否实际改变任一 PLM、返回后是否仍保持，以及是否处理独立
`f8`；日志、QCAP presence 与 status zero 都不能闭合这些状态。

GB20x 调用 `0x185e890(task=2, subobject=1)` 时 response-vector 参数为 null，
成功后也只返回状态码，没有 host 保存的 token、cookie 或响应 payload；调用者
临时设置的 FSP 对象 `+0x31` 标志在返回后立即清零。若权限存在会话期或
one-shot 消费语义，其状态因此只能保存在 FSP/硬件侧，而不是 MODS 收到的一枚
显式授权令牌。公开 610 的通用 FSP command response 也只有三个 `NvU32`：
`taskId`、`commandNvdmType`、`errorCode`；没有 subobject、PLM snapshot、prior
value、lease/expiry、undo 或 restore handle。公开 schema 与 MODS 的 null
response-vector 相互支持“host 不持有可恢复授权对象”这一限定负结论，但不能
排除 FSP 内部自动收权。

正常 GB202 路径与 `SkipFspFs` 路径的 PLM 时序也已分开：

- 正常路径把 `doFsp=1` 传给 `GB20xFs+0x520 = 0x106c4e0`，后者同步发送
  task 2/subobject 1；成功返回后，通用 dispatcher 才调用 `+0x308` 做 host
  floorsweep；
- 只有 `SkipFspFs=1` 时，通用 dispatcher 才先调用 `0x1095cb0`，要求
  OPT/FS 与 L2 两个 PLM 都已经是 `0xf`，否则以 `0x308` 拒绝跳过 FSP；
- 正常 task 2 返回后到 host apply 之间没有再次读取 PLM；apply 之后的
  `+0x488 = 0x105f060` 在 `SkipFspFs=0` 时也是 no-op，没有发送第二条 FSP
  消息或显式收回权限；
- 全程序没有 `0x2059c000/0x20e0c000` 两个 PLM setter 的可执行立即数，说明
  host 从不直接降低这两个 PLM。

因此，正常 `doFsp=true` host 顺序和 Hopper 同槽 precheck 强烈支持这样的设计
意图：task 2 为紧接着的原厂 floorsweep apply 准备 `0x8200d0/0x8200dc` 权限。
但 GB202 FSP consumer 不可见，production 固件实际降低哪些 PLM、权限是否在
返回后存在、何时自动收回均为 `UNKNOWN`；不能从 host 相对顺序单独把意图升级
成已发生的状态变化。这里也不能扩写成“task 2 已给 direct-shadow writer
准备好全部权限”：`ProgramSwFusePlan` 还要先写 `0x820040.bit0`，该 latch
另受 `0x8200f8` 保护，而 Hopper 的 skip-precheck 只检查 `d0/dc`。

task 2 还有一道不能忽略的 FSP capability 门。通用 sender 的 task-2 分支会
查询缓存的 QCAPS 记录；记录不存在时精确报错
`Floorseeping PRC isn't supported by FSP or is not yet active`，返回 `0x12d`，
根本不发送消息。继续展开 task-to-QCAP 映射 `0x1857b10` 后，这道门的关系已经
更精确：task 2 在 `0x185e530`、PRC-write task 13 在 `0x185e490` 都调用
`0x185e0e0`，而映射器对输入 2 和 13 均返回同一个 QCAP key **`0x13`**。

公开 610.43.03 驱动头文件进一步给这个 key 定了义：
`nvdm_format.h` 明确写有 `NVDM_TYPE_PRC = 0x13`、
`NVDM_TYPE_CAPS_QUERY = 0x16`。`fsp_caps_query_rpc.h` 的查询 payload 也只有一个
`subMessageId` 字节。因此这里的 QCAP `0x13` 就是“FSP 是否支持 PRC 消息族”，
不是尚未识别的板卡 capability。公开 RM 内核代码拥有通用 FSP query helper，
但唯一显式的 GPU PRC read-object caller 是上述 GH100-only protected-PCIe
查询；GB202 虽会把 `NVDM_TYPE_PRC=0x13` 经通用 transport 路由到 SEID 0，
却没有公开 caller。公开 SDK/RM control 头文件中也没有 arbitrary PRC read、
FSP-NVDM passthrough 或 QCAP 用户态 control。故目前仍没有既公开又纯只读的
用户态查询可直接取得本卡的 `0x13` 或任意 knob；为此自行发送内部 FSP 消息
不属于本阶段的安全读回方案。

QCAP record 的字段语义也已由 MODS 自己的打印标题闭合：每个 dword 是
`low16=NvdmType, high16=Version`，对应只读字符串
`NvdmType  :  Version`。task-2 helper 会把 Version 暂存到 caller stack，但 sender
只使用“key `0x13` 是否存在”的 Boolean；它不比较 Version、不把它编码进 packet，
随后还会复用并覆盖该栈槽。task-2 caller 显式传 null response vector，完成后只
消费 `NV_STATUS`，没有保存 token、lease、旧 PLM snapshot 或 undo handle。
所以 QCAP `0x13` 是 PRC 命令族/版本 capability 记录，不是 security level 或
credential；presence 通过后仍有一次独立的 FSP command 裁决。Version 的内部编码、
发布条件与 cache epoch 仍 UNKNOWN。见 `parallel/qcap13_semantics.md` 与
`parallel/task2_auth_provenance.md`。

失败码也不是单义证据。初始化 prefetch 是 best-effort；lookup 只在整棵 tree 为空
时再做一次 all-query，若 tree 已有别的 capability 却缺 `0x13`，不会 targeted
refresh。最终缺 key 时，真正不支持、尚未 active、query/parse 失败或非空但陈旧/
不完整的 cache 都会折叠为同一 raw `0x12d` 与 unsupported/not-active 日志，并且
正常 task-2 packet 根本不发送。因此未来即便看到 `0x12d`，也不能据此断言硬件
永久不支持；反之 presence 也不代表命令会成功。

QCAP cache 的 owner/lifetime 也已闭合到 host 侧。`{NvdmType,Version}` tree
属于 `GpuSubdevice+0x1ad8` 指向的 0xa8-byte FSP wrapper；完整对象析构才释放它，
普通 post-program reset 保留同一 wrapper，既不 clear 也不 refetch。后续 all-query
又只是 unique-add：重复 key 不覆盖旧 Version，新 response 中消失的 key 也不会
被删除。因此 QCAP presence 是可能跨 firmware/reset 状态变陈旧的 capability
snapshot，绝不是实时 permission lease；真正每次请求仍只能看独立 FSP status。
见 `parallel/qcap_cache_lifetime.md`。

`Gpu::Initialize` 确实在 `0xda3654`、执行用户 PRC write map **之前**调用
`0x185deb0(0xff)` 预取并缓存全部 QCAPS，PRC writer `0x185ef60` 也没有清空或
重查这张表；但 `0x1d` 写入本身已经依赖同一条 `0x13` capability。因此它不能
“创造”一条原先缺失的 capability：缺失时 PRC write 会先以
`PrcWrite isn't supported by FSP or is not yet active` 失败。反过来，若
`0x1d` 的 PRC write 已经成功，则随后 task 2 不会再因缺少另一条 QCAP 而失败。
这排除了“写 0x1d 后必须刷新另一条 capability cache”这个独立障碍；剩余未知
收敛为本次启动是否已有 `0x13`、以及 FSP 策略是否接受具体 knob/task。

同时找到了 MODS 自带的 no-reset 控制。解码后的命令行表在
`gpuargs.js:1249` 把 **`-skip_prc_reset`** 直接绑定到静态 JS 属性
`Gpu.SkipPrcReset`，说明这不是需要修改二进制才能触发的隐藏分支。该属性
由 getter `0x11613f0`/setter `0xd9b020` 读写 `Gpu` 全局对象 `+0x8e`；
`Gpu::Initialize` 在 `0xda3ca3` 直接检查同一字节。只要本轮确有需要 reset 的
请求且走 FSP 路径，值为 1 就跳过 `GpuSubdevice+0x3c8`。这证明原厂确实预留了
“先执行 PRC/FS、保持未 reset 状态”的 host control-flow 时序；它只建立一个
no-post-FS-reset interval，不证明其中存在权限窗口。它不绕过 QCAPS/FSP 策略，
不改变进程内 `SecurityUnlockLevel`，也不抑制
`SetSwFuses` 自己成功后的 reset/reinit。

`-fsp_prc_read` 本身又有一条更窄的 host-visible no-explicit-reset 结论。JS
read array 默认空，只有显式参数才填入；native executor `0x185f500` 解析名称后
调用 `0x185ea20`。后者发送 task `12`/submessage `2`，request 是 2-byte knob
ID，成功 response body 必须恰为 4 bytes，并取首个 `u16` 作为 knob value。
task 12 也经 `0x1857b10` 映射到 QCAP `0x13`，所以这不是本地缓存读取，而是一
次主动的 FSP PRC transaction。

在 `Gpu::Initialize` 中，early read map `Gpu+0x1e0` 于
`0xda39ba..0xda39da` 调用 `+0x340`，但不进入本轮 reset/mutation 汇总；相邻
write map `Gpu+0x1b0` 不仅调用 `+0x338`，还明确设置 reset-request local。
尾部同构 fallback 也有直接不对称：reader `0xd9d760` 调 `+0x340` 后没有显式
reset 槽调用，而 writer `0xd9c390` 在 `+0x338` 成功后立刻调用
`+0x1b0(state=3)`。因此，在没有其他 mutation 请求的限定 host 路径上，read
map 本身不请求 reset。这是**可见 host 控制流的负结论**，不是安全保证：完整
MODS 仍会初始化 GPU、可能发送首次 task 2，并向不可见 consumer 的 FSP 发送
内部 read 请求。当前桌面 5090 上仍不执行它。详见
`parallel/prc_read_noreset_audit.md`。

但“reader 本身不 reset”不能改写成“存在 stock 纯读初始化模式”。对两个相关
开关继续闭合后，普通 GB202 首次初始化里没有找到能让
`-fsp_prc_read` 成功、同时可靠跳过 floorsweep task 2 的参数组合：

- `SkipFspFs=1` 会在 `0x1095cb0` 只读检查 `0x8200d0/0x8200dc`；若两者尚未
  处于常量 `0xf` 就返回 `0x308`，它自己没有 PLM setter；
- `SkipFspFs` 与 `SkipFsPlmCheck` 同时启用会被同一 helper 拒绝；
- Hopper 的 `SkipFsPlmCheck` 是**跳过发送前检查、直接发 task 2**，不是抑制
  task 2；GB20x `+0x520 = 0x106c4e0` 根本不读取它，只按传入 `doFsp` 决定
  `0x106c587` 的发送。

所以 `SkipFspFs` 更像“PLM 已经开放时不要重复准备”的路径，不会从普通初态
创造无副作用的 PRC reader。故意利用其初始化失败也没有 rollback 保证，不是
安全候选。完整控制流见 `parallel/prc_read_task2_avoidance.md`。

对整个 `Gpu::Initialize` 的 reset 入口重新枚举后，task 2 之后没有漏掉默认
reset：`0xda3538` 的 `+0x1b0(state=4)` 只在显式 pre-init reset 标志下调用；
`0xda3cba` 的 `+0x3c8` 只在本轮 FS/PRC/fusing 请求汇总非零时调用；
`0xda5e4b/0xda5e62` 的 late PRC write/read fallback 只在相应 map 非空并满足
逐设备 type/feature/HAL 条件时进入。无参数首轮这些 map 为空，也没有显式
pre-init reset 或 mutation 汇总，所以上述 reset 条件均不成立；这不要求猜测
GB202 的 `+0x1d8` 私有 HAL 槽最终绑定。

紧随其后的 `GpuSubdevice+0x448(3) -> +0x450(3)` 也不是隐藏 reset/收权链。
GB202 的最终实现 `0x1255150` 读取并报告 FSP fuse-error 状态，明文日志包括
`FSP error status register`、`FSP detected an anomalous fuse configuration` 和
`No register read access for FSP fuse check, skipping check...`；该函数中没有
`+0x1a8/+0x1b0/+0x3c8` reset 调用，也没有已知 L2 PLM setter。主机侧至此没有
发现 task 2 后的 reset、PLM close message 或已知收权调用；这个负结论既不证明
task 2 曾经开放 PLM，也不证明任何状态持续到返回脚本层。FSP/GFW 固件能否在
host 看不见的条件下按计时、状态机或首次写入改变状态，仍不能由这个 ELF 排除。

Hopper 的同槽 task-2 实现 `0x1094990` 在发送前会检查 `0x8200d0` 与
`0x8200dc` 是否都等于 RegHal 常量 `0xf`；若值已如此，它打印
`Skipping FSP FS because PLMs are already lowered!` 并跳过 FSP。这只证明一个
预先存在的 `d0/dc.[7:4]==0xf` 状态能在发送前被观察并抑制发送；它不证明该状态
来自更早一次 task 2，也不证明 task-2 status zero 后的持续性。

初次无 FS 参数路径只建立了一个 host control-flow 候选：task 2 可以返回 status，
随后 host 跳过 apply 与 reset 并正常返回脚本层；从该 status 到返回之间没有
PLM read。因此“由同一 MODS 进程中的后续脚本调用 `SetSwFuses`”仍只是研究
假设：`dc` 是否曾改变、是否仍可写，以及独立 `f8` 是否允许 latch RMW 都是
UNKNOWN。后续 writer 还必须另过进程内 `SecurityUnlockLevel > 3`、
`disable_sw_override`、reset coupling 和物理健康等门槛。这是一个有依据的 host
时序候选，不是已证明的 permission window，也不构成在桌面 5090 上运行未知
MODS、写寄存器或触发 reset 的理由。

`GpuSubdevice+0x1810` 的对象身份也已经闭合：通用子设备构造器按芯片表
`record+0x20` 调用工厂；GB202 (`0xff2`) 的该槽是 `0x1056cc0`，它分配
并构造 `GB20xFs`。所以上述 `+0x18` 不是同偏移的其他对象虚函数，
就是已解码的 floorsweep dispatcher 入口。

PRC 执行前还检查 feature ID `0xdb`。从后续 PRC 门控和明文
`Can't have both GPUSUB_SUPPORTS_FSP & GPUSUB_SUPPORTS_GFW_HOLDOFF enabled!`
可对齐 `0xdb = GPUSUB_SUPPORTS_FSP`，相邻的 `0xce` 是旧 GFW-holdoff 路径。
GB202 使用 FSP 分支。PRC/JS 之后还有一个 GB202 `+0x438 = 0x124bc60`
的中间检查；它通过 RegHal `0x12e54000/0x22e54000` 尝试把一个
32-bit GFW 控制值置 0，成功后进入 `d9ed10`。同一 RegHal setter 在其他
GB20x 路径的失败日志是 `GFW boot did not complete`，因此它是 GFW/FSP 启动
协调，不是额外的 L2 写入器。

末尾另有一个通用 PRC writer `0xd9c390`，它在其他类型的子设备上会
写 PRC 后调用类型 3 `hot` reset。这不能套到 GB202：该 writer 先检查
GpuSubdevice vtable `+0x198`，若它正是默认实现 `0xd70270` 就直接跳过；
GB202 的 `+0x198` 恰好就是 `0xd70270`。所以零售 GB202 的关键路径是
前面那次“PRC -> FS”，不会被这个末尾 fallback 无条件 hot reset。

这项发现只固定了“如果 host 显式写 one-shot，它位于后续条件 task 2 之前”，
并没有证明 task 2 要求或消费它：正常首次 task 2 可以在 JS PRC write map 为空
时发送；反过来，task-13 write 与 task 2 又受各自门控，不保证配对。host 在
task 2 后既不重读也不清零 `0x1d`，所以若真有 consume/self-clear/rearm，只能
位于目前不可见的 FSP/硬件状态机。它也尚未直接解决 5090 L2 解锁：
`GB20xFs +0x308` 的已解码 L2 路径仍写普通
SW disable mask，不会清 `0x8234e0+4*FBP` 的 raw/OPT mask。因此目前最合理的
解释仍只是推断：`FLOORSWEEPING_ALLOW_INB_ONE_SHOT` 可能向 FSP 准备某种原厂
floorsweep/PLM 权限，但它本身不替代 Blackwell direct-shadow writer。两者之间
是否存在可复用同步钩子，以及 knob `0x1d` 的精确允许值/消费/自清时机，仍需
FSP consumer 才能证明。

### GSP 拓扑枚举读取的是 fuse status 别名，不是 raw OPT 槽

610.43.03 GSP 的 GR HAL 构造器已经按 GB202 chip index 65 做了离线重放。GR
对象 vtable `+0x9b0` 精确落到 `0x132ae68`；共享 helper
`RMROPL2FuseMaskForFModel`（`0x132932c`）逐 FBP 调用它，并把结果限制到该代的
ROP/L2 位宽。`0x132ae68` 的核心行为是：

```text
FuseReadByOffset(0x0d70 + 4*FBP, &raw)
return ~raw
```

这里的对象身份也已闭合。`pGpu+0x1dc0` 由 class ID `0x95ba71` 构造，正是大小
`0x360` 的 `OBJFUSE`；其 `+0x100` 槽在 GB202 上先经 thunk `0x13d3b04`，再进入
`0x13e0414`。后者取得 Fuse `IoAperture` 后调用 aperture `Read32(offset)`，没有
先从 GR 软件配置或普通 host cache 取值。因此 GSP 实际观察的是 fuse aperture
内 `0x820d70..0x820d8c` 的状态/读出寄存器，而非直接读取
`0x8234e0..0x8234fc` raw OPT/shadow 槽。

MODS 的独立 GB202 RegHal 表交叉验证了这组新地址：read ID `0x10d6c000` 和
`0x10d70000` 都展开为 `0x820d70 + 4*index`，数组元数据宽度为 16；其中
`0x10d6c000` 也被 GB20x floorsweep 参数修正器用作“FBP L2 current mask”。
这不是反编译器把 `0x8234e0` 错算成另一个地址。

这使关键链条已经闭合到原厂 host 控制流框架层面：流程尝试设置
`0x820040.bit0`，调用 raw OPT shadow writer 并回读；只有 aggregate 状态为零
才进入由现有 reset-coupling 状态选择类型的 reset/reinit，但权限哨兵分支也可能
未被计错。独立的 GSP getter 能从 `0x820d70+4*FBP` 枚举；原厂设计强烈预期
reset/reinit 后会重新形成并枚举 topology，但 success tail 没有调用 getter 去
比较本次 plan。若当时 boot coupling 已
激活，映射器会选择类型 5
`boot reset`；若 base/fuse coupling 已激活或三者均未激活，则分别选择
base/fuse/hot，不能把 boot 分支写成无条件事实。与之对照，显式 resense host
路径会尝试 fuse coupling、发出 latch-clear 请求，并在 preparation 成功且非
pre-silicon 时请求 reset；mapper 只有在当时观察到 base=0、fuse=1 时才选择
类型 6，不能证明该 fuse bit 来自本次请求。其角色强烈支持“重新采用实体熔丝”
的解释。两条路径共同构成“reset 后由 fuse-status 视图重新枚举”的强语义证据，
但哪种 reset 能可靠地让启用的 OPT shadow roll up 到该视图仍需进一步区分。

仍需保留一个实机边界：rollup 本身发生在硬件/GFW 初始化中，二进制里不会出现
一条普通 CPU 赋值；而且写回 shadow 成功并不能证明零售卡的实时 PLM 接受写入、
GFW 不拒绝该组合、或新增 L2 单元物理健康。因此只能说 host 的
“写 shadow -> reset/reinit -> GSP 重新枚举”框架已经知道；真正决定 shadow
是否被保留、消费并传播到 effective topology 的 reset-domain/firmware/hardware
机制仍未知，本卡当然也没有验证解锁。

同一 helper 中的配置掩码也不是零售旁路：只有 FModel/仿真标志成立且 GPU 被
标为仿真模型时才把配置值与硬件 mask 相交；真实硬件分支会记录提示后仍返回
FuseRead 的结果。故不能用 registry/config mask 在零售 GB202 上绕过 fuse
status。

### Blackwell `DecodeIff` 到底会不会烧写

MODS 暴露给脚本的 `DecodeIff` 不是旧 `GpuFuse` 的同名打印函数，而是 5090
实际使用的 `NewFuse` 实现。已对齐的真实链路为：

```text
NewFuse::DecodeIff                    0x145aea0
  -> EncodingAdapter                 0x1478250
  -> SplitMacroEncoder 虚函数 +0xb8  0x1488d90
  -> SplitMacro 元数据/值查找
  -> NewFuse 的记录打印器             0x1459950
```

这条命令自身没有进入 soft-burn、IFF 执行或熔丝写入路径；它收集并解码已经由
编码器/访问器提供的记录，再打印结果。旧框架中位于 `0x1432a70` 的同名核心更
简单，只遍历对象内存中的记录 vector。两者都不是烧写函数。

但这**不等于可以在主系统放心运行整个 MODS**。Blackwell 实现会在内部映射未
初始化时延迟建立 `SplitMacro` 的描述器和缓存；其依赖对象是在 MODS 初始化
阶段创建的。现有静态证据只能证明 `DecodeIff` 命令本身不烧写，不能证明加载
未签名 MODS、初始化其内核组件和设备对象的全过程没有副作用。

另外，旧框架的原始熔丝行感测器 `0x15181a0` 虽然语义是读取，却会先写选择器
和触发控制寄存器，再读取感测结果；它并不是“只做普通 MMIO read”的安全
探针。故当前仍不在主机上执行 MODS，也不把 `DecodeIff` 当作已获安全认证的
验票命令。

## 部分开启的理论粒度

按此前未留原始输出的读取报告，本卡八个 FBP 都是低 8-bit 掩码 `0x12`，即
每个 FBP 的 bit 1 和 bit 4 被关。若该报告与 2 MiB/bit 模型均准确，则
16 个置位 bit 正好解释 128 MiB 完整模型与归档 96 MiB 之间的差额。所以从
**条件性的掩码编码/容量记账**看，理论序列是：

```text
96 -> 98 -> 100 -> ... -> 126 -> 128 MiB
```

在该模型下，清掉一个报告为置位的 bit，理论上就是某个 FBP 增加 2 MiB。
例如仅把 FBP0 从 `0x12` 变为 `0x10`，记账结果为 98 MiB；把两个 bit 清掉
则是 100 MiB。这是离线编码能力，不证明本卡当前值、写入接受或物理健康。

这里的计数域不能混称为一套“LTS”。静态 RegHal 直接证明的是每 FBP 一个
`[7:0]` raw 字段；MODS tag-map 给出 `2 LTC 标签 × 4 RM/MODS slice 标签 = 8`
个人类可读位置。归档 NCU 则直接报告当前 12 个 `l2s`/FBP，满配 16 个
`l2s`/FBP 以及“每 raw bit 对应两个 NCU l2s”都仍依赖规则等容量模型。
PerfWorks 的 48 个 rollup 又是匿名的另一计数层。因而 `2 MiB/bit` 只可由
`96 MiB / 48 enabled raw positions` 条件性记账得到，不能反向证明一个 raw bit
就是已经定位的两个 1-MiB 物理单元。

现在还能把“编码粒度”从容量推算提升为控制流结论。`SplitMacro_EncodeSetSw`
`0x148b4c0` 只遍历调用者实际提供的名称树；每个名称只查一个 descriptor，读取
其唯一的 domain-relative raw offset `descriptor+0x8c`，按 `type/bits` 计算一个
raw 值，再以
该 offset 为键插入或覆盖一个计划节点。函数没有遍历全部 descriptor，也没有
按 FBP 数量复制。外层 `0x147b4b0` 的循环边界是 macro accessor/die 数量，
不是 8 个 FBP；单 die GB202 只经过一套 SplitMacro 编码器，随后仍按 raw
offset 合并。因此只提供 `OPT_L2SLICE_FBP0_DISABLE = 0xef` 时，编码结果严格是
一项 plan key `0x34e0 = 0x10`，经 domain-5 wrapper 才解析为最终 BAR0
`0x8234e0`；不会暗中把 `FBP1..7` 也写成同值。

公开 JS wrapper 也不会把稀疏输入补成完整 SKU。`0x1446860` 要求恰好一个
`fuseNameValPairs` 参数，遍历其中的二元元素；每个元素必须正好含一个名称
字符串和一个 32-bit 整数，名称规范化后插入输入树，重复名称直接报错。遍历
结束便把这棵树原样交给 `NewFuse` vtable `+0x18`。它没有枚举未提供的名称、
查询目标 SKU 或自动补齐八个 L2 descriptor。于是从 JS 单个 pair 到最终单个
raw 节点的稀疏性是端到端成立的，不只是低层 plan API 的理论能力。

这证明官方高层编码器可以表达“单个 FBP、单个 raw mask bit”的修改。这里的
“单 bit”只描述新旧 8-bit 值的 delta；实际计划项仍写该 FBP 的完整 `[7:0]`
raw 值，其余七位必须来自可信基线，不能理解成寄存器级原子 bit clear。在
未归档 `0x12` 报告与 2 MiB/bit accounting model 都成立时，才可把它条件性
标注为“理论 +2 MiB”；编码器本身不证明容量增量或物理 slice 身份。单项计划
只减少同一次调用的多项部分提交面；global latch、失败不回滚、权限哨兵可能
未计错以及 reset/reinit 风险仍在，没有把实卡实验变成安全操作。

后续 host-shape 审计又把“单项可以编码”扩展到稀疏多项：JS wrapper 不补齐未
提供的 FBP，SplitMacro 每个名称只生成自己的 raw node，`ProgramSwFusePlan`
逐 node 执行且没有全局 L2/PAC join、跨 FBP equality、偶数 popcount 或
allowed-pattern lookup。因此在同一个条件 accounting model 下，`96->98/100/110
MiB` 对应的 1/2/7 个 raw-position delta 都具有 stock host plan-level
representability；奇数 7 个不会被已见 host 代码自动补成偶数或整列。这仍不证明
authentic JSON 的产品数据、private FsLib 的其他入口、FSP/GFW 或 hardware
sense/route 会接受该形状。完整矩阵见 `parallel/l2_mask_constraint_audit.md`。

这里必须区分“host 编码粒度”和“能稳定工作的最小粒度”：已见 direct-shadow
host 链没有强制配对/对称规则，但更低层的路由/PAC、GSP/FSP/GFW 拓扑校验或
单元本身的物理缺陷仍可能要求组合修改或直接拒绝。
因此可离线表达的最小候选只是一个 raw mask bit；“2 MiB”仍是条件 accounting
标签，不是单 bit 必然对应某个可独立启用物理单元的保证。
当前也没有 raw bit 以下的 selector；即使接受 2-MiB 模型，也不能用这条路径
单选其中一个假定的 1-MiB NCU `l2s`。反过来，硬件真正接受并能稳定工作的最小
组合仍可能大于一个 bit，或者根本拒绝被屏蔽单元。

能稳定命名的身份目前只有 `(FBP, raw_bit)`/寄存器坐标。OpenRM 对
`ltsEnMask` 只规定“在一个 FBP 内 flatten”，没有规定 flatten 顺序；因此不能
把报告中的 bit 1 或 bit 4 固定写成某个 `LTCx.slicey`，也不能绑定到绝对 NCU
`l2s` 或 PerfWorks rollup instance。完整证据与两种同样相容的排列反例见
`parallel/l2_mask_granularity.md`。
若将来映射、权限和恢复链都齐全，最保守的首次实验目标也至多是报告中的一个
raw mask bit（accounting model 下理论 +2 MiB），而不是报告中的全部 16 bit
（该 model 下 32 MiB）。

## 已恢复的 fuseless 记录格式

Hopper 与 Blackwell 的 fuseless 编码主槽位共用同一实现；Blackwell 改写的是
少数外围槽位，不是下面这段行布局。编码器把每条物理记录做成一个 32-bit
word：

```text
31                 27 26              16 15             6 5 4          0
+--------------------+------------------+----------------+---+------------+
| chainId[9:5]       | data[10:0]       | offset[9:0]    | S | chainId[4:0] |
+--------------------+------------------+----------------+---+------------+
```

等价公式是：

```text
row = (data11 << 16)
    | ((chainId & 0x3e0) << 22)
    | ((offset & 0x3ff) << 6)
    | (state << 5)
    | (chainId & 0x1f)
```

- `chainId` 为 10 bit；
- `offset` 为该链上第几个 11-bit 块；
- `data` 是该块的 11 bit 内容；
- bit 5 是编码器单独检查的状态位，新构造的普通记录为 0；
- 空记录标记 `0xf800001f` 解码为 `chainId=0x3ff, offset=0, data=0`。

逆向位置包括共享编码器 `0x14da3c0`、11-bit 打包函数 `0x14d93c0` 和解码槽位
`0x14d9860`。编码器会把已有记录解码后比较，明确拒绝 1→0 转换；所以即使
知道目标行，也不能脱离本卡原始行状态直接生成可写补丁。

### JSON 坐标如何变成记录

这段转换也已经完整对上：

1. `fuselessFuse.fuseName` 找到逻辑熔丝；
2. 按 `jtagConfigFields` 的列出顺序处理对应 `configFields`；
3. 每项消耗逻辑值低端的 `msbIndex-lsbIndex+1` bit，然后把逻辑值右移该宽度；
4. 这些 bit 写入 `chainId` 指定链的 `lsbIndex..msbIndex`；
5. 链位号除以 11 得到记录 `offset`，余数得到 `data` 内的 bit 位置。

解析器确实也保存 `blockIndex` 和 `blockOffset`，但共享的 fuseless 行构造路径
没有用它们生成上述记录；它们属于同一配置描述中的其他 JTAG/实体熔丝访问
坐标。关键公式因此不再缺失，缺失的是目标 L2 名称究竟对应哪些
`jtagConfigFields`，以及那些 field 的实际 `chainId/lsbIndex/msbIndex` 数值。

相关静态控制流为：配置项解析器 `0xca95b0` → `fuselessFuse` 名称解析和复制
`0xca5df0` → 逻辑值分片 `0x1493960` → 11-bit 链打包 `0x14d93c0`。

## 已恢复的 IFF 外层编码

IFF 外层也已从“知道有 CRC”推进到可复现：

- CRC 为反射形式 CRC-16，反射多项式 `0xa001`（正常写法 `0x8005`）；
- 初值 0，每个 32-bit word 从最低 bit 开始处理，无最终 xor；
- 例如单词 `0x00000001` 的结果为 `0xfc01`，单词 `0x80000000` 的结果为
  `0xa001`；
- MODS 中的原实现位于 `0x14dc8c0`，逐 word 调用展开的 XOR 网络
  `0x14dc230`。

已识别的低 4-bit 命令类型包括执行过滤、PRI 错误轮询、四种 retry 比较、四种
abort 比较、modify、write 和 set-field。尤其是：

- type `0xd` 的直接写入使用两行，地址行编码为
  `((address >> 2) << 6) | 0x2d`，另一行携带 value；
- type `0xe` 的 set-field 单行中包含 field value、shift、space 和地址偏移；
- Blackwell 尾部例程固定追加 `0x00000000`、`0xfffbf5ff`，再追加
  `0x08200dec` 或 `0x0bf00dec`，共三行。

这说明信封、校验和行语法都可以离线重建。但它们只解决“信怎么写”，没有
提供“目标 L2 在哪一格”的 GB202 地址簿，也不会绕过 SW override 与固件权限。

## `gb202_f.json` 仍是高层入口缺口，但不再是唯一地址来源

MODS 按芯片 ID `0xff2` 选择外部文件 `gb202_f.json`。包内只有这个文件名，
没有文件内容；项目目录、已提取 payload 及完整可识别 archive 成员链的
filename/member 搜索都没有找到副本。

这一缺失现已从“展开目录没找到”提升为完整可识别归档链的成员级结论。外层
ZIP 只有一个 TBZ；其中的 `570.151.tgz` 共 133 个 payload node，与
`mods_audit/static/extracted_inner` 一一一致。外层 `python3.tbz` 的 33,236 个
成员，以及识别出的 driver、fatool、CASK、CUDA、NVDEC/NVOFA/NVJPG 等嵌套
archive 也都没有 GB202 FuseSpec/schema 成员。ELF 内只有默认文件名、解析器
schema key、独立 tag-map 和 RegHal 元数据，没有可寻址的 JSON body。加密
Nautilus manifest、私有 staging 或自定义编码 blob 仍不能由成员名负搜索排除；
完整边界见 `parallel/gb202_fuse_descriptor_inventory.md`。

公开代码索引也已用精确 literal 查询复核，并包含 archived repository 与 fork：
`gb202_f.json`、旧架构 `ga102_f.json`、`jtagConfigFields` 和
`OPT_L2SLICE_FBP0_DISABLE` 均为 0 个代码命中。此前对普通网页搜索的结果也为空。
这不证明文件从未泄露或不存在于私有制造包，只说明当前没有可验证的公开文本
来源；不会为补齐 schema 去下载更多来历不明的 MODS 可执行包。

外层 JSON schema 已经从 `FuseJsonParser2` 的虚表和顶层调度器静态恢复，因而
“不知道文件语法”不再是阻塞项。主 `_f.json` 的最小结构是：

```text
header:
    "Perforce file revision"   string（解析器从 `#` 后取十进制 revision）
    "Generation time"          string
    "Project Name"             string
    "Status"                   string
    "Version"                  integer

options:
    Chip_options:               object，普通 `_f.json` 以 FPF 标志 0 解析
        <fuse name>:
            bits                integer，必需
            customer_visible    integer，必需
            type                string，必需
            offset              integer或解析器支持的位域字符串，必需
            reload              integer，可选
            ecc                 string，可选
    Map_options:                object；空对象可直接成功
    Mkt_options:
        dies:                   object；空对象可直接成功
```

`Pseudo_fuses`、`Fuse_encoding`、`Tag_map`、`Floorsweeping_options`、
`IFF_patches`、`Fuse_macro`、`Sku_ids` 等段由顶层解析器用 `HasMember` 检查，
均不是上述普通 descriptor 的语法必需项。后处理还检查四组 patch 地址段，但
不存在时会跳过。对应的 `_POR.json` 与 `_fpf.json` 是按主文件名派生后尝试
加载的附加文件；文件不存在走可选分支，不会否定已经解析的主 `_f.json`。

`Chip_options` 的第三个解析参数已经由调用点坐实为 FPF 来源标志：主 `_f.json`
调用时传 0，派生 `_fpf.json` 调用时传 1，最终保存到 descriptor `+0x80`。
相邻布局也已确认：`+0x84 customer_visible`、`+0x88 bits`、`+0x8c`
domain-relative raw offset，`type` 字符串在 `+0x60`。direct-shadow 编码器读取
`+0x80/+0x88/+0x8c` 和
`type`，没有读取 `customer_visible`；所以后者是必填元数据，不是 raw plan
按名称编码的权限门。

类型字符串也不是推测：编码器精确比较小写 `"dis"`，然后执行
`raw = ~logical & ((1 << bits) - 1)`；另一特殊值是 `"en/dis"`。因此 L2
disable 字段若以已恢复的 8-bit descriptor 表示，`0xed -> raw 0x12`、
`0xef -> raw 0x10` 等补码关系与此前独立反编译完全一致。

这已经足以构造一个**语法上**能表达八个 L2 raw OPT domain offsets 的最小描述
数据库，
但没有因此生成可直接交给 MODS 的文件：自造 schema 不能替代原厂 GB202 内容
的可信性，也不能绕过进程内 `SecurityUnlockLevel > 3`、PLM、
`disable_sw_override`、GSP 行为和
reset/reload 风险。当前只把恢复结果用于离线验证器和交叉核对。

需要区分该外部 fuse JSON 的两种消费者：普通按名称的 `SetSwFuses`
编码器需要名称、`type`、位宽和 domain-relative raw OPT offset；IFF/fuseless
编码器则需要下面的 JTAG chain 坐标。前者最终生成 raw shadow 计划，后者生成
IFF 记录。文件
缺失会卡住原样运行时的两个**高层名称入口**；现在前者的最小 parser schema
可以离线重建，后者仍缺 chain 坐标。已经确认的低层 raw plan 接口本身不需要
chain 坐标。

对 direct-shadow 名称入口，真实缺口精确到八个大写 descriptor
`OPT_L2SLICE_FBP0_DISABLE ... OPT_L2SLICE_FBP7_DISABLE` 的 authentic
`bits/type/customer_visible/domain-relative raw offset` 记录。`_POR.json`、
`_fpf.json` 与 IFF chain 坐标都不是这条 name-to-raw-plan 路径的替代品。自造
一个能过 parser 的
最小 JSON 只能证明语法，不能证明它等价于 NVIDIA 的 GB202 数据库，因而不把
它交给 MODS。

已经逆出 JSON 相关结构：

```text
configFields[]:
    name
    chainId
    blockIndex
    blockOffset
    lsbIndex
    msbIndex

fuselessFuse[]:
    fuseName
    jtagConfigFields[]
```

`fuselessFuse` 先按 `fuseName` 找到逻辑熔丝，再把每个
`jtagConfigFields` 指向的 JTAG 链坐标复制给编码器。它不是任意
`地址 + mask + value` 列表。

静态跟踪进一步确认，复制过程中五个数没有再被散列或加密。也就是说，拿到
可信的原始 JSON 后即可直接离线展开；反过来，没有 JSON 时也不存在能从
BAR0 地址倒推出 chain 坐标的隐藏公式。

Blackwell 编码器结束后会逐项检查用户请求是否进入“已编码”集合。缺少映射
时打印 `Unencoded fuse: <name>` 并返回错误 2；没有根据普通 BAR/RegHal
描述自动生成 IFF 记录的回退路径。

这句话只适用于 IFF 编码分支。直接 shadow 分支已经证明可以携带普通
`(domain-relative raw offset, raw value)`；它的问题不是地址无法表示，而是标准入口仍缺 JSON、
写入器要求进程内 `SecurityUnlockLevel > 3`，设备 PLM/`disable_sw_override` 未知。
写入尾声的 RM 状态重载机制已经找到，但这是一条重型、尚未在隔离环境验证的
自动重初始化路径，不能等同于安全的桌面运行时接口。

目标名 `opt_l2slice_fbp0_disable`、模板 `opt_l2slice_fbp` 和打印名
`OPT_L2SLICE_FBP%u_DIS` 属于 raw OPT/shadow floorsweep 描述；可持久复核的
direct-shadow RegHal read ID 是 `0x1087c000`、实例范围 0..7，八个 relative
rows 是 `0x34e0 + 4*FBP`；fixed-selector instance0 fallback 展开为
`0x8234e0 + 4*FBP`，runtime resolver 也可能改取 PTOP record 的 base。
`0x10880000` 则在另一条通用 repair/tag-metadata
路径中出现，不能在没有独立 alias 说明时拿来替代 direct-shadow ID。没有发现
编译进程序的 L2 IFF 映射引用。

程序中另有名为 `GB20X fuse tag maps` 的表，最初看起来可能是缺失地址簿。
逐条还原 GB202 初始化后确认，它是一个 50 项的普通拓扑字典：每项只有
“熔丝名 + 一组人类可读单元标签”。例如
`OPT_L2SLICE_FBP0_DISABLE` 对应恰好 8 个
`f0fbpltc{0,1}slice{0..3}` 字符串。单项结构为 32-byte 字符串加 24-byte
字符串 vector，没有任何 chain、offset、numeric-bit 坐标或已证明的 flatten
顺序。因此它只能把一个 FBP 的 L2 floorsweep 名称关联到八个候选人类可读
标签；当前不能用 `0x12` 判定具体哪两个标签被关闭，也不能生成 fuseless/IFF 行。

## 为什么不能从已知寄存器猜 IFF 映射

我们知道的 `0x8234e0 + 4*FBP` 是 raw OPT/shadow view。IFF 映射需要的是
内部 `chainId/blockIndex/blockOffset/lsbIndex/msbIndex`。二者不属于同一坐标
系，程序中也没有公开换算函数。

猜错 IFF 记录的风险不只是不生效：格式和 CRC 即使完全正确，错误的
`chainId/offset` 仍会修改另一项熔丝影子，或令下一次初始化失败。因此在缺少
映射时不试写。

## 安全的离线工具

新增 `gb202_iff_offline.py`，它只处理传入的数字/JSON 文件，不打开 GPU、
`/dev`、BAR、驱动、固件或 MODS。当前功能为：

- `decode-row`：拆解 32-bit fuseless 记录；
- `encode-row`：按已验证布局装一条分析用记录；
- `crc`：计算已验证的 IFF CRC-16；
- `map-fuse`：将来获得外部 JSON 后，把一个逻辑值展开成 chain 的 11-bit 块；
- `plan-l2`：按调用者提供或示例假设的低 8-bit mask 计算条件性 raw-shadow
  候选和 accounting 容量；默认/示例 `0x12` 不是本卡当前值的独立验证；
- `self-test`（仅离线 parser/encoder）：用内部测试向量检查记录布局和 CRC，
  不验证本卡 mask、容量或硬件行为。

它刻意不含硬件写入口，输出也不是可直接写卡的补丁。内置测试已通过；
`0xf800001f` 会正确解码为空标记 `chainId=0x3ff`。

另有 `gb202_reghal_offline.py` 用于查询 MODS 内置的 GB202 普通寄存器映射。
它解决了 RegHal ID 到 relative row 及 fixed-selector fallback BAR0 的静态核名
问题；输出字段现明确标为 `fixed_selector_bar0`，不会冒充本卡 runtime
DeviceInfo2 base。它不能把 BAR0 地址转换成
fuseless IFF 的 `chainId/offset/bit`，两张表不可互相替代。当前版本使用分块
扫描并已在 128 MiB virtual-memory limit 下跑完固定样本 self-test，避免旧入口
一次性读入整份 MODS 的资源风险。

新增 `gb202_fjson_offline.py`，把刚恢复的 `FuseJsonParser2` 外层 schema 固化为
只读校验器：

- `validate <file>` 检查 `header/options/Chip_options/Map_options/Mkt_options.dies`
  以及 descriptor 必填类型，并拒绝重复 JSON key；
- `audit-l2 <file>` 核对八个大写 L2 名称是否均为 `bits=8`、`type="dis"`，且
  integer descriptor offset 是否严格等于 `0x34e0 + 4*FBP`，并另行报告
  fixed-selector fallback BAR0 `0x8234e0 + 4*FBP`；工具明确不把该值冒充
  runtime DeviceInfo2 base；
- `self-test` 使用虚构的 `DUMMY_DISABLE` 内存对象验证 schema，不生成或保存
  可交给 MODS 的 GB202 文件。

该工具没有 MODS、GPU、驱动、MMIO、reset 或写文件入口。三套离线工具的内部
软件测试已在本轮一并复跑通过；这些测试只验证 schema、布局、CRC 和
synthetic/internal vectors，不执行硬件 BIST，不验证 L2 data/tag/set/way/bank，
也不证明本卡 mask、容量模型或 disabled-unit health。

## 当前可行性判断

| 路线 | 判断 |
|---|---|
| `fbp_l2slice_enable` | 对 MODS 570.151 的静态路径分析表明它只写 SW-disable 层，不能清 raw/effective hard mask；未做本卡 live 调用 |
| 向软件配置寄存器写 0 | 此前报告值为 0，但原始输出未归档；即使为 0 也无收益 |
| 直接清当前/生效掩码 | 没有已验证写接口；预期被硬熔丝重新并入 |
| GSP/InfoROM LTS repair | generic 等量 swap 实现存在；当前有界重放证明 GB202 的 repair/marking/commit 槽为 `NV_OK` no-op stubs；当前公开 RM/有界搜索未见明确的 client-visible per-LTS repair 入口，不能支持扩容或逐 LTS 修复 |
| SW IFF / soft fuse | 格式和 CRC 已恢复；目标映射、原始行状态未知；总禁用位已定位但本卡值未读 |
| `NewFuse.SetSwFuses` 名称入口 | raw disable 降位可由编码器生成；准确 array-of-pairs 语法和名称已恢复；仍缺 GB202 JSON，且 writer 要求进程内 `SecurityUnlockLevel > 3`；这不提供 FSP admission 或设备 PLM 权限 |
| 低层 raw shadow plan | domain-relative L2 key 可离线精确列出，物理 `0x8234e0..fc` family 有独立证据；class `0x10` vector 为空时 resolver 才用 instance-0 fixed fallback `0x820000`，非空时必须存在 exact instance 0，否则 MODS 进入越界 no-match 路径，安全离线模型应拒绝。本卡 row 未捕获，但公开 610 的 GB202 primary FUSE getter 同样固定返回 `0x820000`，正常 row 强预期一致。候选值依赖未归档的 `8 x 0x12` 报告。host 顺序已闭合到“尝试置 latch -> raw write/readback -> 依 coupling 选择 reset/reinit”；可见软件中未找到 A-derived effective writer，采纳点收敛到 hardware/FSP-GFW/hidden replay。QCAP `0x13` presence/status 时序已知，但 task 2 对 `d0/dc` 的 effect 仍只是推断，`f8` 又是无同等级旁证的独立缺口；三只 PLM 的实际值/lifetime、传播/恢复和物理健康均未闭合，不实现实机 writer |
| 纯离线编码/解码器 | 已完成并通过内置测试；不会访问 GPU |
| 自造 IFF 行并试写 | 当前不安全，不执行 |

### 当前 610 没有逐 LTS 的受支持隔离或完整性自检入口

`610.43.03` 开源 RM 的 GET controls 可以返回总 L2 容量、active
FBP/LTC/LTS count，以及每 FBP 当前生效的 LTC/LTS enable mask：

- `NV2080_CTRL_CMD_FB_GET_INFO_V2`；
- `NV2080_CTRL_CMD_FB_GET_LTC_INFO_FOR_FBP`；
- `NV2080_CTRL_CMD_FB_GET_FS_INFO` 的 `LTS_MASK` 查询。

旧 `GET_LTC_INFO_FOR_FBP` 还有一处需要按执行环境解释：CPU-RM 的 non-VF
**本地** HAL binding 确实是 `NV_ERR_NOT_SUPPORTED` stub，但两个 control 都带
`ROUTE_TO_PHYSICAL`。正常 GSP-offload 下，CPU-RM prologue 会在本地 handler
之前 RPC 到物理 GSP；610.43.03 与 610.74 GSP 都有真实旧/new handler。非 MIG
type-3 最终经 GB202 FB `+0x9c0` 读取 `0x822900 + 4*FBP`，反相并按动态位宽
裁成 active enable mask。因此这里的支持结论限于 GSP-offload physical path；
不能因 host-local stub 说 5090 必然不支持，也不能把返回值说成 raw fuse。
完整路由与两版本交叉检查见 `parallel/gb202_getfsinfo_support.md`。

该 type-3 GSP 分支本身是读取路径，但 `GET_FS_INFO` export flags 不含
`API_LOCK_READONLY`。所以它是未来较可信的 effective-topology baseline 候选，
仍不能仅凭命令名或 flag 宣称在任意 live 状态“绝对零风险”；当前没有对承担
桌面的 5090 发出该 control。

最小客户端路径也已从公开 610 RM ioctl/object 链静态闭合：

```text
open /dev/nvidiactl
  -> ordinary userspace RM client
  -> NV01_DEVICE_0
  -> NV20_SUBDEVICE_0
  -> GET_FS_INFO(FBP_MASK)
  -> GET_FS_INFO(LTS_MASK, enabled FBP indices)
```

用户态即使在 alloc 参数里写 `NV01_ROOT`，Unix ioctl 入口也会把它强制降为
`NV01_ROOT_CLIENT`，所以这不是提权或 MODS security-level 绕过。后续 alloc 与
control 都走 ctl fd；旧 `gb202_fs_probe.c` 中的 `/dev/nvidia0` open 和
`NV_ESC_REGISTER_FD` 没有被这条查询链消费，应删除而不是复用。尤其实际设备
节点首次 open 在 GPU 尚未初始化时可以触发 `nv_start_device()`，只开 ctl 节点
能避免主动走这条初始化入口。

该 GET 的正常可见路径没有 reset 或 topology write，但它带
`ROUTE_TO_PHYSICAL` 且没有 `NO_GPUS_ACCESS`：device/subdevice 建销会创建每进程
RM/GSP 对象，control 会拿锁、RPC，并可能唤醒低功耗设备。因此准确分类是
“查询内容只读、风险明显低于寄存器探针”，不是“驱动状态零变化”。未来若实现，
还必须锁定与 loaded RM 匹配的 ABI，断言 outer 参数大小 `0xf08`，分别检查
ioctl、outer RM status 和每个 query status，并用非零 sentinel 防止把未写输出
误当真值；失败时不得 fallback 到 card-node open、模块操作或 reset。完整审计见
`parallel/getfs_client_path.md`。本轮只完成设计审计，没有写出或运行 live probe。

这些接口只描述**最终有效拓扑**，没有字段区分 SKU mask、物理缺陷、repair
记录或它们的合并结果，也不报告 disabled 单元健康。完整源码/归档审计见
`parallel/l2_safety_observe.md`；其中还确认：

- 本卡保存状态的 MIG、ECC/InfoROM 和 row-remap telemetry 为 N/A；N/A 不能
  当作零错误或零 repair record；
- CUDA persisting/access-policy 只是共享缓存优先级提示，没有 physical LTS
  selector；48 个 PerfWorks LTS rollup 也没有稳定的绝对 instance identity；
- `RMCFG_FEATURE_LTS_REPAIR=1` 只证明通用功能族被编入，不能证明 GB202
  挂接了非空 repair hook 或导出 client control；
- `NV2080_CTRL_CMD_ECC_GET_REPAIR_STATUS` 只报告 TPC/channel pending，
  没有 LTS 字段；
- 共享头虽声明逐 LTC/slice ECC injection，但当前 generated `DiagApi` 方法表
  从 `0x208f050e` 跳到 `0x208f0510`，没有 `0x208f050f` handler。即使别的
  产品支持，主动故障注入也不是只读健康测试，更不是覆盖所有 cache
  data/tag/set/way/bank 的 BIST。

MODS 自带测试也没有补上这个缺口。旧 `CudaL2Mats` wrapper 确实按
`(FBP, slice)` 创建 perfmon 并读取 hit/miss，但它自己的 support callback 会拒绝
所有没有 uGPU 的 GA10x+ 设备；其现代 `CudaL2Noc` 分支还因 GA100+ perfmon
latch 问题明确禁用这些 experiment。较新的 test 351 `NewCudaL2Mats` 则明确为
Blackwell 启用 `TriadTest`，并把 allocation 限到当前报告的 L2 容量，因而可算
未来的 aggregate stress 候选；但它没有 FBP/LTS selector 或 per-slice perfmon，
不能认证某个新启用物理单元。详见 `parallel/mods_l2_test_boundary.md`；本轮没有
运行 MODS 或任何测试。

独立 native/JS 交叉检查又把 test 351 的能力说得更准确：`NewCudaL2Mats`
不是独立 native L2 引擎，而是 JS 用 `CUDA_CHANGE_RUN_NAME` 调普通
`NewCudaMatsTest.Run()`，再设置 L2-sized working set、随机数据和 Blackwell
`TriadTest`。native 可见门允许 SM 8.9+，包级 fatbin 含 SM120 资源；这支持
“设计上覆盖 Blackwell”，不证明零售 GB202 必然接纳。它能报告数据 miscompare、
错误结果缓冲异常及可选 bit/burst/SMID 信息，但 SMID 只是遇到错误的执行单元，
不是失败 LTS 身份；未见 L2 ECC、tag-array 或逐 LTS 证书。详见
`parallel/newcudal2mats_native.md`。

当前材料也不能确定：若只出现异步 L2 ECC/Xid、却没有 CUDA data miscompare，
test 351 是否会把该异步事件并入自己的返回码。因此它能发现一部分数据路径
错误，不等于覆盖所有新单元故障模式。

因此，即使将来有另行授权的拓扑改变，高层信号最多证明“RM/PerfWorks reported
容量/rollup 数增加、
有流量经过、未观察到聚合错误”；它不能形成逐 slice 健康证书，也不能保证
某个测试 allocation 只经过新启用单元。

## 运行时、易失性测试的隔离构想

用户提出的优先测试模型已保留：主机桌面和显示完全由核显承担，5090 不作为
DRM/display master；未来若另行获得授权和恢复证据，只对 5090 做一次性的
software-shadow 改动，每轮至多选择报告中的一个 raw mask bit（accounting model
下理论 +2 MiB），随后用 allocation-scoped LTS placement 做极小流量观察。
一旦异常只能立即停止进一步操作；device reset、resense 或冷断电是否能清除
latch/partial raw state 目前都没有被证明，不能预先称为恢复方案，也绝不让
shadow 进入 VBIOS、InfoROM、IFF 或实体熔丝。

该模型能显著降低“显示卡挂住等于整机失去桌面”的风险，但有两个明确边界：

- 现有 `l2_slice_re` 只能把**自己的 CUDA allocation** 放到 allocation-relative
  LTS 类，不能把 compositor、scanout、GSP 或驱动内部 allocation 钉到一两个
  物理 slice；CUDA persisting set-aside 也是共享的保留优先级，不是物理隔离。
- 当前放置器按已观测的 48 个相对 LTS rollup 类严格 fail-closed，但公开证据
  不足以预测清一个 raw mask bit 后类别数必然从 48 变成 49；它可能不变、变成
  其他基数，或只改变另一观察层。未来校准必须动态发现结构并 fail-closed；
  即使观察到新增类，也没有绝对 instance 标签，不能证明它就是目标 mask bit。

因此更实际的保护不是“把桌面挤进健康 slice”，而是让 5090 完全脱离桌面，
最好再直通给隔离 VM；宿主和远程控制都留在核显。这个构想只用于将来的明确
批准阶段，当前不改变显示路由、不运行 MODS、不触发 GPU reset。

用户此前提到的本地恢复脚本已经定位并只读审计：
`/home/user/hw_configs/nvidia-reset.sh` 会杀掉所有 NVIDIA device holder、卸载
四个 NVIDIA 模块、对上游桥执行 SBR、PCI rescan，再重载模块。它原本用于、且
可合理期待用于 dirty GSP/RM 恢复，但并非对所有 dirty state 的恢复保证。脚本
还把 GPU BDF 固定为 `0000:01:00.0`、上游桥固定为 `00:01.1`；未来任何隔离环境
使用前都必须重新确认地址及桥下游没有会被连带 reset 的其他 function/device。
源码没有保存旧 raw 值、clear latch、fuse resense 或
post-reset L2 拓扑比较；SBR 对 shadow 的保持域又未知。因此它**不是**部分
direct-shadow 写入的已证明 rollback，而且在桌面仍由 5090 承担时绝不能运行。
交叉检查还确认 bridge-control bit `0x40` 就是 PCI SBR，MODS 也明确把
`HotReset` 描述为 secondary-bus reset；所以它属于 hot/SBR 类，不是
boot/fuse/base。这里的 reset mechanism 同类不代表脚本与 MODS 的 RM/FSP
编排等价。公开 GB202 SBR HAL 的最终 body 同样只切桥位、等待并轮询配置空间，
没有四组 L2 shadow/status 状态的处理；这进一步说明 SBR 名称本身不提供
rollback 合同。脚本尾声也只以 `lspci`/`nvidia-smi` 检查设备和 RM 回来，不验证 L2
topology。完整源审计见 `parallel/local_recovery_script_scope.md` 与
`parallel/sbr_shadow_scope.md`、`parallel/shadow_reset_domains.md`；本轮没有
执行该脚本。

## 2026-07-22 runtime addendum：直接 FSP/MNOC 查询与受限 no-op 写

在 5090 已隔离到 VFIO VM 的状态下，已用自写最小工具直接通过 FSP MNOC mailbox
完成三类验证；未运行 MODS，未写 VBIOS/InfoROM/OTP/fuse，未写 L2/FS/PLM MMIO，
未触发 GPU reset。

1. **PRC read 成功。** task/read-object 读取 knob `0x1d` 返回
   `PRC_READ_OK knob=0x001d value=0x0001`。相邻 read-only 扫描中
   `0x1b..0x24` 也均读回 `0x0001`，而公开 GH100 PPCIE precedent 的 `0x2d`
   在本卡返回 `0x1e3 = PRC_ERROR_INVALID_KNOB_ID`。完整记录见
   `vm_mods_lab/fsp_prc_read_direct_result_20260722.md`。
2. **PRC write 入口可达，但受限 no-op 被 FSP 拒绝。** 对
   `0x1d=0x1` 做“先读确认 current 已等于 requested，再发送等值 write”的
   allowlisted no-op 请求，FSP 返回 `0x1e4 =
   PRC_ERROR_PERSISTENCE_NOT_SUPPORTED`。写后 PRC read 仍成功，BAR0
   floorsweep/L2 状态未变，宿主机无相关 Xid/vfio/AER 报错。完整记录见
   `vm_mods_lab/fsp_prc_write_noop_result_20260722.md`。
3. **CAPS query 证明 PRC family 当前 active。** 直接
   `NVDM_TYPE_CAPS_QUERY` 查询 `subMessageId=0x13` 返回
   `{NVDM type 0x13, Version 0x1}`；`0xff` 全量查询同样列出 `0x13/version 1`。
   因此 no-op write 的 `0x1e4` 不能解释成“PRC family 不存在”或“mailbox/port
   不通”，而是具体 PRC object-write 的 policy/options/persistence/lifecycle
   拒绝。caps response 只有 `{NvdmType, Version}` 记录，没有 token、nonce、
   session handle、lease 或 security level 字段可供后续 packet 携带。完整记录见
   `vm_mods_lab/fsp_caps_query_result_20260722.md`。

运行后快照仍为：

```text
0x00820040 latch_request        = 0x00000000
0x008200d0 plm_floorsweep_0     = 0xfffffb8f
0x008200dc plm_l2_raw_sw        = 0xfffffb8f
0x008200f8 plm_latch            = 0xfffffb8f
0x008212ac disable_sw_override  = 0x00000001

raw_fbp0..7       = 0x00000012
effective_fbp0..7 = 0x00000012
software_fbp0..7  = 0x00000000
```

当前收敛结论：直接 mailbox transport、PRC read-object、caps-query 都已经闭合；
PRC write-object 也能到达 FSP，但零售/当前状态会在对象策略层拒绝这条
`0x1d` 等值写。后续不能再把重点放在“找端口/找地址”，而应放在 FSP 内部对
`0x1d` 的合法 persistence/options/lifecycle 条件、以及 task-2 consumer 是否会
在特定时序中读取同一状态。未知 tail/options 不能盲试，因为错误名已经落到
persistence 域。

## 安全的下一步

1. 权限研究已收敛到不可见 consumer：继续只从新出现的可信 FSP/GFW artifact
   查明 task 2 是否实际改变 `0x8200d0/0x8200dc`、写成什么值、何时收回，以及
   是否另行处理独立 latch PLM `0x8200f8`。QCAP presence、command status 和
   host 无 token/restore handle/显式 close 都不能替代这些 device-state 证据。
   `UseTestValues`
   已排除，HULK 是另一条签名授权路线，不能互相代替。PLM 静态门形已经闭合为
   L0/source0 的 `bit0 & bit4 & (!bit10|bit12) & (!bit11|bit12)`；`dc/f8`
   field setter 虽存在，当前 GB202 host 没有已绑定的 direct lowering caller，
   且两只 PLM 无 self-access metadata。后续不要把“host audit 默认 pass”误当成
   硬件可写。
2. reset/coupling 的 host 链已闭合为“继承既有 coupling，选择
   hot/boot/fuse/base”；接下来只追各 reset domain 对 latch/raw/effective 的
   保持/消费规则。现有 OpenRM/MODS/GSP 小窗口中没有 GB202 四寄存器 reset-domain
   表；retain、reset-edge sample、hidden-state rebuild 三种模型目前不可区分，
   以后只在出现新的可信 FSP/GFW/硅级资料时重开这条线。GSP-offload 的
   `GET_FS_INFO/LTS_MASK` 已静态证明 physical handler 能另行读取
   current/effective 拓扑，但 MODS success tail 不自动调用，接口也不报告 raw、
   provenance 或健康；本轮未做 live control。其无需 MODS 的 ctl-only 最小
   client 链已静态闭合，但仍有 per-client RM/GSP bookkeeping、RPC/lock 和可能
   wake，故暂时只保留为未来 baseline 设计，不在桌面卡上运行。显式 resense
   会先尝试 clear latch，不能充当 direct-shadow success 的无损验证或 rollback。
   `disable_sw_override` 的来源/生命周期继续仅做静态审计。raw→effective 的
   可见软件边界也已闭合到“reset 前 host 写/回读 raw A，init 后 GSP 读
   effective B”；固定 GSP 中没有找到 A-derived B copier/recompute。后续只有在
   出现可信 FSP/GFW 或硅级资料时，才继续区分 hardware rollup、firmware rebuild
   与隐藏 replay，不能把当前有限负结果升级成自动传播保证。
   公开 boot success 又只检查 FSP/GSP 存活和 engine `StateLoad`；`INIT_DONE`
   与 static config 都不携带 LTS topology，所以它们也不是 adoption proof。
   预测实际 reset 类型的剩余静态缺口是三个位的 power-on/firmware 来源，以及
   base coupling 是否会经硬件/reset sequencer/FSP/GFW 隐式级联到公开 getter
   直接读取的 fuse/boot 位；可见 GSP setter/dispatcher 的软件镜像已经排除。
   `GpuSubdevice+0x6c0` 也已闭合为 MIG/SMC partition 专用 `SmcRegHal`，普通未
   分区 GB202 使用嵌入普通 RegHal，coupling 的 PMC-relative 访问强支持不被该
   override 改路。getter 的 `isVirtual` guard、两个直接输入、优先级和 GB202
   `+0x668` 绑定本身均已不再是未知。
3. 本地包内的 `gb202_f.json` 搜索已经穷尽到所有可识别 archive member；若未来
   获得可信外部原始文件，只用离线 validator 独立核对八个大写 L2 descriptor
   的 `type/width/offset`。validator 报出的 `0x8234e0..fc` 只标记 fixed-selector
   fallback，不能代替本卡 PTOP DeviceInfo2 runtime base。不要用自造
   parser-compatible JSON 代替 authentic
   FuseSpec。IFF `fuselessFuse` chain 坐标仍是另一项独立缺口。
4. 把 L2 OPT 的 `0x8200dc` PLM、latch 的 `0x8200f8` PLM、
   `disable_sw_override` 读取侧的 `0x8200fc` PLM、`0x8212ac.bit0` 和
   `0x820040` override latch 的只读判定继续缩小到已有驱动允许的接口；在没有
   真正受支持的 getter 前，不增加裸 BAR/MMIO 探针。`GET_FS_INFO/LTS_MASK`
   只能代替 effective-mask baseline，不能读取这些 permission/latch/raw 位；也
   不应为取得 baseline 打开 `/dev/nvidia0` 或自动 fallback 到 reset/init。
   DeviceInfo2 class `0x10` 的 instance0 base 同样只接受未来出现的受支持 getter、
   保存日志或可信静态资料，不为它新增裸 PTOP/MMIO 读取；若 class 非空却没有
   instance0，必须离线判为拓扑不一致并拒绝，不能模仿 MODS 的越界 no-match 路径。
5. 若以后拿到 IFF 映射，仍需用纯离线工具验证 chain、bit、CRC 与 1→0 约束；
   direct shadow 与 IFF 两条路线分别评估，不能互相代替恢复证据。
6. 最终任何硬件研究至多先选择报告中的一个 raw mask bit；“理论 +2 MiB”只是
   accounting 标签，不能称为已识别的单个 2-MiB 物理单元。开始前需要独立、
   可验证的恢复语义、隔离系统和用户明确批准。自动 RM state reload 也算 reset
   级副作用；当前阶段
   不运行 MODS、不加载其驱动、不重载/reset GPU、不写 MMIO、固件或 VBIOS。

## 2026-07-22 runtime addendum: task2-zero opens d0/dc, not f8/latch

详见独立记录：
`vm_mods_lab/fsp_task2_zero_result_20260722.md`。

本轮在 VFIO 隔离 VM 内做了一个范围受限的 runtime probe：

```text
sudo timeout 25s /mnt/prc/gb202_fs.static \
  --task2-zero \
  --i-accept-task2-zero \
  --port 1 \
  --timeout-ms 10000
```

发送的 FSP body 是：

```text
02 01 00 00 00 00 00 00
```

即 task `2`、subobject `1`、六字节零 payload。FSP 返回：

```text
TASK2_ZERO_OK
error_code=0x00000000
```

关键硬件可见状态变化：

| Register | Before | After |
|---|---:|---:|
| `0x8200d0` floorsweep PLM | `0xfffffb8f` | `0xfffffbff` |
| `0x8200dc` L2 raw/software PLM | `0xfffffb8f` | `0xfffffbff` |
| `0x8200f8` latch PLM | `0xfffffb8f` | `0xfffffb8f` |
| `0x820040` latch request | `0x00000000` | `0x00000000` |
| raw/effective FBP0..7 | `0x00000012` | `0x00000012` |

随后只做了一次 latch-only 写入：

```text
BAR0[0x00820040] = 0x00000001
```

读回仍是：

```text
0x00820040 = 0x00000000
0x008200f8 = 0xfffffb8f
raw/effective FBP0..7 = 0x00000012
```

随后又做了一次更小的 f8-only 写/读/恢复尝试；它要求 `d0/dc` 已经是
`0xfffffbff`，且 latch/raw/effective/software baseline 全部匹配，不写 latch，
不写 raw L2：

```text
BAR0[0x008200f8] = 0xfffffbff
readback 0x008200f8 = 0xfffffb8f
BAR0[0x008200f8] = 0xfffffb8f
readback 0x008200f8 = 0xfffffb8f
```

也就是说，task2-zero 打开 `d0/dc` 以后，普通 host BAR0 写仍不能让 `f8`
变成 `...bff`。后续 FSP status-only 正常，raw/effective/software L2 mask 没变，
guest dmesg tail 未见新增 Xid/AER/fatal。

同样的 open-then-restore 探针对 `0x8200e0` 和 `0x8200f4` 也失败：

```text
BAR0[0x008200e0] = 0x00800bff
readback 0x008200e0 = 0x00800b8f

BAR0[0x008200f4] = 0x00800bff
readback 0x008200f4 = 0x00800b8f
```

因此旧 GV100 路径里出现过的 `f4/f8` sibling 思路，在当前零售 GB202 上也不是
普通 host BAR0 self-write 可走的捷径。

最后做了一次已经带恢复逻辑的 FBP0 raw-shadow 单 bit clear-then-restore 探针。
当时 `0x8200dc` 已是 `0xfffffbff`，但 `0x8200f8` 仍是 `0xfffffb8f`：

```text
BAR0[0x00820040] = 0x00000001
BAR0[0x008234e0] = 0x00000010
after_clear raw_fbp0 = 0x00000012

BAR0[0x00820040] = 0x00000001
BAR0[0x008234e0] = 0x00000012
after_restore raw_fbp0 = 0x00000012
```

所以即使 `dc` 已打开，普通 host BAR0 raw-shadow 写也没有可见生效；失败发生在
raw shadow 读回之前，而不是只卡在 raw→effective 采用阶段。

HULK 样本也做了离线复核，详见
`parallel/hulk_sample_cert_inventory_20260722.md`。MODS 包内 8 个 JS 包装文件
只有 6 份唯一 Figueroa payload，明文 device id 分别为
`0x2685/0x2816/0x2817/0x2929/0x3414/0x3415`，没有本卡 `0x2b85`；其中确实存在
12-byte `address/and_mask/or_value` 风格 register-RMW 记录，但没有
`0x8200f8`、`0x8200dc`、`0x820040` 或 `0x8234e0`。因此本地 MODS 包不包含
可直接用于 GB202/f8 的 HULK 动作；HULK 只剩“若未来拿到合法 GB202/设备绑定证书”
这种理论路线。只读 CAPS 查询同时确认当前 FSP 报告 `0x11` HULK 与 `0x13` PRC
均为 version 1；这只证明协议族存在，不证明有本卡 f8 授权。

当前更新后的结论：

- task2/subobject1/zero-payload 对零售 GB202 FSP 是有效交易；
- 它确实打开了可见的 `0x8200d0` 和 `0x8200dc`；
- 它没有打开独立 latch PLM `0x8200f8`；
- 直接写 `0x8200f8 = 0xfffffbff` 也读不回来，说明最简单的 self-write 路径
  已闭合为失败；
- 直接写 `0x8200e0/0x8200f4` 的 nibble-open 值也读不回来；
- 直接写 FBP0 raw shadow `0x8234e0 = 0x10` 也读不回来；
- 包内 HULK 样本不是 GB202/2b85，也不含 f8/latch/L2 目标地址；
- latch request 仍不吃，raw/effective L2 mask 仍没变；
- 因此下一步重点不再是“task2 能不能到达”，而是找 `0x8200f8`
  的合法开启/消费路径，或确认是否存在另外的 FSP/HULK/task4 交易负责 latch。

本轮只执行了一次带立即恢复逻辑的 FBP0 raw-shadow clear-then-restore 探针，
且 raw 读回未变化；未写 VBIOS/固件/flash，也未对宿主机 GPU 做持久修改。

## 2026-07-22 MODS FSP sender 调用点复核

静态枚举 `mods_audit/static/extracted_inner/mods` 里进入公共 FSP sender
`0x185e890` 的 18 个直接调用点后，明确出现的 task 只有
`1/2/3/4/8/13`。没有发现另一个明显的隐藏高编号 FSP task 直接负责
`0x8200f8` 或 L2 raw/effective mask。完整表见
`parallel/mods_fsp_sender_callsite_inventory_20260722.md`。

其中已能排低优先级的分支包括：一个 task3 callsite 附近日志是
`Using the GH100 dramclk devinit WAR with COEFF register = 0x%08x`；task4
附近日志是 `Unsupported FSP reset coupling option: %s`，更符合已知
reset-coupling 路径；特殊 task13/sub2 helper 附近是
`SMSKED_MESSAGE/SMHOST_MESSAGE` 和 `UnlockHost2Jtag` 一类 bring-up/调试线索。

新增的重要发现是 `task13/subobject2` 里存在两条不同路径。通用 PRC knob 写
路径位于 `0x185f299`：它发送一次 `task=13, subobject=2`，然后调用 PRC 读回
helper 校验 old/new knob value。这与本地 `gb202_fsp_prc_read.c` 的保守
PRC write-noop 更接近。

另一个特殊 helper 位于 `0x1258756/0x12587a8`。它先发送一次
`task=13, subobject=2`，成功后把同一个 payload 的第一个字节从 `0x00` 改成
`0x06`，再发送第二次同 task/subobject。该 helper 附近有 `SMSKED_MESSAGE`
字符串线索，暂时不能泛化成所有 PRC knob 写；但它说明 MODS 中确实存在
task13/sub2 的二阶段时序变体。

同时，`task8/subobject1` 的上下文字符串明确是 FSP fusing mode：

```text
Running FSP fusing mode for use case:%s(%u)!
Skipping fusing mode use case: %s(%u) as the fuses are already blown!
Fsp fusing mode disabled! Fuses for usecase 0x%x can't be blown.
```

所以 task8 目前应视为潜在破坏性/烧录相关入口，而不是安全的运行时 L2 解锁
候选。下一步低风险方向是继续离线命名这个特殊二阶段 task13/sub2 helper 的
payload 语义；不应直接尝试 task8 或永久性 fusing path。

## 2026-07-22 `0x8200f8` 写后可见状态

在隔离 VFIO VM 中又做了一次已验证边界内的 `f8` open-then-restore 探针，详见
`vm_mods_lab/f8_write_status_probe_20260722.md`。这次额外记录了写前/写后的 FSP
MNOC mailbox status 和 guest `dmesg` tail。

结果：

```text
phase open f8: BAR0[0x008200f8] = 0xfffffbff
phase open readback f8: BAR0[0x008200f8] = 0xfffffb8f
phase restore f8: BAR0[0x008200f8] = 0xfffffb8f
phase restore readback f8: BAR0[0x008200f8] = 0xfffffb8f
```

FSP mailbox 前后均保持：

```text
send_info 0x008f1f10 = 0x80000000 ... err=0
recv_info 0x008f1f90 = 0x85000009 ... ready=1 credit=1 err=0
```

guest `dmesg` 尾部没有新增 Xid、PCIe AER、vfio fatal、FSP/GSP error 或 kernel
fault。相关 PLM/latch/raw/effective/software L2 mask 全部保持 baseline。

因此，在当前 host 可见面上，直接写 `0x8200f8` 更像静默拒绝/丢弃，而不是返回
一个可直接利用的错误码。仍不能排除 firmware-private counter 或内部日志，但
目前能读到的 BAR0/FSP mailbox/kernel-log 表面没有给出有用返回。

后续只读 scratch 对比已准备但本轮未执行：公开 610 headers 给出 FSP scratch
group2 `0x8f0320..0x8f032c`、FSP boot-complete scratch `0xad00bc`、GSP mailbox
`0x110040/0x110044`、PBUS GSP-FMC error scratch `0x14dc`。直接 `od` 读
`resource0` 会 EIO，必须用 mmap 工具；新版工具和 ISO 已在宿主构建，但 guest
当前 `/mnt/prc` 是旧只读 ISO，且没有编译器/网络/可访问 monitor 热换路径。

## 2026-07-22 HULK / VBIOS / FSP_RUN 授权边界复核

按“合法开启 `0x8200f8`”路线做了一轮纯静态复核，详见
`parallel/hulk_vbios_policy_boundary_20260722.md`。四份本地 GB202 ROM/NVFW
样本中没有 `0x8200f8`、`0x8200dc`、`0x8200d0`、`0x820040`、
`0x8234e0` 的明文/literal 常量，也没有 `HULK`、`PLM`、`PRIV`、`fuse`
明文字串；只有 `FSP_RUN` tag。GeForce 与 RTX PRO 6000 的 `FSP_RUN`
envelope 确有差异，但该对象已有 SHA-384 record 和上一层 digest 约束，当前
不能把它当成可手改配置表。

当前 GSP raw image 中存在 `VBIOS_VERIFY_HULK_*`、`CERT_HULK_*`、
`CERT_T7_REG_OVERRIDE_*`、`PRI_TRANSACTION_ERROR` 等 FWSECLIC/HULK 错误名，
也存在 `RmActivateHulk`、`RMHulkCertSize`、`RMHulkCert` 配置入口。对
`VBIOS_VERIFY_HULK_*` 的交叉引用只落到连续错误码 formatter 窗口，证明的是
错误名存在，不证明当前 GB202 从 VBIOS 读取并接受某个 HULK KA。`RMHulkCert*`
路径则是真实的 HULK 输入面，会把证书/激活请求送入 NVDM type `0x11`/FSP
路线；但公开 host 源码没有 payload schema、签名验证、range whitelist 或
PLM lowering/restore 规则。

因此当前更准确的判断是：若 `0x8200f8` 能通过合法路线打开，最可能需要
NVIDIA 签过且适用于本设备/本生命周期的 HULK 授权对象，或需要可被本卡
secure-loader 接受的 VBIOS/FSP_RUN 授权材料。本地还没有这两者。这个结论不
排除特定官方 BIOS/证书/实验室生命周期能做到，但排除了“现有 VBIOS 里有明文
开关”与“只差普通 BAR0 寄存器序列”这两个简单模型。

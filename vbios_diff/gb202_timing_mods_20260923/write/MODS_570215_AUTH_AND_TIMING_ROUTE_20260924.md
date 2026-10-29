# MODS 权限分层与 GB202 GDDR7 时序写路径（离线核查，2026-09-24）

**范围：**以下研究只读本地已有 MODS 570.215/570.151 ELF、解码脚本、GSP/PMU 研究和已保存的隔离 VM 日志。未新增任何 GPU 寄存器写、凭据、网络授权操作或驱动/VM 切换。运行时日志见 `GB202_MODS_NATIVE_RW_TRIAL_20260924.md` 和 `../read/GB202_MODS_18000MHZ_LIVE_20260924.md`。

## 实机给出的两种不同结果

- VM 中 MODS 570.215 原生 `rw` 请求把广播 `0x9a0294` 或 FBPA0 `0x900294` 的 CONFIG1 从 `0x796805a3` (CL35) 写成 `0x796805a4` (CL36)，**均立即读回旧值**；之后九组 CONFIG0..5 仍是原值。这证明这两种运行时 raw 写**未产生可见改变**，不证明具体是授权、硬件写保护、额外锁存协议还是 RM 校验阻止。
- 同版 MODS 的原生 `dramclk(18000)` 报实际 `17999 MHz`，八 FBPA+广播 **全部切换**到 CONFIG1 `0x797885a5` (CL37)，整组六字与旧 E1 ROM 的 timing entry15 对应；频率退回请求的“实际/有效”读数不一致后，QMP 复位并在全新客体核实回到 `14001 MHz/CL35`。因此 **MODS/固件确有可用的受控时序档位切换路径**；不意味着随意在线写 CONFIG1 的路径也开放。

## 三类不同的“权限”

1. **宿主操作系统权限：**客体中 `sudo` 运行 MODS、加载 `mods.ko` 并访问 `/dev/mods`；这只解决 Linux 进程打开诊断驱动和设备的条件。
2. **MODS 进程本地策略（已在实际 570.215 ELF 重新核对）：**目标文件 SHA256 `6645d5de…82e5856`；启动解析器 VA `0xbd6900` 查 `-b`，无记录时 `0xbd6d70` 将本地输入归为 `1`，`0xbd6d8b` 调 setter。setter `0xd81d70` 先把进程 dword `0x1875f474` 设为 `1`，若 `-no_net` 或 NVIDIA 证书网络检测 `0x8c0c1e0` 不成功则保留输入；成功时输入1→4、输入3→5。getter `0xd81e00` 从该 dword 取值，`0xd81e20` 提供 `>3` 判定；ELF 存在 `SecurityUnlockLevel`/`SUL_NONE`/`SUL_NVIDIA_NETWORK` 字符串。这证明**同版确有进程级授权**，不同于 570.151 旧版 VA。客体无网络且启动命令没有 `-b`。之后在**全新客体、已初始化 GPU 的 MODS 570.215 交互进程**执行只读 `Print("PI_AUTH_LEVEL=" + SecurityUnlockLevel)`，实测 **level=1**，同时 `Gpu.IsInitialized=true`。这验证了该次进程的低等级，不代表 CONFIG1 写操作一定检查此值。启动信息显示 PCI DID `0x2b85`、Device/Chip Name `GB202`、`BAR0 Access=DirectMap`、`GSP-RM=Disabled`；它是该诊断 MODS session 的设备报告，不能单独判定每次 RegWr32 实际走哪条 backend。客体 `mods.jse` SHA256 `a62bf220...e3976026f` 与本地提取包逐字对应。旧版 `parallel/tmux_mods_permissions.md` 的 **L2/软件熔丝** `ProgramSwFusePlan` 要求 `>3`，但尚无证据把 **GB202 CONFIG1** 写路径连到这个 host gate。
3. **设备授权与支持：**本地 `parallel/tmux_mods_permissions.md` 及 `parallel/mods_hulk_debugtoken_frontend_20260813.md` 分清 FSP/PLM、签发的 HULK 材料与主机进程等级；通过主机检查≠某个 GPU 寄存器写入获准。所引用的具体 PLM/PRC/HULK 证据针对 L2/fuse/其它特定块，**未证明 CONFIG1 需要哪种授权**，也没有当前 CONFIG1 的 PLM/返回错误记录。

**重要澄清：**此前运行 `-m 'g_CheckVbiosSecurity=false;'` 并不是提升 MODS 授权等级。`mods_audit/static/decoded/all/gpuargs.js:11815-11820` 显示该开关仅令 `ValidateVbios()` 提前返回；不得把它等同 `SecurityUnlockLevel` 或设备权限解锁。该解码 JS 来自旧 **570.151** 静态样本，不能单凭它推定 570.215 的代码。570.215 包的 `/home/user/mod570_215_static/extracted/home/570.215/mods.jse` 为加密文件（SHA256 `a62bf220ae4b5200cab80221b04e74bd99523d6b91bd0cc1e293fe3e3976026f`）；本次只读运行时查询同时得到 `g_CheckVbiosSecurity=false` 和独立的 `SecurityUnlockLevel=1`。所以此选项至少**没有把当前进程升级到4/5**。

## 原生 raw 命令的回读不能充当写入返回码

旧版原装 JS `mods_audit/static/decoded/all/mods.js:1102-1117` 的 `rw(addr,data)` 先调用 `RegWr32`，再调用 `RegRd32` 并返回 `RC.OK`；`mods.js:331-358` 的 `RegWr32` 在 GPU 已初始化时使用 `GpuSubdevice.RegWr32`；`intrutil.js:371-424` 的 `FillData` **不检查每次 `WriteFunction` 的返回值**，结束时返回 `RC.OK`。**这段磁盘明文来自 570.151；已用本次实际 570.215 VM 的只读函数内省补证相同逻辑。**对 `rw.toString()`、`RegWr32.toString()`、`FillData.toString()`、`SubdevRegWr32.toString()` 的客体串口只读查询证实：当前 `rw` 调用 `RegWr32` 再 `RegRd32`；GPU已初始化时使用 `GpuSubdevice.RegWr32`；`FillData` 默认一次且忽略 `WriteFunction` 返回，外层照常返回 `RC.OK`。原生方法 `GpuSubdevice.RegWr32.toString()` 仅给 `[native code]`。

**新增同版 ELF 只读结果：**JS 原生绑定 wrapper FDE `0x11b4880..0x11b492f`（由 `.rodata` 中 `Usage: GpuSubdevice.RegWr32(Offset, Data)` 字符串及调用内容确认）验证两个参数后解析 subdevice，再于 `0x11b4911` 调其 vtable `+0x230` 写方法；随后无论该虚方法的返回值是什么，都把 JavaScript 输出设为 `true` 并返回成功。该 wrapper 没有读取 `SecurityUnlockLevel`。下层有界函数 `0xdec430..0xdec678`（依据 RegWr32 excluded/failed 写日志和寄存器存储控制流，识别为普通寄存器 writer）先查一般写屏蔽/掩码 vector (`0xdbf640`)，需要掩码时读旧值合并；随后按 transport state 进入 RM `EXEC_REG_OPS` helper (`0xdec2f0`) 或 mapped aperture store。以上 wrapper、writer、地址/remap/filter/RM helper 窗内均没有对 `SecurityUnlockLevel` getter/`>3` helper 的直接调用。全 ELF 直接-call 扫描找到 `>3` helper `0xd81e20` 的唯一直接调用点 `0x15081d6`（`0x1507460..0x1508860`，fuse/floorsweep mask 流程），不在此 writer；getter `0xd81e00` 的六个直接调用点是 `0xc0b077`、`0xd76826`、`0x19f0d3d`、`0x19f0e00`、`0x19f5df8`、`0x19f5e02`。**重要补充：还有 219 处直接调用跳板 `0xd77cd0 → 0xd81e00`，其中 165 处紧跟对 3 的比较；不能由 getter 的六个直接调用推断进程级权限检查稀少或全局不存在。**已辨认的 `RegWr32` JS/native wrapper、普通 writer 与 FB HAL constructor/直接 caller 的局部窗口均没有直接 SUL getter、跳板或 `>3` helper 调用；但其它更上游/间接路径尚未穷尽，目前没有正面证据说这个 raw writer 按网络等级拒写。已识别的 profile writer `0x685a690` 有间接 HAL 调用，故不能用“未见直接 SUL call”证明整个旧 profile writer 链绝无 gate。仍未知 RM/GSP/设备侧 PLM 是否拒写、native status，以及本次 CL+1 请求是否到达设备。运行时 `g_RegWrMask` 为 object 且 `length=0`；无此脚本屏蔽项不代表设备允许访问。

## 高层时序 setter 与频率切档不是同一条路径

与 VM 同版的 MODS **570.215** ELF SHA256 `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856` 已在同目录 `REPORT.md` 用原指令重放：selector `0x1d` 的 FB HAL `+0x700` 绑定 `0x685a690`（CONFIG0..5 programmer，目标值不同时经 helper `0x6b0ac60` 写），但已识别 **GB202 命名组** `0x46/0x47/0x49/0x4a/0x4b` 的 `+0x700` 是 `0x6c533c0`（`xor eax,eax; ret`），三个旧 timing setter 槽返回 `0x56`。`0x56` 表示**不支持这个旧接口**，不是已证明的“授权拒绝”。

**DID→selector 结论：仍未闭合；完整同版扫描未找到 `0x2b85` 的静态 feed。** constructor `0x6c47810` 在 `0x6c47864` 读取输入对象 `[rsi+0x10]`；全 ELF `.text` 直接 rel32 扫描确认其唯一 caller 是 `0x6c55eb2`（FDE `0x6c550e0..0x6c58f41`）。该 wrapper 保留输入对象于 `r14` 并将 `rsi=r14` 传给 constructor。其上游 FDE `0x6c58f50..0x6c59184` 在 `0x6c59074` 调 wrapper，输入 `r15` 来自 `0x6c58fec` 对 helper `0x6b797b0` 的 lookup（输入对象 `r14`、描述符 `0x9db2f60`）。新增 `scan_570215_selector_refs.py` 以正确 `.text` VA（`0x4a0ac0`，fileoff `0xa0ac0`）解码全段 30,864,944 条指令：完整 rel32 xref 仍只命中这两个 caller；没有精确 `0x2b85` 指令立即数，574,779 个 RIP-relative 引用也没有任何 file-backed 目标前 0x20 字节含该字。唯一低16位等于 `0x2b85` 的立即数是 `0x09142b85` 日志 ID（`0x11e2319`），并非 selector 比较。由此能说 selector 是 lookup 返回对象的 `+0x10` 字段，不能说 PCI DID `0x2b85` 生成该 lookup 输入/selector；也不能排除更上游由运行时设备信息索引到对象的间接映射。故不能仅凭 DID 或“GB202 命名组”把这张卡归到 no-op 槽位，也不能把旧槽的空实现指定为本次换档的最终 writer。详细扫描及 raw rel32 假阳性说明见同目录 `REPORT.md`。

旧明文 `mods.js:1280-1341` 里的 `dramclk(mHz)` 经 `Gpu.ClkM`、`Subdev.Perf.GetPerfPoint/SetPerfPoint` 等分支设置 Perf；**这不是已核对的 570.215 解密脚本**，只能解释用户界面意图。同版 ELF 的既有 `power_governor_reverse/MODS570215_MCLK_3999_4000_STATIC_FINDINGS_20260903.md` 把高频 MCLK 请求沿 host RM → PMU change-sequence → mailbox command 追到设备固件。旧 E1 Memory Clock 表中 `14750–19999 MHz` 对应 tweak entry15，其前六字与此次 17999 MHz 活动读数一致；E0 运行时的 entry index/消费者**未实测或闭合**。目前仍**未定位哪个 GB202 固件组件最终写 CONFIG0..5**。该同版研究还记录：请求 **18001 MHz**（从14001基准恰好+4000MHz）可触发 PMU mailbox 断言/超时；不能试更高频率来猜权限。

## 目前不能回答、也不应盲试的点

- 570.215 这两个 `rw` 的底层 `GpuSubdevice.RegWr32` 是报告了拒绝、硬件保护哨兵、静默忽略，还是调用成功但另需时序更新/训练？现有实机记录只有**回读旧值**，缺该调用链的独立状态证明。
- 已只读实测此客体进程的 `SecurityUnlockLevel=1`；但 **570.215 CONFIG1 raw/HAL/PMU 的具体 gate**与 CONFIG1 设备端保护状态均未证实，不能把 L2/fuse 的 level>3 或 HULK 要求复制为内存 timing 的答案。
- 受控升频能够触发整组 profile 换档，不证明存在面向这张量产卡的“固定频率只改 CL 一项”接口，也不证明稳定性或任何权限旁路。下一步是**匹配 570.215 的只读静态数据流**及只读诊断资料，而不是捏造 bypass、写保护位或直接重试高风险寄存器。

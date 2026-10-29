# GB202：无需反复刷 VBIOS 的时序试验入口？匹配 MODS 570.215 的离线证据（2026-09-24）

**本轮仅离线。**未运行 MODS、SSH 客体中的 GPU 程序，没有修改/装载 VBIOS、访问 GPU/BAR0/MMIO 或调整MCLK；当前 VFIO 客体继续空闲，低噪冷却守卫运行。下述 ROM 文件入口只是软件存在性证据，**不是建议向这张卡加载改动 ROM**。

## 用户问题与目前最重要的区分

NVIDIA 内部调单项时序不必每次把永久 EEPROM flash 重写：理论上可以用诊断环境将一份 VBIOS 镜像/时序 profile 输入暂存的 host/firmware 初始化流程，或通过具权限的设备端训练/换档程序提交临时状态。但本卡 **GB202/GDDR7** 的可达性、签名/接受门、固定频率重新训练以及有效 CL 变化**还没有一个完整的同版本证据闭环**。因此“无需刷写的输入路径存在”不能等于“可用的量产5090 live CL setter”。

## 570.215 ELF 中确有非 flash 的 VBIOS 文件输入/替换线索

目标 ELF SHA256 `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856`，字符串和有界反汇编：

- file offset `0x8845320`：`Warning: The -bios option is deprecated. Please use -gpubios instead.`；`0x8d20a5c`：`-gpubios`。启动参数解析 `0xbd7956..0xbd79ae` 明确引用这选项。不能仅由 CLI 字符串认定安全固件使用这个镜像。
- file offset `0x8845440`：`Set the vbios file for the specified device`；`0x9120bd4`：`SetDeviceVbios`。注册窗口 `0x77e858..0x77e875` 将方法名和描述绑定到 callback `0xbd6470`；这个 callback 在 `0xbd6570..0xbd663e` 将设备索引和字符串文件名写入**进程内映射**，局部未见 flash 写命令。`-gpubios` 解析附近 `0xbd79b6` 与 callback `0xbd65c4` 均访问同一映射根全局 `0x17ac6470`，所以两个前端确实汇入相同的 per-device filename 状态；**还没证明其后端消费者**是否在 GB202 init 链以它替换 EEPROM 镜像，也未证明修改时序的镜像被设备接受。
- 同 ELF 的 host RM 另有 `NVRM: OBJVBIOS: RedoInitialScan: Found a Rom Override registry key romOverride%02X size=%d`（file offset `0x8a74b30`）、`NVRM: GPU %x VBIOS found: Reg override (1)`（`0x8a757d0`）及 `NVRM: GPU %x using VBIOS from volatile reg key.`（file offset `0x8a75950`）；这是**易失性**内存/registry ROM 来源，不是 EEPROM flash 命令。文件参数可能汇入该来源是**强推断**，但完整 `-gpubios → ROM bytes → romOverride%02X → GB202实际init` 调用/数据流尚未闭合，不能证明改动镜像的 GDDR7 tweak 会被接受或消费。
- 同版 RM 有结构/板卡兼容检查（PCI ROM/PCIR header、checksum、设备ID、revlock），还有**独立**的 VBIOS 签名失败、证书链、FWSECLIC/HAT 错误字符串。`Allowing mismatching PCI devids because of reg key override`（file offset `0x8aa5b98`）只表明某个设备ID不匹配条件有例外，**不**代表签名/证书/HAT/revlock获豁免。旧脚本 `g_CheckVbiosSecurity=false` 跳过 host JS `ValidateVbios()`；本次实际 570.215 进程 level仍为1。不能凭文件输入/JS开关推断改时序的 ROM 在量产5090上会被接受。
- 另有静态 `VBIOS devinit may be skipped` 提示：GPU已由MODS/SBIOS POST或UEFI/skip-POST状态时，传文件名并不保证 Devinit/FSP 重新运行或把镜像的 timing 重新训练到颗粒上。具体 GB202 接受与阶段未测。

## 现存高层显存时序与受控换档接口

- 同版构造函数离线重放 `write/reproduce_selector700_570215.py`：旧/共享 selector `0x1d` 的 FB HAL `+0x700` 是 CONFIG0..5 programmer `0x685a690`；已识别 **GB202 命名组** `0x46/0x47/0x49/0x4a/0x4b` 则 `+0x700` 返回0、不编程，`+0x808/+0x810/+0x818` 三个旧 setter 返回 `0x56=NOT_SUPPORTED`。本卡 PCI DID `0x2b85→实际 selector` 尚未闭合，且这三个旧 setter 所改 entry 字段未被证明分别就是 CL/tRFC/tRCD。不能将共享 writer 名称误叫成 GB202 可用实时单项接口。
- MODS `dramclk(18000)` 实机改变实际 ClkM (约17999MHz) 及九组CONFIG0..5到另一个六字profile；同版已有静态研究 `../../../power_governor_reverse/MODS570215_MCLK_3999_4000_STATIC_FINDINGS_20260903.md` 将 MCLK relation/control 追至 host RM→PMU change-sequence→设备 mailbox command0，payload 是**最终绝对MCLK目标**，不是任意CONFIG1字段。还没有把 mailbox 的后续消费者与本卡 GDDR7 配置字/模式寄存器/训练完整闭合；只靠 `dramclk` 不能声称存在“固定频率单项CL”控制。
- 同版 ELF 确有 `Starting per switch Memory Link Training` 和 `DLCELL training triggered` 字符串，xref 落在函数 `0x685eca0..0x685f65f`；但入口读取 RAM type `[rsi+0x435c]` 并只走旧类型 `0x8/0xc/0x10` 分支，不能把这段日志直接指定为 GDDR7 `0x15` 换档训练。邻接 `0x685eb90..0x685ec43` 的 `Using VBIOS RAM timing table entry` 是条目 stride `0xe0` 的**另一张旧 RAM timing 表**，不是本卡 E1 的每条105字节 `Memory Tweak` 表。某种运行时训练可能存在，但这两个具名代码窗尚未证明为本卡 GB202 18GHz换档调用链。
- 另一条貌似可单项修改的 `NVRM: Updating tRP value from %u to %u. Current FBPA_CONFIG0 = ...`（xref `0x7025c29`）已经做了同版有界反汇编：函数 `0x7025bc0..0x7025e49` 先要求 `[rsi+0x8c62]!=0`，再只允许 `[rdi+0xc6a]` 为 `0x1db1/0x1db2/0x1db4`（本机 pci.ids 对应 GV100 Tesla V100），否则 `0x7025bec` 立即返回。随后读 `0x9a0290` 的 tRP `[30:24]`，只有它不等于**固定常量20**时才调用其它 helpers。全 `.text` 直接-call/jmp xref 未找到入口，唯一找到的目标地址 literal 在 `0x6c50118`：另一 FB HAL 构造器 `0x6c4fac0..0x6c52829` 只在输入结构 `+0x10` selector=`0x3` 时把 `0x7025bc0` 绑定到 `+0xeb0`。即使 `0x2b85→selector` 总映射未闭合，函数本身还受这些旧 PCI ID 的硬过滤。它是**特定旧卡的固定 tRP20 修正候选**，不是任意 GB202 CL/频率独立 setter；没有对本卡执行函数或写测试。
- NVIDIA 公布的 `Memory Clock` 表将频段/strap 指向 `Memory Tweak` entry，符合“选整套profile”的设计。**旧 E1** 14750..19999MHz 指向 entry15；当前 E0 实机高频六字与之相同，不等于已验证全部E0表或每个频率的稳定性。对 SHA256 `01a2e034…a8333b` 的**旧 E1 ROM** 在 table `0x73681+6` 按每条105 byte 离线比对 entry14/15，**22/105 字节不同，其中11字节位于 CONFIG0..5 的前24字节之后**（偏移42,43,44,51,56,57,84,85,88,96,97）。后半记录的 GDDR7 含义未闭合；这再次表明“只改 CL 一项”不能未经证实就当作完整的高档配置/训练过程。

## 下一步仅只读

1. 闭合 `-gpubios`/`SetDeviceVbios`/`romOverride` 数据流及 GB202 在内存镜像验证与安全Devinit阶段实际取哪个 ROM。无证据时只报告候选输入，**不准备修改、加载或刷写 ROM**。
2. 查匹配版本 GB202 的 RAM timing表 consumer、单项 setter 槽实际绑定与提交机制；若只找到 cold-boot Devinit/FBFalcon，不能把它移植为 live MCLK 换档。
3. 追已知PMU command0/phase12到真正的 CONFIG0..5 programmer，核查是否从运行中 profile 提取 CL 或由设备侧固件从 VBIOS 重新选表。若接口未知，停止在断点，不通过CL盲写补洞。

交叉参见 `MODS_570215_AUTH_AND_TIMING_ROUTE_20260924.md`、`GB202_CONFIG1_CL_RW_AND_APPLY_20260924.md`、`../read/GB202_MODS_18000MHZ_LIVE_20260924.md`、`../../gb202_init_acceptance_20260911/README.md`。

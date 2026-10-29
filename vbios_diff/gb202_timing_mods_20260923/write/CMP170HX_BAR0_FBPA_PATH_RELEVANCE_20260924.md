# CMP 170HX / SEC2 / BAR0→FBPA 线索：对 GB202 的适用边界（2026-09-24）

## 结论

用户所说的“HX170”最可能是 **NVIDIA CMP 170HX**。这个线索比“MODS 有网络权限等级”更贴近硬件写入问题：相关方法不是单纯打开 BAR0 映射，而是在 CMP 170HX/GA100 的启动链中先取得更高 privilege level、打开受保护资源的 PLM，再由 host 经常规 BAR0 访问写 FBPA memory-geometry 配置。

**这证明某个 GA100/CMP 170HX 配置有可行的受控 PLM-opening→BAR0 写入方案；不能证明 RTX 5090/GB202/GDDR7 也能这样做。** 本项目不尝试把该流程移植到 5090，不试 exploitable booter、PLM/FSP/HULK，也不向 GPU 做写入。

## 交叉核查

### 1. 原始研究讲的不是“BAR0 可直接越权”

Jon Pry 的论文 *A Canary in the Crypto Mine: Defeating Stack Protection in a GPU Secure Coprocessor*（2026-06-26，Zenodo `20916111`）讨论 NVIDIA **CMP 170HX / GA100** 上 SEC2 signed booter 的栈保护缺陷。论文描述的入口是安全固件执行链里的内存破坏/高权限执行条件，而不是 `mmap(BAR0)` 自动绕过寄存器保护。论文称 PL0 对某些目标寄存器的写会被 PLM 拒绝；取得更高执行级别后打开相关 PLM，主机再使用普通 BAR0 写入。签名验证并未被伪造。

论文展示了 framebuffer geometry 的实际效果，但不能把 geometry 变化直接等同于已证明所有 FBPA timing/PLL 写入成功。针对受影响 SEC2 booter 的分支范围仍有限：研究比较过 510 与 580 分支，515–570 及精确修复 point release 未闭合；不把这写成普遍的 NVIDIA 漏洞版本范围。

### 2. cmpunlocker 给出一个 610.43.0x CMP 170HX 工程化实现

本地只读审计 `/home/user/rt_5090_project/external/cmpunlocker`：

- 仓库 HEAD `cc872cb`，README 声称目标为 **nvidia-open 610.43.0x** 与 CMP 170HX；PCI DID 为 `0x20c2/0x2082` 的 GA100 设备路径。
- `driver/patches/0001-sec2-postbl-plm-ss-cfg.patch` 修改 GSP boot 流程：重用 booter-load 操作处理 PLM 后，经 host register access 写若干 FB/feature/memory-geometry 状态，并立即读回/打印；README 将其报告为可恢复 64GB/40GB HBM2e 几何的实现。
- `0002-booter-verify.patch` 增加写后状态读回诊断；补丁源代码能证明项目**尝试并验证**这些访问的设计，README/项目报告提供该卡上的结果主张。本地没有执行过该软件，也没有独立实机复跑。
- 这是一条针对 GA100/特定 DID/特定 GSP+SEC2 启动阶段的 patched-driver 路径，不是 MODS 原生 `rw` 的通用权限开关。

### 3. PLL/HBM timing 扩展是另一项未合并提案

公开 [cmpunlocker PR #53](https://github.com/amoghmunikote/cmpunlocker/pull/53) 标题为开放 FBPA PLL/memory PLM 以便 170tune 调 HBM clock/timing。该 PR 于 **2026-09-21 closed without merge**；讨论提及部分卡存在不可达 FBPA PLL window/PRI orphan 问题。故它是硬件依赖的实验性提案，不是 cmpunlocker 已发布功能或普遍有效性证明。

区别：

- geometry unlock 与 timing/PLL tuning 分开；
- “PLM 已打开”只表示某类受保护寄存器可被 host 请求访问，并不保证每个 FBPA、每个 PLL、每个 timing 项都可达或被接受；
- PR 关闭不证明漏洞已修复，也不证明该方法对其它芯片可移植。

## 与本项目 GB202/570.215 的关系

### 可证

- 5090 是 GB202/GDDR7，目标 PCI DID `0x2b85`；CMP 170HX 是 GA100/HBM2e，cmpunlocker 针对不同 DID/boot state 和内存控制器世代。
- GB202 公开 610.43.03 源码审计 `../parallel/gb202_610_arch.md` 证实 GB202 的 FSP/NVDM 与 SEC2/NVDM HAL 职责不同：GB202 有有效 FSP 消息路径，而 SEC2 NVDM packet 方法为不支持桩。这个事实**不等于**对 GB202 启动中所有 SEC2/Booter 使用情形都已定论；不能只凭它断言 booter 漏洞不可能存在。
- 本次匹配的 MODS 570.215 实机只读查询显示 `SecurityUnlockLevel=1`，`g_RegWrMask.length=0`；运行时内省确认 `rw` 调 `GpuSubdevice.RegWr32` 后回读。ELF 内原生 JS 绑定 wrapper `0x11b4880..0x11b492f` 在 `0x11b4911` 调 vtable `+0x230`，再无条件把 JS 结果设为 `true`；此 wrapper 不查 `SecurityUnlockLevel`。该 session 的启动信息还显示 `BAR0 Access=DirectMap`、`GSP-RM=Disabled`。这些说明 MODS 用户侧请求不会因已观察的 level=1 被这个 wrapper 拦截，不说明设备接受请求。
- 同版 ELF 的普通寄存器 writer 候选 `0xdec430..0xdec678`含 range filter与 mapped-aperture/RM transport分支；该有界 writer/helper 路径无直接 `SecurityUnlockLevel` getter/`>3` 检查。`>3` helper `0xd81e20` 的唯一直接调用位于另一函数 `0x15081d6`；**同时全 ELF 还存在 219 处对 getter 跳板 `0xd77cd0` 的直接调用，不能凭前者只有一次就断言等级只被检查一次。**已识别的 raw wrapper/writer 窗没有直接调用这些 getter/跳板；“缺网络等级就是它的显式 host gate”目前无正面证据，但 RM/GSP/设备侧 PLM、其余间接路径仍未排除。
- 两次 CONFIG1 CL+1 请求都回读原值。该观察与“host BAR0 写请求到达后被设备侧权限/硬件拒绝”相容，也与 native backend 抑制、写入协议、其它未识别机制相容；**不能据此判定是 `SecurityUnlockLevel=1` 导致**。

### 未知

1. 本次 CL+1 对应的底层 `GpuSubdevice.RegWr32` native 状态/错误码，以及该 CONFIG1 写是否到达设备。
2. 当前卡 CONFIG0..5 的 GB202 RegHal/access metadata、实际 PLM 等级和写接受条件。
3. `0x2b85 → MODS 内部 FB HAL selector` 的完整生产映射。Constructor `0x6c47810` 从传入对象 `+0x10` 读 selector（唯一直接 caller `0x6c55eb2`）；caller 的上游 `0x6c59074` 通过 `0x6b797b0` lookup 得到该对象，但未找到 PCI DID 如何进入该 lookup。已重放的 `0x46/0x47/0x49/0x4a/0x4b` 只是“已识别 GB202 命名 selector 组”，还不是由 DID 闭合出来的板卡路径。
4. GB202 固件在 MCLK PerfPoint 切换时由哪个组件/命令更新配置，以及是否存在支持“固定 MCLK、只改一个 timing”的受支持 consumer。
5. CMP 170HX booter 漏洞是否在 GB202 的对应固件/secure boot path 中以任何相同缺陷存在。两种架构相似有安全固件/PLM概念，不构成漏洞移植证据。

## 最小安全后续

1. 只读闭合 570.215 native `RegWr32` → OS/RM transport 的状态语义；不复做寄存器写。
2. 对 GB202 的 CONFIG0..5 做离线 RegHal descriptor/access-offset 与同版 GSP/FSP firmware 静态交叉，确认是否有设备侧写限制。不要用未经确认的 PLM 含义推断值。
3. 完成 DID→selector→HAL writer 的静态映射。若符号/字符串无法闭合，记录“未知”，不使用高风险探针补洞。
4. 需要厂商权限/修复状态时，询问 NVIDIA 产品安全团队精确 GB202 SEC2/FSP firmware build 范围；不仿造网络认证/HULK token，不修改 firmware/PLM。

## 来源

- 原论文与元数据：[Zenodo record 20916111](https://zenodo.org/records/20916111)
- CMP 170HX 实现：[amoghmunikote/cmpunlocker](https://github.com/amoghmunikote/cmpunlocker)；本地静态副本 `external/cmpunlocker/README.md`、`driver/patches/0001-sec2-postbl-plm-ss-cfg.patch`、`0002-booter-verify.patch`
- HBM/PLL 扩展提案：[cmpunlocker PR #53](https://github.com/amoghmunikote/cmpunlocker/pull/53)
- GB202 同版源码边界：`../../../parallel/gb202_610_arch.md`
- 当前 570.215 进程等级、raw wrapper 边界：`MODS_570215_AUTH_AND_TIMING_ROUTE_20260924.md`

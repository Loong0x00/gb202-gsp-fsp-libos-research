# GB202：写的是 CL 字段还是“请求寄存器”？CONFIG1 读写对称性与生效边界（只读核查，2026-09-24）

**硬件范围：**只回看已有 VFIO/MODS 570.215 记录、NVIDIA Memory Tweak Table 文档副本和同版 MODS ELF SHA256 `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856`。本轮没有运行 MODS、访问 GPU/BAR0、执行寄存器写、切换 MCLK 或改变 VFIO。宿主现有低噪声冷却守卫保持运行。

## 首先纠正寄存器性质

原始命令 `rw(0x9a0294, 0x796805a4)` 和 `rw(0x900294, 0x796805a4)` 的目标是 **FBPA CONFIG1** 的广播/FBPA0 MMIO 地址，**不是一个独立的“修改 CL 请求”寄存器或 MODS 时序 setter**。公开 [NVIDIA Memory Tweak Table](https://nvidia.github.io/open-gpu-doc/MemoryTweakTable/MemoryTweakTable.html) 的 v0x20 entry 把 `CONFIG1[6:0]` 标为 `CL`。两值按此字段解码：

| CONFIG1 字 | `[6:0]` | CL |
|---|---:|---:|
| 14001MHz 活动回读 `0x796805a3` | `0x23` | 35 |
| 请求写入 `0x796805a4` | `0x24` | 36 |
| 17999MHz 活动回读 `0x797885a5` | `0x25` | 37 |

`0x796805a3 ^ 0x796805a4 = 0x7`，差异**完全落在 CL 这个 7-bit 字段内**，不是置位一个额外的 update/request bit。同版 MODS 570.215 的 FB HAL `+0x738` 地址解析函数 `0x70601b0` 在 mode=0、index=0 时返回 `0x9a0000+offset`，所以 offset `0x294` 对应广播 `0x9a0294`；在 mode=1、index=0 时返回 `(0x240<<14)+offset=0x900000+offset`，所以对应 FBPA0 `0x900294`。同版旧 CONFIG programmer `0x685a690` 在 `0x685ad3d..0x685ad8d` 也将 offset `0x294` 与 entry `+0xd8` 比较并调用寄存器写 helper，日志字符串明确标作 `NV_PFB_FBPA_CONFIG1 programmed to`；**但该旧 programmer 在已测 GB202 命名 selector 的 +0x700 为 no-op，不能说这张卡实际使用了它。**实机在两种受控频率的九组读值分别与旧 E1 ROM timing entry14/15 前六字对应，进一步支持这些 MMIO CONFIG0..5 是被受控换档选中的配置字。不过公开位域定义早于 GB202，E0 当前 ROM 的精确 entry index 和 GDDR7 内部/颗粒 mode register 生效状态**没有独立实测**；因此只证实“该可读配置字的 CL 编码”，不声称等于 DRAM 物理生效 CL 的最终唯一状态。

**避免混淆：**CMP 170HX/GA100 项目在 `0x9a0204` 写的 `FBPA_CFG1` 是内存几何配置；本卡的时序 `CONFIG1` 地址是 `0x9a0294`，偏移差 `0x90`。不能把那项 geometry 解锁视为本卡 CONFIG1 写成功证据。

## 匹配版本的 JS/原生同址关系（570.215）

原生 JS 绑定 `GpuSubdevice.RegRd32` FDE `0x11b4d10..0x11b4dc8` 于 `0x11b4d84` 用 vtable `+0x220`，`GpuSubdevice.RegWr32` FDE `0x11b4880..0x11b492f` 于 `0x11b4911` 用 vtable `+0x230`。抽查同版包含普通/Blackwell/GB20x 的 vtable 样本，例如表 qword VA `0x92cbb18`：`+0x220` 指向 `0xdebeb0`，`+0x230` 指向 `0xdec430`；另外若干 vtable 也有同一 read/write 函数对。并非仅根据 570.151 脚本类比。

- 读后端 `0xdebeb0..0xdec02f`：输入 offset 于 `0xdebeb9` 经 exact-remap `0xdbe4b0`；mapped-aperture 分支 `0xdebf5d` 再调用同一 remap helper，`0xdebf6e` 从设备 aperture `mappedBase+translatedOffset` 加载 `DWORD`。
- 写后端 `0xdec430..0xdec678`：输入 offset 于 `0xdec441` 经**同一个** `0xdbe4b0`；在一般写掩码/排除表 `0xdbf640`（`mask=0` 时有 excluded 路径）之后，mapped-aperture 分支 `0xdec571` 再 remap，`0xdec582` 对 `mappedBase+translatedOffset` 存储 `DWORD`。
- 读/写在对象状态 `+0x19ea/+0x19e8` 同时满足时也各有可选 RM `NV2080_CTRL_CMD_GPU_EXEC_REG_OPS (0x20800122)` 分支（读 `0xdeb810`、写 `0xdec2f0`）。实机 MODS 启动记录是 `BAR0 Access=DirectMap`、`GSP-RM=Disabled`，但这两行**不足以独立证明**此次 raw call 绝对只走 mapped 还是可选 RM 分支。两个后端对地址的 remap helper 相同；写侧还可能命中排除/位掩码表，且特定虚方法/设备分区条件需继续限定。

因此在**普通同一对象、默认无外部 remap/写屏蔽且相同 transport flags**条件下，`rw` 的写和紧随读访问同一解析地址；不是 JS 故意写“请求寄存器”后改从另一个地址读 CL。以前 570.215 VM 的运行时 `g_RegWrMask.length=0` 是 JS 层没有添加写屏蔽项的正证据，不能穷尽原生外部初始化或设备级保护。原生 JS wrapper 不传播底层写状态，不能仅凭 `rw` 打印旧值辨别 PLM、硬件锁还是静默失败。

## 同版本 RegHal 的 CONFIG1 线索不等于 PLM 已知

对该 570.215 ELF 使用项目既有**离线** `gb202_reghal_offline.py` 解出 chip `0x0ff2` 表：header file offset `0x9043c8f`、20,083 rows。普通 lookup `RegHal ID=0x1007c000`、index `(165,0,0,0)`、domain `0x1e` 的 offset 为 `0x294`；同 ID 的 index164/166 分别是 `0x290/0x298`。该 ID 没有 `index=0xfffe` 的配套 access-offset 行。表中还存在其它 domain-5 的 `0x294` 行、access offset `0xfc`；**不同 domain/ID 的这个 `0xfc` 不得移植给 FBPA CONFIG1**，也不能用“此 ID 缺 access metadata”断言设备没有 PLM。此表的 domain0x1e 解析到具体 FBPA 实际绝对地址仍需 HAL resolver/DeviceInfo2 核验；当前证据仍不能给出本卡 CONFIG1 的具体访问权限寄存器或实时值。

## “下一个显存时钟自动应用” vs 显式事件

- 两次 CL+1 请求之后立刻读回原 `0x796805a3`，随后八分区+广播九组 CONFIG0..5 仍旧值。无可见“过若干 CK 周期自动变成 CL36”；JS 命令和九组复读跨过的显存时钟周期远多于一个。
- 若**同一可读存储**接受了 CONFIG1 写但等待一个显式 commit/training 才生效，通常会先读到新 CONFIG1 字而未必改变真实 DRAM mode register；本次并没有读到新字。这使“已经成功存入该可读 CONFIG1、仅差下一次显存时钟”缺乏证据。
- 但是硬件也可以具有“写入不可读 shadow／读出仅 current effective 值”或保护写入、需要先停钟/特定时序窗口等语义。这里**没有芯片级定义或写状态**来排除这些机制，也没有证据将某个已知 commit 事件指认为本卡的 CL 单项生效 trigger。
- 受控 `dramclk(18000)` 报实际17999MHz，同时八 FBPA/广播整组六字变成另一条 ROM 表对应值。这证明**频率切档能调用某条更新整组时序的控制流程**，不能证明“正常运行每一个显存 CK 沿都会接纳任意 CL 写”，也不能证明存在固定频率独立修改 CL 的受支持 API。

**当前最准确的答法：**写的是 CONFIG1 的 CL 字段，且同版普通 read/write 后端在默认条件下同址；**没有看到异值在该可读 CONFIG1 上锁存**。设备侧为何未变化、读值是否为只读 effective alias、是否另需提交/训练，仍未知。下一步只能继续限定普通读写 transport/设备 CONFIG1 访问元数据与换档固件消费者，不能随便写 update 位或模仿其它 GPU 的 PLM。

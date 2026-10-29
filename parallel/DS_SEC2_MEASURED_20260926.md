# SEC2 实测数据解读（追问轮）—— 0x5E0 / 队列单位 / 是否在跑 / 风险

- 日期：2026-09-26（紧跟上一轮 `parallel/DS_SEC2_INTERFACE_20260926.md`）
- 机器：RTX 5090（`0x2b85`，GB202，chipHal idx = **65**），BDF `0000:01:00.0`
- 本轮方法：**纯静态源码分析 + 只读本地证据**。没有碰设备、没有跑任何 GPU 实验、没有改任何既有文件；
  本文件是唯一新增文件。
  - 允许并被使用的只读本地证据：① 上一轮与更早的**本机实测结果**（`PEEK`/`PANY` 内核模块日志，来自本机
    kernel journal）；② 更早的 FSP/EMEM 实测落盘日志（`/home/user/rt_5090_project/guest_dmesg_emem*_10*.txt`）；
    ③ 既有探针源码（`/home/user/peek/*.c`、`/home/user/fsp_probe/fsp_emem_mod.c`）。
- 源码版本：`/usr/src/nvidia-610.57.04/`；下文 `文件:行号` 相对 `/usr/src/nvidia-610.57.04/src/`。
- 证据等级：
  - ✅**[源]** = 源码/发布寄存器头文件的直接证据（可引用行号）
  - ✅**[实测]** = 本机已落盘日志里的直接观测（可引用命令与行）
  - ⚠️**[同族]** = 兄弟代（ga100/ga102/tu102/gh100/gb10b/gb20b）发布表跨到 GB202，只是"同 IP 假设"
  - ❓**[推测]** = 明确标注的推断，不要当结论

---

## 0. 摘要（7 行）

1. **`PMC 0x5E0` 不是我们的判据**：它只发布在 `blackwell/gb20b/dev_boot_zb.h:26`（`NV_PMC_ZB_SCRATCH_RESET_PLUS_2`，
   整 32 bit 的普通 scratch，`0xFF` 是**约定值**而非位域），只有 GB20B/GB20C 会去等它；GB202 实测 0 **不代表异常**
   ——GB202 绑定的 `ksec2WaitForSecureBoot` 是返回 `NV_ERR_NOT_SUPPORTED` 的 default 桩，**从不读 0x5E0**。
   GB202 真正的"boot 完成"判据是 FSP 的 `0x00AD00BC == 0xFF`（`kern_fsp_gb202.c:50-61`）。
2. **`0x840100` 的 bit4 = `CPUCTL.HALTED`**（不是"核在跑"）。实测 `0x840100 = 0x10` ⇒ `HALTED = 1` ⇒
   SEC2 核**当前处于 halt/空闲**（既可能"跑完固件后 HALT"，也可能"上电后从未启动"），因此**它不能证明 SEC2 在跑**；
   且该寄存器在不同 GPU 状态下读到过 `0xbadf5620`（读取被特权拒绝），单点值不可信。**上一轮把 bit4 说反了**。
3. **`0x840320` 那对 `0xBADF5108` 更可能是"host 读被拒"而不是"FWSEC 错误码"**：`0xBADF0000/0xFFFF0000` 是
   falcon CSB 特权 PRI 错误编码（`nvidia/arch/nvalloc/common/inc/flcnretval.h:256-257`），同型的 `0xbadf5620`
   在本机的 FSP 受保护区（0x8f0000..）也被读到（`guest_dmesg_emem3_1003.txt:3-40`）。⇒ 这个偏移对 host **不可读**，
   里面的真实内容（FWSEC 错误码是否 0）我们**看不到**。
4. **队列寄存器是"字节偏移（地址）"，不是索引/计数**——这一条现在有**闭环证据**：驱动三处写
   `align_up(bytes,4)-4`（`kernel_sec2_gb10b.c:704,708`、`kern_fsp_gh100.c:648,651`、`fsprpc_nvswitch.c:326-343`），
   读侧 `(tail-head)+4` 字节（`kernel_sec2_gb20b.c:479`、`kern_fsp_gh100.c:688`），而 EMEMC 的 OFFS/BLK 是 **dword**
   计数（`kernel_sec2_gb20b.c:514`、`kern_fsp_gh100.c:723` 的断言把它俩钉在一起）。
   **本机 FSP 实测把这条闭环了**：回包结构长度恰为 20 B，FSP 写 `MSGQ_TAIL=0x10=16` ⇒ `(16-0)+4 = 20` ✅ 字节；
   而本机 `0x8f2ac0 = 0x02000014`（`AINCR=1, OFFS=5` dword = **20 B**）也与 host 上一次“读了 20 B 回包”吻合
   （❓[推测]：两者是同一事件的前后脚印，但没有同一次运行的直接日志把两者钉死；早前的 `0x02000020`（OFFS=8 dword=32 B）
   说明这个字段确实随真实传输变化）。
5. **既有 FSP 工具的 `QUEUE_TAIL = len/4-1` 与 `dw=(tail-head)+1` 都是错的（差 4×）**：正确形式是
   `TAIL = align_up(bytes,4) - 4`、`HEAD = 0`（TAIL 先写、HEAD 后写 = 敲门铃）。该工具的"响应字节≈20"一行用的是
   字节公式（对的），而它的读取循环用 dword 公式（多读 48 B）。
6. **GB202 上"SEC2 在跑"没有源码背书，也没有现成心跳**：唯一可用的只读信号是 ① `PBUS SW_SCRATCH` 系列
   （**绝对偏移 0x1400+4i**：`FWSEC version`/`Devinit Boot Status`/`FRTS Completion`/`COT Polling Status`，
   `kernel_sec2_gb20b.c:850-887` + `gb100/dev_bus.h:27` + `gb100/hwproject.h:35`）② PCI config DVSEC `0x2B4`
   的 `SEC2_DCLS/SEC2_L5_WDT` 位（`gb202/dev_boot_zb.h:41-43`、`gb202/dev_xtl_ep_pcfg_gpu.h:27`）；
   ③ 0x840xxx 的**可读性本身**就是状态指针（见 §1.1 与 §2.3(b) 的 A/B 实测）。
7. **风险结论不变**：只读基本安全（本机已做过上千次读，无 Xid、驱动正常），**发送仍然一律禁止**，但必须点名两个
   "读不纯"的东西：`EMEMD`（`0x840ac4`，当前 `EMEMC=0x02000040` 里 `AINCR=1` ⇒ **读一次就推进一次游标**，
   上一轮已经读过很多次了）与 `MSGQ_HEAD/TAIL`/`QUEUE_HEAD/TAIL`（**写**=门铃/ACK，绝不能写）。

---

## 1. 本轮新增/复用的只读证据（可复核）

### 1.1 本机 PEEK/PANY 实测时间线（kernel journal，2026-09-26）

命令（只读本地日志，不触设备）：
```bash
journalctl -k --no-pager --since "2026-09-26 13:40" | grep -E "PEEK|PANY"
```
探针源码：`/home/user/peek/peek_mod.c`（一次性读，`ioremap(resource0)+ioread32`）、
`/home/user/peek/poll_any.c`（10 ms 周期采样器，只打印变化）。**两者读法完全相同**（同一 BDF 默认参数：
`pbus=1,pdev=0,pfn=0`；同一 `ioremap(pci_resource_start(p,0), 0x900000)`；同一 `ioread32`）。

| 时刻 | 事件 | 关键观测 |
|---|---|---|
| 14:06:52 | PEEK（驱动已绑定且已完成 devinit/显示初始化） | 0x840040=`0xe6513000` 0x840044=`0x74000007` 0x840100=`0x10` 0x840ac0=`0x02000040` 0x840c00/04=`0x01000100` 0x840c80/84=`0x01000040` |
| 14:09:09–14:09:10 | `[drm] Unloading driver` / `nvidia-modeset: Unloading` | 驱动卸载 |
| 14:09:13 | PANY 基线（**无驱动**） | 0x840040/44=`0` 0x840100=`0xbadf5620`(毒) 0x840ac0=`0` 0x840c00/04=`0` 0x840c80/84=`0`；**0x840320=`0xbadf5108` 两次状态都一样** |
| 14:09:15 | `NVRM: loading ... 610.57.04` | 驱动重新加载 |
| 14:09:13→14:10:15 | PANY 连续采样 **5630 轮 / 18 寄存器 / 150 s** | **全程没有一行"变化"**（PSEC 那批寄存器一直是 0/毒） |
| 14:10:20 / 14:10:42 | `nvidia-modeset: Loading` / `fbcon: Taking over console` | 显示侧起来 |
| 14:10:59 | PEEK（与 14:06:52 **逐字段相同**） | 结构化值全部回来 |

**控制读数（两个状态下都可读，说明 GPU 并没断电）**：`0x000000 = 0x1b2000a1`（PMC BOOT_0）、
`0x0005e0 = 0`、`0x824140 = 0x2`（fuse）、`0x8f2ac0 = 0x02000014`（FSP EMEMC）、`0x8f2c00/0x8f2c80 = 0`。

⇒ 两个可复现事实（✅[实测]）：
- **PSEC 块（0x840xxx）的可读性/内容随 GPU 状态变化**：驱动卸载后那批偏移读 0、`0x840100` 读特权毒；
  驱动 + 显示活动重新起来后，它们又变成同一组结构化值（跨一次 unload/reload **完全可重复**）。
- **`0x840320`/`0x840324` 在两种状态下都返回 `0xBADF5108`** ⇒ 这不是"状态相关"，而是**访问被拒**（见 §2.1）。

### 1.2 更早的 FSP/EMEM 实测（决定"字节 vs dword"的关键证据）

```
/home/user/rt_5090_project/guest_dmesg_emem5_1010.txt:4
  fsp_emem: MSGQ_HEAD=0 MSGQ_TAIL=16 → 数据 dwords=17        ← 工具按 dword 公式算
/home/user/rt_5090_project/guest_dmesg_emem5_1010.txt:3
  fsp_emem: 发后 MSGQ 0/16 → 响应字节≈20                      ← 同一工具里按字节公式算
/home/user/rt_5090_project/guest_dmesg_emem5_1010.txt:5
  fsp_emem: 回包 68 字节:                                     ← 实际读了 17 dword
/home/user/rt_5090_project/guest_dmesg_emem3_1003.txt:1
  fsp_emem: mode=prc_read ... EMEMC(0)=0x2000020 EMEMD(0)=0xffffffff QHEAD(0)=0x0 QTAIL(0)=0x0
```
（同型日志 `guest_dmesg_emem4_1008.txt:4` 有同样的 `MSGQ_HEAD=0 MSGQ_TAIL=16`。）

FSP 的 PRC 回包**结构长度**是可确定的：`NVDM_PAYLOAD_COMMAND_RESPONSE` = 12 B
（`nvidia/arch/nvalloc/common/inc/sec2/nvdm_payload_cmd_response.h:35-42`）+ MCTP(4) + NVDM(4) = **20 B**。
`MSGQ_TAIL - MSGQ_HEAD = 16` ⇒ `16 + 4 = 20` ✅（字节）；若按 dword 语义应是 `4*16+4 = 68` ❌。

---

## 2. 四个问题的回答

### 2.1 问题 1：`0x5E0` 的出处、语义，为什么是 0；第二个"FWSEC 完成"判据；`0x840100` 的位定义

**(a) 它属于哪个块 / 符号名 / 位定义** ✅[源]

| 项 | 值 | 出处 |
|---|---|---|
| 块 | **PMC（ZB PMC 窗口，`NV_PMC0_PRI_BASE = 0x0`）** | `blackwell/gb202/hwproject.h:27`、`blackwell/gb20b/hwproject.h:27` |
| 符号 | `NV_PMC_ZB_SCRATCH_RESET_PLUS_2` = `0x000005e0`，`RW-4R`，`__SAFETY "parity"`，孪生寄存器 `__PRIV_LEVEL_MASK = 0x000005e4` | `blackwell/gb20b/dev_boot_zb.h:26-30`（**只有 gb20b 发布**） |
| 位定义 | 只有整字 `_VALUE 31:0`，`VALUE_INIT = 0`。**没有位域**——"0xFF 表示完成"是**驱动/固件的约定**，不是硬件字段 | 同上 `:29-30` |
| 家族关系 | gb100 定义的是数组 `NV_PMC_ZB_SCRATCH_RESET_2(i) = 0x580 + 4i`，`__SIZE_1 = 16`（0x580..0x5BC）；`0x5E0 = 0x580 + 24*4`，**在该数组之外**，所以 gb20b 把它单独命名是合理的 | `blackwell/gb100/dev_boot_zb.h:28-31` |

**(b) 语义与消费点** ✅[源]
- 唯一语义声明：`// FWSEC writes 0xFF value in NV_PMC_SCRATCH_RESET_PLUS_2 register after completion of boot`；
  判据是**整字等于 0xFF**：`kernel_sec2_gb20b.c:525-527`（`_ksec2WaitBootCond_GB20B`，返回 `reg == 0xFF`）。
  另一个读取点是失败时的调试打印 `"FWSEC Completion = 0x%x"`：`kernel_sec2_gb20b.c:859-860`。
- 这里的 "FWSEC" 就是**跑在 SEC2 上的安全启动分区固件**（同文件把同一条链叫 FWSEC：`:997` "FWSEC timed out
  processing COT command"、`:1044/:1108` "FWSEC failed to process boot command"）⇒ 这条判据的真实含义是
  **"SEC2 的 FWSEC 固件启动完成"**。

**(c) 为什么实测 0 而驱动正常** ✅[源]
- **GB202 根本不会执行这个等待**：`ksec2WaitForSecureBoot` 的 HAL 绑定只给 `GB20B | GB20C`
  （`g_kernel_sec2_nvoc.c:859-866`，mask `0x000000c0` 是 group2 的 bit6/bit7 = idx 70/71；GB202 是 idx 65 = bit1），
  GB202 落到 default `ksec2WaitForSecureBoot_395e98`，其实现是 `return NV_ERR_NOT_SUPPORTED;`
  （`g_kernel_sec2_nvoc.h:888-890`）。
- 这个等待只被两处调用：`ksec2PrepareBootCommands_GB20B`（`kernel_sec2_gb20b.c:992`）和 BIF 的 FLR 路径
  `kbifDoFunctionLevelReset_GH100`（`kernel/gpu/bif/arch/hopper/kernel_bif_gh100.c:1054-1063`，**只有在 FSP 缺失时**
  才走 SEC2 分支）。本机 FSP 存在（见 §2.3 的 FSP HAL 绑定），所以两条都不走 SEC2。
- GB202 自己也**没有发布** `NV_PMC_ZB_SCRATCH_RESET_PLUS_2`（`gb202/dev_boot_zb.h` 里只有 `NV_SYSCTRL_SEC_FAULT`）。
- 实测 0 在**两种 GPU 状态下都是 0**（14:06 与 14:09 两次 PEEK，§1.1）⇒ 这个 scratch 在本机确实**没人写**。
  **结论：0 是"这条 GB20B 约定在 GB202 上不适用"，不是"SEC2 没起来"。**

**(d) 是否还有第二个"FWSEC/boot 完成"判据** —— 有 5 个候选，按"对本机是否有效"排序：

| # | 判据 | 寄存器/绝对偏移 | 有效范围 | 出处 |
|---|---|---|---|---|
| 1 | **FSP boot 完成（本机真正在用的那一条）** | `NV_THERM_I2CS_SCRATCH = 0x00AD00BC`，值 `0xFF` | **GB202 绑定**（mask `0x0000303e`） | `gb202/dev_therm.h:27`、`gb202/dev_therm_addendum.h:27-30`、`kern_fsp_gb202.c:50-61`、`g_kern_fsp_nvoc.c:494-497` |
| 2 | **FWSEC/FSP 的版本与进度 scratch（最有用，见 §2.3）** | `PBUS SW_SCRATCH(i) = 0x1400 + 4i`（**绝对偏移**）：i=0 `FWSEC version`、i=2 `Devinit version`、i=12 `Devinit Boot Status`、i=15 `Failing Register Addr`、i=16 `Devinit PC`、i=28 `PRI error code`、i=52 `FRTS Completion`、i=54 `COT Polling Status` | 由 GB100 发布 + `gpuReadPBusScratch_GB100`（GB202 走 default 分支 ⇒ 用的就是它） | `gb100/dev_bus.h:27`、`gb100/hwproject.h:35`、`kern_gpu_gb100.c:1765-1772`、`g_gpu_nvoc.c:979-995`、`kernel_sec2_gb20b.c:850-887` |
| 3 | **FWSEC 错误现场** | `NV_PSEC_FALCON_COMMON_SCRATCH_GROUP_2(0..3) = 0x840320+4i`（0=无错） | 表里有；但本机**读被拒**（0xBADF5108，见下） | `gb20b/dev_sec_pri.h:62-67`、`kernel_sec2_gb20b.c:862-872` |
| 4 | GFW_BOOT 进度（"先确认 FWSEC 降低了它的 PLM"） | `NV_PGC6_AON_SECURE_SCRATCH_GROUP_05_PRIV_LEVEL_MASK = 0x118128` + `..._05(0) = 0x118234`，`PROGRESS == 0xFF` | **只绑 TU102..AD107**（`g_gpu_nvoc.c:2635-2650`）⇒ 对 GB202 不生效，且 Blackwell 没发布 PGC6 | `turing/kern_gpu_tu102.c:395-445`、`turing/tu102/dev_gc6_island*.h` |
| 5 | **SEC2 故障位（把 SEC2 当被监控引擎）** | **PCI config DVSEC** `NV_EP_PCFG_GPU_VSEC_DEBUG_SEC_1 = 0x2B4`（`SEC2_SCPM 15`、`SEC2_DCLS 16`、`SEC2_L5_WDT 17`） | **GB202 自己发布**，`gpuHandleSecFault_GB202` 解码 | `gb202/dev_boot_zb.h:41-43`、`gb202/dev_xtl_ep_pcfg_gpu.h:27-28`、`kern_gpu_gb202.c:192-243` |

> 注意 4：`gpuWaitForGfwBootComplete_TU102` 用的 `kflcnWaitForHalt`（等 GSP falcon HALT）+ PGC6 GFW_BOOT 组合，
> 是"另一个家族"的 boot 完成判据，**不能搬到 GB202**（HAL 未绑定 + 头文件未发布）。

**(e) `0x840100` 的位定义 —— 它不在 `dev_sec_pri.h` 里** ✅[源]

- `dev_sec_pri.h`（gb10b/gb20b）**没有任何 0x840100 条目**。gb10b 只发布 `NV_PSEC_FALCON_MAILBOX0/1 = 0x840040/0x840044`
  （`gb10b/dev_sec_pri.h:27-31`）。`0x840100` 属于 **falcon v4 标准块**：PSEC 的 falcon 基址 = `0x840000`
  （由 MAILBOX 在 falcon+0x40 反推），因此 `0x840100 = NV_PFALCON_FALCON_CPUCTL`。
- 位定义（`turing/tu102/dev_falcon_v4.h:46-56`；`ampere/ga102/dev_falcon_v4.h:109-120` 逐位相同）：
  `STARTCPU 1:1`（**`-WXVF` 只写**）、**`HALTED 4:4`（`R-XVF` 只读）**、`ALIAS_EN 6:6`（RW）。
- ⇒ **实测 `0x840100 = 0x00000010` ⇒ bit4 `HALTED = 1`**。驱动自己对 falcon 的用法可以校准这个语义：
  `kflcnWaitForHalt_HAL` 就是**等** `CPUCTL.HALTED == TRUE`（`kernel_falcon_tu102.c:345-346`），
  而启动是写 `CPUCTL.STARTCPU`（`:246-247`）。
- **更正上一轮**：`bit4 == 0 ⇒ 核在跑` 是错的。`HALTED=1` 只说明核**现在没在取指**（上电默认就是 halt；
  固件跑完执行 HALT 也是 halt）。⇒ **它既不能证明"在跑"，也不能证明"死了"**；而且本机在**无驱动状态**下
  同一偏移读到 `0xbadf5620`（读被拒）⇒ 单点值不可用作判据。

**(f) 顺带更正 `0x840320 = 0xBADF5108` 的解读** ✅[源]+❓[推测]
- `0xBADF0000 / 0xFFFF0000` 是 **falcon CSB 特权 PRI 错误族**（`nvidia/arch/nvalloc/common/inc/flcnretval.h:256-257`）；
  host 侧 NV 读路径也把 `(v & 0xFFF00000) == 0xBAD00000` 判成 PRI 读错误（`g_gpu_nvoc.h:6097-6098`）。
- 本机在**另一块**（FSP 的受保护区 0x8f0000..0x8f03ff）批量读到**同族**的 `0xbadf5620`
  （`guest_dmesg_emem3_1003.txt:3-40`，例如 `pre 8f0000: badf5620 ...`）。
- ⇒ 更合理的解释：**"host 读这个偏移被拒绝"**，而不是"FWSEC 在 scratch 里写了 0xBADF5108"。
  若真如此，`0x840320` 里的 FWSEC 错误码**我们读不到**（=未知，不是"有错"）。
- 可验证的只读线索（❓[推测]，需下轮实测）：`0x8403F8 = NV_PSEC_FALCON_COMMON_SCRATCH_GROUP_2__PRIV_LEVEL_MASK`
  （`gb20b/dev_sec_pri.h:65`）——如果它显示读保护使能，就坐实"被 PLM 挡住"；同时把 `0x840300..0x84031C`
  与 `0x840328/0x84032C` 一起读：若整段都返回同一 suffix 的 `0xBADFxxxx`，就是"整段被保护"而非"单个错误码"。

### 2.2 问题 2：队列寄存器是"索引/计数"还是"地址/偏移"？单位最终结论；正确写形式

**结论：是 EMEM 通道内的"偏移（地址）"，单位 = 字节。** ✅[源]

| 证据 | 内容 | 出处 |
|---|---|---|
| 字段名 | `NV_PSEC_QUEUE_HEAD_ADDRESS / _TAIL_ADDRESS`（31:0），INIT = 0（FSP 侧同名 `NV_PFSP_QUEUE_*_ADDRESS`） | `gb20b/dev_sec_pri.h:44-51`、`gb10b/dev_sec_pri.h:32-39`、`hopper/gh100/dev_fsp_pri.h:53-60` |
| 写侧（3 条独立路径，全是字节） | `paddedSize = NV_ALIGN_UP(packetSize, 4)`（字节）→ `TAIL = paddedSize - sizeof(NvU32)`，注释明确 "TAIL points to the last DWORD written, so subtract 1 DWORD"；`HEAD = 0`，注释 "RM always starts at offset 0" | `kernel_sec2_gb10b.c:704,707-708`；`kern_fsp_gh100.c:648,650-651`；`common/nvswitch/kernel/fsprpc_nvswitch.c:326-343`（"Pad to align size to 4-bytes boundary since EMEMC increments by DWORDS"） |
| 读侧（字节） | `packetSize = (msgqTail - msgqHead) + sizeof(NvU32)`，随后**读 `packetSize/4` 个 dword**，并断言 `EMEMC(OFFS+BLK*64) == packetSize/4` | `kernel_sec2_gb20b.c:479,499,514`；`kern_fsp_gh100.c:688,708,723` |
| 谁更新谁 | host 写 TAIL 再写 HEAD（**HEAD 的写 = 门铃/中断**）；固件收完后把 `HEAD = TAIL`。"空" = `HEAD == TAIL` | `kernel_sec2_gb10b.c:81-83,355`；`kern_fsp_gh100.c:104-106,263`；`kernel_sec2_gb20b.c:93-94,159` |
| **本机实测闭环**（✅[实测]） | FSP 回包结构长度 = 20 B；固件写的 `MSGQ_TAIL = 0x10 = 16` ⇒ `(16-0)+4 = 20` ✅ 字节（dword 语义会得 68 B ❌） | `guest_dmesg_emem4_1008.txt:4`、`guest_dmesg_emem5_1010.txt:3-5` + `nvdm_payload_cmd_response.h:35-42` |
| **单位关系（最终定论）** | 同一 1 KB 通道，**QUEUE/MSGQ 用字节**，**EMEMC 的 OFFS 7:2 / BLK 15:8 用 dword**（BLK 一块 = 64 dword = 256 B）。本机旁证：`0x8f2ac0 = 0x02000014` ⇒ `AINCR=1, OFFS=5`（=20 B，与 20 B 回包吻合）；早前 `0x02000020` ⇒ `OFFS=8`（=32 B）⇒ 该字段随真实传输变化（❓[推测]：与某次 20 B 传输对应，非同一次运行的直接日志） | `kernel_sec2_gb10b.c:189-202`（读写循环）、`:205-210` / `kernel_sec2_gb20b.c:506-514`（dword 自检）、`gb20b/dev_sec_pri.h:28-31`；实测日志 `guest_dmesg_emem3_1003.txt:1` + 本机 `0x8f2ac0 = 0x02000014` |

> **对"dword vs byte 冲突"的最终结论**：**字节**。既有 FSP 工具的
> `iowrite32((len+3)/4-1, QTAIL)`（`/home/user/fsp_probe/fsp_emem_mod.c:76`）与
> `dw = (tail-head)+1`（`:34-36`）都是错的；它同一份日志里的"响应字节≈20（= tail-head+4）"才是对的那个公式。
> 两者在**单 dword（≤4 B）报文**上恰好都给 0，所以小报文试验会"看起来能用"（解释见下）。

**若要在 GB202 上按 SEC2 的方式发一条消息，正确形式是**（仅形式说明，本轮**不执行**）：
```c
/* 通道 0；基址：EMEMC=0x840ac0 EMEMD=0x840ac4 QUEUE_HEAD=0x840c00 QUEUE_TAIL=0x840c04 */
padded = (len + 3) & ~3u;                 /* 字节 */
wr(EMEMC(0), 0x01000000);                 /* OFFS=0,BLK=0,AINCW=1  → 从通道首 dword 开始写 */
for (i = 0; i < padded/4; i++) wr(EMEMD(0), dw[i]);   /* 不足 4B 的尾字节补 0 */
wr(QUEUE_TAIL(0), padded - 4);            /* **字节**偏移：最后一个 dword 的首字节位置 */
wr(QUEUE_HEAD(0), 0);                     /* 门铃；必须在 TAIL 之后写（会中断 SEC2） */
```
- 860 B 的 COT ⇒ `padded = 860`，`TAIL = 856`（**不是** 214）。
- 读回包：`bytes = (MSGQ_TAIL - MSGQ_HEAD) + 4`；`EMEMC(0) = 0x02000000`（AINCR）；读 `bytes/4` 个 `EMEMD`；
  ACK = 把 `MSGQ_TAIL`/`MSGQ_HEAD` 一起写成 `MSGQ_HEAD`（`kernel_sec2_gb20b.c:479,490,499-503,511-512`）。

**GB202 的两个"实测异常"，必须写进结论**（✅[实测] + ❓[推测]）：
1. 本机 SEC2 通道 0 空闲时读到的**不是 0**：`QUEUE_HEAD = QUEUE_TAIL = 0x01000100`、
   `MSGQ_HEAD = MSGQ_TAIL = 0x01000040`（而 FSP 侧空闲读 0）。
   两种解读：**(i)** 固件把游标留在了非零位置（`HEAD==TAIL` ⇒ 仍然"空"），
   `0x0100/0x0040` 恰好能用 gb20b 的 EMEMC 字段布局解读成 `BLK=1,OFFS=0`（=64 dword=256 B）与
   `BLK=0,OFFS=16`（=16 dword=64 B）——都落在 1 KB 通道内，**自洽**；
   **(ii)** 把它们当"纯 32-bit 字节偏移"读就是 16 MB，超出通道 ⇒ GB202 上 SEC2 的这套寄存器**编码与 GB20B 文档不同**。
   ❓[推测] 我更倾向 (i)（因为 `0x01000100` 的高 16 位 = 0x0100 = 256 dword = **1 KB 通道容量**，像是容量/状态字段），
   但不能静态定论。
2. 不管哪种解读，**驱动模型的"未用过就是 0/0"基线在 GB202 上不成立** ⇒ 手工发送时
   **我们无法自检自己的 bookkeeping**（既不能判断"空"，也不能预测固件会怎么解释我们写的 TAIL）。
   这是"不要发"的又一条硬理由。

### 2.3 问题 3：SEC2 在 GB202 上是否真的在跑？只读判据

**(a) 源码层面：GB202 的 open RM 对 SEC2 只有"配置 + 不通信"** ✅[源]
- GB202（chipHal idx **65**，`g_chips2halspec_nvoc.c:129-133`）落到的 ksec2 HAL：
  `ksec2ConfigureFalcon_GA102`（`g_kernel_sec2_nvoc.c:569`，只登记 base：`registerBase=DRV_BASE(NV_PSEC)=0x840000`、
  `riscvRegisterBase=NV_FALCON2_SEC_BASE=0x841000`，`kernel_sec2_ga102.c:46-47`）、
  `ksec2StateLoad_GH100`（`:606`，只做 CC 密钥派生，`kernel_sec2_gh100.c:30-46`）、
  `ksec2ReadUcodeFuseVersion_GB100`（`:648`，读 fuse）。
- **所有 EMEM 收发/读回/ACK HAL 对 GB202 都是 default 桩**（mask 里只有 `GB10B|GB20B|GB20C`：
  `g_kernel_sec2_nvoc.c:780-796,804-808,827-831,838-842,860,871,882,893,904,915`），
  default 体就是 `NV_ERR_NOT_SUPPORTED` / `NV_FALSE` / `0`（`g_kernel_sec2_nvoc.h:876-901`；
  `ksec2IsResponseAvailable` 默认 `NV_FALSE`）。
- `gpuBootGspRmProxy`（`gpu.c:7860-7890`）**优先 FSP**：`if (pKernelFsp != NULL) return kfspPrepareAndSendBootCommands(...)`；
  本机 FSP 存在（GB202 绑定 `kfspSendPacket_GB100` / `kfspReadPacket_GB100` / `kfspWaitForSecureBoot_GB202`：
  `g_kern_fsp_nvoc.c:351,367,494-497`）⇒ **永不走 SEC2**。
- 另外三条"FWSEC 主机协议"（FWSECLIC：`kgspPrepareForFwsecSb/ExecuteFwsec`）也**只绑 TU102..AD107**
  （`g_kernel_gsp_nvoc.c:1406-1458`）⇒ Blackwell 上 open RM 里**没有任何 FWSEC 主机协议**。
- 唯一的"SEC2 存在"证据是软件属性：`PDB_PROP_KSEC2_IS_MISSING` 在所有芯片上都被设成 `NV_FALSE`
  （`g_kernel_sec2_nvoc.c:471-472`），以及 GB202 自己发布了 SEC2 的故障位（`gb202/dev_boot_zb.h:41-43`）
  ⇒ **GB202 硅片上有 SEC2（=FWSEC 引擎），但本机驱动从不与它通信、也不检查它是否在跑。**

**(b) 只读判据清单（具体到偏移与期望值模式）**

| 判据 | 偏移 | 期望/解读 | 为什么可信 | 等级 |
|---|---|---|---|---|
| SEC2 域是否被上电/解除复位（**本机最强**） | `0x840040/0x840044`、`0x840100`、`0x840AC0..`、`0x840C00/04`、`0x840C80/84` | **必须与"状态对照"一起看**：驱动卸载/未 devinit 时这一批 = 0（`0x840100` = 特权毒）；devinit + 显示活动后 = `0xe6513000/0x74000007/0x10/0x02000040/0x01000100/0x01000040`，**跨一次 unload/reload 完全可重复** | 本机两次 PEEK vs 一次 150 s PANY，见 §1.1；`/home/user/peek/*.c` 读法已公开可复核 | ✅[实测] |
| SEC2 falcon 块是否可访问 | `0x8400F4 = NV_PFALCON_FALCON_HWCFG2`（`gb20b/dev_falcon_v4.h:27`） | 非 0 且 `(v & 0xFFFFFF00) != 0xBADF4100` ⇒ 该 falcon 目标未锁死。**这正是驱动给 GSP falcon 用的活体判据**（`kernel_sec2_gb10b.c:264-283`） | 驱动源码里同型判据 | ✅[源]+⚠️[同族]（GB202 未单独实测） |
| SEC2 核是否"跑过" | `0x840008 = FALCON_IRQSTAT`（`R--4R`），`HALT 4:4` | `IRQSTAT.HALT == 1` 且 `CPUCTL.HALTED == 1` ⇒ 核**执行过 HALT 指令**（= 固件至少跑到了空闲点）。仅 `HALTED=1` **不能**证明跑过 | `tu102/dev_falcon_v4.h:30-33`、`ga100/dev_falcon_v4.h:37-41`（IRQSCLR 才是清位，**读 IRQSTAT 不是读即清**） | ⚠️[同族] + ❓[推测] |
| SEC2 是否正在处理 host 命令 | `0x840040 = MAILBOX0` | `== 0xC001CAFE` ⇒ 正在处理（GB10B 约定）；本机 `0xe6513000` ⇒ **空闲** | `kernel_sec2_gb10b.c:289-297`、超时打印 `:617-628` | ✅[源]（语义）/ ✅[实测]（值） |
| 是否有"给 host 的消息"待取 | `0x840C80/84 = MSGQ_HEAD/TAIL` | `HEAD != TAIL` ⇒ SEC2 主动发过消息（本机驱动在 GB202 上**不会**去 ACK，所以这是"活着"的强信号）；本机 `HEAD == TAIL` ⇒ 空 | `kernel_sec2_gb20b.c:148-161` | ✅[源] / ✅[实测]：空 |
| 是否有未收的 host→SEC2 命令 | `0x840C00/04` | `HEAD == TAIL` ⇒ 无在飞命令（本机相等 ✅）；**不等** ⇒ 有人投过/投了一半 | `kernel_sec2_gb10b.c:343-357` | 同上 |
| **FWSEC（SEC2 固件）是否记录过版本/进度** | **`0x1400`**(FWSEC version)、`0x1408`(Devinit version)、`0x1430`(Devinit Boot Status)、`0x143C/0x1440`(Failing Reg Addr / Devinit PC)、`0x1470`(PRI error code)、`0x14D0`(FRTS Completion)、`0x14D8`(COT Polling Status) | 非 0 / 特定进度值 ⇒ 该固件阶段执行过并留下记录。**这是最接近"FWSEC 完成"的 GB202 可用判据** | `kernel_sec2_gb20b.c:850-887` 直接把这些偏移当代号读（`pEntry->devicePriBase + NV_PBUS_ZB_SW_SCRATCH(i)`），而 `NV_PBUS_ZB_SW_SCRATCH(i) = 0x400+4i` 是**相对 PBUS 基址**、GB100 又发布了**绝对** `NV_PBUS_SW_SCRATCH(i) = 0x1400+4i`、且 `NV_PBUS0_PRI_BASE = 0x1000` 与之自洽；GB202 走 `gpuReadPBusScratch_GB100` default 分支 | ✅[源]（偏移）+ ❓[推测]（GB202 上是否真有人写） |
| **SEC2 故障（读只，无需 BAR）** | **PCI config DVSEC `0x2B4`**（`NV_EP_PCFG_GPU_VSEC_DEBUG_SEC_1`，bit15/16/17 = `SEC2_SCPM/SEC2_DCLS/SEC2_L5_WDT`） | 全 0 ⇒ 安全块没有报告 SEC2 故障。注意：`SEC_FAULT` 一旦置位**只有冷复位能清**（`kern_gpu_gb202.c:282`） | `gb202/dev_boot_zb.h:41-43`、`gb202/dev_xtl_ep_pcfg_gpu.h:27-28`、`kern_gpu_gb202.c:192-243` | ✅[源] |
| SEC2 固件镜像存在性（静态，非活性） | `0x824140 + 4i`（i=0..15） | 非 0 = 该 slot 有签名镜像；版本 = 最高位+1。本机 `0x824140 = 0x2` ⇒ 版本 2、**两种 GPU 状态下都一样** | `kernel_sec2_gb100.c:38-59`、`gb100/hwproject.h:31`、`gb100/dev_fuse_zb.h:37-40` | ✅[源]/✅[实测] |
| 对照（证明读取方法学 OK + GPU 醒着） | `0x000000`（PMC BOOT_0）= `0x1b2000a1`、`0x8F2AC0`（FSP EMEMC）非 0、`0x824140` | 三者在本机**两种状态下都可读** ⇒ 恒开域正常；**不能**用来判断 SEC2 域是否上电 | §1.1 | ✅[实测] |

**(c) 为什么可信 / 为什么不够**
- 可信的部分：`MSGQ HEAD!=TAIL`、"`MAILBOX0 == 0xC001CAFE`"、"falcon HWCFG2 非毒" 都是**驱动自己在用的判据**，
  语义有源码背书；PBUS SW_SCRATCH 的**绝对偏移**有 GB100 发布表背书（且 fuse 基址 0x820000+0x4140 已被本机实测
  印证 ⇒ GB202 确实复用 GB100 的这些子块映射）。
- 不够的部分（必须诚实）：① **没有任何随时间的计数器/心跳** 被发布（`gb202/`+`gb20b/` 的 SEC2 相关头文件只有
  EMEM/QUEUE/MSGQ/scratch + falcon 的 HWCFG2）；② `0x840320`（FWSEC 错误码）**读被拒**，所以"FWSEC 无错"这件事
  在 host 侧**无法证实**；③ 只读值会随 **GPU 电源状态**变化（§1.1 的 0/毒 ↔ 结构化值），
  一次"读到 0"很可能是**块被门控**而不是"SEC2 停了"。
- **可操作定义（建议下轮用）**：一次"SEC2 已启动"的判定 =
  ① 控制读数证明 GPU 在 D0（`0x824140`、`0x8F2AC0` 可读）
  ② `0x8400F4` 非毒 + `0x840100` 可读（= PSEC 域已被 devinit 打开）
  ③ `0x1400`(`FWSEC version`) 或 `0x1430`(`Devinit Boot Status`) 非 0（= FWSEC 阶段留过记录）
  ④ `0x840C80 == 0x840C84`（无待取回包）+ `0x840040 != 0xC001CAFE`（不在处理命令）。
  四条同时成立 ⇒ 可以说"SEC2 已被启动并处于空闲"，而不是"SEC2 没跑"。

### 2.4 问题 4：风险再确认

**(a) 只读队列/信箱/状态是否安全？——基本安全，但有 3 个例外要避开** 

- ✅ 经验证据（✅[实测]）：上一轮 PEEK 已在两种状态下读过这批偏移；PANY 更是 **5630 轮 × 18 寄存器 × 150 s**
  连续读，随后驱动正常重载、显示正常、**journal 里零 Xid、零 SEC_FAULT**（`journalctl -k | grep -i xid` 无输出）。
  ⇒ 对这些**文档内偏移**做只读**没有留下可见后果**。
- ⚠️ 三个例外（逐个点名）：
  1. **`0x840AC4 = NV_PSEC_EMEMD(0)`：读会改变状态。** 实测 `0x840AC0 = 0x02000040` ⇒ `AINCR(bit25) = 1`
     （`gb20b/dev_sec_pri.h:36-39`），而 AINCR 的定义就是"读 EMEMD 时自动推进 OFFS/BLK"
     （读侧自检代码 `kernel_sec2_gb20b.c:499-514`、写侧同理 `kernel_sec2_gb10b.c:189-202`）。
     → 上一轮每读它一次，通道 0 的读游标就前进 1 个 dword；PANY 若把它放进采样列表就是 5630 次。
     本机没出事，但**这不是"纯读"**。建议：**把 `0x840AC4` 从采样列表里拿掉**；要读先读 `0x840AC0`，
     只有 `AINCR/AINCW 都为 0` 时才读 `EMEMD`（注意我们**不能**去写 EMEMC 清零那两个位——那属于"写"）。
  2. **`0x842AC0 / 0x842C00` 这类"猜出来的窗口"返回 `0xBADF5040`**：这是"读不存在/被拒的实现"。
     单次读无害，但按 NVIDIA 自己的模型，PRI 错误的访问原则上可能点亮 `SEC_FAULT` 类的 sticky 位
     （`IFF_PRI_ERROR`、`FLCN_CSB_PRIV_PRI_ERROR`；且 `kern_gpu_gb202.c:282` 明说 **只有冷复位能清 SEC_FAULT**）。
     本机反复读都没点着 ⇒ 对当前这批偏移**实测安全**；但它不是"零风险"，**别做随机地址扫描**（尤其别连续爆破
     非文档偏移）。
  3. **`0x840100` 的取值本身不稳定**（`0x10` ↔ `0xbadf5620`）⇒ 不要把它当"绝对健康位"用；
     它只是"当前可读/不可读"的状态指示。
- 另注：GB202 上**不存在**"读一下就把 SEC2 唤醒/启动"的路径（没有任何 GB202 主机侧 SEC2 HAL），
  所以只读不会"顺手启动 SEC2"。

**(b) "发送"是否仍应一律禁止？——是，仍然一律禁止**（上一轮结论不变，且本轮新增 3 条理由）
1. 源码里主机→SEC2 **唯一有发送路径**的类型就是 **COT（0x14）**（`kernel_sec2_gb20b.c:1074`、
   `kernel_sec2_gb10b.c:600`），即启动安全链本身；INFOROM/HULK 只有 SEID 路由痕迹（`gb20b:186-194`）。
   发错 = 拿"RM 本次 devinit 能否起来"去赌（失败路径 `:1108` + `ksec2DumpDebugState`）。
2. GB202 的 SEC2 EMEM HAL 全是桩 ⇒ **没有经过验证的 GB202 发送配方**（§2.3a）。
3. **本轮新增**：GB202 上这套寄存器的**空闲基线不是 0/0**（`0x01000100 / 0x01000040`），
   说明要么固件留了非零游标、要么 GB202 的字段编码与 GB20B 文档不同 ⇒ **写入值的语义无法自证**，
   "报 4 倍长度（越过 1 KB 通道）"或"写到错误位置"的风险比上一轮评估的更高。
4. 另：`QUEUE_HEAD` 的写就是**中断/门铃**（`kernel_sec2_gb10b.c:81-83`），
   "随便写个 head 看看"= 让固件去读一段长度由 TAIL 决定的半成品报文。

**(c) 有没有"读即清"（读一下就改变状态）的寄存器？逐个点名** ✅[源]

在**已发布的 SEC2 寄存器集合**（`gb10b/gb20b/dev_sec_pri.h` + falcon v4 映射）里：
- **没有任何 `R-C`（read-clear）属性的寄存器**：所有项都是 `RW-4A/RW-4R`（scratch、EMEMC/D、QUEUE、MSGQ、
  MAILBOX、CPUCTL、OS/RM、HWCFG/HWCFG2、DMACTL 状态位…）。
- 但下面这些**读是安全的、写是危险的**（真正的"不能碰"名单，建议写进禁区表）：

| 偏移 | 名称 | 为什么危险 | 出处 |
|---|---|---|---|
| `0x840AC4 + 8i` | `NV_PSEC_EMEMD(i)` | **读有副作用**（AINCR=1 时推进游标，实测已 armed）；写会改共享 SRAM | `gb20b/dev_sec_pri.h:40-42` |
| `0x840AC0 + 8i` | `NV_PSEC_EMEMC(i)` | 写 = 改变通道游标/自增方向（读安全） | `:26-39` |
| `0x840C04 / 0x840C00` | `QUEUE_TAIL / QUEUE_HEAD` | 写 = 生产者指针 + **门铃中断** | `:44-51`、`kernel_sec2_gb10b.c:81-83` |
| `0x840C84 / 0x840C80` | `MSGQ_TAIL / MSGQ_HEAD` | 写 = ACK/消费（会丢弃或错位固件已排队的回包） | `:53-60`、`kernel_sec2_gb20b.c:84-95` |
| `0x840004`（falcon+0x04） | `NV_PFALCON_FALCON_IRQSCLR` | **只写**寄存器；写 = 清中断（读本身无害） | `tu102/dev_falcon_v4.h:27-31` |
| `0x840010 / 0x840014 / 0x840018 / 0x84001C` | `IRQMSET / IRQMCLR / IRQMASK / IRQDEST` | 写会改中断投递（`IRQMSET/MCLR` 为只写） | `:35-41` |
| `0x840100` | `FALCON_CPUCTL` | `STARTCPU(bit1)` 是**只写**；写下去 = 启停 SEC2 核 | `:46-49`、`kernel_falcon_tu102.c:246` |
| `0x840130` | `FALCON_CPUCTL_ALIAS` | 写 = 别名方式 STARTCPU | `:50-56` |
| `0x84010C` | `FALCON_DMACTL` | 写可触发 IMEM/DMEM scrub（`SCRUBBING` 位本身是只读状态） | `:60-66` |
| `0x8403C0`（⚠️[同族]） | `NV_PSEC_FALCON_ENGINE.RESET(bit0)` | 写 = **复位 SEC2 引擎** | `ampere/ga100/dev_sec_pri.h:28-31` |
| `0x8403F8` | `NV_PSEC_FALCON_COMMON_SCRATCH_GROUP_2__PRIV_LEVEL_MASK` | 写 = 改读/写保护级别（**读它很有价值**，见 §2.1f） | `gb20b/dev_sec_pri.h:65` |
| `0x840300..0x84031C` | `FALCON_COMMON_SCRATCH_GROUP_0/1`（`tu102` 表：`0x300+4i` / `0x310+4i`） | 普通 scratch（读安全） | `tu102/dev_falcon_v4.h:119-122` |
- **结论**：`QUEUE_HEAD/TAIL`、`MSGQ_HEAD/TAIL`、`MAILBOX0/1`、`CPUCTL`、`HWCFG2`、`IRQSTAT`、
  `SCRATCH_GROUP_2`、PBUS SW_SCRATCH 全部**可以只读**；**唯一"读不纯"的是 `EMEMD`**（在 AINCR 已 armed 的当前状态下）。
  **未被文档覆盖的 0x842xxx / 0x840100（不同状态下）等偏移读回特权毒**：单次读实测无后果，但不要成规模扫。

---

## 3. 与上一轮报告（`DS_SEC2_INTERFACE_20260926.md`）的差异/更正

| # | 上一轮说法 | 本轮更正 | 依据 |
|---|---|---|---|
| 1 | `0x840100 bit4 == 0 ⇒ 核在跑` | **错了**：bit4 = `HALTED`（只读），`1` = 核处于 halt/空闲；实测 `0x10` ⇒ `HALTED=1`。该寄存器还随 GPU 状态在"可读"与"特权毒"之间切换，不能单独当判据 | `tu102/dev_falcon_v4.h:46-49`、`ga102/dev_falcon_v4.h:111-115`、`kernel_falcon_tu102.c:345-346`；journal `0x840100 = 0x10` vs `0xbadf5620` |
| 2 | `0x840320 = FWSEC 错误码 = 0xBADF5108`（⇒ 报过错） | 更可能是**host 读取被拒**（`0xBADFxxxx` = falcon CSB 特权 PRI 错误族；同型 `0xbadf5620` 在 FSP 受保护区也批量出现）⇒ FWSEC 错误码**未知**，不是"有错" | `flcnretval.h:256-257`、`g_gpu_nvoc.h:6097-6098`、`guest_dmesg_emem3_1003.txt:3-40` |
| 3 | `PMC 0x5E0 == 0xFF` 作为"最安全只读指纹"之一 | **对 GB202 无效**：GB202 的 wait HAL 是 `NOT_SUPPORTED` 桩，从不读它；本机实测恒 0（两种状态都是 0）。GB202 用 FSP 的 `0xAD00BC == 0xFF` | `g_kernel_sec2_nvoc.c:859-866`、`g_kernel_sec2_nvoc.h:888-890`、`kern_fsp_gb202.c:50-61` |
| 4 | `QUEUE_TAIL` 单位"必须先定论"（§1.7 悬置） | **已定论：字节**（并有本机实测闭环：FSP 的 `MSGQ_TAIL=0x10` ↔ 20 B 回包）。既有的 `emem_cli`/`fsp_emem_mod` 的 `len/4-1`、`(tail-head)+1` 是错的 | `kernel_sec2_gb10b.c:704-708`、`kernel_sec2_gb20b.c:479,514`、`kern_fsp_gh100.c:648-651,688,723`、`fsprpc_nvswitch.c:326-343`、`guest_dmesg_emem*_10*.txt` |
| 5 | `EMEMC(0)` 的 `AINCR=1` 可当"上一次传输被中断"的指纹 | **不能**：FSP 侧同样长期 `AINCR=1` 且 OFFS 随真实传输变化（`0x02000020` → `0x02000014`）⇒ 这是**正常使用痕迹**，不是错误状态；而且 `0x840AC4` 读一次就推进它 | `guest_dmesg_emem3_1003.txt:1`、`kernel_sec2_gb20b.c:499-514` |
| 6 | "SEC2 的 EMEM 块在 GB202 上看起来是活的（值是结构化的）" | **要降温**：结构化值只在"驱动 + 显示活动"状态下出现，驱动卸载后同一批偏移全 0、`0x840100` 变毒；而且空闲基线**不是** 0/0（`0x01000100`/`0x01000040`）⇒ "活的"最多说明"PSEC 域在 devinit 后被上电/可访问"，**不能**说明 SEC2 固件在跑 | journal 14:06 / 14:09 / 14:10 三次采样（§1.1） |

---

## 4. 建议的下一轮"只读"探测清单（全部零写入；本轮未执行）

```text
【A. 先确认 GPU 在 D0 + 控制读数（恒开域，必须与 B 同时成立）】
  0x000000      PMC BOOT_0                  期待 0x1b2000a1
  0x824140      FUSE SEC2 UCODE1_VERSION    期待 0x2（非 0 ⇒ 有签名镜像）
  0x8F2AC0      FSP EMEMC                   期待非 0（本机 0x02000014）

【B. SEC2/FWSEC 进度（GB202 关键新增）】
  0x1400  PBUS SW_SCRATCH(0)   "FWSEC version"        ← 非 0 是最有价值的"FWSEC 跑过"证据
  0x1408  PBUS SW_SCRATCH(2)   "Devinit version"
  0x1410  PBUS SW_SCRATCH(4)   ?（留空位观察）
  0x1430  PBUS SW_SCRATCH(12)  "Devinit Boot Status"
  0x143C  PBUS SW_SCRATCH(15)  "Failing Register Addr"
  0x1440  PBUS SW_SCRATCH(16)  "Devinit PC"
  0x1470  PBUS SW_SCRATCH(28)  "PRI error code"
  0x14D0  PBUS SW_SCRATCH(52)  "FRTS Completion"
  0x14D8  PBUS SW_SCRATCH(54)  "COT Polling Status"

【C. PSEC（SEC2）块存在的证据 —— 只看不改】
  0x8400F4      FALCON_HWCFG2              非 0 且非 0xBADF41xx
  0x840008      FALCON_IRQSTAT             bit4(HALT) 是否 1（配合 0x840100 的 HALTED）
  0x840100      FALCON_CPUCTL              只读；注意它会"可读↔毒"切换
  0x840040/44   MAILBOX0/1                 != 0xC001CAFE；非 0 才说明有东西写过
  0x840C00/04   QUEUE_HEAD/TAIL            两者相等 ⇒ 空
  0x840C80/84   MSGQ_HEAD/TAIL             两者相等 ⇒ 无待取回包（不等 ⇒ SEC2 活着且发过消息）
  0x840AC0      EMEMC(0)                   只读：看 AINCW/AINCR/OFFS/BLK 状态
  0x8403F8      SCRATCH_GROUP_2 PLM 掩码    ← 读它能解释 0x840320 为什么是特权毒
  ⚠️ 不要放进采样列表： 0x840AC4（EMEMD，读即推进游标）
  ⚠️ 不要扩大扫描：0x842xxx 等非文档偏移（返回 0xBADFxxxx）；不要碰 0x840300..0x84032C 之外的随机地址

【D. 想做"活性 A/B"（本机已证明有效，且是零写入）】
  在驱动卸载窗口与"驱动 + 显示活动"窗口分别读【C】那批 → 期望看到 0/毒 ↔ 结构化值 的翻转；
  这说明 PSEC 域的电源/复位状态，而不是 SEC2 固件的执行状态。
  注意：严格说这是"改驱动状态"而不是"改寄存器"，但按本轮约束，是否做这一步请由你（父代理）决定。

【E. 不要做】
  任何对 EMEMC/EMEMD/QUEUE/MSGQ/CPUCTL/IRQ* /DMACTL/0x8403C0/0x8403F8 的写；任何 NVDM 消息（尤其 COT 0x14）；
  不要用 emem_cli send|recv；不要用带 len/4-1 语义的旧工具去发 >4 B 的报文。
```

---

## 5. 仍然空白/未定（不编造）

| 空白 | 现状 |
|---|---|
| GB202 的 `NV_PSEC` 位表 | swref 里**没有** `blackwell/gb202/dev_sec_pri.h`；本报告全部偏移取自 gb20b 表（+ falcon v4 标准块） |
| `0x01000100 / 0x01000040` 的精确编码 | 两种解读（非零游标位 vs 与 GB20B 不同的字段编码）都能自洽；静态不可判 ⇒ 映射到"不要写" |
| GB202 上 SEC2 固件是否**执行** | 无发布心跳；只能靠 PBUS SW_SCRATCH 进度值 + falcon 侧间接迹象（❓） |
| `0x840320` 里 FWSEC 的真实错误码 | host 读被拒（0xBADF5108）；PLM 掩码 `0x8403F8` 待读 |
| GB202 是否绑定 `NV_PBUS_SW_SCRATCH(0)` 的写入者 | 偏移可信（GB100 发布表 + GB202 复用 GB100 fuse 基址已被实测印证），但"谁写、写什么进度值"未知 |
| FSP 为什么容忍了 host 的 4× 长度错误 | 两种可能（固件对请求长度宽松 / 该次回包其实未被正确解析）❓；可用已有 `guest_dmesg_emem*.txt` 的 HEX 复用判断（本轮未展开） |
| `0x5E0` 为什么恒 0（连 devinit 后也 0） | 最可能是 GB202 的 BootFSM/FSP 根本不写这个 GB20B 专用 scratch；无源码证据可进一步确认 |

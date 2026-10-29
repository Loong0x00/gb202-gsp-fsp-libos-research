# DS:FSP MNOC 信箱"正确访问配方"(宿主/客体侧)

日期:2026-09-26。范围:**只读本地文件静态分析**(驱动 610.43.03 / 610.57.04 源码、swref 公开头、
`vm_mods_lab` 旧工具与当年结论、`guest_dmesg_*`)。未碰 GPU/驱动/VM/MMIO,未联网。

---

## 0. 结论(先说答案)

1. **地址形式你们是对的**:基址就是常量 `0x008f1e00`,端口步长 `0x0c`,偏移 `0x104/0x108`(FSP→host)+
   `0x184/0x188`(host→FSP)。没有"选择器寄存器/窗口使能"这一步。
2. **失败原因不是地址,是两个别的错**:
   - **失败 1(用户态)= 用错了 port**:你们读了/发了 **port 2**。当前卡上 port 2/3 从来就没被 FSP
     "armed"(READY=0),`RECV_INFO=0x04000000` 正是当年记录里 port 2/3 的指纹。**当年能用的那次
     (task2/sub1 被接受)用的是 port 1**(`--port 1`),port 1 才是 armed 的 host 端口。
   - **失败 2(内核模块)= 模块把基址加了两次**(`ioremap(BAR0+0x8f1e00,0x2000)` 之后又用含
     `FSP_MNOC_BASE` 的偏移去读),读的根本不在 0x2000 映射窗口内 ⇒ **0 没有任何硬件含义**。
3. "驱动侧权威做法"里 port 常量确实是 2(`KERNEL_FSP_MBOX_PORT 2`),但那是 **RM 自己的 CPU-MNOC
   模式**(registry `RmFspUseMnoc`,默认 0,默认走 EMEM 队列通道);而且在 GB202 上
   `gpuMnocMboxSend/Recv` 的 HAL body 是 `return NV_ERR_NOT_SUPPORTED` 桩。**所以"port 2"对
   "我们(宿主/客体用户态)"没有约束力,必须以 `RECEIVE_READY` 探测为准。**

---

## 1. 驱动侧权威做法(Q1:信箱地址怎么算)

### 1.1 孔径 = BAR0 + 常量 0x8f1e00,长度 0x200 —— 纯偏移,无选择器

```c
// driver_gpio_internal_610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb100.c
56: #define KERNEL_FSP_MBOX_PORT 2
82: kfspConstructHal_GB100(...)
83:     return ioaprtInit(&pKernelFsp->mboxAperture, pGpu->pIOApertures[DEVICE_INDEX_GPU],
84:                       NV_PFSP_MNOC_RX_FIFO_DATA(0), 0x200);
```

```c
// src/common/inc/swref/published/blackwell/gb100/dev_fsp_pri.h:37   (-W-4A = 只写)
37: #define NV_PFSP_MNOC_RX_FIFO_DATA(i)  (0x008f1e00+(i)*8)
```

- 父孔径:`pGpu->pIOApertures[DEVICE_INDEX_GPU]` = **整块 BAR0 映射**
  (`_gpuInitIOAperture()`:`objCreate(..., pMapping, /*mappingStartAddr*/0, /*offset*/0, pMapping->gpuNvLength)`
  —— `gpu_access.c:809`;`gpuNvAddr`/`gpuNvLength` 来自 `nv->regs->map/size` 即 BAR0,
  `gpu_mgr.c:1972/1981`、`osinit.c:855/860`,读写在 `os.c:1933 osDevReadReg032` → `NV_PRIV_REG_RD32(gpuNvAddr, offset)`)。
- 子孔径 = 父孔径 + 0x8f1e00(`gpu_access.c:303 ioaprtConstruct_IMPL`:`pAperture->baseAddress += offset`)。
- 实际寄存器访问 = `REG_RD32(pMboxAperture, off)` → `regAddr = baseAddress + off` →
  `mappingRegAddr = regAddr - mappingStartAddr`(`gpu_access.c:334` 写 / `:515` 读)。
  **⇒ 绝对地址 = BAR0 + 0x8f1e00 + off。**
- **结论:基址是常量 `0x8f1e00`,不是 GPU 对象字段、不是窗口/选择器。** 与 `parallel/DS_GSP_MMIO_WINDOW_20260926.md`
  在 GSP 侧得到的结论一致(孔径就是"BAR0/PRI 窗口指针",没有"写选择器寄存器再访问"的序列)。
- GB202 也走这条路:GB202 的 `gb202/dev_fsp_pri.h` **没有** MNOC 定义,`kern_fsp_gb100.c` 直接
  `#include "published/blackwell/gb100/dev_fsp_pri.h"`;`g_kern_fsp_nvoc.c:333-343` 的 ChipHal 组
  `GB100|GB102|GB110|GB112|GB202|GB203|GB205|GB206|GB207|GR100|GR102` 说明 GB202 用
  `kfspConstructHal_GB100`(即 0x8f1e00/0x200)。

### 1.2 端口与寄存器(源码行)

```c
// src/common/inc/swref/published/blackwell/gb100/dev_mnoc_pri_zb.h   (偏移相对孔径 = 相对 0x8f1e00)
27: NV_MNOC_ZB_PRI_MESSAGE_INFO_0_SENDMBOX(i)      (0x104 + (i)*0xC)  // RW  FSP→host 的 INFO
32:   ..._SENDMBOX_MESSAGE_READY                  24:24              // R   FSP 有报文待取
35:   ..._SENDMBOX_ERR                            25:25              // R
38:   ..._SENDMBOX_INTR_ENABLE                    30:30              // RW
41:   ..._SENDMBOX_INTR_STATUS                    31:31              // RW oneToClear(W1C)
46: NV_MNOC_ZB_PRI_RDATA_0_SENDMBOX(i)             (0x108 + (i)*0xC)  // R   FSP→host 数据
51: NV_MNOC_ZB_PRI_MESSAGE_INFO_0_RECEIVEMBOX(i)   (0x184 + (i)*0xC)  // RW  host→FSP 的 INFO(我们写)
56:   ..._RECEIVEMBOX_MESSAGE_TRIGGER             20:20              // -WX 写触发(自清)
30/54: ..._MESSAGE_SIZE                          19:0              // 长度域(发送方自声明)
58:   ..._RECEIVEMBOX_RECEIVE_READY               24:24              // R   ★发送前置条件
61:   ..._RECEIVEMBOX_ERR                         25:25
64:   ..._RECEIVEMBOX_CREDIT_AVAILABLE            26:26              // R   ★数据推送流控
75: NV_MNOC_ZB_PRI_WDATA_0_RECEIVEMBOX(i)          (0x188 + (i)*0xC)  // -W  host→FSP 数据
```

**命名是按 FSP 视角命名的**,这是最容易踩的坑:`..._RECEIVEMBOX` 才是**我们发**给 FSP 的信箱,
`..._SENDMBOX` 是 **FSP 发给我们的**信箱。

### 1.3 驱动收发序列(照抄即可)

```c
// src/kernel/gpu/arch/blackwell/kern_gpu_gb100.c
1275  _gpuMnocMboxSendReceiverReady_GB100(...)   // 等 RECEIVEMBOX.RECEIVE_READY==1
        -> 1548-1557: FLD_TEST_DRF(_RECEIVEMBOX,_RECEIVE_READY,_TRUE)
1281  regVal = REG_RD32(RECEIVEMBOX(port));        // RMW
1282  FLD_SET_DRF_NUM(...,_MESSAGE_SIZE, msgSize)
1284  FLD_SET_DRF(...,_MESSAGE_TRIGGER,_SET)       // 一次写入 size+trigger
1286  REG_WR32(RECEIVEMBOX(port), regVal)
1293  每 64 字节: 等 CREDIT_AVAILABLE==1 (->_gpuMnocMboxSendCreditCond, 1591-1599)
1303  REG_WR32(WDATA_RECEIVEMBOX(port), data)      // 4 字节/次
1310  _gpuMnocMboxSendErrorCheck_GB100 -> 读 RECEIVEMBOX.ERR(1634-1650)
1430  IsMsgAvailable: 读 SENDMBOX.MESSAGE_READY==1
1357  recv: 读 SENDMBOX 取 size(19:0)
1388  recv: 读 RDATA_SENDMBOX(port), 每 dword 前复检 MESSAGE_READY/ERR
1529  MaxMessageSize = DRF_MASK(SENDMBOX_MESSAGE_SIZE)+1 = 0x100000;Min = 4 (1512)
```

### 1.4 为什么"不能指望驱动"在 GB202 上替我们打开这条路

```c
// src/kernel/gpu/fsp/kern_fsp.c:170-181
170  if (osReadRegistryDword(pGpu, NV_REG_STR_RM_FSP_USE_MNOC, &data) == NV_OK) {
172      if (data & NV_REG_STR_RM_FSP_USE_MNOC_CPU)  PDB_PROP_KFSP_USE_MNOC_CPU = TRUE; ...
// src/nvidia/interface/nvrm_registry.h:2062-2066
2063  #define NV_REG_STR_RM_FSP_USE_MNOC_DEFAULT (0x00000000)   // ★ 默认 0
2064  ..._CPU 0x1   2065  ..._GSP 0x2   2066  ..._BOTH 0x3
```

- `kfspSendPacket_GB100`(kern_fsp_gb100.c:319-325)**只有**在 `PDB_PROP_KFSP_USE_MNOC_CPU` 时才走
  `gpuMnocMboxSend_HAL(..., KERNEL_FSP_MBOX_PORT=2)`;否则走 `kfspSendPacket_GH100` =
  **EMEM 队列通道**(`kern_fsp_gh100.c:621-654`:`NV_PFSP_EMEMC/EMEMD(0x8f2ac0+8i)`、
  `NV_PFSP_QUEUE_HEAD/TAIL(0x8f2c00+8i)`、`FSP_EMEM_CHANNEL_RM=0`,见 `fsp_emem_channels.h:34`)。
- 更彻底:`generated/g_gpu_nvoc.c:1866-1876` 的 ChipHal 组是
  `GB100|GB102|GB110|GB112|GR100|GR102`(**不含 GB202**),其余芯片落到
  `generated/g_gpu_nvoc.h:5214-5225` 的桩 `return NV_ERR_NOT_SUPPORTED`。
  ⇒ **在 610 这份代码里,GB202 的 `gpuMnocMboxSend/Recv` 根本不可用**;RM 在 GB202 上默认既不走
  MNOC 也不会去 arm port 2。这也解释了 port 2 长期 READY=0。

---

## 2. 我们的形式对不对(Q2)

| 项 | 你们用的 | 权威值 | 判定 |
|---|---|---|---|
| 基址 | `FSP_MNOC_BASE=0x008f1e00` | `NV_PFSP_MNOC_RX_FIFO_DATA(0)=0x008f1e00`(dev_fsp_pri.h:37) | ✅ |
| 长/端口步长 | `0x2000` / `port*0x0c` | 孔径 0x200(kern_fsp_gb100.c:84)/ `(i)*0xC`(dev_mnoc_pri_zb.h:27/46/51/75) | ✅(0x2000 覆盖 0x200 没问题) |
| host→FSP INFO/DATA | `+0x184/+0x188` | `RECEIVEMBOX` + `WDATA_RECEIVEMBOX` | ✅ |
| FSP→host INFO/DATA | `+0x104/+0x108` | `SENDMBOX` + `RDATA_SENDMBOX` | ✅ |
| 长度/触发/READY/ERR/CREDIT | `[19:0] / b20 / b24 / b25 / b26` | 同(见表) | ✅ |
| **端口号** | **port 2(硬编码)** | 驱动常量是 2 **但** 只在 CPU-MNOC 模式且 GB202 无 HAL body;实测 armed 的是 **port 1** | ❌ **错在这里** |
| 基址是否要"先使能窗口" | — | 无此步骤 | ✅(没有遗漏) |

补充两个"读 0 陷阱":
- `0x8f1e00` 本身是 `-W-`(只写,RX FIFO DATA),**直接读它**不该指望有意义的值。
- 真信箱寄存器全在 `0x8f1f04..0x8f1fac` 之间(见下表),都在孔径 0x200 内。

### 实测端口表(2026-07-22,客体,GB202,`vm_mods_lab/fsp_prc_read_direct_result_20260722.md`)

| port | SEND(0x104+0xc*p) FSP→host | RECV(0x184+0xc*p) host→FSP | 可用? |
|---:|---|---|---|
| 0 | `0x008f1f04 = 0x00000000` | `0x008f1f84 = 0x05000000` ready=1 credit=1 | armed |
| **1** | **`0x008f1f10 = 0x80000000`** intr=1 | **`0x008f1f90 = 0x8500000c` ready=1 credit=1 size=12** | ★**当年全程用它** |
| 2 | `0x008f1f1c = 0xbadf5720` err(实为 PRI 读错误) | `0x008f1f9c = 0x04000000` ready=0 credit=1 | ✗ |
| 3 | `0x008f1f28 = 0xbadf5720` | `0x008f1fa8 = 0x04000000` ready=0 credit=1 | ✗ |

- 你们的"失败 1"读数 `RECV_INFO=0x04000000 / SEND_INFO=0xbadf5720` **与 port 2 行逐位相同**(且
  `fsp_lie_probe.c` 里写死 `const unsigned port = 2`)。⇒ 不是新回归,是**一直发在没 arm 的端口上**。
- `0xBADFxxxx` = 硬件 PRI 读错误族(`gpu_access.c` `GPU_READ_PRI_ERROR_MASK 0xFFF00000/CODE 0xBAD00000`;
  `flcnretval.h` `FLCN_CSB_PRIV_PRI_ERROR_CODE 0xBADF0000`;另见 `parallel/badf510c_provenance.md`)。
  读到它说明**这个地址真的被硬件解码了**(所以窗口/基址没错),只是该 port 的 SEND 侧对我们不可用。
  另外 `dev_mnoc_pri_zb.h:29/48/53/77` 给这几个寄存器都标了 `__PRIV_LEVEL_MASK`,说明访问受特权级约束。
- 当年的成功用例都明确带 `--port 1`:
  `vm_mods_lab/fsp_task2_zero_result_20260722.md:84-89`(**task2/sub1 被接受** + `error_code=0`)、
  `fsp_prc_read_direct_result_20260722.md`、`fsp_caps_query_result_20260722.md`、
  `fsp_prc_write_noop_result_20260722.md`(FSP 回 `0x1e4` = 收到并拒绝,也证明通道通);
  工具默认值也是 1(`vm_mods_lab/prc-read-tools/gb202_fsp_prc_sweep.c:835 opt->port = 1`)。

---

## 3. 为什么读到 0,以及怎么判定(Q3)

### 3.1 主因(可复核,必须先改):`fsp_lie_mod.c` 双重基址

```c
// /home/user/fsp_probe/fsp_lie_mod.c
#define FSP_MNOC_BASE   0x008f1e00u
#define OFF_RECV_INFO(p) (FSP_MNOC_BASE + 0x184u + ((p)*0x0cu))   // ← 已含基址
...
bar = ioremap(base + FSP_MNOC_BASE, 0x2000);                       // ← 又含基址
pr_err(... ioread32(bar + OFF_RECV_INFO(port)) ...);               // = BAR0 + 2*0x8f1e00 + 0x19c
```

实际访问地址 ≈ `BAR0+0x11e3d9c`,**远超 0x2000 的 ioremap 窗口**(`0x8f1e00+0x2000` 之外),
读到的是"窗口外/别的东西",`0x0` **不能作为"信箱没响应"的证据**。改法二选一:
- `bar = ioremap(BAR0_phys, 0x900000)` + 直接用绝对偏移;
- 或保留 `ioremap(BAR0_phys+0x8f1e00, 0x2000)`,偏移改成 **相对**(`0x104/0x108/0x184/0x188 + p*0xc`)。

模块另外几处要改:未校验 `vendor/device == 10de:2b85`、未检查 `pci_resource_len(dev,0) >= 0x900000`;
`port` 硬编码 2(应扫描);在宿主 ioremap 别人 VM 的 BAR0(应只在客体做)。
参考可用的正例:`vm_mods_lab/prc-read-tools/gb202_fsp_prc_sweep.c`(mmap `resource0`,长度 0x900000,
偏移 = 基址 + 寄存器偏移,`--port` 默认 1)。

### 3.2 第二因(即使修好偏移也会再撞上):port 2 未 arm

`RECEIVE_READY=0` ⇒ 驱动也会 `NV_ERR_NOT_READY`(kern_gpu_gb100.c:1275)。**这不是"FSP 没在跑"**,
而是"FSP 没在这个端口上听"。实例:同一轮里 port 1 的 SEND 侧还挂着一条 12 字节 FSP 报文
(INTR_STATUS=1),port 1 的 RECV 侧 size 残留 12(正好是一次 PRC read 请求长度)——说明 FSP 侧活着,
只是端口绑定不同。

### 3.3 可检验的判定流程(不改硬件语义,纯读为主)

1. **P0 正控制(先证明窗口对)**——同一窗口里读:
   - `0x00000000` `NV_PMC_BOOT_0`:应等于 chipId(GB202 形如 `0x1b2xxxxx`),绝不能是 0/0xffffffff;
   - `0x000200bc` `NV_THERM_I2CS_SCRATCH`(=FSP_BOOT_COMPLETE,`dev_therm.h:27` + `dev_therm_addendum.h:28`):
     FSP 启动完成应为 **`0x000000FF`**;
   - `0x008f0334` `NV_GFW_FSP_UCODE_VERSION`(=SCRATCH_GROUP_3(1),`dev_fsp_addendum.h:27-30`)bits11:0:非 0;
   - `0x008f0320..0x008f032c` `NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(0..3)`:读得动即可。
   - 若这些都正常、只有信箱是 0 ⇒ 100% 是**偏移写错**(§3.1)或端口错。
   - 若这些也全 0/0xff ⇒ 基址错:核对 `lspci -nn` 是 `10de:2b85`、`pci_resource_start/len(0)`
     (64 位 BAR 注意高 32 位)、确认模块跑在**客体**、设备不在 reset/D3。
2. **P1 四端口扫描(必做,替代硬编码)**:对 p=0..3 读 `RECV_INFO/RECV_WDATA` 与 `SEND_INFO`。
   期望形态:RECV 至少 `bit26(CREDIT)=1`;port 2/3 的 SEND 期望 `0xBADF57xx`。
   **四个 RECV_INFO 全 0 是异常**(历史数据最低是 `0x04000000`),此时回到 P0。
3. **P2 写入回读(可选、低风险)**:对 `RECV_INFO` 只写 size 域(bit20 trigger 保持 0)再读回,
   验证该窗口可写;验证完把 size 写回 0。(别在 RM 正在用信箱时做;GB202 上 RM 默认不用 MNOC。)
4. **P3 只有在某端口 `RECEIVE_READY=1 && ERR=0 && CREDIT=1` 时才发**。若 4 个端口都没 READY:
   结论是"此刻不能经 MNOC 发",此时可选的替代接口是 RM 自己的 EMEM 通道(§1.4),但那是"另走一路",
   不是本配方。

**明确回答"是不是要先写寄存器使能"**:不是。驱动源码里没有任何 MNOC 窗口使能/选择写入;
唯一前置条件就是目标端口的 `RECEIVE_READY`(以及推数据时的 `CREDIT_AVAILABLE`)。

---

## 4. 最终访问配方(step-by-step)

1. **在哪**:客体(VM)里对 `0000:00:02.0` 操作。先 `lspci -nn -s 0000:00:02.0` 确认
   `10de:2b85[GB202/5090]`;读 `/sys/bus/pci/devices/0000:00:02.0/resource` 记下 BAR0 基址与长度
   (**长度必须 ≥ 0x900000**;5090 的 region0 = 64M)。不要从宿主去读客体的 BAR0。
2. **怎么映射**(两选一,推荐用户态,和当年成功路径一致):
   - 用户态:`fd=open(resource0,O_RDWR|O_SYNC)` → `mmap(NULL, 0x900000, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0)`;
   - 内核:同一 BAR0 段 `ioremap(BAR0_phys, 0x900000)`,或 `ioremap(BAR0_phys+0x8f1e00, 0x2000)`
     之后**只用相对偏移**。
3. **地址公式**(绝对偏移,加在 BAR0 上):
   ```
   BASE         = 0x008f1e00
   RECV_INFO(p) = BASE + 0x184 + 0x0c*p     (host→FSP 控制/状态,我们写)
   RECV_WDATA(p)= BASE + 0x188 + 0x0c*p     (host→FSP 数据,我们写)
   SEND_INFO(p) = BASE + 0x104 + 0x0c*p     (FSP→host 控制/状态,我们读)
   SEND_RDATA(p)= BASE + 0x108 + 0x0c*p     (FSP→host 数据,我们读)
   ```
4. **先做 P0 正控制(§3.3)**,确认窗口可信(FSP_BOOT_COMPLETE=0xFF、ucode≠0、PMC_BOOT_0=chipId)。
5. **端口选择(不要硬编码 2)**:扫 p=0..3,选满足
   `(RECV_INFO & (1<<24)) && (RECV_INFO & (1<<26)) && !(RECV_INFO & (1<<25))` 的 p;
   若多个,取 SEND 侧 `INTR_STATUS(bit31)==0` 的(没有悬挂报文)优先。
   **当前卡(FSP 记录 + 2026-07 实测)应为 p=1。**
6. **发送前置检查(每次发之前都要做)**:
   - `RECV_INFO.bit24 RECEIVE_READY == 1`(必须,否则不发);
   - `RECV_INFO.bit25 ERR == 0`;
   - 消息长度 `4 ≤ size ≤ 0x100000`(bits19:0);
   - 之后推数据时:**每 64 字节前**再确认 `bit26 CREDIT_AVAILABLE == 1` 且 `ERR == 0`。
7. **发送顺序**:RMW 读 `RECV_INFO` → 清 bits[19:0] → 写 size → **同一次写**置 `bit20 TRIGGER=1`
   → 依次 `RECV_WDATA = dword`(4 字节/次,不足补 0)→ 结束后读 `RECV_INFO` 确认 `ERR==0`。
   (报文内容不变:MCTP dword0 + NVDM dword1 + payload,例 CAPS_QUERY =
   `010000c0 7ede1016 13`,PRC read = `010000c0 7ede1013 0c02<knob_le16>`。)
8. **收响应**:轮询 `SEND_INFO.bit24 MESSAGE_READY==1` 且 `bit25 ERR==0` → `size = bits[19:0]`
   → 循环 `SEND_RDATA` 读 4 字节,每读一个 dword 前复检 READY/ERR,直到 size 字节读完;
   若 `INTR_STATUS(bit31)=1` 需要时写回 `bit31=1` 清中断(W1C,tool 不强求)。
9. **如果 4 个端口都 READY=0**:不要发,也不要再试 port 2。此时结论是"当前状态不经 MNOC 发",
   RM 自己在 GB202 上默认走 EMEM 队列通道(§1.4),或等 FSP/端口重新 arm 后再试。

---

## 5. 不确定项(必须明说)

1. **armed 端口是否每次 boot 都一样**——只有 2026-07-22 一轮四端口快照;port 1 在那一轮可用,但
   "每次都要扫"仍是硬要求。FSP 为什么 arm 0/1 而 2/3 没有,**固件加密,不可证**。
2. `0xBADF5720` 的精确字段(子类型/端口位)未公开;只能说它属 PRI 读错误族,并伴随
   `__PRIV_LEVEL_MASK` 属性,推测与端口未实例化/特权级有关。
3. "port 2 是 CPU 口"只出现在 RM 源码常量里;GB202 的 `gpuMnocMbox*` 是 `NV_ERR_NOT_SUPPORTED` 桩,
   所以**不能**由"驱动常量=2"推出"FSP 在 2 上听"。
4. 570.215(MODS,当年成功环境)无源码;只能从"port 1 RECV size 残留 12 = 一次 PRC read 长度"
   推断它也用 port 1。
5. 本轮**未做任何硬件访问**,所有地址与顺序均来自源码/旧记录;细则第 4 步起需实机验证(建议先在
   无驱动客体里只读扫 4 个端口,再决定发不发)。

---

## 总结

1. 地址公式是对的:`BAR0 + 0x008f1e00 + {0x104,0x108,0x184,0x188} + 0x0c*port`,基址是常量、
   无窗口/选择器使能步骤;唯一"驱动侧权威"来源是 `kern_fsp_gb100.c:83-84` + swref 头。
2. 失败 1 是**端口选错**:你们一直在 port 2,而当年 task2/sub1 被 FSP 接受的那次用的是
   `--port 1`;port 2/3 的指纹(`0x04000000 / 0xbadf5720`)与你们读数逐位一致。
3. 失败 2 是**模块双重基址**:`fsp_lie_mod.c` 把 `FSP_MNOC_BASE` 加了两次,读的地址在 0x2000
   映射窗口之外 ⇒ 那批 `0x0` 与硬件无关,不能当结论。
4. 驱动常量 `KERNEL_FSP_MBOX_PORT=2` 只在 `RmFspUseMnoc`(默认 0)的 CPU-MNOC 模式下生效,
   且 GB202 的 `gpuMnocMboxSend/Recv` 是 `NV_ERR_NOT_SUPPORTED` 桩;GB202 上 RM 默认走 EMEM 通道。
5. 正确配方:确认设备/窗口 → 正控制读(FSP_BOOT_COMPLETE=0xFF、ucode≠0、PMC_BOOT_0=chipId)
   → 扫 0..3 端口取 `RECEIVE_READY=1`(当前应 p=1)→ 发前查 READY/ERR → 写 size+TRIGGER →
   每 64B 查 CREDIT → 推 WDATA → 读 SEND_INFO/RDATA 收响应。
6. 判定"读到 0 是不是真故障"的办法:四个 RECV_INFO 全 0 就是访问/偏移问题(历史最低是 0x04000000);
   只有信箱为 0 而正控制正常 = 偏移写错。

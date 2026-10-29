# GB202 RegHal 全量名字 → 地址映射(570.215)与 domain 0 基址闭合尝试

日期:2026-09-25
范围:**纯本地只读静态**。未运行 MODS、未访问任何 GPU / 设备节点 / BAR0 / MMIO / PCI config / debugfs / /proc/driver/nvidia,
未写卡、未刷写、未联网、未做任何设备侧或出口管制相关操作。全部结论来自本地文件解析与反汇编。

## 0. 工件与哈希

| 项 | 值 |
|---|---|
| MODS 570.215 | `/home/user/mod570_215_static/extracted/home/570.215/mods` (392,897,664 B, SHA-256 `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856`) |
| 名字池 | `/home/user/rt_5090_project/parallel/gb202_fslib_strings_20260925.txt`(578 行,第一列 = 文件偏移) |
| RegHal 表 | chip `0xff2`(GB202),表头 file `0x9043c8f`,compressed 29896 / uncompressed 562324 / 20083 行,9 平面 delta 编码 |
| 解码器 | `/home/user/rt_5090_project/gb202_reghal_offline.py`(既有工具) |
| 开源驱动源 | `/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules`(git `nlr/greenfield-v1`,hwref 仅 11 个文件)、`/usr/src/nvidia-610.57.04`(其中的 `src/common/inc/swref/published/**` 为**已发布的 swref/ZB 头**,与本机 greenfield 仓库 `/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/src/common/inc/swref/published/**` **逐字节相同**,已 `diff -q` 验证) |
| 本轮新增工件 | `parallel/gb202_reghal_namepool_scan_20260925.py`(扫描器)、`..._scan_20260925.results.json`(全量原始结果)、`..._scan_20260925.detail.txt`(可读明细)、本报告 |

VA/文件偏移换算(本工件):`VA = file_offset + 0x400000`(第一 LOAD 段;RegHal 表头 file `0x9043c8f` = VA `0x9443c8f` 已验证)。

## 1. 结论先行(TL;DR)

1. **FACT(交付主体)**:578 条池内名字中,577 条至少有一处代码立即数引用(共 2348 处);
   在名字引用点 ±`0xC0` 字节窗口内,**214 条**名字能对上"RegHal 形即时数"(`imm>>28 ∈ {1,2,4}`),其中 **121 条**对上了 GB202(0xff2)表里真实存在的 ID。
   按"最佳 ID 的 domain"分类:**40 条落在 domain 5**(fuse/PRI 逻辑域,可换算成 `0x00820000 + offset`),**81 条落在 domain 0/29/33/54/60 等**其它域(基址未闭合,见 §4)。
2. **FACT**:domain 5 的换算链不变:`ID → 表行 → (domain=5, offset[, 4*i]) → 0x00820000 + offset`。
   本轮新增**独立交叉验证**(开源/已发布材料侧):MODS 的 domain-5 offset 与 NVIDIA 610 已发布 "ZB"(zone-base)头文件**同值**:
   ` OPT_DISPLAY_DIS` → offset `0xc04` == `NV_FUSE_ZB_STATUS_OPT_DISPLAY 0x00000C04`(blackwell/gb100/dev_fuse_zb.h);
   `NV_FUSE_ZB_FEATURE_READOUT 0x00003814` ↔ MODS ID `0x10570000`/`0x10574000`(offset `0x3814`);
   `NV_FUSE0_PRI_BASE = 0x820000`(blackwell/gb100/hwproject.h;hopper 头写作十进制 `8519680`)。
3. **FACT**:§3 的 **表 A/B/C/D 覆盖全部 214 条**能在代码里定位到 RegHal 形即时数的池内名字(A=domain 5 高置信、B=domain 5 中/低置信、C=非 domain 5(含四个目标名)、D=邻近 ID 不在 GB202 表中的负结果)。
4. **FACT(新增机械配对)**:FsLib 单位簇(file `0xcc0a00..0xcc1300`)可逐条机械解出 `ID → 单位名`(表 E)。
   其中 9 个 ID 在 GB202 表内 → 可闭合到 `0x82xxxx`;**6 个单位名对应的 ID 在 GB202 表中没有行**(`gpc_zcull` `0x104a8000`、`ce` `0x102e8000`、`fbio_shift_override` `0x10320000`、`pcie_lane` `0x10398000`、`fbpa` `0x10330000`、`fbio_shift` `0x10318000`),即这些站点在 GB202 上走不到成功读。
5. **任务第 2 项结论(先负后正)**:用"开源 hwref **同名**寄存器全地址反推"的路线 **NEGATIVE**(四个名字在开源/已发布材料中 0 命中,命令见 §4.2);
   但改用"**同值**"证据后,**domain 0 基址本轮闭合 = `0x000000`** —— 即 domain-0 行的 `offset` 本身就是**绝对 PRI 寄存器号**,不需再加基址。
   最强证据是 GB202 自己的已发布头文件:`NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(i) = (0x008f0320+(i)*4)`(`__SIZE_1 = 4`)
   ↔ MODS ID `0x12004000` 的 `(domain 0, offset 0x8f0320, count 4)`(同值 + 同数组形状 + 同项数,§4.3);
   再结合已发布 `NV_PMC0_PRI_BASE 0x0`、以及 domain-0 家族其它成员都落在已发布 PRI 编号区(0x84xxxx=SEC、0x826xxx=XAL EP P2P、0x11d000=PCIe 区)⇒ 基址 = 0。
   由此**排除** fuse 基址 `0x820000` 与各 aperture 基址(`0x1000`/`0x9000`/`0x140000`/`0x400000`/`0x880000`/`0x8A000`),依据见 §4.6。
6. **UNKNOWN(必须明写的残余负结果)**:按表行字面值,四个目标寄存器落在 **PRI `0x10`(`PAC_DISABLE`、`SYSPIPE_GFX_DISABLE`)/ PRI `0x20`(`TPC_GPCx_DISABLE`、`GPC_GFX_DISABLE`)**;
   但本地全部材料里**找不到** PRI `0x10`/`0x20` 上与该四名字相符的寄存器定义,且这四个 ID 的 read 行在**全部 29 张内嵌芯片表(0x800…0xff5,跨 5 代架构)中逐字相同**、无 access-PLM 元数据行。
   因此这四行很可能是**跨代复用的通用/占位行**(对应打印名正是 `Cannot read PAC/TPC/GPC/SYSPIPE_GFX mask`),或真正的掩码寄存器只由**写侧 domain 5 的 field 描述符**(如 `gpc_gfx` `0x20eb0000` bits[11:0])定义。三个假设与"要如何才能真正闭合"见 §4.7。
## 2. 方法、口径与置信度定义

**扫描口径**(可复现,脚本 `parallel/gb202_reghal_namepool_scan_20260925.py`):

1. 用 `gb202_reghal_offline.py` 解码 chip `0xff2` 的 RegHal 表(20083 行),得到 `ID → rows[{opcode, indices, words(domain,w1,w2,offset)}]`。
2. 对名字池每一条,取其在 ELF 中的**字符串 VA**(= 池内 file 偏移 + `0x400000`),在整文件中搜索它的 4 字节/8 字节小端立即数出现点(含非对齐;池内 577/578 条至少一处,共 2348 处)。
3. 以每个出现点为中心,在 `[-0x100, +0x140]` 窗口内用 capstone 从 16 个相位各线性反汇编一次,收集所有 `mov r32, imm32`,保留高半字节为 RegHal opcode(`1`/`2`/`4`)的立即数,并标注该 ID 是否真的存在于 GB202 表(`in_table`)。
4. `Δ = 立即数指令 file 偏移 − 名字立即数 file 偏移`(负 = ID 在名字之前);`|Δ| ≤ 0xC0` 才收录。
5. 表行汇总:`domain`、`offset`、`count`(若同一 ID 的 read 行 offset 构成 `base+4*i (i=0..n-1)` 则 `count=n`,否则 `1`);
   domain 5 时给出 `BAR0 = 0x00820000 + offset`(固定选择器 fallback,见既有审计 `fuse_domain_instance.md`;非运行时实测值),以及该 ID 的 **access-PLM** 行地址。
6. 不执行 MODS;不开任何设备接口。

**置信度**:

| 级别 | 判据 | 说明 |
|---|---|---|
| **高(FACT)** | 表 A:最佳 in-table ID 的 |Δ| ≤ `0x40`,且其 read 行 domain = 5 | 与既有审计(`GB202_FSLIB_ADDR_MAP_20260925.md`)逐条一致;并至少有一条被公开 ZB 头文件同值交叉验证 |
| **中** | 表 B:`0x40 < |Δ| ≤ 0xC0`,或同一名字出现多个同距 ID | 需按名字语义人工判读;表 B 中已标出已知误配 |
| **负(NEGATIVE)** | 表 D:邻近只有"不在 GB202 表中"的 RegHal 形 ID | 对应失败日志 `Invalid register 0x%x%s specified for this GPU` |
| **UNKNOWN** | 表 C:最佳 ID 的 domain ≠ 5 | 基址未闭合,不能给出 `0x82xxxx` 之外的地址 |

> ⚠ 方法学告警(沿用既有审计并本轮复核):名字立即数常为**非 4 字节对齐**,只扫对齐会漏一半以上;同一函数内可能有多个名字/ID,`Δ` 只表示**距离**,不等于语义配对。表 C 里 `*_DISABLE` 名与 `0x20xxxxxx` **field-setter** 的同距配对是"写侧字段描述符",与同名 register 的 read 行不是同一条目。

## 3. 交付主体:池内名字 → RegHal ID → (domain, offset, count) → 地址

以下四张表是**机器生成**(脚本 `gb202_reghal_namepool_scan_20260925.py`),覆盖全部 214 条"能在代码里定位到 RegHal 形即时数"的池内名字;
121 条对上了 GB202 表中的真实 ID,其余 93 条见表 D。名字按池内 file 偏移升序;"引用点"均指**file 偏移**(VA = +0x400000)。

### 3.1 表 A —— domain 5 已闭合,高置信(最佳 |Δ| ≤ 0x40,共 23 条)

地址列 = `0x00820000 + offset`(数组为 `+4*i`);`count` = 该 ID 的 read 行偏移构成 `base+4*i` 的项数;
"access PLM" = 该 ID 元数据行(idx `0xfffe`)给出的 PRI 级掩码寄存器地址(域 5)。

| 名字(池内原文) | 最佳 RegHal ID | Δ(字节) | 引用点(file) | domain | offset | count | 固定选择器真实地址(BAR0) | access PLM |
|---|---|---|---|---|---|---|---|---|
| `fbp_ltc_disable` | 0x10368000 | -31 | 0xcbca62 | 5 | 0x970 | 16 | **0x00820970..0x008209ac +4*i (i=0..15)** | 0x00820010,0x008200dc |
| `Cannot read GPC mask` | 0x10d64000 | -60 | 0xcbd8b5 | 5 | 0xc1c | 1 | **0x00820c1c** | 0x008200dc |
| `Cannot read PES mask` | 0x10de4000 | -58 | 0xcb56b7 | 5 | 0x2a78 | 16 | **0x00822a78..0x00822ab4 +4*i (i=0..15)** | 0x00820010,0x008200dc |
| `Cannot read L2 mask` | 0x10d9c000 | -18 | 0xcbaae7 | 5 | 0xd70 | 16 | **0x00820d70..0x00820dac +4*i (i=0..15)** | 0x00820010,0x008200dc |
| `%s0x%x'` | 0x10d2c000 | -50 | 0xca1d19 | 5 | 0x2a00 | 16 | **0x00822a00..0x00822a3c +4*i (i=0..15)** | 0x00820010,0x008200dc |
| `OPT_CPC_DIS : 0x%x` | 0x106fc000 | -17 | 0xc9f056 | 5 | 0x30e0 | 1 | **0x008230e0** | 0x008200dc |
| `OPT_GPC_DISABLE` | 0x106fc000 | -62 | 0x10f087a | 5 | 0x30e0 | 1 | **0x008230e0** | 0x008200dc |
| `OPT_ROP_DIS : 0x%x` | 0x109f4000 | -20 | 0xcad391 | 5 | 0x30a0 | 1 | **0x008230a0** | 0x008200dc |
| `OPT_PES_GPC%u_DIS : 0x%x` | 0x10984000 | -42 | 0xcb80f9 | 5 | 0x3600 | 12 | **0x00823600..0x0082362c +4*i (i=0..11)** | 0x008200dc |
| `OPT_LTC_DIS : 0x%x` | 0x108ac000 | -15 | 0xcbb707 | 5 | 0x3090 | 1 | **0x00823090** | 0x008200dc |
| `head` | 0x10308000 | -33 | 0xcc0f4d | 5 | 0x808 | 1 | **0x00820808** | 0x008200dc |
| `OPT_MCHIP_EN   : 0x%x` | 0x108b4000 | -20 | 0xcbd57b | 5 | 0x204 | 1 | **0x00820204** | 0x008200fc |
| `OPT_HDCP_EN    : 0x%x` | 0x10844000 | -12 | 0xcbd5ab | 5 | 0x2fc | 1 | **0x008202fc** | 0x008200fc |
| `OPT_GC6_ISLAND : 0x%x` | 0x10d34000 | +28 | 0xcbd5fb | 5 | 0xc04 | 1 | **0x00820c04** | 0x008200dc |
| `OPT_DISPLAY_DIS: 0x%x` | 0x10d34000 | -12 | 0xcbd5fb | 5 | 0xc04 | 1 | **0x00820c04** | 0x008200dc |
| `OPT_NVDEC_DIS  : 0x%x` | 0x10da4000 | -12 | 0xcbd623 | 5 | 0xc24 | 1 | **0x00820c24** | 0x008200dc |
| `OPT_NVENC_DIS  : 0x%x` | 0x10dac000 | -12 | 0xcbd64b | 5 | 0xd68 | 1 | **0x00820d68** | 0x008200dc |
| `OPT_ECC_EN     : 0x%x` | 0x1073c000 | -12 | 0xcbd673 | 5 | 0x228 | 1 | **0x00820228** | 0x008200fc |
| `display` | 0x10300000 | -28 | 0xcc0f03 | 5 | 0x804 | 1 | **0x00820804** | 0x008200dc |
| `fbio_shift_override` | 0x10370000 | +46 | 0xcc0eb9 | 5 | 0x824 | 1 | **0x00820824** | 0x008200dc |
| `fbio_shift` | 0x10378000 | +46 | 0xcc1109 | 5 | 0x968 | 1 | **0x00820968** | 0x008200dc |
| `pcie_lane` | 0x10488000 | +46 | 0xcc0fe1 | 5 | 0x830 | 1 | **0x00820830** | 0x008200dc |
| `spare` | 0x10488000 | -28 | 0xcc0fe1 | 5 | 0x830 | 1 | **0x00820830** | 0x008200dc |

**表 A 的就近配对修正(机械配对规则见 §3.5,打印簇规则见 §3.4.1)**:

- 正确、可直接使用:`head`→`0x10308000`、`display`→`0x10300000`、`fbio`→`0x10310000`、`nvdec`→`0x10370000`、`nvenc`→`0x10378000`、`spare`→`0x10488000`;
  `OPT_CPC_DIS`→`0x106fc000`、`OPT_ROP_DIS`→`0x109f4000`、`OPT_LTC_DIS`→`0x108ac000`、`OPT_MCHIP_EN`→`0x108b4000`、`OPT_HDCP_EN`→`0x10844000`、
  `OPT_DISPLAY_DIS`→`0x10d34000`、`OPT_NVDEC_DIS`→`0x10da4000`、`OPT_NVENC_DIS`→`0x10dac000`、`OPT_ECC_EN`→`0x1073c000`、`OPT_PES_GPC%u_DIS`→`0x10984000`。
- **误配需作废**:
  `fbio_shift_override`(表 A 给 `0x10370000`,`Δ+46`;正确 ID `0x10320000`,表中无行)、
  `fbio_shift`(表 A 给 `0x10378000`;正确 `0x10318000`,无行)、
  `pcie_lane`(表 A 给 `0x10488000`;正确 `0x10398000`,无行)、
  `OPT_GC6_ISLAND`(表 A 给 `0x10d34000`,`Δ+28`;正确 `0x10d5c000`,无行)、
  `OPT_GPC_DISABLE`(表 A 给 `0x106fc000`,`Δ−62`,与 `OPT_CPC_DIS` 撞行;其真实 ID(`0x10xxxxxx` 族)在 GB202 表中无行,读站点在 `0xca8324`=`0x10e2c000` 簇,属通用打印/回退路径)。

### 3.2 表 B —— domain 5 中/低置信(最佳 0x40 < |Δ| ≤ 0xC0,共 17 条)

表 B 的配对需要人工判读,已知情况:
- `OPT_GPC_DISABLE` / `OPT_FBP_DISABLE` / `OPT_OFA_DISABLE` 的最佳 ID 与 `OPT_CPC_DIS` / `OPT_SYS_PIPE_DISABLE` **撞同一行**(`0x106fc000` / `0x10e24000`),属**误配**:它们的真实 ID(`0x10xxxxxx`)在 GB202 表中没有行(见 §3.4/既有审计)。
- `OPT_CE_DIS` / `OPT_SEC_DEBUG_EN` / `OPT_PRIV_SEC_EN` 同理(最佳 ID 撞到 `OPT_ECC_EN` / `OPT_NVDEC_DIS` 所属行);它们的真实 ID 不在表中。
- `OPT_ROP_L2_DIS` / `OPT_ZCULL_DIS` 与 `OPT_LTC_DIS` 撞 `0x108ac000`;`OPT_PES_DIS` 与 `OPT_PES_GPC%u_DIS` 撞 `0x10984000`(真实全局 PES ID `0x10974000` 不在表中,既有审计已证)。
- `fbp_l2slice[%u]=0x%x` / `gpc_rop[%u]=0x%x` 与 `0x10360000`(16 项数组 `0x822080..`)的配对由既有审计的代码簇分析支持(中)。
- `half_fbpa_enable`(Δ−157)、`Cannot read PIPE_GFX/PCE mask`(Δ−169/−104)属弱配对,仅作线索。

| 名字(池内原文) | 最佳 RegHal ID | Δ(字节) | 引用点(file) | domain | offset | count | 固定选择器真实地址(BAR0) | access PLM |
|---|---|---|---|---|---|---|---|---|
| `half_fbpa_enable` | 0x1059c000 | -157 | 0xcb6e99 | 5 | 0x0dc | 1 | **0x008200dc** | — |
| `Cannot read SYSPIPE_GFX mask` | 0x10d00000 | -169 | 0xc8b7e8 | 5 | 0x563c | 1 | **0x0082563c** | 0x008200fc |
| `OPT_SYS_PIPE_DISABLE` | 0x10e24000 | -69 | 0xca66a3 | 5 | 0x2a70 | 1 | **0x00822a70** | 0x008200dc |
| `OPT_OFA_DISABLE` | 0x10e24000 | -143 | 0xca66a3 | 5 | 0x2a70 | 1 | **0x00822a70** | 0x008200dc |
| `Cannot read PCE mask` | 0x10d04000 | -104 | 0xca7539 | 5 | 0x5580 | 71 | **0x00825580..0x00825698 +4*i (i=0..70)** | 0x008200fc |
| `OPT_FBP_DISABLE` | 0x106fc000 | -124 | 0x10f087a | 5 | 0x30e0 | 1 | **0x008230e0** | 0x008200dc |
| `gpc_rop[%u]=0x%x ` | 0x10360000 | +131 | 0xcad99f | 5 | 0x2080 | 16 | **0x00822080..0x008220bc +4*i (i=0..15)** | 0x00820010,0x008200dc |
| `fbp_l2slice[%u]=0x%x ` | 0x10360000 | -133 | 0xcad99f | 5 | 0x2080 | 16 | **0x00822080..0x008220bc +4*i (i=0..15)** | 0x00820010,0x008200dc |
| `OPT_PES_DIS : 0x%x` | 0x10984000 | -122 | 0xcb80f9 | 5 | 0x3600 | 12 | **0x00823600..0x0082362c +4*i (i=0..11)** | 0x008200dc |
| `OPT_ROP_L2_DIS : 0x%x` | 0x108ac000 | +135 | 0xcbb6cf | 5 | 0x3090 | 1 | **0x00823090** | 0x008200dc |
| `OPT_ZCULL_DIS  : 0x%x` | 0x108ac000 | +82 | 0xcbb6cf | 5 | 0x3090 | 1 | **0x00823090** | 0x008200dc |
| `fbp_rop_l2_enable` | 0x10368000 | -140 | 0xcbca62 | 5 | 0x970 | 16 | **0x00820970..0x008209ac +4*i (i=0..15)** | 0x00820010,0x008200dc |
| `fbp_rop_l2_disable` | 0x10368000 | -126 | 0xcbca62 | 5 | 0x970 | 16 | **0x00820970..0x008209ac +4*i (i=0..15)** | 0x00820010,0x008200dc |
| `OPT_CE_DIS     : 0x%x` | 0x1073c000 | -75 | 0xcbd673 | 5 | 0x228 | 1 | **0x00820228** | 0x008200fc |
| `OPT_SEC_DEBUG_EN: 0x%x` | 0x1073c000 | -115 | 0xcbd673 | 5 | 0x228 | 1 | **0x00820228** | 0x008200fc |
| `OPT_PRIV_SEC_EN: 0x%x` | 0x10da4000 | +106 | 0xcbd778 | 5 | 0xc24 | 1 | **0x00820c24** | 0x008200dc |
| `fbpa` | 0x10310000 | -102 | 0xcc102b | 5 | 0x814 | 1 | **0x00820814** | 0x008200dc |

### 3.3 表 C —— 最佳 ID 不在 domain 5(含四个任务目标名)

> **注意**:`domain 0` 的基址已在本报告 §4 闭合为 **`0x000000`**(offset = 绝对 PRI 号),
> 所以表 C 中 domain 0 的行可以读成"绝对 PRI 号 = offset";而 `domain 29/30/31/32/33/35/54/60` 等仍未闭合。
> 表 C 中 `地址状态` 列沿用扫描器的保守写法 `基址未闭合(dom N)`。


`domain 0` 是本表的重点:**四个目标名全部落在这里**。
- `PAC_DISABLE` / `fbp_pac` → ID `0x10338000`,(domain 0, offset `0x10`)
- `GPC_GFX_DISABLE` / `gpc_gfx`(read 侧)/ `gpc_tpc` / `TPC_GPCx_DISABLE` → ID `0x10348000`,(domain 0, offset `0x20`)
- `SYSPIPE_GFX_DISABLE` / `syspipe_gfx` / `SYS_PIPE_DISABLE` / `syspipe` → ID `0x10498000`,(domain 0, offset `0x10`)
- 另有 `0x104d8000`(domain 0, `0x20`)、`0x12004000`(domain 0, `0x8f0320`,4 项)、`0x129b4000`/`0x129bc000`(domain 0,`0x12004c`/`0x120048`)、`0x12fcc000`/`0x12fd4000`(domain 0,`0x11d000`/`0x11d21c`)、`0x129fc000`(domain 0,`0x122274`)等。
- `0x20xxxxxx` 行为 **field-setter(opcode 2)**:`words[3]=(msb<<16)|lsb` 是字段位,不是地址;其中 `gpc_gfx` `0x20eb0000`→bits[11:0]、`gpc_tpc` `0x20bdc000`→bits[7:0]、`gpc_pes` `0x203a8000`→bits[15:0]、`fbp_pac` `0x20ec8000`→bits[1:0] 等。**这些写侧描述符的 domain 是 5(fuse)**,与同名 read 行的 domain 0 不同域(见 §4.5)。

| 名字(池内原文) | 最佳 RegHal ID | Δ(字节) | 引用点(file) | domain | offset | count | 地址状态 | — |
|---|---|---|---|---|---|---|---|---|
| `unordered_map::at` | 0x12e04000 | -138 | 0xca07e2 | 0 | 0x0 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `gpc_pes_enable` | 0x409ac200 | -46 | 0xcb7143 | — | — | — | constant-setter(非 read 行) | — |
| `gpc_pes_disable` | 0x409ac200 | -81 | 0xcb7143 | — | — | — | constant-setter(非 read 行) | — |
| `Cannot read FBP mask` | 0x12b68000 | -50 | 0xc8baef | 60 | 0x438 | 1 | 基址未闭合(dom 60) | — |
| `Cannot read NVLINK mask` | 0x12dec000 | +101 | 0xc8d6e6 | 0 | 0x1 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `Cannot read FBIO mask` | 0x12b58000 | -53 | 0xcb5b1c | 60 | 0x43c | 1 | 基址未闭合(dom 60) | — |
| `SkipFspFs` | 0x129fc000 | +100 | 0xc8eaec | 0 | 0x122274 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `Cannot read TPC mask` | 0x42cfc000 | +62 | 0xcbd45f | — | — | — | constant-setter(非 read 行) | — |
| `UseBootResetForFs` | 0x429fc104 | -58 | 0xc8f3f7 | — | — | — | constant-setter(非 read 行) | — |
| `PollPriRingCmdNone` | 0x429fc000 | -51 | 0xc9f57d | — | — | — | constant-setter(非 read 行) | — |
| `InitializePriRing` | 0x429fc104 | +32 | 0xc8ecc0 | — | — | — | constant-setter(非 read 行) | — |
| `PollPriRingStatus` | 0x429fc104 | +33 | 0xc9f60b | — | — | — | constant-setter(非 read 行) | — |
| `Exit Code` | 0x429fc104 | -179 | 0xc8ecc0 | — | — | — | constant-setter(非 read 行) | — |
| `InitializePriRing_FirstStage` | 0x429fc002 | -57 | 0xc9f969 | — | — | — | constant-setter(非 read 行) | — |
| `PAC_DISABLE` | 0x10338000 | -16 | 0xc98a99 | 0 | 0x10 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `fbp_pac` | 0x20ec8000 | +20 | 0xc98ad1 | — | — | — | field-setter(非 read 行) | — |
| `C2CHBI_DISABLE` | 0x20e9c000 | +37 | 0xc98bad | — | — | — | field-setter(非 read 行) | — |
| `c2chbi_group` | 0x20e9c000 | +20 | 0xc98bad | — | — | — | field-setter(非 read 行) | — |
| `GPC_GFX_DISABLE` | 0x10348000 | -16 | 0xc98c67 | 0 | 0x20 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `gpc_gfx` | 0x20eb0000 | +20 | 0xc98c9f | — | — | — | field-setter(非 read 行) | — |
| `SYSPIPE_GFX_DISABLE` | 0x10498000 | -16 | 0xc98da0 | 0 | 0x10 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `syspipe_gfx` | 0x10498000 | -39 | 0xc98da0 | 0 | 0x10 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `TPC_DISABLE` | 0x20bdc000 | +37 | 0xc98fbf | — | — | — | field-setter(非 read 行) | — |
| `gpc_tpc` | 0x20bdc000 | +20 | 0xc98fbf | — | — | — | field-setter(非 read 行) | — |
| `CPC_DISABLE` | 0x206fc000 | +37 | 0xc9908d | — | — | — | field-setter(非 read 行) | — |
| `gpc_cpc` | 0x206fc000 | +20 | 0xc9908d | — | — | — | field-setter(非 read 行) | — |
| `ROP_DISABLE` | 0x209f4000 | +37 | 0xc9915b | — | — | — | field-setter(非 read 行) | — |
| `gpc_rop` | 0x209f4000 | +20 | 0xc9915b | — | — | — | field-setter(非 read 行) | — |
| `PES_DISABLE` | 0x203a8000 | +43 | 0xc9922f | — | — | — | field-setter(非 read 行) | — |
| `gpc_pes` | 0x203a8000 | +26 | 0xc9922f | — | — | — | field-setter(非 read 行) | — |
| `LTC_DISABLE` | 0x208ac000 | +37 | 0xc992f7 | — | — | — | field-setter(非 read 行) | — |
| `fbp_ltc` | 0x208ac000 | +20 | 0xc992f7 | — | — | — | field-setter(非 read 行) | — |
| `L2SLICE_DISABLE` | 0x20894000 | +37 | 0xc993c5 | — | — | — | field-setter(非 read 行) | — |
| `fbp_l2slice` | 0x20894000 | +20 | 0xc993c5 | — | — | — | field-setter(非 read 行) | — |
| `SYSLTC_DISABLE` | 0x20ee8000 | +43 | 0xc995fe | — | — | — | field-setter(非 read 行) | — |
| `sysltc` | 0x20ee8000 | +14 | 0xc995fe | — | — | — | field-setter(非 read 行) | — |
| `HSHUB_DISABLE` | 0x20e88000 | -141 | 0xc99604 | — | — | — | field-setter(非 read 行) | — |
| `hshub` | 0x20e88000 | -156 | 0xc99604 | — | — | — | field-setter(非 read 行) | — |
| `GSP_DISABLE` | 0x20ec4000 | +188 | 0xc99b04 | — | — | — | field-setter(非 read 行) | — |
| `OOB_HUB_DISABLE` | 0x20ec4000 | +29 | 0xc99b04 | — | — | — | field-setter(非 read 行) | — |
| `oobhub` | 0x20ec4000 | +14 | 0xc99b04 | — | — | — | field-setter(非 read 行) | — |
| `RHXB_DISABLE` | 0x20ed8000 | +29 | 0xc99ba3 | — | — | — | field-setter(非 read 行) | — |
| `rhxb` | 0x20ed8000 | +14 | 0xc99ba3 | — | — | — | field-setter(非 read 行) | — |
| `SEC_DISABLE` | 0x20e84000 | +35 | 0xc99c48 | — | — | — | field-setter(非 read 行) | — |
| `GPC_DISABLE` | 0x207fc000 | +29 | 0xc99ce1 | — | — | — | field-setter(非 read 行) | — |
| `FBP_DISABLE` | 0x20774000 | +29 | 0xc99d80 | — | — | — | field-setter(非 read 行) | — |
| `FBIO_DISABLE` | 0x20754000 | +29 | 0xc99e1f | — | — | — | field-setter(非 read 行) | — |
| `fbio` | 0x20754000 | +14 | 0xc99e1f | — | — | — | field-setter(非 read 行) | — |
| `SYS_PIPE_DISABLE` | 0x10498000 | -22 | 0xc99eb2 | 0 | 0x10 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `syspipe` | 0x20bb4000 | +14 | 0xc99ee5 | — | — | — | field-setter(非 read 行) | — |
| `OFA_DISABLE` | 0x20914000 | +29 | 0xc99f84 | — | — | — | field-setter(非 read 行) | — |
| `NVJPG_DISABLE` | 0x208f4000 | +29 | 0xc9a023 | — | — | — | field-setter(非 read 行) | — |
| `nvjpg` | 0x208f4000 | +14 | 0xc9a023 | — | — | — | field-setter(非 read 行) | — |
| `C2C_DISABLE` | 0x206e4000 | +29 | 0xc9a0c2 | — | — | — | field-setter(非 read 行) | — |
| `NVDEC_DISABLE` | 0x208dc000 | +29 | 0xc9a161 | — | — | — | field-setter(非 read 行) | — |
| `nvdec` | 0x208dc000 | +14 | 0xc9a161 | — | — | — | field-setter(非 read 行) | — |
| `NVENC_DISABLE` | 0x208e4000 | +29 | 0xc9a200 | — | — | — | field-setter(非 read 行) | — |
| `nvenc` | 0x208e4000 | +14 | 0xc9a200 | — | — | — | field-setter(非 read 行) | — |
| `NVLINK_DISABLE` | 0x20378000 | -179 | 0xc9a206 | — | — | — | field-setter(非 read 行) | — |
| `%s : 0x%x` | 0x104d8000 | +157 | 0xca73b3 | 0 | 0x20 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `TPC_GPCx_DISABLE` | 0x10348000 | -21 | 0xcb2220 | 0 | 0x20 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `FS IFR Records:` | 0x12340000 | +160 | 0xcb2a41 | 54 | 0x200 | 1 | 基址未闭合(dom 54) | — |
| `[0x%08x] = 0x%08x` | 0x12340000 | +124 | 0xcb2a41 | 54 | 0x200 | 1 | 基址未闭合(dom 54) | — |
| `Adjusting GPC mask to 0x%x` | 0x12b58000 | +159 | 0xcb68b3 | 60 | 0x43c | 1 | 基址未闭合(dom 60) | — |
| `GpcEnableMask` | 0x42be0001 | -34 | 0xcc3655 | — | — | — | constant-setter(非 read 行) | — |
| `GpcEnableMask is not valid!!` | 0x42be0001 | -122 | 0xcc3655 | — | — | — | constant-setter(非 read 行) | — |
| `PollMasterRingCommand` | 0x129b4000 | -39 | 0xcc3bd1 | 0 | 0x12004c | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `...done` | 0x129bc000 | +28 | 0xcc3c45 | 0 | 0x120048 | 1 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `SkipFsPlmCheck` | 0x409c4000 | +99 | 0xcc5080 | — | — | — | constant-setter(非 read 行) | — |
| `ZcullEnableMaskOnGpc` | 0x12b78000 | +191 | 0xcc678b | 60 | 0x450 | 1 | 基址未闭合(dom 60) | — |
| `SetAspm on GPU: 0x%x` | 0x21ac4000 | -15 | 0xcd7c72 | — | — | — | field-setter(非 read 行) | — |
| `Invalid lane %u specified` | 0x22fcc000 | -20 | 0xcddbdb | — | — | — | field-setter(非 read 行) | — |
| `Margining not ready!` | 0x21adc200 | -15 | 0xcdb290 | — | — | — | field-setter(非 read 行) | — |
| `RunMarginCommand` | 0x11aac000 | -104 | 0xcdbaa6 | 33 | 0x208 | 16 | 基址未闭合(dom 33) | — |
| `VerifyMarginOffset` | 0x21aac000 | -187 | 0xcdbd0e | — | — | — | field-setter(非 read 行) | — |
| `Cannot enable AER` | 0x232e0000 | -80 | 0xcdea99 | — | — | — | field-setter(非 read 行) | — |
| `SetAspmCya on GPU: 0x%x` | 0x2331c300 | -31 | 0xcdf81b | — | — | — | field-setter(非 read 行) | — |
| `, BOOTFSM` | 0x12004000 | +179 | 0xcdfab9 | 0 | 0x8f0320 | 4 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `(POS=0x%x)` | 0x12004000 | +130 | 0xcdfab9 | 0 | 0x8f0320 | 4 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `FSP Debug Regs:` | 0x12004000 | -25 | 0xcdfab9 | 0 | 0x8f0320 | 4 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |
| `reg:0x%x value:0x%x` | 0x12004000 | -52 | 0xcdfbca | 0 | 0x8f0320 | 4 | **dom 0 基址=0 ⇒ 绝对 PRI 号 = offset**(§4) | — |

### 3.4 表 D —— 负结果:邻近只有"不在 GB202 表中"的 RegHal 形即时数(共 93 条)

这些名字的代码窗口里存在 RegHal 形 ID,但它们在 chip `0xff2` 的 20083 行表里 **0 行**;
运行时该 ID 走 `0x19c69c0` 前置检查失败分支,日志格式串为 `Invalid register 0x%x%s specified for this GPU`(file `0x8d0b0f8`)。
多数属"共享代码里的其它芯片条目"或"名字与 ID 只是相邻而非同一寄存器",故本表**只作为负结果与线索**,不构成地址。


| 名字(池内原文) | 邻近的 RegHal 形即时数(不在 GB202 表中) | Δ | 引用点(file) |
|---|---|---|---|
| `ConfigGet` | 0x18771800(+6), 0x187715e0(+11), 0x178745a0(+21) | — | 0x3c8fe7, 0x154db2a9, 0x154ea753 |
| `ConfigSet` | 0x18771800(+4), 0x187715a0(+15), 0x178745a0(+25) | — | 0x3c9023 |
| `RunStressTest` | 0x18771800(+4), 0x18771560(+15), 0x178745a0(+25) | — | 0x3c9063 |
| `Access an I2C device.` | 0x18771560(-20), 0x18771800(+20), 0x178745a0(-25) | — | 0x3c9095, 0xdf84980, 0xdf8f280 |
| `I2CAccess` | 0x18771800(+4), 0x18771520(+9), 0x178745a0(+23) | — | 0x3c90a5 |
| `GetBuildVersion` | 0x18771800(+4), 0x187714e0(+9), 0x178745a0(+23) | — | 0x3c90e5 |
| `GetDeviceHandle` | 0x18771800(+4), 0x187713e0(+9), 0x187714e0(-16) | — | 0x3c9111 |
| `gpc_cpc_enable` | 0x178a0440(-70) | — | 0xca2526, 0xca2679, 0x8ece390 |
| `gpc_rop_enable` | 0x178a0600(-118) | — | 0xcabe56, 0xcabfb1, 0x8ece3e0 |
| `fbp_ltc_enable` | 0x10a04000(-49), 0x1881f770(-60), 0x178a0a20(-132) | — | 0xcbc6c4, 0xcbc78e, 0xcbcb9f |
| `nvdec_enable` | 0x178a0ae0(-101) | — | 0xcbe22d, 0xcbe2ad, 0x8ece700 |
| `nvdec_disable` | 0x1881f770(+186), 0x10dd4000(+191) | — | 0xcbe2be, 0xcbe381, 0x1ad494b |
| `nvenc_enable` | 0x178a0ae0(-65) | — | 0xcbe209, 0xcbe27a, 0x8ece750 |
| `nvenc_disable` | 0x1881f770(+154), 0x10dd4000(+159) | — | 0xcbe28b, 0xcbe3a1, 0x1b6a6a7 |
| `display_enable` | 0x178a0ca0(-65) | — | 0xcc48d2, 0xcc4a08, 0x8ece7a0 |
| `half_fbpa_disable` | 0x178a0940(-170) | — | 0xcb6f6d, 0xcb73d3, 0x8ece818 |
| `PriRingPollTimeoutMs` | 0x187a1880(+121), 0x1879aaa0(+126), 0x178745a0(+136) | — | 0x3e7862, 0xc8c887, 0xcb0527 |
| `nvlink_perlink_enable` | 0x18784958(+91), 0x18784960(+120), 0x178745a0(+130) | — | 0xc906f5, 0x8ecfb10, 0x1749e940 |
| `nvlink_perlink_disable` | 0x18784958(+70), 0x18784960(+99), 0x178745a0(+109) | — | 0xc9070a, 0x1b1ba86, 0x8ecfb38 |
| `7/7/2023` | 0x18784960(+9), 0x178745a0(+19), 0x18784958(-20) | — | 0xc90764 |
| `deprecNvlinkPerlink` | 0x18784958(+38), 0x18784960(+67), 0x178745a0(+77) | — | 0xc9072a, 0xc90769 |
| `DisableCeInterrupts` | 0x187a1880(+101), 0x1879aaa0(+106), 0x178745a0(+116) | — | 0x3e7876, 0xc95363, 0xc95433 |
| `PERLINK_DISABLE` | 0x20964000(+37), 0x203a0000(+43), 0x103a0000(-50) | — | 0xc98ecc |
| `nvlc_perlink` | 0x20964000(+20), 0x203a0000(+26), 0x103a0000(-67) | — | 0xc98edd |
| `HSHUBNVL_DISABLE` | 0x20eb8000(+29), 0x20e60000(+35), 0x20e5c000(-124) | — | 0xc99730, 0xa2835d0 |
| `hshubnvl` | 0x20eb8000(+14), 0x20e60000(+20), 0x20e5c000(-139) | — | 0xc9973f, 0x1148b79, 0x114ec31 |
| `SCB_DISABLE` | 0x20edc000(+29), 0x20e80000(+35), 0x20e60000(-124) | — | 0xc997cf |
| `c2cmisc` | 0x20edc000(+14), 0x20e80000(+20), 0x20e60000(-139) | — | 0xc997de |
| `PCIE_DISABLE` | 0x20ecc000(+29), 0x20e6c000(+35), 0x20e80000(-121) | — | 0xc9986b |
| `pcie` | 0x20ecc000(+14), 0x20e6c000(+20), 0x20e80000(-136) | — | 0x664375, 0x671f35, 0xc9987a |
| `FSP_DISABLE` | 0x20eac000(+29), 0x20e50000(+35), 0x20e6c000(-124) | — | 0xc9990a |
| `PMU_DISABLE` | 0x20ed4000(+29), 0x20e78000(+35), 0x20e50000(-124) | — | 0xc999a9 |
| `nvlink` | 0x208fc000(+14), 0x20388000(+20), 0x1881f770(+41) | — | 0xc9a2c8, 0x114ec01, 0x1158a2c |
| `nvlink_enable` | 0x1881f770(+170), 0x10358000(+175), 0x1881f770(+187) | — | 0xcb39f1, 0xcb3a2b, 0x8ed1e40 |
| `nvlink_disable` | 0x1881f770(+24), 0x10388000(+29), 0x1881f770(+105) | — | 0xcb3a43, 0xcb3b67, 0x1b59f6f |
| `OPT_PERLINK_DISABLE` | 0x10ddc000(-70), 0x1881f770(-75) | — | 0x506165, 0x50bb34, 0x522926 |
| `OPT_C2C_DISABLE` | 0x178745a0(-11), 0x178745a0(-11), 0x178745a0(-11) | — | 0x504c86, 0x509e7f, 0x521447 |
| `OPT_CPC_DISABLE` | 0x178745a0(-97), 0x178745a0(-97), 0x178745a0(-97) | — | 0x504cdc, 0x509eec, 0x52149d |
| `OPT_FBIO_DISABLE` | 0x178745a0(-11), 0x178745a0(-11), 0x178745a0(-11) | — | 0x50369e, 0x504ecb, 0x50a00d |
| `half_ltc` | 0x1881f770(+97), 0x22341200(+102), 0x1881f770(+121) | — | 0xcb26b0 |
| `nvlink` | 0x1881f770(+81), 0x22341200(+86), 0x1881f770(+105) | — | 0xcb26c0 |
| `half_ltc` | 0x1881f770(+151), 0x10358000(+156), 0x1881f770(+192) | — | 0xcb3a15, 0x8ed1e90 |
| `fbp_rop_l2` | 0x10a04000(-99), 0x1881f770(-104) | — | 0xcbb41e, 0xcbb4f1 |
| `%s[%d] ` | 0x10a04000(-176), 0x1881f770(-181) | — | 0xcbb46b |
| `RopL2` | 0x10a04000(-51), 0x1881f770(-56) | — | 0xcbcf12, 0xbb155f0, 0xbc4fc16 |
| `fbp%s[%d]_mask` | 0x10a04000(-110), 0x1881f770(-115) | — | 0xcbcf4d, 0xac825e7 |
| `head_enable` | 0x178a0ae0(-137) | — | 0xcbe251, 0xcbe2dd, 0x8ed4900 |
| `Cannot read XP mask` | 0x20dd4000(-52), 0x1881f770(-57), 0x20dd4000(-87) | — | 0xcbe4d1 |
| `gpc_zcull` | 0x104a8000(-55) | — | 0xcc0bca, 0xcc0be1 |
| `pcie_lane_enable` | 0x178a0bc0(-80), 0x22b3c100(-110), 0x1881f770(-118) | — | 0xcc1d61, 0xcc1dc9, 0x8ed4f00 |
| `fbpa_enable` | 0x178a0bc0(-114), 0x22b3c100(-144), 0x1881f770(-152) | — | 0xcc1d83, 0xcc1dfa, 0x8ed4f50 |
| `spare_enable` | 0x178a0bc0(-148), 0x22b3c100(-178), 0x1881f770(-186) | — | 0xcc1da5, 0xcc1e2a, 0x8ed4fa0 |
| `msdec_enable` | 0x178a0ca0(-101) | — | 0xcc48f6, 0xcc4a42, 0x8ed5070 |
| `msvld_enable` | 0x178a0ca0(-137) | — | 0xcc491a, 0xcc4a75, 0x8ed50c0 |
| `fbio_shift_override_enable` | 0x178a0ca0(-173) | — | 0xcc493e, 0xcc4aa8, 0x8ed5110 |
| `Mode` | 0x18822480(+4), 0x18822120(+9), 0x1888a4e0(+16) | — | 0x4a24cd, 0x5b2e0f, 0xccc1e8 |
| `Invalid fslib mode %u` | 0x18786248(+53) | — | 0xccc201, 0xccc8d7 |
| `Testing with Fslib mode %u` | 0x18786248(-132), 0x18786240(-186) | — | 0xccf2e0, 0xcd0185, 0xcd02f3 |
| `GpcMask` | 0x187a1880(+4), 0x1879db60(+9), 0x178745a0(+19) | — | 0x3e54ae, 0xccf4eb, 0xdc2931 |
| `FbpMask` | 0x187a1880(+4), 0x1879da40(+9), 0x178745a0(+19) | — | 0x3e5570, 0xccf768, 0xdbecd1 |
| `FsLib interface.` | 0x178a0f40(+10), 0x18786240(-17), 0x187861a0(+20) | — | 0x3d3529 |
| `FsLib` | 0x187861a0(+4), 0x178a0f40(-6), 0x178745a0(+16) | — | 0x3d3539, 0x1749ff40 |
| `SetMode` | 0x1878a240(+4), 0x187afb20(+4), 0x187861a0(+9) | — | 0x3d35ad, 0x3dab90, 0x3f90f8 |
| `IsFloorsweepingValid` | 0x187861a0(+4), 0x187860e0(+9), 0x178745a0(+19) | — | 0x3d35f0 |
| `SetTimeoutMs` | 0x187861a0(+4), 0x187860a0(+9), 0x178745a0(+19) | — | 0x3d362e |
| `MODE_DISABLE` | 0x187861a0(+4), 0x18786040(+9), 0x178745a0(+19) | — | 0x3d3671 |
| `CONSTANT: MODE_DISABLE` | 0x187860a0(-20), 0x178745a0(-25), 0x187861a0(+27) | — | 0x3d365a |
| `MODE_FUNC_VALID` | 0x187861a0(+4), 0x18785fe0(+9), 0x178745a0(+19) | — | 0x3d36b4 |
| `CONSTANT: MODE_FUNC_VALID` | 0x18786040(-20), 0x178745a0(-25), 0x187861a0(+27) | — | 0x3d369d |
| `MODE_PRODUCT` | 0x187861a0(+4), 0x18785f80(+12), 0x18785fe0(-25) | — | 0x3d36e5 |
| `CONSTANT: MODE_PRODUCT` | 0x187861a0(+11), 0x18785fe0(-18), 0x18785f80(+19) | — | 0x3d36de |
| `NV_%s = 0x%08x` | 0x1881f770(-48), 0x1881f770(-50), 0x1881f770(-108) | — | 0xcd3ecf, 0xcd401f |
| `Rm call failed ` | 0x20801802(-64), 0x20801814(+176), 0x187686e0(-188) | — | 0xcd6ce1 |
| `due to a training error` | 0x20801804(-139) | — | 0xcd77c7 |
| `because ASLM is disabled` | 0x20801804(-176) | — | 0xcd77ec |
| `speed unknown` | 0x20801802(-166) | — | 0xcd7ef1 |
| `Cannot train Gpu to %dMB/s` | 0x20801805(-17) | — | 0xcd8180 |
| `&PollEomDone` | 0x1881f770(-21), 0x23274000(-26), 0x1881f770(+64) | — | 0xcda03e, 0x14cc36b, 0x14cc48f |
| `DoGetEomStatus` | 0x1881f770(-26), 0x1881f770(+31), 0x23274000(-31) | — | 0xcda043, 0xcda94e, 0xcdaa9e |
| `Unsupported FOM mode : %d` | 0x1881f770(+111), 0x43274000(+116), 0x43274000(+150) | — | 0xcdcf38, 0xcdd6b9, 0x1575c4a |
| `PciCfgSpace` | 0x18786c40(+4), 0x178a4720(-6), 0x178745a0(+14) | — | 0x3d5769, 0xce28e6, 0xce2a91 |
| `CheckCfgSpaceNotReady` | 0x18786c40(+4), 0x18786b40(+9), 0x178745a0(+19) | — | 0x3d5856, 0xce2ac3, 0xce37b2 |
| `CheckCfgSpaceReady` | 0x18786c40(+9), 0x18786b80(+14), 0x178745a0(+24) | — | 0x3d5813, 0xce2b73, 0xce3782 |
| `Test device is not a GPU` | 0x178a47c0(-33), 0x178a4800(+39) | — | 0xce3ef1, 0xdd7899 |
| `PciCfgSpace JS Object` | 0x178a4720(+14), 0x18786cd0(-19), 0x178745a0(-24) | — | 0x3d5755 |
| `Save the PciCfgSpace data` | 0x18786c40(+17), 0x18786c40(-19), 0x178745a0(-24) | — | 0x3d578f |
| `Save` | 0x18786c40(+4), 0x18786c00(+12), 0x178745a0(+22) | — | 0x3d579c |
| `Restore the PciCfgSpace data` | 0x18786c00(-19), 0x18786c40(+20), 0x178745a0(-24) | — | 0x3d57ca |
| `Restore` | 0x18786c40(+4), 0x18786bc0(+9), 0x178745a0(+19) | — | 0x3d57da |
| `SaveCfgSpaceToFile` | 0x18786c40(+4), 0x18786b00(+9), 0x178745a0(+19) | — | 0x3d5894 |
| `RestoreCfgSpaceFromFile` | 0x18786c40(+4), 0x18786ac0(+13), 0x18786b00(-19) | — | 0x3d58bf |
| `GPIO notification (%d) added` | 0x208f1301(+74) | — | 0xceb026 |
| `Unknown C2C ` | 0x11684000(-67), 0x1881f770(-72), 0x1168c000(-99) | — | 0xcee77c |
### 3.4.1 表 D2 —— "形态正确但 GB202 表中不存在"的最近 ID(负结果的可判定子集)

下表把"最近邻是 RegHal 读 ID 形态(`imm < 0x17000000` 且低 12 位为 0)、但该 ID 在 0xff2 表中 0 行"的名字单独列出。
注意:`0x1881f770`/`0x178745a0` 这类值其实是 **.text/.data 里的数据指针**,已在本表中剔除(它们不是 RegHal ID)。
最后一列标出"是否存在更近的 in-table ID"——若存在,说明机器表 A/B/C 的就近配对是**误配**,以本表给出的 ID 为准。

| 名字(池内原文) | 邻近的"形态正确但表中不存在"ID | Δ | 引用点(file) | 是否有更近的 in-table ID(若有=需按此表修正) |
|---|---|---|---|---|
| 0x8d38967 `fbio` | **0x10330000** | +46 | 0xcc1075 | 有:0x20754000(Δ+14,见表 A/B/C) |
| 0x8d389e1 `NVLINK_DISABLE` | **0x10388000** | -38 | 0xc9a293 | 有:0x20378000(Δ-179,见表 A/B/C) |
| 0x8d389f0 `nvlink` | **0x10968000** | +46 | 0x1158a5a | 无 |
| 0x8d38c7e `nvlink_disable` | **0x10388000** | +29 | 0xcb3b84 | 无 |
| 0x8d391c7 `OPT_PES_DIS : 0x%x` | **0x10974000** | -9 | 0xcb816a | 有:0x10984000(Δ-122,见表 A/B/C) |
| 0x8d39217 `OPT_ROP_L2_DIS : 0x%x` | **0x10a04000** | -22 | 0xcbb632 | 有:0x108ac000(Δ+135,见表 A/B/C) |
| 0x8d39244 `OPT_ZCULL_DIS  : 0x%x` | **0x10c24000** | -22 | 0xcbb667 | 有:0x108ac000(Δ+82,见表 A/B/C) |
| 0x8d3925c `fbp_rop_l2_enable` | **0x10a04000** | -17 | 0xcbc693 | 有:0x10368000(Δ-140,见表 A/B/C) |
| 0x8d3929a `head` | **0x10398000** | +41 | 0xcc0f97 | 有:0x10308000(Δ-33,见表 A/B/C) |
| 0x8d392b7 `OPT_HDCP_EN    : 0x%x` | **0x10d5c000** | +28 | 0xcbd5d3 | 有:0x10844000(Δ-12,见表 A/B/C) |
| 0x8d392cf `OPT_GC6_ISLAND : 0x%x` | **0x10d5c000** | -12 | 0xcbd5d3 | 有:0x10d34000(Δ+28,见表 A/B/C) |
| 0x8d3932f `OPT_ECC_EN     : 0x%x` | **0x10d24000** | +44 | 0xcbd6ab | 有:0x1073c000(Δ-12,见表 A/B/C) |
| 0x8d39347 `OPT_CE_DIS     : 0x%x` | **0x10d24000** | -19 | 0xcbd6ab | 有:0x1073c000(Δ-75,见表 A/B/C) |
| 0x8d3935f `OPT_SEC_DEBUG_EN: 0x%x` | **0x10a54000** | -11 | 0xcbd6db | 有:0x1073c000(Δ-115,见表 A/B/C) |
| 0x8d39378 `OPT_PRIV_SEC_EN: 0x%x` | **0x10df4000** | -11 | 0xcbd703 | 有:0x10da4000(Δ+106,见表 A/B/C) |
| 0x8d393d0 `fbio_shift_override` | **0x10320000** | -28 | 0xcc0e6f | 有:0x10370000(Δ+46,见表 A/B/C) |
| 0x8d393e7 `fbio_shift` | **0x10318000** | -28 | 0xcc10bf | 有:0x10378000(Δ+46,见表 A/B/C) |
| 0x8d393f2 `pcie_lane` | **0x10398000** | -28 | 0xcc0f97 | 有:0x10488000(Δ+46,见表 A/B/C) |
| 0x8d393fc `fbpa` | **0x10330000** | -28 | 0xcc1075 | 有:0x10310000(Δ-102,见表 A/B/C) |
| 0x8d39d5a `Invalid lane %u specified` | **0x13268000** | -37 | 0x15730ae | 有:0x22fcc000(Δ-20,见表 A/B/C) |

**归属修正(按"最近且符号优先"与 §3.5 的机械配对规则)**:

- 打印簇(`0xcbd5xx..0xcbd7xx`,OPT_* 逐条打印)按 Δ 就近归属:
  `0x10974000` → `OPT_PES_DIS`(Δ−9)、`0x10a04000` → `OPT_ROP_L2_DIS`(Δ−22)、`0x10c24000` → `OPT_ZCULL_DIS`(Δ−22)、
  `0x10d5c000` → `OPT_GC6_ISLAND`(Δ−12;表 A 中 `OPT_HDCP_EN` 的 +28 命中属误配)、`0x10d24000` → `OPT_CE_DIS`(Δ−19;`OPT_ECC_EN` 的 +44 属误配)、
  `0x10a54000` → `OPT_SEC_DEBUG_EN`(Δ−11)、`0x10df4000` → `OPT_PRIV_SEC_EN`(Δ−11)。
- 单位簇(`0xcc0a00..0xcc1300`)按 §3.5 机械规则(名字紧跟其 ID 之后):
  `0x10320000`→`fbio_shift_override`、`0x10318000`→`fbio_shift`、`0x10398000`→`pcie_lane`、`0x10330000`→`fbpa`、
  `0x104a8000`→`gpc_zcull`、`0x102e8000`→`ce`;表 A 中这三条(Δ=+46)是**误配**,应改为本表 ID(均为"表中无行")。
- `head`/`fbio` 在 D2 中的 `0x10398000`/`0x10330000` 分别是 `pcie_lane`/`fbpa` 的 ID(同一簇),**不能**算作 `head`/`fbio`。
- `OPT_PES_DISABLE`/`OPT_TPC_DISABLE`/`OPT_LTC_DISABLE`/`OPT_ROP_DISABLE`/`OPT_NVDEC_DISABLE`/`OPT_NVENC_DISABLE`/`OPT_NVJPG_DISABLE`/`OPT_C2C_DISABLE`/`OPT_PERLINK_DISABLE`
  等名字在代码里以**数据指针**(如 `0x178745a0`)出现于描述符表,窗口内没有可用 ID ⇒ 归入"名字不可闭合"(负结果),不强行给地址。

### 3.5 表 E —— FsLib 单位簇的机械配对(FACT)

file `0xcc0a00..0xcc1300` 的代码形态为:
`mov edx, <ID>; xor esi,esi; call 0x19cdce0(检查该 ID 是否被本 GPU 支持)`,随后把**单位名字符串**写入描述符(`mov qword ptr [rsp+0x50], <name VA>` / 追加到链表)。
按该固定形态逐条提取得到(名字 VA − 0x400000 = 池内 file 偏移):

| 单位名(池内) | IM ID | GB202 行 | (domain, offset, count) | 固定选择器地址 |
|---|---|---|---|---|
| `gpc_zcull` | `0x104a8000` | **无** | — | — |
| `ce` | `0x102e8000` | **无** | — | — |
| `fbp` | `0x10328000` | 有 | (5, `0x938`, 1) | `0x00820938` |
| `fbp`(备选分支 ID) | `0x10754000` | 有 | (5, `0x3014`, 1) | `0x00823014` |
| `fbio_shift_override` | `0x10320000` | **无** | — | — |
| `nvdec` | `0x10370000` | 有 | (5, `0x824`, 1) | `0x00820824` |
| `display` | `0x10300000` | 有 | (5, `0x804`, 1) | `0x00820804` |
| `head` | `0x10308000` | 有 | (5, `0x808`, 1) | `0x00820808` |
| `pcie_lane` | `0x10398000` | **无** | — | — |
| `spare` | `0x10488000` | 有 | (5, `0x830`, 1) | `0x00820830` |
| `fbio` | `0x10310000` | 有 | (5, `0x814`, 1) | `0x00820814` |
| `fbpa` | `0x10330000` | **无** | — | — |
| `fbio_shift` | `0x10318000` | **无** | — | — |
| `nvenc` | `0x10378000` | 有 | (5, `0x968`, 1) | `0x00820968` |

(另有 `gpc_tpc` → `0x104a0000`(5, `0x838`, count 32,`0x00820838..0x008208b4`),来自既有审计的代码簇分析,与表 A/B 一致。)

### 3.6 表 F —— 池内名字可到达的 domain-5 数组寄存器(count > 1,共 15 个 ID 组)

| ID(主/备用) | count | offset 范围 | BAR0 范围(`0x00820000+offset+4*i`) | access PLM | 池内典型名字 |
|---|---|---|---|---|---|
| `0x104a0000` | 32 | `0x838..0x8b4` | `0x00820838..0x008208b4` | `0x00820020`/`0x008200dc` | `gpc_tpc` |
| `0x10368000` | 16 | `0x970..0x9ac` | `0x00820970..0x008209ac` | `0x00820010`/`0x008200dc` | `fbp_ltc_disable`、`fbp_rop_l2_*` |
| `0x10e2c000` | 32 | `0xc38..0xcb4` | `0x00820c38..0x00820cb4` | `0x00820020` | `Cannot read TPC mask` |
| `0x10d9c000` | 16 | `0xd70..0xdac` | `0x00820d70..0x00820dac` | `0x00820010`/`0x008200dc` | `Cannot read L2 mask` |
| `0x10360000` | 16 | `0x2080..0x20bc` | `0x00822080..0x008220bc` | `0x00820010`/`0x008200dc` | `fbp_l2slice[%u]=0x%x` |
| `0x103a8000` | 16 | `0x2178..0x21b4` | `0x00822178..0x008221b4` | `0x00820010` | `gpc_pes_*` |
| `0x10dfc000` | 16 | `0x2880..0x28bc` | `0x00822880..0x008228bc` | `0x00820010` | (邻 `OPT_ROP_DIS` 簇) |
| `0x10d94000` | 16 | `0x2900..0x293c` | `0x00822900..0x0082293c` | `0x00820010` | (邻 `%s0x%x'` 打印簇) |
| `0x10d2c000` | 16 | `0x2a00..0x2a3c` | `0x00822a00..0x00822a3c` | `0x00820010` | (同上) |
| `0x10de4000` | 16 | `0x2a78..0x2ab4` | `0x00822a78..0x00822ab4` | `0x00820010` | `Cannot read PES mask` |
| `0x10894000`/`0x10898000` | 8 | `0x34e0..0x34fc` | `0x008234e0..0x008234fc` | `0x008200dc` | `OPT_ROP_DIS` 簇 / `gpc_gfx` |
| `0x10984000`/`0x10988000` | 12 | `0x3600..0x362c` | `0x00823600..0x0082362c` | `0x008200dc` | `OPT_PES_GPC%u_DIS` |
| `0x10d04000` | 71 | `0x5580..0x5698` | `0x00825580..0x00825698` | `0x008200fc` | `Cannot read PCE mask`(配对中置信) |

> **FACT(交叉验证要点)**:表中 `0x00820010` 与 `0x00820020` 是**真实使用中的 fuse 区寄存器地址** —— 它们分别是 PES 掩码族(`0x103a8000`/`0x10360000`/`0x10de4000`…)与 TPC 掩码族(`0x10e2c000`/`0x104a0000`…)的 **access-PLM**。这一点与四个目标名(domain 0, offset `0x10`/`0x20`)只是**数值巧合**,不构成它们的基址。

### 3.7 完整性统计

| 口径 | 条数 |
|---|---|
| 池内名字总数 | 578 |
| 至少一处名字立即数引用 | 577(共 2348 处;唯一未被引用的 1 条是 `0x08d3867e  "name" : "Final"`) |
| 名字 ±0xC0 内存在 RegHal 形即时数 | **214** |
| ├ 最佳 ID 命中 GB202 表 | **121** |
| │ ├ 表 A(domain 5,高置信) | 23 |
| │ ├ 表 B(domain 5,中/低置信) | 17 |
| │ └ 表 C(非 domain 5;domain 0 = 绝对 PRI 号,其余域未闭合) | 81 |
| └ 邻近 ID 均不在 GB202 表(表 D,负结果) | 93 |

## 4. 交付主体 B:domain 0 基址闭合尝试

### 4.1 FACT:四个目标寄存器的表行(570.215,chip 0xff2)

| 池内名字 | RegHal ID | read 行 | (domain, offset, count) | 代码引用点(file) | Δ |
|---|---|---|---|---|---|
| `PAC_DISABLE` | `0x10338000` | 2 行(idx 均 `(0,0,0,0)`,words `(0,0,0,0x10)` / `(0,0,1,0x10)`) | **(0, 0x10, 1)** | `0xc98aa9`(名字 imm;ID 在 `0xc98a99`) | −16 |
| `fbp_pac` | `0x10338000` | 同上 | (0, 0x10, 1) | `0xc98abd` | −36 |
| `TPC_GPCx_DISABLE` | `0x10348000` | 2 行,words `(0,0,0,0x20)` / `(0,0,1,0x20)` | **(0, 0x20, 1)** | `0xcb2235`(ID `0xcb2220`) | −21 |
| `GPC_GFX_DISABLE` | `0x10348000` | 同上 | (0, 0x20, 1) | `0xc98c77`(ID `0xc98c67`) | −16 |
| `gpc_gfx`(read 侧) | `0x10348000` | 同上 | (0, 0x20, 1) | `0xc98c8b` / `0x114ec71` / `0x1157c69` | −36 |
| `SYSPIPE_GFX_DISABLE` | `0x10498000` | 2 行,words `(0,0,0,0x10)` / `(0,0,1,0x10)` | **(0, 0x10, 1)** | `0xc98db0`(ID `0xc98da0`) | −16 |
| `syspipe_gfx` | `0x10498000` | 同上 | (0, 0x10, 1) | `0xc98dc7` | −39 |
| `SYS_PIPE_DISABLE` / `syspipe` | `0x10498000` | 同上 | (0, 0x10, 1) | `0xc99ec8` / `0xc99ed7` | −22 / −37 |

附加事实:
- 这 4 个 ID 的 read 行**没有** `idx=0xfffe` 的 access-PLM 元数据行(与 domain-5 的 OPT_* 行不同);它们**只有** `words[2]=0/1` 两个变体。
- 这 4 个 ID(以及同族的 `0x1033c000`/`0x1034c000`/`0x1049c000`/`0x104d8000`/`0x104dc000`)的 read 行内容**在全部 29 张内嵌芯片表(0x800…0xff5)中逐字相同**(逐 ID 比对,见 §4.4)。
- **写侧描述符**:同一批单位的 enable/disable 写路径使用 **opcode 2(field-setter)** 的 `0x20xxxxxx` ID,且其 **domain = 5**(fuse)——
  `gpc_gfx` `0x20eb0000`→bits[11:0]、`gpc_tpc` `0x20bdc000`→bits[7:0]、`gpc_pes` `0x203a8000`→bits[15:0]、`gpc_cpc` `0x206fc000`→bits[11:0]、
  `gpc_rop` `0x209f4000`→bits[23:0]、`fbp_ltc` `0x208ac000`→[15:0]、`fbp_l2slice` `0x20894000`→[7:0]、`fbp_pac` `0x20ec8000`→[1:0]、
  `GPC_DISABLE` `0x207fc000`→[11:0]、`FBP_DISABLE` `0x20774000`→[7:0]、`FBIO_DISABLE` `0x20754000`→[7:0]、`SYS_PIPE_DISABLE` 单位等同样。
  即:**读走 domain 0,写走 domain 5**,二者不是同一 domain。
- 邻近的池内打印名 `Cannot read PAC mask`(`0x8d38518`)/`Cannot read TPC mask`(`0x8d385de`)/`Cannot read GPC mask`(`0x8d384ed`)/`Cannot read SYSPIPE_GFX mask`(`0x8d384b9`)说明这些读是"读当前掩码"的入口;失败日志为 `Invalid register 0x%x%s specified for this GPU`(file `0x8d0b0f8`)。

### 4.2 NEGATIVE:用"开源 hwref 同名寄存器全地址反推"的路线不成立

命令与结果(**0 命中**):

```bash
# 1) 精确同名搜索:开源 hwref + 已发布 swref + NVIDIA 610 全源码树
rg -n --no-heading "TPC_GPCx_DISABLE|GPC_GFX_DISABLE|SYSPIPE_GFX_DISABLE|PAC_DISABLE" \
   /usr/src/nvidia-610.57.04 \
   /home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules
#  -> 无输出(0 命中;本地只有 MODS 派生物 par/GB202_FSLIB_* 与名字池含这些字符串)

# 2) 宽口径:任何 GPC/TPC/PES/PAC/SYSPIPE/FBP + DISABLE 的寄存器宏
rg -n -i "NV_[A-Z0-9_]*(GPC|TPC|PES|PAC|SYSPIPE|FBP)[A-Z0-9_]*DISABLE" /usr/src/nvidia-610.57.04/src
#  -> 只有无关项:NV_EP_PCFG_GPU_*_IO_SPACE_DISABLE、NV_PFB_PRI_MMU_GPCCS_*_DISABLE、
#     NV_REG_STR_RM_D3_FEATURE_..._DISABLED 等;无 floorsweep/GPC-TPC-PAC 寄存器

# 3) hwref 目录清单(仅 11 个文件,无 fuse/floorsweep 头)
find /home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/kernel-open/nvidia-uvm/hwref -type f
#  -> ampere/ga100/{dev_fault,dev_runlist}.h、blackwell/gb100/dev_fault.h、hopper/gh100/*、
#     rubin/gr100/*、turing/tu102/* 共 11 个,均为 fault/mmu/fb/runlist,无 fuse/GPC 寄存器

# 4) GB202 已发布 swref 全清单(18 个文件,无 fuse/GPC/floorsweep 头)
ls /usr/src/nvidia-610.57.04/src/common/inc/swref/published/blackwell/gb202/
#  -> dev_boot_zb.h dev_ce_base.h dev_fault.h dev_fsp_addendum.h dev_fsp_pri.h dev_mmu.h
#     dev_nv_xal_ep_zb.h dev_ram.h dev_riscv_pri.h dev_runlist.h dev_therm*.h dev_top_zb.h
#     dev_vm.h dev_xtl_ep_pcfg_gpu.h dev_xtl_ep_pri.h hwproject.h kind_macros.h

# 5) 0x82 区寄存器定义(已发布头里的全部 0x00820xxx)
rg -n "0x0082000[0-9a-f]|0x0082001[0-9a-f]|0x0082002[0-9a-f]" \
   /usr/src/nvidia-610.57.04/src/common/inc/swref/published
#  -> 仅 NV_FUSE_OPT_NVDEC_DISABLE 0x00820378(ampere/ga100/dev_fuse.h);
#     没有任何 0x00820010 / 0x00820020 这类寄存器定义
```

**结论(NEGATIVE)**:四个名字在开源驱动/已发布材料中**没有同名寄存器**,因此不存在"同名寄存器全地址 − offset = 基址"这一算式所需的被减数。任务给出的这条路线在本机材料下**无法闭合**。

### 4.3 FACT:这条路线仍然给出了可用的"同值"交叉验证(并用于本轮闭合)

虽无同名寄存器,但**同一 Intel 式数值**可以在已发布头文件里找到独立同值条目:

| 证据 | 已发布材料 | MODS 侧 | 关系 |
|---|---|---|---|
| **domain 0 = 绝对 PRI 号(base 0)** | `blackwell/gb202/dev_fsp_pri.h`(上述两个副本均存在,内容相同):`NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(i) = (0x008f0320+(i)*4)`,`__SIZE_1 = 4` | ID `0x12004000`(池内 `FSP Debug Regs:`/`reg:0x%x value:0x%x`/`, BOOTFSM`/`(POS=0x%x)` 簇)= **(domain 0, offset 0x8f0320, count 4)** | **同值 + 同数组形状 + 同项数**:domain 0 的 offset 就是绝对寄存器号,无需再加基址 |
| domain 0 家族是绝对 PRI 号 | `blackwell/gb20b/dev_sec_pri.h`:`NV_PSEC_FALCON_COMMON_SCRATCH_GROUP_2(i) = 0x00840320+4i`,`__PRIV_LEVEL_MASK = 0x008403f8` | domain-0 家族 offset: `0x840400`/`0x840408`/`0x840530`(ID `0x12ab4000`/`0x12abc000`/`0x12ab8000`)、`0x828000`(ID `0x12d80000`)、`0x11d000`/`0x11d21c`、`0x120048`/`0x12004c`、`0x122274`、`0xad0xxx`、`0xb81xxx`、`0xbb0094` | 同一 PRI 编号区(0x84xxxx=SEC、0x826xxx-0x827fff=XAL EP P2P `NV_XAL_EP_P2P 0x00827fff:0x00826000`),与"offset 即绝对号"一致 |
| domain 5 = fuse 基址 + ZB offset | `blackwell/gb100/hwproject.h`:`NV_FUSE0_PRI_BASE 0x820000`;`dev_fuse_zb.h`:`NV_FUSE_ZB_STATUS_OPT_DISPLAY 0x00000C04`、`NV_FUSE_ZB_FEATURE_READOUT 0x00003814`;`src/nvidia/src/kernel/gpu/arch/blackwell/kern_gpu_gb100.c:1704` `GPU_REG_RD32(pGpu, gpuGetPrimaryFuseBaseAddr_HAL(pGpu) + NV_FUSE_ZB_STATUS_OPT_DISPLAY)` | `OPT_DISPLAY_DIS` → ID `0x10d34000` = (5, `0xc04`);ID `0x10570000`/`0x10574000` = (5, `0x3814`) | 同值 ↔ 反证 domain 5 的换算 `0x820000+offset` 正确;也说明 **domain 5 与 domain 0 是两套编码** |
| access-PLM = 绝对 PRI 号 | gb20b `NV_PSEC_...__PRIV_LEVEL_MASK 0x008403f8`、gb100 `NV_XAL_EP_P2P_WMBOX_ADDR__PRIV_LEVEL_MASK 0x00826900` | MODS 元数据行(idx `0xfffe`)给出 `0x00820010`/`0x00820020`/`0x008200dc`/`0x008200fc`(fuse 区) | 机制一致(PLM 用绝对号);**数值巧合**:PES 族 PLM=0x00820010、TPC 族 PLM=0x00820020,与四个目标名的 offset 0x10/0x20 同值 |

> 说明:第 4 行的"数值巧合"仅说明"0x10/0x20 确实作为 fuse 区的 PLM 号出现",**不**能把四个目标名的 domain-0 行解释成 fuse 地址 —— 因为 domain 0 已被第 1、2 行证明是"绝对号、无基址"的另一套编码。

### 4.4 FACT:四个 ID 的行内容在 29 张内嵌芯片表中逐字相同

本工件内嵌 29 张 RegHal 表(逐条 zlib 解码验证):

```text
0x800 0x802 0x807 0x808 0x900 0xa02 0xa04 0xa06 0xa07 0xa08 0xc00
0xc02 0xc03 0xc04 0xc06 0xc07 0xd02 0xd03 0xd04 0xd06 0xd07 0xe00
0xf00 0xf02 0xf0b 0xff2 0xff3 0xff4 0xff5
```

对 `0x10338000`/`0x10348000`/`0x10498000` 逐表比对:

| ID | 在 29 张表中的行(全部相同) |
|---|---|
| `0x10338000` | `(domain 0, w2=0, offset 0x10)` 与 `(domain 0, w2=1, offset 0x10)` |
| `0x10348000` | `(domain 0, w2=0, offset 0x20)` 与 `(domain 0, w2=1, offset 0x20)` |
| `0x10498000` | `(domain 0, w2=0, offset 0x10)` 与 `(domain 0, w2=1, offset 0x10)` |

⇒ 若这四个 offset 是"某个 per-chip BAR0 aperture 的偏移",那么它必须在**从 Maxwell 到 Blackwell 的 5 代芯片**上取同一个数值——与已发布的各代 aperture 差异(fuse:`0x21C04`(GM107)/`0x2174C`(TU102)/`0x820000`(GA100+/GB202);PBUS `0x1000`;TIMER `0x9000`;LTC `0x140000`)不一致。**这是排除 C2/C3 类候选的关键依据**(结合 §4.3 的 domain-0=绝对号结论)。

### 4.5 FACT/INFERENCE:domain → 基址 的分发模型(570.151 实证 + 570.215 对应物)

**570.151(`/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods`,既有审计 `fuse_domain_instance.md` 的同一工件)实证**:

```text
0x125b720  (GpuSubdevice vtable+0x218 = "domain,instance -> 基址")
   cmp edx,0x127 ; jg 其它分支
   cmp edx,4     ; jle 0x125b828        <- domain 0..4 走默认分支
   lea eax,[rdx-5] ; cmp eax,0x122 ; ja 默认
   jmp qword ptr [rax*8 + 0x92b3d38]   <- 跳转表按 (domain-5) 索引
0x125b828 (默认:domain<=4)
   ... jmp 0xdb4080
0xdb4080
   sub edx,0x1c ; xor eax,eax ; cmp edx,0xd ; ja ret
   mov eax,[rdx*4 + 0x925f2c0]         <- 只有 0x1c..0x29 有值(0x88000/0x104000/0xcc00)
   ret                                  <- domain<0x1c => 返回 0
0xdb5540 (raw wrapper)
   r12d = map_lookup_0xd99930(r8d)
   若 vtable+0x218 == 0xdb4080:对 0x1c..0x29 直接 r12d += table[domain-0x1c]
   否则: call 0x218(instance,domain,ctx) ; r12d += eax
   [vtable+0x230](r12d)                  <- 真正读写
```

⇒ **INFERENCE(570.151 模型)**:`地址 = 寄存器号 + 基址(domain,instance)`;**domain 0 的基址 = 0**(因为 `0 < 0x1c`);
且 570.151 的 domain 5 由跳转表第 0 项选到 `0x125c1f6`:`mov ecx,esi; mov edx,0x10ef4000; mov esi,0x10` → 走 class 0x10(fuse)+ 选择器 `0x10ef4000` 的固定表回退。

**570.215 对应物**:

- FACT:本工件的 GB202 表里,**基址选择器行**是 ID **`0x10f24000`**:`idx=(0,0,0,0) → words=(0,0,0,0x820000)`、`idx=(1,0,0,0) → words=(0,0,0,0xbf0000)`(570.151 的同类 ID 是 `0x10ef4000`;**这是一次跨构建 ID 漂移**,与既有审计一致)。
- FACT:570.215 里存在同一形态的 case 体(`mov ecx,esi; mov edx,<selector>; mov esi,<class>; jmp <resolver>`),其中 class `0x10` + selector `0x10f24000` 的 fuse 例在 file `0xea252b`(VA `0x12a252b`)。
- UNKNOWN:570.215 的**跳转表本体(按 domain-5 索引的那张)** 与 domain 0..4 的默认分支**未逐字节复现**(该表在 570.215 中未定位到;570.151 的表在 VA `0x92b3d38`)。因此 570.215 的 domain 0 → 0 的推断是 **INFERENCE(由 570.151 实证 + 570.215 表行/选择器一致外推)**,不是 570.215 的逐指令实证。

### 4.6 候选基址与排除依据(任务要求的"若无法闭合则列候选+排除")

| # | 候选基址 B | 来源(可核) | 若成立 → 四者地址 | 支持 | **排除/保留依据** | 判定 |
|---|---|---|---|---|---|---|
| C1 | **`0x000000`** | 已发布 `blackwell/{gb202,gb100,gb20b}/hwproject.h`:`NV_PMC0_PRI_BASE 0x0`;570.151 的 `0xdb4080` 对 domain<0x1c 返回 0;§4.3 第 1/2 行的"domain 0 = 绝对 PRI 号"同值交叉验证 | PRI `0x10` / `0x20` | 唯一被同值证据与模型同时支持的基址;domain-0 家族的其它成员(0x11d000、0x120048、0x8f0320、0x8404xx、0x828000、0xad0xxx…)都落在此模型可解释的 PRI 编号区 | **保留为"基址"结论(基址=0,即无需加基址)**;但 PRI `0x10`/`0x20` 这两个具体号在本工件/已发布材料里**找不到**与这四个名字相符的寄存器定义 ⇒ 具体语义仍是 UNKNOWN(见 §4.7) | **基址闭合(0)**;号本身存疑 |
| C2 | `0x820000`(fuse) | `gb100/hwproject.h: NV_FUSE0_PRI_BASE`(GH100 头 = 十进制 8519680) | `0x00820010` / `0x00820020` | 名字语义像 fuse 掩码;四者的**写侧 field-setter 是 domain 5**;`0x00820010`/`0x00820020` 在本表里确实是 **PES/TPC 掩码族的 access-PLM**(真实存在) | ① 四者的 **read 行 domain = 0**,而 domain 0 已被证明是"绝对号、无基址"的另一套编码(§4.3);② 已发布 fuse 头(裁剪过的发布集)里没有任何 `0x10`/`0x20` 偏移的 fuse 寄存器——这些头出现的最小 ZB 偏移是 `0x74C`(`NV_FUSE_ZB_OPT_SECURE_GSP_DEBUG_DIS`),另有 `0xC04`/`0x3814`/`0x4140`/`0x41C0`/`0x4E04`;③ 若按此基址,则同一行在 Maxwell/Turing 上也应指 fuse+0x10/0x20,但那两代的 fuse 基址分别是 `0x21C04`/`0x2174C`(已发布),行内却不含任何芯片相关基数;④ offset `0x10`/`0x20` 在本表里已被 PES/TPC 族的 PLM 占用,复用会导致同址冲突 | **排除** |
| C3 | `0x001000`(PBUS0)、`0x009000`(PTIMER0)、`0x140000`(LTC)、`0x400000`(PGRAPH)、`0x880000`(HUBMMU)、`0x08A000`(gb202 XTL) | 已发布 `gb100/hwproject.h`、`gb202/hwproject.h` | 各自的 `+0x10`/`+0x20` | 这些是真实 aperture 基址 | ① 同一行在 29 张芯片表逐字相同(§4.4),而这些 aperture 的数值跨代不同;② 已发布材料里这些 aperture 内**没有** GPC/TPC/PAC/SYSPIPE disable 类寄存器(§4.2 命令);③ 四个目标名的代码窗口内**没有任何** `mov r32, imm32` 等于上述候选基址 `+0x10`/`+0x20`(扫描窗口 ±0xC0 内只有 `0x10338000`/`0x10348000`/`0x10498000` 与 `0x20xxxxxx` field 描述符) | **排除** |
| C4 | `0x00000000` 之外的"0 号 PRI 别名" | — | 同 C1 | — | 无独立证据,归入 C1 | 舍弃 |
| C5 | "domain 0 无基址语义(offset 只是软件索引/占位)" | 29 张表逐字相同 + 四个 ID 无 PLM 元数据行 + 名字为"stub 式" | 不能给出地址 | 可解释"为何 0x10/0x20 找不到同名/同值寄存器" | 不能证伪,也不能给出地址 | **保留为 UNKNOWN 备选解释** |

### 4.7 结论与残余 UNKNOWN

1. **闭合结果(本轮结论)**:domain 0 的基址 = **`0x000000`**,即 domain-0 行的 `offset` **本身就是绝对 PRI 寄存器号**,不需要再加任何基址。
   最强证据是**同一颗芯片家族(GB202)的已发布头文件同值**:`NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(i) = 0x008f0320 + 4*i`(`__SIZE_1 = 4`)↔ MODS ID `0x12004000` 的 `(domain 0, offset 0x8f0320, count 4)`;次强证据是 domain-0 家族其它成员落在已发布 PRI 编号区(0x84xxxx = SEC、0x826xxx-0x827fff = XAL EP P2P、0x11d000 = PCIe 区)以及已发布 `NV_PMC0_PRI_BASE 0x0`。
2. **由该闭合直接排除** C2(`0x820000`)与 C3(`0x1000`/`0x9000`/`0x140000`/`0x400000`/`0x880000`/`0x8A000`),排除依据见 §4.6。
3. **因此,按表行字面值**,四个目标寄存器位于 **PRI `0x10`**(`PAC_DISABLE`、`SYSPIPE_GFX_DISABLE`)与 **PRI `0x20`**(`TPC_GPCx_DISABLE`、`GPC_GFX_DISABLE`)。
4. **UNKNOWN(必须明写的负结果)**:在本工件与全部本地已发布材料中,**找不到** PRI `0x10`/`0x20` 上与该四个名字相符的寄存器定义;PRI `0x10`/`0x20` 落在 PMC/TOP 低号区,与"GPC/TPC/PAC/SYSPIPE disable 掩码"语义不符。可能的解释(按证据强度排序):
   - **H-stub(较强)**:这四个 ID 是**跨 29 颗芯片逐字复用的通用/占位行**(无 PLM 元数据行,offset 极小且与 PES/TPC 族的 PLM 号同值),在 GB202 上这类读很可能落到 `Invalid register` 分支,对应的打印名正是 `Cannot read PAC/TPC/GPC/SYSPIPE_GFX mask`。
   - **H-write-only**:真正的掩码寄存器由**写侧(domain 5 的 field 描述符,如 `0x20eb0000` bits[11:0])** 定义,domain-0 的 read 行只是"读当前值"的软/占位路径,不能用作地址来源。
   - **H-alias(较弱)**:`words[2]=0/1` 两行分别对应 GPC 两半/两个实例,offset 0x10/0x20 是"fuse 区 PLM 别名"的编号;但 domain 0 ≠ 5,且无 PLM 元数据行,证据不足。
5. **要真正闭合(超出本轮只读静态范围,未做)**:① 在 570.215 中逐字节定位 domain 跳转表本体与 domain 0..4 的默认 case(确认基址 0,或找到 domain 0 的专门 case);② 运行时读数一次 `0x10338000`/`0x10348000`/`0x10498000`,记录最终寄存器号(需设备侧操作,本轮禁止);③ 取得 GB202 PTOP `DEVICE_INFO2` 全表的 `devicePriBase`(运行时/固件侧数据)。

## 5. 复现步骤(全部只读、无设备访问)

```bash
# 0) 环境:python3 + capstone;工件 MODS 570.215
cd /home/user/rt_5090_project

# 1) 复核既有解码器可用(GB202 = chip 0xff2)
python3 gb202_reghal_offline.py \
  /home/user/mod570_215_static/extracted/home/570.215/mods \
  --id 0x10348000 --id 0x10338000 --id 0x10498000 --id 0x10f24000 --include-metadata
#    -> 0x10348000: (0,0,0,0x20)/(0,0,1,0x20);0x10338000/0x10498000: 0x10;
#       0x10f24000: (0,0,0,0x820000)/(1,0,0,0xbf0000)  <- domain-5 基址选择器

# 2) 名字池 → ID 邻接全量扫描(本报告表 A/B/C/D 与附录 A 的来源)
python3 parallel/gb202_reghal_namepool_scan_20260925.py \
  --mods /home/user/mod570_215_static/extracted/home/570.215/mods \
  --pool /home/user/rt_5090_project/parallel/gb202_fslib_strings_20260925.txt \
  --outdir /home/user/rt_5090_project/parallel
#    -> 输出 .../gb202_reghal_namepool_scan_20260925.results.json
#       (578 池条 / 2348 引用点 / 214 条有 RegHal 形即时数 / 121 条命中表内 ID)

# 3) 29 张内嵌芯片表枚举(用于 §4.4 的不变性检查)
python3 - <<'EOF'
import numpy, zlib
d=open("/home/user/mod570_215_static/extracted/home/570.215/mods","rb").read(); N=len(d)
for s in range(4):
    K=(N-s)//4; a=numpy.frombuffer(d[s:s+4*K],dtype="<u4")
    A,B,C,D=a[:-3],a[1:-2],a[2:-1],a[3:]
    for k in numpy.nonzero((D>=1000)&(D<=200000)&(C==D*28)&(B>1000)&(B<2**26)&(A>=0x100)&(A<=0x2000))[0]:
        off=s+4*int(k)
        try: raw=zlib.decompress(d[off+16:off+16+int(B[k])])
        except Exception: continue
        if len(raw)==int(C[k]): print(hex(off),hex(int(A[k])),int(D[k]))
EOF
#    -> 29 张表:0x800 0x802 0x807 0x808 0x900 0xa02..0xa08 0xc00..0xc07
#       0xd02..0xd07 0xe00 0xf00 0xf02 0xf0b 0xff2 0xff3 0xff4 0xff5

# 4) 开源/已发布材料的同名搜索(§4.2 的负结果)
rg -n "TPC_GPCx_DISABLE|GPC_GFX_DISABLE|SYSPIPE_GFX_DISABLE|PAC_DISABLE" \
   /usr/src/nvidia-610.57.04 \
   /home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules      # 0 命中

# 5) domain 0 = 绝对 PRI 号 的同值交叉验证(§4.3)
grep -n "FALCON_COMMON_SCRATCH_GROUP_2" \
   /usr/src/nvidia-610.57.04/src/common/inc/swref/published/blackwell/gb202/dev_fsp_pri.h
#    -> NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(i) (0x008f0320+(i)*4)  __SIZE_1 4
python3 gb202_reghal_offline.py /home/user/mod570_215_static/extracted/home/570.215/mods --id 0x12004000
#    -> (domain 0, offset 0x8f0320)  x4 项数组

# 6) domain 5 换算的公开侧交叉验证(§4.3)
grep -n "STATUS_OPT_DISPLAY\|FEATURE_READOUT" \
   /usr/src/nvidia-610.57.04/src/common/inc/swref/published/blackwell/gb100/dev_fuse_zb.h
#    -> NV_FUSE_ZB_STATUS_OPT_DISPLAY 0x00000C04 / NV_FUSE_ZB_FEATURE_READOUT 0x00003814
sed -n '1700,1706p' /usr/src/nvidia-610.57.04/src/nvidia/src/kernel/gpu/arch/blackwell/kern_gpu_gb100.c
#    -> GPU_REG_RD32(pGpu, gpuGetPrimaryFuseBaseAddr_HAL(pGpu) + NV_FUSE_ZB_STATUS_OPT_DISPLAY)
```

**新增/更新的工件**

| 路径 | 内容 |
|---|---|
| `parallel/gb202_reghal_namepool_scan_20260925.py` | 扫描器(只读;公开方法、窗口、阈值) |
| `parallel/gb202_reghal_namepool_scan_20260925.results.json` | 全量原始结果(每名字的每个引用点与每个邻近 RegHal 形即时数 + 表行汇总) |
| `parallel/gb202_reghal_namepool_scan_20260925.detail.txt` | 可读明细(121 条命中表内 ID 的名字,逐条列出候选 ID/Δ/表行) |
| `parallel/GB202_REGHAL_FULLMAP_20260925.md` | 本报告 |

## 6. 不确定度与边界

1. **所有 `0x82xxxx` 都是"固定选择器(instance-0 fallback)"结果**(`0x00820000`),不是运行时实测 BAR0;运行期若走 PTOP `DEVICE_INFO2` class `0x10` instance-0 的 `devicePriBase` 分支,数值可能改变(既有审计 `fuse_domain_instance.md`/`deviceinfo_class10_identity.md`)。
2. **名字↔ID 是邻接启发式**:`Δ` 只表示距离。表 A 因 |Δ| ≤ 0x40 且与既有审计逐条一致而标"高置信";表 B/C/D 必须按名字语义判读(表 B 已标出已知误配)。
3. **扫描只覆盖名字作为 32/64 位立即数(含非对齐)的引用**;RIP-relative `lea` 引用未纳入(既有审计同样口径)。因此"没有邻近 ID"不等于"该名字与寄存器无关"。
4. **ID 跨构建会漂移**(既有双构建实证 + 本轮新增:`0x10ef4000`(570.151 的域 5 选择器)→ `0x10f24000`(570.215))。任何"aperture/ID 目录"必须与构建绑定。
5. **domain 0 的具体语义仍有残余 UNKNOWN**(§4.7):基址已闭合为 0,但 PRI `0x10`/`0x20` 找不到与四名字相符的定义;三个假设(H-stub / H-write-only / H-alias)已列,静默地把它们写成 `0x00820010`/`0x00820020` 是**错误**的。
6. **domain 29/30/31/32/33/35/54/60 仍未闭合**(表 C 中 `RunMarginCommand` → dom 33、`Cannot read FBP/FBIO mask` → dom 60 等);它们的基址同样需要 domain→class→selector 的分发表逐字节复现或运行时数据。
7. 本轮**未**定位 570.215 的 domain 跳转表本体(570.151 的表在 VA `0x92b3d38`,570.215 未逐字节复现),故 §4.5 的"domain 0..4 → 默认分支 → 返回 0"对 570.215 是 INFERENCE。

## 7. 合规声明

本轮全程只读取本地文件(ELF、开源头文件、既有审计文本),未执行 MODS,未打开 `/dev/mem`、`/dev/nvidia*`、sysfs resource、`/proc/driver/nvidia` 或任何设备节点,
未做任何 MMIO 读/写、未加载/卸载模块、未写卡、未刷写、未联网、未尝试绕过任何许可/签名/出口管制机制。
报告内容为**静态地址定位结论**,不构成刷写、解锁或规避方案;所有涉及运行期数值的结论都明确标注为"未实测"。

---

## 附录 A:全量机器表(214 条池内名字的邻近 RegHal 形即时数)

说明:`*` 前缀 = 该 ID 在本工件 GB202(0xff2)表内;**无 `*`** = 不在表中(负结果)。
`(Δ)` = 立即数指令 − 名字立即数(file 偏移差)。

| 池偏移 | 名字 | 名字引用点(file) | 邻近 ID(在表中者加 * ) |
|---|---|---|---|
| 0x8d3800a | `ConfigGet` | 0x3c8fe7, 0x154db2a9, 0x154ea753, 0x154f9941 | 0x18771800(+6) 0x187715e0(+11) 0x178745a0(+21) 0x187715e0(+26) 0x18771620(-38) 0x178745a0(-43) 0x18771620(-53) 0x18771800(-58) 0x18771800(+64) 0x187715a0(+75) 0x178745a0(+85) 0x187715a0(+90) 0x18771680(-102) 0x178745a0(-107) 0x18771680(-117) 0x18771800(-122) 0x18771800(+128) 0x18771560(+139) 0x178745a0(+149) 0x18771560(+154) 0x187716e0(-166) 0x178745a0(-171) 0x187716e0(-181) 0x18771800(-186) |
| 0x8d38014 | `ConfigSet` | 0x3c9023 | 0x18771800(+4) 0x187715a0(+15) 0x178745a0(+25) 0x187715a0(+30) 0x187715e0(-34) 0x178745a0(-39) 0x187715e0(-49) 0x18771800(-54) 0x18771800(+68) 0x18771560(+79) 0x178745a0(+89) 0x18771560(+94) 0x18771620(-98) 0x178745a0(-103) 0x18771620(-113) 0x18771800(-118) 0x18771800(+134) 0x18771520(+139) 0x178745a0(+153) 0x18771520(+158) 0x18771680(-162) 0x178745a0(-167) 0x18771680(-177) 0x18771800(-182) |
| 0x8d3801e | `RunStressTest` | 0x3c9063 | 0x18771800(+4) 0x18771560(+15) 0x178745a0(+25) 0x18771560(+30) 0x187715a0(-34) 0x178745a0(-39) 0x187715a0(-49) 0x18771800(-60) 0x18771800(+70) 0x18771520(+75) 0x178745a0(+89) 0x18771520(+94) 0x187715e0(-98) 0x178745a0(-103) 0x187715e0(-113) 0x18771800(-118) 0x18771800(+134) 0x187714e0(+139) 0x178745a0(+153) 0x187714e0(+158) 0x18771620(-162) 0x178745a0(-167) 0x18771620(-177) 0x18771800(+178) 0x18771800(-182) 0x187713e0(+183) |
| 0x8d3802c | `Access an I2C device.` | 0x3c9095, 0xdf84980, 0xdf8f280 | 0x18771560(-20) 0x18771800(+20) 0x178745a0(-25) 0x18771520(+25) 0x18771560(-35) 0x178745a0(+39) 0x18771520(+44) 0x18771800(-46) 0x187715a0(-84) 0x18771800(+84) 0x178745a0(-89) 0x187714e0(+89) 0x187715a0(-99) 0x178745a0(+103) 0x187714e0(+108) 0x18771800(-110) 0x18771800(+128) 0x187713e0(+133) 0x187715e0(-148) 0x178745a0(-153) 0x187715e0(-163) 0x178745a0(+167) 0x18771800(-168) 0x187713e0(+172) |
| 0x8d38042 | `I2CAccess` | 0x3c90a5 | 0x18771800(+4) 0x18771520(+9) 0x178745a0(+23) 0x18771520(+28) 0x18771560(-36) 0x178745a0(-41) 0x18771560(-51) 0x18771800(-62) 0x18771800(+68) 0x187714e0(+73) 0x178745a0(+87) 0x187714e0(+92) 0x187715a0(-100) 0x178745a0(-105) 0x18771800(+112) 0x187715a0(-115) 0x187713e0(+117) 0x18771800(-126) 0x178745a0(+151) 0x187713e0(+156) 0x187715e0(-164) 0x178745a0(-169) 0x187715e0(-179) 0x18771800(-184) |
| 0x8d3804c | `GetBuildVersion` | 0x3c90e5 | 0x18771800(+4) 0x187714e0(+9) 0x178745a0(+23) 0x187714e0(+28) 0x18771520(-36) 0x178745a0(-41) 0x18771800(+48) 0x187713e0(+53) 0x18771520(-55) 0x18771800(-60) 0x178745a0(+87) 0x187713e0(+92) 0x18771560(-100) 0x178745a0(-105) 0x18771560(-115) 0x18771800(-126) 0x187715a0(-164) 0x178745a0(-169) 0x187715a0(-179) 0x18771800(-190) |
| 0x8d3805c | `GetDeviceHandle` | 0x3c9111 | 0x18771800(+4) 0x187713e0(+9) 0x187714e0(-16) 0x178745a0(-21) 0x187714e0(-35) 0x18771800(-40) 0x178745a0(+43) 0x187713e0(+48) 0x18771520(-80) 0x178745a0(-85) 0x18771520(-99) 0x18771800(-104) 0x18771560(-144) 0x178745a0(-149) 0x18771560(-159) 0x18771800(-170) |
| 0x8d38081 | `unordered_map::at` | 0xc873d3, 0xc92c24, 0xc947e8, 0xc94ffb | *0x12e04000(-138) *0x115a0000(+187) 0x18a7c700(-11) 0x18a7c700(-47) 0x18a7c700(-83) 0x18a7c700(-119) 0x1881f770(-143) 0x1881f770(+155) 0x1881f770(+180) 0x1881f770(-181) |
| 0x8d38128 | `gpc_cpc_enable` | 0xca2526, 0xca2679, 0x8ece390, 0x8ecfac0 | 0x178a0440(-70) |
| 0x8d38147 | `gpc_rop_enable` | 0xcabe56, 0xcabfb1, 0x8ece3e0, 0x8ed0e80 | 0x178a0600(-118) |
| 0x8d38166 | `gpc_pes_enable` | 0xcb7171, 0xcb7183, 0x8ece430, 0x8ed2a40 | *0x409ac200(-46) *0x109ac000(-90) *0x103a8000(+144) 0x1881f770(-51) 0x1881f770(-95) |
| 0x8d38175 | `gpc_pes_disable` | 0xcb7194, 0x1ad4ca8, 0x1b596af, 0x8ece458 | *0x409ac200(-81) *0x103a8000(+109) *0x109ac000(-125) 0x1881f770(-86) 0x1881f770(-130) |
| 0x8d381b5 | `fbp_ltc_enable` | 0xcbc6c4, 0xcbc78e, 0xcbcb9f, 0x8ece520 | 0x10a04000(-49) 0x1881f770(-60) 0x178a0a20(-132) |
| 0x8d381c4 | `fbp_ltc_disable` | 0xcbc784, 0xcbca81, 0x1b1b3de, 0x1b59b05 | *0x10368000(-31) *0x20368000(-175) |
| 0x8d38263 | `nvdec_enable` | 0xcbe22d, 0xcbe2ad, 0x8ece700, 0x8ed16b0 | 0x178a0ae0(-101) |
| 0x8d38270 | `nvdec_disable` | 0xcbe2be, 0xcbe381, 0x1ad494b, 0x1b1b5c6 | 0x1881f770(+186) 0x10dd4000(+191) |
| 0x8d3827e | `nvenc_enable` | 0xcbe209, 0xcbe27a, 0x8ece750, 0x8ed1700 | 0x178a0ae0(-65) |
| 0x8d3828b | `nvenc_disable` | 0xcbe28b, 0xcbe3a1, 0x1b6a6a7, 0x8ece778 | 0x1881f770(+154) 0x10dd4000(+159) |
| 0x8d38299 | `display_enable` | 0xcc48d2, 0xcc4a08, 0x8ece7a0, 0x8ed5020 | 0x178a0ca0(-65) |
| 0x8d382b8 | `half_fbpa_enable` | 0xcb6f36, 0xcb6f5c, 0x8ece7f0, 0x8ed2a90 | *0x1059c000(-157) 0x178a0940(-115) 0x1881f770(-162) |
| 0x8d382c9 | `half_fbpa_disable` | 0xcb6f6d, 0xcb73d3, 0x8ece818, 0x8ed2ab8 | 0x178a0940(-170) |
| 0x8d384b9 | `Cannot read SYSPIPE_GFX mask` | 0xc8b891 | *0x10d00000(-169) 0x1881f770(-174) |
| 0x8d384d7 | `Cannot read FBP mask` | 0xc8bb21, 0xcb59d1 | *0x12b68000(-50) *0x12b68000(-53) *0x10d4c000(-88) *0x10dac000(+119) *0x20dac100(+157) *0x10378000(-179) 0x1881f770(-55) 0x1881f770(-58) 0x1881f770(+114) 0x1881f770(-192) |
| 0x8d384ed | `Cannot read GPC mask` | 0xc8bbd9, 0xcbd8f1 | *0x10d64000(-60) *0x42cfc000(+78) *0x42cfc000(+101) *0x10310000(+162) *0x20dac000(-181) 0x1881f770(+73) 0x1881f770(+117) 0x1881f770(+149) 0x1881f770(-186) |
| 0x8d38503 | `PriRingPollTimeoutMs` | 0x3e7862, 0xc8c887, 0xcb0527, 0xdcc76c | 0x187a1880(+121) 0x1879aaa0(+126) 0x178745a0(+136) 0x1879aaa0(+141) 0x187a1880(+191) |
| 0x8d38544 | `Cannot read PES mask` | 0xc8d4a9, 0xcb56f1, 0xbdf2cbc, 0xbfdef1c | *0x10de4000(-58) *0x103a8000(+83) *0x12b58000(-139) 0x1881f770(-153) 0x1881f770(+176) 0x22341200(+181) |
| 0x8d38574 | `Cannot read NVLINK mask` | 0xc8d681 | *0x12dec000(+101) 0x1881f770(+96) |
| 0x8d3858d | `Cannot read FBIO mask` | 0xc8e051, 0xcb5b51 | *0x12b58000(-53) *0x10d3c000(-88) 0x1881f770(-58) |
| 0x8d385bf | `Cannot read L2 mask` | 0xc8e291, 0xcbaaf9 | *0x10d9c000(-18) *0x10d4c000(+79) *0x12b78000(-112) *0x12b68000(+117) *0x22341700(-191) 0x1881f770(+74) 0x10e04000(-88) 0x1881f770(+112) 0x1881f770(-117) |
| 0x8d385d4 | `SkipFspFs` | 0x3e789e, 0xc8e3cd, 0xc8e4a5, 0xc8ea88 | *0x129fc000(+100) 0x187a1880(+61) 0x1879aaa0(+66) 0x178745a0(+76) 0x1879aaa0(+81) 0x1881f770(+95) 0x1881f770(+102) 0x10dbc000(+107) 0x187a1880(+131) 0x1879aa40(+136) 0x178745a0(+146) 0x1879aa40(+151) 0x1881f770(+157) 0x1124c000(+162) |
| 0x8d385de | `Cannot read TPC mask` | 0xc8e759, 0xcbd421, 0xe506a06, 0xea9b926 | *0x42cfc000(+62) *0x42cfc000(+85) *0x10e2c000(-87) *0x10754000(+134) *0x10310000(+181) 0x1881f770(+57) 0x1881f770(+101) 0x1881f770(+129) 0x1881f770(+168) |
| 0x8d385f4 | `UseBootResetForFs` | 0x3e78b2, 0xc8ec11, 0xc8f431, 0xdcd76c | *0x429fc104(-58) *0x429fc000(-104) *0x429fc000(-127) *0x423bc101(+133) *0x429fc104(+175) *0x423bc001(-176) 0x423b4000(-22) 0x1881f770(-27) 0x187a1880(+41) 0x1879aaa0(+46) 0x1881f770(-53) 0x178745a0(+56) 0x1879aaa0(+61) 0x1881f770(-63) 0x423b4000(-75) 0x1881f770(-79) 0x423b4000(-98) 0x1881f770(-103) 0x187a1880(+111) 0x1879aa40(+116) 0x178745a0(+126) 0x1881f770(+128) 0x1879aa40(+131) 0x1881f770(-132) 0x123b4000(-136) 0x1881f770(-141) 0x1881f770(-169) 0x1881f770(+170) 0x1881f770(-181) 0x187a1880(+182) 0x1879a9e0(+187) |
| 0x8d38606 | `PollPriRingCmdNone` | 0xc8ebe3, 0xc8f3a9, 0xc9f5b0, 0xc9f99d | *0x429fc000(-51) *0x429fc002(-52) *0x429fc000(-58) *0x429fc002(-58) *0x429fc000(-68) *0x429fc002(-75) *0x429fc104(+78) *0x429fc000(-81) *0x429fc002(-81) *0x429fc104(+85) *0x429fc104(+91) *0x129fc000(-100) *0x429fc101(-110) *0x12338000(+119) *0x429fc101(-131) *0x12338000(+144) *0x129fc000(-150) *0x42338301(+162) *0x12338000(-170) *0x129fc000(-170) *0x42338101(+189) 0x1881f770(-27) 0x1881f770(-27) 0x1881f770(-33) 0x1881f770(-33) 0x1881f770(+73) 0x1881f770(-73) 0x1881f770(-80) 0x1881f770(+80) 0x1881f770(-86) 0x1881f770(-86) 0x1881f770(+86) 0x1881f770(-105) 0x1881f770(+114) 0x1881f770(-115) 0x1881f770(-136) 0x1881f770(+139) 0x1881f770(-155) 0x1881f770(+157) 0x1881f770(-175) 0x1881f770(-176) 0x1881f770(+184) |
| 0x8d38619 | `InitializePriRing` | 0xc8ebe8, 0xc8eca0, 0xc9f5b5, 0xc9f5ef | *0x429fc104(+32) *0x129b4000(-44) *0x429fc000(-56) *0x429fc000(-63) *0x129bc000(+72) *0x429fc000(-73) *0x429b4100(-78) *0x429fc000(-86) *0x429fc104(+86) *0x129fc000(-105) *0x12338000(+114) *0x129b4000(-123) *0x12338000(+139) *0x42338001(+149) *0x429f0001(+152) *0x42338301(+157) *0x429dc001(-164) *0x429f0001(+169) *0x429dc001(-181) *0x12338000(+183) *0x42338101(+184) 0x1881f770(+27) 0x1881f770(-32) 0x1881f770(-38) 0x1881f770(-50) 0x1881f770(+66) 0x1881f770(-78) 0x1881f770(+81) 0x1881f770(-83) 0x1881f770(+88) 0x1881f770(-91) 0x429b4003(+93) 0x429b4001(-105) 0x1881f770(+109) 0x1881f770(-110) 0x1881f770(-110) 0x429b4003(+110) 0x1881f770(+126) 0x1881f770(-128) 0x1881f770(+134) 0x1881f770(+144) 0x1881f770(+147) 0x1881f770(-149) 0x1881f770(+152) 0x1881f770(+177) 0x1881f770(+179) 0x1881f770(-186) 0x1881f770(+192) |
| 0x8d3862b | `PollPriRingStatus` | 0xc8ec9b, 0xc8f3d2, 0xc9f5ea, 0xc9f9cd | *0x429fc104(+33) *0x429fc104(+37) *0x429fc104(+37) *0x429fc104(+37) *0x12338000(+61) *0x12338000(+86) *0x429fc002(-99) *0x429fc002(-100) *0x42338301(+104) *0x429fc000(-109) *0x429fc002(-122) *0x429fc002(-123) *0x429fc000(-126) *0x42338101(+131) *0x42338001(+154) *0x129fc000(-158) *0x429fc101(-158) *0x12b30000(+166) *0x429fc101(-172) *0x12338000(+188) 0x1881f770(+28) 0x1881f770(+32) 0x1881f770(+32) 0x1881f770(+32) 0x1881f770(+56) 0x1881f770(-74) 0x1881f770(-75) 0x1881f770(+81) 0x1881f770(-85) 0x1881f770(+99) 0x1881f770(+126) 0x1881f770(-127) 0x1881f770(-128) 0x1881f770(-131) 0x1881f770(+149) 0x1881f770(+161) 0x1881f770(-163) 0x1881f770(-163) 0x1881f770(-177) 0x1881f770(+182) |
| 0x8d3863d | `Exit Code` | 0xc8ed73, 0xcc945d, 0x1b0ff0f, 0x1b49ddc | *0x429fc104(-179) 0x1881f770(-184) |
| 0x8d38694 | `InitializePriRing_FirstStage` | 0xc8f3ae, 0xc8f3d7, 0xc9f9a2, 0xc9f9d2 | *0x429fc002(-57) *0x429fc002(-63) *0x429fc104(+73) *0x429fc002(-80) *0x429fc104(+80) *0x429fc002(-86) *0x429fc101(-115) *0x429fc101(-136) *0x129fc000(-155) *0x12b30000(+161) *0x12338000(-175) *0x129fc000(-175) 0x1881f770(-32) 0x1881f770(-38) 0x1881f770(+68) 0x1881f770(+75) 0x1881f770(-85) 0x1881f770(-91) 0x1881f770(-120) 0x1881f770(-141) 0x1881f770(+156) 0x1881f770(-160) 0x1881f770(-180) 0x1881f770(-181) |
| 0x8d386b9 | `nvlink_perlink_enable` | 0xc906f5, 0x8ecfb10, 0x1749e940, 0x1749f280 | 0x18784958(+91) 0x18784960(+120) 0x178745a0(+130) 0x18784960(+135) 0x18784958(+150) 0x18784960(+176) |
| 0x8d386cf | `nvlink_perlink_disable` | 0xc9070a, 0x1b1ba86, 0x8ecfb38, 0x1749e948 | 0x18784958(+70) 0x18784960(+99) 0x178745a0(+109) 0x18784960(+114) 0x18784958(+129) 0x18784960(+155) |
| 0x8d386e6 | `7/7/2023` | 0xc90764 | 0x18784960(+9) 0x178745a0(+19) 0x18784958(-20) 0x18784960(+24) 0x18784958(+39) 0x18784960(+65) |
| 0x8d386ef | `deprecNvlinkPerlink` | 0xc9072a, 0xc90769 | 0x18784958(+38) 0x18784960(+67) 0x178745a0(+77) 0x18784960(+82) 0x18784958(+97) 0x18784960(+123) |
| 0x8d38722 | `%s0x%x'` | 0xc92056, 0xc925ce, 0xca1d4b, 0xca8269 | *0x10d2c000(-50) *0x10d94000(-50) *0x10dfc000(-50) *0x10d9c000(-56) *0x10de4000(-58) *0x10e2c000(+187) |
| 0x8d3875a | `DisableCeInterrupts` | 0x3e7876, 0xc95363, 0xc95433, 0xc95503 | 0x187a1880(+101) 0x1879aaa0(+106) 0x178745a0(+116) 0x1879aaa0(+121) 0x187a1880(+171) 0x1879aa40(+176) 0x178745a0(+186) 0x1879aa40(+191) |
| 0x8d3876e | `PAC_DISABLE` | 0xc98aa9 | *0x10338000(-16) *0x20ec8000(+40) *0x20e68000(+46) 0x1881f770(-21) |
| 0x8d3877a | `fbp_pac` | 0xc98abd | *0x20ec8000(+20) *0x20e68000(+26) *0x10338000(-36) 0x1881f770(-41) |
| 0x8d38782 | `C2CHBI_DISABLE` | 0xc98b88 | *0x20e9c000(+37) *0x20e4c000(+43) *0x20e68000(-177) *0x20ec8000(-183) |
| 0x8d38791 | `c2chbi_group` | 0xc98b99 | *0x20e9c000(+20) *0x20e4c000(+26) |
| 0x8d3879e | `GPC_GFX_DISABLE` | 0xc98c77 | *0x10348000(-16) *0x20eb0000(+40) *0x20e54000(+46) 0x1881f770(-21) |
| 0x8d387ae | `gpc_gfx` | 0xc98c8b, 0x114ec71, 0x1157c69 | *0x20eb0000(+20) *0x20e54000(+26) *0x10348000(-36) *0x10988000(-57) *0x10898000(+118) *0x10984000(-127) 0x1881f770(-41) |
| 0x8d387b6 | `SYSPIPE_GFX_DISABLE` | 0xc98db0 | *0x10498000(-16) *0x10498000(-87) 0x1881f770(-21) 0x20eec000(+43) 0x20e8c000(+49) 0x1881f770(-92) |
| 0x8d387ca | `syspipe_gfx` | 0xc98dc7, 0x114ec81, 0x1158639 | *0x10498000(-39) *0x10498000(-110) 0x20eec000(+20) 0x20e8c000(+26) 0x1881f770(-44) 0x1881f770(-115) |
| 0x8d387d6 | `PERLINK_DISABLE` | 0xc98ecc | 0x20964000(+37) 0x203a0000(+43) 0x103a0000(-50) 0x1881f770(-55) |
| 0x8d387e6 | `nvlc_perlink` | 0xc98edd | 0x20964000(+20) 0x203a0000(+26) 0x103a0000(-67) 0x1881f770(-72) |
| 0x8d387f3 | `TPC_DISABLE` | 0xc98f9a | *0x20bdc000(+37) *0x204a0000(+43) 0x203a0000(-163) 0x20964000(-169) |
| 0x8d387ff | `gpc_tpc` | 0xc98fab, 0xcb2251, 0xcc082e, 0xcc0845 | *0x20bdc000(+20) *0x204a0000(+26) *0x10348000(-49) *0x104a0000(-55) *0x10d64000(+122) *0x10340000(+171) 0x1881f770(-54) 0x1881f770(+117) 0x203a0000(-180) 0x20964000(-186) 0x1881f770(+189) |
| 0x8d38807 | `CPC_DISABLE` | 0xc99068 | *0x206fc000(+37) *0x202f0000(+43) *0x204a0000(-163) *0x20bdc000(-169) |
| 0x8d38813 | `gpc_cpc` | 0xc99079 | *0x206fc000(+20) *0x202f0000(+26) *0x204a0000(-180) *0x20bdc000(-186) |
| 0x8d3881b | `ROP_DISABLE` | 0xc99136 | *0x209f4000(+37) *0x20470000(+43) *0x202f0000(-163) *0x206fc000(-169) |
| 0x8d38827 | `gpc_rop` | 0xc99147 | *0x209f4000(+20) *0x20470000(+26) *0x202f0000(-180) *0x206fc000(-186) |
| 0x8d3882f | `PES_DISABLE` | 0xc99204 | *0x203a8000(+43) *0x20470000(-163) *0x209f4000(-169) 0x20974000(+37) |
| 0x8d3883b | `gpc_pes` | 0xc99215 | *0x203a8000(+26) *0x20470000(-180) *0x209f4000(-186) 0x20974000(+20) |
| 0x8d38843 | `LTC_DISABLE` | 0xc992d2 | *0x208ac000(+37) *0x20368000(+43) *0x203a8000(-163) 0x20974000(-169) |
| 0x8d3884f | `fbp_ltc` | 0xc992e3, 0xcbb418, 0xcbb4f6 | *0x208ac000(+20) *0x20368000(+26) *0x203a8000(-180) 0x10a04000(-93) 0x1881f770(-98) 0x20974000(-186) |
| 0x8d38857 | `L2SLICE_DISABLE` | 0xc993a0, 0xc62f3b5 | *0x20894000(+37) *0x20360000(+43) *0x20368000(-163) *0x208ac000(-169) |
| 0x8d38867 | `fbp_l2slice` | 0xc993b1 | *0x20894000(+20) *0x20360000(+26) *0x20368000(-180) *0x208ac000(-186) |
| 0x8d38873 | `SYSLTC_DISABLE` | 0xc995d3 | *0x20ee8000(+43) *0x20e88000(+49) |
| 0x8d38882 | `sysltc` | 0xc995f0, 0x1148b0d | *0x20ee8000(+14) *0x20e88000(+20) 0x20ebc000(+190) |
| 0x8d38889 | `HSHUB_DISABLE` | 0xc99691 | *0x20e88000(-141) *0x20ee8000(-147) 0x20ebc000(+29) 0x20e5c000(+35) 0x20eb8000(+188) |
| 0x8d38897 | `hshub` | 0xc996a0, 0x1148b43, 0x114ec21, 0x1158702 | *0x20e88000(-156) *0x20ee8000(-162) 0x20ebc000(+14) 0x20e5c000(+20) 0x20eb8000(+173) 0x20e60000(+179) |
| 0x8d3889d | `HSHUBNVL_DISABLE` | 0xc99730, 0xa2835d0 | 0x20eb8000(+29) 0x20e60000(+35) 0x20e5c000(-124) 0x20ebc000(-130) 0x20edc000(+188) |
| 0x8d388ae | `hshubnvl` | 0xc9973f, 0x1148b79, 0x114ec31, 0x1158915 | 0x20eb8000(+14) 0x20e60000(+20) 0x20e5c000(-139) 0x20ebc000(-145) 0x20edc000(+173) 0x20e80000(+179) |
| 0x8d388b7 | `SCB_DISABLE` | 0xc997cf | 0x20edc000(+29) 0x20e80000(+35) 0x20e60000(-124) 0x20eb8000(-130) 0x20ecc000(+185) 0x20e6c000(+191) |
| 0x8d388c3 | `c2cmisc` | 0xc997de | 0x20edc000(+14) 0x20e80000(+20) 0x20e60000(-139) 0x20eb8000(-145) 0x20ecc000(+170) 0x20e6c000(+176) |
| 0x8d388cb | `PCIE_DISABLE` | 0xc9986b | 0x20ecc000(+29) 0x20e6c000(+35) 0x20e80000(-121) 0x20edc000(-127) 0x20eac000(+188) |
| 0x8d388d8 | `pcie` | 0x664375, 0x671f35, 0xc9987a | 0x20ecc000(+14) 0x20e6c000(+20) 0x20e80000(-136) 0x20edc000(-142) 0x20eac000(+173) 0x20e50000(+179) |
| 0x8d388dd | `FSP_DISABLE` | 0xc9990a | 0x20eac000(+29) 0x20e50000(+35) 0x20e6c000(-124) 0x20ecc000(-130) 0x20ed4000(+188) |
| 0x8d388e9 | `PMU_DISABLE` | 0xc999a9 | 0x20ed4000(+29) 0x20e78000(+35) 0x20e50000(-124) 0x20eac000(-130) 0x20eb4000(+188) |
| 0x8d388f5 | `GSP_DISABLE` | 0xc99a48 | *0x20ec4000(+188) 0x20eb4000(+29) 0x20e58000(+35) 0x20e78000(-124) 0x20ed4000(-130) |
| 0x8d38901 | `OOB_HUB_DISABLE` | 0xc99ae7 | *0x20ec4000(+29) *0x20e64000(+35) *0x20ed8000(+188) 0x20e58000(-124) 0x20eb4000(-130) |
| 0x8d38911 | `oobhub` | 0xc99af6 | *0x20ec4000(+14) *0x20e64000(+20) *0x20ed8000(+173) *0x20e7c000(+179) 0x20e58000(-139) 0x20eb4000(-145) |
| 0x8d38918 | `RHXB_DISABLE` | 0xc99b86 | *0x20ed8000(+29) *0x20e7c000(+35) *0x20e64000(-124) *0x20ec4000(-130) 0x20ee0000(+188) |
| 0x8d38925 | `rhxb` | 0xc99b95 | *0x20ed8000(+14) *0x20e7c000(+20) *0x20e64000(-139) *0x20ec4000(-145) *0x20e84000(+179) 0x20ee0000(+173) |
| 0x8d3892a | `SEC_DISABLE` | 0xc99c25 | *0x20e84000(+35) *0x20e7c000(-124) *0x20ed8000(-130) *0x207fc000(+188) 0x20ee0000(+29) |
| 0x8d3893a | `GPC_DISABLE` | 0xc99cc4 | *0x207fc000(+29) *0x20340000(+35) *0x20e84000(-124) *0x20774000(+188) 0x20ee0000(-130) |
| 0x8d3894a | `FBP_DISABLE` | 0xc99d63 | *0x20774000(+29) *0x20328000(+35) *0x20340000(-124) *0x207fc000(-130) *0x20754000(+188) |
| 0x8d3895a | `FBIO_DISABLE` | 0xc99e02 | *0x20754000(+29) *0x20310000(+35) *0x20328000(-124) *0x20774000(-130) *0x10498000(+176) 0x1881f770(+171) |
| 0x8d38967 | `fbio` | 0xc99e11, 0xcc1047, 0xcc105e, 0xcc28f2 | *0x20754000(+14) *0x20310000(+20) *0x10310000(-28) *0x10488000(-102) *0x20328000(-139) *0x20774000(-145) *0x10498000(+161) *0x10378000(+171) 0x1881f770(-33) 0x1881f770(+41) 0x10330000(+46) 0x1881f770(-107) 0x1881f770(+115) 0x10318000(+120) 0x1881f770(+156) 0x10398000(-176) 0x1881f770(-181) 0x1881f770(+189) |
| 0x8d3896c | `SYS_PIPE_DISABLE` | 0xc99ec8, 0xcaa209, 0xff3c086 | *0x10498000(-22) *0x20bb4000(+29) *0x20490000(+35) *0x20310000(-163) *0x20754000(-169) *0x20914000(+188) 0x1881f770(-27) |
| 0x8d3897d | `syspipe` | 0xc99ed7, 0xcaa291 | *0x20bb4000(+14) *0x20490000(+20) *0x10498000(-37) *0x20914000(+173) *0x20310000(-178) *0x20390000(+179) *0x20754000(-184) 0x1881f770(-42) |
| 0x8d38985 | `OFA_DISABLE` | 0xc99f67, 0xcaa539 | *0x20914000(+29) *0x20390000(+35) *0x20490000(-124) *0x20bb4000(-130) *0x10498000(-181) *0x208f4000(+188) 0x1881f770(-186) |
| 0x8d38995 | `NVJPG_DISABLE` | 0xc9a006, 0xcaa7e3 | *0x208f4000(+29) *0x20380000(+35) *0x20390000(-124) *0x20914000(-130) *0x206e4000(+188) |
| 0x8d389a3 | `nvjpg` | 0x664317, 0x669525, 0xc9a015, 0xcaa7fc | *0x208f4000(+14) *0x20380000(+20) *0x20390000(-139) *0x20914000(-145) *0x206e4000(+173) *0x202e0000(+179) |
| 0x8d389a9 | `C2C_DISABLE` | 0xc9a0a5, 0xca4274 | *0x206e4000(+29) *0x202e0000(+35) *0x206e4000(+50) *0x202e0000(+56) *0x20380000(-124) *0x208f4000(-130) *0x208dc000(+188) |
| 0x8d389b9 | `NVDEC_DISABLE` | 0xc9a144 | *0x208dc000(+29) *0x20370000(+35) *0x202e0000(-124) *0x206e4000(-130) *0x208e4000(+188) |
| 0x8d389c7 | `nvdec` | 0x65476f, 0x6597c7, 0x663cd9, 0x669293 | *0x208dc000(+14) *0x20370000(+20) *0x10370000(-28) *0x10300000(+46) *0x10308000(+120) *0x202e0000(-139) *0x12b58000(-142) *0x206e4000(-145) *0x208e4000(+173) *0x10754000(-176) *0x20378000(+179) *0x10e2c000(+186) 0x1881f770(-33) 0x1881f770(+41) 0x10d54000(-89) 0x1881f770(-94) 0x10320000(-102) 0x1881f770(-107) 0x1881f770(+115) 0x1881f770(-149) 0x10398000(+171) 0x1881f770(-181) 0x1881f770(+189) |
| 0x8d389cd | `NVENC_DISABLE` | 0xc9a1e3 | *0x208e4000(+29) *0x20378000(+35) *0x20370000(-124) *0x208dc000(-130) 0x1881f770(+171) 0x10388000(+176) |
| 0x8d389db | `nvenc` | 0x6547cd, 0x6598e1, 0x66425b, 0x6694c7 | *0x208e4000(+14) *0x20378000(+20) *0x10378000(-28) *0x12b60000(+118) *0x20370000(-139) *0x208dc000(-145) *0x12b58000(-160) *0x10e2c000(+168) 0x1881f770(-33) 0x10318000(-102) 0x10d54000(-107) 0x1881f770(-107) 0x1881f770(-112) 0x1881f770(+113) 0x1881f770(+156) 0x10388000(+161) 0x1881f770(-167) 0x10330000(-176) 0x1881f770(-181) |
| 0x8d389e1 | `NVLINK_DISABLE` | 0xc9a2b9 | *0x20378000(-179) *0x208e4000(-185) 0x208fc000(+29) 0x20388000(+35) 0x10388000(-38) 0x1881f770(-43) |
| 0x8d389f0 | `nvlink` | 0xc9a2c8, 0x114ec01, 0x1158a2c, 0x1c03e7c | 0x208fc000(+14) 0x20388000(+20) 0x1881f770(+41) 0x10968000(+46) 0x10388000(-53) 0x1881f770(-58) |
| 0x8d38c70 | `nvlink_enable` | 0xcb39f1, 0xcb3a2b, 0x8ed1e40, 0x1749e8d0 | 0x1881f770(+170) 0x10358000(+175) 0x1881f770(+187) 0x10358000(+192) |
| 0x8d38c7e | `nvlink_disable` | 0xcb3a43, 0xcb3b67, 0x1b59f6f, 0x8ed1e68 | 0x1881f770(+24) 0x10388000(+29) 0x1881f770(+105) 0x10358000(+110) 0x1881f770(+146) 0x10358000(+151) 0x1887e040(-153) |
| 0x8d38e74 | `OPT_CPC_DIS : 0x%x` | 0xc9f067 | *0x106fc000(-17) *0x429fc102(-143) *0x429fc103(-182) 0x1881f770(-22) 0x1881f770(-148) 0x1881f770(-177) |
| 0x8d38eaa | `OPT_PERLINK_DISABLE` | 0x506165, 0x50bb34, 0x522926, 0x5283f4 | 0x10ddc000(-70) 0x1881f770(-75) |
| 0x8d38ebe | `OPT_C2C_DISABLE` | 0x504c86, 0x509e7f, 0x521447, 0x52673f | 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x1887c340(-21) 0x1887ccc0(-21) 0x1887d220(-21) 0x1887d780(-21) 0x1887e100(-21) 0x1887e660(-21) 0x10ddc000(-144) 0x1881f770(-149) |
| 0x8d38ece | `OPT_CPC_DISABLE` | 0x504cdc, 0x509eec, 0x52149d, 0x5267ac | 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x1887c340(-107) 0x1887ccc0(-107) 0x1887d220(-107) 0x1887d780(-107) 0x1887e100(-107) 0x1887e660(-107) |
| 0x8d38ede | `OPT_SYS_PIPE_DISABLE` | 0x504042, 0x5062f2, 0x50c04d, 0x50e117 | *0x10e24000(-69) 0x1881f770(-74) |
| 0x8d38ef3 | `OPT_OFA_DISABLE` | 0x5000dd, 0x50153d, 0x5024f9, 0x5030af | *0x10e24000(-143) 0x1881f770(-148) |
| 0x8d38f39 | `%s : 0x%x` | 0xca7316 | *0x104d8000(+157) 0x1881f770(-23) 0x1881f770(-38) 0x1881f770(-88) 0x1881f770(+152) |
| 0x8d38f45 | `Cannot read PCE mask` | 0xca75a1 | *0x10d04000(-104) *0x10d64000(+115) *0x10d4c000(+161) 0x1881f770(+110) 0x1881f770(+156) |
| 0x8d38f5b | `OPT_GPC_DISABLE` | 0x4ff8bc, 0x500f3a, 0x502033, 0x502cf0 | *0x106fc000(-62) *0x10e2c000(-175) 0x1881f770(-67) 0x1095c000(-108) 0x1881f770(-113) 0x178745a0(-115) 0x178745a0(-115) 0x178745a0(-115) 0x178745a0(-115) 0x178745a0(-115) 0x178745a0(-115) 0x1887c3c0(-125) 0x1887cd40(-125) 0x1887d2a0(-125) 0x1887d800(-125) 0x1887e180(-125) 0x1887e6e0(-125) 0x178745a0(-133) 0x178745a0(-133) 0x178745a0(-133) 0x178745a0(-133) 0x178745a0(-133) 0x178745a0(-133) 0x1887c400(-143) 0x1887cd80(-143) 0x1887d2e0(-143) 0x1887d840(-143) 0x1887e1c0(-143) 0x1887e720(-143) 0x178745a0(-151) 0x178745a0(-151) 0x178745a0(-151) 0x178745a0(-151) 0x178745a0(-151) 0x178745a0(-151) 0x108fc000(-154) 0x1881f770(-159) 0x1887c440(-161) 0x1887cdc0(-161) 0x1887d320(-161) 0x1887d880(-161) 0x1887e200(-161) 0x1887e760(-161) 0x178745a0(-187) 0x178745a0(-187) 0x178745a0(-187) 0x178745a0(-187) 0x178745a0(-187) 0x178745a0(-187) |
| 0x8d38f8b | `OPT_FBP_DISABLE` | 0x4ff80c, 0x500eae, 0x501fb9, 0x502c88 | *0x106fc000(-124) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x1887c3c0(-21) 0x1887c400(-21) 0x1887c440(-21) 0x1887c470(-21) 0x1887cd40(-21) 0x1887cd80(-21) 0x1887cdc0(-21) 0x1887ce00(-21) 0x1887d2a0(-21) 0x1887d2e0(-21) 0x1887d320(-21) 0x1887d360(-21) 0x1887d800(-21) 0x1887d840(-21) 0x1887d880(-21) 0x1887d8b0(-21) 0x1887e180(-21) 0x1887e1c0(-21) 0x1887e200(-21) 0x1887e240(-21) 0x1887e6e0(-21) 0x1887e720(-21) 0x1887e760(-21) 0x1887e7a0(-21) 0x1887c470(-31) 0x1887ce00(-31) 0x1887d360(-31) 0x1887d8b0(-31) 0x1887e240(-31) 0x1887e7a0(-31) 0x178745a0(-48) 0x178745a0(-48) 0x1887ce20(-51) 0x1887d380(-51) 0x1887e260(-51) 0x1887e7c0(-51) 0x178745a0(-56) 0x178745a0(-56) 0x178745a0(-56) 0x178745a0(-56) 0x1887c880(-58) 0x1887dcc0(-58) 0x1887ce20(-66) 0x1887d380(-66) 0x1887e260(-66) 0x1887e7c0(-66) 0x1887c860(-73) 0x1887dca0(-73) 0x1887ce40(-86) 0x1887d3a0(-86) 0x1887e280(-86) 0x1887e7e0(-86) 0x1887c840(-88) 0x1887dc80(-88) 0x178745a0(-91) 0x178745a0(-91) 0x178745a0(-91) 0x178745a0(-91) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x1887ce40(-101) 0x1887d3a0(-101) 0x1887e280(-101) 0x1887e7e0(-101) 0x1887c820(-103) 0x1887dc60(-103) 0x1887c300(-107) 0x1887cc80(-107) 0x1887d1e0(-107) 0x1887d740(-107) 0x1887e0c0(-107) 0x1887e620(-107) 0x1887c800(-118) 0x1887dc40(-118) 0x1887ce60(-121) 0x1887d3c0(-121) 0x1887e2a0(-121) 0x1887e800(-121) 0x178745a0(-126) 0x178745a0(-126) 0x178745a0(-126) 0x178745a0(-126) 0x1881f770(-129) 0x1887c7e0(-133) 0x1887dc20(-133) 0x1887ce60(-136) 0x1887d3c0(-136) 0x1887e2a0(-136) 0x1887e800(-136) 0x1887c7c0(-148) 0x1887dc00(-148) 0x1887ce80(-156) 0x1887d3e0(-156) 0x1887e2c0(-156) 0x1887e820(-156) 0x178745a0(-161) 0x178745a0(-161) 0x178745a0(-161) 0x178745a0(-161) 0x1887c7a0(-163) 0x1887dbe0(-163) 0x1095c000(-170) 0x1887ce80(-171) 0x1887d3e0(-171) 0x1887e2c0(-171) 0x1887e820(-171) 0x1881f770(-175) 0x1881f770(+178) 0x1887c780(-178) 0x1887dbc0(-178) 0x1887cea0(-191) 0x1887d400(-191) 0x1887e2e0(-191) 0x1887e840(-191) |
| 0x8d38fac | `OPT_FBIO_DISABLE` | 0x50369e, 0x504ecb, 0x50a00d, 0x50d2cd | 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x178745a0(-11) 0x1887c380(-21) 0x1887cd00(-21) 0x1887d260(-21) 0x1887d7c0(-21) 0x1887e140(-21) 0x1887e6a0(-21) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x178745a0(-97) 0x1887c1c0(-107) 0x1887c200(-107) 0x1887c240(-107) 0x1887c280(-107) 0x1887cb40(-107) 0x1887cb80(-107) 0x1887cbc0(-107) 0x1887cc00(-107) 0x1887d0a0(-107) 0x1887d0e0(-107) 0x1887d120(-107) 0x1887d160(-107) 0x1887d600(-107) 0x1887d640(-107) 0x1887d680(-107) 0x1887d6c0(-107) 0x1887df80(-107) 0x1887dfc0(-107) 0x1887e000(-107) 0x1887e040(-107) 0x1887e4e0(-107) 0x1887e520(-107) 0x1887e560(-107) 0x1887e5a0(-107) |
| 0x8d3903b | `OPT_ROP_DIS : 0x%x` | 0xcad3a5, 0x15950d8b | *0x109f4000(-20) *0x10894000(+90) *0x10dfc000(-169) 0x1881f770(-25) |
| 0x8d3906e | `gpc_rop[%u]=0x%x ` | 0xcad91c | *0x10360000(+131) |
| 0x8d39080 | `fbp_l2slice[%u]=0x%x ` | 0xcada24 | *0x10360000(-133) |
| 0x8d390ba | `TPC_GPCx_DISABLE` | 0xcb2235 | *0x10348000(-21) 0x1881f770(-26) |
| 0x8d390cb | `half_ltc` | 0xcb26b0 | 0x1881f770(+97) 0x22341200(+102) 0x1881f770(+121) 0x22341300(+126) 0x1881f770(+142) 0x22340000(+147) 0x1881f770(+165) 0x22340100(+170) 0x20388000(-184) 0x1881f770(+185) 0x22340200(+190) |
| 0x8d390d5 | `nvlink` | 0xcb26c0 | 0x1881f770(+81) 0x22341200(+86) 0x1881f770(+105) 0x22341300(+110) 0x1881f770(+126) 0x22340000(+131) 0x1881f770(+149) 0x22340100(+154) 0x1881f770(+169) 0x22340200(+174) 0x1881f770(+189) |
| 0x8d390dd | `FS IFR Records:` | 0xcb29a1 | *0x12340000(+160) 0x1881f770(+155) 0x1881f770(+185) |
| 0x8d390ee | `[0x%08x] = 0x%08x` | 0xcb29c5, 0x1034763, 0x11ff9e9, 0x1203ddd | *0x12340000(+124) *0x12340000(+161) *0x12340000(+185) 0x1881f770(+119) 0x1881f770(+149) 0x1881f770(+180) |
| 0x8d39101 | `half_ltc` | 0xcb3a15, 0x8ed1e90 | 0x1881f770(+151) 0x10358000(+156) 0x1881f770(+192) |
| 0x8d3917d | `Adjusting GPC mask to 0x%x` | 0xcb6814 | *0x12b58000(+159) *0x12b78000(+177) 0x1881f770(+79) 0x10764000(+84) 0x1881f770(+154) 0x1881f770(+172) |
| 0x8d391c7 | `OPT_PES_DIS : 0x%x` | 0xcb8173 | *0x10984000(-122) 0x10974000(-9) 0x1881f770(-16) |
| 0x8d391dc | `OPT_PES_GPC%u_DIS : 0x%x` | 0xcb8123 | *0x10984000(-42) 0x1881f770(+64) 0x10974000(+71) |
| 0x8d391f7 | `fbp_rop_l2` | 0xcbb41e, 0xcbb4f1 | 0x10a04000(-99) 0x1881f770(-104) |
| 0x8d39202 | `%s[%d] ` | 0xcbb46b | 0x10a04000(-176) 0x1881f770(-181) |
| 0x8d39217 | `OPT_ROP_L2_DIS : 0x%x` | 0xcbb648 | *0x108ac000(+135) *0x108ac000(+191) 0x1881f770(-15) 0x10a04000(-22) 0x10c24000(+31) 0x1881f770(+38) 0x10a04000(-71) 0x1881f770(-76) 0x1881f770(+130) 0x1881f770(+186) |
| 0x8d3922f | `OPT_LTC_DIS : 0x%x` | 0xcbb716 | *0x108ac000(-15) *0x108ac000(-71) 0x1881f770(-20) 0x1881f770(-76) 0x1881f770(-168) 0x10c24000(-175) |
| 0x8d39244 | `OPT_ZCULL_DIS  : 0x%x` | 0xcbb67d | *0x108ac000(+82) *0x108ac000(+138) 0x1881f770(-15) 0x10c24000(-22) 0x1881f770(-68) 0x10a04000(-75) 0x1881f770(+77) 0x10a04000(-124) 0x1881f770(-129) 0x1881f770(+133) |
| 0x8d3925c | `fbp_rop_l2_enable` | 0xcbc6a4, 0xcbcaee, 0xcbcb1a, 0x8ed4200 | *0x10368000(-140) 0x10a04000(-17) 0x1881f770(-28) 0x178a0a20(-100) |
| 0x8d3926e | `fbp_rop_l2_disable` | 0xcbcae0, 0xcbcb31, 0x1ad4dbc, 0x8ed4228 | *0x10368000(-126) |
| 0x8d39281 | `RopL2` | 0xcbcf12, 0xbb155f0, 0xbc4fc16, 0xc201890 | 0x10a04000(-51) 0x1881f770(-56) |
| 0x8d3928b | `fbp%s[%d]_mask` | 0xcbcf4d, 0xac825e7 | 0x10a04000(-110) 0x1881f770(-115) |
| 0x8d3929a | `head` | 0xcbd31d, 0xcc0f6e, 0xcc0f80, 0x16c800a | *0x10308000(-33) *0x10300000(-107) *0x10488000(+115) *0x12b58000(-155) *0x10e2c000(+173) *0x10370000(-181) *0x10310000(+189) 0x1881f770(+36) 0x1881f770(-38) 0x10398000(+41) 0x10d54000(-102) 0x1881f770(-107) 0x1881f770(+110) 0x1881f770(-112) 0x1881f770(-162) 0x1881f770(+184) 0x1881f770(-186) |
| 0x8d3929f | `OPT_MCHIP_EN   : 0x%x` | 0xcbd58f | *0x108b4000(-20) *0x10844000(+28) *0x10e14000(-86) *0x10d34000(+108) *0x20e14000(-132) *0x10da4000(+148) *0x10310000(-185) *0x10dac000(+188) 0x1881f770(+21) 0x1881f770(-25) 0x1881f770(+61) 0x10d5c000(+68) 0x1881f770(-91) 0x1881f770(+101) 0x1881f770(-137) 0x1881f770(+141) 0x1881f770(+181) |
| 0x8d392b7 | `OPT_HDCP_EN    : 0x%x` | 0xcbd5b7 | *0x10844000(-12) *0x108b4000(-60) *0x10d34000(+68) *0x10da4000(+108) *0x10e14000(-126) *0x10dac000(+148) *0x20e14000(-172) *0x1073c000(+188) 0x1881f770(-19) 0x1881f770(+21) 0x10d5c000(+28) 0x1881f770(+61) 0x1881f770(-65) 0x1881f770(+101) 0x1881f770(-131) 0x1881f770(+141) 0x1881f770(-177) 0x1881f770(+181) |
| 0x8d392cf | `OPT_GC6_ISLAND : 0x%x` | 0xcbd5df | *0x10d34000(+28) *0x10844000(-52) *0x10da4000(+68) *0x108b4000(-100) *0x10dac000(+108) *0x1073c000(+148) *0x10e14000(-166) 0x10d5c000(-12) 0x1881f770(-19) 0x1881f770(+21) 0x1881f770(-59) 0x1881f770(+61) 0x1881f770(+101) 0x1881f770(-105) 0x1881f770(+141) 0x1881f770(-171) |
| 0x8d392e7 | `OPT_DISPLAY_DIS: 0x%x` | 0xcbd607 | *0x10d34000(-12) *0x10da4000(+28) *0x10dac000(+68) *0x10844000(-92) *0x1073c000(+108) *0x108b4000(-140) 0x1881f770(-19) 0x1881f770(+21) 0x10d5c000(-52) 0x1881f770(-59) 0x1881f770(+61) 0x1881f770(-99) 0x1881f770(+101) 0x1881f770(-145) 0x10d24000(+164) 0x1881f770(+174) |
| 0x8d392ff | `OPT_NVDEC_DIS  : 0x%x` | 0xcbd62f | *0x10da4000(-12) *0x10dac000(+28) *0x10d34000(-52) *0x1073c000(+68) *0x10844000(-132) *0x108b4000(-180) 0x1881f770(-19) 0x1881f770(+21) 0x1881f770(-59) 0x1881f770(+61) 0x10d5c000(-92) 0x1881f770(-99) 0x10d24000(+124) 0x1881f770(+134) 0x1881f770(-139) 0x1881f770(+164) 0x10a54000(+172) 0x1881f770(-185) |
| 0x8d39317 | `OPT_NVENC_DIS  : 0x%x` | 0xcbd657 | *0x10dac000(-12) *0x1073c000(+28) *0x10da4000(-52) *0x10d34000(-92) *0x10844000(-172) 0x1881f770(-19) 0x1881f770(+21) 0x1881f770(-59) 0x10d24000(+84) 0x1881f770(+94) 0x1881f770(-99) 0x1881f770(+124) 0x10a54000(+132) 0x10d5c000(-132) 0x1881f770(-139) 0x1881f770(+167) 0x10df4000(+172) 0x1881f770(-179) |
| 0x8d3932f | `OPT_ECC_EN     : 0x%x` | 0xcbd67f | *0x1073c000(-12) *0x10dac000(-52) *0x10da4000(-92) *0x10d34000(-132) 0x1881f770(-19) 0x10d24000(+44) 0x1881f770(+54) 0x1881f770(-59) 0x1881f770(+84) 0x10a54000(+92) 0x1881f770(-99) 0x1881f770(+127) 0x10df4000(+132) 0x1881f770(-139) 0x10d5c000(-172) 0x1881f770(-179) |
| 0x8d39347 | `OPT_CE_DIS     : 0x%x` | 0xcbd6be | *0x1073c000(-75) *0x10dac000(-115) *0x10da4000(-155) *0x10da4000(+186) 0x1881f770(-9) 0x10d24000(-19) 0x1881f770(+21) 0x10a54000(+29) 0x1881f770(+64) 0x10df4000(+69) 0x1881f770(-82) 0x1881f770(-122) 0x1881f770(-162) 0x1881f770(+181) |
| 0x8d3935f | `OPT_SEC_DEBUG_EN: 0x%x` | 0xcbd6e6 | *0x1073c000(-115) *0x10da4000(+146) *0x10dac000(-155) *0x20da4000(+182) 0x10a54000(-11) 0x1881f770(-19) 0x1881f770(+24) 0x10df4000(+29) 0x1881f770(-49) 0x10d24000(-59) 0x1881f770(-122) 0x1881f770(+141) 0x1881f770(-162) 0x1881f770(+177) |
| 0x8d39378 | `OPT_PRIV_SEC_EN: 0x%x` | 0xcbd70e | *0x10da4000(+106) *0x20da4000(+142) *0x1073c000(-155) 0x10df4000(-11) 0x1881f770(-16) 0x10a54000(-51) 0x1881f770(-59) 0x1881f770(-89) 0x10d24000(-99) 0x1881f770(+101) 0x1881f770(+137) 0x1881f770(-162) |
| 0x8d39390 | `head_enable` | 0xcbe251, 0xcbe2dd, 0x8ed4900, 0x1749fb50 | 0x178a0ae0(-137) |
| 0x8d393a9 | `Cannot read XP mask` | 0xcbe4d1 | 0x20dd4000(-52) 0x1881f770(-57) 0x20dd4000(-87) 0x10dd4000(-145) 0x1881f770(-150) |
| 0x8d393be | `gpc_zcull` | 0xcc0bca, 0xcc0be1 | 0x104a8000(-55) |
| 0x8d393c8 | `display` | 0xcc0f1f, 0xcc0f36, 0xcc28a6, 0xd9d9a6 | *0x10300000(-28) *0x10308000(+46) *0x10370000(-102) *0x10488000(+171) 0x1881f770(-33) 0x1881f770(+41) 0x187ac6f8(-57) 0x187acb38(-57) 0x187ac700(-72) 0x187acb40(-72) 0x187acc38(+74) 0x178745a0(-77) 0x178745a0(-77) 0x187ac700(-87) 0x187acb40(-87) 0x187acc40(+95) 0x1881f770(-107) 0x1881f770(+115) 0x10398000(+120) 0x10320000(-176) 0x1881f770(-181) 0x1881f770(+189) |
| 0x8d393d0 | `fbio_shift_override` | 0xcc0e8b, 0xcc0ea2, 0xcc2906 | *0x10370000(+46) *0x10754000(-102) *0x10300000(+120) *0x10328000(-149) *0x10308000(+171) 0x10320000(-28) 0x1881f770(-33) 0x1881f770(+41) 0x1881f770(-107) 0x1881f770(+115) 0x1881f770(-154) 0x1881f770(+189) |
| 0x8d393e7 | `fbio_shift` | 0xcc10db, 0xcc10f2, 0xcc28ec, 0xcc49f2 | *0x10378000(+46) *0x10310000(-176) *0x12b60000(+192) 0x10318000(-28) 0x1881f770(-33) 0x1881f770(+41) 0x10330000(-102) 0x1881f770(-107) 0x1881f770(-181) 0x1881f770(+187) |
| 0x8d393f2 | `pcie_lane` | 0xcc0fb3, 0xcc0fca, 0xcc1ab6 | *0x10488000(+46) *0x10308000(-102) *0x10310000(+120) *0x10754000(-145) *0x10300000(-176) 0x10398000(-28) 0x1881f770(-33) 0x1881f770(+41) 0x1881f770(-101) 0x1075c000(-106) 0x1881f770(-107) 0x1881f770(+115) 0x1881f770(-153) 0x10330000(+171) 0x1881f770(-181) 0x1881f770(+189) |
| 0x8d393fc | `fbpa` | 0xcc1091, 0xcc10a8, 0xcc1aa4, 0x10f72b5 | *0x10310000(-102) *0x10378000(+120) *0x10754000(-127) *0x10488000(-176) 0x10330000(-28) 0x1881f770(-33) 0x1881f770(+41) 0x10318000(+46) 0x1881f770(-83) 0x1075c000(-88) 0x1881f770(-107) 0x1881f770(+115) 0x1881f770(-135) 0x1881f770(-181) |
| 0x8d39401 | `spare` | 0xcc0ffd, 0xcc1014, 0xcc1ab1, 0x135984b | *0x10488000(-28) *0x10310000(+46) *0x10754000(-140) *0x10308000(-176) 0x1881f770(-33) 0x1881f770(+41) 0x1881f770(-96) 0x1075c000(-101) 0x10398000(-102) 0x1881f770(-107) 0x1881f770(+115) 0x10330000(+120) 0x1881f770(-148) 0x10318000(+171) 0x1881f770(-181) 0x1881f770(+189) |
| 0x8d3947a | `pcie_lane_enable` | 0xcc1d61, 0xcc1dc9, 0x8ed4f00, 0x1749fbc0 | 0x178a0bc0(-80) 0x22b3c100(-110) 0x1881f770(-118) |
| 0x8d3949d | `fbpa_enable` | 0xcc1d83, 0xcc1dfa, 0x8ed4f50, 0xfd9bc3a | 0x178a0bc0(-114) 0x22b3c100(-144) 0x1881f770(-152) |
| 0x8d394b6 | `spare_enable` | 0xcc1da5, 0xcc1e2a, 0x8ed4fa0, 0x1749fc30 | 0x178a0bc0(-148) 0x22b3c100(-178) 0x1881f770(-186) |
| 0x8d3951b | `GpcEnableMask` | 0x3e760a, 0xcc3677, 0xdccedc, 0xdcf83e | *0x42be0001(-34) *0x42be0001(-57) *0x42be0000(-134) *0x42be0000(-157) 0x1881f770(-62) 0x1881f770(-107) 0x1879ab00(-108) 0x178745a0(-113) 0x1879ab00(-123) 0x187a1880(-128) 0x1881f770(-162) 0x1879ab60(-172) 0x178745a0(-177) 0x1879ab60(-187) 0x187a1880(-192) |
| 0x8d39529 | `GpcEnableMask is not valid!!` | 0xcc36cf | *0x42be0001(-122) *0x42be0001(-145) 0x1881f770(-150) |
| 0x8d39547 | `PollMasterRingCommand` | 0xcc3bf8 | *0x129b4000(-39) *0x429b4100(-73) *0x129bc000(+77) *0x129b4000(-118) *0x429f0001(+157) *0x429dc001(-159) *0x429f0001(+174) *0x429dc001(-176) 0x1881f770(-45) 0x1881f770(+71) 0x1881f770(-78) 0x1881f770(+93) 0x429b4003(+98) 0x429b4001(-100) 0x1881f770(-105) 0x429b4003(+115) 0x1881f770(-123) 0x1881f770(+131) 0x1881f770(-144) 0x1881f770(+152) 0x1881f770(-181) |
| 0x8d3955d | `...done` | 0xcc3c29 | *0x129bc000(+28) *0x129b4000(-88) *0x429f0001(+108) *0x429b4100(-122) *0x429f0001(+125) *0x129b4000(-167) 0x1881f770(+22) 0x1881f770(+44) 0x429b4003(+49) 0x429b4003(+66) 0x1881f770(+82) 0x1881f770(-94) 0x1881f770(+103) 0x1881f770(-127) 0x1881f770(+148) 0x429b4001(-149) 0x1881f770(-154) 0x1881f770(-172) |
| 0x8d39566 | `SkipFsPlmCheck` | 0x3e784e, 0xcc3d29, 0xcc501d, 0xdcda6c | *0x409c4000(+99) *0x10e3c000(+126) *0x429f0001(-131) *0x10e3c000(+143) *0x429f0001(-148) *0x40e3c000(+164) *0x40e3c000(+182) 0x1881f770(+94) 0x1881f770(-108) 0x1881f770(+118) 0x1881f770(+138) 0x187a1880(+141) 0x1879aaa0(+146) 0x1881f770(-153) 0x178745a0(+156) 0x1881f770(+159) 0x1879aaa0(+161) 0x1881f770(-174) 0x1881f770(+177) 0x429b4003(-190) |
| 0x8d39598 | `msdec_enable` | 0xcc48f6, 0xcc4a42, 0x8ed5070, 0x1749fcd8 | 0x178a0ca0(-101) |
| 0x8d395b3 | `msvld_enable` | 0xcc491a, 0xcc4a75, 0x8ed50c0, 0x1749fd10 | 0x178a0ca0(-137) |
| 0x8d395ce | `fbio_shift_override_enable` | 0xcc493e, 0xcc4aa8, 0x8ed5110, 0x1749fd48 | 0x178a0ca0(-173) |
| 0x8d3962d | `ZcullEnableMaskOnGpc` | 0x3e76be, 0xcc5e2c, 0xcc66cc, 0xdd4349 | *0x12b78000(+191) 0x1881f770(+186) |
| 0x8d39901 | `Mode` | 0x4a24cd, 0x5b2e0f, 0xccc1e8, 0x123b91e | 0x18822480(+4) 0x18822120(+9) 0x1888a4e0(+16) 0x178745a0(+19) 0x1888a480(+21) 0x18822120(+24) 0x178745a0(+31) 0x1888a4e0(-34) 0x1888a480(+36) 0x178745a0(-39) 0x18822180(-40) 0x178745a0(-45) 0x1888a4e0(-49) 0x18822180(-55) 0x178ca820(-59) 0x18822480(-60) 0x188820e0(-64) 0x18822480(+75) 0x188220c0(+80) 0x1888a4e0(+86) 0x178745a0(+90) 0x1888a420(+91) 0x188220c0(+95) 0x1888a580(-95) 0x178745a0(-100) 0x178745a0(+101) 0x1888a420(+106) 0x188221e0(-110) 0x1888a580(-110) 0x178745a0(-115) 0x188221e0(-125) 0x18822480(-130) 0x1888a5a0(-133) 0x178745a0(-138) 0x18822480(+147) 0x1888a5a0(-148) 0x18822060(+152) 0x1888a4e0(+157) 0x178745a0(+162) 0x1888a3c0(+162) 0x18822060(+167) 0x1888a5c0(-171) 0x178745a0(+172) 0x178745a0(-176) 0x1888a3c0(+177) 0x18822240(-181) 0x178745a0(-186) 0x1888a5c0(-186) |
| 0x8d39906 | `Invalid fslib mode %u` | 0xccc201, 0xccc8d7 | 0x18786248(+53) |
| 0x8d39a58 | `Testing with Fslib mode %u` | 0xccf2e0, 0xcd0185, 0xcd02f3 | 0x18786248(-132) 0x18786240(-186) |
| 0x8d39aa8 | `GpcMask` | 0x3e54ae, 0xccf4eb, 0xdc2931 | 0x187a1880(+4) 0x1879db60(+9) 0x178745a0(+19) 0x1879db60(+24) 0x1879dbc0(-41) 0x178745a0(-46) 0x1879dbc0(-56) 0x187a1880(-61) 0x187a1880(+69) 0x1879db00(+74) 0x178745a0(+84) 0x1879db00(+89) 0x1879dc20(-107) 0x178745a0(-112) 0x1879dc20(-122) 0x187a1880(-127) 0x187a1880(+134) 0x1879daa0(+139) 0x178745a0(+149) 0x1879daa0(+154) 0x1879dc80(-172) 0x178745a0(-177) 0x1879dc80(-187) 0x187a1880(-192) |
| 0x8d39ae6 | `FbpMask` | 0x3e5570, 0xccf768, 0xdbecd1, 0x1649e9c | 0x187a1880(+4) 0x1879da40(+9) 0x178745a0(+19) 0x1879da40(+24) 0x1879daa0(-40) 0x178745a0(-45) 0x1879daa0(-55) 0x187a1880(-60) 0x187a1880(+68) 0x1879d9e0(+73) 0x178745a0(+83) 0x1879d9e0(+88) 0x1879db00(-105) 0x178745a0(-110) 0x1879db00(-120) 0x187a1880(-125) 0x187a1880(+133) 0x1879d980(+138) 0x178745a0(+148) 0x1879d980(+153) 0x1879db60(-170) 0x178745a0(-175) 0x1879db60(-185) 0x187a1880(-190) |
| 0x8d39b40 | `FsLib interface.` | 0x3d3529 | 0x178a0f40(+10) 0x18786240(-17) 0x187861a0(+20) 0x178745a0(-22) 0x178745a0(+32) 0x187861a0(+37) 0x18786240(-75) 0x187861a0(+79) 0x18786248(-80) 0x18786160(+84) 0x178745a0(+94) 0x18786160(+99) 0x18786248(-125) 0x187861a0(+141) 0x18786120(+146) 0x178745a0(+156) 0x18786120(+161) |
| 0x8d39b51 | `FsLib` | 0x3d3539, 0x1749ff40 | 0x187861a0(+4) 0x178a0f40(-6) 0x178745a0(+16) 0x187861a0(+21) 0x18786240(-33) 0x178745a0(-38) 0x187861a0(+63) 0x18786160(+68) 0x178745a0(+78) 0x18786160(+83) 0x18786240(-91) 0x18786248(-96) 0x187861a0(+125) 0x18786120(+130) 0x178745a0(+140) 0x18786248(-141) 0x18786120(+145) 0x187861a0(+187) 0x187860e0(+192) |
| 0x8d39b57 | `SetMode` | 0x3d35ad, 0x3dab90, 0x3f90f8, 0xf3cc86 | 0x1878a240(+4) 0x187afb20(+4) 0x187861a0(+9) 0x18789f80(+9) 0x187ac1c0(+9) 0x18786120(+14) 0x178745a0(+19) 0x178745a0(+23) 0x178745a0(+24) 0x187ac1c0(+24) 0x18789f80(+28) 0x18786120(+29) 0x18786160(-33) 0x18789fc0(-33) 0x178745a0(-38) 0x178745a0(-38) 0x187ac2c0(-38) 0x178745a0(-43) 0x18786160(-48) 0x18789fc0(-51) 0x187861a0(-53) 0x187ac2c0(-53) 0x1878a240(-56) 0x187afb20(-58) 0x187afb20(+62) 0x1878a240(+65) 0x18789f40(+70) 0x187861a0(+71) 0x187ac0c0(+73) 0x187860e0(+76) 0x178745a0(+83) 0x178745a0(+84) 0x178745a0(+86) 0x187ac0c0(+88) 0x18789f40(+89) 0x187860e0(+91) 0x1878a000(-93) 0x187861a0(-95) 0x178745a0(-98) 0x178745a0(-100) 0x187ac3c0(-100) 0x178745a0(-105) 0x187861a0(-112) 0x1878a000(-114) 0x187ac3c0(-115) 0x1878a240(-119) 0x187afb20(-120) 0x178a0f40(-122) 0x187afb20(+126) 0x1878a240(+128) 0x187861a0(+133) 0x18789f00(+136) 0x187abfc0(+137) 0x187860a0(+138) 0x178745a0(+146) 0x178745a0(+147) 0x178745a0(+148) 0x18786240(-149) 0x18789f00(+151) 0x187abfc0(+152) 0x187860a0(+153) 0x178745a0(-154) 0x187ac4c0(-162) 0x1878a040(-163) 0x178745a0(-167) 0x178745a0(-168) 0x187ac4c0(-177) 0x1878a040(-182) 0x187afb20(-182) 0x1878a240(-187) 0x1878a240(+190) |
| 0x8d39b5f | `IsFloorsweepingValid` | 0x3d35f0 | 0x187861a0(+4) 0x187860e0(+9) 0x178745a0(+19) 0x187860e0(+24) 0x18786120(-38) 0x178745a0(-43) 0x18786120(-53) 0x187861a0(-58) 0x187861a0(+66) 0x187860a0(+71) 0x178745a0(+81) 0x187860a0(+86) 0x18786160(-100) 0x178745a0(-105) 0x18786160(-115) 0x187861a0(-120) 0x187861a0(+133) 0x18786040(+138) 0x178745a0(+148) 0x18786040(+153) 0x187861a0(-162) 0x178745a0(-167) 0x187861a0(-179) 0x178a0f40(-189) |
| 0x8d39b74 | `SetTimeoutMs` | 0x3d362e | 0x187861a0(+4) 0x187860a0(+9) 0x178745a0(+19) 0x187860a0(+24) 0x187860e0(-38) 0x178745a0(-43) 0x187860e0(-53) 0x187861a0(-58) 0x187861a0(+71) 0x18786040(+76) 0x178745a0(+86) 0x18786040(+91) 0x18786120(-100) 0x178745a0(-105) 0x18786120(-115) 0x187861a0(-120) 0x187861a0(+138) 0x18785fe0(+143) 0x178745a0(+153) 0x18785fe0(+158) 0x18786160(-162) 0x178745a0(-167) 0x18786160(-177) 0x187861a0(-182) 0x187861a0(+187) |
| 0x8d39b81 | `MODE_DISABLE` | 0x3d3671 | 0x187861a0(+4) 0x18786040(+9) 0x178745a0(+19) 0x18786040(+24) 0x187860a0(-43) 0x178745a0(-48) 0x187860a0(-58) 0x187861a0(-63) 0x187861a0(+71) 0x18785fe0(+76) 0x178745a0(+86) 0x18785fe0(+91) 0x187860e0(-105) 0x178745a0(-110) 0x187860e0(-120) 0x187861a0(+120) 0x187861a0(-125) 0x18785f80(+128) 0x178745a0(+147) 0x18785f80(+152) 0x18786120(-167) 0x178745a0(-172) 0x18786120(-182) 0x187861a0(-187) |
| 0x8d39b8e | `CONSTANT: MODE_DISABLE` | 0x3d365a | 0x187860a0(-20) 0x178745a0(-25) 0x187861a0(+27) 0x18786040(+32) 0x187860a0(-35) 0x187861a0(-40) 0x178745a0(+42) 0x18786040(+47) 0x187860e0(-82) 0x178745a0(-87) 0x187861a0(+94) 0x187860e0(-97) 0x18785fe0(+99) 0x187861a0(-102) 0x178745a0(+109) 0x18785fe0(+114) 0x187861a0(+143) 0x18786120(-144) 0x178745a0(-149) 0x18785f80(+151) 0x18786120(-159) 0x187861a0(-164) 0x178745a0(+170) 0x18785f80(+175) |
| 0x8d39ba5 | `MODE_FUNC_VALID` | 0x3d36b4 | 0x187861a0(+4) 0x18785fe0(+9) 0x178745a0(+19) 0x18785fe0(+24) 0x18786040(-43) 0x178745a0(-48) 0x187861a0(+53) 0x18786040(-58) 0x18785f80(+61) 0x187861a0(-63) 0x178745a0(+80) 0x18785f80(+85) 0x187860a0(-110) 0x178745a0(-115) 0x187860a0(-125) 0x187861a0(-130) 0x187860e0(-172) 0x178745a0(-177) 0x187860e0(-187) 0x187861a0(-192) |
| 0x8d39bb5 | `CONSTANT: MODE_FUNC_VALID` | 0x3d369d | 0x18786040(-20) 0x178745a0(-25) 0x187861a0(+27) 0x18785fe0(+32) 0x18786040(-35) 0x187861a0(-40) 0x178745a0(+42) 0x18785fe0(+47) 0x187861a0(+76) 0x18785f80(+84) 0x187860a0(-87) 0x178745a0(-92) 0x187860a0(-102) 0x178745a0(+103) 0x187861a0(-107) 0x18785f80(+108) 0x187860e0(-149) 0x178745a0(-154) 0x187860e0(-164) 0x187861a0(-169) |
| 0x8d39bcf | `MODE_PRODUCT` | 0x3d36e5 | 0x187861a0(+4) 0x18785f80(+12) 0x18785fe0(-25) 0x178745a0(-30) 0x178745a0(+31) 0x18785f80(+36) 0x18785fe0(-40) 0x187861a0(-45) 0x18786040(-92) 0x178745a0(-97) 0x18786040(-107) 0x187861a0(-112) 0x187860a0(-159) 0x178745a0(-164) 0x187860a0(-174) 0x187861a0(-179) |
| 0x8d39bdc | `CONSTANT: MODE_PRODUCT` | 0x3d36de | 0x187861a0(+11) 0x18785fe0(-18) 0x18785f80(+19) 0x178745a0(-23) 0x18785fe0(-33) 0x178745a0(+38) 0x187861a0(-38) 0x18785f80(+43) 0x18786040(-85) 0x178745a0(-90) 0x18786040(-100) 0x187861a0(-105) 0x187860a0(-152) 0x178745a0(-157) 0x187860a0(-167) 0x187861a0(-172) |
| 0x8d39cc4 | `NV_%s = 0x%08x` | 0xcd3ecf, 0xcd401f | 0x1881f770(-48) 0x1881f770(-50) 0x1881f770(-108) 0x1881f770(+152) |
| 0x8d39cd5 | `Rm call failed ` | 0xcd6ce1 | 0x20801802(-64) 0x20801814(+176) 0x187686e0(-188) |
| 0x8d39ce6 | `due to a training error` | 0xcd77c7 | 0x20801804(-139) |
| 0x8d39cff | `because ASLM is disabled` | 0xcd77ec | 0x20801804(-176) |
| 0x8d39d19 | `SetAspm on GPU: 0x%x` | 0xcd7c81 | *0x21ac4000(-15) *0x11ac4000(+33) *0x11ac4000(-64) 0x1881f770(+27) 0x1881f770(-28) 0x1881f770(-69) |
| 0x8d39d2f | `speed unknown` | 0xcd7ef1 | 0x20801802(-166) |
| 0x8d39d3e | `Cannot train Gpu to %dMB/s` | 0xcd8180 | 0x20801805(-17) |
| 0x8d39d5a | `Invalid lane %u specified` | 0xcd95dc, 0xcd977c, 0xcdca5c, 0xcddbef | *0x22fcc000(-20) *0x22fcc000(-23) *0x22fcc000(-23) *0x12fd4000(+40) *0x12fd4000(+47) *0x12fcc000(+104) *0x21ab8000(+109) *0x12fcc000(+111) *0x12fd4000(+132) *0x12fd4000(+139) *0x21ab8000(+158) *0x22fd4200(+158) *0x22fd4200(+165) *0x430ac500(-170) *0x430ac500(-187) *0x22fd4000(+189) 0x1881f770(-25) 0x1881f770(-28) 0x1881f770(-28) 0x23274000(-33) 0x1881f770(+35) 0x13268000(-37) 0x1881f770(-38) 0x1881f770(+42) 0x1881f770(-43) 0x2326c000(-44) 0x1881f770(-49) 0x1881f770(-63) 0x23274000(-66) 0x2325c000(+67) 0x1881f770(-72) 0x1881f770(-80) 0x2326c000(-80) 0x2326c000(-80) 0x1881f770(-85) 0x23268000(-88) 0x20801827(+89) 0x23268300(-91) 0x1881f770(+92) 0x20801814(-94) 0x1881f770(+95) 0x1881f770(-96) 0x20801827(+97) 0x1881f770(-99) 0x1881f770(+99) 0x1881f770(-99) 0x23274000(+100) 0x13268000(-104) 0x1881f770(-104) 0x1881f770(+104) 0x1881f770(+106) 0x13268000(-109) 0x2325c000(+109) 0x2326c000(-116) 0x23268200(-120) 0x23274000(-124) 0x1881f770(-125) 0x1881f770(+127) 0x1881f770(+129) 0x1881f770(-130) 0x1881f770(+132) 0x1881f770(-133) 0x1881f770(+134) 0x23274000(+134) 0x23268000(-136) 0x23274000(-138) 0x1881f770(+139) 0x1881f770(-141) 0x13268000(+144) 0x23268100(-149) 0x1881f770(+150) 0x23268000(-150) 0x1881f770(+153) 0x1881f770(-154) 0x1881f770(-154) 0x1881f770(-155) 0x1881f770(+158) 0x23268300(-159) 0x1881f770(+160) 0x13268000(-162) 0x23268000(+163) 0x1881f770(-167) 0x1881f770(-168) 0x1881f770(+170) 0x13268000(+175) 0x13268000(-177) 0x1881f770(-182) 0x23268000(-182) 0x1881f770(+183) 0x1881f770(+184) 0x23274000(-186) 0x1881f770(-187) 0x132a8000(+188) 0x23268000(-188) 0x1881f770(+191) 0x1881f770(+191) 0x1881f770(-192) 0x1881f770(-192) |
| 0x8d39d75 | `&PollEomDone` | 0xcda03e, 0x14cc36b, 0x14cc48f | 0x1881f770(-21) 0x23274000(-26) 0x1881f770(+64) 0x43274000(+69) 0x1881f770(-92) 0x43274000(+92) 0x1881f770(+117) 0x4325c101(-117) 0x4325c101(-140) 0x1881f770(+141) 0x1881f770(-145) 0x4325c100(+146) 0x1881f770(-169) 0x4325c100(+169) |
| 0x8d39d82 | `DoGetEomStatus` | 0xcda043, 0xcda94e, 0xcdaa9e, 0xcdb53b | 0x1881f770(-26) 0x1881f770(+31) 0x23274000(-31) 0x1881f770(+34) 0x1881f770(-35) 0x1881f770(-35) 0x1881f770(-35) 0x1881f770(-35) 0x1881f770(-35) 0x1881f770(-35) 0x1881f770(-36) 0x1881f770(-36) 0x413e0000(+36) 0x413e4000(+36) 0x1881f770(+37) 0x1881f770(+37) 0x1881f770(+37) 0x1881f770(+38) 0x43274000(+39) 0x1881f770(+42) 0x1881f770(+42) 0x1881f770(+42) 0x413e4000(+42) 0x43274000(+42) 0x43274000(+42) 0x23274000(-43) 0x23274000(-43) 0x23274000(-43) 0x23274000(-43) 0x20088000(+46) 0x23274000(-46) 0x23274000(-46) 0x43274000(+46) 0x43274000(+47) 0x43274000(+47) 0x43274000(+47) 0x23274000(-48) 0x23274000(-48) 0x43274000(+56) 0x1881f770(+59) 0x413e0100(+60) 0x413e4000(+60) 0x43274000(+64) 0x43274000(+64) 0x43274000(+64) 0x43274000(+64) 0x43274000(+64) 0x413e4000(+67) 0x43274000(+69) 0x1881f770(+70) 0x1881f770(-70) 0x1881f770(+71) 0x20088000(+71) 0x1881f770(-74) 0x43274000(+74) 0x43274000(+75) 0x1881f770(+76) 0x413e0101(+76) 0x42884101(+76) 0x1881f770(+78) 0x2080300c(+78) 0x2080303c(+78) 0x413e0000(+78) 0x413e0101(+78) 0x1881f770(+79) 0x1881f770(+79) 0x1881f770(+80) 0x1881f770(+80) 0x1881f770(+85) 0x1881f770(-86) 0x43274000(+87) 0x1881f770(+89) 0x1881f770(+90) 0x1881f770(+91) 0x42884000(+91) 0x1881f770(+92) 0x1881f770(+94) 0x1881f770(+94) 0x1881f770(+96) 0x1881f770(+96) 0x1881f770(+96) 0x20088000(+96) 0x413e4000(-96) 0x1881f770(-97) 0x4325c100(+97) 0x1881f770(+100) 0x1881f770(+100) 0x1881f770(+100) 0x1881f770(+100) 0x413e4001(-100) 0x1881f770(+101) 0x1881f770(+101) 0x1881f770(+101) 0x43274000(+102) 0x413e4000(+105) 0x4325c100(+105) 0x4325c201(+105) 0x1881f770(+106) 0x4325c100(+106) 0x4325c201(+106) 0x1881f770(+107) 0x1881f770(+108) 0x1881f770(+108) 0x413e4001(-108) 0x413e4100(+108) 0x1881f770(+111) 0x4325c100(+111) 0x1881f770(+112) 0x1881f770(+112) 0x413e4100(+112) 0x4325c100(+114) 0x413e0001(-116) 0x4325c201(+116) 0x1881f770(-117) 0x20088000(+117) 0x413e0101(+117) 0x42884101(+117) 0x1881f770(+118) 0x413e0000(-118) 0x413e0000(+118) 0x413e0101(+118) 0x42884001(-118) 0x413e0001(-119) 0x413e4000(-121) 0x413e4001(-121) 0x4325c100(+122) 0x4325c101(-122) 0x4325c201(+122) 0x42884000(-123) 0x4325c100(+123) 0x4325c201(+123) 0x413e0000(-124) 0x42884000(+125) 0x1881f770(-126) 0x4325c100(+128) 0x1881f770(-129) 0x1881f770(+129) 0x413e4000(+129) 0x413e4100(+129) 0x4325c200(-132) 0x213d4100(-133) 0x413e4001(-133) 0x4325c201(+133) 0x1881f770(-134) 0x1881f770(+136) 0x1881f770(-136) 0x1881f770(+137) 0x1881f770(+137) 0x413e4100(+137) 0x1881f770(-138) 0x1881f770(-138) 0x1881f770(-138) 0x1881f770(-138) 0x1881f770(+139) 0x1881f770(+139) 0x1881f770(+139) 0x1881f770(-139) 0x1881f770(-140) 0x1881f770(-140) 0x1881f770(-141) 0x1881f770(-141) 0x4325c100(+141) 0x1881f770(-142) 0x1881f770(-142) 0x1881f770(-143) 0x213d4100(+143) 0x1881f770(+144) 0x4325c201(+144) 0x1881f770(-145) 0x4325c101(-145) 0x1881f770(-146) 0x1881f770(-147) 0x1881f770(+149) 0x4325c200(-149) 0x1881f770(-150) 0x1881f770(+150) 0x1881f770(+153) 0x1881f770(-154) 0x4325c100(-154) 0x4325c200(+155) 0x1881f770(-156) 0x413e0001(-156) 0x4325c100(-156) 0x1881f770(+158) 0x1881f770(+158) 0x413e0000(-158) 0x4325c100(-158) 0x1881f770(+159) 0x42884001(-159) 0x4325c100(-159) 0x1881f770(+160) 0x1881f770(+160) 0x413e0001(-160) 0x1881f770(+161) 0x4325c101(-161) 0x4325c201(+161) 0x4325c101(+163) 0x4325c200(+163) 0x4325c100(+164) 0x1881f770(+165) 0x4325c101(+165) 0x4325c200(+165) 0x42884000(-169) 0x1881f770(+170) 0x413e0000(-170) 0x4325c200(+170) 0x1881f770(+171) 0x4325c100(-171) 0x413e4101(-172) 0x4325c200(+172) 0x4325c100(-173) 0x1881f770(-174) 0x1881f770(-175) 0x4325c100(-175) 0x4325c101(+175) 0x1881f770(-176) 0x4325c100(-176) 0x1881f770(+177) 0x1881f770(-178) 0x413e4101(-178) 0x4325c101(-178) 0x1881f770(-180) 0x4325c101(+180) 0x4325c200(+180) 0x1881f770(-181) 0x4325c101(+182) 0x4325c200(+182) 0x1881f770(-183) 0x1881f770(+187) 0x2080303c(-187) 0x4325c200(+187) 0x1881f770(+189) 0x4325c100(-190) 0x4325c101(+192) |
| 0x8d39d91 | `Margining not ready!` | 0xcdb29f | *0x21adc200(-15) *0x21adc400(-56) *0x21adc000(-99) *0x11adc000(-115) *0x42a3c001(-158) *0x42a3c001(-181) 0x1881f770(-25) 0x1881f770(-66) 0x1881f770(-104) 0x1881f770(-120) 0x1881f770(-143) 0x1881f770(-186) |
| 0x8d39da7 | `RunMarginCommand` | 0xcdbb0e | *0x11aac000(-104) *0x11aac000(+113) |
| 0x8d39db8 | `VerifyMarginOffset` | 0xcdbdc9, 0xcdbe5d | *0x21aac000(-187) 0x1881f770(-192) |
| 0x8d39dcb | `Unsupported FOM mode : %d` | 0xcdcf38, 0xcdd6b9, 0x1575c4a | 0x1881f770(+111) 0x43274000(+116) 0x43274000(+150) 0x20801828(-155) 0x1881f770(+175) |
| 0x8d39de6 | `Cannot enable AER` | 0xcdeae9 | *0x232e0000(-80) *0x11a70000(+82) *0x21a70600(+104) *0x21a70000(+137) *0x232e0000(-151) *0x21a70300(+171) 0x1881f770(+77) 0x1881f770(-86) 0x1881f770(+99) 0x1881f770(+132) 0x1881f770(-156) 0x1881f770(+166) |
| 0x8d39df9 | `SetAspmCya on GPU: 0x%x` | 0xcdf83a, 0x1577cfb | *0x2331c300(-31) *0x2331c300(-31) *0x1331c000(+66) *0x1331c000(+66) *0x2331c000(-67) *0x2331c000(-67) *0x1331c000(-103) *0x1331c000(-131) 0x1881f770(-42) 0x1881f770(-42) 0x1881f770(-72) 0x1881f770(-72) |
| 0x8d39e12 | `, BOOTFSM` | 0xcdfa06 | *0x12004000(+179) 0x1881f770(+22) 0x21b94100(+30) 0x21b94000(-78) 0x1881f770(-86) |
| 0x8d39e1c | `(POS=0x%x)` | 0xcdfa37 | *0x12004000(+130) 0x21b94100(-19) 0x1881f770(-27) 0x21b94000(-127) 0x1881f770(-135) |
| 0x8d39e27 | `FSP Debug Regs:` | 0xcdfad2 | *0x12004000(-25) *0x12004000(+160) 0x21b94100(-174) 0x1881f770(-182) |
| 0x8d39e38 | `reg:0x%x value:0x%x` | 0xcdfbfe | *0x12004000(-52) *0x12004000(-140) |
| 0x8d39ed3 | `PciCfgSpace` | 0x3d5769, 0xce28e6, 0xce2a91, 0xce2b41 | 0x18786c40(+4) 0x178a4720(-6) 0x178745a0(+14) 0x18786c40(+19) 0x18786cd0(-39) 0x178745a0(-44) 0x18786cd0(-54) 0x18786c40(+55) 0x18786c00(+63) 0x18786ce0(-69) 0x178745a0(+73) 0x178745a0(-74) 0x18786c00(+78) 0x18786c40(+117) 0x18786bc0(+122) 0x178a47c0(-126) 0x18786ce0(-126) 0x18786ce8(-131) 0x178745a0(+132) 0x18786bc0(+137) 0x178a4800(-150) 0x18786ce8(-173) 0x18786c40(+179) 0x18786b80(+184) |
| 0x8d39ef4 | `CheckCfgSpaceNotReady` | 0x3d5856, 0xce2ac3, 0xce37b2 | 0x18786c40(+4) 0x18786b40(+9) 0x178745a0(+19) 0x18786b40(+24) 0x18786b80(-38) 0x178745a0(-43) 0x18786b80(-53) 0x18786c40(-58) 0x18786c40(+66) 0x18786b00(+71) 0x178745a0(+81) 0x18786b00(+86) 0x18786bc0(-100) 0x178745a0(-105) 0x18786c40(+109) 0x18786bc0(-115) 0x18786ac0(+118) 0x18786c40(-120) 0x178745a0(+149) 0x18786ac0(+154) 0x18786c00(-159) 0x178745a0(-164) 0x18786c00(-174) 0x18786c40(-182) |
| 0x8d39f1c | `CheckCfgSpaceReady` | 0x3d5813, 0xce2b73, 0xce3782 | 0x18786c40(+9) 0x18786b80(+14) 0x178745a0(+24) 0x18786b80(+29) 0x18786bc0(-33) 0x178745a0(-38) 0x18786bc0(-48) 0x18786c40(-53) 0x18786c40(+71) 0x18786b40(+76) 0x178745a0(+86) 0x18786b40(+91) 0x18786c00(-92) 0x178745a0(-97) 0x18786c00(-107) 0x18786c40(-115) 0x18786c40(+133) 0x18786b00(+138) 0x178745a0(+148) 0x18786c40(-151) 0x18786b00(+153) 0x178745a0(-156) 0x18786c40(-166) 0x178a4720(-176) 0x18786c40(+176) 0x18786ac0(+185) |
| 0x8d39f73 | `Test device is not a GPU` | 0xce3ef1, 0xdd7899 | 0x178a47c0(-33) 0x178a4800(+39) |
| 0x8d39f8c | `PciCfgSpace JS Object` | 0x3d5755 | 0x178a4720(+14) 0x18786cd0(-19) 0x178745a0(-24) 0x18786c40(+24) 0x178745a0(+34) 0x18786cd0(-34) 0x18786c40(+39) 0x18786ce0(-49) 0x178745a0(-54) 0x18786c40(+75) 0x18786c00(+83) 0x178745a0(+93) 0x18786c00(+98) 0x18786ce0(-106) 0x18786ce8(-111) 0x18786c40(+137) 0x18786bc0(+142) 0x178745a0(+152) 0x18786ce8(-153) 0x18786bc0(+157) |
| 0x8d39fa2 | `Save the PciCfgSpace data` | 0x3d578f | 0x18786c40(+17) 0x18786c40(-19) 0x178745a0(-24) 0x18786c00(+25) 0x18786c40(-34) 0x178745a0(+35) 0x18786c00(+40) 0x178a4720(-44) 0x18786cd0(-77) 0x18786c40(+79) 0x178745a0(-82) 0x18786bc0(+84) 0x18786cd0(-92) 0x178745a0(+94) 0x18786bc0(+99) 0x18786ce0(-107) 0x178745a0(-112) 0x18786c40(+141) 0x18786b80(+146) 0x178745a0(+156) 0x18786b80(+161) 0x18786ce0(-164) 0x18786ce8(-169) |
| 0x8d39fbc | `Save` | 0x3d579c | 0x18786c40(+4) 0x18786c00(+12) 0x178745a0(+22) 0x18786c00(+27) 0x18786c40(-32) 0x178745a0(-37) 0x18786c40(-47) 0x178a4720(-57) 0x18786c40(+66) 0x18786bc0(+71) 0x178745a0(+81) 0x18786bc0(+86) 0x18786cd0(-90) 0x178745a0(-95) 0x18786cd0(-105) 0x18786ce0(-120) 0x178745a0(-125) 0x18786c40(+128) 0x18786b80(+133) 0x178745a0(+143) 0x18786b80(+148) 0x18786ce0(-177) 0x18786ce8(-182) 0x18786c40(+190) |
| 0x8d39fc1 | `Restore the PciCfgSpace data` | 0x3d57ca | 0x18786c00(-19) 0x18786c40(+20) 0x178745a0(-24) 0x18786bc0(+25) 0x18786c00(-34) 0x178745a0(+35) 0x18786bc0(+40) 0x18786c40(-42) 0x18786c40(-78) 0x18786c40(+82) 0x178745a0(-83) 0x18786b80(+87) 0x18786c40(-93) 0x178745a0(+97) 0x18786b80(+102) 0x178a4720(-103) 0x18786cd0(-136) 0x178745a0(-141) 0x18786c40(+144) 0x18786b40(+149) 0x18786cd0(-151) 0x178745a0(+159) 0x18786b40(+164) 0x18786ce0(-166) 0x178745a0(-171) |
| 0x8d39fde | `Restore` | 0x3d57da | 0x18786c40(+4) 0x18786bc0(+9) 0x178745a0(+19) 0x18786bc0(+24) 0x18786c00(-35) 0x178745a0(-40) 0x18786c00(-50) 0x18786c40(-58) 0x18786c40(+66) 0x18786b80(+71) 0x178745a0(+81) 0x18786b80(+86) 0x18786c40(-94) 0x178745a0(-99) 0x18786c40(-109) 0x178a4720(-119) 0x18786c40(+128) 0x18786b40(+133) 0x178745a0(+143) 0x18786b40(+148) 0x18786cd0(-152) 0x178745a0(-157) 0x18786cd0(-167) 0x18786ce0(-182) 0x178745a0(-187) 0x18786c40(+190) |
| 0x8d39fe6 | `SaveCfgSpaceToFile` | 0x3d5894 | 0x18786c40(+4) 0x18786b00(+9) 0x178745a0(+19) 0x18786b00(+24) 0x18786b40(-38) 0x178745a0(-43) 0x18786c40(+47) 0x18786b40(-53) 0x18786ac0(+56) 0x18786c40(-58) 0x178745a0(+87) 0x18786ac0(+92) 0x18786b80(-100) 0x178745a0(-105) 0x18786b80(-115) 0x18786c40(-120) 0x18786dd0(+142) 0x178745a0(+160) 0x18786bc0(-162) 0x18786dd0(+165) 0x178745a0(-167) 0x18786bc0(-177) 0x18786c40(-182) |
| 0x8d39ff9 | `RestoreCfgSpaceFromFile` | 0x3d58bf | 0x18786c40(+4) 0x18786ac0(+13) 0x18786b00(-19) 0x178745a0(-24) 0x18786b00(-34) 0x18786c40(-39) 0x178745a0(+44) 0x18786ac0(+49) 0x18786b40(-81) 0x178745a0(-86) 0x18786b40(-96) 0x18786dd0(+99) 0x18786c40(-101) 0x178745a0(+117) 0x18786dd0(+122) 0x18786b80(-143) 0x178745a0(-148) 0x18786b80(-158) 0x18786c40(-163) |
| 0x8d3a4d1 | `GPIO notification (%d) added` | 0xceb026 | 0x208f1301(+74) |
| 0x8d3a5f4 | `Unknown C2C ` | 0xcee77c | 0x11684000(-67) 0x1881f770(-72) 0x1168c000(-99) 0x1881f770(-104) |

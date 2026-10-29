# GB202 FsLib / floorsweep 名字 → 真实寄存器地址映射(静态挖掘, MODS 570.215)

日期:2026-09-25
范围:**纯本地只读静态**。未运行 MODS、未访问 GPU / 设备节点 / BAR0 / MMIO / PCI config /
debugfs、未写卡、未刷写、未联网、未做任何出口管制规避;未生成任何可用于刷写的输入。
主工件:`/home/user/mod570_215_static/extracted/home/570.215/mods`
(size `392,897,664` B,SHA-256 `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856`,
ELF64 EXEC 非 PIE x86-64,stripped)。

证据标签:**FACT** = 本次单条指令 / 表行 / 工具输出直接支持;**INFERENCE** = 由 FACT 推出的最窄解释;
**UNKNOWN** = 现有静态材料不能决定;**NEGATIVE** = 明确的有界负结果。

---

## 1. 结论先行(TL;DR)

1. **FACT(核心):不存在 “aperture `0x10xxxxxx` → `0x82xxxx`” 的算术换算。**
   `0x10xxxxxx / 0x20xxxxxx / 0x40xxxxxx` 是 MODS 的 **RegHal ID(不透明键)**,不是地址、
   也不是 aperture 基址。换算链是 **ID → 表行 → (domain, offset[, stride·index]) →
   domain 基址 + offset**。因此任务里 “找 aperture→0x82xxxx 换算规律(可能是表或宏)” 的答案是:
   **是表,而且是 MODS 内嵌的 zlib+delta 编码 RegHal 数据表**。
2. **FACT:表已定位并完整解码。** GB202(`chip = 0xff2`)表头在 **file `0x9043c8f`**
   (VA `0x9443c8f`,位于 `.rodata`):`{chip=0xff2, compressed=29896, uncompressed=562324, rows=20083}`,
   后接 zlib 流;解压后是 9 个 delta 平面的 SoA(4×u32 ID、4×u16 index、4×u32 words)。
   解码器:`/home/user/rt_5090_project/gb202_reghal_offline.py`(既有工具,本构建可用)。
3. **FACT:domain 5 = fuse/PRI 逻辑域,固定选择器 instance-0 fallback = `0x820000`。**
   于是 domain-5 行可换算成真实 BAR0 地址:
   `real = 0x00820000 + offset`(+ `4*index` 对数组寄存器)。
   本次在本工件内部找到了**独立同址验证**:
   - 代码 raw 立即数:`file 0x6d1c40b  mov edx, 0x82381c`、`file 0x6d1c426  mov edx, 0x823820`
     (随后 `call qword ptr [r12+0x1a8]`,即按寄存器号写入的虚调用);
   - 同一 ELF 的 RegHal 表:ID `0x10560000`/`0x10564000` → domain 5, offset `0x381c`;
     ID `0x10568000`/`0x1056c000` → domain 5, offset `0x3820`。
   两条**互不依赖**的机制给出同一地址 `0x82381c/0x823820`,这是 “`0x820000` + offset”
   在本构建里成立的最强内部证据。
4. **FACT(必须修正任务前提):`0x107c4000/0x107c8000 ↔ 0x8212ac` 只对 570.151 成立。**
   本轮把同一个解码器同时跑在 **570.151**(`mods_audit/static/extracted_inner/mods`,SHA-256
   `c30461e2…`)与 **570.215** 上,直接对比得到:

   | 寄存器 / 语义 | 570.151 的 ID → offset | 570.215 的 ID → offset | 是否漂移 |
   |---|---|---|---|
   | `0x008212ac` | `0x107c4000`/`0x107c8000` → `0x12ac` | **`0x107dc000`/`0x107e0000` → `0x12ac`** | **ID 漂移** |
   | `0x00821e78` | `0x107ac000`/`0x107b0000` → `0x1e78` | `0x107c4000`/`0x107c8000` → `0x1e78` | **ID 漂移** |
   | `0x00820d70` | `0x10d6c000`/`0x10d70000` | `0x10d9c000`/`0x10da0000` | **ID 漂移** |
   | `0x008234e0` | `0x1087c000`/`0x10880000` | `0x10894000`/`0x10898000` | **ID 漂移** |
   | `0x00823090` | `0x10894000`/`0x10898000` | `0x108ac000`/`0x108b0000` | **ID 漂移(且旧 ID 改指 0x8234e0)** |
   | `0x00823600`(逐 GPC 数组) | `0x1096c000`/`0x10970000` | `0x10984000`/`0x10988000` | **ID 漂移** |
   | `0x00820040` | `0x104f0000` | `0x104f0000` | 稳定 |
   | `0x008200f8` | `0x105c4000` | `0x105c4000` | 稳定 |
   | `0x00822080` | `0x10360000` | `0x10360000` | 稳定 |
   | `0x0082381c`/`0x00823820` | `0x10560000`/`0x10568000` | 同 | 稳定 |
   | `domain 0` 的 `0x10`/`0x20`(PAC/GPC/TPC 族) | `0x10338000`/`0x10348000` | 同 | 稳定 |

   **结论(修正版):** “aperture → 寄存器” 的绑定**部分稳定、部分按构建重排**,
   尤其 fuse/L2 一族在 570.151→570.215 之间发生了 ID 迁移。因此
   **任何 “aperture 目录” 只有在与具体构建绑定后才能使用**;跨构建引用会静默错位
   (这正是“`0x107c4000 → 0x8212ac`”这个锚点在 570.215 上会指向 `0x821e78` 的原因)。
5. **FACT:FsLib 名字里可闭合到 `0x82xxxx` 的一族已闭合**,典型:
   - `OPT_PES_GPC%u_DIS` → ID `0x10984000` → domain 5 → **`0x00823600 + 4*gpc`**(gpc `0..11`),
     PLM `0x8200dc`;
   - `OPT_CPC_DIS` → `0x106fc000` → **`0x008230e0`**;`OPT_ROP_DIS` → `0x109f4000` → **`0x008230a0`**;
     `OPT_LTC_DIS` → `0x108ac000` → **`0x00823090`**;`OPT_FBPA_DISABLE` → `0x10774000` → **`0x00823084`**;
   - L2/LTC 掩码族:`0x10360000` → **`0x00822080 + 4*i`**(i=`0..15`,L2 slice 软件配置),
     `0x10894000` → **`0x008234e0 + 4*i`**(i=`0..7`,硬 L2 slice disable),
     `0x10d94000` → **`0x00822900 + 4*i`**(i=`0..15`),`0x10d9c000` → **`0x00820d70 + 4*i`**(i=`0..15`),
     `0x10368000` → **`0x00820970 + 4*i`**(i=`0..15`,LTC)。
6. **NEGATIVE(无法闭合并明写):`TPC_GPCx_DISABLE` / `GPC_GFX_DISABLE` / `PAC_DISABLE` /
   `SYSPIPE_GFX_DISABLE` 一族落在 `domain 0`,其基址在本 ELF 里没有可验证常量**
   (offset 只有 `0x10`/`0x20`,不是地址)。它们的真实地址 = `base(domain 0) + offset`,
   `base(domain 0)` 需要 domain→class→selector 或 PTOP DeviceInfo2 记录,本轮**未闭合**。
   详情见 §5。
7. **NEGATIVE:若干 FsLib 名字邻近的 ID 在 GB202 表中根本不存在**
   (`0x10974000` = `OPT_PES_DIS`、`0x10a04000` = `OPT_ROP_L2_DIS`/`fbp_ltc`、
   `0x10c24000`/`0x10a04000` = `OPT_ZCULL_DIS`、`0x10e04000`、`0x10d24000`、`0x10a54000`、
   `0x10df4000`、`0x103a0000`、`0x10388000`、`0x10320000`、`0x10318000`、`0x10398000`、
   `0x10330000`、`0x102e8000`、`0x10d54000`、`0x10d5c000`、`0x1075c000`、`0x104a8000` 等)。
   含义:这些站点在 GB202 上走不到成功读(`0x19c69c0` 返回假,日志串为
   `Invalid register 0x%x%s specified for this GPU` @ `file 0x8d0b0f8`),
   它们属于其它芯片的共享代码,或与名字只是**邻近**而非同一寄存器(见 §7 方法论告警)。
8. **NEGATIVE/中性:`TpcMasks`、`L2SliceMasks`、`IsFloorsweepingValid`、`SetMode`、`SetTimeoutMs`、
   `GpcMask`、`FbpMask` 等不是寄存器名**,而是 FsLib 的 **JS/CLI 接口名与参数名**
   (与 `FsLib interface.` 同簇),引用点里没有 RegHal ID(§3.3、§6)。

---

## 2. 机制与证据链

### 2.1 RegHal 表(名字→地址的唯一转换器)

| 项 | 值 |
|---|---|
| 表头 file offset | `0x9043c8f`(VA `0x9443c8f`,`.rodata`) |
| 头 16 字节 | `f2 0f 00 00 | c8 74 00 00 | 94 94 08 00 | 73 4e 00 00` = `{0xff2, 29896, 562324, 20083}` |
| 载荷 | zlib 流(file `0x9043c9f` 起) |
| 解压后 | 562324 B = 20083 × 28 B,9 平面 delta 编码(4×u32 ID 累积 + 4×u16 index 累积 + 4×u32 word 累积) |
| 行语义 | `reg_id`(u32);`opcode = reg_id>>28`(`1`=read/地址、`2`=field 描述符、`4`=常量描述符);`indices[4]` 为查表索引(`0xfffe`/`0xffff` = 元数据行);`words = (domain, ?, ?, offset)`;opcode 2 时 `words[3] = (msb<<16)\|lsb`,opcode 4 时 `words[3] = 常量值` |

**FACT(解析路径)**:普通读取路径为
`0x19cbe10(obj, index, reg_id, &out)` → `0x19c6a80`(取行、校验,失败打印
`Invalid register 0x%x%s specified for this GPU`,格式串 file `0x8d0b0f8`,附加串 `" (%s)"` file `0x8d7254a`)
→ `0x19caec0`(用行内偏移 + 第二次查表 `0x19c89b0` 做算术:`d[+4] + e[+0] - d[+0]`)
→ 或按调用者的 handler(`[rax+0x18]` 读 / `[rax+0x1a8]` 按号写)。
`0x19c69c0` 是“该 ID 是否为本 GPU 支持”的前置检查(调用者在失败时会跳过该分支或报错)。

### 2.2 domain → 基址

- **FACT:** domain 5 的固定选择器 fallback instance-0 = `0x00820000`
  (既有审计:`fuse_domain_instance.md`、`deviceinfo_class10_identity.md`;公开头把 `0x820000`
  命名为 `NV_FUSE0_PRI_BASE`)。
- **FACT(本构建内部同址校验):** §1.3 的 `0x82381c/0x823820` raw 立即数 ↔ ID 表行同址。
- **UNKNOWN:** domain 5 在真实运行时可能改用 PTOP DeviceInfo2 class `0x10` instance-0 的
  `devicePriBase`(既有审计),那会改变实际数值;本轮未做任何设备读取,故所有地址应标注为
  “固定选择器结果”。

### 2.3 570.215 的 domain-5 锚点表(供后续复核)

下表由本工件解码得到(`BAR0 = 0x820000 + offset`),用于替代 570.151 时代的锚点:

| BAR0 | RegHal ID(570.215) | 备注 |
|---|---|---|
| `0x00820040` | `0x104f0000`, `0x104f4000` | software-fuse latch;PLM `0x8200f8`;常量描述符 `0x404f0001 = 1` |
| `0x008200dc` | `0x1059c000`, `0x105a0000` | L2 OPT access PLM(元数据指向它) |
| `0x008200f8` | `0x105c4000`, `0x105c8000` | override latch |
| `0x008200fc` | `0x109ac000`, `0x109b0000` | 被大量行当作 access PLM |
| `0x008212ac` | **`0x107dc000`, `0x107e0000`** | PLM `0x8200fc`(570.151 中此地址属 `0x107c4000`) |
| `0x00821e78` | **`0x107c4000`, `0x107c8000`** | PLM `0x8200fc` |
| `0x00822080` | `0x10360000`, `0x10364000` | 16 项数组 `+4*i` |
| `0x00822168`/`0x00822170` | `0x10390000`/`0x10394000`, `0x10490000`/`0x10494000` | VBIOS info-table 候选(既有审计) |
| `0x00822900` | `0x10d94000`, `0x10d98000` | 16 项数组 `+4*i` |
| `0x00823090` | `0x108ac000`, `0x108b0000` | 粗粒度 OPT ROP/L2 |
| `0x008234e0` | `0x10894000`, `0x10898000` | 8 项数组 `+4*i`(FBP) |
| `0x00823600` | `0x10984000`, `0x10988000` | 12 项数组 `+4*i`(GPC) |
| `0x0082381c`/`0x00823820` | `0x10560000`/`0x10564000`, `0x10568000`/`0x1056c000` | sm_speed_select 0/1,有 raw 立即数佐证 |
| `0x00820d70` | `0x10d9c000`, `0x10da0000` | 16 项数组 `+4*i` |
| `0x008204dc` | `0x10704000`, `0x10708000` | |

---

## 3. 名字 → (代码引用) → RegHal ID → 候选真实地址

说明:
- “名字 imm 位置” = 该名字字符串 VA 作为 32 位立即数出现的 **file offset**(指令里 `mov esi/edx/ecx/…, <VA>`);
  VA = file + `0x400000`(第一 LOAD)。注意这些立即数常常**不是 4 字节对齐**的,
  做全文件对齐扫描会漏掉(本轮修正过这一点)。
- “邻近 ID” = 同一函数内距名字引用 ±`0x60` 字节的 `mov r32, imm32`;
  Δ = **ID 指令起始 VA − 名字立即数 VA**(负值 = ID 在名字之前);Δ 绝对值越小配对越可信。
  表中 Δ 已用指令边界重算(不是按 4 字节对齐的近似值)。方法学告警见 §7。
- 地址列的 `+4*i` 表示该 ID 是数组寄存器,`i` 是运行时 index(`0x19c69c0`/handler 的 `esi`/`ecx` 参数)。

### 3.1 已闭合到 `0x82xxxx`(domain 5)

| 名字 | 名字 imm 位置 (file) | 邻近 ID(file, Δ) | ID → (domain, offset) | 候选真实地址 | 置信度 |
|---|---|---|---|---|---|
| ` OPT_PES_GPC%u_DIS : 0x%x\n` @`0x8d391dc` | `0xcb8123` | `0x10984000` @`0xcb80f9` (Δ−42) | dom 5, `0x3600+4*i`, i=0..11, PLM `0x8200dc` | **`0x00823600 + 4*gpc`** | 高(FACT) |
| ` OPT_PES_DIS : 0x%x\n` @`0x8d391c7` | `0xcb8173` | `0x10974000` @`0xcb816a` (VA `0x10b816a`,Δ−9) | **表中无 GB202 行** | — (NEGATIVE,见 §5.2) | — |
| ` OPT_CPC_DIS : 0x%x\n` @`0x8d38e74` | `0xc9f067` | `0x106fc000` @`0xc9f056` (Δ−17) | dom 5, `0x30e0` | **`0x008230e0`** | 高 |
| ` OPT_ROP_DIS : 0x%x\n` @`0x8d3903b` | `0xcad3a5` | `0x109f4000` @`0xcad391` (Δ−20) | dom 5, `0x30a0` | **`0x008230a0`** | 高 |
| ` OPT_LTC_DIS : 0x%x\n` @`0x8d3922f` | `0xcbb716` | `0x108ac000` @`0xcbb707` (Δ−15) | dom 5, `0x3090` | **`0x00823090`** | 高 |
| `OPT_FBPA_DISABLE` @`0x8d38f9b` | `0x10f0573` | `0x10774000` @`0x10f0537` (Δ−60) | dom 5, `0x3084` | **`0x00823084`** | 中(Δ 较大) |
| ` fbpl2slice=%u` 打印族 `fbp_l2slice[%u]=0x%x ` @`0x8d39080` | `0xcada24` | `0x10360000` @`0xcad99f` (`mov esi, 0x10360000`,Δ−133;同函数簇内另有 15 处同 ID) | dom 5, `0x2080+4*i`, i=0..15 | **`0x00822080 + 4*slice`** | 中高 |
| `fix L2 slice` 族 `Fixing L2 slice[%d] to 0x%x\n` @`0x8d3901e` | `0xcac6fb` | 同上簇(`0x10360000`) | dom 5, `0x2080+4*i` | **`0x00822080 + 4*slice`** | 中 |
| `Cannot read L2 mask\n` @`0x8d385bf` | `0xcbaaf9` | `0x10d9c000` @`0xcbaae7` (Δ−18) | dom 5, `0xd70+4*i`, i=0..15 | **`0x00820d70 + 4*i`** | 中高 |
| `Cannot read L2 SLICE mask\n` @`0x8d385a4` | `0xc8e191` | 无(±`0x200` 内无 ID) | — | — (UNKNOWN) | — |
| `Cannot read TPC mask\n` @`0x8d385de` | `0xcbd421` | `0x10e2c000` @`0xcbd3ca` (Δ−87) | dom 5, `0xc38+4*i`, i=0..31 | **`0x00820c38 + 4*tpc`** | 中 |
| `Cannot read GPC mask\n` @`0x8d384ed` | `0xcbd8f1` | `0x10d64000` @`0xcbd8b5` (Δ−60) | dom 5, `0xc1c` | **`0x00820c1c`** | 中高 |
| `Cannot read FBP mask\n` @`0x8d384d7` | `0xcb59d1` | `0x10d4c000` @`0xcb5979` (Δ−88) | dom 5, `0xd38` | **`0x00820d38`** | 中 |
| `Cannot read FBIO mask\n` @`0x8d3858d` | `0xcb5b51` | `0x10d3c000` @`0xcb5af9` (Δ−88) | dom 5, `0xc14` | **`0x00820c14`** | 中 |
| `Cannot read PES mask\n` @`0x8d38544` | `0xcb56f1` | `0x10de4000` @`0xcb56b7` (Δ−58) | dom 5, `0x2a78+4*i`, i=0..15 | **`0x00822a78 + 4*i`** | 中 |
| `Cannot read CPC mask\n` @`0x8d3872a` | `0xc94729` | **无**(该名字 ±`0x60` 内没有 ID) | — | —(UNKNOWN) | — |
| (无池内名字,内联构造串) | `0xca1d19` 簇 | `0x10d2c000`(Δ 视站点而定) | dom 5, `0x2a00+4*i`, i=0..15 | `0x00822a00 + 4*i`(名字关联 UNKNOWN) | 低 |
| ` OPT_MCHIP_EN   : 0x%x\n` @`0x8d3929f` | `0xcbd58f` | `0x108b4000` @`0xcbd57b` (Δ−20) | dom 5, `0x204` | **`0x00820204`** | 高 |
| ` OPT_HDCP_EN    : 0x%x\n` @`0x8d392b7` | `0xcbd5b7` | `0x10844000` @`0xcbd5ab` (Δ−12) | dom 5, `0x2fc` | **`0x008202fc`** | 高 |
| ` OPT_GC6_ISLAND : 0x%x\n` @`0x8d392cf` | `0xcbd5df` | `0x10d5c000` @`0xcbd5d3` (Δ−12) | **表中无 GB202 行** | — (NEGATIVE) | — |
| ` OPT_DISPLAY_DIS: 0x%x\n` @`0x8d392e7` | `0xcbd607` | `0x10d34000` @`0xcbd5fb` (Δ−12) | dom 5, `0xc04` | **`0x00820c04`** | 高 |
| ` OPT_NVDEC_DIS  : 0x%x\n` @`0x8d392ff` | `0xcbd62f` | `0x10da4000` @`0xcbd623` (Δ−12) | dom 5, `0xc24` | **`0x00820c24`** | 高 |
| ` OPT_NVENC_DIS  : 0x%x\n` @`0x8d39317` | `0xcbd657` | `0x10dac000` @`0xcbd64b` (Δ−12) | dom 5, `0xd68` | **`0x00820d68`** | 高 |
| ` OPT_ECC_EN     : 0x%x\n` @`0x8d3932f` | `0xcbd67f` | `0x1073c000` @`0xcbd673` (Δ−12) | dom 5, `0x228` | **`0x00820228`** | 高 |
| ` OPT_CE_DIS     : 0x%x\n` @`0x8d39347` | `0xcbd6be` | `0x10d24000` @`0xcbd6ab` (Δ−19) | **表中无 GB202 行** | — (NEGATIVE) | — |
| ` OPT_SEC_DEBUG_EN: 0x%x\n` @`0x8d3935f` | `0xcbd6e6` | `0x10a54000` @`0xcbd6db` (Δ−11) | **表中无 GB202 行** | — (NEGATIVE) | — |
| ` OPT_PRIV_SEC_EN: 0x%x\n` @`0x8d39378` | `0xcbd70e` | `0x10df4000` @`0xcbd703` (Δ−11) | **表中无 GB202 行** | — (NEGATIVE) | — |
| ` OPT_ROP_L2_DIS : 0x%x\n` @`0x8d39217` | `0xcbb648` | `0x10a04000` @`0xcbb632` (Δ−22) | **表中无 GB202 行** | — (NEGATIVE) | — |
| ` OPT_ZCULL_DIS  : 0x%x\n` @`0x8d39244` | `0xcbb67d` | `0x10a04000` @`0xcbb632`(Δ−75)/`0x10c24000` @`0xcbb667`(Δ−22) | **表中无 GB202 行** | — (NEGATIVE) | — |

### 3.2 单位名(`gpc_*` / `fbp*` / `fbio` / `head` / `display` / `spare` / `nvdec` / `nvenc` …)

这些是 FsLib “单元 enable/disable”名字(与 §6 的表同一命名体系),集中在 file `0xcc0xxx` 簇:

| 名字 | 名字 imm 位置 | 邻近 ID(Δ) | (domain, offset) | 候选地址 | 置信度 |
|---|---|---|---|---|---|
| `gpc` | `0xcc0916` | `0x10340000` (Δ−38) | dom 5, `0x81c` | **`0x0082081c`** | 中高 |
| `gpc_tpc` | `0xcb2251` / `0xcc082e` | `0x10348000`(Δ−49;见 §5.1)/ `0x104a0000`(Δ−55) | dom 0 `0x20` / dom 5 `0x838+4*i`(i=0..31) | 未闭合 / **`0x00820838 + 4*tpc`** | 低 / 中 |
| `gpc_cpc` | `0xc99079` | 写侧字段描述符 `0x20bdc000` @`0xc98fbf`(Δ−186)/`0x204a0000`(field[31:0]) | field,无地址 | — | — |
| `gpc_rop` | `0xc99147` | 写侧字段描述符 `0x206fc000` @`0xc9908d`(Δ−186)/`0x202f0000`(field[31:0]) | field,无地址 | — | — |
| `fbp` | `0xcc0dcd` | `0x10328000` (Δ−24) | dom 5, `0x938` | **`0x00820938`** | 中高 |
| `fbp_ltc` | `0xcbb418` / `0xcc0e41` | `0x10a04000`(无行)/ `0x10754000`(Δ−28) | — / dom 5 `0x3014` | — / **`0x00823014`** | — / 中 |
| `fbp_ltc_disable` | `0xcbca81` | `0x10368000` (Δ−31) | dom 5, `0x970+4*i`, i=0..15 | **`0x00820970 + 4*i`** | 中 |
| `fbio` | `0xcc1047` | `0x10310000` (Δ−28) | dom 5, `0x814` | **`0x00820814`** | 中高 |
| `head` | `0xcc0f6e` | `0x10308000` (Δ−33) | dom 5, `0x808` | **`0x00820808`** | 中高 |
| `display` | `0xcc0f1f` | `0x10300000` (Δ−28) | dom 5, `0x804` | **`0x00820804`** | 中高 |
| `spare` | `0xcc0ffd` | `0x10488000` (Δ−28) | dom 5, `0x830` | **`0x00820830`** | 中高 |
| `nvdec` | `0xcc0ed5` | `0x10370000` (Δ−28) | dom 5, `0x824` | **`0x00820824`** | 中高 |
| `nvenc` | `0xcc1125` | `0x10378000` (Δ−28) | dom 5, `0x968` | **`0x00820968`** | 中高 |
| `fbio_shift_override` | `0xcc0e8b` | `0x10320000` (Δ−28) | **表中无 GB202 行** | — (NEGATIVE) | — |
| `fbio_shift` | `0xcc10db` | `0x10318000` (Δ−28) | **表中无 GB202 行** | — (NEGATIVE) | — |
| `pcie_lane` | `0xcc0fb3` | `0x10398000` (Δ−28) | **表中无 GB202 行** | — (NEGATIVE) | — |
| `fbpa` | `0xcc1091` / `0xcc1aa4` | `0x10330000` / `0x1075c000` | **表中无 GB202 行** | — (NEGATIVE) | — |
| `ce` | `0xcc0d7f` | `0x102e8000` (Δ−28) | **表中无 GB202 行** | — (NEGATIVE) | — |
| `gpc_zcull` | `0xcc0bca` | `0x104a8000` (Δ−55) | **表中无 GB202 行** | — (NEGATIVE) | — |
| `gpc_pes_enable/disable` | `0xcb7171` / `0xcb7194` | `0x109ac000`(Δ−90/−81)→ **`0x008200fc`**;常量描述符 `0x409ac200 = 0xf` | dom 5, `0xfc` | 该簇实际写的是 access-PLM/字段位,不是 PES 本体 | 中 |

### 3.3 不是寄存器名的条目(避免误判)

`GpcMask`(`0x9139aa8`)、`TpcMasks`(`0x9139ab0`)、`PesMasks`、`RopMasks`、`FbpMask`、`FbioMasks`、
`FbpaMasks`、`HalfFbpaMasks`、`LtcMasks`(`0x9139b10`)、`L2SliceMasks`(`0x9139b19`)、`pGpcSettings`、
`pFbSettings`、`pErrMsg`、`Mode`、`FsLib`、`SetMode`、`IsFloorsweepingValid`(`0x9139b5f`)、`SetTimeoutMs`、
`MODE_DISABLE/MODE_FUNC_VALID/MODE_PRODUCT`、`CONSTANT: MODE_*`:

- **FACT:** 它们的引用点(`TpcMasks` file `0xccf628`、`L2SliceMasks` file `0xccf969`、
  `IsFloorsweepingValid` file `0x3d35f0`、`FsLib`/`SetMode` file `0x3d35xx` 簇)附近只有
  **JS/CLI 描述表指针**(如 `0x8c6fe90`)与字符串构造(`mov esi/edx, <name>, <name_end>`,
  `call 0x10aff00`),**没有任何 RegHal ID 立即数**。
- **INFERENCE(强):** 它们是 FsLib 的 JS 接口名/参数名(与 `FsLib interface.` 字符串同簇),
  因此**不存在 “名字→寄存器地址” 的直接映射**;其寄存器语义要经真正的 unit 名(§3.2)
  或 `OPT_*` 名(§3.1)才能落到地址。

---

## 4. 数组寄存器(索引语义)汇总

`idx0 = i` 的行按 `offset = base + 4*i` 展开;这正是 FsLib 里 `%u`/`[%d]` 打印循环的落点:

| ID | 项数 | offset 范围 | 真实地址范围(domain 5) | 典型 FsLib 名 |
|---|---|---|---|---|
| `0x10984000`/`0x10988000` | 12 | `0x3600..0x362c` | `0x00823600..0x0082362c` | `OPT_PES_GPC%u_DIS` |
| `0x10d9c000`/`0x10da0000` | 16 | `0x0d70..0x0dac` | `0x00820d70..0x00820dac` | `Cannot read L2 mask` |
| `0x10894000`/`0x10898000` | 8 | `0x34e0..0x34fc` | `0x008234e0..0x008234fc` | 硬 L2 slice disable(FBP) |
| `0x10360000`/`0x10364000` | 16 | `0x2080..0x20bc` | `0x00822080..0x008220bc` | `fbp_l2slice[%u]=0x%x` |
| `0x10d94000`/`0x10d98000` | 16 | `0x2900..0x293c` | `0x00822900..0x0082293c` | 软件 L2 slice 有效掩码 |
| `0x10d2c000` | 16 | `0x2a00..0x2a3c` | `0x00822a00..0x00822a3c` | CPC/GPC 掩码族 |
| `0x10de4000` | 16 | `0x2a78..0x2ab4` | `0x00822a78..0x00822ab4` | `Cannot read PES mask` |
| `0x10e2c000` | 32 | `0x0c38..0x0cb4` | `0x00820c38..0x00820cb4` | `Cannot read TPC mask` |
| `0x104a0000` | 32 | `0x0838..0x08b4` | `0x00820838..0x008208b4` | `gpc_tpc` |
| `0x10368000` | 16 | `0x0970..0x09ac` | `0x00820970..0x008209ac` | `fbp_ltc_disable` |
| `0x10d0c000` | 1 | `0x00ec` | `0x008200ec` | (单点) |

---

## 5. 负结果 / 未闭合(必须明写)

### 5.1 `domain 0` 一族:`TPC_GPCx_DISABLE`、`GPC_GFX_DISABLE`、`PAC_DISABLE`、`SYSPIPE_GFX_DISABLE`

**FACT(表行):**

| ID | opcode/kind | domain | w1 | w2 | offset | 名字引用点(名字 imm file) |
|---|---|---|---|---|---|---|
| `0x10348000` | read | **0** | 0 | 0 和 1(两行) | `0x20` | `TPC_GPCx_DISABLE` `0xcb2235`;`GPC_GFX_DISABLE` `0xc98c77`;`gpc_gfx` `0xc98c8b`;`gpc_tpc` `0xcb2251` |
| `0x10338000` | read | **0** | 0 | 0 和 1 | `0x10` | `PAC_DISABLE` `0xc98aa9`;`fbp_pac` `0xc98abd` |
| `0x10498000` | read | **0** | 0 | 0 和 1 | `0x10` | `SYSPIPE_GFX_DISABLE` `0xc98db0`;`syspipe_gfx` `0xc98dc7`;`syspipe` `0xc99ed7` |

对应代码(例,file `0xcb21f9` 函数):

```asm
010b2220  ba00803410   mov edx, 0x10348000     ; file 0xcb2220
010b2225  31f6         xor esi, esi            ; index = 0
010b2227  4889c7       mov rdi, rax
010b222a  e8e19b9100   call 0x19cbe10          ; RegHal read(obj, 0, id, &out@0x1881f770)
010b222f  baca901309   mov edx, 0x91390ca      ; "TPC_GPCx_DISABLE" 的结尾指针
010b2234  beba901309   mov esi, 0x91390ba      ; "TPC_GPCx_DISABLE"
```

**NEGATIVE / UNKNOWN:** `base(domain 0)` 在 ELF 里**没有**可以静态验证的常量:
- 表行只给 `domain=0` 与极小 offset(`0x10`/`0x20`),offset 不是地址;
- `0x820000` 这个 fallback 只被证实用于 domain 5(fuse class `0x10`);
- domain→class/selector 的分派与其它 domain 的基址来自 PTOP DeviceInfo2 / selector,
  需要设备侧记录或运行时表,本轮静态材料**不能**给出。
- 若把 domain 0 也按 `0x820000` 处理,会得到 `0x00820010`(`PAC_DISABLE`)/`0x00820020`
  (`TPC_GPCx_DISABLE`/`GPC_GFX_DISABLE`)。这一族偏移与 GA100 的 `OPT_GPC_DISABLE = 0x820350`
  同区,数字上“像”fuse 区,**但没有证据**,故只能作为**明确标注的未验证假设(H1)**,
  不能写成结论。

### 5.2 邻近 ID 在 GB202 表中不存在(NEGATIVE)

`0x10974000`(`OPT_PES_DIS`)、`0x10a04000`(`OPT_ROP_L2_DIS`、`fbp_ltc*`、`RopL2`、`Ltc`)、
`0x10c24000`(`OPT_ZCULL_DIS` 第二处)、`0x10e04000`、`0x10d54000`、`0x10d5c000`、`0x10d24000`、
`0x10a54000`、`0x10df4000`、`0x103a0000`、`0x10388000`、`0x10320000`、`0x10318000`、`0x10398000`、
`0x10330000`、`0x102e8000`、`0x104a8000`、`0x1075c000`、`0x20388000`、`0x20974000`、`0x20000000`。

- **FACT:** 这些 ID 在 0xff2 表中 0 行。
- **FACT:** 同一路径的失败日志是 `Invalid register 0x%x%s specified for this GPU`
  (file `0x8d0b0f8`)。
- **INFERENCE:** 它们是“多芯片共享代码”的 ID,或我的邻近启发式把它们与名字配错了
  (见 §7)。任务关心的 `OPT_PES_DIS` 全局寄存器在 GB202 上**没有**可静态闭合的地址;
  代码里实际走的是逐 GPC 数组(`0x10984000`)分支(见 `0x10b7fee..0x10b8185` 的
  `0x19c69c0` 前置判断)。

### 5.3 `disable_sw_override` 家族(与任务锚点直接相关)

- **FACT:** 570.215 表:`0x107c4000`/`0x107c8000` → **`0x821e78`**;`0x107dc000`/`0x107e0000`
  → **`0x8212ac`**;两者 access PLM 都是 `0x8200fc`。
- **FACT:** `0x8212ac` 与 `0x821e78` 在 570.215 的 `.text` 里**都没有** raw 立即数
  (即不会被 `mov $0x82xxxx,%ecx` 直访);`0x107dc000` 在 570.215 `.text` 里也没有立即数;
  `0x107c4000` 只有 2 处(file `0x165b2d5`/`0x165b310`,shadow/对比循环里)。
- **FACT:** 570.151 里存在的 `0x207c4000`、`0x407c4001` 在 570.215 的 `.text` 中不存在
  (`0x407c4000` 仅在 `.rodata`/`.nv_fatbin` 命中)。即 570.151 的“常量描述符比较”写法
  在本构建里被换掉了,**本构件的对应比较点未定位(UNKNOWN)**。
- 结论:任务给出的“已知锚点”不能用于 570.215 的换算,否则会把 `0x821e78` 误标成 `0x8212ac`。

---

## 6. 任务第 (3) 项:表区解析结论

### 6.1 file `0x1749de88` 附近(以及 `0x8ece368`/`0x8ed1638`/`0x8ed5228`)

- **FACT(记录结构):** `.data` 区 `0x1749dd90` 起是 **stride `0x38`** 的记录:
  `{u32 flag(1), u32 value(2), char* name_enable, char* name_disable, …, char* help_text}`;
  `.rodata` 的 `0x8ece338` 一带是同一体系的 `{char* name_a, char* name_b, u32, u32, char* help}`
  记录(name 指针指向字符串池 `0x9138xxx`,help 指针指向 `.rodata` 里的说明文本,
  例如 `0x8c6c580 = "disable TPCs corresponding to a GPC, Usage <gpc Idx>:<tpc mask>"`)。
- **FACT(内容):** 名字对正是 FsLib 的“单元”名:`fbp_pac_enable/disable`、`c2chbi_group_*`、
  `sec_*`、`gpc_*`、`gpc_tpc_*`、`gpc_cpc_*`、`gpc_rop_*`、`gpc_pes_*`、`fbp_ltc_*`、
  `fbp_l2slice_*`、`fbp_rop_l2_*`、`sysltc_*`、`hshub*`、`pcie_*`、`nvlink*`、`half_fbpa_*`、
  `nvdec/nvenc/display/ofa/…`,以及 region 变体(`GPC region enable/disable` 等)。
- **FACT(关键否定):** 这些记录里只有 `u32 1`、`u32 2` 这类**小整数与名字指针**,
  **没有任何 `0x10xxxxxx`/`0x20xxxxxx`/`0x40xxxxxx` 形式的 RegHal ID 立即数**,也没有小
  offset/width 元组。
- **结论:** 它是 **JS/CLI(及 FsLib 单元启用/禁用)参数描述表**,**不是**
  `name → (type,width,offset)` 的寄存器描述符表。任务中“表区 `0x1749de88` 附近 = 名字→描述符表”
  的猜测在本构建**不成立(NEGATIVE)**。

### 6.2 file `0x174a1300` 一带(`stride 0x40`)

- **FACT:** 记录形如 `{u32 reg_id = 0x131fc000, u32 index = 15..0, u64 → 0x92d6ea0 …}`,
  其中被指向的对象是 `{ptr, u32 len = 0x1c(28), 28 字节高熵数据}` —— 形态为“ID+index → 名字/摘要对象”,
  不含真实地址。
- **FACT:** `0x131fc000` 在 GB202 表中是 **domain 0** 的 16 项数组(`offset 0x193c+4*i`,PLM `0x2770`),
  因此它同样落在 §5.1 的未闭合域里。
- **结论:** 该表**不能**作为地址来源(NEGATIVE),但可作为“domain 0 数组存在”的旁证。

### 6.3 线索(未闭合,不作为结论)

`.rodata` file `0x8fb5090` 附近与 `.data` file `0x174bd300` 附近存在**大端 u32** 排布的地址/数据对
(如 `00 82 36 00` = BE `0x00823600`、`00 82 3b 00`、`00 8d 94 00`,以及 `0x00004100`/`0x00004000`
这类值),形态像 fusemap / “地址-数据”表。本轮**未**把它与 §3 的名字表闭合,
**不得**据此推断任何寄存器地址(UNKNOWN)。

---

## 7. 不确定度、方法学告警与如何闭合

1. **运行时基址可覆盖静态 fallback。** domain 5 的真实基址可能是 PTOP DeviceInfo2 class `0x10`
   instance-0 的 `devicePriBase`,而不是 `0x820000`。本报告所有 `0x82xxxx` 都是
   **固定选择器(instance-0 fallback)** 结果;要确认需窄读设备侧记录,本轮未做。
2. **邻近启发式的局限。** 名字↔ID 的配对用 ±`0x60` 字节窗口;同一函数里若存在多个同名引用的
   打印串(例如 `gpc_gfx` 在 `0x1157c69` 与 `0x10988000` 相邻,但语义上更像 shadow 记录循环),
   会产生误配。表中已按 Δ 标注置信度;Δ > `0x40` 的条目按“中/低”处理。
3. **对齐陷阱。** 字符串 VA 常作为**非 4 字节对齐**的立即数出现(例如 `file 0xcb2235` 是对齐余 1);
   只做 4 字节对齐扫描会漏掉一半以上的引用(本轮同时用 4 种相位重扫,池内引用从 1402 修正为 1920 处,
   涉及 432 个不同名字)。引用的 “`0xaperture @0x…`” 位置必须按**文件偏移 + 立即数位置**理解。
4. **ID 跨构建部分稳定、部分迁移(已双构建实证)。** 见 §1.4 的对比表:稳定例
   `0x10338000`/`0x10348000`(domain 0)、`0x10360000`、`0x104f0000`、`0x10560000`;
   迁移例 `0x107c4000`(`0x8212ac`→`0x821e78`)、`0x10894000`(`0x823090`→`0x8234e0`)、
   `0x10d6c000`→`0x10d9c000`(同为 `0x820d70`)、`0x1096c000`→`0x10984000`(同为 `0x823600`)。
   因此“aperture 清单/目录”必须与构建绑定,否则会静默错位。
5. **闭合 domain 0 的最短路径(纯静态可做):** 在 `.text` 中定位 domain→class/selector 的分派
   (即 `fuse_domain_instance.md` 描述的 `vtable+0x218(domain, instance, ctx)` 在本构建中的对应实现)
   以及非 fuse class 的 fallback 表;若其中出现 `{index0 → 0x00820000}` 之外的成对常量,
   即可把 §5.1 的 `0x10/0x20` 落到具体 `0x82xxxx`。
6. **复核命令(只读,无设备访问):**
   ```bash
   python3 /home/user/rt_5090_project/gb202_reghal_offline.py \
     /home/user/mod570_215_static/extracted/home/570.215/mods \
     --id 0x10984000 --id 0x10360000 --id 0x10348000 --id 0x108ac000 \
     --id 0x107c4000 --id 0x107dc000 --include-metadata
   ```
   - 注意 1:该工具内置 `--self-test` 的期望值是 **570.151** 的 ID(如 `0x10d6c000`),
     用在 570.215 上会失败;这不是解码失败——失败信息本身正好给出了 570.215 的新 ID
     (`got [0x10d9c000, 0x10da0000]`),与 §1.4 的跨构建对比一致。
   - 注意 2:同一工具可直接跑在 `mods_audit/static/extracted_inner/mods`(570.151,
     表头 `0x8fd61aa`,19999 行)上,得到 §1.4 左列,用于复核漂移。

---

## 附录 A:关键站点原始字节(便于复核)

| file offset | 字节 | 反汇编(VA) | 说明 |
|---|---|---|---|
| `0xcb2220` | `ba 00 80 34 10` | `010b2220 mov edx, 0x10348000` | `TPC_GPCx_DISABLE` 读取(domain 0) |
| `0xcb2235` | `ba 90 13 09`(`be` 在 `0xcb2234`) | `010b2234 mov esi, 0x91390ba` | 名字立即数位置(非对齐) |
| `0xcb80f9` | `ba 00 40 98 10` | `010b80f9 mov edx, 0x10984000` | 逐 GPC PES disable 读(循环内) |
| `0xcb8123` | `be dc 91 13 09` | `010b8122 mov esi, 0x91391dc` | ` OPT_PES_GPC%u_DIS : 0x%x` |
| `0xcb816a` | `ba 00 40 97 10` | `010b816a mov edx, 0x10974000` | `OPT_PES_DIS`(GB202 表内不存在) |
| `0x6d1c40b` | `ba 1c 38 82 00` | `0711c40b mov edx, 0x82381c` | raw 寄存器号(raw 与 ID 同址佐证) |
| `0x6d1c426` | `ba 20 38 82 00` | `0711c426 mov edx, 0x823820` | 同上 |
| `0x9043c8f` | `f2 0f 00 00 c8 74 00 00 94 94 08 00 73 4e 00 00` | — | RegHal GB202 表头 |

## 附录 B:本轮使用的名称池(只读导出)

- 名字池 file `0x8d38000..0x8d3a600`(VA `0x9138000..0x913a600`),既有导出:
  `parallel/gb202_fslib_strings_20260925.txt`。
- 名字↔ID 邻近全表(410 条,其中 |Δ|≤`0x60` 有 130 条)由本轮扫描生成;
  相关中间产物留在 `/tmp/fslib/`(`name_id_scan.txt`、`adjacency.txt`、`key_arrays.txt`、
  `aperture_sites.txt`),均为只读分析输出,不属于任何设备侧操作。

## 附录 C:合规声明

本轮全程只读取本地文件,未执行 MODS,未打开 `/dev/mem`、`/dev/nvidia*`、sysfs resource
或任何设备节点,未做任何 MMIO 读/写、未加载模块、未刷写、未联网、未尝试绕过任何许可或
出口管制机制。报告内容为静态地址定位结论,**不构成**刷写、绕过或解锁方案。

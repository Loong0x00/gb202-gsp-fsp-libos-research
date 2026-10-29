# GB202 寄存器定位 (MODS 570.215 + 610 GSP) — 2026-09-25

范围:本地只读静态。未运行 MODS、未访问 GPU/BAR0/MMIO、未刷写、未联网。
主工件:`/home/user/mod570_215_static/extracted/home/570.215/mods`
(SHA256 见 `mod570_215_static/STATIC_AUDIT_20260811.md`)

## 1. 正面:PLM / latch / speed-select 一组与 GA100 同偏移

### 1.1 授权门控 + latch 序列(函数入口 0x69d66f0,返回到 0x69d6814)

```asm
69d6728: mov $0x8200f8,%ecx       ; 读 0x8200f8
69d673e: mov $0x82013c,%ecx       ; 读 0x82013c
69d674b: shr $0x4,%ebx  / 69d674e: and $0x1,%ebx    ; bit4 of 0x8200f8
69d6751: and $0xffff,%eax                            ; low16 of 0x82013c
69d6759: or  %dl,%bl
69d675b: je  0x69d67e8            ; 两个都为 0 → 错误分支,返回 0xffff (日志 level 4, line 0x127)
69d6761: test %eax,%eax ; jne 0x69d67c0   ; 0x82013c 低 16 位非 0 → 只记日志(line 0x12e)后返回 0
69d6768: mov $0x820040,%ecx ; 读
69d6783: or  $0x1,%eax      ; set bit0
69d678e: call <wr32>        ; 写回 0x820040 = old|1   ← 拉 latch
69d6796: mov $0x1,%r8d ; 69d679e: mov $0x82013c,%ecx ; 69d67a8: call <wr32>  ; 写 0x82013c = 1
69d67ad: xor %eax,%eax ; ret                        ; 返回 0 (成功)
```

语义:MODS 把 **0x8200f8.bit4** 与 **0x82013c[15:0]** 当作前置授权灯;若 0x82013c 尚未置位,
就执行「读 0x820040 → OR 1 → 写回」的 latch,再写 0x82013c=1。**这是工具侧认可的完整序列**,
可直接作为差分实验的骨架(注意先后顺序:latch 先,0x82013c 后)。

### 1.2 SM speed-select 写入口(函数 0x6d1c3f0)

```asm
6d1c40b: mov $0x82381c,%edx ; call *0x1a8(%r12)   ; sm_speed_select_0 ← 调用方给的 u32
6d1c426: mov $0x823820,%edx ; jmp  *%rax           ; sm_speed_select_1
```

即 MODS 有**直接可调用的 0x82381c/0x823820 写路径**(与 cmpunlocker 在 GA100 上补的那两个寄存器一致)。

### 1.3 0x8200fc 作为 PLM 参与寄存器号分派(0x78d4040 / 0x78d4068)

```asm
78d4040: cmp $0x8204dc,%esi      ; 入参寄存器号先与 0x8204dc 比较
78d406e: mov $0x8200fc,%r9d      ; 并把 0x8200fc 作为 PLM 参数下传
```

### 1.4 新增(此前清单里没有)的两个寄存器

- **0x82013c** —— 可能为"latch 已发出/请求已登记"的状态位(低 16 位被检查)。
- **0x8204dc** —— 被当作寄存器号参与比较,位置紧邻 GA100 的 `OPT_PCIE_DEVIDA(0x8204d8)` 家族。

## 2. 正面(大件):FsLib(floorsweep 库)名字池整段可读

- 文件偏移 `0x8d38000..0x8d3a600`(VA `0x9138000..0x913a600`)是一整段可打印名字池。
- 已导出:**`parallel/gb202_fslib_strings_20260925.txt`**(逐行 `file_off  string`)。
- 关键命名族(节选):
  - 单元族:`gpc_enable/disable`、`gpc_tpc_*`、`gpc_pes_*`、`gpc_rop_*`、`gpc_cpc_*`、`gpc_zcull_*`、
    `fbp_enable/disable`、`fbp_ltc_*`、**`fbp_l2slice_enable/disable`**、`fbp_pac_*`、`fbp_rop_l2_*`、
    `syspipe_*`、`ofa_*`、`nvjpg_*`、`nvdec_*`、`nvenc_*`、`display_*`、`half_fbpa_*`、`hbm_*`、
    `pcie_lane_*`、`spare_*`、`c2c_*`、`nvlink_*`、`nvlc_perlink_*`、`hshub*`、`sysltc_*`、`rhxb_*`、`oobhub_*`、`fsp_*`、`pmu_*`、`gsp_*`
  - 打印/寄存器名字串:`OPT_TPC_DISABLE`、`OPT_PES_DISABLE`、`OPT_PES_GPC%u_DIS : 0x%x`、
    `OPT_GPC_DISABLE`、`OPT_FBP_DISABLE`、`OPT_FBPA_DISABLE`、`OPT_FBIO_DISABLE`、`OPT_LTC_DISABLE`、
    `OPT_ROP_DISABLE`、**`OPT_L2SLICE_DISABLE`**、**`TPC_GPCx_DISABLE`**、`OPT_ROP_L2_DIS`、`OPT_ZCULL_DIS`、
    `OPT_CPC_DISABLE`、`OPT_SYS_PIPE_DISABLE`、`OPT_PERLINK_DISABLE`、`OPT_C2C_DISABLE`、
    `OPT_MCHIP_EN/HDCP_EN/GC6_ISLAND/DISPLAY_DIS/NVDEC_DIS/NVENC_DIS/ECC_EN/CE_DIS/SEC_DEBUG_EN/PRIV_SEC_EN`
  - 掩码访问器:`gpc_mask`、`fb_mask`、`fbio_mask`、`gpctpc[%d]_mask`、`gpcPes[%d]_mask`、`gpcRop[%d]_mask`、
    `gpcCpc[%d]_mask`、`gpczcull[%d]_mask`、`fbpLtc[%d]_mask`、`fbpL2Slice[%d]_mask`、`fbpPac[%d]_mask`、
    `nvlink_link_mask`、`c2c_mask`、`c2cMisc_mask`
  - FsLib 接口结构:`GpcMask`、`TpcMasks`、`PesMasks`、`RopMasks`、`FbpMask`、`FbioMasks`、`FbpaMasks`、
    `HalfFbpaMasks`、`LtcMasks`、**`L2SliceMasks`**、`pGpcSettings`、`pFbSettings`、`SetMode`、
    `IsFloorsweepingValid`、`SetTimeoutMs`、`MODE_DISABLE/MODE_FUNC_VALID/MODE_PRODUCT`
  - 计划/修复参数:`sweep.json`、`/sweep.json`、`"name" : "Final"`、`skyline = [`、`mustEnableList`、
    `mustDisableList`、`minEnableCount/repairMinCount/repairMaxCount`、`Group Settings per unit`、
    `FsLib returned %s`、`SkipFsPlmCheck`、`SkipFspFs`、`UseBootResetForFs`、`PriRingPollTimeoutMs`、
    `DisableCeInterrupts`、`FS IFR Records:`、`[0x%08x] = 0x%08x`、
    `Fixing FB mask to 0x%x`、`Fixing L2 Mask [%d] to 0x%x`、`Fixing L2 slice[%d] to 0x%x`、`Adjusting GPC mask to 0x%x`
- 结论:GB202 的 floorsweep 是 **JSON 驱动(`sweep.json`)的 FsLib**,名字与掩码通道齐全;
  需要的外部 fuse 描述符(`gb202_f.json`)本地缺失(见 `gb202_fuse_descriptor_inventory.md`),
  但**名字池+写入点都在 ELF 里**,可逐个定位。

## 3. 代码引用点(名字 → 现场)

| 名字 | 引用文件偏移 |
|---|---|
| `TPC_GPCx_DISABLE` | `0xcb2235`(附近出现 aperture `0x10348000`) |
| `OPT_PES_GPC%u_DIS : 0x%x` | `0xcb8123`(循环逐 GPC 打印;附近 aperture **`0x10984000`**,另一处 **`0x10974000`**) |
| `OPT_L2SLICE_DISABLE` | `0xcaf4ff`、`0x1b0f142`、`0x1b4893e`、`0x1b65xxx` 簇(疑为名字→信息表) |
| `gpc_tpc_disable` | `0xcc4bcc` 以及表区 `0x8ece368`/`0x8ed1638`/`0x8ed5228`、`0x1749de88…` |
| `IsFloorsweepingValid` | `0x3d35f0` |
| `TpcMasks` / `L2SliceMasks` | `0xccf628` / `0xccf969` |
| `FsLib returned %s` | `0xccf320`、`0xcd01c8` |

注:`0x10xxxxxx` 是 MODS 的 aperture 空间(已知 `0x107c4000/0x107c8000 → 0x8212ac`),
所以 `0x10348000 / 0x10974000 / 0x10984000` 是**下一步换算到 0x82xxxx 的真实跳板**。

## 4. 负结果(同样重要)

- `0x820350`、`0x820368` 在 MODS 570.215 中**不存在**(即 GA100 的 OPT_GPC_DISABLE /
  OPT_FBPA_DISABLE 偏移未直接沿用);`0x820364` 仅 1 处且落在 `.debug_str`(DWARF)里,非代码。
- `0x8234e0` 在 MODS/GSP 中均**无立即数** → 该 raw mask 由 base+index 计算或来自描述符。
- **方法论警告**:对 GSP ELF 做 u32 区间扫描会把 RISC-V `AUIPC`(`0x…97`)指令当成地址;
  `0x0082x097` 之类规整族是噪声。定位必须用「指令级成对匹配(x86 `mov imm32` / RISC-V `lui+addi`)」或「指针表 xref」。

## 5. 下一步(纯静态)

1. 由 `0xcb8123` / `0xcb2235` 两处往上游追**写入点**,把 `0x10348000 / 0x10974000 / 0x10984000`
   经 aperture 表换算成 0x82xxxx 真实地址(TPC / PES / ROP / L2SLICE 各族)。
2. 解析 `0x1749de88` 那片表(8 字节名字指针 + 小整数),它像是 name→(type,width) 的 fuse 标签表。
3. 复用 1.1 的序列做多镜像差分(ASUS stock / Lightning 800W / Matrix):读
   `0x8200f8`、`0x82013c`、`0x820040`、`0x8200dc`、`0x8234e0+4*FBP`、`0x822900+4*FBP`、
   以及新定位的 TPC/PES 族地址,只在**窄读**下进行(WPR2 禁区规则不变)。

## 6. 追加:PES 族的 aperture 已在代码里闭合(2026-09-25 二轮)

在 MODS 570.215 中找到两个**逐 GPC / 全局**读取点,并直接对应 FsLib 名字池里的两条格式串:

| 代码偏移 | aperture | 邻近格式串 | 语义 |
|---|---|---|---|
| `0xcb80f9`(循环体内,`add $1,%ebp` 逐 GPC) | **`0x10984000`** | `0x91391dc` = `OPT_PES_GPC%u_DIS : 0x%x` | **每 GPC 的 PES disable(带 index)** |
| `0xcb816a`(单次) | **`0x10974000`** | `0x91391c7` = `OPT_PES_DIS : 0x%x` | **全局 PES disable** |

读取调用形如 `call *(vtable)`(rdi=对象, esi=0, edx=aperture, rcx=指向 index 结构的指针),
说明 aperture + index 就是 MODS 访问该族熔丝的方式(即 GA100 `FUSE_CTRL_OPT_TPC_GPC(i)` 的 GB202 对应物)。

TCG/GPC 侧的相邻 aperture(**带内联构造的 `gpc_tpc_*` / `fbp_l*` 名字**):

| 代码偏移 | aperture |
|---|---|
| `0xc87775`、`0xc98a99` | `0x10338000` |
| `0xc87a7e`、`0xc98c67` | `0x10348000` |

同时目录化了全部对齐 aperture 站点:**`parallel/GB202_APERTURE_SITES_20260925.txt`**
(765 个 `mov edx, 0x10xxxxxx` 站点,去重 277 条,含 offset / aperture / 邻近名字)。

已知锚点(用于换算校验):`0x107c4000` 与 `0x107c8000` → 同一 `0x8212ac`。
下一步:由 `0xcb80f9` / `0xcb816a` 的 vtable 索引反查 aperture→0x82xxxx 的换算表,
再把 `0x10338000 / 0x10348000` 落到具体 TPC/GPC disable 的 0x82xxxx 地址。

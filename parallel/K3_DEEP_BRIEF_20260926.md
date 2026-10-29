# 给 K3 的深度分析简报:ASUS Astral RTX 5090(GB202)资源解锁 / 特权提升

你是被派来做**深度静态分析**的。目标不是复述已知结论,而是**找出我们还没想到的角度**,或在已关闭的路径里找出**我们推理中的漏洞**。
**不限时间、不限输出长度。** 尽可能深。

---

## 0. 任务与规则(先读这一节,规则是硬约束)

### 最终目标(按优先级)
1. **解锁被熔丝屏蔽的资源**:这张卡实测 `L2 = 96 MB`(GB202 die 物理 128 MB,缺 **32 MB**);`SM = 170`(die 192,缺 **22**)。目标是找到**任何**能把它拿回来的路径(硬件寄存器写 / 固件路径 / 管理处理器 / 驱动侧配置 / 其它)。
2. 若 1 不可达:找到 **GSP/FSP/SEC2/PMU 等管理处理器上的内存破坏型漏洞**(不是卡死型),从而在**设备侧安全上下文**里获得任意读/写,再看是否能越过 1 的那道门。
3. 任何**新的**、真实的、可验证的能力(信息泄露、控制流、绕过某道校验),都有价值。

### 硬规则
- **只做静态分析**。你可以读文件、跑脚本、写分析(run: read + bash)。
- **需要动态运行 GPU 的任何实验**(寄存器读写、驱动重载、设备复位、跑 CUDA、跑内核模块),**不要自己尝试** —— 调用 `request_parent` 把:
  1. **你要验证的假设**、
  2. **精确的操作序列**(命令级,含要读/写的地址与值)、
  3. **预期结果与判据**(看到什么算证实、什么算否定)、
  4. **风险和失败后果(设备可能卡死/需要断电)**、
  5. **这个实验能区分哪两种可能** ——
  一起发给父 agent。**父 agent 会在真机上执行,并把原始输出回给你,然后你继续分析。**
  批量化你的请求:一次 `request_parent` 尽量带上多个实验(按优先级排序),不要一问一停。
- **禁止**在这些实验里写熔丝/BIOS:不得写 `0x820078/0x82007c/0x820080/0x820084`、不得写 FSP PRC 对象 `0x03`、不得做 InfoROM/EEPROM/CCC 写、不得刷 BIOS。写任何寄存器**必须先读回原值**。
- 卡不能永久损坏。Xid / 卡死 / 需要断电重启都可以接受(父 agent 有权限处理)。
- **不要**写安全报告、不要联系厂商、不要外发。

### 交付物
1. **完整报告写到文件**:`/home/user/rt_5090_project/parallel/K3_DEEP_20260926.md`
   —— 不限长度,但要求:**每个断言都标出证据来源(文件:行号 / 实测记录 / 或明确标注"推测")**。
   把 **已确证 / 已排除 / 尚未验证** 三类严格分开。用户极其反感把推测写成结论、以及数字前后不一致。
2. 返回给父 agent 的摘要里,给出:**(a)** 你认为最值得做的 5~10 个动态实验(按期望值排序,每个附命令级步骤与判据);**(b)** 你发现的最重要的 3 个新角度;**(c)** 你对已有结论中**最可能出错**的 3 条的质疑。

---

## 1. 环境与硬件事实

| 项 | 值 | 证据 |
|---|---|---|
| 卡 | ASUS Astral RTX 5090 (GB202), PCI `10de:2b85` | 本机 `lspci` |
| 主机 | `/home/user`,root 可用(`sudo`),BDF `0000:01:00.0` | |
| BAR0 | `0xd8000000`,64 MB(寄存器窗口) | |
| BAR1 | 显存 32 GB | |
| 实测 L2 | `cudaDeviceGetAttribute(l2CacheSize) = 100663296 B = 96 MB` | `/home/user/l2knee/l2attr` |
| 实测 SM | 170 | 同上 |
| 实测 buswidth | 512 bit | 同上 |
| 实测 persistingL2 上限 | 60 MB | 同上(这个 60 MB 的来历未知,别乱解释) |
| 权威口径 | GB202 die = **128 MB L2**;RTX 5090 = 96 MB(缺 32);RTX PRO 6000 = 128 MB 全开;SM 192→170;NVENC/NVDEC 4/4→3/2 | 芯片显微照片/多家媒体(已网络核实) |
| 点灯/防砖措施 | 显示器当前接**独显 DP**;音箱接独显 HDMI;显示器还有一条 HDMI 接**核显** | 用户口述 |

**关键事实**:RSI 与所有既有尝试都表明,这张零售卡的 32 MB L2 与 22 SM **是熔丝/配置层面被屏蔽的**(不是"根本没做进去")。

---

## 2. 已确证的事实(可直接作为前提)

### 2.1 固件与启动链
- **ROM 里没有任何 FWSEC 微码表**(0 命中,跨 ROM/BIT 链/.nvfw/GSP/FMC/bootloader/Dell 100 MB bin)。
- 启动链:FMC → COT 校验,**SHA-384 + ECDSA P-384,prod 公钥 `af870e5d…` 硬钉住**。
- **所有 VBIOS 镜像都是加密的**(36 个样本,descriptor dword `bit2=1`);密文性质:16 字节整数倍、熵 7.999、非 ECB(无重复块)、无密钥流重用、**确定性**(同一版本跨厂商字节一致)。
- 容器格式源码级确认(`kernel_gsp_fwsec.c`):BIT id `0xB8FF` + `"BIT\0"`,token `{id, ver, size:u16, ofs:u16}` 相对 expansion ROM;FALCON_DATA token `0x70`;descriptor dword = `bit0 ver-valid | bit2 ENCRYPTED | bits15:8 ver | bits31:16 size`;FWSEC app id `0x05/0x45/0x85`;V3 签名含 `BCRT30_RSA3K_SIG_SIZE=384`。
- **驱动里没有任何密钥/IV/AES 代码** ⇒ **host 从不解密**;解密只发生在设备侧。
- GSP 明文固件里出现 `AES0/AES1 engine`、`AES-GCM`、`kslot`、`ENCRYPT_IV_CTR_OVERFLOW`、`RmDisableFwseclic`、`RMExecuteFwsecOnSec2`。
- **FSP 验证 gfw 镜像、dyn 镜像被执行、但 dyn 不被 COT 覆盖** ⇒ 设备侧整镜像校验失败 ⇒ `Fatal GSP-FMC Error: code=0xaff` ⇒ `RmInitAdapter failed! (0x62:0x55:2119)`。这是**唯一一次**我们让链上校验拦住的记录(线索:验证发生在设备侧 FSP)。
- FSP 镜像自身也是加密的(flags 0x0d,熵 7.999)⇒ **FSP 的接收端代码只以密文存在** ⇒ 静态分析 FSP 内部逻辑不可能(这是关键限制,别浪费时间找 FSP 明文)。

### 2.2 我们已有的 GSP 域内任意读/写(已在真机验证)
通过修补 `nvidia.ko` 里 GSP 消息接收路径的一个长度校验缺陷,我们**已经**证明:
- **控制流劫持**:`recv` 的 `rxrefresh` 调用点 `+0xb8` → `c.jalr a5 @0x1004c9c`,`sepc=stval=0xdeadbeee`(崩溃证据即证明)。
- **任意写**:`0x1b52246 = c.sw a4,0(a1)`,其中 `a1 = *(msgMetadata+0x38)`(目标地址)、`a4 = *(msgMetadata+0xc0)`(值)。金丝雀测试:写 `0xDEAD0041` 到 `0x418ff68` 成功。
- **任意读**:`0x1020a30 = ld a5,0x168(a1); c.mv a0,s3; c.jalr a5`,通过崩溃时的 `sepc/stval` 泄露。注意 `ld` 需要 8 字节对齐。
- 布局:RX staging `[P, P+0x10000)`,TX staging `[P+0x10000, P+0x20000)`,msgqMetadata `[P+0x20000, P+0x200e8)`;环 64 槽 ⇒ 单次约 192 KB 载荷上限。
- 工具:`/home/user/rpc_ovf_patch_v11.py`(参数 `<src> <K> <CK> <FN> [PAT] [SPARSE] [MAP] [HEX]`)、`/home/user/unpatch_xdig.py`、`/home/user/run8.sh`。
- **重要否定结论**:在拿到任意写之后,我们**没法**通过它改变 floorsweep 家族寄存器:
  实测 `run8.sh 33 0 73 0 "" "0x100a4:0x01,0x100b8:0x1b52246,0x10038:0x08A200D0,0x100c0:0xfffffbff"`
  ⇒ gadget 干净执行(`GSP Timeout`,无 trap)但 **`0x8200d0/0xdc/0xf8` 不变(0xfffffb8f)** ⇒ 写被丢弃。
  证据:`/home/user/rt_5090_project/guest_dmesg_regwrite4_1052.txt`(含 Xid 119)。
  ⇒ **推论:该寄存器族在 GSP 域内也不可写(不是权限问题,是"根本不接受")**。这一点若能找出**反例**,价值极高。

### 2.3 L2 / SM 屏蔽的控制面(项目静态分析已点名)
- PLM(硬件级):`0x8200d0` `plm_floorsweep_0`、`0x8200dc` `plm_l2_raw_sw`、`0x8200f8` `plm_latch`、`0x8200e0/0x8200f4 = 0x00800b8f`、`0x8200fc = 0x80842bcf`。
- latch 请求 `0x820040.bit0`;reset 耦合 `0x820434`;`0x8212ac`(`disable_sw_override`,冷态 = 1)。
- 掩码:`raw 0x8234e0+4i`(8 个 FBP,**全部 = `0x12`**)、`eff 0x822900+4i`(同样 `0x12`)、`sw 0x822080+4i`(全 0)、fuse `0x824140+4i`。
- 七月记录(`GB202_PARALLEL_WORK.md`,标注 REPORT-ONLY + conditional):8 个 FBP 上 enable/disable 图案一致,软件掩码为 0,**记账模型 = 16 个被禁的 2 MiB 单元(32 MiB)**。
- **未知**:raw bit 与物理 MiB 的映射未证(`l2_mask_granularity.md` 明确说"控制坐标是 FBPn.raw_bitb,物理容量映射未证");`0x12` 的极性(1=启用还是禁用)未证。
- **已排除的写入路径**(每一条都实测过,全部丢弃/不保持):宿主 BAR0 写、RM 官方 API(`EXEC_REG_OPS`)、GSP 域内任意写、以及 **FSP task2 把 PLM 打开到 L0–L3 之后**的宿主写。
  - task2 效果可复现:走 **MNOC port 1** 发 `C0000001/1310de7e/0201000000000000`,error 0,`0x8200d0/dc` 从 `0xfffffb8f` → `0xfffffbff`(但 `f8` 不变、`0x8212ac` 仍为 1、掩码仍 `0x12`)。
- **RM registry knob 矩阵(2026-09-26 实测,用 l2CacheSize 判定)全部为负**:
  | knob | L2 | SM | 设备 |
  |---|---|---|---|
  | 基线 | 96 MB | 170 | 正常 |
  | `RmDevinitBySecureBoot=0;EnableRmTestOnlyCode=1` | 0 | 0 | 初始化失败 |
  | `RmDisableFwseclic=1` | 96 MB | 170 | 正常 |
  | 上面组合 | 0 | 0 | 初始化失败 |
  | `RMExecuteDevinitOnPmu=1` | 96 MB | 170 | 正常 |
  | `RMExecuteFwsecOnSec2=1` | 96 MB | 170 | 正常 |
- 唯一已知能写这些的写入者:**NVIDIA MODS / direct-shadow `SetSwFuses` 熔丝通路**(项目审计里还提到 `SecurityUnlockLevel > 3` 的门)⇒ 属于熔丝写,禁止。

### 2.4 FSP(设备侧管理处理器)协议面
- 接口 MNOC:**port 0/1 健康,port 2/3 返回 `0xBADF5720` 特权毒值**;task2 必须走 **port 1**。
- EMEM 配方已跑通:`EMEMC=0x8f2ac0+8i`、`EMEMD=0x8f2ac4+8i`、`QUEUE_HEAD/TAIL=0x8f2c00/04+8i`、`MSGQ_HEAD/TAIL=0x8f2c80/84+8i`,1024 B,AINCW bit24 / AINCR bit25。
- CAPS 报支持的服务:`0x13 PRC, 0x14 COT, 0x15 RESPONSE, 0x16 CAPS, 0x17 INFOROM, 0x18 SMBPBI, 0x1A ROMREAD, 0x1C UEFI_RM, 0x1D UEFI_XTL, 0x20 CLOCK_BOOST`;**RESET/HULK/FIRMWARE_UPDATE 不支持**。
- `(task,sub,payload)` 空间已被穷举:只有 `(2,1)`/`(3,1)` 被接受;全 `0xFF` 载荷 ⇒ `0x3A5`;单字节载荷被接受但**寄存器窗口零变化**(⇒ 没有任何 task 会打开 `f8` 或清 `0x8212ac`)。
- MCTP 分片:**SOM/EOM/SEQ/version 位被忽略**;≤7 字节消息静默丢弃且**无重组状态**;**DEID 必须为 0**。
- 长度信任:**已否定** —— 用 `0xDEADBEEF` 预填测试,FSP 读声明长度但只在自己通道内;超声明(1027/4099 dword)被拒/截断,无覆盖、无泄露。
- PRC 对象/旋钮空间(12 字节协议:`MCTP | NVDM 0x13 | prcObjType | numBytes | knobId:u16`;读 `0x0c` / 写 `0x0d`;成功 = error 0 + 22 字节回复含 2 字节值):
  - **44 个对象可读**(`0xHH00` 系列);**14 个可写**(`0x02,0x03,0x06,0x08,0x0a,0x19,0x20,0x22,0x24,0x25,0x26,0x27,0x28,0x2a`);
  - 另有 `0x00LL` 系列可读(值全 `0x0001`);错误码 `0x1E3`(无此对象)/`0x1E4`/`0x1E5`(拒绝写);
  - 驱动只用一个具名旋钮 `0x002D`(PPCIE),**本卡不存在**(返回 `0x1E3`),驱动容忍;
  - **★ 事故**:批量写这 14 个对象把卡打进了"要求机密计算"状态(`confComputeConstructEngine_IMPL: CPU does not support confidential compute` + `Assertion failed: 0 @ conf_compute.c:163` + `osInitNvMapping: *** Cannot attach gpu` ⇒ `RmInitAdapter failed! (0x22:0x38:894)`)。**热重启无效,只有整机断电才恢复** ⇒ 该状态是 FSP 易失运行时状态。
  - 已恢复 13/14;对象 `0x03`(原值 `0x0001`)是**单向闩锁**(清 0 可以,再写回 1 被拒 `0x1E4`),留在 0 无害。
- 会话实测:FSP `0xAD00BC == 0xFF` 表示 FWSEC 完成(PBUS `SW_SCRATCH 0x1400+4i` 分别对应 FWSEC 版本 / Devinit Boot Status / FRTS 完成 / **COT 轮询状态**)。
- **SMBPBI(0x18)会把整个 FSP 邮箱卡死**(所有端口失效,直到设备复位)—— 疑似 bug,值得挖。
- **UEFI_RM(0x1C)/ UEFI_XTL(0x1D)从未被真正调用过** —— 未开发区。

### 2.5 SEC2
- EMEM 配方:`EMEMC=0x840AC0`、`EMEMD=0x840AC4`、`QUEUE_HEAD/TAIL=0x840C00/04`、`MSGQ_HEAD/TAIL=0x840C80/84`(绝对基址,另一组 `0x842ac0/0x842c00` 是 `0xBADF5040` 特权毒值)。
- **host→SEC2 唯一已知消息 = COT(0x14)**;ksec2 EMEM HAL 在 GB202 上是**桩**(chipHal 65 vs 70/71)。
- `0x840100` = Falcon **CPUCTL,bit4 = HALTED**(0x10 ⇒ 已停机);
- **QUEUE_TAIL 语义 = 字节偏移**(`align_up(bytes,4)-4`,驱动三处代码印证;20 字节回复 ↔ 固件 `MSGQ_TAIL=0x10`),我们早期工具用 `len/4-1` 和 `(tail-head)+1`,**4 倍偏差但被 FSP 容忍**(未解之谜)。
- 只读大体安全(PANY 跑过 5630 轮 × 18 寄存器,零 Xid/SEC_FAULT),但**读 `0x840AC4`(EMEMD)会推进游标**;11 个"读安全/写致命"寄存器已列出;SEC2 块仅在驱动绑定时非零 ⇒ 该图案 = "PSEC 域有电",不是"固件在跑"。
- 结论:不可发送,仅只读观测。

### 2.6 其它已被关闭的路
- **硬件内存过滤器**:读解密后的代码被挡(WPR2 探测 `0xDEADDEAD` 后来被解释为未映射显存的填充值;权威 hubmmu WPR2 寄存器返回 `0xBADF5040` 特权毒值 ⇒ 不可判定且价值低)。**注意:不要再大范围读 WPR2/GSP 私有内存。**
- **BIOS 刷新**:不在范围内(用户禁止)。
- 显示/操作经验:`enter-live` 会在打印 `LIVE_VFIO_READY` 之后失败并留下 `driver_override=vfio-pci`(阻塞 nvidia 探测,需清空 + rescan);`recv` 走 MNOC port 1;`scp` 用大写 `-P`;`sudo` 清环境(用 `sudo env VAR=...`);驱动重载后 **必须先建立 ioremap 再读**,否则读到 0。

---

## 3. 项目里已有的大量资料(请**先去读**,不要重复劳动)

按优先级:
1. `/home/user/rt_5090_project/RESUME_BRIEF.md`(**793 行,最重要**,§20–§39 是最近几天;§37–§39 是 L2 数字更正与 knob 矩阵)
2. `/home/user/rt_5090_project/FSP_LINE_COMPLETE_20260926.md`(363 行,FSP 线完整记录)
3. `/home/user/rt_5090_project/parallel/` 下(按主题):
   - **GSP/固件**:`K3_FULL_REVIEW_20260926.md`、`DS_FWSEC_CALLSITE_20260926.md`、`DS_FWSEC_ERRCODE_TABLE_20260926.txt`(347 个错误码)、`DS_GSP_MMIO_WINDOW_20260926.md`、`DS_GSP_MNOC_SERVER_20260926.md`、`DS_GSP_OBJECT_ACCESS_20260926.md`、`DS_FMT_WRITE_PRIMITIVE_20260926.md`、`DYN_IMAGE_AND_FSP_LAYERING_20260925.md`、`COT_PUBKEY_PINNING_20260925.md`、`COT_STAGE1_2_RESULTS_20260925.md`、`DESC_OFFSET_ABUSE_AND_KEY_BINDING_20260925.md`、`bcrt_manifest_coverage.md`、`falcon_manifest_table.md`
   - **FSP**:`DS_FSP_MNOC_ACCESS_20260926.md`、`fsp_boot_chain_trace.md`、`fsp_postdecrypt_observability.md`、`fsp_run_object_diff.md`、`fsp_task2_consumer_followup.md`、`debugtoken_prc_candidate_20260813.md`
   - **SEC2**:`DS_SEC2_INTERFACE_20260926.md`、`DS_SEC2_MEASURED_20260926.md`
   - **L2/mask(项目七月工作,极重要)**:`/home/user/rt_5090_project/GB202_PARALLEL_WORK.md`、`L2_REENABLE_STATIC_FINDINGS.md`、`L2_SLICE_MAP_FINDINGS.md`、`L2_SLICE_RE_BRIEF.md`、`parallel/l2_mask_granularity.md`、`parallel/l2_mask_constraint_audit.md`、`parallel/l2_safety_observe.md`、`parallel/effective_mask_boot_lifecycle.md`、`parallel/effective_setter_provenance.md`、`parallel/disable_sw_override_lifecycle.md`、`parallel/coupling_gate_semantics.md`、`parallel/coupling_setter_crosscheck.md`、`parallel/base_coupling_visibility.md`、`parallel/l2_authorization_state_machine_20260813.md`、`parallel/newcudal2mats_native.md`
   - **其它**:`parallel/evidence_audit.md`(证据分级)、`parallel/enthusiast_hulk_license_route_20260723.md`
4. 反编译/静态工具:`gb202_reghal_offline.py`、`gb202_vbios_diff.py`、`gb202_jse_offline.py`、`gb202_iff_offline.py`、`gb202_fjson_offline.py`(RegHal/微码反汇编)
5. 固件样本:VBIOS ROM(5090 Astral / FE / Pro6000 Dell 8D / HPE 9E + `g153_0210_895__98028D0001.fwpkg`)、FSP 密文 `vbios_diff/fsp_ciphertext_app24_target0f.bin`(sha256 `1a546c20674f1ccb50c5451f305ed3e2e64a2396ae8bf8418ac61ce944597214`)、`dell_8d_payload/`、`hpe_scexe_payload/`
6. 动态工具源码(理解我们**能**做什么):`/home/user/rpc_ovf_patch_v11.py`、`/home/user/run8.sh`、`/home/user/fsp_probe/*.c`、`/home/user/peek/*.c`、`/home/user/l2knee/*.cu`、`/home/user/wpr_probe/wpr_probe.c`

---

## 4. 我认为最可能有新发现的方向(供你参考,但**不要被它限制**)

1. **`0x12` 掩码的真实语义**:它是"启用位"还是"禁用位"?8 FBP × 8 bit 对应 128 MB 还是 64 MB?项目自己的 `l2_mask_granularity.md` 说未证。**如果能从 ROM/固件/RegHal 元数据里找到这张表的权威定义,就能反推"128 MB 全开"应该是什么值** —— 那是解锁的目标值(即便我们暂时写不进去)。
2. **PMU falcon**:`RMExecuteDevinitOnPmu` 这个 knob 证明存在一个 **PMU 处理器**,而我们的所有工作**从未触及它**。它是否可访问(哪个 BAR/偏移/窗口)?它的固件在哪?它能否写 PLM/fuse 影子?
3. **`UEFI_RM`(0x1C)/`UEFI_XTL`(0x1D)/`ROMREAD`(0x1A)**:CAPS 声称支持但从未被调用。UEFI 调试通道历史上常是大洞。找出它们的**消息格式**(可能需要 host→FSP 的其它封装路径,或从驱动/FMC 明文固件里找调用点)。
4. **PMU/PLM 的"level"语义**:task2 能把 PLM 打开到 L0–L3,但仍写不动 `f8`/掩码。**找出 PLM 的完整状态机**(哪些 bit 是什么 level、`f8` 由谁置位、`0x8212ac` 谁能清),定位**还缺哪一个条件**。
5. **FSP 解析器的内存破坏类 bug**:我们找到的是卡死类(DoS)。**SMBPBI 卡死整个邮箱**尤其可疑 —— 它是否是"越界写导致状态机损坏"?若是,也许能从 DoS 提升为可控写。
6. **GSP 域内任意写为何对 PLM 无效**:是地址被过滤(窗口/黑名单),还是寄存器本身在 GSP 时钟域读回不敏感?**找一个能区分两种解释的实验**。
7. **熔丝的"影子"路径**:项目审计提到 MODS 用 direct-shadow 写熔丝。**驱动/固件里是否存在非 MODS 的合法入口**(例如某个 debug/devinit 表项、某个 registry key、某个 FSP 服务)?
8. **Pro 6000 的 ROM** 是 128 MB 全开的同一 die。**能否从中提取出 L2/SM 的配置差异**(不是字节级 diff,而是解码后的表:floorsweep 表/PLC 配置/DevInit 表)。VBIOS 的 `FloorsweepingTbl` 是具名表(名字来自 Dell 工具元数据)。
9. **其它未被触碰的处理器/引擎**:GB202 上除了 FSP/GSP/SEC2/PMU 还有哪些 falcon?(项目有 `falcon_manifest_table.md`。)哪个可能持有能改 PLM/fuse 的权限?
10. **我们对"已排除"的推理是否有漏洞**:例如 task2 打开 PLM 后,是否**必须配合某个 latch 时序**(`0x820040` 的写被我们判为"从未接受",但也许需要特定序列/延时)?项目 `coupling_gate_semantics.md`/`effective_mask_boot_lifecycle.md` 可能藏着我们没执行完的序列。

---

## 5. 一句最重要的提醒

用户是**资深**研究者,极其在行。他最反感两件事:**(1) 把推测当结论**;**(2) 数字前后不一致**。
所以:**每个数字都要有出处;每个结论都要标明"实测/源码/推测";不确定就说不确定。**
另外:别为了给出"好消息"而夸大 —— 这几天已经有过两次"以为发现了新路径,结果是测量方法的问题"的教训(一次是拿 CUDA 属性否定 L2 被砍,一次是把流式带宽拐点当成真实容量)。
**静态分析的价值在于:找出我们**没试过**的东西,以及**我们推理错**的地方。**

# Ampere→Blackwell 无界拷贝攻击面结构审计 — Falcon/早期启动可见性矩阵

日期:2026-10-25。执行者:Pi(用户授权:"可以试试模拟器那条路,不保证能成功")。
方法:全部离线、只读。新增脚本:`falcon_table_extract.py`(SHA-256 见文件);
复用 `gb202_vbios_diff.py`(`90cefd37…`)。未访问 GPU、未执行任何固件。

## 0. 问题

Jon Pry《A Canary in the Crypto Mine》(Zenodo 20916111)证明 GA100/CMP 170HX 的
SEC2 HS Booter 存在"WPR 元数据 signature-length 字段驱动的无界 DMA 拷贝"。
该缺陷按其 §7.2 为 580 时代回归(510 无)。问题:**GB202(Blackwell)上这个
攻击面是否仍然存在?**

## 1. 证据(E4 离线静态,全部本机可复核)

### E-1 实卡 VBIOS Falcon 表:6/6 非空条目全部 enc=1

样本:`flash_logs/astral-original-20260726_020901.rom`(本机 ASUS Astral 原槽 dump,
image base 0x38000,falcon_table@0x9ce9d,35 entries)。

| idx | app | tgt | flags | enc | tag | region bytes | 熵 |
|---|---|---|---|---|---|---:|---|
| 5 | 0x07 | 0x06 | 0x1d | **1** | — | 0x20200 | 8.00 |
| 22 | 0x18 | 0x01 | 0x1f | **1** | — | 0xcc00 | 8.00 |
| 23 | 0x19 | 0x01 | 0x05 | **1** | — | 0x21b00 | 8.00 |
| 24 | 0x15 | 0x01 | 0x05 | **1** | — | 0x5b00 | 7.99 |
| 32 | 0x23 | 0x0e | 0x1f | **1** | `OOBHUB.a` | 0x1e200 | 8.00 |
| 34 | 0x24 | 0x0f | 0x0d | **1** | `FSP_RUN` | 0x29400 | 8.00 |

payload 已导出 `falcon_extract_out/`(文件名含 `_ENC`)。**VBIOS 内不存在可反汇编的
明文 Falcon 微码。**(熵 8.00 与 flags.bit2 一致;不区分加密/高熵编码,结论同向。)

### E-2 宿主侧 Booter 概念在 Blackwell 被整体删除

`driver_gpio_internal_610.43.03/src/nvidia/generated/` 清点:
`kgspGetBinArchiveBooterLoadUcode_*` / `BooterUnloadUcode_*` **仅存在于
TU102/TU116/GA100/GA102/AD102**。GB100/GB202/GB20B/GH100/GR100 **没有任何
Booter bindata**。GB202 驱动提供的固件资产只有:ConcatenatedFMC(+Desc)、
GspRmBoot、FmcGfw(prod/debug/CC)、SPDM 证书。

⇒ Ampere 攻击的结构性前提——"宿主提供明文 SEC2 Booter 并喂给它元数据"——
在 GB202 上**不存在**。gpu-unlock(Ampere/Ada)的整条流水线对 Blackwell 无对应物。

### E-3 FMC monitor 区为密文,签名覆盖密文

`gsp_qemu/firmware/` 资产复核:`gb202-610.57.04-monitorCode.bin`(225,280B,
=dyn[0xF200:+0x37000]=gfw 签名覆盖区)熵 **8.00**;monitorData(59,392B)熵 8.00。
结合 SIGNATURE_VERIFIER_HUNT(2026-09-25)9/9 样本 P-384 全镜像覆盖:
**验的是密文,解密在片内**。FSP(VBIOS idx34 `FSP_RUN`)同理密文。

⇒ "明文 booter"变成了"密文+签名 FMC/FSP"。无 key-37 式泄漏则 Falcon 侧不可审计。

### E-4 可见明文 RISC-V 执行镜像(攻击面仍然存在,换了 ISA)

| 镜像 | 大小 | 状态 |
|---|---:|---|
| LibOS 内核(`kernel-610.57.04/kernel-load-segments.elf`) | ~164KB | 明文,QEMU 已 boot 至 walk 表发布(E3) |
| init-task(`init-task-610.57.04.elf`) | 53KB | 明文 RISC-V ELF |
| GSP-RM(`gsp-fwimage` 84MB / inner ELF 63MB) | — | 明文,主力 RE 对象 |

已知同族缺陷(GSP-RM,均为既有实锤):F-1 regOpCount 无界 VLA(A 级,Xid 120)、
F-2 IDLE_CHANNELS、V1 fn73 numEntries、K3-1 msgq 先拷后验。**count 信任病在
RISC-V 侧被证实 ≥4 处**——论文批评的解析文化与作者笔迹延续。

## 2. 结论

1. **对"FSP 是否仍有无界 DMA 拷贝":不可判定(密文黑盒),且当前无解密途径。**
   VBIOS 六个 Falcon 条目、FMC monitor、FSP 全部 enc=1;签名覆盖密文;
   无 debug 测试密钥泄漏迹象(FMC debug 镜像用的是另一把签名公钥,非加密泄漏)。
2. **Ampere 的具体入口已被结构性移除**(E-2):不是"修补了溢出",是"不再让宿主
   提供 Falcon booter"。gpu-unlock 谱系(cmp170hx→cmp90hx→GA10x→AD10x)在
   Blackwell 无落点,与公开世界无人做出 50 系解锁一致。
3. **等价病灶确认仍在明文 RISC-V 层**(E-4):LibOS 内核与 GSP-RM 的宿主可控
   结构解析是新的"booter 解析面",且已实锤 4 处 count 类缺陷。模拟器路线
   (论文 §3.4/§5.5:确定性目标 + 离线状态重构 + 续体撰写)对这一层完全适用,
   基础设施(gsp_qemu、rv64_emu.py)已在。

## 3. 下一步(修正 2026-10-25 晚:用户判定 + 文档互证)

**划掉 F-1 续体撰写对本目标的价值**:即便 F-1 升级为受控写、即便拿到 GSP
S-mode 任意执行,对解锁 L2/SM/GPC/ROP 无用(用户判断,与既有静态证据一致):

- 单元启用链为 raw OPT(fuse)→ shadow → latch(0x822900 effective 视图)→
  reset-coupled 重枚举;关键写点面对 domainBase+0xdc / +0xf8 与
  disable_sw_override(0x8212ac.bit0,读 PLM 0x8200fc)等 PLM,
  写权限属 FSP/HS 侧,GSP 引擎身份不在允许集(`L2_REENABLE_STATIC_FINDINGS.md`)。
- MODS `fbp_l2slice_enable` 也不能清硬 L2 屏蔽位;公开源码里 GSP 自己的
  reset PLM(0x1103c4)与 device-relative coupling targets 不是同一批
  (`parallel/official_fsp_plm_scope.md`)。
⇒ **GSP S-mode ≠ 单元解锁权限。目标寄存器的唯一写权限在 FSP。**

因此目标导向的有效面只剩:
1. **FSP 合法/半合法接口**:NVDM task2/PRC 请求(历史仅 task2/sub1 一次
   error_code=0 接受,写入为 no-op;`GB202_WRITE_LADDER_PLAN_20260925.md`、
   `fsp_prc_*` 实验、`PRC_KNOB_MAP.md`)。
2. **FSP 解析器内存破坏**:盲区,仅有永久 DoS 级证据(PSIRT Draft 1)。
3. **哨戒条件**:若未来出现 FSP/FMC monitor 的明文泄漏(debug 测试密钥、
   灾难性 mispack),立即对密文组件跑 envydis + Falcon 模拟器(envytools 已构建,
   `build-static/envydis/envydis`)。

F-1/F-2/fn73/K3-1 类 GSP-RM 缺陷仅对非单元解锁目标(InfoROM、时钟策略、
RM 行为伪造等)保留价值。

## 5. FSP 驻留位置:不在显存(用户实测记忆与文档互证)

用户指出"FSP 甚至好像不在显存里,我摸过完整的显存"。既有文档完全支持:

1. **host 不上传 FSP**:`kgspExtractVbiosFromRom` GB202 HAL 返回 `NV_ERR_NOT_SUPPORTED`;
   BootFSM 在 chip reset 后自动触发 FSP;公开链路在"VBIOS v6 对象如何被取出/认证/解密"
   处断掉(私有 BootROM/secure-boot stage)(`parallel/fsp_boot_chain_trace.md`)。
2. **FSP runtime 在自己受保护存储中执行**(片内 Falcon IMEM/DMEM),不密驻 FB。
   host 放进 sysmem/FB 的是 GSP-FMC/GSP-RM 材料与 COT 元数据,不是 FSP 本体。
3. **FB 对照物**:GSP 的东西全在 FB(169 MiB WPR heap、GSP 镜像、COT);全 BAR1 32GB
   只读扫描(`hotspot_reader/bar1_full_vbios_scan_20260726.log`)亦为 FB 内容面面观,
   无 FSP 驻留痕迹。
4. **FSP 对外全部窗口均在 BAR0,非 FB**(FSP_STAGE0_RECON 实测):
   Falcon 寄存器块 0x8f0000+(大部分特权毒);MNOC 信箱 0x8f1e00;EMEM 窗口
   (通道 0–3 可访问/4–7 特权毒;blk≥4=dead5ed0,不可越界读);CMS2 窗口 0x8AA374
   仅 128 dword。唯一泄出面:EMEM 通道 0 残留(曾读到 FSP 侧 INFOROM 响应+PPID)。
5. 无公开 FSP IMEM/DMEM/code dump API;Xid 转储也不附 FSP 内存
   (`parallel/fsp_postdecrypt_observability.md`)。

⇒ 对模拟器路线的修正:**FSP 无明文镜像可灌,Falcon 模拟器对它无直接用武之地**;
FSP 的可接近面只剩其消息解析器(NVDM over EMEM/MNOC)——与既有永久 DoS 实验
所击中的层一致,且该面边界已测绘完毕。RISC-V 侧余下有效目标为 GSP-RM
F-1 类原语的续体撰写(§3.2)。

## 6. 密钥泄漏面调查(2026-10-25 晚,联网检索 + 本地对比)

### 6.1 公开世界的密钥谱系(全部可验证来源)

1. **Turing/TSEC 全量密钥提取(2021)**:`CAmadeus/falcon-tools` — 用 `csecret 6`
   在片内解密 SecureBoot 阶段并导出明文;Reddit r/programming "Full key extraction
   of NVIDIA TSEC"。
2. **Ampere debug key 公开破解(2026-09,mrmcd26 演讲 "FACEB13D exploit")**:
   https://media.ccc.de/v/2026-757-… — 摘要原文:"exploit is based on **guessing
   the debug AES key**";"Nvidia ships two versions of every piece of code…
   encrypted and signed with the production keys and the test or debug keys
   respectively";"**debug and production versions of the code are identical**,
   we can also read the production code"。视频已公开(无 slides)。
3. **密钥跨代共享先例(2023-12)**:dartraiden/NVIDIA-patcher issue #73 —
   booter_load 的 AES/RSA 密钥在同族 SEC2(含 Turing 各代)间共享。
4. cmp170hx 仓库 docs/unlock/(falcon-and-booter.md 等)公开了 Falcon
   HS 入口例程、csecret/ckeyreg/cenc/csigcmp 序列、PLM 模型、ROP 链构造。
5. **Blackwell 先例**:bird/vgpu-unlock-blackwell — vGPU 软件链全部打通,
   GSP 在消费卡被熔断的 VF PRIV 寄存器(0x111xxx)处崩溃 ⇒ "硬件封锁"结论
   (与单元解锁目标不同轴,但同样印证消费/数据中心分测=熔丝)。

### 6.2 ★ 本地新发现:GB202 FMC 保留双版本独立密文(E4,可复算)

用 `parallel/fmc_signature_probe_20260925.py` 解 610.43.03 bindata:

| 对象 | 长度 | SHA-256(前16) |
|---|---:|---|
| `g_gsp_gb20x_dyn_prd_gfw_image.bin` | 287,304 | `17a15ce8f0e697f8` |
| `g_gsp_gb20x_dyn_dbg_gfw_image.bin` | 287,304 | `e5dc90284a4fa56c` |

逐字节对比:全程仅 0.5% 相同;72B 头逐字节相同;manifest(0xA00)/monData
(0xE800)/monCode(0x37000) 区 99%+ 字节不同,熵全 8.00 ⇒ **两份独立加密的
密文**(不同密钥),而非同密文重签。

⇒ **Ampere 攻击的前半段前提在 GB202 FMC 上成立**:若 debug 密钥可猜/可复用,
   可解出 225KB FMC monitor(RISC-V)明文——当前最大的一块不可见启动链代码。
   注意与 Ampere 差异:GB202 无宿主提供 booter,debug key 的价值是**读代码**
   (理解 dyn 完整性检查/0xaff/host 数据解析),而非运行时 ROP。

### 6.3 待做(密钥攻击实验,均离线)

1. 看 mrmcd26 视频拿 Ampere debug key 值与弱熵细节(是弱密钥还是测试向量)。
2. 用已知密钥族对 GB202 dbg_gfw monCode 区试解:Ampere key-37、TSEC
   csecret 密钥、falcon-tools 密钥;AES 模式候选:CTR/GCM(GSP-RM
   crypto_lib 有 AES-GCM/kslot 串)。
3. 解析 72B 头与 manifest 字段(prod=dbg 逐字节同),找 nonce/counter 结构;
   若同 IV 不同 key,验证密文异或流特征。
4. 扩大密文对:GB100/GB20B/GH100/GR100 的 dbg/prd FMC bindata(同在 610
   源码)+ HGX B300 fwpkg 组件 — 跨代密钥复用排查。

## 7. 证据级别

本文件全部新结论为 **E4**(离线静态);引用的 F-1/F-2/K3-1/V1 为 **E0/E1**
(既有文档);QEMU 走到 walk 表为 **E3**(gsp_qemu/PROGRESS.md)。
不声称:FSP 内部无缺陷;明文 RISC-V 层缺陷可利用性(未闭合)。

---

## 8. Ampere 测试密钥完整复原 + GB202 FMC 试解(2026-10-25 深夜)

### 8.1 key37 复原(从 mrmcd26 演讲幻灯片 OCR + 构造公式验证,E5→已验证)

来源:演讲《FACEB13D exploit》视频(已存 `external/mrmcd26_faceb13d_talk_hd.mp4`)。
幻灯片给出完整构造:

```c
// Jetson r39.2 KeyPreparation 文档的示例 SBK(NVIDIA 公开)
const DWORD NvTestKey[8] = {0x12345678,0x9abcdef0,0xfedcba98,0x76543210,
                            0x23456789,0xabcdef01,0xedcba987,0x6543210f};
void makeSecret(DWORD* secret, int secretNum) {
    secret[0] = NvTestKey[5] & 0xFFFFFF00 | (secretNum & 0xFF);
    secret[1] = NvTestKey[4];
    secret[2] = NvTestKey[3];
    secret[3] = NvTestKey[2];
}   // AES key 字节 = 4 个 DWORD 小端序列化;GA100 密钥族 = 512 把(2×256,prod+dbg)
```

**验证通过**:`key37 = 25efcdab896745231032547698badcfe`
`AES-128-ECB(key37, 00×16) = 717D1494EACA317FF106195258B38377` ——与 cmp170hx
文档的已知对逐字节一致。**这是从全公开材料复原 NVIDIA 密钥的完整可复现链。**
(演讲同时披露:密钥共享 120bit、末 8bit=编号;编号 DWORD 位于 rk[0] 以抗 DFA。)

### 8.2 GB202 FMC 试解:阴性(但获得新结构事实,E4)

对 `dyn_dbg/prd_gfw_image`(610.43.03)做三重验尸:
1. 尾部零/FF 填充 oracle:512 把密钥 × 2 镜像 × 64 块 —— 无命中(FMC 为精确
   尺寸容器,本无填充,此 oracle 天然弱)
2. 内部最高频密文块 vs ECB(00/FF):无命中
3. **结构图**:monCode(0x37000) 整体高熵(MIX/DENSE 比 ≈ 随机数据特征),
   但存在**明文零洞**(DBG 30 块 / PROD 6 块,如 +0x36600 处 256B 全零)
   ⇒ 分段加密、明文间隙保留;无 ECB 企鹅(CTR/CBC/AEAD 或唯一明文)。

**结论:GB202 FMC 不吃 Ampere 编号测试密钥族**。下一步:从 GSP-RM 明文
crypto_lib(`fsp_code/crypto_lib_01c38000`,含 AES-GCM/kslot 串)复原
FMC 解密的实际算法与密钥来源(kslot 由谁派生),再回头打 FMC 密文。

### 8.3 FSP 合法接口实测(2026-10-25 晚,E0 真机,宿主 615.78.08)

环境:本机 Astral 原槽 E0,驱动 615.78.08 绑定,EMEM 通道 0(12B 诚实帧,
trial.sh 协议),全程零 Xid、桌面存活。工具:`fsp_recon/emem/fsp_probe2.ko`
(已重建 vermagic 7.2.11-arch1-1)+ `trial.sh`。

**发现:PRC knob 表在 615.78.08 下只剩 knob 0x0000**(读成功,值 0x0000);
九月(610.57.04)存在的 0x0001/0x0002/0x001d/0x0029 全部变 0x1E3(不存在)。
全量扫描 0x0000–0x003F:仅 0x0000 存活。FSP 固件版本未变(v4.76,0x44c),
fuse check=0,boot complete=0xff ⇒ **变化来自卡上 PRC/SPI 配置或 RM 供给面,
非 FSP 固件**。十月 SBR/双 BIOS 槽事件为首要嫌疑(对照 PRC_KNOB_MAP 的
静态预期与九月实测,差异待解释)。
判据词典复验:0x000+载荷=成功、0x202=形状非法、0x1E3=knob 不存在 ——
与九月完全一致。原始日志见 dmesg fsp2: 记录(2026-10-25 19:1x)。

### 8.4 "Blackwell 有没有同款?"最终判定(严格判据,E4)

测试矩阵:**256 把编号测试密钥 × 3 模式(ECB / CBC-IV0 / CTR-nonce0)** 打:
- 驱动侧 FMC dbg+prd:GB202、GB20B、**GH100(Hopper)** ⇒ 全部阴性
- VBIOS 侧 6 个密文 Falcon 对象(本卡 dump,含 FSP_RUN/OOBHUB)⇒ 全部阴性
判据:熵<6.9 且 ≥10 字节 ASCII 串≥15(初轮 7.98 熵的"命中"均为统计噪声,已剔除)。

**结论:编号测试密钥族在 FMC 世代(至迟 Hopper)已被弃用。** debug/prod 双密文
传统保留,但锁已换。最终答案需反推明文 GSP-RM crypto_lib(AES-GCM/kslot)的
实际解密路径。No public Blackwell key exists(检索无果)。

### 8.5 密钥空间数学评估(2026-10-25 深夜二轮)

**已排除(全部严格判据,熵<6.9+长串≥15)**:
- Ampere 编号族 makeSecret(SBK 示例)512 把 × ECB/CBC0/CTR0 × GB202/GB20B/GH100 FMC
- Jetson r39.2 文档全部三个示例密钥(SBK `12345678…` / FUSE `11223344…` / AUTH0 全零)
  × 全部 word 切片(w0-3/w1-4/w2-5/w3-6/w4-7)× 双端序 × 编号 0–255 × 正/反序 × ECB/CTR
  ≈ 数万候选 → 三镜像全阴性
- VBIOS 侧 6 密文对象同battery阴性

**结论:Blackwell FMC 密钥不再派生自公开示例。剩余可行路线(按性价比)**:
1. **DFA(差分故障分析)——不是撞,是降维**:Petri Krohn 在 170HX 上就是用 DFA
   从真卡提取密钥的(演讲原话,编号入 rk[0] 的布局就是防 DFA 的证据)。
   AES-128 DFA 只需**数十个错误密文**即可代数恢复密钥,复杂度≈多项式。
   本项目有全套电压/时钟控制基础设施(power_governor 线)——降压毛刺打
   GSP/FSP 的 FMC 解密窗口是技能匹配度最高的路。5090 68G/s 的算力在此无用,
   用的是代数不是蛮力。
2. **crypto_lib 全量逆向**(20215 行,混合 ECC+AES-位切片;含 0xb2a53fe1 类魔数
   与 0x1010201 位交叉掩码):搞清 kslot 体系与派生函数,若 FMC 与 RM 同库,
   派生结构即缩小空间的钥匙。
3. 已知明文库:monitor 与明文 LibOS 内核同工具链,大概率共享 runtime 代码
   ——仅能做验证 oracle,不能缩 AES 空间。
4. 纯蛮力:若密钥真随机 128bit,2^128 @ 68G/s ≈ 5×10^18 年,数学上死路。

---

## 9. MODS 考古:FSP 合法接口全清单 + FuseRework 调试通道(2026-10-25 深夜三轮)

来源:`mod570_215_static/extracted/home/570.215/mods`(393MB ELF,570.215,纯离线字符串/结构提取)。

### 9.1 FSP use-case 完整清单(字符串表原文,顺序即表)

```
Ecc | Floorsweep | HbmFreq | ResetCoupling | RowRemap | PrcReadMode | PrcWriteMode
| IstDevinitMode | DisableCutthru | LoadHulk | MemInfo | InfoRomRead | FuseRework
| Capability Query | BackgroundCopy | DebugTokenErase | DebugTokenQuery
```
**对位修正:既有实验的 "task 2" = Floorsweep**(2026-07-22/09-25 的 task2/sub1
开 0x8200d0/0x8200dc 的就是它;L2_REENABLE 的 production task 2 亦同)。
sub0/2/3 = 0xaf 的语义 = Floorsweep 的其他子命令在该状态被拒。

### 9.2 FuseRework:调试认证的代码加载通道(新)

流程字符串(原文):Falcon Start → `PollKfuseSfkLoaded`(Kfuse Secure Fuse Key)
→ LoadMetadata → IMEM/DMEM/Manifest → `FRB Riscv Start`(**F**use**R**ework
**B**inary,RISC-V 载荷),认证材料 = `fuserework_debug_gfw_pub_key.bin` /
`_hash.bin` / `_sig.bin`(文件未随 MODS 发布;`fuserework.bin` 主载荷同名引用)。
⇒ 存在一条 FSP 侧、debug-GFW 认证的 RISC-V 载荷加载路径;零售卡是否接受
debug 公钥未证(常规预期:不接受)。**若哪天拿到 fuserework.bin + 三件套,
即是一条 FSP 协作的代码执行通道。**

### 9.3 fusing_mode 状态机(新)

字符串证据:`-fusing_mode` CLI(“Use fuseblow support in FSP for various
usecases”);`Fsp fusing mode disabled! Fuses for usecase 0x%x can't be blown`;
**`Invalid transition from permanent disallow state(0x%x) to allow state for
fusing_mode 0x%x`**(永久单向门!);`Skipping FSP fuseblow ... based on
currently fused values`;PRC 写流(`Before Write PRC, default PrcKnob Value=...
for knob %s (knobId %u)`);另有 "Suicide bits to disable features for HULK"。

⇒ 模型:每 use-case 有 fusing_mode 状态(含 **permanent disallow** 单向态)。
**本卡 615 下 knob 表塌缩可能即状态机迁移的结果**(待证:与 §8.3 关联)。
L2/SM 解锁的"合法"上限 = Floorsweep+fusing_mode 在当前状态允许的范围内。

### 9.4 其他

- AES 描述符 dump 格式含 `key_slot_index`/`initialization_vector[0..3]`/
  `key_increment`/`encryption_mode`(视频引擎密钥结构,证 AES 引擎编程面)。
- 615 新增 `ucodes_ga10x/tu10x.bin`(NVCODES 容器):多引擎 ucode,明文
  符号表+构建串(2024-2026 多代,"STANDARD/NON-SAFETY BUILD"),体加密。
  与 FMC 无直接关联(FMC/SCP 命中皆密文巧合)。
- CC 论文(2507.02770)无密钥层级细节;nvtrust 无 FMC 材料;nova-core
  克隆待补(gitlab 认证问题)。

**本轮净结论:FSP 合法接口全貌到手(17 use-case + 状态机模型 + FRB 调试通道
的存在性证明)。"缩小搜索空间"的最大战果不是密钥,而是:单元配置的合法
入口(Floorsweep/fusing_mode)与它的单向门状态机——下一步应实测本卡各
use-case 的 fusing_mode 现态,判定 L2/SM 合法路是否已被 permanent disallow 关死。**

---

## 10. "解决密码"专项:全量阴性清单与剩余路径(2026-10-25 终)

用户明确目标:解决 FMC/FSP 密钥本身,非绘制地图。以下为完整尝试账目。

### 10.1 已排除(全部有证据)

| 假设 | 范围 | 判定 |
|---|---|---|
| Ampere 编号测试密钥族 | 512 把 × 3 模式 | ✗(全芯片) |
| Jetson 三示例密钥种子 | SBK/FUSE/AUTH0 × 全构造 × 256 编号 | ✗ |
| GB202/GB20B/GH100/GB100/GR100 FMC | prod+dbg × ECB/CBC0/CTR0 | ✗(含 GR100/GB100 补测) |
| B300 数据中心固件 | 111MB fwpkg,Falcon 表(PREPXUC/POSTPXUC 等) | ✗ 全 enc=1 |
| 跨版本密钥流复用 | 610.43.03↔610.57.04(同镜像);↔615(重加密,XOR=噪声) | ✗ |
| GSP-RM crypto_lib 含密钥 | 引擎为 AES0/AES1 硬件引擎 + kslot 硬件槽("before/after kslot clear"),密钥不经固件内存 | ✗(RE 部分完成:xref 于 0x1b22-0x1b2e 簇) |
| QEMU 补丁 | "decryption unimplemented"(跳过 monitor) | ✗ |

### 10.2 密钥体系架构(新证据)

- Thor(PSC)文档:r39.2 KeyPreparation——`PscOemKdk1`(KDK1,32B 熔丝密钥)→
  KDK 派生 usage root keys;SBK 加密 bootloader;"PSC/OESP/SB 的 SBK 同值"。
  ⇒ NVIDIA 家族的 FSP/PSC 密钥模型 = **熔丝根密钥 + 用途派生**。
- Ampere 先例:"Same key across ALL GA100 variants"(170HX 8G/10G/300W/A100/
  Drive A100 同一把 ECB 钥匙)⇒ **家族共享密钥**是 NVIDIA 的真实习惯。
  若 Blackwell FMC 钥匙同样全家族共享,则**任意一台设备的密钥实体转储
  =全家族密钥**。

### 10.3 剩余真实路径(非撞库,是取钥匙)

1. **fuserework.bin + fuserework_debug_gfw_{pub_key,hash,sig}.bin** 泄漏
   (MODS 证明其存在;返修站物料)⇒ 直接获得 debug 认证的 FRB 加载通道。
2. **任一 Blackwell 开发板/返修件的密钥实体 dump**(DFA/JTAG/fuse 读):
   家族共享假设下一次 dump 全族通吃。
3. **PSC/EKB 派生算法移植验证**:若 dGPU FSP 沿用 PSC 的 KDK→usage-root
   KDF(算法在 Jetson 工具链中公开),则剩余未知只有熔丝根密钥本体
   (回到路径 2)。GSP-RM kslot 装载路径 RE(0x1b22-0x1b2e 簇继续)可判定
   槽位是否经固件编程(若是,密钥流经内存 ⇒ 可观测点)。

### 10.4 第三步执行完毕(2026-10-26 凌晨):公开派生体系假设排除

- 取得 NVIDIA 官方 KDF 源码(`gen_ekb.py`,SP800-108 AES-CMAC 构造)+
  Thor 文档 HMAC-SHA256 构造 + 官方默认测试密钥(未烧熔丝 KEK2=全零、
  示例 OEM_K1=Base64 口诀串、固定 FV=bad66eb4...)。
- 电池:16 根钥候选(含 FMC 镜像自身 pubkey/hash/头)× ~27000 组合
  (label/context/KDF/模式/三密文窗口)⇒ **全阴性**。
- 结论:dGPU FMC 不使用 Jetson 公开派生体系(至少不以任何可枚举标签)。
  派生逻辑(若有)在 FSP 密文内部,鸡生蛋闭环。

**"解决密码"最终状态:公开材料+沙发侧手段已穷尽。解锁事件只剩实物:
fuserework 三件套泄漏 / 任一 Blackwell 密钥实体转储 / FSP 明文泄漏。**

### 10.5 "你确定?"复核(2026-10-26 凌晨终):补射四发+实战验证

1. **key37 实战验证 ✓**:解密本机 610.43.03 GA102 DBG booter(60,416B):
   `717D1494…` 标记 DBG×4 / PROD×0(完全吻合指纹);HS 区熵 7.99→6.93。
   产物已存 `ghidra_static/booter_ga102_610_dbg_hs_decrypted.bin`(明文 ACR
   代码,含 scp_key_derive=csecret(0x36/0x37) 结构,GH100 世代 LS 派生可从此研读)。
2. **补射:测试密钥族作 KDF 根**(47,616 组合,SP800-108-CMAC/HMAC/ECB-FV
   ×23 标签 ×7 context)⇒ 阴性。
3. **跨变体/芯片/版本 XOR**(prod↔CC、GB202↔GB20B/GH100、610↔570)⇒ 全噪声。
4. **密码识别**:IC 全平(0.31-0.47%),频度均匀,无周期性 ⇒ 无结构弱点。

**最终判定(沙发侧穷尽后):是,确定。** FMC 密钥为硬件槽值(生产 SCP 槽),
公开材料与一切已知测试密钥族/派生组合均不可及。解锁事件维持:实物密钥转储
(DFA/熔丝读)、fuserework 物料泄漏、FSP 明文泄漏,三者之一。

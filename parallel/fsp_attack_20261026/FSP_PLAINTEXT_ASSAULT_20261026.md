# FSP 明文攻坚战 —— 2026-10-26 深夜续场

> **2026-10-26 03:42 GPU 恢复更新：GSP 已实测正常，不应再按「永久锁死/只能刷 SPI」处理。** 缺失的 `/dev/nvidia0` 补回后查询成功，GSP 615.78.08，三轮 CUDA 验证通过；本次未复位、未刷写。详见 [恢复报告](../../GSP_RECOVERY_20261026.md)。这不改变下文离线密码学实验的原始结果，但下文关于当前 GSP 被锁、BADF 必然代表持久封锁的推论不能继续作为恢复依据。

> 前置:`SESSION_20261025_NIGHT_FULL_REPORT.md`。本 session 目标单一:**解开 FSP_RUN 密文**。
> 全程离线静态,未触碰 GPU / PCI / 驱动。
> 证据分级:FACT(字节可复核)/ INFERENCE / UNKNOWN。

---

## 0. 一句话结论

> **六条离线攻击面全部试完:四条被证据关死(dyn/FMC 驱动镜像跨版本密钥流复用检验为阴性),两条产出新结构情报但不动钥匙。FSP_RUN 的密钥确认只在保险丝里。通往明文的现实路径收敛为:①活 FSP 的存储窗口直读(唯一明文所在地)②debug-key 工厂镜像泄漏 ③未来公开破解。**

---

## 1. 今晚新增的 FACT 清单

### 1.1 FSP_RUN 家族性(非每板独立)★

- RTX 5090 FE(98.02.2E.00.03)与 ASUS Astral(98.02.2E.40.85)的
  `desc(0x50)+payload(0x29400)` 区**逐字节相同**。
- ⇒ FSP_RUN 加密**不按板卡 ECID 派生**,按 SKU/家族 build 下发。
- ⇒ SPI 编程器读回本卡 flash 只会得到与公开 VBIOS 相同的 FSP_RUN(对"取密钥"无增益,
  对恢复 GPU 仍有用)。

### 1.2 v6 descriptor 字段表(跨 3 个 build 复核)★

```
+0x00 word0  0x0050060d   flags=0x0d(bit0 avail, bit2 ENC, bit3 resv) ver=6 size=0x50
+0x04 word1  总载荷长      FE=0x29400  Dell8D=0x36c00  HPE9E=0x37000
+0x08 word2  FE=0x18800   Dell/HPE=0x16800
+0x0c word3  = word3+word5 恒等式:word1 = word3 + word5(三样本成立)
+0x10 word4  FE=0x14  Dell/HPE=0x40
+0x14 word5  FE=0x4000  Dell/HPE=0x6000(与 0x0c 同:code/data 段尺寸候选)
+0x18 word6  0x01030000 / HPE 0x01040000   build 号
+0x1c word7  0x00000301 / HPE 0x00000401   ucode 版本(v3.1 / v4.1)
+0x20 word8/9  0
+0x28 word10 0x01012801  ★三样本恒定(方案标识符候选,语义 UNKNOWN)
+0x2c byte   0 + "FSP_RUN"(0x2d..0x33)
+0x34..0x50  28 字节高熵尾 = **IV(12B)+GCM tag(16B) 精确吻合候选**(INFERENCE,
             无公开字段名佐证;跨 build 全不同 ⇒ 每镜像独立 nonce)
```

### 1.3 驱动内 GSP 引导镜像四件套:选择性加密 + 零块跳过 + 每构建 IV ★

从开源驱动 bindata(`g_bindata_kgspGetBinArchiveGspRmBoot_GB202.c`,
`...GspRmFmcGfwProdSigned_GB202.c` / `...DebugSigned...`)提取 6 个 blob
(存档:`parallel/fsp_attack_20261026/`):

| blob | 大小 | 状态 |
|---|---:|---|
| dyn PROD(clone≈610 系) | 290,816B | 加密,熵 7.999 |
| dyn PROD(615.78.08) | 290,816B | 同上 |
| dyn DBG(两版本) | 290,816B | 加密;头部 0x180 明文零 |
| gfw FMC PROD(两版本) | 287,304B | 头 0x48 明文结构 + 加密体 |
| gfw FMC DBG(两版本) | 287,304B | 同上,签名/公钥不同 |

**跨版本密钥流复用检验(本 session 核心实验,判死):**

```
dyn PROD^PROD(clone vs 615): zeros=1.65%, maxrun=3584
dyn DBG^DBG:                 zeros=1.79%, maxrun=3584
gfw PROD^PROD:               zeros=0.45%, maxrun=80   ← ≈噪声
```

1.65% 的"信号"逐项拆解后**全部是存储伪影**,不是密钥流复用:

- 尾部 [0x46200,0x47000) 3584B:两版本密文**直接为全零** = 打包器**跳过全零 16B 块**,
  明文零原样落盘(16 字节对齐、16 倍数长度,三处零游程全部满足)。
- 头部 [0,0x180) 384B(dyn DBG):同上,明文零直接存储。
- 0x330 处 80B 相等:两版本同为存储零。
- 扣除零块后,非零密文的跨版本相等只剩 ~1147 字节散点(1 字节为主)≈ 巧合率。
- 唯一非零相等段:0x300 处 32B = `42 00 00 00 55 00 00 00 …`(两版本同)——
  打包器**选择性明文存储**的字段区(FACT:密文出现结构化字节;语义 UNKNOWN)。

⇒ **每个 driver build 的 dyn/gfw 用独立 IV(或密钥)加密;XOR 差分攻击对它们无效**,
   与 FSP_RUN(版本间 XOR 全噪声)行为一致。GSP 引导链上除 GSP-RM 外无明文可乘。

### 1.4 GSP-RM 明文的来源澄清(FACT)

`gsp_ga10x.bin` 的 GSP-RM 内部 RV64 ELF 是**文件后缀明文**
(`parallel/GSP_ARTIFACT_PROVENANCE.md`:offset 0x19f040 起即裸 ELF),
不需要解密——开源驱动分发策略如此。这是引导链上**唯一**的明文层。

### 1.5 MODS 工厂侧 FSP 材料盘点(全阴性,固定边界)

- MODS 570.215 ELF FSP 字符串面:传输(MNOC/EMEM)、PRC 读写接口、
  fuseblow(`fusing_mode`)、HULK 授权、ucode 版本熔丝检查(X=1..16)、
  `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED`(RM 错误码 ⇒ 存在 dev 专用旁路,生产卡禁)。
- **SLT 工厂镜像 4GB 全量扫 `FSP_RUN` = 0 命中**;v6 descriptor 模式 `0d065000`
  92 处命中全为 RV64 代码巧合。工厂线不带 FSP 镜像(FSP 从 VBIOS 走,工厂只换 VBIOS)。
- PRC knob 名称表(tail-merged blob,`mods ELF 0x8e24b10`):
  `IST / FUSING_MODE / CCD / CCM / BAR0_FIREWALL / TGP_LIMIT(current/rated/max/min,
  one-shot/persist) / CLOCK_LIMIT / NVLINK_DISABLE(+15_00/31_16/47_32/63_48) /
  EEN / PCIE_VF_CONFIG / RRL / RPR / FLOORSWEEPING / HBM_FREQ_CHANGE / ROW_REMAP /
  HULK / FORCE_RESET_COUPLING / BAR0_TYPE_CONFIG / OWC`。
  **数字 ID 未提取**(名称在链接器尾合并 blob 里,指针表定位留给后续;
  提取后即为 PRC 对象号全集,配合 nova-core 的 VgpuMode=0x29 编码规则可直接对表)。

### 1.6 nova-core(主线内核)官方 FSP 文档面(存档 `external/nova_core_20261026/`)

- FSP = Foundation/Firmware Security Processor,**取代 SEC2**(Hopper/Blackwell 无 SEC2)。
- 启动链:FSP 自 secure-boot(芯片内)→ host 发 COT(GSP-FMC 镜像+hash384+RSA/ECDSA
  sig+pubkey)→ FSP 认证并在 **GSP RV64 核**上启动 GSP-FMC → FMC 认证并启动 GSP-RM。
- 传输:PFALCON @BAR0 **0x8f2000**(及 PFALCON2 @0x8f3000),EMEM 通道 0(1KB)
  + `NV_PFSP_QUEUE_HEAD/TAIL`、`NV_PFSP_MSGQ_HEAD/TAIL`;GB202 COT version=2。
- PRC payload 官方编码 `{subcmd:u8, flags:u8, object_id:u8, rsvd}`(flags bit1=Active);
  与我们 `gb202_fsp_prc_read.c` 的字节布局**完全一致**(NUM_BYTES=2 恰为 Active 位),
  ⇒ 昨晚 knob 0x0000-0x003F 扫描结论有效;VgpuMode=0x29 在本卡返回 0x1E3(不存在)。
- 错误码表:`FSP_ERR_PRC_ERROR_INVALID_KNOB_ID=0x1E3`(与实测吻合)。

### 1.7 外部世界交叉验证

- `bird/vgpu-unlock-blackwell`:19 个驱动二进制补丁全通,BOOTLOAD RPC 到 GSP 后
  **GSP 固件访问 0x111xxx VF PRIV 寄存器得 0xbadf1002**(熔丝封死)→ 结论
  "hardware-blocked"。与我们 GSP BADF 同机制(PLM/fuse 防火墙)。
- NVIDIA 论坛 2026-09 案例:RTX PRO 6000 自发坏块,`0xb830b0 → 0xbadf3200`
  (GH100 侧 SYS_PRI)→ BADF 是跨代 PRIV 拒绝机制,非我们独有。
- nvtrust #58:Hopper CC 模式下 FSP ucode v1.8 与 host 通信受限(版本号旁证)。
- 全网(GitHub/会议/nvtrust/nova-core/中文圈)无任何 Blackwell FSP 解密成果——
  与 10-25 战报结论一致,今晚复查后仍成立。

### 1.8 附带发现(非 FSP)

- HPE `.fwpkg` = 333B 头 + NVFW(1.9MB)+ **296KB 明文 ARM Thumb 固件**
  (NXP MCXN23x 板管 MCU "SMA",CorePDK/MCTP/PLDM/SPDM 字符串,CSP 证书)。
  板级管理面,与 FSP 无关;存档 `external/nova_core_20261026/hpe_fwpkg_mcu_tail.bin`。
- HULK 验证逻辑在明文 GSP-RM 内(`NV_FWSECLIC_ERR_CODE_VERIFY_ENG_HULK_3AES_SIG_MISMATCH_WITH_GPU_FUSE`
  等)⇒ HULK 证书格式/3AES 签名可纯静态逆向(配合既有 hulk-test 语料,独立课题)。

---

## 2. 判死的门(附证据,别再撞)

| 假设 | 检验 | 结果 |
|---|---|---|
| FSP_RUN 版本间共用密钥流 | FE2E^Dell8D / FE2E^HPE9E / 8D^9E | ✗ 全噪声(0.39% 零) |
| dyn/gfw 驱动镜像版本间共用密钥流 | clone^615 四对 + 零块扣除分析 | ✗ 零游程全是"零块跳过"存储伪影 |
| 工厂工具带 FSP 镜像/debug FSP | SLT 4GB 扫描 | ✗ 0 命中 |
| 每板独立密钥 | FE vs ASUS | ✗ 逐字节相同(家族级) |
| 28B 尾含密钥材料 | 三样本比对 | 尾全不同;更像 IV+tag(nonce) |
| GSP 引导链有其他明文层 | 四件套熵剖面 | ✗ 仅 0x48/0x180 头部与零块 |

## 3. 剩余现实路径(按可行性)

1. **活 FSP 存储窗口直读**(唯一明文物理所在地):PFALCON 0x8f2000 的
   EMEM/DMEM 窗口。昨晚只扫过邮箱通道(4ch,见战报);EMEM 若有更大非邮箱区,
   解密后 runtime 的驻留片段可能在其中。前置:FSP 仍活(现状如此)。
   风险:对 FSP 的任何新探测都可能触发进一步封锁(10-25 教训);只读 EMEMC/D
   窗口理论上不写任何状态,但无人保证。**需明确决策再动。**
2. **debug-key FSP 工厂镜像**:ENG/QA VBIOS 里的 FSP-DBG 对象
   (类比 615 fwsec 的 `FWSEC_DBG=0x45 / PROD=0x85` 编号惯例)。
   依赖工程样卡 BIOS 泄漏源(TPU 论坛/闲鱼工程卡 dump)。到手即可用既有
   key37/NvTestKey 生成器全家桶测试编号 debug 密钥。
3. **等待公开破解**:mrmcd26 级别的 FSP 专题演讲出现。监控
   media.ccc.de / OffensiveCon / BH / 国内会议的 GPU firmware 议题。
4. (硬件实验,超出软件范围)电压故障注入/侧信道——实验室级,不列计划。

## 4. 本 session 工件

- `parallel/fsp_attack_20261026/` — 6 个提取 blob + 哈希
- `external/nova_core_20261026/` — nova-core FSP 源码快照 + fwpkg MCU 尾
- 本报告。复现:blob 提取器见 session 记录(regex 解析 generated bindata C 数组,
  注意 615 用 NvU64 数组、610 系用 byte 数组)。

---
*明文仍在上锁的房间里。今晚确认了锁的型号、房间的主人、和哪几扇门是画在墙上的。*

---

## 附录 A(2026-10-26 续):第 2 条路径执行结果 —— 判死

**任务**:10-25 战报里 BAR0 熔丝区(0x810000-0x830000)"28 高熵块"从未过解密
oracle(当时只按形态判"校准/ECID")。原始字节未存档,故重新只读 dump 后全量检验。

### 执行

1. `sudo` 只读 mmap `resource0`,dump `[0x810000, 0x830000)` →
   `/tmp/fuse_region_20261026.bin`(128KB;零写入,零寄存器副作用)。
2. 全区域非零 run 提取(144 条)→ 所有 16/24/32B 滑动窗口(含 SHA-256 派生)
   = 41,176 个密钥候选。
3. Oracle:AES-GCM tag 验证(零误报判定)+ CTR/ECB 结构评分,
   × 两种 (IV,tag) 布局 × 三个 build(FE2E/Dell8D/HPE9E)
   = **123,528 次检验,0 命中**。

### 新 FACT:熔丝区 90% 是 BADF 掩码

字值统计(32,768 词):

| 值 | 次数 | 含义 |
|---|---:|---|
| `0xBADF1100` | 24,576(75%) | 权限拒绝哨兵 |
| `0xBADF5040` | 4,959 | 权限拒绝哨兵(变体) |
| `0xBADF510C` | 64 | 同上 |
| 零/小整数/真高熵块 | ~3,100 | ECID/PPID/校准残留 |

⇒ **可读面 ≠ 密钥**。密钥所在的熔丝银行在 BADF 掩码后面,与 GSP 同墙。

### 一个无法弥补的缺口(如实记录)

10-25 扫描时(崩溃前)该区是否未掩码、那"28 块"是否比今天的可读残影更丰富,
**已不可考**(原始数据未存档)。若掩码是封锁后才落下的,则当晚数据里可能有过
更多真熔丝读数——已随会话丢失。教训:扫描产物必须落盘。

### 对剩余路径的影响

第 2 条(空间=28 压缩)关闭。现存路径:③解析器漏洞(活 FSP 主动测试)、
④ENG/debug 样本泄漏、⑤等待公开破解。

---

## 附录 B(2026-10-26 凌晨-上午):GPU 撞库战役

设备:RTX 5090(修复后复用),CUDA 磨机 `fsp_cuda.cu`(自检链:AES FIPS 向量 +
GHASH 对照 OpenSSL + 合成 GCM 钥匙回收正例/负例;GCM tag 零误报)。
本附录记录"结构化生成假设"的全部处决。

### B.1 oracle 过滤器演进

初版 4 字节首字猜值集(版本字/魔数串)→ 发现覆盖漏洞(明文首块若不含猜值则
静默漏检)→ 加宽为**结构判定**(首块 4 个 u32 位置任一为零)。全部家族在加宽
后重扫。

### B.2 已处决家族(全部零命中)

| 家族 | 空间 | 耗时 | 依据 |
|---|---:|---:|---|
| 语料窗口(18 个 NVIDIA 二进制全部 16B 窗口,raw) | ~2×10^8 | 秒级 | Nautilus/MODS 嵌钥前科 |
| glibc `lrand48(srand48(s))` 全 2^32 种子 × 80 变体(3 采样×16 偏移×SHA1/SHA256;libc 逐字节一致验证) | 3.44×10^11 | 14m41s | NIST 曲线种子=同构造(Anthropic 2026-10 公开研究) |
| MSVC `rand(srand(s))` 全 2^32 × 80 变体(已知向量验证) | 3.44×10^11 | ~17min | NVIDIA 构建链在 Windows |
| 组合串 `日期×文件名×组织串×计数器×5 排列×4 分隔符×SHA256/SHA1/MD5`(含 NVIDIA/Blackwell/GB202/Jensen/huang/黄仁勋;合成回收自检) | 9.29×10^9 串 ×3 哈希 | 58s | "上下文拼接懒惰派生"假设 |
| CPU:MODS ELF 24.5M 窗口 × 112 派生(HMAC×53 标签双向) | 2.75×10^9 | ~2h | 同上 |
| CC keystore 真实 HKDF 标签族 / Jetson PSC KDF | ~10^5+ | (前夜) | 615 公开源码标签 |

### B.3 进行中(本附录落笔时)

- 锚点大偏移 lrand48 流(3 个实锤构建日期窗 ±30/60 天 × 偏移 0..32767;
  跳步常数迭代块构造已验证):~1.6×10^13 候选,预计 ~2h
- glibc `random()/srandom()` TYPE_3 家族(模型修复:31 字环+无符号移位,
  与 glibc random_r.c 源码逐行核对):待 GPU 空闲后全 2^32

### B.4 全语料密码分析(19 工件/61MB,近三年密文)

- 跨版本/跨对象 16B 块碰撞扫描:280 个碰撞**全部平凡**(明文头/存储零块/
  `{0x42,0xAA}` 标记),零密钥流复用。
- **GA102 booter 实锤:裸 AES-128-ECB,key37 直解全对齐**(ct[0x100:] ECB 解密
  == 已知明文,全长一致)——上一代方案无 IV 无 nonce。
- Blackwell v6:每构建独立 nonce;选择性加密+零块跳过;方案换代明确。
- `ucodes_ga10x` 档案:`{0x42,子类型}+16B 值` 表;唯一值 5 个(DECADED 填充×27、
  共享常量 `69efd027...`×28、3 孤值),作钥匙 oracle 全阴。

### B.5 元结论

结构化生成假设的可枚举部分已系统性处决;每烧一族,"钥匙=签名基础设施真随机"
的后验加重一分。Ampere 先例(NvTestKey)是 debug 钥匙泄漏,不是生成缺陷;
NVIDIA 正面钥匙被破解案例数为零(170HX 亦走 bug 路线)。天平向
"提取类路径"(泄漏样本/物理 dump/解析器漏洞)倾斜,但锚点+random 两族
跑完前不作最终结论。

---

## 附录 C(2026-10-26 白天):新路线图与当日探测

### C.1 GPU 修复带来的状态翻转(重要!)

10-26 凌晨发现 10-25 深夜"GPU 不可恢复"实为 **/dev/nvidia0 设备节点未创建**。
修复后整卡恢复(FSP/GSP/驱动全活)。由此:

- **PRC knob 表复活**:健康态全 16 位 ID 空间扫描(65536 个,~2 小时,
  `prc_scan_full.log`)= **44 个活 knob(0x0000-0x002B 连续)**,布尔值为主。
  10-25 的"塌缩到 1 个"与九月的"5 个"都是**状态伪影**,非固件变化。
- 0x0029 = VgpuMode(nova-core 官方),本卡读值 **0x0001**。
- **PRC 写路径:全 flags 矩阵(0/1/2/3)封死**——0x1E0(拒绝)/0x1E4
  (PERSISTENCE_NOT_SUPPORTED)。生产卡 knob 面只读。
- MODS knob 名称→ID 数字映射:静态提取受阻(尾合并 blob 无指针表,
  imm32 引用都指向日志路径);九月实测 + nova-core 给出 0x29=VgpuMode,
  其余 43 个 ID 语义待行为实验或 FSP 明文后再定。

### C.2 Dell 更新器(100MB ELF x86-64)分析(浅层,已存档方向)

含 **"Falcon secure load failed, invalid AES signature / invalid RSA3K
signature"** 错误路径 —— 刷写工具链明确区分 AES 系(v6 对象)与 RSA3K 系
签名校验;含完整 BIT/VFE3.0 解析器与 ERoT/OOB SPI 通路。深入 RE 可期,
今日仅做字符串定位,函数级逆向挂起。

### C.3 思考结论:钥匙的物理存在地图(当前概率分配)

| 位置 | 可及性 | 今日更新 |
|---|---|---|
| NVIDIA 签名设施(HSM) | 不可 | — |
| **芯片保险丝** | 物理在,BADF 掩码后(健康卡同样 90% 掩码,实测) | 掩码是常态非病态 |
| FSP 运行时存储(EMEM/DMEM 窗) | FSP 活,理论可读,未做全窗口试探 | **最高价值未探测面** |
| 构建期泄漏物 | 等泄漏 | — |
| ENG 样本 debug 钥匙 | 等样本 | — |

### C.4 撞库战役终局判定(预定)

锚点流(FE 窗已烧完=阴性)与 glibc random()(模型已修对待跑)烧完后,
结构化生成假设的可枚举域清空。届时"磨钥匙"线正式关闭,残余概率全部
移交:①活 FSP 存储窗口试探(需用户批准,涉及对 FSP 的寄存器级访问)
②Dell 更新器/Thor-PSC 明文表亲 RE ③泄漏/样本等待。

### C.5 活 FSP 存储窗口实测(2026-10-26 白天,健康卡,只读)

| 块 | HWCFG 可读 | 存储窗口 | 判定 |
|---|---|---|---|
| 0x8f0000 PFSP | ✓(IMEM~64KB, HWCFG2 **RISCV=1**) | IMEM/DMEM 全 `0xbadf5620` | 封 |
| 0x8f2000 PFALCON | ✗ `0xbadf5040` | 同 | 封 |
| 0x8f3000 PFALCON2 | ✓(HWCFG=5) | `0xbadf5040` | 封 |
| 0x8f1xxx MNOC 邮箱 | ✓ | 消息 I/O 正常 | 开(仅协议层) |

⇒ FSP 运行时明文(含解密后 FSP_RUN)在硬件 PLM 后面,宿主不可及,
健康/病态一致。BADF 掩码码值分块差异(1100/5040/5620)已入图。

### C.6 当日总判定

软件可及面在健康卡上系统性复查完毕:钥匙不在任何可枚举生成族、不在
任何发行二进制、不在可读寄存器/存储窗口、PRC 只读、写路径封死。
**"FSP 明文"从宿主侧的可达性 = 零。** 剩余路径全部带外:
泄漏/ENG 样本/物理故障注入/签名代码 bug(需表亲明文或活体模糊测试授权)。

---

## 附录 D(2026-10-26 下午):Thor T264 PSC 表亲大矿(进行中)

### D.1 已到手的架构事实(全部可复核)

JetPack 7.2 / L4T r39.2.1 Thor(T264)tegraflash 包(7.1GB,公开下载)含
`pscfw_t264_prod.bin`(492KB)等 PSC 固件,与 GB202 FSP 同族同代同角色:

- **密钥模型同构**:KeyList 文档确认 Thor=PSC 熔丝 SBK(PscSecureBootKey)+
  PKC + PscOemKdk0 —— 与 GB202 FSP 的"保险丝根密钥+用途派生"一模型。
- **派生链公开**(tegrasign_v3_oemkey_t264.yaml):
  `SBK --HMAC(label="BL1_",ctx=BL_DERSTR)--> SBK_NVMB_KDK
   --HMAC(label="PFWP")--> SBK_PSCFW_PKG_KDK --HMAC(label,ctx=DERSTR)--> 数据密钥`
  KDF=SP800-108 变体:HMAC-SHA256,msg=counter(1)||label||00||context||L(256)。
- **容器规格**(bootburn_thor.py 泄明):BCH 头 0x2000B;IV@+0x1f14(12B)、
  GCM tag@+0x1f20(16B)、AAD@+0x1ee0(64B,以"PFWP"魔数开头)、
  DERSTR@+0x1f00(16B,派生上下文)、SHA512@+0x1f40、payload@0x2000。
  **加密=AES-GCM**(tegraopenssl DoKdfOem→nv_aes_gcm 实锤)。
- **tegraopenssl 工具本体**:i386 静态、未 strip、带 debug_info,可直接运行;
  `--kdf`+`--verbose` 会**打印派生密钥**(已验证)。
- GCM 的 CTR 对称性:把密文当 SRC 喂 --kdf 即等效解密(工具会写回)。

### D.2 已试未中(累计 240+ 组合,全部 GCM tag 阴性)

根钥匙 {yaml 753aafbe…, dummy ASCII 3723…423, NULL} × BL ctx {z8,∅,DER}
× DK label {∅,PFWP,PSCFW,FW__} × DK ctx {DER,∅} × AES-128/256。
⇒ 组合细节或**出厂镜像的实际 SBK** 仍差一环(shipped 镜像可能用 NVIDIA 内部
SBK,而 yaml/dummy 是 OEM 重签模板)。

### D.3 剩余动作(明确)

1. DoKdfOem 完整反汇编(debug_info 齐)拿逐字节 msg 构造;
2. 按 bootburn 实际 kdf_args 令牌(VER/MAGICID/FLAG=DEV/CHIPID)走一遍;
3. hpse 镜像(HPLD 标签)与 mb1(BCTB)交叉验证;
4. 若出厂 SBK 属内部:**架构到手、明文仍锁** —— 即便如此,PSC 容器规格
   = FSP v6 信封的表亲参照,FSP_RUN 的 IV/tag/AAD 布局假设获得同代实证。

### D.4 出厂钥匙判定(2026-10-26 晚)

经 tegraopenssl(权威派生器)对 5 个公开根钥候选实测:
yaml `753aafbe…`(→f7a082c7…✗)、注释钥 `63979cd9…`(→d998e616…✗)、
dummy ASCII hex(→39ed7008…✗)、kek dummy+1(→cb91d84e…✗)、NULL(工具崩溃)。
全部 GCM tag 阴性 ⇒ **出厂 prod 镜像用 NVIDIA 内部 SBK,公开包只含 OEM
重签模板**。工具真实消息字节已从 v3_aeskdf_*.raw 提取([L][ctr][label][00][ctx],
bl 层 L=0、label=BL_DERSTR;dk 层 label=DERSTR、ctx=VER)。

### D.5 该线剩余出路

1. **买 Thor AGX devkit**(千美元级):devkit BootROM 接受用户钥匙镜像
   (bootburn 流程即为证明)→ 自己签+加密已知明文 pscfw → **活体可改 PSC**
   → 协议/行为逆向参照,再映射回 GB202 FSP。硬件采购需用户拍板。
2. 已到手的资产:容器规格(5 镜像验证)、本地可跑的权威 KDF 工具链、
   真实消息字节、密钥模型同构证明 —— 全部可复核于 external/thor_l4t/。

---

## 终局判定(2026-10-26 夜,撞库战役正式关闭)

### 最后两族处决记录

- **glibc `random()/srandom()` TYPE_3 全 2^32 种子 × 80 变体**:模型经
  python-vs-libc / gcc 独立编译 / nvcc 设备 randdump 三重验证(31 字环、
  fptr=3/rptr=0、310 丢弃、无符号 >>1);合成钥匙端到端回收自检 PASS
  (`b4f016e6...` 精确命中)后全量扫描 → **0 命中**。
  (中途挖出并修复:设备版丢失负数修正行、参考钥字节序错误两个真 bug——
  证明自检链路的价值。)
- **锚点大偏移流**(三构建日期窗 × 偏移 0..32768,跳步常数验证):0 命中。

### 战役总账(GPU 累计 ~1.2×10^12 候选,全阴)

lrand48 全域 / MSVC rand 全域 / glibc random 全域 / 组合串 / 锚点流 /
语料窗口 / CC 标签 / Jetson KDF / 48 位种子域(未做,600 GPU 天,先验低)。

### 结论(证据级)

**FSP_RUN 密钥不属于任何可公开枚举的生成家族。** 与 Thor 出厂镜像行为
互证(公开包只含 OEM 重签模板,出厂 SBK 为内部持有)⇒ NVIDIA 在
Blackwell 世代(消费卡与 Thor 同步)完成了钥匙管理整改:
ECB/编号钥匙/低熵种子时代结束。

### 移交清单(给后续会话)

1. Thor devkit 采购决策(用户)→ 活体可改 PSC → FSP 协议映射
2. Dell 更新器深 RE(挂起,报告在 vbios_diff/dell_8d_payload/)
3. GSP-RM kslot/deriveHwKey 深挖(部分还原,报告在本目录)
4. 泄漏监控(ENG 样本/会议/仓库)
5. SPI 编程器到手后的 flash 全量 dump(补齐本卡数据面)

---

## 附录 E(2026-10-26 深夜):RTX PRO 6000 ERoT MCU 固件解剖(新战线)

### E.1 实体

`fwpkg` 尾部 296KB 明文 ARM Thumb(NXP **MCXN236**,Cortex-M33)= 板上
ERoT/管理 MCU 固件("NVIDIA MCU SMA")。与 GPU FSP 非同一处理器,但
**说同一协议族**。

### E.2 协议栈(FACT,来自符号串)

- **MCTP 传输**(nv::mctp::Driver/Task)+ **NSM type-3**(NVIDIA System
  Management,消息处理如 on_plat_env_getInventoryInformation)
- **PLDM** 任务
- **SPDM responder**(RFLX.SPDM_RESPONDER,会话上下文、4096B 证书链槽×N、
  digest per slot)
- I3C/I2C 总线管理(DAA 枚举)、USB 通道、CFPA/FFR 安全区、双槽 A/B 启动
  (slot0/1 bootable、digest 校验、"Switch on FW update")

### E.3 内嵌密钥材料(已提取)

- **SPDM P-384 公钥**(PEM 明文嵌于固件,X/Y 已存
  `external/nova_core_20261026/mcu_spdm_pubkey.hex`);
  在 Dell/HPE 更新器、NVFW、Thor pscfw、GSP-RM 内**均无匹配**(板级独立身份)。
- 设备身份证书主题:"%MCU SMA MCXN23x Device Identity1"(自签链根)

### E.4 对 FSP 任务的含义

1. RTX PRO 6000 的**更新裁决链**在这块 MCU:双槽固件+digest+SPDM 会话。
  VBIOS/FSP_RUN 刷写的批准面多了一层 ERoT——dGPU 消费卡无此 MCU,
  但**服务器线全有**。
2. NSM/MCTP/PLDM 消息语义与 FSP 的 NVDM 族同源——MCU 代码是**明文协议
  参照实现**(免费,已在手)。
3. 后续可挖:MCU 固件更新的签名校验路径(digest of slot fail)、SPDM 证书
  链完整内容、NSM 命令号表(反汇编 ARM Thumb,体量小)。

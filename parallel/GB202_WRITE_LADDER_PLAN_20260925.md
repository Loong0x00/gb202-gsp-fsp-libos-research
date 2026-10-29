# GB202 写测试阶梯计划 (草案 v1) — 2026-09-25

前提:这是本机自有卡;禁止项不变(WPR2 类区域禁扫、禁 bulk copy、出口管制相关不碰)。
目的:用**最少的写次数**回答三个问题
Q1 门控能不能开(`0x8200f8.bit4` / `0x82013c[15:0]`)
Q2 开了以后 L2 raw mask 能不能写进并按 effective 生效(+32 MiB)
Q3 被切的单元是 defective 还是 policy(用同一族的来源位判定)

## 0. 前置(必须在第一次写之前完成)

- [ ] 状态快照:VBIOS(`--save` 全片 + 只看不改)、InfoROM 可读部分、`nvidia-smi -q`、MODS 侧全部可读寄存器。
- [ ] **SBR 恢复脚本**放在手边(次级总线复位;已知 WPR2 up 时只有它能救):
      remove → rmmod → `setpci -s 00:01.1 BRIDGE_CONTROL.w=0040:0040` → 清位 → rescan → modprobe。
- [ ] 控制台不在目标卡上(iGPU/串口/SSH),显示器不要挂这块卡。
- [ ] 隔离环境:VFIO 客体 + MODS(与既有实验一致);不做持久化写入,不进 InfoROM/EEPROM。
- [ ] 冒烟判据写死:出现任一 Xid(8/92/94/95/109/120/154)或读到 `0xbadf1100` 类哨兵 → 立即停,跑 SBR。

## 1. 阶梯(每档单独日志,记录 preimage → 写 → 读回 → 复读)

**固定读集 R**(窄读,逐地址,间隔 ≥5 ms,禁扫):
`0x8200f8`、`0x82013c`、`0x820040`、`0x8200fc`、`0x8200dc`、`0x8212ac`、
`0x8234e0+4n`(raw L2,n=0..7)、`0x822900+4n`(effective,n=0..7)、SM 数/`0x82381c`/`0x823820`。

| 档 | 动作 | 判据(=本档回答什么) |
|---|---|---|
| **L0** | 三个镜像(ASUS stock / Lightning 800W / Matrix)下各跑一遍 R | 掩码随镜像变 → 策略表;不变 → 接近熔丝 (Q3 的一半) |
| **L1** | **只做 latch 序列**(今天反汇编出来的顺序):`0x820040 ← (old\|1)`;随后 `0x82013c ← 1` | 读回 `0x8200f8.bit4` 与 `0x82013c[15:0]` 是否变 1;这是唯一"从未试过完整顺序"的步骤 (Q1) |
| **L2** | 若 L1 成功:对 **单个 FBP、单个 bit** 写 raw(`0x8234e0+4n`,只清 1 bit),按需要复拉 latch | raw 是否保持;`0x822900+4n` 是否跟随;(可能需要 post-program reset 才生效 → 记录) (Q2 第一步) |
| **L3** | 用 CUDA/NCU 侧读数验证:`device__attribute_l2s_count` 与 L2 带宽/命中率 | 96 → 104(=+2 MiB/bit 的模型)?还是无变化?(Q2 终判) |
| **L4** | 稳定后逐 FBP 推进(一次一个),每步后跑短时压力(≤60 s,锁频锁功耗) | 出现 ECC/L2 错误 → 说明该 bit 是 **defective**,立即回写置位并复拉 latch |
| **L5**(可选) | SM speed-select:`0x82381c/0x823820` 走 **MODS 现成 setter**(比手写安全) | 时钟/功耗变化 + 稳定性;这是收益最直接也最"有官方路径"的一档 |

**顺序不可换**:L1 → L2 → L3,因为 170HX/GA100 的经验是"先开门再写影子,否则回读原值"
(与既有 `0x8234e0=0x10 → 读回 0x12` 的负结果一致)。

## 2. 不变式(每次写入前重述)

1. 一次只改一个地址、一个字段;其余位按 preimage 回写。
2. 任何写入后必须**复读三处**:目标、同族 PLM(`0x8200f8/0x8200dc/0x8200fc`)、effective(`0x822900+4n`)。
3. 每个 bit 的"回滚动作"在写之前就要写好(置位 + 复拉 latch)。
4. 不做跨镜像混合(同一档内不换 VBIOS)。
5. 出现哨兵/异常即停并 SBR;恢复了才允许下一档。

## 3. 待补(worker ④ 回来后)

- `0x10338000 / 0x10348000`(TPC/GPC region)与 `0x10974000 / 0x10984000`(PES)对应的真实 `0x82xxxx` 地址;
  拿到后把 R 集扩展成"TPC/PES/ROP/L2SLICE 全族窄读",这样 Q3 的判定就从 L2 一族扩展到 SM 一族。
- post-program reset 的准确形式(是否需要 reset/re-enumeration 才让 raw→effective 生效),
  这条决定 L2 与 L4 之间要不要插一次 SBR。

---

## 0b. 存活与止损(补,起因:本机唯一显示设备就是目标卡)

实况:`01:00.0` 是**唯一 VGA**(无 iGPU),host 已绑定 `nvidia`,`gnome-shell`/`Xwayland` 就跑在这块卡上。
→ 一旦 Xid 154/GPU locked,**桌面先死、终端/harness 一起死**,日志与"下一步"都拿不到。
因此下面三条是写之前的前置,不是可选项:

1. **把 harness 挪出显示路径**:`systemctl isolate multi-user.target`(停桌面),全程 SSH/串口驱动;
   `/dev/ttyS0..S23` 已在(mainboard COM header),必要时插挡板。
2. **看门狗必须在 harness 之外**(独立 systemd unit,参照现有 `gpu-thermal-kill-guard.sh` 模式):
   监听 `Xid 8/92/94/95/109/120/154` + `_kgspRpcRecvPoll: GSP RM heartbeat timed out` + `kflcnWaitForHaltRiscv*`,
   触发后执行 SBR 序列(kill users → remove → rmmod → `setpci BRIDGE_CONTROL 0x40` → rescan → modprobe)并 **停住**,不自动续档。
3. **两阶段日志 + 异盘落盘**:每步先 `append` "intent"(含 preimage),做完再 append "result";
   日志写到 `/mnt/sda`(与系统盘不同的块设备),每步 `fsync`。
   事后可 `journalctl -b -1` 取内核侧;凭 intent/result 的配对判断"卡死时哪一次写正在飞"。

### 带外硬复位(最后手段,写之前必须实测)

`/run/media/user/POWERCTRL` 里是电源控制软件(`PowerCtrl.jar`、`sscom32.exe`、`A5558.CAP`),
但 `lsusb` 当前**没有枚举到 USB-serial/继电器**(只有 Phison U 盘、hub、键鼠、AURA)。
所以:
- [ ] 插上/确认 PowerCtrl 硬件本体,脚本化"断电+上电"一条命令;
- [ ] BIOS 设 `AC Power Loss = Power On`,保证硬断电能自动回来;
- [ ] **干跑一次**(不动任何寄存器),确认从"卡死"到"回到可 SSH"是脚本化的。

### 容器化方案(VFIO,推荐用于真正写入阶段)

- 写入阶段把卡绑到 `vfio-pci`:host 不加载 nvidia(无桌面、纯 headless + SSH/串口),
  MODS 与写入都在客体里跑。客体崩 → host 存活 → host 执行 SBR 并重启客体(`vfio_production_lab/`、`vf_recovery_path_safe_pilot_20260822` 已有底子)。
- 代价:host 侧 `nvidia-smi` 读数与部分 RegOp 通道不可用,
  因此**窄读差分(L0)在 host 驱动配置下做,写入阶梯(L1+)在 VFIO 客体里做**。

## 0c. 明确移出计划的两项

- **MODS 的 5 层 `SecurityUnlockLevel`**:经确认那是给 UI 使用者的进程级概念,
  不在本阶梯的门控链条上;本计划只认**设备侧**门(PLM/latch/fuse),不再为它花步骤。
- (不变)出口管制相关不在范围内;WPR2 类区域禁扫、禁 bulk copy。

---

## 0d. 签名链审计回灌(2026-09-25,两份 worker 报告)

来源:`SIGNATURE_VERIFIER_HUNT_VBIOS_20260925.md`(718 行)、`SIGNATURE_VERIFIER_HUNT_FSP_20260925.md`(522 行)。

### 被否掉的假设(从计划里删掉)

- **"GB202 VBIOS 里的 FWSEC 尾有未签名 CTRL_OPT 表"** —— 不存在。
  理由:GB20x 上 `kgspExtractVbiosFromRom_HAL` 是 `NV_ERR_NOT_SUPPORTED` stub;
  **5090 ROM 里没有 FWSEC app(0x05/0x45/0x85),只有 `FSP_RUN`(0x24) v6**。
  ⇒ 170HX 那条"改未签名的 FwSec 表"路线在 GB202 上**没有对应物**;worker ③ 预计负结果。

### 新事实(可复算,已验签)

- FMC 容器:72-B 头(`ver=0x0403, hdrSize=0x48, payloadSize, codeSize@0x0c, dataSize@0x14`)+ manifest 0xA00 + data + code;
  尺寸恒等式 5/5 成立;**签名覆盖=整个 image blob(无排除区)**,9/9 个 P-384 样本验签 VALID。
- 签名形态:`secp384r1` + SHA-384,裸 `r||s` 96 B,未压缩点 97 B;`NVDM_PAYLOAD_COT{hash384[12],pubkey[96],sig[96]}`。
- 密钥复用:GB202/GB100 prod 同一把(`af870e5d…`),debug `9cdd06eb…`,GR100 `34a0836e…`。
- 主机侧**零密码学**:按 `".fwsignature_"+chipFamily` 取 4 KiB section 交给设备(570.144 有 7 个、610.57.04 有 12 个)。
- 熔丝锚点:`NV_FUSE_ZB_OPT_SECURE_GSP_DEBUG_DIS(0x74C)`;`sigIndex = numSigs-1-fuseUcodeVersion(0x41C0/0x4140)`(防回滚)。
- 设备侧 P-384/P-256 曲线常数表已在 3 份 GSP-RM/RX 里定位。

### 最重要的 UNKNOWN(升为本项目第一优先静态问题)

**FMC prod 公钥在本地全部材料里搜不到**(HGX B300 FW 包、GB202 NVFW、5090 ROM、两份 GSP-RM ELF、R570 RX 切片)。
即:可见范围内公钥只由 **host 提供**。因此唯一决定性问题变成——

> 设备是否把该公钥**钉死**在 fuse/ROM(或只钉一个 key-hash)?
> 若是 → 签名路径基本关死,回到 FSP/NVDM + PRC 授权面;
> 若否 → "自带公钥 + 自签 FMC" 就是那条全新载体,而且是 host 递字节这一层就成立的。

判定线索(纯静态):`HS_CHK_GFW_CHAIN_OF_TRUST_BROKEN(0xC8)`/`INVALID_KEY(0xD1)`/`SWKG_INVALID_SIGNATURE(0xD2)`
的产出点、COT 消费代码、以及是否存在 "key hash" 类熔丝字段。

### 其余可用面(按优先级)

1. **FSP/NVDM 路径**(已有实证:`task2/subobject1` 能开 `0x8200d0/0x8200dc`,开不了 `0x8200f8`);
2. **PRC knob 授权**(`PRC_KNOB_ID_FLOORSWEEPING_ALLOW_*`、`..._HULK_ALLOW_INB`);
3. 容器解析面(主机侧 off-by-one / 重名 section / `strtab size=0` 下溢)——注意:这些是**主机内核**面,
   对"我们已经有 host 权限"的场景价值低,除非能跨 VM 边界;
4. ConcatenatedFMC(CC 路径)无独立 hash/sig/pkey —— 认证来源未闭合,留作观察项。

---

## 1b. 读集 R 的真实地址(已闭合,来自 worker ④:RegHal 表解码)

机制:`0x10xxxxxx/0x20xxxxxx` 是 MODS 的 **RegHal ID(不透明键)**,换算 = `ID → 表行 → (domain, offset[, 4·index]) → domain 基址 + offset`。
**domain 5 = fuse/PRI 逻辑域,基址 0x820000** ⇒ `real = 0x00820000 + offset (+4·index)`。
表位置:file `0x9043c8f`(GB202, chip=0xff2,zlib+9 平面 delta,20083 行);解码器 `gb202_reghal_offline.py`。

| 名字 | 真实地址 | 备注 |
|---|---|---|
| `OPT_PES_GPC%u_DIS` | **`0x00823600 + 4·gpc`** | 12 项,逐 GPC(与我反汇编的 `0x10984000` 循环互证) |
| `OPT_LTC_DIS` | `0x00823090` | |
| `OPT_ROP_DIS` | `0x008230a0` | |
| `OPT_FBPA_DISABLE` | `0x00823084` | |
| `OPT_CPC_DIS` | `0x008230e0` | |
| L2 slice 族 A | `0x00822080 + 4i`(16) | |
| L2 slice 族 B(raw) | `0x008234e0 + 4i`(8) | 已知目标 |
| L2 effective | `0x00822900 + 4i`(8) | 已知目标 |
| L2 族 D | `0x00820d70 + 4i` | |
| unit: gpc / fbp / fbio / head / display / spare / nvdec / nvenc | `0x0082081c / 0x00820938 / 0x00820814 / 0x00820808 / 0x00820804 / 0x00820830 / 0x00820824 / 0x00820968` | |
| **未闭合(domain 0,offset 仅 0x10/0x20)** | 假设 H1 = `0x820010 / 0x820020`(未验证) | `TPC_GPCx_DISABLE`、`GPC_GFX_DISABLE`、`PAC_DISABLE`、`SYSPIPE_GFX_DISABLE` |

**构建漂移警告(重要)**:ID 分配**部分稳定**(`0x10348000/0x10338000/0x10360000/0x104f0000/0x10560000`),
但 **fuse/L2 一族随构建迁移**:
- `0x10894000`:570.151 → `0x823090`;570.215 → **`0x8234e0`**
- `0x1096c000`:→ `0x10984000`
- `0x10d6c000` → `0x10d9c000`
- `0x107c4000/0x107c8000 → 0x8212ac` **只在 570.151 成立**;570.215 里它们 → `0x821e78`,而 `0x8212ac` 由 `0x107dc000/0x107e0000` 承担。

⇒ **任何用 ID 记录下来的地址都必须标注 MODS 构建版本**;跨构建引用前先用 `gb202_reghal_offline.py` 复核。

R 集更新(null 值待 L0 实测;全部窄读、间隔 ≥5 ms、禁扫):
`0x8200f8`、`0x82013c`、`0x820040`、`0x8200fc`、`0x8200dc`、`0x8212ac`、`0x8234e0+4n`、`0x822900+4n`、
`0x822080+4i`、`0x823600+4g`、`0x823090`、`0x8230a0`、`0x823084`、`0x8230e0`、`0x820d70+4i`、
`0x82081c`、`0x820938`、`0x820814`、`0x820808`、`0x820804`、`0x820830`、`0x820824`、`0x820968`、`0x82381c`、`0x823820`

## 1c. 表区解析的负结果(省得再挖)

`0x1749de88` / `0x8ece338` 是 **JS/CLI 单元名 + help 描述表**(stride 0x38/0x70),**不是**寄存器描述符表;
表内无 RegHal ID。`TpcMasks / L2SliceMasks / IsFloorsweepingValid` 是 JS 接口/参数名,不是寄存器。
`0x10974000`(`OPT_PES_DIS`)、`0x10a04000`、`0x10c24000` 等 20+ 个名字在 GB202 表中**不存在**。

---

## 0e. 约束更新(用户口径,2026-09-25)

- **不折腾 BIOS**:不做多镜像刷写。⇒ 原 L0「ASUS stock / Lightning / XOC 三点差分」**取消**。
- **Xid 可接受**:软挂/需 SBR 恢复都算可承受;底线是**不硬损坏**(不烧熔丝、不废卡、不动 InfoROM/CCC)。
- 冷却与风扇不在约束内(分体水)。

### 替代 L0:单镜像内判定"policy vs fuse"(不依赖第二张镜像)

| 读数组 | 地址 | 它能回答什么 |
|---|---|---|
| 多域对照 | `0x822080+4i`(16)、`0x8234e0+4i`(8)、`0x822900+4i`(8)、`0x820d70+4i` | 谁是权威域、谁是聚合/镜像;16 项族 vs 8 项族的口径差 |
| 门控前后 | `0x8200f8`、`0x82013c`、`0x820040`(L1 前后各读一次) | 门能否打开(=策略存在) |
| 单元掩码 | `0x82081c/0x820938/0x820814/0x820808/0x820804/0x820830/0x820824/0x820968` | 与 L2 族的屏蔽模式是否同源 |
| 外部一致性 | NCU `device__attribute_l2s_count`(=96) | 实测切片数与寄存器口径是否自洽 |

判据:L1 之后 raw 写入**能保持**且 effective 跟随 ⇒ 事前是 policy;L1 之后仍读回原值 ⇒ 更接近熔丝/硬件闩锁(此时停止投入)。

### 硬损坏禁区(绝对不写的地址族)

- **熔丝编程/覆盖使能**:`0x820078`(FUSE_EN_PROGRAM)、`0x82007c`(FUSE_DIS_PROGRAM)、`0x820080`(FUSE_BYPASS_STATUS)、`0x820084`(FUSE_DIS_SW_OVR);
  GA100 对应族:`0x8203f0`(FUSE_FEAT_OVR_DIS)及其邻居。**这些是"写一次就改设备身份/寿命"的东西,不属于本阶梯。**
- InfoROM / CCC / EEPROM 区(只读也不做批量)。
- WPR2 与 GSP 私有内存(禁扫、禁 bulk copy;只允许既有窄读)。
- 任何 `*_EN_PROGRAM` / `*_OVERRIDE_EN` 语义的字段(逐字确认,不靠猜)。

Xid 可接受 ≠ 写操作可随意:写阶梯仍保留 **preimage + 回写置位 + 复读三处** 的每次动作纪律。

---

# 【执行结果】P0 只读快照 + L1 latch 序列(2026-09-25 12:0x,真卡实测)

方法:VFIO 客体 + 驱动补丁(注入点在 `kgspInitRm_IMPL` GSP-RM 起来之后),`GPU_REG_RD32/WR32`。
每次注入/变体都自检(`注入标记数=1`、`xdL1/xdL2 变体值`、`模块内 XDIG 字符串数=1`),避免"跑了但没生效"。

## P0 只读快照(两次独立启动完全一致 ⇒ 地址是真寄存器、值确定性)

```
8200f8=fffffb8f  82013c=00000000(门低16位=0,关)  820040=00000000(latch=0)
8200fc=80842bcf  8200dc=fffffb8f  8212ac=00000001
L2raw[0..7] (0x8234e0+4n) = 00000012 × 8      ← 8 项全同
L2eff[0..7] (0x822900+4n) = 00000012 × 8      ← 与 raw 完全一致
L2fam[0..15](0x822080+4i) = 0 × 16            L2d70[0..7](0x820d70+4i) = 0 × 8
单元掩码 fbp938/gpc81c/fbio814/head808/disp804/spare830/nvdec824/nvenc968 = 0 × 8
PLM: ltc3090=0  rop30a0=00000003  fbpa3084=0  cpc30e0=0  smsel81c=16676035  smsel820=00077007
GPCdis[0]=0000000f  GPCdis[1..11]=0
```

## L1:latch 序列(写 → 读回 → 立即还原,只碰 0x820040 / 0x82013c)

| 步骤 | 动作 | 读回 | 判读 |
|---|---|---|---|
| pre | — | 820040=0, 82013c=0, 8200f8=fffffb8f | 与"门关闭"前置一致 ✓ |
| s1 | `820040 ← pre\|1` | **00000000** | **写被丢弃** |
| s2 | `82013c ← 1` | **00000000**;f8/dc/fc/12ac 无变化 | **写被丢弃** |
| s2b | — | L2raw0=12 L2eff0=12 rop30a0=3 GPCdis0=f | 无跟随 |
| restore | 还原 preimage | 820040=0, 82013c=0 | 设备回到原状 |

**结论(Q1 的答案):门打不开。**
- 写 1 读回 0;整个 PLM/latch 族**对宿主只读**。
- 与早期负结果 `0x8234e0=0x10 → 读回 0x12` 完全同型 ⇒ 该族同样是只读。
- 合理解释(与命名一致):`PLM` = **Privilege Level Mechanism**,这族寄存器在**硬件特权层**受保护,
  只有设备侧安全域(MODS/FMC)在特权上下文才可写。⇒ 解释了早期"需要 MODS 层访问"的悬案:
  **不是策略表,是硬件特权级**。

**据此**:Q2/L2(清 raw mask)/L4 全部不成立(前提"门能开"已被否证);按计划判据
"L1 之后仍读回原值 ⇒ 更接近熔丝/硬件闩锁(此时停止投入)" —— **本条线到此停止**。

**唯一保留的不确定性**:地址若在 610.x 上又漂移,则"只读"结论会被误判。
但支持地址有效的证据:①两次独立启动读数完全一致(确定性);②读数与配方前置状态吻合(gate=0/f8bit4=0/latch=0);
③`8200fc=0x80842bcf` 这类值明显是真实 strap/时钟域内容;④早期会话在同一地址族写入未造成任何损坏。

---

# 【B 线结果】冷态快照 + FSP 任务扫描(2026-09-25 12:45,真卡,无驱动裸 BAR0)

环境:自家 VFIO lab,客体**不加载 nvidia 驱动**(裸 BAR0),工具为本轮新写的直连 FSP 客户端
`gb202_fs_sweep.static --task-generic <task> <sub> <hexpayload>`(已在客体跑通)。

## B0 冷态(复位后、未加载任何固件/驱动)

```
0x820040=0  0x8200d0=fffffb8f  0x8200dc=fffffb8f  0x8200f8=fffffb8f
0x8200e0=00800b8f  0x8200f4=00800b8f  0x8200fc=80842bcf  0x820434=1  0x8212ac=1
fbp0..7 raw=0x12 effective=0x12 software=0
```

**判读:`0x8200f8`(latch PLM)在冷态就是 `0xfffffb8f`** ⇒ 该值是**熔丝/复位默认**,不是固件在启动过程中"抬起来"的。
⇒ **"宿主趁窗口写"的时序假设(C 方案)被否**:宿主不存在"门开着"的时刻。

## B1 任务扫描(每条:前读 → 请求 → 后读)

| 请求 | FSP 回应 | d0/dc | f8 |
|---|---|---|---|
| task 2 / sub 1 / 6B 零 | **error_code=0(接受)** | **…fb8f → …fbff** | 不动 |
| task 2 / sub 0,2,3 | 0xaf | 不动 | 不动 |
| task 0 / 1 / 3 / 4 / 5, sub 1 | 0xaa / 0xac / 0xab / 0xae / 0xb0 | 不动 | 不动 |

**判读:**
- 新工具与环境可信(复现了 2026-07-22 那次 task2 结果);
- 各 task 返回**互不相同**的"不支持"码 ⇒ FSP 有明确的 (task,subobject) 校验表;
- **没有任何命令能放下 `0x8200f8`**;latch 门是 raw 掩码生效的必经路径 ⇒
  **"宿主单方面改 floorsweep"这一族闭合。**

## 机制结论(与 MODS 逆向一致)

1. MODS 的 latch/raw 写**不是 MMIO**:走对象→虚表→`0x6abc3b0`(缓存"当前选中寄存器/值")→带超时的包化访问;
2. 该通道的互斥是 **`SEC2MUTEX_..._BSI_WRITE_MUTEX`**(前缀 `NV_FWSECLIC_ERR_`/`NV_UCODE_ERR_`)⇒ **由设备安全域仲裁**;
3. 驱动注释同证:`"Required to allow GSP to lower PLM to allow RM"`、`"check that FWSEC has lowered its PLM first"`;
4. 剩余唯一被点名、且未探的授权路径是 **HULK**(`HULK_ALLOW_INB`/`HULK` PRC 条目),需要**设备签发的授权报文**;“无 GB202 HULK caller/payload”仍是既有的静态负结果。

**⇒ 现状:宿主能做的都做完了;再往前需要设备签名的授权材料或设备固件内部漏洞(两者都不可及)。**
**未测项(诚实记录):** `OPT_*_DEFECTIVE` 族仍未读出(=“被切单元是缺陷还是策略”仍未验证);表驱动,需另行定位地址。

---

# 【B 线补测】多相位 PLM 采样(2026-09-25 13:1x,驱动内注入,纯读)

动机:K3 独立审查指出我的两条表述过强 —— ①"PLM 只读⇒宿主无路"只排除了单方面 MMIO;②冷态读数**不能**证明"没有时序窗口"
(驱动注释 `"check that FWSEC has lowered its PLM first"` 反而暗示窗口存在)。故补做**相位采样**。

方法:在驱动 3 个相位点插入 `_xdigPlmSample()`(读 f8/d0/dc/e0/f4/40/ac/fc),其中
`_kgspBootstrapGspFmc_GH100` 作为**死代码阴性对照**(该函数在 GB202 不被调用)。
自检:每文件调用点计数 kernel_gsp=1 / kern_fsp=1 / gsp_gh100=2;模块内 4 个 tag 字符串均在。

## 结果(3 个相位点,逐字节相同)

```
[plm-initRm-entry] f8=fffffb8f d0=fffffb8f dc=fffffb8f e0=00800b8f f4=00800b8f 40=00000000 ac=00000001 fc=80842bcf
[plm-bootstrap]    同
[plm-fsp-send]     同
[plm-fmc-deadcode] 未打印  ← 阴性对照成立
```

加上冷态与 P0(引导完成)**共 4 个相位点全部一致**。

## 判读

1. **f8/d0/dc/e0/f4/40/ac/fc 从复位到 GSP-RM 引导完成,在所有采样点上保持不变** ⇒
   该族在此平台是**静态锁定**的;K3 的"窗口很可能存在"在**floorweep 这一族**上未获支持。
2. **死代码结论由推断升级为实测**:同一注入框架下其它点位都打印,唯独 `_kgspBootstrapGspFmc_GH100` 静默 ⇒
   "BCR 取指地址代码在 GB202 不被调用"**阳性确认**。
3. **重新解释驱动注释**:`kern_gpu_tu102.c:414` 等处的"FWSEC lowered its PLM"更可能指
   **FWSEC 自己的** PLM(如 `PGSP_FALCON_RESET_PRIV_LEVEL_MASK`,见 `kgspResetHw_GB100` 的等待),
   **不是 floorsweep 这一族** ⇒ K3 的窗口推论属**跨族误迁移**。
4. **仍未闭合(诚实记录)**:
   - 采样点之间的**亚秒级瞬态**未排除(要连续轮询;但 4 点全同使"熔丝/ROM 静态"成为最省假设);
   - K3 指出的**归因缺口仍在**:raw 写失败 = f8 latch vs `0x8212ac=1`(disable_sw_override,**且已证为静态=1**)vs BSI/SEC2 互斥 ——
     相位分离法已被证无效(所有相位相同),三候选未被分离;
   - `OPT_*_DEFECTIVE` 仍未读(缺陷 vs 策略)。

---

# 【B 线补测 2】FSP 等待循环内轮询 + 方法学更正(2026-09-25 13:2x)

## 方法学更正(重要,先记)
RM 的 `NV_PRINTF` **不是立刻进 dmesg** —— 有数秒到数十秒的冲刷延迟(加上 log-polling 与卸载时的 dump)。
⇒ 之前那轮"**0 条打印**"是**假阴性**(时机问题),不是补丁无效。之后的纪律:
**①加载前先验证模块内含 tag 字符串 ②加载后等 30s 并触发一次 `nvidia-smi -q` ③卸载(触发 dump)后再读 dmesg。**

## 本轮(已按上述纪律验证:initRm=1 / fsp=1 / poll=1 三个 tag 均在模块内)

| 观测点 | 结果 |
|---|---|
| `plm-initRm-entry`(引导前) | `f8=fffffb8f d0=fffffb8f dc=fffffb8f e0=00800b8f f4=00800b8f 40=00000000 ac=00000001 fc=80842bcf` |
| `plm-fsp-send`(FSP 命令前) | **同上,逐字节相同** |
| `XDIG POLL[waitresp]`(FSP 响应等待自旋循环内,每次回调做 30×3 密集读) | `call=1 f8=fffffb8f d0=fffffb8f dc=fffffb8f 40=00000000 ac=00000001`;**无任何变化、无 MID-BURST**;且**无 progress 行**(progress 每 5000 次调用打一行)⇒ 该自旋循环**调用次数 < 5000**,即 FSP 回包很快,长耗时不在这个等待里 |

## 覆盖度诚实分析(未覆盖的窗口)
- `_kfspWaitBootCond_GH100`(**FMC/GSP 引导条件等待**):本轮与上轮均**从未被调用** ⇒ 该等待路径在本平台不走;
- `_kfspIsGspTargetMaskReleased`:仅 `call=1`(立即满足);
- ⇒ **"FMC/GSP 实际引导期间"的那个长等待,用这两个钩子没盖到**;若要盖,应插在轮询
  `kfspCheckGspBootStatus`(`kern_fsp_gh100.c:1106`)的那个循环里(尚未定位其调用循环)。

## 但这轮的总模式已经很清楚
把**冷态 + 引导前 + bootstrap + FSP 命令前 + 引导完成(P0)+ 响应等待自旋**六处合起来看:
**该族 8 个字在所有可观测状态下逐字节恒定** ⇒ 它们在本平台是**静态的**(与"熔丝/ROM 默认"一致);
结合"裸写一律被丢弃 + MODS 的写要走 SEC2/BSI 仲裁"⇒
**"宿主趁设备降 PLM 的窗口去写"这一假设,在宿主观测粒度上未获任何支持**
(数学上仍不能排除亚毫秒且不可用的瞬态)。

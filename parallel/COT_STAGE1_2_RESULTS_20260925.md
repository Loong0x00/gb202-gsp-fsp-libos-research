# COT 可选性判定实验:stage 1 + stage 2(实机,VFIO 客体)— 2026-09-25

## 环境与前置(实况)

- 宿主:RTX 5090 + `nvidia-open 610.57.04`;`enter-live` 前必须先停 `nvidia-persistenced` / `lactd`
  (它们持有 `/dev/nvidia-modeset`、`/dev/nvidiactl`,否则 `modprobe -r nvidia_modeset` 失败——
  **本 harness 当前不自动停这两个服务,是一个可修的缺口**;`nvidia-reset.sh` 的 `MANAGED_SERVICES` 里已有这三个)。
- 直通:`rtx5090-vfio-enter-live` → `vfio-pci` + `armed`,preflight OK(codex/quill 存活)。
- 客体:`arch-gpu-base.qcow2` + overlay,`nvidia-open-dkms 610.57.04` + `linux-headers` + `/usr/src/nvidia-610.57.04`(可重建)。
- 恢复:`systemctl stop rtx5090-vfio-lab.service` → `leave-live --restore-display`
  → `LIVE_VFIO_RELEASED gpu=nvidia audio=snd_hda_intel display=restored`;GPU 33 °C / 67 W,`/dev/dri` 回来,gdm 到登录器。

## Stage 1:只关 COT 旋钮(`RmDisableCotCmd=1`)

- 客体写入 `/etc/modprobe.d/zz-cot-stage1.conf` 并以 `modprobe nvidia NVreg_RegistryDwords="RmDisableCotCmd=1"` 重载。
- 结果:**GPU 正常初始化**,`nvidia-smi rc=0`,`NVRM: loading ... 610.57.04`,nvlink 重新注册。
- 判读:**歧义**。它可能是"驱动干脆不走带 COT 的那条路径"(没送 = 没校验对象),也可能是"设备用内部根自验"。
  ⇒ 必须用 stage 2 区分。

## Stage 2(决定性):FMC 镜像翻 1 字节 + 重建 + **不带旋钮**加载

- 改动:`/usr/src/nvidia-610.57.04/src/nvidia/generated/…GspRmFmcGfwProdSigned_GB202.c` 的 IMAGE 数组,
  98% 位置处 1 个字节 `^0xFF`;`dkms build/install --force`;`modprobe nvidia`(无旋钮)。
- 结果:**设备拒绝引导**(`nvidia-smi rc=6`):

```
kfspProcessCommandResponse_GH100: FSP response reported error. Task ID: 0x1 Command type: 0x14 Error code: 0x33
NV_PFSP_FALCON_COMMON_SCRATCH_GROUP_2(0) = 0x9f   (3) = 0xa
NV_PBUS_SW_SCRATCH_GSP_FMC_ERROR = 0x0
kfspSendBootCommands_GH100: FSP boot cmds failed. RM cannot boot.
_kgspBootGspRm: unexpected WPR2 already up, cannot proceed with booting GSP
RmInitAdapter: Cannot initialize GSP firmware RM
```

## 结论

1. **FMC/COT 校验在设备侧是硬性的**:镜像 1 字节不同 → FSP 拒收。**"验证可选/可跳过"这扇便宜的门关闭。**
2. 新增一条**可复用的判定指纹**(以后任何"载体"实验的胜负线):
   `FSP Task 0x1 / Cmd 0x14 / Err 0x33` + `_kgspBootGspRm: unexpected WPR2 already up` = **镜像被判无效**。
   若将来某种手法能让 GPU 越过这一点正常起 GSP,那就是真正的突破。
3. 与静态结论一致:签名覆盖整块 image(E8/worker 报) → 改字节必炸。
4. 剩余路线不变且都是贵路线:FMC/FSP **parse-before-verify** 的解析缺陷、熔丝钉扎(需签名/内部通道)、HULK(需 NVIDIA 签)。

## 工件

- 宿主日志:`vfio_production_lab/results/cot_stage1_*.log`、`cot_stage2_*.log`;客体产物目录已取回 `results/cot_stage1_20260925_100111*`。
- 客体 overlay(内含 stage2 的 dmesg/nvidia-smi 全量):`vfio_production_lab/runs/20260925_095932/disk.qcow2`(只读挂载可取)。
- 脚本:`vfio_production_lab/guest/run-cot-stage1.sh`、`run-cot-restore.sh`、`run-cot-stage2.sh`。

---

## Matrix 尝试(2026-09-25 10:08)与其失败原因

### 已跑到的相位

- **P0 基线(stock + 无旋钮)**:`modprobe rc=0`、`GPU_UP=yes`。
  附带观察:**成功路径的 dmesg 里 `kfspSendBootCommands` 与 SEC2 标记都是 0** ——
  也就是说"这次用了哪条镜像路径"**无法从成功日志读出**,只能靠"改哪张图会炸"反推。
- **P1 控制试验(stock + `RmDisableFsp=1`)**:在执行我的"客体侧 PCI reset"时**客体整体挂死**,SSH 不再响应。

### 失败原因(我的两个操作错误,写下来别再犯)

1. **在客体里做 PCI remove/rescan 是禁区**。你们 harness 自己写着:
   "Stopping/restarting a disposable guest is the recovery boundary, not the end of the whole scan"
   —— 清洗 GPU 状态要靠**重启客体**,而不是在客体里 `echo 1 > …/remove` + `rescan`;
   后者直接把客体卡死(本相即死在这里)。**修正:每相 = 一个新客体启动。**
2. **绝不用模式匹配杀进程**。`pkill -f <服务名字符串>` 与 `grep -F '[r]…'` 都会**匹配到我自己的命令行**,
   结果把自己 kill 掉两次(143/137)。修正:用 `systemctl show -p MainPID` 拿 PID,或按 `comm`(15 字符截断)匹配。

### 宿主侧恢复链(实测有效,已验证两次)

```
systemctl stop rtx5090-vfio-lab.service        # QMP quit;若 MainPID 仍在 → kill -TERM/-KILL 该 PID
systemctl reset-failed rtx5090-vfio-lab.service
rtx5090-vfio-recover                            # FLR → bus reset → 显式 SBR(仅在 vfio 且无持有者时)
rtx5090-vfio-leave-live --restore-display        # 回到 nvidia + 恢复所有 VT 绑定 + 起 gdm
# 手动补:systemctl start nvidia-persistenced lactd waterloop-fan-control gdm
#         (leave-live 只恢复"交接时处于 active"的服务,而交接前必须停它们)
```

### 剩余两相(设计已固定,每相一个新客体)

| 相 | 内容 | 判读 |
|---|---|---|
| **D** | 改 FMC + `RmDisableCotCmd=1` | 能起 ⇒ **旋钮是可用杠杆**(驱动选了一条不校验的路);起不来 ⇒ 旋钮无用 |
| **K** | 改 `GspRmBoot_GB202`(该归档**无 hash/sig/pkey**) | 能起 ⇒ **SEC2/非 FSP 路径不校验** → 真门;起不来 ⇒ 两条路径都验 |

每相成本:客体启动 ~40 s + `dkms build/install` ~3-5 min + 一次加载与取 log ~2 min ≈ **6-8 min/相**。
脚本骨架已就绪(`guest/run-cot-matrix.sh` 去掉 `reset_gpu`、改为"单相"模式;`flip_image.py` 可对任一数组定向翻字节)。

---

## 决定性组合实验(2026-09-25 11:01,run 20260925_105834)

**配置**:两张图同时改 1 字节(`GspRmFmcGfwProdSigned_GB202` + `GspRmBoot_GB202`),并设
`NVreg_RegistryDwords="RmDisableFsp=1;RmDisableCotCmd=1"`。补丁已核对(`cmp` 确认文件已变)。

**结果**:仍失败,且**走的是 FSP 路径**——

```
kfspSendBootCommands_GH100: FSP boot cmds failed. RM cannot boot.
_kkgspBootGspRm: unexpected WPR2 already up, cannot proceed with booting GSP
RmInitAdapter failed! (0x62:0x40:2119)
```

**判读(重要)**:

1. **旋钮未被采纳**:`RmDisableFsp=1` 在场时 dmesg 依然出现 `kfspSendBootCommands_GH100`,且
   "NVRM: FSP disabled due to regkey override." 从未出现 ⇒ 这两个键以当前写法(open 模块 610.57.04 +
   `NVreg_RegistryDwords`)无效。可能原因:键名/语义不符、open 构建不吃、或需要额外 override 开关。
2. **因此 stage 1"关旋钮也能起"不构成证据**——那次用的是原装镜像、走的仍是原路径。
3. **FSP/FMC 校验是硬的**:两次独立实验(单改 FMC;两张图都改)都在 FSP 处被拒。
   失败指纹:`FSP Task 0x1 / Cmd 0x14 / Err 0x33`、`NV_PFUSP_FALCON_COMMON_SCRATCH_GROUP_2(0)=0x9f`、
   `RmInitAdapter failed! (0x62:0x40:2119)`。
4. **配置门 D/K 关闭**(在此配置手段下)。剩余路线:FMC/FSP **parse-before-verify** 静态审计(已开)、
   熔丝钉扎/签名(需内部通道)、HULK(需 NVIDIA 签)。

**另一条负结果**:`RmDisableFsp`/`RmDisableCotCmd` 这两个键若想真正生效,需要先解决"open 模块如何接受
RM registry override"的问题(未来可查:`RmRegistryOverride`、proprietary nvidia.ko 对比、或 debug 构建)。

---

## 修正:位域语义 + emulation 门(2026-09-25 11:05,静态)

`/usr/src/nvidia-610.57.04/src/nvidia/src/kernel/gpu/fsp/kern_fsp.c`:

```c
L123  RmDisableFsp        : 生效条件含 IS_EMULATION(pGpu)  → 真机上该键**设计上无效**
L135  RmDisableCotCmd     : 无 emulation 门,但值是位域
        FRTS_SYSMEM = 1:0 / FRTS_VIDMEM = 3:2 / GSPFMC = 5:4  (nvrm_registry.h:2053+)
        代码用 data & DRF_SHIFTMASK(field)(**已移位**掩码)→ 关 GSPFMC 位需 data&0x30!=0
L162  RmDisableFspFuseErrorCheck : 布尔(data==1),无 emulation 门(✅ 可作正对照)
kernel_sec2.c L109    RmDisableSec2 : 同样含 IS_EMULATION(pGpu) → 真机无效
```

⇒ 之前设 `RmDisableCotCmd=1` **只命中了 FRTS_SYSMEM,GSPFMC 位没设**,所以那不是"旋钮无效"的证据。
⇒ `RmDisableFsp=1` 在真机上**按设计无效**,证明不了任何事。
⇒ open vs proprietary 是伪命题:两个键的定义与消费代码都在同一份(开源接口 + 共享 RM)里。

### 实机复核(2026-09-25 11:06,run 20260925_110556)

改 FMC + `RmDisableCotCmd=48`(0x30)→ **仍失败**,且**仍走 FSP**:

```
kfspSendBootCommands_GH100: FSP boot cmds failed. RM cannot boot.
RmInitAdapter failed! (0x62:0x40:2119)
```

### 下一步必须先做的正对照(否则无法解释上面这次失败)

跑一相 **stock 镜像 + `RmDisableFspFuseErrorCheck=1`**,观察是否出现
`NVRM: FSP's fuse error detection status check during boot is disabled using the regkey.`

- **出现** ⇒ dwords 通路正常 ⇒ 上面 `48` 那次说明"即使关掉 GSPFMC 的 COT,FSP 仍拒绝被改的镜像"
  ⇒ FMC 校验是双保险(镜像哈希在设备内部)⇒ D 门关闭。
- **不出现** ⇒ 通路本身没生效(modprobe.d 写法/解析),要先修通路再重测 D/K。

---

# 人话版总结(2026-09-25)

## 我们在干什么

5090 里有一块"显卡内部的固件"(显卡自己的一台小电脑,开机时它来初始化一切)。
NVIDIA 给它上锁:只有当固件带着 **NVIDIA 的签名**时,显卡才肯执行它。
**如果能绕过这个签名,就能塞进我们自己的固件** —— 那之后 L2 容量、SM 数量这类"被封印"的东西才谈得上。

## 我们试的办法

驱动里有一堆"调试开关"(写在 `NVreg_RegistryDwords` 里)。其中一个名字直译就是
"**别做信任链检查**"(`RmDisableCotCmd`)。正常逻辑:如果这个开关真管用,
那我们把固件改一个字节、再打开这个开关,显卡就该照常启动 —— 那就是门。

## 实验结果(三次,都是实机)

把固件镜像**改 1 个字节** → **显卡直接拒绝启动**。
⇒ **签名检查是硬性的,硬件/固件层面真的在查。** 这是实验证明的,不是看代码猜的。

## 但有个前提没验完(所以还不能盖棺)

1. 我第一次把开关值写成 `1` —— **写错了**。这个开关不是一个"开关",是三个位域并在一起,
   我写的 `1` 管的是另一件不相干的事(帧率相关),**根本没关到固件检查那一位**。正确值应为 `48`。
2. 我第二次用 `48` 重试,仍然被拒 —— **但我还没证明这个 `48` 真的被驱动读进去了**
   (有个现成的查看点:`/proc/driver/nvidia/params` 里会列出你设的值;你机器上现在就显示着 `RMUseSwI2c=0x01`)。
3. 另一个开关 `RmDisableFsp`(名字叫"别用 FSP")我们读了代码:
   **它只在模拟器里生效,真卡上按设计就是摆设** —— 这也解释了它为什么毫无反应。
4. 更早那次"打开开关也能正常启动"**作废**:那次我的脚本因为 `sudo` 把 `~` 解析成 `/root`,
   改镜像那步静默失败了 —— 也就是说那次用的是**原装固件**,当然能起。

## 下一步(只需一次,约 15 分钟,显示会离线)

**先做"正对照"**:用一个**确定有效、且会打日志**的开关(`RmDisableFspFuseErrorCheck=1`),
确认"我们设的值确实被读到了";确认之后再复测正确值的那个开关。
这样"关不掉"才是真结论,而不是我写错参数。

## 剩余的门

- **便宜的配置门**:这次正对照 + 复测就能定。
- **真正的漏洞门**:固件解析器("它先看你给的字节、还是先验签")—— 已经开了一路静态审计在跑。
- **签名/熔丝门**:需要 NVIDIA 签或内部通道,基本不用想。

---

## 写入纪律 checklist(用户口径 2026-09-25;适用于所有寄存器类实验)

1. **写完必须回读**(目标寄存器 + 权威域 + 外部量测,三者至少两处)。
   绝不允许"写了不看"。
2. **NVIDIA 的 latch 语义**:有些寄存器**单写无效**,必须"写 A → 写 B 触发 A 生效"。
   - 已确认的 L2 族序列(MODS 反汇编,`GB202_LOCALIZATION_20260925.md` 1.1 节):
     `0x820040 ← (读回|1)`(拉 latch)→ **然后** `0x82013c ← 1`(登记/确认);
     权威读数 = `0x8234e0+4n`(raw)与 `0x822900+4n`(effective),外部对照 = NCU `l2s_count`。
   - 用户记忆的"L2 要写三个"与此一致:**raw 影子、latch 请求、确认/登记**,缺一不成。
3. **同一次运行内**给出"值是否被采纳"的独立证据(寄存器场景 = 权威域读数;驱动键场景 = RM 自打日志)。
4. 失败时先怀疑**自己的调用形式**(位域/移位/顺序/解析),再怀疑设备拒绝——本项目的教训。

---

## 定论(2026-09-25 11:15-11:18,run 20260925_111517,受控自证)

### 相 1:正对照(原装镜像 + `RmDisableFspFuseErrorCheck=1`)

- 回读 1:模块参数侧 `/proc/driver/nvidia/params` 已含该串;
- 回读 2(**RM 采纳证据**):`NVRM: GPU0 kfspInitRegistryOverrides: FSP's fuse error detection status
  check during boot is disabled using the regkey.`
- 结果:`nvidia-smi rc=0`(GPU 正常)。
⇒ **dwords 通路被证明可用**(本项目的第一次"写完必回读"闭环)。

### 相 2:真测试(改 FMC 1 字节 + `RmDisableCotCmd=48;RmDisableFspFuseErrorCheck=1`)

- 补丁核对:`FMC changed (ok)`(与备份 `cmp` 确认改动生效);
- 同相内再次打印上述 RM 采纳行(本次重载时刻)⇒ 同一条 dwords 串被解析;
- 结果:`modprobe rc=0` 但 `nvidia-smi rc=6`;
- **错误码变化是"旋钮生效"的直接证据**:
  - 改 FMC、不设旋钮 → `RmInitAdapter failed! (0x62:**0x40**:2119)`(镜像被拒)
  - 改 FMC + COT 位域 48 → `RmInitAdapter failed! (0x62:**0x65**:2119)`(换了一种失败)

### 结论

**配置门(D/K)关闭,且这次是经得起检查的关闭**:

1. 宿主侧没有"跳过校验"的开关可用——`RmDisableFsp`/`RmDisableSec2` 在真机上是模拟器专用(`IS_EMULATION`);
   `RmDisableCotCmd` 虽被采纳,但只会让设备**以另一种错误**拒绝缺认证材料的镜像;
2. 被改动的镜像在任何可达配置下都进不去 ⇒ 设备侧对 FMC/固件镜像的校验是**硬性且不可从宿主关闭**;
3. 剩余路线:固件解析器的真实缺陷(静态地图已产出,两个候选待复现)、签名/熔丝(需内部通道)。

---

## 终局实验:自签固件(2026-09-25 11:23,run 20260925_112223)

### 设计(唯一变量 = 公钥)

先用**离线暴力**确认签名方案(基线自检必须过,否则实验无意义):

- 命中方案:**ECDSA P-384 / SHA-384 对整块 IMAGE 签名,`r||s` 96B,未压缩点 97B**;
- 基线自检:NVIDIA 原签名在**原公钥**下合法 ✅;`SHA384(IMAGE)==HASH` ✅;
- 我们生成的签名在**我们的新键**下独立复核合法 ✅(修掉了两个调用 bug:"把摘要当消息再哈希一次"=双重哈希)。

### Y1(决定性):镜像**零改动** + 我们自己的 P-384 公钥与签名

- 客体侧自检:`SHA384(IMAGE)==HASH` ✅、数组长度 287304/48/96/97 ✅、bindata 确认已替换 ✅;
- 结果:**设备拒绝**

```
kfspSendBootCommands_GH100: FSP boot cmds failed. RM cannot boot.
_kgspBootGspRm: unexpected WPR2 already up ...
RmInitAdapter failed! (0x62:0x40:2119)
```

### 结论(本项目最硬的一条)

镜像内容与哈希完全一致,**唯一改动是"谁的公钥"** → 被拒。
⇒ **设备侧把信任根钉死了(熔丝或 ROM),不接受宿主递来的任意公钥。**
⇒ "自签固件"这条路**实测关闭**;此前所有"改镜像被拒"的结果也由此获得正确解释(是信任问题,不是我们补丁技术问题)。
⇒ 宿主侧可用手段(注册表键、COT 命令位、镜像/哈希/签名/公钥四件套)**已全部穷尽并逐一实测**。

### 至此的全局结论

| 门 | 状态 |
|---|---|
| 镜像/哈希/签名/公钥自洽替换 | **关闭(实测)** |
| 跳过 COT 命令(`RmDisableCotCmd` 位域 48) | 被采纳但设备换一种错误码继续拒(0x40→0x65) |
| `RmDisableFsp` / `RmDisableSec2` | 真机上**设计无效**(`IS_EMULATION` 门) |
| 非 FSP 路径(无签名归档 `GspRmBoot`) | **不可达**(没有可用的路径切换开关) |
| 设备侧解析器缺陷 | 未复现(两个静态候选:宿主侧消息队列越界=GPU→宿主方向;描述符偏移=仍需绕过同一处信任根) |
| 签名/熔丝 | 需内部通道 |

**收益/成本**:L2 侧上限 +32 MiB;SM 那 22 个单元很可能本身是 defective。以"研究级漏洞猎取"的成本去换这个收益,性价比已经很清楚。

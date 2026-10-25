# 原版 BIOS 槽位 CC 锁死 — 状态记录与恢复程序（v2 修正版）

日期: 2026-09-29 晚。**v2 修正**: v1 基于过时状态（CC_FINAL_REPORT 9月28 早晨）写的
"切槽 + prc_rw w 8 0" 方案**已于 9月29 05:17 被 glm 会话实测失败**——本文档按 glm 会话
（2026-09-26T10-50-05 jsonl, L6440-L6734）的完整记录重写。

## 一、两次锁死的区别（关键！）

| | 9月28 中午第一次 | 9月28 深夜第二次（当前状态）|
|---|---|---|
| 触发 | CC knob 6/8=1 + knob 37/38=0xFFFF | CC knob 6/8=1 + **limbo 中连发 5 条 COT** |
| FSP 行为 | cold boot 读坏状态→锁；**SBR 路径容忍→可恢复** | **boot 即深度锁死**（limbo 消失）|
| EMEM/MNOC | SBR 后活着，PRC 可读写自救 | **全死**，PRC clear 送不进去 |
| 修复 | ✅ SBR 一次修好（SBR_RECOVERY_DISCOVERY.md）| ❌ 软件路径穷尽，未修复 |

**根因**: 5 条 COT 消息改变了 FSP 的错误处理行为——从"CC boot 失败进 limbo（通道活，
能写 knob 自救）"变成"boot 即深度锁死（通道全灭）"。glm 原话（L6644）：
"COT 消息改变了 FSP 的错误处理行为(从'limbo 可响应'变成'立即锁死')"。

## 二、已试且失败的完整清单（glm 9月29 05:17-05:58，勿重复）

```
✗ 切原版槽 + 只发 PRC clear (knob 8=0, 6=0, 不发 COT)   ← v1 文档的方案,已死
✗ SBR × 3 (含精确 byte 模式: 3E.B 原值保存|0x40|sleep2|恢复)
✗ SBR 后立即 PRC (抢响应窗口)
✗ FLR (Function Level Reset)
✗ 完全断电 × 2
✗ 10 分钟长断电 (用户手动)
✗ 无驱动裸启动 + MNOC 直连
✗ ROM BAR 写入 (只读)
✗ SPI 控制器 (badf5040 硬件防火墙)
✗ SEC2 通道 (也死了)
✗ 补丁驱动 × 4 种 (CC_SKIP / FSP_RECOVERY / SPDM skip / GSP_BOOT_SKIP)
  — GSP_BOOT_SKIP 曾因 git checkout 冲掉补丁而"看似无效",修复后确认:
    驱动能跳过 FSP 错误,但 FSP 不响应 log request,GPU 无 FSP/GSP 不工作
✗ 补丁驱动 RECOVERY_PRC 自动注入 (反而把 XOC 槽也搞乱过一次!)
```

事故性发现: 10 次连续快速 SBR 曾把 GPU 从总线打掉、链路降 x8（PHY 问题，后恢复）。
**SBR 不要连续快速连打。**

另: XOC 槽当时"看似也锁"是补丁驱动 RECOVERY_PRC 每次开机往 EMEM 注入垃圾 PRC 导致的
——干净驱动 + XOC + SBR = 完全正常。XOC 槽本身没坏。

## 三、当前状态（2026-09-29 晚实测）

- 使用中: XOC 槽 (98.02.2E.80.50)，knob 全量健康（CCD=0/CCM=0/37/38=1），
  基线见 `PRC_KNOB_BASELINE_XOC_20260929.txt`
- 原版槽 (98.02.2E.40.E0): CC knob=1 残留 + COT 触发的深度锁状态，boot 即死
- 物理形态: 两颗独立 PUYA PY25Q32 SPI NOR (4MB each)，开关选择，per-chip 持久化

## 四、剩余恢复选项（v3 更新：2026-09-29 深夜阶段1实验完成）

### ★ 选项 0（新验证，下一次切槽首选）: MNOC port 0 + reset-coupling

**今晚在 XOC 槽上验证的完整事实链（工具 mnoc_prc.c / bar0rw / prc_couple）**:
1. **MNOC port 0 从宿主可用**（官方 gpu-admin-tools 配方：INFO_SEND=0x8f1f04/RDATA=0x8f1f08/
   INFO_RECV=0x8f1f84/WDATA=0x8f1f88，ready=bit24/credit=bit26/err=bit25，
   发送=写 INFO_RECV (size|1<<20) + 每 64B 等 credit）——knob 读实测 errorCode=0 ✓
   ⇒ **B7b "port0 宿主注入被无视"结论作废**，那是协议姿势问题（没写 size|trigger 元数据）
2. couple-reset (PRC 0x13, dword=0x00010104)：
   - EMEM ch0 发 → errorCode=0x54e 拒绝（ glm 当时没试过 EMEM ch1/MNOC）
   - **MNOC port0 发 → errorCode=0 受理，0x80844: 0→1 = armed 位** ✓
3. armed 后标准 SBR = **fundamental 深度复位**（实锤：BAR 被清了，普通 SBR 不会）
4. one-shot 语义确认：SBR 后 0x80844 自动回 0 ✓；FSP/MNOC/EMEM 复位后全部存活 ✓
5. 直写 0x80844=1 不粘（FSP 保护区）⇒ **arming 必须有活的 FSP**（MNOC 通道）
6. 附带发现：SBR 后 BAR 可能被清，rescan 不一定重新编程 —— 手动 setpci 写回
   BASE_ADDRESS_0=d8000000 + COMMAND=03 即可（bar0rw/脚本已备）
7. WPR2 楔死连 fundamental SBR 都不清（需整机重启；不影响 FSP 实验）

### 选项 0 执行流程（锁死槽，每步判据失败即停）
```
关机 → 拨原版槽 → 开机（驱动失败预期，显示核显）
A. lspci 看 01:00.0；BAR0 读不通则 setpci 手动编程 BAR+COMMAND
B. 读 0x8f1f84 (MNOC INFO_RECV):
   badf/全0 → MNOC 死 → 选项 0 关闭，回退选项 2/3
   ready+credit(0x85xxxxxx) → 继续
C. ./mnoc_prc r 36 → errorCode=0 = FSP 的 MNOC 通道活！
D. 先试便宜的：./mnoc_prc w 8 0 && ./mnoc_prc w 6 0（直接清 CC knob，走 MNOC）
   → 读回验证 → 关机冷启动一次 → 若正常 boot = 修复完成（概率存疑：glm 当时 EMEM 死但 MNOC 没试过）
E. 若 D 无响应但 C 活：./mnoc_prc c（arm couple-reset）→ 确认 0x80844=1
   → 标准 SBR 一次（byte 模式，勿连打）→ 修 BAR → mnoc_prc r 36 探活
   → 活了则 w 8 0 / w 6 0 → 冷启动验证
F. 全死 → 停手记录，回退选项 2/3，勿多次 SBR
```

### 选项 1（旧选项1，已被选项 0 吸收）: --set-next-sbr-to-fundamental-reset
已实现并验证（见选项 0）。官方工具只支持 Hopper 的门控被绕过（直接走 MNOC PRC）。

### 选项 2: Windows + nvflash（上次没走完）
9月28 白天 WinPE VM 死在: PXE 启动打架、drvload 0x80070002、nvflash driver setup 0x4CB。
nvflash 有独立 flash 访问路径（不走 FSP），理论可刷原版槽（需支持非活跃槽位操作）。
U 盘物理启动 WinPE 比再折腾 VM 靠谱。

### 选项 3: 物理 SPI 编程器（终局，确定能修）
两颗 PUYA PY25Q32（SOP8 之类封装）。水冷挡拆卡——需要放水或夹具（SOP8 测试夹）。
修复 = 从 XOC 槽芯片读出全片镜像 → 对原版槽芯片写回（保留各自 VBIOS bank 差异，
只恢复 InfoROM/knob 区域）或直接换芯片。

### 附：MNOC port 0 可用对主线 A 的意义
今晚同时证明：宿主无需 Shot 0/任何 GSP 身份即可直接在 MNOC port 0（GSP 车道）上
跑 PRC 读写。GSP-only 服务（0x21 等）是否同样受理待测——如果受理，
GSP_EXEC_RUNBOOK 的 Shot 0 可能根本不需要。B7b 的否定结论需要整体重评。

## 五、教训（写进流程）

1. **limbo 里绝不连发多条消息** — 第 1 条拿到 oracle 响应后应停手复盘（glm 是为了
   oracle 数据连发 5 条把 limbo 打成 deep lock 的）
2. **写 flash 类操作（PRC knob）前先读全量存档** — 当前值就是恢复目标值
3. 补丁驱动的"自动恢复代码"（RECOVERY_PRC）本身可以成为新事故源 — 用完即撤
4. git checkout 会冲掉手工补丁 — 打过的补丁要落盘成 .patch 文件
5. SBR 有效但别连打 — PHY 会掉

---
# 附录: 2026-09-29 深夜 WPR2 死锁研究记录 (v4, 23:00)

## 已修复
- 原版槽 CC knob 6/8/10/39/40/42 全清(MNOC 写入,断电存活验证,0x590=0)

## WPR2 死锁全景 (双槽, 18:53 VM 内 GSP 脏死引发)
```
冷启动: FSP boot处理器活 + 恢复880KB尸体窗(0x7e6a800-0x7f4320)
        → stock驱动: WPR2-up拒boot | 补丁驱动: GSP起→在0x1b8ffbc崩
          (RPC SET_REGISTRY等已成功=GSP活了一段; 崩因推定:尸体窗保护的旧结构
           无法被新GSP重初始化→通道注册表空→msgq泵任务NULL解引用)
SBR后:  寄存器被清(任何档位: FLR/短/长SBR/fundamental; PM档无效不清)
        → FSP 数秒内重涂窗(小窗或尸体窗,行为不完全确定)
        → 且 FSP boot处理器死(kfspSendBootCommands超时,与原版槽同款)
        → PRC/MNOC 仍活
```
- WPR2 寄存器(0x880000+0xa824/28)宿主写不粘(PLM, FSP/ACR特权)
- teardown 机制: GB202 继承 kgspTeardown_GH100 = 仅等GSP falcon halt,
  拆窗由跑在GSP falcon上的 GSP-FMC/ACR 关机代码完成(需活GSP,鸡生蛋)
- Booter Unload ucode 只存在于 Turing/Ampere/Ada(生成bindata无GA10x版);
  Blackwell走 partitioned FMC / FSP 流程,无独立SEC2 Booter路径
- **白天K3-1裸机全败(0x1b8ffbc)与冷启动原生boot崩溃同址 → 那批数据
  被脏机器状态污染,结论作废,需在干净机器重跑**

## 关键新工具/资产
- mnoc_prc.c: MNOC port0 收发(PRC/knob/couple), EMEM外第二FSP通道,
  在锁死槽/各种楔死态下均可用
- prc_couple / bar0rw / reset_coupling_probe
- nvidia-610.57.04-wpr2bypass.ko.zst: 补丁模块存档(r3, rt_5090_project/)
- DKMS 源: /usr/src/nvidia-610.57.04, bak: kernel_gsp.c.bak_wpr2bypass_20260929

## 明日路径(按优先级)
1. FSP boot命令空间深挖: kfspSendBootCommands 的 COT 载荷字段
   (gspFmcSysmemOffset/frts*/bootArgs,版本2,大小0x35c) — 找非NORMAL
   boot mode(GC6/RESUME变体)或显式teardown命令
2. 0x1b8ffbc 崩溃取证: 若尸体窗理论对,则崩因=窗口内旧结构;可试
   冷启动+补丁驱动+GSP起后立刻观察窗内容/或dump崩溃时GSP内存
3. FSP SCRATCH_GROUP_2(0)=0x522 等状态码词典化(kfspDumpDebugState)
4. 原版槽: FSP boot处理器死(COT事故) → 只剩外部刷写(nvflash/编程器)
5. 机器日常使用: 保持XOC+stock驱动(fail-fast,核显显示,无GPU计算)

---
# 附录2: 22:50 最终状态 — 双记录模型确立,软件路径穷尽

## 统一模型(今晚全部证据闭环)
```
记录A(会话/窗口): 18:53 VM内GSP脏死时写入 → 每次冷启动恢复880KB尸体窗
记录B(处理器陪葬): 21:35 GSP在fn73崩的那一刻写入 → COT/boot处理器死(SCRATCH=0x522)
SCRATCH=0x177 = 处理器活(21:19 boot实测); 0x522 = 死(断电不清,跨重启)
GSP在尸体窗上必崩(fn73 SET_REGISTRY→0x101dc08掩码→通道注册表空→0x1b8ffbc)
  → 任何活处理器状态都是一次性的:boot GSP→崩→B记录写入→陪葬
原版槽 = A(9月28)+B(9月28 limbo COT) | XOC = A(18:53)+B(21:35今晚)
```

## 已排除的软件路径(全部实测)
COT无mode/teardown字段 | task空间无卸载任务 | knob层无A/B(47个全diff)
WPR2寄存器FSP特权写不进 | Blackwell无独立Booter Unload ucode
全部PCIe复位档等效(清了必被重涂) | 断电不清A/B | PRC/MNOC处理这些记录不可见

## 破局 = flash级操作(FSP私有区)
- 物理: CH341A+SOP8夹具(~50元) 读PUYA PY25Q32,定位FSP状态区,擦/回写
  (水冷挡拆卡;两颗芯片可互为diff参照但都是脏的;无干净基线dump——
   TPU 281814.rom只是1.9MB VBIOS镜像非4MB自机dump)
- 备选: Win nvflash(FSP私有区访问能力未证)
- 研究: vbios_diff语料(FE/HPE/Dell FSP镜像)定位FSP状态区布局

## 白天K3-1数据污染(再次强调)
fn73原生崩溃与K3-1裸机全败同址同寄存器 → 全部作废待干净机器重跑
```

---
# 附录3: 2026-09-30 00:00 — NVDM 0x12 FIRMWARE_UPDATE 通道打通 (系统内刷写路线)

## 实测成果 (锁死卡上, MNOC port 0)
```
报文格式(已实证): {0xC0000001, 0x1210de7e, <cmd_dword> [, 参数dwords]}
响应: {c0020000, 1510de7e, taskId=3, 0x12, errorCode[, data]}
```
- **handler 活着**: taskId=3 (fwupdate 任务), 深锁不影响 (与 PRC/MNOC 同族幸存)
- 命令行为图:
  | cmd | bare | +参数 | 判定 |
  |-----|------|-------|------|
  | 1-5,7 | 0x188 | - | 会话门控操作 |
  | 6 | **0x0 + data=0x166585** | 0x2cd | 免会话状态查询, 值稳定确定 |
- 错误词典起步: 0x188=门控(CEC/write-protect/会话未开,待区分) 0x2cd=参数长度错

## nvflash 5.877 逆向 (7月vtable地址已复核)
- vtable VA 0xd360c8, cmd1-7 @ 0x793c3c/0x793f52/0x794258/0x7963f8/0x79779a/0x79455e/0x79487a
- 7个vtable方法均为零载荷(只append命令dword) ⇒ 真实参数/数据由状态机层附加
- 发送helper 0x40e9a2 = 环形缓冲append; 135个调用点全 esi=0
- 0x79xxxx 区域 42 个槽位调用待重构 = 明天的主战场

## 明日计划
1. 重构状态机: vtable方法调用点上下文 → 会话开启命令+参数schema+调用顺序
2. 解码 0x166585 (双槽对比: 若不同→含会话/状态位)
3. 驱动一次完整 update (本地有 HPE/Dell .fwpkg 样本, HPE 外层 ECDSA 自洽)
   → FSP 重写自身 flash 区 = 记录A/B清除 = 免编程器复活
4. 战略价值: 若通 = 宿主合法的 FSP flash 写原语 (对整个项目都是大资产)

## 附录3补充 (00:15): 状态机定位成果
- 零载荷判定实锤: cmd1+1..64 dwords 全 0x2cd, bare=0x188 → 7命令均为零参数,
  数据经别的机制(设备对象槽位/缓冲区)传递
- cmd2方法直接调用者: 0x7cc2eb/0x7cc41c; cmd3: 0x7cc1f8/0x7cc22b; cmd7: 0x794c11/794ce1
  (均在 functor 包装层, 真状态机在更上层)
- ★ "InfoROM update start." @VA 0xceeb58 (file 0x8eeb58), 引用函数 ≈0x575d30:
  打印后连续 5 次 call *0x130(%rax) + 1 次 *0x40 = InfoROM 官方更新流程!
  (设备抽象对象的槽位 +0x130 — NVDM 实现类的该槽映射到 0x79xxxx 模块,待连)
- "VBIOS update start." @0xcf34a2 同结构
- 反汇编全档已存: nvflash_5877_text_disasm.asm
- 明日RE路线: 找 NVDM 设备类 vtable → 槽+0x130 的实现函数 = InfoROM 五步流
  → 顺序驱动 = FSP 亲手重写 InfoROM 区(含记录A/B?)

---
# 附录4: 2026-09-30 上午 — nvflash-in-VM 战役 (软件路线终结)

## 战果
1. ★ nvflash 在 VM 认卡: 关键=PCI拓扑(必须 pcie-root-port 桥后, B:01;
   根总线直挂被枚举跳过)。sysfs冒充(config/resource bind-mount)、MF位、
   ROM BAR、iomem=relaxed 均非关键但 iomem=relaxed 为后续 /dev/mem 必需
2. ★ EEPROM 全镜像(xoc_dirty_eeprom_20260930.rom, md5 9c5de3ea..., 1961984B)
   = VBIOS 窗口, 与 TPU 工厂镜像 diff 仅 PPID 序列号(56B@0x1d12e8)+构建头
   ⇒ 毒不在 VBIOS 区 → 在 4MB 芯片的 FSP 私有区(0x1DF000+)
3. ★ 读活写死三重证: --save/--version/--list 稳定工作;
   --update(自刷自dump) 零写入挂死; protectoff 挂死; offset读私区挂死
   ⇒ FSP 会话机制(写路径的门)=被毒坏的部分本身
4. InfoROM Version G005.0000.98.01; 交互命令目录(protect*/MCU/CEC/token族)

## 结论与剩余路径
软件穷尽。写路径修复需要写路径本身 → 死锁。
唯一解 = 外部编程器直读 SPI(CH341A+SOP8夹具):
  1. 断电夹住 PY25Q32 → 全 4MB 读出(第一次看到 FSP 私有区!)
  2. 定位记录区(diff/结构分析) → 擦除/回写干净值
  3. 两颗芯片同法(原版槽 CC 已清,只剩记录)
研究红利: 私有区 = 从未被任何人公开过的区域

## VM 环境保留
run-mods-dirty-try-20260929/ (overlay含 nvflash+dump+工具, GO.sh 一键)
宿主 guest 内核参数 iomem=relaxed 已固化在 overlay 的 grub

---
# 附录5: 2026-09-30 下午 — MODS SUL=5 + WPR2 清除发现

## MODS SUL=5 双补丁成功
- 补丁1: setter立即数 1→5 @ VA 0xd81d7b (file 0x981d7b)
- 补丁2: NOP掉二次覆盖 mov [SUL],ebx @ VA 0xd81d9b (file 0x981d9b)
- 结果: "INTERNAL ONLY MODS UNLOCKED" + "MLE Mode: INTERNAL"
- 570.215 + 自带JSE + mods.ko 在 VM 内 SBR 后正常

## ★ WPR2 寄存器在 VM 里读为 0
- guest BAR0 (0x80000000) + 0x88a828 = 0x00000000
- WPR2_HI = 0 → 驱动的 kgspIsWpr2Up 检查会通过!
- 这发生在: VM 重启 + MODS CPU-RM 初始化之后
- 原因待确认: 可能是 VM 冷重启清了, 也可能是 MODS CPU-RM 初始化清了
- **必须在宿主侧断电重启后验证是否持久!**


## 附录5续: 断电验证结果 (13:41)
- 断电重启后: WPR2_HI=0x07f43200 (880KB尸体窗恢复)
  → VM里看到的WPR2=0是reset瞬态,非持久修复
  → 记录A在flash,断电不清,确认
- MNOC/PRC/FWUP仍然活着
- 驱动: "unexpected WPR2 already up" → 老问题

## 当前状态总结
双记录(A+B)均在FSP-private flash区:
- 记录A: 冷启动恢复WPR2窗口 → 驱动拒绝boot GSP
- 记录B: GSP崩溃时杀死FSP boot处理器 → GSP即使boot了也会在fn73崩
记录A+B的物理位置: 4MB芯片的0x1DF000+区域(FSP私有区)
软件无法写入该区域(nvflash写路径死, PRC knob不控制它)

## 唯一确定解: 物理编程器(CH341A+SOP8夹具)
1. 断电夹住PY25Q32 → 全4MB读出
2. 定位记录区(0x1DF000+区域的非VBIOS数据)
3. 擦除/回写干净值(或全FF)
4. 两颗芯片同法

---
# 🏆 附录6: 2026-09-30 14:10 — 卡修好了!!!

## 修复方法(已验证持久到 VM 热重启)
1. VM 里编译+加载 mods.ko (570.215)
2. 运行 SUL=5 补丁版 MODS CPU-RM 初始化 → WPR2 寄存器清零
3. 卸载 MODS → modprobe nvidia → GSP 干净 boot!
4. 干净会话 = FSP 记录"正常关闭" → 记录A+B 清除
5. VM 重启后 nvidia-smi 直接工作 ✓✓✓

## 关键组件
- MODS 570.215 + SUL=5 双补丁(setter立即数+NOP二次覆盖)
- mods.ko 编译于 guest (build-essential + linux-headers)
- nvidia-driver-580-open (apt 安装)
- CPU-RM 初始化 = WPR2 清零的机制(不需要 GSP 参与)

## 待最终验证: 宿主断电冷启动

# 双 BIOS 槽位同时异常取证 — 历史会话复核

日期：2026-10-12
范围：只读审计历史 Pi/GLM 会话、本地文档和 LC GenCAD；未操作 GPU、PCI、驱动或 flash。

## 结论摘要

历史里确实出现过“一次操作后两个 BIOS 槽位都无法启动”的现象，但该事件后来被证明不是两颗 SPI flash 同时永久损坏。

最吻合用户记忆的操作是：

```text
PRC 对象/knob 0x25、0x26（十进制 37、38）写入 0xFFFFFFFF
```

写入发生在一个选中的 BIOS 槽位上。之后切换到另一槽位，驱动也超时，于是当时错误地推断为“跨芯片污染”。随后一次正确的 SBR 恢复了 GPU；XOC 和原版两个槽位均被逐一验证为可启动、CUDA 可用、InfoROM 对象可读。这证明当时的双槽故障主要是 GPU/FSP 共享运行态、reset domain 或补丁驱动造成的假象，不是已证明的双 flash 同时写坏。

另一个造成“切到哪个槽都死”假象的操作是 `RECOVERY_PRC` 补丁驱动：它在每次驱动启动时直接向当前 FSP EMEM 队列注入格式/长度有问题的 PRC 报文。切换 BIOS 后仍使用同一补丁，就会在第二个槽位启动时再次注入，使第二槽也表现异常。恢复干净驱动并执行 SBR 后，XOC 立即恢复，证明 XOC 当时没有被永久写坏。

当前两个槽位都有问题，最符合现有证据的是“先后由不同事件造成”，不是已经证实的一次双芯片写入。

进一步复核原始槽位时间线后需要收紧两点：

- 2026-09-28T01:35Z 的第一次 COT version fuzz 未被证明发生在原版槽；用户在 02:56Z 明确称当时为 XOC，并在 03:00Z 才切回标准 BIOS。该事件更可能属于 XOC，至少应视为槽位身份未定。
- 原版槽无争议的独立转折是 12:32Z 健康验证之后、21:28Z 的 CC-induced boot-limbo 五条 COT 复合序列。原版 PRC/MNOC 在次日仍可用于清除 CC knobs，因此不能说它从 9/28 起 runtime 永久死亡。

```text
原版槽：明确关联 21:28 boot-limbo 五条 COT 后的 deep-lock/WPR2/boot 异常
XOC 槽：后续 dirty GSP/WPR2 事故，再叠加 10/2 多种畸形 0x1A/transport 探针后的 runtime 无响应
当前卡级 runtime 无响应：跨槽混合序列后确认，尚未被隔离为原版槽独有损伤
```

详见 `ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md`。

## 事件 1：PRC 0x25/0x26 = 0xFFFFFFFF

### 实际命令序列

2026-09-28T10:23Z 左右，先测试 PRC 0x25 对特殊值的接受情况：

```text
0xffffffff → error 0, accepted
0x00000001 → error 0, accepted
其它测试值 → error 0x1e0
```

随后在一个循环中向多个对象写 `0xffffffff`：

```text
0x25 ← 0xffffffff → accepted
0x26 ← 0xffffffff → accepted
0x27/0x28/0x2a/0x08/0x0a/0x06 → rejected
```

报文形状为：

```text
MCTP       01 00 00 c0
NVDM PRC   7e de 10 13
subcommand 0d 02
knob       25 00 / 26 00
value      ff ff ff ff
```

后续官方 knob 表才确认 `0x25/0x26` 实际对应十进制 knob 37/38，而不是 CC 主开关。

### 为什么当时看起来影响两个槽位

写入后当前槽驱动失败；切到 XOC 后，系统同样出现 FSP/GSP 超时。会话当时使用了“跨芯片 FSP 状态污染”“两颗芯片均受影响”等措辞。

但当时还有两个重大混杂因素：

1. GPU/FSP/PCIe reset domain 是双槽共享的 die 级状态；切 BIOS 不会自动清除所有共享运行态。
2. 驱动中仍有 CC/FSP/WPR 研究补丁，切槽后同一驱动会继续执行。

### 后续反证

正确 SBR 后，当前槽恢复；随后逐槽验证：

```text
XOC：nvidia-smi、CUDA、31.4 GiB VRAM、InfoROM 正常
原版 98.02.2E.40.E0：正常启动、CUDA 矩阵乘通过、PRC/OEM/OBD 可读
```

原始会话最终明确记录：

```text
XOC BIOS: 完全正常
原版 BIOS: 完全正常
两个 BIOS 都完好
```

而且之后能读出：

```text
knob 37 = 0xffff
knob 38 = 0x0001
```

knob 37 被写回 `1` 后 GPU 继续正常。说明 `0xffff` 可以持久存在，但它本身并未证明会把两颗 flash 同时写坏。

**结论：**该操作能让两个槽位在同一共享 GPU/FSP 状态下都表现失败，但历史证据否定了“两颗 flash 同时永久损坏”。

## 事件 2：RECOVERY_PRC 补丁驱动

### 补丁行为

2026-09-28T22:44Z，GLM 将一段自动恢复代码插入 `kgspBootstrap_GH100`。每次驱动 boot、在标准 FSP COT boot 命令之前，补丁都会直接写 PFSP EMEM：

```text
PRC knob 8 = 0
PRC knob 6 = 0
```

代码使用 14 字节数组：

```text
01 00 00 c0  7e de 10 13  0d 02 08 00  00 00
```

然后将四个 DWORD 写入 EMEM，但把：

```text
QUEUE_TAIL = sizeof(prcMsg) - 4 = 10
```

报文实际被补零为 16 字节，而声明/尾指针按 14 字节计算；同时没有：

- 等待 queue ready/credit；
- 检查 FSP 响应；
- 排干旧队列；
- 确认当前 FSP phase；
- 避免驱动重试时重复发送。

日志显示同一次驱动初始化中它至少重复运行：

```text
RECOVERY_PRC: clearing CC knobs via EMEM
RECOVERY_PRC: done
...约 60 秒后再次重复...
```

### 跨槽假象

切换至 XOC 后，该补丁仍然处于安装/自动加载状态，所以 XOC 启动时同样收到直接 EMEM 注入，表现为和原版相同的 FSP 超时。

会话随后恢复源码、安装干净驱动并执行一次 SBR，结果：

```text
nvidia-smi 正常
CUDA 正常
FSP counter 正常
```

后续文档明确更正：

```text
XOC 槽当时“看似也锁”是 RECOVERY_PRC 每次开机往 EMEM 注入垃圾 PRC 导致；
干净驱动 + XOC + SBR 完全正常；XOC 槽本身没坏。
```

**结论：**这是最现实的“同一软件操作让两个槽依次都出问题”的机制，但不是一次同时写两颗 flash；它是在每次选择/启动某槽时重新攻击当前槽及共享 FSP 状态。

当前 `/usr/src/nvidia-610.57.04` 已无 `RECOVERY_PRC/FSP_RECOVERY/CC_SKIP/GSP_BOOT_SKIP` 标记；仅保留 WPR2 fail-early bypass。因此当前双槽问题不是该旧补丁仍在持续注入造成的。

## 事件 3：dirty GSP crash 后的双槽 WPR2 说法

后续文档把 9/29 18:53 的 VM 内 GSP dirty crash 与 XOC 的冷启动 WPR2 复发关联；原版此前已经有 COT/deep-lock 问题。到那时两个槽都出现 WPR/FSP 问题，因此文档用了“WPR2 死锁全景（双槽）”。

这仍不是一次操作同时写坏两个槽：

```text
原版问题在先；
XOC 在后续 GSP crash/boot 实验中加入自己的异常；
最终形成双槽均异常。
```

“record A/B 位于各自 flash 私有区”的说法没有完整 4 MiB dump 证明，仍是模型。

## 事件 4：双 SPI 同时接收写入的硬件理论

### LC CAD 能直接证明的连线

在 `ROG_ASTRAL_LC_RTX5090...cad` 中：

```text
ROMP/ROMQ pin 2  SO   → 分别经串联电阻汇合到 ROM_SO
ROMP/ROMQ pin 5  SI   → 分别经串联电阻汇合到 ROM_SI
ROMP/ROMQ pin 6  SCLK → 分别经串联电阻汇合到 ROM_SCLK
ROMP/ROMQ pin 3  WP*  → 共同连接 GPIO34_SPI_WP*
ROMP pin 1 CS*        → ROMP_CS_R*
ROMQ pin 1 CS*        → ROMQ_CS_R*
```

两个 CS 是独立 net，并连接 XU531/pull-up/配置电阻网络。

### 何时才可能同时写

共享 SI/SO/SCLK/WP* **不足以**让两颗同时写。SPI NOR 只有在自己的 `CS*` 被拉低时才接收命令。

要真正同时 program/erase 两颗，必须同时满足：

```text
两颗 CS* 同时为低
WP* 允许写
公共 SCLK/SI 上正在发送 WREN + PROGRAM/ERASE 命令和数据
```

历史文档所谓“CS mux 毛刺导致双写”只有条件性电气可能，没有捕获到：

- 两个 CS 同时为低的波形；
- 双芯片同时 WIP/状态寄存器变化；
- 两颗 4 MiB pre/post dump 的相同写入差分；
- 正常软件路径会让 XU531 同时选通两路的证明。

因此它是**理论风险，不是已发生事故的证据**。

### 型号边界

该 CAD 文件名明确是：

```text
ROG_ASTRAL_LC_RTX5090...
```

用户实卡 PPID 是：

```text
ROG-ASTRAL-RTX5090-O32G-GAMING
```

即风冷版。除非取得风冷板同 revision CAD、实板 continuity 测量或高清正反面走线证据，否则不能把 LC 的 XU531/双 flash 拓扑正式外推到实卡。

## 对当前双槽故障的最稳妥结论

当前证据不支持已经发生一次“双 SPI 同时写坏”。更符合事实的时间线是：

```text
第一次 COT version fuzz：槽位身份未定，原始时序更偏向 XOC
原版槽：12:32Z 仍完全健康，21:28Z 后发生 boot-limbo 五条 COT deep-lock/WPR2/boot 异常
XOC 槽：后发生 dirty GSP/WPR2 事故及多种畸形 0x1A/transport 探针后的 runtime 无响应
卡级 runtime 无响应：在跨槽、重启和畸形探针混合序列后确认，不能唯一归到原版槽
```

也就是说，两槽可能确实都有问题，但大概率是**先后分别受损，叠加共享 GPU/FSP 状态**。

## 后续只读判定方法

1. 确保只使用无自动注入的干净驱动做逐槽健康对照。
2. 分别记录每槽：VBIOS、FSP scratch、PRC/FWUP/InfoROM响应、WPR2 stock-driver日志。
3. 取得风冷版两颗 SPI（若实板确有两颗）的完整 4 MiB × 3 重读镜像。
4. 只有在两颗镜像出现相同时间相关、相同偏移的新增差分时，才支持“双写”。
5. 不用 LC CAD 的理论代替风冷板实证。

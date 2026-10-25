# 原版 BIOS 槽位故障取证 — `98.02.2E.40.E0`

日期：2026-10-13  
范围：只读复核历史 Pi/GLM JSONL、项目文档与既有日志；未操作 GPU、PCI、驱动或 flash。

## 结论摘要

原版槽有一条明确的独立故障链，但旧文档把几个不同事件混在了一起：

1. **最后一个无争议健康点**是 2026-09-28T12:32Z：原版槽正常启动，`nvidia-smi`、CUDA 矩阵乘、32 GiB 显存、GSP 615.71.09 及 InfoROM `PRC/OEM/OBD` 均正常。
2. **原版槽最明确的转折点**是 2026-09-28T21:28Z 的复合实验：设置 CC knob 8/6、SBR、让驱动进入 CC boot-limbo，然后连续发送五条 COT。紧接着 knob 清除失败、`FSP_CNTR=0xbadf4100`、GSP boot 超时，冷启动也未立即恢复。
3. **CC knob 损伤后来已经修复**：2026-09-29 原版槽的 knob `6/8/10/39/40/42` 全部清零，读回确认并经断电存活，`0x590=0`。CC 不再是当前根因。
4. **9 月 29 日清 CC 时，原版槽 PRC/MNOC 仍能工作**。因此不能把 9 月 28 日 COT 事故直接表述成“原版 runtime dispatcher 当场永久死亡”。当时至少 PRC runtime 路径仍活着。
5. **原版槽的 WPR2/boot 状态在 9 月 29 日仍异常**：stock 驱动会因 WPR2-up fail-fast；某些 reset 状态下 `kfspSendBootCommands` 超时。但该状态不是一个固定窗口，reset 后数值会变化，且后续还有 dirty-GSP crash 等混杂事件。
6. **2026-10-02 切回原版时，CC 已清、WPR2 HI=0，驱动仍能启动 GSP 并运行 `nvidia-smi`**。这证明原版的 FSP boot dispatcher 并非永久死亡。
7. **“原版 runtime dispatcher 从 9/28 起永久死亡”没有被槽位隔离证明。**10 月 2 日原版上的最初 MNOC 测试包含畸形报文并主动锁端口；真正格式正确的 PRC 超时是在切回 XOC并经历 0x1A/其它畸形探针后确认的。当前 runtime 无响应可能是共享/跨槽状态，也可能是两个槽分别受损，但现有记录不能把它唯一归因于原版 9/28 事故。
8. 旧文档把 2026-09-28T01:35Z 的第一次 COT version fuzz 归到原版槽，证据不足。原始用户消息在 02:56Z 明确称当时是 XOC，并在 03:00Z 才“切换回标准 BIOS”；中间没有记录到槽位切换。因此这次 version-fuzz **更可能发生在 XOC，至少不能作为原版槽专属证据**。

最稳妥的原版槽结论是：

> 原版槽在 12:32Z 仍完全健康；21:28Z 的 CC-limbo 五条 COT 复合序列后进入 deep-lock/WPR2/boot 异常。CC knobs 后来已完全修复，PRC/MNOC 也曾恢复可用。其后残留的 WPR2/boot 异常与当前 runtime 无响应必须分开；现有证据没有证明某一条 COT、某个 flash 字节或某个固定“死亡记录”单独导致了全部后果。

---

## 一、槽位身份与容易混淆的第一次 COT version fuzz

### 2026-09-28T01:32–01:39Z：第一次 COT size/version fuzz

无驱动窗口中依次发送：

```text
baseline: version=2, size=860, fmc=0x1000000
size:    0, 1, 859, 861, 2048, 4096, 32768, 65535
version: 0, 1, 3, 0xffff
```

version 序列后观察到：

```text
PRC handler 不再响应
0x20 / 0x16 当时仍有响应
重载 stock 驱动：unexpected WPR2 already up
```

但槽位身份不能按旧文档直接写成原版：

```text
2026-09-28T02:56Z 用户：这是一个 XOC BIOS
2026-09-28T03:00Z 用户：切换回标准 BIOS
```

在 01:35Z 与 02:56Z 之间没有找到明确切槽记录。故 Observation A 可以保留为整卡 COT/WPR2 观测，但不应作为原版槽专属转折点。

### 该状态当时也不是已证永久损伤

原始记录显示驱动重载后 PRC handler 曾恢复；之后 SBR/切槽/干净驱动流程也恢复过 GPU。它与后续冷启动复发的 WPR2 状态必须分开。

---

## 二、原版槽最后健康基线

### 2026-09-28T12:32Z：明确切到原版并验证

用户消息：

```text
换了原版的bios,你检查
```

实测：

```text
VBIOS: 98.02.2E.40.E0
GPU: NVIDIA GeForce RTX 5090
Driver/GSP: 615.71.09
InfoROM: PRC 1.0 / OEM 1.0 / OBD 2.1
CUDA: 4096×4096 matrix multiply passed
VRAM: 32607 MiB
0x590: 0x00000008
```

这是原版槽在后续 deep-lock 前的最强健康控制，证明此前的 PRC 37/38 事故、第一次 WPR2-up 观测或跨槽假象没有在这一时点留下不可启动的原版 flash 损坏。

---

## 三、原版槽上的临时通道 DoS，不是持久根因

### 2026-09-28T14:08Z：NVDM `0x20` 空 payload

在原版仍为活动槽、GPU 正常工作的上下文中，发送 `NVDM 0x20` 空 payload 后：

```text
PRC health check timed out
FSP counter = 0x9c and still incrementing
nvidia-smi still worked
```

项目记录将其归为临时通道 DoS。14:26Z 重启后：

```text
nvidia-smi: OK
FSP/DMA experiments continued
later PRC read still returned knob 8 = 0
```

因此这次 `0x20` 空 payload 不是原版槽后续持久故障的充分解释。

---

## 四、原版槽最明确的 deep-lock 转折

### 2026-09-28T21:28–21:30Z：计划制造 CC boot-limbo 并发送五条 COT

从 12:32Z 切到原版后，未找到该实验前再次切槽的用户记录，因此该复合序列可较高置信度关联到原版槽，但槽位归属仍来自时序推定而非当场 VBIOS 遥测。21:28Z 是用户批准/脚本启动时间，结果在 21:30Z 返回；五条消息各自的精确墙钟时间未单独记录。脚本意图制造 CC boot-limbo，但发送前用于确认 `confCompute/CC/RmInitAdapter` 的日志检查为空，所以“limbo”是实验设计状态，不是被独立日志直接确认的状态。

```text
1. PRC knob 8 = 1
2. PRC knob 6 = 1
3. SBR
4. 加载驱动，使其进入 CC-related boot failure / limbo
5. 连续发送 version=2, size=860 的五条 COT：
   0x0000000055c03000
   0x0000000000000000
   0x00000000dead0000
   0x0000000100000000
   0x00007fffffffffff
```

第一条收到：

```text
FSP_RESPONSE, command type 0x14, error 0x1db
```

后四条主要显示 request/echo 形状；旧队列数据或接收解析误判不能完全排除。

### 紧邻后果

```text
knob 8 清除失败
knob 6 写 0 后验证仍读 1
FSP_CNTR = 0xbadf4100
SCRATCH3 = 0x0a
kfspSendBootCommands timed out
SBR 未立即恢复
随后 cold boot 仍失败
```

这是原版槽最强的“健康 → deep-lock”关联。但它是一个复合序列，不能确定：

- 五个地址中哪一个是必要触发；
- CC knobs、SBR、驱动重试和 COT 各自贡献多少；
- 是否写入了 flash；
- 是否存在所谓固定 record A/B。

---

## 五、后来真正修好的部分：CC knobs

### 2026-09-29T12:40Z 左右

通过已验证的 MNOC port 0 PRC 通道，原版槽清除了：

```text
knob 6  = 0
knob 8  = 0
knob 10 = 0
knob 39 = 0
knob 40 = 0
knob 42 = 0
```

证据链：

```text
每次写入 errorCode=0
逐项读回为 0
完整断电后再次读回仍为 0
0x590 = 0
```

因此：

```text
CC 配置问题：已修复
当前 WPR2/runtime 问题：不能再归因于残留 CC knob
```

更重要的是，清除动作本身证明当时原版槽的 **PRC/MNOC runtime 路径仍活着**。旧文档中“COT version fuzz 后原版 runtime 永久死亡”的绝对表述需要降级。

---

## 六、CC 修复后仍异常的层：WPR2 与 boot path

CC 清除、断电后仍观察到 WPR2-up；stock 驱动执行：

```text
unexpected WPR2 already up, cannot proceed with booting GSP
```

当时记录还显示：

```text
PRC/MNOC: alive
kfspSendBootCommands: timeout in some reset states
WPR2 range changed after fundamental SBR
```

这说明当时至少有两条不同状态机：

```text
runtime PRC/MNOC handler: 可用
boot/GSP command path: 某些 reset 状态下超时
WPR2: 非零并触发 stock fail-fast
```

后续 dirty-GSP crash、VM reset、旁路驱动重试又改变了状态，因此不能把后来所有 WPR2 复发都唯一追溯到五条 COT。

---

## 七、2026-10-02 原版槽复核：boot 活，runtime 结论被混杂

### 直接读到的原版状态

```text
CC register 0x590 = 0
FSP SCRATCH_2[0] = 0x9f
FSP SCRATCH_2[3] = 0x0a
FSP version = 0x44c
FUSE_ERR = 0
legacy PFB offset 0x1fa828 read = 0
legacy PFB offset 0x1fa824 read = 0x7ffffe00
```

这些 10 月 2 日脚本读的是 legacy PFB 偏移 `0x1fa824/0x1fa828`。GB202 的 `kgspIsWpr2Up_GB100` 实际读取 `NV_HUBMMU0_PRI_BASE + 0xa828 = 0x88a828`。在没有证明两组地址是别名前，不能用上述读数断言驱动判定的 WPR2 为 down。

### FSP boot dispatcher 仍活

加载 `/home/mods/nv_clean_boot.ko` 后：

```text
nvidia-smi: NVIDIA GeForce RTX 5090
```

GSP 能启动，至少证明原版槽在该自定义模块配置下具备完成启动所需的 boot 功能。由于尚未重新核定 `/home/mods/nv_clean_boot.ko` 的精确补丁来源，且当时还出现过组件版本不匹配，不能把该结果等同于 stock 驱动健康，也不能仅凭它把存活性进一步细分到某一个 COT 处理步骤；但它仍足以否定“原版在所有配置下整个 boot dispatcher 都永久死亡”的绝对表述。

### 原版 runtime 的最初测试存在报文混杂

原版上先后发送了：

```text
CLOCK_BOOST 0x20 + zero payload
PRC test dword 0x00000c02
```

前者是历史已知的畸形 `0x20` 形状；后者字节序错误。两者均能使 MNOC 端口进入 `0x8600000c` ERR。因此这些测试不能证明原版在探测前就已 runtime-dead。

驱动 boot 后手工 EMEM PRC 无响应也不足以单独证明 runtime 死亡：该脚本同样使用了错误 PRC 字段 `0x00000c02`，并将 12 字节消息的 QTAIL 写成 `2`，而已复核的队列格式要求末 DWORD 的字节偏移 `8`。此外，手工投递在 boot 完成后也不等价于驱动的 boot-time transport。

### 真正确认的 runtime 无响应发生在跨槽混合序列之后

随后切回 XOC、经历完整断电，使用正确 PRC 报文：

```text
0xc0000001 0x1310de7e 0x001d020c
```

在 MNOC p0/p1 上均超时；PRC/FWUP/CLOCK_BOOST/CAPS/INFOROM 全超时，EMEM 无响应，CMS2 为空。该现象确认了当时的卡级 runtime 无响应，但它发生在：

- XOC 上早先的畸形 EMEM `0x1A` 探针；
- p1/p0 畸形 `0x1A` 报文；
- 原版上的畸形 `0x20`/PRC 报文；
- 多次重启、切槽与 reset；

之后，不能用来单独证明原版槽从 9 月 28 日起已经永久 runtime-dead。

---

## 八、分层判定

| 层 | 原版槽历史状态 | 当前可下的结论 |
|---|---|---|
| VBIOS/GPU 基本功能 | 12:32Z 完整健康 | 没有证据表明 VBIOS 主区当时损坏 |
| 六个已识别的 CC/相关 knobs | 6/8/10/39/40/42 曾被设错/残留 | 同期工具输出证实写 0、读回 0，并在一次断电后仍为 0；不等于所有 47 个 knob 都归零 |
| PRC/MNOC runtime | deep-lock 后一度仍可用 | 不能说 9/28 起永久死亡 |
| FSP boot功能 | 某些 reset 状态下超时 | 10/2 自定义模块下能 boot GSP；不等同 stock 健康，也不能细分证明某个 COT 步骤 |
| WPR2 | 多次出现 up/重建/dirty-exit 状态 | 是 stock 驱动的重要阻断点，但不是固定窗口、单一成因；10/2 legacy PFB 读数不能代替 GB202 driver 判据 |
| 当前 runtime 无响应 | 后续卡级状态已确认 | 原版槽后续状态没有用正确报文做干净、槽位隔离的复现 |
| flash 私有区损坏 | 旧文档有模型 | 无完整 4 MiB 实卡 dump，未证明具体字节/对象 |

---

## 九、需要修正的旧结论

### 可以保留

```text
原版槽明确经历了 21:28Z CC-limbo 五条 COT 后的 deep-lock。
原版槽后来出现 WPR2/boot 异常。
CC knobs 已被独立修复。
当前两个槽都可能存在问题。
```

### 必须降级

```text
“01:35Z COT version fuzz 一定发生在原版”
→ 原始槽位时间线更像 XOC；至少未证明原版。

“原版 runtime 从 9/28 起永久死亡”
→ 9/29 原版 PRC/MNOC 仍活，可完成六个 knob 的清除和读回。

“10/2 原版上的所有 runtime 测试都证明 dispatcher 预先已死”
→ 初始测试包含畸形 0x20 和错误字节序 PRC，先锁了端口。

“record A/B 已定位到 flash 私有区”
→ 仍是假说；缺少完整物理 dump 和字节级 diff。
```

## 十、最适合对外使用的一句话

> The original VBIOS slot was last verified fully healthy at 2026-09-28T12:32Z. Its clearest slot-specific failure transition occurred later during a compound CC-induced boot-limbo experiment that sent five COT requests. The CC-related PRC knobs were subsequently repaired and the PRC/MNOC runtime path was still functional, while WPR2 and GSP boot behavior remained abnormal. A later card-wide runtime-dispatcher failure was observed only after additional malformed probes, BIOS switching, resets, and dirty GSP crashes, so it cannot yet be attributed uniquely to the original slot or to one specific COT request.

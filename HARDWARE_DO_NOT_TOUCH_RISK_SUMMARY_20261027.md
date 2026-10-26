# GB202/FSP 真机操作风险清单（只读复核）

日期：2026-10-27

范围：仅复核本地既有报告和历史日志；本次没有访问 GPU、BAR、PCI 配置或设备节点，没有发送 FSP/GSP 消息，没有复位、刷写或改动硬件状态。

## 总结

本地记录支持“不再碰真卡”的决定。风险不只来自显式写入：畸形消息、未知子命令、过宽 MMIO 读取、异常后的恢复操作，以及正常参数边界附近的 MODS 控制都曾造成 FSP/GSP/PMU/PCIe 或内核级故障。

最危险的特点是故障会跨层传播：

```text
FSP/GSP 消息解析或状态机异常
  -> mailbox/transport 卡死
  -> WPR2 或启动状态未正确清理
  -> GSP-RM 下一次启动失败
  -> reset/rescan/bind 失败或设备掉线
  -> 用户态进程、kworker 甚至整机进入不可杀状态
```

## 一、已实测的 FSP/启动链故障

### 1. SMBPBI 服务可楔死整个 FSP 报文循环

`FSP_LINE_COMPLETE_20260926.md` 记录：CAPS 宣称支持 NVDM `0x18 SMBPBI`，但若干请求没有响应；一次 GET_TEMP 类请求后，所有端口均超时，连原先可用的 task/PRC 通路也不能再发送。该故障需要设备复位恢复。

定性：已实测状态机 DoS；未证明内存破坏或提权。

### 2. MNOC 非法长度可锁存端口 ERR

`RESUME_BRIEF.md` 记录：超大 MESSAGE_SIZE 在 INFO 写入时被硬件置 ERR；ERR 为只读锁存状态，READY 不再恢复，随后 EMEM 通道也不再回包。驱动和桌面当时可能仍活着，但 FSP 通信在本次 boot 内报废。

定性：已实测端口级永久卡死（直到复位/断电）。

### 3. MCTP/NVDM 畸形序列可造成临时通道 DoS

`FSP_MSG_LAYER_AUDIT.md` 记录：

- 双 SOM；
- SEQ 跳跃；
- NVDM `0x20` 空载荷；
- NVDM `0x21 FSP_GSP_COMM` 任意载荷；
- 某些 InfoROM 请求；

均可能令通道卡死，通常约 10 秒自愈。普通边界洪水和 EMEM 越界偏移则被限制或毒化，没有观察到可用溢出。

定性：临时 DoS；说明即使没有内存破坏，协议状态机也很脆弱。

### 4. COT/失败启动序列可留下 WPR2-up 或 deep-lock 状态

历史 COT version/size fuzz、CC boot-limbo 下连续 COT 请求，以及后续 dirty-GSP crash 后，曾反复出现：

```text
unexpected WPR2 already up, cannot proceed with booting GSP
```

后果包括 stock 驱动拒绝启动 GSP、`kfspSendBootCommands` 超时、`RmInitAdapter` 失败和冷启动后再次出现 WPR2-up。

必须保留证据边界：

- 没有隔离出某一条 COT 请求是唯一原因；
- 旧记录中的“固定 flash poison record / InfoROM 永久锁”属于过度外推；
- 后续只跳过 host 侧 WPR2 fail-early 检查时，标准签名启动链和 CUDA 曾能正常运行，说明部分 stale WPR2 状态是驱动阻断，不一定等于硬件已损坏。

定性：已实测启动链持久性 DoS/清理缺陷；具体存储机制未知。

### 5. task2/PRC 状态可阻止 WPR2 正常释放

`FSP_LINE_COMPLETE_20260926.md` 记录：task2 引起的 PLM 状态可熬过驱动卸载，但设备复位会清除；同一会话中随后启动 GSP 会遇到 WPR2 已存在，导致初始化失败。

定性：会话级状态耦合；即使某个写入本身看似可逆，也可能封死后续启动顺序。

## 二、GSP 缺陷会反向污染 FSP/启动状态

### 1. K3-1 消息队列先拷贝、后校验

`RESUME_BRIEF.md`、`fsp_ace_static_20260927/` 记录：宿主声明的元素数量可驱动设备侧把数据复制进 64 KiB staging，容量检查发生在复制之后。超过 16 个 4 KiB 元素时产生确定性设备侧破坏，并触发 Xid 120/GSP 崩溃。

这不是 FSP 本体漏洞，但 GSP 异常退出后可能留下 WPR2 或 FSP/GSP 握手状态，令后续驱动加载失败。

### 2. RPC handler 的 count/length 关系多处脆弱

静态和动态记录包括：

- `GPU_EXEC_REG_OPS` count 驱动动态栈分配及越界源读取；
- `IDLE_CHANNELS` 字节数与条目数比较错位；
- `SET_REGISTRY` 的 `numEntries`、offset、length 未与表剩余范围完整关联。

其中部分已达到确定性 DoS/设备侧破坏，部分仍是静态候选。不能把“只是 GSP 崩一下”视为隔离良好的故障。

## 三、读操作和恢复操作也可能出事

### 1. BAR0/FB/WPR 广泛扫描并非安全只读

历史记录在 BAR0 全空间扫描、COT/HULK 子命令扫描后出现 RC watchdog、Xid 109/119、GSP heartbeat/RPC timeout。之后还发生过 `fallen off the bus`、BAR0 变 0、COT/WPR2/RmInitAdapter 失败。

精确触发项没有隔离，不能断言某个读寄存器必然导致事故；但本地经验足以证明“只读盲扫天然安全”是错误假设。可能存在 read-to-clear、审计/状态寄存器或时序干扰。

`FAN_CONTROL_DO_NOT_REPEAT_20260727.md` 也明确记录：宽范围 FB/WPR 扫描曾导致显示/GPU hang。

### 2. 异常状态下的 sysfs bind/rescan 可把内核挂死

`RESUME_BRIEF.md` 记录：

- FSP 端口锁存后执行 PCI rescan，进程可能进入内核态忙循环，SIGKILL 和用户态 `timeout` 均无效；
- 手工绑定 NVIDIA 驱动可能进入 D 状态，同时拖住 `kworker`；
- 最终只能整机断电。

因此“先打挂，再靠自动恢复脚本救”本身就是高风险方案。

### 3. FLR、SBR、POR 不是等价恢复

本地记录出现过：

- FLR/普通重载无效，SBR 恢复；
- SBR 后设备 `fallen off the bus`；
- couple-reset/SBR 后 BAR0 丢失或 GSP 启动仍失败；
- 冷启动与 SBR 命中不同 reset domain，结果相反。

恢复动作可能改变故障形态，而非简单清零。

### 4. 软件入口问题容易被误判为固件永久损坏

`GSP_GLM53_CONTEXT_AUDIT_20261026.md` 证明历史恢复过程中混入：

- 错误删除/重建 `/dev/nvidia0`；
- 普通 sudo 仍受 cgroup BPF 限制；
- 用 `cat` 读取 driver 目录符号链接并误判未绑定；
- 把 EBUSY 误判为 probe 失败。

误判会诱导继续执行不必要的 reset、unbind、rescan 和手工 BAR 修复，从而制造第二次真实事故。

## 四、持久化和不可逆风险面

### 1. FuseRework

MODS/FieldDiag 明确存在 `fuserework.bin` 路线，发送 NVDM command `0x0f`，并需要 RSA-3072 认证材料。虽然回包只有 4-byte ACK，名称、文件布局和调用语义都表明它属于制造/返修级路径。

在不知道主 payload 内容时，发送该命令可能修改 fuse、shadow/latch、SKU 或其它持久状态；禁止在零售卡上尝试。

### 2. PRC 写、HULK、InfoROM 和 firmware-update 类服务

- PRC `0x0d` 是真实写路径，不是查询接口；具体生命周期依赖 flag、对象和 reset domain。
- HULK 涉及许可证/授权状态。
- InfoROM 涉及板级非易失对象。
- firmware update 涉及固件/flash。

当前实测 CAPS 路线中 RESET、HULK、FIRMWARE_UPDATE 未受理，但这不证明其它 SEID、制造包或 FuseRework 路线也不可达。

旧记录宣称 PRC 必然写坏 InfoROM 的结论已被后续证据降级；更准确的说法是：持久或冷启动复现状态确实出现过，但 flash 记录和存储位置未被证明。

### 3. nvflash/SPI 访问

历史 Linux nvflash 尝试曾导致整机冻结。其“FSP 总线级拦截”的内部机理未完全证明，但实际 hang 足以把直接 SPI 操作归为高风险。

## 五、性能/电源控制也存在硬故障边界

### 1. MODS MCLK +4000 MHz 边界

MODS 570.215 实测：

- 18000 MHz（相对 14001 MHz 为 +3999 MHz）可进入测试；
- 18001 MHz（+4000 MHz）在测试开始前导致 PMU-RISCV halt、change-sequencer timeout 和 MODS error 539；
- 根因表现为硬件 mailbox 事务未完成后发生重入断言，并非普通参数越界拒绝。

1050 mV / 3100 MHz GPC 组合也曾硬失败，不应重复。

### 2. 配置的 600 W 不一定是瞬时物理上限

18000 MHz + GLCombustPulse 的 MODS 遥测曾报告 657.305 W 峰值。未用外部功率计复核，但足以说明不能把 UI/配置中的 600 W 当成硬件绝对保险丝。

### 3. LACT 曲线恢复存在状态依赖

`BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md` 记录：controller reload 时会丢弃旧 controller 的 `reset_clocks()` 错误；新 controller 又不知道硬件上是否残留逐点 V/F offset，可能在旧曲线上再次计算和应用配置。

这类故障不一定立刻挂卡，但会留下难以识别的频率/电压状态，使后续实验失去干净基线。

## 六、风险分级

| 级别 | 操作类别 | 主要后果 |
|---|---|---|
| 极高 | FuseRework、fuse/shadow/latch、firmware update、HULK/InfoROM 写、SPI/nvflash | 持久状态改变、整机冻结、潜在不可逆损坏 |
| 高 | 未知 COT/SMBPBI/MNOC payload、GSP RPC 畸形长度、广泛 BAR/FB/WPR 扫描 | FSP/GSP 卡死、WPR2 stale、Xid、掉总线、需断电 |
| 高 | 卡死状态下反复 bind/rescan/SBR/手工 BAR 修复 | 内核 R/D 状态不可杀、BAR 丢失、二次故障 |
| 中高 | MODS 极限频率/电压/功耗测试 | PMU halt、change-sequencer timeout、超预期功耗 |
| 中 | PRC 写、reset coupling、CC mode 切换 | 状态跨驱动周期、启动链耦合、恢复语义不确定 |
| 中低 | 畸形 MCTP 包、未知 NVDM 空载荷 | 通道临时 DoS，部分约 10 秒自愈 |
| 低但非零 | 窄范围、已知无副作用的状态查询 | 仍需防止权限/设备节点误判和读取副作用 |

## 七、结论

本地证据显示，GB202 的危险并不只是“某个写寄存器可能烧卡”，而是：

1. FSP/GSP 的错误路径和清理路径不可靠；
2. 多种看似局部或可逆的故障会污染下一次启动；
3. PCIe/驱动恢复路径自身也可能挂住内核；
4. 诊断工具允许进入零售驱动不会进入的频率、功耗和制造状态；
5. 旧日志里还存在若干误诊，继续操作容易在错误模型上叠加新事故。

因此当前建议是：不再对现有 RTX 5090 执行 FSP/GSP 消息、BAR/MMIO 扫描、reset、MODS 极限测试、FuseRework、flash 或 fuse 类操作。后续研究保持离线静态、模拟器或独立可牺牲样品范围。

## 主要依据

- `SESSION_20261025_NIGHT_FULL_REPORT.md`
- `GSP_GLM53_CONTEXT_AUDIT_20261026.md`
- `GSP_RECOVERY_20261026.md`
- `FSP_LINE_COMPLETE_20260926.md`
- `FSP_MSG_LAYER_AUDIT.md`
- `RESUME_BRIEF.md`
- `FSP_ULTIMATE_FINDINGS.md`
- `BLACKWELL_UNBOUNDED_COPY_SURFACE_20261025.md`
- `PSIRT_DRAFT_2_GB202_WPR2_PERSISTENT_STATE.md`
- `ORIGINAL_BIOS_SLOT_FORENSICS_20261013.md`
- `FAN_CONTROL_DO_NOT_REPEAT_20260727.md`
- `vm_mods_lab/mods570215-diagnostic-20260825-logs/SUMMARY.md`
- `power_governor_reverse/MODS570215_MCLK_3999_4000_STATIC_FINDINGS_20260903.md`
- `BLACKWELL_CONTROL_LOGIC_EXTRACTION_20260725.md`

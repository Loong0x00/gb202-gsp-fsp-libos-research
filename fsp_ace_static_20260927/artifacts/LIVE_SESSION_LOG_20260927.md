# 实弹会话记录 2026-09-27 07:00-07:45 —— 低→高风险阶梯执行

环境:宿主直连(BAR0 内核模块路线;新内核 7.2.6 上用户态 resource0 mmap 被 NVIDIA 设备专属拒绝 ⇒ 全部经 ioremap 内核模块)。驱动 610.57.04 全程加载(桌面在 AMD 核显)。每步之间做健康检查(FSP 寄存器 + PRC 回包 + NVRM 错误计数)。

## 阶梯与结果

| # | 实验 | 风险 | 结果 | 状态 |
|---|---|---|---|---|
| T0 | 基线快照(FSP/MNOC/PSEC/PLM/EMEM) | 零 | 全部健康:FSP boot=0xFF、ucode=0x44c、scratch=0x9f、port0/1 idle+READY、port2/3 毒;PSEC 部分可读(MAILBOX=0xe6513000、MSGQ idle、scratch 毒) | ✓ |
| T0.2 | 0x8f4000-0x8f7fff 身份分析 | 零 | **活的 FSP 内存**(双计数器随时间变化;SEID/端口形状表;PLM 值表;0x8f8000+ 是新毒值 badf1100)。0x8f40f8=008f4000 自指针;三重复实例@4KB 间隔 | ✓ 定性 |
| T1.1 | 0x8f7340 单点写-读-还原(零区中央) | 低 | **读回=原值(写被忽略/读过滤)** ⇒ 该区宿主只读。**但 28 秒后 GSP 楔死**(见事故①) | ⚠️ 阴性+事故 |
| T1.2 | PRC 子命令扫描(cmd=00..ff 采样) | 低 | 全部干净拒绝:未识别→0xAA;识别但参数错→0xAC/0xAF/0xAB/0xAE/0xB0;0x0b/0x0e/0x0f/0x10 有专用错误码(0x1FE/0x22C/0x1B2/0x23E)= 真实子命令 | ✓ 阴性 |
| T2.1 | COT(0x14)运行时直注 v0xFFFF(868B 诚实) | 低 | **被投递(credits 消耗)但静默无回包**;16 秒后 port 1 仍正常 ⇒ COT 任务运行时不受理(GSP 活着时 COT 窗口关) | ✓ 新事实 |
| T2.2 | B2:QUEUE_HEAD=1(起点平移) | 低 | **消息照常成功解析**(errorCode=0)!回包值 0xdead0001(高位=预填标记 ⇒ 响应缓冲与通道残留重叠)⇒ **HEAD 被无视,FSP 从偏移 0 读到 TAIL;HEAD=纯门铃** | ✓ 阴性(结构性) |
| T2.3 | B2:QUEUE_HEAD=200(>>TAIL) | 低 | 同样正常处理(0xcafe0001)⇒ 无下溢/平移原语。**B2 关闭** | ✓ 关闭 |
| T3.1 | MCTP 形状矩阵:SOM-only / SOM+SEID=1 / EOM-only | 低 | SOM-only→**0x202**(形状非法);SOM+SEID=1→0x202;EOM-only(SEQ=1)→**静默丢弃**。⇒ EMEM ch0 要求单包(SOM|EOM),重组缓冲不可达 ⇒ **B1(EMEM 多包溢出)关闭** | ✓ 关闭 |
| T3.2 | B7b:FSP_GSP_COMM(0x21)→port 0 | 低 | 16B 被消耗(credits);FSP 状态值 0x8f4488: 0xd0→0x3c(内部活动);EMEM 见证完好;驱动零错误。**不可判**(port 0 无回包通道) | ◐ 弱数据点 |
| — | port 0 行为测定 | 零 | **port 0 收下宿主消息但不回包**(与 port 1 的回包行为对照)⇒ port 0 = GSP 车道假设增强 | ✓ 新事实 |

## 事故①(硬复位):0x8f7340 写入 → GSP 楔死 → 系统级冻结
- 时间线:45188.79 写入(读回不变、立即"还原")→ 45188.83 健康检查全绿 → ~45209 GSP 停止响应 → 45216 RC watchdog 连环 → nvidia-modeset 内核线程 D 态 → systemd-logind D 态 → **键盘大小写灯无响应** → 用户按重启键(07:24)。
- 因果未定:窗口内唯一的我们动作 = 写入测试;但 quill(12h CUDA 进程)同期在跑。写入的"读回不变"与"GSP 楔死"并存 ⇒ 若因果成立,则 0x8f4000 区**读被过滤/写透传**(写生效但读视图被滤)——这本身是重要原语假设;若不成立则 quill 自身撞死。
- 恢复:热复位后全绿(FSP 干净重启、0x8f4000 计数器新鲜、驱动正常、零 Xid)。
- 教训:**任何 0x8f4000+ 写入 = 系统级风险**(不是"FSP 挂→重启"而是"内核 D 态→可能硬复位");在因果定案前不再写该区。

## 事故②(port 1 楔死):COT/qhead 实验后 port 1 TX ERR 锁存
- 时间线:307 COT(port1,无回包)→ 323 PRC(port1,正常回包)→ 397/422 EMEM qhead 实验(EMEM 回包正常)→ 424 PRC(port1)→ **推送成功但无回包,port1 send_info=0x82000000(ERR 锁存)**。
- 排空 RDATA(读到 0x11111111 空值)+ W1C 清 INTR(bit31 可清)均无效;**ERR(bit25)不清,READY 不再置位** ⇒ port 1 消息通道死亡(FSP 侧 TX 状态机楔死)。
- 候选机制:(a) COT 迟发回包(116 秒后?)与后续 PRC 的 TX 冲突;(b) qhead=200 实验的副作用。无法定案(FSP 密文)。
- **副作用隔离良好**:port 1 死后 EMEM ch0 全功能存活(多轮 PRC 回包验证)、port 0 仍收、FSP 核心活(scratch/boot-complete/计数器)、驱动零 Xid。⇒ **FSP 消息通道按端口隔离,单端口楔死不扩散**。
- 恢复:需设备复位(驱动重载周期或重启);本会话未恢复(EMEM 够用)。

## 新工具(本会话产出,均在 fsp_recon/)
- `fsp_tx_mod.ko` — 通用 MNOC 发送器(任意 hex 载荷/声明长度覆写/回包读取/COT 构造模式)
- `fsp_wrtest_mod.ko` — 单 dword 写-读-还原测试器
- `fsp_sniff.c` — 用户态嗅探器(因 mmap 限制暂不可用,留档)
- `fsp_probe2.c` 新增 `qhead` 参数(门铃值覆写)
- `drain_mod.ko` — port 排空/W1C 恢复尝试器

## 阶梯剩余(全部需要驱动重载周期 = 杀会话/quill)
1. **F-1 GSP RPC 枪**(GPU_EXEC_REG_OPS count 无界 VLA——保底交付物的定级):需 spy 轮(捕获 fn=50 真实布局)+ 实弹轮,两周期;GSP 崩溃恢复 = 设备复位(非重启)
2. **COT 直注窗口**(无驱动态:COT 任务应受理):version/size 字段 fuzz——size 是"未检长度候选",若 FSP 按 size 拷贝即溢出
3. **B3 MNOC 超申报**(port 0,V1/V3/V2):零回包观测,且楔 port 0 = 楔 GSP 车道 = 系统级风险 ⇒ 最后考虑
4. port 1 楔死复现实验(定案事故②机制)——每轮代价 = 一次复位

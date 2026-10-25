# PMU completion-notification 超时：静态机制与日志证据

## 范围 / 结论

只读检查匹配的 `gb202_r570215_runtime_pmu.elf`（SHA-256：`2eef42f0b434990d2c9669124199a912e8e16d8480d1c9a74d46d75e1575b93b`）、既有反汇编/报告，以及 `edc18001-auto`、`edc18001-msvdd1050` 的 `.log`、`.mle` 和可用 stdout 附件。未执行 GPU/MODS；未打开或修改旧 GhidraDB。新产物仅在本目录。

**当前能证明的是 command-0 completion wait 超时，不是 endpoint 一定未处理，也不是 IRQ 一定丢失。** 两种故障都与当前现场相容：completion 状态从未出现；或 endpoint 已完成但 bit-2 notification 没有抵达/转成软件 signal。所留日志没有相应的 PMU 内部状态，不能在二者之间作判别。

下文将原始指令直接支持的事实标为“发现”；未由指令/留存状态直接证明的因果解释标为“未决/假说”。函数含义仅按可见数据流描述。

## 指令直接支持的发现

### 1. wait 预算及单位

- **Parent 原始指令复核修正：** MCLK wrapper传给primitive的timeout参数是 **95000**，但不是直接传给wait的预算。`205d1ab4–205d1abe`执行`(timeout-1)/50+1`；`205d1aba`的字节`02f4d4bb`在`llvm-objdump --mattr=+m`下明确解码为`divuw s1,s1,a5`。故`205cf612 → 205cf1c8`实际获得 **1900** 个scheduler tick。先前默认反汇编将该指令显示为unknown，导致此处漏记换算。
- 通用等待代码将这1900的预算用于`0x2000e768`计数、整数比较及调度超时项。尚未独立闭合每tick的墙钟时长，不能把1900直接说成毫秒或CPU周期。95000/50形态与微秒转50微秒tick相符，但只有确认时基后才可严格称95ms。
- `205c847a` 在预算耗尽路径返回 `-0x13`；`205cf1c8` 对该值返回 `4`。调用者随后走 command-0 completion failure 分支。另一个 marker `0x256c8` 才对应此前识别的 busy 失败；本案日志的 `0x25728` 是 completion wait marker（`205d1acc`），二者不可混称。
- 独立 scheduler alarm 代码用 `rdtime` 并选用 `0x3d090` 或 `0xc350` 的raw间隔；其与实际1900-tick预算的墙钟比例仍需确认，不能只凭这些数值推定时长。

### 2. type-2 completion notification / queue

- 初始化路径为 `205cf59e → 205d8064 → 205d8398 → 205d8274`。对象初始化显式把对象偏移 `+0x80` 清零、`+0x88` 写入 1；创建者再写入初始 count 0。completion 对象全局地址为 `0x20016b00`。与等待/发送代码的数据流合看，这是初始 count 0、上限 1 的计数事件。
- wait 路径检查 `+0x80` 的 count；已有 token 时递减后返回。signal/post 路径在未满时递增 count，等待/唤醒使用对象内的队列和锁辅助代码。因此 **signal 先于 wait 时有一个可保留的 token**；“仅仅因为 signal 比 wait 早到而必然丢失”的机制未由这些指令支持。计数已满时 signal 路径返回 `-4`；dispatcher 对非零 dispatch 结果执行 `ebreak`。
- dispatcher `205dd196` 读 `0x014024c0`，只取 mask `5`（bit 0、bit 2）。对于置位项，它先向该 status 地址写相应位，再调用 type dispatch；bit index 2 分支 `205dd420` 进入 `205cf644 → 205cf27e → 205c8416`，把全局 completion 对象送入 signal/post 路径。这里仅将 `0x014024c4` 保守称作 notification/control word：静态片段本身不足以给寄存器作芯片语义命名。
- “何时置 bit 2”：`205d080a` 对 `0x014024c4` 执行 `(old | a0) & ~a1`。全 ELF 直接调用扫描发现仅两个调用点：`205dd1ba` 传入 `a0=5,a1=0`；`20660324` 传入 `a0=0,a1=0`（不改变 word）。前一调用位于 dispatcher 发现 `(0x014024c0 & 5)==0` 的分支内，故该分支写入 bit 0 和 bit 2；不是单独写 bit 2。静态证据定位了这个**条件分支**，但不能确定它相对 PMU 启动、目标 MCLK 请求或真实 IRQ 的绝对时刻，也不能据此证明 `0x014024c4` 就是硬件 IRQ enable。

### 3. dispatcher 调用及 IRQ 注册边界

- `205dd196` 的全 ELF 直接 `jal` 扫描唯一命中为 `205de08c`。`205d8d50–54` 形成 callback 地址 `205de0b2` 并传给 `205dbdba`；callback 随后调用 `205df7be`、跳入 `205ddfe4`。该循环通过 `205cf474` 等待/取消息，解析出 type `0x10` 时从 `205de08c` 调 dispatcher。可证明的是这条 callback → task/message worker → dispatcher 调用链。
- 初始化路径 `205d9688` 另将 callback 地址 `2063597a`（由 `205d970e–12` 形成）传给同一 setup helper；该 callback 也进入 `205cf474` 的通用队列/事件等待路径。没有闭环证明它产生 status bit 2，也没有其到 `205dd196` 的直接调用。两条 callback/setup 路径显示的是等待/消息 worker；不能仅凭 helper 名称/参数解释成 IRQ-vector/source 注册。
- 本子任务未闭合dispatcher的硬件IRQ入口；**Parent随后已补齐固件内的supervisor-external trap → 顶层bit11 → 二级bit1 → msg0x10/queue0 → worker → dispatcher路径**，见`../parent_scan/IRQ_COMPLETION.md`。设备侧通知源、PMU-local到host寄存器的完整alias映射及本次故障是否走过该路径仍未闭合。不能仅用host `IRQSTAT`/`SIP`字段替代当次内部状态。

### 4. `ebreak` 的指令核验

失败 marker 后到 `205d1a2c` 是实际 `ebreak` 指令；`205cf2ea` 也是失败分支上的实际 `ebreak`。`205dd1f0` 是 dispatcher 错误处理中的实际 `ebreak`。这些都不是可继续执行的正常轮询循环；decompile 中若把 `ebreak` 后地址恢复/伪循环呈现为循环，不能据此称为 retry 或 busy-wait。汇编摘录见 `instruction_evidence.txt`。

## 日志与附件能/不能回答什么

两个 `.log` 各有六份 `PMU_MAILBOX(01)=0x00025728` 快照；各自 `.mle` 及 `edc18001-msvdd1050.stdout` 也保留六份该 mailbox marker。auto 日志例：line 543 marker、line 469 `SEPC=0x205d1a2c`、line 472 `SCAUSE=3`；多个快照记录了 Falcon/RISC-V 寄存器、trace 和 halt。host 报告的 `4000 msecs` 是 PMU 已 halt 后的外层thread timeout，不是primitive的95000参数或实际1900-tick预算。

**但所检视的可读诊断内容没有保存/显示**：`0x014024c0` 的 bit-2 pending 值、`0x014024c4` 的当时值、request 实际 payload/写入值、`0x01402808/0x01402828` response 值、completion 对象 `0x20016b00` 的 count/队列状态。两份 `.mle` 是带 `MLE` 头的二进制容器；对可读字符串和上述地址的原始字节序列做过检查，但没有本地 schema/parser 来解释其他 opaque 字段。因此不能断言它们所有隐藏二进制字段绝无相关值；现有材料没有提供可解读、可关联到端点/通知状态的证据。因此：

- 可以确认这些 run 到达 completion failure marker 并 halt；
- 不能确认 endpoint 是否看见/处理了 MCLK request，不能确认 response 是否已写；
- 不能确认 bit 2 是否 pending、是否被 worker ack、是否成功 post 到对象；
- 所以日志**不足以区分 endpoint 未处理与 notification/IRQ 丢失**。

日志里的 `INTR_0_PRI_FECSERR pending` 是另一个外层/host 文本字段；Falcon `IRQSTAT`、RISC-V `SIP` 在重复快照间也有变化，但现有资料没有寄存器位映射将它们连接到上述 PMU notification status bit 2。不能拿这些字段替代缺失的 PMU 状态快照。结论针对可解读的留存证据；若要排除 `.mle` opaque 字段还藏有状态，仍需对应格式解析器/schema。

## 未决项 / 假说（不是发现）

- endpoint 未完成、完成但 status/notification 产生失败、worker/IRQ 路由/调度未执行，均不能由现有 dump 排除。
- status ack 与软件 post 之间存在顺序窗口（指令为先 ack、再 dispatch/post）；这是值得关注的路径，不是日志已证明发生的 lost-notification 事件。
- 二值 count 语义减弱了“只因 signal 先于 wait 就丢 wakeup”这一解释；但没有当次对象状态、IRQ 路由状态及 handler 执行证据，不能排除更上游的丢通知或生命周期竞态。
- 不能从两次相同 marker、命令行设置 `dramclk 18001`、host IRQ 名称，推出请求实际载荷或 endpoint 完成状态。

## 复现静态核查

摘录文件：`instruction_evidence.txt`（匹配 ELF 的 `llvm-objdump -d`）；`dispatcher_registration.asm`（worker/调用与 callback 参数）；`log_audit.txt`（原始行号、计数及缺失字段检索）。检查均为离线文件读取/静态反汇编；没有运行 GPU/MODS，也没有修改既有取证文件。
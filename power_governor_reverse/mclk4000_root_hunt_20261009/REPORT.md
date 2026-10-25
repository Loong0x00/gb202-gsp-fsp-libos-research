# PMU +3999/+4000 首因追踪：目前不是已证明的主动拦截

范围：GB202 R570.215匹配runtime PMU及已有MODS日志，只读静态逆向。不运行GPU/MODS，不改寄存器、固件或旧研究报告。原ELF SHA-256：`2eef42f0b434990d2c9669124199a912e8e16d8480d1c9a74d46d75e1575b93b`。

## 一句话结论

**已恢复的PMU目标提交/command-0发送段没有找到+4000或18001的主动频率拒绝：频率按32位原样发送，metadata恒0；故障是等待completion预算耗尽后PMU主动断言停机。** 尚未定位“为何没有正常completion”的设备侧首因，所以不能把它定性为FSP拦截、36Gbps硬限制或显存训练失败。

本轮推进了前一轮的三个缺口：目标payload形成、正常错误回应与timeout的区别、实际外部中断→deferred worker通知链。仍未恢复设备侧消费者。

## 1. 目标是否在PMU这里被改坏/拦住

`20633630`把输入32-bit target保存到object+68；`2063469e`清零12-byte输入缓冲，只写dword0=object+68，再交给`206358ca`。因此该MCLK worker的输入dword1为0；wrapper截为halfword之后仍为0；CMD高16位不随频率改变。

在假设输入为最终目标kHz的条件下：

| 输入 | DATA | metadata | 发送段差异 |
|---:|---:|---:|---|
| 18000000 | 0112a880 | 0 | DATA本身 |
| 18001000 | 0112ac68 | 0 | 仅DATA多1000 |

没有在此链路见到MHz换算、rounding、频率档位投影、16-bit频率截断或把4000混入CMD高位的步骤。全部256个sequence情况下，这两个DATA也都不会碰到DATA==CMD的bit15特殊处理。

发送前有小幅调整抑制：全局disable、override mask `0x10`，以及reference±2000/old target±500窗口。它们决定state1（不发送）或state2（更新后发送），不是硬编码18GHz上限。若reference和old都为14001000，两请求都置state2。这个代入是模型验证，不是当次heap读数。

本次日志已经落在MCLK wrapper/primitive等待失败处，故实际失败没有停在state1跳过发送的门。

详见`target_path/REPORT.md`与`parent_scan/sender_model_test.json`。不把上述条件演算冒充实际运行payload；原日志没有保存实际DATA/CMD。

## 2. 真正触发停机的条件

匹配故障标记：`PMU_MAILBOX(01)=25728`，SEPC=`205d1a2c`。

```c
write_request_data();
write_tagged_command();
ticks = timeout ? ((uint32_t)timeout - 1) / 50 + 1 : 0;
status = wait_completion(event, ticks);
if (status != 0)
    ebreak_at_shared_assert(marker_25728);
```

MCLK wrapper的timeout参数是95000；**实际wait预算是1900 ticks**。`205d1aba`原字节`02f4d4bb`为`divuw`，须启用llvm M扩展才能正确显示。先前子分析漏解这一指令，95000-tick说法已修正。

底层deadline耗尽返回`-0x13`（十进制-19），wait wrapper映射为4。其它底层异常会在别处assert；marker25728指向本次wait失败。当前没有独立闭合tick墙钟单位，不把1900称为毫秒或CPU周期。

### 与正常“拒绝ACK”的区别

- 当前停机在wait失败，还未进入response检查。
- wait成功后才读response，检查sequence/command并得到状态字段。
- MCLK wrapper如果收到非零response状态会走cleanup和`2063592a`等后续分支；与当前SEPC/marker不同。
- 入口busy、response序号/command错误也有不同marker；enqueue/event post错误有不同trap地址。

所以现有现场不是“收到明确拒绝状态后退出”的证明。它仍允许消费者静默丢弃、执行/训练未完成、通知未产生或调度未及时处理等情况。

## 3. 新恢复的实际通知链

```text
supervisor external interrupt(scause high-bit|9)
  -> 205c8f56 -> 205c7dc6
  -> local[01400008] & ~local[0140152c]
  -> 顶层bit11(mask800)
  -> local[01402688] bit1(mask2)
  -> local[014024c0] &5 非零
  -> 3-byte message type10 入queue0
  -> 205ddfe4 deferred worker
  -> 205dd196 遍历pending
  -> completion bit index2
  -> 205dd420 -> post(event20016b00)
  -> waiter醒来检查response
```

中间不是只有“一个IRQ”：包含硬件/本地状态、IRQ入口、队列、deferred worker、计数事件。因此“已发送但timeout”不能只归到外部消费者，也不能只归到IRQ丢失。

事件对象初始count0、容量1，post早于wait时可以保留token；因此“仅因为ACK来得太早就必丢唤醒”这一简单解释不成立。queue enqueue、event post都有失败处理，不能仅从调用者未显式检查返回值推断静默丢消息。

硬件消费者、谁设置各级状态、端点命名仍未知。`014xxxxx`不是已经证明的BAR0偏移。细节与原始指令见`parent_scan/IRQ_COMPLETION.md`、`irq_completion_verified.asm`。

## 4. 对+4000边界的当前判断

PMU本段接收的是最终绝对target，不是MODS显示的relative offset。若确实有能力/政策检查在设备侧限制目标，**名义18000/18001边界**比“此command字段中存在offset4000比较”更符合所见数据流；但这仍是方向判断，不是已恢复的拒绝代码。

前轮外置晶振记录也只能说明软件名义目标和物理频率可以分离，不能证明本消费者应接受更高名义target。可用资料不足以判断是下游能力表、训练/换频过程、时限还是通知链首因。

本地两个旧clear-PMU构建也使用同样的9a4514/9a4504事务框架，却使用不同local response地址；其结构只能作跨构建协议线索，不可当当前消费者身份或限值源码。消费者追踪覆盖MODS RegHal、已发布头/rnndb、旧PMU与固件inventory，仍无正面身份绑定，见`consumer_identity/REPORT.md`。

Parent还恢复了MODS通用FBFalcon MCLK状态机的候选host函数（`parent_scan/mods_fbflcn_host_recovered.c`），但尚未把它的HAL路径与本次GB202 command0相连；不能因日志字符串提到FBFalcon就定责该引擎。

## 5. 日志线索与首因缺口

后期IRQSTAT从00400000变成00400800，新增bit11，与新找到的顶层通知位号一致。这是后续取证线索，**不是晚到ACK的证明**：还缺内部alias/二级bit1/completion bit2及response值，且它发生在halt之后。

要真正回答“为何被拦截”，至少需以下之一：

1. 找到命名consumer的代码及针对该target的验证/失败分支；或
2. 同一时刻保留实际DATA/CMD、response两字、三级pending/control、queue0与event count、worker调度状态。

现有可读日志没有这些现场值；MLE附件是二进制容器，可读内容检查不等同于穷尽解码所有opaque字段。

**因此当前能解释怎么停机、并排除几种发送端错误；还不能解释设备端为什么没有按时完成，更不能声称已经找到了拦截者。** 没有实施NOP ebreak、延长timeout或绕过训练的补丁，这些都不构成已验证修复。

## 验证与文件

- `target_path/`：setter、worker、DATA/metadata形成及指令。
- `notification_failure/`：事件对象、deadline、附件审计；已由parent纠正预算和补充IRQ入口边界。
- `consumer_identity/`：跨构建/寄存器/固件身份覆盖与负结果。
- `parent_scan/irq_completion_verified.asm`：启用RISC-V M扩展的关键原始指令。
- `parent_scan/sender_model_test.json`：条件输入模型与全部sequence验证，不含硬件运行值。
- `parent_scan/runtime_pmu.full.asm`：初始完整默认反汇编；unknown指令需以启用M扩展的定点输出为准。
- `parent_scan/mods_fbflcn_host_recovered.c`：Ghidra仅readOnly临时创建函数/反编译，日志确认Discarding changes，未保存旧DB。
- 额外资源`pride.deflate.bin`解压后是《Pride and Prejudice》测试PDF，不是寄存器手册；已排除为不相关测试数据。

本轮没有访问设备，没有修改旧Ghidra数据库、原ELF、固件或既有日志。

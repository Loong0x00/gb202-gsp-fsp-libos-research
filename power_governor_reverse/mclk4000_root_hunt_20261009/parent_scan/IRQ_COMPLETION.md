# Parent 新增：从 supervisor external trap 到 MCLK completion event

范围：仅匹配runtime PMU ELF和既有日志的静态复核；不执行GPU/MODS，不修改固件。原始指令见`irq_completion_verified.asm`，使用`llvm-objdump --mattr=+m,+a,+c,+f,+d`，不是依据反编译伪循环。

## 1. 已补齐固件内部IRQ入口 → deferred worker

```text
205cbb70..205cbba8
  scause = 0x8000000000000009（supervisor external interrupt）
  -> 205c8f56
  -> 205c7dc6
  -> 205d0c9a：read local[01400008] & ~local[0140152c]
  -> 205d0b08
  -> 205d0842：其中bit11(mask800)选择205d0986
  -> 205d08ac
     read local[01402688]
     若bit1(mask2)置位：
       read local[014024c0] & 5
       非零则构造3-byte message，type=10
       205d0900 -> 205c7f34(queue_id=0, message, size=3)
       写local[014024c4]（pending非零分支写0），fence io,io
  -> 205ddfe4消息worker
     type10 -> 205de08c -> 205dd196
     status bit index2 -> 205dd420 -> event post20016b00
```

这证明completion不是“ISR直接signal”那么简单，中间有queue0和deferred worker。它推进了此前“IRQ入口未闭合”的边界，但仍未命名设备侧硬件源、说明谁设置各级pending，也不能证明故障实例实际执行过该链。

两个位不能混淆：顶层IRQ bit11、二级status bit1、最终completion status bit2，是三级不同的状态条件。

`205c7f34`并非不检查错误：其尾跳`205c7f04`，后者检查enqueue结果；queue满/其他错误在`205c7f1e`断言。故不能只看到调用者没有显式检查a0，就宣称这里会静默丢消息。

worker清空`014024c0 & 5`之后经`205d080a(5,0)`重新写入local control word的bit0和bit2。这样出现“ISR关门→deferred worker处理→重新开放”的模式；这是从读写顺序观察到的通知控制行为，寄存器正式名称/硅片路由仍未知。

## 2. 正确的等待预算：1900 ticks，不是95000 ticks

原始opcode：

```text
205d1ab4 addiw s1,s1,-1
205d1ab6 li a5,50
205d1aba divuw s1,s1,a5  # 原字节02f4d4bb
205d1abe addiw s1,s1,1
```

因此wrapper提供的95000参数变成ceil(95000/50)=**1900**，再进入`205cf612 → 205cf1c8 → 205c8616/205c847a`。

默认llvm-objdump未开启M扩展会把divuw显示为unknown，不能忽略。墙钟tick比例尚未独立确认；不能把1900当作毫秒、也不在本报告把95ms作为已闭合时长。

deadline耗尽时底层返回-0x13，wait wrapper映射成4。当前fault marker25728定位到这个结果；其他不被wait wrapper接受的底层异常会在另一处ebreak。

## 3. 正常错误回应与本次timeout的不同位置

- 入口busy：marker256c8；不是本次25728。
- response序号/command不匹配：同共享ebreak，但分别加载不同marker；不是本次25728。
- wait成功、response表示非零状态：MCLK wrapper在`2063593c`后走cleanup，再有`2063592a`断言/返回路径；不是本次SEPC205d1a2c的等待失败。
- enqueue失败：205c7f1e；event post/dispatcher错误：205dd1f0；也不是本次陷入PC。

因此未见“正常回应带明确拒绝状态”的证据；本次PMU停止于未取得正常completion的阶段。消费者静默丢弃、转换未完成、通知未抵达或未及时调度，均仍可能；这些位置的区分不能在没有response/pending现场值时闭合。

## 4. 日志里的一个后续线索（不能当ACK证明）

两份18001日志先有Falcon IRQSTAT00400000，后有00400800，新增位是800（bit11）。它与上述固件顶层bit11位号吻合，值得未来关联；但仅有这一位，不足以证明二级bit1和completion bit2也置位，更不能证明调频完成。

MODS原始host指令显示，通用Falcon打印中的IRQSTAT来自引擎base+8（见`mods_falcon_irqstat_accessor.asm`），与固件local[01400008]的offset一致；Peregrine另一打印器也采用寄存器快照表。尚未完整证明该故障的全部local→host alias及寄存器语义，故“ACK晚到”“消费者其实完成了”在这里仍仅是假说。

## 5. 剩余取证缺口

要区分哪一段不通，须有同一时刻的：实际DATA/CMD、response两字、三级pending/控制状态、queue0消息与completion事件count、以及消息worker的调度进度。现有可读日志未保存这些字段，不能仅由晚期IRQSTAT推断首因。

# GB202 PMU MCLK 继续逆向：发送、通知与外置参考时钟

日期2026-10-09。硬件只读/静态研究：没有运行MODS、访问GPU、改写寄存器或固件，也没有运行未知Windows工具。本轮是一次阶段性逆向，不声称已经识别设备侧消费者或修复+4000。

## 核心结论

1. **本次故障可以确认PMU的软件发送路径已执行**：原始日志的断言标记0x25728对应共享primitive的完成等待失败分支，该分支必然经过DATA和CMD两次MMIO store。不是仅构造了参数、也不是在入口busy处就停止。
2. **仍不能确认硬件端点接收/执行成功**：未有应答、写回读验或设备侧事务转储。MMIO store执行不等于消费者确认。
3. 找到了PMU端完成通知链：pending status bit2 → dispatcher → event post → 正常等待者检查response。故障在event wait返回失败处，而不是之后的response序号/command检查处。
4. Windows工具是**1usmus/Yuri Bubliy的HYDRA 2.3B Pro**。原作者公开声明非5080的5090等也可解限至36 Gbps；但具体技术实现未公开，本轮未获得其二进制，不能将它归到FSP、PMU或某个setter。
5. 用户提到的闪电外置时钟记录找到原始条目：**Cmaker，Lightning Z，3650/2333 MHz，28.6363 MHz晶振**。其对应3DMark显示名义3442/2200 MHz、描述106.06%，与参考时钟缩放算术一致。

## 1. 本次command0确实走过发射端

匹配runtime PMU ELF：`../gb202_r570215_runtime_pmu.elf`。

SHA-256：`2eef42f0b434990d2c9669124199a912e8e16d8480d1c9a74d46d75e1575b93b`。

原始故障日志为`../../vm_mods_lab/mods570215-diagnostic-20260825-logs/edc18001-auto.log`和`edc18001-msvdd1050.log`，两份的所有六次dump均有`PMU_MAILBOX(01)=0x25728`。

指令级路径：

```text
206358ca MCLK wrapper
  command = 0
  timeout parameter = 95000
  direct = 0
        |
205d19ce shared primitive
  guard -> seq/command-word construction
        |
205d1a6c -> 205d496a -> sw
  effective PMU CPU address c09a4514 = input 32-bit DATA word
        |
205d1a76 -> 205d496a -> sw
  effective PMU CPU address c09a4504 = tagged CMD word
        |
205d1ac6 -> 205cf612(wait-object stored at 20016b00, budget)
        |
205d1aca wait returned nonzero
205d1acc loads assertion marker 25728
205d1ad4 -> 205d1a2c ebreak
```

CMD字段为`(halfword << 16) | (cmd << 8) | seq8`，并有避免与DATA相同的bit15处理。command0本身未比较4000000或18001000阈值。DATA从调用者缓冲读取，数据流指向最终MCLK目标；但此故障转储没有保存该输入字的实际值，因此“端点实际收到18001000”仍未被独立观测。

异常路径`205cba5a`保存a0至frame+0x48；SCAUSE=3 handler`205ca588–205ca596`取该值并写PMU mailbox1，有效CPU地址`c08f6454`。`25728`是完成等待失败标记，入口busy的标记是`256c8`。

helper两条正常路径都有store（`205d498a`或`205d49a0`），没有找到目标寄存器readback或显式发送端fence。相关CSR/临界区语义与底层MMIO强序性质未完整恢复；**缺少显式fence不能直接判成根因**，只说明不能拿这段代码当端点接收确认。

## 2. PMU完成通知路径

```text
init 205d9688
  205d974e -> 205cf59e(&20016b00, 0)

pending status at PMU-visible local address 014024c0
  205d07e2 reads
  205dd196 masks with 5 and traverses set-bit indices
  bit index 2 (mask 4)
  205d07f6 acknowledges the one-bit status
  205dd1f8(2)
  205dd420(2)
  205cf644(object at 20016b00) -> generic event post

wait success
  205d1ae4 onward reads 01402808/01402828
  check seq8 and command bits8..14
  copy response fields
  clear guard at 20016af8
```

`205d080a`还更新本地地址`014024c4`，该路径有`fence io,io`。它不在前述发射helper内，不能混为发送确认。

此闭合的是PMU端“状态分发唤醒waiter”的软件协议。尚未恢复：谁设置bit2、IRQ/vector注册、谁更新response寄存器、以及发射端消费者身份。失败日志没有保存这些通知/response寄存器在该实例中的值，所以也不能证明bit2从未置位；准确说是**完成wait没有取得正常完成结果**。

`014xxxxx`是固件直接访问的本地地址区，不能直接拿作BAR0偏移。`c09a45xx`是另一种accessor-derived访问路径。公开头/rnndb未正面命名这些端点，FSP/PBFB/FBPA归属均未闭合。

队列worker`2063597a`的函数指针在`205d970e–205d9726`被传入setup helper`205dbdba`（a3=0x12）；它是任务/队列路径，不应等同于通知bit2的ISR。

反编译注意：共享ebreak被Ghidra当成可能返回，导致primitive及init伪代码出现伪retry loop。报告已按原始指令修正；本次不是等待失败后正常重试发送。

## 3. HYDRA的36 Gbps与MODS的18001并非相同目标

原作者公开帖：<https://www.patreon.com/1usmus/posts/hydra-unlocks-166927902>。

作者列出常规5090最高34 Gbps、5080最高36 Gbps；初版HYDRA解限至36 Gbps，示范卡为Astral LC 5090。作者还声称无需刷VBIOS/特殊驱动，并把36 Gbps描述为初版人为限制。只有功能声明/演示，不是实现源码证据。

常用名义口径换算：

| 常用显存MHz口径 | MODS MCLK MHz口径 | GDDR7名义速率 |
|---:|---:|---:|
| 1750 | 14000 | 28 Gbps |
| 2200 | 17600 | 35.2 Gbps |
| 2250 | 18000 | 36 Gbps |
| 2333 | 18664 | 37.328 Gbps |

本机MODS的relation基准是**14001**而不是14000。因此+3999对应18000，而+4000对应**18001（36.002 Gbps名义请求）**。HYDRA公开“支持36”与本机MODS“18000能跑”一致；它本身没有证明MODS的18001控制请求也应通过。宣传的+4000必须先核对基准，不可直接按相同输入比较。

实际硬件测量可能与名义值有晶振/换算偏差：原18000实验实测约17982。因此也不能把18001失败写成PHY实测恰好越过36 Gbps。

## 4. 闪电2333记录对归因的价值

原始条目：<https://esports.hwbot.org/benchmarks/3dmark_-_port_royal/submissions/6065913>。

- Cmaker，Lightning Z，液氮，Port Royal 53558；填报核心3650/显存2333 MHz。
- 作者明确标注28.6363MHz Crystal。
- 对应<https://www.3dmark.com/pr/4007885>显示名义核心3442、显存2200、默认显存1750，描述106.06%。

按常规27MHz参考频率推算（分析，不是额外实测）：

```text
28.6363 / 27 = 1.0606037
2200 * 1.0606037 = 2333.328 MHz
3442 * 1.0606037 = 3650.598 MHz
35.2 Gbps * 1.0606037 = 37.333 Gbps
```

因此这条记录非常符合“软件名义2200/35.2 Gbps，外部参考时钟把真实工作频率抬高”的路径。其名义MODS-equivalent MCLK仅17600，低于本机18001失败请求；外部放大后可以超过36 Gbps，而无需向调频消费者提交名义18664。这是**软件请求域与实际频率分离**的重要例子，不能把它当作PMU已成功接受18664请求。

限制：3DMark页面标记INVALID，理由为硬件规格经不可验证修改/可能绕过驱动限制；本条只能视为硬改极限跑分记录，不是有效成绩认证、日用稳定性或本卡长期37.33 Gbps支持证明。

## 后续最有区分力的问题

1. DATA/CMD endpoint的正面身份与consumer代码：请求是被拒绝、执行卡住，还是只是通知丢失？
2. 目标能力/分档检查是相对offset还是绝对名义target？目前只有同一基准下18000/18001对照。
3. HYDRA实际控制方法及其与新版本驱动/PMU的兼容性：需取得获授权的工具/源码后静态检查，不能从宣传反推固件setter。
4. 在既有dump能力内如何被动保留response、pending bit2、wait状态及实际request word；不以重跑已知会停机频率替代协议定位。

## 文件与复核

- `parent_verified_instructions.asm`：parent直接对匹配ELF反汇编及SHA核验。
- `send_path/REPORT.md`：发送分支；已纠正timeout、helper入参/有效地址及mailbox地址误记。
- `completion_path/REPORT.md`、`endpoint_identity/REPORT.md`：完成/地址身份，已纠正伪循环、DATA非零与setup函数指针锚点。
- `completion_path/ghidra_*_evidence.txt`：持久保存原暂存引用/反编译输出，以原始指令为准。
- `web_sources/VERIFIED_SOURCES.md`：作者、报道、HWBOT与3DMark的浏览器核验字段及短摘。
- `frequency_crosscheck.json`：频率口径交叉计算。

环境副作用：一个子分析任务使用headless Ghidra查询时更新了现有`ghidra_static/gb202_pmu570215_runtime.rep`索引/数据库元数据；没有改ELF或旧研究报告。后续端点查询已避免打开/修改旧数据库。本轮未执行硬件实验。

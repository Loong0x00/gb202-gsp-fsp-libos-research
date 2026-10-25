# MODS 570.215：+3999 / +4000 MCLK 故障只读复核

范围：ASUS RTX 5090 GB202、本地 2026-08-25 原始诊断日志及匹配 runtime PMU ELF。仅静态分析；未启动 MODS、未访问或改写 GPU、未修改旧研究文件。

## 修正后的结论

不是 GSP-RM：两份故障日志均明确 `GSP-RM: Disabled`。不是显存测试中的数据误码：失败发生在 `SetPerfPoint()` / `InitPStates()`，测试尚未开始。

直接可定位的故障是 **PMU 的 MCLK command-0 完成等待失败后断言停机**，随后 host change sequence 超时。不能把 MODS 前端、CPU RM 和 FSP 当成穷尽的二选一：CPU RM 后还有 PMU、设备侧调频消费者、完成通知/中断路径。

此前 `MODS570215_MCLK_3999_4000_STATIC_FINDINGS_20260903.md` 把共享 `ebreak` 解读为入口 busy，并进一步推断更早 command 3/4 持锁；此次原始 mailbox 标记与异常处理器复核不支持该故障链。旧文第 5 节的“首个事务必为 command 3/4”不应继续作为已证事实。

## 1. 原始实验

日志目录：`../../vm_mods_lab/mods570215-diagnostic-20260825-logs/`。

- `edc18000-auto.log:313–315`：34008.0879 GB、1326.7389 GB/s，NewCudaMatsRandom(test 242) 正常完成；`:344` 返回 0。实际 MCLK 约 17982 MHz，target 18000 MHz。
- 基准为 14001 MHz，因此 18000 MHz 请求对应 +3999 MHz，而 18001 MHz 请求对应 +4000 MHz。
- `edc18001-auto.log:84` 与 `edc18001-msvdd1050.log:84`：GSP-RM Disabled。
- 两份日志 `:276`：relation 12 offset = 4000000 kHz；`:377–385`：异常发生于 SetPerfPoint / InitPStates。
- 两份日志 `:469`：SEPC = 0x205d1a2c；`:543`：PMU_MAILBOX(01) = 0x00025728；`:545–549`：当前栈为 MCLK command-0 链。
- 两份日志 `:553`：PMU-RISCV HALTED；`:875–876`：host 4000 ms 超时；`:1486`：change sequencer status = 0x65。公开 `nvstatuscodes.h:130` 定义 0x65 = NV_ERR_TIMEOUT。
- 自动电压和手动 1050 mV 两组均如此；这不是“加压后显存测试误码仍未改善”的证据，而是两个控制阶段失败。

## 2. 为什么此次可以区分共享 ebreak 的分支

匹配 runtime PMU ELF：

`../gb202_r570215_runtime_pmu.elf`

SHA-256：`2eef42f0b434990d2c9669124199a912e8e16d8480d1c9a74d46d75e1575b93b`。

`0x205d1a2c` 是多个分支共享的断言落点。只看 SEPC 不足以区分 busy、非法 command、等待失败、序号/响应不匹配等。

但异常处理器保存并上报了断言时的 a0：

```text
0x205cba5a: sd a0, 0x48(gp)       保存陷入时 a0
0x205ca588: ld a5, 0x48(s6)       读取异常帧中的 a0（SCAUSE=3 路径）
0x205ca596: sw a3, 0x454(a4)      写入 0xc08f6454（mailbox 1）
```

原始日志 mailbox 1 为 `0x25728`，在 primitive 内匹配的是：

```text
0x205d1ac6: jal  0x205cf612       等待完成
0x205d1aca: beqz a0, 0x205d1ad6  成功才继续
0x205d1acc: auipc a0, 0xdfa54
0x205d1ad0: addi  a0, a0, -0x3a4 -> a0 = 0x25728
0x205d1ad4: j 0x205d1a2c         等待返回非零 -> ebreak
```

入口 busy 分支使用的标记则是 `0x256c8`，不是 `0x25728`。因此应修正为 **本次 command 0 的等待失败断言**，而非已证明的 busy 重入。

`0x205cf612` 包装 `0x205cf1c8`；后者把正常结果 1 映射为 0，把底层 -0x13 映射为 4，其余异常会停在另一断言点。下层队列/事件等待代码有预算耗尽检查和 -0x13 返回路径。由此可把本次非零等待结果收窄到该失败/超时路径；无需假设另一个 command 3/4 持锁。

注意：a0 作为断言标记/元数据地址使用；本次不声称已经读取或解码该地址指向的文本内容。

## 3. CPU RM 与 FSP 的责任边界

CPU RM validator `0x6e204c0` 的原始 x86 指令执行有符号 `offset <= max` / `min <= offset` 比较，读取的是 32-bit kHz 值；未见硬编码 +4000 拒绝。原始日志也已进入 PMU 调频，故不是 MODS 无法解析 18001 或 CPU RM 普通范围拒绝。

旧研究保存的匹配 VBIOS MCLK 元数据广告范围为 -1000..+5000 MHz。广告范围并不证明下游调频固件、timing/training 与完成通知路径支持所有 target；CPU RM 可能缺少与实际能力匹配的预检查，但尚不能认定它构造错了 payload。

MCLK wrapper `0x206358ca` 明确以 command=0、timeout 参数=95000、direct=0 调用 primitive；payload 为最终绝对 MCLK target。primitive 经通用 helper 访问 `0xc09a4514` / `0xc09a4504` 等设备寄存器，并等待完成。现有证据未命名其消费者，不能直接等同于 FSP 的主机 MCTP/NVDM 接口。

公开 GB202 `dev_fsp_pri.h` 的 FSP scratch 地址为 0x008f03xx；没有把该 PMU 事务端点绑定到 FSP。既不能据此归罪 FSP，也不能穷尽排除私有内部接口、映射/别名或 FSP 的间接参与。

## 4. +4000 与 18001：仍不能混同

同一 14001 MHz 基准下观察到 +3999 成功 / +4000 失败，同时也等价于 target 18000 成功 / 18001 失败。仅这一组实验不能证明阈值属于相对 offset，而非绝对 target。

因此“4k 导致整数溢出”“固件里写死 offset >= 4000000”“FSP 锁在 +4000 拒绝”均未获证实。4000 也不是 4096；不能只凭数字称其为 12-bit 溢出。参数 4000000 kHz 与 host 超时 4000 ms 是不同单位、不同角色。

更合理的待查方向是：绝对频率能力/档位边界、调频消费者或训练转换失败、PMU 对完成事件/中断的处理、MODS CPU RM 与所装 PMU/VBIOS 的协议/能力不匹配。

## 后续建议

先静态定位 command-0 消费者、完成事件生成者以及 18 GHz 附近的目标验证/档位选择，不再重跑已知会停机的 18001。还需区分“消费者未完成”与“已完成但通知丢失”。单纯延长 host 超时、NOP ebreak 或改 relation 基准不构成已验证修复。

## 本次新增证据

- `pmu_assert_branch_evidence.asm`：直接对匹配 ELF 的关键区间运行 llvm-objdump，包含 SHA-256。
- `runtime_log_evidence.txt`：从两份失败日志与 18000 成功日志提取带原始行号的证据。

外部检索两次均遇到提供方错误；本结论不依赖未核实的网络结果。

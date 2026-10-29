# LibOS 初始化诊断：记录检查与纯模拟复现

> **后续重要补充：** 继续定位时，已经用单指令测试并与 QEMU 对照，确认 Python 模拟器存在 LUI/32 位符号扩展、W 运算、CSRS 位操作和有符号除法错误。因此下述零节点循环不能先归因为 BootROM 缺失；应先建立正确的执行语义基线。详见 [HOW_TO_FIX.md](HOW_TO_FIX.md) 与 `10_isa_semantics_probe.log`、`11_qemu_isa_reference.gdb.log`。原始 QEMU CSR 异常和启动桩寄存器问题的实测证据不受影响。

## 范围与限制

- 检查项目已有文档、`rv64_emu.py`、`emu_bench/` 中现存内核和引导镜像。
- QEMU 11.1.2，`virt` 板、`rv64` CPU、TCG、1 hart、1 GiB 内存；无网络、无磁盘、无 VFIO。
- 未找到保存下来的完整 RISC-V QEMU 启动命令，因此本次是根据镜像和引导桩重建的最小启动环境，不声称完全还原旧实验参数。
- 未操作真实 GPU，也未操作已有的 x86/VFIO QEMU 进程（观测时 PID 63532）。只结束了诊断脚本自身启动的进程。
- 原有源文件和二进制未修改。新增脚本、命令、日志均在本目录。GDB 改寄存器仅发生在一次性模拟实例中。

## 实际 QEMU 结果

代码原始分段经核对：`kernel_code.bin` 是 REAL ELF 的前 0xe000 字节，装入 PA 0x92fff000；`kernel_data.bin` 是随后 0x1b000 字节，装入 PA 0xa3000000。引导使用现成的 `boot_stub_clean.bin`，它与 `boot_stub.elf` 的 .text 一致。

| 实验 | 观测 | 含义 |
|---|---|---|
| 01：现有 stub 进入 init | PC=0xffffffff93001ec6，sp=0，a0=0xa3100000，a1..a7=0，stvec=mtvec=0 | stub 跳过原始引导，却没有补齐其栈和启动 ABI |
| 02：现有 stub + 原始代码继续 | mepc=0xffffffff930044be，mcause=2，指令 `csrw 0x5ca,a3` | init 的窗口初始化辅助函数依赖标准 QEMU 不支持的 NVIDIA CSR |
| 03：回到原始 boot 入口，设置 a0=0x30、a7 为内核数据地址 | mepc=0xffffffff93000002，mcause=2，指令 `csrwi 0x5d0,0` | 不跳过 boot 时，第二条指令就遇到平台专有 CSR |
| 04：只补 sp 和 a0 | 仍在 0xffffffff930044be 遇到同一 CSR 异常 | 栈/参数和 CPU 平台支持是彼此独立的问题 |
| 05：现有 stub + 现成 kernel_selective.bin | mepc=0xffffffff93000390，mcause=7，mtval=0，指令 `sd a2,0(a5)`，a5=0 | NOP CSR 后出现零地址写入；轨迹明确是 a0 检查失败后走到未就绪调度/数据结构路径，不能简单归因于某个未知 global 字段 |
| 06：补丁镜像，补 sp、a0=0x30、a5=3 | mepc=0xffffffff930052e8，mcause=13，mtval=0x0c00000000000200 | 通过可见参数检查后，启动数据复制源地址在当前映射下不可用 |

实验 06 中的寄存器值只是按反汇编中的比较条件设置，**并不等于恢复了真实 BootROM ABI**。其页故障证明简单补几项寄存器仍不够，不能独立证明真实硬件一定从该精确地址读取，或仅实现某一种映射就能启动。

相关文件：`01_*.gdb.log` 到 `06_*.gdb.log` 为寄存器证据；同名 `.qemu.log` 为指令/异常日志；`.command.json` 保存 QEMU 参数。串口无输出；诊断结论来自 GDB 和 QEMU 跟踪，不来自串口。

## 已确认的分层问题

### 1. 不是通用 RISC-V virt 平台可以直接启动的固件

原始 boot 使用 CSR 0x5d0/0x5d1，以及 0x5ca–0x5cf 一组窗口配置指令。Python 模拟器对部分写入模拟别名，但标准 QEMU rv64 CPU 没有相应设备/CPU 扩展。

`kernel_selective.bin` 对这些指令做 NOP，只是消除异常，**并没有实现窗口映射的副作用**。后续读写失去原有地址空间语义是合理风险，不能将“跑过更多指令”当作平台初始化成功。

### 2. 当前启动桩没有复现原始引导状态

`../boot_stub.s:68–100` 直接跳入 init，并将 a0 设置成 0xa3100000，但没有设置 sp；而原始代码在 0x93000104 建立栈，0x9300010c 恢复启动参数。init 在 0x93001f3e 检查原始 a0==0x30，之后还检查原始 a5==3。

stub 只把一个指针写到 0xa2ff2010，没有建立对应完整结构或启动描述符。这个写入不是完整 BootROM 初始化的替代品。

另外，早期 mtvec=0；本次非法指令/访问异常转入 M-mode 的地址 0。仅设置后续 stvec 不等于已经有 M-mode 服务、异常委派或 BootROM 实现。

### 3. Python 模拟器能前进，但仍在零节点链表上不收敛

原样运行 `rv64_emu.py` 首先因 `/tmp/kernel_gb20x.elf` 不存在而失败，见 `07_legacy_python_entry.log`。

只改诊断加载路径，加载持久化的 REAL ELF；未增加任何指令 hook、任务构造或新别名。执行 10,000,000 步，见 `09_python_boot_10m.log`：

- 前约 8.39M 步主要执行 `0x93005206–0x9300521a` 的内存填充循环；a5、页数和 ecall 计数都在变化，这是耗时工作，不是已经证明的死循环。
- 最后一次调用为 ecall #192（通道参数 a0=0x3f）。
- 8.5M–10M 步期间 ecall 计数固定 192、内存页数固定 2094，反复运行 `0x93008b02` 周边和 `unlink@0x930005dc`。
- 结束时 s1=0，s0=-0x20，a0..a5=0。反汇编显示 s1 是从链表头取出的节点；随后把零节点交给 unlink，并读取 node-0x20。Python 稀疏内存对未分配地址自动创建零页，因而不会像真实保护机制那样立即报错。
- 这与旧记录的零节点池/链表遍历现象吻合。有限步数复现不证明所有输入下都永久不收敛，但当前启动输入没有完成 init。

源码风险：

- `rv64_emu.py:407–411`：全部 ecall 都返回 a0=0，不区分 BootROM 服务、没有必要的输出/内存副作用建模。因此“服务成功”并非运行事实。
- `rv64_emu.py:21–47`：地址转换仅应用手工别名；没有完整 Sv39、访问权限或缺页处理，未映射内存默认为零。
- `rv64_emu.py:130` 的 memset 快进仅匹配高地址 0xffffffff93004eea，与这份 REAL GB20X 内核实际频繁执行的低地址 0x93005206 不一致，导致前期看起来特别慢。
- 定时器/WFI 是合成行为，MMIO 没有完整 GPU 设备模型。它们属于保真度缺口，本次尚未证明它们是首个卡点。

**仍不能确认的部分：** 缺失链表状态究竟应由哪个 BootROM 服务、启动参数、固件输入或某处内核流程建立，尚未定位到唯一生产者。旧文档“BootROM 初始化的池结构缺失”是合理方向，不应升级为已经完整证实的硬件 ABI。

### 4. 镜像/脚本的可复现性问题

- 多个 Python bench 硬编码 `/tmp/kernel_gb20x_REAL.elf`、`/tmp/rm_fw.elf`；本次均不存在。
- 旧记录曾混用不同内核构建。V3 文档 502–507 行明确指出 `kernel_full_disasm.txt` 为另一构建，当前应核对 `kernel_gb20x_disasm.txt` 与实际 ELF 字节。
- `boot_stub.elf` 实际是带 Linux interpreter 的 PIE；本次没有把它当成可直接加载的裸机 ELF，而是使用已经验证的 .text 原始二进制。
- REAL ELF 的节头表在截取文件范围外，readelf 会警告；程序段及实际代码/数据可读取。本次使用核对过的原始段，不把节头告警误认成已证明的执行首因。
- `pagetable.s` 中“0xffffffff... 超出 Sv39”的旧注释不正确：0xffffffff93000000、0xffffffffa3000000 都是合法的 Sv39 符号扩展地址，本次已经实际执行到高地址 init。真正缺的是平台地址语义和启动状态，不能仅凭地址高位判断。

## 旧记录索引

- `../../KERNEL_PRIVESC_C1_C2_PROOF_20261008.md:95–101`：memset 别名、ecall #192、完整 init 未完成。
- `../../GSP_PRIVESC_FINAL_PLAN_20261008.md:285–292,323`：0x93008b2a/unlink 池结构遍历及 BootROM ABI 假设。
- `../../★AUTHORITATIVE_PROGRESS_v3_20261015.md:502–507`：正确构建、init 地址、启动状态的运行时来源判断。
- `../../★V5_STATUS_20261016.md:143–156`：QEMU/GPU/global/null pointer 简要结论。

## 建议优先级

1. 固定唯一内核版本、段装载地址和持久化文件路径，建立可重复的启动参数基线。
2. 正确复现原始引导的栈、寄存器与 trap/M-mode 服务契约；不再把任意 global 指针当作完整启动状态。
3. 建模自定义 CSR/窗口映射的副作用，而不是继续 NOP。
4. 沿已经复现的零节点链表定位其初始化生产者，再按实际需要补 BootROM 服务返回值和写内存行为。
5. 性能优化 memset 与平台保真度修复分开验证；性能改善不代表完整初始化。

## 重跑

只使用纯模拟，不依赖外部 VM。重跑会覆盖本诊断目录内同名日志，不覆盖原项目文件。

```sh
python run_qemu_diagnostic.py
python -B -u run_python_diagnostic.py 10000000 > python-rerun.log 2>&1
```

QEMU 每个实例都有超时、core dump 禁用和 8 MiB 日志上限。现有交叉 GDB 的 Python 辅助模块有版本不匹配警告；硬件断点和寄存器读取成功，并与 QEMU 异常日志互证，这不是 LibOS 自身错误。

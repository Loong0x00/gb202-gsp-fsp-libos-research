# LibOS 610.57.04 → 615.78.08：已确认变化

## 结论

**固件包中对应GB20x/GB202的LibOS内核确实变了**，不只是GSP-RM变。公开辅助代码的目录名仍为libos-v3.1.0，但不能用该目录名判断固件内核相同。

## 公开代码

两版本 `src/common/uproc/os/` 仅三份文件改动，70行增加、35行删除：libos_log.h、libdwarf.c、liblogdecode.c。主要是指针转换、nv_stddef include、日志前缀拼接及坏metadata日志记录的有界重同步。详见libos-public-diff.md。

`libos_init_args.h`、`libelf.h`、`libelf.c` 没有变化。其中init_args的SHA256两版同为75174fb8b643fa28537acba0cf3d936f292e99a1590762ccd4936be093ae33a1。

这只是公开host/helper代码及共享头，不是完整的LibOS内核调度/IPC实现。前一轮的GSP_ARGUMENTS_CACHED、MCTP、GMCAPI/NVKV变化应主要归于RM启动/通信层，不能直接说成LibOS syscall ABI变化。

## 实际kernel_gb20x.elf

从各版本官方gsp_ga10x.bin的命名catalog定位kernel_gb20x.elf，而非直接套旧偏移。对record的代码/数据引用、VA、长度与目标ELF的PT_LOAD逐项校验；610提取结果还与既有QEMU lab的生产fixture哈希完全相同，排除了混入相邻GH100 kernel的错误。

| 项目 | 610.57.04 | 615.78.08 |
|---|---:|---:|
| catalog基址（outer文件偏移） |0x6d040|0x69040|
| kernel ELF outer偏移 |0x10d040|0x12a040|
| RX段 |0xe000 / 56KiB|0x10000 / 64KiB|
| RW段 |0x1b000 / 108KiB|0x24000 / 144KiB|
| LOAD合计 |164KiB|208KiB|
| RX VA |0xffffffff92fff000|相同|
| entry VA |0xffffffff93000000|相同|
| RW VA |0xffffffffa3000000|相同|

LOAD合计增加44KiB，RX增加8KiB、RW增加36KiB。RX含一页ELF头/元数据，不能把整段大小当作纯指令大小。

旧LOAD SHA256：d556e44f4b542ed801b43d31a0d4c5e1cbbf030b2871adb16f2b582b7aa9db44。
新LOAD SHA256：1c88a9738b9fcd22bdb0a5fdf0382d75906e5edf6ffa920731ab551742cb2b2d。

排除最前0x1000头部页后，代码区域hash仍不同；入口起仅前117字节相同。按相同offset比较有大量差异，但包含重排、地址重定位等，**不能据此声称内核被重写或某个syscall语义变化**。具体调度、对象/句柄布局、系统调用差异还需函数级匹配。

## 产物

`libos/kernel-comparison.json`：定位、各段大小、全部hash和比较方法。

`libos/{610.57.04,615.78.08}/`：
- kernel-original-full.elf：原始完整内嵌ELF，未修改；
- kernel-load-segments.elf：仅LOAD字节，兼容既有fixture形式；不含ELF尾部section table，工具可能因此报section越界；
- code.bin、data.bin：原始段；
- kernel.linear.asm：从真实高地址入口开始的线性反汇编。

上一轮Ghidra工程是低地址GSP-RM主任务，不是这个高地址LibOS kernel。本轮已单独导出两版LibOS反汇编，尚未在Ghidra中完成内核函数级匹配。旧lab的硬编码catalog/ELF偏移和断点不能直接用于615。

以上均为静态文件分析；没有运行QEMU、加载新固件、访问GPU寄存器或更改驱动/温控/权限。

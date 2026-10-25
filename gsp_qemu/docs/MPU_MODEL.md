# 固件驱动的 GSP MPU 模型与真实启动进展

## 当前可复现的结果

```sh
make test-mpu
make probe-kernel
```

纯 QEMU 中，未修改的 610.57.04 生产 LibOS 执行结果（2026-10-18，`handoff=fixture` profile）：

```text
ORIGINAL_BOOT_REACHED_INIT
  pc    = 0xffffffff93001ec6
  sp    = 0xffffffffa3008000
  satp  = 0xf000000000000000
  a0    = 0x30
  a5    = 3
  a6    = 0x7400000000000600
BOOT_REGION_TABLE_ACCEPTED
  pc    = 0xffffffff93002052
  va    = 0x8000000000800000   # (3<<58) + (FB+0x800000)
  len   = 0x0f800000
  pa    = 0x7400000000800000
NEXT_UNMODELED_INPUT reason=init_args
  pc    = 0xffffffff9300395e
  a0    = 0xb   (11)
  line  = 0xdc  (220: 0x93005550 returned non-zero)
TRAP_AFTER_PANIC
  mcause= 0x5
  mepc  = 0xffffffff930041c2
  mtval = 0xffffffff60050800   # log window VA, no MPU window in this profile
```

这是 **CPU/MPU 子系统回归**：测试驱动从 M-mode 进入原始 boot 入口，内核自己配置窗口、切换别名、建立栈并进入 init。没有 NOP、强制分支、跳过 init，也没有回答任何 NVIDIA SBI 调用。

它不是完整 FSP/FMC/BootROM 认证链的启动证明。测试驱动的初始寄存器是按可见消费者构造的受控输入，不宣称已恢复完整硬件 handoff ABI。物理装载布局也是测试配置，不宣称真实芯片总使用该地址。`handoff=fixture` 是**声明式功能 profile**：签名包门禁照跑，FB/SYS aperture 由真实 RAM 支撑，区域表只声明被支撑的区间；它不声称 BootROM/熔丝认证。

历史基线（2026-10-18 上午，`a6=0`，未建模区域表）停在 `mcause=0xd / mtval=0x0c00000000000200`。
该输入现已被本 profile 的区域表模型替代，见 `docs/LAB_BOOT.md` 的实测表与 `PROGRESS.md` 的检查点。

## 原始字节的来源

`prepare-kernel-fixture.sh` 直接读取：

- `/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin`
- offset `0x10d040`，执行段范围 `0x29000` bytes
- SHA256 `d556e44f4b542ed801b43d31a0d4c5e1cbbf030b2871adb16f2b582b7aa9db44`

执行段原样提取到本目录 `firmware/kernel-610.57.04/`，不依赖旧 Python 模拟器或旧 bench 脚本。ELF 节头位于被打包执行段之外，不用于执行装载。

不是仅信任旧文件名或硬编码 offset：生产 catalog 的 `fwimage+0x6d2b0` 确认名称为 `kernel_gb20x.elf`；其 code blob offset 字段为 `0xa0000`，相对 catalog 基址 `0x6d000`。加 outer `.fwimage` 文件偏移 `0x40` 得到 `0x10d040`。catalog 同时确认 code `0xe000`、data `0x1b000`；提取脚本已检查名称、字段和哈希，避免把相邻 GH100 模块混进来。

## 从固件恢复，而不是等手册

以下地址均为该内核的链接 VA 低 32 位，完整 VA 带 `0xffffffff` 前缀。

| 已实现行为 | 原始固件证据 |
|---|---|
| 128 个索引槽 | `0x9300a6d4` 掩码 `0x7f`；`0x93006eaa..6ece` 扫描至 `0x80` |
| index / VA+valid / PA / range / attr | boot `0x9300002a..100`、映射 `0x93004498..450a`、fault path `0x9300a6de..708` |
| VA bit0 valid，低 10 位对齐 | 写 VA 时 OR 1；失效 `0x93006ebc` 使用 mask `-0x400` |
| MODE=15 的地址窗口翻译 | boot `0x9300004c..52` 设置 `satp.MODE=0xf`；代码继续依赖新窗口取指 |
| S/U 各自 R/W/X 位 | 原始 64 项属性 LUT `0x9300a538`，以及 boot code RX `0x02040028` / data RW `0x02040018` |
| S-mode 权限 bits3..5；U-mode bits0..2 | LUT 低位分别产生 `1,2,0xc` 和 `8,0x10,0x28`，与实际 fault/boot 访问用途互证 |
| 每个映射字段写入都要更新/失效 | fault path 先写 VA，再 PA/range/attr；不能错误地只把 VA 最后一次写视为 commit |
| 独立选择寄存器的初始清零 | boot `0x93000002..0e`；仅恢复 5d0/5d1 的 0/1 清零子集，非零事件配置仍明确 illegal |

高位 attr 原样保存；目前没有声称恢复所有缓存、内存类型、硬件域语义。模型为实验性 `-cpu nvidia-gsp`，标准 ISA 仍由 QEMU 执行，不是另写解释器。

## 与旧解释器现象的区别

正确执行 LUI 符号扩展后，本测试由物理入口 `0x93000000` 起步。原始代码先建立临时 identity 窗口，再创建 canonical 高地址代码窗口，通过自己的 `jr` 进入高地址，随后撤销临时窗口。

因此旧 Python 模拟器所谓“高地址启动后跳低别名”的现象不能拿来定义芯片行为。它的 LUI 实现曾经执行错误。

## 安全性与回归

- 17 个真实执行的 S/U 正负案例：索引读回、数据读写、W^X、S/U 隔离、动态改 PA、改权限、失效、1 KiB 子页、越界索引、未实现 CSR、U-mode CSR 权限。
- 标准 rv64 必须拒绝 MODE=15/专有 CSR；实验性 CPU 才接受。
- 对未知的冲突窗口优先级、子页 VA/PA 偏移不共页、未知配置明确报错，不猜结果。
- 已实现每 CPU 状态、reset 清零、迁移 subsection/索引边界校验。完整跨进程迁移尚无运行测试，不把 schema 编译成功当成迁移验证。
- 必要的同模型审查：`openai-codex/gpt-6.1-sol`，job `sa_5485b86d55d947d2`。发现一个 High：整页 TLB 缓存可能遮蔽页内冲突窗口。
- 已修复：扫描候选页内**所有**有效窗口边界，必要时使用子页逐次翻译；同时检查完整访问区间。新增两例：外侧预热后访问内侧冲突、跨边界的非对齐访问；两者必须明确拒绝未知优先级，不能缓存绕过。

## 启动区域表：消费者契约与已建模输入

从 init 指令恢复的消费者契约（全部由原始指令直接读出）：

- source = `(entry_a5 << 58) + entry_a6 + 0x200`，64 位回绕
- copy length = `0x180` = 384 bytes，16 项，每项 24 bytes
- 可见字段：首字节 selector，`+8` base，`+16` size；`size==0` 的项被跳过
- destination = `0xffffffffa300b7a8`
- 逐项检查 `[base, base+size)` 是否落入 `0x9300c918` 的 8 个允许 aperture
- 通过后写入 9 项区域记录（`0xffffffffa3008e28`，24 字节步长），并把物理 base 记到 `+216 + i*8`

`make probe-lab-table` 直接从原始 SBI server 运行时抓取这张表（`logs/lab-boot-region-table.bin`）：
本 lab profile 由生产代码生成 4 个非空项（FB heap / FB meta / FB aperture / SYS），
并给出 init 解析后的 9 项记录（`logs/lab-region-records.bin`）。内容与回绕编码见 `docs/LAB_BOOT.md`。

`nvidia-gsp,handoff=fixture` 是审计分支的声明式模型：

- 仍执行生产 FMC 包的 SHA384/ECDSA-P384 验证（`stage=SIGNED_PACKET_VERIFIED`）；
- FB aperture `0x7400000000000000` 256 MiB、SYS aperture `0x9400000000000000` 16 MiB 均为真实 RAM；
- 区域表放在 `FB+0x800`，只声明这三段被真实支撑的区间（WPR heap / WPR meta / SYS）；
- 驱动用生产回绕编码传入 `a6 = FB_BASE + 0x600`，于是 source = `0x8000000000000800`，
  经内核自己的 window 0 落到 `PA 0x7400000000000800`。

本 profile **不**声明整段 FB aperture 的“补齐到 2^58 末尾”项（生产 SBI server 会发），因为该段绝大多数没有 RAM 支撑；
也不伪造 SBI 返回值、global 指针或空表。

### 下一处缺项

1. **handoff init 参数 blob**：入口 `a1`（指针）/`a2`（大小）在本 profile 为 0，`0x93005550` 解析失败，
   init 走 `line 220` 致命路径（`0x9300395e` 的 `a0=11, a1=0xdc`）。生产 lab 中 `a1=0x740000000801c000`、`a2=0x7e4000`，
   由原始 SBI server 构造。
2. **内核日志窗口**：致命路径写 `0xffffffff60000000+`（静态区域记录 kind=2，size 8 MiB），本 profile 没有对应 MPU 窗口，
   于是 `mcause=5 / mtval=0xffffffff60050800`。生产 lab 由 SBI server 在进入内核前建好该窗口。

两者都属于 boot handoff / M-mode 服务输出，属 `NS-Q2` 范围；审计分支到此为止是**正确停止**，不是启动成功。

### 已找到可继续逆向的原始生产者代码

原始 `.fwimage` 开头已有**明文初始化分区和 SBI 客户端**，本轮提取了原始 `0x40..0x6e040` 字节，保存为 `firmware/gsp-bootstrap-610.57.04.bin`。不能误把这个 S-mode 客户端直接称为 M-mode SBI 服务实现。

可复核定位：

- entry `+0x0` → main `+0x1e0a`
- `+0x45e..0x526` 保存上下文并发出真实 ecall
- `+0x3a70`：vendor EID `a7=0x090001eb`，FID `a6=0`
- `+0x3a86`：同一 EID，FID `a6=7`
- `+0x3a7e`：EID `8`，a6=0，fatal/shutdown 路径，不能统一返回成功
- 新模型的 SBI 观测必须记录全部 a0..a7，尤其 a6(FID)；旧 Python 日志省略 a6，不能据此断言调用服务号或重试原因
- `+0x6d000` 后的原始模块 catalog 含各型号 kernel ELF；`+0x1e0a` 附近选择型号、配置后续加载函数

静态结果存于 `logs/bootstrap-first.asm`、`bootstrap-main.asm`、`bootstrap-services.asm`。下一步沿初始化分区的请求构造和 M-mode 服务边界恢复这张表的生产过程，按真实分配的内存生成合法输入，并实现对应的 BootROM/SBI 行为。不是等待不存在的手册，也不是填写一张能让检查通过的假表。

## 完整链的处理原则

- 可以实现等价、可验证的 BootROM 行为模型；不必把厂商 ROM 原始字节当成唯一道路。
- `make preflight` 仍用于审计原始 ROM 输入分支，它的 `BOOTROM_REQUIRED` 不是整个项目的停止条件。
- CPU 子系统回归允许明确的夹具边界，但不得把它标记成完整 GSP 启动或硬件认证。
- 继续恢复每个尚缺的内存输入、服务副作用和设备行为；原始固件中的检查必须真实执行。

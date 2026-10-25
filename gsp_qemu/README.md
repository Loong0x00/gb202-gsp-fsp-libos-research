# QEMU-only NVIDIA GSP/LibOS 启动链开发

**当前状态：实验性 NVIDIA MPU/CSR 模型 + `nvidia-gsp-lab` 功能 profile；生产 FMC 签名、原始 LibOS init 和 walk 表发布已在 QEMU 中真实执行。完整 FSP/FMC/LibOS/GSP-RM 启动链尚未完成。**

最新模型、原始字节依据及下一处启动表问题见 [docs/MPU_MODEL.md](docs/MPU_MODEL.md)。缺公开手册不再作为停止条件，按原始固件恢复行为并用 QEMU 回归检验。

本目录是后续唯一执行主线，不使用 `rv64_emu.py` 或其他 Python CPU 模拟器。Python 可用于 QEMU 构建、官方数据提取或 GDB 内部辅助，但不参与任何固件指令执行；CPU/固件执行一律在 QEMU。

## 已实现

- 独立 QEMU **11.1.2** 开发构建，不替换 `/usr/bin/qemu-system-riscv64`。
- 新增 `-machine nvidia-gsp` 启动链开发入口。
- C 实现的生产 FMC GFW/ROM 包解析、长度/范围/对齐/重叠检查。
- 实际 **SHA384 + ECDSA-P384** 验证，不以 CRC、哈希单独代替签名。
- 生产公钥 SHA256 独立核对 NVIDIA 官方 610.57.04 release commit；不默认信任包内自带公钥。
- 核对 GFW 签名覆盖的 code/data/manifest 与 BootROM 输入包的对应内容逐字节相同，避免版本/镜像混配。
- 按官方 HAL/header 派生 BootROM DMA 地址计划，检查 256-byte 对齐、52 位边界和高位编码；这是输入计划，不是已工作的 DMA 硬件。
- 实验性 `-cpu nvidia-gsp`：128 个索引式窗口、MODE=15、S/U 独立权限、映射修改/失效后的 TLB 刷新与子页边界保护。
- 原始 LibOS boot → init 回归：代码直接从生产镜像提取并验证哈希，不执行旧解释器、不 NOP、不直接跳 init。
- `nvidia-gsp-lab` 功能 profile：生产 FMC SHA384/ECDSA-P384 验证通过后才建模 Booter 的 `verified` 位；原始 SBI server 创建/加载 GB20X 内核和 init 任务。
- 原始 LibOS 已执行到 `0xffffffff93007324`（`sd s7,0x450(s0)`），并在本 profile 下发布 walk 表地址；详见 [docs/LAB_BOOT.md](docs/LAB_BOOT.md)。
- 384B 启动区域表：生产者（原始 SBI server）实测 + 消费者契约（`(a5<<58)+a6+0x200`、16×24B、8 aperture 校验、9 条区域记录）；审计分支用 `handoff=fixture` 只声明被真实 RAM 支撑的区间并通过该检查点。
- 保留原始 ROM 输入分支的审计门禁；它不是唯一开发路线。可以实现可验证的 BootROM 行为模型，不需要等待原始 ROM 字节。
- 只在纯 TCG 中测试；无网络、无磁盘、无 GPU/VFIO 操作。

## 实际验证结果

```text
GSP stage=SIGNED_PACKET_VERIFIED SHA384/ECDSA-P384;
    code=225280 data=59392 manifest=2560
GSP stage=BOOTROM_REQUIRED
```

`SIGNED_PACKET_VERIFIED` 仅证明所选生产信任锚下的宿主侧包签名成立，**不等于芯片熔丝策略、BootROM 认证/解密、FSP 启动或 LibOS 启动成功**。

`BOOTROM_REQUIRED` 仅表示原始 ROM 输入审计分支缺少输入，当前 `make preflight` 因此返回 1。它不是继续建立行为模型的障碍。

新 CPU 子系统的真实结果（`handoff=fixture` 声明式 profile，2026-10-18）：

```text
ORIGINAL_BOOT_REACHED_INIT pc=0xffffffff93001ec6
sp=0xffffffffa3008000 satp=0xf000000000000000 a0=0x30 a5=0x3 a6=0x7400000000000600
BOOT_REGION_TABLE_ACCEPTED pc=0xffffffff93002052
va=0x8000000000800000 len=0xf800000 pa=0x7400000000800000
NEXT_UNMODELED_INPUT reason=init_args pc=0xffffffff9300395e a0=0xb line=0xdc
TRAP_AFTER_PANIC mcause=0x5 mepc=0xffffffff930041c2 mtval=0xffffffff60050800
```

历史基线（`a6=0`、区域表未建模）停在 `mcause=0xd / mtval=0x0c00000000000200`。

384 字节启动区域表的**生产者**已实测：`make probe-lab-table` 从原始 SBI server 抓表
（`logs/lab-boot-region-table.bin`，本 profile 4 个非空项），并抓 init 解析后的 9 条记录
（`logs/lab-region-records.bin`）。审计分支用 `handoff=fixture` 只声明被真实 RAM 支撑的区间。
下一处缺项是 handoff init 参数 blob（`line 220`）和内核日志窗口（`0xffffffff60000000`），
详见 `docs/MPU_MODEL.md`、`docs/LAB_BOOT.md`。

`nvidia-gsp-lab` 功能 profile（同一生产输入 + 真实签名验证）已继续执行：

```text
BOOTER_SIGNED_PACKET_VERIFIED P384/SHA384
    gfw=287304 bootloader=290816 gspfw=84258816
host region[0] id8=2 pa=7400000000801000 size=00000000007ff000
...
LAB_WALK_WRITE_BEFORE hit=1 global=0xffffffffa3013030 table=0x800000000803a000
LAB_WALK_INITIAL global=0xffffffffa3013030 table=0x800000000803a000 stored=0x800000000803a000
LAB_WALK_WRITE_BEFORE hit=2 global=0xffffffffa30134d0 table=0x8000000008046000
LAB_WALK_POPULATED global=0xffffffffa3013030 table=0x800000000803a000
LAB_WALK_TABLE_ADDRESS=0x800000000803a000
LAB_WALK_GLOBAL=0xffffffffa3013030
WALK_TABLE_INITIAL_SHA256=98dbb968929aded4b23a8a020cb58a5840184d181db32e03b45a5f71d5df50d6
WALK_TABLE_SHA256=6f1efbdd5c9f877767d261eaee3398d19978d5f70a0614a827a56279df3c339d
WALK_TABLE_INITIAL_HEADER=0xb,0x80,0x2
WALK_TABLE_HEADER=0xe,0x80,0x1
WALK_TABLE_ALLOCATED=0x1:0x8000000008028088:0x8000000000000001 ...
```

第一次发布时表还是 free-list（`meta=0`）；第二次发布后同一个表已填充有效项，`meta=[entry+16]` 的 bit63=1，符合 `0x9300a090` 的 lookup。

这证明原始生产 LibOS 在 QEMU 功能 profile 中真实执行到任务卡指定的 walk 表发布指令，并给出本 profile 的表地址；**不等于真机 32GB FB 布局、芯片熔丝/BOOTROM 认证、FMC 解密或 GSP-RM 已完成**。`0x800000000803a000` 是本 profile 的地址，真机探针应使用真机布局的地址。

### 测试

- 42 项 C 正/负向检查，ASan + UBSan。
- 5000 个有界畸形输入健壮性检查（不等同完整模糊测试覆盖）。
- 纯 QEMU RV64 汇编边界测试：LUI、SEXT.W、ADDW、CSRS、DIV/REM、除零/溢出、压缩 LW。
- QEMU 门禁：缺 BootROM、错误信任锚、禁止 `-kernel` 捷径、缺包、超大文件、FIFO/特殊文件、错误 ROM 哈希。
- 独立的四字节合成 ROM 只检查只读映射、reset PC 和 reset 回调；CPU 保持 `-S`，不执行 NVIDIA 固件或 LibOS。
- ISA 测试固件仅在 **virt 平台**运行，不是 NVIDIA ROM，也不会作为替代 ROM 启动 LibOS。
- 17 个 S/U MPU 正负执行案例、2 个页内冲突/跨界拒绝回归、2 种 CPU 的专有功能隔离回归。
- 原始生产 LibOS 的 boot → init 回归，不代替完整认证链测试。
- `make test-lab`：`nvidia-gsp-lab` 从签名 FMC 验证、原始 SBI server、LibOS init 到 `0xffffffff93007324` 的 walk 表发布检查点；断言 `[global+0x450] == s7`，回读 4096 字节表（116 项、稳定 SHA256），并验证错误信任锚在 CPU 启动前被拒绝。
- `make test-lab-isolation`：纯合成分区隔离负向回归，不执行 NVIDIA 固件。
- `make test-lab-release`：直接调用真实 t0=23/t0=4 handler 的诊断，验证 create→release 的 state/refcount/表项变化；明确不是用户 syscall 或对象销毁闭环。
- `make test-lab-destroy`：直接调用真实 0x93005B26，验证 refcount→0、TYPECALC、dtor 0x93008130、S-mode entry；明确不是 U-mode 可达的攻击路径。
- `make test-lab-gadget`：受控 a1/PC 进入 0x930035d2 (`mv a0,a1; jal 0x93005B26`)，验证 gadget→ref 0→S-mode dtor；明确不是 U-mode 可达性证明。
- `make test-lab-fastpath`：受控 t0=4/stval=0 进入 0x930042f8，验证 fast path 只做 state 0→1、ref 不变、不调 0x93005B26/handler；明确不是真实 U-mode trap。
- `make test-lab-t017`：验证 t0=17 handler 释放的是新分配对象 s1，不是用户 a0 s2；t0=17 是 create/register，不是 destroy。
- `make test-lab-statecond`：验证 slow handler 在 state=1/ref=0 不 dtor、state=0/ref=0 走 0x93005B26→S-mode dtor；并说明普通 U-mode t0=4 fast path 不会进入该 slow handler。
- `make probe-lab-table`：在原始 SBI server 运行时抓取 384B 启动区域表与 init 解析后的 9 条区域记录（证据采集，不写 guest 内存）。
- `make probe-kernel`：`handoff=fixture` 声明式 profile 下，原始 LibOS 通过区域表检查，并记录下一处未建模输入（handoff init 参数 / 日志窗口）。

## 使用

```sh
cd /home/user/rt_5090_project/gsp_qemu
make build
make test          # 全部包验证、ISA、MPU、原始内核、lab walk 表回归
make test-mpu      # 专有窗口/权限和 TLB 回归
make test-lab      # 签名 FMC + 原始 LibOS → walk 表发布检查点
make test-lab-isolation  # 合成隔离负向回归
make test-lab-release    # 直接 handler 的 create→release 诊断
make test-lab-destroy    # 直接 decref→dtor 诊断
make test-lab-gadget     # 受控 a1/PC 的 gadget→dtor 诊断
make test-lab-fastpath   # 受控 t0=4 fast path 诊断
make test-lab-t017       # t0=17 create/register 反例诊断
make test-lab-statecond  # slow handler state/ref 条件诊断
make probe-kernel  # 原始 boot → init → 区域表接受，记录下一处真实缺项
make probe-lab-table  # 原始 SBI server 生成的 384B 区域表 + 解析记录
make preflight    # 仅原始 ROM 输入审计分支
```

重提取本地匹配的生产固件：

```sh
make extract
```

使用 NVIDIA 官方 `nouveau/extract-firmware-nouveau.py`，输入默认 `/home/user/rt_5090_project/gspkm`，版本必须为 610.57.04。输出仅在本目录 `firmware/`，不会修改系统固件。

依赖：C 编译器、Meson、Ninja、GLib、OpenSSL 3、zlib、RISC-V GNU binutils。QEMU 源码和固件已经准备好；可移植的重建补丁在 `patches/`，全新检出可使用 `scripts/bootstrap-qemu.sh`。

## 还缺哪些真实启动阶段

工作目标链路（具体 GB202 FSP/SEC2 分支以匹配版本官方 HAL 为准）：

```text
宿主启动元数据 / FSP 启动协议
    → GSP BootROM 的认证、载荷解码/解密和初始硬件状态
    → 原始生产 FMC / M-mode 运行环境
    → 原始 LibOS boot → init
    → GSP-RM 任务
```

继续按实际消费者和生产者补齐模型，而不是等待完整手册：

1. CPU/MPU 已有固件驱动的实现；高位 attr 的完整域/缓存行为、未知窗口冲突优先级和部分专有寄存器仍待恢复，不能静默猜。
2. `nvidia-gsp` 审计分支已用 `handoff=fixture` 穿过 16×24 字节区域表（只声明被真实 RAM 支撑的区间）；下一处缺项是 handoff init 参数 blob 与内核日志窗口。`nvidia-gsp-lab` 功能 profile 由原始 SBI server 生成同一张表并执行到 walk 表发布。不得用假 global、空表或未支撑的地址混过检查。
3. `nvidia-gsp-lab` 已得到本 profile 的 walk 表地址，但表内容位于 handle/内核对象空间；当前 MPU/handle 翻译未在回调上下文成功采样。需要继续恢复 CSR 1487/handle 表语义并读出表项。
4. 生产镜像开头存在明文初始化分区与 SBI **客户端**，可继续追请求构造；它不是已发现的 M-mode 服务端。已确认 vendor EID/FID，不能再对所有 ecall 返回成功。
5. FMC 包的认证/不透明载荷处理、M-mode 服务、DMA 和设备模型仍需完成。允许等价、可验证的 BootROM 行为模型，但不能把 CPU 子系统回归当作完整认证链启动。
6. GSP-RM 任务尚未启动；`init.elf` 后续 map（错误字符串 `0x20004bb0` 路径）和 RM 依赖的服务仍需补齐。
7. `-bios`/ROM 摘要/显式地址仍可用于真实 ROM 输入研究；缺这项输入不妨碍上述模型开发。

不跳过原始固件检查，不靠 NOP、直接跳 init 或假 SBI 返回值制造成功。当前已从“只有门禁”推进到真实原始 boot 执行，尚不能宣称完整 GSP/RM 已运行。

## 来源与版本

- QEMU tag `v11.1.2`，commit `4fc49f46dc95d4a27de2509e7fceb2931e91faeb`。
- NVIDIA tag `610.57.04`，commit `e4a5faa2567f28c8eabe0ebb6422b6d0abcf37eb`。
- 本地 `/home/user/rt_5090_project/gspkm/version.mk` 与上述版本相同；生产 GFW generated source 与官方 commit 逐字节相同。
- 生产 key SHA256：`af870e5dde972840588bfb94a87f94b19ad6659dae6e1343dd0d22f16074ba39`。
- 原始 GSP 固件：`/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin`；当前未执行或改写其内核。
- 公开资料、准确 URL、证据范围见 [docs/SOURCES.md](docs/SOURCES.md)。尚未找到完整公开的 GB202 MPU/CSR/BootROM 编程手册，不把搜索摘要或第三方猜测当作规范。

## 文件

- `qemu/hw/riscv/nvidia_gsp*.{c,h}`：QEMU 入口与 C 包验证。
- `docs/LAB_BOOT.md`：签名 FMC、WPR meta、init args、walk 表检查点的完整证据与限制。
- `PROGRESS.md`：简洁恢复点和下一步。
- `tools/nvfw-verify.c`：同一验证实现的宿主诊断入口。
- `scripts/`：构建、提取、测试和 preflight。
- `tests/`：C 输入验证、纯 QEMU ISA 测试。
- `logs/`：真实构建和测试结果。
- `patches/`：相对固定 QEMU 版本的变更。

固件仅本地使用，未发布、未替换系统安装；第三方资料仅作检索线索，不作为已实现寄存器模型的规范。

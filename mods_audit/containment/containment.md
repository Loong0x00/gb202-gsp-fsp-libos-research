# MODS 570.151 动态审计与 GPU 只读隔离方案

日期：2026-07-14  
目标设备：`0000:01:00.0`，`10de:2b85`，RTX 5090 / GB202  
本阶段状态：**只做静态检查和本地编译；没有加载 `mods.ko`，没有卸载 NVIDIA 驱动，没有执行 MODS payload，没有访问 GPU MMIO。**

## 结论先行

1. **原版 MODS 不能在“绝无 PCI/MMIO 写、只读 therm 寄存器”的护栏下直接运行。** 包内官方诊断驱动会把任意请求的物理设备地址直接映射到用户态，并保留调用者要求的可写页权限；一旦映射建立，普通 CPU store 不再经过 syscall，`seccomp`、namespace 和 `strace` 都看不到、更无法阻止。
2. 包内 `driver.tgz` 本身没有被第三方篡改：其中 15 个文件与 NVIDIA 官方 `mods-kernel-driver` 的 `v4.29` 标签逐字节一致。这个结论只覆盖开源内核驱动，**不等于闭源 `mods` 用户态程序已被证明无恶意**。
3. 已准备一个不可在运行时关闭的拒写 patch。它只给 `0000:01:00.0` 暴露 BAR0 的 `BAR0+0x00ad0000` 一个 4 KiB PTHERM 页，页表永久只读/不可执行/UC；其余设备页不映射，所有写类 ioctl 默认返回 `EPERM`。它可以安全地回答“该 MODS 温度路径是否真能只靠读操作完成”：
   - 成功：该路径没有使用被禁止的 PCI/MMIO/DMA/ACPI/MSR/PIO 写操作，并且 GPU MMIO 读取局限于上述 PTHERM 页。
   - `EPERM` / `SIGSEGV` / `SIGBUS`：路径尝试了禁止 ioctl、写映射，或访问 PTHERM 页之外的寄存器；尝试在硬件生效前被拒绝。
4. patch 已在当前 `7.1.3-arch1-2` 内核头文件上编译成功，但**尚未加载和做运行时验证**。因此当前可交付的是“可编译的安全探针”，不是已经运行成功的 MODS hotspot 结果。

## 来源与同源性

| 对象 | 结果 | 状态 |
|---|---|---|
| `570.151_GB202_5090.zip` SHA-256 | `d141f685ea70c9a49095b7369201ab0651222bea3c063acfd6616dfde058ded9` | VERIFIED |
| 内层 `driver.tgz` SHA-256 | `fa8eeb376ef108c3198ed03feded213f0700b690905958d22ff2ce63fad1853b` | VERIFIED |
| 驱动 ABI 版本 | `4.29` | VERIFIED |
| 官方对应提交 | NVIDIA tag `v4.29`, commit `7fc0231c7ebb52340f773b19525aec6ecf3fb9bd` | VERIFIED |
| 包内 15 个驱动文件与官方 tag | 逐文件 `cmp` 全部相同 | VERIFIED |
| 包内预编译 `.ko` | 没有；只有完整 GPL 源码 | VERIFIED |
| 闭源 `mods`、脚本和各 `.bin` 完全无恶意 | 静态检查只能提供“未发现”，不能数学证明 | UNKNOWN |

官方来源：[NVIDIA/mods-kernel-driver v4.29](https://github.com/NVIDIA/mods-kernel-driver/tree/7fc0231c7ebb52340f773b19525aec6ecf3fb9bd)

未修改的包内驱动源码保存在 `mods_audit/containment/driver/`。不要把它和已经打 patch 的构建树 `audit/mods-kernel-driver-v4.29/` 混淆。

## 原版驱动的实际权限

| 能力 | 证据位置 | 影响 |
|---|---|---|
| 任意物理 PFN 的用户态映射 | `mods_krnl.c:1187-1230, 1335-1390` | `map_device_mem()` 没有 BAR/BDF/resource allowlist，直接调用 `io_remap_pfn_range()`；普通映射可继承 `PROT_WRITE` |
| PCI config 读写 | `mods_pci.c:370-575` | 可对指定 BDF 的 4 KiB config space 调用 `pci_read_config_*` / `pci_write_config_*` |
| x86 port I/O | `mods_pci.c:665-713` | 可执行 `inb/inw/inl` 和 `outb/outw/outl` |
| x86 MSR 读写 | `mods_krnl.c:1933-1960` | 可在指定 CPU 上执行 `rdmsr_safe_on_cpu` / `wrmsr_safe_on_cpu` |
| 任意 ACPI method | `mods_acpi.c:270-409` | 用户控制 method name 和参数，最终进入 `acpi_evaluate_object()`；ACPI method 可能改变电源/设备状态 |
| 内核代写 sysfs/sysctl | `mods_krnl.c:1787-1930` | ioctl 可让内核打开 `/sys/...` 或 `/proc/sys/...` 并写入 |
| DMA/IOMMU 映射 | `mods_mem.c:180-375, 2290-2360` | 可将分配页以 `DMA_BIDIRECTIONAL` 映射给 PCI 设备；另有 DMA mask 与 coherent DMA API |
| PCI enable/disable、IRQ | `mods_irq.c:44-133` 及 IRQ 注册路径 | `pci_enable_device()` / `pci_disable_device()`，注册/控制中断并可映射 IRQ aperture |
| PCI reset/remove/rescan/SR-IOV | `mods_pci.c:577-663, 1019-1077` 及 `mods_krnl.c` ioctl dispatch | 可 FLR、移除设备、扫描总线、改变 VF 数量 |
| 所有 escape 编号 | `mods.h:2004-2221` | 包括上述写能力、console、clock/reset、GPIO、Tegra/FFA 等 |

驱动源码没有找到显式 `request_firmware()`、`pci_map_rom()`、SPI flash 或 ROM write API，状态为 **VERIFIED-ABSENT**。但这不能推出“无法写固件/ROM”：可写 BAR 和 PCI config 足以让用户态通过 GPU 的间接寄存器、falcon/firmware loader 或板级控制器实现同类效果。因此固件风险在原版驱动下仍是 **NOT CONTAINED**。

包内 `install_module.sh` 也不应运行：它会在第 106-110 行卸载 `nvidia`，随后编译/安装模块、运行 `depmod`，并可能写 `/etc/udev` 和 `/lib/modules`。这些是正常诊断安装行为，不是恶意证据，但违反本项目的最小改动护栏。

## 为什么普通 sandbox 不够

| 控制 | 能防什么 | 对原版 `/dev/mods` 的缺口 |
|---|---|---|
| network namespace | 阻断联网和外传 | 不影响 GPU/PCI/MMIO |
| 只读 rootfs / mount namespace | 阻断普通文件修改 | 驱动可在内核态写 sysfs/sysctl；BAR store 与文件系统无关 |
| user namespace / drop capabilities | 阻断 `iopl`、模块加载、宿主 root 操作 | 原驱动 ioctl 没有对每项操作做 `capable(CAP_SYS_RAWIO)` 检查；能打开设备节点就成为 confused deputy |
| classic seccomp | 可按 syscall 号和 ioctl command 过滤 | 不能检查 ioctl 指向结构的全部语义；更无法观察 mmap 后的普通 load/store |
| seccomp user notification | 可让 supervisor 审核 ioctl | 参数有 TOCTOU；同样看不到已经映射页上的 CPU store |
| `strace` | 记录 syscall 与 ioctl 返回值 | 不记录 MMIO load/store |
| IOMMU | 限制设备 DMA 到宿主内存 | 不阻止 CPU 写 BAR、PCI reset、GPU firmware/ROM 控制，也不保护实体 GPU 本身 |
| VFIO/KVM | 隔离宿主文件与进程 | 若 BAR 直通，写操作仍落到真实 GPU；不能满足“实体 GPU 不写” |

所以安全边界必须放进内核驱动：**不创建可写 PTE，并在 ioctl dispatch 处默认拒绝。**

## 已准备的拒写 patch

文件：`mods_audit/containment/mods-v4.29-readonly-gb202.patch`  
SHA-256：`ddfdb7d9d7af500fbd583e7106e58f884f60bb037d690fdcbf36214f828ca822`

实现内容：

- 编译期固定 `MODS_READ_ONLY_POLICY=1`，没有 module parameter 或 sysfs 开关。
- 固定目标为 domain/bus/device/function `0000:01:00.0`、VID:DID `10de:2b85`。
- 不注册 MODS PCI driver，因此不会抢占或 bind GPU；现有 `nvidia` 驱动无需卸载。
- `/dev/mods` 初始模式固定为 `0600`；测试时只给专用非特权进程临时 ACL。
- BAR0 当前由 sysfs 只读元数据验证为：
  - start `0xd8000000`
  - size `0x04000000`（64 MiB）
  - 唯一可映射实体页 `0xd8ad0000`，即 `BAR0+0x00ad0000`
- 该页覆盖独立 reader 已识别的全部温度地址：edge `0x00ad0400`、bank `0x00ad0a90..0x00ad0ae4`、mirror `0x00ad0b50/0x00ad0b70`。
- 即使用户请求映射整个 BAR0，驱动也只填入上述一个 PTE；其余页保持空洞，访问会 fault。
- 拒绝初始 `VM_WRITE` / `VM_EXEC`，清除 `VM_MAYWRITE` / `VM_MAYEXEC` 防止后续 `mprotect()`，强制 MMIO 为 UC。
- 关闭 `vm_ops.access`，防止经 `/proc/self/mem`/ptrace 的 device-memory 旁路读取。
- ioctl 默认拒绝；只放行：API/version、access token、目标 GPU 枚举、BAR0 元数据、目标 GPU PCI config read、NUMA/IOMMU 查询、普通 host-memory 分配/释放/地址查询和 driver stats。
- 禁止 PCI config write、PIO、MSR、ACPI、sysfs/sysctl、DMA/IOMMU map、IRQ、reset、bus remove/rescan、clock/GPIO/console 等路径。
- host-memory 总量限制为 256 MiB；`MODS_ALLOC_MAP_DEV` 与 `MODS_ALLOC_DMA_PAGES` 明确拒绝。
- 携带 NVIDIA v4.35 中针对 Linux 7.0+ 的 `sysfb_primary_display` 兼容改动；ABI 版本仍保持 4.29。

编译验证：

```text
kernel: 7.1.3-arch1-2
module version: 4.29
vermagic: 7.1.3-arch1-2 SMP preempt mod_unload
build: success
patch --dry-run against pristine package source: success
```

当前本地构建物：`audit/mods-kernel-driver-v4.29/mods.ko`  
本次构建 SHA-256：`26c8476eeac2820c44a4416bede9a1ae90a419f7b1cf71244e442c62de9d63e7`

模块哈希可能随编译环境/BTF 变化；patch 哈希与 clean-source comparison 才是主要可复核对象。

## 仍然无法完全隔离的风险

1. 页保护粒度是 4 KiB，无法只暴露 15 个 32-bit word；同一个 PTHERM 页内的其他寄存器也可读。没有写权限，但理论上 MMIO read 也可能具有 read-clear 等副作用。当前没有证据表明该 PTHERM 页的温度读取有破坏性，风险为 **LOW / NOT ZERO**。
2. 该 patch 没有形式化验证。若闭源程序利用 Linux 内核漏洞、驱动内存安全漏洞或 CPU 漏洞，sandbox 仍可能被绕过；这属于普通“不可信本地二进制”剩余风险。
3. MODS 的准确寄存器 load 地址不能由 `strace` 得到。安全驱动只能证明访问没有离开 4 KiB PTHERM 页。精确到 word 的对照仍需脚本/二进制逆向，或更复杂的 fault-emulation monitor。
4. `-skip_rm_state_init` 只说明跳过某个 RM state 初始化，不等于所有 GPU 初始化都跳过。`gputest.jse -test 2` 很可能仍需要其他寄存器写。最终是否能在拒写驱动下工作是 **UNKNOWN，预计更可能失败**；失败本身是安全且有信息量的结果。
5. 若 Secure Boot / kernel lockdown 拒绝未签名本地模块，应立即停止；不得绕过签名或 lockdown。

## 最小安全运行顺序（下一阶段，尚未执行）

### A. 先做无设备行为审计

使用已经验证过的 rootless bubblewrap 结构：无网络、无 `/sys`、无 `/home`、无 NVIDIA 设备节点、payload 只读，只有 `/out` 可写。先运行 `--help` 或不会初始化 GPU 的解析路径，并在 sandbox 内用 `strace` 记录文件/进程/网络企图。

已验证 sandbox 骨架能满足：看不到 `/dev/nvidia0`、`/dev/mods`、`/home/user/.ssh` 和 `/sys`，payload 只读，输出目录可写。尚未用它执行未知 payload。

### B. 再加载拒写模块，保持 NVIDIA 驱动在线

只可直接 `insmod` 本地构建物；**不要**运行 `install_module.sh`、不要 `make install`、不要 `depmod`、不要卸载 `nvidia`。加载前后都核对：

```sh
lspci -nnk -s 01:00.0
```

GPU 应始终显示 `Kernel driver in use: nvidia`。拒写模块不会注册 PCI driver，只提供经过收窄的 `/dev/mods`。

测试进程必须是非特权用户，只临时获得 `/dev/mods` ACL；sandbox 内唯一额外设备节点为 `/dev/mods`。示意结构如下，实际 MODS 参数应由 thermal 逆向结果决定：

```sh
sudo insmod /home/user/rt_5090_project/audit/mods-kernel-driver-v4.29/mods.ko
sudo setfacl -m u:$(id -un):rw /dev/mods

timeout --signal=KILL 30s prlimit \
  --as=1073741824 --cpu=20 --fsize=67108864 --nproc=32 --nofile=128 -- \
  bwrap --unshare-all --die-with-parent --new-session --cap-drop ALL \
    --clearenv \
    --ro-bind /usr /usr \
    --symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib /lib64 \
    --proc /proc --dev /dev --dev-bind /dev/mods /dev/mods \
    --tmpfs /tmp \
    --ro-bind /home/user/rt_5090_project/mods_audit/static/extracted_inner /mods \
    --bind /home/user/rt_5090_project/mods_audit/containment/sandbox-out /out \
    --chdir /mods --setenv HOME /tmp --setenv PATH /usr/bin \
    /usr/bin/strace -ff -yy -s 256 -o /out/strace \
    /mods/mods '<仅温度读取的参数>'
```

判读：

- ioctl 返回 `EPERM`：记录 `_IOC_NR`；说明 MODS 需要被禁止的能力。
- `SIGSEGV`/`SIGBUS`：记录 fault address；PTHERM 页内 fault 通常表示写尝试，页外 fault 表示访问了非温度页。两者都不会形成 GPU MMIO 写。
- 成功输出温度：与独立 reader 同步采样，对照 edge、`max(bank0_max, bank1_max)` 和 MODS `GPU_OFFSET_MAX`。

### C. 清理与恢复

无论成功或失败都执行：

```sh
sudo setfacl -x u:$(id -un) /dev/mods 2>/dev/null || true
sudo rmmod mods
lspci -nnk -s 01:00.0
```

因为没有安装模块、没有写 udev、没有卸载 NVIDIA 驱动，恢复只需要移除临时 ACL 并 `rmmod mods`。测试产物只应存在于 `mods_audit/containment/sandbox-out/`。

## 最终护栏判定

- **原版 driver + 原版 MODS：不允许执行。** 无法强制无写，风险过线。
- **拒写 driver + rootless/no-network/minimal-filesystem sandbox：可作为下一阶段的安全失败探针。** 它能阻止 PCI/MMIO 写和绝大多数旁路，但运行前仍应结合用户态静态审计结论。
- **若要求字面意义上的“只读确切 15 个 therm word，其他同页 word 也不可读”**：直接 MODS mmap ABI 无法以 4 KiB 页表粒度实现；应继续使用现有 NVIDIA RM `READ_32` reader，或开发逐访问 fault-emulation，而不是运行 MODS。

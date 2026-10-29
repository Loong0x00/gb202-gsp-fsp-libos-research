# MODS 570.151 GB202/RTX 5090 静态安全审计

审计日期：2026-07-14

## 结论先行

**结论：NOT CLEARED / 未达到“确认没有恶意后即可在宿主机安全运行”的门槛。**

没有发现路径穿越、SUID/file-capability、典型矿工/勒索/持久化 IOC，内核驱动源码也与 NVIDIA 公开仓库 `v4.29` 完全一致。这些是重要的正面证据。但决定性的限制是：核心 `mods` 是一个 392 MB、stripped、无可验证发布签名的闭源 ELF；`gputest.jse` 和全部 thermal JSE 是接近满熵的不可读封装。它们能够调用 shell、网络、任意 PCI/MMIO/EEPROM/fuse 接口。静态审计无法证明这些不透明部分没有恶意逻辑，也无法通过容器阻止它们对已直通 GPU 做破坏性写入。

因此：

- **VERIFIED**：包形态和内容高度符合 NVIDIA 制造诊断包；没有看到常见通用恶意软件 IOC。
- **INFERRED**：它很可能是真实泄露的 NVIDIA MODS/“659”制造诊断包，而不是从零伪造的木马。
- **UNKNOWN**：核心 ELF/JSE 是否未经第三方篡改、是否含定向后门、运行给定温度命令时是否只做预期 GPU 初始化。
- **不建议**：因为本报告而把它标记为“安全”并直接在日常 Arch 宿主环境以 root 运行。

本次没有执行任何包内程序、没有加载模块、没有访问 `/dev/mem`、`/dev/mods` 或 GPU。只把文件作为数据进行解包、散列、格式解析、字符串/导入表和源码审阅。

## 样本链与散列

下载来源为公开 Yandex Disk 资源。Yandex API 返回 `antivirus_status: clean`，但这只是托管方扫描状态，不构成 NVIDIA 发布签名或完整安全证明。

| 层级 | 大小 | SHA-256 | 状态 |
|---|---:|---|---|
| `570.151_GB202_5090.zip` | 943,721,235 | `d141f685ea70c9a49095b7369201ab0651222bea3c063acfd6616dfde058ded9` | **VERIFIED** 与 Yandex API 元数据一致 |
| `659-1G145-0035-MFG-41923.tbz` | 943,748,743 | `5912dc09ad65c6a2f1376428bafc2bf6022aec6c1bade45c562f3478279742c5` | **VERIFIED** ZIP 唯一成员 |
| `570.151.tgz` | 434,926,703 | `3f579e910b87c69dfa1d955af4150b03c8098c71c1142b24fbba6c85d87fba60` | **VERIFIED** 内层 payload |
| `mods` | 392,339,552 | `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf` | **VERIFIED** 本地样本散列；发布者真实性 **UNKNOWN** |
| `driver.tgz` | 81,908 | `fa8eeb376ef108c3198ed03feded213f0700b690905958d22ff2ce63fad1853b` | **VERIFIED** 含源码、无预编译 `.ko` |
| `gputest.jse` | 110,897 | `a866edca7174433edcefbb0fb7862403aee0ed290c6eecdc6aacb5d253977a67` | 不透明 |
| `thermcal.jse` | 5,864 | `53a740a236145fbdedaf0dd47f7c52b1539a3f775cff80f46559828ddd8f4d1a` | 不透明 |
| `thermresgpu.jse` | 3,878 | `5b9e8937f505385ec7e03b361ae7dfdea10a026136baf57e7925353bfd6e195e` | 不透明 |
| `systhermsanity.jse` | 6,149 | `8fa0498c81385f67fce70569102e0af0c455d8fe157bbfef8cf871e6cdc86310` | 不透明 |
| `nautilus` wrapper | 4,831,852 | `11fd9440dca00cbb1109682d13e461f7eaf5d7d37963c4b2d8755e4136060732` | 不应用于热点测试 |

公开搜索没有找到 ZIP SHA-256、ZIP MD5 或 `mods` SHA-256 的独立声誉记录。即没有公开恶意命中，也没有独立可信白名单命中。

## 解包安全性

所有检查均在解包前先读 central directory/tar header：

- 外层 ZIP：1 个 regular file；无绝对路径、`..`、反斜杠路径、重复名、符号链接。
- `659-...tbz`：40 个 regular file、7 个目录；全部位于单一相对目录；无 link/device/FIFO、无穿越。
- `570.151.tgz`：134 项（132 regular、1 directory、1 symlink）；唯一链接为 `libstdc++.so.6 -> libstdc++.so.6.0.30`，目标仍在目录内；无重复名或大小写冲突。
- `driver.tgz`：15 个相对路径 regular file；无穿越或链接。
- Nautilus 自解包 payload：247 项（201 regular、46 directory）；无穿越或链接。
- `python3.tbz`：33,236 项；29,322 regular、2,444 directory、1,470 symlink。所有 link target 归一化后仍在解包根内；0 个绝对链接、0 个逃逸链接。
- 所有已解文件中未发现 SUID/SGID、file capability 或特殊设备节点。

这排除了常见的“解包即覆盖宿主文件”攻击，但不涉及运行时行为。

## 内核模块：强正面证据

`driver.tgz` 不含预编译模块，只有 `Makefile`、GPLv2 文件和 12 个左右的 MODS 驱动源文件。包内：

```text
MODS_DRIVER_VERSION_MAJOR 4
MODS_DRIVER_VERSION_MINOR 29
```

将整个目录与 NVIDIA 公开 `mods-kernel-driver` tag `v4.29` 做 `diff -qr`，**所有共同文件逐字节一致**；公开 checkout 只额外含 `.github/` 和 `.gitignore`。因此：

- `mods.ko` 源码没有看到供应链植入：**VERIFIED**。
- 该驱动本来就提供 PCI 设备、物理内存、IRQ、ACPI 等原始访问：这是设计能力，不等于低风险。
- `install_module.sh` 会卸载 `nvidia`、编译安装模块、写 `/lib/modules/<kernel>`、运行 `depmod` 并写 `/etc/udev` 规则。属于可解释行为，但确实会改变/持久化宿主状态。
- 它的卸载分支会删除所安装的 `mods.ko`、udev 文件和 `/dev/mods`；仍应在一次性启动环境中使用，不应在日常宿主“试一下”。

## 核心 ELF 与封装脚本

### `mods`

识别信息与包标称相符：

- ELF64 x86-64，字符串含 `570.151`、`Jan  7 2025`、`Copyright NVIDIA`。
- 标准 `.text`、`.rodata`、`.nv_fatbin`、relocation/dynamic sections；没有 UPX/MPRESS/VMProtect 标记，整体 entropy 约 `6.46081`，**未呈现整文件加壳形态**。
- 但它是 stripped ELF、没有 Build-ID、没有可验证的 NVIDIA 文件签名；`.gnu_debuglink` 指向未提供的 `mods.dbg`。
- 非 PIE、仅 partial RELRO；主程序栈 NX，但旧 `nvpex` 是 executable stack。现代 exploit hardening 水平偏弱。
- `RUNPATH=$ORIGIN`，会加载包内 `libstdc++.so.6`；未发现指向随机临时目录的 RPATH。

### JSE

内层共有 72 个 `.jse`，都以 `f1 1a 80 ..` 类似 magic 开头。代表性熵：

| 文件 | entropy (bits/byte) |
|---|---:|
| `gputest.jse` | 7.99848 |
| `thermcal.jse` | 7.96365 |
| `thermresgpu.jse` | 7.95120 |
| `systhermsanity.jse` | 7.97306 |

这与加密/压缩的 NVIDIA JSE 格式一致，但意味着无法审阅测试代码。`strings` 只有随机短片段，不能确认给定 test ID 的全部副作用。

### 包内 checksum 数据库的真实覆盖范围

外层 `.checksum.db` 是 SQLite，含 19 个配置文件的 checksum。按 Nautilus 所用规则（去 CR，再对 SHA-256 的四个 64-bit chunk 做 `B,D,C,A` 排列）复算，19/19 都匹配：**VERIFIED**。

但是数据库明确没有覆盖以下关键执行内容：

- `570.151.tgz`
- `mods`
- 所有 `.jse`
- `nautilus` 自解包程序和 Python bytecode
- 大型 `.bin` 测试资源

数据库自身也没有外部签名。因此它只能证明一小部分配置内部自洽，不能证明核心 payload 来源。

## 已验证的高权限能力

以下是静态导入表和可读字符串直接证实的能力，不应被描述成“只读温度工具”：

### 网络与进程执行

`mods` 导入/包含：

```text
socket connect bind listen accept send recv getaddrinfo
system popen execl execv execvp fork dlopen dlsym
```

它向 JS 暴露 `Popen(command)`、system command 和 `Socket.Connect/ListenOn`。硬编码/内置网络材料包括：

- `hqnvmodsauth01..04.nvidia.com`
- `rnnvmodsauth01..04.nvidia.com`
- NVIDIA OCSP/CRL 地址
- HTTP GET、TLS client 与内部 CA 验证逻辑
- remote UI、telnet UI、GDM/DRA、multinode/fabric-manager 协议

`-no_net` 的程序内描述是：

```text
Treat system as not being on the internal Nvidia network
```

它不等同于操作系统级“禁止全部网络”。因此即使采用该参数，也必须在外部用 network namespace/防火墙阻断；不能仅信任开关。

### 原始硬件写能力

`mods` 明确包含：

- 打开和 mmap `/dev/mem`、访问 `/dev/mods`
- `Pci.Write08/16/32`
- `RegWrite32`、BAR0 window write、EEPROM read/write
- 电压/时钟/P-state/风扇/GPU reset 控制
- fuse soft/hardware burn/write 路径
- VBIOS override/devinit 和固件/RM 管理能力

没有发现它通过 shell 调用 `nvflash` 或 `flashrom` 的直接字符串；但这不是“不具备固件写能力”的证明。内置 RM 和脚本接口已经足够执行广泛硬件写。

包内 plaintext `board_common.spc` 也直接含 `NV_OVR.Write`、`HBM_OVR.Write`、`gpu.RegWr32`、电压 offset 等函数。`fatool.egg` 含 InfoROM repair、`nvpex2` register write/reset 和 voltage shmoo 逻辑。它们通常不是热点命令路径，但证实整个工具集设计上并非只读。

### 持久化/宿主修改

- `mods` 本体字符串扫描没有发现 cron、systemd unit、`authorized_keys`、`ld.so.preload` 等典型隐蔽持久化 IOC。
- `install_module.sh` 的模块和 udev 安装是显式、可解释的持久化。
- MODS 能运行任意 shell，故“没有硬编码持久化路径”不能排除 JSE 在运行时这么做。

## Nautilus 外层：热点测试必须绕开

外层并不只是一个无害启动器。它是 Nautilus 4.18.0 自解包制造测试框架，payload 包含：

- Python bytecode、API server、socket database
- SSH/SCP 上传和远程脚本执行（含 `StrictHostKeyChecking=no`）
- IPMI 远程 power on/off
- CIFS upgrade 脚本（`//172.20.69.105/nautilus`）
- nvflash 查找/读 SN 和 ECID 的流程
- 清理脚本中的 scoped `rm -rf`
- 一个示例 wrapper 甚至硬编码 `echo 'labuser' | sudo -S`（看起来是测试样例，但属于不应运行的危险内容）

外层项目 `run.sh` 在 `NAUTILUS_FACTORY=FXSJ` 时还会挂载 `//192.168.2.11/START`。默认是 `FXLH`，但没有任何理由为读取热点执行这个 wrapper。

`operator.txt` 把它描述为 `659-1G145-0035-MFG-41923`、TinyLinux、PG145 SKU35 的 FCT/ENG/GN5/IDT/OQA 制造流程，并要求额外的 Blackwell trace folders。这是“真实内部制造包”推断的强上下文证据，但不是密码学来源证明。

## 常见恶意 IOC 扫描

对主 ELF、MATS/NVPEX、Nautilus wrapper、所有 plaintext shell/Python/SPC 做了定向扫描：

- 未发现 XMRig/stratum/Monero、勒索提示、Discord/Telegram webhook、Pastebin/ngrok、`authorized_keys`、`ld.so.preload`、cron/systemd 隐蔽安装等典型 IOC。
- 域名主要是 NVIDIA 内部服务、标准库/协议字符串；另有库内测试/网络常量。它们无法证明运行时不会连接外部地址。
- 公开搜索没有该样本散列的恶意或良性声誉结果。

“没有命中”只是一项弱负面证据；对 stripped 392 MB ELF 和加密 JSE 不能转化为“没有恶意”。

## 对热点测试的安全判定

从恶意软件审计角度，能给出的最严格结论是：

1. **内核驱动源码可审且与 NVIDIA 公版一致。**
2. **核心用户态程序/JSE 无法建立可验证供应链，也无法完整审计。**
3. **常规 OS 级网络/文件副作用可以在一次性离线系统里大幅约束。**
4. **GPU/MMIO/EEPROM/fuse 写无法在仍允许 MODS 控制 GPU 的同时被可靠沙箱化。**

所以，若上层任务的硬条件真的是“审计完成且确认没有恶意才运行”，应当停止：该条件无法被满足。若用户明确接受残余风险，最低限度应是：一次性离线启动环境、无持久盘/只读挂载、外部网络物理断开、只编译经 diff 的 v4.29 驱动、绝不运行 Nautilus、命令强制 `-no_net`、审计所有系统调用/文件修改，并在测试后断电重启和删除临时系统。即便如此，对 GPU 本体的破坏性写风险仍为 **UNKNOWN**。

## 状态汇总

| 命题 | 结论 |
|---|---|
| 下载文件与公开 Yandex 元数据相同 | **VERIFIED** |
| archive extraction 不会路径穿越 | **VERIFIED** |
| driver 源码等同 NVIDIA 公共 v4.29 | **VERIFIED** |
| 包内容结构像真实 NVIDIA 5090 制造诊断包 | **INFERRED（强）** |
| 未发现常见通用恶意软件 IOC | **VERIFIED（仅限所做静态扫描）** |
| 核心 ELF/JSE 没有恶意 | **UNKNOWN** |
| `-no_net` 能完全禁止联网 | **否；需外部阻断** |
| 热点命令只读、不写 GPU 控制状态 | **UNKNOWN，且与 MODS 初始化设计不符** |
| 可据本审计安全地在日常宿主 root 运行 | **否** |


# GB202 显存初始化上游：只读校准、真实代码执行与 id89 数据链

## 本轮回答了什么

**已证明：原版5090 VBIOS内被提取的EFI容量读取/消费代码，能够处理合成的48/96GiB容量，没有在这些片段内限制为32GiB。尚未证明：原BIOS能从更大密度或clamshell颗粒初始化出这些容量。也没有证据足以断言必须改BIOS。**

本轮不止比较表格：完成标准EFI解压和原始x86-64指令执行；又运行了当前驱动自带的设备端GSP RISC-V指令。两者都用只读实卡快照作了校准。不过，运行到的仍是**已有容量的消费者**，不是从DRAM Info Read/拓扑输入生成几何设置的初始化程序。

更上游的新结果是：几何候选数组已经定位到 **BIT小写i → id89明文数据块 → application 0x19（十进制25）的source record**。还确认该数据块受两层可复算SHA-384关系覆盖。“它是明文”不等于“它是未经完整性检查的任意数据”。

## 1. 本轮允许并实际做过的硬件读取

用户随后明确授权只读必要硬件信息。本轮未改时钟、功耗、strap，没有reset、解绑、驱动替换或刷写；未运行NVFlash/MODS原生程序。

- GPU：RTX5090，`0000:01:00.0`，PCI `10de:2b85`，驱动`610.57.04`。
- 运行VBIOS版本报告：`98.02.2E.40.E0`。
- 最初`O_RDONLY/PROT_READ`映射BAR0在首个地址失败，`EINVAL`，未取得寄存器值。
- 改用公开RM `GPU_EXEC_REG_OPS`，固定4个`READ_32/GLOBAL`，全部RM/op状态为0。独立审查后增加了**实际RM对象**的PCI位置/ID查询及proc minor绑定，再读一次；四值完全一致。
- FB信息通过固定6项`FB_GET_INFO`获取，不是寄存器扫描。

| 地址/信息 | 值 | 本轮可确认的意义 |
|---|---:|---|
| `0x1183a4` | `0x00007f5f` | GSP原始代码将其作为u32 MiB数读取 |
| `0x1fa3e0` | `0x0007f5f0` | EFI原始代码解出32607MiB |
| `0x9a0200` | `0x3e8f0883` | CFG0候选；不等于ROM候选数组config0原值 |
| `0x9a0204` | `0x1e66b000` | CFG1候选；与标准样本候选数组相同 |
| RM RAM_CFG | `0` | 驱动报告配置号，不把它冒充原始strap寄存器读取 |
| RM RAM_TYPE / vendor | `0x15 / 1` | 公开API枚举为GDDR7 / Samsung |
| RM RAM_SIZE、TOTAL_RAM_SIZE | `33389568 KiB` | 即32607MiB，与NVML一致 |
| RM USABLE_RAM_SIZE | `33083200 KiB` | 另一个API指标，不能与上两项混用 |

`nvidia-smi`读取前后总显存均为32607MiB。它不是32GiB标称物理容量的完整原始几何信息。

证据：`reports/live_readonly/*_verified.txt`、`nvidia_smi_verified.csv`、`proc_gpu_information.txt`。只读工具在`tools/read_memory_regops.c`、`tools/read_fb_info.c`。设备节点以O_RDWR打开以使用ioctl；程序有临时RM对象分配/释放等软件状态变化，**不宣称驱动内部零副作用**。提交的硬件操作只有明确列出的读取/信息查询。

## 2. 原VBIOS EFI：真实代码而非手写容量模型

### 提取与入口依据

5090完整E1 ROM和PRO WS ROM的标准EFI压缩均严格解压成功，得到有效AMD64 PE32+；节区/入口/长度通过验证。Tiano算法失败，不能混称为任意压缩猜测。

| 片段 | 5090解压PE RVA | PRO解压PE RVA | 长度 |
|---|---:|---:|---:|
| 容量读取 | `0x20288` | `0x20244` | 62字节 |
| 下游容量消费者 | `0x1fe30` | `0x1fdec` | 214字节 |
| 分区求和helper | `0x201ac` | `0x20168` | 218字节 |

三类片段分别跨两份EFI逐字节相同。函数入口有vtable指针、DIR64 relocation、构造器安装与递归CFG证据，并非随机反汇编。未建立完整PE entry到这些函数的运行时调用链。

当前运行版本报告为E0，而完整参考ROM是E1。额外解压了**既有缓存的E0 host-visible ROM**：上述三个EFI片段、legacy容量片段及MEM TYPE字节与E1相同。**整份EFI Option-ROM并非相同；缓存E0也不包含后面的id89/设备载荷区。没有把缓存说成新读取的完整实卡ROM。**

### 执行及校准

Unicorn执行原始机器码，I/O抽象由合成字典响应；消费者的写调用仅记入仿真日志，未发给GPU。

| 输入 | EFI原码结果 | 输入性质 |
|---|---:|---|
| 实测`1fa3e0=0x7f5f0` | 32607MiB | 当前驱动加载后的快照，与NVML一致 |
| `1fa3e0=0x80000` | 32GiB | 合成最终容量 |
| `1fa3e0=0xc0000` | 48GiB | 合成最终容量 |
| `1fa3e0=0x180000` | 96GiB | 合成最终容量 |

消费者还调用写抽象，地址实参为`0x10fd40 / 0x830000 / 0x830004`；其48/96GiB分支已实际仿真，不只是改GOP显示数字。但是它**不写0x1fa3e0，也未连到9a0200/204**；这些下游操作不是已证明的颗粒密度/行列/训练初始化。

验证：EFI三类片段共**312个正常案例**；另外6个负控拒绝缺失读响应、未知写地址、直接跳sentinel而未经RET。独立校准再运行12个EFI案例：两份各自用真实快照及32/48/64/96/128GiB合成值。

详见`efi_research/README.md`、`reports/live_calibration.json`。

### legacy旧结论的进一步修正

用当前实测`0x7f5f0`重放legacy容量函数，AX得到3935，而不是32607。这反映其混合AX/EAX处理对当前MAG/SCALE编码的局限；**不是实卡只有3935MiB，也不是SKU限制**。

此前以MAG=96、SCALE=10表达96GiB，legacy AX回绕为32768，则是16位结果截断。两种现象都说明：不能把旧报告函数的编码/位宽局限或驱动加载后的输入，当成冷启动显存初始化能力的判决。

## 3. 设备端GSP RISC-V片段也实际执行了

当前`gsp_ga10x.bin`内有可验证明文RISC-V代码，原先“整个设备固件均无法执行”的泛化不能成立。但它是**驱动提供的GSP固件**，不是ROM里的app0x19。

提取`[0x01358484,0x013584ae)`的42字节：

```c
base = *(u64 *)(gpu_object + 0xb98);
*out = (u64)*(u32 *)(base + 0x1183a4) << 20;
return 0;
```

当前GSP中有对应函数指针安装点；相邻小版本公开HAL源将同语义函数分配给GB202。不过当前二进制的完整GB202 selector尚未闭合，不冒充已经证明本机每次必走该分支。

- 用Unicorn RV64执行，**138个正常案例通过**，含真实`0x7f5f`、48/96GiB值、u32最高位与随机输入。
- 一个缺失寄存器负控停止，未产生有效输出。
- 只初始化明确对象字段、一个只读合成MMIO字及栈；逐次记录数据读写，未知数据读取拒绝。原码仅保存栈和写输出，不写MMIO。
- 不输入DRAM density/topology，所以这仍不是显存初始化仿真。

另外追到一个`1fa3e0/1180f0`比较函数，但公开源将其绑定GB100类HDM逻辑，**不能挪作GB202初始化证据**。现成RX提取比完整PT_LOAD少16KiB，本轮补查尾部，未找到目标writer。

详见`gsp_upstream/RESULT.md`、`reports/gsp_capacity_execution.json`。

## 4. 几何候选数组的真正owner与装载引用

29/29样本均满足：

```text
BIT 小写 i + 0x6e/u32
  → 10 08 89 00 <payload_length> 明文blob
  → application 0x19 的v6 source record
       id=0x89，source、size、allocation size精确一致
```

Astral E1：
- id89范围`[0x9cf75,0xa74b9)`，长`0xa544`。
- CFG0/CFG1候选数组起点`0xa31d5 / 0xa320d`。
- app0x19 source record：`00890001 0004cf75 00008a00 0000a544 0000a544`。

这说明它们是设备载荷引用的外置明文数据，不是在密文内偶然搜到的u32。

| 样本组 | CFG1候选前13配置 | 后两个候选块 |
|---|---|---|
| 26个5090/5090D | 全部`1e66b000` | 全0 |
| 3个PRO | 0/7=`1e77b000`，4=`1e88b000`，其余`1e66b000` | 仅config4=`c000` |

HPE 9E实际为**16项块**，不是13项；三PRO前13项仍相同。强套13会把c000索引判错。

限制：
- **owner/source闭合，字段到寄存器writer未闭合。** CFG0/CFG1仍为候选命名。
- 实卡CFG0=`3e8f0883`，而E1候选config0=`1e878083`，异或`20088800`；不能宣称数组未经调整原样写入。
- 这些标准样本的候选数组没有另一组PRO式值；但静态数组一致不能证明设备代码绝无动态覆盖路径。
- `c000=3/4*65536`只与非2次幂范围限制假说相容，尚无单位/字段/writer证据；不据此证明24Gb或128GB。

详见`geometry_research/REPORT.zh-CN.md`。

## 5. id89还有独立的两层完整性关系

29/29核查通过：

```text
完整 id89（含8字节头）
  → SHA-384，精确等于60字节表项中存储的digest
     同表项tag=0x89，relative offset与size也精确指向id89
  → 完整hash table的SHA-384
     精确等于对应nested image +0x209的parent digest
```

| 样本 | id89 digest位置 | hash table范围 | parent digest位置 |
|---|---:|---:|---:|
| Astral E1 | `0x614ba` | `[0x5fe5a,0x6177e)` | `0x5fc09` |
| PRO WS | `0x5ec42` | `[0x5d65a,0x5ef06)` | `0x5d409` |

每样本做两个**内存中的哈希负控**：翻转候选数组一字节，leaf不匹配；只更新leaf digest后，parent不匹配。58个检查通过，无修改版ROM写盘。

这是精确的无密钥摘要关系，**不是已完成公钥验签，也不是证明硬件必定强制该检查**。没有证明签名信任根或可刷写性。

证据：`reports/id89_integrity.json`；复现：`tools/verify_id89_integrity.py`。

## 6. 为什么尚不能执行真正初始化

v6结构化前缀已恢复出有效边界：

```text
N = u16(D+0x1a); stride = u16(D+0x1c)
body_start = D+0x50+N*stride
body_end = body_start+stored_size
```

此前直接用`D+0x50`会把source records混入body，并截掉尾部。四样本app0x15/0x19的新body终点8/8精确落到下一descriptor；58/58非零源记录匹配独立BIT指针。

校正边界后的604项有界标准解压尝试未得到有效流；**app0x19 body仍没有经验证的明文ISA/入口/加载映射**。这不证明绝无私有解码方法，也不表示整个ROM均被加密。

真正还缺的是：
1. app0x19如何消费id89中这些字段；
2. 如何结合物理strap、DRAM Info Read和clamshell/拓扑输入；
3. 哪些路径写geometry、完成training并发布最终容量。

在这条链尚未恢复时，把`1fa3e0`或`1183a4`预置成96GiB只能验证消费者。**不能称作“原BIOS面对96GB颗粒完成了初始化”。**

## 7. 复现与审查

环境：本目录`.venv`，CPython3.12.12、Unicorn2.1.4、Capstone5.0.7、pefile、uefi-firmware等。

**以下命令完全离线，不运行任何硬件读取工具：**

```sh
R=/home/user/rt_5090_project/vbios_diff/gb202_boot_upstream_20260911
"$R/.venv/bin/python" "$R/tools/verify_all_offline.py"
```

本轮实际重跑：**14个离线阶段全部通过**，C只做`-Werror -fsyntax-only`检查，5份核心源文件前后SHA256不变；29-ROM脚本另外逐份核对既有corpus哈希。

- `reports/offline_verification.json` / `verification_summary.txt`：最终回归。
- `reports/verification/`：逐阶段日志。
- `reports/independent_review.md`：审查发现与修正。
- `efi_research/`、`legacy_upstream/`、`payload_research/`、`geometry_research/`、`gsp_upstream/`：分支证据。

独立审查指出的两处边界已处理：硬件读取对象绑定与CSV按BDF选择；EFI写地址白名单/顶层RET及栈检查，并补充负控。没有把模型输出或静态引用关系冒充设备初始化成功。

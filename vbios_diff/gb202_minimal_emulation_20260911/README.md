# RTX5090显存相关代码：最小离线执行实验

日期：2026-09-11。

## 实际做成了什么

**不是只写计划，也不是把手写解码器称为固件仿真：本轮确实执行了两类原始机器码。**

1. **来自原版5090/PRO VBIOS的16位x86容量读取函数**：67字节，连同原始23字节寄存器read helper一起在Unicorn中运行。提供合成的硬件寄存器响应，记录全部IN/OUT与执行PC。
2. **来自MODS/RM的x86-64显存表解析/选择函数**：原始函数机器码从固定ELF提取，使用真实ROM表，只有依赖接口被模拟。完成71次运行及额外正负控制。

两者都**不是完整的GB202设备端冷启动仿真**。第一类读取已计算好的容量，第二类读取/选择ROM配置；都没有执行“发现更大颗粒→训练→编程实际显存几何”的全过程。

## 安全边界

- 没有运行MODS本体、NVFlash、updater或原ROM的宿主进程；机器码仅由Unicorn在私有模拟内存中解释执行。
- 没有GPU设备节点、MMIO、PCI资源、真实I/O端口、驱动操作、reset或刷写。
- 真实IN/OUT指令由Unicorn hooks截获，绝不转发给宿主硬件。
- 未知执行目标、未映射的非ELF数据访问、未建模端口/寄存器响应会停止。已分配的合成上下文对象整体以零初始化，这是模型假设；不是逐字段检测所有未知读取。
- 原始ROM和MODS源文件只读。只有独立本目录新增环境、脚本、提取片段和报告。
- `.venv`使用CPython3.12.12，Unicorn2.1.4、Capstone5.0.7；未改全局Python环境。

## A. 真实VBIOS机器码实验

### A1. 提取目标

| 部分 | 5090原ROM绝对offset | PRO原ROM绝对offset | 大小 |
|---|---:|---:|---:|
| 容量读取换算函数 | **0x3fe86** | **0x3d646** | 67 bytes |
| indexed-I/O read helper | 0x3c416 | 0x39c16 | 23 bytes |

原版5090输入：`/home/user/rt_5090_project/flash_logs/astral-original-20260726_020901.rom`。
PRO输入：`/home/user/Downloads/NVIDIA.RTXPRO6000Blackwell.98304.250324.rom`。

两函数的关键行为：

```text
mov esi, 0x1fa3e0
call 原始read helper
从返回EAX取MAG / SCALE，用16位AX换算
可选bit30乘15/16分支
ret，返回AX
```

helper执行`OUT base+8, EAX`选择寄存器地址，然后`IN EAX, base+12`读取值。**OUT只是选择读事务地址，不是写显存配置。** caller随后把AX缓存到CS:307a，另有getter读取这个16位缓存。

公开Blackwell GB100头`dev_fb.h`将0x1fa3e0命名为`NV_PFB_PRI_MMU_LOCAL_MEMORY_RANGE`，MAG=27:4、SCALE=3:0；与本5090代码吻合。公开GP102驱动同类算法使用`MAG << (SCALE+20)`生成byte size，并说明这是Devinit计算后的范围值。不能因GB100头存在就声称全部GB202私有位均已知。

### A2. 模拟环境

- 原始legacy镜像按CS相对位置装入虚拟内存；目标函数和read helper机器码不改。
- CS=0、单独SS栈，避免真实BIOS影子内存/设备访问；所有代码保留原相对地址。
- CS:d7a仅设置模拟的已初始化I/O基址0x1000，这是runtime环境字段，不是容量逻辑补丁。
- 只允许目标67字节、helper23字节及返回sentinel执行；其它执行地址停止。
- 两个端口hooks只接受地址选择0x1fa3e0的32位读，返回指定寄存器编码。
- 除模拟栈外没有guest memory写入；未调用显存训练或CFG写路径。

### A3. 真正执行结果

输入采用合成编码`MAG=GiB, SCALE=10`，即`(GiB<<4)|10`，对应未截断MiB。它们不是从真实大显存卡采集到的寄存器值。

bit30=0时：

| 合成输入名义容量 | 5090返回AX | PRO返回AX | 解释 |
|---:|---:|---:|---|
| 24GiB | 24576 | 24576 | 数值正常换算 |
| 32GiB | 32768 | 32768 | 基线 |
| **48GiB** | **49152** | **49152** | 该片段没有在32GiB处拒绝/钳制 |
| 64GiB | 0 | 0 | 16位回绕 |
| **96GiB** | **32768** | **32768** | 98304 mod 65536 |
| 128GiB | 0 | 0 | 16位回绕 |

bit30=1的12组额外运行也完成，走原始乘15/16式调整分支。每条bit30=0路径执行26条真实指令，bit30=1执行32条（包含read helper）。源寄存器EDX正确恢复。

独立审核发现并修正了手写预期模型的混合位宽细节：`mul dx`保留EAX高16位，随后`or edx,eax`会混入这些高位。原24个场景高位为零，结果不受影响；例如额外输入`0x40010000`真实AX=4096，简化模型曾错误预测0。修正后新增256次算术压力运行（不是有效硬件配置宣称），含该回归用例，均与实际原机器码一致。

**关键限制：96GiB返回32768不是“5090只能用32GB”的证据。PRO对应函数具有同样行为，这只是一个16位legacy容量消费/缓存接口。也不能由48GiB数值通过就认定原固件能够初始化48GB颗粒。**

脚本：`tools/emulate_vbios_capacity.py`。
完整24组执行、全部PC、端口记录及故意缺失寄存器响应的fail-closed测试：`reports/vbios_capacity_execution.json`。

## B. 真实MODS/RM机器码实验

### B1. 执行范围与模拟依赖

ELF：`/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods`。
SHA256：`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`。
执行原函数VA范围：`[0x672c9e0,0x672d36b)`。

真实指令执行这些逻辑：
- 表头/record size分支与枚举jump table；
- 22-byte记录位字段解码；
- Skip过滤和有效记录列表构建；
- method0/method4选择、结果复制与错误返回。

明确模拟的接口：
- `_STRAP_MEMSEL`返回指定输入；
- method4的MEMINFO_INDEX HAL输入（仅额外反事实测试）；
- generic ROM byte/format读取（5b、1d1b1w5b1w2d的格式解包）；
- 私有内存分配、日志；
- 上下文假设partition metadata已初始化且有1个logical partition。

**没有重写记录解码和选择算法来决定结果。** 这些逻辑由原机器码运行；但它属于MODS/RM，不是假称取自GPU设备端FSP。

### B2. 结果

| ROM表 | 输入 | 原代码返回 | 选中结果 |
|---|---|---|---|
| 5090原版 | MEMSEL0 | 0 | record0，density6/org3 |
| 5090原版 | MEMSEL4 | **0x4a** | 无匹配 |
| PRO原版 | MEMSEL0 | 0 | record0，density6/org2 |
| PRO原版 | MEMSEL4 | 0 | record4，density7/org2 |

分别遍历0～31，共64组；5090有效输入0/1/2/3/7/8，PRO另含4，其余均0x4a。完整主测试共71组，每组约2298～2614条原始指令，全部正常到返回点。

正控制：只在模拟器私有ROM副本中将record0的density/org改为7/2，原代码确实返回7/2，证明输出不是硬编码。**源ROM没有改变，这也不是可刷写补丁或验签测试。**

反事实method4：私有副本改变selection method，index0成功；index4返回0x5b。实际源ROM仍method0。

### B3. “告诉它有48/96GB”的探针实际发生了什么

另外在模拟地址0x1183a4放入32、48、96GiB对应的MiB数值，观察这个拷贝函数是否读取它。结果：**读取次数全部为0，PC轨迹、hooks及输出逐项相同。**

这只是明确的接口探针。它证明**此拷贝函数不消费该容量寄存器**，不能表达用户想要的“早期DRAM密度/组织输入”；绝不解释为整个BIOS忽略大容量。与A实验读取0x1fa3e0是两个不同函数/接口，不混用。

## C. 对原5090设备端初始化载荷的实查

详细报告：`firmware_probe/REPORT.zh-CN.md`。

不是仅看到encrypted flag就停止：
- 实查了六个v6描述符后的有边界候选区域；多个区域前部存在规律的20-byte结构化记录，**不能把整个VBIOS说成全是密文**。
- ELF/MZ/PE、常见压缩头及有界zlib解压验证，没有取得可确认的设备端可执行镜像/入口。MZ短串均未通过PE链验证。
- 私有记录的offset/长度语义、ISA及装载布局尚未验证；没有将随机解码出来的指令冒充固件执行。
- 标准EFI option ROM另含compression_type=1的压缩通道：5090 0x47f50、PRO 0x45750。目前未成功解压验证PE。即使解开，也须再确认其中哪些只是GOP/报告容量，哪些真正参与初始化。

所以当前没有运行“同一份5090设备端初始化固件，分别面对16×2GB、16×3GB和32×3GB颗粒”的完整实验。阻碍已具体缩小为**取得并正确装载做初始化决策的代码**，而非笼统说不能仿真。

## D. 复现

```sh
uv venv .venv
uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python tools/emulate_meminfo.py
.venv/bin/python tools/verify_emulation.py
.venv/bin/python tools/emulate_vbios_capacity.py
```

程序均不访问GPU；输入路径固定在现有研究文件，执行前/后校验源哈希。

关键产物：
- `tools/`：两个Unicorn执行器和验证脚本。
- `reports/emulation_results.json`：71组MODS真实机器码运行。
- `reports/negative_and_alternate_controls.json`：未知依赖fail-closed、method4控制。
- `reports/vbios_capacity_execution.json`：24组**真实VBIOS**函数运行。
- `reports/verification.json`：MODS执行器断言汇总。`verify_emulation.py`核查已保存的71组结果，并另执行3个控制；它本身不是重新跑全部71组，完整重跑由`emulate_meminfo.py`完成。
- `firmware_probe/`：原ROM切片、反汇编、容器尝试及来源证据。
- `derived/meminfo_original_x86.bin`：原ELF函数字节提取，不可刷写。

## 下一步有效方向

沿**写入**0x1fa3e0/显存几何寄存器的路径，或从已识别私有载荷结构恢复初始化代码，而不是继续只调用容量getter。现有两个执行器可以作为可复用的最小框架，但不会自动提供GB202解密密钥、Boot ROM或训练器模型。

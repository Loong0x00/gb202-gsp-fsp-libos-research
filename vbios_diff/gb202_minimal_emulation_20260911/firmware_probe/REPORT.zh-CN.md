# 原版5090 ROM最简离线可执行片段检查

## 结论（不是笼统 encrypted）

**有可提取的显存相关明文 x86 子程序：读取并换算既有容量寄存器，而不是显存颗粒/几何初始化。** 已提取原版5090的67字节函数和23字节寄存器读取helper。Falcon载荷未找到有格式依据的可执行入口；但多个载荷开头明显是结构化明文记录，不能说它们全部都是随机密文。另有标准压缩EFI option-ROM，值得作为独立的后续解压目标。

全程只读取文件、运行静态解析工具/手写算术模型，没有执行原ROM机器码、没有GPU/设备访问。所有输出在本目录。不涉及MODS选择器。

## 1. 基址及检查方法

复用指定 `gb202_memory_route_20260911/tools/memory_corpus.py::load`，不是旧g.load。5090 legacy base **0x38000**；PRO **0x35800**。两者legacy长度均为0xfa00。后续偏移除CS相对值外均是原ROM文件偏移。

`probe.py`：遍历六个非空Falcon描述符；只把 descriptor+size 起的word1字节称为 immediate region（不声称完整v6字段语义）。检查整个region的ELF、MZ/PE、gzip、xz、bzip2、zstd、lz4、ZIP签名；MZ另验证e_lfanew所指PE签名；遍历满足RFC1950条件的zlib头，要求限4MiB解压且流到EOF。保存前64字节及首256字节/整体entropy。不把反汇编成功作为代码证据。

## 2. 找到了真正可读的legacy容量函数

| 对象 | 5090 CS相对 / 文件偏移 | PRO CS相对 / 文件偏移 |
|---|---|---|
| 容量读取换算函数，67字节 | 0x7e86 / **0x3fe86** | 0x7e46 / **0x3d646** |
| 地址立即数字节 e0 a3 1f 00 | 0x7e8a / **0x3fe8a** | 0x7e4a / **0x3d64a** |
| 寄存器read helper，23字节 | 0x4416 / **0x3c416** | 0x4416 / **0x39c16** |
| caller保存AX到CS:307a | 0x7f30 / **0x3ff30** | 0x7ef0 / **0x3d6f0** |
| 缓存getter，5字节 | 0x39e7 / **0x3b9e7** | 0x39e7 / **0x391e7** |

证据不是孤立立即数：`mov esi,0x1fa3e0; call read_helper`，接着提取低4位scale、mask `0x0ffffff0`，做AX的右移4/左移CL；bit30置位时执行乘15再除16式调整；caller将AX缓存到CS:307a，getter再读取缓存。函数有正常保存/恢复、分支和RET，完整指令见`5090_capacity.txt`、`5090_read_register.txt`、`5090_caller.txt`。

helper将ESI写入 I/O base+8（地址选择），从base+12读EAX：`out dx,eax`在这里是**读事务的地址选择**，不是向容量寄存器写入值。相邻还有通用write helper（CS:43fa附近），但这不证明调用者在写显存几何。

本地公开头的独立语义依据：
`/home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/common/inc/swref/published/blackwell/gb100/dev_fb.h:27-32`
定义 `NV_PFB_PRI_MMU_LOCAL_MEMORY_RANGE=0x001FA3E0`，LOWER_SCALE=3:0、LOWER_MAG=27:4，与机器码吻合。其是gb100公开头，并非声称掌握私有gb202定义；原5090自身确实使用该地址。公开GP102实现`src/nvidia/src/kernel/gpu/mem_sys/arch/pascal/kern_mem_sys_gp102.c`注释说明此类寄存器是Devinit计算后的usable FB范围，并含ECC 15/16调整。因此这里是容量消费/缓存路径，不是证明颗粒密度检测、channel/rank/row/column编程。

两ROM全文件均**没有**little-endian u32 `0x1183a4`；也没有`0x10020c`。这不能排除动态拼地址。另在5090 CS:7e4d（文件0x3fe4d）/PRO CS:7e0d（0x3d60d）有 `mov esi,0x90020c`，循环按0x4000加地址，通过同一read helper累加EAX到EBX，caller缓存AX到CS:3078。它有内嵌脚本解释器调用，未把这些内嵌字节误当x86；未在时限内独立解出其分区mask/数量来源，不能命名为初始化几何。

### 能做的最小函数实验

直接使用提取的capacity函数，映射完整legacy至一个16位CS，给栈放sentinel返回地址，把CS:4416替换为host侧read回调：断言ESI==0x1fa3e0，返回合成EAX，然后继续原函数至RET。无需BAR、PCI、GPU、训练器或整卡仿真。该机器码仿真实验**本任务未执行**（遵守不执行原二进制边界），但切片及接口已经明确。

已实际执行的是 `extract_capacity.py` 的手写指令算术模型断言：合成reg=0x2006 -> AX=32768；0x3006 ->49152；bit30的0x40002006 ->30720；0x2007 ->0；0x3007 ->32768。注意最后两项揭示**AX只有16位**：不能将这个legacy API当96GiB全宽容量真值，更不能把改变它当作32->96GB的几何初始化成功。输入只是合成编码，非实卡回读。

## 3. Falcon实际命中/不命中

| index | 5090 immediate region start / word1 | PRO start / word1 | 观察 |
|---|---|---|---|
| 5 | 0xa7df0 / 0x20200 | 0xa6088 / 0x20600 | 开头未见已识别容器/stub |
| 22 | 0x10e154 / 0xcc00 | 0x114554 / 0xc500 | 明文结构，开头01 00 44 00；连续4组20字节规律记录 |
| 23 | 0xc8040 / 0x21b00 | 0xc66d8 / 0x21200 | 明文结构，开头01 00 35 00，多个20字节规律记录 |
| 24 | 0xe9c80 / 0x5b00 | 0xe7a18 / 0x5500 | 开头01 00 35 00，前60字节为3组规律记录 |
| 32 | 0xef80c / 0x1e200 | 0xecfa4 / 0x27000 | 5090开头01 00 1d 00，前60字节为3组规律记录；PRO开头不呈同样结构 |
| 34 | 0x11b354 / 0x29400 | 0x121154 / 0x2a800 | FSP_RUN标签在descriptor，不是payload入口；开头未识别 |

例：5090 index24前3组 little-endian u32：
```
00350001 000047a7 000057c0 000004bd 00001100
008a0001 000574b9 00004000 00000790 00000790
00d20001 0001936d 000068c0 00000c0f 00000c13
```
其中某些数值看似offset/压缩前后长度，但没有把这种相似性赋予正式语义，也没有拿它们盲切为代码。没有已知入口、ISA和载入布局，直接交envydis没有证据收益，因此没有这么做。

十二个region内：**ELF/PE签名、gzip/xz/bzip2/zstd/lz4/zip均无命中；所有MZ候选均未通过PE链验证；所有zlib候选均未得到有效完整流**。MZ短串假阳性具体偏移全在`probe.json`，例如5090 FSP_RUN的0x125347、index23的0xd8afa/0xdda0d/0xdfed5/0xe7bfb。整个两ROM也无ELF或PE签名。不据此排除无头压缩、私有压缩、分段明文或RISC-V裸代码。

真实阻碍是**已识别结构化前缀尚缺可验证的私有容器记录含义/提取规则和执行入口映射**，而不是仅凭encrypted位下结论。

## 4. 别漏掉标准EFI压缩通道

两者第二PCI image code_type=3，EFI header有signature=0x0ef1、machine=0x8664、compression_type=1、EFI image offset=0x550。

- 5090压缩流文件偏移 **0x47f50**，开头两个u32为96623（compressed bytes）、186568（original bytes）。
- PRO压缩流文件偏移 **0x45750**，对应96571、186536。

这提供有依据的UEFI标准压缩解包目标，不是Falcon encrypted问题。已保存5090完整EFI option-ROM至`5090_efi_optionrom.bin`。现成`uefiextract ... report`未生成解包或report（未得到有效PE）；本机Python没有uefi_firmware/EfiCompressor，未在时限内安装新工具。因此本任务**没有成功提取/验证EFI PE**；后续可用EDK2 EfiDecompress严格按上述长度解压，核验MZ/e_lfanew/PE与section/entry，再搜容量读和初始化几何。不要把压缩EFI的无PE字节命中解释为无明文可执行代码。

## 5. 验证与限制

实际成功命令：`python -B probe.py`、`python -B trace_x86.py`、`python -B extract_capacity.py`（最终算术断言全部通过）、SHA256切片校验。脚本所有导入禁写pycache。

`*_legacy_linear.txt`只是导航，里面混有数据、表及inline脚本，不可作为整段代码证据。`trace_x86.py`从标准入口CS:0003跟踪到0x50->0x307c->push-CS/push-0x7c83/retf，遇0x81bb的jmp si停止；313条指令不是完整可达图。容量函数由独立call链、返回边界、公开寄存器布局和同构PRO代码确认，不宣称已完整解释所有legacy路径。

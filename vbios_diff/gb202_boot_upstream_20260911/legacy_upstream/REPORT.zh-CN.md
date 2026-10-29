# 原5090 legacy容量/几何上游离线追踪

## 结论

**本轮推进到两个明确边界，但没有找到写 `0x1fa3e0` / `0x9a0200` / `0x9a0204` 的真实初始化调用者。**

1. 已将 CS:7e32 分区容量函数中的内嵌脚本完整解出，并用 Unicorn 执行**原84字节函数、原脚本解释器和原读helper**。其上游输入是 **READ(0x2243c) -> ECX、READ(0x820c14) -> EDX**；不是猜总容量输入。
2. 按本地 NVIDIA BIT 官方规格核实：BIT I 主脚本表首指针为零，BootScripts/NonGC6/PrivateBootScript指针为零；BIT M v2 的 **+0x11 才是 Memory Script List**，5090 CS:81be、PRO CS:817e，前3个u32均零。没有从这些公开入口得到可执行的显存初始化脚本。
3. 新的固件边界证据：BIT I 指定的 **DevinitTables=(0x47a7,0x4bd)** 与5090固件 index23/index24载荷首记录的两个字段精确对应；PRO同构对应 `(0x47a7,0x3fc)`。这连接了 legacy 数据表和设备固件的明文记录，不等于已经解出固件代码、记录全字段或固件启动指令。
4. 修正前轮模糊地址：**CS:43fa 是单字节 RET；真正通用写helper入口是 CS:43fb**。

所有文件偏移必须加正确legacy基址：5090 **0x38000**，PRO **0x35800**。下文 `CS:` 为legacy相对地址。全程未访问GPU、PCI、BAR、/dev/mem，未原生执行ROM；Unicorn只有私有内存和host侧合成I/O回调。

## 1. 已验证的容量上游读取链

启动静态链补全前轮停止点：

```
CS:0003 -> 0050 -> 307c
3094 push cs / 3095 push 7c83 / 3098 retf
7cf5 mov si,7cfb; 7cf8 jmp 81bb; 81bb jmp si => 7cfb
7d35 call ef13  # 扩展ROM定位/映射，不是已证实的固件启动
7d38 call 7f23
7f23 call 7f3c  # 含显示相关寄存器脚本
7f26 call 7e32  # 分区求和
7f29 mov cs:[3078],ax
7f2d call 7e86  # 既有0x1fa3e0容量换算
7f30 mov cs:[307a],ax
7f37 call 7eff  # 另外3个寄存器写，不是目标容量/几何寄存器
```

### CS:7e32 / 文件0x3fe32，84字节

保存 EBX/ECX/EDX/ESI 后，CS:7e3a `call 1327`，紧接的13字节**不是x86**：

| CS / 文件 | 原字节 | 实际解释 |
|---|---|---|
| 7e3d / 3fe3d | `2c 3c 24 02 00 18` | 读0x2243c，写入保存寄存器帧+0x18，即ECX |
| 7e43 / 3fe43 | `2c 14 0c 82 00 14` | 读0x820c14，写入保存寄存器帧+0x14，即EDX |
| 7e49 / 3fe49 | `71` | 结束脚本；恢复x86返回地址至7e4a |

后续原x86：

```
7e4a xor ebx,ebx
7e4d mov esi,0x90020c
7e53 rcr edx,1
7e56 jb 7e5e                 # mask位1表示跳过该分区
7e58 call 4416              # read EAX
7e5b add ebx,eax
7e5e add esi,0x4000
7e65 loop 7e53              # 16位CX计数；不是ECX全宽loop
7e67 mov ax,bx
7e69 shr ebx,16
...                         # 高16位非零或结果为零调用21b1警告路径
7e7d..7e85 恢复并ret
```

精确依赖：两个上游寄存器、mask为0的各 `0x90020c+0x4000*i`、CS:d7a合成索引I/O基址、独立SS栈、原CS脚本/dispatch表。没有颗粒密度、row/column/rank编程。这里的寄存器名称只按机器码用途描述，没有未经核实的GB202私有字段命名。CX=0不是“零次循环”，该路径会回绕；测试没有提供这种无证据环境。

### 实际机器码仿真结果

`emulate_partition.py` / `partition_emulation.json`：

- 合成 `READ(2243c)=4, READ(820c14)=5`；四个分区值111/222/333/444，仅实际读取90420c=222、90c20c=444；**AX=666，1071条原指令**，原EBX/ECX/EDX/ESI恢复。
- mask=0，实际读取四项；**AX=1110，1097条原指令**。
- 缺少0x820c14响应时，**在CS:4428的IN回调报 unmodeled register 0x820c14并停止**，469条原指令；没有用0填补未知环境。
- 完成测试均到私有sentinel CS:ff00停止。所有OUT只是索引地址选择(base+8)，**没有base+12数据写**；所有guest内存写只发生在合成栈。
- 首次测试的sentinel未放终止字节，Unicorn翻译零填充区域产生FETCH_UNMAPPED；已改为在sentinel放HLT，并在执行该地址前hook停止，三个最终断言通过。没有修改目标函数/解释器机器码。

这些合成小整数只测试控制流和求和，不代表任何实卡容量配置。原CS:7e86的AX截断事实保持不变，不把它当96GiB初始化。

## 2. 内嵌脚本解释器及动态寄存器地址

- **CS:1327 / 文件0x39327**：`push es; pushad; mov di,sp; push ss; pop es`。ES:DI指向保存寄存器帧。
- **CS:1315**：从 `SS:[SP+0x24]` 取内嵌脚本地址；解释结束后在CS:1322将SI写回这个返回地址槽。
- **CS:1383/1385**：从CS:SI读取opcode。以CS:117c的0x85个word压缩dispatch记录查handler；小于0x100的word重设opcode序号。
- **CS:13b5 `call ax`**：动态dispatch边界。opcode **2c -> 14dc**；opcode **71 -> 17cb**。
- **CS:14dc..14f3**：读脚本u32地址至EDX，call1439；读u8目的offset，写 `ES:[DI+offset]=EAX`。
- **CS:1439 -> 13c3 -> 4416** 为读路径。
- **CS:1444 -> 13c3 -> 43fb** 为通用脚本写路径；RMW/WRITE/OR-AND/移位复制handlers在14b5、14f4、1511、1734。

**动态拼地址函数 CS:13c3..1438，118字节**：EDX为带标签地址，BH为上下文，生成ESI，保留EAX。

```
if EDX.bit31: offset = 0x800*(BH&3)
elif EDX.bit30: offset = 0x800*((BH&0xf0)>>4)
elif EDX.bit29: offset = 0x100*(((BH&0xf0)>>3)|((BH&4)>>2))
else: offset=0
ESI=(EDX+offset)&0x0fffffff
```

因此“没有完整u32立即数”不证明不能写目标。这里已找到并解释实际的动态地址生成，而不是仅扫字符串。不过本轮33个可完整解码的inline候选脚本中，出现的带标签寄存器是 `0x80612084` 一类显示区地址；未发现可拼到目标的实际operand/caller组合。

`analyze.py`：从原入口及已解析的7cfb继续递归，内嵌脚本按原dispatch handler长度跳过，得13089条静态候选指令、18个脚本入口；另把全legacy E8调用inline包装器的候选单独收集，33个全部解码到结束。候选不自动等于启动可达。未解决的间接调用包括 **2a90/2b1b/2a63 call di、42ea/20f5表调用、13b5 call ax**；81bb此次有7cf5提供的明确SI，但工具仍保留通用未解析边。不声称获得完整启动CFG。

## 3. 目标写helper调用者排查范围

`target_literals.json`：5090/PRO全legacy逐字节检查 `(u32 & 0x0fffffff)`：

- 0x1fa3e0各只有 **CS:7e8a / PRO:7e4a** 一处，是已知getter的`mov esi`立即数。
- 0x9a0200、0x9a0204均无此类literal（包含高位标签形式）。
- 这只是literal搜索边界，不排除表载入、任意间接输入、未分析设备固件的动态地址。

5090所有18处近CALL 43fb候选，及核查到的地址来源：

| 调用点CS | 地址来源 |
|---|---|
| 1449 | 脚本EDX经13c3动态生成；见上一节 |
| 1d1b / 1d42 | 固定6165d8 / 62580c |
| 1ebc | 9b2200 + 4*AL |
| 1f53 | 固定9b0604 |
| 3756 | 610000 + (输入ESI&ffff) |
| 3a0e / 3a2b | 本地直接caller 41d5/4206经4218生成9b0f08+4*(CL&f) |
| 3b5e / 3b83 / 3b94 / 3ba2 / 3bb0 | 3dba/3d8d/3da9选择ef00+40*(AL-80)、e800/e830，部分+4；是对应有效选择路径，非法AL路径另调用21b1，未假定其行为 |
| 4262 | 9b0014 + 20*(DX&1f) |
| 4537 | 620000 + (输入ESI&ffff) |
| f08c / f0ca / f0f6 | 固定10fd00，扩展ROM映射窗口路径 |

未找到直接E9尾跳43fb。仍不能排除未解析的间接调用。CS:43fb确实输出地址到base+8、EAX数据到base+12，区别于4416的读事务。

容量缓存后的 **CS:7eff -> call1327** 脚本具体写：

```
7f04: WRITE 0x625f04 = 0x00010e09
7f0d: WRITE 0x10fd40 = 0x00000100
7f16: WRITE 0x625f00 = 0x00000009
7f1f: END
```

这些是实际调用链中的写，但没有把10fd40猜成显存几何或FSP启动命令，也没有把这三项写误报为目标寄存器。

## 4. BIT I/M入口和设备固件数据边界

语义依据为本地已下载官方 **NVIDIA BIOS Information Table Specification**：
`/home/user/rt_5090_project/vbios_diff/rtx4090_24g_48g_compare_20260911/nvidia_BIT_spec.txt`，823..946行。
另交叉核查公开头 `driver_gpio_internal_610.43.03/src/common/nvswitch/kernel/inc/rom_nvswitch.h:572..589` 的BIT I v1结构。

`verify_tables.py`重新从两份原ROM通过memory_corpus.load定位，断言此前legacy切片逐字节相同。

| 字段 | 5090 | PRO |
|---|---|---|
| BIT I文件位置 | 38ee9 | 366e9 |
| I+00 主脚本指针表 | CS:47fb；首u16=0 | 同左 |
| I+0e PrivateBootScript | 0 | 0 |
| I+12 PCIeSettingsScript | 0 | 0 |
| I+14/16 DevinitTables ptr/size | CS:47a7 / 04bd；文件3c7a7 | CS:47a7 / 03fc；文件39fa7 |
| I+18/1a BootScripts ptr/size | 0 / 0 | 0 / 0 |
| I+1e/20 NonGC6 ptr/size | 0 / 0 | 0 / 0 |
| M v2 +11 Memory Script List | CS:81be；文件401be；首3个u32为0 | CS:817e；文件3d97e；首3个u32为0 |

M+0d是Memory Partition Information Table，不是脚本入口；M+15及之后不在上述公开M v2字段说明内，**没有擅自称为另一个脚本入口**。只报告M列表头没有非零脚本指针；不凭零填充长度猜整个私有列表格式。

### 前轮固件明文记录有了独立数据交叉引用

以下是原ROM中的真实五u32记录，index采用前轮Falcon表编号：

```
5090 index23 file c8040: 00350001 000047a7 00017eb0 000004bd 00001100
5090 index24 file e9c80: 00350001 000047a7 000057c0 000004bd 00001100
PRO  index23 file c66d8: 00350001 000047a7 000189e0 000003fc 00001100
PRO  index24 file e7a18: 00350001 000047a7 000058c0 000003fc 00001100
```

记录word1=BIT I DevinitTablesPtr、word3=BIT I DevinitTablesSize，在两种ROM都吻合且尺寸差异同步。这是**设备固件记录引用legacy devinit表区域**的强证据。已提取该表区域（5090 1213字节、PRO 1020字节），而不是将记录word2或word4擅自作为执行地址/解压长度。

**真正停止点**：尚未验证该容器的记录执行语义、固件ISA/载入映射/入口；亦未识别“legacy发命令启动设备固件”的具体指令。本轮能确定的调用链已经在消费设备容量寄存器；初始化计算者仍在该边界外。不能将空BIT脚本入口推导为“没有devinit”，也不能将ef13（扫描PCIR/NPDE、按code_type=e0寻找扩展图像）误认成FSP启动。

## 5. 产物与复现

- `confirmed_functions.txt`：按真实x86/脚本边界分离的重点反汇编。
- `partition_function.bin`、`partition_inline_script.bin`、`address_builder.bin`、`dispatch_table.bin`、`interpreter_and_handlers.bin`：原始切片；后者是连续区域，执行仍依赖原CS布局，不能单独原生运行。
- `5090_devinit_tables.bin`、`PRO_devinit_tables.bin`：按已验证BIT字段提取的数据。
- `dispatch.json`、`inline_scripts.json`、`inline_candidates.json`、`flow_expanded.json`、`call_candidates.json`、`target_literals.json`、`tables_verified.json`：可审计地址及边界。
- `partition_emulation.json`：逐条原指令PC、寄存器读、栈写、合成输入和停止原因。
- `disasm_*.txt`和`nvbios_5090.txt`只作导航。nvbios版本不识别Blackwell多种表，legacy-only输入也产生扩展指针OOB警告；**不以其显示脚本乱解结果作证据**。重点BIT字段使用自己的边界解析和官方规格核查。

最终复现命令：

```
python -B analyze.py
python -B verify_tables.py
../.venv/bin/python -B emulate_partition.py
```

没有写出本目录外文件；所有Python入口禁写pycache。结论仍是读取/解释器/固件表引用的离线证据，不是颗粒训练或32->96GB初始化成功。

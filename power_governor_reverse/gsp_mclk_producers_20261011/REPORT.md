# MCLK +3999/+4000：GSP 限幅源与 Pstate 输入生产链阶段报告

## 结论与边界

本轮不把 `MCLK_MAX_CAPABILITY` 当成已找到的 18000 MHz 硬上限。新闭合的是 **真实描述表 → 源对象构造**、**选表指针的 Pmu 身份**，以及 **Pmu 字节 → Perf 新源类型开关**。尚未闭合该源后续收到的数值、是否参与故障时的限制计算，以及 R570.215 设备端不完成请求的首因。

分析对象是本地 R610.57.04 GSP main，所有地址均为其内部 VA；不能直接套用到 MODS R570.215。原始 MODS 故障 GSP-RM 关闭，已确认的故障是 PMU completion wait 超时，而不是已收到非零拒绝响应。

全程静态：不访问 GPU/MMIO，不运行 MODS/固件，不修改固件。Ghidra 使用 `control_dispatch/work_db` 副本，`-readOnly -noanalysis`；临时修复函数/流属性仅在内存中，日志确认最终丢弃。

## 1. MCLK_MAX_CAPABILITY 是可被加载的源描述，不仅是字符串

`control_dispatch/capability_full_descriptor_table.json` 完整解析：

- 表基址 `0x01e21b98`，253 (`0xfd`) 行，每行 `0x20` 字节，结束地址 `0x01e23b38`。
- 最后一行 `0x01e23b18`：第一 dword `0xff`，第二 dword `0x122`（290），flags qword `0x11e`，名字指针 `0x01e8e860`，scope qword `0xff02`。
- 行序号是 252，不等于其内部索引字段 255。
- 对照 `MCLK_LIMIT`：行 `0x01e22e78`，第一字段 145、第二字段 `0xfb`。

表基址具有真实代码引用：`0x01bad062`，属于初始化函数 `0x01bacb98`。加载链：

```
0x01bacb98
  -> 0x01b9e158（逐行源描述加载）
  -> 0x01ac70bc（源类型工厂，type 6）
  -> 0x0169d810（共享源对象构造）
```

加载器把第一字段放入源对象 `+0x58`，第二字段放入 `+0x5c`，flags 低字节放入 `+0x60`，名字放入 `+0x68`，scope 两字节放入 `+0x70/+0x71`。因此仅搜索数值 `0x122` 不足以找到其使用者：还必须追索引 `0xff`、表基址、对象指针及泛化回调。

证据：`capability_table_base_xrefs.txt`、`capability_table_user.c`、`descriptor_loader_and_factory.c`、`capability_source_object.c`。

## 2. 选表对象已经确认是 Pmu

### 类身份，不靠偏移猜测

GSP 类分派器 `classid_to_child @ 0x0141f1c0` 用 `(u32)arg1 >> 8` 得到类 ID：

```asm
0141f2d8: lui  a4,0xf3d
0141f2dc: addi a4,a4,0x722
0141f2e0: beq  a5,a4,0x0141fa8e
0141fa8e: lui  a5,0x2
0141fa90: add  a5,a5,a0
0141fa92: ld   a0,0x50(a5)     # pGpu + 0x2050
```

本地同版本公开生成头 `/usr/src/nvidia-610.57.04/src/nvidia/generated/g_eng_desc_nvoc.h:609`：

```c
#define __nvoc_class_id_Pmu 0xf3d722u
```

### 分配/赋值链也可对应

`0x014200d4` 的调用准备 `Pmu` 类 ID `0xf3d722`、实例 0、输出槽 `pGpu+0x2050`，进入 `0x01419ab4`。该 helper 创建动态类对象、调用 `0x018d23b4(object, 0xf3d722)` 转成 Pmu 视图并写入输出槽，然后调用 engine 构造接口。

动态类选择由 GPU engine registry，以及 `0x01813ef0` 的 `RmPmuUcodeProfile` 查询控制；本轮未绑定实际 GB202 registry 行。不能因为找到一个派生类工厂就假定运行时必选它。

证据：`gpu2050_identity_candidates.c`、`pmu_gpu_slot_classid_raw.asm`、`pmu_child_slot_factory.c`、`pmu_engine_kind_selector.c`；Pmu 类描述 `0x01c631c8` 的 ID/大小以及相关 RTTI xrefs 另存于 `pmu_classdef_xrefs.txt`、`pmu_rtti_xrefs.txt`。

**据此，`+0x78d/+0x78e` 是 Pmu 对象字段，不是已经识别的 GB202/GB203 型号开关。字段的符号名及初始化值仍未恢复。**

## 3. Perf 类型选择也受 Pmu 字节控制

`perf_init_locked_impl @ 0x0164bb38` 首部：

- `s11 = *(pGpu+0x2050)`，即 Pmu；
- `s1 = a1`，即此函数的 Perf 参数。

在进入相应初始化分支后：

```asm
0164bec4: li   a5,1
0164bec6: sb   a5,0x2e6(s1)
0164beca: beqz s11,...
0164bece: lbu  a4,0x78c(s11)
0164bed2: beqz a4,...
0164bed6: sb   a5,0x2ea(s1)
```

因此 Pmu `+0x78c != 0` 会在该分支中设置 Perf `+0x2ea=1`，后者使 `0x01bacb98` 进入新 type-6 源加载路径。不能省略外围 Perf 模式门，简化成全局 iff。

随后同一 Pmu 对象的两个字节决定描述表：

| Pmu 字段条件 | 表 | 行数 | MCLK_MAX_CAPABILITY |
|---|---|---:|---|
| `+78d==0 && +78e!=0` | `0x01e21b98` | 253 | 有 |
| `+78d!=0` | `0x01e23b38` | 245 | 无 |
| `+78d==0 && +78e==0` | 错误分支 | — | — |

已独立解析第二表，文件 `alternate_f5_descriptor_table.json`。第一表比第二表多出的名字恰为 8 项：

- `MCLK_MAX_CAPABILITY`
- `MODS_RULES_IODVDD`
- `OVERVOLTAGE_IODVDD`
- `RAM_ASSIST_UNLOAD_DRIVER_VOLTAGE_RAIL_4`
- `RELIABILITY_ALT_IODVDD`
- `RELIABILITY_IODVDD`
- `UNLOAD_DRIVER_VOLTAGE_RAIL_4`
- `VMIN_IODVDD`

这不是仅一个内存频率开关的差异。不能据此断言 GB202 与 GB203 分别选两表；更不能直接推出 GB202 的限制值为 18000 MHz。

原 worker 的 `table_activation/REPORT.md` 未闭合对象身份，本节及其 parent addendum 补上该点。此前 `0x012b6fe2/0x012cab4a` 等同偏移写入仍未证明属于该 Pmu 实例，不作为字段生产者。

## 4. 源输入缓冲已找到，但数值生产者未绑定

共享源对象有 `+0x88`、长度 `0xb0` 的缓冲，构造时清零。已恢复的回调：

- `0x01656518`：对象 `+0x88` → 输出参数 `+4`，复制 `0xb0`；
- `0x01656844`：输入参数起始位置 → 对象 `+0x88`，复制 `0xb0`；
- `0x0165571c`：对象 `+0x88` → 参数 `+8`，同样是输出方向，不能误称来自 PMU 的数值生产者。
- type-6 的 `+0x148 = 0x01695220` 找到 ClockManager `+0x1170` 的映射对象/工作区，单凭该映射并不构成频率计算。

通用输入解析 `0x01651d84` 接受 Pstate 引用、关系/域引用加 32-bit 数值、直接数值等输入形态；没有在该段发现固定 18000 MHz 的比较。但它不是已绑定的 MCLK source 更新栈，也不足以证明整个源计算没有上限。

缺口：哪次操作为 `index=0xff / ID field=0x122` 填入有效输入或工作结果，数据的单位、值及后续约束合成路径。名字、metadata flags、缓冲清零都不能替代这一证明。

证据：`source_input_and_working_buffer.c`、`capability_status_import.c`（文件名沿用探查名称，但其 `0x0165571c` 实际方向是输出）、`capability_source_object.c`。

## 5. Pstate 描述符上游与反编译修复

`pstate_descriptor/REPORT.md` 与原始指令确认工厂 `0x01670ea0` 的 selector 来自 **第二参数 a1 的 byte0**：

- call `0x01198f0a`：`s8`，selector 1，Perf/runtime getter `0x0167be2c`；
- call `0x01198fb8`：`s6`，条件 selector 9，getter `0x01692ea8`；
- call `0x01199018`：`s9`，selector 3，缓存 getter `0x0168ac3c`。

这些不是一个已绑定的“全局 GB202 selector”。范围/cache 输入的来源已到 BIOS 解析器，但当前运行的表/分支仍未闭合。

### 先修掉错误的 memset 后终止

`0x01ae518c`、`0x01ae535c` 先前被反编译成只清零的短函数，原因是调用已知 `memset_like @ 0x01be41ec` 的两条指令 `0x01ae51be/0x01ae538e` 被赋予 `CALL_RETURN` flow override；callee 本身并不是 noreturn。

在只读项目副本的内存中，仅对这两次已验证的 memset 清除错误 override，补齐各自原始指令边界并重建函数 body：

- `0x01ae518c..0x01ae535b`：要求 header version `0x50`，解析 2/3-byte 主记录和 `1w1d` 域子记录；
- `0x01ae535c..0x01ae55b3`：要求 version `0x40`，根据主记录长度选择格式，解析 `1w2b` 子记录；
- `0x01ae4fac` 的已恢复路径要求 version `0x60`。

`pstate_parsers_repaired_copy.c` 是修复后的输出，`RepairBoundedParserCopy.java` 当前版本只解除目标为已知 memset 的 override。原始字节不改变，退出时 Ghidra 丢弃修改。

另用 LLVM `--mattr=+m,+a,+c,+f,+d` 重导出 selector-3 域循环（worker 的早期窗口遗漏 M 扩展，显示了 `<unknown>`）：`s5=1000`，域字段 `+0x34` 等于 `0x1a` 时跳过乘法，其余范围/数值通过 `mulw` 乘 1000。证据是 `pstate_selector3_frequency_units_raw.asm`。这补上了缓存频率单位的转换，不是 OC SET 的验证路径。

### ROM 探查不能直接替代路径绑定

完整候选 ROM `281814.rom` 的 BIT P 主指针 `P+0=0x202a8`，高指针使用最终 expansion bias `0x50000`（legacy base `0x38000` + expansion offset `0x18000`），解到 ROM `0x702a8`，其 header 起始为 `70 0e 05 07 ...`。

`live-vbios-sysfs-full.rom` 的非零前 `0x27a00` 字节与该完整 ROM 从 `0x38000` 开始的区间相同；但该 sysfs 镜像不能覆盖上述表体，严格 PCI 链解析遇到后续全零区失败。不能拿 sysfs `0x202a8` 当成主表位置，或把候选完整 ROM 的表体当成已捕获运行时实例。

更重要的是，尚未把所追 0x40/0x50/0x60 解析器的具体 BIOS 对象指针绑定到这个主指针。不能仅凭 version 0x70 就宣布此前 factory 为 dead path，也不能反过来声称它必然是 GB202 当前路径。

证据：`verified_rom_bitP_pointer_heads.json`、`pstate_descriptor_upstream_helpers.c`、`pstate_parsers_full_raw.asm`。

## 下一步最小闭合链

1. 追 **同一个 Pmu 实例的 `+0x78c/+0x78d/+0x78e`** 初始化（包括 firmware-info 导入、动态循环或块复制），而不是把别的结构同偏移写入当成生产者。对象分配槽/类身份现已明确。
2. 追 `source +0x88` 或其 ClockManager `+0x1170` 工作结果的更新者，明确绑定 index `0xff`，恢复实际约束值及单位。
3. 将 BIOS 对象指针/版本分支与真实 GB202 ROM 的记录连起来，确定检查使用的 Pstate cache，而不是只确定某个可构造 selector。
4. 只有这三者闭合后，才有资格讨论该 GSP 限幅源是否对应 18000 MHz；仍需另证它如何对应到 GSP-RM 关闭的 R570.215 请求/completion 路径。

本轮没有找到足以归因 +4000 失败的具体 cap 比较地址或设备端 handler。上述新增结构证据并未改变这一结论。

## 最终交叉核验

重新计算 full RX SHA256：`50614073f1ca73d4a10e66bdba15e557763b402c75b203a8950161c0afe59085`，与此前已核实的 R610.57 GSP RX 一致。脚本断言通过：253/245 行数、第一表索引唯一、capability index `0xff` / ID field `0x122`、第二表无该名称、同版本 Pmu 类宏及原始分派指令、两条 memset-only 修复及只读退出丢弃日志。未使用未完整核验的 PMU engine 临时修复 C 输出来断定字段生产者或 cap 值。

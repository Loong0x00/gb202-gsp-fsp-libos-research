# GB202 app19 / id89：命名与初始化可见边界

## Result

**后续补证：** 同级`fbfalcon_locator/REPORT.zh-CN.md`已找到virtual+8d0的真实查表实现：比较Falcon entry首字节与selector，返回entry+2的descriptor ROM相对指针（不是entry index）。因此下面保留的“selector末跳未确认”描述是本分支最初的边界，已被后续证据推进；具体vtable在GB202的实例化仍未闭合。两ROM现已由正确PCI-chain loader验证。

**发现了此前遗漏的 NVFlash 独立 v6 extent consumer，以及两个有直接静态表支持的名称；但没有恢复设备端原代码入口，也没有找到针对显存容量/几何的拒绝条件。**

- **id89 的 NVFlash 内部对象名是 `postLtssmDevinitCfgDataTable`。** 不是靠搜索到一个 meminit 字符串猜测：三份对象元数据记录都将数值 `0x89`、该名称指针、callback 放在同一条48字节记录内。
- **app19 最强的新命名证据为 `DevInitFMC`**：该对象 callback 明确将 selector `0x19` 交给通用 Falcon 对象 extent helper。由于本次没有继续解析 helper 内 `vtable+0x8d0` 的具体目标，把“selector就是Falcon ApplicationID”的最后一跳保留为**强推断**，不伪称正式公开枚举定义。
- **MODS 的 `RVDevinit ucodeDescV6` 不是 app19 的消费者！** 已恢复调用者：它只对 **application 0x1d / target 1** 走该 parser；app19 在同一路径的 allowlist 被跳过。这是本轮防止错误认领的重要结果。
- 显存训练属于 devinit 的公开证据存在：官方 GB202 FSP 源码明确写 `FBFalcon training during devinit`。但不能把整个 devinit 或 DevInitFMC 等同于唯一显存初始化程序；尚未闭环 id89 字段→FBFalcon参数/CFG寄存器/拒绝分支。

仅静态读文件、下载官方文本，没有运行 NVFlash/MODS/ROM，没有硬件操作，没有解压扫描或密文反汇编。

## 1. 直接命名证据与版本陷阱

NVFlash 文件：`/home/user/rt_5090_project/vbios_flash_tools/nvflash_5.877_hpe/nvflash`；SHA256见 `verification.json`。以下地址均为 ELF VA（此区间 file offset=VA−0x400000）。

| 元数据 name-pointer 槽 VA | 同记录 id | 名称 | callback |
|---|---:|---|---:|
| fcba40 | 89 | postLtssmDevinitCfgDataTable | 488c40 |
| fce710 | 89 | postLtssmDevinitCfgDataTable | 488b90 |
| fd13f0 | 89 | postLtssmDevinitCfgDataTable | 493264 |
| fcba10 | 8a | preLtssmDevinitCfgDataTable | 488ae0 |
| fcc040 | 86 | DevInitFMC | 48f778 |
| fcc070 | 87 | PostLtssm | 48b520 |
| fcc0a0 | 88 | PreLtssm | 48f762 |

其中 metadata 的 `86/87/88` 是**对象/region id**，不要与Falcon application字节混同。DevInitFMC callback `48f778` 的 `48f77f: mov ecx,0x19`、`48f784: call 48f44a` 是独立一跳；PreLtssm对应selector1a，PostLtssm callback使用selector15。`48f44a` 保存selector，随后 `48f476: movzx esi,bpl`，交给 `vtable+8d0`；再经 `+8c8` 获得descriptor位置并读版本。不能把对象id86直接当app86。

**版本不匹配必须保留：** id89元数据标记包含 `69 02 72 00`；callback488b90和493264确实读取输入base+72。当前两ROM独立验证的 owner 却是 **BIT.i+6e**，+72指向id8a。因此不能照抄NVFlash旧BIT偏移重新切当前ROM。该名称是跨版本强线索，当前owner/长度仍由ROM自带typed id和source record独立确认；这些callback只取地址/长度，没解析blob中的显存几何字段。文件名 `nvflash_id89_blackwell.asm` 仅为产物标签，未证明其具体类/HAL就是GB202。

两原ROM复核：
- Astral D=c7ff0，body=[c8130,e9c30)，id89源=[9cf75,a74b9)。
- PRO D=c6688，body=[c67c8,e79c8)，id89源=[9a9dc,a5750)。
- 两者N=12、stride20、头长50；source record89总长分别a544/ad74，与typed header的8+length相等。没有使用旧 immediate-body 边界。

## 2. 实质修正前轮 bounded negative：NVFlash有另一条v6识别路径

前轮 `parallel/nvflash_v6_parser_reverse.md` 关于 **7dde66 classifier 错将v6落到旧GFW-v1** 的结论不变；但“未找到第二条明确 v6+50 consumer”这个有界搜索结果，**被本轮新函数推翻**。

`nvflash_generic_v6.asm`（函数48f44a）：
- 48f4cb 比较版本6，跳48f5e8；48f5f8比较头长50。
- 48f659读descriptor+1a/u16，48f66c读+1c/u16。
- 48f68f..48f697计算count*20；48f69f计算count*stride；不等时返回状态候选 **0xc9**（48f6ac..48f6b1）。
- 48f6b5读取+4；48f6c5计算 **word1+count*20+0x50**，用于输出region extent。
- 查找结果为ffffffff返回 **0x78**。此处未验证NVFlash错误码官方符号，不为c9/78强起名字。

这是与原ROM观测完全相合的**有结构依据的外层长度consumer**，不是解密器、设备loader或寄存器写入程序。且count=0时count*stride==count*20成立，不能将这条比较说成严格无条件stride==20。不匹配版本/头长还有旧fallback，不能将其称为全面安全格式验证。

另一个具名PostLtssm callback48b520也有独立v6+50分支；其selector15与当前app15相符的程度仍受同一virtual-selector未解析限制。

## 3. MODS v6 parser与可见启动/失败分支（明确不是app19）

MODS文件：`/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods`；只静态读取ELF。`objdump`显示的远距离C++最近符号名无意义，不能当函数名。

### 3.1 谁调用

- 670d5db读Falcon entry（格式字符串 `0x91845f7`，该循环的parsed app字段在rsp+90）。
- 670d627只允许1d进入后续descriptor路径；19不匹配，670d632→670eb6b跳到下一entry。
- jump table **9cec130[1d]=670f4b8**；**[19]=670eb6b**。verify.py直接读取验证。
- 670f4b8检查target==1；670f4f3调用 **675f810**。
- 675f810的日志为`Parse RVDevinit`，只分版本4/6；675fae8是v6路径，日志`RVDevinit ucodeDescV6`。这份MODS确实有v6 parser，但不能从这一事实推出它会执行当前ROM的app19。

### 3.2 能看到的外层消费与启动参数

v6记录解析格式字符串 **2w4d**（VA9185311），即两word、四dword；每条ROM record为20字节，host展开记录占24字节。v6 descriptor parser计算count*stride并跳过记录后存body指针；检查stride20触发诊断helper，而非已证明的硬拒绝。

host执行候选函数 **675fdd0** 使用此前保存的code/data source、target和length；helper **675f5c0** 收到 `edx=target, rcx=source, r8d=size, r9d=code/data选择`。v6外置记录路径675fed8..675ff0e按host结构+8 ROM offset、+c DMEM offset、+10 size传入；日志明确称 `dmemOffset, romOffset, size`。这给出**相同记录体系中**目的字段与copy长度的语义支持，但这里没有type1/type2完整分派，也不是当前app19实证执行。

675ff70打印 `Can't run when PRIV LOCKDOWN engaged. Please turn on dev mode.` 并提前返回；**这条分支并未显式设置新的失败码，返回保留r15d，因此不能说它一定返回某个NV_ERR。**

启动前676007c..67600b5经HAL地址转换，再设置启动信息；67600e2调用HAL+290，67600ee调用HAL+2f8检查RISC-V active。false路径打印 `flcnIsRiscvActive_HAL not active`，最终返回 **0x55**。缺少HAL具体实现与映射，不把这些host call地址冒充设备PC。

失败分支范围：
- parser不支持版本：0xffff；分配失败：0x51；读取失败传播helper status。
- RISC-V未active：0x55；Devinit完成检查false：日志`Devinit complete is false`，返回0xffff路径。
- 公共nvstatuscodes.h分别定义0xffff=NV_ERR_GENERIC、51=NV_ERR_NO_MEMORY、55=NV_ERR_NOT_READY；这是RM状态命名，不是显存geometry拒绝码。
- 上述全是host解析/权限/启动/完成检查；没有`density/row/rank/c000`的验收条件。

## 4. 真正显存初始化在哪一层可见

本轮联网下载官方main：
`https://raw.githubusercontent.com/NVIDIA/open-gpu-kernel-modules/main/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb202.c`

保存 `upstream_kern_fsp_gb202.c`，关键61–64、80–85、94–101行：
- Bootfsm在chip reset之后触发FSP；host等待FSP写boot-complete成功标识。
- `FBFalcon training during devinit`；更大显存WS SKU等待增加到5秒。
- 失败时记录FSP完成状态与四个scratch，标记reset并dump状态。这是**host观察固件初始化结果**，不是host执行id89几何合法性比较。

因此目前可见层级是：
1. **ROM/source元数据层：已闭环** id89属于app19引用的数据，并有post-LTSSM devinit配置名称线索。
2. **NVFlash区域目录层：已见** DevInitFMC selector19及v6外层extent/格式状态。
3. **MODS host offload层：已见但app不同** app1d RVDevinit装载/权限/RISC-V active/完成分支。
4. **GB202硬件安全启动/FSP/devinit/FBFalcon设备执行层：只有公开职责说明和host完成检测。** 未提取原code，未找到entry PC/ABI、id89字段consumer及显存拒绝条件。

FMC通常可作stage名称线索，但本轮没有针对这一对象的官方全称/执行职责文档，故不自行扩展全称。app19可能承担更广泛devinit/启动角色；其引用内存配置不等于它独占所有显存训练职责。

官方BIT文档也重新下载至 `upstream_BIT.html`：只公开传统大写I devinit表/脚本含义，不定义当前小写i+6e/id89 schema。这次未发现公开官方app19枚举或设备代码入口。没有找到入口就不声称“可执行提取成功”。

## Files Changed / Verification

所有新增位于本 `firmware_entry/`，没有改旧报告、原ROM或工具二进制。

- `REPORT.zh-CN.md`：本报告。
- `verify.py`、`verification.json`：源hash、NVFlash名称记录、MODS分派、两ROMdescriptor/id89边界；运行 `python -B verify.py` 已PASS。
- `find_refs.py`、`mods_refs.txt`：有界字符串immediate候选xref；关键候选另由objdump核实。
- `mods_{rvdevinit,parser_caller,app_dispatch,app_allowlist}.asm`：host有依据函数窗口。
- `nvflash_{postltssm,id89,id89_blackwell,selector_wrappers,generic_v6}.asm`：名称关联callback和独立v6 extent consumer。
- `upstream_kern_fsp_gb202.c`、`upstream_BIT.html`：官方网络证据快照（main/master非固定commit）。

剩余最具体工作不是扫压缩：解析NVFlash virtual+8d0确定selector命名末跳；寻找GB202 DevInitFMC/id89的真实设备consumer或公开ABI。现有静态证据不支持任何显存拒绝分支修改方案。

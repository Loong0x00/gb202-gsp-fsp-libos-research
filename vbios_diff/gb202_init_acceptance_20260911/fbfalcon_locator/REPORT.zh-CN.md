# FBFalcon 定点补充：ROM app 命名与 selector 最后一跳

## Result

**本轮闭合了 selector→Falcon entry.ApplicationID 的实际比较；但没有找到能把 app07/18/19/15 中任一个直接命名为 FBFalcon/显存训练的证据。** 不能继续把 DevInitFMC 当作唯一显存训练程序。NVFlash 唯一明确的 `FalconUcodeFbInit` 区域使用 **app08**；本次用修正PCI-chain loader解析的 Astral / PRO WS 两ROM均不含 app08。

所有 app/地址以下均为十六进制。NVFlash VA 的相关 file offset=VA−400000。

| 名称槽 VA | region id（非app） | 名称 | callback VA | 实际 selector |
|---|---|---|---|---|
| fcb710 | 见 verification.json | FalconUcodeFWSecLic | 48af1c | 07 |
| fcb740 | 36 | FalconUcodeFbInit | 48b21e | 08 |
| fcc010 | 见 verification.json | FalconUcodeSwitchBoot_PROD | 48f148 | 18 |
| fcc040 | 86 | DevInitFMC | 48f778 → 48f44a | 19 |
| fcc070 | 87 | PostLtssm | 48b520 | 15 |

每条均由同条静态记录的名称指针、callback，以及 callback 起始80字节内的 `mov esi,selector`（19为ecx后传helper）核验，不靠字符串邻近推测。`FalconUcodeFbInit` 另三个元数据名称槽 fce440/fd1120/fd3aa0 对应 callback 48b21e/496b40/49c4e2；三种 callback 均显式传08（附反汇编）。**FbInit 是工具区域名，不额外保证它在GB202的训练职责或适用性。**

定向字符串检索 `FBFalcon/FBFLCN/MemoryTraining`：只见 `Fbfalcon Reset`（file88754f）、`fbfalcon`（8ea422）；后二者没有找到完整64位名称指针元数据记录。未见 `MemoryTraining`/`FBFLCN` 区域名称。存在这些reset/引擎字符串不能据此认领ROM app。

## selector 最后一跳：已见真实实现，不是仅推断

从 .rodata 的静态 vtable 候选（零offset-to-top、多个有效代码槽）筛选，再只反汇编有依据的目标：

- address point **cd3858**：+78=4a07fc（读一字节）、+98=4a0952、+4f0=4a2d5e、**+8c8=4a426a、+8d0=4bce0a**。
- address point **ccf9d8**：**+8d0=4b33d0**，+8c8同上；独立实现有相同表项匹配结构。
- 另一些基类槽+8d0=4a4386，直接返回ffffffff；不是所有vtable都支持查表。

`lookup_4bce0a.asm` 完整函数证据：
1. 4bce1b保存输入esi到r12d。
2. 4bce82/87向+4f0传 **version=2、token=70（小写p）**，随后读其u32指针，交+8c8地址换算。
3. 4bcef0..4bcf2d读表头+3（count）、+2（stride）、+1（header size）、+5（检查所需长度）。
4. entry地址=table+header_size+index*stride；4bcfaf **`cmp BYTE PTR [rax],r12b`**，不等转下一条。
5. 匹配后4bcfb4 **`mov ebp,DWORD PTR [rax+2]`**，经过长度/可读性检查返回该descriptor指针；遍历失败返回ffffffff。这里**没有检查entry+1的TargetID**。

这与 ROM `BIT.p v2 → Falcon表；entry=<u8 ApplicationID,u8 TargetID,u32 descriptor>` 精确结构吻合，且Astral六字节表头 `01 06 06 23 01 30` 和实表位置独立解析验证。因此前轮“selector是否等于ApplicationID”已获得真实比较指令支持，**+8d0返回的不是entry index，而是descriptor的ROM相对指针**。

边界：没有继续恢复构造器/芯片HAL选择，不能声称已经证明某一个具体vtable在GB202运行时被实例化；也没有把该查表helper当设备loader。已证实的是NVFlash实际存在的查表实现与字段语义，不是目标native执行轨迹。

## ROM / GSP严格相等检查

Astral原ROM SHA256、NVFlash SHA256及GSP SHA256全部见 `verification.json`。Astral Falcon table=9ce9d：

| app | target | entry | descriptor | body半开区间 |
|---|---|---|---|---|
| 07 | 06 | 9cec1 | a7da0 | [a7df0,c7ff0) |
| 18 | 01 | 9cf27 | 10e104 | [10e1a4,11ada4) |
| 19 | 01 | 9cf2d | c7ff0 | [c8130,e9c30) |
| 15 | 01 | 9cf33 | e9c30 | [e9cbc,ef7bc) |

按v6 header50、N*stride、word1得到body；app07 N=0且stride=0是合法观测，不能强制stride==20。其余分别N=4/12/3、stride20。

只对这些**已确定完整extent**在 `/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin` 做精确字节查找：两ROM各4个app、每app的“descriptor+records+body”和“完整body”两种，共16次完整范围查找，**命中均为零**。每个范围的长度/SHA256均已记录。没有仅凭短magic或共同字符串宣布明文副本。

此结果只排除该bundle里的完整逐字节副本；**不排除其中有去签名/重排/局部代码/不同版本或不同编码的副本，也不能据此宣布ROM已加密**。没有做盲扫、解压猜测或载荷反汇编。

首轮错误使用旧`gb202_vbios_diff.py` loader，PRO被明确跳过。父进程随后将本目录`verify.py`切换到既有`memory_corpus.load`，没有改旧parser；重新验证PRO legacy base=`0x35800`及四个descriptor：07=`a6038`、18=`114504`、19=`c6688`、15=`e79c8`。当前`verification.json`已包含两份成功解析的ROM，无跳过。这个修正不改变app名称/selector比较结论。

## Verification / Files

运行 `python -B verify.py`：PASS（父进程修正loader后，两ROM均通过）。核验静态名称记录、selector机器码、两组具体vtable槽、最终字节比较/descriptor读指令、两ROM结构和16次GSP精确范围查找。中间验证暴露的N=0/stride=0及PRO parser问题已修正，历史失败没有作为有效切片证据。

新增仅本目录：`REPORT.zh-CN.md`、`verify.py`、`verification.json`；`named_callback_07/08/15/18/19.asm`、`callback_48b21e/496b40/49c4e2.asm`；`lookup_4b33d0.asm`、`lookup_4bce0a.asm`、`selector_lookup.asm`、`read_byte.asm`、`bit_lookup.asm`。callback辅助窗口为有界摘录，不声称全部为完整函数。

只读离线静态分析；未执行NVFlash/ROM/GSP，未访问硬件、未重复容量getter、未构建loader、未更改旧成果或原件。最终仍缺 **GB202具体训练设备code/入口或官方app→FBFalcon明确绑定**；本轮最重要的修正是 app07=FWSecLic、18=SwitchBoot_PROD、08才是工具显式FbInit，而非将19强行认领为训练应用。

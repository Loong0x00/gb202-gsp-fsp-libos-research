# FSP-ACE 静态分析战役总报告(2026-09-27)

> 目标(用户原话):FSP 固件上的任意代码执行漏洞;差一点则要"类似于 GSP 上已知内存溢出、但作用稍差"的新漏洞。
> 本战役 = 纯静态(未碰 GPU/驱动/设备,未执行固件,未联网,遵守项目红线)。
> 产物目录:/home/user/rt_5090_project/fsp_ace_static_20260927/

---

## 0. 一页结论

| 目标 | 结果 | 判定 |
|---|---|---|
| **FSP ACE(理想)** | **静态不可直接达成**——FSP runtime(FSP_RUN v6)AES-GCM 加密,本地/公开世界均无明文(本轮公开基线核查再次确认:FSP 解析器内存破坏在公开世界是空白,连 CVE 都没有;仅有的 FSP CVE-2025-23301/23302 是配置类 CWE-1244) | 硬约束 |
| **FSP 线静态产出** | ✅ 完整重建了宿主可达的全部协议面 + GSP 侧同族传输栈审计(明文)+ **7 组按同族证据排序的黑盒实验规格(B1-B7)**,其中 B1(多包重组溢出)、B4(COT 字段)、B7(GSP 身份注入)是本轮新增/大幅强化 | 交付 |
| **GSP 新溢出(保底)** | ✅ **三个 B 级候选缺陷,全部指令级证据 + 主 agent 独立复核**。最强:**GPU_EXEC_REG_OPS(RPC 0x32)handler 0x1a8a7f0——无界 count → 无界动态栈分配(sub sp,sp,count×32)+ 越界源读**,内容可经 staging 残留 grooming 部分控制 | **交付** |

## 1. FSP 线:静态能做什么、做了什么

### 1.1 为什么不能直接"读 FSP 代码找洞"(结论加固)
- FSP_RUN 镜像熵 7.999/字节,v6 descriptor bit2=ENCRYPTED,密钥芯片内锚定;三份样本(FE/Dell/HPE)密文跨厂商确定性一致(同明文同密文)。
- 公开基线核查(notes/PUBLIC_BASELINE_CHECK.md,5+1 项检索):**无人公开解密/转储 GB202 FSP**;无 FSP MCTP/NVDM 通道安全研究;无专有 GSP-RM blob 内存破坏 CVE。
- 新增结构性事实:FSP 镜像 165-225KB > EMEM 64KB 寻址范围 ⇒ 解密后代码大概率在 FSP 私有 SRAM,B2 类"EMEM 越界读"能泄漏的是数据结构/相邻通道而非代码本身。

### 1.2 本轮新钉死的静态事实(全部指令级/源码级)
见 notes/FSP_SURFACE_REVISIONS.md §A:
- **A1**:EMEM 命令队列完整寄存器协议(QUEUE_HEAD 是 FSP 读区间起点且宿主可写;TAIL=dword 单位;单包驻留非环形)。
- **A2**:MNOC 硬件语义(SIZE 19:0 为宿主自声明 RW,上限 1MiB,无硬件强制;CREDIT=边收边排空 ⇒ 1MiB 全推可行)。
- **A3**:SEC2/PSEC(0x840000)是第二个同型通道面(GB202 上驱动不用、寄存器在、COT 860B 是唯一已知合法消息)。
- **A4**:MSGQ 指针操纵只是流控(结构性理由,F1c 降级有据)。
- **A5**:GSP 侧 FSP 传输栈定位(EMEM 后端 0x15015c8/0x14fb74c、MNOC aperture 0x150a3b0 base=0x8f1e00/span=0x200、RmFspUseMnoc 位→ctx+0x1dd/0x1df、方法槽 +0x158/+0x1c8/+0x1d0)。
- **A6**:✅ **宿主可向 GSP 注入伪造"FSP 响应"**(0x14FB74C 读的 MSGQ_HEAD/TAIL/EMEMD 全部宿主可写;拷贝有界 ⇒ 定性为内容控制/状态机欺骗原语,非溢出)。

### 1.3 GSP 同族传输栈审计(FSP_TRANSPORT_AUDIT.md,负结果为主)
- mctpSubmit(0x1B594D0)= 本地类型化 API(0x0F-0x14 分发,拷贝长度全为立即数)——**无声明长度驱动拷贝**。
- GSP 的 EMEM FSP→GSP 收包(0x14FB74C)= **先验后拷**(容量比较在 EMEMD 读取之前)——安全序。
- GSP↔FSP 的 tdisp 服务(0x18BBD60)= 固定 0xA4/0x78。
- **未决**:MNOC 动态接收槽(对象方法表运行期绑定,静态无法唯一解析)——这正好由 B7a/B3 黑盒实验覆盖。
- **GSP→FSP 发送原语已重建**(mctpSubmit 调用约定 + 24 个调用者),配合既有 GSP 代码执行能力 = "以 GSP 身份"向 FSP 发任意 NVDM 的完整路径。

### 1.4 FSP 侧黑盒实验规格(修订版,notes/FSP_SURFACE_REVISIONS.md §B)
优先级:B1 多包重组溢出(同族 K3-1 同型,FSP 必须实现)> B4 COT 字段探测(size/version/四个地址字段从未 fuzz;gspFmcSysmemOffset = FSP 任意物理读 oracle 候选)> B2 QUEUE_HEAD≠0(区间平移/下溢)> B3 MNOC 1MiB(既有 spec+V4 变体)> B7 GSP 端口嗅探+注入 > B5 SEC2/PSEC > B6 port 归属。
全部带构造、判据(错误码/泄漏字节/WDT Xid/信箱挂死)、风险与复位预案。

## 2. GSP 线(保底):三个新候选缺陷(RPC_LAYER_AUDIT.md)

**共同背景**:RPC 分发层(E3)首度闭合——18 项 function→handler 表 @0x1e14190,分发器 0x1a92054(取 payload+0xc 的 function,16 字节步长查表,间接调用)。全部宿主可达(经命令队列 E1)。

### F-1【最强】GPU_EXEC_REG_OPS(RPC 0x32,handler 0x1a8a7f0)— 无界 count → 无界 VLA + 越界源读
指令级证据(主 agent 独立复核一致):
```
0x1a8a840-46  仅检查消息长度 > 0x57(88B 固定头)
0x1a8a84a     lw a2, 0x3c(s3)          ; count = payload+0x3c(宿主可控,无上限检查)
0x1a8a852-5e  a0 = count*32(64 位干净乘);t3 = payload+0x58 + count*32(校验循环终点)
0x1a8a864-90e 校验循环:按 32B 步长逐项读(payload+0x58 起),只查 opcode/类型范围,
              终点 t3 不与消息末端比较 ⇒ 越界源读(读到 staging 残留 = 可 grooming)
0x1a8a916     sub sp, sp, a0           ; ★ 动态栈分配 sp -= count*32,无任何上限
0x1a8a92c-98c 拷贝循环:把 count 个 32B op 从源(越界读)写入新 sp 起的 VLA
```
**攻击形态**:短消息(length=0x58+32) + count=N≫1 ⇒ (a) 校验循环读 N-1 个"幽灵 op"(staging 残留,grooming 可控且需首字节过 opcode 检查);(b) sp 下移 N*32 字节后写入 N*32 字节 ⇒ **超出任务栈边界的下方写入**(count=0x4000 ⇒ 512KB)。若下方无 guard page 而是映射区(其它任务栈/堆),即成大范围受控破坏;若有 guard page 则 DoS。
**未定级项**:GSP 任务栈大小/边界未从静态取得 ⇒ 定 B+(动态一枪即可定级:发 count=0x4000,看 scause/sepc/stval 是 store-fault 在栈下(guard)还是别的签名)。
**与 K3-1 关系**:不同层(msgq 接收层 vs RPC 分发层)、不同原语(线性 staging 溢出 vs VLA 栈分配+越界读)、独立缺陷。
**附带**:该 RPC 早被本项目实测用过(EXEC_REG_OPS 写 PLM 被拒)⇒ 路径活跃性无疑。

### F-2 IDLE_CHANNELS(RPC 0x16,handler 0x1a91e90)— 单位错配 + 三段 VLA
`0x1a91f00 bltu a4,a5` 比较"实际字节跨度 ≥ nchannels"(字节 vs 条目,错配)⇒ 0x2C 字节消息+nchannels=1 也能过,随后从 payload+0x2c 按 12B stride 读(全越界)+ 三次 round_up(count*4,16) 的 VLA。count*12 溢出有 mulhu 检查(仅防溢出,不防单位错配)。B 级。

### F-3 SET_REGISTRY(RPC 0x49,handler 0x1a961f4)— 表 size 与 numEntries 脱钩
只验 `actual_len ≥ size+0x20`;numEntries 独立读取、以 16B stride 逐条消费,无 `numEntries*16 ≤ size-8` 交叉检查;条目内 offset/length 字段进入字符串/二进制分支无表内界检查 ⇒ 越界读 + 潜在更深问题(未证越界写)。B 级。

### 2.1 其余 15 个 handler
全部指令级过检(固定长度/有界检查),记录在 RPC_LAYER_AUDIT.md 的 18 项表——**RPC_RM_CONTROL 的下游 NV2080_CTRL 回调面未穷尽**(外层封套长度检查已证存在,内层回调待后续)。

## 3. 公开基线(notes/PUBLIC_BASELINE_CHECK.md)
- FSP_RUN/v6 解密、FSP MCTP/NVDM 通道安全、专有 GSP-RM blob 内存破坏:**公开空白** ⇒ 本战役所有发现均为新territory。
- 最近的 FSP CVE(2025-23301/23302,HGX/DGX VBIOS/LS10)= CWE-1244 配置类(unsafe debug access),非内存破坏;证明 FSP 代码库出过安全问题且 NVIDIA 会修,但不改变"解析器缺陷未公开"的判断。
- 工具链:envydis/ghidra_falcon 只覆盖旧 Falcon 明文;对 Blackwell FSP 无能为力(与本地判断一致)。

## 4. 建议的下一步(按性价比)
1. **F-1 动态定级一枪**(已有 rpc_ovf_patch 工具链可改造:发 RPC 0x32,length=0x58+32,count=0x4000;观测崩溃签名)— 把 B+ 升/降为 A 级既成事实或 guard-page DoS。
2. **FSP 侧 B1(多包重组)+ B4(COT size 字段)** 黑盒轮(工具 fsp_probe2/prcraw 现成;按既有纪律:无驱动环境、一档一命令、复位预案)。
3. **B7a 嗅探**(零风险)定 MNOC 端口归属 ⇒ 决定 B7b(GSP 身份注入 0x21)可行性。
4. (可选)F-3 的字符串/二进制分支深挖(SET_REGISTRY 的 offset/length → 拷贝目的地尺寸),可能升级为堆溢出。

## 5. 产物清单
```
fsp_ace_static_20260927/
├── FSP_TRANSPORT_AUDIT.md          GSP 侧 FSP 通信栈/MCTP 审计(Track F1)
├── RPC_LAYER_AUDIT.md              RPC 分发层审计 + F-1/F-2/F-3(Track G1)
├── NVDM_DEMUX_AND_ENTRIES_AUDIT.md NVDM 解复用与 E1-E7 入口全景(Track G2)
└── notes/
    ├── CONTEXT_BRIEF.md            战役共享上下文
    ├── FSP_SURFACE_REVISIONS.md    A1-A6 新事实 + B1-B7 实验规格(主 agent)
    └── PUBLIC_BASELINE_CHECK.md    公开基线核查(5+1 项)
```
所有结论带 VA+反汇编;置信分级 A/B/C;阴性结果(排除项)均已记录原因。

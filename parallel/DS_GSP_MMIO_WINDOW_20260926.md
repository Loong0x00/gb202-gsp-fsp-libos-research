# DS:GSP-RM 在自身地址空间访问 GPU 寄存器(BAR0/PRI)的基址与机制

日期:2026-09-26。范围:**只读本地文件静态分析**。未访问 GPU / 驱动 / 设备节点 /
BAR / MMIO / PCI config / debugfs,未执行固件,未联网,未做任何设备侧操作。

| 项 | 值 |
|---|---|
| 主工件 | `/home/user/rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin`(RV64GC,基址 `0x1000000`,md5 `138c287af83b5026770f636b3b2c9f4b`) |
| 长度/PH | 文件 `0xE97000`;PH0 `vaddr 0x1000000 filesz/memsz 0xE9B000 (R+X)`→ **尾部缺 `0x4000` 字节**,PH1 `vaddr 0x4000000 filesz/memsz 0x1D5000 (R+W)`(RW 段用同目录 `gsp61057_rw_full.bin`),PH2 `PT_TLS 0x203C6000` |
| 入口 | `e_entry = 0x1A9E1C0` |
| 工具 | 既有 `k3_device_work/rvlib.py` + 本轮新增 `ds_work/{gsp_mmio_window_evidence.py, find_writer.py, stores_range.py, fanout.py, grep_disasm.py, scan_lui_range.py, track64.py}` |
| 产物 | `ds_work/regwin_*.asm`(25 个反汇编片段)、`ds_work/README_regwin_rerun.md`(复跑命令) |

---

## 0. 一句话结论

**GSP-RM 的寄存器访问不使用"固定大基址常量"。** 它是一个**两级指针 + 常量选择器**:

```
aperture  = *(u64 *)(pGpu + 0xB98)      // 设备映射数组第 0 项的 GSP 虚拟地址(gpuNvAddr)
selector  = (*(u64 *)(pGpu + 0x318))()  // 本 chip 的常量 getter → 0x820000(即 fuse 域 devicePriBase)
addr      = aperture + selector + reg_offset      // 然后 32-bit lw / sw
```

因此:要让"往 4 字节的写"落到 BAR0 `0x008200d0`,GSP 侧地址 =
**`*(pGpu + 0xB98) + 0x8200d0`**(fuse 域 offset `0xd0`,已由驱动侧 RegHal 表交叉验证)。
所有窗口基址都是**运行期值**,镜像里**没有任何**固定常量基址(GSP 端也没有
先写"选择器寄存器"再访问窗口的序列)。

---

## 1. 机制与证据

### 1.1 核心惯用法(镜像里逐字节出现 5 次)

`ds_work/gsp_mmio_window_evidence.py` 在 RX 段搜索 16 字节序列
`03 37 85 31 85 66 b3 07 d5 00 83 b4 87 b9 02 97`,命中 5 处:

```asm
ld   a4, 0x318(a0)        ; method  = *(u64*)(pObj + 0x318)
lui  a3, 1
add  a5, a0, a3           ; a5 = pObj + 0x1000
ld   s1, -0x468(a5)       ; aperture = *(u64*)(pObj + 0xB98)
jalr a4                   ; a0 = selector()  → 0x820000(GB202)
addiw a5, a0, K ; srliw a5,a5,2 ; slli a5,a5,2 ; add s1,a5   ; ← align4(selector + K)
lw   a0, 0(s1)            ; 读 == *(u32*)(aperture + align4(0x820000 + K))
```

5 处消费者(也是 5 个独立的正校准点):

| 消费者函数入口 | site | K | 等效 BAR0 地址 | 驱动 GB202 RegHal(domain 5) 同值? |
|---|---|---|---|---|
| `0x13585FC` | `0x1358606` | `0x3814` | `aperture+0x823814` | ✓(id `0x10570000`) |
| `0x1414ED8` | `0x1414EE2` | `0xC04` | `aperture+0x820C04` | ✓(id `0x10D04000`,=`OPT_DISPLAY_DIS`) |
| `0x1415074` | `0x141507E` | `0x3F4` | `aperture+0x8203F4` | domain 5 表内无;domain 30 有(见 §4) |
| `0x14F6D64` | `0x14F6D6E` | `0x434` | `aperture+0x820434` | ✓(id `0x109AC000`) |
| `0x18B042C` | `0x18B0436` | `0x74C` | `aperture+0x82074C` | domain 5 表内无;domain 30 有 |

产物:`regwin_idiom_*.asm`。**FACT:selector 返回的 0x820000 被当作"域基址"加在
aperture 上**,与驱动侧 `domain 5 → 0x00820000 + offset` 完全一致。

### 1.2 selector 是"每 chip 安装的常量 getter"

```asm
0x01415B2C   c.addi sp,-0x10 ; c.sdsp s0,8(sp) ; c.addi4spn s0,sp,0x10
0x01415B32   c.ldsp s0,8(sp)
0x01415B34   lui a0, 0x820            ; a0 = 0x0000000000820000
0x01415B38   c.addi sp,0x10 ; 0x01415B3A c.jr ra
```
同样的常量返回函数还有 `0x1441AB4`(同为 `lui a0,0x820; ret`)。
**FACT:该 getter 被 OBJGPU 构造簇写入 `obj+0x318`**:

```asm
0x01B9F216  auipc a4, 0xff8a3 ; addi a4,a4,-0x762   ; a4 = 0x01441AB4
0x01B9F21E  sd    a4, 0x318(s11)                    ; s11 = 被构造对象
0x01B9FAF2  sd    a4, 0x318(s11)
0x01BA10F2  sd    a4, 0x318(s11)
```
产物:`regwin_install_0x1b9f1f0.asm`、`regwin_getter_0x1441ab4.asm`。

### 1.3 aperture 就是"BAR0/PRI 窗口基址",且被真实读写(RMW 证据)

`fn 0x108C774`(产物 `regwin_fuse_rmw_0x108c774.asm`):

```asm
0x0108C77C c.lui a5,1 ; 0x0108C780 c.add a0,a5 ; 0x0108C782 ld a5,-0x468(a0)  ; aperture
0x0108C786 lui a1, 0x820 ; 0x0108C78C c.add a5,a1                             ; + 0x820000
0x0108C78E lw  a2, 0xf8(a5)        ; read  aperture+0x8200F8
0x0108C792 lw  a3, 0x13c(a5)       ; read  aperture+0x82013C
0x0108C7AA c.lw a4, 0x40(a5)  ; 0x0108C7AC ori a4,a4,1 ; 0x0108C7B0 c.sw a4,0x40(a5)  ; RMW aperture+0x820040
0x0108C7B2 ld  a5,-0x468(a0) ; 0x0108C7BA sw a4, 0x13c(a5)                     ; write aperture+0x82013C = 1
```

`fn 0x1848B38`(产物 `regwin_fuse_rd_0x1848b38.asm`)在同一 aperture 上读
`0x820084/0x8202FC/0x8203F4/0x820434/0x820584/0x82063C/0x82067C/0x8206F4/0x820C04`
以及 `0x82424C`,全部是 per-bit fuse/OPT 状态位(`c.andi 1`)。
`0x8200F8/0x8200DC/0x820040/0x82013C/0x820C04` 与驱动 GB202 RegHal domain 5 行同值。
**FACT:该指针是真寄存器窗口(读回 fuse 位、写回寄存器),不是 shadow buffer。**

### 1.4 第二个"基址选择器"载荷 `0xBF0000`(与本任务提示一致)

`fn 0x1541Bxx`(产物 `regwin_bf0000_0x1541b6a.asm`):

```asm
0x01541B72 lui a2, 0xbf0            ; a2 = 0xBF0000
0x01541B78 addiw a3, a3, -0x580     ; 0x1000-0x580 = 0xA80(由前面 HAL 调用得到)
0x01541B7C c.addw a5, a3 ; 0x01541B82 slliw a5,a5,2          ; a5 = 4*(idx+0xA80)
0x01541B86 ld  a4,-0x468(a4)       ; aperture = *(s1+0xB98)  ← 同一个 0xB98 字段!
0x01541B8A c.addw a5, a2 ; 0x01541B90 c.add a5, a4           ; aperture + 0xBF0000 + 4*idx
0x01541B96 c.lw a5, 0(a5)          ; 读 aperture + 0xBF2A00 + 4*idx
```
**FACT:同一个 aperture 上出现 `0x820000` 与 `0xBF0000` 两个"基址选择器"载荷**,
与 MODS/驱动侧出现过的 `0x820000`、`0xbf0000` 逐一对应。
(驱动 GB202 RegHal 表里 `id 0x10EF4000, domain 0, offset 0xBF0000` 确实存在,即
`0xBF0000` 是 PRI 空间里另一个寄存块基址;`0xBF2A00+4i` 在表内无对应行。)

### 1.5 RX BSS 里还有一个"窗口指针全局":VA `0x41904E0`

- `find_writer.py 0x41904e0` → **30,785 条互不相同的 `ld`** 从该 8 字节槽读指针;
  手工复核 7 处 auipc+ld(如 `0x100C462 auipc a5,0x3184; 0x100C466 ld a5,0x7e(a5)`
  与 `0x1BE4D74..78`)全部正确。
- 读出的指针随后被加 `0x111000` 量级的 PRI 偏移使用:
  `lui a4,0x111; addi a3,a4,0x52c; add a3,a5; lw a1,0(a3)`,并且紧跟
  `or 0x400000` / `sw` 回写(产物见 `README_regwin_rerun.md` 步骤 2)。
- 驱动 GB202 RegHal 表在 domain 0 确有 offset `0x110000`、`0x111000` 等行 ⇒
  该指针**也只能是**一个寄存器窗口基址。
- **`stores_range.py 0x4180000 0x41a0000` 显示该 BSS 区有 16,858 条 store,但
  `0x41904E0` 本身 0 命中**;`*_pkl`/`u32/u64` raw 搜索也找不到指向该地址的数据。
  ⇒ 它由运行期代码通过"取地址的 setter / memcpy"写入,静态不可解析。

### 1.6 `+0xB98` 的写入者不在本镜像

在 OBJGPU 构造簇(`0x1B9C000..0x1BA2000`)内对 `0xB98` 只有 **读**:
`0x01B9C030 / 0x01B9C0C2 / 0x01B9C154 / 0x01B9C1F8 / 0x01B9C240 / 0x01B9C342 /
0x01B9C3BC / 0x01B9C490` 全是 `ld x,-0x468(s3)` — 即"从**外部对象 s3** 拷进来"。
全镜像 5,769 处 `-0x468(...)` 中 store 共 75 处;其中只有 11 处的基址寄存器先被
`c.lui +0x1000` 调过(即 net `+0xB98` 那种编码),而**没有一处**是"把窗口基址写进
OBJGPU 的 0xB98"(其余 64 处基本是 `sp`/`s0` 栈槽)。⇒ **aperture 数值来自运行期
attach-args 结构**,不在镜像内。

公开 610 驱动源码(本地 `/usr/src/nvidia-610.57.04/src/nvidia/src/kernel/gpu_mgr/gpu_mgr.c:1972`)
给出同名语义:`pGpu->deviceMappings[0].gpuNvAddr = pAttachArg->regBaseAddr;`
⇒ GSP 端 `pGpu+0xB98` 对应的就是"设备映射数组第 0 项的寄存器窗口虚拟基址",
由 attach args 的 `regBaseAddr` 提供。**强 INFERENCE(字段语义),FACT(指针角色)。**

---

## 2. 逐问回答

### Q1. 找到"寄存器读/写原语"了吗?基址常量是什么?

**找到了原语,但没有"固定大基址常量"。** 基址常量不存在;存在的常量是**每域基址
选择器** `0x820000`(fuse 域)与 `0xBF0000`(另一 PRI 块)。

原语(镜像里的规范形式,5 处正校准 + 2 处直接 `lui 0x82x` 消费者):

```
aperture = *(u64*)(pGpu + 0xB98)                  ; 窗口 VA(运行期)
sel      = (*(u64*)(pGpu + 0x318))(pGpu)          ; = 0x820000
addr     = aperture + sel + offset                ; offset 例:0x40 / 0xF8 / 0x13C / 0x3814
*(u32*)addr  ← lw / sw
```
**置信度 A(HIGH)。** 依据:§1.1–1.3 的指令级证据 + 驱动 RegHal 表同值交叉验证 +
窗口读写回环(RMW)。

### Q2. 是"先写选择器寄存器再访问 aperture 窗口"吗?

**不是(在 GSP 侧软件层面)。** 没有任何"选择器寄存器 + 窗口"的写入-再访问序列:
选择器是一个**纯软件常量 getter**(`*(pObj+0x318)` → `lui a0,0x820; ret`),不是被写的
寄存器;窗口基址是 attach-args 提供的一个指针,也不需要先写任何寄存器。

**但硬件层面确实存在"per-device base"机制**:驱动侧同名量叫 `devicePriBase`
(GB100 已发布头 `NV_PTOP_DEVICE_INFO2_DEV_DEVICE_PRI_BASE`,以及
`OFFSET(entry)+0x10` 的 device-info 项),GSP 侧对应"由 `+0x318` getter 返回"。
本任务给出的两个"选择器载荷" `0x820000 / 0xBF0000` 就是这类**设备/域基址**,
在 §1.1/§1.4 里都用在同一个 `+0xB98` 窗口上。

- 选择器(软件)"寄存器"无地址,只有字段:`obj+0x318`(方法槽)、`obj+0xB98`(窗口指针)。
- 窗口地址:`*(pGpu+0xB98)`;使用顺序:`读 0xB98 → 调 0x318 → 相加 → lw/sw`。

### Q3. 是经 libos 系统调用/共享页吗?

**不是。** 我们找到的全部寄存器访问都是**内联的普通 load/store**:
`lw/sw` 直接作用在 `aperture + offset` 上,窗口之间没有任何 syscall/trap/共享页
中介指令(§1.1/§1.3/§1.4 的片段里,`jalr` 只用来调那个常量 getter)。
**映射的建立**(谁把 BAR0 映到 GSP VA)不在本镜像里:本镜像既没有 `+0xB98`
的写入者,也没有 `0x41904E0` 的写入者(§1.5/§1.6),窗口值来自 attach args。
⇒ **FACT:访问路径不经 libos 调用;UNKNOWN:映射建立者(镜像外)。**

### Q4. 要让"写 4 字节"落到 BAR0 `0x008200d0`,GSP 侧应写哪个 VA?

驱动 GB202 RegHal 表确认 `0x008200d0` = **domain 5(fuse)offset `0xd0`**
(`id 0x10E0C000 / 0x10E10000`,属 floorsweep/OPT 掩码族;同族 `0xdc`/`0xf8`/`0x3814`/`0xc04`
本镜像里都有消费者)。

**排序后的候选:**

| # | GSP 侧地址 | 依据 | 置信度 | 风险 |
|---|---|---|---|---|
| 1 | **`*(u64*)(pGpu + 0xB98) + 0x8200d0`** | 5 个正校准消费者全用同一公式 `aperture + 0x820000 + K`;`+0xB98` = `deviceMappings[0].gpuNvAddr`;§1.1/§1.3 | **A(HIGH)** | `pGpu` 是堆对象(崩溃现场落在 `0x0fe4xxxxx..0x0febxxxxx`),窗口值运行期才存在,**静态拿不到数值**;必须先取到 `pGpu` |
| 2 | `*(u64*)0x41904E0 + 0x8200d0` | RX BSS 全局,30,785 处读点,配 `0x111xxx` PRI 偏移写回(§1.5) | **B(MED)** | 只证明它是**某个**寄存器窗口基址;已见用途全是 domain-0 偏移,不能证明与候选 1 相等;若它对应另一张映射(另一 mapping index/设备)则写到错误 aperture |
| 3 | `devMap[fuseDeviceIndex].gpuNvAddr + 0xd0` | 若 GSP 为 fuse 设备单独建了一张映射,则 `devicePriBase` 已含在基址内 | **C(LOW)** | 本镜像 5 处 fuse 读全部写成 `devMap[0] + 0x820000`,**没有**见过第 3 种形式;仅作理论候选 |
| — | ~~`*(pGpu+0xB98) + 0xd0`~~ | 会被误判的写法 | **已排除** | 5 个消费者自己加上 getter 的 `0x820000`,证明 aperture 是"设备 PRI 偏移 0"的基址,**不能再省** 0x820000 |

**负结果(必须明写):** 对 RX 段枚举 `lui rd,imm` 且 `imm<<12 ∈ [0x820000,0x824000]`,
得 14 个点(`ds_work/gsp_mmio_window_evidence.py` §3),**没有任何一处使用 offset `0xd0`**;
亦无 `0x8200d0` 的完整 32/64-bit 字面量。即**镜像里没有现成的"往 0x8200d0 写"的代码**,
地址只能由候选 1 的指针在运行期合成。

---

## 3. 置信度汇总

| 结论 | 级别 |
|---|---|
| 原语 = `*(*(pObj+0xB98)) + sel + off`,32-bit `lw/sw` | **FACT / A** |
| `obj+0x318` = 常量 getter 槽,GB202 安装 `0x1441AB4`(返回 `0x820000`) | **FACT / A** |
| `obj+0xB98` = 可直接解引用的 PRI/BAR0 窗口虚拟基址 | **FACT(角色)/ A**;字段正式名 = `deviceMappings[0].gpuNvAddr` = **强 INFERENCE** |
| GSP 侧无"选择器寄存器 + 窗口"序列;无 libos 中转 | **FACT(限本镜像线性编码域)/ A** |
| 两个基址选择器载荷 `0x820000` / `0xBF0000` 同属本机制 | **FACT / A** |
| BSS `0x41904E0` 是另一个寄存器窗口指针 | **FACT(角色)/ A**;是否等于 §1.1 的 aperture = **UNKNOWN** |
| 窗口数值 / 映射建立者 | **UNKNOWN(镜像外)** |

## 4. 不确定项、负结果与风险

1. **窗口数值不可静态取得**(最重要)。`+0xB98` 只被读不被写;`0x41904E0` 无任何 store、
   也无数据引用。任何"具体 VA"都必须先取得 `pGpu` 指针(或该全局的运行时值)。
2. **文件截断**:`rx_full.bin` 比 PH0 `filesz` 少 `0x4000` 字节(VA `0x1E93000..0x1E97000`
   未包含)。最后 16 KB 未分析(该区间是字符串/数据区,不影响上述代码点)。
3. **线性反汇编口径**:PH0 是 `R+X` 单一段,`.rodata` 与代码混在一起,所有整段扫描
   (含 §1.5 的 30,785 计数)都可能有数据误码;但 §1.1–1.4 的每个点都做了逐条手工复核。
4. **aperture 的"零基点"前提**:本文断言 `aperture` 是"设备 PRI 偏移 0"的基址,依据是
   5 个消费者自己加 `0x820000`。若某 chip 装的是**另一个**常量 getter(例如返回
   `0xBF0000`),则公式不变、常量变。
5. **offset 归域不一致**:消费者用的 `0x3F4`/`0x74C` 在驱动 GB202 表里只出现在
   **domain 30**;domain 5 里没有。说明 GSP 侧"一个 getter 对所有 fuse 类 offset"
   与驱动侧"按 domain 分基址"并不完全等价 ⇒ 若目标寄存器属 domain 30,
   正确基址可能不是 `0x820000`。**这是候选 1 唯一的实质性风险。**
6. **`0xBF2A00+4i`** 在驱动 GB202 表内无对应行,`0xBF0000` 这一支的具体语义未闭合。
7. **未做**任何运行期验证(不碰 GPU/驱动/VM),因此所有 VA 都是"应写到"的推导,
   不是实测地址。

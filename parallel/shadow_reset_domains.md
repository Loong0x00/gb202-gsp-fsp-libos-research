# GB20x/GB202 L2 shadow 的 reset-domain 静态证据矩阵

日期：2026-07-21
状态：final；严格静态、只读、有限窗口

## 范围、artifact 与结论口径

本轮只追四组状态在 reset 前后的可见生命周期：

- software-override latch：`0x820040.bit0`；
- raw OPT/shadow L2 disable：`0x8234e0 + 4*FBP`；
- coarse LTC/ROP-L2 status：`0x820d70 + 4*FBP`；
- current/effective LTS disable：`0x822900 + 4*FBP`。

只读取了：

- `mods_audit/static/extracted_inner/mods` 的既有已知函数小窗口；
- `/tmp/gsp_inner_19f040_a.elf` 的既有已知 GSP 小窗口和已归档 constructor
  replay 结果；
- `/usr/src/nvidia-610.43.03/src` 中与 GB202、SBR、FSP boot 和公开 reset type
  直接有关的少量源码；
- 项目中已有的 `parallel/shadow_reset_lifecycle.md`、
  `parallel/sbr_shadow_scope.md`、`parallel/tmux_gsp_l2_repair.md`、
  `parallel/gb202_getfsinfo_support.md` 等报告。

没有运行 MODS 或固件，没有打开 `/dev/nvidia*`，没有访问 GPU、PCI config、
BAR/MMIO、debugfs 或 live driver control，也没有 reset、rebind、模块、电源、VBIOS
或其他硬件操作。没有做 whole-file 反编译或建立分析数据库；新增反汇编只限已知
地址的小窗口。

本文严格区分：

- **FACT**：当前静态文件或明确地址窗口直接支持；
- **INFERENCE**：最窄的软件设计解释，不是硅级保证；
- **UNKNOWN**：当前材料不能决定，尤其不能被 reset 名称代替。

## 直接答案

1. **没有找到 GB202 的四寄存器 reset-domain 表。** 当前公开头、OpenRM、MODS
   RegHal 表和已审计 GSP 小窗口都没有说明 hot/SBR、boot、fuse、base 分别对四组
   状态执行 retain、clear、sample、reload 还是 recompute。
2. **正常 direct-shadow success 强烈预期 shadow 跨 reset 有效，但方式未知。**
   host 在 reset 前尝试置 latch、写并回读 raw，随后不 clear、不 replay，也不把
   plan 传给 reset/reinit。若所有 reset 都在消费之前无条件丢失这些信息，正常
   success path 就没有可见机制达到目的。因此“保持、被 reset 边沿采样，或由隐藏
   状态重建”三者至少应有一种发生；静态 host 代码不能区分它们。
3. **只有显式 resense 给出 target-specific 的撤销意图。** 它在 reset 前尝试发
   `0x404f0000`，即 latch-clear coded operation；但 coupling 请求和 clear 返回都
   不是 fail-closed，且 pre-silicon 分支会跳过 reset。它不清、不恢复 raw，也不
   比较 post-reset status/effective。
4. **fuse reset 有 physical-resense 的软件语义，仍不是硅级证明。** 当前 MODS
   把 resense 与 state 6 配对，物理 fuseblow 协调器也打印
   `Performing a Fuse Resense after Fsp Fuseblow`。hot、boot、base 是否同样重采实体
   fuse 没有证明；尤其 `BASE` 是独立 reset type，不能因名字或强度把它自动等同
   `cold reset`。
5. **OpenRM 的 GB202 SBR host 实现不碰四组地址。** GB202 选择 GH100 SBR HAL，
   后者直接复用 GM107 的 bridge-bit 实现：只切换上游桥 Bridge Control `0x40`、
   等待，再轮询配置空间恢复。另有 GB202 源码证明 chip reset 会启动 FSP；它支持
   “重型 reset 跨过固件重建边界”的设计解释，但公开调用链没有逐 type 证明每次
   SBR 都经过完全相同的 FSP 阶段，更不证明 FSP 对四组状态做了什么。
6. **`0x820d70` 和 `0x822900` 目前只闭合为 GSP 可读的派生/有效视图。** 当前
   GB202 FB getter 会读取它们，但 normal writer 的 success tail 不调用这些 getter，
   不比较预期 mask，也没有 host 显式写入这两组状态。将它们描述为 reset 后
   “重新形成”是有力设计推断，不是已见 consumer 的 bit-level 证明。
7. **目前没有任何一种 reset 可被称为已证明的 rollback。** 这也包括直接 SBR、
   本地模块卸载/重载脚本、普通 fuse reset、base reset 与冷断电；后三者最多有
   名称或旁路日志线索，没有本四寄存器的可验证恢复合同。

## 1. 四组状态不是同一层

### 1.1 FACT：地址、访问角色与 getter 分离

GB202 RegHal 离线解码和当前 GSP constructor replay 支持以下分层：

| 状态 | 地址 | 当前静态角色 | 已见 host/GSP 动作 |
|---|---:|---|---|
| override latch | `0x820040.bit0` | 选择 software override 的 latch；access PLM 是独立 `0x8200f8` | MODS 用 `0x404f0001/0` 尝试 set/clear |
| raw OPT/shadow | `0x8234e0 + 4*FBP`，FBP 0..7 | 每 FBP `[7:0]` raw plan 目标；access PLM 为 `0x8200dc` | reset 前 write + immediate readback |
| coarse status | `0x820d70 + 4*FBP` | GSP 的 coarse LTC/ROP-L2 status 读出视图 | GB202 `FB +0x9b0 = 0x0132ae68` 读取后取反 |
| current/effective | `0x822900 + 4*FBP` | GSP/RM 的 flattened current/effective LTS-disable 视图 | GB202 `FB +0x9c0 = 0x0132ef40` 读取、裁宽、取反 |

constructor replay 的持久化结果见：

- `parallel/gsp_fb_vtable_replay.results.txt`：GB202 index 65 的
  `+0x9b0 = 0x0132ae68`、`+0x9c0 = 0x0132ef40`；
- `parallel/gsp_fb_vtable_replay.py`：只解释 bounded constructor subset，未执行
  固件；
- GSP artifact hash/provenance 见 `parallel/GSP_ARTIFACT_PROVENANCE.md`。

本轮重新查看的两个 getter 小窗口仍只显示读路径：

- `0x0132ae68..0x0132aebe` 经 Fuse/RegHal aperture 取出 coarse word 并取反；
- `0x0132ef40..0x0132f010` 先取得拓扑有效位宽，再读取目标 word、裁宽并取反。

它们证明“GSP 能观察 status/effective”，不证明 reset 内何时产生这些值，也不把
`physical/local` 的 RM 坐标术语升级成“直接读取实体 OTP”。

### 1.2 FACT：RegHal 表不含 reset-domain 描述

`gb202_reghal_offline.py` 解码的 row 只提供 RegHal ID、实例 index、domain、offset、
field bits、constant value 与 access-PLM metadata。它能区分 latch/raw/effective
地址与字段宽度，但没有每个 register 的 hot/boot/fuse/base reset value、retention
domain、sense source 或 reset priority 字段。

对公开 610 Blackwell/GB202 headers 和 OpenRM 的精确地址/名称检索也没有找到
`0x820040`、`0x8234e0`、`0x822900`、`0x820d70` 或对应 L2 shadow 的公开寄存器
定义。`parallel/public_fusebase_callers.md` 进一步证明公开源码中已枚举的七个
`gpuGetPrimaryFuseBaseAddr` 直接 caller 都不访问 latch/PLM 目标；这个负结果仅限
公开 host C 代码，不能覆盖闭源 GSP/FSP/硬件状态机。

## 2. 正常 direct-shadow 的 reset 前后合同

### 2.1 FACT：reset 前写入顺序

MODS 570.151 的 bounded x86-64 窗口 `0x1515ea0..0x15160df` 显示：

```text
security level > 3
  -> handler +0x78, constant 0x404f0001       # 尝试 latch := 1
  -> for each plan node:
       handler +0xb8(raw offset, raw value)   # write return 未消费
       handler +0xc0(raw offset)              # immediate readback
       ordinary mismatch -> aggregate 0x79
       0xbadf510c -> 只日志，未置 aggregate error
```

这里能直接证明的是 host request/order。latch-set call 的返回没有检查；raw write
本身的返回也没有消费。因此即使在 reset 前，success status 的保证也弱于“每项
已被硬件可靠接受”。

### 2.2 FACT：reset callback 不携带 plan

正常 post-program 入口 `0x1515770..0x1515786` 只把 accessor 内的 handler 取出，
给出整数 5 并跳到 `+0x100`；thunk `0x151ad50..0x151ad5d` 又只转发对象到
`GpuSubdevice +0x1b0`，丢弃该整数。后续 `0xdff7b0` 自己构造 request `2` 的小
descriptor，交给 GB202 mapper `+0x1070`，再把该 descriptor 交给 reset dispatcher。

因此 reset/reinit 没有收到：

- raw plan tree；
- 每个 FBP 的期望 `[7:0]` 值；
- pre-reset latch 值；
- 期望 `0x820d70` 或 `0x822900` mask。

一次成功 reset 后，`0x127b000` 只在 recovery-mode property 为真时再发第二次
reset；这个 fallback 同样没有 plan/effective compare。

### 2.3 FACT：reset 类型继承既有 coupling

`0xdff7b0` 的 request-2 jump-table entry 落到 mapper
`0x126b430..0x126b4a6`。mapper 在前序窗口读取 boot、fuse、base coupling，再按：

```text
base == 1                  -> MODS state 7, base
else fuse == 1             -> MODS state 6, fuse
else boot == 1             -> MODS state 5, boot
else                       -> MODS state 3, hot
```

request-2 分支把 descriptor 的“需要补设 coupling”byte 写为 0。因此 normal
direct-shadow success 是“沿用当时已有 coupling 后 reset”，不是为这次 shadow
transaction 固定选择 boot/fuse/base。

`gpuargs.js:755-762` 明确把 `HotReset` 描述为 secondary-bus reset，并把
`BootReset`、`FuseReset`、`BaseReset` 分成独立命令。这里的 MODS state 数字不能
与公开 BIF reset type 数字混用。

### 2.4 INFERENCE：normal path 预期 retain 或 consume，二者不可区分

reset 后没有 raw replay，也没有直接写 effective。由此得到的最窄强推断是：

```text
(latch, raw shadow, physical fuse, other policy)
             -- reset/FSP/GFW/hardware --> status/effective
```

但至少三种底层实现都与当前 host 行为相容：

1. latch/raw 寄存器物理跨 reset 保持；
2. reset 边沿先把它们采样到另一 always-on 状态，原寄存器随后可清；
3. FSP/GFW 从不可见持久/安全状态重新构造它们或其 downstream rollup。

所以可说“原厂流程预期 shadow 穿过 reset 边界后仍影响拓扑”，不能说
“`0x820040` 和 `0x8234e0` 已证明在某种 reset 下 retention”。

## 3. 显式 resense 的目标与限制

### 3.1 FACT：target-specific 顺序是 coupling attempt -> latch-clear attempt

`GB20xPrepareResense` 的 bounded 窗口 `0x1516e20..0x1516f91` 显示：

```text
handler +0xf8(state 6)          # 尝试 fuse-reset coupling
  nonzero -> log, but continue
handler +0x78(0x404f0000)       # 尝试 latch := 0
  return immediately overwritten; no latch readback
if preparation status == 0:
  if non-pre-silicon:
      handler +0x100(state 6)   # 实际仍由 coupling mapper 选 reset
  else:
      log "Skipping fuse reset on Pre Silicon Platforms!"
```

因此：

- **FACT：** resense 与 normal post-program 是不同 vtable slot/path；normal success
  不发 `0x404f0000`；
- **FACT：** coupling 失败不阻止 clear request；clear return 不参与 final status；
- **FACT：** 传给 reset callback 的整数 6 又被 thunk 丢弃；只有 final mapper
  观察到 `base=0,fuse=1` 才选择 state 6；
- **FACT：** resense 不保存、清零或恢复 `0x8234e0` raw plan，也不读取/比较
  `0x820d70` 或 `0x822900`；
- **UNKNOWN：** latch 是否真清、最终 reset 是否确为 fuse、raw 是否仍留在 inactive
  shadow storage、status/effective 是否回到实体 fuse 拓扑。

### 3.2 INFERENCE：clear latch 比清 raw 更符合 source-select 语义

resense 只尝试 clear latch 而不清 raw，最自洽的设计解释是：raw shadow 可以继续
留在存储中，但 latch=0 时不再作为有效来源；随后 reset/resense 重新形成
status/effective。这个解释能说明为何没有 raw rollback write，但真正 source mux、
优先级和保持域仍在不可见硬件/FSP 内。

### 3.3 FACT/INFERENCE：fuse reset 的 physical-resense 证据等级

当前可见证据为：

- resense host path 名义上请求 state 6/fuse coupling；
- physical FSP fuseblow 协调器 mode 2 的原始字符串为
  `Performing a Fuse Resense after Fsp Fuseblow`；
- 物理 fusing 状态机另有字符串：
  `Skipping the reset after fusing. New fuse values may not be reflected until a fuse / cold reset`。

这些是 **FACT（软件命名和工作流）**，强烈支持 fuse reset 是实体 fuse 重新反映的
边界；“某次零售 GB202 reset 确已重采并采用 OTP”仍是 **UNKNOWN**。该物理-fusing
语义也不能移植成 normal direct-shadow state-6 的 rollback：normal path 没有先
clear latch。

## 4. hot/SBR 的公开 GB202 实现

### 4.1 FACT：GB202 继承 GH100 -> GM107 SBR body

公开 610 generated HAL 先把 GB202 识别为 chip index 65
（`g_chips2halspec_nvoc.c:129-132`）。该 index 不命中
`g_kernel_bif_nvoc.c:1493-1505` 的 embedded 或 TU/GA/AD 分支，故选择
`kbifDoSecondaryBusHotReset_GH100`。GH100 body 在
`kernel_bif_gh100.c:1805-1812` 直接返回
`kbifDoSecondaryBusHotReset_GM107(...)`。

最终公开 body `kernel_bif_gm107.c:1557-1614` 只：

1. 打开上游桥 PCI handle；
2. 读 Bridge Control；
3. set bit `0x40`；
4. 等至少 1 ms；
5. clear bit `0x40`；
6. 等至少 100 ms；
7. 等待 GPU config access 恢复。

该函数没有 GPU BAR0/fuse-aperture read/write，没有 target address，也没有 latch
clear、raw save/restore、fuse-resense 或 L2 topology compare。

### 4.2 FACT：chip reset 会重新启动 FSP；与每种 reset 的精确调用关系未公开

GB202 OpenRM 明确写道 `Bootfsm triggers FSP execution out of chip reset`；
`kfspWaitForSecureBoot_GB202` 轮询 FSP boot-complete scratch
（`kern_fsp_gb202.c:58-85`）。GB202 BIF 的 BAR-firewall 恢复函数也说 FSP 在 chip
reset 后运行并在 CRS release 附近 disengage firewall
（`kernel_bif_gb202.c:289-313`）。

这直接证明 GB202 的 **chip-reset boot model** 包含 FSP 启动边界。它与 SBR
实现同处 reset/recovery 体系，支持 SBR 后可能发生 FSP 重建的解释；但当前公开
小窗口没有给出“每个 SBR/boot/fuse/base type 必定调用该 wait”的完整调用图，
因此这层连接仍须列为 **INFERENCE**。无论如何，它没有证明：

- FSP 会重新读取实体 fuse；
- FSP 会 clear 或 retain `0x820040`；
- FSP 会保存/replay `0x8234e0`；
- FSP boot-complete 代表 `0x820d70/0x822900` 与 shadow plan 一致。

### 4.3 INFERENCE：MODS hot 与裸 SBR同类，但 lifecycle 不等价

MODS 自己把 `HotReset` 定义为 SBR，所以在 reset mechanism 层它与公开桥位操作
同类。MODS 的 managed reset/reinit 还包含配置保存、设备状态卸载、GFW/FSP 等待
和 RM 重建；本地 shell 脚本则先卸载模块再直接切桥位。两者不能因都叫 SBR 就
互相提供 shadow-retention 或 rollback 证明。

## 5. boot/fuse/base 的 GSP reset endpoint 只证明 taxonomy

### 5.1 FACT：公开 BIF type 是不同枚举

`ctrl0080bif.h:37-76` 独立定义：

```text
type 2 = SBR
type 4 = BOOT_DEVICE_FUSE
type 5 = BOOT_DEVICE
type 8 = BASE
```

并明确指出 Blackwell 不支持 `_FUNDAMENTAL`，应使用
`BOOT_DEVICE_FUSE` 或 `BOOT_DEVICE`。这个接口证明 type 分离，不给出 reset
层级、包含关系或目标寄存器 domain。

### 5.2 FACT：当前 GSP outer handler 有独立 4/5/8 分支

当前 GSP method descriptor 把 `0x01066260` 绑定到
`NV0080_CTRL_CMD_BIF_RESET (0x800102)`。bounded window 中：

- `0x0106653c` 以 selector 4 调对象 `+0x5e8`；
- `0x0106656a` 以 selector 5 调对象 `+0x5e8`；
- `0x0106661a` 以 selector 8 调对象 `+0x5e8`。

这些分支可与公开名称对应为 boot-device-fuse、boot-device、base。outer handler
的小窗口没有直接编码本报告四个 target register；不过它包含多条 virtual/far
call，所以这个局部负结果不能排除 callee、FSP、ROM 或硬件状态机的隐式动作。

### 5.3 FACT：已识别的 LTS-repair reset hook 在 GB202 上不提供 rollup 证据

既有 bounded object/constructor audit 把上述 `+0x5e8` 链与 `OBJINFOROM` 的 LTS
repair reset hook 关联。GB202 index 65 虽安装公共 `+0x5e8` handler，但其内层
`+0x188` repair slot 解析到 `0x01975824` 的 zero-return success stub；marking 与
commit 相关槽也为 stub。证据见：

- `parallel/gsp_inforom_vtable_replay.results.txt`；
- `parallel/tmux_gsp_l2_repair.md:34-63`。

因此，boot/fuse/base reset endpoint 中存在 LTS-related hook，不能被当作 GB202
会在软件内修复或重写 active LTS mask 的证据。raw-to-effective 仍可能在另一
FSP/GFW/hardware consumer 中完成；该 consumer 当前没有恢复。

后续 bounded 数据流审计在固定 GSP 中确认了 A/B 的独立读取 wrapper；原先
归为 caller-driven “B 类 setter”的 `0x15d3a98` 已正向识别为 GH100
Ioctrl/MINION NVLink EOM sender，GB202 对应槽位为 stub，故应从 B writer
候选删除。仍没有找到 A-derived B writer/copy/recompute。因此上述 consumer
候选仍须保持为 hardware sense/rollup、FSP/GFW 或隐藏 replay 三类并列 UNKNOWN，
不能因可见软件缺少 copier 就升级成“硬件必然自动传播”。见
`parallel/raw_effective_propagation.md`。

## 6. reset/action × register 证据矩阵

表中的“无显式动作”只限定已审计 host/GSP 路径，不表示硅中没有隐式动作。

| reset/action | `0x820040` latch | `0x8234e0` raw | `0x820d70` status | `0x822900` effective | 可下结论 |
|---|---|---|---|---|---|
| normal state 3 hot / managed SBR | reset 前尝试 set=1；不 clear、不 post-read | reset 前 write/readback；不 replay、不 post-read | 不写、不 compare | 不写、不 compare | **FACT：host 动作；INFERENCE：shadow 预期继续生效；硅级保持 UNKNOWN** |
| normal state 5 boot | 同上 | 同上 | 同上 | 同上 | 独立 reset type 已证；逐寄存器行为 UNKNOWN |
| normal state 6 fuse | 同上；normal path 不 clear | 同上 | 同上 | 同上 | fuse-resense 语义存在，但 latch=1 时不是 rollback；实际行为 UNKNOWN |
| normal state 7 base | 同上 | 同上 | 同上 | 同上 | 独立 reset type 已证；不能等同 cold/resense；实际行为 UNKNOWN |
| explicit resense | reset 前尝试 clear=0；返回未验 | 不清、不恢复、不 replay | 不写、不 compare | 不写、不 compare | **INFERENCE：意图回到实体 fuse source；执行成功与最终值 UNKNOWN** |
| OpenRM/raw SBR | host SBR body 无显式访问 | 无显式访问 | 无显式访问 | 无显式访问 | bridge reset 已证；GB202 chip-reset/FSP boot 模型另有证据，但 exact SBR-to-FSP chain 与所有 target lifecycle UNKNOWN |
| FSP boot completion | 只轮询 boot scratch | 无 plan replay | 无 target compare | 无 target compare | 证明 firmware boot 边界，不证明 topology adoption |
| physical fuseblow mode-2 resense | 该 mode 的名称本身不证明 latch clear，也没有 latch readback | 无本项目 raw restore 证明 | 无 post-read compare | 无 post-read compare | physical-resense 名称/工作流 FACT；每寄存器效果 UNKNOWN |

## 7. base reset 与其他 FMMC 状态不能混同

物理 fuse-binary 前置检查有日志要求用 `-base_reset` 清
`FMMC_SOFT_BURN_ENABLE` 或 `FMMC_MIRROR_ENABLE`。这确实证明 MODS 预期 base
reset 会影响某些 FMMC mode state，但这些字段不是：

- `0x820040.bit0` override latch；
- L2 raw `0x8234e0`；
- coarse status `0x820d70`；
- effective LTS mask `0x822900`。

所以该旁路证据不能升级成“base reset 会清 L2 shadow”。同理，base reset 的
“强度”或名称也不能替代 cold power cycle 的定义。

## 8. 软件设计推断与硅级保证的最终边界

### 8.1 可以合理采用的设计模型

当前最自洽的软件模型是：

```text
physical fuse/OTP ----+
                      |
raw OPT shadow -------+--> source select / rollup --> 0x820d70 / 0x822900
                      ^
0x820040 latch --------+
                      |
other SW/repair policy +
```

normal writer 尝试 latch=1 并写 raw，然后 reset；resense 尝试 latch=0 后再 reset。
这很像 source-select + rollup，而不是 host 直接把 effective register 当配置寄存器
写入。

### 8.2 当前绝不能写成事实的内容

以下全部仍是 **UNKNOWN**：

1. latch/raw 分别属于 always-on、fuse、boot、base 还是其他 retention island；
2. hot/SBR、boot、fuse、base 对 latch/raw 的 clear/retain 时点；
3. reset 先 sample raw 再 clear，还是先 clear 再从 hidden state rebuild；
4. `0x820d70` 与 `0x822900` 是 reset retention register，还是每次由硬件/FSP
   recompute；
5. raw bit 到 status/effective bit 的逐位公式、优先级和 failure mode；
6. normal state-6 在 latch=1 时 physical fuse 与 shadow 的覆盖顺序；
7. explicit resense 是否在任一零售 GB202 上 fail-closed；当前 host 明确不是；
8. cold power cycle、base reset、fuse reset或 SBR 中哪一种能在 partial-write 后
   可靠恢复实体-fuse topology；
9. reset/reinit 返回 0 是否代表 L2 topology 自洽。当前只证明没有与请求 plan 的
   post-reset equality check；
10. 被重新启用的单元是否物理健康。reset-domain 证据与健康证据是两件事。

## 9. 对后续安全研究的直接含义

1. 不能把任何 reset 预先登记为 rollback。尤其不能把本地 SBR 恢复脚本当作
   shadow undo；它不保存 raw、不 clear latch、不 resense，也不验证 effective。
2. 即便未来在完全隔离条件下做 pre/post topology query，`GET_FS_INFO/LTS_MASK`
   只能观察 `0x822900` effective view，不能证明 latch/raw 的实际值、来源或健康。
3. 若未来需要区分“raw 保持”与“被 reset 消费”，至少需要三个独立观察层：
   pre-reset raw/latch、post-reset raw/latch、post-reset effective/status；当前公开
   production RM 只静态闭合了 effective/status 的候选 getter，没有 raw/latch 的
   普通 client GET。
4. 在没有隔离显示、经过验证的 recovery 和用户另行明确授权之前，本报告不给出
   任何 live writer/reset 实验依据。

## 最小可引用结论

> GB20x MODS 的 normal direct-shadow host 流程在 reset 前尝试置
> `0x820040.bit0`、写/回读 `0x8234e0+4*FBP`，随后沿用既有 coupling 选择
> hot/boot/fuse/base reset；reset/reinit 不携带 raw plan，之后也不比较
> `0x820d70` 或 `0x822900`。这强烈表明 NVIDIA 预期 shadow 跨 reset 保持、被
> reset 边沿采样或从隐藏状态重建后继续影响拓扑，但三种实现当前不可区分，因而
> 不是任何 reset 的硅级 retention 保证。显式 resense 的 target-specific 语义是
> “尝试 fuse coupling、尝试 clear latch、再条件 reset”，且不清 raw、不做
> post-reset effective 验收。公开 GB202 SBR host body 只切桥位并等待；另有源码
> 证明 chip reset 会启动 FSP，但没有逐 reset type 的完整连接或 fuse-sampling
> 证明。当前没有 hot/SBR、
> boot、fuse、base 中任何一种能作为已验证的 shadow rollback。

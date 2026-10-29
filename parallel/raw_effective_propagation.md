# GB202 raw OPT L2 mask 到 effective LTS mask 的传播审计

日期：2026-07-21
状态：final；严格离线、只读、资源受控的静态审计

## 范围与结论口径

本报告只回答一个问题：GB202 的 raw OPT/shadow L2 disable 数组
`A = 0x8234e0 + 4*FBP` 在 reset/reinit 前后，是否能在当前可读软件中追到
current/effective LTS-disable 数组 `B = 0x822900 + 4*FBP`，以及谁是 writer、
consumer，传播最早/最晚可能发生在哪个初始化阶段。

使用的固定材料为：

- MODS 570.151 的既有 bounded 静态报告与已确认小窗口；
- 610.43.03 GSP inner ELF `/tmp/gsp_inner_19f040_a.elf`，82,577,496 bytes，
  SHA-256 `bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`；
- `/usr/src/nvidia-610.43.03/src` 的公开 OpenRM 源码；
- `parallel/shadow_reset_domains.md`、`parallel/shadow_reset_lifecycle.md`、
  `parallel/gb202_getfsinfo_support.md`、`parallel/l2_mask_granularity.md`、
  `parallel/gb202_610_arch.md` 与 `parallel/fsp_task2_consumer_followup.md` 的
  已审计结论。

GSP 新增检查只覆盖第一个 executable `PT_LOAD`，VA
`0x01000000..0x01e97000`。先按 A/B 的 word-offset 构造方式筛选候选
`LUI/C.LUI`，再对候选做很小的 RISC-V/RVC 窗口反汇编；没有 whole-segment
Capstone、反编译数据库或固件执行。没有运行 MODS，没有打开 `/dev/nvidia*`，没有
GPU/MMIO/PCI config/reset/rebind/模块/电源写操作。

下文严格使用：

- **FACT**：静态文件、已绑定 vtable 或明确指令数据流直接支持；
- **INFERENCE**：最窄且与全部事实相容的解释；
- **UNKNOWN**：当前 artifact 不足以决定。

## 直接答案

1. **FACT：host writer 已定位。** MODS direct-shadow 流程在 reset 前尝试置
   `0x820040.bit0`，逐 FBP 写 A 并立即回读 A；随后只提交 reset/reinit 请求，
   不把 raw plan 传给 reset callback，也不在 reset 后 replay A。
2. **FACT：GB202 的 GSP effective consumer 已定位。** FB vtable
   `+0x9c0 = 0x0132ef40` 读取 B，按当前拓扑位宽裁剪并取反，返回 LTS enable
   mask。它消费的是已经形成的 B，不读取 A，也不触发传播。
3. **FACT（有限负结果）：没有在可读 GSP/OpenRM/MODS success path 中找到
   A-derived B writer。** 固定 GSP 内有 A read wrappers、B read wrappers 和诊断
   reader；此前误判为“能按调用者参数访问 B 类地址”的 `0x015d3a98` 已正向识别
   为 GH100-only Ioctrl/MINION NVLink EOM command sender，GB202 对应 HAL 槽为
   stub，故它不属于 B writer 候选。
4. **UNKNOWN：真正传播者和精确时刻仍未定位。** 当前材料与 hardware
   sense/source-select/rollup、FSP/GFW 在 reset/chip boot 中重建、或另一份隐藏状态
   replay 都相容。不能把“可读软件中没发现 copier”升级成“已证明硬件自动传播”。
5. **因此还不能据此写出可靠的 runtime 解锁器。** 缺失的不是 B 的地址，而是
   权限合同、A 被采样的 reset 边沿、A→B 的逐 bit 公式、失败处理，以及 post-reset
   adoption 验证。单独直接写 A 或猜写 B 都没有从本审计获得安全依据。

## 1. 四个不同层次的状态

| 层次 | 地址 | 当前可证角色 | 当前可证 actor |
|---|---:|---|---|
| software-override latch | `0x820040.bit0` | 选择/请求 software override | MODS 在 direct-shadow 前尝试 set，resense 路径尝试 clear |
| raw OPT/shadow A | `0x8234e0 + 4*FBP`，FBP 0..7 | 每 FBP `[7:0]` raw plan 存储/输入 | MODS 写并即时回读；GSP 有 read wrappers |
| coarse status | `0x820d70 + 4*FBP` | LTC/ROP-L2 粗粒度派生视图 | GB202 GSP `+0x9b0 = 0x0132ae68` 读取 |
| current/effective B | `0x822900 + 4*FBP` | flatten 后的 current/effective LTS-disable 视图 | GB202 GSP `+0x9c0 = 0x0132ef40` 读取 |

**FACT。** A 的 RegHal read/write ID 分别为 `0x1087c000` 和
`0x2087c000.[7:0]`；B 的 read ID 为 `0x10d64000`。RegHal 记录给出地址、字段和
access-PLM metadata，但不含 reset retention、sense source 或 A→B rollup 公式。

这里必须避免两个常见混淆：

- A 的 readback 只证明 reset 前 raw slot 可见，不证明 B 已采用；
- B 的 getter 只证明 reset/reinit 后可以观察 effective view，不证明它来自 A。

## 2. Host writer 与 reset 交接

### 2.1 FACT：A 在 reset 前写入并回读

既有 MODS bounded flow `0x1515ea0..0x15160df` 的顺序为：

```text
security level > 3
  -> handler +0x78(0x404f0001)        # 尝试 latch := 1
  -> 对每个 plan node：
       handler +0xb8(raw offset, value)
       handler +0xc0(raw offset)      # immediate A readback
       compare
  -> post-program reset/reinit
```

latch-set 返回没有 fail-closed 检查，raw write 的返回本身也不被消费；ordinary
readback mismatch 才汇总错误。因此 host success 的强度小于“硬件已可靠接受且将采用
全部项”。

### 2.2 FACT：reset callback 没有拿到 A plan

正常 post-program path 最终只构造 request `2` 的 reset descriptor。该 descriptor
不包含：

- 八个 A word 或原始 plan tree；
- latch 的期望状态；
- coarse status/B 的期望结果；
- reset 后 compare/replay callback。

request 2 沿用已经存在的 coupling，mapper 按 base > fuse > boot > hot 选择 reset。
success tail 也不调用 GB202 的 B getter。因此“reset 返回成功”不等于“A 已传播到
B”。

**INFERENCE。** 若原厂流程确实生效，则 A/latch 必须在某个 lower-level 边界被
retain、sample 或由隐藏状态重建；host reset callback 本身没有足够信息重新计算 B。

## 3. 固定 GSP 中对 A 的可见使用

### 3.1 FACT：`0x013d3520` 是直接 A read wrapper

`0x013d352a..0x013d3554` 的关键算术为：

```text
0x1000 - 0x2c8 = 0x0d38
offset = (0x0d38 + index) << 2
call object +0x100 read callback
return loaded word/status
```

内部 Fuse/RegHal aperture 的 `0x0d38*4 = 0x34e0`，对应 BAR0
`0x8234e0 + 4*index`。该函数读 A；窗口中没有 B 地址构造或 store-to-B。

### 3.2 FACT：还有 A 的动态 field/read plumbing

- `0x013d4082..0x013d40b4` 用
  `(0x0d38 + (encoded_index & 7)) << 2` 读取并提取字段；
- `0x013d8996..0x013d89a0` 是 jump-table RegHal field-address decoder 的一个 A
  分支，随后走公共 read/test 路径；
- 多个 `0x013d0xxx..0x013d55xx` 命中只是把 `0x0d38` 放进 descriptor/range
  table，不能据此称为 propagation。

`0x01337db8` 的复杂 helper 确实读取 `0x0d38` 并做 popcount/list construction，
但当前直接 constructor xref 位于 `0x01b0323a`；GB202 FB group-2 constructor replay
从 `0x01b03b72` 开始，并在 `0x01b03b6c` 返回。现有证据没有把该 helper 绑定到
GB202 的 FB override/rollup 阶段，所以不能将它命名为 GB202 A→B consumer。

### 3.3 有限负结果：没有定位到 GSP A writer 或 A-derived B writer

对 executable `PT_LOAD` 的 exact literal 与 address-constructor scan 没有发现
full BAR literal `0x8234e0`、`0x822900`、`0x1087c000`、`0x2087c000`、
`0x10d64000`；编译代码主要用 aperture word offsets 构造地址。围绕 `0x0d38`
候选的 bounded dataflow 中，已确认的是 read wrappers、field decoders 和 descriptor
tables，未见由 GSP 写 A 的具体路径，也未见 A 值流到 B write。

这是针对当前构造方式和可执行映像的有限负证据，不排除动态 table、间接 dispatcher、
压缩/加密固件或硬件状态机。

## 4. 固定 GSP 中对 B 的可见使用

### 4.1 FACT：GB202-bound consumer `0x0132ef40`

constructor replay 对 chip index 65/GB202 给出：

```text
FB +0x9b0 = 0x0132ae68
FB +0x9c0 = 0x0132ef40
```

`0x0132ef98..0x0132efb4` 先通过 FB slots `+0x758` 与 `+0x730` 算出该 FBP 的
有效 LTS 位宽 W；`0x0132efbe..0x0132efdc` 再构造：

```text
0x1000 - 0x5c0 = 0x0a40
offset = (0x0a40 + FBP) << 2
call Fuse/RegHal aperture read callback
```

`0x0a40*4 = 0x2900`，即 B。随后 `0x0132efde..0x0132efec` 在 W 内裁掉无效高位，
反转 disable mask，形成 enable mask。该函数没有读取 A、latch 或 reset state。

### 4.2 FACT：其余 B reader 也没有 A 输入

- `0x0133071c` 有相同的 B-read 算法，但不是已证明绑定到 GB202 FB `+0x9c0` 的
  target；最稳妥的分类是 sibling HAL；
- `0x013d35d0..0x013d35ec` 构造 `(0x0a40+index)<<2` 并调用 object `+0x100`
  read callback，是独立 B read wrapper；
- `0x015d8434..0x015d8478` 在循环中以 `lw` 读取 B 类地址并记录/诊断；
- `0x015da6b4..0x015da718` 构造同类地址并轮询/读取。

值得特别指出：`0x013d3520` 的 A getter 与 `0x013d35d0` 的 B wrapper 在文件中
相邻，但两者之间各自 return；“相邻”不是 copy edge。

### 4.3 纠错：`0x015d3a98` 不是 B-address-capable setter

此前把该函数中的 `0x0a40` 解释为
`(0x822900 - 0x820000) / 4`，因而把它列为 caller-driven B-address setter。
完整 provenance 证明这是一次数值碰撞：真实寄存器是 Ioctrl/MINION aperture 内的
`NV_MINION_NVLINK_DL_CMD(i) = 0x2900 + 4*i`，而 `0x0a40 = 0x2900/4`。

- NVOC class-def `0x1e050c8` 的 class ID `0x11ce10` 由公开 generated header
  命名为 `Ioctrl`；
- GH100/index 58 才把 `Ioctrl+0x438` 绑定到 `0x015d3a98`，GB202/index 65
  在该槽绑定直接返回 `NV_ERR_NOT_SUPPORTED` 的 `0x019d3b50`；
- GH100 的 `Ioctrl+0x468 = 0x015b60a4` 固定发送 command `0x40`，GB202 对应
  `0x019d3bf0` 则直接返回成功而不下钻；
- 固件 export method `0x2080300c/0x2080303c` 与公开
  `NVLINK_SETUP_EOM/NVLINK_EOM_CONTROL` ABI 对齐；公开 MINION hwref 又把
  `0x28b0`、`0x2900`、command `0x40/0x44/0x45` 分别命名为 scratch、per-link
  DL command 与 CONFIG/START/END EOM。

所以该函数既不属于 FB/Fuse aperture，也不写 B，必须从候选集合删除。更详细的
对象、HAL、method-ID 和 register-name 证据见
`parallel/effective_setter_provenance.md`。严格结论仍是：**当前没有发现由 A
驱动的 B writer/copy/recompute**；这不排除未取得的 FSP/GFW 或硬件路径。

## 5. 已排除的几个软件传播假说

### 5.1 Host 在 reset 后显式 copy A→B

**排除于已审计 success path（FACT）。** reset descriptor 不携带 A，success tail
不 replay A、不写 B，也不 compare B。

### 5.2 GB202 `+0x9c0` getter 顺便触发 rollup

**排除于该函数（FACT）。** `0x0132ef40` 只有 topology-width queries、B aperture
read、crop/invert 和返回；没有 A read 或 B write。

### 5.3 `RMROPL2FuseMaskForFModel` 是零售软件 override

**排除（FACT）。** 字符串 `RMROPL2FuseMaskForFModel` 位于 GSP
VA `0x01e30dc8`，可见引用包括 `0x0130718c` 与 `0x013293e0`。
`0x0132932c` 先调用 coarse getter，再只在 FModel/仿真条件成立时把配置 mask 与
读回 mask 相交；真实硬件分支仍保留 FuseRead 结果。它既不读取 A，也不写 B，
不是 retail A→B 传播或旁路。

### 5.4 InfoROM LTS repair hook 是 GB202 rollup

**排除于当前 GB202 binding（FACT）。** 既有 constructor replay 表明 GB202 的
repair、marking、apparent commit 三个实质性 inner slots 都绑定 zero-return stubs。
共享 reset outer hook 的存在不能证明 GB202 通过 InfoROM 重写 B；该机制即使在
其他 chip index 上存在，也属于 repair bookkeeping，不等同于 SKU raw-shadow
rollup。

## 6. 能证明到什么初始化时序

### 6.1 FACT：上下界

当前可见顺序可以安全地写成：

```text
T0  MODS 尝试 set latch，写 A，立即回读 A
T1  MODS 提交不携带 plan 的 reset/reinit request
T2  [不可见的 reset / sense / FSP-GFW / hardware 边界]
T3  GSP/RM 初始化完成后的 topology consumer 读取 B
```

因此，若 A 的确影响 B，传播必须晚于或发生于 T0 之后，并早于某个依赖 B 的
post-init topology query。当前证据不能把 T2 缩小到某条具体指令或某一种 reset
edge。

### 6.2 FACT：公开 chip-boot 顺序只提供更宽的时序框

OpenRM 对 GB202 明确说明 Bootfsm 在 chip reset 后启动 FSP，host 的
`kfspWaitForSecureBoot_GB202` 等待 boot-complete。正常 GSP bootstrap 随后通过
FSP COT/target release，建立可选 SPDM、发送 init RPC、等待 lockdown release、
RISC-V active 与 RM init done。`KernelFsp` 没有专用 `StateLoad`，其该槽为基类
no-op。

这支持以下时序框：

```text
chip reset edge
  -> Bootfsm/FSP secure boot complete
  -> FSP-assisted GSP bootstrap
  -> GSP-RM init complete
  -> GSP topology getter reads B
```

但 MODS request 2 可按既有 coupling 落到 hot、boot、fuse 或 base；公开调用图没有
逐 type 证明每次都穿过完全相同的 chip-reset/FSP sequence。因此不能声称 A 必定在
“FSP boot-complete 前”或“GSP bootstrap 某一步”被采样。

### 6.3 UNKNOWN：T2 内的精确动作

当前不能决定：

- A/latch 是跨 reset retain，还是只在 reset edge 被 sample；
- latch 是 source-select、one-shot trigger，还是受安全固件代理的 request bit；
- B 是 hardware sense/rollup register，还是 FSP/GFW 写出的 shadow；
- A→B 是逐 bit identity、按 LTS pair 扩展、与 physical fuse 做 OR/AND，还是还叠加
  SKU、repair、GPC/FBP availability 等 mask；
- hot/boot/fuse/base 哪一种 reset 会 clear、retain、sample 或 recompute A/B；
- post-reset 首个可靠 B-read 时点，以及失败时是否会回滚或只降级。

## 7. FSP/GFW 与 hardware 边界

### 7.1 FACT：当前可读 GSP ELF 不是 FSP runtime

`/tmp/gsp_inner_19f040_a.elf` 是 GSP-RM 的 RISC-V ELF。公开 610 host tree 暴露
FSP transport、boot wait 和通用 response parser，但没有 host-visible 的 GB202
FSP task dispatcher/image，也没有 A/B 地址、floorsweep `task2/subobject1`
consumer 或 restore body。

既有 task-2 审计只闭合了 MODS sender：host 可见结果是同步 status，没有返回的
plan、PLM snapshot、permission token 或 undo handle。把这个 sender 当成 A→B
consumer，或把 GSP getter重命名为 FSP handler，都会混淆执行域。

### 7.2 INFERENCE：lower-layer propagation 目前是最窄解释，不是证明

综合以下事实：

- host 在 reset 前只写 A；
- reset callback 不携带 A plan；
- post-init GSP 只读 B；
- 可读 GSP 中未找到 A-derived B writer；

最窄的工程解释是：传播发生在 host/GSP 可见层以下，候选为 hardware
sense/source-select/rollup、FSP/GFW，或两者协作。但三者目前没有优先级证据；
“hardware auto rollup”应标成 **INFERENCE/候选**，不能标成 FACT。

## 8. Actor / stage 判定矩阵

| 问题 | 判定 | 等级 |
|---|---|---|
| 谁在正常流程写 A？ | MODS direct-shadow host path | **FACT** |
| A 是否在 reset 前回读？ | 是，逐 plan node immediate readback | **FACT** |
| reset callback 是否收到 A plan？ | 否 | **FACT** |
| 谁读取 GB202 的 B？ | GSP FB `+0x9c0 = 0x0132ef40` | **FACT** |
| B getter 是否读取 A/触发传播？ | 否 | **FACT** |
| 固定 GSP 是否含 A reader？ | 是，`0x013d3520` 等 | **FACT** |
| 固定 GSP 是否有已识别的 B write plumbing？ | 未找到；原候选已反证为 GH100 Ioctrl/MINION EOM sender | **有限负证据 / 候选排除为 FACT** |
| 是否找到 A-derived B writer/copy/recompute？ | 没有，在本报告的 bounded 可读范围内 | **有限负证据** |
| host 是否在 reset 后验证 B adoption？ | 正常 success tail 不验证 | **FACT** |
| FModel property 是否为零售 override？ | 否，只是仿真条件下的 mask intersection | **FACT** |
| FSP/GFW 是否执行 A→B？ | 当前不可见 | **UNKNOWN** |
| hardware 是否自动 rollup？ | 与事实相容，但未证明 | **INFERENCE** |
| 精确 reset 类型/采样边沿？ | 未知 | **UNKNOWN** |
| A→B 逐 bit 公式？ | 未知 | **UNKNOWN** |

## 9. 对后续工作的实际含义

现阶段可以静态写出的，是一个 **observer/validator 的规格**，而不是安全解锁器：
它应区分 pre-reset A、post-reset B、coarse status 和最终公开容量/count，并拒绝把
reset success 当成 adoption success。但在当前桌面仍由 5090 驱动、且没有隔离与
已知恢复合同的情况下，本报告不授权也不建议做 live read/write/reset。

若以后获得新的、仍可离线验证的 artifact，最有价值的三个缺口依次是：

1. 可读的 GB202 FSP/GFW floorsweep consumer 或其有来源的符号/调用表；
2. 每种 reset type 对 latch/A/B 的 retain/sample/clear/recompute 合同；
3. 一个由 NVIDIA 自身代码实现的 post-reset A-plan→B expected-mask compare。

## 最终可引用结论

> 固定 610.43.03 GSP 中，GB202 已确认的 `FB +0x9c0` 只读取已经形成的
> `0x822900+4*FBP` effective LTS-disable view；GSP 另有
> `0x8234e0+4*FBP` raw OPT mask 的读取封装，但在已审计 executable image、公开
> OpenRM reset/bootstrap 路径和 MODS normal success path 中，没有发现一条把 raw
> A 读出、变换并写入 effective B 的软件数据流。MODS 在 reset 前写/回读 A，随后
> 提交不携带 plan 的 reset/reinit；GSP 在 init 后只观察 B。因此传播若存在，最可能
> 位于 reset 边沿以下的 hardware sense/rollup、FSP/GFW 或隐藏状态 replay 中。
> 这是层级边界推断，不是“硬件自动传播”的证明；精确权限、reset 时序和逐 bit
> 公式仍为 UNKNOWN。

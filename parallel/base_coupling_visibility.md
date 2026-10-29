# GB202 base coupling 是否会镜像到 aggregate getter

日期：2026-07-21
状态：离线静态审计完成；硬件级副作用仍未知

## 结论先行

固定 GB202 GSP 中，可以把问题分成两层：

1. **GSP 软件层明确没有做镜像。** GB202 的 reset-coupling setter 在 selector 8
   路径只对 `devicePriBase+0x48.bit0` 做一次 RMW 置位和同址读回；它不读写
   `+0x40` 或 `+0x44`。reset control 的 type 8 arm 也只调用一次 selector 8，
   不会再串行调用 selector 4/5。这一范围内是 **FACT / 否定**。
2. **aggregate getter 明确不直接看 base。** `0x144d4e8` 只返回
   `+0x40.bit0 || +0x44.bit0`，即 fuse coupling OR boot coupling；没有形成
   `+0x48` 地址。这是 **FACT**。
3. **硬件或 reset 边界是否隐式级联仍是 UNKNOWN。** 对 `+0x48.bit0` 的一次
   register write 是否会被 PMC/reset sequencer 以硬件副作用反映到 `+0x40` 或
   `+0x44`，以及 base reset 后三个位如何 retain/clear/reload，固定 GSP 指令和
   公开 610 源码都没有给出合同。不能用“软件没写”冒充“硅一定不会联动”。

因此目前最窄而可靠的答案是：

> **没有找到 base -> fuse/boot 的软件镜像；也没有证据证明硬件镜像存在。**
> 若硬件允许 `base=1, fuse=boot=0`，固定 GB202 aggregate getter 会返回 false。
> 但在硬件级联关系被证明前，一次 aggregate false 仍不能证明 base 为 0。

## 范围、安全边界与 artifact

固定 GSP：

```text
file   /tmp/gsp_inner_19f040_a.elf
size   82577496
sha256 bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47
RX VA  0x01000000..0x01e97000
```

对照源码：`/usr/src/nvidia-610.43.03/src`。公开 generated chip table 在
`nvidia/generated/g_chips2halspec_nvoc.c:129-132` 把 GB202 映射到 HAL index 65。

本轮只做：

- 已知函数附近的小窗口 RISC-V/RVC 解码；
- 两个精确 target 的 direct-xref / constructor replay；
- 公开 610 源码和项目既有报告的定向文本搜索。

没有打开 `/dev/nvidia*`，没有运行 MODS 或 GSP，没有访问 BAR/MMIO、PCI config
或 debugfs，没有 reset、驱动、模块、电源、时钟或显示操作。

证据等级：

- **FACT**：固定 artifact 的指令/控制流或公开源码直接定义；
- **V-STATIC**：两个独立静态来源闭合到同一语义；
- **INFERENCE**：有较强支持，但不是硬件合同；
- **UNKNOWN**：当前静态材料不能决定。

## 1. GB202 确实绑定 base-aware setter

coupling setter 所在对象的 bounded constructor 从 `0x1b431fc` 开始，在
`0x1b43202` 读取第二参数 `+0x10` 的 HAL index，并以 `index >> 5` 和
`index & 31` 做分组选择。

用既有 incomplete RV64 replay 只重放该 constructor、令 index=65，并继续到
`0x1b436c0` 的返回 epilogue，记录到目标对象 `+0x5e8` 只有一次写入：

```text
0x1b4400e: auipc/addi a2 -> 0x109300c
0x1b44016: sd         a2,0x5e8(a0)
```

在抵达 epilogue 前没有第二次 `+0x5e8` 覆盖。故对 GB202/index 65：

```text
object +0x5e8 = 0x109300c
```

这是 **FACT（bounded constructor replay）**。另两个静态 address-construction
位置会把 `0x1084508` 写给其他 dispatch 条件，不能因此把 GB202 误绑定成只支持
selector 4/5 的旧 handler。

## 2. selector 8 只写 `+0x48`

### 2.1 lookup 和 type 分支

`0x109300c` 调用：

```text
0x1b562f0(pGpu, 0x2a, 3, -1, 0, &entry)
```

并从 `entry+0x10` 取 `devicePriBase`，从 private `pGpu+0xb98` 取可直接解引用的
PRI aperture pointer。固定函数在 `0x1093058..0x109305a` 明确要求 selector 为 8；
非 8 路径最终在 `0x109310e..0x1093112` 尾跳 `0x1084508`。

因此 selector 8 和 selector 4/5 是互斥 arm，不是“先 base、再 fuse/boot”的
fallthrough。

### 2.2 selector 8 的全部目标地址

selector 8 正常路径：

```text
0x109306c: addiw  a4,a5,0x310     # access/PLM metadata
0x1093078: lw     a4,0(a4)
0x109307a: addiw  a5,a5,0x48      # coupling target
0x109307e: andi   a4,a4,0x10      # require metadata.bit4
...
0x109308c: lw     a5,0(a3)
0x109308e: ori    a5,a5,1
0x1093092: sw     a5,0(a3)        # RMW set +0x48.bit0
...
0x10930b6: lw     s1,0(a5)        # read back the same target
0x10930b8: not    s1,s1
0x10930bc: andi   s1,s1,1
0x10930be: slli   s1,s1,6         # set failure status if bit0 remained 0
```

**FACT：** selector 8 的成功 arm：

- 只形成 target `devicePriBase+0x48`；
- 只对该 word 的 bit0 做 OR；
- delay 后只读回同一个 target；
- 不形成、不读、不写 `devicePriBase+0x40/+0x44`；
- 不调用 selector 4/5 handler。

所以在 GSP 指令层，base setter 没有软件级 cascade/mirror。

### 2.3 selector 4/5 是三个独立 target 的交叉校准

尾跳目标 `0x1084508` 仍使用完全相同的 device-info tuple 和 aperture：

| selector | metadata | target | 固定 GSP 行为 |
|---:|---:|---:|---|
| 4 | `devicePriBase+0x308` | `devicePriBase+0x40.bit0` | 只置位并读回该 target |
| 5 | `devicePriBase+0x30c` | `devicePriBase+0x44.bit0` | 只置位并读回该 target |
| 8 | `devicePriBase+0x310` | `devicePriBase+0x48.bit0` | 只置位并读回该 target |

这与 `parallel/reset_selection_inputs.md` 中 MODS RegHal 的
fuse/boot/base 三元组逐项一致，故命名达到 **V-STATIC**：

```text
+0x40 = fuse coupling
+0x44 = boot coupling
+0x48 = base coupling
```

三条 setter 各自只验证自己的 target；这支持“软件把三个位当独立状态”这一
解释，但仍不能排除 register write 自身存在未公开的硬件 side effect。

## 3. reset-control 在 base arm 中不串行设置 lower coupling

固定 GSP 的 `NV0080_CTRL_CMD_BIF_RESET` handler 位于 `0x1066260`。公开
`ctrl0080bif.h:68-76` 给出：

```text
type 4 = BOOT_DEVICE_FUSE
type 5 = BOOT_DEVICE
type 8 = BASE
```

对应的三个 mutually-exclusive jump-table arm 是：

```text
0x106653c: load object+0x5e8; a2=4; call
0x106656a: load object+0x5e8; a2=5; call
0x106661a: load object+0x5e8; a2=8; call
```

三条成功边都汇合到 `0x1066392` 后继续 reset，而不是从 type 8 落入 type 4/5。

**FACT：** 在发起 base reset 之前，可见 GSP dispatcher 只请求一次 selector 8；
它没有用另外两个 selector 补写 fuse/boot coupling。

**范围限制：** `0x1066392` 之后跨入真正 reset/reinit 机制。指令级调用图能排除
reset 前的显式串行 setter，却不能观测 reset sequencer、FSP/GFW 或硅内部在
reset 边沿做什么。

## 4. aggregate getter 与 bounded xref 负结果

GB202 的 public aggregate control 已由 constructor replay 证明绑定到
`OBJGPU+0x668 = 0x144d4e8`。该 getter 的正常路径为：

```text
fuse = bit0(aperture + align4(devicePriBase + 0x40))
if (fuse)
    return true
boot = bit0(aperture + align4(devicePriBase + 0x44))
return boot
```

它没有第三次 `+0x48` load。完整 guard / lookup 证据见
`parallel/reset_getter_guard_provenance.md`。

对固定 ELF 第一 executable PT_LOAD 做 exact direct-call xref 后，
`gpuGetOneDeviceEntry`-like helper `0x1b562f0` 有 22 个 direct far-call site；其中
call site 自己在紧邻窗口明确 materialize `a1=0x2a` 的只有：

| call site | 角色 |
|---:|---|
| `0x1084540` | selector 4/5 setter |
| `0x1093048` | selector 8/base setter |
| `0x144d526` | aggregate fuse/boot getter |

这是一个**有界负结果**：在“direct helper call + call-site immediate type 0x2a”
这一可复核集合中，没有第四条 initialization/copy routine，也没有看到
`read +0x48 -> write +0x40/+0x44`。

它不是 whole-program 不存在性证明：间接 helper call、动态形成 type enum、FSP
代码、boot ROM 和硬件状态机都不在该枚举的证明范围内。

## 5. 公开 610 能说明什么，不能说明什么

公开 610：

- `ctrl2080gpu.h:4907-4923` 只定义一个 aggregate `NvBool isResetCoupled`，没有
  三个位或 reset-value 合同；
- `gpu.c:7416-7433` 在 self-hosted GPU 的 recovery 决策中用该 bool 判断是否把
  bus-reset action 升级为 system reboot；
- `ctrl0080bif.h:68-76` 只公开 type 4/5/8 taxonomy；
- 定向搜索没有找到 `+0x40/+0x44/+0x48` 三个 private PMC coupling register 的
  公开名字、reset value、retention domain 或 cascade 定义。

因此公开源码可以证明 aggregate control 的用途和 reset type 分类，不能解释
“为何 getter 不直接读 base”，也不能把 base 写入后的硬件副作用补全。把
`gpu.c` 中的 recovery 用途解释成“base 一定无关”会超出证据。

## 6. 肯定 / 否定 / 未知矩阵

| 问题 | 结论 | 等级 |
|---|---|---|
| GB202 的 coupling setter 绑定 | `object+0x5e8 = 0x109300c` | **FACT** |
| selector 8 的直接写目标 | 只写 `+0x48.bit0` | **FACT** |
| selector 8 是否显式写 `+0x40/+0x44` | 否 | **FACT / 否定** |
| selector 8 是否随后调用 selector 4/5 | 否；非 8 才尾跳 common handler | **FACT / 否定** |
| reset-control type 8 是否串行走 type 4/5 arm | 否，三个 jump-table arm 互斥 | **FACT / 否定** |
| getter 是否直接读 base `+0x48` | 否，只读 fuse OR boot | **FACT / 否定** |
| 找到软件 copy `base -> fuse/boot` | bounded 集合中没有 | **有界负结果** |
| `+0x48` 写入是否有硬件 side effect | 固定软件看不到 | **UNKNOWN** |
| base reset 后三个位的 retain/clear/reload | 无公开 reset-domain 合同 | **UNKNOWN** |
| base-only 状态是否可持续存在 | setter 的独立 target 模型支持其可能性，但未实测 | **INFERENCE / UNKNOWN** |
| aggregate false 是否证明 base=0 | 不能 | **FACT（getter scope）+ UNKNOWN（硬件联动）** |

## 最终可用于主线的表述

> 固定 GB202 GSP 的 base-coupling 软件路径是独立的：selector 8 只置位并读回
> `devicePriBase+0x48.bit0`，reset dispatcher 不追加 selector 4/5；aggregate
> getter 则只读 fuse `+0x40` 与 boot `+0x44`。所以不存在已见的软件级
> base-to-fuse/boot 镜像。硬件 reset sequencer、FSP/GFW 或 register 自身是否
> 产生隐式级联仍无证据，故 aggregate false 不能证明 base 位为 0，也不能单独
> 预测最终 hot/boot/fuse/base reset 类型。

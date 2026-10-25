# RTX 5090 / Lightning BIOS Fan1 Route 1 阶段表

日期：2026-07-27  
当前目标：找一条受控、可复现的 host/RM/GSP 路径，让 Lightning BIOS 启动后的缺失 fan1 / PWM11 / GPIO3 运行时对象被建立或被等效设置；优先静态与只读，风险实验前必须满足安全前置条件。

## 压缩上下文后先读这里

如果上下文被压缩或新会话接手，先读本文件，然后读：

1. `/home/user/rt_5090_project/FAN_CONTROL_DO_NOT_REPEAT_20260727.md`
2. `/home/user/rt_5090_project/FAN_RUNTIME_ROUTE_FINDINGS_20260727.md`
3. `/home/user/rt_5090_project/ASTRAL_STOCK_FAN_BASELINE_20260727.md`
4. `/home/user/rt_5090_project/gsp_heap_runtime_20260726.md`
5. `/home/user/rt_5090_project/scan_logs/fb_scan_incident_summary_20260727_073816.txt`

不要因为压缩上下文而重复已经否定的路线。

## 风险操作硬边界

任何可能导致桌面黑屏、GPU lost、GSP reset、NVIDIA 模块卸载、PCI remove/rescan、BAR/MMIO 写入、FB/WPR/GSP 堆扫描或 live GPU 寄存器实验的操作之前，必须先完成并确认：

1. tmux 会话已经迁移/确认不依赖 GNOME 图形会话；
2. sing-box / VPN 后端已经迁移/确认不依赖 GNOME 图形会话；
3. SSH 仍可进入本机；
4. GPU 恢复脚本路径和用法已经重新确认；
5. 当前没有未保存的重要桌面状态。

如果上述任一项没有确认，不执行风险实验，只继续静态/只读研究。

当前阶段默认禁止：

- 大范围读取/扫描 FB、WPR、hidden carveout、GSP heap；
- 修改 VBIOS、刷写 VBIOS；
- GPIO direction/output、PWM11 强写、GPIO_CUSTOMER_ASYNCRW、ActivateHwFunction 重试；
- 卸载/重载 NVIDIA 驱动模块；
- PCI remove/rescan/FLR/SBR/reset；
- 任何会杀桌面或 GPU 客户端的动作。

## 已确认的硬件/状态事实

当前问题场景：

- ASUS Astral Black RTX 5090 使用 MSI Lightning 800W VBIOS。
- Lightning BIOS 下只初始化一路风扇对象，物理上只有 1、3 号风扇转，2、4 号风扇不转。
- Astral 原厂 BIOS 下有两路 NV-CONTROL fan：
  - fan0 / controller0 -> 物理风扇 1、3；
  - fan1 / controller1 -> 物理风扇 2、4。
- 用户实测：
  - controller0 控制靠近机箱后面板和前面板的一组；
  - controller1 控制中间和背面的一组。

关键差异：

- Astral 好状态：PWM11 可用，`0x00118ab8 = 0x1a000438`，`0x00118abc` 跟随 fan1 duty。
- Lightning 坏状态：PWM11 配置为 `0x00118ab8 = 0x1a0000d8`，`0x00118abc = 0`。
- 直接写 PWM11 duty/config 可以读回或局部生效，但 2、4 号风扇仍不转；缺的不是简单 duty latch，而是 GPIO3/PWM11 mux/selector/运行时对象层。

需要恢复/模拟的配置：

- Astral GPIO3 DCB 片段：`03 d1 00 80 ef 10`
- Lightning GPIO3 DCB 片段：`03 ff 00 00 ef 10`
- 目标语义：GPIO3 `function=0xd1`，`selector=0x5c`

## 已否定或不要重复的路线

这些路线已经测试/审查过，不要压缩上下文后重复：

- NVD FAN dump：能走诊断/枚举方向，但未给出可直接写的 live FanCooler 地址。
- RmFan2XOverride / fan reload / ordinary fan controls：不会凭空建立 Lightning 缺失的第二路 fan cooler。
- ActivateHwFunction：公开 GPIO internal control 没有 selector 参数，不能表达 `selector=0x5c`。
- 普通 GPIO direction/output/read：不是 PWM11 mux 初始化。
- GPIO_CUSTOMER_ASYNCRW：不是这个路径。
- PWM11-only write：不会让 2、4 号风扇启动。
- 大范围 FB/WPR/GSP hidden scan：曾触发 `NV_ERR_RESET_REQUIRED` / 卡死风险，禁止继续粗扫。

## GSP 静态输入

外层固件：

- `/usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin`
- SHA256：`572373620a37418f24dc16b5031c39338778c3257e48e8408de9a57291b24f3a`

内层 ELF 提取方式：

```sh
dd if=/usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin \
  of=/tmp/gsp_inner_19f040_a.elf bs=64 skip=26561 status=none
sha256sum /tmp/gsp_inner_19f040_a.elf
```

内层 ELF：

- offset：`0x19f040`
- SHA256：`bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47`
- 类型：RISC-V ELF，RX segment VA `0x01000000`，RW segment VA `0x04000000`

## 当前核心候选函数

### 1. raw selector method：`0x01802f74`

静态结论：

- `a1` 是 GPIO index / line；
- `a2` 是 selector；
- 写寄存器地址公式近似为 `(gpio_index + 0x880) * 4`；
- 写入时保留高位，低 8 bit OR/替换为 selector；
- 对本目标等价于：GPIO3 selector 写 `0x5c`。

关键逻辑：

```asm
01802fe2: addiw a5, a5, -0x780   # 0x1000 - 0x780 = 0x880
01802fe8: addw  a1, s2, a5       # a1 = gpio_index + 0x880
01802fec: slliw a1, a1, 2
01803006: andi  a2, a2, -0x100
0180300c: or    a2, s3, a2       # low byte = selector
01803010: c.jalr a5              # write vmethod
```

直接引用当前只看到 vtable/address install，不是普通 host-call 入口：

```text
0x01941ca6 -> 0x01802f74 address via 0x01941caa (a5)
0x0194247a -> 0x01802f74 address via 0x0194247e (t3)
0x01942b2e -> 0x01802f74 address via 0x01942b32 (a1)
```

### 2. runtime record setter：`0x017fe5b4`

静态结论：

- 检查 `a1` 是否在对象 line count 范围内；
- 根据 `a1` 找现有 runtime record；
- 写：
  - `record + 0x72b = a2`
  - `record + 0x72c = a3`
- 对本目标希望表达：`a1=3`，`a2=0xd1`，`a3=0x5c`。
- 但它依赖已有有效 line/record 结构，不等价于凭空分配新对象。

关键写入：

```asm
017fe600: sb a2, 0x72b(a5)
017fe604: sb a3, 0x72c(a5)
```

直接调用点：

```text
0x0118152c -> 0x017fe5b4
0x011f11ee -> 0x017fe5b4
0x011f12e4 -> 0x017fe5b4
0x0121cb92 -> 0x017fe5b4
0x0122a69e -> 0x017fe5b4
0x0122a6fa -> 0x017fe5b4
0x0129484e -> 0x017fe5b4
0x01294878 -> 0x017fe5b4
```

初步分类：目前看这些调用多为 VBIOS/table/config/runtime-derived，不是明显 host payload 任意输入。

### 3. wrapper/dispatch：`0x01bca3f8`

静态结论：

- 会先验证所选 runtime record 是否存在；
- 检查返回值不是 `0xff`；
- 检查 index 范围；
- 最后经对象 vtable `+0x250` 调 raw selector method。
- 所以它不是任意 GPIO selector 写入口；Lightning 如果没有有效 GPIO3 record，直接走它可能失败。

直接调用点当前重跑结果：

```text
0x011f11fc -> 0x01bca3f8
0x011f12f4 -> 0x01bca3f8
0x0122a6ae -> 0x01bca3f8
0x0122a708 -> 0x01bca3f8
0x0129485c -> 0x01bca3f8
0x01294886 -> 0x01bca3f8
0x017ffa54 -> 0x01bca3f8
0x017ffa64 -> 0x01bca3f8
0x017ffa8a -> 0x01bca3f8
0x0180003c -> 0x01bca3f8
0x0180004c -> 0x01bca3f8
0x01800072 -> 0x01bca3f8
0x01800630 -> 0x01bca3f8
0x01800640 -> 0x01bca3f8
0x01800666 -> 0x01bca3f8
0x01808250 -> 0x01bca3f8
0x01808272 -> 0x01bca3f8
```

## Public RM control 面的负结果

公开/生成的 GPIO subdevice controls 只有：

- `0x20802300` PROGRAM_DIRECTION：`gpioPin`, `bInput`
- `0x20802301` PROGRAM_OUTPUT：`gpioPin`, `value`
- `0x20802302` READ_INPUT：`gpioPin`, `value`
- `0x20802303` ACTIVATE_HW_FUNCTION：`function`, `pin`

这些结构没有 selector 字节，无法表达 `selector=0x5c`。  
PMGR/平台内部 controls 当前看到的是 power/platform request handler，不是 GPIO selector。

## 当前阶段判断

最有价值的问题不是“PWM11 duty 怎么写”，而是：

1. Lightning 启动后是否存在可用 GPIO3 runtime record；
2. 如果存在，是否有 host/RM/GSP 入口能把该 record 设置为 `function=0xd1 selector=0x5c`；
3. 如果不存在，是否有受控路径能重新导入/补建这个 record；
4. 如果都没有，才考虑更高风险路径：GSP heap/object patch 或 VBIOS table init 前拦截。

当前还没有找到 host payload 直接控制 selector 的公开路径。

## 2026-07-27 新增：callsite 参数来源分类

新增离线脚本：

- `/home/user/rt_5090_project/fan_route1_arg_classifier.py`
- SHA256：`800c5bc88a6513fbf74a0580d5e29b29ce71fab4e64e3342cd9ce4e648a57f1a`

输出：

- `/home/user/rt_5090_project/fan_route1_arg_classifier_20260727.txt`
- SHA256：`1209ec2a7d9fa6e6b9a4f26aa6dff5e5bfe04f46bb28d9c2013bb838547cfd84`

脚本性质：

- 只读 `/tmp/gsp_inner_19f040_a.elf`；
- 不打开 `/dev/nvidia*`；
- 不读写 BAR/MMIO/FB/WPR；
- 不接触运行中的 GPU/驱动。

分类覆盖：

- `0x017fe5b4` setter：8 个直接 callsite；
- `0x01bca3f8` wrapper：17 个直接 callsite。

直接结果：

- `0x017fe5b4` 的 8 个 callsite 中，没有看到“host payload 直接传入 arbitrary function/selector”的局部形态。
- 多数参数来源是：
  - stack/临时表 load；
  - 对象字段 load；
  - 常量 `0`；
  - 已有寄存器/配置字段复制。
- `0x0118152c` 这个 setter caller 比较特殊：它从 `t5` 拆位得到 `a2/a3`：
  - `a2 = (t5 >> 16) & 0xff`
  - `a3 = (t5 >> 24) & 0x1f`
  - 前面把 `t5` 保存到 stack，形态像从表项/编码 word 中取 function/selector，而不是外部控制直接传入。
- `0x017ffa..`、`0x018000..`、`0x018006..` wrapper families 继续显示为内部 GPIO runtime/object-field 路径：
  - `a1` 多来自 `lw -0x414/-0x404/-0x418(...)`；
  - `a2` 多来自 `s7/s2/s4`；
  - 同窗口能看到 `sb ..., 0x72b(record)`；
  - 这证明 GSP 自己会改 runtime GPIO record，但没证明 host 可任意指定 `0xd1/0x5c`。
- `0x01808250`、`0x01808272` 明确使用 `a2=3`，不是目标 selector `0x5c`。

新增 public RM 窄搜结果：

- 搜索范围：
  - `/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080`
  - `/usr/src/nvidia-610.43.03/src/nvidia/generated/g_subdevice_nvoc.c`
  - display/platform/gsp/fifo 相关源文件
- 关键词包括 `selector`、`gpioFunction`、`gpioPin`、`pinSet`、`HwFunction`、`GPIO.*PWM`、`PWM.*GPIO`。
- 结果仍只有：
  - display/NBSI ACPI selector 注释；
  - internal GPIO direction/output/read/activate；
  - display SLI/link GPIO sw-control；
  - 没有能表达 `GPIO3 function=0xd1 selector=0x5c` 的公开 control ABI。

当前新增结论：

route 1 还没死，但“直接找一个公开 RM control 塞 selector”基本是负结果。下一步更有信息量的是追 `0x0118152c` 上游的 `t5` 来源，以及 `0x011f/0x0121/0x0122/0x012948` 这些 table/import caller 的父路径，确认它们是否全都来自 VBIOS/GSP 内部表，而不是 host/RPC payload。

### 2026-07-27 继续追 `0x0118152c`

`0x0118152c` 是 8 个 setter caller 里最值得追的一个，因为它不是简单常量 `0`，而是：

```asm
0118151e: srliw a3, t5, 0x18
01181522: srliw a2, t5, 0x10
01181526: c.andi a3, 0x1f
01181528: andi  a2, a2, 0xff
0118152c: call  0x017fe5b4
```

继续追踪后确认：

- `t5` 最近定义来自 `lw t5, -0xd8(s0)`；
- `-0xd8(s0)` 是同一函数前面通过通用 unpack helper 写入的输出缓冲；
- 关键调用形态：

```asm
01181022: li    a4, 0
01181024: addi  a3, s0, -0xd8     # output buffer
01181028: auipc a1, ...           # format string
0118102c: addi  a1, a1, ...       # "1d1w"
01181030: call  0x011751ac        # generic firmware-table unpack helper
01181056: lw    t5, -0xd8(s0)
```

读出的固定格式串：

- `0x01e26c68`: `1d1w`
- 邻近格式串包括 `1b1w1d4w`、`1b1w1d3w`、`1b1w1d2w1d`、`MXMData` 等；
- 前一个相关 unpack 使用 `0x01e26960`: `4b1w`。

`0x011751ac` 的窗口显示它是高复用固件表 unpack helper：

- xref 数量很多；
- 先解析格式串；
- 再从固件缓冲区/表偏移处 unpack 到调用者给的输出结构；
- 参数里有输出指针和格式串，没有看到 live host/RPC payload 直接参与。

因此 `0x0118152c` 目前也归类为“VBIOS/固件表项导入路径”。它解释了 GSP 如何把表项里的 function/selector 拆出来写 runtime record，但不提供运行时任意指定 `function=0xd1 selector=0x5c` 的入口。

### 2026-07-27 host/RM VBIOS handoff 窄搜

在开源 RM 里窄搜 `VBIOS` / `vbios` / `GspStaticConfig` / `DCB` / `BIT` 后，当前只确认到 host 侧的早期 FWSEC/VBIOS 解析边界：

- `/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/message_queue_cpu.c` 注释说：pre-silicon platforms 需要更大的 command queue，原因是要通过 RPC 发送 VBIOS image；
- `/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/kernel_gsp.c` 早期 FRTS/FWSEC 路径会调用 `kgspExtractVbiosFromRom_HAL`；
- `/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/arch/turing/kernel_gsp_vbios_tu102.c` 显示该路径从 PROM/ROM 读 VBIOS，复制到 host system memory 的 `KernelGspVbiosImg`；
- `KernelGspVbiosImg` 只有：
  - `NvU8 *pImage`
  - `NvU32 biosSize`
  - `NvU32 expansionRomOffset`

注意边界：

- 这段开源代码主要是 early FWSEC/FRTS 的 host-side VBIOS extraction，不等价于已经找到了 fan/GPIO importer 的 host entry；
- 但它支持一个负判断：量产硅片普通路径没有显式公开的“host 任意传一份改过 VBIOS 给 GSP fan importer”的 RPC ABI；
- 如果后续要找初始化前可控点，应继续找 GSP RM 主体里 VBIOS image/object 的来源，而不是假设 public RM control 能直接替换整张表。

### 2026-07-27 新增：GSP VBIOS/global object 槽

`0x01180fb0` caller 中，unpack helper 的 `a0` 来自：

```asm
01180fb0: auipc s7, ...
01180fb4: addi  s7, s7, ...
01180fbc: ld    a0, 0(s7)
```

计算出的全局槽地址：

- `0x041d3f00`

新增离线脚本：

- `/home/user/rt_5090_project/gsp_global_slot_accesses.py`
- SHA256：`7f683611ac6f247943adbb91bca9016b28754e367ea8fc9e51057403908c166b`

输出：

- `/home/user/rt_5090_project/gsp_global_041d3f00_accesses_la80_20260727.txt`
- SHA256：`d155fce15105b2af561ea558bd01150e74efee59777a8548a796eefb30a8fe32`

结果：

- `0x041d3f00` 是一个高频 GSP 全局槽，很多 VBIOS/BIT/DCB/board table parser 都通过 `ld ..., 0(slot)` 读取它；
- 大多数引用是读取；
- 修正脚本避免把 `ld a5,0(a5)` 后的对象字段写误判为 slot 写；
- 当前找到一个真正的 slot 写候选：

```asm
01b9f44e: auipc s3, ...
01b9f452: addi  s3, s3, ...       # s3 = 0x041d3f00
01b9f458: ld    a3, 0(s3)
01b9f466: beqz  a3, ...
01b9f468: j     ...               # 如果已有对象则跳走
...
01b9f47c: sd    s11, 0(s3)        # 初始化全局 VBIOS object 槽
```

包含该写入的函数入口大概率是：

- `0x01b9c210`

该函数直接 caller：

- `0x0101e056 -> 0x01b9c210`
- `0x0195a6b6 -> 0x01b9c210`

`0x0195a688` 是一个参数结构转寄 wrapper：

- 从 `a3 + 0x00 .. 0x48` 读取多个字段；
- 放入寄存器/栈；
- 调用 `0x01b9c210`；
- ELF 中唯一的 `0x0195a688` 函数字面量在 `0x01de0d48`，形态像 descriptor / dispatch table 项，不是普通 direct call。

`0x01b9c210` 局部语义：

- `a0` 是某种对象指针槽，函数内部 `s11 = *(a0)`；
- 若 `s11` 有效，会初始化大量 object fields；
- 在 `0x01b9f47c` 将 `s11` 写入全局 `0x041d3f00`；
- 随后把 `s0` 初始化参数结构里的字段拷到 object：
  - `ld a4, 0x18(s0)` -> `sd a4, 0x738(s11)`
  - `ld a5, 0x10(s0)`，若非零则后续 memcpy 到 object 内部；
  - `lw a4, 0(s0)` -> 存入 object 内部某字段。

当前判断：

- `0x041d3f00` 是比单个 GPIO caller 更上游的好锚点；
- 它很可能代表 GSP 内部 VBIOS/BIOS table access object；
- 下一步应追 `0x0195a688` 的 descriptor/dispatcher 表，确认这个初始化 wrapper 是哪个 RPC/class/object constructor 调到的；
- 如果这个初始化参数结构来自 host/RPC staging，理论上有机会找“表导入前缓冲”；如果来自 GSP 自己从 ROM/FSP 装载，则 route 1 继续收窄。

## 下一步最短反馈回路

只做静态/只读：

1. 追 `0x0195a688` 的 descriptor/dispatch table：`0x01de0d48` 周围结构是什么，谁遍历/注册它。
2. 追 `0x01b9c210` 的两个 caller，尤其 `0x0195a688` 参数结构的来源，判断是否 host/RPC staging。
3. 从剩余 `0x011f/0x0121/0x0122/0x012948` setter callers 和 17 个 wrapper callers 向上追父函数/dispatcher，确认有没有 host/RPC payload 到达。
4. 若仍无 host payload path，才考虑更高风险的 GSP heap/object patch；但这需要先解决 safe read/write primitive 和风险前置迁移。
5. 暂不进入 live 风险实验；如果后面找到明确实验点，先执行本文件“风险操作硬边界”。

只有在找到了明确、参数可控、可回滚的最小 live 实验后，才进入风险操作；进入前必须执行本文件“风险操作硬边界”。

## 2026-07-27 继续：`0x041d3f00` init 链路追到 GSP entry

新增阶段证据文件：

- `/home/user/rt_5090_project/fan_route1_vbios_object_init_chain_20260727.txt`
- `/home/user/rt_5090_project/fan_route1_strict_direct_refs_20260727.txt`
- `/home/user/rt_5090_project/hotspot_reader/gsp_rv_direct_refs_strict.py`

当前 SHA256：

```text
3b02cc3a5823a60b675dd22856f0a6c6b27a05b86ebed376ea87c1aab8986a43  hotspot_reader/gsp_rv_direct_refs_strict.py
cfa177dfc7453d18e650471831b51458d582d756c25f8a5a9e5f3ba39ac4ce67  fan_route1_strict_direct_refs_20260727.txt
b39c9ee7f5be2af2886c8b69deb818eff688dcfabfa0ccf3559e2da5637c8e35  fan_route1_vbios_object_init_chain_20260727.txt
```

重要工具修正：

- `hotspot_reader/gsp_rv_direct_refs.py` 对相邻 `AUIPC+ADDI/JALR` 很有用；
- 但它没有检查 lookahead 窗口内同一寄存器是否被新的 `auipc` 覆盖；
- 因此长 lookahead 可能出现假阳性；
- 本节只采用相邻或人工窗口确认过的边。

人工/相邻确认的链路：

```text
ELF entry point 0x01a9baec
  -> 0x01a9baf8/0x01a9bafc materializes 0x01aba85e in t0
  -> 0x01a9bb00 jr t0

0x01aba85e
  -> 0x01abaa06 materializes 0x01aa6666 in a7
  -> 0x01abaa1a calls helper with that callback-like a7
  -> 0x01abaa30 direct-calls 0x01aa6666

0x01aa6666
  -> 0x01aa6778 direct-calls 0x01a96250

0x01a96250
  -> 0x01a96c32 direct-calls 0x01aaa9b8

0x01aaa9b8
  -> 0x01aab162 direct-calls 0x0101deac

0x0101deac
  -> 0x0101e056 direct-calls 0x01b9c210

0x01b9c210
  -> 0x01b9f47c writes s11 into global slot 0x041d3f00
```

这轮结论：

- 目前追到的 `0x041d3f00` VBIOS/table object 初始化链是 GSP 固件 entry / early init 链；
- 这不是运行时 host/RPC payload 路径；
- 因此它不能作为“开机后重建 GPIO3 record / runtime 设置 `function=0xd1 selector=0x5c`”的直接入口；
- `0x0195a688` 仍更像 NVOC/class metadata constructor thunk：其唯一字面量引用在 `0x01de0d48`，不是普通 RPC dispatch table；
- `0x0101deac` 局部行为是从内部对象链和 `s8+0x7c/0x80/0x88` 等字段选择/补建对象，再调用 `0x01b9c210`；目前没有看到 host 任意参数输入。
- strict direct-ref 额外确认 `0x01b9c210` 还有第二个 caller：`0x0195a6b6 -> 0x01b9c210`；这对应前面发现的 `0x0195a688` wrapper/metadata 分支，下一步单独追它的调度来源。

未证明的边界：

- 这不证明完全没有其他运行时 re-init 路径；
- 只说明当前从 `0x041d3f00` 全局槽倒追到的初始化分支已经收敛到 entry/init；
- 下一步不应继续在这条 branch 上重复找 public selector control，而应转向：
  1. 找是否存在其他运行时 `0x041d3f00`/VBIOS object 重新初始化入口；
  2. 或从 FAN/NVD dump / FAN BoardObjGrp introspection 方向确认对象枚举和字段；
  3. 或继续静态搜索 `GPIO3`/`function=0xd1`/`selector=0x5c` 被写入 runtime record 的其他来源。

安全边界：

- 本节只读 GSP ELF；
- 没有打开 `/dev/nvidia*`；
- 没有读写 BAR/MMIO/FB/WPR/GSP heap；
- 没有动桌面、VPN、模块或显卡状态。

## 2026-07-27 继续：`0x0195a688` / metadata wrapper 分支

追 `0x01b9c210` 的第二个 caller：

```asm
0195a688: addi16sp sp, -0x30
0195a690: ld  t5, 0x48(a3)
0195a694: ld  t4, 0x40(a3)
0195a698: lw  t3, 0x38(a3)
0195a69c: lw  t1, 0x30(a3)
0195a6a0: lw  a7, 0x28(a3)
0195a6a4: lw  a6, 0x20(a3)
0195a6a8: lw  a5, 0x18(a3)
0195a6aa: lw  a4, 0x08(a3)
0195a6ac: lw  a3, 0x00(a3)
0195a6ae: sd  t5, 0x18(sp)
0195a6b0: sd  t4, 0x10(sp)
0195a6b2: sd  t3, 0x08(sp)
0195a6b4: sd  t1, 0x00(sp)
0195a6b6: call 0x01b9c210
```

含义：

- `0x0195a688` 本身只是参数结构展开 wrapper；
- 输入 `a3` 是一个固定 layout 的 metadata/init 参数结构；
- 当前没有看到它从 host/RPC payload 直接获得 `GPIO3/function/selector` 字段；
- 它唯一 raw 字面量引用仍在 `0x01de0d48`。

数据图：

```text
0x0195a688 raw function pointer
  <- qword at 0x01de0d48

0x01de0d38 descriptor-ish record
  contains 0x01e8cc70, 0x0195a688, 0x01e90868, 0x01dde528
  <- qword at 0x01dde4b0

0x01dde4b0 metadata/class-ish record
  contains 0x01de0d38 and method 0x019598c0
  <- qword at 0x01e90870

0x01e90868 table
  qword 0x01e90868 = 5
  qword 0x01e90870.. = five metadata record pointers
```

strict PC-ref 结果：

```text
TARGET 0x0195a688     # no PC-relative code ref; raw table only
TARGET 0x01de0d38     # no strict PC-relative code ref; raw table only
TARGET 0x01de0d48     # no ref
TARGET 0x01dde4b0
0x01b9c320 -> 0x01dde4b0 address via 0x01b9c324 (a4)
TARGET 0x01e90868     # no strict PC-relative code ref
TARGET 0x01e90870     # no strict PC-relative code ref
TARGET 0x01e8cc70     # no useful unique ref; common metadata pointer
```

这轮判断：

- `0x0195a688` 分支目前不是可用的 runtime host entry；
- 它更像对象系统/NVOC-style constructor metadata；
- `0x01dde4b0` 在 `0x01b9c320` 被写入新建 object 的 slot 0，说明 constructor 会给 object 安装这套 class metadata；
- 继续沿这条 metadata 图找“谁普通调用 `0x0195a688`”判别力较低，因为调用大概率是通用 object framework 间接调用；
- 若要继续找运行时入口，优先级转向：
  1. GSP/RM NVD FAN introspection 静态追踪；
  2. 其他 runtime re-init / VBIOS object reload controls；
  3. 其他能写 `record+0x72b/0x72c` 或 raw selector `(gpio+0x880)*4` 的非 init caller。

## 2026-07-27 继续：NVD FAN introspection 已有实测为负

本地已经存在 NVD FAN dump 实测，不需要再碰 live GPU：

```text
/home/user/rt_5090_project/lightning_bad_snapshot_20260727_061134/fan_component6.pb
/home/user/rt_5090_project/asus_stock_final_snapshot_20260727_060820/fan_component6.pb
/home/user/rt_5090_project/asstral_stock_baseline_20260727_055919/fan_component6_astral_stock.pb
/home/user/Downloads/fan_component_nvdump_6104303_a.pb
/home/user/Downloads/fan_component_nvdump_6104303_b.pb
```

这些文件 SHA256 全部相同：

```text
d3cb19c03042cea932ae7352ebaf413ed50fd4445cd29d855454072c0a2e967d
```

共同 wire decode：

- payload 只有 120 bytes；
- top-level 只有 `root.3[0]`；
- 内部只有两个小 message：
  - `root.3[0].1[0]`，26 bytes；
  - `root.3[0].101[0]`，87 bytes；
- 未出现能区分 Astral good-state 两路 fan 和 Lightning bad-state 单路 fan 的对象列表；
- 未出现可作为 GSP heap VA / FanCooler pointer 的 64-bit live 指针字段；
- 好 BIOS 和坏 BIOS 完全同 SHA，说明这条 dump 不是我们需要的 FanCooler/Fan1 runtime object introspection。

开源 RM 路径确认：

- `gpu_protobuf.c` 在 GSP-client 模式下把 `NVDUMP_COMPONENT_ENG_FAN` 注册为 GSP-only；
- `nv_debug_dump.c` 对 GSP-only engine 调 `NV_RM_RPC_DUMP_PROTOBUF_COMPONENT`；
- `rpc.c` 的 `rpcDumpProtobufComponent_v18_12` 只发送：
  - component；
  - dump type；
  - countOnly；
  - bug/internal code；
  - buffer size；
  然后把 GSP 返回 blob 原样追加到 protobuf；
- 因此 external `NV2080_CTRL_CMD_NVD_GET_DUMP(component=6)` 是观察路径，不是控制路径。

这轮结论：

- NVD FAN dump 这条路已经不值得继续作为“找 Fan1 live object pointer”的主线；
- 它可以保留为 sanity check，但当前证据是负结果；
- 下一步应回到静态搜索其他 runtime setter/re-init，或者明确进入风险更高的 GSP heap/object patch 前置研究。

## 2026-07-27 继续：`0x72b/0x72c` 全局写点归组

本节只读 GSP ELF；没有打开 `/dev/nvidia*`，没有读写 BAR/MMIO/FB/WPR/GSP heap。

目标是避免把“同样数值的结构偏移”误判成 GPIO runtime record。机器化按 `+/-0x72b`、`+/-0x72c` 写点归组后得到：

```text
groups 19, stores 50

0x017fe5b4 leaf setter:
  017fe600: sb a2, 0x72b(a5)
  017fe604: sb a3, 0x72c(a5)
```

核心修正：

- `0x017fdf38` 是一个更大的 GPIO / hardware-function 编排函数；
- `0x017fe5b4` 是其中附近的独立 leaf setter；
- 不应把 `0x017fdf38` 和 `0x017fe5b4` 混成同一个 API。

`0x017fe5b4` 的准确局部语义：

```asm
017fe5b4: c.addi   sp, -0x20
...
017fe5be: c.lui    a4, 2
017fe5c0: c.add    a4, a0
017fe5c2: lw       a4, 0x5a4(a4)       # line count / upper bound
017fe5c8: bgeu     a1, a4, fail
...
017fe5e0: lw       a0, 0x2f8(a0)
017fe5e4: bgeu     a4, a0, fail
...
017fe5f2: mul      a1, a1, 0xa
017fe5f8: mul      a4, a4, 0x280
017fe5fc: c.add    a1, a4
017fe5fe: c.add    a5, a1
017fe600: sb       a2, 0x72b(a5)
017fe604: sb       a3, 0x72c(a5)
```

也就是说它依赖已有对象里的 line count / index table / record 数量；它能改已有 record，不负责凭空建立缺失 GPIO3/Fan1 record。

`0x72b/0x72c` 全局写点的其他重要分类：

- `0x0191e0d8`：
  - 有 11 个同偏移写点；
  - 直接 caller 只有 `0x01421152` 和 `0x01939db4`；
  - 本体从 `a1/a2` 读取 ID/表字段，然后批量写 `a0 + 0x16c0` 起的一大段配置；
  - 这是大对象默认配置/生成器，不是 GPIO3 selector 的运行时入口。
- `0x0181be2a`：
  - 有 6 个同偏移写点；
  - strict direct refs 没有普通 direct call；
  - 形态更像表/方法引用或大初始化函数，不是当前目标入口。
- `0x017ff854`、`0x017ffe3c`、`0x01800430`、`0x018080e8`：
  - 只写 `0x72b`，并通过 wrapper/方法表继续走对象校验；
  - strict refs 均为 `0x01941xxx/0x01942xxx` 附近的地址安装；
  - 属于 GPIO method/vtable 安装或内部对象方法，不是 public host control。
- `0x01be01cc`、`0x01be03d8`、`0x01be0ae0`：
  - 这些地址把 `0x0181e850`、`0x0181f0e0`、`0x0181f81c` 等函数地址写入对象 slot；
  - 当前定性为按芯片/对象类型安装方法表；
  - 不是 runtime host/RPC 入口。

对 `0x017fe5b4` 的 direct caller 再看一层：

```text
0x0118152c -> 0x017fe5b4
0x011f11ee -> 0x017fe5b4
0x011f12e4 -> 0x017fe5b4
0x0121cb92 -> 0x017fe5b4
0x0122a69e -> 0x017fe5b4
0x0122a6fa -> 0x017fe5b4
0x0129484e -> 0x017fe5b4
0x01294878 -> 0x017fe5b4
```

其中：

- `0x0118152c` 从 firmware-table unpack 结果 `t5` 中拆字段：

```asm
0118151e: srliw a3, t5, 0x18
01181522: srliw a2, t5, 0x10
01181526: c.andi a3, 0x1f
01181528: andi  a2, a2, 0xff
0118152c: call  0x017fe5b4
```

- `0x011f11ee/0x011f12e4/0x0122a69e/0x0122a6fa/0x0129484e/0x01294878` 都先从栈临时变量、对象字段或表项读出 `a1/a2/a3`，再调用 setter；
- 没看到 public host/RPC payload 直接带入 arbitrary `function=0xd1 selector=0x5c`。

当前判断：

- 目前唯一真正能写 runtime record `+0x72b/+0x72c` 的小函数仍是 `0x017fe5b4`；
- 它不是创建 Fan1/GPIO3 对象的函数；
- 已看到的调用来源仍是 VBIOS/firmware table import 或内部对象状态同步；
- 因此“找一个现成公开 control 调 setter”这条路继续收窄，下一步应找：
  1. 是否存在运行时 re-import / reload 这类上层路径；
  2. 是否存在能让 `0x017fe5b4` 看见 GPIO3 record 的对象补建路径；
  3. 如果都没有，再进入 GSP heap/object patch 的安全前置研究。

## 2026-07-27 继续：`0x017fe4b8` base record helper 归类

本节只读 GSP ELF；没有打开 `/dev/nvidia*`，没有读写 BAR/MMIO/FB/WPR/GSP heap。

`0x017fe4b8` 是目前最像“补建/填充 GPIO base function record”的小 helper。它和 `0x017fe5b4` 是两层：

1. `0x017fe4b8` 填 base record：
   - 检查 record index、line/index、mask；
   - 写 `record + 0x724..0x728`；
   - 设置对象 mask；
   - 失败时不创建新上层对象。
2. `0x017fe5b4` 改 secondary bytes：
   - 写 `record + 0x72b = a2`；
   - 写 `record + 0x72c = a3`；
   - 依赖 base record / line count / index table 已存在。

`0x017fe4b8` 的 strict direct caller：

```text
0x011812dc -> 0x017fe4b8
0x0118146e -> 0x017fe4b8
0x0118150e -> 0x017fe4b8
0x0121cb76 -> 0x017fe4b8
0x0121d6ee -> 0x017fe4b8
0x01bb24e8 -> 0x017fe4b8
0x01bb2d2a -> 0x017fe4b8
0x01bb30c0 -> 0x017fe4b8
0x01bb3144 -> 0x017fe4b8
0x01bb3856 -> 0x017fe4b8
0x01bb38f8 -> 0x017fe4b8
0x01bb394e -> 0x017fe4b8
0x01bb3d64 -> 0x017fe4b8
```

当前分类：

- `0x011812dc / 0x0118146e / 0x0118150e`：
  - 和 `0x0118152c -> 0x017fe5b4` 同属 firmware table unpack/import 路径；
  - 参数来自 `s5/t5` 中拆出的表项 bitfield；
  - 不是 host/RPC payload。
- `0x0121cb76`：
  - 从已有结构的 `-0x314..-0x304(t6)` 取字段；
  - 先调用 `0x017fe4b8`，随后调用 `0x017fe5b4`；
  - 形态是把已有 runtime/config record 重放到对象里。
- `0x0121d6ee`：
  - 先用 `0x017fe68c / 0x017fe76c` 一类 getter 读现有 record；
  - 再把字段写回/同步；
  - 不是任意新建 GPIO3 的入口。
- `0x01bb24e8 / 0x01bb2d2a / 0x01bb30c0 / 0x01bb3144`：
  - 都在同一个大 DCB/GPIO importer/state-machine 内；
  - 从已有 `record+0x724..0x728` 读字段，复制到另一个 index；
  - 常见参数形式是 `a2 = index + 0xe8`，`a3 = index`，其余字段来自已有 record。
- `0x01bb3856 / 0x01bb38f8 / 0x01bb394e / 0x01bb3d64`：
  - 仍在同一大 GPIO importer/state-machine 内；
  - 会按固定 case 添加若干默认/派生 function，例如 `0x20`、`0x21`、`0x25`、`0x26`、`0x75` 等；
  - 没看到目标 `function=0xd1 selector=0x5c` 从 host 传入。

这轮结论：

- `0x017fe4b8` 证明 GSP 内部确实有“添加/填 base record”的函数；
- 但已找到的全部直接 caller 都是 VBIOS/DCB/GPIO importer 或已有对象状态重放；
- 目前仍没有公开 host/RPC/control 入口可以在 Lightning 启动后任意调用：

```text
0x017fe4b8(a0=gpio_object, a1=record_index, a2=function, a3=line, a4/a5/a6/a7=flags...)
0x017fe5b4(a0=gpio_object, a1=line, a2=function_or_secondary, a3=selector_or_secondary)
```

对目标的意义：

- 如果有办法合法调用这两个 helper，理论上“先补 GPIO3 base record，再写 secondary selector，再 raw selector 写 PWM mux”这条链是合理的；
- 当前缺口不是“不知道该写什么”，而是“不知道怎么从 host 安全、合法、参数可控地触达这些 GSP 内部 helper”；
- 继续路线应优先找能调用 `0x01bb...` GPIO re-import/state-machine 的运行时入口，或找 object framework 是否有 debug/internal invoke，而不是重复 PWM11-only 写。

### GPIO object 偏移校正

前面阶段表里写的 `+0x5a4`、`+0x724` 是反汇编窗口里的局部表达，容易漏掉 `c.lui 2` 或 index 计算。当前按 `0x017fe4b8/0x017fe5b4/0x017feb84` 重算后的对象布局应使用这些公式：

```text
gpio_object + 0x02f8
  record_count

gpio_object + 0x0328 + function * 4
  function -> record_index table

gpio_object + 0x25a4
  line_count

gpio_object + 0x25a8 + function * 0x10
  per-function line mask

gpio_object + 0x3598 + line * 4
  line -> record_index table

gpio_object + 0x0724 + record_index * 0x280 + line * 0x0a
  base record function byte

gpio_object + 0x0725..0x0728 + record_index * 0x280 + line * 0x0a
  base record auxiliary fields

gpio_object + 0x072b + record_index * 0x280 + line * 0x0a
  secondary byte written by 0x017fe5b4 a2

gpio_object + 0x072c + record_index * 0x280 + line * 0x0a
  secondary byte written by 0x017fe5b4 a3
```

这不改变前面的方向判断，但会影响后续任何 GSP object patch / dump pattern matching。后续不要再把 `0x5a4` 直接当成 object absolute offset；它实际是 `0x25a4`。

### `0x01bb0f60` GPIO importer/state-machine 入口追踪

`0x01bb24e8..0x01bb3d64` 这些 `0x017fe4b8` caller 都落在同一个大函数内。该大函数入口当前按 prologue 定为：

```asm
01bb0f60: c.addi16sp sp, -0x1c0
...
01bb0f7e: auipc s7, ...
01bb0f86: ld    s5, 0(s7)
```

strict direct ref 到 `0x01bb0f60` 只有一个：

```text
0x01bb20d4 -> 0x01bb0f60
```

但 `0x01bb20d4` 仍在 `0x01bb0f60` 同一函数内部，是本 state-machine 的二阶段/递归调用：

```asm
01bb20c6: ld   a0, -0x350(s0)
01bb20d2: mv   a1, s5
01bb20d4: call 0x01bb0f60
```

额外查了 split-entry 可能性：

- `0x01bb0ffe`：无 strict direct ref；
- `0x01bb1002`：无 strict direct ref；
- raw qword/dword 中也没有直接保存 `0x01bb0f60`、`0x01bb0cf0`、`0x017fe4b8`、`0x017fe5b4`。

因此当前没有看到外部 host/RPC 直接进入该 GPIO importer/state-machine 的证据。它更像 GSP 对象构造/内部状态机使用的路径。

### public/internal RM control 再核对

再次核对 610.43.03 公开生成表和 headers：

```text
0x20802300 PROGRAM_DIRECTION  flags=0xc0 params={gpioPin,bInput}
0x20802301 PROGRAM_OUTPUT     flags=0xc0 params={gpioPin,value}
0x20802302 READ_INPUT         flags=0xc0 params={gpioPin,value}
0x20802303 ACTIVATE_HW_FUNCTION flags=0xc0 params={function,pin}
```

这些结构仍然没有：

- selector；
- mux select；
- DCB entry payload；
- table re-import；
- GPIO object create/build；
- FanCooler create/build。

所以它们不能表达目标操作：

```text
GPIO3 function=0xd1 selector=0x5c
```

本轮结论：

- GSP 内部有足够的 helper 能表达这件事；
- 公开/internal GPIO control ABI 仍不足；
- 关键缺口收敛为“找一个能触发 GSP 内部 helper 的受控入口”，不是“继续猜 PWM 寄存器”。

### `EnableRmTestOnlyCode` / internal flag 复核

`0x20802300..0x20802303` 的 `flags=0xc0` 拆开是：

```text
0x40 = RMCTRL_FLAGS_ROUTE_TO_PHYSICAL
0x80 = RMCTRL_FLAGS_INTERNAL
```

`RMCTRL_FLAGS_INTERNAL` 的注释是：只能由 RM 自己发起；外部调用返回 `NV_ERR_NOT_SUPPORTED`。

`EnableRmTestOnlyCode` 对应的是另一个 flag：

```text
RMCTRL_FLAGS_RM_TEST_ONLY_CODE = 0x100000
```

源码中它只在 control path 看到这个 flag 时检查 `PDB_PROP_SYS_ENABLE_RM_TEST_ONLY_CODE`。GPIO internal controls 没有这个 flag，所以开启 `EnableRmTestOnlyCode` 不会把 `0x20802300..0x20802303` 变成外部可用，也不会新增 selector 参数。

当前结论：

- `EnableRmTestOnlyCode` 不是这条 GPIO/Fan1 路线的权限钥匙；
- 即使能调用 `ACTIVATE_HW_FUNCTION(function,pin)`，它仍缺 selector 字段，不能表达 `selector=0x5c`；
- 如果要触达 `0x017fe4b8/0x017fe5b4`，仍需 RM-internal caller、GSP object patch、或初始化输入/VBIOS 路线。

公开源码里能看到 `NV2080_CTRL_CMD_INTERNAL_GPIO_ACTIVATE_HW_FUNCTION` 的一个真实调用点：

```text
/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/disp/arch/v04/kern_disp_0400.c
```

该调用使用：

```c
pGpu->hInternalClient
pGpu->hInternalSubdevice
params.pin
params.function
```

语义是 display / SLI-link 检测内部按 pin/function 激活硬件功能。它没有 selector，也没有 DCB/GPIO table payload；这进一步支持它不是本目标的直接入口。

GSP ELF 中只保留了底层 GPIO HAL 名：

```text
gpioProgramOutput_v05_01     string VA 0x01ddc898 -> code ref 0x01807f0a
gpioProgramDirection_v05_01  string VA 0x01ddc8b8 -> code ref 0x018080d2
gpioReadInput_v05_01         string VA 0x01ddc918 -> code ref 0x01808a08
```

这些窗口对应普通 pin output/direction/input 实现。raw selector 方法 `0x01802f74` 是另一条对象方法：

```asm
01802fe8: addw  a1, s2, 0x880
01802fec: slliw a1, a1, 2
01803006: andi  a2, a2, -0x100
0180300c: or    a2, s3, a2
01803010: jalr  write_vmethod
```

也就是说：

- `PROGRAM_OUTPUT/DIRECTION/READ_INPUT` 不会写 selector；
- `ACTIVATE_HW_FUNCTION` 的公开参数也没有 selector；
- selector 写仍只存在于 GSP 内部对象方法，不在当前公开/internal GPIO control ABI 暴露。

源码全局搜索 `NV2080_CTRL_CMD_INTERNAL_GPIO_*` 的实际调用点，除 headers/generated table 外，只看到：

```text
/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/disp/arch/v04/kern_disp_0400.c
```

没有看到 fan、pmgr、therm 或 board-object 路径通过这些 public/internal controls 间接重建 Fan1/GPIO3。

### fan / thermal public controls 复核

`ctrl2080fan.h` 在 610.43.03 公开 header 中基本为空；generated table 中 `0x2080270d/0e` 是 GC6 entry/exit，不是 fan config。

`NV2080_CTRL_CMD_THERMAL_SYSTEM_EXECUTE_V2` 只是 thermal targets/providers/sensors 的查询脚本，支持的 opcode 是：

- targets available/type；
- provider type；
- sensors available；
- sensor provider/target/range；
- sensor reading。

它没有：

- fan/cooler object create；
- fan target set；
- PWM selector；
- GPIO mux；
- DCB/GPIO table re-import。

所以 public fan/thermal control 面目前也没有可用的 Fan1/GPIO3 补建入口。

### generic BoardObj control 复核

`ctrl2080boardobj.h` / `ctrl2080boardobjgrpclasses.h` 主要是通用结构、mask、client info/status/control/readings 类型定义。它们没有 `NV2080_CTRL_CMD_*` 命令定义；generated subdevice table 里也没有 generic BoardObj set/get 方法。

因此当前看不到一个“从用户态传任意 BoardObjGrp payload 给 RM/GSP”的公开入口。FanCooler/GPIO runtime object 仍然只能走具体子系统的闭源 importer/control，而不是通用 BoardObj API。

### registry / override knob 复核

围绕以下 GSP registry 字符串引用窗口做了一轮 AUIPC/JALR 目标解析：

```text
RmPmgrOverride
RmPmgrPmuOverride
RmFan2XOverride
RMSCIVidPWM
RMForceEnableBrightnessOverPwmPin
RMGpioPmuMutexTimeoutus
```

过滤目标包括：

```text
0x017fe4b8  base_record helper
0x017fe5b4  secondary setter
0x01bb0f60  GPIO importer/state-machine
0x01802f74  raw selector method
0x01bb0cf0  GPIO subobject init
```

第一次手写快速脚本漏掉了 `AUIPC imm << 12`，所以只保留校正后的结果。校正结果：

```text
key_hits = none
```

解释：

- 这些 registry/override knob 目前没有表现出“运行时补建 Lightning 缺失 Fan1/GPIO3/PWM11 对象”的直接入口；
- `RmFan2XOverride` 附近确实会调用若干通用 GPIO/helper 函数，例如 `0x017feb84`、`0x017fec9c`、`0x017ff72c`、`0x01804318`，但没有命中 `base_record`、`secondary_setter`、`gpio_importer` 或 `raw_selector`；
- `RMGpioPmuMutexTimeoutus` 附近也有通用 helper 调用，例如 `0x017fec9c`、`0x01800c28`，但同样不是拓扑导入或 selector 配置入口；
- `RmFan2XOverride` 仍按既有实验结论处理：`1/2/3` 没有创建第二个 fan target；
- `RMSCIVidPWM` 和 brightness PWM 路线不是 board fan PWM；
- `RMGpioPmuMutexTimeoutus` 是互斥/超时参数，不是拓扑导入或 selector 配置。

所以这组 knob 暂时降级，不继续反复追。

### 关于“直接复用启动导入函数”的当前判断

用户指出：GPIO/Fan 路线虽然在启动阶段从 VBIOS/DCB 表导入，但这不代表运行时不能复用同一批函数。这个判断是对的；当前不能把“启动路径”直接等同于“不可调用”。

当前更精确的边界是：

- `0x017fe4b8` / `0x017fe5b4` / `0x01802f74` 都是 GSP 内部可执行代码；
- 如果能在 GSP 内部以正确参数调用它们，理论链条成立：

```text
0x017fe4b8(gpio_object, record_index, function, line, flags...)
0x017fe5b4(gpio_object, line, secondary/function, selector)
0x01802f74(gpio_object/register-object, gpio_index, selector)
```

目标效果是补/改 GPIO3：

```text
line/index = 3
function   = 0xd1
selector   = 0x5c
```

但当前未解决的是“reachability”，不是“函数是否存在”：

1. host CPU 不能直接跳到 GSP VA `0x017fe4b8` / `0x017fe5b4` / `0x01802f74`；
2. 这些函数需要 live `gpio_object` 指针、已有/可用 record index、line count、mask/table 状态；
3. 已找到的公开/内部 RM controls、registry knob、thermal/fan APIs 没有把任意 `function/selector` payload 传给这些函数；
4. `0x01bb0f60` GPIO importer 的入口仍只看到同函数内部的二阶段调用，未看到外部 host/RPC 入口；
5. 原始 VBIOS/table object init 链来自 GSP entry/early init，并写入全局 slot `0x041d3f00`，这解释了启动导入，但不提供运行时重导入 ABI。

所以当前路线不是“证明不能调用”，而是把问题缩小为以下三种之一：

1. 找到一个现成 GSP/RM runtime control，能合法进入上述函数并带入目标参数；
2. 找到运行时可改的输入缓存，让已有 importer 重新读到 Astral 风扇/GPIO 表项；
3. 走 live GSP patch / heap object patch，人工提供 `gpio_object` 和调用参数。

第 3 条理论上最直接，但风险也最高，和之前“读/扫 GSP heap 都可能让显示卡死”的风险同类；当前静态阶段不执行。

### FanCooler importer / allocator 入口复核

`0x011cd878` 是已知 FanCooler importer。strict direct-ref 结果：

```text
0x012f2772 -> 0x011cd878 call via 0x012f2776
```

也就是说当前镜像中只看到一个直接 caller。该 caller 位于 `RmFan2XOverride` 同族的 fan-management / board-object startup allocation 路径。

FanCooler allocator `0x01b835ec` 的 direct caller：

```text
0x011cdcfc -> 0x01b835ec
0x011ce434 -> 0x01b835ec
0x012f296a -> 0x01b835ec
0x012f2af6 -> 0x01b835ec
```

其中 `0x012f296a` / `0x012f2af6` 也在 `0x012f...` fan-management startup/import 家族内。

`0x011751ac` 是通用 VBIOS/table parser，direct caller 极多；单独枚举它没有判别力。和本目标相关的是 `0x011cd878` importer 使用它解析 fan table entry，而不是 parser 自身提供 runtime API。

当前解释：

- “复用启动函数”的瓶颈不是 parser 或 allocator 缺失；
- 瓶颈是没有找到第二条 runtime host/RPC 入口能进入 `0x011cd878` 并提供替换 fan/GPIO 表项；
- 现有唯一 importer caller 仍落在 startup/object allocation 路线。

### VBIOS/table global slot `0x041d3f00` 读写分类

`0x041d3f00` 是历史记录中已确认的 VBIOS/table object global slot。对该地址做 direct xref 并按后续内存访问分类：

```text
direct refs: 438
read refs:   314
write refs:  0
read+write:  1
none/indirect use: 123
```

唯一的读后写点：

```text
0x01b9f44e address materialization
  -> ld a3, 0(s3)
  -> sd s11, 0(s3)   ; around 0x01b9f47c
```

这就是既有记录里的 early-init 写入路径。

fan/GPIO/table importer 附近看到的是读：

```text
0x01bb0f7e -> ld s5, 0(s7)    ; GPIO importer/state-machine 入口读 global slot
0x01bb1cbc -> ld s6, 0(s4)
0x011c2b52..0x011ce06e 等 fan/table helper 读 global slot
```

当前没有看到另一个 runtime 写 `0x041d3f00` 的路径。因此“改运行时 table object 指针，让 importer 重新读替换表”的路线目前也没有现成入口；如果要做，仍会落到 live memory patch。

### GPIO object 指针公式候选

`0x01bb0f60` GPIO importer/state-machine 入口附近：

```asm
01bb0f7e: auipc s7, ...
01bb0f82: addi  s7, s7, ...      ; s7 = &0x041d3f00
01bb0f86: ld    s5, 0(s7)        ; s5 = *(0x041d3f00)
01bb0f8a: c.lui a5, 2
01bb0f94: add   a5, s5           ; a5 = s5 + 0x2000
...
01bb0fbe: ld    s6, 0x1a8(a5)    ; s6 = *(s5 + 0x21a8)
...
01bb1018: addi  a5, s6, 0x2e0
01bb103e: addi  a0, s6, 0x450
01bb1062: sd    a5, 0x300(s6)
```

因此 live GPIO object 指针的静态候选公式是：

```text
vbios_table_object = *(0x041d3f00)
gpio_object        = *(vbios_table_object + 0x21a8)
```

这对 route 3（live object patch / 内部函数调用）有价值：`0x017fe4b8`、`0x017fe5b4`、`0x01802f74` 的 `a0` 大概率应是这个 `gpio_object` 或它关联的 GPIO/register object。

但这仍不是可执行入口。它只是把“如果以后必须做窄 live 验证，需要哪个 GSP 对象指针”这件事变得更具体。

## 2026-07-27 继续：GSP 端 RM control 表与 GPIO activate 精确语义

本节只读 GSP ELF 和 NVIDIA 610.43.03 开源 RM；没有打开 `/dev/nvidia*`，没有读写 BAR/MMIO/FB/WPR/GSP heap。

### GSP 端 control dispatch 表

在 `/tmp/gsp_inner_19f040_a.elf` 中，若干 RM control ID 只出现一次，形态是 32-byte dispatch table entry：

```text
handler qword
flags   qword
methodId + paramSize
common dispatch pointer 0x01c20870
```

关键 entry：

```text
0x20802300 GPIO_PROGRAM_DIRECTION
  handler=0x017f4728 flags=0xc0 psize=0x8

0x20802301 GPIO_PROGRAM_OUTPUT
  handler=0x017f47cc flags=0xc0 psize=0x8

0x20802302 GPIO_READ_INPUT
  handler=0x017f486c flags=0xc0 psize=0x8

0x20802303 GPIO_ACTIVATE_HW_FUNCTION
  handler=0x01801fa4 flags=0xc0 psize=0x8

0x208001e8 GPU_RPC_GSP_TEST
  handler=0x013ffe10 flags=0x100108 psize=0x20

0x208001f2 GSP_CRYPTO_CONTROL
  handler=0x01431134 flags=0x100044 psize=0x78

0x20803605 GSP_GDMA_FUZZ_TEST
  handler=0x0140fb1c flags=0x100004 psize=0x10

0x20803606 GSP_CORE_TEST
  handler=0x014314ec flags=0x100044 psize=0x30

0x20800afa INTERNAL_MEMMGR_MEMORY_TRANSFER_WITH_GSP
  handler=0x01361098 flags=0xc0 psize=0x60
```

这说明 GSP 端确实存在这些 handler；但是 host CPU-RM 是否能外部调用，还要看 control flag 和 resource prologue。

重要校正：

- 对 `RMCTRL_FLAGS_ROUTE_TO_PHYSICAL = 0x40` 的 control，在 GSP offload/FW-client 模式下，`rmresControl_Prologue_IMPL` 会先调用 `NV_RM_RPC_CONTROL(...)` 转发到 GSP，并返回 `NV_WARN_NOTHING_TO_DO`；
- 因此 CPU-RM generated HAL 里某个 method body 是 stub，不必然代表该 control 不能到 GSP；
- 真正的前置 gate 是 control path 里的 access / internal / test-only flag。

当前 CPU-RM 侧已经确认：

- `GSP_CORE_TEST`、`GSP_GDMA_FUZZ_TEST`、`GSP_CRYPTO_CONTROL` 都带 `RMCTRL_FLAGS_RM_TEST_ONLY_CODE = 0x100000`；
- 若 `PDB_PROP_SYS_ENABLE_RM_TEST_ONLY_CODE` 未开启，control path 会先返回 `NV_ERR_TEST_ONLY_CODE_NOT_ENABLED`；
- `GSP_CRYPTO_CONTROL` 的 ABI 只包含 RSA/ECDSA/RNG/SHA 输入输出缓冲，不是任意 GSP 函数调用；
- `GSP_CORE_TEST` 的 ABI 是 memory benchmark/copy/invalidate 测试，不带目标函数地址或对象指针。

所以本轮修正后的判断是：

- `GSP_CORE_TEST` 不是因为 CPU stub 而绝对不可达；
- 它最多是 test-only GSP memory benchmark/copy control；
- 它没有表达 `gpio_object/function/selector` 的字段，不是 `0x017fe4b8/0x017fe5b4/0x01802f74` 调用入口。

### `GPIO_ACTIVATE_HW_FUNCTION` 的真实语义

公开 header `/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080gpio.h`：

```c
typedef struct NV2080_CTRL_INTERNAL_GPIO_ACTIVATE_HW_FUNCTION_PARAMS {
    NvU32 function; // in
    NvU32 pin;      // in
} NV2080_CTRL_INTERNAL_GPIO_ACTIVATE_HW_FUNCTION_PARAMS;
```

GSP handler `0x01801fa4` 做的事情：

```asm
01801fa4: ...                    # 从 Subdevice 取 live GPIO object
01801fb2: lw a2, 4(a1)           # a2 = pin
01801fb4: lw a1, 0(a1)           # a1 = function
01801fb6: jump 0x01801ee4        # 内部 activate helper
```

内部 helper `0x01801ee4`：

```asm
01801ef2: li  a5, -1
01801ef4: beq a1, a5, fail       # function == -1 失败
01801ef8: li  a5, 0xff
01801f02: beq a2, a5, fallback   # pin == 0xff 走 getter/比较分支

01801f06: ld  a5, 0x280(gpio_object)
01801f10: mv  a1, function
01801f14: mv  a0, gpio_object
01801f1a: jr  a5                 # 调 GPIO vtable +0x280
```

对当前 GB202 GPIO vtable，`+0x280` 目标是 `0x017f699c`，而 `+0x250` 才是 raw selector method `0x01802f74`。

`0x017f699c` 的关键逻辑：

```asm
017f69aa: ... load line_count
017f69b4: bgeu pin, line_count, fail
017f69c0: offset = pin * 0x0a
017f69ca: lbu a4, 0x724(gpio_object + offset)
017f69ce: bne a4, function, fail
017f69d2: lbu a2, 0x72b(gpio_object + offset)
017f69d6: beqz a2, fail
017f69da: ld  a5, 0x250(gpio_object)
017f69e2: mv  a1, pin
017f69e4: mv  a0, gpio_object
017f69ec: jr  a5                 # 调 raw selector，用已有 0x72b 作为 selector
```

因此 `ACTIVATE_HW_FUNCTION(function,pin)` 不是“设置 function/pin/selector”的 API。它的真实作用更像：

```text
if runtime_record[pin].function == requested_function
   and runtime_record[pin].selector != 0:
       raw_selector(pin, runtime_record[pin].selector)
else:
       fail
```

这解释了之前的实测：

- Lightning GPIO3 runtime record 是 `function=0xff` / `selector=0x00`；
- 调 `ActivateHwFunction(function=0xd1, pin=3)` 不会把 record 改成 `0xd1/0x5c`；
- 它只会看到 record function 不匹配或 selector 为 0，然后失败；
- 所以返回 `0x0000ffff` 一类结果符合 GSP 端逻辑，不是参数写错。

对目标的影响：

- 公开/internal GPIO activate 路线已从“参数缺 selector”加强为“GSP handler 本身也只是消费已有 selector，不创建 selector”；
- 要让它成功，仍必须先让 runtime record 里存在：

```text
record[3].function = 0xd1
record[3].selector = 0x5c
```

- 这仍指向 `0x017fe4b8` / `0x017fe5b4` 这类 record builder/setter，或更上游的 VBIOS/DCB importer；不是重复调用 `ACTIVATE_HW_FUNCTION`。

### RISC-V 层面的边界

GSP 是 RISC-V ELF，指令集和局部函数语义可以静态解码；这也是本节能确认 handler/vtable/record 逻辑的原因。  
但公开 RISC-V ISA 只解决“如何读懂 GSP 代码”，不提供 host CPU 到 GSP 任意 PC 的执行入口。当前缺口仍是 reachability：

```text
host CPU/RM -> 可控 GSP entry -> gpio_object + 参数 -> 0x017fe4b8/0x017fe5b4/0x01802f74
```

目前可见 control/RPC 面没有给出这个入口。

### GSP-only GPIO-ish control `0x2080a304/305/306/30c`

解析整个 GSP dispatch 表得到 1155 个 entry。除了公开 `0x20802300..303` 外，GSP 端还存在几个 GPIO-ish control：

```text
0x2080a304 handler=0x017feb40 flags=0x48 psize=0x84
0x2080a305 handler=0x017f41bc flags=0x48 psize=0x14
0x2080a306 handler=0x017f40c8 flags=0x48 psize=0x14
0x2080a30c handler=0x017fd214 flags=0x48 psize=0x8
```

但在 CPU-RM 公开 generated subdevice table / headers 中没有这些 command ID：

```text
rg "0x2080a304|0x2080a305|0x2080a306|0x2080a30c" ... -> no CPU-RM table/header hit
```

这意味着普通 host RM control lookup 不把它们暴露成正式外部 API。此前 `0x2080a304` 已被本地试过，返回 `0x40` 且没有给出有用 payload；不要再按同样方式重复。

GSP 端语义也不是目标：

- `0x2080a304` 调内部 helper `0x017feacc(gpio_object, function=0x63, max=0x20, out=params+4)`，看起来是在枚举某类 `function=0x63` GPIO line；
- `0x2080a305` / `0x2080a306` 都先检查：

```asm
record_function == 0x63
```

  然后才调用已有 GPIO direction/output/read vtable；
- 它们没有接收 `function=0xd1` 或 `selector=0x5c`；
- 它们也不调用 `0x017fe4b8` / `0x017fe5b4` 创建或改写 runtime record。

`0x2080a30c` 的 handler `0x017fd214` 虽然地址上靠近 `0x017fe4b8/0x017fe5b4`，但 direct-ref 检查没有发现它调用这两个 helper；“靠近”只是代码布局邻近，不是调用关系证据。

本轮结论：

- `0x2080a304/305/306/30c` 不提供 `GPIO3 function=0xd1 selector=0x5c` 的入口；
- GSP dispatch 表里尚未出现一个“公开/半公开 selector set” control；
- 继续方向仍是找能触达 record builder/setter 的更上游 re-import/debug path，或为高风险 live object patch 做前置研究。

### `0x20800a58 DISPLAY_CHANNEL_PUSHBUFFER` 的假阳性/有限意义

全表交叉时发现：

```text
0x20800a58 handler=0x0121b718 flags=0xc0 psize=0x38
```

这个 GSP handler 的代码范围内确实有一段调用：

```asm
0121cb76 -> 0x017fe4b8   # base record helper
0121cb92 -> 0x017fe5b4   # secondary setter
```

局部参数来自一个临时结构 `t6` 的字段：

```asm
lw  a1, -0x314(t6)
lbu a2, -0x304(t6)
...
lbu a3, -0x305(t6)
lbu a2, -0x306(t6)
```

因此它证明“某个 GSP runtime control handler 可以间接触达 GPIO record builder/setter”。但它目前不是可用的目标入口，原因：

1. CPU-RM header 定义该 command 为：

```c
NV2080_CTRL_CMD_INTERNAL_DISPLAY_CHANNEL_PUSHBUFFER = 0x20800a58

typedef struct NV2080_CTRL_INTERNAL_DISPLAY_CHANNEL_PUSHBUFFER_PARAMS {
    NvU32 addressSpace;
    NvU64 physicalAddr;
    NvU64 limit;
    NvU32 cacheSnoop;
    NvU32 hclass;
    NvU32 channelInstance;
    NvBool valid;
    NvU32 pbTargetAperture;
    NvU32 channelPBSize;
    NvU32 subDeviceId;
} ...
```

2. 结构里没有 GPIO function、pin、selector 或 DCB payload；
3. flags 是 `0xc0 = ROUTE_TO_PHYSICAL | INTERNAL`，普通外部 client 不能直接调用；
4. CPU-RM 真实调用点在 `/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/disp/disp_channel.c` 的 `kdispSetPushBufferParamsToPhysical_IMPL()`，用 `pGpu->hInternalClient` 发送显示通道 pushbuffer 元数据；
5. 从 GSP 反汇编看，`0x017fe4b8/0x017fe5b4` 的参数来自 display 内部构造出的临时结构，不来自 host 传入的 command params。

本轮结论：

- `0x20800a58` 是一个重要证据：GSP 的 RM control handler 体系确实可以在运行时调用 GPIO record builder/setter；
- 但它不是任意 GPIO record 写 API，不能表达 `GPIO3 function=0xd1 selector=0x5c`；
- 如果继续利用这类路径，需要找“可控临时结构来源”或另一个 command，而不是直接外部调用 `0x20800a58`。

### direct caller 到 dispatch handler 的全量交叉

把当前已知关键函数的 direct caller 与 GSP 端 1155 个 RM control dispatch handler 做最近邻交叉：

```text
base_record helper 0x017fe4b8 callers:
  0x011812dc / 0x0118146e / 0x0118150e
    no nearby dispatch handler
  0x0121cb76 / 0x0121d6ee
    inside 0x20800a58 DISPLAY_CHANNEL_PUSHBUFFER handler 0x0121b718
  0x01bb24e8 / 0x01bb2d2a / 0x01bb30c0 / 0x01bb3144
  0x01bb3856 / 0x01bb38f8 / 0x01bb394e / 0x01bb3d64
    no nearby dispatch handler

secondary setter 0x017fe5b4 callers:
  0x0118152c
    no nearby dispatch handler
  0x011f11ee / 0x011f12e4
    no nearby dispatch handler
  0x0121cb92
    inside 0x20800a58 DISPLAY_CHANNEL_PUSHBUFFER handler 0x0121b718
  0x0122a69e / 0x0122a6fa / 0x0129484e / 0x01294878
    no nearby dispatch handler

raw selector 0x01802f74 refs:
  only vtable install / method table refs, no direct dispatch handler

GPIO importer 0x01bb0f60:
  only same-function two-stage call, no dispatch handler

FanCooler importer 0x011cd878:
  no nearby dispatch handler
```

当前解释：

- 运行时 RM control 路线目前只找到 `0x20800a58` 这一条会触达 record helper 的实际 handler；
- 该 handler 是 display pushbuffer 内部同步，参数不可表达目标；
- 其它 helper caller 仍归类为 VBIOS/DCB/GPIO importer、fan-management startup/import、对象方法/metadata 或内部状态同步。

这进一步收窄了 route 1：要么找到另一个二跳/间接 handler；要么证明 `0x20800a58` 的临时结构可控；否则仍要转向 live object patch / 初始化输入修改。

#### `0x20800a58` 临时结构来源

继续追 `0x20800a58` 的 `t6` 来源：

```asm
0121c91c..0121c928:
  在 display/channel table 中按 index 查 entry
  s5 = *(entry + 0x2000 - 0x148)

0121c930:
  t6 = s5 + 0x3000

0121caea..0121cb92:
  从 t6 - 0x314, -0x30b..-0x304 读取字段
  调 0x017fe4b8 / 0x017fe5b4
```

这些字段不是 `NV2080_CTRL_INTERNAL_DISPLAY_CHANNEL_PUSHBUFFER_PARAMS` 中的字段，也不是 host 直接传入的 pointer。host command params 在 handler 入口保存为 `s6`，主要用于 pushbuffer 物理地址、limit、hclass、channelInstance、valid 等 display channel 元数据；`t6` 则来自 GSP 内部 display/channel object/table。

所以：

- `0x20800a58` 不是“给一段 payload 就写 GPIO record”的接口；
- 想借它写 `GPIO3 0xd1/0x5c`，需要先能控制 GSP 内部 display table entry 的这些私有字段；
- 这又回到了 object/table patch 级别，不比直接 patch GPIO object 更简单。

## 2026-07-27 继续：RM export table 结构更正与全局 callgraph 去伪

本轮先修正一个表解析问题。GSP 内部 Subdevice export table 的真实 32-byte entry 布局是：

```text
+0x00 NvP64 pFunc
+0x08 NvU32 flags
+0x0c NvU32 accessRight
+0x10 NvU32 methodId
+0x14 NvU32 paramSize
+0x18 NvP64 pClassInfo
```

之前把它误读成 `method/param/class/handler/flags`，会造成 handler 和 method 看起来整体错位一项。按正确布局重扫 `/tmp/gsp_inner_19f040_a.elf`：

```text
entries=1155
first=0x00c15370
last =0x00c1e3d0

0x20800a58 DISPLAY_CHANNEL_PUSHBUFFER
  entry=0x00c17190 psize=0x38 handler=0x0121b718 flags=0xc0

0x20802300 GPIO_PROGRAM_DIRECTION
  entry=0x00c19c70 psize=0x8 handler=0x017f4728 flags=0xc0
0x20802301 GPIO_PROGRAM_OUTPUT
  entry=0x00c19c90 psize=0x8 handler=0x017f47cc flags=0xc0
0x20802302 GPIO_READ_INPUT
  entry=0x00c19cb0 psize=0x8 handler=0x017f486c flags=0xc0
0x20802303 GPIO_ACTIVATE_HW_FUNCTION
  entry=0x00c19cd0 psize=0x8 handler=0x01801fa4 flags=0xc0

0x2080a304 handler=0x017feb40 flags=0x48 psize=0x84
0x2080a305 handler=0x017f41bc flags=0x48 psize=0x14
0x2080a306 handler=0x017f40c8 flags=0x48 psize=0x14
0x2080a30c handler=0x017fd214 flags=0x48 psize=0x8
```

用正确表重跑 RISC-V direct-call graph：

```text
direct target hits:
  base_record      0x017fe4b8: 13 direct calls
  secondary_setter 0x017fe5b4: 8 direct calls
  raw_selector     0x01802f74: 0 direct calls
  activate_method  0x017f699c: 0 direct calls
  fan_importer     0x011cd878: 1 direct call
  gpio_importer    0x01bb0f60: 1 direct call
```

直接从 RM control handler 触达目标 helper 的结果仍只有：

```text
0x20800a58 handler=0x0121b718 -> 0x017fe4b8 depth=1
0x20800a58 handler=0x0121b718 -> 0x017fe5b4 depth=1
```

全局 BFS 还找到 16 条 6-8 层深路径，但候选 method 是：

```text
0x20800a43 INTERNAL_MIGMGR_PROMOTE_GPU_INSTANCE_MEM_RANGE
0x20800aa5 INTERNAL_MIGMGR_SET_GPU_INSTANCES
0x20800aa9 INTERNAL_KMIGMGR_IMPORT_GPU_INSTANCE
0x20800aaa INTERNAL_MIGMGR_IMPORT_GPU_INSTANCE
0x20801121 FIFO_OBJSCHED_SET_STATE
0x2080133b FB_SETUP_VPR_REGION
0x20802a0b CE_GET_ALL_PHYSICAL_CAPS
0x20800190 GSP-private/undocumented, psize=1
```

这些深路径都经过共享对象/初始化链，例如：

```text
... -> 0x0146c964 -> 0x01ada59c -> 0x0118eb34 -> 0x01180e34 -> 0x017fe4b8/0x017fe5b4
```

目前不能把它们当作可用风扇入口，原因是：

- 参数 ABI 是 MIG/FIFO/VPR/CE 等业务对象，不携带 `GPIO3/function=0xd1/selector=0x5c`；
- 深路径是全局静态 callgraph 的“可能调用”，不是 host payload 到 helper 参数的数据流；
- 即使某个业务路径运行时真的能碰到同一 helper，它操作的也不一定是当前 `gpio_object` 或目标 line 3。

本轮更正后的有效结论没有变宽，反而更窄：

1. `ACTIVATE_HW_FUNCTION` 仍只是消费已有 runtime record/selector；
2. GSP-only `0x2080a304/305/306/30c` 仍不提供目标 selector 写入；
3. `0x20800a58` 仍是唯一直接触达 record helper 的 RM handler，但参数不可表达目标；
4. 继续找“外部可控 runtime setter API”的收益下降，下一步应优先找受支持的只读 dump/introspection，或找一个窄范围、可恢复的 live object 定位办法。

## 2026-07-27 继续：GPIO object 指针链与 vtable 调用再校正

本节只读 `/tmp/gsp_inner_19f040_a.elf` 和已有日志；没有打开 GPU 设备、没有读写 BAR/MMIO/FB/WPR/GSP heap。

### `0x041d3f00 -> +0x21a8` 链路状态

`0x01bb0f60` 的入口窗口重新确认：

```asm
01bb0f7e: auipc s7, ...
01bb0f82: addi  s7, s7, ...      ; s7 = &0x041d3f00
01bb0f86: ld    s5, 0(s7)        ; s5 = *(0x041d3f00)
01bb0f8a: c.lui a5, 2
01bb0f94: add   a5, s5           ; a5 = s5 + 0x2000
01bb0fbe: ld    s6, 0x1a8(a5)    ; s6 = *(s5 + 0x21a8)
```

所以当前最佳静态公式仍是：

```text
vbios_table_object = *(0x041d3f00)
gpio_object        = *(vbios_table_object + 0x21a8)
```

这只是对象定位公式，不是可执行入口。它的价值是把后续 live object patch / narrow dump 的目标从“整个 GSP heap”缩到一个二级指针链。

### `0x017fe4b8` / `0x017fe5b4` helper 语义再确认

Capstone 从 `0x017fe4b8` 普通窗口会因为前一段边界不整齐而无输出；启用 skipdata 后可正常反汇编。关键语义：

```asm
017fe4b8: addi t1, zero, 0xfe
017fe4bc: bltu t1, a2, fail        ; function <= 0xfe
017fe4c0: lw   t1, 0x2f8(a0)       ; record_count
017fe4c4: bgeu a1, t1, fail        ; record_index in range
017fe4ce: lw   t1, 0x5a4(a0+0x2000); line_count
017fe4d2: bgeu a3, t1, fail        ; line in range
...
017fe514: sw   a1, 8(t1)           ; function -> record_index
...
017fe55c: sb   a2, 0x724(a1)       ; base function byte
017fe560: sb   a4, 0x725(a1)
017fe564: sb   a5, 0x726(a1)
017fe568: sb   a6, 0x727(a1)
017fe56c: sh   a7, 0x728(a1)
```

`0x017fe5b4`：

```asm
017fe5c2: lw   a4, 0x5a4(a0+0x2000); line_count
017fe5c8: bgeu a1, a4, fail
...
017fe5de: lw   a4, 8(a4)           ; line -> record_index
017fe5e0: lw   a0, 0x2f8(a0)       ; record_count
017fe5e4: bgeu a4, a0, fail
...
017fe600: sb   a2, 0x72b(a5)
017fe604: sb   a3, 0x72c(a5)
```

更准确地说：

```text
0x017fe4b8 = 在已有 GPIO object 内填/补 base record；
0x017fe5b4 = 对已有 line 映射到的 record 写 secondary bytes。
```

它们能表达目标修改，但调用前提仍是 live `gpio_object`、合法 record index、合法 line count、以及进入 GSP 的执行入口。

### GPIO vtable 调用点

收窄搜索 `0x017f0000..0x01810000` 内的 GPIO vtable 间接调用：

```text
slot +0x250:
  load=0x01805b70 call=0x01805b76 object=a0
  load=0x0180cbae call=0x0180cbb8 object=s2

slot +0x280:
  load=0x01805f86 call=0x01805f92 object=a1
```

`0x01802f74` 被写入 GPIO vtable `+0x250`，`0x017f699c` 被写入 `+0x280`。对应 vtable 构造窗口：

```asm
0194247a: materialize 0x01802f74
0194255a: sd t3, 0x250(s1)

019424a2: materialize 0x017f699c
01942572: sd a1, 0x280(s1)
```

`0x01805b30` 只有地址引用，并被放到 GPIO vtable `+0x298`：

```asm
0194235e / 0194258a materialize 0x01805b30
01942366 / 01942592 store to 0x298(s1)
```

这说明它也是 GPIO object 方法之一，不是 host/RM control handler。

### 本轮结论

- `+0x250/+0x280/+0x298` 都是 GPIO object vtable 方法层；
- `ACTIVATE_HW_FUNCTION` 走 `+0x280`，本质是消费已有 `0x724/0x72b` runtime record；
- `+0x250` raw selector 方法确实能写 selector/mux，但调用参数来自 GSP 内部 GPIO object/method chain；
- 目前仍没看到一个 host control 能把任意 `GPIO3 function=0xd1 selector=0x5c` 作为 payload 传进这些 helper；
- 因此“运行时复用启动 importer/helper”理论上成立，但实际还缺 CPU/RM -> GSP 的可控入口。

## 2026-07-27 继续：NVD component 只读矩阵权限结果

构建目录：

```text
/home/user/rt_5090_project/nvdump_matrix_20260727_205840/
```

尝试 component：

```text
5, 6, 7, 8, 9, 12, 15, 27
```

当前 Codex 进程是普通 `user`，所有 component 返回同一状态：

```text
rm_status=0x0000001b (NV_ERR_INSUFFICIENT_PERMISSIONS)
```

注意：日志里的 `NVD_GET_DUMP(FAN)` 是原 probe 的硬编码标签；实际 component 数字是编译时替换的，所以不能按标签理解为所有测试都跑了 FAN。

这个结果不说明 NVD 路线不可用，只说明当前非 root 上下文无法直接抓取。此前 root/tty 抓到过 120 字节 FAN dump，但内容太小，尚未提供 live Fan/GPIO object 指针。

后续如果要在 tty/ssh root 下做只读 NVD 矩阵，已准备通用工具：

```text
/home/user/rt_5090_project/nvdump_component_probe.c
/home/user/rt_5090_project/nvdump_component_probe
/home/user/rt_5090_project/scripts/capture-nvdump-matrix-root.sh
```

编译/语法检查通过：

```text
cc -std=gnu11 -O2 -Wall -Wextra -Wpedantic -Werror
bash -n
```

SHA-256：

```text
f24090e3444100367e79dd423540c427ac271356effa317f8c2ce8839309a258  nvdump_component_probe.c
8f0408eac27a5cc2d80eba5994eec372846580f183c0cd9baaf98abe2ebbccfb  scripts/capture-nvdump-matrix-root.sh
0d13253ddad8852c9d747baa16e8c4d893b9d010397a58c6122757bf75b0f85c  nvdump_component_probe
```

## 2026-07-27 继续：legacy thermal physical controls 排查

GSP RM export 表里除了公开 `0x20800513` thermal execute 外，还有一组 `0x208085xx` legacy/non-privileged physical thermal controls。公开 CPU generated 源码没有完整列出这组 GSP 端 method 名称，因此按 GSP export 表直接枚举。

相关 method：

```text
0x20808501 handler=0x0184a818 psize=0x40c
0x20808513 handler=0x0185fc3c psize=0x598
0x20808524 handler=0x0184a02c psize=0x4
0x2080852a handler=0x018760f4 psize=0x6f8
0x2080852b handler=0x01872b78 psize=0xcfc
0x2080852c handler=0x018766c4 psize=0x5a0
0x2080852e handler=0x012e0480 psize=0x598
0x2080852f handler=0x012e06c8 psize=0x34c
0x20808530 handler=0x012e87a4 psize=0x3d4
0x20808532 handler=0x012f47e0 psize=0x150
0x20808533 handler=0x012f4a0c psize=0x28c
0x20808534 handler=0x012fc198 psize=0x614
0x20808536 handler=0x018702a4 psize=0x63d0
0x20808537 handler=0x012e8f64 psize=0xb3c8
0x20808539 handler=0x0186bb2c psize=0xc9a8
0x2080853a handler=0x0186bafc psize=0x3bf8
0x2080853b handler=0x0186bacc psize=0x37f0
0x2080853c handler=0x01861494 psize=0xc1c
0x2080853e handler=0x01300428 psize=0xc4
0x20808540 handler=0x0185998c psize=0x18
0x20808542 handler=0x01859dd8 psize=0x1f8
0x20808543 handler=0x0186089c psize=0x4c
0x20808544 handler=0x01860a30 psize=0x308
0x20808545 handler=0x0184d78c psize=0x10
0x20808546 handler=0x018599a4 psize=0x18
0x20808547 handler=0x01302fec psize=0x14c
0x20808548 handler=0x01300240 psize=0x10c
0x20808549 handler=0x01862da0 psize=0xc1c
0x2080854a handler=0x0184d884 psize=0x2
0x2080854b handler=0x01859f88 psize=0x2
0x2080854c handler=0x01862f84 psize=0x4fe0
```

粗略用 handler 地址范围过滤 direct calls 时，`0x012f2772 -> 0x011cd878` 会落在若干 handler 范围内；这容易误判。重新定位后：

- `0x012f2772` 是 callsite，不是函数入口；
- 它位于一个大函数中段，最近合理入口是 `0x012f11e8`；
- 近似函数级 callgraph 没有支持 `0x2080852e/2f/30/37` 直接到 `fan_importer` 的路径。

唯一命中的深路径是：

```text
0x2080854a handler=0x0184d884
  -> 0x01b57f90 -> 0x01b5737c -> 0x012ee308
  -> 0x0109b3ac -> 0x01094218 -> 0x0146c964
  -> 0x01ada59c -> 0x0118eb34 -> 0x01180e34
  -> 0x017fe5b4
```

但 `0x2080854a` 的 handler 本体只是读取两个字节：

```asm
0184d884: ld  a5, 0x158(a0)
0184d88a: ld  a5, 0xe0(a5)
0184d88e: ld  a5, -0x58(a5 + 0x2000)
0184d896: lbu a4, 0x3b5(a5)
0184d89c: sb  a4, 0(a1)
0184d8a0: lbu a5, 0x3b6(a5)
0184d8a4: sb  a5, 1(a1)
```

因此它不是初始化/写 GPIO runtime record 的入口。`0x208085xx` 暂时不作为风扇 2/4 启动候选。

## 2026-07-27 继续：root NVD component matrix 与风扇 RM 包差分

本节执行了一次只读 root NVD matrix：

```text
/home/user/rt_5090_project/scripts/capture-nvdump-matrix-root.sh
```

执行边界：

- 只调用 `NV2080_CTRL_CMD_NVD_GET_DUMP`；
- 不写 BAR/MMIO/GPIO/PWM；
- 不读 FB/WPR/GSP heap；
- 不重置/卸载/刷写 GPU；
- 遇到 `NV_ERR_RESET_REQUIRED`、`NV_ERR_GPU_IS_LOST`、`NV_ERR_TIMEOUT` 会停止。

输出目录：

```text
/home/user/rt_5090_project/nvdump_matrix_root_20260727_212524
```

结果：

```text
component 5  DISP    NV_OK  49877 bytes
component 6  FAN     NV_OK    120 bytes
component 7  THERMAL NV_OK    120 bytes
component 8  FUSE    NV_OK    120 bytes
component 9  VBIOS   NV_OK    236 bytes
component 12 PMU     NV_OK    138 bytes
component 15 GPU     NV_OK    239 bytes
component 17 NVD     NV_OK    123 bytes
component 27 GSP     NV_OK    120 bytes
component 28 INFOROM NV_ERR_INVALID_ARGUMENT
component 30 KGSP    NV_OK   4946 bytes
```

注意：`NVDUMP_COMPONENT_ENG_GSP = 27` 仍只有 120 bytes；`NVDUMP_COMPONENT_ENG_KGSP = 30` 是 CPU 侧 KGSP dump，不是 GSP-only component，但它包含 RPC/control history。

主要发现：

- FAN/THERMAL/FUSE/GSP component 都只有通用 120-byte 壳，不能区分 Astral good-state 和 Lightning bad-state；
- DISP component 很大，但搜索 `0x118ab8`、`0x118abc`、`0x208085xx`、GPIO good/bad DCB fragment、`selector=0x5c` 没有直接命中目标；
- KGSP component 的 RPC/control history 确认最近存在大量：

```text
0x2080c531 size=0x3d4
0x20808530 size=0x3d4
```

解析摘要：

```text
/home/user/rt_5090_project/nvdump_matrix_root_20260727_212524/component_30_rpc_history_summary.txt
```

这只证明这些 control 到达/经过了 GSP/RM control 路径；它没有携带 GSP heap pointer、GPIO object pointer 或 FanCooler object pointer。

### `0x20808530` / `0x2080c531` 参数包差分

对已有 NV-CONTROL 风扇设置 trace 做只读差分：

```text
/home/user/rt_5090_project/fan_rm_diff_msi_20260726_024612/set30
/home/user/rt_5090_project/fan_rm_diff_msi_20260726_024612/set40
```

稳定差异：

```text
20808530 set30 -> set40:
  offset 0x24: 00 -> 01
  offset 0x28: 0000 -> 4ccd

2080c531 set30 -> set40:
  offset 0x28: 4ccd -> 6666
```

并且：

```text
set40/20808530 == set30/2080c531
```

解释：

- `0x4ccd` 是约 30% 的 16-bit fraction；
- `0x6666` 是约 40% 的 16-bit fraction；
- `0x20808530` 像读取/同步当前 fan target 状态；
- `0x2080c531` 像提交新的 fan target duty；
- 这组包里没有 fan controller count、GPIO selector、DCB entry、PWM mux 或 FanCooler create payload。

额外差分：

- `0x2080852e` 在 set30/set40 完全相同，更像静态能力/结构信息；
- `0x2080852f` 的差异集中在尾部运行时状态/指针样字段和少量当前 duty 字段，噪声较大；没有表现为拓扑补建 payload。

本轮结论：

- `0x20808530/0x2080c531` 是“已有 fan target 的转速状态/设定”路线，不是“建立第二路 FanCooler/GPIO3/PWM11”的路线；
- 这解释了为什么 `RmFan2XOverride` 和普通风扇设置可以改变已注册 controller0，却不能让 2、4 号风扇启动；
- 后续不应继续把这组 control 当作拓扑初始化入口。

## 2026-07-27 继续：raw selector vtable caller 反查

本节只读 GSP ELF；没有打开 GPU 设备、没有读写 BAR/MMIO/FB/WPR/GSP heap。

目标是确认是否存在 RM handler 直接暴露 raw selector method `+0x250`。

已知 raw selector method：

```text
0x01802f74
```

已知 `+0x250` 间接调用点：

```text
0x01805b70 -> ld a5, 0x250(a0)
0x01805b76 -> jalr a5

0x0180cbae -> ld a5, 0x250(s2)
0x0180cbb8 -> jalr a5
```

局部语义：

- `0x01805b30` 附近会从已有 runtime record 的 `0x72b/0x72c` 读取 selector/辅助字节，然后调用 raw selector；
- `0x0180cb5c` 附近是 GPIO object method chain，参数来自内部对象/结构，不是 RM payload；
- 两者都不是“传入 pin/function/selector 并设置”的公开控制入口。

strict direct refs：

```text
0x01942250 -> 0x01805908 address via 0x01942254 (a4)
0x019426a0 -> 0x01805908 address via 0x019426a4 (a5)
0x01942328 -> 0x01805a5c address via 0x0194232c (a4)
0x0194278c -> 0x01805a5c address via 0x01942790 (a0)
0x0194235e -> 0x01805b30 address via 0x01942362 (a4)
0x0194258a -> 0x01805b30 address via 0x0194258e (a5)
```

`0x0180cb5c` 没有 strict direct ref。

结论：

- 这些 raw-selector 消费函数目前只看到 GPIO vtable/method-table 安装引用；
- 没有看到 RM control handler 直接调用；
- raw selector 仍是“内部可执行方法”，不是 host 可直接调用的 selector-set API；
- 后续不要把 `+0x250` 当成已找到的运行时入口，它仍需要先解决 GSP 内部 reachability 和 live `gpio_object` 指针。

## 2026-07-27 继续：RM method table 全表关键函数命中

本节只读 GSP ELF 和公开 RM source；没有打开 GPU 设备、没有读写 BAR/MMIO/FB/WPR/GSP heap。

目的：验证是否有任何 host/RM control handler 直接调用以下关键函数，而不是只在 `0x208085xx/0x2080c5xx` 邻域里找：

```text
0x017fe4b8  GPIO base record helper
0x017fe5b4  GPIO secondary setter
0x01802f74  raw selector method
0x011cd878  FanCooler importer
0x012f2772  FanCooler importer caller
0x01b835ec  FanCooler child allocator
0x01bb0f60  GPIO importer/state-machine
```

扫描范围是 GSP RM method table：

```text
table file offsets 0x00c15370..0x00c1e3f0
entries parsed: 1156
```

结果文件：

```text
/home/user/rt_5090_project/full_method_table_key_function_hits_20260727.txt
```

唯一命中：

```text
0x20800a58 handler=0x0121b718 call@0x0121cb7a -> 0x017fe4b8 GPIO base record helper
0x20800a58 handler=0x0121b718 call@0x0121cb96 -> 0x017fe5b4 GPIO secondary setter
0x20800a58 handler=0x0121b718 call@0x0121d6f2 -> 0x017fe4b8 GPIO base record helper
```

没有任何 RM method handler 直接命中：

```text
0x01802f74 raw selector
0x011cd878 FanCooler importer
0x012f2772 FanCooler importer caller
0x01b835ec FanCooler child allocator
0x01bb0f60 GPIO importer/state-machine
```

`0x20800a58` 在公开 header/source 中是：

```text
NV2080_CTRL_CMD_INTERNAL_DISPLAY_CHANNEL_PUSHBUFFER
subdeviceCtrlCmdDisplaySetChannelPushbuffer
```

参数结构 `NV2080_CTRL_INTERNAL_DISPLAY_CHANNEL_PUSHBUFFER_PARAMS` 只包含 display pushbuffer 的 addressSpace、physicalAddr、limit、cacheSnoop、hclass、channelInstance、valid、pbTargetAperture、channelPBSize、subDeviceId。它没有 fan index、GPIO function、GPIO selector、DCB fragment、PWM id 或 FanCooler create payload。

本轮结论：

- 全表级别没有发现一个可直接把 `function=0xd1`、`selector=0x5c` 或 FanCooler child payload 送入 GSP 的 RM control；
- `0x20800a58` 虽然内部触达 GPIO record helper，但它是 display channel pushbuffer 路线，属于 display/SLI-link GPIO 辅助逻辑，不是 board-fan GPIO3/PWM11 拓扑初始化入口；
- 这强化了当前边界：正常 host/RM control 面还没有找到“补建 Lightning 缺失第二路 fan controller”的直接入口。

### 间接调用闭包补充

第一版全段 Capstone 扫描从 ELF/header 起始处连续反汇编会停在无效数据，结果不可用；已用 `skipdata` 重跑完整 executable PT_LOAD。

结果文件：

```text
/home/user/rt_5090_project/key_gpio_fan_reverse_callers_20260727.txt
```

完整 executable 静态扫描规模：

```text
instructions: 5263700
direct_calls: 212733
target_rows: 17
```

关键 direct callsite 中，落在 RM method handler 范围内的只有：

```text
0x20800a58 handler=0x0121b718 flags=0xc0
  call@0x0121cb7a -> 0x017fe4b8 GPIO base record helper
  call@0x0121cb96 -> 0x017fe5b4 GPIO secondary setter
  call@0x0121d6f2 -> 0x017fe4b8 GPIO base record helper

0x20800ac9 handler=0x011ebccc flags=0xc0
  call@0x011f11f2 -> 0x017fe5b4 GPIO secondary setter
  call@0x011f12e8 -> 0x017fe5b4 GPIO secondary setter
```

`0x20800ac9` 在公开 header/source 中是：

```text
NV2080_CTRL_CMD_INTERNAL_GSYNC_IS_DISPLAYID_VALID
subdeviceCtrlCmdInternalGsyncIsDisplayIdValid
```

参数结构 `NV2080_CTRL_INTERNAL_GSYNC_IS_DISPLAYID_VALID_PARAMS` 只有：

```text
NvU32 displays;
NvU32 displayId;
```

所以它同样是 display/G-SYNC 内部路线；没有 fan index、GPIO function、selector、DCB fragment、PWM id 或 FanCooler create payload。

其它 direct callsite：

- `0x011812e0`、`0x01181472`、`0x01181512`、`0x01181530` 等不落在 RM method handler 范围，属于启动/内部 GPIO 构造路线；
- `0x011cdd00`、`0x011ce438`、`0x012f296e`、`0x012f2afa` 是 FanCooler allocator 的启动/导入路线；
- 没有 host-callable handler 直接或在这一层闭包内到达 FanCooler importer / raw selector。

补充结论：

- “handler -> 中间函数 -> GPIO helper”的低阶间接路线目前也没有出现可用 fan topology 入口；
- 仅有命中都属于 display/G-SYNC internal control，仍不能用来补建 Lightning 缺失的第二路 board-fan controller。

## 2026-07-27 继续：NVD FAN dump 降级

复核 `NVDUMP_COMPONENT_ENG_FAN` 输出：

```text
/home/user/rt_5090_project/nvdump_matrix_root_20260727_212524/component_6.pb
size: 120 bytes
sha256: 5c1c9a15fffa0d522f726b7b918eaafef80b48bdd29939a49395cbe4bacbf7cc
```

它与以下 component 完全同 SHA：

```text
component_7.pb   THERMAL
component_8.pb   FUSE
component_27.pb  GSP
```

wire decode 只有固定 wrapper/通用字段，没有嵌套 fan/cooler record、BoardObjGrp mask、child index、PWM id、GPIO function/selector 或 live pointer。

因此 `NV2080_CTRL_CMD_NVD_GET_DUMP` / `DUMP_PROTOBUF_COMPONENT` 路线当前降级：

- 它证明 GSP FAN component 可以被公开 NVD 诊断 RPC 调用；
- 但 610.43.03 当前 build 的 FAN component 没有输出 FanCooler/FanTarget 对象内容；
- 继续对这个 120-byte protobuf 猜字段没有意义；
- 若后续继续 NVD，只应寻找另一个明确输出 BoardObjGrp 的 component/debug path，而不是重复 component 6。

## 2026-07-27 继续：debug/test control ABI 复核

筛 `g_subdevice_nvoc.c` 中 method name/param name 的 debug、GSP、RPC、memory、object 等关键词，结果保存：

```text
/home/user/rt_5090_project/subdevice_method_keyword_map_20260727.txt
```

几个看似相关的 control 复核如下。

`NV2080_CTRL_CMD_GPU_RPC_GSP_TEST = 0x208001e8`：

- ABI 是 `test/dataSize/startTimestamp/stopTimestamp/data`；
- source 注释说明它只检查固定 pattern 并回填另一个固定 pattern；
- GSP-client 模式下 serialized test 调的是当前 RM control 自己，unserialized test 固定转 `NV2080_CTRL_CMD_GPU_GET_IP_VERSION`；
- 它不是“任意 RPC function id + payload”通道。

`NV2080_CTRL_CMD_GPU_RPC_GSP_QUERY_SIZES = 0x208001e9`：

- 只返回 `maxRpcSize/finnRmapiSize/rpcGspControlSize/rpcMessageHeaderSize/timestampFreq`；
- 不能读/写 GSP heap 或调用 GSP function。

`NV2080_CTRL_CMD_INTERNAL_MEMMGR_MEMORY_TRANSFER_WITH_GSP = 0x20800afa`：

- ABI 是 source/destination transfer surface 的 physical base/size/offset/aperture/caching + memcpy/memset；
- 不是 GSP private heap VA 访问器；
- 之前当前配置下实现路径已确认返回 `NV_ERR_NOT_SUPPORTED`。

`NV2080_CTRL_CMD_INTERNAL_CONTROL_GSP_TRACE = 0x208001e3`：

- ABI 是 tracepointMask、physical buffer、size/watermark、start/stop flag；
- 用于 GSP trace logging，不提供 arbitrary object lookup 或 heap read/write。

`NV2080_CTRL_CMD_GSP_CRYPTO_CONTROL = 0x208001f2`：

- ABI 是 RSA/ECDSA/RNG/SHA crypto 操作；
- 不提供 GSP object/heap 访问。

本轮结论：

- 公开/内部 debug/test control 里没有发现可变 function-id 的 GSP RPC invoke；
- 也没有发现以 GSP VA 为输入的安全 heap/object reader；
- 当前仍然没有正常 RM ABI 可以把 host 参数送到 GPIO helper / FanCooler importer。

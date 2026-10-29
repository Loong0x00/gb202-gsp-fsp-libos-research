# MODS 570.151 ordinary write filter 对 GB202 fuse/L2 目标的静态核对

## 范围与证据等级

本文只分析固定样本
`mods_audit/static/extracted_inner/mods`（SHA-256
`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`）、
已有解码脚本 `mods_audit/static/decoded/gpuargs.js` 和少量有界反汇编窗口。
没有执行 MODS，没有访问 GPU、BAR0/MMIO、PCI config、设备节点或 debugfs。

- **FACT**：固定指令、BSS/rodata 布局或解码 JS 直接证明；
- **INFERENCE**：由这些固定关系推出，但未观察实际进程状态；
- **UNKNOWN**：依赖调用者输入或运行时表，当前静态样本不能决定。

本文的“默认”严格指固定包内的默认 JS 状态及随包 `init.arg`、`bringup.arg`、
`dev.arg`，不代表任意外部命令行、policy 文件或实验室启动框架。

## 结论先行

1. **FACT：`0xd9aac0` 本体不是编译进函数的芯片寄存器黑名单。** 它线性查询
   一个运行时 vector；每项是 4 个 `u32`：
   `(GpuInst, inclusiveStart, inclusiveEnd, writableBitMask)`。函数体没有
   `0x8234e0`、`0x820040`、`0x8200dc`、`0x8200f8` 或 `0x8212ac` 的特判。
2. **FACT：表项语义如下。** 无匹配返回 `0xffffffff`，ordinary writer 原值
   全写；匹配且 mask 为 0 时整次 write 被排除；其他 mask 先读旧值，只允许
   mask 中为 1 的位采用 requested value。
3. **FACT：JS 可见的配置源是 `-reg_write_mask`。** `g_RegWrMask` 默认构造为
   空数组；`ArgRegMask` 才向其中追加范围，`HandleGpuPreInitArgs` 随后把数组交给
   `Gpu.WriteExclusionRegions`。三个随包 `.arg` 文件均没有该选项或本项目目标
   地址。
4. **强 INFERENCE（默认包流）：** 默认没有外部参数/policy/native 注入时，
   表为空，五类目标均返回 `-1`，所以不会被这一层默认排除或施加部分 write
   mask。严格的任意运行时结论仍是 **UNKNOWN**，因为外部命令行或其他调用者
   可以动态添加覆盖这些地址的范围。
5. **FACT：lookup 看到的是最终 translated offset，不是 raw thunk 收到的
   未解析 offset。** GB20x raw 路径先做可选 exact-address remap，再解析
   domain/instance base，进入 `0xdc74f0` 后又做一次 exact remap，然后才调用
   `0xd9aac0`。remap tree 的静态初始化值为 empty，固定 executable 中唯一
   direct setter caller 又闭合到显式 `-reg_remap` 的 JS callback；随包参数没有
   该选项。因此 stock/default 流中的两次 exact remap 都可高置信视为 identity。
   domain base 本身还有两种来源：PTOP DeviceInfo2 class `0x10` 若为空，固定
   selector 的 instance0 fallback 是 `0x820000`，relative `0x34e0..0x34fc`
   便解析成 `0x8234e0..0x8234fc`；若该 class 存在，则取硬件 record 的
   instance0 `devicePriBase`。filter 比较的是该 runtime base 加 relative key
   后的值。本卡 DeviceInfo2 数值与任意未观察外部 argv/state 仍为 UNKNOWN。
6. 这张 host-side 表与 RegHal `accessOffset`/PLM metadata 完全是两层机制。
   默认不屏蔽不表示设备侧 PLM 会接受写入，更不表示写入安全或能传播到
   effective topology。

## 1. `0xd9aac0` 的精确表结构

有界窗口 `0xd9aac0..0xd9aafd`：

```text
begin = *(u8 **)0x186e00c0
end   = *(u8 **)0x186e00c8

for (p = begin; p != end; p += 0x10) {
    if (p->word0 != gpuInst)
        continue;
    if (translatedOffset < p->word1)
        continue;
    if (translatedOffset > p->word2)
        continue;
    return p->word3;
}
return 0xffffffff;
```

`0x186e00c0/0x186e00c8` 位于 `.bss`，即 executable 不携带 link-time data
表项。这一点证明 lookup 本体没有静态 data table；它不能单独排除其他 native
初始化代码或启动输入在运行时填表。

调用点 `0xdc7506..0xdc752e` 提供：

```text
gpuInst         = *(GpuSubdevice+0x128)+0x70
translatedOffset = r12d
mask            = lookup(gpuInst, translatedOffset)
```

虽然 caller 还把 `0x186e01c0` 放入 `RDI`，`0xd9aac0` 的固定函数体不读取
`RDI`；真正判定只使用 `ESI=gpuInst`、`EDX=translatedOffset` 和全局 vector。

## 2. writer 对返回值的消费语义

`0xdc7520..0xdc7546` 精确区分三个情况。

### 2.1 mask 为 0：整次排除

`test eax,eax; je 0xdc7670` 直接跳到日志：

```text
GpuSubdevice::RegWr32(%08x, %08x) excluded.
```

该路径不进入 mapped-aperture store 或 RM reg-ops write。

### 2.2 mask 为 `0xffffffff`：不做合并

caller 把 `0xffffffff` 当作“不命中范围”，直接保留 requested value。即使调用者
显式配置了全 1 mask，效果也与无表项相同：全部 32 位可由 requested value
覆盖。

### 2.3 其他非零 mask：先读旧值再合并

`0xdc7530..0xdc7544` 的指令等价于：

```text
new = old ^ ((old ^ requested) & mask)
    = (old & ~mask) | (requested & mask)
```

所以 `mask` 的 1 bit 是**允许写的新值位**，0 bit 保留旧值。它不是常见的
“1=禁止写”命名方式。

若多个范围重叠，`0xd9aac0` 按 vector 顺序返回第一个匹配项；函数本身不做
优先级合并。

## 3. 运行时表从哪里来

解码的 `gpuargs.js` 给出完整 JS 侧生命周期：

```javascript
ARG_STATE_VARIABLE(g_RegWrMask, new Array());

AddArg("reg_write_mask", FUNC1, "ArgRegMask", ...);

function ArgRegMask(DevInst, regargs) {
    // addr                -> [addr, addr], mask 0
    // addr,mask           -> [addr, addr], supplied mask
    // addr1,addr2,mask    -> inclusive ordered range, supplied mask
    g_RegWrMask.push({
        GpuInst: DevInst,
        Addr1: reg1,
        Addr2: reg2,
        Bitmask: Mask
    });
}

VIRTUAL_FUNCTION(HandleGpuPreInitArgs)() {
    ...
    Gpu.WriteExclusionRegions(g_RegWrMask);
    ...
}
```

因此以下是可分开的结论：

- **FACT：** JS 初值为空；只有收到 `-reg_write_mask` 才由 `ArgRegMask` push；
- **FACT：** 固定包的 `init.arg`、`bringup.arg`、`dev.arg` 没有该选项；
- **FACT：** 项目可读文本参数/JSON 中没有针对五类目标的 `reg_write_mask`；
- **INFERENCE：** 无外部参数或额外 native/policy 注入的普通启动会保持空表；
- **UNKNOWN：** 某次实际运行的完整外部 argv、policy 脚本或其他 native caller
  是否添加过表项。本轮未运行样本、也未读取进程内存。

换句话说，这一层可以由启动者主动用作保护，但不是固定样本对 fuse/L2 目标
自动提供的保护。

## 4. raw writer 到 lookup 的地址形态

### 4.1 raw thunk 保留 domain 与 offset，wrapper 再解析

`ProgramSwFusePlan` 在 `0x1516053..0x151606b` 传给 handler `+0xb8` 的主要参数是：

```text
ESI = plan/device instance
EDX = 5                         # logical domain
R8D = plan raw offset
R9D = requested raw value
```

`0x151ad00` 只换成 `GpuSubdevice` 对象后 tail-call `+0x238`。GB202 绑定
`+0x238 = 0xdb5540`，后者的顺序是：

```text
O1   = d99930(rawOffset)        # optional exact-address remap
base = vtable+0x218(domain=5, instance, context)
T    = O1 + base
tail-call vtable+0x230(T, value)
```

GB202 的 `+0x218` 是 `0x125b720`，不是 generic `0xdb4080` stub。domain 5
分支 `0x125c1f6` 传入 class `0x10`、instance 和 RegHal base-selector ID
`0x10ef4000`。`0x1252200` 会先检查延迟建立的 PTOP DeviceInfo2 class-vector：
有记录时按 instance 返回硬件 `devicePriBase`；无记录时才使用固定 selector。
固定 GB202 表解码为：

```text
index 0 -> 0x00820000
index 1 -> 0x00bf0000
```

同一固定 RegHal 表把 raw L2 read ID `0x1087c000` 的 domain-5 offsets 编码为：

```text
index 0..7 -> 0x34e0, 0x34e4, ... 0x34fc
```

所以 fixed-selector fallback 的解析关系是：

```text
0x820000 + (0x34e0 + 4*FBP) = 0x8234e0 + 4*FBP
```

### 4.2 ordinary backend 在 filter 前还有一次 remap

`+0x230 = 0xdc74f0` 一进入便再次调用 `0xd99930`：

```text
F = d99930(T)
mask = d9aac0(gpuInst, F)
```

于是严格答案是：

- raw thunk 的 API 仍携带 logical domain、instance 和 raw offset；
- `0xd9aac0` 不看原始三元组，而看解析后、并再次 exact-remap 后的最终 offset；
- identity/no-remap 的主 fuse domain 路径中，最终值就是绝对 BAR0 offset；
- 若显式 `-reg_remap fromAddr toAddr` 或其他 runtime remap 已安装，lookup 比较
  remap 后地址。raw wrapper 前后的两次 `d99930` 还允许相对 offset 和解析后
  absolute offset 分别成为 exact-remap key。

后续 lifecycle 审计把这里的 default 假设进一步闭合：tree 初始化器明确把
root/size 清零；setter `0xda1670` 的完整 direct-call scan 只命中
`Gpu.RemapRegister` callback `0x1162276`；全部解码 JS 又只从显式
`ArgRegRemap` 调用它，随包参数没有 `-reg_remap`。所以“stock/default 时两次
identity”是高置信结论，而不再只是因为没观察到 remap；任意外部 argv 或动态
注入仍为 UNKNOWN。见 `parallel/reg_remap_lifecycle.md`。

这也修正了一个容易混淆的说法：不能简单写成“raw plan integer 原样就是最终
BAR0 地址”。可证明的是最终访问与 filter key 解析为 `0x8234e0..0x8234fc`；
plan 节点的输入 offset 与 domain base 是分层传递的。

## 5. 五类目标的默认判定矩阵

下表只回答 `0xd9aac0` 这一层，不回答设备 PLM 或 firmware 是否允许。

| 最终 identity key | 本路径角色 | lookup 本体地址特判 | 默认包流 | 外部配置后 |
|---|---|---:|---|---|
| `0x8234e0..0x8234fc` | raw OPT L2 mask | 无 | **不排除、不掩码（强 INFERENCE）** | 可被单地址或范围 mask 覆盖 |
| `0x820040` | software-override latch | 无 | **不排除、不掩码（强 INFERENCE）** | 可动态排除/掩码 |
| `0x8200dc` | raw L2 access PLM | 无 | **不排除、不掩码（强 INFERENCE）** | 可动态排除/掩码 |
| `0x8200f8` | latch access PLM | 无 | **不排除、不掩码（强 INFERENCE）** | 可动态排除/掩码 |
| `0x8212ac` | `disable_sw_override` state | 无 | **不排除、不掩码（强 INFERENCE）** | 可动态排除/掩码 |

“lookup 本体地址特判为无”是 **FACT**：函数没有目标常量且 vector 位于 BSS；
“默认包流不命中”是强 **INFERENCE**：JS 默认空且随包参数不填表，但尚未穷尽
所有 native writer；“任意一次运行是否命中”仍是 **UNKNOWN**。

对 latch，现有 `0x404f0001` RegHal constant RMW 最终会汇入同一 ordinary
writer family，所以会经过本表。对 `0x8200dc/0x8200f8/0x8212ac`，本矩阵只说明
**如果**某 ordinary writer 把它们作为最终 key 交给 `0xdc74f0` 时，本通用表
不会静态特判；它不声称当前 direct-shadow 流程实际有这些寄存器的 host writer。

## 6. 与 PLM/安全结论的边界

该通用表是 host 自选的防误写层。raw plan 不走 RegHal descriptor/accessOffset
预检，而 `d9aac0` 默认包流又没有目标范围，因此它不能替代：

- `0x8200dc` 对 raw L2 shadow 的设备侧访问裁决；
- `0x8200f8` 对 `0x820040` latch 的设备侧访问裁决；
- `0x8200fc` 对 `0x8212ac` 读取侧 metadata；
- FSP/GSP、firmware 或硬件对 floorsweep 状态的接受与传播。

最终安全含义是负面的：**没有发现这一层默认挡住目标写入，也没有发现这一层
授予目标权限。** 它只是一个默认空、可由启动参数动态配置的 host filter。
因此这项静态结论不能降低实卡写入、reset 或 disabled-unit health 的风险门槛。

## 7. offset representation erratum：JSON/plan key 是 domain-relative

这里需要显式纠正主报告和离线校验器中的一处表示法混淆。下述 relative-key
结论适用于 domain-5 的 DeviceInfo2 与 fixed-selector 两种 base 来源；数值
`0x8234e0..fc` 则是 fixed-selector instance0 fallback 的展开结果。

### 7.1 结论

- **FACT：** `FuseJsonParser2` 接受的 integer `offset`、descriptor `+0x8c`、
  encoder 生成的 plan node `+0x20` 是同一个、未加基址的 32-bit 数值。
- **FACT：** `ProgramSwFusePlan` 把 node `+0x20` 与 `domain=5` 分开传递；
  GB202 raw wrapper 随后为它加上 domain/instance base。
- **FACT（固定 GB202 表、instance0 fallback）：** 该 fallback base 是
  `0x820000`，因此 L2 八个 plan offset `0x34e0 + 4*FBP` 在这条分支展开为
  `0x8234e0 + 4*FBP`。若 PTOP class `0x10` 已填充，runtime 结果则是
  `devicePriBase(instance0) + 0x34e0 + 4*FBP`。
- 所以“plan/JSON integer 直接填 `0x8234e0..0x8234fc`”是错的。wrapper 无论
  选 DeviceInfo2 还是 fixed fallback 都会再加一个非零 domain base；fallback
  下 FBP0 会变成 `0x10434e0`，而不是 `0x8234e0`。

### 7.2 parser 没有替 integer offset 做基址换算

`FuseJsonParser2` 的 Chip-options record parser 位于
`0xcbbf70..0xcbc941`，`offset` key 字符串为 `0x90c37ec`。对 JSON
integer 分支：

```text
0xcbc948..0xcbc964  取得 offset 节点，mov eax, [node]
0xcbc966             mov [rsp+0xdc], eax
0xcbc5a1             mov rax, [rsp+0xdc]
0xcbc5a9             mov [descriptor+0x8c], rax
```

整条分支没有 `add/sub 0x820000`，也没有按数值范围区分 absolute/
relative 的特判。字符串形式则在 `0xcbc3cc..0xcbc40c` 转为数值后写入
同一个 `[rsp+0xdc]`；其 helper `0xc9d990` 解析十进制地址及可选 bit
range，也没有 fuse-aperture 基址换算。

这一点对现有 `gb202_fjson_offline.py` 尤其关键：它强制目标 `offset`
必须是 JSON integer，而该 integer 分支已经直接证明为原样复制。

### 7.3 descriptor 到 plan node 也没有换算

encoder `0x148b4c0` 的固定数据流是：

```text
0x148b62e  eax = [descriptor+0x8c]
0x148b635  [rsp+0x60] = eax
0x148b72d  ebp = [rsp+0x60]          # map key
0x148b748  compare [plan-node+0x20], ebp
0x148b76b..0x148b790                 # 新节点也以该 key 构造
0x148b797  [plan-node+0x24] = value
```

plan combiner `0x147b4b0` 在 `0x147b6e8` 和 `0x147b900` 分别取两输入图的
`[source-node+0x20]`，用同值在输出图查找/插入；已审计窗口中也没有
基址归一化。`0x1471530` MultiMacro 调度只选择/调用 per-macro
encoder，没有对 key 做 `0x820000` 级别的算术处理。

`ProgramSwFusePlan` 最后在 `0x1516018..0x151602a` 原样读出 node
`+0x24/+0x20`，并在 `0x1516053..0x151606b` 传递：

```text
EDX = 5
R8D = node+0x20
R9D = node+0x24
```

### 7.4 domain base 只在 raw wrapper 解析阶段加一次

GB202 `+0x238 = 0xdb5540` 先对 `R8D` 做可选 exact remap，然后调
`+0x218` 解析 `(instance, domain, context)`，在 `0xdb5682` 执行：

```text
resolved = remappedPlanOffset + domainBase
```

GB202 `+0x218 = 0x125b720` 的 domain-5 jump-table 入口是 `0x125c1f6`，
它把 class `0x10`、instance 和 selector ID `0x10ef4000` 交给 `0x1252200`。
若 DeviceInfo2 class-vector 为空，固定 RegHal 表对 instance0 返回
`0x820000`。与 raw L2 ID `0x1087c000` 的 relative rows
`0x34e0..0x34fc` 组合后，fallback 为：

```text
plan/descriptor offset = 0x34e0 + 4*FBP
fixed fallback base    = 0x820000
fallback BAR0/filter   = 0x8234e0 + 4*FBP
```

后续独立复核还把这里的 instance 0 来源闭合：普通 GB20x factory 在
`0x1431fd5` 把 constructor 第三参数清零，`0x1517df0` 将其保存到 accessor
`+0x8`，`ProgramSwFusePlan` 再从该字段传出。新的 alternate-branch lifecycle
审计则证明，它不是外部预建 map，而是 GpuSubdevice 延迟解析 PTOP DeviceInfo2
形成的硬件拓扑缓存：class `0x10` 非空时，仍用 instance0 查 record，但改取
`devicePriBase`，不再使用 selector；class 为空才走上述 fallback。完整链见
`parallel/fuse_domain_instance.md` 与
`parallel/fuse_instance_map_lifecycle.md`。本卡没有 live table capture，故不能
把 `0x820000` 称作本卡已观察的 runtime row；不过公开 610 的 GB202 primary
FUSE getter 也无状态地固定返回 `0x820000`，所以正常 row 有很强的产品不变量
理由与 fallback 一致。未来校验器应验证这一点，而不是信任异常值。见
`parallel/deviceinfo_reset_stability.md`。这不改变 key 必须是 domain-relative。
另一个 bounded follow-up 证明了异常边界：class 非空但
缺 requested instance0 时，lookup 不报错/不 fallback，而会把
`vector.end()+0x18` 的越界 dword 当 base 继续使用；正常 GB202 table 是否可能
违反该不变量仍为 UNKNOWN。见 `parallel/deviceinfo_instance_nomatch.md`。
同一串行 plan 内，latch RMW 最早可建立该 cache，之后所有 raw write/readback
都复用同一 snapshot；`ProgramSwFusePlan` 不含 invalidator/reset。因此 runtime
row 虽未 live capture，但正常单次 plan 内不会逐项漂移；post-program reset 也
保留同一 cache owner/snapshot。见 `parallel/deviceinfo_cache_writer_timing.md`
与 `parallel/postreset_deviceinfo_cache_lifetime.md`。

所以普通 writer ABI 并不需要一个“避免 double-add”的隐藏 special case：
**若要让这条 ordinary/default 路径命中目标，descriptor/plan key 必须是
domain-relative，wrapper 再在解析成最终 BAR0 时加一次 base。** 这句话描述的
是已恢复 ABI 的必要输入，不等于声称已经看见原厂 `gb202_f.json` 中的实际记录。

### 7.5 对现有文档/工具的更正评估

1. **`gb202_fjson_offline.py` 已更正。** 旧常量
   `GB202_L2_RAW_OFFSETS = 0x008234E0 + 4*FBP` 会把真正符合该 writer ABI 的
   relative integer 误报为错误，反而接受会在 default writer 中被再加基址的
   absolute integer。当前校验目标已改为 `0x34e0 + 4*FBP`，并用独立字段只报告
   fixed-selector fallback BAR0 `0x820000 + relativeOffset`；工具同时声明 runtime
   DeviceInfo2 base 未被它验证。
2. **主报告的 plan/JSON 措辞已更正。**
   `L2_REENABLE_STATIC_FINDINGS.md` 不再把 plan item/JSON integer 直接写成
   `0x8234e0 + 4*FBP`，而明确区分 relative `0x34e0 + 4*FBP`、runtime base
   解析和 fixed-selector fallback BAR0。
   raw register 的物理 `0x8234e0..0x8234fc` 地址仍有独立 GSP/RegHal 证据；但
   ordinary MODS resolver 的 filter key 必须按实际 DeviceInfo2/fallback base
   描述，不能再把 fixed fallback 数值冒充本卡已观察的 runtime table 结果。

主报告与两只离线校验/解码工具现已同步该 erratum。实际 NVIDIA
`gb202_f.json` 仍未获得，因此无法用原厂文件做内容级交叉验证；
但对“JSON integer -> descriptor -> plan node -> domain-5 wrapper”这条固定
ABI 数据流，表示法结论已是 **FACT**。它不改变 PLM、firmware、
security level 或 disabled-unit health 仍然未知的安全边界。

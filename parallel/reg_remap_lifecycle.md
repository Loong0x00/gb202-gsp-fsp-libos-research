# MODS 570.151 exact-address remap lifecycle

日期：2026-07-21

## 范围与安全边界

本文只对固定样本 `mods_audit/static/extracted_inner/mods`、随包解码
JavaScript 和参数文件做离线静态核对，目标是闭合 raw writer 地址推导中
`0xd99930` remap tree 的默认状态与写入来源。没有执行 MODS，没有访问 GPU、
设备节点、BAR/MMIO、PCI config 或驱动，也没有生成可用于硬件写入的配置。

- **FACT**：由固定指令、BSS 初始化、完整 direct-call/pointer scan 或随包文本
  直接证明；
- **INFERENCE**：由已闭合的 stock 数据流推出，但不声称覆盖外部动态模块或
  未保存的任意命令行；
- **UNKNOWN**：固定包不能决定的外部输入或运行时注入。

## 结论先行

1. **FACT：remap tree 启动时为空。** 静态初始化器 `0x7b31a3..0x7b31dc`
   明确把 root `0x186e00f0` 和 size `0x186e0108` 写成 0，并把 header 的
   left/right 指回 `0x186e00e8`。
2. **FACT：固定 executable 中，map setter `0xda1670` 只有一个 direct caller：**
   JavaScript native callback `0x1162276`。完整 `.text` direct-`CALL rel32`
   扫描只命中这一处；完整文件的 exact 32/64-bit pointer scan没有找到保存的
   setter 指针。
3. **FACT：该 native callback 就是 `Gpu.RemapRegister(fromAddr,toAddr)`。**
   注册点 `0x7cc425..0x7cc445` 把字符串 `0x90d2717 = "RemapRegister"`、
   arity 2 和 callback `0x11621c0` 绑定到 `Gpu` 对象。
4. **FACT：随包 JavaScript 只有命令行 handler 会调用它。**
   `gpuargs.js:1277` 注册 `-reg_remap`，`gpuargs.js:5357..5359` 的
   `ArgRegRemap` 仅做整数解析后调用 `Gpu.RemapRegister`。全部解码 JS 中没有
   第二个 `RemapRegister(...)` caller；随包 `.arg/.spc/.js/.json` 也没有
   `-reg_remap` 实例。
5. **高置信 INFERENCE（stock/default）：** 没有外部 `-reg_remap` 或动态
   注入时，tree 保持空，`0xd99930(x)` 原样返回 `x`。因此 ordinary GB202
   direct-shadow 路径的两次 remap 在默认包流中都是 identity：plan key
   `0x34e0+4*FBP` 先保持不变，加 separately resolved domain base 后的值也
   保持不变。fixed-selector fallback base 为 `0x820000` 时，后者就是
   `0x8234e0+4*FBP`；PTOP DeviceInfo2 class `0x10` 非空时则使用硬件 record
   的 instance0 `devicePriBase`。
6. **UNKNOWN：** 某次未保存的真实 argv、外部脚本或运行时生成的间接调用是否
   显式安装 remap。静态闭合 default source 不等于对所有可能进程状态作绝对
   断言。

## 1. tree 的结构与启动状态

lookup `0xd99930` 读取全局 root：

```text
0xd99930  mov 0x186e00f0, rdx       # root
0xd99939  test rdx,rdx
0xd9993c  je identity_return
...
0xd99980  mov node+0x24,eax         # mapped value on exact key
```

它是 `std::map<u32,u32>` 风格的红黑树：node `+0x20` 是 key，`+0x24` 是
value。若 root 为空或没有 exact key，函数保留输入 `EAX=EDI`；命中后只返回
一次 node value，没有递归追链。

同一 executable 的静态初始化器给出了比“`.bss` 初值为 0”更强的证据：

```text
0x7b31aa  [0x186e00e8] = 0          # header color/word
0x7b31ba  [0x186e00f0] = 0          # root
0x7b31c6  [0x186e00f8] = 0x186e00e8 # leftmost/header
0x7b31d1  [0x186e0100] = 0x186e00e8 # rightmost/header
0x7b31dc  [0x186e0108] = 0          # size
```

所以 executable 没有在静态构造阶段预装芯片专用 remap 表。

## 2. 唯一可见 setter 与其语义

setter `0xda1670(fromAddr,toAddr)` 搜索同一棵树：

- 若 `toAddr` 本身已经是一个 remap key，返回 2，避免形成多级间接；
- 若 `fromAddr` 不存在，分配 0x28-byte node，并把 key 写到 `+0x20`；
- 若 `fromAddr` 已存在，复用原 node；
- 最终把 `toAddr` 写到 node `+0x24`，成功返回 0。

native callback `0x11621c0` 先解析两个 JS 参数。它在调用 setter 前还显式做：

```text
mappedTo = d99930(toAddr)
if (mappedTo != toAddr)
    report "Multiple indirection is not allowed"
else
    da1670(fromAddr, toAddr)
```

这说明 remap 是进程级 exact-key 配置，而非按 GPU instance 自动选择的
chip table。重复 `fromAddr` 会更新值；callback 和 setter 都阻止把目标指向
另一个已 remap key。

## 3. caller closure

辅助脚本 `parallel/mods_x86_direct_xrefs.py` 只扫描固定 `.text` 中的 x86
direct `CALL rel32`，并对整个文件做 exact 32/64-bit pointer literal scan。
在 256 MiB virtual-memory limit 下运行：

```text
python3 parallel/mods_x86_direct_xrefs.py 0xda1670 0xd99930
```

setter 的完整结果只有：

```text
CALL source=0x1162276 target=0xda1670
```

没有 `PTR32/PTR64 target=0xda1670` 结果。lookup `0xd99930` 有多处 ordinary
RegHal/raw backend consumer，以及 callback 自身的两个 guard call；这些都是
读取 tree，不是填 tree。

这项 closure 能排除固定 executable 中第二个直接 setter caller 和静态保存的
setter function pointer。它不能形式化排除运行时算出的函数地址、自修改代码或
外部加载模块；当前没有证据表明 stock 流程使用这些方式。

## 4. JavaScript/参数来源

`mods_audit/static/decoded/gpuargs.js` 中：

```text
1277 AddArg("reg_remap", FUNC2, "ArgRegRemap", ..., PARAM_MULTI_OK)
5357 function ArgRegRemap(fromAddr, toAddr)
5359     return Gpu.RemapRegister(parseInt(fromAddr), parseInt(toAddr));
```

对全部解码 JavaScript 搜索 `RemapRegister(` 只得到 `5359` 这一处。对固定包内
`.arg/.spc/.js/.json` 搜索 `-reg_remap`/`reg_remap`，除上述定义外没有实际
参数实例。因此 stock 包没有自动为 GB202、fuse domain 或 L2 地址安装 remap。

`PARAM_MULTI_OK` 表示启动者可以显式提供多组 mapping；它不是隐含默认值。tree
是进程全局状态，已见路径没有按 raw-writer call 临时建立或自动清除它。

## 5. 对 L2 地址链的影响

GB202 raw wrapper 和 ordinary backend 分别调用一次 `0xd99930`：

```text
O1 = remap(planRelativeOffset)
T  = O1 + domainBase
F  = remap(T)
```

因此任意显式配置理论上可以分别以 relative key 或 resolved BAR0 key 命中。
但在已闭合的 stock/default 空树状态下：

```text
remap(0x34e0 + 4*FBP)             = 0x34e0 + 4*FBP
domainBase                        = DeviceInfo2 instance0 devicePriBase
                                    or fixed fallback 0x820000
remap(domainBase + relativeKey)   = domainBase + relativeKey
```

这把此前报告中的“identity/no-remap 假设”收紧为：

- 对固定包、没有外部 `-reg_remap` 的普通启动，是**高置信 default conclusion**；
- 对任意未观察过的真实进程 argv/state，仍保留 **UNKNOWN**。

它只提高地址推导的确定性，不改变 network level、`0x8200dc/0x8200f8` PLM、
FSP 时序、reset propagation 或 disabled L2 health 的缺口，也不构成运行 MODS
或写卡的理由。

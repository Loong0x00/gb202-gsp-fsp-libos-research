# MODS PRC write-map 自动注入有限核对

日期：2026-07-21

## 范围与安全边界

本轮只读取已解码 JS 与本地 MODS ELF；没有执行 MODS，没有访问 GPU、设备节点、
BAR/MMIO、PCI config 或 debugfs，也没有 reset、驱动/模块或固件操作。二进制检查
仅使用小窗口 `objdump` 和对 `.text` 中 x86 `call rel32` 的流式精确目标扫描，
没有建立全程序分析数据库或做全量反汇编。

## 1. 可见 JS 前端不会无参数自动写 `0x1d`

`mods_audit/static/decoded/all/gpuargs.js` 给出：

- `:251`：`g_FspPrcWriteArray` 初始化为 `new Array`；
- `:1710`：`-fsp_prc_write` 注册到 `ArgFspPrcWrite`，允许多次出现；
- `:7362..7365`：只有数组非空才调用 `Gpu.SetFspPrcWriteInfo()`；
- `:16481..16487`：`ArgFspPrcWrite()` 把命令行给出的名称和值 push 入数组。

对现有 `mods_audit/static/decoded/**/*.js` 的检索没有第二个
`g_FspPrcWriteArray.push`，也没有
`PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT` 明文。故在**这份可见 JS
前端**中，普通无参数初始化不会自动合成 `0x1d` 请求；显式参数才会填充该 map。

这里的 ID 已按完整 0x28-byte knob record 重新校准：floorsweeping one-shot 是
`0x1d`，`0x1c` 属于前一项 `RPR_ALLOW_INB`；见
`parallel/prc_knob_metadata.md`。

这不排除私有/未解码脚本直接调用同一 JS native method，也不排除 FSP 中已有的
启动默认值或持久策略。

## 2. JS native callback 只被登记为一个明确方法

native callback `0x116bd50` 在构造器窗口 `0x7d1d55..0x7d1d7d` 作为立即数传给
JS method 注册器；相邻字符串精确为：

```text
Set the FSP PRC Write Array
SetFspPrcWriteInfo
```

该 callback 解析数组后只在 `0x116c0ac..0x116c0b6` 把临时 map 交给
`0xd9b2c0` 保存。全 `.text` 的 raw 4-byte immediate scan 对 `0x116bd50` 只有
这一处注册引用；没有 direct `call rel32` 调用它。这与“它是 JS binding，而非
初始化代码中被硬编码调用的 helper”一致。

该 immediate negative 不能排除动态查表、计算地址或另一个模块中的调用者。

## 3. PRC executor 的四个直接 caller

对 `.text` VA `0x4a0940..0x8bd747a` 中每个 `0xe8 rel32` 计算实际目标后，
`0x185ef60` 恰有四个 direct-call site：

| call site | 可见输入 | 角色 |
|---:|---|---|
| `0x123fcd4` | 从保存的名称到值 map 构造临时链表 | 通用 PRC write-map 执行 |
| `0x1ebc909` | `PRC_KNOB_ID_IST = 1` | 内部 IST enable |
| `0x1ef55c3` | `PRC_KNOB_ID_CCD = 1` | 内部 CCD enable |
| `0x1ef6128` | `PRC_KNOB_ID_CCD = 0` | 内部 CCD disable/收尾 |

IST/CCD 的名称和值均由这些 caller 的指令立即构造。四处没有硬编码
floorsweeping one-shot 名称或 ID `0x1d`。这些 caller 都以名称进入 resolver，
所以旧文档的 ID 错配不改变其二进制行为。对 ELF 原始字节另查
`0x185ef60` 的 8-byte absolute pointer 为零个命中，但这仍不能排除间接跳转、
别名 thunk、运行时注册或未包含模块。

## 结论

1. **FACT（可见 JS）：** 默认 PRC write array 为空，只有显式
   `-fsp_prc_write` 回调向其添加项目。
2. **FACT（direct callers）：** 当前 ELF 中 PRC executor 的四个直接 caller
   是通用 map、IST enable、CCD enable/disable；没有一个硬编码 `0x1d`。
3. **有限负证据：** 正常无参数 task 2 之前不存在已见 JS/native 直接路径自动
   注入 `0x1d`。这加强了“`0x1d` 与 task 2 是独立可选事务”的结论。
4. **UNKNOWN：** FSP 启动默认值、持久 policy、未解码脚本、动态/间接 native
   caller，以及 `0x1d` 的实际 required value、消费和 self-clear 语义。

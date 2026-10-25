# R610.57.04 CLK domain 列表与对象导出证据 — 2026-08-16

## 边界

- GPU：GB202 RTX 5090；驱动/GSP：R610.57.04。
- 本轮硬件操作只有 `CLK_DOMAIN_GET_INFO (0x2080901a)` 与既有
  `CLK_DOMAINS_GET_INFO (0x20809019)` 只读 RPC。
- 未调用任何 `SET_CONTROL`，未加负载，未改频率、电压或功率限制。
- probe source SHA-256：
  `d6cc5d6faddaa6ab42f237bc9985af5f85e97da64d0ec3ce245bdca567c6803c`
- probe binary SHA-256：
  `8459a95ee3131a72e0bf013315f10958325dbd220332bd71b5a06512a1f10eff`

## 九个域的完整 GET_INFO 结果

| index | domain | count | min..max MHz | 精确列表/公式 |
|---:|---|---:|---:|---|
| 0 | GPC | 465 | 15..3495 | `15+floor(i*15/2)`, `0<=i<465` |
| 1 | XBAR | 465 | 15..3495 | `15+floor(i*15/2)`, `0<=i<465` |
| 2 | MCLK | 5 | 405..15001 | `405,810,7001,13801,15001` |
| 3 | SYS | 439 | 15..3300 | `15+floor(i*15/2)`, `0<=i<439` |
| 4 | NVD | 459 | 15..3450 | `15+floor(i*15/2)`, `0<=i<459` |
| 5 | PWR | 459 | 15..3450 | `15+floor(i*15/2)`, `0<=i<459` |
| 6 | PCIE | 5 | 1..5 | `1,2,3,4,5` |
| 7 | API40 | 8 | 675..1620 | `675,900,1026,1080,1188,1296,1350,1620` |
| 8 | API08 | 4 | 540..1080 | `540,675,810,1080` |

五个主时钟域的每个相邻差值都只可能是 7 或 8 MHz，数量严格相等：

```text
GPC/XBAR: 232 x 7 MHz, 232 x 8 MHz, formula mismatches=0
SYS:      219 x 7 MHz, 219 x 8 MHz, formula mismatches=0
NVD/PWR:  229 x 7 MHz, 229 x 8 MHz, formula mismatches=0
```

因此这是整数 MHz API 对 7.5 MHz 有理步长的 floor 投影，不是统计拟合。

## 当前 GSP 的公开 domain record serializer

`CLK_DOMAINS_GET_INFO` 的当前 `0x180`-byte record serializer 是
`0x010f7840`，基类 serializer 是 `0x010f6460`。成功路径逐字段复制：

```text
record +0x20 <- object +0x152 (u8)
record +0x21 <- object +0x153 (u8)
record +0x22 <- object +0x154 (u8)
record +0x23 <- object +0x150 (u8)
record +0x24 <- object +0x151 (u8)
record +0x25 <- low byte of object +0x156
record +0x26 <- object +0x158 (u16)
record +0x28 <- object +0x15a (u16)
record +0x2c <- object +0x15c (u32)
record +0x30 <- object +0x160 (u32)
record +0x34 <- object +0x164 (u32)
record +0x38 <- object +0x168 (u32)
record +0x3c <- object +0x194 (u32)
record +0xe8 <- object +0x2b0 (u32)
record +0xec..+0x17b <- object +0x2c0 (0x90 bytes)
record +0x17c <- object +0x350
record +0x17d <- object +0x351
record +0x17e <- derived boolean
```

RPC descriptor/handler 也已闭合：

```text
0x20809019 size 0x3030 -> handler 0x010ddb58 -> object method +0x98
0x2080901a size 0x0804 -> handler 0x010ddeb4 -> group-state method +0x18
```

这里存在一个已实测但尚未命名的 public/static ABI 翻译边界：R610 主 ELF 的静态
`0x20809019` handler 是频率列表生成器，而本机公开 RM endpoint 上实际返回列表的是
`0x2080901a`；静态 `0x2080901a` 则进入 group serializer。只能确认两个观测面的语义
对调，不能在尚未找到转换层时宣称它们是同一 ABI。

## 列表生成算法

静态列表路径已经从 RPC 闭合到最底层整数除法器：

```text
0x20809019
  -> 0x010ddb58
  -> domain object +0x98
  -> 0x010e0830：遍历 domain +0x148..+0x149 的 inclusive program range
  -> clock program +0x68
  -> 0x010f4dac：按 program mode 0/1/2 追加频点
  -> mode 2: clock-table row +0x78
  -> 0x0112feac：枚举 inclusive divider range
```

`manager+0x1150` 因而是 clock-program/control group，不是此前暂定的 clock-client
group。它最多保存 255 个 program，factory `0x01b54908` 支持 type 1/3/4/5/7/8。
mode 2 查找的 clock-table row 来自 `manager+0x1308`；其 factory `0x01b85260`
支持 type 2/3/5/6/7/8。

共同 helper `0x010f4dac` 的行为是：mode 1 只追加 endpoint；mode 0 按 u8 step
生成包含左右边界的线性序列，初始零值和相邻 program 的左边界重复都由固件保留；mode 2
委托 row callback。`0x0112feac` 先用 `0x01ae7334` 将前一频率与 endpoint 映射到
divider 下界/上界，然后输出：

```text
frequency(divider) = floor(
    row.u16_22 * divider / (row.u8_21 * row.u16_24)
)
```

随后还执行由 `manager+0x47e` 与 `row+0x3e` 选择的 x2/div2 分支。下界转换不是普通
floor/ceil：down 路径使用 `(frequency+1)` 的不对称整除边界，再将 lower divider 加一；
这解释了为何列表不会简单等价于对 endpoint 做一次浮点 `arange`。

对五个主域，运行时列表与上述生成器共同确定的最简有效比率恰为 `15/2 MHz/divider`：
前一值 0 映射后从 divider 2 开始，GPC/XBAR endpoint 3495 映射到 divider 466，
`d=2..466` 精确生成 465 个值：

```text
floor(15*d/2) = 15 + floor(i*15/2), i=d-2
```

这不是仅凭列表作的曲线拟合；它是恢复出的整数生成算法对 live list 的零误差重放。
但当前没有直接读回 row 的三个原始字段，所以只能证明约分后的有效比率 `15/2`，不能区分
例如等价的成比例 numerator/denominator factorization。

可执行重放位于
`power_governor_reverse/bug_inverse/algorithm/gpu_inverse/clock_program.py`，包括 mode 0/1、
mode 2 divider 上下界、u32 arithmetic、capacity/status 分支及 465 点判别测试。

## public RPC 的写入边界

新增的 sentinel probe 用 `0xa5a5a5a5` 预填整个参数区，只保留输入 index byte：

- index 0：GSP 重写 header 与 465 个 u32 频点，到 offset `0x744` 为止；`0x748`
  起仍是 sentinel；
- index 2：返回 `u16 count=5` 和 `405,810,7001,13801,15001`，`0x18` 起仍是
  sentinel；
- index 9：返回 RM status `0x1f`。

因此当前公开 endpoint 的实际最小布局可证明为 `u8 index, u8 reserved, u16 count,
u32 frequency[count]`；输入只消费 index，不依赖调用方清零的尾部。另一个公开
`CLK_PROGS_GET_INFO` 只读请求返回成功且全零，但由于已经存在上述翻译边界，这不能证明
固件内部没有 clock-program objects。

## 结论边界

PROVED：当前固件公开的支持频率集合、当前 GSP domain INFO 对象到 RPC record 的字段
来源，以及静态列表从 domain program range 到 mode-2 divider 枚举的整数算法。五个主域
的 `15/2` 是算法约束下的精确有效比率。

UNKNOWN：该公开集合是否是每条最终 clock-arbitration 路径的最后量化器。数字孪生因此
把它作为可查询、可 bracket 的 diagnostic list；在拿到当前 R610 私有 PMU domain
normalizer 字段或有判别力的 SET/readback 实验前，不用它替换既有最终时钟模型。公开
`0x20809019/0x2080901a` 与静态 handler 之间的精确转换层、以及 live row 未约分的原始
字段也仍是 UNKNOWN。

## 复现

```bash
cd /home/user/rt_5090_project
cc -O2 -Wall -Wextra -Werror -o power_cap_limit_probe power_cap_limit_probe.c
./power_cap_limit_probe --clk-domain-grid 0
./power_cap_limit_probe --clk-domain-list 2
./power_cap_limit_probe --clk-domain-info-prefill-raw 2 0xa5a5a5a5
```

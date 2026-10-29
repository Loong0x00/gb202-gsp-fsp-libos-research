# MODS 570.151 PRC knob table 元数据限界审计

日期：2026-07-21
样本：`mods_audit/static/extracted_inner/mods`
SHA256：`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`

## 范围与安全边界

本轮只读取本地 MODS ELF 和已解码 JS，使用小窗口 `objdump`、`xxd`、`rg`
以及按 4 MiB 分块的 `call rel32` 目标扫描。没有运行 MODS，没有访问 GPU、设备
节点、BAR/MMIO、PCI config、debugfs、驱动、固件或 reset；没有建立 Ghidra/全程序
反汇编数据库。结论只覆盖当前可见 host ELF/JS，不能代替不可见 FSP consumer 的
校验规则。

## 结论先行：前提中的 ID 有一位偏差

**FACT：** `PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT` 在这份 MODS
570.151 表中的 ID 是 **`0x1d`，不是 `0x1c`**。

旧判读把“一个记录末尾的 ID store”配给了紧随其后才开始构造的字符串。实际临时
记录布局是：

```text
record size 0x28
+0x00  std::__cxx11::string name   (0x20 bytes)
+0x20  uint32_t id
+0x24  padding                     (0x04 bytes)
```

因此 `0x18603d4: mov dword [rsp+0x4b0], 0x1c` 属于基址
`rsp+0x490` 的上一条 `RPR_ALLOW_INB` 记录；floorsweeping 名称从
`rsp+0x4b8` 开始，其 ID store 是
`0x1860458: mov dword [rsp+0x4d8], 0x1d`。

这不是单靠相邻指令顺序的猜测：表插入循环和 name->ID resolver 都独立确认了字段
方向与偏移，详见下文。

## 1. `0x1b..0x1f` 邻接记录的逐条重建

构造函数从 `0x185f690` 开始；`0x185f6a4` 令临时表基址
`rbx = rsp+0x30`。第 `n` 条记录基址为：

```text
rsp + 0x30 + n * 0x28
```

下表中的“name 构造”列给出 string object/长度设置、分配和 payload store 的
有界窗口；“ID store”总是该记录基址 `+0x20`。

| ID | record 基址 | name 构造窗口 | ID store | 精确名称 |
|---:|---:|---:|---:|---|
| `0x1b` | `rsp+0x468` | `0x18602ef..0x186034e`；长度 `0x19`，块 `0x9224cf0/0x9224d00` | `0x186035c -> [rsp+0x488]` | `PRC_KNOB_ID_RRL_ALLOW_INB` |
| `0x1c` | `rsp+0x490` | `0x1860367..0x18603c6`；长度 `0x19`，块 `0x9224d10/0x9224d20` | `0x18603d4 -> [rsp+0x4b0]` | `PRC_KNOB_ID_RPR_ALLOW_INB` |
| `0x1d` | `rsp+0x4b8` | `0x18603df..0x186044a`；长度 `0x2c`，块 `0x9224d30/0x9224d40/0x9224c10` | `0x1860458 -> [rsp+0x4d8]` | `PRC_KNOB_ID_FLOORSWEEPING_ALLOW_INB_ONE_SHOT` |
| `0x1e` | `rsp+0x4e0` | `0x1860463..0x18604d0`；长度 `0x25`，块 `0x9224d50/0x9224d60` 加立即数字节 | `0x18604de -> [rsp+0x500]` | `PRC_KNOB_ID_HBM_FREQ_CHANGE_ALLOW_INB` |
| `0x1f` | `rsp+0x508` | `0x18604e9..0x1860548`；长度 `0x1f`，块 `0x9224d70/0x9224d80` | `0x1860556 -> [rsp+0x528]` | `PRC_KNOB_ID_ROW_REMAP_ALLOW_INB` |

特别地，floorsweeping 名称的三个 payload store 是：

- `0x18603fa..0x186041f`：把 `0x9224d30` 写到 string `+0x00`；
- `0x1860422..0x186042a`：把 `0x9224d40` 写到 `+0x10`；
- `0x186042e..0x1860436`：把 `0x9224c10` 写到 `+0x1c`。

按长度 `0x2c` 截断后，结果精确为上述 44 字节名称。紧随其后的
`0x1860458` 才把 `0x1d` 写入同一记录 `+0x20`。

## 2. 插入循环排除“ID 在下一条记录前面”的解释

所有字符串构造完后，`0x18609fc` 令 `r12 = rbx`，即从
`rsp+0x30` 的第 0 条开始。循环对每条记录执行：

1. `0x1860a60` 分配 `0x48` 字节红黑树节点；
2. `0x1860a75..0x1860a85` 从 `[r12+0x00]` 和 `[r12+0x08]`
   取得 string data/length，复制成 node `+0x20` 的 key；
3. `0x1860a8a` 读取 `dword [r12+0x20]`；
4. `0x1860a9d` 把它写到 `dword [node+0x40]`；
5. `0x1860aab` 执行 `r12 += 0x28`；
6. `0x1860aaf..0x1860aba` 以 `rsp+0x710` 为 exclusive end。

所以临时记录和树节点都只有 `name + uint32 id`。范围
`[rsp+0x30, rsp+0x710)` 恰为 `0x6e0 / 0x28 = 44` 条，即 ID
`0x00..0x2b`；此构造器里没有 `0x2c` 或 `0x2d` 记录。

## 3. resolver 与反向 lookup 再次确认字段

### 3.1 name -> ID：`0x1858280`

resolver 用 node `+0x20/+0x28` 的 string data/length 做红黑树精确名称比较；命中
后：

```text
0x1858424  mov eax, dword [rbp+0x40]
0x185842c  mov dword [output], eax
```

这与插入循环的 node `+0x40 <- record+0x20` 完全对齐。名称不存在时走
`0x1858440..0x1858467` 的错误返回，不存在 type/range/default 查询。

### 3.2 ID -> name：`0x1858140`

反向路径逐节点比较 `dword [node+0x40]`（`0x185817d`），命中后仅取得
node `+0x20` 的名称用于格式化（`0x1858183..0x1858194`）。它同样没有读取第二
个 metadata 字段。

对 `.text` 中 `call rel32` 的分块精确目标扫描得到：

| target | direct call sites |
|---|---|
| name->ID `0x1858280` | `0x185f083`（write executor）、`0x185f577`（read executor） |
| ID->name `0x1858140` | `0x185e5e1` |
| write executor `0x185ef60` | `0x123fcd4`、`0x1ebc909`、`0x1ef55c3`、`0x1ef6128` |
| read executor `0x185f500` | `0x1ef5d97` |

这是 direct-call 的限界结果，不排除动态间接调用；但记录本身的两字段布局不依赖
该负结果。

## 4. 与 IST、CCD、PCIE/PPCIE 的对照

同一构造器中的已知记录使用完全相同的 `0x28` 字节 shape：

- `PRC_KNOB_ID_IST_ALLOW_INB`：record `rsp+0x58`，ID `1` 写在
  `rsp+0x78`（`0x185f7b2`）；
- `PRC_KNOB_ID_IST`：record `rsp+0x80`，ID `2` 写在
  `rsp+0xa0`（`0x185f7ce`）；
- `PRC_KNOB_ID_CCD_ALLOW_INB`：record `rsp+0xf8`，ID `5` 写在
  `rsp+0x118`（`0x185f932`）；
- `PRC_KNOB_ID_CCD`：record `rsp+0x120`，ID `6` 写在
  `rsp+0x140`（`0x185f951`）。

硬编码 IST caller `0x1ebc8df` 明确把 requested value `1` 放入 name->value
map；CCD callers 在 `0x1ef559d` 和 `0x1ef6100` 分别放 `1`、`0`。这些值来自
caller 指令，不来自 knob-table 记录。因此“IST/CCD 使用 0/1”不能证明
floorsweeping knob 的合法值也是 0/1。

本表可见的是 `PCIE_VF_CONFIG...` 等 `PCIE` 名称；已公开 GH100 路径所用的
`PPCIE` knob ID `0x2d` 不在这个只到 `0x2b` 的 MODS 表内。公开 PPCIE caller
把 `value == 1` 解释为 ON，是另一个产品/knob 的 caller-specific 语义，不能
迁移成 `0x1d` 的 validator 或 default。

## 5. write/read executors 没有暴露 knob-specific 元数据

### 5.1 write executor `0x185ef60`

对每个输入 name->requested-value 项，executor：

1. 在 `0x185f074..0x185f088` 只调用 name->ID resolver；
2. 从输入 map node `+0x40` 取 32-bit requested value（`0x185f0a4`），把
   value 和 resolved ID 放入内部 list 的两个 dword；
3. 唯一的名称分类是
   `std::string::find("ALLOW_INB", 0, 9)`（`0x185f090..0x185f0b4`），用于把
   `ALLOW_INB` 名称与普通名称分组/排序；它不检查 `ONE_SHOT`，也不验证值；
4. 先读 current value，仅在不同的时候发 write；
5. `0x185f1c0..0x185f27f` 把 resolved ID 的低 16 位和 requested value 的低
   16 位编码后，再追加两个 literal-zero byte，形成 6-byte
   `id16+value16+zero16` request；tail 的私有字段名未知；
6. 写后再读并与 requested 32-bit value 比较。

在该 executor 中没有按 ID 分支的 type、enum、min/max、default、writable、
one-shot flag 或 validator。payload 是 16-bit value 只证明 wire width；它不
证明所有 `0..65535` 都合法。超过 16 位的输入会在请求中截成低 16 位，而且仍用
原 32 位值做 readback 比较，也不能据此建立受支持范围。

### 5.2 read executor `0x185f500`

read executor 在 `0x185f56b..0x185f57e` 只做 name->ID，随后调用
`0x185ea20`，把回读的 16-bit value 零扩展后存入调用者 map node `+0x40`
（`0x185f539..0x185f557`）。它也不返回 type/default/range/flags。

### 5.3 JS/native 输入层

可见 JS `ArgFspPrcWrite()` 仅执行 `knobId.toUpperCase()` 与
`parseInt(knobValue)`；native callback `0x116bd50..0x116c0b6` 读取
`knobId`/`knobValue` 并把后者保存为 map node `+0x40`。两层均没有按 knob 名称
选择 validator。

## 6. 硬编码 callers 是否受 ID 修正影响

**代码行为不变，文档和 wire-ID 解释需要修正。** 四个 write-executor direct
caller 是：

- `0x123fcd4`：通用用户/脚本 name->value map；
- `0x1ebc909`：`PRC_KNOB_ID_IST = 1`；
- `0x1ef55c3`：`PRC_KNOB_ID_CCD = 1`；
- `0x1ef6128`：`PRC_KNOB_ID_CCD = 0`。

它们都传“名称”，再由 `0x1858280` 解析，因此二进制本来就会正确得到 ID。
当前可见 direct callers 中没有硬编码 floorsweeping 名称的专用 caller。修正影响的
是此前静态报告中的表述：若显式按名称 read/write floorsweeping knob，host 编码的
ID 是 `0x001d`，不是 `0x001c`；task 2、QCAP family 和 IST/CCD 路径本身不因
这项文档纠错而改变。

## 最终判定

1. **FACT：** floorsweeping one-shot knob 的 MODS 570.151 host-table ID 是
   `0x1d`；`0x1c` 是 `RPR_ALLOW_INB`。
2. **FACT：** host knob table 每条只有 `std::string name + uint32 id`，没有
   type、allowed-values、default、writability、one-shot bit、range 或 validator
   字段。
3. **FACT：** host writer 只利用名称中的 `ALLOW_INB` 子串安排顺序；字符串中的
   `ONE_SHOT` 没有对应可见 flag/校验器。
4. **FACT：** write wire value 为 16 位，read 返回值也按 16 位解析；这只是 ABI
   宽度，不是合法值集合。
5. **UNKNOWN：** `0x1d` 的合法值、默认值、是否可写、值 `1` 是否表示 grant、
   FSP 是否自清、何时消费，以及 FSP 内部 range/policy validator。当前 host 静态
   材料不能把 `1` 认证为正确值；IST/CCD/PPCIE 的 `1` 都不能替代该证据。

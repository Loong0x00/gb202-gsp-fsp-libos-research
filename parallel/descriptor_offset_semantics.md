# `FuseJsonParser2` 的 `Chip_options.offset` 表示与 plan key 逐跳审计

日期：2026-07-21  
范围：只对本地 `mods_audit/static/extracted_inner/mods` 做静态、小窗口审计；
没有访问 GPU、没有运行 MODS、没有进行任何设备读写。

## 结论

1. **`FuseJsonParser2` 不会把 `Chip_options.offset` 减去
   `0x820000`，也没有做任何 domain-base 归一化。**
   - JSON 整数形式：低 32 bit 原样写入 descriptor `+0x8c`。
   - 字符串形式：把 `|` 前的十进制地址原样解析到 descriptor
     `+0x8c`；`|MSB:LSB` 只另外填入 `+0x94/+0x90`。
   - `NA`：地址写成 `0xffffffff`。
2. **`SplitMacro_EncodeSetSw` 在 `0x148b62e` 取出的
   descriptor `+0x8c`，未经加减或掩码，成为 plan RB-tree 节点
   `+0x20` 的 32-bit key。**
3. 因而这段代码只证明 parser/encoder 是透明搬运：
   - 文件若写 `0x8234e0`（JSON 中通常以十进制整数表达），plan key
     就是 `0x8234e0`；
   - 文件若写 `0x34e0`，plan key 就是 `0x34e0`。

   本地缺少原厂 `gb202_f.json`，所以**不能单凭 parser 判定原厂记录本身
   究竟采用绝对值还是 domain-relative 值**。可以明确排除的是“parser
   自动执行 `offset - 0x820000`”这一解释。

## 1. 目标函数确为 `FuseJsonParser2::Chip_options` parser

### RTTI 与虚表

只读数据窗口 `0x9250d60..0x9250e40` 包含 RTTI 名称
`15FuseJsonParser2`。其对应虚表的 callable 区从 `0x9250da0` 开始；
该表 `+0x38` 的 qword 是 `0x0000000000cbbf70`：

```text
0x9250d60  "15FuseJsonParser2"
...
0x9250da0  0x0000000000cc3ab0   # vptr +0x00
...
0x9250dd8  0x0000000000cbbf70   # vptr +0x38
```

顶层 JSON dispatcher `0xcc1530` 的精确调用链是：

```text
0xcc1598  查找 "options"
0xcc15b8  查找 "Chip_options"
0xcc15ce  mov rax,[rbp+0]       # parser vptr
0xcc15de  mov rbx,[rax+0x38]    # Chip_options virtual parser
0xcc15e7  mov edx,r14d          # 第三个参数，FPF 来源标志
0xcc15f0  call rbx
```

对 `FuseJsonParser2` 实例，这个间接调用的目标就是 `0xcbbf70`。因此下文
分析的是 JSON `Chip_options` parser，而不是 IFF/JTAG `configFields`
parser，也不是旧 XML parser。

## 2. JSON `offset` 到临时 descriptor：没有 base 变换

`0xcbbf70` 逐个遍历 `Chip_options` 成员。目标 record 的临时字段在栈上；
其中：

```text
[rsp+0xd4] customer_visible
[rsp+0xd8] bits
[rsp+0xdc] offset/address
[rsp+0xe0] LSB
[rsp+0xe4] MSB
```

### 整数形式

`0xcbc398..0xcbc3c6` 先确认成员 `offset` 存在并区分 JSON 类型。整数
分支为：

```text
0xcbc948  call 0xcb2950          # 取 offset JSON value
0xcbc94d  test byte [rax+0xe],0x40
0xcbc957  再取 offset JSON value
0xcbc964  mov eax,[rax]          # JSON 中的 32-bit 整数
0xcbc966  mov [rsp+0xdc],eax     # 原样保存地址
0xcbc96d  movabs rax,0x1f00000000
0xcbc977  mov [rsp+0xe0],rax     # LSB=0, MSB=31
```

从 `mov eax,[rax]` 到 `mov [rsp+0xdc],eax` 之间没有算术指令、掩码或函数
调用，尤其没有 `sub 0x820000`。

### 字符串/位域形式

字符串分支 `0xcbc3cc..0xcbc407` 把文本交给 helper `0xc9d990`，输出
地址结构从 `[rsp+0xdc]` 开始。helper 的语义为：

```text
0xc9da40..0xc9da58   查找 "|"
0xc9da8d..0xc9daac   对 "|" 前文本调用 strtol(..., base=10)，
                     直接写 output+0（地址）
0xc9daaf..0xc9dc0f   查找 ":"，分别把 MSB/LSB 写 output+8/output+4
0xc9dc80..0xc9dc9c   没有 "|" 时 strtoul(..., base=10)，
                     直接写 output+0，并补 LSB=0、MSB=31
```

`"|"` 的字符串 VA 是 `0x90c2f82`，`":"` 是 `0x90ae929`。
这条路径同样没有减 base。`NA` 分支 `0xc9da17..0xc9da25` 把地址设为
`0xffffffff`，并不是某种 domain-relative 编码。

### 临时结构到最终 descriptor

`0xcbc560` 以后把临时结构装入 name-tree 中的最终 descriptor：

```text
0xcbc592  mov rax,[rsp+0xd4]
0xcbc59a  mov [rbx+0x84],rax     # customer_visible + bits
0xcbc5a1  mov rax,[rsp+0xdc]
0xcbc5a9  mov [rbx+0x8c],rax     # offset/address + LSB
0xcbc5b0  mov eax,[rsp+0xe4]
0xcbc5b7  mov [rbx+0x94],eax     # MSB
```

因此 descriptor 布局可更精确写成：

```text
+0x8c  uint32 address（JSON 数值原样或字符串十进制前缀）
+0x90  uint32 LSB
+0x94  uint32 MSB
```

## 3. descriptor `+0x8c` 到 plan RB-tree `+0x20`

编码器 `0x148b4c0` 的相关窗口给出完整数据流：

```text
0x148b62e  mov eax,[r14+0x8c]    # descriptor address
0x148b635  mov [rsp+0x60],eax    # 暂存 plan key
0x148b72d  mov ebp,[rsp+0x60]
0x148b750  cmp [rax+0x20],ebp    # 按现有 node key 查树
...
0x148b770  准备 RB-tree 插入参数
0x148b786  [rsp+0x68] = &key
0x148b78b  call 0xdedf50
```

插入 helper `0xdedf50` 明确复制这个 dword：

```text
0xdedf52  r13 = rcx              # rcx -> 持有 &key 的参数
0xdedf76  rax = [r13+0]
0xdedf85  r13d = [rax]
0xdedf88  [rbx+0x20] = r13d      # 新 plan node 的 key
```

随后 `0x148b797` 只把编码后的 raw value 写入 node `+0x24`。从
descriptor `+0x8c` 到 plan node `+0x20`，没有地址加法、减法、位移、
掩码，也没有 RegHal/domain resolver 参与。

## 4. 对当前绝对值/相对值矛盾的限定

这里可以下的强结论是：

```text
Chip_options.offset 的文件数值
  -> descriptor+0x8c
  -> SplitMacro 临时 key
  -> plan RB-tree node+0x20
```

四处的低 32 bit 相同。

后续生命周期审计进一步证明，GB202 domain-5 wrapper 始终把一个**单独解析的
domain base** 加到 plan key 上：若 PTOP DeviceInfo2 的 mapped class `0x10`
为空，fixed-selector fallback 的 instance0 base 是 `0x820000`；若该类存在，
则使用硬件表中 instance0 record 的 `devicePriBase`。两条分支都没有把 plan key
改写成绝对地址。因此与该 writer ABI 相容的 L2 文件数值应是
`0x34e0..0x34fc`；在固定 fallback 下才直接展开成
`0x8234e0..0x8234fc`。这是**组合多条调用链得到的推论**，不是 parser 自己
施加的格式规则，也不是对本卡运行时 DeviceInfo2 数值的观察。没有原厂
`gb202_f.json`，仍不能把该推论冒充为原厂文件内容的直接证据。

反过来，旧说法“JSON 写绝对 `0x8234e0..0x8234fc`，而 parser/encoder 会在
中途规范化成相对值”已被上述逐指令数据流排除。

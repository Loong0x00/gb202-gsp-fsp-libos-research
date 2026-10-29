# GSP `base+0x318` 私有对象 provenance 复核

日期：2026-07-21

## 范围与结论先行

本轮只读取固定归档
`/tmp/gsp_inner_19f040_a.elf`：

```text
size   82577496
sha256 bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47
```

只对 first executable PT_LOAD（VA `0x01000000..0x01e97000`）做了精确常量
搜索、2-byte 边界 AUIPC 配对扫描、若干小窗口 Capstone 反汇编，以及从已选
group-2 入口开始的有限构造路径重放。没有访问 GPU、设备节点、BAR/MMIO、PCI
config 或 debugfs，没有执行固件/MODS，也没有 reset、驱动或模块操作。

复核后的最准确结论是：

- **FACT（固定二进制）：** GB202/index 65 的构造路径把独立函数
  `0x01444500` 写入所构造对象的 `+0x318`；该函数只返回 `0x820000`。
- **FACT（固定二进制）：** 四个正校准函数都从其**原始入参 `a0`**加载
  `+0x318` 并在未改写 `a0` 的情况下间接调用；四者还都把各自的原始 `a0`
  用作 `+0xb98` companion field 的基址。前三个入口的这段 16-byte 序列逐字节
  相同。
- **FACT（固定二进制）：** GB202 同一构造路径还把 `+0xc04` 正校准函数
  `0x0141579c` 写入同一对象的 `+0x1a0`，再把 getter 写到 `+0x318`。
- **强 INFERENCE：** 四个经正校准的调用点把 `a0` 当作同一种私有 GSP
  GPU-like layout；该 layout 的 `+0x318` 很可能就是 primary-fuse-base getter。
  这是“构造器 + receiver 传递 + 两个共同字段 + 返回值用途”的二进制行为对齐，
  不依赖公开 host `OBJGPU` ABI。
- **UNKNOWN：** stripped GSP 中该类型和字段的正式名称。公开 host RM 的同名
  getter 位于 `OBJGPU+0x460`，不是 `+0x318`，所以不能把这里写成公开 ABI FACT；
  也不能把其余裸 `+0x318` 候选全局命名为同一方法。

## 1. 两个独立的 `0x820000` 返回函数

对 `lui a0, 0x820` 精确编码做 raw 定位，再逐点小窗口反汇编，得到两个真正的
独立 constant-return function：

```text
0x014163f0:
  addi sp,sp,-0x10
  ...
  lui  a0,0x820
  ...
  jr   ra

0x01444500:
  addi sp,sp,-0x10
  ...
  lui  a0,0x820
  ...
  jr   ra
```

RV64 `lui a0,0x820` 在这里得到 `0x0000000000820000`。两者都不读取入参，
没有附带寄存器访问。

另一个 raw 命中 `0x013d1b1c` 不是此类函数：其后立即执行
`remuw a2,a2,a0`，属于前一控制流的内部运算，不能计作第三个 getter。

## 2. `+0x318` 的函数地址只在同一初始化簇中形成

在 first PT_LOAD 的 2-byte 边界上只解码 AUIPC 候选，并在最多 40-byte 的
局部窗口内验证同寄存器的 `addi` 配对。对两个返回函数得到：

| 返回函数 | 地址形成点 | 后续动作 |
|---|---:|---|
| `0x01444500` | `0x01b9c70e` | `0x01b9c716: sd a4,0x318(s11)` |
| `0x01444500` | `0x01b9cfd2` | `0x01b9cfda: sd a4,0x318(s11)` |
| `0x01444500` | `0x01b9e4b6` | 放入 `a6`，跳到公共 store `0x01b9dcb8` |
| `0x01444500` | `0x01b9e5d2` | `0x01b9e5da: sd a4,0x318(s11)` |
| `0x014163f0` | `0x01b9eb88` | 放入 `a6`，跳到公共 store `0x01b9dcb8` |

公共汇合点为：

```text
0x01b9dcb8: sd a6, 0x318(s11)
```

**FACT（限上述 AUIPC+ADDI 形式和 first PT_LOAD）：** 本次没有发现两个返回函数
在该 executable segment 中被其他代码簇形成地址；已确认的形成点都属于从
`0x01b9c210` 开始的同一大段 per-chip 初始化 routine，并最终写同一
`s11+0x318` 字段。

这仍不是 whole-file relocation proof：数据表、另一 PT_LOAD 或未建模的地址构造
形式不在这项负枚举范围。

## 3. GB202/index 65 的实际构造路径

初始化 routine 的入口片段直接给出对象和 chip-index 关系：

```text
0x01b9c244: mv   s1,a0
0x01b9c256: ld   s11,0(a0)       # 被初始化对象
...
0x01b9c300: lhu  a2,0x48(s11)    # HAL/chip index
0x01b9c330: srli a3,a2,5         # group
0x01b9c33c: beq  a3,2,0x1b9d076 # group 2
```

同版本 generated chip map 给出 GB202 的 `HalVarIdx=65`；因此低 index 为 1，
group 为 2。为了避免解释整个固件，本轮只从 `0x01b9d076` 开始：

- 初态固定为 `a2=65`、`a3=2`、`s11=sentinel object`；
- 只解释当前构造路径出现的 AUIPC、整数移位/加法/逻辑、条件分支、直接跳转和
  store；
- 不执行任何 call，也不读取硬件；
- 上限 2000 步，实际在第 475 步到达目标 store。

关键轨迹为：

```text
step 200  0x01b9fb90: s11+0x1a0 <- 0x0141579c
step 475  0x01b9e5da: s11+0x318 <- 0x01444500
```

控制流包含向前进入 alternate block、再跳回公共后续的路径，所以执行顺序与 VA
数值不单调；这不是地址记录倒置。

由此可直接分层：

- **FACT（固定 artifact、固定 index 和已解释到该选择点的路径）：** GB202
  在 `+0x318` 选择点写入 `s11+0x318 = 0x01444500`，而不是
  `0x014163f0`。
- **FACT：** 同一个 `s11` 对象还在 `+0x1a0` 获得
  `0x0141579c`，即后述 `+0xc04` 正校准函数。
- **UNKNOWN：** stripped ELF 没有提供 `s11` 对象及 `+0x318/+0x1a0`
  字段的正式 C 类型名。

有限重放在首个 `+0x318` store 处停止，没有把随后被调用的 extension routine
解释到底，因此不单靠这次重放宣称“整个 constructor 生命周期绝无后续覆盖”。
前一节的地址形成扫描没有找到这两个 constant-return function 的其他安装簇，
对后续覆盖假设构成额外负证据，但仍保留其限定域。

## 4. 四个正校准点的 receiver 传递

四个函数入口分别为 `0x01357b04`、`0x0141579c`、`0x018ae670` 和
`0x018af0b8`。这里不借用公开结构布局，只看指令如何使用入参。

### 4.1 前三个入口共享逐字节相同的对象访问序列

三个入口在保存寄存器之后，分别从 `0x01357b0e`、`0x014157a6`、
`0x018ae67a` 开始执行同一串 16-byte 字节
`03 37 85 31 85 66 b3 07 d5 00 83 b4 87 b9 02 97`：

```text
ld    a4,0x318(a0)
lui   a3,0x1
add   a5,a0,a3
ld    s1,-0x468(a5)
jalr  a4
```

其含义只按算术展开就是：

```text
method    = *(a0 + 0x318)
companion = *(a0 + 0x1000 - 0x468) = *(a0 + 0xb98)
return    = method(a0, ...)
```

在 `jalr` 前没有指令改写 `a0`。因此 getter 接到的就是该函数原始入参 `a0`，
不是另行加载或换算出的对象。getter 返回后，三者分别形成：

| 函数入口 | slot load / call | getter return 后形成 | companion field |
|---:|---:|---:|---:|
| `0x01357b04` | `0x01357b0e / 0x01357b1c` | `+0x3814` at `0x01357b24` | incoming `a0+0xb98` |
| `0x0141579c` | `0x014157a6 / 0x014157b4` | `+0x0c04` at `0x014157bc` | incoming `a0+0xb98` |
| `0x018ae670` | `0x018ae67a / 0x018ae688` | `+0x074c` at `0x018ae68a` | incoming `a0+0xb98` |

三个独立函数共享两个相距很远的字段 offset，并让 `+0x318` 返回值进入三个已知
fuse-relative address pattern；这显著降低了“只是不同类型碰巧都用了裸
`+0x318`”的解释空间。

### 4.2 第四个入口也保留同一个 `a0`，并再次使用 `+0xb98`

第四个函数的关键片段为：

```text
0x018af0c4: ld    a5,0x318(a0)
0x018af0c8: mv    s1,a0
0x018af0ce: jalr  a5
0x018af0d4: mv    s2,a0          # 保存 getter return
0x018af0d6: mv    a0,s1          # 恢复原始 a0
0x018af0d8: ld    a5,0x188(a1)
0x018af0dc: jalr  a5
...
0x018af0e2: lui   a5,0x1
0x018af0e4: add   s1,a5          # original a0 + 0x1000
0x018af0ec: ld    a4,-0x468(s1) # original a0 + 0xb98
```

所以第一次 `+0x318` 调用同样接收未改写的原始 `a0`；随后该原始值从 `s1`
恢复，并用于同一个 `+0xb98` companion field。getter 返回值保存在 `s2`，后续
形成 `+0x4e04/+0x4e08/+0x4e0c`。

这里还有一个有用的 binary-only 区分：函数另外从 `a1+0x188` 取出第二个间接
方法。这说明 `a1` 可以是拥有另一套 method slot 的对象，而 `a0` 仍独立承担
共同 GPU-like layout 的角色；不能因为某函数地址被安装在另一对象的表中，就把
其第一个参数 `a0` 自动当作那张表的 owner。

## 5. 同一私有 layout 能确认到什么程度

### FACT

1. GB202 构造路径把 constant-return `0x01444500` 安装到
   `s11+0x318`。
2. 同一路径把 `0x0141579c` 安装到 `s11+0x1a0`；该函数在入口把同一
   `a0+0x318` 当作方法并把 `a0+0xb98` 当作 companion pointer。
3. 四个正校准函数调用 `+0x318` 时传入的都是各自原始 `a0`；四者都再次使用
   原始 `a0+0xb98`。
4. getter 返回值分别进入 `+0x3814`、`+0xc04`、`+0x74c` 和
   `+0x4e04/+0x4e08/+0x4e0c` 的简单形成过程。

### 强 INFERENCE

相关 `a0` 是同一种私有 GSP GPU-like object layout，且其 `+0x318` 字段承担
primary fuse base getter 语义。支持它的不再只是“返回值碰巧是 `0x820000`”，
而是：

```text
GB202 per-chip constructor selection
    + same-object method installation
    + unchanged-a0 receiver passing
    + repeated (+0x318, +0xb98) field pair
    + four independent fuse-relative return uses
```

公开 host 源码只用于给 `0x3814/c04/74c/4e04...` 提供人类语义校准；该推断本身
不要求 host `OBJGPU` 与 GSP 私有对象具有相同 offset。

### UNKNOWN / 不应宣称

- 私有对象正式名是否就是 `OBJGPU`；stripped ELF 没有 symbol/type info。
- 私有 `+0x318` 字段的正式 NVOC 名称。
- 私有 layout 与公开 host layout 是否只做了裁剪、是否重排，或是否是另一生成
  版本。公开 host getter 在 `+0x460`，明确不能称为 offset/ABI 对齐。
- 除四个正校准点以外的其他 `base+0x318` 候选是否属于同一对象。裸 offset 可被
  任意类型复用。
- `+0xb98` companion field 的正式字段名；本轮只证明其数值和共同使用方式。
- 该 getter 存在不等于存在 `+0xf8` setter；本报告没有扩大此前 0-match 的证明域。

## 结论

原先最薄弱的环节——“四个正校准点是否真的把同一类 receiver 传给
`+0x318`”——现在得到 binary-only 的显著加强：四处都传递未改写的原始 `a0`，
且四处共同访问 `a0+0xb98`；其中 `+0xc04` 函数和 `+0x318` getter 还由
GB202 的同一条构造路径安装到同一个 `s11` 对象。

因此，把这四个相关字段解释为私有 GSP primary-fuse-base getter 是**强行为推断**，
而不是公开 ABI FACT。正式类型名、字段名和其余裸 `+0x318` 候选仍保持 UNKNOWN，
这正是当前证据能支持而不过界的等级。

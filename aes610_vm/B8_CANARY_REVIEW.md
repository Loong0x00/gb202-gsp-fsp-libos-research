# B8 610.57 静态审阅：最小读写 canary 与恢复约束

## 范围与证据

仅离线分析 `/home/user/rt_5090_project/power_governor_reverse/gsp_mclk4000_review_20261010/parent_capability/gsp61057_full_main_view.elf`；没有访问 GPU、启动 VM、写 MMIO、改硬件或运行任何 canary。反汇编直接取自该 ELF 的 `.gsp_rx`。`readelf` 显示 `.gsp_rx` VA 为 `0x01000000`，长度 `0xe9b000`，本报告涉及的三个地址都落在该段。该 ELF view 的 SHA-256：`8b66217940da2cc4de6869ce613a599ceda6734adf6305c83b6b77e041d8b781`；`full_main_provenance.json` 将其对应到 610.57.04 完整 main ELF。以下结论以本次 ELF 指令为准，不以旧 B8 说明为 ABI 证据。

## 1. B8 backend 的实证语义

### 签名及参数块字段

`0x0100cf9c` 使用标准 RV64 入参寄存器：`a0, a1, a2, a3, a4`。在函数中 `s1=a4`，所以 `a4` 是元数据/映射参数块基址；`a2` 是长度，`a3` 是 flags。

| `a4` 相对偏移 | 指令证据与语义 |
|---|---|
| `+0x08` | 低窗口的长度上界。`flags&0x100==0` 时，比较 `offset >= *(u64 *)(arg+8)`，命中则返回 `0x1e`。它是相对 `+0x78` 的跨度，不是 GPU VA 基址。 |
| `+0x18` | 第二窗口的长度上界。`flags&0x100!=0` 时使用；同样按 `offset >= *(u64 *)(arg+0x18)` 拒绝。 |
| `+0x78` | 共用的 GPU VA 窗口基址。指令先将被选作 GPU VA 的参数减去 `*(u64 *)(arg+0x78)`，所得为窗口内 offset。 |
| `+0x80` | 第一窗口页基址数组指针。低窗口选择后，函数读取 `*(u64 *)(arg+0x80 + ((offset >> 12) * 8))`。 |
| `+0x88` | 第二窗口页基址数组指针。`flags&0x100` 选择它；在使用前检查该指针非零。它不是回调函数指针。 |
| `+0x90` | 成功复制后读取的可选 byte 开关。最小 canary 置零，避免走可选 service-8 路径。 |

重要指令：`0x100cfb4` 提取 `flags&1`；未置位时在 `0x100cfc6` 对 `a1` 减基址，置位时在 `0x100cff0` 对 `a0` 减基址。窗口 selector `flags&0x100` 在两种方向下都独立生效：未置位用 `+8/+80`，置位用 `+0x18/+0x88`。

### flags 方向

代码在调用复制 service `0x1a9e19e` 前明确摆放了实参：

- `flags&1 == 0`：被翻译的 GPU VA 来自 `a1`；service 收到 `a0=原 a0`、`a1=已翻译页地址`、`a2=len`。这是 **GPU VA → 本地缓冲区**（读）。
- `flags&1 != 0`：被翻译的 GPU VA 来自 `a0`；service 收到 `a0=已翻译页地址`、`a1=原 a1`、`a2=len`。这是 **本地缓冲区 → GPU VA**（写）。

当前代码调用点交叉验证了方向：`0x0101618c` 置 `a3=0` 后调用 backend（读）；`0x0101695a–0x01016972` 置 `a3=0x101` 后调用 backend（写 + 第二窗口）。因此，`0x100` 不是方向位，而是窗口选择位；`0x1` 才是方向位。

### 页查找与返回路径

backend 对 GPU VA 先减 `arg+0x78`，用 `offset >> 12` 乘 8 作为页数组索引，再将页项 qword 加上 offset 的低 12 位。它没有解码硬件 PTE flag，也没有检查单个页项是否为零；它把页项直接当作 firmware 可访问的页地址基址使用。空的页数组指针会走缺页表错误（返回 `0x40`）；数组项本身必须是有效、可访问的页基址。

边界检查只验证 **起始 offset** 小于跨度，不验证 `offset+len`。调用方必须额外保证整个 transfer 在窗口内且不溢出。本 canary 用 4 字节、页内对齐，规避跨页边界。

数据搬运 helper 的返回值被窄化为 byte（`0x1a9e19e` 最后 `zext.b a0`；函数体发出 `t0=0x20; unimp`，这是固件自定义 trap/service 序列，不把它误称为标准 RISC-V syscall）。backend 对非零结果重试最多 3 次，耗尽返回 `0x8c`；长度越界返回 `0x1e`；页数组缺失返回 `0x40`。零返回走成功分支，经 `t0=0x21` 的 trap/service 路径及 fence 后最终返回 0；若 `arg+0x90` 非零，还会额外走 `0x1a9e45c`。因此，**仅看到 callback/backend 返回 0 不能证明目标数据已写入**。

## 2. 当前地址下的最小真参数块

以用户给出的窗口基址为准：`GPU_BASE=0x20800000`。若 `metadata base 0x0fe4790e10` 就是 backend 的 `a4`，相关字段绝对地址为：`+8=0x0fe4790e18`、`+0x18=0x0fe4790e28`、`+0x78=0x0fe4790e88`、`+0x80=0x0fe4790e90`、`+0x88=0x0fe4790e98`、`+0x90=0x0fe4790ea0`。若该地址只是某个 backing allocation 的基址而非传给 `a4` 的指针，则这些绝对地址应改以实际 `a4` 计算；字段偏移语义不变。

为兼容 610.57 已观察到的真实读写 flags（读 `0`，写 `0x101`），最小块须同时提供两个窗口描述。建议分配至少 `0x98` 字节、8-byte 对齐：

```c
struct B8_min_map {
    uint8_t  reserved00[0x08];
    uint64_t span0;       // +0x08 = 0x41000, exclusive offset limit
    uint8_t  reserved10[0x08];
    uint64_t span1;       // +0x18 = 0x41000, exclusive offset limit
    uint8_t  reserved20[0x58];
    uint64_t gpu_base;    // +0x78 = 0x20800000
    uint64_t *pages0;     // +0x80, 65 qwords for indices 0..64
    uint64_t *pages1;     // +0x88, can alias pages0 for identical mapping
    uint8_t  optional;    // +0x90 = 0
    uint8_t  padding[7];  // allocation ends at +0x98
};
```

`0x41000` 覆盖 `[0x20800000, 0x20841000)`；足以涵盖 queue VA `0x20801000` 的 4 字节读和 QOUT VA `0x20840000` 的 4 字节写。页数组所需项：

- command queue：`offset=0x1000`，页索引 `1`，页内偏移 `0`；`pages0[1]` 必须指向该 GSP VA 页在 firmware 可访问视图中的页基址。
- QOUT：`offset=0x40000`，页索引 `64`，页内偏移 `0`；`pages1[64]` 必须指向 QOUT 页基址。

backend 对两个数组只做 qword 查表，因此，如果两窗口的实际映射完全相同，`pages1` 可与 `pages0` 指向同一数组；否则必须是各自正确的数组。这里的数组项是被直接 dereference 的页基址，不是未经转换的 NVIDIA 硬件 PTE。仅凭 ELF 无法证明运行时页基址/权限/缓存属性，也无法从 `0x0fe4790e10` 推出数组项内容；需要由提供该 metadata 的现有 KMD/GSP 映射建立方保证。

如果只测直接 backend 的 `flags=0/1`，可以只依赖 `+8/+80`；但这不兼容本 ELF 中 `flags=0x101` 的真实写调用点，故不作为完整 B8 canary 的参数块。

## 3. 可区分三种阶段的单次 canary（设计，不执行）

使用独立、隔离的测试 ring/window；不要向正在使用的生产命令队列塞测试字节。输入页和 QOUT 均为用户给出的 VA，操作限制为对齐的 4-byte transfer：

1. **callback executed：**在隔离测试 harness 中，对 B8 callback/backend 入口的精确 `(VA,len,flags)` tuple 做独立计数/trace（例如 test-only wrapper 的入口计数；若只观测 `t0=0x20` trap，则它证明已到达 data-move helper，不等价于函数入口）。计数通道必须独立于 QOUT；wrapper 随后调用原始 `0x0100cf9c`，不能仅模拟成功。当前 ELF 本身没有可见的持久化 callback-entry 计数器；若测试环境不能独立观测入口，就不能声称已区分这一阶段。
2. **queue read：**测试 queue 在 `0x20801000` 放入唯一 cookie（如 `0x5151b807`），读调用使用 `(a0=&scratch, a1=0x20801000, a2=4, a3=0, a4=map)`。只有原始 backend 返回 0、scratch 精确等于 cookie，且正常 pump/consumer 状态完成预期的 4-byte 消费（读指针按容量正确推进、available 相应减少）才记 `queue_read=1`。仅计数到 callback，或仅看到 pump 返回 0，不够。
3. **output written：**先把 QOUT 初始化成 poison 值；从已读 cookie 产生一个不同的固定输出 marker。写调用采用已见真实方向/窗口 flags：`(a0=0x20840000, a1=&marker, a2=4, a3=0x101, a4=map)`。只有 backend 返回 0 **且**在正确同步/可见性处理后，从 QOUT 独立读回 marker 才记 `output_written=1`。不能用“写 callback 被调用”替代读回。

结果应保留三个独立状态，而非一个 `success`：`callback_count`、`queue_read`（cookie + consumer bookkeeping）、`output_written`（QOUT readback）。这样可以区分入口已执行但读失败、队列数据已读但输出未写、以及三者全部完成。`0x01004c6c` 的刷新 callback 出错分支最终把返回值置 0，故测试 harness 应额外记录底层 callback 的原始 status；不能把该 pump 返回 0 当作刷新成功证明。

## 4. B8 pump 的必要恢复/修复

`0x01004c6c` 和 `0x01004cdc` 不是 backend；它们从 stream 对象取 callback 指针 `ctx+0xb8`，把 backend 参数指针 `ctx+0xc0` 作为第五参传入：

- `0x1004c6c` 刷新 producer 状态时调用 `(dst=&ctx+0x8c, src=*(ctx+0x38), len=4, flags=0, arg=ctx+0xc0)`，对应 GPU VA → local 的读。
- `0x1004cdc` 消费时先推进/回绕 `ctx+0x9c`，然后写 `(dst=*(ctx+0x40), src=&ctx+0x9c, len=4, flags=1 | (ctx[0xa5] ? 0x100 : 0), arg=ctx+0xc0)`。因此 `ctx+0xa5` 非零会切到第二窗口；这条路径不能只配置 `+8/+80`。
- `0x1004cdc` 的 backend 非零时会回滚本地 `+0x9c` 并返回 `-2`；成功才减少 `+0xa0` available，并继续可选 `+0xd0/+0xe0/+0xa8` 通知。回滚只覆盖本地 ring index，不会撤销已经发生的远端部分写，因此 B8 callback 必须保证 full-copy-or-error，避免“写了一半后报错”。
- `0x1004c6c` 对 callback 非零状态不向上返回该错误，而是走 `a0=0` 返回；这是状态观测盲点，不是底层传输成功的证明。

若确需多 callback/临时 wrapper：优先安装一个透明 dispatcher，保存原始 B8 函数指针并直接调用保存值（不要经 `ctx+0xb8` 递归调用自己）；每个未匹配请求原样委托。必须维持 ABI、参数次序、len、flags 和第五参 `ctx+0xc0`。若不得不临时换 callback，串行化整个多步操作，并在所有成功、错误和 timeout 出口恢复原 `(ctx+0xb8, ctx+0xc0)` 及被临时改动的 queue 状态；不要跨请求留下 wrapper/context。原 callback 返回非零时 backend 会最多重试三次，任何“副作用已发生但返回失败”都可能造成重复写。

## 与当前指令冲突的旧式解释/做法

- 把 `arg+0x80/+0x88` 当函数指针/回调：当前代码将它们作为按页索引的 qword 数组指针；真正被 pump 间接调用的 callback 在 stream `ctx+0xb8`，第五参 context 在 `ctx+0xc0`。
- 把 `arg+0x08/+0x18` 当 VA base 或 byte pointer：当前代码将其作为相对 `arg+0x78` 的 exclusive 长度上界。
- 认为 flags `0/1` 只选读写以外的模式，或认为 `0x100` 是读/写方向：当前指令证明 bit0 决定方向，bit8 选 `(+8,+80)` 与 `(+18,+88)` 窗口组。
- 仅填 `+80`，却照真实 `flags=0x101` 写 QOUT：该调用必走 `+0x18/+0x88`；缺字段会越界或走空表错误。
- 以 callback 入口计数、pump 返回 0、或 backend 返回 0 单独宣布读/写成功：当前 pump 会更新自己的记账，刷新路径还会吞掉 callback 错误；输出必须独立 readback。
- 让临时 B8 wrapper 返回 0 但不实际搬数据，或在复制/提交后返回非零：前者会制造假消费/状态不同步，后者会触发 backend 最多三次重试并可能重复副作用。

## 静态核验记录

已运行的只读命令：`readelf -h -l -S <full_main_view.elf>`；`llvm-objdump -d --start-address=0x1004c40 --stop-address=0x1004e30 <full_main_view.elf>`；`llvm-objdump -d --start-address=0x100cf50 --stop-address=0x100d140 <full_main_view.elf>`；以及对调用点 `0x1016130..0x10161d8`、`0x101695a..0x10169a8` 的定点反汇编。未改 ELF、驱动源码、固件或硬件。静态分析不能证明运行时 PTE 内容、权限/缓存一致性、metadata 的实际传入地址，或当前 callback 是否在任何运行时已执行；这些均需后续在获准且隔离的环境单独验证，本任务不执行。

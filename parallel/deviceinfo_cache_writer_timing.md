# GB202 DeviceInfo2 cache / raw-shadow writer 时序审计

日期：2026-07-21
状态：完成；纯离线、固定小窗口

## 范围与安全边界

本轮只回答一个窄问题：`GpuSubdevice` 内的 PTOP DeviceInfo2 cache
（56 个 vector，`+0x158..+0x697`；lazy flag `+0x698`）相对以下动作的顺序：

- `NewFuse.SetSwFuses -> ProgramSwFusePlan`；
- latch `0x404f0001` 的 read-modify-write；
- 每个 raw plan 项的 write / immediate readback；
- floorsweep FSP task `2` / subobject `1`；
- floorsweep cache invalidator `0xdd2520`；
- writer 成功后的 reset/reinitialize。

材料限于：

- `mods_audit/static/extracted_inner/mods`，SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- 该 ELF 的已知函数固定小窗口；
- `parallel/fuse_instance_map_lifecycle.md`、
  `parallel/task2_lifecycle_audit.md`、
  `parallel/reghal_writer_transport.md`、
  `parallel/shadow_reset_lifecycle.md`、
  `parallel/reset_selection_inputs.md` 与
  `parallel/rmregops_lifecycle.md`、
  `parallel/postreset_deviceinfo_cache_lifetime.md`、
  `parallel/deviceinfo_instance_nomatch.md` 与
  `parallel/deviceinfo_reset_stability.md` 的既有结论。

没有运行 MODS，没有访问 GPU、设备节点、BAR/MMIO、PCI config、驱动或固件，
没有 reset/rebind/reboot，也没有进行 whole-binary 反编译或大范围扫描。

下文严格使用：

- **FACT**：固定指令窗口或既有已闭合静态证据直接支持；
- **INFERENCE**：由这些事实得到的最窄生命周期解释；
- **UNKNOWN**：当前静态材料不能决定。

## 结论先行

### 1. 同一次 `ProgramSwFusePlan` 内，base 在正常串行路径上不会重建或改变

**FACT：** 每次 latch/raw 访问都会重新调用 domain-5 base resolver；writer
并没有在函数入口把 base 单独 snapshot 一次。可是 resolver 的第一次查询若发现
`+0x698 == 0`，会建立全部 DeviceInfo2 vectors，随后把 `+0x698` 置 1；后续查询
只读同一份 cache。`ProgramSwFusePlan` 本体没有调用 invalidator、FS task 2 或
reset/reinit。因此在已审计的单线程串行调用链上：

```text
第一次 domain-5 查询：必要时 build cache -> flag = 1 -> 得到 base
后续 latch/raw 查询：复用同一 cache              -> 得到同一来源的 base
```

普通 accessor 固定请求 class `0x10` / instance 0，resolver 必须按三种情况描述：

1. class vector 为空：走 fixed-selector instance-0 fallback `0x820000`；
2. class vector 非空且 exact instance 0 存在：返回该 record 的
   `devicePriBase`；
3. class vector 非空但 exact instance 0 缺失：**不 fallback、不报错**，而是读取
   `vector.end()+0x18` 的越界 dword 并把它当 base。

第三种是 unsafe no-match，不是合法 base 来源，离线安全模型必须拒绝。对前两种
正常形状，各次查询都复用同一 cache/source。即使首次 builder 记录错误并提前
返回，调用者仍把 flag 置 1，故该次 plan 也会持续使用当时形成的空/部分 cache，
而不会在下一 raw 项自动重试。

**边界：** cache 没有在这些小窗口中表现出锁或 generation counter。若另一个线程
能并发调用 `0xdd2520`，理论上两个 plan 项之间可以发生重新建立；但是否允许这种
并发、MODS 上层是否串行化 NewFuse/FS 操作均未闭合。因此“同一 plan 稳定”严格
适用于已见串行控制流，不是跨线程原子性保证。

### 2. 首个潜在建立点在 latch 的旧值读取，不必等到第一个 raw 项

`ProgramSwFusePlan` 在安全级别通过后，先发 constant `0x404f0001`。这个
constant setter 不是 blind store，而是 RegHal read-modify-write：先经
`GpuSubdevice +0x228` 读 `0x820040` 的旧 word，再经 `+0x238` 写合成值。两次
访问都进入同一 domain/instance wrapper。因此：

- 若 cache 在进入 writer 前已经建立，latch read 直接复用它；
- 若 cache 此时无效，latch 的 **read half** 是本 writer 内最早的 lazy-build
  机会；
- latch 的 write half、随后每个 raw write/readback 都看见已经置 1 的 flag。

这也意味着不能把“第一个 L2 raw write”描述成必然的首次 DeviceInfo2 查询。

### 3. FS invalidator 位于 task 2 / host apply 之后、可选 post-FS reset 之前

在正常 FSP-enabled、首次 eligible FS 成功路径中，顺序是：

```text
task 2/subobject 1 send + synchronous completion
  -> pending host floorsweep apply（若 pending）
  -> post hook
  -> set FS initialized/bookkeeping
  -> 0xdd2520: vectors.end = vectors.begin; +0x698 = 0
  -> return from GB20xFs Apply
  -> Gpu::Initialize 可选 post-FS reset
```

所以 task 2 本身不是已见的 cache invalidator；`0xdd2520` 是 host 在成功 FS
主线尾部另外调用的。task-2 status 非零、host apply/post-hook error 等提前退出
路径不会到达这个 invalidator。

`0xdd2520` 只清空逻辑长度并清 flag，不立即读取 PTOP，也不立刻算出新 base。
下一次 `0xdeda50` 或 `0xdd2230` 才会重新解析当时的 DeviceInfo2 hardware rows。

### 4. `SetSwFuses` 自己的 post-program reset 不等于 cache refresh

**FACT：** 所有 plan 项完成 write/readback、aggregate status 为 0 后，
`SetSwFusesCore` 才进入 post-program callback，再进入 coupling-selected
reset/reinitialize。writer 本体与这段 success callback 之前都没有
`0xdd2520`。

后续同对象生命周期审计已闭合这条 visible host path：

- `0x127b000 -> 0xdff7b0 -> 0xdfe3d0` 在 reset 前后保留并继续使用同一个
  `GpuSubdevice*`；
- dispatcher 不调用该对象的 constructor/destructor，不调用 `0xdd2520`，也不写
  `+0x158..+0x698` 的 vectors/flag；
- 可选 recovery reset 仍复用同一对象。

因此对 normal `SetSwFuses` post-program reset，结论是 **FACT：built
DeviceInfo2 cache 保留，reset 本身不会使下一次 resolver 自动重读 PTOP 表。**
这只闭合当前 570.151 可见 host 路径；它不证明硬件 DeviceInfo2 寄存器在 reset
边沿不 reload，也不证明 raw L2 shadow 已被 effective topology 采纳。

## FACT：逐步调用时序

### A. cache 的建立、查询和失效原语

`0xdeda50(this, type)`：

```text
0xdeda5b  if this+0x698 == 0
0xdeda64      call virtual +0x1080          # GB202 builder 0xdec350
0xdeda6d      this+0x698 = 1
0xdeda74  inspect vector at this+0x158+24*type
```

`0xdd2230(this, type, instance)` 有相同 lazy guard：

```text
0xdd2230  test this+0x698
0xdd2244  call virtual +0x1080 when zero
0xdd224d  this+0x698 = 1
0xdd2256  scan vector and return matching record+0x18 devicePriBase
```

`0x1252200` 先在 `0x1252215` 调 `0xdeda50`：

- unique instance count 为 0：用 fixed selector；
- 非 0 且 exact instance 存在：tail-call `0xdd2230(type, instance)`，取 hardware
  record base；
- 非 0 但 exact instance 缺失：同一 tail-call 最终读取
  `vector.end()+0x18`；不重试 fixed selector。

`0xdd2520` 则执行相反动作：对 56 个 vector 把 end 指针恢复为 begin，最后在
`0xdd2545` 清 `+0x698`。它保留 allocated capacity，不调用 builder。

### B. writer 中最早的 resolver 调用

`ProgramSwFusePlan 0x1515ea0` 的可见顺序：

```text
0x1515eb4  读取 host security level
0x1515ed8  handler +0x78(0x404f0001)
             -> 0x151b6c0 constant decode
             -> 0x198b410 RegHal RMW
                0x198b4fe  GpuSubdevice +0x228 read old latch word
                0x198b565  GpuSubdevice +0x238 write merged latch word
0x151600a  对第一个/下一个 plan node 开始 raw write
```

GB202 的 `+0x228/+0x238` 分别绑定 `0xdb68a0/0xdb5540`。二者每次都调用
`GpuSubdevice +0x218` 解析 `(domain, instance)` base，再把它加到本次 relative
offset 上。domain 5 在 GB202 `+0x218 = 0x125b720` 中进入
`0x1252200(class=0x10, instance=0, selector=0x10ef4000)`。

因此若此前 flag 为 0，最早的 latch old-word read 已足以触发全表 builder；
同一次 RMW 的 write 不会重新 build。

### C. 每个 raw plan 项

每项的精确 host 顺序是：

```text
node+0x20 relative offset, node+0x24 requested value
  -> 0x151606b handler +0xb8 raw write
     -> 0xdb5540 -> base resolver -> low-level write
  -> optional wait/delay path
  -> 0x1515fb3 handler +0xc0 raw readback
     -> 0xdb68a0 -> base resolver -> low-level read
  -> compare readback against node+0x24
  -> advance to next node
```

也就是说 base resolver 在一项中至少走两次，但 `+0x698` 使二者复用同一
DeviceInfo2 snapshot。普通 mismatch 累计 `0x79`；privilege sentinel
`0xbadf510c` 只记日志。这些 status 语义不改变 cache 时序。

### D. reset 只发生在 plan 完成之后

`ProgramSwFusePlan` 返回后，`SetSwFusesCore` 只在 aggregate success 时调用
post-program slot `+0x370`；该链最后进入：

```text
0x127b000
  -> 0xdff7b0
  -> 0xdfe3d0 coupling-selected reset/reinitialize
  -> optional recovery second reset
```

因此已见串行路径不存在：

- 在 latch RMW 与第一个 raw 项之间 reset；
- 在两个 raw plan 项之间 reset；
- 在某项 write 与它的 readback 之间 FS task 2 或 `0xdd2520`；
- reset 后回到同一个 `ProgramSwFusePlan` 继续剩余项。

programming error 则跳过 post-program reset，但同样没有在错误尾调用
`0xdd2520`。

## FACT / INFERENCE / UNKNOWN：完整时间线

下表把普通 MODS 生命周期与函数内硬顺序分开，避免把“通常先初始化”写成 API
强制条件。

| 时点 | 动作 | cache 状态/影响 | 等级 |
|---|---|---|---|
| T0 | `GpuSubdevice` constructor | 56 vectors 空，`+0x698=0` | **FACT** |
| T1 | 任意早期 DeviceInfo2 query | 首次 query 可 build 并置 1；可能早于 FS | **FACT / 是否发生 UNKNOWN** |
| T2 | 首次 eligible FS：task 2 send/wait | 不直接改 host cache；非零 status 阻止后续主线 | **FACT** |
| T3 | pending host apply / post hook / bookkeeping | 成功后才到 invalidator | **FACT** |
| T4 | `0x1095ffa -> 0xdd2520` | vectors 逻辑清空，flag 清 0；尚未 rebuild | **FACT** |
| T5 | `Gpu::Initialize` 可选 post-FS reset | 位于 T4 之后；若中间无 query，下一次 resolver 已因 T4 的 explicit invalidation 而需要 rebuild | **FACT（顺序与条件）** |
| T6 | 普通已初始化对象调用 `SetSwFuses` | 正常生命周期通常在 T2-T5 后，但 API body 没有 phase guard | **INFERENCE / guard UNKNOWN** |
| T7 | latch RMW read | flag 为 0 时 build；否则复用现有 snapshot | **FACT** |
| T8 | latch write；每项 raw write/readback | 每次 resolve base，但在串行路径中不 invalidate | **FACT** |
| T9 | aggregate success 后 reset/reinit | plan 已全部结束；同一 `GpuSubdevice*` 与 built DeviceInfo2 cache 保留 | **FACT** |
| T10 | normal post-program reset 后第一次 base query | 复用 reset 前 built snapshot；reset 本身不触发 parse | **FACT（visible host path）** |

## 回答：base 何时会在 reset 后真正刷新

### 已证明可以刷新的两种软件条件

1. **reset 前已经由 FS 主线执行 `0xdd2520`，且直到 reset 完成前没有任何查询
   把 flag 再置 1。** 这时 reset 后第一次 resolver 会解析 post-reset 时刻可见的
   DeviceInfo2 rows。普通 `Gpu::Initialize` 的顺序为“FS invalidation -> 可选
   post-FS reset”；刷新条件已由 reset 前的 explicit invalidation 建立，不需要把
   reset 本身解释成通用 cache invalidator。
2. **reset 后又成功走一次包含 `0xdd2520` 的 FS apply。** invalidator 返回后，
   下一次 resolver 才重建。它刷新的是“FS apply 完成以后”的 hardware table，
   不是 task-2 response 内携带的某份 host snapshot。

### 条件成立时也不代表 numeric base 必然改变

重新解析只能保证 cache **重新取样**；是否从 `0x820000` 切到别的来源、class
`0x10` 是否出现/消失、instance-0 `devicePriBase` 是否改变，均取决于 reset/FS 后
的 PTOP DeviceInfo2 内容。本卡没有 live capture，故 numeric result 是
**UNKNOWN**。最合理的产品设计仍是 instance-0 base 保持 `0x820000`，但不能把
该预期升级为本卡 runtime FACT。

### 已排除和仍未证明的刷新来源

- **已排除（visible normal path）：** normal `SetSwFuses` post-program reset 自动
  调用 `0xdd2520`、清 host 对象的 `+0x698`，或销毁并重建 `GpuSubdevice`；
- **仍未证明：** 未见动态/外部模块路径在 reset 中另行 clear；
- FSP task 2 自动更新这些 host vectors；
- 每个 raw plan 项都重新读取 PTOP hardware table。

后三项仍不应写成事实。

## 对解锁研究的直接含义

1. **同一 plan 内的多个 L2 项不会因正常串行时序各自得到不同 base。** 这排除了
   “第一个 FBP 写到 fuse base、后一个 FBP 因 task2/reset 改到另一 aperture”这类
   普通控制流解释。
2. **地址转换仍不是硬编码绝对地址。** 每项都会执行 resolver；稳定性来自 cache
   lifetime，而不是 writer 保存了一份 immutable base。
3. **normal post-program reset 后的下一次 writer 继续使用 reset 前 DeviceInfo2
   snapshot。** 只有后续 explicit `0xdd2520` invalidation 或完整对象销毁/重建才
   会改变这条 visible host cache 条件；这不等于硬件表或 effective topology 未变。
4. **cache refresh 不是 topology 验收。** 即便重新解析了 DeviceInfo2，它也只给
   register aperture base/engine inventory；它不验证 raw L2 bit 是否被 effective
   topology 接纳，更不证明被重新启用的 LTS 物理健康。

## 最小可引用结论

> GB202 MODS 的 latch RMW 与每个 raw write/readback 都重新走 domain-5 resolver，
> 但 resolver 的 PTOP DeviceInfo2 table 是 `GpuSubdevice` 持有的 lazy cache。若
> cache 尚未建立，本 writer 内最早可在 latch old-word read 时建立；之后 flag
> 保持为 1，且 `ProgramSwFusePlan` 不含 FS task2、invalidator 或 reset，所以同一
> 串行 plan 使用同一 base 来源。成功 FS 主线的 `0xdd2520` 位于 task2/host apply
> 之后、可选 post-FS reset 之前，只负责清 vectors/flag；下一次 query 才重建。
> normal `SetSwFuses` 的 post-program reset 则保留同一 `GpuSubdevice*` 与 built
> cache，不调用 `0xdd2520`，也不触碰 vectors/flag；因此 reset 后第一次 resolver
> 继续复用 pre-reset snapshot，不会仅因该 reset 自动重读 PTOP。class `0x10` 的
> base 解析必须分成空 vector fallback、exact instance-0 match，以及非空但缺
> instance 0 时的 unsafe no-match 三种情况。

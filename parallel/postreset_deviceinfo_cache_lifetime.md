# normal post-program reset 与 DeviceInfo2 cache 对象生命周期

日期：2026-07-21
状态：完成；纯离线、资源受限审计

## 结论先行

`NewFuse.SetSwFuses` 成功尾声的 coupling-selected reset/reinitialize **保留同一个
host `GpuSubdevice` C++ 对象**；它做的是该对象所管理设备的 state
unload/reset/state load，而不是析构并重新创建 `GpuSubdevice`。

最直接的证据是：

```text
0x127b000  save incoming GpuSubdevice* in RBP
0x127b009  call 0xdff7b0 -> 0xdfe3d0
           ... state unload / reset / state load returns ...
0x127b020  pass the saved RBP to another GpuSubdevice method
0x127b02c  load vtable from [RBP]
0x127b033  call saved object's +0x208 method
...
0x127b067  optional recovery reset: pass the same RBP to 0xdff7b0 again
```

`0xdff7b0` 同样把传入指针保存在 `RBX`，然后把同一地址传给 `0xdfe3d0`。
`0xdfe3d0` 的正常 active-reset 路径也持续以原指针调用方法；设备重新 ready、配置
恢复完成后，它仍以该指针调用 `0xdfe0a0`，随后打印 reset succeeded。

因此，**不能再把 normal post-program reset 的 cache effect 标成“也许因为
`GpuSubdevice` 重建而自动刷新”**。对象重建这条候选已由当前可见 host 路径
排除。

对 cache 的窄结论是：

- `ProgramSwFusePlan` 在 reset 前已经经 domain-5 resolver 使用这张 cache；首次
  查询无论 builder 得到空表、部分表还是正常表，helper 都会把 `+0x698` 置 1。
- normal reset 链没有显式调用 cache invalidator `0xdd2520`，也没有触碰
  `+0x158..+0x698`，没有调用 `GpuSubdevice` 构造/析构链。
- 因而在**已见 host 路径**上，reset 后 cache 仍是 reset 前那份 built snapshot；
  下一次 resolver 不会仅因为这次 reset 自动重读 PTOP DeviceInfo2。
- 真正已证明的刷新来源仍是 FS Apply 中的 `0x1095ffa -> 0xdd2520`，或将来证明的
  另一条显式 invalidation；reset 本身不是刷新原语。

这只回答 cache lifetime，不回答 reset 后 DeviceInfo2 硬件表是否变化，更不回答
raw L2 mask 是否被 effective topology 接纳。

## 范围与安全边界

本轮材料限于：

- `mods_audit/static/extracted_inner/mods`，SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`；
- 已知函数的固定小窗口：`0x127b000`、`0xdff7b0`、`0xdfe3d0`、
  `0xdf2af0`、`0xddda70`、`0xdd2520`、GB202 destructor slots；
- 两次单目标、流式、低内存 `.text` direct-call 扫描；
- 当前项目已有时序报告；
- `/usr/src/nvidia-610.43.03` 的公开 OpenRM 源码仅作结构交叉核对。

没有运行 MODS，没有打开 GPU/设备节点，没有 BAR/MMIO、PCI config、ioctl、
debugfs、reset、模块操作或固件交互；没有 whole-binary 反汇编、Ghidra 导入或
大内存扫描。

下文使用：

- **FACT**：当前 ELF 的固定窗口或严格限定扫描直接支持；
- **INFERENCE**：多项事实共同支持，但未观察 runtime；
- **UNKNOWN**：当前静态材料不能决定。

## 1. cache 的构造、失效和析构原语是三件独立的事

### 1.1 构造

基础 `GpuSubdevice` constructor `0xdf2af0` 初始化对象自有的 56 个 vector：

```text
object +0x158 ... +0x697   DeviceInfo2 class vectors
object +0x698              lazy-built flag
```

`0xdf2c03` 开始构造 vector 区域，`0xdf2c5c` 用 word store 清
`+0x698/+0x699`。所以新对象天然得到空 vectors、`+0x698=0`。

### 1.2 显式失效

`0xdd2520` 不是 destructor。它把每个 vector 的 end 恢复到 begin，保留 capacity，
最后在 `0xdd2545` 单独写 `+0x698=0`。下一次 `0xdeda50`/`0xdd2230` 才重新解析
PTOP DeviceInfo2。

### 1.3 析构

GB202 vtable address point `0x92c8500` 的首两个槽为：

```text
+0x00  0x127c620   non-deleting destructor
+0x08  0x127c7e0   deleting destructor
```

两者都沿派生析构链到基础 destructor `0xddda70`。基础析构尾部
`0xdde2ad..0xdde2db` 从 `+0x680` 向下释放包含 DeviceInfo2 cache 在内的 vector
buffers。也就是说，如果 reset 真重建对象，机器码中应出现下列至少一类可见
生命周期动作：

- 对原对象调用 vtable `+0/+8`；
- 直接/间接进入上述 destructor chain；
- 再进入 constructor `0xdf2af0`，恢复空 vectors 与 flag 0；
- 或在原地址做一套等效的 in-place 重构。

已审计的 normal reset 链不包含这些动作。

## 2. 成功尾声明确依赖原 `GpuSubdevice*` 在 reset 后仍有效

### 2.1 accessor 到 GB202 post-program method

`0x151ad50` 从 handler `+0x8` 取出 `GpuSubdevice*`，再经其 vtable `+0x1b0`
跳到 GB202 实现 `0x127b000`。因此 `0x127b000` 的 `RDI` 正是 cache owner。

### 2.2 `0x127b000` 跨 reset 保存并继续使用同一指针

固定窗口给出：

```text
0x127b001  mov RDI,RBP                 # save original this
0x127b009  call 0xdff7b0
0x127b020  mov RBP,RDI                 # reset returned; same this
0x127b023  call 0xde3ac0
0x127b02c  mov [RBP],RAX               # dereference same vtable
0x127b030  mov RBP,RDI
0x127b033  call [RAX+0x208]
...
0x127b067  mov RBP,RDI
0x127b06a  call 0xdff7b0               # optional recovery reset, same this
```

这是对象存活的直接 **FACT**。如果 `0xdff7b0 -> 0xdfe3d0` 释放该 allocation，
`0x127b020` 之后就是确定的 use-after-free；如果换成另一个地址的新对象，保存的
`RBP` 也不会自动更新。

理论上可以想象“在完全相同地址析构后 placement-new”这种实现，但下一节的
constructor/destructor 负证据排除了当前可见链中的这种解释。

### 2.3 `0xdff7b0` 与 `0xdfe3d0` 也保留原 owner

`0xdff7b0` 在 `0xdff7b1` 把 `RDI` 存入 `RBX`，用同一对象调用 reset mapper，
再在 `0xdff829` 把 `RBX` 重新放入 `RDI` 调 `0xdfe3d0`。

`0xdfe3d0` 在入口把同一指针存入 `RBP`。正常设备 reset 的 active path 中：

- reset 前用该对象查询平台、设备与 coupling 相关方法；
- 等待 GFW/device ready 并恢复配置；
- `0xdff0f4` 又把同一 `RBP` 传给 `0xdfe0a0`；
- 随后经同一对象打印 `%s reset succeeded` 并返回。

函数退出清理临时 vector 时编译器会复用 `RBP` 寄存器保存局部 begin pointer；
这发生在 owner 的 active-reset 使用结束以后，不表示 `GpuSubdevice*` 被替换。

## 3. normal dispatcher 没有构造、析构或 cache invalidation

### 3.1 固定窗口结果

对 `0xdfe3d0..0xdff776` 的完整函数窗口检查得到：

- 没有 direct call `0xdf2af0`、`0xddda70`、`0x127c620`、`0x127c7e0`；
- 没有 direct call `0xdd2520` 或 FS dispatcher `0x1095e50`；
- 没有 `+0x158..+0x698` 的 cache store；
- 没有向原 owner 的 vtable `+0/+8` 调用 destructor；
- 没有写回 GB202 vptr `0x92c8500` 或基类 vptr 来做 in-place reconstruction。

函数内确有若干 `call [vtable+8]`，但其 receiver 来自局部临时对象/vector 元素，
不是保存在 owner `RBP` 中的 `GpuSubdevice*`。函数内唯一 `operator new` 位于
`0xdff608`，请求大小 `0x28`，用于本地 tree node；它不是 GpuSubdevice allocation。

### 3.2 单目标全 `.text` direct-call 扫描

在 `.text`（VA `0x4a0940`，file offset `0x0a0940`，size `0x8736b3a`）中只按
`E8 rel32` 形式流式扫描目标，结果为：

```text
target 0xdd2520  <- only 0x1095ffa
target 0x1095e50 <- only 0x106fed3
```

`0x1095ffa` 位于 generic FS Apply；`0x106fed3` 是 GB20xFs Apply wrapper。
`0x1095e50` 的静态函数指针出现在 `AmpereFs`、`AD10xFs`、`GA10xFs` 等 Fs
vtables 的 Apply 槽，它不是 `GpuSubdevice` state reset 槽。normal
`0xdfe3d0` 没有取 `GpuSubdevice+0x1810` 的 Fs object，也没有进入既有
`Gpu::Initialize -> Fs +0x18 -> 0x106fec0 -> 0x1095e50` 链。

另外，对整个 ELF 的精确 8-byte little-endian `0x0000000000dd2520` 搜索没有
静态函数指针命中。因此当前文件中没有把 invalidator 直接挂到某个 vtable 的
证据。

这些是严格限定的 host 静态负结果。它们不排除自修改代码、运行时计算出的函数
指针或当前 ELF 以外模块；当前没有证据表明这些机制参与 normal MODS reset。

## 4. state unload/load 不等于 C++ object destroy/create

MODS 日志和 dispatcher 顺序确实表明它会保存配置、卸载设备状态、发 reset、
等待 GFW、恢复配置并重载状态。这些动作可以销毁/重建低层 RM、GSP 或设备侧
状态；它们不自动销毁承载 JS/MODS API 与 DeviceInfo2 vectors 的 host
`GpuSubdevice` wrapper。

NVIDIA 610 OpenRM 是不同代码库，不能代替上述 MODS ELF 证明，但提供一致的公开
结构交叉核对：

- `gpuStateUnload_IMPL` (`gpu.c:3927`) 接收同一个 `OBJGPU *pGpu`，遍历现有
  `OBJENGSTATE` 并调用 `engstateStateUnload`，最后只更新 state flags；
- `gpuStateLoad_IMPL` (`gpu.c:2652`) 仍接收同一个 `OBJGPU *pGpu`，遍历现有
  engine objects 调 `engstateStateLoad`，最后设置 `bStateLoaded`；
- `gpuStateDestroy_IMPL` 是另一个独立入口 (`gpu.c:4203`)。

这与 MODS 中“同一个 owner 指针跨 reset 返回并继续使用”的机器码完全相容：
state transition 是对象的方法，不是对象本身的 lifetime transition。

## 5. 对 `SetSwFuses` 时序的具体影响

在普通成功链里，cache 状态是：

```text
ProgramSwFusePlan
  -> latch old-word read 经 domain-5 resolver
  -> if needed, build DeviceInfo2 vectors
  -> helper sets +0x698 = 1
  -> latch write + every raw write/readback reuse this snapshot
  -> aggregate success
  -> 0x127b000 -> 0xdff7b0 -> 0xdfe3d0
       state unload/reset/state load on the same GpuSubdevice object
       no visible 0xdd2520 / constructor / destructor
  -> return with the same host cache object
```

因此：

1. **FACT（visible host path）：** object reconstruction 不是 post-program cache
   refresh 来源。
2. **FACT（进入 reset 前）：** 本次 writer 已经让 lazy flag 处于 built 状态；
   即使 builder 当时失败/提前返回，caller 也会置 1，后续不会自动重试。
3. **INFERENCE（强、path-scoped）：** 未发生另一路显式 invalidation 时，reset
   后下一次 resolver 继续使用 reset 前 snapshot，而不是 post-reset PTOP 表。
4. **UNKNOWN：** 某个尚未识别的运行时计算 callback、外部模块或未来版本是否会
   增加 invalidation；当前 570.151 ELF 没有相应证据。
5. **UNKNOWN：** reset 前后硬件 PTOP DeviceInfo2 rows 是否实际改变。即使显式
   refresh，通常也可能仍解析出相同的 instance-0 base `0x820000`。

## 最小可引用结论

> `NewFuse.SetSwFuses` 成功后的 `0x127b000 -> 0xdff7b0 -> 0xdfe3d0`
> 保留并在 reset 返回后继续解引用同一个 `GpuSubdevice*`；optional recovery
> reset 也复用同一指针。该 dispatcher 没有调用 GB202/base constructor、
> destructor、DeviceInfo2 invalidator `0xdd2520`，也没有触碰
> `+0x158..+0x698`。全 `.text` 对 `0xdd2520` 的 direct-call 扫描只有 Fs Apply
> 内的 `0x1095ffa`。所以 normal post-program reset 是同一 host 对象上的
> state unload/load，不会因对象重建而天然刷新 DeviceInfo2 cache；在已见 host
> 路径上，writer 建立的 pre-reset snapshot 会继续保留，除非另有显式
> invalidation。该结论不证明 PTOP 硬件表、raw/effective L2 mask 或物理健康状态。

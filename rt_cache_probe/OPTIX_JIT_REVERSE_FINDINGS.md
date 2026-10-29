# OptiX JIT / TTU compiler reverse-engineering findings on RTX 5090

日期：2026-07-12  
环境：CUDA 13.3.73、Driver 610.43.03、OptiX 9.1、SM 120

## 结论摘要

逆编译器有明确收益，并且已经得到两类硬件级证据：

1. `optixTrace` 不会在公开的 raygen SASS 中表现为一条可见 TTU mnemonic。OptiX 把 shader 拆成 continuation states，借助 `.rt.info.*`、`__rtci_stateId` 与 RT runtime/硬件交接 traversal。
2. 强制编译 current-hit triangle vertex fetch 后，closest-hit SASS 中出现连续八条 CUDA 13.3 `nvdisasm`/`cuobjdump` 都无法命名的 128-bit 指令；低位 opcode 形成紧密的 D0–D4 家族。它们只出现在 `nv.rt.read.triangle.vertex.data` 路径，并与 `libnvidia-rtcore.so` 中的 `nv.rt.ttu.trifetch` / `nv.rt.ttu.trifetch.with.flags` 后端 intrinsic 对应。
3. 九个 component-liveness 变体进一步把 D2 的 `0x34/0x35` 区分为两个结果传输
   bundle candidate，把 `0x36` 区分为共同 finalize；D4 immediate `5/6` 随一个或
   两个结果 bundle 而变。from-handle 与 hit-object 两条合法 API 路径都不内联
   D0–D4。

所以 TTU 并非“只有一个 trace opcode”。至少存在 shader-continuation traversal ABI 和独立 triangle-fetch 指令族。

## OptiX disk cache 可以直接提取

OptiX 9.1 disk cache 是 SQLite：

```sql
CREATE TABLE cache_data (key VARCHAR(1024) UNIQUE, value BLOB);
CREATE TABLE cache_info (...);
```

每个 private envelope BLOB 内嵌一个或多个普通 CUDA ELF64/cubin。已实现只读提取器：

[`jit_cache/extract_optix_cache.py`](jit_cache/extract_optix_cache.py)

```sh
python3 jit_cache/extract_optix_cache.py \
  jit_cache/ias_probe_trifetch_20260712_b/optix7cache.db \
  jit_cache/ias_probe_trifetch_20260712_b/carved
```

当前探针的 123,538 B cache blob 内有四个主 ELF：

| ELF | 内容 | 大小 |
|---:|---|---:|
| 0 | miss、普通 closest-hit、trifetch closest-hit | 9472 B |
| 1 | forced-outside-root raygen continuation states | 33529 B |
| 2 | guaranteed-hit raygen continuation states | 33401 B |
| 3 | no-trace ring-control raygen | 7744 B |

缓存捕获目录：[`jit_cache/ias_probe_trifetch_20260712_b`](jit_cache/ias_probe_trifetch_20260712_b)

## `optixTrace` 的 continuation 结构

no-trace ring control：

```text
one .text function
4096 B SASS
no .rt.info sections
```

forced miss 与 guaranteed hit raygen 各自被拆为：

```text
ss_0: 6912 B
ss_1: 7296 B
ss_2: 7552 B

.rt.info.callsite
.rt.info.liveState
.rt.info.callstack
.rt.strtab
undefined __rtci_stateId symbol
```

可见 SASS 主要负责构造 ray state、保存 continuation live state，并以特殊 RT ABI 返回。真实 traversal 不表现为 raygen 里的 `TTU ...` 普通指令。这也解释了为什么 Nsight Compute 无法给 `optixLaunch` 提供完整常规 SASS source view。

IR/cache 字符串中仍保留：

```text
nv.rt.trace.17.0.1
nv.rt.throw.exception
```

## 捕获到的 TTU triangle-fetch opcode family

为了不改变 timing pipeline，探针增加了只在专用 JIT-cache capture 时链接、从不执行的：

```cpp
__closesthit__root_probe_trifetch()
{
    float3 vertices[3];
    optixGetTriangleVertexData(vertices);
    ...
}
```

OptiX module log 把它识别为 11 条 IR instruction；cache 中保留 `nv.rt.read.triangle.vertex.data`。最终 closest-hit cubin 的 SASS 在普通指令之间出现以下八个未命名 128-bit encoding：

| inferred offset | low 64 bits | high/control 64 bits | provisional family |
|---:|---|---|---|
| 0x770 | `0x00000000000073d0` | `0x000fec0000000000` | TTU.D0 candidate |
| 0x780 | `0x00000600000079d4` | `0x000fc80000000000` | TTU.D4 candidate |
| 0x790 | `0x00000002000003d1` | `0x000fe200000000ff` | TTU.D1 candidate |
| 0x7a0 | `0x000280ff000073d1` | `0x000fe20000000006` | TTU.D1 candidate |
| 0x7b0 | `0x00000000000073d3` | `0x000fe20000000000` | TTU.D3 candidate |
| 0x7c0 | `0x00034000000273d2` | `0x000e2200000e00ff` | TTU.D2 candidate |
| 0x7d0 | `0x00035000006873d2` | `0x000e2200000e00ff` | TTU.D2 candidate |
| 0x7e0 | `0x00036000000673d2` | `0x000e2400000e04ff` | TTU.D2 candidate |

原始反汇编：[`trifetch_ch.sass`](jit_cache/ias_probe_trifetch_20260712_b/carved/trifetch_ch.sass)

证据链：

- 普通 closest-hit 没有这八条编码。
- 只有增加 triangle vertex fetch intrinsic 后出现。
- 前后所有常规 SM120 指令均能被同一版 `nvdisasm` 正常命名。
- `cuobjdump --dump-sass` 同样只输出这八条的 hex，不给 mnemonic。
- `libnvidia-rtcore.so.610.43.03` 明确包含 `nv.rt.ttu.trifetch` 与 `nv.rt.ttu.trifetch.with.flags`。
- D0/D1/D2/D3/D4 opcode 连续成族，不像随机数据或 relocation hole。

因此可以高置信称为 **TTU triangle-fetch instruction family encodings**；当前还不能给每个 D 子操作命名。

### 受控 component-liveness 差分

同一 module 编译了九个合法变体，覆盖单分量、每个单独顶点、三个两顶点组合、
对角分量和全部九个 float：

| 变体 | live vertex data | D4 immediate | D2 slot sequence | hidden 数量 |
|---|---|---:|---|---:|
| `x` | `v0.x` | 5 | `0x34,0x36` | 7 |
| `v0` | `v0.xyz` | 5 | `0x34,0x36` | 7 |
| `v1` | `v1.xyz` | 6 | `0x34,0x35,0x36` | 8 |
| `v2` | `v2.xyz` | 5 | `0x35,0x36` | 7 |
| `v01` | `v0.xyz+v1.xyz` | 6 | `0x34,0x35,0x36` | 8 |
| `v02` | `v0.xyz+v2.xyz` | 6 | `0x34,0x35,0x36` | 8 |
| `v12` | `v1.xyz+v2.xyz` | 6 | `0x34,0x35,0x36` | 8 |
| `diag` | `v0.x+v1.y+v2.z` | 6 | `0x34,0x35,0x36` | 8 |
| `all` | all 9 floats | 6 | `0x34,0x35,0x36` | 8 |

D0 与 D3 保持不变，D1/D2 的寄存器/selector 位随 live components 改变。最小且
能解释全部九行的模型是：

```text
D2 slot 0x34  -> result bundle 0 transfer candidate
D2 slot 0x35  -> result bundle 1 transfer candidate
D2 slot 0x36  -> common finalize/commit candidate
D4 imm 5      -> one result bundle shape
D4 imm 6      -> both result bundles shape
```

`v1` 单独就需要两个 bundle，说明 bundle 边界不是“一个 vertex 一个 bundle”；它
更像按底层 packed result/register layout 切分。这个模型仍是 encoding 差分推断，
尚未给 D2 的每个 selector bit 命名。

机器可读结果：

- [`jit_cache/ttu_trifetch_component_summary.tsv`](jit_cache/ttu_trifetch_component_summary.tsv)
- [`jit_cache/ttu_dops_components_20260712.tsv`](jit_cache/ttu_dops_components_20260712.tsv)
- capture/raw SASS：[`jit_cache/ias_probe_trifetch_components_20260712_d`](jit_cache/ias_probe_trifetch_components_20260712_d)

`optixGetTriangleVertexDataFromHandle` 是另一条实现：当前 shader cubin 中没有
D0–D4，而是普通 `LDG`、状态解码和一次 indirect `CALL.ABS.NOINC R16`。新增的
`optixHitObjectGetTriangleVertexData` capture 同样没有 D0–D4；它展开为 hit-object
状态/原子同步/普通 load 路径。提取器在这两个函数中均返回零条 D-family encoding，
但同一 ELF 的 current-hit entries 仍返回 7/8 条，排除提取失败。

最简解释是 from-handle 与 hit-object 通过未内联 RT runtime/helper；
`nv.rt.ttu.trifetch.with.flags` 若被使用，位于系统 callable 或另一 continuation
state 中。capture：[`jit_cache/ias_probe_trifetch_hitobject_20260712_e`](jit_cache/ias_probe_trifetch_hitobject_20260712_e)。

### 最终 cubin metadata 的边界

`cuobjdump --dump-elf` 能解出 closest-hit 的 `.nv.info.__closesthit__*`，但 final cache ELF 中没有可见的 `EIATTR_RTCORE_ENTRY` 项；该属性很可能只存在于更早的内部对象或在最终链接时被编码/剥离。不能因为工具字符串存在就声称 final cubin 暴露了这个 flag。

current-hit fetch 变体相对普通 closest-hit：

| entry | registers | frame/stack offset | tool statistics |
|---|---:|---:|---|
| plain closest-hit | 107 | 0 | 45 instructions |
| current-hit trifetch | 108 | 0x10 | 116–121 instructions |
| from-handle | 107 | 0 | 176 instructions、2 exits |

所有 current-hit `D0–D4` 变体都有 `EIATTR_STACK_OFFSET=0x10`；from-handle 没有，但多出 indirect call/relocation。更关键的是，`cuobjdump` 的 statistics 对 current-hit 仍报告 `tex reads: 0`。因此隐藏 D0–D4 不是普通 TEX instruction，也不会被工具当成常规 texture read。

## 编译器/rtcore binary 暴露的其他信息

`libnvidia-ptxjitcompiler.so`：

```text
[est schedDisp=%d] [est tex=%d] [est ttu=%d] [est udp=%d]
[schedDisp thru=%f] [tex thru=%f] [ttu thru=%f] [udp thru=%f]
EIATTR_RTCORE_ENTRY
EIATTR_LD_CACHEMOD_INSTR_OFFSETS
EIATTR_LOAD_CACHE_REQUEST
```

`libnvidia-rtcore.so` 还暴露大量内部 intrinsic 名：

```text
nv.rt.read.blas.ptr.from.traversable
nv.rt.read.instance.child.from.traversable
nv.rt.read.instance.{transform,inverse.transform}...
nv.rt.read.triangle.vertex.data.from.traversable
nv.rt.hitobject.*
nv.rt.ttu.trifetch
nv.rt.ttu.trifetch.with.flags
```

这表明后端分别建模 traversal、instance/transform、triangle fetch 与 hit-object 操作。`EIATTR_LD_CACHEMOD_INSTR_OFFSETS` 证明编译对象能记录普通 load cache modifiers，但它与 `EIATTR_RTCORE_ENTRY` 同时存在并不等于 TTU opcode 有用户 cache-policy 位。

对 stripped x86 rtcore backend 的静态交叉引用还定位到：

```text
nv.rt.read.triangle.vertex.data  string 0x270d430 -> code xref 0x1fa714
nv.rt.ttu.trifetch               string 0x270cbe2 -> code xref 0x1fbb19
nv.rt.ttu.trifetch.with.flags    string 0x270cbf5 -> code xref 0x1fbd74
```

这些地址附近是 intrinsic registration/lowering builder，而不是可直接复制的 SASS opcode table；无符号 x86 CFG 分析没有比合法 OptiX 变体编译提供更多字段语义。当前最高收益方法仍是“让官方 JIT 生成合法 D0–D4，再做受控 IR/SASS 差分”。

## 与 AS backing-line 实验的交叉收益

编译器逆向负责告诉我们操作语义，地址干预负责告诉我们它实际消费哪条 AS line。两者目前已经对上：

```text
nv.rt.read.instance.child/transform...
    <-> IAS output+0x600 instance leaf/transform/child-root pointer

nv.rt.ttu.trifetch / nv.rt.read.triangle.vertex.data
    <-> GAS output+0x400 triangle primitive data

traversal continuation
    <-> IAS/GAS output+root-node lines
```

这不是说 `optixGetTriangleVertexData` 就是 traversal primitive test；它是 closest-hit 中独立取顶点数据的 TTU path。但同一 triangle-data backing line 与内部 intrinsic 名互相确认，使 `GAS+0x400` 的语义不再只靠浮点字节模式判断。完整地址图见 [`IAS_GAS_BACKING_LINE_FINDINGS.md`](IAS_GAS_BACKING_LINE_FINDINGS.md)。

## 下一步最高价值的逆向实验

1. 增加 ray-time/motion、不同 vertex format 和 live-register pressure 变体，继续
   确定 D2 selector 与返回寄存器组的逐 bit 映射。
2. 捕获真正会触发 `trifetch.with.flags` 的合法 OptiX API/geometry 组合，定位 helper 内或内联的第二种序列。
3. 比较 direct GAS、IAS、motion transform、cluster/OMM/LSS 程序的 cache ELF 与 hidden opcode 序列。
4. 将 D0–D4 字段差分与 Nsight 的 TTU throughput/stall 变化联立；在没有明确 ABI 前仍不注入 raw opcode。

不建议直接注入未知 D0–D4 raw opcode：目标 entry 需要特殊 RT ABI、寄存器状态和 metadata，错误编码可能触发非法指令或设备异常。静态差分和合法 OptiX intrinsic 编译已经足以逐步恢复字段，无需补丁驱动、绕签名或访问 MMIO。

## 当前对“能否找到 RT cache control”的判断

- 逆编译器很适合回答 **发射什么、分几阶段、状态如何交接、哪些字段属于 TTU**。
- 它可能发现 TTU request priority/cache bits，但目前 D0–D4 没有证据显示用户可控 cache operand。
- 对缓存内容与地址，AS output 热行实验比 compiler binary 更直接；目前已定位 one-triangle GAS 的三条关键 128 B 行。
- 已证可用的软件控制仍是 CUDA pre-touch + L2 persisting preference，而不是 TTU L0 直接控制。

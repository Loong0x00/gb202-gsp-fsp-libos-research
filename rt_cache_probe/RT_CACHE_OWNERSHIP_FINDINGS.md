# RTX 5090 RT traversal 状态的 SM 所有权实验

更新：2026-07-12  
设备：RTX 5090（GB202，CC 12.0，170 SM）  
基准：`experiments/ias_root_probe`，ownership v9

## 结论

同一 launch 内的因果 prime/probe 显示，direct-GAS forced-miss 路径存在稳定的
**双 SM 可见域**：

```text
同一 SM               P trace A 可使 Q probe A 快约 1.0--1.2k cycles
特定配对 SM           可稳定传递约 0.46--0.50k cycles 的 warm 状态
已测跨配对边界         传递量约 0
```

实测到的配对包括 `{0,1}`、`{2,3}`、`{22,23}`、`{44,45}`；正反方向都复现。
`0->22`、`1->22`、`22->1`、`23->44` 等跨组对照没有 warm transfer。

在 P、Q 各自用不重叠的 256 KiB、`L1::evict_last` global-load 区域冲刷普通 L1
以后，普通 GAS backing-load 的 A/C 对照大多回到约 0，而 trace-generated 状态在
多个配对中仍保留约 `0.42--0.47k cycles`。因此该双 SM 信号不能只用“P 暖了普通
backing line”解释，强烈支持 RT traversal/root 路径自身存在配对可见状态。

严谨命名是：

> **two-SM RT traversal residency domain（TPC candidate）**

它与本机 performance-monitor 拓扑中“一 TPC 覆盖两个 SM”相容，但实验没有公开
TPC ID，也没有版图或 tag-RAM 可见性，所以本文不把 `smid/2` 当作先验映射，更
不声称已经证明“每 TPC 一块物理 SRAM”。

后续 v11 联合工作集扫描又得到一个精确边界：P 在 paired SM 上 prime A，P/Q
分别冲刷普通 L1 后，Q 最多再加入 15 个 unique roots 而保留 A；加入第16个时
远端 warm benefit 从约 `-0.48k` 同时降到 0。三个 paired 域、forward/reverse
control order 都复现。因此远端 A 会参与 Q 所见的同一个 **16-entry effective
replacement budget**；这比仅看到 warm transfer 更强，但仍不能区分共享 SRAM
与“迁移/复制到 Q 的16-entry local array”。

## 为什么原来的相邻 launch 方法不够

预注册设计先尝试两个相邻 width-1 launch：P prime A，Q probe A，并按实际
`%smid` 后分层。64 trials 全部得到 `(SM0,SM0)`，但 Q 的 probe-only 中位数约
6734.5 cycles，而同一 Q 内部的 same-scrub/unique-scrub 控制约 4006/5141 cycles。
launch 边界显然改变或隔离了所需状态，因此这个方法不具 ownership 判别力。

两个非阻塞 stream、两个 OptiX pipeline 的有界并发版本也没有真正并发：握手安全
退出为 `arrived=3, phase=0, timeout_mask=1`，P 超时后 Q 才被调度。没有无限自旋、
GPU reset 或设备挂死。

最终使用一个 width=8192 的 OptiX launch，其中只有两个指定 launch index 工作：

```text
P: 记录 smid -> prime -> 发布 phase 1 -> 等待 Q
Q: 记录 smid -> 等待 phase 1 -> 控制性 scrub -> 计时 probe -> 发布 phase 2
```

`prime_index` 和 `probe_index` 可独立指定；每条记录同时保存 P/Q 的 begin、timed、
end SMID，任何线程迁移、payload 非零、握手超时或记录错位都会使进程失败。

## 因果控制

工作集为 64 个物理独立 one-triangle GAS，target 为 trial 0--63。所有非
`probe_only` 的 Q 路径在计时前都执行恰好 16 次准备 trace。

| 控制 | P | Q 在计时 A 前 | 用途 |
|---|---|---|---|
| `other_scrub` | trace A | trace B ×16 | 待测远端 warm |
| `unrelated_prime_other` | trace C | trace B ×16 | 完全等长的 cold 因果对照 |
| `local_prime_other` | trace A | trace A ×1 + B ×15 | Q-local warm 参考 |
| `backing_load_other` | global-load A 的 GAS `+0/+0x380` | trace B ×16 | 普通 backing locality 对照 |
| `dual_l1_trash_other` | trace A，再冲 P-L1 | 冲 Q-L1，再 trace B ×16 | 去除两端普通 L1 后的 RT 状态 |
| `backing_load_dual_l1_trash_other` | load A，再冲 P-L1 | 冲 Q-L1，再 trace B ×16 | 验证 trash 是否仍留下普通 backing warm |

`C=(A+17) mod 64`，不与 B 或前 16 个 unique scrub target 重合。P/Q trash 分别使用
不重叠的 256 KiB 区域，load 带公开 PTX `L1::evict_last` 保留优先级。负的配对差

```text
delta = cycles(P primes A) - cycles(P primes C)
```

表示 P 的 A 状态使 Q 更快。控制既按 forward 顺序运行，也把 18 个 control 完全
反序运行；记录槽仍由 control ID 固定，所以可逐 trial 配对。

## 结果矩阵

下表均为 64 个 target 的逐 trial 差值中位数，单位 cycles：

| P -> Q | 分类 | 顺序/重复 | raw RT prime | RT prime + 双端 L1 trash | backing load + 双端 L1 trash |
|---|---|---|---:|---:|---:|
| 0 -> 0 | same SM | forward | -1000.5 | -420.0 | +207.5 |
| 0 -> 0 | same SM | reverse | -1095.0 | -443.0 | -4.5 |
| 0 -> 1 | paired | forward | -473.5 | -415.0 | +6.0 |
| 0 -> 1 | paired | reverse | -475.5 | -451.0 | -2.0 |
| 2 -> 3 | paired | forward | -497.0 | -450.0 | -1.5 |
| 22 -> 23 | paired | forward | -464.0 | -457.5 | -1.5 |
| 22 -> 23 | paired | reverse | -467.5 | -428.0 | -176.0 |
| 44 -> 45 | paired | forward run 1 | -459.5 | -96.5 | +8.5 |
| 44 -> 45 | paired | forward run 2 | -455.0 | -443.0 | -8.0 |
| 44 -> 45 | paired | reverse | -462.0 | -446.5 | +3.5 |
| 45 -> 44 | paired | forward | -456.5 | -468.0 | -5.5 |
| 0 -> 22 | cross-domain | forward | -1.0 | +179.5 | +1.0 |
| 0 -> 22 | cross-domain | reverse | 0.0 | -2.5 | +3.0 |
| 23 -> 44 | cross-domain | forward | +1.5 | +10.5 | +0.5 |

机器可读汇总：[`rt_ownership_summary.tsv`](rt_ownership_summary.tsv)。完整 raw CSV
位于 [`experiments/ias_root_probe/results`](experiments/ias_root_probe/results)。

### 稳定部分

1. raw RT prime 的拓扑最干净：同 SM 大收益、四组 paired SM 均约 `-0.46--0.50k`、
   跨组约 0；正反方向和 forward/reverse 控制顺序都复现。
2. 普通 backing load 本身在未双端冲刷时也会产生局部收益，所以 raw 差值不能全部
   归给 RT L0。
3. 双端 L1 trash 后，普通 backing 对照在多数运行回到 `-22.5..+8.5` cycles，
   而 RT prime 在同 SM 和多数 paired 运行仍约 `-0.42..-0.47k`。
4. `44->45` 第一次 dual-trash 只有 `-96.5`，但独立 run 2、反控制顺序和反方向
   分别为 `-443/-446.5/-468`；这是报告保留的异常值，不做删除。

### 仍然不能过度解释的部分

- `L1::evict_last` 是 eviction-priority hint，不是形式化 flush。少数 backing control
  仍有残差（如 `22->23 reverse=-176`、`0->0 forward=+207.5`），所以证据等级是
  强推断，不是物理 tag 直接观测。
- ownership probe 计时的是一次完整 cold-ish `optixTrace`。数百 cycles 的 transfer
  大于稳态 K16->17 的约 27-cycle refill，因此它可能合并 root/complet residency、
  address translation、RT front-end return state 等，不应说成只测到某一个 tag bit。
- warm transfer 可由共享存储、伙伴转发、coherent replication 或 victim 结构造成；
  本实验只证明**可观察状态的共享域**，不证明只有一份物理 cache。
- 因此不能把“16-entry、2 KiB effective backing footprint”直接升级成“每 TPC
  2 KiB SRAM”。v11 已证明远端 A 与 Q-local unique roots 共享一个16项**有效**
  budget，但共享物理 tag/data RAM、迁移、复制和伙伴转发仍可能给出同一曲线。

## Paired-SM 联合容量：第16个 Q evictor 精确清除远端 A

v11 把 Q 的 unique scrub 数量 `S` 参数化，并只运行两个等长 control：

```text
test:    P trace A -> P L1 trash -> Q L1 trash -> Q trace U1..US -> probe A
control: P trace C -> P L1 trash -> Q L1 trash -> Q trace U1..US -> probe A
```

`C=A-1 mod 64`，而 `Ui=A+i mod 64`，所以 C 不进入最多62项的 evictor 序列。
下表是64 targets的逐 target 差值中位数：

| P -> Q | order | S=1 | S=8 | S=14 | S=15 | S=16 | S=17 | S=18 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 0 -> 1 | forward | -482.0 | -484.5 | -485.5 | -484.5 | -0.5 | 0.0 | 0.0 |
| 0 -> 1 | reverse | -480.5 | -486.0 | -484.5 | -485.5 | +0.5 | 0.0 | -1.0 |
| 22 -> 23 | forward | -474.5 | -476.0 | -480.0 | -478.0 | 0.0 | 0.0 | +0.5 |
| 22 -> 23 | reverse | -480.5 | -477.5 | -478.0 | -480.5 | -1.0 | -1.0 | +0.5 |
| 44 -> 45 | forward | — | — | -464.0 | -469.5 | +1.0 | 0.0 | — |
| 44 -> 45 | reverse | — | — | -465.5 | -469.5 | +0.5 | 0.0 | — |
| 0 -> 22 cross | forward | 0.0 | +1.0 | 0.0 | 0.0 | 0.0 | +1.0 | +3.5 |
| 0 -> 22 cross | reverse | -1.0 | -1.0 | -1.0 | -5.5 | 0.0 | -1.0 | +1.0 |

计数方式中，A 加 S 个 evictors 的总工作集为 `S+1`。所以 S=15 保留、S=16
消失，恰好等价于总有效容量16。same-SM完整 trace 在S>=16仍有一部分不跨SM的
address/translation/backing残差；paired 曲线反而精确归零，说明跨SM传递的成分
就是这个16-entry root-residency candidate，而不是所有 per-SM 局部状态。

32-target探索扫描曾在 paired S=8 出现假转折；64-target、target前后两半、正反
control order 均否定该解释。这一异常被保留在 raw CSV，最终结论只采用64-target
重复结果。

关键点机器汇总：[`rt_paired_capacity_summary.tsv`](rt_paired_capacity_summary.tsv)。

## 对优化的含义

当前最可操作的结论仍是提高 ray/AS coherence：让相邻时间内的 traversal 重用相同
GAS/root。paired-domain 结果说明局部性并非严格限于单 SM，但 CUDA/OptiX 没有给
应用一个稳定、可移植的“把 ray 放到某 TPC”接口，所以不能把观测到的 SMID 配对
硬编码进产品调度。

普通 global pre-load 不能替代 RT trace prime；在双端 L1 压力后，两者表现明显
分离。L2 persisting pre-touch 仍是另一条、作用于下游 backing residency 的独立
软件控制面。

## 安全与复现边界

- 每次 ownership launch 最多两个 active raygen threads；其他 index 立即返回。
- 每个设备端 spin 有 100,000,000 `clock64` 周期 deadline。
- 每个 host launch 有 2 s 默认 watchdog，超时直接退出，不 reset GPU。
- trials 硬上限 64，width 硬上限 65536，trace/launch 硬上限 2,000,000。
- 没有改驱动、固件、功耗、ECC、持久化模式或时钟。

# RTX 5090 RT 硬件研究矩阵

本文件把“已观察到的现象”与“仍需证明的硬件含义”分开，避免用一个容量台阶
替代整套 RT Core 运行模型。

## 已有硬证据

| 事实 | 当前证据 | 状态 |
|---|---|---|
| RTX 5090 有 170 SM、170 RT Core、96 MiB L2 | NVIDIA 白皮书 + CUDA API | 已证实 |
| 每 SM 是 128 KiB 统一 L1/shared 物理池 | 白皮书 + 本机 GB20x metric 配置 | 已证实 |
| 不同 GAS 的 traversal 公共路径存在 16-entry 驻留阈值 | cyclic + prime/evict/probe | 已证实有效阈值 |
| 阈值溢出后每 trace 多 4 个 32B L1TEX hit sectors | one-pass NCU 精确整数关系 | 已证实 |
| same-handle、ring-only 没有 16->17 变化 | 对照实验 | 已证实 |
| 物理地址加空洞后结果逐整数不变 | padded allocation 对照 | 已证实 |
| 新增 4 sectors 不增加 `l1tex__t_requests` | K16/K17 unique/same；request 值逐项相同 | 新证据，需解释注入点 |
| 每次溢出对应一次 SRAM1 read-active cycle | one-pass SRAM counter 精确整数关系 | 已证实 backing 读取粒度 |
| hit-specific primitive-path layer 可驻留31条unique record | hit-minus-miss sector差分，K29--64 | 已证实有效阈值 |
| hit/deeper层表现为30 stable + 1 allocation slot | 31+1逐victim、4种fill order、post-fill hit | 已证实串行分配行为 |
| 同一GAS内64个target/128个triangle/64个build input不各占31-record槽 | 单callsite AB/BA paired、32 victims×3 paths、完整L1放大map | 已证实null；排除per-primitive/path/geometry/SBT-index allocation |
| 同一build的64个GAS relocation clone会各占root/hit record | one-triangle clone、四fill-order、hit-minus-outside、L1放大 | 已证实；31-record tag随output/handle身份变化 |
| 64个static-transform handle共享child GAS时不各占root/hit record | paired全victim、L1 trash、K1--64 unique/same | 已证实null；排除generic traversable-handle tag模型 |
| 独立IAS共享child时gap+27、leaf+54 | double-triangle gap/leaf paired、四fill-order | 已证实两个同步31-class hit阶段 |
| 16-entry root层采用hit-updated circular-successor语义 | 16个单refresh + 24个任意/重复顺序插入控制 | 已证实串行行为；真LRU否定 |
| 所测64-GAS root池未见E<16 set conflict | 192个地址序列 + 64个15项reduction | 支持16-entry effective fully-associative |
| root L0 miss 令RT-associated long-scoreboard多约25.9/trace | generic−non-RT counter，同pass unique/same | 已证实相关等待代价 |
| RT-associated MIO throttle 为28/trace且不随cache miss变 | unique/same/ring控制 | 已证实提交端公共信号 |
| direct-GAS trace状态在特定双-SM域可见、跨已测域不共享 | same-launch `%smid`、A/C prime、正反方向与双端 L1-trash | 强支持 TPC candidate |

`l1tex__t_requests.sum` 的新结果：

```text
                 K16       K17
unique miss      599051    636491
same-handle      599051    636491
```

因此 RT 驻留层 miss 所增加的 4 sectors 并不是普通 LSU/TEX request 计数的一部分。
最可能的解释是 RTCORE/cache-fill traffic 在 T-request 计数点之后进入 L1TEX data/tag
路径；需结合本地 GB20x 配置、SRAM bank counters 和文档进一步验证。

SRAM data-stage 的 one-pass 结果进一步满足：

```text
K=16: SRAM1_read(unique) - SRAM1_read(same) = 599068 - 599053 = 15
K=17: SRAM1_read(unique) - SRAM1_read(same) = 654988 - 636493 = 18495 = N17 - 1
K=17: SRAM0_read(unique) = 0
```

结合 sector 结果，overflow 后每次访问恰好增加一次 SRAM1 read-active cycle和四个
32B sectors，而不增加普通 T-stage request。它强支持“一次 RT backing refill 从
tagged SRAM1 读出一条 128B line”，比仅凭 aggregate sector 数更接近地址线粒度。

## 尚待回答的硬件问题

| 问题 | 能证明它的实验/资料 | 当前状态 |
|---|---|---|
| 16项缓存的是 GAS handle、root descriptor 还是任意 BVH complet？ | 同一 GAS 内更深、可控形状的空间分离子树；独立 IAS/GAS 对照 | 部分完成：小GAS多路径无容量行为 |
| IAS两个31-class阶段如何组织？ | IAS shared-child gap/leaf + IU sector方程；未来地址/ownership分离 | 两阶段已证；双bank vs bundle vs parent-qualified child未决 |
| instance transform/IAS record 是否走同一 L0？ | IAS/GAS 9/17 方程与 `+0x600/+0x700` 地址干预 | 部分完成：两个16域+两个32域事件 |
| replacement 是全相联、LRU/FIFO、round-robin 还是 set mapping？ | 任意refresh + insert/no-insert + eviction-set reduction | 串行successor已证、真LRU否定；所测池等效全相联，物理电路未决 |
| 128B 是一条连续 line，还是四个分散 sector？ | 4 sectors + 1 SRAM1 read cycle + 专利单线语义 | 强支持，仍无地址trace |
| RT L0 与普通 L1 是否保持独立副本？ | P/Q 双端 `L1::evict_last` + 普通 backing-load 对照 | 强支持独立可见状态；hint非形式化flush |
| cache ownership 是每 RT Core、每 SM、每 TPC 还是更高层？ | same-launch SMID干扰与联合容量缩放 | 双-SM域+16项有效budget已证；物理共享/复制未决 |
| traversal stack 存在哪里、何时 spill？ | 深 BVH/嵌套 IAS + local/L1 traffic 台阶 | 未完成 |
| Blackwell cluster/LSS/OMM 单元是否有独立数据缓存？ | 官方资料 + 专用 API 场景 | 未完成 |

## 实验优先级

1. **IAS两31-class阶段的ownership/地址分离**：shared-child已分出gap+27与leaf再+27；
   下一步区分双bank、multi-line bundle和parent-qualified child record。
2. **更深、可控形状的同一GAS多子树**：继续区分16-entry root/handle cache与通用
   interior-complet cache。
3. **IAS/GAS 交叉矩阵扩展**：定位instance/root descriptor是否共享16-entry层。
4. **扩大地址/record类型覆盖**：root池192个序列与64个reduction已无E<16冲突；
   下一步把等效全相联结论扩展到IAS、compaction/build flags和更大VA跨度。
5. **L1 set-conflict**：把 `L1::evict_last` hint 升级为地址匹配的确定性冲突控制。
6. **primitive 与 stack 专项**：需要可控 BVH 形状或更强 counter 证据。

## 结论用词门槛

- “16-entry RT traversal residency layer”：当前已满足。
- “root/complet-path L0 candidate”：当前资料与实验共同支持。
- “通用 BVH complet cache”：必须先在同一 GAS 内复现容量行为。
- “primitive cache”：same-GAS多target已经反证每primitive独立分配，当前不应使用；
  除非多build-input/geometry实验和地址证据另行定位出primitive级结构。
- “每 TPC 2 KiB 物理 SRAM”：联合实验已证明特定双-SM域共享同一16项有效预算，
  但共享array、复制/迁移、连续line内部格式仍未区分；当前只能写“特定双-SM
  可见域（TPC candidate）”。

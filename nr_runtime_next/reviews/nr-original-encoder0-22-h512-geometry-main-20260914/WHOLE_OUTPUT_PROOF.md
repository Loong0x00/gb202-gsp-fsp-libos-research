# 整幅输出结论的边界与推导

`RESULT.json` 的“整幅输出”不是把透明 buffer 回填后命名为 original，也不是重跑
10,006 个 CTA。推导分为两个彼此独立的部分：

1. **局部原始程序证据。** 对 blocks 0–22 的每个实际 program/weight slab，`SAMPLE_COMPARE.json`
   都用未改 `literal.run`、其 pinned `original.ptx` 和 CPU VM 执行四角、四边中点及 4–5
   个内点。每个 literal 写出的稀疏 offset/value patch 与冻结透明全局 buffer 相同 offset
   逐字节比较；没有 transparent→transparent comparison 被称为 original。DS4/8/14/22 的
   high/low 分别比较。

2. **完整 writer partition。** `STATIC_PARTITION.json` 对每一个全局 port 的全部 CTA
   坐标枚举 original writer 的仿射 cell 公式：普通/high port 是 4×4 physical-C tile，
   pre-primary/DS-low 是 planar16 `(group,y,x)` cell。每个 cell 映射到唯一完整字节区间；
   枚举同时检查所有 cell 被写、没有 cross-CTA owner 重复、cell 字节数等于完整 port
   字节数。每个已执行 literal patch 的实际 writer set 必须恰等于该公式的 cell set；内点
   还要求相同的原始 literal store PC/warp/lane/size shape，记录了平移同构。

因此，在既有“固定 8×8 local program 对原始 literal 等价”的基础上，扩展 geometry 只改变
CTA→全局地址的仿射映射和已记录的边界 predicate；局部等价加无重叠完备 partition 给出
blocks 0–22 的全局 port 等价，再按 block handoff 归纳到 block22 low。此目录的新增运行
直接证实的是 297 个 local literal witnesses（2,249,216 bytes）；未执行的 9,709 个 CTA
不是伪造的 original execution，而是上述 local-program/partition 推导的对象。

这个结论不扩大到 GPU、native tensor-core、game、网络、部署或 temporal/history。

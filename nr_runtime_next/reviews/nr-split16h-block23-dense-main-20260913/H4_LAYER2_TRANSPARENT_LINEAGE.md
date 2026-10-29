# block23 H4 layer-2：原始 attention lineage 与透明公式

## 结论

`ORIGINAL_LAYER2_H4.bin` 不是 H8 的 64-token attention 截断，也不是把 48 个
零 `Q/K/V` 直接喂给带完整 relative-position bias 的 H8 公式。原始 PTX 保留
`Nphysical=64` 的 reduction tile，但只有 `Nlogical=16` 个 H4 token 有 QKV
fragment。padding key 的 score 是 **0**（不加 bias）；64-key tree 完成后再用
half RN 减去这 48 个 `map(0)` 项。padding V 为零。

实现已加入 `candidate_v3.py`。独立原始 PTX/VM 四个 `cta.z` slice 与该实现、
以及 `ORIGINAL_LAYER2_H4.bin` 三方逐字节相同：8192/8192 bytes，SHA-256
`245bc1c5d0c6d64793e73468916c8fb7acebe66725d229973ae8dd5e84449f0f`。旧的
失败记录 `H4_LAYER2_V3_DIAGNOSTIC.json` 保留未改。

## 原始物理地址与 fragment lineage

原始 entry 是 `cc_split_swin_16h_qkv_512_fp8`，固定 PTX SHA
`fb1585fc32da5d6b48fc82015f52fa50392d1bd4c682d65dfd1ff7c3eebb18f7`。ABI56
中 input/output/slab/H/W/x/y 分别在 byte `0/8/16/24/28/32/36`；本 replay 的
pointer bases 分别为 `0x100000/0x400000/0x200000`，且 `(H,W,x,y)=(4,4,0,0)`。

令 `t=4*y+x`、`m=4*y+x`、`k=c mod 32`。H4 input 的每个逻辑 E4M3 code
`X[t,c]` 来自 input physical byte offset：

```
p = 1024*floor(c/64) + 512*floor((c mod 64)/32)
  + 16*(4*(m mod 8) + floor((k mod 16)/4))
  + 8*floor(k/16) + 4*floor(m/8) + (k mod 4)
address = 0x100000 + p
```

这正是 `packed_a_offset(4,4,y,x,c)`。原始 async bulk PC 180/243 各读取
`[0,512,0,512]` 的四个 512-byte source blocks；PC 418/499 各读取从
`1024..7680` 的 14 个 blocks（每 block 在该 PC 两次）。因此每个 H4 input
512-byte physical block 合计被读四次，并经 8 次 mbarrier publish 写入 8192-byte
shared staging；这是物理复制，不是额外的逻辑 token。

直接解码原始 `mma.sync.m16n8k32` 的 A fragments 给出了语义边界：

* VM PC 566--661 的 2688 个 A fragments 精确等于 `X[0:16, c:c+32]`，覆盖
  `c=0..447`；
* VM PC 817--912 的 384 个 A fragments 精确覆盖 `c=448,480`；
* 16 个 32-channel segment 各出现 192 次，共 3072 个 fragments，零个不匹配。

故 QKV projection 的 source lineage 是完整 `X[0:16,0:512]`，而非把 H4
storage 误解为 64 个有效 token。token 16--63 没有输入 A fragment。

后续 lineage 是：`X -> QKV(K32) -> Q/K norm -> E4M3 Q/K/V -> QK score ->
map/reduction/subtraction -> E4M3 probability -> PV(K32) -> E4M3 C -> pack_c`。

## H4 透明 attention 公式

对 head `a`、有效 query/key `q,k in [0,15]`，沿用已经由 H8 证明的 K32 与
fragment permutation `pi32`：

```
s[a,q,k] = RN16(dot(Q[a,q,pi32], K[a,k,pi32]) + bias[a,q,k])
s[a,q,k] = 0                    for padded k=16..63
u            = map(s)           # 原始 affine/clamp/bit-map
D64[a,q]    = tree_RN16_sum(u[a,q,0:64])
D[a,q]      = RN16(D64[a,q] - RN16(48 * map(0)))
P[a,q,k]    = FP8_RN(RN16(u[a,q,k] * reciprocal(max(D[a,q], eps))))
V[a,16:64]  = 0
C[a,q]      = K32_PV(P[a,q,:], V[a,:,:])
```

这里是“先 64 路 reduction、后 padding-subtraction”，不能代数化成普通的
16-key softmax；half RN、原始 reciprocal LUT、以及 FP8 publish 顺序都保留。
实现中的 `_softmax_h4_padding_subtraction` 恰好执行该顺序。

block31 的已证明模式提供了正确的启发：其 lineage 是 physical `N=32` /
logical `N=16`，padding 行可先算/存、但最后由 zero-publish 覆盖；因此必须把
物理 tile 与逻辑 token 分开，并减去 padding 对归一化的贡献。本例细节不同：
block23 H4 的 padding V 是零，不是 alias/repeat 的有效 V。因此不能复制
block31 的 value alias，只借用 padding-subtraction 原则。

## 为什么旧 `candidate_v3` 全部 8192 bytes 错误

旧 H4 分支把有效 16 token 放入 64-row array，tail Q/K/V 虽是零，却调用了 H8
的完整 bias score：tail score 实际变成 `bias[a,q,16:64]`。它还保留了这些
padding keys 的 mapped denominator 项。原始 PTX 的 tail 应为无 bias 的 score
0，且分母应减 `RN16(48*map(0))`。概率的 FP8 publish 随之改变，PV 的所有
有效 channel 都被缩放/舍入到不同 code，故没有任何一个物理 output byte 幸存：
旧 SHA `fbeec7557c1ff4de3f3d69e5edb758a738a9f223ad9ea822b47dc3492daf8014`，
`different=8192, first=0`。

## 输出 map / store lineage

原始 VM 的所有 H4 output store 都来自 PC 2376，每 CTA 128 个 16-byte store。
对 `z=0..3`、warp `wy=0..3`、lane `l=0..31`：

```
store address = 0x400000 + 2048*z + 512*wy + 16*l
```

四个 CTA slice 因而覆盖 `[0,2047]`、`[2048,4095]`、`[4096,6143]`、
`[6144,8191]`，无 gap/overlap。每一个最终物理 byte 同时满足

```
out[packed_c_offset(4,4,y,x,c)] = FP8_C[4*y+x,c]
```

即 `pack_c` 是这组 source stores 的输出 map，而不是一个仅 H8 成立的 layout
假设。

## 可复核证据

运行 `PYTHONDONTWRITEBYTECODE=1 python3 -B verify_h4_layer2_transparent.py`
会重放四个独立 original-PTX VM slice、解码 A fragments、检查 PC 2376 store
覆盖，并与 candidate/original 三方比较。机器可读结果保存在
`CORRECTED_H4_LAYER2_TRANSPARENT.json`。这是 CPU VM 原始程序 equality；没有
GPU、游戏或部署结论。

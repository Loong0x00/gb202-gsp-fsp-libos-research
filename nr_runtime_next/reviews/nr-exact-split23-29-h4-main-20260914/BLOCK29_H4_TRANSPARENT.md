# Block-29 H4 `origin=(-4,0)` transparent L2

`candidate_origin_neg40.py` 是按几何选择的纯 NumPy 分支；不导入指令回放、没有输入摘要门，也不读取任何固定输入或输出。

## 推导的物理拓扑

- `query_position`：右上 4x4 score tile，
  `[4,5,6,7,12,13,14,15,20,21,22,23,28,29,30,31]`。
- K 与 V alias：对每个物理 key `p` 均为
  `4*((p//8)%4) + p%4`。
- bias 使用物理 score columns，而不是 alias 后的 token columns。
- QK 的八个 8-column fragment 按
  `[[0,1,2,3,8,9,10,11], [16,17,18,19,24,25,26,27],
  [4,5,6,7,12,13,14,15], [20,21,22,23,28,29,30,31],
  [32,33,34,35,40,41,42,43], [48,49,50,51,56,57,58,59],
  [36,37,38,39,44,45,46,47], [52,53,54,55,60,61,62,63]]`
  放入 canonical 64-column score plane。
- 64 列都是真实 alias，使用普通 `_softmax` 64-key denominator；**不**做 H4 zero-padding / invalid-key subtraction。

该分支已接入 `split_standard_candidate_h4.py`。Block-25 的旧输入相等结果没有作为推导或验证证据。

## 验证

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B verify_block29_h4_transparent.py
```

验证器在加载诊断 VM 前先计算透明候选，静态拒绝 replay/hash/固定输入钩子，然后分别比较：

- 真实链 `ORIGINAL_BLOCK29_LAYER1.bin`：8192/8192 相等，L2 SHA-256 为
  `3446cc60f22f1d9dd981edda91a7d33a73f5e06f466f3de0757b13ccc35475b7`；
- 独立有限 E4M3 heldout `HELDOUT_BLOCK29_LAYER1.bin`：8192/8192 相等。

完整结果保存在 `BLOCK29_H4_TRANSPARENT_RESULT.json`。

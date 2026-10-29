# 实际权重重建修复与原生核验证

当前可运行的静态图片入口是 `DLSS5StaticImage`，导出文件为
`models/dlss5_real_static_256.onnx`。它使用完整的 71-block 实际权重图，
不是小型拟合网络。四张真实图片的 CPU PyTorch / ONNX Runtime 输出逐元素一致。
接口、结果及限制见 [ONNX 验证报告](DLSS5_ONNX_VALIDATION.md)。

## 确认并修复的错误

| 部位 | 修复 |
| --- | --- |
| 所有残差 | `skip * cos_skip + branch`，原实现把系数乘在学习分支上 |
| FP8 矩阵 | 按 QMMA B fragment 解码，并吸收寄存器重排形成的 K 列排列；不再直接 row-major reshape |
| 普通 Swin FFN | C→4C、每 head 的 128→32 contraction、C→C mix；原来的矩阵尺寸分割错误 |
| 普通 Swin / pre QKV | 修正提前 16 字节的读取起点；QKV 输出由 head-major 重排到 Q/K/V-major |
| 32→64 降采样 | 权重从 `0x50b0` 开始；记录末尾有 16 字节对齐，不能使用 `record_size - matrix_size` |
| Split FFN | dense→分组 expand→cubic activation→分组 contract→projection，移除错误的并行门控结构 |
| Swin / Split 位置偏置 | 解码 64×64 accumulator 存储排列；通过原生脉冲实验恢复 |
| Swin 注意力 | Q/K 归一化及 FP8 位置、half 指数近似、概率量化；shifted window 使用零边界，替代循环移位加 mask |
| pre | 恢复 3 个 PCG Gaussian 通道、常量、当前/历史 RGB、3 个标量及 2 个辅助通道；pre window 不移位 |
| 融合残差 | pre/post/up 中间残差保留 half 值，只量化 GEMM 的副本；池化使用未提前量化的残差 |
| upsample | 实际 transition matrix 在 FFN 矩阵之后；加载 skip scale；恢复最近邻复制 |
| ViT QKV | 128-byte header 是 32 个 FP32 Q gain；只给 Q 乘 sqrt(32) 和 gain，K 只归一化 |
| ViT attention | 全局有效 token 注意力；先量化未归一化指数做 value product，再除以指数和；移除错误的 row-max 路径 |
| ViT layer3 | 2-byte 记录没有被 attention kernel 读取，不再误当作学习到的 score scale |
| post | 解码完整两个 K=16 HMMA 输出分片；保留未量化残差；恢复最近邻输入和 RGB 残差加回 |

`DLSS5Graph` 保留显式前端输入的研究接口。直接静态 RGB 推理使用
`DLSS5StaticImage(graph)`，避免旧的零 adapter 静默返回缩暗的原图。

## RTX 5090 原生验证

将仓库 sm_120 cubin 通过 CUDA Driver API 直接加载到 RTX 5090；没有重新实现一个
“原生替代网络”作为比较对象。探针修改少量权重或构造输入，以隔离具体算子。
这些是局部原生核验证，不等于完整 NVIDIA DLL 的逐位复现。

| 实验 | 结果 / 证据 |
| --- | --- |
| C32 FFN，常量及非均匀通道输入 | 32 个输出通道全部精确匹配 |
| C64 FFN，常量输入 | 64 个输出通道全部精确匹配 |
| C32 down projection，逐通道脉冲 | 修正偏移后，完整 64×32 矩阵与原生输出精确匹配 |
| Swin bias，4096 个位置脉冲 | 恢复一一对应的位置排列 |
| Swin 仅位置偏置的注意力 | 指数近似后 4094/4096 个数值精确匹配；其余最大差 0.0078125 |
| Split 仅位置偏置的注意力 | 4096/4096 个数值精确匹配 |
| C32 upsample 坐标输入，经 C64 outview | 输出为完整 2× 最近邻复制 |
| post 坐标输入，经 C32 outview | 最近邻复制最大误差 0 |
| post 主支路 / skip 分离 | 原生输出分别等于对应 half 系数，证明中间残差不应提前 FP8 化 |
| ViT 二组 K/V，Q gain=.125/.25/1 | 原生输出 .8125/.875/1，与恢复的指数及归一化顺序精确匹配 |
| 完整编码链至 block22 | 原生 pre、inpview、Swin、downsample 均成功执行；各阶段保持相近数值范围，没有旧的系统性饱和 |

真实 landscape 的 pre 逐元素 MAE 从约 0.0096 降到 0.00068。原生 / PyTorch
首个 pool 的平均绝对值分别为 0.272923 / 0.272930。后续仍有 half 累加和量化
导致的差异，不能仅凭数值范围相近宣称逐位匹配。

关键探针位于 `tools/probe_dlss5_cuda_*.py`；例如：

```bash
PYTHONPATH=src:tools python tools/probe_dlss5_cuda_encoder.py
PYTHONPATH=src:tools python tools/probe_dlss5_cuda_down.py
PYTHONPATH=src:tools python tools/probe_dlss5_cuda_split_attention.py
PYTHONPATH=src:tools python tools/probe_dlss5_cuda_up_spatial.py
PYTHONPATH=src:tools python tools/probe_dlss5_cuda_post_spatial.py
PYTHONPATH=src:tools python tools/probe_dlss5_cuda_vit_attention_scores.py
```

这些研究探针需要 sm_120 GPU、CUDA Driver、CUDA PyTorch、仓库 cubin，以及
默认位于 `../DLSS5-extracted` 的实际权重。ONNX 推理不需要这些条件。

## 可移植数值计算

FP32 GEMM 后的微小后端差异可能落在 half/FP8 的舍入中点，随后被网络放大。
静态导出默认启用 `enable_portable_reductions()`：矩阵乘法和归一化的求和使用
FP64，中间张量仍回到 FP32，并保留明确的 FP16/FP8 边界。这是较慢的参考运算，
不是声称 NVIDIA 内核使用 FP64。

精简后的可移植 FP8 量化器已对全部 65,536 个 half bit pattern，与 PyTorch 的
E4M3 转换逐值比较通过。回归测试还覆盖偏移、通道排列、分组 FFN、shift 零边界、
ViT padding、原生注意力测试值及最近邻复制。

```bash
PYTHONPATH=src python -m unittest discover -s tests -v
```

## 仍有的边界

静态模式明确选用 frame=0、color scale=.125、当前颜色作为历史 fallback、
标量/辅助特征为零和 reference-color RGB 后处理分支。没有恢复完整时序资源 ABI，
也没有把 Windows host 的全部动态参数默认值视为已知。捕获的 Windows host 还会
给 256×256 输入分配 320×320 内部画布；当前导出使用固定 256×256 静态图。

图片保留了结构和颜色，但部分平坦/暗色区域可见噪点。数值一致性通过，不代表
已证明增强效果优于输入，也不代表原生 DLL 的画质一致性或实时性能。

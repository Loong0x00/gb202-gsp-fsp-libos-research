# O / C codec 同输入 CPU 反事实 — 2026-09-11

## 结论

**宿主算法可以在不换模型、不做新推理时明显改变局部结果；但本旧 POST 场景不是“换社区 compositor 就全图变成另一种真实感”。**

- **实际 t=.6，P1 几乎相同**：两帧 O/C RGB MAE 约 2×10⁻⁷，C guard 完全不触发。不能拿源码里的 near-grey/黑帧保护故事直接解释这张图的巨大差距。
- **P5 局部差异明显，主要来自双侧亮度 ratio guard**：实际 .6 的 MAE **.004119 / .005764**；像素 guard 触发 **8.931% / 11.147%**。此处上界触发远多于下界，C 全图均值 Y 比 O **低约 1.68% / 2.27%**，并非普遍“提亮救黑”。
- **明确反事实 t=1（没有修改设置）**：P5 MAE **.017447 / .025225**，guard 触发 **29.387% / 36.319%**；C 同时抑制过亮编辑和保住部分过暗编辑。此时才显著减少输出 Y<.01 的比例。
- **同一 A 的编码差异稀疏但可很大**：O/C 编码 RGB MAE **.000379**、单分量最大 **.758843**，但 **99.5918% 分量完全相同，p99 差为0**。HDR 饱和像素的模型输入色比确实可大变，不能仅用全图平均否认它；本次没有新 NR 输出，不能量化这种输入变化对最终网络结果的影响。

这隔离出可验证的**宿主局部原因**，不是作者/抖音画质归因，也不是 C 全社区管线或视觉质量认证。

## 1. 范围、输入与身份

只读输入：`reviews/cinematic-image-main/runs/20260910-182346-wuwa-still-L5-capture/d5r-layer-capture-*`，两包分别为 `...-f2-a1`、`...-f3-a2`。每张 **768×432、little-endian RGBA16F**；冻结 **A=S、B、N=P1/P3/P5**，D 为旧 P5 最终 compositor 保存结果。所有输入的完整 SHA256/字节数见 [INPUT_PINS.json](INPUT_PINS.json)。S/B 在两包相同；N 不同，不能当两张独立场景。

这是**旧 POST、由既存 WuWa RR still 下采样所得的 offscreen 静帧、synthetic guides**，不是 latest PRE3、ZZZ、Douyin、author version，也不是游戏 Present。原图派生与 synthetic-zero motion/constant .375 depth 由既存 SOURCE.json 记录；本任务没有重建或替换 S/B。SOURCE.json 的 guides=[768,432] 是较早的描述；该次 COMMAND.json 明确 `--guide-width 512 --guide-height 288`，capture metadata 也为 render=512×288；本次数学只消费已保存的颜色，不“修复”guides。

实际 metadata 解码：POST order=0、5层、Cinematic style=2、paper white=1、color=1、transfer float32 位型 `3f19999a` = **0.6000000238418579**。帧2各层 reset=1，帧3 reset=0；这不是受控 temporal 质量评测。t=1 仅另一组 CPU 参数，**未写用户/安装设置**。

- O：completed chain-diff REPORT 所定 frozen9e graphics source；与旧 audit 的 frozen manifest/hash 重新链接核对，包含实际嵌入 shader 字节文件。不是 CPU 模型 reference。
- C：wilsjo2 **e237f895623742b761f9e5f00067cb3dc62619f4** 固定 HLSL，SHA256 `c0aebd916f0cff6a04720bf8111d850e5312e0e7a179c5d8961dc7876d563534`，与既存固定提交 FETCH 的 SHA256/Git blob 再核对。
- C 限定 HDR、white1、same-raster、reversible mode0 composed、color1、ApplyModel on、无 SkinProtection、无 residual/replace/debug/compare/live-exposure 分支。**MaxRatio=2** 来自 pinned Config.h:348，Dx12.cpp:2787 转发默认值；不等于知道作者实际设置。

精确公式、矩阵、源行号、有限值契约见 [MATH.md](MATH.md)。C 使用真正 HLSL HPE/D65 gamut 与 near-grey hue 算法，未借用 O Hue/AP1，也非仅灰阶近似。

## 2. 首先验证 O CPU 与旧 saved D

analyze.py 对两帧都先执行 O(A=S,B,N=P5,实际 metadata 控制)，通过后才计算 C。这里是 RGB 未量化 float64 数学 vs 已保存半精度 D；alpha 与 S 逐值相等。

| frame | MAE | p99 abs | max abs | 差值≤saved向上相邻half间距的分量 |
|---|---:|---:|---:|---:|
| 2 | 0.000084239 | 0.000408623 | 0.014301437 | 99.97810% |
| 3 | 0.000088595 | 0.000425163 | 0.014301437 | 99.97971% |

通过的是**数值一致性门**：MAE<1e-4、p99<5e-4、max<.016，并非 exact shader parity。最大的 .0143 出现在 HDR 数值范围（A RGB max=38.59375），不可把绝对 max 当作同量级暗部误差。

NumPy RNE-half 再量化与 saved D 仅约 **50% 分量相等**；未量化误差绝大多数处于一个 half 间距内，小部分略超（最大约1.00364间距）。**本次不把这个分布宣布为 RTZ surface 证明，也不把 float32 CPU 当 GPU**。没有模拟 shader 编译/FMA、pow/exp 近似、denormal、texture addressing 精度或确证 surface rounding。完整诊断在 [VALIDATION.json](VALIDATION.json)。O float32/float64 P5 实际 .6 差的 max 约3.64e-6，不能替代 shader 验证。

## 3. 同一 A/B/N，仅换 compositor

所有表格 Y 统一用线性 BT.709 权重 (.2126,.7152,.0722)，未作显示 tone-map；O 内部仍用自己的源权重。RGB MAE/p99 在未量化 math RGB 上算；guard 数是 C 自己中间 floored ratio 的触发占比。

| frame | 冻结 N | t | RGB MAE | RGB p99 abs | mean Y O → C | C 下界 / 上界触发 |
|---|---|---|---:|---:|---:|---:|
| 2 | P1 | 实际 .6 | 0.00000020 | 0.000000 | 0.176134 → 0.176134 | 0.000% / 0.000% |
| 2 | P3 | 实际 .6 | 0.00047957 | 0.013697 | 0.197521 → 0.197131 | 0.234% / 2.366% |
| 2 | P5 | 实际 .6 | 0.00411866 | 0.099791 | 0.219197 → 0.215518 | 0.780% / 8.151% |
| 2 | P1 | **反事实 1** | 0.00001393 | 0.000001 | 0.182012 → 0.182022 | 0.120% / 0.003% |
| 2 | P3 | **反事实 1** | 0.00373078 | 0.089418 | 0.217658 → 0.215358 | 3.136% / 7.340% |
| 2 | P5 | **反事实 1** | 0.01744749 | 0.234445 | 0.253783 → 0.239764 | 6.348% / 23.038% |
| 3 | P1 | 实际 .6 | 0.00000020 | 0.000001 | 0.179033 → 0.179033 | 0.000% / 0.000% |
| 3 | P3 | 实际 .6 | 0.00076614 | 0.023539 | 0.205275 → 0.204626 | 0.234% / 3.238% |
| 3 | P5 | 实际 .6 | 0.00576413 | 0.123952 | 0.230396 → 0.225164 | 0.743% / 10.404% |
| 3 | P1 | **反事实 1** | 0.00001701 | 0.000001 | 0.186844 → 0.186855 | 0.126% / 0.008% |
| 3 | P3 | **反事实 1** | 0.00509963 | 0.107540 | 0.230579 → 0.226951 | 2.935% / 9.679% |
| 3 | P5 | **反事实 1** | 0.02522461 | 0.276797 | 0.272448 → 0.250843 | 5.887% / 30.432% |

**隔离机制而非臆测**：记录了 C 原公式的 preguard 中间结果（未发明新参数/分支）。P5 实际 .6，C postguard 与其 preguard 的 MAE=.00411842/.00576389，几乎就是总 O/C 差；全部12组 C preguard/O 的 MAE≤4.47e-7。全部比较中黑模型 fallback、gamut compression、最终负RGB clamp 的触发均为 **0**。near-grey 阈值在 P1约.022%、P3约.055–.058%、P5约.106–.112% 像素触发，但并未造成全图大色偏。源实现不同是真的，是否触发必须用目标输入查。

在 actual .6、P5 的源 Y∈[.01,.1) 区域（全图27.651%），mean Y O→C 为 **.098971→.087832 / .105639→.090408**；这部分 RGB MAE **.012267/.016593**。原图 Y<.01 只有 **6个像素**（.001808%），因此本样本不代表广泛极暗夜景，也不能用来排除 C 黑值/近灰防护在别处的作用。

### 颜色与暗部/clip

| frame | P5 t | 输出 Y<.01：O → C | mean Oklab chroma C−O | 平均有效 hue 角差 |
|---|---|---:|---:|---:|
| 2 | 实际 .6 | 0.0181% → 0.0181% | -0.0002299 | 0.000274° |
| 2 | **反事实 1** | 1.4465% → 0.2655% | -0.0004597 | 0.000567° |
| 3 | 实际 .6 | 0.0286% → 0.0286% | -0.0002945 | 0.000285° |
| 3 | **反事实 1** | 1.5134% → 0.3159% | -0.0006397 | 0.000587° |

所有 compositor 输出的**负 RGB、精确0分量比例均为0**；Y<.01 是“暗阈值”，不是硬 clipping 的同义词。C 末端 clamp 在这些像素中没有救回任何负值。HDR RGB>1 另行统计，**不称其为白裁剪**。hue 只在双方 Oklab chroma>1e-4 且 Y>1e-5 时计算，覆盖率/分位数/最大值均保留在 RESULTS.json；近灰像素不强行解释色相。这里主要改的是亮度/随亮度缩放的 chroma，不是大面积换 hue。

C 的 `(Y(u)+1/512)/(Yo+1/512)` guard **不严格保证最终亮度在0.5–2倍**：受控 `o=p=.2,n=.01,t=color=1` 给 C≈.084477，而不是.1。测试同时覆盖上界反例。N=0 时 O=(1−t)A，C=A；但真实两包 N 没有触发这条 fallback。

## 4. 编码单独研究，绝不串成伪完整管线

两包 A 相同，因此 encoder 数字相同。O channel knee 触发 **.705295%** 像素；C luma knee **.096149%**、peak共同缩放 **.280912%**。编码 RGB MAE=.000378645，RMSE=.012106586，max=.758842705；sRGB 解回线性的两种 B MAE=.000448074，max=.951153865。

O CPU encode 与 saved B 的 MAE=.000162214、max=.000488281，全部在 saved 向上一个 half 间距内。仅用于旧 encoder 数学一致性诊断，**本次所有 compositor 仍读原 saved B**，绝不替换为 CPU B_O 或 B_C。

| 同一线性 A（synthetic probe，非新场景） | O 编码 | C 编码 |
|---|---|---|
| (1,1,1) | (.973571,.973571,.973571) | (.958431,.958431,.958431) |
| (4,1,.2) | (~1,.973571,.484529) | (1,.537099,.247801) |

完整黑、低灰、HDR灰、纯RGB、饱和探针见 RESULTS.json；测试验证 C encoded→decoded 色比为同一个缩放后的原RGB方向。B 改变可能改变原模型推理，这是**候选输入原因**；没有把 changed B 配 existing N 然后称“完整社区结果”。encoder NPZ 名称有 `encoder-ONLY`，无任何 NR 执行。

## 5. 看图与数据

- [frame2 实际 .6](images/frame-2-CPU-actual-t0.6.png)、[frame3 实际 .6](images/frame-3-CPU-actual-t0.6.png)：每行 P1/P3/P5，列 O、C、|C−O|×4。
- [frame2 反事实1](images/frame-2-CPU-counterfactual-t1-NOT-settings-change.png)、[frame3 反事实1](images/frame-3-CPU-counterfactual-t1-NOT-settings-change.png)：**不是设置变更**，图内与文件名均标明。
- [同A编码比较](images/frame-3-CPU-encoder-ONLY.png)、[O saved-D 验证上下文](images/frame-3-CPU-validation-context.png)；frame2也各有一张。

每张图明确 **CPU COUNTERFACTUAL ONLY / OLD POST synthetic guides**。compositor 共用旧 preview `max(v,0)/(1+max(v,0))` 后 ^(1/2.2)，并非游戏 EOTF/曝光/最终显示。encoder 图直接显示编码数值；差图线性绝对RGB×4后裁到[0,1]，未用热图自动拉伸。为排版所有面板等比例缩至384×216，定量值来自768×432原数组。图像不能证明真实感/作者质量。

`tensors/` 六个 NPZ 保存完整 unrounded float64 CPU RGB，alpha 单独保存（来自S）；不是GPU surface。`RESULTS.json` 包括所有输入域统计、Y/chroma/hue分布、暗/高光/负值、按原A亮度分层的差异、全部CPU32敏感性检查及源中间触发率。输入 B/P 的摘要 Y/chroma 是**编码信号统计**，不是物理亮度；encoder 的真正颜色比较应读 `linear_decoded_B_O_vs_C`。

## 6. 复现与剩余不确定性

项目根执行（只写本目录，不装依赖）：

```sh
OPENBLAS_NUM_THREADS=1 python -B reviews/nr-codec-counterfactual-20260911/test_codec.py
OPENBLAS_NUM_THREADS=1 python -B reviews/nr-codec-counterfactual-20260911/analyze.py
```

**15个测试通过**：源码/guard pin和转发、矩阵方向、sRGB阈值、identity/黑NR/黑A、HDR灰与饱和RGB、ratio floor/双侧guard及最终Y反例、近灰、D65 gamut共同缩放、标量C全RGB独立运算流程、黑阈值/proxy小分母、signed-original差异、缺失/长度错误/非有限值硬失败、旧metadata/O-D验证、loader安全提取。100个固定种子的完整RGB标量/向量C样本×两种t比对；不是GPU oracle。

完整日志 [tests.log](tests.log)、[analysis.log](analysis.log)；第二次完整运行的 **16个 JSON/PNG/NPZ 数值产物 SHA256 全部逐字复现**，见 [REPRODUCIBILITY.json](REPRODUCIBILITY.json)。[SHA256SUMS](SHA256SUMS) 固定本目录交付物（不包含自身）；`python -B reviews/nr-codec-counterfactual-20260911/verify.py` 只读核查输入、产物hash及图像/张量结构。重新生成 tests.log 的计时可能改变日志hash，并不表示数值产物不复现。只从已SHA-pinned旧analyzer AST提取 load/preview，不执行旧main/compose，避免旧图像被覆盖。全部 pin 在计算前后核验。CPU64输出可跨NumPy/BLAS版本存在末位差；环境版本记录在 RESULTS.json。

**未做 GPU、Wine、新 inference、配置/安装改动、旧参考编辑、网络下载、完整社区模型执行。** C发布二进制是否编译此HLSL、作者实际DLL/设置/seam/history/曝光/显示后处理仍未知。后续层tone默认、PRE/POST与NR/SR/RR次序、工作分辨率、输入域和真实guides等静态差异不能由本次 fixed-N 研究代替。这次证明的是“哪些宿主机制在这张旧输入上有多大作用”，不是“社区为什么必然更真实”。

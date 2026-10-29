# DLSSNR → MFG 管线、性能与轻量转接器研究记录

日期：2026-09-02

这份记录汇总本机已完成的 DLSSNR 架构、原生性能、SM/XBAR/SYS 缩放、《鸣潮》NR→FG 时域伪影、DLAA 热切换故障、NVIDIA 首批官方 DLSS 5 性能数据，以及一个尚未实现的轻量 NR→MFG 转接器方案。

## 0. 证据等级

- **已验证**：由本地二进制、原生 DLL Evaluate、GPU timestamp、输出哈希、日志或录屏直接支持。
- **强推断**：多项证据一致，但官方没有公开完整 ABI/训练细节。
- **构想**：尚未实现或训练，不得描述为现有组件。

尤其要区分：

1. 模块存在；
2. Feature Create 成功；
3. Evaluate 成功；
4. 每帧真实运行；
5. 性能可用；
6. 与下游 MFG 时间域兼容。

前五项不能自动证明第六项。

---

## 1. 本地运行时身份

- DLL：`nvngx_dlssnr.dll` 310.8.0.0
- SHA-256：`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`
- 权重资源：`WEIGHTS_HT.bin`
- 权重 SHA-256：`836f445d06ecd2e59bb9f17b84b91c143396fd76ccda1c9dc7fe81d5edd548f4`
- 权重 payload：147,683,778 bytes
- 模型配置：`CC_Control_History_Blend_Quantize_With_Teacher_honest_tench_2026_07_04_22_30_weights`
- Backbone：`crazy-cuckoo`
- `architecture.json` SHA-256：`2f5edac58de5c6f9024103ba4c9443a00070e9dee376aa71e5ed0c3aa5082bc7`
- `manifest.json` SHA-256：`ede129b017f44fd811ea80b8d3c3cdfda2718f38f5fd0b5b0891dc60855ccf05`

模型名中的 `History`、`Blend`、`Quantize` 和 `With_Teacher` 是实际字符串；它们支持“有时域状态、量化和教师/学生训练路径”的判断，但不公开教师模型、训练集或 loss。

---

## 2. 架构复核：为什么几乎不能增量压缩

### 2.1 精确图结构

DLL 图工厂导出的 `architecture.json` 记录：

- 71 blocks
- 152 executable layers
- 153 serialized tensors
- 47 个 single-layer fused blocks
- 16 个 512-channel split-Swin blocks
- 8 个 1024-channel 1-D ViT blocks

语义拓扑近似为：

```text
RGB/控制/历史输入
  → fused Swin encoder: 32 → 64 → 128 → 256 channels
  → 8 × split-Swin, 512 channels
  → 8 × 1-D ViT bottleneck, 1024 channels
  → 8 × split-Swin, 512 channels
  → fused Swin decoder: 256 → 128 → 64 → 32 channels
  → RGB residual/control blend
```

Decoder 通过硬编码 skip 连接 block 22、14、8、4、0；中间还存在 `inpview`、`outview`、2D↔1D repack、upsample、downsample、tile-sync、wait 和 publish 专用路径。

### 2.2 已经消耗掉的“容易优化项”

原生路径已经使用：

- Blackwell `sm_120` CUBIN；
- E4M3 FP8 融合 kernel；
- 混合 FP16 tail/scale；
- 自定义 approximate softmax；
- 专用 Tinlayout pack/repack；
- fused Swin/ViT/encoder/decoder kernel；
- teacher/distillation 与 quantize 命名路径。

它不是可以直接套通用 INT8、剪枝或 TensorRT profile 的普通 ONNX 图。改变通道数会同时破坏 packed matrix 边界、attention head 几何、skip adapter、历史状态布局和专用 CUBIN ABI。

### 2.3 权重占比与真实耗时错位

| 部分 | 权重占比 | 6K 原生 kernel 时间占比 |
|---|---:|---:|
| 1-D ViT bottleneck | 68.18% | 19.69% |
| split-Swin | 约 22.04% | 13.85% |
| 高分辨率 fused Tinlayout 前后端 | 约 9.78% | 64.80% |
| 其他 copy/repack | — | 1.66% |

所以：

- 大幅压缩 ViT 权重主要减文件/常驻权重，不会同比降低时延；
- 真正耗时的是权重很少但激活分辨率很高的 fused 前后端；
- 缩这些阶段必须重做整个多尺度网络，而不是删除几个 block；
- “轻量版”实质上需要 NVIDIA 重新设计、重新蒸馏训练并重新生成整套 kernel。

---

## 3. 原生 DLSSNR 性能

### 3.1 分辨率 sweep

`native-inference-timing.csv`：

| 尺寸 | 像素量 | GPU 时间 |
|---|---:|---:|
| 384×384 | 0.147 MP | 3.630 ms |
| 1024×576 | 0.590 MP | 3.808 ms |
| 2048×1152 | 2.359 MP | 4.702 ms |
| 3840×2160 | 8.294 MP | 9.278 ms |
| 6144×3456 | 21.234 MP | 20.255 ms |

独立 C++ 100 次重测：

- 4K：9.360 ms
- 6K：20.787 ms

对 `≥2.3 MP` 拟合：

```text
GPU 时间 ≈ 2.611 ms + 0.828 ms × 每百万像素
R² = 0.999505
```

因此大尺寸区间近似按输出像素线性增长，不应再笼统描述为“非线性”。

### 3.2 Nsight 原生 kernel

每次原生 Evaluate：

- 156 次 CUDA kernel launch
- 43 个 kernel family
- 4K kernel 合计约 7.726 ms/Evaluate
- 6K kernel 合计约 18.442 ms/Evaluate
- 6K 最大单一 kernel family 只占 12.6%

证据：

- `nsys-dlssnr-4k-stats.csv`，SHA-256 `9b4eff4d043ff609827eade543be19aac6253d631b64090f82e921fe7448cf36`
- `nsys-dlssnr-6k-stats.csv`，SHA-256 `60ebd99979f4119093a59b3f48234f7671ada0c99ad3eb31ee4720607a88375b`

没有一个单独热点可以“一刀砍掉”获得数量级收益。

---

## 4. SM/GPC、XBAR、SYS 缩放

所有 sweep 都使用同一 6144×3456 输入、五次 Evaluate、丢弃 iteration 0，并通过 `cuCtxSynchronize` 覆盖 NGX 内部/default stream。最终输出哈希均为：

`028e7fa578b62928031494f1a0c399ef12d5a8a26c7e013a858eac5963116a24`

### 4.1 原始 16→170 SM sweep

目录：`gpc-sweep-contextsync-20260830-2315/`

- 16 SM：155.170 ms
- 80 SM：33.794 ms
- 160 SM：20.686 ms
- 170 SM：20.129 ms

拟合：

```text
time_ms = 2392.83 / SM + 4.67
R² = 0.99949
```

16→170 SM 实际加速 7.71×，低于理想 10.625×；160→170 SM 只改善 2.69%。

### 4.2 XBAR +301 / SYS +206 / ratio 0.9500

目录：`gpc-sweep-xbar301-sys206-20260902-070928/`

控制回读：

- XBAR `+301449 kHz`
- SYS `+205797 kHz`
- GPC→XBAR `62259/65536 = 0.9499969482`
- MCLK 15001 MHz
- 功耗限制 600 W
- 当前 GPC 峰值 2992 MHz；旧 sweep 为约 3097 MHz

结果：

- 16 SM：164.735 ms
- 170 SM：21.220 ms

拟合：

```text
time_ms = 2549.57 / SM + 4.956
R² = 0.999720
```

相对旧 sweep 绝对时间慢约 5–8%，主要混杂变量是当前 GPC 较低及旧 Green probe 二进制已被后续构建覆盖。按 GPC 频率粗归一，170 SM 仍约慢 1.85%；这不是严格隔离的 XBAR A/B。

### 4.3 XBAR +301 / SYS +146 / ratio 0.92656

目录：`gpc-sweep-xbar301-sys146-ratio0p9266-20260902-071456/`

控制回读：

- XBAR `+301449 kHz`
- SYS `+145797 kHz`
- GPC→XBAR `60723/65536 = 0.9265594482`
- GPC 峰值 2992 MHz

结果：

- 16 SM：166.074 ms
- 170 SM：21.179 ms

拟合：

```text
time_ms = 2565.65 / SM + 4.790
R² = 0.999539
```

与上一 tuple 比较：

- 170 SM：−0.20%
- 全部点的中位变化：−0.12%
- 排除 144 SM 离群点后的平均变化：−0.07%

**结论**：降低 SYS 与传播比例、从而降低 MSVDD 所需电压后，单实例 DLSSNR 吞吐基本不变。收益主要是能效/电压裕量，不是时延。短采样峰值功耗从 155.71 W 到 151.83 W，方向一致，但样本不足以将约 3.9 W 精确归因于该 tuple。

单实例结果不能回答“多个独立模型并发时是否转为 XBAR/L2 瓶颈”；需要两个独立 Green Context 同时 Evaluate 的专门实验。

---

## 5. 《鸣潮》实际 `SR/RR → NR → FG` 链

现场组件身份：

- 已部署稳定 service：`01-dlss5-post-service.addon64`
- service SHA-256：`6e1621581aa2a1a81b422a5870c07ed326a32299d4c1b2a098a1c8af42d29210`
- 当前 bridge 源码：`../dlss5_vk_bridge/dlss5_vk_bridge.cpp`
- 当前源码 SHA-256：`93154cea2faf8acf2675ce2d4bd7733c9aeabbceb70faa27daf80b8d45c68cc8`

### 5.1 顺序

本地 router 在原始 SR/RR Evaluate 成功返回后，同步调用 post service。NR 直接写回游戏 SR/RR 的同一个 Output；Streamline DLSSG 随后在 Present/FG 路径消费最终场景、MV、Depth、HUDless/backbuffer 等资源。

因此《鸣潮》当前逻辑顺序已验证为：

```text
Engine render
  → native DLSS SR/RR Evaluate
  → Feature18/DLSSNR post-SR Evaluate
  → Streamline DLSSG/MFG
  → Present
```

NR 调用不是依赖 ReShade Present callback，因此不是简单的 Present hook 顺序猜测。

### 5.2 6K 各 SR 档输入

日志中观察到：

- Quality：约 `4099×2306 → 6144×3456`
- Balanced：约 `3564×2005 → 6144×3456`
- Ultra Performance：约 `2046×1151 → 6144×3456`

后置 NR 始终处理 6144×3456 输出，游戏路径约 17–17.5 ms。降低 SR 输入只节省上游渲染/SR，不降低固定 6K NR 成本。

近似关系：

```text
FPS_with_NR ≈ 1000 / (1000/FPS_without_NR + 17 ms)
```

例如 45 FPS Balanced：

```text
22.2 ms + 17 ms = 39.2 ms ≈ 25.5 FPS
```

这与用户现场观察的约 25 FPS 一致。

### 5.3 NR→6×FG 鬼影现场

录屏：`/home/user/2026-09-02 06-14-04.mp4`

- SHA-256：`0073929140ee0c40dd0d1c2290cb350da9637afb14b796f436b32e18369c05f1`
- 6144×3456、60 FPS、AV1
- 时长 28.373 秒
- 场景设置：Ultra Performance SR + 6×FG + post-SR NR

逐帧观察：

- 静态背景相对稳定；
- 角色起步、奔跑、技能动作时，头发、裙摆、腿、武器和轮廓出现周期性分裂/拖影；
- 特效和遮挡边缘出现拉伸、残留与错误填充；
- 症状符合“NR 新生成的高光/材质细节无法被原始 engine MV/Depth 完整解释，MFG 在两个 NR 端点之间错误外推”。

这验证了当前链路存在实际时间域兼容问题。严格因果边界仍需注明：本轮没有保存同场景、同 Ultra Performance + 6×FG、仅关闭 NR 的完整 A/B，因此不能把所有鬼影增量百分之百归因于 NR；低基础帧率的 6×FG 本身也会产生伪影。

确定性并不等于运动等变性。真正需要满足的是：

```text
warp(NR(Frame_t), MV_t) ≈ NR(warp(Frame_t, MV_t))
```

以及正确的 disocclusion/reset 行为。

---

## 6. DLAA 热切换故障

关闭 FG 后，从 Ultra Performance 热切换到 DLAA：

- 桥接先映射新的 6144×3456 全分辨率 MV/Depth；
- 创建 4096×2304 guide proxy；
- 尚未记录下一次成功 NR Evaluate，进程/画面即异常；
- 内核出现 `intermapRegisterDmaMapping` 失败和 `gpu_vaspace.c` 断言；
- 无 Xid；
- 无新 UE crash dump。

这把故障定位到高分辨率 DLAA 热重建期间的 D3D12↔Vulkan 映射/资源生命周期区域，而不是已证明的 Feature18 Evaluate 崩溃。

建议但尚未部署的安全策略：检测高分辨率 `render == output` DLAA 时 fail-closed，保留原生 DLAA 输出，不映射全分辨率 guides；恢复 SR 后强制 NR temporal reset。

---

## 7. NVIDIA 2026-09-01 首批官方性能数据

官方页面：

- <https://www.nvidia.com/en-eu/geforce/news/dlss-5-3d-guided-neural-rendering/>
- <https://research.nvidia.com/labs/adlr/DLSS5/>

测试均为《NBA 2K27》、Ultra、RT On、Ryzen 7 9800X3D、64 GB、Windows 11，并同时开启：

```text
DLSS 5 3D-Guided Neural Rendering
+ DLSS Super Resolution
+ 6× Multi Frame Generation
```

### 7.1 关键数字

| 输出分辨率 | SR 模式 | GPU | 官方输出 FPS | 粗略除以 6 的端点 cadence |
|---|---|---|---:|---:|
| 3840×2160 | Performance | RTX 5090 | 370 | 61.7 |
| 3840×2160 | Performance | RTX 5080 | 233 | 38.8 |
| 2560×1440 | Quality | RTX 5090 | 594 | 99.0 |
| 2560×1440 | Quality | RTX 5080 | 413 | 68.8 |
| 2560×1440 | Quality | RTX 5070 Ti | 353 | 58.8 |
| 2560×1440 | Quality | RTX 5070 | 262 | 43.7 |
| 1920×1080 | Quality | RTX 5060 | 258 | 43.0 |

除以 6 不是精确的 MFG-off 性能，因为关闭 MFG 会释放其自身开销；它只用于近似真实端点更新频率，不能当作输入延迟。

NVIDIA 没有提供：

- 同内部分辨率 NR Off/On；
- SR-only 与 SR+NR；
- MFG Off；
- 1% low/frametime；
- PC latency；
- VRAM、功耗；
- 高速运动/鬼影量化。

另一个 `Native 4K DLSS Off 227 FPS → Full Stack 370 FPS` 图同时改变 SR、NR 和 6×MFG，不能用于隔离 NR 成本。

### 7.2 4K 时间预算与本地 9.36 ms 对齐

RTX 5090 4K：

```text
370 / 6 ≈ 61.67 个真实端点帧/s
端点预算 ≈ 16.22 ms
本地 4K NR ≈ 9.36 ms
剩余 ≈ 6.86 ms
```

剩余预算需要容纳约 1080p 内部渲染、SR Performance、MFG/光流和调度。NR 占最终端点预算约 57.7%，与媒体转述的 NVIDIA 工程师“50–60% 性能损失”数量级吻合。

这使官方运行顺序强烈指向：

```text
Engine → SR/RR → DLSS 5 NR → MFG → Present
```

本地《鸣潮》已直接验证此顺序；官方材料把 NR 描述为真实帧的最终 appearance stage，并把 MFG 作为其下游组合，但未公开完整 ABI block diagram。

### 7.3 “5× 模型性能”与本地 July 模型

官方曲线声称六个月内模型性能提升 5×，图示约：

- March：1×，dual RTX 5090
- May：约 1.45×，single RTX 5090
- July：约 2.5×
- August：5×

本地模型名带 `2026_07_04`，可能早于首发 NBA 构建。但官方纵轴没有毫秒，也没有给出模型 hash/版本与各节点映射；不能据此断言正式模型比本地快两倍。4K 官方预算反而与本地 8–9 ms NR 成本相容。

---

## 8. MFG-aware 训练假设

### 已公开/强支持

- NR 是确定性的 causal one-frame-in/one-frame-out 模型；
- 但它不是纯空间滤镜：使用 motion vector 和 carried temporal state；
- NVIDIA 称其经过 frame-to-frame temporal stability 训练；
- 训练使用 renderer-derived scene attributes 做一致性监督；
- 正式产品明确要求与 MFG 共存。

### 尚未公开

NVIDIA 没有确认：

- NR 与 MFG 端到端联合训练；
- MFG 生成帧 loss 是否反传到 NR；
- 是否有专门 ghosting/disocclusion loss；
- 是否更新了 MFG 模型以适配 NR 输出分布；
- 是否存在 NR→MFG guide adapter。

合理但未证实的训练方式包括：

1. 在 NR loss 中加入 MFG/光流代理，约束 NR 输出运动等变；
2. 冻结 MFG，用生成中间帧对高帧率真值的误差微调 NR；
3. 冻结 NR，微调 MFG 以适应 NR 新生成的皮肤、头发、高光和材质细节；
4. 用正式游戏的 control mask、材质/人物标签和 disocclusion 数据做集成级监督。

“产品链与 6×MFG 一起发布”说明必须做端到端验证，但不等价于已证明联合训练。

---

## 9. 构想：轻量 NR→MFG 转接器

状态：**构想，未实现、未训练。**

### 9.1 目标

不重训 148 MB NR 主模型，也不重训完整 MFG；在二者之间增加几十万参数的 domain adapter，把 NR 端点转换成 MFG 可解释的颜色/运动/置信度表示。

```text
                     ┌──────────── SR conservative endpoint
Engine → SR → NR ────┤
                     └→ lightweight adapter → MFG-compatible endpoint/guides → MFG
```

### 9.2 建议输入

低分辨率（1/4 或 1/8）输入：

- 当前 SR 颜色；
- 当前 NR 颜色；
- `NR - SR` residual；
- 上一真实帧 SR/NR 经 engine MV warp 后的差值；
- engine MV；
- Depth 与 Depth gradient；
- disocclusion/valid-history mask；
- optical-flow/MFG confidence（若接口暴露）；
- reset/camera-cut 状态。

### 9.3 建议输出

```text
alpha             NR/SR 融合 mask
DeltaMV.xy        NR 生成细节的运动修正
confidence        MFG 可信度
occlusion         遮挡/新显露区域 mask
optional residual 小幅颜色修正
```

组合示例：

```text
Color_for_MFG = SR + alpha × (NR - SR)
MV_for_MFG    = EngineMV + DeltaMV
```

- 静态、可靠区域：`alpha ≈ 1`，保留 NR；
- 快速角色、头发、衣摆、透明/反射、disocclusion：降低 alpha 或修正 MV；
- 最保守路径只输出 alpha，在危险区域退回 SR；
- 更高质量路径输出 DeltaMV/confidence，让 MFG 保留移动中的 NR 细节。

### 9.4 训练方式

冻结 NR 和 MFG，仅训练 adapter。训练序列需要高帧率真值及匹配的 MV/Depth/遮挡：

- MFG 中间帧对高帧率真值的 Charbonnier/L1；
- perceptual/LPIPS（谨慎使用，避免重新引入幻觉）；
- warp consistency；
- disocclusion BCE；
- temporal flicker loss；
- DeltaMV 正则；
- 静态区域 NR 保真 loss；
- reset/cut 后快速收敛约束。

参数量可以很小，但运行成本主要由全分辨率 activation traffic 决定，而不是权重大小。因此建议在 1/4 或 1/8 分辨率预测 mask/guide，再做轻量上采样；不要再堆一个全分辨率 Transformer。

### 9.5 DLL 不提供 backward 时的训练方法

不需要把 NVIDIA DLL 逆向成可微计算图。NR 和 MFG 都可以冻结并当作黑盒；adapter 的输入/输出矩阵布局对齐后，有三条实用路径。

#### A. 不穿过 MFG 的直接监督

令：

```text
z = Adapter(SR_t, NR_t, MV_t, Depth_t, history)
Color_t = SR_t + alpha_t × (NR_t - SR_t)
```

只对真实端点训练：

- `warp(Color_t, MV_t) ↔ Color_{t+1}` consistency；
- forward/backward optical-flow consistency；
- Depth disocclusion；
- 高帧率真值导出的 `DeltaMV = Flow_NR - MV_engine`；
- 静态区 `alpha→1`，不可靠运动区 `alpha→0`。

这条路线完全不需要 DLL 梯度。它直接减少 MFG 输入端点的不一致，是首个原型最稳妥的目标。

#### B. 对真实 DLL 做 SPSA/antithetic 黑盒 VJP

不要对几十万权重逐项差分；只扰动 adapter 的低分辨率输出 `z`。对每个训练样本：

```text
z = Adapter_theta(x)
delta ∈ {-1,+1}，为低分辨率 Rademacher 扰动
L+ = Loss(MFG(Compose(z + epsilon×delta)), high_fps_GT)
L- = Loss(MFG(Compose(z - epsilon×delta)), high_fps_GT)

g_z ≈ ((L+ - L-) / (2×epsilon)) × delta
z.backward(g_z)
```

SPSA 每条方向只需两次真实 DLL 前向，开销与参数数量无关；PyTorch 再从 `z` 正常反传到 adapter 权重。可以使用多条 antithetic direction、tile/block 扰动、EMA 和 gradient clipping 降低方差。

难点不是矩阵乘法，而是让两次 MFG 调用具有完全相同的 temporal state：

- 相同的端点帧、MV、Depth、HUDless/UI 与 camera metadata；
- 每次 `L+`/`L-` 前将 MFG state 恢复到同一快照或可靠 reset；
- 固定生成帧时间位置与倍率；
- 获取真实中间生成帧而不是 60 Hz 视频抽样；
- 避免 Present 调度和异步队列引入随机差异。

若不能重放相同 Streamline state，SPSA 差分会主要测到调度噪声而不是 adapter 梯度。

#### C. 蒸馏一个可微 MFG surrogate

先采集：

```text
(endpoint_t, endpoint_t+1, MV, Depth, HUDless, timing)
    → 真实 MFG intermediate frames
```

训练一个只在当前数据分布附近拟合 MFG 的小型 surrogate `G_phi`。冻结 `G_phi` 后，通过它把中间帧 loss 反传到 adapter；每隔若干 step 再用真实 DLL 做验证/黑盒校正。surrogate 不必复刻完整 DLSSG，只需近似 adapter 所改变的小 residual 邻域或 artifact/confidence map。

黑盒 SPSA 最接近真实 DLL，但运行慢且要求可重复 state；直接端点监督最简单；surrogate 适合二阶段微调。逆向 fused DLL 并编写完整 backward kernel 是三者中收益最低的路线。

### 9.6 不依赖商业游戏的 MFG 专属监督

普通视频不能作为最终监督。它没有 engine MV、Depth、jitter、camera matrices、reset、HUDless/UI、精确 disocclusion、MFG 中间帧时间位置，也没有 NR/MFG 的隐藏时域状态。再训练一个识别器从视频猜这些量，会把问题变成另一个欠约束的大模型，并产生严重的游戏/素材过拟合。

可行方案是程序化合成渲染器加“稠密 NR 教师”：

```text
同一确定性场景 S(t)，以 6×时间密度真实渲染 t0...t6
  → 得到每个时刻的 RGB、Depth、MV、instance ID、occlusion、camera、HUDless/UI
  → 独立的 dense NR teacher 按 t0...t6 顺序运行
  → 得到 oracle NR 帧 T0...T6

训练分支只保留端点 t0、t6
  → sparse NR → adapter → 真实 NVIDIA MFG
  → 生成 G1...G5

Loss = Σk Loss(Gk, Tk)
```

教师目标 `Tk` 不是普通渲染 RGB，而是“如果中间时刻真的被渲染并经过 NR，应当出现的画面”。因此 loss 同时依赖 NR 和 MFG，也不会自然塌缩为 `alpha=0`/完全关闭 NR。可再用普通高质量 renderer frame 只约束几何边缘和可见性，避免把 dense NR 自己的几何错误当真值。

建议损失：

```text
L = Charbonnier(Gk, Tk)
  + λedge GradientLoss(Gk, Tk)
  + λperc LPIPS/DISTS(Gk, Tk)
  + λocc OcclusionWeightedLoss
  + λtemp TemporalFlickerLoss
  + λkeep EndpointNRPreservation
  + λflow DeltaMVRegularization
```

#### 不让模型依赖游戏语义

adapter 不应学习“识别头发/角色/某款游戏”，而应学习局部可靠性。输入先规范化成跨引擎物理量：

- `NR-SR` residual / local luminance；
- 当前端点和上一端点的 motion-compensated residual；
- engine MV 与 NR optical flow 的差；
- log/relative Depth 与 Depth gradient；
- forward/backward flow consistency；
- jitter、delta time、cadence、reset；
- occlusion/confidence 的教师标签。

训练时教师可以读取 instance ID、精确世界坐标和可见性等“特权信息”；部署时小模型只读 SR、NR、MV、Depth 和自己的短历史。对于透明、反射、粒子等无法从现有 guides 恢复的运动，目标不是凭空重建，而是预测低 confidence、降低 alpha 并退回 SR。

#### 泛化与数据划分

- 每个序列随机化几何、材质、纹理、灯光、曝光、相机、速度、骨骼、布料、alpha-tested hair、粒子、反射、阴影、动画纹理、UI 和 distortion；
- 随机化 2×–6×倍率、12–120 Hz 端点 cadence、分辨率、SR 比例和 jitter；
- augmentation 必须同步变换 RGB/MV/Depth/camera，不能只随意改图片；
- 按完整 scene/asset/motion family 划分 train/validation/test，禁止把同一视频的相邻帧随机拆开；
- 留出从未训练的资产、材质、速度范围、分辨率和整套 renderer pipeline；
- 最终在完全未参与训练的真实游戏上零微调验证。

Kubric/MOVi、MPI Sintel、FlyingThings3D 等带 flow/depth/segmentation 的合成数据只适合预训练 occlusion/confidence；它们没有真实 NR+MFG 输出，不能代替最终闭环监督。Blender 可按 fractional timestamp 输出 RGB/Depth/Vector/ID，或直接扩展 D3D12 renderer。

#### 无游戏 MFG host 的可行性与真实障碍

NVIDIA 的开源 `Streamline_Sample` 已含 D3D12/Vulkan renderer、Depth、MotionVectors、HUDless/UI tagging、Reflex 和 DLSS-G，源码还带 sample App ID `231313132`；可以改造成确定性数据生成器，不需要借用商业游戏 App ID。

标准 Streamline DLSS-G API在 `Present` 内异步生成并展示帧，只公开 `numFramesActuallyPresented`，没有正式的 generated-texture callback。真正的训练需要取得图像矩阵。OptiScaler 的直接 NGX 路径已经暴露出可利用的内部资源键：

```text
DLSSG.OutputInterpolated
DLSSG.OutputReal
DLSSG.MultiFrameIndex
DLSSG.MultiFrameCount
```

这表明可在实验 host 中为每个中间位置绑定自己的 D3D12 UAV，并复制/readback 真实 MFG 输出；但该未公开契约仍需用正式 runtime 验证。

所以最难的不是普通视频泛化，而是：

1. 构建可确定重放的 Streamline/NGX MFG host；
2. 捕获每个 `OutputInterpolated`；
3. 为 dense teacher 与 sparse/MFG student 分离并重置时域状态；
4. 保证 SPSA 的 `+/-` 两次评估从完全相同状态开始；
5. 用足够强的 renderer/domain randomization 缩小 synthetic→game domain gap。

#### 不可辨识性与真实游戏数据壁垒

只给两个 NR endpoint，存在无穷多条与端点一致的中间运动/遮挡轨迹。没有中间时刻的真实场景状态、几何或稠密渲染结果，就没有 loss 能证明其中哪一条正确。这不是换一个 perceptual loss 或识别器可以消除的问题。

因此最终闭环至少需要某种真实 renderer/engine 数据，但游戏不必参与每个 SGD step。可以一次性在离线单机游戏或授权 renderer 中以高 cadence 捕获：

```text
F0...F6
+ 每帧 Depth/MV/camera/jitter/HUDless/UI/reset
```

随后离线生成：

```text
Tk = dense NR(Fk)                         # oracle
G1...G5 = MFG(Adapter(sparse NR(F0,F6))) # student
```

再把捕获包放入自建 MFG replay host 反复训练。游戏只作为无人工标签的数据生成器，而不是训练运行环境。按完整游戏/引擎划分 train/test，并从多个 renderer 收集，才可能验证跨游戏泛化。

如果拿不到稠密中间帧，较弱的自蒸馏信号是把原生 `MFG(SR endpoints)` 当作 motion/occlusion teacher，让 `MFG(adapted NR endpoints)` 对齐其几何与时间位置，同时另外约束 NR residual 保留。这仍然可能退化或继承 MFG(SR) 的错误，不能等价于真正 dense oracle。

因此真正的壁垒是游戏/引擎数据访问与可重放资源捕获，而不是 adapter 参数量。NVIDIA 的优势很可能正是开发商合作构建、内部测试矩阵和合法的数据取得渠道。

### 9.7 为什么它能解释当前差异

- 《鸣潮》：新 NR 直接连接游戏已有 DLSSG，没有已知转接器，运动角色出现鬼影；
- 正式 NBA 2K27：可能同时更新 `nvngx_dlssnr.dll`、`nvngx_dlssg.dll`、`sl.dlss_g.dll` 或 Streamline guide contract；
- 如果正式版时域显著更好，修复可能位于轻量 adapter/MFG 适配层，而不是 148 MB NR 主模型。

需要检查的不只是 NR DLL：

- `nvngx_dlssnr.dll`
- `nvngx_dlssg.dll`
- `sl.dlss_g.dll`
- `sl.interposer.dll`
- 新增 NGX/Streamline 参数、confidence、distortion、mask 或 guide 资源

如果 MFG 不暴露修正 MV/confidence 接口，外部通用注入只能做颜色 alpha 回退，无法完整复现 NVIDIA 内部 adapter。

---

## 10. 多专家并行与 XBAR/L2

另一个构想是多个独立专家并行，再由融合模型合成：

- conservative SR expert；
- detail NR expert；
- temporal/occlusion expert；
- learned fusion/gating model。

原始 SM sweep 的边际递减说明多个独立 Green Context 可能填补单模型 156 段 kernel 链中的利用率空泡，但总延迟仍会上升。按旧经验拟合，两个约 80–90 SM 专家并行的理想完成时间约 34 ms，而非两个全模型串行约 40 ms；这属于低于线性的多专家成本，不是降低单模型延迟。

并发时潜在新瓶颈：

- 每套约 148 MB packed weights；
- 独立高分辨率 activation/skip/history；
- 6K RGBA16F 候选帧约 170 MB/张；
- L2 互相冲刷；
- XBAR/显存带宽竞争。

当前单实例 XBAR/SYS sweep 没有显示吞吐敏感性，不能外推到多实例。真正验证需要两个独立 Green Context 同时运行，记录 wall time、输出哈希、每实例资源划分、XBAR/SYS 实频、功耗和可获得的 L2/DRAM 代理指标。

轻量 adapter 比复制多套完整 `crazy-cuckoo` 更现实。

---

## 11. 后续验证清单

1. 等待正式 NBA 2K27/Game Ready Driver 上线，记录正式 NR/FG/Streamline DLL 的版本、签名和 SHA-256。
2. 用同一 bare CUDA/Vulkan harness 重测正式 NR：4K、6K、100 次 GPU timing。
3. 对比本地 310.8 July 构建与正式模型的架构、权重、kernel 名和输出。
4. 获取正式 NBA 运动场景，测试人物奔跑、转身、头发、球、遮挡、镜头切换和 UI；不能只看静态图。
5. 做严格 A/B：SR+MFG 与 SR+NR+MFG，保持分辨率、SR 档、MFG 倍率、场景和输入序列一致。
6. 检查正式 FG/Streamline 是否新增 adapter/guide/confidence contract。
7. 若接口允许，先实现低分辨率 alpha/DeltaMV adapter 原型；若接口不允许，不用假插帧或普通光流冒充真实 DLSSG。
8. 在《鸣潮》再次热切 DLAA 前，先实现高分辨率 DLAA fail-closed 门控。
9. 如需验证并行多专家，另建双 Green Context 并发实验，不再重复单实例 SM sweep。

---

## 12. 关键证据路径

- 架构：`architecture.json`
- 权重清单：`manifest.json`
- PyTorch 语义重建：`dlssnr_pytorch.py`、`dlssnr_full_pytorch.py`
- 原生结果：`NATIVE_WUWA_RESULT.md`
- 原生分辨率时间：`native-inference-timing.csv`、`native-inference-timing-cpp.csv`
- Nsight：`nsys-dlssnr-4k-stats.csv`、`nsys-dlssnr-6k-stats.csv`
- 原始 SM sweep：`gpc-sweep-contextsync-20260830-2315/`
- XBAR/SYS sweep A：`gpc-sweep-xbar301-sys206-20260902-070928/`
- XBAR/SYS sweep B：`gpc-sweep-xbar301-sys146-ratio0p9266-20260902-071456/`
- 《鸣潮》bridge 源码：`../dlss5_vk_bridge/dlss5_vk_bridge.cpp`
- 《鸣潮》GPU timing：`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/dlss5-gpu-timing.csv`
- 《鸣潮》bridge 日志：`/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/dlss5-vk-bridge.log`
- NR+6×FG 录屏：`/home/user/2026-09-02 06-14-04.mp4`

## 13. 当前结论

- 本地 `SR/RR → NR → MFG` 顺序已验证。
- 6K post-SR NR 的约 17 ms 固定成本会吞掉 SR Quality/Balanced 的大部分性能收益。
- 当前通用 NR→已有 MFG 直连在运动角色上出现明显鬼影。
- DLSSNR 主模型已经是高度融合、混合精度、多尺度时域网络，无法靠简单剪枝/量化获得有意义的 6K 时延下降。
- 单实例吞吐对当前 XBAR/SYS/MSVDD tuple 变化不敏感；降低电压需求可以改善能效而基本不损失性能。
- NVIDIA 官方 4K/6×MFG 数据的时间预算与本地 4K 约 9 ms NR 成本相容。
- 一个低分辨率、几十万参数的 NR→MFG adapter 是合理研究方向，但目前仍是构想；正式版是否已经包含类似组件尚未证明。

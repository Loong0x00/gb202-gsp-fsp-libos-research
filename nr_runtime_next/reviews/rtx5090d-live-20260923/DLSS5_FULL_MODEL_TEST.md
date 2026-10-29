# DLSS 5完整模型在RTX 5090 D上的CUDA实测

日期：2026-09-23

## 结论

已把本地解包得到的完整`nvngx_dlssnr.dll`部署到云端原版32 GB RTX 5090 D，并通过裸CUDA NGX接口成功执行。`CreateFeature`、每次`EvaluateFeature`、`ReleaseFeature`和`Shutdown`均返回成功值`0x00000001`，输出图像正常落盘。

DLSS 5没有一个固定的“CTA需求量”。一帧由156个依次提交的CUDA kernel组成，每个kernel的grid大小不同，而且随分辨率显著变化：

| 输入分辨率 | kernel launches/帧 | 各kernel CTA范围 | 一帧累计CTA（非同时驻留） | ViT主体常见grid |
|---|---:|---:|---:|---:|
| 512×512 | 156 | 8–4,745 | 26,336 | 40次×32 CTA；另2次×96 CTA |
| 3840×2160 | 156 | 160–131,313 | 704,986 | 32次×544 CTA；8次×288 CTA；另2次×2,160/2,176 CTA |

“累计CTA”只是把156次独立launch的grid相加，不代表这些CTA同时运行。5090 D有170个SM，CUDA会把大grid分成多波执行。是否触发此前测到的FP8→FP16并发墙，取决于同一时刻的resident CTA、warp级Tensor指令密度、同步、寄存器/共享内存和访存瓶颈，不能只看总grid是否大于170。

512² trace中，137/156次launch（87.8%）不超过170 CTA，占5090 D所测kernel时间的91.8%；40个主要ViT launch各只有32 CTA。这正是DLSS 5小分辨率没有出现饱和微基准约45%吞吐差距的直接原因。4K时155/156次launch超过170 CTA，但完整模型仍未出现45%级崩塌，说明“grid大于170”也不是充分条件。

## 被测二进制与环境

- DLSSNR文件版本：`310.8.0.0`（`NVIDIA DLSSNR - DVS PRODUCTION`）
- DLL SHA-256：`e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`
- 裸CUDA probe SHA-256：`82647ebb1cbc215793d29ae25e367d9170438ad866aec73113e6ca8f30eb9101`
- patched Wine nvcuda bridge SHA-256：`29354630d413d9b2acf14e4752ee35894375fecbbfbf313d79e1f703c7ad8d7f`
- 云端GPU：原版RTX 5090 D，PCI ID `0x2B87`，170 SM，32,607 MiB，driver `595.71.05`
- 对照GPU：完整RTX 5090，170 SM
- 两张卡功耗上限：均为450 W
- API路径：Wine PE DLL → patched `nvcuda.dll` → Linux CUDA driver；未使用Vulkan

云端容器没有Windows图形设备注册表条目，初次运行在`cuDeviceGetLuid`终止。桥接层源码本来就带有无显示环境路径，因此设置`CUDA_FAKE_LUID=1`，用设备UUID稳定派生一个LUID。它只解决设备身份查询；后续context、stream、array、texture、156次kernel launch和拷回仍由真实RTX 5090 D执行。

## 稳态端到端结果

计时由probe中的CUDA event包围完整`EvaluateFeature`。512²运行100帧，4K运行30帧；下表丢弃前10帧后取中位数。输入、DLL、参数和probe相同。

| 分辨率 | RTX 5090 D @450 W | RTX 5090 @450 W | D延迟差 | D等效吞吐差 |
|---|---:|---:|---:|---:|
| 512×512 | 5.392 ms（185.46帧/s） | 5.047 ms（198.14帧/s） | +6.8% | −6.4% |
| 3840×2160 | 12.264 ms（81.54帧/s） | 10.946 ms（91.36帧/s） | +12.0% | −10.8% |

这不是纯GPU归因：两张卡位于不同主机，且一次Evaluate会由CPU提交156个launch。4K的CPU提交中位数在云端为3.706 ms，本地主机为2.584 ms；CUDA event跨度会包含GPU队列暂时排空时的主机提交空隙。因此12.0%的端到端差异不能全部算作5090 D限制。

Nsight Systems另外抓取了一帧并把156个kernel的实际执行区间相加：

| 分辨率 | RTX 5090 D kernel总和 | RTX 5090 kernel总和 | D/5090 |
|---|---:|---:|---:|
| 512×512 | 2.092 ms | 1.924 ms | 108.8% |
| 3840×2160 | 8.793 ms | 9.061 ms | 97.0% |

单帧profile会有扰动，不应把4K的3%优势解释成5090 D更快；它的意义是：剔除跨主机提交空隙后，真实kernel总时间处于同一档，没有复现饱和`QMMA.16832.F16.E4M3.E4M3`微基准的约45%吞吐损失。

## 输出一致性

两卡输出逐bit一致：

| 分辨率/状态 | 两卡共同SHA-256 |
|---|---|
| 512×512，100次Evaluate后 | `1c6bf93b5e2997b378be66e823c931fdacdca842e1e18581cbdc5789c92b79d5` |
| 3840×2160，30次Evaluate后 | `6e17efb2fdd38513eb6b16511d7bf0e3ed19bef05e87573f0a75d7818682b0cf` |
| 512×512，Nsight单帧 | `571fa2100c1842deff8769510a78f90cbe84810d64bb3ea82eaba41cf1cd793e` |
| 3840×2160，Nsight单帧 | `5188ec9774d5d3cd186909e4669c6bd34b65bafa44dc57016789839ecfd455a2` |

这同时证明云端不是只完成了初始化，而是确实执行了相同模型并生成相同结果。

## 与5090 D选择性Tensor限制的关系

结果与此前CTA sweep并不矛盾：

1. 微基准刻意让大量resident warps连续发射同一种FP8→FP16 QMMA，340 CTA时5090 D只有完整5090约55%的吞吐。
2. DLSS 5是156个异构、融合、同步和访存混合kernel的串行图；小分辨率的绝大多数launch甚至不足一CTA/SM。
3. 大分辨率虽然grid很大，但“大grid”只表示波次数量，并不保证每个SM同时驻留第二个高密度QMMA CTA，也不保证Tensor issue是唯一瓶颈。
4. 因此5090 D的选择性饱和上限在DLSS 5完整图上被低占用、访存、同步和CPU launch开销稀释；本次实测只看到约6–11%的端到端吞吐差，而不是约45%。

## 证据位置

根目录：`/home/user/rt_5090_project/nr_runtime_next/reviews/rtx5090d-live-20260923/`

- `dlss5-full-comparison.json`：两分辨率的完整统计
- `dlss5-full-timings.csv`：逐帧原始计时
- `dlss5-cta-launches-*.csv`：四份逐kernel grid/block/CTA/资源/时长表
- `dlss5-full-512-5090d/`、`dlss5-full-512-5090/`：512²原始日志、输出、遥测、Nsight报告与SQLite
- `dlss5-full-4k-5090d/`、`dlss5-full-4k-5090/`：4K原始日志、输出、遥测、Nsight报告与SQLite
- `dlss5-artifacts/source/`：probe及patched nvcuda源码快照
- `dlss5-analysis-SHA256SUMS`和各目录`SHA256SUMS.local`：完整性校验

本地完整RTX 5090测试后已恢复600 W；云端RTX 5090 D保持450 W并已回到空闲状态。

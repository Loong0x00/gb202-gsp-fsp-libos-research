# 单层 NR→SR vs SR→单层 NR：正确目标的300帧实测

**完成。此次不比较多层迭代。** 6144×3456虚拟显示器、RTX5090，基准前/中/后各100个连续源帧；每帧比较同一输入的两条独立时域链路：

- **A：4096×2304 → NR一次 → signed SR_A → 6144×3456**。
- **B：同一4096×2304 → signed SR_B → NR一次 → 6144×3456**。

## 结论

在本轮同帧画面和统一分析显示映射下，两种顺序**整体外观很接近**：300帧平均SSIM **0.994531**，范围 0.989975–0.999187。显示分析域MAE平均 0.007789，约相当于0–255标尺的 1.986级；不是均匀分布到每个像素的误差。

**这并不等于逐像素相同，也不证明哪种更好。** 全6K HDR差异确实存在，尤其极亮高光会被色调映射和缩图压缩。若优先考虑成本，此前同配置单层NR的GPU实测为前置7.588ms、后置17.056ms；结合本轮整体相似程度，前置是合理的成本优先候选，但这里没有ground truth证明它画质更优或严格等价。

## 逐帧指标

SSIM/PSNR/显示MAE：对两路同样执行曝光1、负RGB截0、逐通道Reinhard `x/(1+x)`、sRGB OETF，再做整数面积缩小到1024×576。**这不是游戏的最终显示色调映射**。HDR MAE/RMSE直接在全部6144×3456 RGB上计算。表内为逐帧指标的平均；不是把所有帧合并后重新计算一个PSNR/RMSE。

|片段|配对帧数|SSIM|PSNR dB|显示域 MAE|全6K HDR MAE|
|---|---:|---:|---:|---:|---:|
|前段|100|0.995235|40.706|0.006910|0.006398|
|中段|100|0.995166|39.779|0.007561|0.008581|
|后段|100|0.993193|38.324|0.008894|0.011232|
|全部|300|0.994531|39.603|0.007789|0.008737|

- 全局逐帧HDR RMSE平均：0.042796。
- 正亮度均值比B/A的逐帧平均：1.002389；它描述变化，不是正确曝光评分。
- 两路alpha全数据最大绝对差0。
- [逐帧差异曲线](/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/order-captures/20260909-134930-single-nr-order-full/difference-curves.png)；[全部300帧CSV](/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/order-captures/20260909-134930-single-nr-order-full/analysis/per-frame.csv)。曲线不跨采集窗口连线。

## 局部差异不能被高SSIM掩盖

保存了每段中间帧的原生像素中心裁剪（无空间缩放），以及一个明确标为最大差异选择偏差的高光示例。

Frame216的强高光示例在 `(3988,1338)`：A的RGB是`[1273,610.5,238.5]`，B为`[106.375,51.0625,20]`，alpha都1，最大通道差1166.625。这不是NaN；固定分析映射后两边都接近白色，所以**0.9945的平均SSIM不能说明HDR高光也一样**。没有参考图，不判定谁更准确。

- [高光原生像素对照](/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/order-captures/20260909-134930-single-nr-order-full/detail-previews/frame-000216-max-HDR-difference-biased.png)
- [前段中心裁剪](/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/order-captures/20260909-134930-single-nr-order-full/detail-previews/frame-000050-center.png)
- [中段中心裁剪](/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/order-captures/20260909-134930-single-nr-order-full/detail-previews/frame-000150-center.png)
- [后段中心裁剪](/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/order-captures/20260909-134930-single-nr-order-full/detail-previews/frame-000250-center.png)
- [六帧总览/差分热图](/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/order-captures/20260909-134930-single-nr-order-full/analysis/contact-sheet.jpg)：每段中间帧加最大HDR差异帧；最大差异帧不是随机抽样或盲评。

## 配对与执行证据

1. 先做无NR双SR校准：两个独立signed Feature1 ID1/2，两帧6K RGBA16F结果逐字节相同。不是共享同一个时域handle反复Evaluate。
2. 正式四个模型实例各自持有历史。两个NR私有参数图和handles不同，共享NRruntime仅bootstrap一次；每个NR角色只Create一次，且每个实际对照帧各Evaluate一次。全程没有第二/第三遍NR。
3. 两条链路收到同源Color/Depth/MV/jitter/exposure和一份不变的本帧控制快照；参数绑定/还原、输出资源/尺寸、记录顺序与计数核验通过。NR Create先build-only，实际execute确认后才用；初次signed SR同未reset command list Create→Evaluate的合法记录顺序有独立校准依据。
4. 连续NR逻辑序号256–355 / 576–675 / 896–995；实际游戏scene ID258–357 / 578–677 / 898–997。窗口间220帧只是不采集，四个历史继续推进，不重置后重算。
5. `MAIN_METADATA_AUDIT.json`和分析器分别通过全部300帧。600个原始平面完整流读并计算SHA256，无缺文件、丢帧、NaN/Inf；无新Xid。所有readback在实际提交之后的Present Signal/fence完成后才由worker Map/写盘。

粗基准时间定位为前2.410–10.235s、中26.039–33.269s、后48.330–55.842s（约3.4–14.6%、37.1–47.4%、68.8–79.5%）。此定位使用summary mtime减官方duration，**不是精确Present/benchmark帧号匹配**；同帧配对依据是同一次拦截调用和四个实例的计数/参数证据。

## 配置与限制

- CP2.31、GE-Proton10-34、RTX5090/驱动610.57.04；普通SR Quality2、PT开、RR/FG/dynamic resolution关；输出6144×3456、输入4096×2304。DLSS调试文字关闭，避免仅后置NR处理调试叠字。
- 两路NR均Style0/Preset0、Intensity/Tone/Structure1、Skin-1、AutoMask关；HDR luminance-gain合成，paper-white/transfer1、color strength0。
- 后置NR实际work source为6144×3456，但兼容Create广告输入为4096×2304，guides仍4K。这是本地实现的比较，不能据此声称官方6K支持或确定内部tensor尺寸。
- 此次比的是两条链路各自结束时的**6K工作HDR**，在游戏最终tone map/HUD之前；不是不同轮次截图，也不是以前的4K多层NR结果。
- 没有raw MV/depth guides，**未测权威时域重投影、拖影/闪烁分数**；不能从数值有限/无Xid推断长期画质稳定。LPIPS未测、未下载模型。两路都不是ground truth。
- 当前同时跑两条完整链路，测试FPS包含两个SR和两个NR，**不能作为单独某个顺序的性能成本**。7.588/17.056ms引用此前独立单层测试的真实NR GPU时间，不是本次双路FPS换算。

## 清理与复原

- 正式raw600平面原总量101,921,587,200 bytes（94.922GiB）；连同这轮2帧NR小样本，共604文件/95.555GiB，**分析、hash与预览留证后均已删除**。
- 更早误采的多层raw1510文件/95.555GiB，以及双SR校准raw4文件/0.633GiB，也已按要求删除。没有删除无关游戏/旧档案/系统快照。
- 指标、逐帧JSON、hash清单、预览、原生像素裁剪、源码/候选和部署恢复证据保留。历史payload hash清单记录测量时文件，不表示raw目前仍在。
- 游戏已退出，三个临时插件移除；生产owned文件、配置/控制/markers、signed SR/RR/FG/NR和loader全部复核恢复。虚拟显示进程已结束，未永久改桌面显示/电源或硬件配置。

证据目录：`/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/order-captures/20260909-134930-single-nr-order-full`；实际运行：`/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/runs/20260909-134931-single-nr-order-full`。

[机器可读摘要](RESULTS.json) · [最后复原核查](FINAL_RESTORATION.json) · [本轮raw清理清单](/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/FULL_ORDER_RAW_CLEANUP.json)

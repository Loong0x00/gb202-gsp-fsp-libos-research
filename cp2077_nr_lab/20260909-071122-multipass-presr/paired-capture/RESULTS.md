> **目标已纠正，raw已清理。** 本报告比较一层/三层，并非用户要求的单层 NR→SR vs SR→NR；不能用其SSIM评价顺序。原始平面已按请求删除。详见 [USER_CORRECTION.md](USER_CORRECTION.md)。原报告原样存于 `RESULTS.before-user-correction.md`，旧 `FINAL_SHA256SUMS` 的报告hash对应那一版本。

# Cyberpunk 2077：300帧同源 Pre-SR NR 对照实测

## 结果与边界

**已实际采集并完成分析，不再是方案或计数推断。** 前、中、后各100连续源帧，共300帧、1500个raw平面，101,921,587,200 bytes（94.922 GiB）。无丢帧、缺文件、NaN/Inf；三路颜色alpha最大差为0。

- 原图、NR一层、NR三层为同一次持续三遍运行中的**同源4096×2304线性HDR工作图**，另存同期MV/深度。第一遍在第三遍覆盖A之前GPU保留，并用相同HDR codec/控制量合成；不是重置后重算。
- 捕获在原签名SR之前；**没有把最终6144×3456 SR结果冒充独立配对分支**，也不代表NR关闭、一层、三层三次独立完整游戏历史。
- 300帧均匹配到同一router源调用ID与QPC区间；尺寸、jitter、MV scale、曝光、flags一致；signedSR success、绑定/恢复成功、post调用0。
- 原配置、owned插件、控制文件与markers已恢复；签名DLL未改，游戏已退出，没有永久部署采集版。

## 同帧差异

SSIM在共同1024×576尺寸上计算。固定分析映射为线性HDR乘曝光1 → 负值截0 → 逐通道Reinhard `x/(1+x)` → sRGB OETF；**不是游戏最终色调映射**。HDR MAE直接在完整4096×2304 RGB上计算。表内为逐帧指标平均值。

|片段|原图↔一层 SSIM|原图↔三层 SSIM|一层 HDR MAE|三层 HDR MAE|
|---|---:|---:|---:|---:|
|前|0.984207|0.915365|0.014135|0.036599|
|中|0.980449|0.904543|0.020806|0.049987|
|后|0.971179|0.858093|0.026794|0.068618|
|全部|0.978612|0.892667|0.020578|0.051735|

- 三层相对原图的全分辨率HDR平均绝对改动约为一层的 **2.514倍**；显示分析域MAE分别为 0.019557 / 0.047874。
- 一层与三层之间SSIM为 0.951210。
- 逐帧正亮度均值之比（处理后/原图）的平均，一层 0.985557，三层 0.970069。这是场景亮度变化，不是更准确的曝光。
- **可以确认NR在改图，三层改得更多；不能由更低/更高SSIM判定改善。** 原图不是ground truth，无处理反而可以获得最高相似度。

## 时域检查

只比较每段内部相邻源帧：297对有效，2个跨段候选明确排除。使用采集到的backward MV假设（`previous=current+rawMV*scale`），默认不额外加jitter差；`0x4b`没有设置MVJittered bit2。遮挡/反遮挡筛选仅为深度阈值启发式，不是权威可见性；有效mask平均覆盖 97.294%。

共同缩小HDR域，重投影MAE平均值：

|信号|MAE|
|---|---:|
|原图|0.04104096|
|NR一层|0.04092999|
|NR三层|0.04230112|
|一层增强残差 `NR1-original`|0.00571923|
|三层增强残差 `NR3-original`|0.01298832|

三层增强残差的绝对时域变化为一层约 2.271倍，但三层本身改动也更强；**这不能直接翻译成“闪烁多了2.3倍”**。运动、照明、透明物与MV/jitter约定仍会影响分数；这些数据不足以单独排名真实拖影/闪烁或证明长期稳定。

LPIPS没有运行：本机未安装lpips，未下载权重，未用随机网络冒充结果。

## 实际窗口

源成功三遍序号（zero-based）：256–355 / 576–675 / 896–995。实际调用ID为260–359 / 580–679 / 900–999，每段连续。

根据summary文件mtime减官方duration作粗时间定位：前2.119–9.567s，中24.446–31.256s，后45.148–52.238s；约基准进度3.15–14.22%、36.34–46.46%、67.11–77.65%。这是粗分段定位，**不是不同录像帧号匹配**。

## 安全与验证

- 实际提交关联后，在匹配的后续Present排入Signal；worker只有GetCompletedValue证明完成后才Map。渲染线程不Map/等待GPU/写盘/哈希。
- 硬上限300帧/120GiB/360秒、最多96 readback槽/32GiB并保留8GiB可用RAM；实际捕获终态耗时75.180秒（含GPU提交与IO，**不是NR推理耗时**）。
- 首轮小样本因router部署名的`00-`前缀未匹配而在初始化失败，0帧；已修复并保留失败/回滚记录。修正后2帧通过，再执行本300帧。
- 1500平面完整流读并计算SHA256，所有byte-size/有限值校验通过；`RAW_SHA256SUMS`为本次读取建立的校验清单，不声称存在预先已知图像hash。
- 七项CPU合成测试通过；串行/并行全部指标和四种CSV在合成及真实2帧smoke上逐byte一致。全量使用6个有界CPU worker，保持父进程时域顺序；原始图像不整批加载内存。
- 全量分析约300秒墙钟；性能统计与采集分开，勿用这轮benchmark FPS计算纯NR成本。
- 12张预览按差异最大值选取，属于异常/变化示例，不是随机代表性抽样或盲评。固定热图上限0.1。

## 文件

- 原始数据：`/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/captures/20260909-104246-paired-300`
- 原始hash：`/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/captures/20260909-104246-paired-300/RAW_SHA256SUMS`
- 全量指标：`/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/captures/20260909-104246-paired-300/analysis`
- 对照与差分总览：[contact-sheet.jpg](/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/captures/20260909-104246-paired-300/analysis/contact-sheet.jpg)
- 精确调用配对/粗时间线：`/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/captures/20260909-104246-paired-300/TIMELINE_AUDIT.json`
- 运行与回滚：`/home/user/rt_5090_project/cp2077_nr_lab/20260909-071122-multipass-presr/runs/20260909-104246-paired-300`
- 最后生产哈希/进程复核：[FINAL_RESTORATION.json](FINAL_RESTORATION.json)
- 机器可读摘要：[RESULTS.json](RESULTS.json)

95GiB raw完整保留，未自动删除或另作一份大型复制；未修改其他游戏。

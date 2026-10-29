# NR 社区图像链静态对照 — 2026-09-11

## 结论先行

**不是“CPU 逆向没写完，所以游戏里不够真实”。安装游戏和此前私有实验调用的都是 ORIGINAL signed NVIDIA NR DLL；未完成的 CPU reference 不在游戏渲染链上。** HFMA/RZ reference 修正只能解释 CPU 对照误差，不能解释实际游戏画面的黑、平、假。

**也不能二选一地归为“只差参数”或“换插件就换模型”。** 本次发现了可直接改变相同输入/相同原版模型结果的宿主算法差异：输入颜色域/曝光、不同肩部压缩、输出暗部保护、过滤顺序，以及多层实际 tone 设置。这些比盲调同名 GUI 数字更应优先排查。它们是**静态候选原因，不是已证实的视频差距归因**。抖音作者的确切插件、版本、二进制、场景、链路与有效配置仍 UNKNOWN。

**完整模型逆向仍未完成。** 已有原版参数/资源绑定、部分完整有界算子参考和局部原生数值验证；没有完整同帧 image→所有网络层→temporal history→image 的原版等价重建。应与下面的宿主图像链问题分别立项。

## 1. 版本与证据边界（先定版本，再比较）

路径别名均相对项目根，文件行号从 1 开始：

| 别名 | 精确来源 / 身份 |
|---|---|
| **O** | `reviews/nr-swin-consumer-main-20260911/source`。不是 Git checkout，以源文件 SHA256 定版。`BASELINE_VERIFICATION.json` 核对了 9 个图像链/ABI文件，全部匹配 frozen9e 原始 manifest；包括实际嵌入的 `codec_shaders.inc`。normal reserve 在 `O/native/common/control.h:140–160`，`reserve=max(Budget/10,1 GiB)`，不是 zero-reserve 候选。 |
| frozen / observer | 原 runtime `9e0154fac9d821f9d51a18e7fe163114e12b9f0924e93e7bb724aeb3bf80caaa`；consumer observer `0efd06383925b2e41a9c84d38746317de89ef8907ebb93c03be6858ee58c2690`。该 review 的 `SOURCE_DIFF.json` 是 4 个 observer/test 文件，非视觉实现变更。既有 OFF/ON 五张 RGBA16F 与 frozen 相等只覆盖 POST1 私有两帧，不外推游戏/Present。 |
| 原 NR | 既有绑定报告固定 SHA256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`；本次未运行/修改 DLL，未重新验证安装状态。 |
| **D** | 本目录 `dagherbou/OptiScaler`：`Dagherbou/OptiScaler_DLSSNR` **973761621353b99bee3dc7d4bb27b117fef2644f**。先通过 GitHub commit API 解出提交，再仅取该提交的 5 个文件，并逐一核 Git blob。 |
| **C** | 本目录 `community/OptiScaler`：`wilsjo2/OptiScaler-DLSSNR-PreSR-Multipass` **e237f895623742b761f9e5f00067cb3dc62619f4**，使用项目既存 `wuwa-tutorial-main-20260911/REMOTE_HEAD.txt` 的提交 pin；35 个相关源文件，约 0.82 MB，逐一核 Git tree blob。不是用移动的 main 下结论。 |
| **L** | 本目录 `legacy/OptiScaler`：同一 wilsjo2 仓库 **ec96f42f8d32a4fc82f7c4558c0ed12a9f90d853**。4 个固定提交文件；其中 Dx12.cpp 与现存 `/tmp/nr-presr-static-PgXuk8/optiscaler/...` 字节相同。**L/C 的整个 dlssnr.hlsl 字节相同**，SHA256 `c0aebd916f0cff6a04720bf8111d850e5312e0e7a179c5d8961dc7876d563534`，但 RR 放置规则已经变了。 |
| **F** | 本目录 `feeder/src`：`jlrouzies-fr/DLSS5-Feeder` **76a08db83652617cfe4192eeecf9e46bfc008382**。既存主源与固定提交重新取得的主源逐字相同；补取其 `feed_pq12.h`。 |
| **N** | 本目录 `neural-upstream/src`：`matiasLombo/neural-upstream` **c06c07b27c3c5af0d916c3d9545434735d624bdf**，从现存 checkout 只复制 codec/addon；与 `git show COMMIT:path` 核对相同。 |
| **V** | `reviews/nr-style-enum-audit/sources/DLSS5VKLayer/core/ngx_snippet.cpp`；项目 `COMMITS.txt` pin 为 `bmitch87/DLSS5VKLayer` **0fd9a6a5e19081ae38a77582f1397697212984ee**。该保留源码另与固定提交的 Git tree blob核对相同；只比较参数源，不把另一个 Linux layer/预编译 shader 归给这段 helper。 |

用户指定的 `/tmp/OptiScaler-DLSSNR-src/OptiScaler/dlssnr` **本机已不存在**，无法恢复它当时的精确提交；D 是有记录的固定提交替代对照，**不声称它就是已删除目录或作者版本**。所有 public fetch 仅写本目录，URL/提交/hash 见 `*FETCH.json`。源文件存在不证明发布包实际编译了对应 shader，社区运行二进制/编译 shader/hash 仍须在 A/B 前核对。

另外，旧资料 `renodx-dllmain.cpp` 实际仅为 14 字节 **`404: Not Found`**，绝不能当作 RenoDX 实现证据。`COMMITS.txt` 的 RenoDX pin 是 `cd32113a98608e63027d40910cfe296a14dfe228`，但没有在该证据中得到所称 NR addon。下面引用的 RenoDX-style 数学以 **实际 C/D shader** 为证，不据此断言某 RenoDX 插件版本的完整行为。

## 2. 可行动的原因优先级

**MATCH = 指定路径/条件下机制相同，不是视觉等价；DIFFERENT = 代码可证不同；UNKNOWN = 还缺实测身份/输入。优先级是辨因价值，不是已测影响大小。**

| 优先级 / 项目 | 状态与具体证据 | 最小下一步（仅计划） |
|---|---|---|
| P0 同一模型/同一 seam 身份 | **UNKNOWN** 作者 DLL、Style catalog、实际内核与后处理。O 已是原版模型，不存在“必须先完成 CPU 模型才能真实”的前提。C 还有默认关闭的实验 precision4；见 §6。 | 先固定 NR/SR/RR 二进制、模型资源、宿主提交、调用 seam；拒绝从标题认版本。 |
| P1 输入颜色域与曝光 | **DIFFERENT** O `native/runtime/codec.cpp:34–43` 强制 HDR=1，paperwhite 实际 `max(user,1)`；C `Dx12.cpp:3421–3423` 按 create HDR flag + float format 判域，shader 有 SDR passthrough，曝光可使 divisor 远小于 1（§3）。 | 同一线性 A，导出 shader constants 与编码 B；先比较 B，不扫 Style。若本场景确为线性、white=1，两项条件差异可排除。 |
| P1 压缩曲线 | **DIFFERENT** O encode:36–41 每通道 `5.770780` shoulder；C shader:324–355 是亮度 shoulder `4.0` + peak 全色缩放；D:304–335 同类。不同模型输入与色比，即使 white/strength 一样。 | HDR 灰阶、饱和 RGB、小高光 CPU 探针；固定原 A，分别记录 B 的灰阶/色比/clip。 |
| P1 输出暗部/色域处理 | **DIFFERENT** O decode:88–100、138–144 没有 C 的空模型回退、ratio floor、双侧 ratio guard、近灰 hue 阈值和末端非负 clamp。C shader:957–1109；D:877–1011 对应核心。 | 固定 **同一 A/B/raw NR C**，只换 D compositor。暗像素差异无需新模型即可辨因。不要称 guard 为严格最终 Y 比值限制（§3）。 |
| P1 多层实际控制 | **DIFFERENT** O 对每层重复同一 tone/structure/style/autoMask (`pipeline.cpp:284–290,510–535`)；C/L `PassProfiles.h:47–95` 后续 pass 默认 tone=0，而非继承主 tone；可逐层 override。D `Dx12.cpp:2186–2195` **只有一次 evaluate**，尽管 Config.h:477 尚有 Passes 字段。 | 记录每层实际参数与句柄，而非截图上“Passes=3、Tone=2”；固定每层 tuple 后再比较。 |
| P1 NR/SR/RR 顺序 | **DIFFERENT / 条件 MATCH** O PRE 只允许普通 SR，POST 允许 SR 或 combined RR；D 此 seam 为 POST 单次；L 强制 RR 走 POST，C 已允许普通 PRE-RR 路径且有 residual-across-RR。见 §5。 | 选择相同 PRE-SR 或相同 POST-RR，不拿 POST→缩小→NR 当 PRE-SR。先禁用 residual/deferred/finished-picture 分支。 |
| P2 采样、工作分辨率 | **DIFFERENT / 条件 MATCH** O 此链 proxy=work，不外部缩放 (`pipeline.cpp:389–397`)；encode nearest、decode 神经 RGB先 sRGB decode 再 bilinear。C 先 encode，再 box area 降采样；resolve 在编码域 bilinear 后 decode。C WorkingScale 默认1时缩放差异不触发。 | 对齐 active W/H、work W/H，再用棋盘/细线查 filter footprint；不以 UI“50%”认定分辨率相同。 |
| P2 guide 格式/单位 | **条件 MATCH / DIFFERENT** O 固定 render-size motion、乘 `frame scale * control scale`；C 区分 render/output-size MV，再乘 work/frame ratio (`Guides.h:27–33; Dx12.cpp:2567–2571,2681–2682`)。O normalization 有 SNORM→半精度量化，不是光学 flow 推断。 | 核对 active rect、MV current→previous 符号、单位、jitter-included 与否；同一 raw guide fixture验证，不能只对 MVScale 数字。 |
| P2 history/reset | **MATCH** O/C 多层是持久独立 feature、当前层输出喂下一层，非每层编码/解码；**DIFFERENT** 参数块独立性及重建/reset 条件，见 §4。当前 live history 内容 **UNKNOWN**。 | cold reset 单帧先隔离；再跑同一短序列，逐层身份/计数器/Reset完整匹配。 |
| P2 padding/viewrect | **条件 MATCH / DIFFERENT** O `copy_active:216–234,487–498` 将显式非零基址裁成紧凑 origin0；C `ActiveColor.h:16–34` PRE 不支持非零 Color base，会退 POST，但支持 origin0 padded active staging。 | 同一紧凑 origin0先比；padding 用毒值，active CRC 不应受边缘脏像素影响。 |
| P3 显示域/PQ/额外效果 | **UNKNOWN** 作者 ReShade/RenoDX、LUT、曝光、RT/AO、sharpener、视频 tone-map；**DIFFERENT** 已固定 F 的 PQ bridge 与 O 无 PQ bridge（§6）。 | 先在 NR/SR 边界做线性 tensor 对照，再分别打开显示/后处理；不要用经过压缩的视频量化 raw NR 差异。 |

**本次新增，而非重述旧 HDRTransfer mix：** forced HDR + white 下限；通道 shoulder vs 亮度 shoulder；guard/floor/空模型回退；gamma 域过滤顺序；后续层默认 tone=0；D 已移除 multipass但字段残留；L→C 的 RR 规则变更；F 的 PQ shader 没有色域矩阵；C 的局部肤色保护是外部 heuristic 而非 NGX autoMask。它们都是可以逐项冻结的链路变量。

## 3. 精确 codec 数学

记 `E/D` 为 clamp 到 [0,1] 后的分段 sRGB encode/decode：
`E(x)=12.92x (x≤.0031308), else 1.055*x^(1/2.4)-.055`；
`D(x)=x/12.92 (x≤.04045), else ((x+.055)/1.055)^2.4`。
O 的 ≤ 与 C 的 HLSL step 在恰好阈值的分支约定不同，不能声称 bit-match；一般数学曲线 **MATCH**。不能把 SDR passthrough 当作 sRGB↔linear 转换。

### 3.1 输入

O (`codec.cpp:40–43; codec_encode.comp:19–43`)，`wO=max(userPaperWhite,1)`，`a=max(A.rgb,0)/wO`：

```
K_O(x) = x, x<=.75
       = .75+.25*(1-exp(-5.770780*(x-.75))), otherwise
B = E(K_O(a))  // 逐 RGB 通道；alpha 原样
```

O shader 虽有 HdrMode=0 分支，但 runtime **始终送1**；验证允许 paperwhite .05–16 (`pipeline.cpp:103–104`) 不等于 shader 真吃 .05。`DLSS.Pre.Exposure` 仅在 valid flag 时写 NGX (`pipeline.cpp:282–283`)，**没有进入 O codec 的曝光还原**；也未证明原 NR 一定读取这个 SR 命名的 key。不能将“传了 key”当作已经去 pre-exposure。

C/L (`shader:271–282,324–355,728–775`)：HDR `a=max(A,0)/wC`，默认 mode0：

```
y = dot(a,(.2126,.7152,.0722))
a1 = a * ((.75+.25*(1-exp(-4*(y-.75))))/y) if y>.75 else a
K_C(a) = a1/max(1,max(a1.r,a1.g,a1.b))
B = E(K_C(a))
```

manual `wC` 来自 slider；source1 可为 `clamp(preExposure * clamp(trim,.25,4)/exposure,.01,4096)`；DX12 shader 直接读 live exposure有效值，否则回 CPU whitePoint。source2 是 scan anchor，不能假设 equals game exposure。C 的 Vulkan 编译明确禁用 live t4 exposure 分支，使用 CPU whitePoint (`shader:246–282`)；这也是特定数据路径差异，不是“API 改变模型”。

C/L 模式1/2 的 Neutwo 编码：`m=max(a)`，`a/sqrt(m*m+1)`（m≤1e-6早退）；mode3/4 hybrid 把 peak `m>.75` 的超额 `e=(m-.75)/.25` 映到 `.75+.25*e/sqrt(e*e+1)`，再按 peak 比例统一缩 RGB (`shader:374–462`)。模式2/4 在输出用有上限保护的逆函数**替换**结果，跳过前面 composition/guard/palette 的效果 (`1066–1069`)。这些不是仅换同一转移混合强度。

SDR C 走原数值 `max(A,0)` passthrough，原 whitePoint 不参与该 encode/resolve 正常路径；输入是不是**已经编码**必须由实际内容/颜色空间确定，float format与 HDR flag也不是场景曝光的证明。O 格式桥只是 typed `Load/Store`，没有 PQ/sRGB/709↔2020 变换（`O/adapters/format_bridge/shaders/normalize_hlsl.inc:34–55`）。

CPU纯公式、同一A与white=1的编码反例（不是新GPU结果）：

| A线性RGB | O编码RGB | C/L编码RGB |
|---|---|---|
| (1,1,1) | (.973571,.973571,.973571) | (.958431,.958431,.958431) |
| (4,1,.2) | (1,.973571,.484529) | (1,.537099,.247801) |

第二行说明这不是只在最后混合里多留几成原图：**模型看到的色比已不同**。是否导致目标场景的真实感差距仍要用相同A的原版NR输出确认。

### 3.2 输出（不要遗漏暗部保护）

用 `o=A/w, p=D(B), n=D(rawNR)`，`Y_O=(.212639,.715169,.072192)`、`Y_C=(.2126,.7152,.0722)`。O：

```
r = Yo/Yp                      if Yo<Yp
  = (Yn+max(0,Yo-Yp))/Yn       otherwise, Yn>0
  = 0                         otherwise
u = mix(o, HueO(n*r,n), t)
l = o*(Y(u)/Yo)                if Yo!=0, else o
out = w*mix(l,u,color)
```

`HueO` 用 Oklab hue方向修复，分母仅检查 chroma==0，再硬 clamp AP1负值（O decode:66–100）。没有 model黑值回退，也没有 final max RGB。该旧 `(1-t)A+t*reconstructed` 已在 transfer-mechanism 证明；本次不把它重新包装成新发现。

C composed模式 (`shader:197–222,957–1057`)，先 `Yn<=1e-5` 则 `u=o`；否则同类 two-branch ratio（小分母有保护），`u=mix(o,HueC(n*r,n),saturate(t))`；随后：

```
f=1/512
q=(Y(u)+f)/(Yo+f)
a=pow(max(q,1e-6), 1+max(t-1,0))
g=max(MaxRatio,1)
b=clamp(a,1/g,g)
u2=u*b/max(q,1e-6)
out=w*mix(o*b,u2,min(color,1))
```

`HueC` 对 chroma≤1e-5归零方向，负 gamut 用 D65 neutral-axis 单比例压缩；color>1另扩 Oklab chroma；末端 max RGB≥0。注意：floor 修饰的是 `q`，**color=1 的最终亮度比不严格等于 b**，不能把注释“守住0.5–2倍”当数学保证。CPU纯公式灰色反例 `o=p=.2,n=.01,t=color=1,g=2`：O≈.01；C≈.084477，不是恰好.1。`n=0` 时 O=0、C=.2。只是受控灰色数学反例，未模拟 shader浮点/FP16/原生纹理或断言本场景存在这些像素。

### 3.3 缩放 / 重建

O encode采样 `floor((pixel+.5)*SourceSize/Size)+SourceBase`，不是 area平均；O decode神经分支 `bilerp(D(n00),D(n10),D(n01),D(n11))`，Proxy取nearest（encode:32–35；decode:103–134）。**当前 O pipeline work与proxy同尺寸，因此通常退化为同坐标读取，不能误称游戏当前在做nearest downsample。**

C先全尺寸 encode，再 down-mode2 面积积分：
`Bsmall=Σ Bij*overlap([i,i+1]×[j,j+1],footprint)/footprintArea`；直接平均**编码 B 数值** (`shader:668–724; Dx12.cpp:2454–2469,2484–2548`)。resolve是 `D(bilerp(Bsmall))` 与 `D(bilerp(Nsmall))` (`shader:816–821`)，linear sampler + clamp (`Dx12.cpp:1483–1487`)。它不等于 O 的 `bilerp(D(N))`；例如编码端点0/1的中点分别是 `.214041` vs `.5`。above-native另走可配置 up/down scaler，不能把 Lanczos3设置名当已验证编译核。

C默认 Transfer=1 仅在 raster不同的时候做 matched residual：`Pfull=K_C(o)`；`edit=D(filter(Nsmall))-D(filter(Bsmall))`；`model=Pfull+alpha*edit`，`alpha∈[0,1]` 是使 RGB落unit cube的最大共同因子 (`shader:473–489,910–947`)；之后才走上面的 reconstruction。**不是把低分辨率模型RGB直接放大替换原图。**

## 4. 有效 NGX 控制、每层身份与 history

| 字段 | 对照 / 限制 |
|---|---|
| Intensity / LocalTone / LocalStructure / SkinStructure | **MATCH key，不保证 MATCH value**：O pipeline:284–287 与 C forwarder:876–880；C GUI Menu.cpp:460–463 是这四个字段。后续层 tone默认0（Profiles:51），O每层全同。 |
| “Detail strength” / “Colour strength” | **不是** Intensity/LocalStructure。C Menu.cpp:415–427 实际改 `DlssNrTransferStrength` (0–2)、`DlssNrColourStrength` (0–4)，仅 compositor消费；O传输/color范围都0–1。数字同为1也不能推导同一 field/公式。 |
| Style | O写 signed int，C写 uint，支持0/1/2同一非负值域；C GUI Standard/Natural/Cinematic映0/1/2 (Menu:452–459)。原 DLL静态证明：effective Style夹到catalog count-1后 `/128`，再由模型descriptor gate控制；不是 intensity也不是通过宿主自动换权重。 |
| AutoMask / Skin=-1 | O写 UseAutoMask，未供应 ControlMask；C forwarder:63–68 **显式清空 ControlMask**，避免共享参数块遗留mask，随后写开关。原 DLL reader：若有显式mask则auto=0；auto开启时 skin<0→LocalStructure，否则用skin；auto关则两override=-1。故 skin=-1不等于关auto、也不等于结构强度0。 |
| 原 DLL额外 override | `nr-preblock-binding-20260911/REPORT.md` §2 的 reader→optional provider→effective request链可覆写 tone/structure/intensity/style/auto/skin（VA `0x18001add4..1ae82`）。descriptor gate也影响conditioning。**UNKNOWN**本次两宿主/provider实际状态；参数表ACK/readback不等于生效conditioning。 |
| create vs evaluate | O每层 create先configure (`429–454`)、evaluate再configure (`533–535`)；C也两边写，并在 tuning变更时重建全部相应features (`Dx12:1383–1395,1875–1889`)。社区注释“全部只在create读取”不能覆盖我们原DLL evaluation reader的实证。两边冷建对齐；不要从一个注释假定所有动态控制都死。 |
| UI | O写 UICorrection但本 configure未绑定UI/UIAlpha；C SetExtras普通路径送null UI/backbuffer (`1370–1379,2573`)。传了 UICorrection数字不等于真的给了HUD mask。 |

O有**逐层独立参数块+feature handle**并检查不重用 (`pipeline:437–454`)；C多层独立feature但共享 `capabilityParams`，每次重写field (`Dx12:2666–2696; forwarder:845–881`)。二者都 `B→NR1→NR2…→NRk→一次decode`，同一帧guides复用；不是每层都从A重跑，也不是每层重新HDR压缩。

O reset=`game reset || first layer evaluate || reset generation changed || frame_id gap` (`pipeline:301–304`)；chain按owner、order、SR/RR身份、render/work尺寸冻结 (`697–735`)。C game reset/placement/tuning/recreate重置 (`Dx12:1772–1777,1865–1889,2077,2670`)；额外pass首次有自己的passNeedsReset；不声称两者帧计数/丢帧/reset epochs天然一致。shader注释“没有accumulator”只指普通resolve，不否定原NR内部history或C独立residual shader。

原 DLL已知边界（不是本次新发现）：`nr-preblock-binding-20260911/REPORT.md` T0=Color/Backbuffer、T1=prev_output、T2=MVec、T4=ControlMask；**观察/恢复的frontend路径把T3设为null**，不能把提供的Depth纹理擅自接到T3，也不能全球断言depth无用。`nr-vulkan-sampling-history-20260911/REPORT.md`：Vulkan当前color/MV模式2为normalized nearest clamp，history模式0为normalized linear clamp；RGBA16F prev_output是NR结果history，存在条件compute-copy路由，尚不是完整数值recurrence。不得把这组Vulkan内部sampler推定到C/D的D3D12/NVAPI backend。

## 5. 调用顺序不是 GUI 一个开关能概括

- **O PRE-SR**：原始Color裁紧凑A→codec B→独立NR层→compose D→临时Color输入给**原signed SR**→restore；RR PRE直接拒绝、没有暗中fallback (`native/host/pipeline.cpp:308–313`；`native/runtime/pipeline.cpp:144–160,470,557–559`)。
- **O POST-SR / POST-RR**：原signed reconstruction成功后的output→NR链→compose→commit；RR调用本身可能包含重建与upscale，**不是已证RR→另一次SR→NR**。
- **D pin973761**：`Dx12.cpp:2476–2509` 取upscaler Output的after seam，`2186–2195` 一次NR。残留 `Config.h:467–477` multipass描述/字段不是可执行多层证明。
- **L pinec96**：`Dx12.cpp:2952–2965,3014–3015` RR forcePost、ApplyAfterRR gating。**C pine237**：`3249–3303` 已取消一般RR强制POST；`3305–3325` 可選 NR preRR但保留原Color，再把残差放回RR+SR输出的双seam模式。C普通PRE-RR存在≠它对所有游戏radiance/G-buffer契约安全，也不是对作者流程的证据。
- **C可选 deferred/finished picture** 与普通NR不是同一链 (`Dx12:3157–3232; DlssNr_DeferredSr.inl; DlssNr_Late.inl`)；本任务不扩展证明这些实验模式的全部资源/时序。匹配实验先关掉。
- **N pin c06c**：`addon.cpp:1347–1364,1456–1471` 确实是低分辨率NR→临时Color→原SR→restore，但 codec数学与O/C均不同，见下段。故两个都叫PRE-SR也不能当同一输入输出。

## 6. 其他社区链 / 额外效果

**N codec DIFFERENT** (`codec.hlsl.h:87–118,65–81,123–143`)：HDR mode2除paperwhite；luminance shoulder的系数是 `5.770780*.25/(1-k)`，不是C的4；过饱和pixel部分向亮度去饱和后再saturate。输出核心 `gain=clamp(Yn/Yp,1/8,8)`、`lit=original*gain`，ChromaTransfer可选NR色向；再TransferStrength与EffectStrength混合。其ColorStrength==0被特殊解读为1（第139行），**完全不等于O color=0保留原色的含义**。代码头部的“恢复original/proxy ratio”注释不能代替实际 `Yn/Yp` 运算。cadence/delta复用是另一可选temporal机制，不纳入单帧同一输入比较。

**F PQ桥 DIFFERENT**：`feed_pq12.h:50–69` 是ST.2084：
`p=max(code,0)^(1/78.84375)`；`L=(max(p-.8359375,0)/max(18.8515625-18.6875*p,1e-6))^(1/.1593017578125)`；进入消费者 `L*10000/paperWhiteNits`，返回 `PQ(max(linear,0)*paperWhiteNits/10000)`（encode先saturate到10000nits范围），alpha=1。`dlss5-feed.cpp:3068–3071` 默认有效paperwhite=203nits；`3530–3542` auto依赖PQ BT.2020 swapchain与10bit资源，float不重复桥接。

**新注意点：该 D3D12 shader没有 BT.2020→BT.709 / inverse矩阵，只有逐通道transfer与scale。** 它不是完整“PQ2020↔linear709”桥。若后接C/O的709亮度/色空间数学，还需确认另一个stage是否做gamut变换；否则为实际色域契约差异候选。仅从“PQ bridge”名称不能认为所有HDR链都兼容。

**V参数片段** (`ngx_snippet.cpp:561–614,645–649`) 显式清UI/mask，初始资源设置写MVScale=1、Reset=1，另有NgxSetReset覆写；因此只读setter就宣布“它每帧必reset”也是错误。完整caller/reprojection链未在本任务核清，标 UNKNOWN，不把helper的SDR RGBA8输入当我们PRE线性HDR场景。

**外部肤色保护不同于AutoMask。** C shader:64–72 是warm-color YCbCr椭圆/smoothstep heuristic；1074–1093根据原图mask分别混合亮度与色向，可在全部NR层之后衰减编辑，连replace模式都受影响。O没有这个外部mask。是否开启未知，不能当作者使用的功能。

**RenoDX/ReShade extraeffects UNKNOWN**：可能还有原游戏/插件tone mapper、LUT、AO、曝光/锐化、UI分离与capture色彩管理；没有版本+配置+实际加载列表不能据字幕赋值。本次C shader中的RenoDX attribution是来源说明，不是实际安装了RenoDX的证明；旧404更不是证据。C `Config.h:277` 默认precision=0，`DlssNrNative.cpp:142–148` 仅precision4打开实验hybrid FFN路径。若未来比较该模式，必须标记非原始执行路径并单独核对；本报告正常original-model对照不包含它，亦不认为某宿主会自动“神奇换模型”。

## 7. 模型逆向完成度（与真实游戏因果分开）

**未完成全模型。** 已完成的是精确原版文件pin、host ABI/conditioning/resource绑定、选定Swin/DS/2h等有界CPU算子与部分连接、局部fixture原生数值对照。`nr-swin-consumer-main-20260911/RESULTS.md` 最后明确 full image-to-image仍不完整；`nr-swin2h-reference-20260911/REPORT.md` 还新纠正88字节ABI的 output+8/slab+16，证明“算子看过/边界跑过”不能替代全链认证。

`nr-finalpost-numeric-gap-20260911/REPORT.md` 的Q/K HFMA2修正把那一个 A=B=C=0、单CTA fixture的CPU/native-f32差异从14/256变为0；它**不是全网络、带纹理历史、完整游戏帧的证明**。半精度surface舍入与其它approx/MMA策略仍要区分。还缺完整选定launch DAG、所有层/变体/工作区epoch、全图padding/跨CTA依赖、真实guide/history数值recurrence与冷/热多帧原版对齐。培训数据/损失/所谓3D语义也没有由这些证据复原。

上述reference缺口**不参与现有游戏original DLL计算**，不列入“游戏真实性差”的原因表。反过来，原DLL Evaluate成功/ACK甚至fenced completion也只证明调用/完成，不证明喂对颜色、不证明画面更真实、更不证明与视频视觉等价。

## 8. 最小 SAME-INPUT A/B 证明计划（本次没有执行GPU步骤）

1. **身份门**：固定一个作者无关的可重放输入fixture：源A、MV、Depth、可选mask/UI、曝光及preExposure、flags/jitter、格式/view swizzle、active rect/padding、work raster。记录NR/SR/RR文件hash、宿主commit/实际shaderhash、selected Style/model catalog、每层tuple、provider状态；禁止hybrid/额外effects/FG/cadence/deferred/residual。用户视频无法提供这些则保持UNKNOWN，不替它选版本。
2. **只比codec（CPU可以先做）**：同一A跑O/D/C encode，分别保存B；同一**冻结 A/B/rawNR**跑两种compose，分离输入与输出算法。受控identity NR=B、black NR=0、HDR grey/saturated swatches、checker/padding poison，不称这些合成fixture为视觉质量测试。第一步只检查哪些已证代码差异在目标像素范围真正触发。
3. **最小原版模型测试（未来须另获授权）**：选择相同backend，NORMALRESERVE、原signed NR、单layer、相同有效field，两个独立干净feature，先reset frame。把**同一编码B字节**、相同guides输入两边，记录fenced rawNR输出。只换host、不换input；若不同，查effective args/provider/model selection/format/sampler，而不是直接宣布模型不同。再把O/C各自编码B送同一原版executor，隔离输入codec的因果影响。
4. **仅在第3步身份/单帧通过后**：同一3帧source+guides序列，不自反馈更新A；每层独立feature和相同reset/invocation epoch，先1层再3层。分别对齐后续tone=0及显式逐层tuple；不要把preblock内部invocation counter当全局frame数。保存每层raw output/必要history证据，不能只存最后Present或ACK。
5. **最后才接同一原signed SR/RR与显示后处理**：先同seam、同重建输入/历史，输出线性边界tensor；再固定transfer/color/display EOTF比较Present/截图，额外ReShade/RenoDX一次只开一项。SR/RR无法完整重放时只作NR边界结论，不能声称最终游戏等价。

最小数据包是 `identity.json + effective-fields-per-layer.json + A/B/MV/Depth/exposure + rawNR-per-layer + composedD + reset/sequence/format metadata + fenced-readback receipts`。像素对照分别给exact hash、maxabs/MAE/分位数、暗部/高光与色域clip比例；“相同GUI值”“Get返回正确”“Evaluate=1”均不能代替其中任一项。

## Verification

`python -B reviews/nr-community-chain-diff-20260911/verify.py`：只读hash/源码断言与CPU公式反例，无GPU、Wine、游戏、部署、配置或外部源文件编辑。`VERIFICATION.json` 保存结果；`INPUT_PINS.json` 固定只读输入，`SHA256SUMS` 固定本目录产物。源码算法比较不证明社区发布包shader一致，也未测新场景或实际视觉差距。

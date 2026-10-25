# R610.57.04 GSP 时钟/电压控制逻辑拆解 — 2026-08-16

## 结论先行

这一轮已经把“用户控制进入 GSP 后发生什么”拆成了两条可复核链：

```text
VOLT request
  -> 10 个 16-byte client slot
  -> mode 1/direct 或 mode 2/source 求值
  -> controller base + record delta + per-client delta
  -> client 0..9 最大值仲裁（相等时高 ID 胜）
  -> rail grid 向上量化
  -> min/max clamp
  -> rail apply method

CLK control / propagation control
  -> RM control descriptor
  -> GSP manager 的 BoardObjGrp
  -> state accessor
  -> 通用 BoardObjGrp apply
  -> 每个对象的 +0x30 control importer
  -> 对象态/拓扑态下发到后续 PERF/PMU 路径
```

电压链的整数仲裁与量化已经恢复为可执行模型。时钟链已经恢复 RPC、对象组、accessor、
apply、当前 R610 type-3 U16.16 比率/倒数构造、GB202 R570 明文 PMU 的 type-3
图遍历/乘法/方向性频点归一化，以及同代 clear RM 的 type-5 双端点区间运算。
后续又恢复了 R570 group-`0x0b` 的 V/F 上中位数二分、相邻点复核、多 relation
最小值仲裁、post-selection signed-kHz/Q12 调整与 relation reproject；当前 R610 的
DG0 Q12 scale 已只读闭合为 `0x0800/0x1000`。仍不把跨版本 PMU 代码伪装成 R610
主 ELF handler：当前 adjustment objects、group-`0x11` tuple 状态机和 transition
ordering 继续保持显式未知。

本轮只做文件、ELF 和 Ghidra 工程的静态分析；没有打开 NVIDIA 设备、提交 control、改频率或跑负载。

## 1. 固定分析对象

```text
driver package: 610.57.04
wrapper: /usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin
wrapper SHA-256: c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999

inner ELF wrapper offset: 0x19f040
inner ELF size: 82558976 bytes
inner ELF SHA-256: 88cb25e9940d9b242a8dc518291d028519b1f7b734954c6d358112b4af0a690e
```

持久 Ghidra 工程：

```text
/home/user/rt_5090_project/ghidra_static/gb202_gsp61057.gpr
program: gsp_inner_61057.elf
language: RISCV:LE:64:default
```

必须用 inner ELF 的虚拟地址；不能把 wrapper 文件偏移、ELF RVA 和 GPU runtime VA 混在一起。

### 1.1 同一个 bundle 内存在多个执行边界

主 RISC-V ELF 的 RX/RW load segment 后还有两个嵌套 RISC-V ELF：

```text
file offset 0x1071000: entry 0x1075604
  strings: "GSP vGPU host", "NVIDIA vGPU for Compute",
           "NVIDIA Virtual Compute Server"
file offset 0x1123000: entry 0x10026bc
```

`0x1132000` 开始到文件末尾是 64,528,384-byte 不透明高熵 payload，SHA-256 为
`cace04104b456011e6f80276f84a1eccf446ffc26190650e6c8c0f9ee8ddb0bf`。它的具体容器/
加密语义尚未证明，但已能排除“整个 GSP bundle 只有一个可直接反编译的主 ELF”。

## 2. 当前 GSP 的入口坐标

| 方法 | 命令 | 参数大小 | handler |
|---|---:|---:|---:|
| CLK GET_CONTROL | `0x2080901b` | descriptor-defined | `0x010ddcf0` |
| CLK SET_CONTROL | `0x2080d01c` | descriptor-defined | `0x010f46d8` |
| VOLT RAILS GET_STATUS | `0x2080b202` | descriptor-defined | `0x017e3458` |
| PWR limit arbitration output | `0x2080a620` | descriptor-defined | `0x01798cb0` |
| PWR limit arbitration input | `0x2080a61f` | descriptor-defined | `0x017abf7c` |
| CLK PROP RELS GET_INFO | `0x20809081` | `0x1518` | `0x01148a8c` |
| CLK PROP RELS GET_STATUS | `0x20809082` | `0x004c` | `0x01107108` |
| CLK PROP RELS GET_CONTROL | `0x20809083` | `0x0c18` | `0x01148d3c` |
| CLK PROP RELS SET_CONTROL | `0x2080d084` | `0x0c18` | `0x01113358` |
| CLK FREQ CONTROLLERS GET_STATUS | `0x20809025` | `0x1c14` | `0x01118958` |
| CLK FREQ CONTROLLERS GET_CONTROL | `0x20809027` | `0x1890` | `0x010cb5e4` |
| CLK CLIENT DOMAINS GET_INFO | `0x20809029` | `0x0388` | `0x010cbcf4` |
| CLK CLIENT VF POINTS GET_INFO | `0x2080902a` | `0x0324` | `0x010cbe98` |
| CLK CLIENT VF POINTS GET_STATUS | `0x2080902b` | `0x1810` | `0x010cc03c` |
| CLK CLIENT VF POINTS GET_CONTROL | `0x2080902c` | `0x1014` | `0x010f3f70` |

`0x2080d084` 的 descriptor 位于 `0x01c23870`，flags 为 `0x44`。SET handler 在 feature
检查后调用：

```text
0x01113358
  -> manager + 0x1188
  -> 0x01bd89ac
  -> group + 0x20 accessor, state 0
  -> returned group + 0x28
```

`manager+0x1188` 的 accessor 为 `0x011052d0`，state 0/1 都返回外层对象 `+0x178`。
这个内嵌 BoardObjGrp 由 `0x01ac2860` 构造；其 `+0x28` 明确安装为 `0x01739248`。
`0x01739248` 逐有效对象解析 control record，然后调用该对象 state view 的 `+0x30`。
因此 SET_CONTROL 的实际落点不是一个“直接写 ratio 的单函数”，而是 typed BoardObj 的
逐项 importer。

`0x20809025/0x20809027` 不是目前有证据支持的 per-domain clock-client
candidate/winner 接口。前者经 `ClockManager+0x1328/+0x1348` 的独立对象组进入
STATUS exporter，且受 `ClockManager+0x47a` feature flag 约束；后者从
`ClockManager+0x1148` 的另一内嵌对象进入 control exporter。相同代 MODS 的明确字符串为
`closed loop frequency controllers`、`Enable/Disable all frequency controller(s)` 和
`FREQ CONTROLLER LOAD RPC`。本机零缓冲以及简单 type/mask prefill 的只读 STATUS 均未返回
对象。因此能确认它们属于 frequency-controller 功能面，不能把空记录或对象序号改名为
XBAR/SYS/NVD request candidate/winner；真正 client arbitration 状态仍未知。

`0x20809029/2a/2b` 共用 `ClockManager+0x1168` 下的 client-V/F 对象，分别进入该对象的
`+0x08/+0x38/+0x18` 导出槽；`0x2080902c` 从 `ClockManager+0x1310` 的 control group
导出。`0x902b` 的 `+0x18` 在 embedded-group constructor `0x01ac2860` 中安装为通用
BoardObjGrp serializer `0x01738d64`，其 STATUS entry accessor `+0x68=0x010cc46c`
逐项写入 `output+0x28+index*0x18`；两者都不是选择器。实机只读同步对照没有发现多
candidate/winner 表，而是闭合了 GPC 曲线分层：

```text
main 0x9022 source base
  + 45 MHz current VBIOS/firmware layer
  = client 0x902b STATUS freq1
  + client 0x902c CONTROL frequency offset
  + grid/constraint remainder
  = client 0x902b STATUS freq0
  = main 0x9022 effective frequency
```

125 个主 STATUS 非 sentinel 点的 final frequency 逐点相等；127/127 个 client baseline
都等于 main source-base `+45 MHz`，两个 voltage 字段也 127/127 相等。4 秒 L2 只读判别中，
高端 points 79..126 随 VFE/温度状态变化而 CONTROL offset 不变，early/steady load 相同，
post-load 保留热态。它是动态 curve-composition view，不能据此声称 `freq0` 是某个获胜
candidate 或 `freq1` 是最终 grant。回执：
`clk_client_vf_status_load_probe_20260817.dVz089/`。

真正具备已知 candidate 语义的公共面之一是 `PERF_LIMITS_GET_STATUS_V2`
`0x2080a079`。Phase-9 采样器现在同步保留 ID
`0x41/42/43/46/48/4d/e9/ea` 的 valid/frequency 原值，覆盖已知 GPC 的过压、可靠性、
PMU/热策略候选和 XBAR 的热/功耗策略候选。它们是 bounded candidate observations，
不是完整 binding-winner 集；最终 physical grant 仍由独立测频给出。

随后已对当前 ABI 的全部 ID `0x00..0xff` 做逐 ID、同 RM session 的只读枚举，并用固定
GSP container SHA-256
`c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999`
交叉映射静态 catalog。三次 inventory 均只有 20 个 runtime-valid ID。与频率控制器直接相关
的 catalog/runtime 结果是：

```text
0xd0 PERF_CF_CONTROLLER_DRAM_MIN  valid
0xd1 PERF_CF_CONTROLLER_GPC_MIN   valid
0xd2 PERF_CF_CONTROLLER_NVD_MIN   state-dependent
0xd5 PERF_CF_CONTROLLER_DRAM_MAX  invalid
0xd6 PERF_CF_CONTROLLER_GPC_MAX   invalid
0xd7 PERF_CF_CONTROLLER_NVD_MAX   invalid
0xdb PERF_CF_CONTROLLER_XBAR_MAX  invalid
```

catalog 没有 `PERF_CF_CONTROLLER_SYS_*`；唯一含 `SYS` 的静态名是 runtime-invalid 的
`0x1b SYSPERF`，不能据此虚构 SYS candidate。由此已排除“只是没猜到另一个 PERF-limit
ID”这一分支：SYS 的 phase-local request/winner 必须在别的对象面寻找；NVD 也只有 transient
MIN endpoint，没有 active MAX/winner。

LACT 持久 session 的 6.5 秒同步负载采样中，`d2` 仅 4/53 行有效，值为
`637..697 MHz`，同刻物理 NVD 为 `2234.762..2286.117 MHz`；短生命周期的独立探针进程则
会改变它的可见时段。8/9/10 项 batch 对照一致，排除了数组第十项截断。故 `d0/d1/d2`
只能命名为 state-dependent controller-min endpoint，不是 binding upper winner 或 final
grant。回执：`phase9_perf_limit_inventory_20260817.Rg1EsO/`；可复现 catalog auditor：
`bug_inverse/perf_limits_61057/audit_perf_limit_catalog.py`。

`0x20809062` 则补上了 PERF-limit 没有的四域最终目标面。当前 descriptor 参数尺寸为
`0x288`；payload 是 8-byte header 加最多 32 个 20-byte record，输入 API domain 位于
record `+4`。同代 MODS 的精确日志格式是：

```text
clkDomain=... actualFreq=...KHz targetFreq=...KHz clkSource=... flags=...
```

当前 GPC/XBAR/SYS/NVD (`1/2/4/0x00100000`) 全部只读成功。L2 稳态的
physical/actual/target 分别约为 GPC `3190/3187/3195`、XBAR
`2414/2414/2427`、SYS `2402/2398/2407`、NVD `2276/2286/2299 MHz`；纯
NVENC 的 target 则稳定为 `2580/2317/2302/2197 MHz`。所以 SYS/NVD 的
post-arbitration target 与 actual 已直接可见，不再需要由曲线 envelope 猜测。

该 STATUS 仍不导出同时存在的 pre-arbitration candidates 或 binding client ID；本次所有
四域 `clkSource/flags` 都为 0，不能把 0 改名成 winner。NVIDIA 当前公开 MIT header 另明确
定义 `0x20801037` PMUMON 的 programmed GPC/DRAM/NVD/active-GPC 字段；其 programmed
NVD 与 `0x9062 actual`、直接 NVD 测频在时间延迟范围内互相校验。同步 sampler 已扩展为
79 列，回执：`nvd_sys_workload_matrix_20260817.nyD453/`。

## 3. 电压请求仲裁：当前二进制已闭合的整数算法

### 3.1 控制器布局

恢复到的关键字段：

```text
controller + 0x14a    disabled/enable state
controller + 0x142    source selector/state
controller + 0x144    source selector/state
controller + 0xad8    10-bit active mask
controller + 0xadc    10-bit deferred mask
controller + 0xae0    guard/state
controller + 0xae4    signed controller base offset
controller + 0xae8    10 x signed per-client delta
controller + 0xb10    10 x 16-byte request record
```

request writer `0x0167d028` 验证 `client_id < 10`、`mode < 3`，复制四个 dword，更新
active/deferred mask 后触发仲裁。16-byte record 的已恢复字段为：

```text
+0x00  u8  client_id
+0x04  s32 record_delta_uv
+0x08  u8  mode
+0x09  u8  source_id
+0x0c  s32 direct_uv
```

### 3.2 单请求求值

`0x017ddd74` 的语义：

```text
mode 1: value = direct_uv
mode 2: value = resolve(source_id)    # feature 允许时
active mode 0/其他: error/assert path

if value > 0:
    value += controller_base_uv
    value += record_delta_uv
    value += client_delta_uv[client_id]
if value < 0:
    error/assert path
```

这里的 rail MAX 是 clamp，不是 voltage request；只有 active request record 进入最大值仲裁。

### 3.3 winner 规则

实际 arbiter 入口为 `0x017dead8`，核心扫描区间 `0x017deb48..0x017deba8`：

```text
winner_uv = 0
winner_id = none
for client_id in 0..9:
    if active_mask & (1 << client_id):
        candidate = evaluate(client_id)
        if winner_uv <= candidate:
            winner_uv = candidate
            winner_id = client_id
```

比较是 `<=`，不是 `<`。所以两个 active client 求值完全相同时，后扫描的更高 client ID 胜。

### 3.4 rail grid 与 clamp

`0x017e1cdc` 安装在 rail/device vslot `+0x8b0`，使用：

```text
base = object + 0x908
step = object + 0x90c
minimum = object + 0x874
maximum = object + 0x878
```

对当前正 step 的语义是：相对 base 向上取整到整数 grid，负结果归零，然后依次应用 minimum
和 maximum clamp。apply method 位于 `0x017e8040`（相邻路径 `0x017e7d48` 仍需按具体
rail class 区分）。

### 3.5 公开 rail STATUS 不导出十槽 winner；PMUMON 提供带时间戳的 aggregate 通道

当前 GSP `VOLT_RAILS_GET_STATUS` `0x2080b202` handler `0x017e3458` 通过
controller 内嵌 BoardObjGrp 取得 rail status object，然后调用 object vtable `+8`。
constructor `0x017f7c00` 给基础/派生对象安装 `0x017efc1c` 与 `0x017efe64`；基础路径
进入通用 BoardObj status serializer，派生路径只再补一个 byte。该链不读取
`controller+0xad8/+0xadc/+0xae4/+0xae8/+0xb10`，所以 `0x2080b202` 只能导出
aggregate rail record，不能给出 active/deferred mask、十条 request、evaluated value 或 winner ID。

同一只读 method family 中，`0x2080b216`（size `0x658`，handler `0x017eced8`）
暴露 PMUMON 队列：`0x18`-byte super header 加 `50 * 0x20`-byte sample。将公开
PMUMON retrieval mode `+0x14` 设为 latest 后得到一条 `u64` 纳秒时间戳和六个
`u32` voltage word。当前 build/boot 的成对读取证明 word0 等于 rail0 target、word2
等于 rail1 target；word1/word3 暂不命名，word4/word5 为 `UINT32_MAX`。它改善了
aggregate rail 的时间对齐，但仍不暴露 request-client winner。静态与实机只读回执：
`phase9_voltage_pmumon_probe_20260817.YSxUzm/`。

当前 descriptor table 的整个 retail voltage GET family 也已枚举并逐项实测：

```text
b201 0x098c   b202 0x0ca0   b205 0x0708   b207 0x0188
b209 0x020c   b210 0x0a08   b211 0x0208   b212 0x7a0e0
b213 0x040c   b214 0x14ed8  b216 0x0658   b217 0xff28
b218 0x2404
```

这些尺寸来自当前 R610 descriptor，不从 R570 header 猜。R570 MODS 的方法名 metadata
已经证明该 family 在两版之间发生编号重排，因此当前未由 handler/实测确认的方法只保留
`b2xx` 数字名。live 结果如下：`b201` 返回 mask `0x3` 的两轨 INFO，带该 mask 的
`b202` 返回两轨 aggregate STATUS；`b205/b207` 返回 mask `0xf` 的四个 voltage-device
INFO/派生状态；`b209/b210/b211` 只返回一个对象的公开 INFO/STATUS/CONTROL 字段；
`b212` 返回 version 2、mask `0x1f` 的公开对象组；`b213` 对该 mask 返回
`NV_ERR_INVALID_ARGUMENT (0x25)`；`b217` 只返回 version/object header；`b218` 只返回
一个 feature-present word。

`b214` 的非零记录形状是重复的 raw quantization code / microvolts / valid 三元组，且
handler `0x017d91e8` 进入 generic PMU telemetry copier `0x018151d8`。它既没有
10-bit active/deferred mask，也不是 `10 * 16`-byte request record；禁止把恰好出现的
11 组三元组改名为 request clients。至此当前 retail descriptor 中所有 voltage GET
surface 都已检查，除 aggregate rail/device/policy/telemetry 外没有路径读取
`controller+0xad8/+0xadc/+0xae4/+0xae8/+0xb10`。

这也给出 winner 的信息论不可辨识证书，而不只是“没找到接口”：两个内部状态
`client1=880 mV, client3=870 mV` 与 `client1=870 mV, client3=880 mV` 分别由不同 client
获胜，却产生同一个 `880 mV` aggregate 和同一个 5 mV-grid target。求解器测试
`test_aggregate_target_does_not_identify_the_winning_client` 固定了这个反例。只要没有槽位
dump 或对单个 request writer 的可观测 instrument，任何 aggregate/PMUMON/final-clock
组合都不能唯一恢复 winner ID。

可执行重放器：

```text
power_governor_reverse/bug_inverse/algorithm/gpu_inverse/voltage_arbiter.py
```

它保留 i32 wrap、C 风格截断、mode error、10-bit mask 和 tie-break，而不是用浮点 `max()`
近似。

## 4. 时钟域组、控制组和 propagation 组不是同一个对象

### 4.1 clock domains/status: manager + 0x1148

`0x010ec8ac` 调用 `0x01ac2494`，再由 `0x010ebfa8` 分配 `0x808` bytes 到
`manager+0x1148`。该组：

- accessor holder 在 `+0x20`，静态地址 `0x01e92e90`；
- class/ABI byte 在 `+0x171`；本路径设置 `0x30`，其他硬件变体可为 `0x20/0x31/0x35/0x40/0x50`；
- GET_CONTROL handler `0x010ddcf0` 由 `gpu+0x1f88 -> manager+0x1148` 进入；
- domain row 的 V/F 回调包括 `0x010d5778`（frequency -> voltage）和
  `0x010d5b20`（voltage -> frequency），输出频率乘 `1000`。

class byte 是对象 ABI/变体选择，不应直接重命名成 propagation relation type。

### 4.2 clock program/control: manager + 0x1150

`0x01102b5c` 分配 `0x9b8` bytes，constructor 为 `0x010f939c`，最多容纳 255 个
clock-program object，accessor table
来自 `0x010f1b30`。CLK SET_CONTROL handler `0x010f46d8` 进入这一组；state-1 的
`+0x28` 为 `0x010fae18`，它先调用通用 `0x01739248`，再从 `gpu+0x1f98` 取得
`Perf` 对象并执行直接回调槽 `Perf+0x560`。原始 RISC-V 指令为
`ld a5,0x560(s4); jalr a5`；这不是二级 C++ vtable offset。

当前 R610 的 class-ID dispatch `0x0141f1c0` 已把此前的对象归属错误闭合：

```text
gpu+0x1f88 -> ClockManager (0x00bcadd3, size 0x1bb0, ctor 0x018dc860)
gpu+0x1f98 -> Perf         (0x00ed0b65, size 0x8f1e0, ctor 0x019df2a0)
gpu+0x1fa0 -> KernelPerf   (0x00c53a57)
```

因此精确链是“ClockManager 的 clock-program BoardObj apply → 独立 Perf 对象的
post-apply 回调”，不是 `ClockManager+0x560`。Perf 构造器只直接安装到 `+0x2a8`；
`+0x560` 初始为零，邻接 `+0x568` 是另一个单独分配的 0x68-byte 对象指针，后者不会
回填 `+0x560`。该二阶段安装现已闭合：`Perf::initLocked` `0x0164bb38` 直接调用
`0x016a9f40(pGpu,pPerf)`；原始 CFG 证明 `s2=a1`，`0x016ab146` 将
`0x016abaf4` 写入 `pPerf+0x560` 并置 `pPerf+0x2ed=1`。目标 `0x016abaf4`
是严格的 return-zero stub，所以 SET_CONTROL 后的直接 hook 在当前 R610 构建不执行
求解或提交。精确指令还排除了
两个假命中：`0x01933e5a` 的基址已先加 `0x1000`，实际目的为 `+0x1560`；
`0x0198785c` 则先分配独立的 0x11b8-byte 嵌套对象，其 `+0x560` 不属于 Perf。

同代 GB202-capable R570.151 MODS 给出了更强的语义锚：普通路径 `0x06ee8a00`
和 deferred-load 路径 `0x0724fb21` 都以 `(pGpu, pPerf)` 调用 `0x071cd890`；前者
失败字符串明确为 `NVRM: Perf load failed (0x%08x)`，后者由
`Initiating deferred Perf load` / `Deferred Perf load complete/failed` 包围。
`0x071cd890` 检查 `pPerf+0x366`，启用时向 PMU unit `0x1c` 发请求。因此
`perfLoad(pGpu,pPerf)` 是这个 R570 MODS 函数的证据化命名，但不能直接移植为当前
R610 slot 的函数名。R570.144 GSP 的 `0x010e3d58` 已证明同构链使用
`gpu+0x1c20 -> ClockManager`、`gpu+0x1c30 -> Perf`、`Perf+0x4d8`，相对 R610
的 `+0x560` 恰好移动 `+0x88`。同一 `+0x4d8` 槽同时存在二参数调用和
`(pGpu,pPerf,out_u32,0,mode)` 调用；因此目前能确认的是上下文相关的 Perf
evaluation/application 边界，不能确认每次调用都只是 load，也不证明 R610 使用相同
implementation、PMU unit 或 flags。

GB202 R570.151 MODS 中的相似路径 `0x06dd88b0` 把该版本的第二阶段对象收窄为 `pClk`：它先执行
CLK_DOMAINS BoardObj SET_CONTROL，再经 `0x069acd00` 调度 `pClk+0x5d8`，失败字符串为
`Error loading the PS30 features`。同一二进制中的 PS3.0 异步 worker 若被调用，提交顺序是
Perf → Voltage/VFE voltage PERF_LIMITS → Clock program；但 `pClk+0x5d8` 在 GB202 上是否
选中该 worker 仍缺赋值边，不能当作已闭合的 SET_CONTROL 后继。

R610 的实际工作已迁到注册回调 `0x016aedcc/0x016bcc80`：前者管理
`pPerf+0x318/+0x320` 对象启停，后者执行事件状态机。其 PMU 边界已经精确恢复为：

```text
PERF/type 0x0c: 0x214 bytes
  wire+0x10 <- pPerf+0x34c 的 0x204-byte snapshot
  response+0x2c+0x20*i -> pPerf+0x368+0x20*i

PERF/type 0x0d: 0x54 bytes
  wire+0x50 <- pPerf+0x34c domain mask
  response+0x10+4*i -> pPerf+0x368+0x20*i
```

当前布局实际容纳 16 个域条目；只导入 mask 选中的项。PMU 返回值生成算法仍是边界，
但 R610 slot 地址和 GSP 侧协议不再未知。完整证据见
`GSP_61057_CLK_CONTROL_COMMIT_20260817.md` 与
`GSP_61057_PERF_EVENT_PROTOCOL_20260817.md`。

此前把 `0x0114b758` 当成该 target 是错误的：精确指令 dump 表明它位于
`0x0114a92c` 的函数体/错误分支中，不能作为独立 apply 函数引用。

当前 domain 的 GSP→PMU transfer 边界也已定位。`0x010ee204` 把 GSP object
`+0x148..+0x17f` 映射到 transfer `+0x1c..+0x53`，派生 serializer `0x010ee478`
再追加 object `+0x1a0/+0x1a1`。公开 INFO exporter `0x010f7840` 将 object `+0x160`
作为 `factory_offset_khz` 导出到 record `+0x30`；同一个 object `+0x160` 又由
`0x010ee204` 复制到 PMU transfer `+0x34`。这证明 factory offset 进入 PMU 对象传输，
不是 UI-only metadata。用户 offset 会经过上述 SET_CONTROL/BoardObj apply；紧随其后的
`Perf+0x560` 在当前 R610 是 no-op，后续实际提交由事件回调和 type-0x0c/type-0x0d
交换承接。尚不能把 factory/user offset 或 R570 的任一压缩 adjustment slot 直接互相重命名。精确映射见
`GSP_61057_CLK_DOMAIN_PMU_TRANSFER_20260816.md`。

### 4.3 propagation relation control: manager + 0x1188

`manager+0x1188` 外层对象大小 `0x2a8`；`+0x178` 是内嵌 BoardObjGrp。公开 control
最大 28 个 relationship entry，mapping hooks 包括：

```text
0x01107614  entry map: param3 < 0x1c -> base + param3*0x16 + 9
0x011076a8  secondary map: param3 < 0x1c -> base + (param3+2)*4
0x01107734  path map: param4 < 0x20 -> base + param4*0x30 + 0x10
```

`0x01189954` 从 BIOS/clock table 构建 typed objects 并插入该组；本轮已把 transport
serializer/importer 与 evaluator 分开。`0x110d68c/0x110f8b4/0x11105ec/0x1110cfc`
等函数主要负责 BoardObj 导入导出和记录遍历，不包含 U16.16 乘法本身。

### 4.4 当前 R610 实际 relation 组与 type-3 定点对象: manager + 0x1180

`0x01ac2ea8` 分配 `0xab8` bytes 到 `manager+0x1180`，解析 BIOS relation type 并构建
实际运行对象。type 3 分支构建 `0x70`-byte 对象，安装 `+0x30 = 0x011161dc`，
并写入：

```text
object + 0x60 = ratio_raw              # unsigned U16.16
object + 0x64 = floor(2^32 / ratio_raw)
object + 0x68 = ratio_raw              # mirrored state
object + 0x6c = floor(2^32 / ratio_raw)
```

倒数 helper `0x0111610c` 对零值走 error path，用 RISC-V `divu` 计算
`0x100000000 / ratio_raw`，并拒绝超出 u32 的结果。SET importer `0x011161dc`
使用同一 helper 重算 `+0x64`。因此这部分是当前 R610.57.04 GSP 的位精确
整数算法，不再只是“同代 RM 推断”。

`0xe660` 的精确倒数为 `0x11c79`；`0x10000` 的倒数仍为 `0x10000`。
R610 主 ELF 到这里负责对象构造/下发；频率传播执行点位于 PMU 边界。下面用经 HAL
路径确认属于 GB202 的 R570 明文 PMU 恢复该执行算法。

### 4.5 GB202 R570 PMU：type-3 图遍历、定点乘法与目标域频点归一化

MODS 的 GB202 HAL 路径把 `chipHal=0x3c` 映射到未加密 PMU archive，ELF 位于 MODS
文件偏移 `0x0b9589c0`；精确 archive slice 长度 `0x115c00`、SHA-256：

```text
333d8c4ea22659f65c898579d70806640b7e26357eb6305bd900a807627d2db0
```

它不是按代码形状猜出的“同代候选”：host 和 PMU 使用完全相同的
`CLK_PROP_TOP_RELS` BoardObjGrp 身份：

| 层 | 入口 | group ID | group bytes | transfer object bytes |
|---|---:|---:|---:|---:|
| MODS host constructor | `0x06dfb440` | `0x25d970` | `0x130` | `0x20` |
| GB202 PMU registration | `0x202f52de` | `0x25d970` | `0x130` | `0x20` |

PMU group global 是 `DAT_20010490`。`0x202c49ac` 沿 source/target domain ID 查 relation
edge；`0x202c4ac4` 按 type `3/4/5/7` 分发。type-3 importer `0x202f50ee` 把传输对象
`+0x0c/+0x10` 的两个 dword 写到 PMU object `+0x08/+0x0c`；type-3 evaluator
`0x202c4b30` 的方向语义为：

```text
forward: relation +0x08 ratio_raw,         destination = object +0x05
reverse: relation +0x0c ratio_inverse_raw, destination = object +0x04
```

两条方向都调用 `0x202b4c96(16, freq_mhz, ratio)`。该 helper 的位精确表达式是：

```text
rounded_mhz = (u32(freq_mhz) * u32(ratio_u16_16) + 0x8000) >> 16
```

它使用 64-bit product、显式处理加 bias 的 carry，并拒绝结果超出 u32。因此舍入是
nearest/half-up，不是 floor。判别例：`3000 * 0xe660` 的精确有理数是
`2699.70703125`，PMU 中间整数为 `2700 MHz`；`1 * 0x8000` 为 `1 MHz`，而
`1 * 0x7fff` 为 `0 MHz`。

乘法后还没有结束。`0x202c4b30` 立即以目标 domain 调用 `0x202c353c`，经
`0x202c3e6e -> 0x202c4f8e -> 0x202c5d8a -> 0x202c2e72` 按 domain mask
从 `DAT_ram_20010358` 找到目标域对应的 frequency-grid 对象，
再由 `0x202c2d2a/0x202c2e00` 映射到该域实际可表示的频点。对象参数位于：

```text
+0x05  u8  divider scale S
+0x0a  u16 frequency numerator A
+0x0c  u16 frequency denominator D
+0x30  u8  direct-unit flag; zero 时内部使用 2*f + direction
B = S * D
representable(d) = floor(A * d / B)     # flag=0 时结果再 /2
```

方向决定不等式：forward 选择不高于输入的最大可表示频点，reverse 选择不低于输入的
最小可表示频点。反例网格 `A=3,B=2` 对输入 5 MHz 给出 forward `4`、reverse `6`。
所以完整的 type-3 传播是：

```text
edge lookup -> ratio/inverse select -> U16.16 half-up -> destination frequency-grid down/up normalize
```

这直接增加了“最初选择值为何不是实际值”的固件级原因：即使 ratio 乘积已经确定，目标
domain 仍会把它投影到自身 divider grid。数字孪生已位精确实现乘法和参数化域归一化。
当前 R610 的未约分 `S/A/D/+0x30` 仍无 PMU heap readback；但下文的当前
GSP-to-PMU serializer 字段桥与 live list 已把主域有效比率固定为 15/2，足以在当前
频率范围唯一复现 divider/readback。模型明确把算法体标为 R570 cross-build，不把约分
表示冒充原始 heap 字段。

这里实际有两组对象，不能仅凭 serializer 形状合并语义：

- relation evaluator 查找目标 domain row 的 group 是 `DAT_ram_20010360`。PMU
  `0x202cf7c8` 用 group ID `0x273bf0`、header `0x30`、transfer object `0x20`
  注册；当前提取的 R570 MODS（SHA-256
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`）中，
  host routine `0x072f2a30` 在 `0x072f2b4c` 注册同一 identity/ABI。这闭合了真正的
  clock-domain group。
- divider-grid 参数由 `DAT_ram_20010358` 的另一组对象提供。PMU `0x202f630a`
  注册 group ID `0x7bfb0`、header `0x30`、transfer object `0x40`；importer
  `0x202f74d2` 把 transfer `+0x04/+0x05/+0x08/+0x0a/+0x0c/+0x10`
  分别写入 internal `+0x04/+0x05/+0x06/+0x0a/+0x0c/+0x14`，并把
  `+0x22/+0x23/+0x24/+0x25/+0x20` 写入
  `+0x07/+0x08/+0x09/+0x30/+0x2e`。其中 internal `+0x14` 是 evaluator
  使用的 domain mask，`+0x05/+0x0a/+0x0c/+0x30` 是上述 grid 参数。

当前 R610 的发送端也已逐字段闭合。GSP `0x0112d0ac` 把 clock-table row
`+0x21/+0x22/+0x24/+0x3e` 写到 0x40-byte PMU transfer
`+0x05/+0x0a/+0x0c/+0x25`；这与 R570 `0x202f74d2` 的接收位置一一相同。当前主域
live list 的有效 15/2 可分别表示成 direct `A=15,B=2` 或 doubled-input
`A=15,B=1`；对 0..3999 MHz 每个整数请求的穷举比较均得到相同 divider 和逆算频率，
所以原始因式分解未知不再阻塞主域物理量化输出。

原先把 group `0x76cf0`、host `0x06e684f0`/serializer `0x0735bba0`、PMU importer
`0x202f7832` 接到 normalizer 上，是由相似结构造成的错误语义连接，现已从 PROVED
移除。负对照也已确定：R610 serializer `0x01132234` 的唯一构造调用链起于
`0x012f1d7c`，函数内直接引用 `RmFan2XOverride` 并解析 BIOS `+0x3dc`，所以它属于
Fan 2.x，不是时钟域或 power-sense。结构同形本身不能给 subsystem 定名。

当前 R610 另有一个不依赖私有 PMU heap 的观测面：只读 `CLK_DOMAIN_GET_INFO`
导出了全部九个域的支持频率集合。列表算法也已沿静态 handler 闭合：

```text
0x20809019 -> 0x010ddb58 -> domain+0x98 -> 0x010e0830
  -> inclusive clock-program range -> program+0x68 -> 0x010f4dac
  -> mode 2 clock-table row+0x78 -> 0x0112feac
```

`0x010f4dac` 支持 mode 0 线性 step、mode 1 单 endpoint、mode 2 divider-row
委托。mode 2 最终枚举 inclusive divider interval，并逐点计算：

```text
floor(row.u16_22 * divider / (row.u8_21 * row.u16_24))
```

再按两个 scale flag 选择可选 x2/div2。前一频率到 lower divider 的转换还包含
`(frequency+1)` 的不对称整数边界，不是普通浮点四舍五入。对 live GPC/XBAR 列表，
最简有效比率 `15/2`、`divider=2..466` 精确重放全部 465 点；但 row 原始三字段尚未
live-read，因此只能确定约分后的比率，不能排除等价的成比例字段。五个主域均零误差满足：

```text
frequency[i] = 15 + floor(i * 15 / 2) MHz
GPC/XBAR: count=465, max=3495
SYS:      count=439, max=3300
NVD/PWR:  count=459, max=3450
```

相邻差因此严格交替为 7/8 MHz。其余离散表为 MCLK
`405,810,7001,13801,15001`，PCIE `1..5`，API40
`675,900,1026,1080,1188,1296,1350,1620`，API08 `540,675,810,1080`。
当前 `0x180`-byte domain INFO serializer `0x010f7840` 还把对象
`+0x150..+0x168` 精确导出到 record `+0x20..+0x38`。完整 readback、字段表和复现命令见
`GSP_61057_CLK_DOMAIN_READBACK_20260816.md`。

静态 descriptor 把 list handler 挂在 `0x20809019`，但本机公开 RM endpoint 实际由
`0x2080901a` 返回列表；sentinel prefill 已证明公开布局只消费 index，并只覆盖
`u16 count + u32[count]`。这里只记录已观察到的 public/static 语义对调；精确转换层仍未知。

公开列表证明“当前固件宣布哪些整数 MHz 点”，但尚未证明所有最终仲裁路径都以它作为
最后一级量化器。数字孪生已把九张表做成可查询的 floor/ceil bracket，并在 trace 中输出；
默认仍标成 diagnostic-only，不用缺失的因果边冒充完整闭环。

同一 GB202 R570 PMU 的候选搜索器 `0x202a817e` 还给出了 GPC raw target 到提交 target
之间的精确非对称 Q12 tracker。对象 `+0xe0/+0xe2` 分别是 U16
`clkUpScale/clkDownScale`：

```text
up:   old + round_half_up((new-old) * clkUpScale   / 4096)
down: old - round_half_up((old-new) * clkDownScale / 4096)
```

实现使用 `mulw`，再把 product bit 11 加到 `product >> 12`。某方向 scale 为 0 时跳过
平滑并直接保留 raw `new`，不是把频率冻结在 `old`。数字孪生已按这一分支和位宽执行；
当前 R610 两个 scale 的活值也已通过只读 `0x2080a61a` 闭合。当前 GSP status getter
`0x017a0d38` 将 combined-policy 对象 `+0x390/+0x392` 两个 U16 分别导出到每条
status record `+0x16/+0x18`；配对 getter/setter `0x017a09c8/0x017a171c` 对同一字段
执行双向复制。旧 MODS 的同类 printer 则直接把这两个连续 U16 命名为
`clkUpScale/clkDownScale`。本机 policy 0、10、16 各重复读取三次均为：

```text
clkUpScale   = 0x0800 = 2048 = 0.5 Q12
clkDownScale = 0x1000 = 4096 = 1.0 Q12
```

所以当前 boot 的单次 tracker 更新可具体化为“上升走一半差值、下降一步接受 raw target”，
均保留上述 half-up 规则。完整地址与 readback 证据见
`GSP_61057_Q12_SCALE_READBACK_20260816.md`。这不自动排除调度器外层另有 dwell/hysteresis。

### 4.6 type-5 共享电压区间语义

同代 clear RM 中的 core `0x6999860` 给出可执行顺序：

```text
source [Fmin_kHz, Fmax_kHz]
  -> [floor(Fmin/1000), ceil(Fmax/1000)] MHz
  -> source FREQ_TO_VOLT(Vmin, Vmax)
  -> target VOLT_TO_FREQ(Fmin, Fmax)
  -> min(max(endpoint, allowed_min), allowed_max)  # 两个端点分别执行
  -> ordinary target domain * 1000 back to kHz
```

`0x6996cf0` 负责 source frequency range -> voltage range，`0x69994b0` 负责 voltage
range -> target frequency range，`0x6998050` 对两个端点分别 clamp。当前 R610 的私有
object 字段和 callback 插值细节还未全部命名，但数字孪生已按这一区间顺序执行，
不再只用单个 MAX 标量代替整个 type-5 relation。

### 4.7 V/F relation 搜索、关系仲裁与 post-selection 改写

GB202 R570 PMU 把 VF relation 注册为 CLK group `0x0b`，identity/ABI 为
`0x2610b0 / 0x30 / 0x80`，与同代 host 精确相同。点求值链
`0x202c5b28 -> 0x202c5c76` 返回 `{u16 MHz, u32 voltage}`。
`0x202c52d2` 的 frequency→voltage 和 `0x202c50a4` 的 voltage→frequency 均使用
`mid=(lo+hi+1)>>1` 的上中位数二分，并在边界求值相邻点；前者取 ceiling 点，后者取
floor 点。secondary bank 的 point index 由 `0x202bba02` 按
`primary-primary_lower+secondary_lower` 映射。

relation range walker `0x202c3c4e/0x202c3d5e` 将内部 `0x41` 解释为已命中边界并转成
成功。`0x202c40f6` 让所有活动 relation 从同一输入独立生成 clamp candidate，取最小值，
相等时后扫描 relation 胜；`0x202c3fbe` 汇总 terminal upper bound 同样取最小，但相等
时保留先扫描者。

初选后的另一层 `0x202c2c28` 支持 signed-kHz/1000 或 signed-Q12 调整，随后窄化为
s16 并把负值 clamp 到 0。`0x202c4786` 遍历活动域，每次调整相对循环原始输入发生变化
时，调用 `0x202c3e6e` 重新投影 through VF relations。位精确模块分别位于：

```text
algorithm/gpu_inverse/vf_relation_search.py
algorithm/gpu_inverse/relation_arbitration.py
algorithm/gpu_inverse/domain_adjustment.py
```

当前 R610 adjustment group flags/object values 未 readback，所以默认 trace 明确显示
`not_applied_missing_current_r610_objects`，不代入猜值。完整逐地址证据见
`R570_PMU_VF_RELATION_SEARCH_20260816.md` 与
`R570_PMU_DOMAIN_ADJUSTMENT_20260816.md`。

## 5. 当前 topology 对“XBAR 相同结果”和“GPC 最终不同”的解释层

既有本机只读快照（不等同于本轮/当前 boot）记录了活动 top ID 7、关系 mask `0x3ff`：

```text
relation 0: GPC -> XBAR, type 3, bidirectional
ratio_raw: 0x0000e660
ratio: 58976 / 65536 = 0.89990234375

relations 1..9: type 5 shared-rail relationships
XBAR/SYS/NVD and additional domains are connected behind relation 0
```

因此必须区分：

```text
最初 GPC candidate
  -> DG0/filter
  -> client/PERF max/min
  -> type-3 U16.16 half-up propagation
  -> destination-domain directional frequency normalization
  -> type-5 shared-rail range conversion
  -> V/F ceiling and clock grid
  -> measured GPC/XBAR/SYS
```

两个 XBAR offset 如果都先超过同一个 type-3 source ceiling，或最后落入同一个 rail/VF/grid
可行点，就会产生相同 XBAR 输出；它们的 request、winner client 或共享 rail headroom 仍可能不同。
同理，功率搜索器最初选择的 GPC 只是上游 candidate，后续限制或量化可以让实际 GPC 不同。

当前数字孪生已经为每个域输出 ordered `decision_certificate`：每个候选上限的 before/after、
是否实际改变输出、`winner_chain` 与最后一个 decisive constraint 都单独保存。PTX 实测边界的
判别结果是：

```text
XBAR +330/+360/+390/+420:
  ratio ceiling 3000 MHz 后仍被 MSVDD 1065 mV V/F ceiling 压到
  2902/2932/2962/2992 MHz，因此 decisive = msvdd_vf_voltage_ceiling

XBAR +430/+440:
  V/F ceiling 已升到 3002/3012 MHz，高于 ratio ceiling 3000 MHz，
  因此 decisive = gpc_to_xbar_ratio_ceiling，两个 offset 同为 3000 MHz
```

前四点对 compute 实测均值的绝对误差分别为 `1.370/0.922/0.626/0.052 MHz`。
`+430` 的采样均值 2991.430 MHz 低于静态包络，而 `+440` 为 3000.092 MHz；这保留为
负载中 source/DG0/power/sampling 的动态差异，不用隐藏常数强行拟合。可复放证书为
`algorithm/artifacts/ptx_xbar_boundary_certificate_20260816.json`。

GPC 示例同样形成完整证书：`3330` 候选先被 `user_gpc_max` 限到 `2992`，再由
`clock_grid_quantization` 物化成 `2985 MHz`。这不再把“选择值”“readback”“实频”混成
一个字段。

当前 top ID 7 的 `domainsDstPath` 也已成为可执行图配置：GPC→XBAR 路径为 `[0]`，
GPC→SYS 为 `[0,1]`，GPC→NVD 为 `[0,2]`；XBAR→PCIE 为 `[4,3]`，先反向经过
MCLK/XBAR type-5，再正向经过 MCLK/PCIE type-5。路径 walker 复现 PMU `0x202c49ac`
的 `current,target -> next relation -> next domain` 循环并检测断路/环路。

## 6. 已证明、推断、未知

### PROVED（当前 R610.57.04 GSP）

- 上述 RPC descriptor/handler 坐标；
- 电压 10-slot record、active/deferred mask、mode 1/2、三个 signed offset、最大值循环和 tie-break；
- rail 整数量化再 clamp；
- CLK domains、CLK control、propagation control 是不同 manager object；
- propagation SET_CONTROL 经 `0x01bd89ac -> 0x01739248 -> object+0x30`；
- `manager+0x1180` 的当前 type-3 对象字段、`0x0111610c` 倒数 helper 与 `0x011161dc` SET importer；
- power-policy status getter `0x017a0d38` 的 U16 `object+0x390/+0x392 -> record+0x16/+0x18`
  映射，以及配对 control getter/setter `0x017a09c8/0x017a171c`；
- `CLK_DOMAIN_GET_INFO` 九个域的完整频率列表；五个主时钟域精确满足
  `15+floor(i*15/2)`，相邻步长 7/8 MHz 且零 mismatch；
- 频率列表的 domain program-range walker、clock-program mode 0/1/2 dispatcher、mode-2
  divider interval 与逐点整数公式；live 主域列表确定最简有效比率 `15/2`；
- CLK domain INFO serializer `0x010f7840` 的 `object+0x150.. -> record+0x20..` 字段映射；
- GPC/XBAR V/F 双向回调和 typed clock-domain object construction 存在。
- `Perf::initLocked -> 0x016a9f40` 的第二阶段安装、`pPerf+0x560` 精确写点以及
  `0x016abaf4` return-zero target；
- 注册回调 `0x016aedcc/0x016bcc80`、type-0x0c/type-0x0d 精确 wire layout、
  16-domain masked result import 与 GSP-side active/valid 状态字段。

### PROVED（既有本机只读 runtime 快照）

- 活动 topology 7、relation 0 的 GPC/XBAR、type 3、bidirectional、`0xe660/65536`；
- relations 1..9 为活动 type-5 shared-rail relationships；
- GPC 采用 NVVDD bank，XBAR/SYS/NVD 采用 MSVDD bank；
- 当前四个 127-point STATUS bank 和 MCLK 五点 frequency-indexed bank。
- policy 0/10/16 的 `clkUpScale=0x0800`、`clkDownScale=0x1000`，三轮只读结果一致。

### PROVED（GB202 R570 明文 PMU，跨版本边界明确）

- host/PMU `CLK_PROP_TOP_RELS` 的 `0x25d970` identity、`0x130/0x20` ABI 对应；
- `0x202c49ac` relation graph walk 与 `0x202c4ac4` type `3/4/5/7` dispatcher；
- type-3 的 ratio/inverse 方向选择、`0x202b4c96` U16.16 half-up 乘法；
- 乘积继续进入目标域对应的 frequency-grid 对象，forward 向下、reverse 向上归一化到可表示频点；
- 真正 clock-domain group `DAT_ram_20010360` 的 host/PMU group ID `0x273bf0`、
  `0x30/0x20` ABI 对应；
- frequency-grid group `DAT_ram_20010358` 的 PMU group ID `0x7bfb0`、`0x30/0x40`
  ABI、importer `0x202f74d2` 的逐字段映射，以及 evaluator 按 domain mask 查找该对象；
- R610 `0x01132234` 链由 `RmFan2XOverride` 字符串和 BIOS `+0x3dc` 解析路径证明为
  Fan 2.x，是防止结构同形误归类的负对照；
- `0x202a817e` 的非对称 U16-Q12 candidate tracker、half-up 与 zero-scale bypass 分支。
- VF relation group `0x0b` 的 `0x2610b0 / 0x30 / 0x80` identity、V/F point 输出布局、
  双向上中位数搜索、相邻点与 cross-bank point-index 映射；
- relation-range `0/0x41` traversal、独立 candidate 最小值/terminal-bound 最小值及不同
  equal tie-break；
- post-selection signed-kHz/Q12 调整的逐指令算术、双 object 选择和 active-domain
  relation-reprojection walk。

### PARAMETERIZED / INFERRED

- 数字孪生当前 topology 把 type-3 用作 downstream XBAR ceiling；PMU evaluator 的双向算术
  已恢复，但不同 limit kind 如何选择遍历方向仍未全部恢复；
- 当前静态 arbiter core 按每个 configured rail 实例化，但物理 rail 到具体 controller class 的
  当前 boot 对象映射尚无 live heap readback；
- GPC client 1、XBAR client 3 来自同代静态映射，不是当前 boot slot dump。
- type-5 双端点 F->V->F 顺序与独立 clamp 来自同代 clear RM，不把当前
  R610 私有 callback 细节伪装成已恢复。

### UNKNOWN

- 当前 boot 两轨各自 active/deferred mask、10 条 request record、base 和 per-client delta；
- R610 type-0x0c/type-0x0d 返回值的 PMU 生成算法、逐域 32-bit word 语义，以及 R570 capability branch 的运行时选择；
- R610 PMU 是否逐指令保持 R570 GB202 type-3 evaluator，以及当前 boot 各 frequency-grid
  对象的 `S/A/D/+0x30`；
- 当前公开 `CLK_DOMAIN_GET_INFO` 支持集合是否是每条最终 clock-arbitration 路径的最后量化器；
- 公开 `0x20809019/0x2080901a` 到静态 handlers 的精确转换层，以及 live clock-table row
  未约分的原始 numerator/denominator fields；
- Q12 tracker 外层是否另有 dwell/hysteresis；
- 当前 R610 type-5 完整私有字段、callback 插值细节和 transition ordering；
- 当前 R610 group `0x11` 的 VFE tuple sampling/filter/product rounding 和边界状态机；
- 当前 R610 post-selection adjustment group flags、active mask、primary/secondary object
  type/value；
- P-state/context-switch/reset 期间的对象残留和重放顺序。

## 7. 可复现入口

```bash
# 电压整数模型测试
cd /home/user/rt_5090_project/power_governor_reverse/bug_inverse/algorithm
PYTHONPATH=. python -m unittest tests.test_voltage_arbiter -v

# 完整离线模型测试
PYTHONPATH=. python -m unittest discover -s tests -v

# 静态 handler decompile 已保存
less /home/user/rt_5090_project/power_governor_reverse/gsp61057_handlers_20260816.c

# 精确指令范围 dumper（绕开错误的函数边界）
less /home/user/rt_5090_project/power_governor_reverse/ghidra_scripts/DumpInstructionRanges.java

# GB202 R570 PMU 持久反汇编（上述地址均可直接检索）
less /home/user/rt_5090_project/power_governor_reverse/gb202_r570_clear_pmu.objdump.txt
```

当前 algorithm suite、collector parser/runtime 与 catalog suite 均由下述最新回归覆盖；
精确计数见本轮验证结果，不再保留早期 `48 tests` 的过期数字。

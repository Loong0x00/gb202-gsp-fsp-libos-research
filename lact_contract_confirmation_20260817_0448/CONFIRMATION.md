# LACT Blackwell 多域控制契约确认

日期：2026-08-17（Asia/Singapore）

本记录只确认开发接口语义。当前确认过程中没有执行 GPU control SET：用户的《鸣潮》进程正在持续满载运行，新的写入实验会把应用负载状态与控制变量耦合；现有同一驱动/VBIOS 环境下的单变量 SET/GET/STATUS/恢复原始数据已经能够区分待确认假设。

## 当前契约指纹

| 项目 | 当前值 |
|---|---|
| GPU | NVIDIA GeForce RTX 5090, `10de:2b85`, GPU UUID `GPU-43fc92f5-ea03-4a4f-ef51-3e346d97c8dc` |
| 驱动 | `610.57.04` |
| VBIOS version | `98.02.2E.80.50` |
| live PCI ROM BAR SHA-256 | `f9a4bcf866c216f633ca322d14ff9de02e8238aeee93ebe7de0a20ab9c5f77cf` |
| live ROM size | 524288 bytes |
| `libnvidia-api.so.1` SHA-256 | `fea6a0090bbdca9b294682b34a8808e1a4e3f6613f9b6684b412893d5047cef8` |
| GSP SHA-256 | `c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999` |
| CLK_DOMAINS GET/SET | `0x2080901b/0x2080d01c`, size `0x83c` |
| CLK_VF_POINTS INFO/STATUS/GET/SET | `0x20809021/22/23/0x2080d024`, sizes `0x8208/0x98208/0x1020c/0x1020c` |

PCI ROM sysfs 的顺序读取在本机只返回第一页，因此使用 128 次显式 4096-byte offset read 组成完整 512 KiB 映像。两次独立读取逐字节一致。该值是当前 live ROM BAR fingerprint；不得用只含版本字符串的查询替代。

当前 boot 的 CLK_DOMAINS masks 均为 `0xff`。GPC、XBAR、SYS、NVD frequency offset 和已知 rail-offset 槽位均为零；活动 GPC→XBAR ratio 为 raw `0x0000e660`，即 `0.89990234375`。当前 boot 无 Xid、GSP timeout、GPU-lost 或 reset-required 记录。

## 结论 1：XBAR/SYS frequency offset 是域级控制，不是 P-State offset

当前结构中每个时钟域只有一个 control record：

```text
record = 0x3c + domain_index * 0x40
record + 0x0c = signed frequency offset in kHz
```

保存的 SYS A/B STATUS 原始 dump 被重新解析。提交 `SYS +15 MHz` 后：

| bank | effective frequency delta | total frequency offset delta | points |
|---|---:|---:|---:|
| GPC | 0 MHz | 0 kHz | 127/127 |
| XBAR | 0 MHz | 0 kHz | 127/127 |
| SYS | +15 MHz | +15000 kHz | 127/127 |
| NVD | 0 MHz | 0 kHz | 127/127 |

因此 LACT 的 XBAR/SYS slider 应建模成各自的 domain-wide offset。它不应复用现有 GPC P0/P8 map，也不应把值复制进 127 个 point-offset control 字段。

## 结论 2：已确认的是 per-domain MSVDD request，不是 native global rail offset

`CLK_DOMAINS` 每个 domain record 的已验证电压字段为：

```text
record + 0x10 + rail_index * 4 = signed per-domain rail offset in uV
```

历史八格 rail×domain A/B CSV 被重新逐点计算。每次只请求 `+1000 uV`：

| 请求 | 被 STATUS 采用的 bank | 结果 |
|---|---|---|
| GPC × rail 0 | GPC | 127/127 点 effective/source 与 total offset 均 +1000 uV |
| GPC × rail 1 | 无 | 无 STATUS adoption |
| XBAR × rail 0 | 无 | 无 STATUS adoption |
| XBAR × rail 1 | XBAR | 127/127 点 +1000 uV |
| SYS × rail 0 | 无 | 无 STATUS adoption |
| SYS × rail 1 | SYS | 127/127 点 +1000 uV |
| NVD × rail 0 | 无 | 无 STATUS adoption |
| NVD × rail 1 | NVD | 127/127 点 +1000 uV |

这确认了逻辑映射：

```text
GPC  -> rail 0 / NVVDD
XBAR -> rail 1 / MSVDD
SYS  -> rail 1 / MSVDD
NVD  -> rail 1 / MSVDD
```

R610.57.04 的 native global-rail offset 字段仍未确认。因此简单 UI 中的一根“MSVDD offset”滑块必须明确实现为复合操作：在同一个完整 `0x83c` read-modify-write 中，把 XBAR/SYS/NVD 三个 rail-1 槽位设置为相同 offset。权威配置仍保存三个 per-domain 值；三值不同时，简单滑块显示 `Mixed`，不得伪造一个全局值。

这是驱动可见的逻辑 voltage request。aggregate MSVDD target 由独立 rail STATUS 读取；public sensed 字段在本机为零，物理/observed voltage 必须保留为另一数据源。任何 readback 都不得写成外部 VRM VOUT 的直接证明。

## 结论 3：propagation 与本地 XBAR 请求是竞争约束

已保存的 PTX sweep 和数字孪生重新测试支持以下静态上包络：

```text
propagated_candidate = normalize_domain(GPC_source * ratio)
local_curve_candidate = F_xbar(MSVDD) + XBAR_domain_offset + XBAR_point_offset

XBAR_static_upper_envelope
    = min(propagated_candidate, local_curve_candidate, other_known_limits)
```

在 GPC source 3000 MHz、ratio 1.0、MSVDD max 1065 mV 的测试矩阵中，XBAR `+330/+360/+390/+420 MHz` 的物理均值与 local V/F ceiling 模型误差不超过 1.5 MHz；到 `+430/+440 MHz` 后 decisive constraint 变成 GPC→XBAR ratio ceiling。`+440` 不再产生 `3000 + 440` 一类的线性叠加结果。

本轮重新运行数字孪生完整测试：92/92 通过，其中测试直接读取六份原始 `hardware-clocks.csv` 复算，不只验证手写摘要。

该公式只可显示为 constraint candidates/static envelope。最终 effective curve 与 physical clock 仍必须来自 STATUS 和独立测频；功耗、温度、grid、其他 relation 和 rail arbitration 可进一步降低结果。

## 曲线网格

当前四个 runtime bank 均为 127 点，XBAR/SYS/NVD 的 source-voltage 序列在本次读回中逐点相同，范围 450000..1240000 uV。但 flat index 分别为 `127..253`、`259..385`、`386..512`，并不相同。

所以 UI 可以按 voltage 叠加三根曲线；控制写入仍必须使用 `(domain, native point index)`。未来构建若 voltage grid 不同，不得按数组下标对齐或写回插值点。

## 仍未知但不阻塞只读 UI

- native global MSVDD offset 字段：未确认，当前不暴露。
- NVD 物理消费者与 correctness workload：未确认，frequency setter 保持实验性。
- public rail STATUS 的 sensed 字段：当前为零，不能视作物理 VOUT。
- 所有约束之后的唯一闭式最终频率公式：不存在已确认的单一公式，使用 readback。

## 原始证据

- 本目录的两份 live ROM BAR dump、四个当前 127-point CSV、当前 CLK_DOMAINS control 与 policy snapshot。
- 本目录的 `sys-domain-offset-baseline-status.txt`
- 本目录的 `sys-domain-offset-plus15-status.txt`
- 本目录的 `sys-domain-offset-control.txt`
- `/home/user/rt_5090_project/domain_rail_probe_20260816/`
- `/home/user/rt_5090_project/power_governor_reverse/bug_inverse/algorithm/artifacts/ptx_xbar_boundary_certificate_20260816.json`
- `/home/user/rt_5090_project/ptx_xbar_stress/RESULTS_20260816.md`

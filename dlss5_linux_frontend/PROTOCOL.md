# D5LC 通用实时控制协议 v1

控制器和游戏后端通过游戏可执行文件同目录下的 `.dlss5-linux/` 交换固定长度二进制块：

- 输入：`live-control.bin`
- 后端回执：`live-status.bin`

两者均为 little-endian、`#pragma pack(1)`、72 字节。控制器必须先写同目录临时文件，再用 rename 原子替换。后端只接受完整、版本正确、校验正确且数值在范围内的块；无效或缺失输入必须保留后端默认行为。

| 偏移 | 类型 | 字段 | 范围/说明 |
|---:|---|---|---|
| 0 | `uint32` | magic | `0x434c3544`，磁盘字节 `D5LC` |
| 4 | `uint16` | version | `1` |
| 6 | `uint16` | size | `72` |
| 8 | `uint64` | sequence | 每次提交改变；回执原样返回 |
| 16 | `uint8` | neural_uplift | 0=Feature18 关闭并透明直通，1=开启 |
| 17 | `uint8` | enable_upscaling | 0/1 |
| 18 | `uint8` | auto_mask | 0/1 |
| 19 | `uint8` | ui_correction | 0/1 |
| 20 | `uint32` | preset | 0..3 |
| 24 | `uint32` | style | 0..1 |
| 28 | `uint32` | depth_mode | 0..2 |
| 32 | `float` | intensity | 0..2 |
| 36 | `float` | local_tone | 0..2 |
| 40 | `float` | local_structure | 0..2 |
| 44 | `float` | skin_structure | -1..2 |
| 48 | `float` | motion_scale_x | -2..2 |
| 52 | `float` | motion_scale_y | -2..2 |
| 56 | `float` | paper_white_scale | 0.05..16 |
| 60 | `float` | transfer_strength | 0..1 |
| 64 | `float` | color_strength | 0..1 |
| 68 | `uint32` | checksum | 前 68 字节的 FNV-1a 32-bit |

## 后端行为要求

1. 在 Evaluate 路径中低频轮询（参考 20 Hz），不要在渲染线程执行阻塞 IPC。
2. 应用有效块后，将**实际钳制/应用后的完整块**写入 `live-status.bin`，并保留输入 sequence。
3. `neural_uplift: 1→0` 不得改变原生 DLSS Evaluate 返回值或输出。
4. `neural_uplift: 0→1` 必须触发一次 temporal reset。
5. 后端自己的安全/阶段 gate 优先于控制器；回执代表“参数已读取”，运行状态应由额外遥测扩展表达，不能绕过 fail-closed gate。
6. 不得用该协议替换或修改 NVIDIA 签名 DLL。

当前控制器对未知扩展采取版本不匹配即拒绝策略。排序/层数使用下面的独立 D5RP 文件，**D5LC v1 的 72 字节布局保持不变**。

## D5RP v1：NR 顺序与独立层（独立协议）

只有实际存在 `dlss5-native-runtime.dll`/native host 且
`.dlss5-linux/pipeline-capabilities.json` 通过严格校验时，管理器才会写
`.dlss5-linux/pipeline-control.bin`。仅有 `nvngx_dlssnr.dll`、旧 Post
Service、Vulkan Bridge 或 RenoDX 并不构成 D5RP 能力，也不会由管理器生成
能力文件。

请求为 little-endian `<IHHQIIII`、固定 32 字节：

| 偏移 | 类型 | 字段 | 范围/说明 |
|---:|---|---|---|
| 0 | `uint32` | magic | `0x50523544`，磁盘字节 `D5RP` |
| 4 | `uint16` | version | `1` |
| 6 | `uint16` | size | `32` |
| 8 | `uint64` | sequence | 非零，每次明确应用更新 |
| 16 | `uint32` | order | 0=`post`（SR/RR→NR），1=`pre_sr`（NR→普通 SR） |
| 20 | `uint32` | passes | 1..10 次真正独立 NR evaluation |
| 24 | `uint32` | reserved | 必须为 0 |
| 28 | `uint32` | checksum | 前 28 字节 FNV-1a 32-bit |

管理器使用同目录临时文件、flush/fsync 和 rename 原子替换。长度、版本、
sequence、顺序、层数、reserved 或 checksum 任一无效都故障关闭。请求缺失时
后端默认 `post/1`；D5LC 的总开关为 0 时，D5RP 不能开启 NR。

静态能力文件（最大 16 KiB）schema 为 `d5rp-capabilities/v1`，必须声明
`backend: dlss5-native`、协议 1、受支持顺序、`max_nr_passes`、
`requires_restart: true` 和 `pre_sr_requires_feature1: true`。旧后端的配置仍可
保存，但管理器不会写不受支持的 D5RP 请求。

运行状态 `.dlss5-linux/pipeline-status.json`（最大 16 KiB）schema 为
`d5rp-status/v1`。管理器只信任 5 秒内的 heartbeat、有效 PID/session 上下文、
与当前请求相同的 sequence、requested_order 和 requested_passes。`active` 还
必须使 effective 顺序/层数与请求完全相同；D5LC 回执本身绝不确认 D5RP。
状态明确区分 `active`、`pending_restart`、`unsupported`、`gate_closed`、
`budget_exceeded`、`disabled` 和 `error`。缺失、过期、损坏或不匹配都只显示
“未确认/故障关闭”，不会标成已应用。

顺序和层数在 v1 初始后端中是进程冷启动锁存项。新请求可报告
`pending_restart`。新鲜状态为 RR 时，管理器禁用/拒绝 `pre_sr`，不会自动
更改游戏的 RR 设置；后端同样必须以 `unsupported` 和 NR bypass 拒绝该组合。

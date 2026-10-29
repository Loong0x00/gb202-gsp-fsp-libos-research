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

当前控制器对未知扩展采取版本不匹配即拒绝策略。未来状态/能力协商应增加新版本或独立文件，不能改变 v1 的 72 字节布局。

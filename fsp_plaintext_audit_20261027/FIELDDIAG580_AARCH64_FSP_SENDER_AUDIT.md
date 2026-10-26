# DGX Spark FieldDiag 580 AArch64 FSP sender 与调用者静态审计

## 范围与方法

只读检查 FieldDiag 2.0.4 中的 AArch64 MODS ELF：

`external_dgx_spark_fielddiag/v2.0.4/dgx/tests/mods.580/fieldiag`

ELF SHA-256：`383147f07018911fe55537dd7a35eced01ac9c4b65873dc55dd634fe35483b48`。它是 AArch64 ELF64 `ET_EXEC`。未运行 ELF、未发送 FSP 命令、未操作 GPU/硬件；使用 `readelf`、`strings`、`llvm-objdump` 和只读 Python 指令扫描。

 sender VA `0x10e80c54` 由 FuseRework 调用处 `0x10ce9e00` 确认。随后按 `.text` 的 ELF VA `0x10009280`、文件偏移 `0x0fdf9280`、长度 `0x0a758aa0` 扫描全部四字节对齐的 AArch64 `BL imm26`，反算目标地址；结果与现有 `fieldiag580_all_fsp_sender_callers.asm` 一致。FuseRework 调用链还参照同目录的 `fieldiag580_fuserework_flow.asm`。本报告仅新增，不改其他报告或样本。

## 结论

- sender `0x10e80c54` 有 **7 个直接 BL 调用点**；没有发现 570.215 直接调用清单以外的新调用形态。7 个点分别是 7-byte 小型状态查询、FuseRework `0x0f`、2-byte 内部 `0x0c` wrapper、一个 12-byte telemetry 响应和三个 24-byte telemetry 响应。
- 最大请求是 FuseRework **`0x346`（838）字节**，但它由固定认证侧文件和 FuseRework 状态字段组成；响应解析严格要求 4-byte `0x0000000f` ACK。不是 bulk decrypt-to-host。
- 没有 sender 调用者接收 `0x29400–0x37000` 级响应，也没有调用点把大明文响应解释为 FSP/GFW 镜像。未发现新的 v6 crypto descriptor 消费者或新的 `NON_FSP` decrypt wrapper。
- ELF 确有可变长度的本机软件 AES-GCM decrypt helper；其输入/输出由普通调用者对象提供，结构与已知 MODS 570.215 软件 decrypt 路径相符。静态证据没有把它连到 FSP sender、`FSP_RUN` descriptor 或 FuseRework 输入。
- sender 内有 transport vtable 的 `blr` 间接分派；这是 sender 下层传输回调，不是另一个上层 sender/decrypt API。未找到通过函数地址常量或 direct-branch alias 间接进入 `0x10e80c54` 的证据（限制见“间接调用”）。

## 直接 BL 调用清单

“响应大小”按调用者实际检查/消费描述；若未强制精确长度则单独标明。所有尺寸均为字节。

| BL callsite | 命令 | 请求 | 响应 | 用途/判断 |
|---:|---:|---:|---:|---|
| `0x10345868` | `0x82` | 7 | 消费首个 4-byte word；调用者不做精确总长度比较 | 小型 feature/status bit 查询 |
| `0x10ce9e00` | `0x0f` | `0x346` = 838 | **精确 4**，word 必须为 `0x0000000f` | 已确认 FuseRework |
| `0x10e80d5c` | `0x0c` | 2 | **精确 4**，然后取前 16 bits | sender 内部两字节请求 wrapper |
| `0x1150de9c` | `0x0e` | 14 | **精确 12** | telemetry/clock-style |
| `0x1159a3f4` | `0x0e` | 22 | **精确 24** | telemetry/clock-style |
| `0x115a4a30` | `0x0e` | 22 | **精确 24** | telemetry/clock-style |
| `0x115a4da8` | `0x0e` | 22 | **精确 24** | telemetry/clock-style；复用本函数前面构造的同一 22-byte 请求向量 |

### 请求/响应的汇编依据

#### `0x10345868`：小型 `0x82` 查询

调用前先分配 7-byte vector（`0x103457e0–0x103457f8` 设置 begin/end/capacity）。`0x10345840–0x10345864` 设置 `x5=sp+0x80` 响应 vector、`x3=sp+0x60` 请求 vector、`w2=0xffffffff`、`w1=0xffffff82`，随后在 `0x10345868` BL。

请求字节由 `w21` 分支选择：

- 非零：`52 52 4c 01 00 0c 24`（`RRL`、16-bit `1`、16-bit `0x240c`）；
- 零：`45 43 43 01 00 e8 5b`（`ECC`、16-bit `1`、16-bit `0x5be8`）。

响应路径 `0x103458fc–0x10345918` 从响应 begin 指针 `ldr w3,[x0]` 读取一个 32-bit 状态 word，并按输入状态选择 bit 值 `1` 或 `2` 写回 bool；此调用者未比较响应 vector 的精确长度。因此表中记为“消费首个 4-byte word”，不把动态响应对象误报成强制 4-byte 总长。

#### `0x10ce9e00`：FuseRework `0x0f`

`0x10ce9c90` 起为已确认 FuseRework 执行路径。请求在 `sp+0x50` 构造：

| 请求偏移 | 长度 | 汇编来源/内容 |
|---:|---:|---|
| `0x000` | 2 | `[sp+0x28]`：对象字段 selector（`0x10ce9cf4` 的 `ldrh`） |
| `0x002` | 2 | `0x0348`（`mov w7,#0x348`；`strh` 到 `[sp+0x30]`） |
| `0x004` | 8 | 对象 `+0x20` 的 opaque qword |
| `0x00c` | `0x30` | `fuserework_debug_gfw_hash.bin`，精确读 48 bytes |
| `0x03c` | `0x180` | `fuserework_debug_gfw_pub_key.bin`，精确读 384 bytes |
| `0x1bc` | `0x180` | `fuserework_debug_gfw_sig.bin`，精确读 384 bytes |
| `0x33c` | 8 | 对象 `+0x30` 的 opaque qword |
| `0x344` | 2 | staged transfer 长度的低 16 bits |

追加证据：`0x10ce89a0` 是范围追加 helper；调用点 `0x10ce9d1c/0x10ce9d30/0x10ce9d44` 依次追加前 2、2、8 bytes；`0x10ce9d48/0x10ce9d88/0x10ce9da0` 分别读取并追加 48/384/384-byte sidecar；`0x10ce9db8` 追加第二个 qword，`0x10ce9dcc` 追加最后 2 bytes。总计 `2+2+8+48+384+384+8+2 = 0x346`。因此嵌入的 `0x0348` 字段不是所见 vector 的实际字节数（相差 2 bytes）。

调用参数在 `0x10ce9de0–0x10ce9e00`：`w1=0x0f`、`w2=0xffffffff`、`x3=sp+0x50` 请求 vector、`x5=sp+0x70` 响应 vector。`0x10ce9780` 的解析器先检查响应长度等于 4，再检查 32-bit word 的高 16 bits 为零、低 16 bits 为 `0x0f`；因此大请求只换回 ACK。

#### `0x10e80d5c`：内部 `0x0c` 两字节 wrapper

`0x10e80ce0` 从输入 word 取低/高 byte（`0x10e80d04 ubfx ... #8,#8`），在 `0x10e80d0c/0x10e80d10` 写入 `[sp+0x3e, sp+0x3f]`，形成 2-byte 请求；`w2=2`、`w1=0x0c`，`x3=sp+0x40`，`x5=sp+0x60` 后于 `0x10e80d5c` 调用 sender。返回后 `0x10e80da0–0x10e80db4` 检查响应长度恰为 4，并读取其低 16 bits 存入输出。不是大响应接口。

#### `0x1150de9c`：`0x0e` / 12-byte 回复

请求 vector 位于 `sp+0x80`。`0x1150dd70–0x1150de78` 通过重复调用 `0x115043b0` 追加共 14 bytes：首 byte `0x03`、3 个零 byte、一个 64-bit 值 `x20`（小端）、再 2 个零 byte。`0x1150de7c–0x1150de9c` 设置 `w1=0x0e`、`w2=1` 和响应 vector `sp+0xa0`。`0x1150deb0–0x1150deb8` 比较响应长度与 `0x0c`，只接受 12 bytes。

#### `0x1159a3f4`：`0x0e` / 24-byte 回复

请求在 `sp+0x70` 构造，按 `0x1159a1e0–0x1159a394` 的追加序列共 22 bytes：1 个动态类型 byte、3 个零 byte、8-byte `x23`、8-byte `x20`、2 个零 byte。`0x1159a3e0–0x1159a3f4` 设置 `w1=0x0e`、`w2=1`，`x3=x25` 请求、`x5=x22` 响应。`0x1159a400–0x1159a408` 精确比较响应长度 `0x18`。

#### `0x115a4a30` 与 `0x115a4da8`：同一 `0x0e` / 22-byte 请求

`0x115a49b0–0x115a49e4` 为请求分配 `0x16` bytes，并把 vector end/capacity 设为 begin+`0x16`；`0x115a49e8` 调用初始化 helper，`0x115a49f8–0x115a4a00` 设置首 byte。第一处调用 `0x115a4a30` 的参数为 `w1=0x0e`、`w2=1`、`x3=sp+0x90`、`x5=sp+0xb0`；`0x115a4a7c–0x115a4a84` 精确检查 24-byte 回复。另一条分支在 `0x115a4d90–0x115a4da8` 以相同 `x23=sp+0x90` 请求 vector 再发一次 `0x0e`；`0x115a4db0–0x115a4db8` 同样只接受 24-byte 回复。

## 与 bulk decrypt / descriptor / NON_FSP 路径的关系

### FSP sender 调用者没有大明文回传

全部七个 sender callsite 的 response 由小状态 word、4-byte ACK 或 12/24-byte telemetry 结构消费。FuseRework 虽有 838-byte 请求，其 response 明确只接受 `0x0f` 的四字节 ACK。未见大响应 vector、复制到 `0x29400–0x37000` 级 buffer、或把该响应保存为 FSP/GFW 镜像的 caller。

### Crypto descriptor 错误名不是 descriptor 消费者

ELF 中有 `UNSUPPORTED_CRYPTO_STRUCT_DESC_V1_VERSION`、`KDF_CONFIG_ERROR`、`AES_256_GCM_DECRYPTION_ERROR` 等错误名；这些字符串的可见 AArch64 引用落在返回字符串指针的短 accessor 区域（例如 `0x107b65a8`、`0x107b6b3c`、`0x107b6da0`），而不是解析/传输函数。仅有错误名不能证明 FieldDiag 580 对 v6 `FSP_RUN` descriptor 做了解析或解密。

### `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED` 是错误名 accessor

字符串位于 VA `0xfb20b10`。可见的直接 materialization 在 `0x107b6524–0x107b652c`：

```asm
107b6524: adrp x0, 0xfb20000
107b6528: add  x0, x0, #0xb10
107b652c: ret
```

此处只返回静态错误名字符串；没有 decrypt、FSP send、dev-fuse 判定或 policy bypass 的指令证据。它与错误码/名称映射一致，不是一个可调用的 NON_FSP 解密 wrapper。

### 已知本机软件 AES-GCM helper 仍存在，但未连到 FSP

另见本地软件 decrypt helper（分析标签）`0x1104f220`。它从调用者结构 `+0x44` 复制 32-byte key（`0x1104f34c–0x1104f35c`），用 12-byte IV、零 AAD 和 16-byte tag 调用本机 GCM helper（`0x1104f368–0x1104f398`），成功时按输入长度把输出复制到调用者 output object（`0x1104f3ac–0x1104f3b8`）。失败路径在 `0x1104f418` 记录 `SwDecrypt(), gcm_crypt_and_tag() failed`，并于 `0x1104f42c–0x1104f430` 返回 `0xf0`。`0x1104f580` 是一个受 mode byte 控制的内部入口调用此 helper，另一个直接调用在 `0x1104fd4c`。

这说明 MODS 有一般用途的本机软件 GCM 处理；它可能按调用者长度处理数据，但这不是本次发现的新 FSP bulk wrapper。helper 的 key/IV/tag/output 都来自其显式本机对象；本次未找到这些对象来自 sender response、v6 descriptor 或 `FSP_RUN` 的数据流。570.215 已有软件 decrypt 路径记录（`V6_CRYPTO_KDF_CONSUMER_AUDIT.md`），所以不能把它重新标作 580 新发现的 FSP 解密接口。

## 间接调用判断与边界

- 全 `.text` 精确解码 `BL imm26` 到 `0x10e80c54` 得到上表全部 7 处；未发现 direct `B` alias 到此地址。
- 对 `.text` 扫描未发现把 `0x10e80c54` 直接物化的 `ADR` / `ADRP+ADD` 指令；ELF 文件内无该 VA 的绝对 qword 命中，`.rela.dyn` 中也无指向该 VA 的 relocation addend/offset。
- sender 自身确有间接 transport dispatch。例如 `0x10e80c98–0x10e80cc0` 从 `context+0x90` 取 transport vtable slot `+0x30` 后 `blr x19`；sender 其他分支也从 transport vtable 取目标并 `blr x28`。这是 sender **调用下层传输接口**的证据，不是 sender 被间接调用的证据。
- 以上排除了可见的直接指针/分支别名路径，但不是对所有运行时函数指针传播或外部回调注册的形式化证明。没有证据支持另有间接上层调用者；同时不据此断言隐藏 FSP 固件中不存在 decrypt 服务。

## 可复核检查

- `file`、`readelf -h/-SW`：确认 AArch64 ELF64、`ET_EXEC` 与 `.text` 范围。
- `sha256sum`：样本哈希为上述值。
- `llvm-objdump -d --start-address=... --stop-address=...`：复核各 callsite、FuseRework builder/sender、sender transport dispatch 与软件 GCM helper。
- 对 `.text` raw instruction 的 BL/B immediate、ADR/ADRP+ADD 目标扫描，以及全文件 sender qword/relocation 检查：复核直接与静态间接线索数量。
- `find_aarch64_string_refs.py`、`strings -a -t x`：复核 NON_FSP、crypto descriptor 和软件 decrypt diagnostic 的静态字符串引用。

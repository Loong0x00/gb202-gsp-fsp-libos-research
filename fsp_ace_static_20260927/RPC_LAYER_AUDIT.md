# GSP-RM RPC 分发层（E3）纯静态审计

## 范围与结论

- 目标：本机 610.57 GSP-RM RX 镜像 `power_governor_reverse/gsp61057_rx_full.bin`，基址 `0x01000000`；仅静态反汇编/数据及源码结构交叉核对。遵循 `notes/CONTEXT_BRIEF.md` 的只读要求；未加载驱动、未触碰 GPU、未执行固件、未联网，未改 `parallel/`。
- 接收/分发：`0x1016104` 有调用点 `0x1a92356`（另有 `0x1a8b3d4`）。分发器 `0x1a92054` 取消息指针后在 `0x1a92144` 执行 `lw s10,0xc(s8)`，即从 payload `+0xc` 取 function ID。`0x1a92158–0x1a92170` 以 16-byte 步长遍历 18 项表并比较 ID；`0x1a92230–0x1a9223c` 按索引取相应 64-bit handler 指针并间接调用。`0x1a9927c–0x1a9928c` 将接收缓冲区的 end-start 字节跨度写到分发上下文 `+0x30`，handler 会用该值作实际消息可用长度检查。
- **未确认新的越界写或任意写。** 发现 3 个宿主可控长度/计数未与实际数据覆盖范围充分关联的 B 级风险：`GPU_EXEC_REG_OPS`、`IDLE_CHANNELS`、`SET_REGISTRY`。前两者还会据未充分约束的 count 做动态栈分配；栈边界/任务栈大小未能从本轮静态证据确定，因此不将栈破坏写成 A 级既成事实。`SET_REGISTRY` 可构造越过声明表长度的条目读取，但尚未证明其造成越界写。
- `GSP_RM_CONTROL` 与 `GSP_RM_ALLOC` 的外层可变参数长度均可见到“实际接收长度 ≥ 参数长度 + 固定头”检查；这只证明 RPC 封套，**不代表所有 RM control command 的下游回调均安全**。

## Function → handler 表

表地址为 `0x1e14190`，按 `<u32 ID, u32 aux, u64 handler>` 解码；共有 18 个有效项，ID 遍历上限由 `0x1a92162` 的 `li a3,0x12` 明确给出。`aux` 的语义未确认，故不作解释。名称/ID 与本地 610.43.03 参照树 `src/nvidia/inc/kernel/vgpu/rpc_global_enums.h` 对照；行为结论以 610.57 二进制为准。

| RPC ID | 名称 | aux | handler VA |
|---:|---|---:|---:|
| `0x4c` (76) | `GSP_RM_CONTROL` | 6 | `0x1a8b84c` |
| `0x67` (103) | `GSP_RM_ALLOC` | 5 | `0x1a8b08c` |
| `0x0a` (10) | `FREE` | 1 | `0x1a670e8` |
| `0x04` (4) | `ALLOC_MEMORY` | 4 | `0x1a8b58c` |
| `0x32` (50) | `GPU_EXEC_REG_OPS` | 1 | `0x1a8a7f0` |
| `0x15` (21) | `DUP_OBJECT` | 1 | `0x1a7747c` |
| `0x16` (22) | `IDLE_CHANNELS` | 4 | `0x1a91e90` |
| `0x4e` (78) | `DUMP_PROTOBUF_COMPONENT` | 5 | `0x1a8abc8` |
| `0xca` (202) | `ECC_NOTIFIER_WRITE_ACK` | 2 | `0x1a776a0` |
| `0x36` (54) | `SET_PAGE_DIRECTORY` | 0 | `0x1a66f34` |
| `0x4f` (79) | `UNSET_PAGE_DIRECTORY` | 0 | `0x1a67014` |
| `0x46` (70) | `UPDATE_BAR_PDE` | 0 | `0x1a67180` |
| `0x41` (65) | `GET_GSP_STATIC_INFO` | 1 | `0x1a66ea0` |
| `0x01` (1) | `SET_GUEST_SYSTEM_INFO` | 1 | `0x1a7759c` |
| `0x2f` (47) | `UNLOADING_GUEST_DRIVER` | 2 | `0x1a8a110` |
| `0xe4` (228) | `INIT_GSP_TRACE_CRASH_BUFFER` | 1 | `0x1a8a39c` |
| `0x48` (72) | `GSP_SET_SYSTEM_INFO` | 2 | `0x1a8a680` |
| `0x49` (73) | `SET_REGISTRY` | 6 | `0x1a961f4` |

## 高风险证据链

### F-1 — `GPU_EXEC_REG_OPS`：count 未绑定消息长度；count 驱动栈分配及逐项读/拷贝（B）

本地参照结构 `g_sdk-structures.h` 中 `NV2080_CTRL_GPU_EXEC_REG_OPS_PARAMS` 的 `regOpCount` 位于 payload `+0x3c`，`regOps` 从 `+0x58` 开始；每个 `NV2080_CTRL_GPU_REG_OP` 为 32 bytes（该结构字段合计 32 bytes）。固件与布局吻合：

1. `0x1a8a83e–0x1a8a846` 只检查消息长度字段 `>0x57`，然后从 `0x3c(s3)` 读 count；未见 `0x58 + 32*count <= 实际消息长度` 检查。
2. `0x1a8a852–0x1a8a85e` 计算 `count*32` 并构造数组末端 `t3 = payload+0x58+count*32`。`0x1a8a874–0x1a8a90e` 按 32-byte 步长读取每项（含 `lbu 1(s1)`），只检查操作码/类型范围，迭代到 `t3`；循环前没有把 `t3` 与消息 end 比较。
3. 通过上述循环后，`0x1a8a912–0x1a8a91a` 再执行 `sub sp,sp,a0`，其中 `a0=count*32`；`0x1a8a92c–0x1a8a98c` 将每个 32-byte 操作从输入数组拷到该动态栈区域。没有可见的 count 上限或栈容量检查。

因此，`length=0x58,count=1` 已满足固定头长度检查，却要求读取 `payload+0x58..0x77` 的 32-byte 操作；这是越过 RPC 声明/接收长度的读取。若使用接近 64-KiB staging 上限的有效数组，count 可令动态栈分配接近 64 KiB；是否越过本任务栈的已映射边界，需取得该任务栈大小/边界后定级。**已证实的是消息边界未校验与 count 驱动的动态栈分配；本轮未证明固定栈对象被越界写或发生返回地址覆盖。**

### F-2 — `IDLE_CHANNELS`：把“字节长度”当“条目数”校验，随后按 12-byte stride 读（B）

参照 `g_rpc-structures.h`：头部有 `nchannels`，随后是 `idle_channel_list`，每项含 3 个 `NvU32`（12 bytes）。固件证据：

1. `0x1a91ebc` 从请求 `+0x28` 读取 `nchannels`；`0x1a91ec6–0x1a91ed6` 用 `mulhu` 检查 `count*12` 的算术溢出。
2. `0x1a91ef6–0x1a91f00` 要求请求长度字段 `>0x2b`，然后仅执行 `bltu actual_len,count`（`actual_len` 是分发上下文 `+0x30` 的字节跨度）。这里比较的是“字节数 ≥ 条目数”，不是“字节数 ≥ 固定头 0x2c + 12*条目数”。
3. `0x1a91f08–0x1a91f28` 将 count 换算为每个数组的 `round_up(count*4,16)`，连续三次减 `sp` 分别建立 client/device/channel 数组。接着 `0x1a91f2c–0x1a91f58` 从 `payload+0x2c` 按 12-byte 步长读 3 个 dword，并写入三个数组。

可复核的边界反例：实际消息长 `0x2c`（44 bytes）、`nchannels=1` 时，固定长度 `>0x2b` 成立，`44 >= 1` 也成立，但条目应占用 `[0x2c,0x38)`，12 bytes 全在声明消息之后；复制循环仍会执行。count 同时直接影响三段动态栈分配；按 staging 上限 64 KiB，校验允许 count 最高至字节长度量级，未见任务栈容量限制。这里确证的是越界源读取和未限栈分配；没有静态栈边界证据，故不声称已证明越界写入相邻对象。

正常宿主驱动参照 `rpc.c` 的 `IDLE_CHANNELS_MAX_ENTRIES_v03_00` 会用 `maxRpcSize` 限制条目数后再写消息；这只是可信发送端行为，不构成固件面对恶意宿主报文的校验。

### F-3 — `SET_REGISTRY`：声明表 size 与 numEntries 未交叉校验（B）

参照 `g_os_nvoc.h`：`PACKED_REGISTRY_TABLE` 为 `{size,numEntries,entries[]}`，`PACKED_REGISTRY_ENTRY` 含 `nameOffset/type/data/length`，条目 16 bytes。固件证据：

1. `0x1a9622e–0x1a96250` 读表 `size`，做 `size+0x20`，检查消息长度以及 `actual_len >= size+0x20`。
2. `0x1a96254–0x1a9625a` 随后独立读取 `numEntries`；`0x1a96272–0x1a9627c` 按 `index*16` 寻址并读取每条记录的 type/length 等字段；`0x1a9632e–0x1a96330` 以 `numEntries` 为循环上界。未见 `numEntries*16 <= size-8` 或等价的乘法/剩余长度检查。
3. 类型分支会用记录中的 offset、length 做后续解析/复制（例如 `0x1a96314–0x1a96320` 形成 `offset+table_base`，字符串/二进制分支继续取用长度）。未发现这些 offset/length 均受 `size` 约束的证据。

边界反例：表头 `size=8,numEntries=1`，RPC 总长 `0x28`（40 bytes）时，`size+0x20` 检查恰好通过；但第一个条目应从表头后开始，固件仍根据 `numEntries` 读取该条目的字段，读取已越过消息尾部。这里确定有表头声明与计数脱节及越界读取路径，**尚未证明其写入目的地小于所复制长度**；不据此宣称堆溢出。正常驱动 `osPackageRegistry` 会一致地产生 `size/numEntries`，恶意宿主可绕过该序列化器。

## 18 个 handler 的指令级检查摘要

| ID / handler | 长度/计数与写入审计 | 结论 |
|---|---|---|
| 76 `GSP_RM_CONTROL` `0x1a8b84c` | `0x1a8b888–0x1a8b892` 读 `paramsSize` 并加 `0x48`；`0x1a8b8e2–0x1a8b8f0` 检查消息最小长度及 `actual_len >= paramsSize+0x48`。params 从 `+0x48` 起。 | RPC 封套长度检查存在；RM control 下游 command callbacks 未全覆盖。 |
| 103 `GSP_RM_ALLOC` `0x1a8b08c` | `0x1a8b0bc–0x1a8b112` 读 `paramsSize`、加 `0x40`，并检查最小消息长度和 `actual_len >= paramsSize+0x40`；参数从 `+0x40` 起。 | 外层长度检查存在。 |
| 10 `FREE` `0x1a670e8` | `0x1a67104–0x1a67126` 检查固定最小长度、取固定 client/object 字段并调回调；未见宿主 count 或变量数组。 | 未发现长度驱动写入。 |
| 4 `ALLOC_MEMORY` `0x1a8b58c` | `0x1a8b5d8–0x1a8b5e2` 检查固定消息长度；`0x1a8b5ec–0x1a8b5f8` 对页数/移位换算做高位检查。后续为内存分配/映射路径，本 handler 未见按原始 count 写固定数组。 | 未发现 RPC 层拷贝溢出；不覆盖下游内存管理实现。 |
| 50 `GPU_EXEC_REG_OPS` `0x1a8a7f0` | 详见 F-1；count 控制 `count*32` 读取、动态栈分配和拷贝，未与消息长度/栈界限比较。 | **B 级候选。** |
| 21 `DUP_OBJECT` `0x1a7747c` | `0x1a77498–0x1a774a2` 只检查固定长度；`0x1a774a6–0x1a774c2` 取固定字段并调对象回调。无宿主 count 数组。 | 未发现变量拷贝溢出。 |
| 22 `IDLE_CHANNELS` `0x1a91e90` | 详见 F-2；`count*12` 乘法溢出检查存在，但消息跨度只与 count 比较。 | **B 级候选。** |
| 78 `DUMP_PROTOBUF_COMPONENT` `0x1a8abc8` | `0x1a8ac16–0x1a8ac26` 检查 `bufferSize+0x30` 不小于固定头且不超过实际消息跨度；`0x1a8ac82–0x1a8ac86` 对 component 范围作限制。 | 可变 blob 有实际长度检查。 |
| 202 `ECC_NOTIFIER_WRITE_ACK` `0x1a776a0` | `0x1a776ac–0x1a776c2` 直接调用固定 notifier 回调；未见读取宿主 count/长度后复制。 | 未发现变量拷贝。 |
| 54 `SET_PAGE_DIRECTORY` `0x1a66f34` | `0x1a66f62–0x1a66f6c` 检查固定最小长度；`0x1a66f70–0x1a66f7a` 仅清零固定 0x20-byte 局部对象，再传递固定字段。 | 未发现变量数组。 |
| 79 `UNSET_PAGE_DIRECTORY` `0x1a67014` | `0x1a6703e–0x1a6704c` 检查固定最小长度；`0x1a67050–0x1a67092` 组装固定 8-byte 参数。 | 未发现变量数组。 |
| 70 `UPDATE_BAR_PDE` `0x1a67180` | `0x1a671da–0x1a671e2` 检查固定最小请求；后续 `0x1a67220–0x1a67244` 的 byte count/24-byte 遍历来自已取得的 BAR/PDE 资源记录，不是从 RPC body 直接取的柔性数组 count。 | 未发现 RPC body count 直接驱动的复制；下游资源对象边界不在本结论内。 |
| 65 `GET_GSP_STATIC_INFO` `0x1a66ea0` | `0x1a66eb2–0x1a66eb8` 检查固定请求；`0x1a66ec0–0x1a66ed6` 校验源/目的指针范围，随后 `0x1a66eda–0x1a66f1e` 固定复制 0x640 bytes。 | 固定复制且有地址范围检查。 |
| 1 `SET_GUEST_SYSTEM_INFO` `0x1a7759c` | `0x1a775bc–0x1a775d6` 检查固定请求长度及枚举字段范围；后续为固定字段/状态更新，无 count 驱动数组。 | 未发现变量拷贝。 |
| 47 `UNLOADING_GUEST_DRIVER` `0x1a8a110` | `0x1a8a138–0x1a8a13c` 检查固定最小长度；`0x1a8a168–0x1a8a180` 读取固定字段并更新状态标志。 | 未发现变量拷贝。 |
| 228 `INIT_GSP_TRACE_CRASH_BUFFER` `0x1a8a39c` | `0x1a8a3dc–0x1a8a3e8` 取固定 handle/size；`0x1a8a448–0x1a8a460` 把长度交给映射/分配接口；无 count×entry 的 body 复制循环。 | 未发现 RPC 柔性数组；下游映射边界另审。 |
| 72 `GSP_SET_SYSTEM_INFO` `0x1a8a680` | `0x1a8a6aa–0x1a8a6b0` 检查固定请求长度；处理固定系统信息结构/固定范围数据，未见由 body count 驱动的循环。 | 未发现变量拷贝溢出。 |
| 73 `SET_REGISTRY` `0x1a961f4` | 详见 F-3；校验 `size+0x20`，但没有可见的 `numEntries` 对表剩余长度检查，且 offset/length 进入后续处理。 | **B 级候选（越界读取；未证实越界写）。** |


## `RPC_RM_CONTROL` / `RPC_RM_ALLOC` 的长度细节与限制

- 参照结构：`g_rpc-structures.h` 的 `rpc_gsp_rm_control_v03_00` 中 `paramsSize` 后参数体起于 payload `+0x48`；`rpc_gsp_rm_alloc_v03_00` 中 `paramsSize` 后参数体起于 payload `+0x40`。
- Control：handler `0x1a8b84c` 将 size 加 `0x48`（`0x1a8b892`），拒绝不足固定头的请求（`0x1a8b8e2–0x1a8b8e8`），再以实际字节跨度作 `bltu` 检查（`0x1a8b8ec–0x1a8b8f0`）；之后才将参数传给回调（`0x1a8b90a–0x1a8b920`）。32-bit 加法 wrap 后形成的小于固定头值会被最小头检查拒绝，形成高位/大值的总长度则会被实际跨度比较拒绝；在本条路径未见可绕过的短长度例子。
- Alloc：对应 `paramsSize+0x40` 和实际跨度检查见 `0x1a8b0fc–0x1a8b112`，参数起点保存于 `0x1a8b126`。
- 分发器对 `0x4c` 与 `0x67` 有专门预处理（`0x1a92148–0x1a92150`，分别暂存 control command/class），随后仍进入上述 18 项 handler 表。`0x1a9217c–0x1a921d8` 还比较若干 RM control command ID；这些只是外层 dispatcher 分支，不等价于审计了每个 command callback 的结构长度。

## 定级、正反证据与后续边界

- **B 级风险（可复核）：** `GPU_EXEC_REG_OPS` 和 `IDLE_CHANNELS` 的宿主 count 未受完整消息长度约束就进入逐项读取/动态栈分配；`SET_REGISTRY` 的 `numEntries` 未与已验证的 table `size` 关联，offset/length 缺少可见的表内边界约束。每项均给出具体反例及指令范围。
- **未确证的部分：** 本轮没有任务栈大小/栈边界证据；没有证明栈 VLA 写穿到相邻对象，也没有证明 `SET_REGISTRY` 的源越界读最终造成越界写。故不报 A 级内存破坏，不复述已知 K3-1。
- **RPC_RM_CONTROL 剩余面：** 已证实 `paramsSize` 不超过本条消息的实际可用字节数；仍需对其支持的各类 `NV2080_CTRL_*` 下游回调逐个确认固定参数结构/版本长度，不能把外层封套检查当成全部 command 的安全结论。
- 610.43.03 源码只用来核对 wire layout/正常发送行为。恶意宿主可绕过正常驱动 serializer，因此 sender-side `maxRpcSize`/打包一致性检查不替代 RX 固件端验证。

# 自然 FSP 客户端路线：当前证据边界（2026-10-29）

## 结论

本轮把路线 1 推进过了旧报告中的错误终点，恢复并验证了自然 `OBJGPU` 及其 BAR0 映射：

```text
g_pSys @ 0x041d3f38  -> pSys    = 0x0fe46017f0
pSys + 0x1a8         -> pGpuMgr = 0x0fe4604130
pGpuMgr + 0x441f0    -> pGpu    = 0x0fe4792290   (gpuHandleIDList[0].pGpu)
pGpu + 0xb98         -> B       = 0x08200000       (deviceMappings[0].gpuNvAddr)
```

自然 FSP 客户端函数 `0x14f6c14(pGpu)` 已成功读取该映射下的 MSGQ head/tail，并返回空队列状态 0，随后进入预期的成功回调。这是自然 `pGpu/B` 的独立正对照。

**未获得 `FSP_RUN` 明文。** 后续建立的 32 位读取原语已经证明 DMEMC/IMEMC 在自然视图中均为 `0xBADF5040`，因此这条自然映射明文提取路线最终关闭；详见文末“32 位读取终审补充”。

## 对旧结论的必要勘误

1. 旧实验曾把 `pSys` 或 `pGpuMgr` 当成 `pGpu`，再读取其 `+0xb98=0`，据此关闭自然路线。该推断无效；真正的 `pGpu` 是本轮从 `gpuHandleIDList[0]` 读出的 `0x0fe4792290`。
2. 旧“effective MMIO”实验把自然基址误作 `0x00820000`，少了十六进制的一位。正确基址为 `0x08200000`，因此：
   - EMEMC 为 `0x08af2ac0`，不是旧实验的 `0x01112ac0`；
   - DMEMC 为 `0x08af21c0`；
   - IMEMC 为 `0x08af2180`。
3. 64 位 `ld` read-gadget 在 EMEMC、DMEMC 和已知应为零的 MSGQ 地址上均返回同一种 `0xffffffffbadfffff`。因此该读法不能用于 MMIO 判值，也不能据此认定 DMEMC 被毒化。自然客户端使用的是 32 位 `lw`，两种访问宽度不能混同。
4. `0x18c6fc8` 的 `lwu + unimp` 只得到 RPC 超时，没有寄存器读回，不能作为 EMEMC 正对照或权限证据。
5. 第三回调 read-gadget 可以执行，但 B8 正对照的数据读回 qword 为 0，而源 QOUT 已知非零。故只能证明回调机制执行，不能证明 B8 完成了数据拷贝；不能把该零值当成明文或 DMEM 权限证据。

## 关键运行时证据

### 1. 自然 `pGpu`

文件：`fsp-read-gpu-handle0-run.log`、`fsp-read-gpu-handle0-dmesg.log`

```text
Xid 120 @ pc=0x0fe4792290
sepc=stval=0x0fe4792290
```

目标为 `pGpuMgr(0x0fe4604130)+0x441f0`，不是地址猜测。

### 2. 自然 BAR0 映射 `B`

文件：`fsp-read-gpu-bar0-run.log`、`fsp-read-gpu-bar0-dmesg.log`

```text
Xid 120 @ pc=0x08200000
sepc=stval=0x08200000
```

目标为 `pGpu(0x0fe4792290)+0xb98`。

### 3. 自然映射正对照

文件：`fsp-msgq-natural-run.log`、`fsp-msgq-natural-dmesg.log`

`0x14f6c14(pGpu)` 返回 0 并进入 `0xdeadbeee` 成功回调，证明自然客户端可使用 `pGpu/B` 读取 MSGQ 状态。

### 4. MMIO 判值反例

文件：`fsp-msgq-qword-run.log`、`fsp-msgq-qword-dmesg.log`

已知空 MSGQ 应为零，但 64 位 read-gadget 仍返回 `0xffffffffbadfffff`。所以 EMEMC/DMEMC 上相同结果不得解释为真实寄存器值。

### 5. B8 第三回调边界

文件：`b8-third-aligned-run.log`、`b8-third-aligned-dmesg.log`

第三回调执行了 `0x1020a30`，但最终 qword 为 0，未复现 QOUT 已知非零内容。B8 成功状态不等于通用数据读取能力。

## 已核对的静态对象模型

- 610.57 OpenRM 源码中，`g_pSys` 是 `OBJSYS *`，`SYS_GET_GPUMGR(p)` 取 `pGpuMgr`。
- `OBJGPUMGR.gpuHandleIDList[]` 的每项包含 `pGpu` 和 `gpuInstance`；`gpu_mgr.c` 在 attach 时填入该指针。
- `gpu_mgr.c` 将 `regBaseAddr` 写入 `pGpu->deviceMappings[0].gpuNvAddr`。
- GSP 初始化反汇编独立显示 `pGpuMgr+0x441f0` 为 16 字节条目列表，`+0x443f0` 为条目数。
- 本机公开源码的默认 x86/RISC-V 结构布局与 shipped GSP-RM 不同，不能用 host `offsetof` 替代 GSP ABI。`verify_offsets.c` 及 `host_x86_layout.txt`/`riscv64_layout.txt` 仅用于记录这一差异；实际地址以固件证据为准。

## 当前唯一下一缺口

必须先建立一个**真实、可验证的 32 位 MMIO 读取及回传路径**，再读 DMEMC/IMEMC：

1. 用已知 32 位寄存器值完成正对照；
2. 读取 DMEMC/IMEMC 控制值；
3. 只有控制值真实且允许访问时，才考虑 IMEM/DMEM 数据读取；
4. 在此之前，不宣称 `FSP_RUN` 明文路线已成功，也不把零值、超时或 `0xffffffffbadfffff` 当作权限证明。

不建议重复：旧错误地址、64 位 MMIO read-gadget、`lwu+unimp`、无数据正对照的 B8 拷贝，或自然对象地址盲猜。

可复用的第三回调布局保存在 `b8_third_readback_full_positive_map.txt`，但它只有在找到真实数据源后才有意义。

## 主机与清理状态

- 共使用 11 个一次性 VM overlay；未修改 GSP 固件、VBIOS、InfoROM 或熔丝。
- 每次实验后均执行现有恢复流程，CUDA sanity 均通过。
- 最终 NVIDIA/音频驱动分别为 `nvidia`/`snd_hda_intel`，CUDA sanity 通过，GDM 已恢复 `active`。
- 所有本轮 overlay 已删除；只读 base `arch-gpu-base.qcow2` 保持模式 `0444`。
- GNOME 初始检查确认使用 AMD `card2/renderD129`，并未持有 NVIDIA `card0/renderD128`。

原始日志、map、进入/退出 VM 记录均保存在本目录，未改动旧报告。

## 32 位读取终审补充（最新，优先于上文）

随后建立了真正的 32 位 MMIO 读取/回传原语：回调 `0x103b910` 执行 `c.lw a0,0(a0)`，再加上已知的 `a1=metadata+0x9c` 并跳转，因此异常 PC 可直接反推出 32 位寄存器值。

验证结果：

| 目标 | 实际结果 | 判定 |
|---|---|---|
| `pGpu+0xb98` 正对照 | PC=`0x0fec9910ac`，精确对应 `B=0x08200000` | 32 位读取链成立 |
| EMEMC `0x08af2ac0` | PC=`0x0fe67910c0`，对应 `0x02000014` | 与已知 EMEMC 值一致 |
| DMEMC `0x08af21c0` | PC=`0x0f9f5860ec`，对应 `0xBADF5040` | 被过滤，不能读取 DMEM |
| IMEMC `0x08af2180` | PC=`0x0f9f5860ec`，对应 `0xBADF5040` | 被过滤，不能读取 IMEM |

因此，**自然 `pGpu/B` 路线对 FSP 明文提取正式关闭**：自然对象和映射确实存在且可用于消息面，但 DMEMC/IMEMC 在该自然 GSP 客户端视图中仍被过滤。进一步读取 IMEM/DMEM 数据没有合法前提，也没有 `FSP_RUN` 明文产出。后续若继续获取明文，需要新的工程/debug 工件、不同的调试访问条件或新的服务/schema，而不是继续这条自然映射路线。

同时，修改后的 `rtx5090-vfio-enter-live`/`preflight` 已通过实机交接验证：GDM 和原有 `gnome-shell` 在实验全程保持运行，未再停止桌面。`RTX5090_VFIO_KEEP_GDM=0` 仍保留旧的 display-off 回退行为。

本轮另外 4 个 overlay 已恢复并删除；最终 GDM=`active`、CUDA sanity 通过、base 仍为 `0444`。

## PIO channel 全覆盖补测（消除仅测 channel 0 的证据缺口）

此前仅凭 IMEMC[0]/DMEMC[0] 下结论过强，因为 nova 文档定义了 4 个 IMEMC 和 8 个 DMEMC 通道。随后使用同一已验证的 32 位原语补做完整矩阵：

| 通道 | 地址范围 | 实测结果 |
|---|---|---|
| IMEMC[0..3] | `0x08af2180` / `190` / `1a0` / `1b0` | 4/4 均为 `0xBADF5040` |
| DMEMC[0..7] | `0x08af21c0` / `1c8` / `1d0` / `1d8` / `1e0` / `1e8` / `1f0` / `1f8` | 8/8 均为 `0xBADF5040` |

因此最终结论不再只依赖 channel 0：**在当前 GB202、610.57 GSP 上下文及当前 FSP 状态下，全部文档化 IMEMC/DMEMC PIO 通道均被过滤，没有可用于 dump FSP 明文的通道。** 这仍不否定新工程/debug 工件、不同调试访问条件或新服务/schema 的可能性。

`run_lw32_channel.sh` 只接受上述文档化地址，每次使用独立 overlay、恢复并执行 CUDA sanity；12/12 均通过。补测产生的 overlay 也已全部清理，GDM 持续为 `active`。

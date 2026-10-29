# GB202 / RTX 5090 研究现状（2026-10-28）

## 目标

- 取得可验证的 `FSP_RUN` 明文。
- 解除 GB202 上被关闭的 SM/L2 资源。

**两个目标目前均未实现。** 没有 AES 解密 oracle，没有 `FSP_RUN` 明文，没有解除 floorsweep/fuse 限制。

## 已证明成立的能力

### 1. 多回调与 B8 成功状态

- 在 610.57 v25.3 注入链中，已在**同一条注入消息**内证明真实的第二回调。
- 严格对照结果：
  - `ret0` 正对照进入 `sepc=stval=0xdeadbeee`；
  - 真实 B8 backend `0x100cf9c` 也进入相同异常。
- 调用点只有在 B8 返回 `0` 时才执行第二回调，因此这是固件侧证据，不是 host 提交次数、staged 值或 RPC 超时推断。

关键证据：

- `MULTI_CALLBACK_BREAKTHROUGH_20261028.md`
- `b8-status-ret0-minimal-dmesg.log`
- `b8-status-copy-minimal-dmesg.log`
- `B8_STATUS_BREAKTHROUGH_20261028.md`

**限制：**只建立了 B8 成功状态判断，没有建立通用 B8 数据读写原语。两条完整注入消息连续消费仍未证明。

### 2. 注入上下文和部分运行时结构

已验证：

- 当前共享窗口和专用 QPTE 页表；
- 固件能够读取注入的 AES C 上下文；
- B8 使用的部分 ARG、QOUT、源字段、专用页表项；
- host QRESULT 哨兵读回控制。

B8 的 `flags=1` 方向是 PA→本地读取，不是 host 写出。反向写 canary 未成功，因此不宣称 B8 host-write 能力。

### 3. read-gadget 的正确解释

`0x1020a30` 的语义是读取 `*(a1+0x168)` 并跳到该值，要求 64-bit 对齐。此前若干地址解释已据此纠正，旧报告中若省略该偏移，应以本说明为准。

## AES / SE0 当前边界

- AES0 已执行到 SE0 后端，但读取后端状态寄存器时失败：
  - `sepc=0x1a97582`
  - `stval=0x164010f8`
  - `scause=5`
- 逻辑 SE0 窗口为 `0x01500000`，大小 `0x40000`，配对基址为 `0x16400000`。
- AES1 超时，无 ciphertext/tag。
- 610、615、Windows 610.88 均未提供另一套有效映射。
- 正式 host/GSP 读取也未能访问目标，当前不能区分映射错误、权限/PMP 限制或后端不可用。
- **没有 AES 已知答案运算，没有 oracle，没有向该路径输入 `FSP_RUN`。**

主要报告：

- `AES_BACKEND_FAULT_ANALYSIS_20261028.md`
- `SE0_AND_B8_PROBE_ADDENDUM_20261028.md`
- `SE0_FSP_MMIO_STATUS_20261028.md`

## 直接 GSP-PRI / MMIO 读取

- 正式 `GPU_EXEC_REG_OPS` 对 HWCFG、IMEMC、DMEMC 等敏感寄存器返回 `0xBADF5040`。
- 正对照 `PMC_BOOT_0` 和 `FSP_EMEMC` 正常，说明读取路径本身有效。
- 原始 `0x8f2ac0` 在注入任务中直接读取会产生 page fault。
- `0x1a97540` 的窗口表不覆盖该地址，进入错误路径 `0x1aa3410`。
- 目前没有可用于正对照的 FSP MMIO 映射。

## EMEM / NVDM 服务

EMEM 是实际可用的通信口，但不是 FSP 明文存储：

- `INFOROM` 仅提供板级信息，如 PPID。
- `ROMREAD` 仅在 UEFI 阶段受理，且读取 ROM，不等于读取 FSP 解密后的内部镜像。
- `0x1b` 存在，但名称、格式和用途未知，不能作为解密接口。
- GSP、MODS、FieldDiag 的 sender 审计均未发现大段解密固件回传接口。

报告：`FSP_MESSAGE_SERVICE_AUDIT_20261028.md`。

## 自然客户端 / 私有映射

这是目前剩余的主要软件路线，但尚未恢复出有效对象及映射。

已确认：

- MMIO base 的形式为 `B = *(uint64_t *)(A0+0xb98)`，FSP 客户端实例与外层上下文不是同一对象。
- `0x41d4140` 是指针槽，实测为 NULL，不是可用的自然 `A0`。
- 找到过动态对象 `0x0fe46017f0`，但其 `+0xb98=0`，且虚表项不匹配，不能作为自然客户端上下文。
- 根管理对象的 `+0x1a8` 表链中，候选表项的基址和对应虚表项均为 0，不能提供有效映射。
- late-arm 尝试未能在保持 NVML 健康的情况下取得初始化完成后的自然对象。
- 元数据不可执行，自定义 RISC-V 代码无法运行；签名固件修改路线已放弃。

当前准确结论：**没有可用的自然 `A0` 和私有 MMIO 映射证据。** 这不等于证明所有自然上下文都必然失败，但当前没有可验证实验可做。

相关报告：`FSP_ROUTE2_MAPPING_STATUS_20261028.md`（含勘误）。

## 已排除的路线

- 615 旧 K3 注入链不可用；
- VBIOS override 不改变物理 floorsweep；
- 公开 `FSP_RUN` 明文搜索无结果；
- PRNG/KDF/AES-256 暴力搜索不可行；
- 元数据自定义代码不可执行；
- 签名固件补丁不可行；
- 反复更换地址、token、SE0 alias 均无新证据。

## 当前实验模块与固件

- 当前实验 `share/nvidia.ko` SHA-256：
  `6f17a6495983bc7d2f7f355d9223122100c73095c30473f321fb261385a68343`
  - guest vermagic：`7.1.9-arch1-2`
  - 包含 QRESULT 哨兵诊断。
- 610.57.04 GSP firmware SHA-256：
  `c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999`

## 当前机器状态

- host NVIDIA、音频和 GDM 已恢复，`gdm.service=active`。
- 没有活动研究 VM。
- 本轮创建的临时 overlay 已清理。
- 只读 base `/home/user/rt_5090_project/vfio_production_lab/guest/arch-gpu-base.qcow2` 保持 `0444`。

## 下一步

1. 继续从自然构造/调用链恢复真正的 per-GPU `A0` 及其私有 MMIO 映射；只有在取得有效 EMEMC 正对照后，才考虑 IMEM/DMEM。
2. 若无法恢复，则停止该软件路线，等待新的工程固件、调试转储或可用 JTAG/debug 条件。
3. 不再重复地址枚举、EMEM 缓冲区扫描、AES alias/token 试验或毒化 GSP-PRI 读取。

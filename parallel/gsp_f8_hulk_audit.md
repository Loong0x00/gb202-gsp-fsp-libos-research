# GB202 / 610：GSP、FSP、HULK 与 `0x8200f8` 静态审计

> **后续绑定纠错（2026-07-21）：** 本文对 `0x0108c494` 的 load/store 方向
> 仍然成立，但当时没有闭合其 chip-HAL 绑定。后续 OBJBSP constructor 重放已
> 证明该函数是 TU102/TU116 的 NVDEC ucode-encryption helper；GB202/index 65
> 的同一 `+0x338` 槽绑定 `0x019b4ea0` success stub。因此这条 direct `f8` read
> 不是 5090 runtime path。见 `parallel/gsp_f8_consumer_lifecycle.md`。

## 范围与证据口径

本轮只读本地静态文件，没有访问 GPU、设备节点、BAR/MMIO、PCI config、
debugfs 或实时驱动状态；没有执行 MODS、固件或未知二进制，也没有 reset、模块
操作或提权。反汇编仅使用 `parallel/gsp_rv_window.py` 查看明确地址的小窗口；没有
全量反汇编。

主要材料：

- 610.43.03 开源 RM：`/usr/src/nvidia-610.43.03/src/nvidia`；
- 当前安装的 `gsp_ga10x.bin`，以及来源已闭合的 inner ELF
  `/tmp/gsp_inner_19f040_a.elf`。其映射、大小和 SHA-256 见
  `parallel/GSP_ARTIFACT_PROVENANCE.md:7-46`；GB20X 使用该 firmware 名称的
  公开映射见
  `/usr/src/nvidia-610.43.03/src/nvidia/arch/nvalloc/common/inc/nv-firmware.h:93-106`；
- 已有权限审计：`parallel/tmux_mods_permissions.md`、
  `parallel/mods_final_crosscheck.md`、`parallel/evidence_audit.md` 和
  `parallel/gb202_610_arch.md`；
- MODS 包内旧 Figueroa HULK 样本，仅作为历史格式样本，不作为 GB202 凭据。

下文严格使用：

- **FACT**：当前文件或限定反汇编窗口直接证明；
- **INFERENCE**：多项事实支持，但缺少目标 firmware consumer/绑定；
- **UNKNOWN**：当前材料不能回答。

“公开树/当前归档未命中”只表示这组可见材料没有命中，绝不改写成“固件或硬件
不存在该行为”。

## 结论摘要

| 问题 | 判定 | 等级 |
|---|---|---|
| GSP ELF 中 direct `0x8200f8` block 是读还是写？ | `0x0108c4ae` 是 `lw`；该块写 `0x820040` 和 `0x82013c`，不写 `0x8200f8`；后续证明 GB202 不绑定该 block | **FACT**，限编码方向；GB202 binding 见后续纠错 |
| 当前 GSP ELF 是否有第二个硬编码 `f8` setter？ | 对 first executable PT_LOAD 的 `LUI 0x820` 直接基址枚举未命中 | **FACT（负结果，严格限扫描模式）** |
| HULK 能否用动态 payload 避开 GSP 中的 `f8` literal？ | 当前 GSP 会把证书 blob 以 NVDM `0x11` 交给 FSP；FWSECLIC 错误表认识 register override/RMW | **INFERENCE（机制可能）** |
| 当前是否证明 GB202 HULK 授权范围覆盖 `0x8200f8`？ | 没有 GB202 证书、range/whitelist 或 FSP 解析代码 | **UNKNOWN** |
| HULK `0x11` 是否映射到 floorsweep task 2/subobject 1？ | 没有；两者只共享 FSP transport。task 2 的现有旁证关联 PRC capability `0x13`，不是 HULK `0x11` | **FACT（无映射证据）/ UNKNOWN（FSP 内部路由）** |
| 是否找到 GB202 task-2 consumer？ | 当前 OpenRM、GSP ELF 和归档报告中没有可审计 consumer；FSP 指令体不在这些文件中 | **FACT（材料边界）/ UNKNOWN（consumer 行为）** |
| 是否找到 `f8` restore 或权限 lifetime？ | 没有公开 restore/undo schema、host token 或可见 `f8` 回写点 | **FACT（负结果）/ UNKNOWN（FSP 自动收权）** |

## 1. 当前 GSP 的直接 `0x8200f8` 命中是读取

### 1.1 有限基址枚举

inner ELF 的 first executable PT_LOAD 是 file offset `0..0xe97000`、VA
`0x01000000..0x01e97000`。本轮只枚举该段中 2-byte aligned、立即数为
`0x820` 的 RISC-V `LUI` 候选，共 8 处：

```text
0x0108c4a6  0x013d1b1c  0x013d8658  0x014163f8
0x01444508  0x01449816  0x015348ee  0x018494dc
```

随后只对每处查看 160 bytes 以内窗口。唯一直接使用 `+0xf8` 的块为
`0x0108c494..0x0108c4e8`：

```text
0x0108c4a6  lui  a1, 0x820
0x0108c4ac  add  a5, a1
0x0108c4ae  lw   a2, 0xf8(a5)     # read  base + 0x8200f8
0x0108c4b2  lw   a3, 0x13c(a5)
...
0x0108c4ca  lw   a4, 0x40(a5)
0x0108c4cc  ori  a4, a4, 1
0x0108c4d0  sw   a4, 0x40(a5)    # write base + 0x820040
...
0x0108c4da  sw   a4, 0x13c(a5)   # write base + 0x82013c
```

**FACT：** 当前已知 GSP `f8` 直接命中是 32-bit read。该基本块没有向
`+0xf8` store；它的两次可见 store 分别是 `+0x40` 和 `+0x13c`。因此不能把这
段代码写成“GSP lowering/restoring `0x8200f8`”。
主报告此前将它归入 NVDEC encryption/latch 例程；本轮独立闭合的是上述访问
方向和地址，不靠该语义标签作结论。

**FACT（限定负结果）：** 其余 7 个直接 `LUI 0x820` 小窗口没有 `+0xf8`
访问。对 inner ELF 的 raw little-/big-endian `0x008200f8` 以及 MODS RegHal
setter ID `0x405c4000/0x205c4000/0x105c4000` 精确字节搜索也无命中。

**UNKNOWN：** 这不是 whole-program data-flow proof。通过通用 PRI helper、动态
RegHal ID、表驱动地址、证书 payload、FSP/GFW 内部代码或硬件状态机访问 `f8`
仍无法由上述负结果排除。

## 2. 当前 HULK 路径允许地址留在 payload，而不在 GSP text 中

### 2.1 当前 610 的可见 sender

610 头文件把 HULK 和 PRC 定义为不同 NVDM type：

- `NVDM_TYPE_HULK = 0x11`、`NVDM_TYPE_PRC = 0x13`：
  `/usr/src/nvidia-610.43.03/src/nvidia/arch/nvalloc/common/inc/nvdm_format.h:37-59`；
- GB202 使用的 `kfspNvdmToSeid_GH100` 将 HULK 显式路由到 SEID 0；PRC
  走 default 0：
  `/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c:267-302`；
- GB202 对该 FSP 实现的 generated HAL 绑定见
  `/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kern_fsp_nvoc.c:509-519`。

对当前 GSP 通用 sender `0x0150e918` 的直接 `AUIPC/JALR` caller 做限定扫描，
得到与主审计一致的 18-address direct-call candidate 集。逐一查看 64-byte 左右
窗口后，只有两处把 NVDM type 立即数设为 `0x11`：

1. `0x0150ef5c` 置 `a4=0x11`，`0x0150ef5e` 把证书长度加 4，
   `0x0150ef64` 调用 sender；payload 指针来自已分配的 certificate buffer。
2. `0x01510120` 置 `a4=0x11`，`0x01510122` 置长度 4，
   `0x01510132` 写零 dword，`0x01510136` 调用同一 sender。已有主审计将其识别为
   激活已刷 token 的分支。

registry string xref 也在同一 loader 内闭合：

```text
0x0150f2ea -> 0x01e77698  RmActivateHulk
0x0150f310 -> 0x01e776a8  RMHulkCertSize
0x0150f606 -> 0x01e776b8  RMHulkCert
```

**FACT：** GSP loader 传输的是 certificate bytes，不在这个 loader 内展开
目标寄存器。因此“GSP text 没有第二个 `0x8200f8` literal”不能排除 FSP 按
payload 处理该地址。

### 2.2 能证明的动态语义边界

当前 GSP 的 FWSECLIC error-name table 明确包含：

- `CERT_T7_REG_OVERRIDE_TYPE_UNKNOWN`（file `0xe2d015`）；
- `CERT_HULK_REG_READ_BACK_VERIFY_MISMATCH`（file `0xe2d3e5`）；
- `CERT_HULK_REG_RMW_RBV_READ_BACK_VERIFY_MISMATCH`（file `0xe2d425`）；
- `CERT_HULK_OPCODE_UNDEFINED`（存在于同一 FWSECLIC/HULK error-name table）；
- `CERT_HULK_ECID_MISMATCH`、`DEVID_MISMATCH` 和 `PRI_TRANSACTION_ERROR`
  （存在于同一 FWSECLIC/HULK error-name table；`PRI_TRANSACTION_ERROR`
  精确 string offset 为 `0xe2d51d`）。

**FACT：** 当前协议/错误命名空间认识 certificate-driven register override/RMW、
readback verification 和设备身份检查。

**INFERENCE：** HULK 的具体 register target 可以由签名 payload 提供，因此无需
在 GSP code 中硬编码目标地址。这使“某个合法、GB202/设备绑定的证书可能请求
`f8` 动作”不能仅凭 literal scan 排除。

**UNKNOWN：** 当前没有 FSP 的 HULK parser、GB202 register allowlist/range、
opcode policy 或任何 NVIDIA 签发且绑定本设备的 HULK certificate。故不能升级为
“GB202 HULK 已允许 `0x8200f8`”。

作为负面样本交叉检查，MODS 包内 8 个 JS 文件实际只有 6 份唯一的 2015
Figueroa certificate（304、340、360、536、552、664 bytes）。离线解析 array
bytes 后，六份均不含 little-endian `0x8200f8`、`0x8200dc`、`0x820040` 或
`0x8234e0`。这是这些旧样本的 **FACT**，不是 GB202 policy 的证据。

## 3. HULK `0x11` 与 floorsweep task 2 没有映射证据

**FACT（MODS 570.151 host）：** `parallel/tmux_mods_permissions.md:45-53`
已经闭合：GB20x floorsweep host 在 `0x106c570..0x106c58c` 调用 common sender，
参数为 task 2/subobject 1；Hopper sibling 在发送同一 task/subobject 前只预检查
`0x8200d0` 与 `0x8200dc`。这支持 d0/dc 权限目的，但没有 GB202 consumer。

**FACT（协议分离）：** HULK 是明确的 NVDM type `0x11`。task 2 的 MODS
capability path 在 `0x185e530` 经 `0x185e0e0` 查询的 key 是 `0x13`；同一 key
也用于 PRC-write task 13。当前 610 公开头文件把 `0x13` 定义为
`NVDM_TYPE_PRC`。这最多证明 task 2 与 PRC capability family 的关联；QCAP key
本身不等于完整的 on-wire consumer 语义。

**FACT（当前 GSP bounded scan）：** 两个 immediate `0x11` sender call 都位于
HULK init loader。当前 GSP 另有 immediate `0x13` sender calls，但本轮小窗口没有
把它们绑定到 floorsweep task 2；例如 `0x0157a780` 的 `04 01 00 00` payload 已在
`parallel/tmux_gsp_l2_repair.md:58-63` 识别为 InfoROM request，而不是 task 2。

**结论：** 当前只有“共享 FSP transport/SEID 0”，没有“HULK NVDM `0x11`
等于或封装 floorsweep task 2/subobject 1”的证据。共享 endpoint 不能建立 task
身份映射。FSP 是否在内部让两条机制共享某个权限状态仍为 **UNKNOWN**。

## 4. 当前材料没有可审计的 GB202 task-2 consumer

对整个 `/usr/src/nvidia-610.43.03` 做精确 `rg`：

- `0x8200f8/0x8200dc/0x8200d0`：无命中；
- `task2/task 2/subobject1/subobject 1`：无命中；
- HULK 只有 type 定义、FSP SEID case 和不适用于 GB202 的 GB20B/GB20C SEC2
  case，详见 `parallel/gb202_610_arch.md:101-123`。

**FACT：** GB202 的可工作 host NVDM endpoint 是 FSP；GB202 SEC2 packet/NVDM
方法落到 stub。generated HAL 证据见 `parallel/gb202_610_arch.md:37-76`。

**FACT（材料边界）：** GB202 FSP 指令体不是当前 GSP ELF。公开源码明确说
“Bootfsm triggers FSP execution out of chip reset”，host 只等待 FSP 写 boot
complete：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb202.c:48-61`。
610 generated bindata 名单中也没有 FSP instruction-image entry；可见 archive/load
路径是供 FSP 验证/启动的 GSP FMC/GFW 材料，不是 FSP consumer 本体。

**FACT（负结果）：** 当前可见 OpenRM、GSP ELF、driver bindata metadata 和已归档
VBIOS/Falcon 报告没有给出 GB202 task/subobject dispatcher 或对 d0/dc/f8 的实际
写入函数。VBIOS 样本中的 version-6 Falcon descriptor 被标为 encrypted；
`FSP_RUN` 只是 descriptor 区域的 printable tag，不能提升为 task/subobject 语义，
见 `parallel/evidence_audit.md:327-330`。

**UNKNOWN：** 这不证明 task-2 consumer 不存在。它可能位于芯片复位启动的
不可见 FSP code/ROM 或其他未公开 firmware；本轮没有其可审计指令体。

## 5. 没有 `f8` restore/lifetime 的可见证据

### 5.1 response 不是 restore 证明

公开 FSP command response 只有三个 `NvU32`：`taskId`、`commandNvdmType`、
`errorCode`：
`/usr/src/nvidia-610.43.03/src/nvidia/arch/nvalloc/common/inc/fsp/nvdm_payload_cmd_response.h:35-42`。
parser 只记录这些字段并映射 status：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c:455-500`。

**FACT：** public response schema 没有 permission token、prior PLM value、expiry、
restore result 或 undo handle。成功 ack 只证明 FSP 报告 command success。

### 5.2 host/GSP 未命中的 restore 点

- GSP direct-call scan 中 hard-coded HULK `0x11` 只有 certificate load 和 flashed
  token activation 两个进入动作；没有第三个 hard-coded deactivate/restore sender。
- OpenRM 中没有 HULK restore/undo message、payload struct 或 caller；精确名称搜索
  也没有 `HULK + restore/undo/close/revoke/deactivate` 命中。
- 当前 GSP 的直接 `f8` 命中是 read，不是 restore write。
- MODS task-2 host 路径没有收到 response vector/token；正常 apply 后的 host
  路径也没有第二条已知 FSP close 消息，见
  `parallel/tmux_mods_permissions.md:59-66,114-117`。
- `GB20xPrepareResense` 的 clear-coded operation 针对 latch `0x820040.bit0`，不是
  PLM `0x8200f8`；reset/resense 也不能在没有 consumer 证据时称为 `f8` restore。

以上均为 **FACT（当前可见 host/GSP 负结果）**。

**UNKNOWN：** FSP 可能按 response、首个受保护写、计时器、init phase、session、
reset 或自身状态机自动收权，也可能保持到其他边界。当前没有足够证据区分这些
模型；chip reset 会重新启动 FSP 也不等于已经证明 PLM 恢复到某一数值。

## 最终判定

1. **FACT：** 本轮 `LUI 0x820` immediate-base 枚举中唯一的 `0x8200f8`
   命中是读取；没有可见直接 `f8` setter/restore。
2. **INFERENCE：** HULK certificate-driven register operation 可以让目标地址只
   出现在 payload/FSP policy 中，因此 literal scan 不能排除潜在 `f8` 动作。
3. **UNKNOWN：** 没有证据证明任何当前 GB202 HULK certificate/range 实际覆盖
   `0x8200f8`。
4. **FACT：** HULK `0x11` 与 floorsweep task 2 没有映射证据；task 2 的现有
   capability 旁证属于 PRC `0x13` family。共享 FSP/SEID 0 不是身份映射。
5. **UNKNOWN：** GB202 task-2 consumer、`f8` lowering、授权 lifetime 和自动
   restore 都仍位于当前不可见的 FSP/firmware/hardware 边界，不能从“公开未命中”
   写成“不存在”。

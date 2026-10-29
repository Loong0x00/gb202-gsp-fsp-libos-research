# nova-core FSP 静态分析：官方寄存器地图与明文通道评估

日期：2026-10-27。范围：纯离线静态。来源：mainline Linux `drivers/gpu/nova-core`（NVIDIA 员工
John Hubbard 上游化，Copyright 2026 NVIDIA CORPORATION）sparse clone 于本目录 `linux/`；
本地 OpenRM 610.43.03 swref 头交叉核对；本地 GSP-RM 610.57 镜像指令级扫描。未碰 GPU。

---

## 1. 官方 boot 流程定论（顶层 fsp.rs 文档注释 + 代码）

```
上电/POST:  FSP 独立完成 secure boot（不经过驱动，FSP_RUN 投递在 SBIOS/VBIOS 阶段完成）
驱动加载:   wait_secure_boot() 轮询 NV_THERM_I2CS_SCRATCH_FSP_BOOT_COMPLETE (GB202 专用寄存器)
驱动→FSP:   ① COT 消息（NVDM type Cot, GB202 version=2）内含 GSP-FMC 镜像 sysmem 偏移
            + FMC 签名 + FRTS 位置 → FSP 认证并在 GSP RISC-V 核上启动 GSP-FMC
            ② PRC 消息（subcmd 0x0c Read, object 0x29 vgpu mode, flag Active=bit1）
GSP-FMC:    随后认证并启动 GSP-RM
```

- **FSP = Foundation Security Processor，Hopper/Blackwell 上取代 SEC2 的角色**。
- 驱动侧 FSP 通信走 **EMEM 队列通道 0（1 KiB）**，非 MNOC 端口（MNOC 是 CPU 侧另一条路，
  OpenRM 默认 `RmFspUseMnoc=0` 走 EMEM 队列，与 `parallel/DS_FSP_MNOC_ACCESS_20260926.md` 一致）。
- GB202：`cot_version()=2`，`fb_end_reserved = 2 MiB + 128 KiB`，COT FRTS vidmem 偏移从 FB 尾部
  反向计算、2 MiB 对齐（r570 语义）。
- COT 消息体 `NvdmPayloadCot`：`u16 version, u16 size, u64 gsp_fmc_sysmem_offset,
  u64 frts_sysmem_offset, u32 frts_sysmem_size, u64 frts_vidmem_offset, u32 frts_vidmem_size,
  FmcSignatures sigs, u64 gsp_boot_args_sysmem_offset`。
- 响应头校验：MCTP 单包 + NVDM FspResponse + `command_nvdm_type` 回显 + `error_code==0`。

**推论：FSP_RUN 的投递不受驱动控制 → "自定义驱动冻结投递时序"假设死亡；
要抓 pre-lock 相位必须到 SBIOS/OVMF 层。Linux 起来时 FSP 已运行。**

## 2. FSP 寄存器地图（nova-core regs.rs，绝对 BAR0 偏移）

PFALCON 块 `0x008f2000`（PFALCON2 `0x008f3000`），MNOC 邮箱 `0x008f1e00`（已知）：

| 偏移(PFALCON 内) | 绝对地址 | 寄存器 | 说明 |
|---|---|---|---|
| +0x040/044 | 0x8f2040/44 | MAILBOX0/1 | 经典邮箱 |
| +0x0f4 | 0x8f20f4 | HWCFG2 | 含 mem_scrubbing 位 |
| +0x100 | 0x8f2100 | CPUCTL | halted/startcpu |
| +0x12c | 0x8f212c | HWCFG1 | **[5:4] security_model: 0=None 2=Light 3=Heavy**; [3:0] core_rev |
| +0x130 | 0x8f2130 | CPUCTL_ALIAS | startcpu |
| +0x180/184/188 (×4, stride16) | 0x8f2180+ | **IMEMC/IMEMD/IMEMT** | 指令存储器窗口；IMEMC bit28=secure, bit24=aincw, [15:0]=offs |
| +0x1c0/1c4 (×8, stride8) | 0x8f21c0+ | **DMEMC/DMEMD** | 数据存储器窗口；DMEMC 无 secure 位, bit24=aincw, [15:0]=offs |
| +0x3c0 | 0x8f23c0 | ENGINE | bit0 reset（官方复位序列用） |
| +0x600+ | 0x8f2600+ | FBIF_TRANSCFG/FBIF_CTL | DMA 目标配置 |
| +0xac0/0xac4 | 0x8f2ac0/c4 | **EMEMC/EMEMD** | EMEM 窗口；EMEMC [7:2]=offs, [15:8]=blk, bit24=aincw, bit25=aincr |
| — | 0x8f2c00/04 | QUEUE_HEAD/TAIL[8] | FSP 队列指针 ×8 通道 |
| — | 0x8f2c80/84 | MSGQ_HEAD/TAIL[8] | 消息队列指针 ×8 通道 |

- 通用 `falcon.rs` 还有完整官方 **PIO/DMA 固件加载路径**（IMEMC+IMEMT tag 写法、DMATRFCMD
  256B 粒度）、**Falcon::reset()**（ENGINE reset + Peregrine 双核 Falcon/RISC-V 选择 +
  等待 scrub）、`signature_reg_fuse_version`（按 engine_id_mask/ucode_id 查 fused 签名版本）。
- Falcon 安全模型枚举（nova falcon.rs）：None / Light(LS,PL2,签名+部分特权,只能从 HS 进入) /
  **Heavy(HS,PL3,BROM 验签+全特权)**。FSP 固件必为 HS。
- OpenRM swref 头（gb100/dev_fsp_pri.h 仅 39 行：scratch 组 + MNOC_RX_FIFO_DATA）不含上述
  窗口定义 → **nova-core regs.rs 是当前最完整的公开 FSP 寄存器文档**。

## 3. EMEM 消息协议（官方实现，falcon/fsp.rs）

- 发送：EMEMC{blk=0,offs=0,aincw} → 连续写 EMEMD；TAIL=包长-4（指向最后一个 dword），
  HEAD=0。
- 接收：轮询 MSGQ_HEAD≠MSGQ_TAIL；大小 = `TAIL-HEAD+4`；EMEMC{aincr} 连续读 EMEMD；
  读完 HEAD=TAIL=0。队列非环形，每条消息后指针归零。
- channel 0 容量 1 KiB（`FSP_EMEM_CHANNEL_0_SIZE`）。

## 4. GSP-RM 610.57 侧证实（指令级扫描，本目录 gsp_rm_fsp_range_hits.txt）

lui/auipc+addi 扫描 0x8f0000–0x8f4000 共 23 处，确认 **GSP-RM 自带 FSP EMEM 队列客户端**：

- 0x8f3000(PFALCON2) 基址 + 负偏移：-0x400/-0x3fc=QUEUE_HEAD/TAIL，-0x380/-0x37c=MSGQ_HEAD/TAIL，
  **-0x540/-0x53c=EMEMC/EMEMD**（0x8f2ac0/c4）。
- 代码点 0x14f6b80–0x15017xx：读 MSGQ 指针、`tail-head+4` 长度算法与 nova poll_msgq 逐位一致、
  解析 EMEMC 的 blk([15:8]) 与 offs([7:2]) 字段、EMEMD 拷贝循环、指针归零。
- 0x150a3c4 处另有 MNOC 基址(0x8f1e00) 引用。
- **GSP-RM 不使用 IMEMC/DMEMC 窗口**（0 处命中）——设备侧对 FSP 的合法面 = 消息窗口。

## 5. 公开工件更新

linux-firmware `nvidia/gb202/gsp/`：`bootloader-570.144.bin` + **`fmc-570.144.bin`**——
FSP COT 认证目标（GSP-FMC）公开分发。与本地 570.144 MODS 分析、gsp_qemu 固件可对表。
FWSEC（nova firmware/fwsec.rs）跑在 **GSP falcon**（Turing/Ada WPR2 建立路径），与 FSP 无关。

## 6. 对"FSP 明文"目标的通道矩阵更新

| 通道 | 本轮变化 |
|---|---|
| host EMEM 窗口 | **旧"EMEM 毒化"结论作废（至少 channel 0 是官方协议面）**；blk 空间 0-255 仅 channel 0 已知合法 |
| host IMEM/DMEM 窗口 | **物理存在、地址精确、协议已知（AINCR 读法）**；FSP 自举→驱动不用→锁定状态未知=头号实测目标 |
| GSP 侧读 | GSP-RM 合法面只有 EMEM 消息窗（与 host 同一窗口）；K3 若劫持 GSP 可多试 IMEM/DMEM（GSP 权限下窗口是否放行未知） |
| 时序竞争 | 驱动不投递 FSP_RUN → pre-lock 窗口只能去 **OVMF/SBIOS 相位**抓（VM 实验室现成） |
| HWCFG1 探针 | 0x8f212c [5:4] 读数直接判定 None/Light/Heavy —— 廉价首测 |

## 7. 建议的只读实验序（未执行，需另行授权）

1. E-A 运行态单寄存器读：HWCFG1/HWCFG2/CPUCTL/MAILBOX（每 boot 一组，先在 VFIO VM）。
2. E-B EMEM 窗口只读枚举：EMEMC{blk=0,aincr} 读 EMEMD；仅 channel 0。
3. E-C DMEMC{aincr}/DMEMD 读（DMEMC 无 secure 位，最有希望）。
4. E-D IMEMC{secure=0,aincr}/IMEMD 读；若 garbage 再单试 secure=1。
5. E-E OVMF DXE 驱动在 POST 阶段重复 A–D（pre-lock 相位矩阵）。
纪律：读/写严格分离、一 boot 一实验、SBR 演练先行、禁止在锁存状态下 rescan。

## 8. 文件索引

- 源码：`linux/drivers/gpu/nova-core/`（regs.rs, fsp.rs, falcon.rs, falcon/fsp.rs,
  fsp/hal/gb202.rs, firmware/, mctp.rs, vbios.rs）
- GSP 扫描：`gsp_rm_fsp_range_hits.txt`, `gsp_fsp_callsite_context.txt`
- 对照旧档：`../parallel/DS_FSP_MNOC_ACCESS_20260926.md`, `DS_GSP_MMIO_WINDOW_20260926.md`,
  `../fsp-offline-crypto-audit-MYwexsWH/FUSEREWORK_ABI.md`

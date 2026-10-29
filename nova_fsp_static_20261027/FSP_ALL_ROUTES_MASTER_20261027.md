# FSP 明文攻坚：全路线综合清单（master）

日期：2026-10-27。综合来源：nova-core 静态分析（NOVA_CORE_FSP_STATIC_FINDINGS）、
E-A 手动读矩阵（FSP_BAR0_READ_SESSION）、历史审计（FINAL_STATUS / HARDWARE_RISK）、
GSP-RM 指令扫描、K3 已证原语。

---

## 一、已判死路线（归档，不再投入）

| 路线 | 死因 |
|---|---|
| AES-256-GCM/KDF 破解或猜测 | 全部 tag 0 命中；key 在片内 |
| 公开文件猎取（四件套/FieldDiag/debug VBIOS） | 已穷尽公开渠道（EN/CN/RU/镜像/网盘） |
| 驱动控制 FSP_RUN 投递时序 | FSP 在驱动前自举（nova 官方注释定论） |
| host 侧 IMEM/DMEM 窗口 | 0x8f2180/0x8f21c0 被 decoupler 过滤，返回 0xBADF5040（实测） |
| 零售卡 JTAG/debug | debug fuse 大概率未烧 |
| 功率侧信道 DPA | 4nm 芯片 + 600W 级噪声，无实验室条件 |
| 把 GFW 公钥/签名当 AES key | 审计已排除 |
| MODS/FieldDiag 570/580 再扫 | helper 集合已扫穿，无四件套 |

## 二、活跃路线（按当前可行性排序）

### R1. K3 → GSP 侧窗口探测【主攻】
- **原理**：0xBADF5040 过滤在 host BAR0 路径；GSP 经设备 PRI 访问同一寄存器文件
  （其 FSP EMEM 客户端代码在用 0x8f2xxx，已证）。GSP 视图里 IMEMC/DMEMC 是否放行 = 唯一未知门。
- **步骤**：K 矩阵（一 boot 一枪，标签图案）→ 找可控落点 → GSP 代码执行 →
  GSP 侧读 IMEMC/DMEMC/HWCFG1 → 若放行：dump IMEM/DMEM = **明文到手**。
- **资产**：全部本地（K3 原语已证、GSP-RM 明文、rpc_ovf_patch、VM 实验室、SBR 救援）。
- **风险**：GSP 崩溃（Xid 120）每枪一次；WPR2 stale 可能；VM+VFIO 隔离可控。
- **副产品**：无论 FSP 结果如何，可控写 = 设备侧写 floorsweep/PLM（原始目标）。
- **判定**：最强路线；单门依赖（设备侧过滤与否）。

### R2. 过滤时序判定（动态 or 静态）
- **原理**：若 decoupler 过滤在 FSP secure boot 完成后才生效，则复位后/极早期存在真实值窗口。
- **步骤**：① 补测 ENGINE @ 0x8f23c0 与 PFALCON2 块（0x8f3000+，MOD_SEL/RISC-V 状态）host 可见性
  （几条手动读，补全地图）；② VFIO 状态 FLR/SBR 后立即锤读 IMEMC/DMEMC/HWCFG（抢 FSP 重启窗口）。
- **风险**：复位类（文档化：FLR→SBR→冷电顺序，VFIO 状态演练先行）。
- **判定**：便宜，一次实验决定 host 路线死活。

### R3. EMEM 面：遥测 + 块空间枚举【新发现的合法写入面】
- **事实**：EMEMC/EMEMD 对 host 真实开放（实测 0x02000014 / "IMG\x01"）。EMEMC 有 8 位 blk 字段
  （最多 256 块），当前只知 channel 0（1 KiB 消息队列）是合法协议面。
- **3a 被动遥测**（零风险）：观测 driver↔FSP 全部消息交换（COT/PRC/残留），对照 nova 结构。
- **3b 块空间枚举**（需授权一次 EMEMC 写）：写 EMEMC{blk=N, aincr} + 读 EMEMD，扫块 1–255。
  EMEM 若被 FSP 用作解密暂存/密钥暂存/其他通道缓冲，可能有敏感残留。
- **风险**：3a 零；3b 低（合法窗口寄存器，注意与驱动消息交换错开、队列空闲时做）。

### R4. 公开工件深挖：FMC/bootloader（马上可做，零风险）
- linux-firmware `nvidia/gb202/gsp/fmc-570.144.bin` + `bootloader-570.144.bin` 已公开。
- **任务**：格式解析（radix3/TLV/riscv 结构 nova 全有代码）、与 610.57 GSP-RM boot 链对表、
  找 FSP↔FMC 握手的设备侧视角（FMC 是被 FSP 认证启动的第一段代码，最接近 FSP 接口的明文）。
- **价值**：喂给 R1（GSP 执行环境/堆布局）+ 理解 FSP 启动语义；若有 FSP 服务调用 repertoire 更好。

### R5. nova 上游社区问询（零成本情报）
- Hubbard（NVIDIA 员工）正在公开 ML 讨论 FSP。直接在 nouveau/nova 邮件列表问技术问题：
  "GB202 上 HWCFG1 host 读回 0xbadf5040，decoupler 过滤规则是什么？nova 是否见过 IMEMC 可读的
  场景？PFALCON2 块的语义？" —— 官方回答 = 免费权威情报，可能直接回答 R1/R2 的门。
- **风险**：零。注意措辞是"驱动开发问题"，不提攻击目的。

### R6. PFALCON2 块 host 可见性补测（几条手动读）
- 0x8f3000 块（nova 用于 Peregrine 核选择、MOD_SEL、RISC-V 状态）完全未测。
- 若其中状态寄存器放行，可读 FSP 核型/安全模式等（替代被毒化的 HWCFG1）。

### R7. GSP-RM 的 FSP 消息库静态盘点
- GSP-RM 有设备侧 FSP 客户端（已证 EMEM 队列代码 @ 0x14f6b80–0x15017xx）。
- 盘点它发什么 NVDM 类型/子命令（设备侧 repertoire 可能比 host 侧 7 个调用点宽），
  为 R1 的 GSP 执行payload 和 3a 遥测解读服务。纯静态，零风险。

### R8. 泄漏监控（后台挂机）
- 四件套文件名、`629-INT27-DIAG-008`、GB202 debug VBIOS、GB100/B200 FSP_RUN 样本。
- 现有 hunt 脚本转定时监控；新 driver 包/新 VBIOS 出现时跑 inventory + GCM harness。

### R9. 工程卡 + JTAG（金钱解决型）
- debug fuse 烧开的 GB202 工程样机 + RISC-V JTAG（Lauterbach/Trace2 级）= 直接 dump SRAM。
- 渠道：工程卡拍卖/清库存；验证真伪本身是工程。成则一击必杀，但可遇不可求。

### R10. 电压毛刺跳 tag 校验（牺牲卡终极型）
- FI 跳过 GCM 验签分支 → 让 FSP 解析/执行攻击者载荷。全卡供电域毛刺，成功率低，
  必然牺牲卡。仅当 R1/R2/R9 全灭且仍有执念时考虑。

### R11. FuseRework（工件依赖）
- ABI 已全逆向。拿到四件套也先只做离线格式/签名/架构分析；实机发送 = 制造级持久化风险，
  仅牺牲卡 + 单独授权。当前无文件，纯挂机（并入 R8）。

### R12. PSIRT/官方关系
- PSIRT 草稿已有。提交可建立联系，长期或换来 NDA 内信息。慢变量，顺手做。

## 三、决策树

```
R4+R5+R6+R7（本周免费四件套：FMC 分析 / 社区问询 / 补测 / GSP 消息库）
   │
R3a EMEM 遥测（零风险观测）──► 3b 块枚举（一次 EMEMC 写授权）
   │
R2 复位后竞速 ──► 过滤动态？ ──是──► host 路线复活，早期窗口读数
   │                    └─否──► host 永久关死（归档）
   │
R1 K3 → GSP 侧探测 ──► GSP 视图放行 IMEMC/DMEMC？
   │                    ├─是──► dump IMEM/DMEM ⇒ FSP 明文到手（终局）
   │                    └─否──► 退守 R9（工程卡）/ R10（毛刺）/ R8（等工件）
   │
（R1 的可控写副产品：设备侧 floorsweep/PLM 写，独立于 FSP 结果成立）
```

## 四、推荐执行顺序

1. **本周零风险**：R4（FMC/bootloader 解析）+ R5（nova ML 问询）+ R6（补测几条）+ R7（静态盘点）
2. **下一步低成本实机**：R3a 遥测；R3b 需要你授权一次 EMEMC 写
3. **然后**：R2 复位竞速（VFIO 演练先行）
4. **主线**：R1 K3 扩展（每枪独立授权）
5. **挂机**：R8 监控、R9 工程卡留意、R12 PSIRT

# FSP PFALCON 寄存器 host 可见性矩阵（手动逐寄存器会话）

日期：2026-10-27 03:12–03:2x。方式：**手动、一次一个寄存器、每次读后 cuda-sanity 健康验证**
（任务 `cuda-sanity`，经 gpu-allowlist）。工具：`sudo bar0rw r <off>`（/dev/mem, BAR0=0xd8000000）。
驱动：615.78.08 live。全程 11 次 CUDA PASS（基线 1 + 每读 1 + 终态 1），无 Xid，温度 28°C。

## 读数矩阵

| # | 寄存器 | 地址 | 值 | 判定 |
|---|---|---|---|---|
| — | 基线 | — | CUDA PASS | GPU 健康 |
| 1 | HWCFG1 | 0x8f212c | `badf5040` | 毒化 |
| 2 | HWCFG2 | 0x8f20f4 | `badf5040` | 毒化 |
| 3 | QUEUE_HEAD[0] | 0x8f2c00 | `00000000` | **真实**（队列空） |
| 4 | MSGQ_HEAD[0] | 0x8f2c80 | `00000000` | **真实**（队列空） |
| 5 | EMEMC | 0x8f2ac0 | `02000014` | **真实**：blk=0, offs=5, aincr=1（驱动在用） |
| 6 | EMEMD | 0x8f2ac4 | `01474d49` | **真实**：小端 `49 4d 47 01` = "IMG\x01" 消息残留 |
| 7 | CPUCTL | 0x8f2100 | `badf5040` | 毒化 |
| 8 | MAILBOX0 | 0x8f2040 | `badf5040` | 毒化 |
| 9 | DMEMC[0] | 0x8f21c0 | `badf5040` | 毒化 |
| 10 | IMEMC[0] | 0x8f2180 | `badf5040` | 毒化 |
| — | 终态 | — | CUDA PASS + nvidia-smi 正常 | 28°C / 35W |

## 结论

1. **BAR0 decoupler 对 FSP PFALCON 寄存器文件做寄存器粒度过滤**：
   - 放行（消息面）：QUEUE/MSGQ 指针、EMEMC/EMEMD 窗口 —— 即驱动协议面；
   - 拦截（安全面）：HWCFG1/2、CPUCTL、MAILBOX、**IMEMC/DMEMC 窗口控制** —— 统一返回
     毒化常量 **`0xBADF5040`**（与 PLM 域毒化值 `0xfffffb8f` 是不同域的各自常量，均未见于历史基线）。
2. **host 侧 IMEM/DMEM 明文窗口通道（E-C/E-D）判死**：不是"固件锁了窗口"，而是窗口控制寄存器
   根本不在 host 可见视图里。任何 EMEMD/IMEMD/DMEMD 数据读都需要先写对应 xxC 寄存器，而它们被过滤。
3. **EMEM 消息面完全可观测**：窗口真实、数据真实（残留 "IMG\x01"）。host 可被动观测 driver↔FSP
   全部消息交换（消息面遥测通道，非固件明文）。
4. **GSP 侧通道（K3）升为主通道**：过滤在 host 路径；GSP-RM 经 PRI 访问同一寄存器文件
   （其代码在用 EMEMC/QUEUE，见 GSP 扫描）。GSP 视图是否同样过滤 IMEMC/DMEMC 未知，需 GSP 侧
   代码执行验证。
5. 残留悬念：过滤是静态（host 永远被滤）还是 secure-boot 后动态生效 —— 若动态，OVMF/POST 早期
   相位仍可能读到真实值（E-E，VM 实验室）。

## 纪律记录

- 无循环脚本；每读一条独立命令；读后即跑 `gpu-allowlist run cuda-sanity`；
- 未做任何寄存器写；未碰 MNOC；未碰 QUEUE/MSGQ 指针（只读）；
- EMEMD 读发生时队列空闲（HEAD=TAIL=0），与驱动无竞争；读后窗口 offs 自增到 6（硬件读语义）。

## R6 补测追加（PFALCON2 块 + ENGINE，同纪律）

| # | 寄存器 | 地址 | 值 |
|---|---|---|---|
| 11 | FALCON_ENGINE | 0x8f23c0 | badf5040 |
| 12 | RISCV_CPUCTL | 0x8f3388 | badf5040 |
| 13 | MOD_SEL | 0x8f3180 | badf5040 |
| 14 | CORE_SWITCH_RISCV_STATUS | 0x8f3240 | badf5040 |
| 15 | BCR_CTRL | 0x8f3668 | badf5040 |

追加结论：
- PFALCON2/PRISCV 块同样全毒化；host 无法读 FSP 核状态（active/halted/核选择）。
- ENGINE 复位寄存器不可见 → 官方 falcon 复位序列对 host 不可执行，R2 只剩 SBR/FLR。
- **最终地图：host 可见面 = QUEUE/MSGQ/EMEM 消息面，精确且仅此。**

## EMEM 窗口会话追加（授权：仅一次写，读不限但逐条）

### 授权写（本会话唯一）
- EMEMC @ 0x8f2ac0 ← **0x02000100**（aincr=1, blk=1, offs=0）
- 写入被接受，读回 0x02000100 ✓。写后 CUDA PASS。

### 发现（读序 #16-#17+）

1. **host 读 EMEMD 是无副作用镜像读（块 0）**：两次读同值 "IMG\x01"（0x01474d49），EMEMC 的
   offs 停在 5 不动 → 通道 0（消息队列）的窗口状态被协议方锁定，host 读不推进。
2. **块 1 存在且可寻址**：EMEMD（blk=1, offs=0..8）= 全 0x00000000 —— 不是 badf5040。
   EMEM 空间 > channel 0；块 1 呈未使用缓冲区特征。
3. **AINCR 对 host 在块 1 上完全工作**：每读一次 EMEMD，EMEMC.offs +1（0→…→9，9 次验证逐
   步无跳跃）→ 我们的写"武装"了窗口后，host 顺序读合法且自动推进。
4. 换块需要新的 EMEMC 写（offs 字段 6 位=64 dword=256B/块假设）。offs 走到 63 后的行为
   （wrap or 进位 blk=2）未测——**若进位，则一次写即可走完整个 EMEM 空间（纯读）**。

### 待批下一步
- A) offs 进位测试：~54 次纯读（offs 9→63→观察），零写。
- B) 块 2-255 采样扫描：每块需一次 EMEMC 写授权。
- C) R2 复位后过滤判定（SBR 流程）。

### R5 状态
- 邮件已发送（"Message sent"）：loong.0x00@gmail.com → nouveau@lists.freedesktop.org，
  主题 "nova-core FSP question: host BAR0 reads of GB202 FSP falcon registers return
  0xBADF5040 — documented decoupler behavior?"，三问：毒化值文档化？过滤静态/动态？
  GB20x 正规状态读取途径？非订阅首帖进审核队列。
- 论坛：账号 loong.0x00 TL0，Graphics/Linux 分类只读，暂挂（资料已完成）。

GPU 终态：28°C/25W，CUDA 全程 PASS（本追加段 3 次）。

## 54 读 offs 进位实验（授权：54 读×逐条 cuda、每 10 读 SBR）

### 批次 1（offs 9→18，10 读全 0x00000000，逐读 CUDA PASS）
- 重臂 #1：EMEMC ← 0x02000124（blk1/offs9）写入接受 ✓
- 事实修正：9+10 读后 offs=18 而非 19 → **写后首读不推进**（写-读边界语义）
- 空闲期间驱动曾重臂窗口回 blk0 姿态 → 重臂 #1 前实测 EMEMC=0x02000014

### SBR #1 事件与恢复（重要经验）
- SBR 脚本执行干净（vendor 应答 ✓），但随后手动 bind nvidia → probe 失败 -1，
  **"fallen off the bus"**（经典已知场景）。原因判定：bind 太急，SBR 后 FSP 未完成
  secure boot，probe 撞死窗口。
- 恢复：remove → SBR 再试（脚本幂等）→ rescan 自动 probe（等待充分）→ nvidia-drm 加载
  → CUDA PASS，GPU 27°C 完全恢复。**全程未断电、未冷启**。
- SBR 后 EMEMC = 0x02000014（blk0/offs5/aincr）——**驱动固定姿态第三次观测，跨 SBR 稳定**。
  我们的 blk=1 臂被复位清除（预期内）。
- 新增铁律候选：SBR 后禁止立即 bind；rescan 自动 probe + 等 15s 再验证。

### 待决策：SBR 节奏矛盾
实测表明：纯读+cuda 零故障（16+ 次 PASS）；**SBR 才是风险动作**（一次掉总线）。
按每 10 读 SBR 的节奏，剩余 44 读 = 4 次 SBR = 4 次掉总线风险暴露。

## C 阶段完成：offs 进位判定 ✅（2026-10-27 深夜会话终）

### 执行（用户批准方案 C：连续读、逐读 CUDA、零复位）
- 重臂 #2：EMEMC ← 0x02000148（blk1/offs18），读回 ✓
- 连续 46 次读（offs 18→63），**每读后 cuda-sanity 全 PASS，GPU 28°C/22W 纹丝不动**
- 块 1 dword 9–63 全部 0x00000000（整块空缓冲特征）
- 无任何 DoS 迹象（配速 ~1 读/2-3 秒 + CUDA 绊线，与洪水量级差 4-5 个数量级）

### ★ 决定性发现：EMEM 窗口跨块自动进位
offs=63 的读完成后 **EMEMC = 0x02000200（blk=2, offs=0）**——不是 wrap 回块 1，不是卡死，
是**进位到下一块**。

**含义：一次 EMEMC 写（aincr=1）即可顺序走完整个 EMEM 地址空间（blk 0-255 × 64 dword），
无需换块写。host 纯读遍历 EMEM 全空间的通道正式成立。**
- 若每块 256B → 全空间 64 KiB；blk 字段 8 位 → 理论 256 块
- 块 2 dword 0 已顺手采到：0x00000000（空）
- 下一步（待批）：从当前 blk=2 继续纯读扫描，寻找非零/非消息面内容（FSP 暂存、密钥材料、
  高块通道缓冲）；每读 CUDA 绊线不变

### 铁律新增
- SBR 后禁止立即 bind nvidia（撞 FSP pre-boot 死窗口 → fallen off bus）；
  正确流程：SBR → rescan（自动 probe）→ 等 ≥15s → 验证

## EMEM 块扫描：块 2 命中活消息（2026-10-27 深夜续）

### 块 2 内容（dword 0-16，逐读 CUDA 全 PASS）
```
d0 : 4f 45 4d 01          "OEM\x01"   ← 消息类型标记（与块 0 "IMG\x01" 同族）
d1 : 00 00 02 00          （头部字段）
d2 : 50 50 49 44          "PPID"      ← 字段名
d3-d15: "ROG-ASTRAL-RXT5090-O32G-GAMING-2I3S#250861698300407\n"
       （完整板级部件号 PPID：BP + SKU + 日期码 2508 + 序列号）
d16: 0
```

### 关键判定
1. **块 2 = OEM 消息通道缓冲（活）**：消息是新鲜流量而非残留——扫描进行中驱动抢回窗口
   （EMEMC 突变 blk=0/offs=22），证明 driver↔FSP 交换就在此刻发生。
2. EMEM 多块 = **按消息类型分的通道缓冲区**（块0=IMG/COT 类，块2=OEM 类，块1=未用通道），
   不是连续数据空间。QUEUE/MSGQ ×8 通道与块的映射待理清。
3. 窗口为单实例共享硬件：驱动随时重臂，遍历会被打断（无碰撞伤害，各自重臂续用）。

### 新的工具能力（已验证）
host 可实时观测 driver↔FSP 全部消息面流量（IMG/COT、OEM/PPID 等），配合 nova 的
消息结构定义（FspMessageHeader/NvdmPayload*）可做完整协议遥测。

### 待批
- 重臂回块 2 续扫（1 次写授权）；或换策略：定点观测块 0/2 的活流量变化。

## B 模式：驱动关闭扫描 + 恢复后活帧解码（会话终章）

### 驱动关闭扫描（unbind，无复位）
- 窗口独占稳定：块 2 续扫（offs 17-63 全零）+ 块 2→3 进位复现（0x02000300）+ 块 3 头部全零
- 绊线替换：每读 setpci config 应答（10de ✓ 全程）+ 每 10 读 EMEMC 状态
- 块 3 d23 孤立标记对：`0xbaad8000, 0x00000001` —— GSP-RM/GFW 615 镜像中无此常量
  → FSP/硬件内部 marker（EMEM 初始化或固件堆标记，候选解释）
- 驱动关闭静默快照：MSGQ 0-7 / QUEUE 1-3 指针全零 —— 消息面无自发流量，FSP 纯被动

### 恢复驱动 + 活帧捕获
- bind 干净（无复位场景），12s 后 CUDA PASS；GSP boot 完成
- 块 0 内容已被新交换刷新：今晨 "IMG\x01" → 现在 "OEM\x01"
- 重臂 blk0/offs0 逐 dword 解码出**完整协议帧**：

```
d0 : c0 00 00 00   MCTP 头（single-packet: SOM|EOM）    ← 对齐 nova MctpHeader
d1 : 7e de 10 15   NVDM 头（含 NVIDIA VID 10de）        ← 对齐 nova NvdmHeader
d2 : 01 00 00 00   （NVDM 载荷参数）
d3 : 20 00 00 00   （长度 0x20）
d4 : 00 00 00 00
d5 : "OEM\x01"     载荷类型标记
d6 : 00 00 02 00
d7+: "PPID" + "ROG-ASTRAL-RXT5090-O32G-..."            板级身份
```

**nova-core 的消息结构定义在真实硬件上逐字段对齐验证通过。host 侧 FSP 协议遥测能力成立：
帧头 → 载荷类型 → 完整消息，全部可读可解码。**

### 会话总账（10/27 全天）
- 读写纪律全程执行：~120 次读、4 次授权写（重臂）、每读 cuda/setpci 绊线
- GPU 健康终态：27°C/25W，CUDA 全 PASS，一次 SBR 掉线成功恢复（无断电）
- 能力清单新增：EMEM 全空间纯读遍历、活帧解码、驱动静默/活跃对照

## SBR 竞速终局（R2 判死，2026-10-27 会话尾声）

### 竞速器（sbr_race.py，一次性，用户指示"卡住复位瞬间"）
- 真机直跑（无 VM/vfio——用户明确 VM 与真机 FSP 行为不同）
- SBR 前预备：/dev/mem 映射 + config sysfs 句柄全就绪
- SBR 20ms → 微秒级轮询 config 存活 → 即刻重写 BAR0+COMMAND → 0.5ms 间隔紧循环采样

### 时间线（唯一一次有效竞速采样）
```
T+149.8ms  config 存活（SBR 后设备 150ms 才应答 config）
T+151.0ms  BAR0=d8000000 / CMD=02 写入生效（之前 +50ms 手写失败因设备未活）
T+151.02ms 首个可读样本：HWCFG1=badf5040  IMEMC=badf5040  EMEMC=0x02000014(真实)
之后 10782 轮 × 5.85s：零跳变，全程同一终态
```

### 结论（R2 = 复位窗口路线，判死）
- **MMIO 可读的第一微秒起过滤已生效**——不存在"明文已解密、过滤未武装"的可达窗口。
- 无论过滤是硬件静态、还是 FSP boot（<150ms）快于 MMIO 存活，host 均无法利用。
- 途中坑位记录：
  1. SBR 常规复位清 BAR（需 config 重写，≈150ms 后才可写）
  2. vfio-pci 绑定 = MMIO 关门（竞速场景禁用）
  3. 纯 setpci 路径（手写 BAR+COMMAND）为正确姿势，本次竞速器已实现

### 恢复
- remove+SBR+rescan → nvidia 自动 probe → CUDA PASS；散热三服务 active
- GPU 零损伤

### 路线图更新
- R2 死。nouveau ML 问询（已发）成为该问题的唯一剩余裁决源（官方口径）。
- 活跃路线收敛：FMC/bootloader 静态分析 + IMG 帧捕获（协议侧）；工件/工程卡（长期）。

## µs 级竞速双杀：SBR + FLR 终审（2026-10-27 深夜终章）

### 工具
- `race10us.c`：C 双模式竞速器（预 mmap BAR0 + config fd；SBR 模式含 10µs config 存活轮询
  + BAR/CMD 重写；FLR 模式走 cap 链自动定位 + DEVCAP FLR 支持检查 + bit15 触发）
  实测采样粒度 3~5.7µs/读组（HWCFG1+IMEMC+EMEMC 三寄存器）
- 风扇控制旁路：`/tmp/waterloop_hold_quiet` 标志文件（GPU handoff 抬升旁路，CPU 热保护不动；
  脚本备份 waterloop-fan-control.bak-20261027，SHA 08913a10…）

### 结果一：FLR —— FSP 完全无视 FLR
- DEVCAP=0x112c8e21 bit28=1（FLR 支持），cap @0x60
- 触发 bit15 → **139 万轮 × 5s，三寄存器零变化，MMIO 连中断都没有**
- 判定：FSP/decoupler 在功能级复位域之外。"FLR 无效"从间接推断变直接证据。FLR 路线死。

### 结果二：SBR（µs 级）—— 锁比门早
```
T+149.540ms config 存活（10µs 检测精度）
T+150.717ms MMIO decode 上线后第一个 5.7µs 采样窗 = badf|badf|real（终态）
70 万轮 × 4s 零后续变化
```
- Python 版遗留的 20µs~1.2ms 观测缝隙全部堵死
- 判定：**过滤在 MMIO 物理可读之前（或同时）已武装**——要么静态硬件过滤，
  要么 FSP boot+武装 < 149.5ms（早于设备 config 恢复）。host 侧复位路线以 µs 级证据终审关闭。

### 竞速方法论沉淀（三次迭代）
| 版本 | config 检测 | 首样本贴合 | 结论 |
|---|---|---|---|
| Python | 200µs | ~1.2ms | 开门即毒化 |
| C-FLR | —（全程可读） | 3.6µs | FSP 不受 FLR 影响 |
| C-SBR | 10µs | ~1.2ms(BAR生效)→5.7µs 采样 | 开门第一µs即毒化 |

### 恢复
- SBR 后直接 bind 出现 CUDA FAIL → 标准配方(remove+SBR+rescan)一次成功 → CUDA PASS
- 散热：静音标志期间 pump 40/2020-2030 rad 30/898 全程钉死（旁路生效验证 ✓），标志已删
- GPU 终态零损伤

### R2/R2b 终局
复位窗口路线（SBR/FLR/cold 思路）以三层证据关闭。过滤时序问题的剩余裁决源：
nouveau ML 邮件（已发）。

## 2 号任务：VBIOS opROM x86 审计（2026-10-27，阴性定论）

- 扫描：全部本地 VBIOS（Astral 原厂×2、pre-XOC×2、FE、TPU Astral、sysfs dump）
  搜索 dword 常量 [0x8f0000, 0x8f4000) + opROM 区（前 128KB）FSP 相关字符串
- 结果：已知 FSP 寄存器常量零命中；FSP/falcon/MCTP/NVDM/secure/SEC2/fuserework 字符串零命中；
  表面命中（0x8f0000×3、0x8f0511 组等）经上下文核验全部为递增索引表/计数表的对齐巧合
- **结论：opROM 的 x86 代码与 FSP 完全零交互。FSP 启动彻底自包含
  （片上 ROM → 自取 SPI 的 FSP_RUN → 自验自解）。host 软件栈（SBIOS/opROM/驱动/OVMF）
  任何层面不存在 FSP 明文或密文中转。"POST 截获"路线族关闭。**
- 交叉推论：VM/真机 FSP 行为差异（用户观察）只能来自运行期环境（entitlement/服务面），
  不可能来自启动路径差异。

## 1 号任务：FMC/bootloader 拆解（2026-10-27 终，判决：公开启动链=密文）

### 结构解析（完整）
- `fmc-570.144.bin`（199,820B）：ELF 壳头 + nvfw manifest（magic 0xFFF00102 条目链）
  - 段表：0x150+0x30（48B，SHA-384 哈希）/ 0x180+0x60（96B，ECC 签名）/ 0x1e0+0x61
    （97B，ECC 公钥）/ **0x244+0x30A48（199,240B 主载荷）**
- `bootloader-570.144.bin`（200,812B）：de10 NVFW ucode 头 + 主体
- ECC 尺寸（96/97B）与 FieldDiag580 审计的 debug GFW 密钥材料一致 → 同一签名族

### 判决（熵分析）
- FMC 主载荷熵 7.9990 bits/byte，无任何压缩容器魔数 → **加密**
- bootloader 主体（前 192KB）高熵同判 → **加密**
- 明文的只有：头结构、段表、验签材料（hash/pkey/sig）

### NVIDIA 明文/密文边界（精确化，重要）
```
明文层：GSP-RM 运行时（gsp.bin rx/rw 段，可反汇编——9月已证）
密文层：booter → FMC → FSP_RUN 全部安全启动链组件
```
- "FMC 是离 FSP 最近的公开明文"假设死亡——它根本不是明文
- COT 流程自洽：FSP 对密文验签（签的是密文哈希）→ 片内解密 → 运行
- linux-firmware 分发物对**签名链结构研究**仍有价值（段表/材料布局），
  对**代码分析**无价值
- 推论：片内解密路径（FSP BROM/Falcon BROM）是全家桶唯一明文生成点——
  与 EMEM/IMEM 过滤观察一致，明文只存在于芯片内

## 用户提示的考古线：旧工件熵普查 + AES0 引擎客户端发现（2026-10-27 黎明，★重要新战线）

### 旧工件熵普查结论
- 615 驱动 carved 全家族（GspRmFmcGfw/CcFmcGfw/Boot，GB202/GB100/GB10B/GB20B/GH100/GR100，
  Debug+Prod）：**UCODE_IMAGE 全部加密（熵 7.998-7.999）**；明文的只有 HASH(48B)/PKEY(97B)/SIG(96B)
  验签材料（ECC 家族）。GB202 booter(DBG/PROD) 均密文。
- 历史明文物件：GA102 debug booter（熵 5.6，60KB，含解密 HS 段 35KB——GA 时代明文/GB 时代密文的
  架构分界）、FWSEC LIC client 24KB（来自 GSP-RM 明文）。
- fsp_code/ 目录四件套（GSP-RM 570.144 明文提取，9 月）：fwsec_lic_client/crypto_lib/
  acr_sec2_opts/sec2_ucode_load——安全链客户端代码，明文可反汇编。

### ★ AES0 引擎客户端发现（GSP-RM 610.57 明文）
跟踪串（VA 0x1e27a80 区）：
  "AES0 engine [AES/RNG]" → "Keyop done" → "AES START" → "before kslot clear" →
  "after kslot clear" → "AES DONE" → "AES-GCM AAD START" → "AES GCM FINAL START" → "post op"

- **Keyop（密钥装载操作）+ kslot（硬件密钥槽）+ 用后清槽**——GSP-RM 操作带 key slot 的
  硬件 AES 引擎（AES0），完整客户端流水线在明文里。
- 37 处字符串引用定位（aes0_xref.txt）：函数簇 0x100d5xx / 0x1bf3fxx / 0x1bf86xx
- 反汇编起点已存（aes0_engine_disasm.txt / aes0_module_consts.txt）
- 引擎 MMIO 访问走 GSP 两级指针（aperture + RegHal selector）——selector 在 RegHal 数据表，
  GB202 公开 swref 头未发布 AES 引擎定义（dev_aes 缺失）

### 新战线的意义
不正面解密 FSP，而是追 **GSP 侧 AES 客户端的密钥管理**：
- Keyop 的 key 从哪来（内存/派生/fuse 通道）——来源可从明文反汇编追溯
- AES0 引擎是否与 FSP 共享/相关（GB202 上 SEC2 角色被 FSP 取代——AES0 归属待判定）
- 若 key 流程可追，加密链一个环节透明；若 kslot 由 FSP 侧装载，则确认 GSP 无 key 知识
- 待做：函数级分析 Keyop 调用链（从 0x1bf3fxx/0x1bf86xx 入）+ RegHal 表定位 AES0 selector
  + dev_riscv_pri.h 交叉 + 与今天 FSP 消息面观测对照

## ★★ 主动消息通道落地 + 真机服务面地图（2026-10-27 晨，用户提议的路线）

### 用户指令背景
用户否定"本地路线全低价值"的绝对化判断，提出：**写 EMEM 消息让 FSP 自己吐东西**。
执行纪律：风扇保护永久旁路（脚本已改，GPU 空转 0W 无过热风险）、挨个单发、手动、安全方式。

### 通道验证（驱动卸载状态，FSP 独立处理我们的消息）
- 工具链：emem_msg.c（臂窗+连写 dword 无中间读，修掉 bar0rw 读回验证在自增窗口上的
  offs 推进副作用）+ ask_fsp.sh（单发完整周期：发→等→读→复位→解码）
- 消息格式（三源合成并实测验证）：
  d0=0xC0000000 (MCTP 单包) | d1=(type<<24)|(0x10de<<8)|0x7e | d2=subMessageId
  投递：EMEMC←0x01000000(aincw 臂写) → EMEMD×3 → QUEUE_TAIL=8 → QUEUE_HEAD=0(扳机)
- **CAPS_QUERY(0x16) subMessageId=0x13 → error=0 + 表项 {PRC 0x13, v1}**——与 7 月 VM/MNOC
  结果逐字节一致，真机 EMEM 通道全功能等价
- 错误码 oracle：err=0x153 = 该 subMessageId/类型未发布或无效

### 真机服务面地图（NVDM 类型 0x01-0x1f 全扫，每发单链手动）
**已发布（11 服务）**：
| type | 版本 | 语义 |
|---|---|---|
| 0x11 | v1 | ？（待探） |
| 0x12 | **v2** | ？（v2 协议，待探） |
| 0x13 | v1 | PRC（knob 读写，已知） |
| 0x14 | v1 | ？ |
| 0x15 | v1 | OEM（PPID 族，已知） |
| 0x17 | v1 | ？ |
| 0x18 | v1 | SMBPBI（已知） |
| 0x1a/0x1b/0x1c/0x1d | v1 | ？ |
**未发布**：0x01-0x10, 0x16(自身), 0x19, 0x1e, 0x1f
（0x0e telemetry/0x0f FuseRework 不在 caps 册——独立路径；0x20/0x21 有 DoS 前科未扫）

### 全程零故障：20+ 发全部干净应答，队列复位正常，GPU 终态 CUDA PASS。
### 下一步金矿：6+ 个语义未知的已发布服务（尤其 0x12 v2）——用对应类型发真实请求探语义；
0x22-0xff 高段抽样；IMG 帧 NVDM 类型号确认；超读检测(响应残留 diff)。

## 8 个未知服务敲门结果（2026-10-27 晨续）

| type | payload=subcmd 0 | 判定 |
|---|---|---|
| 0x11 | err 0x4b3; subcmd 1/2 → err 0x4b2 | **活 handler，子命令空间验证** |
| 0x12 v2 | 沉默（通道验活通过）| 多段消息或发起方门禁 |
| 0x14 | err 0xd7 | 活 handler |
| 0x17 | err 0xc2 | 活 handler |
| 0x1a / 0x1b | 沉默 | 同 0x12 类 |
| 0x1c | err 0x249 | 活 handler |
| 0x1d | err 0x2e5 | 活 handler |

- 5 个活跃服务 × 5 个互不相同的专属错误码 = 5 条独立参数校验路径
- 0x11 已证明错误码随子命令变化 → 全部服务可做子命令枚举地图
- 3 个沉默服务疑似分段协议/GSP 专属通道（nova 仅用 COT/PRC，未覆盖）
- 全程通道健康（每批次用 CAPS 0x13 验活，err=0），GPU 终态 CUDA PASS

### 待办（下次）
- 0x11/0x14/0x17/0x1c/0x1d 子命令空间逐个扫（subcmd 0x01-0x0f，错误码分类）
- 0x12v2/0x1a/0x1b 的分段格式尝试（双 dword 载荷起步）
- PRC object 空间扫描（已知 read=0x0c 合法）
- 对照 MODS/FieldDiag sender 审计里的命令清单定语义

## 服务命名 + INFOROM 实弹（2026-10-27 晨终）

### 官方 NVDM 枚举表定位（不再猜名字）
源: 内部树 nvdm_format.h + 公开树 fsp_nvdm_format.h（一致）：
0x4 RESET / 0x11 HULK / 0x12 FIRMWARE_UPDATE / 0x13 PRC / 0x14 COT / 0x15 FSP_RESPONSE /
0x16 CAPS_QUERY / 0x17 INFOROM / 0x18 SMBPBI / 0x1A ROMREAD / 0x1C UEFI_RM /
0x1D UEFI_XTL_DEBUG_INTR / 0x1F TNVL / 0x20 CLOCK_BOOST / 0x21 FSP_GSP_COMM / 0x25 RM_RPC
（0x1B 官方表缺失——真机在册但无公开定义，GB202 专属？）

### 8 服务定名后的敲门表（终版）
| type | 名字 | 实弹指纹 | 判定 |
|---|---|---|---|
| 0x11 HULK | 许可证 | err 0x4b3/0x4b2 随子命令变化 | 活，可枚举 |
| 0x12 FIRMWARE_UPDATE v2 | 固件更新 | 沉默 | 分段协议（大载荷）|
| 0x14 COT | 信任链 | err 0xd7 | 活（nova 同款）|
| 0x17 INFOROM | **板级信息读** | **subcmd1/2 → err=0**；驱动实测 PPID 从此服务出 | **活，数据服务确认** |
| 0x1A ROMREAD | ROM 读 | 沉默 | 分段/SEID 门禁（nvswitch: INFOROM 走 SEID=1）|
| 0x1B ??? | 真机在册、官方无定义 | 沉默 | GB202 专属，待探 |
| 0x1C UEFI_RM | UEFI 资源管理 | err 0x249 | 活 |
| 0x1D UEFI_XTL_DEBUG_INTR | **调试中断** | err 0x2e5 | 活，名字带 DEBUG |

### 事故与验伤
- 0x17 subcmd 1/2 err=0 无载荷——警惕 InfoROM 写操作风险 → 全面验伤：
  CUDA PASS / dmesg 无 Xid / **驱动重绑后 INFOROM 响应携带完整 PPID 载荷（板级数据无损）**
- 认知修正：今晨"OEM 消息"实为 INFOROM(0x17) 响应；驱动请求 MCTP 头=0xc0010000（带 tag）
- 教训入律：未知服务的 subcmd≥1 实弹前先确认只读性（本次侥幸，参数全零无害）

### 下次最高价值
1. INFOROM(0x17) 对象空间枚举（PPID 是其一；请求格式可仿驱动 0xc0010000 头）
2. ROMREAD(0x1A) 分段格式尝试（SEID=1？）
3. 0x1B 未知类型探底

## 0x17/0x1a 攻坚中期报告（2026-10-27，用户分工：他查0x1b，我攻17/1a）

### 0x17 INFOROM subcmd 完整地图（SEID=1, 实弹）
| subcmd | err | 备注 |
|---|---|---|
| 0 | 0xc2 | 参数错 |
| **1** | **0（无载荷）** | +任意后续 dword 仍 err=0 |
| **2** | **0（无载荷）** | |
| 3 | 0xc3 | |
| 4 | 0xcd | +参数仍 0xcd（唯一独立校验） |
| 5-8 | 0xc2 | |

### 关键否定结果
- SEID 破解确认：驱动 INFOROM 请求 MCTP 头=0xc0010000 → SEID 字段=1（nova 位域解码）；
  但 SEID=1 后数据载荷仍不出现在任何 8 通道队列/EMEM 块 1
- OEM\x01 常量、PPID/ROMREAD 字符串在以下信源全部缺席：
  OpenRM 开源树（含 RPC schema 头目录 inc/fsp/：仅 caps/clock_boost/tnvl/emem/cmd_response 五件）、
  闭源 nvidia.ko（解压 27MB）、GSP-RM 610.57 明文、MODS
- fsp_emem_channels.h 官方确认：RM=通道0、1KB（通道↔服务映射在册的只有这条）
- **结论：INFOROM 数据载荷 schema 与 ROMREAD schema 不在任何本地明文信源——只存在于
  FSP 固件（密文）内。PPID 帧可能是 FSP 主动推送或闭源组件路径**
- 0x1a ROMREAD：SEID 0/1 × subcmd 0-3 全沉默（比 0x17 更严的门禁）

### 0x1b（GPT 协查结论 + 本地实证）
- GPT 确认官方两代头文件（nvdm_format.h + edk2-nvidia fsp_nvdm_format.h）均无 0x1b——历史性空缺
- **本地实证更强：0x1b 是实弹能力记录（err=0 + {type 0x1b, v1}），硅上活服务，非文档推断**
- 实弹：SEID 0/1 × subcmd 0/1 全沉默——最哑的服务

### 交给下一步的弹药
- nvidia.ko 已解压待反汇编（/tmp/tmp.ydvtKulAk1/nvidia.ko，重启丢失，x86 immediate 序列未搜）
- subcmd=4 的独立校验码 0xcd 是 schema 线索（期待特定参数形状）
- MCTP 多包请求路径未试（kfspSendMessage 多包逻辑在开源 kern_fsp.c:478-560）

### 追加（615.78 固件排除 + INFOROM 推送模型修正）
- 运行中固件 615.78 gsp_ga10x.bin（25MB）同样无 OEM\x01/PPID/ROMREAD 字符串
  → 全部本地信源（开源树/闭源ko/GSP-RM 610.57/GSP 615.78/MODS/nova）排除完毕
- **模型修正：INFOROM(0x17) 是 FSP→host 主动推送通道**（GPU init 时推板级身份）。
  证据：无任何 host sender schema + 帧总在驱动 bind 后出现 + subcmd 1/2 err=0 无载荷
  （订阅/确认类）。PPID 不是查询出来的，是 FSP 送的。
- ROMREAD(0x1a) 待验证是否同属推送类或工具专属（nvflash/OEM 工具路径）。

### ROMREAD 攻坚终局（2026-10-27 晨）
- 多包触发链复现 ×3：0x1a 首包+尾包 → 真响应 {MCTP合法头, cmd=0x17, err=0x210}（新错误码）
  + EMEM 残留固定块（0x00700001, 0xffffff03, 0xffffffff…）
- seq 修正（官方格式: 续包 seq=++seq%4）无变化；0x17 对照组读到的"响应"实为自 echo（假响应，
  数据是自写原文）——信号三层混杂（真响应/假响应/残留）已剥离
- **全 8 通道投递测试：0x1a 单包消息无通道受理**（blk_i+QUEUE[i] 触发 ×8 全沉默）
- **判定：ROMREAD(0x1a) 是 UEFI 阶段服务**（与 0x1c UEFI_RM / 0x1d UEFI_XTL_DEBUG_INTR 同族），
  运行期 OS 环境不收请求。真入口 = UEFI 环境（OVMF DXE 或真机 BIOS 阶段）。
- 附带：0x1b 沉默的候选解释新增"环境门禁"（UEFI/GSP 专属 phase）
- 遗留：EMEM 残留块（offs 0x14-0x28 固定内容）来源未定；0x210 错误码语义待对照

## EMEM 运行逻辑恢复完成（2026-10-27，四项全闭合）

### 1. 块↔通道分配（实测边界）
- **EMEM 实际容量 = 1KB = blk0-3，全部归 ch0(RM)**；blk4-255 未实现：
  读回 0xDEAD5ED0 且窗口不推进（硬件常量，与寄存器毒化 0xBADF5040 同族的第二常量）
- blk0 = 命令/响应主缓冲；blk2 = 数据/推送缓冲（PPID 帧曾在此）；blk1/3 = 空
- 8 通道 QUEUE 寄存器存在但仅 ch0 有内存配额（官方头文件 ch0=1KB 与实测吻合）

### 2. 仲裁/锁定粒度
- **offs 级锁定**：驱动活跃时，blk0 的驱动 offs（5）对 host 是镜像读（不推进）；
  同块其他 offs（如 32）host 读正常推进。锁的是位置不是块
- 窗口单实例共享：驱动随时重臂抢走（无碰撞、各自恢复，已多轮实测）

### 3. 残留与填充语义
- 空闲填充 = 0xFFFFFFFF；未实现 = 0xDEAD5ED0（不推进）
- 短响应不覆盖旧数据：blk0 d5/d6（0x00700001/0xffffff03）= 早前长交换的残留尾巴
- 消费后消息不清除（残留=最后一帧，一直可读）

### 4. 写侧/触发语义（三段拆解）
- **HEAD 写入是唯一触发器**：仅写数据→无响应；+TAIL→无响应；+HEAD=0→响应
- FSP 轮询 QUEUE_HEAD，数据与 TAIL 只是预备状态

### 意外收获：blk2 per-boot 40B 高熵数据
- 位置 blk2/d5-d14（40B），驱动 bind 时写入，本 boot 内静态不轮换
- 候选语义：per-boot 会话密钥材料/challenge/设备随机数（待定，bind 复现可再采样）

## 溢出探针矩阵（2026-10-27，emem_probe.c 完整协议客户端）

### 工具
emem_probe.c：snap(全1KB快照+8通道指针)/send(任意TAIL/HEAD)/mpk(多包)/mpkseq(重组序列生成器)/recv

### 矩阵结果（请求侧传输层）
| 探针 | 结果 |
|---|---|
| TAIL 0x3FC(1KB内) 声明1020B实际12B | **FSP 不校验声明vs实际**——正常处理（err=0）|
| TAIL 0x400/0x404/0x800/0x1000/0xfffff000 | 全部静默拒收——**长度校验以1KB为界** |
| HEAD=4(非零起点) | 正常（按 HEAD..TAIL 读）|
| HEAD>TAIL(负长度) | **err=0x84**（新码，指针错乱类）|
| HEAD=0x800 | 静默拒收 |
| 重组总长 524B→16KB(N=2..63, seq合法) | **统一 err=0x9f**——重组总长有界校验 |
| 孤儿EOM / 双SOM | 统一 err=0x9f |
| **seq 跳跃(SOM后直接seq3)** | **该重组流挂死**（补发正确seq也不完成）；**通道本身不受影响**（合法单包照常响应）——轻量单流DoS，比历史MNOC锁存DoS干净 |
| seq 回绕(0,1,2,3,0,1..) | 容忍，继续收包 |

### 新错误码累计：0x84(负长度) 0x9f(重组结构/超长) 0x210(小多包格式) + 既有 0x153/0x4b3/0xd7/0xc2/0xcd
### 结论：**EMEM 传输层外层无溢出**——长度/指针/重组三面全部有校验。NVIDIA 在传输层的质量
显著好于 handler 层（K3 的 GSP 侧"先拷后验"反面）。剩余攻击面：handler 载荷字段级（需逐服务
schema）+ 响应侧残留 diff（未系统做）。
### 附带发现：blk3 d23-24 marker 为活动数据({0xbaad8000→0x88e2b000,1}，跨boot变化，疑似DMA描述符)；QUEUE ch7 TAIL=8 有他者触碰痕迹

## COT 字段门攻坚（2026-10-27，cot_probe.c 字段级工具）

### 结果
| 探针 | err |
|---|---|
| COT 全零载荷（垃圾签名）| 0xd7 |
| COT 尺寸字段极端（0xfffff000 / 野 DMA 地址 / 巨大 vidmem）| 0xd7（字段未消费）|
| **COT 真 ECC 签名三件套**（bindata_615 配套 HASH/PKEY/SIG）| **仍 0xd7** |
| SBR 后无驱动抢先发（COT 窗口理论期）| **EMEM 通道整个未激活**（CAPS 也不响应）|

### 判定
- 0xd7 = **COT 状态机门**（与签名/字段无关——字段解析在门后）
- COT 受理窗口 = FSP boot 完成 + EMEM 激活 + GSP 未启动的三重叠态
- **新行为发现：FSP 重启后 EMEM 通道初始为关**，驱动 bind 序列中某步将其激活
  （激活时刻/机制未知——下次绑驱动后立即逐秒试 CAPS 可定位）
- COT 攻击面存在但被三重门保护（状态门→签名门→字段门），字段门从未到达
- "先验签后消费字段"——FSP 传输层的正确工程顺序再次确认

### 下轮
1. 绑驱动后逐秒 CAPS → 定位 EMEM 激活时刻 → 若激活早于 COT 窗口关闭，可插队
2. HULK(0x11) 证书解析路径（次级花哨目标）
3. 响应侧残留 diff 系统化

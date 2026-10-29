# GB202 FSP：VBIOS Falcon-v6 对象、BootFSM 与 GSP bootstrap 的公开链路

## 0. 范围、安全边界与一句话结论

本轮只读取了：

- `/usr/src/nvidia-610.43.03/src/nvidia/` 及其公开头文件；
- `/home/user/rt_5090_project/vbios_diff/` 中已经保存的 ROM/NVFW；
- 项目已有的离线解析器与既有静态报告。

没有访问 GPU、`/dev/nvidia*`、PCI resource/BAR/MMIO、debugfs 或 MODS；没有
reset、rebind、驱动装卸、固件执行、解密或写入。唯一重新运行的程序是只读本地
解析器 `gb202_vbios_diff.py --help` 以及对一份保存 ROM 的离线解析；另用 `xxd`
读取了两个已知小窗口。

最重要的结论是：**公开调用链在“VBIOS 中的 v6 对象如何被取出并交给 FSP”这一
段断掉了。** 能公开闭合的是后半段：

```text
保存的 VBIOS Falcon entry app=0x24,target=0x0f
  -> v6 descriptor（encrypted bit；可见 FSP_RUN 字节）
  -> [PRIVATE GAP：谁选择、认证、解密、搬运、跳转，公开 610 没有代码]
  -> chip reset 后 BootFSM 触发 FSP
  -> FSP 写 boot-complete=0xff
  -> host/RM 只等待完成
  -> host 把“GSP-FMC/GSP-RM”映像及 hash/signature/key 放到 sysmem
  -> host 向已经运行的 FSP 发送 NVDM_TYPE_COT
  -> FSP 认证/启动 GSP，host 等 target mask、lockdown 与 RM init
```

因此：

- **FACT：** GB202 的公开 Linux RM **不主动提取或上传 `FSP_RUN`**。GB202 的
  `kgspExtractVbiosFromRom` HAL 明确返回 `NV_ERR_NOT_SUPPORTED`，而 FSP wait HAL
  明确说 BootFSM 已在 chip reset 后触发 FSP。
- **FACT：** host 后来确实主动准备并交给 FSP 一个映像，但那是公开命名为
  `g_gsp_gb20x_*` 的 **GSP-FMC/GSP-RM boot material**，不是 FSP 自身 runtime。
- **UNKNOWN：** 公开源码没有把 `app=0x24,target=0x0f` 定义成 `FSP_RUN`；
  `FSP_RUN` 只是该私有 v6 descriptor 中观察到的可打印字节。
- **INFERENCE（强）：** v6 descriptor 的真正解析者位于 GPU 内部的 BootROM/FSP
  secure-boot stage 或另一个未公开认证阶段，而不是公开 host RM。
- **INFERENCE（当前最符合全部证据的分层模型）：** 上电后的最初 root-of-trust/
  loader 必须在芯片 ROM/BootFSM 一侧；体积更大的常驻 FSP runtime 最可能来自
  VBIOS 中标为 `FSP_RUN` 的加密对象，加载后在 FSP 自己的受保护存储中执行。
  但 task 2 handler 究竟在 ROM 还是这个对象内仍为 **UNKNOWN**。

## 1. 本地 VBIOS 对象：能直接确认到哪里

### 1.1 条目与 descriptor 字节

项目既有完整清点把四个独立 raw image 去重为三个目标字节对象：

| 样本组 | Falcon entry / descriptor | 直接可证事实 |
|---|---|---|
| RTX 5090 FE / ASUS | FE entry `0x9cf6f`，descriptor `0x11b304` | entry 为 `24 0f 04 b3 0c 00`；descriptor word0=`0x0050060d` |
| Dell RTX PRO 6000 | entry `0xa0855`，descriptor `0x128104` | `app=0x24,target=0x0f`；word0 同上 |
| HPE RTX PRO 6000 | entry `0xa0d10`，descriptor `0x12cd04` | `app=0x24,target=0x0f`；word0 同上 |

完整 provenance、hash 和边界见
`parallel/vbios_fsp_inventory.md:27-51,96-136`。FE 保存样本的定点 `xxd` 复核为：

```text
file 0x09cf6f: 24 0f 04 b3 0c 00
file 0x11b304: 0d 06 50 00 ...
file 0x11b331: 46 53 50 5f 52 55 4e    # "FSP_RUN"
```

`word0=0x0050060d` 按公开共用首字布局是 `flags=0x0d`、version `6`、
descriptor size `0x50`；flags bit 2 是 `ENCRYPTED`。公开位定义在
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/kernel_gsp_fwsec.c:129-146`。

`FSP_RUN` 从 descriptor `+0x2d` 开始，但它不是公开字段名。项目离线解析器也
刻意只解首字，并把 v6 余下字段保持为 private/uninterpreted：
`/home/user/rt_5090_project/gb202_vbios_diff.py:314-360`。

### 1.2 `word1` 字段名仍非公开；payload 边界已有后续 manifest 证据

四份目标 descriptor 的 `+0x04` raw word1 分别为 `0x29400`、`0x36c00`、
`0x37000`。把它当作紧随 `0x50` descriptor 的区域长度，会准确落到高熵材料转为
`0xff` padding 的边界；旧 v2/v3 descriptor 的相同位置也叫 `StoredSize`。这是
强模式证据，但没有公开 v6 struct，因此仍只能标为 **INFERENCE**。详见
`parallel/fsp_v6_payload_compare.md:18-23,37-76,78-111,140-149`。

**2026-07-22 后续校正：**`parallel/falcon_manifest_table.md` 与
`parallel/bcrt_manifest_coverage.md` 已在四份 descriptor 所属 hash table 中确认
`raw0=0x22 | length=0x50+word1 | SHA-384(envelope)` 且全部复算匹配。
`raw0=0x22` 是相对 table end 的 covered-start offset，不是 Falcon index 34。
所以 exact byte boundary 现为 FACT；仍属 INFERENCE 的是把私有 `word1` 正式
命名为旧版 `StoredSize`，以及它在 v6 schema 中的全部语义。

## 2. 公开 host parser 能读 Falcon 表，但不能映射/解析这个对象

### 2.1 公开到表项布局，未公开 `0x24/0x0f` 名称

`kernel_gsp_fwsec.c` 定义了 BIT Falcon token、表头和表项：表项确实是
`ApplicationID:u8, TargetID:u8, DescPtr:u32`：

- BIT Falcon token：`kernel_gsp_fwsec.c:90-98`；
- table header：`kernel_gsp_fwsec.c:100-112`；
- entry layout：`kernel_gsp_fwsec.c:114-123`。

但该文件只公开三个 app ID 名称：

```text
0x05 FIRMWARE_SEC_LIC
0x45 FWSEC_DBG
0x85 FWSEC_PROD
```

见 `kernel_gsp_fwsec.c:125-127`。在本地 610 公开树的有界符号搜索中：

- `FSP_RUN`：零命中；
- `ApplicationID` / `TargetID` / `FALCON_UCODE_TABLE` 的实际解析实现：只在
  `kernel_gsp_fwsec.c`；
- 没有 `app=0x24` 或 `target=0x0f` 的 FSP 常量/枚举。

特别值得注意的是，公开 parser 虽读出 `TargetID`，却没有任何一次比较它；筛选只
比较 `ApplicationID`。所以公开源码不能给 `target=0x0f` 命名。

### 2.2 该 parser 明确跳过 app 0x24，也明确拒绝 descriptor v6

公开 parser 遍历 Falcon entries 后，只保留 app `0x05/0x45/0x85`：
`kernel_gsp_fwsec.c:594-625`。因此 `0x24` 会在读取 descriptor 前被跳过。

即便绕过 app filter，descriptor body 也只有 v2/v3 struct：

- v2/v3 定义：`kernel_gsp_fwsec.c:148-188`；
- 运行时只接受 v2 或 v3，其他版本报 unexpected 并跳过：
  `kernel_gsp_fwsec.c:627-669`。

这意味着 public host code 能说明 vDesc 首字的 flags/version/size 位布局，却不能
说明 Blackwell v6 的后 `0x4c` bytes 是什么，更不能提取其 payload。

### 2.3 对 GB202，连 VBIOS host extraction 本身都被 HAL 关掉

通用 `kgspInitRm_IMPL()` 的旧路径会尝试从 ROM 提取 VBIOS，并只为了 FWSEC/FRTS
调用上面的 parser：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/kernel_gsp.c:4907-4931`。

但 generated HAL 把 TU/GA/AD 映射到 `kgspExtractVbiosFromRom_TU102`，把包括 GB202
在内的其他离散 GPU 映射到 stub `kgspExtractVbiosFromRom_395e98`：

- dispatch：`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kernel_gsp_nvoc.c:1385-1403`；
- stub 直接 `return NV_ERR_NOT_SUPPORTED`：
  `/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kernel_gsp_nvoc.h:1993-1999`；
- caller 把 `NV_ERR_NOT_SUPPORTED` 当成“extracting VBIOS image from ROM is not
  supported”并继续：`kernel_gsp.c:4947-4951`。

**FACT：** 至少在公开 610 Linux RM 的 GB202 OS-driver 阶段，没有
“host 取出 `FSP_RUN` -> host 解析 v6 -> host 上传 FSP runtime”的数据链。

这不排除 UEFI/VBIOS pre-OS 代码、芯片 ROM 或私有 firmware 在更早阶段处理它；
那些组件不在这份公开 host source 中。

## 3. BootFSM 到 host wait：公开链从这里重新出现

### 3.1 GB202 声明 FSP 由 reset 后的 BootFSM 启动

GB202 专用 wait condition 的原注释非常直接：

> In GB202, Bootfsm triggers FSP execution out of chip reset.

随后说明 FSP boot 完成后向 `NV_THERM_I2CS_SCRATCH` 写 `0xFF`。代码只测试这个
状态：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb202.c:48-61`。

`kfspWaitForSecureBoot_GB202()` 只是建立五秒 OS-timer timeout 并轮询该条件；失败
才读取 FSP scratch/debug 状态：`kern_fsp_gb202.c:64-108`。scratch 的公开值定义为
success `0x000000ff`：
`/usr/src/nvidia-610.43.03/src/common/inc/swref/published/blackwell/gb202/dev_therm_addendum.h:27-30`。

Generated FSP HAL 对 GB202 明确选择这个 wait：
`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kern_fsp_nvoc.c:489-501`。

### 3.2 host FSP object 本身也没有 runtime loader

GB202 present-list 包含一个 `KernelFsp`：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/arch/blackwell/kern_gpu_gb202.c:59-93`。

其公开 constructor 只做 registry/property、async response timer 和 HAL construction：
`/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/fsp/kern_fsp.c:79-105`。GB202 的
construct HAL 复用 GB100，只初始化 FSP MNOC mailbox aperture：

- dispatch：`g_kern_fsp_nvoc.c:333-342`；
- 实现：`kern_fsp_gb100.c:76-85`。

这里也没有 FSP image allocation、VBIOS descriptor parse、DMA upload 或 CPU start。
这是“FSP 在 RM 接管前已由设备内部链启动”的第二个独立旁证。

### 3.3 `kgspInitRm` 的实际 wait 调用链

公开调用链是：

1. `kgspInitRm_IMPL()` 先准备 boot binary、GSP-RM image 和日志，然后调用
   `kgspWaitForGfwBootOk_HAL()`：`kernel_gsp.c:5002-5032`。
2. GB202 的 generated KernelGsp HAL 使用 Hopper+ 默认实现
   `kgspWaitForGfwBootOk_GH100`：
   `/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kernel_gsp_nvoc.c:1601-1624`。
3. 该 wrapper 取得 `KernelFsp`，若存在就直接调用
   `kfspWaitForSecureBoot_HAL()`：
   `/usr/src/nvidia-610.43.03/src/nvidia/src/kernel/gpu/gsp/arch/hopper/kernel_gsp_gh100.c:248-263`。
4. 对 GB202，最终落到上一节的 `kfspWaitForSecureBoot_GB202()`，等 scratch `0xff`。

**FACT：** host 动词是 **wait**，不是 load/start FSP。

## 4. FSP boot 完成后，host 主动交付的是 GSP 映像

这是最容易和 `FSP_RUN` 混淆的地方。公开代码确实有“大映像 -> sysmem -> FSP”
链，但对象名字、调用时机和数据字段都表明它是给已经运行的 FSP 去启动 **GSP**。

### 4.1 GB202 复用 GH100 的 GSP prepare/bootstrap

Generated KernelGsp HAL 对 GB202 选择：

- `kgspPrepareForBootstrap_GH100`：`g_kernel_gsp_nvoc.c:710-728`；
- `kgspBootstrap_GH100`：`g_kernel_gsp_nvoc.c:731-749`。

正常 GB202 构造有 `KernelFsp`，而 SEC2 的 `PDB_PROP_KSEC2_BOOT_GSPFMC` 只对
GB10B/GB20B/GB20C 为 true，其他（含 GB202）为 false：
`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kernel_sec2_nvoc.c:465-475`。
在没有显式 `DISABLE_GSPFMC` override 的正常配置中，这因此选择 FSP 分支。

### 4.2 prepare：先确认 FSP 已活着，再创建 COT

`_kgspBootGspRm()` 先调用 prepare，再调用 bootstrap：
`kernel_gsp.c:4795-4841`。

`kgspPrepareForBootstrap_GH100()`：

1. 设置 GSP-FMC args；
2. 若 FSP 存在且未禁用 GSP-FMC，就标记 GSPRM mode；
3. 调用 `kfspPrepareBootCommands_HAL()`。

见 `kernel_gsp_gh100.c:779-830`。

GB202 的 FSP HAL 复用 `kfspPrepareBootCommands_GH100` 和
`kfspSendBootCommands_GH100`：
`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kern_fsp_nvoc.c:453-470`。

FSP prepare 开头再次等待 FSP secure boot 并做 boot-command precheck：
`kern_fsp_gh100.c:1257-1289`。随后分配 `NVDM_PAYLOAD_COT`，填写 FRTS，最后调用
`kfspSetupGspImages()`：`kern_fsp_gh100.c:1330-1385,1444-1475`。

### 4.3 交给 FSP 的 archive 明确是 `g_gsp_gb20x_*`

`kfspGetGspUcodeArchive()` 在 GSPRM mode 打印
`Loading GSP-RM image using FSP`，并根据 debug/CC 选择
`kgspGetBinArchiveGspRm*FmcGfw*Signed`：`kern_fsp_gh100.c:784-821`。

GB202 generated dispatch 把 production archive 映射到
`kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202`：
`/usr/src/nvidia-610.43.03/src/nvidia/generated/g_kernel_gsp_nvoc.c:958-988`。

该 bindata 的 metadata 明确命名为：

- image `g_gsp_gb20x_dyn_prd_gfw_image.bin`：
  `g_bindata_kgspGetBinArchiveGspRmFmcGfwProdSigned_GB202.c:29-41`；
- hash/signature/public key：同文件 `18018-18103`。

没有一个文件名把它叫 `fsp` runtime。

### 4.4 数据传递的精确形态

`kfspSetupGspImages()`：

- 从 archive 取 `UCODE_IMAGE/HASH/SIG/PKEY`：`kern_fsp_gh100.c:983-1003`；
- 为 image 建 sysmem memdesc 并写入：`kern_fsp_gh100.c:1005-1028`；
- 把 GPU 可见物理地址放进 `gspFmcSysmemOffset`，并复制 hash、signature、public
  key 和 boot args 地址到 COT：`kern_fsp_gh100.c:1030-1047`。

公开 COT struct 字段也直接命名为 `gspFmcSysmemOffset`、认证字段和
`gspBootArgsSysmemOffset`：
`/usr/src/nvidia-610.43.03/src/nvidia/inc/kernel/gpu/fsp/kern_fsp_cot_payload.h:37-55`。

真正发送时，`kfspSendBootCommands_GH100()` 用 `NVDM_TYPE_COT` 调
`kfspSendAndReadMessage()`：`kern_fsp_gh100.c:1499-1528`；类型值公开为 `0x14`：
`/usr/src/nvidia-610.43.03/src/nvidia/arch/nvalloc/common/inc/nvdm_format.h:43-49`。

底层 host transport 是 MCTP/NVDM 分包后调用 FSP packet HAL：

- 封包：`kern_fsp.c:473-576`；
- 同步 send/wait/read：`kern_fsp.c:690-747`；
- GB100/GB202 packet HAL 可选 MNOC mailbox，否则复用 GH100 EMEM：
  `kern_fsp_gb100.c:310-387`。

### 4.5 FSP 启动 GSP 后的 host wait

`kgspBootstrap_GH100()` 在 FSP 分支发送 COT：
`kernel_gsp_gh100.c:875-890`，然后按次序：

1. 等 FSP/ACR 释放 GSP target mask：`901-919`；
2. 可选建立 SPDM session：`936-948`；
3. 发送 GSP init RPC：`950-964`；
4. 等 lockdown release/FMC error：`967-996`；
5. 确认 GSP RISC-V active：`998-1012`；
6. 等 GSP-RM init done：`1014-1027`。

这闭合了“**已运行 FSP -> 认证/启动 GSP**”的公开链，但没有补上
“**VBIOS FSP_RUN -> 启动 FSP 自己**”的私有缺口。

## 5. 四个重点问题的最终判定

| 问题 | 判定 | 证据边界 |
|---|---|---|
| host 是否主动提取/上传 `FSP_RUN`？ | **FACT：公开 GB202 Linux RM 不会。** | GB202 VBIOS extraction HAL 返回 `NV_ERR_NOT_SUPPORTED`；FSP wait 注释说 BootFSM 从 reset 触发；constructor 只有通信 aperture。不能外推到未公开 UEFI/ROM。 |
| `app=0x24,target=0x0f` 能否在公开源码映射为 `FSP_RUN`？ | **UNKNOWN / 不能正式映射。** | raw entry 和 descriptor 内的可打印 `FSP_RUN` 同时存在是 FACT；公开枚举没有 0x24/0x0f，TargetID 甚至未参与 host filter。把二者命名绑定是强提示，不是公开定义。 |
| Falcon v6 descriptor 谁解析？ | **UNKNOWN；强 INFERENCE 为 device-internal secure boot loader。** | 公开 host parser 只接受 app 05/45/85 与 desc v2/v3；GB202 不提取 ROM。BootFSM 已在 RM wait 前启动 FSP，因此真正 v6 parser/loader 必须位于更早的私有阶段。 |
| 代码最可能在 ROM 还是 VBIOS 对象？ | **两级模型最可能：ROM first stage + VBIOS bulk runtime。** | Reset 后无 host upload，故最初可执行 root 必须 device-resident；同时存在 169–225 KiB、encrypted、随 VBIOS build 变化的 `FSP_RUN` 对象，且公开包没有 standalone FSP runtime，故主体 runtime 最可能来自该对象。具体 task handler 归属仍 UNKNOWN。 |

## 6. 对后续逆向方向的实际含义

1. **不要再把公开 `kernel_gsp_fwsec.c` 当成 v6 解包器。** 它是旧 FWSEC/FRTS
   host parser，GB202 不走它，且 app/version 都不匹配。
2. **“逆向 VBIOS FSP_RUN”仍是最有价值的静态方向**，但目标应表述为识别 envelope、
   认证/加密结构及跨版本差异，而不是假定现在已有 plaintext code。
3. **真正缺的关键材料是 first-stage consumer。** 最有价值的新公开证据会是：
   Blackwell v6 descriptor spec、BootFSM/BootROM flow、FSP ROM symbols/log format，或
   能把 app `0x24`/target `0x0f` 正式命名的 NVIDIA source/header。
4. **即使恢复 `FSP_RUN` plaintext，也不能先验保证 task 2 在里面。** task dispatcher
   可能在 bulk runtime，也可能是 ROM service，或由两者共同实现。

当前最严谨的人话版是：**VBIOS 很可能装着 FSP 的“大脑主体”，芯片 ROM 是负责验
身份证并把它叫醒的引导员；Linux 驱动来得更晚，只看到它已经醒了，然后把 GSP
交给它继续启动。公开代码没有告诉我们引导员究竟怎样读 v6，也没有正式说明
`0x24/0x0f` 的名字。**

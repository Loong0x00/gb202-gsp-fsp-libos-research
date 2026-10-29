# `0x015d3a98` effective-setter provenance audit

## 结论

此前把 GSP 函数 `0x015d3a98` 视为“可能形成
`0x822900 + 4*FBP` effective-mask 地址的通用 setter”是错误分类，现明确撤销。

该函数是 **GH100 专用的 `Ioctrl`/MINION NVLink DLCMD sender**。它通过
IOCTRL 的 MINION aperture 写 `NV_MINION_MISC_0` 和
`NV_MINION_NVLINK_DL_CMD(i)`，服务于 NVLink Eye-Opening Monitor（EOM）控制；
它不是 FB/Fuse 对象方法，不写 raw/effective floorsweep mask，也不属于 GB202
reset/init 链。

旧分类的根源是常量碰撞：函数中的 `0x0a40` 实际为
`0x2900 / sizeof(NvU32)`，即 MINION DLCMD 数组的 word offset。不能把它与
`(0x822900 - 0x820000) / 4` 相等这一数值巧合解释成 Fuse effective-B 地址。

## 审计对象与边界

- 固件：`/tmp/gsp_inner_19f040_a.elf`
- ISA：RV64/RVC
- 完整函数范围：`[0x015d3a98, 0x015d3ba0)`，大小 `0x108`
- `0x015d3b3a` 只是函数内的 command store；`0x015d3b82..0x015d3b9e`
  仍是同一函数的 `NV_ERR_NOT_SUPPORTED` 日志与返回块
- 下一函数从 `0x015d3ba0` 开始

## NVOC 对象身份

固定 GSP 中的 NVOC class definition 起于 `0x01e050c8`：

| 字段 | 值 |
|---|---:|
| `classInfo.size` | `0x0a40` |
| `classInfo.classId` | `0x11ce10` |
| `classInfo.providerId` | `0x01e8cc70` |
| `objCreatefn` | `0x019eb544` |
| `pCastInfo` | `0x01e912e8` |
| `pExportInfo` | `0x01e050b8` |

`0x019eb544` 是 thunk，尾跳到对象 creator `0x019e7460`。creator 清零
`0x0a40` 字节对象空间并按 `chipHal_HalVarIdx` 初始化方法表。

随 610.43.03 驱动发布的 generated source 提供独立名称校准：

- `src/nvidia/generated/g_eng_desc_nvoc.h:878-883`：class ID
  `0x11ce10` 明确对应 `Ioctrl`
- 同文件 `:1111`：`ENG_CLASS_IOCTRL = classId(Ioctrl)`
- 同文件 `:1272-1276`：`Ioctrl` 是 indexed IOCTRL engine，最大实例数为 3

因此该 receiver 是 NVLink I/O controller，而不是 FB、Fuse、InfoROM 或
floorsweep 对象。

## GH100 与 GB202 HAL 绑定差异

对 `0x019e753a` 起的 `Ioctrl` 方法表初始化器按全部 chip index 做符号重放，
得到以下关键绑定：

| ChipHal | index | `Ioctrl+0x438` | `Ioctrl+0x468` |
|---|---:|---:|---:|
| GH100 | 58 | `0x015d3a98` | `0x015b60a4` |
| GB202 | 65 | `0x019d3b50` | `0x019d3bf0` |

具体写表位置为：

- GH100：`0x019e9042..0x019e904a` 把 `0x015d3a98` 写入 `+0x438`；
  `0x019e908a..0x019e9092` 把 `0x015b60a4` 写入 `+0x468`
- GB202：`+0x438` 选择 `0x019d3b50`，`+0x468` 选择 `0x019d3bf0`

公开 chip-to-HAL 映射再次独立确认 index：

- `src/nvidia/generated/g_chips2halspec_nvoc.c:99-103`：GH100 为 index 58
- 同文件 `:129-133`：GB202 为 index 65

GB202 的两个函数均为纯 stub：

- `0x019d3b50` 直接返回 `0x56`，即 `NV_ERR_NOT_SUPPORTED`
- `0x019d3bf0` 直接返回 0

所以 GB202 调 `Ioctrl+0x468` 时会在该槽直接 no-op 成功，不会继续下钻到
`Ioctrl+0x438`。任何经其他 wrapper 间接调用 `+0x438` 的 GB202 路径也只会
命中 `0x019d3b50`，不会执行 `0x015d3a98`。

## `0x015d3a98` 的参数与行为

函数保存的六个 RV64 参数及稳健行为命名如下：

| ABI 参数 | 保存寄存器 | 行为含义 |
|---|---|---|
| `a0` | `s5` | `pGpu` |
| `a1` | `s4` | `pIoctrl` |
| `a2` | `s2` | `linkNumber` |
| `a3` | `s1` | MINION `command` |
| `a4` | `s7` | `scratch0` |
| `a5` | `s3` | `bWaitForCompletion` |

据此可把行为签名描述为
`NV_STATUS (pGpu, pIoctrl, linkNumber, command, scratch0, bWaitForCompletion)`；
私有源符号本身未恢复，不应把这个行为签名误写成已取得的符号名。

主要控制流为：

1. 检查 `pIoctrl+0x840` 的 enable/support gate；为假时记录 command 并返回
   `NV_ERR_NOT_SUPPORTED (0x56)`。
2. 通过 `Ioctrl+0x440` 调 `0x015da650`，等待该 link 的前一条 DLCMD 完成；
   失败时转成 `NV_ERR_GENERIC (0xffff)`。
3. 当 `(command & ~4) == 0x40`，即 command 为 `0x40` 或 `0x44` 时，把
   `scratch0` 写到 MINION base 加 `0x28b0`。
4. 向 MINION base 加 `0x2900 + 4*localLink` 写
   `0x40000000 | (command & 0xff)`。
5. 若 `bWaitForCompletion` 为真，再尾调 `Ioctrl+0x440`；否则直接返回 0。

地址生成使用以下对象状态：

- `pGpu+0xb98`：寄存器 aperture/base pointer
- `pIoctrl+0x850`：global-to-local link-number 基准
- `pIoctrl+0x8f4`：MINION block offset

这组动态字段决定的是每个 IOCTRL/MINION 实例的 PRI 地址，不是 primary Fuse
base。函数没有读取 raw A，也没有接收 A getter 的返回值。

`Ioctrl+0x440 = 0x015da650` 的行为也与 DLCMD 一致：它读取 per-link command
register，轮询 bit 31 `READY`，并检查 bit 30 `FAULT`。

## 公开 MINION 寄存器校准

610.43.03 的公开 NVSwitch hwref 与目标指令逐项吻合：

- `src/common/inc/swref/published/nvswitch/ls10/dev_minion_ip.h:275-277`：
  `0x28b0 = NV_MINION_MISC_0`
- 同文件 `:278-280`：
  `NV_MINION_NVLINK_DL_CMD(i) = 0x2900 + i*4`，command 位为 `[7:0]`
- 同文件 `:314-319`：
  `0x40 = CONFIGEOM`、`0x44 = STARTEOM`、`0x45 = ENDEOM`
- 同文件 `:354-359`：bit 30 为 `FAULT`/fault-clear，bit 31 为 `READY`
- 同文件 `:360-363`：相邻的 DLCMD data array 定义

公开 `src/common/nvswitch/kernel/ls10/minion_ls10.c:157-343` 还给出了参数同构的
MINION sender：输入为 device、link number、command、scratch0；必要时先写
scratch，再发 DLCMD，最后轮询 READY 并处理 FAULT。它为这里的私有 GSP 实现
提供独立的寄存器级语义校准。

## 直接 xref 审计

对 executable PT_LOAD 在每个 2-byte 边界做 bounded 扫描后：

- 没有以 `0x015d3a98` 为目标的 direct `JAL`、compressed jump 或 conditional
  branch
- 没有简单的同基址 `AUIPC -> JALR` direct call
- 全 ELF 没有该地址的 4-byte 或 8-byte absolute pointer literal
- 唯一 `AUIPC -> ADDI` 地址实体化在 `0x019e9042..0x019e9046`，随后于
  `0x019e904a` 写入 `Ioctrl+0x438`

因此目标的可见入口是 `Ioctrl` vtable，不能把任意其他对象中相同的 `+0x438`
offset 当作 caller。全局按 offset 搜索会产生大量无关 class 的 slot collision。

## 一至两层调用图

### Ioctrl wrapper 层

- `Ioctrl+0x468 = 0x015b60a4`：把 caller 的 `a3` 作为 `scratch0`、`a4`
  作为 wait flag，固定 `command=0x40 (CONFIGEOM)`，尾调 `Ioctrl+0x438`
- `Ioctrl+0x478 = 0x015d2b98`：固定 `command=0x44 (STARTEOM)`、
  `scratch0=0`，尾调 `+0x438`
- `Ioctrl+0x480 = 0x015d2bb0`：固定 `command=0x45 (ENDEOM)`、
  `scratch0=0`，尾调 `+0x438`
- GH100 的 `Ioctrl+0x488 = 0x015d2bc8` 直接返回 0

### NV2080 control 层

固定 GSP 的 NVOC export table 给出两个精确 caller：

| Export entry | pFunc | methodId | paramSize | 公开名称 |
|---|---:|---:|---:|---|
| `0x01c1a170` | `0x015acb44` | `0x2080300c` | `0x8` | `subdeviceCtrlCmdNvlinkSetupEom` |
| `0x01c1a330` | `0x015acc30` | `0x2080303c` | `0x1c` | `subdeviceCtrlCmdNvlinkEomControl` |

`0x015acb44` 从参数读取 `linkId@+0` 和 `params@+4`，选择相应 Ioctrl 对象后，
以 wait flag 1 调 `Ioctrl+0x468`。公开
`ctrl2080nvlink.h:1686-1702` 对 `NV2080_CTRL_CMD_NVLINK_SETUP_EOM`
的描述明确写着：把 packed 32-bit params 写入 MINION scratch，然后向目标 link
发送 EOM DLCMD。

`0x015acc30` 按 `cmd@+0`、`linkId@+4`、`params@+8` 解析参数，并按 cmd 调度：

| EOM control cmd | Ioctrl slot | 最终 DLCMD |
|---:|---:|---:|
| 0 | `+0x478` | `0x44 STARTEOM` |
| 1 | `+0x480` | `0x45 ENDEOM` |
| 2 | `+0x468` | `0x40 CONFIGEOM` |
| 3 | `+0x488` | full-sequence HAL slot |

公开 `ctrl2080nvlink.h:2365-2398` 给出完全相同的结构布局与枚举：
`START_EOM=0`、`END_EOM=1`、`CONFIG_EOM=2`、`FULL_EOM_SEQUENCE=3`。

因此第二层 caller 不是 generic HW-info/register script，而是由 method ID、参数
布局和 DLCMD selector 三方面共同确认的 NVLink EOM control path。

## 对 GB202 raw-to-effective 结论的影响

必须删除以下旧表述：

- “固定 GSP 存在一条 caller-driven、能形成 B 类地址的通用 setter”
- “`0x015d3a98` 是未闭合到 GB202 reset/init 的 effective setter 候选”
- “`0x40000040` 可能是 floorsweep/reset 命令”

应替换为：

> `0x015d3a98` 已正向识别为 GH100-only Ioctrl/MINION EOM DLCMD sender。
> 其中 `0x0a40` 是 `NV_MINION_NVLINK_DL_CMD` 的 word offset，`0x40` 是
> `CONFIGEOM` command。GB202 的对应 Ioctrl 槽为 stub，故该函数不提供任何
> GB202 effective-B write plumbing。

以下结论不受影响：

- GB202 FB `+0x9c0 = 0x0132ef40` 对 effective B 的 getter/consumer 绑定仍成立
- 已审计范围内没有找到 A-derived B writer/copy/recompute 的有限负结论仍成立，
  且因排除这个假候选而更强
- 该有限负结果仍不能证明 propagation 必然由 hardware 或 FSP/GFW 自动完成；
  reset-edge sense、firmware rebuild 和隐藏 replay 仍是并列 UNKNOWN

## 已同步纠正的既有段落

主协调任务已据此修正：

- `L2_REENABLE_STATIC_FINDINGS.md` 当前约 47-55 行、210-226 行；
  2671-2675 行的“A-derived copier 未找到”本身仍正确
- `parallel/raw_effective_propagation.md` 当前约 44-47 行、整个 4.3 节、
  actor/stage 矩阵中的 generic B setter 行
- `parallel/shadow_reset_lifecycle.md` 当前约 254-260 行
- `parallel/shadow_reset_domains.md` 当前约 331-336 行

本报告归档证据与纠错范围；上述文件中的旧候选表述现已撤销。

## 证据边界

本次工作是纯离线、bounded 静态审计，没有执行固件或访问 GPU。私有 Ioctrl
函数的精确 C symbol 未恢复；报告使用的是由对象 class ID、HAL binding、寄存器
定义、method ID 和参数数据流共同支持的行为命名。

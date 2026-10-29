# GB202：`GET_FS_INFO/LTS_MASK` 的实际路由、支持边界与返回语义

日期：2026-07-21  
状态：静态审计完成；未做 live control call

## 结论先行

在 **610.43.03、CPU-RM 以 GSP firmware client 方式运行、物理 GPU、非 MIG**
这个精确边界内，`NV2080_CTRL_CMD_FB_GET_FS_INFO`（`0x20801346`）的
`NV2080_CTRL_FB_FS_INFO_LTS_MASK`（query type `3`）并非空壳：请求会路由到
物理 GSP，GSP 有真实 handler，GB202 HAL 也把它最终调用的 FB vtable
`+0x9c0` 绑定到一个非 stub getter。

该 getter 读取 `0x822900 + 4*FBP` 所代表的 **current/effective LTS-disable
视图**，在实际拓扑位宽内反相后返回 enable mask。因此输出应解释为
**当前可用/已启用的 flattened LTS 拓扑**，不是 raw OPT/shadow fuse，亦不是
repair/provenance/health map。

旧接口 `NV2080_CTRL_CMD_FB_GET_LTC_INFO_FOR_FBP`（`0x20801328`）需要作一个
重要纠正：

- CPU-RM 的 **非 VF 本地 HAL binding** 确实是 `NV_ERR_NOT_SUPPORTED` stub；
- 但在正常 GSP-offload 路径上，`ROUTE_TO_PHYSICAL` 会先把 control RPC 到
  物理 GSP，因而不会执行这个本地 stub；
- 610.43.03 的物理 GSP 中存在非 stub handler，它同时返回 active LTC/LTS
  mask，并由这两个 mask 计算 count。

所以“旧命令在 non-VF 是 stub”只适用于 **本地/monolithic handler 选择**，
不能外推成“裸机 GB202 的 GSP-offload 路径也是 stub”。

## 审计边界与安全

本轮只读：

- 本地 610.43.03 OpenRM 源码；
- 已记录来源和 hash 的 610.43.03 GSP inner ELF；
- 本地 610.74 Windows 驱动包中提取出的 GSP inner ELF，作为版本交叉检查；
- 精确 method-ID literal、固定 32-byte export entry、明确函数地址的小窗口
  RISC-V 反汇编，以及既有的 bounded FB-constructor replay。

未访问 `/dev/nvidia*`、PCI config、BAR/MMIO 或正在驱动桌面的 RTX 5090；未
发 control call、reset、写寄存器、加载模块、运行 MODS/固件/安装包，也未做
全 ELF 反汇编或大型分析数据库。

## FACT

### 1. 公开接口本身描述的是 active/physical-local mask

610.43.03 头文件
`/usr/src/nvidia-610.43.03/src/common/sdk/nvidia/inc/ctrl/ctrl2080/ctrl2080fb.h`
给出：

- `GET_LTC_INFO_FOR_FBP`：`1240..1269`；输入 physical FBP index，输出
  active LTC/LTS mask 和 count；
- `NV2080_CTRL_FB_FS_INFO_LTS_MASK_PARAMS`：`2021..2033`；输入
  `fbpIndex`，输出一个在该 FBP 内把所有 LTC 的 LTS 位摊平后的
  `ltsEnMask`；
- query type `LTS_MASK = 3`：`2288`；
- batched `GET_FS_INFO` 参数和 command：`2332..2359`。

这里的 `physical/local` 描述的是 **索引/坐标空间**。结构里没有 raw-fuse、
repair source、provenance 或 health 字段，不能把这几个词解释成“读取原始熔丝”。

### 2. 两个 control 的 host export flags 都要求 route-to-physical

生成的 host export table：

| control | method | flags | accessRight | param size | 源码位置 |
|---|---:|---:|---:|---:|---|
| `GET_LTC_INFO_FOR_FBP` | `0x20801328` | `0x50158` | `0` | `0x14` | `g_subdevice_nvoc.c:9991..10004` |
| `GET_FS_INFO` | `0x20801346` | `0x10248` | `0` | `0xf08` | `g_subdevice_nvoc.c:10201..10213` |

按 `src/nvidia/inc/kernel/rmapi/control.h:196..305` 的定义：

- `0x50158` = NON_PRIVILEGED、GPU_LOCK_DEVICE_ONLY、ROUTE_TO_PHYSICAL、
  API_LOCK_READONLY、GSP_PLUGIN_FOR_VGPU_GSP、
  PHYSICAL_IMPLEMENTED_ON_VGPU_GUEST；
- `0x10248` = NON_PRIVILEGED、ROUTE_TO_PHYSICAL、ROUTE_TO_VGPU_HOST、
  GSP_PLUGIN_FOR_VGPU_GSP。

注意：`GET_FS_INFO` 的 flag 数值 **不含** `API_LOCK_READONLY (0x100)`。
后文看到的 type-3 handler 是读取路径，但不能错误声称 export flag 本身把整个
control 标成 API-lock-readonly。

### 3. CPU-RM 的 route prologue 会绕开 non-VF local stub

`src/nvidia/src/kernel/rmapi/resource.c:215..297` 明确显示：当
`IS_FW_CLIENT(pGpu)` 且 control 带 `ROUTE_TO_PHYSICAL` 时：

1. 参数向下序列化；
2. prologue 调用 `NV_RM_RPC_CONTROL(...)`；
3. RPC 成功时返回 `NV_WARN_NOTHING_TO_DO`，使本地 implementing function
   不再执行。

与此同时，旧接口的 host-local 选择确实如下：

- `generated/g_subdevice_nvoc.c:14217..14224`：VF 绑定
  `subdeviceCtrlCmdFbGetLTCInfoForFBP_VF`，其他 variant 绑定
  `subdeviceCtrlCmdFbGetLTCInfoForFBP_92bfc3`；
- `generated/g_subdevice_nvoc.h:8175..8178`：后者直接返回
  `NV_ERR_NOT_SUPPORTED`；
- `kern_mem_sys_ctrl.c:1703..1726`：可见源码实现是 VF/VSI 路径，而且只填
  LTC 字段。它不是裸机物理 GSP handler 的实现。

由此可以精确区分：

| 执行环境 | 旧 `GET_LTC_INFO_FOR_FBP` 的结论 |
|---|---|
| CPU-RM 本地、non-VF、未走 firmware RPC | 本地 binding 是 stub，FACT |
| VF/VSI host-local | 有独立 VF 实现；可见源码只填 LTC，FACT |
| CPU-RM 是 FW client 且走 GSP-offload | 在本地 stub 前 route-to-physical，FACT |
| 物理 610.43.03 GSP endpoint | 有非 stub handler，FACT，见下一节 |

### 4. 610.43.03 物理 GSP 同时导出两个真实 handler

样本 provenance：`parallel/GSP_ARTIFACT_PROVENANCE.md`。

```text
/tmp/gsp_inner_19f040_a.elf
size    82577496
sha256  bda917c95547644398eaf77fefe6c7f1b701c962db91f88bffaed6448a218a47
RX VA   0x01000000..0x01e97000  (file offset = VA - 0x01000000)
```

`NVOC_EXPORTED_METHOD_DEF` 的字段布局来自
`src/nvidia/inc/libraries/nvoc/runtime.h:71..86`。对精确 method literal 所在的
32-byte aligned entry 解码得到：

| entry VA | pFunc | flags | access | method | params | class |
|---:|---:|---:|---:|---:|---:|---:|
| `0x01c18fd0` | `0x01306320` | `0x50158` | `0` | `0x20801328` | `0x14` | `0x01c20870` |
| `0x01c191b0` | `0x0131111c` | `0x10248` | `0` | `0x20801346` | `0xf08` | `0x01c20870` |

这直接排除了“物理 GSP export table 里也把它们设成 NULL”的说法。

#### 4.1 旧 handler `0x01306320`

bounded disassembly 的数据流是：

```text
pParams[0]                -> physical FBP index
call 0x0132932c           -> pParams+0x04 (ltcMask)
call FB vtable +0x9c0     -> pParams+0x0c (ltsMask)
popcount(ltcMask)         -> pParams+0x08 (ltcCount)
popcount(ltsMask)         -> pParams+0x10 (ltsCount)
return NV_OK
```

关键指令位于 `0x01306332..0x013063da`。这不是返回
`NV_ERR_NOT_SUPPORTED` 的 stub。

#### 4.2 新 `GET_FS_INFO` handler `0x0131111c`

handler 在 `0x013111ce..0x013111e2` 读取 query type，接受 `0..0x12`，并经
19 项 jump table dispatch。type `3` 的表项落到 `0x013117ac`。

该分支包含 MIG/instance-aware 路径；其 **non-MIG** 路径落到
`0x01311d8e`：

```text
0x01311d8e  load FB vtable +0x9c0
0x01311d9a  fbpIndex &= 0xff
0x01311da0  call getter
0x01311da2  store return -> query ltsEnMask
0x01311da8  store NV_OK  -> per-query status
```

因此 type 3 并非只在 header 中定义；在这一精确 GSP build 中有可达的
non-MIG physical implementation。MIG 分支返回的是 GI/实例可见的 active
allocation topology，不应与全物理 GPU mask 混用。

### 5. GB202 的 `+0x9c0` 绑定是非 stub，而且读 effective view

OpenRM 的 chip mapping
`generated/g_chips2halspec_nvoc.c:129..142` 把 GB202 映射为 HAL index 65。
既有 bounded constructor replay 的归档结果
`parallel/gsp_fb_vtable_replay.results.txt` 显示：

```text
GB202 index 65:
  FB +0x9b0 = 0x0132ae68
  FB +0x9c0 = 0x0132ef40
```

`0x0132ef40` 的小窗口反汇编给出：

```text
W       = call(FB +0x758) * call(FB +0x730)
require W <= 31
disable = read32((0x0a40 + fbpIndex) * 4)
return (~disable) & ((1U << W) - 1)
```

对应关键地址为：

- `0x0132ef98..0x0132efb8`：两个宽度 getter、乘法、`W <= 31`；
- `0x0132efbe..0x0132efdc`：构造内部 offset
  `0x2900 + 4*FBP` 并经 aperture/Fuse 对象的 read callback 读取；
- `0x0132efe2..0x0132efec`：按 `W` 裁宽并反转 disable mask。

既有 RegHal 解码（`parallel/l2_mask_granularity.md:83..105`、
`parallel/shadow_reset_lifecycle.md:71..85`）把 domain-5 内部
`0x2900 + 4*FBP` 映射到：

```text
BAR0 0x822900 + 4*FBP   current/effective LTS-disable view
```

它不同于：

```text
BAR0 0x8234e0 + 4*FBP   raw OPT/shadow L2-disable view
```

所以两个 GSP query 最终看到的是 **effective enable mask**，不是 raw mask。
它能回答“RM/硬件当前把哪些 flattened LTS position 当作启用”，不能回答这些
位置为何禁用、是否物理损坏、来自 SKU floorsweep 还是 repair，以及将 raw bit
更改后是否会被 reset/reinit 接纳。

### 6. 610.74 保持同一路由和 getter 语义

交叉检查样本：

```text
/tmp/gsp_inner_61074.elf
size    82593880
sha256  bff2477fea7c8c8fde194006009f060f8eb1761fe2a1951235530dd57950b2a8
RX VA   0x01000000..0x01e99000
```

其 export entries 为：

| entry VA | pFunc | flags | method | params |
|---:|---:|---:|---:|---:|
| `0x01c19fd0` | `0x01306934` | `0x50158` | `0x20801328` | `0x14` |
| `0x01c1a1b0` | `0x01311738` | `0x10248` | `0x20801346` | `0xf08` |

小窗口确认：

- 旧 handler `0x01306934` 仍调用 FB `+0x9c0` 并返回两组 mask/count；
- `GET_FS_INFO` type-3 branch 为 `0x01311dc8`，non-MIG endpoint
  `0x013123aa` 仍调用 FB `+0x9c0`，写 `ltsEnMask` 与 `NV_OK`；
- 对新 constructor 用同一 bounded replay 逻辑，GB202 index 65 得到
  `+0x9b0 = 0x0132b488`、`+0x9c0 = 0x0132f564`；
- getter `0x0132f564` 在 `0x0132f5bc..0x0132f610` 保持相同算法：
  `W` 动态裁宽、读取 `(0xa40+FBP)*4`、返回反相后的 enable mask。

因此 610.74 没有显示这条支持链被删除或改成 stub。该样本来自本地 Windows
驱动包；它是版本交叉证据，不等于对当前 Linux runtime 做了调用验证。

## INFERENCE

1. 对正常启用 GSP-offload、未启用 MIG 的 RTX 5090/GB202，两个 control 的
   physical handler 与 GB202 HAL target 都已静态存在；只要 runtime object、
   control allowlist/permission 和参数均接受，请求应返回当前 effective topology。
2. `GET_FS_INFO/LTS_MASK` 更适合后续安全观察，因为它只请求需要的 mask，且
   GSP 的 type-3 路径是纯读取；但其 export flags 不含
   `API_LOCK_READONLY`，故不能仅凭命令名或 flags 宣称任意 live 调用绝对无风险。
3. 旧命令和新 type-3 在 physical GSP 中共用 `FB +0x9c0`，所以在同一非 MIG
   时刻，两者的 LTS mask 应一致；旧命令额外给出 coarse LTC mask/count。

## UNKNOWN

1. 当前这台机器的 live RM control allowlist、句柄建立和最终返回码；本轮故意
   没有触碰 GPU，不能把静态 handler 存在写成“已经在本卡调用成功”。
2. 当前运行中的驱动/GSP 是否正好与被审计 hash 完全一致；版本号和 artifact
   可核对，但未向设备查询实际 loaded firmware。
3. raw `0x8234e0` 如何逐 bit roll up 到 effective `0x822900`，以及 GSP/FSP/
   reset/reinit 在何时采纳或覆盖它。
4. effective mask 中的 disabled bit 属于永久 defect、SKU floorsweep、repair、
   runtime software override 还是其他来源。这个 API 没有 provenance 字段。
5. 被关闭位置重新启用后的物理健康、数据一致性或稳定性。拓扑查询不是自检。
6. non-GSP/monolithic GB202 环境下新 `GET_FS_INFO` 的本地实现情况；可见 host
   export 设计为 route-to-physical，不能从 GSP handler 反推 monolithic 支持。

## 给主报告的纠错短句

可以安全写成：

> 610.43.03 的 CPU-RM non-VF **本地** `GET_LTC_INFO_FOR_FBP` HAL binding
> 是 `NV_ERR_NOT_SUPPORTED` stub，但在 Blackwell 的 GSP-offload 路径中，
> `ROUTE_TO_PHYSICAL` 会先 RPC 到物理 GSP；该 GSP 对旧命令和
> `GET_FS_INFO/LTS_MASK` 均有真实 handler，并在 GB202 上经 FB `+0x9c0`
> 返回 current/effective LTS enable mask，而非 raw/repair map。

不应写成：

> `GET_LTC_INFO_FOR_FBP` 在 normal non-VF RTX 5090 上必然是 stub。

也不应写成：

> `GET_FS_INFO/LTS_MASK` 能读出 raw fuse、repair provenance 或被屏蔽单元的
> 健康状态。

## 人话版

驱动这边看起来像有两个“问显卡现在开了哪些 L2 小块”的接口。旧接口在 CPU
驱动自己的 non-VF 代码里确实放了个“这里不支持”的假门，但 5090 正常工作时
请求会先被转交给显卡上的 GSP，GSP 里是真有门、也真有处理代码，所以不能因为
CPU 那个假门就说整条路走不通。

不过它读到的是“显卡现在实际启用了哪些块”的结果表，不是“出厂原始熔丝写了
什么”，更不会告诉我们某个关闭块究竟是坏的、被 SKU 人为砍掉的，还是某次
修复/初始化决定关掉的。它很适合作为以后只读基线和前后对照，但本身不是解锁
手段，也不是坏块检测器。

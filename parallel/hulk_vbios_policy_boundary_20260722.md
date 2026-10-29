# GB202 `0x8200f8`：HULK / VBIOS / FSP_RUN 授权边界复核

日期：2026-07-22（Asia/Singapore）

## 范围与安全边界

本轮只做静态文件读取和本地字节/字符串/小窗口反汇编检查。没有运行 MODS、
updater、nvflash、固件或未知二进制；没有访问 GPU 设备节点、BAR/MMIO、
PCI config、debugfs；没有 reset、rebind、刷写或永久修改。

检查对象：

- 四份本地 GB202 ROM/NVFW：
  - `vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom`
  - `vbios_diff/unverified_TPU_280522_ASUS_Astral_1043-89E3_98.02.2E.40.85.rom`
  - `vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw`
  - `vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw`
- 当前抽取出的 GSP raw image：`/tmp/gsp_inner_19f040_a.elf`
- 610.43.03 开源 RM：`/usr/src/nvidia-610.43.03/src/nvidia`
- 既有项目报告：`parallel/vbios_fsp_inventory.md`、
  `parallel/bcrt_manifest_coverage.md`、`parallel/falcon_manifest_table.md`、
  `parallel/gb202_610_arch.md`、`parallel/gsp_f8_hulk_audit.md`

## 结论先行

1. **没有找到 VBIOS/NVFW 明文策略。** 四份 ROM/NVFW 中没有
   `0x8200f8`、`0x8200dc`、`0x8200d0`、`0x820040`、`0x8234e0`
   这些目标寄存器常量，也没有 `HULK`、`PLM`、`PRIV`、`fuse`
   明文字串；只有 `FSP_RUN` tag。
2. **`FSP_RUN` 是最强 carrier 候选，但不是可手改配置表。**
   GeForce 与 RTX PRO 6000 的 `FSP_RUN` envelope 确实不同；同时该 envelope
   有 SHA-384 记录覆盖，记录本身又被上一层 SHA-384 覆盖。当前没有闭合到可
   重签的 root/key，也没有解密后的 plaintext。
3. **GSP 里存在 HULK/FWSECLIC 词汇，但 `VBIOS_VERIFY_HULK_*`
   目前只落到错误码 formatter。** 这些字符串证明固件库认识“VBIOS verify
   HULK”这类错误名；当前交叉引用没有证明 GB202 正在从 VBIOS 读取一个可用的
   HULK KA 或证书并据此开放 `0x8200f8`。
4. **真实可见的 HULK host 入口仍是证书/激活路径。**
   GSP raw image 中有 `RmActivateHulk`、`RMHulkCertSize`、`RMHulkCert`
   配置项引用；既有审计已证明该路径把 HULK payload 作为 NVDM type `0x11`
   发往 FSP。卡点是签名证书、设备/SKU 绑定和 FSP/FWSECLIC 策略，不是普通
   BAR0 写法。
5. **当前“合法 f8 路线”的实际缺口很窄：需要 NVIDIA 签过且适用于本设备/
   本生命周期的 HULK 授权材料，或者需要能被本卡 secure-loader 接受的
   VBIOS/FSP_RUN 授权对象。** 本地材料还没有这两者。

## 1. VBIOS/NVFW 直接字节搜索

对四份 canonical ROM/NVFW 扫描以下字节/字符串：

```text
0x8200f8 / 0x8200dc / 0x8200d0 / 0x820040 / 0x8234e0
HULK / hulk / PLM / GFW / PRIV / fuse / FSP_RUN
```

结果：

| 样本 | 命中 |
|---|---|
| RTX 5090 FE `98.02.2E.00.03` | `FSP_RUN` at `0x11b331` |
| ASUS RTX 5090 `98.02.2E.40.85` | `FSP_RUN` at `0x11b331` |
| Dell RTX PRO 6000 `98.02.8D.00.01` | `FSP_RUN` at `0x128131` |
| HPE RTX PRO 6000 `98.02.9E.00.01` | `FSP_RUN` at `0x12cd31` |

**FACT：** 上述四份样本中，没有目标寄存器常量，也没有 HULK/PLM/权限相关
明文字串。`FSP_RUN` 是 descriptor 内的可打印 tag，不是公开字段定义。

**边界：** 负结果只排除明文/literal。策略仍可能在加密、高熵、压缩或私有编码
的 `FSP_RUN` envelope 中，也可能在 device ROM/FSP 内部。

## 2. `FSP_RUN` descriptor 差异与完整性边界

既有 `parallel/vbios_fsp_inventory.md` 已经把四份 raw image 去重成三个
`FSP_RUN` 字节对象：

| 分组 | `FSP_RUN` envelope |
|---|---|
| GeForce common：FE + ASUS | 完全相同 |
| Dell RTX PRO 6000 8D | 与 GeForce 不同 |
| HPE RTX PRO 6000 9E | 与前两者不同 |

descriptor 的明显差异集中在长度/版本/高熵 private 字段：

```text
GeForce word1 = 0x29400
Dell Pro word1 = 0x36c00
HPE Pro  word1 = 0x37000
```

`parallel/bcrt_manifest_coverage.md` 与
`parallel/falcon_manifest_table.md` 又闭合了两层 hash 关系：

```text
FSP_RUN descriptor + immediate bytes
        <- exact SHA-384 entry
two-entry hash table
        <- exact SHA-384 at nested-image +0x209
```

**FACT：** `FSP_RUN` 的 on-disk envelope 不是一个随便能改的孤立 blob；至少有
局部 hash record 和上一层 digest 约束。

**UNKNOWN：** `+0x209` digest 再往上的正式签名 schema、root key、lifecycle/SKU
policy 尚未闭合。当前不能重签或构造可被设备接受的修改版。

## 3. GSP 中 HULK 字符串和 `VBIOS_VERIFY_HULK_*`

当前 GSP raw image `/tmp/gsp_inner_19f040_a.elf` 的直接字符串命中：

```text
NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HULK_INIT_FAIL        0xe2cc70
NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HULK_KA_NOT_FOUND     0xe2cca8
NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HULK_TYPE_INVALID     0xe2cce0
NV_FWSECLIC_ERR_CODE_CMD_VBIOS_VERIFY_HULK_SIG_INVALID      0xe2cd18
CERT_T7_REG_OVERRIDE_TYPE_UNKNOWN                           0xe2d015
CERT_HULK_REG_READ_BACK_VERIFY_MISMATCH                     0xe2d3e5
CERT_HULK_REG_RMW_RBV_READ_BACK_VERIFY_MISMATCH             0xe2d425
PRI_TRANSACTION_ERROR                                       0xe2d51d
RmActivateHulk                                              0xe77698
RMHulkCertSize                                              0xe776a8
RMHulkCert                                                  0xe776b8
```

同一文件中，目标寄存器常量的 little/big endian 精确搜索均为 0 命中：

```text
0x8200f8  0
0x8200dc  0
0x8200d0  0
0x820040  0
0x8234e0  0
```

对四个 `VBIOS_VERIFY_HULK_*` 字符串做 AUIPC/ADDI 交叉引用扫描，只找到：

```text
INIT_FAIL      0x011bf958 -> 0x011bf95c
KA_NOT_FOUND   0x011bf936 -> 0x011bf93a
TYPE_INVALID   0x011bf914 -> 0x011bf918
SIG_INVALID    0x011bf8f2 -> 0x011bf8f6
```

该窗口是密集重复的错误码到字符串转换块。每段都形如：

```text
load error-name string
load numeric error code
load severity/domain value
tailcall common formatter
```

其中这四项对应的 error code 连续为 `0x30`、`0x2f`、`0x2e`、`0x2d`。

**FACT：** 当前交叉引用证明的是 FWSECLIC 错误名格式化表，不是实际
VBIOS/HULK verifier 的控制流。

**INFERENCE：** 固件库确实包含 HULK 证书、register override、RMW、readback
verification 相关错误类型；HULK 机制有能力携带受签名约束的寄存器动作。

**UNKNOWN：** 当前材料没有证明本卡 VBIOS 中存在可用 HULK KA，也没有证明
`0x8200f8` 在 HULK 授权范围内。

## 4. `RmActivateHulk` / `RMHulkCert*` 的意义

`RmActivateHulk`、`RMHulkCertSize`、`RMHulkCert` 的 xrefs 落在 GSP 配置读取/
准备路径附近：

```text
RmActivateHulk   0x0150f2ea -> 0x0150f2ee
RMHulkCertSize   0x0150f310 -> 0x0150f314
RMHulkCertSize   0x01a91c5a -> 0x01a91c5e
RMHulkCert       0x0150f606 -> 0x0150f60a
RMHulkCert       0x01a91cb2 -> 0x01a91cb6
```

小窗口反汇编显示该路径读取 `RmActivateHulk` 布尔/配置项，读取
`RMHulkCertSize`，分配 `size + 4` 形式的 buffer，再读取 `RMHulkCert` 内容。
既有 `parallel/gsp_f8_hulk_audit.md` 进一步把后续动作和 NVDM HULK type `0x11`
发送路径关联起来。

当前 artifact 的直接 call-target 扫描还校正了旧报告中的 sender 地址：统一
sender 是 `0x0150e918`，共有 18 个直接 caller；旧写法 `0x0150e8d8` 在本轮
扫描中没有直接 caller。两条 HULK 分支分别是：

```text
external cert:   0x0150ef64 -> 0x0150e918, type=0x11, length=cert_size+4
flashed token:   0x01510136 -> 0x0150e918, type=0x11, length=4, payload=0
```

**FACT：** stock GSP/MODS 确有“给我一个 HULK 证书/激活闪存 license”的入口。

**FACT：** 公开 610 host 源只公开 NVDM routing：GB202 上 HULK type `0x11`
经 FSP SEID 0；公开源码没有 HULK payload schema、签名验证逻辑、range whitelist
或 PLM lowering/restore 规则。

**当前判断：** 这条路如果能开 `0x8200f8`，应当表现为“提供一个被 FSP/FWSECLIC
接受的 HULK 授权对象”，而不是先手动写 `f8` 再等固件返回。

## 5. 对“特定 BIOS / 特定证书 / 特定时序”的区分

### 特定 BIOS

可能，但当前证据不支持“普通修改 VBIOS 就行”：

- Pro 与 GeForce 的 `FSP_RUN` envelope 确实不同；
- 但没有明文 `f8`/L2/HULK policy；
- envelope 受 hash/signature-like 结构约束；
- RTX PRO 6000 VBIOS/NVFW 与 5090 的 SM、显存、SKU、板级上下文不同，直接刷写
  不在安全候选内。

### 特定证书

这是目前最符合证据的模型：

- HULK type `0x11` 是公开命名的 FSP NVDM 类型；
- GSP/MODS 有 `RMHulkCert*` 输入；
- FWSECLIC 字符串说明 HULK cert 支持 register override/RMW/readback
  verification；
- 本地旧 Figueroa HULK 样本没有 GB202、2b85、`0x8200f8`、L2 raw/effective
  目标地址。

MODS JS 参数层确认证书输入格式可以是 importable `.js` 或二进制 `.hulk`：
`ArgHandleHulk()` 会先尝试 `HULK_DIR`，`.js` 路径读取 `g_hulk_cert`，
`.hulk` 路径用 `InteractiveFile.ReadBinary()` 读原始 bytes，随后设置
`g_HulkCert/g_HulkCertLength`。本地项目树目前只发现旧 Figueroa `HULK*.js`
样本，没有发现可疑的 GB202/`0x2b85` `.hulk` 证书文件。

公开驱动包内的 `hal/library/cryptlib` 头文件只提供通用 SPDM/X.509、RSA/ECDSA、
SHA-384/HMAC 等接口声明；没有 HULK、VBIOS verify HULK、GB202 lifecycle 或
register override certificate 的私有 schema。因此它只能解释算法尺寸背景，不能
替代 FSP/FWSECLIC 私有 parser。

缺口是没有本卡/本 SKU/本 lifecycle 可接受的签名授权材料。

### 特定时序

不能完全排除，但当前不是主解释：

- 直接 `task2/subobject1` 已能打开 `0x8200d0/0x8200dc`，但不打开
  `0x8200f8`；
- 直接写 `0x8200f8` 立即读回旧值，FSP mailbox 和 kernel log 表面没有错误；
- `0x8200f8` 不是 host 代码里已见的普通 prepare/latch writer。

因此“还缺一个时序动作”只有在能找到合法 HULK/FSP 消息或 VBIOS-carried 授权
对象时才值得继续；盲试寄存器序列目前信息增益低。

## 6. 下一步仍有价值的静态方向

1. 继续拆 `RMHulkCert*` path：把证书 buffer 格式、长度字段、NVDM payload
   头部和错误处理边界对齐，但不伪造、不发送未知证书。
2. 对 `FSP_RUN` 上层认证继续做 bounded parser mapping：确认 `+0x209` digest
   到 adjacent signature-shaped bytes 的正式 signed range。目标是判断“能否替换
   为另一份官方对象”，不是尝试重签。
3. 对本地/公开流出的 HULK cert 样本做离线字段清点：找 chip ID、device ID、
   lifecycle、register override target。只接受静态解析，不在宿主执行。
4. 如果以后要做 runtime，只限隔离 VM、已知可恢复 reset 边界，并且只验证
   “官方/已签授权对象是否被接受”；不要在宿主桌面卡上盲写新的 PLM/熔丝路径。

## 当前一句话结论

按合法路线继续查，最现实的门槛不是“我们还差一个寄存器值”，而是
`0x8200f8` 属于更高一层的签名授权域。现有本地证据支持 HULK/FSP 能执行签名
寄存器动作，但没有发现能授权 GB202/5090 开 `0x8200f8` 或 L2 raw shadow 的
证书、VBIOS 明文配置或可修改策略表。

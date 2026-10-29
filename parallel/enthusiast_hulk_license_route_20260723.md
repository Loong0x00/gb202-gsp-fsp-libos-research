# GB202 L2 解锁：`Enthusiast.key` / HULK / InfoROM license 路线复核

日期：2026-07-23（Asia/Singapore）

## 范围与安全边界

本轮只做静态读取：

- 本地 Dell RTX PRO 6000 GB202 更新器：
  `vbios_diff/dell_8d_payload/RTXPRO6000_98.02.8D.00.01_FW_upgrade.bin`
- 本地 HPE 包中保存的 `nvflash`：
  `vbios_diff/hpe_static_tools/nvflash`
- 本地 Dell `.nvfw/.fwpkg`、本地 RTX 5090 ROM 批量样本；
- 公开网页只用于确认 `USER_FW_MOD`/`licreq` 入口不是本地孤例。

没有运行 updater、`nvflash`、MODS 或未知二进制；没有访问 GPU、BAR/MMIO、
PCI config、debugfs；没有 reset、刷写或持久修改。

Dell 官网页面列出
`RTXPRO6000_98.02.8D.00.01_FW_upgrade.tar.gz` 的 SHA-256 为
`023ef3028e6360946794d7a48e85233021c708a38cc228a7a0e39ab876bb9445`；
本地保存的 tar 包复算值相同。因此下面的 Dell updater 证据来自官方 Dell
发布包，而不是第三方重打包样本。

## 结论先行

1. **`Enthusiast.key` / `USER_FW_MOD` 是真实的 NVIDIA 固件授权机制线索。**
   本地 HPE `nvflash` 和 Dell PRO6000 更新器都包含 `--licreq ... USER_FW_MOD`、
   `--license=... firmware.rom`、`--wrhlk`、`--rdhlk`、`--licflash` 等入口。
2. **它不是本地签名器。** 工具能生成 request、读取/写入/使用 license/key，
   但本地没有发现可用的 `Enthusiast.key`、GB202 `.hulk/.cert/.lic` 或
   `0x2b85` HULK 授权对象。
3. **它更像“官方/厂商签发授权对象”流程。** 公开 NVIDIA Developer Forum 上也有人
   提到 `nvflash64 --licreq=LicenseRequest.bin USER_FW_MOD`，但没有公开可用的
   生成方法或私钥。
4. **这条线对 L2 的意义是间接的。** 它能解释“为什么修改 VBIOS/固件需要授权”，
   也解释 HULK/InfoROM license 入口从哪里来；但没有证明存在能打开
   `0x8200f8` 或 raw L2 shadow 的公开授权文件。

## 本地静态证据

### HPE `nvflash`

`strings -a -t x vbios_diff/hpe_static_tools/nvflash` 中可见：

```text
--licreq=LicenseRequest.bin USER_FW_MOD
--license=License.hulk vbios.rom
--wrhlk=License.hulk
--installkey=Enthusiast.key
--keyinfo=Enthusiast.key
Example: Provide Enthusiast.key to flash "firmware.rom"
ERROR: License authorization failed
The current firmware version is not supported to install the Enthusiast key.
The current display adapter is not supported to install the Enthusiast key.
Enthusiast key installed successfully.
```

这说明 `nvflash` 同时认识：

- 生成请求：`licreq` / `USER_FW_MOD`
- 安装 key：`installkey`
- 查看 key：`keyinfo`
- 写 HULK：`wrhlk`
- 用 license/key 刷固件：`--license` 或 `--key`

### Dell RTX PRO 6000 updater

`strings -a -t x ...FW_upgrade.bin` 中可见：

```text
--licenseinfo
--lichelp
--rdhlk <filename>
--wrhlk <filename>
--licinfo <filename>
--licreq <filename>,<reqType>
Provide a HULK license file
--license <filename>
--licflash <filename>
--wrhlk license.hulk
License filename must have a *.lic extension
License validation failure.
--licreq <filename>.bin USER_FW_MOD
Could not generate a license for this request.
Command to generate Enthusiast key request file
Enthusiast key request file
```

同时该 updater 还包含 InfoROM/license/HULK/FWSECLIC 错误族：

```text
License Image does not have ULF object.
License Image does not have HLK object.
HULK Payload
HULK License Information
NV_UCODE_CMD_COMMAND_LICVERIFY
NV_UCODE_CMD_COMMAND_HULKPROC
NV_UCODE_ERR_CODE_CERT_HULK_ECID_MISMATCH
NV_UCODE_ERR_CODE_CERT_HULK_DEVID_MISMATCH
NV_UCODE_ERR_CODE_VERIFY_ENG_HULK_3AES_SIG_MISMATCH_WITH_GPU_FUSE
NV_UCODE_ERR_CODE_VERIFY_ENG_HULK_LICENSE_HULK_AES_SIG_INVALID
```

这与旧 MODS HULK 样本、GSP `RMHulkCert*` 输入和 FSP NVDM type `0x11`
互相吻合：HULK/license 是实际存在的一套授权通道。

## 本地负结果

对以下范围做了静态文件名和内容检查：

- `/home/user/Downloads`
- `/home/user/rt_5090_project`
- Dell `.nvfw/.fwpkg`
- RTX 5090 ROM 批量样本
- MODS 解包目录

没有发现可用的：

```text
*.hulk
*.cert
*.lic
*.ulf
*.upr
*.key
```

命中的主要是普通开源 `LICENSE` 文件、MODS 自带旧 Figueroa HULK JS 样本、
HPE/Dell 固件许可文本，以及 updater/nvflash 自身的命令帮助字符串。

对 Dell `.nvfw/.fwpkg` 和 5090 ROM 的 `LIC/ULF/UPR/HLK/HULK/LU` 结构扫描也没有
发现清晰的嵌入式 license 对象。Dell `.fwpkg` 仍符合既有结论：PLDM header 后
直接是一份 NVFW；没有额外 license/cert payload 尾巴。

## 对当前 L2 目标的含义

这条路线能回答“为什么不能自己改 VBIOS/固件再刷”：

- host 工具认识固件授权 key/license；
- 固件/工具也认识 HULK、HLK、ULF、UPR、ECID、DEVID、GPU fuse AES 签名等约束；
- 没有合法签发对象时，普通修改会在 certificate/license/FWSECLIC 路径被拒。

但它还不能回答“怎么开 32 MiB L2”：

- 没有发现 GB202/`0x2b85` 的 HULK/license；
- 没有发现针对 `0x8200f8`、`0x8200dc`、`0x820040`、`0x8234e0` 的授权动作；
- 没有发现本地可生成/签发 `Enthusiast.key` 或 `.hulk` 的工具链；
- `USER_FW_MOD` 看起来是 request 类型，不是离线签名算法。

## 当前判断

`Enthusiast.key` / HULK / InfoROM license 是一个真实但受控的授权生态。
如果存在官方签发、绑定本设备/生命周期、并允许相关 register action 的 HULK 或
USER_FW_MOD 授权对象，它可能成为合法入口；当前本地和公开材料没有发现这样的对象。

因此这条路线当前不能直接推进到 L2 解锁，只能作为解释 VBIOS/FSP/HULK 权限边界的
重要证据。

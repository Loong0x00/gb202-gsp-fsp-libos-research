# FSP 相关【明文】代码摘录(来自 GSP-RM 固件)

来源: `/tmp/fwscan/gsp-570.144.bin`(63.5 MB 明文 ELF,驱动加载的 GSP 固件)
映射: VA = 0x01000000 + (文件偏移 - 0x40)(已用 166,204 条 auipc+addi 与已知串交叉验证)

| 名称 | 说明 | VA 段 | 字节 | 指令数 |
|---|---|---|---|---|
| `fwsec_lic_client_012d2000.bin` / `.asm` | FWSECLIC/UDE 客户端模块(错误码上报,440 个调用点) | 0x012d2000-0x012d8000 | 24576 | 0 |
| `crypto_lib_01c38000.bin` / `.asm` | AES/加密库(AES START / kslot / AES-GCM 跟踪串在此段) | 0x01c38000-0x01c46000 | 57344 | 0 |
| `acr_sec2_opts_018e0e00.bin` / `.asm` | ACR/SEC2 选项消费点(RMAcrExecuteOnSec2 等) | 0x018e0e00-0x018e2000 | 4608 | 0 |
| `sec2_ucode_load_018f5600.bin` / `.asm` | SEC2 ucode 装载选项点(ucode_data/manifest/RmDisableSec2Load) | 0x018f5600-0x018f5d00 | 1792 | 0 |

> 注意:这是 **GSP-RM 侧的 fwsec/加密客户端代码**(明文 ✓),不是 FSP 自己的 Falcon 微码(那份只有密文 ✗)。

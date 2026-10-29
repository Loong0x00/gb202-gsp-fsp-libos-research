# GB202 VBIOS x86/UEFI 是否解析 Falcon descriptor v6：有界静态排除

日期：2026-07-22（Asia/Singapore）

## 结论

四份已保存 GB202 raw image 的 **legacy x86 option-ROM** 和解开的 **UEFI GOP
PE32+** 内，都没有找到主机代码明确选择或解析：

- descriptor 首字 `0x0050060d`（flags `0x0d`、version `6`、size `0x50`）；
- Falcon entry `app=0x24,target=0x0f`；
- 明文 `FSP_RUN`。

目标 entry/descriptor 确实存在，但位于 x86/UEFI code image 之外的后续表/数据
区。因此这是“VBIOS 携带/暴露目标对象，但未发现 legacy BIOS/GOP 是其
consumer”的 **bounded negative**，不是对一切间接路径的全局否定。

## 范围与安全边界

只读取四份 canonical raw image，复用 `gb202_vbios_diff.py` 的
`load_image()/parse_pci_chain()`（SHA-256
`90cefd37e109684119e98c5ab64ef382048710dcdc344e1cd4bb5d70abb517eb`）。没有运行
ROM、GOP、updater、`nvflash`、MODS 或 firmware；没有访问 GPU/设备/MMIO、网络、
reset/rebind 或写入。

检查限于四个 64,000-byte legacy image、四个约 184 KiB GOP PE 和各自 `.text`；
只做精确 byte/string、立即数分类和小反汇编窗口，没有 CFG 恢复或反编译。

## host code image 范围与 hash

| 样本 | legacy x86 range / SHA-256 | UEFI code-type=3 range / raw SHA-256 | 解码 GOP PE bytes / SHA-256 |
|---|---|---|---|
| FE 2E.00.03 | `[0x38000,0x47a00)` / `276719b59acd9cc623e589489539ceb02bab2d2f0a2ba5a43e0b14a49c08e0b6` | `[0x47a00,0x5fa00)` / `346720d984e813581a622039330b9745509256a24c0c1179cb319b757515d26c` | 184,544 / `67a7916e27f37605c0b3cfbc5bdf7bf61000e3d847b4b49a5b2714a71dc2b18a` |
| ASUS 2E.40.85 | `[0x38000,0x47a00)` / `a301aa0070ef6ff249492fc6a8a872c1ee6cde6876f49b5a21d6d66348380a6d` | `[0x47a00,0x5fa00)` / `ad7451f5337504034301cd2cdc28d00b34082c41090ef9400a61f072b7474820` | 184,416 / `e6563d87de6b60bff5fc89cde2826377b31fea23dd6ab31303449c645e4b6369` |
| Dell Pro 8D | `[0x3b000,0x4aa00)` / `2955e01b854e4f1318c7700c2a4197567cfa8f34c008fc380be7e548cccf5b5d` | `[0x4aa00,0x62a00)` / `1a4813d6cbb9a5a7a8ac79c551082d3583c3cc952cc4dc95b34196c27e70d0e4` | 184,544 / `67a7916e27f37605c0b3cfbc5bdf7bf61000e3d847b4b49a5b2714a71dc2b18a` |
| HPE Pro 9E | `[0x3b000,0x4aa00)` / `3b00f0d32e15995271acbc0452acf8ac52080156010ac5b377c08e44c797fbeb` | `[0x4aa00,0x62a00)` / `0210c638a4c2300e7aaf3e8f9ed6448af39c63427043225511cfd00878d4595d` | 183,808 / `4938943b351d3609a62fb9f0f0458f04645b284c4d559e652158dc95aaf8f191` |

四份 EFI ROM header 都是 machine `0x8664`、compression type `1`、EFI pointer
`0x550`。标准 EFI compression 离线解码后均为 5-section x86-64 EFI boot-service
PE，入口 RVA `0x308`；四份 `pefile.verify_checksum()` 均为 true。FE/Dell 的
compressed bytes 与 PE 逐字节相同。解码器只回放文件格式、从未调用 PE；当次
脚本 `/tmp/vbios_gop_decompress.py` SHA-256 为
`1a7b077aa0f2f46725eb254174d6306dcf1e4612fd37933f7bba71ed98dfe3ad`。

## 命中分类

### legacy x86

四个完整 legacy ranges 内：

- `0d 06 50 00`：0；`FSP_RUN`：0；`NVFW`：0。
- 每份存在常规 BIT/PCIR data，不能据此推成 private-v6 parser。
- raw `24 0f` 每份恰有 3 个；逐一反汇编都只是掩码指令：

```text
FE/ASUS +0x29a1: 24 0f        and al,0xf
FE/ASUS +0x2cc6: 24 0f        and al,0xf
FE/ASUS +0x7b49: 2e 80 24 0f  and byte ptr cs:[si],0xf

Dell/HPE +0x299d, +0x2cc2:    and al,0xf
Dell/HPE +0x7bc9:              and byte ptr cs:[si],0xf
```

### 解码 GOP

四份完整 PE 和 `.text` 内：

- `0d 06 50 00`、`FSP_RUN`、`FALCON`、`UCODE`、`NVFW`：均 0；
- `.text` immediate `0x0050060d` / `0x50060d` / `0x0f24`：均 0；
- FE/Dell/HPE `.text` 各 17 个 raw `24 0f`：15 个 `and al,0xf`、1 个 LEA
  displacement 尾字节、1 个跨在另一条 `cmp` 内；ASUS 16 个：15 个 `and`、
  1 个 LEA。没有 app/target compare。

GOP 明确有通用 PCIR 解析，例如 FE/Dell/HPE：

```text
0x315f cmp dword [rax+r8],0x52494350       # "PCIR"
0x6f95 cmp eax,0x52494350                  # "PCIR"
0x84e5..0x8508 逐字节比较 50 43 49 52     # "PCIR"
```

唯一真正的 `cmp al,0x24`（FE/Dell/HPE RVA `0x10283`；ASUS `0x101b7`）与
`0x18,0x1e,0x30` 并列，是 24/30/36/48 一组的显示格式/位深式分支，不伴随
target `0x0f`：

```text
cmp al,0x18
cmp al,0x1e
cmp al,0x24
cmp al,0x30
```

分开的常用整数也没有闭合成 v6 parser：8 个 `cmp ...,0x50` 全是 **byte**
compare，没有 vDesc `+0x02` 所需的 `word == 0x0050`。唯一形似 memory version
`==6` 的 RVA `0xd6a3` 位于按长度步进的 type-7 TLV 小循环，只读取下一字节；它
不检查 size `0x50`、flags `0x0d`、app `0x24` 或 target `0x0f`。

## 与目标数据的交叉定位

| 样本 | Falcon entry | descriptor |
|---|---:|---:|
| FE / ASUS | `0x9cf6f`，`24 0f 04 b3 0c 00` | `0x11b304`，word0 `0x0050060d`，`+0x2d` 为 `FSP_RUN` |
| Dell | `0xa0855`，`app=0x24,target=0x0f` | `0x128104`，同一 word0/tag |
| HPE | `0xa0d10`，`app=0x24,target=0x0f` | `0x12cd04`，同一 word0/tag |

这些 locators 全在上述 legacy/UEFI ranges 之外。整份 ROM 扫描命中的是
Falcon table/descriptor **数据**，不能自动升级成 x86/GOP consumer。

## FACT / INFERENCE / UNKNOWN

### FACT

1. legacy 与解码 GOP 中没有完整 vDesc 常量、`FSP_RUN` 或 app/target immediate。
2. 所有 raw `24 0f` 已归为其他指令编码；单独 `cmp 0x24` 也有明确的非 Falcon
   上下文。
3. GOP 有常规 PCIR/ROM table 处理；目标 Falcon entry/descriptor 在 host code
   image 外的数据区。

### INFERENCE

legacy/GOP 负责常规显示和 ROM/table 服务，VBIOS 携带 `FSP_RUN` envelope，后者
的认证/加载/执行 consumer 位于另一执行域。结合既有“公开 GB202 host RM 不上传
`FSP_RUN`、BootFSM 从 reset 启动 FSP”，device-internal 路径比 GOP 更符合事实。

### UNKNOWN

1. GOP 是否通过无 Falcon-specific literal 的间接通用接口触碰 Falcon table；
   动态构造、间接调用或外部 protocol 不被本次 bounded scan 排除。
2. v6 private body、`0x24/0x0f` 正式名称，以及 consumer 究竟位于 chip ROM、
   解密后 VBIOS object 还是另一 device-internal stage，仍未闭合。

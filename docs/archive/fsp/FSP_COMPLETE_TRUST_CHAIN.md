# NVIDIA RTX 5090 FSP 完整信任链 — 实验性安全模型

日期: 2026-09-28/29 超长马拉松(最终版)

## 摘要

通过 12+ 小时的系统性实验,完整逆向了 NVIDIA Blackwell (GB202) FSP
的启动信任链。发现 COT 层的验证字段(95% 的 payload)全部是摆设,
但 WPR 元数据层的签名验证是真实的。定位了确切的验证边界和错误码。

## 完整信任链(实验确认)

```
┌─────────────────────────────────────────────────────────┐
│ COT Payload (860B)                                      │
│ ├── version/size: 检查                                   │
│ ├── gspFmcSysmemOffset: 使用(boot args 地址)            │
│ ├── frtsSysmem/Vidmem: 使用                             │
│ ├── hash384[48B]:        ★完全忽略★ (实验2证明)          │
│ ├── publicKey[384B]:     ★完全忽略★ (实验4-5证明)        │
│ └── signature[384B]:     ★完全忽略★ (实验5证明)          │
├─────────────────────────────────────────────────────────┤
│ GSP_FMC_BOOT_PARAMS (256B, 无验证)                       │
│ ├── magic: 检查                                          │
│ ├── bootGspRmParams.gspRmDescOffset: 使用(WPR元数据地址) │
│ ├── bIcuEnabled: 使用(但默认已关)                        │
│ └── bScrubCbcSr: 使用(但默认已关)                        │
├─────────────────────────────────────────────────────────┤
│ GspFwWprMeta (~200B, ★签名在这里验证★)                   │
│ ├── magic (0xdc3aae21371a60b3): 检查                     │
│ ├── sysmemAddrOfRadix3Elf: 使用(ELF地址)→ 签名覆盖      │
│ ├── sysmemAddrOfBootloader: 使用 → 签名覆盖              │
│ ├── sysmemAddrOfSignature: 使用 → ★真正验证!★            │
│ └── sizeOfRadix3Elf: 使用 → 大小检查                     │
├─────────────────────────────────────────────────────────┤
│ GSP ELF 固件 (27MB, 受 WPR 签名保护)                     │
│ └── 修改任何字节 → 0x83e 错误                            │
└─────────────────────────────────────────────────────────┘
```

## GSP-FMC 错误码映射(实验确认)

| 修改字段 | 错误码 | 验证阶段 |
|----------|--------|----------|
| (无修改) | 无错误 | ✓ 启动成功 |
| ELF 地址 +0x1000 | 0x83e | ELF 内容验证 |
| ELF 大小 27MB→256B | 0xaff/0xb | 元数据/大小检查 |
| Bootloader 地址 +0x1000 | 0xaff/0xb | 元数据检查(同上) |
| 签名地址 = NULL | 0xa97/0x0 | 签名验证 |
| 固件改 1 字节 | (超时) | WPR2 锁定 |
| COT hash = 全FF | 无错误! | hash 被忽略 |
| COT publicKey = 我们的 | (超时) | 公钥根信任检查 |
| COT signature = 我们的 | (超时) | 签名用内部密钥 |
| Boot args 地址 → DMA | 0x927 | DMA 可达但格式/内容问题 |

## 关键发现

### 1. COT 是"加载指令"不是"信任链"
860 字节的 COT 中,816 字节(95%)的验证字段被 FSP 完全忽略。
COT 只告诉 FSP"boot args 在哪",不提供任何验证材料。

### 2. WPR 元数据是真正的安全门
签名验证发生在 WPR 元数据层,使用 FSP 芯片内的密钥。
宿主无法通过软件影响这一层的验证。

### 3. 三级验证检查点
```
检查点 1 (0xaff): 元数据有效性 + Bootloader 可读性
检查点 2 (0x83e): ELF 内容验证(通过签名)
检查点 3 (0xa97): 签名验证(独立检查)
```

### 4. 验证用 FSP 内部密钥
- 替换 COT 的 publicKey → 无效(FSP 用自己的)
- 替换 COT 的 signature → 无效(FSP 用自己的)
- WPR 的签名验证同样使用 FSP 内部密钥

## 攻击面总结(穷尽)

| 层级 | 攻击 | 结果 |
|------|------|------|
| COT | hash 伪造 | ✗ 字段被忽略(不是漏洞,是设计) |
| COT | publicKey 替换 | ✗ 根信任比对 |
| COT | signature 伪造 | ✗ 内部密钥验证 |
| COT | boot args 地址替换 | ✗ DMA 可达性问题(error 0x927) |
| Boot Args | ICU 禁用 | ✗ 本来就关 |
| Boot Args | WPR 元数据指针替换 | ✗ DMA 可达性 |
| WPR Meta | ELF 地址偏移 | ✓ Booter 读取!但验证失败 0x83e |
| WPR Meta | 大小截断 | ✓ Booter 读取!但格式错误 0xaff |
| WPR Meta | 签名置 NULL | ✓ Booter 读取!签名验证 0xa97 |
| WPR Meta | bootloader 地址偏移 | ✓ Booter 读取!但验证失败 0xaff |
| ELF | 修改 1 字节 | ✗ 签名验证失败 |
| FSP 消息 | 全部 | ✗ 解析器设防 |
| FSP 寄存器 | 全部 | ✗ badf 锁定 |
| CC 模式 | 六层防御 | ✗ 第六层硬件锁 |

## 意义

**NVIDIA FSP 的安全设计:**
- COT 的验证字段是历史遗留或未来兼容(当前不用)
- 真正的安全边界在 WPR 元数据的签名验证
- FSP 芯片内的密钥是物理信任根
- 宿主可控制"从哪加载"但无法控制"加载什么"(签名锁定)

**与学术/公开研究的差异:**
- 无公开报告指出 COT 验证字段被忽略
- 无公开的 GSP-FMC 错误码映射
- 无公开的 WPR 元数据攻击实验

## 剩余理论攻击面

1. **WPR 签名绕过**: 需要 FSP 固件逆向找到签名验证代码的 bug
2. **TOCTOU**: Booter 验证后、GSP 加载前的时间窗口
3. **ELF 内部漏洞**: GSP 固件的运行时漏洞(F-1 已有一个)
4. **侧信道**: 签名验证的功耗/时序分析
5. **物理**: 芯片级攻击(熔丝读取、fault injection)

## 文件索引

本文档: `FSP_COMPLETE_TRUST_CHAIN.md`
之前的分析:
- `COT_SIGNATURE_FINDINGS.md` — hash 不验的发现
- `FSP_TRUST_CHAIN_MODEL.md` — 初步模型
- `COT_FINAL_VERDICT.md` — COT 分析
- `FSP_MSG_LAYER_AUDIT.md` — 消息层审计
- `PRC_KNOB_MAP.md` — 47 knob 地图
- `CC_FINAL_REPORT.md` — CC 六层防御
- `SBR_RECOVERY_DISCOVERY.md` — SBR 恢复

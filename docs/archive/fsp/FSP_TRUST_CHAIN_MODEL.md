# FSP 信任链完整安全模型 — 实验确认版

日期: 2026-09-29 凌晨 (最终版)

## 完整实验矩阵

| 实验 | COT hash | COT publicKey | COT signature | 固件内容 | 结果 |
|------|----------|---------------|---------------|----------|------|
| 1. 基线 | 原始 | 原始 | 原始 | 原始 | ✓ GSP 启动 |
| 2. hash 破坏 | **全0xFF** | 原始 | 原始 | 原始 | **✓ GSP 启动!** |
| 3. 固件修改 | **全0xFF** | 原始 | 原始 | **改1字节** | ✗ FSP 拒绝 |
| 4. 公钥替换 | 原始 | **我们的** | 测试值 | 原始 | ✗ FSP 拒绝 |
| 5. 完整伪造 | 原始 | **我们的** | **我们的签名** | 原始 | ✗ FSP 拒绝 |

## FSP 验证模型 (最终确认)

```
COT Payload 字段           FSP 行为              实验证据
─────────────────────────────────────────────────────────────
version (2)               检查 (必须=2)         结构解析
size (0x35c)              检查 (必须=0x35c)     结构解析
gspFmcSysmemOffset        使用(从这里DMA读)      实验1-5
frtsSysmemOffset          使用                   结构解析
frtsVidmemOffset          使用                   结构解析
hash384[12]              ★完全忽略★             实验2: 全FF仍启动
publicKey[96]            ★完全忽略★             实验4-5: 替换无效
signature[96]            ★忽略(不用COT的)★      实验5: 伪造无效
                            ↓
                    FSP 用自己芯片内的公钥
                    直接验证固件内容
                    (不经过 COT 的任何字段)
```

## 关键结论

### 1. COT 的验证字段全是装饰品
hash384、publicKey、signature — FSP 都不用。这三个字段共 816 字节(占 COT 的 95%),全部是摆设。

### 2. FSP 的真正验证
FSP 从 gspFmcSysmemOffset 读取固件后,用**自己芯片内烧死的公钥**直接验证固件内容。宿主完全无法影响验证过程。

### 3. 安全等级
这是硬件级信任根 — 无法通过软件绕过。与 TPM 的 PCR 类似,FSP 的内部密钥是物理安全的。

## 攻击面总结 (穷尽)

| 攻击向量 | 结果 | 原因 |
|----------|------|------|
| PRC knob 溢出 | ✗ | 全部设防 |
| NVDM 消息 fuzzing | ✗ DoS only | 解析器完善 |
| MCTP 重组攻击 | ✗ DoS only | 有界限保护 |
| EMEM 越界写 | ✗ | FSP 主动毒化 |
| COT hash 伪造 | ✗ (hash 不验) | 字段被忽略 |
| COT 公钥替换 | ✗ | FSP 用内部密钥 |
| COT 签名伪造 | ✗ | FSP 用内部密钥 |
| 固件修改 | ✗ | 内部签名验证 |
| CC 模式强制 | ✗ | CPU TEE 硬件依赖 |
| FSP boot 命令注入 | ✗ | 循环依赖 |

## 剩余的理论攻击面

1. **FSP 内部密钥提取** — FSP ROM 可能可读(需要硬件级别的访问)
2. **签名验证算法 bug** — RSA 实现可能有边界条件(需要 FSP 固件逆向)
3. **侧信道攻击** — 签名验证的功耗/时序分析(需要物理设备)
4. **GSP 侧攻击** — F-1 已有 A 级发现,GSP 固件可能更软

## 技术产出

- 完整 COT 注入工具链(驱动补丁 + DMA buffer + RSA 签名)
- FSP boot 路径 TRACE 工具
- nvidia_modeset 卸载 bug 的发现和修复
- FSP 状态机映射(badf4100 → 自解锁 → runtime)
- SBR timing 精确控制方法

## 今晚全部文档

| 文件 | 内容 |
|------|------|
| `COT_SIGNATURE_FINDINGS.md` | hash 不验的发现 |
| `COT_FINAL_VERDICT.md` | 循环依赖分析 |
| `COT_INJECTION_FINDINGS.md` | 注入基础设施 |
| `FSP_MSG_LAYER_AUDIT.md` | 消息层全面审计 |
| `PRC_KNOB_MAP.md` | 47 knob 完整地图 |
| `PRC_COMPLETE_LOGIC.md` | PRC 协议 |
| `CC_FINAL_REPORT.md` | CC 六层防御 |
| `SBR_RECOVERY_DISCOVERY.md` | SBR 恢复方法 |
| `FSP_INFOROM_PERSISTENCE_20260928.md` | InfoROM 持久化 |
| 本文档 | `FSP_TRUST_CHAIN_MODEL.md` |

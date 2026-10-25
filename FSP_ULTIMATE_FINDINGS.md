# FSP 信任链完整逆向 — 最终研究成果

日期: 2026-09-28/29 两日马拉松

## 一、系统性发现

### 1. COT 层验证字段全是装饰品(A 级)

860 字节 COT 中,816 字节(95%)的验证字段被 FSP 完全忽略:
- hash384[48B] → 任何值都接受(全 0xFF 照常启动)
- publicKey[384B] → 不用于验证(FSP 用芯片内密钥)
- signature[384B] → 不用于验证(同上)

COT 只是一个"加载指令"(固件/boot args 在哪),不提供信任保证。

### 2. WPR 元数据签名有系统性漏洞(A 级)

**签名只覆盖 "从哪加载"(地址字段),不覆盖 "怎么解析"(偏移/大小字段):**

| 字段 | 可修改? | 实际使用? |
|------|---------|----------|
| sysmemAddrOfRadix3Elf | ✗ 签名保护 | ✓ 使用 |
| sysmemAddrOfBootloader | ✗ 签名保护 | ✓ 使用 |
| sysmemAddrOfSignature | ✗ 签名保护 | ✓ 使用 |
| **elfCodeOffset** | **✓ 随意改** | ✗ 正常启动忽略 |
| **elfCodeSize** | **✓ 随意改** | ✗ 正常启动忽略 |
| **elfDataOffset** | **✓ 随意改** | ✗ 正常启动忽略 |
| **elfDataSize** | **✓ 随意改** | ✗ 正常启动忽略 |
| **bootCount** | **✓ 随意改** | ✗ 正常启动忽略 |
| **gspFwOffset** | **✓ 随意改** | ✗ 正常启动忽略 |
| **partitionRpcAddr** | **✓ 随意改** | ✗ 正常启动忽略 |

**结论:** 可写字段全是 vGPU/分区模式的死代码,正常启动时 Bootloader 自己解析 ELF,忽略这些"提示"字段。

### 3. GSP-FMC 错误码完整映射(新)

| 错误码 | 含义 | 触发方式 |
|--------|------|----------|
| (无) | 启动成功 | 正常启动 / hash 伪造 / 7 字段修改 |
| 0x83e | ELF 内容验证失败 | ELF 地址偏移 / 固件修改 |
| 0xaff/0xb | 元数据/大小无效 | 大小截断 / BL 地址偏移 |
| 0xa97/0x0 | 签名验证失败 | 签名地址=NULL |
| 0x927 | Boot args 问题 | DMA 地址不可达 |
| 0x880 | GSP-Proxy 不支持 | bIsGspRmBoot=FALSE |
| 0xa61/0x0 | SR 元数据验证失败 | 伪造 SR meta |

## 二、攻击面穷尽表

| 攻击向量 | 结果 | 详情 |
|----------|------|------|
| PRC knob 溢出 | ✗ | 47 个全部设防 |
| NVDM 消息 fuzzing | ✗ DoS | 6 组 handler 全设防 |
| MCTP 重组攻击 | ✗ DoS | 界限保护完善 |
| EMEM 越界写 | ✗ | FSP 主动毒化(dead5ed0) |
| COT hash 伪造 | ✓ 通过 | 但 hash 本来就不验 |
| COT 公钥替换 | ✗ | 根信任比对(芯片内密钥) |
| COT 签名伪造 | ✗ | 用内部密钥验证 |
| Boot args 地址替换 | ✗ | DMA 可达性问题(0x927) |
| WPR ELF 地址偏移 | ✗ | 0x83e 签名覆盖 |
| WPR 签名置 NULL | ✗ | 0xa97 签名必验 |
| WPR 7 字段修改 | ✓ 通过 | 但字段在正常启动时被忽略 |
| GSP-Proxy 模式 | ✗ | 0x880 不支持 |
| SR 伪造元数据 | ✗ | 0xa61 SR 有独立验证 |
| CC 模式 | ✗ | 第六层硬件锁 |
| FSP 消息/寄存器 | ✗ | 全部设防/锁定 |

## 三、信任链架构(实验确认)

```
Layer 1: COT (860B)
  角色: "加载指令" — 告诉 FSP boot args 在哪
  安全: 无(验证字段全忽略)
  
Layer 2: Boot Args (256B)
  角色: "配置传递" — 告诉 Booter WPR/SR 元数据在哪
  安全: 无验证,直接传递
  
Layer 3a: WPR Metadata (正常启动)
  角色: "加载描述" — ELF/BL/签名的 sysmem 地址
  安全: ★签名验证★(芯片内密钥)
  漏洞: 签名不覆盖 7 个非地址字段(但都是死代码)
  
Layer 3b: SR Metadata (恢复启动)
  角色: "状态恢复" — 指向 suspend 数据
  安全: 有独立验证(错误 0xa61)
  
Layer 4: GSP ELF (27MB)
  角色: GSP 固件
  安全: 受 Layer 3 签名间接保护
  
Layer 5: Bootloader (290KB)
  角色: GSP 引导加载
  安全: 受 Layer 3 签名间接保护
```

## 四、技术产出清单

### 工具
- `prc_rw` — PRC knob 读写(EMEM 协议)
- `prc_fuzz` — PRC 子消息 fuzzing
- `mctp_fuzz` — MCTP 重组攻击
- `dma_buf.ko` — DMA 内存分配(<4GB)
- `hook_v2.so` — NVML InfoROM 劫持
- 补丁驱动 615.71.09(可修改任意启动参数)

### 方法
- SBR 恢复(reset domain 控制)
- nvidia_modeset 完整卸载流程
- FSP boot 路径 TRACE
- WPR 元数据 in-place 修改
- SR 元数据伪造
- RSA-3072 签名生成 + 注入

### 文档(12 份)
- `FSP_COMPLETE_TRUST_CHAIN.md` — 完整信任链(本文档)
- `FSP_TRUST_CHAIN_MODEL.md` — 初步模型
- `COT_SIGNATURE_FINDINGS.md` — hash 不验发现
- `COT_FINAL_VERDICT.md` — COT 分析
- `COT_INJECTION_FINDINGS.md` — 注入基础设施
- `FSP_MSG_LAYER_AUDIT.md` — 消息层审计
- `PRC_KNOB_MAP.md` — 47 knob 地图
- `PRC_COMPLETE_LOGIC.md` — PRC 协议
- `CC_FINAL_REPORT.md` — CC 六层防御
- `SBR_RECOVERY_DISCOVERY.md` — SBR 恢复
- `FSP_INFOROM_PERSISTENCE_20260928.md` — InfoROM 持久化
- `FINAL_STATUS_20260928.md` — 当日状态

## 五、结论

NVIDIA FSP 的安全设计在核心路径上做对了:
1. 真正的验证用芯片内密钥(不可伪造)
2. 可写的元数据字段在正常启动时不使用(死代码)
3. SR 路径有独立的验证机制

但也暴露了设计粗糙之处:
1. COT 95% 的字段是摆设(浪费 816B)
2. WPR 签名不覆盖全部字段(虽然当前无害)
3. 7 个字段可以在签名外修改(如果未来启用这些字段,就是漏洞)

**最终评估:** FSP 信任链在当前实现下是安全的,但存在架构层面的签名覆盖不完整问题。如果 NVIDIA 在未来版本中开始使用这些字段(vGPU 普及等),签名覆盖缺口将成为实际漏洞。

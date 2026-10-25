# CC 模式尝试 #3 — 结果与分析

日期: 2026-09-28 晚间

## 尝试的配置

```
FSP 侧 (PRC knobs):
  knob 6 (CCD) = 1 ✓ 写入成功
  knob 8 (CCM) = 1 ✓ 写入成功,flash 持久化

驱动侧 (615.71.09 补丁版):
  ✓ CPU 检查绕过 (conf_compute.c: if(0))
  ✓ bForceEnableCC = TRUE (硬编码)
  ✓ FSP GSP-FMC boot 禁用 (走直接 bootstrap)
  ✓ CC 固件选择逻辑确认 (gpuIsCCFeatureEnabled → ConcatenatedFMC)
```

## 结果: 驱动初始化挂死

即使禁用了 FSP boot 命令(直接 GSP bootstrap),驱动仍然在初始化时挂死。

## 根因分析

CC 模式需要**双侧配合**:

```
GPU 侧:  FSP CC knobs → GPU 硬件 CC 配置 → ✓ 我们能控制
CPU 侧:  SEV-SNP/TDX TEE → SPDM 认证 → ✗ 消费级 CPU 不支持
```

驱动的 CPU 检查不是人为障碍 — CC 模式的密钥交换和内存加密
**依赖 CPU TEE 硬件**。没有 SEV-SNP,SPDM 握手无法完成,初始化挂死。

## 已确认的完整链路

```
1. FSP CC knobs (6,8) = 1          ✓ PRC 写入成功
2. FSP 重启 → 读 knobs → GPU 进入 CC 硬件模式  ✓ (SBR 后生效)
3. 驱动加载 → gpuIsCCEnabledInHw = TRUE  ✓
4. CC 引擎构建开始                    ✓
5. CPU 检查                           ✓ (补丁绕过)
6. SPDM/密钥交换                      ✗ 挂死(需要 CPU TEE)
7. CC 固件加载                        未到达
8. CC 模式就绪                        未到达
```

## 结论

消费级 RTX 5090 上 CC 模式的阻塞点**不在 GPU 侧**:
- FSP 接受 CC knob 写入
- 硬件支持 CC 配置
- 驱动可以绕过 CPU 检查

**阻塞在 CPU 侧**: CC 的加密密钥需要通过 CPU TEE (SEV-SNP/TDX) 交换,
消费级 CPU 的 TEE 不对 GPU 驱动开放。这是架构级限制,不是驱动 bug。

## 可能的绕过方向

1. **Dev Mode**: `NV_REG_STR_RM_CONFIDENTIAL_COMPUTE_DEV_MODE`
   可能提供不需要完整加密的调试 CC 模式
2. **跳过 SPDM**: 找到并绕过 SPDM 初始化(深入驱动代码)
3. **模拟 TEE**: 在内核层面伪造 SEV-SNP 接口(工程量大)
4. **接受现状**: GPU 侧 CC 研究已到边界,CPU 侧是硬限制

## 本次尝试的新发现

- FSP boot 禁用后驱动仍然挂死 → 问题不在 FSP boot 命令
- CC 初始化有多层依赖,CPU TEE 是其中之一
- 驱动的 CPU 检查对应真实的硬件依赖,不只是 gating

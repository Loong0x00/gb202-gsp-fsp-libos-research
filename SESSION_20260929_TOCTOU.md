# 2026-09-29 凌晨 — TOCTOU 攻击完整实验 + FSP 最终防御模型

## 核心成果: FSP 全阶段完整性检查(新发现)

FSP 不是"验证一次就不管"——是**每个阶段都重新校验 sysmem 数据**:

```
T=0ms:    sendMessage → FSP 开始处理
T=0-5ms:  签名验证 → 检测到修改 → 0xFFFF(干净拒绝)
T=5-10ms: 验证完成 → FSP 响应 0x0(但后台加载继续!)
T=10-50ms: 后台加载 + 完整性检查 → 检测到修改 → FSP 锁死(badf4100)
T>50ms:   加载完成 → sysmem 死 → 写入无效果
```

**关键洞察: sendAndRead 返回 0x0 ≠ 一切完成。**FSP 异步加载,响应只是"验证通过"。

## 实验矩阵(全部实测,使用热重载方法)

| 写入时机 | 延迟 | sendAndRead | GPU | 含义 |
|----------|------|-------------|-----|------|
| Pre-send | - | 0xFFFF | 失败 | 签名验证 |
| MID-send | 0ms | 0xFFFF | 失败 | 验证中 |
| MID-send | 5ms | 0xFFFF | 失败 | 验证中 |
| MID-send | 10ms | 挂死 | 失败 | 加载中,FSP锁死 |
| MID-send | 20-45ms | 挂死 | 失败 | 同上 |
| MID-send | 50ms | 0x0或挂死 | 失败 | 边界(不稳定) |
| POST-send | 0ms | 0x0 | 正常 | 加载已完成(运气) |
| POST-send | 10ms | 0x0 | 失败 | 命中后台加载! |
| POST-send | 50ms | 0x0 | 失败 | 同上 |

## 热重载方法(新工具,无需断电)

```bash
# CC trick: 用 CC 模式强制 GSP 停止,然后重新 boot
/home/user/prc_rw w 8 1; /home/user/prc_rw w 6 1  # CC=1 → boot会失败
# ... SBR ...
modprobe nvidia &  # 驱动加载,boot 失败(CC=1)
sleep 5
/home/user/prc_rw w 8 0; /home/user/prc_rw w 6 0  # CC=0
sleep 25  # 驱动 retry → 正常 boot → 补丁代码执行!
```

## FSP TOCTOU 防御架构(最终模型)

```
sendMessage()
  └→ FSP 接收命令
      ├→ 阶段1: 签名验证 (0-5ms)
      │   └→ 读 sysmem → 签名检查 → 不匹配 → 0xFFFF
      ├→ 阶段2: 响应"验证通过" (5-10ms) → sendAndRead 返回 0x0
      └→ 阶段3: 后台加载 (10-50ms) ← 异步!
          ├→ 复制固件到 FB/GSP
          ├→ 持续完整性检查
          └→ 检测到修改 → FSP 锁死(badf4100, SCRATCH3=0xa)
```

**没有漏检窗口。每个阶段都校验。**

## 全部 FSP 攻击向量总结(穷尽)

| 攻击 | 结果 | 防御层 |
|------|------|--------|
| PRC 消息溢出 | ✗ | 16 子消息全设防 |
| NVDM fuzzing | ✗ | 256 类型全处理 |
| MCTP 重组 | ✗ | 界限保护 |
| EMEM 越界 | ✗ | 主动毒化 |
| COT 伪造 | ✗ | 验证字段全忽略(不是漏洞) |
| WPR 元数据 | ✗ | 签名覆盖关键字段 |
| CC 强制 | ✗ | 硬件锁(第六层) |
| TOCTOU | ✗ | **全阶段完整性检查** |
| SR 伪造 | ✗ | 独立验证(0xa61) |
| 固件修改 | ✗ | 两阶段检查 |

## GSP 方向成果

- ★ F-1: GPU_EXEC_REG_OPS 溢出(A 级,之前发现)
- ★ TOCTOU 基础设施(时序数据 + 热重载 + 写入工具)
- ★ POST-DELAY 10ms 命中后台加载窗口(GSP 方向可能有用)
- ★ 27MB ELF 地址获取 + 精确时序映射

## 技术产出清单

### 工具
- `prc_rw` — PRC knob 读写
- `prc_fuzz` — PRC 子消息 fuzzing  
- `race_v3/v4/v5` — TOCTOU 竞争模块
- `timing_monitor` — FSP boot 时序监控
- CC trick 热重载方法

### 方法
- FSP 处理时间线(0-50ms 各阶段)
- 两阶段完整性检查发现
- sendAndRead 异步加载发现
- 热重载(无需断电重启)

### 驱动补丁基础设施
- `g_savedFwVa` 全局映射保存
- MID-SEND 写入框架
- POST-DELAY 写入框架
- RACE_SETUP 地址链(COT→BA→WPR→ELF)

## 下一步建议

1. **GSP RPC 全面 fuzzing** — 基础设施全有,F-1 证明有溢出
2. **POST-DELAY GSP ELF 修改** — 只改 ELF 不碰 FMC(需要 ELF 映射)
3. **FSP 固件逆向** — 需要解密/提取运行时代码
4. **硬件侧信道** — 需要物理设备

## 文件索引(今日新增)
- `TOCTOU_FINAL_REPORT.md` — 完整实验报告
- `GSP_TOCTOU_SUCCESS.md` — GSP 方向 TOCTOU 基础设施
- `FSP_ULTIMATE_FINDINGS.md` — FSP 完整发现
- `FSP_COMPLETE_TRUST_CHAIN.md` — 信任链模型
- 本文档: `SESSION_20260929_TOCTOU.md`

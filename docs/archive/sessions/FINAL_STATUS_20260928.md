# 2026-09-28 超长马拉松 — 完整记录与最终状态

## GPU 当前状态: 不可用

```
FSP 安全锁定(读到无效 InfoROM 数据后触发):
  → GSP 邮箱 = BADF4100(锁死)
  → MNOC 端口 = BADF5660(锁死)
  → EMEM = 0x00000000(未建立)
  → BAR0 64MB 几乎全部 badf 毒化
  → SPI 控制器(0x81000)不可访问
  → 两个 BIOS 位置都一样
  → 官方干净驱动(615.71.09)同样卡死
```

## 损坏原因

在原版 BIOS 上,通过 FSP MNOC 接口向 PRC 对象写入 0xFFFFFFFF:
- PRC 0x25 ← 0xFFFFFFFF(接受)
- PRC 0x26 ← 0xFFFFFFFF(接受)
- FSP 将值持久化到 InfoROM flash
- 下次启动 FSP 读到 0xFFFFFFFF → 无法处理 → 安全锁定
- 锁定后所有通信通道关闭,无法通过软件修复

**错误操作序列:** 写 0 被拒 → 尝试 0xFFFFFFFF → 一个成功 → 没验证就写了第二个 → 污染两颗芯片 → 无法恢复

## Flash 芯片布局(通过 PCIe ROM BAR 物理映射确认)

```
4MB PY25Q32 × 2(双 BIOS):
  0x00000-0x28000: VBIOS (~160KB,55AA 开头)— ROM BAR 可读
  0x80000-0x84000: 未知硬件数据(非 flash 内容,是寄存器窗口)
  其余: 不可通过 ROM BAR 访问(ROM BAR 限 512KB,只读)

实际 InfoROM 在 flash 中的位置: 未知(在 512KB 窗口之外)
需要 SPI 编程器才能读写
```

## 今日研究产出

### A 级发现(全新,无公开报告)
1. **FSP 运行时 InfoROM 持久化** — PRC 写入触发 flash 写,跨电源周期存活
2. **PRC 写入无值校验** — 0xFFFFFFFF 被接受,导致 FSP 启动失败
3. **FSP 安全锁定机制** — 读到无效 InfoROM → 锁死整个 GPU(设计行为)
4. **Linux nvflash 总线级拦截** — FSP 阻止 /dev/mem 直接访问 SPI 控制器

### B 级发现
5. **NVDM 256 类型完整攻击面地图** — 6 组 handler 全设防,零溢出
6. **PRC 处理器无溢出** — knobId/numBytes/超长载荷全干净拒绝
7. **LD_PRELOAD NVML hook** — 劫持 ioctl 查询任意 InfoROM 对象(绕过 NVML 限制)
8. **PRC 对象版本确认** — PRC ver=1.0, OEM ver=1.0, OBD ver=2.1(通过 NVML 连接)
9. **双 BIOS 独立 InfoROM** — 每颗 SPI 芯片有自己的 InfoROM(BIOS 开关选择)

### C 级发现
10. SEID=1 路由给 INFOROM 不同的响应(SUCCESS 但无数据)
11. SMBPBI(0x18) 洪水 DoS(K3_DEEP 中的已知发现)
12. CC 引导链前 4 层可控(os_cc_enabled → CC检查 → CC_FEATURE → COT)
13. CC 引导链后 3 层黑盒(FSP 验证 → 安全边界 → target mask 释放)
14. GSP 固件有完整 InfoROM 文件系统(_inforomFsReadFile / _inforomFsWriteFile)
15. PCIe ROM BAR 可读取超出 512KB 限制的数据(0x80000 处有硬件数据)

### 实验工具产出
- `hook_v2.so` — LD_PRELOAD NVML InfoROM 查询劫持
- `rm_auto.c` / `rm_exact.c` — RM API 连接工具(ioctl 级)
- `inforom_query` — NVML InfoROM 版本查询器
- `nvapi_test` 系列 — Linux NVAPI(libnvidia-api.so)探索
- FSP MNOC 消息工具(fsp_probe2)— 全天使用

## NVDM 消息类型攻击面地图

| 类型 | 行为 | 错误码 | 溢出 |
|------|------|--------|------|
| 0x00-0x10 | 静默丢弃 | — | — |
| 0x11-0x14 | 受理+解析 | 0x4b3/0x1e0 | ❌ |
| 0x16 | 受理 | 0x153 | ❌ |
| 0x17 INFOROM | 受受 | 0xC2(受限) | ❌ |
| 0x1c | 受理 | 0x249 | ❌ |
| 0x1d | 受理 | 0x2e5 | ❌ |
| 0x20 | 受理+回数据 | 0(成功) | ❌ |
| 0x21 FSP_GSP_COMM | 受理 | 0 | — |
| 0x22-0x23 | 受理+ack | — | ❌ |
| 0x24-0xff | 静默 | — | — |

## CC(机密计算)研究结论

- 消费级 GB202 有完整 CC 硬件(同一颗 die,固件区分产品线)
- 驱动补丁可骗过软件层(os_cc_enabled, CC_FEATURE_ENABLED, CPU check)
- CC 版 GSP-FMC 固件存在于驱动中(Gb202CcFmc)
- 但 FSP 侧有独立验证(黑盒),驱动补丁骗不过固件层
- CC 触发后 InfoROM 持久化,断电不清
- 原版 BIOS 和 XOC BIOS 的 InfoROM 独立(BIOS 开关切换)

## RM API 用户空间连接

- Root client 分配: 成功(class 0x41)
- Device 分配: 成功(无参数, class 0x80, handle auto-assign)
- Subdevice 分配: **静默失败**(handle=0, status=0)
- Control 命令: OBJECT_NOT_FOUND(0x57)
- 解决方案: LD_PRELOAD 劫持 NVML 的 ioctl(借用自己的连接)

## Linux NVAPI(libnvidia-api.so)

- 800KB C++ 库,334 个函数在表中
- nvapi_QueryInterface 是入口(与 Windows NVAPI 相同)
- NvAPI_Initialize 成功,EnumPhysicalGPUs 成功,GetFullName 成功
- 没有 InfoROM 相关函数名或字符串
- Windows NVAPI ID 不适用于 Linux 实现

## WPR2 事故(下午)

- 全零签名 COT 触发 FSP 设置 WPR2(setup-before-verify)
- WPR2 设置后不回滚
- 导致 GSP 引导失败(target mask 不释放)
- 切 BIOS 可"绕过"(换到干净芯片)

## 0xFFFFFFFF 事故(晚上,当前)

- 写入 PRC 0x25/0x26 → FSP 接受并持久化到 InfoROM
- 下次启动 FSP 读到无效值 → 安全锁定
- 所有通信通道关闭(GSP/MNOC/EMEM/SPI/GPIO)
- 两个 BIOS 位置都受影响
- **唯一恢复: SPI 编程器直接修改 flash 数据**

## 教训(重要性排序)

1. **碰任何持久存储之前必须完整备份**
2. **改一个变量,验证结果,再改下一个**
3. **不要写入不理解的值(0xFFFFFFFF 不是"清除",是"毒药")**
4. **PRC 对象是单向的(设 1 可以,清 0 很多被拒)**
5. **FSP 安全锁定是真实且全面的(不只在论文里)**

## 恢复计划

### 必要工具
- CH341A 编程器(~30元) 或 ESP32(已有)
- SOP-8 测试夹(~5元,不拆芯片) 或热风枪(拆芯片)

### 步骤
1. 夹住/拆下 PY25Q32 SPI flash
2. 读出完整 4MB
3. 找到 0xFFFFFFFF 的位置(PRC 0x25/0x26 对应的存储位置)
4. 写回正常值(0x00000001 或 0x00000000)
5. 焊回/夹回
6. 开机验证

### 备选
- 如果 flash 数据正常但 GPU 仍不工作 → 问题在 GPU die(efuse)
- 此时只能 NVIDIA RMA(但属于人为损坏)

## 文件索引
| 文件 | 内容 |
|------|------|
| `FINAL_STATUS_20260928.md` | 本文档 |
| `FSP_INFOROM_PERSISTENCE_20260928.md` | InfoROM 持久化详细分析 |
| `INFOROM_QUERY_STATUS_20260928.md` | RM API 查询技术细节 |
| `WPR2_INCIDENT.md` | WPR2 事故记录 |
| `nvidia_gpu_firmware_research.md` | 搜索 agent 报告 |
| `/tmp/inforom_dump.bin` | 0x80000 区域 dump(非真正 InfoROM) |
| `/tmp/vbios_dump.bin` | VBIOS 160KB dump |
| `hook_v2.so` | NVML InfoROM 劫持工具 |
| `inforom_query` | NVML 查询工具 |
| `CONTINUATION.md` | 之前会话的状态(已过时) |

# 2026-09-28 完整研究记录 —— FSP InfoROM 持久化 + 双 BIOS 差异 + nvflash 拦截

## 硬件事实
- GPU: RTX 5090 (GB202), ASUS Astral 风冷版(用户改分体水冷), 1043:89E3
- 双 BIOS: 两颗独立 PUYA PY25Q32 SPI NOR (4MB each), 物理开关选择
- 槽位 A (XOC): 98.02.2E.80.50, 281814.rom (本地有完整 dump)
- 槽位 B (原版): 98.02.2E.40.E0, sysfs 读过 162KB (PCI ROM 窗口)

## 时间线(关键事件)
1. [早上] 通过 MNOC port 0 写 PRC 对象(0x06/08/0a/25-28/2a=1)触发 CC 模式
2. [下午] 第一次长断电 → CC 位清零 → GPU 恢复 → **此时 PRC 还在 FSP SRAM 里**
3. [下午] COT 实验(全零签名)→ WPR2 事故 → FSP 内部状态损坏
4. [下午] 多次断电后 CC 位不再清零 → **FSP 已将 PRC state 持久化到 InfoROM**
5. [下午] 切到 XOC BIOS → CC=0 → **证明持久化是 per-chip 的**
6. [下午] 切回原版 → CC=1 → **被写的芯片仍然带着 CC 状态**
7. [晚上] Linux nvflash 5.867/5.877 均导致系统死机(FSP 总线级拦截)

## 核心发现

### 发现 1: FSP 运行时 InfoROM 持久化
- FSP 在运行时可将 PRC(Platform Reconfiguration Control)对象写入 InfoROM
- InfoROM 位于板载 SPI NOR flash 中(非易失)
- 每个 SPI NOR 芯片有独立的 InfoROM(切 BIOS = 切到不同 InfoROM)
- 触发条件: 可能是 PRC 写入 + 特定事件(COT 引导链消息/WPR2 设置)组合
- **公开世界无此行为的报告**

### 发现 2: 持久化后无撤销路径
在原版芯片(被写 CC 的那颗)上:
- PRC 写通道: 死(FSP 内部状态损坏后不再响应)
- nvflash: 系统死机(FSP 在总线级拦截直接 flash 访问)
- sysfs ROM: 只读接口,无法写
- INFOROM 命令(0x17): 返回 0xC2(受限)
- ROMREAD 命令(0x1A): 静默丢弃
- 断电: 无效(InfoROM 是非易失的)

### 发现 3: Linux nvflash 的 FSP 拦截
- Linux nvflash 使用 /dev/mem + mmap 直接访问 BAR0 → SPI 控制器
- Blackwell 上 FSP 是信任根,守着 SPI flash 控制器
- 直接 MMIO 访问触发总线级死锁 → 系统冻死(无内核日志)
- Windows nvflash 走 nvlddmkm 驱动接口,有 FSP 协商路径
- **nvflash 二进制中确认了 /dev/mem 和 mmap 的使用**

### 发现 4: 原版 vs XOC BIOS 的 CC 行为差异
- 原版 BIOS (98.02.2E.40.E0): 每次启动设置 0x590 CC 位(从 InfoROM 读 PRC state)
- XOC BIOS (98.02.2E.80.50): 不设 CC 位(其 InfoROM 干净,或该版本 BIOS 砍了此行为)
- **不确定是 "XOC BIOS 本来就不设 CC" 还是 "XOC 芯片的 InfoROM 恰好干净"**

## 系统稳定性教训
- 驱动初始化期间发 FSP 消息 → 系统死机(与 GSP-FSP 握手冲突)
- 无驱动状态发大量 ROMREAD → 网络显示挂(可能影响 PCIe)
- NVML 在无驱动状态调用 → 触发驱动加载 → 可能死机
- **安全窗口: 驱动完全加载并稳定后(30秒+),或完全无驱动且不触发自动加载**

## 恢复路径(按可行性排序)
1. **Windows + nvflash**: 走驱动接口,FSP 允许 → 刷干净原版 ROM 到槽位 B
2. **自定义 SPI 读内核模块**: 从 nvflash 反汇编找寄存器 → 只读操作 → 安全风险低于 nvflash
3. **物理编程器**: 直接读 SPI 芯片(水冷阻挡,需要拆卡)
4. **永久使用 XOC BIOS**: CC=0,一切正常,只是损失一个 BIOS 槽位

## 消费卡 CC 绕过链(早上的成果,后来被事故打断)
```
CPUID SEV=0 → os_cc_enabled=TRUE(驱动补丁)
  → gpuIsCCEnabledInHw 绕过(驱动补丁)
    → PRC 对象写入(CC 开关,MNOC 通道)
      → CC 模式触发(0x590=1)
        → spdmContextInit(手动调用,payloadBufferSize 修复)
          → libspdm 完全初始化(4056B ctx + 9204B scratch)
            → spdmDeviceInit 传输层注册
              → spdmStart → GSP 侧 SPDM Responder 无响应 ← 终点
```

## NVDM 消息类型完整攻击面地图
| 类型 | 行为 | 错误码 | 256B 载荷 | 溢出 |
|------|------|--------|-----------|------|
| 0x00-0x10 | 静默 | — | — | — |
| 0x11-0x14 | 受理 | 0x4b3 | 0x1e0 拒 | ❌ |
| 0x16 | 受理 | 0x153 | 受理 | ❌ |
| 0x17 INFOROM | 受理 | 0xC2(受限) | 受理 | ❌ |
| 0x1c | 受理 | 0x249 | 受理 | ❌ |
| 0x1d | 受理 | 0x2e5 | 通道污染 | ❌ |
| 0x20 | 受理+回数据 | 0(成功) | 通道错误态,自愈 | ❌ |
| 0x21 FSP_GSP_COMM | 受理 | 0 | — | — |
| 0x22-0x23 | 受理+ack | — | 静默 | ❌ |
| 0x24-0xff | 静默 | — | — | — |

## PRC 处理器设防确认
- knobId 越界: 干净拒绝 0x202(合法范围 0x02-0x2a)
- numBytes > 4: 干净拒绝 0x1e0
- 超长消息: 拒绝,通道 5 秒自愈
- 值字段: 16 位
- **结论: PRC 解析器设防完好,不是溢出入口**

## 待定案
- [ ] FSP 何时/为什么决定持久化 PRC 到 InfoROM(触发条件是什么)
- [ ] 原版 BIOS 芯片的 InfoROM 具体被写了什么(CC=on 之外还有别的吗)
- [ ] XOC BIOS 是"天生不设 CC"还是"InfoROM 恰好干净"(需要在干净的原版芯片上验证)
- [ ] Windows nvflash 是否真的能绕过 FSP 拦截
- [ ] SMBPBI(0x18)洪水 DoS 的精确触发参数(K3_DEEP 里的 E5 配方从未执行)

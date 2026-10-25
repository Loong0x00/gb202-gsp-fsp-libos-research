# 会话总结 — 2026-10-02 全天 (逻辑遗漏审计 + FSP通道彻底审计 + 重大发现)

## ★★★ 最重要的发现: FSP Runtime Dispatcher Permanent DoS

### 现象
```
单条 ROMREAD (NVDM type 0x1A) 消息 via MNOC port 0/1:
  → 端口瞬时 ERROR (bit 25 锁存)
  → FSP runtime dispatcher 永久死亡
  → 所有 NVDM 类型 (PRC/FWUP/CLOCK_BOOST/CAPS/INFOROM) 全部无响应
  → EMEM runtime 也无响应
  → CMS2 窗口全空 (FSP 日志系统也死了)
```

### 持久性 (全部尝试过的恢复方法)
```
❌ 完全断电 (拔电源线30秒再插回)
❌ BIOS 切换 (XOC ↔ 原版, 两颗独立SPI芯片都试了)
❌ SBR (Secondary Bus Reset)
❌ 驱动卸载/重载 (宿主 + VM)
❌ VM 重启 (多次)
❌ FLR / D3hot / runtime-PM
```

### 不受影响的功能
```
✅ GPU 基本功能 (nvidia-smi 正常)
✅ GSP boot (驱动正常加载)
✅ CUDA (推测, 未测试但 GSP 活着应该没问题)
✅ FSP boot dispatcher (还能 boot GSP)
✅ 显示输出
```

### 安全评估
```
严重性: High (永久 DoS, 不可恢复)
触发条件: 单条消息 (零成本)
攻击面: MNOC port 0/1 (宿主可访问)
影响范围: FSP 管理的全部 runtime 服务
  - PRC (功耗管理, 47个knob)
  - FWUP (固件更新)
  - CLOCK_BOOST
  - CAPS_QUERY
  - INFOROM
可能是: 有意的 fail-secure 设计 (安全敏感操作触发永久锁定)
也可能是: FSP 固件 bug (dispatcher crash 后无恢复路径)
无论哪种, 从安全研究角度都是有价值的发现
```

---

## 时间线 (2026-10-02 全天)

### 第一阶段: 逻辑遗漏审计 (上午)
读了全部 ~40 份安全相关文档, 发现 9 个逻辑遗漏:

| # | 遗漏 | 严重性 | 状态 |
|---|------|--------|------|
| 1 | EMEM 只在 boot 阶段工作 | ★★★ | 已证实 (但比想象更复杂) |
| 2 | 0x8f4000-0x8f7fff 从未跟进 | ★★ | 已测 (原版BIOS上有数据, XOC上死区, 不可写) |
| 3 | PRC byte8 子命令空间未扫描 | ★★ | 未完成 (FSP死了) |
| 4 | EMEM 通道 1-3 未探索 | ★ | 未测 |
| 5 | CMS2 窗口未用作监测器 | ★ | 已用 (现在是空的!) |
| 6 | 48字节高熵块未追 | ★ | 未测 |
| 7 | EMEM"消费"可能是假的 | ★ | 已证实 (QH写重置QT) |
| 8 | 双BIOS芯片FSP行为差异 | ★ | 已测 (原版runtime死, XOC今天也死了) |
| 9 | 无驱动时FSP确切phase | ★ | 已测 (boot complete但MNOC不响应) |

### 第二阶段: GSP 权限探索 (下午)
```
✅ GSP 完整内存权限图:
  代码段: R-X (WPR硬件保护, page fault 0xF)
  数据段: RW
  堆/staging: RW + XN (不可执行)
  栈: RW + XN
  → 完整的 W^X, 没有 RWX 区域
  → 不能在 GSP 上执行任意代码

✅ FSP Falcon IMEM/DMEM:
  从宿主: 0xbadf* 死区
  从 GSP: 0xbadf* 死区 (泄漏读证实)
  → FSP 内存在硬件层面完全隔离

✅ GSP 固件无 MNOC 静态地址引用
  → 硬件寄存器通过 HAL 对象间接访问

✅ 完整 GSP 固件 ELF 发现 (84MB, 数据段在偏移 0x19f040)

✅ 关键地址修正: 0x41B17678 → 0x04191678 (ELF数据段内)

✅ 泄漏读原语验证:
  通道表(0x04191678) = 0x0FE4790E10 (staging元数据)
  mctpSubmit入口全局(0x0418FF68) = 0x77f2058f82306a67 (哈希值)
```

### 第三阶段: V3 注册表键静态分析 (下午)
```
14 个 Tier-1 安全键的消费点全部定位:
  RmDisableFsp, RmDisableCotCmd, RmSpdmEnableFuzz,
  RmDisableDHKeyExchange, RmAllowPrivSecDisabled, ...
统一模式: registry_read(ctx, name, &v) → if(v==1) 跳过检查
零守卫: 无熔丝检查/无调试模式门
注入障碍: /proc 写入是 Binary 类型, GSP 按 DWORD 读不到
```

### 第四阶段: FSP 通道全面测试 (傍晚 → 灾难)
```
XOC BIOS · 第一次重启后:
  ✅ PRC via MNOC p1 → 响应! (第一次也是最后一次)
  ✅ FWUP cmd6 via MNOC p1 → 响应!
  ❌ ROMREAD via p1 → ERROR (端口锁)
  ❌ ROMREAD via p0 → ERROR (端口锁)
  ← 这两条 ROMREAD 杀死了 FSP runtime dispatcher

之后所有测试 (多次重启 + BIOS切换 + 完全断电):
  ❌ 所有类型 × 所有端口 × 所有通道 → 超时
  ← FSP runtime 永久死亡

原版 BIOS 测试:
  ✅ 驱动能 boot (FSP boot dispatcher 活着)
  ❌ 所有 runtime 消息 → 死 (9/28 WPR2事故的旧伤 + 可能叠加了新伤)
  ❌ 0x8f4000 有数据但不可写
```

---

## MODS 通信路径确认
```
MODS 使用 MNOC port 1 (宿主道) — 与我们完全相同
无魔法, 无 GSP 路径, 就是用户态工具 + 正确的 PRC 子命令
MODS 的 task2/subobject1 能降 PLM (0x8200d0/0x8200dc)
但 MODS 也发不了 COT/ROMREAD (同样的类型过滤)
```

---

## HULK 授权机制澄清
```
HULK 证书是刷进 EEPROM 的 (nvflash --wrhlk), 不是运行时发的
需要 NVIDIA 签名 + 设备绑定 (device_id)
MODS 样例证书没有 5090 (0x2b85) 的
对这条路基本封死 (除非搞到合法签名证书)
Enthusiast.key 也是类似流程 (nvflash --installkey)
```

---

## PRC 消息格式 (字节序教训)
```
正确的第三 dword 格式 (从 9/26 日志逆向):
  (knob_id << 16) | (flags << 8) | subcmd
  
  例如 knob 0x1D read: 0x001D020C
    subcmd = 0x0C (bits 7:0)
    flags  = 0x02 (bits 15:8)  ← numBytes=2
    knob   = 0x1D (bits 31:16)

我搞错的格式 (浪费了好几次重启):
  0x00000C02 — 字节序完全反了
  0x000C0200 — 这是一种变体(之前某次成功过,可能碰巧)
  
教训: 从日志的 raw_bytes 逆向, 不要从文档的公式正向推
```

---

## 今天的实验统计
```
宿主机完全断电重启: 2次
普通重启: 4次
BIOS 切换: 2次 (XOC→原版→XOC)
VM 周期: ~8次
SBR: 1次
MNOC 端口锁死: ~6次 (每次都要断电恢复)
模块编译: ~4次
文档产出: 5个主要 .md 文件
```

---

## 当前状态
```
GPU: 工作正常 (nvidia-smi OK, 游戏可用)
FSP: boot 正常, runtime 永久死亡
  PRC/FWUP/CLOCK_BOOST/CAPS/INFOROM: 全部不可用
  EMEM: 不响应
  MNOC: 不响应 (端口不锁但无回音)
  CMS2: 空
GSP: 正常 (K3-1 注入仍可用)
编程器: 用户已购买, 待到货
```

---

## 下一步建议
```
1. 物理编程器 (CH341A) — 读 SPI flash
   → InfoROM 取证 (看 FSP 写了什么状态)
   → flash 结构分析
   → 这是唯一不受 FSP runtime 死亡影响的路径

2. FSP DoS 漏洞报告 — 这本身就是一个安全发现
   → 单条消息永久杀死 FSP 全部 runtime 服务
   → 无论是有意设计还是 bug, 都值得报告

3. GSP 侧继续 (K3-1)
   → GSP 不受 FSP runtime 死亡影响
   → 假对象树 / tdispmgr 蹦床仍然可行
   → 但没有 FSP 响应, "以 GSP 身份发消息给 FSP" 的价值降低了

4. 等新卡 / RMA
   → 如果需要 FSP runtime 功能 (固件更新等), 这张卡已经不行了
```

---

## 关键文件索引 (今日新增)
```
LOGICAL_GAPS_AUDIT_20261002.md — 9个逻辑遗漏的详细分析
FSP_CHANNEL_AUDIT_20261002.md — MNOC/EMEM/FSP寄存器完整审计
FULL_REREAD_FINDINGS_20261002.md — 全量文档重读, 未探索线索
V3_KEY_STATIC_ANALYSIS_20261002.md — 注册表键消费点分析
SESSION_SUMMARY_20261002.md — 上午会话总结
本文档 — 全天最终总结
/tmp/gsp_610_full.bin — 完整84MB固件(含数据段)
```

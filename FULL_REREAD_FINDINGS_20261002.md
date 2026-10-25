# 全量研究重读 — 未探索线索 + 可能错误结论 (2026-10-02)

读了 rt_5090_project 全部 ~40 份安全相关文档后的系统性整理。

---

## 一、便宜且未做过的（现在就能搞,不需要 GPU）

### 1. FWUP 会话门分析 [标价"零门槛"却从未做过]
```
来源: VULN_INVENTORY.md T4
事实: FWUP cmd1-7 裸发全返回 0x188(会话门控)
     FWUP cmd6(状态查询)能通 → 通道本身是活的
     nvflash_5877_text_disasm.asm 有全量反汇编
任务: 在反汇编里搜 FWUP 命令 1-5 的构造函数
     看 nvflash 发命令前设置了什么(会话token? 前置命令序列?)
价值: 搞定 = flash 写权限 = FSP 固件修改 = 代码执行
```

### 2. 55MB ucodes 条目表分析 [纯分析,无GPU需求]
```
来源: UCODES_ANALYSIS.md
事实: ucodes_ga10x.bin 55.5MB, 1293 个条目
     0-20MB 有低熵区域(5.7-7.8, 可能是明文代码!)
     20-48MB 纯加密(熵8.0)
     TOCTOU 窗口已证明存在(100ms 命中)
任务: 分析 1293 个条目哪些指向低熵(明文)区域
     如果有条目指向可执行明文 → 直接改内容 = TOCTOU 注入
     不需要绕签名(ucodes 无签名验证!)
价值: 绕过所有信任链直接注入代码到安全处理器
```

### 3. V3 注册表键效果测试 [75 个安全键,零个测过]
```
来源: REGISTRY_INJECTION_SURFACE.md + VULN_INVENTORY.md V3
事实: fn73 转发宿主注册表全部键值到 GSP
     75 个安全相关键已识别:
       RmDisableDHKeyExchange(禁密钥交换)
       RmSpdmEnableFuzz(SPDM模糊模式)
       RmSkipSkylineChecker(跳内存完整性检查)
       RmDisableCotCmd(禁信任链命令)
       RmAllowPrivSecDisabled(允许特权安全禁用)
       RmDisableFsp / RmDisableSec2(禁安全引擎)
     全部无生产态守卫(无熔丝/调试模式检查)
     基础设施完备(fn73 解析器 + K3-1 溢出)
障碍: /proc 写入全是 Binary 类型 → GSP 按 DWORD 读不到
     需要找到正确的 dword 注入姿势
价值: 一个键 = 一个安全特性被禁用
```

---

## 二、中等成本高潜力的

### 4. K3-1 Shot 0: 翻 RmFspUseMnoc 标志 [一步到位]
```
来源: PRIMITIVE_CROSS_ANALYSIS.md 组合1
事实: K3-1 写原语已在 GSP 里运行(以 GSP 身份)
     RmFspUseMnoc 标志在 GSP 的 ctx+0x1df
     翻转后 GSP 切到 MNOC 车道
     所有 GSP→FSP 流量走信任端口(port 0)
成本: 一个字节翻转(用现有写 gadget)
价值: GSP 身份的 FSP 通信 = 绕过所有宿主限制
注意: 需要确认 GSP 侧的 RmFspUseMnoc 位置(跟内核驱动的注册表键不同)
```

### 5. 热切换 GSP 代码 [理论可行,差几步验证]
```
来源: HOT_SWAP_GSP_ANALYSIS.md
事实: K3-1 写原语以 GSP 身份运行
     GSP 代码区在 WPR 保护窗内(防"外部"写)
     但 GSP 自己写自己的代码段 = 从未测试!
     staging 有 192KB 受控空间(可以放 RISC-V payload)
需要: ① 目标函数运行时地址
     ② staging 持久性(payload 做完后自我复制到安全区域)
     ③ I-Cache 一致性(选不常调用的函数)
价值: 持久 GSP 代码执行 = 完全控制
```

### 6. V1 崩溃机理深化 [理解了 = 可能变成可控注入]
```
来源: VULN_INVENTORY.md V1 缺口①②③
事实: fn73 numEntries 谎报 → 解析器越过包尾继续"解析"
     +1/+2 存活, +3/+5/+4094 崩溃(Xid 120 @ 0x1b8ffbc)
     零偏移条目被当作垃圾键消化
不知道: ① 崩溃前到底读了什么(链路)
       ② 幽灵条目是否被"成功注入"注册表(语义污染)
       ③ 如果可控 = 注入驱动永远不会发的键
```

---

## 三、可能错了的旧结论

### A. "EMEM 写通道挂死" — 可能是 nvflash 特有问题
```
旧结论: EMEM 写路径挂死(与 nvflash 同命运)
新证据: 我们最近的测试 EMEM 写完全不挂!
     只是消息被消费后无响应
     写QH=0会重置QT=0(硬件副作用,不是FSP读的)
含义: EMEM 通道本身可能是活的
     "挂死"可能是 nvflash 用了错误的寄存器序列
     09-28 审计通过某通道得到了各种 NVDM 类型的响应
     (那个通道可能就是 EMEM,当时协议理解不对)
```

### B. "FSP InfoROM 持久化" — 已被 SBR 发现降级
```
旧结论: FSP 往 InfoROM flash 写持久化状态(断电不清)
修正: SBR_RECOVERY_DISCOVERY.md 明确降级:
     "可能不是 flash 写,而是冷启动不清、SBR 才清的 volatile/secure 区域"
     SBR 后 InfoROM 版本正常读出 → flash 完好
含义: "断电不掉"的持久化可能是寄存器/内部SRAM级别的
     不是真正的 flash 写
```

### C. "Port 0 有硬件来源验证" — 不完全准确
```
旧结论: MNOC port 0 有硬件级来源验证,宿主写被拒
新证据: B7b 实验显示 port 0 ACCEPTS 写入(credit 被消耗!)
     只是不响应(消息没被 FSP 处理器处理)
     区别: 硬件端口是活的,是 FSP 固件层在过滤
含义: 如果是固件层过滤(而非硬件),那 GSP 侧的写应该被处理
     这就是 K3-1 → port 0 路线的理论基础
```

### D. "COT Oracle 死路" — 只对 runtime 成立
```
B4 结论: 所有地址→相同错误0xD7 → "不可行"
但: 这只在 runtime 成立!
   limbo 状态(CC mode)确实给出了不同地址→不同错误码
   (0xDEAD0000→0xffff7044, 0x944480000→0x62340000)
含义: limbo 里的 COT oracle 是活的
     但 limbo 状态有 brick 风险
```

### E. TOCTOU 时序数据有内部矛盾
```
LOGICAL_INCONSISTENCIES_DEEP_ANALYSIS.md 矛盾#1:
  race_v3: 400ms写入→GPU正常 → "窗口=200-600ms"
  最新: 50ms→已太晚, 10-45ms→被检测
  如果50ms就完成,为什么race_v3说窗口是200-600ms?
未测: 在400ms时刻写FMC代码入口(0xF200)而非0x10000
     区分"处理已完成"和"写到死代码"
```

---

## 四、被遗忘但有价值的观察

### F. SEC2 MAILBOX0 = 0xe99b3000
```
来源: B4_B5_B7_RESULTS.md B5
SEC2(第二安全处理器)在 GB202 上"不活跃"
但 MAILBOX0 = 0xe99b3000 是一个真实值(不是毒化)
可能是 SEC2 的内部代码/数据地址
从未分析过这个值
```

### G. `--set-next-sbr-to-fundamental-reset`
```
来源: SBR_RECOVERY_DISCOVERY.md
NVIDIA gpu-admin-tools 有这个选项
证明 SBR 和 fundamental reset 语义不同
对应一个可设置的寄存器位
从未找到这个寄存器位在哪
如果找到 → 控制 FSP 的重置深度 = 可能进入更深的安全模式
```

### H. PCIe ROM BAR 可读超 512KB 限制
```
来源: FINAL_STATUS_20260928.md C级发现#15
"PCIe ROM BAR 可读取超出 512KB 限制的数据(0x80000处有硬件数据)"
从未探索这个超限数据是什么
可能是 FSP 相关的硬件配置
```

---

## 五、综合优先级推荐

```
立即可做(纯分析):
  ① FWUP nvflash 反汇编搜索 [T4]
  ② ucodes 1293 条目低熵区分析
  ③ V3 注册表键注入姿势设计

近期实验(需要 VM 但不需要新工具):
  ④ K3-1 Shot 0(翻 RmFspUseMnoc)
  ⑤ V3 安全键逐个测试
  ⑥ EMEM 通道重新审计(用正确协议)

中期(需要新工具或更多分析):
  ⑦ 热切换 GSP 代码
  ⑧ V1 崩溃机理
  ⑨ TOCTOU 时序矛盾解决
```

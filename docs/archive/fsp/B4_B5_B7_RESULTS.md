# B4/B5/B7 实验结果 — 2026-09-29 05:15

## B4: COT gspFmcSysmemOffset Oracle

**结果: 不可行(FSP 运行时关闭 boot 级消息)**

```
所有地址(0x0 到 0xffffffffffff):
  → 完全相同响应: err=0xD7, time=~300-500μs
  
结论: FSP 在验证地址之前就拒绝了
原因: COT(0x14)只在 boot 阶段被接受
     运行时发送 → 0xD7 字段拒绝(不读 gspFmcSysmemOffset)
     
防御评估: ★★★★★ 
  FSP 有 boot/runtime 状态区分
  boot 消息(COT)在 runtime 被干净拒绝
  gspFmcSysmemOffset 不构成读 oracle
```

## B7a: MNOC SENDMBOX 流量嗅探

**结果: 空闲时无 FSP→GSP 流量**

```
10 秒嗅探 + 主动触发 PRC:
  port 0: TX=0x00000000 (无流量)
  port 1: TX=0x00000000 (无流量)
  port 2: TX=badf5720   (特权毒化,不是真实流量)
  port 3: TX=badf5720   (特权毒化)

TXD(端口数据寄存器)= 0x11111111 (可能是默认值)

结论: PRC 事务不触发 FSP→GSP 通知
     FSP↔GSP 通信只在 boot 阶段发生
     需要在 SBR/boot 期间嗅探才能看到流量
```

## B7b: MNOC Port 0 注入(以 GSP 身份)

**结果: 端口接受写入但不响应**

```
注入到 port 0 RECEIVEMBOX:
  消息: type 0x21 (FSP_GSP_COMM), 0x16 (CAPS_QUERY), 0x14 (COT)
  状态变化: RX 0x85000000 → 0x84000000 (CREDIT 消耗)
  响应: 无(TX 全零,MSGQ 无变化)

port 1 对照:
  同样接受写入,同样无响应(通过 MNOC)
  (port 1 通过 EMEM 协议正常响应)

结论: MNOC 端口写入被硬件接受
     但 FSP 的 MNOC 处理器不处理宿主注入的消息
     可能需要额外的硬件认证(真实的 GSP 发送方标识)
     
防御评估: ★★★★☆
  MNOC 有硬件级的来源验证
  不是简单的"谁写都行"的邮箱
```

## B5: SEC2 (PSEC) 第二攻击面

**结果: 通道死(消息不消费,MSGQ 卡死)**

```
SEC2 EMEM 通道(0x840ac0):
  发送后 QH 不动(QT=12, QH 永远 0)
  → 没有固件在消费消息
  MSGQ 卡在 MH=MT=16777280 (0x1000080)
  → 不是正常空闲状态(MH=MT=0)
  → 可能是 boot 时的残留或崩溃状态

SEC2 SCRATCH: 0xbadf5108 (毒化 — 同族保护)
SEC2 MAILBOX0: 0xe99b3000 (真实值! 可能是内部地址)

早期"响应"分析: 是 EMEM 缓冲里我们自己的消息回声
                不是 SEC2 的真实响应

结论: SEC2 在 GB202 上存在但不活跃
     Kernel RM 从不经此通道通信(源码确认)
     SEC2 固件可能:
       a) 没有运行(未加载或崩溃)
       b) 运行但 EMEM 服务端未启动
       c) 在某种锁定状态

MAILBOX0=0xe99b3000 可能值得进一步分析
```

## MNOC 端口归属(更新)

| Port | RX状态 | TX状态 | 归属 | 证据 |
|------|--------|--------|------|------|
| 0 | READY+CREDIT→接受写入 | 静默 | 疑似GSP | 接受写入但不响应 |
| 1 | READY+CREDIT→接受写入 | 静默 | 宿主 | EMEM协议正常工作 |
| 2 | CREDIT only | badf5720毒化 | CPU-RM | 特权拒绝 |
| 3 | CREDIT only | badf5720毒化 | 未知特权 | 特权拒绝 |

## 总结: 新增防御发现

1. **FSP 有 boot/runtime 状态机** — boot 消息运行时被拒
2. **MNOC 有来源验证** — 宿主写入 port 0 不被 FSP 处理
3. **SEC2 通道 GB202 上休眠** — EMEM 服务端未启动
4. **COT 任意读 oracle 不可行** — gspFmcSysmemOffset 运行时不被消费

## 下一步(按优先级)

1. **GSP RPC 全面 fuzzing** — 基础设施完整,F-1 证明有溢出
2. **Boot 期间 MNOC 嗅探** — SBR + 实时捕获 FSP↔GSP 交互
3. **SEC2 MAILBOX0 分析** — 0xe99b3000 可能是代码/数据地址
4. **F-1 升级到 ACE** — 控制 GPU_EXEC_REG_OPS 溢出的执行流

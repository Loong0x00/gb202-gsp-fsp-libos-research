# GSP-exec → FSP GSP-lane 探测器 —— 工程 Runbook(kickoff 2026-09-27)

## 目标
让被劫持的 GSP 以自己的身份向 FSP 发送受控 NVDM 消息(探测 GSP 车道特权服务集 0x21+),
不需要完整 ROP——用**假对象树**走 tdispmgr 包装器。

## 原语回顾(全部已证)
- **K3-1 元数据劫持**:staging 溢出 → msgqMetadata 腐化(P6 载荷证可持续、GSP 不崩)
- **rxrefresh 回调** @0x1004c9c:`call [*(meta+0xb8)](a0=meta+0x8c, a1=*(meta+0x38)【值,全控】, a2=4, a3=0, a4=*(meta+0xc0)【值,全控】)`
  - **每次 RPC 收包都触发** = 可循环调用
- staging 溢出区 = 64KB+ 受控数据(假对象树放这里)

## 路线:假对象树 + tdispmgr 包装器
关键洞察:回调的 a1 是完全受控值 ⇒ 指向 staging 里的假 pObj。
tdispmgr(0x18BBD60)只吃 a1 ⇒ 自动成为我们的 trampoline:

### 已钉死的解引用链(入口)
```
tdispmgr(a1 = fake_pObj):
  s4 = *(fake_pObj + 0x2288)          ← 假 session(指向另一个假对象)
  栈上建 req[0xA4]:全零 + u16 0x0414  ← 固定请求(第一枪内容不可控,先证明通道)
  mctpSubmit(a0=?, a1=session, a2=req, ...) @0x18bbde8
```

### 待钉死(下一会话的静态工作,~1-2h)
1. mctpSubmit(0x1B594D0) 入口对 a0/a1 的解引用(pObj/session 读哪些字段)
2. transport 分发(0x150c170)的方法槽链:ctx+0x158/+0x1c8/+0x1d0 各自怎么到达
3. 真后端(EMEM 0x15015c8 / MNOC 0x150a3b0)需要对象里的哪些字段:
   - PRI 窗口基址 W = 0x08200000(已知!K3 泄漏读实证)
   - 端口号/aperture 基址 0x8f1e00(已知)
4. 假对象树布局(staging 内,含真叶子值)
5. K/MAP 载荷(rpc_ovf_patch v11 机器,fn 门控选晚期 fn=76)

### 射击序列
- **Shot 1**:tdispmgr 固定请求(0x0414)经假 transport 从 GSP 车道发出
  → 观测:port 0 send_info / EMEM MSGQ / FSP 0x8f4000 活窗
  → 若 FSP 响应 ⇒ **GSP 身份通道打通**(第一目标)
- **Shot 2+**:内容受控——其它包装器(24 个调用者里找 msg 内容来自对象字段的)
  或 trampoline gadget(找 `mv a2,a4; jalr` 类 arg 重排;gadget 库薄,备选:直接写
  mctpSubmit 的全局请求缓冲 0x41906B0 一带的 BSS 目标区——写原语可循环!)
- 风险:每次 GSP 崩溃 = 驱动周期;WPR2 残留规律已明(脏关机→需重启)

## 备用路线(如果假对象树某层不可伪造)
- MarkConsumed 回调(a0=值全控!P4 未 fired——先补这枪定可达性)
  → a0 直接当 pObj/参数 → 组合空间更大
- ROP:pivot 0x1b70ad8(脏,含写 0x4 风险)+ epilogue 0x12a210c(库存薄,不优)
- 写原语循环改 GSP 全局配置(如 RmFspUseMnoc 的 GSP 位 ctx+0x1df → 让真 GSP 自己
  切到 MNOC 车道!然后正常 RPC 触发它的 FSP 流量)——**这个其实最便宜,优先级提到 Shot 0!**

## Shot 0(新增,最便宜):翻转 GSP 的 MNOC 标志
用循环写原语把 GSP 侧 `RmFspUseMnoc` 的 ctx+0x1df 置 1(静态已知该字节控制
EMEM→MNOC 方法切换)→ GSP 后续 FSP 流量自动走 MNOC 车道 → 配合宿主侧 RPC 触发
任何会发 FSP 消息的 GSP 路径(CC/SPDM 证书查询等)→ 全部流量走 GSP 端口!
前置:找到 ctx 对象运行时地址(从 0x1509338 初始化函数的全局回溯,或写原语扫描)。

## 资产清单(已就位)
- gsp61057_rx_full.bin + rvlib/disas/callgraph 工具链
- K3-1 全套:msgqMetadata 布局、回调调用点实参语义、gadget 库、P1-P6 载荷规格
- F-1 注入机器(f1_fire_patch.py 可改造为任意 fn 载荷注入)
- FSP 通道地图:port0 对话协议、错误码词典、ROMREAD 原语、0x8f4000 活窗
- 本文件 + GADGET_INVENTORY.md

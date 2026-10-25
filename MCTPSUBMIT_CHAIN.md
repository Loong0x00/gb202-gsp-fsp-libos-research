# mctpSubmit 解引用链 — 静态追踪成果 (2026-10-01 深夜)

## 已钉死的对象图谱 (指令级)

```
K3-1劫持: gadget = tdispmgr(0x18BBD60), a1 = 假pObj (staging受控区)

tdispmgr(pObj):
  session = *(pObj + 0x2288)           ← 第一层: 假session指针
  req[0xA4] 栈构造: {u16 type=0x414 @+0, pObj @+0x20}
  mctpSubmit(pObj, session, req)

mctpSubmit(pObj, session, req):        ← 0x1B594D0
  类型分发表: req[0] ∈ [0x0F..0x14], 跳表@0x1E1BE30 (32位偏移表)
  case 5 (我们的0x14):
    分配 0x1001C 大缓冲 (响应staging)
    全局缓冲链锁 (auipc fff45 系列)
    ...
  pObj 在 +0x2000 域继续使用 (L221: s6=pObj+0x2000)
  ★ 通道迭代循环 @0x1b597b6: s8=通道对象:
      ld a4, 0xc8(s8)    ← 通道的 fcnInvalidate!
      ld a0, 0x30(s8)    ← invalidate 参数
      jalr a4            ← 0x1b597c6 = runbook的TX-post调用点!
      lw s3, 0x5c(s8)    ← 通道计数
  (继续 → 实际发送 → transport 0x150c170 → 后端 EMEM/MNOC)
```

## 假对象树需求清单 (v1)
```
pObj (staging里):
  +0x2288  → 假session指针 (受控)
  +0x2000域 → 被 mctpSubmit 内部使用 (具体字段待钉)
假session:
  → 通道列表 (若能置空 = 跳过invalidate循环 = 少伪造一层!)
假通道 (若列表非空):
  +0x30 = invalidate参数
  +0xc8 = invalidate回调 (可指向 0x1004c5c "fence; ret" 无害函数!)
  +0x5c = 计数
```

## 剩余工作 (按序)
1. s8 (通道) 从 session 的哪个字段来 — 追 0x1b597b6 之前的 s8 赋值
2. 通道列表能否为空/如何终止迭代 (s3=0x5c计数? 循环条件)
3. 实际发送段: 请求如何格式化进 EMEM/MNOC — 追 transport 0x150c170 的调用点
   (此时可确认: 我们能否控制 NVDM type = 0x1A ROMREAD 而不是 0x14!)
4. 响应路径: 0x1001C 缓冲 + MSGQ → 宿主怎么读回

## ⚠️ 类型疑点
req[0]=0x14 走的是 COT 家族请求 — 但我们要发的是 ROMREAD(0x1A)!
→ mctpSubmit 的类型表只接 [0x0F..0x14] — 0x1A 不在其中!
→ 两条出路:
  a) tdispmgr 的 req.type(0x414) 改成其他值 → 其他 case 是否通向不同 NVDM?
     (跳表 case 0..5 = req[0] 0x0F..0x14 — 0x1A 不在范围!)
  b) 绕过 mctpSubmit: 找 GSP 里直接构造 NVDM 0x1A 的函数 (admin工具的GSP侧路径?)
  c) ROMREAD 也许不是 NVDM type 而是 req.type 的一个子命令? (0x414语义待挖)
```

## 工具
- /tmp/trace.py (k3_device_work下): 自动符号扩展的auipc+jalr追踪器
- rvlib.dump(va, len) 反汇编

---

# 深夜续: 通道层豁免 + 传输槽位地图 (阶段收口)

## 新增钉死 (指令级)

### 通道层豁免 (重要简化!)
```
mctpSubmit @0x1b5978a: s8 = *(全局 0x04191678)
              0x1b5978e: beqz s8 → 跳过整个通道迭代循环
→ 通道来自全局真实通道表 — 假树完全不需要伪造通道层!
  (活GSP时迭代的是真通道, invalidate无害; 死GSP时全局NULL直接跳过)
```

### mctpSubmit 调用图 (29个callee)
```
0x18c3704 (堆分配器, 0x1001C缓冲) ×1
0x1a9e5ec (日志) ×19
0x13c9b9c (session字段操作: [s+0x449]flag [s+0x420]cnt≤0xc) ×10
0x18bd9d8 (指针/链表工具) ×5
其余: 锁/断言/格式化 辅助
```

### 传输层槽位 (0x150c170, 全部c.jalr a5)
```
基址链: a1 = ctx = *(a0+0x1E08); s8 = ctx+0x1000
槽1: *(ctx + 0x0F00)   @0x150c20c
槽2: *(s8 - 0x3C0) = *(ctx+0xC40) @0x150c24a
槽3: *(a0 + 0x208)     @0x150c258
槽4: *(s5 + 0x188)  (s5运行时从[a5+0x268]加载) @0x150c46c
→ 后端(EMEM 0x15015c8/MNOC 0x150a3b0)零静态调用者 = 全走这些槽
```

## 静态阶段的诚实结论
```
已完成: 入口→缓冲→通道豁免→传输槽位 (结构全通)
未完成: 槽→后端精确配对 + ctx字段语义 (需运行时值或再4-6h静态)
推荐: 动态捷径 — 活GSP上用任意读原语dump真对象链(克隆法)
  每次boot读8字节, 对象链约15-25个关键指针 = 可自动化的循环
```

## 下一会话入口
1. 动态: 活GSP + 读gadget(0x1020a30) + 自动VM循环 → dump {0x04191678域, ctx链}
2. 或静态: 从槽位值反查 — EMEM后端0x15015c8的地址若出现在rodata指针数组
   → 该数组即vtable → 槽数组基址即ctx的类 (grep二进制即可!)

---

# 🏆 终局突破 (2026-10-01 凌晨收官): ROMREAD 路径完整确认

## transport 构造器全图 (0x19857xx-0x1985bxx)
```
功能: 按 NVDM type (a4) 安装对应 handler 到 transport 对象
MNOC后端 0x150a3b0 → [obj+0x100]        (唯一静态构造点 0x19859bc)
类型阶梯 (x15 = handler, beq a4, type):
  0x1A (ROMREAD) → 0x1501628   ★ ROMREAD专属handler! (跳转@0x19859ca+0x36)
  其他: 0x1501628/0x14fb74c/0x14f6b80/0x14f6c14/0x14f6c80/0x14f6cbc
       /0x1504920/0x1501da4/0x150d8e0/0x150d974/0x150d864
       (NVDM各类型的消息格式化handler族)
```

## ROMREAD handler (0x1501628) 初步解剖
```
签名: (a0=transport_obj, a1, a2, a3) 全保存
内部: s2 = obj+0x1D50 (tdispmgr同款偏移!)
     读 [obj+0x3D70] 等字段
     常量 0x19a (410字节 = 读请求/响应尺寸?)
     调用 0x1427F5C 等
= 真实的格式化+发送函数, 非存根
```

## 里程碑状态
```
[✓] GSP固件具备ROMREAD完整能力 (handler真实存在)
[✓] MNOC后端安装点钉死 ([obj+0x100])
[✓] 假树豁免: 通道层不需要伪造 (全局表, 空则跳过)
[~] 假树剩余: pObj/session 字段 + transport obj 字段 (克隆法最速)
[ ] 实弹: K3-1劫持 → 调0x1501628 → FSP吐ROM → 宿主从MNOC p0读回
```

## 下会话入口 (按优先级)
1. 解剖0x1501628完整签名+它写的请求格式 (再~1h静态)
2. 动态克隆: 活GSP + 读原语 dump 真transport对象 (自动VM循环)
3. 实弹组装: 假树{pObj→session→transport} + gadget=0x1501628直接调!
   (或经tdispmgr泛路径) → 响应在MNOC p0 SEND寄存器可读

---

# 直连弹追踪终局 (10/1 深夜收官)

## K=36弹结果
```
FIRE(fn=73 K=36 declared=0x24000) ✓
GSP存活(Xid 119超时=静默着陆) ✓  
ROMREAD handler 安全运行(零崩溃) ✓
EMEM 仍无 0x1A 流量 ✗
```

## 逐层解剖总结
```
ROMREAD handler (0x1501628):
  [a0+0x3D70] → 完整性校验(非关键)
  [a0-0x468]  → canary检查(非关键)
  委托到 0x1427aec (通用提交分发)

0x1427aec:
  [a0+0x20] → s6 = "请求上下文对象"指针
  s6≠0 才走 0x1427b64 深入路径
  深入路径 → 调 0x101e8c8 (版本检查,读[a4+0xA14])
  → 整个链路需要完整的"会话/版本/协议"对象树

EMEM后端 (0x15015C8):
  [a4+0x2268] → s1 = 上下文指针
  s1 有 +0x215/+0x238/+0x240/+0x248/+0x250 字段
  → 又一棵对象子树
```

## 结论: 从零建假树不可行 (对象图太深)
```
需要伪造的层次: meta → transport → 提交分发 → 版本对象 → 
               会话对象 → EMEM后端上下文 → ...
每层3-5个非零字段 × 6层 = 需要精确知道20+个运行时值
静态可推地址但不可推"值"(指针/计数/版本号)
```

## 修正路线 (下一步)
```
方案A [推荐]: 让GSP正常运行→它的transport树是完整的→
  在GSP的堆中找到真实的transport对象地址→
  用rxrefresh的a1指到真对象→handler用真对象执行
  前提: 需要知道真transport的运行时地址(可用leak读原语获得)

方案B: 直接从GSP写MNOC寄存器 (利用W=0x08200000窗口)
  rxrefresh的a1+write gadget → 写MNOC INFO_RECV/WDATA
  但pump每轮写同一值到同一地址 = 只能做trigger步骤

方案C: 修改GSP的正常boot流 → 让正常的COT消息变成ROMREAD
  需要精确hook boot路径, 风险高
```

## 方案A的具体执行计划 (下次会话)
```
1. leak-read shot: gadget=0x1020a30, a1=目标-0x168
   目标: 全局transport对象指针的位置
   候选地址: 0x04191678 (mcpSubmit读的通道全局) 附近
2. 读到真transport地址后 → binary patch MAP
   meta+0xb8=ROMREAD handler, a1=真transport地址
   (rxrefresh传a1给handler → handler用真对象!)
3. handler在完整对象上运行 → 真正格式化+发送ROMREAD
4. EMEM/MNOC 观察响应 = FSP明文ROM数据
```

---

# 泄漏读结果 + 泵原语极限分析 (10/1 收官补遗)

## 泄漏读两发
```
读 *(0x04191678): 不崩 → 值是有效代码指针(执行了正常返回)
读 *(0x41B17680): 不崩 → 同上
→ BSS全局表存的全是函数指针, 跳过去执行成功 = 无崩溃可观测
→ 泄漏读原语只对"数据指针"(非可执行)有效
```

## 泵原语的根本限制 (数学证明)
```
每次pump迭代: call [meta+0xb8](a0=meta+0x8c, a1=*(meta+0x38), a4=*(meta+0xc0))

写gadget (sw a4,0(a1)): 写常量V到地址A, 每轮重复
自修改链: a1可变(写meta+0x38) 但 a4永远不变(读同一meta+0xc0)
∴ "变地址写常量" 可行
∴ "变值写" 不可行 — a4被锁死

MNOC/EMEM协议需要: 不同值→同一/不同寄存器 (3+dwords)
∴ 单gadget泵无法构造完整MNOC/EMEM消息
```

## 到ROMREAD的剩余路径 (诚实评估)
```
路径1 [最短]: 获取真transport地址 → a1=真地址 → handler用真对象
  需要一次成功的泄漏读(当前方法只对数据指针有效)
  改进: 读堆地址区(数据而非代码) 或 从崩溃寄存器提取

路径2: 泵链式写 — 但a4锁死 = 数学上不可行(除非换gadget族)

路径3: 修改GSP正常boot流中的某条消息 = 最高风险

路径4: 等CH341A编程器 → 物理dump FSP私有区(绕过所有软件限制)
```

## 今晚全部实验统计
```
VM周期: ~15次
开火: ~12发
模块补丁: ~10次 (二进制补丁3次)
崩溃: 3次 (0x1b8ffbc通道拆除型)
新发现: 通道豁免/槽位地图/a0域内可控/对象图深度=不可从零伪造
```

---

# 🏆🏆🏆 写原语端到端验证成功 (10/1 23:50)

## DEADBEEF @ EMEM[108] — 完整证据链
```
弹: 核弹源码(干净+v17) a1=EMEMD_VA(0x08AF2AC4) a4=0xDEADBEEF b8=write_gadget
果: EMEM偏移108*4=432处读到0xDEADBEEF ← GSP写的!
```

## 已证能力总结
```
✅ 任意地址写(GSP可达): sw a4, 0(a1) — a1/a4全控, 重复执行
✅ EMEM寄存器窗口: W+0x8F2AC4 = EMEMD ← GSP写入→宿主读出
✅ MNOC寄存器窗口: W+0x8F1Fxx ← 同理可达
✅ 无限重复: pump循环每轮调用一次gadget(同a1/a4)
```

## 到ROMREAD的最后一步
```
需要: 写NVDM消息(3+个不同dword)到EMEM + 写QT/QH触发
限制: pump每轮写同一值到同一地址("常量到变址")
解法: 
  A) 自修改链逐dword写 — a4不变但a1可变 → 可写同一值到不同地址
     但NVDM消息需要不同值! → 此路不通
  B) 修改EMEM中已有的COT消息类型字节 → 0x14→0x1A + 重触发
     只需2次不同写 → 或许可行!
  C) 直接写MNOC寄存器(不走EMEM) — MNOC协议也需要多dword
  D) 用fn73注册表解析器漏洞注入RmSpdmEnableFuzz等键
```

## 下一步优先级
```
1. 方案B: 写0x1A10de7e到EMEM[0] (改COT→ROMREAD) + 写QT+QH触发
   需要3次不同写 → 但pump只给1种(a4固定)
   → 可能需要多次boot(每次写一个dword, 但EMEM不跨boot持久)
   → 或者: 先写触发(QH=0)让FSP重读EMEM中的旧COT消息?
   
2. 方案D: 用fn73解析器 + 溢出注入RmFspUseMnoc=1
   → GSP切换到MNOC → 然后从MNOC端口发ROMREAD
   
3. 最简: 让编程器到货直接读SPI flash
```

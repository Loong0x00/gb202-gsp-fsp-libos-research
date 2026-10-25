# 原语交叉分析 — 组合攻击面

## 可用原语清单

```
A. K3-1 消息队列 staging 溢出
   → 64KB+ 受控写入 GSP 内存
   → msgqMetadata 腐化(可持续, GSP 不崩)
   → rxrefresh 回调劫持(每次 RPC 触发 = 循环)
   → 假对象树(64KB 空间随便放)
   → 函数指针 + 参数全控

B. F-1 GPU_EXEC_REG_OPS VLA
   → count 无上界 → 栈分配 count×32
   → 向下溢出(不覆盖返回地址)
   → 拷贝源 = 消息 + staging 残留
   → 单发(触发后 crash)

C. 55MB ucodes TOCTOU
   → sendAndRead 后窗口(~50-150ms)
   → 无签名验证
   → GSP 解析我们修改的容器
   → 可造成 GSP crash(有具体 PC)

D. CC-mode limbo(原版 BIOS)
   → COT 读 oracle(不同地址→不同错误码)
   → 风险: 触发深度锁死(已付出代价)

E. MNOC port 0(GSP 的端口)
   → 硬件接受宿主写入
   → FSP 不处理宿主注入的消息
   → 但如果 GSP 自己用 → FSP 信任

F. PRC knob 读写(MNOC port 1)
   → 宿主直接读写 FSP knob
   → 运行时可用
```

## 交叉组合分析

### ★★★ 组合 1: K3-1 + MNOC port 0 (最直接)

```
K3-1 给我们 GSP 代码执行(回调劫持)
  → 从 GSP 内部发 MNOC port 0 消息
  → FSP 信任 GSP 端口的消息(比 port 1 高权限)
  → 访问 GSP-only 服务(0x21 FSP_GSP_COMM 等)
  → 甚至读 FSP 内部状态

具体路径(Runbook 的 Shot 0):
  K3-1 写原语 → 翻转 RmFspUseMnoc 标志(ctx+0x1df)
  → GSP 自动切到 MNOC 车道
  → 正常 RPC 触发 GSP→FSP 通信
  → 全部流量走 GSP 信任端口

成本: 最便宜(一个字节翻转)
价值: GSP 身份的 FSP 通信
```

### ★★★ 组合 2: K3-1 循环 + F-1 staging 联合

```
F-1 的拷贝源 = 消息 + staging 残留
K3-1 的溢出目标 = staging 区域

联合:
  1. K3-1 先溢出, 在 staging 放精确数据
  2. F-1 触发, 从 staging 读到 K3-1 放的数据
  3. F-1 把这些数据写到栈上(VLA)

这实际上是 F-1 分析中已经提到的:
  "配合 staging 铺垫可稳定触发"
  K3-1 = 铺垫工具, F-1 = 触发器

但 F-1 写的是 VLA 内部(向下), 不经过返回地址
→ 单独不能控制 PC
→ 但如果 VLA 恰好覆盖了别的线程栈或数据结构...
```

### ★★ 组合 3: 55MB TOCTOU + K3-1

```
TOCTOU 修改 ucodes 容器 → GSP 解析我们的数据
K3-1 假对象树 → GSP 执行我们的回调

联合:
  1. TOCTOU 在 ucodes 里注入额外的数据结构
  2. K3-1 的假对象树引用这些结构
  3. 或者: TOCTOU 修改 GSP 的启动配置

价值: TOCTOU 可以在 GSP 启动前就改变行为
      K3-1 在运行时劫持执行
      时间维度上互补(boot 时 vs 运行时)
```

### ★★ 组合 4: K3-1 → 读 FSP 代码(终极目标)

```
K3-1 给我们 GSP 代码执行
  → GSP 有 GPU 内部总线访问权
  → 尝试读 FSP 的 EMEM/SRAM
  → dump FSP 解密后的代码
  → 静态分析 FSP

这是所有路径的汇聚点:
  无论走 K3-1 还是 TOCTOU 还是别的
  最终目标都是: 在 GPU 内部获得足够权限来读 FSP
  K3-1 是目前最成熟的路径
```

### ★ 组合 5: F-1 栈溢出 + K3-1 回调(backup)

```
如果 K3-1 的假对象树某层不可伪造:
  用 F-1 的栈溢出在栈上放 ROP chain
  → 但 F-1 不覆盖返回地址(向下溢出)
  → 除非: K3-1 先修改栈布局(通过其他写原语)
  → 极其复杂, 不推荐
```

### ★ 组合 6: CC-limbo + K3-1

```
CC-limbo 给我们 FSP 的 COT 读 oracle
K3-1 给我们 GSP 代码执行

联合:
  1. 在 limbo 中用 COT oracle 探测 FSP 内存布局
  2. 获得信息后, 用 K3-1 从 GSP 侧精确攻击
  → 信息收集(oracle) + 执行(K3-1) 分工

风险: limbo 状态不稳定(已导致 brick 一次)
建议: 不再使用
```

## 推荐路径

```
优先级 1: K3-1 → Shot 0(翻 MNOC 标志)
         最便宜, 一步到位, GSP→FSP 通信
         
优先级 2: K3-1 → 假对象树 → tdispmgr trampoline
         如果 Shot 0 不够, 走完整链
         
优先级 3: K3-1 → 从 GSP 读 FSP 内存
         最终目标: dump FSP 代码
         
备选:    55MB TOCTOU 作为 K3-1 的补充
         (boot 时修改 + 运行时劫持 = 双重控制)
```

## 关键洞察

```
K3-1 是所有原语中最强的:
  - 唯一有"循环"能力的(每次 RPC 都触发)
  - 唯一证明"可持续, GSP 不崩"的
  - 唯一有函数指针 + 参数全控的
  - 已经有完整的假对象树设计

其他原语都是单发或有限使用
K3-1 是真正的代码执行框架

最佳组合不是"多个漏洞串联"
而是"K3-1 打天下, 其他原语辅助"
```

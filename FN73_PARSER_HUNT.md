# fn73 解析器静态追踪 — 进度与交接 (2026-10-01)

## 已钉死的链路 (指令级)

```
RPC 收包 → pump(0x1016232) → 校验 → RPC循环(0x1b8feec)
  → lookup(0x101dcb4) → channel对象
  → 分发(0x142A1EC) → 核心(0x1bca024) → 会话层(0x1b61840)
  → RPC函数号分发表 (两张候选, 内容重复=两个接口实例):
      0x1c3b858 / 0x1c3bd00  (112项)
  → fn73 的 thunk: 0x19f0db0 (另一副本 0x18cc1c0)
      thunk: ld a5, 0x18(a0)    ← a0+0x18 = 分发器子对象
             ld a5, 0x88(a5)    ← 子对象vtable+0x88 = 真·fn73 handler
             尾跳 a5
```

## 下一步 (谁接谁做)

1. **找 vtable**: thunk 读 [对象+0x88]。对象在运行时分配,但其 vtable
   是静态 rodata。构造代码里必有 "存vtable常量到[对象+0]" 的模式。
   - 已知槽位偏移 0x88 → 在 rodata 找函数指针数组,
     其 +0x88 处的函数应具有"表走查"特征 (lw +4 计数, 0x10 步长循环)
2. **或反过来**: 对 0x19f0db0 的两条已知副本表 (0x1c3b858系 / 0x18cc1c0系)
   dump 全部112个thunk, 提取每个的 (对象偏移, vtable槽位) 对
   → 两个相邻fn的槽位模式会暴露对象布局
3. **或运行时**: GSP 代码执行(已有!)后读 0x19f0db0 引用的对象链
   — 一次任意读就能拿到vtable指针 (最便宜!)

## 已排除的静态路线 (别重走)
- RPC函数名字符串: GSP固件里没有 (超时消息是宿主打的)
- 注册表日志字符串: 没有
- lbu@4+stride16 模式扫描: 3候选全非
- auipc+jalr 直接调 0x1509338: 无 (走vtable)

## 工具就绪
- rvlib 反汇编: k3_device_work/rvlib.py (dump(va, len))
- auipc 符号扩展坑: imm≥0x80000 时是负数! (已坑3次)
- 调用对解析: callgraph.py / calls.py

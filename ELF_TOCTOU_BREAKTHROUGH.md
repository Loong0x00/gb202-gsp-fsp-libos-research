# 🔥 GSP ELF TOCTOU 窗口确认 — 2026-09-29 14:10

## 核心发现 (B+ 级)

**GSP ELF (27MB) 的 sysmem 加载窗口存在,100ms 延迟即可命中。**

```
实验:
  1. 驱动正常 boot (XOC BIOS, CC=0, 无 limbo)
  2. sendAndRead 返回后等 100ms
  3. 写入 ELF 起始 4 字节: 0x4355564e → 0x00000000
  4. GPU 挂死 — GSP 无法启动

结论: FMC 在 sendAndRead 返回后仍在从 sysmem 读取 ELF
      写入破坏了 ELF 格式 → GSP 解析失败 → 确认读取!
```

## 为什么之前所有 TOCTOU 都失败

```
之前: 写 FMC (290KB) → FSP 全阶段检测 → "没有窗口" (错误结论!)
现在: 写 ELF (27MB)  → 窗口存在 → 之前的结论只适用于 FMC!

时间线修正:
  sendAndRead 返回 (~50ms): FMC 已验证+加载完成
  100ms: ELF 还在被 FMC 读取 ← ★ 窗口在这里!
  ???ms: ELF 加载完成, sysmem 死亡

27MB / PCIe 带宽 ≈ 数百毫秒的读取窗口
```

## 技术细节

```
ELF 起始 magic: 0x4355564e = "NVUC" (NVIDIA UCode 格式)
  不是标准 ELF magic (0x7F 'E' 'L' 'F')
  是 radix3 容器格式

sysmem 中的布局:
  [radix tree pages][NVUC container (27MB firmware data)]

kernel VA 保存方法:
  在 kgspCreateRadix3_IMPL 中, memdescUnmap 之前保存 pRadix3Buf + dataOffset
  跳过 unmap 保持映射活着
```

## 下一步

1. **可开关的补丁** — arm/disarm 机制(不每次 boot 都破坏)
2. **扫描延迟边界** — 100ms 命中了,试 200/400/600ms 找窗口末端
3. **ELF 格式分析** — NVUC 容器里的实际代码位置
4. **注入 shellcode** — 不破坏 magic,修改代码字节
5. **如果 GSP 执行了我们的代码 → 任意代码执行!**

## 攻击链

```
宿主内核(或有内核权限的攻击者)
  → 补丁驱动(或直接内核模块)
  → 在 GSP firmware 加载窗口写入 sysmem
  → GSP 执行修改后的固件
  → ★ GPU 任意代码执行 (GSP RM 级别)
```

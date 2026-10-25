# ucodes_ga10x.bin 分析结果 — 2026-09-29 14:45

## 文件结构

```
ucodes_ga10x.bin (55.5MB)
├── 0x0000: NVUC 容器头 ("NVUC"+"ODES"+version+count=1293)
├── 0x05B8: 条目表开始 (每个条目 24 字节)
│   ├── Entry: type=4, offset=0x7a00, size=0x22f00
│   ├── Entry: type=4, offset=0x1ce00, size=0x23500
│   └── ... (1293 个条目)
├── 0-20MB: 混合熵 (5.7-7.8) — 结构化数据/压缩数据
│   └── 低熵区域: 可能是代码或配置
├── 20-48MB: 纯加密 (熵 8.0) — 安全处理器固件
└── 48-55MB: 混合 (7.6-8.0)
```

## TOCTOU 窗口确认

```
55MB ucodes 在 sendAndRead 返回后仍在从 sysmem 加载
100ms 延迟写入 → GPU 挂死 → 窗口存在!

27MB firmware 在 100ms 时已加载完(EBREAK 无效果)
→ 27MB 的加载窗口 < 100ms (可能在 50-100ms 之间)
```

## 加载时间线(修正)

```
sendAndRead 内 (~50ms):
  FMC 验证 + 加载到 I-Cache

sendAndRead 返回后:
  ~50-??ms:  27MB ELF 从 sysmem 加载到 GSP 指令存储
  ~??-???ms: 55MB ucodes 从 sysmem 加载

我们的写入窗口:
  100ms: ELF 已加载完, ucodes 还在加载 ← 命中!
  ??ms:  ELF 加载中 ← 未测试(需要更短延迟)
```

## 下一步

### 1. 缩短 ELF 写入延迟 (0ms, 25ms, 50ms, 75ms)
```
当前: 100ms → 无效果 (太晚)
目标: 找到 ELF 加载中的时刻
方法: 在 sendAndRead 返回后立即写(0ms)
     然后逐步增加延迟找到边界
```

### 2. 分析 ucodes 条目表中的明文代码
```
1293 个条目, 每个指向不同 offset/size
检查哪些条目指向低熵(明文)区域
如果有明文可执行代码 → 直接 TOCTOU 注入!
```

### 3. 修改 ucodes 条目表
```
TOCTOU 不改数据, 改条目表:
  - 修改 offset/size 造成越界
  - 重定向到恶意数据
  - 可能触发解析 bug
```

# COT Payload 注入 — 初步实验结果

日期: 2026-09-28 深夜

## 核心发现

**FSP 处理宿主发送的 COT payload 并根据内容产生不同响应。**

## 实验结果

| gspFmcSysmemOffset | FSP 响应 | 解读 |
|---------------------|----------|------|
| 0xDEAD0000 (首次) | 0xffff7044 (1 word) | DMA 失败或地址无效 |
| 0x944480000 (真实固件地址) | 0x62340000 (1 word) | 读到数据,hash/签名不匹配 |
| 0x0 / 0x1000 / 0x100000000 | 超时 | 通道未建立或驱动干扰 |

## 关键洞察

1. **FSP 在 boot 窗口期(GSP 未启动时)接受 COT**
2. **不同地址产生不同错误码** — FSP 真的在从指定地址 DMA 读取
3. **通道在 COT 处理后关闭** — FSP 进入 boot 状态,不再处理新消息
4. **每次测试需要完整 SBR 循环** — 卸载驱动 → SBR → 发 COT → 收响应

## COT 结构 (860 bytes)

```c
NVDM_PAYLOAD_COT {
    u16 version = 2
    u16 size = 0x35c
    u64 gspFmcSysmemOffset  ← 攻击点:FSP 从这里读固件
    u64 frtsSysmemOffset
    u32 frtsSysmemSize
    u64 frtsVidmemOffset
    u32 frtsVidmemSize
    u32 hash384[12]          ← SHA-384 固件哈希
    u32 publicKey[96]        ← 384B 验证公钥
    u32 signature[96]        ← 384B 签名
    u64 gspBootArgsSysmemOffset
}
```

## 待解决问题

1. **DMA 可访问内存**: /dev/mem 被 strict_devmem 限制,BAR1 在无驱动时不可写
   - 解决: 修复内核模块(__get_free_pages),或用 hugepage,或驱动加载时预写
2. **错误码解析**: 0xffff7044 和 0x62340000 的具体含义
   - 0xffff7044 可能是 "DMA read failure"
   - 0x62340000 可能是 "hash mismatch" 或 "signature verification failed"
3. **验证顺序**: hash 先还是 signature 先?
   - 如果只验 hash 不验 signature → 换固件 = ACE
   - 如果都验 → 需要绕过签名

## 下一步(明天)

1. 修复 DMA 内存分配(内核模块或 hugepage)
2. 在受控内存放已知数据 + 正确 SHA-384 hash
3. 观察 FSP 响应:
   - 正确 hash + 垃圾 signature → 看 signature 是否单独检查
   - 如果不检查 → 放 Falcon shellcode = **完整 ACE**
4. 如果 signature 被检查 → 研究签名验证算法 → 找实现 bug

## 工具

- COT 注入需要: 卸载驱动 → SBR → 通过 EMEM 发 NVDM 0x14 + 860B payload
- 响应是 1 word 的裸错误码(非标准 5-word 响应格式)

# COT 注入实验 — 重大安全发现

日期: 2026-09-28/29 (深夜马拉松)

## ★★ A 级发现: FSP COT hash384 字段不验证

### 实验证明

```
实验 1: hash=全0xFF (垃圾) + 原始固件 + 原始签名
  → GPU 正常启动! GSP 正常运行!
  → FSP 不检查 COT 中的 hash384 字段

实验 2: hash=全0xFF + 修改固件(1字节) + 原始签名  
  → GPU 启动失败, FSP 超时
  → FSP 通过签名验证固件内容(不通过 hash 字段)
```

### 安全模型(实测确认)

```
COT Payload 字段     验证状态
─────────────────────────────
version              检查 ✓ (必须=2)
size                 检查 ✓ (必须=0x35c)  
gspFmcSysmemOffset   使用 ✓ (从这里读固件)
hash384[12]         ★不验证!★ (可以为任意值)
publicKey[96]        可能验证(与根密钥比对)
signature[96]        验证 ✓ (对固件内容)
```

### 意义

1. hash384 字段是摆设 — 驱动可以填任何值
2. 真正的安全门是签名验证
3. 要实现 ACE 需要绕过签名(或找到签名验证的 bug)
4. 这是 NVIDIA FSP 信任链的一个已确认弱点

## 攻击链(完整验证)

```
宿主补丁驱动 
  → kfspSetupGspImages 修改 COT (gspFmcSysmemOffset + hash384)
  → kfspSendBootCommands 发送修改后的 COT 给 FSP
  → FSP 接收 COT
  → FSP 从 gspFmcSysmemOffset 读取固件
  → FSP 验证签名 (跳过 hash)
  → 通过: 加载固件 / 失败: 锁死
```

## 关键技术发现

### 1. 驱动模块替换 bug (耗时数小时发现)

```bash
# 错误(导致所有补丁看起来无效):
modprobe -r nvidia_uvm nvidia  # nvidia_modeset 还在引用!

# 正确:
modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia
```

**nvidia_modeset 不卸载,nvidia 模块就不会真正替换。**
所有补丁都编译进了新模块,但旧模块一直在跑。

### 2. GSP boot 路径 (TRACE 确认)

```
kgspInitRm_IMPL (kernel_gsp.c:5521)
  → _kgspBootGspRm (kernel_gsp.c:5429)
    → FSP path (kernel_gsp_gh100.c:964)
      → kfspPrepareBootCommands (kern_fsp_gh100.c:1311)
        → kfspSetupGspImages (kern_fsp_gh100.c:991)
          → COT 构建 (kern_fsp_gh100.c:1068) ← 我们的补丁在这里
      → kfspSendBootCommands (发送 COT)
```

### 3. FSP 响应行为

```
有效 COT + 有效签名 → GSP 启动
有效 COT + 无效 hash + 有效签名 → GSP 启动 (hash 不验!)
有效 COT + 修改的固件 → FSP 超时 + WPR2 locked + GSP locked
```

### 4. SBR 后 FSP 自解锁时间

```
SBR → badf4100 (locked) → 约 3-5 秒 → 自动解锁
但 EMEM 通道需要驱动初始化才能工作
无驱动时 FSP 活着但不处理 EMEM 消息
```

## 工具和方法

### DMA Buffer 内核模块
```c
// /home/user/dma_buf.c — 分配 <4GB 物理连续内存
// /proc/dma_buf — 读: 物理地址, 写: 数据
// __GFP_DMA32 确保地址在 32-bit 范围内
```

### COT 覆盖补丁模板
```c
// 在 kfspSetupGspImages 中, memdescUnmap 之前:
pCotPayload->gspFmcSysmemOffset = OUR_DMA_ADDR;
// hash384 可以是任何值(不验证!)
// signature 保持原始(这是验证的)
```

## 下一步研究方向

1. **签名绕过**: 
   - 签名验证算法是什么 (RSA? ECDSA?)
   - publicKey 字段是否可以替换
   - 签名验证代码是否有边界条件 bug

2. **publicKey 替换测试**:
   - 把 publicKey 换成自己的密钥
   - 用自己的私钥签固件
   - 如果 FSP 用 COT 中的 publicKey 验证 → 完整 ACE

3. **时序攻击**:
   - 签名验证的耗时测量
   - 是否可以逐字节猜测正确的签名

4. **FSP 固件逆向**:
   - 签名验证代码在 FSP 固件中
   - 固件加密但可能可以提取运行时代码

## 文件索引

- 本文档: `COT_SIGNATURE_FINDINGS.md`
- DMA 模块: `/home/user/dma_buf.c` + `/proc/dma_buf`
- 补丁驱动源码: `/home/user/gpu_src_615/`
- FMC 固件: `/lib/firmware/nvidia/gb202/gsp/fmc-570.144.bin`
- 之前分析: `COT_FINAL_VERDICT.md`, `COT_INJECTION_FINDINGS.md`

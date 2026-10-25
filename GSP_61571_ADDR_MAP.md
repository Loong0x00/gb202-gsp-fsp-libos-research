# GSP 615.71.09 关键地址定位 — 2026-09-29

## 已定位

```
tdispmgr 函数: VA 0x01ab7e04 (610.57 中是 0x18BBD60)
  - 函数头: c.addi16sp sp, -0x170
  - s1 = a1 (session/ctx 参数)
  - 请求大小 0xA4, 消息类型 0x0414 (与 610.57 相同)
  - mctpSubmit 调用

mctpSubmit: VA ~0x016F2604 (计算得出, 需验证)
  (610.57 中是 0x1B594D0)

字符串位置:
  _tdispmgrServiceMnocMctpAsyncMsg_GB100 @ 0x2016c10
  RMBifMnocOverride @ 0x20416c5 (新! 610.57 用 RmFspUseMnoc)
  RmOobMnocDisable @ 0x209b52d (新!)
  mnoc.elf @ 0x10697c8
  RMUseSwI2c @ ~0x209c2b0

EMEM lui 0x8f2 (基址访问): VA 0x16e5904
  (只有 1 处! 610.57 有多处)
```

## 还需要定位

```
1. msgq 接收函数 (K3-1 溢出点)
   610.57: 0x1016104
   特征: 拷贝循环 + bytes→elements 转换 + 后置校验

2. rxrefresh 回调 (K3-1 劫持点)
   610.57: 0x1004c9c
   特征: c.ld a5, 0xb8(a0); c.ld a1, 0x38(a0); c.ld a4, 0xc0(a0); jalr

3. 写 gadget
   610.57: 0x1b52246
   指令: c.sw a4, 0(a1); c.li a0, 0; c.jr ra

4. MNOC 控制标志 (新的!)
   610.57: ctx+0x1df, 由 RmFspUseMnoc bit1 控制
   615.71: RMBifMnocOverride (语义待分析)
```

## 下一步方法

```
1. 从 tdispmgr (0x01ab7e04) 的调用者回溯找消息泵
2. 从消息泵找 msgq 接收函数
3. 在 msgq 附近找 rxrefresh 回调
4. 搜索写 gadget 的字节模式
5. 分析 RMBifMnocOverride 的语义
```

## 更新 (2026-09-29 15:30)

### 已确认地址

```
tdispmgr (MNOC/MCTP 服务):
  610.57: VA 0x18BBD60
  615.71: VA 0x01ab7e04 ← 已确认
  验证: 函数头 c.addi16sp sp,-0x170, 引用 tdispmgr 字符串

MNOC 初始化 (aperture 设置):
  610.57: VA 0x150A3B0  
  615.71: VA 0x016e58f0 ← 已确认
  验证: lui 0x8f2 + addi -0x200 = 0x8f1E00 (MNOC 基址)
         addi 0x200 (aperture 大小)

mctpSubmit (统一提交 API):
  610.57: VA 0x1B594D0
  615.71: VA ~0x016F2604 (从 jalr 计算得出, 待直接验证)
```

### 代码重排程度

```
偏移不是统一的:
  tdispmgr:  0x18BBD60 → 0x01ab7e04 (代码位置大幅移动)
  MNOC init: 0x150A3B0 → 0x016e58f0 (不同方向移动)
  
结论: 不能用简单偏移做地址转换
      必须用字符串/模式匹配逐个定位
```

### 还缺的三个关键地址

```
1. msgq 接收函数 (K3-1 溢出)
   方法: 从 tdispmgr 的调用链回溯到消息泵
   
2. rxrefresh 回调 (K3-1 劫持)
   方法: 在 msgq 代码附近找 c.ld 0xb8(寄存器) 模式
   
3. 写 gadget
   方法: 搜索 c.sw a4,0(a1); c.li a0,0; c.jr ra 字节序列
```

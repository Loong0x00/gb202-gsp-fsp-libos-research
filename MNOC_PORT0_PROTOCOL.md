# MNOC port 0 完整协议手册 — 从发现到验证

日期: 2026-09-29/30
状态: 协议完整闭合, 在脏卡上验证通过

---

## 1. 发现过程

### B7b 的错误结论 (旧)

```
之前: 向 MNOC port 0 RECEIVEMBOX 写入
观察: CREDIT 消耗了(硬件接受) 但 FSP 无响应
结论(错误): "MNOC 有硬件级来源验证, 不是谁写都行"

实际原因: 协议姿势错误 — 没写 size|trigger 元数据到 INFO_RECV
```

### 正确协议来源

```
NVIDIA gpu-admin-tools (官方开源)
文件: gpu/mnoc.py — GpuMnoc 类
发现时间: 2026-09-29 晚
```

## 2. 寄存器布局

```
MNOC 基址: BAR0 + 0x8f1e00
端口步长: 0x0c

Port 0 (GSP 车道):
  INFO_SEND  = 0x8f1e00 + 0x104 + 0*12 = 0x8f1f04
  RDATA_SEND = 0x8f1f08
  INFO_RECV  = 0x8f1e00 + 0x184 + 0*12 = 0x8f1f84
  WDATA_RECV = 0x8f1f88

Port 1 (宿主车道):
  INFO_SEND  = 0x8f1f10
  RDATA_SEND = 0x8f1f14
  INFO_RECV  = 0x8f1f90
  WDATA_RECV = 0x8f1f94
```

## 3. 位定义

```
INFO_RECV (发送方向状态):
  bit 24 = receive-ready (FSP准备好接收)
  bit 25 = error (发送错误锁存)
  bit 26 = credits (缓冲区信用)
  bits 19:0 = 消息大小(bytes, 只在写入时用)

INFO_SEND (接收方向状态):
  bit 24 = message-ready (FSP有响应)
  bit 25 = error
  bits 19:0 = 响应大小(bytes)
```

## 4. 发送协议

```c
// 1. 等 receive-ready
while (!(INFO_RECV & (1<<24))) ;

// 2. 写元数据 (声明长度 + 触发)
INFO_RECV = size | (1 << 20);  // size in bytes, bit20 = trigger

// 3. 写数据 (每64字节等credit)
for (i = 0; i < words; i++) {
    if (sent % 64 == 0)
        while (!(INFO_RECV & (1<<26))) ;  // 等 credit
    WDATA_RECV = data[i];
    sent += 4;
}

// 4. 检查错误
if (INFO_RECV & (1<<25)) → error
```

## 5. 接收协议

```c
// 1. 等 message-ready
while (!(INFO_SEND & (1<<24))) ;

// 2. 读大小
size = INFO_SEND & 0xfffff;

// 3. 读数据
for (i = 0; i < size/4; i++)
    data[i] = RDATA_SEND;

// 4. 检查错误
if (INFO_SEND & (1<<25)) → error
```

## 6. 消息格式

```
Word 0: MCTP 传输头 = 0xC0000001 (SOM|EOM, seq=0, version=1)
Word 1: NVDM 头
  PRC (0x13): 0x1310de7e
  FWUP (0x12): 0x1210de7e
  COT (0x14):  0x1410de7e
Word 2+: 命令 dword + 参数 dwords
```

## 7. PRC 命令编码

```
Word 2 = subcommand | (flags << 8) | (arg << 16)

Knob 读:  0x0C | (0x02 << 8) | (knob_id << 16)
Knob 写:  0x0D | (0x02 << 8) | (knob_id << 16), value
Couple:   0x04 | (0x01 << 8) | (0x01 << 16)  [one-shot arm]
Task2:    0x02 | (subobject << 8)  [6字节载荷跟随]
```

## 8. 响应格式

```
Word 0: MCTP 响应头 = 0xC0020000
Word 1: NVDM 响应头 = 0x1510de7e (type 0x15 = FSP_RESPONSE)
Word 2: taskId (1=PRC, 3=FWUP)
Word 3: commandNvdmType (echo回请求的NVDM type)
Word 4: errorCode
Word 5+: data (如果有的话)
```

## 9. 已验证的操作

```
✓ Knob 读 (全部47个)
✓ Knob 写 (CC清除, 断电存活)
✓ Couple-reset arm (R1从0变1, SBR消耗后自动清零)
✓ Task2 零载荷 (generic success)
✓ FWUP cmd6 (status query, data=0x166585)
✓ FWUP cmd1-7 bare (all 0x188)
✓ FWUP cmd6 with params (0x2cd = length error)
```

## 10. 在脏卡上的行为

```
✓ PRC 读/写: 正常工作
✓ FWUP cmd6: 正常工作
✓ FWUP cmd1-5,7: 0x188 (会话门控, 但不挂死)
✗ COT (0x14): 处理器死(记录B), 不响应
✗ EMEM 写路径: 挂死(与nvflash写路径同死)
```

## 11. 参考实现

```c
// mnoc_prc.c (完整C实现)
// 编译: gcc -O2 -o mnoc_prc mnoc_prc.c
// BAR0基址根据环境修改 (宿主0xd8000000 / guest 0x80000000)

// 用法:
//   sudo ./mnoc_prc r <knob>       读knob
//   sudo ./mnoc_prc w <knob> <val> 写knob
//   sudo ./mnoc_prc c              arm couple-reset
//   sudo ./mnoc_prc fw <cmd>       FWUP命令
//   sudo ./mnoc_prc rawm <d1> <d2>...  原始多dword
```

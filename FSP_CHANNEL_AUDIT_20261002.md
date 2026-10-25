# FSP通道审计终极结论 — 2026-10-02 会话

## 今日核心发现

### 1. MNOC端口矩阵（完整）
| 端口 | 用途 | 状态 | ROMREAD(0x1A)? | 证据 |
|------|------|------|----------------|------|
| P0 | GSP车道 | error锁(0x8600000c) | ❌ 瞬时error | 宿主直写→ERR=1 |
| P1 | 宿主车道 | error锁(0x8600000c) | ❌ 瞬时error | 同上 |
| P2 | 内核CPU车道 | 未武装(badf5720) | ❌ 写入被忽略 | 静默无效果 |
| P3 | 未知 | 未武装(badf5720) | ❌ 同上 | 同上 |

### 2. 内核驱动的MNOC机制（源码确认）
```
kern_fsp.c:170 → 读注册表键 "RmFspUseMnoc"
  bit0(CPU)=1 → CPU走MNOC端口2 (KERNEL_FSP_MBOX_PORT=2)
  bit1(GSP)=1 → GSP走MNOC MCTP
kern_fsp_gb100.c:325 → gpuMnocMboxSend_HAL(port=2)
  前提: _gpuMnocMboxSendReceiverReady → 端口2 bit24必须=1
  实测: 端口2永远bit24=0 → 永不ready → 发送失败

强制CPU MNOC实验: 源码硬编码PDB_PROP_KFSP_USE_MNOC_CPU=TRUE
  → "FORCED: CPU will use MNOC mailbox (port 2)"
  → "FSP boot cmds failed. RM cannot boot."
  → FSP不接受端口2的boot命令（boot只认EMEM）
```

### 3. EMEM通道真相
```
写QH=0会同时重置QT=0（硬件副作用，不是FSP消费！）
之前"FSP消费了"的结论可能是误判
即使带正确MCTP头(0xC0000001)+NVDM头，任何类型都无响应
MSGQ(0x8F2C80/84)永远空
EMEM在boot后被FSP关闭（或从未对宿主开放）
```

### 4. FSP寄存器空间审计
```
BAR0 0x8F0000-0x8F0800: 95%是0xbadf5620(死区)
活跃寄存器:
  0x8F0320-23: SCRATCH_GROUP_2 (boot状态=0x9f)
  0x8F0330-34: SCRATCH_GROUP_3 (版本=0x44c=v4.76)
  0x8F1E00+: MNOC寄存器
  0x8F2AC0-84: EMEMC/EMEMD/队列
Falcon IMEM/DMEM窗口: 不存在或被硬件屏蔽
→ FSP内部内存(含解密固件)从宿主完全不可达
```

### 5. MNOC错误锁特性
- 一旦0x1A写入→瞬时ERR(bit25=1)→端口永久锁死
- 跨VM重启持久（GPU不物理断电）
- 跨GSP重启持久（GSP boot不清FSP的MNOC状态）
- 清除方法: 宿主nvidia驱动完整加载/卸载周期（可能通过FSP全初始化）

### 6. NVDM类型完整表（nvdm_format.h）
```
0x04=RESET  0x11=HULK  0x12=FWUP  0x13=PRC  0x14=COT
0x15=FSP_RESPONSE  0x16=CAPS_QUERY  0x17=INFOROM  0x18=SMBPBI
0x1A=ROMREAD  0x1C=UEFI_RM  0x1D=UEFI_DEBUG  0x1F=TNVL
0x20=CLOCK_BOOST  0x21=FSP_GSP_COMM  0x25=RM_RPC
```

## 死路总结（全部排除）
```
❌ MNOC p0/p1: 类型0x1A被硬件/低层固件硬滤
❌ MNOC p2/p3: FSP不武装这些端口
❌ EMEM CMDQ: 消息无响应（可能根本没被FSP读）
❌ FSP IMEM/DMEM: BAR0死区
❌ RmFspUseMnoc=1: 端口2 boot失败
❌ 宿主侧任何直接通道: 全部封闭
```

## 存活路径（按优先级）

### ① GSP侧泄漏读 → 真transport对象 → ROMREAD handler
（继承自上一会话，仍然是最佳路径）
参考: HANDOFF_20261001.md 方案①

### ② 物理SPI dump + GSP侧ROM读取
CH341A读加密flash + GSP ROM(明文,含解密逻辑) = 解密材料

### ③ 新思路: 修改GSP固件使GSP自己发ROMREAD
GSP固件在host内存中加载(gsp.61057.bin)
→ 修改GSP固件的NVDM发送代码
→ 让GSP在正常通信中夹带一条ROMREAD
→ FSP返回ROM数据到GSP
→ GSP正常转发到host RPC队列
（需要理解GSP固件的FSP通信代码并patch它）

## 文件引用
- 端口寄存器布局: MNOC_PORT0_PROTOCOL.md §2
- EMEM协议: MNOC_PORT0_PROTOCOL.md + 本文件§3
- 内核MNOC代码: greenfield src/nvidia/src/kernel/gpu/fsp/kern_fsp.c:170
- gpuMnocMboxSend: greenfield src/nvidia/src/kernel/gpu/arch/blackwell/kern_gpu_gb100.c:1251
- NVDM定义: greenfield src/nvidia/arch/nvalloc/common/inc/nvdm_format.h

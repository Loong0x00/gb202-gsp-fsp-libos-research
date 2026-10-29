# 实验规格:MNOC 信箱"声明长度 vs 实际投递"不一致(静态工作推导出的可执行实验)

日期:2026-09-26。来源:驱动源码 `src718` + DS/我自己的静态分析。**尚未执行**(会寄 FSP ⇒ 需用户批准)。

## 0. 为什么这个实验值得做
我们要找的是 **FSP 接收端的"先按声明长度拷、后校验"** 类内存破坏 bug(GSP 上我们已经打穿过同型:
`0x1016104`,宿主声明假长度 ⇒ GSP 侧拷贝溢出 ⇒ 控制流)。
FSP 代码是密文 ⇒ 静态不可判 ⇒ 只能用**畸形长度**黑盒判定。

## 1. 权威事实(驱动源码级别,fact)
```c
// kern_gpu_gb100.c: gpuMnocMboxSend_GB100(...)
if ((pMsgBuf==NULL) || (msgSize < min) || (msgSize > max)) return NV_ERR_INVALID_ARGUMENT;
_gpuMnocMboxSendReceiverReady_GB100(...);              // 等 READY
regVal  = REG_RD32(INFO_0_RECEIVEMBOX(port));          // 块内偏移 0x184 + port*0xC
regVal  = FLD_SET(MESSAGE_SIZE, msgSize, regVal);      // bits 19:0   ← 声明长度
regVal  = FLD_SET(MESSAGE_TRIGGER, SET, regVal);       // bit 20      ← 触发
REG_WR32(INFO_0_RECEIVEMBOX(port), regVal);
while (msgSize > 0) {                                   // 每 64B 等 CREDIT(bit26)
    data = 0; portMemCopy(&data, min(4,msgSize), pMsgBuf+offset, ...);
    REG_WR32(WDATA_0_RECEIVEMBOX(port), data);          // 块内偏移 0x188 + port*0xC
    offset += n; msgSize -= n;
}
return _gpuMnocMboxSendErrorCheck_GB100(...);          // ERR bit25
```
- `min = sizeof(NvU32) = 4`;**`max = 0xfffff + 1 = 1 MiB`**(字段本身的宽度)
- **边界检查在*驱动软件*里,不在硬件里** ⇒ 直接写寄存器可绕过(宿主有 BAR0,本来就能写这些寄存器 ——
  驱动自己就是这么发的)⇒ **这个实验不需要 GSP**,宿主即可。
- 相关位:`MESSAGE_SIZE` 19:0 / `TRIGGER` 20(只写)/ `RECEIVE_READY` 24 / `ERR` 25 / `CREDIT_AVAILABLE` 26
  (见 `dev_mnoc_pri_zb.h`;SENDMBOX=0x104+i*0xC,RDATA_SENDMBOX=0x108,RECEIVEMBOX=0x184,WDATA=0x188)

## 2. 三个变体(按期望值排序)
| 变体 | 做法 | 检验什么 |
|---|---|---|
| **V2(主)** | INFO 声明 = **1 MiB**;**实际推送 1 MiB 数据**,但 **NVDM/MCTP 头声明的载荷很小**(如 20 B) | 接收端按 **transport 长度** 还是按 **协议头长度** 分配/拷贝 ⇒ 两者不一致时的行为 |
| **V3** | INFO 声明 = 1 MiB;**只推 20 B** 就停(不补数据) | 接收端是否**在数据到齐前**就按声明长度行动;或硬件是否会补齐/挂起 |
| **V1(弱)** | 常规 20 B 报文,只把 INFO 的 SIZE 改成 0xfffff | 与 V3 类似但更"干净",先做可保底 |
递增风险:V1 < V3 < V2(V2 会把 1 MiB 灌进 FSP 的接收路径 ⇒ 最可能触发缓冲问题)

## 3. 观测点(判据)
- **安全实现**:`MNOC_SEND_ERR`(INFO bit25)置位 / FSP 回包 `errorCode != 0`(如 `0x20c`/`0x3a5`)/ 无异常
- **有 bug**:FSP WDT 或不可纠正错误(host 可见 Xid 字符串 `_FSP_WDT` / `_FSP_UNCORRECTABLE_ERROR`)、
  信箱挂死(READY 不再置位,所有端口无响应)、设备复位
- 记录:`0x1400+4i`(PBUS SW_SCRATCH: FWSEC 版本/Devinit 状态/FRTS/COT 轮询)、FSP `0xAD00BC`、
  PLM 家族是否变化(如果 FSP 崩了,这些会变 —— 这本身就是信号)

## 4. 前置/善后
- 前置:显示器在**核显**(已完成);记录 PLM/掩码基线(`BASELINE_READ_20260926.txt`,已完成)
- 善后:若 FSP 挂死 ⇒ 设备复位;若无效 ⇒ 整机断电(已知 FSP 状态可被断电清除;热重启不够)
- 现有工具可复用:`/home/user/fsp_probe/*`(EMEM/MNOC 发送)、`prcraw`、`peek`(只读观测)

## 5. 与"GSP 身份"路线的关系
本实验用**宿主**身份。若结果阴性,仍需试**以 GSP 身份**发(FSP 可能对来源端口不同对待):
资产已找到 —— `mctpSubmit`(`0x1B594D0`,GSP-RM 内 24 个调用者)+ `RmFspUseMnoc` 的 CPU/GSP 位
(`ctx+0x1db/0x1dc/0x1dd`)+ 传输分发函数 `fn 0x150c170`(按三标志选 `ctx+0x158/0x1c8/0x1d0` 三个方法)。

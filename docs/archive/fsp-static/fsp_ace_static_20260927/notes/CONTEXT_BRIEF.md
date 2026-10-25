# FSP-ACE 静态分析战役 2026-09-27 — 共享上下文

## 目标
用户需求:(优先)FSP 固件上的任意代码执行漏洞;(保底)GSP 上一个新的、宿主可达的内存溢出(与已知 K3-1 同类但作用稍差)。

## 硬约束(必须遵守)
- 纯静态:不碰 GPU、不加载内核模块、不执行固件、不联网。
- 只读分析;产物写入 /home/user/rt_5090_project/fsp_ace_static_20260927/。
- 项目红线:不写 BIOS/InfoROM/熔丝、不刷机、不对外报告。

## 关键事实(已由前期研究确证,勿重复推导)
1. FSP runtime 镜像(FSP_RUN,v6 descriptor,app=0x24/target=0x0f)在 VBIOS 中 AES-GCM 加密
   (熵 7.999/字节,三样本一致),本地与公开世界均无明文 ⇒ FSP 代码直接静态分析不可能。
   样本:parallel/k3_device_work/fsp/fsp_image{,_dell8d,_hpe9e}.bin
2. 明文资产:GSP-RM 610.57(本机在用版本)
   - power_governor_reverse/gsp61057_rx_full.bin (15.3MB, RX 段, ELF 无节表, 加载基址 0x1000000, VA=文件偏移+0x1000000)
   - power_governor_reverse/gsp61057_rw_full.bin (RW 段, VA 0x4000000+)
   - RV64GC 指令集,无符号,但有大量字符串与 __func__ 日志锚点
   - 工具:parallel/ds_work/disas_range.py, callgraph.py; parallel/k3_device_work/{func_starts.pkl(6942 函数), edges.pkl, refhits.pkl, namepool_refs.pkl}
3. 已知漏洞 K3-1(勿重复发现,它是"已知的那一个"):GSP 命令队列接收函数
   0x1016104(610.57 同地址)把宿主可控元素计数直接用作拷贝循环上界,校验全部后置
   ⇒ 64KB staging 越界写 ⇒ 覆盖 msgqMetadata(0xb8 fcnBackendRw 等函数指针)
   ⇒ 经 rxrefresh 调用点(0x1004c9c,a1=*(meta+0x38) 值可控)得任意 4 字节写
   ⇒ gadget 0x1b52246 (c.sw a4,0(a1); li a0,0; ret)。详见 parallel/DS_FMT_WRITE_PRIMITIVE_20260926.md
4. FSP 可达面(宿主 BAR0 直达):
   - EMEM ch0:寄存器 0x8f2ac0+8i (EMEMC/EMEMD),队列 0x8f2c00+8i (QUEUE_HEAD/TAIL),
     回包 0x8f2c80+8i (MSGQ_HEAD/TAIL);通道 1KB;宿主可任意写 EMEMC/EMEMD/QUEUE_*
   - MNOC port1:0x8f1e00 基址;INFO bits19:0=声明长度(上限 1MiB,发送方自声明,驱动软件侧检查,硬件无检查),bit20=TRIGGER,bit24=READY,bit25=ERR,bit26=CREDIT(每64B)
   - 协议:dword0=MCTP 头(SOM bit31/EOM bit30/SEQ 29:28/SEID 23:16),dword1=NVDM 头(type byte7,vendor 0x10de),payload 自 byte8
   - FSP 已实测行为:QTAIL 过申报超通道 ⇒ error 0x20c(拒);EMEM 上 task2 不受理(error 0xAF),MNOC port1 受理;
     SMBPBI(0x18)⇒ 无回包+FSP 信箱整个挂死(真 bug,DoS 级);PRC 对象写可把卡逼进 CC 模式(断电才清)
5. 宿主侧开源参照(610.43.03 树,rt_5090_project/driver_gpio_internal_610.43.03/src/nvidia/):
   - src/kernel/gpu/fsp/kern_fsp.c: kfspReadMessage(收包重组,先验后拷,安全)
   - src/kernel/gpu/fsp/arch/hopper/kern_fsp_gh100.c: EMEM 通道实现(GB202 复用)
   - src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb100.c: MNOC port2 (CPU-RM) 
   - GSP 侧也内嵌同源 kfsp 客户端(GSP ELF 有 "GPU-KFSP"、"RmFspUseMnoc" 字符串)
6. GSP 侧 MCTP 栈锚点(已知):
   - mctpSubmit = 0x1B594D0(24 个调用者);传输分发 = 0x150c170(按 RmFspUseMnoc CPU/GSP 位选 ctx+0x158/0x1c8/0x1d0 三个方法)
   - tdispmgr MNOC 服务 = 0x18BBD60(注册于事件表,请求/响应固定 0xA4/0x78)
   - 见 parallel/DS_GSP_MNOC_SERVER_20260926.md

## 本战役的两个工作流
- **Track F(FSP 线)**:把 GSP ELF 里 MCTP/kfsp/EMEM/msgq 接收侧代码全部反汇编审计,
  找"按声明长度先拷后验"型缺陷(与 K3-1 同型)。发现 ⇒ (a)若宿主可达,本身就是 GSP 新漏洞;
  (b)若 FSP 响应可达,即为 FSP 侧同族缺陷假设(FSP 服务端同一内部库血统)⇒ 产出精确黑盒触发规格。
- **Track G(GSP 线,保底)**:RPC 分发层(E3)与 NVDM type 解复用(E4)审计,
  找 K3-1 之外新的宿主可达内存溢出(栈/堆拷贝越界、计数信任等)。

## 产物纪律
- 每个结论必须带指令级证据(VA+反汇编片段)。
- 置信度分级:A=指令级确证;B=结构级;C=推断。
- 阴性结果同样有价值(记录"已排除+原因")。

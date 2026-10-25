# F-1 最终定级:GSP-RM GPU_EXEC_REG_OPS 无界 regOpCount 栈下溢 —— A 级实锤

日期:2026-09-27 08:38。发射平台:宿主 dkms 改驱动(initramfs 同步)→ 开机 RPC 流自动触发。

## 崩溃现场(原始 dmesg,artifacts/F1_CRASH_PROOF.log)
```
[4.829] F1PRIME: len=0x5054 -> 64KB zero-op primer        ← Stage A:20KB fn=76 扩为合法 64KB
                                                                  (16 元素=sizeMax,非溢出),message+0x58
                                                                  起全零(= 2045 个合法零 op),铺满 staging
[4.829] F1FIRE: fn76 len=0x54c -> fn=50 count=2045 fit=39  ← Stage B:下一条 fn=76 变身
                                                                  GPU_EXEC_REG_OPS,count=2045
[4.831] Xid 120: GSP task exception: store access page fault (cause:0xf)
        @ pc:0x1a8a938, partition:4#0, task:3, gfid:0
        sepc:0x1a8a938  stval:0xfeb7ffd50  scause:0xf
```

## 证据链闭合(静态 ↔ 动态逐点对上)
| 静态预言(反汇编) | 动态实测 | 判定 |
|---|---|---|
| handler 0x1a8a7f0 只查 length>0x57(0x1a8a846),count 从 message+0x3c 读、无界(0x1a8a84a) | count=2045 被原样消费 | ✓ |
| 校验循环终点 t3=payload+0x58+count×32,不与消息末端比较(0x1a8a85e) | fit=39,其余 2006 个幽灵 op 读 staging 残留(primer 铺的零 op)→ 校验全过 | ✓ |
| `sub sp,sp,count*32` 无界 VLA(0x1a8a916) | sp 下移 65,440 字节 | ✓ |
| VLA 拷贝循环 0x1a8a92c-0x1a8a98c(首条 `sb a3,-0x20(a4)` @0x1a8a938) | **崩溃 PC = 0x1a8a938(stval=0xfeb7ffd50,store page fault)** | ✓✓✓ |

## 漏洞定义
- **组件**:NVIDIA GSP-RM 专有固件 610.57.04(RV64,RM_RPC 命令队列路径)
- **位置**:RPC function 50(GPU_EXEC_REG_OPS)handler @ GSP VA 0x1a8a7f0
- **缺陷**:regOpCount 字段(消息偏移 +0x3c)被直接用作 VLA 分配与拷贝上界,仅有的长度检查(实际长度>0x57)与 count 完全脱钩
- **原语**:宿主可控的 GSP 侧栈区域越界写(内容=attacker-primable 的 32B op 结构;范围=count×32,单消息最大 ~64KB;配合 staging 铺垫可稳定触发)
- **影响**:GSP 任务崩溃(Xid 120)已证;栈下方若为映射区(非 guard page)则为受控内存破坏——本次实测 stval 落在栈底 guard 页(fault),说明该任务栈底有保护,但 **count 可控 ⇒ 下探深度可控**,对"栈下方无保护的部署/版本"构成直接写原语
- **与 K3-1 的关系**:完全独立(K3-1=msgq 接收层线性 staging 溢出;F-1=RPC 分发层 VLA 栈分配+越界源读)
- **触发前提**:宿主内核(或等价通道)能向 GSP 命令队列注入/改写 RPC——本项目经 dkms 改驱动实现;恶意内核模块/被攻破的宿主同权
- **公开基线**:无先例(专有 GSP-RM blob 内存破坏 CVE 公开世界为零,见 PUBLIC_BASELINE_CHECK.md)

## 阶梯记录(本次会话)
| count | VLA | 结果 |
|---|---|---|
| 16 | 512B | 正常处理,回包(Unexpected RPC event: 0x32) |
| 600 | 19.2KB | 正常处理,回包(GSP 任务栈 >19.2KB 或下方映射) |
| **2045** | **65.4KB** | **store page fault @ VLA 拷贝指令,Xid 120** |

## 副产物发现(本会话)
1. 驱动重载周期的 WPR2 残留规律:RPC 楔死/硬杀持有者 ⇒ 脏关机 ⇒ FSP 不放 WPR2 ⇒ 重载必败,需整机重启(热重启可清)
2. initramfs 内嵌 nvidia.ko(启动加载的是旧副本)——任何 dkms 实验必须同步 mkinitcpio
3. COT 无驱动窗口:size 字段偶数→处理(0xD7 字段拒绝)、奇数→静默;64KB 声明也无界拷贝 ⇒ size 轴安全关闭
4. MNOC port1 楔死事故(ERR 锁存不可恢复,排空/W1C 无效;EMEM 通道不受影响=按端口隔离)
5. B2(QUEUE_HEAD):真模块重测——HEAD≠0 被校验拒绝(HEAD=1→0x202,HEAD=200→静默);旧"HEAD 无视"结论作废(旧模块参数未生效)
6. B1(EMEM 多包):SOM-only→0x202、EOM-only→静默丢弃 ⇒ 重组缓冲不可达,关闭

## 系统状态
已完全恢复:源码 0 标记、驱动 0 fire 字符串、initramfs 干净重建。本启动内 GPU 因崩溃残留 WPR2(下次重启即恢复,已验证该规律)。

# GSP 侧 FSP 通信栈 / MCTP 纯静态审计

日期：2026-09-27。范围仅为本地 GSP-RM RX 指令与已有静态参考资料；未访问 GPU、驱动运行态、设备节点或 MMIO，未执行固件、未联网。除本文件外未在目标目录外写入分析产物；未修改 `parallel/` 下文件。

## 0. 结论摘要

1. **`RmFspUseMnoc` 被 GSP 内的初始化函数 `0x1509338` 查询。** 查询值 bit0、bit1 分别被写成对象字节 `+0x1dd`、`+0x1df`；结合注册表位定义，bit0 是 CPU-MNOC，bit1 是 GSP-MNOC。GSP 端既有 EMEM 后端，也有 MNOC aperture/方法表路径；多个 EMEM 方法在 `+0x1df != 0` 时 trampoline 到对象方法槽。因此不是 `mctpSubmit` 内按报文字段直接选硬件通道。
2. **`mctpSubmit=0x1B594D0` 是可复用的 GSP 内部报文提交入口。** 它按本地 `msg[0]` 做类型分发，并对若干类型使用固定拷贝长度；它本身不按 MCTP/NVDM wire length 重建或校验报文。服务端例子 `0x18BBD60` 构造固定 `0xA4` 请求、接收固定 `0x78` 回调结果。
3. **可见 EMEM RX 路径 `0x14FB74C` 先以接收队列可用字节数与调用者容量比较，再从 EMEMD 搬运**；容量不足走错误路径，不进入拷贝。安全性仍依赖传入容量真实、队列索引有效。
4. **`mctpSubmit` 完成侧只重建固定前缀/类型化 payload，却把固定 `0x78` 字节交给回调。** 0x0f/0x10/0x11 分支分别只写 `0x18/0x1c/0x0c` payload，0x12 写 `0x74`，0x14 不写 payload；未见对输出临时区先清零。因此短响应尾部存在向回调复制未初始化栈内容的可能（是否被调用者暴露或使用，依赖回调）。
5. **未发现由 wire 声明长度驱动的 GSP MCTP 拷贝越界；另有上述潜在 stale-stack 暴露。** 已知 `0x1016104` msgq 缺陷是下层队列接收问题，按上下文要求不重复报告。MNOC 收包最终进入哪些槽函数以及其完整动态长度校验，无法仅凭静态对象构造唯一绑定到运行时实例，报告为未决而非安全结论。
6. FSP runtime 镜像是密文，不能据此审计 FSP 服务端收包校验。此报告不推断 FSP 侧安全性。

## 1. 样本与证据约定

- 明文样本：`power_governor_reverse/gsp61057_rx_full.bin`，RV64GC，VA=`文件偏移+0x1000000`；可见文件长度 `0xE97000`，尾部缺 `0x4000`。下文所有指令均在该文件已含范围内。FSP runtime 镜像加密/尾截断状态见本目录 `notes/CONTEXT_BRIEF.md`；因此不对 FSP 明文行为作结论。
- RW 样本的 `0x41906B0` 等全局描述符在静态 dump 中为零/BSS，运行期缓冲地址与容量无法从文件恢复。
- 置信度：**A**=指令级事实；**B**=由调用形状/相邻代码推断；**C**=无法唯一解析的动态路径。
- 下列指令摘录保留 VA 和反汇编；地址均为 GSP VA。

## 2. `RmFspUseMnoc` 与通道选择

### 2.1 引用函数与 CPU/GSP 位

字符串 `RmFspUseMnoc` 位于 VA `0x1E7B798`，唯一指令引用在 `0x1509426`，归属函数 `0x1509338`。这是配置/初始化函数，而不是 `mctpSubmit` 内联字符串读取：

```asm
0x0150941e  addi a2,s0,-0x3c
0x01509422  auipc a1,0x972
0x01509426  addi a1,a1,0x376     ; a1 = 0x1e7b798, "RmFspUseMnoc"
0x0150942a  mv   a0,s2
0x0150942c  auipc ra,0xffb33
0x01509430  jalr ra,ra,-0x3d8    ; 查询注册表，结果写入栈变量
0x0150943c  andi a4,a5,1
0x01509440  bnez a4,0xc2
0x01509442  andi a5,a5,2
0x01509444  bnez a5,0xde
...
0x015094fc  sb   a5,0x1dd(s1)   ; bit0 -> ctx+0x1dd = 1
...
0x01509536  sb   a5,0x1df(s1)   ; bit1 -> ctx+0x1df = 1
```

注册表头文件中的位定义为 `CPU=0x1`、`GSP=0x2`（上下文参考文档已核）。因此 GSP bit 是 `+0x1df`，不是 `+0x1dd`。**A**（引用、掩码、写入字节）；注册表位的 CPU/GSP 语义 **B**（与本地头文件对照）。

### 2.2 EMEM 后端与 MNOC trampoline

存在明确的 GSP EMEM 操作代码：

- `0x1501628` 访问 `0x8f2ac0/0x8f2ac4`（EMEMC/EMEMD）及 `0x8f2c00/04`、`0x8f2c80/84` 队列寄存器；入口保存 `a2` 源缓冲、`a3` 长度，代码按 dword 写 EMEMD 并推进 queue tail。它是 GSP→FSP 的 EMEM 发送后端候选/方法实现，具体虚调用者由对象方法表决定。**A**（寄存器与传参事实），高层协议语义 **B**。
- `0x14FB74C` 读取 FSP→GSP 的 MSGQ，按 head/tail 算可用长度并从 EMEMD 搬入调用者缓冲（见 §4.1）。
- `0x150A3B0` 为 MNOC 对象准备 aperture 参数：`lui/addi` 得到基址 `0x8f1e00`，并把长度 `0x200` 放入构造参数，再调用 `0x1951660`。这确认 GSP 有 MNOC aperture 初始化路径；不等于证明该路径在所有配置中已启用，也不能仅凭这段确定端口号。

例如 `0x14FB74C` 的尾部仅在特定 `a4 != 0` 控制出口检查 +1df 并可能转交对象方法；`0x14F6BC0` 等 EMEM 包装函数也检查此标志：

```asm
0x014fb900  beqz a4,0x22
0x014fb902  lbu  a6,0x1df(a1)
0x014fb906  beqz a6,0x14
0x014fb90a  lui  a1,2
0x014fb90c  add  a5,a0,a1
0x014fb910  ld   a1,0x260(a5)
0x014fb914  ld   a5,0x150(a1)
0x014fb918  jr   a5             ; GSP-MNOC 标志打开时走对象方法
```

包装 `0x14F6BC0` 读 `ctx+0x1df`，置位时经对象 `+0x260` 再间接调用其 `+0x158`；`0x14F6C3C/0x14F6C90/0x14F6CCC` 分别使用 +0x160/+0x168/+0x170。故实际通道切换由初始化对象和函数指针表完成；MCTP 提交函数本身不选择 port。**A**（条件和间接跳转），槽的协议命名 **B/C**。

### 2.3 `0x150C170` 的三个方法槽

`0x150C170` 内可直接看到三个不同调用点：

```asm
0x0150c5b6  ld   a5,0x158(a1)
0x0150c5e4  mv   a1,s1
0x0150c5e6  mv   a0,s2
0x0150c5ea  jalr a5             ; ctx+0x158(owner,ctx)，返回状态
...
0x0150c63c  ld   a5,0x1c8(s1)
0x0150c640  mv   a1,s1
0x0150c642  mv   a0,s2
0x0150c644  jalr a5             ; ctx+0x1c8(owner,ctx)
0x0150c646  addi a2,s0,-0x84    ; 随后使用栈上输出/状态位
...
0x0150c67a  ld   a5,0x1d0(s1)
0x0150c680  seqz s9,s9
0x0150c684  mv   a2,s9
0x0150c686  mv   a0,s2
0x0150c688  jalr a5             ; ctx+0x1d0(owner,ctx,bool)
```

事实层面：`+0x158` 是第一阶段调用；`+0x1c8` 接在条件检查后并关联一个栈输出；`+0x1d0` 接收布尔参数并返回状态。**反汇编没有符号名，不足以把它们严谨命名成 send/recv/ack。** 大型初始化函数 `0x1983C1C` 存在多套按类型/特征分支写入方法表的代码；其中一个初始化序列把 `+0x158` 写为 `0x10BD380`、`+0x1C8` 写为 `0x1978CE0`、`+0x1D0` 写为 `0x1978CF0`（后两者是返回 `0x56` 的 stub）。不能证明这是 `0x150C170` 运行时所持的同一个实例，因此不将这组值冒充为 MNOC 活跃路径的唯一绑定。**A**（槽位访问）；实例绑定与方法语义 **C/未决**。

## 3. `mctpSubmit` 的 TX 重建与 GSP→FSP 发送原语

### 3.1 本地 API 形状与类型分发

入口 `0x1B594D0` 栈帧 `0x140`，从第三参数 `msg` 读 `msg[0]`，用六项跳转表处理 `0x0F..0x14`；既不解析 wire dword0 的 SOM/EOM/SEQ/SEID，也没有取外部声明长度的指令。入口证据：

```asm
0x01b594ee  lbu   a6,0(a2)       ; type = msg[0]
0x01b594fc  addiw a5,a6,-0xf
0x01b59520  bltu  a2,a5,0x18e    ; 越出类型表则错误
0x01b59524  auipc/addi ...       ; 六项 u32 相对跳转表
0x01b59536  jr    a5
```

可见的本地 request payload 固定长度如下；各长度均为立即数而非由包字段驱动：

| `msg[0]` | source | 固定拷贝长度 | 备注 |
|---|---|---:|---|
| `0x0f` | `msg+4` | `0x40` | `0x1B595F6` 设常数后调用 copy helper |
| `0x10` | `msg+4` | `0xA0` | 同时读取 `msg[4]` 字段 |
| `0x11` | `msg+4` | `0x20` | 固定长度 |
| `0x12` | `msg+4` | `0x44` | 固定长度 |
| `0x13` | — | — | 记日志并返回状态 `0x1f` |
| `0x14` | — | — | 本 switch 分支不做 payload copy，设置内部状态后继续流程 |

例：

```asm
0x01b595d8  ... ld a0,0xd8(...)  ; 运行期描述符目标指针
0x01b595e0  addi a1,s7,4         ; src = msg+4
0x01b595ee  addi a5,a0,0x40
0x01b595f2  bgeu a1,a5,...       ; 指针/区间路径判断
0x01b595f6  li   a2,0x40
0x01b595fa  jal  0x1b63b2c       ; 固定 0x40 copy
```

调用点含非空、地址区间/重叠处理后才进入拷贝；没有从 `msg` 获得实际长度与 `0x40/0xa0/0x20/0x44` 比较。目标地址来自 RX/RW 镜像中为 BSS 的描述符 `0x41906B0`，缓冲容量未知，故只能确证“不是声明长度驱动”，不能证明所有调用者缓冲容量足够。**A**。

### 3.2 完成侧的固定结果重建

成功等待/取回结果后，`mctpSubmit` 在局部缓冲 `base = s0-0xf0` 上先复制请求头 4 字节：`0x1B59900..0x1B5990E` 调 `0x18BD9D8(dst=base, dstCap=4, src=msg, n=4)`；随后按原请求 `msg[0]` 选择结果源，payload 目的地均为 `base+4 = s0-0xec`。可见长度：

| 类型 | payload 拷贝 | 先验/边界 |
|---|---:|---|
| `0x0f` | `0x18` | `0x18BD9D8`，cap 与 n 均为 `0x18`；源为全局描述符 `+8` |
| `0x10` | `0x1c` | `0x18BD9D8`，cap 与 n 均为 `0x1c`；selector 为 6 时走另一分支，否则回调 |
| `0x11` | `0x0c` | `0x18BD9D8`，cap 与 n 均为 `0x0c`；源为全局描述符 `+8` |
| `0x12` | `0x74` | 调 `0x1B63B2C(dst,src,n)`，仅见源/目的相等时跳过，没有显式目的容量或源长度检查；目的为局部栈区 |
| `0x14` | 0 | 仅先复制 4 字节头，之后仍可进入固定回调 |
| `0x13` | — | 前段类型分发以状态 `0x1f` 退出，不进入该正常完成回调路径 |

因此 `0x12` 的 `4+0x74=0x78` 恰好铺满回调帧；其余类型只写局部结果区的前 `0x1c/0x20/0x10/0x04` 字节。反汇编中没有在此区域先做 `memset(0,0x78)`：首次可见写入是 4 字节头拷贝，随后只有上述短 payload 拷贝。`0x1B59964..0x1B59968` 对正常回调仍传 `base`，且具体回调 `0x18B4DDC` 无条件复制 `0x78` 字节。**A**（拷贝长度、次序、固定回调）；尾部实际内容是否曾被其他未识别别名写入 **B**。

这形成一个**潜在未初始化栈尾传递**：`0x0f/0x10/0x11/0x14` 时短拷贝后的余下 bytes 没有本函数内清零，却被固定长度回调读出并写到 `deliver_ctx`。最直接的 `0x18BBD60` caller 只检查 `resp[0]`，未见其把尾部送出固件；不能据此断言外部可利用，但其他回调可见整段数据。属于信息暴露/数据契约风险，不是报文长度驱动越界写。

### 3.3 已证实的 GSP→FSP 调用样例

`0x18BBD60`（tdisp/MNOC 服务例程）是具体发送方：栈上清零 `req[0xA4]`、`resp[0x78]`，写 `u16 0x0414`，再调 `mctpSubmit`：

```asm
0x018bbd84  addi a2,zero,0xa4
0x018bbd98  jal  0x1be41ec       ; memset(req,0,0xa4)
0x018bbda0  addi a2,zero,0x78
0x018bbdaa  jal  0x1be41ec       ; memset(resp,0,0x78)
0x018bbdb6  li   a5,0x414
0x018bbdc4  sh   a5,-0xe0(s0)    ; req[0..1]=0x0414，msg[0]=0x14
0x018bbdd0  addi a4,s0,-0x158   ; deliver_ctx = resp
0x018bbdd4  auipc a3,0xffff9
0x018bbdd8  addi a3,a3,8         ; deliver_cb = 0x18b4ddc
0x018bbde2  mv   a0,s1
0x018bbde4  jal  0x1b594d0       ; (pObj,selector,req,deliver_cb,&resp)
```

反推的 API 形状（**B**）：`mctpSubmit(pObj, selector/session, msg, deliver_cb, deliver_ctx)`；`msg` 是本地类型化请求，不是已组装的 MCTP wire frame。transport 内部再调用对象方法/下层队列。全镜像约有 24 个直接调用者，说明它是通用入口；但不同 caller 的缓冲契约各异。

因此可复用的 GSP→FSP NVDM 原语是 `0x1B594D0`（而非 `0x18BBD60` 的 tdisp 服务封装）。EMEM 路径能直接看到 `0x1501628` 通过 EMEMC/EMEMD 写数据；`RmFspUseMnoc` GSP 位打开时，则通过方法表切到 MNOC。**没有证据证明 GSP MNOC 活跃端口号是固定值**；宿主侧 CPU port 常量不能直接代替 GSP 的 runtime port 选择。

## 4. 接收重建、每个可见拷贝点的校验顺序

### 4.1 EMEM FSP→GSP 收包 `0x14FB74C`

此方法从 `0x8f2c80/0x8f2c84` 读取 MSGQ head/tail，计算待取字节数，再以第四参数 `a3`（调用者容量）先检查，之后才读 EMEMD 写目的缓冲。关键顺序：

```asm
0x014fb760  ... lw s5,-0x380(a5)  ; MSGQ_HEAD @ 0x8f2c80
0x014fb774  ... lw s4,-0x37c(a5)  ; MSGQ_TAIL @ 0x8f2c84
0x014fb77c  addiw s4,s4,4
0x014fb77e  subw  s4,s4,s5        ; 可用字节数（ring 差值）
0x014fb782  sext.w a1,s4
0x014fb786  bgeu  a0,a1,...       ; 极小/无可用数据走非拷贝路径
0x014fb78a  bgeu  a3,a1,0x46      ; capacity >= 可用长度才进 copy
...
0x014fb7ea  ...                   ; copy path
0x014fb80a  lw    a5,-0x53c(a5)   ; EMEMD
0x014fb80e  sw    a5,-4(a2)       ; 写调用者目的缓冲
...
0x014fb816  sw    s4,0(s6)        ; *pOutLen = 实际搬运量
```

容量不足分支先返回错误（可见返回值 `0x25`），不会落入 EMEMD dword 拷贝路径；代码另有未对齐长度日志分支，但未见按字节补拷。**A**：顺序是“得出队列可用量→比较目的容量→读取/写目的缓冲”。局限：head/tail 的运行期有效性与调用者是否谎报容量不能由这一函数保证；MNOC 标志打开时该函数还会转入动态对象方法，不适用于证明 MNOC RX 方法安全。

### 4.2 `mctpSubmit` 完成缓冲的逐拷贝顺序

这与 §3.2 的结构重建相对应，重点是校验顺序：

- 头部 `0x4`：`0x1B59900..0x1B5990E` 调 `0x18BD9D8`，容量参数 `a1=4`，长度 `a3=4`；该 helper 先比较 cap/len，再拷贝。
- `0x10` payload `0x1c`：`0x1B59934..0x1B5994A`；cap=`0x1c`、len=`0x1c` 后调 `0x18BD9D8`。
- `0x0f` payload `0x18`：`0x1B59A04..0x1B59A1A`；cap=len=`0x18`，调同一 bounded helper。
- `0x11` payload `0x0c`：`0x1B59A20..0x1B59A36`；cap=len=`0x0c`，调同一 bounded helper。
- `0x12` payload `0x74`：`0x1B59972..0x1B5998C`；仅比较 source pointer 与 destination pointer 是否相同，不同则以 `a2=0x74` 调 `0x1B63B2C`。无动态 source length/cap 比较，但目的区是 `base+4` 后的栈内固定空间，局部容量为 `0x74`；source 描述符容量无法从 BSS 静态恢复。

没有观察到 `base..base+0x78` 在这些拷贝前整体清零。不同分支写入长度低于 `0x78` 时，其余栈字节会被下一节的固定回调读出。该项是信息暴露/未初始化数据契约风险，**不是**由报文声明长度导致的越界写。针对该问题的置信度：代码未清零并固定读 0x78 为 **A**；内容是否能被不可信主体观察为 **B/C**。

### 4.3 `mctpSubmit` 的回包投递 `0x18B4DDC`

`mctpSubmit` 收尾时将调用者第 4 参作为回调，传入 transport 内部缓冲与第 5 参：

```asm
0x01b59954  ld   a2,-0x120(s0)   ; deliver_ctx
0x01b59958  ld   a0,-0x108(s0)   ; pObj
0x01b5995c  ld   a5,-0x118(s0)   ; deliver_cb
0x01b59964  addi a1,s0,-0xf0     ; internal buffer
0x01b59968  jalr a5
```

例子回调 `0x18B4DDC` 的拷贝是固定 0x78：

```asm
0x018b4de2  beqz a2,...           ; dst 非空
0x018b4de4  beqz a1,...           ; src 非空
0x018b4de8  beq  a2,a1,...
0x018b4df0  addi a5,a1,0x78
0x018b4df4  bltu a2,a5,...        ; overlap/方向检查
0x018b4e10  addi a4,a0,0x78
0x018b4e14  ld   a5,0(a1)
0x018b4e1a  sd   a5,-8(a0)        ; 8 字节循环，共 0x78
```

它不接收源长度或目的容量；相应地没有动态长度校验。对 `0x18BBD60` 这个已核实例，调用前明确预留且清零 0x78 字节，故固定拷贝符合其调用契约；若其他 caller 给更小的 buffer，则回调本身不能保护它。**A**（复制常量与指针分支）；实例安全 **B**。

### 4.4 其它可见层与未闭合路径

- `0x101671C` 是 MCTP 路径触发的 msgq 投递/索引更新（`0x1B597CE` 调用）；它更新 `+0x70/+0x74` 等队列索引，不是报文 payload 的重建拷贝点。
- 已知 msgq RX `0x1016104` 存在“宿主计数作拷贝上界，验证后置”的已知问题（上下文 K3-1）。按任务约束，本报告只标记为下层既有问题，不重复作为新发现，也不将其归因于 `mctpSubmit`。
- `RmFspUseMnoc` 的 GSP bit 把 EMEM 方法转为对象方法；`0x150C170` 还有 +0x158/+0x1c8/+0x1d0 动态方法调用。静态能确定槽位/调用参数，不能在不假设运行期对象类型的条件下唯一确定 MNOC RX 实例的槽目标和拷贝主体。**MNOC 接收长度校验顺序：未决（C）**，不能因 EMEM fallback 安全就推出 MNOC 路径安全。
- `0x18BD9D8` 是通用 bounded-copy helper 的另一处证据：调用方传入 `(dst, dstCap, src, n)`，它先做 `dstCap < n` 比较，才进入拷贝分支；目前 `mctpSubmit` 已定位到的这些调用用于本地固定字段构造，不能替代对动态 MNOC RX 槽的审计。

## 5. 负结果、置信度与限制

| 结论 | 级别 | 边界 |
|---|---|---|
| `RmFspUseMnoc` 唯一引用、bit0/bit1 写入 +1dd/+1df；+1df 控制多处方法 trampoline | A/B | 位的 CPU/GSP 名称由本地注册表定义对照 |
| GSP 存在 EMEMC/D + queue/msgq 客户端，且 `0x14FB74C` 在拷贝前比容量 | A | 调用者容量真实性、队列索引运行态未证 |
| GSP MNOC aperture 初始化参数包含 base `0x8f1e00`, span `0x200` | A | 不证明启动时启用或固定 port |
| `mctpSubmit` 按 0x0f–0x14 类型分发；payload 拷贝尺寸为常量；非声明长度驱动 | A | BSS 目标缓冲真实容量未知 |
| `0x18B4DDC` 固定复制 0x78；具体 tdisp caller 提供 0x78 | A/B | 回调目的容量没有运行期校验；短响应源尾部未见清零，存在潜在 stale-stack 传递 |
| `mctpSubmit` 完成缓冲的 0x0f/10/11/14 短拷贝后仍固定回调 0x78 | A/B | 可能暴露栈尾，调用方能否向不可信边界传播未证 |
| MNOC 动态 RX slot 的确切函数/长度检查 | C / 未决 | 多套构造路径和对象类型，静态无法唯一绑定 |
| FSP runtime 内部收包校验 | UNKNOWN | FSP image encrypted，无明文指令可审 |

**关键阴性结果：**未在 `0x18BBD60`/`0x1B594D0` 找到由 wire 声明长度驱动的拷贝；该服务的 request/response 容量是 `0xA4/0x78` 常量。但这不等于整条路径无风险：短结果分支只初始化局部回调缓冲的前缀，随后固定拷贝 0x78 字节，存在潜在未初始化栈尾传递。此处没有证据证明尾部可从固件外部观察；也不能排除 msgq 或动态 MNOC 方法层的问题。

## 6. 可复核命令

```bash
cd /home/user/rt_5090_project/parallel/ds_work
python3 find_va_refs.py 0x1e7b798
python3 disas_range.py 0x1509338 0x2a0
python3 disas_range.py 0x150c170 0x600
python3 disas_range.py 0x1983c1c 0x230
python3 disas_range.py 0x150a3b0 0x80
python3 disas_range.py 0x14fb74c 0x220
python3 disas_range.py 0x1501628 0x280
python3 disas_range.py 0x18bbd60 0x100
python3 disas_range.py 0x1b594d0 0x6a2
python3 disas_range.py 0x18b4ddc 0x56
python3 callgraph.py callers 0x1b594d0
python3 callgraph.py callees 0x1b594d0 0x1b59ad0
```

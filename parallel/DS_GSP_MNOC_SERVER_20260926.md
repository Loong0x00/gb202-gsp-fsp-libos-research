# DS:GSP MNOC/MCTP 异步报文服务端 `_tdispmgrServiceMnocMctpAsyncMsg_GB100`

日期:2026-09-26。范围:**只读本地文件分析**,未碰 GPU/驱动/VM,未执行固件,未联网。
镜像:`power_governor_reverse/gsp61057_rx_full.bin`(RV64GC,加载基址 `0x1000000`,
md5 `138c287af83b5026770f636b3b2c9f4b`,ELF 无节表);RW 段判读用同目录
`gsp61057_rw_full.bin`(md5 `11a87a5f3ae6c849a2c3a7753a44be9e`)。

**读取前提(caveat)**:`rx_full.bin` 被截断 —— 文件长 `0xE97000`,而 ELF 第一个 LOAD
段为 `[0x1000000,0x1E9B000)`(FileSiz `0xE9B000`),RW LOAD(`0x4000000+`)整体不在该文件里。
本报告所有结论都只用 VA `< 0x1E97000` 的字节或 RW 镜像;凡落到
`0x1E97000..0x1E9B000`、`0x1E9B000..0x20000000`、`0x20000000+` 的地址一律标注"文件未包含"。

---

## 0. 一句话结论

`_tdispmgrServiceMnocMctpAsyncMsg_GB100` 的字符串 **只有一个代码引用点**
(`0x18BBE08`),位于函数 **VA `0x18BBD60` / 文件 `0x8BBD60`**(0xF6 B,栈帧 `0x170`)。

该函数是一个**注册在"事件位 → 处理函数"表里的服务例程**(无任何直接调用者,见 §1.4),
它自己**不解析入站报文**,而是:取会话指针 → 构造固定 `0xA4` 的请求(u16 `0x0414`,
即 `msg[0]=0x14`)→ 调用 MCTP 提交/分发 API **`0x1B594D0`** → 检查回包首字节 `== 0x14`。

**关键否定结论**:这条 MNOC/MCTP 服务路径上**没有**"从描述符/信箱结构里取长度字段、
再按该长度拷贝"的结构 —— 上行下行所有长度都是编译期常量(`0xA4/0x78`,
transport 内 `0x40/0xA0/0x20/0x44`)。因此 `0x1016104` 那种"先按长度拷、后校验"
的 bug **不在此层**;长度驱动的拷贝在更下层 msgq/device 层(§2.4)。

---

## 1. 函数位置与范围

### 1.1 名字字符串(定位锚点)

| 项 | 值 |
|---|---|
| 字符串 VA / 文件偏移 | `0x1DE6958` / `0xDE6958`(位于 `0xDE6958` 的 ASCII 字面量,后随 `"610.57.04"`) |
| 全镜像出现次数 | 1(`strings_all.txt` 里唯一) |

```
00de6950: 0f00 0000 0000 0000 5f74 6469 7370 6d67   ........_tdispmg
00de6960: 7253 6572 7669 6365 4d6e 6f63 4d63 7470   rServiceMnocMctp
00de6970: 4173 796e 634d 7367 5f47 4231 3030 0000   AsyncMsg_GB100..
00de6980: 3631 302e 3537 2e30 3400 0000 0000 0000   610.57.04.......
```

`python3 find_va_refs.py 0x1de6958` 全镜像只有 1 个 auipc 引用:

```
0x018bbe08 -> 0x01de6958   [addi a1, a1, -0x4ac]   in fn 0x18bbd60
```

该点位于函数序言 `0x18BBD60` 之内(`c.addi16sp sp,-0x170`),因此
**`_tdispmgrServiceMnocMctpAsyncMsg_GB100` = VA `0x18BBD60`**。

### 1.2 该引用为何是"函数名"而不是普通字符串

`0x18BBDEC`–`0x18BBE12` 是一条 **GSP-RM 结构化日志/断言调用**,寄存器实参为
`(a0=level, a1=pFuncName, a2=actual, a3=expected, a4=pFileName)`:

```
0x018bbdf0  03 46 84 ea lbu      a2, -0x158(s0)   ; a2 = resp[0] (实际值)
0x018bbdf4  d1 47       c.li     a5, 0x14
0x018bbdf6  63 00 f6 02 beq      a2, a5, 0x20     ; 相等 -> 直接返回
0x018bbdfa  17 c7 ac 1e auipc    a4, 0x1eacc      ; a4 = 0x20387EC0 (文件名,文件未包含)
0x018bbdfe  13 07 67 0c addi     a4, a4, 0xc6
0x018bbe02  d1 46       c.li     a3, 0x14         ; a3 = 期望值 0x14
0x018bbe04  97 b5 52 00 auipc    a1, 0x52b        ; a1 = 0x1DE6958 = 函数名
0x018bbe08  93 85 45 b5 addi     a1, a1, -0x4ac
0x018bbe0c  11 45       c.li     a0, 4            ; level=4
0x018bbe0e  97 20 1e 00 auipc    ra, 0x1e2
0x018bbe12  e7 80 e0 7d jalr     ra, ra, 0x7de    ; -> 0x1A9E5EC 日志器(用 tp=TLS 环形缓冲)
```

同一实参形状在其它模块的同族调用中一致(`gpioGetInterruptHal_v05_01` @`0x1808F42`
`(3,name,value,file)`;`i2cWriteBuffer_v05_01` @`0x17CF5CA` `(3,name,value,file)`;
`_inforomFsReadFile` @`0x1553F80` `(2,name,value,file)`),且每个名字都出现在其
**同名模块**的代码区(0x14D…vgpu、0x150…nvle、0x155…inforom、0x17C…i2c、
0x180…gpio、0x18B…tdisp)。故判定 log 宏传入 `__func__`。
→ 见"置信度 B"。

### 1.3 函数边界、栈帧、栈布局

```
0x018bbd60  49 71       c.addi16sp sp, -0x170     ; 栈帧 0x170
0x018bbd68  80 1a       c.addi4spn s0, sp, 0x170  ; s0 = sp+0x170
0x018bbd78  97 49 8d 02 auipc    s3, 0x28d4        ; s3 = 0x418FF68 = 栈金丝雀 global
0x018bbd80  03 ba 87 28 ld       s4, 0x288(a5)     ; s4 = *(a1 + 0x2288)  <- 会话/通道指针
0x018bbd8c  23 34 f4 fc sd       a5, -0x38(s0)     ; 金丝雀入栈 (sp+0x138)
...
0x018bbe16  03 37 84 fc ld       a4, -0x38(s0)     ; 金丝雀校验
0x018bbe1e  b9 8f       c.xor    a5, a4
0x018bbe22  95 e7       c.bnez   a5, 0x2c          ; 失败 -> 0x18BBE4E -> 0x1AA340C(收尾)
0x018bbe30  75 61       c.addi16sp sp, 0x170
0x018bbe32  82 80       c.jr     ra
```

| 项 | 值 |
|---|---|
| 入口 VA / 文件偏移 | `0x18BBD60` / `0x8BBD60` |
| 函数体结束(最后一条 `ret`) | `0x18BBE32`;冷路径到 `0x18BBE56`(之后 `0x18BBE58` 是新函数 `c.addi16sp sp,-0x190`) |
| 大小 | 0xF6 B(+冷路径 0x26 B) |
| 栈帧 | `0x170`,金丝雀在 `sp+0x138`(全局 `0x418FF68`) |
| 栈布局 | `sp+0x00`:0x18 B 超时结构(RMTIMEOUT 型,由 `0x1427AEC` 初始化);`sp+0x18`:`resp[0x78]`;`sp+0x90`:`req[0xA4]`;`sp+0x138` 金丝雀;`sp+0x140..0x168` 保存 s4/s3/s2/s1/s0/ra |
| 形参 | `a0` = 通道 ctx(**未使用**),`a1` = 对象指针 pObj(`*(pObj+0x2288)` 取会话) |

**调用边**(基于 `k3_device_work/edges.pkl`):

```
-> 0x1BE41EC   from 0x18bbd9c, 0x18bbdae     ; memset(dst,0,n)  (清 req 0xA4 / resp 0x78)
-> 0x1427AEC   from 0x18bbdcc                ; 超时/上下文初始化 (a0=pObj+0x1D50, a1=&栈上0x18B, 0,0)
-> 0x1B594D0   from 0x18bbde8                ; *** MCTP 报文提交/分发 API(核心) ***
-> 0x1A9E5EC   from 0x18bbe12, 0x18bbe48     ; 结构化日志器
-> 0x1AA340C   from 0x18bbe52                ; 金丝雀失败收尾
```

### 1.4 它是**被间接调用**的处理函数(不是被直接 call)

* `callers of 0x18bbd60 = 0`(全镜像无 `jal/jalr` 直呼)。
* 唯一"取地址"处:`0x18BD0F0`。它位于**独立函数 `0x18BD088`**(序言 `c.addi16sp sp,-0x40`,无直接调用者,
  其自身地址由配置代码 `0x1A0FEC2` 在某个配置位判定后写入 `pObj[+0x100]` 槽 —— RM 风格的方法覆盖/安装)。
  (注:本目录的 `find_va_refs.py` 序言启发式会把 `0x18bd0f0` 归到更外层的 `0x18BCDC0`,实际入口是 `0x18BD088`。)

```
0x018bd0e4  17 37 91 02 auipc    a4, 0x2913 ; addi a4,a4,-0x314   ; a4 = 0x41CFDD0 = 记录表基址(BSS)
0x018bd0ec  17 f6 ff ff auipc    a2, 0xfffff; addi a2,a2,-0x38c   ; a2 = 0x18BBD60 = 本函数
0x018bd0f4  ba 97       c.add    a5, a4                          ; a5 = 表 + idx*0xC0
0x018bd0f6  23 bc 07 08 sd       zero, 0x98(a5)
0x018bd0fa  23 b0 37 0b sd       s3, 0xa0(a5)                    ; 记录[+0xA0] = owner  (注册函数第 1 参)
0x018bd0fe  23 b4 07 0a sd       zero, 0xa8(a5)
0x018bd102  23 b8 57 0b sd       s5, 0xb0(a5)                    ; 记录[+0xB0] = pCtx+0x114 / +0x118
0x018bd106  d0 ff       c.sd    a2, 0xb8(a5)                    ; 记录[+0xB8] = 0x18BBD60
```

* 间接调用点 `0x1B9C71C`(用记录 +4 的"位号"匹配一个 32 位事件掩码后分发):

```
0x01b9c420  83 a7 4d 00 lw       a5, 4(s11)      ; 记录[+4] = bit index
0x01b9c424  bb 97 fe 00 sllw     a5, t4, a5      ; 1 << bit
0x01b9c428  b3 77 f3 00 and      a5, t1, a5      ; 与事件掩码
0x01b9c42c  63 98 07 2e bnez     a5, 0x2f0       ; 命中 -> 0x1B9C71C
...
0x01b9c71c  83 bf 8d 0b ld       t6, 0xb8(s11)   ; handler
0x01b9c724  83 b5 8d 0a ld       a1, 0xa0(s11)   ; owner
0x01b9c728  03 b5 0d 0b ld       a0, 0xb0(s11)   ; pCtx
0x01b9c742  82 9f       c.jalr   t6              ; handler(a0=pCtx, a1=owner)
```

→ 与本函数"只把 `a1` 当 pObj 用、忽略 `a0`"完全吻合。记录表 `0x41CFDD0` 在 RW 段
(`gsp61057_rw_full.bin` 对应偏移全 0 ⇒ BSS,运行期填充)。

---

## 2. 有没有"收报文"路径?先校验还是先拷贝?

### 2.1 本函数(`0x18BBD60`):无长度字段、无报文解析

```
0x018bbd84  13 06 40 0a addi     a2, zero, 0xa4        ; 固定 0xA4
0x018bbd94  13 05 04 f2 addi     a0, s0, -0xe0         ; req = sp+0x90
0x018bbd98  ...         jalr     -> 0x1BE41EC          ; memset(req,0,0xA4)
0x018bbda0  13 06 80 07 addi     a2, zero, 0x78        ; 固定 0x78
0x018bbda6  13 05 84 ea addi     a0, s0, -0x158        ; resp = sp+0x18
0x018bbdaa  ...         jalr     -> 0x1BE41EC          ; memset(resp,0,0x78)
0x018bbdb6  93 07 40 41 addi     a5, zero, 0x414
0x018bbdc4  23 10 f4 f2 sh       a5, -0xe0(s0)         ; req[0..1] = 0x0414  -> msg[0]=0x14
0x018bbde2  26 85       c.mv     a0, s1                ; a0 = pObj
0x018bbde4  ...         jalr     -> 0x1B594D0          ; (pObj, *(pObj+0x2288), req, 0x18B4DDC, resp)
0x018bbdec  01 25       c.addiw  a0, 0
0x018bbdee  39 e1       c.bnez   a0, 0x46              ; 状态!=0 -> 日志(level=2, status)
0x018bbdf0  03 46 84 ea lbu      a2, -0x158(s0)        ; a2 = resp[0]
0x018bbdf4  d1 47       c.li     a5, 0x14
0x018bbdf6  63 00 f6 02 beq      a2, a5, 0x20          ; != 0x14 -> 日志(level=4) 后仍返回 0
```

本函数里**没有任何 `lw/lhu` 自描述符取长度**的指令;所有偏移/长度都是立即数。

### 2.2 提交/分发 API `0x1B594D0`:按**类型**取**常量**长度

```
0x01b594ee  03 48 06 00 lbu      a6, 0(a2)             ; a6 = msg[0] = 类型
0x01b594fc  9b 07 18 ff addiw    a5, a6, -0xf
0x01b59520  63 67 f6 18 bltu     a2(5), a5, 0x18e     ; 类型超出 [0x0f..0x14] -> 错误路径
0x01b59524  ...         auipc/addi a4 = 0x1E1BE30      ; 跳转表(6 项, u32 相对偏移)
0x01b59536  82 87       c.jr     a5
```

per-type 常量长度(跳转表 `0x1E1BE30`,target = `0x1E1BE30 + s32(entry)`):

| msg[0] | case | 目标 | payload 长度 | 目标位置 |
|---|---|---|---|---|
| 0x0F | idx0 | `0x1B595D8` | `0x40` (`0x1B595F6`) | `*(0x41906B0+0xD8)` |
| 0x10 | idx1 | `0x1B5960E` | `0xA0` (`0x1B59630`) | `*(0x41906B0+0xA2)` |
| 0x11 | idx2 | `0x1B5964C` | `0x20` (`0x1B5966C`) | `*(0x41906B0+0x64)` |
| 0x12 | idx3 | `0x1B59684` | `0x44` (`0x1B59696`) | `*(0x41906B0+0x2C)` |
| 0x13 | idx4 | `0x1B596AE` | 不拷贝,直接日志 + 状态 `0x1F`(不支持) | — |
| 0x14 | idx5 | `0x1B59538` | 不拷贝(置状态 5) | — |

拷贝函数是 **`0x1B63B2C` = `portMemCopy` 语义(dst=a0, src=a1, n=a2, 处理重叠)**:

```
0x01b63b32  63 66 b5 00 bltu     a0, a1, 0xc      ; dst<src -> 正向
0x01b63b36  b3 87 c5 00 add      a5, a1, a2
0x01b63b3a  63 6c f5 06 bltu     a0, a5, 0x78     ; 重叠 -> 反向
0x01b63b9c  03 c7 05 00 lbu      a4, 0(a1)        ; 逐字节 src->dst
0x01b63ba4  a3 8f e7 fe sb       a4, -1(a5)
```

case 0 的调用形态(`0x1B595D8`,可见 dst 来自全局、src = `msg+4`):

```
0x01b595d8  17 75 63 02 auipc    a0, 0x2637 ; ld a0, 0xd8(a0)   ; a0 = *(0x41906B0+0xD8)
0x01b595e0  93 85 4b 00 addi     a1, s7, 4                         ; a1 = msg+4
0x01b595f6  13 06 00 04 addi     a2, zero, 0x40                    ; 常量长度
0x01b595fa  ...         jalr     -> 0x1B63B2C                      ; portMemCopy(dst, msg+4, 0x40)
```

### 2.3 回包侧:调用方提供**定长**投递回调

```
0x01b59954  03 36 04 ee ld       a2, -0x120(s0)   ; a2 = 调用方第 5 参(&resp)
0x01b59958  03 35 84 ef ld       a0, -0x108(s0)   ; a0 = pObj
0x01b5995c  83 37 84 ee ld       a5, -0x118(s0)   ; a5 = 调用方第 4 参(0x18B4DDC)
0x01b59960  01 47       c.li     a4, 0
0x01b59962  81 46       c.li     a3, 0
0x01b59964  93 05 04 f1 addi     a1, s0, -0xf0    ; a1 = transport 内部缓冲
0x01b59968  82 97       c.jalr   a5               ; pfn(pObj, pInternalBuf, pDeliverCtx, 0, 0)
```

`0x18B4DDC`(**固定 0x78 字节拷贝**,dst=`a2`,src=`a1`):

```
0x018b4de2  21 c2       c.beqz   a2, 0x40
0x018b4de6  32 85       c.mv     a0, a2           ; dst = a2
...
0x018b4e10  13 07 85 07 addi     a4, a0, 0x78
0x018b4e14  9c 61       c.ld     a5, 0(a1)
0x018b4e1a  23 3c f5 fe sd       a5, -8(a0)       ; 8B/次,共 0x78
0x018b4e1e  e3 1b e5 fe bne      a0, a4, -0xa
```

### 2.4 结论(第 2 问)

* **本层(服务函数 + MCTP 提交/分发)不存在"先按报文长度拷贝、再校验"的结构**:
  入参缓冲 0xA4/0x78、per-type payload 0x40/0xA0/0x20/0x44 全是立即数;
  没有 `lw` 取 length 后驱动拷贝的循环。⇒ **与 `0x1016104` 同型 bug 不在此层**。
* 唯一"信任字段"是回包首字节 `resp[0]`,且校验是**非致命**的(不等只记日志,函数仍 `return 0`)。
* 长度驱动的拷贝在下层:transport 把报文投递到 msgq/device 层
  `0x101671C`(环形队列,`+0x70/+0x74/+0x5C/+0x60` 头尾索引),即已知 `0x1016104`
  (收)那一族函数所在层 —— 若要继续追同型 bug,应从 `0x101671C`/`0x1016104` 往下看。

---

## 3. 有没有"发报文"路径?(可复用的构造+发送入口)

**有。`0x1B594D0`(VA `0x1B594D0` / 文件 `0xB594D0`)就是可直接复用的 MCTP/NVDM 报文
提交 API**;`0x18BBD60` 给出了一个完整调用样例(§2.1)。

推断签名(置信度 B):

```c
NV_STATUS mctpSubmit(pObj      a0,   // 通道对象(本例 = *(owner+0x2288) 的拥有者)
                     pSession  a1,   // 会话/通道指针(本例 = *(pObj+0x2288))
                     pMsg      a2,   // 报文缓冲: [0]=type(0x0F..0x14), payload 自 +4
                     pfnDeliver a3,  // 投递回调,形如 fn(pObj, pInternalBuf, pCtx, 0, 0)
                     pDeliverCtx a4);
```

* **请求结构(本函数构造的 0xA4 字节)**:`+0x00` u16 类型字段 = `0x0414`
  ⇒ `msg[0]=0x14`(type)、`msg[1]=0x04`(子类型/版本);`+0x04` 起 payload;
  transport 按 type 决定从 `msg+4` 拷多少字节(§2.2 表)。
  其余字段本函数未填(全 0)。⇒ MCTP 传输头/NVDM 头(SEID/type/长度)**不在此结构里**,
  应由 transport 或下层自己拼。
* **响应结构(0x78 字节)**:transport 通过调用方给的定长回调把内部缓冲拷回;
  本函数随后只检查 `resp[0] == 0x14`。
* **返回值**:transport 的 NV_STATUS(未支持的类型走 default 返回 `0x1F`,其余为各路径状态码);
  本函数把非 0 当"记录并继续"(不中止、不影响函数自身返回值 0)。
* **可选的注册方式**(若要让自己的处理函数被间接调用):调用函数 `0x18BD088`(其地址被装入
  `pObj[+0x100]`,即它是某对象的方法),它把 `{+0xA0 owner, +0xB0 ctx, +0xB8 handler}` 写入
  `0x41CFDD0 + idx*0xC0`,索引取自 `ctx+0x114` / `ctx+0x118`(`idx <= 1` 有硬检查),
  记录 `+4` 是事件掩码位号。
* 该 API 是共享的:全镜像 **24 个直接调用者**,包括 FSP/MNOC 区(`0x1504F38`、`0x1505BFC`、
  `0x1505DB4`、`0x1505E8C`(=`gspNvleUpdateTopology_GB100` 所在函数)、`0x1508288` 等)、
  tdisp 区(`0x18BBD60` 自身)、以及 `0x133FDBC/0x13DD060/0x13E32D0/0x184FCFC/0x185CBBC/0x1B5C958`。
  说明它就是 GSP-RM 内部通用的报文提交入口,可被复用。

---

## 4. SEID / 端口号 / 来源校验;可疑点

* **本函数没有任何 SEID、port、来源校验**:`0x18BBD60` 与 `0x1B594D0` 全程未出现 MCTP
  dword0 位域(SEID 23:16、SOM/EOM/SEQ)的解析指令,transport 只按 `msg[0]` 分发类型。
* **端口/会话来源** = `*(pObj+0x2288)`(pObj 由间接调用者给出);本例 `a0`(ctx)**完全未使用**。
  → 若调用者能影响 pObj,就能影响会话选择。
* **分发不是按报文的 SEID/port**,而是按**事件位**(记录 `+4`)与某个 32 位掩码的与运算
  (`0x1B9C424`,掩码来自全局),处理函数表 `0x41CFDD0` 是 BSS。⇒ **表/掩码/mask 一旦可写,
  就可能跨通道分发**(未验证可写性,UNKNOWN)。
* **可被"信任"的字段**:`resp[0]`(只做相等比较,不等不报错、不影响返回)、
  `*(pObj+0x2288)`(当指针用,无有效性检查)、transport 回包投递长度(**由调用方自带回调
  决定**;本函数给的是固定 0x78,若换错回调会写错长度)。
* 未见容量/边界比较(len vs 缓冲大小);因其本身不用长度,故"缺边界检查"在这层不构成溢出面。
* 目标缓冲指针来自 RW 段描述符 `0x41906B0`(`+0xD8/0xA2/0x64/0x2C`),该描述符在
  `gsp61057_rw_full.bin` 中为 0 ⇒ BSS/运行期填充,**静态无法确定实际缓冲与容量**。

---

## 5. 置信度与不确定项

**高置信(FACT / A)**
1. 名字字符串 VA `0x1DE6958`、唯一代码引用 `0x18BBE08`、函数入口 `0x18BBD60`、文件偏移 `0x8BBD60`、
   栈帧 `0x170`、金丝雀 `0x418FF68`、函数体 `0x18BBD60..0x18BBE56`。
2. 调用边:`memset 0x1BE41EC`、超时初始化 `0x1427AEC`、`mctpSubmit 0x1B594D0`、
   日志 `0x1A9E5EC`;`0x18BBD60` 无直接调用者,地址在 `0x18BD0F0` 被写入 `0x41CFDD0+idx*0xC0+0xB8`,
   且 `0x1B9C71C` 用 `(entry+0xB0, entry+0xA0)` 间接调用它。
3. transport 的类型表(6 项跳转表 `0x1E1BE30`)与 per-type 常量长度;`portMemCopy = 0x1B63B2C`
   的 `(dst,src,n)` 语义;回包回调 `0x18B4DDC` 为"固定 0x78 字节拷贝"。
4. 该路径无 length-driven 拷贝(负结论,基于指令级全函数检查)。

**中置信(INFERENCE / B)**
5. "log 宏传 `__func__`"⇒ `0x18BBD60` 就是该名字(**主要推断链**;若该宏传的是别的字符串,
   结论会退化为"0x18BBD60 是 `tdispmgr` 里调用该服务的调用者")。旁证:同族调用在 5 个模块
   一致、且名字与所在代码区模块一一对应;但**没有符号表可终局确认**。
6. `0x1B594D0` 的 5 参数语义与"请求/回包"方向(由实参使用点与 0x18B4DDC 的拷贝方向推出);
   类型 0x0F..0x14 的**协议语义**(哪个是 SPDM/TDISP/NVDM 的哪条命令)未定。
7. `0x18BBD60` 是"异步消息服务例程"还是"事件触发后主动发请求的客户端":
   代码形态(构造请求→同步等待回包→校验版本字节)偏向**"事件到达后发同步请求"**;
   真正解析入站报文载荷的是 transport/下层。

**低置信/UNKNOWN(C)**
8. `0x41CFDD0` 记录表的完整语义(仅凭"位号+掩码+handler"推断为事件/中断处理登记表);
   记录 `+0x98/+0xA8` 字段含义未知。
9. `0x41906B0` 描述符各字段指向的实际缓冲与容量(在 BSS,`rw_full.bin` 全 0)。
10. 文件名串(`0x20387EC0`、`0x20387EA8`、`0x1030AD5C` 等)位于 `0x20000000+` 或
    `0x1E9B000..0x20000000`,**不在 `rx_full.bin` 内**,无法读取/交叉验证。
11. 由于 `rx_full.bin` 截断(缺 `0x1E97000..0x1E9B000` 与整个 RW LOAD),
    凡此范围内的常量/表格未核。

---

## 6. 交付物与复跑命令

产物(全部在 `parallel/ds_work/`):

| 文件 | 内容 |
|---|---|
| `mnoc_server.asm` | 目标函数 `0x18BBD60..0x18BBE58` 全反汇编(85 行) |
| `mnoc_server_coldpath.asm` | 冷路径/金丝雀失败 0x18BBE34..0x18BBE58 |
| `mnoc_server_refs.txt` | 函数内所有 auipc 解析结果(canary global、5 个调用目标) |
| `name_refs.txt` | 名字字符串的代码引用点 + 所属函数 |
| `mctp_submit_0x1b594d0.asm` | MCTP 提交/分发 API 0x1B594D0..0x1B59AD0 |
| `copy78_cb_0x18b4ddc.asm` | 回包投递回调(固定 0x78 拷贝) |
| `tdisp_register_0x18bcdc0.asm` | 记录表注册代码所在区域(`0x18BD0F0` 在此;含 `0x18BCDC0` 与 `0x18BD088` 两段) |
| `handler_invoker_0x1b9c680.asm` | 间接分发/调用点(`0x1B9C71C`) |
| `portmemcopy_0x1b63b2c.asm` | `portMemCopy` 语义实证 |
| `callers_mctp_submit.txt` / `callers_mnoc_server.txt` / `callees_mnoc_server.txt` | 调用图 |
| `find_va_refs.py` / `disas_range.py` / `fnfind.py` / `callgraph.py` / `refs_range.py` / `va2off2.py` | 复跑工具 |
| `README_rerun.md` | 复跑命令 |

```bash
cd /home/user/rt_5090_project/parallel/ds_work
python3 find_va_refs.py 0x1de6958            # 名字 -> 唯一引用点 -> 所属函数
python3 disas_range.py 0x18bbd60 0x100 mnoc_server.asm
python3 callgraph.py callees 0x18bbd60 0x18bbe58
python3 callgraph.py callers 0x1b594d0
python3 fnfind.py 0x18bbe08 0x1b594d0        # 函数边界启发式
```

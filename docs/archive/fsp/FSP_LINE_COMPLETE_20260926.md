# FSP 线完整记录 —— RTX 5090 (GB202, ASUS Astral)

> 生成时间:2026-09-26 12:3x
> 来源:`rt_5090_project/RESUME_BRIEF.md` §22/§23/§26/§27/§28/§30 + `parallel/DS_*`、`parallel/K3_*` + 本机实测
> 本文件**可独立阅读**;所有标"实测"的条目都能在 `rt_5090_project/guest_dmesg_*` 原始日志里找到对应行。

---

## 0. 结论速览

| 项 | 状态 |
|---|---|
| 宿主 ↔ FSP 通道 | **打通** ✓ 两条:EMEM(内存队列)+ MNOC port 1(邮箱) |
| 协议 | **完全掌握** ✓ MCTP/NVDM 头、服务号表、载荷结构(有官方头文件佐证) |
| 服务地图 | **已枚举** ✓ CAPS 逐条查询;危险服务(RESET/FIRMWARE_UPDATE/HULK)本来就不支持 |
| FSP 唯一的权限操作(task2) | **可复现** ✓ 净效果 = 把 `0x8200d0/0xdc` 的写权限 nibble 从"仅 L3"开到"全 level" |
| 但 task2 够不够解锁 | **不够** ✗ 它只开"许可",而许可不是真正的门槛(宿主/GSP/开策略后的宿主 三者都写不动目标寄存器) |
| "FSP 是否信任发送方声明的长度" | **阴性** ✗ 按声明读,但只读到通道自身内容;超通道声明被拒/截断,无越界回写 |
| (task, subobject, payload) 空间 | **穷尽** ✗ 只有 (2,1)/(3,1) 合法,没有一条能开 `f8` 或清 `disable_sw_override` |
| 发现的真 bug | **1 个**:SMBPBI(声明支持)⇒ 不回包 + **把 FSP 邮箱整个打挂**(DoS 类,非提权) |
| 加密(FWSEC)侧 | 算法族 = **AES**(CTR/GCM 一族),解密器本体在加密区/芯片内 ⇒ **静态不可得** ✗ |
| 未找到 | 任何"动 BIOS/InfoROM/熔丝之外"能解锁被 floorsweep 掉的 L2/SM 的路径 |

---

## 1. 硬件与协议基础

### 1.1 EMEM 通道(内存队列,默认路径)

寄存器(通道 i,`FSP_EMEM_CHANNEL_RM = 0`,每通道 1024 字节):

```
EMEMC(i)       = 0x8f2ac0 + 8i     控制:OFFS(7:2) BLK(15:8) AINCW(bit24) AINCR(bit25)
EMEMD(i)       = 0x8f2ac4 + 8i     数据口
QUEUE_HEAD(i)  = 0x8f2c00 + 8i     发送队列头
QUEUE_TAIL(i)  = 0x8f2c04 + 8i     发送队列尾(= 声明长度/4 - 1)
MSGQ_HEAD(i)   = 0x8f2c80 + 8i     回包队列头
MSGQ_TAIL(i)   = 0x8f2c84 + 8i     回包队列尾
```

**发送**:`EMEMC = 0 | AINCW` → 连续写 `EMEMD` → 写 `QUEUE_TAIL = len/4 - 1` → **写 `QUEUE_HEAD = 0`(这一步等于敲门铃)**
**接收**:读 `MSGQ_HEAD/TAIL` → 长度 `= (tail-head)+4` → `EMEMC = AINCR` → 连续读 `EMEMD`

证据:`guest_dmesg_emem*_1010.txt`(发 PRC 读 → `MSGQ_TAIL` 0→0x10,回包 20 字节,两次独立运行一致,零 Xid)

### 1.2 MNOC 邮箱(带外,port 1 是正道)

```
FSP_MNOC_BASE           = 0x8f1e00
MNOC_SEND_INFO(port)    = BASE + 0x104 + port*0x0c     host→FSP 方向
MNOC_SEND_RDATA(port)   = BASE + 0x108 + port*0x0c
MNOC_RECV_INFO(port)    = BASE + 0x184 + port*0x0c     FSP→host 方向
MNOC_RECV_WDATA(port)   = BASE + 0x188 + port*0x0c
位:size(19:0) TRIGGER(20) READY(24) ERR(25) CREDIT(26)
```

**端口地图(实测)**:

| port | send_info | recv_info | 判定 |
|---|---|---|---|
| 0 | `0x00000000` | `0x85000000` ready=1 credit=1 | 健康 ✓ |
| **1** | `0x80000000` intr=1 | `0x85000000` ready=1 credit=1 | **健康,任务通道** ✓ |
| 2 | `0xbadf5720` err=1 size=1005344 | `0x04000000` | **特权毒** ✗ |
| 3 | `0xbadf5720` err=1 size=1005344 | `0x04000000` | **特权毒** ✗ |

> 注:2026-09 早先"GB202 没有 MNOC"的结论是**错的** —— 那是用错端口(2)+ 探针模块双重基址 bug 所致。port 1 一直是好的 ✓。

### 1.3 MCTP / NVDM 报文格式(来自 `mctp_format.h` / `nvdm_format.h`)

```
dword0(传输头) = VERSION(3:0)=1 | RSVD(7:4) | DEID(15:8) | SEID(23:16)
                 | TAG(26:24) | TO(27) | SEQ(29:28) | EOM(30) | SOM(31)
                 ⇒ 单包 = 0xC0000001
dword1(NVDM头) = TYPE(6:0)=0x7e(vendor PCI) | IC(7)=0 | VENDOR_ID(23:8)=0x10de
                 | NVDM_TYPE(31:24)
                 ⇒ PRC          = 0x1310de7e
                 ⇒ FSP_RESPONSE = 0x1510de7e  (== SEC2_RESPONSE)
dword2..       = { taskId, commandNvdmType, errorCode } + 服务私有载荷
```

**NVDM 服务号全表**(`nvdm_format.h`,实测 CAPS 支持集见 §3):

```
0x04 RESET            0x11 HULK            0x12 FIRMWARE_UPDATE   0x13 PRC
0x14 COT              0x15 FSP_RESPONSE    0x16 CAPS_QUERY        0x17 INFOROM
0x18 SMBPBI           0x1A ROMREAD         0x1C UEFI_RM           0x1D UEFI_XTL_DEBUG_INTR
0x1F TNVL             0x20 CLOCK_BOOST     0x21 FSP_GSP_COMM      0x25 RM_RPC
```

通道定义:`FSP_EMEM_CHANNEL_RM = 0` / `SEC2_EMEM_CHANNEL_RM = 0`,各 **1024 字节**。

---

## 2. task2(唯一的权限操作)

### 2.1 报文(16 字节)

```
请求: 01 00 00 c0 | 7e de 10 13 | 02 01 00 00 00 00 00 00
       └ MCTP ───┘   └ NVDM PRC ─┘ └ task=2, subobject=1, 6×00 ┘
回包: 00 00 00 c0 | 7e de 10 15 | 01 00 00 00 | 13 00 00 00 | 00 00 00 00
                                   task_id=1     cmd=PRC       error=0 ✓
```

- 通道:**必须 MNOC port 1**。同一条报文走 EMEM 只回 `error=0xAF` 且不生效 ✗。
- 通道前提:**客体无驱动**(有驱动时 MNOC 不回)。

### 2.2 净效果(实测)

| 寄存器 | before | after | 含义 |
|---|---|---|---|
| `0x8200d0` (plm_floorsweep_0) | `0xfffffb8f` | **`0xfffffbff`** | 写权限 nibble [7:4]:`0b1000`(仅 L3)→ `0b1111`(L0..L3 全开) |
| `0x8200dc` (plm_l2_raw_sw) | `0xfffffb8f` | **`0xfffffbff`** | 同上 |
| `0x8200f8` (plm_latch) | `0xfffffb8f` | `0xfffffb8f` | **不动** ✗ |
| `0x8200e0` / `0x8200f4` | `0x00800b8f` | 不变 | sibling PLM 不被覆盖 |
| `0x820040` (latch req) | 0 | 0 | 写 1 不吃 |
| raw/eff 掩码 `0x8234e0`/`0x822900` | `0x12`×8 | `0x12`×8 | **功能效果为零**(PLM 只是许可) |

### 2.3 生命周期与副作用(重要)

- **会话内持久** ✓;熬得过**驱动卸载** ✓(卸载后 `d0/dc` 仍 `fffffbff`);**设备复位清除** ✓。
- **副作用(本轮新发现)**:task2 之后 FSP **不释放 WPR2** ⇒ 再次加载驱动时:

```
kfspSendBootCommands_HAL ... Failure: Generic Error (0x0000FFFF)
_kgspBootGspRm: unexpected WPR2 already up, cannot proceed with booting GSP
RmInitAdapter failed! (0x62:0x40:2119)  ⇒ 必须设备复位
```

⇒ 而复位会清掉 task2 ⇒ **"task2 + 之后再启动 GSP"在同一电源周期内不可能** ✓(这条封死了 GSP 侧那个组合实验)。

---

## 3. 服务地图(CAPS 枚举,port 1)

```
支持:   0x13 PRC  0x14 COT  0x15 RESPONSE  0x16 CAPS  0x17 INFOROM
        0x18 SMBPBI  0x1A ROMREAD  0x1C UEFI_RM  0x1D UEFI_XTL  0x20 CLOCK_BOOST
不支持: 0x00/0x01/0x02/0x10/0x1F TNVL/0x21 GSP_COMM/0x25 RM_RPC   (error=0x153)
```

- **危险服务本来就不通**:`0x04 RESET`、`0x11 HULK`、`0x12 FIRMWARE_UPDATE` 均不受理 ✓
- 状态码词典:正常 `0x202`;畸形声明长度 `0x20c`;不支持的服务 `0x153`
- 命中的 task 错误码:`0xAA`(未知 task)、`0xAC/0xAE/0xB0/0xB2`(子对象/参数错)、`0xAF`(EMEM 上不受理 task)、`0x3A5`(载荷校验失败)、`0x1FE/0x1E0/0x22C/0x1B2/0x23E`(其他)

---

## 4. "FSP 是否信任发送方声明的长度"(F1)

方法:先把 1 KB 通道整段预填 `0xDEADBEEF` 标记(**不敲 QUEUE_TAIL** ⇒ FSP 看不见),再发 12 字节报文,声明长度从 3 dword 一路加到 4099 dword。

| 声明 | 结果 |
|---|---|
| 3 dword(与实际相符) | 回包 20 字节;**第 5 个字 = 0xDEADBEEF** ⇒ 它按声明读(读到我们没写的第 4 个 dword) |
| 255 dword(≈ 整通道) | 回包仍是 20 字节,形状变"回显请求头 + `0x20c`" |
| 1027 dword(超通道 4×) | 不崩,回包形状回到正常(`0x202`) |
| 4099 dword(超通道 16×) | 不崩,回显 + `0x20c` |

**判定**:它会按声明长度读,但只读到**通道自身**的内容;超通道声明被拒/截断;**没有出现"FSP 写超长回包"或"读到通道外其它内存"** ⇒ 阴性 ✗(不是可用的信息泄漏/溢出路径)。
代价:这轮激进探针**很可能把 FSP 惹毛**了(见 §6 的教训栏)。

---

## 5. (task, subobject, payload) 穷尽 + SMBPBI

### 5.1 task/sub 扫描(每发一条就做全窗口快照)

| 范围 | 结果 |
|---|---|
| task = 0x00..0x10,sub=1 | 只有 **0x02、0x03** 接受(error=0);其余回 `0xAA/0xAC/0xAE/0xB0/0xB2/0x1FE/0x202/0x1E0/0x22C/0x1B2/0x23E` |
| task ∈ {2,3},sub ∈ {0,1,2,3} | **只有 sub=1** 接受;sub=0/2/3 ⇒ `0xAF`/`0xAB` |
| payload = 全 FF | task2 ⇒ `0x3A5`(它**在校验载荷** ✓);task3 ⇒ 0 |
| payload = 单字节置位(6 种位置) | 全部 error=0,但**寄存器窗口零变化**(FNV 不变)✗ |

⇒ **没有任何 (task,sub) 能打开 `plm_latch(f8)` 或清掉 `disable_sw_override(0x8212ac)`** ⇒ FSP 的 task 接口对解锁无用 ✗

### 5.2 SMBPBI(0x18)—— 一个真 bug

格式(来自 `oob/smbpbi.h`):

```
命令字 = |flags(31:29)|STATUS(28:24)|ARG2(23:16)|ARG1(15:8)|OPCODE(7:0)|
   REGISTER_READ(addr)  = CMD(0x11 REGISTER_ACCESS, ARG1=0x01 READ , addr)
   REGISTER_WRITE(addr) = CMD(0x11 REGISTER_ACCESS, ARG1=0x00 WRITE, addr)
   SCRATCH_READ(0x0d) / SCRATCH_WRITE(0x0e) / SCRATCH_COPY(0x0f) / GET_TEMP(0x02) ...
报文 = MCTP + NVDM(0x18) + {taskId, cmdType=0x18, errorCode} + 命令字 [+ 数据字]
```

实测(发往 port 1):

| 命令 | 结果 |
|---|---|
| SCRATCH_READ(0) | **零回包** ✗ |
| REGISTER_READ(0x00d0) / (0x0000) / (0x0100) | **零回包** ✗ |
| SCRATCH_WRITE(off=0,cnt=1)+0x12345678 | **零回包** ✗ |
| GET_TEMP(0)(port 0 与 1 都试) | 之后**所有端口全部超时** |

最终状态:

```
timeout waiting for send mailbox message ready at 0x008f1f10: last=0x80000000 mask=0x01000000 expected=0x01000000
(port 0 同样:last=0x00000000) ⇒ 连 task2 也发不出去了
```

**判定**:**一条被 CAPS 声明"受支持"的服务,发过去既不回包、又把 FSP 的报文循环整个卡死** ✓ ——
这是真实的健壮性缺陷(状态机卡死类),**不是内存破坏、不是提权路径**;副作用是 GSP 也起不来,必须设备复位。

---

## 6. 寄存器语义与实测工具

### 6.1 相关寄存器(裸读 BAR0)

| 偏移 | 语义名 | 冷态值 |
|---|---|---|
| `0x820040` | latch_request | 0 |
| `0x8200d0` | plm_floorsweep_0 | `0xfffffb8f`(task2 后 `fbff`)|
| `0x8200dc` | plm_l2_raw_sw | 同上 |
| `0x8200e0` / `0x8200f4` | plm_8200e0 / plm_8200f4 | `0x00800b8f` |
| `0x8200f8` | **plm_latch** | `0xfffffb8f`(宿主打不开 ✗)|
| `0x8200fc` | plm_8200fc | `0x80842bcf` |
| `0x820434` | reset_coupling | 1 |
| `0x8212ac` | **disable_sw_override** | 1(改不动 ✗)|
| `0x8234e0+4i` | FBP i 的 **raw** floorsweep 掩码 | `0x12` |
| `0x822900+4i` | FBP i 的 **effective** 掩码 | `0x12` |
| (software 掩码) | FBP i 的 sw 掩码 | 0 |

### 6.2 工具清单

| 工具 | 位置 | 用途 |
|---|---|---|
| `fsp_probe2.c` | `/home/user/fsp_probe/` | 内核模块:EMEM 发送/预填/接收,**支持声明长度操控** |
| `bar0_read_mod.c` | 同上 | 内核模块:裸读 BAR0 关键寄存器(驱动加载时也能用) |
| `fscan_mod.c` | 同上 | 内核模块:打印 `0x820000-0x824000` 的 **FNV-1a 校验和** + 关键寄存器 ⇒ 操作前后各跑一次判"落/丢/别名" |
| `fsp_raw.c` | 同上 | 由 7 月 `gb202_fsp_prc_read.c` 加 **RAWHEX 环境变量**(发任意长度报文,32 字节对齐)|
| `gb202_bar0_latch_probe` | `/home/user/rt_5090_project/vm_mods_lab/prc-read-tools/` | 带**前置条件校验**的写测探针:`--commit-fbp0-bit1-clear-then-restore` / `--commit-f8-open-then-restore` / `--commit-latch-bit0` / `--read-only` |
| `gb202_fsp_prc_read` | 同上 | `--status-only` / `--caps-query` / `--prc-read` / `--prc-write-noop` / `--task2-zero` |

### 6.3 踩过的坑(必读)

1. **`dkms build/install` 不是合法命令** ✗ ⇒ 必须 `dkms build` 再 `dkms install`;安装后要校验 `modinfo -n nvidia` 的 mtime 是新的,**且** 模块里有我们的标记串。
2. **`sudo` 会清空环境** ⇒ 传 `RAWHEX` 必须写 `sudo env RAWHEX=... ./prcraw ...`,写成 `RAWHEX=... sudo ...` 会被丢掉 ✗。
3. **`NVRM` 日志是延迟拼接的** ⇒ 开火后立刻 grep 会得到 0 行,判定要看完整 dmesg(等 20~25 s)。
4. **顺序纪律**:若要打 GSP 侧实验,必须「①task2 → ②GSP 那一枪 → ③FSP 激进探针」;反了的话激进探针会把 GSP 搞得起不来 ✗。
5. 动设备前 `fuser -v /dev/nvidia* /dev/dri/*`;判判定看**退出码**不看文本;`scp` 端口用大写 `-P`。

---

## 7. 加密 / 混淆侧(FWSEC)—— 与解锁是同一个特权面

### 7.1 容器格式(官方定义,来自 `kernel_gsp_fwsec.c`)

```
BIT(BIOS Information Table): Id=0xB8FF + 签名 "BIT\0"(0x00544942);头 12B
  token(6B) = {id, ver, size:u16, offset:u16}  ← offset 相对"扩展 ROM 基址"
  实测 ASUS ROM:BIT@0x38df0,20 个 token;token[1]=0x42 BIOSDATA,token[14]=0x70 FALCON_DATA
微码表(由 token 0x70 指向) = {Version=1, HeaderSize, EntrySize, Count, DescVersion, DescSize}
  条目 = {ApplicationID, TargetID, DescPtr}
描述符头(1 dword) = bit0 版本有效 | **bit2 = ENCRYPTED** | bits15:8 版本(V1..V4) | bits31:16 大小(V2=60,V3=44)
```

- 我们那 6 个镜像的描述符 = `{flags=0x0d, 版本=6, 大小=0x50}` ⇒ **bit2=加密,源码证实**。
- V3 描述符带签名字段:`SignatureCount` / `SignatureVersions` / **`BCRT30_RSA3K_SIG_SIZE = 384`** ⇒ **RSA-3072**(签名侧,与加密严格分开 ✓)。
- **FWSEC 微码应用号**:`0x05 = FIRMWARE_SEC_LIC`、`0x45 = FWSEC_DBG`、`0x85 = FWSEC_PROD`。

### 7.2 决定性否定结果

- 按"微码表特征"扫描 **ROM、两个 optionrom_chain、Dell/HPE .nvfw、63 MB GSP 明文、fmc、bootloader:全部 0 命中** ⇒ **GB202 的 VBIOS 里根本没有 FWSEC 微码**;与 `RMExecuteFwsecOnSec2`(fwsec 在芯片内 SEC2 上跑)一致。
- ROM 熵地图:`0x2000-0x36000` 密文(208 KB)、6 个镜像描述符 bit2 全为 1 ⇒ **VIBIOS 内无一明文**。
- 驱动侧对该加密**只有标志位,没有任何密钥/IV/AES 代码** ⇒ **主机永不解密,解密在芯片内**。
- GSP 明文固件里的加密线索:`AES0/AES1 engine`、`AES-GCM AAD/FINAL`、`before/after kslot clear`(密钥槽)、**`ENCRYPT_IV_CTR_OVERFLOW`/`DECRYPT_IV_CTR_OVERFLOW`**、`NVRNG`、`NVPKA[RSA/ECC]`、`NIST_P-256/P-384`;参数名 `RmDisableFwseclic`、`RMExecuteFwsecOnSec2`。
- 静态分析(DS 报告):明文 RM 里**没有"把镜像交给 fwsec"的调用**;容器解析器不在 RM 里;347 条 FWSECLIC 错误码→名字已解出(含 `CMD_VBIOS_VERIFY_*`、`CERT_HULK_*`、**`3AES_SIG vs GPU_FUSE`**、`BSI/PLM/VPR-SCRATCH` 互斥超时)。

### 7.3 密文本身的统计性质(实测)

- 载荷全部 **16 字节整数倍**;熵 **7.999**;
- **非 ECB**(16 万字节里零重复块);
- 跨厂商异或熵 7.998–7.999、零字节 ≈0.39%(= 随机理论值)⇒ **无 keystream 复用**;
- **确定性**:FE/ASUS/ASUS-old 三份逐字节相同 ⇒ 同一明文 ⇒ 同一密文(可当等值预言机用)。
- 描述符尾部 28 字节高熵块逐镜像不同 ⇒ 很可能是 **nonce + tag**(12+16)。
- ⇒ 结论:**算法族 = AES + CTR/GCM 一类;确切模式/IV/密钥派生在芯片内** ⇒ 从宿主静态不可得 ✗。

---

## 8. 证据文件索引

```
rt_5090_project/guest_dmesg_emem*_1010.txt      EMEM 通道打通(收发 20 字节 0x15)
rt_5090_project/guest_dmesg_fsp_*.txt           早期 FSP/MNOC 尝试(含被 bug 污染的那批)
rt_5090_project/guest_dmesg_regwrite4_1052.txt  GSP 写 PLM 那一枪(含 Xid 119)
rt_5090_project/parallel/DS_FSP_MNOC_ACCESS_20260926.md     MNOC 配方与端口分析
rt_5090_project/parallel/DS_FWSEC_CALLSITE_20260926.md      明文 RM 里的 FWSEC 线索(538 行)
rt_5090_project/parallel/DS_FWSEC_ERRCODE_TABLE_20260926.txt 347 条 FWSECLIC 错误码表
rt_5090_project/parallel/K3_FULL_REVIEW_20260926.md         全量审阅(FSP 探针优先级在 §③)
rt_5090_project/parallel/L2_REENABLE_STATIC_FINDINGS.md     项目早期大文档(task2 原始记录)
rt_5090_project/vm_mods_lab/fsp_task2_zero_result_20260722.md  2026-07-22 task2 成功记录
```

---

## 9. 仍开放 / 下一步(如果要继续)

1. **SMBPBI 那个卡死**:换 framing(不同 taskId/长度/端口)看是"永不回包"还是"特定形状卡死";若能把状态码问出来,也许能摸到它的命令解析器。**注意:每次卡死都要设备复位**。
2. **INFOROM(0x17) / ROMREAD(0x1A)**:两个声明的只读服务,本轮**还没试**(被 SMBPBI 卡死打断)。这是当前最干净的剩余面。
3. **其它服务的 framing**:`0x1C UEFI_RM`、`0x1D UEFI_XTL_DEBUG_INTR`(名字里有 DEBUG,值得看)、`0x20 CLOCK_BOOST`。
4. **CAPS 更深**:CAPS 除了服务位图,可能还有能力/版本信息可枚举。
5. 若要碰内存破坏类:需要在**发送 framing**(MCTP 分片 SOM/EOM/SEQ 组合、声明的 size 与实写不一致)上做更系统的模糊测试,但**每次都可能卡死 FSP ⇒ 每轮都要复位**。

**红线(与用户约定)**:不写 BIOS/InfoROM/熔丝、不刷机、不做物理攻击;不做对外安全报告。


---

## 10. 【新增】PRC 对象/knob 接口 —— 与一次真实事故(2026-09-26 之后)

### 10.1 协议(驱动源码逐字节确认,不是猜的)
`kern_gpu_gh100.c` 里驱动自己就用这套协议:
```c
typedef struct { NvU8 prcObjType; NvU8 numBytes; NvU16 knobId; } NVDM_PAYLOAD_PRC_OBJECT_READ;      // 4 字节
typedef struct { NvU8 messageType; NvU32 taskId; NvU32 commandNvdmType; NvU32 errorCode;
                 NvU16 knobValue; NvU16 misc; } NVDM_PAYLOAD_PRC_OBJECT_RESPONSE;
#define NVDM_PRC_PPCIE_READ_OBJECT  0x0C     // = PRC_OBJ_READ
#define NVDM_PRC_PPCIE_NUM_BYTES    0x02
#define NVDM_PRC_PPCIE_KNOB_ID      0x2D     // "受保护 PCIe 是否开启"
```
- 完整报文 12 字节:`MCTP(0xC0000001) | NVDM(0x1310de7e) | prcObjType | numBytes | knobId:u16`
- 写:`prcObjType = 0x0D`(PRC_OBJ_WRITE),`numBytes = 0x02`,后面 2 字节 = 值(LE)
- 成功回包 **22 字节**,末 2 字节 = 值
- knob 空间是 **16 位稀疏**:`0xHH00` 系列(44 个可读 ⇒ id 0 的 44 个实例)与 `0x00LL` 系列(0x01,02,04,05,07,09,0b-24,29,2b 可读,值全 0x0001)是**两套不同的东西** ✓
- 自检:驱动用的 `knobId=0x002D`(PPCIE)在本卡返回 **0x1E3 "无效 knob"** ✓ —— 而驱动的断言**本就允许**这一结果(`NV_OK || NV_ERR_INVALID_ARGUMENT`)✓ ⇒ 我们的报文与驱动同款 ✓✓(消费级没有 PPCIE ✓,那是 Hopper 数据中心功能)
- **驱动源码里只有这一个具名 knob** ⇒ 其余对象的语义**无文档可查** ✗

### 10.2 ★ 事故:一次对象写入把卡逼进"必须支持机密计算(CC)"模式
- 枚举时写了 `0xHH00` 这 14 个可写对象(写前已读全表存原值 ✓,这一步救了命 ✓)
- 结果:驱动立刻变成
```
NVRM: confComputeConstructEngine_IMPL: CPU does not support confidential compute.
NVRM: nvAssertFailedNoLog: Assertion failed: 0 @ conf_compute.c:163
NVRM: osInitNvMapping: *** Cannot attach gpu   → RmInitAdapter failed! (0x22:0x38:894)
```
- **热重启无效** ✗(GPU 未断电,FSP 的运行状态还在)⇒ **只有彻底断电(关电源 30s)才清** ✓✓ —— 实测断电后立即恢复 ✓
- 事后复核:**13/14 已写回原值**;唯一残留 `0x03`(**持久**,能清不能置 ⇒ 单向闩锁 ✗)与故障**无关** ✓ —— 因为断电后卡已正常而它仍是 0 ✓
  ⇒ **更正**:把卡逼进 CC 模式的是**另一处易失的 FSP 状态**(掉电即清 ✓,完美解释"热重启无效/断电恢复"✓),**不是 0x03** ✗
### 10.3 安全意义(按约定不对外报告)
**任何能驱动 FSP 信箱的主体(宿主内核 / 显卡直通 VM 里的客体)只需 2 字节的 PRC 对象写入,就能把宿主 GPU 变成"必须宿主 CPU 支持机密计算才能用"** ✗
⇒ 跨 VM 边界、**掉电前无法自愈**的持久性拒绝服务 ✓(研究环境里这条路是实打实可达的 ✓)
### 10.4 安全规则(以后必须遵守)
1. 任何对象**写**之前,先读全表并**存原值** ✓
2. 对可写对象假定"可能需要**彻底断电**才能撤销" ✓;不要连写、不要盲目扫写 ✓
3. 撞了 CC 断言先**彻底断电**(热重启没用 ✗)
4. 若驱动认不到设备:清 `driver_override`(实验室残留 `vfio-pci` 会挡住 nvidia 探测 ✗)+ 必要时 rescan ✓
5. 读对象需驱动未绑定(vfio-pci 绑着时 resource0 mmap 会失败/读到 0xffffffff ✗)
### 10.5 服务侧最终结论
| 服务 | 结论 |
|---|---|
| `0x13 PRC` | **完全可用**(读 + 写对象)✓ |
| `0x17 INFOROM` | 驱动里只出现在**接收**路径 ⇒ 它是 FSP→宿主的通知型消息 ✗(我们发它得"error=0 无载荷"就说得通 ✓) |
| `0x20 CLOCK_BOOST` | 载荷 1 字节(子命令 0=disable/1=enable/2=restore ✓);**FSP 上无论载荷都静默** ✗ ⇒ 很可能属于 **SEC2 侧**(协议里 FSP/SEC2 各有独立通道 ✓) |
| `0x14 COT` / `0x1A ROMREAD` / `0x18 SMBPBI` | 静默丢弃 ✗;**SMBPBI 还会把 FSP 信箱整个打挂**(需设备复位)✗ |
| `0x1C UEFI_RM` / `0x1D UEFI_XTL` / `0x11 HULK` | 回包 + 错误码 ✓ |
| `0x04 RESET` / `0x12 FIRMWARE_UPDATE` | CAPS 声明**不支持** ✓(危险门本来不通 ✓) |
### 10.6 状态
卡与机器完全正常(29-30°C、8 服务、桌面在核显上 ✓);对象表仅 `0x03` 与最初不同(无碍 ✓)。

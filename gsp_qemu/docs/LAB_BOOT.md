# `nvidia-gsp-lab` 原始 LibOS walk 表发布检查点

## 结论

在纯 QEMU TCG 中，未修改的 GB202 610.57.04 生产 LibOS 已执行到：

```text
pc = 0xffffffff93007324     # sd s7, 0x450(s0)
global = 0xffffffffa3013030
[global + 0x450] = 0x800000000803a000
```

`0xffffffff93007324` 是任务卡指定的 walk 表发布指令。断点执行前后回读：

```text
WALK_WRITE_BEFORE global=0xffffffffa3013030 table=0x800000000803a000
WALK_WRITE_AFTER  global=0xffffffffa3013030 stored=0x800000000803a000
```

同一路径还观察到第二个对象：

```text
global = 0xffffffffa30134d0
[global + 0x450] = 0x8000000008046000
```

并且 walk 表内容可读且跨运行稳定。第一次 `sd s7,0x450(s0)` 时表还是 free-list；继续到第二次发布后，同一个表已经填充出有效项：

```text
table VA  = 0x800000000803a000
table PA  = 0x740000000803a000   (MPU slot 0: 0x8000000000000000 -> FB_BASE)
size      = 4096 bytes

initial   sha256 = 98dbb968929aded4b23a8a020cb58a5840184d181db32e03b45a5f71d5df50d6
          header = 0xb, 0x80, 0x2
          free   = 116 entries, 0xc..0x7f

populated sha256 = 6f1efbdd5c9f877767d261eaee3398d19978d5f70a0614a827a56279df3c339d
          header = 0xe, 0x80, 0x1
```

populated 表的有效项（`meta` bit63=1）：

```text
idx 0x01: obj=0x8000000008028088 meta=0x8000000000000001
idx 0x08: obj=0xffffffffa300f030 meta=0x8000000000000001
idx 0x09: obj=0xffffffffa3015060 meta=0x8000000000000002
idx 0x0b: obj=0x800000000802a0d8 meta=0x8000000000000001
idx 0x0c: obj=0xffffffffa3015090 meta=0x8000000000000000
idx 0x0d: obj=0xffffffffa3015030 meta=0x8000000000000002
```

布局与 `0x9300a090` 的 lookup 一致：

```text
entry = table + (idx + 1) * 16
obj   = [entry + 8]
meta  = [entry + 16]      # 下一个 entry 的 field0
有效项要求 meta bit63 = 1；否则返回 0
```

因此第一次 dump 的“全 0 meta”不是字段偏移错误，而是 **snapshot 太早**：free-list 还未转换成有效项。第二次发布的 populated 表已经满足 lookup 的有效性条件。

第二个 global `0xffffffffa30134d0` 的 `[+0x450]` 是更大的表：

```text
table VA  = 0x8000000008046000
table PA  = 0x7400000008046000
size      = 0x20000 (count=0x2000 slots)
header    = 0xd, 0x2000, 0x1

idx 0x01: obj=0x8000000008028030 meta=0x8000000000000001
idx 0x08: obj=0xffffffffa300f030 meta=0x8000000000000001
idx 0x09: obj=0xffffffffa3015060 meta=0x8000000000000002
idx 0x0b: obj=0x800000000802a0f0 meta=0x8000000000000001
idx 0x0c: obj=0xffffffffa3015060 meta=0x8000000000000003
```

同一对象 `0xffffffffa3015060` 可以以不同 meta 低两位（type/flags）出现在不同 slot；`meta` 的 bit63 是有效位，低位是类型/权限。表不是单一页表：`count` 可以是 `0x80` 或 `0x2000`，条目布局一致。

这是 **QEMU 功能 profile 的真实指令执行检查点**，不是芯片熔丝/BOOTROM 认证、FSP 启动或完整 GSP-RM 启动的证明。

## 可重复命令

```sh
cd /home/user/rt_5090_project/gsp_qemu
make build
make test-lab
```

脚本：`scripts/test-lab-walk.sh`，日志：`logs/lab-walk.gdb.log`、`logs/lab-walk.qemu.log`。

完整 lab 启动命令：

```sh
build/qemu-system-riscv64 \
  -M nvidia-gsp-lab,\
bootstrap=firmware/gsp-bootstrap-610.57.04.bin,\
libos=firmware/kernel-610.57.04/kernel-load-segments.elf,\
image=firmware/gsp-fwimage-610.57.04.bin,\
fmc=firmware/610.57.04/nvidia/gb202/gsp/fmc-610.57.04.bin,\
bootloader=firmware/610.57.04/nvidia/gb202/gsp/bootloader-610.57.04.bin \
  -m 32M -display none -serial none -monitor none -nic none -S \
  -gdb unix:/tmp/gsp.sock,server=on,wait=off
```

## 本轮新增的真实行为

### 1. FMC 签名验证 → Booter 建模

`nvidia-gsp-lab` 现在要求并提供：

- `fmc=` 生产 `fmc-610.57.04.bin`
- `bootloader=` 生产 `bootloader-610.57.04.bin`
- 默认生产信任锚 `af870e5d...ba39`

启动时执行：

1. `nv_gsp_parse_gfw()` 解析 ELF32 GFW 容器；
2. `nv_gsp_verify_gfw()` 实际做 SHA384 + ECDSA-P384 验证，并核对固定公钥；
3. `nv_gsp_parse_boot_image()` 解析 FMC 包；
4. `nv_gsp_match_boot_images()` 逐字节比对 GFW code/data/manifest 与 BootROM 输入包；
5. 只有以上全部通过，才设置 `GspFwWprMeta.verified = 0xa0a0a0a0a0a0a0a0`。

日志：

```text
nv-gsp-lab: BOOTER_SIGNED_PACKET_VERIFIED P384/SHA384 gfw=287304 bootloader=290816 gspfw=84258816 manifest=2560 code=225280 data=59392
```

这仍然是 **Booter 行为模型**：没有声称完成片上熔丝策略、BootROM 解密或 ACR 认证。

### 2. WPR 元数据与堆区域

`init.elf` 在 `0x10048ee` 读取并校验：

- `meta->magic == 0xdc3aae21371a60b3`
- `meta->revision == 1`
- `meta->verified == 0xa0a0...`

通过后，它用 meta 字段构建 12 项区域表，并检查区域是否落在 WPR 内、是否重叠。第一版模型把 heap 写成 `[0x801000, 0x10000000)`，与 GSP FW image `[0x1000000, ...)` 重叠，导致 `0x1004b0e` 检查失败。修正为：

```text
WPR heap = [FB + 0x801000, FB + 0x1000000)
GSP FW   = [FB + 0x1000000, FB + 0x605b000)
boot bin = [FB + 0x605b000, FB + 0x60a2000)
```

`init.elf` 的区域表检查通过，并将 `[global+0x450]` 等关系继续传递。

### 3. init args 页

`init.elf` 在 `0x1004c90` 映射 `LibosMemoryRegionInitArgument[0]`：

```text
id8 = 2
pa  = FB + 0x801000
size= 0x7ff000
kind= 1 (CONTIGUOUS)
loc = 2 (FB)
```

该页实际由 `FB + 0x7003000` 支撑；lab 在 native platform constructor 之后同时更新：

- `SYS_BASE + 0x1000 + 0x160`
- `FB + PLATFORM_OFFSET + 0x160`

映射返回 `a0=0`，init 继续执行。

### 4. walk 表发布

随后原始内核执行到：

```text
0xffffffff93007324: sd s7,0x450(s0)
```

`scripts/test-lab-walk.sh` 用硬件断点在该指令前后检查：

- `s7 != 0`
- `s7` 的 bit63 置位（handle/内核对象空间）
- `[s0+0x450] == s7`
- 通过 MPU slot 0 的 FB 别名回读 4096 字节表；第一次发布先记录 free-list，第二次发布再记录 populated 表；检查 `meta bit63=1` 的有效项和稳定 SHA256

当前稳定结果：

```text
global=0xffffffffa3013030 -> 0x800000000803a000
global=0xffffffffa30134d0 -> 0x8000000008046000
```

## 与真机布局的差异

本 lab 是 256MB FB 的 **功能 profile**，不是真机 32GB FB 布局：

| 项目 | 本 lab | 真机参考 |
|---|---|---|
| FB | 256MB | 32GB |
| WPR start | FB + 0x800000 | ≈0x7E6A8000 |
| GSP heap | 8MB | 135MB |
| non-WPR heap | 0 | 3MB |
| FRTS | 0 | 1MB |
| GSP FW image | FB + 0x1000000 | ≈0x7F0A8000 |

因此 lab 的 `global` 是解析后的 VA，不是真机的 `0x0303000000307c70` handle；walk 表地址 `0x800000000803a000` 是当前 profile 的真实分配结果。真机探针应使用真机 walk 表地址，而不是这个 profile 地址。

## GLM 假设的 lab 验证（2026-10-18）

GLM 的局部结论在 QEMU 中部分确认、部分不成立：

确认：

- `0x9300a090` 的 lookup 布局正确：`entry=tbl+(idx+1)*16`、`obj=[entry+8]`、`meta=[entry+16]`、有效项 `meta bit63=1`。
- 第一次 `sd s7,0x450(s0)` 是 free-list；第二次发布后表已填充。t1/t2 的 populated 结果见上。
- walk 实际被调用（`0x9300a090`），返回的 stripped meta 为 `0/1/2/3`；调用点包括 `0x93007226` 等，`0x93004568`（TYPECALC）确实在 obj 上执行。
- `0x93005b26`（release）被大量调用；tab.obj 包含 `a3015060`、`a3014138`、`800000000802a198` 等。

未确认：

- “`meta & 0xC == 0xC` 是进入 TYPECALC/release 的必要条件”在本 lab 的首批路径中 **不成立**：TYPECALC 对 meta=0/1/2/3 的对象都执行；`0x93000900` 这个 gate 断点在观察窗口内一次也没有命中。
- 把 t1 首项 meta 从 `0x8000000000000001` 改成 `0x800000000000000D` 后，观察窗口内 release/TYPECALC 行为没有可见变化，`0x93000900` 仍未命中。
- “handle 0x0303000000307c70 的 slot 263 属于大表”尚未在 lab 中证实：`0x80/0x2000` 是 `0x9300a090` 使用的对象 slot 表；`0x93005096` 的 9-bit handle resolver 使用哪张表/哪个 base 还没有定位。`0x93005096` 的反汇编只给出了 slot 计算，没有给出表 base 的来源。

待 GLM 补充：

1. `0x93005E94` 完整函数和 `a3` 参数来源（决定每种对象类型写入的 meta 位模式）。
2. `0x93005096` 的调用者/表 base：9-bit slot 表实例在哪里，如何与 `0x80/0x2000` 对象表区分。
3. `0x93000900` gate 的具体调用路径：它属于 `SYSCALL t0=4` 的哪类对象？本 lab 的 TYPECALC/release 是否走了另一条路？
4. 一个真实 handle → resolver 表 → entry 的样例，或 9-bit 表项格式。

供 GLM 使用的新数据：

```text
t1 = 0x800000000803a000 (PA 0x740000000803a000), count 0x80
  populated header = 0xe,0x80,0x1
  idx 1  obj=8000000008028088 meta=8000000000000001
  idx 8  obj=ffffffffa300f030 meta=8000000000000001
  idx 9  obj=ffffffffa3015060 meta=8000000000000002
  idx b  obj=800000000802a0d8 meta=8000000000000001
  idx c  obj=ffffffffa3015090 meta=8000000000000000
  idx d  obj=ffffffffa3015030 meta=8000000000000002

t2 = 0x8000000008046000 (PA 0x7400000008046000), count 0x2000
  populated header = 0xd,0x2000,0x1
  idx 1  obj=8000000008028030 meta=8000000000000001
  idx 8  obj=ffffffffa300f030 meta=8000000000000001
  idx 9  obj=ffffffffa3015060 meta=8000000000000002
  idx b  obj=800000000802a0f0 meta=8000000000000001
  idx c  obj=ffffffffa3015060 meta=8000000000000003

walk returns observed: meta=0,1,2,3 (stripped)
0x93000900 gate hits in observed window: 0
0x93005b26 release hits: many (a3015060, a3014138, a3014030, ...)
```


### `0x93005096` handle resolver 的首次实测

lab 首次命中：

```text
raw      = 0x400000
table    = 0x8000000008045000   (PA 0x7400000008045000)
out      = 0xffffffffa3007d08
slot     = (raw >> 12) & 0x1FF = 0
table[0] = 0x740000000804308c
table[263] = 0
```

确认：

- `(raw >> 12) & 0x1FF` 和 8 字节表项成立；
- 表是 512 项的 **handle/page 表**，表项是 `物理页基址 | flags`（`0x...308c` 的低位是 flags）；
- 这张表与 `0x80/0x2000` 的 object slot 表是不同对象；
- 该实例的 slot 263 为空，所以真机 handle `0x0303000000307c70` 的 slot 263 需要另一张表实例（不同 address space/对象池）。

这修正了“slot 263 属于 0x2000 object table”的推断：slot 263 属于 512 项 handle 表；只是当前实例未映射 263。


### 修正：`0x93005E94` / `0x93005C6C` 不是 meta 写入者

lab 实测：

```text
0x93005E94 a3 = 0x1000000, 0x800000, 0x4000   # 区域 size
0x93005C6C 是区域分配器：读 a1+40/48/56，拆分/占用 [a2, a2+a3)
```

真正的 meta 写入在 `0x93005934`（`sd a3,16(a5)`），其 wrapper 是
`0x9300581e`。观察到的调用点与 raw meta：

```text
0x93007406: a3=1 -> meta 0x8000000000000001, slot 0xb
0x930074aa: a3=1 -> meta 0x8000000000000001, slot 0x1
0x93002d1c: a3=0 -> meta 0x8000000000000000, slot 0xc
0x93002db0: a3=2 -> meta 0x8000000000000002, slot 0xd
```

因此 `meta` 低两位来自**调用者传给 `0x9300581e` 的 a3 类型/标志**，
不是区域 size，也不是 `0x93005E94` 的 a3。`0x93005E94` 的 a3
是区域大小，`0x93005C6C` 负责区域分配，不负责对象表 meta。

t2 的 `idx 0xc: obj=a3015060 meta=...0003` 对应一个 a3=3 的
注册调用；具体调用点可继续从 0x930074xx 区间确认。


### wrapper `0x9300581e` 的完整类型样本

`0x9300581e` 接收 `a3` 类型，最终在 `0x93005934` 写入
`meta = 0x8000000000000000 | a3`。lab 观察到的调用点：

```text
type 0: ra=0x93002d20  global=a3013030 obj=a3015090
type 1: ra=0x93007406  global=a3013030 obj=800000000802a0d8
        ra=0x930074aa  global=a30134d0 obj=8000000008028030
        ra=0x930074e2  global=a30134d0 obj=ffffffffa300f030
        ra=0x93007266  global=a3013030 obj=800000000802a108/120/138/150/198/1b0/1c8
        ra=0x930067dc  global=a3013030 obj=80000000080280e0/806d030
type 2: ra=0x93002db8  global=a3013030 obj=a3015030
        ra=0x930074fa  global=a30134d0 obj=a3015060
type 3: ra=0x930032b2  global=a30134d0 obj=a3015060
```

调用点的 `a4` 是 0/1/8/9 的辅助标志，不是 slot；slot 由
`0x9300581e`/表分配器从 free-list 选择。`meta` 低两位因此是
**注册类型/标志 a3**，不是区域大小，也不是 0xC gate。


### wrapper a4、type 12 与 session 的进一步实测/静态结果

a4 语义（与 GLM 一致，已由 slot 对应关系确认）：

```text
a4=1 -> 表 slot 1
a4=8 -> 表 slot 8
a4=9 -> 表 slot 9
a4=0 -> free-list 自动分配（本次得到 slot 0xb/0xc/0xd）
```

`0x9300581E` 先做 `bgeu a4,count` 越界检查，再 `bnez a4` 走显式
slot 分支；`a4=0` 读表头 `[0]` 的 free-list 头。

静态找到 type 12（0xC）的注册点：

```text
0x93006300  函数入口, li a0,10; jal 0x9300543a  # 分配对象
0x93006330  sd s2,128(a0)                       # s2=[a3008010] global
0x9300633c  li a3,12
0x93006344  jal 0x9300581e                      # meta = ...000C
0x9300634a  jal 0x93005b26                      # release 临时引用
```

这说明：

- `meta=0x800000000000000C` 的注册路径确实存在；
- 它注册的是新分配、保存 global 到 +128 的对象；
- boot 观察窗口内的 type 0/1/2/3 都不含 0xC，因此不走
  `SYSCALL[t0=4]` 的 release gate；type 12 更可能是运行期/RM
  对象，需继续追 `0x93006300` 的调用者。

session 纠正：

```text
0x93006C68 的 session a1 = 0xffffffffa3007e28  (不是 global a3013030)
[session+0x10] = 0x2c
[session+0x18] = 0x1400000, 0x1600000, 0x1800000,
                 0x1a00000, 0x7400000008001000, ...
```

`[session+0x18]` 是 4F3E 的 outer table base，且随调用变化。
`[global+0x18]` 不是 outer table：a3013030 的值是 `a3013040`
（循环 list），a30134d0 的值是 0。因此“session = global”不成立；
真机 handle 的 outer table 实例需要从 session 结构/调用者获取。


### 纠正：真正的 syscall dispatch 与 `0x93003902` 的归属

GLM 的纠正是对的：`0x93003902` **不是**全局 syscall dispatcher，
而是 `SYSCALL[t0=9]` handler 的一部分。实测 handler 表：

```text
table = 0xffffffffa3008280
entry(t0) = 32-bit handler pointer at table + t0*8

t0=4  -> 0xffffffff930008cc
t0=9  -> 0xffffffff930038fe    # 0x93003902 在 0x930038fe 内
t0=23 -> 0xffffffff93006300
```

真正的分发代码：

```text
0x930043e6: jal gp,0x930001cc
0x930043ea: li t1,36
0x930043ee: bltu t0,t1,0x930043f6
0x930043f2: j 0x930019b6
0x930043f6: slli t4,t0,3
0x930043fa: lui t1,0xa3008
0x930043fe: add t4,t4,t1
0x93004400: lw t4,640(t4)          # handler = table[t0]
0x9300440a: jalr t4                 # direct t0 dispatch
```

因此：

- `[global+0x450]` 不是 syscall dispatch table，而是 **对象/handle 表**；
- `0x93003902` 在 t0=9 handler 中，用 `[global+0x450]` 按 index 查对象；
- t0=4 的 fast path 在 `0x930042f8..0x9300434a`，使用
  `[sscratch+0x450]`，并检查 entry `meta & 0xC == 0xC`；
- KINIT n=3 实测：`sscratch = global = 0xffffffffa3013030`，
  所以 `[sscratch+0x450] == [global+0x450] == 0x800000000803a000` (t1)。

### `0x93006300` 的定位

`0x93006300` 是 handler 函数（t0=23 的候选），但它不是普通
call 目标，也没有在 boot 时注册到 syscall 表 index 23。
`0x93006300` 内部：

```text
0x93006314: li a0,10; jal 0x9300543a   # 分配对象
0x93006330: sd s2,128(a0)              # 保存 global
0x9300633c: li a3,12                   # type 12
0x93006344: jal 0x9300581e             # a4=0 -> free-list 自动 slot
```

这个 type 12 对象被插入随机 free slot，不是 slot 23；handler
本身也没有通过 `a4=23` 注册。故“t0=23 -> t0=4 完整闭环”在
当前 boot 表中不成立：t0=23 先会在 `0x9300391e` 返回 lookup=0
错误，handler 0x93006300 不会执行。

### wrapper 显式 slot 分支

```text
0x593c: a0 = table + (a4+1)*16
0x5944: a6 = [a0+16]          # 请求 slot 的 meta
0x5948: a0 = 1
0x594a: bgez a6, 0x5914       # meta>=0 (free) -> insert
0x594e: j 0x58b2              # meta<0 (occupied) -> error
0x5914: refcount++/insert obj/meta -> return 0
```

确认：

- a4 非 0 是显式 slot；slot 的 meta bit63=0 才可插入；
- 已占用（bit63=1）走 0x58b2 错误；
- 没有旧 refcount 检查，只有 meta 符号位判断。


### 23→4 纠正

之前的“t1[23]=0 所以 23→4 不成立”是基于错误表的反例，**撤回**。
t0=23 和 t0=4 都由 `0xa3008280` handler 表直接分发，不需要
在 `[global+0x450]` 预注册 syscall 号。type 12 对象由
`0x93006300` 创建并写入 t1（type 12 meta）；t0=4 fast path 在
`sscratch+0x450`（KINIT n=3 时就是同一张 t1）检查 `meta & 0xC`。
因此对象生命周期在表层面是自洽的；仍缺的是 `0x93006300`
返回给调用者的 slot/handle ABI，以及 t0=4 fast path 与
handler 表入口 0x930008cc 的关系。


### 直接 handler 实验：t0=23 create → t0=4 release

脚本 `scripts/test-lab-release.sh`（`make test-lab-release`）在 KINIT
n=3、`sscratch == global == a3013030` 的上下文里，用 scratch stack
直接进入真实 handler 函数体：

```text
call 0x93006300  (t0=23 handler)
  a0 = 0
  [sp+0xC] = 0x17 (slot 23)
  t1[23] = { obj=0x8000000008245030, meta=0x800000000000000c }
  obj refcnt = 1
  obj state(+120) = 0
  obj globalref(+128) = a3013030

call 0x930008cc(a0=0x17)  (t0=4 handler)
  a0 = 0
  t1[23] meta 仍为 0x800000000000000c
  obj refcnt 仍为 1
  obj state(+120) = 1
  t1 header first-free 仍为 0x18

第二次 call 0x930008cc(a0=0x17)
  a0 = 0
  t1[23] meta 仍为 0x800000000000000c
  obj refcnt = 2
  obj state(+120) = 1
  t1 header first-free 仍为 0x18
```

结论：

- `0x93006300` 的 ABI：无输入、a0=0 成功、slot 在 `[sp+0xC]`，
  不直接返回给用户。
- `0x930008cc` 用 a0=slot 走 t1 walk、`meta & 0xC` gate、
  TYPECALC type 10，返回 0。
- 第一次 release 是**引用/状态转移**（state 0→1，refcnt 净保持 1）；
  第二次 release 继续增加 refcnt（1→2），state 仍为 1，表项和
  meta 0xC 保留。它不是对象立即销毁或清表。
- 因而“23→4 完整闭环”应限定为“create→release handler
  路径成立”；完整对象销毁、用户 syscall 生命周期和更大目标
  仍未证明。表项本身很可能持有一个引用，需另一步移除/释放。


### 真正销毁路径：`0x93005B26` → TYPECALC → dtor（S-mode）

GLM 的解释与 lab 数据一致：

- t0=4 handler `0x930008cc` 不是 release，而是 lookup/deref：
  - refcount +1；
  - 若 obj state(+120) == 0，调用 `0x93005B26`（-1），净保持 1，
    并把 state 置 1；
  - 若 state != 0，跳过 `0x93005B26`，只保留 +1。
  这正好解释第一次 release 净 1、state 0→1，第二次 release
  refcount 1→2、state 1。
- 真正的销毁是 `0x93005B26`：refcount--，归零后调用
  `0x93004568` (TYPECALC)，从类型表 `0xffffffffa300a000 +
  type*40` 取 dtor，`jalr` 执行。

直接销毁实验（`scripts/test-lab-destroy.sh`，`make test-lab-destroy`）：

```text
create:  slot=0x17 obj=0x8000000008245030 meta=0x800000000000000C ref=1 state=0
call 0x93005B26(obj):
  ref 1 -> 0
  dtor = 0xffffffff93008130
  priv = 1 (S-mode)
  pc   = 0x93005b5e
  obj  = 0x8000000008245030
  satp = 0xf000000000000000
dtor entry 0x93008130, priv=1
```

`0x93008130` 是 type-10 dtor：先 `jal 0x93000e12`（清理 +40
list），再 tail-call `0x930069b6`。

结论：

- **已证明**：refcount→0 触发 TYPECALC/dtor，dtor 在 S-mode 执行；
  type-12 对象可以走到真实 dtor。
- **未证明**：U-mode 用户 syscall 能把一个正常注册对象的 refcount
  控制到 0 并到达该 dtor；t0=4 handler 的 +1/-1 净效果不会销毁
  正常对象。直接调用 `0x93005B26` 是诊断路径，不是用户可达路径。
- 因而“U-mode→S-mode 攻击闭环”仍需要额外的用户可达入口/对象控制，
  不能仅凭本实验宣称完成。


### t0=10 handler 与 gadget 实测

t0=10 的 handler 是 `0x93000bde`。它的检查顺序：

```text
walk(t1, index) -> obj/meta
if (meta & 2) == 0 -> return 2          # 0x93000c44
TYPECALC(obj) -> type
if type == 5 -> allowed
else if type <= 10 && ((0x491 >> type) & 1) -> allowed
else return 2
refcount += 1
jal 0x93005B26                          # -1, net 0
call 0x9300075a
```

注意：

- `0x491` 的位是 **0,4,7,10**（不是 0/4/8）；type 5 另有特判。
- 我们的 type-12 对象 meta=0xC，`meta & 2 == 0`，所以在
  0x93000c44 就被拒绝，返回 `a0=2`；不是 TYPECALC 位图拒绝。
- `0x93000bde` 在调用 `0x93005B26` 前先 `refcount += 1`，
  所以它是 lookup/deref，净 0，不是 net -1 的 destroy。

gadget 实测（`scripts/test-lab-gadget.sh`，`make test-lab-gadget`）：

```text
create: slot=0x17 obj=0x8000000008245030 meta=0x800000000000000C ref=1
t0=10 handler: a0=2 (meta & 2 == 0, rejected)

enter 0x930035d2 with a1=obj, s0=0:
  mv a0,a1
  jal 0x93005B26
  -> ref 1 -> 0
  -> dtor 0xffffffff93008130
  -> priv=1 (S-mode)
  -> dtor entry 0x93008130
```

静态 gadget：

```text
0x930035d2: mv a0,a1
0x930035d4: jal 0xffffffff93005b26
0x930035d8: mv a0,s0
0x930035da: jal 0xffffffff93005b26
```

结论：

- **已证明**：`mv a0,a1; jal 0x93005B26` 在受控 a1/PC 下能把
  type-12 对象 ref 1→0 并进入 S-mode dtor。
- **未证明**：U-mode 能控制 PC 到 0x930035d2，且控制 a1 为目标对象；
  B8 S-mode 回调的入口/寄存器控制仍未验证。
- t0=10 的“type12 被拒”结论正确，但原因是 meta bit1，不是
  0x491 位图；0x491 允许 type 0/4/7/10 + 特判 5。


### t0=4 fast path 实测

真正的 t0=4/5 特殊分支在 `0x930042f8..0x930043a0`。受控实验
（`scripts/test-lab-fastpath.sh`，`make test-lab-fastpath`）：

```text
setup: t0=4, a0=slot(0x17), stval=0, sscratch=global,
       sepc=marker, sstatus.SPP=1
create: slot=0x17 obj=0x8000000008245030 meta=0x800000000000000C ref=1 state=0

LAB_FASTPATH_STATE pc=0x93004382 a0=0x17 ref=0x1 state=0x1
```

结论：

- t0=4 fast path 对 state=0 的对象只做 state 0→1；
- refcount 保持 1；
- 不调用 `0x93005B26`；
- 不调用 handler `0x930008cc`（对应断点未命中）。

这确认 GLM 的 fast-path 判断。需要注意：如果 state != 0，
0x93004378 会跳到 0x930043e6 的 generic dispatch，才进入
handler `0x930008cc`；handler 路径才会做 refcount +1。

自然 boot 中 `0x930042f8` 命中为 t0=0/1/0x16；未观察到
t0=4 或 t0=23。因此这是受控 fast-path 入口，不是 U-mode trap。

### TYPECALC / dtor 表

`0x93004568` 从对象页 `+0x20` 读 class desc，减去
`0xffffffffa300a000` 后计算 type。类型表在静态 `data.bin`
中为 0（BSS），运行时由初始化填充；type-10 dtor 项在
`0xffffffffa300a198`，实际值为 `0xffffffff93008130`。


### t0=17 纠正：不是“直接把用户 a0 传给 0x93005B26”

GLM 的 t0=17 结论与 lab 实测相反。handler `0x93001AE0`：

```text
0x93001AE4: mv s2,a0          # s2 = 用户 a0
0x93001AE6: mv a0,a1
0x93001AF8: jal 0x93006906    # a1 必须是 [a301a1c8] 的 table slot
0x93001B14: jal 0x93008C26    # 请求 type 39；失败返回
0x93001B22: jal 0x9300543A    # 分配新对象 -> s1
0x93001B4E: sb s2,40(a0)      # 用户 a0 只按字节存到新对象 +40
0x93001B5C: jal 0x9300581E    # 注册新对象，type 3
0x93001B62: mv a0,s1          # a0 = 新分配对象
0x93001B64: jal 0x93005B26    # 释放的是 s1，不是用户 s2
```

`make test-lab-t017` 实测：

```text
LAB_T017_SETUP global=0xffffffffa3013030 t1=0x800000000803a000
    target=0xffffffffa3015090 t1slot12=0xffffffffa3015090
LAB_T017_SERVICE_RET a0=0 s2(user)=0x41 (forcing success)
LAB_T017_ALLOC s1(new)=0x8000000008245030 s2(user)=0x41 newref=0x1
LAB_T017_PRE_RELEASE s1(new)=0x8000000008245030 s2(user)=0x41 newref=0x2
LAB_T017_CALL_05B26 a0=0x8000000008245030 s1(new)=0x8000000008245030 s2(user)=0x41
LAB_T017_RET a0=0 newobj=0x8000000008245030 newref=0x1 userbyte=0x41
```

因此：

- t0=17 是 **create/register** 类操作，不是 destroy user pointer。
- `0x93001B64` 的 `a0` 是 `0x9300543A` 新分配的 s1；
  用户 a0=s2 只被存成 `[newobj+40]` 的一个字节。
- 注册后新对象 ref=2，释放后 ref=1；没有 ref→0，没有 dtor。
- 前置条件：a1 必须是 `[a301a1c8]` 的 table slot（本 profile slot 12）；
  且 `0x93008C26` 服务成功；否则 handler 返回 2。
  lab 中该服务自然返回 2，脚本为到达分配路径强制其返回 0。
- 所以 t0=17 不是 GLM 所说的“干净 U-mode destroy 入口”。

真正的受控 destroy 仍是 `0x930035D2` gadget / 直接 `0x93005B26`；
仍缺 U-mode 控制 PC/a1 的入口（B8 回调）。


### t0=17 / B8 / slow handler 的条件

GLM 的静态扫描（80 个 `li t0,17`，无有效 `unimp` stub）与 lab 的
t0=17 反例一致：t0=17 是 create/register，不是 U-mode destroy。

B8 地址空间约束：

```text
RM code range:      0x01xxxxxx
kernel gadget:      0x930035d2 (kernel VA / outside RM range)
```

RM U-mode 不能直接跳到 kernel 空间；B8 若只能执行 RM 空间，
直接跳 `0x930035d2` 不可行。lab 的 U-mode fetch 测试因 gdb 不能
可靠写 priv 而没有拿到干净 fault 轨迹；这条目前是“地址空间/静态
支持”，不是完整 RM 执行验证。

慢 handler 条件（`make test-lab-statecond`）：

```text
state=1, ref=0 -> handler 0x930008CC: ref 0->1, state=1, 跳过 0x93005B26
                  -> a0=0, 无 dtor

state=0, ref=0 -> handler 0x930008CC: ref 0->1, state=0,
                  调 0x93005B26 -> ref 0 -> dtor 0x93008130 (priv=1)
```

但正常 U-mode t0=4 fast path 在 state=0 时只做 state 0→1，
不调用 handler、不调用 0x93005B26。因此：

- `li t0,4; unimp` 的正常 syscall 路径**不能**用 state=0/ref=0 到达 dtor；
- 要利用“write gadget 改 refcount + state=0 + 触发”，触发必须
  **直接调用 slow handler 0x930008CC**（或绕过 fast path），
  而不是普通 U-mode t0=4 syscall。

这意味着 GLM 的 RM 读/写 gadget + trigger 计划在“直接调 slow
handler”前提下是可行的；若 trigger 只是 `li t0,4; unimp`，则不成立。

## 尚未完成

1. walk 表已确认可读且已填充；下一步是解码 `obj/meta` 的具体类型语义，以及 handle（如真机 `0x0303000000307c70`）到表项的索引规则。
2. `init.elf` 后续 map（错误字符串 `0x20004bb0` 路径）和 RM 任务启动。
3. FMC 之后的完整 M-mode 服务、DMA 设备、BootROM 认证/解密策略。
4. 真机 `GspFwWprMeta` 的 ACR 实际填充值与 non-WPR/FRTS 布局。

不把本检查点等同于真机启动成功；它只证明原始生产 LibOS 在 QEMU 中真实执行到 walk 表发布指令，并给出了该 profile 下的表地址。

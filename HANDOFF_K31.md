# 交接文档 — GSP 代码执行攻击 (K3-1)

日期: 2026-09-29 19:00
状态: K3-1 在裸机上 crash 在 0x1b8ffbc，VM 环境需要重建

> **⚠️ 2026-09-29 晚补充**: 本文档状态已过时两处 —
> ① K3-1 不止 IP 控制：**任意读(0x1020a30) + 任意写(0x1b52246) 已于 9月26日在 VM 实测打通**；
> ② 0x1b8ffbc 已有静态解释("有效通道集合变空" 0x101dc08 掩码机制)，裸机 K=33 失败 = 回调路径未触发。
> 详见 **`DS_SESSION_K31_RECOVERY_20260929.md`**（含 DS 原始会话 line 号索引、FSP 主线两条路径、行动清单）。

---

## 一、核心目标

在 RTX 5090 (GB202) 的 GSP (RISC-V 处理器) 上获得任意代码执行，
然后从 GSP 内部读取 FSP 的运行时代码（解密后的）进行静态分析。

## 二、必读文件（按优先级排序）

### 最高优先 — K3-1 完整分析
| 文件 | 内容 |
|------|------|
| `parallel/K3_STAGING_ADJACENCY_20260926.md` | **堆布局指令级证明**：RX staging 64KB → TX staging 64KB → msgqMetadata 0xE8B。元素 32 = P+0x20000 = msgqMetadata。含枪A完整规格和触发路径推演 |
| `parallel/DS_FMT_WRITE_PRIMITIVE_20260926.md` | **回调参数语义 + P1-P6 载荷规格**。rxrefresh@0x1004c9c 的 a1=*(meta+0x38), a4=*(meta+0xc0)。写 gadget 0x1b52246 = `c.sw a4,0(a1); ret` |
| `parallel/K3_IP_CONTROL_NEXT_20260926.md` | **成功记录**：枪A命中，sepc=stval=0xdeadbeee, scause=0xc, ra=0x1004c9e。IP 控制确认 |
| `guest_dmesg_K33_DEADBEEF_0722.txt` | **成功 crash log 原件**。fn=73 触发, K=33, pat=1, ck=0 |
| `parallel/K3_DEEP_20260926.md` | K3 全面分析：PRC 子命令模型更正、effective L2 掩码未写过、task 扫描模型错误 |

### 高优先 — 利用基础设施
| 文件 | 内容 |
|------|------|
| `fsp_ace_static_20260927/GSP_EXEC_RUNBOOK.md` | Shot 0 (翻 MNOC 标志) + 假对象树 + tdispmgr trampoline 完整计划 |
| `fsp_ace_static_20260927/F1_FINAL_VERDICT.md` | F-1 VLA 溢出 (GPU_EXEC_REG_OPS) A 级实锤。dkms 补丁方法 |
| `parallel/RM_HOST_IFACE_BUGHUNT_K3_20260925.md` | K3-1a/b 指令级漏洞定义 + 溢出量化 (63×4096B) |

### 参考 — 架构和之前实验
| 文件 | 内容 |
|------|------|
| `parallel/K3_FSP_MSGPATH_20260926.md` | FSP 通信协议完整闭合 + GSP↔FSP 通道 |
| `parallel/DS_GSP_MNOC_SERVER_20260926.md` | tdispmgr 服务端逆向 (VA 0x18BBD60, 610.57) |
| `K31_FINAL_REPORT.md` | 本轮裸机测试全部阴性结果记录 |
| `PRIMITIVE_CROSS_ANALYSIS.md` | 所有原语交叉分析（K3-1 是核心，其他辅助） |
| `ELF_TOCTOU_BREAKTHROUGH.md` | 55MB ucodes TOCTOU 窗口确认 |
| `GSP_61571_FINAL_ADDR_MAP.md` | 615.71 地址映射（gadget/回调/tdispmgr） |

## 三、当前状态

### K3-1 成功条件（2026-09-26 07:22 在 VM 中验证；HANDOFF 原写 2026-07-22 系文件名 _0722 时间戳误读为日期，已修正）

```
环境: VFIO GPU 直通 VM (mods-lab-gpu-primary.service)
驱动: 610.57.04 DKMS 补丁版
触发: fn=73 (boot 后期, ~160s)
参数: K=33, pat=1, ck=0, realElems=1, declared=0x21000
载荷: 元素 0=正常RPC+ck=0, 元素 1-31=全零, 元素 32=P1 (全零+0xa4=1+0xb8=DEADBEEF)
结果: sepc=stval=0xdeadbeee, scause=0xc, a5=0xdeadbeef, ra=0x1004c9e
     → IP 控制确认，写入 meta+0xb8 的字节被 jalr 执行
```

### 裸机上失败的原因

```
裸机测试 (2026-09-29): 所有参数组合都 crash 在 pc=0x1b8ffbc, stval=0x4fe6
原因: 0x1b8ffbc 代码做 lbu a5, -0x1a(a0+0x5000), a0=NULL → load fault
推论: 裸机堆布局与 VM 不同，溢出覆盖的某个结构含关键指针
     VM 中该位置可能恰好不含关键数据（或对齐不同）
```

### 610.57 vs 615.71 差异

```
当前系统: 已降级到 610.57.04 (与成功案例相同版本)
版本锁定: pacman IgnorePkg 已设置

615.71 固件: 代码完全重排，需要重新定位所有地址
  已定位: 写gadget 0x010754F0 (c.sd a4,0(a1)), 回调分发 0x01D7A7CC,
         tdispmgr 0x01AB7E04, MNOC init 0x016E58F0
  未定位: msgq 接收函数的 615.71 精确地址, 堆布局
```

## 四、关键猜想（未验证）

### 猜想 1: 裸机 crash 的根本原因
```
0x1b8ffbc 的代码读取 a0+0x4FE6 处的字节
a0 可能来自被溢出覆盖的某个指针（元素 17-31 范围内的堆结构）
VM 中这个偏移恰好是空闲内存（VM 内存映射更简单）
裸机中这里有活跃数据 → 任何覆盖都导致 NULL 指针

验证方法: 在 VM 中 dump 元素 17-31 落点的堆内容,
         对比裸机 crash 位置
```

### 猜想 2: 堆布局可能是确定性的
```
如果 GSP 堆分配是确定性的（每次 boot 相同），
则在 VM 中 dump 一次堆内容，就能永远用于该环境

关键地址 (从成功 crash log):
  s3 = s5 = 0x0fe4770e10 → P = RX staging 基址
  s1 = s8 = 0x0fe4790e10 → P + 0x20000 = msgqMetadata
  s11 = 0x41914d0 → MQI (BSS)

验证: 在 VM 中多次 boot 检查这些地址是否恒定
```

### 猜想 3: 获取任意写后可以直接 dump FSP
```
成功 P1 后的升级路径:
  1. 把 0xb8 换成写 gadget (0x1b52246): c.sw a4, 0(a1); ret
  2. a1 = 任意地址 (meta+0x38), a4 = 任意值 (meta+0xc0)
  3. 循环触发 (每次 RPC 收包都调回调)
  4. 从 GSP 内部读 FSP 的 EMEM/寄存器 → dump 到 sysmem → 宿主读

前置: 知道 FSP 内部 SRAM 在 GSP 地址空间的映射
```

### 猜想 4: Shot 0 (翻 MNOC 标志) 可能比 dump 更有价值
```
GSP 侧 RmFspUseMnoc 标志在 ctx+0x1df
置 1 后 GSP 的 FSP 通信自动走 MNOC port 0 (GSP 车道)
FSP 信任 GSP 端口的消息 → 可能解锁 GSP-only 服务

用 K3-1 任意写: 一次写入即可翻转
需要: ctx 运行时地址 (从 0x1509338 初始化函数全局回溯)
```

## 五、VM 环境问题（需要解决）

```
当前 VM 基础设施:
  磁盘: vm_mods_lab/base.qcow2 (4GB) + run-gpu/gpu-overlay.qcow2 (160MB overlay)
  OVMF: run-gpu/OVMF_VARS.gpu.fd
  VFIO: vfio-bind-5090.sh / vfio-release-5090.sh
  QEMU: 已安装 (11.1.1), KVM 可用

问题:
  1. SSH 未安装在 VM 中 (cloud-init 没配好)
  2. 之前的 systemd service (mods-lab-gpu-primary.service) 被清理了
  3. 串口 console 只能输出(文件)不能输入
  4. cloud-init seed (ISO/FAT) 不被识别 — DataSourceNone
  5. guestfish/libguestfs 超时 (可能与 VFIO 状态冲突)

解决方向:
  a. 重建 systemd service (用 libvirt 或直接 QEMU)
  b. 用 expect/tmux send-keys 通过串口交互
  c. 或用 libguestfs (需要先解决超时问题)
  d. 或重新制作 VM 镜像 (预装 SSH)
```

## 六、重要操作注意事项

1. **GPU 状态管理**: kill QEMU 后 GPU 进入脏状态，必须做 SBR 重置才能启动新 VM
2. **WPR2 残留**: GSP crash 后 WPR2 不释放，只有整机热重启能清
3. **nvidia-reset.sh**: `/home/user/hw_configs/nvidia-reset.sh` — 完整的 GPU 恢复脚本
4. **BIOS 开关**: 卡上有双 BIOS 开关。当前在 XOC 位置（原版位置被 CC knob 锁死）
5. **版本锁定**: nvidia 610.57.04 已通过 pacman IgnorePkg 锁定

## 七、下一步建议（按优先级）

### 路径 A: 修 VM 环境（推荐）
```
1. 重建 VM 交互能力 (SSH 或串口)
2. 在 VM 中验证 K3-1 (应该能复现 7月22日的成功)
3. 升级到写 gadget (P1 → 任意写)
4. Shot 0: 翻 MNOC 标志 → GSP 身份的 FSP 通信
5. 从 GSP dump FSP 代码
```

### 路径 B: 裸机堆布局分析
```
1. 分析 0x1b8ffbc 的代码依赖什么指针
2. 确定裸机上元素 17-31 覆盖了什么结构
3. 找到不破坏该结构的载荷方案
4. 或者: 找到不同的溢出点（比如从 status queue 溢出）
```

### 路径 C: 55MB ucodes TOCTOU
```
已证明可以修改 ucodes 容器并使 GSP crash
需要: 分析 GSP 解析 ucodes 的代码 (磁盘上 27MB 固件中)
找: 解析 bug (越界/类型混淆)
```

## 八、工具和资产

```
DKMS 补丁驱动: /usr/src/nvidia-610.57.04/ (含 XDIG_OVF 补丁)
VM 磁盘: vm_mods_lab/run-gpu/gpu-overlay.qcow2 (含 7月22日的 XDIG 补丁)
GSP 固件 (明文): power_governor_reverse/gsp61057_rx_full.bin
615.71 固件: /usr/lib/firmware/nvidia/615.71.09/gsp_ga10x.bin
成功 crash log: rt_5090_project/guest_dmesg_K33_DEADBEEF_0722.txt
写 gadget: 610=0x1B52246, 615=0x010754F0
回调分发: 610=0x1004C9C, 615=0x01D7A7CC
F-1 注入机器: f1_fire_patch.py, f1_patch.py
PRC 工具: /home/user/prc_rw
```

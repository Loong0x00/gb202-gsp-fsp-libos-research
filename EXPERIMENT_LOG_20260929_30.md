# 2026-09-29/30 GPU WPR2 死锁战役 — 完整实验记录

日期: 2026-09-29 19:00 → 2026-09-30 17:00 (约22小时)
状态: GPU 可通过 VM 流程复活, 永久修复待编程器

---

## 一、时间线总览

### 9月29日晚 (19:00-24:00)

| 时段 | 实验 | 结果 |
|------|------|------|
| 19:00-20:00 | DS 会话考古 + K3-1 白天数据证伪 | 白天 K3-1 裸机全败 = 脏机器污染 |
| 20:00-21:00 | MNOC port0 通道打通 + 原版槽 CC 清除 | CC knob 6/8/10/39/40/42 全清, 断电存活 |
| 21:00-22:00 | WPR2 死锁机理闭环 | 双记录模型确立 (记录A=窗口恢复, B=处理器陪葬) |
| 22:00-23:00 | PCIe 复位档位矩阵 + 外部情报 | FLR/SBR/PM 全等效; 世界已知=浅层版 |
| 23:00-24:00 | NVDM 0x12 FIRMWARE_UPDATE 通道打通 | cmd6 免会话查询活; cmd1-5,7 会话门控(0x188) |

### 9月30日 (09:00-17:00)

| 时段 | 实验 | 结果 |
|------|------|------|
| 09:00-10:00 | nvflash 逆向 + vtable 定位 | 7 命令构造函数地址复核 |
| 10:00-11:00 | nvflash 进 VM | ★ 拓扑修复(pcie-root-port) → 认卡! |
| 11:00-12:00 | EEPROM dump + diff | 1.9MB VBIOS 区干净; 毒在 0x1DF000+ FSP 私有区 |
| 12:00-13:00 | nvflash 写路径测试 | 读活写死三重证(update/protectoff/offset 全挂) |
| 13:00-14:00 | MODS SUL=5 双补丁 | setter立即数1→5 + NOP二次覆盖 → INTERNAL 模式! |
| 14:00-15:00 | ★ GPU 复活! | MODS CPU-RM → nvidia → RTX 5090 完全工作 |
| 15:00-16:00 | 持久性验证 | VM 热重启: 活 ✓ / 宿主断电: 死(记录A在flash) |
| 16:00-17:00 | 宿主 MODS 编译 | mods.ko 编译成功但中断 API 不兼容(内核7.2 vs 5.15) |

---

## 二、核心发现

### 1. WPR2 双记录死锁模型

```
记录A(会话/窗口): GSP脏死时写入 → 每次冷启动恢复WPR2窗口
  位置: FSP-private flash (0x1DF000+, 4MB芯片的上半2.1MB)
  效果: FSP boot → 读flash → 预设WPR2 → 驱动拒绝boot GSP

记录B(处理器陪葬): GSP崩溃那一刻写入 → COT/boot处理器死
  位置: 同上
  效果: FSP SCRATCH_GROUP_2(0) 从0x177(活)变为0x522(死)
  连锁: 即使清了WPR2, GSP boot后在fn73处崩(0x1b8ffbc)
```

**死锁**: 清除记录需要写flash → 写flash需要FSP会话 → FSP会话被记录毒坏

### 2. MNOC port 0 = 宿主可用的 FSP 通道

```
寄存器 (BAR0 偏移, 基址 0x8f1e00, port stride 0x0c):
  INFO_SEND = base + 0x104 + port*12   (bit24=ready, bit25=error)
  RDATA_SEND = INFO_SEND + 4           (读FSP响应)
  INFO_RECV = base + 0x184 + port*12   (bit24=ready, bit25=err, bit26=credits)
  WDATA_RECV = INFO_RECV + 4           (写消息数据)

发送配方:
  1. poll INFO_RECV bit24 (receive-ready)
  2. 写 INFO_RECV = size | (1<<20)  (长度+触发)
  3. 逐dword写WDATA_RECV, 每64B poll bit26 (credits)
  4. 检查bit25 (error)

接收配方:
  1. poll INFO_SEND bit24 (message-ready)
  2. size = INFO_SEND & 0xfffff
  3. 逐dword读RDATA_SEND

关键事实:
  ★ 这是官方 gpu-admin-tools 使用的通道 (FspMnocRpc)
  ★ 在脏卡上仍然活着 (与PRC/EMEM同族幸存)
  ★ B7b "port0宿主注入被无视"结论作废 — 那是协议错误
```

### 3. MODS CPU-RM = WPR2 清零机制

```
MODS CPU-RM 初始化过程会清零 WPR2 寄存器(0x88a824/0x88a828)
这是因为它走 CPU 侧 RM 初始化路径, 不经过 FSP 会话

完整复活流程:
  1. VM 里加载 mods.ko + 运行 MODS CPU-RM → WPR2 = 0
  2. 卸载 MODS → modprobe nvidia → GSP boot!
  3. nvidia-smi 显示完整 RTX 5090 (32GB, 29°C, 30W)

局限性:
  - 断电后 FSP 重新读 flash → 记录A恢复 → WPR2 又up
  - VM 关闭时的设备复位也会触发 FSP 重涂
  - 需要每次冷启动后重新执行
```

### 4. MODS SUL=5 双补丁

```
目标: 把 SecurityUnlockLevel 从 1 提升到 5 (最高工厂级)

补丁1: setter 立即数 1→5
  VA 0xd81d7b (file offset 0x981d7b, 570.215 binary)
  原始: c7 05 <rel32> 01 00 00 00  (mov dword[SUL], 1)
  补丁: c7 05 <rel32> 05 00 00 00  (mov dword[SUL], 5)

补丁2: NOP 掉二次覆盖
  VA 0xd81d9b (file offset 0x981d9b)
  原始: 89 1d <rel32>  (mov [SUL], ebx — 用input覆盖)
  补丁: 90 90 90 90 90 90  (NOP×6 — 保留初始值5)

效果: "INTERNAL ONLY MODS UNLOCKED" + "MLE Mode: INTERNAL"
注意: 必须用 570.215 二进制 + 570.215 JSE 文件 (版本不兼容会 Decompression failed)
```

### 5. NVDM 0x12 FIRMWARE_UPDATE 任务

```
任务ID: taskId=3
通道: MNOC port 0 (与PRC同通道, 不同任务)

命令行为:
  cmd 1-5,7,8-15 bare: errorCode=0x188 (会话门控)
  cmd 6 bare: errorCode=0 + data=0x166585 (免会话查询)
  cmd 6 +参数: errorCode=0x2cd (参数长度错)
  任意命令: 三字段标准响应 {taskId, cmdType, errorCode}

结论: FSP固件更新任务活着, 但写路径被会话机制锁住
这与 nvflash 的行为一致(读EEPROM活, 写EEPROM挂)
```

### 6. nvflash VM 拓扑修复

```
问题: nvflash 在 VM 里报 "No NVIDIA display adapters found"
根因: GPU 挂在 PCIe 根总线上 (00:03.0)
修复: 加 pcie-root-port 让 GPU 挂在桥后 (01:00.0)

QEMU 参数:
  -device pcie-root-port,id=gpuport,bus=pcie.0,chassis=5,slot=5
  -device vfio-pci,bus=gpuport,host=0000:01:00.0,multifunction=on

其他必要条件:
  - guest 内核参数 iomem=relaxed (允许 /dev/mem MMIO)
  - multifunction=on (保持 header type 0x80)
  - rmmod nouveau (防止抢占)
```

---

## 三、实验环境

### VM 配置 (run-mods-dirty-try-20260929/)

```
磁盘链: overlay.qcow2 → run-mods570215-vf-sweep-20260929/overlay.qcow2 → base.qcow2
Guest OS: Ubuntu 22.04.5, kernel 5.15.0-194-generic
内核参数: iomem=relaxed console=ttyS0,115200

关键目录:
  ~/mf215/     — MODS 570.215 完整环境 (SUL=5 补丁版)
  ~/mf215/driver/ — mods.ko 源码 (已编译)
  ~/nf/        — nvflash + .fwpkg 样本
  ~/mf2/       — 570.151 JSE 环境 (备用)

QEMU 启动命令:
  qemu-system-x86_64 -name mods-dirty-try \
    -machine q35,accel=kvm,kernel_irqchip=on \
    -cpu host -m 8G -smp 4 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/ovmf/x64/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file=$P/OVMF_VARS.fd \
    -drive file=$P/overlay.qcow2,if=virtio,format=qcow2 \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:22292-:22 \
    -device virtio-net-pci,netdev=net0 \
    -device pcie-root-port,id=gpuport,bus=pcie.0,chassis=5,slot=5 \
    -device vfio-pci,bus=gpuport,host=0000:01:00.0,multifunction=on \
    -display none \
    -serial unix:$P/serial.sock,server,nowait \
    -monitor unix:$P/mon.sock,server,nowait \
    -daemonize
```

### SSH 连接

```
安装: apt install openssh-server (一次性)
连接: sshpass -p 'mods-lab' ssh -p 22292 mods@127.0.0.1
传文件: sshpass -p 'mods-lab' scp -P 22292 <file> mods@127.0.0.1:~/
注意: boot 后需要 dhclient enp0s2 才有网络
sudo: echo mods-lab | sudo -S <command>
```

### 串口驱动工具

```
位置: $P/serial_drive.py
用法: sudo python3 $P/serial_drive.py $P/serial.sock <cmd_file>
格式:
  WAIT:<pattern>  — 等待串口输出匹配
  SEND:<text>     — 发送一行
  SLEEP:<sec>     — 等待
日志: $P/serial_full.log (全部串口输出)
```

---

## 四、GPU 复活流程 (验证有效)

### 方法A: VM 内复活 (在 VM 里用 GPU)

```bash
# 1. 宿主: 停nvidia绑vfio
sudo pkill -9 gb202_hotspot; sudo rmmod nvidia_uvm nvidia
sudo bash -c 'for d in 0000:01:00.0 0000:01:00.1; do
  echo vfio-pci > /sys/bus/pci/devices/$d/driver_override
  echo $d > /sys/bus/pci/drivers_probe; done'

# 2. 启动 VM (上述QEMU命令)

# 3. Guest 内 (通过串口或SSH):
echo mods-lab | sudo -S bash -c "
insmod /home/mods/mf215/driver/mods.ko
rmmod nouveau 2>/dev/null
cd /home/mods/mf215
timeout 90 ./mods -nc -m 'g_CheckVbiosSecurity=false;' \
  gputest.jse -test 2 -testarg 2 LoopMs 500 \
  -skip_azalia_init -null_display -no_vga -no_gold > /dev/null 2>&1
rmmod mods
modprobe nvidia
sleep 15
nvidia-smi  # 应显示 RTX 5090!
"
```

### 方法B: 宿主直接复活 (尝试中, 中断API不兼容)

```
1. 宿主上编译 mods.ko (需要修复 screen_info + rdmsr 兼容性)
2. insmod mods.ko
3. 运行 MODS CPU-RM
4. rmmod mods
5. modprobe nvidia

当前卡点: 内核 7.2.6 的中断 API 与 MODS 570.215 不兼容
"cannot hook interrupt" (MSI-X 无法使能)
需要: 内核补丁或降级内核
```

---

## 五、K3-1 注入环境 (已搭建, 未触发)

### 已完成

```
1. 610.57 DKMS 驱动编译安装 ✓
   源码: /usr/src/nvidia-610.57.04/ (从宿主传输)
   GSP固件: /lib/firmware/nvidia/610.57.04/gsp_ga10x.bin

2. v17 溢出补丁植入 ✓
   目标: message_queue_cpu.c
   源码来源: open-gpu-kernel-modules (干净版)
   参数: K=33, ck=0, fn=73 (硬编码)
   _xdigPostInit = 1 (始终激活)

3. 注入参数硬编码 ✓
   _xdigOvfK = 33u (元素数)
   _xdigOvfCk = 0u (checksum)
   _xdigOvfFn = 73u (目标RPC函数)
```

### 未触发原因

```
nvidia-smi 版本不匹配 (610内核 vs 580用户态) → 无法发送RPC
需要: 610.57 的用户态库 (libnvidia-ml.so 等)
来源: 从宿主传输或下载 .run 安装包
```

### 下一步

```
1. 传 610.57 用户态库到 guest
2. nvidia-smi 触发 RPC fn=73
3. 观察 XDIG 输出确认注入
4. 用注入控制 GSP 执行 → MNOC 写 flash → 清记录A
```

---

## 六、资产清单

### 工具 (宿主)

```
/home/user/rt_5090_project/
├── mnoc_prc.c/.c     — MNOC port0 收发 (PRC/knob/fw/rawm)
├── bar0rw.c           — BAR0 寄存器读写
├── prc_couple.c       — PRC couple-reset (SBR→fundamental)
├── reset_coupling_probe.py — armed前后对照
├── GPU_REVIVE_V2.sh   — 一键复活脚本 (需改进)
├── mnoc_guest2        — guest版MNOC工具 (BAR0=0x80000000)
├── xoc_dirty_eeprom_20260930.rom — 脏EEPROM dump (1.9MB)
├── mods_sul5_host     — SUL=5补丁版MODS (570.215, 392MB)
├── nvflash_5877_text_disasm.asm — nvflash全量反汇编
└── PRC_KNOB_BASELINE_XOC_20260929.txt — knob基线
```

### 工具 (guest overlay 内)

```
/home/mods/
├── mf215/             — MODS 570.215 完整环境
│   ├── mods           — SUL=5 补丁版二进制
│   ├── driver/mods.ko — 已编译内核模块
│   └── *.jse          — 570.215 JSE 脚本
├── nf/                — nvflash + fwpkg
├── eeprom_dump_xoc_dirty.rom — EEPROM dump
└── mnoc_g             — guest版MNOC工具
```

### 密钥文件

```
/home/user/rt_5090_project/vbios_flash_tools/nvflash_5.877_hpe/
└── nvflash            — nvflash 5.877 (16MB, stripped ELF)

/home/user/.cache/mods570215-powertrace.GC5pNs/
└── mods               — MODS 570.215 原始二进制 (SHA: 6645d5de...)

/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/
└── src/.../message_queue_cpu.c — 干净源码 (v17补丁基底)
```

---

## 七、公开世界对比

| 来源 | 症状 | 恢复 | 我们的差异 |
|------|------|------|-----------|
| NVIDIA论坛 qiuzhiqiang75 | WPR2 up, SBR打掉卡 | 整机重启恢复 | 我们断电不恢复(flash记录) |
| NVIDIA论坛 atlaspoint | 同上 | 整机重启 | 同上 |
| CloudRift悬赏 | FLR后卡死 | 整机重启 | 580+驱动已修FLR类 |
| Reddit Xid79 | 随机掉卡 | 断电重启 | 我们的更深层 |
| Level1Techs | InfoROM锁定 | 无法恢复 | 部分类似 |

**我们的独特发现**:
1. WPR2 双记录模型 (公开世界无报告)
2. 记录跨断电存活 (公开世界未见)
3. MODS CPU-RM 可清 WPR2 (独创)
4. MNOC port0 宿主配方 (B7b否定结论推翻)

---

## 八、编程器修复计划 (待执行)

```
硬件: CH341A + SOP8 测试夹 (~50元)
目标: 两颗 PUYA PY25Q32 (4MB each, SOP8)

步骤:
1. 断电, 夹住芯片 (注意方向)
2. 读全 4MB (第一次看到 FSP 私有区!)
3. 对比两颗芯片 (都是脏的但损伤不同)
4. 定位记录A+B 的具体字节位置
5. 擦除/回写正常值 (或全FF)
6. 装回 → 断电重启 → nvidia-smi

注意事项:
- 水冷挡住 PCB 上方, 需确认芯片可达性
- 编程器供电 3.3V 可能倒灌 GPU SPI 引脚
- 备份原始数据后再修改!
```

---

## 九、9月30日傍晚 K3-1 注入搭建记录

### 610.57 驱动安装过程

```
1. 从宿主 tar 打包 DKMS 源码 (27MB)
2. scp 传到 guest /tmp/
3. tar 解压到 /usr/src/nvidia-610.57.04/
4. GSP固件复制到 /lib/firmware/nvidia/610.57.04/
5. dkms remove 580 → dkms install 610
6. 验证: nvidia/610.57.04 installed

注意:
- guest systemd 自动加载 nvidia → 需要先 rmmod 再 insmod 610
- nvidia_uvm 被 modules-load.d/nvidia-utils.conf 强制加载
- 需要清空该文件 + rmmod 全部 nvidia 模块
```

### v17 补丁踩坑记录

```
1. guest 源码已被之前的补丁污染 (XDIG标记残留)
   → 需要从干净源码重新开始
   → 干净源码: /home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules/

2. v17 的 anchorC 匹配失败
   → 原因: 源码格式差异 (多空格 vs 单空格)
   → 解决: 用干净源码后匹配成功

3. _xdigPostInit 未定义
   → v17 期望在 kernel_gsp.c 定义
   → 解决: 追加 "NvU32 _xdigPostInit = 1;" 到 kernel_gsp.c 末尾

4. sed 多空格匹配失败
   → 源码里 "_xdigOvfK         = 0xffffffffu" (多空格)
   → sed 模式需要用 " * " 匹配任意空格: '_xdigOvfK *= *0xffffffffu'

5. DKMS 编译缓存
   → dkms remove 后重 install 使用最新源码
   → 需要在修改源码后 ALWAYS 做 dkms remove + install
```

### 注入参数硬编码

```
文件: /usr/src/nvidia-610.57.04/src/nvidia/src/kernel/gsp/message_queue_cpu.c

修改 (使用通配空格的 sed):
  _xdigOvfK:   0xffffffffu → 33u   (声明33个元素,实际16个)
  _xdigOvfCk:  1u → 0u            (不修checksum, 走重试路径)
  _xdigOvfFn:  0xffffffffu → 73u  (只在fn=73时注入)

加上 kernel_gsp.c 末尾:
  NvU32 _xdigPostInit = 1;  (始终激活)
```

---

## 十、待办事项

- [ ] 编程器到货 → 读4MB flash → 定位毒位 → 永久修复
- [ ] 610.57 用户态库传输 → nvidia-smi 触发 K3-1 注入
- [ ] K3-1 注入 → GSP 代码执行 → MNOC 写 flash
- [ ] 宿主 mods.ko 中断兼容性修复 (内核 7.2 API)
- [ ] GPU_REVIVE_V2.sh 改进 (音频绑定时序、模块卸载排序)
- [ ] CVE 报告撰写 (WPR2 双记录死锁 + 跨断电 DoS)

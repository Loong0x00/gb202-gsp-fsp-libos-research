# GPU 复活操作手册 (MODS CPU-RM 方法)

日期: 2026-09-30
状态: 已验证有效 (VM 内), 宿主待中断兼容性修复
前提: 每次**冷启动(断电)**后需要重新执行

---

## 原理

```
MODS CPU-RM 初始化 GPU 时会清零 WPR2 寄存器
→ 驱动检查通过 → GSP 正常 boot → GPU 完全工作
→ 断电后 FSP 从 flash 重新恢复 WPR2 → 需重新执行

注意: "GPU 完全工作"包括 nvidia-smi、CUDA、显示输出
但这个状态不持久(记录A在flash里, 我们写不了flash)
```

## 方法A: VM 内复活 (验证有效)

### 步骤 1: 宿主准备

```bash
#!/bin/bash
# 停宿主 nvidia, 绑 vfio
sudo systemctl stop nvidia-persistenced lactd 2>/dev/null
sudo pkill -9 gb202_hotspot 2>/dev/null
for pid in $(sudo lsof -t /dev/nvidia* 2>/dev/null); do
    sudo kill -9 $pid 2>/dev/null
done
sleep 1
sudo rmmod nvidia_uvm nvidia 2>/dev/null
sleep 1
# unbind nvidia if still bound
sudo bash -c 'echo 0000:01:00.0 > /sys/bus/pci/drivers/nvidia/unbind 2>/dev/null'
sudo modprobe vfio_pci 2>/dev/null
sudo bash -c '
for d in 0000:01:00.0 0000:01:00.1; do
    echo vfio-pci > /sys/bus/pci/devices/$d/driver_override
    echo $d > /sys/bus/pci/drivers_probe
done'
sleep 2
# 确认
lspci -kk -s 01:00.0 | grep "driver in use"  # 应显示 vfio-pci
lspci -kk -s 01:00.1 | grep "driver in use"  # 应显示 vfio-pc
```

⚠️ **常见问题**: 01:00.1 (音频) 可能被 snd_hda_intel 抢占:
```bash
sudo bash -c '
echo 0000:01:00.1 > /sys/bus/pci/drivers/snd_hda_intel/unbind 2>/dev/null
echo vfio-pci > /sys/bus/pci/devices/0000:01:00.1/driver_override
echo 0000:01:00.1 > /sys/bus/pci/drivers_probe'
```

### 步骤 2: 启动 VM

```bash
P=/home/user/rt_5090_project/vm_mods_lab/run-mods-dirty-try-20260929
rm -f $P/*.sock
sudo qemu-system-x86_64 \
  -name gpu-revive \
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
echo "等待 VM 启动 (~3分钟, 网络等待可能加时)"
```

### 步骤 3: 等待 boot + 设网 + SSH

```bash
sleep 180  # 等 boot (网络等待服务可能挂2分钟)

# 通过串口设网 (如果 SSH 不通)
sudo python3 $P/serial_drive.py $P/serial.sock <(cat <<'EOF'
WAIT:login:
SEND:mods
WAIT:Password:
SEND:mods-lab
WAIT:[$ ]
SEND:echo mods-lab | sudo -S dhclient enp0s2 2>/dev/null; echo NET_OK
SLEEP:5
SEND:echo NET_DONE
WAIT:NET_DONE
EOF
)

# 测试 SSH
sshpass -p 'mods-lab' ssh -p 22292 mods@127.0.0.1 'echo SSH_OK'
```

### 步骤 4: VM 内执行修复

```bash
sshpass -p 'mods-lab' ssh -p 22292 mods@127.0.0.1 '
echo mods-lab | sudo -S bash -c "
# 加载 MODS 内核模块
insmod /home/mods/mf215/driver/mods.ko 2>/dev/null
rmmod nouveau 2>/dev/null

# ★ 运行 MODS CPU-RM (清 WPR2) ★
cd /home/mods/mf215
timeout 90 ./mods -nc -m \"g_CheckVbiosSecurity=false;\" \
  gputest.jse -test 2 -testarg 2 LoopMs 500 \
  -skip_azalia_init -null_display -no_vga -no_gold \
  > /dev/null 2>&1

# 卸载 MODS
rmmod mods

# ★ 加载 nvidia 驱动 (GSP boot!) ★
modprobe nvidia
sleep 15

# 验证
nvidia-smi 2>&1 | grep -E \"GeForce|MiB\" | head -2
"
'
```

### 步骤 5 (可选): 关 VM 还 GPU 给宿主

```bash
# 注意: 关VM会触发设备复位, WPR2会回来!
# 只在需要在宿主上用GPU时才这样做
P=/home/user/rt_5090_project/vm_mods_lab/run-mods-dirty-try-20260929
echo quit | timeout 5 sudo socat - unix-connect:$P/mon.sock 2>/dev/null
sleep 8
sudo bash -c '
for d in 0000:01:00.0 0000:01:00.1; do
    echo $d > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null
    echo "" > /sys/bus/pci/devices/$d/driver_override
    echo $d > /sys/bus/pci/drivers_probe
done'
sleep 3
sudo modprobe nvidia
sleep 15
nvidia-smi  # 大概率失败(WPR2回来了), 需要重新走流程
```

## 方法B: 宿主直接复活 (待修复)

```
1. 编译 mods.ko (源码在 mod570_215_static/driver_extracted/driver/)
   已知兼容性问题:
   - screen_info 未声明 → 需 #include <linux/screen_info.h> 或 extern
   - rdmsr_safe_on_cpu 改名 → rdmsrq_safe_on_cpu (参数签名不同)
   编译: cd driver && make

2. 加载 + 运行 MODS
   sudo insmod mods.ko
   cd mod570_215_static/extracted/home/570.215
   sudo ./mods_sul5_host -nc -m 'g_CheckVbiosSecurity=false;' \
     gputest.jse -test 2 -testarg 2 LoopMs 500 \
     -skip_azalia_init -null_display -no_vga -no_gold

3. 卸载 + 加载 nvidia
   sudo rmmod mods
   sudo modprobe nvidia

当前卡点: "cannot hook interrupt" (error 0x41)
原因: 内核 7.2.6 的 MSI-X API 与 MODS 570.215 不兼容
```

---

## 故障排除

| 问题 | 原因 | 解决 |
|------|------|------|
| VM 里 nvidia-smi 显示 580 | apt 装了 580 驱动 | 正常, GSP 用的是 DKMS 610 固件 |
| MODS 报 "unload nvidia" | nvidia 模块还在 | rmmod nvidia_uvm nvidia (注意顺序) |
| MODS 报 "Invalid module format" | mods.ko 内核版本不匹配 | cd driver && make clean && make |
| VM 无网络 | dhclient 没跑 | 串口执行 dhclient enp0s2 |
| GPU rev ff | 设备掉总线 | 断电重启宿主 |
| WPR2 回来 | 断电/设备复位 | 重新执行完整流程 |
| 01:00.1 不在 vfio | snd_hda_intel 抢占 | unbind + override + probe |

---

## 耗时参考

```
宿主准备: ~30秒
VM 启动: ~3分钟 (含网络等待)
VM 内修复: ~2分钟 (MODS 90s + nvidia 15s)
总计: ~5-6分钟
```

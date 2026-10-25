# VM 实验环境使用指南

## 首次设置（重启后）

```bash
# 1. 卸载宿主 nvidia
sudo systemctl stop nvidia-persistenced lactd 2>/dev/null
for pid in $(lsof -t /dev/nvidia* 2>/dev/null); do sudo kill -9 $pid; done
sudo rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia

# 2. 绑定 GPU 到 VFIO
sudo /home/user/rt_5090_project/vm_mods_lab/vfio-bind-5090.sh

# 3. 启动 VM（console 输出到文件）
VM_DIR=/home/user/rt_5090_project/vm_mods_lab/run-gpu
sudo qemu-system-x86_64 \
  -name mods-lab-gpu \
  -machine q35,accel=kvm,kernel_irqchip=on \
  -cpu host -m 8G -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/ovmf/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=$VM_DIR/OVMF_VARS.gpu.fd \
  -drive file=$VM_DIR/gpu-overlay.qcow2,if=virtio,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -device vfio-pci,host=0000:01:00.0 \
  -device vfio-pci,host=0000:01:00.1 \
  -display none \
  -serial file:/tmp/vm-console.log \
  -monitor unix:/tmp/qemu-mon.sock,server,nowait \
  -daemonize

# 等 VM boot (~120秒)
sleep 120
tail -20 /tmp/vm-console.log
```

## VM 关闭与重启（正确流程）

```bash
# 1. 通过 monitor 优雅关闭 VM
echo "system_powerdown" | socat - unix:/tmp/qemu-mon.sock
sleep 15  # 等 VM 关机

# 2. 强制关闭（如果优雅关闭失败）
sudo pkill -f "qemu-system.*mods-lab-gpu"
sleep 5

# 3. 重置 GPU
sudo bash -c '
# 解绑 VFIO
echo "0000:01:00.0" > /sys/bus/pci/drivers/vfio-pci/unbind
echo "0000:01:00.1" > /sys/bus/pci/drivers/vfio-pci/unbind
# 移除
echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove
echo 1 > /sys/bus/pci/devices/0000:01:00.1/remove
# SBR
ORIG=$(setpci -s 00:01.1 3E.B)
setpci -s 00:01.1 3E.B=$(printf "%02x" $((0x$ORIG | 0x40)))
sleep 2
setpci -s 00:01.1 3E.B=$ORIG
sleep 3
# Rescan + 重绑 VFIO
echo 1 > /sys/bus/pci/rescan
sleep 3
echo "vfio-pci" > /sys/bus/pci/devices/0000:01:00.0/driver_override
echo "vfio-pci" > /sys/bus/pci/devices/0000:01:00.1/driver_override
echo "0000:01:00.0" > /sys/bus/pci/drivers_probe
echo "0000:01:00.1" > /sys/bus/pci/drivers_probe
'
sleep 2

# 4. 重新启动 VM（重复上面的启动命令）
```

## 重要注意事项

1. **绝不要直接 kill QEMU 后立刻重启 VM** — GPU 会进入脏状态
2. **每次 VM 结束后必须执行 GPU 重置流程**
3. **VM 内的驱动版本是 610.57.04（7月22日的版本）**
4. **SSH 未安装在 VM 中** — 使用串口 console 文件查看输出
5. **GPU overlay 中有 XDIG OVF 补丁** — 开机自动触发 K=33

## 已知问题

- VM 没装 SSH server（宿主无法 apt 安装，离线镜像无网络）
- 串口 PTY/socket 交互不稳定（只能用 file 输出）
- 需要通过修改 VM 镜像来预配置命令（mount → chroot → 修改 → 转换）

# nvflash 5.877 VM 实验完整记录

日期: 2026-09-30
状态: 读路径活着, 写路径死锁, 原因已定位

---

## 一、VM 环境搭建踩坑全记录

### 问题 1: "No NVIDIA display adapters found"

```
原因: GPU 挂在 PCIe 根总线 (00:03.0), nvflash 只枚举桥后设备
修复: QEMU 加 pcie-root-port, GPU 挂在 01:00.0

排错过程中排除的方向 (都不是原因):
  ✗ sysfs config/resource 内容差异 (bind-mount 冒充无效)
  ✗ header type MF 位 (multifunction=on 已修)
  ✗ ROM BAR 分配 (setpci 写入无效)
  ✗ /dev/mem MMIO 权限 (iomem=relaxed 已加)
  ★ PCI 拓扑 (根总线 vs 桥后) ← 唯一真因
```

### 问题 2: 音频功能 IOMMU 组

```
现象: "group 13 is not viable"
原因: 01:00.1 被 snd_hda_intel 抢占
修复:
  echo 0000:01:00.1 > /sys/bus/pci/drivers/snd_hda_intel/unbind
  echo vfio-pci > /sys/bus/pci/devices/0000:01:00.1/driver_override
  echo 0000:01:00.1 > /sys/bus/pci/drivers_probe

注意: 此问题反复出现, 建议写入自动化脚本
```

### 问题 3: guest 网络等待卡死

```
现象: "A start job is running for Wait for..." 无限等待
原因: 无NIC时 systemd-networkd-wait-online 挂起
修复: 必须加 NIC (即使不用 SSH):
  -netdev user,id=net0 -device virtio-net-pci,netdev=net0
```

---

## 二、nvflash 操作记录

### 读路径 (全部成功)

```
✓ --list: 找到 (10DE,2B85,1043,89E3)
✓ --version: Component 0xC001, Version 2.0.20.0
✓ --save: 完整 EEPROM dump (1,961,984 bytes)
  md5: 9c5de3ea94ff1ab7007207e03a619294
✓ --ecid: 不支持 (消费卡)
```

### 写路径 (全部失败)

```
✗ --update <自己的dump>: 零写入挂死 (md5前后一致)
✗ protectoff: 挂死
✗ offset读0x1DF000+: 挂死(guest console wedge)
✗ --display --offset: 需要文件参数(不是卡读取)
```

### 交互命令模式

```
进入: 发送无效命令(如 --zzz) → "Command format not recognized" → 按 Enter 列命令

命令列表 (部分):
  save b <file>       — 读EEPROM存文件
  compare k <file>    — 全内容比较
  verify h <file>     — 验证
  version v [file]    — 版本
  check c             — EEPROM支持检查
  list a              — 列出适配器
  protecton w         — 写保护
  protectoff r        — 解保护
  protectmain         — 主固件段保护
  protectlock         — 状态寄存器锁
  protectinfo         — 保护状态显示
  setpci <R.W>[=D]    — PCI配置读写
  offset [start]      — 起始地址
  display d [bytes]   — 显示EEPROM字节
  string              — ASCII显示
  updateuefi u <file> — 只更新UEFI段
  createlic           — 创建License占位

注意: 交互模式通过 stdin 管道驱动容易卡死
     建议用 script -qc 包裹
```

---

## 三、EEPROM dump 分析

### 基本信息

```
大小: 1,961,984 bytes (= 1.9MB, 标准VBIOS区域)
芯片总容量: 4MB (PUYA PY25Q32)
未读取区域: 0x1DF000-0x400000 (2.1MB, FSP私有区)
```

### 与 TPU 工厂镜像 (281814.rom) 的 diff

```
差异区块 (256B粒度):
  0x000000-0x000100 (256B, ~32字节差异) = VBIOS头部(构建变体)
  0x01d1200-0x01d1400 (512B, ~56字节差异) = PPID 序列号
  0x01def00-0x01df000 (256B, ~0差异) = 尾部(长度差导致)

结论: VBIOS 区域干净, 毒在 0x1DF000+ 的 FSP 私有区

PPID 内容: "PPID-ROG-ASTRAL-RTX5090-O32G-GAMING-2I3S#25086169830040 7\n"
```

---

## 四、nvflash 内部逆向

### FWUP (0x12) vtable

```
位置: VA 0xd360c8 (file 0x9360c8)
格式: 函数指针表 (8字节/槽)

  +0x00: 0x797110  校验MCTP帧
  +0x20: 0x793c3c  构造NVDM 0x12, cmd1
  +0x28: 0x793f52  cmd2
  +0x30: 0x794258  cmd3
  +0x38: 0x7963f8  cmd4
  +0x40: 0x79779a  cmd5 (读回复状态)
  +0x48: 0x79455e  cmd6
  +0x50: 0x79487a  cmd7
```

### 命令编码

```
消息格式: {MCTP头, NVDM头(0x12), 命令dword}
所有命令零载荷(vtable方法只append命令dword)
数据经设备对象层传递, 不在NVDM载荷中
```

### InfoROM 更新流程 (0x575d30)

```
打印 "InfoROM update start." 后:
  连续5次 call *0x130(%rax)  — 设备对象槽位
  + 1次 call *0x40(%rax)
= InfoROM 官方五步更新流

大vtable @VA 0xf646c8:
  +0x130 = 0x797c2d (fwupdate模块函数)
```

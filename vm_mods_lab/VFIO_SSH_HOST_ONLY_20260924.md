# 2026-09-24：当前 MODS/VFIO 客体的离线 SSH 管理接口

**仅适用于本次临时 VM** `/tmp/pi-mods-gb202-auth-ro.fP6yIU`。用户要求不再局限串口，但保留显卡 VFIO、隔离性、Quill/SSH 和散热。本次**没有运行 GPU 寄存器写、提高 MODS 权限或尝试网络授权**。原始实验环境的基础镜像和 `vm_mods_lab/user-data` 未改；修改只在此 VM 的一次性 qcow2 写层、QEMU 启动参数和本目录研究文档。

## 已配置

- 原 `user-data` 的 `ssh.install-server: false`：原客体确实没有 `sshd`。从 **本客体原版 Ubuntu 22.04.5 安装 ISO** `vm_mods_lab/ubuntu-22.04.5-mods-lab.iso` 离线提取恰好匹配客体 apt 索引的 `libwrap0_7.6.q-31build2`、`openssh-sftp-server_1:8.9p1-3ubuntu0.10`、`openssh-server_1:8.9p1-3ubuntu0.10`，用临时 CDROM 在客体离线安装；没有给客体配置互联网。
- 客体 `/etc/ssh/sshd_config.d/00-vfio-local.conf`：`PasswordAuthentication no`、`KbdInteractiveAuthentication no`、`PermitRootLogin no`、`AllowUsers mods`、`AuthenticationMethods publickey`；禁 agent/TCP/unix 转发、X11 和 tunnel。`sshd -t` 与 `sshd -T` 均验证生效。专用一次性 ED25519 公钥安装在客体 `~mods/.ssh/authorized_keys`。
- 客体 `/etc/netplan/99-vfio-local-ssh.yaml`：只给专用 `virtio-net-pci` MAC `52:54:00:00:52:92` 分配 `mgmt0=10.0.2.15/24`，无 DHCP、IPv6 或默认路由。实测 `ip -4 route` **只有** `10.0.2.0/24 dev mgmt0`。
- QEMU 启动时提供 `-netdev user,id=ssh-hostonly,restrict=on,ipv6=off,hostfwd=tcp:127.0.0.1:22292-:22` 与上述 MAC 的 virtio NIC。宿主 `ss` 实测仅 `127.0.0.1:22292` 监听，不对 LAN/公网开放；`restrict=on` 阻止客体主动访问外部，外加客体无默认路由。不会因此取得 NVIDIA 内部网络认证。
- 热插 NIC 曾被 Q35 `pcie.0` 拒绝（不支持 hotplug）；临时 QMP netdev 已即时清理。后来按序关闭原客体，宿主内核确认两 PCI 功能 VFIO `reset done`，使用**原同一写层磁盘**重新启动，静态加上受限 NIC；没有改变宿主 NVIDIA 绑定。

## 使用：从宿主终端（包括现有 Quill/SSH 会话）登录

```sh
ssh -F /dev/null \
  -i /tmp/pi-mods-gb202-auth-ro.fP6yIU/id_ed25519 \
  -p 22292 \
  -o IdentitiesOnly=yes -o IdentityAgent=none \
  -o BatchMode=yes \
  -o UserKnownHostsFile=/tmp/pi-mods-gb202-auth-ro.fP6yIU/known_hosts \
  mods@127.0.0.1
```

密钥 `/tmp/pi-mods-gb202-auth-ro.fP6yIU/id_ed25519` 权限 `0600`、仅宿主本地文件，`known_hosts` 针对此本地端口。宿主重启/清理 `/tmp` 或销毁该 disposable VM 后，此连接自然失效；**不要**把它误认为基准镜像中永久启用了 SSH。

首次连接已实测 `PI_SSH_AUTH_OK`、客体用户 `mods`、`mgmt0=10.0.2.15/24`、`systemctl is-active ssh=active`、禁止密码/root/允许用户=mods/仅公钥。MODS 在 SSH 热改之后**没有重新启动**；此前 `SecurityUnlockLevel=1` 属于重启前独立、完全无网客体中的只读实测。新 VM 的网络仍受限、但若研究要断言新进程的确切等级，必须另作授权的只读实测，不从宿主侧网络拓扑臆测。

## 边界与恢复

- SSH 仅改善运维便利，不证明 CONFIG1 可直接改写，也不提供或绕过设备 PLM、固件权限、显存更新/训练流程。
- 当前 GPU 和音频功能继续绑定 `vfio-pci`；`hsr-path-probe.service` 仍冻结，Quill/SSH 及 BIOS 自动冷却保持。退出时先停/关闭 VM、确认 VFIO reset，再按现有 VFIO leave 流程恢复宿主 GPU/音频、水冷控制和桌面服务，不因网络变动改变原有回退顺序。
- 以后若启动新的一次性 overlay，应明确按需要安装 SSH 并带受限网卡；不要默认把此 overlay 或密钥复制到其它客体。

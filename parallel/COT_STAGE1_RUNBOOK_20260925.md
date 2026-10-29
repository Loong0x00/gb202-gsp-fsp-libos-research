# COT-optional 判定实验 (stage 1) — 执行记录

目的:在被直通的客体里,把驱动的 COT 发送关掉(`RmDisableCotCmd=1`),看**设备是否仍然把 GSP-RM 启起来**。
判据:能起 ⇒ 这层认证对该路径**可选**(170HX 形状的门);起不来 ⇒ 认证是硬性的,并留下错误码。

前提(已核实):
- 宿主:`enter-live` → 解绑 nvidia → 绑 vfio-pci → arm → 启动 `rtx5090-vfio-lab.service`(QEMU,专用 GRUB 亦可)。
- 客体:`arch-gpu-base.qcow2`(只读基底 + 每次新 overlay),`nvidia-open-dkms` + `linux-headers` 已在,SSH:2222,key `~/.ssh/rtx5090-vfio-lab`,user 有 NOPASSWD sudo。
- 旋钮字符串存在于驱动二进制:`RmDisableCotCmd`(与 `RmDisableSec2` 同区),`RmDisableFspFuseErrorCheck`(语义有自带说明:"FSP's fuse error detection status check during boot is disabled using the regkey")。
- 恢复链:`systemctl stop rtx5090-vfio-lab.service`(QMP quit → stop-post → recover) → `leave-live --restore-display`;兜底 `nvidia-reset.sh` / `nvidia-sbr-preserve-processes.sh`。

客体脚本:guest/run-cot-stage1.sh(实验)、guest/run-cot-restore.sh(复原)。
产物:客体 `/home/user/cot_stage1_<ts>/`,随后取回宿主 `vfio_production_lab/results/`。

不在本次范围:stage 2(把 FMC 镜像翻一个字节 + 重建模块)——需要在客体里拿到驱动源码并重编,另开。

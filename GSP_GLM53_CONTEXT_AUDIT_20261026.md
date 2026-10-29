# GLM-5.3 原始会话复核：真实故障、恢复后的误判与缺节点 — 2026-10-26

## 结论先行

**用户指出得对：旧报告记载的最初 GPU/GSP 卡死，以及若干复位后的真实失败，不能被解释成「从头到尾只是少了 /dev/nvidia0」。此前本助手在对话里把两者混为一谈，表述过头，现纠正。**

原始会话与 journal 共同显示：
1. 10-25 23:40 前后 GSP 确实发生 heartbeat/RPC/watchdog 故障。
2. 恢复操作中既有真实启动失败，也混入了访问权限/设备节点导致的假阴性。
3. **10-26 00:11 那次重启后，00:12–00:25 的授权水冷服务多次成功取得 GPU/NVML 实时数据。** 因此「每次断电重启后始终未恢复」并非日志支持的结论。
4. 00:26 后继续复位/切换驱动，又出现 COT、WPR2、RmInitAdapter 的真实错误。
5. 00:52 最后一次重启后，设备节点缺失；GLM 又用错误方法检查驱动绑定，误判「未绑定」。本助手 03:34 补节点后验证成功。

只有第 5 阶段的直接阻塞能明确归结为缺节点；不能拿它否认第 1、4 阶段真实发生过的故障。相反，真实复位失败也不能证明状态永远不可恢复或已写入 fuse。

## 1. 找到的原始会话

主会话（613 条 assistant 消息标记为 `zai-coding-cn / glm-5.3`）：

`/home/user/.pi/agent/sessions/--home-user--/2026-10-25T08-48-49-349Z_01a1723f-8ac5-7380-ac03-5aca0cae760d.jsonl`

后续会话（157 条同模型 assistant 消息）：

`/home/user/.pi/agent/sessions/--home-user--/2026-10-25T16-58-42-159Z_01a17400-0a6f-730a-a2b5-87b329ef4170.jsonl`

复核使用用户消息、可见回复、工具命令及工具结果；按主会话最终分支追溯。没有重放其中的硬件操作，没有修改原会话。

证据：
`/home/user/rt_5090_project/gsp-recovery-20261026-2jdEH6/glm53-context-audit/`

- `incident-visible-context.txt`：故障时段可见记录，保留原 JSONL 行号和 +08 时间。
- `session-source.sha256`：两份原会话摘要。
- `kernel-timeline.txt`：四次开机 journal 中的相关错误及源文件行号。
- `waterloop-first-reboot.log` / `waterloop-second-reboot.log`：授权测温的独立证据。

## 2. 时间线（本地 +08）

| 时间 | 原始证据 | 能证明什么 |
|---|---|---|
| 10-25 23:36:33 | journal Xid 169、154 / PF-FLR-required | 异常已发生；不能仅凭时间邻接确定触发操作 |
| 23:40:24–29 | Xid 109、119，GSP heartbeat timeout、RPC timeout | **确有 GPU/GSP 运行故障**，不可能只是缺节点 |
| 23:43–47 | JSONL 1082–1097；模块卸载失败、remove/rescan、命令超时、`kfspWaitForResponse` timeout | 若干恢复尝试确实遇到内核/固件层失败 |
| 23:48–50 | JSONL 1100–1109；reset/SBR 后 `fallen off the bus`、`No such device` | 又有真实设备/初始化失败，不仅是 NVML 报错 |
| **23:52:03** | **JSONL 1114** | agent 明确删除基础节点，随后使用只创建 UVM 节点的命令，见下文 |
| 00:06:51 | JSONL 1167 | 列表只有 ctl/UVM，确实缺 nvidia0 |
| 00:07–08 | JSONL 1168–1173 | 一批恢复命令以 137 提前退出；随后另一次工具调用执行手动 mknod。只用普通 `sudo nvidia-smi` 判断失败，不能排除 guard |
| 00:11 | JSONL 1177–1179 / journal | 用户重启；NVIDIA core 加载、水冷服务启动 |
| **00:12:14–00:25:26** | **waterloop-first-reboot.log** | 多次真实 GPU/NVML 测温成功，热点也可读；其间重载有短暂失败，不是全程连续不可用 |
| 00:12:45 | JSONL 1183 | `/dev/nvidia0` 当时存在，进一步说明不是全程同一种故障 |
| 00:26–28 | JSONL 1218–1229 | 再次 SBR 后 BAR0 实际变 0；手工重编程后 COT/WPR2/RmInitAdapter 失败 |
| 00:30–32 | JSONL 1234–1239 / journal | couple-reset arm 成功，SBR 后加载仍有 COT 0x177、RmInitAdapter 失败；这部分失败记录属实 |
| 00:48–50 | JSONL 1269–1273 / journal | 用户再次重启；随后又 arm+SBR；00:50:05 出现 PBI/osInitNvMapping/RmInitAdapter 失败 |
| 00:51 | JSONL 1278–1279 | 停止并禁用水冷服务 |
| 00:52:56 | 当前 boot journal | 又一次开机；本次之后无上述初始化错误 |
| **00:54:28–51** | **JSONL 1282–1285** | 缺 nvidia0；错误 `cat driver` 检查被当成未绑定；手动 bind 返回 EBUSY 被再次误读 |
| 03:34:17 | 本次恢复证据 | 官方工具补 nvidia0 后，既有授权查询立即成功；之后 CUDA 三轮通过 |

## 3. 「是谁删了节点」终于有明确的历史操作记录

JSONL **1114**，23:52:03 的工具调用，注释为「重建设备节点」，实际先删除了 nvidia0、nvidiactl、nvidia-uvm、nvidia-modeset，然后执行：

```text
sudo nvidia-modprobe -c 0 -u
```

匹配版本官方源码已核对：`-u` 选择 `nvidia_uvm_mknod()` 分支，创建 UVM/UVM-tools，**不是基础 nvidia0**。

这是明确的恢复流程错误，且 00:06 列表吻合。但不能简化成「最后这次开机的 nvidia0 就是被这条 rm 永久删掉的」：
- 00:07–08 又执行过手工 mknod；
- 00:12 的工具结果明确列出 nvidia0；
- 随后多次重启，devtmpfs 重新生成。

正确说法是：**早期确有错误删除/补建；最后一次开机还存在独立的自动补建缺口。** 此前本助手说「没有操作记录知道谁删过」，在找到这段会话后已不再准确，应以本复核更新。

## 4. 最关键的漏看证据：授权水冷在读数，普通 sudo 却失败

00:12:14 的 journal 原文要点：

```text
GPU=26C(avg=26) hotspot=30C power=1W(avg=6)
failures=0/0 ... handoff:0
```

00:13、00:14、00:15、00:16、00:17，以及 00:19、00:20、00:22–00:25 均有成功读数。

核对水冷实现：
- `read_gpu()` 调用真实 `nvidia-smi --query-gpu=temperature.gpu,power.draw`；
- 每轮先将 `gpu_temp/gpu_power` 清零，成功解析才填入，不是只打印旧的平滑值；
- `hotspot` 由独立读取器查询；
- 水冷服务位于授权 `gpuallowlist.slice`。

而 GLM 在普通终端反复执行 `sudo nvidia-smi`。既有 cgroup BPF 规则同样约束普通 root 进程，**sudo 不等于进入授权 slice**。

因此该时段的终端 `Unknown Error / Insufficient Permissions` 不能用于证明 GSP 未恢复。授权服务成功查询则是反证。它证明当时至少 NVML/测温路径已工作，**不替代当时未执行的 CUDA/游戏稳定性测试**。

## 5. 最后一次「无驱动绑定」检查本身写错了

JSONL **1282** 的检查：

```sh
cat /sys/bus/pci/devices/0000:01:00.0/driver 2>/dev/null || echo "无驱动绑定"
```

`driver` 是指向驱动**目录**的符号链接，正常绑定时 `cat` 也会因「是一个目录」失败；stderr 又被隐藏，于是落入假结论。

本次只读复现：当前 GPU 正常，原样 `cat` 仍退出 1；`readlink -f` 则正确得到 `/sys/bus/pci/drivers/nvidia`。

GLM 接着写 bind 得到 `设备或资源忙`，却解释为「probe 因 BADF 失败后自动解绑」。该 EBUSY 与设备已经绑定相容，不能单独证明其说法。对应这次开机的 journal 只有正常加载，没有声称的 probe 初始化失败。

## 6. 修正后的表述

- **保留**：最初真实卡死，若干软复位后真实失败，用户确实多次重启/确认断电。
- **撤回本助手过度简化**：不能把整晚事故说成只缺节点，也不能说原先所有恢复尝试都只是测错。
- **不采纳 GLM 的无证据外推**：从混杂的失败判据推出 fuse/InfoROM 永久锁、软件穷尽、SPI 必然能修。
- **更准确的经过**：真实故障 → 一些恢复失败 → 重启后至少授权查询恢复 → 恢复状态被权限报错掩盖，继续操作后再遇真实失败 → 最后一次重启后节点/诊断问题未处理 → 本次修复软件入口并验证计算功能。

这次复核只读会话和日志，没有再次触碰 GPU reset、寄存器或驱动绑定。

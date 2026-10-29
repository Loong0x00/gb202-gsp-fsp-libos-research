# DLSS5 通用控制器（Linux / Wine / Proton）

这是一个面向**已安装 DLSS5/Feature18 后端**的 GTK4/libadwaita 控制器。它不要求特定游戏，也不要求替换 NVIDIA 签名 DLL。

## 通用模式

启动只读取并校验现有配置，不扫描游戏树、不准备/复制组件仓、不中途回写 `profiles.json`。需要发现目标时，用户显式点击“扫描已安装 DLSS5”或使用 `--scan-installed`，再检查以下证据：

- `01-dlss5-post-service.dll` / `.addon64`；
- `00-dlss5-vk-bridge.addon64`；
- `renodx-dlss5.addon64`；
- `nvngx_dlssnr.dll`；
- `.dlss5-linux/install.json` 或现有控制块。

显式扫描发现后建立“控制模式”目标。加载已有配置时也会按同目录证据把 Post Service/native 归一化为控制模式；旧 `control_only=false` 不能让历史 ReShade 安装器覆盖 Post Service。只要后端支持任一接口即可使用：

1. **通用实时协议 D5LC v1**：游戏目录 `.dlss5-linux/live-control.bin`，固定 72 字节、FNV-1a 校验、原子替换；支持运行时 `live-status.bin` 回读。
2. **原生流水线扩展 D5RP v1**：独立的 32 字节 `pipeline-control.bin` 控制 NR 的 `post`/`pre_sr` 顺序与 1–10 个独立层。只有实际 native runtime/host 证据和有效静态能力文件同时存在时才开放；管理器不会为旧后端制造能力。
3. **RenoDX 兼容接口**：只在实际检测到 RenoDX 为当前后端时同步维护 `ReShade.ini` 的 `[RenoDX.DLSS5]` 段。原生控制路径即使残留旧 INI 也不会改写它。

owned Post Service 会在 `NeuralUplift=0` 时透明保留原生 DLSS 输出，重新开启时强制 temporal reset。HSR 版本还会在开始/加载界面自动停用 Feature18，进入 3D 场景后恢复。

## 可调参数

- Feature18 总开关、NR 上采样、模型预设、自然/电影风格；
- NR 位于重建后（`post`）或普通 SR 前（`pre_sr`），以及 1–10 个真正独立 NR 层（具体上限按后端能力）；
- 神经渲染强度、局部色调、局部结构、皮肤结构；
- 自动蒙版、UI 修正；
- 深度约定、运动矢量 X/Y 倍率；
- 纸白、HDR 转移和原始颜色保留。

参数均按后端 ABI 范围钳制。`NR 上采样`属于实验性 create-contract 选项，建议改动后重启游戏。D5RP v1 的顺序/层数目前按进程冷启动锁存；界面会区分“实际已应用”“请求待重启”“不支持”“阶段门关闭”“预算拒绝”“状态过期/不匹配”。D5LC 的 72 字节回执不能确认排序或层数。

`pre_sr` 只用于普通 SR。新鲜运行状态为 RR 时界面会禁用并由核心拒绝该请求；控制器不会自动修改游戏的 RR 配置。旧配置仍可保存 `post/1` 等偏好，但旧后端只收到原有 D5LC 标量，不会收到 D5RP，也不会被显示为已生效。

## 使用

```bash
# 图形界面
dlss5-linux

# 扫描并登记全部已安装后端
dlss5-linux --scan-installed

# 应用保存的参数：默认明确请求 D5LC + D5RP
dlss5-linux --apply all
dlss5-linux --apply "崩坏：星穹铁道"

# 旧后端只要求标量时，显式跳过 D5RP
dlss5-linux --apply "鸣潮" --scalars-only
```

`--apply` 只有所有被请求通道都确认时返回 0；排队、待重启、不支持、过期/不匹配等部分结果返回 3；硬错误返回 1；找不到目标返回 2。输出会分别说明 D5LC/D5RP 是否已写入、是否已回执/实际应用。`--scalars-only` 明确表示不请求 D5RP，避免把缺少 native 部署悄悄当成完整成功。

配置保存在 `~/.config/dlss5-linux/profiles.json`。若配置库 JSON/schema 损坏，GUI 会保留原文件并显示错误，不会用默认配置覆盖。控制文件按游戏隔离，不加载来源不明 DLL，也不修改网络配置。

原有的原子备份安装/恢复功能仍保留给真正的旧版安装目标；Post Service/native 控制目标在 GUI 与 `install_profile()` 核心入口都禁止进入历史 ReShade 安装器。前端只实现协议管理与如实状态展示；它不会部署尚未安装的 native backend，因此缺少 native runtime/host + 有效能力文件时，顺序和层数保持禁用，仅可用 D5LC 标量。

已审核的已知启动交接不使用 shell 字符串：CP2077 走 `/usr/bin/steam steam://rungameid/1091500`；legacy 鸣潮走现有 `/home/user/.local/bin/wuwa-dlss5-6k-launch`，检测到 native 文件时因该 wrapper 未获 native 证明而故障关闭；HSR 只走 `/usr/bin/python /home/user/rt_5090_project/astral_pin_monitor/astral_hsr_guard.py --run-dir <独立用户状态目录>`，不会 bare-Wine 绕过 guardian。进程创建成功仅显示“启动器已交接、游戏状态未确认”，不冒充游戏已经活动。

## 已验证包的原生迁移与回滚（CP2077）

“DLSS5 设置 → NR 顺序与独立层”现在提供 **预览原生迁移 / 原生回滚**。
只读预览先校验固定发布包、源码清单、相同 DLL 的真实 GPU 记录及冷启动状态；
勾选明确确认后才修改文件。安装不代表 NR 已执行，仍以游戏内新鲜状态为准。
原生回滚提供事务选择、只读预览、第二次确认；不走旧 ReShade 恢复器。

安装器使用 `nr_runtime_next/releases/native-pc4-cp-20260910-084731/` 的固定包，
不跟随开发目录重编译。6K DLAA 的预算限制仍保留，不自动降画质。
鸣潮和星铁尚未开放永久原生迁移，不能通过解除灰色控件冒充支持。

Main 已在真实 CP 目录通过真实 GTK 回调完成一次临时安装和回滚（没有启动游戏），
验证原生静态能力安装后控件开放、回滚后关闭，所有目标/受保护文件内容恢复。
该测试不替代新版本的游戏/GPU验收。运行中的旧控制器进程需关闭重开才能加载新代码。

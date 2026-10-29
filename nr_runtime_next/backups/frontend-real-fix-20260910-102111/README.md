# DLSS5 通用控制器（Linux / Wine / Proton）

这是一个面向**已安装 DLSS5/Feature18 后端**的 GTK4/libadwaita 控制器。它不要求特定游戏，也不要求替换 NVIDIA 签名 DLL。

## 通用模式

启动时会在 Steam、Honkers Railway Launcher 和常用游戏目录中静态扫描以下证据：

- `01-dlss5-post-service.dll` / `.addon64`；
- `00-dlss5-vk-bridge.addon64`；
- `renodx-dlss5.addon64`；
- `nvngx_dlssnr.dll`；
- `.dlss5-linux/install.json` 或现有控制块。

发现后自动建立“控制模式”目标。只要后端支持任一接口即可使用：

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

# 应用保存的参数
dlss5-linux --apply all
dlss5-linux --apply "崩坏：星穹铁道"
```

配置保存在 `~/.config/dlss5-linux/profiles.json`。控制文件按游戏隔离，不加载来源不明 DLL，也不修改网络配置。

原有的原子备份安装/恢复功能仍保留给旧配置；自动发现的控制模式目标只写配置和受支持的控制块，不替换游戏运行库。前端只实现协议管理与如实状态展示；它不会部署尚未安装的 native backend，因此仅保存配置不代表新后端已经工作。

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

1. **通用实时协议**：游戏目录 `.dlss5-linux/live-control.bin`，固定 72 字节、FNV-1a 校验、原子替换；支持运行时 `live-status.bin` 回读。
2. **RenoDX 兼容接口**：同步维护 `ReShade.ini` 的 `[RenoDX.DLSS5]` 段。

owned Post Service 会在 `NeuralUplift=0` 时透明保留原生 DLSS 输出，重新开启时强制 temporal reset。HSR 版本还会在开始/加载界面自动停用 Feature18，进入 3D 场景后恢复。

## 可调参数

- Feature18 总开关、NR 上采样、模型预设、自然/电影风格；
- 神经渲染强度、局部色调、局部结构、皮肤结构；
- 自动蒙版、UI 修正；
- 深度约定、运动矢量 X/Y 倍率；
- 纸白、HDR 转移和原始颜色保留。

参数均按后端 ABI 范围钳制。`NR 上采样`属于实验性 create-contract 选项，建议改动后重启游戏。

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

原有的原子备份安装/恢复功能仍保留给旧配置；自动发现的控制模式目标只写配置和控制块，不替换游戏运行库。

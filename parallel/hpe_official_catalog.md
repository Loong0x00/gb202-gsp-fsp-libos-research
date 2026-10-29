# HPE RTX PRO 6000 Blackwell VBIOS 98.02.9E.00.01：官方目录核验

日期：2026-07-22（Asia/Singapore）

## 范围与结论

本次只浏览 HPE 官方域名的公开页面和搜索索引；没有点击下载按钮、没有请求 RPM
文件正文、没有运行任何二进制，也没有访问 GPU。

**官方命中（FACT）：** HPE Support Center 有一条与目标版本精确对应的 Linux
固件记录：

- 页面：[NVIDIA RTX PRO 6000 Linux VBIOS Flash Utility](https://support.hpe.com/connect/s/softwaredetails?collectionId=MTX-932a73f6d33b4c5c&language=en_US)
- `collectionId`：`MTX-932a73f6d33b4c5c`
- 版本：`98.02.9E.00.01`
- 发布日期：`Apr 24, 2026`
- 类型：`Firmware - Video BIOS`
- 升级级别：`Recommended`
- 重启要求：`Required`
- 页面说明：这是 NVIDIA RTX PRO 6000 的首个 VBIOS flash utility 版本。

HPE 的[中文页面](https://support.hpe.com/connect/s/softwaredetails?collectionId=MTX-932a73f6d33b4c5c&language=zh_CN)
显示相同版本与 `2026-04-24` 日期，可作为语言无关的交叉核验。

## 未能从 HPE 公开索引核验的字段

截至本次查询，HPE 官方可检索页面没有暴露以下字段：

- 精确文件名
  `NVIDIA_RTX_PRO_6000_Blackwell_96GB_PCIe_GPU_VBIOS-98.02.9E.00.01-1-0.x86_64.rpm`
- 文件大小
- HPE 发布的 SHA-256/checksum
- RPM 或独立文件签名资料
- `downloads.hpe.com` 的直接下载 URL

这是一项**有界负结果**：只能说上述字段没有出现在本次可公开检索、可直接读取的
HPE 页面/目录中；不能据此断言 HPE 下载弹窗、登录后接口或传输端完全不提供这些
元数据。为遵守本任务边界，本次没有触发“Download Software”按钮或抓取文件。

执行过的精确搜索包括：

```text
site:support.hpe.com "98.02.9E.00.01"
site:downloads.hpe.com "98.02.9E.00.01"
site:hpe.com "NVIDIA_RTX_PRO_6000_Blackwell_96GB_PCIe_GPU_VBIOS"
"NVIDIA_RTX_PRO_6000_Blackwell_96GB_PCIe_GPU_VBIOS-98.02.9E.00.01-1-0.x86_64.rpm"
site:downloads.hpe.com/pub/softlib2/software1/ "RTX_PRO_6000_Blackwell_96GB"
"MTX-932a73f6d33b4c5c" "98.02.9E.00.01"
"NVIDIA RTX PRO 6000 Linux VBIOS Flash Utility" "SHA-256"
```

其中只有 HPE Support Center 的版本页面得到精确官方命中；精确 filename、checksum
和 `downloads.hpe.com` 目录查询没有结果。

## 与本地样本的严格区分

项目中现有同名 RPM 的静态测量值为：

```text
size    8,471,656 bytes
SHA256  183c76f5ea0d5e72796fe1cf2f1ce5d8c31796e3f6d7876c19121a4e41784fe8
```

这些是**本地文件事实，不是 HPE 官方公布的 checksum**。因此，官方页面目前能够
证明“该产品/版本/发布日期确实存在”，但仅凭公开目录还不能把本地 RPM 的每一个
字节与 HPE 发布物做外部密码学认证。

## 容易混淆的另一条官方记录

HPE 还有一个 Windows 项目：[NVIDIA RTX6000 Pro BSE Windows VBIOS Flash Utility](https://support.hpe.com/connect/s/softwaredetails?collectionId=MTX-4f8d2d9292af4fa2&language=en_US)。
它也列出 `98.02.9E.00.01`，但发布日期为 `2026-02-17`，是 Windows/BSE 页面，
不能用它替代上述 Linux RPM 的目录证明。


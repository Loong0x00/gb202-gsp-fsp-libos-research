# 610.57.04 → 615.78.08：公开 LibOS 目录只读核对

依据裸仓库 `/home/user/gsp-615-analysis/compare.git` 的 `v610`→`v615`（`git diff --name-status`），并以 `/tmp/vix-review.HMfoyk/nvidia-open-{610.57.04,615.78.08}` 源码副本复核。限定关注文件如下：

## 有变化

- `src/common/uproc/os/common/include/libos_log.h`：日志 dispatch 元数据指针转换前新增 `NvUPtr` 中间转换，避免直接把指针转 `NvU64`；raw/variadic 两分支都改了。615 行 292–302（转换见 296、301）。
- `src/common/uproc/os/libos-v3.1.0/lib/libdwarf.c`：NVRM 分支 `<stddef.h>` 换成 `<nv_stddef.h>`；版权年份更新。615 行 1–3、24–28。
- `src/common/uproc/os/libos-v3.1.0/lib/liblogdecode.c`：
  - `<stddef.h>` 换为 `<nv_stddef.h>`（NVRM 行 27–30、通用 include 行 74–80）；版权年份更新。
  - 两处合并日志 task 前缀拼接改用 `snprintf`，以 resolver 前缀长度定位 suffix（行 542–550、636–644），替代固定取第五字符及无界 `sprintf`。
  - 元数据错误日志可抑制（`_getLoggingMetadata` 行 1140、1174–1190）；读取记录遇坏 metadata 后按 NvU64 槽逐项回退重同步，限制扫描到 `LIBOS_LOG_ENTRY_MAX_SIZE`，同步缓冲区仍不尝试跳过（行 1235–1359）；回退后成功及 wrap 情况有相应诊断（行 1389–1404）。这是日志记录解码/恢复逻辑，不是内核调度器。

## 未变化（所核文件）

- `src/common/uproc/os/common/include/libos_init_args.h`：两版本逐字节相同。
- `src/common/uproc/os/libos-v3.1.0/lib/libelf.c`：两版本逐字节相同。

裸仓库该范围 `name-status` 仅列出上述三个修改文件；指定目录及文件统计为 70 insertions / 35 deletions。此结论仅关于公开源码差异；LibOS v3.1.0 目录相同或其中多数文件未变，不能据此推断实际固件内容未变。

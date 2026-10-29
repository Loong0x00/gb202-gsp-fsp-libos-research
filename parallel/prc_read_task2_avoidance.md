# `-fsp_prc_read` 与 task 2：原厂“只读且跳过 floorsweep 初始化”路径审计

## 范围与结论

本报告只审计 MODS 570.151 的解码 JavaScript 与已有的小窗口原生控制流；没有
运行 MODS、没有访问 GPU，也没有构造错误路径或实时命令。

结论是：**没有找到一个原厂参数组合，能在普通 GB202 首次初始化中仅执行
`-fsp_prc_read`，同时可靠跳过 floorsweep task 2。** PRC reader 自身没有
host-visible write/reset，但完整 `Gpu::Initialize` 成功路径随后仍会进入
`ProcessFloorsweepingArgs`。默认 GB202 FSP 路径的首次 pass 会发送 task 2；
`SkipFspFs` 只适用于 d0/dc 已经处于开放常量状态的进程阶段，并不能从普通
零售初始状态创建一个“纯读”入口；`SkipFsPlmCheck` 更不是抑制开关。

这仍然只是 host ELF 的静态结论。FSP 内部副作用和固件状态机不可见，因此它
不能把 MODS 运行归类为对当前桌面显卡安全。

## 1. 前端顺序

- **FACT：** `gpuargs.js:395` 把 `g_SkipFsPlmCheck` 默认设为 false，`:403`
  把 `g_SkipFspFs` 默认设为 false。
- **FACT：** `gpuargs.js:1667` 将 `-skip_fsp_fs` 描述为跳过向 FSP 发送 FS PRC
  packet、改由 MODS 完成 FS；`:1718` 将 `-skip_fs_plm_check` 描述为跳过发送
  FSP floorsweep API 前的 PLM 检查。
- **FACT：** `EarlyInitCallback` 在 `gpuargs.js:13184..13206` 把两个非默认值写入
  `JsGpuSubdevice` 属性。它们是初始化策略，而不是 `-fsp_prc_read` reader 的
  局部选项。
- **FACT：** 已有 `Gpu::Initialize` 数据流证明 early PRC read map 在
  `0xda39ba..0xda39da` 先执行；成功后才在 `0xda3c5f` 调用
  `ProcessFloorsweepingArgs`。所以 reader 本身不写，不等于整个初始化不会随后
  发送 task 2。

## 2. `SkipFspFs` 的实际门槛

通用 dispatcher `0x1095e50`：

- **FACT：** `0x1095e7b` 将本地 `doFsp` 初始化为 0；正常支持 FSP 且
  `SkipFspFs==0` 时，`0x109603d` 将其置 1。
- **FACT：** `SkipFspFs==1` 改走 `0x1096088 -> 0x1095cb0`。该 helper 只读取
  d0/dc 的 RegHal 值并与常量 `0xf` 比较；两者都满足才让 `doFsp=0` 继续，
  否则在 `0x1095d90` 报 `Cannot use -skip_fsp_fs as the PLMs are raised` 并
  返回 `0x308`。该 helper 没有 PLM setter。
- **FACT：** helper 开头还读取 `SkipFsPlmCheck`；若它与 `SkipFspFs` 同时为真，
  `0x1095db8` 打印二者不能同时使用并返回 `0x308`。日志把前一个参数拼成
  `-skip_fsp_plm_check`，而公开参数表是 `-skip_fs_plm_check`；这是二进制文本
  中的命名不一致，不改变属性数据流。
- **FACT：** GB20x `+0x520 = 0x106c4e0` 在 `0x106c4f1` 直接测试传入的
  `doFsp`。为 1 时于 `0x106c587` 发送 task 2/subobject 1；为 0 时走
  `0x106c5c0` no-send 分支。该 GB20x sender 没有读取 `SkipFsPlmCheck`。

因此，`SkipFspFs` 是“PLM 已经开放时不要重复发送”的路径，不是从普通初始
状态安全绕开 task 2 的路径。故意依靠其 `0x308` 失败也不是可用方案：那会使
`Gpu::Initialize` 走错误出口，无法证明此前初始化动作已回滚，更不能保证脚本
还能继续到 PRC read 的预期输出。

## 3. `SkipFsPlmCheck` 的方向

- **FACT：** Hopper 同槽 task-2 实现 `0x1094990` 只有在 `doFsp!=0` 时进入。
  它于 `0x10949c8..0x10949ec` 读取 `SkipFsPlmCheck`。
- **FACT：** 属性为真时，`0x1094a0b..0x1094a38` 直接调用 task-2 sender；为假
  时才从 `0x1094a50` 开始检查 `0x8200d0/0x8200dc` 是否已经等于开放常量，
  以决定是否跳过重复发送。
- **FACT：** 在 GB202/GB20x 的 `0x106c4e0` 实现中没有这项检查；发送与否由
  dispatcher 计算的 `doFsp` 决定。

所以该参数的可见语义是**绕过发送前的 PLM 状态检查**，在适用的旧/同族路径上
反而更容易让 task 2 被发出；它不能把 PRC read 变成不初始化 floorsweep 的
只读模式。

## 4. 对安全候选的影响

| 命题 | 结论 |
|---|---|
| PRC reader 自身是否请求 host reset | 没有发现；见 `prc_read_noreset_audit.md` |
| 普通 GB202 首次初始化是否仍可能发送 task 2 | 是，默认 FSP 成功路径会发送 |
| `-skip_fsp_fs` 能否从普通初态安全避免 task 2 | 不能；它要求 d0/dc 已开放，否则初始化失败 |
| `-skip_fs_plm_check` 能否抑制 task 2 | 不能；Hopper 上方向相反，GB20x sender 不消费它 |
| 是否存在 stock `PRC-read-only / no-task2` 模式 | **未找到** |

当前可保留的较窄候选仍是：在一个已经由正常无参数 task 2 成功准备、且没有
reset 的同进程阶段内，后续 PRC read 或 direct writer 是否能观察/使用该窗口。
但 d0/dc/f8 的实际值、FSP 是否自动收权和 GPU 初始化副作用都仍未知；这不是
当前桌面 5090 上的执行建议。

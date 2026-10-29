# GB202 显存时序读取：离线取证（2026-09-23）

## 边界

只读检查本地 MODS ELF、NVIDIA 公开文档、5090 E1 ROM；另从 `https://github.com/b00nz/mVolt/releases/latest/download/mVolt%2B.exe` 下载 mVolt+ **0.47.2** 到 `/tmp/pi-mvolt-plus-timing-research.exe` 作静态 PE/Capstone 分析，文件 SHA256 `7bb4710cd6494aebcc133ef4dbee107de08fce98321834048e1c1a30f96ebc3b`。没有执行这个程序或 MODS，没有访问 GPU MMIO、刷写 ROM、修改驱动。mVolt+ 是 Windows 程序；其代码分析不是 Linux 主机实时测量。

**MODS 版本边界：**下文的 MODS VA 来自 SHA256 `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf` 的旧静态样本；隔离 VM 里曾用的 570.215 样本 SHA256 `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856`，不是同一构建，不能直接套旧地址/绑定结论。mVolt+ 证据又来自**另一个 Windows 程序**，不能冒充 MODS 570.215 的实现。

## 1. 直接证明的 live-read 路线（mVolt+ 0.47.2，**不是 MODS**）

- PE VA `0x1401474d9..0x14014771f` 构造批量读取请求，开头包含 `0x11808`、`0x12` (18 项)；请求中的地址依次为 `(0x900290+0x4000*i, 0x900294+0x4000*i)`，`i=0..7`，以及 `0x9a0290/0x9a0294`。这是八组和单独广播行，不能把广播行当成八组均值。
- PE VA `0x140147730` 调用 `0x140146630`，返回后 `0x140147762` 调用解包器 `0x14011df70`。`0x140146630` 调用另一个函数指针并检查返回；目前尚未证实这个指针的公开 API 名称。不能仅由请求结构推断 MODS 支持相同接口。
- `0x14011df70` 确认消息大小 `0x1808`、标记 `0x11808`、条目数 `0x12`，解包18条32位寄存器结果；`0x14011e1fa..0x14011e23c` 直接按位解析一对返回值：`RC=CFG0&255`、`RFC=(CFG0>>8)&511`、`RAS=(CFG0>>17)&127`、`RP=(CFG0>>24)&127`、`CL=CFG1&127`、`WL=(CFG1>>7)&127`、`RD_RCD=(CFG1>>14)&63`、`WR_RCD=(CFG1>>20)&63`；后续 `0x14011e29a..0x14011e3a3` 对其它七组重复相同位抽取。前两字格式与 NVIDIA [Memory Tweak Table](https://nvidia.github.io/open-gpu-doc/MemoryTweakTable/MemoryTweakTable.html) 公开前缀一致。
- mVolt+ [指南](https://github.com/b00nz/mVolt/blob/main/docs/guide.md) 称时序为只读遥测；此批量请求只含 CONFIG0/1，并没有读取 `+0x298..+0x2a4`。不能把额外寄存器的内容或可写性视作已验证。

## 2. MODS 中找到的通用读取和条件写入，但 **GB202 绑定未证明**

- 原始 MODS `0x680d4a2..0x680d5ba` 在 `FB+0x4351.bit4` 条件下，经 FB HAL `+0x738` 把 offset `0x290/0x294` 解析为读目标，再通过 `0x687b960` 读原值，与内部记录 `+0xd4/+0xd8` 对比。不相等则再次解析 offset 并调用写辅助函数 `0x6abc210`。日志原文 `NV_PFB_FBPA_CONFIG0/1 programmed to ...`。`0x680d5ba..0x680d7xx` 同样处理 offset `0x298/0x29c/0x2a0/0x2a4`（CONFIG2..5）；并见 CONFIG6 `+0x2a8`。在已分析的 `0x700de00` resolver 中，mode0/index0 将 offset `0x290` 映射到广播地址 `0x9a0290`，与 mVolt+ 的 broadcast 请求一致。
- `0x6809322..0x680940d` 在写之前记录目标寄存器值来源于内部记录的 `+0xd4,+0xd8,+0xdc,+0xe0,+0xe4,+0xe8`。这提供**读取其它配置字的静态候选 offset**，但并不证明 GB202 能使用 MODS 这个初始化函数，也不证明在运行驱动的主机上直接访问这些地址安全/允许。
- `0x6fd3d70` 中另一个 tRP 更新日志读 `0x9a0290`、拆 `[30:24]`，但该函数在 `0x6fd3d84..0x6fd3dad` 有早期芯片范围 `0x1db1..0x1db4` 门槛，不是 GB202/`0x2b85` 的可用写路径。
- 关于旧 RAM timing 三个 setter 在 GB202 命名 HAL 槽位绑定到 `0x56=NOT_SUPPORTED` 的证据及风险，见同层 `../write/REPORT.md`。当前仍缺 `0x2b85→HAL selector→CONFIG0..5 programmer` 的完整链条。

## 3. 本地 E1 ROM 与更多字段（仅**候选配置**）

- 输入 `flash_logs/astral-original-20260726_020901.rom` SHA256 `01a2e0340725c82988d54300934b993968f977ddea3185e64be161c279a8333b`，不是当前 E0 完整 EEPROM。Memory Clock at `0x7075c`：v0x11、header29、base112、per-strap84、strap count13、clock entry count10。config0 在 `14750..19999 MHz` 档的 tweak index 是15；本机 NVML 频率曾显示17001MHz。
- Memory Tweak at `0x73681`，header `20 06 69 0c 00 60`，即 v0x20、header6、base105、ext12、ext count0、**entry count96**；entry15 at `0x73cae`。CONFIG0 `0x1c711054`，CONFIG1 `0x797885a5`，按公开前缀得 RC84、RFC272、RAS56、RP28、CL37、WL11、RD_RCD34、WR_RCD23。CONFIG2 `0xcc2c1000`、CONFIG3 `0x2400006c`、CONFIG4 `0xf1428032`、CONFIG5 `0xe8027154`：按旧规范前缀暂算 WR44、RRD5、CCDL4、CCDS2、W2R_BUS12、R2W_BUS12；例如 FAW 解为0，所以不能直接当 GB202 的 tFAW。未用当前 E0 live 数据验证。
- 现存 `vbios_diff/gb202_memory_route_20260911/tools/memory_corpus.py` 的 `simple()` 将 header byte3 当 count，只取12条；实际此两表含扩展记录字段，tweak 的 count 在 header byte5=96。早先报告“12条整表相同”的结论只比较了表前段；对 E1 与一份 PRO ROM 的完整10086字节比较 SHA 分别为 `109ae3919e502da2f22fbc7e4e112b19e114135d2c998957a567747a81506179` / `8170930416929a22fde91784f344bedd6cb9b3b7dc9ac4daa1dff5ea747a08fe`，两者并不完全相同。

## 未解决 / 可验证的下一步

MODS 解析 `BIT P+8` 的 GB202 v0x20 / 105-byte VBIOS 记录的确切函数与数据流**尚未定位**；已解析的 `0x672c9e0` 属于另一张 Memory Information 表，不是这张 Tweak 表；旧源码中出现 `0x105` 常量也不能充当 record 长度证据。

1. 离线查 MODS `0x680d4a2` 所在函数的上游 caller 和 FB HAL/芯片 selector 绑定；不能把前代的 CONFIG writer 自动判作 GB202 可用。
2. 在单独授权、隔离且可回滚的只读研究环境，分别读八组与广播的 `CONFIG2..5` 原值，确认它们在 GB202 上的行为，再和 VBIOS 表字段交叉校验；当前**没有**这些寄存器的运行时读回。
3. 即使可读，也需要受支持的时序更新/停流/重训练流程、固件覆盖行为和安全回退证据，才能声称某个写路径可用；不对活动显卡试写。

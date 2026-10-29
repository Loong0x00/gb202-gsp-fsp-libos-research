# Offline reverse research: GB202 RAM timing write route

**Scope/safety of this original report:** static review of the stripped MODS/RM x86-64 ELF disassembly and existing offline Unicorn evidence under `gb202_init_acceptance_20260911/mods_init`. This original analysis did not use a GPU. **Later, user-authorized real MODS 570.215 native CONFIG1 `CL+1` trials in an isolated VM produced no observable register change** on either broadcast or FBPA0; see `GB202_MODS_NATIVE_RW_TRIAL_20260924.md`. The offline report does not treat a table-entry edit as proof of a hardware timing-register write.

最新 570.215 进程内 `SecurityUnlockLevel` 实测、原生 `RegWr32` wrapper/status 及 SUL 引用边界见 `MODS_570215_AUTH_AND_TIMING_ROUTE_20260924.md`；**CL 字段/真实 CONFIG1 寄存器地址、570.215 raw 读写同址与未知 update/训练条件**见 `GB202_CONFIG1_CL_RW_AND_APPLY_20260924.md`；CMP 170HX 的 SEC2/PLM/BAR0 方法与 GB202 适用性核对见 `CMP170HX_BAR0_FBPA_PATH_RELEVANCE_20260924.md`；`-gpubios` 等非刷写镜像输入候选、GB202 时序 setter 与 MCLK/训练的版本边界见 `GB202_NOFLASH_TIMING_ROUTE_20260924.md`。

## 原生 MODS 命令与专用 HAL setter 必须分开

之前“没有写渠道”的表述不准确：离线解码出的 `mods_audit/static/decoded/all/mods.js` 明确提供交互式 `RegWr32(address,data)` 及简写 `rw(address,data)`。当 `Gpu.IsInitialized` 为真，它走 `GpuSubdevice.RegWr32`；未初始化时退化为 BAR 物理内存写入。`RegMaskedWr32` 也可进行先读后掩码写。**因此 MODS 有原生原始寄存器写接口**；下面 `+0x700`/三个 setter 在 GB202 上的 no-op/NOT_SUPPORTED 仅排除了**那组高层时序 profile setter**，并不能推导通用 `RegWr32` 无法发送写请求。相反，能发送 MMIO 写也不等于 GB202 会接受/锁存它，更不等于修改活动 CONFIG1.CL 时可安全同步 GDDR7 模式寄存器/读延迟/训练。本报告最初的离线阶段未执行任何 CONFIG 写；后续 VM 中的 `rw` 请求与回读（包括 CL+1 无可见效果）单独记录于 `GB202_MODS_NATIVE_RW_TRIAL_20260924.md`。

## 版本边界（重要）

本报告离线分析的 MODS ELF SHA256 为 `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`（392,339,552 字节）。本地曾在 VM 使用的 **570.215** 样本 `/home/user/.cache/mods570215-powertrace.GC5pNs/mods` SHA256 为 `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856`（392,897,664 字节）。它们**不是同一构建**；以下 VA、HAL 枚举和否定结论不能不经重新验证就直接外推到 VM 的 570.215。

## Result

The available evidence does **not** prove a GB202 tRP/tRFC/tRCD/CL active-hardware write route, nor that PCI/device ID `0x2b85` selects the old RAM-timing HAL path. There are three legacy/shared RAM-timing-entry setters with range checks, plus a different active register-programming path. Their timing-field names are not identified in the evidence. The tested GB202-named HAL selector family does not bind these setters (or the CFG0 writer) in the inspected FB HAL slots.

### Legacy/shared table setters (not identified as tRP/tRFC/tRCD/CL)

The verified entry points and code are `0x700e4c0`, `0x700e560`, and `0x700e5d0` (`setters_verified.asm`). They call `0x700db80`, which chooses RAM timing-table entries by frequency; report evidence identifies the table base as FB+`0x4368`, stride `0xe0`, through `0x6811390` (log: “Using VBIOS RAM timing table entry ... maximum ... KHz”). These mutate the selected in-memory profile entries:

| VA | Accepted field input | Profile-entry update |
|---|---|---|
| `0x700e4c0` | full u32 `0..63`, or `0xffffffff` meaning preserve/default | copies selector into entry `+0x70` bits `[15:11]` and `+0x74` bits `[20:15]`; default extracted from entry `+0xd4` bits `[20:15]` |
| `0x700e560` | low byte `0..15`, or `0xff` meaning preserve/default | writes byte `+0xb5`, default from `+0xd8` |
| `0x700e5d0` | low byte `0..15`, or `0xff` meaning preserve/default | writes byte `+0xb6`, default from `+0xd9` |

Other values in the tested range-check path return `0x1f`. For the latter two, the comparison is on the low byte; e.g. `0x100` behaves as 0, so their acceptance is not a full-u32 exact set. These setters edit a **RAM timing table profile**, not an MMIO register. No evidence labels these fields as tRP, tRFC, tRCD or CL; assigning those names or a DRAM-specific bitfield meaning would be speculation.

### Legacy active register writer (not established as GB202)

`0x700f500` receives existing CFG0 in `T+0` (it is not shown reading a VBIOS timing ID). It conditionally modifies that value, compares it with the original, resolves mode 0/index 0/offset `0x200` through HAL `+0x738`, and calls the write helper `0x6abc210` only if changed. Resolver `0x700de00` maps that tuple to register/address `0x9a0200`. Its bit changes are:

- bit 12 from `T+0x75.bit0`;
- bit 21 from `T+0x60 != 0` under FB object conditions;
- bit 24 from `T+0x78.bit24` under an FB flag condition;
- for FB mode `0x10`, bit 19 and low bits `[1:0]`: choose bit19=0/low=3 when `T+0x78.bit31` is set, otherwise bit19=1/low=2.

This is the existing `NV_PFB_FBPA_CFG0` RMW/write route (log string at `0x700f58?`); it is not evidence that any of those bits encode tRP/tRFC/tRCD/CL. The offline test captured write-helper arguments, but did not execute `0x6abc210`.

The ELF also contains a separate initialization path logging `NV_PFB_FBPA_TIMING12`, `TIMING11`, and `TIMING1` (e.g. `geometry_base.asm` around VAs `0x680dc11`, `0x680dcc4`, `0x680dd56`). It resolves offsets `0x250`, `0x24c`, and `0x224` through its HAL resolver and computes RMW values from geometry/object data. It does not associate these registers/bits with tRP/tRFC/tRCD/CL, and the inspected evidence does not connect this path to the three profile setters or prove it is the active GB202 route. Thus expected per-parameter active register offsets/masks remain **unknown**.

### Selector/HAL binding and chip identity limit

The report's constructor simulation tested selector values, not a PCI-ID-to-selector production dispatch. In the enumerated legacy selector cases `0x1d..0x22`, FB HAL slots `+0x808/+0x810/+0x818` point to `0x700e4c0/0x700e560/0x700e5d0`. `+0x6f8` points to `0x700f500` only for `0x1e..0x22` (not `0x1d`).

For the tested **GB202-named fuse HAL family** selectors `0x46,0x47,0x49,0x4a,0x4b`, constructor instructions bind fuse `+0x198` to `0x705b4f0`; the corresponding FB HAL has `+0x6f8 -> 0x6c044a0` (a `ret` stub), `+0x738 -> 0x700de00`, and `+0x808/+0x810/+0x818 -> 0x6bf8130/0x6bf8140/0x6c040b0` (fixed `0x56` return stubs). The old setters and CFG0 writer are therefore **not bound in those inspected slots**. This is strong negative evidence against reusing the old `0x1d..0x22` route for that named family, not proof that every GB202 consumer is absent.

Neither the local report/disassembly evidence nor this analysis closes `0x2b85 -> selector -> constructor/HAL -> timing consumer`. A chip ID by itself cannot establish that route. We cannot claim that `0x2b85` takes either selector family, nor prove a GB202 hardware timing write path at all from this evidence.

## 补查：CONFIG0..5 整字编程路径的 GB202 HAL 槽位（离线新增验证）

前一节只枚举到 `+0x6f8`，漏掉紧邻的 `FB HAL +0x700`。用相同受限 Unicorn sandbox **只执行原 ELF 构造函数 `0x6bf8780` 的指令**，增加对 `+0x700` 的离线枚举，不执行 MODS 本体，也不触碰设备：

| selector | FB HAL +0x700 | +0x6f8 | 说明 |
|---|---|---|---|
| `0x1d` | `0x680ce90` | `0x680cdd0` | 旧/共享 CONFIG 编程 |
| `0x1e` / `0x22` | `0x700f620` | `0x700f500` | 其它旧/共享处理 |
| GB202 命名组 `0x46,0x47,0x49,0x4a,0x4b` | **`0x6c043d0`** | `0x6c044a0` | `0x6c043d0` 原指令是 `xor eax,eax; ret`，并不执行旧的 `0x680ce90` |

MODS 原指令中 `0x6bf9651/0x6bf9bfa` 为旧路径安装 `0x680ce90` 到 `+0x700`；GB202 命名组读到的是另外的空实现。`0x680ce90` 的打印/读写分支 `0x680d4a2..0x680d7xx` 通过 HAL `+0x738` 解析 `0x290,0x294,0x298,0x29c,0x2a0,0x2a4` (CONFIG0..5)，读函数 `0x687b960` 对比内部 entry 字段、仅在不同时才调用 `0x6abc210`。其入口 `0x680cebd..0x680cee3` 的 RAM type 掩码 `0x50c000` 只包含 `0xe,0xf,0x14,0x16`，不包括已还原的 GDDR7 type `0x15`（此掩码控制的具体子分支仍需数据流确认）。

由此能够更明确地说：**MODS 确有整字 CONFIG0..5 写程序，但已测 GB202 命名 HAL 组在 `+0x700` 不绑定它**。这不排除其它 GB202 固件/初始化写路径，也没有闭合 PCI `0x2b85` 到具体 selector；切忌将通用寄存器 `0x9a0290` 可读误判为可直接调整时序。对应 live READ 的跨软件静态证据见 `../read/REPORT.md`。

## 新增：VM 实际使用的 MODS 570.215 重新验证（非旧地址迁移）

离线独立定位 570.215 ELF 中 `NV_PFB_FBPA_CONFIG0 programmed to` 的代码 xref `0x685ad10`；ELF FDE 表证明该处属于函数 `0x685a690..0x685b866`，对应新构建的整字 CONFIG programmer。新构建的 FB HAL 构造函数由 FDE 确认为 `0x6c47810..0x6c49edc`，不是上文旧版 VA。增加只读文件映射、限定指令区间的 Unicorn 重放，见 `reproduce_selector700_570215.py`，已实际运行并核对 hash/输出：

| 内部 selector | `+0x700` | `+0x6f8` | `+0x808/+0x810/+0x818` |
|---|---|---|---|
| `0x1d` | `0x685a690` (有 CONFIG0..5 写程序) | `0x685a5d0` | `0x7060870/0x7060910/0x7060980` |
| `0x1e,0x22` | `0x70619d0` | `0x70618b0` | 同左旧/共享 setters |
| 已识别 GB202 命名组 `0x46,0x47,0x49,0x4a,0x4b` | **`0x6c533c0` (`xor eax,eax; ret`)** | `0x6c534d0` (`ret`) | **`0x6c471b0/0x6c471c0/0x6c530b0`，全部 `eax=0x56;ret`** |

新构建也没有在这几个 GB202 命名槽位绑定旧整字写程序或三个 setter。这是针对 **570.215** 的实际指令结果，而非由旧二进制地址推断；仍未闭合板卡 PCI `0x2b85`→内部 selector 全生产路径，不排除其它固件/槽位。**没有对 GPU 执行写入。**

### 570.215 caller chain and corrected full-ELF scan

The selector input is a field in an object, not a literal passed in a register: constructor `0x6c47810..0x6c49edc` reads the 16-bit value at `[rsi+0x10]` (`movzx esi, word ptr [rsi+0x10]` at `0x6c47864`). Its unique direct rel32 callsite in this ELF is `0x6c55eb2`, inside the wrapper/factory FDE `0x6c550e0..0x6c58f41`. That wrapper preserves its input object in `r14` (`0x6c550ff`), reads `[rsi+0x10]` itself at `0x6c552bc`, and just before the constructor call passes `rsi=r14` (`0x6c55ea7`). The next upstream factory FDE is `0x6c58f50..0x6c59184`: it calls the wrapper at `0x6c59074` with `rdi=rbx`, `rsi=r15`; `r15` is the result of the preceding helper lookup call at `0x6c58fec` (`0x6b797b0`, given input object `r14` and descriptor `0x9db2f60`). This maps constructor → wrapper → caller/lookup, but does **not** identify the lookup input as PCI DID or show how the live card DID becomes the selector-bearing object.

A new read-only scanner, `scan_570215_selector_refs.py`, verifies the same ELF SHA and decodes the entire `.text` (30,864,944 instructions) with LLVM; it uses the ELF `.text` VA `0x4a0ac0` and file offset `0xa0ac0` (VA/file bias `+0x400000`), avoiding file-offset-as-VA errors. Across the decoded code it finds exactly one direct rel32 reference to the FB HAL constructor (`0x6c55eb2 -> 0x6c47810`) and exactly one to the wrapper factory (`0x6c59074 -> 0x6c550e0`). It finds **no exact instruction immediate operand `0x2b85`** and, among 574,779 decoded RIP-relative references, no file-backed target whose first `0x20` bytes contain that word. The only decoded immediate whose low 16 bits equal `0x2b85` is `0x09142b85` at `0x11e2319`; it is passed to the logging helper in a sequence of neighboring `0x09142bxx` message IDs, not used as a selector comparison. The raw `.text` byte occurrences of `85 2b 00 00` decode as rel32 displacements (e.g. `call 0x241cac0` and `jne 0x857e2e2`), not PCI-ID constants.

**Conclusion on DID→selector:** the matching 570.215 static evidence does not show `0x2b85` feeding the selector. It positively identifies the immediate selector source as object field `+0x10`, and maps the object through the internal lookup/factory chain above, but it does not prove that the DID is absent from an upstream runtime-derived object or indexed table. Therefore the production `0x2b85 -> selector` mapping remains **unresolved**, not “selector `0x46`” and not a proven negative. The replayed `0x46/0x47/0x49/0x4a/0x4b` cases remain no-op at FB HAL `+0x700`, while `0x1d` binds the real `0x685a690` writer; without DID-to-selector closure, we cannot assign either case to this board.

## Evidence and confidence

Primary local evidence: `gb202_init_acceptance_20260911/mods_init/REPORT.zh-CN.md`; `setters_verified.asm`; `writer_verified.asm`; `hal_matrix.json`; `verification.txt`; and `geometry_base.asm`. Existing verification records raw-instruction tests of 96×2 constructor cases, 72 writer cases, and 780 range cases. The setter range harness substitutes a successful lookup result for `0x700db80`; the write-helper call is captured rather than run. These are offline code-path checks, not device/boot observations. No ROM Falcon app19 simulation or runtime evidence is present.

## Safe follow-up

1. Offline only: locate a trustworthy device-ID-to-HAL-selector dispatch in matching ELF/source/build metadata for `0x2b85`, and follow its actual FB HAL construction to timing consumers.
2. Statically trace all callsites of the three setters and the TIMING-register initialization block, then trace the input fields back to VBIOS table fields. Require explicit format/field evidence before naming a field tRP/tRFC/tRCD/CL.
3. Match register offsets and masks against authoritative GB202 register definitions / a read-only symbol map. Keep table-profile edits separate from the eventual MMIO write path.
4. If that still leaves runtime uncertainty, use a separately authorized, read-only observation plan only; do not invoke MODS setters or test by flashing/writing hardware.

# MODS 570.151 / 570.215 / 570.278 FuseRework / FRB 调用链差分审计

**范围与方法。** 静态审查宿主 MODS ELF；未运行 MODS、未向 FSP/设备发送命令。样本：570.151（`mods_audit/570.151_GB202_5090.zip` 内 `core/mods0/570.151.tgz` 的 `./mods`）、570.215（`vm_mods_lab/MOD570_215.img` 内 `home/570.215/mods`）、570.278（`mods_versions/570.278/mods`）。以下 file offsets/哈希均针对抽出的 `mods` ELF。570.215 的函数级反编译来自本目录既有 Ghidra 项目；跨版本完成 ELF/字符串差分，但本次没有为 151、278 重做完整 Ghidra callgraph。因此将“版本一致”与“对 151/278 的全间接调用穷尽”区别表述。

## 结论摘要

1. 三版均保留 `SetReworkBinaryFilename`、`GetSkuReworkInfo`、`fuserework.bin`、`FRB Riscv Start` 等同一组 FuseRework/FRB 字符串；字符串文件偏移有平移。570.215 的主文件绑定不只是字符串共现：FuseRework 构造/初始化代码把 `fuserework.bin` 指针作为默认路径字段传入初始化 helper；随后 `FuseReworkStart` 对 context `+0x98` 的加载结果调用 `FuseReworkLoadOne`，走同一 mode-2 解析入口。这支持默认主文件绑定，但不能推出任意 `SetReworkBinaryFilename()` 用户值在所有运行时条件下都实际覆盖成功（需看 JS setter 的数据流/调用）。
2. `GetSkuReworkInfo`、`SetReworkBinaryFilename` 字符串对应 JS API/usage，不是 FSP sender 的别名。已恢复的 FRB/Execute 链与 SKU 查询接口在功能上不同；字符串存在本身不证明 FRB Start 必然调用 SKU 接口。
3. 570.215 mode-2 主输入来自 MODS 文件加载器：`LoadFileVector` 读取选定文件到 vector；`FuseReworkLoadAuth` / `FuseReworkSelectAuth` 最终对 vector 调 `FuseReworkLoadMode2`。`FuseReworkStart` 随后从该 vector 调 `FuseReworkLoadOne`，不是从 debug hash/pubkey/signature 三个旁文件读取 mode-2 主内容。后者各自是 `FuseReworkExecute` 的认证附加数据。
4. 570.215 对已知 FSP sender `0x18a0d40` 的直接 call 只有七处；唯一 FuseRework caller 是 `0x173b1fe` 的 outer command `0x0f`。这个 caller 要求精确 4-byte `0x0f` 响应，不是 bulk decrypt-to-host 响应。其余 callsites 是小状态/4-byte wrapper/12 或 24-byte telemetry 响应。`FspSendRequestCandidate` 本身经 transport vtable 发包/收包；这层间接 dispatch 是传输机制，不是另一个面向任意 FSP decrypt 的 MODS API。
5. 重要限制：现存证据可以排除 570.215 上“直接 sender callsite 中漏掉的明显 bulk plaintext response”，但不能仅凭这份报告对 570.151/570.278 宣称穷尽函数指针/任意 wrapper，也不能证明 FSP firmware 内部不存在 decrypt service。需把跨版本 Ghidra 的全 xref/函数指针流分析作为剩余项，而非静默推断没有。

## 版本指纹

| 版本 | `mods` 字节数 | SHA-256 | 关键字符串 file offset |
|---|---:|---|---|
| 570.151 | 392,339,552 | `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf` | usage Set `0x884bc08`; usage SKU `0x884c130`; SKU symbol `0x8ce063d`; Set symbol `0x8ce07a2`; main name `0x8ce1420`; FRB Start `0x8cf2318` |
| 570.215 | 392,897,664 | `6645d5de5e0ce3c9dacd79e264e46398cb1296107d4dba15cbb3a84ea82e5856` | usage Set `0x88b06c0`; usage SKU `0x88b0be8`; SKU symbol `0x8d4b551`; Set symbol `0x8d4b6b6`; main name `0x8d4c334`; FRB Start `0x8d5d4cb` |
| 570.278 | 393,278,528 | `1d55a7e4fc0ffcad1405ae0a512dc1e5b11e183dad6a14ec34e2dc8042b74f72` | secureboot error `0x88b8e00`; usage Set `0x88dbb28`; usage SKU `0x88dc050`; SKU symbol `0x8d79e9a`; Set symbol `0x8d79fff`; main name `0x8d7ac7d`; FRB Start `0x8d8beab` |

三版本均有 `SECUREBOOT_FAILURE_ABANDON_FUSEREWORK`（在本次列出的 570.151/570.215关键字符串 grep 中未见；570.278 明确命中）。这只能说明诊断文案的加入/保留差异，不能单凭字符串判定控制流改变。各版本不是相同 ELF，也不应直接复用 570.215 的 VA 地址解释其他版本。

## 570.215 主文件及 mode-2 链

反编译/指令证据（函数地址为 570.215 ELF VA）：

```text
FuseReworkOrchestrator 0x14a1730
  -> FuseReworkCtor(context, config)
  -> FuseReworkLoadSelect(context, 1)
  -> FuseReworkLoadAuth(context, param_1 + 0xc, mode=2)
  -> FuseReworkTransfer(...)
  -> FuseReworkExecute(context)

FuseReworkSelectAuth 0x173acd0
  -> FuseReworkLoadFiles(context+0x98, ...)
  -> FuseReworkStage(...)
  -> FuseReworkStart(context)

FuseReworkStart 0x173a8d0
  -> FuseReworkLoadOne(context, context+0x98, ...)
  -> 写 opaque qwords 到 context+0x18/+0x20

FuseReworkLoadOne 0x173a700
  -> 输入 vector 长度 < 0x200000 才继续
  -> parser/helper 处理 vector；输出由 LoadOne 消费
```

`FuseReworkLoadAuth` 调 `LoadFileVector(path, context+0x98)`，随后 `FuseReworkSelectAuth`/`LoadFiles` 对同一 vector 执行 mode 2。`FuseReworkLoadMode2` 校验首字节为 odd，再按 type `2/3/4` 分派 parser。故 mode-2 输入来源是 MODS 的文件向量/主路径，不是 FSP response buffer。loader 对主文件有 `< 2 MiB` 限制，也不符合约 `0x29400–0x37000` encrypted GFW payload 的裸 bulk 输出路径。

### `fuserework.bin` 默认绑定证据及边界

570.215 字符串 VA `0x0914c334`（file offset `0x08d4c334`）。对它的机器码引用位于构造函数邻域 `0x14a9bf8`：`mov esi,0x914c334`，紧接着把相应对象字段清零并调用初始化 helper `0x149bf40`（参数含 `this+0x60`、默认路径和相邻字符串）。这证明文件名被用作 FuseRework 对象默认配置，而非仅仅一个未引用的字符串。

与之相接的 `FuseReworkStart` 从 `context+0x98` 取 vector，调用 `FuseReworkLoadOne`；`FuseReworkLoadFiles`/`LoadFileVector` 则以当前路径参数装入该 vector。由“构造时默认文件路径 + file loader 填充主 vector + Start 解析主 vector”组成闭合的默认主文件链。`SetReworkBinaryFilename` 的 usage 与 symbol 字符串表明存在可覆盖路径的 JS API；本轮没有对所有 JS 调用者、设置时序和 setter 错误分支做完整数据流证明，因此精确结论是**默认主文件绑定成立，运行时自定义覆盖的覆盖面未穷尽**。

## FSP sender 与 bulk decrypt-to-host 检查（570.215）

`FspSendRequestCandidate` (`0x18a0d40`) 的直接 `call` 枚举来自 `fsp_sender_callsites.txt`，并用调用者反编译交叉检查：

| callsite | 形状 | 解释 |
|---:|---|---|
| `0x00e241c7` | outer `0x82`，7-byte request，4-byte bit/status response | feature/status |
| `0x0173b1fe` | outer `0x0f`，FuseRework payload，response 必须是 4-byte `0x0f` | FuseRework command ack |
| `0x018a0e47` | 小 request，4-byte response | 内部两字节请求 wrapper |
| `0x01f11d4c` | outer `0x0e`，12-byte response | telemetry/clock-style |
| `0x01f4b9f3` | outer `0x0e`，24-byte response | telemetry/clock-style |
| `0x01f542fb` | outer `0x0e`，24-byte response | telemetry/clock-style |
| `0x01f5468d` | outer `0x0e`，24-byte response | telemetry/clock-style |

FuseRework command 构造器 `FuseReworkExecute` 依次追加 selector、`0x0348`、主文件解析所得 opaque qword、三个固定长度 auth sidefiles、transfer 状态 qword 和 16-bit 长度，再发 `0x0f`。`FuseReworkParseResponse` 只接受 4-byte 精确 `0x0000000f`。输出 vector 的大小/消费方式由此不是 bulk data。

### 间接/包装路径判断

- sender 内部通过 `context+0x90` transport 对象的 vtable `+0x30` 发、`+0x38` 收；`context+0x70` selector 参与 transport 选择。它是已见 sender 的下层传输动态分派，不会自动形成一个接收任意大明文的上层 API。
- 直接 caller 清单覆盖了已知 sender 地址上的所有 x86-64 `call rel32` 直接调用。该清单没有发现第八个 bulk 返回 caller。已见 caller 的响应解释都是 4、12 或 24 bytes，且没有将 response vector 当 GFW/FSP_RUN 镜像写入文件/大 buffer 的后处理。
- 风险边界：普通 `objdump` 的直接 call 枚举不能证明没有 `call [reg]` / `jmp [reg]` 先取 sender 地址、回调表注册或地址别名；需要对每个版本的 Ghidra references、函数指针值传播和 indirect-call targets 逐一恢复。现有 `ghidra_all_fsp_sender_callers.c` 与 `FSP_SENDER_CALLSITE_AUDIT.md` 对 570.215 提供了直接 caller 的函数级证据，不是跨版本指针分析的证明。
- `NON_FSP_DECRYPTION_DEV_NOT_ALLOWED` 仍说明内部策略/错误路径的存在；这既不等于 host 可调用 decrypt 服务，也不否定 FSP 固件内可能有私有 decrypt 能力。

## 尚未闭合的差分点

- 570.151/570.278 的 ELF 字符串集合和 offsets 已核验，但它们的 sender 入口地址、每一条直接/间接 caller 和 FuseRework 构造器/调用者尚未逐个 Ghidra 导出；不要把 570.215 `0x18a0d40` 或它的七条 callsite 原样套用到其他 build。
- 尚未证明 `GetSkuReworkInfo` 是否在某个独立 SKU/FRB 前置流程间接改变主路径、文件名或 mode；当前证据只表明它是存在的 API 名称。继续审计应沿三个版本该字符串 xref 和 JS 注册表追调用者。
- 当前“无 bulk decrypt-to-host wrapper”是对已审计 570.215 sender 直接调用者的结论；要升级为三版本穷尽结论，应在 151/278 中重建同名/同签名 sender function，再检索直接 xref、函数地址常量和 indirect-call points，并对任何接收大 response 的 caller 做 decompile。

## 可复查材料

- 已有反编译：`ghidra_fuserework_orchestrator.c`、`ghidra_fuserework_flow.c`、`ghidra_fuserework_fileload_helpers.c`、`ghidra_fuserework_mode2_parsers.c`、`ghidra_fuserework_payload_helpers.c`。
- sender：`fsp_sender_callsites.txt`、`ghidra_all_fsp_sender_callers.c`、`ghidra_fsp_sender_18a0d40.c`、`ghidra_fsp_sender_helpers.c`、`FSP_SENDER_CALLSITE_AUDIT.md`。
- ABI/context：`FUSEREWORK_ABI.md`。
- 本次只读样本提取到临时目录 `/tmp/mods-callchain/`；没有修改这些 ELF 或其他已有报告。

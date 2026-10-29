# Blackwell Debug Token / PRC 候选路径：公开 ABI 的已证边界

日期：2026-08-13  
范围：NVIDIA 公开 `nsmd`/NSM 源码、已归档 Dell HGX Blackwell Redfish schema、
既有 RTX PRO 6000 updater 静态结果。未生成、安装或请求 token；未访问 GPU。

## 结论

`PrcKnobEn` 是真实存在的 NVIDIA GPU Debug Token capability 名，不是推测。
这给出了 HULK 之外的一条具体、签名 token 候选路径，因此不能声称 GB202 L2
解锁 **100% 必须**使用 HULK 文件。

但公开源码没有把 `PrcKnobEn` 映射到 PRC object `0x1d`、FSP task 2、
`0x8200f8`、latch `0x820040` 或 raw mask `0x8234e0`。所以也不能声称取得该
token 就足以改变 RTX 5090 L2。

## 1. 当前 NSMD subtype

NVIDIA `nsmd` 的 GPU `HardwareUnlock` subtype 表（token type `4`）明确列出：

```text
0x00000040  Bar0DecouplerUnlock
0x00000200  NvlinkGlobalHulk
0x00001000  PrcKnobEn
0x00100000  PxucGlobalHulk
0x00200000  TargetMaskUnlock
```

直接来源：

- <https://github.com/NVIDIA/nsmd/blob/develop/nsmd/nsmDebugToken/debugTokenUtils.cpp>
- 本地归档文件 SHA-256
  `ee06baf4181912188f9de57241a7feba4f1d056a8826fc2da6844d06bf83a5fc`

这些是同一 HardwareUnlock subtype 枚举中的不同 bit；名字本身不能证明它们的
底层寄存器作用域。

## 2. Legacy request 与 Unified HardwareUnlock 必须分开

公开 NSM `nsm_debug_token_request` 结构包含：

```text
token_request_version / size
device_uuid[8]
device_type
token_opcode
device_index
keypair_uuid[16]
base_mac[8]
psid[16]
fw_version[5]
source_address[16]
session_id
challenge_version
challenge[32]
```

`QueryTokenParameters` 的请求端只发送一个 token opcode；上述身份、固件、会话和
challenge 字段由设备响应返回。**但是这套 140-byte request 是 legacy
QueryTokenParameters/GetRequest 流；公开 D-Bus wrapper 只对 CRCS/CRDT 暴露它。**

`PrcKnobEn` 则属于较新的 Unified TLV `HardwareUnlock` subtype 表。公开源码没有
给出从这个 legacy request 到 Unified HardwareUnlock 的字段映射，所以不能据此
声称 `PrcKnobEn` token 必然绑定上面每一个字段。

Unified TLV 的公开类型表只证明容器可以出现这些字段：`ChallengeNonce`、device
serial/array、firmware/agent version、lifecycle、token identifier/type/config、
NVIDIA/OEM signature、SKU、NVIDIA/OEM ratchet、validity counter、certificate
chain、measurement transcript、device ID、type/subtype list、payload，以及 GPU
`FeatureMask`/`ChipId` 和 NBU `KeypairUUID`/`PSID`。哪些字段对 GPU HardwareUnlock
必需、签名覆盖范围和签发策略均未公开。

源码：

- <https://github.com/NVIDIA/nsmd/blob/develop/libnsm/debug-token.h>
- <https://github.com/NVIDIA/nsmd/blob/develop/nsmtool/nsm_diag_cmd.cpp>
- 本地 `nsmd` develop tarball：SHA-256
  `f60e80de050f6f185d72f485cd59f897bc1a3a1e781bdcb5df109c572603acc6`

## 3. 安装是设备端判定，不是 host 字符串开关

`nsmd` 将 token 分块编码为 `offset / chunk_length / length_remaining / data`，
发给设备，逐块解码 completion/reason code。安装完成后再查询 token 状态。
公开代码只有传输、解析和状态管理，没有签发私钥或本地生成可接受签名的实现。

Dell HGX Blackwell rootfs 中的 legacy NVIDIA Redfish schema进一步给出真实管理面：

- `GenerateToken(TokenType)` 返回 `BinaryTokenURI`；
- `InstallToken(TokenData)` 接受 Base64 token data；
- `DisableToken` 终止当前 token；
- `DeviceID` 被描述为用于此 token 的 device unique identifier；
- 状态区分 challenge 已生成、安装超时、debug session active 和 token timeout。

当前 NVIDIA `nv-redfish` v1.1.0 schema 更直接地说明：`HardwareUnlock` token
“provides authorization to lower the hardware enforced protections like lowering PLMs
or overriding registers”，并把 `PrcKnobEn` 列为独立 subtype。其安装入口是
`InstallTokenPushURI`，由 associated trusted components 处理二进制 token image。
这证明 HardwareUnlock 的总体目标确实包括降低 PLM/寄存器覆盖，但没有说
`PrcKnobEn` 本身覆盖哪个 PLM 或寄存器。

文件：

- `NvidiaDebugToken_v1.xml`，SHA-256
  `92151db9223c0eeb2f61918039ae8a0a07f58c4f033daee470640553324f573a`
- `NvidiaDebugTokenManagement_v1.xml`，SHA-256
  `d0cc0c6e04969f7eb9e7a8527aefc05c3463751b79141143ad01e6fb2e85cb0f`
- current NVIDIA `nv-redfish` v1.1.0
  <https://github.com/NVIDIA/nv-redfish/blob/main/schema/oem/nvidia/NvidiaDebugTokenManagement_v1.xml>,
  48,556 bytes, SHA-256
  `b224db45bd73bb341490b186356ce0145d44d5fec007678351f2f5dc87786790`

## 4. 旧 RTX PRO updater 与当前 NSMD 枚举不能直接混用

进一步反汇编已经纠正了旧分类：HPE 与 Dell 两个 5.877 updater 都把
`prc_knob_en` 放在 GPU `HardwareUnlock` type `4` 的 subtype 分支，bit 为
`0x00020000`；并非 `feature_unlock`。当前 `nsmd` 也把 `PrcKnobEn` 放在
`HardwareUnlock` type `4`，但 bit 为 `0x00001000`。父类型一致而 mask 布局不同；
多个相邻同名 subtype 也发生整体重排，因此不能把它当成单独一个 bit 的别名。
公开证据尚未给出两代 wire/TLV 表示或转换关系，报告必须保留各自 ABI 的原始 bit。

旧工具还显示 request/install workflow 和失败分类，包括 nonce、lifecycle、ratchet、
firmware version、serial、PSID 和 signature mismatch。它证明 token 有真实签名和
身份策略，但工具只收集请求、安装并显示 device status，不包含公开签发服务。

- HPE `nvflash` SHA-256
  `d1aee0b0309475826b15bb8c31624d11a80e0e6d568bea6144be7e213df44780`
- Dell updater SHA-256
  `6e1ccf97addee26c3c836cc4c87b4fdd0151cf78edb4df921b35338479e6ab61`
- 既有静态审计 `parallel/gsp_hulk_token_gate_20260723.md` SHA-256
  `12961afa6ce012d0287deb58fa116e320301550433dd223acb992387ff1bc0c4`
- mask/type dispatch 审计 `parallel/prc_knob_en_mask_generation_20260813.md`
  SHA-256 `48a9d114fe20ea783c6feb0cffb6f1ab507c1bea3102b1a631a0962a007bf2c1`

### 4.1 公开 ABI 的时间边界

`nsmd` 的 Git 历史给出了比当前文件快照更严格的来源界限：

- commit `974a21f008ea34d331d87cfb614ec7de6abcc7c4` 首次加入按 device type
  区分的 token type/subtype 映射；GPU `HardwareUnlock=4` 和
  `PrcKnobEn=0x00001000` 已在该提交中。author date 为 2026-01-05，commit
  date 为 2026-01-29：
  <https://github.com/NVIDIA/nsmd/commit/974a21f008ea34d331d87cfb614ec7de6abcc7c4>
- commit `af3d8c00d774a08b0d61224947a7b35dde474066` 于 2026-03 加入
  `TargetMaskUnlock=0x00200000`，提交说明明确称其为 GPU Hw Unlock：
  <https://github.com/NVIDIA/nsmd/commit/af3d8c00d774a08b0d61224947a7b35dde474066>
- `nv-redfish` commit `d80974d79df0fe3df02d452c89511a9d054dd2c2`（2026-08-03）
  是从 `NVIDIA/bmcweb` vendoring schema，不是这些 subtype 的最早来源：
  <https://github.com/NVIDIA/nv-redfish/commit/d80974d79df0fe3df02d452c89511a9d054dd2c2>

公开 schema 将 `TargetMaskUnlock` 描述成 GR10X hardware-unlock subtype，
并说 target mask 用于选择 debug operation 的目标 silicon；但没有解释 target
编码是否代表 GPU、FSP、FBP/GPC/TPC、L2 slice 或其他硬件域。`nsmd`、`bmcweb`、
`phosphor-dbus-interfaces`、`nv-redfish` 的相关文件与 Git 历史中也没有
`floorsweep`、`L2 slice` 或 `PrcKnobEn` 与 `0x1d` 的关联。因此必须把
`PrcKnobEn=0x1000`（token subtype bitmap）、`TargetMaskUnlock=0x200000`
（另一 token subtype bitmap）和 PRC object ID `0x1d` 视为三个独立命名空间。

## 5. 与 PRC 0x1d / L2 的关系

对完整 `nsmd` develop tarball 做限定搜索：

```text
PrcKnobEn                         1 hit (debugTokenUtils.cpp enum)
prc_knob_en                       0 hits
FLOORSWEEPING_ALLOW_INB_ONE_SHOT  0 hits
0x8200f8 / 0x820040 / 0x8234e0   0 hits
```

因此当前分级为：

- **PROVED:** NVIDIA 有 signed Debug Token 生态；GPU HardwareUnlock 中存在独立
  `PrcKnobEn` subtype，HardwareUnlock 类型总体用于降低 PLM 或覆盖寄存器。
- **PROVED, legacy-only:** QueryTokenParameters request 有 device UUID/PSID/FW/
  session/challenge 等字段；不能自动推广到 Unified `PrcKnobEn` token。
- **PROVED:** HULK license update permission、HULK NVDM、PRC NVDM 和
  Debug Token 是公开接口中可区分的对象/通道。
- **INFERENCE:** `PrcKnobEn` 很可能允许某类 PRC knob 操作，因此是解释本卡
  PRC write gate 的优先候选。
- **UNKNOWN:** 它是否允许 object `0x1d`，是否改变 task 2 行为，是否打开 `f8`
  或 latch，以及是否可用于零售 GB202/`2b85`。
- **NOT FOUND:** 公开签发端、私钥、真实 `PrcKnobEn` token、目标 GPU request/
  response 对、或成功 RTX 5090 安装日志。

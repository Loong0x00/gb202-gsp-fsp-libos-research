# GB202 制造包隐藏返修/外部依赖审计

## 结论摘要

**发现了未由制造包外层文件名暴露的 FuseRework/FRB 工具能力及外部输入文件名，但没有发现这些返修输入文件本体随包交付。** 线索位于包内 `core/mods0/570.151.tgz` 的 MODS 可执行文件字符串表，而不是 `recipe_eng.xml`、ENG/NOCHK spec 或 `gldGB202.bin`。包中唯一 `frb` 命名的文件是 `frb_ga100.bin`（4,792 bytes）；内层 570.151 MODS 包名清单没有 `fuserework.bin` 或三个 `fuserework_debug_gfw_*` sidecar。

另发现一个条件式 SMBv1 网络日志共享、若干 Perforce 源路径及 Nautilus 的一般下载/更新文案；未发现明文 entitlement、SiteID 值或 GB202 rework 下载 ID。关键配置文件是不可读的密文，因此 entitlement/SiteID 负结果有明确边界。

## 范围与完整性

- 已先阅读 `/home/user/rt_5090_project/AGENTS.md`。本次是只读静态包审计；未运行 Nautilus/MODS、未访问 GPU/设备、未挂载网络共享、未访问网络或刷写/改动硬件。
- 原始 ZIP：`/home/user/rt_5090_project/mods_audit/570.151_GB202_5090.zip`，大小 `943,721,235` bytes，SHA-256 `d141f685ea70c9a49095b7369201ab0651222bea3c063acfd6616dfde058ded9`。
- `zipinfo -v` 显示 ZIP 只有一个成员 `659-1G145-0035-MFG-41923.tbz`。以流式方式读取其目录清单（不落盘解包）得 47 个成员；其中 `core/mods0/570.151.tgz` 为 `434,926,703` bytes。该内层 tar.gz 清单有 134 个成员；`./mods` 为 `392,339,552` bytes。
- 已有提取文本目录含 27 个文件，二进制目录含 `gldGB202.bin`、`UHBR.dpc` 两个文件。整个审计没有改写这些输入或其他报告；目标报告此前不存在。

## 1. MODS 二进制内嵌返修能力与文件名

对 ZIP 内流式读取的 `core/mods0/570.151.tgz::./mods` 执行 `strings -a -t x -n 5`。下列是 `strings -t x` 报告的 **MODS 文件原始字节偏移**（非反汇编地址）：

| 偏移 | 精确可见字符串 | 含义/边界 |
|---|---|---|
| `0x8ce1420` | `fuserework.bin` | 主返修输入文件名字符串；文件未出现在内层 tar 成员清单。 |
| `0x8878438` | `fuserework_debug_gfw_pub_key.bin` | debug GFW 公钥 sidecar 名；未见同名成员。 |
| `0x8cf22ac` | `fuserework_debug_gfw_hash.bin` | debug GFW hash sidecar 名；未见同名成员。 |
| `0x8cf22ca` | `fuserework_debug_gfw_sig.bin` | debug GFW 签名 sidecar 名；未见同名成员。 |
| `0x884cab8` / `0x884cae0` / `0x884cb08` / `0x884cb38` | `Sets the fuse rework binary filename` / `...SHA Hash filename` / `...Public Key filename` / `...RSA Signature filename` | 明确存在可设置四类文件名的工具接口说明。 |
| `0x8cfa569` | `FuseRework` | MODS 字符串表中的能力名。 |
| `0x8cf2318` | `FRB Riscv Start` | FRB/RISC-V 路径提示；不等于包内存在对应 GB202 FRB 文件。 |
| `0x88783b8` | `Loading FRB > 2 MB is not supported!` | 存在 FRB 加载路径提示。 |
| `0x8cd5812` / `0x8cd582e` | `Load and execute RIR binary` / `RunRirFrb` | 另有 RIR/FRB 工具入口字符串。 |

对比内层 tar.gz 的 134 项成员名，相关实际文件只有 `./frb_ga100.bin`（4,792 bytes）、`./fub_ga100.bin`（5,332 bytes）、`./fuseread_gp10x.bin` 与 `./fuseread_gm206.bin`（各 1,608 bytes）。**没有** `fuserework.bin`、`fuserework_debug_gfw_pub_key.bin`、`fuserework_debug_gfw_hash.bin`、`fuserework_debug_gfw_sig.bin`，也没有 `frb_gb202*` 命名成员。故证据支持“工具支持并可引用外部返修物料”，不支持“GB202返修/GFW payload 已随包交付”。

## 2. ENG / NOCHK / recipe 调用图

静态调用链：

```text
run.sh --process=ENG
  └─ PROCESS=ENG；RP=recipe_eng.xml                         run.sh:12-20
      └─ ./nautilus s ... --recipe=./recipes/$RP            run.sh:55-59
          ├─ GET_DEVICE_PDI：mods -no_net ... gputest.js    recipe_eng.xml:18-29
          └─ ENG：mods -no_net ... -readspec {{ENG_SPC}}    recipe_eng.xml:43-47
              └─ ENG_SPC 的具体值由配置/运行时解析；当前 manifest 密文，未能确认
```

`recipe_eng.xml` 只执行 PDI 获取与 `{{ENG_SPC}}` spec，没有 `FuseRework`、FRB 或 debug GFW 调用。`pg145sku35_eng.spc` 和 `pg145sku35_eng_nochk.spc` 都从 `pg145sku35.spc` 开始；后者再 include `board_common.spc`。相关 spec 使用的基础参数是测试/时钟/链路配置；可见 fuse 相关项为 `-vfe_var_range fuse_20 ...`，BAT spec 有 `FuseCheck` 测试名（`pg145sku35_bat_nochk.spc:40`），均不能据此等同于 FuseRework。

文件配对比对结果：

- `pg145sku35_eng.spc` 与 `pg145sku35_eng_nochk.spc`：逐字节相同，2,405 bytes，SHA-256 `dff18b9335a2dfb14e0d7d71b959fb681f4b7d73d7fab3d33eb5a9c540f95d01`。
- `fct` / `fct_nochk`：逐字节相同，35,151 bytes，SHA-256 `7bbd96aace89fc655e08e1288170f5c516fa091f9ac4d321234d5501682b8b94`。
- `fctrotation` / `fctrotation_nochk`：逐字节相同，12,935 bytes，SHA-256 `b933ecc7e43309da5fbd8ea6cd657b86e20e979468017dea8274c49975ed7372`。
- `mss` / `mss_nochk`：逐字节相同，17,717 bytes，SHA-256 `982ba88c0ed0b678bdaa662a28165984f2a8565ee920376808acea63f0259d04`。

注意：包内 `checksum.ignore` 明确写明这些文件从 checksum application 排除（如 `core/mods0/pg145sku35_eng_nochk.spc`、`...fct_nochk.spc`、`...fctrotation_nochk.spc`、`...mss_nochk.spc`，该文件第 9–15 行）。`.checksum.db` 是 SQLite，`FILE_CHECKSUM` 表列有正常 ENG/FCT/MSS spec 与 `recipe_eng.xml`，没有上述 NOCHK 配对。这是**包级校验排除清单**的证据，不应误读为 spec 内部一定跳过某种硬件检查。

FCO/FCT 过程还显示 NOCHK 参数确实被 recipe 传入：`recipe_fco.xml:44,61,78,96,115` 使用 `BAT_SPC_NOCHK`、`T275_SPC_NOCHK`、`FCT_SPC_NOCHK`、`FCTROTATION_SPC_NOCHK`、`MSS_SPC_NOCHK`；`recipe_fct.xml:51,70` 先跑 BAT/T275 NOCHK，后续 FCT/FCTROTATION/MSS 使用普通 spec（第 89、109、129 行）。

## 3. 外部路径、共享与下载线索

### 可执行脚本中的网络共享

`run.sh:42-53` 默认 `NAUTILUS_FACTORY=FXLH`；仅当传入/配置 `NAUTILUS_FACTORY=FXSJ` 时执行：

```text
mount -t cifs -o "user=nobody,vers=1.0" //192.168.2.11/START /mnt/mcu
```

随后 `run.sh:56,58` 无条件把 `--logwarehouse=/mnt/mcu/LOGS` 传给 Nautilus。也就是说有一个条件式 SMB/CIFS v1 共享挂载与网络日志目标；默认 FXLH 分支不执行该 mount。未实际连接或验证该地址。

`operator.txt:26,45,57` 要求将 `652-BW00B-HV40-001`、`652-BW00B-MTLL-001`、`652-BW00B-SUPP-001` trace 目录复制到 `core/mods0`；`checksum.ignore` 第 16–18 行也排除这些目录通配符。包中未看到相应 trace 目录或下载 ID。

### Perforce 与本机路径

多个 spec 注释包含内部 Perforce 源路径，例如：

- `pg145sku35_fct_nochk.spc:4`：`//pte/stie/prod/Spec_Lib/GB20X/GB20X_GeForce/GB202/659/DVT/659_GeForce_GB202_DVT_FCT.spc#7`
- `pg145sku35_mss_nochk.spc:4`：对应 `...GB202_DVT_MSS.spc#8`
- `pg145sku35_fctrotation_nochk.spc:4`：对应 `...GB202_DVT_FCT_Rotation.spc#7`
- `board_common.spc:14,27` 另有 `//pte/stie/prod/tesla/skus/...` 与 `$Id: //sw/apps/gpu/diag/TeslaTestEng/skus/board_common.spc#12 $`。

这些是源版本/历史注释，未见脚本运行时 fetch 这些路径。MODS 字符串还含 `//ate/scripts/dftqtracker/BCA_Ratchet.enc`（原始偏移 `0x89fe110`）；包中未见该路径对应文件，本次未证实其与 FuseRework 的调用关系。

包内 Nautilus 自解包 shell（ZIP 成员 `nautilus`）含一般依赖/更新路径：第 193 行把 `/mnt/nv/nautilus/python3.tbz` 作为 Python 包的本机回退查找位置，第 206–210 行接受 `python3.path` 自定义路径；第 137 行提示客户端发布目录 `https://storage.nvidia.com/nautilus/release/`。单板入口 `nautilus s` 在第 395–397 行派发到 `do_single_dut_test`；更新/下载错误字典的 `do_get_error_dict` 是另一分支（如 `e`，第 375–376 行）及 init/release 流程调用，不能据此断言 ENG 单板运行一定访问发布站点。内嵌 MODS 另有 `https://confluence.nvidia.com/x/4e7-Mw`（原始偏移 `0x88f4850`、`0x88f6530`），上下文是同目录缺失的通用视频 Stream 文件下载说明；不是 FuseRework/GB202 下载标识。未发现 NVOnline ID 或直接指向返修物料的 URL。

## 4. Entitlement / SiteID / debug GFW 与 gldGB202.bin

- 可见 `manifest_secondary.json` 只有 `CM_FIELD:"XXXX"`、`PARTNER:"XXXX"` 占位值和 PCIe 地址列表；`operator.txt:14-17` 要求操作者填 PARTNER/CM_FIELD。没有明文 entitlement certificate、SiteID 值或授权编号。
- `configs/manifest.json`（10,596 bytes）、`.nautilus.config`（228 bytes）、`disposition.dict`、`errorcode.dict` 是 `gAAAAA...` 开头的高熵/编码样式内容，无法按明文键值搜索。未尝试解密；因此它们内可能包含哪些字段仍未知。`run.sh:3-4` 对 manifest 的 `prod`/`sku` grep 在可见密文中不能揭示值，而且两个 shell 变量后续未使用。
- MODS 有 `siteId`/`siteID` 相关技术 API/字段字符串，例如原始偏移 `0x8823498` 的 `Subdevice.GetHBMSiteInfo(HBMSiteInfo, siteID)`、`0x88a2298` 的 `Fusing siteID %d, stackID %d, channel %d, bank %d, row %d`。这些是 HBM/内存修复接口参数文案，没有发现具体 SiteID 值或其作为 entitlement 的证据。
- `run.sh:43` 的默认 `NAUTILUS_PBR="PB-DEBUG"`，以及 `idt.sh:4` 的 `-fslib_mode_debug`，分别是 PBR 字符串和 IDT/FSLIB 测试参数；未发现包内 debug GFW 镜像或其 sidecar 内容。debug GFW **文件名**仅在 MODS 字符串中出现（第 1 节）。
- 已有 `gldGB202.bin` 大小 1,081,608 bytes，SHA-256 `917e1a811777f1e40d40993841a435006d0e7ac7ce4093f4c4b67c97930b72f3`。`strings -a -t x -n 5` 的针对性搜索（FuseRework/FRB/GFW/debug/entitlement/SiteID/URL/共享/文件扩展名）无命中；可见正例是 `0x18` 的 `570.151`、`0xf8178` 的 `GB202Protocol_DP_MST_FFFFLLLL_F_16`、`0xf8a18` 附近的 `Linux_x86_64_GB202`。因此未发现它隐藏了可打印的返修文件名/下载标识。`UHBR.dpc` 是 562-byte DP/UHBR 显示测试 JSON，无上述标识。

## 搜索覆盖与剩余不确定性

- 以只读流式方式检查 ZIP/内层 tar 文件名清单；对现有 27 个文本文件搜查 `FuseRework/FuseRework 拼写变体/FRB/debug GFW/entitlement/SiteID/URL/共享/下载`，逐读 `run.sh`、ENG/FCO/FCT recipes、相关 spec、operator、manifest_secondary；对内层 MODS 二进制做原始偏移字符串搜索；对内层 `.jse/.he/.arg/.bin/.dpc/.json/.sh/.txt` 的可打印字符串也作目标词扫描。可见文本里的 fuse 命中主要是 `FuseCheck` 与 `fuse_20` 参数，不是 FuseRework。
- 未对 Nautilus 自解包载荷中的 Python `.pyc` 反编译，未对密文 manifest/config 解密，也未把 570.151 MODS 提取成新文件做完整反汇编；`.jse` 只做可打印字符串检查。因此结论限于已列出的字符串、成员名与可见调用图，不能排除密文/字节码/非字符串数据中另有逻辑。
- 复核输入哈希未变；未写入或修改任何输入文件。本报告为本任务唯一新增项目文件。

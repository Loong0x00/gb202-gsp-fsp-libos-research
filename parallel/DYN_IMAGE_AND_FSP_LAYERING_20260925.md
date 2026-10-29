# 执行镜像 vs 验签镜像:dyn/gfw 分层与"取指地址"死代码结论

日期:2026-09-25(晚场)  载体:5090/GB202,guest 内 dkms 重编宿主驱动 + 改 bindata
本文件所有结论都配"读回/复核",凡未通过的验证都标注为无效。

## 1. 对象分层(本轮最大的结构性收获)

归档头里的 `// FILE NAME:` 直接给出身世(见 `generated/g_bindata_kgspGetBinArchiveGspRmBoot_GB202.c`
与 `..._GspRmFmcGfwProdSigned_GB202.c`):

| 对象 | 文件 | 尺寸 | 压缩 | 角色 |
|---|---|---|---|---|
| dyn 镜像 | `g_gsp_gb20x_dyn_prd_image.bin` | 290,816 B | NO | **被执行的那块**(BootROM/FSP 分区加载) |
| dyn 描述符 | `g_gsp_gb20x_dyn_prd_desc.bin` | 92 B → 28 B | YES(raw deflate) | **宿主侧取指描述符**(进 BCR/FALCON 寄存器) |
| gfw 镜像 | `g_gsp_gb20x_dyn_prd_gfw_image.bin` | 287,304 B | NO | **FSP COT 验签的那块** |
| gfw 三件套 | `..._gfw_hash/sig/pub_key.bin` | 48/96/97 B | NO | COT 载荷(hash384/signature/publicKey) |

描述符离线解压(raw deflate)得到的真实字段:

```
version=6  manifestOffset=0x0(size=0xA00)  monitorDataOffset=0xA00(size=0xE800)
monitorCodeOffset=0xF200(size=0x37000)  bIsMonitorEnabled=1   其余全 0
```

两份镜像的字节关系:`dyn[0xF200:+0x37000] == gfw[0x48:+0x37000]`(225,280 B 逐字节相同);
gfw 头 72 B 自洽:`ver=0x0403 hdr=0x48 payload=0x46200`,payload = manifest(0xA00)+data(0xE800)+code(0x37000)。

## 2. 哪块被验、哪块被执行(实测)

- FSP 侧:`kfspSetupGspImages` 把 `pGspFmcMemdesc`(= **gfw 镜像**)的物理地址塞进 COT 载荷
  (`kern_fsp_gh100.c:1005-1042`)⇒ FSP 只验 gfw。
- 改 **gfw** → FSP 拒绝(`Task 0x1 / Cmd 0x14 / Err 0x33`,SCRATCH_GROUP_2(0)=0x9f,`0x62:0x40`)。
- 改 **dyn**(执行侧)→ **FSP 完全无抱怨**,推进到 GSP-RM 引导,由设备侧报:
  `Fatal GSP-FMC Error: version=0x1, partition=0x1, error code=0xaff, additional info=0xb`
  → `kgspInitRm_IMPL: Max GSP-RM boot attempts exceeded: 4/4` → `RmInitAdapter failed! (0x62:0x55:2119)`。
- dyn 的**代码段翻 1 字节**与**数据段翻 1 字节**给出**同一个 0xaff** ⇒ 执行镜像(代码+数据)**整体**
  受设备侧保护,且这套保护与 FSP 的 COT 是**两套独立机制**。

## 3. "宿主给取指地址"通道 = 死代码(三重证据)

1. 只把描述符 `monitorCodeOffset 0xF200→0x200`(镜像内容零改动)→ **nvidia-smi rc=0,设备正常启动**;
2. 同一轮驱动补丁的读回打印(`XDIG BCR rb: FMCCODE=... FMCDATA=... PKCPARAM=...`)**一条未出现**;
   而该字符串经 `strings nvidia.ko.zst` 确认**已编入本轮加载的模块**(模块时间戳与构建时间一致);
3. 静态:`bPartitionedFmc=TRUE`(GB202 等,`g_kernel_gsp_nvoc.c:466-475`)⇒ FMC 由 FSP 分区加载,
   驱动里 `_kgspBootstrapGspFmc_GH100`(写 `NV_PRISCV_RISCV_BCR_DMAADDR_*` 的那段)`kernel_gsp.c:4970` 分支不走它。

⇒ 宿主无法通过描述符/BCR 给设备指路:该函数在本平台不被调用。

## 4. COT 载荷字段是硬校验,不是"空值跳过"

- `hash384` 置零(镜像不动)→ FSP 报 **Err 0x377**(与"哈希不符"的 0x33 **不同**)⇒ 字段非法会被单独识别,无 null-skip。
- 自签(镜像零改动 + 我们的 P-384 密钥)+ `RmDisableFspFuseErrorCheck=1`(该轮 RM 明确打印
  `kfspInitRegistryOverrides: FSP's fuse error detection status check during boot is disabled using the regkey.`)
  → 仍被拒,Err **0x1db** ⇒ 该旋钮只关"熔丝错误状态检查",不削弱密钥强制。

## 5. 本机实测错误码汇编(以后对表用)

| 实验 | 设备/FSP 指纹 | RmInitAdapter |
|---|---|---|
| gfw 镜像哈希不符 | Task 0x1 / Cmd 0x14 / Err 0x33,SCRATCH_GROUP_2(0)=0x9f | 0x62:0x40 |
| 自签(换密钥,镜像不变) | Err 0x1db(+fuse 旋钮);无旋钮时同 0x40 路径 | 0x62:0x40 |
| COT hash 字段置零 | Err **0x377** | 0x62:0x40 |
| 跳过 COT(`RmDisableCotCmd=48`)+ 改镜像 | — | 0x62:**0x65** |
| 改 dyn(执行侧,代码或数据) | `Fatal GSP-FMC 0xaff/0xb` + `Max attempts 4/4` | 0x62:**0x55** |
| 只改描述符取指地址 | 无 | **启动成功** |

## 6. 方法学教训(已修正)

同一台 VM 内重复 `modprobe -r/-` 之后,设备状态残留(上次失败留下的 WPR2/分区未清),
后续变体的"失败"不可归因到变体本身 ⇒ **一变体一台新 VM**。Z5 的后三个变体(sig/pkey/ver)因此作废,未计入结论。

## 7. 结论

宿主可达的每一层都各有一把**设备侧锚定**的锁,且互不共用:

1. **验签对象(gfw)**:FSP COT + 钉死密钥(Y1 实测);
2. **执行对象(dyn)**:设备侧整体校验(0xaff);
3. **取指地址**:死代码,不可达;
4. **COT 字段**:硬校验 + 专用错误码(0x377/0x1db/0x33);
5. **唯一的"削弱型"旋钮**(FuseErrorCheck):实测无效。

剩余可选路径(概率均低,如实记录):
- (a) sig/pubkey 置零、version=1 三个变体(一 VM 一个);
- (b) 系统化 fuzz 启动命令/COT 结构(成本高;FSP 校验风格严谨,已有专用错误码);
- (c) 设备固件内部(FSP µcode v6 加密,本地无明文,静态不可及)/ 熔丝与签名(需内部通道)。

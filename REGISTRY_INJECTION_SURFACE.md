# 宿主→GSP 注册表注入攻击面 — 普查报告 (2026-10-01 凌晨)

## 核心发现

**宿主驱动通过 fn73 (SET_REGISTRY) RPC 把自己的全部注册表打包转发给 GSP-RM，
GSP 侧无认证地消化这些键值并用于自身初始化配置。**

```
宿主 root: echo "RmAnything=1" > /proc/driver/nvidia/registry
  → RmPackageRegistry() 打包全局+本地注册表 (任意键名!)
  → fn73 SET_REGISTRY RPC → GSP 消化
  → GSP-RM 初始化时按键名读取并改变行为
```

已实证: RmFspUseMnoc 经此路径送达 (transport init 读取点确认);
机制级验证: 9/30 晚 guest 内 RmFspUseMnoc=2 注入后 MNOC p0 车道被武装。

## 威胁模型定位

**CC (Confidential Compute) 威胁模型 = 宿主不可信**。
GSP 的安全意义就是"防御被攻陷的宿主"。此机制允许宿主 root
直接配置 GSP 的安全相关行为 = 架构级信任倒挂。

非 CC 场景下也成立: GSP 作为若干操作的信任根, 其配置不应由宿主任意摆布。

## 键名普查 (固件 gsp61057_rx_full.bin)

```
Rm* 键总数:      441
安全相关候选:     75
Tier-1 (名字即罪): 
  RmAllowPrivSecDisabled      — "允许特权安全禁用"
  RmDisableFsp                — 禁用 FSP transport (读取点×2已钉: 0x15036e0, 0x1509370)
  RmDisableSec2 / RmDisableSec2Load — 禁用 SEC2 安全引擎
  RmDisableCotCmd             — 禁用信任链命令 (读取点: 0x15093a4, transport init 内)
  RmDisableFspFuseErrorCheck  — 禁用 FSP 熔丝错误检查
  RmDisableFakeEntryCheck     — 禁用假入口检查
  RmSkipSkylineChecker        — 跳过内存完整性检查 (读取点: 0x14d3d34, 无守卫,
                                flag→[s6+0xC30], seqz(value==1) 模式)
  RmSpdmEnableFuzz            — SPDM 模糊测试模式 (读取点: 0x1503a28,
                                ==1 → ctx+0x36b 置位)
  RmDisableDHKeyExchange      — 禁用 DH 密钥交换 (CC 会话建立!)
  RmHulkDisableFeatures       — HULK 特性禁用
  RmRouteToPhyiscalLockBypass — 物理锁绕过 (读取点: 0x100d7e4)
  RmTestOnlyCode              — 测试专用代码路径
  RmClockUprocSecurityCheck   — 安全检查控制 (读取点: 0x1171764)
```

**所有已解剖读取点均无生产态守卫** (无熔丝检查/调试模式门),
模式统一: `registry_read(ctx, name, &v)` → `if (v==1) flag/跳转`。

## 载荷结构 (宿主侧 g_os_nvoc.h)

```c
typedef struct PACKED_REGISTRY_ENTRY {  // 16字节自然对齐 (type后3字节padding洞)
    NvU32 nameOffset;   // ★ 宿主控制的偏移 → GSP 解析器用它定位键名
    NvU8  type;         // 0=unknown 1=dword 2=binary 3=string
    NvU32 data;
    NvU32 length;
} PACKED_REGISTRY_ENTRY;

typedef struct PACKED_REGISTRY_TABLE {
    NvU32 size;         // 总大小
    NvU32 numEntries;   // ★ 宿主控制
    PACKED_REGISTRY_ENTRY entries[];
} PACKED_REGISTRY_TABLE;
```

宿主打包侧 (registry.c regCopyEntriesToPackedBuffer) 边界检查完备,
表本身合法 — 攻击需宿主篡改表内容 (CC 威胁模型下 = 内核内存补写, 平凡可行)。

## 待办 (按优先级)

1. **GSP 侧解析器审计** (fn73 handler):
   - nameOffset 是否有界检查? (越界读 = 相对任意读/键名混淆)
   - numEntries vs size 一致性校验?
   - 键名 NUL 终止假设?
   - 定位线索: 注册表读取函数 = 0x103C054 (修正auipc符号扩展后),
     找对称的 store 函数 → 其调用者 = 解析器
2. **实证实验** (补丁驱动加畸变旋钮):
   - 打包后篡改 nameOffset=0x41414141 → 观察 GSP 崩溃形态 = 无界检查实锤
   - RmSpdmEnableFuzz=1 注入 → 观察 SPDM 行为变化
   - RmDisableCotCmd=1 注入 → 观察 COT 命令流消失
3. **Tier-1 键逐个读取点解剖** (剩余未钉死的)
4. fn73 大表路径 (>maxRpcSize 时走 portMemAllocNonPaged 大RPC缓冲) — 另一条解析路径?

## 与既有武器的关系

- K3-1 注入链 (溢出/劫持/任意读写) = 更强原语但需驱动补丁
- 注册表注入 = 零补丁、纯配置面, 但只能改"有键可改"的行为
- 两者互补: 注册表面做侦察/降级, K3-1 做精确打击

---

# 💥 实弹结果 (2026-10-01 上午): 解析器漏洞证实

## 实验装置
补丁驱动 (v20) 在 fn73 发送前篡改载荷 (checksum 之前, 消息合法到达 GSP):
- mode 1: entries[0].nameOffset = 0x41414141 (野偏移)
- mode 2: numEntries = 0xFFF (谎报 4095 条, 实际 ~30)

## 结果

| mode | 弹着点 | 判定 |
|------|--------|------|
| 1 | 无崩溃, 初始化完整走完 (fn76 序列正常) | nameOffset 路径有防护(或有界) |
| **2** | **Xid 120, pc=0x1b8ffbc, stval=0x4fe6, task:3** | **numEntries 无校验 → 越界走表 → 内存损坏 → GSP 崩** |

## 漏洞叙述 (草稿)

```
组件: GSP-RM 固件 (610.57.04) 的 RPC fn73 (SET_REGISTRY) 处理器
缺陷: 解析 PACKED_REGISTRY_TABLE 时信任宿主提供的 numEntries,
      未以 size 字段约束条目走表范围
触发: 宿主构造 numEntries=4095 的表 (真实条目 ~30)
效果: 解析器越过表尾继续读条目 ~4000 条 → 状态损坏 → GSP task exception
崩溃签名: pc=0x1b8ffbc, stval=0x4fe6, scause=0xd (load access fault)
威胁模型: CC (宿主不可信) — 恶意宿主可稳定打崩 GSP (DoS);
          更深: 若配合 K3-1 staging 控制, 表后内存可控 →
          越界"条目"的 nameOffset/type/data 全部可伪造 = 注册表投毒
```

## 组合攻击展望 (K3-1 × 本漏洞)
K3-1 溢出控制 RPC 缓冲区之后的 staging 内存 → 那正是 numEntries 越界
走表读到的区域 → 伪造的"条目"内容完全可控 → 向 GSP 注册表注入
任意(键,类型,值) — 包括驱动永远不会发送的内部键。
= 无需 /proc, 无需驱动打包, 直接从内存投喂。

## 复现
1. /usr/src 源码 _xdigRegFuzz = 2u (硬编码)
2. dkms install; rmmod/insmod; nvidia-smi
3. dmesg: REGFUZZ mode=2 → Xid 120 @ 0x1b8ffbc
日志: dmesg_regfuzz_mode2_CRASH.txt

---

# 梯度实验结果 (2026-10-01 下午, VM工作流)

## 数据
| 越界 | 结果 | 机理 |
|-----|------|------|
| +1 | 存活 | 幽灵=名字串字节 → 野offset → 拒收 |
| +2 | 存活 | 同上 |
| +3 | **崩溃** (0x1b8ffbc) | 走入零填充 → offset=0 → 垃圾键入册 |
| +5 | 崩溃 | 更多零条目 |
| (mode2: +4094) | 崩溃 | 海量零条目 |

## 精确机理模型
1. nameOffset 有界校验存在(野值拒收 = mode1/+1/+2的证据)
2. 但 offset=0/小值 通过校验(指向表自身=形式合法)
3. 被注入的垃圾键: 名字=表头字节(size/numEntries字段), type=0, data=0
4. 少量垃圾键→下游通道查找崩(0x1b8ffbc teardown签名)

## Trinity 完整设计 (v2, 含桥梁解法)
```
垫片: /proc 写 ~250 个 RmPadXXX=1 (Binary型, 1字节数据, 会被打包)
  → 真实表(条目+名字区)膨胀至 ~4KB = 恰填满元素0
桥: 真实表尾(名字字节)到元素1边界之间的幽灵条目 → 全部野offset → 无害拒收
弹: K3-1 填充元素1+ = 伪造条目 {nameOffset→受控名串, type=1(DWORD), data=值}
引信: numEntries = 真实 + 桥幽灵数 + 伪造数 (精确止步, 零区永不触达)
效果: 任意键名+正规DWORD类型注入GSP注册表
```

## VM工作流经验
- 崩溃后: system_powerdown → fwupd stop job 卡死(超时指数翻倍) → 直接quit+换vars
- /tmp 会被重启清 → 脚本放 ~/
- guest dkms 产物是不压缩的 .ko (zstdcat会造空文件)
- guest nvidia 拦截(/etc/modprobe.d)持久有效 ✓

---

# 2026-10-01 深夜: FSP 通道矩阵探测 (VM, 无驱动状态BAR0直打)

## EMEM 通道全解码 (内核源码 kern_fsp_gh100.c 配方)
```
窗口: 1KB @ EMEMC/EMEMD (0x8f2ac0/ac4), AINCR=bit25读自增, AINCW=bit24写自增
队列: CMDQ 0x8f2c00/04, MSGQ 0x8f2c80/84 (RM通道)
投递: EMEMC=0|AINCW → 数据dword流写EMEMD → QT=字节数-4 → QH=0 (HEAD写=中断)
消费: FSP收包后置 QH=QT (归零)
✅ 宿主可读写EMEM (写不挂死! 旧"EMEM写挂死"结论只适用nvflash的错误姿势)
✅ FSP确实消费了包 (队列归零了)
❌ 但从不响应 (0x1A/0x13都试过, MSGQ永远空)
```

## 通道矩阵 (最终)
| 通道 | 宿主可用? | ROMREAD(0x1A)? | 证据 |
|------|----------|----------------|------|
| MNOC p1 | ✓ PRC响应 | ✗ transport error (bit25) | 0x1A写入直接err |
| MNOC p0 | ✗ bit24=0 (GSP占用) | — | 宿主not-ready |
| EMEM CMDQ | 半通(收包不答) | ✗ 静默 | QH/QT归零但MSGQ空 |
| ROMREAD结论 | | **GSP车道专属** | CAPS广告了但宿主道无handler |

## 里程碑路径定论 (FSP明文代码)
```
唯一通路: 活GSP + K3-1 → 以GSP身份发ROMREAD(0x1A) → FSP服务
  → dump FSP mask ROM → 从ROM逆向解密算法 → 离线解密flash里的FSP固件blob
具体注入点: tdispmgr(0x18BBD60)假对象树 (只吃a1=我们staging里的假树)
  或: GSP自己的FSP send函数 + K3-1劫持调用
前置静态工作: mctpSubmit(0x1B594D0)解引用链 (1-2h)
```

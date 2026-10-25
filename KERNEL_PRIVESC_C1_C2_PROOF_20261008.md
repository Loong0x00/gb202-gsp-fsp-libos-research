# LibOS 内核提权漏洞 C1/C2 — 模拟器实证 (2026-10-08)

工具: `rv64_emu.py` + `/tmp/kernel_gb20x.elf` (boot 160万步后 S-mode 直调内核函数)
脚本: `emu_test_c2_release.py` / Phase C 内联复现

---

## ⚠️ 地址勘误 (修正本目录早前文档的错误)

之前 auipc 手算偏了 0xA000,本次经模拟器单步验证的真实地址:

| 对象 | 错误值(旧) | 真实值(本次实证) |
|---|---|---|
| 类型/析构表 | 0xa301a000 | **0xffffffffa300a000** (entry=40B, dtor在+0x28) |
| pool描述符数组 | 0xa3014020 | **0xffffffffa300a020** (40B/项) |
| 除法魔数 | — | [0xffffffff9300b678] = 0xCCCCCCCD (即 /5, 配合>>3 = /40) |

真实公式 (0x9300408c):
```
type_id = ((desc − 0xffffffffa300a020) >> 3 × 0xCCCCCCCD) mod 2³²
        = (desc − 0xa300a020) / 40      ← 无任何边界校验
```
RELEASE (0xffffffff930060f2) destroy路径:
```
slot = 0xffffffffa300a000 + u32(type_id)×40 + 0x28
dtor = [slot]                            ← OOB读, 可达范围: 表基址起 +160GB
      (含 mod 2⁶⁴ 回绕 → 覆盖 0x0..0x27FFFFFFD8 低地址窗口 ≈160GB)
jalr dtor   (a0=对象指针, S-mode)         ← 无校验直接跳转
```

---

## 🎯 C2 实证: 页头投毒 → S-mode 任意跳转

```
[boot] 1605736步 (PMP窗口与静态分析100%吻合)
Phase A 公式探测: desc=base+k×40 → ret=k 精确命中 (k=0,1,2,5,10,100,5632,0x28CC334)
Phase B 攻击:
  K = 0x28cc99b  → desc_fake = 0x9002058 (写入假对象页头+0x20, 8字节)
  slot = 0x9002060 (攻击者scratch页) 预置 0xcafec0de
  RELEASE(假对象, refcount=1):
    实测jalr目标 = 0xcafec0de
    stop = UNIMP@kernel pc=0xcafec0de     ← 内核在S-mode跳到攻击者指定地址 ✅
```

**含义**: 对象页头 pool指针 8字节污染 = S-mode 控制流劫持。
**真机约束**: slot 读取需 S-mode 可访问 → 实际武器化时 type_id 取小值落在内核数据段内
(0xa300a000..0xa31c000), 目标可选取含攻击者数据的内核堆页(IPC消息体等)。

## 🎯 C1 实证: 非原子refcount → 双destroy → freelist环

RELEASE 的 `ld a5,-8(a0) / addi -1 / sd` 三连非原子(全内核0原子指令),
timer tick/外部中断可落在 ld 与 sd 之间:

```
T1: 执行 ld (a5=1) 后挂起            ← 中断窗口(实测pc=0x930060f8)
T2: 完整RELEASE → destroy#1 (freelist头=0x90040f8, pool_cnt 0→0xFFFFFFFF)
T1: 恢复 → 写回过期值0 → destroy#2
    [obj-8] = 0x90040f8 == obj-8      ← freelist 自指环 ✅
后果演示:
    分配#1 → 0x9004100
    分配#2 → 0x9004100  ← 同一对象两个所有者 → 内核结构类型混淆 ✅
```

**真机参数**: 丢失更新窗口 = ld→sd 间 6 条指令; 中断源 = timer tick(heartbeat)
+ extintr + IPI。RM可经RPC风暴放大RELEASE调用频率 → 概率累积。

---

## 完整提权链 (待补中间环节)

```
RM操作(RPC/IPC风暴) → C1 refcount竞争 → 同对象双分配(类型混淆)
    → [缺口: 找一个字段被内核写入的混淆对象 → 内核数据写原语]
    → 污染对象页头+0x20 (8字节)
    → C2: jalr → S-mode 任意代码执行
    → 之后: 改快表0xa3008ce8持久化 / 直写PMP CSR 1482-1487 开全内存
```

## 与既有工作的衔接
- V2 (K3-1 staging溢出) 已给 RM 进程内任意读写 = RM用户态全控; C1/C2 是 U→S 的最后一跳
- V1 (fn73 崩溃) 的 Xid 120 崩溃可能是踩中 C2 的 jalr-to-garbage (待归因)
- 早前结论"低别名U位挡住用户态"不受影响 — C1/C2 是内核自身路径, 与低别名无关

## 下一步
1. 中间缺口: 枚举 pool 对象类型(type表+0x38字段/分配器调用点), 找"内核写字段+用户读回"
   的混淆对象 → 补全 8 字节页头写原语
2. 真机验证: RV侧无法调试 → 用 V2 写原语从 RM 侧构造 C1 竞争(两任务对同一port对象RELEASE)
3. V1 崩溃 jalr 目标归因 (对照 dmesg_regfuzz_mode2_CRASH)

---

## 附录 B: 中间缺口攻关纪要 (2026-10-08 session 2)

### 模拟器保真度发现 (影响所有后续实验)
1. **内核 boot 后运行在低别名** 0x9300xxxx — rv64_emu 的 memset 快转发只认高别名 →
   曾在字节级 memset(清零32MB池)上空烧 3700 万步。补丁: step() 里把低别名 0x93004eea 改写为高别名。
2. 内核 init 的 SBI 通道建立极长: ecall#192 仍在通道 0x3f (a4=0x7a0000..0x7e0000 物理区),
   之后陷入 0x9300737a 通道链表工作队列 (0x9300036a 双链摘除×百万次), 130M 步不收敛 —
   **模拟器未能完整跑完内核init** (可能是真实工作量大,也可能 SBI ecall 假返回 a0=0 导致重试)。
3. RM spawn 配方 (emu_run_rm.py) 依旧有效: 任务建立成功, RM U-mode 起跑, 发出第一个 syscall。

### RM 实测捕获 (首次!)
```
RM第一个syscall: t0=1  a0=3  a1=0  a2=0x41cd700(65MB尺寸!)
  → 内核经 SPAWN_TASK 路径 (call@file 0x9c68, 动态type) 分配 type=4 对象
  → type 4 = 任务对象
```

### C1 竞争面扩大 (新证)
- t0=1 handler 内 **shuttle 非原子ACQUIRE**: 0xffffffff93002542
  `s0=[task+0x30]; a5=[s0-8]+1; [s0-8]=a5`  ← 又一处 ld/addi/sd 三连
- shuttle(task+0x30) 是 **syscall上下文与调度器共享的对象** — 双上下文RELEASE/ACQUIRE
  = C1 的天然竞争目标 (真机上 timer 中断切换即命中窗口)
- **0x9300408c 兼职"类型检查"**: t0=1 在 0x9300259c 调它验证句柄对象 type==6
  → 页头投毒不仅触发C2, 还能让类型检查错判 → 更多confused-deputy入口

### 对象类型目录 (静态普查: 25个分配点)
```
type  1,2,3,5,7,8,9,11,12,14,15,16,18,19,20,21 (各1处常量调用) + 8处动态
已知语义: type4=任务(SPAWN) type6=SBI通道(T15/t0=15) typeA=端口(t0=23) typeE=t0=25
类型表记录布局(40B): +0x28 dtor | +0x30 in-use | +0x34 高水位 | +0x38 freelist游标
```

### 中间缺口候选 (8字节页头写原语, 按可行性)
1. **C1双分配 → shuttle/port对象混淆**: shuttle字段含 owner/result(+0x10)、
   state(+0x00) — 由内核写; 需找到一个"用户参数→对象字段"的写入点 (port消息体最可疑)
2. **freelist游标/页freelist二轨制待核对**: RELEASE插入[page+0x18]链,
   分配器快路径消费[entry+0x38]游标链(+0x10链接) — 两条链如何合并(refill路径
   0x9300036a/0x930051c4-0x93005214)未核对; Phase C的"分配两次"是手工模拟, 真机
   双分配需走真refill路径 (验证项!)
3. 类型检查混淆(t0=1的type==6判定) → 以SBI通道身份通过检查 → 走特权分支

### 下次优先级
A. 核对refill路径 → 确认真机双分配可达 (纯静态, 30min)
B. 修模拟器SBI返回值 → 完整init → fn=72 RPC注入 (项目主线)
C. port消息体写入路径 → 找用户字节落点与页头距离 (混淆代理关键)

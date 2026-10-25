# 会话总结 — 2026-10-02 全天 (GSP权限探索 + FSP通道审计 + 内存布局)

## 重大发现

### 1. GSP 完整内存权限图 (实验确认)
```
代码段 (0x1000000-0x1E9B000):  R-X  ← 写=page fault 0xF ✗ (WPR硬件保护)
数据段 (0x0400000-0x041D5000):  RW   ← 应该可写
堆/staging (0xFE4xxxxxxx):      RW+XN ← 可写✓ 不可执行✗
栈 (0xFEB8xxxxxx):              RW+XN ← 可写 不可执行
寄存器窗口 (W=0x08200000):       RW   ← 可写✓ (EMEMD/MNOC验证)

结论: 完整的W^X实现,没有任何RWX区域。
     不能在GSP上执行任意代码(只能调用已有函数)。
```

### 2. FSP Falcon 内存完全隔离
```
FSP IMEM/DMEM (BAR0 0x8F0100-0x8F0140):
  从宿主: 0xbadf5620 (死区)
  从GSP:  0xbadf* (同样是死区,通过泄漏读证实)
  GSP写IMEMD: 无fault但无效果(静默丢弃)

结论: FSP内存在硬件层面完全隔离,连GSP都读不到。
```

### 3. 关键地址修正
```
错误: 通道表全局 = 0x41B17678 (~1GB, "神秘区域")
正确: 通道表全局 = 0x04191678 (65.6MB, ELF数据段内!)

修正方法: mctpSubmit@0x1b59782 的auipc+addi精确重算
影响: 之前所有引用0x41B17678的分析全部作废
好消息: 所有全局变量都在ELF数据段,地址固定跨boot不变
```

### 4. 完整GSP固件ELF发现
```
文件: /lib/firmware/nvidia/610.57.04/gsp_ga10x.bin (84MB)
结构: 容器格式,内嵌多个ELF
主GSP ELF: 容器偏移 0x19f040
  LOAD RX VA=0x1000000-0x1E9B000 (代码, 14.6MB)
  LOAD RW VA=0x0400000-0x041D5000 (数据, 1.86MB) ← 之前缺失的段!
  TLS VA=0x203C6000
```

### 5. 泄漏读原语验证
```
通道表(0x04191678)运行时值 = 0x0FE4790E10 = staging元数据地址
mctpSubmit入口全局(0x0418FF68) = 0x77f2058f82306a67 (哈希/魔法数,非指针)

泄漏读方法: 读gadget(0x1020A30) + a1=目标-0x168
  → load [目标] → jalr → crash → stval = 值
  限制: 目标必须8字节对齐,每次boot只能读一个
```

### 6. MNOC通道完整矩阵 (今日重测)
```
       P0(GSP道)      P1(宿主道)
PRC    ✗ 硬件拒        ✓ 可用
FWUP   ✗ 硬件拒        ✓ cmd6通,cmd1-7=0x188(会话门)
COT    ✗ 硬件拒        ✗ 类型过滤(瞬时ERR)
ROMREAD ✗ 硬件拒       ✗ 类型过滤(瞬时ERR)

MNOC ERR位: 硬件锁存,只有GPU物理断电才能清
           VM重启/驱动周期/PCIe reset都不清
```

### 7. GSP固件无MNOC静态引用
```
搜索auipc+addi对: 目标0x08AF1E00/0x08AF1F88/0x08200000等
结果: 零命中!
原因: GSP通过运行时HAL对象间接访问硬件寄存器
     寄存器基址存在数据结构中,不是静态常量
影响: 找不到"简单发MNOC消息"的函数入口
```

## MODS通信路径确认
```
MODS使用MNOC port 1(宿主道) — 与我们完全相同的通道!
无魔法,无GSP路径,就是用户态工具+正确的PRC子命令。
MODS的task2/subobject1能降PLM(0x8200d0/0x8200dc)。
```

## V3注册表键静态分析
```
14个Tier-1键的消费点全部定位(auipc+addi扫描):
  RmDisableFsp@0x15036e0,0x1509370 → 跳过FSP transport初始化
  RmDisableCotCmd@0x15093a4 → obj[0x1DB]=1
  RmSpdmEnableFuzz@0x1503a28 → SPDM fuzz模式
  RmDisableDHKeyExchange@0x10c3b1e → obj[0x1B1]=1
  RmSkipSkylineChecker@0x14d3d34 → flag→[s6+0xC30]
  (全部13/14个已钉死,详见V3_KEY_STATIC_ANALYSIS_20261002.md)
统一模式: registry_read(ctx,name,&v) → if(v==1) 跳过检查
零守卫: 无熔丝检查/无调试模式门
注入障碍: /proc写入是Binary类型,GSP按DWORD读不到
```

## 假对象树分析
```
ROMREAD handler(0x1501628)读:
  a0+0x1D70 → transport后端指针(staging外,不可控!)
  a1+0x118 → 发送函数(我们的受控数据内 ✓)

问题: a0+0x1D70 = staging+0x21DFC = 超出staging分配范围的堆垃圾
     无法从RPC消息或MAP注入控制这个位置

GSP固件中的MNOC/EMEM访问全部通过HAL对象间接完成
→ 找不到"只要a1指向数据就能发消息"的简单函数
```

## 今天排除的死路
```
✗ GSP写自己代码段 → WPR page fault
✗ GSP读FSP IMEM/DMEM → 0xbadf*死区
✗ GSP写FSP IMEMD → 静默丢弃
✗ PMP/CSR修改 → 固件中无此类指令(数据误报)
✗ 代码洞写入 → page fault
✗ 堆执行 → XN
✗ "不装驱动"让FSP停boot phase → FSP自己boot后照样锁port 0
✗ MNOC port 2/3 → 从未武装
```

## 仍存活的路径
```
1. 假对象树(tdispmgr蹦床) — 理论可行但对象图深,需要更多静态分析
2. FSP接口fuzzing — PRC/FWUP是活的,可能找到解析漏洞
3. 物理flash dump — CH341A(用户已购买)
4. 注册表键注入 — 需要解决DWORD注入姿势
5. 泄漏读侦察 — 每次boot读一个全局,可以逐步画出运行时对象图
```

## 关键文件索引(今日新增)
```
FSP_CHANNEL_AUDIT_20261002.md — MNOC/EMEM/FSP寄存器完整审计
FULL_REREAD_FINDINGS_20261002.md — 全量文档重读,未探索线索清单
V3_KEY_STATIC_ANALYSIS_20261002.md — 注册表键消费点分析
/tmp/gsp_610_full.bin — 完整84MB固件(含数据段!)
```

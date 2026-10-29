# GB202 显存初始化接受性：明确分支与尚未跨过的边界

## 结论先行

**找到并验证了初始化相关组件的明确判断分支，但仍未取得GB202设备端颗粒几何/训练代码入口，不能报告“48/96GB初始化已接受”或“已拒绝”。** 本轮没有再以预置最终容量寄存器作为测试。

关键进展：
1. 真正执行了 **CPU Devinit脚本使用的timing选择helper及其调用的原MEMINFO解析器**。发现MEM TYPE查找失败并不必然在这里拒绝：会回退到strap转换表。
2. 查清前轮CFG0 writer的HAL适用边界：**GB202命名family的已测槽位不绑定它**；三个旧timing设置槽返回`NV_ERR_NOT_SUPPORTED`。不能把旧setter范围直接套到GB202 boot。
3. 查清应用名称与职责：当前ROM app19在NVFlash中名为`DevInitFMC`，id89有`postLtssmDevinitCfgDataTable`名称证据。显式`FbInit`对应app08，但两份GB202 ROM均无app08。
4. 公开GB202专用代码证明，冷启动devinit中的FBFalcon training位于 **GSP-RM加载之前的FSP安全启动阶段**。在GSP主体中找到的配置/日志分支不是这一阶段的颗粒接受算法。

本轮纯离线，没有新增GPU读取或配置操作；没有native执行MODS/NVFlash/固件，原文件哈希保持不变。

## 1. 实际运行的初始化相关分支：CPU Devinit timing选择

原MODS机器码：`[0x6712970,0x6712a4d)`，221字节。Devinit脚本解释器内`0x671411c`、`0x67157d0`调用它；另有其它调用点。它在`0x67129a2`真实调用原MEMINFO函数`0x672c9e0`，并非hook直接返回解析结果。

**这是一条CPU Devinit辅助路径，未证明GB202实际冷启动使用它。** 不把“Devinit”名称当成GB202可达性保证。

恢复并执行的局部行为：

```c
status = original_meminfo_parser(...);
if (status == 0)
    candidate = selected_record.timing_index;
else {
    candidate = read_STRAP_MEMSEL();
    if (translation_pointer != 0)
        candidate = ROM[translation_pointer + candidate];
}
if (candidate > bound) {
    *timing_index = 0;
    *bound_out = bound;
    return 0xffff;
}
*timing_index = candidate;
*bound_out = bound;
return 0;
```

具体分支：
- `0x67129a9`：MEMINFO非零→`0x67129e0`回退。
- `0x67129fa`：转换表指针为0则使用原始selector；此零指针分支本轮未单独覆盖。
- `0x67129c4/29c6`、`0x6712a12/2a14`：比较候选值与bound。
- `0x6712a20`：打印`Incorrect memory strap index`，返回`0xffff`（`NV_ERR_GENERIC`）。

### 原ROM输入的结果

两ROM的M token首字节均13、转换表指针均`0x4825`。这些值在harness中由ROM填入模拟VBIOS对象，**未运行整个BIT初始化流程**。字段位置有原代码依据：当前M v2/length41选格式`1b2w2d1w`，展开的M+0与M+1/u16经`0x670e202/0x670e217`复制到对象+42c/+430。

| 原ROM / selector | MEMINFO返回 | helper后续 | helper返回 |
|---|---:|---|---:|
| 5090 / 0 | 0 | 使用timing index0 | 0 |
| 5090 / 4 | `0x4a`（缺表项） | 回退转换表，得到index4 | **0** |
| PRO / 4 | 0 | 使用timing index4 | 0 |
| 两者 / 13 | `0x4a` | 回退转换表，得到index5 | 0 |

**这修正了一个潜在错误推论：不能仅凭5090的MEM TYPE config4为Skip，就认定所有初始化路径当场拒绝。** 但helper选择成功也不会凭空生成PRO的几何参数，不能据此说selector4能初始化96GB。

### 边界与负控

仅在模拟ROM内，把5090的selector4转换结果改为：
- 13 → 返回0/index13；
- 14 → 返回ffff/index0。

所以这段原码条件确实是 **≤13**，不是<13。它不证明id89存在第14个合法配置，也不证明后续脚本安全/训练成功。

另有缺失strap响应时harness停止的负控；这是**仿真依赖缺失**，不是设备返回的拒绝码。

共64次原ROM输入执行及3个控制。0..15是主要测试范围；16..31只是扩展反事实，可能读到转换表后邻接字节，**不作为有效物理strap或支持配置的证据**。没有宣称转换表实际有32个合法项。原来的容量寄存器映射已从harness移除。

产物：`tools/emulate_devinit_selector.py`、`reports/devinit_selector_execution.json`。

## 2. GB202命名HAL family的实际分派：旧writer不是这组槽位

通过具有明确`fuseGetState_GB202`字符串的数据流，找到其Fuse实现`0x705b4f0`。对Fuse与FB两个constructor的原始指令分别枚举96个selector。

使用这一GB202命名实现的selector组为`46/47/49/4a/4b`（均十六进制）；在其FB HAL中：

| 槽位 | 绑定 | 含义 |
|---|---:|---|
| +6f8 | `0x6c044a0` | 单条ret，不执行旧CFG0 writer |
| +738 | `0x700de00` | 地址解析器；广播offset200→9a0200 |
| +808/+810/+818 | 三个短stub | 固定返回`0x56=NV_ERR_NOT_SUPPORTED` |

前轮的`0x700f500` writer只在已测`1e..22`组绑定。其实际写9a0200、条件调整位、相等则跳过写入等行为已用72个案例验证；三个旧timing setter范围用780个案例验证，但它们**不是上述GB202命名family的这几个槽位**。

限制：实际PCI设备到具体selector还未完整闭环；这里只是**family/已测槽位级结论**，不能排除其它槽位、直接调用或设备固件消费者。0x56表示该接口不支持，并不是针对48/96GB的判定。

详见`mods_init/REPORT.zh-CN.md`、`hal_matrix.json`。

## 3. 设备应用定位：比上轮更明确，但仍未得到训练代码

NVFlash只被静态解析。名称元数据、callback selector，以及实际查表函数`0x4bce0a`的`entry[0]==selector`比较，构成以下关系：

| ApplicationID（hex） | NVFlash名称 |
|---|---|
| 07 | FalconUcodeFWSecLic |
| 08 | FalconUcodeFbInit |
| 18 | FalconUcodeSwitchBoot_PROD |
| 19 | DevInitFMC |
| 15 | PostLtssm |

查表的virtual+8d0返回entry+2的descriptor ROM相对指针，**不是entry index**。具体vtable在GB202运行时实例化仍未证明，但selector字段语义已有原始比较指令。

- Astral及PRO WS两份ROM均有07/18/19/15，**均无08**。不能把旧FbInit app08直接套到这两份GB202 ROM。
- id89的名称为`postLtssmDevinitCfgDataTable`；当前ROM实际owner是`BIT.i+6e`，`+72`指向id8a。NVFlash部分旧callback仍用+72，不能照抄旧偏移。
- LTSSM是PCIe链路状态机；这个名字本身不证明它是专门的显存训练程序。
- 新找到的NVFlash v6外层consumer确认`0x50+count*20+word1`长度，并有格式状态分支；**它不是设备执行入口或密度检查器**。
- MODS具名RVDevinit v6 parser实际服务**app1d/target1**，app19在该分派中跳过。不能因看见RVDevinit字样就把它当当前app19。

两ROM四类完整载荷对当前GSP bundle的16次精确范围查找均无命中；这只排除完整逐字节副本，不排除重排、局部、其它版本或编码副本。没有随机反汇编载荷。

详见`firmware_entry/REPORT.zh-CN.md`、`fbfalcon_locator/REPORT.zh-CN.md`。初始PRO loader问题已改用既有`memory_corpus.load`解决，当前两份验证均成功；owner链也已改为从BIT/Falcon表动态交叉验证。

## 4. 真正GB202冷启动训练的职责边界

本地公开610.43.03代码和联网官方GB202源码相互支持：

```text
chip reset → BootFSM启动FSP
  → devinit / FBFalcon training
  → FSP发布安全启动完成
  → host加载GSP-RM主体
```

GB202专用`kfspWaitForSecureBoot_GB202`的注释明确包括`FBFalcon training during devinit`，并为大显存WS SKU使用5秒等待。至少有这个前置训练阶段，不排除后续重训练/换频。**这是架构职责证据，不是已经执行这些设备代码。**

当前610.57.04 GSP明文中看到的明确分支包括：
- `RMFbLinkTraining`覆盖项bit0及memory-type-like默认分支；没有密度/容量输入证据，未绑定GB202 selector。
- FBFLCN/devinit配置状态组合，在特定缺失覆盖项路径下于`0x01a95256`返回`0x40=NV_ERR_INVALID_STATE`。
- 多个devinit mismatch/training completed文本只是错误或状态的打印端，不能当真正判断条件。

上述0x40是**配置状态冲突**，不是“24Gb不支持”或“容量超过32GB”的证据。详见`gsp_init/RESULT.md`。

## 5. 对48/96GB问题的当前判决

- **能看到明确判断分支：是。** 已区分配置索引范围、接口不支持、配置状态冲突、loader格式/启动错误。
- **能确认这些分支在按48/96GB或更高颗粒密度拒绝：不能。** 在已定位的相关代码中，未找到可归属于GB202颗粒初始化的“density>6”或“容量>32GiB”拒绝条件。
- **已测试原BIOS面对48/96GB颗粒能否训练：没有。** 真正设备端参数到geometry/training的consumer仍缺入口和语义。

因此，这轮不把“选择器通过”当“初始化通过”，也不把旧API返回不支持当“硬件扩容不支持”。下一关键目标是GB202实际FSP/devinit/FBFalcon执行体对id89/颗粒信息的消费，而不是继续测试最终容量getter。

## 6. 验证、审查和复现

```sh
P=/home/user/rt_5090_project/vbios_diff/gb202_boot_upstream_20260911/.venv/bin/python
R=/home/user/rt_5090_project/vbios_diff/gb202_init_acceptance_20260911
"$P" "$R/tools/verify_all_offline.py"
```

实际重跑六个离线阶段全部通过，五份核心源文件哈希未变。细节见`reports/offline_verification.json`、`reports/verification/`。计数是**局部代码验证次数，不是显存训练次数**：192个HAL constructor、72个旧writer、780个旧setter、64个Devinit选择器输入及3个控制。

独立审查确认原始指令确实执行、回退及≤13边界正确，并指出owner自动验证与断言覆盖不足；本轮已补齐动态owner/source相等、bound输出、错误分支和原parser实际执行计数断言。family级标题也已收窄。详见`reports/independent_review.md`。

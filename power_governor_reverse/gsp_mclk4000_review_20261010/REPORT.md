# 本地GSP代码核查：MCLK控制、动态范围与PMU提交

## 范围与结论

本轮直接读取GPU内GSP-RM的RV64代码及其原始指令，不只是公开KMD的`kernel_gsp.c`。主要是本地R610.57.04 RX/RW与完整main，辅以R570.144对应实现。只读静态分析：不访问GPU、不运行MODS/固件、不改写寄存器/固件/旧Ghidra数据库。

**当前恢复的GSP控制导入和范围检查没有给出固定“offset>=4000000”或“target>18000000”的拦截代码。** 控制值按32位保存；存在运行态Pstate频率范围检查，来源已经推进到缓存getter/转换回调。`MCLK_MAX_CAPABILITY`名字/描述项确实存在，但尚未绑定其有效值和producer，不能据此宣称上限恰为36Gbps。

这些是GSP对应实现的线索，不是本次MODS实际故障栈：原MODS日志明确`GSP-RM Disabled`，本次停机仍定位在匹配R570.215 PMU的completion wait。GSP和CPU RM有可比较的相似模块，但不同build/入口不能强行等同。

## 1. 本地代码身份已核对

输入：

- `../gsp61057_rx_full.bin`，VA1000000，长E97000，SHA256`50614073f1ca73d4a10e66bdba15e557763b402c75b203a8950161c0afe59085`。
- `../gsp61057_rw_full.bin`，VA4000000，长1D5000，SHA256`e8532f698214230ab3ae57e2017dcbed35a40fddc6e3171372b0e93bcc92dc8d`。
- `../../windows_driver_compare/610.88/inner/linux-610.57.04-gsp-main.elf`，SHA256`ee1475a798c6a8cb8ecac7d58e18e2bbbbfa51569186ce958feaebe976af773a`。

逐字节确认RX切片是完整main的前缀、RW完全匹配相应段；既有RX末尾少16KiB，本轮另生成包含完整RX/RW的离线ELF view用于LLVM。view只添加反汇编所需header/section，不是新固件，没有执行。

Ghidra项目在010f46d8、0111c008、016bcae0三个入口各64bytes与原始RX全部匹配。详见`parent_capability/full_main_provenance.json`、`project_byte_checks.txt`。

## 2. 控制API和32位字段

恢复的API2080d073 handler在`01105f5c`：检查对象/功能状态，解析ClockManager+1170的控制组，再转调组对象+28方法。它本身没有读取18000/4000作数值比较。

已恢复的type7控制导入`0111c008`先调用`01ae404c`。原始指令表明这个继承helper检查的是对象和控制记录的type byte匹配，不是频率上限。

随后：

```text
0111c04a..04e : input +04 的dword -> object +68
0111c052..056 : input +08 的dword -> object +6c
```

指令均为`lw/sw`，没有将这个值转成16bit或在4000000处分叉。给定3999000、4000000及18000000、18001000均能完整装入signed32。**这是字段宽度/导入的结论，不是某一次MCLK请求已获得许可的证明。** 还需结合调用对象类型、外层验证及最终target生成。

详细控制路径/范围语义由`validators/`新增证据补充；不得将programming key的uint16 MHz与控制offset的32bit kHz混同。

## 3. 真正看到的范围检查是动态的

函数`01670320`遍历Perf+308的Pstate group，按clock-domain取得对象，通过该Pstate对象的direct slot+548填充0x3c-byte范围记录。原始比较：

```c
if (requested_khz <= selected_max && selected_min <= requested_khz)
    return NV_OK;
// 不匹配则继续检查下一Pstate；无匹配返回0x5b
```

`16703ce`和`16703d2`是unsigned strict-less的窗外分支，因此范围两端包含。该函数没有在这些指令里把max写成4000000或18000000。

注意它在已恢复的`0111cc80`调用者中接受的是某个programming key的uint16 MHz乘1000；调用者对0x5b有“nothing to do/返回成功”处理。因此不能未经完整target链证明，就说这里直接拒绝了本次18001的物理请求。

### slot548解虚一层

构造器中找到了多条赋值；恢复到的getter包括：

- `01668f40`：复制`pState + domain*54 +61c`处的3c bytes。
- `0168ac3c`：复制`pState + domain*3c +5e0`处的3c bytes。
- `0168b2a8`：复制`pState + domain*40 +5ec`处的3c bytes。
- `01692ea8`：domain映射后复制对应缓存记录。
- `0167be2c`：按domain类型取Perf运行态值，并可能调用`01bcebe4`转换，再构造范围。

这把范围来源推进到**Pstate缓存/Perf运行态表/转换回调**，但尚未确认本机GB202在特定入口选择哪一derived Pstate类，也未追完缓存的writer。没有运行态min/max可代入，因此不能伪造“该max=18000000”。

详见`parent_capability/pstate_range_slot548_recovered.c`与`pstate_range_original_instructions.asm`。167122a的store使用1671202的AUIPC结果，正确target167be2c；不能错用store附近PC算成167be50。

## 4. GSP提交到PMU：跨build有真实变化

R610当前ClockDomains SET_CONTROL：

```text
010f46d8
  -> ClockManager控制组
  -> 010fae18 BoardObj CONTROL apply
  -> Perf+560 callback
```

后一个hook在当前build被安装为`016abaf4`的return-zero stub；不能因旧MODS有相似hook就称它为硬件programmer。也不能据此说整个API完全无作用：前面BoardObj apply及独立事件路径仍存在。

实际恢复的Perf事件提交路径中，`016bcae0`构造214-byte、unit1300/type0c的PMU RPC；成功后按domain mask导入返回字。`016adb28`是54-byte、type0d的后续路径。R570.144的相应协议含triggerC、largeD、finalizeE，消息编号和hook布局与R610不同。

GSP RPC的失败分支可记录fault并ebreak；但这个GSP地址/标记不是本机PMU205d1acc/25728。不能把“都调用PMU”当成同一协议或相同首因。

既有、已地址级恢复的边界详见`../GSP_61057_CLK_CONTROL_COMMIT_20260817.md`和`../GSP_61057_PERF_EVENT_PROTOCOL_20260817.md`；本轮交叉核查见`cross_build/REPORT.md`。

## 5. 能力限值名字与VBIOS列表不能直接当拦截证据

- RX中的`MCLK_MAX_CAPABILITY`在1e8e860，描述项名字指针在1e23b28；相邻记录是描述数据，不是比较指令，尚未闭合producer/activation/有效freq。
- `MCLK_LIMIT`、`RMClkSwitchWithinMargin`、`RmMClkSwitchOnFbflcn`也在代码/名字池中。后两项是换频配置，不能把0x10 mask当4000阈值。
- R610读回支持列表最大名义点15001、ROM最后key14001和OC offset range -1000..5000是不同对象/阶段。**不能把列表的最后一项直接称为最终OC最大频率**，也不能用它反推R570.215的失败边界。
- RW两个未对齐byte序列可拼出18001，但它们跨两项数据，并非频率常量，已排除。

详见`parent_capability/NOTES.md`。静态无literal命中不能证明所有指令/动态表没有相应限值。

## 6. 对本次MODS问题的结论边界

GSP对应路径支持排除一种简单解释：目前没有代码证据显示32位控制offset在+4000被截断、或已恢复的范围比较故意排除相等端点。

更有价值的下一跳是：

1. 正面绑定GB202-selected Pstate/clock-domain类。
2. 追其range缓存/Perf运行态表的writer与MCLK_MAX_CAPABILITY来源。
3. 核对最终absolute target是否受该能力/档位约束，再对应到匹配PMU/设备端消费者。

**本轮还不能据GSP代码定责FSP，也不能证明MODS CPU RM缺少某个18GHz校验。** 本机原始故障仍是PMU发射之后completion deadline耗尽；此处为相关实现的对照，不是GSP实际参与了那次MODS测试。

## 本轮新增证据与安全

- `validators/`：控制导入/API/范围原始指令与字段核验。
- `cross_build/REPORT.md`：570.144/610.57/570.215与VBIOS/PMU的证据边界。
- `parent_capability/`：完整main身份、Ghidra字节交叉验证、slot548 getter恢复、限值名字表与false-positive排除。
- `parent_capability/static_checks.json`：两条dword store与包含端点branch的精确opcode检查、signed32模型；没有硬件运行值。

Ghidra使用-readOnly/-noanalysis；临时创建函数的日志明确Discarding changes。原始ELF/RX/RW、旧报告和旧DB未改。本轮未执行任何GPU实验。

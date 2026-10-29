# MODS/RM x86-64 初始化接受性：本轮结果

## 最重要结论：GB202命名HAL family的已测槽位不绑定前轮CFG0 writer

输入 SHA256 已逐次断言：`c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`。

**找到可复现的 HAL 绑定反证，而没有找到可称为 GB202 boot 的 density/org 接受分支。** 不能把以下旧/共享 RAM timing 修改函数的接受范围套给 GB202，更不能套给 ROM Falcon app19。

1. `0x705b4f0` 的错误路径 `0x705b51a` 引用明确文字 `fuseGetState_GB202`。Fuse HAL constructor `0x6c271f0` 与 FB HAL constructor `0x6bf8780` 都读取第二参数对象 `+0x10/u16` 作为 selector。
2. Fuse constructor 在 `0x6c27934` 检查 `selector>>5 == 2`，`0x6c2794f` 对低5位检查 mask `0xec0`，`0x6c27ff0..0x6c28021` 将 `0x705b4f0` 绑定到 `+0x198`。即 selector **46/47/49/4a/4b** 这组使用 GB202 命名实现。
3. 对两个 constructor **原始指令**仿真 selector 0..95，这五项 FB HAL 都给出：

| 槽位 | 绑定地址 | 实际指令/意义 |
|---|---|---|
| +6f8 | 6c044a0 | 单条 `ret`，不是前轮700f500 writer |
| +738 | 700de00 | FBPA地址解析；广播0x200→0x9a0200 |
| +808 | 6bf8130 | `eax=0x56; ret` |
| +810 | 6bf8140 | `eax=0x56; ret` |
| +818 | 6c040b0 | `eax=0x56; ret` |

前轮 writer `0x700f500` **只在枚举测试中 selector 1e/1f/20/21/22 绑定到+6f8**。三种有字段范围检查的 timing setter 在1d..22绑定，而上述GB202命名family对应槽是固定0x56 stub。证据：`hal_matrix.json`、`fuse_binding.asm`、`fuse_hal.asm`、`hal_writer_bind.asm`、`gb202_writer_stub.asm`。

限制：没有进一步找出实际GB202设备→这五个selector中哪一个的生产路径。因此这里是**GB202命名HAL family级交叉绑定证据**，不是精确PCI device id→selector闭环，也不排除另有非此槽位的初始化消费者。父进程补查本地公开`nvstatuscodes.h:115`：0x56为`NV_ERR_NOT_SUPPORTED`。此状态指调用不支持，不是48/96GB容量拒绝。

## 前轮writer：写地址及调整已仿真，但不绑定上述GB202命名family的已测槽位

`0x700f500..0x700f620` 输入：RSI=FB对象，RCX=工作记录T；T+0的u32是既有CFG0，不是这次证明从ROM id89读取。

| 地址 | 条件与变化 |
|---|---|
| 700f51d/521 | CFG0.bit12 := T+75.bit0 |
| 700f531..539、700f5e0 | FB+4350.bit15 且 FB+434c==3 时，CFG0.bit21 := (T+60/u32 !=0) |
| 700f53f..55b | FB+4350.bit59 时，CFG0.bit24 := T+78.bit24 |
| 700f55e、700f5b8 | FB+434c==0x10：若T+78.bit31=1，清CFG0.bit19并置低2位=3；否则置bit19、低2位=2 |
| 700f563/565 | 调整后与原CFG0相等则跳过写入；不等才写 |
| 700f567..581 | HAL+738参数(mode=0,index=0,offset=200)，再6abc210(writer/context,address,value) |

独立解析器 `0x700de00`：先mask offset为3fff；mode0,index0→`9a0000+offset`（700deb8/700debc），所以目标是 **0x9a0200**。mode1→`((index+240)<<14)+offset`；mode2→`((index+260)<<14)+offset`。mode非法→日志/断言后返回ffffffff；mode0,index非0会走断言后仍生成广播地址，不能说这里严格拒绝。

72个组合采用真实writer+真实resolver指令；**6abc210只捕获写入参数，不运行其指令**；日志函数同样stub。所有结果与独立位运算预测相等，捕获写目标全部9a0200。函数无可靠返回状态语义，不把EAX残值当拒绝码。

## 字段范围：找到了真实分支，但必须标记为旧/共享timing路径

三个setter的共同依赖 `700db80` 通过频率范围选出RAM timing entry首尾；`6811390` 明确日志 `Using VBIOS RAM timing table entry ... maximum ... KHz`，entry stride=e0，基址为FB+4368，索引为`group*16+entry`。因此不是显存容量getter，也**不是已经证明的boot几何初始化**。

| 函数/分支 | 接受范围 | 拒绝/默认源/输出 |
|---|---|---|
| 700e4c0，700e4d0/4d3 | 完整u32的0..63或ffffffff | 其它立即返回1f，不调用selector；ffffffff取entry+d4.bits20:15；写entry+70及+74中的相应移位字段（<<11/<<15） |
| 700e560，700e56f/572 | 低8位0..15或ff | 其它返回1f；ff取entry+d8，写entry+b5 |
| 700e5d0，700e5df/5e2 | 低8位0..15或ff | 其它返回1f；ff取entry+d9，写entry+b6 |

**未给三个字段强加density/org/rowbits名字。** 它们只是有范围的timing字段。第二/三个函数使用8位比较，0x100、0x10f、0x1ff与低8位等价，不能说接受集合只限完整u32的0..15/ffffffff。

780个原始指令测试覆盖0..255和ffffffff/100/10f/1ff；仅把700db80 stub成返回一条合成entry（成功），验证范围码；真实setter负责字段修改。没有运行真实selector依赖。真实700db80下游错误会透传，缺少首/尾entry→40（700dc5e..7b），对象缺失→40（700dc88..92）。这些是依赖失败，不是density拒绝。

## MODS测试前端覆盖分支（非RM boot认定）

- `0x1235a30/32`、`0x1235a3b/3d` 检查 per-FBP row override 是否在动态上下限中；超出则 `1235a58` 将该项置0并继续，日志明确 `Fbp Row bits ... out of range. Not overriding`。上下限由字段查询结果和`10-query`偏移组合，不是本轮已知常量。FBP mask禁用也将项清0。不返回整个初始化失败。未闭环该前端类到GB202。
- `0x1238e07` 的 clamshell override=-1则跳过；`1238e30/32`、`1238e38/3b` 分别接受0/1，其它打印 `invalid fb_clamshell`，随后沿用原读取值调用写helper；这不是确定的整卡拒绝。后面的banks-per-row-bg覆盖仅2/4/8有独立分支。`0x11d84000`等是字段访问token，**不能视作GPU BAR地址**。

## meminit日志路径：纠正前轮线索

- `67070e0`本身只把对象+370..384复制到输出参数；全输出指针为空返回ffff。它不是解包器、更不是density验证。
- 真正`671689a`调用`6e808c0`（count=16，format=91847a2）；`67168a4`检查EAX，非0→`67168aa`的could not unpack日志。
- `6e808c0`是按format解包通用BIOS数据，`6e80983/985/987`比较 **递增后的u32 offset <= BIOS对象+350/u32长度**，合法再调用6705600；解包器非0→`6e80a00`返回ffff。
- 越界并非必然整体失败：`6e80989..9ca`把剩余输出清零，`6e809d1/d4`若已有至少一条成功则继续成功返回0，否则ffff。此处有u32相加，没有在本轮验证整数溢出防护。外层67168d0..dd还可能调用6710720并覆盖状态。
- **此通用解包范围检查不等于显存几何合法性检查**；没有证明读取id89或density code7表示24Gb。

## 尚不能确认

GB202实际boot中density/org/clamshell/rowbits的拒绝集合、自动降级/调整策略、ROM id89字段到CFG0/CFG1的来源链、24Gb枚举与c000单位均未闭环。尤其不能由旧timing setter或MODS CLI覆盖检查推导“GB202 boot接受某个显存组织”。本轮最有力产出是HAL绑定排除和可执行复验的范围/写入条件，而非伪造接受性结论。

## 安全及复现

全部新增文件仅此目录。只读ELF与前轮文本；**未native执行MODS、未打开设备节点、未执行GPU/硬件命令**。Unicorn中代码地址allowlist、拒绝syscall/in/out等指令、未知地址失败；file-backed ELF页面复制到模拟内存，不映射主机硬件。这是MODS/RM x86-64原始指令模拟，**不是ROM app19模拟**。

运行 `bash reproduce.sh`（固定前轮venv Python），`verification.txt`记录96×2个constructor、72个writer、780个setter case成功。`analyze.py asm/ref/strings`供静态复核（实际子命令为`refs`）；反汇编若从截断边界开始可能有伪指令，结论中的完整函数以确认入口及Unicorn验证为准。

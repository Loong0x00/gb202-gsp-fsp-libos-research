# Parent：本地GSP身份、能力限值名字与误命中排除

## 代码身份

实际检查的是GPU内GSP-RM的RV64代码，不是只读公开KMD的`kernel_gsp.c`。

- 既有RX切片：`../../gsp61057_rx_full.bin`，VA1000000，长E97000，SHA256`50614073f1ca73d4a10e66bdba15e557763b402c75b203a8950161c0afe59085`。
- 既有RW切片：`../../gsp61057_rw_full.bin`，VA4000000，长1D5000，SHA256`e8532f698214230ab3ae57e2017dcbed35a40fddc6e3171372b0e93bcc92dc8d`。
- 完整main原件：`../../../windows_driver_compare/610.88/inner/linux-610.57.04-gsp-main.elf`，SHA256`ee1475a798c6a8cb8ecac7d58e18e2bbbbfa51569186ce958feaebe976af773a`。
- 逐字节确认：RX切片与完整main的前E97000完全相同；RW与main[E9B000:1070000]完全相同。完整RX应为E9B000，既有RX切片末尾少16KiB。
- `project_byte_checks.txt`：Ghidra只读读取010f46d8、0111c008、016bcae0三个入口各64bytes，12行全部与原始RX切片一致。

为LLVM反汇编生成了两个仅离线使用的ELF view。`gsp61057_static_view.elf`及`gsp61057_full.asm`来自既有切片（RX尾部缺16KiB）；`gsp61057_full_main_view.elf`含完整RX/RW。其ELF section/header是离线新增的工具封装，不是新的可加载/已签名固件；未运行它们。provenance JSON记录对应源与范围。

## MCLK_MAX_CAPABILITY不是已找到的18000比较

RX中可见字符串：

- `1e8d030`：MCLK_LIMIT。
- `1e8e860`：MCLK_MAX_CAPABILITY。
- `1e8bc00`：RmMClkSwitchOnFbflcn。
- `1e29e28`：RMClkSwitchWithinMargin。

MCLK_MAX_CAPABILITY的静态名字指针在`1e23b28`。其附近是描述表，原始qword：

```text
1e23b18 = 00000122000000ff
1e23b20 = 000000000000011e
1e23b28 = 0000000001e8e860 (name pointer)
1e23b30 = 000000000000ff02
```

已知MCLK_LIMIT名字在另一类同形描述表中，其中`1e22e78=000000fb00000091`。旧记录已将MCLK_LIMIT与limit IDfb联系；对新增MCLK_MAX_CAPABILITY，**此处只有名字/描述字段，不宣称已闭合其产生函数、activation或具体频率值**。表本身没有18000/18001限值。

筛查code中的fb/122立即数遇到多个误命中：01183ddc的fb是一个bindata/group描述列表项；013583d0的122是和LUI240组合的寄存器地址部分；013002c4/0304中122是索引偏移。它们不能只因数值相同被命名为MCLK能力限值代码。保存的`limit_id_candidate_functions.c`是候选检查输出，不是确认的限值producer。

## 真实读取到的MCLK初始化配置函数

GSP `010d8658`（原始对应函数已只读反编译）读取：

- SlideMCLK：写ClockManager+f8c，非零时置Perf的两个配置byte（+2b8/+2ba）。
- RMMaxMclkFbstopTime：写ClockManager+11b4。
- RMReportMclkSwitchFbStopTime：设置报告开关。
- RMClkSwitchWithinMargin：检查配置mask10，进入日志路径；不能把mask10说成offset4000。
- RmMClkP5LinkTrainingWckStopClks：设置配置byte+483。

它还写默认500000到ClockManager+11c0；**未经consumer/单位绑定，不把这个字段说成MCLK最大频率或替代PMU的1900-tick budget**。这些配置证明显存换频路径有独立的PLL/FB-stop/训练参数，但没有从此函数找到18GHz或+4000判断。

## Raw字节搜索的假阳性

RW的未对齐位置413df3f、4142edf都能拼出18001的little-endian字节，但它们各跨过两项：前一aligned qword为518de87a00000048，下一项为46。不能把跨项byte序列称为频率常量或边界判断。

同理，“整个RX原始字节没找到4000000/18000000”不能证明指令/动态表绝无该阈值。最终结论必须以恢复的代码比较、字段来源与本次运行现场为准。

## 安全

所有Ghidra操作带-readOnly/-noanalysis，日志包含Discarding changes；无GPU/MODS运行、无MMIO/固件改写、无旧DB保存。

## 新推进：动态range的slot548解虚一层

`01670320`从Pstate对象的slot+548填充0x3c-byte范围记录，再以两个uint32范围端点比较绝对频率（包含端点）。本轮通过原始AUIPC/addi/store恢复多个构造器赋值，见`pstate_range_original_instructions.asm`：

- base target01664728；另一路覆盖为01668f40。
- 1670fa0的赋值生成0168ac3c。
- 1671360的赋值生成0168b2a8。
- 1671550的赋值生成01692ea8。
- 167122a的store使用**1671202**的AUIPC结果，正确target是0167be2c；不能错误地以store附近PC1671226计算成0167be50（后者在函数中部）。

解虚后部分getter只是复制缓存范围：0168ac3c来自`pState + domain*0x3c + 0x5e0`，0168b2a8来自`pState + domain*0x40 + 0x5ec`，01668f40来自`pState + domain*0x54 + 0x61c`，均复制0x3c bytes。0167be2c还根据domain类型读取Perf中的运行态字段，并可能调用频率转换helper01bcebe4。

这把“动态min/max从哪里来”的边界推进到Pstate缓存/Perf运行态表或转换回调，但尚未确认本机GB202在某次调用选中了哪一derived Pstate类，也未追完这些cache的producer。不能凭slot同名认定全是当前MCLK的有效上限。未从这些getter恢复固定18000或offset4000比较。

`pstate_range_slot548_recovered.c`来自-readOnly临时创建三个缺失函数后反编译，日志确认Discarding changes。`pstate_range_slot548_targets.c`是最初候选检查；其中167be50错误候选不能引用为函数入口，以上修正为准。

# 独立审查与整改

独立worker只读审查，不执行C程序、不访问硬件、不写审查目标。审查结果来自本次会话返回；以下不把未持久化的审查试验计入正式回归数量。

## 原始发现

1. 中：C工具仅确认指定sysfs BDF存在，却另行选择`/dev/nvidia0`和RM deviceId=0；多卡枚举变化可能错标目标。校准脚本也直接取CSV首行。
2. 低：EFI runner原先接受任意写地址，且仅以到达sentinel判定返回。内存内变异可以把写地址换为deadbeef，或直接跳sentinel。原有外层结果断言会捕获这些变化，不推翻原始容量计算，但文档的fail-closed表述过强。

审查未发现高严重性问题；报告原306例、额外228个consumer边界案例及6个ABI压力案例通过。geometry/payload报告未将owner误当writer或将候选schema冒充已知。

## 已落实修正

### 目标身份

- 两个C工具都核查目标BDF对应的proc Device Minor=0。
- 在实际分配的RM subdevice对象上查询BUS_GET_INFO，只取domain/bus/device三个身份项（不查询clear-on-read错误计数器）。
- 同一RM对象另查询BUS_GET_PCI_INFO，要求PCI vendor/device=`2b8510de`。
- 任一查询失败或不匹配，在目标寄存器读取/FB查询前退出。
- 校准脚本按BDF唯一选择CSV记录，并核对PCI ID，不再使用首行。

实际执行过身份查询only构建；随后新工具重新读取固定4地址及6个FB字段，与首次一致。新证据为`live_readonly/*_verified.txt`，包括实际RM身份输出。没有测试所有多卡/热拔插场景，不声称泛化覆盖。

### EFI边界

- 写callback仅允许consumer的`10fd40/830000/830004`。
- 顶层退出同时要求经过该函数末RET以及RSP平衡。
- 补入每镜像3个负控：缺失读响应、guest内未知写地址、guest内跳sentinel不RET。全部拒绝。
- 文档缩小控制流声明：只限提取片段边界，不冒充完整GOP控制流模型或逐字节未知内存模型。
- 额外加入48GiB消费者案例，正式正常测试变为312项，另6项负控。

## 正式验证证据

`offline_verification.json`记录14个离线阶段均通过及C的`-Werror -fsyntax-only`检查。`verification/efi_research_emulate.py.log`与`../efi_research/negative_controls.json`保存更新后的实际结果。所有原ROM/MODS/GSP文件保持原哈希。

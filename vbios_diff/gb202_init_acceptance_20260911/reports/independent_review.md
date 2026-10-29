# 独立审查及落实情况

审查worker仅只读操作，拦截报告写入后重放CPU Devinit helper与192个HAL constructor，并复核两份owner/应用定位脚本；没有硬件访问或目标原生执行。以下是会话审查返回的摘要。

## 已确认

- helper `6712970..6712a4d`真实调用原MEMINFO parser `672c9e0..672d36b`；解析器结果不是stub。
- parser失败回退、候选值≤13、反事实13成功/14返回ffff等结果正确。
- 缺失strap响应是harness拒绝未知依赖，不是设备拒绝。
- 当前M v2/length41的格式为`1b2w2d1w`，M+0及M+1/u16复制到VB+42c/+430有原代码依据；harness仍是人工建立这些对象字段，没有执行完整BIT初始化。
- HAL结果只能作GB202命名family/已测槽位级解释。
- app名称与selector比较成立，但不能把DevInitFMC直接等同唯一FBFalcon训练程序。
- 当前ROM i+6e→89、i+72→8a；NVFlash旧callback偏移不可照搬。

## 指出并修正

1. 中：`firmware_entry/verify.py`原先只核硬编码descriptor与SRC，缺少动态owner来源相等断言。现已改用正确loader，从Falcon app19/target1和BIT.i动态定位；断言source逻辑指针、绝对地址、size/alloc相等，并检查+72为id8a。独立审查补验原数据本来正确；此为覆盖补强。
2. 低：`mods_init/REPORT.zh-CN.md`标题“排除了/非GB202绑定”可能脱离正文被过度引用。现改为“GB202命名family的已测槽位不绑定”，保留其它路径未知。
3. 低：Devinit harness未断言已记录的bound输出、错误分支、parser实际执行计数。现已增加这些断言；零translation pointer分支未单独测试，报告不称全边界覆盖。

## 最终验证

六阶段离线回归全部通过，五份核心源文件哈希不变，见`offline_verification.json`。本次修正没有增加GPU操作，也没有产生修改版ROM。

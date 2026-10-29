# GSP 610.57.04：init/training 分支与 GB202 职责分界

## 结论

**找到明文 FB training 配置分支和 FBFLCN/devinit 状态拒绝分支，但没有证明任何一个是 GB202 的颗粒 density / organization / clamshell 接受判定。** 本轮没有仿真容量 getter、没有执行目标、没有硬件访问。

比“未发现 init”更强的正面证据是：本地公开 KMD 的 **GB202 专用 HAL** 在 GSP-RM 加载前等待由 chip-reset BootFSM 启动的 FSP 完成安全启动；该等待明确包括 devinit 的 FBFalcon training。故 GB202 冷启动颗粒训练至少有一个 **GSP-RM 主体运行前的 GFW/FSP/FBFalcon 阶段**。这不排除 GSP 后续 re-training / mclk switching，也不证明整个 bundle 不含其他初始化 payload。

## 1. 当前二进制可复核的条件分支

### A. `RMFbLinkTraining`：函数入口 `0x01318988`

- 字符串 wrapper `0xfd3928` → RX VA `0x01e348e8`。
- `0x01318ac2` 构造字符串，`0x01318aca..ace` 调用 `0x0103c054`，输出指针为栈上 u32。这一调用点及多组 `Rm...` 键共同支持 registry DWORD reader 解释，**不是 RAM 容量 getter**。
- `0x01318ad4 beqz a0` → `0x01319070`：配置读取成功后测试值 bit0；`0x01319078` bit0 为零 → `0x0131977a`，否则处理对象 `+0x84b8/+0x84c0` 的 training 配置。
- 未读取到覆盖项的默认路径：`0x01318adc lw a5,0x3d8c(object)`；比较 `0xc`、`0x10`、`8`。`0xc` → `0x0131916c`，设置 `object+0x84b0=3`；8/0x10 → `0x013197a0`。此处是 memory-type-like 配置选择，**没有 density 或容量输入证据**。
- 公开 RM ABI `ctrl2080fb.h:399–424` 中 8/0x10 分别是 GDDR5/GDDR5X，GDDR7 为 `0x15`。内部 `+0x3d8c` 是否直接采用同一 enum 尚未闭合，不用这个数值相似性把分支命名为 GB202。
- 函数地址 materializer：`0x01b03526`、`0x01b043ca`、`0x01b0537e`、`0x01b0592c`。第一/第三处明确安装到基寄存器 `-0x3e8` 槽；其 chip-HAL selector 未闭合到 GB202。

另 `RMFBTrainingCMOS/CML` xref `0x0112db1a/0x0112db34` 也调用同一 reader，按读取状态分支；不代表训练结果成功/失败，更不是 CMOS/CML 颗粒几何验证。

### B. FBFLCN/devinit 配置及实际拒绝出口

同一明文大函数内：

```c
// 根据字符串键与字段存取恢复；obj = s3
if (read_key("RmEnableFbflcn", &v) == 0) {
    if (v == 1) obj->byte_1b0 = 1;   // 0x01a94c5c
    else if (v == 0) obj->byte_1b0 = 0; // 0x01a93e82
}
if (read_key("RmDisableFbflcnDevinitBoot", &v) == 0) {
    if (v == 1) obj->byte_1b9 = 0;   // 0x01a94c54
    else if (v == 0) obj->byte_1b9 = 1; // 0x01a93eae
}
```

- 字符串 xref `0x01a93e56/0x01a93e8a`；值比较分支 `0x01a93e7c/0x01a93ea8`。
- `byte_1b0!=0` 经 `0x01a93eb8` 跳 `0x01a9520e`，读取 `RmMClkSwitchOnFbflcn`。
- 在该键读取失败/未提供的 fall-through 路径，`0x01a95230..0x01a95240` 再检查 `byte_1b0` 和 `byte_1b9`；**两者非零则进入错误日志，`0x01a95256` 将返回状态设为 `0x40`**，跳 `0x01a938de`，最终 `0x01a93924` 返回 s3。公开 `nvstatuscodes.h:93` 将 0x40 定义为 `NV_ERR_INVALID_STATE`。
- 这是真实的 **FBFLCN/devinit 配置状态拒绝**，不是内存颗粒不支持、不是几何超限。未证明 GB202 默认会走到它，也未枚举 registry override 成功路径的全部条件。

### C. 容易误读的 “DEVINIT mismatch / training completed” 字符串

- `NV_UDE_ERR_DEVICE_ID_WITH_DEVINIT_TABLES_MISMATCH` xref `0x011bf626`；scripts 对应 `0x011bf648`。
- 相邻块加载错误号 `0x42c/0x42b`，把字符串交给同一日志函数后 tail-call。**这是错误解释/输出端，不是此处在比较 VBIOS device ID**。
- `...FBFALCON_BOOT_TRAINING_COMPLETED` xref `0x011cf994`：相邻块只把枚举值 3 和字符串交给日志函数，不是训练完成 writer。
- 大批 DEVINIT authenticate/signature/HS-mode 字符串同属这类错误名字。**AES/signature 名字只能证明认证错误词汇存在，不能证明这些 app payload 已加密。**

## 2. GB202 的可核查职责分界（公开源，版本差异明确）

源根 `/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules`，version.mk **610.43.03**（非当前固件 610.57.04）。带行号和各文件 SHA256 的摘录见 `kmd_boundary_evidence.txt`。

链条：

1. `kernel_gsp.c:5032` 调 `kgspWaitForGfwBootOk_HAL`；5035–5038 注释明确 **GFW boot complete 后、加载 GSP-RM ucode 前**。
2. `g_kernel_gsp_nvoc.c:1601–1626` 的非 VF 分支，GB202 不在 TU102..AD107 特例中，走 `kgspWaitForGfwBootOk_GH100`。函数名 GH100 不等于只适用 GH100。
3. `kernel_gsp_gh100.c:249–263` 调 `kfspWaitForSecureBoot_HAL`。
4. `g_kern_fsp_nvoc.c:494–497` **明确列 GB202/GB203/GB205/GB206/GB207**，分配 `kfspWaitForSecureBoot_GB202`，而非 GB100 HAL。
5. `kern_fsp_gb202.c:58–61`：GB202 的 BootFSM 在 chip reset 后启动 FSP；FSP 完成 boot 写 scratch=0xff。
6. 同文件 75–85：等待包括 devinit 中的 FBFalcon training，考虑大 VRAM workstation SKU 设置 5s timeout。注释里的 HBM3 是通用历史措辞，不用它给 GB202 归类 HBM。
7. GB202 `dev_therm_addendum.h:27–30` 明确 SUCCESS=0xff、FAILED=0；超时路径 `kern_fsp_gb202.c:89–107` 请求 reset、报告错误并 dump FSP 状态。

这形成可检验的前置依赖，而不是把最终容量报告或 GB100 HDM 裁切误称颗粒初始化。

### 关于加密 app

`kernel_gsp_fwsec.c:114–141` 公开 Falcon ucode table ABI：ApplicationID、TargetID、DescPtr，以及 vDesc 的 ENCRYPTED bit2；本文件列出的 APPID 是 FWSEC 0x05/0x45/0x85。**本轮没有从 GB202 ROM 解出具体 devinit/FBFalcon app descriptor，因此不声称它们的 encrypted bit 已验证，也不把 FWSEC APPID 当 RVDevinit APPID。** 下一步应由 ROM 的 app 表/descriptor 定位实际代码及加密标记，再找几何字段消费者；仅追主 GSP RX 中日志名字不够。

## 3. 搜索/验证覆盖与产物

- 输入 wrapper SHA256 `c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999`，两个脚本每次均断言验证。
- 采用已知 inner wrapper offset `0x19f040`，**扫描完整 RX 0xe9b000**，而不是旧提取物少尾部 0x4000 的 RX；RW 为 inner `[0xe9b000:0x1070000]`。
- 全 wrapper ASCII 长度≥4 的语义字符串扫描，共 62 条；density / organization / clamshell / meminit 无命中。搜索模式含 training、devinit、fbflcn、fbfalcon、gddr 和 fb.?init。
- RX 每半字扫描相邻 AUIPC+ADDI/load 引用，RX/RW 查 64-bit 绝对字符串指针；不是完整数据流，也不覆盖所有压缩指令组合、远距离常量传播、非 ASCII、其他嵌入执行体。
- `verified_ranges.asm`：直接从 hash 验证后的原 wrapper 反汇编；选段无 `<undecoded>`。函数内部选段不能冒充完整 CFG。
- `semantic_branch_candidates.asm` / `branch_targets.asm` 是初始探索上下文，个别首地址落指令中间；结论以 `verified_ranges.asm` 为准。

重现：

```sh
D=/home/user/rt_5090_project/vbios_diff/gb202_init_acceptance_20260911/gsp_init
python "$D/semantic_scan.py" > "$D/semantic_scan.txt"
python "$D/collect_evidence.py"
```

所有新增仅在本目录。未下载或原生执行任何目标程序；未使用 Unicorn，因为已确认的这些片段是配置/日志/调度边界，微仿真不能补上 GB202 颗粒几何语义。

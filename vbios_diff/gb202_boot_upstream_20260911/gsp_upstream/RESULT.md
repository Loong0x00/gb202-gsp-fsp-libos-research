# R610.57.04 GSP 容量 / geometry 上游：限时只读静态研究

## 结论

**找到可精确提取的 usable-size reader 及其函数指针安装点；未找到四个目标寄存器的 writer，未闭合 GB202 的容量/geometry 初始化链。不能把未找到解释成整个 firmware bundle 不含初始化。**

本轮没有硬件访问，没有执行/仿真目标固件；只处理本地文件。用户给的寄存器/NVML值仅作为文本输入。

### 1. 已验证当前固件和提取物一致

- wrapper `/usr/lib/firmware/nvidia/610.57.04/gsp_ga10x.bin`
  SHA256 `c0156954f3e048d56011524e0c2ae2881bb6db8173b53f9b2f4eb94197f02999`
- inner 起点 wrapper `0x19f040`，长度 `82558976`，SHA256
  `88cb25e9940d9b242a8dc518291d028519b1f7b734954c6d358112b4af0a690e`。
  **不能直接 hash wrapper[0x19f040:]，末尾还包含外层元数据。**
- 现成 RX `gsp61057_rx_full.bin` 长 `0xe97000`，逐字节等于 inner `[0:0xe97000]`；VA `0x01000000`。
  SHA256 `50614073f1ca73d4a10e66bdba15e557763b402c75b203a8950161c0afe59085`。
- RW 长 `0x1d5000`，逐字节等于 inner `[0xe9b000:0x1070000]`；VA `0x04000000`。
  SHA256 `e8532f698214230ab3ae57e2017dcbed35a40fddc6e3171372b0e93bcc92dc8d`。
- **RX 提取名中的 full 不等于整个 PT_LOAD**：ELF RX segment 实际长 `0xe9b000`，尾部缺 `0x4000`。
  另直接检查该尾部：4857 个非零字节，前缀看起来是数据表；对相同三种 LUI page 的额外扫描零命中。未宣称尾部全为数据。
- 外层 ELF 的 `not stripped` 不能理解成 RM 函数符号可用：`readelf -s` 只有 null 和三个 binary blob 边界符号；inner section headers 为 8 个空头。

### 2. 确定 reader：0x01358484，范围 [0x01358484, 0x013584ae)

精确数据流：

```c
// a0 = GPU-like object, a2 = output pointer; a1 unused
mmioBase = *(uint64_t *)(a0 + 0xb98);
uint32_t mb = *(volatile uint32_t *)(mmioBase + 0x1183a4); // PC 0x0135849a
*(uint64_t *)a2 = (uint64_t)mb << 20;
return 0;
```

`lw` 之后 `slli 32; srli 12` 正是 u32 零扩展后左移 20，不是探测颗粒。

安装链（均在当前 GSP 字节里核实）：

- `0x0199e632: auipc a5,...; 0x0199e636: addi ...` 构造 `0x01358484`；
  `0x0199e63a: sd a5,0x108(s1)`。
- 另一 HAL 分支 `0x0199ecac..0x0199ecb4` 同样把该地址安装到对象 `+0x108`。
- 另一个地址 materializer：`0x0199ebdc` 构造该 reader 到 `t2`；此处未进一步跟踪最终存槽。
- 上游 selector：`0x0199e612 lhu a4,0x10(s2)`，随后 `a4 >> 5` 分组；尚未把此对象中的 HAL index 数值绑定当前 GB202，**不将该二进制安装分支擅自命名为 GB202**。

可用于软件离线微片段验证：从现成 RX `[0x358484:0x3584ae]` 取 42 字节；输入只需上述对象/寄存器映射与输出指针。此轮未执行它。
用户快照 `0x1183a4=0x7f5f` => `32607 MiB`，与文本 NVML 一致。这个一致只说明读取端语义，不说明谁初始化。

### 3. 另一个确定 reader：0x01358658，不要误绑定 GB202

完整函数 `[0x01358658,0x013586b4)`：

```c
r = read32(mmioBase + 0x1fa3e0); // PC 0x01358672
s = read32(mmioBase + 0x1180f0); // PC 0x01358676, 注意不是 1183a4
expand(v) = ((uint64_t)((v >> 4) & 0xffffff)) << ((v & 15) + 20);
*out = expand(s) != expand(r) ? expand(s) : 0;
return 0;
```

地址 materializers 为 `0x0199e982`、`0x0199f08a`。它是比较 LOCAL_MEMORY_RANGE 和另一 scratch 的读取逻辑，不是 writer。

本地 open 源 `kmemsysReadHdmTopFromVbios_GB100` 与其语义完全对应。更重要的是，本地 generated HAL 对该 GB100 函数列举 **GB100/GB102/GB110/GB112/GR100/GR102，不包括 GB202**。因此它不能当作 GB202 上游容量探测证据。

用户 `0x1fa3e0=0x7f5f0` 按此 magnitude/scale 格式也得到 32607 MiB。仍不能区分 VBIOS 发布、驱动 carveout 或其他阶段裁切。

### 4. 本地 open 源辅助证据（与目标不同小版本，明确区分）

源码根：`/home/user/nvidia-live-recovery-lab/greenfield/open-gpu-kernel-modules`
commit `d7b969d1210f6c655c16b7837ef1f559ee6e72d4`，`version.mk` 为 **610.43.03**，不是目标 610.57.04。

- `src/nvidia/src/kernel/gpu/mem_sys/arch/ampere/kern_mem_sys_ga102.c:37`
  `kmemsysReadUsableFbSize_GA102`：读 `NV_USABLE_FB_SIZE_IN_MB`，输出 u64 <<20；注释说明 VBIOS Devinit 计算并发布 usable FB size。
- `src/common/inc/swref/published/ampere/ga102/dev_gc6_island_addendum.h:33`
  `NV_USABLE_FB_SIZE_IN_MB = NV_PGC6_AON_SECURE_SCRATCH_GROUP_42`，值位域 31:0。
- `src/common/inc/swref/published/ampere/ga102/dev_gc6_island.h:34` 对应 `0x1183a4`。
- `src/nvidia/generated/g_kern_mem_sys_nvoc.c:362-375`
  usable-size HAL 列表明确把 **GB202** 分配给 `kmemsysReadUsableFbSize_GA102`。
  这是本地 open 源的 GB202 绑定证据，不冒充当前 GSP 二进制 selector 已闭合。
- `src/nvidia/src/kernel/gpu/mem_sys/kern_mem_sys.c:1176` generic get 路径返回 `kmemsysReadUsableFbSize_HAL(...)`。
- `src/nvidia/src/kernel/gpu/mem_sys/arch/blackwell/kern_mem_sys_gb100.c:240-285`
  上述 HDM comparison；注释指出部分 **GB100** VBIOS 在 FSP boot 前后改 LOCAL_MEMORY_RANGE。
  仅是 GB100 边界提示，不移植为 GB202 结论。

### 5. geometry / writers 的阴性证据范围

- 对现成 RX 每个半字检查 RISC-V `LUI` 三个 page `0x1fa000/0x118000/0x9a0000`，导出前16/后100字节上下文。
- 这批上下文里确认了上述两个目标读取，**未识别出 1fa3e0、1183a4 写入或 9a0200/204 读写**。
- 确实有其他 `0x9a0xxx` 寄存器访问，如 `0x013143a6` 读 `9a0170`，`0x01342136` 读 `9a0144`，`0x01347e0e` 读 `9a038c`。不能把这些叫 geometry CFG0/CFG1。
- 全 84MB wrapper 四个完整 little-endian u32 地址字面值均零命中；这不是 RISC-V 指令中不存在引用的证明。
- 扫描不覆盖任意远距常量传播、跨块/表驱动地址计算、不同 MMIO alias、间接调用后的运行时状态、嵌套固件中的拆分指令构造、opaque payload。近邻扫描也不是完整 CFG。
- 因此本轮能交付的是 reader/installer 与明确未知边界，**不能宣称找到颗粒容量探测，更不能把其他 HAL 或 LOCAL_MEMORY_RANGE 裁切当作 GB202 geometry 初始化**。

## 可复核产物

- `verification.json` / `verify_extracts.py`：固件/提取物一致性。
- `confirmed_readers_and_installers.asm`：精确函数边界及槽安装字节反汇编。
- `scan_registers.py` / `register_candidates.asm`：可重跑近邻候选扫描；候选上下文起点有可能处于指令中间，不能拿任意首条反汇编作函数边界。

精确重现命令：

```sh
python /home/user/rt_5090_project/vbios_diff/gb202_boot_upstream_20260911/gsp_upstream/verify_extracts.py
python /home/user/rt_5090_project/power_governor_reverse/tools/riscv_range_disasm.py \
 /home/user/rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin 0x1358484 0x13584ae
python /home/user/rt_5090_project/power_governor_reverse/tools/riscv_range_disasm.py \
 /home/user/rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin 0x1358658 0x13586b4
```

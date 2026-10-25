# 进度记录

## 2026-10-19（下午）— trap/syscall 分发静态战役 + 真机 t0=4 探针开跑

- **OBJ-10…OBJ-14（见 FINDINGS A2 区）**：
  - 0x930042f8 fast 契约完整破解（stval==0/c.unimp、t0∈{4,5}、[global+0x450] 表、
    meta bit63+meta&0xC==0xC、type10、try-lock/unlock、sepc+=2）。
  - syscall 分发器精确链 0x930043ea→f6→400→40a；t0=17 在内核表中有 handler
    （修正 OBJ-08 表述）；t0=16/29 空。
  - RM stub 形态实测：`li t0,4; li a1,-1; unimp` ×109 → t0=4 真机 U-mode 自然可达（静态确证）。
  - 慢 handler meta/type 双门控表：净 -1 destroy 只发生在 meta&3==3 / meta&0xC==0xC
    等特殊状态对象；lab boot 期对象地图（17 项）证明这些状态不存在 →
    **“清零 ref + 自然 t0=4/18 → dtor”被门控封死**（重要负结果，纠正 GLM 计划的前提）。
- 新脚本 `make test-lab-t18-refzero`（含 walk 表对象地图 dump，后续复用）。
- **真机侧**：k61_t4probe.sh（B8→RM t0=4 stub 0x100fd7a→unimp，探测真机 fast/slow
  分发是否存活）在 GPU 直通 VM 开跑。VM 基础设施修复：
  - /tmp/start_vm_fresh.sh 丢失 → 重建（systemd-run --slice=gpuallowlist.slice 包裹，
    BPF 设备守护下 root 直跑 /dev/vfio 也 EPERM）；
  - k61_start.sh 的 qemu socket 语法 `server,nowait` → `server=on,wait=off`
    （QEMU 版本更新后旧语法 parse error，VM 起不来元的元凶）。
- 下一步：t4probe 判读 → 读原语探 [0xa3008010]/walk 表 → meta 位写入者定位
  （谁置 meta&3==3 / &0xC==0xC —— U-mode destroy 的真正钥匙）。

# 进度记录

## 2026-10-19（真机轮）— t0=4 分发存活确证 + B8 MPU 边界实测（E1，FINDINGS GSP-14..16）

- **GSP-14**：B8→RM t0=4 stub（0x100fd7a）→ unimp trap 被内核正常 dispatch + sret 返回
  （sepc=0x101002c = unimp 后 0x2b2，死于脏寄存器对齐错）→ **真机 syscall 分发链存活**（OQ-01 真机侧核心问题关闭）。
- **GSP-15**：读 gadget 目标=内核数据段 0xffffffffa3008010 → **load page fault（cause 0xd）**。
  B8 回调上下文 MPU 不含内核数据/代码段；GSP-READ 的能力范围修正为"回调上下文可见区域"。
  内核侧信息需走 syscall（内核上下文）或 window0 别名（待测）。
- **GSP-16**：a0 由 metadata+0x10030 槽提供、全可控（旧 loadgadget sepc=0x2 已证）；
  连同 a1 → stub 注入两参数全可控。
- 真机基础设施：`k61_vm_fg.sh`（前台 VM，systemd-run --slice=gpuallowlist.slice 包裹——
  BPF 设备守护下 root 直跑 /dev/vfio 也 EPERM）；k61_start.sh qemu socket 语法修复
  （`server,nowait`→`server=on,wait=off`，QEMU 升级后 parse error 是 VM 起不来的元凶）。
  新探针脚本：`k61_t4probe.sh`、`k61_readprobe.sh`（宿主侧 rt_5090_project）。
- 待办（下一轮）：① window0 VA（0x8000…）可达性探针 → walk 表读取通道；
  ② t0=18（a0=0）注入观察 rv（meta/type 门控行为）；③ meta 低 4 位写入者；
  ④ a0/a1 双控 t0=4/t0=18 对特定 handle 的 destroy 实验（需 ①③ 的地图）。

### 2026-10-19 深夜补充 — 多射器（multishot）调通：fire 确认

- **k61_multishot.sh**（宿主侧 rt_5090_project）：一次 VM boot 串多发（v21 module_param 版，
  ~2 分钟/发 + Xid 后自动 VM 复位）。计划文件驱动（名字+xdig_map 行）。
- **调试坑记录（重要，防重蹈）**：
  1. VM 内 /usr/src 的 message_queue_cpu.c 是**历史 XDIG 残留版**（v21 因"残留标记"静默
     拒绝植入 → ko 是老版：有 META DUMP 无 OVERRIDE → 参数全无效、永不 fire、无打印）。
     必须先 unpatch_xdig.py 清干净再植 v21（mq.c + kernel-open/nvidia/nv.c 双文件，nv.c 路径
     不是 src/nvidia/nv.c！）。
  2. module_param perm=0 → /sys 不可读，参数生效与否不能从 sysfs 判断。
  3. NV_PRINTF 无限流问题；判读必须用 journal（VM 已启用 persistent journal）。
  4. pkill -f qemu 会匹配外层 bash 自身命令行（自杀）；用 pkill -f "mods-dirty-try"。
- **FIRE 已确认**：mcal3 标定发（K=33, FN=73, B8=0x100fd7a）在 GspMsgQueueSendCommand+0x99
  触发 **host 内核 oops**（journal 06:09:40）而非 v17 式 GSP Xid120——v21 的 fill/cksum
  行为与 v17 有差异待调（下一轮第一小任务：xdig_ck=1 对比、或逐项对齐 v17 参数语义）。
- 下一轮队列：① fire 参数对齐（复现 Xid120 语义）→ ② session/walk 相关 RM 内存多点扫描
  （计划文件已就绪 /tmp/plan_sess1.txt 模式）→ ③ t0=22/t0=18 注入（a0/a1 双控）。

### 2026-10-19 傍晚收工 — v17 循环射击器稳定运转；单发扫描数据（E1）

- **k61_v17shot.sh**：v17 编译期 MAP 循环射击器（植入→DKMS→fire→判读→自动 VM 复位，
  ~11 分钟/发，判读 100% 稳定）。标定发完美复现 t4probe（Xid120 sepc=0x101002c）。
- **v21 放弃原因记录**：module_param 版 fire 后宿主死锁（GspMsgQueueSendCommand+0x9b
  oops / smi 卡死拖垮 VM），与 v17 的干净 Xid 行为不同；ParseParams-once 修复无效。
  v21 源码树残留状态复杂（历史 XDIG 残留、_xdigPostInit=1 boot 期开火），不再深挖，
  全部射击走 v17 编译期。
- **单发扫描战役（10 发）**：
  - metadata 区 [s1+0x00..0xE0]（每 0x20）在 fire 时刻**全 0**（8 发）；
  - hubclient 槽 [0x0C200EB8] 在 fire 时刻 = **0**（1 发，可读但空）——
    **E1 已知值 0xFFFFFFFF930019B8 的填充时机晚于 smi 期**，需要 RM 活跃期
    （mods 全程/更多 RPC 流量后）再 fire 才能读到。
- **追加（18:14-18:35）**：hubclient 槽在 firen=3 + 8×smi 流量下仍 = 0 —— smi 级流量
  不足以触发该槽填充；需要 CUDA 级重量级 RPC。t0=4 stub（109 处）unimp 后继指令统计：
  无一处紧跟 store-a0（rv 泄漏 gadget 直接形态不存在；首选后继是 ld/lw a5 型，占 27+）。
- **下一轮优先级（修订）**：
  0. fire 落入 CUDA 级流量：fire.sh 里 nvidia 装载后跑 CUDA 程序（VM 内查 deviceQuery
     或用 n610 库编最小 init），firen 取大（20+）——hubclient/handle 才会填充。
  1. K3-1 泄漏通道复用（不依赖 B8，历史已证 0x0FE4790E10 可读）——扫 RM 堆对象区
     （staging 0x0FE478xxxx 系）而非 metadata。
  2. rv 泄漏 gadget：扩展到全部 300 处 li t0,4 的后继窗口（±16B）找 a0 存储；或
     逆向 stub 所在函数的返回路径（a0 最终流向）。
  3. t0=7/22 注入（a0/a1 双控）。
- **下一轮优先级（旧）**：
  1. fire 延迟到 RM 活跃期：v17 的 firen 参数（第 N 个匹配报文）调大
     （如 firen=40/80，跳过 boot+smi 早期），让 fire 落在 mods 流量中期 →
     hubclient/handle/对象指针已填充 → 读原语有内容。
  2. 读 [0x0C200EB8] 重试（预期 0x930019b8）→ 从 hubclient 结构顺藤摸瓜找 RM 对象。
  3. t0=7/22 注入（a0/a1 双控已确认，GSP-16）。

### 2026-10-19 收工补记 — fire 复现为 host-oops 变体（+0x9b），v17/v21 差异待解

- mq.c 清理重植 v21（mq+nv.c 双文件）+ DKMS 重编后，cal_ck1（K=33 ck=1 FN=73
  B8=0x100fd7a，最小序列 insmod+smi）稳定复现 **GspMsgQueueSendCommand+0x9b 内核
  oops ×3**（journal 06:36），而非 v17 流程的 GSP Xid120。fire 本身已确认稳定触发。
- 待解：v17（编译期 MAP，t4probe 流程 = mods 90s + 二次 insmod + smi → Xid120）与
  v21（module_param，最小序列 → host oops）的差异——候选：v21 对 pRpcX->length 的
  改写让 SendCommand 剩余路径（+0x9b 处的拷贝/计算）越界；或 mods 段建立的状态差异。
  下轮第一任务：objdump ko 的 SendCommand+0x9b 对应 v21 植入代码行；或给 v21 补
  "改写后恢复"逻辑。
- 判读通道已固化：VM persistent journal（Xid/oops 永不丢）；shot 落 /root/shot_xid.txt。

### 2026-10-19 补充（window0 结果 + 攻击面收敛）

- **window0 也不可读**（win0probe：stval=0x8000000010000000 cause 0xd）→ B8 回调 MPU
  仅 RM 空间（GSP-17 待入台账）。**内核对象（FB/walk 表/数据段）读写全封锁**；
  内核交互只剩 syscall 注入（内核上下文、受 meta/type 门控）。
- **t0=22（0x93007160）= type3+type8 成对操作**：a0=type3 handle（meta&1、type3）、
  a1=type8 handle（meta&1、type8）→ 0x93006fcc（region map/unmap 引擎，a4 flags、
  a3 size）。lab walk 表证明 RM 活跃对象正是 type3（2 个）+ type8（9 个）结构。
  **a0/a1 双控（GSP-16）+ RM 内存可读（handle 可侦察）→ 对 RM 活跃对象注入
  t0=22 = 内核上下文 UAF 候选主攻线。**
- 收敛后的提权路径图：
  1. 读原语侦察 RM 对象（[s3] 类）拿 type3/type8 handle；
  2. B8 注入 t0=22(a0,a1) → 内核对活跃对象 region 操作/销毁（0x93006fcc destroy 条件待全解）；
  3. UAF 后 RM 继续用 → 伪对象（RM 内存可控）→ 内核侧越权。
  辅助线：不查 walk 的 handler（t0=7：a0=[a0+0x61a] 二级解引用）= 伪对象直接候选。

# 进度记录

## 2026-10-19（深夜最终轮）— RM 活跃期 fire + 读原语成功（E1 里程碑）

- **firen + FN 调优攻克**：spy 流量分析显示 boot 期 fn=73 仅 1 条，cuInit 流量主力是
  fn=76（registry read 60+ 条）。v17 的 firen 变量是死代码（声明了但 fire gate 没检查），
  已直接修改 rpc_ovf_patch_v17.py 加上 `_xdigOvfFnCnt > _xdigFireAfterN` gate。
  FN=76 + firen=40 → fire 落在 cuInit 中期（RM 完全活跃、对象已建、指针已填）。
- **首份 RM 活跃期读取数据**：
  - [0x04191678] = **0x80e7ffafe097856a**（非零！但不是早期 K3-1 泄漏的 0x0FE4790E10——
    cuInit 流量期间该地址内容已被覆写或值变化）
  - [0x14FB74C] = **load fault**（RM .data 段不在回调 MPU 可见区，只有 staging/heap 可读）
- **v17shot 射击器完善**：计划文件 5 列（名字/map/firen/spy/fn），支持任意组合。
  已知可用参数：FN=76+firen=40 → RM 活跃期 fire；FN=73+firen=0 → boot 期 fire。
- **spy 数据(95 条 RPC)**：完整 boot→cuInit 流量 fn 分布已归档
  （fn=76 主力，fn=72/103/65/228/71/10 次要，fn=73 仅 1 条 boot 期）。
- 下一轮：① 系统扫描 RM staging/heap 区（0x0419xxxx、0x0FE47xxxx）找 handle；
  ② 用非零读出值（0x80e7ffafe097856a）识别数据类型；③ t0=7/22 注入。

## 2026-10-19 — NS-Q2 第一步：init 参数 blob 契约实测；fixture 遭遇 QEMU dispatch 阻塞

恢复点：

- 上一检查点：`e3ce459`（384B 启动区域表）。
- 本轮产物：`scripts/probe-lab-init-args.sh`、`logs/lab-init-blob-pre.bin`（8.2MB 全零）、
  `logs/lab-init-a3-region.bin`、`logs/lab-init-a7-region.bin`、`docs/LAB_BOOT.md` 新章节。

已完成：

- **0x93005550 语义破解**（消费者，静态+动态双验证）：
  - `0x93005550(base, size, kind=12, out)` = init memory regions 解析器；
    返回非零 → init panic line 220（即 fixture 停点 `reason=init_args line=0xdc` 的真正出处）。
  - 入口要求 `(base|size)&0xfff==0` 且 `size!=0`；fixture 传 0/0 → 返 1 → panic。
  - 把 `[base, base+align4k(pages*24))` 当 24B/页描述符数组，尾部作 buddy 堆，
    **自己切分并回填描述符**；分配 type-12 对象（与 t0=23 CREATE 同分配器），
    注册 `0xa300a7f0`，`[0xa301a130]=size`。
- **blob 入口内容全零**（8.2MB dump）——生产者只给清零内存，fixture 无需合成内容。
- **生产布局实测**：`a1=FB+0x801c000 a2=0x7e4000`、`a3=FB+0x1068000 a4=0x4000`、
  `a7=FB+0x8001000`（内核数据段 backing：MPU slot 7 PA=a7、size=0x1b000）；
  a3/a7 消费者是 `0x93006d68(...attr=12)`。
- lab 中 0x93005550 返回 0、out=0xffffffffa300e030（ref=2、kind48=12、
  heap=[FB+0x8028000,FB+0x87fffff]）；walk 表 0x803a000 即从该堆分配。
- **反汇编基址纠正**：code.bin 实际加载在 0x92fff000，反汇编必须
  `--adjust-vma=0xffffffff92fff000`（错位 0x1000 会得出完全错误的结构；已写入 LAB_BOOT）。

未完成 / 阻塞：

1. **QEMU 11.1.2 CPU iotlb dispatch 阻塞（新发现，硬阻塞）**：fixture 机器
   （staging@0x80000000 + FB@0x7400... + SYS@0x9400...）中，内核 MPU slot PA 指向
   FB/SYS 的数据访问被解析为 `io_mem_unassigned`（tlb_set_page_full 实测
   name=NULL/is_ram=0）→ store transaction failed → mcause=7。flatview/monitor/rom
   路径完全正常；`info mtree -f -d` 显示 dispatch 树把 FB/SYS 子树挂在"错一位"的
   root 槽（58/74 ≈ 0x74/0x94>>1），疑顶层槽宽 off-by-one。已排除 MTTCG/顺序/强制
   commit/@0 dummy/staging 大小。lab（32M@0）不受影响。详见 LAB_BOOT 新章节。
   → 后续：深挖 fill 路径中 section 的来源；修好前 fixture 无法按生产布局
   把 data/blob 放 FB（暂维持 staging 布局，probe-kernel/test 全绿）。
   追加证据（同日深夜）：**竞态实锤**——同二进制同参数一次成功（到达
   0x93002052）多次失败；`info mtree -f -d` 树正确（58/74 为十进制=0x74/0x94>>57，
   "错一位"系进制误读已更正）；FB fill 在 `address_space_translate_for_iotlb` 的
   打印从未触发而 tlb_set_page_full 已拿到 unassigned section（来源路径待查）；
   `drain_call_rcu()` 无效。
2. handoff init 参数 blob 与内核日志窗口 0xffffffff60000000 仍未在 fixture 建模
   （受 1 阻塞）；a3 区 frame 目录内容已 dump 待解析。
3. 其余同上一检查点。

## 2026-10-18 — 启动区域表：生产者实测 + 审计分支模型

恢复点：

- 上一检查点：`9c84e26` (`lab: test the slow-handler state/ref condition`)
- 本轮改动：见 `git log`（`handoff=fixture`、CSR 0x5c0、`probe-lab-table`）

已完成：

- **生产 SBI server 的 384B 区域表已实测**（`make probe-lab-table` → `logs/lab-boot-region-table.bin`）：
  - 契约 `source = (a5<<58) + a6 + 0x200`（64 位回绕），16×24B，`size==0` 跳过；
  - lab profile 生成 4 个非空项：FB WPR heap、WPR meta、整段 FB aperture、SYS；
  - init 解析后的 9 条记录在 `logs/lab-region-records.bin`；`+8` 字段是滚动累加值，不是地址。
- `nvidia-gsp,handoff=fixture`：声明式 boot handoff profile
  - 仍跑生产 FMC 的 SHA384/ECDSA-P384 门禁；
  - FB `0x7400000000000000` 256 MiB、SYS `0x9400000000000000` 16 MiB 是真实 RAM；
  - 区域表写在 `FB+0x800`，只声明被支撑的三段；驱动用生产回绕编码传 `a6 = FB+0x600`。
- `CSR 0x5c0`（内核 trap scratch，静态只有 `0x9300395e` 写 / `0x930039e2` 读两处）与
  `time (0xc01)` 时间源已建模，trap 入口不再立刻 illegal。
- `make probe-kernel` 新结果：

```text
ORIGINAL_BOOT_REACHED_INIT pc=0xffffffff93001ec6 a0=0x30 a5=0x3 a6=0x7400000000000600
BOOT_REGION_TABLE_ACCEPTED pc=0xffffffff93002052
    va=0x8000000000800000 len=0xf800000 pa=0x7400000000800000
NEXT_UNMODELED_INPUT reason=init_args pc=0xffffffff9300395e a0=0xb line=0xdc
TRAP_AFTER_PANIC pc=0x8000006c mcause=0x5 mepc=0xffffffff930041c2 mtval=0xffffffff60050800
```

回归：

```sh
make test        # 通过：包验证/ISA/MPU/kernel+区域表/lab-isolation/lab-walk
make probe-lab-table
```

未完成 / 下一处：

1. **handoff init 参数 blob**：入口 `a1`（指针）/`a2`（大小）未建模。本 profile 传 0，
   `0x93005550` 返回非零，init 走 `line 220` 致命路径；生产 lab 为
   `a1=FB+0x801c000, a2=0x7e4000`，由原始 SBI server 构造。
2. **内核日志窗口**：`0xffffffff60000000`（静态记录 kind=2，8 MiB）在本 profile 无 MPU 窗口，
   panic 路径写 `+0x50800` 触发 `mcause=5`。生产 lab 由 boot 环境在进入内核前建立。
3. 其余同上一检查点：walk 表 `obj/meta` 低位语义、handle→索引规则、RM 任务启动、FMC 后 M-mode 服务。

注意：`handoff=fixture` 是**声明式功能 profile**，不是 BootROM/熔丝认证；
`0x8000000000800000` 等地址只属本 profile。

## 2026-10-18 — walk 表发布检查点

恢复点：

- QEMU 源码提交：`5d33402` (`hw/riscv: NVIDIA GSP MPU, packet verification and functional lab`)
- gsp_qemu 提交：`efc46f6` (`gsp-qemu: signed-FMC lab boot and walk-table checkpoint`)

已完成：

- 生产 FMC 的 SHA384 + ECDSA-P384 验证接入 `nvidia-gsp-lab`，错误信任锚在 CPU 启动前被拒绝。
- 只有签名和 GFW/BootROM 载荷逐字节匹配通过后，才建模 `GspFwWprMeta.verified`。
- 修复 WPR heap `[0x801000,0x1000000)` 与 GSP FW image `[0x1000000,...)` 的重叠；init 区域检查通过。
- 修正 init args 页 `VA 0x4001000` 的实际支撑页（`FB+0x7003000`），发布 `id8=2` 的 heap grant。
- 原始生产 LibOS 执行到 `0xffffffff93007324`（`sd s7,0x450(s0)`）。
- 本 profile 结果：

```text
global=0xffffffffa3013030 -> [global+0x450]=0x800000000803a000
global=0xffffffffa30134d0 -> [global+0x450]=0x8000000008046000
```

walk 表内容（通过 MPU slot 0 的 FB 别名回读）：

```text
table VA  = 0x800000000803a000
table PA  = 0x740000000803a000

initial (first write):
  sha256  = 98dbb968929aded4b23a8a020cb58a5840184d181db32e03b45a5f71d5df50d6
  header  = 0xb, 0x80, 0x2
  free    = 116 (0xc..0x7f)

populated (second write):
  sha256  = 6f1efbdd5c9f877767d261eaee3398d19978d5f70a0614a827a56279df3c339d
  header  = 0xe, 0x80, 0x1
  valid   = idx 1,8,9,0xb,0xc,0xd, all with meta bit63=1
```

第一次 dump 是 free-list，`meta=0`；第二次发布后表已填充，`meta=[entry+16]` 的 bit63=1，符合 `0x9300a090` 的 lookup。

第二个 global `0xffffffffa30134d0` 的 `[+0x450]` 是更大的表：

```text
table VA = 0x8000000008046000, PA = 0x7400000008046000
header   = 0xd, 0x2000, 0x1
allocated= idx 1,8,9,0xb,0xc (meta low bits 1/2/3)
```

同一对象 `0xffffffffa3015060` 可以以不同 meta 低两位出现在不同 slot；`count` 可以是 0x80 或 0x2000，条目布局一致。

回归：

```sh
make test              # 通过：包验证/ISA/MPU/kernel/lab-isolation/lab-walk
```

未完成 / 下一处：

1. 解码 populated 表 `obj/meta` 的低位类型语义，以及 handle（真机样例 `0x0303000000307c70`）的 idx=0x70 如何选择 0x80/0x2000 slot 表。
2. `init.elf` 后续 map（错误字符串 `0x20004bb0` 路径）和 GSP-RM 任务启动。
3. 真机 32GB FB 的 ACR WPR 布局（non-WPR 3MB、heap 135MB、FRTS 1MB）与 lab 256MB 功能 profile 的差异需要在探针侧换算。
4. FMC 之后的 M-mode 服务、DMA 设备、BootROM 认证/解密策略。

注意：`0x800000000803a000` 是 **本 QEMU 功能 profile** 的表地址，不是真机地址；不得把本检查点等同于真机启动成功。

## 2026-10-18 — GLM 假设的 lab 验证

确认：

- `0x9300a090` lookup 布局正确；t1/t2 populated 表已 dump。
- walk 返回 stripped meta=0/1/2/3；TYPECALC(0x93004568) 在这些对象上执行。
- release(0x93005b26) 大量执行。

未确认：

- `meta & 0xC == 0xC` 不是本 lab 首批 TYPECALC 路径的前置条件；`0x93000900` gate 在观察窗口内 0 次命中。
- 把 t1 首项 meta 改成 `0xD` 后，release/TYPECALC 行为在窗口内无可见变化。
- `0x93005096` 的 9-bit slot 263 属于哪张表/哪个 base 尚未定位；`0x80/0x2000` 是对象 slot 表。

需要 GLM 补：`0x93005E94` 完整函数/a3 来源；`0x93005096` 的表 base/调用者；`0x93000900` gate 的具体路径。

补充：`0x93005096` 首次实测 raw=0x400000，table=0x8000000008045000，entry0=0x740000000804308c，entry263=0。公式 `(raw>>12)&0x1FF` 成立；handle 表是 512 项 8 字节表，与 0x80/0x2000 object table 不同。真机 handle 的 slot 263 需要另一张表实例。

修正：0x93005E94 的 a3 是区域 size（0x1000000/0x800000/0x4000），0x93005C6C 是区域分配器，不是 meta 写入者。meta 写入在 0x93005934，wrapper 0x9300581e；meta 低位来自调用者 a3 类型：
  0x93007406 a3=1 -> meta ...0001 slot b
  0x930074aa a3=1 -> meta ...0001 slot 1
  0x93002d1c a3=0 -> meta ...0000 slot c
  0x93002db0 a3=2 -> meta ...0002 slot d
t2 idx c meta=3 对应 a3=3 注册，调用点待补。

wrapper 0x9300581e 类型样本补全：type0 ra=0x93002d20；type1 ra=0x93007406/74aa/74e2/0x93007266/0x930067dc；type2 ra=0x93002db8/74fa；type3 ra=0x930032b2（global a30134d0 obj a3015060）。a4 是辅助标志不是 slot；slot 由表分配。

新证据：a4=1/8/9 分别对应 slot 1/8/9；a4=0 走 free-list。静态找到 type12 注册点 0x9300633c（li a3,12; wrapper -> meta ...000C），对象由 0x9300543a 分配并保存 global 到 +128。session 是 a3007e28，不是 global；[session+0x18] 是 outer table base 且随调用变化；[global+0x18] 是 list/0，不是 outer table。

关键：0x93003902 证明 [global+0x450] 是 syscall dispatch table；walk index=syscall number。boot 表仅注册 1,8,9,0xb,0xc,0xd；t0=4/t0=23 为 0，dispatcher 在 0x9300391e 返回 a0=2 错误，不会调用 0x93006300。0x93006300 的 type12 对象用 a4=0 自动 slot，不是 slot23。wrapper 显式 slot：meta>=0 可插入，meta<0 已占用走 0x58b2 错误；无旧 refcount 检查。

重大纠正（GLM 正确）：0x93003902 在 t0=9 handler 0x930038fe 内，不是全局 syscall dispatcher。真正 dispatch 在 0x930043e6..0x9300440a，使用 handler 表 0xa3008280 + t0*8：t0=4 -> 0x930008cc，t0=9 -> 0x930038fe，t0=23 -> 0x93006300。因此 [global+0x450] 是对象/handle 表，t1[23]=0 不是 23→4 的反例（撤回）。KINIT n=3: sscratch=global=a3013030，[sscratch+0x450]=[global+0x450]=t1。23→4 表层面自洽；仍缺 create handler 的 slot/handle ABI 和 t0=4 fast path 与 0x930008cc 的关系。

直接 handler 实验通过：KINIT n=3 调用 0x93006300 -> a0=0, slot=0x17, t1[23] obj=8000000008245030 meta=...000C, refcnt=1 state=0；再调用 0x930008cc(a0=0x17) -> a0=0, state=1, meta/refcnt/表项保持。证明 create->release handler 路径；不是销毁/清表或完整用户生命周期。脚本 scripts/test-lab-release.sh，make test-lab-release。

第二次 release 实测：a0=0，t1[23] meta 仍 0xC，refcnt 1->2，state 仍 1，表头 0x18。release 不是销毁/清表，表项很可能持有引用；需要 GLM 说明 state=1 和后续释放路径。

真正销毁路径已实测：create type-12 obj (slot 0x17, ref=1, state=0)，直接调 0x93005B26(obj) -> ref 1→0，TYPECALC -> dtor 0x93008130，priv=1 (S-mode)，进入 dtor entry。t0=4 handler 是 lookup/deref：+1，state=0 时 -1（净1）并置 state=1；state=1 时跳过 -1（第二次 ref 1→2）。这解释全部 release 数据。仍未证明 U-mode 可把正常对象 refcount 控到 0 并到达 dtor；直接 0x93005B26 是诊断路径。

t0=10 handler 0x93000bde：先 meta&2 检查（type12 meta=0xC 被拒 a0=2），再 TYPECALC type 5 或 0x491 位图（0/4/7/10），再 ref+1 -> 0x93005B26（净0），不是 net -1。gadget 0x930035d2 (mv a0,a1; jal 0x93005B26) 受控 a1=type12 obj -> ref 1→0 -> dtor 0x93008130 priv=1。U-mode PC/a1 控制仍未证明。

t0=4 fast path 受控实测：t0=4, stval=0, a0=slot, sscratch=global, sepc=marker -> 0x93004382 处 state 0->1，ref 仍 1，未调 0x93005B26，未调 handler 0x930008cc。自然 boot 的 0x930042f8 命中为 t0=0/1/0x16，未观察到 t0=4/23。TYPECALC 从对象页+0x20 取 class；dtor 表静态 BSS 零，运行时 type10 dtor 0x93008130。

t0=17 纠正：handler 0x93001AE0 中 s2=用户 a0，s1=0x9300543A 新分配对象；0x93001B64 jal 0x93005B26 的 a0=s1，不是用户 s2。用户 a0 只按字节存到 newobj+40；注册 type 3 后 ref=2，释放后 ref=1，无 dtor。前置 a1=slot12([a301a1c8]) 且 0x93008C26 成功；lab 自然服务返回 2，脚本强制为 0 到达分配路径。t0=17 是 create/register，不是 U-mode destroy。

GLM t0=17 静态扫描 80 个 li t0,17、无有效 stub，与 lab t0=17 create/register 反例一致。B8 只能执行 RM 0x01xxxxxx，kernel gadget 0x930035d2 不在 RM 范围；直接跳不可行（地址空间/静态支持，未拿到干净 U-mode fault 轨迹）。慢 handler 条件实测：state=1/ref=0 -> ref1/state1 无 dtor；state=0/ref=0 -> ref0/dtor 0x93008130 priv=1。普通 U-mode t0=4 fast path state=0 只置 state=1，不调 handler/0x93005B26；因此 RM 触发必须直接调 slow handler 0x930008CC，普通 li t0,4; unimp 不成立。

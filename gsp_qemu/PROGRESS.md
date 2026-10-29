# 进度记录

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

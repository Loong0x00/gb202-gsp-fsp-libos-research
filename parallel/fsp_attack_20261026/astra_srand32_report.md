# glibc lrand48 / srand32 CUDA 验证报告

## 结果

已完成 `srand32 <base> <count>`、`srand32test`、`srand32selftest`；编译及三项自检均通过。所有 GPU 执行均通过 `sudo gpu-allowlist run fsp-grind`，没有直接执行二进制、操作 VFIO VM 或修改生产固件。

本轮只执行一个 2^28 种子性能样本（另有合成自检与 2 种子边界测试），**未运行完整 2^32 搜索**。

进入任务时本地已有新增族的实现及一次失败的合成自检记录。本轮保留其实现，修复新自检的重复命中处理，补充一致率输出，并重新编译和验证。旧日志未覆盖；本轮有效证据以 `srand32_evidence/*.worker.log` 为准。

## 明确定义的采样协议

- glibc 初始化 `X = ((uint64_t)s << 16) | 0x330e`，每次按 48 位 LCG 更新后返回 `X >> 17`。
- 每种子 16 个偏移，偏移 n 丢弃 **n×20 次 lrand48 输出**，不是丢弃 n×20 字节。使用 host 预计算仿射跳步常量，device 直接到达对应状态；与 libc 顺序调用逐项核对。
- (a) `(uint8_t)out`，16 次；(b) `(uint8_t)(out >> 24)`，16 次。
- (c) 将输出视为 32 位字，依次抽取 `out>>24, out>>16, out>>8` 的低字节，6 次填满 16B（末次仅首字节）；散列输入取同一流的前 20B，需 7 次输出。这里采用最高三个字节，**不是**低 24 位的三个字节。
- 每偏移五个候选：(a)、(b)、(c) 前16B、SHA1(20B)[:16]、SHA256(20B)[:16]；共 80 次 `try_key`/种子。候选可能重复，不代表 80 个独立密钥。
- 新增单块标准 SHA1/SHA256 20B 实现；保留原 `sha256_22` 逐字节不变，没有顺带修正其既有填充逻辑。新散列的完整摘要与 OpenSSL 比对，旧 shactr 的 SHA256 标准符合性不属于本轮认证结果。
- 32 位区间禁止回绕，count 为正，base+count≤2^32。接受十进制和 `0x` 记法。每 2^28 种子输出进度，尾批也输出；普通批次为 2^18 种子。

## 重复命中的自检修正

(a) 只取状态的 bits17..24，因此固定偏移下只依赖种子的低 9 位；相差 512 的种子会生成同一密钥。原有大批自检产生大量重复真实命中，触发既有 `try_key` 的 `d_nhits>4` 快速返回，并导致不完整搜索。

未修改 `try_key`、record 或命中上限。合成自检改为每批 256 种子，逐批读取并用 `cudaMemcpyToSymbol` 重置命中符号；跨批累加真实命中，检查每批未触发上限。完整扫描 `[0x12345000, 0x12355000)`，得到 128 个相同密钥的认证命中，每批最多 1 个，`incomplete=no`。重复密钥仅打印一次。自检样本 4096B，避免旧 CTR 结构分支读取 256 个块时越界；明文首四字节为零，目标完全由 libc/OpenSSL 合成。

普通模式保留旧命中语义：模式0/1标为 GCM 验证，模式2仅标为未验证 CTR 结构候选；出现结构候选或命中上限时警告并返回2，不将其计为完整可靠的搜索。本次性能样本 nhits=0，不存在该提前跳过问题。

## 构建与执行

工作目录：`/home/user/rt_5090_project/parallel/fsp_attack_20261026`

```sh
/opt/cuda/bin/nvcc -O3 -arch=sm_120 -o fsp_cuda fsp_cuda.cu -lcrypto
# 每次执行均先覆盖包装器参数文件，例如：
printf '%s\n' 'srand32test' > /tmp/fsp_grind_task.args
sudo gpu-allowlist run fsp-grind
```

按顺序执行：`srand32test`、`srand32selftest`、`selftest`、`srand32 0 0x10000000`，以及非法参数检查和末端 2 种子检查。构建退出0；三项自检及性能样本包装器退出0。

## 吞吐与估算

| 项目 | 结果 |
|---|---:|
| 实测种子数 | 268,435,456 (2^28) |
| 实测候选调用数 | 21,474,836,480 (2^28×80) |
| 耗时 | 54.435125 s |
| 种子吞吐 | 4,931,291.28 seeds/s |
| 候选吞吐 | 394,503,303 candidate keys/s |
| 命中 | 0 |
| 全量候选数 | 343,597,383,680 (2^32×80) |
| 线性全量估时 | 870.962 s ≈ 14分30.962秒 |

耗时由 host steady_clock 包围分批 kernel 启动、同步及进度处理得到，不包含前面的文件加载、分配与常量初始化；不是 CUDA 纯 kernel 时间。全量估时为样本耗时×16，依赖同等负载、温度、频率及无大量命中条件，不能视为保证。合成自检使用小批及重复认证命中，其吞吐不能用于全量估算。这里只测得一次有限样本正常完成，不声称经过长期压力测试。

## 边界与不确定性

- `srand32test` 使用真 libc `srand48/lrand48`，100 个 OpenSSL 随机参数加6个边界参数（含高位及 0xffffffff）。每种子核对320个完整输出，及全部16偏移的采样材料/完整SHA1/SHA256，共176,384字节，逐字节一致率100%。随机种子原文记录如下。
- 用户提及的 NIST 种子起源论文及其采样协议未作独立来源核实；本实现验证的是上述明确协议，不能据此声称复现了论文全部结论或证明固件使用此生成方式。
- 无命中只排除本次范围、采样协议与现有过滤/GCM布局下的候选。旧 filter 可能排除其他明文，旧 gcm_verify 仅实现 layout A，CTR 结构候选不等于认证解密；不能据本次结果否定全部可能生成模式。
- 旧组件及 selftest/windows/shactr 主分支与已有备份逐字节比对一致。旧 selftest 的 PASS 是现有测试范围，不将其夸大为新增全套 AES/GHASH 形式验证。没有运行 compute-sanitizer。
- 原始固件未修改。任务结束时包装器参数恢复为进入任务时的 `srand32selftest`，没有留下全量搜索指令。

## 原始证据

### 编译

```text
nvcc_exit=0
```

### libc 与 device 一致性

```text
srand32test seeds (6 edges + 100 OpenSSL random):
00000000 00000001 7fffffff 80000000 ffffffff 12345678 5615725f 23cb6319
f216604c 4e8a8a32 4b248650 1d750424 4c1b1881 605113b3 25c5f39a 273c7a44
da54db55 d1cc4b6f 151120d7 33e91435 99ff9922 eaffc1aa a08ff126 83ffe205
37b2ab6a 576f149d d0e2bab0 6ba7ace7 131e7586 efd758cb 98a41d71 5b8504c9
b063cd50 d187d116 2c308f26 1e8a31ea eab806c6 df342fc2 61a0615c e9c4cf89
e7246cfa e98d2ab5 eea2fa05 c12db24c 6f09b226 8617e887 f73ea94a 7ad33c9d
e1e4c8cc 37039b05 0d358406 8252a96a 7fb86ce5 8e566e5e 44cf9282 325e4eee
e42447a4 a236ff1f 184d14cf 1f883271 968a8332 17f72c21 d1394d45 f95af1f7
47b4a06e a4c77287 2ca6721b 22a6f49c 5628ffe5 b3b970aa 0a7757b9 0d9e3c7f
095c3ac2 a5949357 3e0614a2 32ef0849 f264719f 82f1e0df 0b8c1f36 eba33b21
6bd432dc 0ac57953 ee56eefc 6ffbde18 b789bd30 7b029c8d 8b814e93 4cd046f4
55283a3b 4afb6b1a 7b8315d4 4ebc86c6 863dee74 87db9645 d14ea996 2e1324b6
313e38fa f53567ca 6bff5100 1300eacb 2bac7a11 e36e2a82 407c2100 69ca9908
82e3a690 10be2d21
libc lrand48: 106 seeds x 320 calls = 33920 full outputs: PASS
byte streams + full SHA1/SHA256 (OpenSSL): 106 seeds x 16 offsets x 104 bytes = 176384 bytes: PASS (100% byte agreement)
SRAND32TEST PASS
wrapper_exit=0
```

### 合成密钥回收

```text
Synthetic libc seed=0x12345678 convention=a n=0 key=fa5c768d1c4e956ac6d034b7d73896a2
[srand32] base=0x12345000 count=65536 variants/seed=80; high=v>>24 packed=v>>{24,16,8}
GCM_VERIFIED_HIT mode=0 key=fa5c768d1c4e956ac6d034b7d73896a2
  65536/65536 seeds nhits=128
done 0.342686s (191241.892 seeds/s; 15299351.4 candidate keys/s) candidates=5242880 nhits=128
recovery batch=256 max_batch_hits=1 incomplete=no
SRAND32 RECOVERY SELFTEST PASS
wrapper_exit=0
```

### 既有 selftest

```text
AES(fipskey)=69c4e0d8.. expect 69c4e0d8..
KS(IV||2)=5625a3f41d785f2cfa3fde1e82fc6737
H=4d705945240d0c24f2b86e7d353272ff
Y1=c05b6e17ffa566bcf51649a4b4e3d6df
devtag=ed18a835e3ca54e6de96131f7a7f6d34
rmtag =ed18a835e3ca54e6de96131f7a7f6d34
hosttag=ed18a835e3ca54e6de96131f7a7f6d34
hostH  =4d705945240d0c24f2b86e7d353272ff
selftest: nhits=1 (expect 1, mode 0)
recovered key: 030a11181f262d343b424950575e656c
negative: nhits=0 (expect 0)
SELFTEST PASS
wrapper_exit=0
```

### 2^28 性能样本

```text
[srand32] base=0x00000000 count=268435456 variants/seed=80; high=v>>24 packed=v>>{24,16,8}
  268435456/268435456 seeds nhits=0
done 54.435125s (4931291.28 seeds/s; 394503303 candidate keys/s) candidates=21474836480 nhits=0
wrapper_exit=0
```

### 旧逻辑保持检查

```text
kexp: byte-identical PASS
aes_enc: byte-identical PASS
gf_shl1: byte-identical PASS
ghash_mul: byte-identical PASS
gcm_verify: byte-identical PASS
filter_ok: byte-identical PASS
record: byte-identical PASS
try_key: byte-identical PASS
sha256_22: byte-identical PASS
k_windows: byte-identical PASS
k_shactr: byte-identical PASS
k_debug: byte-identical PASS
k_single: byte-identical PASS
legacy selftest/windows/shactr main branches: byte-identical PASS
no cudaMemset of device symbols: PASS
```

### 非法参数拒绝

```text
COMMAND srand32 0xffffffff 2
srand32 requires base in [0,2^32), positive count, base+count <= 2^32 (no wrap)
wrapper_exit=1 (expected 1)
COMMAND srand32 0 0
srand32 requires base in [0,2^32), positive count, base+count <= 2^32 (no wrap)
wrapper_exit=1 (expected 1)
COMMAND srand32 -1 1
srand32 requires base in [0,2^32), positive count, base+count <= 2^32 (no wrap)
wrapper_exit=1 (expected 1)
COMMAND srand32 0 0x100000001
srand32 requires base in [0,2^32), positive count, base+count <= 2^32 (no wrap)
wrapper_exit=1 (expected 1)
COMMAND srand32 nope 1
srand32 requires base in [0,2^32), positive count, base+count <= 2^32 (no wrap)
wrapper_exit=1 (expected 1)
COMMAND srand32 0
srand32 requires base in [0,2^32), positive count, base+count <= 2^32 (no wrap)
wrapper_exit=1 (expected 1)
```

### 区间末端尾批

```text
[srand32] base=0xfffffffe count=2 variants/seed=80; high=v>>24 packed=v>>{24,16,8}
  2/2 seeds nhits=0
done 0.000565s (3541.35237 seeds/s; 283308.19 candidate keys/s) candidates=160 nhits=0
wrapper_exit=0
```

### 交付哈希

```text
b41cf0bf7258bc0a0bbaba44f3939ac24e4942c58a667b4c37f16be22a3e3252  fsp_cuda.cu
56d4881dd68713d98ce62cade33649e19229013017fdedb15bb732b5fcb610aa  fsp_cuda
```

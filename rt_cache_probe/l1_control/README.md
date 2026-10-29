# RTX 5090 L1 前提复核

这个目录只复核 RT-cache 调查的前提，不把普通 CUDA L1 当成 RT 私有缓存。

## 实机硬件属性

CUDA 13.3 在本机 RTX 5090（CC 12.0）返回：

```text
multiProcessorCount          = 170
l2CacheSize                  = 100663296 bytes = 96 MiB
sharedMemPerMultiprocessor   = 102400 bytes = 100 KiB (CUDA-visible limit)
```

NVIDIA Blackwell 白皮书给出的物理统一 L1/shared 池是每 SM 128 KiB。本机
Nsight GB20x metric 配置进一步说明它由两块 64 KiB SRAM 组成。`64 KiB` 是
单块 SRAM 的尺寸，并不自动等于整个 L1 的有效容量。

## 对 Claude `latsweep.cu` 的审计

原程序的 Sattolo 单环和依赖指针追逐适合观察小工作集延迟；编译出的 GB202
SASS 是严格依赖的 `LDG.E.CONSTANT` 链。L1 区域的 warm-up 和测量步数也足够。

但原扫描在 64 KiB 后直接跳到 96 KiB，所以数据只能把边界限制在二者之间，
不能把 64 KiB 称为“最后平台点”。本目录的细扫结果见
[`results.tsv`](results.tsv)：84--89 KiB 仍约 48--52 cycles，90 KiB 开始
出现渐进式 miss，96 KiB 已严重 thrash。这个访问模式下的近满命中工作集约为
89 KiB，而不是 64 KiB。由于 L1 是集合相联缓存，渐进 miss 曲线不是物理 SRAM
在某一个字节处硬切断；不要把约 89 KiB 的有效工作集反称为物理容量。

原程序另有一个独立限制：测量固定为 2^21 次访问。工作集大于 8 MiB 时并未
走完一个随机环，因此 96 MiB/1 GiB 部分主要是在测随机冷访问、TLB 和 DRAM，
不能据此定位 L2 容量。L2=96 MiB 的结论由白皮书与 CUDA `l2CacheSize` 直接
确认，而不是由那段大工作集曲线确认。

## 只读性能计数器交叉验证

对同一单线程 kernel 只读采集：

| 工作集 | L1 hit sectors | L1 miss sectors | hit rate |
|---:|---:|---:|---:|
| 88 KiB | 1,438,976 | 2,818 | 99.80% |
| 90 KiB | 1,406,156 | 68,406 | 95.36% |
| 96 KiB | 1,150,066 | 422,800 | 73.12% |
| 112 KiB | 886,690 | 948,320 | 48.32% |

`tpc__l1tex_sram_bytes_mem_tagged_realtime` 在这些运行中均为每 TPC
261.76 kB（十进制显示），约合每 SM 127.8 KiB tagged SRAM。它直接反驳
“默认固定预留 64 KiB shared，所以只剩 64 KiB L1”的解释。配置容量与随机
访问下的有效命中容量是两个不同概念。

## 构建与低负载运行

```bash
/opt/cuda/bin/nvcc -O3 -arch=sm_120 l1_effective_probe.cu -o l1_effective_probe
./l1_effective_probe 88
./l1_effective_probe 96
```

程序限制工作集为 2--512 KiB，只启动 `<<<1,1>>>`，不锁频、不改功耗、不改
驱动设置。每个工作集至少 warm 8 个完整环，再测 64 个完整环。

# `gb202_reghal_offline.py` 分块扫描与资源回归

日期：2026-07-21

## 结果

原脚本的普通入口使用 `Path.read_bytes()`，会一次性把
`392,339,552`-byte MODS ELF 放入 Python heap。现已改为：

- 以 4 MiB chunk 顺序扫描 chip-ID descriptor；
- 只保留 3-byte 边界 overlap；
- 用 `os.pread` 读取候选 header 和声明的压缩 stream；
- 在同一次顺序扫描中增量计算整个输入的 SHA-256；
- 只长期保留解压后的 RegHal 表和 19,999 个解码 row。

修改后的脚本 SHA-256：

```text
e9cc196414125c3b420340b29988a783b72fea1f93a0f1bff2fcacce2a0eb5c2
```

## 128 MiB virtual-memory guard 下的回归

执行命令：

```sh
zsh -c 'ulimit -v 131072; export PYTHONDONTWRITEBYTECODE=1; \
  exec python3 gb202_reghal_offline.py --self-test \
    --bar0 0x82013c --bar0 0x8200f8 --bar0 0x820040'
```

进程在该 hard virtual-memory limit 下 exit 0，关键输出为：

```text
sha256=c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf
chip=0xff2 header=0x8fd61aa compressed=29724 uncompressed=559972 rows=19999
self-test: PASS

fixed-selector BAR0 0x0082013c: 0 lookup row(s)
fixed-selector BAR0 0x008200f8: 2 lookup row(s)
  0x105c4000 -> domain 5, offset 0xf8
  0x105c8000 -> domain 5, offset 0xf8
fixed-selector BAR0 0x00820040: 2 lookup row(s)
  0x104f0000 -> domain 5, offset 0x40
  0x104f4000 -> domain 5, offset 0x40
```

第二次同样受 128 MiB guard 的查询还确认：

```text
0x205c4000 -> field [7:4]
0x405c4000 -> constant 0xf
0x405c4100 -> constant 0x0
```

`0x82013c` 没有 ordinary RegHal lookup row，只表示这张固定 GB202 RegHal 表没有
以普通 read-ID 公开它；不能由此断言 GSP、FSP 或硬件不存在该寄存器。

## 证据边界与安全

这项修改保留 descriptor validation、bounded zlib decompression、delta-row
解码和 self-test 断言。后续 DeviceInfo2 审计只把 absolute 输出标签收紧为
`fixed_selector_bar0`：`0x820000` 是 embedded selector 的 instance0 fallback，
不是本卡 runtime PTOP base 的读取结果。128 MiB `ulimit -v`
通过证明该命令没有依赖原先约 374 MiB 的整文件 heap copy；它不是精确 RSS
测量。

整个回归只读取本地 MODS 文件。没有执行 MODS，没有打开 `/dev/nvidia*`，没有
访问 GPU/MMIO，也没有驱动、reset 或固件操作。

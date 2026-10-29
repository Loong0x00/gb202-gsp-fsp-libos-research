# GB202 SHA-384 记录与完整 Falcon 表交叉清单（纯离线）

日期：2026-07-22（Asia/Singapore）

## 范围与结论

本支线只读取四份已经保存的 canonical ROM/NVFW，逐 byte 枚举完整文件中的
`u32 | u32 | 48 bytes` 关系，再与 35 项 Falcon table 交叉。没有访问 GPU、
设备节点、PCI/BAR/MMIO、debugfs 或网络；没有执行、修改或写入任何固件。

结论有两点需要特别校正：

1. 先前在 `FSP_RUN` 前看到的第一个 `u32 = 34 (0x22)` **不能再称为 Falcon
   index**。四份文件的全部匹配都满足
   `covered_start = record + 0x38 + raw0`；因此 `raw0` 可机械解释为从 56-byte
   记录末尾到覆盖起点的相对距离。对于 Falcon index 22 和 34，`raw0` 都是
   `0x22`；这已经排除了“它就是 Falcon table index”的解释。
2. 每个 35-entry Falcon table 都只有 6 个非空项；只有 index 22 与 34 的
   descriptor 起点各有一条这种精确 SHA-384 记录。index 5、23、24、32 没有
   descriptor-start 同型记录。该 negative 只适用于这一个 byte layout，不能
   推导为它们没有其他认证层。

## 1. 可复算的 raw 关系

本文不为 private 字段赋予格式名，只使用以下机械关系：

```text
R+0x00  u32 LE raw0
R+0x04  u32 LE length
R+0x08  48-byte stored digest

S = R + 0x38 + raw0
stored digest == SHA-384(file[S:S+length])
```

验证脚本在每个文件的**每一个 byte offset**测试这条关系，要求 `length != 0`
且覆盖区间不越界。每份文件各找到 7 个 exact match：6 个长度至少 `0x38` 的
对象大小记录，以及一个稳定的 `length=1, SHA-384(ff)` outlier。后者在四份
样本中位置与指向随布局变化，故不能当成随机的 48-byte digest 碰撞；但其用途
未知，本文不把它命名为 Falcon manifest。

## 2. 全文件 exact-match 清单

表中每格为 `record / raw0 / length / covered_start`；`F22/F34` 表示覆盖起点
恰好等于该 Falcon descriptor 起点，`-` 表示不等于任何非空 Falcon descriptor。

| ordinal / 关联 | FE | ASUS | Dell Pro | HPE Pro |
|---|---|---|---|---|
| 0 / - | `372aa/22/344/37304` | `372aa/22/344/37304` | `3a2aa/22/344/3a304` | `3a2aa/22/344/3a304` |
| 1 / - | `37d22/d6/38/37e30` | 同 FE | `3ad22/d6/38/3ae30` | 同 Dell |
| 2 / - | `38c66/e206/aac/46ea4` | 同 FE | `3bc66/e286/aac/49f24` | 同 Dell |
| 3 / - | `47ee6/32/17982/47f50` | `47ee6/32/17977/47f50` | `4aee6/32/17982/4af50` | `4aee6/32/178e4/4af50` |
| 4 / -，1-byte outlier | `61746/ac2ca/1/10da48` | 同 FE | `646ce/b6496/1/11ab9c` | `646ce/bb0e6/1/11f7ec` |
| 5 / F22 | `10e0aa/22/cca0/10e104` | 同 FE | `11b0aa/22/c9a0/11b104` | `11fcaa/22/c9a0/11fd04` |
| 6 / F34 | `11b2aa/22/29450/11b304` | 同 FE | `1280aa/22/36c50/128104` | `12ccaa/22/37050/12cd04` |

所有数值均为十六进制。28 条 stored digest 都与各自覆盖区间的 SHA-384
逐字节相等。完整位置清单保存在
`parallel/falcon_manifest_table.results.txt`；完整 digest 与 payload SHA-256
由脚本在每次运行时直接打印。

没有任何样本出现重复的 exact covered range；每份文件的 6 个 active Falcon
descriptor pointer 也都互不重复。

## 3. 35 个 Falcon table entries

四份样本的 table header 均登记 35 项，非空 index/app/target 集合完全相同：

| index | app/target | vDesc | descriptor-start 同型记录 | exact coverage 相对 `0x50+word1` |
|---:|---|---|---|---:|
| 5 | `07/06` | v6 / `0x50` | 无 | n/a |
| 22 | `18/01` | v6 / `0x50` | 有 | `+0x50` |
| 23 | `19/01` | v6 / `0x50` | 无 | n/a |
| 24 | `15/01` | v6 / `0x50` | 无 | n/a |
| 32 | `23/0e` | v6 / `0x50` | 无 | n/a |
| 34 | `24/0f` | v6 / `0x50` | 有 | `+0x00` |

29 个全零空项为：

```text
0-4, 6-21, 25-31, 33
```

空项没有 descriptor，故“没有 record”不是缺失对象；真正可比较的是 6 个非空项。

### index 22

四份都严格满足：

```text
record length = 0x50 + word1 + 0x50
```

FE/ASUS 为 `0xcca0`，Dell/HPE 为 `0xc9a0`。record 覆盖的最后额外 `0x50`
bytes 仍是对象末端的高熵材料，覆盖结束后转为 `ff` padding。由于 v6 private
schema 未公开，不能给这额外 `0x50` 命名。

### index 34 / `FSP_RUN`

四份都严格满足：

```text
record length = 0x50 + word1
```

即 FE/ASUS `0x29450`、Dell `0x36c50`、HPE `0x37050`；覆盖结束后同样进入
`ff` padding。这确认了 `FSP_RUN` envelope 的精确磁盘边界，但不证明谁信任
这条 digest，也不等于签名链已经闭合。

## 4. 为什么 `0x22` 是相对距离，而不是 Falcon index

对 index 22 与 34 的八条记录均有：

```text
R+0x38 .. R+0x3a   ff ff
R+0x3a .. R+0x5a   0x20-byte PCIR structure
R+0x5a              Falcon descriptor

raw0 = 0x22 = (R+0x5a) - (R+0x38)
```

因此 `0x22` 正好是 `2-byte padding + 0x20-byte PCIR` 的跨度。更直接的反证是：

- Falcon table index 22 的十六进制值是 `0x16`，其记录 raw0 却为 `0x22`；
- Falcon table index 34 的十六进制值恰为 `0x22`，只是数值碰巧相同；
- 非 Falcon exact records 的 raw0 还会是 `0xd6`、`0xe206/e286`、`0x32`
  和更大的 layout-dependent 值，仍逐项满足同一相对距离公式。

所以此前的 `index | length | SHA-384` 应校正成不命名的
`raw relative value | length | SHA-384`。它在这些样本中行为像相对 offset，
但没有公开 private schema 时，本文不进一步猜正式字段名。

## 5. 跨样本关系

- Falcon table 的 6 个 active index 与 app/target 四份完全一致，只有 descriptor
  pointers 随 image layout 变化。
- Falcon 22 和 34 的 exact covered bytes 都按
  `FE = ASUS | Dell | HPE` 分成三组；这与既有三个 target/object 字节组一致。
- ordinal 1 的 `0x38` covered bytes 四份完全相同；ordinal 2 为
  `FE = ASUS | Dell = HPE`；ordinal 3 为 `FE = Dell | ASUS | HPE`；ordinal 0
  四份都不同。
- 1-byte outlier 四份都只覆盖一个 `ff`，所以 payload/digest 相同，但 raw0 与
  covered address 随各自布局变化。

这些关系证明 record 会随 covered bytes/布局同步更新，却没有给出它上层由哪把
key 认证、由谁消费，亦不能据此构造可接受的修改。

## 6. 可复现验证

脚本：`parallel/falcon_manifest_table.py`

```bash
cd /home/user/rt_5090_project
python3 -m py_compile parallel/falcon_manifest_table.py
python3 parallel/falcon_manifest_table.py \
  vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom \
  vbios_diff/unverified_TPU_280522_ASUS_Astral_1043-89E3_98.02.2E.40.85.rom \
  vbios_diff/dell_8d_payload/RTXPRO6000_GB202_GPU_98.02.8D.00.01.nvfw \
  vbios_diff/hpe_scexe_payload/RTXPRO6000_GB202_GPU_98.02.9E.00.01.nvfw
```

脚本没有默认路径、glob 或目录遍历，只读取命令行明确给出的 regular files。
本次版本 SHA-256：

```text
69d322cc729d5a218e4ca89e6baa55e5dc11cf62268649fc5093fdd58222038f  parallel/falcon_manifest_table.py
90cefd37e109684119e98c5ab64ef382048710dcdc344e1cd4bb5d70abb517eb  gb202_vbios_diff.py
```

## 最终边界

可以确定的是：完整 Falcon table 并非“每个 active entry 都有一条相邻同型
SHA-384 record”；只有 index 22 与 34 命中。还可以确定，首个 raw dword 是
相对定位量而不是 Falcon index。仍不能确定的是这些 records 的正式格式名、
consumer、上层签名 coverage 与 trust root。此次结果只修正磁盘结构模型，
不改变“不执行固件、不触碰运行中 GPU”的安全边界。

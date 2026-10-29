# 复跑命令：GSP-RM 寄存器窗口(BAR0/PRI aperture)证据

只读离线分析，不访问 GPU / 驱动 / 设备节点 / MMIO，不执行固件。

镜像：`/home/user/rt_5090_project/power_governor_reverse/gsp61057_rx_full.bin`
（RV64GC，加载基址 `0x1000000`，md5 `138c287af83b5026770f636b3b2c9f4b`，
长度 `0xE97000`；注意 PH0 `filesz=0xE9B000`，文件尾部缺 `0x4000` 字节）。
RW 段用 `.../gsp61057_rw_full.bin`（基址 `0x4000000`，长度 `0x1D5000`）。

依赖：`python3` + `capstone`（`CS_MODE_RISCV64|CS_MODE_RISCVC`）。
基础库：`/home/user/rt_5090_project/parallel/k3_device_work/rvlib.py`。

```bash
cd /home/user/rt_5090_project/parallel/ds_work

# 0) 一键复现全部证据 + 生成全部 .asm 产物（约 30 s）
python3 gsp_mmio_window_evidence.py

# 1) 核心惯用法：ld a4,0x318(a0); lui a3,1; add a5,a0,a3; ld s1,-0x468(a5); jalr a4
#    （= method=*(pObj+0x318); aperture=*(pObj+0xB98)），逐点反汇编已生成
#    regwin_idiom_*.asm / regwin_install_0x1b9f1f0.asm

# 2) 直接清单某个全局指针 xref（含 mv 别名传播）
python3 find_writer.py 0x41904e0 | head          # RX BSS 0x41904E0 的读点(≈30.8k)
python3 stores_range.py 0x4180000 0x41a0000 | head   # 该 BSS 区所有 store（0 命中 0x41904E0）
python3 fanout.py 0x41904e0 10 | head            # 读点后 10 条指令里用到的偏移高半

# 3) 枚举所有 `lui rd,0x82xxxx` 直接 BAR0 偏移点
python3 scan_lui_range.py 0x820000 0x825000
# 4) 全镜像反汇编 grep（例如找 -0x468 / 0x820xxx 组合）
python3 grep_disasm.py '\-0x468\(' | head
# 5) 某个 imm 的编码级扫描
cd ../k3_device_work && python3 imm_scan.py 0x820,0xbf0,0x820000,0xbf0000

# 6) 驱动侧交叉验证（GB202 RegHal 表 chip 0xff2），只读 MODS
cd /home/user/rt_5090_project
python3 - <<'PY'
import sys; sys.path.insert(0,"/home/user/rt_5090_project")
import gb202_reghal_offline as R
from pathlib import Path
p=Path("/home/user/rt_5090_project/mods_audit/static/extracted_inner/mods")
d,raw,_=R.find_table_file(p,0x0ff2)
for r in R.decode_rows(raw,d.row_count):
    if r.opcode==1 and r.is_lookup_row and r.domain==5 and r.offset in (0x40,0xd0,0xdc,0xf8,0x3814,0xc04,0x434):
        print(hex(r.reg_id), hex(0x820000+r.offset))
PY
```

# 复跑命令(只读;GSP 610.57.04 RV64 逆向)

工具依赖: `capstone` (python3)。基础库在
`/home/user/rt_5090_project/parallel/k3_device_work/rvlib.py`(RX 镜像,基址 0x1000000)。

```bash
cd /home/user/rt_5090_project/parallel/ds_work
# 1) 函数名字符串
python3 -c "from va2off2 import cstr; print(hex(0x1de6958), cstr(0x1de6958))"
# 2) 谁引用这个字符串(auipc+addi),并给出所在函数
python3 find_va_refs.py 0x1de6958
# 3) 反汇编目标函数
python3 disas_range.py 0x18bbd60 0x100 mnoc_server.asm
# 4) 反汇编 MCTP 提交/分发 API
python3 disas_range.py 0x1b594d0 0x1b594d0+0x600  # 或见 mctp_submit_0x1b594d0.asm
# 5) 调用图查询(基于 k3_device_work/edges.pkl)
python3 callgraph.py callers 0x1b594d0
python3 callgraph.py callers 0x18bbd60      # 直接调用者:无(经 0xc0 表间接调用)
python3 callgraph.py callees 0x18bbd60 0x18bbe58
# 6) 函数边界启发式
python3 fnfind.py 0x18bbe08 0x1b594d0        # 首次运行会重建 prologue_starts.pkl(~20s)
```

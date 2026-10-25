# Bug-aware inverse governor prototype

本目录把问题拆成三个可运行部分：

- `data_pipeline/`：610.57 只读统一采集、raw JSONL、CSV 与 run manifest。
- `algorithm/`：历史数据规范化、四类竞争模型、约束离散逆求解。
- `voltage_61057/`：当前 library/GSP 静态审计与两轨 aggregate target reader。
- `algorithm/gpu_inverse/digital_twin.py`：GPC/XBAR/SYS/NVD、双电压轨、传播、功率策略与状态延迟的可执行多域模型。
- `algorithm/multidomain_twin.py`：离线 simulate / compare / constrained solve CLI。

执行状态、证据路径和下一缺口见 `EXECUTION_BOARD_20260814.md`。

## 一条命令端到端只读 smoke

```bash
cd /home/user/rt_5090_project/power_governor_reverse/bug_inverse
python run_readonly_smoke.py
```

它会：

1. 审计当前 610.57 library/GSP 哈希和 method entries；
2. 采集 10 条 core+voltage bracket；
3. 导出规范 CSV；
4. 以 NVVDD target 为显式响应，运行 uncertainty filter 和四模型比较；
5. 运行 observed-only 3300 MHz / 1080 mV / 800 W 查询；
6. 将所有输出写到新的 `integration_artifacts/read_only_smoke_*` 目录。

该入口不调用 SET、offset、锁频、功率写入或 benchmark。由于 core profile 不采 board power，最后的 observed-only 求解预期会如实返回缺少功率观测，而不是伪造可行性结论。

## 多域数字孪生

模型、实测 PTX 上包络验证、XBAR offset 等价类、GPC 选择层次以及 SYS/MSVDD 边界见 `MULTIDOMAIN_DIGITAL_TWIN_20260816.md`。该路径完全离线，不访问 GPU。

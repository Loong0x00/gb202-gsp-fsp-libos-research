# FSP 驱动 570.144 / 610.57.04 / 615.78.08 差异审计

## 总结

跨代确实增加了 FSP 诊断能力，但没有发现 `FSP_RUN` 明文、任意 IMEM/DMEM 读取或解密后固件导出接口。新增能力的性质是：更多传输方式、更多日志、更结构化的错误遥测，而不是固件明文导出。

## 版本差异

| 版本 | 新增/保留的相关能力 | 对明文目标的含义 |
|---|---|---|
| 570.144 | GB202 secure-boot 等待、`kfspDumpDebugState_GB202`、基础 NVDM/COT/PRC/CAPS 等；EMEM ch0=1 KiB | 有诊断输出，没有 DMEM 下载或固件明文导出 |
| 570→610 | 新增 MNOC RX FIFO、MNOC packet 客户端、CMS2 日志、更多 GB100 HAL/FRTS/调试功能；NVDM 增加 SEC2 别名与 RM_RPC | 传输和日志扩展，不是 IMEM/DMEM 任意读 |
| 610→615 | 新增 `_kfspGatherDmemLog_GB100`/`_kfspPrintDmemLog_GB100`；新增 `FspBootTimeout`/`FspFuseError` 事件；`kfspSendMessage`/`kfspReadMessage` 从 static 变为驱动内公开；NVDM 增加 `FSP_GSP_RM_METHOD_OF_COMMS=0x23`、`GMCAPI=0x26` | 新增的是日志与通用消息机制，不是 FSP_RUN 明文接口 |

## DMEM logging 的准确边界

615 `kern_fsp_gb100.c` 证实：

- `NV_DEFINED_DOWNLOAD_LOG_COMMAND = 0x06`
- `DMEM_LOG_MAX_BYTES = 4096`
- `DMEM_RESPONSE_TIMEOUT_US = 5000`
- MCTP VDM IANA 请求，sessionId `0xFF`
- 每包最多 52 字节，按 session 顺序读取日志
- 老 FSP 不支持时会忽略请求并超时

610.57 没有该实现。615 GB202 HAL 仍映射到 `kfspDumpDebugState_GB100`。

但现有真机请求已经得到 `RESP: none`，且 CAPS 正控制正常，因此当前卡/当前 FSP 状态不支持或不应答。该接口没有地址参数，只允许下载 FSP 管理的日志，不是任意 DMEM 读取，更不是 IMEM 或 FSP_RUN 导出。

## 头文件与寄存器

- 570/610/615 的 EMEM RM 通道始终为 channel 0、1024 字节，没有新增大容量固件缓冲区。
- 610/615 的 GB100 与 GB202 `dev_fsp_pri.h`、`dev_fsp_addendum.h` 逐字节相同；570→610 主要补充 MNOC RX FIFO。
- 615 的 NVDM 新值属于 GSP-RM/GMC 通信，不是新的 FSP 明文服务。
- 570→610→615 没发现 `FSP_RUN`、plaintext、decrypt-to-host、firmware dump/export 的实现。

## 与现有实测结论的关系

该版本差异不会推翻当前结论：

1. 当前卡的 DMEM log 请求无响应，不能用“615 有实现”代替硬件支持证据。
2. 610/615 的 FSP PRI 头文件相同，自然映射的 IMEMC/DMEMC 全部被过滤的结论没有新地址或新通道可换。
3. 新 DMEM 日志至多用于版本、状态、错误分析；只有拿到实际日志后，才可判断其中是否还有额外研究价值。
4. 如果未来发现新的消息 schema，615 公开的通用 `kfspSendMessage`/`kfspReadMessage` 会降低实现成本，但 schema 本身仍是缺失前提。

## 下一步判据

只有以下新证据才值得重开对应方向：

- 某个 FSP 版本实际响应 DMEM log，并取回真实日志；
- 新 NVDM/VDM schema 明确给出内存或解密映像导出；
- 新工程/debug FSP_RUN、crypto/KDF 消费者或工程内存转储；
- 不同 debug lifecycle 下，IMEMC/DMEMC 读值不再是 `0xBADF5040`。

否则，继续把 570→615 的版本差异解释为 FSP 明文突破口，证据不足。

## 主要证据位置

- 570.144 源码快照：本目录 `570.144/`
- 610.57.04：`/home/user/rt_5090_project/aes610_vm/src/usr/src/nvidia-610.57.04`
- 615.78.08：`/usr/src/nvidia-615.78.08`
- 615 DMEM log：`src/nvidia/src/kernel/gpu/fsp/arch/blackwell/kern_fsp_gb100.c:58-119, 223-284, 313-432`
- 现有实测：`/home/user/rt_5090_project/gsp615_rpc_equiv_20261027/out/fsp_dmem_log_transcript.txt`

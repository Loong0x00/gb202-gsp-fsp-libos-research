# 第二轮：动态 NVDM、FWUP 与 NVCBA2 decrypt-copy（2026-10-29）

## 动态响应与 FWUP

- 对 1,456 个直接 sender 调用同时恢复 `a3`（请求长度）和 `a6`（响应长度）。
- 立即数响应长度只有：`0`、`0x11`、`0x19`；其余为动态长度。**没有任何可静态确认的 >=0x100 响应**。
- `NVDM_TYPE_FIRMWARE_UPDATE=0x12` 的 getter 确实存在并安装：610.57.04 的 `0x015e7b80`，在 `0x019f2a54` 的 HAL/vtable 构造中被引用。故 FWUP 采用间接类型提供路径，不能因直接调用缺少 `0x12` 而判定不存在。
- FWUP 小命令、动态 RPC 和 `0x24` 的已恢复路径仍未显示固件明文回读或大块代码导出。`0x24` 的 17 字节响应与状态/错误处理相符，未出现地址消费。

证据：`fsp_nvdm_calls.json`、`610_fwup_getter_xrefs.log`、`610_fwup_getter_table.log`、`610_dynamic_other_disasm.txt`。

## NVCBA2 decrypt-copy 是实际存在的地址化 crypto 接口，但不是现成的 FSP_RUN oracle

公开 `clcba2.h` 给出了完整方法布局：

- `0x400/0x404`：source address hi/lo；
- `0x408/0x40c`：destination address hi/lo；
- `0x410`：size，最大 2 MiB；
- `0x414/0x418`：auth-tag address hi/lo；
- `0x41c/0x420`：method-stream auth-tag address hi/lo。

相关错误包括 source/destination/auth-tag 地址未对齐、DMA NACK、tag mismatch，以及 `NVCBA2_ERROR_KEY_DERIVATION_FAILURE`。这证明该接口具备“密文地址 → 明文目标地址”的硬件形态，值得作为独立研究线，而不是把 AES0 slot 当作唯一可能路径。

但当前可见 host 使用方式有重要边界：

1. `channelFillSec2Pb` 是带 CCSL/HMAC 的 method-stream/secure-scrub 流程，不是公开的任意密文解密 API。
2. 可见调用主要写 destination、size、method-stream tag 和 semaphore；没有建立一个把 v6/FSP_RUN 描述符喂进去并回传明文的调用链。
3. GSP-RM 内的 NVCBA2 error-name mapper 只覆盖前 14 个错误，未提供 KDF/root-key 配置或 key-source。错误字符串本身不能证明可任意调用。
4. 因此，source/destination 寄存器存在不等于已有可用 oracle；还缺合法 method-stream、KDF/root-key、IV/AAD/tag 与策略验证。

证据：`615_decrypt_copy_xrefs.log`、`615_decrypt_error_table.log`、`615_decrypt_error_mapper_xrefs.log`，以及 `/usr/src/nvidia-615.78.08/src/common/sdk/nvidia/inc/class/clcba2.h` 和 `channel_utils.c`。

## 当前结论

- 新增两条后续研究价值较高的路径：间接 FWUP 类型提供链，以及 NVCBA2 地址化 decrypt-copy/KDF 方法流。
- **仍未取得 FSP_RUN 明文或新的明文地址。** `0x24` 不是内存读接口，NVCBA2 也不能仅凭方法布局就当作可复用解密器。
- 下一步如果只沿高价值证据推进，应恢复 NVCBA2 的真实消费者与 KDF 输入，而不是向 AES 或 NVDM 路径盲目投喂 FSP_RUN。

# 第三轮：NVCBA2 → MODS SecureCopy 调用链（2026-10-29）

## 已恢复的完整路径

在 MODS 570.215 中追到一条真实、地址化的加密/解密 method-stream 路径：

```text
FUN_01a1c5b0                         顶层循环/对象处理
  FUN_01a1bb50                     初始化 crypto object
  FUN_01a1b610                     构造并执行 method stream
    FUN_017ce7a0(..., 0xbad0cafe, ...)
      source      = object + 0x10
      destination = object + 0x4f0
      size        = object + 0x190
      auth tag    = object + 0x670
  FUN_01a1c0d0                     SwDecryptWrapper
    FUN_01a1bc90                   软件 AES-256-GCM candidate
      key         = object + 0x44（32 bytes）
      IV          = 12 bytes
      tag         = 16 bytes
      plaintext  → caller-provided output object
```

这与 NVCBA2 公开布局相符：source/destination/size/auth-tag 地址均存在，且软件路径也有独立 AES-GCM 实现。不是单纯错误字符串或猜测。

## 关键修正与证据边界

- `param_2+0x44` 确实是软件 GCM 使用的 32-byte key，但**不能据此声称已获得 key**。它是 crypto object 的字段，不是公开 v6 descriptor 的已知字段。
- `FUN_01a1bb50`/`FUN_01a1b610` 还负责 method-stream 构造与执行，因此这个 object 同时具有硬件 NVCBA2 和软件 GCM 两条路径。
- 顶层函数 `FUN_01a1c5b0` 在数据表 `0x0946aba0` 注册。该表带有 RTTI 名称：
  `N10JavaScript14GenericDeleterI10SecureCopyEE`，即 JavaScript `GenericDeleter<SecureCopy>`。
- 本地 JS 声明也有 `SecureCopy` 测试，明确其职责是 secure copy 与 memory compare。未找到它消费 `FSP_RUN`、v6 descriptor 或 FSP KDF root 的脚本/调用证据。

证据文件：

- `mods_crypto_keyflow.log`
- `mods_crypto_method_builder.log`
- `mods_crypto_stream_init.log`
- `mods_crypto_pipeline_registration.log`
- `mods_swdecrypt_wrapper_disasm.txt`
- `mods_audit/static/decoded*/gpudecls.*`

## 判定

这是一条真实、可研究的 decrypt-copy 管线，但**不是已经证明可复用的 FSP_RUN oracle**：

1. 它属于 MODS `SecureCopy` 通用测试/内存复制框架，不是已绑定的 FSP_RUN 消费者。
2. 仍有 key-source、method-stream 权限、KDF/root-key、IV/AAD/tag 与目标描述符绑定问题未解决。
3. 不能因为对象中有 key 字段、source/destination 地址和 AES-GCM 实现，就把任意 v6 密文交给它；这会混淆通用 secure-copy 与 FSP 专用解密策略。

目前仍未取得 `FSP_RUN` 明文或可直接回读的地址。若继续，合理目标是恢复 SecureCopy 输入对象的实际 producer 和 key provenance，而不是盲目调用该 API。

## Key provenance 补查

继续检查 `SwDecrypt(KMB)` 和相邻阶段字符串后，确认 KMB（key material buffer）来自 **SecureCopy 输入 crypto object**，不是公开的 v6 `FSP_RUN` descriptor 字段。`SwDecrypt(KMB)` 只是该对象的 debug 输出，不提供 key producer。

SecureCopy 的控制面仅见 `Debug` 与 `MemSizeInBytes`，JS 声明则强调 memory compare。它更像通用加密/解密正确性测试，不是 FSP 专用 KDF 接口。故“从该对象直接拿到 FSP 密钥”的推断不成立；要继续只能追实际输入对象或转向 FSP 内部/工程 debug 消费者。

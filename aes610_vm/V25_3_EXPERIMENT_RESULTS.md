# v25.3 canary results

- The v25.3 LARGE first RPC completed with `fn=1 st=0`, confirming that the recovered continuation path executes.
- Direct write canary to a shared queue VA did not appear in QOUT.
- Synthetic B8 backend read/consume canary did not produce the expected `0x3f`.
- map1 write followed by map2 read did not produce a second useful callback or `sepc=0xdeadbeef`.
- No AES known-answer operation was attempted and no `FSP_RUN` input was used.
- All three task overlays were removed; the immutable base remains mode `0444`.
- Host NVIDIA and GDM were restored (`display=restored`, `gdm.service=active`). The authorized GPU status check succeeds.

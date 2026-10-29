# LACT pre-reset tuning restoration verification

Restored from:

`/home/user/rt_5090_project/lact_backups/20260903-002316-before-full-reset/pre-reset/config.yaml`

- saved/restored config SHA-256: `cc3940dd896843bbb975502ee718d3ec1f762f5a1d8d12a4ae32c3d61459a7d9`
- LACT API config: exact JSON match with the archived pre-reset API response
- legacy GPU offsets: all 0 (the core tuning is a V/F curve, not a global offset)
- memory offsets: +2000 on all exposed performance levels
- live/max MCLK: 15001 MHz
- configured V/F curve: 127/127 points exactly match hardware effective frequency/voltage readback
- V/F points differing from factory-base curve: 59/127
- GPC domain offset: 0 kHz
- XBAR domain offset: +301449 kHz
- SYS domain offset: +145797 kHz
- NVD domain offset: 0 kHz
- all domain voltage/MSVDD offsets: 0 uV
- GPC-to-XBAR ratio: 60723
- voltage boost: 0
- current/default power cap: 600/600 W
- fan control: disabled
- lactd: active after restart
- GPU Recovery Action: None
- PCIe Replays Since Reset: 0
- kernel NVIDIA event file: empty (no Xid, NVRM assertion, gpu_vaspace or intermap event)

The restore was performed only after the Wuthering Waves process had exited and GPU load had fallen to approximately 3% / 42 W.

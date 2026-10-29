# sm_120 SASS SR selector catalog (0x00–0xff)

This table combines ptxas-produced legal samples with an offline-only nvdisasm selector sweep. `inferred-name-only` means the name was decoded but the selector was never executed. `inferred-pair/name-only` likewise marks an odd PM high-half name: legal `%pmN_64` encodes the adjacent even selector plus CS2R bit 80, not the odd selector directly. Numeric `SR<n>` entries are fully unknown.

| Index | nvdisasm name | Category | Legal/observed emitter | Trigger | Semantics | Confidence |
|---:|---|---|---|---|---|---|
| `0x00` | `SR_LANEID` | other decoder-named | S2R | `%laneid` | lane index in the warp | **verified** |
| `0x01` | `SR_CLOCK` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x02` | `SR_VIRTCFG` | other decoder-named | S2R | `%nwarpid` | packed virtual-warp configuration; ptxas extracts %nwarpid | **verified-lowering** |
| `0x03` | `SR_VIRTID` | other decoder-named | S2R | `%warpid` | packed virtual warp id; ptxas extracts %warpid | **verified-lowering** |
| `0x04` | `SR4` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x05` | `SR5` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x06` | `SR6` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x07` | `SR7` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x08` | `SR8` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x09` | `SR9` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x0a` | `SR10` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x0b` | `SR11` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x0c` | `SR12` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x0d` | `SR13` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x0e` | `SR14` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x0f` | `SR_ORDERING_TICKET` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x10` | `SR_PRIM_TYPE` | graphics/primitive | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x11` | `SR_INVOCATION_ID` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x12` | `SR_Y_DIRECTION` | graphics/primitive | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x13` | `SR_THREAD_KILL` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x14` | `SM_SHADER_TYPE` | graphics/primitive | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x15` | `SR_DIRECTCBEWRITEADDRESSLOW` | graphics/primitive | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x16` | `SR_DIRECTCBEWRITEADDRESSHIGH` | graphics/primitive | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x17` | `SR_DIRECTCBEWRITEENABLED` | graphics/primitive | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x18` | `SR_SW_SCRATCH` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x19` | `SR_MACHINE_ID_1` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x1a` | `SR_MACHINE_ID_2` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x1b` | `SR_MACHINE_ID_3` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x1c` | `SR_AFFINITY` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x1d` | `SR_INVOCATION_INFO` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x1e` | `SR_WSCALEFACTOR_XY` | graphics/primitive | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x1f` | `SR_WSCALEFACTOR_Z` | graphics/primitive | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x20` | `SR_TID` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x21` | `SR_TID.X` | other decoder-named | S2R | `%tid.x` | thread x index within CTA | **verified** |
| `0x22` | `SR_TID.Y` | other decoder-named | S2R | `%tid.y` | thread y index within CTA | **verified** |
| `0x23` | `SR_TID.Z` | other decoder-named | S2R | `%tid.z` | thread z index within CTA | **verified** |
| `0x24` | `SR36` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x25` | `SR_CTAID.X` | other decoder-named | S2R | `%ctaid.x` | CTA x index | **verified** |
| `0x26` | `SR_CTAID.Y` | other decoder-named | S2R | `%ctaid.y` | CTA y index | **verified** |
| `0x27` | `SR_CTAID.Z` | other decoder-named | S2R | `%ctaid.z` | CTA z index | **verified** |
| `0x28` | `SR_NTID` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x29` | `SR_CirQueueIncrMinusOne` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x2a` | `SR_NLATC` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x2b` | `SR43` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x2c` | `SR_SM_SPA_VERSION` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x2d` | `SR_MULTIPASSSHADERINFO` | graphics/primitive | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x2e` | `SR_LWINHI` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x2f` | `SR_SWINHI` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x30` | `SR_SWINLO` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x31` | `SR_SWINSZ` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x32` | `SR_SMEMSZ` | resource/allocation | S2R | `%total_smem_size` | CTA total shared-memory allocation | **verified** |
| `0x33` | `SR_SMEMBANKS` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x34` | `SR_LWINLO` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x35` | `SR_LWINSZ` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x36` | `SR_LMEMLOSZ` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x37` | `SR_LMEMHIOFF` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x38` | `SR_EQMASK` | other decoder-named | S2R | `%lanemask_eq` | mask containing the current lane | **verified** |
| `0x39` | `SR_LTMASK` | other decoder-named | S2R | `%lanemask_lt` | lanes lower than the current lane | **verified** |
| `0x3a` | `SR_LEMASK` | other decoder-named | S2R | `%lanemask_le` | lanes <= current lane | **verified** |
| `0x3b` | `SR_GTMASK` | other decoder-named | S2R | `%lanemask_gt` | lanes greater than the current lane | **verified** |
| `0x3c` | `SR_GEMASK` | other decoder-named | S2R | `%lanemask_ge` | lanes >= current lane | **verified** |
| `0x3d` | `SR_REGALLOC` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x3e` | `SR_BARRIERALLOC` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x3f` | `SR63` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x40` | `SR_GLOBALERRORSTATUS` | error/debug | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x41` | `SR_CGAERRORSTATUS` | error/debug | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x42` | `SR_WARPERRORSTATUS` | error/debug | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x43` | `SR_VIRTUALSMID` | scheduler/execution | S2R | `%smid` | virtual SM identifier used by PTX %smid | **verified** |
| `0x44` | `SR_VIRTUALENGINEID` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x45` | `SR69` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x46` | `SR70` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x47` | `SR71` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x48` | `SR72` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x49` | `SR73` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x4a` | `SR74` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x4b` | `SR75` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x4c` | `SR76` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x4d` | `SR77` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x4e` | `SR78` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x4f` | `SR79` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x50` | `SR_CLOCKLO` | other decoder-named | CS2R.32 / CS2R | `%clock / %clock64` | clock low half; 64-bit form reads the low/high pair | **verified** |
| `0x51` | `SR_CLOCKHI` | other decoder-named | CS2R.32 / pair | `%clock_hi / %clock64` | clock high half | **verified** |
| `0x52` | `SR_GLOBALTIMERLO` | other decoder-named | CS2R.32 / CS2R | `%globaltimer_lo / %globaltimer` | global timer low half; 64-bit form reads the pair | **verified** |
| `0x53` | `SR_GLOBALTIMERHI` | other decoder-named | CS2R.32 / pair | `%globaltimer_hi / %globaltimer` | global timer high half | **verified** |
| `0x54` | `SR_ESR_PC` | error/debug | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x55` | `SR_ESR_PC_HI` | error/debug | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x56` | `SR86` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x57` | `SR87` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x58` | `SR88` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x59` | `SR89` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x5a` | `SR90` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x5b` | `SR91` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x5c` | `SR92` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x5d` | `SR93` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x5e` | `SR94` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x5f` | `SR95` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x60` | `SR_HWTASKID` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x61` | `SR_CIRCULARQUEUEENTRYINDEX` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x62` | `SR_CIRCULARQUEUEENTRYADDRESSLOW` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x63` | `SR_CIRCULARQUEUEENTRYADDRESSHIGH` | scheduler/execution | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x64` | `SR_PM0` | perfmon | CS2R.32 / CS2R | `%pm0 / %pm0_64` | performance-monitor counter 0 low half; public behavior is undefined | **verified-encoding/unknown-counter-event** |
| `0x65` | `SR_PM_HI0` | perfmon | offline decoder / pair inference | `%pm0_64 starts at even selector 0x64` | decoder names this as performance-monitor counter 0 high half; inferred from the adjacent legal 64-bit pair | **inferred-pair/name-only** |
| `0x66` | `SR_PM1` | perfmon | CS2R.32 / CS2R | `%pm1 / %pm1_64` | performance-monitor counter 1 low half; public behavior is undefined | **verified-encoding/unknown-counter-event** |
| `0x67` | `SR_PM_HI1` | perfmon | offline decoder / pair inference | `%pm1_64 starts at even selector 0x66` | decoder names this as performance-monitor counter 1 high half; inferred from the adjacent legal 64-bit pair | **inferred-pair/name-only** |
| `0x68` | `SR_PM2` | perfmon | CS2R.32 / CS2R | `%pm2 / %pm2_64` | performance-monitor counter 2 low half; public behavior is undefined | **verified-encoding/unknown-counter-event** |
| `0x69` | `SR_PM_HI2` | perfmon | offline decoder / pair inference | `%pm2_64 starts at even selector 0x68` | decoder names this as performance-monitor counter 2 high half; inferred from the adjacent legal 64-bit pair | **inferred-pair/name-only** |
| `0x6a` | `SR_PM3` | perfmon | CS2R.32 / CS2R | `%pm3 / %pm3_64` | performance-monitor counter 3 low half; public behavior is undefined | **verified-encoding/unknown-counter-event** |
| `0x6b` | `SR_PM_HI3` | perfmon | offline decoder / pair inference | `%pm3_64 starts at even selector 0x6a` | decoder names this as performance-monitor counter 3 high half; inferred from the adjacent legal 64-bit pair | **inferred-pair/name-only** |
| `0x6c` | `SR_PM4` | perfmon | CS2R.32 / CS2R | `%pm4 / %pm4_64` | performance-monitor counter 4 low half; public behavior is undefined | **verified-encoding/unknown-counter-event** |
| `0x6d` | `SR_PM_HI4` | perfmon | offline decoder / pair inference | `%pm4_64 starts at even selector 0x6c` | decoder names this as performance-monitor counter 4 high half; inferred from the adjacent legal 64-bit pair | **inferred-pair/name-only** |
| `0x6e` | `SR_PM5` | perfmon | CS2R.32 / CS2R | `%pm5 / %pm5_64` | performance-monitor counter 5 low half; public behavior is undefined | **verified-encoding/unknown-counter-event** |
| `0x6f` | `SR_PM_HI5` | perfmon | offline decoder / pair inference | `%pm5_64 starts at even selector 0x6e` | decoder names this as performance-monitor counter 5 high half; inferred from the adjacent legal 64-bit pair | **inferred-pair/name-only** |
| `0x70` | `SR_PM6` | perfmon | CS2R.32 / CS2R | `%pm6 / %pm6_64` | performance-monitor counter 6 low half; public behavior is undefined | **verified-encoding/unknown-counter-event** |
| `0x71` | `SR_PM_HI6` | perfmon | offline decoder / pair inference | `%pm6_64 starts at even selector 0x70` | decoder names this as performance-monitor counter 6 high half; inferred from the adjacent legal 64-bit pair | **inferred-pair/name-only** |
| `0x72` | `SR_PM7` | perfmon | CS2R.32 / CS2R | `%pm7 / %pm7_64` | performance-monitor counter 7 low half; public behavior is undefined | **verified-encoding/unknown-counter-event** |
| `0x73` | `SR_PM_HI7` | perfmon | offline decoder / pair inference | `%pm7_64 starts at even selector 0x72` | decoder names this as performance-monitor counter 7 high half; inferred from the adjacent legal 64-bit pair | **inferred-pair/name-only** |
| `0x74` | `SR_SNAP_PM0` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x75` | `SR_SNAP_PM_HI0` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x76` | `SR_SNAP_PM1` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x77` | `SR_SNAP_PM_HI1` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x78` | `SR_SNAP_PM2` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x79` | `SR_SNAP_PM_HI2` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x7a` | `SR_SNAP_PM3` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x7b` | `SR_SNAP_PM_HI3` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x7c` | `SR_SNAP_PM4` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x7d` | `SR_SNAP_PM_HI4` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x7e` | `SR_SNAP_PM5` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x7f` | `SR_SNAP_PM_HI5` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x80` | `SR_SNAP_PM6` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x81` | `SR_SNAP_PM_HI6` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x82` | `SR_SNAP_PM7` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x83` | `SR_SNAP_PM_HI7` | perfmon | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x84` | `SR_VARIABLE_RATE` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x85` | `__HIR0X000` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x86` | `SR134` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x87` | `SR135` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x88` | `SR_CgaCtaId` | other decoder-named | S2R | `%cluster_ctarank` | CTA rank within cluster | **verified** |
| `0x89` | `SR_GpcLocalCgaId` | other decoder-named | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x8a` | `SR_CgaSize` | other decoder-named | CS2R.32 | `cluster-derived PTX values` | raw CGA-size/config selector used before ptxas table lookup | **verified-lowering** |
| `0x8b` | `SR_CTARegPoolSz` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x8c` | `SR140` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x8d` | `SR_TMemSz` | resource/allocation | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x8e` | `SR_CONTEXT_SAVE_ADDR_LO` | error/debug | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x8f` | `SR_CONTEXT_SAVE_ADDR_HI` | error/debug | offline decoder only | `none found` | nvdisasm name is the only semantic clue; runtime meaning unverified | **inferred-name-only** |
| `0x90` | `SR144` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x91` | `SR145` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x92` | `SR146` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x93` | `SR147` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x94` | `SR148` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x95` | `SR149` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x96` | `SR150` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x97` | `SR151` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x98` | `SR152` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x99` | `SR153` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x9a` | `SR154` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x9b` | `SR155` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x9c` | `SR156` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x9d` | `SR157` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x9e` | `SR158` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0x9f` | `SR159` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa0` | `SR160` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa1` | `SR161` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa2` | `SR162` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa3` | `SR163` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa4` | `SR164` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa5` | `SR165` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa6` | `SR166` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa7` | `SR167` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa8` | `SR168` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xa9` | `SR169` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xaa` | `SR170` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xab` | `SR171` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xac` | `SR172` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xad` | `SR173` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xae` | `SR174` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xaf` | `SR175` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb0` | `SR176` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb1` | `SR177` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb2` | `SR178` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb3` | `SR179` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb4` | `SR180` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb5` | `SR181` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb6` | `SR182` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb7` | `SR183` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb8` | `SR184` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xb9` | `SR185` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xba` | `SR186` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xbb` | `SR187` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xbc` | `SR188` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xbd` | `SR189` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xbe` | `SR190` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xbf` | `SR191` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc0` | `SR192` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc1` | `SR193` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc2` | `SR194` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc3` | `SR195` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc4` | `SR196` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc5` | `SR197` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc6` | `SR198` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc7` | `SR199` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc8` | `SR200` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xc9` | `SR201` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xca` | `SR202` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xcb` | `SR203` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xcc` | `SR204` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xcd` | `SR205` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xce` | `SR206` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xcf` | `SR207` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd0` | `SR208` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd1` | `SR209` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd2` | `SR210` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd3` | `SR211` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd4` | `SR212` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd5` | `SR213` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd6` | `SR214` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd7` | `SR215` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd8` | `SR216` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xd9` | `SR217` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xda` | `SR218` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xdb` | `SR219` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xdc` | `SR220` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xdd` | `SR221` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xde` | `SR222` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xdf` | `SR223` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe0` | `SR224` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe1` | `SR225` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe2` | `SR226` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe3` | `SR227` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe4` | `SR228` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe5` | `SR229` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe6` | `SR230` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe7` | `SR231` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe8` | `SR232` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xe9` | `SR233` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xea` | `SR234` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xeb` | `SR235` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xec` | `SR236` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xed` | `SR237` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xee` | `SR238` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xef` | `SR239` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf0` | `SR240` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf1` | `SR241` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf2` | `SR242` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf3` | `SR243` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf4` | `SR244` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf5` | `SR245` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf6` | `SR246` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf7` | `SR247` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf8` | `SR248` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xf9` | `SR249` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xfa` | `SR250` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xfb` | `SR251` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xfc` | `SR252` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xfd` | `SR253` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xfe` | `SR254` | unnamed | offline decoder only | `none found` | unknown | **unknown** |
| `0xff` | `SRZ` | constant | CS2R in OptiX JIT | `none (SRZ)` | zero special-register selector | **verified-jit** |

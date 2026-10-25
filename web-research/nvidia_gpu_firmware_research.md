# NVIDIA GPU firmware recovery research

**Scope/method.** Web searches covered NVIDIA documentation, NVIDIA open-kernel-module/DCGM repositories and issues, TechPowerUp, Reddit, and Overclock.net for the seven requested phrases and variants. Public search results can miss deleted, login-gated, or unindexed posts. Dates are included only where visible from the cited source; most returned source pages did not expose a date in search results. “Not found” below means not found in this search, not proof of nonexistence.

## 1. RTX 5090 FSP security-processor recovery

**Found**
- NVIDIA’s [GPU Operational Event Catalog](https://docs.nvidia.com/deploy/gpu-operational-events/event-catalog.html) describes FSP boot timeout/fuse-related operational errors as GPU initialization faults. It does not provide a consumer RTX 5090 FSP repair procedure.
- An [NVIDIA Developer Forum report concerning RTX 5090 GSP initialization](https://forums.developer.nvidia.com/t/rtx-5090-on-ubuntu-24-04-gsp-initialization-fails/381318) was returned. This concerns GSP initialization and should not be conflated with a documented FSP corruption repair.
- Search results include user reports of FSP-related errors, including [a ZOTAC RTX 5090 Reddit thread](https://www.reddit.com/r/ZOTAC/comments/1tyfmap/rtx_5090_amp_extreme_fecs_ucode_fatal_error_fsp/). User reports are anecdotal, not an authoritative recovery solution.

**Not found / conclusion**
- No public, NVIDIA-supported user tool or procedure specifically to repair a corrupted RTX 5090 FSP state was found.
- **Solution exists?** No documented end-user FSP-state repair found. A persistent FSP initialization error warrants card/vendor support or RMA; distinguish it from driver/GSP startup errors using the exact event/Xid logs.

## 2. NVIDIA GPU InfoROM corruption recovery

**Found**
- NVIDIA GPU Operator troubleshooting says `nvidia-smi` InfoROM-corruption error (return code 14) is a GPU fault and recommends replacing the GPU: [GPU Operator troubleshooting](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/25.3.1/troubleshooting.html).
- NVIDIA’s [DCGM issue #2](https://github.com/NVIDIA/DCGM/issues/2) discusses an InfoROM corruption report and mentions `nvflash --recoverinforom` as a possible attempt. This is an issue discussion, not a guarantee or universal supported process.
- NVIDIA XID documentation distinguishes **Xid 93**, an InfoROM wear-limit case, and documents `nvflash --elsessionclear` for that specific condition: [XID error documentation](https://docs.nvidia.com/deploy/xid-errors/archive/index.html). Do not treat that as generic corruption repair.
- An OEM-specific HPE procedure, [GPU - InfoROM Recovery](https://support.hpe.com/hpesc/public/docDisplay?docId=sf000073504en_us&docLocale=en_US&page=index.html), uses model/platform-specific tooling. It does not establish a generally applicable RTX 5090 method.
- An older [NVIDIA Developer Forum InfoROM discussion](https://forums.developer.nvidia.com/t/inforom-is-corrupted-at-gpu/74277/2) and Reddit discussions ([r/homelab: 11xxei0](https://www.reddit.com/r/homelab/comments/11xxei0), [r/homelab: w7sb1l](https://www.reddit.com/r/homelab/comments/w7sb1l)) also surfaced; their context is older hardware and not proof of RTX 5090 compatibility.

**Not found / conclusion**
- No universal, NVIDIA-supported repair procedure for GeForce/RTX 5090 InfoROM corruption found. **Possible limited solution:** the recovery option is discussed for supported cases, and OEM recovery exists on some platforms; applicability is model-specific. NVIDIA’s general operator guidance is replacement/RMA.

## 3. PRC (Product Reconfiguration Control) and eFuses

**Found**
- A Linux kernel RFC describes PRC as **Product Reconfiguration Control** (not “Platform Reconfiguration Control”) and documents a protocol for device configuration. Source: [RFC v2 PRC/FSP protocol documentation](https://www.spinics.net/lists/kernel/msg6096917.html), also mirrored on [Patchew](https://patchew.org/linux/20260604114339.1565660-1-zhiw%40nvidia.com/20260604114339.1565660-5-zhiw%40nvidia.com/).
- NVIDIA’s [gpu-admin-tools repository](https://github.com/NVIDIA/gpu-admin-tools) includes GPU administration utilities with PRC-related query functionality; search results also returned an overview of [GPU/NVSwitch operations](https://deepwiki.com/NVIDIA/gpu-admin-tools/3.3-gpu-and-nvswitch-operations).
- Search results describe PRC as configuration “knobs” (e.g. vGPU/ECC/security-related configuration), distinct from a conventional firmware image update. The publicly surfaced sources do **not** specify persistence/storage for every writable PRC object.
- NVIDIA documentation on fuse burning exists for other product families (e.g. DRIVE [Fuse Burning Responsibilities](https://developer.nvidia.com/docs/drive/drive-os/archives/6.0.4/linux/sdk/common/topics/security_concepts/FuseBurningResponsibilities20.html)); it does not answer the storage semantics of GeForce PRC objects.

**Not found / conclusion**
- No authoritative public source found confirming that writes to the queried PRC objects program eFuses, nor one that guarantees all PRC writes are flash-only. A broad claim either way is unsupported by these results. **Solution/answer exists?** Unresolved from public sources; object- and platform-specific documentation is needed. Do not infer irreversibility or flash-only persistence from the acronym/protocol alone.

## 4. Public full RTX 5090 4 MB SPI dump including InfoROM

**Found**
- TechPowerUp’s [VGA BIOS collection](https://www.techpowerup.com/vgabios/) contains RTX 5090 VBIOS entries; one returned [Gainward RTX 5090 entry](https://www.techpowerup.com/vgabios/275355/275355) is a VBIOS image, not evidence of a whole-chip SPI dump.
- Board vendors provide model-specific downloads, e.g. [ASUS ROG Astral RTX 5090 support](https://rog.asus.com/graphics-cards/graphics-cards/rog-astral/rog-astral-rtx5090-32g-gaming/helpdesk_bios/). These are not necessarily full SPI images.
- Search results included Reddit requests/discussion about specific RTX 5090 VBIOS files, not a verifiable complete 4 MB SPI image with InfoROM region.

**Not found / conclusion**
- No publicly shared, verified full **4 MB** RTX 5090 SPI dump including the InfoROM region was found. **Solution exists?** No verified public full dump identified. A VBIOS collection entry must not be represented as a whole-flash dump; images and board-specific data may differ by board/revision.

## 5. GPU reportedly bricked after PRC write

**Found**
- Search for the exact “NVIDIA GPU bricked after PRC write” phrasing did not surface a clearly matching incident. Results included the PRC kernel RFC, NVIDIA admin tooling, and unrelated firmware-brick discussions.
- An [NVIDIA open kernel module file for Hopper](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/main/src/nvidia/src/kernel/gpu/arch/hopper/kern_gpu_gh100.c) appeared in results but is not evidence of a PRC-caused brick.

**Not found / conclusion**
- No independently verifiable report was found in the searched Overclock.net, TechPowerUp, r/nvidia, or GitHub results of a GPU bricked specifically by writing PRC objects. **Solution exists?** No incident-specific recovery solution found. This is an absence of indexed evidence, not proof that no such event has occurred.

## 6. `nvflash --entire` and corrupted-flash recovery

**Found**
- Search results surfaced an HPE [InfoROM recovery procedure](https://support.hpe.com/hpesc/public/docDisplay?docId=sf000073504en_us&docLocale=en_US&page=index.html) associated with platform-specific NVFlash use, including full/recovery operations for a supported system. It is not general GeForce guidance.
- TechPowerUp forum search results included general NVFlash threads such as [GPU brick after virus?](https://www.techpowerup.com/forums/threads/gpu-brick-after-virus.291618/) and [NVFlash error](https://www.techpowerup.com/forums/threads/nvflash-error.245614/), but none established `--entire` as a universal recovery method.
- NVIDIA DCGM discussions concern the separate `--recoverinforom` operation; that is not synonymous with `--entire`.

**Not found / conclusion**
- No authoritative support for using `nvflash --entire` as a generic recovery command for corrupted RTX 5090 SPI flash was found. **Solution exists?** Not as a universal method. It may be appropriate only in an explicitly documented, exact-model OEM workflow; broad full-flash operations carry risk and should not be attempted based on a forum analogy.

## 7. WPR2 storage and reset

**Found**
- NVIDIA open driver source contains GSP/WPR2 handling, including [kernel_gsp.c](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/main/src/nvidia/src/kernel/gpu/gsp/kernel_gsp.c). Search results surfaced error handling around an already-active WPR2 region.
- A Linux kernel mailing-list/Patchew patch discusses WPR2 in the GSP/FSP boot process: [nova-core documentation patch](https://patchew.org/linux/20250423225405.139613-1-joelagnelf%40nvidia.com/20250423225405.139613-4-joelagnelf%40nvidia.com/).
- NVIDIA’s [nvidia-smi documentation](https://docs.nvidia.com/deploy/nvidia-smi/) describes GPU reset functionality subject to device/platform support and restrictions. A reset is not an eFuse programming operation.
- A community project discusses Blackwell Xid/WPR2/GSP crash recovery: [blackwell-xid-wpr2-gsp-crash-recovery](https://github.com/gengchaogit/blackwell-xid-wpr2-gsp-crash-recovery). Treat it as unofficial and hardware/driver-specific. Search also surfaced [NVIDIA open kernel module issue #1080](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1080), which concerns GPU/GSP failures but does not establish a universal WPR2 reset.

**Not found / conclusion**
- No evidence that WPR2 is a dedicated SPI-flash or eFuse setting that can be reset by flashing. The sources place WPR2 in the GPU’s protected GSP boot/memory-region context, not as a VBIOS image field. Exact implementation is architecture-specific.
- **Can it be reset?** A GPU/hardware reset or full host power removal can clear some stuck states, but reports and source do not guarantee recovery in all cases. No public universal “reset WPR2” tool/procedure was established. Do not attempt eFuse or full-flash operations as a WPR2 remedy.

## Overall assessment

The strongest public, actionable material is about conventional InfoROM error handling (NVIDIA recommends replacement in its GPU Operator troubleshooting guide; a recovery option is discussed but not guaranteed) and about WPR2 as part of GSP initialization rather than an eFuse/flash flag. For RTX 5090-specific FSP repair, PRC-write persistence, PRC-caused bricking, and a full 4 MB SPI donor dump, the search found no authoritative public solution or confirmed report. Vendor service is the defensible path for persistent FSP/InfoROM faults.

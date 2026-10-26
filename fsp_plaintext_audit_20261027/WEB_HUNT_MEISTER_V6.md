# Public web hunt: Mats Mods by Meister V6_Final

Date: 2026-10-27

## Source and provenance

A public EletrônicaBR discussion states that a bootable MATS/MODS image was shared for boards through RTX 5090. The page hides external links from guests, but exact-filename search exposed the public Google Drive folder:

- Forum: `https://eletronicabr.com/en/topic/403187-test-programs-for-vram-nvidiaamd-matsmods-and-tserver/`
- Drive folder: `https://drive.google.com/drive/folders/1ICDJ7BKhdtmGNfjdIPAd1RwKgJZmexxu`
- Drive file ID: `1yFJnSfezX3NHmMVMaE8mr-2u3XG9ECv2`
- Filename: `Mats Mods by Meister V6_Final.7z`
- HTTP content length: 22,378,300,632 bytes
- Drive-visible size: 20.84 GB

No purchase, login bypass or forum registration was used. The complete archive was not downloaded.

## Remote 7z inspection

The public Drive endpoint supports byte ranges. The 32-byte 7z signature header and 138-byte next header were fetched and CRC-checked.

7z metadata:

- physical size: 22,378,300,632 bytes
- method: `LZMA2:26`
- solid: no; one block
- contained file: `Mats Mods by Meister V6_Final.img`
- uncompressed size: 61,991,813,120 bytes
- modified: 2026-07-30 23:24:49.7236649
- file CRC-32: `945A004A`
- encrypted: no

The first 64 MiB of the packed stream were range-fetched and decoded as raw LZMA2, yielding a 256 MiB image prefix. This was sufficient to inspect the primary GPT and current Btrfs metadata without retrieving the 22 GB archive.

Image layout:

- GPT total sectors: 121,077,760
- partition 1: 60 MiB EFI System Partition
- partition 2: 61,926,801,408-byte Btrfs filesystem, label `root`
- Btrfs FSID: `5dd94c65-5813-463a-a2ee-4314af85d34b`
- Btrfs generation: 511

The current FS tree contains 12,268 paths. The full reconstructed path inventory is:

- `web_hunt_meister_v6/filesystem_paths.tsv`
- `web_hunt_meister_v6/filesystem_inventory.json`

## RTX 50-series contents

Top-level `/home/RTX5XXX` packages:

- `540.263_5060`
- `570.133_5080`
- `570.151_5090`
- `570.215_5070`
- `570.215_5080`
- `570.278_5050`

The `570.151_5090` directory has the same principal sizes as the already-held local package:

- `mods`: 392,339,552 bytes
- `gldGB202.bin`: 1,081,608 bytes
- `frb_ga100.bin`: 4,792 bytes
- `fub_ga100.bin`: 5,332 bytes
- `driver.tgz`: 81,908 bytes

Other RTX5XXX directories likewise contain only the familiar legacy `frb_ga100.bin`, `fub_ga100.bin` and `fuseread_*` files alongside their MODS executables.

## Related public mirrors

### VLab MEGA folder

The public VLab link `https://mega.nz/folder/qSBkHabQ#Tr01gbXF9K9uP66FhQzKVg` was opened in a fresh browser profile. Its live decrypted listing contains:

- `570.133 GB203 - 5080.zip` — 894.9 MB
- `570.151 GB202 - 5090.zip` — 900 MB
- `570.215 GB203 - 5080.zip` — 902.3 MB
- `570.278 - GB207 RTX5050.zip` — 895.8 MB
- five MODS 520 archives, `Mods 520.iso`, and an NVMT folder

It contains no MODS 580, target FieldDiag archive, or file named `fuserework*`. The GB202/5090 entry is another copy of the already-held 570.151 package class.

### `The Lord Of The GPU` Google Drive folder

The public folder `https://drive.google.com/drive/folders/1wX9DXyTXGD1HIuJJkwDhvP2L3kxJxa6k` exposes several large images. The 31.62 GB `3.rar` was range-inspected without downloading it. Its RAR5 QuickOpen metadata shows exactly one encrypted file:

- `3.pmf`
- uncompressed size 34,618,533,931 bytes
- packed size 33,954,247,888 bytes
- modified 2021-07-07
- encrypted RAR5 stream

This is an old PMF disk image, not a visible Blackwell FieldDiag/FuseRework archive. `OVERKILL2.vhdx` is 7.25 GB but its Drive download currently returns `Quota exceeded`; there is no public member listing or positive target filename evidence, so no copy/download workaround was attempted.

## Target-file result

The complete current Btrfs path inventory contains no member named or containing:

- `fuserework.bin`
- `fuserework_debug_gfw_hash.bin`
- `fuserework_debug_gfw_pub_key.bin`
- `fuserework_debug_gfw_sig.bin`
- Blackwell x86 FieldDiag `629-INT27-DIAG-008`
- MODS 580 standalone package

The image is therefore a useful public mirror/index of common RTX 50-series MODS packages, but it does not provide the missing FuseRework four-file bundle. Downloading/decompressing the remaining ~22 GB would duplicate already-held packages for the current goal, so it was intentionally avoided.

## Local evidence

Directory:

`fsp-offline-crypto-audit-MYwexsWH/web_hunt_meister_v6/`

Key files:

- `header32.bin`
- `next_header.bin`
- `7z_list.txt`
- `image_prefix.bin`
- `root_partition_prefix.bin`
- `fs_tree.txt`
- `filesystem_paths.tsv`
- `filesystem_inventory.json`
- `filesystem_target_hits.txt`

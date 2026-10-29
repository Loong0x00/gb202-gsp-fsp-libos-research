# LACT full GPU configuration reset — 2026-09-03

## Backup

Backup directory:

`/home/user/rt_5090_project/lact_backups/20260903-002316-before-full-reset`

The backup preserves:

- the complete `/etc/lact` tree;
- the installed `lactd.service` unit and all active/disabled drop-ins;
- both historical post-start hook scripts;
- the exact installed `/usr/bin/lact` executable;
- the active pre-reset `config.yaml` as a separate file;
- raw LACT API responses, NVIDIA state, service state, package metadata, source commits, and the local source diff.

The archives passed `gzip -t`, `tar -t`, and the hashes in `SHA256SUMS`. The pre-reset active config and saved copy both had SHA-256:

`cc3940dd896843bbb975502ee718d3ec1f762f5a1d8d12a4ae32c3d61459a7d9`

`restore-current-config.sh` restores only the active pre-reset config and restarts `lactd`; it does not silently replace the installed executable or systemd configuration.

## Reset method

The daemon's native `rest_config` request was used. In this build it executes `Handler::cleanup()`, which resets NVIDIA legacy clock offsets, locked clocks, the V/F curve, voltage boost, and restores the complete preimages of the active contract-bound Blackwell domain/VF/propagation transaction. It then clears all GPU entries and profiles and saves the configuration.

Daemon response:

```json
{"status":"ok","data":null}
```

The daemon was restarted once afterward to prove that the saved empty/default GPU configuration does not reapply the old tuning.

## Before / after

| Item | Before | After restart |
|---|---:|---:|
| GPU config entry | present | absent (`get_gpu_config = null`) |
| Profiles | none | none |
| Legacy GPU offsets | all 0 | all 0 |
| Legacy memory offsets | +2000 | all 0 |
| V/F points differing from base | 59 / 127 | 0 / 127 |
| VRAM clock | 15001 MHz | 14001 MHz |
| GPU reported max clock | 3090 MHz | 3135 MHz |
| XBAR control offset | +301449 kHz | 0 kHz |
| SYS control offset | +145797 kHz | 0 kHz |
| NVD control offset | 0 kHz | 0 kHz |
| Per-point Blackwell control offsets | 0 | 0 |
| Blackwell MSVDD control offsets | 0 uV | 0 uV |
| GPC→XBAR ratio | 60723 (0.926559) | 58976 (0.899902, restored preimage) |
| Voltage boost | 0 | 0 |
| Power limit | 600 W | 600 W (VBIOS default is also 600 W) |
| Fan control | disabled | disabled |
| PowerMizer | configured Auto | no override; live hardware default reported Adaptive |

The post-reset config is:

```yaml
version: 6
daemon:
  log_level: info
  admin_group: wheel
  disable_clocks_cleanup: false
apply_settings_timer: 5
current_profile: null
auto_switch_profiles: false
```

The reported `factory_clock_offset_khz = 45000` on GPC/XBAR remains part of the board's factory VBIOS state; the corresponding user/control offsets are zero.

## Health checks

- `lactd.service`: active after restart.
- GPU Recovery Action: `None`.
- PCIe replays since reset: `0`.
- No new `NVRM`, Xid, `nvAssert`, `gpu_vaspace`, or `intermap` event was found in the kernel journal for the reset interval.
- Current L2 capability query remains read-only and reports 96 MiB total L2, 60 MiB maximum persisting set-aside, and a 128 MiB maximum access-policy window.

Primary post-reset evidence is in `post-reset-api.json`, `post-reset-config.yaml`, `post-reset-nvidia-smi-q.txt`, `post-reset-nvidia-smi-query.csv`, and `post-reset-lactd-journal.txt`.

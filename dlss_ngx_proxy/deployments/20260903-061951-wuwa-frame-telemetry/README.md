# Wuthering Waves frame-telemetry Router deployment

Deployed while `Client-Win64-Shipping.exe` was not running.

- Previous Router SHA-256: `6c258f3c032e27252d2ff9ef5e0eeed0e48369c69589bbb51890e6728f35254c`
- Final telemetry Router SHA-256: `65be255fc529f18c7751666360f4748a743198f21fa7d17f3a757a295ec043ad`
- Installed path: `/home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/00-dlss-ngx-router.addon64`
- New output: `dlss-ngx-frames.jsonl`
- Correlator: `/home/user/rt_5090_project/dlss_ngx_proxy/tools/correlate_obs_dlss.py`

The original signed Evaluate return value remains authoritative. Post-service
failure, absence, or bypass is reported but does not replace it.

Rollback (game must be exited):

```bash
/home/user/rt_5090_project/dlss_ngx_proxy/deployments/20260903-061951-wuwa-frame-telemetry/restore.sh
```

Compilation succeeded. Live creation and per-frame JSON validation remain to be
performed on the next game launch.

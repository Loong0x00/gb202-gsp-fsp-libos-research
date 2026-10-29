# DLSS 5 release-source audit — 2026-09-04 12:43 CST

## Official NVIDIA driver

Downloaded from NVIDIA's official CDN:

`https://us.download.nvidia.com/Windows/616.64/616.64-desktop-win10-win11-64bit-international-dch-whql.exe`

- HTTP content length: 984,282,848 bytes
- HTTP last-modified: 2026-09-04 04:18:32 GMT
- SHA-256: `36584e5df1dc048df5c677e9591295b96b870e7a6a0ad1461457b89de8bc1b37`
- Complete 7-Zip member inventory: `driver-file-list.txt`
- NGX-related members: `driver-ngx-paths.txt`
- Result: the package does **not** contain `nvngx_dlssnr.dll`. It contains the driver NGX core/updater and `nvngx_dlssg.dll`; therefore the official driver is not a source for comparing the DLSSNR game runtime.
- The 939 MiB installer was deleted after inventory and hashing to avoid recreating test-environment clutter.

## NBA 2K27 retail depot

Public SteamDB data identifies the launch depot as app `4356430`, depot `4356431`, build `25068232`, manifest `2271080181003010218` (published before worldwide unlock). It lists `data/streamline/nvngx_dlssnr.dll` at about 158.16 MiB. Public search results do not expose a trustworthy retail SHA-256, and the publicly documented `E16BCF...E1FC8E` allowlist predates the retail unlock, so it is not by itself proof of the launch-depot hash.

## Other announced titles

- NTE / Neverness to Everness: current public depot/search evidence does not show a native `nvngx_dlssnr.dll`; circulated demonstrations use the existing NBA 2K27-derived/community runtime.
- Where Winds Meet / 燕云十六声: current public depot lists conventional DLSS/DLSSG/DLSSD libraries, not `nvngx_dlssnr.dll`. DLSS 5 is announced for a later update.

## Version-name trap

A September 4 post mentioning “DLSS v310.9.0.0” concerns NVIDIA App overrides for the conventional SR/FG/RR components. The post does not name `nvngx_dlssnr.dll` or Neural Rendering, so it is not evidence of a DLSSNR 310.9 runtime.

## Current conclusion

No newly verifiable untouched retail DLL or retail hash was located in this pass. The only clean local baseline remains version 310.8.0.0, SHA-256 `e16bcf15e16e13f527491cdf7845b2fe6521a738d8f7c9c721866a8496e1fc8e`; its equality with the launch depot is still unproven until a clean owner extraction or public file hash appears.

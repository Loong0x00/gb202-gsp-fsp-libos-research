# DLSS NGX dual proxy

This package places two transparent feature-DLL proxies at the game's NGX
boundary:

- `nvngx_dlssd.dll`: observes the DLSSD / ray-reconstruction feature (F or D).
- `nvngx_dlss.dll`: observes the DLSS super-resolution feature (K or another preset).

Every export is forwarded to the matching NVIDIA DLL. Only the D3D12
`CreateFeature`, `EvaluateFeature`, and `ReleaseFeature` exports are wrapped to
write `dlss-proxy.jsonl`. No resource or parameter is modified in this first
version.

The installer preserves each real DLL under its original basename:

```text
game DLL directory/
  nvngx_dlss.dll                         proxy
  nvngx_dlssd.dll                        proxy
  dlss-proxy-real/sr/nvngx_dlss.dll     original
  dlss-proxy-real/rr/nvngx_dlssd.dll    original
```

## Build and fake-backend test

```bash
make -j"$(nproc)" test-layout
cd build/test-sr && WINEDEBUG=-all wine ./harness.exe ./nvngx_dlss.dll
cd ../test-rr && WINEDEBUG=-all wine ./harness.exe ./nvngx_dlssd.dll
```

## Install and restore

Run only while the target game is stopped:

```bash
./scripts/install.sh "/path/to/the/directory/containing/both/dlls"
./scripts/restore.sh "/path/to/the/directory/containing/both/dlls"
```

Analyze the trace:

```bash
python tools/analyze_trace.py /path/to/dlss-proxy.jsonl
```

If both `rr` and `sr` Evaluate calls occur, their QPC timestamps, command-list
identity, and resource identities reveal the first-level handoff topology. If
only `rr` occurs while RR is enabled, DLSSD is acting as the fused RR+SR node at
the public feature-DLL boundary.

# d5native production candidate package

Build ID: `d5native-pc1-20260910`

`bin/` contains exactly the owned `dxgi.dll`, `dlss5-native-host.dll`, and `dlss5-native-runtime.dll`. Check `SHA256SUMS`; `SOURCE_SHA256SUMS` freezes the corresponding source tree (excluding build/package outputs), and `TEST_RESULTS.md` freezes the CPU/Wine result and its acceptance boundary.

This package has passed the CPU/static/Wine fake-runtime tests in `../tests`, but has not been deployed to a game and has not passed a real CP2077 signed Feature 18 GPU Create/Evaluate run. Read `../README.md`, `../docs/ARCHITECTURE.md`, and `../docs/HANDOFF.md` before main-owner acceptance.

No NVIDIA, ReShade, or RenoDX binary is included. Do not overwrite or rename any NVIDIA DLL with these files.

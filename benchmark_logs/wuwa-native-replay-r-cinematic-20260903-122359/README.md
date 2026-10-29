# Native signed-RR temporal replay source — R cinematic caught

- Raw payload: /home/user/.local/share/Steam/steamapps/common/Wuthering Waves/Client/Binaries/Win64/dlss5-raw-captures/20260903-122359-540-p320
- 150/150/150 complete; 450 raw payloads; 21,315,182,400 bytes; abandoned=0; write_failed=0.
- SHA256SUMS contains 451 entries and every entry passed re-verification.
- Global frame IDs 6912..7061 are contiguous; exact QPC span is 4.9631875 s.
- All 150 Router records: original signed RR success, requested/effective DLSS5 mode 0, post_called=0, native_capture_called=1 success.
- Surfaces per frame: native signed RR 6144x3456 R11G11B10, motion 3564x2005 RG16F, depth 3564x2005 R32F.
- Reset appears at raw/global 9/6921 and 68/6980.
- R animation is covered by raw 9..97. Old bad-pose correspondences are approximately raw/global 25/6937 and 27/6939, with intermediate 26/6938 and 28/6940.
- Visual review of all native RR frames finds no old structured mosaic.
- OBS: 6144x3456 AV1, 26.88 s, full decode passed, SHA-256 16eb70fd54c91834088248bbb2c6bfb311d1d263fd6e009be53c2af491f57caf.
- OBS had 5 skipped/lagged frames (0.3%); this does not affect the contiguous raw Evaluate sequence.

This is the required source sequence for independent Feature18 replay. It is not Feature18 output itself.

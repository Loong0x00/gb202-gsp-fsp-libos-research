# User-recorded 2K visual A/B audit

Video: `/home/user/2026-09-03 07-57-59.mp4`

- SHA-256: `207b6527a73bbfb6fd88c4a9a85e749d9688dfb5e7881d3c96620b8840aa51ca`
- Container/video stream: AV1, 6144x3456, 60 fps, 70.416667 s
- OBS creation time: `2026-09-02T23:58:00Z`
- ReShade recorded swapchain resize to 2560x1440 at local 07:58:38.816.

Router telemetry for the latest process contains 13,615 signed RR Evaluate
records, all successful. Output/post breakdown:

| Output | Native/no-post | Feature18 post success | Feature18 post failure |
|---|---:|---:|---:|
| 6144x3456 | 732 | 3490 | 0 |
| 4096x2304 | 28 | 0 | 1849 |
| 3840x2160 | 28 | 0 | 3901 |
| 2560x1440 | 52 | 0 | 2796 |
| 2048x3456 | 739 | 0 | 0 |

Every attempted 2560x1440 post call returned `0xbad00005`; zero 2K frames ran
Feature18 successfully. The bridge log repeatedly reports:

`post-SR dynamic output change unsupported created=6144x3456/f26 current=2560x1440/f26`

Therefore this recording supports the visual observation that the bad frame was
absent after switching to 2K, but it does **not** establish a 6K-only Feature18
bug: the service retained its 6K-created resources and failed closed at 2K, so
those frames effectively remained signed-RR output. A valid resolution A/B
requires a fresh process started directly at 2560x1440, then confirmation of
`post_result=0x00000001` at 2K before judging the scene.

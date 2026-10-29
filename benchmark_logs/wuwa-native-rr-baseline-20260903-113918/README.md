# WuWa signed native-RR baseline (2026-09-03 11:39)

- OBS: 6144x3456 AV1 60 fps, 36.85 s, full ffmpeg decode passed.
- Video SHA-256: bbebe8021015b58f95a80d2ac1d1f37f9a5204e74c37f441776a3fcd97d6efdb
- Router telemetry: 4011/4011 signed RR evaluates succeeded; post_called=0 and effective_dlss5_mode=0 for all frames.
- The run used 3564x2005 and 4099x2306 signed-RR inputs, both targeting 6144x3456.
- Four Super+Alt+C invocations were refused because the Feature18 flight service was intentionally absent. No raw capture occurred.
- The OBS clip is a visual baseline only and is not a valid Feature18 replay input. A separate transparent native replay recorder is being deployed for RR+MV+Depth raw tensors.

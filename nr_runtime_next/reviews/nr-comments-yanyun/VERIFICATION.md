# Verification

Run from `/home/user/rt_5090_project/nr_runtime_next/reviews/nr-comments-yanyun`:

- `python build_report.py`: 129 comments; 27 UP comments; 26 indexed evidence quotes; 60 preserved HTTP requests.
- `python verify.py`: passed exact raw-text / rpid / mid / ctime matching for all 129 records; six target ownership/aid checks; six full-description responses; four selected reply threads match 31/13/26/8 advertised replies; both Kodak PNG signatures/dimensions; saved response byte counts.
- `sha256sum -c SHA256SUMS.txt`: passed for all files listed at check time; final manifest regenerated after verification artifacts were added and checked again.

HTTP statuses: 50 × 200, 5 × 404, 5 × 412. HTTP 200 is not synonymous with usable content: two reply/main responses have API code -352; Bing results irrelevant; second-page hot comment responses empty.

Acquisition timestamps: 2026-09-10 12:21:20–12:25:05 UTC (20:21–20:25 UTC+8), as recorded in per-request metadata. Video and comment times in reports use UTC+8.

No runtime benchmark, installation, video-stream playback, HDR transfer validation, or GPU/Wine/game execution. Screenshot control values were visually transcribed, not mechanically inferred from comment prose. Current source README is not proof of historical executable behavior. Public legacy top-comment access is partial, not a full census of video comments.

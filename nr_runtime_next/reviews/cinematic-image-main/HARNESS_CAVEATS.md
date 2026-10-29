# Observed harness issues

180750 POST1 completed four actual GPU frames and wrote fenced pixels, but failed an overstrict runtime sampled-last-frame assertion. Main fixed only this assertion in harness-reviewed; runtime unchanged.
181010 POST5 likewise produced all four fenced frames and SUCCESS.txt, then the process did not exit within40s. Main stopped only that lab prefix. Pixel evidence exists but this is NOT a clean-lifecycle pass. No teardown workaround applied yet.
Initial SOURCE.json said synthetic depth0.5; actual case.json and C++ specify0.375. Input bytes are only Color; runtime received0.375. Source metadata corrected for future cases; original run records retained.

181322/181407 WuWa cases also finished all GPU/pixel writes but stalled during process exit. Added OPTIONAL --fast-exit: explicit lab TerminateProcess only after all exact output fences, file flushes, and success receipt; skips DLL process-detach testing. Runtime DLL remains unchanged; original normal-teardown failures retained. Subsequent fast-exit data passes are NOT a claim the exit stall is fixed.

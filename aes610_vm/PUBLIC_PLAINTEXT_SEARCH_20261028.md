# Public FSP plaintext search — 2026-10-28

## Result

No usable public `FSP_RUN` plaintext was found in this search. No claim is made that such plaintext does not exist anywhere; only that the indexed sources checked did not yield it.

## Queries / sources checked

- Exact names and semantics: `"FSP_RUN"`, `"fsp_run.bin"`, `GB202`, `RTX 5090`, `Blackwell`, `plaintext`, `decrypted`, `unencrypted`, `ELF`, `debug`, `engineering`, `signed`.
- Chinese: `解密`, `明文`, `工程包`, `固件下载`.
- Code/index attempts: GitHub code search, grep.app, Sourcegraph, searchcode.
- Related architectures: GH100 / GB100.

## What was actually found

- Nova-core/FSP boot documentation and patch series.
- NVIDIA forum reports of FSP/GSP initialization failures and encrypted/signed firmware handling.
- Existing local/public research material about encrypted containers and recovery work.

None of these provided a plaintext `FSP_RUN` image, a decryption oracle, or a new legal plaintext-export path.

## Assessment

The public-plaintext route remains the lowest-cost route **if a new artifact appears**, but the current search did not produce one. Repeating the same broad searches is not justified. Better next steps are a natural AES known-answer context or a cautious JTAG feasibility check.

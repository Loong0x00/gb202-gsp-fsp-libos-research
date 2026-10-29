# Main dispatch correction

First outview worker did no reads and correctly refused to discover/guess which six files were allowed. Main's task said “six packet-listed files” without explicitly authorizing/naming PACKET.json or listing paths. This was Main's incomplete instruction, not absent files, runtime difficulty or an agent/tool failure.

FIRST_DISPATCH_BLOCKED_PROGRESS.md and FIRST_DISPATCH_BLOCKED_REPORT.md preserve the response. Main checked the exact six regular files (lstat, no symlink/directory traversal), recorded absolute paths/sizes/hashes in EXPLICIT_INPUT_PATHS.json, and is reissuing the task with all six absolute paths explicitly permitted. No global agent configuration, original sources, GPU/PE/Wine execution or installed state changed.

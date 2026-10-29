# Development tree after Project-ID merge

Main source/build now includes typed Project identity and hardened Core IAT observation. CPU/build checks only; no owned-GPU bootstrap or HSR native NR acceptance. Existing native/package is intentionally NOT regenerated: its source preflight blocks new launches from the changed development tree.

CP installer keeps its fixed accepted release. GPU-tested WuWa POST2 package/source remains in reviews/wuwa-main-physical-20260910-142015, with publisher freeze reviews/wuwa-publisher-main-20260910-144721 and proof in run144823. Do not substitute new development DLLs into either accepted bundle or call them GPU-verified.

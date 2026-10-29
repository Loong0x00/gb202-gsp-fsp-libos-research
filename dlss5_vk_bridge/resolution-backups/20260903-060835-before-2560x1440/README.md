# WuWa 2560x1440 configuration change

Applied: 2026-09-03T06:08:53+08:00
Game process was not running.
Changed current, last-confirmed, desired, and last-confirmed-desired dimensions to 2560x1440.
Left LocalStorage.db unchanged because it contains only selection indices, not authoritative pixel dimensions.
Removed dlss5-codec-only marker separately to restore normal Feature18 mode.
The rollback restores only GameUserSettings.ini; it deliberately does not roll back later database/login state or codec diagnostics.

Rollback:
  /home/user/rt_5090_project/dlss5_vk_bridge/resolution-backups/20260903-060835-before-2560x1440/restore.sh

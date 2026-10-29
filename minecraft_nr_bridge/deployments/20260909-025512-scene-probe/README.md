# Scene probe deployment

Installed only nr-scene-probe-0.1.0.jar in /home/user/minecraft/26.1/mods.
Original mods/config hashes and their successful verification are preserved.
The first built jar was corrected before any target-world test: coherent
world color/depth are captured before hand rendering, not at the late HUD seam.
`deployed-corrected-world-hook.jar` is final. `rollback.sh` removes exactly that
known jar after Minecraft exits. Other files/worlds are untouched; captures stay.

This is transport-only, NOT a running NR integration. Target world test pending.

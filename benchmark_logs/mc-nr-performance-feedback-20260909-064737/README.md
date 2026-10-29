# User feedback: no visible NR benefit, observed32FPS

NR was disabled. A bounded original-COPY test was then run; both NR and COPY
were left OFF. No resolution/settings/raw captures were changed.

Off / COPY / off observed scene-hook frame-rate estimates:
31.08 /30.63 /30.64 per second. Camera metadata stayed exactly unchanged in
all three windows. COPY performed zero additional Feature18 evaluations.
These are not GPU inference timings and are not a valid unthrottled cost split.

Existing options are enableVsync=false, maxFps260, inactivityFpsLimit=afk.
Actual26.1.2 bytecode caps to30 after60000ms without input,10 after600000ms.
A targeted Render-thread stack sample while OFF was parked inside
FramerateLimiter.limitDisplayFPS. Thus AFK/limiter interference must be removed
before attributing the observed32FPS to NR; the user's active-play cost remains
unmeasured. No option was changed or input fabricated.

Before disabling, actual NR had9367 cumulative evaluations at snapshot; clean
shutdown reached9381 (9261 in continuous session), zero timeouts/late discards.
This validates execution, not a visible quality improvement. No in-game matched
pre/post-present image comparison has yet established why the effect looked weak.

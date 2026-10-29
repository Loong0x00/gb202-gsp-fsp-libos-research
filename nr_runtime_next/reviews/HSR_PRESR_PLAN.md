# HSR PRE proposal — not implemented/validated

Current new HSR ingress is POST-only, so it does not yet satisfy the requested
PRE option. Do not advertise PRE from policy support alone.

A conservative future route can avoid assuming signed SR accepts a different
Color format: capture the real before-SR Color via observed D3D11 ResourceGet
slot 8, normalize its finite HDR into owned RGBA16F, run selected PRE NR layers,
then convert the native float16 result back into an owned **same-format R11**
D3D11/shared-D3D12 Color resource before the single original signed SR call.
This adds an explicit R11 quantization step; it is not identical to passing a
float16 replacement and must be disclosed/tested.

Required before implementation/deployment:

1. Actual current Color descriptor, active subrect, MV/depth views and same-frame
   metadata at the real Feature-1 seam. RR/Feature13 remains unsupported.
2. Verify the real game-parameter D3D11 setter ABI (likely slot 2 from the MSVC
   overload order, NOT CP D3D12 slot1 and NOT float slot6). Start with an exact
   same-pointer set/get roundtrip; do not infer ABI solely from a header/mock.
3. Two directional fences and protected lifetime for shared inputs. D3D11 copies
   original inputs -> input-ready signal; D3D12 waits, normalizes, NR, R11 output
   conversion -> output-ready signal; D3D11 waits, evaluates original SR once
   with the owned R11 Color, restores and rereads original Color/base params.
4. Keep replacement Color alive through original SR GPU consumption, not just
   the CPU callback. No CPU waits/late previous-frame substitution.
5. Failure/budget/phase/lease/ABI rejection calls original SR exactly once with
   original Color. Existing Guardian and late-load rules remain mandatory.
6. FormatBridge currently returns a float16 PRE replacement; it needs a reviewed
   same-format PRE conversion/commit path, not a fake POST result or incompatible
   CopyTextureRegion. Native ABI 200/216 and D5LC/D5RP sizes stay unchanged.

This is a future design, not permission to modify protected startup components,
change game/anti-cheat settings, or claim HSR compatibility. POST transport and
its actual Guardian/AppID/view evidence must first be validated.

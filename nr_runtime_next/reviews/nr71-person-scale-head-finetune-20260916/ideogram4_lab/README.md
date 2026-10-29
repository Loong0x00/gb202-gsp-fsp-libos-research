# Ideogram4 diversity expansion lab

Prepared only after the fixed nonlinear adapter passed standalone-face identities but failed both final full-body identities.

Pinned source checkouts:

- ComfyUI: `7a0b5eede3f9721c8faab290689893f36edc6d66`
- official ComfyUI-Ideogram4 node: `c05545d71e61b7ce47534a972eaeefd958a3719f`

No model weights have been downloaded and no license was accepted automatically. Official Ideogram4 local weights are gated/non-commercial. The machine currently has no Hugging Face token. The user must personally accept the model terms and authenticate locally before weight acquisition.

Planned use is training-data diversity only: create one base full-/half-body identity on a uniform background, derive all scales from that single generated image, extract an explicit alpha/person mask, and keep identity groups within one split. Generated final outputs will not be used as a substitute for untouched real/procedural final identities.

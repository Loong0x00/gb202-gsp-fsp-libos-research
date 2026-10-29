# Signature-defect status — RTX 5090 VBIOS corpus

Scope: static local-file analysis only. No flashing, no execution, no GPU/device access.

## Short answer

No obvious signature defect has been found in the current corpus.

The checks performed so far rule out the easy/cheap classes of mistakes:

- broken SHA-384 coverage inside the nested image;
- same raw 96-byte signature-shaped field reused over different parent/object digests;
- same adjacent P-384 point plus repeated `r`-half across different parent/object digests, which would be a nonce-reuse-like symptom under the simple ECDSA model;
- DER-encoded ECDSA signature blobs accidentally embedded/reused in the plain ROM bytes;
- trivial direct self-verification with the adjacent P-384 point over the bounded candidate transcripts tested.

## Important observation

For the current local corpus, almost every normal RTX 5090 / `2B85` sample shares the exact same `FSP_RUN` envelope:

- Lightning 800W: `281640.rom`
- Lightning 1000W: `281649.rom`
- ASUS Astral XOC #2 / 2001W: `281814.rom`
- normal ASUS / MSI / Gigabyte / Palit / Zotac / Inno3D 5090 ROMs

They all resolve to the same `FSP_RUN` envelope SHA-256 prefix:

```text
1f01255cf607...
```

The GALAX HOF `5090D / 2B87` sample is the current outlier:

```text
e66270a9c726...
```

This means the visible 800W/1000W/2001W differences are probably not inside the common `FSP_RUN` object. They are more likely in another signed VBIOS policy area or board-policy table.

## Practical implication

Right now there is no evidence for:

```text
edit bytes -> preserve/bypass signature -> accepted by Blackwell secure path
```

The evidence fits this better:

```text
NVIDIA/AIB generated multiple valid signed policy images
same FSP_RUN object reused
outer VBIOS policy differs
device accepts only intact signed material
```

This does not prove the scheme has no flaw. It only says the current sample set does not show a low-hanging flaw.

## Report files

- `signature_defect_audit.md`
- `signature_defect_audit.json`
- `family_group_stats.md`
- `corpus_completeness.md`


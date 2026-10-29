# Main style-enum mismatch finding (public source + local audit)

Local frontend has labels [Natural,Cinematic], raw indices0/1 and max1. Both current and frozen runtime pass control.style directly to DLSSNR.Style and reject style>1. Thus style2 cannot currently be selected/executed by this path. Earlier claims that the actual Style1 run was cinematic were based on these labels, not independent raw-enum proof.

Public DLSS5VKLayer README explicitly maps raw Style0 Default,1 Natural,2 Cinematic. Current DLSS5-Image-Converter settings.py exposes the same three indices and explicitly says its earlier two-entry list mislabeled Default as Natural and made Cinematic unreachable; its runtime writer uses len(NR_STYLES), despite an outdated two-style comment. Exact downloaded bytes/URLs/date are in SOURCES.json; commit pin unavailable due API rate limit.

This is strong evidence of a label/range discrepancy, not proof that every external video used style2 or that style2 is safe/effective with our exact e16 DLL/backend. A CPU/static audit of exact enum/call semantics is delegated in reviews/nr-style-enum-audit. No style change, game launch, GPU test, stored-value migration or automatic switch to2 occurred here.

Next fix must preserve numeric stored values, accurately name them, audit every validator/legacy consumer, and validate style2 with a bounded single-layer same-source comparison before advertising it. Five natural-style passes are not evidence of cinematic-style output or of visual improvement.

## Confirmed / label-only fix at17:29

Exact retained RenoDX SHA87aef9...a4aee constructs three options(Default,Natural,Cinematic) and passes the unchanged raw selection through globalRVA0x5a778 to DLSSNR.Style; exact e16 NR consumes the same integer. Main independently reran reviews/nr-style-enum-audit/verify_static.py successfully. No implicit+1 mapping is appropriate.

Frontend app.py now displays supported raw0 as默认 and raw1 as自然, with explicit notice that raw2电影感 is not currently exposed. Core range/default, raw wire values, saved profiles and all runtime/game binaries are unchanged. tests/test_style_labels.py verifies labels and0->0/1->1 payload roundtrips;2tests pass. Backup pointer STYLE_LABEL_FIX_BACKUP. Supporting style2 and rendering it remain separate work; no automatic switch or GPU claim.

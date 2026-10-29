# English Public-Web Hunt: Blackwell/GB202 FieldDiag, MODS 580, FuseRework

**Checked:** 2026-10-26 (UTC)  
**Scope:** Public English-language web pages, public search endpoints, forums, code indexes, and public file-host indexes. I opened the source pages for the leads below; search snippets alone are not treated as evidence. No login, paid access, NDA, CAPTCHA, or other access control was bypassed. No executable, firmware, archive, `.bin`, `.tgz`, or package was downloaded.

## Executive result

One strong public pointer identifies the target x86 Blackwell Field Diagnostics release, but it does **not** expose the package or any FuseRework files. Its linked NVIDIA NVOnline document redirects to an account login. I found no publicly verifiable direct artifact URL for `fuserework.bin`, its three debug-GFW sidecars, or a standalone x86 MODS 580 package. No file size or hash for those target artifacts is publicly visible in the pages checked.

This is a bounded search result, **not proof that no public copy exists**: several general-purpose search engines returned noise or challenged automated access, and the NVOnline item is gated.

## Verified leads

| Lead | Original-page evidence (opened) | Visible target filenames / size / hash | Credibility and link state |
|---|---|---|---|
| [Supermicro FAQ 44778](https://www.supermicro.com/en/support/faqs/faq.php?faq=44778) | The page title is “FAQ Entry | Online Support | Support”. The body asks “What is the latest Fieldiag Utility Version for PCIe GPUs?” and says: “The latest Fieldiag Utility adds more support for Blackwell PCIe GPUs. Please check your NVOnline account for the following details.” It then lists **NVOnline ID #1124962**, **Version: 629-INT27-DIAG-008**, **Release Date: 2/23/2026**, and **Description: NVIDIA Blackwell GPU Field Diagnostics (x86)**. The live page also shows FAQ ID 44778 and Date Posted 02/27/26. | No `.tgz`, `.bin`, MODS executable, file size, or hash is shown; no download link is present on the page. **High confidence** for release identity (official Supermicro support page); not evidence that any particular FuseRework payload is included. **Live** when checked. |
| [NVIDIA NVOnline DocumentDetails, DocID 1124962](https://partners.nvidia.com/DocumentDetails?DocID=1124962) | Opening the official URL redirects to `https://partners.nvidia.com/Login?ReturnUrl=%2fDocumentDetails%3fDocID%3d1124962&DocID=1124962`. The original page displays “Login” and Email / Password fields. | No document listing, filename, size, or hash is visible before login. No download was attempted. | **High confidence** that this is the NVIDIA portal pointer referenced by the FAQ. **Login-gated, not dead**; not accessed further. |

The public FAQ establishes the version/ID, but it does not state `629.580.36`, `629.580.34`, `GB202`, or any of the four FuseRework filenames. I therefore do not attribute those items to this package based on the FAQ alone.

## Search coverage and observed results

Queries were submitted in English, with exact-phrase and domain-restricted variants. The phrase set included:

- `"fuserework.bin"`, `"fuserework_debug_gfw_hash.bin"`, `"fuserework_debug_gfw_pub_key.bin"`, `"fuserework_debug_gfw_sig.bin"`
- `"SetReworkBinaryFilename"`, `"FRB Riscv Start"`
- `"629-INT27-DIAG-008"`, `"NVOnline 1124962"`, `"629.580.36"`, `"629.580.34"`
- `"Blackwell fielddiag tgz"`, `"MODS 580 download"`

| Surface checked | What the opened/retrieved page showed | Assessment |
|---|---|---|
| General web search (Bing, Naver; English terms) | Exact-string and site-restricted searches produced mostly unrelated results / generic host landing pages; no matching artifact page or share URL was confirmed. | Low-confidence negative evidence because the indexes were noisy. Generic Mega/Drive/MediaFire/Pixeldrain pages were not counted as candidates. |
| Google, DuckDuckGo, Brave Search | Google showed an automated-traffic challenge; DuckDuckGo showed its image challenge; Brave showed a verification challenge. | Stopped at the challenges; did not solve or bypass them. |
| [GitHub code search for `fuserework.bin`](https://github.com/search?q=%22fuserework.bin%22&type=code) | The opened page says to log in or create an account before using code search. Public GitHub repository-search API queries for `fuserework`, `NVIDIA Fieldiag`, `NVIDIA FieldDiag Blackwell`, and the exact release ID returned zero repositories before rate limiting. | No public repository lead found. Code search is login-gated; no login or alternate access was used. |
| [grep.app exact code search](https://grep.app/api/search?q=fuserework.bin) | The API returned `hits.total: 0` for `fuserework.bin`, `fuserework_debug_gfw_hash.bin`, `SetReworkBinaryFilename`, `FRB Riscv Start`, `629.580.36`, and `629-INT27-DIAG-008`. | No indexed public-code match in this service. This is not a claim about unindexed/private repositories. |
| Internet Archive Advanced Search | Direct API searches for `fuserework`, `629.580.36`, `629-INT27-DIAG-008`, and `Blackwell fielddiag` returned `numFound: 0`. A broader `NVIDIA MODS 580` query returned one GitHub-snapshot item; its [original item page](https://archive.org/details/github.com-HayatoG-iss_pc_-_2026-10-21_22-15-32) was opened and is unrelated gaming/software content (generic “Mods/Cheats”, NVIDIA GPU mentions, and RX 580 references), not FieldDiag/MODS 580. | No relevant Archive.org artifact. The one broad-query match is a verified false positive. |
| Hugging Face | Public models/datasets/spaces API searches for `fuserework`, `629.580.36`, `Blackwell fielddiag`, and `NVIDIA MODS` returned empty lists. The [full-text search page for `fuserework`](https://huggingface.co/search/full-text?q=fuserework) was opened; visible matches were unrelated dataset text, not these artifacts. | No relevant public model, dataset, space, or file listing found. |
| Forums / GPU and electronics repair communities | ServeTheHome public forum searches returned “No results found” for `fuserework.bin`, `629-INT27-DIAG-008`, `629.580.36`, `SetReworkBinaryFilename`, `Blackwell fielddiag`, and `MODS 580`. Badcaps’ public search page opened as an advanced-search form but did not expose results for the supplied query. TechPowerUp returned an access-denied/bot-check page. | No verified forum post or attachment. Badcaps/TechPowerUp results remain unknown rather than “no results”; no challenge was bypassed. |
| Google Drive / MEGA / MediaFire / Gofile / Pixeldrain | Domain-restricted web-index queries combined these hosts with the filenames, release IDs, and `fuserework`. Returned links were generic/unrelated or absent; no share URL whose original page visibly matched the target was found. | No candidate share link to open; no files, sizes, or hashes verified. Search-index absence is weak evidence, especially for unindexed or private shares. |

### Reproducible search endpoints

Representative queries and direct public index endpoints used:

- [Bing: `"fuserework.bin"`](https://www.bing.com/search?q=%22fuserework.bin%22)
- [Bing: `"629-INT27-DIAG-008"`](https://www.bing.com/search?q=%22629-INT27-DIAG-008%22)
- [Google: `"SetReworkBinaryFilename"`](https://www.google.com/search?q=%22SetReworkBinaryFilename%22)
- [DuckDuckGo: `"fuserework.bin"`](https://html.duckduckgo.com/html/?q=%22fuserework.bin%22)
- [Archive.org Advanced Search: `fuserework`](https://archive.org/advancedsearch.php?q=fuserework&fl%5B%5D=identifier&fl%5B%5D=title&output=json)
- [Hugging Face models search: `fuserework`](https://huggingface.co/api/models?search=fuserework&limit=10)

## Candidate artifact inventory

| Candidate artifact / URL | Page-visible filename | Size | Hash | Status / confidence |
|---|---|---:|---|---|
| Blackwell x86 FieldDiag `629-INT27-DIAG-008` — [NVOnline DocID 1124962](https://partners.nvidia.com/DocumentDetails?DocID=1124962) | None visible before login | Not visible | Not visible | Official portal lead; access-gated. **No public binary URL verified.** |
| `fuserework.bin` | None found | — | — | No public candidate URL found in the checked indexes/pages. |
| `fuserework_debug_gfw_hash.bin` | None found | — | — | No public candidate URL found in the checked indexes/pages. |
| `fuserework_debug_gfw_pub_key.bin` | None found | — | — | No public candidate URL found in the checked indexes/pages. |
| `fuserework_debug_gfw_sig.bin` | None found | — | — | No public candidate URL found in the checked indexes/pages. |
| MODS 580 / `629.580.36` / `629.580.34` standalone download | None found | — | — | No public x86 MODS 580 candidate page or file hash verified. |

## Bottom line

The only substantiated public lead is the Supermicro FAQ pointing to an NVIDIA NVOnline entry for Blackwell x86 Field Diagnostics. The original NVOnline URL is live but requires login, and the public FAQ exposes no artifact metadata or files. I found no page-verified public download/share for the FieldDiag archive, MODS 580, or the FuseRework main binary and sidecars. Any follow-up requiring NVOnline would need the user's legitimately authorized account; this hunt did not attempt access beyond the login page.

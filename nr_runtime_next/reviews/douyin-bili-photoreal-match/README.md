# Exact Douyin → Bilibili source search (2026-09-10, CPU/public HTTP only)

## Outcome / confidence boundary

**Exact cross-platform source NOT resolved.** Do not present any video below as the supplied Douyin clip. No original Douyin pixels, audio, uploader, caption metadata, or authoritative publication time were retrieved. Consequently there are **zero verified matching frame pairs and zero verified matching timestamps**. No basis was obtained for classifying this exact clip as NR/DLSS5, UE cinematics/path tracing, a conventional filter/mod, or generative video redraw.

The user's observation that ordinary filtering seems insufficient is an observation about appearance, not an accusation of forgery. It is not refuted or proved by these results. Earlier FanticSama material is not a source match and was not used as one.

## Exact target / date

- Supplied shortlink: https://v.douyin.com/TZUEUtBtjG0/
- Parent's saved HTTP redirect headers at `../douyin-TZUEUtBtjG0/headers.txt` identify video **7681968680128892198** and canonical URL https://www.douyin.com/video/7681968680128892198.
- User-supplied caption (NOT independently verified): `你还能分得清游戏和现实吗？#游戏推荐 #鸣潮`.
- A mobile-UA ordinary GET to https://www.iesdouyin.com/share/video/7681968680128892198/ returned HTTP 200 but an error screen: `抱歉出错了 请尝试在抖音内观看`. Its embedded `_ROUTER_DATA` contains `itemId:7681968680128892198`, but no item detail. `_SSR_DATA.data` is empty. Saved as `douyin-share.body` and `douyin-share.meta.json`.
- Ordinary public detail endpoints returned HTTP 200 with **zero body bytes**. The desktop search page was only a JavaScript shell. yt-dlp stopped with `Fresh cookies (not necessarily logged in) are needed`; no cookies/login/challenge handling was attempted.
- Independent **ID-encoding heuristic only**: `7681968680128892198 >> 32 = 1788597712`, interpreted as Unix seconds gives **2026-09-05 08:41:52 UTC / 2026-09-05 16:41:52 UTC+8**. This is consistent with about five days before the research date, **but is not verified publication metadata**. No `create_time` was obtained. Do not claim exact publication date verified from this. The share-text `09/07` was not used.

## Useful current Bilibili leads — explicitly NOT matches

Bilibili's public **search HTML worked**, despite its JSON search endpoint and ordinary video pages returning 412. Search SSR `window.__pinia` contains publication timestamps, owners, descriptions, cover URLs and tags. Those are saved in `candidate-search-metadata.json`. Dates below are `pubdate`, converted to UTC+8, not the distinct `senddate` field.

| Lead | Uploader | Publication (UTC+8) | Duration | Evidence / limitation |
|---|---|---|---|---|
| [英伟达最新技术DLSS5，全程AI渲染鸣潮实机演示](https://www.bilibili.com/video/BV1uGth6CEfh/) | 五言不会唱歌, mid 3546814630332630 | 2026-08-31 18:00:38 | 2:43 | Description `英伟达dlss5，教程私信我`; cover: pink-haired character in wet courtyard, `DLSS 5 On` label. Uploader's technical claim only. |
| [【鸣潮DLSS5】玄方地界6K120hz角色/跑图/战斗10分钟演示，NR风格：Cinematic目前最适合鸣潮的DLSS5模式](https://www.bilibili.com/video/BV1NhtW67EUq/) | 玄方研究院, mid 3707016587512597 | 2026-08-31 10:57:34 | 10:17 | Search description explicitly says these are unofficial early configurations, not official WuWa-client settings; mentions dual-PCIe layout, RTX5090. See quote below. No independent runtime verification. |
| [鸣潮dlss5开启展示，分不清现实与游戏了！](https://www.bilibili.com/video/BV1Xzt46BErZ/) | Man牢布, mid 3546694094424970 | 2026-08-31 09:38:55 | 0:40 | Wording and wet courtyard cover are relevant; no description beyond `-`. Cover is not proof of derivation from either lead above. |
| [当二游开了dlss5后，这个画风好像不太对......](https://www.bilibili.com/video/BV1ATtr6oEA5/) | 彩虹游戏菌, mid 405068883 | 2026-09-04 21:46:39 | 0:40 | Tags include 异环、鸣潮、绝区零、原神; plausible cross-game roundup lead, but no exact-caption/source link. |
| [找到了燕云在dlss5下最舒服的调色，这谁能分得清游戏和现实啊！](https://www.bilibili.com/video/BV199Yp6gEwL/) | 温煦丶游戏杂谈, mid 290486319 | 2026-09-09 07:20:38 | 0:26 | Related YanYun lead only; NOT WuWa exact source. Cover shows reflective water and village architecture. |

玄方研究院's search-indexed description begins:

> 目前所有DLSS5均为通过其他游戏泄露配置反向推演偷跑。效果均非鸣潮游戏客户端官方设定，DLSS5大概率会是NVIDIA给每个游戏厂商开放参数由研发团队调整最终效果，无论如何，未来已至。

This is **what the uploader says**, not a verified general statement about all DLSS5 videos. The search description is truncated, so it does not establish the full setup.

### False positive excluded

[你分得清这是游戏还是现实吗？](https://www.bilibili.com/video/BV19N8C6XE9L/), bili_694656351, 2026-08-22 13:17:42 UTC+8, 1:01: tags explicitly concern Call of Duty; cover is an FPS weapon inspection. Similar caption does not make it the requested WuWa clip.

## Images / timestamps

`candidate-covers-NOT-matched-frames.jpg` is a contact sheet of **public cover images**, not extracted movie frames. Tile IDs correspond to the table (and excluded COD false positive). There are no playback timestamps for covers and they must not be described as footage comparisons. Douyin original media was unavailable. No complete clip was downloaded, no ffmpeg frame extraction was performed, and no visual algorithm was used to assert a source match.

## Search/access checks

- Public Bilibili search HTML: exact caption with/without quotes, shorter phrase segments, 鸣潮 + 现实/画质/DLSS5, 绝区零 + DLSS5, author-name queries. Full responses and response metadata saved; extracted cards in `search-candidates.json`; SSR data in `bili-*.state.json`.
- Google returned a JavaScript/redirect screen, not usable results. Bing returned unrelated results for several exact/relevant queries, and no useful exact-target hit; not used as evidence for identity.
- First Baidu query returned broadly related older WuWa results, then subsequent requests returned `百度安全验证`. No challenge solving attempted. Sogou connection failed.
- Ordinary Bilibili video-page GETs for the six listed leads returned explicit HTTP 412 security-control rejection. No alternate-login, cookie, signing or challenge workaround was used.
- `yt-dlp --skip-download --dump-single-json --no-warnings https://www.douyin.com/video/7681968680128892198` failed at the cookie requirement. Saved stderr.
- CPU-only Python/requests/BeautifulSoup fetched and parsed public HTML; Node `vm.runInNewContext` decoded the search page's **data-only SSR assignment**, not an access challenge; Pillow decoded the public cover images and composed a contact sheet. No GPU/game execution.

## What would resolve the gap

A user-provided frame/screen recording of this exact Douyin clip, or its visible uploader name, is the smallest missing discriminator. Without original pixels or an uploader, collecting more unrelated impressive WuWa clips risks repeating the previous source mismatch. All five leads above remain candidates, not answers.

## Artifacts

All new files are confined to this directory. `FILES.txt` lists exact absolute paths; `SHA256SUMS.txt` records file hashes. Major files: this report, `candidate-search-metadata.json`, `candidate-covers-NOT-matched-frames.jpg`, `search-candidates.json`, `douyin-share.body`, HTTP `.meta.json` records, and `yt-dlp.stderr`.

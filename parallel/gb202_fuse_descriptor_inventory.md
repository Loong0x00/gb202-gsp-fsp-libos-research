# MODS 570.151 GB202 `NewFuse` descriptor / name database inventory

Date: 2026-07-21  
Scope: static, local, low-resource inventory only. No MODS/GPU execution, no
network access, no authorization material, no live command construction, no
Ghidra/full disassembly, and no whole-memory binary load was used.

## Bottom line

1. **The stock high-level name path expects an external fuse-spec file whose
   default GB202 name is `gb202_f.json`.** The executable contains the parser,
   the default filename, schema-key strings, the eight public L2 names, a
   separate human-readable tag map, and RegHal metadata. It does **not** contain
   an addressable `gb202_f.json` payload.
2. **The file is genuinely absent from this local distribution at the archive
   member level.** This is not merely an incomplete `extracted_inner`
   directory: its 133 top-level payload nodes exactly match the nested
   `570.151.tgz` member list, and neither list contains any `_f.json`,
   `_POR.json`, or `_fpf.json` file.
3. **No GB202 fuse schema was found in any recognized nested archive.** The ZIP,
   outer TBZ, MODS TGZ, Python TBZ, driver TGZ, egg/zip, CASK tar files, gzip-tar
   resource bundles, and the outer NVDEC/NVOFA/NVJPG bundles were inventoried by
   member name. The only exact plaintext hits for `gb202_f.json`,
   `Chip_options`, `jtagConfigFields`, `fuselessFuse`, or
   `OPT_L2SLICE_FBP0_DISABLE` under the extracted MODS payload are in the
   `mods` ELF itself, where they belong to filename selection, parser/schema,
   and tag-map strings.
4. This is a **bounded negative**, not proof that NVIDIA has no such file. The
   authentic database could exist in a private manufacturing/runspace package
   or be staged by external orchestration. Opaque/encrypted configuration and
   arbitrary custom-encoded blobs were not reverse engineered, so an
   intentionally hidden copy cannot be ruled out in the mathematical sense.
5. For `NewFuse.SetSwFuses` to resolve the eight L2 raw-mask names through the
   stock name entry, what remains missing is an **authentic GB202 main fuse
   descriptor database**, reachable through the package/runspace file resolver,
   with the eight descriptor records and their type/width/raw-offset metadata.
   `_POR.json`, `_fpf.json`, and IFF JTAG coordinates are not the missing pieces
   for this particular direct-shadow name path. A parser-compatible invented
   file would not establish authenticity or safety and was not created.

## Artifact provenance

### Local outer archive

- Local artifact: `mods_audit/570.151_GB202_5090.zip`
- Size: `943,721,235` bytes
- Local SHA-256:
  `d141f685ea70c9a49095b7369201ab0651222bea3c063acfd6616dfde058ded9`
- `mods_audit/static/gb202_metadata.json` records the mirror object as
  `/570.151 GB202 - 5090.zip`, size `943,721,235`, MD5
  `3ae2748b5cea1a73ce1f7f7056477ab1`, the same SHA-256, mirror timestamp
  `2025-08-06T12:24:34Z`, and resource ID
  `167329768:baf946a5a49bc496407e512d2301cdda30ff0a90e49e9b224ce0fde713f482b8`.
- This metadata establishes identity with the locally recorded mirror object;
  it is **not** an NVIDIA signature or official-release provenance.
- The ZIP central directory has one unencrypted, deflated member only:
  `659-1G145-0035-MFG-41923.tbz`, uncompressed size `943,748,743`, CRC32
  `faf9e99c`, DOS timestamp `2025-01-27 10:08:34`.

### MODS executable used for string and small-window evidence

- Artifact: `mods_audit/static/extracted_inner/mods`
- Size: `392,339,552` bytes
- SHA-256:
  `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`
- It is a stripped x86-64 ELF with 39 sections. `readelf -S` reports no section
  with the ELF `SHF_COMPRESSED` (`C`) flag. It does contain an `.nv_fatbin`
  code-resource section; that is not evidence of a fuse JSON database.
- A streaming member-list comparison showed no difference between the nested
  `570.151.tgz` payload names and `mods_audit/static/extracted_inner`: the local
  extraction is complete for that TGZ (132 regular files plus one symlink).

## Where the database comes from and how it is loaded

### Direct artifact facts

The `mods` ELF contains one exact `gb202_f.json` string at file offset
`0x08ce15c9`. It sits in a generation filename sequence beginning with
`gp100_f.json` and continuing through Blackwell names (`gb100_f.json`,
`gb102_f.json`, `gb202_f.json`, `gb203_f.json`, ... `gb207_f.json`), immediately
followed by `Fuse file %s does not exist` at `0x08ce1617`. This is a default-name
dispatch table, not JSON content.

The same ELF separately contains:

- parser keys `Chip_options`, `Map_options`, `Mkt_options`, `configFields`,
  `fuselessFuse`, `fuseName`, `jtagConfigFields`, `blockIndex`, `blockOffset`,
  `chainId`, `lsbIndex`, `msbIndex`, `bits`, `customer_visible`, and `offset`
  in the small string window `0x08cc3828..0x08cc398b`;
- `Fuse file %s not found`, the header keys `Perforce file revision`,
  `Generation time`, `Project Name`, `Status`, and the suffixes `_f.json`,
  `_POR.json`, `_fpf.json` at `0x08cc3941..0x08cc39eb`;
- the JSI usage string `Usage: Fuse.FuseFile = fuseFileName` at
  `0x0884bd58`, the `FuseFilename` property/usage strings at `0x0884bdf4` and
  `0x08ce0570`, and `Usage: FindPkgFile(filename)` / `FindPkgFile` at
  `0x08cc7c52` / `0x08cc8004`.

Decoded JavaScript independently shows the package-file boundary:

- `mods_audit/static/decoded/all/prntutil.js:677` passes
  `subdev.Fuse.FuseFilename` to `FuseJson.GetPorFileId`;
- `prntutil.js:2460-2494` and `:5922-5958` read `FuseFilename`, call
  `FindPkgFile(fuseFile)`, and only then request P4/version metadata.

The manufacturing wrapper supplies the local filesystem context. The outer
TBZ member `run.sh` changes into `core/mods0` and extracts `570.151.tgz` there;
the recipe XML files then change into the per-port MODS directory before
launching tests. No outer recipe or wrapper member names or text reference
`gb202_f.json`, and the wrapper does not visibly fetch a fuse database.

### Reconstructed loading chain and confidence

Existing bounded native analysis in `L2_REENABLE_STATIC_FINDINGS.md:507-645`
and `:2008-2052` gives this chain:

```text
NewFuse.SetSwFuses
  -> SetSwFusesCore
  -> SplitMacro input preparation / lazy initialization
  -> FuseJsonParser2(main _f.json)
  -> normalized name lookup and descriptor-based raw plan
```

The same prior analysis assigns chip ID `0xff2` to the `gb202_f.json` default.
This inventory independently reproduced the filename table, parser keys,
package resolver interface, decoded-JS consumers, and package absence, but did
not repeat the full native call-graph disassembly.

The most defensible source statement is therefore:

- **PROVED for this executable:** MODS chooses a logical external filename and
  has a JSON parser for a generated fuse-spec format.
- **STRONG INFERENCE:** the normal source is a separately supplied NVIDIA
  FuseSpec/manufacturing artifact. The required header vocabulary, especially
  `Perforce file revision` and generation/project fields, supports this, but no
  authentic repository path or revision was recovered.
- **PROVED for decoded utilities:** the selected `FuseFilename` is resolved via
  `FindPkgFile` for package metadata access.
- **UNKNOWN:** the exact directory precedence of `FindPkgFile` and whether a
  private Nautilus deployment injects another runspace path. The JSI
  `Fuse.FuseFile` setter also shows that a caller can select a filename, but no
  such selection appears in the bundled recipes/scripts inspected here.

The derived `_POR.json` and `_fpf.json` are companion loads. Existing bounded
parser analysis shows their absence is optional after a valid main `_f.json`
has loaded. They are not substitutes for the main descriptor database.

## Why the compiled names are not an embedded descriptor database

Three different data sources must not be conflated:

| Source | What is compiled in | What it cannot supply to stock name encoding |
|---|---|---|
| Default filename table | `gb202_f.json` and other generation filenames | Any descriptor record or JSON body |
| `GB20X fuse tag maps` | `OPT_L2SLICE_FBPn_DISABLE` plus human-readable labels such as `f0fbpltc0slice0` | `bits`, `type`, `customer_visible`, raw `offset`, FPF state, or JTAG coordinates |
| RegHal / floorsweep metadata | GB20x read IDs and the independently recovered raw-address family | A `FuseJsonParser2` descriptor object or fallback insertion into the name tree |

The L2 tag-map region is directly visible in small string windows: FBP0 begins
at `0x08d1a73a`, and FBP7 appears at `0x08d1b97d`. Each of the eight requested
names occurs exactly once in the ELF. Nearby content is a vector of readable
unit labels, not JSON punctuation/fields. The lower-case string
`opt_l2slice_fbp0_disable` at `0x08ce1eea` belongs to a different built-in
hard-read/floorsweep metadata layer. The stock `SetSwFuses` external names are
the upper-case `OPT_L2SLICE_FBPn_DISABLE` names.

This distinction also explains why knowing the RegHal addresses does not make
the stock name entry self-sufficient: no observed fallback synthesizes a
`Chip_options` descriptor from RegHal or from the tag map. `SetOverrides` can
attach a value to an already known descriptor, but it does not provide the
missing width/type/offset definition (`L2_REENABLE_STATIC_FINDINGS.md:619-645`).

## Complete recognized-container inventory

The checks below were filename/member-list or exact-string checks. Archive
payloads were streamed; no large archive was unpacked into a new tree.

| Container/layer | Inventory result | Fuse-schema result |
|---|---:|---|
| Outer ZIP | 1 member | Only the outer TBZ |
| `659-1G145-0035-MFG-41923.tbz` | 47 entries | No member matching `gb202_f`, `_f.json`, `fuse`, or `schema` |
| Outer `python3.tbz` | 33,236 entries | No GB202 or `_f.json`; matches for `fsspec/fuse.py` and `jsonschema` are unrelated Python packages |
| Outer `core/mods0/570.151.tgz` | 133 payload nodes (+ `./`) | No `.json`; only `pwrregcheck_cfg.jsone`; exact match to `extracted_inner` |
| `driver.tgz` | 15 C/source members | No relevant member |
| `fatool.egg` | 8 Python members | No relevant member |
| `cask_sm100.bin` / `cask_sm120.bin` | 2,632 / 676 tar members | CUTLASS resource names only; no `fuse`, `gb202`, JSON, manifest, or schema member |
| `cecomp.bin` / `cuda.bin` | 1 / 270 gzip-tar members | No relevant member name |
| `nvlinktopofiles.bin` / `vktextures.bin` | 25 / 177 gzip-tar members | No relevant member name |
| Outer `nvdec.bin` | 38 tar members | Video bitstreams only; no relevant member |
| Outer `nvofa.bin` | 18 gzip-tar members | Optical-flow image data only; no relevant member |
| Outer `nvjpg.bin` | 14 gzip-tar members | JPEG/MJPEG vectors only; no relevant member |
| Outer `gldGB202.bin` | 1,081,608-byte unrecognized data file | Strings are GB202 graphics/display test names; no exact fuse/schema marker |

The Python TBZ contains a small number of ordinary third-party wheels/test
archives (pip, setuptools, image/test data, timezone data). They were identified
by member name but not recursively unpacked; none is named for NVIDIA, GB202, or
FuseSpec. This is included as a negative-search boundary rather than treated as
an absolute content proof.

Outer metadata files do not fill the gap:

- `manifest_secondary.json` contains platform variables and a PCI port map;
- `core/mods0/NVSpecsData.json` contains board/device/test properties;
- `.checksum.db` is a 20,480-byte SQLite database with checksum tables and no
  exact `gb202_f`/fuse-spec string hit;
- `.nautilus.config` and `configs/manifest.json` are opaque encrypted tokens.
  They were not decrypted. Their opacity means external staging cannot be
  excluded, but they are not archive members named as a fuse database.

An exact plaintext scan across all 133 extracted MODS payload nodes for
`gb202_f.json`, quoted `Chip_options`, quoted `jtagConfigFields`, quoted
`fuselessFuse`, or `OPT_L2SLICE_FBP0_DISABLE` returned only the `mods` ELF. A
project-wide filename search found no `gb202_f.json`, `*_f.json`, `*_fpf.json`,
or `*_POR.json` file.

## What `SetSwFuses` still needs to resolve the L2 raw masks

### Descriptor-resolution gap

For the stock upper-case name entry, a trustworthy main database must make the
following eight names resolvable:

```text
OPT_L2SLICE_FBP0_DISABLE ... OPT_L2SLICE_FBP7_DISABLE
```

The recovered parser/encoder model says each corresponding `Chip_options`
record must provide, at minimum:

- the exact name as the object key;
- `bits` (the recovered GB202 L2 model expects 8);
- `type` (the direct encoder special-cases lower-case `dis`);
- `offset` (the direct-writer ABI requires the domain-relative raw OPT family
  `0x000034e0 + 4 * FBP`, ending at `0x000034fc`; the GB202 domain-5 wrapper
  then adds a separately resolved base. Its fixed-selector instance-0 fallback
  is `0x00820000`, yielding `0x008234e0 + 4 * FBP`; if PTOP DeviceInfo2 class
  `0x10` is populated, the runtime base instead comes from that hardware
  record's instance-0 `devicePriBase`);
- `customer_visible`, which the parser requires even though the direct encoder
  does not use it as a write-permission gate;
- the valid surrounding main-file header and `options` containers needed for
  `FuseJsonParser2` to accept the document.

The exact values above are a recovered ABI model corroborated by RegHal,
encoder, and domain-wrapper behavior, not a substitute for the missing
authentic file. Parser and encoder transparently preserve the integer; the
authentic database is still needed to observe independently that NVIDIA's
record uses the required relative value and to confirm the descriptor
type/width association and generation-specific metadata. This audit did not
create a synthetic GB202 file.

### Items that are **not** required for this exact lookup

- `_POR.json` and `_fpf.json`: optional companions, not the main name database.
- IFF `chainId/blockIndex/blockOffset/lsbIndex/msbIndex`: required for the
  separate fuseless/IFF encoder, not for the direct raw-shadow plan produced by
  ordinary `SetSwFuses`.
- The compiled tag labels: useful for human topology naming only.
- A `SetOverrides` record: it changes an existing name's value but cannot
  create the missing descriptor.

### Resolution success is not programming authorization

Supplying the authentic descriptor file would only close host-side name lookup
and plan construction. It would not satisfy MODS's separate NVIDIA-network
security level, device PLMs, latch/override state, firmware acceptance,
reset/reinitialization behavior, rollback, or disabled-unit health. No
authorization file, credential, or live invocation was sought or constructed
in this inventory.

## Public-index negative result supplied by the parent audit

The parent audit reported that, on 2026-07-21, exact public searches for
`"opt_l2slice_fbp0_disable"`, `"gb202_f.json"`, and
`"FLOORSWEEPING_ALLOW_INB_ONE_SHOT"` produced no relevant result. The query
`"0x8200dc" NVIDIA` produced only an unrelated DVB-driver address hit. This
worker did not perform those network searches.

These results mean only that the exact literals were absent from the consulted
public indexes at that time. They do not prove that the file never existed, is
not private, or cannot appear under a different name/encoding.

## Negative-search boundary

The strongest supported wording is:

> No addressable or recognizably archived GB202 fuse descriptor/schema is
> present in the inspected MODS 570.151 manufacturing package. The executable
> contains the parser, default filename, tag names, and independent RegHal
> metadata, but the authentic `gb202_f.json` body remains externally missing.

The following stronger claims are **not** supported:

- “NVIDIA never shipped or possesses `gb202_f.json`.”
- “No encrypted/custom-packed byte sequence anywhere in the package could
  encode equivalent data.”
- “The encrypted Nautilus manifest cannot arrange private runspace staging.”
- “A fabricated minimal JSON is operationally equivalent to the authentic
  database.”
- “Name resolution alone makes L2 raw-mask programming authorized or safe.”

Resource boundary: searches were confined to
`/home/user/rt_5090_project`, the named ZIP/TBZ/TGZ/archive members, decoded JS,
the extracted MODS payload, exact string scans, `readelf`, and small byte
windows. No unrelated home-directory recursion, full disassembly, GPU access,
MODS execution, or network access was performed.

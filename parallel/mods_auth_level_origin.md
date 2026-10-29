# MODS 570.151 `SecurityUnlockLevel` origin and lifecycle audit

## Scope and evidence rules

This is a bounded, static audit of the extracted Linux MODS executable. It answers where native security levels 1–5 come from, when they are established, and whether the stock path is a name check, remote authorization, a signed credential, a build constant, or a GPU/firmware result.

No MODS executable was run. No NVIDIA endpoint was contacted. No GPU, driver, BAR, MMIO, VBIOS, GSP, FSP, or fuse state was read or written. The audit used `readelf`, `objdump`, string and decoded-JavaScript searches, whole-`.text` raw xref/call scans followed by small-window disassembly validation, and `openssl x509` on the bundled CA file.

Labels used below:

- **FACT** — directly established in this exact artifact.
- **INFERENCE** — the most economical interpretation of facts, but not itself encoded as a literal statement.
- **UNKNOWN** — not closed by the available static artifact.

## Artifact identity and address basis

- **FACT:** Executable: `mods_audit/static/extracted_inner/mods`.
- **FACT:** SHA-256: `c30461e21dfcd8a27687481f9618206d4291c0b3e24f039d270dec944c06c7bf`.
- **FACT:** It is a stripped x86-64 ELF. `.text` is VA `0x4a0940`, file offset `0x0a0940`, size `0x8736b3a`; for file-backed text/rodata in this image, VA minus file offset is `0x400000`.
- **FACT:** `.bss` is VA `0x17a2a480`, size `0x119b830`. The security-level fields discussed below are in `.bss`, so they have zero-filled process-start state rather than an on-disk initialized value.
- **FACT:** Bundled CA: `mods_audit/static/extracted_inner/HQNVCA121-CA.crt`, SHA-256 `60936cd6362ad895a1cc40e523b0c4548fa808a9df8d8db4522fd222b5138088`.

## Bottom line

- **FACT:** `SecurityUnlockLevel` is a host-process dword at `0x186d6f74`. It is not a GPU register, fuse value, VBIOS field, GSP reply, or FSP reply.
- **FACT:** The only established direct setter invocation in the complete executable `.text` is the startup argument/parser path at `0xbb5f3b`. It passes a locally computed file result into the setter; the setter may then run a cached NVIDIA-network certificate test.
- **FACT:** Level 4/5 is not read from a server response. MODS computes it locally from two inputs: a `-b` bypass-file classification and a Boolean result from TLS validation against one of eight NVIDIA authentication hosts.
- **FACT:** JavaScript can read `SecurityUnlockLevel`, but the native binding has no setter callback. The decoded bundled JavaScript only consumes the value.
- **FACT:** There is no ordinary stock numeric CLI, JavaScript, environment, `.arg`, or `.spc` setting that directly selects level 4 or 5 in the audited package.
- **UNKNOWN:** How an authorized user obtains a legitimate `-b` file. The executable accepts such records, but this package contains no candidate record and no enrollment, issuance, account, or download workflow.

In plain language: MODS decides the level once near startup. It first classifies any vendor-provided bypass files, then optionally asks, “Can I reach an NVIDIA auth host and validate its certificate against the bundled NVIDIA CA?” The server does not send back “level 4” or “level 5”; the executable turns those local facts into the number.

## 1. Native storage, getter, setter, and complete direct-xref result

### Backing fields

- **FACT:** Level dword: `0x186d6f74`.
- **FACT:** “NVIDIA network detected” byte: `0x186d6f71`.
- **FACT:** Setter body: `0xd5d5d0`; public trampoline: `0xd53520`.
- **FACT:** Level getter body: `0xd5d660`; public trampoline: `0xd53530`.
- **FACT:** Network-byte getter: `0xd5d670`.
- **FACT:** Boolean “level greater than 3” predicate: `0xd5d680`.

### Whole-`.text` reference audit

A complete raw scan of `.text` for RIP-relative references to `0x186d6f74`, followed by disassembly validation of every candidate, found:

- **FACT:** Stores at `0xd5d5d5` (write 1), `0xd5d5fb` (write setter input), and `0xd5d631` (write combined result).
- **FACT:** Loads/tests at `0xd5d660` (getter), `0xd5d680` (`> 3` predicate), and a cold exception/logging path at `0x4b8001`.
- **FACT:** References to `0x186d6f71` are the writes at `0xd5d5f4` (false) and `0xd5d619` (true), plus the getter load at `0xd5d670`.
- **FACT:** A complete raw scan of direct x86 `E8 rel32` calls found exactly one direct call to the setter trampoline: `0xbb5f3b -> 0xd53520`. It found no direct call to the setter body.
- **FACT:** Exact 4-byte and 8-byte pointer scans found no stored pointer to the setter body, setter trampoline, getter body, or getter trampoline.
- **UNKNOWN:** Static scanning cannot exclude self-modifying code, a runtime-created function pointer, or an unexamined externally loaded module. None is established in this artifact, so it would be unjustified to claim a second stock setter path.

### Lifecycle

- **FACT:** The dword begins as zero-filled `.bss`; setter entry immediately writes level 1 at `0xd5d5d5` before doing any network work.
- **FACT:** The startup parser calls the setter once at `0xbb5f3b`, then immediately reads the result through `0xd53530` at `0xbb5f40`.
- **FACT:** No later direct clear, downgrade, or revalidation store to the level dword exists in `.text`.
- **FACT:** Network detection caches “completed” at `0x18bc55a8` and its Boolean result at `0x18bc5628`.
- **INFERENCE:** Under the established stock path, the level lasts for the MODS process lifetime. A new process reruns parsing and network detection; the current process does not periodically refresh the level.

## 2. Setter state machine

The setter at `0xd5d5d0..0xd5d666` behaves as follows.

- **FACT:** It first stores 1 into `0x186d6f74`.
- **FACT:** It calls `0x8ba7250(input > 3)`. That helper only stores a byte at `0x18bc5090`; it is not network authentication and is not a second security-level setter. The byte gates an internal formatted-output path beginning at `0x8ba8160`.
- **FACT:** It calls `0xbb1fe0`, which tests the exact CLI switch `-no_net` (string VA `0x90b5ca3`).
- **FACT:** With `-no_net`, it stores network=false and preserves the caller's input as the final level.
- **FACT:** Otherwise it calls the cached detector at `0x8ba8960`. Network failure stores network=false and preserves the input.
- **FACT:** Network success stores network=true and transforms inputs 1/2/4 to 4, input 3 to 5, and inputs greater than 4 remain unchanged.

For the named 1–5 values, the exact transition is:

| Setter input | `-no_net` or network failure | Valid NVIDIA-network result |
|---:|---:|---:|
| 1 | 1 | 4 |
| 2 | 2 | 4 |
| 3 | 3 | 5 |
| 4 | 4 | 4 |
| 5 | 5 | 5 |

- **FACT:** `-no_net` does not create level 4. It only suppresses the network probe and retains whatever the bypass-file parser already produced.
- **FACT:** Network success plus an ordinary unexpired level-3 record produces level 5. Network success plus a special level-4 record remains level 4.

## 3. Native names and JavaScript exposure

### Enum names and values

The executable registers these numeric constants:

| Value | Native name | String VA |
|---:|---|---:|
| 1 | `SUL_NONE` | `0x90c8278` |
| 2 | `SUL_BYPASS_EXPIRED` | `0x90c8265` |
| 3 | `SUL_BYPASS_UNEXPIRED` | `0x90c8250` |
| 4 | `SUL_NVIDIA_NETWORK` | `0x90c823d` |
| 5 | `SUL_NVIDIA_NETWORK_BYPASS` | `0x90c8223` |

- **FACT:** The constant registrations at `0x7a4e62..0x7a4f9d` load doubles 5, 4, 3, 2, and 1 from rodata and bind the names above.

### Read-only property

- **FACT:** Registration at `0x7a4e23..0x7a4e49` binds the name `SecurityUnlockLevel` (VA `0x90c81f9`) with getter callback `0xd56f00` and `r8 = 0` for the second callback.
- **FACT:** The registration constructor at `0xc026a0` stores `rcx` at object offset `+0x20` and `r8` at `+0x28`; therefore this binding has a getter pointer and a null setter pointer.
- **FACT:** Getter callback `0xd56f00` calls the native getter trampoline at `0xd56f19` and publishes its numeric return to JavaScript.
- **FACT:** A search of all decoded bundled JavaScript found many comparisons/reads of `SecurityUnlockLevel`, but no assignment to it. Comparisons using `===` were excluded from the assignment test.
- **INFERENCE:** Bundled JavaScript is a policy consumer, not the authority source.

## 4. `-b` bypass-file parser

### CLI entry and file shape

- **FACT:** Startup function `0xbb5940..0xbb7550` looks up the exact argument `-b` at `0xbb5ab0..0xbb5abe`. The help table describes it as “bypass file name” (file offset `0x8cb6054`).
- **FACT:** The lookup returns a collection and the parser iterates all supplied candidates; repeated `-b` inputs are supported by this path.
- **FACT:** Each candidate is opened in binary-read mode (`"rb"`, VA `0x90b59e1`) and must have exact size `0x10` bytes (`0xbb5b5d..0xbb5b66`).
- **FACT:** It performs three reads at `0xbb6098..0xbb6104`: 4 bytes, 4 bytes, and 8 bytes.
- **FACT:** It applies bitwise NOT to all three fields at `0xbb6112..0xbb6121`, then compares the first two fields with embedded constants at `0x92592b8` and `0x92592b4`.
- **FACT:** This report intentionally does not reproduce a record-construction recipe or the embedded constant values; those are unnecessary to establish the legitimate stock lifecycle.

### Classification

- **FACT:** An invalid/open/size/read/first-field failure yields level 1.
- **FACT:** A matching special second-field value jumps to `0xbb7370`, sets a process byte at `0x17a3dfb5`, and yields level 4.
- **FACT:** Otherwise `0xb9de50 -> 0xb6bbe0` obtains realtime and computes milliseconds. If current time is before the decoded 64-bit timestamp, the record yields level 3 at `0xbb6156`; otherwise it yields level 2 at `0xbb740d`.
- **FACT:** Combining multiple records is normally a maximum operation, except one level-4 record plus one level-3 record, in either order, yields aggregate level 5 (`0xbb5ba0..0xbb6026`).
- **FACT:** The aggregate in `r13d` is passed to the sole setter call at `0xbb5f38..0xbb5f3b`.

### What the parser does not do

- **FACT:** The parser performs fixed-size reads, inversion, equality checks, and a wall-clock comparison. Within this parser there is no public-key signature, MAC, hash, certificate, account, password, or network verification call.
- **FACT:** Bitwise NOT is reversible encoding, not cryptographic authenticity.
- **FACT:** There is no `getenv` call in the startup parser window, and a bounded string scan found no MODS/NVIDIA auth or bypass environment-variable name tied to this path.
- **FACT:** Response-file handling exists elsewhere in startup parsing (for example local `init.arg` contains `@dev.arg`). That only forwards arguments to this same parser; it is not an independent authority or credential source.
- **FACT:** A scan of the extracted package's top-level `.arg`/`.spc` files found no `-b` or `-no_net`. A scan of the extracted package found no regular file of exactly 16 bytes.
- **UNKNOWN:** Who issues a legitimate record, how identity or entitlement is checked before issuance, how it is transported, and whether NVIDIA relies on operational secrecy/controlled distribution rather than cryptographic verification inside MODS.

## 5. NVIDIA-network detector and TLS path

### Hosts, concurrency, and caching

- **FACT:** The endpoint table at VA `0x1762e660` contains eight host pointers:

  - `hqnvmodsauth01.nvidia.com` through `hqnvmodsauth04.nvidia.com`
  - `rnnvmodsauth01.nvidia.com` through `rnnvmodsauth04.nvidia.com`

- **FACT:** Detector `0x8ba8960` creates one worker state for each of the eight hosts. Worker `0x8ba6660` calls `0x8bc0bf0(host)` and sets shared success byte `0x18bc5628` if any host succeeds (`0x8ba670a..0x8ba670e`).
- **FACT:** The detector waits up to `0x2540be400` nanoseconds, i.e. 10 seconds, and then marks the cached check complete at `0x18bc55a8`.
- **FACT:** Subsequent detector calls return the cached Boolean rather than repeating the eight-host check.

### Certificate validation chain

The worker's relevant call chain is `0x8ba6660 -> 0x8bc0bf0 -> 0x8bc1770 -> 0x8bc1b70`.

- **FACT:** TLS routine `0x8bc1b70` constructs the literal filename `HQNVCA121-CA.crt` (VA `0x923c330`) and passes it through the package's file-resolution/loading helper.
- **FACT:** It appends `:443` to the selected endpoint (VA `0x920a73f`).
- **FACT:** It configures cipher text `DEFAULT:@SECLEVEL=0` (VA `0x920a744`). This lowers OpenSSL's cipher-policy floor for compatibility; it does not by itself make the later peer-chain result succeed.
- **FACT:** The mapped OpenSSL dispatch calls enable peer verification, set SNI from the selected host, perform the TLS handshake, and obtain the peer certificate.
- **FACT:** It converts issuer information to text and requires both `DC=nvidia` (VA `0x920a758`) and `CN=HQNVCA122-CA` (VA `0x920a762`) at `0x8bc1e96` and `0x8bc1eb6`.
- **FACT:** It then checks the OpenSSL verification result at `0x8bc1ef1..0x8bc1ef7`; only zero proceeds to the success log at `0x90ad9c8`: “X509 certificate verified, executing on the nvidia network”.
- **FACT:** The bundled root is self-signed `CN=HQNVCA121-CA`, RSA 4096, RSASSA-PSS/SHA-256, valid 2016-10-13 through 2036-10-13, SHA-256 fingerprint `F1:57:17:70:EB:DA:BE:7C:42:AE:CC:C4:D4:A9:65:1C:4A:1A:81:93:3A:02:46:D2:67:97:35:05:71:75:48:72`.
- **INFERENCE:** `HQNVCA122-CA` is an NVIDIA intermediate issuer under the bundled `HQNVCA121-CA` trust anchor.

### What is and is not remotely authorized

- **FACT:** In the actual auth-worker call chain above, success is a TLS/certificate Boolean. No account/password, HTTP request body, token, entitlement record, or server-returned numeric level is consumed before success.
- **FACT:** Generic HTTP-building code and strings exist nearby in the executable, but the auth worker calls the simpler `0x8bc0bf0 -> 0x8bc1770 -> 0x8bc1b70` certificate path, not that generic HTTP transaction path.
- **FACT:** A bounded dynamic-symbol/string audit found no `SSL_set1_host` or `X509_VERIFY_PARAM_set1_host`, and no independent hostname-verification step was observed in this call chain. SNI, chain verification, and the explicit issuer tests are present.
- **UNKNOWN:** Whether a dynamically resolved OpenSSL wrapper performs additional hostname checks not recognizable from the stripped static call sites. The evidence supports no such claim.
- **INFERENCE:** This is remote PKI-backed network-location/reachability attestation, not a service that assigns a per-user numeric authorization level.
- **FACT:** Merely changing a hostname or DNS answer is not sufficient for the stock path: the peer certificate must also validate to the bundled CA and satisfy the issuer-string checks.

## 6. Classification of the authority mechanism

| Candidate mechanism | Result | Evidence |
|---|---|---|
| Executable filename / host computer name check | **No evidence; effectively rejected for this path** | Setter inputs come from the `-b` parser and TLS Boolean; neither path checks the executable's filename or machine hostname. |
| Build-time level constant | **No** | Backing dword is zero-filled `.bss`; startup setter writes 1 and computes the final value at runtime. |
| GPU/VBIOS/GSP/FSP authorization result | **No** | Entire level computation is host-side startup code and finishes before privileged GPU routines consume the getter. |
| Remote authentication | **Yes, narrowly** | TLS server-chain/issuer validation against NVIDIA hosts yields a Boolean “NVIDIA network” result. |
| Remote service returning level 4/5 | **No** | The setter maps a local Boolean plus parser input to 4/5; no remote numeric value is read. |
| Cryptographically signed `-b` credential | **No verification in the examined parser** | Fixed 16-byte record, reversible NOT encoding, embedded comparisons, and time check; no signature/MAC/hash verification. |
| Controlled vendor credential | **Plausible but provenance unknown** | Native help and enum names explicitly support bypass files, but issuance/distribution is absent from the package. |
| JavaScript/config/environment numeric override | **No stock path found** | Native JS property has a null setter; decoded JS only reads it; parser has no auth `getenv`; bundled `.arg`/`.spc` files contain no auth switches. |

## 7. Legitimate stock-path closure

“Closed” here means the executable-side conditions are known. It does not mean the required NVIDIA network access or vendor-issued files are available to this machine.

### Level 4 through NVIDIA network

1. **FACT:** Parser aggregate begins at ordinary level 1 (or may be expired level 2).
2. **FACT:** `-no_net` must be absent.
3. **FACT:** At least one of the eight hosts must complete the certificate path within the detector's wait window.
4. **FACT:** The setter converts input 1 or 2 plus network=true to level 4.

This route is mechanically closed in the binary. Whether the hosts are publicly routable, restricted to NVIDIA internal DNS/routes, or currently alive is **UNKNOWN** because no network contact was made.

### Level 3 through an ordinary unexpired bypass file

1. **FACT:** `-b` names an exact 16-byte record accepted by the parser.
2. **FACT:** Its decoded timestamp is later than current realtime.
3. **FACT:** With no successful network result, the setter retains level 3.

The parser side is closed. Legitimate acquisition/provisioning of such a file is **UNKNOWN**.

### Level 5

There are two stock computation routes:

- **FACT:** One accepted unexpired level-3 record plus network=true is converted to level 5 by the setter.
- **FACT:** One special level-4 record plus one unexpired level-3 record, supplied as repeated `-b` inputs, is combined to level 5 by the parser before the setter. With `-no_net` or network failure, setter input 5 remains 5.

A special level-4 record by itself plus network=true remains level 4; the “bypass” component represented by level 3 is what produces the network+bypass name at level 5.

### Level 4 through the special bypass record

- **FACT:** A record matching the parser's special second-field constant produces input level 4 even without network success; `-no_net` merely retains that already-produced input.
- **UNKNOWN:** The legitimate NVIDIA issuance and entitlement policy for this special record.

## 8. Remaining unknowns and safe next evidence

- **UNKNOWN:** The authorized issuance tool/service and lifecycle for both timed and special bypass records.
- **UNKNOWN:** Whether endpoint reachability requires NVIDIA corporate DNS, VPN, source-network controls, or only possession of a certificate-valid server endpoint.
- **UNKNOWN:** Live endpoint availability and current certificate chain. This audit intentionally did not contact them.
- **UNKNOWN:** Whether a separate NVIDIA package contains an enrollment client or signed wrapper around the otherwise unsigned 16-byte record.

Safe follow-up evidence would be documentary or static: authentic NVIDIA MODS manuals, packaging manifests, internal deployment documentation supplied by an authorized owner, or another version's parser for comparison. This report does not propose binary patching, memory writes, forged records, fake certificates/DNS, or authentication evasion.

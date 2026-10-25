# GB202 L2 re-enable: parallel work contract

## Objective

Determine whether the L2 units reported as disabled in prior GB202 work can be
enabled selectively and reversibly, with emphasis on the current 610.43.03
Blackwell stack.  Historical PMU material is background only and must not become
the primary line of investigation.

Archived NCU data directly proves 96 MiB L2, 8 FBPs, 96 NCU `l2s` attributes,
and 48 anonymous LTS rollup domains at the time of capture.  Earlier work also
reported 16 LTCs and the same effective enable/disable pattern (`0xed`/`0x12`)
on all eight FBPs, with software masks zero, but the raw stdout/register dump
for that observation was not retained.  It is therefore `REPORT-ONLY`, not a
current or independently replayable runtime fact.  Conditional on that report
being accurate, the accounting model is 16 disabled 2-MiB mask units (32 MiB),
and the regular pattern favors SKU floor-sweeping while still allowing a
separate defect/repair map.

## Known modern register chain

- raw OPT/shadow physical family / fixed-selector fallback result:
  `0x8234e0 + 4 * FBP`
- direct-writer descriptor/plan offsets: `0x34e0 + 4 * FBP`; the domain-5
  wrapper adds a separately resolved base. GB202 PTOP raw device type `0x22`
  maps to internal class `0x10`. An empty class vector uses the instance-0
  fixed-selector fallback `0x820000`; a nonempty vector must contain an exact
  instance-0 record, otherwise MODS reaches its unsafe no-match path instead
  of falling back
- software masks: `0x822080 + 4 * FBP`
- effective masks: `0x822900 + 4 * FBP`
- fuse status: `0x820d70 + 4 * FBP`
- fuse latch: `0x820040.bit0`
- software-override control: `0x8212ac.bit0`
- L2 PLM: `0x8200dc`
- latch/fuse-security PLM: `0x8200f8`

## Existing high-confidence static findings

- The local MODS 570.151 sample contains the direct writer chain:
  `NewFuse.SetSwFuses -> SetSwFusesCore -> ProgramSwFusePlan`.
- Its host algorithm requires security-unlock level above 3, attempts the
  latch-set request, applies one or more raw-plan values, and on aggregate
  success enters reset/reinitialization.  The latch/write returns are not
  checked directly, and readback sentinel `0xbadf510c` logs without setting
  the aggregate error.
- The direct writer is non-transactional: neither its normal success tail nor
  its failure cleanup performs rollback or latch clear.  A separate current
  GB20x `PrepareResense` path does clear the latch before a fuse reset, but it
  is not direct-writer rollback and is intended to re-adopt physical-fuse
  topology.
- Modern HULK uses signed/device-bound authorization over NVDM type `0x11`.
- **FACT:** FSP task2/subobject1 first requires cached QCAP key `0x13`
  presence and then returns one synchronous command status; neither result is
  a credential or PLM snapshot.
- **RUNTIME FACT:** in the isolated VFIO VM, direct task2/subobject1 with a
  six-byte zero payload was accepted by retail GB202 FSP and changed
  `0x8200d0/0x8200dc` from `0xfffffb8f` to `0xfffffbff`.
- **RUNTIME FACT:** the same run did not change `0x8200f8`; latch-request writes
  still did not stick, and direct f8 write/readback of `0xfffffbff` still read
  back as `0xfffffb8f`.
- **RUNTIME FACT:** sibling security PLM-like words `0x8200e0/0x8200f4` also
  rejected direct nibble-open write/readback (`0x00800bff` read back as
  `0x00800b8f`).
- **RUNTIME FACT:** with `0x8200dc` already open, a bounded FBP0 raw-shadow
  clear-then-restore probe still could not change `0x8234e0`; attempted
  `0x10` read back as `0x12`.
- **RUNTIME FACT:** a repeated bounded `0x8200f8` open-then-restore probe read
  back the old value immediately, left all L2/PLM/latch masks unchanged, left
  FSP MNOC mailbox ERR bits clear, and produced no new guest Xid/AER/FSP/GSP
  kernel-log error. Current host-visible behavior is silent reject/drop.
- **STATIC FACT:** four local GB202 ROM/NVFW samples contain no plaintext/literal
  `0x8200f8`, `0x8200dc`, `0x8200d0`, `0x820040`, `0x8234e0`, `HULK`, `PLM`,
  `PRIV`, or `fuse` hits; only the private `FSP_RUN` tag appears. GeForce and
  RTX PRO 6000 `FSP_RUN` envelopes differ, but the object is hash-covered and
  not a plaintext policy table.
- **STATIC FACT:** current GSP contains FWSECLIC/HULK error strings including
  `VBIOS_VERIFY_HULK_*` and certificate register-override/readback errors, but
  the `VBIOS_VERIFY_HULK_*` xrefs found in this pass land in an error-code
  formatter window, not a proved GB202 VBIOS-HULK verifier path.
- **STATIC FACT:** `RmActivateHulk`, `RMHulkCertSize`, and `RMHulkCert` are real
  GSP-side configuration inputs for the HULK path. Public 610 host code routes
  HULK NVDM type `0x11` to FSP SEID 0 on GB202, but does not expose the signed
  payload schema, accepted register ranges, or PLM lowering/restore semantics.
- **STATIC FACT:** direct MODS calls into the common FSP sender expose task IDs
  `1/2/3/4/8/13` only; no separate direct high-numbered task was found for
  `0x8200f8` or L2 raw/effective masks.
- **STATIC FACT:** MODS has two task13/subobject2 paths. The generic PRC knob
  writer at `0x185f299` sends once and reads back old/new knob value. A separate
  special helper at `0x1258756/0x12587a8` is two-phase: after a successful first
  send, byte 0 of the same payload is changed from `0x00` to `0x06` and sent
  again as `task13/subobject2`.
- **STATIC FACT:** task8/subobject1 is tied to FSP fusing-mode strings and is
  not currently a safe runtime L2-unlock candidate.
- **UNKNOWN:** production-GB202 f8/latch consumer, permission lifetime across
  reset, and whether any legitimate HULK/task/firmware path can open f8.
- MODS' process-local `SecurityUnlockLevel > 3` entry check is orthogonal to
  both the FSP protocol checks and the device PLM state.
- Old 390.67 PMU/HULK material only establishes historical Type-7 RMW semantics;
  it cannot prove Blackwell behavior and should not receive more effort unless a
  current 610 cross-reference explicitly requires it.

## Absolute safety rules

The bullets below are the original desktop-on-5090 static-audit rules. Later
runtime work was separately moved into the isolated VFIO VM and is recorded in
`vm_mods_lab/*_20260722.md`.

- Never execute MODS or any downloaded NVIDIA diagnostic binary.
- Never load a new kernel module or rerun `permission_state_readonly_probe`.
- No BAR0/MMIO/PCI config/debugfs reads or writes, even reads.
- No GPU reset, FLR, SBR, PCI unbind/rebind, module unload, GSP reset, or reboot.
- No VBIOS/FSP/GSP flashing, clock, voltage, power or persistence-mode changes.
- No root escalation.
- The desktop is running on the RTX 5090.  Do not disrupt it.
- Only official high-level read-only interfaces (`nvidia-smi`, NVML, ordinary
  sysfs identity/status files) may be queried by the hardware task, and only when
  the same fact is not already present in saved output.
- Do not issue undocumented internal RM/FSP requests to live hardware.

## Resource rules

- No Ghidra, radare analysis database, full-binary decompilation, or whole-file
  disassembly.
- Use bounded `objdump`/Capstone windows, `readelf`, `nm`, `rg`, and small scripts.
- Stream output; do not retain multi-megabyte disassembly text.
- One potentially heavy process at a time per task, with a memory ceiling of
  roughly 384 MiB and a timeout.
- Do not recursively scan unrelated home-directory trees.

## Completed platform-agent reports

- Isolated-VM runtime FSP/MNOC and BAR0 probe reports:
  `vm_mods_lab/fsp_prc_read_direct_result_20260722.md`,
  `vm_mods_lab/fsp_caps_query_result_20260722.md`,
  `vm_mods_lab/fsp_prc_write_noop_result_20260722.md`,
  `vm_mods_lab/fsp_task2_zero_result_20260722.md`,
  `vm_mods_lab/bar0_write_probe_20260722.md`,
  `vm_mods_lab/f8_write_status_probe_20260722.md`
- Bundled HULK sample-certificate inventory:
  `parallel/hulk_sample_cert_inventory_20260722.md`
- MODS FSP sender callsite inventory:
  `parallel/mods_fsp_sender_callsite_inventory_20260722.md`
- Current 610 FSP/SEC2 routing:
  `parallel/gb202_610_arch.md`
- Evidence provenance and contradiction audit:
  `parallel/evidence_audit.md`
- L2 isolation, repair, and safe observability audit:
  `parallel/l2_safety_observe.md`
- Final MODS permission/sequencing cross-check:
  `parallel/mods_final_crosscheck.md`
- Final current-GSP repair binding cross-check:
  `parallel/repair_final_crosscheck.md`
- Main-document post-merge stale-claim audit:
  `parallel/main_doc_stale_claims.md`
- Current post-merge evidence-level and cross-section consistency audit:
  `parallel/postmerge_consistency_20260721.md`
- DeviceInfo2/QCAP and host/FSP/PLM terminology consistency audits:
  `parallel/deviceinfo_qcap_consistency.md`,
  `parallel/permission_reports_consistency.md`
- FSP task-2/PRC/f8 lifecycle audit:
  `parallel/task2_lifecycle_audit.md`,
  `parallel/task2_auth_provenance.md`,
  `parallel/qcap13_semantics.md`,
  `parallel/qcap_cache_lifetime.md`
- PRC auto-injection negative audit:
  `parallel/prc_autoinject_audit.md`
- Corrected PRC knob-record layout and `0x1d` ID audit:
  `parallel/prc_knob_metadata.md`,
  `parallel/prc_id_correction_map.md`
- Public 610.43.03 PRC `0x1d`/task-2 boundary audit (report filename retains the
  earlier ID before record-boundary correction):
  `parallel/prc_1c_public_audit.md`
- PRC-read host reset/data-flow audit and independent cross-check:
  `parallel/prc_read_noreset_audit.md`,
  `parallel/prc_read_noreset_crosscheck.md`
- PRC-read/full-init task-2 avoidance audit:
  `parallel/prc_read_task2_avoidance.md`
- Current GSP private `+0x318` fuse-base getter provenance:
  `parallel/gsp318_private_provenance.md`
- Current GSP `0x8200f8` literal/table-flow negative audit and the direct
  block's GB202 binding correction:
  `parallel/gsp_f8_tableflow.md`,
  `parallel/gsp_f8_consumer_lifecycle.md`
- Independent 610.74 GSP cross-version `0x8200f8` check:
  `parallel/gsp_61074_crosscheck.md`
- MODS host `SecurityUnlockLevel` origin/lifetime audit:
  `parallel/mods_auth_level_origin.md`
- GB202 `disable_sw_override` source/readers/reset-lifecycle boundary:
  `parallel/disable_sw_override_lifecycle.md`
- PRC `0x1d` value/default/one-shot consumption boundary audit:
  `parallel/prc_1d_value_semantics.md`,
  `parallel/prc_1d_domain_followup.md`,
  `parallel/prc_1d_stale_reference_audit.md`,
  `parallel/tmux_prc1d_consumer_refresh.md`
- FSP task-2 consumer/material-classification follow-up:
  `parallel/fsp_task2_consumer_followup.md`,
  `parallel/tmux_task2_artifact_inventory.md`
- Direct-shadow reset/resense lifecycle and post-reset verification boundary:
  `parallel/shadow_reset_lifecycle.md`,
  `parallel/effective_mask_boot_lifecycle.md`
- Per-reset-type latch/raw/status/effective lifecycle matrix and public GB202
  SBR/FSP-boot boundary:
  `parallel/shadow_reset_domains.md`
- Raw OPT A to effective LTS B visible-software propagation boundary:
  `parallel/raw_effective_propagation.md`,
  `parallel/effective_setter_provenance.md`
- Direct-shadow request-2 reset-selection inputs, setter, backend, and query
  boundary:
  `parallel/reset_selection_inputs.md`,
  `parallel/coupling_gate_semantics.md`,
  `parallel/reghal_override_lifecycle.md`
- GB202 `OBJGPU+0x668` reset-coupled getter binding, persistent replay, and
  independent path/address cross-check:
  `parallel/reset_coupled_binding_replay.md`,
  `parallel/gsp_objgpu_668_replay.py`,
  `parallel/gsp_objgpu_668_replay.results.txt`,
  `parallel/objgpu_668_independent_check.md`,
  `parallel/reset_getter_internal_fields.md`,
  `parallel/reset_getter_guard_provenance.md`,
  `parallel/coupling_setter_crosscheck.md`,
  `parallel/base_coupling_visibility.md`
- NVIDIA official upstream 610 release/reset-schema version cross-check:
  `parallel/upstream_610_reset_crosscheck.md`
- NVIDIA R580.126.09 FSP/RESET-PLM product, owner, and GB202 coupling scope:
  `parallel/official_fsp_plm_scope.md`
- GB202 GSP-offload routing and effective-topology semantics for L2 GET controls:
  `parallel/gb202_getfsinfo_support.md`
- Minimal MODS-free RM client/object/ABI path for an effective LTS-mask baseline:
  `parallel/getfs_client_path.md`
- MODS built-in aggregate/per-slice L2-test support boundary:
  `parallel/mods_l2_test_boundary.md`,
  `parallel/newcudal2mats_native.md`
- Complete local archive inventory for the missing GB202 fuse descriptor:
  `parallel/gb202_fuse_descriptor_inventory.md`
- Per-FBP raw-mask encoding, capacity-accounting, and physical-identity
  granularity audit:
  `parallel/l2_mask_granularity.md`,
  `parallel/l2_mask_constraint_audit.md`
- Streaming/low-memory regression for the offline GB202 RegHal decoder:
  `parallel/gb202_reghal_streaming_regression.md`
- Raw writer / ordinary RegHal transport and error-propagation boundary:
  `parallel/reghal_writer_transport.md`
- L2 raw/latch PLM field layout, host diagnostic behavior, and stock lowering
  caller boundary:
  `parallel/l2_plm_static_permissions.md`
- Process-global exact-address remap initialization, sole visible setter source,
  and stock/default identity boundary:
  `parallel/reg_remap_lifecycle.md`
- Raw writer exclusion-mask policy and descriptor/plan/domain offset
  representation:
  `parallel/raw_filter_targets.md`,
  `parallel/descriptor_offset_semantics.md`,
  `parallel/fuse_domain_instance.md`,
  `parallel/fuse_instance_map_lifecycle.md`,
  `parallel/deviceinfo_instance_nomatch.md`,
  `parallel/deviceinfo_cache_writer_timing.md`,
  `parallel/deviceinfo_class10_identity.md`,
  `parallel/deviceinfo_instance_invariant.md`,
  `parallel/postreset_deviceinfo_cache_lifetime.md`,
  `parallel/deviceinfo_reset_stability.md`
- `UseRmRegOps` / RM-ready lifecycle and GB202 special-address transport
  predicates:
  `parallel/rmregops_lifecycle.md`
- `0xbadf510c` host/RM/hardware provenance boundary and NVIDIA public
  PRI-error-family cross-check:
  `parallel/badf510c_provenance.md`
- Local SBR/module-reload script recovery-scope audit:
  `parallel/local_recovery_script_scope.md`,
  `parallel/sbr_shadow_scope.md`
- Falcon v6 target-object comparison and complete local VBIOS inventory:
  `parallel/fsp_v6_payload_compare.md`,
  `parallel/vbios_fsp_inventory.md`
- Falcon-v6 public-format boundary, three-object ciphertext/envelope diff,
  device-internal BootFSM handoff, and post-decrypt host-observability audits:
  `parallel/falcon_v6_public_research.md`,
  `parallel/fsp_run_object_diff.md`,
  `parallel/fsp_boot_chain_trace.md`,
  `parallel/fsp_postdecrypt_observability.md`
- HPE-packaged `nvflash` 5.877.0 bounded static Falcon-descriptor classifier
  audit (the saved v6 header falls into its legacy GFW-v1 catch-all; the binary
  was not executed):
  `parallel/nvflash_v6_parser_reverse.md`
- Host-side PLDM/NVFW structural parsing versus returned update-status boundary
  in the same saved, non-executed updater:
  `parallel/nvflash_update_compat_boundary.md`
- Dell/HPE PLDM component layout, header CRC, and HPE outer P-384/SHA-384
  signature verification and trust boundary:
  `parallel/fwpkg_container_auth.md`
- Public RM NVDM-type-`0x12` transport/response boundary, private updater
  command inventory, and separation from type-`0x14` GSP COT:
  `parallel/public_fsp_fwupdate_chain.md`
- HPE footer consumer/trust-anchor bounded negative across the packaged
  wrapper, updater parser, and management-MCU component:
  `parallel/hpe_footer_consumer.md`
- GeForce/Pro outer PCI/subsystem/PLDM applicability, public-key lineage, and
  nested `FSP_RUN` correlation matrix:
  `parallel/nvfw_sku_binding_compare.md`
- NVFW/BCRT/Falcon-v6 authentication-layer separation and exact per-object
  relative-offset/length/SHA-384 coverage records:
  `parallel/nvfw_auth_layout.md`
- Full-file SHA-384 record enumeration, complete 35-entry Falcon-table cross-check,
  and the correction that `raw0=0x22` is a covered-start offset rather than index 34:
  `parallel/falcon_manifest_table.md`
- Exact nested-image coverage chain from the `FSP_RUN` envelope, through its
  two-entry hash table, to the parent SHA-384 at image `+0x209`:
  `parallel/bcrt_manifest_coverage.md`
- Bounded P-384 audit of the three outer BCRT/VBIOS-extension slots and the
  unresolved signature/transcript boundary:
  `parallel/raw_nvfw_p384_coverage.md`
- Exact RPM -> `.scexe` -> tar-member extraction and integrity/authenticity
  boundary for that saved binary:
  `parallel/hpe_nvflash_provenance.md`
- HPE official catalog cross-check for the matching Linux VBIOS release, and
  the bounded absence of an official public filename/hash/direct-download
  record:
  `parallel/hpe_official_catalog.md`
- Legacy x86 option-ROM and decompressed UEFI GOP bounded negative for an
  alternative host-side Falcon-v6/`FSP_RUN` consumer:
  `parallel/vbios_uefi_v6_consumer.md`

The `0x1d` knob-record reconstruction is complete: the host table has only name+ID
and exposes no value-domain metadata. Native input is normalized to `uint32`; the
task-13 vector is `id16+value16+zero16`, with the tail fixed by host code, and
readback compares a zero-extended u16 with
the full requested dword; hence `0..65535` is only a host-success envelope, not
the FSP allowed domain. Recovered invalid-value/permission/persistence errors
prove a device-side validator category exists but reveal no `0x1d` value. The
private parser preserves detailed firmware names in its log but folds QCAP
absence, a wrong response type and parsed nonzero application errors into raw
host status `0x12d`; `0x12e` is the PRC-read length mismatch and `0x12f` the
post-write readback mismatch. Public R580/R610 adds only invalid-knob-ID
`0x1e3` mapping, not a `0x1d` value schema. The
process-local MODS `SecurityUnlockLevel > 3` predicate and its origin/lifetime,
plus the fixed-GSP literal/table-driven `0x8200f8` searches, are also closed within their
stated static scopes. Neither produced a stock authorization credential or a
visible `f8` setter. The sole direct-read block present in both 610.43.03 and
610.74 is a TU102/TU116 OBJBSP/NVDEC helper; GB202/index 65 binds a success stub
in that slot, so its mere cross-version presence is not a GB202 consumer. The
host gate is now fully separate from the downstream layers: no bypass/TLS state
is carried in the task-2 packet, and task-2 completion does not modify the host
value. QCAP `0x13` presence is only the FSP-reported PRC-family admission check,
and the returned status is only the host-visible completion/error result.
Neither proves a `d0/dc/f8` value. The remaining device-side gap is the
unavailable GB202 consumer: whether task 2 changes `d0/dc` at all, for how long,
and whether it touches the independent `f8` PLM. PRC knob `0x1d` and the signed
HULK path remain separate mechanisms with unresolved target semantics. All work
remains static-only.

The completed artifact inventory now fixes the practical consumer-visibility
boundary. Ordinary archive layers, raw-DEFLATE bindata and GSP ELF nesting are
all traversable; installed `ucodes_*.bin` contain only their 24-byte headers
followed by zero-filled bodies, and the visible GSP/FMC images are material that
the already-running FSP verifies/boots rather than FSP runtime code. No
standalone FSP image is exposed. The strongest local carrier candidates remain
the three unique VBIOS Falcon-v6 `app=0x24,target=0x0f` objects: each descriptor
has `ENCRYPTED` set, while public 610 defines only the four-byte v6 descriptor
header and no body layout. The production consumer may be inside one of those
objects, chip ROM, or another unsaved authenticated stage; no local evidence
chooses among them.

The task-2 QCAP record is now decoded as `low16=NvdmType,
high16=Version`, using MODS's own `NvdmType : Version` dump label. Task 2 maps
to `0x13=NVDM_TYPE_PRC` and tests only key presence; it neither compares the
Version nor carries it in the packet. QCAP is therefore a message-family
capability/version record, not a security level or reusable credential, and a
separate FSP command status is only the host-visible completion/error result;
it does not establish a PLM state.

The reset-coupled binding audit corrected an earlier material mistake.  GB202
index 65 is selected by the group-2 `0x303f` bitmap and binds the state-aware
`0x144d4e8` implementation at `OBJGPU+0x668`; it does not retain the constant-
false `0x19508c4` default.  This binding is now reproducible `V-STATIC` evidence.
The internal audit now also identifies its guard as `isVirtual` and its direct
physical result as `fuse(+0x40) || boot(+0x44)`.  The sibling selector-8 setter
uses base coupling at `+0x48`, but this getter has no direct `+0x48` load.  The
public ABI still returns only one bool, the historical zero lacks retained
stdout, and no current three-input coupling state was queried.  Whether base
coupling has a hardware/reset-sequencer/FSP side effect remains unknown; the
visible GSP setter and type-8 dispatcher have now ruled out software mirroring
into the first two bits.

The coupling permission audit also identifies each private gate's bit 4 as the
standard PLM `WRITE_PROTECTION_LEVEL0_ENABLE` bit. It is unrelated to MODS'
process-local `SecurityUnlockLevel > 3` gate. MODS chooses direct versus FSP before any
write; direct readback failure is not retried through FSP, and the fixed GSP
setter itself contains no such fallback.

The raw-to-effective audit also corrected a register-constant collision.  The
former `0x15d3a98` “B-address-capable setter” candidate is positively identified
as a GH100-only `Ioctrl`/MINION NVLink EOM DLCMD sender: `0x0a40` is
`0x2900/4` in the MINION aperture, not an effective-L2 offset in the Fuse
aperture.  GB202 binds the corresponding methods to no-op/not-supported stubs.
It is therefore removed from the B-writer candidate set; no visible GSP
A-derived B writer remains in the bounded evidence.

The ordinary domain-5 accessor always carries literal instance 0, but its base
source is conditional.  A populated PTOP DeviceInfo2 mapped class `0x10`
supplies that instance's `devicePriBase`; an empty class falls back to embedded
selector row 0 (`0x820000`).  This is a hardware-topology cache, not an external
instance redirect.  Within one serial write plan the latch RMW may build the
cache and all later write/readback operations reuse it.  A malformed nonempty
class without instance 0 does not fail closed in MODS—it performs an out-of-
range record-field read—so any future offline topology input must reject that
shape rather than emulate the binary.

The GB202 DeviceInfo2 type translation is now complete: PTOP raw type `0x22`
maps mechanically to internal class `0x10`, and NVIDIA's published
`NV_FUSE0_PRI_BASE=0x820000` name independently closes this class's semantic
role as the fuse PRI aperture in the audited path.  The exact stripped C++ enum
token and unpublished public PTOP macro spelling remain unknown.  This identity
result does not reveal whether the live RTX 5090 table contains the row or its
actual `devicePriBase`.  Published 610 builders also do not establish the
stronger invariant "nonempty type implies instance 0": they preserve instance
IDs and explicitly handle missing/duplicate matches, while the physical-side
producer that could enforce a hardware rule is unpublished.

Normal `SetSwFuses` post-program reset does not refresh this cache by
reconstructing its owner. The reset chain preserves and continues to use the
same `GpuSubdevice*`, has no visible call to `0xdd2520`, and does not touch the
cache vectors/flag. Consequently the pre-reset snapshot remains built on the
visible 570.151 path. Independently, NVIDIA 610 binds GB202's primary-FUSE
getter to a stateless `NV_FUSE0_PRI_BASE=0x820000` return, so a legitimate
class-`0x10` instance-0 row is very strongly expected to agree with the
fallback. These are host-cache/address invariants, not evidence that raw L2
changes were adopted into effective topology.

The direct-shadow host-shape audit also finds no mandatory L2/PAC pairing,
cross-FBP symmetry, even-popcount or allowed-pattern normalization in the
visible JS/encoder/plan chain. Conditional on the reported `8 x 0x12` baseline
and 2-MiB/raw-position accounting model, the 1/2/7-bit deltas for theoretical
`96 -> 98/100/110 MiB` are therefore representable by the stock host plan.
This is not firmware/hardware acceptance evidence: private FsLib, FSP/GFW,
route/PAC and physical health remain unresolved lower-layer constraints.

The agent names shown by the orchestration UI (for example
`/root/evidence_audit`) are task-tree identifiers, not filesystem paths or
Linux users.

## Interactive tmux workers

Both workers run an ordinary interactive Codex TUI with working directory
`/home/user/rt_5090_project`.  Neither uses non-interactive/print mode.

| Worker | tmux pane | Watcher | Task | Report | Completion inbox |
|---|---|---|---|---|---|
| `gb202-mods` | `%4` at launch | `gb202-mods-watch` | MODS permission and sequencing audit | `parallel/tmux_mods_permissions.md` | `parallel/inbox/tmux_mods_permissions.done.md` |
| `gb202-repair` | `%5` at launch | `gb202-repair-watch` | current GSP L2 repair-path audit | `parallel/tmux_gsp_l2_repair.md` | `parallel/inbox/tmux_gsp_l2_repair.done.md` |

Both interactive workers completed successfully on 2026-07-21 and left their
sessions idle for follow-up.  The MODS worker proved the host gate/order and
non-fail-closed error handling while leaving private GB202 PLM effects
unknown.  The repair worker proved that GB202 index 65 binds substantive
`OBJINFOROM +0x188/+0x1b0/+0x6a0` methods to `NV_OK` no-op stubs; a separate,
non-empty physical repair map remains unproved.

On 2026-07-22 both existing panes were confirmed alive and idle, then assigned
new non-overlapping static-only follow-ups:

| Worker | Follow-up | Report | Completion inbox |
|---|---|---|---|
| `gb202-mods` / `%4` | Inventory local artifacts for the production task-2/subobject-1 consumer and identify the exact visibility/packaging boundary | `parallel/tmux_task2_artifact_inventory.md` | `parallel/inbox/tmux_task2_artifact_inventory.done.md` |
| `gb202-repair` / `%5` | Cross-version local search for PRC knob `0x1d` value/one-shot semantics and any `d0/dc/f8` state evidence | `parallel/tmux_prc1d_consumer_refresh.md` | `parallel/inbox/tmux_prc1d_consumer_refresh.done.md` |

Both follow-ups retain the same no-live-device, no-execution, no-reset and
bounded-resource rules above. Their reports are not merged until the completion
marker is present and independently checked.

The two auto-continue watcher sessions were stopped on 2026-07-22 to conserve
model quota and prevent repeated retry loops. The worker panes remain alive and
may finish their current single turns, but no warning/menu will now be answered
automatically; any later continuation requires one deliberate coordinator
action.

Both 2026-07-22 follow-ups subsequently produced their completion markers and
are now closed; neither worker was automatically continued afterward.

The coordinator-only follow-up on HULK/VBIOS policy boundaries is recorded in
`parallel/hulk_vbios_policy_boundary_20260722.md`. It concludes that the
currently visible legitimate route, if any, would require a signed HULK
authorization object or a device-accepted VBIOS/FSP_RUN authorization object;
the local artifacts do not contain a usable GB202/`0x8200f8` authorization
material.

Each watcher resolves and locks the worker's pane ID, PID, and TTY.  It cannot
redirect input if the pane identity changes.  Completion files are separate to
avoid concurrent writes; the coordinator polls them and alone merges the main
document.

## Original parallel assignments

### Task A — current 610 FSP/GSP authorization

Trace the GB202 610.43.03 path for NVDM HULK (`0x11`) and task2/subobject1.
Determine which of FSP or SEC2 receives each message, when PLMs `d0`, `dc`, and
`f8` are lowered, and whether a response/restore operation exists.  Use the
current GSP ELF and open 610 source only.  Record evidence and uncertainty in
the completed `parallel/gb202_610_arch.md` and
`parallel/task2_lifecycle_audit.md` reports.

### Task B — current MODS permission and timing

Statically inspect the downloaded MODS binary without executing it.  Separate the
process-local `SecurityUnlockLevel > 3` gate from FSP protocol checks and actual
device PLM state; refine the exact order of permission preparation, mask writes,
latch, reset, and reinit.  Look for a legitimate
current path that can lower permissions without forging a bypass or patching the
binary.  The completed artifact is `parallel/tmux_mods_permissions.md`.

### Task C — L2 isolation, defect evidence, safe observability

Use 610 source, VBIOS/static artifacts, saved probe output, and at most official
high-level read-only hardware queries.  Determine whether physical defect/repair
state is stored separately from the uniform SKU mask, whether LTS slices can be
isolated or tested one at a time, and which existing ECC/Xid/telemetry mechanisms
could detect a bad slice after a future authorized enable.  Record evidence in
the completed `parallel/l2_safety_observe.md` report.

## Evidence standard

Every claim must include a file path plus symbol/address/line where possible.
Clearly label facts, strong inferences, and unknowns.  Do not convert an inference
into a proposed live command.  Each task writes only its assigned report; the root
agent alone updates the main findings document.

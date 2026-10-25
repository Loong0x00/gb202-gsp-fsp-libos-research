# Isolated MODS VM

Purpose: run the untrusted/unsigned MODS sample with the RTX 5090 passed
through as a complete IOMMU group. By default the experiment VM has no NIC
and no host filesystem sharing. A clean base disk is kept read-only; each MODS
run uses a disposable qcow2 overlay. An explicitly restricted host-loopback
SSH management NIC was enabled only on the disposable 2026-09-24 guest;
see `VFIO_SSH_HOST_ONLY_20260924.md` for scope and access details. It has
no guest default route or general Internet access.

The installer account is `mods` with password `mods-lab`.  This credential is
only for the offline disposable guest.

The RTX 5090 group contains exactly `0000:01:00.0` and `0000:01:00.1` on the
host at the time this lab was created.  Never start a passthrough run without
rechecking the group and all device holders.

# RTX 5090 VFIO production test lab

This lab keeps the host NVIDIA stack out of the failure path. The RTX 5090
GPU and its HDA function are bound to `vfio-pci` in a dedicated GRUB boot
entry, then assigned together to a disposable Arch Linux guest.

Host invariants:

- the normal Arch boot entry is left unchanged;
- the VFIO entry is headless and boots `multi-user.target`;
- `0000:01:00.0` and `0000:01:00.1` must be the only members of IOMMU group
  13 and the only devices below root port `0000:00:01.1`;
- the immutable guest base is never passed to QEMU writable;
- every VM start creates a fresh qcow2 overlay and OVMF variable file;
- QEMU serial output and QMP stay on the host;
- no host NVIDIA RM, UVM, DRM, or KMS module participates in a VFIO-lab boot.

The guest is controlled over `127.0.0.1:2222` using the dedicated SSH key in
this directory. A guest failure is handled by killing QEMU, allowing VFIO to
reset on close, and only then attempting a bounded FLR or bus reset. A timed
out reset is never followed by another reset operation.


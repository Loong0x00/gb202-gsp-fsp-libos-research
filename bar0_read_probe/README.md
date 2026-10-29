# GB202 fixed read-only BAR0 probe

This kernel module reads five fixed 32-bit BAR0 registers from the RTX 5090 at
`0000:01:00.0` and reports them to the kernel log. It has no module parameters,
device node, debugfs entry, mmap path, or MMIO write instruction.

The first two reads validate the direct BAR path against ordinary boot/status
registers. The final three addresses are published NVIDIA fuse option/readout
registers that RM's user-mode register-operation allowlist rejects. Comparing
the results distinguishes an RM software allowlist from a lower hardware/FSP
read firewall.

The module deliberately does not claim or unbind the PCI device. It maps only
four bytes for each fixed read and can coexist briefly with the bound NVIDIA
driver. Unload it immediately after collecting the log.

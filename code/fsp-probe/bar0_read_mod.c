// bar0_read_mod.c —— 直接 ioremap BAR0,读 fuse 域的 floorsweep 相关寄存器(不依赖 nvidia 驱动)
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
static int __init bar0r_init(void)
{
    struct pci_dev *pdev; void __iomem *bar; int i;
    pdev = pci_get_domain_bus_and_slot(0, 0, PCI_DEVFN(2, 0));
    if (!pdev) return -ENODEV;
    bar = ioremap(pci_resource_start(pdev, 0), 0x900000);
    if (!bar) { pci_dev_put(pdev); return -ENOMEM; }
    pr_err("bar0r: 0x8200d0=%#x 0x8200dc=%#x 0x8200f8=%#x 0x8200e0=%#x 0x8200f4=%#x 0x8200fc=%#x\n",
           ioread32(bar+0x8200d0), ioread32(bar+0x8200dc), ioread32(bar+0x8200f8),
           ioread32(bar+0x8200e0), ioread32(bar+0x8200f4), ioread32(bar+0x8200fc));
    pr_err("bar0r: FBP raw 0x8234e0+4i:");
    for (i = 0; i < 8; i++) pr_cont(" %02x", ioread32(bar+0x8234e0+4*i) & 0xff);
    pr_cont("   eff 0x822900+4i:");
    for (i = 0; i < 8; i++) pr_cont(" %02x", ioread32(bar+0x822900+4*i) & 0xff);
    pr_cont("\n");
    iounmap(bar); pci_dev_put(pdev); return -EINVAL;
}
module_init(bar0r_init);
MODULE_LICENSE("GPL");

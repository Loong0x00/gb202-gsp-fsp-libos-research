// 扫描 0x820000-0x824000 窗口:打印 FNV-1a 校验和 + 关键寄存器(用于开火前后对比)
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
static char *tag = "x";
module_param(tag, charp, 0);
static int __init fs_init(void){
    struct pci_dev *pdev; void __iomem *bar; u32 h=2166136261u; unsigned o;
    pdev = pci_get_domain_bus_and_slot(0,0,PCI_DEVFN(2,0));
    if(!pdev) return -ENODEV;
    bar = ioremap(pci_resource_start(pdev,0),0x900000);
    if(!bar){pci_dev_put(pdev);return -ENOMEM;}
    for(o=0x820000;o<0x824000;o+=4){ u32 v=ioread32(bar+o); h=(h^v)*16777619u; }
    pr_err("fscan[%s]: FNV=0x%08x\n", tag, h);
    pr_err("fscan[%s]: d0=%#x dc=%#x f8=%#x e0=%#x f4=%#x fc=%#x latch=%#x ac=%#x\n", tag,
        ioread32(bar+0x8200d0), ioread32(bar+0x8200dc), ioread32(bar+0x8200f8),
        ioread32(bar+0x8200e0), ioread32(bar+0x8200f4), ioread32(bar+0x8200fc),
        ioread32(bar+0x820040), ioread32(bar+0x8212ac));
    pr_err("fscan[%s]: raw[0..7]=", tag);
    for(o=0;o<8;o++) pr_cont(" %#x", ioread32(bar+0x8234e0+4*o));
    pr_cont("  eff[0..7]=");
    for(o=0;o<8;o++) pr_cont(" %#x", ioread32(bar+0x822900+4*o));
    pr_cont("\n");
    iounmap(bar); pci_dev_put(pdev); return -EINVAL;
}
module_init(fs_init);
MODULE_LICENSE("GPL");

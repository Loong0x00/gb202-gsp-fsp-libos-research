// 临时:排空 port1 send FIFO + W1C 清 INTR
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
static int __init dr_init(void){
    struct pci_dev *p; void __iomem *b; int i; u32 info;
    p = pci_get_domain_bus_and_slot(0,1,PCI_DEVFN(0,0)); if(!p) return -ENODEV;
    b = ioremap(pci_resource_start(p,0), 0xC00000); if(!b){ pci_dev_put(p); return -ENOMEM; }
    info = ioread32(b+0x8f1f10);
    pr_err("DR: p1 send_info=0x%08x (size=%u ready=%u err=%u)\n", info, info&0xfffff, (info>>24)&1, (info>>25)&1);
    for (i=0;i<64;i++){ u32 d=ioread32(b+0x8f1f14); if(i<8) pr_err("DR: rdata[%d]=0x%08x\n", i, d); }
    info = ioread32(b+0x8f1f10);
    pr_err("DR: 排空后 send_info=0x%08x\n", info);
    iowrite32(0x80000000u, b+0x8f1f10);   // W1C INTR_STATUS(bit31)
    info = ioread32(b+0x8f1f10);
    pr_err("DR: W1C 后 send_info=0x%08x (err=%u ready=%u)\n", info, (info>>25)&1, (info>>24)&1);
    iounmap(b); pci_dev_put(p); return -EINVAL;
}
module_init(dr_init); MODULE_LICENSE("GPL");

// fsp_wrtest_mod.c —— 单 dword 写-读-还原测试(默认立即还原)
// 用法: sudo insmod fsp_wrtest_mod.ko addr=0x8f7340 val=0xA5A55A5A
// 行为: 读原值 → 写 val → 读回 → 还原原值 → 再读验证 → 打印全部
// keep=1 时跳过还原(默认 0)。读完返回 -EINVAL 自卸载。
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
static unsigned long addr = 0;
static unsigned long val = 0xA5A55A5A;
static int keep = 0;
module_param(addr, ulong, 0); module_param(val, ulong, 0); module_param(keep, int, 0);
static int __init wr_init(void)
{
    struct pci_dev *p; void __iomem *b; u32 before, after, restored;
    if (!addr || addr > 0xBFFFFC) { pr_err("WRTEST: addr 不合法\n"); return -EINVAL; }
    p = pci_get_domain_bus_and_slot(0, 1, PCI_DEVFN(0, 0));
    if (!p) { pr_err("WRTEST: 无设备\n"); return -ENODEV; }
    b = ioremap(pci_resource_start(p, 0), 0xC00000);
    if (!b) { pci_dev_put(p); return -ENOMEM; }
    before  = ioread32(b + addr);
    iowrite32((u32)val, b + addr);
    after   = ioread32(b + addr);
    if (!keep) {
        iowrite32(before, b + addr);
        restored = ioread32(b + addr);
        pr_err("WRTEST: 0x%06lx 原=%08x 写=%08x 读回=%08x 还原后=%08x => %s\n",
               addr, before, (u32)val, after, restored,
               after == (u32)val ? "可写(已还原)" : (after == before ? "只读(写被忽略)" : "写改变为其它值!"));
    } else {
        pr_err("WRTEST: 0x%06lx 原=%08x 写=%08x 读回=%08x (keep,未还原)\n",
               addr, before, (u32)val, after);
    }
    iounmap(b); pci_dev_put(p);
    return -EINVAL;
}
module_init(wr_init);
MODULE_LICENSE("GPL");

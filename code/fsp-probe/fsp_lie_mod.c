// fsp_lie_mod.c —— 在客体内核里直接 ioremap BAR0,向 FSP 的 MNOC 信箱发一条"声明长度≠实际长度"的报文
// insmod fsp_lie_mod.ko declared=<N> pushed=<M> port=2
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <linux/delay.h>

#define FSP_MNOC_BASE   0x008f1e00u
#define OFF_SEND_INFO(p) (0x104u + ((p) * 0x0cu))
#define OFF_SEND_RDATA(p)(0x108u + ((p) * 0x0cu))
#define OFF_RECV_INFO(p) (0x184u + ((p) * 0x0cu))
#define OFF_RECV_WDATA(p)(0x188u + ((p) * 0x0cu))
#define SIZE_MASK        0x000fffffu
#define RECV_TRIGGER     (1u << 20)
#define RECV_READY       (1u << 24)
#define SEND_READY       (1u << 24)
#define RECV_ERR         (1u << 25)
#define SEND_ERR         (1u << 25)
#define RECV_CREDIT      (1u << 26)

static unsigned declared = 9, pushed = 9, port = 2;
module_param(declared, uint, 0444);
module_param(pushed,   uint, 0444);
module_param(port,     uint, 0444);

static int __init fsp_lie_init(void)
{
    struct pci_dev *pdev;
    resource_size_t base;
    void __iomem *bar;
    u32 info, si;
    unsigned off;
    u8 msg[32];

    pdev = pci_get_domain_bus_and_slot(0, 0, PCI_DEVFN(2, 0));   /* 0000:00:02.0 */
    if (!pdev) { pr_err("fsp_lie: GPU not found\n"); return -ENODEV; }
    base = pci_resource_start(pdev, 0);
    bar = ioremap(base, 0x900000);   /* 整段映射:绝对偏移直接用,不再叠加基址(修 v1 的双重基址 bug) */
    if (!bar) { pci_dev_put(pdev); pr_err("fsp_lie: ioremap failed\n"); return -ENOMEM; }

    pr_err("fsp_lie: BAR0=%pa mnoc=%#x declared=%u pushed=%u port=%u\n",
           &base, FSP_MNOC_BASE, declared, pushed, port);
    pr_err("fsp_lie: 前 RECV_INFO=%#x SEND_INFO=%#x\n",
           ioread32(bar + OFF_RECV_INFO(port)), ioread32(bar + OFF_SEND_INFO(port)));

    /* 正控制读:确认访问路径没错 */
    pr_err("fsp_lie: 控制读 BAR0+0x0=%#x(期望 chipId) BAR0+0x200bc=%#x(期望 0xFF) BAR0+0x8f0334=%#x(ucode)\n",
           ioread32(bar + 0x0), ioread32(bar + 0x200bc), ioread32(bar + 0x8f0334));
    {
        int pp;
        for (pp = 0; pp < 4; pp++)
            pr_err("fsp_lie: port%d RECV_INFO=%#x SEND_INFO=%#x ready=%d credit=%d err=%d\n",
                   pp, ioread32(bar + OFF_RECV_INFO(pp)), ioread32(bar + OFF_SEND_INFO(pp)),
                   !!(ioread32(bar + OFF_RECV_INFO(pp)) & RECV_READY),
                   !!(ioread32(bar + OFF_RECV_INFO(pp)) & RECV_CREDIT),
                   !!(ioread32(bar + OFF_RECV_INFO(pp)) & RECV_ERR));
    }
    info = ioread32(bar + OFF_RECV_INFO(port));
    if (!(info & RECV_READY)) { pr_err("fsp_lie: 信箱未就绪(RECV_INFO=%#x),FSP 可能没在跑\n", info); goto out; }
    if (info & RECV_ERR)      { pr_err("fsp_lie: 发送前 ERR 置位 %#x\n", info); goto out; }

    memset(msg, 0, sizeof(msg));
    /* MCTP dword0: version1|SOM|EOM ; dword1: NVDM type 0x16 (CAPS_QUERY) */
    msg[0] = 0x01; msg[2] = 0x00; msg[3] = 0xc0;
    msg[4] = 0x7e; msg[5] = 0xde; msg[6] = 0x10; msg[7] = 0x16;
    if (pushed > sizeof(msg)) pushed = sizeof(msg);

    info &= ~SIZE_MASK;
    info |= declared & SIZE_MASK;
    info |= RECV_TRIGGER;
    iowrite32(info, bar + OFF_RECV_INFO(port));
    pr_err("fsp_lie: 已声明长度=%u\n", declared);

    for (off = 0; off < pushed; off += 4) {
        u32 d = 0;
        memcpy(&d, msg + off, (pushed - off < 4) ? (pushed - off) : 4);
        iowrite32(d, bar + OFF_RECV_WDATA(port));
        if ((off & 0x3fu) == 0) udelay(50);
    }
    pr_err("fsp_lie: 已推入 %u 字节\n", pushed);

    /* 等回包(1.5s) */
    for (off = 0; off < 1500; off++) {
        si = ioread32(bar + OFF_SEND_INFO(port));
        if (si & SEND_ERR) { pr_err("fsp_lie: !! 发送侧 ERR %#x\n", si); break; }
        if (si & SEND_READY) {
            pr_err("fsp_lie: 收到响应 size=%u\n", si & SIZE_MASK);
            break;
        }
        udelay(1000);
    }
    if (!(si & (SEND_ERR | SEND_READY))) pr_err("fsp_lie: 1.5s 无响应(RECV_INFO=%#x SEND_INFO=%#x)\n",
                                               ioread32(bar + OFF_RECV_INFO(port)), si);
out:
    pr_err("fsp_lie: 后 RECV_INFO=%#x SEND_INFO=%#x\n",
           ioread32(bar + OFF_RECV_INFO(port)), ioread32(bar + OFF_SEND_INFO(port)));
    iounmap(bar);
    pci_dev_put(pdev);
    return -EINVAL;      /* 故意失败:模块不驻留,只留下 printk */
}
module_init(fsp_lie_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("probe FSP mailbox length-trust");

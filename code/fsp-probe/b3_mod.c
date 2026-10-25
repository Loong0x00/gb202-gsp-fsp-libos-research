// b3_mod.c —— B3 实验:MNOC port1 发 task2(打开 PLM),然后宿主写 effective L2 掩码 0x822900,
// 立即读回;并打印全套关键寄存器前后值。读完返回 -EINVAL(自卸载)。
// 参数: port(默认1) target(默认0x822900) val(默认0x00000010) mode(1=只读检查 2=task2+写)
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <linux/delay.h>
#include <linux/string.h>

#define MNOC_BASE      0x8f1e00U
#define RECV_INFO(p)   (MNOC_BASE + 0x184U + (p)*0x0cU)
#define RECV_WDATA(p)  (MNOC_BASE + 0x188U + (p)*0x0cU)
#define SIZE_MASK      0x000fffffU
#define RECV_TRIGGER   (1U<<20)
#define RECV_READY     (1U<<24)
#define RECV_ERR       (1U<<25)
#define RECV_CREDIT    (1U<<26)

static int port = 1; static int mode = 1;
static unsigned long target = 0x822900UL; static unsigned int val = 0x10U;
module_param(port,int,0); module_param(mode,int,0);
module_param(target,ulong,0); module_param(val,uint,0);
static int pb=1,pd=0,pf=0;
module_param(pb,int,0); module_param(pd,int,0); module_param(pf,int,0);

static const unsigned int watch[] = {0x8200d0,0x8200dc,0x8200f8,0x8200fc,0x8212ac,0x820040,
                                     0x8234e0,0x822900,0x822080,0x820d70,0x824140,0x820838};
static void dump(void __iomem *b, const char *tag)
{
    int i;
    for (i=0;i<(int)(sizeof(watch)/sizeof(watch[0]));i++)
        pr_err("B3: %s *0x%06x = 0x%08x\n", tag, watch[i], ioread32(b+watch[i]));
}

static int wait_bit(void __iomem *b, u32 off, u32 mask, int want, const char *w)
{
    int i;
    for (i=0;i<2000;i++){ u32 v=ioread32(b+off); if (want?(v&mask):!(v&mask)) return 0; udelay(1000); }
    pr_err("B3: 等 %s 超时 off=0x%x last=0x%08x\n", w, off, ioread32(b+off)); return -1;
}

/* task2 报文: MCTP c0000001 | NVDM 1310de7e | 02 01 00*6  = 16 字节 */
static const u8 task2[16] = {0x01,0,0,0xc0, 0x7e,0xde,0x10,0x13, 0x02,0x01, 0,0,0,0,0,0};  /* MCTP dword 0xC0000001 小端 */

static int mnoc_send(void __iomem *b, const u8 *msg, size_t n)
{
    u32 reg; size_t off;
    if (wait_bit(b, RECV_INFO(port), RECV_READY, 1, "RECV_READY") != 0) return -1;
    reg = ioread32(b+RECV_INFO(port));
    if (reg & RECV_ERR) { pr_err("B3: 发送前 ERR=1 (0x%08x)\n", reg); return -1; }
    reg &= ~SIZE_MASK; reg |= (u32)n & SIZE_MASK; reg |= RECV_TRIGGER;
    iowrite32(reg, b+RECV_INFO(port));
    pr_err("B3: 已写 INFO=0x%08x (声明=%zu)\n", reg, n);
    for (off=0; off<n; off+=4) {
        u8 t[4]={0,0,0,0}; u32 d; size_t k, m=(n-off<4)?(n-off):4;
        if ((off%64U)==0) {
            if (wait_bit(b, RECV_INFO(port), RECV_CREDIT, 1, "CREDIT") != 0) return -1;
            reg = ioread32(b+RECV_INFO(port));
            if (reg & RECV_ERR) { pr_err("B3: off=%zu 处 ERR=1 (0x%08x)\n", off, reg); return -1; }
        }
        memcpy(t, msg+off, m);
        d = t[0] | (t[1]<<8) | (t[2]<<16) | ((u32)t[3]<<24);
        iowrite32(d, b+RECV_WDATA(port));
    }
    pr_err("B3: 已推送 %zu 字节\n", n);
    return 0;
}

static int __init b3_init(void)
{
    struct pci_dev *p; void __iomem *b; u32 before, after;
    p = pci_get_domain_bus_and_slot(0, pb, PCI_DEVFN(pd,pf));
    if (!p) { pr_err("B3: 无设备\n"); return -ENODEV; }
    b = ioremap(pci_resource_start(p,0), 0xC00000);
    if (!b) { pci_dev_put(p); return -ENOMEM; }
    pr_err("B3: mode=%d port=%d target=0x%06lx val=0x%08x\n", mode, port, target, val);
    dump(b, "前 ");
    if (mode == 2) {
        if (mnoc_send(b, task2, sizeof(task2)) != 0) { pr_err("B3: task2 发送失败\n"); goto out; }
        mdelay(500);
        dump(b, "task2后");
    }
    if (mode == 3) {
        before = ioread32(b + target);
        pr_err("B3: 目标原值 *0x%06lx = 0x%08x\n", target, before);
        iowrite32(val, b + target);
        after = ioread32(b + target);
        pr_err("B3: 写入后 *0x%06lx = 0x%08x  ⇒ %s\n", target, after,
               (after == val) ? "写入成功(读回=新值)" : (after == before ? "写入被丢弃(读回=原值)" : "其它"));
        dump(b, "写后 ");
    }
out:
    iounmap(b); pci_dev_put(p);
    return -EINVAL;
}
module_init(b3_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("B3: task2 + host write to effective L2 mask (self-unloading probe)");

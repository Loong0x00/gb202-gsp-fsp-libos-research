// fsp_od_mod.c —— MNOC 信箱"声明长度 vs 实际推送"实验(内核态,驱动绑定时也能用 ioremap)
//
// 用法:
//   sudo insmod fsp_od_mod.ko                      # 对照:声明=实际(9 字节)
//   sudo insmod fsp_od_mod.ko declared=0xfffff     # V1:声明 1 MiB,只推 9 字节
//   sudo insmod fsp_od_mod.ko declared=0xfffff push=0x100000 fill=0xaa   # V2:推 1 MiB
//   sudo insmod fsp_od_mod.ko declared=0xfffff push=4                    # V3:只推 4 字节
// 参数: port(默认 1) declared(0=实际) push(0=实际) fill(0) no_recv(0)
// 模块读完即返回 -EINVAL(故意加载失败,免得驻留)。
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <linux/delay.h>
#include <linux/string.h>

#define FSP_MNOC_BASE        0x8f1e00U
#define MNOC_SEND_INFO(p)    (FSP_MNOC_BASE + 0x104U + (p) * 0x0cU)
#define MNOC_SEND_RDATA(p)   (FSP_MNOC_BASE + 0x108U + (p) * 0x0cU)
#define MNOC_RECV_INFO(p)    (FSP_MNOC_BASE + 0x184U + (p) * 0x0cU)
#define MNOC_RECV_WDATA(p)   (FSP_MNOC_BASE + 0x188U + (p) * 0x0cU)

#define SIZE_MASK            0x000fffffU
#define RECV_TRIGGER         (1U << 20)
#define SEND_READY           (1U << 24)
#define RECV_READY           (1U << 24)
#define SEND_ERR             (1U << 25)
#define RECV_ERR             (1U << 25)
#define RECV_CREDIT          (1U << 26)

static int port   = 1;
static int declared = 0;
static int push     = 0;
static int fill     = 0;
static int no_recv  = 0;
static int force    = 0;   /* force=1: 即使 ERR 已置位也照写(用于试清) */
static int pbus = 1, pdev = 0, pfn = 0;
module_param(port, int, 0);
module_param(declared, int, 0);
module_param(push, int, 0);
module_param(fill, int, 0);
module_param(no_recv, int, 0);
module_param(force, int, 0);
module_param(pbus, int, 0); module_param(pdev, int, 0); module_param(pfn, int, 0);

/* 等一个掩码位,最多 ~2 秒 */
static int wait_bit(void __iomem *b, u32 off, u32 mask, bool want, const char *what)
{
    int i; u32 v;
    for (i = 0; i < 2000; i++) {
        v = ioread32(b + off);
        if (want ? (v & mask) : !(v & mask)) return 0;
        udelay(1000);
    }
    pr_err("FSPOD: 超时等待 %s (off=0x%x last=0x%08x)\n", what, off,
           ioread32(b + off));
    return -1;
}

static int __init od_init(void)
{
    struct pci_dev *p; void __iomem *b;
    u8 req[16]; u32 reg, data; size_t off2; size_t dsz, psz;
    u32 rsp[8];

    /* 9 字节 CAPS 查询: MCTP 0xC0000001 + NVDM 0x1610DE7E + submsg 0 */
    memset(req, 0, sizeof(req));
    req[0]=0x01; req[1]=0x00; req[2]=0x00; req[3]=0xC0;
    req[4]=0x7E; req[5]=0xDE; req[6]=0x10; req[7]=0x16;
    req[8]=0x00;

    dsz = declared ? (size_t)declared : 9;
    psz = push     ? (size_t)push     : 9;
    if (dsz < 4 || dsz > (SIZE_MASK + 1U) || psz > (SIZE_MASK + 1U)) {
        pr_err("FSPOD: 参数不合理 dsz=%zu psz=%zu\n", dsz, psz);
        return -EINVAL;
    }

    p = pci_get_domain_bus_and_slot(0, pbus, PCI_DEVFN(pdev, pfn));
    if (!p) { pr_err("FSPOD: 无设备\n"); return -ENODEV; }
    b = ioremap(pci_resource_start(p, 0), 0x900000);
    if (!b) { pci_dev_put(p); return -ENOMEM; }

    pr_err("FSPOD: BAR0=0x%llx port=%d declared=%zu push=%zu fill=0x%02x\n",
           (u64)pci_resource_start(p, 0), port, dsz, psz, fill);

    if (!force && wait_bit(b, MNOC_RECV_INFO(port), RECV_READY, true, "RECV_READY(前)") != 0) goto out;
    reg = ioread32(b + MNOC_RECV_INFO(port));
    pr_err("FSPOD: 前 INFO=0x%08x (size=%u err=%u credit=%u)\n", reg,
           reg & SIZE_MASK, !!(reg & RECV_ERR), !!(reg & RECV_CREDIT));
    if ((reg & RECV_ERR) && !force) { pr_err("FSPOD: 发送前已 ERR,放弃(force=1 可强写)\n"); goto out; }
    if ((reg & RECV_ERR) && force) pr_err("FSPOD: ERR 已置位,force=1 ⇒ 照写(试清)\n");

    /* 核心: 写入"声明长度"(可与实际推送量不一致) + TRIGGER */
    reg &= ~SIZE_MASK;
    reg |= (u32)dsz & SIZE_MASK;
    reg |= RECV_TRIGGER;
    iowrite32(reg, b + MNOC_RECV_INFO(port));
    pr_err("FSPOD: 已写 INFO=0x%08x (声明 size=%zu)\n", reg, dsz);

    for (off2 = 0; off2 < psz; off2 += 4) {
        u8 tmp[4];
        size_t n = 0;
        if ((off2 % 64U) == 0) {
            if (wait_bit(b, MNOC_RECV_INFO(port), RECV_CREDIT, true, "CREDIT") != 0) {
                pr_err("FSPOD: 在 off=%zu/%zu 处等 CREDIT 超时\n", off2, psz);
                goto out;
            }
            reg = ioread32(b + MNOC_RECV_INFO(port));
            if (reg & RECV_ERR) { pr_err("FSPOD: off=%zu 处 ERR=1 INFO=0x%08x\n", off2, reg); goto out; }
        }
        if (off2 < 9) { n = (9 - off2) < 4 ? (9 - off2) : 4; memcpy(tmp, req + off2, n); }
        if (n < 4) { size_t k; for (k = n; k < 4; k++) tmp[k] = (u8)fill; }
        data = tmp[0] | (tmp[1] << 8) | (tmp[2] << 16) | ((u32)tmp[3] << 24);
        iowrite32(data, b + MNOC_RECV_WDATA(port));
    }
    pr_err("FSPOD: 已推送 %zu 字节(声明 %zu)\n", psz, dsz);

    reg = ioread32(b + MNOC_RECV_INFO(port));
    pr_err("FSPOD: 后 INFO=0x%08x (size=%u err=%u ready=%u credit=%u)\n", reg,
           reg & SIZE_MASK, !!(reg & RECV_ERR), !!(reg & RECV_READY), !!(reg & RECV_CREDIT));

    if (!no_recv) {
        if (wait_bit(b, MNOC_SEND_INFO(port), SEND_READY, true, "SEND_READY(回包)") == 0) {
            u32 sz = ioread32(b + MNOC_SEND_INFO(port)) & SIZE_MASK;
            int i;
            pr_err("FSPOD: 回包到达 size=%u\n", sz);
            memset(rsp, 0, sizeof(rsp));
            for (i = 0; i < 8 && (u32)(i * 4) < sz; i++)
                rsp[i] = ioread32(b + MNOC_SEND_RDATA(port));
            pr_err("FSPOD: 回包 dwords: %08x %08x %08x %08x %08x\n",
                   rsp[0], rsp[1], rsp[2], rsp[3], rsp[4]);
            pr_err("FSPOD: decode mctp=0x%08x nvdm=0x%08x (type=0x%02x) taskid=0x%08x cmd=0x%08x errcode=0x%08x\n",
                   rsp[0], rsp[1], (rsp[1] >> 24) & 0xff, rsp[2], rsp[3], rsp[4]);
        } else {
            pr_err("FSPOD: 没有回包(超时)—— SEND_INFO=0x%08x\n",
                   ioread32(b + MNOC_SEND_INFO(port)));
        }
    }
out:
    iounmap(b); pci_dev_put(p);
    return -EINVAL;
}
module_init(od_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("FSP MNOC over-declare experiment (read/write probe, self-unloading)");

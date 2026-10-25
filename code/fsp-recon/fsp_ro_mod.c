// fsp_ro_mod.c —— FSP 侦察模块(阶段 0:以只读为主)
// 三种模式,一次 insmod 只做一件事,读完自卸载(返回 -EINVAL,故意加载失败,免得驻留):
//   mode=range  start=0x8f0000 cnt=0x100              纯 BAR0 连续读
//   mode=cms2   start=0x0 cnt=0x4000 go=1             CMS2 间接窗口:写 0x8AA374(ADDR) 读 0x8AA378(DATA)
//   mode=emem   chan=0 blk=1 offs=0 cnt=0x40 go=1     EMEM 窗口:写 EMEMC(块/偏移/AINCR) 后连读 EMEMD
// 说明:
//  - range 模式零写入;cms2/emem 需要 go=1 才执行(默认拒绝),因为要写 ADDR/EMEMC 控制寄存器(与 RM 自己做的事相同)。
//  - 不写任何数据寄存器、不敲门铃、不碰 PLM/mask/熔丝。
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <linux/string.h>
#include <linux/kernel.h>

#define BAR_MAP_LEN   0x900000U

/* FSP falcon 块(参考:dev_fsp_pri.h / dev_fsp_addendum.h) */
#define R_FSP_SCRATCH_G2(i)   (0x8f0320U + 4U*(i))   /* FALCON_COMMON_SCRATCH_GROUP_2(0..3) */
#define R_FSP_SCRATCH_G3(i)   (0x8f0330U + 4U*(i))   /* GROUP_3(1)=ucode 版本, (3)=FUSE_ERROR_CHECK */
#define R_FSP_UCODE_VER       0x8f0334U
#define R_FSP_FUSE_ERR        0x8f033CU

/* OOBHUB 间接读窗口(参考:gb100/dev_oob_pri.h) */
#define R_OOBHUB_CMS2_ADDR    0x8AA374U
#define R_OOBHUB_CMS2_DATA    0x8AA378U

/* FSP EMEM / MNOC */
#define R_EMEMC(i)            (0x8f2ac0U + 8U*(i))
#define R_EMEMD(i)            (0x8f2ac4U + 8U*(i))
#define R_QHEAD(i)            (0x8f2c00U + 8U*(i))
#define R_QTAIL(i)            (0x8f2c04U + 8U*(i))
#define R_MHEAD(i)            (0x8f2c80U + 8U*(i))
#define R_MTAIL(i)            (0x8f2c84U + 8U*(i))
#define R_MNOC_SEND_INFO(p)   (0x8f1e00U + 0x104U + 0x0cU*(p))
#define R_MNOC_RECV_INFO(p)   (0x8f1e00U + 0x184U + 0x0cU*(p))

static char *mode = "range";
static unsigned long start = 0x8f0000UL;
static int cnt = 0x100;
static int chan = 0, blk = 0, offs = 0, go = 0;
static int pb = 1, pd = 0, pf = 0;

module_param(mode, charp, 0);
module_param(start, ulong, 0);
module_param(cnt, int, 0);
module_param(chan, int, 0);
module_param(blk, int, 0);
module_param(offs, int, 0);
module_param(go, int, 0);
module_param(pb, int, 0); module_param(pd, int, 0); module_param(pf, int, 0);

static void __iomem *bar;

static u32 rd(unsigned long o) { return ioread32(bar + o); }
static void wr(unsigned long o, u32 v) { iowrite32(v, bar + o); }

static int __init ro_init(void)
{
    struct pci_dev *p;
    int i;

    p = pci_get_domain_bus_and_slot(0, pb, PCI_DEVFN(pd, pf));
    if (!p) { pr_err("FSRRO: 无设备\n"); return -ENODEV; }
    bar = ioremap(pci_resource_start(p, 0), BAR_MAP_LEN);
    if (!bar) { pci_dev_put(p); return -ENOMEM; }

    pr_err("FSRRO: mode=%s BAR0=0x%llx\n", mode, (u64)pci_resource_start(p, 0));

    if (!strcmp(mode, "range")) {
        if (cnt <= 0 || cnt > 0x2000) { pr_err("FSRRO: cnt 不合法 %d\n", cnt); goto out; }
        pr_err("FSRRO: == range 0x%06lx .. 0x%06lx (%d dword) ==\n",
               start, start + 4UL*cnt - 4, cnt);
        for (i = 0; i < cnt; i += 8) {
            int j; char line[8*11 + 1];
            line[0] = 0;
            for (j = 0; j < 8 && i + j < cnt; j++)
                scnprintf(line + strlen(line), sizeof(line) - strlen(line),
                          " %08x", rd(start + 4UL*(i + j)));
            pr_err("FSRRO: 0x%06lx:%s\n", start + 4UL*i, line);
        }
    } else if (!strcmp(mode, "cms2")) {
        int nz = 0, ff = 0, poison = 0, printed = 0;
        if (!go) { pr_err("FSRRO: cms2 需要 go=1(会写 0x8AA374 ADDR)\n"); goto out; }
        if (cnt <= 0 || cnt > 0x10000) { pr_err("FSRRO: cnt 不合法 %d\n", cnt); goto out; }
        pr_err("FSRRO: == CMS2 扫描 idx 0x%04lx .. 0x%04lx ==", start, start + (unsigned long)cnt - 1);
        for (i = 0; i < cnt; i++) {
            u32 v;
            wr(R_OOBHUB_CMS2_ADDR, (u32)(start + (unsigned long)i));
            v = rd(R_OOBHUB_CMS2_DATA);
            if (v == 0xffffffffU) ff++;
            else if (v == 0) nz += 0;
            else nz++;
            if ((v >> 16) == 0xbadfU) poison++;
            if (start + (unsigned long)i < 0x100) { /* 低 256 全打印 */
                if (i % 4 == 0) pr_err("FSRRO: idx 0x%04x:", (unsigned)(start + i));
                pr_err("FSRRO:   0x%04x = %08x", (unsigned)(start + i), v);
                printed++;
            }
        }
        pr_err("FSRRO: CMS2 汇总: 非零且非 FF = %d, FF = %d, badf 族 = %d, 打印 = %d\n",
               nz, ff, poison, printed);
        pr_err("FSRRO: ADDR 寄存器读回 = 0x%08x\n", rd(R_OOBHUB_CMS2_ADDR));
    } else if (!strcmp(mode, "emem")) {
        u32 before, after, v;
        if (!go) { pr_err("FSRRO: emem 需要 go=1(会写 EMEMC)\n"); goto out; }
        if (cnt <= 0 || cnt > 0x2000) { pr_err("FSRRO: cnt 不合法 %d\n", cnt); goto out; }
        if (chan < 0 || chan > 7) { pr_err("FSRRO: chan 不合法 %d\n", chan); goto out; }
        if (blk < 0 || blk > 0xff || offs < 0 || offs > 63) {
            pr_err("FSRRO: blk/offs 不合法 %d/%d\n", blk, offs); goto out;
        }
        pr_err("FSRRO: EMEM 窗口探测 chan=%d blk=%d offs=%d cnt=%d\n", chan, blk, offs, cnt);
        pr_err("FSRRO: 前: EMEMC=0x%08x EMEMD=0x%08x QHEAD=%u QTAIL=%u MHEAD=%u MTAIL=%u\n",
               rd(R_EMEMC(chan)), rd(R_EMEMD(chan)), rd(R_QHEAD(chan)), rd(R_QTAIL(chan)),
               rd(R_MHEAD(chan)), rd(R_MTAIL(chan)));
        before = rd(R_EMEMC(chan));
        /* AINCR(bit25) + BLK(15:8) + OFFS(7:2) */
        wr(R_EMEMC(chan), (1U << 25) | ((u32)blk << 8) | ((u32)offs << 2));
        for (i = 0; i < cnt; i += 8) {
            int j; char line[8*11 + 1];
            line[0] = 0;
            for (j = 0; j < 8 && i + j < cnt; j++) {
                v = rd(R_EMEMD(chan));
                scnprintf(line + strlen(line), sizeof(line) - strlen(line), " %08x", v);
            }
            pr_err("FSRRO: +0x%04x:%s\n", (blk * 64 + offs + i) * 4, line);
        }
        after = rd(R_EMEMC(chan));
        pr_err("FSRRO: 后: EMEMC=0x%08x (前 0x%08x)  ⇒ 推进了 %u dword\n",
               after, before, ((after >> 2) & 0x3f) + (((after >> 8) & 0xff) * 64) -
               (((before >> 2) & 0x3f) + (((before >> 8) & 0xff) * 64)));
    } else {
        pr_err("FSRRO: 未知 mode=%s\n", mode);
    }

out:
    /* 顺手打印关键状态(零写入) */
    pr_err("FSRRO: ST 0x8f0320..3c = %08x %08x %08x %08x | %08x %08x %08x %08x\n",
           rd(R_FSP_SCRATCH_G2(0)), rd(R_FSP_SCRATCH_G2(1)),
           rd(R_FSP_SCRATCH_G2(2)), rd(R_FSP_SCRATCH_G2(3)),
           rd(R_FSP_SCRATCH_G3(0)), rd(R_FSP_SCRATCH_G3(1)),
           rd(R_FSP_SCRATCH_G3(2)), rd(R_FSP_SCRATCH_G3(3)));
    pr_err("FSRRO: ST ucode=0x%08x fuse_err=0x%08x ad00bc=0x%08x\n",
           rd(R_FSP_UCODE_VER), rd(R_FSP_FUSE_ERR), rd(0xad00bc));
    {
        int p2;
        for (p2 = 0; p2 < 4; p2++)
            pr_err("FSRRO: ST MNOC p%d send=0x%08x recv=0x%08x\n",
                   p2, rd(R_MNOC_SEND_INFO(p2)), rd(R_MNOC_RECV_INFO(p2)));
    }
    pr_err("FSRRO: ST PLM d0=%08x dc=%08x f8=%08x fc=%08x 212ac=%08x 40040=%08x\n",
           rd(0x8200d0), rd(0x8200dc), rd(0x8200f8), rd(0x8200fc),
           rd(0x8212ac), rd(0x820040));
    pr_err("FSRRO: ST mask raw=%08x eff=%08x sw=%08x fuse=%08x\n",
           rd(0x8234e0), rd(0x822900), rd(0x822080), rd(0x824140));

    iounmap(bar);
    pci_dev_put(p);
    return -EINVAL;   /* 自卸载 */
}
module_init(ro_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("FSP stage-0 read-only recon (range / CMS2 window / EMEM window)");

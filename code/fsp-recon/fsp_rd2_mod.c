// fsp_rd2_mod.c —— ROMREAD 批量转储器(一次 insmod 内循环:发请求→收回包→解析数据)
// 用法:
//   sudo insmod fsp_rd2_mod.ko start=0x0 end=0x800000 step=0x10000 len=4   # 粗扫找非FF岛
//   sudo insmod fsp_rd2_mod.ko start=0x1000 end=0x2000 step=0x100 len=0xff # 细转储
// 输出: dmesg 每行 "RD: addr=0x%06x len=%u d0=0x%08x d1=..." ;全 FF 行标 ALLFF
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <linux/delay.h>
#include <linux/string.h>

static unsigned long start = 0, end = 0x800000, step = 0x10000;
static int len = 4, port = 0, timeout_ms = 0, pace_ms = 30;  /* timeout_ms=0 ⇒ 自动=400+len*8 */
static int tmo_auto(int l) { return timeout_ms > 0 ? timeout_ms : (400 + l * 8); }
module_param(pace_ms, int, 0);
module_param(start, ulong, 0); module_param(end, ulong, 0); module_param(step, ulong, 0);
module_param(len, int, 0); module_param(port, int, 0); module_param(timeout_ms, int, 0);

#define MNOC_BASE 0x8f1e00U
#define SEND_INFO(p)  (MNOC_BASE + 0x104U + (p)*0x0cU)
#define SEND_RDATA(p) (MNOC_BASE + 0x108U + (p)*0x0cU)
#define RECV_INFO(p)  (MNOC_BASE + 0x184U + (p)*0x0cU)
#define RECV_WDATA(p) (MNOC_BASE + 0x188U + (p)*0x0cU)
#define SIZE_MASK 0x000fffffU
#define TRIGGER (1U<<20)
#define READY   (1U<<24)
#define ERR     (1U<<25)
#define CREDIT  (1U<<26)

static int wait_bit(void __iomem *b, u32 off, u32 mask, int want, int tmo)
{ int i; for (i=0;i<tmo;i++){ u32 v=ioread32(b+off); if (want?(v&mask):!(v&mask)) return 0; udelay(1000);} return -1; }

static int romread(void __iomem *b, u32 addr, u8 rlen, u32 *out, int outdw)
{
    u8 msg[16] = {0x01,0x00,0x00,0xc0, 0x7e,0xde,0x10,0x1a, 0x01,
                  (u8)(addr>>16),(u8)(addr>>8),(u8)addr, rlen, 0,0,0};
    u32 reg; int i, ndw = 0, rsp_dw;
    int _t = tmo_auto(len);
    {   /* 排空残留:READY 置位时读掉旧回包(最多 80 dword,防卡) */
        int _g;
        for (_g = 0; _g < 80 && (ioread32(b+SEND_INFO(port)) & READY); _g++)
            (void)ioread32(b+SEND_RDATA(port));
    }
    if (wait_bit(b, RECV_INFO(port), READY, 1, _t)) return -1;
    reg = ioread32(b+RECV_INFO(port));
    if (reg & ERR) return -2;
    reg &= ~SIZE_MASK; reg |= 16; reg |= TRIGGER;  /* 声明=补齐 16B(driver 口径) */
    iowrite32(reg, b+RECV_INFO(port));
    for (i = 0; i < 16; i += 4) {
        u32 d = msg[i] | (msg[i+1]<<8) | (msg[i+2]<<16) | (msg[i+3]<<24);
        if ((i & 63) == 0) { if (wait_bit(b, RECV_INFO(port), CREDIT, 1, _t)) return -1;
                             if (ioread32(b+RECV_INFO(port)) & ERR) return -2; }
        iowrite32(d, b+RECV_WDATA(port));
    }
    if (wait_bit(b, SEND_INFO(port), READY, 1, _t)) return -3;
    reg = ioread32(b+SEND_INFO(port));
    if (reg & ERR) return -2;
    rsp_dw = (int)(reg & SIZE_MASK) / 4;
    /* 头 5 dword 跳过(MCTP/NVDM/taskId/cmdType/err);数据从第 6 dword 起 */
    for (i = 0; i < rsp_dw && i < 5+outdw; i++) {
        u32 d = ioread32(b+SEND_RDATA(port));
        if (i >= 5 && i-5 < outdw) out[i-5] = d;
    }
    return (rsp_dw > 5) ? (rsp_dw-5)*4 : 0;   /* 返回数据字节数 */
}

static int __init rd_init(void)
{
    struct pci_dev *p; void __iomem *b; u32 addr; u32 out[64]; int nz = 0, ff = 0, err = 0;
    p = pci_get_domain_bus_and_slot(0,1,PCI_DEVFN(0,0)); if (!p) return -ENODEV;
    b = ioremap(pci_resource_start(p,0), 0xC00000); if (!b){ pci_dev_put(p); return -ENOMEM; }
    pr_err("RD: == ROMREAD 扫描 start=0x%lx end=0x%lx step=0x%lx len=%d ==\n", start, end, step, len);
    for (addr = start; addr < end; addr += step) {
        int n, i; memset(out, 0, sizeof(out));
        n = romread(b, addr, (u8)len, out, 64);
        if (n == -2) { pr_err("RD: addr=0x%06x ERR-LATCH(wedged) — 停扫\n", addr); break; }
        if (n < 0) { pr_err("RD: addr=0x%06x ERROR(%d)\n", addr, n); err++; continue; }
        if (n == 0) { pr_err("RD: addr=0x%06x EMPTY(err-code-rsp)\n", addr); continue; }
        { int allff = 1;
          for (i = 0; i < n/4 && i < 64; i++) if (out[i] != 0xffffffffU) allff = 0;
          if (allff) { ff++; if ((ff & 15) == 1) pr_err("RD: addr=0x%06x ALLFF\n", addr); continue; } }
        if (pace_ms > 0) mdelay(pace_ms);
        if (fatal_signal_pending(current)) { pr_err("RD: 致命信号,退出\n"); break; }
        { char line[256]; int o = 0;
          o += scnprintf(line+o, sizeof(line)-o, "RD: 0x%06x:", addr);
          for (i = 0; i < n/4 && i < 8; i++) o += scnprintf(line+o, sizeof(line)-o, " %08x", out[i]);
          pr_err("%s\n", line); nz++; }
    }
    pr_err("RD: == 完成: 非FF=%d 全FF区=%d 错误=%d ==\n", nz, ff, err);
    iounmap(b); pci_dev_put(p);
    return -EINVAL;
}
module_init(rd_init);
MODULE_LICENSE("GPL");

// fsp_probe2.c —— FSP/SEC2 EMEM 通道探针(第二版:带正确的 MCTP/NVDM 头 + 发送方声明长度操控)
// 用法(客体内核模块参数):
//   mode=send  hex="<十六进制字节>"  extra=<额外多声明的 dword 数>  chan=0
//   mode=prefill  pat=0xDEADBEEF  ndw=256 chan=0      # 先把通道后面填成标记(不敲门铃)
//   mode=recv   chan=0  nbytes=256                     # 读 MSGQ 回包
//   mode=peek   chan=0                                 # 只打印 EMEM/QUEUE/MSGQ 指针
// 关键探针思路:声明长度(写 QUEUE_TAIL)可以大于实际写入的字节数 ⇒ 考察 FSP 是否信任发送方声明的长度。
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <linux/string.h>
#include <linux/kernel.h>

static char *mode = "peek";
static char *hex = "";
static int extra = 0, chan = 0, nbytes = 256, ndw = 256;
static unsigned int pat = 0xDEADBEEF;
static int pb = 1, pd = 0, pf = 0;
static int tailbytes = 1;   /* 1=QTAIL 用字节语义(driver 口径) 0=旧的 dword 语义 */
module_param(mode, charp, 0); module_param(hex, charp, 0); module_param(extra, int, 0);
module_param(chan, int, 0); module_param(nbytes, int, 0); module_param(ndw, int, 0); module_param(pat, uint, 0);
module_param(pb, int, 0); module_param(pd, int, 0); module_param(pf, int, 0);
module_param(tailbytes, int, 0);

#define EMEMC(i) (0x8f2ac0 + 8*(i))
#define EMEMD(i) (0x8f2ac4 + 8*(i))
#define QHEAD(i) (0x8f2c00 + 8*(i))
#define QTAIL(i) (0x8f2c04 + 8*(i))
#define MHEAD(i) (0x8f2c80 + 8*(i))
#define MTAIL(i) (0x8f2c84 + 8*(i))

static int hexval(char c){ if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return c-'a'+10; if(c>='A'&&c<='F')return c-'A'+10; return -1; }
static int parse_hex(const char *s, u8 *out, int max){ int n=0; while(s[0]&&s[1]&&n<max){ int h=hexval(s[0]),l=hexval(s[1]); if(h<0||l<0)break; out[n++]=(h<<4)|l; s+=2; } return n; }

static int __init p2_init(void)
{
    struct pci_dev *pdev; void __iomem *bar; u32 ememc, v; int i;
    pdev = pci_get_domain_bus_and_slot(0, pb, PCI_DEVFN(pd,pf));
    if (!pdev) { pr_err("fsp2: no device\n"); return -ENODEV; }
    bar = ioremap(pci_resource_start(pdev,0), 0xC00000);
    if (!bar) { pci_dev_put(pdev); return -ENOMEM; }
    pr_err("fsp2: chan=%d EMEMC=%#x QH=%u QT=%u MH=%u MT=%u\n", chan,
        ioread32(bar+EMEMC(chan)), ioread32(bar+QHEAD(chan)), ioread32(bar+QTAIL(chan)),
        ioread32(bar+MHEAD(chan)), ioread32(bar+MTAIL(chan)));
    if (!strcmp(mode,"peek")) goto out;
    if (!strcmp(mode,"prefill")) {
        iowrite32(0x01000000u | (0u<<2), bar+EMEMC(chan));   // 偏移 0 + AINCW
        for (i=0;i<ndw;i++) iowrite32(pat, bar+EMEMD(chan));
        pr_err("fsp2: prefill 写了 %d 个 dword = %#x(未敲 QUEUE_TAIL ⇒ FSP 看不见)\n", ndw, pat);
        pr_err("fsp2: 之后 EMEMC=%#x\n", ioread32(bar+EMEMC(chan)));
        goto out;
    }
    if (!strcmp(mode,"send")) {
        u8 buf[1024]; int n = parse_hex(hex, buf, 1024);
        int nd = (n+3)/4;
        int declared = nd + extra;
        if (n==0) { pr_err("fsp2: 空报文\n"); goto out; }
        iowrite32(0x01000000u, bar+EMEMC(chan));             // 偏移 0 + AINCW
        for (i=0;i<nd;i++){ u32 w=0; memcpy(&w, buf+4*i, min(4,n-4*i)); iowrite32(w, bar+EMEMD(chan)); }
        { u32 _tail; size_t _bytes = (size_t)declared * 4u;
          _tail = tailbytes ? (u32)(((_bytes + 3u) & ~3u) - 4u) : (u32)(declared - 1);
          iowrite32(_tail, bar+QTAIL(chan));
          pr_err("fsp2: QTAIL=%u (tailbytes=%d, 声明 %zu 字节, 实际 %d 字节)\n", _tail, tailbytes, _bytes, n); }
        iowrite32(0, bar+QHEAD(chan));                       // 敲门铃
        pr_err("fsp2: 发送 %d 字节(%d dword),声明 %d dword(多报 %d) ⇒ QT=%u\n",
               n, nd, declared, extra, ioread32(bar+QTAIL(chan)));
        goto out;
    }
    if (!strcmp(mode,"ack")) {
        u32 mt = ioread32(bar+MTAIL(chan));
        iowrite32(mt, bar+MHEAD(chan));
        pr_err("fsp2: ack ⇒ MSGQ_HEAD=%u (TAIL=%u)\n", ioread32(bar+MHEAD(chan)), mt);
        goto out;
    }
    if (!strcmp(mode,"recv")) {
        u32 mh = ioread32(bar+MHEAD(chan)), mt = ioread32(bar+MTAIL(chan));
        int len = (int)(mt - mh) + 4, k;
        pr_err("fsp2: MSGQ head=%u tail=%u ⇒ 长度 %d 字节\n", mh, mt, len);
        if (len <= 0 || len > 4096) { pr_err("fsp2: 长度不合理,跳过\n"); goto out; }
        ememc = 0x02000000u;                                  // 偏移 0 + AINCR
        iowrite32(ememc, bar+EMEMC(chan));
        for (k=0;k<len/4+1;k++){ v = ioread32(bar+EMEMD(chan)); pr_err("fsp2: [%2d] %#010x\n", k, v); }
        goto out;
    }
out:
    iounmap(bar); pci_dev_put(pdev);
    return -EINVAL;   // 加载后立即退出
}
module_init(p2_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("FSP EMEM probe v2");

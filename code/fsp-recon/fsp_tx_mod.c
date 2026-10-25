// fsp_tx_mod.c —— 通用 MNOC 报文发送器(内核态;任意载荷/可覆写声明长度/回包读取)
// 用法:
//   sudo insmod fsp_tx_mod.ko msg="010000c0 7ede1014 ..."       # 空格分隔 hex(也可连续)
//   参数: port=1 declared=0(诚实)/其它(覆写 INFO SIZE) timeout_ms=3000 no_rsp=0
// 发送序列 = b3_mod 已验证序列;回包读取 = fsp_od 已验证序列。自卸载(-EINVAL)。
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <linux/string.h>
#include <linux/delay.h>

static int port = 1, timeout_ms = 3000, no_rsp = 0;
static unsigned long declared = 0;
static char *msg = "";
static int cot_mode = 0;
static int cot_ver = -1, cot_size = -1;
static unsigned long cot_fmc = 0;
module_param(port, int, 0); module_param(timeout_ms, int, 0);
module_param(no_rsp, int, 0); module_param(declared, ulong, 0); module_param(msg, charp, 0);
module_param(cot_mode, int, 0); module_param(cot_ver, int, 0);
module_param(cot_size, int, 0); module_param(cot_fmc, ulong, 0);

/* 构造 COT 载荷(NVDM_PAYLOAD_COT,860B,pack(1)):
   u16 ver; u16 size; u64 gspFmc; u64 frtsSys; u32 frtsSysSz; u64 frtsVid; u32 frtsVidSz;
   u32 hash[12]; u32 pub[96]; u32 sig[96]; u64 bootArgs */
static int build_cot(u8 *buf, int buflen)
{
    u64 fmc = (u64)cot_fmc;
    if (buflen < 860) return -1;
    memset(buf, 0, 860);
    *(u16 *)(buf + 0)  = (u16)(cot_ver & 0xffff);
    *(u16 *)(buf + 2)  = (u16)(cot_size & 0xffff);
    *(u64 *)(buf + 4)  = fmc;
    /* 其余全零 */
    return 860;
}

#define MNOC_BASE       0x8f1e00U
#define SEND_INFO(p)    (MNOC_BASE + 0x104U + (p)*0x0cU)
#define SEND_RDATA(p)   (MNOC_BASE + 0x108U + (p)*0x0cU)
#define RECV_INFO(p)    (MNOC_BASE + 0x184U + (p)*0x0cU)
#define RECV_WDATA(p)   (MNOC_BASE + 0x188U + (p)*0x0cU)
#define SIZE_MASK       0x000fffffU
#define TRIGGER         (1U<<20)
#define READY           (1U<<24)
#define ERR             (1U<<25)
#define CREDIT          (1U<<26)

static int wait_bit(void __iomem *b, u32 off, u32 mask, int want, int tmo, const char *w)
{
    int i;
    for (i = 0; i < tmo; i++) {
        u32 v = ioread32(b+off);
        if (want ? (v & mask) : !(v & mask)) return 0;
        udelay(1000);
    }
    pr_err("FTX: 等 %s 超时 off=0x%x last=0x%08x\n", w, off, ioread32(b+off));
    return -1;
}

static void st(void __iomem *b, const char *tag)
{
    pr_err("FTX: [%s] p%d send=0x%08x recv=0x%08x | scratch9f=%08x ad00bc=%08x\n",
           tag, port, ioread32(b+SEND_INFO(port)), ioread32(b+RECV_INFO(port)),
           ioread32(b+0x8f0320), ioread32(b+0xad00bc));
}

static int hexval(char c){ if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return c-'a'+10; if(c>='A'&&c<='F')return c-'A'+10; return -1; }

static int __init ftx_init(void)
{
    struct pci_dev *p; void __iomem *b;
    u8 buf[4096]; int n = 0, i; u32 reg; int declared_len;
    if (cot_mode) {
        u8 hdr[8] = {0x01,0x00,0x00,0xc0, 0x7e,0xde,0x10,0x14};
        int body = build_cot(buf + 8, sizeof(buf) - 8);
        if (body < 0) { pr_err("FTX: COT 构造失败\n"); return -EINVAL; }
        memcpy(buf, hdr, 8);
        n = 8 + body;
        pr_err("FTX: COT 模式 ver=0x%x size=0x%x fmc=0x%lx 总长=%d\n", cot_ver, cot_size, cot_fmc, n);
    } else {
    const char *s = msg;
    /* 解析 hex(忽略空格) */
    while (*s && n < (int)sizeof(buf)) {
        int h = hexval(*s);
        if (h < 0) { if (*s==' '||*s==','||*s==':') { s++; continue; } break; }
        s++;
        { int l = hexval(*s); if (l < 0) { pr_err("FTX: hex 奇数个字符\n"); return -EINVAL; } s++;
          buf[n++] = (u8)((h<<4)|l); }
    }
    if (n < 4) { pr_err("FTX: msg 太短(%d 字节),至少 8(MCTP+NVDM)\n", n); return -EINVAL; }
    }
    pr_err("FTX: port=%d len=%d declared=%lu timeout=%dms\n", port, n, declared, timeout_ms);
    for (i = 0; i < n; i += 4)
        pr_err("FTX:  TX[%03x] %02x %02x %02x %02x\n", i, buf[i], (n>i+1)?buf[i+1]:0, (n>i+2)?buf[i+2]:0, (n>i+3)?buf[i+3]:0);
    p = pci_get_domain_bus_and_slot(0, 1, PCI_DEVFN(0, 0));
    if (!p) { pr_err("FTX: 无设备\n"); return -ENODEV; }
    b = ioremap(pci_resource_start(p, 0), 0xC00000);
    if (!b) { pci_dev_put(p); return -ENOMEM; }
    st(b, "前");
    /* --- 发送(b3_mod 已验证序列) --- */
    if (wait_bit(b, RECV_INFO(port), READY, 1, timeout_ms, "RECV_READY") != 0) goto out;
    reg = ioread32(b+RECV_INFO(port));
    if (reg & ERR) { pr_err("FTX: 发送前 ERR=1 (0x%08x)\n", reg); goto out; }
    declared_len = declared ? (int)(declared & 0xfffff) : n;
    reg &= ~SIZE_MASK; reg |= (u32)declared_len; reg |= TRIGGER;
    iowrite32(reg, b+RECV_INFO(port));
    pr_err("FTX: INFO=0x%08x (声明=%d 实际=%d)\n", reg, declared_len, n);
    for (i = 0; i < n; i += 4) {
        u32 d = buf[i] | ((u32)(n>i+1?buf[i+1]:0)<<8) | ((u32)(n>i+2?buf[i+2]:0)<<16) | ((u32)(n>i+3?buf[i+3]:0)<<24);
        if ((i % 64) == 0) {
            if (wait_bit(b, RECV_INFO(port), CREDIT, 1, timeout_ms, "CREDIT") != 0) goto out;
            reg = ioread32(b+RECV_INFO(port));
            if (reg & ERR) { pr_err("FTX: off=0x%x 处 ERR=1 (0x%08x)\n", i, reg); goto out; }
        }
        iowrite32(d, b+RECV_WDATA(port));
    }
    pr_err("FTX: 已推送 %d 字节\n", n);
    if (no_rsp) { st(b, "后"); goto out; }
    /* --- 回包(fsp_od 已验证序列) --- */
    if (wait_bit(b, SEND_INFO(port), READY, 1, timeout_ms, "send mailbox ready") != 0) { st(b, "超时"); goto out; }
    reg = ioread32(b+SEND_INFO(port));
    if (reg & ERR) { pr_err("FTX: 回包前 ERR=1 (0x%08x)\n", reg); goto out; }
    { u32 rsz = reg & SIZE_MASK; int off = 0;
      pr_err("FTX: 回包 size=%u\n", rsz);
      if (rsz >= 4 && rsz <= 1024) {
        while (off < (int)rsz) {
            u32 d;
            reg = ioread32(b+SEND_INFO(port));
            if (reg & ERR) { pr_err("FTX: 回包中 ERR=1 (0x%08x) @off=%d\n", reg, off); break; }
            if (!(reg & READY)) { pr_err("FTX: 回包 ready 掉落 @off=%d info=0x%08x\n", off, reg); break; }
            d = ioread32(b+SEND_RDATA(port));
            pr_err("FTX:  RX[%03x] %08x\n", off, d);
            off += 4;
        }
        if (off >= 16)
            pr_err("FTX: 解码 taskId=0x%08x cmdType=0x%08x errorCode=0x%08x\n",
                   ioread32(b+SEND_INFO(port)) & 0, 0, 0); /* 占位;实际解码在用户侧做 */
      }
    }
    st(b, "后");
out:
    iounmap(b); pci_dev_put(p);
    return -EINVAL;
}
module_init(ftx_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("FTX: generic MNOC message sender (self-unloading)");

// poll_mod.c —— 常驻寄存器采样器:每 period_ms 采一次,只打印"变化"并带时间戳
// 用途:观察设备初始化过程中(以及驱动加载/卸载时)各许可位/掩码寄存器何时改变
// 用法: insmod poll_mod.ko period_ms=10 duration_s=120
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/io.h>
#include <linux/kthread.h>
#include <linux/delay.h>
#include <linux/timekeeping.h>

static int period_ms = 10, duration_s = 120;
module_param(period_ms, int, 0);
module_param(duration_s, int, 0);


struct regent { unsigned off; const char *name; };
static const struct regent T[] = {
    {0x8200d0, "plm_floorsweep_0"}, {0x8200dc, "plm_l2_raw_sw"},
    {0x8200e0, "plm_e0"},           {0x8200f4, "plm_f4"},
    {0x8200f8, "plm_latch"},        {0x8200fc, "plm_fc"},
    {0x820040, "latch_req"},        {0x820434, "reset_coupling"},
    {0x8212ac, "disable_sw_override"},
    {0x8234e0, "raw_fbp0"},         {0x8234fc, "raw_fbp7"},
    {0x822900, "eff_fbp0"},         {0x82291c, "eff_fbp7"},
    {0x820004, "w_820004"},         {0x820008, "w_820008"},
    {0x821000, "w_821000"},         {0x821004, "w_821004"},
};
#define NREG (sizeof(T)/sizeof(T[0]))

static struct pci_dev *g_pdev;
static void __iomem *g_bar;
static struct task_struct *g_th;
static u32 prev[NREG];
static int have_prev;
static u64 t0;

static u64 us_now(void) { return ktime_to_us(ktime_get_boottime()); }

static int poller(void *arg)
{
    unsigned long stop = jiffies + (unsigned long)duration_s * HZ;
    int i, n = 0;
    while (!kthread_should_stop() && time_before(jiffies, stop)) {
        for (i = 0; i < (int)NREG; i++) {
            u32 v = ioread32(g_bar + T[i].off);
            if (!have_prev || v != prev[i]) {
                pr_err("POLL %8llu us  +%06x %-20s = 0x%08x%s\n",
                       us_now() - t0, T[i].off, T[i].name, v,
                       have_prev ? "  <== 变化" : "  (基线)");
                prev[i] = v;
            }
        }
        have_prev = 1;
        if ((n++ % (1000 / (period_ms > 0 ? period_ms : 10))) == 0)
            pr_err("POLL -- 心跳 %llu us(仍在采样)--\n", us_now() - t0);
        msleep(period_ms > 0 ? period_ms : 10);
    }
    pr_err("POLL 结束:采样 %d 轮\n", n);
    return 0;
}

static int __init pm_init(void)
{
    g_pdev = pci_get_domain_bus_and_slot(0, 0, PCI_DEVFN(2, 0));
    if (!g_pdev) { pr_err("POLL: 未找到设备\n"); return -ENODEV; }
    g_bar = ioremap(pci_resource_start(g_pdev, 0), 0x900000);
    if (!g_bar) { pci_dev_put(g_pdev); return -ENOMEM; }
    t0 = us_now();
    g_th = kthread_run(poller, NULL, "regpoller");
    if (IS_ERR(g_th)) { iounmap(g_bar); pci_dev_put(g_pdev); return -ENOMEM; }
    pr_err("POLL: 启动采样 period=%dms duration=%ds 寄存器数=%zu\n",
           period_ms, duration_s, NREG);
    return 0;   /* 保持加载,采样在后台线程进行 */
}

static void __exit pm_exit(void)
{
    if (g_th) kthread_stop(g_th);
    if (g_bar) iounmap(g_bar);
    if (g_pdev) pci_dev_put(g_pdev);
    pr_err("POLL: 模块卸载\n");
}
module_init(pm_init);
module_exit(pm_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("register change poller");

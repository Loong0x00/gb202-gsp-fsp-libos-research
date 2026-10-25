// fsp_lie_probe.c —— 探测 FSP 的 MNOC 信箱是否信任"发送方声明的长度"
// 做法:把声明长度写进 MNOC_RECV_INFO[19:0],但实际只推入更少的数据。
// 用法: fsp_lie_probe <bdf> normal|<declared_bytes> [pushed_bytes]
//   例: fsp_lie_probe 0000:00:02.0 normal 16     ← 对照组(声明=实际)
//       fsp_lie_probe 0000:00:02.0 4096 16       ← 声明 4096,只推 16 字节
// 只做一件事:发一条 CAPS_QUERY(NVDM 0x16)。不写任何固件/熔丝。
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <sys/mman.h>

#define BAR0_MAP_LEN            0x00900000U
#define FSP_MNOC_BASE           0x008f1e00U
#define MNOC_SEND_INFO(p)       (FSP_MNOC_BASE + 0x104U + ((p) * 0x0cU))
#define MNOC_SEND_RDATA(p)      (FSP_MNOC_BASE + 0x108U + ((p) * 0x0cU))
#define MNOC_RECV_INFO(p)       (FSP_MNOC_BASE + 0x184U + ((p) * 0x0cU))
#define MNOC_RECV_WDATA(p)      (FSP_MNOC_BASE + 0x188U + ((p) * 0x0cU))
#define MNOC_MESSAGE_SIZE_MASK  0x000fffffU
#define MNOC_RECV_TRIGGER       (1U << 20)
#define MNOC_SEND_READY         (1U << 24)
#define MNOC_RECV_READY         (1U << 24)
#define MNOC_SEND_ERR           (1U << 25)
#define MNOC_RECV_ERR           (1U << 25)
#define MNOC_RECV_CREDIT        (1U << 26)
#define MCTP_MSG_VENDOR_PCI     0x7eU
#define MCTP_VENDOR_NVIDIA      0x10deU
#define NVDM_TYPE_CAPS_QUERY    0x16U

static volatile uint8_t *bar;
static inline uint32_t rd32(uint32_t off) { return *(volatile uint32_t *)(bar + off); }
static inline void wr32(uint32_t off, uint32_t v) { *(volatile uint32_t *)(bar + off) = v; }
static uint32_t now_ms(void){ struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts);
    return (uint32_t)(ts.tv_sec*1000ULL + ts.tv_nsec/1000000ULL); }
static void p32(uint8_t *p, uint32_t v){ p[0]=v; p[1]=v>>8; p[2]=v>>16; p[3]=v>>24; }

static int wait_bit(uint32_t off, uint32_t mask, uint32_t want, unsigned to_ms,
                    const char *label, uint32_t *out) {
    uint32_t t0 = now_ms();
    for (;;) {
        uint32_t v = rd32(off);
        if ((v & mask) == want) { if (out) *out = v; return 0; }
        if ((uint32_t)(now_ms() - t0) > to_ms) {
            printf("  [超时] %s: 0x%08x 等 0x%08x\n", label, v, want); return -1;
        }
        usleep(1000);
    }
}

int main(int argc, char **argv) {
    const char *bdf = argc > 1 ? argv[1] : "0000:00:02.0";
    unsigned declared, pushed;
    bool normal = (argc > 2 && strcmp(argv[2], "normal") == 0);
    if (normal) { declared = pushed = (argc > 3 ? (unsigned)strtoul(argv[3],0,0) : 16); }
    else {
        if (argc < 3) { fprintf(stderr, "用法: %s <bdf> normal|<declared> [pushed]\n", argv[0]); return 2; }
        declared = (unsigned)strtoul(argv[2], 0, 0);
        pushed   = (argc > 3 ? (unsigned)strtoul(argv[3], 0, 0) : 16);
    }
    if (declared < 4 || declared > (MNOC_MESSAGE_SIZE_MASK + 1U)) { fprintf(stderr,"声明长度非法\n"); return 2; }
    if (pushed > declared) { fprintf(stderr, "pushed > declared,无意义\n"); return 2; }

    char path[128]; snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/resource0", bdf);
    int fd = open(path, O_RDWR | O_CLOEXEC | O_SYNC);
    if (fd < 0) { fprintf(stderr, "open %s: %s\n", path, strerror(errno)); return 1; }
    bar = mmap(NULL, BAR0_MAP_LEN, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    if (bar == MAP_FAILED) { fprintf(stderr, "mmap: %s\n", strerror(errno)); return 1; }

    const unsigned port = 2;   /* CPU 固定 port 2 */
    printf("=== FSP 信箱长度信任探测: declared=%u pushed=%u port=%u ===\n", declared, pushed, port);
    printf("  发送前 RECV_INFO=0x%08x SEND_INFO=0x%08x\n", rd32(MNOC_RECV_INFO(port)), rd32(MNOC_SEND_INFO(port)));

    uint32_t info = 0;
    if (wait_bit(MNOC_RECV_INFO(port), MNOC_RECV_READY, MNOC_RECV_READY, 2000, "recv ready", &info)) return 1;
    if (info & MNOC_RECV_ERR) { printf("  发送前 ERR 已置位:0x%08x\n", info); return 1; }

    /* 组一条合法的 CAPS_QUERY: MCTP dword0 + NVDM dword1 + submessage */
    uint8_t msg[64]; memset(msg, 0, sizeof(msg));
    p32(msg + 0, 0xC0000001U | 0x0U);                       /* SOM|EOM|version1 */
    p32(msg + 4, MCTP_MSG_VENDOR_PCI | (MCTP_VENDOR_NVIDIA << 8) | (NVDM_TYPE_CAPS_QUERY << 24));
    msg[8] = 0x0;                                            /* caps subMessageId */
    if (pushed > sizeof(msg)) { fprintf(stderr, "pushed 太大(本工具上限 %zu)\n", sizeof(msg)); return 2; }

    /* 关键一步:声明长度 = declared(而实际只推 pushed 字节) */
    info = rd32(MNOC_RECV_INFO(port));
    info &= ~MNOC_MESSAGE_SIZE_MASK;
    info |= declared & MNOC_MESSAGE_SIZE_MASK;
    info |= MNOC_RECV_TRIGGER;
    wr32(MNOC_RECV_INFO(port), info);
    printf("  已写 RECV_INFO=0x%08x(声明长度=%u)\n", info, declared);

    for (unsigned off = 0; off < pushed; off += 4) {
        uint32_t d = 0;
        if ((off % 64U) == 0)
            if (wait_bit(MNOC_RECV_INFO(port), MNOC_RECV_CREDIT, MNOC_RECV_CREDIT, 2000, "credit", &info)) return 1;
        memcpy(&d, msg + off, (pushed - off < 4) ? (pushed - off) : 4);
        wr32(MNOC_RECV_WDATA(port), d);
    }
    printf("  已推入 %u 字节数据(声明 %u)\n", pushed, declared);

    uint32_t si = 0; uint32_t t0 = now_ms();
    for (;;) {
        si = rd32(MNOC_SEND_INFO(port));
        if (si & MNOC_SEND_ERR) { printf("  !! 发送侧 ERR 置位:0x%08x\n", si); break; }
        if (si & MNOC_SEND_READY) {
            uint32_t n = si & MNOC_MESSAGE_SIZE_MASK;
            printf("  收到响应: size=%u\n", n);
            if (n >= 4 && n < 1024) {
                printf("  响应前 16 字节:");
                for (uint32_t i = 0; i < n && i < 16; i += 4) {
                    uint32_t w = rd32(MNOC_SEND_RDATA(port));
                    printf(" %08x", w);
                    if (i == 0) printf("(首字节=0x%02x)", w & 0xff);
                }
                printf("\n");
            }
            break;
        }
        if ((uint32_t)(now_ms() - t0) > 1500) { printf("  !! 1.5s 内无响应,RECV_INFO=0x%08x SEND_INFO=0x%08x\n", rd32(MNOC_RECV_INFO(port)), si); break; }
        usleep(1000);
    }
    printf("  结束状态: RECV_INFO=0x%08x SEND_INFO=0x%08x\n", rd32(MNOC_RECV_INFO(port)), rd32(MNOC_SEND_INFO(port)));
    return 0;
}

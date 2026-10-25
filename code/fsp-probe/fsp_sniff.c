// fsp_sniff.c —— B7a: MNOC/PSEC/PFSP 纯只读嗅探(零写入)
// 用途: 捕捉 FSP→宿主方向的 MNOC 发向活动(端口归属 + FSP↔GSP 流量)、PSEC(SEC2)队列活动、
//       PFSP EMEM 队列活动。任何寄存器只读。
// 用法: sudo ./fsp_sniff [间隔ms=200] [时长s=60] [--bdf 0000:01:00.0]
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/stat.h>

#define BAR0_MAP_LEN 0x00900000u
#define FSP_MNOC_BASE 0x008f1e00u
#define MNOC_SEND_INFO(p)  (FSP_MNOC_BASE + 0x104u + (p)*0x0cu)
#define MNOC_SEND_RDATA(p) (FSP_MNOC_BASE + 0x108u + (p)*0x0cu)
#define MNOC_RECV_INFO(p)  (FSP_MNOC_BASE + 0x184u + (p)*0x0cu)
#define PFSP_QUEUE_H 0x8f2c00u
#define PFSP_QUEUE_T 0x8f2c04u
#define PFSP_MSGQ_H  0x8f2c80u
#define PFSP_MSGQ_T  0x8f2c84u
#define PSEC_MSGQ_H  0x840c80u
#define PSEC_MSGQ_T  0x840c84u
#define PSEC_MBOX0   0x840040u
#define PSEC_MBOX1   0x840044u

static inline uint32_t rd32(volatile uint8_t *bar, uint32_t off) {
    return *(volatile uint32_t *)(bar + off);
}

int main(int argc, char **argv)
{
    long interval_ms = argc > 1 ? strtol(argv[1], NULL, 0) : 200;
    long duration_s  = argc > 2 ? strtol(argv[2], NULL, 0) : 60;
    const char *bdf  = "0000:01:00.0";
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--bdf") && i + 1 < argc) bdf = argv[++i];
    }
    char res[128];
    snprintf(res, sizeof(res), "/sys/bus/pci/devices/%s/resource0", bdf);
    int fd = open(res, O_RDONLY | O_CLOEXEC | O_SYNC);
    if (fd < 0) { fprintf(stderr, "open %s: %s\n", res, strerror(errno)); return 1; }
    struct stat st;
    if (fstat(fd, &st) || (uint64_t)st.st_size < BAR0_MAP_LEN) { fprintf(stderr, "BAR0 too short\n"); return 1; }
    volatile uint8_t *bar = mmap(NULL, BAR0_MAP_LEN, PROT_READ, MAP_SHARED, fd, 0);
    if (bar == MAP_FAILED) { fprintf(stderr, "mmap: %s\n", strerror(errno)); return 1; }

    uint32_t prev[32]; memset(prev, 0, sizeof(prev));
    // index map: 0..3 send_info p0..3, 4..7 recv_info p0..3, 8..9 pfsp qh/qt, 10..11 pfsp mh/mt,
    //            12..13 psec mh/mt, 14..15 psec mbox0/1, 16..19 send_info again for rdata capture
    struct timespec ts0, ts;
    clock_gettime(CLOCK_MONOTONIC, &ts0);
    long samples = 0, deltas = 0;
    printf("# sniff start interval=%ldms duration=%lds\n", interval_ms, duration_s);
    printf("# t  send_info[0..3]  recv_info[0..3]  pfspQ(H T)  pfspM(H T)  psecM(H T)  psecMB(0 1)\n");
    for (;;) {
        clock_gettime(CLOCK_MONOTONIC, &ts);
        double t = (ts.tv_sec - ts0.tv_sec) + (ts.tv_nsec - ts0.tv_nsec) / 1e9;
        if (t >= duration_s) break;
        uint32_t cur[16];
        for (int p = 0; p < 4; p++) {
            cur[p]     = rd32(bar, MNOC_SEND_INFO(p));
            cur[4 + p] = rd32(bar, MNOC_RECV_INFO(p));
        }
        cur[8]  = rd32(bar, PFSP_QUEUE_H); cur[9]  = rd32(bar, PFSP_QUEUE_T);
        cur[10] = rd32(bar, PFSP_MSGQ_H);  cur[11] = rd32(bar, PFSP_MSGQ_T);
        cur[12] = rd32(bar, PSEC_MSGQ_H);  cur[13] = rd32(bar, PSEC_MSGQ_T);
        cur[14] = rd32(bar, PSEC_MBOX0);   cur[15] = rd32(bar, PSEC_MBOX1);
        int changed = (samples == 0);
        for (int i = 0; i < 16; i++) if (cur[i] != prev[i]) changed = 1;
        if (changed) {
            printf("[%8.3f] send=%08x %08x %08x %08x | recv=%08x %08x %08x %08x | pfspQ=%08x/%08x pfspM=%08x/%08x | psecM=%08x/%08x psecMB=%08x/%08x\n",
                   t, cur[0], cur[1], cur[2], cur[3], cur[4], cur[5], cur[6], cur[7],
                   cur[8], cur[9], cur[10], cur[11], cur[12], cur[13], cur[14], cur[15]);
            // 若某端口发向 READY=1(bit24) 抓 RDATA 流(只读)
            for (int p = 0; p < 2; p++) {
                if ((cur[p] >> 24) & 1) {
                    uint32_t sz = cur[p] & 0xfffff;
                    printf("  [port%d TX-FSP->host size=0x%x] rdata:", p, sz);
                    for (uint32_t k = 0; k < (sz ? sz / 4 : 0) && k < 64; k++)
                        printf(" %08x", rd32(bar, MNOC_SEND_RDATA(p)));
                    printf("\n");
                }
            }
            fflush(stdout);
            deltas++;
        }
        memcpy(prev, cur, sizeof(cur));
        samples++;
        usleep(interval_ms * 1000);
    }
    printf("# sniff done samples=%ld delta-events=%ld\n", samples, deltas);
    munmap((void *)bar, BAR0_MAP_LEN);
    close(fd);
    return 0;
}

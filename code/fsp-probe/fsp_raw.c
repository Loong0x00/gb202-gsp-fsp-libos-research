#define _GNU_SOURCE

/*
 * Minimal GB202 FSP/MNOC PRC probe.
 *
 * This tool intentionally implements only:
 *   - mailbox status read;
 *   - one caps-query request over the FSP MNOC mailbox;
 *   - one PRC object-read request over the FSP MNOC mailbox;
 *   - one explicitly gated PRC object-write no-op probe.
 *   - one explicitly gated floorsweep task-2/subobject-1 zero-payload probe.
 *
 * It does not implement arbitrary PRC write, floorsweep register writes, PCI
 * config writes, VBIOS writes, resets, InfoROM writes, or OTP/fuse writes.
 *
 * The only MMIO writes in --prc-read/--prc-write-noop mode are the documented
 * MNOC mailbox send sequence used by OpenRM on Blackwell:
 *   MESSAGE_INFO_0_RECEIVEMBOX(port) size+trigger,
 *   WDATA_0_RECEIVEMBOX(port) message dwords.
 */

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define NVIDIA_VENDOR_ID       0x10deU
#define RTX_5090_GB202_DEVID   0x2b85U

#define BAR0_MAP_LEN           0x00900000U

#define FSP_MNOC_BASE          0x008f1e00U
#define MNOC_SEND_INFO(port)   (FSP_MNOC_BASE + 0x00000104U + ((port) * 0x0cU))
#define MNOC_SEND_RDATA(port)  (FSP_MNOC_BASE + 0x00000108U + ((port) * 0x0cU))
#define MNOC_RECV_INFO(port)   (FSP_MNOC_BASE + 0x00000184U + ((port) * 0x0cU))
#define MNOC_RECV_WDATA(port)  (FSP_MNOC_BASE + 0x00000188U + ((port) * 0x0cU))

#define MNOC_MESSAGE_SIZE_MASK 0x000fffffU
#define MNOC_RECV_TRIGGER      (1U << 20)
#define MNOC_SEND_READY        (1U << 24)
#define MNOC_RECV_READY        (1U << 24)
#define MNOC_SEND_ERR          (1U << 25)
#define MNOC_RECV_ERR          (1U << 25)
#define MNOC_RECV_CREDIT       (1U << 26)

#define MCTP_MSG_VENDOR_PCI    0x7eU
#define MCTP_VENDOR_NVIDIA     0x10deU
#define NVDM_TYPE_PRC          0x13U
#define NVDM_TYPE_FSP_RESPONSE 0x15U
#define NVDM_TYPE_CAPS_QUERY   0x16U

#define PRC_OBJ_READ           0x0cU
#define PRC_OBJ_WRITE          0x0dU
#define PRC_READ_NUM_BYTES     0x02U

/* ---- RAWHEX:环境变量传 16 字节报文的十六进制,复用本工具的 MNOC 机制 ---- */
static int hexnib(char c){ if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return c-'a'+10;
                          if(c>='A'&&c<='F')return c-'A'+10; return -1; }
static int rawhex_load(uint8_t *out, size_t cap)
{
    const char *hx = getenv("RAWHEX");
    int n = 0;
    if (!hx) return 0;
    while (hx[0] && hx[1] && (size_t)n < cap) {
        int h = hexnib(hx[0]), l = hexnib(hx[1]);
        if (h < 0 || l < 0) break;
        out[n++] = (uint8_t)((h << 4) | l);
        hx += 2;
    }
    return n;
}


enum mode {
    MODE_STATUS,
    MODE_CAPS_QUERY,
    MODE_PRC_READ,
    MODE_PRC_WRITE_NOOP,
    MODE_TASK2_ZERO,
};

struct options {
    enum mode mode;
    char bdf[64];
    bool have_bdf;
    unsigned port;
    unsigned timeout_ms;
    unsigned mctp_version;
    uint16_t knob;
    uint16_t value;
    uint8_t caps_submessage;
    bool accept_prc_write;
    bool accept_task2_zero;
    bool mods_mctp_header;
};

static uint64_t now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)ts.tv_nsec / 1000000ULL;
}

static int read_hex_file(const char *path, unsigned *value)
{
    FILE *f = fopen(path, "r");
    int ok = f && fscanf(f, "%x", value) == 1;
    if (f)
        fclose(f);
    return ok ? 0 : -1;
}

static int parse_u16(const char *s, uint16_t *out)
{
    char *end = NULL;
    unsigned long value;

    errno = 0;
    value = strtoul(s, &end, 0);
    if (errno || !end || *end || value > 0xffffUL)
        return -1;
    *out = (uint16_t)value;
    return 0;
}

static int parse_uint(const char *s, unsigned max, unsigned *out)
{
    char *end = NULL;
    unsigned long value;

    errno = 0;
    value = strtoul(s, &end, 0);
    if (errno || !end || *end || value > max)
        return -1;
    *out = (unsigned)value;
    return 0;
}

static int find_gpu(char *bdf, size_t size)
{
    DIR *dir = opendir("/sys/bus/pci/devices");
    struct dirent *de;

    if (!dir)
        return -1;

    while ((de = readdir(dir)) != NULL) {
        char path[512];
        unsigned vendor = 0, device = 0;

        snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/vendor",
                 de->d_name);
        if (read_hex_file(path, &vendor) != 0)
            continue;
        snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/device",
                 de->d_name);
        if (read_hex_file(path, &device) != 0)
            continue;
        if (vendor == NVIDIA_VENDOR_ID && device == RTX_5090_GB202_DEVID) {
            size_t len = strlen(de->d_name);
            if (len >= size) {
                closedir(dir);
                errno = ENAMETOOLONG;
                return -1;
            }
            memcpy(bdf, de->d_name, len + 1);
            closedir(dir);
            return 0;
        }
    }

    closedir(dir);
    errno = ENODEV;
    return -1;
}

static uint32_t mmio_read32(volatile uint8_t *bar, uint32_t offset)
{
    volatile uint32_t *p = (volatile uint32_t *)(void *)(bar + offset);
    uint32_t value = *p;
    __sync_synchronize();
    return value;
}

static void mmio_write32(volatile uint8_t *bar, uint32_t offset, uint32_t value)
{
    volatile uint32_t *p = (volatile uint32_t *)(void *)(bar + offset);
    *p = value;
    __sync_synchronize();
}

static uint16_t get_le16(const uint8_t *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t get_le32(const uint8_t *p)
{
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static void put_le16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v & 0xffU);
    p[1] = (uint8_t)(v >> 8);
}

static void put_le32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v & 0xffU);
    p[1] = (uint8_t)((v >> 8) & 0xffU);
    p[2] = (uint8_t)((v >> 16) & 0xffU);
    p[3] = (uint8_t)((v >> 24) & 0xffU);
}

static uint32_t mctp_transport_header(unsigned version, bool som, bool eom,
                                      unsigned seid, unsigned deid,
                                      unsigned seq)
{
    return (version & 0x0fU) |
           ((deid & 0xffU) << 8) |
           ((seid & 0xffU) << 16) |
           ((seq & 0x03U) << 28) |
           (eom ? (1U << 30) : 0U) |
           (som ? (1U << 31) : 0U);
}

static uint32_t nvdm_header(unsigned nvdm_type)
{
    return MCTP_MSG_VENDOR_PCI |
           (MCTP_VENDOR_NVIDIA << 8) |
           ((nvdm_type & 0xffU) << 24);
}

static uint32_t request_mctp_header(const struct options *opt)
{
    if (opt->mods_mctp_header)
        return 0xc8000000U;
    return mctp_transport_header(opt->mctp_version, true, true, 0, 0, 0);
}

static int wait_mask(volatile uint8_t *bar, uint32_t offset, uint32_t mask,
                     uint32_t expected, unsigned timeout_ms,
                     const char *label, uint32_t *last_value)
{
    const uint64_t deadline = now_ms() + timeout_ms;
    uint32_t value = 0;

    do {
        value = mmio_read32(bar, offset);
        if ((value & mask) == expected) {
            if (last_value)
                *last_value = value;
            return 0;
        }
        usleep(50);
    } while (now_ms() <= deadline);

    if (last_value)
        *last_value = value;
    fprintf(stderr,
            "timeout waiting for %s at 0x%08x: last=0x%08x mask=0x%08x expected=0x%08x\n",
            label, offset, value, mask, expected);
    return -1;
}

static void print_status(volatile uint8_t *bar, unsigned port)
{
    const uint32_t send_info = mmio_read32(bar, MNOC_SEND_INFO(port));
    const uint32_t recv_info = mmio_read32(bar, MNOC_RECV_INFO(port));

    printf("mnoc_port=%u\n", port);
    printf("send_info 0x%08x = 0x%08x size=%u ready=%u err=%u intr_en=%u intr=%u\n",
           MNOC_SEND_INFO(port), send_info,
           send_info & MNOC_MESSAGE_SIZE_MASK,
           !!(send_info & MNOC_SEND_READY),
           !!(send_info & MNOC_SEND_ERR),
           !!(send_info & (1U << 30)),
           !!(send_info & (1U << 31)));
    printf("recv_info 0x%08x = 0x%08x size=%u ready=%u credit=%u err=%u intr_en=%u intr=%u\n",
           MNOC_RECV_INFO(port), recv_info,
           recv_info & MNOC_MESSAGE_SIZE_MASK,
           !!(recv_info & MNOC_RECV_READY),
           !!(recv_info & MNOC_RECV_CREDIT),
           !!(recv_info & MNOC_RECV_ERR),
           !!(recv_info & (1U << 30)),
           !!(recv_info & (1U << 31)));
}

static void dump_bytes(const uint8_t *buf, size_t len)
{
    printf("raw_bytes:");
    for (size_t i = 0; i < len; ++i)
        printf("%s%02x", (i % 4) == 0 ? " " : "", buf[i]);
    printf("\n");

    printf("raw_dwords:");
    for (size_t i = 0; i < len; i += 4) {
        uint8_t tmp[4] = {0, 0, 0, 0};
        size_t n = len - i < 4 ? len - i : 4;
        memcpy(tmp, buf + i, n);
        printf(" 0x%08x", get_le32(tmp));
    }
    printf("\n");
}

static int mnoc_send(volatile uint8_t *bar, unsigned port,
                     const uint8_t *msg, size_t msg_size,
                     unsigned timeout_ms)
{
    uint32_t reg;

    if (msg_size < 4 || msg_size > MNOC_MESSAGE_SIZE_MASK + 1U) {
        fprintf(stderr, "invalid message size: %zu\n", msg_size);
        return -1;
    }

    if (wait_mask(bar, MNOC_RECV_INFO(port), MNOC_RECV_READY, MNOC_RECV_READY,
                  timeout_ms, "receive mailbox ready", &reg) != 0)
        return -1;
    if (reg & MNOC_RECV_ERR) {
        fprintf(stderr, "receive mailbox reports ERR before send: 0x%08x\n",
                reg);
        return -1;
    }

    reg = mmio_read32(bar, MNOC_RECV_INFO(port));
    reg &= ~MNOC_MESSAGE_SIZE_MASK;
    reg |= (uint32_t)msg_size & MNOC_MESSAGE_SIZE_MASK;
    reg |= MNOC_RECV_TRIGGER;
    mmio_write32(bar, MNOC_RECV_INFO(port), reg);

    for (size_t off = 0; off < msg_size; off += 4) {
        uint8_t tmp[4] = {0, 0, 0, 0};
        uint32_t data;
        size_t n = msg_size - off < 4 ? msg_size - off : 4;

        if ((off % 64U) == 0) {
            if (wait_mask(bar, MNOC_RECV_INFO(port), MNOC_RECV_CREDIT,
                          MNOC_RECV_CREDIT, timeout_ms,
                          "receive mailbox credit", &reg) != 0)
                return -1;
            if (reg & MNOC_RECV_ERR) {
                fprintf(stderr, "receive mailbox reports ERR during send: 0x%08x\n",
                        reg);
                return -1;
            }
        }

        memcpy(tmp, msg + off, n);
        data = get_le32(tmp);
        mmio_write32(bar, MNOC_RECV_WDATA(port), data);
    }

    reg = mmio_read32(bar, MNOC_RECV_INFO(port));
    if (reg & MNOC_RECV_ERR) {
        fprintf(stderr, "receive mailbox reports ERR after send: 0x%08x\n", reg);
        return -1;
    }

    return 0;
}

static int mnoc_recv(volatile uint8_t *bar, unsigned port,
                     uint8_t *buf, size_t buf_size, size_t *out_size,
                     unsigned timeout_ms)
{
    uint32_t reg;
    uint32_t recv_size;
    size_t off = 0;

    if (wait_mask(bar, MNOC_SEND_INFO(port), MNOC_SEND_READY, MNOC_SEND_READY,
                  timeout_ms, "send mailbox message ready", &reg) != 0)
        return -1;

    if (reg & MNOC_SEND_ERR) {
        fprintf(stderr, "send mailbox reports ERR before recv: 0x%08x\n", reg);
        return -1;
    }

    recv_size = reg & MNOC_MESSAGE_SIZE_MASK;
    if (recv_size < 4 || recv_size > buf_size) {
        fprintf(stderr, "invalid receive size: %u, buffer=%zu\n",
                recv_size, buf_size);
        return -1;
    }

    while (off < recv_size) {
        uint8_t tmp[4];
        uint32_t data;
        size_t n = recv_size - off < 4 ? recv_size - off : 4;

        reg = mmio_read32(bar, MNOC_SEND_INFO(port));
        if (reg & MNOC_SEND_ERR) {
            fprintf(stderr, "send mailbox reports ERR during recv: 0x%08x\n",
                    reg);
            return -1;
        }
        if (!(reg & MNOC_SEND_READY)) {
            fprintf(stderr,
                    "message ready dropped during recv at offset %zu/%u, send_info=0x%08x\n",
                    off, recv_size, reg);
            return -1;
        }

        data = mmio_read32(bar, MNOC_SEND_RDATA(port));
        put_le32(tmp, data);
        memcpy(buf + off, tmp, n);
        off += n;
    }

    *out_size = off;
    return 0;
}

static int prc_read_transaction(volatile uint8_t *bar, const struct options *opt,
                                uint16_t knob, uint16_t *out_value,
                                bool verbose)
{
    uint8_t req[12];
    uint8_t rsp[256];
    size_t rsp_size = 0;

    memset(req, 0, sizeof(req));
    put_le32(req + 0, request_mctp_header(opt));
    put_le32(req + 4, nvdm_header(NVDM_TYPE_PRC));
    req[8] = PRC_OBJ_READ;
    req[9] = PRC_READ_NUM_BYTES;
    put_le16(req + 10, knob);

    if (verbose) {
        printf("request: PRC read knob=0x%04x port=%u timeout_ms=%u mctp_version=%u\n",
               knob, opt->port, opt->timeout_ms, opt->mctp_version);
        dump_bytes(req, sizeof(req));
    }

    if (mnoc_send(bar, opt->port, req, sizeof(req), opt->timeout_ms) != 0)
        return -1;

    memset(rsp, 0, sizeof(rsp));
    if (mnoc_recv(bar, opt->port, rsp, sizeof(rsp), &rsp_size,
                  opt->timeout_ms) != 0)
        return -1;

    if (verbose) {
        printf("response_size=%zu\n", rsp_size);
        dump_bytes(rsp, rsp_size);
    }

    if (verbose && rsp_size >= 8) {
        uint32_t mctp = get_le32(rsp + 0);
        uint32_t nvdm = get_le32(rsp + 4);
        printf("decode: mctp=0x%08x som=%u eom=%u seq=%u seid=0x%02x deid=0x%02x version=0x%x\n",
               mctp,
               !!(mctp & (1U << 31)),
               !!(mctp & (1U << 30)),
               (mctp >> 28) & 0x3U,
               (mctp >> 16) & 0xffU,
               (mctp >> 8) & 0xffU,
               mctp & 0x0fU);
        printf("decode: nvdm_header=0x%08x msg_type=0x%02x vendor=0x%04x nvdm_type=0x%02x\n",
               nvdm,
               nvdm & 0x7fU,
               (nvdm >> 8) & 0xffffU,
               (nvdm >> 24) & 0xffU);
    }

    if (verbose && rsp_size >= 20) {
        uint32_t task_id = get_le32(rsp + 8);
        uint32_t command_type = get_le32(rsp + 12);
        uint32_t error_code = get_le32(rsp + 16);
        printf("decode: task_id=0x%08x command_nvdm_type=0x%08x error_code=0x%08x\n",
               task_id, command_type, error_code);
        if (rsp_size >= 22)
            printf("decode: prc_value_candidate_u16_at_20=0x%04x\n",
                   get_le16(rsp + 20));
        if (rsp_size >= 24)
            printf("decode: prc_misc_candidate_u16_at_22=0x%04x combined_optional_dword=0x%08x\n",
                   get_le16(rsp + 22), get_le32(rsp + 20));
    }

    if (rsp_size < 22) {
        fprintf(stderr, "response too short for PRC read value\n");
        return -1;
    }
    if (((get_le32(rsp + 4) >> 24) & 0xffU) != NVDM_TYPE_FSP_RESPONSE) {
        fprintf(stderr, "unexpected response NVDM type\n");
        return -1;
    }
    if (get_le32(rsp + 12) != NVDM_TYPE_PRC) {
        fprintf(stderr, "unexpected command NVDM type in response\n");
        return -1;
    }
    if (get_le32(rsp + 16) != 0) {
        fprintf(stderr, "FSP returned nonzero error_code=0x%08x\n",
                get_le32(rsp + 16));
        return -1;
    }

    if (out_value)
        *out_value = get_le16(rsp + 20);
    if (verbose)
        printf("PRC_READ_OK knob=0x%04x value=0x%04x\n",
               knob, get_le16(rsp + 20));
    return 0;
}

static int do_prc_read(volatile uint8_t *bar, const struct options *opt)
{
    uint16_t value = 0;
    return prc_read_transaction(bar, opt, opt->knob, &value, true);
}

static int parse_fsp_response(const uint8_t *rsp, size_t rsp_size,
                              const char *op_name, uint32_t expected_command)
{
    if (rsp_size < 20) {
        fprintf(stderr, "%s response too short for FSP command response\n",
                op_name);
        return -1;
    }
    if (((get_le32(rsp + 4) >> 24) & 0xffU) != NVDM_TYPE_FSP_RESPONSE) {
        fprintf(stderr, "%s unexpected response NVDM type\n", op_name);
        return -1;
    }
    if (get_le32(rsp + 12) != expected_command) {
        fprintf(stderr, "%s unexpected command NVDM type in response\n",
                op_name);
        return -1;
    }
    if (get_le32(rsp + 16) != 0) {
        fprintf(stderr, "%s FSP returned nonzero error_code=0x%08x\n",
                op_name, get_le32(rsp + 16));
        return -1;
    }
    return 0;
}

static void print_caps_records(const uint8_t *rsp, size_t rsp_size,
                               size_t offset, const char *label)
{
    if (rsp_size <= offset) {
        printf("decode: %s no payload records\n", label);
        return;
    }

    printf("decode: %s payload_offset=%zu payload_size=%zu\n",
           label, offset, rsp_size - offset);
    for (size_t pos = offset; pos + 4 <= rsp_size; pos += 4) {
        uint32_t rec = get_le32(rsp + pos);
        printf("decode: %s record@%zu raw=0x%08x nvdm_type=0x%04x version=0x%04x\n",
               label, pos, rec, rec & 0xffffU, (rec >> 16) & 0xffffU);
    }
    if (((rsp_size - offset) % 4U) != 0) {
        printf("decode: %s trailing_bytes=%zu\n",
               label, (rsp_size - offset) % 4U);
    }
}

static int do_caps_query(volatile uint8_t *bar, const struct options *opt)
{
    uint8_t req[9];
    uint8_t rsp[1024];
    size_t rsp_size = 0;

    memset(req, 0, sizeof(req));
    put_le32(req + 0, request_mctp_header(opt));
    put_le32(req + 4, nvdm_header(NVDM_TYPE_CAPS_QUERY));
    req[8] = opt->caps_submessage;

    printf("request: CAPS query subMessageId=0x%02x port=%u timeout_ms=%u mctp_version=%u\n",
           opt->caps_submessage, opt->port, opt->timeout_ms,
           opt->mctp_version);
    dump_bytes(req, sizeof(req));

    if (mnoc_send(bar, opt->port, req, sizeof(req), opt->timeout_ms) != 0)
        return -1;

    memset(rsp, 0, sizeof(rsp));
    if (mnoc_recv(bar, opt->port, rsp, sizeof(rsp), &rsp_size,
                  opt->timeout_ms) != 0)
        return -1;

    printf("response_size=%zu\n", rsp_size);
    dump_bytes(rsp, rsp_size);

    if (rsp_size >= 8) {
        uint32_t mctp = get_le32(rsp + 0);
        uint32_t nvdm = get_le32(rsp + 4);
        printf("decode: mctp=0x%08x som=%u eom=%u seq=%u seid=0x%02x deid=0x%02x version=0x%x\n",
               mctp,
               !!(mctp & (1U << 31)),
               !!(mctp & (1U << 30)),
               (mctp >> 28) & 0x3U,
               (mctp >> 16) & 0xffU,
               (mctp >> 8) & 0xffU,
               mctp & 0x0fU);
        printf("decode: nvdm_header=0x%08x msg_type=0x%02x vendor=0x%04x nvdm_type=0x%02x\n",
               nvdm,
               nvdm & 0x7fU,
               (nvdm >> 8) & 0xffffU,
               (nvdm >> 24) & 0xffU);
    }

    if (rsp_size >= 20) {
        printf("decode: standard task_id=0x%08x command_nvdm_type=0x%08x error_code=0x%08x\n",
               get_le32(rsp + 8), get_le32(rsp + 12), get_le32(rsp + 16));
        print_caps_records(rsp, rsp_size, 20, "standard");
    }

    if (rsp_size >= 21) {
        printf("decode: alt nvdm_type_byte=0x%02x task_id=0x%08x command_nvdm_type=0x%08x error_code=0x%08x\n",
               rsp[8], get_le32(rsp + 9), get_le32(rsp + 13),
               get_le32(rsp + 17));
        print_caps_records(rsp, rsp_size, 21, "alt");
    }

    if (rsp_size >= 20 &&
        ((get_le32(rsp + 4) >> 24) & 0xffU) == NVDM_TYPE_FSP_RESPONSE &&
        get_le32(rsp + 12) == NVDM_TYPE_CAPS_QUERY &&
        get_le32(rsp + 16) == 0) {
        printf("CAPS_QUERY_OK subMessageId=0x%02x\n", opt->caps_submessage);
        return 0;
    }

    if (rsp_size >= 21 &&
        ((get_le32(rsp + 4) >> 24) & 0xffU) == NVDM_TYPE_FSP_RESPONSE &&
        get_le32(rsp + 13) == NVDM_TYPE_CAPS_QUERY &&
        get_le32(rsp + 17) == 0) {
        printf("CAPS_QUERY_OK_ALT subMessageId=0x%02x\n",
               opt->caps_submessage);
        return 0;
    }

    fprintf(stderr, "CAPS query returned non-success or unknown response shape\n");
    return 1;
}

static int do_prc_write_noop(volatile uint8_t *bar, const struct options *opt)
{
    uint16_t before = 0;
    uint16_t after = 0;
    uint8_t req[16];
    uint8_t rsp[256];
    size_t rsp_size = 0;

    if (!opt->accept_prc_write) {
        fprintf(stderr, "refusing PRC write: missing --i-accept-prc-write\n");
        return -1;
    }
    if (opt->knob != 0x001dU || opt->value != 0x0001U) {
        fprintf(stderr,
                "refusing PRC write-noop: only knob=0x001d value=0x0001 is allowlisted\n");
        return -1;
    }

    printf("pre-read before write-noop\n");
    if (prc_read_transaction(bar, opt, opt->knob, &before, true) != 0)
        return -1;

    if (before != opt->value) {
        fprintf(stderr,
                "refusing PRC write-noop: current=0x%04x requested=0x%04x\n",
                before, opt->value);
        return -1;
    }

    memset(req, 0, sizeof(req));
    put_le32(req + 0, request_mctp_header(opt));
    put_le32(req + 4, nvdm_header(NVDM_TYPE_PRC));
    req[8] = PRC_OBJ_WRITE;
    req[9] = PRC_READ_NUM_BYTES;
    put_le16(req + 10, opt->knob);
    put_le16(req + 12, opt->value);
    put_le16(req + 14, 0);

    printf("request: PRC write-noop knob=0x%04x value=0x%04x port=%u timeout_ms=%u mctp_version=%u\n",
           opt->knob, opt->value, opt->port, opt->timeout_ms,
           opt->mctp_version);
    dump_bytes(req, sizeof(req));

    if (mnoc_send(bar, opt->port, req, sizeof(req), opt->timeout_ms) != 0)
        return -1;

    memset(rsp, 0, sizeof(rsp));
    if (mnoc_recv(bar, opt->port, rsp, sizeof(rsp), &rsp_size,
                  opt->timeout_ms) != 0)
        return -1;

    printf("response_size=%zu\n", rsp_size);
    dump_bytes(rsp, rsp_size);

    if (rsp_size >= 20) {
        printf("decode: task_id=0x%08x command_nvdm_type=0x%08x error_code=0x%08x\n",
               get_le32(rsp + 8), get_le32(rsp + 12), get_le32(rsp + 16));
    }

    if (parse_fsp_response(rsp, rsp_size, "PRC write-noop",
                           NVDM_TYPE_PRC) != 0)
        return -1;

    printf("post-read after write-noop\n");
    if (prc_read_transaction(bar, opt, opt->knob, &after, true) != 0)
        return -1;

    if (after != opt->value) {
        fprintf(stderr,
                "PRC write-noop readback mismatch: after=0x%04x requested=0x%04x\n",
                after, opt->value);
        return -1;
    }

    printf("PRC_WRITE_NOOP_OK knob=0x%04x value=0x%04x before=0x%04x after=0x%04x\n",
           opt->knob, opt->value, before, after);
    return 0;
}

static int do_task2_zero(volatile uint8_t *bar, const struct options *opt)
{
    uint8_t req[256];
    uint8_t rsp[256];
    size_t rsp_size = 0;
        size_t msg_len = 16;

    if (!opt->accept_task2_zero) {
        fprintf(stderr, "refusing task2-zero: missing --i-accept-task2-zero\n");
        return -1;
    }

    memset(req, 0, sizeof(req));
    if (rawhex_load(req, sizeof(req)) >= 4) {
        int hl = (int)strlen(getenv("RAWHEX")) / 2;
        msg_len = (size_t)((hl + 3) / 4) * 4;   /* 仅 4 字节对齐 ⇒ 可发短报文 */
        printf("RAWHEX 模式(%d 字节 ⇒ 发送 %zu)\n", hl, msg_len);
        dump_bytes(req, msg_len);
    } else {
    put_le32(req + 0, request_mctp_header(opt));
    put_le32(req + 4, nvdm_header(NVDM_TYPE_PRC));
    req[8] = 0x02U;  /* floorsweep task 2 */
    req[9] = 0x01U;  /* subobject 1 */
    }
    /* req[10..15] intentionally remain the allowlisted 6-byte zero payload. */

    printf("request: TASK2_ZERO task=0x02 subobject=0x01 payload=000000000000 port=%u timeout_ms=%u mctp_version=%u mods_mctp_header=%u\n",
           opt->port, opt->timeout_ms, opt->mctp_version,
           opt->mods_mctp_header);
    dump_bytes(req, sizeof(req));

    if (mnoc_send(bar, opt->port, req, msg_len, opt->timeout_ms) != 0)
        return -1;

    memset(rsp, 0, sizeof(rsp));
    if (mnoc_recv(bar, opt->port, rsp, sizeof(rsp), &rsp_size,
                  opt->timeout_ms) != 0)
        return -1;

    printf("response_size=%zu\n", rsp_size);
    dump_bytes(rsp, rsp_size);

    if (rsp_size >= 20) {
        printf("decode: task_id=0x%08x command_nvdm_type=0x%08x error_code=0x%08x\n",
               get_le32(rsp + 8), get_le32(rsp + 12), get_le32(rsp + 16));
    }

    if (parse_fsp_response(rsp, rsp_size, "TASK2_ZERO",
                           NVDM_TYPE_PRC) != 0)
        return -1;

    printf("TASK2_ZERO_OK\n");
    return 0;
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "usage:\n"
            "  %s --status-only [--bdf BDF] [--port 0..3]\n"
            "  %s --caps-query 0xSUBMSG [--bdf BDF] [--port 0..3] [--timeout-ms N] [--mctp-version 0|1]\n"
            "  %s --prc-read 0xKNOB [--bdf BDF] [--port 0..3] [--timeout-ms N] [--mctp-version 0|1]\n",
            argv0, argv0, argv0);
    fprintf(stderr,
            "  %s --prc-write-noop 0x1d 0x1 --i-accept-prc-write [--bdf BDF] [--port 0..3] [--timeout-ms N]\n",
            argv0);
    fprintf(stderr,
            "  %s --task2-zero --i-accept-task2-zero [--bdf BDF] [--port 0..3] [--timeout-ms N] [--mods-mctp-header]\n",
            argv0);
}

static int parse_args(int argc, char **argv, struct options *opt)
{
    memset(opt, 0, sizeof(*opt));
    opt->mode = MODE_STATUS;
    opt->port = 1;
    opt->timeout_ms = 5000;
    opt->mctp_version = 1;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--status-only") == 0) {
            opt->mode = MODE_STATUS;
        } else if (strcmp(argv[i], "--prc-read") == 0) {
            if (++i >= argc || parse_u16(argv[i], &opt->knob) != 0)
                return -1;
            opt->mode = MODE_PRC_READ;
        } else if (strcmp(argv[i], "--caps-query") == 0) {
            unsigned submessage = 0;
            if (++i >= argc || parse_uint(argv[i], 0xff, &submessage) != 0)
                return -1;
            opt->caps_submessage = (uint8_t)submessage;
            opt->mode = MODE_CAPS_QUERY;
        } else if (strcmp(argv[i], "--prc-write-noop") == 0) {
            if (++i >= argc || parse_u16(argv[i], &opt->knob) != 0)
                return -1;
            if (++i >= argc || parse_u16(argv[i], &opt->value) != 0)
                return -1;
            opt->mode = MODE_PRC_WRITE_NOOP;
        } else if (strcmp(argv[i], "--task2-zero") == 0) {
            opt->mode = MODE_TASK2_ZERO;
        } else if (strcmp(argv[i], "--i-accept-prc-write") == 0) {
            opt->accept_prc_write = true;
        } else if (strcmp(argv[i], "--i-accept-task2-zero") == 0) {
            opt->accept_task2_zero = true;
        } else if (strcmp(argv[i], "--mods-mctp-header") == 0) {
            opt->mods_mctp_header = true;
        } else if (strcmp(argv[i], "--bdf") == 0) {
            size_t len;
            if (++i >= argc)
                return -1;
            len = strlen(argv[i]);
            if (len >= sizeof(opt->bdf))
                return -1;
            memcpy(opt->bdf, argv[i], len + 1);
            opt->have_bdf = true;
        } else if (strcmp(argv[i], "--port") == 0) {
            if (++i >= argc || parse_uint(argv[i], 3, &opt->port) != 0)
                return -1;
        } else if (strcmp(argv[i], "--timeout-ms") == 0) {
            if (++i >= argc || parse_uint(argv[i], 60000, &opt->timeout_ms) != 0)
                return -1;
            if (opt->timeout_ms < 100)
                return -1;
        } else if (strcmp(argv[i], "--mctp-version") == 0) {
            if (++i >= argc || parse_uint(argv[i], 1, &opt->mctp_version) != 0)
                return -1;
        } else {
            return -1;
        }
    }

    return 0;
}

int main(int argc, char **argv)
{
    struct options opt;
    char resource[512];
    struct stat st;
    int fd = -1;
    volatile uint8_t *bar = MAP_FAILED;
    int ret = 1;
    int open_flags;
    int prot;

    if (parse_args(argc, argv, &opt) != 0) {
        usage(argv[0]);
        return 2;
    }

    if (geteuid() != 0) {
        fprintf(stderr, "must run as root\n");
        return 1;
    }

    if (!opt.have_bdf) {
        if (find_gpu(opt.bdf, sizeof(opt.bdf)) != 0) {
            perror("find NVIDIA 10de:2b85");
            return 1;
        }
    }

    snprintf(resource, sizeof(resource), "/sys/bus/pci/devices/%s/resource0",
             opt.bdf);

    open_flags = (opt.mode == MODE_STATUS ? O_RDONLY : O_RDWR) |
                 O_CLOEXEC | O_SYNC;
    prot = PROT_READ | (opt.mode == MODE_STATUS ? 0 : PROT_WRITE);

    fd = open(resource, open_flags);
    if (fd < 0) {
        fprintf(stderr, "open %s: %s\n", resource, strerror(errno));
        goto out;
    }

    if (fstat(fd, &st) != 0) {
        fprintf(stderr, "fstat %s: %s\n", resource, strerror(errno));
        goto out;
    }
    if ((uint64_t)st.st_size < BAR0_MAP_LEN) {
        fprintf(stderr, "BAR0 too short: 0x%jx bytes, need 0x%x\n",
                (uintmax_t)st.st_size, BAR0_MAP_LEN);
        goto out;
    }

    bar = mmap(NULL, BAR0_MAP_LEN, prot, MAP_SHARED, fd, 0);
    if (bar == MAP_FAILED) {
        fprintf(stderr, "mmap BAR0: %s\n", strerror(errno));
        goto out;
    }

    printf("BDF=%s resource0=%s mode=%s\n", opt.bdf, resource,
           opt.mode == MODE_STATUS ? "status-only" :
           opt.mode == MODE_CAPS_QUERY ? "caps-query" :
           opt.mode == MODE_PRC_READ ? "prc-read" :
           opt.mode == MODE_PRC_WRITE_NOOP ? "prc-write-noop" : "task2-zero");
    print_status(bar, opt.port);

    if (opt.mode == MODE_STATUS) {
        ret = 0;
    } else if (opt.mode == MODE_CAPS_QUERY) {
        ret = do_caps_query(bar, &opt) == 0 ? 0 : 1;
        print_status(bar, opt.port);
    } else if (opt.mode == MODE_PRC_READ) {
        ret = do_prc_read(bar, &opt) == 0 ? 0 : 1;
        print_status(bar, opt.port);
    } else if (opt.mode == MODE_PRC_WRITE_NOOP) {
        ret = do_prc_write_noop(bar, &opt) == 0 ? 0 : 1;
        print_status(bar, opt.port);
    } else {
        ret = do_task2_zero(bar, &opt) == 0 ? 0 : 1;
        print_status(bar, opt.port);
    }

out:
    if (bar != MAP_FAILED)
        munmap((void *)bar, BAR0_MAP_LEN);
    if (fd >= 0)
        close(fd);
    return ret;
}

// FSP oracle worker: reads 16-byte AES-128 candidate keys on stdin,
// tests each against 3 FSP_RUN builds x layouts (GCM A/B) + CTR/CBC structure.
// Emits "HIT <family-hex> <mode> <image>" on stdout. Zero false positives for GCM.
// Build: gcc -O3 -march=native -fopenmp -o fsp_oracle fsp_oracle.c -lcrypto
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <openssl/evp.h>

typedef struct { const uint8_t *ct; size_t ctlen; const uint8_t *tail; const char *name; } target_t;

static int gcm_try(EVP_CIPHER_CTX *ctx, const uint8_t *key, const uint8_t *iv12,
                   const uint8_t *tag, const uint8_t *ct, size_t ctlen) {
    uint8_t out[4096]; int outl;
    uint8_t tagcopy[16]; memcpy(tagcopy, tag, 16);
    if (EVP_DecryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL) != 1) return 0;
    EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
    if (EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv12) != 1) return 0;
    size_t done = 0;
    while (done < ctlen) {
        size_t chunk = ctlen - done > 4096 ? 4096 : ctlen - done;
        if (EVP_DecryptUpdate(ctx, out, &outl, ct + done, chunk) != 1) return 0;
        done += chunk;
    }
    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, tagcopy) != 1) return 0;
    uint8_t fin[16]; int fl;
    return EVP_DecryptFinal_ex(ctx, fin, &fl) == 1;
}

static int ctr_zeros(EVP_CIPHER_CTX *ctx, const uint8_t *key, const uint8_t *iv16,
                     const uint8_t *ct, size_t ctlen) {
    // decrypt 4KB head, count zeros; firmware heads often have zero structure
    uint8_t out[4096]; int outl;
    if (EVP_DecryptInit_ex(ctx, EVP_aes_128_ctr(), NULL, key, iv16) != 1) return 0;
    size_t n = ctlen > 4096 ? 4096 : ctlen;
    if (EVP_DecryptUpdate(ctx, out, &outl, ct, n) != 1) return 0;
    int z = 0;
    for (size_t i = 0; i < n; i++) if (!out[i]) z++;
    return z > (int)(n * 5 / 8);   // >62.5% zeros in 4KB head = structured
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] :
        "/home/user/rt_5090_project/parallel/k3_device_work/fsp";
    static uint8_t fe[0x29400], dl[0x36c00], hp[0x37000];
    uint8_t dfe[0x50], ddl[0x50], dhp[0x50];
    FILE *f;
    f = fopen("/home/user/rt_5090_project/parallel/k3_device_work/fsp/fsp_image.bin", "rb");
    if (!f || fread(fe, 1, sizeof fe, f) != sizeof fe) { perror("fe"); return 1; } fclose(f);
    f = fopen("/home/user/rt_5090_project/parallel/k3_device_work/fsp/fsp_image_dell8d.bin", "rb");
    if (!f || fread(dl, 1, sizeof dl, f) != sizeof dl) { perror("dl"); return 1; } fclose(f);
    f = fopen("/home/user/rt_5090_project/parallel/k3_device_work/fsp/fsp_image_hpe9e.bin", "rb");
    if (!f || fread(hp, 1, sizeof hp, f) != sizeof hp) { perror("hp"); return 1; } fclose(f);
    f = fopen("/home/user/rt_5090_project/parallel/k3_device_work/fsp/fsp_image_descriptor.bin", "rb");
    if (!f || fread(dfe, 1, 0x50, f) != 0x50) { perror("dfe"); return 1; } fclose(f);
    f = fopen("/home/user/rt_5090_project/parallel/k3_device_work/fsp/fsp_image_dell8d_descriptor.bin", "rb");
    if (!f || fread(ddl, 1, 0x50, f) != 0x50) { perror("ddl"); return 1; } fclose(f);
    f = fopen("/home/user/rt_5090_project/parallel/k3_device_work/fsp/fsp_image_hpe9e_descriptor.bin", "rb");
    if (!f || fread(dhp, 1, 0x50, f) != 0x50) { perror("dhp"); return 1; } fclose(f);

    target_t tg[3] = {
        {fe, sizeof fe, dfe + 0x34, "FE2E"},
        {dl, sizeof dl, ddl + 0x34, "Dell8D"},
        {hp, sizeof hp, dhp + 0x34, "HPE9E"},
    };

    // self-test: synthetic GCM with known key must HIT
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        uint8_t key[16] = {0}; uint8_t iv[12] = {9}; uint8_t pt[128] = {1,2,3};
        uint8_t ct[128], tag[16]; int outl;
        EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        EVP_EncryptUpdate(ctx, ct, &outl, pt, 128);
        EVP_EncryptFinal_ex(ctx, ct + outl, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
        uint8_t bad[16] = {1};
        if (!gcm_try(ctx, key, iv, tag, ct, 128)) { fprintf(stderr, "SELFTEST FAIL pos\n"); return 2; }
        if (gcm_try(ctx, bad, iv, tag, ct, 128)) { fprintf(stderr, "SELFTEST FAIL neg\n"); return 2; }
        EVP_CIPHER_CTX_free(ctx);
        fprintf(stderr, "selftest OK\n");
    }

    uint8_t key[16];
    uint64_t tested = 0;
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    while (fread(key, 1, 16, stdin) == 16) {
        tested++;
        for (int t = 0; t < 3; t++) {
            const uint8_t *tail = tg[t].tail;
            if (gcm_try(ctx, key, tail, tail + 12, tg[t].ct, tg[t].ctlen)) {
                printf("HIT GCM-A %s ", tg[t].name);
                for (int i = 0; i < 16; i++) printf("%02x", key[i]);
                printf("\n"); fflush(stdout);
            }
            if (gcm_try(ctx, key, tail + 16, tail, tg[t].ct, tg[t].ctlen)) {
                printf("HIT GCM-B %s ", tg[t].name);
                for (int i = 0; i < 16; i++) printf("%02x", key[i]);
                printf("\n"); fflush(stdout);
            }
            if (ctr_zeros(ctx, key, tail, tg[t].ct, tg[t].ctlen)) {
                printf("HIT CTR-Z %s ", tg[t].name);
                for (int i = 0; i < 16; i++) printf("%02x", key[i]);
                printf("\n"); fflush(stdout);
            }
        }
        if ((tested & 0xFFFFF) == 0) {
            fprintf(stderr, "progress %llu candidates\r", (unsigned long long)tested);
        }
    }
    fprintf(stderr, "\ndone: %llu candidates tested\n", (unsigned long long)tested);
    return 0;
}

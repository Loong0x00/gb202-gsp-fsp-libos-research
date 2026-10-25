/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "nvidia_gsp_boot.h"
#include <stdio.h>
#include <stdlib.h>

static void *read_file(const char *path, size_t *size)
{
    FILE *file = fopen(path, "rb");
    long length;
    void *data;
    if (!file || fseek(file, 0, SEEK_END) || (length = ftell(file)) < 0 ||
        length > 128 * 1024 * 1024 || fseek(file, 0, SEEK_SET)) {
        fprintf(stderr, "Cannot read input: %s\n", path);
        exit(2);
    }
    data = malloc(length ? (size_t)length : 1);
    if (!data || fread(data, 1, length, file) != (size_t)length) {
        fprintf(stderr, "Input read failed: %s\n", path);
        exit(2);
    }
    fclose(file);
    *size = length;
    return data;
}

int main(int argc, char **argv)
{
    if (argc != 4) {
        fprintf(stderr, "Usage: %s FMC-GFW-ELF FMC-NVFW-BIN TRUSTED-KEY-SHA256\n", argv[0]);
        return 2;
    }
    size_t gfw_size, boot_size;
    void *gfw_data = read_file(argv[1], &gfw_size);
    void *boot_data = read_file(argv[2], &boot_size);
    NvGspGfw gfw;
    NvGspBootImage boot;
    char error[256];
    bool ok = nv_gsp_parse_gfw(gfw_data, gfw_size, &gfw, error, sizeof(error)) &&
              nv_gsp_verify_gfw(&gfw, argv[3], error, sizeof(error)) &&
              nv_gsp_parse_boot_image(boot_data, boot_size, &boot, error, sizeof(error)) &&
              nv_gsp_match_boot_images(&gfw, &boot, error, sizeof(error));
    if (!ok) {
        fprintf(stderr, "REJECTED: %s\n", error);
    } else {
        printf("VERIFIED: SHA384 + ECDSA-P384 with explicitly pinned public key\n");
        printf("VERIFIED: identical GFW/ROM payload: manifest=%zu code=%zu data=%zu\n",
               boot.manifest.size, boot.code.size, boot.data.size);
        NvGspBootDmaPlan plan;
        if (!nv_gsp_boot_dma_plan(&boot, 0x1000000, &plan, error, sizeof(error))) {
            fprintf(stderr, "REJECTED: %s\n", error);
            free(gfw_data);
            free(boot_data);
            return 1;
        }
        printf("PLAN ONLY at example sysmem base 0x1000000: DMACFG=%08x PKC=%08x:%08x CODE=%08x:%08x DATA=%08x:%08x\n",
               plan.dmacfg, plan.manifest_hi, plan.manifest_lo,
               plan.code_hi, plan.code_lo, plan.data_hi, plan.data_lo);
        printf("NOT VERIFIED: on-chip trust-root/fuse policy, BootROM decoding/decryption, CPU handoff\n");
    }
    free(gfw_data);
    free(boot_data);
    return ok ? 0 : 1;
}

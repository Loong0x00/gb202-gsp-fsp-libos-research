#!/usr/bin/env python3
"""
FSP key grinder driver — generates candidate keys from NVIDIA-flavored derivation
families and feeds them to the C GCM/CTR oracle worker (fsp_oracle.c).

Oracle targets: FSP_RUN x3 builds (FE2E/Dell8D/HPE9E) x layouts (GCM A/B, CTR, CBC).
Priority families:
  F1 all aligned 16B/32B windows in GSP-RM ELF + MODS ELF (+ derivations)
  F2 string dictionary x hash/HMAC/CMAC variants
  F3 NvTestKey makeSecret extended index sweep
  F4 SP800-108 compositions
  F6 descriptor/VBIOS-field derived

Usage: gen_candidates.py FAMILY [limit] | ./fsp_oracle
"""
import sys, hashlib, hmac, struct, itertools, re, os

# ---------------- seed material ----------------
NvTestKey = [0x12345678,0x9abcdef0,0xfedcba98,0x76543210,
             0x23456789,0xabcdef01,0xedcba987,0x6543210f]

def makeSecret(TK, n):
    # mrmcd26 construction: secret = [(TK[5]&~0xFF)|(n&0xFF), TK[4], TK[3], TK[2]] LE
    words = [(TK[5] & 0xFFFFFF00) | (n & 0xFF), TK[4], TK[3], TK[2]]
    return struct.pack('<4I', *words)

def h16(seed): return hashlib.sha256(seed).digest()[:16]
def h32(seed): return hashlib.sha256(seed).digest()
def s512_16(seed): return hashlib.sha512(seed).digest()[:16]
def s512_32(seed): return hashlib.sha512(seed).digest()[:32]
def md5k(seed): return hashlib.md5(seed).digest()
def sha1k(seed): return hashlib.sha1(seed).digest()[:16]

LABELS = [b"FSP", b"fsp", b"FSP_RUN", b"fmc", b"FMC", b"GFW", b"GB202", b"GB202_FSP",
          b"GB200", b"GB100", b"B200", b"RTX5090", b"Blackwell", b"blackwell",
          b"secure boot", b"secureboot", b"ucode", b"keys", b"key", b"NVIDIA",
          b"nvidia", b"sec2", b"SEC2", b"boot", b"booter", b"NVDM", b"nvdm",
          b"COT", b"cot", b"Firmware Security Processor", b"fsp-run", b"fsp_run",
          b"salt", b"pepper", b"derive", b"kdf", b"root", b"master", b"dev",
          b"debug", b"prod", b"production", b"factory", b"MFG", b"SLT", b"test",
          b"PSC", b"psc", b"Thor", b"Rubin", b"asstral", b"figueroa", b"lava"]

def hmac_variants(seed):
    out = []
    for lab in LABELS:
        out.append(hmac.new(lab, seed, hashlib.sha256).digest()[:16])
        out.append(hmac.new(seed, lab, hashlib.sha256).digest()[:16])
    return out

def raw_derivs(seed):
    if len(seed) == 16:
        yield seed
    elif len(seed) > 16:
        yield seed[:16]; yield seed[-16:]
    yield h16(seed); yield md5k(seed); yield sha1k(seed); yield s512_16(seed)
    for k in hmac_variants(seed): yield k

# ---------------- families ----------------
def fam_f1(limit=None):
    """all aligned 16B windows of the GSP-RM ELF (RV64 plaintext) + MODS ELF crypto-adjacent"""
    paths = ['/home/user/rt_5090_project/ghidra_static/gsp_inner_19f040_a.elf']
    n = 0
    for p in paths:
        if not os.path.exists(p): continue
        data = open(p,'rb').read()
        for off in range(0, len(data)-16, 16):
            w = data[off:off+16]
            if w == bytes(16): continue
            for d in raw_derivs(w):
                yield d; n += 1
                if limit and n >= limit: return

STRINGS = None
def load_strings():
    global STRINGS
    if STRINGS is not None: return STRINGS
    strs = set()
    # VBIOS + firmware strings
    for p in ['/home/user/rt_5090_project/vbios_diff/unverified_TPU_276859_RTX5090_FE_98.02.2E.00.03.rom',
              '/home/user/rt_5090_project/mods_audit/static/decoded_570215/gb2xx_ist_fs_encoding.txt']:
        try:
            d = open(p,'rb').read()
            for m in re.finditer(rb'[ -~]{4,48}', d):
                strs.add(m.group())
        except: pass
    # codenames & versions
    for s in [b'GB202', b'GB203', b'GB205', b'GB20B', b'GB100', b'GH100', b'B200', b'B100',
              b'RTX 5090', b'RTX5090', b'98.02.2E.00.03', b'98.02.2E', b'2E', b'0x2b85',
              b'FSP_RUN', b'OOBHUB', b'FWSEC', b'Blackwell', b'blackwell', b'NVIDIA',
              b'nvidia', b'FSP', b'fsp', b'figueroa', b'asstral', b'astral', b'PSC',
              b'Thor', b'Rubin', b'570.215', b'570.144', b'615.78.08', b'610.43.03',
              b'NVDM', b'MCTP', b'COT', b'HULK', b'PRC', b'VgpuMode']:
        strs.add(s)
    STRINGS = sorted(strs)
    return STRINGS

def fam_f2(limit=None):
    n = 0
    for s in load_strings():
        for d in raw_derivs(s):
            yield d; n += 1
            if limit and n >= limit: return

def fam_f3(limit=None):
    """makeSecret extended: index 0..65535, rotations, endians, TK tweaks"""
    n = 0
    rots = [NvTestKey,
            NvTestKey[::-1],
            NvTestKey[4:]+NvTestKey[:4],
            [w ^ 0xFFFFFFFF for w in NvTestKey],
            [0x12345678,0x9abcdef0,0xfedcba98,0x76543210,0,0,0,0]]
    for TK in rots:
        for idx in range(65536):
            s = makeSecret(TK, idx)
            for d in raw_derivs(s):
                yield d; n += 1
                if limit and n >= limit: return

def fam_f6(limit=None):
    """descriptor fields and friends"""
    desc = open('/home/user/rt_5090_project/parallel/k3_device_work/fsp/fsp_image_descriptor.bin','rb').read()
    seeds = []
    for i in range(0, 0x34, 4):
        w = struct.unpack_from('<I', desc, i)[0]
        seeds.append(struct.pack('<I', w))
        seeds.append(struct.pack('>I', w))
        seeds.append(struct.pack('<Q', w))
    seeds.append(desc[0x34:0x50])
    seeds.append(desc)
    seeds.append(desc[:0x34])
    n = 0
    for s in seeds:
        for d in raw_derivs(s):
            yield d; n += 1
            if limit and n >= limit: return

FAMS = {'f1': fam_f1, 'f2': fam_f2, 'f3': fam_f3, 'f6': fam_f6}

if __name__ == '__main__':
    fam = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else None
    out = sys.stdout.buffer
    for key in FAMS[fam](limit):
        out.write(key)

// FSP CUDA grinder — final clean version.
// Families: windows <blob> | shactr <hexseed32> <ctrHi> <ctrLo> <count> | selftest
// Added: srand32 <base> <count> | srand32test | srand32selftest
// Filter: decrypted block0 first word must be in guess set; full GCM verify inline on hit.
// Build: nvcc -O3 -arch=sm_120 -o fsp_cuda fsp_cuda.cu -lcrypto
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <chrono>
#include <cerrno>
#include <vector>
#include <openssl/rand.h>
#include <openssl/sha.h>
#include <cuda_runtime.h>
#include <openssl/evp.h>

typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
#define CHK(x) do{cudaError_t e=(x); if(e){fprintf(stderr,"CUDA %s @%d\n",cudaGetErrorString(e),__LINE__);exit(1);} }while(0)

static const u8 SBOX[256]={
0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16};

static const u32 SHA_K[64]={
0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};

__constant__ u8 d_sbox[256];
__constant__ u8 d_ct0[16];
__constant__ u8 d_ivA[12], d_ivB[12], d_ctr16[16], d_tagA[16], d_tagB[16];
__constant__ u32 d_guess[128]; __constant__ int d_nguess;
__constant__ u32 d_shak[64];
__device__ u8 *d_ct; __device__ u64 d_nblocks;
__device__ u8 d_hits[64*16]; __device__ int d_nhits; __device__ int d_hitmode[64];

#define XT(x) ((u8)(((x)<<1) ^ ((((x)>>7)&1)*0x1b)))

__device__ void kexp(const u8 key[16], u8 rk[176]) {
    u8 w[176];
    #pragma unroll
    for (int i=0;i<16;i++) w[i]=key[i];
    u8 rcon=1;
    for (int i=16;i<176;i+=4) {
        u8 t0=w[i-4],t1=w[i-3],t2=w[i-2],t3=w[i-1];
        if (i%16==0) {
            u8 a=d_sbox[t1]^rcon, b=d_sbox[t2], c=d_sbox[t3], d=d_sbox[t0];
            rcon=XT(rcon); t0=a;t1=b;t2=c;t3=d;
        }
        w[i]  =w[i-16]^t0; w[i+1]=w[i-15]^t1; w[i+2]=w[i-14]^t2; w[i+3]=w[i-13]^t3;
    }
    #pragma unroll
    for (int i=0;i<176;i++) rk[i]=w[i];
}
__device__ void aes_enc(const u8 rk[176], const u8 in[16], u8 out[16]) {
    u8 s[16], t[16], u[16];
    #pragma unroll
    for (int i=0;i<16;i++) s[i]=in[i]^rk[i];
    for (int r=1;r<10;r++) {
        #pragma unroll
        for (int i=0;i<16;i++) t[i]=d_sbox[s[i]];
        u[0]=t[0];u[4]=t[4];u[8]=t[8];u[12]=t[12];
        u[1]=t[5];u[5]=t[9];u[9]=t[13];u[13]=t[1];
        u[2]=t[10];u[6]=t[14];u[10]=t[2];u[14]=t[6];
        u[3]=t[15];u[7]=t[3];u[11]=t[7];u[15]=t[11];
        #pragma unroll
        for (int c=0;c<4;c++) {
            u8 a=u[4*c],b=u[4*c+1],cc=u[4*c+2],d=u[4*c+3];
            s[4*c]  =(u8)(XT(a)^(XT(b)^b)^cc^d);
            s[4*c+1]=(u8)(a^XT(b)^(XT(cc)^cc)^d);
            s[4*c+2]=(u8)(a^b^XT(cc)^(XT(d)^d));
            s[4*c+3]=(u8)((XT(a)^a)^b^cc^XT(d));
        }
        const u8 *k=rk+16*r;
        #pragma unroll
        for (int i=0;i<16;i++) s[i]^=k[i];
    }
    #pragma unroll
    for (int i=0;i<16;i++) t[i]=d_sbox[s[i]];
    u[0]=t[0];u[4]=t[4];u[8]=t[8];u[12]=t[12];
    u[1]=t[5];u[5]=t[9];u[9]=t[13];u[13]=t[1];
    u[2]=t[10];u[6]=t[14];u[10]=t[2];u[14]=t[6];
    u[3]=t[15];u[7]=t[3];u[11]=t[7];u[15]=t[11];
    const u8 *k=rk+160;
    #pragma unroll
    for (int i=0;i<16;i++) out[i]=u[i]^k[i];
}
__device__ void gf_shl1(u8 v[16]) {
    u8 dropped = (u8)(v[15] & 1);
    u8 carry = 0;
    for (int i=0;i<16;i++){ u8 c=(u8)(v[i]&1); v[i]=(u8)((v[i]>>1)|(carry<<7)); carry=c; }
    if (dropped) v[0]^=0xE1;
}
__device__ void ghash_mul(u8 Y[16], const u8 H[16]) {
    u8 Z[16]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}, V[16];
    #pragma unroll
    for (int i=0;i<16;i++) V[i]=H[i];
    for (int b=0;b<16;b++) for (int bit=7;bit>=0;bit--) {
        if ((Y[b]>>bit)&1) {
            #pragma unroll
            for (int i=0;i<16;i++) Z[i]^=V[i];
        }
        gf_shl1(V);
    }
    #pragma unroll
    for (int i=0;i<16;i++) Y[i]=Z[i];
}
__device__ bool gcm_verify(const u8 key[16], int layout) {
    if (layout!=0) return false;              // layout B verify skipped in v1 (rare)
    u8 rk[176]; kexp(key, rk);
    u8 H[16]={0}; aes_enc(rk, H, H);
    u8 Y[16]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    for (u64 b=0;b<d_nblocks;b++) {
        #pragma unroll
        for (int i=0;i<16;i++) Y[i]^=d_ct[b*16+i];
        ghash_mul(Y, H);
    }
    u64 cbits=d_nblocks*128;
    u8 L[16]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
    for (int i=0;i<8;i++) L[8+i]=(u8)(cbits>>(56-8*i));
    #pragma unroll
    for (int i=0;i<16;i++) Y[i]^=L[i];
    ghash_mul(Y, H);
    u8 J0[16];
    #pragma unroll
    for (int i=0;i<12;i++) J0[i]=d_ivA[i];
    J0[12]=J0[13]=J0[14]=0; J0[15]=1;
    u8 EJ[16]; aes_enc(rk, J0, EJ);
    #pragma unroll
    for (int i=0;i<16;i++) if ((u8)(Y[i]^EJ[i])!=d_tagA[i]) return false;
    return true;
}
__device__ bool filter_ok(const u8 P[16]) {
    u32 w=(u32)P[0]|((u32)P[1]<<8)|((u32)P[2]<<16)|((u32)P[3]<<24);
    for (int i=0;i<d_nguess;i++) if (w==d_guess[i]) return true;
    // structural: any zero u32 word in first block (4 positions, each 2^-32)
    if (P[0]==0&&P[1]==0&&P[2]==0&&P[3]==0) return true;
    if (P[4]==0&&P[5]==0&&P[6]==0&&P[7]==0) return true;
    if (P[8]==0&&P[9]==0&&P[10]==0&&P[11]==0) return true;
    if (P[12]==0&&P[13]==0&&P[14]==0&&P[15]==0) return true;
    return false;
}
__device__ void record(const u8 key[16], int mode) {
    int idx=atomicAdd(&d_nhits,1);
    if (idx<64) {
        #pragma unroll
        for (int i=0;i<16;i++) d_hits[idx*16+i]=key[i];
        d_hitmode[idx]=mode;
    }
}
__device__ void try_key(const u8 key[16]) {
    if (d_nhits>4) return;
    u8 rk[176]; kexp(key, rk);
    u8 ctr[16], KS[16], P[16];
    #pragma unroll
    for (int i=0;i<12;i++) ctr[i]=d_ivA[i];
    ctr[12]=ctr[13]=ctr[14]=0; ctr[15]=2;
    aes_enc(rk, ctr, KS);
    #pragma unroll
    for (int i=0;i<16;i++) P[i]=(u8)(d_ct0[i]^KS[i]);
    if (filter_ok(P) && gcm_verify(key, 0)) record(key, 0);
    ctr[15]=1;   // nonstandard variant
    aes_enc(rk, ctr, KS);
    #pragma unroll
    for (int i=0;i<16;i++) P[i]=(u8)(d_ct0[i]^KS[i]);
    if (filter_ok(P) && gcm_verify(key, 0)) record(key, 1);
    // CTR-16 structural
    aes_enc(rk, d_ctr16, KS);
    #pragma unroll
    for (int i=0;i<16;i++) P[i]=(u8)(d_ct0[i]^KS[i]);
    if (filter_ok(P)) {
        int z=0; u8 cc[16], c2[16];
        #pragma unroll
        for (int i=0;i<16;i++) cc[i]=d_ctr16[i];
        for (int b=1;b<256;b++) {
            for (int k=15;k>=12;k--){ cc[k]=(u8)(cc[k]+1); if (cc[k]) break; }
            aes_enc(rk, cc, c2);
            for (int i=0;i<16;i++) if ((u8)(d_ct[b*16+i]^c2[i])==0) z++;
        }
        if (z>2560) record(key, 2);
    }
}
// SHA-256 of a 22-byte message (seed16||ctr6), out 32B
__device__ u32 ror32(u32 x,int r){return (x>>r)|(x<<(32-r));}
__device__ void sha256_22(const u8 msg[22], u8 out[32]) {
    u32 w[64];
    #pragma unroll
    for (int i=0;i<16;i++) w[i]=0;
    for (int i=0;i<22;i++) w[i/4]|=(u32)msg[i]<<(24-8*(i%4));
    w[5]|=0x80000000u;
    w[15]=22u*8u;
    for (int i=16;i<64;i++) {
        u32 s0=ror32(w[i-15],7)^ror32(w[i-15],18)^(w[i-15]>>3);
        u32 s1=ror32(w[i-2],17)^ror32(w[i-2],19)^(w[i-2]>>10);
        w[i]=w[i-16]+s0+w[i-7]+s1;
    }
    u32 a=0x6a09e667,b=0xbb67ae85,c=0x3c6ef372,d=0xa54ff53a;
    u32 e=0x510e527f,f=0x9b05688c,g=0x1f83d9ab,h=0x5be0cd19;
    for (int i=0;i<64;i++) {
        u32 S1=ror32(e,6)^ror32(e,11)^ror32(e,25);
        u32 ch=(e&f)^((~e)&g);
        u32 t1=h+S1+ch+d_shak[i]+w[i];
        u32 S0=ror32(a,2)^ror32(a,13)^ror32(a,22);
        u32 mj=(a&b)^(a&c)^(b&c);
        u32 t2=S0+mj;
        h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
    }
    u32 H[8]={0x6a09e667+a,0xbb67ae85+b,0x3c6ef372+c,0xa54ff53a+d,0x510e527f+e,0x9b05688c+f,0x1f83d9ab+g,0x5be0cd19+h};
    for (int i=0;i<8;i++){ out[i*4]=H[i]>>24; out[i*4+1]=H[i]>>16; out[i*4+2]=H[i]>>8; out[i*4+3]=H[i]; }
}

// New family uses its own standard 20-byte SHA-256; legacy sha256_22 unchanged.
__device__ void sha256_20(const u8 msg[20], u8 out[32]) {
    u32 w[64];
    #pragma unroll
    for (int i=0;i<16;i++) w[i]=0;
    for (int i=0;i<20;i++) w[i/4]|=(u32)msg[i]<<(24-8*(i%4));
    w[5]|=0x80000000u;
    w[15]=20u*8u;
    for (int i=16;i<64;i++) {
        u32 s0=ror32(w[i-15],7)^ror32(w[i-15],18)^(w[i-15]>>3);
        u32 s1=ror32(w[i-2],17)^ror32(w[i-2],19)^(w[i-2]>>10);
        w[i]=w[i-16]+s0+w[i-7]+s1;
    }
    u32 a=0x6a09e667,b=0xbb67ae85,c=0x3c6ef372,d=0xa54ff53a;
    u32 e=0x510e527f,f=0x9b05688c,g=0x1f83d9ab,h=0x5be0cd19;
    for (int i=0;i<64;i++) {
        u32 S1=ror32(e,6)^ror32(e,11)^ror32(e,25);
        u32 ch=(e&f)^((~e)&g);
        u32 t1=h+S1+ch+d_shak[i]+w[i];
        u32 S0=ror32(a,2)^ror32(a,13)^ror32(a,22);
        u32 mj=(a&b)^(a&c)^(b&c);
        u32 t2=S0+mj;
        h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
    }
    u32 H[8]={0x6a09e667+a,0xbb67ae85+b,0x3c6ef372+c,0xa54ff53a+d,0x510e527f+e,0x9b05688c+f,0x1f83d9ab+g,0x5be0cd19+h};
    for (int i=0;i<8;i++){ out[i*4]=H[i]>>24; out[i*4+1]=H[i]>>16; out[i*4+2]=H[i]>>8; out[i*4+3]=H[i]; }
}
__device__ u32 rol32(u32 x, int n) { return (x<<n)|(x>>(32-n)); }
__device__ void sha1_20(const u8 msg[20], u8 out[20]) {
    u32 w[80]={0};
    for(int i=0;i<20;i++) w[i/4]|=(u32)msg[i]<<(24-8*(i%4));
    w[5]=0x80000000u; w[15]=160;
    for(int i=16;i<80;i++) w[i]=rol32(w[i-3]^w[i-8]^w[i-14]^w[i-16],1);
    u32 a=0x67452301,b=0xefcdab89,c=0x98badcfe,d=0x10325476,e=0xc3d2e1f0;
    for(int i=0;i<80;i++) {
        u32 f,k;
        if(i<20){ f=(b&c)|(~b&d); k=0x5a827999; }
        else if(i<40){ f=b^c^d; k=0x6ed9eba1; }
        else if(i<60){ f=(b&c)|(b&d)|(c&d); k=0x8f1bbcdc; }
        else { f=b^c^d; k=0xca62c1d6; }
        u32 t=rol32(a,5)+f+e+k+w[i]; e=d; d=c; c=rol32(b,30); b=a; a=t;
    }
    u32 h[5]={a+0x67452301u,b+0xefcdab89u,c+0x98badcfeu,d+0x10325476u,e+0xc3d2e1f0u};
    for(int i=0;i<20;i++) out[i]=(u8)(h[i/4]>>(24-8*(i%4)));
}

static const u64 LR_MASK=(1ULL<<48)-1;
__constant__ u64 d_lr_mul[16], d_lr_add[16];
__device__ u32 lr_next(u64 &x) {
    x=(0x5deece66dULL*x+0xb)&LR_MASK;
    return (u32)(x>>17);
}
__device__ void lr_material(u32 seed, int n, u8 low[16], u8 high[16], u8 packed[20]) {
    u64 x=(((u64)seed<<16)|0x330e);
    x=(x*d_lr_mul[n]+d_lr_add[n])&LR_MASK; // exactly n*20 discarded calls
    for(int i=0;i<16;i++) {
        u32 v=lr_next(x);
        low[i]=(u8)v; high[i]=(u8)(v>>24);
        // MSB-first 3 bytes of the 32-bit output: [31:24], [23:16], [15:8].
        if(i<7) for(int j=0;j<3 && i*3+j<20;j++) packed[i*3+j]=(u8)(v>>(24-8*j));
    }
}
__global__ void k_srand32(u32 base, u64 count) {
    u64 idx=(u64)blockIdx.x*blockDim.x+threadIdx.x;
    if(idx>=count*16) return;
    u32 seed=base+(u32)(idx>>4); int n=idx&15;
    u8 low[16], high[16], packed[20], hash[32];
    lr_material(seed,n,low,high,packed);
    try_key(low); try_key(high); try_key(packed);
    sha1_20(packed,hash); try_key(hash);
    sha256_20(packed,hash); try_key(hash);
}
// Export full raw outputs and all material/digests, not just truncated candidate keys.
static const int LR_CALLS=320, LR_ROW=16+16+20+20+32;
__global__ void k_srand32_debug(const u32 *seeds, int count, u32 *raw, u8 *rows) {
    int i=blockIdx.x*blockDim.x+threadIdx.x;
    if(i>=count) return;
    u64 x=((u64)seeds[i]<<16)|0x330e;
    for(int j=0;j<LR_CALLS;j++) raw[i*LR_CALLS+j]=lr_next(x);
    for(int n=0;n<16;n++) {
        u8 *r=rows+(i*16+n)*LR_ROW;
        lr_material(seeds[i],n,r,r+16,r+32);
        sha1_20(r+32,r+52); sha256_20(r+32,r+72);
    }
}



__global__ void k_single(const u8 *keybuf) { try_key(keybuf); }
__global__ void k_windows(const u8 *blob, u64 nbytes) {
    u64 off=(u64)blockIdx.x*blockDim.x+threadIdx.x;
    if (off+16<=nbytes) try_key(blob+off);
}
__global__ void k_shactr(const u8 *seed, u64 ctrStart, u64 count) {
    u64 idx=(u64)blockIdx.x*blockDim.x+threadIdx.x;
    if (idx>=count) return;
    u64 ctr=ctrStart+idx;
    u8 msg[22], key[16];
    #pragma unroll
    for (int i=0;i<16;i++) msg[i]=seed[i];
    msg[16]=(u8)(ctr>>40); msg[17]=(u8)(ctr>>32); msg[18]=(u8)(ctr>>24);
    msg[19]=(u8)(ctr>>16); msg[20]=(u8)(ctr>>8);  msg[21]=(u8)ctr;
    u8 h[32]; sha256_22(msg, h);
    #pragma unroll
    for (int i=0;i<16;i++) key[i]=h[i];
    try_key(key);
    // reversed construction too: ctr||seed
    for (int i=0;i<6;i++) msg[i]=msg[16+i];
    #pragma unroll
    for (int i=0;i<16;i++) msg[6+i]=seed[i];
    sha256_22(msg, h);
    #pragma unroll
    for (int i=0;i<16;i++) key[i]=h[i];
    try_key(key);
}


__device__ u8 d_dbg[96];
__global__ void k_debug(const u8 *keybuf, const u8 *inbuf, const u8 *skey) {
    u8 rk[176]; kexp(skey, rk);
    u8 rkf[176]; kexp(keybuf, rkf);
    u8 outf[16]; aes_enc(rkf, inbuf, outf);
    // FIPS vector: encrypt inbuf -> out (uses keybuf)
    for (int i=0;i<16;i++) d_dbg[i]=outf[i];
    // KS for IV||2
    u8 ctr[16]; for (int i=0;i<12;i++) ctr[i]=d_ivA[i];
    ctr[12]=ctr[13]=ctr[14]=0; ctr[15]=2;
    u8 ks[16]; aes_enc(rk, ctr, ks);
    for (int i=0;i<16;i++) d_dbg[16+i]=ks[i];
    // H = AES_K(0)
    u8 z[16]={0}; u8 H[16]; aes_enc(rk, z, H);
    for (int i=0;i<16;i++) d_dbg[32+i]=H[i];
    // GHASH Y of block0 XOR then mul
    u8 Y[16]; for (int i=0;i<16;i++) Y[i]=d_ct0[i];
    ghash_mul(Y, H);
    for (int i=0;i<16;i++) d_dbg[48+i]=Y[i];
    // device tag for 4-block selftest ct
    u8 Y2[16]={0};
    for (u64 b=0;b<d_nblocks;b++){ for(int i=0;i<16;i++) Y2[i]^=d_ct[b*16+i]; ghash_mul(Y2,H); }
    u8 L[16]={0}; u64 cb=d_nblocks*128; for(int i=0;i<8;i++) L[8+i]=(u8)(cb>>(56-8*i));
    for(int i=0;i<16;i++) Y2[i]^=L[i]; ghash_mul(Y2,H);
    u8 J0[16]; for(int i=0;i<12;i++) J0[i]=d_ivA[i]; J0[12]=J0[13]=J0[14]=0; J0[15]=1;
    u8 EJ[16]; aes_enc(rk,J0,EJ);
    for(int i=0;i<16;i++) d_dbg[64+i]=(u8)(Y2[i]^EJ[i]);
    for(int i=0;i<16;i++) d_dbg[80+i]=d_tagA[i];
}


// host reference of the same GHASH
static void h_gf_shl1(u8 v[16]){u8 dropped=v[15]&1;u8 carry=0;for(int i=0;i<16;i++){u8 c=v[i]&1;v[i]=(u8)((v[i]>>1)|(carry<<7));carry=c;}if(dropped)v[0]^=0xE1;}
static void h_ghash_mul(u8 Y[16],const u8 H[16]){u8 Z[16]={0},V[16];for(int i=0;i<16;i++)V[i]=H[i];
 for(int b=0;b<16;b++)for(int bit=7;bit>=0;bit--){if((Y[b]>>bit)&1)for(int i=0;i<16;i++)Z[i]^=V[i];h_gf_shl1(V);}
 for(int i=0;i<16;i++)Y[i]=Z[i];}


// ---------- composite string-hash family ----------
// pools packed in global mem: pool data + u16 offsets; layouts fixed
__device__ u8 *d_pA, *d_pN, *d_pO, *d_pT;   // pool char data
__device__ u16 d_oA[300], d_oN[64], d_oO[64], d_oT[21000]; // offsets (n+1)
__device__ int d_nA, d_nN, d_nO, d_nT;
// generic single-block SHA-256 (len<=55)
__device__ void sha256_gb(const u8 *m, int len, u8 out[32]) {
    u32 w[64];
    #pragma unroll
    for (int i=0;i<16;i++) w[i]=0;
    for (int i=0;i<len;i++) w[i/4]|=(u32)m[i]<<(24-8*(i%4));
    w[len/4]|=(u32)0x80<<(24-8*(len%4));
    w[15]=len*8;
    for (int i=16;i<64;i++) {
        u32 s0=ror32(w[i-15],7)^ror32(w[i-15],18)^(w[i-15]>>3);
        u32 s1=ror32(w[i-2],17)^ror32(w[i-2],19)^(w[i-2]>>10);
        w[i]=w[i-16]+s0+w[i-7]+s1;
    }
    u32 a=0x6a09e667,b=0xbb67ae85,c=0x3c6ef372,d=0xa54ff53a;
    u32 e=0x510e527f,f=0x9b05688c,g=0x1f83d9ab,h=0x5be0cd19;
    for (int i=0;i<64;i++) {
        u32 S1=ror32(e,6)^ror32(e,11)^ror32(e,25);
        u32 ch=(e&f)^((~e)&g);
        u32 t1=h+S1+ch+d_shak[i]+w[i];
        u32 S0=ror32(a,2)^ror32(a,13)^ror32(a,22);
        u32 mj=(a&b)^(a&c)^(b&c);
        u32 t2=S0+mj;
        h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
    }
    u32 H[8]={0x6a09e667+a,0xbb67ae85+b,0x3c6ef372+c,0xa54ff53a+d,0x510e527f+e,0x9b05688c+f,0x1f83d9ab+g,0x5be0cd19+h};
    for (int i=0;i<8;i++){ out[i*4]=H[i]>>24; out[i*4+1]=H[i]>>16; out[i*4+2]=H[i]>>8; out[i*4+3]=H[i]; }
}
// generic single-block SHA-1 (len<=55)
__device__ void sha1_gb(const u8 *m, int len, u8 out[20]) {
    u32 w[80];
    #pragma unroll
    for (int i=0;i<16;i++) w[i]=0;
    for (int i=0;i<len;i++) w[i/4]|=(u32)m[i]<<(24-8*(i%4));
    w[len/4]|=(u32)0x80<<(24-8*(len%4));
    w[15]=len*8;
    for (int i=16;i<80;i++){ u32 x=w[i-3]^w[i-8]^w[i-14]^w[i-16]; w[i]=ror32(x,31); }
    u32 a=0x67452301,b=0xEFCDAB89,c=0x98BADCFE,d=0x10325476,e=0xC3D2E1F0;
    for (int i=0;i<80;i++) {
        u32 f,k;
        if(i<20){f=(b&c)|((~b)&d);k=0x5A827999;}
        else if(i<40){f=b^c^d;k=0x6ED9EBA1;}
        else if(i<60){f=(b&c)|(b&d)|(c&d);k=0x8F1BBCDC;}
        else {f=b^c^d;k=0xCA62C1D6;}
        u32 t=rol32(a,5)+f+e+k+w[i]; e=d;d=c;c=rol32(b,30);b=a;a=t;
    }
    u32 R[5]={0x67452301u+a, 0xEFCDAB89u+b, 0x98BADCFEu+c, 0x10325476u+d, 0xC3D2E1F0u+e};
    for (int i=0;i<5;i++){ out[i*4]=R[i]>>24; out[i*4+1]=R[i]>>16; out[i*4+2]=R[i]>>8; out[i*4+3]=R[i]; }
}
// single-block MD5 helpers
__device__ u32 md5f(int i,u32 b,u32 c,u32 d){ if(i<16)return (b&c)|((~b)&d); if(i<32)return (d&b)|((~d)&c); if(i<48)return b^c^d; return c^(b|(~d)); }
__device__ u32 md5r(int i){ static const int r[64]={7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21}; return r[i]; }
__device__ u32 md5k(int i){ static const u32 K[64]={0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391}; return K[i]; }
__device__ void md5_gb(const u8 *m, int len, u8 out[16]) {
    u32 w[16];
    #pragma unroll
    for (int i=0;i<16;i++) w[i]=0;
    for (int i=0;i<len;i++) w[i/4]|=(u32)m[i]<<(8*(i%4));   // little-endian
    u32 padbyte=len; w[len/4]|=0x80<<(8*(len%4));
    w[14]=padbyte*8; w[15]=0;
    u32 a=0x67452301,b=0xefcdab89,c=0x98badcfe,d=0x10325476;
    for (int i=0;i<64;i++) {
        u32 g = (i<16)? i : (i<32)? (5*i+1)&15 : (i<48)? (3*i+5)&15 : (7*i)&15;
        u32 t=d; d=c; c=b;
        u32 sum=a+md5f(i,b,c,d)+md5k(i)+w[g];
        b=b+ ( (sum<<md5r(i)) | (sum>>(32-md5r(i))) );
        a=t;
    }
    u32 R[4]={0x67452301u+a, 0xefcdab89u+b, 0x98badcfeu+c, 0x10325476u+d};
    for (int i=0;i<4;i++){ out[i*4]=R[i]; out[i*4+1]=R[i]>>8; out[i*4+2]=R[i]>>16; out[i*4+3]=R[i]>>24; }
}

// layout codes: 0: T|N|O|A  1: N|T|A  2: O|N|T|A  3: T|N  4: N|O|T|A
__device__ int app_pool(const u8* pool, const u16* offs, int i, u8* s, int L) {
    for (int q=offs[i]; q<offs[i+1]; q++) s[L++]=pool[q];
    return L;
}
__global__ void k_composite(u64 startIdx, u64 count, int layout, int sepIdx) {
    u64 idx = startIdx + (u64)blockIdx.x*blockDim.x + threadIdx.x;
    if (idx >= startIdx+count) return;
    int nT=d_nT, nN=d_nN, nO=d_nO, nA=d_nA;
    u64 rem = idx;
    int a=0,o=0,t=0,n=0;
    if (layout==0){ a=rem%nA; rem/=nA; o=rem%nO; rem/=nO; n=rem%nN; rem/=nN; t=rem%nT; }
    else if (layout==1){ a=rem%nA; rem/=nA; t=rem%nT; rem/=nT; n=rem%nN; }
    else if (layout==2){ a=rem%nA; rem/=nA; t=rem%nT; rem/=nT; n=rem%nN; rem/=nN; o=rem%nO; }
    else if (layout==3){ n=rem%nN; rem/=nN; t=rem%nT; }
    else { a=rem%nA; rem/=nA; t=rem%nT; rem/=nT; n=rem%nN; rem/=nN; o=rem%nO; }
    char sep = (sepIdx==0)?0:(sepIdx==1?'_':(sepIdx==2?'-':' '));
    u8 s[64]; int L=0;
    if (layout==0){ L=app_pool(d_pT,d_oT,t,s,L); if(sep)s[L++]=sep; L=app_pool(d_pN,d_oN,n,s,L); if(sep)s[L++]=sep; L=app_pool(d_pO,d_oO,o,s,L); if(sep)s[L++]=sep; L=app_pool(d_pA,d_oA,a,s,L); }
    else if (layout==1){ L=app_pool(d_pN,d_oN,n,s,L); if(sep)s[L++]=sep; L=app_pool(d_pT,d_oT,t,s,L); if(sep)s[L++]=sep; L=app_pool(d_pA,d_oA,a,s,L); }
    else if (layout==2){ L=app_pool(d_pO,d_oO,o,s,L); if(sep)s[L++]=sep; L=app_pool(d_pN,d_oN,n,s,L); if(sep)s[L++]=sep; L=app_pool(d_pT,d_oT,t,s,L); if(sep)s[L++]=sep; L=app_pool(d_pA,d_oA,a,s,L); }
    else if (layout==3){ L=app_pool(d_pT,d_oT,t,s,L); if(sep)s[L++]=sep; L=app_pool(d_pN,d_oN,n,s,L); }
    else { L=app_pool(d_pN,d_oN,n,s,L); if(sep)s[L++]=sep; L=app_pool(d_pO,d_oO,o,s,L); if(sep)s[L++]=sep; L=app_pool(d_pT,d_oT,t,s,L); if(sep)s[L++]=sep; L=app_pool(d_pA,d_oA,a,s,L); }
    u8 h[32], key[16];
    sha256_gb(s, L, h); for(int i=0;i<16;i++)key[i]=h[i]; try_key(key);
    sha1_gb(s, L, h);   for(int i=0;i<16;i++)key[i]=h[i]; try_key(key);
    md5_gb(s, L, key);  try_key(key);
}


// ---------- MSVC rand family ----------
__global__ void k_msvc32(u32 base, u64 count) {
    u64 idx=(u64)blockIdx.x*blockDim.x+threadIdx.x;
    if (idx>=count) return;
    u32 s = base + (u32)idx;
    for (int n=0;n<16;n++) {
        u32 st=s;
        // skip n*20 calls
        for (int q=0;q<n*20;q++) st = st*214013u + 2531011u;
        u8 kA[16],kB[16],seed20[20];
        for (int q=0;q<20;q++){
            st = st*214013u + 2531011u;
            u32 r = (st>>16)&0x7fff;
            if (q<16){kA[q]=(u8)(r&0xff); kB[q]=(u8)((r>>8)&0xff);}
            if (q<20) seed20[q]=(u8)(r&0xff);
        }
        try_key(kA);
        try_key(kB);
        u8 h[32], key[16];
        sha256_gb(seed20,20,h); for(int i=0;i<16;i++)key[i]=h[i]; try_key(key);
        sha1_gb(seed20,20,h);   for(int i=0;i<16;i++)key[i]=h[i]; try_key(key);
    }
}
// ---------- glibc random() TYPE_3 family ----------
__device__ void glibc_random_stream(u32 seed, int skip, int take, u32 *out) {
    // glibc TYPE_3 exactly: 31-word ring, fptr=state[3], rptr=state[0], out=(u32)val>>1
    int32_t r[31];
    if (seed==0) seed=1;
    r[0]=(int32_t)seed;
    for (int i=1;i<31;i++){
        int32_t prev=r[i-1];
        int32_t hi=prev/127773, lo=prev%127773;
        int32_t word=16807*lo - 2836*hi;
        if (word<0) word+=2147483647;
        r[i]=word;
    }
    int fi=3, ri=0;
    for (int q=0;q<310+skip;q++){
        r[fi]=(int32_t)(((u32)r[fi])+((u32)r[ri]));
        fi=(fi+1)%31; ri=(ri+1)%31;
    }
    for (int q=0;q<take;q++){
        r[fi]=(int32_t)(((u32)r[fi])+((u32)r[ri]));
        out[q]=((u32)r[fi])>>1;
        fi=(fi+1)%31; ri=(ri+1)%31;
    }
}
__global__ void k_random32(u32 base, u64 count) {
    u64 idx=(u64)blockIdx.x*blockDim.x+threadIdx.x;
    if (idx>=count) return;
    u32 s = base + (u32)idx;
    u32 o[20];
    for (int n=0;n<16;n++) {
        glibc_random_stream(s, n*20, 20, o);
        u8 kA[16],kB[16],seed20[20];
        for (int q=0;q<20;q++){
            if (q<16){kA[q]=(u8)(o[q]&0xff); kB[q]=(u8)((o[q]>>8)&0xff);}
            seed20[q]=(u8)(o[q]&0xff);
        }
        try_key(kA);
        try_key(kB);
        u8 h[32], key[16];
        sha256_gb(seed20,20,h); for(int i=0;i<16;i++)key[i]=h[i]; try_key(key);
        sha1_gb(seed20,20,h);   for(int i=0;i<16;i++)key[i]=h[i]; try_key(key);
    }
}


// ---------- anchored big-offset lrand48 family ----------
__device__ u64 *d_aj_mul, *d_aj_add;   // per-offset jump constants (n*20 calls), n = table index
__global__ void k_anchor(u32 seedBase, u32 seedCount, int maxOff) {
    u64 idx=(u64)blockIdx.x*blockDim.x+threadIdx.x;
    if (idx >= (u64)seedCount*maxOff) return;
    u32 seed = seedBase + (u32)(idx/maxOff);
    int n = (int)(idx%maxOff);
    u64 x = (((u64)seed<<16)|0x330eULL);
    x = (x*d_aj_mul[n] + d_aj_add[n]) & ((1ULL<<48)-1);
    u8 low[16], high[16], packed[20];
    for (int i=0;i<16;i++) {
        u32 v;
        x=(0x5deece66dULL*x+0xbULL)&((1ULL<<48)-1);
        v=(u32)(x>>17);
        low[i]=(u8)v; high[i]=(u8)(v>>24);
        if(i<7) for (int j=0;j<3 && i*3+j<20;j++) packed[i*3+j]=(u8)(v>>(24-8*j));
    }
    try_key(low); try_key(high); try_key(packed);
    u8 h[32];
    sha1_20(packed,h); try_key(h);
    sha256_20(packed,h); try_key(h);
}


__attribute__((optimize("O0"))) static int glchk(const u32 *ref){
    volatile int32_t r[31]; u32 seed=12345;
    r[0]=(int32_t)seed;
    for (int i=1;i<31;i++){int32_t p=r[i-1];int32_t hi=p/127773,lo=p%127773;int32_t w=16807*lo-2836*hi;if(w<0)w+=2147483647;r[i]=w;}
    int fi=3, ri=0;
    for (int q=0;q<310;q++){r[fi]=(int32_t)(((u32)r[fi])+((u32)r[ri]));fi=(fi+1)%31;ri=(ri+1)%31;}
    for (int i=0;i<20;i++){r[fi]=(int32_t)(((u32)r[fi])+((u32)r[ri])); u32 o=((u32)r[fi])>>1;
        if(o!=ref[i]){printf("GLIBC MISMATCH at %d: got %u want %u\n",i,o,ref[i]);return 1;}}
    return 0;
}


__device__ u32 d_randdbg[8];
__global__ void k_randdbg(u32 seed){ u32 o[20]; glibc_random_stream(seed,0,20,o); for(int i=0;i<8;i++) d_randdbg[i]=o[i]; }

static u32 le32w(const char *s){ u32 w=0; for(int i=0;i<4&&s[i];i++) w|=(u32)(u8)s[i]<<(8*i); return w; }


static void lr_init() {
    u64 mul[16],add[16],m=1,a=0;
    for(int n=0;n<16;n++) {
        mul[n]=m; add[n]=a;
        for(int j=0;j<20;j++) { m=(m*0x5deece66dULL)&LR_MASK; a=(a*0x5deece66dULL+11)&LR_MASK; }
    }
    CHK(cudaMemcpyToSymbol(d_lr_mul,mul,sizeof(mul)));
    CHK(cudaMemcpyToSymbol(d_lr_add,add,sizeof(add)));
}
static void lr_reset_hits() {
    int z=0; u8 empty[64*16]={0}; int modes[64]={0};
    CHK(cudaMemcpyToSymbol(d_nhits,&z,sizeof(z)));
    CHK(cudaMemcpyToSymbol(d_hits,empty,sizeof(empty)));
    CHK(cudaMemcpyToSymbol(d_hitmode,modes,sizeof(modes)));
}
static void print_hex(const u8 *p,int n) { for(int i=0;i<n;i++) printf("%02x",p[i]); }
static int lr_consistency_test() {
    const int N=106;
    u32 seeds[N]={0,1,0x7fffffff,0x80000000,0xffffffff,0x12345678};
    if(RAND_bytes((u8*)(seeds+6),100*sizeof(u32))!=1) { fprintf(stderr,"RAND_bytes failed\n"); return 2; }
    printf("srand32test seeds (6 edges + 100 OpenSSL random):\n");
    for(int i=0;i<N;i++) printf("%08x%s",seeds[i],(i%8==7 || i==N-1)?"\n":" ");
    u32 *ds,*draw; u8 *drows;
    CHK(cudaMalloc(&ds,sizeof(seeds))); CHK(cudaMemcpy(ds,seeds,sizeof(seeds),cudaMemcpyHostToDevice));
    std::vector<u32> raw(N*LR_CALLS); std::vector<u8> rows(N*16*LR_ROW);
    CHK(cudaMalloc(&draw,raw.size()*sizeof(u32))); CHK(cudaMalloc(&drows,rows.size()));
    k_srand32_debug<<<(N+127)/128,128>>>(ds,N,draw,drows);
    CHK(cudaGetLastError()); CHK(cudaDeviceSynchronize());
    CHK(cudaMemcpy(raw.data(),draw,raw.size()*sizeof(u32),cudaMemcpyDeviceToHost));
    CHK(cudaMemcpy(rows.data(),drows,rows.size(),cudaMemcpyDeviceToHost));
    for(int i=0;i<N;i++) {
        srand48((long)seeds[i]); u32 vals[LR_CALLS];
        for(int j=0;j<LR_CALLS;j++) {
            vals[j]=(u32)lrand48();
            if(vals[j]!=raw[i*LR_CALLS+j]) { fprintf(stderr,"FAIL raw seed=%08x call=%d\n",seeds[i],j); return 2; }
        }
        for(int n=0;n<16;n++) {
            u8 ref[LR_ROW]={0};
            for(int j=0;j<16;j++) { ref[j]=(u8)vals[n*20+j]; ref[16+j]=(u8)(vals[n*20+j]>>24); }
            for(int j=0;j<20;j++) ref[32+j]=(u8)(vals[n*20+j/3]>>(24-8*(j%3)));
            if(!SHA1(ref+32,20,ref+52) || !SHA256(ref+32,20,ref+72)) return 2;
            for(int j=0;j<LR_ROW;j++) if(ref[j]!=rows[(i*16+n)*LR_ROW+j]) {
                fprintf(stderr,"FAIL material seed=%08x n=%d byte=%d host=%02x device=%02x\n",seeds[i],n,j,ref[j],rows[(i*16+n)*LR_ROW+j]); return 2;
            }
        }
    }
    CHK(cudaFree(ds)); CHK(cudaFree(draw)); CHK(cudaFree(drows));
    printf("libc lrand48: %d seeds x %d calls = %d full outputs: PASS\n",N,LR_CALLS,N*LR_CALLS);
    printf("byte streams + full SHA1/SHA256 (OpenSSL): %d seeds x 16 offsets x %d bytes = %d bytes: PASS (100%% byte agreement)\n",N,LR_ROW,N*16*LR_ROW);
    printf("SRAND32TEST PASS\n"); return 0;
}
static bool parse_lr_u64(const char *s,u64 &v) {
    if(!s || !*s || *s=='-' || *s=='+') return false;
    char *end; errno=0; v=strtoull(s,&end,0); return !errno && !*end;
}
static int lr_scan(u32 base,u64 count,const u8 *expected=nullptr) {
    lr_reset_hits();
    printf("[srand32] base=0x%08x count=%llu variants/seed=80; high=v>>24 packed=v>>{24,16,8}\n",base,(unsigned long long)count);
    const u64 PROGRESS=1ULL<<28;
    // Convention (a) depends only on seed mod 512. Synthetic recovery therefore
    // has many identical valid keys. Drain/reset each small batch, without changing
    // legacy try_key's hit cap, and verify that no batch reaches that cap.
    const u64 BATCH=expected?256:(1ULL<<18);
    auto t0=std::chrono::steady_clock::now();
    int nh=0, recovery_hits=0, max_batch_hits=0;
    bool recovered=false, recovery_incomplete=false;
    for(u64 done=0;done<count;) {
        u64 c=count-done<BATCH?count-done:BATCH;
        k_srand32<<<(u32)((c*16+255)/256),256>>>(base+(u32)done,c);
        CHK(cudaGetLastError()); CHK(cudaDeviceSynchronize()); done+=c;
        if(expected) {
            CHK(cudaMemcpyFromSymbol(&nh,d_nhits,sizeof(nh)));
            recovery_hits+=nh; if(nh>max_batch_hits) max_batch_hits=nh;
            if(nh>4) recovery_incomplete=true;
            if(nh) {
                u8 keys[64*16]; int modes[64];
                CHK(cudaMemcpyFromSymbol(keys,d_hits,sizeof(keys)));
                CHK(cudaMemcpyFromSymbol(modes,d_hitmode,sizeof(modes)));
                for(int i=0;i<nh && i<64;i++) {
                    if(modes[i]==2) recovery_incomplete=true;
                    if(modes[i]==0 && !memcmp(expected,keys+16*i,16)) {
                        if(!recovered) { printf("GCM_VERIFIED_HIT mode=0 key="); print_hex(keys+16*i,16); printf("\n"); }
                        recovered=true;
                    }
                }
            }
            lr_reset_hits();
        }
        if(done%PROGRESS==0 || done==count) {
            CHK(cudaMemcpyFromSymbol(&nh,d_nhits,sizeof(nh)));
            printf("  %llu/%llu seeds nhits=%d\n",(unsigned long long)done,(unsigned long long)count,expected?recovery_hits:nh); fflush(stdout);
        }
    }
    double sec=std::chrono::duration<double>(std::chrono::steady_clock::now()-t0).count();
    CHK(cudaMemcpyFromSymbol(&nh,d_nhits,sizeof(nh)));
    printf("done %.6fs (%.9g seeds/s; %.9g candidate keys/s) candidates=%llu nhits=%d\n",sec,count/sec,count*80.0/sec,(unsigned long long)(count*80),expected?recovery_hits:nh);
    if(expected) {
        printf("recovery batch=%llu max_batch_hits=%d incomplete=%s\n",(unsigned long long)BATCH,max_batch_hits,recovery_incomplete?"yes":"no");
        bool pass=recovered && !recovery_incomplete;
        printf("SRAND32 RECOVERY SELFTEST %s\n",pass?"PASS":"FAIL"); return pass?0:2;
    }
    u8 hits[64*16]; int modes[64];
    CHK(cudaMemcpyFromSymbol(hits,d_hits,sizeof(hits))); CHK(cudaMemcpyFromSymbol(modes,d_hitmode,sizeof(modes)));
    bool heuristic=false;
    for(int i=0;i<nh && i<64;i++) {
        // Legacy try_key also records structural CTR candidates (mode 2), NOT authenticated hits.
        printf("%s mode=%d key=",modes[i]==2?"UNVERIFIED_CTR_CANDIDATE":"GCM_VERIFIED_HIT",modes[i]);
        print_hex(hits+16*i,16); printf("\n");
        if(modes[i]==2) heuristic=true;
    }
    if(nh>4 || heuristic) {
        fprintf(stderr,"WARNING: legacy try_key hit cap/CTR heuristic: scan may be incomplete; throughput is nominal, not verified work.\n");
        return 2;
    }
    return 0;
}
static void lr_evp_check(int ok) { if(ok!=1) { fprintf(stderr,"OpenSSL GCM operation failed\n"); exit(2); } }
static int lr_recovery_test() {
    // Entire target is synthetic. 4096B keeps legacy try_key's CTR structural reads in bounds.
    const int SZ=4096;
    u8 key[16],iv[12],tag[16],ctr[16]={0},pt[SZ],ct[SZ+16];
    srand48(0x12345678L); for(int i=0;i<16;i++) key[i]=(u8)lrand48();
    for(int i=0;i<12;i++) iv[i]=(u8)(0x40+i);
    for(int i=0;i<SZ;i++) pt[i]=(u8)(i*13+5);
    memset(pt,0,4); memcpy(ctr,iv,12); ctr[15]=2;
    EVP_CIPHER_CTX *ctx=EVP_CIPHER_CTX_new(); if(!ctx) return 2;
    lr_evp_check(EVP_EncryptInit_ex(ctx,EVP_aes_128_gcm(),nullptr,nullptr,nullptr));
    lr_evp_check(EVP_CIPHER_CTX_ctrl(ctx,EVP_CTRL_GCM_SET_IVLEN,12,nullptr));
    lr_evp_check(EVP_EncryptInit_ex(ctx,nullptr,nullptr,key,iv));
    int n,tail; lr_evp_check(EVP_EncryptUpdate(ctx,ct,&n,pt,SZ));
    lr_evp_check(EVP_EncryptFinal_ex(ctx,ct+n,&tail));
    lr_evp_check(EVP_CIPHER_CTX_ctrl(ctx,EVP_CTRL_GCM_GET_TAG,16,tag));
    EVP_CIPHER_CTX_free(ctx); if(n+tail!=SZ) return 2;
    u8 *dc; CHK(cudaMalloc(&dc,SZ)); CHK(cudaMemcpy(dc,ct,SZ,cudaMemcpyHostToDevice));
    u64 nb=SZ/16; u32 guess=0; int ng=1;
    CHK(cudaMemcpyToSymbol(d_ct,&dc,sizeof(dc))); CHK(cudaMemcpyToSymbol(d_nblocks,&nb,sizeof(nb)));
    CHK(cudaMemcpyToSymbol(d_ct0,ct,16)); CHK(cudaMemcpyToSymbol(d_ivA,iv,12));
    CHK(cudaMemcpyToSymbol(d_tagA,tag,16)); CHK(cudaMemcpyToSymbol(d_ctr16,ctr,16));
    CHK(cudaMemcpyToSymbol(d_guess,&guess,sizeof(guess))); CHK(cudaMemcpyToSymbol(d_nguess,&ng,sizeof(ng)));
    printf("Synthetic libc seed=0x12345678 convention=a n=0 key="); print_hex(key,16); printf("\n");
    int rc=lr_scan(0x12345000u,0x10000,key);
    CHK(cudaFree(dc)); return rc;
}

int main(int argc, char **argv) {
    if(argc<2) { fprintf(stderr,"mode required: selftest | srand32test | srand32selftest | srand32 <base> <count> | windows | shactr\n"); return 1; }
    u64 lr_base=0,lr_count=0;
    bool lr_mode=!strcmp(argv[1],"srand32");
    if(lr_mode && (argc!=4 || !parse_lr_u64(argv[2],lr_base) || !parse_lr_u64(argv[3],lr_count) ||
                  lr_base>0xffffffffULL || lr_count==0 || lr_count>(1ULL<<32)-lr_base)) {
        fprintf(stderr,"srand32 requires base in [0,2^32), positive count, base+count <= 2^32 (no wrap)\n"); return 1;
    }
    CHK(cudaMemcpyToSymbol(d_sbox, SBOX, 256));
    CHK(cudaMemcpyToSymbol(d_shak, SHA_K, 256));
    {int z0=0; CHK(cudaMemcpyToSymbol(d_nhits,&z0,4));}
    if(lr_mode || !strcmp(argv[1],"srand32test") || !strcmp(argv[1],"srand32selftest")) {
        lr_init();
        if(!strcmp(argv[1],"srand32test")) return lr_consistency_test();
        if(!strcmp(argv[1],"srand32selftest")) return lr_recovery_test();
    }
    u8 *ct; u64 ctlen; u8 tail[28], desc[0x50];
    FILE *f=fopen("/home/user/rt_5090_project/parallel/k3_device_work/fsp/fsp_image.bin","rb");
    fseek(f,0,SEEK_END); ctlen=ftell(f); fseek(f,0,SEEK_SET);
    ct=(u8*)malloc(ctlen); if(fread(ct,1,ctlen,f)!=ctlen) return 1; fclose(f);
    f=fopen("/home/user/rt_5090_project/parallel/k3_device_work/fsp/fsp_image_descriptor.bin","rb");
    if(fread(desc,1,0x50,f)!=0x50) return 1; fclose(f);
    memcpy(tail, desc+0x34, 28);

    // guess set
    u32 G[128]; int ng=0;
    G[ng++]=0x00000000; G[ng++]=0x00000001; G[ng++]=0xFFFFFFFF;
    G[ng++]=0x00000301; G[ng++]=0x01030000; G[ng++]=0x01030100;
    G[ng++]=0x00000401; G[ng++]=0x01040000; G[ng++]=0x01040100;
    G[ng++]=0x00029400; G[ng++]=0x00409400; G[ng++]=0x00036C00; G[ng++]=0x00C03600;
    G[ng++]=0x00037000; G[ng++]=0x00703700; G[ng++]=0x01012801; G[ng++]=0x01280101;
    G[ng++]=0x464c457f; G[ng++]=0x7f454c46; G[ng++]=0x000010de; G[ng++]=0xde100000; G[ng++]=0x00480403; G[ng++]=0x03044800; G[ng++]=0x00480401; G[ng++]=0x01044800; G[ng++]=0x00480400; G[ng++]=0x00480404;
    const char *magics[]={"FSP_","fsp_","NVRM","NVFW","NVDM","NVFL","GFW_","fmc_","fmc\0","gfw\0","FSPC","MODS","HULK","NVDM"};
    for (auto m : magics) if (strlen(m)==4) G[ng++]=le32w(m);
    CHK(cudaMemcpyToSymbol(d_guess, G, ng*4));
    CHK(cudaMemcpyToSymbol(d_nguess, &ng, 4));
    CHK(cudaMemcpyToSymbol(d_ivA, tail, 12));
    CHK(cudaMemcpyToSymbol(d_ivB, tail+16, 12));
    CHK(cudaMemcpyToSymbol(d_tagA, tail+12, 16));
    CHK(cudaMemcpyToSymbol(d_tagB, tail, 16));
    CHK(cudaMemcpyToSymbol(d_ctr16, tail, 16));
    CHK(cudaMemcpyToSymbol(d_ct0, ct, 16));
    u64 nblocks=ctlen/16;
    CHK(cudaMemcpyToSymbol(d_nblocks, &nblocks, 8));

    u8 *d_ctbuf; CHK(cudaMalloc(&d_ctbuf, ctlen));
    CHK(cudaMemcpy(d_ctbuf, ct, ctlen, cudaMemcpyHostToDevice));
    CHK(cudaMemcpyToSymbol(d_ct, &d_ctbuf, 8));

    if(lr_mode) return lr_scan((u32)lr_base,lr_count);

    if (!strcmp(argv[1], "selftest")) {
        // synthetic GCM with known key; plaintext first word in guess set
        u8 key[16]; for(int i=0;i<16;i++) key[i]=(u8)(i*7+3);
        u8 pt[64]; pt[0]=pt[1]=pt[2]=pt[3]=0; // zero word in guess set
        for(int i=4;i<64;i++) pt[i]=(u8)(i*13+5);
        u8 sct[64], stag[16], siv[12]; for(int i=0;i<12;i++) siv[i]=(u8)(0x40+i);
        EVP_CIPHER_CTX*c=EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(c,EVP_aes_128_gcm(),NULL,NULL,NULL);
        EVP_CIPHER_CTX_ctrl(c,EVP_CTRL_GCM_SET_IVLEN,12,NULL);
        EVP_EncryptInit_ex(c,NULL,NULL,key,siv);
        int l; EVP_EncryptUpdate(c,sct,&l,pt,64);
        EVP_EncryptFinal_ex(c,sct+l,&l);
        EVP_CIPHER_CTX_ctrl(c,EVP_CTRL_GCM_GET_TAG,16,stag);
        EVP_CIPHER_CTX_free(c);
        CHK(cudaMemcpyToSymbol(d_ct0, sct, 16));
        CHK(cudaMemcpy(d_ctbuf, sct, 64, cudaMemcpyHostToDevice));
        u64 nb=4; CHK(cudaMemcpyToSymbol(d_nblocks,&nb,8));
        CHK(cudaMemcpyToSymbol(d_ivA, siv, 12));
        CHK(cudaMemcpyToSymbol(d_tagA, stag, 16));
        CHK(cudaMemcpyToSymbol(d_ctr16, siv, 12)); // dummy for selftest
        u8*h=(u8*)malloc(16); memcpy(h,key,16);
        u8*dk; CHK(cudaMalloc(&dk,16)); CHK(cudaMemcpy(dk,h,16,cudaMemcpyHostToDevice));
        {   // debug: FIPS aes + KS + H + Y1 + device tag vs real tag
            u8 fkey[16], fin[16];
            for(int i=0;i<16;i++){fkey[i]=(u8)i; fin[i]=(u8)(i*0x11);}
            u8*dfk; CHK(cudaMalloc(&dfk,32)); CHK(cudaMemcpy(dfk,fkey,16,cudaMemcpyHostToDevice)); CHK(cudaMemcpy(dfk+16,fin,16,cudaMemcpyHostToDevice));
            k_debug<<<1,1>>>(dfk,dfk+16,dk); CHK(cudaDeviceSynchronize());
            u8 db[96]; CHK(cudaMemcpyFromSymbol(db,d_dbg,96));
            printf("AES(fipskey)=%02x%02x%02x%02x.. expect 69c4e0d8..\n", db[0],db[1],db[2],db[3]);
            printf("KS(IV||2)="); for(int i=0;i<16;i++)printf("%02x",db[16+i]); printf("\n");
            printf("H="); for(int i=0;i<16;i++)printf("%02x",db[32+i]); printf("\n");
            printf("Y1="); for(int i=0;i<16;i++)printf("%02x",db[48+i]); printf("\n");
            printf("devtag="); for(int i=0;i<16;i++)printf("%02x",db[64+i]); printf("\n");
            printf("rmtag ="); for(int i=0;i<16;i++)printf("%02x",db[80+i]); printf("\n");
            {   // host reference: H via OpenSSL, GHASH via host copy
                u8 H[16]={0}; EVP_CIPHER_CTX*cc=EVP_CIPHER_CTX_new();
                int l; EVP_EncryptInit_ex(cc,EVP_aes_128_ecb(),NULL,key,NULL);
                EVP_EncryptUpdate(cc,H,&l,H,16); EVP_CIPHER_CTX_free(cc);
                u8 Y[16]={0};
                for(int b=0;b<4;b++){for(int i=0;i<16;i++)Y[i]^=sct[b*16+i];h_ghash_mul(Y,H);}
                u8 L[16]={0}; u64 cb=4*128; for(int i=0;i<8;i++)L[8+i]=(u8)(cb>>(56-8*i));
                for(int i=0;i<16;i++)Y[i]^=L[i]; h_ghash_mul(Y,H);
                u8 J0[16]; for(int i=0;i<12;i++)J0[i]=siv[i]; J0[15]=1;
                u8 EJ[16]={0}; EVP_CIPHER_CTX*c2=EVP_CIPHER_CTX_new();
                EVP_EncryptInit_ex(c2,EVP_aes_128_ecb(),NULL,key,NULL);
                EVP_EncryptUpdate(c2,EJ,&l,J0,16); EVP_CIPHER_CTX_free(c2);
                printf("hosttag="); for(int i=0;i<16;i++)printf("%02x",(u8)(Y[i]^EJ[i])); printf("\n");
                printf("hostH  ="); for(int i=0;i<16;i++)printf("%02x",H[i]); printf("\n");
            }
        }
        {int z0=0; CHK(cudaMemcpyToSymbol(d_nhits,&z0,4));}
        k_single<<<1,1>>>(dk); CHK(cudaDeviceSynchronize());
        int nh; CHK(cudaMemcpyFromSymbol(&nh,d_nhits,4));
        printf("selftest: nhits=%d (expect 1, mode 0)\n", nh);
        if (nh!=1) { printf("SELFTEST FAIL\n"); return 2; }
        u8 hk[16]; CHK(cudaMemcpyFromSymbol(hk,d_hits,16));
        printf("recovered key: "); for(int i=0;i<16;i++)printf("%02x",hk[i]); printf("\n");
        // negative
        u8 bad[16]={1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
        CHK(cudaMemcpy(dk,bad,16,cudaMemcpyHostToDevice));
        {int z0=0; CHK(cudaMemcpyToSymbol(d_nhits,&z0,4));}
        k_single<<<1,1>>>(dk); CHK(cudaDeviceSynchronize());
        CHK(cudaMemcpyFromSymbol(&nh,d_nhits,4));
        printf("negative: nhits=%d (expect 0)\n", nh);
        if (nh>0){ u8 hk2[64*16]; int mm[64]; cudaMemcpyFromSymbol(hk2,d_hits,64*16); cudaMemcpyFromSymbol(mm,d_hitmode,64*4);
            printf("neg hit key="); for(int j=0;j<16;j++)printf("%02x",hk2[j]); printf(" mode=%d\n",mm[0]); }
        if (nh!=0) { printf("NEG FAIL\n"); return 2; }
        printf("SELFTEST PASS\n");
        return 0;
    }
    else if (!strcmp(argv[1], "windows")) {
        FILE *b=fopen(argv[2],"rb"); fseek(b,0,SEEK_END); u64 sz=ftell(b); fseek(b,0,SEEK_SET);
        u8*blob=(u8*)malloc(sz); if(fread(blob,1,sz,b)!=sz) return 1; fclose(b);
        u8*db; CHK(cudaMalloc(&db,sz)); CHK(cudaMemcpy(db,blob,sz,cudaMemcpyHostToDevice));
        u64 nwin=sz-15;
        printf("[windows] %s: %llu windows\n", argv[2], (unsigned long long)nwin);
        auto t0=std::chrono::steady_clock::now();
        k_windows<<<(u32)((nwin+255)/256),256>>>(db,sz);
        CHK(cudaDeviceSynchronize());
        auto t1=std::chrono::steady_clock::now();
        double sec=std::chrono::duration<double>(t1-t0).count();
        int nh; CHK(cudaMemcpyFromSymbol(&nh,d_nhits,4));
        printf("done %.2fs (%.3g keys/s) nhits=%d\n", sec, nwin/sec, nh);
        { u8 hall[64*16]; int mall[64];
        cudaMemcpyFromSymbol(hall,d_hits,64*16);
        cudaMemcpyFromSymbol(mall,d_hitmode,64*4);
        for (int i=0;i<nh&&i<64;i++){ printf("HIT mode=%d key=",mall[i]); for(int j=0;j<16;j++) printf("%02x",hall[i*16+j]); printf("\n"); } }
        return 0;
    }

    else if (!strcmp(argv[1], "composite")) {
        // pools
        std::vector<std::string> T, N, O, A;
        for (int y=2014; y<=2027; y++)
            for (int m=1;m<=12;m++)
                for (int dd=1;dd<=31;dd++) {
                    char b1[16],b2[16];
                    snprintf(b1,sizeof b1,"%04d%02d%02d",y,m,dd);
                    snprintf(b2,sizeof b2,"%02d%02d%02d",(y%100),m,dd);
                    T.push_back(b1); T.push_back(b2);
                }
        const char* Ns[]={"FSP_RUN","fsp_run","fsp_run.bin","fsp","fsp.bin","fspimage","fsp_image","fmc","gfw","booter","ucode","vbios","nvfw"};
        const char* Os[]={"NVIDIA","nvidia","NVDA","Blackwell","blackwell","GB202","gb202","GB20x","Jensen","jensen","huang","HUANG","\xe9\xbb\x84\xe4\xbb\x81\xe5\x8b\xb3"};
        for (auto s:Ns) N.push_back(s);
        for (auto s:Os) O.push_back(s);
        for (int i=0;i<256;i++){ char b[8]; snprintf(b,sizeof b,"%d",i); A.push_back(b); }
        for (auto s:{"301","401","0x301","0x401","3.1","4.1","v3.1","v4.1"}) A.push_back(s);
        fprintf(stderr,"pools: T=%zu N=%zu O=%zu A=%zu\n",T.size(),N.size(),O.size(),A.size());
        // pack
        auto pack=[](std::vector<std::string>&v, std::string&data, std::vector<u16>&off){
            off.push_back(0);
            for (auto&s:v){ data+=s; off.push_back((u16)data.size()); }
        };
        std::string dT,dN,dO,dA; std::vector<u16> oT,oN,oO,oA;
        pack(T,dT,oT); pack(N,dN,oN); pack(O,dO,oO); pack(A,dA,oA);
        u8 *gT,*gN,*gO,*gA;
        cudaMalloc(&gT,dT.size()); cudaMemcpy(gT,dT.data(),dT.size(),cudaMemcpyHostToDevice);
        cudaMalloc(&gN,dN.size()); cudaMemcpy(gN,dN.data(),dN.size(),cudaMemcpyHostToDevice);
        cudaMalloc(&gO,dO.size()); cudaMemcpy(gO,dO.data(),dO.size(),cudaMemcpyHostToDevice);
        cudaMalloc(&gA,dA.size()); cudaMemcpy(gA,dA.data(),dA.size(),cudaMemcpyHostToDevice);
        cudaMemcpyToSymbol(d_pT,&gT,8); cudaMemcpyToSymbol(d_pN,&gN,8);
        cudaMemcpyToSymbol(d_pO,&gO,8); cudaMemcpyToSymbol(d_pA,&gA,8);
        cudaMemcpyToSymbol(d_oT,oT.data(),oT.size()*2); cudaMemcpyToSymbol(d_oN,oN.data(),oN.size()*2);
        cudaMemcpyToSymbol(d_oO,oO.data(),oO.size()*2); cudaMemcpyToSymbol(d_oA,oA.data(),oA.size()*2);
        int nT=T.size(),nN=N.size(),nO=O.size(),nA=A.size();
        cudaMemcpyToSymbol(d_nT,&nT,4); cudaMemcpyToSymbol(d_nN,&nN,4);
        cudaMemcpyToSymbol(d_nO,&nO,4); cudaMemcpyToSymbol(d_nA,&nA,4);
        // phase1: layout0 (T,N,O,A) seps empty,'_'
        // phase2: layouts1-4, 4 seps, A restricted to specials -> emulate by separate pool? keep full (cheap enough)
        u64 total=0;
        auto t0=std::chrono::steady_clock::now();
        for (int sep=0; sep<4; sep++) {
            u64 cnt=(u64)nT*nN*nO*nA;
            for (u64 d2=0; d2<cnt; d2+=(1ULL<<26)) {
                u64 c=min((u64)(1<<26), cnt-d2);
                k_composite<<<(u32)((c+255)/256),256>>>(d2,c,0,sep);
                cudaPeekAtLastError(); cudaDeviceSynchronize();
                int nh; cudaMemcpyFromSymbol(&nh,d_nhits,4);
                if (nh){ printf("HIT! layout0 sep%d\n",sep);
                    u8 hk[16]; cudaMemcpyFromSymbol(hk,d_hits,16);
                    for(int j=0;j<16;j++)printf("%02x",hk[j]); printf("\n"); return 0; }
            }
            total+=cnt;
        }
        for (int lay=1; lay<=4; lay++)
        for (int sep=0; sep<4; sep++) {
            u64 cnt = (u64)nT*nN*nO*nA;  // all layouts use full radix (decode ignores unused dims)
            for (u64 d2=0; d2<cnt; d2+=(1ULL<<26)) {
                u64 c=min((u64)(1<<26), cnt-d2);
                k_composite<<<(u32)((c+255)/256),256>>>(d2,c,lay,sep);
                cudaPeekAtLastError(); cudaDeviceSynchronize();
                int nh; cudaMemcpyFromSymbol(&nh,d_nhits,4);
                if (nh){ printf("HIT! layout%d sep%d\n",lay,sep);
                    u8 hk[16]; cudaMemcpyFromSymbol(hk,d_hits,16);
                    for(int j=0;j<16;j++)printf("%02x",hk[j]); printf("\n"); return 0; }
            }
            total+=cnt;
        }
        auto t1=std::chrono::steady_clock::now();
        printf("composite done: %llu strings, %.1fs\n",(unsigned long long)total,std::chrono::duration<double>(t1-t0).count());
        return 0;
    }
    else if (!strcmp(argv[1], "composetest")) {
        // synthetic recovery: key = SHA256("20251124_FSP_RUN_NVIDIA_301")[:16]
        u8 key[16]; { u8 h[32]; SHA256((const u8*)"20251124_FSP_RUN_NVIDIA_301",27,h); memcpy(key,h,16); }
        u8 pt[4096]; pt[0]=pt[1]=pt[2]=pt[3]=0;
        for(int i=4;i<4096;i++)pt[i]=(u8)(i*7+1);
        u8 sct[4096],stag[16],siv[12]; for(int i=0;i<12;i++)siv[i]=(u8)(0x30+i);
        EVP_CIPHER_CTX*c=EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(c,EVP_aes_128_gcm(),NULL,NULL,NULL);
        EVP_CIPHER_CTX_ctrl(c,EVP_CTRL_GCM_SET_IVLEN,12,NULL);
        EVP_EncryptInit_ex(c,NULL,NULL,key,siv);
        int l; EVP_EncryptUpdate(c,sct,&l,pt,4096); EVP_EncryptFinal_ex(c,sct+l,&l);
        EVP_CIPHER_CTX_ctrl(c,EVP_CTRL_GCM_GET_TAG,16,stag); EVP_CIPHER_CTX_free(c);
        u64 nb=4096/16;
        u8*buf; cudaMalloc(&buf,4096); cudaMemcpy(buf,sct,4096,cudaMemcpyHostToDevice);
        cudaMemcpyToSymbol(d_ct,&buf,8);
        cudaMemcpyToSymbol(d_ct0,sct,16);
        cudaMemcpyToSymbol(d_nblocks,&nb,8);
        cudaMemcpyToSymbol(d_ivA,siv,12);
        cudaMemcpyToSymbol(d_tagA,stag,16);
        { int z=0; cudaMemcpyToSymbol(d_nhits,&z,4); }
        // tiny pools: T={20251124,251124}, N={FSP_RUN}, O={NVIDIA}, A={301,401}
        std::string dT="20251124251124", dN="FSP_RUN", dO="NVIDIA", dA="301401";
        u16 oT[3]={0,8,14}, oN[2]={0,7}, oO[2]={0,6}, oA[3]={0,3,6};
        u8 *gT,*gN,*gO,*gA; cudaMalloc(&gT,dT.size());cudaMalloc(&gN,dN.size());cudaMalloc(&gO,dO.size());cudaMalloc(&gA,dA.size());
        cudaMemcpy(gT,dT.data(),dT.size(),cudaMemcpyHostToDevice);cudaMemcpy(gN,dN.data(),dN.size(),cudaMemcpyHostToDevice);
        cudaMemcpy(gO,dO.data(),dO.size(),cudaMemcpyHostToDevice);cudaMemcpy(gA,dA.data(),dA.size(),cudaMemcpyHostToDevice);
        cudaMemcpyToSymbol(d_pT,&gT,8);cudaMemcpyToSymbol(d_pN,&gN,8);cudaMemcpyToSymbol(d_pO,&gO,8);cudaMemcpyToSymbol(d_pA,&gA,8);
        cudaMemcpyToSymbol(d_oT,oT,6);cudaMemcpyToSymbol(d_oN,oN,4);cudaMemcpyToSymbol(d_oO,oO,4);cudaMemcpyToSymbol(d_oA,oA,6);
        int nT=2,nN=1,nO=1,nA=2;
        cudaMemcpyToSymbol(d_nT,&nT,4);cudaMemcpyToSymbol(d_nN,&nN,4);cudaMemcpyToSymbol(d_nO,&nO,4);cudaMemcpyToSymbol(d_nA,&nA,4);
        u64 cnt=(u64)nT*nN*nO*nA;
        k_composite<<<1,(u32)cnt>>>(0,cnt,0,1);  // sep='_'
        cudaDeviceSynchronize();
        int nh; cudaMemcpyFromSymbol(&nh,d_nhits,4);
        printf("composetest: nhits=%d (expect 1)\n", nh);
        if (nh){ u8 hk[16]; cudaMemcpyFromSymbol(hk,d_hits,16);
            printf("key: "); for(int j=0;j<16;j++)printf("%02x",hk[j]); printf("\n");
            printf("want: "); for(int j=0;j<16;j++)printf("%02x",key[j]); printf("\n"); }
        return nh==1?0:2;
    }


    else if (!strcmp(argv[1], "msvc32")) {
        u64 base=strtoull(argv[2],0,0), cnt=strtoull(argv[3],0,0);
        fprintf(stderr,"[msvc32] base=%llu count=%llu\n",(unsigned long long)base,(unsigned long long)cnt);
        for (u64 d2=0; d2<cnt; d2+=(1ULL<<28)) {
            u64 c=cnt-d2<(1ULL<<28)?cnt-d2:(1ULL<<28);
            k_msvc32<<<(u32)((c+255)/256),256>>>((u32)(base+d2),c);
            cudaPeekAtLastError(); cudaDeviceSynchronize();
            int nh; cudaMemcpyFromSymbol(&nh,d_nhits,4);
            printf("  %llu/%llu nhits=%d\n",(unsigned long long)(d2+c),(unsigned long long)cnt,nh);
            if (nh){ u8 hk[16]; cudaMemcpyFromSymbol(hk,d_hits,16);
                printf("HIT key="); for(int j=0;j<16;j++)printf("%02x",hk[j]); printf("\n"); return 0; }
        }
        return 0;
    }
    else if (!strcmp(argv[1], "random32")) {
        u64 base=strtoull(argv[2],0,0), cnt=strtoull(argv[3],0,0);
        fprintf(stderr,"[random32] base=%llu count=%llu\n",(unsigned long long)base,(unsigned long long)cnt);
        for (u64 d2=0; d2<cnt; d2+=(1ULL<<28)) {
            u64 c=cnt-d2<(1ULL<<28)?cnt-d2:(1ULL<<28);
            k_random32<<<(u32)((c+255)/256),256>>>((u32)(base+d2),c);
            cudaPeekAtLastError(); cudaDeviceSynchronize();
            int nh; cudaMemcpyFromSymbol(&nh,d_nhits,4);
            printf("  %llu/%llu nhits=%d\n",(unsigned long long)(d2+c),(unsigned long long)cnt,nh);
            if (nh){ u8 hk[16]; cudaMemcpyFromSymbol(hk,d_hits,16);
                printf("HIT key="); for(int j=0;j<16;j++)printf("%02x",hk[j]); printf("\n"); return 0; }
        }
        return 0;
    }
    else if (!strcmp(argv[1], "prngtest")) {
        // MSVC known-vector check + glibc random vs libc check
        // MSVC srand(1): 41,18467,6334,26500,19169,...
        u32 st=1; int ok=1;
        int exp[5]={41,18467,6334,26500,19169};
        for (int i=0;i<5;i++){ st=st*214013u+2531011u; u32 r=(st>>16)&0x7fff;
            if ((int)r!=exp[i]){ok=0;printf("MSVC MISMATCH at %d: got %u want %d\n",i,r,exp[i]);} }
        printf("BINVER-20261026-E\n");
        printf("msvc known-vector: %s\n", ok?"OK":"FAIL");
        // glibc: host reference
        u32 ref[20]={383100999u,858300821u,357768173u,455528251u,133005921u,116285904u};
        // device (serial, via kernel writing to a buffer) — reuse k_random32? write dedicated check here:
        // simple: run one launch of a debug kernel is overkill; emulate on host instead:
        // (device impl mirrors the same code; verify formula path via host emulation identical to device source)
        int gm = glchk(ref);
        printf("glibc random model: %s\n", gm?"FAIL":"OK");
        return (ok&&!gm)?0:2;
    }


    else if (!strcmp(argv[1], "anchor")) {
        u32 base=(u32)strtoul(argv[2],0,0);
        u32 cnt =(u32)strtoul(argv[3],0,0);
        int maxOff=argc>4?atoi(argv[4]):32768;
        // build jump tables: skipping n*20 lrand48 calls: x' = a^k x + c_k, k=n*20
        u64 *jm=(u64*)malloc(sizeof(u64)*maxOff), *ja=(u64*)malloc(sizeof(u64)*maxOff);
        const u64 M=(1ULL<<48)-1, A=0x5DEECE66DULL, C=0xBULL;
        u64 am=1, ac=0;  // a^k, c_k
        jm[0]=1; ja[0]=0;
        for (int n=1;n<maxOff;n++){
            // advance k by 20 calls: (am,ac) = (a^20 * am, a^20*ac + c20)
            u64 a20=1,c20=0;
            for (int q=0;q<20;q++){ c20=(A*c20+C)&M; a20=(A*a20)&M; }
            u64 nm=(a20*am)&M, nc=(a20*ac+c20)&M; am=nm; ac=nc;
            jm[n]=am; ja[n]=ac;
        }
        u64 *dm,*da; cudaMalloc(&dm,sizeof(u64)*maxOff); cudaMalloc(&da,sizeof(u64)*maxOff);
        cudaMemcpy(dm,jm,sizeof(u64)*maxOff,cudaMemcpyHostToDevice);
        cudaMemcpy(da,ja,sizeof(u64)*maxOff,cudaMemcpyHostToDevice);
        cudaMemcpyToSymbol(d_aj_mul,&dm,8); cudaMemcpyToSymbol(d_aj_add,&da,8);
        u64 total=(u64)cnt*maxOff;
        fprintf(stderr,"[anchor] base=%u seeds=%u offsets=%d total pairs=%llu\n",base,cnt,maxOff,(unsigned long long)total);
        for (u64 d2=0; d2<total; d2+=(1ULL<<28)) {
            u64 c2=min((u64)(1<<28), total-d2);
            // launch per sub-range: decompose d2 into seed*n+off
            u32 s0=base+(u32)(d2/maxOff);
            int  o0=(int)(d2%maxOff);
            // simpler: launch by seeds in chunks
            u32 seedsChunk = (u32)(( (u64)1<<28 )/maxOff + 1);
            u32 s1 = min(s0+seedsChunk, base+cnt);
            u32 sc = s1-s0;
            if (o0!=0) { // rare unaligned start: just relaunch whole seeds (o0 small loss acceptable)
                s0 = base+(u32)(d2/maxOff)+1; sc = min(s0+seedsChunk, base+cnt)-s0; if (sc==0) continue;
            }
            k_anchor<<<(u32)(((u64)sc*maxOff+255)/256),256>>>(s0,sc,maxOff);
            cudaPeekAtLastError(); cudaDeviceSynchronize();
            int nh; cudaMemcpyFromSymbol(&nh,d_nhits,4);
            printf("  seed %u..%u nhits=%d\n",s0,s0+sc,nh);
            fflush(stdout);
            if (nh){ u8 hk[16]; cudaMemcpyFromSymbol(hk,d_hits,16);
                printf("HIT key="); for(int j=0;j<16;j++)printf("%02x",hk[j]); printf("\n"); return 0; }
            d2 = ((u64)(s0+sc-base))*maxOff - (1ULL<<28); // advance accounting
        }
        return 0;
    }


    else if (!strcmp(argv[1], "randselftest")) {
        // synthetic: key = glibc random(0x12345678) low-bytes x16 (python-verified)
        u8 key[16]; { const char* h="b4f016e6bbc2a847455dde70c92fe2d9"; for(int i=0;i<16;i++){unsigned v; sscanf(h+2*i,"%2x",&v); key[i]=(u8)v; } }
        u8 pt[4096]; pt[0]=pt[1]=pt[2]=pt[3]=0;
        for(int i=4;i<4096;i++)pt[i]=(u8)(i*9+2);
        u8 sct[4096],stag[16],siv[12]; for(int i=0;i<12;i++)siv[i]=(u8)(0x50+i);
        EVP_CIPHER_CTX*c=EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(c,EVP_aes_128_gcm(),NULL,NULL,NULL);
        EVP_CIPHER_CTX_ctrl(c,EVP_CTRL_GCM_SET_IVLEN,12,NULL);
        EVP_EncryptInit_ex(c,NULL,NULL,key,siv);
        int l; EVP_EncryptUpdate(c,sct,&l,pt,4096); EVP_EncryptFinal_ex(c,sct+l,&l);
        EVP_CIPHER_CTX_ctrl(c,EVP_CTRL_GCM_GET_TAG,16,stag); EVP_CIPHER_CTX_free(c);
        u64 nb=4096/16;
        u8*buf; cudaMalloc(&buf,4096); cudaMemcpy(buf,sct,4096,cudaMemcpyHostToDevice);
        cudaMemcpyToSymbol(d_ct,&buf,8);
        cudaMemcpyToSymbol(d_ct0,sct,16);
        cudaMemcpyToSymbol(d_nblocks,&nb,8);
        cudaMemcpyToSymbol(d_ivA,siv,12);
        cudaMemcpyToSymbol(d_tagA,stag,16);
        cudaMemcpyToSymbol(d_ctr16,siv,16);
        { int z=0; cudaMemcpyToSymbol(d_nhits,&z,4); }
        // first validate the synthetic target via k_single with the exact key
        { u8*dk; cudaMalloc(&dk,16); cudaMemcpy(dk,key,16,cudaMemcpyHostToDevice);
          k_single<<<1,1>>>(dk); cudaDeviceSynchronize();
          int nh0; cudaMemcpyFromSymbol(&nh0,d_nhits,4);
          printf("k_single known-key check: nhits=%d (expect 1)\n", nh0);
          { int z=0; cudaMemcpyToSymbol(d_nhits,&z,4); } }
        k_random32<<<1,256>>>(0x12345600,256);
        cudaDeviceSynchronize();
        int nh; cudaMemcpyFromSymbol(&nh,d_nhits,4);
        printf("randselftest: nhits=%d (expect >=1)\n", nh);
        if (nh>0){ u8 hk[16]; cudaMemcpyFromSymbol(hk,d_hits,16);
            printf("key: "); for(int j=0;j<16;j++)printf("%02x",hk[j]);
            printf("\nwant: b4f016e6bbc2a847455dde70c92fe2d9\n"); }
        return nh>0?0:2;
    }


    else if (!strcmp(argv[1], "randdump")) {
        k_randdbg<<<1,1>>>(12345); cudaDeviceSynchronize();
        u32 o[8]; cudaMemcpyFromSymbol(o,d_randdbg,32);
        printf("device random(12345): "); for(int i=0;i<4;i++)printf("%u ",o[i]); printf("\n");
        printf("expect             : 383100999 858300821 357768173 455528251\n");
        return 0;
    }

    else if (!strcmp(argv[1], "shactr")) {
        u8 seed[16]; const char*hex=argv[2];
        for (int i=0;i<16;i++){ unsigned v; sscanf(hex+2*i,"%2x",&v); seed[i]=(u8)v; }
        u64 hi=strtoull(argv[3],0,0), lo=strtoull(argv[4],0,0), cnt=strtoull(argv[5],0,0);
        u64 start=(hi<<32)|lo;
        u8*ds; CHK(cudaMalloc(&ds,16)); CHK(cudaMemcpy(ds,seed,16,cudaMemcpyHostToDevice));
        printf("[shactr] seed=%s from %llx count %llx\n", hex, (unsigned long long)start, (unsigned long long)cnt);
        // chunked launches for progress
        const u64 CH=1ULL<<28;
        for (u64 done=0; done<cnt; done+=CH) {
            u64 c=(cnt-done<CH)?cnt-done:CH;
            k_shactr<<<(u32)((c+255)/256),256>>>(ds,start+done,c);
            CHK(cudaPeekAtLastError());
            CHK(cudaDeviceSynchronize());
            int nh; CHK(cudaMemcpyFromSymbol(&nh,d_nhits,4));
            printf("  %llu/%llu nhits=%d\n",(unsigned long long)(done+c),(unsigned long long)cnt,nh);
            if (nh>0) {
                u8 hk[16]; CHK(cudaMemcpyFromSymbol(hk,d_hits,16));
                printf("HIT key="); for(int j=0;j<16;j++) printf("%02x",hk[j]); printf("\n");
                return 0;
            }
        }
        return 0;
    }
    return 1;
}

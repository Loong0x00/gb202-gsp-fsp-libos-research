/* emem_cli.c —— 通用 EMEM 客户端(基址可用环境变量覆盖 ⇒ FSP 与 SEC2 通用)
 * 用法:
 *   sudo ./emem_cli status [chan]
 *   sudo env EMEMC=0x8f2ac0 ... ./emem_cli send <chan> <hex>
 *   sudo ./emem_cli recv <chan>
 * 环境变量:BDF / EMEMC / EMEMD / QHEAD / QTAIL / MHEAD / MTAIL */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/mman.h>
static unsigned long B_EMEMC=0x8f2ac0,B_EMEMD=0x8f2ac4,B_QHEAD=0x8f2c00,
                     B_QTAIL=0x8f2c04,B_MHEAD=0x8f2c80,B_MTAIL=0x8f2c84;
static volatile uint8_t *bar;
static uint32_t rd(unsigned o){ return *(volatile uint32_t *)(bar+o); }
static void     wr(unsigned o,uint32_t v){ *(volatile uint32_t *)(bar+o)=v; }
static void envul(const char *n,unsigned long *p){ const char *e=getenv(n); if(e) *p=strtoul(e,0,0); }
static int hv(char c){ if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return c-'a'+10;
                       if(c>='A'&&c<='F')return c-'A'+10; return -1; }
int main(int argc,char **argv)
{
    envul("EMEMC",&B_EMEMC); envul("EMEMD",&B_EMEMD); envul("QHEAD",&B_QHEAD);
    envul("QTAIL",&B_QTAIL); envul("MHEAD",&B_MHEAD); envul("MTAIL",&B_MTAIL);
    const char *bdf=getenv("BDF"); if(!bdf) bdf="0000:01:00.0";
    char path[256]; snprintf(path,sizeof path,"/sys/bus/pci/devices/%s/resource0",bdf);
    int fd=open(path,O_RDWR|O_SYNC);
    if(fd<0){ perror("open resource0"); return 1; }
    bar=mmap(0,0x900000,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    if(bar==MAP_FAILED){ perror("mmap BAR0"); return 1; }
    if(argc<2){ fprintf(stderr,"usage: %s status|send|recv [chan] [hex]\n",argv[0]); return 2; }
    unsigned ch = (argc>2)?(unsigned)atoi(argv[2]):0;
    if(!strcmp(argv[1],"status")){
        printf("chan=%u  EMEMC=%#010x  QHEAD=%u QTAIL=%u  MHEAD=%u MTAIL=%u  (基址 EMEMC=%#lx EMEMD=%#lx Q=%#lx M=%#lx)\n",
            ch, rd(B_EMEMC+8*ch), rd(B_QHEAD+8*ch), rd(B_QTAIL+8*ch),
            rd(B_MHEAD+8*ch), rd(B_MTAIL+8*ch), B_EMEMC, B_EMEMD, B_QHEAD, B_MHEAD);
    } else if(!strcmp(argv[1],"send")){
        if(argc<4){ fprintf(stderr,"send 需要 hex\n"); return 2; }
        const char *h=argv[3]; int n=0; uint8_t buf[4096];
        while(h[0]&&h[1]&&n<4096){ int a=hv(h[0]),b=hv(h[1]); if(a<0||b<0)break; buf[n++]=(a<<4)|b; h+=2; }
        if(n<4){ fprintf(stderr,"太短\n"); return 2; }
        int nd=(n+3)/4;
        wr(B_EMEMC+8*ch, 0x01000000u);                 /* 偏移 0 + AINCW */
        for(int i=0;i<nd;i++){ uint32_t w=0; memcpy(&w,buf+4*i, (4*i+4<=n)?4:(n-4*i)); wr(B_EMEMD+8*ch,w); }
        wr(B_QTAIL+8*ch,(uint32_t)(nd-1));             /* 声明长度 */
        wr(B_QHEAD+8*ch,0);                            /* 敲门铃 */
        printf("已发送 %d 字节(%d dword)  QT=%u\n", n, nd, rd(B_QTAIL+8*ch));
    } else if(!strcmp(argv[1],"recv")){
        uint32_t mh=rd(B_MHEAD+8*ch), mt=rd(B_MTAIL+8*ch);
        int len=(int)(mt-mh)+4;
        printf("MSGQ head=%u tail=%u ⇒ %d 字节\n",mh,mt,len);
        if(len>0&&len<4096){
            wr(B_EMEMC+8*ch, 0x02000000u);             /* 偏移 0 + AINCR */
            for(int k=0;k<len/4+1;k++) printf("[%2d] %#010x\n",k,rd(B_EMEMD+8*ch));
        }
    } else fprintf(stderr,"未知模式 %s\n",argv[1]);
    return 0;
}

#!/usr/bin/env python3
"""
GSP LibOS RV64 模拟器 — 全系统裸奔可见
用法: python3 rv64_emu.py [max_steps] [boot_a0]
默认: 跑内核boot+init, dump页表/任务/PMP状态
"""
import struct, sys
from capstone import *

# ══════════════ 内存 (稀疏页) ══════════════
class Memory:
    def __init__(self):
        self.pages = {}   # page_base → bytearray(4096)
        self.watch = {}   # page_base → callback(addr, size, val)
        self.aliases = [] # (alias_base, phys_base, size) — PMP窗口

    def add_alias(self, alias, phys, size):
        self.aliases.append((alias & ~0xFFF & M64 if False else alias, phys, size))
        print(f"[PMP窗口] {alias:#x} → {phys:#x} (+{size:#x})")

    def translate(self, addr):
        for ab, pb, sz in self.aliases:
            if ab <= addr < ab + sz:
                return pb + (addr - ab)
        return addr

    def _page(self, addr):
        base = addr & ~0xFFF
        p = self.pages.get(base)
        if p is None:
            p = bytearray(4096)
            self.pages[base] = p
        return p, addr & 0xFFF

    def read(self, addr, size):
        addr = self.translate(addr)
        val = 0
        for i in range(size):
            p, off = self._page(addr + i)
            val |= p[off] << (8*i)
        return val

    def write(self, addr, size, val):
        addr = self.translate(addr)
        for i in range(size):
            p, off = self._page(addr + i)
            p[off] = (val >> (8*i)) & 0xFF
        base = addr & ~0xFFF
        if base in self.watch:
            self.watch[base](addr, size, val)

    def load_elf(self, path):
        data = open(path, 'rb').read()
        e_phoff = struct.unpack_from('<Q', data, 0x20)[0]
        e_phnum = struct.unpack_from('<H', data, 0x38)[0]
        e_phentsize = struct.unpack_from('<H', data, 0x36)[0]
        segs = []
        for i in range(e_phnum):
            off = e_phoff + i*e_phentsize
            p_type = struct.unpack_from('<I', data, off)[0]
            if p_type != 1: continue
            p_offset, p_vaddr, _, p_filesz, p_memsz = struct.unpack_from('<QQQQQ', data, off+8)
            for j in range(p_filesz):
                self.write(p_vaddr + j, 1, data[p_offset + j])
            segs.append((p_vaddr, p_memsz))
        return segs

# ══════════════ RV64 模拟器 ══════════════
MD = Cs(CS_ARCH_RISCV, CS_MODE_RISCV64 | CS_MODE_RISCVC)
MD.skipdata = False
M64 = (1 << 64) - 1

def sx(val, bits):
    if val & (1 << (bits-1)): return val - (1 << bits)
    return val

class Emu:
    def __init__(self, mem):
        self.mem = mem
        self.x = [0]*32
        self.f = [0]*32          # 浮点寄存器只存位
        self.pc = 0
        self.csr = {}            # CSR号 → 值 (含自定义)
        self.priv = 1            # 1=S-mode启动(内核)
        self.steps = 0
        self.icache = {}         # pc → (mnemonic, op_str)
        self.log = []
        self.stop_reason = None
        self.bootrom_ecalls = 0
        self.timer = 0
        # 标准CSR初始
        self.csr[0x100] = 0x22   # sstatus
        self.csr[0x180] = 0      # satp

    # ── 取指+解码(带缓存) ──
    def fetch(self):
        pc = self.pc
        ins = self.icache.get(pc)
        if ins is None:
            hw = self.mem.read(pc, 2)
            size = 4 if (hw & 3) == 3 else 2
            raw = self.mem.read(pc, size)
            try:
                d = next(MD.disasm(struct.pack('<I', raw)[:size] if size==4 else struct.pack('<H', raw), pc))
                ins = (d.mnemonic, d.op_str)
            except StopIteration:
                ins = ('.und', hex(raw))
            self.icache[pc] = ins
        return ins

    def rd(self, r): return self.x[r] if r else 0
    def wr(self, r, v):
        if r: self.x[r] = v & M64

    CSR_NAMES = {'satp':0x180,'sstatus':0x100,'sepc':0x141,'scause':0x142,'stval':0x143,
                 'sscratch':0x140,'scounteren':0x106,'stvec':0x105,'sie':0x104,
                 'mstatus':0x300,'mepc':0x341,'mie':0x304,'time':0xC01,'cycle':0xC00,
                 'instret':0xC02,'sip':0x144,'hartid':0xF14}
    def csrnum(self, s):
        if s in self.CSR_NAMES: return self.CSR_NAMES[s]
        try: return int(s, 0)
        except: return None

    # ── 定时器注入 (指令计数驱动, 相位锁定实验用) ──
    timer_period_insns = 0      # 0=关闭; >0 = 每N条指令投递S-timer中断
    timer_next_at = 0
    # ── 主执行 ──
    def step(self):
        # ── memset快进: 内核的inline memset循环 ──
        if self.pc == 0xffffffff93004eea:
            a2 = self.x[12]  # remaining
            a5 = self.x[15]  # dst
            a1 = self.x[11]  # value
            if a2 and a2 < (1<<32):
                phys = self.mem.translate(a5)
                base = phys & ~0xFFF
                # 跨页填充
                remaining = a2; addr = a5; val = a1 & 0xFF
                while remaining > 0:
                    p, off = self.mem._page(self.mem.translate(addr))
                    n = min(remaining, 4096 - off)
                    p[off:off+n] = bytes([val])*n
                    addr += n; remaining -= n
                self.x[15] = (a5 + a2) & M64
                self.x[12] = 0
            self.pc = self.x[1] & M64  # c.jr ra
            self.steps += 1
            return True
        if self.timer_period_insns and self.steps >= self.timer_next_at:
            self.timer_next_at = self.steps + self.timer_period_insns
            stvec = self.csr.get(0x105, 0)
            if stvec and self.priv >= 0 and self.pc != stvec:
                import struct as _s
                old_sstatus = self.csr.get(0x100, 0)
                self.csr[0x141] = self.pc
                self.csr[0x142] = 0x8000000000000005  # S-timer intr
                self.csr[0x143] = 0
                self.csr[0x100] = ((old_sstatus & ~0x120) | 0x20) | ((old_sstatus & 0x1) << 8) | 1
                # SIE位(1)清除 → S-mode, SPP保留旧值... 简化: 进S-mode关中断
                self.priv = 1
                self.log.append(f"[TICK] @{self.pc:#x} steps={self.steps}")
                self.pc = stvec
        mnem, ops = self.fetch()
        self.steps += 1
        self.timer += 100  # 每步时间+100
        pc = self.pc
        nxt = pc + (4 if (self.mem.read(pc,2) & 3) == 3 else 2)

        O = ops.replace(' ', '')

        try:
            # ══ 伪指令 ══
            if mnem in ('mv','c.mv'):
                p=O.split(',')
                self.wr(self.regnum(p[0]), self.rd(self.regnum(p[1])))
            elif mnem=='not':
                p=O.split(','); self.wr(self.regnum(p[0]), (~self.rd(self.regnum(p[1])))&M64)
            elif mnem=='neg':
                p=O.split(','); self.wr(self.regnum(p[0]), (-self.rd(self.regnum(p[1])))&M64)
            elif mnem=='seqz':
                p=O.split(','); self.wr(self.regnum(p[0]), 1 if self.rd(self.regnum(p[1]))==0 else 0)
            elif mnem=='snez':
                p=O.split(','); self.wr(self.regnum(p[0]), 1 if self.rd(self.regnum(p[1]))!=0 else 0)
            elif mnem=='sext.w':
                p=O.split(','); self.wr(self.regnum(p[0]), sx(self.rd(self.regnum(p[1])),32)&M64)
            elif mnem=='zext.w':
                p=O.split(','); self.wr(self.regnum(p[0]), self.rd(self.regnum(p[1]))&0xFFFFFFFF)

            # ══ 跳转类 ══
            elif mnem in ('jal', 'c.jal'):
                p = O.split(',')
                off = int(p[-1], 0)
                if mnem == 'jal' and len(p) >= 2:
                    rd = self.regnum(p[0])   # jal rd, off — rd可以是gp!
                else:
                    rd = 1  # c.jal固定ra
                self.wr(rd, nxt)
                nxt = (pc + off) & M64
            elif mnem == 'jalr':
                p = O.split(',')
                if len(p) == 3:
                    rd_n = self.regnum(p[0]); rs_n = self.regnum(p[1]); imm = int(p[2], 0)
                else:
                    rd_n = 1; rs_n = self.regnum(p[0]); imm = 0  # jalr rs = jalr ra, rs, 0
                tgt = (self.rd(rs_n) + imm) & M64 & ~1
                self.wr(rd_n, nxt)
                nxt = tgt
            elif mnem == 'c.jalr':
                p = O.split(',')
                tgt = self.rd(self.regnum(p[0])) & ~1
                self.wr(1, nxt)
                nxt = tgt
            elif mnem == 'j' or mnem == 'c.j':
                nxt = (pc + int(O, 0)) & M64
            elif mnem in ('jr', 'c.jr'):
                nxt = self.rd(self.regnum(O)) & M64 & ~1 if O != 'ra' else self.x[1]
            elif mnem == 'ret':
                nxt = self.x[1]

            # ══ 分支 ══
            elif mnem == 'beq':
                p = O.split(','); a=self.rd(self.regnum(p[0])); b=self.rd(self.regnum(p[1])); off=int(p[2],0)
                if a==b: nxt=(pc+off)&M64
            elif mnem == 'bne':
                p = O.split(','); a=self.rd(self.regnum(p[0])); b=self.rd(self.regnum(p[1])); off=int(p[2],0)
                if a!=b: nxt=(pc+off)&M64
            elif mnem in ('blt','bge','bltu','bgeu'):
                p = O.split(','); a=self.rd(self.regnum(p[0])); b=self.rd(self.regnum(p[1])); off=int(p[2],0)
                u = 'u' in mnem
                av, bv = (a,b) if u else (sx(a,64), sx(b,64))
                if (mnem.startswith('blt') and av<bv) or (mnem.startswith('bge') and av>=bv):
                    nxt=(pc+off)&M64
            elif mnem in ('beqz','c.beqz'):
                p=O.split(','); v=self.rd(self.regnum(p[0])); off=int(p[1],0)
                if v==0: nxt=(pc+off)&M64
            elif mnem in ('bnez','c.bnez'):
                p=O.split(','); v=self.rd(self.regnum(p[0])); off=int(p[1],0)
                if v!=0: nxt=(pc+off)&M64
            elif mnem in ('bgez','bgtz','blez','bltz'):
                p=O.split(','); v=sx(self.rd(self.regnum(p[0])),64); off=int(p[-1],0)
                if (mnem=='bgez' and v>=0) or (mnem=='bgtz' and v>0) or (mnem=='blez' and v<=0) or (mnem=='bltz' and v<0):
                    nxt=(pc+off)&M64

            # ══ 立即数运算 ══
            elif mnem in ('addi','c.addi','c.addiw','addiw','andi','c.andi','ori','xori','slli','c.slli','srli','c.srli','srai','c.srai','slti','sltiu','slliw','srliw','sraiw','li','c.li','c.addi16sp','c.addi4spn'):
                p=O.split(',')
                rd=self.regnum(p[0])
                if len(p)>=3:
                    rs=self.regnum(p[1]); imm=int(p[2],0)
                elif mnem in ('li','c.li'):
                    rs=0; imm=int(p[1],0)   # li rd, imm = addi rd, zero, imm
                else:  # 压缩形式: rd隐式即源
                    rs=rd; imm=int(p[1],0)
                if mnem in ('li','c.li'):
                    r = imm & M64
                else:
                    a=self.rd(rs)
                    w = 'w' in mnem
                    if 'addi' in mnem:
                        r = (sx(sx(a,64)+imm, 32) & M64) if w else ((a+imm)&M64)
                    elif mnem in ('andi','c.andi'): r=a&(imm&M64)
                    elif mnem=='ori': r=a|(imm&M64)
                    elif mnem=='xori': r=a^(imm&M64)
                    elif 'slli' in mnem:
                        sh=imm&(0x1f if w else 0x3f)
                        r=(((a&0xFFFFFFFF)<<sh)&0xFFFFFFFF) if w else ((a<<sh)&M64)
                    elif 'srli' in mnem or 'srai' in mnem:
                        sh=imm&(0x1f if w else 0x3f)
                        if 'srai' in mnem:
                            r=((sx(a&0xFFFFFFFF,32)>>sh)&0xFFFFFFFF) if w else ((sx(a,64)>>sh)&M64)
                        else:
                            r=((a&0xFFFFFFFF)>>sh) if w else ((a&M64)>>sh)
                    elif mnem=='slti': r=1 if sx(a,64)<imm else 0
                    elif mnem=='sltiu': r=1 if a<(imm&M64) else 0
                    else: r=a
                self.wr(rd,r)

            # ══ 寄存器运算 ══
            elif mnem in ('add','c.add','sub','c.sub','and','c.and','or','c.or','xor','sll','srl','sra','slt','sltu','mul','div','divu','rem','remu','addw','subw','mulw','divw','divuw','remw','remuw','sllw','srlw','sraw'):
                p=O.split(',')
                rd=self.regnum(p[0])
                if len(p)>=3:
                    rs1=self.regnum(p[1]); rs2=self.regnum(p[2])
                else:  # 压缩: rd即rs1
                    rs1=rd; rs2=self.regnum(p[1])
                a=self.rd(rs1); b=self.rd(rs2)
                base=mnem.replace('c.','')
                if base=='add': r=(a+b)&M64
                elif base=='sub': r=(a-b)&M64
                elif base=='and': r=a&b
                elif base=='or': r=a|b
                elif base=='xor': r=a^b
                elif base=='sll': r=(a<<(b&0x3f))&M64
                elif base=='srl': r=(a&M64)>>(b&0x3f)
                elif base=='sra': r=(sx(a,64)>>(b&0x3f))&M64
                elif base=='slt': r=1 if sx(a,64)<sx(b,64) else 0
                elif base=='sltu': r=1 if a<b else 0
                elif base=='mul': r=(a*b)&M64
                elif base=='div':
                    r=0xFFFFFFFFFFFFFFFF if sx(b,64)==-1 and a==(1<<63) else ((1<<64)-1 if sx(b,64)==0 else (sx(a,64)//sx(b,64))&M64 if (sx(a,64)<0)!=(sx(b,64)<0) and sx(a,64)%sx(b,64)!=0 else (sx(a,64)//sx(b,64))&M64)
                elif base=='divu': r=(M64 if b==0 else a//b)
                elif base=='rem': r=(a if sx(b,64)==0 else (sx(a,64)%sx(b,64))&M64)
                elif base=='remu': r=(a if b==0 else a%b)
                elif base.endswith('w'):
                    aa=a&0xFFFFFFFF; bb=b&0xFFFFFFFF
                    if base=='addw': r=(aa+bb)&0xFFFFFFFF
                    elif base=='subw': r=(aa-bb)&0xFFFFFFFF
                    elif base=='mulw': r=(aa*bb)&0xFFFFFFFF
                    elif base=='divw': r=0xFFFFFFFF if (sx(bb,32)==0) else (sx(aa,32)//sx(bb,32))&0xFFFFFFFF
                    elif base=='divuw': r=0xFFFFFFFF if bb==0 else aa//bb
                    elif base=='remw': r=aa if sx(bb,32)==0 else (sx(aa,32)%sx(bb,32))&0xFFFFFFFF
                    elif base=='remuw': r=aa if bb==0 else aa%bb
                    elif base=='sllw': r=(aa<<(bb&0x1f))&0xFFFFFFFF
                    elif base=='srlw': r=aa>>(bb&0x1f)
                    elif base=='sraw': r=(sx(aa,32)>>(bb&0x1f))&0xFFFFFFFF
                self.wr(rd,r)

            # ══ 高位加载 ══
            elif mnem in ('lui','c.lui','auipc'):
                p=O.split(',')
                rd=self.regnum(p[0])
                if mnem=='auipc':
                    imm=int(p[1],0)
                    r=(pc+(imm<<12))&M64 if -0x80000<=imm<0x80000 else (pc+((imm&M64)<<12))&M64
                else:
                    imm=int(p[1],0)
                    r=(imm<<12)&M64
                self.wr(rd,r)

            # ══ 内存 load ══
            elif mnem.startswith(('ld','lw','lh','lb','lwu','lhu','lbu','c.ld','c.lw','c.lwsp','c.ldsp','c.fld','c.fldsp')):
                if '(' in O:
                    paren=O.split('(',1)
                    base=paren[1].rstrip(')')
                    parts=[x for x in paren[0].split(',') if x]
                    rn=self.regnum(parts[0])
                    imm=int(parts[1],0) if len(parts)>1 else 0
                    addr=(self.rd(self.regnum(base))+imm)&M64
                    m=mnem.replace('c.','').replace('.fld','').replace('fld','ld64')
                    if mnem in ('ld','c.ld','c.ldsp','c.fld','c.fldsp'): v=self.mem.read(addr,8)
                    elif mnem in ('lw','c.lw','c.lwsp','lwu'): 
                        v=self.mem.read(addr,4)
                        if mnem=='lw': v=sx(v,32)&M64
                    elif mnem=='lh': v=sx(self.mem.read(addr,2),16)&M64
                    elif mnem=='lhu': v=self.mem.read(addr,2)
                    elif mnem=='lb': v=sx(self.mem.read(addr,1),8)&M64
                    elif mnem=='lbu': v=self.mem.read(addr,1)
                    else: v=self.mem.read(addr,8)
                    if mnem.startswith(('c.fld','c.fldsp')):
                        self.f[rn]=v
                    else:
                        self.wr(rn,v)

            # ══ 内存 store ══
            elif mnem.startswith(('sd','sw','sh','sb','c.sd','c.sw','c.swsp','c.sdsp','c.fsd','c.fsdsp','fsw')):
                if '(' in O:
                    paren=O.split('(',1)
                    base=paren[1].rstrip(')')
                    parts=[x for x in paren[0].split(',') if x]
                    rn=self.regnum(parts[0])
                    imm=int(parts[1],0) if len(parts)>1 else 0
                    addr=(self.rd(self.regnum(base))+imm)&M64
                    if mnem.startswith(('sd','c.sd','c.sdsp','c.fsd','c.fsdsp')): 
                        v=self.f[rn] if mnem.startswith(('c.fsd','c.fsdsp')) else self.rd(rn)
                        self.mem.write(addr,8,v)
                    elif mnem in ('sw','c.sw','c.swsp','fsw'):
                        v=self.f[rn] if mnem=='fsw' else self.rd(rn)
                        self.mem.write(addr,4,v&M64)
                    elif mnem=='sh': self.mem.write(addr,2,self.rd(rn)&0xFFFF)
                    elif mnem=='sb': self.mem.write(addr,1,self.rd(rn)&0xFF)

            # ══ CSR ══
            elif mnem.startswith('csr') or mnem in ('csrs',):
                p=O.split(',')
                if mnem=='csrwi':
                    n=self.csrnum(p[0]); v=int(p[1],0); self.csr[n]=v&M64
                elif mnem in ('csrw','csrs'):
                    n=self.csrnum(p[0]); rn=self.regnum(p[1]); self.csr[n]=self.rd(rn)
                    if n == 1483 and (self.rd(rn) & 1):  # PMP窗口commit!
                        alias = self.rd(rn) & ~1 & M64
                        phys = self.csr.get(1484, 0)
                        size = self.csr.get(1486, 0)
                        self.mem.add_alias(alias, phys, size)
                elif mnem=='csrr':
                    rn=self.regnum(p[0]); n=self.csrnum(p[1]); self.wr(rn,self.csr.get(n,0))
                elif mnem=='csrrs' or mnem=='csrsi':
                    if mnem=='csrrs':
                        rn=self.regnum(p[0]); n=self.csrnum(p[1]); r2=self.regnum(p[2])
                        old=self.csr.get(n,0); self.csr[n]=(old|self.rd(r2))&M64; self.wr(rn,old)
                    else:
                        rn=self.regnum(p[0]); n=int(p[1],0); imm=int(p[2],0)
                        old=self.csr.get(n,0); self.csr[n]=(old|imm)&M64; self.wr(rn,old)
                elif mnem=='csrrsi':
                    rn=self.regnum(p[0]); n=self.csrnum(p[1]); imm=int(p[2],0)
                    old=self.csr.get(n,0); self.csr[n]=(old|imm)&M64; self.wr(rn,old)
                elif mnem=='csrrci':
                    rn=self.regnum(p[0]); n=self.csrnum(p[1]); imm=int(p[2],0)
                    old=self.csr.get(n,0); self.csr[n]=(old&~imm)&M64; self.wr(rn,old)
                elif mnem=='csrrwi':
                    rn=self.regnum(p[0]); n=self.csrnum(p[1]); imm=int(p[2],0)
                    self.wr(rn,self.csr.get(n,0)); self.csr[n]=imm&M64

            # ══ 特殊 ══
            elif mnem=='rdtime':
                rn=self.regnum(O.split(',')[0])
                self.wr(rn,self.timer&M64)
            elif mnem=='ecall':
                self.bootrom_ecalls += 1
                self.log.append(f"[ECALL→BootROM #{self.bootrom_ecalls}] a7={self.x[17]:#x} a0={self.x[10]:#x} a1={self.x[11]:#x} a2={self.x[12]:#x} a3={self.x[13]:#x} a4={self.x[14]:#x} a5={self.x[15]:#x} pc={pc:#x}")
                # BootROM返回: a0=0 (成功)
                self.x[10] = 0
            elif mnem=='ebreak' or mnem=='c.ebreak':
                self.stop_reason = f"EBREAK @ {pc:#x}"
                return False
            elif mnem=='sret':
                newpc = self.csr.get(0x141, 0)
                spp = (self.csr.get(0x100,0) >> 8) & 1
                self.priv = spp  # SPP=1→S-mode, 0→U-mode
                if self.log and self.log[-1].startswith('[SYSCALL'):
                    self.log.append(f"  [RET] a0={self.x[10]:#x} → {newpc:#x}")
                self.log.append(f"[SRET] → {newpc:#x} priv={'S' if spp else 'U'}")
                self.pc = newpc & M64
                return True
            elif mnem=='wfi':
                # 投递定时器中断! (模拟硬件timer)
                stvec = self.csr.get(0x105, 0)
                if stvec:
                    self.csr[0x141] = nxt          # sepc = wfi下一条
                    self.csr[0x142] = 0x8000000000000005  # scause = S-timer interrupt
                    self.csr[0x143] = 0
                    self.csr[0x100] = self.csr.get(0x100,0) | 0x20
                    self.pc = stvec
                    self.log.append(f"[TIMER-INT] @ {pc:#x}")
                    return True
            elif mnem=='fence' or mnem=='fence.i':
                pass
            elif mnem in ('nop','c.nop'):
                pass
            elif mnem=='c.unimp' or mnem=='.und':
                # RM固件syscall陷阱 → 投递到stvec
                stvec = self.csr.get(0x105, 0)
                if stvec and self.priv == 0:  # 用户态才有syscall快速路径
                    self.csr[0x141] = pc          # sepc
                    self.csr[0x142] = 2           # scause = illegal instr
                    self.csr[0x143] = 0           # stval = 0 (指令字就是0!)
                    old_sstatus = self.csr.get(0x100, 0)
                    self.csr[0x100] = (old_sstatus & ~0x100) | 0x20  # SPP=0(user), SPIE=1
                    self.priv = 1
                    self.pc = stvec
                    self.log.append(f"[SYSCALL] pc={pc:#x} t0={self.x[5]} a0={self.x[10]:#x} a1={self.x[11]:#x} a2={self.x[12]:#x} a3={self.x[13]:#x} a4={self.x[14]:#x} a5={self.x[15]:#x}")
                    return True
                self.stop_reason = f"UNIMP@kernel pc={pc:#x} t0={self.x[5]:#x}"
                return False
            elif mnem.startswith('f') and ('add' in mnem or 'sub' in mnem or 'mul' in mnem):
                rd=self.regnum(O.split(',')[0]); self.f[rd]=0  # 浮点=0
            else:
                self.stop_reason = f"未实现指令 {mnem} {ops} @ {pc:#x}"
                return False

        except Exception as e:
            self.stop_reason = f"异常: {e} @ {mnem} {ops} pc={pc:#x}"
            return False

        self.pc = nxt
        return True

    def regnum(self, s):
        s = s.strip()
        names = {'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,'t0':5,'t1':6,'t2':7,
                 's0':8,'fp':8,'s1':9,
                 'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
                 's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,'s8':24,'s9':25,'s10':26,'s11':27,
                 't3':28,'t4':29,'t5':30,'t6':31}
        if s in names: return names[s]
        if s.startswith('x'): return int(s[1:])
        return 0

    def run(self, max_steps=2_000_000):
        last_pc_count = {}
        while self.steps < max_steps:
            if not self.step(): break
            # 循环检测: 同一pc执行太多次
            c = last_pc_count.get(self.pc, 0) + 1
            last_pc_count[self.pc] = c
            if c > 200000:
                self.stop_reason = f"循环卡死 @ {self.pc:#x} (200K次)"
                break
        return self.steps

# ══════════════ 主程序 ══════════════
if __name__ == '__main__':
    max_steps = int(sys.argv[1]) if len(sys.argv) > 1 else 500_000
    boot_a0   = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x30

    mem = Memory()
    segs = mem.load_elf('/tmp/kernel_gb20x.elf')
    print(f"段加载: {[(hex(a), hex(s)) for a, s in segs]}")

    emu = Emu(mem)
    emu.x[10] = boot_a0   # a0 = BootROM参数
    emu.x[17] = 0xffffffffa3000000  # a7 = 内核数据段物理地址(BootROM提供)
    emu.csr[0x105] = 0xffffffff93000114  # stvec = trap入口 (BootROM设置)
    emu.pc = 0xffffffff93000000

    print(f"启动: pc={emu.pc:#x}, a0={boot_a0:#x}, 最多{max_steps}步")
    print("─" * 60)

    n = emu.run(max_steps)

    print(f"\n执行了 {n} 步, 停止原因: {emu.stop_reason or '步数用尽'}")
    print(f"\n寄存器:")
    for i in range(0, 32, 4):
        print(f"  x{i:2d}={emu.x[i]:#018x} x{i+1:2d}={emu.x[i+1]:#018x} x{i+2:2d}={emu.x[i+2]:#018x} x{i+3:2d}={emu.x[i+3]:#018x}")

    print(f"\nCSR:")
    for k in sorted(emu.csr):
        if emu.csr[k] or k in (0x180, 0x100, 0x140, 0x141):
            print(f"  {k} ({k:#x}): {emu.csr[k]:#x}")

    print(f"\n日志 (最后30条):")
    for l in emu.log[-30:]:
        print(f"  {l}")

    # dump关键数据段位置
    print(f"\n内存页数: {len(mem.pages)}")

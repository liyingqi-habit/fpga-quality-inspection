"""Deterministic RV32IM vectors; Python integer oracle, not RTL-derived."""
from pathlib import Path
import json
import sys

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
asm = ['.section .text.start,"ax"', '.option norvc', '.global _start', '_start:j main',
       '.org 0x80', 'j handler', '.org 0x100', 'main:', 'li x28,0x80004800',
       'li s4,0', 'li s5,0', 'li s6,0x10000000']
results = []; coverage = {}
def signed(v): return v - (1 << 32) if v & (1 << 31) else v
def emit(op, instructions, value):
    asm.extend(instructions + ['sw x3,0(x28)', 'addi x28,x28,4'])
    results.append(value & 0xffffffff)
    coverage[op] = coverage.get(op, 0)+1

for a,b in ((0,0),(1,1),(0xffffffff,3),(0x80000000,0xffffffff),(0x7fffffff,31),(0xaaaa5555,0x12345678)):
    sa,sb=signed(a),signed(b); shift=b&31
    q = -1 if b==0 else (abs(sa)//abs(sb)) * (-1 if (sa<0)!=(sb<0) else 1)
    r = sa if b==0 else sa-q*sb
    values={'add':a+b,'sub':a-b,'sll':a<<shift,'slt':int(sa<sb),'sltu':int(a<b),
            'xor':a^b,'srl':a>>shift,'sra':sa>>shift,'or':a|b,'and':a&b,
            'mul':a*b,'mulh':(sa*sb)>>32,'mulhsu':(sa*b)>>32,'mulhu':(a*b)>>32,
            'div':q,'divu':0xffffffff if b==0 else a//b,'rem':r,'remu':a if b==0 else a%b}
    for op,value in values.items():
        emit(op,[f'li x1,{a}',f'li x2,{b}',f'{op} x3,x1,x2'],value)
    for op,value in {'addi':a-17,'slti':int(sa < -17),'sltiu':int(a<0xffffffef),
                     'xori':a^0xffffffef,'ori':a|0xffffffef,'andi':a&0xffffffef,
                     'slli':a<<31,'srli':a>>31,'srai':sa>>31}.items():
        emit(op,[f'li x1,{a}',f'{op} x3,x1,{31 if op in ("slli","srli","srai") else -17}'],value)
emit('lui',['lui x3,0xabcde'],0xabcde000)
asm += ['auipc x1,0','auipc x3,0','sub x3,x3,x1']
emit('auipc',[],4)
for op in ('beq','bne','blt','bge','bltu','bgeu'):
    for a,b in ((0xffffffff,1),(1,1),(1,0xffffffff)):
        sa,sb=signed(a),signed(b)
        taken={'beq':a==b,'bne':a!=b,'blt':sa<sb,'bge':sa>=sb,'bltu':a<b,'bgeu':a>=b}[op]
        label=f'branch_{len(results)}'
        emit(op,[f'li x1,{a}',f'li x2,{b}','li x3,0',f'{op} x1,x2,{label}',
                 'li x3,1',f'{label}:'],0 if taken else 1)
asm += ['jal x1,link_target','j fail','link_target:','la x2,link_target','addi x2,x2,-4','sub x3,x1,x2']
emit('jal',[],0)
asm += ['la x2,indirect_target','jalr x1,0(x2)','j fail','indirect_target:',
        'la x2,indirect_target','addi x2,x2,-4','sub x3,x1,x2']
emit('jalr',[],0)
asm += ['li x4,0x80004400','li x1,0x89abcdef','sw x1,0(x4)']
for op,offset,value in [('lw',0,0x89abcdef),('lb',0,-17),('lbu',0,239),('lh',2,-30293),('lhu',2,0x89ab)]:
    emit(op,[f'{op} x3,{offset}(x4)'],value)
asm += ['li x1,0x12','sb x1,1(x4)','li x1,0x3456','sh x1,2(x4)']
emit('sb/sh/sw',['lw x3,0(x4)'],0x345612ef)
emit('fence',['fence rw,rw','lw x3,0(x4)'],0x345612ef)
emit('x0',['addi zero,zero,7','addi x3,zero,0'],0)
# CSR operand variants use mscratch and independently known values.
asm += ['li x1,0x12','csrw mscratch,x1']
for op,code,value in [('csrrw','csrrw x3,mscratch,x0',0x12),('csrrwi','csrrwi x3,mscratch,3',0),
                      ('csrrs','csrrs x3,mscratch,x1',3),('csrrc','csrrc x3,mscratch,x1',0x13),
                      ('csrrsi','csrrsi x3,mscratch,4',1),('csrrci','csrrci x3,mscratch,1',5)]:
    emit(op,[code],value)
asm += ['csrr x1,mcycle','nop','csrr x3,mcycle','sub x3,x3,x1','sltu x3,zero,x3']
emit('mcycle',[],1)
for index,(cause,addr,code) in enumerate([(11,0,'ecall'),(3,0,'ebreak'),(2,0,'.word 0'),
                                        (4,0x80004401,'lw x3,1(x4)'),(6,0x80004402,'sw x3,2(x4)'),
                                        (5,0x20000000,'lw x3,0(x5)'),(7,0x20000000,'sw x3,0(x5)')]):
    asm += [f'li s1,{cause}',f'li s3,{addr}',f'la s2,fault{index}',f'la s7,resume{index}',
            'li x5,0x20000000',f'fault{index}:',code,f'resume{index}:']
    coverage[f'trap{cause}']=1
asm += ['li s1,0','li s3,0x80000202','la s2,misaligned_jump','la s7,resume_jump',
        'li x5,0x80000202','misaligned_jump:jalr zero,0(x5)','resume_jump:',
        'li s1,1','li s2,0x20000000','li s3,0x20000000','la s7,resume_fetch',
        'li x5,0x20000000','jalr zero,0(x5)','resume_fetch:']
coverage['trap0']=1;coverage['trap1']=1
# Establish pending while mie and global MIE are disabled; then enable in two steps.
for bit,name in ((3,'software'),(7,'timer'),(11,'external')):
    asm += ['csrw mie,zero','csrci mstatus,8',f'li s1,{0x80000000+bit}','li s5,0']
    if bit==3: asm += ['li x1,1','sw x1,0x30(s6)']
    elif bit==7: asm += ['lw x1,0x20(s6)','addi x1,x1,40','sw x1,0x34(s6)']
    else: asm += ['li x1,0xe1','sw x1,0x10(s6)']
    asm += [f'pending_{name}:','csrr x1,mip',f'li x2,{1<<bit}','and x1,x1,x2',
            f'beq x1,zero,pending_{name}','bne s5,zero,fail','csrw mie,x2',
            'nop','nop','nop','bne s5,zero,fail','csrsi mstatus,8',
            f'wait_{name}:','beq s5,zero,wait_'+name,'csrr x1,mstatus','andi x1,x1,8','li x2,8','bne x1,x2,fail']
    coverage[name+'_interrupt']=1
asm += ['li x3,12','bne s4,x3,fail','li x1,0x6b','sw x1,0x10(s6)','done:j done',
        'fail:li x1,0xee','sw x1,0x10(s6)','j fail',
        'handler:','csrr t0,mcause','bne t0,s1,fail','addi s4,s4,1','blt t0,zero,irq',
        'csrr t1,mepc','bne t1,s2,fail','csrr t2,mtval','bne t2,s3,fail',
        'csrw mepc,s7','mret',
        'irq:','csrr t0,mtval','bne t0,zero,fail','csrr t0,mstatus','andi t0,t0,0x88','li t1,0x80','bne t0,t1,fail',
        'csrw mie,zero','sw zero,0x30(s6)','li t0,-1','sw t0,0x34(s6)',
        'li t0,0xe2','sw t0,0x10(s6)','li s5,1','mret']
(out/'program.S').write_text('\n'.join(asm)+'\n',encoding='ascii')
(out/'expected.hex').write_text(''.join(f'{v:08x}\n' for v in results),encoding='ascii')
(out/'config.vh').write_text(f'`define RESULTS {len(results)}\n',encoding='ascii')
(out/'coverage.json').write_text(json.dumps(coverage,indent=2)+'\n')
print(f'GENERATED: {len(results)} independent result words; 9 traps and 3 masked/pending interrupt sources')

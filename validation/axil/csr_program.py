"""Spec-derived CSR access/boundary vectors; no DUT source or trace as oracle."""
import json
import sys
from pathlib import Path

out = Path(sys.argv[1]); suite = sys.argv[2]
out.mkdir(parents=True, exist_ok=True)
a = ['.section .text.start,"ax"', '.option norvc', '.global _start', '_start:j main',
     '.org 0x80', 'j handler', '.org 0x100', 'main:', 'li s11,0x80004800',
     'csrw mie,zero', 'csrci mstatus,8', 'li t0,0x10000000',
     'sw zero,0x30(t0)', 'li t1,-1', 'sw t1,0x34(t0)']
rules = []; cases = []
sentinel = 0x5a5aa5a5


def case(name, instruction, trap=False, rd=None, setup=(), observe=(), value=None, mask=0xffffffff):
    n = len(cases)+1
    # Handler uses only s4..s8 and t5; s1 is the instruction destination sentinel.
    a.extend(['li t0,0x80000080', 'csrw mtvec,t0', 'csrw mie,zero',
              'li t0,0x1800', 'csrw mstatus,t0', f'li s0,{n}', f'li s1,{sentinel}',
              'li s4,0', 'li s5,0', 'li s6,0', 'li s7,0', f'la s8,resume_{n}',
              *setup, f'fault_{n}:', instruction, f'resume_{n}:',
              'csrr s10,mstatus', 'li s2,0', *observe, 'jal ra,collect'])
    row = [dict(name='case', value=n), dict(name='trap_count', value=int(trap)),
           dict(name='mcause', value=2 if trap else 0),
           dict(name='mepc', symbol=f'fault_{n}') if trap else dict(name='mepc', value=0),
           dict(name='mtval', opcode=f'fault_{n}') if trap else dict(name='mtval', value=0),
           dict(name='rd', value=sentinel if trap else rd),
           dict(name='readback', value=value, mask=mask),
           dict(name='post_mret_mpp', value=0x1800, mask=0x1800)]
    rules.extend(row); cases.append(dict(id=n, name=name, instruction=instruction, trap=trap))


if suite == 'readonly':
    # Architectural read-only address space, unlike writable misa with fixed fields.
    for csr in (0xf11,0xf12,0xf13,0xf14,0xc00,0xc80,0xc02,0xc82):
        identity = csr >= 0xf00
        for op,operand,setup,write in (
            ('csrrw','zero',(),True), ('csrrwi','0',(),True),
            ('csrrs','zero',(),False), ('csrrc','zero',(),False),
            ('csrrsi','0',(),False), ('csrrci','0',(),False),
            ('csrrs','t0',('li t0,0',),True), ('csrrc','t0',('li t0,0',),True),
            ('csrrsi','1',(),True), ('csrrci','31',(),True),
            ('csrrw','t0',('li t0,-1',),True), ('csrrwi','31',(),True)):
            case(f'{csr:03x}_{op}_{operand}_{len(cases)}', f'{op} s1,0x{csr:x},{operand}',
                 write, 0 if identity else None, setup, (f'csrr s2,0x{csr:x}',), 0 if identity else None)
        for op,operand in (('csrrw','zero'),('csrrwi','0')):
            case(f'{csr:03x}_{op}_rdzero',f'{op} zero,0x{csr:x},{operand}',True,
                 observe=(f'csrr s2,0x{csr:x}',),value=0 if identity else None)
    # Deliberately unmapped CSR in this pinned configuration, not PMP/HPM aliases.
    for op,operand in (('csrrs','zero'),('csrrw','zero'),('csrrsi','0'),('csrrwi','0')):
        case(f'unmapped_7ff_{op}',f'{op} s1,0x7ff,{operand}',True)
elif suite == 'boundary':
    for value in (0,1,0x7fffffff,0x80000000,0xffffffff,0xaaaaaaaa,0x55555555):
        case(f'mscratch_{value:08x}','csrw mscratch,t0',setup=(f'li t0,{value}',),
             observe=('csrr s2,mscratch',),value=value)
        case(f'misa_fixed_{value:08x}','csrw misa,t0',setup=(f'li t0,{value}',),
             observe=('csrr s2,misa',),value=0x40001100)
    for bit in range(32):
        value = 1 << bit
        case(f'mie_bit{bit}','csrw mie,t0',setup=(f'li t0,{value}',),
             observe=('csrr s2,mie',),value=value & 0x888)
    case('mie_all','csrw mie,t0',setup=('li t0,-1',),observe=('csrr s2,mie',),value=0x888)
    for mpp in range(4):
        for flags in (0,8,128,136):
            value = (mpp << 11) | flags
            case(f'mstatus_mpp{mpp}_flags{flags}','csrw mstatus,t0',setup=(f'li t0,{value}',),
                 observe=('csrr s2,mstatus',),value=0x1800|flags,mask=0x1888)
    for base in (0x80000100,0x80003ffc):
        for low in range(4):
            case(f'mepc_{base|low:08x}','csrw mepc,t0',setup=(f'li t0,{base|low}',),
                 observe=('csrr s2,mepc',),value=base)
    for previous in (0,1):
        for mode in range(4):
            case(f'mtvec_previous{previous}_mode{mode}','csrw mtvec,t0',
                 setup=(f'li t0,{0x80000080|previous}','csrw mtvec,t0',f'li t0,{0x80000080|mode}'),
                 observe=('csrr s2,mtvec',),value=0x80000080)
            # Pinned configuration has xtvecModeGen=false: Direct-only is legal.
else:
    raise ValueError('unknown suite')

a.extend(['li t0,0x10000000','li t1,0x6b','sw t1,0x10(t0)','done:j done','collect:'])
for reg in ('s0','s4','s5','s6','s7','s1','s2','s10'):
    a.extend([f'sw {reg},0(s11)','addi s11,s11,4'])
a.extend(['ret','handler:','addi s4,s4,1','csrr s5,mcause','csrr s6,mepc','csrr s7,mtval',
          'csrw mepc,s8','mret'])
(out/'program.S').write_text('\n'.join(a)+'\n')
(out/'expected.json').write_text(json.dumps(rules,indent=2)+'\n')
(out/'cases.json').write_text(json.dumps(cases,indent=2)+'\n')
print(f'GENERATED {suite}: {len(cases)} cases, {len(rules)} records')

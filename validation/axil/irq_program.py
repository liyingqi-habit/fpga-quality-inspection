"""Directed concurrent pending tests. Oracle order is architectural MEI > MSI > MTI."""
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
asm = ['.section .text.start,"ax"', '.option norvc', '.global _start', '_start:j main',
       '.org 0x80','j handler','.org 0x100','main:',
       'li s11,0x80004800','li s0,0x10000000']
expected = []
cases = []


def record(instructions, value, name):
    asm.extend(instructions + ['sw t0,0(s11)','addi s11,s11,4'])
    expected.append(dict(value=value, name=name))


def constant(value, name):
    record([f'li t0,{value}'],value,name)


def csr(csr_name, mask, value, name):
    record([f'csrr t0,{csr_name}',f'li t1,{mask}','and t0,t0,t1'],value,name)


cid = 0
for sources in ((11,3),(11,7),(3,7),(11,3,7)):
    full = sum(1<<bit for bit in sources)
    for defer_high in (0,1):
        for gate in (0,1):
            cid += 1
            asm += ['csrci mstatus,8','csrw mie,zero','li s4,0',f'li s8,{full}',
                    'sw zero,0x30(s0)','li t0,-1','sw t0,0x34(s0)','li t0,0xe2','sw t0,0x10(s0)']
            constant(cid,'case')
            if 3 in sources: asm += ['li t0,1','sw t0,0x30(s0)']
            if 7 in sources: asm += ['sw zero,0x34(s0)']
            if 11 in sources: asm += ['li t0,0xe1','sw t0,0x10(s0)']
            asm += [f'pending_{cid}:','csrr t0,mip','and t0,t0,s8',f'bne t0,s8,pending_{cid}']
            csr('mip',full,full,'all_pending_before_enable')
            record(['addi t0,s4,0'],0,'masked_count')
            order = list(sources)
            stages = [order] if not defer_high else [order[1:],order[:1]]
            remaining = full
            handled = 0
            for stage, enabled_sources in enumerate(stages):
                enabled = sum(1<<bit for bit in enabled_sources)
                lo,hi = f'resume_{cid}_{stage}_lo',f'resume_{cid}_{stage}_hi'
                asm += ['csrci mstatus,8','csrw mie,zero',f'li s1,{enabled}',f'li s2,{handled+len(enabled_sources)}']
                if gate == 0: asm += ['csrw mie,s1']
                else: asm += ['csrsi mstatus,8']
                asm += ['nop']*8
                csr('mie',0x888,enabled if gate==0 else 0,'masked_mie')
                csr('mstatus',8,0 if gate==0 else 8,'masked_global_mie')
                record(['addi t0,s4,0'],handled,'no_masked_delivery')
                asm += [lo+':','csrsi mstatus,8' if gate==0 else 'csrw mie,s1',
                        f'wait_{cid}_{stage}:',f'bne s4,s2,wait_{cid}_{stage}',
                        'csrr s9,mstatus','csrci mstatus,8',hi+':']
                for bit in enabled_sources:
                    expected.extend([dict(value=0x80000000|bit,name='mcause'),
                                     dict(value=remaining,name='pending_on_entry'),
                                     dict(value=enabled,name='mie_on_entry'),
                                     dict(value=0x1880,name='trap_status'),
                                     dict(value=0,name='mtval'),
                                     dict(lo=lo,hi=hi,name='mepc')])
                    remaining &= ~(1<<bit)
                    expected.append(dict(value=remaining,name='pending_after_clear_one'))
                    handled += 1
                record(['andi t0,s9,8'],8,'mret_restored_mie')
                asm += ['csrw mie,zero']
                csr('mip',full,remaining,'pending_after_stage')
                record(['addi t0,s4,0'],handled,'handled_count')
            # Leave all three enabled briefly after all requests were acknowledged.
            asm += [f'li t0,{full}','csrw mie,t0','csrsi mstatus,8','li s10,40',
                    f'quiet_{cid}:','addi s10,s10,-1',f'bne s10,zero,quiet_{cid}',
                    'csrci mstatus,8','csrw mie,zero']
            record(['addi t0,s4,0'],len(sources),'no_duplicate_after_return')
            cases.append(dict(case=cid,sources=list(sources),defer_high=bool(defer_high),gate=gate,
                              service_order=[bit for group in stages for bit in group]))

asm += ['li t0,0x6b','sw t0,0x10(s0)','done:j done','handler:']
# This handler branches on the actual cause, not an expected sequence.
for csr_name, mask in [('mcause',None),('mip','s8'),('mie',None),('mstatus',0x1888),('mtval',None),('mepc',None)]:
    asm += [f'csrr t0,{csr_name}']
    if isinstance(mask,int): asm += [f'li t1,{mask}','and t0,t0,t1']
    elif mask: asm += [f'and t0,t0,{mask}']
    asm += ['sw t0,0(s11)','addi s11,s11,4']
asm += ['csrr t2,mcause','li t3,0x8000000b','beq t2,t3,clear_external',
        'li t3,0x80000003','beq t2,t3,clear_software','li t3,0x80000007','beq t2,t3,clear_timer','j fail',
        'clear_external:','li t0,0xe2','sw t0,0x10(s0)','li t2,0x800','j clear_wait',
        'clear_software:','sw zero,0x30(s0)','li t2,8','j clear_wait',
        'clear_timer:','li t0,-1','sw t0,0x34(s0)','li t2,0x80',
        'clear_wait:','csrr t0,mip','and t1,t0,t2','bne t1,zero,clear_wait',
        'and t0,t0,s8','sw t0,0(s11)','addi s11,s11,4','addi s4,s4,1','mret',
        'fail:li t0,0xee','sw t0,0x10(s0)','j fail']
(out/'program.S').write_text('\n'.join(asm)+'\n')
(out/'expected.json').write_text(json.dumps(expected,indent=2)+'\n')
(out/'cases.json').write_text(json.dumps(cases,indent=2)+'\n')
print(f'GENERATED: {len(cases)} concurrent IRQ cases, {len(expected)} records, 36 handlers per boot')

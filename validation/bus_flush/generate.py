"""Directed control flow with an independent architectural store oracle."""
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for kind in ('beq_taken', 'bne_taken', 'beq_not', 'bne_not', 'jal', 'jalr'):
    for gap in (0, 1, 3, 5):
        directory = out / f'{kind}-{gap}'
        directory.mkdir()
        asm = ['.section .text.start,"ax"', '.option norvc', '.global _start',
               '_start: j main', '.org 0x80', 'trap: sw zero,64(zero)', 'j trap',
               'main:', 'li t0,0x10000000', 'li t1,0x123', 'li t2,1', 'li t3,2',
               'la t4,target', 'sw t1,0(t0)'] + ['nop'] * gap
        branch = {'beq_taken': 'beq t2,t2,target', 'bne_taken': 'bne t2,t3,target',
                 'beq_not': 'beq t2,t3,target', 'bne_not': 'bne t2,t2,target',
                 'jal': 'jal x0,target', 'jalr': 'jalr x0,0(t4)'}[kind]
        asm += ['tested_branch:', '#ifdef FLUSH_MUTATION', 'bne t2,t2,target', '#else', branch, '#endif']
        taken = not kind.endswith('_not')
        asm += ['sw t1,64(t0)' if taken else 'sw t3,4(t0)',
                'target:', 'sw t2,8(t0)', 'done: j done']
        stores = [[0x10000000, 0x123]]
        if not taken:
            stores += [[0x10000004, 2]]
        stores += [[0x10000008, 1]]
        (directory / 'program.S').write_text('\n'.join(asm)+'\n', encoding='ascii')
        (directory / 'expected.json').write_text(json.dumps(dict(kind=kind, gap=gap, stores=stores))+'\n')
print('GENERATED: 6 control-flow types x 4 NOP gaps = 24 programs')

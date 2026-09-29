"""Generate directed RV32 cases and an integer oracle, without reading RTL results."""
import argparse
import json
from pathlib import Path

REGISTERS = (0, 1, 2, 7, 15, 16, 23, 27)


def generate(out, registers=REGISTERS, gaps=range(6), contexts=('plain', 'divide', 'flush')):
    out.mkdir(parents=True, exist_ok=True)
    code = ['.section .text.start,"ax"', '.option norvc', '.global _start',
            '_start: j start', '.org 0x80', 'trap:', 'li x28,0x10000010',
            'li x29,0xee', 'sw x29,0(x28)', 'halt: j halt',
            'start:', 'li x28,0x80004800', 'li x31,9']
    cases = []
    for context in contexts:
        for reg in registers:
            for gap in gaps:
                for role in ('rs1', 'rs2', 'both'):
                    case = len(cases)
                    value = ((case * 137 + 19) % 2048) - 1024
                    actual = value if reg else 0
                    result = {'rs1': actual + 3, 'rs2': 9 - actual, 'both': 2 * actual}[role] & 0xffffffff
                    code += [f'case_{case}:', f'li x{reg},{value}']
                    if context in ('divide', 'divide_flush'):
                        code += ['div x30,x31,x31']
                    if context in ('flush', 'divide_flush'):
                        code += [f'beq x31,x31,skip_{case}',
                                 f'addi x{reg},zero,777', 'sw x31,0(zero)', f'skip_{case}:']
                    code += ['nop'] * gap
                    code += [{'rs1': f'addi x29,x{reg},3',
                              'rs2': f'sub x29,x31,x{reg}',
                              'both': f'add x29,x{reg},x{reg}'}[role],
                             'sw x29,0(x28)', 'addi x28,x28,4']
                    cases.append(dict(case=case, context=context, register=reg,
                                      nop_gap=gap, role=role, producer_value=value, expected=result))
    code += ['li x28,0x10000010', 'li x29,0x6b', 'sw x29,0(x28)', 'done: j done']
    if len(cases) > 512:
        raise ValueError('Result region supports at most 512 cases; split larger matrices into batches')
    (out / 'matrix.S').write_text('\n'.join(code)+'\n', encoding='ascii')
    (out / 'matrix_expected.hex').write_text(''.join(f'{c["expected"]:08x}\n' for c in cases), encoding='ascii')
    (out / 'cases.json').write_text(json.dumps(cases, indent=2)+'\n', encoding='ascii')
    context_names = ('plain', 'divide', 'flush', 'divide_flush')
    (out / 'matrix_context.hex').write_text(''.join(f'{context_names.index(c["context"]):x}\n' for c in cases), encoding='ascii')
    div_count = sum(c['context'] in ('divide', 'divide_flush') for c in cases)
    flush_count = sum(c['context'] in ('flush', 'divide_flush') for c in cases)
    enabled = sum(1 << context_names.index(c) for c in contexts)
    (out / 'matrix_config.vh').write_text(
        f'`define MATRIX_CASES {len(cases)}\n`define MATRIX_DIVIDES {div_count}\n'
        f'`define MATRIX_FLUSHES {flush_count}\n`define MATRIX_CONTEXTS 4\'h{enabled:x}\n', encoding='ascii')
    print(f'GENERATED: {len(registers)} registers x {len(gaps)} NOP gaps x 3 operand roles x {len(contexts)} contexts = {len(cases)} cases')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--registers', default=','.join(map(str, REGISTERS)))
    parser.add_argument('--gaps', default='0,1,2,3,4,5')
    parser.add_argument('--contexts', default='plain,divide,flush')
    args = parser.parse_args()
    registers = tuple(map(int, args.registers.split(',')))
    gaps = tuple(map(int, args.gaps.split(',')))
    contexts = tuple(args.contexts.split(','))
    if len(set(registers)) != len(registers) or not all(0 <= r <= 27 for r in registers):
        parser.error('Unique registers x0..x27 only; x28..x31 are reserved')
    if len(set(gaps)) != len(gaps) or not all(0 <= g <= 32 for g in gaps):
        parser.error('Unique NOP gaps 0..32 only')
    if len(set(contexts)) != len(contexts) or not set(contexts) <= {'plain', 'divide', 'flush', 'divide_flush'}:
        parser.error('Unique contexts: plain,divide,flush,divide_flush')
    generate(args.output, registers, gaps, contexts)

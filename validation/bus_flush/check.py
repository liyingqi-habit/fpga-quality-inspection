"""Independent cycle-trace checker. Does not trust the SV PASS line."""
import csv
import copy
import json
import sys
from pathlib import Path


def check(rows, expected, schedule=None, delay=None):
    stats = dict(cmd_stalls=0, aw_stalls=0, w_stalls=0, b_stalls=0, overlap=0)
    for epoch in (1, 2):
        selected = [r for r in rows if r['epoch'] == epoch]
        assert selected, 'missing boot'
        issued, effects, retired = [], [], []
        pending = None
        prev = None
        for r in selected:
            assert all(r[k] in (0, 1) for k in ('bv', 'br', 'rv', 'retire', 'overlap')), 'unknown control'
            for valid, ready, fields, key in (
                ('cv', 'ready', ('write', 'ca', 'cd', 'cm', 'cp'), 'cmd_stalls'),
                ('av', 'ar', ('aa',), 'aw_stalls'),
                ('wv', 'wr', ('wd', 'ws'), 'w_stalls')):
                assert r[valid] in (0, 1) and r[ready] in (0, 1), 'unknown control'
                if r[valid]:
                    assert all(r[f] is not None for f in fields), 'unknown payload'
                if prev and prev[valid] and not prev[ready]:
                    assert r[valid] and all(r[f] == prev[f] for f in fields), f'{valid} unstable'
                stats[key] += int(r[valid] == 1 and r[ready] == 0)
            stats['b_stalls'] += int(r['bv'] == 1 and r['br'] == 0)
            stats['overlap'] += r['overlap']
            if prev and prev['bv'] and not prev['br']:
                assert r['bv'] == 1, 'B withdrawn'
            if r['cv']:
                assert r['ca'] in (0x10000000, 0x10000004, 0x10000008), 'wrong path valid'
            if r['cv'] and r['ready']:
                assert pending is None, 'multiple outstanding'
                assert r['write'] == 1 and r['cm'] == 15, 'non-word write'
                pending = dict(addr=r['ca'], data=r['cd'], pc=r['cp'], aw=False, w=False, b=False, rsp=False)
                issued.append([r['ca'], r['cd']])
            if r['av'] and r['ar']:
                assert pending and not pending['aw'] and r['aa'] == pending['addr'], 'AW mismatch'
                pending['aw'] = True
                pending['aw_cycle'] = r['cycle']
            if r['wv'] and r['wr']:
                assert pending and not pending['w'] and r['wd'] == pending['data'] and r['ws'] == 15, 'W mismatch'
                pending['w'] = True
                pending['w_cycle'] = r['cycle']
            if r['bv'] and (not prev or not prev['bv']):
                assert pending and pending['aw'] and pending['w'], 'early B valid'
                if delay is not None:
                    assert r['cycle'] - max(pending['aw_cycle'], pending['w_cycle']) == delay+1, 'response delay mismatch'
            if r['bv'] and r['br']:
                assert pending and pending['aw'] and pending['w'] and not pending['b'], 'B before AW/W or duplicate'
                pending['b'] = True
                if schedule is not None:
                    ac, wc = pending['aw_cycle'], pending['w_cycle']
                    assert (ac < wc if schedule == 0 else wc < ac if schedule == 1 else ac == wc), 'AW/W order mismatch'
                effects.append([pending['addr'], pending['data']])
            if r['rv']:
                assert pending and pending['b'] and not pending['rsp'], 'response before B or duplicate'
                pending['rsp'] = True
            if r['retire']:
                assert pending and pending['rsp'] and r['rp'] == pending['pc'], 'retire before response or wrong PC'
                retired.append(pending['pc'])
                pending = None
            prev = r
        assert pending is None, 'unfinished transaction'
        assert issued == expected == effects, 'architectural stores mismatch'
        assert len(retired) == len(expected), 'retirement count'
    for key in ('aw_stalls', 'w_stalls', 'b_stalls'):
        assert stats[key] > 0, f'missing {key}'
    return stats


def load(path):
    with path.open() as stream:
        return [{k: int(v) if v.isdigit() else None for k, v in row.items()} for row in csv.DictReader(stream)]


def negative_controls(rows, expected):
    for mutation, reason in (('aw', 'av unstable'), ('retire', 'retire before response or wrong PC'),
                             ('store', 'architectural stores mismatch')):
        changed = copy.deepcopy(rows)
        oracle = copy.deepcopy(expected)
        if mutation == 'aw':
            index = next(i for i, r in enumerate(changed[:-1]) if r['av'] and not r['ar'])
            changed[index+1]['aa'] ^= 4
        elif mutation == 'retire':
            row = next(r for r in changed if r['cv'] and r['ready'])
            row['retire'], row['rp'] = 1, row['cp']
        else:
            oracle[0][1] ^= 1
        try:
            check(changed, oracle)
        except AssertionError as error:
            assert str(error) == reason, (mutation, str(error))
        else:
            raise AssertionError(f'negative escaped: {mutation}')


if __name__ == '__main__':
    root = Path(sys.argv[1])
    totals = {}
    count = 0
    for manifest in sorted(root.glob('*/expected.json')):
        spec = json.loads(manifest.read_text())
        for trace in sorted(manifest.parent.glob('s*/trace.csv')):
            schedule, delay, admit = map(int, trace.parent.name[1:].split('-'))
            stats = check(load(trace), spec['stores'], schedule, delay)
            if spec['gap'] == 0 and not spec['kind'].endswith('_not'):
                assert stats['overlap'] > 0, 'tested branch never overlaps outstanding write'
            if admit:
                assert stats['cmd_stalls'] >= admit * len(spec['stores']) * 2, 'missing admission backpressure'
            for key, value in stats.items():
                totals[key] = totals.get(key, 0) + value
            count += 1
    assert count == 432, f'missing configurations: {count}'
    assert totals['overlap'] > 0, 'no actual branch/bus overlap'
    sample = root / 'beq_taken-0'
    negative_controls(load(sample / 's0-31-5/trace.csv'), json.loads((sample / 'expected.json').read_text())['stores'])
    print(json.dumps(dict(configurations=count, boots=count*2, counters=totals, checker_negatives_rejected=3), indent=2))

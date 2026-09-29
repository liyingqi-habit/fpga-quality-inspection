"""Directed synchronous exception / IRQ oracle; expected causes are not RTL-derived."""
import copy
import itertools
import json
import sys
from pathlib import Path
from check_competition import rows, require

CAUSES = (11, 3, 2, 4, 6, 0, 1)
VALUES = (0, 0, 0, 0x10000001, 0x10000002, 0x80000202, 0x20000000)


def verify(records, trace, symbols, kind, source, masked, phase):
    require(bool(records) and records[0]['data'] == CAUSES[kind], 'FIRST_CAUSE')
    count = 12 if masked else 21
    require(len(records) == count * 2, 'RECORD_COUNT')
    fault_pc = 0x20000000 if kind == 6 else symbols['fault_pc']
    for boot in (1, 2):
        rec = [r for r in records if r['boot'] == boot]
        tr = [r for r in trace if r['boot'] == boot]
        require(len(rec) == count and bool(tr), 'BOOT_COUNT')
        require(all(a['cycle'] < b['cycle'] for a, b in zip(tr, tr[1:])), 'TRACE_ORDER')
        require([r['addr'] for r in rec] == list(range(0x80004000, 0x80004000 + 4 * count, 4)), 'RECORD_ADDRESS')
        data = [r['data'] for r in rec]
        for h in range(1 if masked else 2):
            v = data[h * 9:h * 9 + 9]
            require(v[0] == (CAUSES[kind] if h == 0 else 0x80000000 | source), 'CAUSE_ORDER')
            if h == 0:
                require(v[1] == fault_pc, 'FAULT_PC')
            else:
                require(v[1] % 4 == 0 and symbols['resume'] <= v[1] < symbols['resume_end'], 'IRQ_PC')
            require(v[2] == (VALUES[kind] if h == 0 else 0), 'MTVAL')
            require(v[3] == 0x1880, 'MSTATUS')
            require(v[4] == 1 << source, 'PENDING')
            require(v[5:8] == [0xdeadbeef, 0, 0x13579bdf], 'REGISTERS')
            require(v[8] == h, 'HANDLER_ORDER')
        require(data[-3:] == [1 if masked else 3, 0, 0xdeadbeef], 'RETURN_STATE')
        retired = [r['retire_pc'] for r in tr if r['retire']]
        require(fault_pc not in retired, 'FAULT_RETIRED')
        require(symbols['younger_pc'] not in retired, 'YOUNGER_RETIRED')
        require(not any(r['cv'] and r['ready'] and 0x10000000 <= r['addr'] <= 0x10000003 for r in tr), 'FAULT_DATA_COMMAND')
        require(all(not r['commit'] or r['commit_addr'] in (0x10000030, 0x10000024) or
                    0x80004000 <= r['commit_addr'] < 0x80004000 + 4 * count for r in tr), 'UNEXPECTED_COMMIT')
        require(all(r['memory'] == 0x11223344 for r in tr), 'MEMORY_EFFECT')
        starts = [r for r in tr if r['retire'] and r['retire_pc'] == symbols['handler']]
        require(len(starts) == (1 if masked else 2), 'HANDLER_COUNT')
        fetch = next((r for r in tr if r['iv'] and r['ip'] == fault_pc), None)
        require(fetch is not None, 'FAULT_FETCH')
        asserted = next((r['cycle'] for r in tr if r['irq']), None)
        require(asserted is not None, 'IRQ_MISSING')
        if phase < 2:
            require(asserted == fetch['cycle'] + phase + 1, 'FETCH_WINDOW')
        else:
            require(asserted > starts[0]['cycle'], 'HANDLER_WINDOW')
        delivered = [r for r in tr if r['ir'] and r['response_pc'] == fault_pc]
        require(bool(delivered) and all(r['ifault'] == int(kind == 6) for r in delivered), 'FETCH_RESPONSE')
        clears = [r for r in tr if r['commit'] and r['commit_addr'] == 0x10000030]
        require(len(clears) == (0 if masked else 1), 'IRQ_ACK')
        done = [r for r in tr if r['commit'] and r['commit_addr'] == 0x10000024]
        require(len(done) == 1 and done[0]['commit_data'] == (1 if masked else 3), 'COMPLETION')


def main():
    out = Path(sys.argv[1])
    samples = {}
    checked = 0
    for k, s, m, p in itertools.product(range(7), (3, 7, 11), (0, 1), (0, 1, 2)):
        fw = out / f'fw_k{k}_s{s}_m{m}'
        symbols = {v[2]: int(v[0], 16) for line in (fw / 'symbols.txt').read_text().splitlines()
                   if len(v := line.split()) == 3}
        folder = out / f'k{k}_s{s}_m{m}_p{p}'
        rec, tr = rows(folder / 'records.csv'), rows(folder / 'trace.csv')
        try:
            verify(rec, tr, symbols, k, s, m, p)
        except ValueError as error:
            raise ValueError(f'{folder.name}: {error}') from error
        checked += 1
        if s == 3 and m == 0 and p == 0:
            samples[k] = rec, tr, symbols, k, s, m, p
    rejected = 0
    for args in samples.values():
        rec, tr, symbols, k, s, m, p = args
        for index, reason in [(0, 'FIRST_CAUSE'), (1, 'FAULT_PC'), (2, 'MTVAL'),
                              (3, 'MSTATUS'), (4, 'PENDING'), (5, 'REGISTERS'),
                              (6, 'REGISTERS'), (7, 'REGISTERS'), (8, 'HANDLER_ORDER'),
                              (9, 'CAUSE_ORDER'), (10, 'IRQ_PC'), (-3, 'RETURN_STATE')]:
            bad = copy.deepcopy(rec)
            bad[index]['data'] ^= 1
            try:
                verify(bad, tr, symbols, k, s, m, p)
            except ValueError as error:
                require(str(error) == reason, 'NEGATIVE_REASON:' + str(error))
                rejected += 1
            else:
                raise ValueError('NEGATIVE_ESCAPED:' + reason)
        controls = []
        for pc, reason in [(0x20000000 if k == 6 else symbols['fault_pc'], 'FAULT_RETIRED'),
                           (symbols['younger_pc'], 'YOUNGER_RETIRED')]:
            bad = copy.deepcopy(tr)
            next(r for r in bad if r['retire'])['retire_pc'] = pc
            controls.append((bad, reason))
        bad = copy.deepcopy(tr)
        bad[0]['memory'] = 0
        controls.append((bad, 'MEMORY_EFFECT'))
        bad = copy.deepcopy(tr)
        for r in bad:
            r['irq'] = 0
        controls.append((bad, 'IRQ_MISSING'))
        bad = copy.deepcopy(tr)
        next(r for r in bad if r['commit'] and r['commit_addr'] == 0x10000030)['commit'] = 0
        controls.append((bad, 'IRQ_ACK'))
        bad = copy.deepcopy(tr)
        next(r for r in bad if r['commit'] and r['commit_addr'] == 0x10000024)['commit_data'] = 0
        controls.append((bad, 'COMPLETION'))
        bad = copy.deepcopy(tr)
        next(r for r in bad if r['ir'] and r['response_pc'] ==
             (0x20000000 if k == 6 else symbols['fault_pc']))['ifault'] ^= 1
        controls.append((bad, 'FETCH_RESPONSE'))
        bad = copy.deepcopy(tr)
        bad[0].update(cv=1, ready=1, addr=0x10000001)
        controls.append((bad, 'FAULT_DATA_COMMAND'))
        for bad, reason in controls:
            try:
                verify(rec, bad, symbols, k, s, m, p)
            except ValueError as error:
                require(str(error) == reason, 'TRACE_NEGATIVE_REASON:' + str(error))
                rejected += 1
            else:
                raise ValueError('TRACE_NEGATIVE_ESCAPED:' + reason)
    bad = rows(out / 'negative_fetch' / 'records.csv')
    require(bool(bad) and bad[0]['data'] == 0x80000003, 'FETCH_NEGATIVE_NOT_IRQ_FIRST')
    try:
        verify(bad, [], {}, 6, 3, 0, 0)
    except ValueError as error:
        require(str(error) == 'FIRST_CAUSE', 'FETCH_NEGATIVE_REASON')
    else:
        raise ValueError('FETCH_NEGATIVE_ESCAPED')
    report = dict(status='PASS', configurations=checked, boots=checked * 2,
                  handler_entries=378, checker_mutations_rejected=rejected,
                  actual_fetch_error_suppression_rejected=1,
                  scope='7 synchronous causes vs individual machine IRQ; directed fetch windows, not exhaustive arbitration')
    (out / 'audit.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()

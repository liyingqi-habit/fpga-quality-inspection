"""Independent exception/IRQ ordering oracle from firmware CSR records and bus events."""
import argparse
import copy
import csv
import itertools
import json
from pathlib import Path


def rows(path):
    with path.open() as stream:
        return [{k: int(v) for k, v in row.items()} for row in csv.DictReader(stream)]


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def verify(records, trace, symbols, write, source, masked, phase):
    # Check first cause before completeness, so error-suppression cannot pass as timeout.
    require(bool(records), 'NO_RECORDS')
    require(records[0]['data'] == (7 if write else 5), 'FIRST_CAUSE')
    count = 12 if masked else 21
    require(len(records) == 2 * count, 'RECORD_COUNT')
    require(all(r['boot'] in (1, 2) for r in trace), 'TRACE_BOOT')
    for boot in (1, 2):
        rec = [r for r in records if r['boot'] == boot]
        tr = [r for r in trace if r['boot'] == boot]
        require(len(rec) == count and bool(tr), 'BOOT_COUNT')
        require(all(a['cycle'] < b['cycle'] for a, b in zip(tr, tr[1:])), 'TRACE_ORDER')
        require([r['addr'] for r in rec] == list(range(0x80004000, 0x80004000 + count * 4, 4)), 'RECORD_ADDRESS')
        data = [r['data'] for r in rec]
        for h in range(1 if masked else 2):
            v = data[h * 9:h * 9 + 9]
            require(v[0] == ((7 if write else 5) if h == 0 else 0x80000000 | source), 'CAUSE_ORDER')
            if h == 0:
                require(v[1] == symbols['fault_pc'], 'FAULT_PC')
            else:
                require(v[1] % 4 == 0 and symbols['resume'] <= v[1] < symbols['resume_end'], 'IRQ_PC')
            require(v[2] == (0x10000000 if h == 0 else 0), 'MTVAL')
            require(v[3] == 0x1880, 'MSTATUS')
            require(v[4] == 1 << source, 'PENDING_RETAINED')
            require(v[5] == 0xdeadbeef, 'DESTINATION_PRESERVED')
            require(v[6] == 0, 'YOUNGER_REGISTER')
            require(v[7] == 0x13579bdf, 'OLDER_REGISTER')
            require(v[8] == h, 'HANDLER_ORDER')
        require(data[-3:] == [1 if masked else 3, 0, 0xdeadbeef], 'RETURN_STATE')
        fault_commands = [r for r in tr if r['cv'] and r['ready'] and r['addr'] == 0x10000000]
        require(len(fault_commands) == 1 and fault_commands[0]['write'] == write and
                fault_commands[0]['cmd_pc'] == symbols['fault_pc'], 'FAULT_COMMAND')
        errors = [r for r in tr if r['rv'] and r['error']]
        require(len(errors) == 1, 'ERROR_RESPONSE_COUNT')
        retired = [r['retire_pc'] for r in tr if r['retire']]
        require(symbols['fault_pc'] not in retired, 'FAULT_RETIRED')
        require(symbols['younger_pc'] not in retired, 'YOUNGER_RETIRED')
        require(all(r['memory'] == 0x11223344 for r in tr), 'ERROR_MEMORY_EFFECT')
        starts = [r for r in tr if r['retire'] and r['retire_pc'] == symbols['handler']]
        require(len(starts) == (1 if masked else 2), 'HANDLER_COUNT')
        asserted = next((r['cycle'] for r in tr if r['irq']), None)
        require(asserted is not None, 'IRQ_NOT_INJECTED')
        err_cycle = errors[0]['cycle']
        if phase == 0:
            require(fault_commands[0]['cycle'] < asserted < err_cycle, 'EARLY_WINDOW')
        elif phase == 1:
            require(asserted == err_cycle, 'SAME_RESPONSE_WINDOW')
        else:
            require(asserted > starts[0]['cycle'], 'HANDLER_WINDOW')
        clears = [r for r in tr if r['commit'] and r['commit_addr'] == 0x10000030]
        require(len(clears) == (0 if masked else 1), 'IRQ_ACK_COUNT')
        done = [r for r in tr if r['commit'] and r['commit_addr'] == 0x10000024]
        require(len(done) == 1 and done[0]['commit_data'] == (1 if masked else 3), 'COMPLETION')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    outputs = args.output
    checked = 0
    sample = None
    for w, s, m, p, c, d in itertools.product((0, 1), (3, 7, 11), (0, 1), (0, 1, 2), (2, 3), (3, 17)):
        fw = outputs / f'fw_w{w}_s{s}_m{m}'
        symbols = {v[2]: int(v[0], 16) for line in (fw / 'symbols.txt').read_text().splitlines()
                   if len(v := line.split()) == 3}
        folder = outputs / f'w{w}_s{s}_m{m}_p{p}_c{c}_d{d}'
        rec, tr = rows(folder / 'records.csv'), rows(folder / 'trace.csv')
        verify(rec, tr, symbols, w, s, m, p)
        checked += 1
        if sample is None:
            sample = rec, tr, symbols, w, s, m, p
    rec, tr, symbols, w, s, m, p = sample
    mutations = [(0, 0, 'FIRST_CAUSE'), (1, 0, 'FAULT_PC'), (2, 0, 'MTVAL'),
                 (3, 0, 'MSTATUS'), (4, 0, 'PENDING_RETAINED'), (5, 0, 'DESTINATION_PRESERVED'),
                 (6, 1, 'YOUNGER_REGISTER'), (7, 0, 'OLDER_REGISTER'), (8, 1, 'HANDLER_ORDER'),
                 (9, 0, 'CAUSE_ORDER'), (10, 0, 'IRQ_PC'), (-3, 0, 'RETURN_STATE')]
    for index, value, reason in mutations:
        bad = copy.deepcopy(rec)
        bad[index]['data'] = value
        try:
            verify(bad, tr, symbols, w, s, m, p)
        except ValueError as error:
            require(str(error) == reason, 'WRONG_NEGATIVE_REASON:' + str(error))
        else:
            raise ValueError('NEGATIVE_ESCAPED:' + reason)
    trace_controls = []
    for field, value, reason in [('retire_pc', symbols['fault_pc'], 'FAULT_RETIRED'),
                                ('retire_pc', symbols['younger_pc'], 'YOUNGER_RETIRED'),
                                ('memory', 0, 'ERROR_MEMORY_EFFECT')]:
        bad = copy.deepcopy(tr)
        idx = next(i for i, r in enumerate(bad) if r['retire'])
        bad[idx][field] = value
        trace_controls.append((bad, reason))
    bad = copy.deepcopy(tr)
    next(r for r in bad if r['rv'] and r['error'])['error'] = 0
    trace_controls.append((bad, 'ERROR_RESPONSE_COUNT'))
    bad = copy.deepcopy(tr)
    next(r for r in bad if r['cv'] and r['ready'] and r['addr'] == 0x10000000)['ready'] = 0
    trace_controls.append((bad, 'FAULT_COMMAND'))
    bad = copy.deepcopy(tr)
    for r in bad:
        r['irq'] = 0
    trace_controls.append((bad, 'IRQ_NOT_INJECTED'))
    bad = copy.deepcopy(tr)
    next(r for r in bad if r['commit'] and r['commit_addr'] == 0x10000030)['commit'] = 0
    trace_controls.append((bad, 'IRQ_ACK_COUNT'))
    bad = copy.deepcopy(tr)
    next(r for r in bad if r['commit'] and r['commit_addr'] == 0x10000024)['commit_data'] = 0
    trace_controls.append((bad, 'COMPLETION'))
    for bad, reason in trace_controls:
        try:
            verify(rec, bad, symbols, w, s, m, p)
        except ValueError as error:
            require(str(error) == reason, 'WRONG_TRACE_NEGATIVE:' + str(error))
        else:
            raise ValueError('TRACE_NEGATIVE_ESCAPED:' + reason)
    for w in (0, 1):
        bad = rows(outputs / f'negative_w{w}' / 'records.csv')
        require(bool(bad) and bad[0]['data'] == 0x80000003, 'RTL_NEGATIVE_NOT_IRQ_FIRST')
        try:
            verify(bad, [], {}, w, 3, 0, 0)
        except ValueError as error:
            require(str(error) == 'FIRST_CAUSE', 'RTL_NEGATIVE_REASON')
        else:
            raise ValueError('RTL_NEGATIVE_ESCAPED')
    result = dict(status='PASS',configurations=checked,boots=checked*2,
                  checker_mutations_rejected=len(mutations)+len(trace_controls),rtl_error_suppression_rejected=2,
                  scope='LW/SW access errors vs machine IRQ; not all synchronous exceptions or nested IRQ')
    (outputs / 'audit.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    main()

"""Independent real-pipeline trace checks, with fixture-specific expected program."""
import copy
import csv
from pathlib import Path
import sys

DELAYS = [0, 7, 31, 9, 3, 0, 8, 8, 15, 2, 0, 0]
ERRORS = {3: 2, 4: 3, 9: 2}
RESET_CASES = {5, 6, 7, 8, 9, 11}


def need(ok, reason):
    if not ok:
        raise ValueError(reason)


def read(path):
    with open(path) as stream:
        return [{k: int(v) for k, v in row.items()} for row in csv.DictReader(stream)]


def check(rows, ident):
    slot = None
    primary = None
    aw_hold = w_hold = b_hold = None
    reset_at = None
    young_transaction = None
    young_retires = 0
    issues = retires = traps = young = responses = stalls = 0
    last = -1
    for r in rows:
        c = r['cycle']
        need(c > last and r['case'] == ident, 'TRACE_ORDER')
        last = c
        if aw_hold is not None:
            need(r['av'] and r['addr'] == aw_hold, 'AW_STABILITY')
        if w_hold is not None:
            need(r['wv'] and (r['data'], r['strb']) == w_hold, 'W_STABILITY')
        if b_hold is not None:
            need(r['bv'] and r['resp'] == b_hold, 'B_STABILITY')
        aw_hold = r['addr'] if r['av'] and not r['ar'] else None
        w_hold = (r['data'], r['strb']) if r['wv'] and not r['wr'] else None
        b_hold = r['resp'] if r['bv'] and not r['br'] else None
        if r['reset']:
            need(reset_at is None and ident in RESET_CASES, 'RESET_COVERAGE')
            reset_at = c
            need(r['cpu_reset'], 'RESET_NOT_ASSERTED')
            if ident == 5:
                need(slot is None and issues == 0, 'RESET_PHASE')
            else:
                need(slot is not None, 'RESET_WITHOUT_SLOT')
                phase = (slot['aw'] is not None, slot['w'] is not None)
                need(phase == {6: (True, False), 7: (False, True),
                               8: (True, True), 9: (True, True), 11: (True, True)}[ident], 'RESET_PHASE')
                need(bool(r['bv'] and r['br']) == (ident == 9), 'RESET_B_EDGE')
                slot['cancel'] = True
        if slot and slot['cancel']:
            need(r['cpu_reset'] and r['busy'], 'QUARANTINE_LOST')
        need(r['epoch'] == (1 if reset_at is not None else 0), 'EPOCH_CONTEXT')
        if r['retire']:
            need(r['retire_pc'] in {0x80000010, 0x80000014}, 'UNEXPECTED_STORE_RETIRE')
            if r['retire_pc'] == 0x80000014:
                need(young_transaction is not None and young_transaction['b'] and
                     young_transaction['resp'] == 0 and not young_transaction['cancel'], 'YOUNG_RETIRE_EARLY')
                young_retires += 1
        if r['retire'] and r['retire_pc'] == 0x80000010:
            need(primary is not None and not primary['cancel'], 'STALE_RETIRE')
            need(primary['b'] and primary['resp'] == 0, 'RETIRE_BEFORE_SUCCESS')
            need(not primary['outcome'], 'DOUBLE_RETIRE')
            primary['outcome'] = True
            retires += 1
        if r['trap']:
            need(primary is not None and not primary['cancel'], 'STALE_TRAP')
            need(primary['b'] and primary['resp'] != 0 and not primary['outcome'], 'TRAP_WITHOUT_ERROR')
            need((r['trap_pc'], r['trap_addr'], r['cause']) ==
                 (0x80000010, 0x10000000 + 4*ident, 7), 'TRAP_CONTEXT')
            primary['outcome'] = True
            traps += 1
        if r['young']:
            need(primary is not None and primary['outcome'] and primary['resp'] == 0
                 and not primary['cancel'], 'YOUNG_SIDE_EFFECT')
            young += 1
        if r['issue'] or r['young']:
            need(slot is None and not r['cpu_reset'], 'SLOT_REUSE')
            need(r['pc'] == (0x80000010 if r['issue'] else 0x80000014), 'ISSUE_PC')
            slot = dict(aw=None, w=None, b=False, resp=None, cancel=False, outcome=False,
                        young=bool(r['young']), epoch=r['epoch'])
            if r['issue']:
                issues += 1
                primary = slot
            else:
                young_transaction = slot
        if r['av'] and r['ar']:
            need(slot is not None and slot['aw'] is None, 'ORPHAN_OR_DOUBLE_AW')
            need(r['addr'] == 0x10000000 + 4*ident + (4 if slot['young'] else 0), 'AW_CONTEXT')
            slot['aw'] = c
        if r['wv'] and r['wr']:
            need(slot is not None and slot['w'] is None, 'ORPHAN_OR_DOUBLE_W')
            need((r['data'], r['strb']) == (0xaabbcc00+ident, 15), 'W_CONTEXT')
            slot['w'] = c
        if r['bv']:
            need(slot is not None and slot['aw'] is not None and slot['w'] is not None, 'B_WITHOUT_REQUEST')
            need(ident != 11, 'UNEXPECTED_B')
            need(c > max(slot['aw'], slot['w']) + DELAYS[ident], 'EARLY_B')
            expected = ERRORS.get(ident, 0) if slot['epoch'] == 0 else 0
            need(r['resp'] == expected, 'B_CODE')
            if not r['br']:
                stalls += 1
            else:
                slot['b'] = True
                slot['resp'] = r['resp']
                if responses == 0:
                    if ident in {0, 3, 6, 9, 10}: need(slot['aw'] < slot['w'], 'AW_FIRST')
                    if ident in {1, 4, 7}: need(slot['w'] < slot['aw'], 'W_FIRST')
                    if ident in {2, 8}: need(slot['w'] == slot['aw'], 'SIMULTANEOUS')
                slot = None
                responses += 1
        if ident in {3, 4}:
            need(not (r['cmd_valid'] and r['cmd_addr'] == 0x10000004+4*ident), 'YOUNG_ERROR_REQUEST')
    need((reset_at is not None) == (ident in RESET_CASES), 'MISSING_RESET')
    if ident == 11:
        need(slot is not None and slot['cancel'] and not slot['b'] and last-reset_at >= 30,
             'QUARANTINE_WINDOW')
        need((issues, retires, traps, young, responses) == (1, 0, 0, 0, 0), 'NEVER_COUNTS')
    else:
        need(slot is None and stalls >= 3, 'UNFINISHED_OR_NO_BACKPRESSURE')
        need(issues == (2 if ident in {6, 7, 8, 9} else 1), 'ISSUE_COUNTS')
        need((retires, traps, young) == ((0, 1, 0) if ident in {3, 4} else (1, 0, 1)), 'OUTCOME_COUNTS')
        need(young_retires == (0 if ident in {3, 4} else 1), 'YOUNG_RETIRE_COUNTS')
        need(responses == (1 if ident in {3, 4} else 3 if ident in {6, 7, 8, 9} else 2), 'RESPONSE_COUNTS')
    return issues, retires, traps, young, responses


def main(root):
    traces = [read(root / f'case{i}/trace.csv') for i in range(12)]
    for i, rows in enumerate(traces):
        print('CHECK_REAL_PASS', i, check(rows, i))
    # Same error categories as the synthetic fixture, checked on real observations.
    mutations = [
        (0, lambda r: r['issue'], {'retire': 1, 'retire_pc': 0x80000010}, 'STALE_RETIRE'),
        (3, lambda r: r['trap'], {'trap': 0, 'retire': 1, 'retire_pc': 0x80000010}, 'RETIRE_BEFORE_SUCCESS'),
        (3, lambda r: r['trap'], {'trap_pc': 0}, 'TRAP_CONTEXT'),
        (3, lambda r: r['trap'], {'trap_addr': 0}, 'TRAP_CONTEXT'),
        (3, lambda r: r['trap'], {'cause': 5}, 'TRAP_CONTEXT'),
        (3, lambda r: r['wv'], {'young': 1}, 'YOUNG_SIDE_EFFECT'),
        (8, lambda r: r['cancelled'], {'busy': 0}, 'QUARANTINE_LOST'),
        (9, lambda r: r['reset'], {'retire': 1, 'retire_pc': 0x80000010}, 'STALE_RETIRE'),
        (2, lambda r: r['av'] and r['ar'], {'addr': 0}, 'AW_STABILITY'),
        (2, lambda r: r['wv'] and r['wr'], {'data': 0}, 'W_STABILITY'),
        (0, lambda r: r['bv'] and r['br'], {'resp': 2}, 'B_STABILITY'),
        (11, lambda r: r['cancelled'], {'issue': 1}, 'SLOT_REUSE'),
    ]
    for i, select, change, reason in mutations:
        altered = copy.deepcopy(traces[i])
        next(r for r in altered if select(r)).update(change)
        try:
            check(altered, i)
        except ValueError as err:
            need(str(err) == reason, f'MUTATION_WRONG_REASON {reason}: {err}')
            print('REJECTED_REAL', reason)
        else:
            raise ValueError('MUTATION_ESCAPED ' + reason)
    print('PASS: 12 real CPU scenarios and 12 trace negative controls')


if __name__ == '__main__':
    main(Path(sys.argv[1]))

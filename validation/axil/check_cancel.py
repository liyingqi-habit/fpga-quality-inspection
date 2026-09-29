"""Independent architectural and AXI handshake audit of real-CPU cancellation."""
import argparse
import copy
import csv
import json
from pathlib import Path

BASE = 0x10000000
OLD = 0xaabbccdd
NEW = 0x55667788
FAULT_PC = 0x80000010


def need(ok, reason):
    if not ok:
        raise ValueError(reason)


def read(path):
    return [{k: int(v) if v.isdecimal() else -1 for k, v in row.items()}
            for row in csv.DictReader(path.open())]


def check(rows, write, phase, code, delay):
    need(len(rows) > 20, 'SHORT_TRACE')
    pending = None
    due = None
    commands = []
    resets = []
    fault_retires = []
    responses = 0
    reset_window = None
    previous = None
    for r in rows:
        c = r['cycle']
        for key in ('epoch','reset','cpu_reset','busy','cancelled','cv','ready','write',
                    'av','ar','wv','wr','bv','br','qv','qr','pv','pr','rv','re','retire','store_retire'):
            need(r[key] in (0,1), 'UNKNOWN_CONTROL:'+key)
        if previous:
            need(c == previous['cycle']+1, 'TRACE_GAP')
            for valid, ready, fields in [('av','ar',['aa']), ('wv','wr',['wd','ws']),
                                          ('qv','qr',['qa']), ('bv','br',['bc']),
                                          ('pv','pr',['pd','pc'])]:
                if previous[valid] and not previous[ready]:
                    need(r[valid] == 1 and all(r[f] == previous[f] for f in fields), 'CHANNEL_UNSTABLE')
        if due:
            need(r['rv'] == 1 and r['re'] == due[0] and r['rd'] == due[1], 'COMPLETION_VALUE')
            due = None
        else:
            need(r['rv'] == 0, 'STALE_RESPONSE')
        if r['reset']:
            resets.append(c)
            need(r['cpu_reset'] and not r['ready'] and not r['retire'], 'RESET_NOT_ISOLATED')
            need(pending is not None, 'RESET_WITHOUT_TRANSACTION')
            pending['cancel'] = True
            reset_window = (pending['a'], pending['w'], pending['q'], r['bv'] or r['pv'],
                            (r['bv'] and r['br']) or (r['pv'] and r['pr']))
        if pending and pending['cancel']:
            need(r['cpu_reset'] == 1 and r['ready'] == 0 and not r['retire'], 'EARLY_RELEASE')
        if r['cv'] and r['ready']:
            need(pending is None, 'SLOT_REUSED')
            need(not r['cpu_reset'], 'COMMAND_DURING_RESET')
            command = (r['addr'], r['write'], r['data'] if r['write'] else 0)
            commands.append(command)
            need(r['cmd_pc'] == FAULT_PC if len(commands) == 1 else True, 'FIRST_PC')
            if r['write']:
                need(r['mask'] == 15, 'WORD_MASK')
            pending = dict(addr=r['addr'], data=r['data'], mask=r['mask'], write=r['write'],
                           a=False, w=False, q=False, cancel=False, complete=None)
        for v, ready, flag in [('av','ar','a'), ('wv','wr','w'), ('qv','qr','q')]:
            if r[v] and r[ready]:
                need(pending is not None and not pending[flag], 'DUPLICATE_CHANNEL')
                need(bool(pending['write']) == (flag != 'q'), 'WRONG_CHANNEL')
                if flag == 'a': need(r['aa'] == pending['addr'], 'AW_PAYLOAD')
                if flag == 'q': need(r['qa'] == pending['addr'], 'AR_PAYLOAD')
                if flag == 'w': need((r['wd'],r['ws']) == (pending['data'],pending['mask']), 'W_PAYLOAD')
                pending[flag] = True
        if pending:
            p = pending
            if p['complete'] is None and (p['a'] and p['w'] if p['write'] else p['q']):
                p['complete'] = c
            if r['bv'] or r['pv']:
                need(p['complete'] is not None and c >= p['complete']+delay+2, 'TARGET_DELAY')
        if (r['bv'] and r['br']) or (r['pv'] and r['pr']):
            need(pending is not None, 'ORPHAN_RESPONSE')
            p = pending
            need((p['write'] and r['bv'] and p['a'] and p['w']) or
                 (not p['write'] and r['pv'] and p['q']), 'RESPONSE_BEFORE_CHANNELS')
            expected_code = code if p['addr'] == BASE else 0
            need((r['bc'] if p['write'] else r['pc']) == expected_code, 'TARGET_CODE')
            expected_data = 0 if p['write'] else (0xdeadbeef if p['addr'] == BASE else 0xcafebabe)
            if not p['write']: need(r['pd'] == expected_data, 'TARGET_DATA')
            if not p['cancel']: due = (int(expected_code != 0), expected_data)
            responses += 1
            pending = None
        if r['retire'] and r['retire_pc'] == FAULT_PC:
            need(not pending and not r['cpu_reset'] and responses > 0, 'EARLY_RETIRE')
            fault_retires.append(r['epoch'])
        previous = r
    need(not due, 'TRUNCATED_COMPLETION')
    first = (BASE, write, OLD if write else 0)
    if phase == 7:
        need(commands == [first] and responses == 0 and not fault_retires, 'NEVER_ARCHITECTURE')
        need(pending is not None and pending['cancel'] and rows[-1]['cpu_reset'], 'NEVER_QUARANTINE')
        need(len(resets) == 1 and rows[-1]['cycle']-resets[0] >= 90, 'SHORT_QUARANTINE')
    else:
        need(pending is None, 'UNDRAINED')
        if phase == 0 and code:
            expected = [first, (BASE+40,1,7 if write else 5), (BASE+44,1,FAULT_PC),
                        (BASE+48,1,BASE), (BASE+36,1,0xbad)]
            need(fault_retires == [], 'FAULT_RETIRED')
        else:
            epoch = int(phase != 0)
            value = (NEW if epoch else OLD) if write else (0xcafebabe if epoch else 0xdeadbeef)
            expected = [first]
            if epoch: expected.append((BASE+16,write,NEW if write else 0))
            expected += [(BASE+32,1,value), (BASE+36,1,0x600d0000+epoch)]
            need(fault_retires == [epoch], 'RETIRE_EPOCH')
        need(commands == expected, 'ARCHITECTURAL_COMMANDS')
        need(responses == len(commands), 'MISSING_RESPONSE')
        need(len(resets) == int(phase != 0), 'RESET_COUNT')
    expected_mem = OLD if write and code == 0 else 0x11223344
    need(rows[-1]['memory'] == expected_mem, 'TARGET_MEMORY')
    if phase:
        a,w,q,valid,handshake = reset_window
        if phase == 1: need(not a and not w and not q, 'WINDOW_BEFORE_CHANNEL')
        if phase == 2: need(a and not w, 'WINDOW_AW_ONLY')
        if phase == 3: need(w and not a, 'WINDOW_W_ONLY')
        if phase in (4,7): need((a and w if write else q) and not valid, 'WINDOW_WAIT')
        if phase == 5: need(handshake, 'WINDOW_SAME_EDGE')
        if phase == 6: need(valid and not handshake, 'WINDOW_STALLED')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    total = 0
    negatives = 0
    expected_folders = {f'w{w}_p{p}_c{c}_d{d}' for w in (0,1)
                        for p in (range(8) if w else (0,1,4,5,6,7))
                        for c in (0,2,3) for d in (3,17)}
    need({p.name for p in args.output.glob('w*_p*_c*_d*')} == expected_folders, 'CASE_SET_CHANGED')
    for folder in sorted(args.output.glob('w*_p*_c*_d*')):
        w,p,c,d = [int(part[1:]) for part in folder.name.split('_')]
        rows = read(folder/'trace.csv')
        try:
            check(rows,w,p,c,d)
        except ValueError as error:
            raise ValueError(f'{folder.name}: {error}') from error
        total += 1
        if p == 4:
            for kind in ('stale','release','result'):
                bad = copy.deepcopy(rows)
                if kind == 'stale':
                    idx = next(i for i,r in enumerate(bad) if (r['bv'] and r['br']) or (r['pv'] and r['pr']))
                    bad[idx+1]['rv'] = 1
                    reason = 'STALE_RESPONSE'
                elif kind == 'release':
                    idx = next(i for i,r in enumerate(bad) if r['cancelled'])
                    bad[idx]['cpu_reset'] = 0
                    reason = 'EARLY_RELEASE'
                else:
                    idx = next(i for i,r in enumerate(bad) if r['cv'] and r['ready'] and r['addr']==BASE+32)
                    bad[idx]['data'] ^= 1
                    reason = 'W_PAYLOAD'
                try:
                    check(bad,w,p,c,d)
                except ValueError as error:
                    need(str(error)==reason, 'WRONG_NEGATIVE_REASON:'+str(error))
                else: raise ValueError('NEGATIVE_ESCAPED')
                negatives += 1
    need(total == 84, 'MISSING_CASES')
    injected = 0
    for kind, reason in [('lost_error','COMPLETION_VALUE'),('stale_response','STALE_RESPONSE'),('early_release','EARLY_RELEASE')]:
        for w in (0,1):
            rows = read(args.output/f'negative_{kind}_w{w}'/'trace.csv')
            try:
                check(rows,w,0 if kind=='lost_error' else 4,2 if kind=='lost_error' else 0,17)
            except ValueError as error:
                need(str(error)==reason, 'WRONG_RTL_NEGATIVE_REASON:'+str(error))
            else: raise ValueError('RTL_NEGATIVE_ESCAPED')
            injected += 1
    print(f'PASS: {total} real CPU AXIL cancel/control traces; {negatives} negative audits; {injected} RTL faults rejected')
    (args.output/'audit.json').write_text(json.dumps(dict(cases=total,negative_audits=negatives,rtl_faults=injected,status='PASS'),indent=2)+'\n')


if __name__ == '__main__': main()

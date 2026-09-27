"""Independent two-level trap and reset oracle. No internal CPU trap probes."""
import copy
import itertools
import json
import sys
from pathlib import Path
from check_competition import rows, require

GUARDS = [0xdeadbeef, 0x2468ace0, 0x13579bdf]


def symbols(path):
    return {v[2]: int(v[0], 16) for line in path.read_text().splitlines()
            if len(v := line.split()) == 3}


def audit_bus(trace):
    pending = None
    for r in trace:
        if r['cv'] and r['ready']:
            require(pending is None, 'OVERLAPPING_COMMAND')
            pending = dict(cancelled=False, completed=False)
        if r['reset'] and pending is not None:
            pending['cancelled'] = True
        if r['b_fire'] or r['r_fire']:
            require(pending is not None and not pending['completed'], 'UNMATCHED_BUS_RESPONSE')
            if pending['cancelled']:
                pending = None
            else:
                pending['completed'] = True
        if r['rv']:
            require(pending is not None and pending['completed'] and not pending['cancelled'], 'UNMATCHED_CPU_RESPONSE')
            require(not r['error'], 'UNEXPECTED_BUS_ERROR')
            pending = None
    require(pending is None, 'UNFINISHED_COMMAND')


def normal(rec, tr, sym, outer, inner, nested):
    data = [r['data'] for r in rec]
    restore = 15 if nested else 7
    require(len(data) >= restore + 4, 'RESTORE_MISSING')
    expected_pc = sym['resume'] if outer == 0 else data[2]
    require(data[restore + 1] == expected_pc, 'RESTORED_PC')
    require(len(data) == 24, 'NORMAL_RECORD_COUNT')
    require([r['addr'] for r in rec] == list(range(0x80004000, 0x80004060, 4)), 'NORMAL_RECORD_ADDRESS')
    require(data[0] == 10 and data[1] == (11 if outer == 0 else 0x80000000 | outer), 'OUTER_CAUSE')
    if outer == 0:
        require(data[2] == sym['fault_pc'], 'OUTER_PC')
    else:
        require(sym['wait_outer'] <= data[2] < sym['resume_end'] and data[2] % 4 == 0, 'OUTER_PC')
    require(data[3] == 0x1880, 'OUTER_STATUS')
    require(data[4:7] == GUARDS, 'OUTER_GUARDS')
    idx = 7 if nested else 11
    require(data[idx:idx+2] == [20, 0x80000000 | inner], 'INNER_CAUSE')
    lo, hi = (sym['outer_wait'], sym['outer_wait_end']) if nested else (sym['wait_outer'], sym['resume_end'])
    require(lo <= data[idx+2] < hi and data[idx+2] % 4 == 0, 'INNER_PC')
    require(data[idx+3] == 0x1880, 'INNER_STATUS')
    require(data[idx+4] == (1 if nested else 3), 'INNER_DEPTH')
    require(data[idx+5:idx+8] == GUARDS, 'INNER_GUARDS')
    require(data[restore] == 30 and data[restore+2:restore+4] == [0x1880, 2 if nested else 1], 'RESTORED_STATUS_DEPTH')
    require(data[-5:] == [40, 2] + GUARDS, 'NORMAL_RETURN')
    require(not any(r['reset'] for r in tr), 'UNEXPECTED_RESET')
    require(sum(r['retire'] and r['retire_pc'] == sym['handler'] for r in tr) == 2, 'NORMAL_HANDLER_COUNT')
    require(sum(r['retire'] and r['retire_pc'] == sym['outer_mret'] for r in tr) == 1, 'OUTER_RETURN_COUNT')
    if outer == 0:
        require(not any(r['retire'] and r['retire_pc'] == sym['fault_pc'] for r in tr), 'ECALL_RETIRED')
    require(tr[-1]['pending'] == 0, 'PENDING_NOT_CLEARED')
    commits = [r for r in tr if r['commit'] and r['commit_addr'] == 0x10000044]
    require(len(commits) == 1 and commits[0]['commit_data'] == GUARDS[0], 'CHECKPOINT_EFFECT')
    done = [r for r in tr if r['commit'] and r['commit_addr'] == 0x10000024]
    require(len(done) == 1 and done[0]['commit_data'] == 1, 'NORMAL_DONE')
    audit_bus(tr)


def reset_case(rec, tr, sym, recovery, phase, hold, baseline):
    resets = [r for r in tr if r['reset']]
    require(len(resets) == 2, 'RESET_PULSE')
    first = resets[0]
    before = [r for r in tr if r['cycle'] < first['cycle']]
    after = [r for r in tr if r['cycle'] >= first['cycle']]
    require(before and before[-1]['epoch'] == 0 and all(r['epoch'] == 1 for r in after), 'EPOCH')
    if phase in (1, 3, 4):
        pc = sym[{1: 'outer_entry', 3: 'inner_entry', 4: 'outer_return_prepare'}[phase]]
        require(before[-1]['retire'] and before[-1]['retire_pc'] == pc, 'RESET_PC_WINDOW')
    elif phase == 2:
        require(before[-1]['cv'] and before[-1]['ready'] and before[-1]['addr'] == 0x10000044, 'RESET_ACCEPT_WINDOW')
    else:
        require(first['b_fire'] and first['busy'] and before[-1]['busy'], 'RESET_RESPONSE_WINDOW')
    expected_pending = before[-1]['pending'] if hold else 0
    require(first['reset_pending'] == expected_pending and first['pending'] == expected_pending, 'RESET_PENDING_POLICY')
    active = [r for r in after if r['cpu_reset']]
    require(bool(active) and all(not r['rv'] and not r['retire'] and not r['ready'] for r in active), 'RESET_ISOLATION')
    if phase in (2, 5):
        require(first['busy'] == 1, 'NO_INFLIGHT_WRITE')
        drains = [r for r in after if r['b_fire']]
        require(bool(drains), 'NO_DRAIN')
        drain_cycle = drains[0]['cycle']
        require(all(r['cpu_reset'] and not r['rv'] for r in after if r['cycle'] <= drain_cycle), 'DRAIN_ISOLATION')
        # Boot ROMs reuse addresses: recovery mret may have the old store's PC.
        # Epoch 1 is separately checked for reset isolation and restart at _start.
        require(not any(r['epoch'] == 0 and r['retire'] and r['retire_pc'] == sym['checkpoint'] for r in tr), 'CANCELLED_STORE_RETIRED')
        effects = [r for r in tr if r['commit'] and r['commit_addr'] == 0x10000044]
        require(len(effects) == 1 and effects[0]['commit_data'] == GUARDS[0], 'ACCEPTED_EFFECT_LOST_OR_DUPLICATED')
    first_retire = next((r for r in after if r['retire']), None)
    require(first_retire is not None and first_retire['retire_pc'] == recovery['_start'], 'RESTART_PC')
    # An accepted pre-reset record may commit after reset. Compare only to a separately verified baseline prefix.
    old = [r for r in rec if r['addr'] < 0x80004800]
    require([(r['addr'], r['data']) for r in old] == [(r['addr'], r['data']) for r in baseline[:len(old)]], 'OLD_RECORD_PREFIX')
    new = [r for r in rec if r['addr'] >= 0x80004800]
    count = 9 if expected_pending else 5
    require(len(new) == count and all(r['epoch'] == 1 for r in new), 'RECOVERY_COUNT')
    require([r['addr'] for r in new] == list(range(0x80004800, 0x80004800 + count * 4, 4)), 'RECOVERY_ADDRESS')
    data = [r['data'] for r in new]
    require(data[:3] == [0, 0, expected_pending], 'RESET_CSR_STATE')
    if expected_pending:
        require(expected_pending in (8, 128, 2048), 'MULTIPLE_PENDING_UNEXPECTED')
        bit = expected_pending.bit_length() - 1
        require(data[3] == 0x80000000 | bit, 'RECOVERY_CAUSE')
        require(recovery['enabled'] <= data[4] < recovery['recovery_end'] and data[4] % 4 == 0, 'RECOVERY_PC')
        require(data[5:7] == [0, 0x1880], 'RECOVERY_TRAP_STATE')
    require(data[-2:] == [int(bool(expected_pending)), 0x89abcdef], 'RECOVERY_RETURN')
    require(sum(r['retire'] and r['retire_pc'] == recovery['handler'] for r in after) == int(bool(expected_pending)), 'RECOVERY_HANDLER_COUNT')
    done = [r for r in tr if r['commit'] and r['commit_addr'] == 0x10000024]
    require(len(done) == 1 and done[0]['commit_data'] == 2 and done[0]['epoch'] == 1, 'RECOVERY_DONE')
    require(tr[-1]['pending'] == 0, 'RECOVERY_PENDING')
    audit_bus(tr)


def main():
    out = Path(sys.argv[1]); recovery = symbols(out / 'recovery/symbols.txt')
    checked = 0; reset_count = 0; held_nonzero = 0; sample = None; reset_sample = None
    for o, i, n, d in itertools.product((0, 3, 7, 11), (3, 7, 11), (0, 1), (2, 13)):
        if o == i: continue
        sym = symbols(out / f'fw_o{o}_i{i}_n{n}/symbols.txt')
        base = out / f'o{o}_i{i}_n{n}_p0_h0_d{d}'
        rec, tr = rows(base / 'records.csv'), rows(base / 'trace.csv')
        try: normal(rec, tr, sym, o, i, n)
        except ValueError as error: raise ValueError(f'{base.name}: {error}') from error
        checked += 1
        if o == 0 and i == 3 and n == 1 and d == 2: sample = rec, tr, sym, o, i, n
        for p, h in itertools.product(range(1, 6), (0, 1)):
            if p == 3 and n == 0: continue
            folder = out / f'o{o}_i{i}_n{n}_p{p}_h{h}_d{d}'
            rr, tt = rows(folder / 'records.csv'), rows(folder / 'trace.csv')
            try: reset_case(rr, tt, sym, recovery, p, h, rec)
            except ValueError as error: raise ValueError(f'{folder.name}: {error}') from error
            reset_count += 1
            held_nonzero += int(any(r['reset_pending'] for r in tt))
            if o == 0 and i == 3 and n == 1 and d == 2 and p == 2 and h == 1:
                reset_sample = rr, tt, sym, recovery, p, h, rec
    rec, tr, sym, o, i, n = sample
    negatives = 0
    for index, reason in [(1,'OUTER_CAUSE'),(2,'OUTER_PC'),(3,'OUTER_STATUS'),(4,'OUTER_GUARDS'),
                          (8,'INNER_CAUSE'),(9,'INNER_PC'),(10,'INNER_STATUS'),(11,'INNER_DEPTH'),
                          (12,'INNER_GUARDS'),(16,'RESTORED_PC'),(17,'RESTORED_STATUS_DEPTH'),(20,'NORMAL_RETURN')]:
        bad = copy.deepcopy(rec);bad[index]['data'] ^= 1
        try: normal(bad,tr,sym,o,i,n)
        except ValueError as error: require(str(error)==reason,'NEGATIVE_REASON:'+str(error));negatives+=1
        else: raise ValueError('NEGATIVE_ESCAPED:'+reason)
    rr,tt,sy,rc,p,h,base = reset_sample
    for field, reason in [('rv','RESET_ISOLATION'),('retire','RESET_ISOLATION'),('ready','RESET_ISOLATION')]:
        bad=copy.deepcopy(tt);next(r for r in bad if r['cpu_reset'])[field]=1
        try: reset_case(rr,bad,sy,rc,p,h,base)
        except ValueError as error: require(str(error)==reason,'NEGATIVE_REASON:'+str(error));negatives+=1
        else: raise ValueError('NEGATIVE_ESCAPED:'+reason)
    for index, reason in [(0,'RESET_CSR_STATE'),(1,'RESET_CSR_STATE'),(2,'RESET_CSR_STATE'),
                          (3,'RECOVERY_CAUSE'),(4,'RECOVERY_PC'),(5,'RECOVERY_TRAP_STATE'),(-1,'RECOVERY_RETURN')]:
        bad=copy.deepcopy(rr);new=[r for r in bad if r['addr']>=0x80004800];new[index]['data']^=1
        try: reset_case(bad,tt,sy,rc,p,h,base)
        except ValueError as error: require(str(error)==reason,'NEGATIVE_REASON:'+str(error));negatives+=1
        else: raise ValueError('NEGATIVE_ESCAPED:'+reason)
    controls=[]
    bad=copy.deepcopy(tt)
    next(r for r in bad if r['epoch']==0 and r['cv'] and r['ready'] and r['addr']==0x10000044).update(retire=1,retire_pc=sy['checkpoint'])
    controls.append((bad,'CANCELLED_STORE_RETIRED'))
    bad=copy.deepcopy(tt)
    next(r for r in bad if r['commit'] and r['commit_addr']==0x10000044)['commit']=0
    controls.append((bad,'ACCEPTED_EFFECT_LOST_OR_DUPLICATED'))
    bad=copy.deepcopy(tt)
    next(r for r in bad if r['epoch']==1 and r['retire'])['retire_pc']+=4
    controls.append((bad,'RESTART_PC'))
    for bad,reason in controls:
        try: reset_case(rr,bad,sy,rc,p,h,base)
        except ValueError as error: require(str(error)==reason,'NEGATIVE_REASON:'+str(error));negatives+=1
        else: raise ValueError('NEGATIVE_ESCAPED:'+reason)
    bad=rows(out/'negative_restore/records.csv')
    require(len(bad)>16 and bad[16]['data']==0,'RESTORE_MUTANT_NOT_EXERCISED')
    try: normal(bad,[],sym,o,i,n)
    except ValueError as error: require(str(error)=='RESTORED_PC','RTL_NEGATIVE_REASON')
    else: raise ValueError('RESTORE_MUTANT_ESCAPED')
    bad_trace=rows(out/'negative_stale/trace.csv')
    require(any(r['reset'] for r in bad_trace),'STALE_MUTANT_NOT_RESET')
    try: audit_bus(bad_trace)
    except ValueError as error: require(str(error)=='UNMATCHED_CPU_RESPONSE','STALE_MUTANT_REASON:'+str(error))
    else: raise ValueError('STALE_MUTANT_ESCAPED')
    result=dict(status='PASS',normal_configurations=checked,reset_configurations=reset_count,
                retained_pending_nonzero_cases=held_nonzero,checker_mutations_rejected=negatives,
                actual_bad_firmware_restore_rejected=1,
                actual_stale_bridge_response_rejected=1,
                scope='two levels; reserved-register software context; CPU-local reset with target retained; not board reset')
    (out/'audit.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))


if __name__ == '__main__':main()

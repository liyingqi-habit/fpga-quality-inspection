"""Reuse protocol audit with explicit changed firmware PC and error schedule."""
import copy
from pathlib import Path
import sys
from check_real import check, read

errors = {3: 2, 4: 3, 6: 2, 7: 3, 8: 2, 9: 2}
root = Path(sys.argv[1])
for branch in range(3):
    traces = [read(root / f'branch{branch}/case{i}/trace.csv') for i in range(12)]
    for i, rows in enumerate(traces):
        check(rows, i, young_pc=0x8000001c, errors=errors)
        assert not any(r['cmd_valid'] and r['cmd_addr'] == 0 for r in rows), 'wrong path'
    for case, field, change, reason in (
        (9, 'reset', {'retire': 1, 'retire_pc': 0x80000010}, 'STALE_RETIRE'),
        (8, 'cancelled', {'busy': 0}, 'QUARANTINE_LOST'),
        (3, 'trap', {'cause': 5}, 'TRAP_CONTEXT')):
        rows = copy.deepcopy(traces[case])
        next(r for r in rows if r[field]).update(change)
        try:
            check(rows, case, young_pc=0x8000001c, errors=errors)
        except ValueError as error:
            assert str(error) == reason, str(error)
        else:
            raise AssertionError('negative escaped')
print('PASS: 36 branch/error/reset traces and 9 negative controls')
